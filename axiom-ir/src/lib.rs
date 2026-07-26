pub mod generator;

pub use axiom_sema::TypeId;

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
