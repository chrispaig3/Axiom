use ariadne::{Color, Label as AriadneLabel, Report, Source};

use crate::diagnostic::Diagnostic;
use crate::severity::Severity;
use crate::source_map::SourceMap;

/// Which of Axiom's diagnostic renderers to use.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Default)]
pub enum DiagnosticFormat {
    /// Rust-style human-readable report with source snippets, underlines,
    /// and colors (via `ariadne`).
    #[default]
    Human,
    /// The AI-optimized notation described in `docs/diagnostics.md`: one
    /// dense, greppable, colorless line per diagnostic with no
    /// re-rendering of source text, designed to minimize tokens consumed
    /// by an LLM agent reading compiler output.
    Ai,
    /// Structured JSON, one object per line (JSON Lines), for tooling that
    /// wants to parse diagnostics programmatically without depending on
    /// either prose format.
    Json,
}

impl DiagnosticFormat {
    pub fn parse(s: &str) -> Option<Self> {
        match s.to_ascii_lowercase().as_str() {
            "human" | "pretty" | "rustc" => Some(Self::Human),
            "ai" | "agent" | "compact" => Some(Self::Ai),
            "json" => Some(Self::Json),
            _ => None,
        }
    }
}

/// Drop diagnostics that are cascading consequences of an earlier
/// diagnostic in the same group. Only the first diagnostic in each group
/// (and every diagnostic with no group at all) survives.
///
/// This directly fixes the "one undefined variable produces three error
/// reports" problem: semantic analysis tags derived errors with a group
/// key (see `axiom-sema`), and this is the single choke point where those
/// duplicates are trimmed before anything is printed, regardless of which
/// renderer is used.
pub fn dedup(diags: Vec<Diagnostic>) -> Vec<Diagnostic> {
    let mut seen_groups = std::collections::HashSet::new();
    let mut out = Vec::with_capacity(diags.len());
    for diag in diags {
        if let Some(group) = &diag.group {
            if !seen_groups.insert(group.clone()) {
                continue;
            }
        }
        out.push(diag);
    }
    out
}

/// Render diagnostics the way a human developer wants to read them:
/// colored, with the offending source line quoted and underlined, plus
/// notes and help text. Modeled closely on `rustc`/`ariadne` output.
pub fn render_human(diags: &[Diagnostic], filename: &str, source: &str) -> String {
    let mut out = String::new();

    for diag in diags {
        let primary_span = diag.primary_span();
        // Feed ariadne the *actual* byte offset of the primary span as the
        // report's anchor. Previously this was hardcoded to `0`, which is
        // why the `[file:L:C]` header always claimed line 1 no matter
        // where the real error was.
        let anchor = primary_span
            .map(|s| clamp_span(source, s.start, s.end).0)
            .unwrap_or(0);

        let code_tag = diag
            .code
            .map(|c| format!("[{}] ", c.code))
            .unwrap_or_default();
        let heading = format!("{}{}", code_tag, diag.message);

        let mut report = Report::build(diag.severity.ariadne_kind(), filename, anchor)
            .with_message(heading);

        if let Some(label) = &diag.primary {
            let (start, end) = clamp_span(source, label.span.start, label.span.end);
            let color = match diag.severity {
                Severity::Error => Color::Red,
                Severity::Warning => Color::Yellow,
                Severity::Note | Severity::Help => Color::Blue,
            };
            let text = if label.message.is_empty() {
                diag.message.clone()
            } else {
                label.message.clone()
            };
            report = report.with_label(
                AriadneLabel::new((filename, start..end))
                    .with_message(text)
                    .with_color(color)
                    .with_order(0),
            );
        }

        for (i, label) in diag.secondary.iter().enumerate() {
            let (start, end) = clamp_span(source, label.span.start, label.span.end);
            report = report.with_label(
                AriadneLabel::new((filename, start..end))
                    .with_message(label.message.clone())
                    .with_color(Color::Cyan)
                    .with_order((i + 1) as i32),
            );
        }

        for note in &diag.notes {
            report = report.with_note(note);
        }
        for help in &diag.helps {
            report = report.with_help(&help.message);
        }
        if let Some(code) = diag.code {
            report = report.with_help(format!(
                "run `axiom explain {}` for a full explanation",
                code.code
            ));
        }

        let mut buf = Vec::new();
        report
            .finish()
            .write((filename, Source::from(source)), &mut buf)
            .expect("ariadne report should render");
        out.push_str(&String::from_utf8_lossy(&buf));
    }

    out
}

