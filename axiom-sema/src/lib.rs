use axiom_ast::ast::*;
use axiom_ast::span::{Ident, Span};
use axiom_errors::{code, Diagnostic};

#[derive(Debug, thiserror::Error)]
pub enum SemError {
    #[error("undefined variable `{name}`")]
    UndefinedVariable {
        name: String,
        span: Span,
        suggestion: Option<String>,
    },
    #[error("undefined type `{name}`")]
    UndefinedType {
        name: String,
        span: Span,
        suggestion: Option<String>,
    },
    #[error("undefined constructor `{name}`")]
    UndefinedConstructor {
        name: String,
        span: Span,
        suggestion: Option<String>,
    },
    #[error("constructor `{name}` expects {expected} argument(s), found {found}")]
    ConstructorArity {
        name: String,
        expected: usize,
        found: usize,
        span: Span,
    },
    #[error("type mismatch: expected {expected}, found {found}")]
    TypeMismatch {
        expected: String,
        found: String,
        span: Span,
    },
    #[error("non-exhaustive pattern match: missing {}", missing.join(", "))]
    NonExhaustive { span: Span, missing: Vec<String> },
    #[error("duplicate definition `{name}`")]
    DuplicateDefinition {
        name: String,
        span: Span,
        first_span: Span,
    },
    #[error("field `{field}` not found on type `{ty}`")]
    FieldNotFound {
        field: String,
        ty: String,
        span: Span,
    },
    #[error("{message}")]
    Message { message: String, span: Span },
    #[error("AXTAG mismatch on `{name}`: {message}")]
    AxtagMismatch {
        name: String,
        message: String,
        span: Span,
    },
    #[error("effect mismatch: {message}")]
    EffectMismatch { message: String, span: Span },
}

impl SemError {
    pub fn span(&self) -> Span {
        match self {
            SemError::UndefinedVariable { span, .. } => *span,
            SemError::UndefinedType { span, .. } => *span,
            SemError::UndefinedConstructor { span, .. } => *span,
            SemError::ConstructorArity { span, .. } => *span,
            SemError::TypeMismatch { span, .. } => *span,
            SemError::NonExhaustive { span, .. } => *span,
            SemError::DuplicateDefinition { span, .. } => *span,
            SemError::FieldNotFound { span, .. } => *span,
            SemError::Message { span, .. } => *span,
            SemError::AxtagMismatch { span, .. } => *span,
            SemError::EffectMismatch { span, .. } => *span,
        }
    }

    /// Convert into a renderer-agnostic [`Diagnostic`], including
    /// "did you mean `foo`?" suggestions computed from names actually in
    /// scope (see [`TypeChecker::suggest_name`]).
    pub fn to_diagnostic(&self) -> Diagnostic {
        let span = self.span();
        match self {
            SemError::UndefinedVariable {
                name, suggestion, ..
            } => {
                let mut d = Diagnostic::error(&code::UNDEFINED_VARIABLE, self.to_string())
                    .with_primary(span, format!("no binding named `{}` in scope", name));
                d = match suggestion {
                    Some(s) => d.with_suggestion(
                        format!(
                            "a similarly named binding `{}` is in scope; did you mean this?",
                            s
                        ),
                        span,
                        s.clone(),
                    ),
                    None => d.with_help(
                        "variables must be defined (via `define`/`fn`, a `let` binding, or a \
                         lambda parameter) before they are used; check for typos",
                    ),
                };
                d
            }
            SemError::UndefinedType {
                name, suggestion, ..
            } => {
                let mut d = Diagnostic::error(&code::UNDEFINED_TYPE, self.to_string())
                    .with_primary(span, format!("no type named `{}` is visible here", name));
                d = match suggestion {
                    Some(s) => d.with_suggestion(
                        format!(
                            "a similarly named type `{}` is visible; did you mean this?",
                            s
                        ),
                        span,
                        s.clone(),
                    ),
                    None => d.with_help(
                        "check for typos, or a missing `data`/`struct`/`type` declaration",
                    ),
                };
                d
            }
            SemError::UndefinedConstructor {
                name, suggestion, ..
            } => {
                let mut d = Diagnostic::error(&code::UNDEFINED_CONSTRUCTOR, self.to_string())
                    .with_primary(
                        span,
                        format!("no constructor named `{}` is visible here", name),
                    );
                d = match suggestion {
                    Some(s) => d.with_suggestion(
                        format!(
                            "a similarly named constructor `{}` is visible; did you mean this?",
                            s
                        ),
                        span,
                        s.clone(),
                    ),
                    None => {
                        d.with_help("check the `data` declaration for the correct constructor name")
                    }
                };
                d
            }
            SemError::ConstructorArity {
                expected, found, ..
            } => Diagnostic::error(&code::CONSTRUCTOR_ARITY, self.to_string())
                .with_primary(span, format!("{} argument(s) provided here", found))
                .with_help(format!(
                    "this constructor takes exactly {} field(s); add or remove arguments to match",
                    expected
                )),
            SemError::TypeMismatch {
                expected, found, ..
            } => {
                // The heading (`self.to_string()`) already states
                // `expected X, found Y`; the primary label only needs to
                // point at *where* - repeating expected/found a second
                // time in a note added no new information.
                Diagnostic::error(&code::TYPE_MISMATCH, self.to_string()).with_primary(
                    span,
                    format!("this has type `{}`, expected `{}`", found, expected),
                )
            }
            SemError::NonExhaustive { missing, .. } => {
                Diagnostic::error(&code::NON_EXHAUSTIVE, self.to_string())
                    .with_primary(
                        span,
                        format!("this `match` does not cover: {}", missing.join(", ")),
                    )
                    .with_help("add the missing arms, or a wildcard `_` arm to catch the rest")
            }
            SemError::DuplicateDefinition {
                name, first_span, ..
            } => Diagnostic::error(&code::DUPLICATE_DEFINITION, self.to_string())
                .with_primary(span, format!("`{}` redefined here", name))
                .with_secondary(*first_span, format!("`{}` first defined here", name))
                .with_help("rename one of the definitions, or remove the duplicate"),
            SemError::FieldNotFound { field, ty, .. } => {
                Diagnostic::error(&code::FIELD_NOT_FOUND, self.to_string())
                    .with_primary(span, format!("no field `{}` on `{}`", field, ty))
                    .with_help(format!(
                        "check the field name and the definition of `{}`",
                        ty
                    ))
            }
            SemError::Message { message, .. } => {
                Diagnostic::error(&code::SEMA_MESSAGE, message.clone())
                    .with_primary(span, message.clone())
            }
            SemError::AxtagMismatch { name, message, .. } => {
                Diagnostic::warning(&code::AXTAG_MISMATCH, self.to_string())
                    .with_primary(span, format!("`{}`: {}", name, message))
            }
            SemError::EffectMismatch { message, .. } => {
                Diagnostic::error(&code::EFFECT_MISMATCH, self.to_string())
                    .with_primary(span, message.clone())
            }
        }
    }
}

fn collect_effects(checker: &TypeChecker, expr: &Expr) -> Vec<axiom_ast::ast::Effect> {
    use std::collections::HashSet;
    let mut set = HashSet::new();
    collect_effects_into(checker, expr, &mut set);
    let mut v: Vec<_> = set.into_iter().collect();
    v.sort_by(|a, b| format!("{}", a).cmp(&format!("{}", b)));
    v
}

/// Like `collect_effects`, but does not strip effects handled
/// by `handle` expressions. Used for AXTAG validation where we
/// need to know if the body *performs* an effect at all, regardless
/// of whether it is contained by `handle`.
fn collect_effects_all(checker: &TypeChecker, expr: &Expr) -> Vec<axiom_ast::ast::Effect> {
    use std::collections::HashSet;
    let mut set = HashSet::new();
    collect_effects_all_into(checker, expr, &mut set);
    let mut v: Vec<_> = set.into_iter().collect();
    v.sort_by(|a, b| format!("{}", a).cmp(&format!("{}", b)));
    v
}

fn collect_effects_into(
    checker: &TypeChecker,
    expr: &Expr,
    out: &mut std::collections::HashSet<axiom_ast::ast::Effect>,
) {
    match expr {
        Expr::EVar(ident) => {
            if checker
                .functions
                .iter()
                .any(|f| f.name == ident.name && f.foreign_symbol.is_some())
            {
                out.insert(axiom_ast::ast::Effect::IO);
            }
        }
        Expr::EApp(func, arg) => {
            collect_effects_into(checker, func, out);
            collect_effects_into(checker, arg, out);
        }
        Expr::ELam(_, body) => collect_effects_into(checker, body, out),
        Expr::ELet(bindings, body) => {
            for (_, e) in bindings {
                collect_effects_into(checker, e, out);
            }
            collect_effects_into(checker, body, out);
        }
        Expr::EIf(_, t, e) => {
            collect_effects_into(checker, t, out);
            collect_effects_into(checker, e, out);
        }
        Expr::EMatch(target, arms) => {
            collect_effects_into(checker, target, out);
            for (_, e) in arms {
                collect_effects_into(checker, e, out);
            }
        }
        Expr::ECond(branches, else_) => {
            for (c, e) in branches {
                collect_effects_into(checker, c, out);
                collect_effects_into(checker, e, out);
            }
            if let Some(e) = else_ {
                collect_effects_into(checker, e, out);
            }
        }
        Expr::EBegin(es) | Expr::ETuple(es) | Expr::EList(es) => {
            for e in es {
                collect_effects_into(checker, e, out);
            }
        }
        Expr::EInfix(l, _, r) => {
            collect_effects_into(checker, l, out);
            collect_effects_into(checker, r, out);
        }
        Expr::ETypeSig(e, _) | Expr::ECast(e, _) | Expr::EGrouped(e) => {
            collect_effects_into(checker, e, out);
        }
        Expr::EAlloc(_, init, _) => {
            out.insert(axiom_ast::ast::Effect::Alloc);
            if let Some(e) = init {
                collect_effects_into(checker, e, out);
            }
        }
        Expr::ESizeof(_, _) | Expr::EAlignof(_, _) | Expr::EError(_, _) => {}
        Expr::ELit(_, _) => {}
        Expr::EHandle(body, handled, _handler) => {
            let mut body_effects = std::collections::HashSet::new();
            collect_effects_into(checker, body, &mut body_effects);
            for e in body_effects {
                if !handled.contains(&e) {
                    out.insert(e);
                }
            }
        }
        Expr::ERegion(_, e) => collect_effects_into(checker, e, out),
        Expr::EConsume(e) => collect_effects_into(checker, e, out),
        Expr::EField(e, _) => collect_effects_into(checker, e, out),
        Expr::EStructCon(_, args) => {
            for e in args {
                collect_effects_into(checker, e, out);
            }
        }
        Expr::ESetField(base, _, value) => {
            collect_effects_into(checker, base, out);
            collect_effects_into(checker, value, out);
            out.insert(axiom_ast::ast::Effect::Mut);
        }
        Expr::EUnionCon(_, _, value) => collect_effects_into(checker, value, out),
    }
}

