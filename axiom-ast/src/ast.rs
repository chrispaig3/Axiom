use crate::span::{Ident, Span};
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
    TLinear(Box<Type>),
}

impl Type {
    pub fn unit() -> Self {
        Type::TTuple(vec![])
    }
    pub fn int() -> Self {
        Type::TCon(Ident::new("Int", Span::dummy()), vec![])
    }
    pub fn bool() -> Self {
        Type::TCon(Ident::new("Bool", Span::dummy()), vec![])
    }
    pub fn string() -> Self {
        Type::TCon(Ident::new("String", Span::dummy()), vec![])
    }
    pub fn float() -> Self {
        Type::TCon(Ident::new("Float", Span::dummy()), vec![])
    }
    pub fn double() -> Self {
        Type::TCon(Ident::new("Double", Span::dummy()), vec![])
    }
    pub fn char() -> Self {
        Type::TCon(Ident::new("Char", Span::dummy()), vec![])
    }
    pub fn void() -> Self {
        Type::TCon(Ident::new("Void", Span::dummy()), vec![])
    }
    pub fn any() -> Self {
        Type::TCon(Ident::new("Any", Span::dummy()), vec![])
    }
    pub fn list(inner: Type) -> Self {
        Type::TList(Box::new(inner))
    }
    pub fn ptr(inner: Type, mutable: bool) -> Self {
        Type::TPtr(Box::new(inner), mutable)
    }
    pub fn arr(from: Type, to: Type) -> Self {
        Type::TArr(Box::new(from), Box::new(to))
    }
    pub fn linear(inner: Type) -> Self {
        Type::TLinear(Box::new(inner))
    }
    pub fn effect(inner: Type, effects: Vec<Effect>) -> Self {
        Type::TEffect(Box::new(inner), effects)
    }
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
    PConNamed(Ident, Vec<(Ident, Pattern)>),
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
    /// Carries the literal token's real span. Previously this variant had
    /// no span field at all and `Expr::span()` fell back to
    /// `Span::dummy()` (byte/char 0), which meant any diagnostic anchored
    /// on a literal - e.g. an `if` condition that's a bare `Int` literal -
    /// silently rendered at `:1:1` instead of its real location.
    ELit(Literal, Span),
    EApp(Box<Expr>, Box<Expr>),
    ELam(Vec<Pattern>, Box<Expr>),
    ELet(Vec<(Pattern, Expr)>, Box<Expr>),
    EIf(Box<Expr>, Box<Expr>, Box<Expr>),
    EMatch(Box<Expr>, Vec<(Pattern, Expr)>),
    ECond(Vec<(Expr, Expr)>, Option<Box<Expr>>),
    EBegin(Vec<Expr>),
    ETuple(Vec<Expr>),
    EList(Vec<Expr>),
    EInfix(Box<Expr>, String, Box<Expr>),
    ETypeSig(Box<Expr>, Type),
    ECast(Box<Expr>, Type),
    EAlloc(Type, Option<Box<Expr>>, Span),
    ESizeof(Type, Span),
    EAlignof(Type, Span),
    EGrouped(Box<Expr>),
    EHandle(Box<Expr>, Vec<Effect>, Box<Expr>),
    EConsume(Box<Expr>),
    EField(Box<Expr>, Ident),
    EStructCon(Ident, Vec<Expr>),
    ESetField(Box<Expr>, Ident, Box<Expr>),
    EError(String, Span),
}