/// Render diagnostics using Axiom's AI-optimized notation ("AXDL": Axiom
/// eXchange Diagnostic Line). See `docs/diagnostics.md` for the full
/// grammar and rationale. Key properties:
///
/// * exactly one primary line per diagnostic, so a tool (or a model) can
///   `grep -c '^E '` to count errors, or parse line-by-line with no
///   multi-line state machine;
/// * no re-rendered source snippet, no box-drawing characters, no ANSI
///   colors - the agent already has the file open, so repeating its
///   contents just burns tokens;
/// * the stable code AND a kebab-case slug are both included so the line
///   is greppable by either humans (`grep AX3001`) or semantic search
///   (`grep undefined-variable`);
/// * related spans, notes, and suggested fixes are appended as
///   sigil-prefixed fields on the *same* line rather than as extra lines,
///   so a single diagnostic is always exactly one line of output.
pub fn render_ai(diags: &[Diagnostic], filename: &str, source: &str) -> String {
    let map = SourceMap::new(source);
    let mut out = String::new();

    for diag in diags {
        out.push_str(&render_ai_line(diag, filename, source, &map));
        out.push('\n');
    }

    out
}

/// Clamp a `(start, end)` *character* range into valid, non-empty bounds
/// within `source`. Spans that land exactly at end-of-file (e.g.
/// "unexpected EOF" diagnostics) previously produced an empty,
/// out-of-bounds range that `ariadne` could not render a snippet for at
/// all - this keeps such diagnostics anchored to the last real character
/// instead of going blank.
///
/// `ariadne::Source` indexes by character (not byte), matching Axiom's own
/// spans (see [`SourceMap`]'s doc comment), so this clamps against a
/// character count rather than `source.len()` (byte length) - using the
/// byte length here would under-clamp for any source containing multi-byte
/// UTF-8 characters.
fn clamp_span(source: &str, start: usize, end: usize) -> (usize, usize) {
    let len = source.chars().count();
    if len == 0 {
        return (0, 1);
    }
    let start = start.min(len.saturating_sub(1));
    let end = end.max(start + 1).min(len).max(start + 1);
    (start, end)
}

/// Format a span as `line:col` or `line:col-col` or `line:col-line:col`.
/// Shared by every AXDL-family renderer (diagnostics *and* the AXSYM
/// symbol/type notation in [`crate::symbols`]) so every one of Axiom's
/// agent-facing notations addresses source locations identically.
pub fn fmt_span(map: &SourceMap, source: &str, span: axiom_ast::span::Span) -> String {
    let (start, end) = map.span_range(source, span.start, span.end.max(span.start));
    if start == end {
        format!("{}:{}", start.0, start.1)
    } else if start.0 == end.0 {
        format!("{}:{}-{}", start.0, start.1, end.1)
    } else {
        format!("{}:{}-{}:{}", start.0, start.1, end.0, end.1)
    }
}