fn collect_effects_all_into(
    checker: &TypeChecker,
    expr: &Expr,
    out: &mut std::collections::HashSet<axiom_ast::ast::Effect>,
) {
    match expr {
        Expr::EVar(ident) => {
            if checker
                .functions
                .iter()
                .any(|f| f.name == ident.name && f.foreign_symbol.is_some())
            {
                out.insert(axiom_ast::ast::Effect::IO);
            }
        }
        Expr::EApp(func, arg) => {
            collect_effects_all_into(checker, func, out);
            collect_effects_all_into(checker, arg, out);
        }
        Expr::ELam(_, body) => collect_effects_all_into(checker, body, out),
        Expr::ELet(bindings, body) => {
            for (_, e) in bindings {
                collect_effects_all_into(checker, e, out);
            }
            collect_effects_all_into(checker, body, out);
        }
        Expr::EIf(_, t, e) => {
            collect_effects_all_into(checker, t, out);
            collect_effects_all_into(checker, e, out);
        }
        Expr::EMatch(target, arms) => {
            collect_effects_all_into(checker, target, out);
            for (_, e) in arms {
                collect_effects_all_into(checker, e, out);
            }
        }
        Expr::ECond(branches, else_) => {
            for (c, e) in branches {
                collect_effects_all_into(checker, c, out);
                collect_effects_all_into(checker, e, out);
            }
            if let Some(e) = else_ {
                collect_effects_all_into(checker, e, out);
            }
        }
        Expr::EBegin(es) | Expr::ETuple(es) | Expr::EList(es) => {
            for e in es {
                collect_effects_all_into(checker, e, out);
            }
        }
        Expr::EInfix(l, _, r) => {
            collect_effects_all_into(checker, l, out);
            collect_effects_all_into(checker, r, out);
        }
        Expr::ETypeSig(e, _) | Expr::ECast(e, _) | Expr::EGrouped(e) => {
            collect_effects_all_into(checker, e, out);
        }
        Expr::EAlloc(_, init, _) => {
            out.insert(axiom_ast::ast::Effect::Alloc);
            if let Some(e) = init {
                collect_effects_all_into(checker, e, out);
            }
        }
        Expr::ESizeof(_, _) | Expr::EAlignof(_, _) | Expr::EError(_, _) => {}
        Expr::ELit(_, _) => {}
        Expr::EHandle(body, _, _handler) => {
            collect_effects_all_into(checker, body, out);
        }
        Expr::ERegion(_, e) => collect_effects_all_into(checker, e, out),
        Expr::EConsume(e) => collect_effects_all_into(checker, e, out),
        Expr::EField(e, _) => collect_effects_all_into(checker, e, out),
        Expr::EStructCon(_, args) => {
            for e in args {
                collect_effects_all_into(checker, e, out);
            }
        }
        Expr::ESetField(base, _, value) => {
            collect_effects_all_into(checker, base, out);
            collect_effects_all_into(checker, value, out);
            out.insert(axiom_ast::ast::Effect::Mut);
        }
        Expr::EUnionCon(_, _, value) => collect_effects_all_into(checker, value, out),
    }
}
/// distance, for "did you mean `foo`?" suggestions. Only returns a match
/// that's close enough to plausibly be a typo (distance <= 2, and no more
/// than half the length of the shorter string) so we don't suggest
/// nonsense for genuinely unrelated names.
fn suggest_closest<'a>(name: &str, candidates: impl Iterator<Item = &'a str>) -> Option<String> {
    let mut best: Option<(&str, usize)> = None;
    for candidate in candidates {
        if candidate == name || candidate.starts_with("__") {
            continue;
        }
        let dist = levenshtein(name, candidate);
        let threshold = (name.len().min(candidate.len()) / 2).clamp(1, 2);
        if dist <= threshold && best.is_none_or(|(_, d)| dist < d) {
            best = Some((candidate, dist));
        }
    }
    best.map(|(s, _)| s.to_string())
}

fn levenshtein(a: &str, b: &str) -> usize {
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let mut prev: Vec<usize> = (0..=b.len()).collect();
    let mut curr = vec![0usize; b.len() + 1];
    for i in 1..=a.len() {
        curr[0] = i;
        for j in 1..=b.len() {
            let cost = if a[i - 1] == b[j - 1] { 0 } else { 1 };
            curr[j] = (prev[j] + 1).min(curr[j - 1] + 1).min(prev[j - 1] + cost);
        }
        std::mem::swap(&mut prev, &mut curr);
    }
    prev[b.len()]
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub enum TypeId {
    TVar(String),
    TCon(String, Vec<TypeId>),
    TArr(Box<TypeId>, Box<TypeId>),
    TTuple(Vec<TypeId>),
    TList(Box<TypeId>),
    TPtr(Box<TypeId>, bool),
    TForall(Vec<String>, Box<TypeId>),
    TEffect(Box<TypeId>, Vec<axiom_ast::ast::Effect>),
    /// A "poison" type produced after an error has already been reported
    /// for this expression (e.g. an undefined variable). Poison types are
    /// deliberately treated as compatible with everything downstream so
    /// that one root-cause error doesn't cascade into a wall of unrelated
    /// type-mismatch errors about the same expression - the single
    /// biggest source of noisy, confusing diagnostics before this change.
    TError,
}

impl TypeId {
    pub fn is_error(&self) -> bool {
        matches!(self, TypeId::TError)
    }

    /// Are `self` and `other` compatible, treating a [`TypeId::TVar`] -
    /// *anywhere*, not just at the top level - as a wildcard that matches
    /// anything?
    ///
    /// This checker has no real unification/substitution: a generic
    /// constructor's field type (e.g. `Node :: (Tree a) -> a -> (Tree a)
    /// -> Tree a`) is bound to a pattern variable exactly as written,
    /// tyvar and all, never substituted with the scrutinee's actual type
    /// argument - so a recursive call like `(sumTree l)` inside `(match t
    /// ((Node l v r) ...))` sees `l`'s type as `(Tree a)`, not `(Tree
    /// Int)`, even when `t : Tree Int`. Plain structural equality
    /// (`PartialEq`) would call that a mismatch against a signature
    /// expecting `(Tree Int)`, which is a false positive: `(Tree a)` and
    /// `(Tree Int)` really are the same type here, just not fully
    /// resolved by this checker. Treating every `TVar` as matching
    /// anything is the deliberately conservative fix - it can't turn a
    /// real mismatch into a false negative for any type this checker
    /// actually produces today (an *unresolved* `TVar` never occurs next
    /// to a genuinely different concrete type in an already-working
    /// program), while it does suppress exactly this kind of
    /// generics-shaped false positive.
    ///
    /// Used everywhere two inferred types are compared for a type error
    /// (`if`/`cond` branches, function-call arguments): see call sites.
    pub fn compatible_with(&self, other: &TypeId) -> bool {
        match (self, other) {
            (TypeId::TVar(_), _) | (_, TypeId::TVar(_)) => true,
            (TypeId::TError, _) | (_, TypeId::TError) => true,
            (TypeId::TCon(n1, args1), TypeId::TCon(n2, args2)) => {
                n1 == n2
                    && args1.len() == args2.len()
                    && args1.iter().zip(args2).all(|(a, b)| a.compatible_with(b))
            }
            (TypeId::TArr(p1, r1), TypeId::TArr(p2, r2)) => {
                p1.compatible_with(p2) && r1.compatible_with(r2)
            }
            (TypeId::TTuple(t1), TypeId::TTuple(t2)) => {
                t1.len() == t2.len() && t1.iter().zip(t2).all(|(a, b)| a.compatible_with(b))
            }
            (TypeId::TList(a), TypeId::TList(b)) => a.compatible_with(b),
            (TypeId::TPtr(a, m1), TypeId::TPtr(b, m2)) => m1 == m2 && a.compatible_with(b),
            (TypeId::TForall(_, a), _) => a.compatible_with(other),
            (_, TypeId::TForall(_, b)) => self.compatible_with(b),
            (TypeId::TEffect(a, effs1), TypeId::TEffect(b, effs2)) => {
                effs1 == effs2 && a.compatible_with(b)
            }
            _ => self == other,
        }
    }

    /// Remove the given effects from a type, stripping `TEffect` wrappers
    /// whose effect set is a subset of `handled`. Used by `handle` to
    /// produce the handler's result type.
    pub fn strip_effects(ty: &TypeId, handled: &[axiom_ast::ast::Effect]) -> TypeId {
        match ty {
            TypeId::TEffect(inner, effs) => {
                let remaining: Vec<axiom_ast::ast::Effect> = effs
                    .iter()
                    .filter(|e| !handled.contains(e))
                    .cloned()
                    .collect();
                if remaining.is_empty() {
                    Self::strip_effects(inner, handled)
                } else {
                    TypeId::TEffect(Box::new(Self::strip_effects(inner, handled)), remaining)
                }
            }
            TypeId::TArr(a, b) => TypeId::TArr(
                Box::new(Self::strip_effects(a, handled)),
                Box::new(Self::strip_effects(b, handled)),
            ),
            TypeId::TTuple(types) => TypeId::TTuple(
                types
                    .iter()
                    .map(|t| Self::strip_effects(t, handled))
                    .collect(),
            ),
            TypeId::TList(inner) => TypeId::TList(Box::new(Self::strip_effects(inner, handled))),
            TypeId::TPtr(inner, mutable) => {
                TypeId::TPtr(Box::new(Self::strip_effects(inner, handled)), *mutable)
            }
            TypeId::TForall(vars, inner) => {
                TypeId::TForall(vars.clone(), Box::new(Self::strip_effects(inner, handled)))
            }
            _ => ty.clone(),
        }
    }
}

impl std::fmt::Display for TypeId {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            TypeId::TError => write!(f, "{{unknown}}"),
            TypeId::TVar(name) => write!(f, "{}", name),
            TypeId::TCon(name, args) => {
                if args.is_empty() {
                    write!(f, "{}", name)
                } else {
                    write!(f, "{}", name)?;
                    for arg in args {
                        write!(f, " {}", arg)?;
                    }
                    Ok(())
                }
            }
            TypeId::TArr(a, b) => write!(f, "({} -> {})", a, b),
            TypeId::TTuple(types) => {
                write!(f, "(")?;
                for (i, t) in types.iter().enumerate() {
                    if i > 0 {
                        write!(f, ", ")?;
                    }
                    write!(f, "{}", t)?;
                }
                write!(f, ")")
            }
            TypeId::TList(inner) => write!(f, "[{}]", inner),
            TypeId::TPtr(inner, mut_) => {
                if *mut_ {
                    write!(f, "*mut {}", inner)
                } else {
                    write!(f, "*{}", inner)
                }
            }
            TypeId::TForall(vars, inner) => {
                write!(f, "forall {}. ", vars.join(", "))?;
                write!(f, "{}", inner)
            }
            TypeId::TEffect(inner, effects) => {
                write!(f, "({}", inner)?;
                for e in effects {
                    write!(f, " {}", e)?;
                }
                write!(f, ")")
            }
        }
    }
}

