use axiom_ast::ast::*;
use axiom_ast::span::Ident;
use axiom_sema::TypeChecker;
use crate::{IrModule, IrFunction, IrBlock, IrInst, IrValue, IrConst, IrStruct, TypeId};
use std::collections::HashMap;

pub struct IrGen {
    module: IrModule,
    local_counter: usize,
    block_counter: usize,
    current_block: Option<String>,
}

/// Look up a data constructor by name across every `data` type the type
/// checker collected, returning:
///
/// * a globally-unique integer tag (`data_type_index * 100 +
///   constructor_index_within_that_type`) - unique across every
///   constructor in the program, not just within one `data` type, so two
///   different `data` types' constructors can never compare equal by
///   accident during pattern matching;
/// * its arity, decomposed from the constructor's curried arrow type
///   (`Field1 -> Field2 -> ... -> TheType`; zero `TArr`s means a nullary
///   constructor).
///
/// Both constructor *construction* (`EVar`/`EApp`, see
/// [`IrGen::gen_construct`]) and constructor *matching* (`ECase`) call
/// this, so a value built with one tag is always compared against that
/// exact same tag - there is exactly one place in the generator that
/// decides what a constructor's tag is.
fn find_constructor(type_checker: &TypeChecker, name: &str) -> Option<(i64, usize)> {
    for (idx, dt) in type_checker.data_types.iter().enumerate() {
        for (cidx, con) in dt.constructors.iter().enumerate() {
            if con.name == name {
                let tag = (idx * 100 + cidx) as i64;
                let arity = constructor_arity(&con.ty);
                return Some((tag, arity));
            }
        }
    }
    None
}

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
            current_block: None,
        }
    }

    pub fn generate(&mut self, ast_module: &Module, type_checker: &TypeChecker) -> IrModule {
        for decl in &ast_module.decls {
            match decl {
                Decl::DStruct { name, fields, repr, .. } => {
                    let packed = matches!(repr, Some(TypeRepr::Packed));
                    let align = if let Some(TypeRepr::Align(n)) = repr {
                        Some(*n)
                    } else {
                        None
                    };

                    let ir_fields: Vec<(String, TypeId)> = fields.iter()
                        .map(|f| (f.name.name.clone(), self.type_to_id(&f.ty)))
                        .collect();

                    self.module.structs.push(IrStruct {
                        name: name.name.clone(),
                        fields: ir_fields,
                        packed,
                        align,
                    });
                }
                Decl::DFn { name, params, body } => {
                    let func = self.gen_function(name, params, body, type_checker);
                    self.module.functions.push(func);
                }
                Decl::DSig { name, ty } => {
                    let _ = (name, ty);
                }
                _ => {}
            }
        }

        std::mem::take(&mut self.module)
    }

    fn gen_function(&mut self, name: &Ident, params: &[Pattern], body: &Expr, type_checker: &TypeChecker) -> IrFunction {
        let params: Vec<(String, TypeId)> = params.iter().filter_map(|p| {
            if let Pattern::PVar(ident) = p {
                Some((ident.name.clone(), TypeId::TCon("I64".to_string(), vec![])))
            } else {
                None
            }
        }).collect();

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
            self.emit_to_func(&mut func, IrInst::Alloca {
                dest: IrValue::Local(alloca_name.clone()),
                ty: pty.clone(),
            });
            self.emit_to_func(&mut func, IrInst::Store {
                ptr: IrValue::Local(alloca_name.clone()),
                value: IrValue::Local(pname.clone()),
            });
            alloca_map.insert(pname.clone(), alloca_name);
        }

        let body_val = self.gen_expr_to_func_with_allocas(&mut func, body, &mut alloca_map, type_checker);

        self.emit_to_func(&mut func, IrInst::Ret { value: Some(body_val) });

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

        self.emit_to_func(func, IrInst::HeapAlloc {
            dest: IrValue::Local(ptr_local.clone()),
            size: IrValue::Const(IrConst::Int(size, i64_ty.clone())),
        });
        self.emit_to_func(func, IrInst::StoreOffset {
            ptr: IrValue::Local(ptr_local.clone()),
            offset: 0,
            value: IrValue::Const(IrConst::Int(tag, i64_ty.clone())),
        });
        for (i, arg) in args.into_iter().enumerate() {
            self.emit_to_func(func, IrInst::StoreOffset {
                ptr: IrValue::Local(ptr_local.clone()),
                offset: ((1 + i) * 8) as i64,
                value: arg,
            });
        }

        IrValue::Local(ptr_local)
    }

    fn gen_expr_to_func_with_allocas(&mut self, func: &mut IrFunction, expr: &Expr, alloca_map: &mut HashMap<String, String>, type_checker: &TypeChecker) -> IrValue {
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
                    let _ty = func.locals.iter()
                        .find(|(n, _)| n == &ident.name)
                        .map(|(_, t)| t.clone())
                        .unwrap_or(TypeId::TCon("I64".to_string(), vec![]));
                    self.emit_to_func(func, IrInst::Load {
                        dest: IrValue::Local(dest.clone()),
                        ptr: IrValue::Local(alloca_name.clone()),
                    });
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
                    "+" => IrInst::Add { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    "-" => IrInst::Sub { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    "*" => IrInst::Mul { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    "/" => IrInst::Div { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    "%" => IrInst::Mod { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    "==" => IrInst::Eq { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    "!=" => IrInst::Neq { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    "<" => IrInst::Lt { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    ">" => IrInst::Gt { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    "<=" => IrInst::Le { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    ">=" => IrInst::Ge { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    "&&" => IrInst::And { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    "||" => IrInst::Or { dest: IrValue::Local(dest.clone()), lhs, rhs },
                    _ => IrInst::Add { dest: IrValue::Local(dest.clone()), lhs, rhs },
                };

                self.emit_to_func(func, inst);
                IrValue::Local(dest)
            }
            Expr::EApp(_func_expr, _arg_expr) => {
                let mut all_args: Vec<IrValue> = Vec::new();
                let mut current = expr;
                while let Expr::EApp(inner_func, inner_arg) = current {
                    all_args.push(self.gen_expr_to_func_with_allocas(func, inner_arg, alloca_map, type_checker));
                    current = inner_func.as_ref();
                }
                all_args.reverse();

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
                }

                if let Expr::ELam(params, body) = current {
                    let mut inline_map = alloca_map.clone();
                    let param_values: Vec<IrValue> = all_args;
                    for (i, pat) in params.iter().enumerate() {
                        if let Pattern::PVar(ident) = pat {
                            let val = param_values.get(i).cloned()
                                .unwrap_or(IrValue::Const(IrConst::Int(0, TypeId::TCon("I64".to_string(), vec![]))));
                            let alloca_name = format!("_alloca_{}", ident.name);
                            func.locals.push((ident.name.clone(), TypeId::TCon("I64".to_string(), vec![])));
                            self.emit_to_func(func, IrInst::Alloca {
                                dest: IrValue::Local(alloca_name.clone()),
                                ty: TypeId::TCon("I64".to_string(), vec![]),
                            });
                            self.emit_to_func(func, IrInst::Store {
                                ptr: IrValue::Local(alloca_name.clone()),
                                value: val,
                            });
                            inline_map.insert(ident.name.clone(), alloca_name);
                        }
                    }
                    return self.gen_expr_to_func_with_allocas(func, body, &mut inline_map, type_checker);
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
                        "+" => Some(IrInst::Add { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        "-" => Some(IrInst::Sub { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        "*" => Some(IrInst::Mul { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        "/" => Some(IrInst::Div { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        "%" => Some(IrInst::Mod { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        "==" => Some(IrInst::Eq { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        "!=" => Some(IrInst::Neq { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        "<" => Some(IrInst::Lt { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        ">" => Some(IrInst::Gt { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        "<=" => Some(IrInst::Le { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        ">=" => Some(IrInst::Ge { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        "&&" => Some(IrInst::And { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        "||" => Some(IrInst::Or { dest: IrValue::Local(dest.clone()), lhs, rhs }),
                        _ => None,
                    };
                    if let Some(inst) = inst {
                        self.emit_to_func(func, inst);
                        return IrValue::Local(dest);
                    }
                }

                self.emit_to_func(func, IrInst::Call {
                    dest: IrValue::Local(dest.clone()),
                    func: func_name,
                    args: all_args,
                });

                IrValue::Local(dest)
            }
            Expr::EIf(cond, then_expr, else_expr) => {
                let cond_val = self.gen_expr_to_func_with_allocas(func, cond, alloca_map, type_checker);
                let then_label = self.new_block_label();
                let else_label = self.new_block_label();
                let merge_label = self.new_block_label();
                let result_alloca = self.new_local();

                self.emit_to_func(func, IrInst::Alloca {
                    dest: IrValue::Local(result_alloca.clone()),
                    ty: TypeId::TCon("I64".to_string(), vec![]),
                });

                self.emit_to_func(func, IrInst::CondBr {
                    cond: cond_val,
                    then_target: then_label.clone(),
                    else_target: else_label.clone(),
                });

                func.blocks.push(IrBlock {
                    label: then_label.clone(),
                    insts: Vec::new(),
                });
                self.current_block = Some(then_label.clone());
                let then_val = self.gen_expr_to_func_with_allocas(func, then_expr, alloca_map, type_checker);
                self.emit_to_func(func, IrInst::Store {
                    ptr: IrValue::Local(result_alloca.clone()),
                    value: then_val,
                });
                self.emit_to_func(func, IrInst::Br { target: merge_label.clone() });

                func.blocks.push(IrBlock {
                    label: else_label.clone(),
                    insts: Vec::new(),
                });
                self.current_block = Some(else_label.clone());
                let else_val = self.gen_expr_to_func_with_allocas(func, else_expr, alloca_map, type_checker);
                self.emit_to_func(func, IrInst::Store {
                    ptr: IrValue::Local(result_alloca.clone()),
                    value: else_val,
                });
                self.emit_to_func(func, IrInst::Br { target: merge_label.clone() });

                func.blocks.push(IrBlock {
                    label: merge_label.clone(),
                    insts: Vec::new(),
                });
                self.current_block = Some(merge_label.clone());

                let load_dest = self.new_local();
                self.emit_to_func(func, IrInst::Load {
                    dest: IrValue::Local(load_dest.clone()),
                    ptr: IrValue::Local(result_alloca),
                });
                IrValue::Local(load_dest)
            }
            Expr::ELet(bindings, body) => {
                for (pat, init) in bindings {
                    if let Pattern::PVar(ident) = pat {
                        let value = self.gen_expr_to_func_with_allocas(func, init, alloca_map, type_checker);
                        let alloca_name = format!("_alloca_{}", ident.name);
                        func.locals.push((ident.name.clone(), TypeId::TCon("I64".to_string(), vec![])));
                        self.emit_to_func(func, IrInst::Alloca {
                            dest: IrValue::Local(alloca_name.clone()),
                            ty: TypeId::TCon("I64".to_string(), vec![]),
                        });
                        self.emit_to_func(func, IrInst::Store {
                            ptr: IrValue::Local(alloca_name.clone()),
                            value,
                        });
                        alloca_map.insert(ident.name.clone(), alloca_name);
                    }
                }
                self.gen_expr_to_func_with_allocas(func, body, alloca_map, type_checker)
            }
            Expr::ECase(target, arms) => {
                let target_val = self.gen_expr_to_func_with_allocas(func, target, alloca_map, type_checker);
                let i64_ty = TypeId::TCon("I64".to_string(), vec![]);
                let result_alloca = self.new_local();
                self.emit_to_func(func, IrInst::Alloca {
                    dest: IrValue::Local(result_alloca.clone()),
                    ty: i64_ty.clone(),
                });

                // Load the scrutinee's tag *once*, up front, rather than
                // re-deriving "is this a constructor value" per arm - every
                // `PCon` arm below compares against this same loaded tag,
                // and every arm agrees on what a given constructor's tag is
                // because both this and construction (`gen_construct`) go
                // through the one shared `find_constructor` lookup. Only
                // emitted when at least one arm actually needs it: a `case`
                // over a plain `Int`/`Bool` scrutinee with only
                // `PLit`/`PVar`/`PWildcard` arms has nothing to unbox.
                let needs_tag = arms.iter().any(|(pat, _)| {
                    matches!(pat, Pattern::PCon(ident, ..) if find_constructor(type_checker, &ident.name).is_some())
                });
                let tag_val = if needs_tag {
                    let tag_local = self.new_local();
                    self.emit_to_func(func, IrInst::LoadOffset {
                        dest: IrValue::Local(tag_local.clone()),
                        ptr: target_val.clone(),
                        offset: 0,
                    });
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
                    self.emit_to_func(func, IrInst::Br { target: check_labels[0].clone() });
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
                        func.blocks.push(IrBlock { label: check_label.clone(), insts: Vec::new() });
                        gen.current_block = Some(check_label.clone());
                        gen.emit_to_func(func, IrInst::Br { target: arm_label.clone() });
                        func.blocks.push(IrBlock { label: arm_label.clone(), insts: Vec::new() });
                        gen.current_block = Some(arm_label.clone());
                    };

                    match pat {
                        Pattern::PCon(ident, args) => {
                            match find_constructor(type_checker, &ident.name) {
                                Some((tag, _arity)) => {
                                    func.blocks.push(IrBlock { label: check_label.clone(), insts: Vec::new() });
                                    self.current_block = Some(check_label.clone());

                                    let cmp_dest = self.new_local();
                                    self.emit_to_func(func, IrInst::Eq {
                                        dest: IrValue::Local(cmp_dest.clone()),
                                        lhs: tag_val.clone().expect("needs_tag scan above must have found this arm"),
                                        rhs: IrValue::Const(IrConst::Int(tag, i64_ty.clone())),
                                    });
                                    self.emit_to_func(func, IrInst::CondBr {
                                        cond: IrValue::Local(cmp_dest),
                                        then_target: arm_label.clone(),
                                        else_target: next_check,
                                    });

                                    func.blocks.push(IrBlock { label: arm_label.clone(), insts: Vec::new() });
                                    self.current_block = Some(arm_label.clone());

                                    // Bind each `PVar` field sub-pattern to
                                    // the actual field extracted from the
                                    // scrutinee's boxed payload (word `1 +
                                    // i`), not to the whole scrutinee value
                                    // - `(case v ((Just x) x))` now binds
                                    // `x` to the argument `Just` was
                                    // constructed with. Non-`PVar`
                                    // sub-patterns (nested constructors,
                                    // literals, wildcards) are left
                                    // unbound and uncompared: nested
                                    // pattern matching one level deep isn't
                                    // implemented yet, matching this
                                    // generator's other documented
                                    // pattern-matching limitations.
                                    for (field_idx, arg_pat) in args.iter().enumerate() {
                                        if let Pattern::PVar(arg_ident) = arg_pat {
                                            let field_local = self.new_local();
                                            self.emit_to_func(func, IrInst::LoadOffset {
                                                dest: IrValue::Local(field_local.clone()),
                                                ptr: target_val.clone(),
                                                offset: ((1 + field_idx) * 8) as i64,
                                            });
                                            let arg_alloca = format!("_alloca_{}", arg_ident.name);
                                            func.locals.push((arg_ident.name.clone(), i64_ty.clone()));
                                            self.emit_to_func(func, IrInst::Alloca {
                                                dest: IrValue::Local(arg_alloca.clone()),
                                                ty: i64_ty.clone(),
                                            });
                                            self.emit_to_func(func, IrInst::Store {
                                                ptr: IrValue::Local(arg_alloca.clone()),
                                                value: IrValue::Local(field_local),
                                            });
                                            arm_map.insert(arg_ident.name.clone(), arg_alloca);
                                        }
                                    }
                                }
                                None => unconditional_arm(self, func),
                            }
                        }
                        Pattern::PVar(ident) => {
                            unconditional_arm(self, func);

                            let var_alloca = format!("_alloca_{}", ident.name);
                            func.locals.push((ident.name.clone(), i64_ty.clone()));
                            self.emit_to_func(func, IrInst::Alloca {
                                dest: IrValue::Local(var_alloca.clone()),
                                ty: i64_ty.clone(),
                            });
                            self.emit_to_func(func, IrInst::Store {
                                ptr: IrValue::Local(var_alloca.clone()),
                                value: target_val.clone(),
                            });
                            arm_map.insert(ident.name.clone(), var_alloca);
                        }
                        Pattern::PWildcard => unconditional_arm(self, func),
                        Pattern::PLit(lit) => {
                            // Literal patterns compare the scrutinee's raw
                            // value directly - never the boxed-constructor
                            // tag - since a `PLit` arm only ever appears
                            // when matching a plain `Int`/`Bool`/`Char`
                            // scrutinee, which is never heap-boxed.
                            func.blocks.push(IrBlock { label: check_label.clone(), insts: Vec::new() });
                            self.current_block = Some(check_label.clone());

                            let lit_val = self.gen_literal(lit);
                            let cmp_dest = self.new_local();
                            self.emit_to_func(func, IrInst::Eq {
                                dest: IrValue::Local(cmp_dest.clone()),
                                lhs: target_val.clone(),
                                rhs: lit_val,
                            });
                            self.emit_to_func(func, IrInst::CondBr {
                                cond: IrValue::Local(cmp_dest),
                                then_target: arm_label.clone(),
                                else_target: next_check,
                            });

                            func.blocks.push(IrBlock { label: arm_label.clone(), insts: Vec::new() });
                            self.current_block = Some(arm_label.clone());
                        }
                        Pattern::PTuple(_) | Pattern::PList(_) => {
                            // Tuples/lists have no runtime representation
                            // at all yet (see the README's Implementation
                            // Status table), so there is nothing to
                            // compare against here yet either. Previously
                            // this fell into a catch-all that emitted an
                            // unconditional `Br` to `next_check` - i.e. the
                            // arm was silently *dead code*, never taken no
                            // matter what. Falling through to the arm
                            // instead (same as a wildcard) is the more
                            // useful of two still-wrong options for an
                            // unimplemented feature: it at least lets
                            // single-arm `case`s over a tuple/list "work"
                            // (by definitely running that one arm) instead
                            // of unconditionally skipping every such arm.
                            unconditional_arm(self, func);
                        }
                    }

                    let body_val = self.gen_expr_to_func_with_allocas(func, body, &mut arm_map, type_checker);
                    self.emit_to_func(func, IrInst::Store {
                        ptr: IrValue::Local(result_alloca.clone()),
                        value: body_val,
                    });
                    self.emit_to_func(func, IrInst::Br { target: merge_label.clone() });
                }

                func.blocks.push(IrBlock {
                    label: merge_label.clone(),
                    insts: Vec::new(),
                });
                self.current_block = Some(merge_label.clone());

                let load_dest = self.new_local();
                self.emit_to_func(func, IrInst::Load {
                    dest: IrValue::Local(load_dest.clone()),
                    ptr: IrValue::Local(result_alloca),
                });
                IrValue::Local(load_dest)
            }
            Expr::EBegin(exprs) => {
                let mut last_val = IrValue::Const(IrConst::Int(0, TypeId::TCon("I64".to_string(), vec![])));
                for e in exprs {
                    last_val = self.gen_expr_to_func_with_allocas(func, e, alloca_map, type_checker);
                }
                last_val
            }
            Expr::ECast(inner, target_type) => {
                let src = self.gen_expr_to_func_with_allocas(func, inner, alloca_map, type_checker);
                let dest = self.new_local();
                let target_ty = self.type_to_id(target_type);

                self.emit_to_func(func, IrInst::Cast {
                    dest: IrValue::Local(dest.clone()),
                    src,
                    target_ty,
                });

                IrValue::Local(dest)
            }
            Expr::ESizeof(ty, _) => {
                let dest = self.new_local();
                let resolved_ty = self.type_to_id(ty);
                self.emit_to_func(func, IrInst::Sizeof {
                    dest: IrValue::Local(dest.clone()),
                    ty: resolved_ty,
                });
                IrValue::Local(dest)
            }
            Expr::EAlignof(ty, _) => {
                let dest = self.new_local();
                let resolved_ty = self.type_to_id(ty);
                self.emit_to_func(func, IrInst::Alignof {
                    dest: IrValue::Local(dest.clone()),
                    ty: resolved_ty,
                });
                IrValue::Local(dest)
            }
            Expr::EGrouped(inner) => self.gen_expr_to_func_with_allocas(func, inner, alloca_map, type_checker),
            _ => IrValue::Const(IrConst::Int(0, TypeId::TCon("I64".to_string(), vec![]))),
        }
    }

    fn gen_literal(&self, lit: &Literal) -> IrValue {
        match lit {
            Literal::LInt(n) => IrValue::Const(IrConst::Int(*n, TypeId::TCon("I64".to_string(), vec![]))),
            Literal::LFloat(n) => IrValue::Const(IrConst::Float(*n, TypeId::TCon("F64".to_string(), vec![]))),
            Literal::LBool(b) => IrValue::Const(IrConst::Bool(*b)),
            Literal::LChar(c) => IrValue::Const(IrConst::Int(*c as i64, TypeId::TCon("U8".to_string(), vec![]))),
            Literal::LStr(s) => IrValue::Const(IrConst::Str(s.clone())),
        }
    }

    fn type_to_id(&self, ty: &Type) -> TypeId {
        match ty {
            Type::TCon(ident, _) => {
                match ident.name.as_str() {
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
                }
            }
            Type::TPtr(inner, mutable) => {
                TypeId::TPtr(Box::new(self.type_to_id(inner)), *mutable)
            }
            Type::TList(inner) => {
                TypeId::TList(Box::new(self.type_to_id(inner)))
            }
            Type::TTuple(_) => TypeId::TTuple(vec![]),
            Type::TArr(from, to) => {
                TypeId::TArr(Box::new(self.type_to_id(from)), Box::new(self.type_to_id(to)))
            }
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
