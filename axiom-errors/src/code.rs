/// Static metadata about a stable Axiom diagnostic code.
///
/// Codes are namespaced by compiler stage so that seeing the first digit
/// alone tells you roughly where in the pipeline something broke:
///
/// * `AX1xxx` - lexical analysis
/// * `AX2xxx` - parsing / syntax
/// * `AX3xxx` - semantic analysis / type checking
/// * `AX4xxx` - IR lowering, codegen, and the native toolchain
/// * `AX5xxx` - module/import resolution
///
/// This is intentionally modeled after `rustc`'s `E0308`-style codes: a
/// stable, greppable identifier that survives message wording changes,
/// can be looked up with `axiom explain <CODE>`, and can be pattern-matched
/// by tooling (editors, CI, AI agents) without parsing prose.
#[derive(Debug, Clone, Copy)]
pub struct CodeInfo {
    /// Stable identifier, e.g. `"AX3001"`.
    pub code: &'static str,
    /// kebab-case machine-friendly name, stable across wording changes.
    /// Doubles as the AI-notation "slug" field.
    pub slug: &'static str,
    /// One-line human title.
    pub title: &'static str,
    /// Longer explanation shown by `axiom explain AX3001`.
    pub explain: &'static str,
}

macro_rules! registry {
    ($($const_name:ident => ($code:literal, $slug:literal, $title:literal, $explain:literal)),* $(,)?) => {
        $(
            pub const $const_name: CodeInfo = CodeInfo {
                code: $code,
                slug: $slug,
                title: $title,
                explain: $explain,
            };
        )*

        /// All known codes, used by `lookup` and `axiom explain --list`.
        pub const ALL: &[CodeInfo] = &[$($const_name),*];
    };
}

