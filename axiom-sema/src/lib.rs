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
    /// `set` applied to a binding that was not declared `mut`.
    ///
    /// Carries the declaration's span as well as the assignment's, so
    /// the report can show both: the fix is at the declaration, not at
    /// the line the error is on.
    #[error("cannot assign to immutable binding `{name}`")]
    AssignToImmutable {
        name: String,
        span: Span,
        decl_span: Span,
    },
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
    /// A top-level function applied to fewer arguments than its
    /// definition declares, or a function of two or more parameters
    /// used as a bare value.
    ///
    /// Both are well-typed under currying and neither has a runtime
    /// representation: a call site would simply omit the missing
    /// arguments, which is how this used to compile into a program
    /// that read register garbage and crashed. `found` is 0 for the
    /// bare-value form.
    #[error("partial application of `{name}`: it takes {expected} argument(s) and {found} were supplied")]
    PartialApplication {
        name: String,
        expected: usize,
        found: usize,
        span: Span,
    },
    /// A bare reference to a name that two or more imported modules
    /// define while the entry file defines none.
    ///
    /// There is no principled winner, and before this diagnostic the
    /// resolvers genuinely disagreed - the type checker bound one
    /// module's definition while code generation called the other's,
    /// so a program could pass `check` against a 2-parameter signature
    /// and then run a 3-parameter function on two arguments. Qualified
    /// access picks explicitly and stays legal.
    #[error("ambiguous name `{name}`: defined in {}", modules.join(" and "))]
    AmbiguousName {
        name: String,
        modules: Vec<String>,
        span: Span,
    },
    /// A signature with no definition behind it, either declared in the
    /// entry file with no matching `fn`/`foreign`, or referenced after
    /// an import delivered the `pub` signature while the definition
    /// stayed private.
    ///
    /// Calling one used to pass `check` and surface later as a raw
    /// toolchain error about an undefined symbol.
    #[error("`{name}` has a signature but no definition")]
    MissingDefinition { name: String, span: Span },
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
            SemError::AssignToImmutable { span, .. } => *span,
            SemError::DuplicateDefinition { span, .. } => *span,
            SemError::FieldNotFound { span, .. } => *span,
            SemError::Message { span, .. } => *span,
            SemError::AxtagMismatch { span, .. } => *span,
            SemError::EffectMismatch { span, .. } => *span,
            SemError::PartialApplication { span, .. } => *span,
            SemError::AmbiguousName { span, .. } => *span,
            SemError::MissingDefinition { span, .. } => *span,
        }
    }

    /// Whether this diagnostic is a warning rather than an error.
    ///
    /// Derived from the rendered diagnostic rather than from a list of
    /// variants, so the severity a reader sees and the severity that
    /// decides whether the build fails can never drift apart - which is
    /// exactly what had happened: `AX3010` rendered as `W` and aborted
    /// compilation.
    pub fn is_warning(&self) -> bool {
        !matches!(self.to_diagnostic().severity, axiom_errors::Severity::Error)
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
            SemError::AssignToImmutable {
                name, decl_span, ..
            } => Diagnostic::error(&code::ASSIGN_TO_IMMUTABLE, self.to_string())
                .with_primary(span, format!("`{}` cannot be assigned", name))
                .with_secondary(*decl_span, format!("`{}` is bound here", name))
                .with_suggestion(
                    format!("declare it mutable: `(mut {} ...)`", name),
                    *decl_span,
                    format!("mut {}", name),
                )
                .with_help(
                    "only a binding introduced by `(let ((mut x ...)) ...)` may be the target of `set`",
                ),
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
            SemError::PartialApplication {
                name,
                expected,
                found,
                ..
            } => {
                let label = if *found == 0 {
                    format!(
                        "`{}` takes {} arguments, so it cannot be used as a bare value",
                        name, expected
                    )
                } else {
                    format!(
                        "`{}` takes {} argument(s); {} more needed",
                        name,
                        expected,
                        expected - found
                    )
                };
                Diagnostic::error(&code::PARTIAL_APPLICATION, self.to_string())
                    .with_primary(span, label)
                    .with_help(
                        "bind the missing arguments with a lambda: \
                         `(lambda (y) (f x y))` builds the value `(f x)` would mean",
                    )
            }
            SemError::AmbiguousName { name, modules, .. } => {
                let candidates = modules
                    .iter()
                    .map(|m| format!("`{}::{}`", m, name))
                    .collect::<Vec<_>>()
                    .join(" or ");
                Diagnostic::error(&code::AMBIGUOUS_NAME, self.to_string())
                    .with_primary(span, format!("`{}` could mean more than one definition", name))
                    .with_help(format!("qualify the reference: {}", candidates))
            }
            SemError::MissingDefinition { name, .. } => {
                Diagnostic::error(&code::MISSING_DEFINITION, self.to_string())
                    .with_primary(span, format!("no `fn` or `foreign` defines `{}`", name))
                    .with_help(
                        "add the definition, or if it lives in another module, \
                         mark that definition `pub` so the import carries it",
                    )
            }
        }
    }
}

/// How many `TArr`s deep a type is: the number of arguments a value of
/// this type could absorb before the result stops being a function.
fn arrow_depth(ty: &TypeId) -> usize {
    let mut depth = 0;
    let mut t = ty;
    while let TypeId::TArr(_, ret) = t {
        depth += 1;
        t = ret;
    }
    depth
}

fn collect_effects(checker: &TypeChecker, expr: &Expr) -> Vec<axiom_ast::ast::Effect> {
    use std::collections::HashSet;
    let mut set = HashSet::new();
    collect_effects_into(checker, expr, &mut set);
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
            // A name is effectful either because it is a foreign
            // binding (the historical case) or because it is a
            // primitive declared with effects - `__syscall1` and
            // friends are the whole reason the standard library can
            // do I/O without a foreign binding, so an
            // `;@axiom:effect(io)` claim on a function whose body
            // only calls syscalls has to validate exactly as it did
            // when that function called `printf`.
            if let Some(f) = checker.functions.iter().find(|f| f.name == ident.name) {
                if f.foreign_symbol.is_some() {
                    out.insert(axiom_ast::ast::Effect::IO);
                }
                for e in &f.effects {
                    out.insert(e.clone());
                }
            }
        }
        Expr::EApp(func, arg) => {
            collect_effects_into(checker, func, out);
            collect_effects_into(checker, arg, out);
        }
        Expr::ELam(_, body) => collect_effects_into(checker, body, out),
        Expr::ELet(bindings, body) => {
            for b in bindings {
                collect_effects_into(checker, &b.init, out);
            }
            collect_effects_into(checker, body, out);
        }
        Expr::EWhile(cond, body) => {
            collect_effects_into(checker, cond, out);
            collect_effects_into(checker, body, out);
        }
        Expr::EAssign(_, value) => collect_effects_into(checker, value, out),
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
        Expr::EQuasiquote(inner) | Expr::EUnquote(inner) | Expr::ESplice(inner) => {
            collect_effects_into(checker, inner, out)
        }
        Expr::EQualified(_, name) => {
            if let Some(f) = checker.functions.iter().find(|f| f.name == name.name) {
                if f.foreign_symbol.is_some() {
                    out.insert(axiom_ast::ast::Effect::IO);
                }
                for e in &f.effects {
                    out.insert(e.clone());
                }
            }
        }
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
            // A `String` is a `Str` handle - one machine word, the
            // address of a `{ len, bytes }` header - and so is
            // interchangeable with `Int`.
            //
            // This is not a hole punched for convenience; it is the
            // uniform-representation model the language already runs
            // on, made visible at one place instead of worked around at
            // every boundary. `Str` handles are `Int` throughout
            // `stdlib/` and the self-hosted compiler, `Vec` stores
            // `Int`, `Map` keys are `Int`, and `memGetWord` takes
            // `Int`. Without this rule a first-class string literal
            // could not be stored in a `Vec`, used as a `Map` key, or
            // read by the very accessors that implement `Str`, and the
            // alternative - a cast at each of those boundaries, or a
            // container library polymorphic over representation that
            // does not exist - would buy a distinction the runtime does
            // not make.
            //
            // The cost is real and bounded: `(+ 1 "hi")` type-checks,
            // adding one to an address. It is the same latitude the
            // language already gives every other handle.
            (TypeId::TCon(n1, _), TypeId::TCon(n2, _))
                if matches!(
                    (n1.as_str(), n2.as_str()),
                    ("String", "Int") | ("Int", "String")
                ) =>
            {
                true
            }
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
    /// Whether `set` may store into this binding.
    ///
    /// Only `(let ((mut x ...)) ...)` sets this. Everything else -
    /// function parameters, ordinary `let`s, top-level declarations,
    /// pattern bindings - is immutable, which is what makes `set` a
    /// checked operation rather than an unrestricted store.
    pub mutable: bool,
}

#[derive(Debug, Clone)]
pub struct DataConInfo {
    pub name: String,
    pub ty: TypeId,
    pub data_type: String,
    pub field_names: Option<Vec<String>>,
    pub module: Option<String>,
}

#[derive(Debug, Clone)]
pub struct FnInfo {
    pub name: String,
    pub ty: TypeId,
    pub foreign_symbol: Option<String>,
    pub is_builtin: bool,
    pub effects: Vec<axiom_ast::ast::Effect>,
    pub module: Option<String>,
    /// How many parameters the function's *definition* declares -
    /// `Some(params.len())` once its `DFn` has been collected, `None`
    /// for builtins, foreigns, and signature-only entries.
    ///
    /// This is a representation fact, not a type fact, and the two
    /// genuinely differ: `(:: mk (-> Int (-> Int Int)))` with
    /// `(fn (mk a) (lambda (b) ...))` has an arrow two deep and one
    /// declared parameter. Saturation - the thing the backend can
    /// actually compile - is measured against the parameter count,
    /// and only the arrow depth is visible in the type. Partial
    /// application below the parameter count has no runtime
    /// representation (a call site would simply omit the missing
    /// arguments), which is why [`SemError::PartialApplication`]
    /// exists.
    pub param_count: Option<usize>,
}

#[derive(Debug, Clone)]
pub struct DataTypeInfo {
    pub name: String,
    pub tyvars: Vec<String>,
    pub constructors: Vec<DataConInfo>,
    pub module: Option<String>,
}

#[derive(Debug, Clone)]
pub struct StructInfo {
    pub name: String,
    pub fields: Vec<(String, TypeId)>,
    pub module: Option<String>,
}

/// A `type` alias declaration: `name`'s type parameters and the type it
/// stands for.
#[derive(Debug, Clone)]
pub struct TypeAliasInfo {
    pub name: String,
    pub tyvars: Vec<String>,
    pub target: TypeId,
    pub module: Option<String>,
}

