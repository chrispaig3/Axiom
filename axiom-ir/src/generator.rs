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

        std::mem::replace(&mut self.module, IrModule::new())
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

    fn gen_expr_to_func_with_allocas(&mut self, func: &mut IrFunction, expr: &Expr, alloca_map: &mut HashMap<String, String>, type_checker: &TypeChecker) -> IrValue {
        match expr {
            Expr::ELit(lit, _) => self.gen_literal(lit),
            Expr::EVar(ident) => {
                for (idx, dt) in type_checker.data_types.iter().enumerate() {
                    for (cidx, con) in dt.constructors.iter().enumerate() {
                        if con.name == ident.name {
                            let tag = (idx * 100 + cidx) as i64;
                            return IrValue::Const(IrConst::Int(tag, TypeId::TCon("I64".to_string(), vec![])));
                        }
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
                loop {
                    if let Expr::EApp(inner_func, inner_arg) = current {
                        all_args.push(self.gen_expr_to_func_with_allocas(func, inner_arg, alloca_map, type_checker));
                        current = inner_func.as_ref();
                    } else {
                        break;
                    }
                }
                all_args.reverse();

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
                let result_alloca = self.new_local();
                self.emit_to_func(func, IrInst::Alloca {
                    dest: IrValue::Local(result_alloca.clone()),
                    ty: TypeId::TCon("I64".to_string(), vec![]),
                });

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

                    match pat {
                        Pattern::PCon(ident, ..) | Pattern::PVar(ident) => {
                            let mut con_tag: Option<i64> = None;
                            for (idx, dt) in type_checker.data_types.iter().enumerate() {
                                for (cidx, con) in dt.constructors.iter().enumerate() {
                                    if con.name == ident.name {
                                        con_tag = Some((idx * 100 + cidx) as i64);
                                        break;
                                    }
                                }
                                if con_tag.is_some() { break; }
                            }

                            if let Some(tag) = con_tag {
                                func.blocks.push(IrBlock {
                                    label: check_label.clone(),
                                    insts: Vec::new(),
                                });
                                self.current_block = Some(check_label.clone());

                                let cmp_dest = self.new_local();
                                self.emit_to_func(func, IrInst::Eq {
                                    dest: IrValue::Local(cmp_dest.clone()),
                                    lhs: target_val.clone(),
                                    rhs: IrValue::Const(IrConst::Int(tag, TypeId::TCon("I64".to_string(), vec![]))),
                                });
                                self.emit_to_func(func, IrInst::CondBr {
                                    cond: IrValue::Local(cmp_dest),
                                    then_target: arm_label.clone(),
                                    else_target: next_check,
                                });

                                func.blocks.push(IrBlock {
                                    label: arm_label.clone(),
                                    insts: Vec::new(),
                                });
                                self.current_block = Some(arm_label.clone());

                                if let Pattern::PCon(_, args) = pat {
                                    for arg_pat in args.iter() {
                                        if let Pattern::PVar(arg_ident) = arg_pat {
                                            let arg_alloca = format!("_alloca_{}", arg_ident.name);
                                            func.locals.push((arg_ident.name.clone(), TypeId::TCon("I64".to_string(), vec![])));
                                            self.emit_to_func(func, IrInst::Alloca {
                                                dest: IrValue::Local(arg_alloca.clone()),
                                                ty: TypeId::TCon("I64".to_string(), vec![]),
                                            });
                                            self.emit_to_func(func, IrInst::Store {
                                                ptr: IrValue::Local(arg_alloca.clone()),
                                                value: target_val.clone(),
                                            });
                                            arm_map.insert(arg_ident.name.clone(), arg_alloca);
                                        }
                                    }
                                }
                            } else {
                                func.blocks.push(IrBlock {
                                    label: check_label.clone(),
                                    insts: Vec::new(),
                                });
                                self.current_block = Some(check_label.clone());
                                self.emit_to_func(func, IrInst::Br { target: arm_label.clone() });

                                func.blocks.push(IrBlock {
                                    label: arm_label.clone(),
                                    insts: Vec::new(),
                                });
                                self.current_block = Some(arm_label.clone());

                                let var_alloca = format!("_alloca_{}", ident.name);
                                func.locals.push((ident.name.clone(), TypeId::TCon("I64".to_string(), vec![])));
                                self.emit_to_func(func, IrInst::Alloca {
                                    dest: IrValue::Local(var_alloca.clone()),
                                    ty: TypeId::TCon("I64".to_string(), vec![]),
                                });
                                self.emit_to_func(func, IrInst::Store {
                                    ptr: IrValue::Local(var_alloca.clone()),
                                    value: target_val.clone(),
                                });
                                arm_map.insert(ident.name.clone(), var_alloca);
                            }
                        }
                        Pattern::PWildcard => {
                            func.blocks.push(IrBlock {
                                label: check_label.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(check_label.clone());
                            self.emit_to_func(func, IrInst::Br { target: arm_label.clone() });

                            func.blocks.push(IrBlock {
                                label: arm_label.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(arm_label.clone());
                        }
                        _ => {
                            func.blocks.push(IrBlock {
                                label: check_label.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(check_label.clone());
                            self.emit_to_func(func, IrInst::Br { target: next_check });
                            func.blocks.push(IrBlock {
                                label: arm_label.clone(),
                                insts: Vec::new(),
                            });
                            self.current_block = Some(arm_label.clone());
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
