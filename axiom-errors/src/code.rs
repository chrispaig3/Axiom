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
    RECURSION_LIMIT => ("AX2005", "recursion-limit",
        "nesting too deep",
        "A form nests more deeply than the parser's fixed limit. Every stage\n\
         after the parser walks the syntax tree recursively, so an unbounded\n\
         nesting depth is an unbounded native stack depth; the limit converts\n\
         what would otherwise be a stack overflow - a crash with no span and no\n\
         message - into this diagnostic, pointing at the token where the limit\n\
         was reached.\n\
         \n\
         Hand-written code effectively never reaches the limit. Generated code\n\
         can: a long chain built by folding a binary operator over a list nests\n\
         once per element. Emit a `let` chain, a `{}` block, or a balanced tree\n\
         instead of one deeply nested form."),

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
        "The body of a `handle` expression performs effects that its\n\
         handled-effects list does not name. List every effect the body\n\
         can perform, or move the unhandled operation outside the\n\
         `handle`.\n\
         \n\
         (Effects do not appear in function signatures; a function's\n\
         effect claims are made with `;@axiom:effect(...)` tags and\n\
         validated as AX3010.)"),
    ASSIGN_TO_IMMUTABLE => ("AX3012", "assign-to-immutable",
        "cannot assign to an immutable binding",
        "`set` stores into a local, and a local is assignable only if it was\n\
         introduced as `(let ((mut x ...)) ...)`. Immutable is the default, so\n\
         a binding that is never reassigned needs no annotation and cannot be\n\
         changed by accident.\n\
         \n\
         Add `mut` at the declaration, or - usually better - compute the value\n\
         you want with a `let` rather than mutating one you already have.\n\
         \n\
         Only a whole local can be assigned. Function parameters, pattern\n\
         bindings and top-level declarations are never mutable, and structure\n\
         fields are written with `memSetWord` instead."),
    AMBIGUOUS_NAME => ("AX3014", "ambiguous-name",
        "a bare name is defined in more than one imported module",
        "Two or more imported modules define this name and the entry file\n\
         does not, so a bare reference has no principled winner - and before\n\
         this diagnostic the compiler's stages genuinely disagreed about\n\
         which definition it meant, so a program could type-check against\n\
         one module's signature and run the other module's code.\n\
         \n\
         Qualify the reference as `Module::name` to pick explicitly, or\n\
         import only the names you want with `(import Module (name ...))`.\n\
         A name the entry file defines itself always resolves to the entry\n\
         file's definition and needs no qualification."),
    MISSING_DEFINITION => ("AX3015", "missing-definition",
        "a signature with no definition behind it",
        "A `(:: name Type)` signature declares a name, but only a `(fn ...)`\n\
         or `(foreign ...)` gives it something to run. This name has the\n\
         former and not the latter - either the entry file declares the\n\
         signature and never defines the function, or an import delivered a\n\
         `pub` signature whose definition stayed private in its module.\n\
         Calling it used to pass `check` and then fail in the native\n\
         toolchain with an undefined-symbol error about generated code.\n\
         \n\
         Add the definition, or mark the defining `fn` `pub` alongside its\n\
         signature so the import carries both."),
    PARTIAL_APPLICATION => ("AX3013", "partial-application",
        "partial application is not supported",
        "A top-level function was applied to fewer arguments than its\n\
         definition declares, or a function of two or more parameters was\n\
         used as a bare value. Both are well-typed under currying, but the\n\
         compiled representation has no way to hold the missing arguments:\n\
         a call site would simply omit them, and the callee would read\n\
         whatever happened to be in the argument registers - which is how\n\
         this used to run and crash instead of being reported.\n\
         \n\
         Bind the missing arguments with a lambda instead: where `(f x)`\n\
         was meant, write `(lambda (y) (f x y))`. A lambda captures `x` in\n\
         a closure record, which is the representation partial application\n\
         would need and lambdas already have. Saturated calls, calls with\n\
         *extra* arguments applied to a returned function value, and\n\
         one-parameter functions used as values are all unaffected."),
    UNKNOWN_EFFECT => ("AX3016", "unknown-effect",
        "a handle list names an effect that is not declared",
        "The effects a `handle` expression may name are the built-ins\n\
         (`IO`, `Alloc`, `Mut`, `Div`) and effects introduced by an\n\
         `(effect Name (op :: sig) ...)` declaration in scope. This name\n\
         is neither, so the handle could never intercept or scope\n\
         anything - before this diagnostic it was accepted silently and\n\
         did nothing.\n\
         \n\
         Declare the effect, import the module that declares it, or fix\n\
         the spelling."),
    EFFECT_HANDLER_UNSUPPORTED => ("AX3017", "effect-handler-unsupported",
        "an effect-handler shape the compiler does not support yet",
        "Dynamic handlers currently support exactly one custom effect per\n\
         `handle` expression, and only effects that declare exactly one\n\
         operation; an effect operation is callable but cannot be used as\n\
         a bare value (there is no closure representation for dynamic\n\
         dispatch). Nest `handle` expressions to install handlers for\n\
         several effects at once, and split multi-operation effects into\n\
         one effect per operation until per-operation handler syntax\n\
         exists."),

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
