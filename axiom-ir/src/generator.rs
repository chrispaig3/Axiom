use crate::{
    IrBlock, IrConst, IrEnum, IrFunction, IrInst, IrModule, IrStruct, IrUnion, IrValue, TypeId,
};
use axiom_ast::ast::*;
use axiom_ast::span::{Ident, Span};
use axiom_sema::TypeChecker;
use std::collections::{HashMap, HashSet};

pub struct IrGen {
    module: IrModule,
    local_counter: usize,
    block_counter: usize,
    lambda_counter: usize,
    current_block: Option<String>,
}

/// Look up a struct variant by name across every `struct`
/// type the type checker collected, returning:
///
/// * a globally-unique integer tag (`struct_index * 100 +
///   variant_index_within_that_struct`) - unique across every
///   variant in the program, not just within one `struct` type,
///   so two different `struct` types' variants can never compare
///   equal by accident during pattern matching;
/// * its arity, decomposed from the variant's field types
///   (each field is an `i64` word, so the arity is just the
///   number of fields).
///
/// Both variant *construction* (`EVar`/`EApp`, see
/// [`IrGen::gen_construct`]) and variant *matching* (`EMatch`) call
/// this, so a value built with one tag is always compared against that
/// exact same tag - there is exactly one place in the generator that
/// decides what a variant's tag is.
fn find_constructor(type_checker: &TypeChecker, name: &str) -> Option<(i64, usize)> {
    for (idx, si) in type_checker.structs.iter().enumerate() {
        for (vidx, sv) in si.variants.iter().enumerate() {
            if sv.name == name {
                let tag = (idx * 100 + vidx) as i64;
                let arity = sv.fields.len();
                return Some((tag, arity));
            }
        }
    }
    None
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
            current_block: None,
        }
    }

    pub fn generate(&mut self, ast_module: &Module, type_checker: &mut TypeChecker) -> IrModule {
        for decl in &ast_module.decls {
            match decl {
                Decl::DStruct {
                    name,
                    tyvars: _,
                    variants,
                    repr,
                    ..
                } => {
                    let packed = matches!(repr, Some(TypeRepr::Packed));
                    let align = if let Some(TypeRepr::Align(n)) = repr {
                        Some(*n)
                    } else {
                        None
                    };

                    // Single-variant struct (product type): generate as IrStruct
                    // Multi-variant struct (ADT): generate each variant as an IrEnum entry
                    if variants.len() == 1 {
                        let fields: Vec<(String, TypeId)> = variants[0]
                            .fields
                            .iter()
                            .map(|f| (f.name.name.clone(), self.type_to_id(&f.ty)))
                            .collect();
                        self.module.structs.push(IrStruct {
                            name: name.name.clone(),
                            fields,
                            packed,
                            align,
                        });
                    } else {
                        // Multi-variant ADT: generate as IrEnum
                        let enum_variants: Vec<(String, Option<TypeId>)> = variants
                            .iter()
                            .map(|sv| {
                                if sv.fields.is_empty() {
                                    (sv.name.name.clone(), None)
                                } else {
                                    // For variants with fields, use the first field's type
                                    // as the variant's type (for tagged union representation)
                                    let field_ty = self.type_to_id(&sv.fields[0].ty);
                                    (sv.name.name.clone(), Some(field_ty))
                                }
                            })
                            .collect();
                        let tag_type = TypeId::TCon("I64".to_string(), vec![]);
                        self.module.enums.push(IrEnum {
                            name: name.name.clone(),
                            variants: enum_variants,
                            tag_type,
                        });
                    }
                }
                Decl::DUnion { name, fields, .. } => {
                    let ir_fields: Vec<(String, TypeId)> = fields
                        .iter()
                        .map(|f| (f.name.name.clone(), self.type_to_id(&f.ty)))
                        .collect();

                    self.module.unions.push(IrUnion {
                        name: name.name.clone(),
                        fields: ir_fields,
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
            let alloca_name = format!("_alloca_{}", pname);
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
                    let arg_alloca = format!("_alloca_{}", ident.name);
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
                            let cmp_dest = self.new_local();
                            self.emit_to_func(
                                func,
                                IrInst::Eq {
                                    dest: IrValue::Local(cmp_dest.clone()),
                                    lhs: IrValue::Local(field_local.clone()),
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
                                1,
                            );
                            return;
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
                                1,
                            );
                            return;
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
                    return;
                }
            }
        }
    }

    fn collect_captured_vars(
        expr: &Expr,
        lambda_params: &[String],
        outer_alloca_map: &HashMap<String, String>,
        out: &mut Vec<String>,
        seen: &mut HashSet<String>,
    ) {
        match expr {
            Expr::EVar(ident) => {
                let name = ident.name.clone();
                if !lambda_params.contains(&name)
                    && outer_alloca_map.contains_key(&name)
                    && !seen.contains(&name)
                {
                    seen.insert(name.clone());
                    out.push(name);
                }
            }
            Expr::EApp(func, arg) => {
                Self::collect_captured_vars(func, lambda_params, outer_alloca_map, out, seen);
                Self::collect_captured_vars(arg, lambda_params, outer_alloca_map, out, seen);
            }
            Expr::ELam(_, body) => {
                let _ = body;
            }
            Expr::ELet(bindings, body) => {
                for (_, e) in bindings {
                    Self::collect_captured_vars(e, lambda_params, outer_alloca_map, out, seen);
                }
                Self::collect_captured_vars(body, lambda_params, outer_alloca_map, out, seen);
            }
            Expr::EIf(_, t, e) => {
                Self::collect_captured_vars(t, lambda_params, outer_alloca_map, out, seen);
                Self::collect_captured_vars(e, lambda_params, outer_alloca_map, out, seen);
            }
            Expr::EMatch(target, arms) => {
                Self::collect_captured_vars(target, lambda_params, outer_alloca_map, out, seen);
                for (_, e) in arms {
                    Self::collect_captured_vars(e, lambda_params, outer_alloca_map, out, seen);
                }
            }
            Expr::ECond(branches, else_) => {
                for (c, e) in branches {
                    Self::collect_captured_vars(c, lambda_params, outer_alloca_map, out, seen);
                    Self::collect_captured_vars(e, lambda_params, outer_alloca_map, out, seen);
                }
                if let Some(e) = else_ {
                    Self::collect_captured_vars(e, lambda_params, outer_alloca_map, out, seen);
                }
            }
            Expr::EBegin(es) | Expr::ETuple(es) | Expr::EList(es) => {
                for e in es {
                    Self::collect_captured_vars(e, lambda_params, outer_alloca_map, out, seen);
                }
            }
            Expr::EInfix(l, _, r) => {
                Self::collect_captured_vars(l, lambda_params, outer_alloca_map, out, seen);
                Self::collect_captured_vars(r, lambda_params, outer_alloca_map, out, seen);
            }
            Expr::ETypeSig(e, _)
            | Expr::ECast(e, _)
            | Expr::EGrouped(e)
            | Expr::ERegion(_, e)
            | Expr::EConsume(e)
            | Expr::EField(e, _) => {
                Self::collect_captured_vars(e, lambda_params, outer_alloca_map, out, seen);
            }
            Expr::EAlloc(_, init, _) => {
                if let Some(e) = init {
                    Self::collect_captured_vars(e, lambda_params, outer_alloca_map, out, seen);
                }
            }
            Expr::ESetField(base, _, value) => {
                Self::collect_captured_vars(base, lambda_params, outer_alloca_map, out, seen);
                Self::collect_captured_vars(value, lambda_params, outer_alloca_map, out, seen);
            }
            Expr::EUnionCon(_, _, value) => {
                Self::collect_captured_vars(value, lambda_params, outer_alloca_map, out, seen);
            }
            Expr::EStructCon(_, args) => {
                for e in args {
                    Self::collect_captured_vars(e, lambda_params, outer_alloca_map, out, seen);
                }
            }
            Expr::ELit(_, _) | Expr::ESizeof(_, _) | Expr::EAlignof(_, _) | Expr::EError(_, _) => {}
            Expr::EHandle(body, _, after) => {
                Self::collect_captured_vars(body, lambda_params, outer_alloca_map, out, seen);
                Self::collect_captured_vars(after, lambda_params, outer_alloca_map, out, seen);
            }
        }
    }

    /// Compile a lambda expression as a named IR function in the
    /// module so it can be passed as a first-class value or called
    /// directly. Parameters are always `I64`; non-`PVar` patterns
    /// are not yet supported for lambda parameters. Free variables
    /// captured from the enclosing scope are supported via a
    /// heap-allocated closure struct: the lambda function receives
    /// captured values as extra leading parameters and the closure
    /// struct bundles the function pointer with the captured values.
    fn gen_lambda(
        &mut self,
        params: &[Pattern],
        body: &Expr,
        type_checker: &mut TypeChecker,
        outer_alloca_map: &mut HashMap<String, String>,
        func: &mut IrFunction,
    ) -> IrValue {
        self.lambda_counter += 1;
        let lambda_name = format!("_lambda_{}", self.lambda_counter);

        // Collect captured variable names from the body.
        let mut captured_vars: Vec<String> = Vec::new();
        let mut seen = HashSet::new();
        Self::collect_captured_vars(body, &[], outer_alloca_map, &mut captured_vars, &mut seen);

        let lambda_param_names: Vec<String> = params
            .iter()
            .filter_map(|p| {
                if let Pattern::PVar(ident) = p {
                    Some(ident.name.clone())
                } else {
                    None
                }
            })
            .collect();

        // Lambda param order: captures first (i64), then lambda params (i64).
        let mut lambda_params: Vec<(String, TypeId)> = Vec::new();
        for cap_name in &captured_vars {
            let cap_type = type_checker
                .scope
                .iter()
                .rev()
                .find(|(name, _)| name == cap_name)
                .map(|(_, vi)| vi.ty.clone())
                .unwrap_or(TypeId::TCon("I64".to_string(), vec![]));
            lambda_params.push((cap_name.clone(), cap_type));
        }
        for pname in &lambda_param_names {
            lambda_params.push((pname.clone(), TypeId::TCon("I64".to_string(), vec![])));
        }

        let lambda_return = TypeId::TCon("I64".to_string(), vec![]);

        let mut lambda_func = IrFunction {
            name: lambda_name.clone(),
            params: lambda_params.clone(),
            return_type: lambda_return,
            blocks: Vec::new(),
            locals: Vec::new(),
        };

        let entry_label = self.new_block_label();
        self.current_block = Some(entry_label.clone());
        lambda_func.blocks.push(IrBlock {
            label: entry_label.clone(),
            insts: Vec::new(),
        });

        let mut lambda_alloca_map: HashMap<String, String> = HashMap::new();

        // Alloca + store for captured params.
        for (pname, pty) in lambda_params.iter().take(captured_vars.len()) {
            let alloca_name = format!("_captured_{}", pname);
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

        // Alloca + store for normal lambda params.
        let capture_count = captured_vars.len();
        for (_i, (pname, pty)) in lambda_params.iter().enumerate().skip(capture_count) {
            let alloca_name = format!("_alloca_{}", pname);
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

        if captured_vars.is_empty() {
            IrValue::Global(lambda_name)
        } else {
            // Build a closure struct on the heap: [i64; 1 + captures.len()]
            // layout: [func_ptr, captured_1, captured_2, ...]
            let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
            let closure_size = ((1 + captured_vars.len()) * 8) as i64;
            let closure_ptr = self.new_local();
            self.emit_to_func(
                func,
                IrInst::HeapAlloc {
                    dest: IrValue::Local(closure_ptr.clone()),
                    size: IrValue::Const(IrConst::Int(closure_size, i64_ty.clone())),
                },
            );
            // Store function pointer at offset 0.
            self.emit_to_func(
                func,
                IrInst::StoreOffset {
                    ptr: IrValue::Local(closure_ptr.clone()),
                    offset: 0,
                    value: IrValue::Global(lambda_name.clone()),
                },
            );
            // Store each captured value at offset 8 * (1 + i).
            for (i, cap_name) in captured_vars.iter().enumerate() {
                if let Some(alloca_name) = outer_alloca_map.get(cap_name) {
                    let cap_value = IrValue::Local(alloca_name.clone());
                    self.emit_to_func(
                        func,
                        IrInst::StoreOffset {
                            ptr: IrValue::Local(closure_ptr.clone()),
                            offset: ((i + 1) * 8) as i64,
                            value: cap_value,
                        },
                    );
                } else {
                    // Captured variable not in outer alloca_map;
                    // emit a load from the outer scope's alloca and store it.
                    let cap_value = self.gen_expr_to_func_with_allocas(
                        func,
                        &Expr::EVar(Ident::new(cap_name, Span::dummy())),
                        outer_alloca_map,
                        type_checker,
                    );
                    self.emit_to_func(
                        func,
                        IrInst::StoreOffset {
                            ptr: IrValue::Local(closure_ptr.clone()),
                            offset: ((i + 1) * 8) as i64,
                            value: cap_value,
                        },
                    );
                }
            }
            IrValue::Local(closure_ptr)
        }
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
                // A *bare* reference to a nullary constructor (`None`,
                // `Leaf`, ...) constructs its (fieldless) boxed value
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
                let mut all_args: Vec<IrValue> = Vec::new();
                let mut current = expr;
                while let Expr::EApp(inner_func, inner_arg) = current {
                    all_args.push(self.gen_expr_to_func_with_allocas(
                        func,
                        inner_arg,
                        alloca_map,
                        type_checker,
                    ));
                    current = inner_func.as_ref();
                }
                all_args.reverse();

                // `(Some 42)`/`(Node a b)`-style constructor application:
                // build the real heap-boxed value instead of falling
                // through to the generic `Call` path below, which would
                // otherwise emit a call to a function literally named
                // after the constructor (e.g. `@Some`) that is never
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
                        let sv = si.variants.first().unwrap();
                        if sv.fields.len() != all_args.len() {
                            return IrValue::Const(IrConst::Int(
                                0,
                                TypeId::TCon("I64".to_string(), vec![]),
                            ));
                        }
                        let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                        let struct_size = (sv.fields.len() * 8) as i64;
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
                    // Union construction: `(Value 42)` where `Value`
                    // is a known union name with exactly one field.
                    // Allocate space and store the value at offset 0.
                    if let Some(ui) = type_checker.unions.iter().find(|u| u.name == ident.name) {
                        if ui.fields.len() != 1 || all_args.len() != 1 {
                            return IrValue::Const(IrConst::Int(
                                0,
                                TypeId::TCon("I64".to_string(), vec![]),
                            ));
                        }
                        let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                        let ptr_local = self.new_local();
                        self.emit_to_func(
                            func,
                            IrInst::HeapAlloc {
                                dest: IrValue::Local(ptr_local.clone()),
                                size: IrValue::Const(IrConst::Int(8, i64_ty.clone())),
                            },
                        );
                        self.emit_to_func(
                            func,
                            IrInst::StoreOffset {
                                ptr: IrValue::Local(ptr_local.clone()),
                                offset: 0,
                                value: all_args[0].clone(),
                            },
                        );
                        return IrValue::Local(ptr_local);
                    }
                }

                if let Expr::ELam(params, body) = current {
                    let lambda_val = self.gen_lambda(params, body, type_checker, alloca_map, func);
                    let dest = self.new_local();
                    match lambda_val {
                        IrValue::Global(name) => {
                            self.emit_to_func(
                                func,
                                IrInst::Call {
                                    dest: IrValue::Local(dest.clone()),
                                    func: name,
                                    args: all_args,
                                },
                            );
                        }
                        IrValue::Local(closure_ptr) => {
                            self.emit_to_func(
                                func,
                                IrInst::ClosureCall {
                                    dest: IrValue::Local(dest.clone()),
                                    closure: IrValue::Local(closure_ptr),
                                    normal_args: all_args,
                                },
                            );
                        }
                        IrValue::Const(_) => {
                            self.emit_to_func(
                                func,
                                IrInst::Call {
                                    dest: IrValue::Local(dest.clone()),
                                    func: "unknown".to_string(),
                                    args: all_args,
                                },
                            );
                        }
                    }
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
                        let alloca_name = format!("_alloca_{}", ident.name);
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
                        merge_label.clone()
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
                                            else_target: next_check,
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
                                    self.gen_sub_pattern_checks(
                                        func,
                                        target_val.clone(),
                                        args,
                                        type_checker,
                                        merge_label.clone(),
                                        &mut arm_map,
                                        8,
                                    );
                                }
                                None => unconditional_arm(self, func),
                            }
                        }
                        Pattern::PVar(ident) => {
                            unconditional_arm(self, func);

                            let var_alloca = format!("_alloca_{}", ident.name);
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
                                merge_label.clone(),
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
            Expr::ELam(params, body) => {
                self.gen_lambda(params, body, type_checker, alloca_map, func)
            }
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
            Expr::ERegion(_, body) => {
                self.gen_expr_to_func_with_allocas(func, body, alloca_map, type_checker)
            }
            Expr::EConsume(e) => {
                self.gen_expr_to_func_with_allocas(func, e, alloca_map, type_checker)
            }
            Expr::EField(base, field_ident) => {
                let base_val =
                    self.gen_expr_to_func_with_allocas(func, base, alloca_map, type_checker);
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                if let Some((_union_name, _field_ty)) =
                    type_checker.find_union_field_by_name(&field_ident.name)
                {
                    let result_reg = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::LoadOffset {
                            dest: IrValue::Local(result_reg.clone()),
                            ptr: base_val,
                            offset: 0,
                        },
                    );
                    IrValue::Local(result_reg)
                } else if let Some((_struct_name, _variant_name, field_index, _field_ty)) =
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
                if type_checker
                    .find_union_field_by_name(&field_ident.name)
                    .is_some()
                {
                    self.emit_to_func(
                        func,
                        IrInst::StoreOffset {
                            ptr: base_val,
                            offset: 0,
                            value: value_val,
                        },
                    );
                    IrValue::Const(IrConst::Int(0, i64_ty))
                } else if let Some((_struct_name, _variant_name, field_index, _field_ty)) =
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
                    let sv = si.variants.first().unwrap();
                    if sv.fields.len() != args.len() {
                        return IrValue::Const(IrConst::Int(0, i64_ty));
                    }
                    let struct_size = (sv.fields.len() * 8) as i64;
                    let ptr_local = self.new_local();
                    self.emit_to_func(
                        func,
                        IrInst::HeapAlloc {
                            dest: IrValue::Local(ptr_local.clone()),
                            size: IrValue::Const(IrConst::Int(struct_size, i64_ty.clone())),
                        },
                    );
                    for (i, arg) in args.into_iter().enumerate() {
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
            Expr::EUnionCon(union_name, field_name, value) => {
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                if let Some(ui) = type_checker
                    .unions
                    .iter()
                    .find(|u| u.name == union_name.name)
                {
                    let field_info = ui
                        .fields
                        .iter()
                        .find(|(fname, _)| fname == &field_name.name);
                    match field_info {
                        Some((_, _fty)) => {
                            let value_val = self.gen_expr_to_func_with_allocas(
                                func,
                                value,
                                alloca_map,
                                type_checker,
                            );
                            let union_size = 8i64;
                            let ptr_local = self.new_local();
                            self.emit_to_func(
                                func,
                                IrInst::HeapAlloc {
                                    dest: IrValue::Local(ptr_local.clone()),
                                    size: IrValue::Const(IrConst::Int(union_size, i64_ty.clone())),
                                },
                            );
                            self.emit_to_func(
                                func,
                                IrInst::StoreOffset {
                                    ptr: IrValue::Local(ptr_local.clone()),
                                    offset: 0,
                                    value: value_val,
                                },
                            );
                            IrValue::Local(ptr_local)
                        }
                        None => IrValue::Const(IrConst::Int(0, i64_ty)),
                    }
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
            Type::TRegion(inner, name) => {
                TypeId::TCon(name.name.clone(), vec![self.type_to_id(inner)])
            }
            Type::TLinear(inner) => {
                TypeId::TCon("Linear".to_string(), vec![self.type_to_id(inner)])
            }
        }
    }

    fn emit_to_func(&mut self, func: &mut IrFunction, inst: IrInst) {
        if let Some(ref label) = self.current_block {
            if let Some(block) = func.blocks.iter_mut().find(|b| &b.label == label) {
                block.insts.push(inst);
            }
        }
    }

    fn new_local(&mut self) -> String {
        let name = format!("_local_{}", self.local_counter);
        self.local_counter += 1;
        name
    }

    fn new_block_label(&mut self) -> String {
        let name = format!("_block_{}", self.block_counter);
        self.block_counter += 1;
        name
    }
}
