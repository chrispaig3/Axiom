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
    /// A `fn` function binding.
    Fn,
    /// A `foreign` FFI binding.
    Foreign,
    /// A `data` algebraic data type (the type itself, not its constructors).
    Data,
    /// A single constructor of a `data` type, e.g. `Red` in `Color`.
    Ctor,
    /// A `struct` declaration.
    Struct,
    /// A `union` declaration.
    Union,
    /// A `type` alias.
    Alias,
    /// A `trait` declaration.
    Trait,
    /// An `effect` declaration.
    Effect,
    /// An `impl` declaration.
    Impl,
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
            SymbolKind::Trait => "T",
            SymbolKind::Effect => "V",
            SymbolKind::Impl => "I",
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
    pub span: Option<Span>,
    pub ty: String,
    pub nid: Option<String>,
    pub meta: Vec<String>,
}

impl SymbolFact {
    pub fn new(
        kind: SymbolKind,
        name: impl Into<String>,
        span: Option<Span>,
        ty: impl Into<String>,
        nid: Option<String>,
    ) -> Self {
        Self {
            kind,
            name: name.into(),
            span,
            ty: ty.into(),
            nid,
            meta: Vec::new(),
        }
    }

    pub fn with_nid(mut self, nid: impl Into<String>) -> Self {
        self.nid = Some(nid.into());
        self
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
    if let Some(nid) = &fact.nid {
        write!(line, " @{}", nid).ok();
    }
    for m in &fact.meta {
        write!(line, " #{}", m).ok();
    }

    line
}

#[cfg(test)]
mod tests {
    use super::*;
    use axiom_ast::span::Span;

    #[test]
    fn ai_fn_without_meta() {
        let fact = SymbolFact::new(
            SymbolKind::Fn,
            "add",
            Some(Span::new(5, 8, 0)),
            "(Int -> (Int -> Int))",
            None,
        );
        let out = render_symbols_ai(
            &[fact],
            "main.ax",
            "(:: add (-> Int Int Int))\n(fn (add x y) (+ x y))\n",
        );
        assert!(out.contains("F add main.ax:1:6-9 \"(Int -> (Int -> Int))\""));
    }

    #[test]
    fn ai_foreign_with_symbol_meta() {
        let fact = SymbolFact::new(
            SymbolKind::Foreign,
            "printf",
            Some(Span::new(10, 16, 0)),
            "(String -> Int)",
            None,
        )
        .with_meta("symbol=printf");
        let out = render_symbols_ai(&[fact], "main.ax", &" ".repeat(20));
        assert!(out.contains("X printf main.ax:1:11-17 \"(String -> Int)\" #symbol=printf"));
    }

    #[test]
    fn ai_data_with_ctors() {
        let fact = SymbolFact::new(
            SymbolKind::Data,
            "Color",
            Some(Span::new(7, 13, 0)),
            "struct Color",
            None,
        )
        .with_meta("ctors=Red,Green");
        let out = render_symbols_ai(&[fact], "main.ax", &" ".repeat(20));
        assert!(out.contains("D Color main.ax:1:8-14 \"struct Color\" #ctors=Red,Green"));
    }

    #[test]
    fn ai_constructor_with_of() {
        let fact = SymbolFact::new(
            SymbolKind::Ctor,
            "Red",
            Some(Span::new(17, 20, 0)),
            "(a -> Color a)",
            None,
        )
        .with_meta("of=Color");
        let out = render_symbols_ai(&[fact], "main.ax", &" ".repeat(22));
        assert!(out.contains("C Red main.ax:1:18-21 \"(a -> Color a)\" #of=Color"));
    }

    #[test]
    fn ai_struct_with_fields_and_repr() {
        let fact = SymbolFact::new(
            SymbolKind::Struct,
            "Point",
            Some(Span::new(9, 14, 0)),
            "struct Point",
            None,
        )
        .with_meta("fields=x:Int,y:Int")
        .with_meta("repr=C");
        let out = render_symbols_ai(&[fact], "main.ax", &" ".repeat(20));
        assert!(
            out.contains("S Point main.ax:1:10-15 \"struct Point\" #fields=x:Int,y:Int #repr=C")
        );
    }

    #[test]
    fn ai_union_with_fields() {
        let fact = SymbolFact::new(
            SymbolKind::Union,
            "Value",
            Some(Span::new(0, 5, 0)),
            "union Value",
            None,
        )
        .with_meta("fields=asInt:I64,asFloat:F64");
        let out = render_symbols_ai(&[fact], "main.ax", &" ".repeat(20));
        assert!(out.contains("U Value main.ax:1:1-6 \"union Value\" #fields=asInt:I64,asFloat:F64"));
    }

