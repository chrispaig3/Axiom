use crate::{
    IrBlock, IrConst, IrFunction, IrInst, IrModule, IrStruct, IrValue, TypeId, MATCH_FAIL_SYMBOL,
};
use axiom_ast::ast::*;
use axiom_ast::span::Ident;
use axiom_sema::TypeChecker;
use std::collections::{HashMap, HashSet};

pub struct IrGen {
    module: IrModule,
    local_counter: usize,
    block_counter: usize,
    lambda_counter: usize,
    /// Distinguishes stack slots that share a source-level name. See
    /// [`IrGen::new_alloca`].
    alloca_counter: usize,
    current_block: Option<String>,
    /// Top-level functions declared with no parameters.
    ///
    /// A bare `foo` where `foo` is nullary has to lower to a *call*,
    /// not to a variable read: there is no local named `foo`, so
    /// reading one produced LLVM referencing an undefined value and
    /// failed at `llc` rather than at a diagnostic. Nullary functions
    /// are how Axiom source expresses a named constant (there is no
    /// `const` declaration), so the standard library's syscall-number
    /// and flag tables depend on this.
    nullary_fns: HashSet<String>,
}

/// Look up a data constructor by name across every `data` type the type
/// checker collected, returning:
///
/// * a globally-unique integer tag - unique across every constructor in
///   the program, not just within one `data` type, so two different
///   `data` types' constructors can never compare equal by accident
///   during pattern matching. The tag is a running count over
///   `(data type, constructor)` pairs in declaration order, which is
///   unique unconditionally. It was previously `data_type_index * 100 +
///   constructor_index`, which aliases as soon as any one `data` type
///   declares 100 constructors: constructor 100 of type *n* and
///   constructor 0 of type *n+1* both get tag `100n + 100`, and a
///   `match` on one would then take the other's arm. 100 constructors is
///   not an absurd number for a self-hosted compiler's token or AST
///   node type, which is exactly the program this compiler has to build;
/// * its arity, decomposed from the constructor's curried arrow type
///   (`Field1 -> Field2 -> ... -> TheType`; zero `TArr`s means a nullary
///   constructor).
///
/// Both constructor *construction* (`EVar`/`EApp`, see
/// [`IrGen::gen_construct`]) and constructor *matching* (`EMatch`) call
/// this, so a value built with one tag is always compared against that
/// exact same tag - there is exactly one place in the generator that
/// decides what a constructor's tag is.
fn find_constructor(type_checker: &TypeChecker, name: &str) -> Option<(i64, usize)> {
    let mut tag: i64 = 0;
    for dt in type_checker.data_types.iter() {
        for con in dt.constructors.iter() {
            if con.name == name {
                return Some((tag, constructor_arity(&con.ty)));
            }
            tag += 1;
        }
    }
    None
}

/// Byte offset of a constructor block's first field.
///
/// A `data` value is `[tag, field0, field1, ...]` with one 8-byte word
/// each, so fields start one word in. Naming it stops the two pattern
/// paths from disagreeing: the outer scrutinee's fields were read from 8
/// while a *nested* constructor's were read from 1, which is not even
/// word-aligned - every nested field read was 7 bytes short and
/// straddled two fields.
const CON_FIELD_BASE: i64 = 8;

fn constructor_arity(ty: &TypeId) -> usize {
    let mut n = 0;
    let mut current = ty;
    while let TypeId::TArr(_, rest) = current {
        n += 1;
        current = rest;
    }
    n
}

impl Default for IrGen {
    fn default() -> Self {
        Self::new()
    }
}

impl IrGen {
    pub fn new() -> Self {
        Self {
            module: IrModule::new(),
            local_counter: 0,
            block_counter: 0,
            lambda_counter: 0,
            alloca_counter: 0,
            current_block: None,
            nullary_fns: HashSet::new(),
        }
    }

    pub fn generate(&mut self, ast_module: &Module, type_checker: &mut TypeChecker) -> IrModule {
        // Collected up front, before any body is lowered, so a
        // nullary function can be referenced by a function defined
        // above it (declaration order is not significant in Axiom -
        // `axiom-sema`'s checker is two-pass for the same reason).
        self.nullary_fns = ast_module
            .decls
            .iter()
            .filter_map(|d| match d {
                Decl::DFn { name, params, .. } if params.is_empty() => Some(name.name.clone()),
                _ => None,
            })
            .collect();

        for decl in &ast_module.decls {
            match decl {
                Decl::DStruct {
                    name, fields, repr, ..
                } => {
                    let packed = matches!(repr, Some(TypeRepr::Packed));
                    let align = if let Some(TypeRepr::Align(n)) = repr {
                        Some(*n)
                    } else {
                        None
                    };

                    let ir_fields: Vec<(String, TypeId)> = fields
                        .iter()
                        .map(|f| (f.name.name.clone(), self.type_to_id(&f.ty)))
                        .collect();

                    self.module.structs.push(IrStruct {
                        name: name.name.clone(),
                        fields: ir_fields,
                        packed,
                        align,
                    });
                }
                Decl::DFn {
                    name, params, body, ..
                } => {
                    let func = self.gen_function(name, params, body, type_checker);
                    self.module.functions.push(func);
                }
                Decl::DForeign { name, ty, .. } => {
                    let mut params = Vec::new();
                    let mut current = self.type_to_id(ty);
                    while let TypeId::TArr(param, rest) = current {
                        params.push(*param);
                        current = *rest;
                    }
                    self.module
                        .extern_funcs
                        .push((name.name.clone(), params, current));
                }
                Decl::DSig { name, ty, .. } => {
                    let _ = (name, ty);
                }
                _ => {}
            }
        }

        std::mem::take(&mut self.module)
    }

    fn gen_function(
        &mut self,
        name: &Ident,
        params: &[Pattern],
        body: &Expr,
        type_checker: &mut TypeChecker,
    ) -> IrFunction {
        let params: Vec<(String, TypeId)> = params
            .iter()
            .filter_map(|p| {
                if let Pattern::PVar(ident) = p {
                    Some((ident.name.clone(), TypeId::TCon("I64".to_string(), vec![])))
                } else {
                    None
                }
            })
            .collect();

        let return_type = TypeId::TCon("I64".to_string(), vec![]);

        let mut func = IrFunction {
            name: name.name.clone(),
            params: params.clone(),
            return_type,
            blocks: Vec::new(),
            locals: Vec::new(),
        };

        let entry_label = self.new_block_label();
        self.current_block = Some(entry_label.clone());

        func.blocks.push(IrBlock {
            label: entry_label.clone(),
            insts: Vec::new(),
        });

        let mut alloca_map: HashMap<String, String> = HashMap::new();

        for (pname, pty) in &params {
            let alloca_name = self.new_alloca(pname);
            func.locals.push((pname.clone(), pty.clone()));
            self.emit_to_func(
                &mut func,
                IrInst::Alloca {
                    dest: IrValue::Local(alloca_name.clone()),
                    ty: pty.clone(),
                },
            );
            self.emit_to_func(
                &mut func,
                IrInst::Store {
                    ptr: IrValue::Local(alloca_name.clone()),
                    value: IrValue::Local(pname.clone()),
                },
            );
            alloca_map.insert(pname.clone(), alloca_name);
        }

        let body_val =
            self.gen_expr_to_func_with_allocas(&mut func, body, &mut alloca_map, type_checker);

        self.emit_to_func(
            &mut func,
            IrInst::Ret {
                value: Some(body_val),
            },
        );

        func
    }

