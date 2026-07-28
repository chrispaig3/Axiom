use crate::span::{Ident, Span};
use std::fmt::{self, Write};

// ============================================================
// Effects
// ============================================================

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub enum Effect {
    Pure,
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
    pub fn region(inner: Type, name: Ident) -> Self {
        Type::TRegion(Box::new(inner), name)
    }
    pub fn effect(inner: Type, effects: Vec<Effect>) -> Self {
        Type::TEffect(Box::new(inner), effects)
    }
}

#[derive(Debug, Clone)]
pub enum TypeRepr {
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
    ERegion(Ident, Box<Expr>),
    EConsume(Box<Expr>),
    EField(Box<Expr>, Ident),
    EStructCon(Ident, Vec<Expr>),
    ESetField(Box<Expr>, Ident, Box<Expr>),
    /// `` `expr `` — quasiquote template
    EBacktick(Box<Expr>),
    /// `,expr` — unquote (evaluated hole in quasiquote)
    EUnquote(Box<Expr>),
    /// `,@expr` — unquote-splicing (splice list into quasiquote)
    EUnquoteSplicing(Box<Expr>),
    EError(String, Span),
}

// ============================================================
// Macro definitions
// ============================================================

/// A source-level macro definition.
///
/// Syntax:
/// ```scheme
/// (defmacro name (param1 param2 ...)
///   body...)
/// ```
///
/// The body is a single expression (typically using backtick
/// quasiquoting to construct the expansion template).
#[derive(Debug, Clone)]
pub struct MacroDef {
    pub name: Ident,
    pub params: Vec<Pattern>,
    pub body: Expr,
    pub doc: Option<String>,
    pub axtags: Vec<Axtag>,
}

// ============================================================
// Quasiquoting (temporary AST nodes, consumed by macro expansion)
// ============================================================