#[derive(Debug, Clone)]
pub struct VarInfo {
    pub ty: TypeId,
    pub span: Span,
}

#[derive(Debug, Clone)]
pub struct StructInfo {
    pub name: String,
    pub tyvars: Vec<String>,
    pub variants: Vec<StructVariant>,
}

#[derive(Debug, Clone)]
pub struct StructVariant {
    pub name: String,
    pub fields: Vec<(String, TypeId)>,
}

#[derive(Debug, Clone)]
pub struct FnInfo {
    pub name: String,
    pub ty: TypeId,
    pub foreign_symbol: Option<String>,
    pub is_builtin: bool,
    pub effects: Vec<axiom_ast::ast::Effect>,
}

/// A `union` declaration. Structurally identical to [`StructInfo`] today
/// (a union is just a struct whose fields overlap at codegen time rather
/// than being laid out sequentially) - kept as its own type rather than
/// reusing `StructInfo` so `TypeChecker.unions` can't accidentally be
/// confused with `TypeChecker.structs` by callers that care about the
/// distinction (e.g. `axiom symbols`'s `SymbolKind::Union` vs
/// `SymbolKind::Struct`), even though nothing here currently checks that
/// distinction any more deeply than that.
#[derive(Debug, Clone)]
pub struct UnionInfo {
    pub name: String,
    pub fields: Vec<(String, TypeId)>,
}

/// A `type` alias declaration: `name`'s type parameters and the type it
/// stands for.
#[derive(Debug, Clone)]
pub struct TypeAliasInfo {
    pub name: String,
    pub tyvars: Vec<String>,
    pub target: TypeId,
}

impl FnInfo {
    fn new(name: impl Into<String>, ty: TypeId) -> Self {
        Self {
            name: name.into(),
            ty,
            foreign_symbol: None,
            is_builtin: false,
            effects: Vec::new(),
        }
    }

    fn builtin(name: impl Into<String>, ty: TypeId) -> Self {
        Self {
            name: name.into(),
            ty,
            foreign_symbol: None,
            is_builtin: true,
            effects: Vec::new(),
        }
    }
}

#[derive(Debug, Clone)]
pub struct TraitInfo {
    pub name: String,
    pub methods: Vec<(String, TypeId)>,
    pub effects: Vec<axiom_ast::ast::Effect>,
}

pub struct TypeChecker {
    pub scope: Vec<(String, VarInfo)>,
    pub structs: Vec<StructInfo>,
    pub unions: Vec<UnionInfo>,
    pub aliases: Vec<TypeAliasInfo>,
    pub functions: Vec<FnInfo>,
    pub traits: Vec<TraitInfo>,
    pub errors: Vec<SemError>,
    pub type_counter: usize,
}

impl Default for TypeChecker {
    fn default() -> Self {
        Self::new()
    }
}

impl TypeChecker {
    pub fn new() -> Self {
        let mut tc = Self {
            scope: Vec::new(),
            structs: Vec::new(),
            unions: Vec::new(),
            aliases: Vec::new(),
            functions: Vec::new(),
            traits: Vec::new(),
            errors: Vec::new(),
            type_counter: 0,
        };

        let int_ty = TypeId::TCon("Int".to_string(), vec![]);
        let bool_ty = TypeId::TCon("Bool".to_string(), vec![]);
        let int_int = TypeId::TArr(Box::new(int_ty.clone()), Box::new(int_ty.clone()));
        let int_int_int = TypeId::TArr(Box::new(int_ty.clone()), Box::new(int_int.clone()));

        for op in &["+", "-", "*", "/", "%"] {
            tc.functions.push(FnInfo::builtin(*op, int_int_int.clone()));
        }

        for op in &["==", "!=", "<", ">", "<=", ">="] {
            tc.functions.push(FnInfo::builtin(
                *op,
                TypeId::TArr(
                    Box::new(int_ty.clone()),
                    Box::new(TypeId::TArr(
                        Box::new(int_ty.clone()),
                        Box::new(bool_ty.clone()),
                    )),
                ),
            ));
        }

        for op in &["&&", "||"] {
            tc.functions.push(FnInfo::builtin(
                *op,
                TypeId::TArr(
                    Box::new(bool_ty.clone()),
                    Box::new(TypeId::TArr(
                        Box::new(bool_ty.clone()),
                        Box::new(bool_ty.clone()),
                    )),
                ),
            ));
        }

        tc
    }

    pub fn check(&mut self, module: &Module) -> Result<(), Vec<SemError>> {
        self.check_duplicate_definitions(&module.decls);
        self.collect_declarations(module);
        self.check_decls(&module.decls);

        if self.errors.is_empty() {
            Ok(())
        } else {
            Err(std::mem::take(&mut self.errors))
        }
    }

    /// Detect a name defined more than once within the same namespace at
    /// module scope. Previously `AX3006`/`SemError::DuplicateDefinition`
    /// was declared but never actually constructed anywhere - two
    /// top-level `(define (f ...) ...)`s with the same name, or two
    /// `data`/`struct`/`union`/`type` declarations with the same name,
    /// silently compiled with the *second* one clobbering the first's
    /// entry (see `collect_declarations`'s `DFn`/`DForeign`/`DData` arms),
    /// with no diagnostic at all.
    ///
    /// Functions and types are checked as two separate namespaces (a
    /// function and a type may share a name), and a `(:: name Type)`
    /// signature is deliberately *not* treated as a definition here - a
    /// signature followed by exactly one matching `define`/`fn`/`foreign`
    /// is the normal, expected pattern, not a duplicate.
    fn check_duplicate_definitions(&mut self, decls: &[Decl]) {
        let mut values: std::collections::HashMap<String, Span> = std::collections::HashMap::new();
        let mut types: std::collections::HashMap<String, Span> = std::collections::HashMap::new();

        for decl in decls {
            let (namespace, name): (&mut std::collections::HashMap<String, Span>, &Ident) =
                match decl {
                    Decl::DFn { name, .. } => (&mut values, name),
                    Decl::DForeign { name, .. } => (&mut values, name),
                    Decl::DStruct { name, .. } => (&mut types, name),
                    Decl::DUnion { name, .. } => (&mut types, name),
                    Decl::DType { name, .. } => (&mut types, name),
                    _ => continue,
                };

            if let Some(first_span) = namespace.get(&name.name) {
                self.errors.push(SemError::DuplicateDefinition {
                    name: name.name.clone(),
                    span: name.span,
                    first_span: *first_span,
                });
            } else {
                namespace.insert(name.name.clone(), name.span);
            }
        }
    }