    /// Build a heap-boxed constructor value: `HeapAlloc` a block of `(1 +
    /// args.len()) * 8` bytes, `StoreOffset` the tag into word 0, then
    /// `StoreOffset` each argument into words `1..`. Every `data`
    /// constructor - nullary or not - goes through this one path, so
    /// there is exactly one runtime representation for a value of a given
    /// `data` type regardless of which constructor produced it (see
    /// [`find_constructor`] and the module-level `HeapAlloc` docs in
    /// `axiom-ir`'s `lib.rs`).
    fn gen_construct(&mut self, func: &mut IrFunction, tag: i64, args: Vec<IrValue>) -> IrValue {
        let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
        let size = ((1 + args.len()) * 8) as i64;
        let ptr_local = self.new_local();

        self.emit_to_func(
            func,
            IrInst::HeapAlloc {
                dest: IrValue::Local(ptr_local.clone()),
                size: IrValue::Const(IrConst::Int(size, i64_ty.clone())),
            },
        );
        self.emit_to_func(
            func,
            IrInst::StoreOffset {
                ptr: IrValue::Local(ptr_local.clone()),
                offset: 0,
                value: IrValue::Const(IrConst::Int(tag, i64_ty.clone())),
            },
        );
        for (i, arg) in args.into_iter().enumerate() {
            self.emit_to_func(
                func,
                IrInst::StoreOffset {
                    ptr: IrValue::Local(ptr_local.clone()),
                    offset: ((1 + i) * 8) as i64,
                    value: arg,
                },
            );
        }

        IrValue::Local(ptr_local)
    }

