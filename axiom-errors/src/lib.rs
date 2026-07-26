//! Axiom's structured diagnostics engine.
//!
//! Every error/warning/note produced anywhere in the Axiom pipeline
//! (lexer, parser, semantic analysis, codegen, toolchain invocation) is
//! represented as a [`Diagnostic`] - a severity, a stable [`code::CodeInfo`],
//! a message, a primary span, and optional secondary spans/notes/help.
//!
//! From that single structured representation, this crate can render two
//! very different outputs:
//!
//! * [`render::render_human`] - a Rust-style report with quoted source,
//!   underlines, colors, and "help" footers, for people reading a terminal.
//! * [`render::render_ai`] - a dense, single-line-per-diagnostic notation
//!   (see `docs/diagnostics.md`) purpose-built to be cheap for an LLM to
//!   read: no re-rendered source text, no ANSI codes, no box-drawing, and
//!   stable machine-parseable fields.
//!
//! Having one model feed both renderers means the two output modes can
//! never disagree about *what* went wrong, only about how verbosely it's
//! presented.

pub mod code;
pub mod diagnostic;
pub mod render;
pub mod severity;
pub mod source_map;
pub mod symbols;

pub use code::{lookup, CodeInfo};
pub use diagnostic::{Diagnostic, Label, Suggestion};
pub use render::{dedup, json_escape, render_ai, render_human, render_json, DiagnosticFormat};
pub use severity::Severity;
pub use source_map::SourceMap;
pub use symbols::{render_symbols_ai, SymbolFact, SymbolKind};

/// Render a batch of diagnostics with cascade-deduplication already applied,
/// in the requested format. This is the one function most callers need.
pub fn render(diags: Vec<Diagnostic>, filename: &str, source: &str, format: DiagnosticFormat) -> String {
    let diags = dedup(diags);
    match format {
        DiagnosticFormat::Human => render_human(&diags, filename, source),
        DiagnosticFormat::Ai => render_ai(&diags, filename, source),
        DiagnosticFormat::Json => render_json(&diags, filename, source),
    }
}

/// Format the full `axiom explain <CODE>` output for a code, or `None` if
/// the code is unknown.
pub fn explain(code: &str) -> Option<String> {
    lookup(code).map(|info| {
        format!(
            "{} - {}\n\n{}\n",
            info.code, info.title, info.explain
        )
    })
}