    #[test]
    fn ai_alias_with_tyvars() {
        let fact = SymbolFact::new(
            SymbolKind::Alias,
            "StringList",
            Some(Span::new(0, 10, 0)),
            "[String]",
            None,
        )
        .with_meta("tyvars=a,b");
        let out = render_symbols_ai(&[fact], "main.ax", &" ".repeat(20));
        assert!(out.contains("A StringList main.ax:1:1-11 \"[String]\" #tyvars=a,b"));
    }

    #[test]
    fn ai_alias_without_tyvars_has_no_meta() {
        let fact = SymbolFact::new(
            SymbolKind::Alias,
            "Int",
            Some(Span::new(0, 3, 0)),
            "Int",
            None,
        );
        let out = render_symbols_ai(&[fact], "main.ax", &" ".repeat(20));
        assert!(out.contains("A Int main.ax:1:1-4 \"Int\""));
        assert!(!out.contains('#'));
    }

    #[test]
    fn ai_trait_with_methods() {
        let fact = SymbolFact::new(
            SymbolKind::Trait,
            "Eq",
            Some(Span::new(9, 11, 0)),
            "trait Eq",
            None,
        )
        .with_meta("methods===:(a -> a -> Bool)");
        let out = render_symbols_ai(&[fact], "main.ax", &" ".repeat(20));
        assert!(out.contains("T Eq main.ax:1:10-12 \"trait Eq\" #methods===:(a -> a -> Bool)"));
    }

    #[test]
    fn ai_builtin_prints_dash() {
        let fact = SymbolFact::new(SymbolKind::Fn, "+", None, "(Int -> (Int -> Int))", None);
        let out = render_symbols_ai(&[fact], "main.ax", "");
        assert!(out.contains("F + - \"(Int -> (Int -> Int))\""));
    }

    #[test]
    fn ai_utf8_location() {
        let fact = SymbolFact::new(SymbolKind::Fn, "hé", Some(Span::new(0, 2, 0)), "Int", None);
        let out = render_symbols_ai(&[fact], "main.ax", "héllo");
        assert!(out.contains("F hé main.ax:1:1-3 \"Int\""));
    }

    #[test]
    fn ai_multiple_metadata_keys_order() {
        let fact = SymbolFact::new(
            SymbolKind::Struct,
            "S",
            Some(Span::new(0, 1, 0)),
            "struct S",
            None,
        )
        .with_meta("fields=a:Int")
        .with_meta("align=8")
        .with_meta("packed");
        let out = render_symbols_ai(&[fact], "main.ax", &" ".repeat(20));
        let line = out.trim_end();
        assert!(line.contains("#fields=a:Int"));
        assert!(line.contains("#align=8"));
        assert!(line.contains("#packed"));
    }

    #[test]
    fn ai_symbol_with_nid() {
        let fact = SymbolFact::new(
            SymbolKind::Fn,
            "add",
            Some(Span::new(5, 8, 0)),
            "(Int -> (Int -> Int))",
            Some("abcd1234".to_string()),
        );
        let out = render_symbols_ai(&[fact], "main.ax", &" ".repeat(20));
        assert!(out.contains("F add main.ax:1:6-9 \"(Int -> (Int -> Int))\" @abcd1234"));
    }

    #[test]
    fn ai_symbol_without_nid_has_no_at_sign() {
        let fact = SymbolFact::new(
            SymbolKind::Fn,
            "add",
            Some(Span::new(5, 8, 0)),
            "(Int -> (Int -> Int))",
            None,
        );
        let out = render_symbols_ai(&[fact], "main.ax", &" ".repeat(20));
        assert!(!out.contains('@'));
    }

    #[test]
    fn ai_symbol_with_axtag_metadata() {
        let fact = SymbolFact::new(
            SymbolKind::Fn,
            "read",
            Some(Span::new(0, 4, 0)),
            "(-> String)",
            None,
        )
        .with_meta("effect=io")
        .with_meta("pure");
        let out = render_symbols_ai(&[fact], "main.ax", &" ".repeat(20));
        let line = out.trim_end();
        assert!(line.contains("#effect=io"));
        assert!(line.contains("#pure"));
    }

    #[test]
    fn ai_kind_letters_disjoint_from_severity_sigils() {
        for kind in [
            SymbolKind::Fn,
            SymbolKind::Foreign,
            SymbolKind::Data,
            SymbolKind::Ctor,
            SymbolKind::Struct,
            SymbolKind::Union,
            SymbolKind::Alias,
            SymbolKind::Trait,
            SymbolKind::Effect,
            SymbolKind::Impl,
        ] {
            let letter = kind.letter();
            assert!(!matches!(letter, "E" | "W" | "N" | "H"));
        }
    }
}
