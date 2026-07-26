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
    pub fn span_range(
        &self,
        source: &str,
        start: usize,
        end: usize,
    ) -> ((usize, usize), (usize, usize)) {
        (
            self.line_col(source, start),
            self.line_col(source, end.max(start)),
        )
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn empty_source_has_one_line() {
        let map = SourceMap::new("");
        assert_eq!(map.line_col("", 0), (1, 1));
        assert_eq!(map.span_range("", 0, 0), ((1, 1), (1, 1)));
    }

    #[test]
    fn single_line_source() {
        let map = SourceMap::new("hello");
        assert_eq!(map.line_col("hello", 0), (1, 1));
        assert_eq!(map.line_col("hello", 4), (1, 5));
        assert_eq!(map.line_col("hello", 5), (1, 6));
    }

    #[test]
    fn multi_line_source() {
        let src = "ab\ncd\nef";
        let map = SourceMap::new(src);
        // line 1: a(0) b(1)
        assert_eq!(map.line_col(src, 0), (1, 1));
        assert_eq!(map.line_col(src, 1), (1, 2));
        // line 2: c(3) d(4)
        assert_eq!(map.line_col(src, 3), (2, 1));
        assert_eq!(map.line_col(src, 4), (2, 2));
        // line 3: e(6) f(7)
        assert_eq!(map.line_col(src, 6), (3, 1));
        assert_eq!(map.line_col(src, 7), (3, 2));
    }

    #[test]
    fn utf8_multibyte_characters() {
        // ë is 2 bytes, but 1 char
        let src = "héllo\nwörld";
        let map = SourceMap::new(src);
        // h(0) é(1) l(2) l(3) o(4)
        assert_eq!(map.line_col(src, 0), (1, 1));
        assert_eq!(map.line_col(src, 1), (1, 2)); // é at char index 1
        assert_eq!(map.line_col(src, 4), (1, 5));
        // line 2
        assert_eq!(map.line_col(src, 6), (2, 1)); // w after newline
        assert_eq!(map.line_col(src, 7), (2, 2)); // ö
        assert_eq!(map.line_col(src, 11), (2, 6));
    }

    #[test]
    fn span_range_same_line() {
        let src = "hello world";
        let map = SourceMap::new(src);
        let ((s_l, s_c), (e_l, e_c)) = map.span_range(src, 0, 4);
        assert_eq!((s_l, s_c), (1, 1));
        assert_eq!((e_l, e_c), (1, 5));
    }

    #[test]
    fn span_range_crosses_lines() {
        let src = "ab\ncd\n";
        let map = SourceMap::new(src);
        let ((s_l, s_c), (e_l, e_c)) = map.span_range(src, 1, 5);
        assert_eq!((s_l, s_c), (1, 2));
        assert_eq!((e_l, e_c), (2, 3));
    }

    #[test]
    fn utf8_span_range() {
        let src = "αβγ\nδεζ";
        let map = SourceMap::new(src);
        // α(0) β(1) γ(2) newline(3) δ(4) ε(5) ζ(6)
        let ((s_l, s_c), (e_l, e_c)) = map.span_range(src, 1, 5);
        assert_eq!((s_l, s_c), (1, 2));
        assert_eq!((e_l, e_c), (2, 2));
    }

    #[test]
    fn line_text() {
        let src = "hello\nworld";
        let map = SourceMap::new(src);
        assert_eq!(map.line_text(src, 0), "hello");
        assert_eq!(map.line_text(src, 6), "world");
    }

    #[test]
    fn line_text_utf8() {
        let src = "héllo\nwörld";
        let map = SourceMap::new(src);
        assert_eq!(map.line_text(src, 0), "héllo");
        assert_eq!(map.line_text(src, 6), "wörld");
    }

    #[test]
    fn offsets_past_eof_clamp() {
        let src = "hi";
        let map = SourceMap::new(src);
        assert_eq!(map.line_col(src, 100), (1, 3)); // clamps to last+1
    }
}
