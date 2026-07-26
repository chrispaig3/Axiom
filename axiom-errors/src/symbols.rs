//! **AXSYM** (Axiom eXchange Symbol Line): the AXDL family's counterpart
//! for *successful* analysis, not failures.
//!
//! [`render::render_ai`] answers "what went wrong, and where, and how do I
//! fix it" in one dense line per diagnostic. AXSYM answers the equally
//! common agent question that AXDL has nothing to say about: "what does
//! this codebase actually export, and what is its type?" - without an
//! agent needing to re-read every source file and re-derive signatures by
//! eye, or (worse) shell out to `axiom repl` and paste `:type` queries one
//! at a time.
//!
//! Same design rationale as AXDL (see `docs/diagnostics.md`), reused
//! deliberately rather than reinvented:
//!
//! * one line per fact, so `grep -c '^F '` counts functions and
//!   `grep '^T '` lists types, with no multi-line state machine;
//! * locations are `file:line:col` via the exact same [`crate::SourceMap`]
//!   and [`crate::render::fmt_span`] AXDL uses, so a single mental model
//!   (and a single parser) covers both notations;
//! * no re-rendered source, no color, no box-drawing;
//! * the type itself is the one field that must stay prose-like (it's
//!   Axiom's own curried arrow-type syntax, which is already maximally
//!   dense), quoted so it can never be confused with the fields around it.
use crate::render::fmt_span;
use crate::source_map::SourceMap;
use axiom_ast::span::Span;

/// What kind of top-level entity a [`SymbolFact`] describes. The one
/// ASCII letter is the notation's `KIND` field (see module docs) and is
/// deliberately disjoint from [`crate::Severity::sigil`]'s letters (`E`,
/// `W`, `N`, `H`) so a line's first letter alone never has to be
/// disambiguated by which command produced it.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum SymbolKind {
    /// A `define`/`fn` function binding.
    Fn,
    /// A `foreign` FFI binding.
    Foreign,
    /// A `data` algebraic data type (the type itself, not its constructors).
    Data,
    /// A single constructor of a `data` type, e.g. `Just` in `Maybe`.
    Ctor,
    /// A `struct` declaration.
    Struct,
    /// A `union` declaration.
    Union,
    /// A `type` alias.
    Alias,
    /// A `class` (type class) declaration.
    Class,
}

impl SymbolKind {
    /// The single-letter AXSYM kind tag.
    pub fn letter(self) -> &'static str {
        match self {
            SymbolKind::Fn => "F",
            SymbolKind::Foreign => "X",
            SymbolKind::Data => "D",
            SymbolKind::Ctor => "C",
            SymbolKind::Struct => "S",
            SymbolKind::Union => "U",
            SymbolKind::Alias => "A",
            SymbolKind::Class => "L",
        }
    }
}

/// One fact about one top-level name: what kind of thing it is, where it's
/// declared, and its type (already rendered as a string - the renderers
/// in this crate never re-derive types, only format ones the caller
/// already computed).
#[derive(Debug, Clone)]
pub struct SymbolFact {
    pub kind: SymbolKind,
    pub name: String,
    /// `None` for built-in operators (`+`, `==`, ...) that have no source
    /// span at all.
    pub span: Option<Span>,
    pub ty: String,
    /// Extra `#key=value` metadata, e.g. a data type's constructor list
    /// (`#ctors=Nothing,Just`) or a struct's field count (`#fields=2`).
    /// Kept as pre-formatted `key=value` strings (no `#` prefix - the
    /// renderer adds that) so callers don't need a second enum just to
    /// describe a handful of ad hoc annotations.
    pub meta: Vec<String>,
}

impl SymbolFact {
    pub fn new(kind: SymbolKind, name: impl Into<String>, span: Option<Span>, ty: impl Into<String>) -> Self {
        Self { kind, name: name.into(), span, ty: ty.into(), meta: Vec::new() }
    }

    pub fn with_meta(mut self, meta: impl Into<String>) -> Self {
        self.meta.push(meta.into());
        self
    }
}

/// Render a batch of [`SymbolFact`]s as AXSYM: one dense line per symbol.
///
/// Grammar: `<KIND> <NAME> <FILE>:<LOC> "<TYPE>" [#<meta>]*`
///
/// Facts with no span (built-in operators) print `-` in place of
/// `<FILE>:<LOC>` rather than a fabricated location, so a consumer can
/// distinguish "defined in this file" from "always in scope" without
/// guessing from the type alone.
pub fn render_symbols_ai(facts: &[SymbolFact], filename: &str, source: &str) -> String {
    let map = SourceMap::new(source);
    let mut out = String::new();
    for fact in facts {
        out.push_str(&render_symbol_line(fact, filename, source, &map));
        out.push('\n');
    }
    out
}

fn render_symbol_line(fact: &SymbolFact, filename: &str, source: &str, map: &SourceMap) -> String {
    use std::fmt::Write;
    let mut line = String::new();

    write!(line, "{}", fact.kind.letter()).ok();
    write!(line, " {}", fact.name).ok();
    match fact.span {
        Some(span) => {
            write!(line, " {}:{}", filename, fmt_span(map, source, span)).ok();
        }
        None => {
            write!(line, " -").ok();
        }
    }
    write!(line, " {:?}", fact.ty).ok();
    for m in &fact.meta {
        write!(line, " #{}", m).ok();
    }

    line
}
