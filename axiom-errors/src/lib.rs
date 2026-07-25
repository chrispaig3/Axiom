/// A diagnostic error that can be reported with rich context
pub struct AxiomError {
    pub title: String,
    pub span_start: usize,
    pub span_end: usize,
    pub notes: Vec<String>,
    pub helps: Vec<String>,
}

impl AxiomError {
    pub fn new(title: impl Into<String>) -> Self {
        Self {
            title: title.into(),
            span_start: 0,
            span_end: 0,
            notes: Vec::new(),
            helps: Vec::new(),
        }
    }

    pub fn with_span(mut self, start: usize, end: usize) -> Self {
        self.span_start = start;
        self.span_end = end;
        self
    }

    pub fn with_note(mut self, note: impl Into<String>) -> Self {
        self.notes.push(note.into());
        self
    }

    pub fn with_help(mut self, help: impl Into<String>) -> Self {
        self.helps.push(help.into());
        self
    }
}

/// A collection of errors
pub struct ErrorBuffer {
    pub errors: Vec<AxiomError>,
}

impl ErrorBuffer {
    pub fn new() -> Self {
        Self { errors: Vec::new() }
    }

    pub fn push(&mut self, error: AxiomError) {
        self.errors.push(error);
    }

    pub fn is_empty(&self) -> bool {
        self.errors.is_empty()
    }

    pub fn len(&self) -> usize {
        self.errors.len()
    }
}

impl Default for ErrorBuffer {
    fn default() -> Self {
        Self::new()
    }
}