/// The names of Axiom's freestanding primitives, together with how
/// many arguments each takes and whether calling it is an I/O
/// effect.
///
/// These are the operations the standard library cannot express in
/// terms of anything else, and are the replacement for what used to
/// require a C foreign binding: raw syscalls, byte- and
/// word-granular memory access at a runtime index, taking the
/// address of a literal, and requesting heap memory. Everything
/// else in the standard library - string handling, formatting,
/// buffered I/O, growable arrays - is ordinary Axiom code written on
/// top of these.
///
/// Each entry is `(name, arity, is_io)`. All arguments and results
/// are `Int`; the primitives are deliberately untyped beyond that,
/// because they are the layer where Axiom's type system stops and
/// the machine begins. Safe, typed wrappers are the standard
/// library's job (`stdlib/Mem.ax`, `stdlib/IO.ax`).
pub const PRIMITIVES: &[(&str, usize, bool)] = &[
    // Raw syscalls, by argument count (excluding the syscall
    // number, which is the first parameter of each).
    ("__syscall0", 1, true),
    ("__syscall1", 2, true),
    ("__syscall2", 3, true),
    ("__syscall3", 4, true),
    ("__syscall4", 5, true),
    ("__syscall5", 6, true),
    ("__syscall6", 7, true),
    // `(__load8 base index)` -> byte at `base + index`.
    ("__load8", 2, false),
    // `(__store8 base index value)` -> 0.
    ("__store8", 3, false),
    // `(__load64 base index)` -> word at `base + index * 8`.
    ("__load64", 2, false),
    // `(__store64 base index value)` -> 0.
    ("__store64", 3, false),
    // `(__alloc bytes)` -> address of `bytes` fresh zeroed bytes.
    ("__alloc", 1, false),
    // Arena watermark: save / restore bump-allocator position.
    ("__axiom_arena_mark", 0, false),
    ("__axiom_arena_reset", 1, false),
];

/// `(__addr s)` -> the address of string literal `s`'s bytes.
///
/// Kept out of [`PRIMITIVES`] because it is the one primitive whose
/// argument is not an `Int`: it takes a `String`, which is exactly
/// what makes it useful (handing a literal's bytes to `write`).
pub const PRIM_ADDR: &str = "__addr";

/// `(__intToFloat n)` -> `n` as a `Float`.
///
/// Kept out of [`PRIMITIVES`] for the same reason as [`PRIM_ADDR`]: the
/// table assumes every primitive is `Int -> ... -> Int`, and these two
/// are the conversions, so one end of each is a `Float`.
pub const PRIM_INT_TO_FLOAT: &str = "__intToFloat";

/// `(__floatToInt x)` -> `x` truncated toward zero.
pub const PRIM_FLOAT_TO_INT: &str = "__floatToInt";

impl FnInfo {
    fn new(name: impl Into<String>, ty: TypeId) -> Self {
        Self {
            name: name.into(),
            ty,
            foreign_symbol: None,
            is_builtin: false,
            effects: Vec::new(),
            module: None,
            param_count: None,
        }
    }

    fn builtin(name: impl Into<String>, ty: TypeId) -> Self {
        Self {
            name: name.into(),
            ty,
            foreign_symbol: None,
            is_builtin: true,
            effects: Vec::new(),
            module: None,
            param_count: None,
        }
    }

    fn builtin_with_effects(
        name: impl Into<String>,
        ty: TypeId,
        effects: Vec<axiom_ast::ast::Effect>,
    ) -> Self {
        Self {
            name: name.into(),
            ty,
            foreign_symbol: None,
            is_builtin: true,
            effects,
            module: None,
            param_count: None,
        }
    }
}

#[derive(Debug, Clone)]
pub struct TraitInfo {
    pub name: String,
    pub methods: Vec<(String, TypeId)>,
    pub effects: Vec<axiom_ast::ast::Effect>,
    pub module: Option<String>,
}

pub struct TypeChecker {
    pub scope: Vec<(String, usize, VarInfo)>,
    pub data_types: Vec<DataTypeInfo>,
    pub structs: Vec<StructInfo>,
    pub aliases: Vec<TypeAliasInfo>,
    pub functions: Vec<FnInfo>,
    pub traits: Vec<TraitInfo>,
    pub errors: Vec<SemError>,
    /// Diagnostics from the last `check` whose severity is warning.
    /// Kept separate so they can be reported without failing the build.
    pub warnings: Vec<SemError>,
    pub type_counter: usize,
    /// True while checking the *function* side of an application - the
    /// head chain of a spine - and false everywhere else. A bare
    /// reference to a multi-parameter function or a fieldful
    /// constructor is fine as a head (the application supplies the
    /// arguments) and unsupported as a value (nothing ever will), and
    /// this flag is how `check_var` tells the two apart. Only the
    /// `EApp` arm sets it, and it clears it around argument checking,
    /// so every other position reads `false`.
    in_app_head: bool,
    /// Which modules declare each bare value-namespace name (`fn`,
    /// `foreign`, or signature), deduped, in merge order; `None` is the
    /// entry file. Two or more `Some` entries with no `None` is
    /// [`SemError::AmbiguousName`]: bare-name resolution is entry file
    /// first, then the *unique* defining module - there is no
    /// import-versus-import precedence, because any choice would be one
    /// the other compiler stages could disagree with, and did.
    fn_defining_modules: std::collections::HashMap<String, Vec<Option<String>>>,
    /// Same, for data constructors.
    ctor_defining_modules: std::collections::HashMap<String, Vec<Option<String>>>,
}

impl Default for TypeChecker {
    fn default() -> Self {
        Self::new()
    }
}

/// Where a name was first defined, keyed by `(name, module)`.
///
/// The module is part of the key, not a payload: a redefinition is only
/// a duplicate *within* one module, and a table keyed by name alone
/// never recorded the second module's definition at all - so a genuine
/// duplicate inside that second module was invisible to it.
type DefinitionTable = std::collections::HashMap<(String, Option<String>), Span>;

impl TypeChecker {
    /// Put every entry of [`PRIMITIVES`] (plus [`PRIM_ADDR`]) in
    /// scope as a builtin function.
    ///
    /// Driven off the `PRIMITIVES` table rather than written out
    /// one-by-one so that adding a primitive is a single-line change
    /// that cannot drift out of sync with the IR lowering, which
    /// reads the same table.
    fn register_primitives(&mut self) {
        let int_ty = TypeId::TCon("Int".to_string(), vec![]);
        for (name, arity, is_io) in PRIMITIVES {
            let mut ty = int_ty.clone();
            for _ in 0..*arity {
                ty = TypeId::TArr(Box::new(int_ty.clone()), Box::new(ty));
            }
            let effects = if *is_io {
                vec![axiom_ast::ast::Effect::IO]
            } else {
                Vec::new()
            };
            self.functions
                .push(FnInfo::builtin_with_effects(*name, ty, effects));
        }
        self.functions.push(FnInfo::builtin(
            PRIM_ADDR,
            TypeId::TArr(
                Box::new(TypeId::TCon("String".to_string(), vec![])),
                Box::new(int_ty.clone()),
            ),
        ));

        // Numeric conversion between `Int` and `Float`.
        //
        // These are not `cast`. `cast` reinterprets - it relabels the
        // machine word, which for a float is its IEEE bit pattern, so
        // `(cast Int 1.5)` is 4609434218613702656 rather than 1. That
        // reinterpretation is what lets a float travel through the
        // `Int`-typed standard library (`Vec`, `Map`, `memSetWord`)
        // without loss, so it is worth having; it is just never what
        // "convert this number" means.
        let float_ty = TypeId::TCon("Float".to_string(), vec![]);
        self.functions.push(FnInfo::builtin(
            PRIM_INT_TO_FLOAT,
            TypeId::TArr(Box::new(int_ty.clone()), Box::new(float_ty.clone())),
        ));
        self.functions.push(FnInfo::builtin(
            PRIM_FLOAT_TO_INT,
            TypeId::TArr(Box::new(float_ty), Box::new(int_ty)),
        ));
    }

    /// Whether `ty` is one of the floating-point types.
    ///
    /// `Float` is the surface spelling and `F64` the explicit-width one;
    /// both are IEEE-754 doubles. `F32` is accepted as a name but is
    /// stored and computed at double precision, since every Axiom value
    /// occupies one machine word.
    pub fn is_float(ty: &TypeId) -> bool {
        is_float_ty(ty)
    }

    pub fn new() -> Self {
        let mut tc = Self {
            scope: Vec::new(),
            data_types: Vec::new(),
            structs: Vec::new(),
            aliases: Vec::new(),
            functions: Vec::new(),
            traits: Vec::new(),
            errors: Vec::new(),
            warnings: Vec::new(),
            type_counter: 0,
            in_app_head: false,
            fn_defining_modules: std::collections::HashMap::new(),
            ctor_defining_modules: std::collections::HashMap::new(),
        };

        let int_ty = TypeId::TCon("Int".to_string(), vec![]);
        let bool_ty = TypeId::TCon("Bool".to_string(), vec![]);
        let int_int = TypeId::TArr(Box::new(int_ty.clone()), Box::new(int_ty.clone()));
        let int_int_int = TypeId::TArr(Box::new(int_ty.clone()), Box::new(int_int.clone()));

        // Bitwise operators are `Int -> Int -> Int` like the arithmetic
        // ones. `>>` is arithmetic (sign-preserving), matching `Int`
        // being signed; on these targets a userspace address is well
        // below 2^63, so address arithmetic sees no difference.
        //
        // Without these, Axiom cannot express an allocator: packing a
        // size and a mark bit into a header word, masking an address to
        // an alignment boundary, and indexing a bitmap all need them.
        // The IR and the LLVM backend have carried `BitAnd`/`BitOr`/
        // `BitXor`/`Shl`/`Shr` all along; nothing had ever connected
        // them to syntax.
        for op in &["+", "-", "*", "/", "%", "&", "|", "^", "<<", ">>"] {
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

        tc.register_primitives();

        tc.data_types.push(DataTypeInfo {
            name: "Option".to_string(),
            tyvars: vec!["a".to_string()],
            constructors: vec![
                DataConInfo {
                    name: "Some".to_string(),
                    ty: TypeId::TArr(
                        Box::new(TypeId::TVar("a".to_string())),
                        Box::new(TypeId::TCon(
                            "Option".to_string(),
                            vec![TypeId::TVar("a".to_string())],
                        )),
                    ),
                    data_type: "Option".to_string(),
                    field_names: None,
                    module: None,
                },
                DataConInfo {
                    name: "None".to_string(),
                    ty: TypeId::TCon("Option".to_string(), vec![TypeId::TVar("a".to_string())]),
                    data_type: "Option".to_string(),
                    field_names: None,
                    module: None,
                },
            ],
            module: None,
        });

        tc
    }

    /// Type-check a module.
    ///
    /// `Err` carries the errors alone. Diagnostics that render as
    /// warnings do not fail the check and are left in
    /// [`TypeChecker::warnings`] for the caller to report on either
    /// path - they are still printed, just not fatal.
    pub fn check(&mut self, module: &Module) -> Result<(), Vec<SemError>> {
        self.check_duplicate_definitions(&module.decls);
        self.check_entry_signatures(&module.decls);
        self.collect_declarations(module);
        self.infer_effects(&module.decls);
        self.check_decls(&module.decls);

        // A warning must not fail the build. Everything the checker
        // produced went into one `errors` list, so an `AX3010` AXTAG
        // mismatch - documented as a warning precisely "so an agent can
        // correct the annotation instead of silently trusting it" -
        // aborted compilation and was announced as
        // "compilation failed due to 1 previous error", of a diagnostic
        // the renderer had already labelled `W`. The severity and the
        // behaviour disagreed, and the behaviour was the wrong one.
        let (warnings, errors): (Vec<SemError>, Vec<SemError>) = std::mem::take(&mut self.errors)
            .into_iter()
            .partition(|e| e.is_warning());
        self.warnings = warnings;

        if errors.is_empty() {
            Ok(())
        } else {
            Err(errors)
        }
    }

    /// Detect a name defined more than once within the same namespace at
    /// module scope. Previously `AX3006`/`SemError::DuplicateDefinition`
    /// was declared but never actually constructed anywhere - two
    /// top-level `(define (f ...) ...)`s with the same name, or two
    /// `data`/`struct`/`type` declarations with the same name,
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
        let mut values: DefinitionTable = std::collections::HashMap::new();
        let mut types: DefinitionTable = std::collections::HashMap::new();

        for decl in decls {
            let (namespace, name, module_path): (&mut DefinitionTable, &Ident, &Option<String>) =
                match decl {
                    Decl::DFn {
                        name, module_path, ..
                    } => (&mut values, name, module_path),
                    Decl::DForeign {
                        name, module_path, ..
                    } => (&mut values, name, module_path),
                    Decl::DData {
                        name, module_path, ..
                    } => (&mut types, name, module_path),
                    Decl::DStruct {
                        name, module_path, ..
                    } => (&mut types, name, module_path),
                    Decl::DType {
                        name, module_path, ..
                    } => (&mut types, name, module_path),
                    _ => continue,
                };

            // Keyed by (name, module), not by name: a table that only
            // remembered the first module's definition never *recorded*
            // a second module's, so a genuine duplicate inside that
            // second module escaped detection entirely. Cross-module
            // same-name declarations remain legal here - a bare
            // reference to one is the ambiguity check's business.
            let key = (name.name.clone(), module_path.clone());
            if let Some(first_span) = namespace.get(&key) {
                self.errors.push(SemError::DuplicateDefinition {
                    name: name.name.clone(),
                    span: name.span,
                    first_span: *first_span,
                });
            } else {
                namespace.insert(key, name.span);
            }
        }
    }