    /// Generate IR to check sub-patterns of a `PCon` arm or
    /// elements of a `PTuple`/`PList` arm against the fields
    /// of a boxed constructor or tuple/list value.
    ///
    /// `target_val` is the pointer (as an `i64` local) to the
    /// boxed block whose fields should be extracted and compared.
    /// `pats` are the sub-patterns to match against the fields.
    /// `field_offset` is the byte offset of the first field
    /// within `target_val` (`1 * 8` for `PCon` arms, `0` for
    /// tuples/lists). Each subsequent sub-pattern uses the
    /// next offset (`field_offset + i * 8`).
    ///
    /// Each sub-pattern that requires a runtime comparison
    /// (`PLit`, nested `PCon`, nested `PTuple`/`PList`) emits
    /// a check block that either falls through to the next
    /// sub-pattern on match or branches to `next_check` on
    /// failure. `PVar` bindings and `PWildcard` skips are
    /// emitted inline without branching. `PCon` sub-patterns
    /// trigger recursive calls that handle the inner
    /// constructor's own sub-patterns.
    ///
    /// Variable bindings from `PVar` sub-patterns are added
    /// to `arm_map`.
    // One parameter per piece of the match being compiled (target
    // value, pattern, success/failure labels, field offset, ...);
    // grouping them into a struct would add a type whose only purpose
    // is to be destructured immediately at the single call site.
    #[allow(clippy::too_many_arguments)]
    fn gen_sub_pattern_checks(
        &mut self,
        func: &mut IrFunction,
        target_val: IrValue,
        pats: &[Pattern],
        type_checker: &TypeChecker,
        next_check: String,
        arm_map: &mut HashMap<String, String>,
        field_offset: i64,
    ) {
        let i64_ty = TypeId::TCon("I64".to_string(), vec![]);

        for (field_idx, arg_pat) in pats.iter().enumerate() {
            let offset = field_offset + (field_idx as i64) * 8;
            let field_local = self.new_local();
            self.emit_to_func(
                func,
                IrInst::LoadOffset {
                    dest: IrValue::Local(field_local.clone()),
                    ptr: target_val.clone(),
                    offset,
                },
            );

            match arg_pat {
                Pattern::PVar(ident) => {
                    let arg_alloca = self.new_alloca(&ident.name);
                    func.locals.push((ident.name.clone(), i64_ty.clone()));
                    self.emit_to_func(
                        func,
                        IrInst::Alloca {
                            dest: IrValue::Local(arg_alloca.clone()),
                            ty: i64_ty.clone(),
                        },
                    );
                    self.emit_to_func(
                        func,
                        IrInst::Store {
                            ptr: IrValue::Local(arg_alloca.clone()),
                            value: IrValue::Local(field_local),
                        },
                    );
                    arm_map.insert(ident.name.clone(), arg_alloca);
                }
                Pattern::PWildcard => {}
                Pattern::PLit(lit) => {
                    let lit_val = self.gen_literal(lit);
                    let cmp_dest = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::Eq {
                            dest: IrValue::Local(cmp_dest.clone()),
                            lhs: IrValue::Local(field_local.clone()),
                            rhs: lit_val,
                        },
                    );
                    let cont = self.new_block_label();
                    self.emit_to_func(
                        func,
                        IrInst::CondBr {
                            cond: IrValue::Local(cmp_dest),
                            then_target: cont.clone(),
                            else_target: next_check.clone(),
                        },
                    );
                    func.blocks.push(IrBlock {
                        label: cont.clone(),
                        insts: Vec::new(),
                    });
                    self.current_block = Some(cont);
                }
                Pattern::PCon(ident, nested_args) => {
                    match find_constructor(type_checker, &ident.name) {
                        Some((tag, _arity)) => {
                            // `field_local` is the *address* of the nested
                            // constructor block, not its tag. Comparing it
                            // against `tag` directly - as this did - is a
                            // pointer/tag confusion that is false for every
                            // reachable heap address, so a nested
                            // constructor pattern could only ever fail to
                            // match. The tag has to be loaded out of word 0
                            // first, exactly as the outer scrutinee's is.
                            let nested_tag = self.new_local();
                            self.emit_to_func(
                                func,
                                IrInst::LoadOffset {
                                    dest: IrValue::Local(nested_tag.clone()),
                                    ptr: IrValue::Local(field_local.clone()),
                                    offset: 0,
                                },
                            );
                            let cmp_dest = self.new_local();
                            self.emit_to_func(
                                func,
                                IrInst::Eq {
                                    dest: IrValue::Local(cmp_dest.clone()),
                                    lhs: IrValue::Local(nested_tag),
                                    rhs: IrValue::Const(IrConst::Int(tag, i64_ty.clone())),
                                },
                            );
                            let cont = self.new_block_label();
                            self.emit_to_func(
                                func,
                                IrInst::CondBr {
                                    cond: IrValue::Local(cmp_dest),
                                    then_target: cont.clone(),
                                    else_target: next_check.clone(),
                                },
                            );
                            func.blocks.push(IrBlock {
                                label: cont.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(cont);
                            self.gen_sub_pattern_checks(
                                func,
                                IrValue::Local(field_local),
                                nested_args,
                                type_checker,
                                next_check.clone(),
                                arm_map,
                                CON_FIELD_BASE,
                            );
                        }
                        None => {
                            // Undefined constructor: skip comparison
                            // (sema already reported the error).
                            self.gen_sub_pattern_checks(
                                func,
                                IrValue::Local(field_local),
                                nested_args,
                                type_checker,
                                next_check.clone(),
                                arm_map,
                                CON_FIELD_BASE,
                            );
                        }
                    }
                }
                Pattern::PTuple(pats) | Pattern::PList(pats) => {
                    self.gen_sub_pattern_checks(
                        func,
                        IrValue::Local(field_local),
                        pats,
                        type_checker,
                        next_check.clone(),
                        arm_map,
                        0,
                    );
                }
            }
        }
    }

    /// Compile a lambda expression as a named IR function in the
    /// module so it can be passed as a first-class value or called
    /// directly. Parameters are always `I64`; non-`PVar` patterns
    /// are not yet supported for lambda parameters. Free variables
    /// captured from the enclosing scope are not yet supported
    /// (a known limitation).
    /// Lower a call to one of Axiom's freestanding primitives (see
    /// `axiom_sema::PRIMITIVES`) to the IR instruction that
    /// implements it, returning `None` if `name` is not a primitive.
    ///
    /// An arity mismatch also returns `None` rather than emitting
    /// something wrong: semantic analysis has already reported the
    /// mismatch against the primitive's declared type, so falling
    /// through to the generic call path keeps the "one diagnostic,
    /// no invalid IR" contract instead of inventing a second failure
    /// mode further down the pipeline.
    fn gen_primitive(
        &mut self,
        func: &mut IrFunction,
        name: &str,
        args: &[IrValue],
        dest: &str,
    ) -> Option<IrValue> {
        let dest_val = IrValue::Local(dest.to_string());
        let inst = match (name, args.len()) {
            // `(__syscallN num a1 .. aN)`: the first argument is
            // always the syscall number.
            (
                "__syscall0" | "__syscall1" | "__syscall2" | "__syscall3" | "__syscall4"
                | "__syscall5" | "__syscall6",
                n,
            ) if n >= 1 => {
                let expected = name
                    .strip_prefix("__syscall")
                    .and_then(|d| d.parse::<usize>().ok())
                    .map(|d| d + 1)?;
                if n != expected {
                    return None;
                }
                IrInst::Syscall {
                    dest: dest_val.clone(),
                    num: args[0].clone(),
                    args: args[1..].to_vec(),
                }
            }
            ("__load8", 2) => IrInst::LoadIdx {
                dest: dest_val.clone(),
                ptr: args[0].clone(),
                index: args[1].clone(),
            },
            ("__store8", 3) => IrInst::StoreIdx {
                ptr: args[0].clone(),
                index: args[1].clone(),
                value: args[2].clone(),
            },
            ("__load64", 2) => IrInst::LoadWordIdx {
                dest: dest_val.clone(),
                ptr: args[0].clone(),
                index: args[1].clone(),
            },
            ("__store64", 3) => IrInst::StoreWordIdx {
                ptr: args[0].clone(),
                index: args[1].clone(),
                value: args[2].clone(),
            },
            ("__alloc", 1) => IrInst::HeapAlloc {
                dest: dest_val.clone(),
                size: args[0].clone(),
            },
            ("__addr", 1) => IrInst::AddrOf {
                dest: dest_val.clone(),
                value: args[0].clone(),
            },
            _ => return None,
        };
        // The store-shaped primitives have no result; they still
        // evaluate to something, and `0` keeps them usable in
        // sequencing position (`{ (__store8 p i c) ... }`) exactly
        // like their `Int`-returning declared type says.
        let is_store = matches!(inst, IrInst::StoreIdx { .. } | IrInst::StoreWordIdx { .. });
        self.emit_to_func(func, inst);
        if is_store {
            Some(IrValue::Const(IrConst::Int(
                0,
                TypeId::TCon("I64".to_string(), vec![]),
            )))
        } else {
            Some(dest_val)
        }
    }

    fn gen_lambda(
        &mut self,
        params: &[Pattern],
        body: &Expr,
        type_checker: &mut TypeChecker,
    ) -> IrValue {
        self.lambda_counter += 1;
        let lambda_name = format!("_lambda_{}", self.lambda_counter);

        let lambda_params: Vec<(String, TypeId)> = params
            .iter()
            .filter_map(|p| {
                if let Pattern::PVar(ident) = p {
                    Some((ident.name.clone(), TypeId::TCon("I64".to_string(), vec![])))
                } else {
                    None
                }
            })
            .collect();

        let lambda_return = TypeId::TCon("I64".to_string(), vec![]);

        let mut lambda_func = IrFunction {
            name: lambda_name.clone(),
            params: lambda_params.clone(),
            return_type: lambda_return,
            blocks: Vec::new(),
            locals: Vec::new(),
        };

        // Lowering the lambda body repoints the emission cursor at the
        // lambda's own blocks. The enclosing function's cursor must be
        // put back before returning: `emit_to_func` resolves the cursor
        // against the function it is handed, so leaving it pointing into
        // the lambda made every later instruction of the *enclosing*
        // function unemittable.
        let saved_block = self.current_block.take();

        let entry_label = self.new_block_label();
        self.current_block = Some(entry_label.clone());
        lambda_func.blocks.push(IrBlock {
            label: entry_label.clone(),
            insts: Vec::new(),
        });

        let mut lambda_alloca_map: HashMap<String, String> = HashMap::new();
        for (pname, pty) in &lambda_params {
            let alloca_name = self.new_alloca(pname);
            lambda_func.locals.push((pname.clone(), pty.clone()));
            self.emit_to_func(
                &mut lambda_func,
                IrInst::Alloca {
                    dest: IrValue::Local(alloca_name.clone()),
                    ty: pty.clone(),
                },
            );
            self.emit_to_func(
                &mut lambda_func,
                IrInst::Store {
                    ptr: IrValue::Local(alloca_name.clone()),
                    value: IrValue::Local(pname.clone()),
                },
            );
            lambda_alloca_map.insert(pname.clone(), alloca_name);
        }

        let body_val = self.gen_expr_to_func_with_allocas(
            &mut lambda_func,
            body,
            &mut lambda_alloca_map,
            type_checker,
        );
        self.emit_to_func(
            &mut lambda_func,
            IrInst::Ret {
                value: Some(body_val),
            },
        );

        self.module.functions.push(lambda_func);
        self.current_block = saved_block;

        IrValue::Global(lambda_name)
    }

    fn gen_expr_to_func_with_allocas(
        &mut self,
        func: &mut IrFunction,
        expr: &Expr,
        alloca_map: &mut HashMap<String, String>,
        type_checker: &mut TypeChecker,
    ) -> IrValue {
        match expr {
            Expr::ELit(lit, _) => self.gen_literal(lit),
            Expr::EVar(ident) => {
                // A *bare* reference to a nullary constructor (`Nothing`,
                // `Nil`, ...) constructs its (fieldless) boxed value
                // directly. A non-nullary constructor referenced bare
                // (not applied to any arguments) falls through to the
                // ordinary variable-lookup path below, same as before -
                // using a data constructor as a first-class function
                // value isn't supported by this generator either way, and
                // this at least doesn't regress that pre-existing gap.
                if let Some((tag, arity)) = find_constructor(type_checker, &ident.name) {
                    if arity == 0 {
                        return self.gen_construct(func, tag, Vec::new());
                    }
                }
                if let Some(alloca_name) = alloca_map.get(&ident.name) {
                    let dest = self.new_local();
                    let _ty = func
                        .locals
                        .iter()
                        .find(|(n, _)| n == &ident.name)
                        .map(|(_, t)| t.clone())
                        .unwrap_or(TypeId::TCon("I64".to_string(), vec![]));
                    self.emit_to_func(
                        func,
                        IrInst::Load {
                            dest: IrValue::Local(dest.clone()),
                            ptr: IrValue::Local(alloca_name.clone()),
                        },
                    );
                    IrValue::Local(dest)
                } else if self.nullary_fns.contains(&ident.name) {
                    let dest = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::Call {
                            dest: IrValue::Local(dest.clone()),
                            func: ident.name.clone(),
                            args: Vec::new(),
                        },
                    );
                    IrValue::Local(dest)
                } else {
                    IrValue::Local(ident.name.clone())
                }
            }
            Expr::EInfix(left, op, right) => {
                let lhs = self.gen_expr_to_func_with_allocas(func, left, alloca_map, type_checker);
                let rhs = self.gen_expr_to_func_with_allocas(func, right, alloca_map, type_checker);
                let dest = self.new_local();

                let inst = match op.as_str() {
                    "+" => IrInst::Add {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "-" => IrInst::Sub {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "*" => IrInst::Mul {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "/" => IrInst::Div {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "%" => IrInst::Mod {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "==" => IrInst::Eq {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "!=" => IrInst::Neq {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "<" => IrInst::Lt {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    ">" => IrInst::Gt {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "<=" => IrInst::Le {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    ">=" => IrInst::Ge {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "&&" => IrInst::And {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    "||" => IrInst::Or {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                    _ => IrInst::Add {
                        dest: IrValue::Local(dest.clone()),
                        lhs,
                        rhs,
                    },
                };

                self.emit_to_func(func, inst);
                IrValue::Local(dest)
            }
            Expr::EApp(_func_expr, _arg_expr) => {
                // Flatten the curried application spine into a flat
                // argument list. The spine is walked outermost-first, so it
                // yields arguments in reverse; reversing the collected
                // *expressions* before lowering any of them is what makes
                // evaluation left-to-right. Lowering during the walk and
                // reversing the resulting values afterwards - as this did -
                // produces the right argument order with the wrong
                // evaluation order, so in
                // `(f (print "a") (print "b"))` the emitted instructions
                // printed `b` first while `f` still received them the
                // right way round. Argument order is now the source order
                // for both.
                let mut arg_exprs: Vec<&Expr> = Vec::new();
                let mut current = expr;
                while let Expr::EApp(inner_func, inner_arg) = current {
                    arg_exprs.push(inner_arg.as_ref());
                    current = inner_func.as_ref();
                }
                arg_exprs.reverse();

                let mut all_args: Vec<IrValue> = Vec::with_capacity(arg_exprs.len());
                for arg_expr in arg_exprs {
                    all_args.push(self.gen_expr_to_func_with_allocas(
                        func,
                        arg_expr,
                        alloca_map,
                        type_checker,
                    ));
                }

                // `(Just 42)`/`(Cons h t)`-style constructor application:
                // build the real heap-boxed value instead of falling
                // through to the generic `Call` path below, which would
                // otherwise emit a call to a function literally named
                // after the constructor (e.g. `@Just`) that is never
                // declared anywhere - invalid LLVM IR that fails at the
                // `llc`/`cc` stage instead of at a compiler diagnostic.
                // Only handled when the argument count matches the
                // constructor's declared arity exactly; a mismatch here
                // means semantic analysis already reported
                // `ConstructorArity` (see `axiom-sema`), so falling
                // through to the old (still-broken) `Call` path for that
                // case is no worse than before and avoids generating a
                // *third*, different kind of wrong code for an
                // already-diagnosed program.
                if let Expr::EVar(ident) = current {
                    if let Some((tag, arity)) = find_constructor(type_checker, &ident.name) {
                        if arity == all_args.len() {
                            return self.gen_construct(func, tag, all_args);
                        }
                    }
                    // Struct construction: `(Point 1 2)` where `Point`
                    // is a known struct name. Allocate space and store
                    // each field at the appropriate offset (no tag word).
                    if let Some(si) = type_checker.structs.iter().find(|s| s.name == ident.name) {
                        if si.fields.len() != all_args.len() {
                            return IrValue::Const(IrConst::Int(
                                0,
                                TypeId::TCon("I64".to_string(), vec![]),
                            ));
                        }
                        let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                        let struct_size = (si.fields.len() * 8) as i64;
                        let ptr_local = self.new_local();
                        self.emit_to_func(
                            func,
                            IrInst::HeapAlloc {
                                dest: IrValue::Local(ptr_local.clone()),
                                size: IrValue::Const(IrConst::Int(struct_size, i64_ty.clone())),
                            },
                        );
                        for (i, arg) in all_args.into_iter().enumerate() {
                            self.emit_to_func(
                                func,
                                IrInst::StoreOffset {
                                    ptr: IrValue::Local(ptr_local.clone()),
                                    offset: (i * 8) as i64,
                                    value: arg,
                                },
                            );
                        }
                        return IrValue::Local(ptr_local);
                    }
                }

                if let Expr::ELam(params, body) = current {
                    let lambda_val = self.gen_lambda(params, body, type_checker);
                    let lambda_name;
                    if let IrValue::Global(name) = lambda_val {
                        lambda_name = name;
                    } else {
                        lambda_name = "unknown".to_string();
                    }

                    let dest = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::Call {
                            dest: IrValue::Local(dest.clone()),
                            func: lambda_name,
                            args: all_args,
                        },
                    );
                    return IrValue::Local(dest);
                }

                let func_name;
                if let Expr::EVar(ident) = current {
                    func_name = ident.name.clone();
                } else {
                    func_name = "unknown".to_string();
                }

                let dest = self.new_local();

                if all_args.len() == 2 {
                    let lhs = all_args[0].clone();
                    let rhs = all_args[1].clone();
                    let inst = match func_name.as_str() {
                        "+" => Some(IrInst::Add {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "-" => Some(IrInst::Sub {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "*" => Some(IrInst::Mul {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "/" => Some(IrInst::Div {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "%" => Some(IrInst::Mod {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "==" => Some(IrInst::Eq {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "!=" => Some(IrInst::Neq {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "<" => Some(IrInst::Lt {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        ">" => Some(IrInst::Gt {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "<=" => Some(IrInst::Le {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        ">=" => Some(IrInst::Ge {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "&&" => Some(IrInst::And {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        "||" => Some(IrInst::Or {
                            dest: IrValue::Local(dest.clone()),
                            lhs,
                            rhs,
                        }),
                        _ => None,
                    };
                    if let Some(inst) = inst {
                        self.emit_to_func(func, inst);
                        return IrValue::Local(dest);
                    }
                }

                // Freestanding primitives lower to dedicated
                // instructions, not to a call: there is no function
                // named `__syscall3` anywhere to call, and emitting
                // one would produce LLVM IR that fails at link time
                // instead of at a diagnostic.
                if let Some(val) = self.gen_primitive(func, &func_name, &all_args, &dest) {
                    return val;
                }

                self.emit_to_func(
                    func,
                    IrInst::Call {
                        dest: IrValue::Local(dest.clone()),
                        func: func_name,
                        args: all_args,
                    },
                );

                IrValue::Local(dest)
            }
            Expr::EIf(cond, then_expr, else_expr) => {
                let cond_val =
                    self.gen_expr_to_func_with_allocas(func, cond, alloca_map, type_checker);
                let then_label = self.new_block_label();
                let else_label = self.new_block_label();
                let merge_label = self.new_block_label();
                let result_alloca = self.new_local();

                self.emit_to_func(
                    func,
                    IrInst::Alloca {
                        dest: IrValue::Local(result_alloca.clone()),
                        ty: TypeId::TCon("I64".to_string(), vec![]),
                    },
                );

                self.emit_to_func(
                    func,
                    IrInst::CondBr {
                        cond: cond_val,
                        then_target: then_label.clone(),
                        else_target: else_label.clone(),
                    },
                );

                func.blocks.push(IrBlock {
                    label: then_label.clone(),
                    insts: Vec::new(),
                });
                self.current_block = Some(then_label.clone());
                let then_val =
                    self.gen_expr_to_func_with_allocas(func, then_expr, alloca_map, type_checker);
                self.emit_to_func(
                    func,
                    IrInst::Store {
                        ptr: IrValue::Local(result_alloca.clone()),
                        value: then_val,
                    },
                );
                self.emit_to_func(
                    func,
                    IrInst::Br {
                        target: merge_label.clone(),
                    },
                );

                func.blocks.push(IrBlock {
                    label: else_label.clone(),
                    insts: Vec::new(),
                });
                self.current_block = Some(else_label.clone());
                let else_val =
                    self.gen_expr_to_func_with_allocas(func, else_expr, alloca_map, type_checker);
                self.emit_to_func(
                    func,
                    IrInst::Store {
                        ptr: IrValue::Local(result_alloca.clone()),
                        value: else_val,
                    },
                );
                self.emit_to_func(
                    func,
                    IrInst::Br {
                        target: merge_label.clone(),
                    },
                );

                func.blocks.push(IrBlock {
                    label: merge_label.clone(),
                    insts: Vec::new(),
                });
                self.current_block = Some(merge_label.clone());

                let load_dest = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::Load {
                        dest: IrValue::Local(load_dest.clone()),
                        ptr: IrValue::Local(result_alloca),
                    },
                );
                IrValue::Local(load_dest)
            }
            Expr::ELet(bindings, body) => {
                for (pat, init) in bindings {
                    if let Pattern::PVar(ident) = pat {
                        let value = self.gen_expr_to_func_with_allocas(
                            func,
                            init,
                            alloca_map,
                            type_checker,
                        );
                        let alloca_name = self.new_alloca(&ident.name);
                        func.locals
                            .push((ident.name.clone(), TypeId::TCon("I64".to_string(), vec![])));
                        self.emit_to_func(
                            func,
                            IrInst::Alloca {
                                dest: IrValue::Local(alloca_name.clone()),
                                ty: TypeId::TCon("I64".to_string(), vec![]),
                            },
                        );
                        self.emit_to_func(
                            func,
                            IrInst::Store {
                                ptr: IrValue::Local(alloca_name.clone()),
                                value,
                            },
                        );
                        alloca_map.insert(ident.name.clone(), alloca_name);
                    }
                }
                self.gen_expr_to_func_with_allocas(func, body, alloca_map, type_checker)
            }
            Expr::EMatch(target, arms) => {
                let target_val =
                    self.gen_expr_to_func_with_allocas(func, target, alloca_map, type_checker);
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                let result_alloca = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::Alloca {
                        dest: IrValue::Local(result_alloca.clone()),
                        ty: i64_ty.clone(),
                    },
                );

                // Load the scrutinee's tag *once*, up front, rather than
                // re-deriving "is this a constructor value" per arm - every
                // `PCon` arm below compares against this same loaded tag,
                // and every arm agrees on what a given constructor's tag is
                // because both this and construction (`gen_construct`) go
                // through the one shared `find_constructor` lookup. Only
                // emitted when at least one arm actually needs it: a `match`
                // over a plain `Int`/`Bool` scrutinee with only
                // `PLit`/`PVar`/`PWildcard` arms has nothing to unbox.
                let needs_tag = arms.iter().any(|(pat, _)| {
                    matches!(pat, Pattern::PCon(ident, ..) if find_constructor(type_checker, &ident.name).is_some())
                });
                let tag_val = if needs_tag {
                    let tag_local = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::LoadOffset {
                            dest: IrValue::Local(tag_local.clone()),
                            ptr: target_val.clone(),
                            offset: 0,
                        },
                    );
                    Some(IrValue::Local(tag_local))
                } else {
                    None
                };

                let merge_label = self.new_block_label();
                // Where a scrutinee that matched no arm goes.
                //
                // It used to go to `merge_label`, which then *loaded the
                // result slot* - a slot nothing had stored to. A `match`
                // that fell off the end therefore produced whatever was
                // on the stack and carried on, silently. Sema's
                // exhaustiveness check is what normally prevents this, so
                // reaching the block means either a gap in that check or
                // an arm whose sub-pattern failed after its tag matched
                // (`(Just 0)` against `(Just 1)`), which is *not* covered
                // by constructor exhaustiveness at all and so is reachable
                // in a program sema accepts today.
                let fail_label = self.new_block_label();
                let mut arm_labels: Vec<String> = Vec::new();
                let mut check_labels: Vec<String> = Vec::new();
                for _ in arms {
                    arm_labels.push(self.new_block_label());
                    check_labels.push(self.new_block_label());
                }

                if !check_labels.is_empty() {
                    self.emit_to_func(
                        func,
                        IrInst::Br {
                            target: check_labels[0].clone(),
                        },
                    );
                }

                for (i, (pat, body)) in arms.iter().enumerate() {
                    let arm_label = &arm_labels[i];
                    let check_label = &check_labels[i];
                    let mut arm_map = alloca_map.clone();

                    let next_check = if i < arms.len() - 1 {
                        check_labels[i + 1].clone()
                    } else {
                        fail_label.clone()
                    };

                    // Emit an unconditional-match check block: no
                    // comparison, straight through to the arm. Shared by
                    // `PWildcard`, `PVar`, and any constructor name sema
                    // already flagged as undefined (see
                    // `SemError::UndefinedConstructor`) - codegen doesn't
                    // re-diagnose that, it just avoids compiling the
                    // already-reported-invalid program into something
                    // that miscompares against a tag that doesn't exist.
                    let unconditional_arm = |gen: &mut Self, func: &mut IrFunction| {
                        func.blocks.push(IrBlock {
                            label: check_label.clone(),
                            insts: Vec::new(),
                        });
                        gen.current_block = Some(check_label.clone());
                        gen.emit_to_func(
                            func,
                            IrInst::Br {
                                target: arm_label.clone(),
                            },
                        );
                        func.blocks.push(IrBlock {
                            label: arm_label.clone(),
                            insts: Vec::new(),
                        });
                        gen.current_block = Some(arm_label.clone());
                    };

                    match pat {
                        Pattern::PCon(ident, args) => {
                            match find_constructor(type_checker, &ident.name) {
                                Some((tag, _arity)) => {
                                    func.blocks.push(IrBlock {
                                        label: check_label.clone(),
                                        insts: Vec::new(),
                                    });
                                    self.current_block = Some(check_label.clone());

                                    let cmp_dest = self.new_local();
                                    self.emit_to_func(
                                        func,
                                        IrInst::Eq {
                                            dest: IrValue::Local(cmp_dest.clone()),
                                            lhs: tag_val.clone().expect(
                                                "needs_tag scan above must have found this arm",
                                            ),
                                            rhs: IrValue::Const(IrConst::Int(tag, i64_ty.clone())),
                                        },
                                    );
                                    self.emit_to_func(
                                        func,
                                        IrInst::CondBr {
                                            cond: IrValue::Local(cmp_dest),
                                            then_target: arm_label.clone(),
                                            else_target: next_check.clone(),
                                        },
                                    );

                                    func.blocks.push(IrBlock {
                                        label: arm_label.clone(),
                                        insts: Vec::new(),
                                    });
                                    self.current_block = Some(arm_label.clone());

                                    // Non-`PVar` sub-patterns (nested constructors,
                                    // literals, tuples, lists) are handled by
                                    // `gen_sub_pattern_checks` which implements
                                    // recursive matching.
                                    // A sub-pattern that fails must fall
                                    // through to the *next arm*, not to the
                                    // merge block: the tag matching only
                                    // establishes the constructor, and a
                                    // later arm may well match the fields.
                                    // Sending it to merge made
                                    // `((Just 0) a) ((Just n) b)` yield
                                    // uninitialised memory for `(Just 1)`
                                    // instead of `b`.
                                    self.gen_sub_pattern_checks(
                                        func,
                                        target_val.clone(),
                                        args,
                                        type_checker,
                                        next_check.clone(),
                                        &mut arm_map,
                                        CON_FIELD_BASE,
                                    );
                                }
                                None => unconditional_arm(self, func),
                            }
                        }
                        Pattern::PVar(ident) => {
                            unconditional_arm(self, func);

                            let var_alloca = self.new_alloca(&ident.name);
                            func.locals.push((ident.name.clone(), i64_ty.clone()));
                            self.emit_to_func(
                                func,
                                IrInst::Alloca {
                                    dest: IrValue::Local(var_alloca.clone()),
                                    ty: i64_ty.clone(),
                                },
                            );
                            self.emit_to_func(
                                func,
                                IrInst::Store {
                                    ptr: IrValue::Local(var_alloca.clone()),
                                    value: target_val.clone(),
                                },
                            );
                            arm_map.insert(ident.name.clone(), var_alloca);
                        }
                        Pattern::PWildcard => unconditional_arm(self, func),
                        Pattern::PLit(lit) => {
                            func.blocks.push(IrBlock {
                                label: check_label.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(check_label.clone());

                            let lit_val = self.gen_literal(lit);
                            let cmp_dest = self.new_local();
                            self.emit_to_func(
                                func,
                                IrInst::Eq {
                                    dest: IrValue::Local(cmp_dest.clone()),
                                    lhs: target_val.clone(),
                                    rhs: lit_val,
                                },
                            );
                            self.emit_to_func(
                                func,
                                IrInst::CondBr {
                                    cond: IrValue::Local(cmp_dest),
                                    then_target: arm_label.clone(),
                                    else_target: next_check,
                                },
                            );

                            func.blocks.push(IrBlock {
                                label: arm_label.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(arm_label.clone());
                        }
                        Pattern::PTuple(pats) | Pattern::PList(pats) => {
                            func.blocks.push(IrBlock {
                                label: check_label.clone(),
                                insts: vec![IrInst::Br {
                                    target: arm_label.clone(),
                                }],
                            });
                            self.current_block = Some(arm_label.clone());

                            func.blocks.push(IrBlock {
                                label: arm_label.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(arm_label.clone());

                            self.gen_sub_pattern_checks(
                                func,
                                target_val.clone(),
                                pats,
                                type_checker,
                                next_check.clone(),
                                &mut arm_map,
                                0,
                            );
                        }
                    }

                    let body_val =
                        self.gen_expr_to_func_with_allocas(func, body, &mut arm_map, type_checker);
                    self.emit_to_func(
                        func,
                        IrInst::Store {
                            ptr: IrValue::Local(result_alloca.clone()),
                            value: body_val,
                        },
                    );
                    self.emit_to_func(
                        func,
                        IrInst::Br {
                            target: merge_label.clone(),
                        },
                    );
                }

                // The no-arm-matched block. Calls a runtime trap that
                // exits with a distinguishable status rather than falling
                // into `merge` and reading the never-written result slot.
                // Emitted unconditionally when there is at least one arm,
                // because it is a branch target: whether it is *reachable*
                // depends on the arms, and an unreachable block is free,
                // whereas a dangling label is invalid IR.
                if !arms.is_empty() {
                    func.blocks.push(IrBlock {
                        label: fail_label.clone(),
                        insts: Vec::new(),
                    });
                    self.current_block = Some(fail_label.clone());
                    let trap_dest = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::Call {
                            dest: IrValue::Local(trap_dest),
                            func: MATCH_FAIL_SYMBOL.to_string(),
                            args: Vec::new(),
                        },
                    );
                    self.emit_to_func(
                        func,
                        IrInst::Br {
                            target: merge_label.clone(),
                        },
                    );
                }

                func.blocks.push(IrBlock {
                    label: merge_label.clone(),
                    insts: Vec::new(),
                });
                self.current_block = Some(merge_label.clone());

                let load_dest = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::Load {
                        dest: IrValue::Local(load_dest.clone()),
                        ptr: IrValue::Local(result_alloca),
                    },
                );
                IrValue::Local(load_dest)
            }
            Expr::EBegin(exprs) => {
                let mut last_val =
                    IrValue::Const(IrConst::Int(0, TypeId::TCon("I64".to_string(), vec![])));
                for e in exprs {
                    last_val =
                        self.gen_expr_to_func_with_allocas(func, e, alloca_map, type_checker);
                }
                last_val
            }
            Expr::ECast(inner, target_type) => {
                let src = self.gen_expr_to_func_with_allocas(func, inner, alloca_map, type_checker);
                let dest = self.new_local();
                let target_ty = self.type_to_id(target_type);

                self.emit_to_func(
                    func,
                    IrInst::Cast {
                        dest: IrValue::Local(dest.clone()),
                        src,
                        target_ty,
                    },
                );

                IrValue::Local(dest)
            }
            Expr::ESizeof(ty, _) => {
                let dest = self.new_local();
                let resolved_ty = self.type_to_id(ty);
                self.emit_to_func(
                    func,
                    IrInst::Sizeof {
                        dest: IrValue::Local(dest.clone()),
                        ty: resolved_ty,
                    },
                );
                IrValue::Local(dest)
            }
            Expr::EAlignof(ty, _) => {
                let dest = self.new_local();
                let resolved_ty = self.type_to_id(ty);
                self.emit_to_func(
                    func,
                    IrInst::Alignof {
                        dest: IrValue::Local(dest.clone()),
                        ty: resolved_ty,
                    },
                );
                IrValue::Local(dest)
            }
            Expr::EGrouped(inner) => {
                self.gen_expr_to_func_with_allocas(func, inner, alloca_map, type_checker)
            }
            Expr::ELam(params, body) => self.gen_lambda(params, body, type_checker),
            Expr::ETuple(elements) => {
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                let tuple_size = (elements.len() * 8) as i64;
                let ptr_local = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::HeapAlloc {
                        dest: IrValue::Local(ptr_local.clone()),
                        size: IrValue::Const(IrConst::Int(tuple_size, i64_ty.clone())),
                    },
                );
                for (i, elem) in elements.iter().enumerate() {
                    let val =
                        self.gen_expr_to_func_with_allocas(func, elem, alloca_map, type_checker);
                    self.emit_to_func(
                        func,
                        IrInst::StoreOffset {
                            ptr: IrValue::Local(ptr_local.clone()),
                            offset: (i * 8) as i64,
                            value: val,
                        },
                    );
                }
                IrValue::Local(ptr_local)
            }
            Expr::EList(items) => {
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                let list_size = (items.len() * 8) as i64;
                let ptr_local = self.new_local();
                self.emit_to_func(
                    func,
                    IrInst::HeapAlloc {
                        dest: IrValue::Local(ptr_local.clone()),
                        size: IrValue::Const(IrConst::Int(list_size, i64_ty.clone())),
                    },
                );
                for (i, item) in items.iter().enumerate() {
                    let val =
                        self.gen_expr_to_func_with_allocas(func, item, alloca_map, type_checker);
                    self.emit_to_func(
                        func,
                        IrInst::StoreOffset {
                            ptr: IrValue::Local(ptr_local.clone()),
                            offset: (i * 8) as i64,
                            value: val,
                        },
                    );
                }
                IrValue::Local(ptr_local)
            }
            Expr::EHandle(body, _, handler) => {
                let _ = handler;
                self.gen_expr_to_func_with_allocas(func, body, alloca_map, type_checker)
            }
            Expr::EConsume(e) => {
                self.gen_expr_to_func_with_allocas(func, e, alloca_map, type_checker)
            }
            Expr::EField(base, field_ident) => {
                let base_val =
                    self.gen_expr_to_func_with_allocas(func, base, alloca_map, type_checker);
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                if let Some((_struct_name, field_index, _field_ty)) =
                    type_checker.find_struct_field_by_name(&field_ident.name)
                {
                    let offset = (field_index * 8) as i64;
                    let result_reg = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::LoadOffset {
                            dest: IrValue::Local(result_reg.clone()),
                            ptr: base_val,
                            offset,
                        },
                    );
                    IrValue::Local(result_reg)
                } else {
                    IrValue::Const(IrConst::Int(0, i64_ty))
                }
            }
            Expr::ESetField(base, field_ident, value) => {
                let base_val =
                    self.gen_expr_to_func_with_allocas(func, base, alloca_map, type_checker);
                let value_val =
                    self.gen_expr_to_func_with_allocas(func, value, alloca_map, type_checker);
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                if let Some((_struct_name, field_index, _field_ty)) =
                    type_checker.find_struct_field_by_name(&field_ident.name)
                {
                    let offset = (field_index * 8) as i64;
                    self.emit_to_func(
                        func,
                        IrInst::StoreOffset {
                            ptr: base_val,
                            offset,
                            value: value_val,
                        },
                    );
                    IrValue::Const(IrConst::Int(0, i64_ty))
                } else {
                    IrValue::Const(IrConst::Int(0, i64_ty))
                }
            }
            Expr::EStructCon(name, args) => {
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                if let Some(si) = type_checker.structs.iter().find(|s| s.name == name.name) {
                    if si.fields.len() != args.len() {
                        return IrValue::Const(IrConst::Int(0, i64_ty));
                    }
                    let struct_size = (si.fields.len() * 8) as i64;
                    let ptr_local = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::HeapAlloc {
                            dest: IrValue::Local(ptr_local.clone()),
                            size: IrValue::Const(IrConst::Int(struct_size, i64_ty.clone())),
                        },
                    );
                    for (i, arg) in args.iter().enumerate() {
                        let val =
                            self.gen_expr_to_func_with_allocas(func, arg, alloca_map, type_checker);
                        self.emit_to_func(
                            func,
                            IrInst::StoreOffset {
                                ptr: IrValue::Local(ptr_local.clone()),
                                offset: (i * 8) as i64,
                                value: val,
                            },
                        );
                    }
                    IrValue::Local(ptr_local)
                } else {
                    IrValue::Const(IrConst::Int(0, i64_ty))
                }
            }
            _ => IrValue::Const(IrConst::Int(0, TypeId::TCon("I64".to_string(), vec![]))),
        }
    }

    fn gen_literal(&self, lit: &Literal) -> IrValue {
        match lit {
            Literal::LInt(n) => {
                IrValue::Const(IrConst::Int(*n, TypeId::TCon("I64".to_string(), vec![])))
            }
            Literal::LFloat(n) => {
                IrValue::Const(IrConst::Float(*n, TypeId::TCon("F64".to_string(), vec![])))
            }
            Literal::LBool(b) => IrValue::Const(IrConst::Bool(*b)),
            Literal::LChar(c) => IrValue::Const(IrConst::Int(
                *c as i64,
                TypeId::TCon("U8".to_string(), vec![]),
            )),
            Literal::LStr(s) => IrValue::Const(IrConst::Str(s.clone())),
        }
    }

    fn type_to_id(&self, ty: &Type) -> TypeId {
        match ty {
            Type::TCon(ident, _) => match ident.name.as_str() {
                "Int" | "Integer" => TypeId::TCon("Int".to_string(), vec![]),
                "Float" => TypeId::TCon("Float".to_string(), vec![]),
                "Double" => TypeId::TCon("Double".to_string(), vec![]),
                "Bool" => TypeId::TCon("Bool".to_string(), vec![]),
                "Char" => TypeId::TCon("Char".to_string(), vec![]),
                "String" => TypeId::TCon("String".to_string(), vec![]),
                "Void" => TypeId::TCon("Void".to_string(), vec![]),
                "Any" => TypeId::TCon("Any".to_string(), vec![]),
                "I8" => TypeId::TCon("I8".to_string(), vec![]),
                "I16" => TypeId::TCon("I16".to_string(), vec![]),
                "I32" => TypeId::TCon("I32".to_string(), vec![]),
                "I64" => TypeId::TCon("I64".to_string(), vec![]),
                "I128" => TypeId::TCon("I128".to_string(), vec![]),
                "Isize" => TypeId::TCon("Isize".to_string(), vec![]),
                "U8" => TypeId::TCon("U8".to_string(), vec![]),
                "U16" => TypeId::TCon("U16".to_string(), vec![]),
                "U32" => TypeId::TCon("U32".to_string(), vec![]),
                "U64" => TypeId::TCon("U64".to_string(), vec![]),
                "U128" => TypeId::TCon("U128".to_string(), vec![]),
                "Usize" => TypeId::TCon("Usize".to_string(), vec![]),
                "F32" => TypeId::TCon("F32".to_string(), vec![]),
                "F64" => TypeId::TCon("F64".to_string(), vec![]),
                _ => TypeId::TCon(ident.name.clone(), vec![]),
            },
            Type::TPtr(inner, mutable) => TypeId::TPtr(Box::new(self.type_to_id(inner)), *mutable),
            Type::TList(inner) => TypeId::TList(Box::new(self.type_to_id(inner))),
            Type::TTuple(_) => TypeId::TTuple(vec![]),
            Type::TArr(from, to) => TypeId::TArr(
                Box::new(self.type_to_id(from)),
                Box::new(self.type_to_id(to)),
            ),
            Type::TVar(name) => TypeId::TVar(name.clone()),
            Type::TForall(_, inner) => self.type_to_id(inner),
            Type::TEffect(inner, _) => self.type_to_id(inner),
            Type::TLinear(inner) => {
                TypeId::TCon("Linear".to_string(), vec![self.type_to_id(inner)])
            }
        }
    }

    /// Append `inst` to the block the emission cursor names.
    ///
    /// The cursor is a *label*, not a reference, so it can name a block
    /// that does not belong to `func` - and it did: `gen_lambda` used to
    /// leave the cursor pointing at the lambda's entry block, after which
    /// every remaining instruction of the enclosing function, including
    /// its `Ret`, was dropped on the floor and the function silently
    /// returned the codegen fallback of `0`. That is a miscompilation
    /// rather than a build failure, which is the worst class of bug this
    /// file can have, so the case is now loud instead of silent.
    ///
    /// Reaching the panic means a lowering routine repointed the cursor
    /// without restoring it. It is unreachable from any input - malformed
    /// source produces a diagnostic long before here - so it is an
    /// internal invariant, not input validation.
    fn emit_to_func(&mut self, func: &mut IrFunction, inst: IrInst) {
        let Some(ref label) = self.current_block else {
            return;
        };
        match func.blocks.iter_mut().find(|b| &b.label == label) {
            Some(block) => block.insts.push(inst),
            None => panic!(
                "internal compiler error: IR emission cursor names block `{}`, \
                 which is not a block of function `{}`. A lowering routine \
                 repointed `current_block` without restoring it.",
                label, func.name
            ),
        }
    }

    fn new_local(&mut self) -> String {
        let name = format!("_local_{}", self.local_counter);
        self.local_counter += 1;
        name
    }

    /// Mint a unique stack-slot name for a source-level binding.
    ///
    /// The slot name used to be `_alloca_{source name}` verbatim, which
    /// collides whenever one function binds the same name twice - two
    /// `match` arms that both bind `x`, or a `let` shadowing a parameter.
    /// The result was two `%_alloca_x = alloca i64` lines in one function
    /// and a hard `llc` failure (`multiple definition of local value
    /// named '_alloca_x'`). Shadowing is ordinary in this language and
    /// tail-call lowering reassigns parameter slots, so uniqueness cannot
    /// be left to the source program.
    ///
    /// The source name is kept in the slot name because it is the only
    /// thing that makes emitted IR readable when debugging a lowering
    /// bug; the counter suffix is what makes it correct. The
    /// `_alloca_` prefix is load-bearing - `axiom-codegen` keys the
    /// stack-slot register naming off it.
    fn new_alloca(&mut self, source_name: &str) -> String {
        let name = format!("_alloca_{}_{}", source_name, self.alloca_counter);
        self.alloca_counter += 1;
        name
    }

    fn new_block_label(&mut self) -> String {
        let name = format!("_block_{}", self.block_counter);
        self.block_counter += 1;
        name
    }
}
