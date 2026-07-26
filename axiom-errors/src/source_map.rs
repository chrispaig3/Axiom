/// Maps byte offsets in a source string to 1-based `(line, column)` pairs.
///
/// This is the piece that was entirely missing before: the old CLI just
/// handed raw byte spans to `ariadne` and let it infer line numbers, which
/// broke down for the report *header* (it always showed `:1:1` regardless
/// of where the span actually was). Every diagnostic now goes through this
/// so human, AI, and JSON renderers agree on the same location.
///
/// Columns are counted in `char`s (not bytes), so multi-byte UTF-8 source
/// text still gets correct column numbers.
pub struct SourceMap {
    /// Byte offset of the start of each line (line 0 always starts at 0).
    line_starts: Vec<usize>,
    len: usize,
}

impl SourceMap {
    pub fn new(source: &str) -> Self {
        let mut line_starts = vec![0];
        for (i, ch) in source.char_indices() {
            if ch == '\n' {
                line_starts.push(i + 1);
            }
        }
        Self {
            line_starts,
            len: source.len(),
        }
    }

    /// Convert a byte offset into a 1-based `(line, column)` pair.
    /// Offsets past the end of the source clamp to the last position.
    pub fn line_col(&self, source: &str, byte_offset: usize) -> (usize, usize) {
        let offset = byte_offset.min(self.len);
        // Binary search for the line containing `offset`.
        let line_idx = match self.line_starts.binary_search(&offset) {
            Ok(i) => i,
            Err(i) => i.saturating_sub(1),
        };
        let line_start = self.line_starts[line_idx];
        let line_end = self
            .line_starts
            .get(line_idx + 1)
            .copied()
            .unwrap_or(self.len);
        let safe_end = offset.min(line_end).max(line_start);
        let col = source
            .get(line_start..safe_end)
            .map(|s| s.chars().count())
            .unwrap_or(0);
        (line_idx + 1, col + 1)
    }

    /// The full 1-based `(line, col)` -> `(line, col)` range for a span.
    pub fn span_range(&self, source: &str, start: usize, end: usize) -> ((usize, usize), (usize, usize)) {
        (self.line_col(source, start), self.line_col(source, end.max(start)))
    }

    /// Extract the raw text of the line a byte offset falls on, useful for
    /// building `^^^` underlines without re-deriving offsets.
    pub fn line_text<'s>(&self, source: &'s str, byte_offset: usize) -> &'s str {
        let offset = byte_offset.min(self.len);
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
        source.get(start..end).unwrap_or("")
    }
}
