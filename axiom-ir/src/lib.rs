pub mod generator;

pub use axiom_sema::TypeId;

/// Runtime trap invoked when a `match` matches no arm.
///
/// Defined here rather than in `axiom-codegen` because both sides need
/// the name and the dependency runs ir -> codegen: the generator emits
/// the call, and codegen emits the definition on demand the same way it
/// does for [`crate::ALLOC_SYMBOL`]'s counterpart in that crate.
///
/// A program that reaches it is one sema should have rejected, with one
/// exception that is reachable today: constructor exhaustiveness does not
/// consider *sub*-patterns, so `(match m ((Just 0) a))` type-checks and
/// has no arm for `(Just 1)`. Trapping makes that a diagnosable exit
/// status instead of a silent read of an uninitialised stack slot.
pub const MATCH_FAIL_SYMBOL: &str = "__axiom_match_fail";

#[derive(Debug, Clone)]
pub enum IrInst {
    Const {
        dest: IrValue,
        value: IrConst,
    },
    Add {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Sub {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Mul {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Div {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Mod {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    And {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Or {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Eq {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Neq {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Lt {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Gt {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Le {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Ge {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Not {
        dest: IrValue,
        src: IrValue,
    },
    Neg {
        dest: IrValue,
        src: IrValue,
    },
    BitAnd {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    BitOr {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    BitXor {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Shl {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Shr {
        dest: IrValue,
        lhs: IrValue,
        rhs: IrValue,
    },
    Load {
        dest: IrValue,
        ptr: IrValue,
    },
    Store {
        ptr: IrValue,
        value: IrValue,
    },
    Alloca {
        dest: IrValue,
        ty: TypeId,
    },
    Call {
        dest: IrValue,
        func: String,
        args: Vec<IrValue>,
    },
    Ret {
        value: Option<IrValue>,
    },
    Br {
        target: String,
    },
    CondBr {
        cond: IrValue,
        then_target: String,
        else_target: String,
    },
    Cast {
        dest: IrValue,
        src: IrValue,
        target_ty: TypeId,
    },
    Sizeof {
        dest: IrValue,
        ty: TypeId,
    },
    Alignof {
        dest: IrValue,
        ty: TypeId,
    },

    /// Heap-allocate `size` bytes via the runtime allocator and bind the
    /// resulting address to `dest`, represented (like every other value in
    /// this IR) as a plain `i64`. This is the one primitive Axiom's `data`
    /// constructors are built from: every constructor value - nullary or
    /// not - is a heap-boxed block whose first word is a tag (see
    /// [`StoreOffset`](IrInst::StoreOffset)/[`LoadOffset`](IrInst::LoadOffset)
    /// for how the tag and fields are written/read). Boxing *every*
    /// constructor uniformly, including zero-argument ones, means pattern
    /// matching never needs two different runtime representations for the
    /// same `data` type depending on which constructor produced a given
    /// value.
    HeapAlloc {
        dest: IrValue,
        size: IrValue,
    },
    /// Store `value` at byte offset `offset` from the address held in
    /// `ptr` (itself an `i64`, per [`HeapAlloc`](IrInst::HeapAlloc)).
    /// Offset `0` is always a constructor's tag; offset `8 * (1 + i)` is
    /// its `i`-th field (every field is stored as a plain 8-byte `i64`
    /// word, matching this IR's existing "everything is `i64`" model -
    /// pointers to other boxed values are just `i64` addresses, so nested/
    /// recursive `data` types (`List`, `Tree`, ...) need no special case).
    StoreOffset {
        ptr: IrValue,
        offset: i64,
        value: IrValue,
    },
    /// Load an `i64` from byte offset `offset` from the address held in
    /// `ptr`. The inverse of [`StoreOffset`](IrInst::StoreOffset).
    LoadOffset {
        dest: IrValue,
        ptr: IrValue,
        offset: i64,
    },

    // ========================================================
    // Freestanding primitives
    //
    // The five instructions below are what let Axiom's standard
    // library be written *in Axiom* rather than bound to C: raw
    // OS entry (`Syscall`), dynamically-indexed memory access at
    // byte and word granularity (`LoadIdx`/`StoreIdx` - the
    // existing `LoadOffset`/`StoreOffset` only take a *constant*
    // offset, which is enough for `data`/`struct` fields but not
    // for strings, buffers, or growable arrays), and taking the
    // address of a value (`AddrOf`, needed to hand a string
    // literal to a syscall).
    //
    // None of them reference libc. See `axiom_codegen::Target`
    // for the per-platform syscall ABI each one lowers to.
    // ========================================================
    /// A raw operating-system call. `num` is the syscall number
    /// (already platform-encoded - on Darwin that includes the
    /// `0x2000000` Unix class bit) and `args` holds up to six
    /// integer arguments; `dest` receives the raw return value.
    ///
    /// This is the single primitive that every effectful stdlib
    /// operation (`write`, `read`, `open`, `close`, `exit`,
    /// `mmap`) is built from, and the reason Axiom needs no C FFI
    /// for I/O.
    Syscall {
        dest: IrValue,
        num: IrValue,
        args: Vec<IrValue>,
    },
    /// `dest = zext i8 *(ptr + index)`: load one byte at a
    /// *runtime* index. `index` is a byte offset, not scaled.
    LoadIdx {
        dest: IrValue,
        ptr: IrValue,
        index: IrValue,
    },
    /// `*(i8*)(ptr + index) = trunc i8 value`.
    StoreIdx {
        ptr: IrValue,
        index: IrValue,
        value: IrValue,
    },
    /// `dest = *(i64*)(ptr + index * 8)`: load one machine word at
    /// a runtime *word* index (the `* 8` scaling is applied here so
    /// Axiom-level array code can index in elements, not bytes).
    LoadWordIdx {
        dest: IrValue,
        ptr: IrValue,
        index: IrValue,
    },
    /// `*(i64*)(ptr + index * 8) = value`.
    StoreWordIdx {
        ptr: IrValue,
        index: IrValue,
        value: IrValue,
    },
    /// `dest = ptrtoint(value)`: the address of a value as a plain
    /// integer. Only meaningful for values that are already
    /// pointers at the LLVM level - string constants and globals -
    /// and used to pass a string literal's bytes to a syscall.
    AddrOf {
        dest: IrValue,
        value: IrValue,
    },
}

impl IrInst {
    /// Every string constant this instruction mentions. Used by
    /// codegen to emit the `@str_N` globals *before* any
    /// instruction refers to them.
    ///
    /// Written as an exhaustive match on purpose: a new
    /// instruction variant that can carry an `IrConst::Str` must
    /// fail to compile here until it is accounted for, rather
    /// than silently referencing an `@str_` global that was never
    /// emitted (which is what happened when string collection
    /// only looked at `Call` arguments).
    pub fn string_consts(&self) -> Vec<&str> {
        fn of(v: &IrValue) -> Option<&str> {
            match v {
                IrValue::Const(IrConst::Str(s)) => Some(s.as_str()),
                _ => None,
            }
        }
        match self {
            IrInst::Const { value, .. } => match value {
                IrConst::Str(s) => vec![s.as_str()],
                _ => Vec::new(),
            },
            IrInst::Call { args, .. } => args.iter().filter_map(of).collect(),
            IrInst::Syscall { num, args, .. } => std::iter::once(num)
                .chain(args.iter())
                .filter_map(of)
                .collect(),
            IrInst::AddrOf { value, .. } => of(value).into_iter().collect(),
            IrInst::Ret { value } => value.as_ref().and_then(of).into_iter().collect(),
            IrInst::Store { ptr, value } => [ptr, value].into_iter().filter_map(of).collect(),
            IrInst::StoreOffset { ptr, value, .. } => {
                [ptr, value].into_iter().filter_map(of).collect()
            }
            IrInst::StoreIdx { ptr, index, value } | IrInst::StoreWordIdx { ptr, index, value } => {
                [ptr, index, value].into_iter().filter_map(of).collect()
            }
            IrInst::LoadIdx { ptr, index, .. } | IrInst::LoadWordIdx { ptr, index, .. } => {
                [ptr, index].into_iter().filter_map(of).collect()
            }
            IrInst::Load { ptr, .. } => of(ptr).into_iter().collect(),
            IrInst::LoadOffset { ptr, .. } => of(ptr).into_iter().collect(),
            IrInst::Add { lhs, rhs, .. }
            | IrInst::Sub { lhs, rhs, .. }
            | IrInst::Mul { lhs, rhs, .. }
            | IrInst::Div { lhs, rhs, .. }
            | IrInst::Mod { lhs, rhs, .. }
            | IrInst::And { lhs, rhs, .. }
            | IrInst::Or { lhs, rhs, .. }
            | IrInst::Eq { lhs, rhs, .. }
            | IrInst::Neq { lhs, rhs, .. }
            | IrInst::Lt { lhs, rhs, .. }
            | IrInst::Gt { lhs, rhs, .. }
            | IrInst::Le { lhs, rhs, .. }
            | IrInst::Ge { lhs, rhs, .. }
            | IrInst::BitAnd { lhs, rhs, .. }
            | IrInst::BitOr { lhs, rhs, .. }
            | IrInst::BitXor { lhs, rhs, .. }
            | IrInst::Shl { lhs, rhs, .. }
            | IrInst::Shr { lhs, rhs, .. } => [lhs, rhs].into_iter().filter_map(of).collect(),
            IrInst::Not { src, .. } | IrInst::Neg { src, .. } | IrInst::Cast { src, .. } => {
                of(src).into_iter().collect()
            }
            IrInst::HeapAlloc { size, .. } => of(size).into_iter().collect(),
            IrInst::CondBr { cond, .. } => of(cond).into_iter().collect(),
            IrInst::Alloca { .. }
            | IrInst::Br { .. }
            | IrInst::Sizeof { .. }
            | IrInst::Alignof { .. } => Vec::new(),
        }
    }
}

#[derive(Debug, Clone)]
pub enum IrValue {
    Local(String),
    Global(String),
    Const(IrConst),
}

#[derive(Debug, Clone)]
pub enum IrConst {
    Int(i64, TypeId),
    Float(f64, TypeId),
    Bool(bool),
    Null,
    Str(String),
}

#[derive(Debug, Clone)]
pub struct IrBlock {
    pub label: String,
    pub insts: Vec<IrInst>,
}

#[derive(Debug, Clone)]
pub struct IrFunction {
    pub name: String,
    pub params: Vec<(String, TypeId)>,
    pub return_type: TypeId,
    pub blocks: Vec<IrBlock>,
    pub locals: Vec<(String, TypeId)>,
}

#[derive(Debug, Clone)]
pub struct IrStruct {
    pub name: String,
    pub fields: Vec<(String, TypeId)>,
    pub packed: bool,
    pub align: Option<usize>,
}

#[derive(Debug, Clone)]
pub struct IrEnum {
    pub name: String,
    pub variants: Vec<(String, Option<TypeId>)>,
    pub tag_type: TypeId,
}

#[derive(Debug, Clone)]
pub struct IrGlobal {
    pub name: String,
    pub ty: TypeId,
    pub value: IrConst,
    pub is_const: bool,
}

#[derive(Debug, Clone)]
pub struct IrModule {
    pub functions: Vec<IrFunction>,
    pub structs: Vec<IrStruct>,
    pub enums: Vec<IrEnum>,
    pub globals: Vec<IrGlobal>,
    pub extern_funcs: Vec<(String, Vec<TypeId>, TypeId)>,
}

impl Default for IrModule {
    fn default() -> Self {
        Self::new()
    }
}

impl IrModule {
    pub fn new() -> Self {
        Self {
            functions: Vec::new(),
            structs: Vec::new(),
            enums: Vec::new(),
            globals: Vec::new(),
            extern_funcs: Vec::new(),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn i64_ty() -> TypeId {
        TypeId::TCon("I64".to_string(), vec![])
    }

    fn s(text: &str) -> IrValue {
        IrValue::Const(IrConst::Str(text.to_string()))
    }

    #[test]
    fn string_constants_are_found_in_every_instruction_that_can_carry_one() {
        // Codegen emits `@str_N` globals from this list, so an
        // instruction missing from it produces IR that references a
        // global which was never defined - an `llc` failure rather than
        // a diagnostic. `AddrOf` and `Syscall` are the cases that
        // regressed when only `Call` was scanned.
        let cases: Vec<(IrInst, Vec<&str>)> = vec![
            (
                IrInst::AddrOf {
                    dest: IrValue::Local("d".into()),
                    value: s("addr"),
                },
                vec!["addr"],
            ),
            (
                IrInst::Syscall {
                    dest: IrValue::Local("d".into()),
                    num: IrValue::Const(IrConst::Int(1, i64_ty())),
                    args: vec![s("arg")],
                },
                vec!["arg"],
            ),
            (
                IrInst::Call {
                    dest: IrValue::Local("d".into()),
                    func: "f".into(),
                    args: vec![s("call")],
                },
                vec!["call"],
            ),
            (
                IrInst::Const {
                    dest: IrValue::Local("d".into()),
                    value: IrConst::Str("konst".into()),
                },
                vec!["konst"],
            ),
            (
                IrInst::StoreIdx {
                    ptr: s("ptr"),
                    index: IrValue::Const(IrConst::Int(0, i64_ty())),
                    value: s("val"),
                },
                vec!["ptr", "val"],
            ),
            (
                IrInst::Ret {
                    value: Some(s("r")),
                },
                vec!["r"],
            ),
        ];

        for (inst, expected) in cases {
            assert_eq!(inst.string_consts(), expected, "{:?}", inst);
        }
    }

    #[test]
    fn instructions_without_strings_report_none() {
        let insts = vec![
            IrInst::Alloca {
                dest: IrValue::Local("a".into()),
                ty: i64_ty(),
            },
            IrInst::Br { target: "b".into() },
            IrInst::Add {
                dest: IrValue::Local("d".into()),
                lhs: IrValue::Const(IrConst::Int(1, i64_ty())),
                rhs: IrValue::Const(IrConst::Int(2, i64_ty())),
            },
            IrInst::Ret { value: None },
        ];
        for inst in insts {
            assert!(inst.string_consts().is_empty(), "{:?}", inst);
        }
    }
}
