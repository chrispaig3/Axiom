use axiom_ir::*;
use axiom_sema::TypeId;
use std::collections::{HashMap, HashSet};
use std::fmt::Write;

pub struct LlvmCodeGen {
    output: String,
    type_counter: usize,
    local_counter: usize,
    struct_types: HashMap<String, usize>,
    enum_types: HashMap<String, usize>,
    current_func: Option<String>,
    locals: HashMap<String, (String, TypeId)>,
    ssa_values: HashMap<String, (String, TypeId)>,
    string_ids: HashMap<String, usize>,
    extern_decls: HashSet<String>,
}

impl Default for LlvmCodeGen {
    fn default() -> Self {
        Self::new()
    }
}

impl LlvmCodeGen {
    pub fn new() -> Self {
        Self {
            output: String::new(),
            type_counter: 0,
            local_counter: 0,
            struct_types: HashMap::new(),
            enum_types: HashMap::new(),
            current_func: None,
            locals: HashMap::new(),
            ssa_values: HashMap::new(),
            string_ids: HashMap::new(),
            extern_decls: HashSet::new(),
        }
    }

    pub fn compile(&mut self, ir_module: &IrModule) -> Result<String, String> {
        writeln!(self.output, "; Axiom compiled LLVM IR").unwrap();
        writeln!(self.output, "target triple = \"arm64-apple-macosx14.0.0\"").unwrap();
        writeln!(self.output).unwrap();

        self.declare_extern_funcs();

        for (name, params, ret) in &ir_module.extern_funcs {
            if self.extern_decls.insert(name.clone()) {
                let params_str = params
                    .iter()
                    .map(|t| self.type_to_llvm(t))
                    .collect::<Vec<_>>()
                    .join(", ");
                let ret_str = self.type_to_llvm(ret);
                writeln!(self.output, "declare {} @{}({})", ret_str, name, params_str).unwrap();
            }
        }

        writeln!(self.output).unwrap();

        // Collect and emit string constants first
        let mut str_id = 0;
        let mut strings: Vec<(usize, String)> = Vec::new();

        for func in &ir_module.functions {
            for block in &func.blocks {
                for inst in &block.insts {
                    if let IrInst::Call { args, .. } = inst {
                        for arg in args {
                            if let IrValue::Const(IrConst::Str(s)) = arg {
                                if !self.string_ids.contains_key(s) {
                                    self.string_ids.insert(s.clone(), str_id);
                                    strings.push((str_id, s.clone()));
                                    str_id += 1;
                                }
                            }
                        }
                    }
                }
            }
        }
        for global in &ir_module.globals {
            if let IrConst::Str(s) = &global.value {
                if !self.string_ids.contains_key(s) {
                    self.string_ids.insert(s.clone(), str_id);
                    strings.push((str_id, s.clone()));
                    str_id += 1;
                }
            }
        }

        for (id, s) in &strings {
            let escaped = escape_llvm_string(s);
            writeln!(
                self.output,
                "@str_{} = private unnamed_addr constant [{} x i8] c\"{}\\00\", align 1",
                id,
                s.len() + 1,
                escaped
            )
            .unwrap();
        }
        if !strings.is_empty() {
            writeln!(self.output).unwrap();
        }

        for ir_struct in &ir_module.structs {
            self.declare_struct(ir_struct);
        }
        writeln!(self.output).unwrap();

        for ir_enum in &ir_module.enums {
            self.declare_enum(ir_enum);
        }
        writeln!(self.output).unwrap();

        for global in &ir_module.globals {
            self.declare_global(global);
        }
        writeln!(self.output).unwrap();

        for ir_func in &ir_module.functions {
            self.define_function(ir_func)?;
        }

        Ok(self.output.clone())
    }

    fn declare_extern_funcs(&mut self) {
        let hardcoded = [
            ("printf", "i32", "ptr, ..."),
            ("puts", "i32", "ptr"),
            ("malloc", "ptr", "i64"),
            ("free", "void", "ptr"),
            ("memset", "ptr", "ptr, i32, i64"),
            ("memcpy", "ptr", "ptr, ptr, i64"),
            ("exit", "void", "i32"),
        ];
        for (name, ret, params) in &hardcoded {
            writeln!(self.output, "declare {} @{}({})", ret, name, params).unwrap();
            self.extern_decls.insert(name.to_string());
        }
    }

