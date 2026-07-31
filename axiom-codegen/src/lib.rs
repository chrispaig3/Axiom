pub mod target;

pub use target::Target;

use axiom_ir::*;
use axiom_sema::TypeId;
use std::collections::{HashMap, HashSet};
use std::fmt::Write;

/// The name of the allocator every `HeapAlloc` lowers to.
///
/// Codegen emits a freestanding `mmap`-backed bump allocator under
/// this name *unless* the program being compiled defines an Axiom
/// function of the same name, in which case the Axiom definition
/// wins. That is the seam that lets the allocator itself be
/// reimplemented in Axiom (`stdlib/Mem.ax`) without the backend
/// having to know whether it has been.
pub const ALLOC_SYMBOL: &str = "axiom_alloc";

pub struct LlvmCodeGen {
    output: String,
    type_counter: usize,
    local_counter: usize,
    struct_types: HashMap<String, usize>,
    current_func: Option<String>,
    locals: HashMap<String, (String, TypeId)>,
    ssa_values: HashMap<String, (String, TypeId)>,
    string_ids: HashMap<String, usize>,
    extern_decls: HashSet<String>,
    target: Target,
    /// The LLVM return type of the function currently being emitted.
    ///
    /// Needed because IR values carry their own width (comparisons
    /// produce `i1`) while every Axiom function returns a machine word,
    /// so `ret` has to widen a boolean rather than emit `ret i1` from
    /// an `i64` function - which LLVM rejects outright.
    current_ret_ty: String,
}

impl Default for LlvmCodeGen {
    fn default() -> Self {
        Self::new()
    }
}

impl LlvmCodeGen {
    pub fn new() -> Self {
        Self::for_target(Target::host())
    }

    /// A code generator that emits code for `target` rather than for
    /// the host.
    pub fn for_target(target: Target) -> Self {
        Self {
            output: String::new(),
            type_counter: 0,
            local_counter: 0,
            struct_types: HashMap::new(),
            current_func: None,
            locals: HashMap::new(),
            ssa_values: HashMap::new(),
            string_ids: HashMap::new(),
            extern_decls: HashSet::new(),
            target,
            current_ret_ty: "i64".to_string(),
        }
    }

    pub fn target(&self) -> Target {
        self.target
    }

