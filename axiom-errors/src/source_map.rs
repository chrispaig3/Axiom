/// Maps Axiom [`axiom_ast::span::Span`] offsets to 1-based `(line, column)`
/// pairs.
///
/// **Units:** Axiom's lexer (`axiom-lexer`) tokenizes a `Vec<char>`, so
/// every [`Span`](axiom_ast::span::Span) it (and everything downstream:
/// the parser, sema, and every `Diagnostic`) produces is a **character
/// index**, not a byte offset. `SourceMap` is deliberately char-indexed to
/// match, throughout: `line_starts` counts characters, `line_col` and
/// `line_text` walk `chars()` rather than byte-slicing. Treating these
/// offsets as byte offsets (the previous implementation did, via
/// `str::get(byte_range)`) silently produces wrong line/column numbers for
/// any source file containing multi-byte UTF-8 characters before an error,
/// because a "byte offset" that is actually a character count drifts from
/// the real byte position as soon as a multi-byte character is lexed.
///
/// This is the piece that was entirely missing before the diagnostics
/// rewrite: the old CLI just handed raw spans to `ariadne` and let it
/// infer line numbers, which broke down for the report *header* (it
/// always showed `:1:1` regardless of where the span actually was). Every
/// diagnostic now goes through this so the AI and JSON renderers agree
/// with the human renderer (which - via `ariadne::Source` - also indexes
/// by character, so it's consistent with this map) about location.
pub struct SourceMap {
    /// Character offset of the start of each line (line 0 always starts at
    /// character `0`).
    line_starts: Vec<usize>,
    /// Total character count of the source.
    len: usize,
}

impl SourceMap {
    pub fn new(source: &str) -> Self {
        let mut line_starts = vec![0];
        for (i, ch) in source.chars().enumerate() {
            if ch == '\n' {
                line_starts.push(i + 1);
            }
        }
        Self {
            len: source.chars().count(),
            line_starts,
        }
    }

    /// Convert a character offset into a 1-based `(line, column)` pair.
    /// Offsets past the end of the source clamp to the last position.
    pub fn line_col(&self, source: &str, char_offset: usize) -> (usize, usize) {
        let offset = char_offset.min(self.len);
        // Binary search for the line containing `offset`.
        let line_idx = match self.line_starts.binary_search(&offset) {
            Ok(i) => i,
            Err(i) => i.saturating_sub(1),
        };
        let line_start = self.line_starts[line_idx];
        let col = offset.saturating_sub(line_start);
        let _ = source; // kept for API stability; no longer needed for byte slicing
        (line_idx + 1, col + 1)
    }

    /// The full 1-based `(line, col)` -> `(line, col)` range for a span.
    pub fn span_range(&self, source: &str, start: usize, end: usize) -> ((usize, usize), (usize, usize)) {
        (self.line_col(source, start), self.line_col(source, end.max(start)))
    }

    /// Extract the raw text of the line a character offset falls on,
    /// useful for building `^^^` underlines without re-deriving offsets.
    pub fn line_text(&self, source: &str, char_offset: usize) -> String {
        let offset = char_offset.min(self.len);
        let line_idx = match self.line_starts.binary_search(&offset) {
            Ok(i) => i,
            Err(i) => i.saturating_sub(1),
        };
        let start = self.line_starts[line_idx];
        let end = self
            .line_starts
            .get(line_idx + 1)
            .map(|&e| e.saturating_sub(1).max(start))
            .unwrap_or(self.len);
        source.chars().skip(start).take(end - start).collect()
    }
}
