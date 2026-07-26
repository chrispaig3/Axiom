use axiom_ast::span::Span;

use crate::code::CodeInfo;
use crate::severity::Severity;

/// A span with an attached message, e.g. `expected function type here`.
#[derive(Debug, Clone)]
pub struct Label {
    pub span: Span,
    pub message: String,
}

/// A machine-applicable (or at least machine-describable) fix.
///
/// When `replacement` is `Some`, tooling (including AI agents) can apply the
/// fix mechanically by replacing the byte range `span` with `replacement` in
/// the source file, without having to parse natural-language prose.
#[derive(Debug, Clone)]
pub struct Suggestion {
    pub message: String,
    pub span: Option<Span>,
    pub replacement: Option<String>,
}

/// A single compiler diagnostic: an error, warning, note, or help message.
///
/// This is the one structured representation that both the human-oriented
/// renderer (`render::human`) and the AI-optimized renderer (`render::ai`)
/// consume, so the two output modes can never drift out of sync with each
/// other or with what the compiler actually knows.
#[derive(Debug, Clone)]
pub struct Diagnostic {
    pub severity: Severity,
    /// Stable code, e.g. `"AX3001"`. Always present for errors/warnings;
    /// notes/helps attached to a parent diagnostic may omit it.
    pub code: Option<&'static CodeInfo>,
    pub message: String,
    pub primary: Option<Label>,
    pub secondary: Vec<Label>,
    pub notes: Vec<String>,
    pub helps: Vec<Suggestion>,
    /// Identity used to collapse cascading diagnostics that all stem from
    /// the same root cause (e.g. one undefined variable producing a chain
    /// of downstream type-mismatch errors). Diagnostics sharing a `group`
    /// with an earlier-emitted diagnostic are suppressed by
    /// [`crate::render::dedup`].
    pub group: Option<String>,
}

impl Diagnostic {
    pub fn new(severity: Severity, code: &'static CodeInfo, message: impl Into<String>) -> Self {
        Self {
            severity,
            code: Some(code),
            message: message.into(),
            primary: None,
            secondary: Vec::new(),
            notes: Vec::new(),
            helps: Vec::new(),
            group: None,
        }
    }

    pub fn error(code: &'static CodeInfo, message: impl Into<String>) -> Self {
        Self::new(Severity::Error, code, message)
    }

    pub fn warning(code: &'static CodeInfo, message: impl Into<String>) -> Self {
        Self::new(Severity::Warning, code, message)
    }

    pub fn with_primary(mut self, span: Span, message: impl Into<String>) -> Self {
        self.primary = Some(Label {
            span,
            message: message.into(),
        });
        self
    }

    pub fn with_secondary(mut self, span: Span, message: impl Into<String>) -> Self {
        self.secondary.push(Label {
            span,
            message: message.into(),
        });
        self
    }

    pub fn with_note(mut self, note: impl Into<String>) -> Self {
        self.notes.push(note.into());
        self
    }

    pub fn with_help(mut self, message: impl Into<String>) -> Self {
        self.helps.push(Suggestion {
            message: message.into(),
            span: None,
            replacement: None,
        });
        self
    }

    pub fn with_suggestion(
        mut self,
        message: impl Into<String>,
        span: Span,
        replacement: impl Into<String>,
    ) -> Self {
        self.helps.push(Suggestion {
            message: message.into(),
            span: Some(span),
            replacement: Some(replacement.into()),
        });
        self
    }

    /// Mark this diagnostic as belonging to a cascade group. All
    /// diagnostics after the first in a group with the same key are
    /// dropped by [`crate::render::dedup`] before rendering.
    pub fn with_group(mut self, group: impl Into<String>) -> Self {
        self.group = Some(group.into());
        self
    }

    pub fn primary_span(&self) -> Option<Span> {
        self.primary.as_ref().map(|l| l.span)
    }
}