/// `` `expr `` — quasiquote: template with holes for evaluation
#[derive(Debug, Clone)]
pub enum QuasiquoteForm {
    /// `` `expr `` — template (quoted structure, except for unquote holes)
    Quasiquote(Box<Expr>),
    /// `,expr` — unquote: evaluate and splice value into template
    Unquote(Box<Expr>),
    /// `,@expr` — unquote-splicing: evaluate and splice list of values
    UnquoteSplicing(Box<Expr>),
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
            Expr::ERegion(_, e) => e.span(),
            Expr::EConsume(e) => e.span(),
            Expr::EField(e, _) => e.span(),
            Expr::EStructCon(name, _) => name.span,
            Expr::ESetField(e, _, _) => e.span(),
            Expr::EError(_, span) => *span,
            Expr::EBacktick(e) => e.span(),
            Expr::EUnquote(e) => e.span(),
            Expr::EUnquoteSplicing(e) => e.span(),
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
pub struct StructVariant {
    pub name: Ident,
    pub fields: Vec<Field>,
}

#[derive(Debug, Clone)]
pub enum Decl {
    DStruct {
        name: Ident,
        tyvars: Vec<String>,
        variants: Vec<StructVariant>,
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
    DMacro {
        name: Ident,
        def: MacroDef,
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
/// - `;@axiom:pure()`           → Axtag { key: "pure", value: Some("") }
/// - `;@axiom:no_refactor`      → Axtag { key: "no_refactor", value: None }
/// - `;@axiom:owned(region=0)`  → Axtag { key: "owned", value: Some("region=0") }
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
    /// Return a content-derived key string for NID generation.
    /// The key includes the declaration kind, name, and structural
    /// content (type parameters, fields, signatures, etc.) so that
    /// the NID changes when the declaration's interface changes
    /// but remains stable across formatting-only edits (whitespace,
    /// comment changes, reordering of independent fields).
    pub fn nid_key(&self, out: &mut String) {
        match self {
            Decl::DStruct {
                name,
                tyvars,
                variants,
                repr,
                ..
            } => {
                out.push_str("DStruct:");
                out.push_str(&name.name);
                out.push('(');
                for tv in tyvars {
                    out.push_str(tv);
                    out.push(',');
                }
                out.push(')');
                for v in variants {
                    out.push('[');
                    out.push_str(&v.name.name);
                    for f in &v.fields {
                        out.push('(');
                        if f.mutable {
                            out.push_str("mut ");
                        }
                        out.push_str(&f.name.name);
                        out.push(':');
                        Self::fmt_type_nid(out, &f.ty);
                        out.push(')');
                    }
                    out.push(']');
                }
                if let Some(repr) = repr {
                    out.push_str("{repr=");
                    match repr {
                        TypeRepr::Packed => out.push_str("packed"),
                        TypeRepr::Align(n) => write!(out, "align={}", n).unwrap(),
                    }
                    out.push('}');
                }
            }
            Decl::DType {
                name,
                tyvars,
                alias,
                ..
            } => {
                out.push_str("DType:");
                out.push_str(&name.name);
                out.push('(');
                for tv in tyvars {
                    out.push_str(tv);
                    out.push(',');
                }
                out.push(')');
                out.push('=');
                Self::fmt_type_nid(out, alias);
            }
            Decl::DTrait {
                name,
                tyvar,
                supertraits,
                methods,
                effects,
                ..
            } => {
                out.push_str("DTrait:");
                out.push_str(&name.name);
                out.push('(');
                out.push_str(tyvar);
                out.push(')');
                for st in supertraits {
                    out.push('+');
                    Self::fmt_type_nid(out, st);
                }
                for m in methods {
                    out.push('|');
                    out.push_str(&m.name.name);
                    out.push(':');
                    Self::fmt_type_nid(out, &m.ty);
                    if !m.effects.is_empty() {
                        out.push('{');
                        for e in &m.effects {
                            out.push_str(&format!("{}", e));
                            out.push(',');
                        }
                        out.push('}');
                    }
                }
                if !effects.is_empty() {
                    out.push_str(" effects(");
                    for e in effects {
                        out.push_str(&format!("{}", e));
                        out.push(',');
                    }
                    out.push(')');
                }
            }
            Decl::DImpl {
                trait_name,
                ty,
                methods,
                effects,
                ..
            } => {
                out.push_str("DImpl:");
                out.push_str(&trait_name.name);
                out.push('[');
                Self::fmt_type_nid(out, ty);
                out.push(']');
                for (mname, _) in methods {
                    out.push('|');
                    out.push_str(&mname.name);
                }
                if !effects.is_empty() {
                    out.push_str(" effects(");
                    for e in effects {
                        out.push_str(&format!("{}", e));
                        out.push(',');
                    }
                    out.push(')');
                }
            }
            Decl::DSig { name, ty, .. } => {
                out.push_str("DSig:");
                out.push_str(&name.name);
                out.push('=');
                Self::fmt_type_nid(out, ty);
            }
            Decl::DFn { name, params, .. } => {
                out.push_str("DFn:");
                out.push_str(&name.name);
                out.push('(');
                for p in params {
                    Self::fmt_pattern_nid(out, p);
                    out.push(',');
                }
                out.push(')');
            }
            Decl::DEffect {
                name,
                operations,
                ..
            } => {
                out.push_str("DEffect:");
                out.push_str(&name.name);
                for op in operations {
                    out.push('|');
                    out.push_str(&op.name.name);
                    out.push('(');
                    for param in &op.params {
                        Self::fmt_type_nid(out, param);
                        out.push(',');
                    }
                    out.push(')');
                    out.push(':');
                    Self::fmt_type_nid(out, &op.return_type);
                }
            }
            Decl::DMacro { .. } => {
                out.push_str("DMacro");
            }
            Decl::DImport { .. } => {
                out.push_str("DImport");
            }
        }
    }

    /// Format a [`Type`] into the NID key string, without span information.
    pub fn fmt_type_nid(out: &mut String, ty: &Type) {
        match ty {
            Type::TVar(name) => {
                out.push_str("v");
                out.push_str(name);
            }
            Type::TCon(ident, args) => {
                out.push_str(&ident.name);
                if !args.is_empty() {
                    out.push('(');
                    for (i, arg) in args.iter().enumerate() {
                        if i > 0 {
                            out.push(',');
                        }
                        Self::fmt_type_nid(out, arg);
                    }
                    out.push(')');
                }
            }
            Type::TArr(from, to) => {
                out.push('(');
                Self::fmt_type_nid(out, from);
                out.push_str(" -> ");
                Self::fmt_type_nid(out, to);
                out.push(')');
            }
            Type::TTuple(types) => {
                out.push('(');
                for (i, t) in types.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    Self::fmt_type_nid(out, t);
                }
                out.push(')');
            }
            Type::TList(inner) => {
                out.push('[');
                Self::fmt_type_nid(out, inner);
                out.push(']');
            }
            Type::TPtr(inner, mutable) => {
                if *mutable {
                    out.push_str("*mut ");
                } else {
                    out.push_str("*const ");
                }
                Self::fmt_type_nid(out, inner);
            }
            Type::TForall(vars, inner) => {
                out.push_str("forall ");
                out.push_str(&vars.join(","));
                out.push('.');
                Self::fmt_type_nid(out, inner);
            }
            Type::TEffect(inner, effects) => {
                Self::fmt_type_nid(out, inner);
                if !effects.is_empty() {
                    out.push('{');
                    for e in effects {
                        out.push_str(&format!("{}", e));
                        out.push(',');
                    }
                    out.push('}');
                }
            }
            Type::TRegion(inner, region) => {
                out.push_str("&");
                out.push_str(&region.name);
                out.push(' ');
                Self::fmt_type_nid(out, inner);
            }
            Type::TLinear(inner) => {
                out.push_str("linear ");
                Self::fmt_type_nid(out, inner);
            }
        }
    }

    /// Format a [`Pattern`] into the NID key string, without span information.
    pub fn fmt_pattern_nid(out: &mut String, pat: &Pattern) {
        match pat {
            Pattern::PWildcard => out.push('_'),
            Pattern::PVar(ident) => out.push_str(&ident.name),
            Pattern::PCon(ident, args) => {
                out.push_str(&ident.name);
                if !args.is_empty() {
                    out.push('(');
                    for (i, arg) in args.iter().enumerate() {
                        if i > 0 {
                            out.push(',');
                        }
                        Self::fmt_pattern_nid(out, arg);
                    }
                    out.push(')');
                }
            }
            Pattern::PLit(lit) => match lit {
                Literal::LInt(n) => write!(out, "{}", n).unwrap(),
                Literal::LFloat(n) => write!(out, "{}", n).unwrap(),
                Literal::LBool(b) => write!(out, "{}", b).unwrap(),
                Literal::LChar(c) => write!(out, "'{}'", c).unwrap(),
                Literal::LStr(s) => write!(out, "\"{}\"", s).unwrap(),
            },
            Pattern::PTuple(pats) => {
                out.push('(');
                for (i, p) in pats.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    Self::fmt_pattern_nid(out, p);
                }
                out.push(')');
            }
            Pattern::PList(pats) => {
                out.push('[');
                for (i, p) in pats.iter().enumerate() {
                    if i > 0 {
                        out.push(',');
                    }
                    Self::fmt_pattern_nid(out, p);
                }
                out.push(']');
            }
        }
    }
}