    fn collect_declarations(&mut self, module: &Module) {
        for decl in &module.decls {
            match decl {
                Decl::DStruct {
                    name,
                    tyvars,
                    variants,
                    ..
                } => {
                    let struct_variants: Vec<StructVariant> = variants
                        .iter()
                        .map(|v| {
                            let variant_fields: Vec<(String, TypeId)> = v
                                .fields
                                .iter()
                                .map(|f| (f.name.name.clone(), self.type_to_id(&f.ty)))
                                .collect();
                            StructVariant {
                                name: v.name.name.clone(),
                                fields: variant_fields,
                            }
                        })
                        .collect();
                    self.structs.push(StructInfo {
                        name: name.name.clone(),
                        tyvars: tyvars.clone(),
                        variants: struct_variants,
                    });
                }
                Decl::DSig { name, ty, .. } => {
                    self.functions
                        .push(FnInfo::new(name.name.clone(), self.type_to_id(ty)));
                }
                Decl::DTrait {
                    name,
                    methods,
                    effects,
                    ..
                } => {
                    let method_tys: Vec<(String, TypeId)> = methods
                        .iter()
                        .map(|m| (m.name.name.clone(), self.type_to_id(&m.ty)))
                        .collect();
                    self.traits.push(TraitInfo {
                        name: name.name.clone(),
                        methods: method_tys,
                        effects: effects.clone(),
                    });
                }
                Decl::DFn { name, .. } => {
                    if !self.functions.iter().any(|f| f.name == name.name) {
                        self.functions.push(FnInfo::new(
                            name.name.clone(),
                            TypeId::TVar(format!("_fn_{}", self.type_counter)),
                        ));
                        self.type_counter += 1;
                    }
                }
                Decl::DForeign {
                    name, ty, source, ..
                } => {
                    let mut info = FnInfo::new(name.name.clone(), self.type_to_id(ty));
                    info.foreign_symbol = Some(source.clone());
                    self.functions.push(info);
                }
                Decl::DUnion { name, fields, .. } => {
                    let union_fields: Vec<(String, TypeId)> = fields
                        .iter()
                        .map(|f| (f.name.name.clone(), self.type_to_id(&f.ty)))
                        .collect();
                    self.unions.push(UnionInfo {
                        name: name.name.clone(),
                        fields: union_fields,
                    });
                }
                Decl::DType {
                    name,
                    tyvars,
                    alias,
                    ..
                } => {
                    self.aliases.push(TypeAliasInfo {
                        name: name.name.clone(),
                        tyvars: tyvars.clone(),
                        target: self.type_to_id(alias),
                    });
                }
                _ => {}
            }
        }
    }

    fn check_decls(&mut self, decls: &[Decl]) {
        for decl in decls {
            match decl {
                Decl::DSig { name, ty, .. } => {
                    let ty_id = self.type_to_id(ty);
                    self.scope.push((
                        name.name.clone(),
                        VarInfo {
                            ty: ty_id,
                            span: name.span,
                        },
                    ));
                }
                Decl::DFn {
                    name,
                    params,
                    body,
                    axtags,
                    ..
                } => {
                    let sig_ty = self
                        .functions
                        .iter()
                        .find(|f| f.name == name.name)
                        .map(|f| f.ty.clone());

                    self.push_scope();
                    let param_types: Vec<TypeId> = if let Some(TypeId::TArr(_, _)) = &sig_ty {
                        let mut types = Vec::new();
                        let mut current = sig_ty.as_ref().unwrap();
                        for _ in 0..params.len() {
                            if let TypeId::TArr(param_ty, rest) = current {
                                types.push(param_ty.as_ref().clone());
                                current = rest.as_ref();
                            } else {
                                break;
                            }
                        }
                        types
                    } else {
                        vec![TypeId::TCon("Int".to_string(), vec![]); params.len()]
                    };

                    let mut actual_param_types: Vec<TypeId> = Vec::new();
                    for (i, pat) in params.iter().enumerate() {
                        let ty = param_types
                            .get(i)
                            .cloned()
                            .unwrap_or(TypeId::TVar(format!("_t{}", self.type_counter)));
                        self.type_counter += 1;
                        actual_param_types.push(ty.clone());
                        self.check_pattern_with_type(pat, &ty);
                    }
                    let body_ty = self.check_expr(body);
                    self.pop_scope();

                    // Build the actual function type from parameters and body
                    let mut fn_ty = body_ty;
                    for param_ty in actual_param_types.into_iter().rev() {
                        fn_ty = TypeId::TArr(Box::new(param_ty), Box::new(fn_ty));
                    }

                    // Update the function's type in self.functions
                    if let Some(fn_info) = self.functions.iter_mut().find(|f| f.name == name.name) {
                        fn_info.ty = fn_ty;
                    }

                    for tag in axtags {
                        match tag.key.as_str() {
                            "effect" => {
                                let declared: Vec<axiom_ast::ast::Effect> =
                                    match tag.value.as_deref() {
                                        Some("io") => vec![axiom_ast::ast::Effect::IO],
                                        Some("pure") => vec![axiom_ast::ast::Effect::Pure],
                                        Some("mut") => vec![axiom_ast::ast::Effect::Mut],
                                        Some("div") => vec![axiom_ast::ast::Effect::Div],
                                        Some("alloc") => vec![axiom_ast::ast::Effect::Alloc],
                                        Some(other) => vec![axiom_ast::ast::Effect::Custom(
                                            Ident::new(other, Span::dummy()),
                                        )],
                                        None => vec![],
                                    };
                                let actual = collect_effects_all(self, body);
                                let mut missing = Vec::new();
                                for e in &declared {
                                    if !actual.contains(e) {
                                        missing.push(format!("{}", e));
                                    }
                                }
                                if !missing.is_empty() {
                                    self.errors.push(SemError::AxtagMismatch {
                                        name: name.name.clone(),
                                        message: format!(
                                            "`effect({})` claim unsupported: missing {}",
                                            tag.value.as_deref().unwrap_or(""),
                                            missing.join(", ")
                                        ),
                                        span: name.span,
                                    });
                                }
                            }
                            "pure" => {
                                let actual = collect_effects_all(self, body);
                                if !actual.is_empty() {
                                    self.errors.push(SemError::AxtagMismatch {
                                        name: name.name.clone(),
                                        message: format!(
                                            "`pure` claim contradicted: body performs {}",
                                            actual
                                                .iter()
                                                .map(|e| format!("{}", e))
                                                .collect::<Vec<_>>()
                                                .join(", ")
                                        ),
                                        span: name.span,
                                    });
                                }
                            }
                            _ => {}
                        }
                    }
                }
                Decl::DForeign { name, ty, .. } => {
                    let ty_id = self.type_to_id(ty);
                    self.scope.push((
                        name.name.clone(),
                        VarInfo {
                            ty: ty_id,
                            span: name.span,
                        },
                    ));
                }
                Decl::DImpl { methods, .. } => {
                    for (_, body) in methods {
                        self.check_expr(body);
                    }
                }
                _ => {}
            }
        }
    }

    /// Check if `expr` is a struct/variant construction: a variable
    /// reference to a known struct name or variant name, possibly
    /// applied to arguments via nested `EApp`. Returns
    /// `(struct_name, args)` if so, or `None` otherwise.
    fn find_struct_con(&self, expr: &Expr) -> Option<(Ident, Vec<Expr>)> {
        let mut args = Vec::new();
        let mut current = expr;
        loop {
            match current {
                Expr::EApp(func, arg) => {
                    args.push(arg.as_ref().clone());
                    current = func;
                }
                Expr::EVar(ident) => {
                    if self.structs.iter().any(|s| s.name == ident.name)
                        || self
                            .structs
                            .iter()
                            .any(|s| s.variants.iter().any(|sv| sv.name == ident.name))
                    {
                        args.reverse();
                        return Some((ident.clone(), args));
                    }
                    return None;
                }
                _ => return None,
            }
        }
    }

    /// Check if `expr` is a union construction: a variable
    /// reference to a known union name with exactly one argument,
    /// where the union has exactly one field. Returns `(union_name,
    /// arg)` if so, or `None` otherwise.
    fn find_union_con(&self, expr: &Expr) -> Option<(Ident, Expr)> {
        let mut arg = None;
        let mut current = expr;
        loop {
            match current {
                Expr::EApp(func, arg_expr) => {
                    if arg.is_some() {
                        return None;
                    }
                    arg = Some(arg_expr.clone());
                    current = func;
                }
                Expr::EVar(ident) => {
                    if self.unions.iter().any(|u| u.name == ident.name) {
                        let arg = *arg?;
                        return Some((ident.clone(), arg));
                    }
                    return None;
                }
                _ => return None,
            }
        }
    }