fn render_ai_line(diag: &Diagnostic, filename: &str, source: &str, map: &SourceMap) -> String {
    use std::fmt::Write;
    let mut line = String::new();

    // <SEV> <CODE> <file>:<loc>
    write!(line, "{}", diag.severity.sigil()).ok();
    if let Some(code) = diag.code {
        write!(line, " {}", code.code).ok();
    }
    if let Some(span) = diag.primary_span() {
        write!(line, " {}:{}", filename, fmt_span(map, source, span)).ok();
    } else {
        write!(line, " {}:-", filename).ok();
    }

    // slug (stable, wording-independent identifier for the kind of error)
    if let Some(code) = diag.code {
        write!(line, " {}", code.slug).ok();
    }

    // quoted human message
    write!(line, " {:?}", diag.message).ok();

    // secondary/related spans: ^loc:"message"
    for label in &diag.secondary {
        write!(
            line,
            " ^{}:{:?}",
            fmt_span(map, source, label.span),
            label.message
        )
        .ok();
    }

    // notes: !"message"
    for note in &diag.notes {
        write!(line, " !{:?}", note).ok();
    }

    // help/suggestions: ?"message" or, when machine-applicable,
    // ?loc"message"~>"replacement"
    for help in &diag.helps {
        match (&help.span, &help.replacement) {
            (Some(span), Some(replacement)) => {
                write!(
                    line,
                    " ?{}:{:?}~>{:?}",
                    fmt_span(map, source, *span),
                    help.message,
                    replacement
                )
                .ok();
            }
            _ => {
                write!(line, " ?{:?}", help.message).ok();
            }
        }
    }

    line
}

/// Minimal JSON Lines renderer for tooling that prefers structured data
/// over either prose format. One JSON object per diagnostic, newline
/// separated (not a JSON array) so output can be streamed.
pub fn render_json(diags: &[Diagnostic], filename: &str, source: &str) -> String {
    let map = SourceMap::new(source);
    let mut out = String::new();
    for diag in diags {
        out.push_str(&json_line(diag, filename, source, &map));
        out.push('\n');
    }
    out
}

/// Escape a string for embedding in a JSON string literal (used by every
/// JSON Lines renderer in this crate, including [`crate::symbols`]'s).
pub fn json_escape(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    for c in s.chars() {
        match c {
            '"' => out.push_str("\\\""),
            '\\' => out.push_str("\\\\"),
            '\n' => out.push_str("\\n"),
            _ => out.push(c),
        }
    }
    out
}

fn json_span(map: &SourceMap, source: &str, span: axiom_ast::span::Span) -> String {
    let (start, end) = map.span_range(source, span.start, span.end.max(span.start));
    format!(
        // `char_start`/`char_end` (not byte offsets): Axiom spans are
        // character-index-based end to end, see `SourceMap`'s doc comment.
        "{{\"start\":{{\"line\":{},\"col\":{}}},\"end\":{{\"line\":{},\"col\":{}}},\"char_start\":{},\"char_end\":{}}}",
        start.0, start.1, end.0, end.1, span.start, span.end
    )
}

fn json_line(diag: &Diagnostic, filename: &str, source: &str, map: &SourceMap) -> String {
    let mut s = String::from("{");
    s.push_str(&format!("\"severity\":\"{}\",", diag.severity.label()));
    if let Some(code) = diag.code {
        s.push_str(&format!(
            "\"code\":\"{}\",\"slug\":\"{}\",",
            code.code, code.slug
        ));
    }
    s.push_str(&format!("\"message\":\"{}\",", json_escape(&diag.message)));
    s.push_str(&format!("\"file\":\"{}\",", json_escape(filename)));
    if let Some(label) = &diag.primary {
        s.push_str(&format!(
            "\"span\":{},\"label\":\"{}\",",
            json_span(map, source, label.span),
            json_escape(&label.message)
        ));
    }
    s.push_str("\"related\":[");
    for (i, label) in diag.secondary.iter().enumerate() {
        if i > 0 {
            s.push(',');
        }
        s.push_str(&format!(
            "{{\"span\":{},\"label\":\"{}\"}}",
            json_span(map, source, label.span),
            json_escape(&label.message)
        ));
    }
    s.push_str("],\"notes\":[");
    for (i, n) in diag.notes.iter().enumerate() {
        if i > 0 {
            s.push(',');
        }
        s.push_str(&format!("\"{}\"", json_escape(n)));
    }
    s.push_str("],\"help\":[");
    for (i, h) in diag.helps.iter().enumerate() {
        if i > 0 {
            s.push(',');
        }
        s.push_str(&format!("\"{}\"", json_escape(&h.message)));
    }
    s.push_str("]}");
    s
}
