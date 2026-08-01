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

        let mut report =
            Report::build(diag.severity.ariadne_kind(), filename, anchor).with_message(heading);

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

    // expansion backtrace: &"call site" per entry
    for entry in &diag.expansion_backtrace {
        write!(line, " &{:?}", entry).ok();
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

#[cfg(test)]
mod tests {
    use super::*;
    use crate::code::CodeInfo;
    use crate::diagnostic::Diagnostic;
    use crate::severity::Severity;
    use crate::source_map::SourceMap;
    use axiom_ast::span::Span;

    const DUMMY_CODE: CodeInfo = CodeInfo {
        code: "AX9999",
        slug: "test-code",
        title: "test title",
        explain: "test explain",
    };

    #[test]
    fn json_escape_quotes_and_backslashes_and_newlines() {
        assert_eq!(json_escape("hello"), "hello");
        assert_eq!(json_escape("he\"llo"), "he\\\"llo");
        assert_eq!(json_escape("he\\llo"), "he\\\\llo");
        assert_eq!(json_escape("he\nllo"), "he\\nllo");
    }

    #[test]
    fn fmt_span_zero_width_is_line_col() {
        let map = SourceMap::new("abc\ndef");
        let span = Span::new(0, 0, 0);
        assert_eq!(fmt_span(&map, "abc\ndef", span), "1:1");
    }

    #[test]
    fn fmt_span_same_line_range() {
        let map = SourceMap::new("hello");
        let span = Span::new(1, 3, 0);
        assert_eq!(fmt_span(&map, "hello", span), "1:2-4");
    }

    #[test]
    fn fmt_span_crosses_lines() {
        let map = SourceMap::new("ab\ncd\n");
        let span = Span::new(1, 4, 0);
        assert_eq!(fmt_span(&map, "ab\ncd\n", span), "1:2-2:2");
    }

    #[test]
    fn fmt_span_utf8() {
        let map = SourceMap::new("αβγδε");
        // character indices: α=0, β=1, γ=2, δ=3, ε=4
        let span = Span::new(1, 3, 0);
        assert_eq!(fmt_span(&map, "αβγδε", span), "1:2-4");
    }

    #[test]
    fn render_ai_line_basic_error() {
        let diag = Diagnostic::error(&DUMMY_CODE, "something broke")
            .with_primary(Span::new(0, 5, 0), "here is the problem");
        let out = render_ai(&[diag], "test.ax", "abcde fghij");
        let line = out.trim_end();
        assert!(line.starts_with("E AX9999 test.ax:1:1-6"));
        assert!(line.contains(" test-code"));
        assert!(line.contains(" \"something broke\""));
    }

    #[test]
    fn render_ai_is_exactly_one_line_per_diagnostic() {
        let diags = vec![
            Diagnostic::error(&DUMMY_CODE, "first").with_primary(Span::new(0, 1, 0), ""),
            Diagnostic::error(&DUMMY_CODE, "second").with_primary(Span::new(2, 3, 0), ""),
        ];
        let out = render_ai(&diags, "f.ax", "0123456789");
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 2);
        assert!(lines[0].contains(" \"first\""));
        assert!(lines[1].contains(" \"second\""));
    }

    #[test]
    fn render_ai_includes_slug_even_when_code_is_omitted() {
        let diag = Diagnostic::new(Severity::Warning, &DUMMY_CODE, "watch out")
            .with_primary(Span::new(0, 1, 0), "");
        let out = render_ai(&[diag], "f.ax", "01");
        assert!(out.contains("W AX9999 f.ax:1:1-2 test-code \"watch out\""));
    }

    #[test]
    fn render_ai_no_primary_span_uses_dash() {
        let diag = Diagnostic::new(Severity::Note, &DUMMY_CODE, "note here");
        let out = render_ai(&[diag], "f.ax", "");
        assert!(out.contains("N AX9999 f.ax:- test-code \"note here\""));
    }

    #[test]
    fn render_ai_secondary_spans() {
        let diag = Diagnostic::error(&DUMMY_CODE, "dup")
            .with_primary(Span::new(0, 3, 0), "here")
            .with_secondary(Span::new(1, 4, 0), "first here");
        let out = render_ai(&[diag], "f.ax", "abcd efgh ijkl");
        let line = out.trim_end();
        assert!(line.contains(" ^1:2-5:\"first here\""));
    }

    #[test]
    fn render_ai_notes() {
        let diag = Diagnostic::error(&DUMMY_CODE, "oops")
            .with_primary(Span::new(0, 1, 0), "")
            .with_note("this is a note");
        let out = render_ai(&[diag], "f.ax", "01");
        assert!(out.contains(" !\"this is a note\""));
    }

    #[test]
    fn render_ai_help_without_replacement() {
        let diag = Diagnostic::error(&DUMMY_CODE, "oops")
            .with_primary(Span::new(0, 1, 0), "")
            .with_help("try this instead");
        let out = render_ai(&[diag], "f.ax", "01");
        assert!(out.contains(" ?\"try this instead\""));
    }

    #[test]
    fn render_ai_help_with_replacement() {
        let diag = Diagnostic::error(&DUMMY_CODE, "oops").with_suggestion(
            "fix it",
            Span::new(0, 1, 0),
            "fix",
        );
        let out = render_ai(&[diag], "f.ax", "01");
        assert!(out.contains(" ?1:1-2:\"fix it\"~>\"fix\""));
    }

    #[test]
    fn render_ai_machine_fix_with_colon_in_message() {
        let diag = Diagnostic::error(&DUMMY_CODE, "oops").with_suggestion(
            "use colon: ok",
            Span::new(0, 1, 0),
            "repl",
        );
        let out = render_ai(&[diag], "f.ax", "01");
        // colon in message must not be confused with span separator
        assert!(out.contains(" ?1:1-2:\"use colon: ok\"~>\"repl\""));
    }

    #[test]
    fn render_ai_message_with_newline_stays_on_one_line() {
        let diag =
            Diagnostic::error(&DUMMY_CODE, "line1\nline2").with_primary(Span::new(0, 1, 0), "");
        let out = render_ai(&[diag], "f.ax", "01");
        let lines: Vec<&str> = out.lines().collect();
        assert_eq!(lines.len(), 1);
    }

    #[test]
    fn dedup_suppresses_later_groups() {
        let a = Diagnostic::error(&DUMMY_CODE, "a").with_group("g1");
        let b = Diagnostic::error(&DUMMY_CODE, "b").with_group("g1");
        let c = Diagnostic::error(&DUMMY_CODE, "c");
        let out = dedup(vec![a, b, c]);
        assert_eq!(out.len(), 2);
        assert_eq!(out[0].message, "a");
        assert_eq!(out[1].message, "c");
    }

    #[test]
    fn diagnostic_format_parse_accepts_aliases() {
        assert_eq!(
            DiagnosticFormat::parse("human"),
            Some(DiagnosticFormat::Human)
        );
        assert_eq!(DiagnosticFormat::parse("ai"), Some(DiagnosticFormat::Ai));
        assert_eq!(
            DiagnosticFormat::parse("json"),
            Some(DiagnosticFormat::Json)
        );
        assert_eq!(DiagnosticFormat::parse("agent"), Some(DiagnosticFormat::Ai));
        assert_eq!(
            DiagnosticFormat::parse("compact"),
            Some(DiagnosticFormat::Ai)
        );
        assert_eq!(
            DiagnosticFormat::parse("rustc"),
            Some(DiagnosticFormat::Human)
        );
        assert_eq!(DiagnosticFormat::parse("unknown"), None);
    }

    #[test]
    fn render_json_produces_valid_json_lines() {
        let diag = Diagnostic::error(&DUMMY_CODE, "test")
            .with_primary(Span::new(0, 1, 0), "label")
            .with_secondary(Span::new(2, 3, 0), "related")
            .with_note("note1")
            .with_help("help1");
        let out = render_json(&[diag], "f.ax", "012345");
        let line = out.lines().next().unwrap();
        assert!(line.contains("\"severity\":\"error\""));
        assert!(line.contains("\"code\":\"AX9999\""));
        assert!(line.contains("\"slug\":\"test-code\""));
        assert!(line.contains("\"message\":\"test\""));
        assert!(line.contains("\"file\":\"f.ax\""));
        assert!(line.contains("\"label\":\"label\""));
        assert!(line.contains("\"related\":[{"));
        assert!(line.contains("\"notes\":[\"note1\"]"));
        assert!(line.contains("\"help\":[\"help1\"]"));
    }

    #[test]
    fn render_json_char_offsets_are_characters_not_bytes() {
        let source = "héllo"; // h=0, é=1, l=2, l=3, o=4 (é is 2 bytes)
        let diag = Diagnostic::error(&DUMMY_CODE, "test").with_primary(Span::new(1, 3, 0), "");
        let out = render_json(&[diag], "f.ax", source);
        let line = out.lines().next().unwrap();
        assert!(line.contains("\"start\":{\"line\":1,\"col\":2}"));
        assert!(line.contains("\"end\":{\"line\":1,\"col\":4}"));
        assert!(line.contains("\"char_start\":1"));
        assert!(line.contains("\"char_end\":3"));
    }
}