    fn declare_struct(&mut self, ir_struct: &IrStruct) {
        let type_id = self.type_counter;
        self.type_counter += 1;
        self.struct_types.insert(ir_struct.name.clone(), type_id);

        let fields: Vec<String> = ir_struct
            .fields
            .iter()
            .map(|(_, ty)| self.type_to_llvm(ty))
            .collect();

        let packed = if ir_struct.packed { "<{ " } else { "{ " };
        let packed_end = if ir_struct.packed { " }>" } else { " }" };

        writeln!(
            self.output,
            "%struct.{} = type {}{}{}",
            type_id,
            packed,
            fields.join(", "),
            packed_end,
        )
        .unwrap();
    }

    fn declare_enum(&mut self, ir_enum: &IrEnum) {
        let type_id = self.type_counter;
        self.type_counter += 1;
        self.enum_types.insert(ir_enum.name.clone(), type_id);

        let variant_types: Vec<String> = ir_enum
            .variants
            .iter()
            .map(|(_, opt_ty)| match opt_ty {
                Some(ty) => self.type_to_llvm(ty),
                None => "i64".to_string(),
            })
            .collect();

        writeln!(
            self.output,
            "%union.{} = type {{ {} }}",
            type_id,
            variant_types.join(", "),
        )
        .unwrap();
        writeln!(
            self.output,
            "%struct.{} = type {{ i64, %union.{} }}",
            type_id, type_id,
        )
        .unwrap();
    }

    fn declare_global(&mut self, global: &IrGlobal) {
        let _ty = self.type_to_llvm(&global.ty);
        let value = self.const_to_llvm(&global.value);
        let const_str = if global.is_const {
            "constant"
        } else {
            "global"
        };

        writeln!(self.output, "@{} = {} {}", global.name, const_str, value,).unwrap();
    }

    fn define_function(&mut self, ir_func: &IrFunction) -> Result<(), String> {
        self.current_func = Some(ir_func.name.clone());
        self.locals.clear();
        self.ssa_values.clear();

        let params: Vec<String> = ir_func
            .params
            .iter()
            .map(|(name, ty)| {
                let llvm_ty = self.type_to_llvm(ty);
                format!("{} %{}", llvm_ty, name)
            })
            .collect();

        let return_type = if ir_func.return_type == TypeId::TCon("Void".to_string(), vec![]) {
            "void".to_string()
        } else {
            self.type_to_llvm(&ir_func.return_type)
        };

        writeln!(
            self.output,
            "define {} @{}({}) {{",
            return_type,
            ir_func.name,
            params.join(", "),
        )
        .unwrap();

        for block in &ir_func.blocks {
            writeln!(self.output, "{}:", block.label).unwrap();

            for inst in &block.insts {
                self.emit_inst(inst)?;
            }
        }

        if !ir_func.blocks.last().is_some_and(|b| {
            b.insts.iter().any(|i| {
                matches!(
                    i,
                    IrInst::Ret { .. } | IrInst::Br { .. } | IrInst::CondBr { .. }
                )
            })
        }) {
            if ir_func.return_type == TypeId::TCon("Void".to_string(), vec![]) {
                writeln!(self.output, "  ret void").unwrap();
            } else {
                writeln!(
                    self.output,
                    "  ret {} 0",
                    self.type_to_llvm(&ir_func.return_type)
                )
                .unwrap();
            }
        }

        writeln!(self.output, "}}").unwrap();
        writeln!(self.output).unwrap();

        Ok(())
    }