    /// Build the [`DataTypeInfo`] for one `data` declaration, including
    /// every constructor's curried field-arrow type. Shared by
    /// `collect_declarations` and `register_decl` (previously this logic
    /// was copy-pasted between the two almost verbatim, which is exactly
    /// how a bug fix applied to one could - and did - miss the other).
    ///
    /// Every constructor's outer type is `TCon(name, tyvars-as-TVars)`,
    /// *including* nullary constructors: `Nil`'s type is `List a`, not
    /// bare `List` with the type parameter silently dropped. Dropping it
    /// for the nullary match (the bug this replaced) was invisible for a
    /// long time because nothing ever compared a nullary constructor's
    /// type against anything - it only became observable once
    /// `Expr::EApp` started actually checking argument types against
    /// parameter types (see `compatible_with`'s call sites): `(Cons 3
    /// (Nil))` would report "expected `List a`, found `List`" for its
    /// second argument even though the program is completely correct.
    fn build_data_type_info(
        &self,
        name: &Ident,
        tyvars: &[String],
        constructors: &[axiom_ast::ast::DataCon],
        module_path: Option<String>,
    ) -> DataTypeInfo {
        let type_args: Vec<TypeId> = tyvars.iter().map(|v| TypeId::TVar(v.clone())).collect();
        let mut con_infos = Vec::new();
        for con in constructors {
            let field_tys: Vec<TypeId> = match &con.con_fields {
                ConFields::Positional(tys) => tys.iter().map(|ft| self.type_to_id(ft)).collect(),
                ConFields::Named(fields) => fields.iter().map(|f| self.type_to_id(&f.ty)).collect(),
            };
            let mut con_ty = TypeId::TCon(name.name.clone(), type_args.clone());
            for ft in field_tys.into_iter().rev() {
                con_ty = TypeId::TArr(Box::new(ft), Box::new(con_ty));
            }
            let field_names = match &con.con_fields {
                ConFields::Named(fields) => {
                    Some(fields.iter().map(|f| f.name.name.clone()).collect())
                }
                ConFields::Positional(_) => None,
            };
            con_infos.push(DataConInfo {
                name: con.name.name.clone(),
                ty: con_ty,
                data_type: name.name.clone(),
                field_names,
                module: module_path.clone(),
            });
        }
        DataTypeInfo {
            name: name.name.clone(),
            tyvars: tyvars.to_vec(),
            constructors: con_infos,
            module: module_path,
        }
    }

    /// A signature in the entry file with no `fn` or `foreign` behind
    /// it, reported at the signature - the earliest point with the best
    /// span. Entry file only: an *imported* module can legitimately
    /// deliver a `pub` signature whose private definition the import
    /// filtered away, and that case is harmless until used, so it is
    /// reported at the reference instead (`check_var`,
    /// `check_app_saturation`). Before this check, calling a
    /// signature-only name passed `check` and failed in the native
    /// toolchain as `use of undefined value` - a raw error about
    /// generated code, with no diagnostic code, for a program the
    /// compiler had just accepted.
    fn check_entry_signatures(&mut self, decls: &[Decl]) {
        use std::collections::HashSet;
        let defined: HashSet<&str> = decls
            .iter()
            .filter_map(|d| match d {
                Decl::DFn {
                    name,
                    module_path: None,
                    ..
                }
                | Decl::DForeign {
                    name,
                    module_path: None,
                    ..
                } => Some(name.name.as_str()),
                _ => None,
            })
            .collect();
        for d in decls {
            if let Decl::DSig {
                name,
                module_path: None,
                ..
            } = d
            {
                if !defined.contains(name.name.as_str()) {
                    self.errors.push(SemError::MissingDefinition {
                        name: name.name.clone(),
                        span: name.span,
                    });
                }
            }
        }
    }

