use std::fmt;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash)]
pub struct Span {
    pub start: usize,
    pub end: usize,
    pub file_id: usize,
}

impl Span {
    pub fn new(start: usize, end: usize, file_id: usize) -> Self {
        Self {
            start,
            end,
            file_id,
        }
    }

    pub fn dummy() -> Self {
        Self {
            start: 0,
            end: 0,
            file_id: 0,
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Hash)]
pub struct Ident {
    pub name: String,
    pub span: Span,
    pub scope: usize,
}

impl Ident {
    pub fn new(name: &str, span: Span) -> Self {
        Self {
            name: name.to_string(),
            span,
            scope: 0,
        }
    }

    pub fn with_scope(name: &str, span: Span, scope: usize) -> Self {
        Self {
            name: name.to_string(),
            span,
            scope,
        }
    }
}

impl fmt::Display for Ident {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(f, "{}", self.name)
    }
}
