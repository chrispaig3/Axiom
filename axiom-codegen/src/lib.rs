pub mod gc;
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

/// The attribute group reference put on every emitted function, and the
/// group itself.
///
/// Axiom's contract is that generated code calls no libc function, and
/// the optimiser does not know that. LLVM's loop-idiom recogniser
/// rewrites a byte loop into a call to `strlen` or `memset` - which are
/// libc symbols, in a language that has deliberately never linked libc -
/// and it does so on IR the compiler was right to emit. Measured: a
/// stage1-built `010-hello.ax` put through `opt -O1` grew 17 references
/// to `strlen`, and the linked binary imported `_strlen` and `_memset`.
///
/// `"no-builtins"` is the string attribute clang emits for
/// `-fno-builtin`, and it is what disables the recognition. The
/// enum attribute `nobuiltin` is NOT the same thing and does NOT work
/// here - measured separately, it left all 17 in place. They are easy
/// to confuse and only one of them is load-bearing.
///
/// The cost is real and accepted: a byte loop stays a byte loop rather
/// than becoming a tuned `memcpy`. A freestanding language cannot take
/// the faster option, because the faster option is a symbol it has no
/// way to define.
pub const NO_BUILTINS_ATTR: &str = "#0 ";

/// The attribute group `NO_BUILTINS_ATTR` refers to.
pub const NO_BUILTINS_GROUP: &str = "attributes #0 = { \"no-builtins\" }";

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
    /// Emit the tracing collector instead of the bump allocator.
    ///
    /// Off by default. A bump allocator is the right trade for a
    /// short-lived process that exits before it can care - which is most
    /// of what Axiom compiles today - and it costs nothing at runtime.
    /// The collector is for programs whose peak memory has to track live
    /// data rather than total allocation.
    gc: bool,
    /// Whether the collector was actually emitted for this module, which
    /// is what decides if `main` has to record the stack base.
    gc_active: bool,
    /// Whether the built-in bump allocator - and with it the arena
    /// helpers and the globals they move - is part of this module.
    bump_allocator_emitted: bool,
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
            gc: false,
            gc_active: false,
            bump_allocator_emitted: false,
        }
    }

    /// Emit the tracing collector rather than the bump allocator.
    pub fn with_gc(mut self, on: bool) -> Self {
        self.gc = on;
        self
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

        // Two globals per literal: the bytes, and a `Str` header over
        // them.
        //
        // The header is what a literal *evaluates* to, which is what
        // makes `(println "hi")` mean what it reads as. It has the
        // layout `Str.strWrap` builds - word 0 length, word 1 byte
        // pointer - so a literal and a constructed `Str` are the same
        // thing to every consumer, and `strLen` on a literal is a load
        // rather than the `cstrLen` scan `strFromLit` had to do. The
        // length is a compile-time constant here, so the scan is not
        // merely faster, it is gone.
        //
        // The bytes keep the NUL terminator even though the header
        // makes it redundant, because `strCStr` hands literal paths
        // straight to a syscall without copying, and `(__addr "...")`
        // still resolves to *these* bytes rather than to the header.
        //
        // Emitting the header unconditionally, rather than only for
        // literals observed in value position, costs 16 bytes of
        // `.rodata` per unused literal and avoids a second pass over
        // the module to decide - and the two uses are not exclusive:
        // the same literal can be both `__addr`-ed and used as a
        // `Str`.
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
            writeln!(
                self.output,
                "@strhdr_{} = private unnamed_addr constant {{ i64, ptr }} \
                 {{ i64 {}, ptr @str_{} }}, align 8",
                id,
                s.len(),
                id
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
        // Effect evidence slots are mutable globals holding the only
        // reference to an installed handler chain; a collector that
        // does not treat them as roots frees a handler while it is
        // installed. They are collected here so the GC emission below
        // can mark through them.
        let evidence_slots: Vec<String> = ir_module
            .globals
            .iter()
            .filter(|g| g.name.starts_with("__axiom_ev_"))
            .map(|g| g.name.clone())
            .collect();
        if !alloc_defined_in_axiom {
            if self.gc {
                writeln!(self.output, "declare ptr @llvm.frameaddress.p0(i32)").unwrap();
                writeln!(self.output).unwrap();
                let text = crate::gc::GcEmitter::new(self.target)
                    .with_global_roots(evidence_slots.clone())
                    .emit();
                self.output.push_str(&text);
            } else {
                self.emit_bump_allocator();
                self.emit_arena_helpers();
                self.bump_allocator_emitted = true;
            }
        }
        self.gc_active = self.gc && !alloc_defined_in_axiom;
        if !evidence_slots.is_empty() {
            self.emit_unhandled_effect_trap();
        }

        // The process's arguments, captured once by the entry wrapper
        // below and read back by the `__argc`/`__argv` primitives. The
        // globals are emitted unconditionally (harmless when unused);
        // the wrapper only when the module actually defines the
        // renamed user `main` - a library module has no entry point
        // and a wrapper would reference an undefined symbol.
        writeln!(self.output, "@__axiom_argc = internal global i64 0").unwrap();
        writeln!(self.output, "@__axiom_argv = internal global i64 0").unwrap();
        writeln!(self.output).unwrap();
        if ir_module
            .functions
            .iter()
            .any(|f| f.name == "__axiom_user_main")
        {
            writeln!(
                self.output,
                "define i64 @main(i64 %argc, i64 %argv) {}{{",
                NO_BUILTINS_ATTR
            )
            .unwrap();
            writeln!(self.output, "entry:").unwrap();
            writeln!(self.output, "  store i64 %argc, ptr @__axiom_argc").unwrap();
            writeln!(self.output, "  store i64 %argv, ptr @__axiom_argv").unwrap();
            writeln!(self.output, "  %r = call i64 @__axiom_user_main(i64 0)").unwrap();
            writeln!(self.output, "  ret i64 %r").unwrap();
            writeln!(self.output, "}}").unwrap();
            writeln!(self.output).unwrap();
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

        writeln!(self.output).unwrap();
        writeln!(self.output, "{}", NO_BUILTINS_GROUP).unwrap();

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

        // `internal`: nothing outside the one emitted module ever
        // links against an Axiom global. (Evidence slots are the
        // first globals to actually flow through here - string
        // literals take their own path.)
        writeln!(
            self.output,
            "@{} = internal {} {}",
            global.name, const_str, value,
        )
        .unwrap();
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
            "define {} @{}({}) {}{{",
            return_type,
            ir_func.name,
            params.join(", "),
            NO_BUILTINS_ATTR,
        )
        .unwrap();

        // The user's entry function - `main` was renamed at mangling so
        // the argv-capturing wrapper could own the linker's `main`. Its
        // frame base still bounds every Axiom frame below it; only the
        // wrapper's own two stores sit above, and they hold no Axiom
        // values.
        let record_stack_base = self.gc_active && ir_func.name == "__axiom_user_main";
        for (bi, block) in ir_func.blocks.iter().enumerate() {
            writeln!(self.output, "{}:", block.label).unwrap();

            // The root scan runs from the current stack pointer up to
            // here. `llvm.frameaddress` rather than the stack pointer,
            // because by the time any instruction of `main` runs the
            // prologue has already moved SP *below* main's own locals -
            // recording it there would leave them outside the scanned
            // range. Asking for the frame address also forces the
            // function to keep a frame pointer, which is what makes it
            // meaningful at higher optimisation levels.
            if record_stack_base && bi == 0 {
                let fp = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = call ptr @llvm.frameaddress.p0(i32 0)",
                    fp
                )
                .unwrap();
                let fpi = self.new_local_reg();
                writeln!(self.output, "  {} = ptrtoint ptr {} to i64", fpi, fp).unwrap();
                writeln!(self.output, "  store i64 {}, ptr @__axiom_stack_base", fpi).unwrap();
            }

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
            IrInst::FloatBin { dest, op, lhs, rhs } => {
                // Floats live in the same `i64` machine word as every
                // other Axiom value, so both operands arrive as integers
                // holding IEEE bit patterns and have to be reinterpreted
                // - not converted - before the operation. `bitcast` is a
                // no-op at runtime; the register allocator keeps the
                // value in an FP register across a chain of these.
                let lhs_val = self.value_to_llvm(lhs)?;
                let rhs_val = self.value_to_llvm(rhs)?;
                let lf = self.new_local_reg();
                let rf = self.new_local_reg();
                writeln!(self.output, "  {} = bitcast i64 {} to double", lf, lhs_val).unwrap();
                writeln!(self.output, "  {} = bitcast i64 {} to double", rf, rhs_val).unwrap();

                let raw = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = {} double {}, {}",
                    raw,
                    op.llvm_opcode(),
                    lf,
                    rf
                )
                .unwrap();

                // A comparison already yields `i1`, which is what `Bool`
                // is here. Arithmetic yields a `double` that has to go
                // back into the uniform word.
                let result_reg = if op.is_comparison() {
                    raw
                } else {
                    let back = self.new_local_reg();
                    writeln!(self.output, "  {} = bitcast double {} to i64", back, raw).unwrap();
                    back
                };

                if let IrValue::Local(name) = dest {
                    let ty = if op.is_comparison() {
                        TypeId::TCon("Bool".to_string(), vec![])
                    } else {
                        TypeId::TCon("I64".to_string(), vec![])
                    };
                    self.ssa_values.insert(name.clone(), (result_reg, ty));
                }
            }
            IrInst::IntToFloat { dest, value } => {
                // `sitofp` converts the *number*; the result then goes
                // back into the uniform word as bits.
                let val = self.value_to_llvm(value)?;
                let as_double = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = sitofp i64 {} to double",
                    as_double, val
                )
                .unwrap();
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = bitcast double {} to i64",
                    result_reg, as_double
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
                }
            }
            IrInst::FloatToInt { dest, value } => {
                let val = self.value_to_llvm(value)?;
                let as_double = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = bitcast i64 {} to double",
                    as_double, val
                )
                .unwrap();
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = fptosi double {} to i64",
                    result_reg, as_double
                )
                .unwrap();
                if let IrValue::Local(name) = dest {
                    self.ssa_values.insert(
                        name.clone(),
                        (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                    );
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
                let lhs_val = self.value_to_i64(lhs)?;
                let rhs_val = self.value_to_i64(rhs)?;
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
                let lhs_val = self.value_to_i64(lhs)?;
                let rhs_val = self.value_to_i64(rhs)?;
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
                // Store what the *slot* holds, not what the value happens
                // to be. A comparison yields `i1`, and an `if` whose arms
                // are comparisons stores into the expression's result
                // slot, which is `alloca i64` like every Axiom local. A
                // bare `store i1` there writes one byte and leaves seven
                // untouched, so the matching `load i64` reads whatever the
                // frame last held - right in a small program, arbitrary in
                // a large one. Widening here is what makes a `Bool`-valued
                // `if` mean the same thing in both.
                let slot_ty = self.pointee_llvm_type(ptr);
                let stored = match &slot_ty {
                    Some(want) if *want != ty_str => self.coerce_int(&val_str, &ty_str, want),
                    _ => (val_str, ty_str),
                };
                writeln!(
                    self.output,
                    "  store {} {}, ptr {}",
                    stored.1, stored.0, ptr_val
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
                        IrValue::Const(IrConst::Float(n, _)) => {
                            format!("i64 {}", n.to_bits() as i64)
                        }
                        IrValue::Const(IrConst::Bool(b)) => {
                            format!("i1 {}", if *b { "true" } else { "false" })
                        }
                        IrValue::Const(IrConst::Null) => "ptr null".to_string(),
                        IrValue::Const(IrConst::Str(s)) => {
                            format!("i64 {}", self.str_header_value(s))
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
                        IrValue::Tag(name) => {
                            if let Some((reg, ty)) = self.ssa_values.get(name) {
                                let llvm_ty = self.type_to_llvm(ty);
                                format!("{} {}", llvm_ty, reg)
                            } else {
                                format!("i64 %{}", name)
                            }
                        }
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
                        IrValue::Const(IrConst::Float(n, _)) => {
                            format!("i64 {}", n.to_bits() as i64)
                        }
                        IrValue::Const(IrConst::Bool(b)) => {
                            format!("i1 {}", if *b { "true" } else { "false" })
                        }
                        IrValue::Const(IrConst::Null) => "ptr null".to_string(),
                        IrValue::Const(IrConst::Str(s)) => {
                            format!("i64 {}", self.str_header_value(s))
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
                        IrValue::Tag(name) => {
                            if let Some((reg, ty)) = self.ssa_values.get(name) {
                                let llvm_ty = self.type_to_llvm(ty);
                                format!("{} {}", llvm_ty, reg)
                            } else {
                                format!("i64 %{}", name)
                            }
                        }
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
            IrInst::Unreachable => {
                writeln!(self.output, "  unreachable").unwrap();
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
                    let ext = if src_ty_str.starts_with('i') && target_llvm.starts_with('i') {
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
            IrInst::ArenaMark { .. } | IrInst::ArenaReset { .. } if self.gc_active => {
                // The waterline these save and restore belongs to the
                // bump allocator. Under the collector there is no
                // waterline, and "free everything allocated since here"
                // is not a request a tracing collector can honour - the
                // objects in that range are exactly the ones it decides
                // about by reachability. Silently ignoring the call
                // would leave a program that asked for memory back and
                // did not get it; honouring it would free live objects.
                return Err(
                    "the `__axiom_arena_*` primitives are bump-allocator controls and cannot \
                     be used with `--gc`: the collector reclaims by reachability, so there is \
                     no waterline to roll back to. Drop the explicit arena calls, or build \
                     without `--gc`."
                        .to_string(),
                );
            }
            IrInst::Argc { dest } => {
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = load i64, ptr @__axiom_argc",
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
            IrInst::Argv { dest } => {
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = load i64, ptr @__axiom_argv",
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
            IrInst::ArenaMark { .. } | IrInst::ArenaReset { .. } if !self.bump_allocator_emitted => {
                // The arena primitives are the built-in allocator's own
                // controls: they save and restore *its* globals. When a
                // program supplies its own `axiom_alloc` the built-in is
                // not emitted at all, so these would reference globals
                // and helpers nothing defines - previously a link error
                // naming `@__axiom_bump`, which points at the compiler
                // rather than at the program.
                return Err(
                    "the `__axiom_arena_*` primitives control the built-in bump allocator, and \
                     this program defines its own `axiom_alloc`, which replaces it. An \
                     allocator that wants a waterline has to expose its own."
                        .to_string(),
                );
            }
            IrInst::ArenaMark { dest } => {
                // Both primitives are one call into a runtime helper
                // emitted beside the allocator. They were inline once,
                // and stopped fitting: a reset now walks the chunk list
                // and zeroes what it reclaims, which needs loops, which
                // need blocks of their own.
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = call i64 @__axiom_arena_mark_fn()",
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
                let result_reg = self.new_local_reg();
                writeln!(
                    self.output,
                    "  {} = call i64 @__axiom_arena_reset_fn(i64 {})",
                    result_reg, ptr_val
                )
                .unwrap();
            }
            IrInst::StoreOffset { ptr, offset, value } => {
                let ptr_val = self.value_to_llvm(ptr)?;
                // A field is one machine word, so an `i1` has to be
                // widened before it goes in. `Bool` is the only Axiom
                // type that is narrower than a word, and storing one
                // into a `data` constructor field or a `struct` field
                // emitted `store i64 true` - a constant whose text LLVM
                // reads as `i1` under a declared `i64` - which `llc`
                // rejected. So no constructor or struct could hold a
                // `Bool` at all.
                let val_str = self.value_to_i64(value)?;
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
                // Same widening as `StoreOffset`: the slot is a word.
                let val = self.value_to_i64(value)?;
                writeln!(self.output, "  store i64 {}, ptr {}", val, word_ptr).unwrap();
            }
            IrInst::AddrOf { dest, value } => {
                // `(__addr "...")` means the literal's *bytes*, not the
                // `Str` header the literal otherwise evaluates to. The
                // two differ now that a literal is a header, and this is
                // the only place that difference is observable: it is
                // what keeps `(strFromLit (__addr "..."))` building a
                // header over the bytes rather than over another header,
                // and what lets a literal path reach a syscall.
                if let IrValue::Const(IrConst::Str(s)) = value {
                    let result_reg = self.new_local_reg();
                    writeln!(
                        self.output,
                        "  {} = add i64 {}, 0",
                        result_reg,
                        self.str_bytes_value(s)
                    )
                    .unwrap();
                    if let IrValue::Local(name) = dest {
                        self.ssa_values.insert(
                            name.clone(),
                            (result_reg, TypeId::TCon("I64".to_string(), vec![])),
                        );
                    }
                    return Ok(());
                }
                let (val, ty) = self.value_to_typed_string(value)?;
                let result_reg = self.new_local_reg();
                if ty == "ptr" {
                    // A pointer-typed value renders with its type as
                    // part of `val`, which must not be repeated.
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
    /// The unhandled-effect trap: an effect operation performed with
    /// no handler in dynamic extent calls this instead of continuing
    /// on a garbage dispatch. Exit code 71, distinct from the
    /// allocators' out-of-memory 70, so a golden test's `.exit` file
    /// can tell the two apart.
    fn emit_unhandled_effect_trap(&mut self) {
        let (body, constraints) = self.target.syscall_asm();
        let exit = self.target.sys_exit();
        let out = &mut self.output;
        writeln!(
            out,
            "define internal i64 @__axiom_unhandled_effect() {}{{",
            NO_BUILTINS_ATTR
        )
        .unwrap();
        writeln!(out, "entry:").unwrap();
        writeln!(
            out,
            "  call i64 asm sideeffect \"{}\", \"{}\"(i64 {}, i64 71, i64 0, i64 0, i64 0, i64 0, i64 0)",
            body, constraints, exit
        )
        .unwrap();
        writeln!(out, "  unreachable").unwrap();
        writeln!(out, "}}").unwrap();
        writeln!(out).unwrap();
    }

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
        // Every mapped chunk carries a two-word header - its total size
        // and the chunk mapped before it - so the chunks form a list in
        // allocation order. `@__axiom_chunk` is its head; a reset walks
        // it back to the marked chunk and moves what it passes onto
        // `@__axiom_free`, where the next refill finds it. Without the
        // list a reset could only ever restore a waterline, so every
        // chunk mapped after the mark was stranded: measured at 576 KiB
        // per iteration on a loop whose body crosses a chunk boundary,
        // which is linear growth in exactly the shape §4.1 exists to
        // make constant.
        writeln!(out, "@__axiom_chunk = internal global i64 0").unwrap();
        writeln!(out, "@__axiom_free = internal global i64 0").unwrap();
        // How far into the current chunk memory has ever been handed
        // out. Everything above it is still the zeroes `mmap` gave us;
        // everything below has been written by the program and must be
        // scrubbed before it is handed out again. See the `handout`
        // block for what that buys and why it is not a reset's job.
        writeln!(out, "@__axiom_high = internal global i64 0").unwrap();
        writeln!(out).unwrap();
        writeln!(
            out,
            "define i64 @{}(i64 %size) {}{{",
            ALLOC_SYMBOL, NO_BUILTINS_ATTR
        )
        .unwrap();
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
        writeln!(out, "  %high = load i64, ptr @__axiom_high").unwrap();
        writeln!(out, "  br label %handout").unwrap();
        writeln!(out, "refill:").unwrap();
        // A request bigger than a chunk gets its own mapping,
        // rounded up to a 64 KiB boundary (a page on every
        // supported target, and the largest of them). The header
        // is part of what has to fit.
        writeln!(out, "  %need = add i64 %sz, 16").unwrap();
        writeln!(out, "  %big = icmp ugt i64 %need, {}", CHUNK).unwrap();
        writeln!(out, "  %rounded0 = add i64 %need, 65535").unwrap();
        writeln!(out, "  %rounded = and i64 %rounded0, -65536").unwrap();
        writeln!(
            out,
            "  %chunk = select i1 %big, i64 %rounded, i64 {}",
            CHUNK
        )
        .unwrap();
        // First fit over the chunks a reset has freed. The list is
        // short (it holds only what outlived a mark), and a chunk on
        // it is a whole mapping, so reuse is what keeps a resetting
        // loop's RSS flat rather than merely its waterline.
        writeln!(out, "  %fhead = load i64, ptr @__axiom_free").unwrap();
        writeln!(out, "  br label %scan").unwrap();
        writeln!(out, "scan:").unwrap();
        writeln!(
            out,
            "  %cand = phi i64 [ %fhead, %refill ], [ %cnext, %scan_next ]"
        )
        .unwrap();
        writeln!(
            out,
            "  %prev = phi i64 [ 0, %refill ], [ %cand, %scan_next ]"
        )
        .unwrap();
        writeln!(out, "  %exhausted = icmp eq i64 %cand, 0").unwrap();
        writeln!(out, "  br i1 %exhausted, label %map, label %scan_test").unwrap();
        writeln!(out, "scan_test:").unwrap();
        writeln!(out, "  %candp = inttoptr i64 %cand to ptr").unwrap();
        writeln!(out, "  %candsz = load i64, ptr %candp").unwrap();
        writeln!(out, "  %candlink = add i64 %cand, 8").unwrap();
        writeln!(out, "  %candlinkp = inttoptr i64 %candlink to ptr").unwrap();
        writeln!(out, "  %cnext = load i64, ptr %candlinkp").unwrap();
        writeln!(out, "  %roomy = icmp uge i64 %candsz, %chunk").unwrap();
        writeln!(out, "  br i1 %roomy, label %unlink, label %scan_next").unwrap();
        writeln!(out, "scan_next:").unwrap();
        writeln!(out, "  br label %scan").unwrap();
        writeln!(out, "unlink:").unwrap();
        writeln!(out, "  %cand_end = add i64 %cand, %candsz").unwrap();
        writeln!(out, "  %at_head = icmp eq i64 %prev, 0").unwrap();
        writeln!(out, "  br i1 %at_head, label %unlink_head, label %unlink_mid").unwrap();
        writeln!(out, "unlink_head:").unwrap();
        writeln!(out, "  store i64 %cnext, ptr @__axiom_free").unwrap();
        writeln!(out, "  br label %install").unwrap();
        writeln!(out, "unlink_mid:").unwrap();
        writeln!(out, "  %prevlink = add i64 %prev, 8").unwrap();
        writeln!(out, "  %prevlinkp = inttoptr i64 %prevlink to ptr").unwrap();
        writeln!(out, "  store i64 %cnext, ptr %prevlinkp").unwrap();
        writeln!(out, "  br label %install").unwrap();
        writeln!(out, "map:").unwrap();
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
        writeln!(out, "  %virgin_high = add i64 %addr, 16").unwrap();
        writeln!(out, "  br label %install").unwrap();
        // Link the chunk - mapped or recycled - onto the active list
        // and allocate out of it. The header sits at the base, so the
        // address handed back is base + 16.
        writeln!(out, "install:").unwrap();
        writeln!(
            out,
            "  %base = phi i64 [ %addr, %mapped ], [ %cand, %unlink_head ], [ %cand, %unlink_mid ]"
        )
        .unwrap();
        writeln!(
            out,
            "  %bsize = phi i64 [ %chunk, %mapped ], [ %candsz, %unlink_head ], [ %candsz, %unlink_mid ]"
        )
        .unwrap();
        // The chunk's high water *before* this request is handed out.
        // A recycled chunk is dirty to its last byte; a fresh mapping
        // is the kernel's zeroes all the way down, so nothing in it
        // has ever been handed out. That is the entire difference
        // between the two, and stating it as a high-water mark is what
        // keeps the scrub off the mapping path and off the reset.
        writeln!(
            out,
            "  %chunk_high = phi i64 [ %virgin_high, %mapped ], [ %cand_end, %unlink_head ], [ %cand_end, %unlink_mid ]"
        )
        .unwrap();
        writeln!(out, "  %basep = inttoptr i64 %base to ptr").unwrap();
        writeln!(out, "  store i64 %bsize, ptr %basep").unwrap();
        writeln!(out, "  %baselink = add i64 %base, 8").unwrap();
        writeln!(out, "  %baselinkp = inttoptr i64 %baselink to ptr").unwrap();
        writeln!(out, "  %chead = load i64, ptr @__axiom_chunk").unwrap();
        writeln!(out, "  store i64 %chead, ptr %baselinkp").unwrap();
        writeln!(out, "  store i64 %base, ptr @__axiom_chunk").unwrap();
        writeln!(out, "  %data = add i64 %base, 16").unwrap();
        writeln!(out, "  %new_bump = add i64 %data, %sz").unwrap();
        writeln!(out, "  store i64 %new_bump, ptr @__axiom_bump").unwrap();
        writeln!(out, "  %new_end = add i64 %base, %bsize").unwrap();
        writeln!(out, "  store i64 %new_end, ptr @__axiom_bump_end").unwrap();
        writeln!(out, "  br label %handout").unwrap();
        // Both paths converge here to hand out `[%hb, %he)`. Memory
        // below the high-water mark has been handed out before, so it
        // holds whatever the program last wrote there and has to be
        // scrubbed: `memAlloc` promises zeroed memory and the standard
        // library spends that promise - `Map` and `Intern` read an
        // all-zero state array as "every slot empty", `strAlloc`
        // reserves a byte for its NUL terminator and never writes one.
        // A fresh mapping arrives zeroed from the kernel, so the
        // promise used to hold for free, and silently stopped holding
        // the moment an arena reset handed the same bytes out twice:
        // `strAlloc 3` after a reset measured a `cstrLen` of 17,
        // running off the end of the string into whatever the arena
        // last held there.
        //
        // Scrubbing here rather than in the reset is what makes the
        // difference for §4.1's copy-at-boundary: the value being
        // copied down sits above the restored waterline, in memory the
        // reset gave back, and it has to survive being read until the
        // copy that reads it has finished. A reset that scrubbed would
        // destroy it. This one cannot: it touches a byte only as that
        // byte is handed to a caller.
        writeln!(out, "handout:").unwrap();
        writeln!(out, "  %hb = phi i64 [ %cur, %fast ], [ %data, %install ]").unwrap();
        writeln!(
            out,
            "  %he = phi i64 [ %next, %fast ], [ %new_bump, %install ]"
        )
        .unwrap();
        writeln!(
            out,
            "  %hh = phi i64 [ %high, %fast ], [ %chunk_high, %install ]"
        )
        .unwrap();
        writeln!(out, "  %past = icmp ugt i64 %he, %hh").unwrap();
        writeln!(out, "  %stop = select i1 %past, i64 %hh, i64 %he").unwrap();
        writeln!(out, "  %newhigh = select i1 %past, i64 %he, i64 %hh").unwrap();
        writeln!(out, "  store i64 %newhigh, ptr @__axiom_high").unwrap();
        writeln!(out, "  br label %wipe").unwrap();
        writeln!(out, "wipe:").unwrap();
        writeln!(
            out,
            "  %wi = phi i64 [ %hb, %handout ], [ %wnext, %wipe_body ]"
        )
        .unwrap();
        writeln!(out, "  %wmore = icmp ult i64 %wi, %stop").unwrap();
        writeln!(out, "  br i1 %wmore, label %wipe_body, label %wiped").unwrap();
        writeln!(out, "wipe_body:").unwrap();
        writeln!(out, "  %wp = inttoptr i64 %wi to ptr").unwrap();
        writeln!(out, "  store i64 0, ptr %wp").unwrap();
        writeln!(out, "  %wnext = add i64 %wi, 8").unwrap();
        writeln!(out, "  br label %wipe").unwrap();
        writeln!(out, "wiped:").unwrap();
        writeln!(out, "  ret i64 %hb").unwrap();
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

    /// Emit the two arena primitives as runtime helpers beside the
    /// allocator whose globals they move.
    ///
    /// A mark is the whole allocator position, not just the waterline.
    /// `@__axiom_bump` alone is meaningless once allocation has moved
    /// to a different chunk, because `@__axiom_bump_end` still
    /// describes the newer one - restoring the old bump against the
    /// new end let the fast path succeed on an address in neither
    /// chunk, and a mark taken before the first chunk existed handed
    /// out address 0. So a mark saves bump, end, *and* the chunk that
    /// bump points into, in a three-word cell so marks can nest.
    ///
    /// The cell is allocated *before* the position is read, which is
    /// what puts it below the mark: a reset restores a waterline above
    /// its own cell, so the cell is never re-handed-out and the same
    /// mark can be reset twice.
    ///
    /// A reset restores that position and returns every chunk mapped
    /// since the mark to the free list, so the memory is reused rather
    /// than stranded. It stays O(1) in the memory it reclaims: it
    /// writes no byte of it. Two properties depend on that, and both
    /// are contracts rather than accidents.
    ///
    /// The first is that a reset **scrubs nothing**, so memory above
    /// the restored waterline keeps its contents until it is handed
    /// out again. §4.1's copy-at-boundary needs exactly this: the
    /// value being copied down to the waterline is itself sitting in
    /// the region the reset just gave back, and it has to survive
    /// being read until the copy finishes. The zeroing `memAlloc`
    /// promises is delivered by the allocator's `handout` block
    /// instead, one byte at the moment that byte is handed to a
    /// caller.
    ///
    /// The second is that a mark may be reset twice. The cell is
    /// allocated before the position is read, so it sits *below* its
    /// own waterline and a reset never reclaims it.
    ///
    /// What a reset cannot survive is being applied to a mark taken
    /// before an enclosing mark that has already been reset - the
    /// chunk it names may be on the free list by then. That is a stale
    /// mark, which the primitives' contract already forbids reading;
    /// the walk below stops at the end of the chunk list rather than
    /// running off it.
    fn emit_arena_helpers(&mut self) {
        let out = &mut self.output;
        writeln!(
            out,
            "define internal i64 @__axiom_arena_mark_fn() {}{{",
            NO_BUILTINS_ATTR
        )
        .unwrap();
        writeln!(out, "entry:").unwrap();
        writeln!(out, "  %cell = call i64 @{}(i64 24)", ALLOC_SYMBOL).unwrap();
        writeln!(out, "  %bump = load i64, ptr @__axiom_bump").unwrap();
        writeln!(out, "  %end = load i64, ptr @__axiom_bump_end").unwrap();
        writeln!(out, "  %chunk = load i64, ptr @__axiom_chunk").unwrap();
        writeln!(out, "  %p0 = inttoptr i64 %cell to ptr").unwrap();
        writeln!(out, "  store i64 %bump, ptr %p0").unwrap();
        writeln!(out, "  %a1 = add i64 %cell, 8").unwrap();
        writeln!(out, "  %p1 = inttoptr i64 %a1 to ptr").unwrap();
        writeln!(out, "  store i64 %end, ptr %p1").unwrap();
        writeln!(out, "  %a2 = add i64 %cell, 16").unwrap();
        writeln!(out, "  %p2 = inttoptr i64 %a2 to ptr").unwrap();
        writeln!(out, "  store i64 %chunk, ptr %p2").unwrap();
        writeln!(out, "  ret i64 %cell").unwrap();
        writeln!(out, "}}").unwrap();
        writeln!(out).unwrap();

        writeln!(
            out,
            "define internal i64 @__axiom_arena_reset_fn(i64 %cell) {}{{",
            NO_BUILTINS_ATTR
        )
        .unwrap();
        writeln!(out, "entry:").unwrap();
        writeln!(out, "  %p0 = inttoptr i64 %cell to ptr").unwrap();
        writeln!(out, "  %sbump = load i64, ptr %p0").unwrap();
        writeln!(out, "  %a1 = add i64 %cell, 8").unwrap();
        writeln!(out, "  %p1 = inttoptr i64 %a1 to ptr").unwrap();
        writeln!(out, "  %send = load i64, ptr %p1").unwrap();
        writeln!(out, "  %a2 = add i64 %cell, 16").unwrap();
        writeln!(out, "  %p2 = inttoptr i64 %a2 to ptr").unwrap();
        writeln!(out, "  %schunk = load i64, ptr %p2").unwrap();
        writeln!(out, "  %chead = load i64, ptr @__axiom_chunk").unwrap();
        writeln!(out, "  %same = icmp eq i64 %chead, %schunk").unwrap();
        writeln!(out, "  br i1 %same, label %restore, label %unwind").unwrap();
        // Allocation moved on since the mark, so every chunk between
        // the head and the marked one is wholly garbage now and goes
        // back on the free list, to be handed out again by the next
        // refill. Without this a reset could only ever restore a
        // waterline, and every chunk mapped after the mark was
        // stranded - measured at 576 KiB per iteration on a loop whose
        // body crosses a chunk boundary, which is linear growth in
        // exactly the shape §4.1 exists to make constant.
        //
        // The marked chunk is then dirty from the restored waterline
        // to its end (it was abandoned because it filled up), and
        // saying so is one store: the high-water mark moves to that
        // chunk's end and the scrub happens lazily, on hand-out.
        writeln!(out, "unwind:").unwrap();
        writeln!(
            out,
            "  %c = phi i64 [ %chead, %entry ], [ %cnext, %unwind_body ]"
        )
        .unwrap();
        writeln!(out, "  %reached = icmp eq i64 %c, %schunk").unwrap();
        writeln!(out, "  %ranout = icmp eq i64 %c, 0").unwrap();
        writeln!(out, "  %stop = or i1 %reached, %ranout").unwrap();
        writeln!(out, "  br i1 %stop, label %tail, label %unwind_body").unwrap();
        writeln!(out, "unwind_body:").unwrap();
        writeln!(out, "  %clink = add i64 %c, 8").unwrap();
        writeln!(out, "  %clinkp = inttoptr i64 %clink to ptr").unwrap();
        writeln!(out, "  %cnext = load i64, ptr %clinkp").unwrap();
        writeln!(out, "  %fhead = load i64, ptr @__axiom_free").unwrap();
        writeln!(out, "  store i64 %fhead, ptr %clinkp").unwrap();
        writeln!(out, "  store i64 %c, ptr @__axiom_free").unwrap();
        writeln!(out, "  br label %unwind").unwrap();
        writeln!(out, "tail:").unwrap();
        writeln!(out, "  store i64 %send, ptr @__axiom_high").unwrap();
        writeln!(out, "  br label %restore").unwrap();
        writeln!(out, "restore:").unwrap();
        writeln!(out, "  store i64 %sbump, ptr @__axiom_bump").unwrap();
        writeln!(out, "  store i64 %send, ptr @__axiom_bump_end").unwrap();
        writeln!(out, "  store i64 %schunk, ptr @__axiom_chunk").unwrap();
        writeln!(out, "  ret i64 0").unwrap();
        writeln!(out, "}}").unwrap();
        writeln!(out).unwrap();
    }

    fn value_to_llvm(&self, value: &IrValue) -> Result<String, String> {
        match value {
            IrValue::Tag(name) | IrValue::Local(name) => {
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

    /// Return the register name for `value`, inserting a `zext i1 … to i64`
    /// when the tracked type is `i1`.  Callers that need a machine word
    /// (e.g. `and i64`) call this instead of `value_to_llvm` so that a
    /// comparison result (`Bool`) is widened before it enters a word-level
    /// operation.
    fn value_to_i64(&mut self, value: &IrValue) -> Result<String, String> {
        let (reg, llvm_ty) = self.value_to_typed_string(value)?;
        if llvm_ty == "i1" {
            let widened = self.new_local_reg();
            writeln!(self.output, "  {} = zext i1 {} to i64", widened, reg).unwrap();
            Ok(widened)
        } else {
            Ok(reg)
        }
    }

    fn value_to_typed_string(&self, value: &IrValue) -> Result<(String, String), String> {
        match value {
            IrValue::Tag(name) | IrValue::Local(name) => {
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
                // A float is the uniform machine word holding its
                // IEEE-754 bit pattern, so it is emitted as the integer
                // those bits spell. Writing `double 1.5` instead would
                // disagree with every `i64` the value flows through -
                // parameters, returns, struct fields, `Vec` slots - and
                // LLVM rejects the mismatch rather than coercing.
                IrConst::Float(n, _) => Ok((format!("{}", n.to_bits() as i64), "i64".to_string())),
                IrConst::Bool(b) => Ok((
                    (if *b { "true" } else { "false" }).to_string(),
                    "i1".to_string(),
                )),
                IrConst::Null => Ok(("null".to_string(), "ptr".to_string())),
                IrConst::Str(s) => Ok((self.str_header_value(s), "i64".to_string())),
            },
        }
    }

    fn const_to_llvm_value(&self, const_val: &IrConst) -> String {
        match const_val {
            IrConst::Int(n, _) => format!("{}", n),
            IrConst::Float(n, _) => format!("{}", n.to_bits() as i64),
            IrConst::Bool(b) => (if *b { "true" } else { "false" }).to_string(),
            IrConst::Null => "null".to_string(),
            IrConst::Str(s) => self.str_header_value(s),
        }
    }

    /// The LLVM type a store through `ptr` must supply, when `ptr` names
    /// an `alloca` this function emitted and whose element type is
    /// therefore known. `None` for anything else - a global, a computed
    /// address, a name introduced before its `alloca` - where the value's
    /// own type is the only information available and coercing would be
    /// guessing.
    fn pointee_llvm_type(&self, ptr: &IrValue) -> Option<String> {
        match ptr {
            IrValue::Local(name) => self.locals.get(name).map(|(_, ty)| self.type_to_llvm(ty)),
            _ => None,
        }
    }

    /// `value` widened or narrowed to `want`, as `(register, type)`.
    ///
    /// Widening a comparison result is `zext`, never `sext`: `i1 true`
    /// sign-extends to -1, and Axiom's `true` is 1. Wider-to-narrower is
    /// `trunc`. Anything that is not an integer pair is left alone rather
    /// than reinterpreted, since a bad guess there is a silent
    /// miscompile and the caller's original type is at least honest.
    fn coerce_int(&mut self, val: &str, from: &str, want: &str) -> (String, String) {
        let (from_bits, want_bits) = (llvm_type_bits(from), llvm_type_bits(want));
        let both_ints = from.starts_with('i') && want.starts_with('i');
        if !both_ints || from_bits == want_bits {
            return (val.to_string(), from.to_string());
        }
        let op = if from_bits < want_bits {
            if from == "i1" {
                "zext"
            } else {
                "sext"
            }
        } else {
            "trunc"
        };
        let reg = self.new_local_reg();
        writeln!(
            self.output,
            "  {} = {} {} {} to {}",
            reg, op, from, val, want
        )
        .unwrap();
        (reg, want.to_string())
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

    /// What a string literal evaluates to: the address of its static
    /// `Str` header, as an `i64` LLVM constant expression.
    ///
    /// A constant expression rather than an emitted `ptrtoint`
    /// instruction so a literal stays usable everywhere a constant is -
    /// global initialisers and `phi` operands included - where an
    /// instruction would need a block to live in.
    fn str_header_value(&self, s: &str) -> String {
        let id = self.string_ids.get(s).unwrap_or(&0);
        format!("ptrtoint (ptr @strhdr_{} to i64)", id)
    }

    /// The literal's raw NUL-terminated bytes, as an `i64` constant
    /// expression. This is what `(__addr "...")` resolves to.
    fn str_bytes_value(&self, s: &str) -> String {
        let id = self.string_ids.get(s).unwrap_or(&0);
        format!("ptrtoint (ptr @str_{} to i64)", id)
    }

    fn const_to_llvm(&self, const_val: &IrConst) -> String {
        match const_val {
            IrConst::Int(n, ty) => {
                let llvm_ty = self.type_to_llvm(ty);
                format!("{} {}", llvm_ty, n)
            }
            IrConst::Float(n, _) => format!("i64 {}", n.to_bits() as i64),
            IrConst::Bool(b) => format!("i1 {}", if *b { "true" } else { "false" }),
            IrConst::Null => "ptr null".to_string(),
            IrConst::Str(s) => format!("i64 {}", self.str_header_value(s)),
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
                "Any" => "ptr".to_string(),
                // A `String` is a `Str` handle: the address of a
                // `{ len, bytes }` header, held as a machine word like
                // every other Axiom value. It is `i64` rather than
                // `ptr` so that handles and the `Int`-typed standard
                // library - `memGetWord`, `vecPush`, `Map` keys - mix
                // without a bitcast at every boundary, which is the
                // same uniform-representation choice that lets
                // polymorphism work without monomorphisation.
                //
                // Code that wants the raw C string behind a literal
                // asks for it: `(__addr "...")` for a literal's bytes,
                // `strCStr` for a `Str`'s.
                "String" => "i64".to_string(),
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
        // `__addr` must resolve to the literal's bytes, never to the
        // `Str` header the same literal evaluates to in value position.
        // Getting this backwards is silent: `(strFromLit (__addr s))`
        // would build a header describing a header, and every read of
        // it would return the wrong length and the wrong bytes.
        assert!(ir.contains("ptrtoint (ptr @str_0 to i64)"), "{}", ir);
        assert!(
            !ir.contains("add i64 ptrtoint (ptr @strhdr_0 to i64)"),
            "__addr resolved to the header instead of the bytes: {}",
            ir
        );
    }

    #[test]
    fn a_string_literal_evaluates_to_a_static_str_header() {
        // The header is what makes `(println "hi")` mean what it reads
        // as, and its length is a compile-time constant - the whole
        // point being that `strLen` on a literal is a load rather than
        // the `cstrLen` scan `strFromLit` performs.
        let ir = compile(
            Target::LinuxX86_64,
            vec![IrInst::Call {
                dest: IrValue::Local("r".to_string()),
                func: "println".to_string(),
                args: vec![IrValue::Const(IrConst::Str("hi".to_string()))],
            }],
        );
        assert!(
            ir.contains(
                "@strhdr_0 = private unnamed_addr constant { i64, ptr } \
                 { i64 2, ptr @str_0 }"
            ),
            "{}",
            ir
        );
        // Passed by header, as one machine word.
        assert!(ir.contains("i64 ptrtoint (ptr @strhdr_0 to i64)"), "{}", ir);
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