    fn collect_declarations(&mut self, module: &Module) {
        // First pass: who declares each bare name. This is the map the
        // ambiguity check reads, and it must be complete before any
        // body is checked, so it cannot ride along in the main walk.
        for decl in &module.decls {
            match decl {
                Decl::DSig {
                    name, module_path, ..
                }
                | Decl::DFn {
                    name, module_path, ..
                }
                | Decl::DForeign {
                    name, module_path, ..
                } => {
                    let mods = self
                        .fn_defining_modules
                        .entry(name.name.clone())
                        .or_default();
                    if !mods.contains(module_path) {
                        mods.push(module_path.clone());
                    }
                }
                Decl::DData {
                    constructors,
                    module_path,
                    ..
                } => {
                    for con in constructors {
                        let mods = self
                            .ctor_defining_modules
                            .entry(con.name.name.clone())
                            .or_default();
                        if !mods.contains(module_path) {
                            mods.push(module_path.clone());
                        }
                    }
                }
                _ => {}
            }
        }
        for decl in &module.decls {
            match decl {
                Decl::DData {
                    name,
                    tyvars,
                    constructors,
                    module_path,
                    ..
                } => {
                    self.data_types.push(self.build_data_type_info(
                        name,
                        tyvars,
                        constructors,
                        module_path.clone(),
                    ));
                }
                Decl::DStruct {
                    name,
                    fields,
                    module_path,
                    ..
                } => {
                    let struct_fields: Vec<(String, TypeId)> = fields
                        .iter()
                        .map(|f| (f.name.name.clone(), self.type_to_id(&f.ty)))
                        .collect();
                    self.structs.push(StructInfo {
                        name: name.name.clone(),
                        fields: struct_fields,
                        module: module_path.clone(),
                    });
                }
                Decl::DSig {
                    name,
                    ty,
                    module_path,
                    ..
                } => {
                    let mut info = FnInfo::new(name.name.clone(), self.type_to_id(ty));
                    info.module = module_path.clone();
                    self.functions.push(info);
                }
                Decl::DTrait {
                    name,
                    methods,
                    effects,
                    module_path,
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
                        module: module_path.clone(),
                    });
                }
                Decl::DFn {
                    name,
                    params,
                    module_path,
                    ..
                } => {
                    if !self
                        .functions
                        .iter()
                        .any(|f| f.name == name.name && f.module == *module_path)
                    {
                        let mut info = FnInfo::new(
                            name.name.clone(),
                            TypeId::TVar(format!("_fn_{}", self.type_counter)),
                        );
                        info.module = module_path.clone();
                        self.functions.push(info);
                        self.type_counter += 1;
                    }
                    // The signature usually registered this entry first,
                    // so the parameter count is recorded on whichever
                    // entry the name resolves to rather than only on a
                    // freshly created one.
                    if let Some(f) = self
                        .functions
                        .iter_mut()
                        .find(|f| f.name == name.name && f.module == *module_path)
                    {
                        f.param_count = Some(params.len());
                    }
                }
                Decl::DForeign {
                    name,
                    ty,
                    source,
                    module_path,
                    ..
                } => {
                    let mut info = FnInfo::new(name.name.clone(), self.type_to_id(ty));
                    info.foreign_symbol = Some(source.clone());
                    info.module = module_path.clone();
                    self.functions.push(info);
                }
                Decl::DType {
                    name,
                    tyvars,
                    alias,
                    module_path,
                    ..
                } => {
                    self.aliases.push(TypeAliasInfo {
                        name: name.name.clone(),
                        tyvars: tyvars.clone(),
                        target: self.type_to_id(alias),
                        module: module_path.clone(),
                    });
                }
                _ => {}
            }
        }
    }

    /// Infer each function's effects from its body, transitively.
    ///
    /// Without this, effect analysis only saw effects a function
    /// performed *itself* - a direct `foreign` call or syscall - so a
    /// function that did its I/O by calling another Axiom function
    /// looked pure. That was tolerable when every effect entered the
    /// program through a `foreign` binding at the point of use, and is
    /// not once there is a standard library: `println` calls `writeStr`
    /// calls `sysWriteFd` calls `__syscall3`, and an
    /// `;@axiom:effect(io)` claim on the caller of any of those has to
    /// validate.
    ///
    /// Implemented as a fixpoint rather than a topological walk because
    /// Axiom has no declaration-order requirement and mutual recursion
    /// is legal: each round recomputes every function's effects from
    /// the effects known so far, and effects only ever grow, so the
    /// iteration is monotone and terminates in at most one round per
    /// function (call-graph depth in practice). Recursive functions
    /// converge on the first round in which their callees stop
    /// changing.
    fn infer_effects(&mut self, decls: &[Decl]) {
        let bodies: Vec<(String, &Expr)> = decls
            .iter()
            .filter_map(|d| match d {
                Decl::DFn { name, body, .. } => Some((name.name.clone(), body)),
                _ => None,
            })
            .collect();

        // One extra round beyond the number of functions can never be
        // needed (each round propagates at least one call-graph edge),
        // and the bound guarantees termination even if a future change
        // makes `collect_effects` non-monotone.
        for _ in 0..=bodies.len() {
            let mut changed = false;
            for (name, body) in &bodies {
                let inferred = collect_effects(self, body);
                if let Some(info) = self.functions.iter_mut().find(|f| &f.name == name) {
                    for e in inferred {
                        if !info.effects.contains(&e) {
                            info.effects.push(e);
                            changed = true;
                        }
                    }
                }
            }
            if !changed {
                break;
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
                        name.scope,
                        VarInfo {
                            ty: ty_id,
                            span: name.span,
                            mutable: false,
                        },
                    ));
                }
                Decl::DFn {
                    name,
                    params,
                    body,
                    axtags,
                    module_path,
                    ..
                } => {
                    let sig_ty = self
                        .functions
                        .iter()
                        .find(|f| f.name == name.name && f.module == *module_path)
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
                    if let Some(fn_info) = self
                        .functions
                        .iter_mut()
                        .find(|f| f.name == name.name && f.module == *module_path)
                    {
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
                                let actual = collect_effects(self, body);
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
                                let actual = collect_effects(self, body);
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
                        name.scope,
                        VarInfo {
                            ty: ty_id,
                            span: name.span,
                            mutable: false,
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

    /// Check if `expr` is a struct construction: a variable
    /// reference to a known struct name, possibly applied to
    /// arguments via nested `EApp`. Returns `(struct_name,
    /// args)` if so, or `None` otherwise.
    fn find_struct_con(&self, expr: &Expr) -> Option<(Ident, Vec<Expr>)> {
        let mut args = Vec::new();
        let mut current = expr;
        loop {
            match current {
                Expr::EApp(func, arg) => {
                    args.push(arg.as_ref().clone());
                    current = func;
                }
                Expr::EVar(ident) | Expr::EQualified(_, ident) => {
                    if self.structs.iter().any(|s| s.name == ident.name) {
                        args.reverse();
                        return Some((ident.clone(), args));
                    }
                    return None;
                }
                _ => return None,
            }
        }
    }

    /// Wrapper that scopes [`TypeChecker::in_app_head`]: the flag means
    /// "this expression is the function side of an application", which
    /// is only true of the `EVar`/`EQualified`/`EApp` chain itself - a
    /// lambda, `let`, or `match` sitting in head position is a head,
    /// but its *body* is back to being ordinary value territory. The
    /// wrapper clears the flag for every non-chain expression and
    /// restores the caller's value afterwards, so the `EApp` arm's
    /// early returns cannot leak a stale `true` either.
    fn check_expr(&mut self, expr: &Expr) -> TypeId {
        let saved = self.in_app_head;
        if !matches!(expr, Expr::EVar(_) | Expr::EQualified(_, _) | Expr::EApp(_, _)) {
            self.in_app_head = false;
        }
        let ty = self.check_expr_inner(expr);
        self.in_app_head = saved;
        ty
    }

    fn check_expr_inner(&mut self, expr: &Expr) -> TypeId {
        match expr {
            Expr::EVar(ident) => self.check_var(ident),
            Expr::ELit(lit, _) => self.check_literal(lit),
            Expr::EApp(func, arg) => {
                // Saturation is checked once per spine, at its root: this
                // node is the root exactly when it was not reached as the
                // head of an enclosing application. Everything below runs
                // with the flag cleared, so operands and arguments read
                // as value positions; only the recursion into `func`
                // re-raises it.
                let at_spine_root = !self.in_app_head;
                self.in_app_head = false;
                if at_spine_root && self.check_app_saturation(expr) {
                    // The spine is refused. The arguments are still
                    // checked for their own diagnostics, and the whole
                    // spine types as `TError`, so the refusal is the one
                    // report - without the poison, the leftover arrow
                    // this would otherwise type as fed a second,
                    // consequent mismatch at the same site ("expected
                    // function type" on the follow-on application, or an
                    // operand mismatch inside `+`).
                    let mut spine_args = Vec::new();
                    let mut current = expr;
                    while let Expr::EApp(func, a) = current {
                        spine_args.push(a.as_ref());
                        current = func;
                    }
                    for a in spine_args.into_iter().rev() {
                        self.check_expr(a);
                    }
                    return TypeId::TError;
                }

                // Arithmetic and comparison over `Int` *or* `Float`.
                //
                // The operators are registered as builtins with the fixed
                // type `Int -> Int -> Int`, so a float operand was a type
                // error and floating point was unusable. They are
                // intercepted here rather than made polymorphic because
                // there is no numeric type class to constrain a type
                // variable with, and an unconstrained one would let
                // `(+ "a" "b")` through.
                //
                // Only the saturated two-argument form is intercepted; a
                // partial application like `(+ 1)` falls through to the
                // ordinary path, where `check_app_saturation` has already
                // reported it - the backend has no representation for a
                // partially applied operator any more than for a
                // partially applied function.
                if let Some((op, lhs, rhs)) = numeric_builtin_app(expr) {
                    return self.check_numeric_builtin(op, lhs, rhs);
                }

                // Check for struct construction first:
                // `(Point 1 2)` where `Point` is a known struct name.
                if let Some((struct_ident, con_args)) = self.find_struct_con(expr) {
                    let si = self
                        .structs
                        .iter()
                        .find(|s| s.name == struct_ident.name)
                        .cloned();
                    if let Some(si) = si {
                        if con_args.len() != si.fields.len() {
                            self.errors.push(SemError::Message {
                                message: format!(
                                    "struct `{}` expects {} field(s), found {}",
                                    struct_ident.name,
                                    si.fields.len(),
                                    con_args.len(),
                                ),
                                span: expr.span(),
                            });
                            return TypeId::TError;
                        }
                        for (i, con_arg) in con_args.iter().enumerate() {
                            let arg_ty = self.check_expr(con_arg);
                            let expected_ty = si.fields[i].1.clone();
                            if !arg_ty.compatible_with(&expected_ty) {
                                self.errors.push(SemError::TypeMismatch {
                                    expected: format!("{}", expected_ty),
                                    found: format!("{}", arg_ty),
                                    span: con_arg.span(),
                                });
                            }
                        }
                        return self.type_to_id(&Type::TCon(struct_ident, vec![]));
                    }
                }

                self.in_app_head = true;
                let func_ty = self.check_expr(func);
                self.in_app_head = false;
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
                let mut ptypes: Vec<TypeId> = Vec::new();
                for pat in patterns {
                    let fresh = TypeId::TVar(format!("_t{}", self.type_counter));
                    self.type_counter += 1;
                    ptypes.push(fresh.clone());
                    self.check_pattern_with_type(pat, &fresh);
                }
                let body_ty = self.check_expr(body);
                self.pop_scope();
                let param_ty = match ptypes.len() {
                    0 => TypeId::TTuple(vec![]),
                    1 => ptypes.into_iter().next().unwrap(),
                    _ => TypeId::TTuple(ptypes),
                };
                TypeId::TArr(Box::new(param_ty), Box::new(body_ty))
            }
            Expr::ELet(bindings, body) => {
                self.push_scope();
                for b in bindings {
                    let init_ty = self.check_expr(&b.init);
                    self.check_pattern_with_type_mut(&b.pat, &init_ty, b.mutable);
                }
                let body_ty = self.check_expr(body);
                self.pop_scope();
                body_ty
            }
            Expr::EWhile(cond, body) => {
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
                // The body's value is discarded, so its type is
                // unconstrained - a loop body is run for its effects.
                self.check_expr(body);
                // A loop that ran zero times has no last iteration to
                // take a value from, so the form is `Int` 0 rather than
                // something whose type depends on the trip count.
                TypeId::TCon("Int".to_string(), vec![])
            }
            Expr::EAssign(target, value) => {
                let value_ty = self.check_expr(value);
                match self.lookup_var(&target.name, target.scope) {
                    Some(info) => {
                        let (var_ty, mutable, decl_span) =
                            (info.ty.clone(), info.mutable, info.span);
                        if !mutable {
                            self.errors.push(SemError::AssignToImmutable {
                                name: target.name.clone(),
                                span: target.span,
                                decl_span,
                            });
                        }
                        if !value_ty.is_error()
                            && !var_ty.is_error()
                            && !value_ty.compatible_with(&var_ty)
                        {
                            self.errors.push(SemError::TypeMismatch {
                                expected: format!("{}", var_ty),
                                found: format!("{}", value_ty),
                                span: value.span(),
                            });
                        }
                        var_ty
                    }
                    None => {
                        self.errors.push(SemError::UndefinedVariable {
                            name: target.name.clone(),
                            span: target.span,
                            suggestion: suggest_closest(
                                &target.name,
                                self.scope.iter().map(|(n, _, _)| n.as_str()),
                            ),
                        });
                        TypeId::TError
                    }
                }
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
                        Pattern::PCon(ident, _) | Pattern::PConNamed(ident, _) => {
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
                        if let Some(dt) = self.data_types.iter().find(|d| &d.name == name) {
                            let missing: Vec<String> = dt
                                .constructors
                                .iter()
                                .map(|c| c.name.clone())
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
            Expr::EConsume(e) => self.check_expr(e),
            Expr::EField(base, field_ident) => {
                let base_ty = self.check_expr(base);
                if let TypeId::TCon(type_name, _) = &base_ty {
                    for si in &self.structs {
                        if si.name == *type_name {
                            for (fname, fty) in &si.fields {
                                if fname == &field_ident.name {
                                    return fty.clone();
                                }
                            }
                        }
                    }
                    if let Some((_dt_name, _idx, fty)) =
                        self.find_data_field_by_name(&field_ident.name)
                    {
                        return fty;
                    }
                    self.errors.push(SemError::FieldNotFound {
                        field: field_ident.name.clone(),
                        ty: type_name.clone(),
                        span: field_ident.span,
                    });
                } else {
                    self.errors.push(SemError::TypeMismatch {
                        expected: "struct or data type".to_string(),
                        found: format!("{}", base_ty),
                        span: base.span(),
                    });
                }
                TypeId::TCon("I64".to_string(), vec![])
            }
            Expr::EStructCon(name, args) => {
                let si = self.structs.iter().find(|s| s.name == name.name).cloned();
                match si {
                    Some(si) => {
                        if args.len() != si.fields.len() {
                            self.errors.push(SemError::Message {
                                message: format!(
                                    "struct `{}` expects {} field(s), found {}",
                                    name.name,
                                    si.fields.len(),
                                    args.len(),
                                ),
                                span: expr.span(),
                            });
                            return TypeId::TError;
                        }
                        for (i, arg) in args.iter().enumerate() {
                            let arg_ty = self.check_expr(arg);
                            let expected_ty = si.fields[i].1.clone();
                            if !arg_ty.compatible_with(&expected_ty) {
                                self.errors.push(SemError::TypeMismatch {
                                    expected: format!("{}", expected_ty),
                                    found: format!("{}", arg_ty),
                                    span: arg.span(),
                                });
                            }
                        }
                        self.type_to_id(&Type::TCon(name.clone(), vec![]))
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
            Expr::ESetField(base, field_ident, value) => {
                let base_ty = self.check_expr(base);
                if let TypeId::TCon(type_name, _) = &base_ty {
                    let field_info = self
                        .structs
                        .iter()
                        .find(|s| s.name == *type_name)
                        .cloned()
                        .and_then(|si| {
                            si.fields
                                .iter()
                                .find(|(fname, _)| fname == &field_ident.name)
                                .map(|(fname, fty)| (fname.clone(), fty.clone()))
                        });
                    let data_field_info = if field_info.is_none() {
                        self.find_data_field_by_name(&field_ident.name)
                            .map(|(_, _, fty)| (field_ident.name.clone(), fty))
                    } else {
                        None
                    };
                    match field_info.or(data_field_info) {
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
                                ty: type_name.clone(),
                                span: field_ident.span,
                            });
                        }
                    }
                } else {
                    self.errors.push(SemError::TypeMismatch {
                        expected: "struct or data type".to_string(),
                        found: format!("{}", base_ty),
                        span: base.span(),
                    });
                }
                TypeId::TCon("I64".to_string(), vec![])
            }
            Expr::EError(_, _) => TypeId::TVar(format!("_t{}", self.type_counter)),
            Expr::EQualified(path, name) => self.check_qualified_var(path, name),
            Expr::EQuasiquote(inner) | Expr::EUnquote(inner) | Expr::ESplice(inner) => {
                self.check_expr(inner)
            }
        }
    }

    /// The number of arguments a function's *representation* wants at a
    /// call site. For a user-defined function that is its declared
    /// parameter count, which the arrow type cannot reveal - a
    /// one-parameter function returning a lambda has a two-deep arrow.
    /// Builtins and foreigns have no parameter list, and for them the
    /// arrow depth *is* the truth: primitives are saturated operations
    /// and a foreign symbol has exactly its C arity. A signature-only
    /// entry (no definition seen) answers `None` and is left alone.
    fn representation_arity(fn_info: &FnInfo) -> Option<usize> {
        fn_info.param_count.or_else(|| {
            if fn_info.is_builtin || fn_info.foreign_symbol.is_some() {
                Some(arrow_depth(&fn_info.ty))
            } else {
                None
            }
        })
    }

    /// Report an application spine that supplies fewer arguments than
    /// its head's representation declares, returning whether it did -
    /// the caller poisons a flagged spine so the refusal is the one
    /// diagnostic. Runs once per spine, at the root.
    ///
    /// Resolution mirrors `check_var`: a local in scope shadows a
    /// top-level function or constructor and makes the head a function
    /// *value*, whose saturation is not statically knowable - a
    /// `Int -> Int -> Int` local may hold a two-parameter function or a
    /// one-parameter function returning a closure, and only the second
    /// survives stepwise application. That is exactly why bare
    /// references to multi-parameter functions are refused (see
    /// `check_var`): every value a local can legally hold is applicable
    /// one argument at a time.
    fn check_app_saturation(&mut self, expr: &Expr) -> bool {
        let mut found = 0usize;
        let mut current = expr;
        while let Expr::EApp(func, _) = current {
            found += 1;
            current = func;
        }
        let (name, module, _span) = match current {
            Expr::EVar(ident) => {
                if self.is_frame_local(ident) {
                    return false;
                }
                // An ambiguous head is `check_var`'s report (it fires
                // in head position too); there is no arity to measure
                // against until the name means one thing.
                if self.ambiguous_modules(&ident.name).is_some() {
                    return false;
                }
                (ident.name.clone(), None, ident.span)
            }
            Expr::EQualified(path, ident) => {
                let m: String = path
                    .iter()
                    .map(|i| i.name.as_str())
                    .collect::<Vec<_>>()
                    .join(".");
                (ident.name.clone(), Some(m), ident.span)
            }
            _ => return false,
        };

        // Resolution takes the LAST matching entry, not the first:
        // imports are merged ahead of the entry file's own declarations,
        // and the checker's scope-based resolution gives later
        // declarations precedence - so an entry-file `helper` shadows an
        // imported one, and this lookup must agree with the typing it
        // rides along with or it flags calls the checker itself accepts.
        // (Which *symbol* codegen then calls for a cross-import
        // collision is a separate, older question - see B4 - but the
        // diagnostic must at minimum be consistent with the type
        // checker.)
        let head_fn = self
            .functions
            .iter()
            .rev()
            .find(|f| {
                f.name == name
                    && match &module {
                        Some(m) => f.module.as_deref() == Some(m.as_str()),
                        None => true,
                    }
            })
            .map(|f| {
                let sig_only = f.module.is_some()
                    && f.param_count.is_none()
                    && !f.is_builtin
                    && f.foreign_symbol.is_none();
                (sig_only, Self::representation_arity(f))
            });
        // Calling an imported signature whose definition stayed
        // private: nothing exists to run. Reported here, at the call,
        // because the exporting module is internally fine and an
        // unused import of it is harmless.
        if let Some((true, _)) = head_fn {
            self.errors.push(SemError::MissingDefinition {
                name,
                span: expr.span(),
            });
            return true;
        }
        let fn_arity = head_fn.and_then(|(_, a)| a);
        if let Some(expected) = fn_arity {
            if found < expected {
                self.errors.push(SemError::PartialApplication {
                    name,
                    expected,
                    found,
                    span: expr.span(),
                });
                return true;
            }
            return false;
        }

        let con_arity = self
            .data_types
            .iter()
            .filter(|dt| match &module {
                Some(m) => dt.module.as_deref() == Some(m.as_str()),
                None => true,
            })
            .flat_map(|dt| dt.constructors.iter())
            .rfind(|c| c.name == name)
            .map(|c| arrow_depth(&c.ty));
        if let Some(expected) = con_arity {
            if found < expected {
                self.errors.push(SemError::ConstructorArity {
                    name,
                    expected,
                    found,
                    span: expr.span(),
                });
                return true;
            }
        }
        false
    }

    /// Whether `ident` names a binding local to the function currently
    /// being checked - a parameter or `let`/pattern binding inside an
    /// active scope frame. Module-level signatures also park entries in
    /// `scope`, but those sit *below* the first `__scope__` frame
    /// marker; a name is only a genuine shadow of a top-level function
    /// or constructor if a frame introduced it.
    fn is_frame_local(&self, ident: &Ident) -> bool {
        let Some(first_frame) = self.scope.iter().position(|(n, _, _)| n == "__scope__") else {
            return false;
        };
        self.scope[first_frame..]
            .iter()
            .any(|(n, s, _)| n == &ident.name && *s == ident.scope)
    }

    /// The modules a bare name would be ambiguous between: two or more
    /// imported definitions with no entry-file definition to win.
    /// `None` when the name is unambiguous (entry-defined, uniquely
    /// defined, or not defined at all).
    fn ambiguous_modules(&self, name: &str) -> Option<Vec<String>> {
        let of = |map: &std::collections::HashMap<String, Vec<Option<String>>>| {
            map.get(name).and_then(|mods| {
                if mods.len() >= 2 && mods.iter().all(|m| m.is_some()) {
                    Some(mods.iter().flatten().cloned().collect::<Vec<String>>())
                } else {
                    None
                }
            })
        };
        of(&self.fn_defining_modules).or_else(|| of(&self.ctor_defining_modules))
    }

    fn check_var(&mut self, ident: &Ident) -> TypeId {
        // A bare name defined by two or more imported modules and not
        // by the entry file has no principled winner - and the stages
        // downstream of this one would not all pick the same one.
        // Refused in every position, head or value; `Mod::name` picks
        // explicitly.
        if !self.is_frame_local(ident) {
            if let Some(modules) = self.ambiguous_modules(&ident.name) {
                self.errors.push(SemError::AmbiguousName {
                    name: ident.name.clone(),
                    modules,
                    span: ident.span,
                });
                return TypeId::TError;
            }
        }

        // A bare reference to a multi-parameter function, outside head
        // position, builds a value that can only ever be applied one
        // argument at a time - and a call site has no way to supply a
        // multi-parameter function's arguments piecemeal, so every use
        // of that value would be the partial-application miscompile
        // with extra steps. One-parameter functions are the working
        // function-value representation and stay allowed; nullary
        // functions are named constants. A frame-local binding shadows
        // the top-level name and is exempt - it holds a value, and
        // values are applied indirectly.
        let flagged = if !self.in_app_head && !self.is_frame_local(ident) {
            // Last match, not first: the entry file's declarations are
            // merged after imports and shadow them - see
            // `check_app_saturation`.
            self.functions
                .iter()
                .rev()
                .find(|f| f.name == ident.name)
                .and_then(Self::representation_arity)
                .filter(|&a| a >= 2)
                .map(|a| (a, false))
                .or_else(|| {
                    // A bare fieldful constructor has no value
                    // representation at all - it lowered to an
                    // undefined SSA name the toolchain rejected.
                    self.data_types
                        .iter()
                        .flat_map(|dt| dt.constructors.iter())
                        .rfind(|c| c.name == ident.name)
                        .map(|c| arrow_depth(&c.ty))
                        .filter(|&a| a >= 1)
                        .map(|a| (a, true))
                })
        } else {
            None
        };
        if let Some((expected, is_con)) = flagged {
            let err = if is_con {
                SemError::ConstructorArity {
                    name: ident.name.clone(),
                    expected,
                    found: 0,
                    span: ident.span,
                }
            } else {
                SemError::PartialApplication {
                    name: ident.name.clone(),
                    expected,
                    found: 0,
                    span: ident.span,
                }
            };
            self.errors.push(err);
            return TypeId::TError;
        }

        for (name, scope, info) in self.scope.iter().rev() {
            if name == &ident.name && *scope == ident.scope {
                return info.ty.clone();
            }
        }

        // Entry-file definition first, then the (unique, after the
        // ambiguity check above) imported one. A plain first-match here
        // returned the *import's* type for an entry-shadowed name while
        // codegen called the entry's symbol - the checker and the
        // binary disagreeing about which function a name means.
        let resolved = self
            .functions
            .iter()
            .find(|f| f.name == ident.name && f.module.is_none())
            .or_else(|| self.functions.iter().find(|f| f.name == ident.name))
            .map(|f| {
                // An import can deliver a `pub` signature whose
                // definition stayed private: the name resolves, and
                // nothing exists to run. The entry file's own
                // signature-only case is reported once, at the
                // signature (see `check_entry_signatures`).
                let sig_only = f.module.is_some()
                    && f.param_count.is_none()
                    && !f.is_builtin
                    && f.foreign_symbol.is_none();
                (sig_only, f.ty.clone())
            });
        if let Some((sig_only, ty)) = resolved {
            if sig_only {
                self.errors.push(SemError::MissingDefinition {
                    name: ident.name.clone(),
                    span: ident.span,
                });
                return TypeId::TError;
            }
            return ty;
        }

        let resolved_con = self
            .data_types
            .iter()
            .filter(|dt| dt.module.is_none())
            .flat_map(|dt| dt.constructors.iter())
            .find(|con| con.name == ident.name)
            .or_else(|| {
                self.data_types
                    .iter()
                    .flat_map(|dt| dt.constructors.iter())
                    .find(|con| con.name == ident.name)
            });
        if let Some(con) = resolved_con {
            return con.ty.clone();
        }

        let suggestion = suggest_closest(
            &ident.name,
            self.scope
                .iter()
                .map(|(n, _, _)| n.as_str())
                .chain(self.functions.iter().map(|f| f.name.as_str()))
                .chain(
                    self.data_types
                        .iter()
                        .flat_map(|dt| dt.constructors.iter().map(|c| c.name.as_str())),
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

    fn check_qualified_var(&mut self, path: &[Ident], name: &Ident) -> TypeId {
        let module: String = path
            .iter()
            .map(|i| i.name.as_str())
            .collect::<Vec<_>>()
            .join(".");

        // Same value-position rules as `check_var`: a qualified name is
        // never a local, so no frame-local exemption applies - only the
        // multi-parameter-function check and the bare fieldful
        // constructor check.
        if !self.in_app_head {
            let flagged = self
                .functions
                .iter()
                .rev()
                .find(|f| f.name == name.name && f.module.as_deref() == Some(&module))
                .and_then(Self::representation_arity)
                .filter(|&a| a >= 2);
            if let Some(expected) = flagged {
                self.errors.push(SemError::PartialApplication {
                    name: format!("{}::{}", module, name.name),
                    expected,
                    found: 0,
                    span: name.span,
                });
                return TypeId::TError;
            }
            let con_flagged = self
                .data_types
                .iter()
                .filter(|dt| dt.module.as_deref() == Some(&module))
                .flat_map(|dt| dt.constructors.iter())
                .rfind(|c| c.name == name.name)
                .map(|c| arrow_depth(&c.ty))
                .filter(|&a| a >= 1);
            if let Some(expected) = con_flagged {
                self.errors.push(SemError::ConstructorArity {
                    name: format!("{}::{}", module, name.name),
                    expected,
                    found: 0,
                    span: name.span,
                });
                return TypeId::TError;
            }
        }

        for fn_info in &self.functions {
            if fn_info.name == name.name && fn_info.module.as_deref() == Some(&module) {
                return fn_info.ty.clone();
            }
        }

        for data_type in &self.data_types {
            if data_type.module.as_deref() == Some(&module) {
                for con in &data_type.constructors {
                    if con.name == name.name {
                        return con.ty.clone();
                    }
                }
            }
        }

        let dotted = format!("{}::{}", module, name.name);
        let suggestion = suggest_closest(
            &name.name,
            self.functions
                .iter()
                .filter(|f| f.module.as_deref() == Some(&module))
                .map(|f| f.name.as_str())
                .chain(
                    self.data_types
                        .iter()
                        .filter(|dt| dt.module.as_deref() == Some(&module))
                        .flat_map(|dt| dt.constructors.iter().map(|c| c.name.as_str())),
                ),
        );

        self.errors.push(SemError::UndefinedVariable {
            name: dotted,
            span: name.span,
            suggestion,
        });

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

    /// Find the data type and constructor (if any) named `name`.
    fn find_constructor(&self, name: &str) -> Option<(&DataTypeInfo, &DataConInfo)> {
        for dt in &self.data_types {
            for con in &dt.constructors {
                if con.name == name {
                    return Some((dt, con));
                }
            }
        }
        None
    }

    /// Search all known struct types for a field with the
    /// given name, returning the first match's `(struct_name, field_index, field_type)`.
    /// Used by the IR generator for field access when the base
    /// expression's type can't be re-queried (e.g. inside `gen_expr_to_func_with_allocas`).
    /// Type a saturated arithmetic or comparison builtin, over `Int` or
    /// `Float`.
    ///
    /// Both operands must agree: mixing the two is an error rather than
    /// an implicit widening, because a silent `Int`-to-`Float`
    /// conversion is how precision is lost without anything in the
    /// source saying so. `(cast Float n)` is the explicit form.
    fn check_numeric_builtin(&mut self, op: &str, lhs: &Expr, rhs: &Expr) -> TypeId {
        let lt = self.check_expr(lhs);
        let rt = self.check_expr(rhs);
        let comparison = matches!(op, "==" | "!=" | "<" | ">" | "<=" | ">=");
        let bool_ty = TypeId::TCon("Bool".to_string(), vec![]);
        let float_ty = TypeId::TCon("Float".to_string(), vec![]);
        let int_ty = TypeId::TCon("Int".to_string(), vec![]);

        // A poisoned operand has already been reported; propagate rather
        // than add a second diagnostic for the same root cause.
        if lt.is_error() || rt.is_error() {
            return if comparison { bool_ty } else { TypeId::TError };
        }

        let l_float = is_float_ty(&lt);
        let r_float = is_float_ty(&rt);

        if l_float || r_float {
            // Whichever side is not a `Float` is the one to point at -
            // but `compatible_with`, not `is_float_ty`, so an
            // as-yet-unconstrained type variable is allowed to be one.
            // A lambda parameter has no declared type, so
            // `(lambda (x) (* x 2.0))` presents `x` as a fresh variable;
            // rejecting that would make floats unusable in exactly the
            // higher-order code they are most wanted in. A concrete
            // `Int` is still rejected.
            for (ty, operand, is_float) in [(&lt, lhs, l_float), (&rt, rhs, r_float)] {
                if !is_float && !ty.compatible_with(&float_ty) {
                    self.errors.push(SemError::TypeMismatch {
                        expected: "Float".to_string(),
                        found: format!("{}", ty),
                        span: operand.span(),
                    });
                }
            }
            return if comparison { bool_ty } else { float_ty };
        }

        // The `Int` path, matching what the ordinary application rule
        // did when these were plain `Int -> Int -> Int` builtins.
        for (ty, operand) in [(&lt, lhs), (&rt, rhs)] {
            if !ty.compatible_with(&int_ty) {
                self.errors.push(SemError::TypeMismatch {
                    expected: "Int".to_string(),
                    found: format!("{}", ty),
                    span: operand.span(),
                });
            }
        }
        if comparison {
            bool_ty
        } else {
            int_ty
        }
    }

    pub fn find_struct_field_by_name(&self, field_name: &str) -> Option<(String, usize, TypeId)> {
        for si in &self.structs {
            for (idx, (fname, fty)) in si.fields.iter().enumerate() {
                if fname == field_name {
                    return Some((si.name.clone(), idx, fty.clone()));
                }
            }
        }
        None
    }

    pub fn find_data_field_by_name(&self, field_name: &str) -> Option<(String, usize, TypeId)> {
        for dt in &self.data_types {
            for con in &dt.constructors {
                if let Some(field_names) = &con.field_names {
                    for (idx, fnm) in field_names.iter().enumerate() {
                        if fnm == field_name {
                            let field_types = Self::constructor_field_types(&con.ty);
                            let fty = field_types
                                .get(idx)
                                .cloned()
                                .unwrap_or(TypeId::TCon("I64".to_string(), vec![]));
                            return Some((dt.name.clone(), idx, fty));
                        }
                    }
                }
            }
        }
        None
    }

    /// Decompose a constructor's curried arrow type (`F1 -> F2 -> ... ->
    /// TheType`) into its individual field types, in order. Empty for a
    /// nullary constructor (whose `ty` is just `TCon(TheType, ..)` with no
    /// `TArr` at all).
    fn constructor_field_types(con_ty: &TypeId) -> Vec<TypeId> {
        let mut fields = Vec::new();
        let mut current = con_ty;
        while let TypeId::TArr(param, rest) = current {
            fields.push((**param).clone());
            current = rest;
        }
        fields
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
    ///   variable - so `(match v ((Just x) (+ x 1)))` gives `x` the real
    ///   field type instead of a fresh, meaningless `TVar`. If `ty` is
    ///   already known concretely and doesn't name the constructor's own
    ///   data type, that's also a [`SemError::TypeMismatch`] (matching a
    ///   `Maybe` constructor against a scrutinee already known to be some
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
        self.check_pattern_with_type_mut(pat, ty, false)
    }

    /// Bind `pat`'s variables at type `ty`, marking them `mutable`.
    ///
    /// Only the top-level variable of a `let` binding can be `mut`;
    /// nested pattern variables are bound immutably, since `(mut (Just
    /// x) e)` would be claiming a field is assignable when `set` can
    /// only reach a whole local.
    fn check_pattern_with_type_mut(&mut self, pat: &Pattern, ty: &TypeId, mutable: bool) {
        match pat {
            Pattern::PVar(ident) => {
                self.scope.push((
                    ident.name.clone(),
                    ident.scope,
                    VarInfo {
                        ty: ty.clone(),
                        span: ident.span,
                        mutable,
                    },
                ));
            }
            Pattern::PCon(ident, args) => {
                let found = self
                    .find_constructor(&ident.name)
                    .map(|(dt, con)| (dt.name.clone(), con.ty.clone()));
                match found {
                    Some((_data_type_name, con_ty)) => {
                        let field_types = Self::constructor_field_types(&con_ty);
                        if field_types.len() != args.len() {
                            self.errors.push(SemError::ConstructorArity {
                                name: ident.name.clone(),
                                span: ident.span,
                                expected: field_types.len(),
                                found: args.len(),
                            });
                        }
                        for (i, arg) in args.iter().enumerate() {
                            if let Some(ft) = field_types.get(i) {
                                self.check_pattern_with_type(arg, ft);
                            } else {
                                self.check_pattern(arg);
                            }
                        }
                    }
                    None => {
                        let suggestion = suggest_closest(
                            &ident.name,
                            self.data_types
                                .iter()
                                .flat_map(|dt| dt.constructors.iter().map(|c| c.name.as_str())),
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
            Pattern::PConNamed(ident, named_args) => {
                let found = self
                    .find_constructor(&ident.name)
                    .map(|(dt, con)| (dt.name.clone(), con.ty.clone(), con.field_names.clone()));
                match found {
                    Some((data_type_name, con_ty, Some(field_names))) => {
                        let field_types = Self::constructor_field_types(&con_ty);
                        for (fname, fpat) in named_args {
                            if let Some(idx) = field_names.iter().position(|n| n == &fname.name) {
                                if idx < field_types.len() {
                                    self.check_pattern_with_type(fpat, &field_types[idx]);
                                } else {
                                    self.errors.push(SemError::FieldNotFound {
                                        field: fname.name.clone(),
                                        ty: data_type_name.clone(),
                                        span: fname.span,
                                    });
                                    self.check_pattern(fpat);
                                }
                            } else {
                                self.errors.push(SemError::FieldNotFound {
                                    field: fname.name.clone(),
                                    ty: data_type_name.clone(),
                                    span: fname.span,
                                });
                                self.check_pattern(fpat);
                            }
                        }
                    }
                    Some((data_type_name, _, None)) => {
                        self.errors.push(SemError::UndefinedConstructor {
                            name: ident.name.clone(),
                            span: ident.span,
                            suggestion: Some(format!(
                                "constructor `{}` of type `{}` has no named fields",
                                ident.name, data_type_name
                            )),
                        });
                        for (_, fpat) in named_args {
                            self.check_pattern(fpat);
                        }
                    }
                    _ => {
                        self.errors.push(SemError::UndefinedConstructor {
                            name: ident.name.clone(),
                            span: ident.span,
                            suggestion: None,
                        });
                        for (_, fpat) in named_args {
                            self.check_pattern(fpat);
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
            Type::TLinear(inner) => {
                TypeId::TCon("Linear".to_string(), vec![self.type_to_id(inner)])
            }
        }
    }

    /// The innermost binding of `name` visible at `scope`, if any.
    ///
    /// Matches `check_var`'s rule: name *and* scope must agree, so a
    /// macro-introduced binding does not capture a user's name of the
    /// same spelling.
    fn lookup_var(&self, name: &str, scope: usize) -> Option<&VarInfo> {
        self.scope
            .iter()
            .rev()
            .find(|(n, s, _)| n == name && *s == scope)
            .map(|(_, _, info)| info)
    }

    fn push_scope(&mut self) {
        self.scope.push((
            "__scope__".to_string(),
            0,
            VarInfo {
                ty: TypeId::TTuple(vec![]),
                span: Span::dummy(),
                mutable: false,
            },
        ));
    }

    fn pop_scope(&mut self) {
        while let Some((name, _, _)) = self.scope.pop() {
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
            Decl::DData {
                name,
                tyvars,
                constructors,
                module_path,
                ..
            } => {
                self.data_types.push(self.build_data_type_info(
                    name,
                    tyvars,
                    constructors,
                    module_path.clone(),
                ));
            }
            Decl::DSig {
                name,
                ty,
                module_path,
                ..
            } => {
                let ty_id = self.type_to_id(ty);
                let mut info = FnInfo::new(name.name.clone(), ty_id.clone());
                info.module = module_path.clone();
                self.functions.push(info);
                self.scope.push((
                    name.name.clone(),
                    name.scope,
                    VarInfo {
                        ty: ty_id,
                        span: name.span,
                        mutable: false,
                    },
                ));
            }
            Decl::DFn {
                name,
                params,
                body,
                module_path,
                ..
            } => {
                if !self
                    .functions
                    .iter()
                    .any(|f| f.name == name.name && f.module == *module_path)
                {
                    let mut info = FnInfo::new(
                        name.name.clone(),
                        TypeId::TVar(format!("_fn_{}", self.type_counter)),
                    );
                    info.module = module_path.clone();
                    self.functions.push(info);
                    self.type_counter += 1;
                }
                // Recorded here as well as in the collection pass: the
                // entry the name resolves to may have been created by
                // either pass (or by the signature), and the parameter
                // count must be present before any body that calls this
                // function is checked.
                if let Some(f) = self
                    .functions
                    .iter_mut()
                    .find(|f| f.name == name.name && f.module == *module_path)
                {
                    f.param_count = Some(params.len());
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
                fields,
                module_path,
                ..
            } => {
                let struct_fields: Vec<(String, TypeId)> = fields
                    .iter()
                    .map(|f| (f.name.name.clone(), self.type_to_id(&f.ty)))
                    .collect();
                self.structs.push(StructInfo {
                    name: name.name.clone(),
                    fields: struct_fields,
                    module: module_path.clone(),
                });
            }
            Decl::DForeign {
                name,
                ty,
                source,
                module_path,
                ..
            } => {
                let mut info = FnInfo::new(name.name.clone(), self.type_to_id(ty));
                info.foreign_symbol = Some(source.clone());
                info.module = module_path.clone();
                self.functions.push(info);
            }
            Decl::DType {
                name,
                tyvars,
                alias,
                module_path,
                ..
            } => {
                self.aliases.push(TypeAliasInfo {
                    name: name.name.clone(),
                    tyvars: tyvars.clone(),
                    target: self.type_to_id(alias),
                    module: module_path.clone(),
                });
            }
            _ => {}
        }
    }

    pub fn lookup_type(&self, name: &str) -> Option<TypeId> {
        for (n, _, info) in self.scope.iter().rev() {
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

/// Whether `ty` is a floating-point type.
pub fn is_float_ty(ty: &TypeId) -> bool {
    matches!(ty, TypeId::TCon(name, _) if matches!(name.as_str(), "Float" | "Double" | "F32" | "F64"))
}

/// Arithmetic and comparison operators that work over `Int` and `Float`
/// alike.
///
/// The bitwise and shift operators (`&`, `|`, `^`, `<<`, `>>`) and `%`
/// are deliberately absent: they have no floating-point meaning, and
/// leaving them `Int`-only keeps a float operand an error rather than a
/// silent reinterpretation of the bits.
pub const NUMERIC_BUILTINS: &[&str] = &["+", "-", "*", "/", "==", "!=", "<", ">", "<=", ">="];

/// Match a saturated application of a numeric builtin, returning the
/// operator and its two operands.
///
/// Application is curried, so `(+ a b)` is `EApp(EApp(EVar("+"), a), b)`
/// and this matches at the outer node.
pub fn numeric_builtin_app(expr: &Expr) -> Option<(&str, &Expr, &Expr)> {
    let Expr::EApp(outer, rhs) = expr else {
        return None;
    };
    let Expr::EApp(callee, lhs) = outer.as_ref() else {
        return None;
    };
    let Expr::EVar(ident) = callee.as_ref() else {
        return None;
    };
    NUMERIC_BUILTINS
        .contains(&ident.name.as_str())
        .then(|| (ident.name.as_str(), lhs.as_ref(), rhs.as_ref()))
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

    /// Type-check `source` and return the diagnostics that did *not*
    /// fail it.
    ///
    /// An AXTAG mismatch is documented as a warning - `AX3010` renders
    /// as `W` - so it must not abort compilation. The four tests below
    /// used `check_err`, which asserted the opposite, and two of them
    /// said `warns` in their own names while requiring a failure.
    fn check_warnings(source: &str) -> Vec<SemError> {
        let mut lexer = Lexer::new(source, 0);
        let tokens = lexer.tokenize().expect("lex failed");
        let module = Parser::new(tokens).parse_module().expect("parse failed");
        let mut tc = TypeChecker::new();
        tc.check(&module)
            .expect("a warning must not fail type-checking");
        std::mem::take(&mut tc.warnings)
    }

    #[test]
    fn every_primitive_is_in_scope_with_its_declared_arity() {
        // The primitives are what let the standard library exist
        // without C bindings; a missing one is an `undefined variable`
        // at the bottom of the stdlib, and a wrong arity is a type
        // error that only shows up in whichever module happens to use
        // it. Driving this from the same table the IR lowering reads
        // keeps the two in step.
        let tc = TypeChecker::new();
        for (name, arity, _) in PRIMITIVES {
            let info = tc
                .functions
                .iter()
                .find(|f| &f.name == name)
                .unwrap_or_else(|| panic!("primitive `{}` is not in scope", name));
            let mut count = 0;
            let mut ty = &info.ty;
            while let TypeId::TArr(_, rest) = ty {
                count += 1;
                ty = rest;
            }
            assert_eq!(count, *arity, "primitive `{}` arity", name);
            assert!(info.is_builtin, "primitive `{}` is not a builtin", name);
        }
        assert!(tc.functions.iter().any(|f| f.name == PRIM_ADDR));
    }

    #[test]
    fn a_syscall_is_an_io_effect_without_any_foreign_binding() {
        // Before the primitives existed, the only way to be effectful
        // was to call a `foreign` function, so an `effect(io)` claim on
        // a syscall-only body would have been rejected as unsupported.
        assert!(check(
            "(:: w (-> Int Int))\n\
             ;@axiom:effect(io)\n\
             (fn (w fd) (__syscall3 1 fd 0 0))\n\
             (:: main Int)\n\
             (fn (main) 0)"
        )
        .is_ok());
    }

    #[test]
    fn a_pure_claim_warns_when_the_body_reaches_a_syscall_indirectly() {
        // Effects propagate through calls: `outer` performs I/O even
        // though the syscall is two levels down. Without transitive
        // inference this program type-checked, which made every
        // `pure` claim above the standard library meaningless.
        let errors = check_warnings(
            "(:: inner (-> Int Int))\n\
             (fn (inner fd) (__syscall3 1 fd 0 0))\n\
             (:: middle (-> Int Int))\n\
             (fn (middle fd) (inner fd))\n\
             (:: outer (-> Int Int))\n\
             ;@axiom:pure\n\
             (fn (outer fd) (middle fd))\n\
             (:: main Int)\n\
             (fn (main) 0)",
        );
        assert!(
            errors
                .iter()
                .any(|e| matches!(e, SemError::AxtagMismatch { name, .. } if name == "outer")),
            "expected a pure-claim mismatch on `outer`, got {:?}",
            errors
        );
    }

    #[test]
    fn effect_inference_terminates_on_mutual_recursion() {
        // The fixpoint is bounded by the function count, but mutual
        // recursion is the case that would spin forever if the
        // iteration were not monotone.
        assert!(check(
            "(:: ping (-> Int Int))\n\
             (fn (ping n) (if (== n 0) 0 (pong (- n 1))))\n\
             (:: pong (-> Int Int))\n\
             (fn (pong n) (ping n))\n\
             (:: main Int)\n\
             (fn (main) (ping 3))"
        )
        .is_ok());
    }

    #[test]
    fn well_typed_arithmetic_program_checks_ok() {
        assert!(check("(:: main Int)\n(fn main (+ 1 (* 2 3)))").is_ok());
    }

    #[test]
    fn exhaustive_match_over_a_data_type_checks_ok() {
        assert!(check(
            "(data Maybe (a) (Nothing) (Just a))\n\
             (:: main Int)\n\
             (fn main (match (Just 1) ((Nothing) 0) ((Just x) x)))"
        )
        .is_ok());
    }

    /// Regression test: `SemError::NonExhaustive`/`AX3005` existed as a
    /// diagnostic long before anything actually constructed one - this is
    /// the first test that would catch that regressing again.
    #[test]
    fn non_exhaustive_match_over_a_data_type_is_an_error() {
        let errors = check_err(
            "(data Maybe (a) (Nothing) (Just a))\n\
             (:: main Int)\n\
             (fn main (match (Just 1) ((Just x) x)))",
        );
        assert!(errors.iter().any(|e| matches!(e, SemError::NonExhaustive { missing, .. } if missing == &["Nothing".to_string()])));
    }

    /// A wildcard arm makes any `match` exhaustive regardless of which
    /// constructors are explicitly covered.
    #[test]
    fn wildcard_arm_makes_match_exhaustive() {
        assert!(check(
            "(data Maybe (a) (Nothing) (Just a))\n\
             (:: main Int)\n\
             (fn main (match (Just 1) ((Nothing) 0) (_ 1)))"
        )
        .is_ok());
    }

    #[test]
    fn constructor_pattern_with_wrong_arity_is_an_error() {
        let errors = check_err(
            "(data Maybe (a) (Nothing) (Just a))\n\
             (:: main Int)\n\
             (fn main (match (Just 1) ((Nothing) 0) ((Just x y) x)))",
        );
        assert!(errors.iter().any(|e| matches!(e, SemError::ConstructorArity { name, expected: 1, found: 2, .. } if name == "Just")));
    }

    #[test]
    fn undefined_constructor_in_pattern_is_an_error_with_a_suggestion() {
        let errors = check_err(
            "(data Maybe (a) (Nothing) (Just a))\n\
             (:: main Int)\n\
             (fn main (match (Just 1) ((Nothign) 0) ((Just x) x)))",
        );
        assert!(errors.iter().any(|e| matches!(
            e,
            SemError::UndefinedConstructor { name, suggestion: Some(s), .. }
                if name == "Nothign" && s == "Nothing"
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
(fn main (if true 1 false))"#,
        );
        assert!(errors
            .iter()
            .any(|e| matches!(e, SemError::TypeMismatch { .. })));
    }

    /// `set` is what makes `mut` worth having: without a check, adding
    /// assignment would silently make every local mutable.
    #[test]
    fn set_on_a_mutable_binding_is_accepted() {
        check(
            r#"(:: main Int)
(fn main (let ((mut x 0)) { (set x 1) x }))"#,
        )
        .expect("`set` on a `mut` binding should type-check");
    }

    #[test]
    fn partial_application_of_a_top_level_function_is_an_error() {
        // Well-typed under currying, and exactly the program that used
        // to compile into an under-populated call reading register
        // garbage. The declared parameter count is the arity, so the
        // error must fire even though the arrow type would keep
        // peeling happily.
        let errors = check_err(
            r#"(:: add2 (-> Int Int Int))
(fn (add2 x y) (+ x y))
(:: main Int)
(fn main (let ((f (add2 1))) (f 2)))"#,
        );
        let err = errors
            .iter()
            .find(|e| {
                matches!(e, SemError::PartialApplication { name, expected: 2, found: 1, .. } if name == "add2")
            })
            .expect("expected PartialApplication");
        assert_eq!(err.to_diagnostic().code.unwrap().code, "AX3013");
    }

    #[test]
    fn a_bare_reference_to_a_multi_parameter_function_is_an_error() {
        // The value could only ever be applied one argument at a time,
        // and a two-parameter function cannot receive its arguments
        // piecemeal - every use would be the partial-application
        // miscompile with extra steps.
        let errors = check_err(
            r#"(:: add2 (-> Int Int Int))
(fn (add2 x y) (+ x y))
(:: main Int)
(fn main (let ((f add2)) (f 1 2)))"#,
        );
        assert!(errors.iter().any(|e| {
            matches!(e, SemError::PartialApplication { name, expected: 2, found: 0, .. } if name == "add2")
        }));
    }

    #[test]
    fn a_saturated_nested_spine_is_not_partial_application() {
        // (((add3 1) 2) 3) is one spine supplying all three arguments;
        // saturation is a property of the spine, not of any inner node,
        // and flagging an inner node was the easiest bug to write here.
        check(
            r#"(:: add3 (-> Int Int Int Int))
(fn (add3 x y z) (+ x (+ y z)))
(:: main Int)
(fn main (((add3 1) 2) 3))"#,
        )
        .expect("a saturated spine must type-check");
    }

    #[test]
    fn over_application_of_a_function_returning_a_closure_is_allowed() {
        // One declared parameter, applied to two arguments: the second
        // applies to the returned lambda. The declared parameter count
        // is what saturation is measured against - the arrow is two
        // deep, and using its depth here would wrongly flag this.
        check(
            r#"(:: adder (-> Int (-> Int Int)))
(fn (adder n) (lambda (m) (+ n m)))
(:: main Int)
(fn main (adder 10 5))"#,
        )
        .expect("over-application through a returned closure must type-check");
    }

    #[test]
    fn a_one_parameter_function_is_still_a_value() {
        // The one-word closure record and one-at-a-time application
        // work for exactly this case, and the standard tests use it;
        // the refusal must be scoped to what the backend cannot run.
        check(
            r#"(:: inc (-> Int Int))
(fn (inc n) (+ n 1))
(:: apply (-> (-> Int Int) Int Int))
(fn (apply f x) (f x))
(:: main Int)
(fn main (apply inc 41))"#,
        )
        .expect("a bare 1-param function value must type-check");
    }

    #[test]
    fn a_local_shadowing_a_function_name_is_exempt() {
        // `add2` here is a let-bound Int, not the function; the
        // signature parks top-level names in `scope` too, and the
        // shadow test must distinguish a frame-local from those.
        check(
            r#"(:: add2 (-> Int Int Int))
(fn (add2 x y) (+ x y))
(:: main Int)
(fn main (let ((add2 5)) add2))"#,
        )
        .expect("a frame-local shadowing a function name is an ordinary value");
    }

    #[test]
    fn an_under_applied_constructor_is_an_arity_error_in_expressions() {
        // AX3009 used to fire only in patterns; at expression sites an
        // under-applied constructor emitted a call to a symbol that
        // does not exist and failed in llc, as a toolchain error.
        let errors = check_err(
            r#"(data Pair (a) (MkPair Int Int))
(:: main Int)
(fn main (let ((p (MkPair 1))) 0))"#,
        );
        let err = errors
            .iter()
            .find(|e| {
                matches!(e, SemError::ConstructorArity { name, expected: 2, found: 1, .. } if name == "MkPair")
            })
            .expect("expected ConstructorArity");
        assert_eq!(err.to_diagnostic().code.unwrap().code, "AX3009");
    }

    #[test]
    fn a_bare_fieldful_constructor_reference_is_an_arity_error() {
        // `MkPair` alone lowered to a use of the undefined SSA value
        // `%MkPair`; a bare fieldful constructor has no value
        // representation at all.
        let errors = check_err(
            r#"(data Pair (a) (MkPair Int Int))
(:: main Int)
(fn main (let ((p MkPair)) 0))"#,
        );
        assert!(errors.iter().any(|e| {
            matches!(e, SemError::ConstructorArity { name, expected: 2, found: 0, .. } if name == "MkPair")
        }));
    }

    #[test]
    fn a_bare_nullary_constructor_is_still_a_construction() {
        check(
            r#"(data Flag (a) (On) (Off))
(:: main Int)
(fn main (let ((f On)) 0))"#,
        )
        .expect("a bare nullary constructor constructs");
    }

    #[test]
    fn an_entry_signature_without_a_definition_is_an_error() {
        // Calling one used to pass `check` and die in `opt` as
        // `use of undefined value '@ghost'` - a raw toolchain error
        // for a program the compiler had accepted. Reported at the
        // signature, called or not: the declaration is a promise the
        // file never keeps.
        let errors = check_err(
            r#"(:: ghost (-> Int Int Int))
(:: main Int)
(fn main 0)"#,
        );
        let err = errors
            .iter()
            .find(|e| matches!(e, SemError::MissingDefinition { name, .. } if name == "ghost"))
            .expect("expected MissingDefinition");
        assert_eq!(err.to_diagnostic().code.unwrap().code, "AX3015");
    }

    #[test]
    fn a_refused_spine_is_one_diagnostic_not_a_cascade() {
        // Without poisoning, the flagged inner spine typed as its
        // leftover arrow and fed `+` a second, consequent mismatch at
        // the same site. The refusal is the root cause and must be the
        // one report.
        let errors = check_err(
            r#"(:: add2 (-> Int Int Int))
(fn (add2 x y) (+ x y))
(:: main Int)
(fn main (+ 1 (add2 1)))"#,
        );
        assert_eq!(errors.len(), 1, "expected exactly one error: {:?}", errors);
        assert!(matches!(&errors[0], SemError::PartialApplication { .. }));
    }

    #[test]
    fn a_partially_applied_operator_is_an_error() {
        // `(+ 1)` used to fall through the numeric intercept and keep
        // its Int-flavoured typing on the theory that `map (+ 1)`
        // would want it someday; the backend has never been able to
        // run it, and a diagnostic beats an llc error.
        let errors = check_err(
            r#"(:: main Int)
(fn main (let ((f (+ 1))) 0))"#,
        );
        assert!(errors.iter().any(|e| {
            matches!(e, SemError::PartialApplication { name, expected: 2, found: 1, .. } if name == "+")
        }));
    }

    #[test]
    fn set_on_an_immutable_binding_is_an_error() {
        let errors = check_err(
            r#"(:: main Int)
(fn main (let ((x 0)) { (set x 1) x }))"#,
        );
        let err = errors
            .iter()
            .find(|e| matches!(e, SemError::AssignToImmutable { .. }))
            .expect("expected AssignToImmutable");
        assert_eq!(err.to_diagnostic().code.unwrap().code, "AX3012");
        // The report has to point at the declaration as well as the
        // assignment, because that is where the fix goes.
        match err {
            SemError::AssignToImmutable {
                span, decl_span, ..
            } => assert_ne!(span, decl_span, "declaration span was not recorded"),
            _ => unreachable!(),
        }
    }

    /// A function parameter is not a `let` binding and is not mutable.
    /// Nothing in the grammar lets one be marked `mut`, so this pins
    /// that the default really is immutable rather than merely unstated.
    #[test]
    fn set_on_a_function_parameter_is_an_error() {
        let errors = check_err(
            r#"(:: f (-> Int Int))
(fn (f n) { (set n 1) n })
(:: main Int)
(fn main (f 0))"#,
        );
        assert!(errors
            .iter()
            .any(|e| matches!(e, SemError::AssignToImmutable { .. })));
    }

    #[test]
    fn set_type_must_match_the_bindings_type() {
        let errors = check_err(
            r#"(:: main Int)
(fn main (let ((mut x 0)) { (set x true) x }))"#,
        );
        assert!(errors
            .iter()
            .any(|e| matches!(e, SemError::TypeMismatch { .. })));
    }

    #[test]
    fn while_requires_a_boolean_condition() {
        check(
            r#"(:: main Int)
(fn main (let ((mut i 0)) { (while (< i 3) (set i (+ i 1))) i }))"#,
        )
        .expect("a Bool condition should type-check");

        let errors = check_err(
            r#"(:: main Int)
(fn main (let ((mut i 0)) { (while i (set i 1)) i }))"#,
        );
        assert!(errors
            .iter()
            .any(|e| matches!(e, SemError::TypeMismatch { .. })));
    }

    /// The deliberate exception to the rule above, pinned so that it is
    /// a decision rather than a regression: a `String` is a `Str`
    /// handle - one machine word, the address of a `{ len, bytes }`
    /// header - so it is interchangeable with `Int`.
    ///
    /// This is what lets a string literal be stored in a `Vec`, used as
    /// a `Map` key, and read by the `Int`-typed accessors that
    /// implement `Str`, none of which would type-check under a nominal
    /// `String`.
    #[test]
    fn a_string_is_a_handle_and_so_is_compatible_with_int() {
        check(
            r#"(:: takesInt (-> Int Int))
(fn (takesInt n) n)
(:: main Int)
(fn main (takesInt "hi"))"#,
        )
        .expect("a String should be accepted where an Int is expected");

        check(
            r#"(:: takesStr (-> String Int))
(fn (takesStr s) 0)
(:: main Int)
(fn main (takesStr 0))"#,
        )
        .expect("an Int should be accepted where a String is expected");
    }

    #[test]
    fn struct_and_type_alias_declarations_are_tracked() {
        let mut lexer = Lexer::new(
            "(struct Point (x : Int) (y : Int))\n\
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
        assert_eq!(tc.structs[0].fields.len(), 2);
        assert_eq!(tc.aliases.len(), 1);
        assert_eq!(tc.aliases[0].name, "StringList");
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
        let errors = check_warnings(
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
        let errors = check_warnings(
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
    fn exhaustive_match_over_option_type_checks_ok() {
        assert!(check(
            r#"(:: main Int)
(fn main (match (Some 1) ((Some x) x) ((None) 0)))"#
        )
        .is_ok());
    }

    #[test]
    fn non_exhaustive_match_over_option_type_is_an_error() {
        let errors = check_err(
            r#"(:: main Int)
(fn main (match (Some 1) ((Some x) x)))"#,
        );
        assert!(errors.iter().any(|e| matches!(e, SemError::NonExhaustive { missing, .. } if missing == &["None".to_string()])));
    }

    #[test]
    fn wildcard_arm_makes_option_match_exhaustive() {
        assert!(check(
            r#"(:: main Int)
(fn main (match (Some 1) ((Some x) x) (_ 0)))"#
        )
        .is_ok());
    }

    #[test]
    fn some_constructor_with_wrong_arity_is_an_error() {
        let errors = check_err(
            r#"(:: main Int)
(fn main (match (Some 1) ((Some x y) x) ((None) 0)))"#,
        );
        assert!(errors.iter().any(|e| matches!(e, SemError::ConstructorArity { name, expected: 1, found: 2, .. } if name == "Some")));
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
    fn pure_tag_with_alloc_warns() {
        let errors = check_warnings(
            r#"(:: main Int)
;@axiom:pure
(fn main (alloc Int 1))"#,
        );
        assert!(errors
            .iter()
            .any(|e| matches!(e, SemError::AxtagMismatch { name, .. } if name == "main")));
    }

    #[test]
    fn effect_collects_alloc() {
        let source = r#"(:: main Int)
;@axiom:effect(alloc)
(fn main (alloc Int 1))"#;
        assert!(check(source).is_ok());
    }
}