impl Expr {
    pub fn span(&self) -> Span {
        match self {
            Expr::EVar(id) => id.span,
            Expr::ELit(_, span) => *span,
            Expr::EApp(e, _) => e.span(),
            Expr::ELam(_, e) => e.span(),
            Expr::ELet(_, e) => e.span(),
            Expr::EIf(c, _, _) => c.span(),
            Expr::EMatch(e, _) => e.span(),
            Expr::ECond(branches, _) => branches
                .first()
                .map(|(e, _)| e.span())
                .unwrap_or(Span::dummy()),
            Expr::EBegin(es) => es.first().map(|e| e.span()).unwrap_or(Span::dummy()),
            Expr::ETuple(es) => es.first().map(|e| e.span()).unwrap_or(Span::dummy()),
            Expr::EList(es) => es.first().map(|e| e.span()).unwrap_or(Span::dummy()),
            Expr::EInfix(l, _, _) => l.span(),
            Expr::ETypeSig(e, _) => e.span(),
            Expr::ECast(e, _) => e.span(),
            Expr::EAlloc(_, _, span) => *span,
            Expr::ESizeof(_, span) => *span,
            Expr::EAlignof(_, span) => *span,
            Expr::EGrouped(e) => e.span(),
            Expr::EHandle(e, _, _) => e.span(),
            Expr::EConsume(e) => e.span(),
            Expr::EField(e, _) => e.span(),
            Expr::EStructCon(name, _) => name.span,
            Expr::ESetField(e, _, _) => e.span(),
            Expr::EError(_, span) => *span,
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
        /// Content-derived stable node ID: a short hash of
        /// `(kind, name, enclosing-module-path)`. Present for
        /// declarations that have a name and a stable identity
        /// across edits elsewhere in the file (unlike character-offset
        /// spans, which rot when an unrelated edit shifts them).
        nid: Option<String>,
        /// AXTAGS - source-embedded agent metadata preserved from
        /// `;@axiom:<key>(<value>)` comments immediately above this
        /// declaration. The compiler validates what it can (e.g. an
        /// `effect(io)` claim against actual FFI calls in the body)
        /// and surfaces accepted tags as `#`-metadata on AXSYM lines.
        axtags: Vec<Axtag>,
    },
    DStruct {
        name: Ident,
        tyvars: Vec<String>,
        fields: Vec<Field>,
        repr: Option<TypeRepr>,
        nid: Option<String>,
        axtags: Vec<Axtag>,
    },
    DType {
        name: Ident,
        tyvars: Vec<String>,
        alias: Type,
        nid: Option<String>,
        axtags: Vec<Axtag>,
    },
    DTrait {
        name: Ident,
        tyvar: String,
        supertraits: Vec<Type>,
        methods: Vec<TraitMethod>,
        effects: Vec<Effect>,
        nid: Option<String>,
        axtags: Vec<Axtag>,
    },
    DImpl {
        trait_name: Ident,
        ty: Type,
        methods: Vec<(Ident, Expr)>,
        effects: Vec<Effect>,
        nid: Option<String>,
        axtags: Vec<Axtag>,
    },
    DSig {
        name: Ident,
        ty: Type,
        nid: Option<String>,
        axtags: Vec<Axtag>,
    },
    DFn {
        name: Ident,
        params: Vec<Pattern>,
        body: Expr,
        nid: Option<String>,
        axtags: Vec<Axtag>,
    },
    /// A compile-time macro: `(macro (name . params) body)`.
    /// The `params` are a single pattern tree (dotted list) parsed
    /// as a flat `Pattern` – matching occurs against the call-site
    /// argument list, and every `PVar` in the pattern is substituted
    /// into `body` during expansion.
    DMacro {
        name: Ident,
        params: Pattern,
        body: Expr,
        nid: Option<String>,
        axtags: Vec<Axtag>,
    },
    DForeign {
        name: Ident,
        ty: Type,
        source: String,
        nid: Option<String>,
        axtags: Vec<Axtag>,
    },
    /// An `(import Mod.Sub ...)` declaration: module-path resolution,
    /// not a named declaration that participates in NID/AXTAG
    /// indexing (imports don't carry source-stable identities and
    /// can't have agent-authored tags attached to them).
    DImport {
        module: Vec<Ident>,
        names: Vec<Ident>,
    },
    DEffect {
        name: Ident,
        operations: Vec<EffectOp>,
        nid: Option<String>,
        axtags: Vec<Axtag>,
    },
}

/// A source-embedded agent metadata tag preserved from the source
/// for the compiler to surface and (where possible) validate.
///
/// Syntax: `;@axiom:<key>(<value>)` on the line immediately above
/// a declaration. The `;` line-comment prefix is consumed by the
/// lexer; the `@axiom:` marker distinguishes AXTAGS from ordinary
/// comments that the lexer discards entirely.  `(<value>)` is
/// optional - a bare `;@axiom:<key>` (no parentheses) is treated
/// as a flag tag with an empty value.
///
/// Examples recognised by the parser:
/// - `;@axiom:effect(io)`      → Axtag { key: "effect", value: Some("io") }
/// - `;@axiom:pure()`           → Axtag { key: "pure", value: Some("") }
/// - `;@axiom:no_refactor`      → Axtag { key: "no_refactor", value: None }
/// - `;@axiom:owned(arena=frame)` → Axtag { key: "owned", value: Some("arena=frame") }
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Axtag {
    pub key: String,
    pub value: Option<String>,
}

#[derive(Debug, Clone)]
pub struct EffectOp {
    pub name: Ident,
    pub params: Vec<Type>,
    pub return_type: Type,
}

#[derive(Debug, Clone)]
pub enum ConFields {
    Positional(Vec<Type>),
    Named(Vec<Field>),
}

#[derive(Debug, Clone)]
pub struct DataCon {
    pub name: Ident,
    pub con_fields: ConFields,
}

impl DataCon {
    pub fn field_types(&self) -> Vec<&Type> {
        match &self.con_fields {
            ConFields::Positional(tys) => tys.iter().collect(),
            ConFields::Named(fields) => fields.iter().map(|f| &f.ty).collect(),
        }
    }