registry! {
    // ---- AX1xxx: lexer ----
    UNEXPECTED_CHAR => ("AX1001", "unexpected-char",
        "unexpected character",
        "The lexer found a character that cannot start any valid Axiom token.\n\
         Axiom identifiers may contain letters, digits, `_` and `'`; operators are\n\
         built from a fixed set of symbol characters. Check for typos, stray\n\
         punctuation copied from another language, or an unsupported Unicode\n\
         character."),
    UNTERMINATED_STRING => ("AX1002", "unterminated-string",
        "unterminated string literal",
        "A `\"` was opened but never closed before the end of input (or end of\n\
         line). Add a matching closing `\"`, or escape an embedded `\"` as `\\\"`."),
    UNTERMINATED_CHAR => ("AX1003", "unterminated-char",
        "unterminated character literal",
        "A `'` character literal must contain exactly one character (or escape)\n\
         followed by a closing `'`, e.g. `'a'` or `'\\n'`."),
    INVALID_NUMBER => ("AX1004", "invalid-number-literal",
        "invalid number literal",
        "The digits form a number literal that doesn't fit the expected numeric\n\
         format (e.g. it overflows i64/f64, or has a malformed exponent)."),
    INVALID_ESCAPE => ("AX1005", "invalid-escape-sequence",
        "invalid escape sequence",
        "Only `\\n`, `\\t`, `\\r`, `\\\\`, `\\\"`, `\\'` and `\\0` are recognized escape\n\
         sequences inside string and character literals."),

    // ---- AX2xxx: parser ----
    UNEXPECTED_TOKEN => ("AX2001", "unexpected-token",
        "unexpected token",
        "The parser expected one kind of token (based on the surrounding\n\
         grammar) but found something else. This is usually a missing/extra\n\
         parenthesis, a misspelled keyword, or a declaration in the wrong\n\
         position."),
    UNEXPECTED_EOF => ("AX2002", "unexpected-eof",
        "unexpected end of file",
        "The file ended while a form was still open, most commonly an\n\
         unbalanced `(`, `[` or `{`. Count opening vs. closing delimiters\n\
         working backward from the end of the file."),
    PARSE_MESSAGE => ("AX2003", "syntax-error",
        "syntax error",
        "A syntax rule was violated in a way that doesn't fit a more specific\n\
         diagnostic code; see the message for details."),
    REMOVED_CONSTRUCT => ("AX2004", "removed-construct",
        "removed language construct",
        "This form was part of an earlier version of Axiom and no longer exists.\n\
         The keyword is still reserved so that old source gets this explanation\n\
         instead of being silently reinterpreted as an ordinary identifier.\n\
         \n\
         `union` is gone because C interoperability is no longer a goal of the\n\
         language. An untagged union cannot be pattern-matched safely and has no\n\
         meaning under linear typing, where every value has exactly one owner and\n\
         one type. Use `data` for a tagged sum, whose variants the compiler can\n\
         check for exhaustiveness, or `struct` for a product.\n\
         \n\
         `region` is gone because memory is no longer scoped by an explicit\n\
         source-level block. Allocation lifetime is inferred: a value's arena is\n\
         determined by where it is created and how far it escapes, and it is\n\
         dropped deterministically at the end of that arena. Delete the `region`\n\
         wrapper; the body is the program."),

    // ---- AX3xxx: semantic analysis ----
    UNDEFINED_VARIABLE => ("AX3001", "undefined-variable",
        "undefined variable",
        "No binding with this name is in scope: not a local `let`/`lambda`\n\
         parameter, not a top-level `define`/`fn`, and not a data constructor.\n\
         Check for typos, missing imports, or a definition that appears later\n\
         in the file (Axiom does not forward-reference local bindings)."),
    UNDEFINED_TYPE => ("AX3002", "undefined-type",
        "undefined type",
        "This type name does not refer to any built-in type, `data`, `struct`,\n\
         or `type` alias visible in this module."),
    UNDEFINED_CONSTRUCTOR => ("AX3003", "undefined-constructor",
        "undefined constructor",
        "This name was used as a data constructor (applied like `(Foo x y)` or\n\
         matched in a pattern) but no `data` declaration defines a constructor\n\
         with this name."),
    TYPE_MISMATCH => ("AX3004", "type-mismatch",
        "type mismatch",
        "An expression's inferred type doesn't match the type required by its\n\
         context (a function parameter, `if` branch, `let` binding, etc.)."),
    NON_EXHAUSTIVE => ("AX3005", "non-exhaustive-match",
        "non-exhaustive pattern match",
        "A `match` expression does not cover every possible constructor/value of\n\
         the scrutinee's type. Add the missing arms or a wildcard `_` arm."),
    DUPLICATE_DEFINITION => ("AX3006", "duplicate-definition",
        "duplicate definition",
        "The same name is defined more than once at the same scope. Rename one\n\
         of the definitions or remove the duplicate."),
    FIELD_NOT_FOUND => ("AX3007", "field-not-found",
        "field not found",
        "The named field does not exist on the given `struct` type. Check the\n\
         field name for typos or that you're accessing the right type."),
    SEMA_MESSAGE => ("AX3008", "semantic-error",
        "semantic error",
        "A semantic rule was violated in a way that doesn't fit a more specific\n\
         diagnostic code; see the message for details."),
    CONSTRUCTOR_ARITY => ("AX3009", "constructor-arity-mismatch",
        "constructor arity mismatch",
        "A data constructor was applied (or matched in a pattern) with the wrong\n\
         number of arguments. Check the constructor's `data` declaration for how\n\
         many fields it actually has."),
    AXTAG_MISMATCH => ("AX3010", "axtag-mismatch",
        "agent metadata mismatch",
        "A `;@axiom:<key>(<value>)` tag on this declaration makes a claim\n\
         (e.g. `effect(io)`, `pure`) that the body does not support. The\n\
         compiler validates tags it can and reports mismatches so an agent\n\
         can correct the annotation instead of silently trusting it."),
    EFFECT_MISMATCH => ("AX3011", "effect-mismatch",
        "effect mismatch",
        "This expression performs effects that are not declared in its\n\
         signature or not handled by the enclosing `handle` expression."),

    // ---- AX4xxx: lowering / codegen / toolchain ----
    MISSING_MAIN => ("AX4001", "missing-main",
        "no `main` function",
        "An executable Axiom program needs exactly one top-level function named\n\
         `main` to serve as the entry point. Add `(:: main Int)` and\n\
         `(define main ...)`, or use `axiom check`/`emit-llvm` if you only want\n\
         to analyze a library-style module."),
    CODEGEN_FAILURE => ("AX4002", "codegen-failure",
        "code generation failed",
        "The IR-to-LLVM lowering stage hit a case it doesn't yet support or an\n\
         internal invariant was violated. This generally indicates a compiler\n\
         limitation rather than a mistake in your source; please file a bug\n\
         with a minimal reproduction."),
    TOOLCHAIN_FAILURE => ("AX4003", "toolchain-failure",
        "external toolchain command failed",
        "Axiom shells out to `llc` and `cc` to turn LLVM IR into a native\n\
         executable. This error means one of those external commands could not\n\
         be run or exited unsuccessfully; check that LLVM (`llc`) and a C\n\
         compiler (`cc`) are installed and on your `PATH`."),

    // ---- AX5xxx: module resolution ----
    MODULE_NOT_FOUND => ("AX5001", "module-not-found",
        "cannot resolve import",
        "An `(import Mod.Sub ...)` declaration names a module path that doesn't\n\
         correspond to any file on disk. Module paths are resolved relative to\n\
         the entry file's own directory (the file passed to `check`/`build`/\n\
         `run`/`emit-llvm`), not the directory of whichever file wrote the\n\
         `(import ...)`: `Mod.Sub` looks for `Mod/Sub.ax` next to (or below)\n\
         the entry file, from every file in the program alike."),
}

/// Look up full metadata for a stable code string such as `"AX3001"`.
/// Matching is case-insensitive and tolerates a missing `AX` prefix so that
/// `axiom explain 3001` and `axiom explain ax3001` both work.
pub fn lookup(code: &str) -> Option<&'static CodeInfo> {
    let normalized = normalize(code);
    ALL.iter().find(|c| normalize(c.code) == normalized)
}

fn normalize(code: &str) -> String {
    let upper = code.trim().to_ascii_uppercase();
    let upper = upper.strip_prefix("AX").unwrap_or(&upper);
    upper.trim_start_matches('-').to_string()
}