    fn check_expr(&mut self, expr: &Expr) -> TypeId {
        match expr {
            Expr::EVar(ident) => self.check_var(ident),
            Expr::ELit(lit, _) => self.check_literal(lit),
            Expr::EApp(func, arg) => {
                // Check for struct/variant construction first:
                // `(Point 1 2)` where `Point` is a known struct or
                // variant name.
                if let Some((struct_ident, con_args)) = self.find_struct_con(expr) {
                    let found = self.structs.iter().find_map(|si| {
                        if si.name == struct_ident.name {
                            // Single-variant struct: use the struct's
                            // first (and typically only) variant.
                            si.variants.first().map(|sv| (si, sv))
                        } else {
                            // Multi-variant struct: find the matching variant.
                            si.variants
                                .iter()
                                .find(|sv| sv.name == struct_ident.name)
                                .map(|sv| (si, sv))
                        }
                    });
                    if let Some((si, sv)) = found {
                        let si_name = si.name.clone();
                        let sv_name = sv.name.clone();
                        let sv_fields: Vec<_> =
                            sv.fields.iter().map(|(_, fty)| fty.clone()).collect();
                        let type_args: Vec<Type> =
                            si.tyvars.iter().map(|v| Type::TVar(v.clone())).collect();
                        if con_args.len() != sv_fields.len() {
                            self.errors.push(SemError::Message {
                                message: format!(
                                    "struct `{}` variant `{}` expects {} field(s), found {}",
                                    si_name,
                                    sv_name,
                                    sv_fields.len(),
                                    con_args.len(),
                                ),
                                span: expr.span(),
                            });
                            return TypeId::TError;
                        }
                        for (i, con_arg) in con_args.iter().enumerate() {
                            let arg_ty = self.check_expr(con_arg);
                            let expected_ty = sv_fields[i].clone();
                            if !arg_ty.compatible_with(&expected_ty) {
                                self.errors.push(SemError::TypeMismatch {
                                    expected: format!("{}", expected_ty),
                                    found: format!("{}", arg_ty),
                                    span: con_arg.span(),
                                });
                            }
                        }
                        return self.type_to_id(&Type::TCon(
                            Ident::new(&si_name, Span::dummy()),
                            type_args,
                        ));
                    }
                }

                // Check for union construction: `(Value 42)` where
                // `Value` is a known union name with exactly one field.
                if let Some((union_ident, con_arg)) = self.find_union_con(expr) {
                    let ui = self
                        .unions
                        .iter()
                        .find(|u| u.name == union_ident.name)
                        .cloned();
                    if let Some(ui) = ui {
                        if ui.fields.len() != 1 {
                            self.errors.push(SemError::Message {
                                message: format!(
                                    "union `{}` has {} fields, use `(Union {} field value)` to specify which field",
                                    union_ident.name,
                                    ui.fields.len(),
                                    union_ident.name,
                                ),
                                span: expr.span(),
                            });
                            return TypeId::TError;
                        }
                        let arg_ty = self.check_expr(&con_arg);
                        let expected_ty = ui.fields[0].1.clone();
                        if !arg_ty.compatible_with(&expected_ty) {
                            self.errors.push(SemError::TypeMismatch {
                                expected: format!("{}", expected_ty),
                                found: format!("{}", arg_ty),
                                span: con_arg.span(),
                            });
                        }
                        return self.type_to_id(&Type::TCon(union_ident, vec![]));
                    }
                }

                let func_ty = self.check_expr(func);
                let arg_ty = self.check_expr(arg);
                match func_ty {
                    TypeId::TArr(param_ty, ret_ty) => {
                        // Previously the argument's type was computed
                        // (`check_expr` has to run for its own side
                        // effects - binding checks, nested errors - either
                        // way) and then simply discarded: calling *any*
                        // function with an argument of the wrong type
                        // (e.g. passing a `String` where an `Int`-taking
                        // function expects one) produced no diagnostic at
                        // all. `compatible_with` (rather than strict
                        // `!=`) is required here, not just a nicety: a
                        // recursive call on a generic constructor's field
                        // (e.g. `(sumTree l)` where `l : Tree a` but
                        // `sumTree` expects `Tree Int`) is completely
                        // ordinary, already-working code that plain
                        // structural equality would wrongly flag as a
                        // mismatch.
                        if !arg_ty.compatible_with(&param_ty) {
                            self.errors.push(SemError::TypeMismatch {
                                expected: format!("{}", param_ty),
                                found: format!("{}", arg_ty),
                                span: arg.span(),
                            });
                        }
                        *ret_ty
                    }
                    // Don't report "expected function type" when `func_ty`
                    // is already a poison type from an earlier error (e.g.
                    // calling an undefined variable): that would just be a
                    // second, redundant error about the same root cause.
                    TypeId::TError => TypeId::TError,
                    _ => {
                        self.errors.push(SemError::TypeMismatch {
                            expected: "function type".to_string(),
                            found: format!("{}", func_ty),
                            span: expr.span(),
                        });
                        TypeId::TError
                    }
                }
            }
            Expr::ELam(patterns, body) => {
                self.push_scope();
                let mut param_tys: Vec<TypeId> = Vec::new();
                for pat in patterns {
                    let fresh = TypeId::TVar(format!("_t{}", self.type_counter));
                    self.type_counter += 1;
                    self.check_pattern_with_type(pat, &fresh);
                    param_tys.push(fresh);
                }
                let body_ty = self.check_expr(body);
                self.pop_scope();
                let mut ty = body_ty;
                for param_ty in param_tys.into_iter().rev() {
                    ty = TypeId::TArr(Box::new(param_ty), Box::new(ty));
                }
                ty
            }
            Expr::ELet(bindings, body) => {
                self.push_scope();
                for (pat, init) in bindings {
                    let init_ty = self.check_expr(init);
                    self.check_pattern_with_type(pat, &init_ty);
                }
                let body_ty = self.check_expr(body);
                self.pop_scope();
                body_ty
            }
            Expr::EIf(cond, then_expr, else_expr) => {
                let cond_ty = self.check_expr(cond);
                if !cond_ty.is_error()
                    && !cond_ty.compatible_with(&TypeId::TCon("Bool".to_string(), vec![]))
                {
                    self.errors.push(SemError::TypeMismatch {
                        expected: "Bool".to_string(),
                        found: format!("{}", cond_ty),
                        span: cond.span(),
                    });
                }
                let then_ty = self.check_expr(then_expr);
                let else_ty = self.check_expr(else_expr);
                if !then_ty.is_error() && !else_ty.is_error() && !then_ty.compatible_with(&else_ty)
                {
                    self.errors.push(SemError::TypeMismatch {
                        expected: format!("{}", then_ty),
                        found: format!("{}", else_ty),
                        span: else_expr.span(),
                    });
                }
                if then_ty.is_error() {
                    else_ty
                } else {
                    then_ty
                }
            }
            Expr::EMatch(target, arms) => {
                let target_ty = self.check_expr(target);
                let mut arm_ty = TypeId::TVar(format!("_t{}", self.type_counter));
                let mut covered: std::collections::HashSet<String> =
                    std::collections::HashSet::new();
                let mut has_catchall = false;
                for (pat, body) in arms {
                    self.push_scope();
                    // Type-directed: validates that `PCon` names are real
                    // constructors (with the right arity) instead of the
                    // old `check_pattern`, which just walked the pattern
                    // shape and bound every `PVar` to an unconstrained
                    // fresh type variable with no relationship to the
                    // constructor's actual field types.
                    self.check_pattern_with_type(pat, &target_ty);
                    match pat {
                        Pattern::PCon(ident, _) => {
                            covered.insert(ident.name.clone());
                        }
                        Pattern::PWildcard | Pattern::PVar(_) => has_catchall = true,
                        _ => {}
                    }
                    arm_ty = self.check_expr(body);
                    self.pop_scope();
                }

                // Exhaustiveness: only checkable when the scrutinee's type
                // is concretely a known `data` type (poisoned/`TVar`
                // scrutinees can't be judged either way, so they're
                // silently skipped rather than guessed at).
                if !has_catchall {
                    if let TypeId::TCon(name, _) = &target_ty {
                        if let Some(si) = self.structs.iter().find(|s| &s.name == name) {
                            let mut covered = std::collections::HashSet::new();
                            for (pat, _) in arms {
                                if let Pattern::PCon(ident, _) = pat {
                                    covered.insert(ident.name.clone());
                                }
                            }
                            let missing: Vec<String> = si
                                .variants
                                .iter()
                                .map(|v| v.name.clone())
                                .filter(|n| !covered.contains(n))
                                .collect();
                            if !missing.is_empty() {
                                self.errors.push(SemError::NonExhaustive {
                                    span: target.span(),
                                    missing,
                                });
                            }
                        }
                    }
                }

                arm_ty
            }
            Expr::ECond(branches, else_branch) => {
                let bool_ty = TypeId::TCon("Bool".to_string(), vec![]);
                let mut result_ty = TypeId::TVar(format!("_t{}", self.type_counter));
                for (cond, body) in branches {
                    let cond_ty = self.check_expr(cond);
                    if !cond_ty.is_error() && !cond_ty.compatible_with(&bool_ty) {
                        self.errors.push(SemError::TypeMismatch {
                            expected: "Bool".to_string(),
                            found: format!("{}", cond_ty),
                            span: cond.span(),
                        });
                    }
                    result_ty = self.check_expr(body);
                }
                if let Some(else_body) = else_branch {
                    let else_ty = self.check_expr(else_body);
                    if !result_ty.is_error()
                        && !else_ty.is_error()
                        && !else_ty.compatible_with(&result_ty)
                    {
                        self.errors.push(SemError::TypeMismatch {
                            expected: format!("{}", result_ty),
                            found: format!("{}", else_ty),
                            span: else_body.span(),
                        });
                    }
                }
                result_ty
            }
            Expr::EBegin(exprs) => {
                let mut last_ty = TypeId::TTuple(vec![]);
                for e in exprs {
                    last_ty = self.check_expr(e);
                }
                last_ty
            }
            Expr::ETuple(elements) => {
                let types: Vec<TypeId> = elements.iter().map(|e| self.check_expr(e)).collect();
                TypeId::TTuple(types)
            }
            Expr::EList(elements) => {
                let mut elem_ty = TypeId::TVar(format!("_t{}", self.type_counter));
                for elem in elements {
                    let t = self.check_expr(elem);
                    elem_ty = t;
                }
                TypeId::TList(Box::new(elem_ty))
            }
            Expr::EInfix(left, _op, right) => {
                let _left_ty = self.check_expr(left);
                let _right_ty = self.check_expr(right);
                TypeId::TVar(format!("_t{}", self.type_counter))
            }
            Expr::ETypeSig(inner, ty) => {
                let _inner_ty = self.check_expr(inner);
                self.type_to_id(ty)
            }
            Expr::ECast(inner, ty) => {
                self.check_expr(inner);
                self.type_to_id(ty)
            }
            Expr::EAlloc(ty, count, _) => {
                if let Some(count_expr) = count {
                    self.check_expr(count_expr);
                }
                TypeId::TPtr(Box::new(self.type_to_id(ty)), true)
            }
            Expr::ESizeof(_, _) => TypeId::TCon("Int".to_string(), vec![]),
            Expr::EAlignof(_, _) => TypeId::TCon("Int".to_string(), vec![]),
            Expr::EGrouped(inner) => self.check_expr(inner),
            Expr::EHandle(body, handled, handler) => {
                let body_ty = self.check_expr(body);
                self.check_expr(handler);
                let actual = collect_effects(self, body);
                for e in &actual {
                    if !handled.contains(e) {
                        self.errors.push(SemError::EffectMismatch {
                            message: format!("unhandled effect `{}`", e),
                            span: body.span(),
                        });
                    }
                }
                TypeId::strip_effects(&body_ty, handled)
            }
            Expr::ERegion(_, body) => self.check_expr(body),
            Expr::EConsume(e) => self.check_expr(e),
            Expr::EField(base, field_ident) => {
                let base_ty = self.check_expr(base);
                if let TypeId::TCon(struct_name, _) = &base_ty {
                    for si in &self.structs {
                        if si.name == *struct_name {
                            for sv in &si.variants {
                                for (fname, fty) in &sv.fields {
                                    if fname == &field_ident.name {
                                        return fty.clone();
                                    }
                                }
                            }
                        }
                    }
                    for ui in &self.unions {
                        if ui.name == *struct_name {
                            for (fname, fty) in &ui.fields {
                                if fname == &field_ident.name {
                                    return fty.clone();
                                }
                            }
                        }
                    }
                    self.errors.push(SemError::FieldNotFound {
                        field: field_ident.name.clone(),
                        ty: struct_name.clone(),
                        span: field_ident.span,
                    });
                } else {
                    self.errors.push(SemError::TypeMismatch {
                        expected: "struct".to_string(),
                        found: format!("{}", base_ty),
                        span: base.span(),
                    });
                }
                TypeId::TCon("I64".to_string(), vec![])
            }
            Expr::EStructCon(name, args) => {
                // Find the struct that contains a variant with this name.
                let found = self.structs.iter().find_map(|si| {
                    let variant = si.variants.iter().find(|sv| sv.name == name.name)?;
                    Some((si, variant))
                });
                match found {
                    Some((si, sv)) => {
                        let si_name = si.name.clone();
                        let sv_name = sv.name.clone();
                        let sv_fields: Vec<_> =
                            sv.fields.iter().map(|(_, fty)| fty.clone()).collect();
                        let type_args: Vec<Type> =
                            si.tyvars.iter().map(|v| Type::TVar(v.clone())).collect();
                        if args.len() != sv_fields.len() {
                            self.errors.push(SemError::Message {
                                message: format!(
                                    "struct `{}` variant `{}` expects {} field(s), found {}",
                                    si_name,
                                    sv_name,
                                    sv_fields.len(),
                                    args.len(),
                                ),
                                span: expr.span(),
                            });
                            return TypeId::TError;
                        }
                        for (i, arg) in args.iter().enumerate() {
                            let arg_ty = self.check_expr(arg);
                            let expected_ty = sv_fields[i].clone();
                            if !arg_ty.compatible_with(&expected_ty) {
                                self.errors.push(SemError::TypeMismatch {
                                    expected: format!("{}", expected_ty),
                                    found: format!("{}", arg_ty),
                                    span: arg.span(),
                                });
                            }
                        }
                        self.type_to_id(&Type::TCon(Ident::new(&si_name, Span::dummy()), type_args))
                    }
                    None => {
                        self.errors.push(SemError::UndefinedType {
                            name: name.name.clone(),
                            span: name.span,
                            suggestion: None,
                        });
                        TypeId::TError
                    }
                }
            }
            Expr::EUnionCon(union_name, field_name, value) => {
                let ui = self
                    .unions
                    .iter()
                    .find(|u| u.name == union_name.name)
                    .cloned();
                match ui {
                    Some(ui) => {
                        let field_info = ui
                            .fields
                            .iter()
                            .find(|(fname, _)| fname == &field_name.name);
                        match field_info {
                            Some((_, fty)) => {
                                let value_ty = self.check_expr(value);
                                if !value_ty.compatible_with(fty) {
                                    self.errors.push(SemError::TypeMismatch {
                                        expected: format!("{}", fty),
                                        found: format!("{}", value_ty),
                                        span: value.span(),
                                    });
                                }
                            }
                            None => {
                                self.errors.push(SemError::FieldNotFound {
                                    field: field_name.name.clone(),
                                    ty: union_name.name.clone(),
                                    span: field_name.span,
                                });
                            }
                        }
                        self.type_to_id(&Type::TCon(union_name.clone(), vec![]))
                    }
                    None => {
                        self.errors.push(SemError::UndefinedType {
                            name: union_name.name.clone(),
                            span: union_name.span,
                            suggestion: None,
                        });
                        TypeId::TError
                    }
                }
            }
            Expr::ESetField(base, field_ident, value) => {
                let base_ty = self.check_expr(base);
                if let TypeId::TCon(struct_name, _) = &base_ty {
                    let field_info = self
                        .structs
                        .iter()
                        .find(|s| s.name == *struct_name)
                        .cloned()
                        .and_then(|si| {
                            si.variants.iter().find_map(|sv| {
                                sv.fields
                                    .iter()
                                    .find(|(fname, _)| fname == &field_ident.name)
                                    .map(|(fname, fty)| (fname.clone(), fty.clone()))
                            })
                        })
                        .or_else(|| {
                            self.unions
                                .iter()
                                .find(|u| u.name == *struct_name)
                                .cloned()
                                .and_then(|ui| {
                                    ui.fields
                                        .iter()
                                        .find(|(fname, _)| fname == &field_ident.name)
                                        .map(|(fname, fty)| (fname.clone(), fty.clone()))
                                })
                        });
                    match field_info {
                        Some((_, fty)) => {
                            let value_ty = self.check_expr(value);
                            if !value_ty.compatible_with(&fty) {
                                self.errors.push(SemError::TypeMismatch {
                                    expected: format!("{}", fty),
                                    found: format!("{}", value_ty),
                                    span: value.span(),
                                });
                            }
                        }
                        None => {
                            self.errors.push(SemError::FieldNotFound {
                                field: field_ident.name.clone(),
                                ty: struct_name.clone(),
                                span: field_ident.span,
                            });
                        }
                    }
                } else {
                    self.errors.push(SemError::TypeMismatch {
                        expected: "struct".to_string(),
                        found: format!("{}", base_ty),
                        span: base.span(),
                    });
                }
                TypeId::TCon("I64".to_string(), vec![])
            }
            Expr::EError(_, _) => TypeId::TVar(format!("_t{}", self.type_counter)),
        }
    }