    fn emit_inst(&mut self, inst: &IrInst) -> Result<(), String> {
        match inst {
            IrInst::Const { dest, value } => {
                if let IrValue::Local(name) = dest {
                    if let Some((alloca_name, ty)) = self.locals.get(name) {
                        let llvm_ty = self.type_to_llvm(ty);
                        let const_val = self.const_to_llvm(value);
                        writeln!(
                            self.output,
                            "  store {} {}, ptr {}",
                            llvm_ty, const_val, alloca_name
                        )
                        .unwrap();
                    }
                }
            }
            IrInst::Add { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = add i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::Sub { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = sub i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::Mul { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = mul i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::Div { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = sdiv i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::Mod { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = srem i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::And { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = and i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::Or { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = or i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::Eq { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = icmp eq i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("Bool".to_string(), vec![])),
                    );
                }
            }
            IrInst::Neq { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = icmp ne i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("Bool".to_string(), vec![])),
                    );
                }
            }
            IrInst::Lt { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = icmp slt i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("Bool".to_string(), vec![])),
                    );
                }
            }
            IrInst::Gt { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = icmp sgt i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("Bool".to_string(), vec![])),
                    );
                }
            }
            IrInst::Le { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = icmp sle i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("Bool".to_string(), vec![])),
                    );
                }
            }
            IrInst::Ge { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = icmp sge i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("Bool".to_string(), vec![])),
                    );
                }
            }
            IrInst::Not { dest, src } => {
                let src_val = self.value_to_llvm(src)?;
                let result_reg = self.new_local_reg();
                writeln!(self.output, "  {} = xor i1 {}, true", result_reg, src_val).unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("Bool".to_string(), vec![])),
                    );
                }
            }
            IrInst::Neg { dest, src } => {
                let src_val = self.value_to_llvm(src)?;
                let result_reg = self.new_local_reg();
                writeln!(self.output, "  {} = sub i64 0, {}", result_reg, src_val).unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::BitAnd { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = and i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::BitOr { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = or i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::BitXor { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = xor i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::Shl { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = shl i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::Shr { dest, lhs, rhs } => {
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = ashr i64 {}, {}",
                    result_reg, lhs_val, rhs_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::Load { dest, ptr } => {
                let ptr_val = self.value_to_ptr(ptr)?;
                if let IrValue::Local(dest_name) = dest {
                    let ty = if let IrValue::Local(ptr_name) = ptr {
                        self.locals
                            .get(ptr_name)
                            .map(|(_, t)| t.clone())
                            .unwrap_or(TypeId::TCon("I64".to_string(), vec![]))
                    } else {
                        TypeId::TCon("I64".to_string(), vec![])
                    };
                    let llvm_ty = self.type_to_llvm(&ty);
                    let result_reg = self.new_local_reg();
                    writeln!(
                        self.output,
                        "  {} = load {}, ptr {}",
                        result_reg, llvm_ty, ptr_val
                    )
                    .unwrap();
                    self.ssa_values.insert(dest_name.clone(), (result_reg, ty));
                }
            }
            IrInst::Store { ptr, value } => {
                let ptr_val = self.value_to_ptr(ptr)?;
                let (val_str, ty_str) = self.value_to_typed_string(value)?;
                writeln!(
                    self.output,
                    "  store {} {}, ptr {}",
                    ty_str, val_str, ptr_val
                )
                .unwrap();
            }
            IrInst::Alloca { dest, ty } => {
                let llvm_ty = self.type_to_llvm(ty);
                if let IrValue::Local(name) = dest {
                    let alloca_name = if name.starts_with("_alloca_") {
                        format!("%{}", name)
                    } else {
                        format!("%_alloca_{}", name)
                    };
                    writeln!(self.output, "  {} = alloca {}", alloca_name, llvm_ty).unwrap();
                    self.locals.insert(name.clone(), (alloca_name, ty.clone()));
                }
            }
            IrInst::Call { dest, func, args } => {
                let arg_values: Vec<String> = args
                    .iter()
                    .map(|a| match a {
                        IrValue::Const(IrConst::Int(n, _)) => format!("i64 {}", n),
                        IrValue::Const(IrConst::Float(n, _)) => format!("double {}", n),
                        IrValue::Const(IrConst::Bool(b)) => {
                            format!("i1 {}", if *b { "true" } else { "false" })
                        }
                        IrValue::Const(IrConst::Null) => "ptr null".to_string(),
                        IrValue::Const(IrConst::Str(s)) => {
                            let id = self.string_ids.get(s).unwrap_or(&0);
                            format!("ptr @str_{}", id)
                        }
                        IrValue::Local(name) => {
                            if let Some((reg, ty)) = self.ssa_values.get(name) {
                                let llvm_ty = self.type_to_llvm(ty);
                                format!("{} {}", llvm_ty, reg)
                            } else if let Some((reg, ty)) = self.locals.get(name) {
                                let llvm_ty = self.type_to_llvm(ty);
                                if reg.starts_with("%_t") {
                                    format!("{} {}", llvm_ty, reg)
                                } else {
                                    format!("{} %{}", llvm_ty, name)
                                }
                            } else {
                                format!("i64 %{}", name)
                            }
                        }
                        IrValue::Global(name) => format!("ptr @{}", name),
                    })
                    .collect();

                if let IrValue::Local(name) = dest {
                    let result_reg = self.new_local_reg();
                    let func_name = if func.chars().any(|c| {
                        matches!(
                            c,
                            '+' | '-' | '*' | '/' | '%' | '<' | '>' | '=' | '!' | '&' | '|' | '^'
                        )
                    }) {
                        format!(r#"@"{}""#, func)
                    } else {
                        format!("@{}", func)
                    };

                    let ret_ty = match func.as_str() {
                        "==" | "!=" | "<" | ">" | "<=" | ">=" | "&&" | "||" => "i1",
                        _ => "i64",
                    };

                    let is_variadic = func == "printf";
                    if is_variadic {
                        writeln!(
                            self.output,
                            "  {} = call i32 (ptr, ...) {}({})",
                            result_reg,
                            func_name,
                            arg_values.join(", "),
                        )
                        .unwrap();
                    } else {
                        writeln!(
                            self.output,
                            "  {} = call {} {}({})",
                            result_reg,
                            ret_ty,
                            func_name,
                            arg_values.join(", "),
                        )
                        .unwrap();
                    }
                    let ret_type = if ret_ty == "i1" {
                        TypeId::TCon("Bool".to_string(), vec![])
                    } else {
                        TypeId::TCon("I64".to_string(), vec![])
                    };
                    self.ssa_values.insert(name.clone(), (result_reg, ret_type));
                }
            }
            IrInst::Ret { value } => {
                if let Some(val) = value {
                    let (val_str, ty_str) = self.value_to_typed_string(val)?;
                    writeln!(self.output, "  ret {} {}", ty_str, val_str).unwrap();
                } else {
                    writeln!(self.output, "  ret void").unwrap();
                }
            }
            IrInst::Br { target } => {
                writeln!(self.output, "  br label %{}", target).unwrap();
            }
            IrInst::CondBr {
                cond,
                then_target,
                else_target,
            } => {
                let cond_val = self.value_to_llvm(cond)?;
                writeln!(
                    self.output,
                    "  br i1 {}, label %{}, label %{}",
                    cond_val, then_target, else_target
                )
                .unwrap();
            }
            IrInst::Cast {
                dest,
                src,
                target_ty,
            } => {
                let src_val = self.value_to_llvm(src)?;
                let target_llvm = self.type_to_llvm(target_ty);
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = trunc i64 {} to {}",
                    result_reg, src_val, target_llvm
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values
                        .insert(name.clone(), (result_reg, target_ty.clone()));
                }
            }
            IrInst::Sizeof { dest, ty } => {
                let size = self.type_size(ty);
                let result_reg = self.new_local_reg();
                writeln!(self.output, "  {} = add i64 0, {}", result_reg, size).unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::Alignof { dest, ty } => {
                let align = self.type_align(ty);
                let result_reg = self.new_local_reg();
                writeln!(self.output, "  {} = add i64 0, {}", result_reg, align).unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::HeapAlloc { dest, size } => {
                let size_val = self.value_to_llvm(size)?;
                // `malloc` is declared to return `ptr`, so the call itself
                // must say `ptr` too (LLVM requires a call site's type to
                // match the callee's declared signature) - then
                // immediately convert to `i64` so every later
                // Store/LoadOffset on this value can keep treating it as
                // the same plain integer address every other IR value
                // already is.
                let ptr_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = call ptr @malloc(i64 {})",
                    ptr_reg, size_val
                )
                .unwrap();
                let addr_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = ptrtoint ptr {} to i64",
                    addr_reg, ptr_reg
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (addr_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::StoreOffset { ptr, offset, value } => {
                let ptr_val = self.value_to_llvm(ptr)?;
                let val_str = self.value_to_llvm(value)?;
                let addr_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = add i64 {}, {}",
                    addr_reg, ptr_val, offset
                )
                .unwrap();
                let field_ptr_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = inttoptr i64 {} to ptr",
                    field_ptr_reg, addr_reg
                )
                .unwrap();
                writeln!(
                    self.output,
                    "  store i64 {}, ptr {}",
                    val_str, field_ptr_reg
                )
                .unwrap();
            }
            IrInst::LoadOffset { dest, ptr, offset } => {
                let ptr_val = self.value_to_llvm(ptr)?;
                let addr_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = add i64 {}, {}",
                    addr_reg, ptr_val, offset
                )
                .unwrap();
                let field_ptr_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = inttoptr i64 {} to ptr",
                    field_ptr_reg, addr_reg
                )
                .unwrap();
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = load i64, ptr {}",
                    result_reg, field_ptr_reg
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::ClosureAlloc {
                dest,
                func_ptr,
                captures,
            } => {
                let captures_len = captures.len();
                let closure_size = ((1 + captures_len) * 8) as i64;
                let size_val = IrValue::Const(IrConst::Int(
                    closure_size,
                    TypeId::TCon("I64".to_string(), vec![]),
                ));
                let size_llvm = self.value_to_llvm(&size_val)?;
                let ptr_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = call ptr @malloc(i64 {})",
                    ptr_reg, size_llvm
                )
                .unwrap();
                let addr_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = ptrtoint ptr {} to i64",
                    addr_reg, ptr_reg
                )
                .unwrap();
                let func_ptr_llvm = self.value_to_llvm(func_ptr)?;
                writeln!(
                    self.output,
                    "  store i64 {}, ptr {}",
                    func_ptr_llvm, addr_reg
                )
                .unwrap();
                for (i, cap) in captures.iter().enumerate() {
                    let cap_llvm = self.value_to_llvm(cap)?;
                    let offset_reg = self.new_local_reg();
                    writeln!(
                        self.output,
                        "  {} = add i64 {}, {}",
                        offset_reg,
                        addr_reg,
                        ((i + 1) * 8) as i64
                    )
                    .unwrap();
                    let field_ptr_reg = self.new_local_reg();
                    writeln!(
                        self.output,
                        "  {} = inttoptr i64 {} to ptr",
                        field_ptr_reg, offset_reg
                    )
                    .unwrap();
                    writeln!(
                        self.output,
                        "  store i64 {}, ptr {}",
                        cap_llvm, field_ptr_reg
                    )
                    .unwrap();
                }
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (addr_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::ClosureCall {
                dest,
                closure,
                normal_args,
            } => {
                let closure_llvm = self.value_to_llvm(closure)?;
                let func_ptr_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = load i64, ptr {}",
                    func_ptr_reg, closure_llvm
                )
                .unwrap();
                let mut args_llvm = Vec::new();
                for cap_idx in 0.. {
                    let offset_reg = self.new_local_reg();
                    writeln!(
                        self.output,
                        "  {} = add i64 {}, {}",
                        offset_reg,
                        closure_llvm,
                        ((cap_idx + 1) * 8) as i64
                    )
                    .unwrap();
                    let field_ptr_reg = self.new_local_reg();
                    writeln!(
                        self.output,
                        "  {} = inttoptr i64 {} to ptr",
                        field_ptr_reg, offset_reg
                    )
                    .unwrap();
                    let load_reg = self.new_local_reg();
                    writeln!(
                        self.output,
                        "  {} = load i64, ptr {}",
                        load_reg, field_ptr_reg
                    )
                    .unwrap();
                    args_llvm.push(load_reg);
                }
                for arg in normal_args {
                    args_llvm.push(self.value_to_llvm(arg)?);
                }
                let func_ptr_llvm = format!("%{}", func_ptr_reg);
                let dest_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = call i64 {}({})",
                    dest_reg,
                    func_ptr_llvm,
                    args_llvm
                        .iter()
                        .map(|a| format!("i64 %{}", a))
                        .collect::<Vec<_>>()
                        .join(", ")
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (dest_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
        }

        Ok(())
    }

    fn value_to_llvm(&self, value: &IrValue) -> Result<String, String> {
        match value {
            IrValue::Local(name) => {
                if let Some((reg, _)) = self.ssa_values.get(name) {
                    Ok(reg.clone())
                } else if let Some((alloca_reg, _)) = self.locals.get(name) {
                    if alloca_reg.starts_with("%_t") {
                        Ok(alloca_reg.clone())
                    } else {
                        Ok(format!("%_load_{}", name))
                    }
                } else {
                    Ok(format!("%{}", name))
                }
            }
            IrValue::Global(name) => Ok(format!("@{}", name)),
            IrValue::Const(const_val) => Ok(self.const_to_llvm_value(const_val)),
        }
    }

    fn value_to_typed_string(&self, value: &IrValue) -> Result<(String, String), String> {
        match value {
            IrValue::Local(name) => {
                if let Some((reg, ty)) = self.ssa_values.get(name) {
                    let llvm_ty = self.type_to_llvm(ty);
                    Ok((reg.clone(), llvm_ty))
                } else if let Some((alloca_reg, ty)) = self.locals.get(name) {
                    let llvm_ty = self.type_to_llvm(ty);
                    if alloca_reg.starts_with("%_t") {
                        Ok((alloca_reg.clone(), llvm_ty))
                    } else {
                        Ok((format!("%_load_{}", name), llvm_ty))
                    }
                } else {
                    Ok((format!("%{}", name), "i64".to_string()))
                }
            }
            IrValue::Global(name) => Ok((format!("@{}", name), "ptr".to_string())),
            IrValue::Const(const_val) => match const_val {
                IrConst::Int(n, ty) => {
                    let llvm_ty = self.type_to_llvm(ty);
                    Ok((format!("{}", n), llvm_ty))
                }
                IrConst::Float(n, ty) => {
                    let llvm_ty = self.type_to_llvm(ty);
                    Ok((format!("{}", n), llvm_ty))
                }
                IrConst::Bool(b) => Ok((
                    (if *b { "true" } else { "false" }).to_string(),
                    "i1".to_string(),
                )),
                IrConst::Null => Ok(("null".to_string(), "ptr".to_string())),
                IrConst::Str(s) => {
                    let id = self.string_ids.get(s).unwrap_or(&0);
                    Ok((format!("ptr @str_{}", id), "ptr".to_string()))
                }
            },
        }
    }

    fn const_to_llvm_value(&self, const_val: &IrConst) -> String {
        match const_val {
            IrConst::Int(n, _) => format!("{}", n),
            IrConst::Float(n, _) => format!("{}", n),
            IrConst::Bool(b) => (if *b { "true" } else { "false" }).to_string(),
            IrConst::Null => "null".to_string(),
            IrConst::Str(s) => {
                let id = self.string_ids.get(s).unwrap_or(&0);
                format!("ptr @str_{}", id)
            }
        }
    }

    fn value_to_ptr(&self, value: &IrValue) -> Result<String, String> {
        match value {
            IrValue::Local(name) => {
                if let Some((alloca_name, _)) = self.locals.get(name) {
                    Ok(alloca_name.clone())
                } else if name.starts_with("_alloca_") {
                    Ok(format!("%{}", name))
                } else {
                    Ok(format!("%_alloca_{}", name))
                }
            }
            IrValue::Global(name) => Ok(format!("@{}", name)),
            IrValue::Const(_) => Err("Cannot get pointer to constant".to_string()),
        }
    }

    fn const_to_llvm(&self, const_val: &IrConst) -> String {
        match const_val {
            IrConst::Int(n, ty) => {
                let llvm_ty = self.type_to_llvm(ty);
                format!("{} {}", llvm_ty, n)
            }
            IrConst::Float(n, ty) => {
                let llvm_ty = self.type_to_llvm(ty);
                format!("{} {}", llvm_ty, n)
            }
            IrConst::Bool(b) => format!("i1 {}", if *b { "true" } else { "false" }),
            IrConst::Null => "ptr null".to_string(),
            IrConst::Str(s) => {
                let id = self.string_ids.get(s).unwrap_or(&0);
                format!("ptr @str_{}", id)
            }
        }
    }

    fn type_to_llvm(&self, ty: &TypeId) -> String {
        match ty {
            TypeId::TCon(name, _) => match name.as_str() {
                "I8" | "U8" => "i8".to_string(),
                "I16" | "U16" => "i16".to_string(),
                "I32" | "U32" => "i32".to_string(),
                "I64" | "U64" | "Isize" | "Usize" => "i64".to_string(),
                "I128" | "U128" => "i128".to_string(),
                "F32" => "float".to_string(),
                "F64" => "double".to_string(),
                "Bool" => "i1".to_string(),
                "Void" => "void".to_string(),
                "Any" | "String" => "ptr".to_string(),
                _ => {
                    if let Some(type_id) = self.struct_types.get(name) {
                        format!("%struct.{}", type_id)
                    } else if let Some(type_id) = self.enum_types.get(name) {
                        format!("%struct.{}", type_id)
                    } else {
                        "i64".to_string()
                    }
                }
            },
            TypeId::TPtr(_, _) => "ptr".to_string(),
            TypeId::TList(inner) => {
                format!("[{} x {}]", 0, self.type_to_llvm(inner))
            }
            TypeId::TArr(_, _) => "ptr".to_string(),
            TypeId::TTuple(_) => "i64".to_string(),
            TypeId::TVar(_) => "i64".to_string(),
            TypeId::TForall(_, inner) => self.type_to_llvm(inner),
            // TError only appears on an AST that already failed semantic
            // analysis; codegen never actually runs on such an AST (the
            // CLI bails out after printing diagnostics), so this arm is
            // unreachable in practice and just needs to satisfy
            // exhaustiveness.
            TypeId::TError => "i64".to_string(),
            TypeId::TEffect(inner, _) => self.type_to_llvm(inner),
            TypeId::TLinear(inner) => self.type_to_llvm(inner),
        }
    }

    // Both `type_size` and `type_align` are written as fully exhaustive
    // matches (one arm per `TypeId` variant, no wildcard `_`) deliberately:
    // a wildcard arm would silently swallow any *new* `TypeId` variant
    // added in the future (as happened with `TypeId::TError`, which was
    // added in axiom-sema without the compiler ever flagging these two
    // functions, because `_ => 8` accepted it by accident). Forcing an
    // explicit arm means the next new variant fails to compile here until
    // someone decides what its size/align actually is.
    fn type_size(&self, ty: &TypeId) -> i64 {
        match ty {
            TypeId::TCon(name, _) => match name.as_str() {
                "I8" | "U8" | "Bool" => 1,
                "I16" | "U16" => 2,
                "I32" | "U32" | "F32" => 4,
                "I64" | "U64" | "F64" | "Isize" | "Usize" | "Any" | "String" => 8,
                "I128" | "U128" => 16,
                _ => 8,
            },
            TypeId::TPtr(_, _) => 8,
            TypeId::TList(inner) => self.type_size(inner),
            TypeId::TArr(_, _) => 8,
            TypeId::TTuple(_) => 8,
            TypeId::TVar(_) => 8,
            TypeId::TForall(_, inner) => self.type_size(inner),
            // Only reachable on an AST that already failed semantic
            // analysis; codegen never actually runs on such an AST (see
            // `type_to_llvm`'s matching arm for the same rationale).
            TypeId::TError => 8,
            TypeId::TEffect(inner, _) => self.type_size(inner),
            TypeId::TLinear(inner) => self.type_size(inner),
        }
    }

    fn type_align(&self, ty: &TypeId) -> i64 {
        match ty {
            TypeId::TCon(name, _) => match name.as_str() {
                "I8" | "U8" | "Bool" => 1,
                "I16" | "U16" => 2,
                "I32" | "U32" | "F32" => 4,
                "I64" | "U64" | "F64" | "Isize" | "Usize" | "Any" | "String" => 8,
                "I128" | "U128" => 16,
                _ => 8,
            },
            TypeId::TPtr(_, _) => 8,
            TypeId::TList(inner) => self.type_align(inner),
            TypeId::TArr(_, _) => 8,
            TypeId::TTuple(_) => 8,
            TypeId::TVar(_) => 8,
            TypeId::TForall(_, inner) => self.type_align(inner),
            TypeId::TError => 8,
            TypeId::TEffect(inner, _) => self.type_align(inner),
            TypeId::TLinear(inner) => self.type_align(inner),
        }
    }

    fn new_local_reg(&mut self) -> String {
        let name = format!("%_t{}", self.local_counter);
        self.local_counter += 1;
        name
    }

    pub fn get_output(&self) -> &str {
        &self.output
    }
}

fn escape_llvm_string(s: &str) -> String {
    let mut escaped = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '\n' => escaped.push_str("\\0A"),
            '\r' => escaped.push_str("\\0D"),
            '\t' => escaped.push_str("\\09"),
            '\\' => escaped.push_str("\\5C"),
            '"' => escaped.push_str("\\22"),
            '\0' => escaped.push_str("\\00"),
            c if c.is_ascii_control() => {
                escaped.push_str(&format!("\\{:02X}", c as u8));
            }
            c => escaped.push(c),
        }
    }
    escaped
}
