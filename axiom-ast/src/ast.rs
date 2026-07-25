use crate::span::{Span, Ident};
use std::fmt;

// ============================================================
// Effects
// ============================================================

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Effect {
    Pure,
    IO,
    Alloc,
    Mut,
    Div,
    Err,
    Custom(Ident),
}

impl fmt::Display for Effect {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self {
            Effect::Pure => write!(f, "Pure"),
            Effect::IO => write!(f, "IO"),
            Effect::Alloc => write!(f, "Alloc"),
            Effect::Mut => write!(f, "Mut"),
            Effect::Div => write!(f, "Div"),
            Effect::Err => write!(f, "Err"),
            Effect::Custom(id) => write!(f, "{}", id.name),
        }
    }
}

// ============================================================
// Types
// ============================================================

#[derive(Debug, Clone)]
pub enum Type {
    TVar(String),
    TCon(Ident, Vec<Type>),
    TArr(Box<Type>, Box<Type>),
    TTuple(Vec<Type>),
    TList(Box<Type>),
    TPtr(Box<Type>, bool),
    TForall(Vec<String>, Box<Type>),
    TEffect(Box<Type>, Vec<Effect>),
    TRegion(Box<Type>, Ident),
    TLinear(Box<Type>),
}

impl Type {
    pub fn unit() -> Self { Type::TTuple(vec![]) }
    pub fn int() -> Self { Type::TCon(Ident::new("Int", Span::dummy()), vec![]) }
    pub fn bool() -> Self { Type::TCon(Ident::new("Bool", Span::dummy()), vec![]) }
    pub fn string() -> Self { Type::TCon(Ident::new("String", Span::dummy()), vec![]) }
    pub fn float() -> Self { Type::TCon(Ident::new("Float", Span::dummy()), vec![]) }
    pub fn double() -> Self { Type::TCon(Ident::new("Double", Span::dummy()), vec![]) }
    pub fn char() -> Self { Type::TCon(Ident::new("Char", Span::dummy()), vec![]) }
    pub fn void() -> Self { Type::TCon(Ident::new("Void", Span::dummy()), vec![]) }
    pub fn any() -> Self { Type::TCon(Ident::new("Any", Span::dummy()), vec![]) }
    pub fn list(inner: Type) -> Self { Type::TList(Box::new(inner)) }
    pub fn ptr(inner: Type, mutable: bool) -> Self { Type::TPtr(Box::new(inner), mutable) }
    pub fn arr(from: Type, to: Type) -> Self { Type::TArr(Box::new(from), Box::new(to)) }
    pub fn linear(inner: Type) -> Self { Type::TLinear(Box::new(inner)) }
    pub fn region(inner: Type, name: Ident) -> Self { Type::TRegion(Box::new(inner), name) }
    pub fn effect(inner: Type, effects: Vec<Effect>) -> Self { Type::TEffect(Box::new(inner), effects) }
}

#[derive(Debug, Clone)]
pub enum TypeRepr {
    C,
    Packed,
    Align(usize),
}

// ============================================================
// Patterns
// ============================================================

#[derive(Debug, Clone)]
pub enum Pattern {
    PWildcard,
    PVar(Ident),
    PCon(Ident, Vec<Pattern>),
    PLit(Literal),
    PTuple(Vec<Pattern>),
    PList(Vec<Pattern>),
}

// ============================================================
// Expressions
// ============================================================

#[derive(Debug, Clone)]
pub enum Expr {
    EVar(Ident),
    ELit(Literal),
    EApp(Box<Expr>, Box<Expr>),
    ELam(Vec<Pattern>, Box<Expr>),
    ELet(Vec<(Pattern, Expr)>, Box<Expr>),
    EIf(Box<Expr>, Box<Expr>, Box<Expr>),
    ECase(Box<Expr>, Vec<(Pattern, Expr)>),
    ECond(Vec<(Expr, Expr)>, Option<Box<Expr>>),
    EBegin(Vec<Expr>),
    ETuple(Vec<Expr>),
    EList(Vec<Expr>),
    EInfix(Box<Expr>, String, Box<Expr>),
    ETypeSig(Box<Expr>, Type),
    ECast(Box<Expr>, Type),
    EAlloc(Type, Option<Box<Expr>>),
    ESizeof(Type),
    EAlignof(Type),
    EGrouped(Box<Expr>),
    EHandle(Box<Expr>, Vec<Effect>, Box<Expr>),
    ERegion(Ident, Box<Expr>),
    EConsume(Box<Expr>),
    EError(String),
}