    pub fn compile(&mut self, ir_module: &IrModule) -> Result<String, String> {
        writeln!(self.output, "; Axiom compiled LLVM IR").unwrap();
        writeln!(self.output, "target triple = \"{}\"", self.target.triple()).unwrap();
        writeln!(self.output).unwrap();

        self.declare_extern_funcs(ir_module);

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

        // Collect and emit string constants first. Every
        // instruction is asked what strings it mentions (see
        // `IrInst::string_consts`) rather than only `Call`: a
        // string reachable from any other instruction - e.g. the
        // `(__addr "...")` that hands a literal's bytes to a
        // syscall - still needs its `@str_N` global emitted here,
        // and an uncollected one silently referenced a
        // non-existent global.
        let mut str_id = 0;
        let mut strings: Vec<(usize, String)> = Vec::new();

        for func in &ir_module.functions {
            for block in &func.blocks {
                for inst in &block.insts {
                    for s in inst.string_consts() {
                        if !self.string_ids.contains_key(s) {
                            self.string_ids.insert(s.to_string(), str_id);
                            strings.push((str_id, s.to_string()));
                            str_id += 1;
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

        // The compiler-emitted allocator is skipped when the program
        // supplies its own `axiom_alloc` (an Axiom-native allocator
        // in the standard library), which would otherwise be a
        // duplicate symbol.
        let alloc_defined_in_axiom = ir_module.functions.iter().any(|f| f.name == ALLOC_SYMBOL);
        if !alloc_defined_in_axiom {
            self.emit_bump_allocator();
        }

        for ir_struct in &ir_module.structs {
            self.declare_struct(ir_struct);
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

    /// Declare the libc functions a `foreign` binding may refer to
    /// without its own declaration.
    ///
    /// Nothing the compiler *generates* calls these any more - memory
    /// comes from Axiom's own allocator and I/O from syscalls - so they
    /// exist purely so that pre-existing `(foreign printf ...)`-style
    /// code keeps linking during the migration away from C bindings.
    /// An unused `declare` contributes no undefined symbol, so this
    /// costs a freestanding program nothing.
    ///
    /// A name defined by the program being compiled wins: Axiom's own
    /// standard library defines `exit`, and emitting a libc `declare`
    /// for a name that also has a definition is an invalid-module error
    /// from `llc` rather than a diagnostic.
    fn declare_extern_funcs(&mut self, ir_module: &IrModule) {
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
            if ir_module.functions.iter().any(|f| f.name == *name) {
                continue;
            }
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
        self.current_ret_ty = return_type.clone();

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
                        IrValue::Tag(t) => format!("i64 {}", t),
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
            IrInst::CallIndirect { dest, ptr, args } => {
                let func_ptr = self.value_to_llvm(ptr)?;
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
                        IrValue::Tag(t) => format!("i64 {}", t),
                    })
                    .collect();
                if let IrValue::Local(name) = dest {
                    let result_reg = self.new_local_reg();
                    let callee_reg = self.new_local_reg();
                    writeln!(
                        self.output,
                        "  {} = inttoptr i64 {} to ptr",
                        callee_reg, func_ptr
                    )
                    .unwrap();
                    let arg_str = arg_values.join(", ");
                    writeln!(
                        self.output,
                        "  {} = call i64 {}({})",
                        result_reg, callee_reg, arg_str
                    )
                    .unwrap();
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::Ret { value } => {
                if let Some(val) = value {
                    let (val_str, ty_str) = self.value_to_typed_string(val)?;
                    let ret_ty = self.current_ret_ty.clone();
                    // A function whose body ends in a comparison
                    // produces an `i1`, but every Axiom function
                    // returns a machine word. Widen rather than
                    // emitting a `ret` whose type contradicts the
                    // function signature: LLVM rejects the latter at
                    // `llc` time, which surfaces as an opaque backend
                    // error instead of working code.
                    if ty_str != ret_ty && ty_str == "i1" && ret_ty == "i64" {
                        let widened = self.new_local_reg();
                        writeln!(self.output, "  {} = zext i1 {} to i64", widened, val_str)
                            .unwrap();
                        writeln!(self.output, "  ret i64 {}", widened).unwrap();
                    } else {
                        writeln!(self.output, "  ret {} {}", ty_str, val_str).unwrap();
                    }
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
                let (cond_val, cond_ty) = self.value_to_typed_string(cond)?;
                // A condition is an `i1` when it came from a
                // comparison in the same function, but a machine word
                // when it came from *calling* a `Bool`-returning
                // function (every Axiom function returns a word). Test
                // the word against zero rather than assuming `i1`:
                // assuming it made every `(if (someBoolFn x) ...)`
                // fail in the backend.
                let cond_i1 = if cond_ty == "i1" {
                    cond_val
                } else {
                    let reg = self.new_local_reg();
                    writeln!(
                        self.output,
                        "  {} = icmp ne {} {}, 0",
                        reg, cond_ty, cond_val
                    )
                    .unwrap();
                    reg
                };
                writeln!(
                    self.output,
                    "  br i1 {}, label %{}, label %{}",
                    cond_i1, then_target, else_target
                )
                .unwrap();
            }
            IrInst::Cast {
                dest,
                src,
                target_ty,
            } => {
                let (src_val, src_ty_str) = self.value_to_typed_string(src)?;
                let target_llvm = self.type_to_llvm(target_ty);
                let result_reg = self.new_local_reg();

                let src_bits = llvm_type_bits(&src_ty_str);
                let tgt_bits = llvm_type_bits(&target_llvm);

                if src_bits == tgt_bits {
                    writeln!(
                        self.output,
                        "  {} = add {} 0, {}",
                        result_reg, target_llvm, src_val
                    )
                    .unwrap();
                } else if src_bits < tgt_bits {
                    let ext = if src_ty_str.starts_with('i')
                        && target_llvm.starts_with('i')
                    {
                        if src_ty_str == "i1" {
                            "zext"
                        } else {
                            "sext"
                        }
                    } else {
                        "zext"
                    };
                    writeln!(
                        self.output,
                        "  {} = {} {} {} to {}",
                        result_reg, ext, src_ty_str, src_val, target_llvm
                    )
                    .unwrap();
                } else {
                    writeln!(
                        self.output,
                        "  {} = trunc {} {} to {}",
                        result_reg, src_ty_str, src_val, target_llvm
                    )
                    .unwrap();
                }

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
                // Allocation goes through Axiom's own allocator, not
                // `malloc`: a compiled program must not need libc for
                // its own data (see `emit_bump_allocator`). The
                // allocator returns a plain `i64` address, matching
                // this IR's "every value is an `i64`" model, so no
                // `ptrtoint` is needed at the call site any more.
                let addr_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = call i64 @{}(i64 {})",
                    addr_reg, ALLOC_SYMBOL, size_val
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (addr_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::ArenaMark { dest } => {
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = load i64, ptr @__axiom_bump",
                    result_reg
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::ArenaReset { ptr } => {
                let ptr_val = self.value_to_llvm(ptr)?;
                writeln!(
                    self.output,
                    "  store i64 {}, ptr @__axiom_bump",
                    ptr_val
                )
                .unwrap();
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
            IrInst::Syscall { dest, num, args } => {
                let num_val = self.value_to_llvm(num)?;
                // The asm template has a fixed arity of six
                // arguments on every target (see
                // `Target::syscall_asm`), so pad with zeros rather
                // than emitting one template per argument count.
                let mut arg_vals = Vec::with_capacity(6);
                for a in args.iter().take(6) {
                    arg_vals.push(self.value_to_llvm(a)?);
                }
                while arg_vals.len() < 6 {
                    arg_vals.push("0".to_string());
                }
                let (body, constraints) = self.target.syscall_asm();
                let result_reg = self.new_local_reg();
                let operands = std::iter::once(num_val)
                    .chain(arg_vals)
                    .map(|v| format!("i64 {}", v))
                    .collect::<Vec<_>>()
                    .join(", ");
                writeln!(
                    self.output,
                    "  {} = call i64 asm sideeffect \"{}\", \"{}\"({})",
                    result_reg, body, constraints, operands
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::LoadIdx { dest, ptr, index } => {
                let byte_ptr = self.emit_byte_gep(ptr, index, 1)?;
                let loaded = self.new_local_reg();
                writeln!(self.output, "  {} = load i8, ptr {}", loaded, byte_ptr).unwrap();
                let result_reg = self.new_local_reg();
                writeln!(self.output, "  {} = zext i8 {} to i64", result_reg, loaded).unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::StoreIdx { ptr, index, value } => {
                let byte_ptr = self.emit_byte_gep(ptr, index, 1)?;
                let val = self.value_to_llvm(value)?;
                let truncated = self.new_local_reg();
                writeln!(self.output, "  {} = trunc i64 {} to i8", truncated, val).unwrap();
                writeln!(self.output, "  store i8 {}, ptr {}", truncated, byte_ptr).unwrap();
            }
            IrInst::LoadWordIdx { dest, ptr, index } => {
                let word_ptr = self.emit_byte_gep(ptr, index, 8)?;
                let result_reg = self.new_local_reg();
                writeln!(self.output, "  {} = load i64, ptr {}", result_reg, word_ptr).unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::StoreWordIdx { ptr, index, value } => {
                let word_ptr = self.emit_byte_gep(ptr, index, 8)?;
                let val = self.value_to_llvm(value)?;
                writeln!(self.output, "  store i64 {}, ptr {}", val, word_ptr).unwrap();
            }
            IrInst::AddrOf { dest, value } => {
                let (val, ty) = self.value_to_typed_string(value)?;
                let result_reg = self.new_local_reg();
                if ty == "ptr" {
                    // String constants already render as
                    // `ptr @str_N`, so the type prefix is part of
                    // `val` and must not be repeated.
                    let stripped = val.strip_prefix("ptr ").unwrap_or(&val).to_string();
                    writeln!(
                        self.output,
                        "  {} = ptrtoint ptr {} to i64",
                        result_reg, stripped
                    )
                    .unwrap();
                } else {
                    // Already an integer address (every heap value
                    // in this IR is a plain `i64`): a no-op copy
                    // keeps the instruction total and avoids
                    // special cases at every use site.
                    writeln!(self.output, "  {} = add i64 {}, 0", result_reg, val).unwrap();
                }
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
        }

        Ok(())
    }

    /// Emit the address computation shared by the four indexed
    /// memory instructions: `ptr + index * scale`, as an LLVM `ptr`.
    ///
    /// `ptr` is a plain `i64` address (this IR has no pointer type),
    /// so the arithmetic is done in integers and converted once at
    /// the end rather than round-tripping through `getelementptr`.
    fn emit_byte_gep(
        &mut self,
        ptr: &IrValue,
        index: &IrValue,
        scale: i64,
    ) -> Result<String, String> {
        let base = self.value_to_llvm(ptr)?;
        let idx = self.value_to_llvm(index)?;
        let scaled = if scale == 1 {
            idx
        } else {
            let reg = self.new_local_reg();
            writeln!(self.output, "  {} = mul i64 {}, {}", reg, idx, scale).unwrap();
            reg
        };
        let addr = self.new_local_reg();
        writeln!(self.output, "  {} = add i64 {}, {}", addr, base, scaled).unwrap();
        let as_ptr = self.new_local_reg();
        writeln!(self.output, "  {} = inttoptr i64 {} to ptr", as_ptr, addr).unwrap();
        Ok(as_ptr)
    }

    /// Emit the freestanding bump allocator that `HeapAlloc` calls.
    ///
    /// Memory comes straight from `mmap`, never from `malloc`, so a
    /// compiled Axiom program has no libc dependency for its own
    /// data. Chunks are never returned to the OS: this is an arena,
    /// which is the right trade for a compiler process that exits
    /// after one run, and it is deliberately overridable - defining
    /// `axiom_alloc` in Axiom replaces it wholesale (see
    /// [`ALLOC_SYMBOL`]).
    fn emit_bump_allocator(&mut self) {
        let (body, constraints) = self.target.syscall_asm();
        let mmap = self.target.sys_mmap();
        let exit = self.target.sys_exit();
        let flags = self.target.map_private_anon();
        // 1 MiB chunks: large enough that the slow path is rare in
        // compiler-shaped workloads, small enough not to commit
        // pointless address space in a `hello world`.
        const CHUNK: i64 = 1024 * 1024;

        let out = &mut self.output;
        writeln!(out, "@__axiom_bump = internal global i64 0").unwrap();
        writeln!(out, "@__axiom_bump_end = internal global i64 0").unwrap();
        writeln!(out).unwrap();
        writeln!(out, "define i64 @{}(i64 %size) {{", ALLOC_SYMBOL).unwrap();
        writeln!(out, "entry:").unwrap();
        // Round the request up to 16 bytes so every returned
        // address stays 16-byte aligned (the strictest alignment
        // any Axiom value needs, and what both ABIs expect).
        writeln!(out, "  %padded = add i64 %size, 15").unwrap();
        writeln!(out, "  %sz = and i64 %padded, -16").unwrap();
        writeln!(out, "  %cur = load i64, ptr @__axiom_bump").unwrap();
        writeln!(out, "  %next = add i64 %cur, %sz").unwrap();
        writeln!(out, "  %end = load i64, ptr @__axiom_bump_end").unwrap();
        writeln!(out, "  %fits = icmp ule i64 %next, %end").unwrap();
        writeln!(out, "  br i1 %fits, label %fast, label %refill").unwrap();
        writeln!(out, "fast:").unwrap();
        writeln!(out, "  store i64 %next, ptr @__axiom_bump").unwrap();
        writeln!(out, "  ret i64 %cur").unwrap();
        writeln!(out, "refill:").unwrap();
        // A request bigger than a chunk gets its own mapping,
        // rounded up to a 64 KiB boundary (a page on every
        // supported target, and the largest of them).
        writeln!(out, "  %big = icmp ugt i64 %sz, {}", CHUNK).unwrap();
        writeln!(out, "  %rounded0 = add i64 %sz, 65535").unwrap();
        writeln!(out, "  %rounded = and i64 %rounded0, -65536").unwrap();
        writeln!(
            out,
            "  %chunk = select i1 %big, i64 %rounded, i64 {}",
            CHUNK
        )
        .unwrap();
        writeln!(
            out,
            "  %addr = call i64 asm sideeffect \"{}\", \"{}\"(i64 {}, i64 0, i64 %chunk, i64 3, i64 {}, i64 -1, i64 0)",
            body, constraints, mmap, flags
        )
        .unwrap();
        // Failure detection has to cover both conventions: Linux
        // returns `-errno` (a huge unsigned value), Darwin returns
        // a small positive errno with the carry flag set - which
        // inline asm cannot read - so a low address stands in for
        // it. Either way the result is not a usable mapping, and
        // continuing would corrupt memory silently.
        writeln!(out, "  %failed_low = icmp ult i64 %addr, 4096").unwrap();
        writeln!(out, "  %failed_neg = icmp ugt i64 %addr, -4096").unwrap();
        writeln!(out, "  %failed = or i1 %failed_low, %failed_neg").unwrap();
        writeln!(out, "  br i1 %failed, label %oom, label %mapped").unwrap();
        writeln!(out, "mapped:").unwrap();
        writeln!(out, "  %new_bump = add i64 %addr, %sz").unwrap();
        writeln!(out, "  store i64 %new_bump, ptr @__axiom_bump").unwrap();
        writeln!(out, "  %new_end = add i64 %addr, %chunk").unwrap();
        writeln!(out, "  store i64 %new_end, ptr @__axiom_bump_end").unwrap();
        writeln!(out, "  ret i64 %addr").unwrap();
        writeln!(out, "oom:").unwrap();
        writeln!(
            out,
            "  call i64 asm sideeffect \"{}\", \"{}\"(i64 {}, i64 70, i64 0, i64 0, i64 0, i64 0, i64 0)",
            body, constraints, exit
        )
        .unwrap();
        writeln!(out, "  unreachable").unwrap();
        writeln!(out, "}}").unwrap();
        writeln!(out).unwrap();
    }

    fn value_to_llvm(&self, value: &IrValue) -> Result<String, String> {
        match value {
            IrValue::Tag(t) => Ok(format!("{}", t)),
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
            IrValue::Tag(t) => Ok((format!("{}", t), "i64".to_string())),
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
            IrValue::Tag(_) => Err("Cannot get pointer to tag".to_string()),
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

#[cfg(test)]
mod tests {
    use super::*;

    fn i64_ty() -> TypeId {
        TypeId::TCon("I64".to_string(), vec![])
    }

    /// A one-function module whose body is `insts` followed by
    /// `ret 0`, for exercising a single instruction's lowering.
    fn module_with(insts: Vec<IrInst>) -> IrModule {
        let mut m = IrModule::new();
        let mut all = insts;
        all.push(IrInst::Ret {
            value: Some(IrValue::Const(IrConst::Int(0, i64_ty()))),
        });
        m.functions.push(IrFunction {
            name: "main".to_string(),
            params: Vec::new(),
            return_type: i64_ty(),
            blocks: vec![IrBlock {
                label: "entry".to_string(),
                insts: all,
            }],
            locals: Vec::new(),
        });
        m
    }

    fn compile(target: Target, insts: Vec<IrInst>) -> String {
        LlvmCodeGen::for_target(target)
            .compile(&module_with(insts))
            .expect("codegen succeeds")
    }

    #[test]
    fn module_header_names_the_requested_target() {
        for t in Target::all() {
            let ir = compile(*t, Vec::new());
            assert!(
                ir.contains(&format!("target triple = \"{}\"", t.triple())),
                "{} triple missing",
                t.name()
            );
        }
    }

    #[test]
    fn syscall_lowers_to_the_targets_asm_with_seven_operands() {
        // Every target's template takes the number plus six arguments,
        // so a two-argument syscall must be padded rather than emitted
        // with a shorter operand list - a mismatch between operand
        // count and constraint count is an LLVM verifier error.
        let ir = compile(
            Target::LinuxX86_64,
            vec![IrInst::Syscall {
                dest: IrValue::Local("r".to_string()),
                num: IrValue::Const(IrConst::Int(1, i64_ty())),
                args: vec![
                    IrValue::Const(IrConst::Int(2, i64_ty())),
                    IrValue::Const(IrConst::Int(3, i64_ty())),
                ],
            }],
        );
        // Skipping the allocator's own `mmap` syscall, which the
        // backend emits into every module ahead of user code.
        let line = ir
            .lines()
            .find(|l| l.contains("asm sideeffect") && l.contains("(i64 1,"))
            .expect("the module's own syscall was emitted");
        assert!(line.contains("\"syscall\""), "{}", line);
        let operands = line
            .rsplit_once('(')
            .expect("operand list")
            .1
            .trim_end_matches(')');
        assert_eq!(
            operands, "i64 1, i64 2, i64 3, i64 0, i64 0, i64 0, i64 0",
            "operand list must be the number plus six padded arguments"
        );
    }

    #[test]
    fn syscall_newlines_are_llvm_escapes_not_raw_bytes() {
        // The Darwin templates are multi-instruction. Emitting a real
        // newline (or worse, a NUL from a mis-escaped `\0A` in Rust
        // source) produces an .ll file that no longer parses - and in
        // the NUL case, one that silently truncates the asm so the
        // error-negation branch disappears.
        let ir = compile(
            Target::DarwinAarch64,
            vec![IrInst::Syscall {
                dest: IrValue::Local("r".to_string()),
                num: IrValue::Const(IrConst::Int(1, i64_ty())),
                args: Vec::new(),
            }],
        );
        assert!(!ir.contains('\0'), "generated IR contains a NUL byte");
        let line = ir
            .lines()
            .find(|l| l.contains("asm sideeffect") && l.contains("(i64 1,"))
            .expect("the module's own syscall was emitted");
        assert!(line.contains(r"\0A"), "{}", line);
        assert!(line.contains("neg x0, x0"), "{}", line);
    }

    #[test]
    fn heap_alloc_calls_axioms_allocator_and_never_malloc() {
        let ir = compile(
            Target::LinuxX86_64,
            vec![IrInst::HeapAlloc {
                dest: IrValue::Local("p".to_string()),
                size: IrValue::Const(IrConst::Int(24, i64_ty())),
            }],
        );
        assert!(
            ir.contains(&format!("call i64 @{}(i64 24)", ALLOC_SYMBOL)),
            "{}",
            ir
        );
        assert!(
            !ir.contains("call ptr @malloc"),
            "allocation still goes through libc"
        );
    }

    #[test]
    fn the_emitted_allocator_uses_mmap_and_no_libc() {
        let ir = compile(Target::LinuxX86_64, Vec::new());
        assert!(ir.contains(&format!("define i64 @{}(i64 %size)", ALLOC_SYMBOL)));
        assert!(
            ir.contains(&format!("i64 {},", Target::LinuxX86_64.sys_mmap())),
            "allocator does not call mmap"
        );
        assert!(ir.contains("@__axiom_bump"), "no bump pointer");
    }

    #[test]
    fn an_axiom_defined_allocator_replaces_the_emitted_one() {
        // The standard library is allowed to provide its own
        // `axiom_alloc`; emitting the built-in one as well would be a
        // duplicate symbol, so the built-in must step aside.
        let mut m = module_with(Vec::new());
        m.functions.push(IrFunction {
            name: ALLOC_SYMBOL.to_string(),
            params: vec![("size".to_string(), i64_ty())],
            return_type: i64_ty(),
            blocks: vec![IrBlock {
                label: "entry".to_string(),
                insts: vec![IrInst::Ret {
                    value: Some(IrValue::Const(IrConst::Int(0, i64_ty()))),
                }],
            }],
            locals: Vec::new(),
        });
        let ir = LlvmCodeGen::for_target(Target::LinuxX86_64)
            .compile(&m)
            .expect("codegen succeeds");
        assert_eq!(
            ir.matches(&format!("define i64 @{}", ALLOC_SYMBOL)).count(),
            1,
            "allocator defined twice:\n{}",
            ir
        );
        assert!(
            !ir.contains("@__axiom_bump"),
            "built-in allocator emitted anyway"
        );
    }

    #[test]
    fn byte_access_narrows_and_widens_explicitly() {
        let ir = compile(
            Target::LinuxX86_64,
            vec![
                IrInst::StoreIdx {
                    ptr: IrValue::Local("p".to_string()),
                    index: IrValue::Const(IrConst::Int(3, i64_ty())),
                    value: IrValue::Const(IrConst::Int(65, i64_ty())),
                },
                IrInst::LoadIdx {
                    dest: IrValue::Local("b".to_string()),
                    ptr: IrValue::Local("p".to_string()),
                    index: IrValue::Const(IrConst::Int(3, i64_ty())),
                },
            ],
        );
        assert!(ir.contains("trunc i64 65 to i8"), "{}", ir);
        assert!(ir.contains("store i8"), "{}", ir);
        assert!(ir.contains("load i8"), "{}", ir);
        assert!(ir.contains("zext i8"), "{}", ir);
    }

    #[test]
    fn word_access_scales_the_index_by_eight() {
        // `__load64`/`__store64` index in words, not bytes: dropping the
        // scale would alias every element onto the first byte of the
        // block and silently corrupt any `Str` header or array.
        let ir = compile(
            Target::LinuxX86_64,
            vec![IrInst::LoadWordIdx {
                dest: IrValue::Local("w".to_string()),
                ptr: IrValue::Local("p".to_string()),
                index: IrValue::Local("i".to_string()),
            }],
        );
        assert!(ir.contains("mul i64 %i, 8"), "{}", ir);
        assert!(ir.contains("load i64"), "{}", ir);
    }

    #[test]
    fn string_literals_reachable_only_from_new_instructions_are_still_emitted() {
        // `AddrOf` was the first instruction to reference a string
        // outside a `Call`, and string collection used to only look at
        // calls - producing IR that referenced an `@str_N` global that
        // was never defined.
        let ir = compile(
            Target::LinuxX86_64,
            vec![IrInst::AddrOf {
                dest: IrValue::Local("a".to_string()),
                value: IrValue::Const(IrConst::Str("hi".to_string())),
            }],
        );
        assert!(
            ir.contains("@str_0 = private unnamed_addr constant"),
            "{}",
            ir
        );
        assert!(ir.contains("ptrtoint ptr @str_0 to i64"), "{}", ir);
    }

    #[test]
    fn a_boolean_result_is_widened_to_the_functions_word_return_type() {
        let ir = compile(
            Target::LinuxX86_64,
            vec![
                IrInst::Lt {
                    dest: IrValue::Local("c".to_string()),
                    lhs: IrValue::Const(IrConst::Int(1, i64_ty())),
                    rhs: IrValue::Const(IrConst::Int(2, i64_ty())),
                },
                IrInst::Ret {
                    value: Some(IrValue::Local("c".to_string())),
                },
            ],
        );
        assert!(ir.contains("zext i1"), "{}", ir);
        assert!(!ir.contains("ret i1"), "{}", ir);
    }

    #[test]
    fn a_word_condition_is_compared_against_zero_before_branching() {
        // A condition that came from calling a `Bool`-returning Axiom
        // function arrives as a word, and `br i1 <word>` is invalid.
        let ir = compile(
            Target::LinuxX86_64,
            vec![
                IrInst::Call {
                    dest: IrValue::Local("c".to_string()),
                    func: "isEmpty".to_string(),
                    args: Vec::new(),
                },
                IrInst::CondBr {
                    cond: IrValue::Local("c".to_string()),
                    then_target: "t".to_string(),
                    else_target: "e".to_string(),
                },
            ],
        );
        assert!(ir.contains("icmp ne i64"), "{}", ir);
    }
}

fn llvm_type_bits(ty: &str) -> u32 {
    match ty {
        "i1" => 1,
        "i8" => 8,
        "i16" => 16,
        "i32" | "float" => 32,
        "i64" | "double" | "ptr" => 64,
        "i128" => 128,
        "void" => 0,
        _ => 64,
    }
}