    fn check_var(&mut self, ident: &Ident) -> TypeId {
        for (name, info) in self.scope.iter().rev() {
            if name == &ident.name {
                return info.ty.clone();
            }
        }

        for fn_info in &self.functions {
            if fn_info.name == ident.name {
                return fn_info.ty.clone();
            }
        }

        for si in &self.structs {
            for sv in &si.variants {
                if sv.name == ident.name {
                    let type_args: Vec<TypeId> =
                        si.tyvars.iter().map(|v| TypeId::TVar(v.clone())).collect();
                    let con_ty = TypeId::TCon(si.name.clone(), type_args);
                    let mut ty = con_ty;
                    for field_ty in sv.fields.iter().rev() {
                        ty = TypeId::TArr(Box::new(field_ty.1.clone()), Box::new(ty));
                    }
                    return ty;
                }
            }
        }

        let suggestion = suggest_closest(
            &ident.name,
            self.scope
                .iter()
                .map(|(n, _)| n.as_str())
                .chain(self.functions.iter().map(|f| f.name.as_str()))
                .chain(
                    self.structs
                        .iter()
                        .flat_map(|si| si.variants.iter().map(|sv| sv.name.as_str())),
                ),
        );

        self.errors.push(SemError::UndefinedVariable {
            name: ident.name.clone(),
            span: ident.span,
            suggestion,
        });

        // Poison: every downstream use of this value is suppressed from
        // producing further cascading errors (see `TypeId::TError`).
        TypeId::TError
    }

    fn check_literal(&self, lit: &Literal) -> TypeId {
        match lit {
            Literal::LInt(_) => TypeId::TCon("Int".to_string(), vec![]),
            Literal::LFloat(_) => TypeId::TCon("Float".to_string(), vec![]),
            Literal::LBool(_) => TypeId::TCon("Bool".to_string(), vec![]),
            Literal::LChar(_) => TypeId::TCon("Char".to_string(), vec![]),
            Literal::LStr(_) => TypeId::TCon("String".to_string(), vec![]),
        }
    }

    /// Find the struct and variant (if any) named `name`.
    fn find_constructor(&self, name: &str) -> Option<(&StructInfo, &StructVariant)> {
        for si in &self.structs {
            for sv in &si.variants {
                if sv.name == name {
                    return Some((si, sv));
                }
            }
        }
        None
    }

    /// Search all known struct types for a field with the
    /// given name, returning the first match's
    /// `(struct_name, variant_name, field_index, field_type)`.
    /// Used by the IR generator for field access when the base
    /// expression's type can't be re-queried (e.g. inside
    /// `gen_expr_to_func_with_allocas`).
    pub fn find_struct_field_by_name(
        &self,
        field_name: &str,
    ) -> Option<(String, String, usize, TypeId)> {
        for si in &self.structs {
            for sv in &si.variants {
                for (idx, (fname, fty)) in sv.fields.iter().enumerate() {
                    if fname == field_name {
                        return Some((si.name.clone(), sv.name.clone(), idx, fty.clone()));
                    }
                }
            }
        }
        None
    }

    /// Search all known union types for a field with the
    /// given name, returning `(union_name, field_type)` if found.
    pub fn find_union_field_by_name(&self, field_name: &str) -> Option<(String, TypeId)> {
        for ui in &self.unions {
            for (fname, fty) in &ui.fields {
                if fname == field_name {
                    return Some((ui.name.clone(), fty.clone()));
                }
            }
        }
        None
    }