impl Expr {
    pub fn span(&self) -> Span {
        match self {
            Expr::EVar(id) => id.span,
            Expr::ELit(_) => Span::dummy(),
            Expr::EApp(e, _) => e.span(),
            Expr::ELam(_, e) => e.span(),
            Expr::ELet(_, e) => e.span(),
            Expr::EIf(c, _, _) => c.span(),
            Expr::ECase(e, _) => e.span(),
            Expr::ECond(branches, _) => branches.first().map(|(e, _)| e.span()).unwrap_or(Span::dummy()),
            Expr::EBegin(es) => es.first().map(|e| e.span()).unwrap_or(Span::dummy()),
            Expr::ETuple(es) => es.first().map(|e| e.span()).unwrap_or(Span::dummy()),
            Expr::EList(es) => es.first().map(|e| e.span()).unwrap_or(Span::dummy()),
            Expr::EInfix(l, _, _) => l.span(),
            Expr::ETypeSig(e, _) => e.span(),
            Expr::ECast(e, _) => e.span(),
            Expr::EAlloc(_, _) => Span::dummy(),
            Expr::ESizeof(_) => Span::dummy(),
            Expr::EAlignof(_) => Span::dummy(),
            Expr::EGrouped(e) => e.span(),
            Expr::EHandle(e, _, _) => e.span(),
            Expr::ERegion(_, e) => e.span(),
            Expr::EConsume(e) => e.span(),
            Expr::EError(_) => Span::dummy(),
        }
    }
}

#[derive(Debug, Clone)]
pub enum Literal {
    LInt(i64),
    LFloat(f64),
    LBool(bool),
    LChar(char),
    LStr(String),
}

// ============================================================
// Declarations
// ============================================================

#[derive(Debug, Clone)]
pub enum Decl {
    DData {
        name: Ident,
        tyvars: Vec<String>,
        constructors: Vec<DataCon>,
        deriving: Vec<Ident>,
    },
    DStruct {
        name: Ident,
        tyvars: Vec<String>,
        fields: Vec<Field>,
        repr: Option<TypeRepr>,
    },
    DUnion {
        name: Ident,
        tyvars: Vec<String>,
        fields: Vec<Field>,
    },
    DType {
        name: Ident,
        tyvars: Vec<String>,
        alias: Type,
    },
    DClass {
        name: Ident,
        tyvar: String,
        superclasses: Vec<Type>,
        methods: Vec<ClassMethod>,
    },
    DInstance {
        class: Ident,
        ty: Type,
        methods: Vec<(Ident, Expr)>,
    },
    DSig {
        name: Ident,
        ty: Type,
    },
    DFn {
        name: Ident,
        params: Vec<Pattern>,
        body: Expr,
    },
    DForeign {
        name: Ident,
        ty: Type,
        source: String,
    },
    DImport {
        module: Vec<Ident>,
        names: Vec<Ident>,
    },
    DEffect {
        name: Ident,
        operations: Vec<EffectOp>,
    },
}

#[derive(Debug, Clone)]
pub struct EffectOp {
    pub name: Ident,
    pub params: Vec<Type>,
    pub return_type: Type,
}

#[derive(Debug, Clone)]
pub struct DataCon {
    pub name: Ident,
    pub fields: Vec<Type>,
}

#[derive(Debug, Clone)]
pub struct Field {
    pub name: Ident,
    pub ty: Type,
    pub mutable: bool,
}

#[derive(Debug, Clone)]
pub struct ClassMethod {
    pub name: Ident,
    pub ty: Type,
    pub default: Option<Expr>,
}

// ============================================================
// Module
// ============================================================

#[derive(Debug, Clone)]
pub struct Module {
    pub imports: Vec<Decl>,
    pub decls: Vec<Decl>,
    pub span: Span,
}
