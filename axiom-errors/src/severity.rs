/// Severity of a [`crate::Diagnostic`].
///
/// Mirrors the tiers used by rustc/clang so that Axiom's diagnostics feel
/// familiar: a compilation only fails because of `Error`s, everything else
/// is advisory.
#[derive(Debug, Clone, Copy, PartialEq, Eq, PartialOrd, Ord, Hash)]
pub enum Severity {
    Help,
    Note,
    Warning,
    Error,
}

impl Severity {
    /// Human label used in the pretty renderer, e.g. `"error"`.
    pub fn label(self) -> &'static str {
        match self {
            Severity::Error => "error",
            Severity::Warning => "warning",
            Severity::Note => "note",
            Severity::Help => "help",
        }
    }

    /// Single ASCII character used in the AI-optimized notation.
    /// Kept to one byte so the format stays maximally token-dense.
    pub fn sigil(self) -> char {
        match self {
            Severity::Error => 'E',
            Severity::Warning => 'W',
            Severity::Note => 'N',
            Severity::Help => 'H',
        }
    }

    pub fn is_error(self) -> bool {
        matches!(self, Severity::Error)
    }

    pub(crate) fn ariadne_kind(self) -> ariadne::ReportKind<'static> {
        match self {
            Severity::Error => ariadne::ReportKind::Error,
            Severity::Warning => ariadne::ReportKind::Warning,
            Severity::Note | Severity::Help => ariadne::ReportKind::Advice,
        }
    }
}