    /// Bind every name introduced by `pat` into the current scope with a
    /// fresh, unconstrained type - used where there's no expected type to
    /// check against (lambda/`let` parameters). Delegates to
    /// [`check_pattern_with_type`](Self::check_pattern_with_type) so a
    /// `PCon` pattern here still gets the same constructor
    /// identity/arity validation as a `match` arm does, rather than a
    /// second, duplicated (and previously non-validating) tree walk.
    fn check_pattern(&mut self, pat: &Pattern) {
        let fresh = TypeId::TVar(format!("_t{}", self.type_counter));
        self.type_counter += 1;
        self.check_pattern_with_type(pat, &fresh);
    }

    /// Bind every name introduced by `pat`, checking it against the
    /// expected type `ty` where that's meaningful:
    ///
    /// * `PCon(name, args)` - `name` must be a real data constructor
    ///   ([`SemError::UndefinedConstructor`] if not, with a "did you
    ///   mean" suggestion), `args.len()` must equal the constructor's
    ///   declared arity ([`SemError::ConstructorArity`] if not), and each
    ///   `arg` is recursively checked against that field's *actual*
    ///   declared type rather than being left as an unconstrained
    ///   variable - so `(match v ((Red x) (+ x 1)))` gives `x` the real
    ///   field type instead of a fresh, meaningless `TVar`. If `ty` is
    ///   already known concretely and doesn't name the constructor's own
    ///   data type, that's also a [`SemError::TypeMismatch`] (matching a
    ///   constructor against a scrutinee already known to be some
    ///   other type).
    /// * `PTuple`/`PList` - binds element patterns against the expected
    ///   element type(s) when `ty` is a matching `TTuple`/`TList`, falling
    ///   back to a fresh variable per element otherwise (arity mismatch,
    ///   or `ty` not concretely known yet).
    /// * `PVar` - binds directly to `ty`.
    /// * `PWildcard`/`PLit` - introduce no bindings and need no further
    ///   checking (a literal pattern's own type is implicit in the
    ///   literal itself).
    fn check_pattern_with_type(&mut self, pat: &Pattern, ty: &TypeId) {
        match pat {
            Pattern::PVar(ident) => {
                self.scope.push((
                    ident.name.clone(),
                    VarInfo {
                        ty: ty.clone(),
                        span: ident.span,
                    },
                ));
            }
            Pattern::PCon(ident, args) => {
                let found = self
                    .find_constructor(&ident.name)
                    .map(|(si, sv)| (si.name.clone(), sv.name.clone(), sv.fields.clone()));
                match found {
                    Some((data_type_name, _variant_name, variant_fields)) => {
                        if let TypeId::TCon(scrutinee_name, _) = ty {
                            if scrutinee_name != &data_type_name {
                                self.errors.push(SemError::TypeMismatch {
                                    expected: scrutinee_name.clone(),
                                    found: data_type_name.clone(),
                                    span: ident.span,
                                });
                            }
                        }

                        let field_types = variant_fields
                            .iter()
                            .map(|(_, fty)| fty.clone())
                            .collect::<Vec<_>>();
                        if field_types.len() != args.len() {
                            self.errors.push(SemError::ConstructorArity {
                                name: ident.name.clone(),
                                expected: field_types.len(),
                                found: args.len(),
                                span: ident.span,
                            });
                        }

                        for (i, arg) in args.iter().enumerate() {
                            match field_types.get(i) {
                                Some(field_ty) => self.check_pattern_with_type(arg, field_ty),
                                None => self.check_pattern(arg),
                            }
                        }
                    }
                    None => {
                        let suggestion = suggest_closest(
                            &ident.name,
                            self.structs
                                .iter()
                                .flat_map(|si| si.variants.iter().map(|sv| sv.name.as_str())),
                        );
                        self.errors.push(SemError::UndefinedConstructor {
                            name: ident.name.clone(),
                            span: ident.span,
                            suggestion,
                        });
                        for arg in args {
                            self.check_pattern(arg);
                        }
                    }
                }
            }
            Pattern::PTuple(pats) => {
                if let TypeId::TTuple(elem_tys) = ty {
                    if elem_tys.len() == pats.len() {
                        for (pat, elem_ty) in pats.iter().zip(elem_tys.iter()) {
                            self.check_pattern_with_type(pat, elem_ty);
                        }
                        return;
                    }
                }
                for pat in pats {
                    self.check_pattern(pat);
                }
            }
            Pattern::PList(pats) => {
                if let TypeId::TList(elem_ty) = ty {
                    for pat in pats {
                        self.check_pattern_with_type(pat, elem_ty);
                    }
                    return;
                }
                for pat in pats {
                    self.check_pattern(pat);
                }
            }
            Pattern::PWildcard | Pattern::PLit(_) => {}
        }
    }

    fn type_to_id(&self, ty: &Type) -> TypeId {
        match ty {
            Type::TVar(name) => TypeId::TVar(name.clone()),
            Type::TCon(ident, args) => {
                let arg_ids: Vec<TypeId> = args.iter().map(|a| self.type_to_id(a)).collect();
                TypeId::TCon(ident.name.clone(), arg_ids)
            }
            Type::TArr(from, to) => TypeId::TArr(
                Box::new(self.type_to_id(from)),
                Box::new(self.type_to_id(to)),
            ),
            Type::TTuple(types) => {
                TypeId::TTuple(types.iter().map(|t| self.type_to_id(t)).collect())
            }
            Type::TList(inner) => TypeId::TList(Box::new(self.type_to_id(inner))),
            Type::TPtr(inner, mutable) => TypeId::TPtr(Box::new(self.type_to_id(inner)), *mutable),
            Type::TForall(vars, inner) => {
                TypeId::TForall(vars.clone(), Box::new(self.type_to_id(inner)))
            }
            Type::TEffect(inner, effects) => {
                TypeId::TEffect(Box::new(self.type_to_id(inner)), effects.clone())
            }
            Type::TRegion(inner, name) => {
                TypeId::TCon(name.name.clone(), vec![self.type_to_id(inner)])
            }
            Type::TLinear(inner) => {
                TypeId::TCon("Linear".to_string(), vec![self.type_to_id(inner)])
            }
        }
    }

    fn push_scope(&mut self) {
        self.scope.push((
            "__scope__".to_string(),
            VarInfo {
                ty: TypeId::TTuple(vec![]),
                span: Span::dummy(),
            },
        ));
    }

    fn pop_scope(&mut self) {
        while let Some((name, _)) = self.scope.pop() {
            if name == "__scope__" {
                break;
            }
        }
    }

    pub fn check_single_expr(&mut self, expr: &Expr) -> Result<TypeId, Vec<SemError>> {
        self.errors.clear();
        let ty = self.check_expr(expr);
        if self.errors.is_empty() {
            Ok(ty)
        } else {
            Err(std::mem::take(&mut self.errors))
        }
    }

    pub fn register_decl(&mut self, decl: &Decl) {
        match decl {
            Decl::DSig { name, ty, .. } => {
                let ty_id = self.type_to_id(ty);
                self.functions
                    .push(FnInfo::new(name.name.clone(), ty_id.clone()));
                self.scope.push((
                    name.name.clone(),
                    VarInfo {
                        ty: ty_id,
                        span: name.span,
                    },
                ));
            }
            Decl::DFn {
                name, params, body, ..
            } => {
                if !self.functions.iter().any(|f| f.name == name.name) {
                    self.functions.push(FnInfo::new(
                        name.name.clone(),
                        TypeId::TVar(format!("_fn_{}", self.type_counter)),
                    ));
                    self.type_counter += 1;
                }
                self.push_scope();
                for pat in params {
                    self.check_pattern(pat);
                }
                self.check_expr(body);
                self.pop_scope();
            }
            Decl::DStruct {
                name,
                tyvars,
                variants,
                ..
            } => {
                let struct_variants: Vec<StructVariant> = variants
                    .iter()
                    .map(|v| {
                        let variant_fields: Vec<(String, TypeId)> = v
                            .fields
                            .iter()
                            .map(|f| (f.name.name.clone(), self.type_to_id(&f.ty)))
                            .collect();
                        StructVariant {
                            name: v.name.name.clone(),
                            fields: variant_fields,
                        }
                    })
                    .collect();
                self.structs.push(StructInfo {
                    name: name.name.clone(),
                    tyvars: tyvars.clone(),
                    variants: struct_variants,
                });
            }
            Decl::DForeign {
                name, ty, source, ..
            } => {
                let mut info = FnInfo::new(name.name.clone(), self.type_to_id(ty));
                info.foreign_symbol = Some(source.clone());
                self.functions.push(info);
            }
            Decl::DUnion { name, fields, .. } => {
                let union_fields: Vec<(String, TypeId)> = fields
                    .iter()
                    .map(|f| (f.name.name.clone(), self.type_to_id(&f.ty)))
                    .collect();
                self.unions.push(UnionInfo {
                    name: name.name.clone(),
                    fields: union_fields,
                });
            }
            Decl::DType {
                name,
                tyvars,
                alias,
                ..
            } => {
                self.aliases.push(TypeAliasInfo {
                    name: name.name.clone(),
                    tyvars: tyvars.clone(),
                    target: self.type_to_id(alias),
                });
            }
            _ => {}
        }
    }