    pub fn is_nullary(&self) -> bool {
        match &self.con_fields {
            ConFields::Positional(tys) => tys.is_empty(),
            ConFields::Named(fields) => fields.is_empty(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct Field {
    pub name: Ident,
    pub ty: Type,
    pub mutable: bool,
}

#[derive(Debug, Clone)]
pub struct TraitMethod {
    pub name: Ident,
    pub ty: Type,
    pub default: Option<Expr>,
    pub effects: Vec<Effect>,
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

impl Decl {
    /// Return a short key string identifying this declaration
    /// for NID generation.  The key is a combination of the
    /// declaration kind and its name, which is sufficient for
    /// a content-derived stable ID (renaming changes the NID,
    /// whitespace/formatting changes do not).
    pub fn nid_key(&self, out: &mut String) {
        match self {
            Decl::DData { name, .. } => {
                out.push_str("DData:");
                out.push_str(&name.name);
            }
            Decl::DStruct { name, .. } => {
                out.push_str("DStruct:");
                out.push_str(&name.name);
            }
            Decl::DType { name, .. } => {
                out.push_str("DType:");
                out.push_str(&name.name);
            }
            Decl::DTrait { name, .. } => {
                out.push_str("DTrait:");
                out.push_str(&name.name);
            }
            Decl::DImpl { trait_name, .. } => {
                out.push_str("DImpl:");
                out.push_str(&trait_name.name);
            }
            Decl::DSig { name, .. } => {
                out.push_str("DSig:");
                out.push_str(&name.name);
            }
            Decl::DFn { name, .. } => {
                out.push_str("DFn:");
                out.push_str(&name.name);
            }
            Decl::DForeign { name, .. } => {
                out.push_str("DForeign:");
                out.push_str(&name.name);
            }
            Decl::DMacro { name, .. } => {
                out.push_str("DMacro:");
                out.push_str(&name.name);
            }
            Decl::DEffect { name, .. } => {
                out.push_str("DEffect:");
                out.push_str(&name.name);
            }
            Decl::DImport { .. } => {
                out.push_str("DImport");
            }
        }
    }
}