    pub fn lookup_type(&self, name: &str) -> Option<TypeId> {
        for (n, info) in self.scope.iter().rev() {
            if n == name {
                return Some(info.ty.clone());
            }
        }
        for fn_info in &self.functions {
            if fn_info.name == name {
                return Some(fn_info.ty.clone());
            }
        }
        None
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use axiom_lexer::Lexer;
    use axiom_parser::Parser;

    fn check(source: &str) -> Result<(), Vec<SemError>> {
        let mut lexer = Lexer::new(source, 0);
        let tokens = lexer.tokenize().expect("lex failed");
        let module = Parser::new(tokens).parse_module().expect("parse failed");
        TypeChecker::new().check(&module)
    }

    fn check_err(source: &str) -> Vec<SemError> {
        check(source).expect_err("expected type-checking to fail")
    }

    #[test]
    fn well_typed_arithmetic_program_checks_ok() {
        assert!(check("(:: main Int)\n(fn main (+ 1 (* 2 3)))").is_ok());
    }

    #[test]
    fn exhaustive_match_over_a_data_type_checks_ok() {
        assert!(check(
            "(struct Color (Red Int) (Green Int))\n\
             (:: main Int)\n\
             (fn main (match (Red 1) ((Green _) 1) ((Red x) x)))"
        )
        .is_ok());
    }

    #[test]
    fn non_exhaustive_match_over_a_data_type_is_an_error() {
        let errors = check_err(
            "(struct Color (Red Int) (Green Int))\n\
             (:: main Int)\n\
             (fn main (match (Red 1) ((Red x) x)))",
        );
        assert!(errors.iter().any(|e| matches!(e, SemError::NonExhaustive { missing, .. } if missing == &["Green".to_string()])));
    }

    #[test]
    fn wildcard_arm_makes_match_exhaustive() {
        assert!(check(
            "(struct Color (Red Int) (Green Int))\n\
             (:: main Int)\n\
             (fn main (match (Red 1) ((Green _) 0) (_ 1)))"
        )
        .is_ok());
    }

    #[test]
    fn constructor_pattern_with_wrong_arity_is_an_error() {
        let errors = check_err(
            "(struct Color (Red Int) (Green Int))\n\
             (:: main Int)\n\
             (fn main (match (Red 1) ((Green _) 0) ((Red x y) x)))",
        );
        assert!(errors.iter().any(|e| matches!(e, SemError::ConstructorArity { name, expected: 1, found: 2, .. } if name == "Red")));
    }

    #[test]
    fn undefined_constructor_in_pattern_is_an_error_with_a_suggestion() {
        let errors = check_err(
            "(struct Color (Red Int) (Green Int))\n\
             (:: main Int)\n\
             (fn main (match (Red 1) ((Redn) 0) ((Red x) x)))",
        );
        assert!(errors.iter().any(|e| matches!(
            e,
            SemError::UndefinedConstructor { name, suggestion: Some(s), .. }
                if name == "Redn" && s == "Red"
        )));
    }

    #[test]
    fn undefined_variable_is_an_error() {
        let errors = check_err("(:: main Int)\n(fn main (+ 1 notARealVariable))");
        assert!(errors.iter().any(
            |e| matches!(e, SemError::UndefinedVariable { name, .. } if name == "notARealVariable")
        ));
    }

    #[test]
    fn duplicate_top_level_definition_is_an_error() {
        let errors = check_err(
            "(:: helper (-> Int Int))\n(fn (helper x) x)\n\
             (:: helper (-> Int Int))\n(fn (helper x) (+ x 1))\n\
             (:: main Int)\n(fn main (helper 1))",
        );
        assert!(errors
            .iter()
            .any(|e| matches!(e, SemError::DuplicateDefinition { name, .. } if name == "helper")));
    }

    #[test]
    fn if_branches_of_different_types_is_an_error() {
        let errors = check_err(
            r#"(:: main Int)
(fn main (if true 1 "no"))"#,
        );
        assert!(errors
            .iter()
            .any(|e| matches!(e, SemError::TypeMismatch { .. })));
    }

    #[test]
    fn struct_and_union_and_type_alias_declarations_are_tracked() {
        let mut lexer = Lexer::new(
            "(struct Point (x : Int) (y : Int))\n\
             (union Value (asInt : I64) (asFloat : F64))\n\
             (type StringList () = [String])\n\
             (:: main Int)\n(fn main 0)",
            0,
        );
        let tokens = lexer.tokenize().unwrap();
        let module = Parser::new(tokens).parse_module().unwrap();
        let mut tc = TypeChecker::new();
        tc.check(&module)
            .expect("expected this program to check cleanly");
        assert_eq!(tc.structs.len(), 1);
        assert_eq!(tc.structs[0].variants.len(), 1);
        assert_eq!(tc.structs[0].variants[0].fields.len(), 2);
        assert_eq!(tc.unions.len(), 1);
        assert_eq!(tc.unions[0].fields.len(), 2);
        assert_eq!(tc.aliases.len(), 1);
        assert_eq!(tc.aliases[0].name, "StringList");
    }

    #[test]
    fn union_construction_checks_field_type() {
        let mut lexer = Lexer::new(
            "(union Value (asInt : Int) (asFloat : F64))\n\
             (:: main Int)\n(fn main (union Value asInt 42))",
            0,
        );
        let tokens = lexer.tokenize().unwrap();
        let module = Parser::new(tokens).parse_module().unwrap();
        let mut tc = TypeChecker::new();
        tc.check(&module)
            .expect("expected this program to check cleanly");
    }

    #[test]
    fn union_construction_rejects_wrong_field_type() {
        let mut lexer = Lexer::new(
            "(union Value (asInt : Int) (asFloat : F64))\n\
             (:: main Int)\n(fn main (union Value asInt \"hello\"))",
            0,
        );
        let tokens = lexer.tokenize().unwrap();
        let module = Parser::new(tokens).parse_module().unwrap();
        let mut tc = TypeChecker::new();
        let result = tc.check(&module);
        assert!(result.is_err());
    }

    #[test]
    fn foreign_binding_tracks_its_linked_symbol_name() {
        let mut lexer = Lexer::new(
            r#"(foreign printf :: (-> String Int) = "printf")
(:: main Int)
(fn main 0)"#,
            0,
        );
        let tokens = lexer.tokenize().unwrap();
        let module = Parser::new(tokens).parse_module().unwrap();
        let mut tc = TypeChecker::new();
        tc.check(&module)
            .expect("expected this program to check cleanly");
        let printf = tc
            .functions
            .iter()
            .find(|f| f.name == "printf")
            .expect("printf not registered");
        assert_eq!(printf.foreign_symbol.as_deref(), Some("printf"));
        assert!(!printf.is_builtin);
    }

    #[test]
    fn builtin_operators_are_flagged_as_builtin() {
        let tc = TypeChecker::new();
        let plus = tc
            .functions
            .iter()
            .find(|f| f.name == "+")
            .expect("+ not registered");
        assert!(plus.is_builtin);
    }

    #[test]
    fn effect_io_tag_with_foreign_call_passes() {
        assert!(check(
            r#"(foreign printf :: (-> String Int) = "printf")
(:: main Int)
;@axiom:effect(io)
(fn main (printf "hello"))"#
        )
        .is_ok());
    }

    #[test]
    fn effect_io_tag_without_foreign_call_warns() {
        let errors = check_err(
            r#"(:: main Int)
;@axiom:effect(io)
(fn main 0)"#,
        );
        assert!(errors
            .iter()
            .any(|e| matches!(e, SemError::AxtagMismatch { name, .. } if name == "main")));
    }

    #[test]
    fn pure_tag_with_foreign_call_warns() {
        let errors = check_err(
            r#"(foreign printf :: (-> String Int) = "printf")
(:: main Int)
;@axiom:pure
(fn main (printf "hello"))"#,
        );
        assert!(errors
            .iter()
            .any(|e| matches!(e, SemError::AxtagMismatch { name, .. } if name == "main")));
    }

    #[test]
    fn pure_tag_without_foreign_call_passes() {
        assert!(check(
            r#"(:: main Int)
;@axiom:pure
(fn main (+ 1 2))"#
        )
        .is_ok());
    }

    #[test]
    fn handle_strips_declared_effects_from_body_type() {
        let source = r#"(foreign printf :: (-> String Int) = "printf")
(:: main Int)
(fn main
  (handle (printf "hello") (IO) 0))"#;
        assert!(
            check(source).is_ok(),
            "handle should strip declared effects"
        );
    }

    #[test]
    fn handle_without_effects_propagates_body_effects() {
        let source = r#"(foreign printf :: (-> String Int) = "printf")
(:: main Int)
(fn main
  (handle (printf "hello") () 0))"#;
        let errors = check_err(source);
        assert!(errors
            .iter()
            .any(|e| matches!(e, SemError::EffectMismatch { .. })));
    }

    #[test]
    fn effect_io_tag_with_alloc_also_passes() {
        assert!(check(
            r#"(foreign printf :: (-> String Int) = "printf")
(:: main Int)
;@axiom:effect(io)
(fn main (let ((_ (alloc Int 1))) (printf "hello")))"#
        )
        .is_ok());
    }

    #[test]
    fn pure_tag_with_alloc_fails() {
        let errors = check_err(
            r#"(:: main Int)
;@axiom:pure
(fn main (alloc Int 1))"#,
        );
        assert!(errors
            .iter()
            .any(|e| matches!(e, SemError::AxtagMismatch { name, .. } if name == "main")));
    }

    #[test]
    fn effect_io_tag_with_handle_containing_io_passes() {
        let source = r#"(foreign printf :: (-> String Int) = "printf")
(:: main Int)
;@axiom:effect(io)
(fn main
  (handle (printf "hello") (IO) 0))"#;
        assert!(
            check(source).is_ok(),
            "effect(io) should be satisfied when IO is handled internally"
        );
    }

    #[test]
    fn pure_tag_with_handle_containing_io_fails() {
        let source = r#"(foreign printf :: (-> String Int) = "printf")
(:: main Int)
;@axiom:pure
(fn main
  (handle (printf "hello") (IO) 0))"#;
        let errors = check_err(source);
        assert!(errors
            .iter()
            .any(|e| matches!(e, SemError::AxtagMismatch { name, .. } if name == "main")));
    }
}
