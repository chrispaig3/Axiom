# Axiom — Agent Instructions

## 1. Always Use `axiom diagnostics=ai` First

When running *any* Axiom compiler command, always pass the AI-optimized diagnostic format:

```bash
axiom diagnostics=ai <command> <args>
```

This is shorthand for `--diagnostic-format=ai` on every `axiom` subcommand (build, check, symbols, run, emit-llvm, etc.). It uses the AXDL (Axiom eXchange Diagnostic Line) renderer, which produces one dense, greppable, colorless line per diagnostic with no re-rendered source text — designed to minimize tokens consumed by an LLM agent.

```bash
# Examples
axiom diagnostics=ai check source.ax
axiom diagnostics=ai build --input source.ax --output myprog
axiom diagnostics=ai symbols source.ax
```

The `human` renderer is for human consumption only; use it only when the `ai` output is insufficient.

### Key `ai` format details

- Each line is a single AXDL (Axiom eXchange Diagnostic Line) record.
- Fields are pipe-delimited and include: severity, code, slug, file, span, and message.
- Use `axiom explain <CODE>` to get the full explanation for any diagnostic code.
- Use `axiom explain --list` to see all known codes.
- Diagnostic codes are stable across wording changes (e.g. `AX3001`).

### Cascade suppression

A single root-cause error may produce cascading downstream errors. The compiler uses a `TError` poison type and `dedup` grouping to suppress these. When reading `ai` output, if multiple diagnostics share the same group key, only the first is the root cause; the rest are cascading consequences.

---

## 2. Architecture

### Compiler Pipeline

Axiom follows a classic multi-phase compiler pipeline. Each phase is a separate crate with a well-defined interface:

```
Source (.ax) → axiom-lexer → axiom-parser → axiom-sema → axiom-ir → axiom-codegen → LLVM IR → llc → Executable
```

| Crate | Responsibility |
|---|---|
| `axiom-lexer` | Tokenization of `.ax` source |
| `axiom-parser` | S-expression parsing into AST |
| `axiom-ast` | AST node definitions and spans |
| `axiom-sema` | Type checking, name resolution, effect analysis |
| `axiom-ir` | Intermediate representation generation |
| `axiom-codegen` | LLVM IR emission |
| `axiom-errors` | Diagnostic types, rendering, code lookup |
| `axiom-cli` | CLI entry point, orchestration |

### Key architectural principles

- **One structured representation, many renderers.** All diagnostics flow through `axiom_errors::Diagnostic`. The `human`, `ai`, and `json` renderers are interchangeable views over the same data. Never duplicate diagnostic logic across renderers.
- **Poison propagation over cascade suppression at the source.** When a type check fails, the checker propagates `TypeId::TError` rather than producing new diagnostics for every downstream use. `dedup` is a secondary safety net for diagnostics that are truly independent but logically related.
- **Stable diagnostic codes.** Every diagnostic carries a stable code (`AX1xxx`–`AX5xxx`) namespaced by compiler stage. Codes must not be reused or renumbered. Wording may change; codes must not.
- **Separation of concerns.** The lexer must not know about types; the parser must not know about effects; the codegen must not know about semantic analysis. Cross-crate dependencies flow in one direction (lexer → parser → sema → ir → codegen).

---

## 3. Design Patterns

### Structured diagnostics over ad-hoc strings

All compiler messages must go through `axiom_errors::Diagnostic` with a stable code, severity, span, and message. Never print raw strings from compiler phases.

### Suggestion-based fixes

`Diagnostic` supports `Suggestion` with an optional `Span` and `replacement` string. When a fix can be applied mechanically, provide it. AI agents and tooling can apply `Suggestion` replacements without parsing natural-language prose.

### Renderer abstraction

`DiagnosticFormat` is an enum with `Human`, `Ai`, and `Json` variants. New renderers should implement a function matching the signature of `render_ai` / `render_human` / `render_json` and be wired into `axiom_errors::render` and the CLI `--diagnostic-format` flag.

### Symbol tables and `SymbolFact`

`axiom-errors` provides `SymbolFact` and `render_symbols_ai` for emitting declarations alongside diagnostics. Use this for "what does this file already provide" queries rather than re-implementing symbol lookup.

### Grouping and deduplication

Use `.with_group(...)` on `Diagnostic` when a single root cause produces multiple logically related diagnostics. `axiom_errors::dedup` will suppress downstream entries in the same group.

### Error codes namespace

| Range | Stage |
|---|---|
| `AX1xxx` | Lexical analysis |
| `AX2xxx` | Parsing / syntax |
| `AX3xxx` | Semantic analysis / type checking |
| `AX4xxx` | IR lowering, codegen, native toolchain |
| `AX5xxx` | Module / import resolution |

---

## 4. Code Quality

### Rust conventions

- Follow `rustfmt` formatting. Run `cargo fmt` before committing.
- Use `clippy` lints. Run `cargo clippy` and treat warnings as errors in CI.
- Prefer `thiserror` for error types over manual `std::error::Error` impls.
- Use `ariadne` for human-readable diagnostic rendering; do not reimplement terminal coloring.
- All public API items must have doc comments. Internal items may use `//` comments sparingly.
- No `unwrap()` in library code. Use `?` or explicit `match`/`if let` with meaningful error messages.

### Testing

- Unit tests live in the same file as the code they test, under `#[cfg(test)]` modules.
- Integration tests live in `tests/` directories within each crate.
- Every diagnostic code must have at least one test case that exercises it.
- Use `insta` or snapshot testing for renderer output to catch formatting regressions.

### Immutability and ownership

- Prefer immutable bindings (`let`) over mutable ones (`let mut`).
- Use references (`&T`) unless ownership transfer is required.
- Avoid `Rc<RefCell<T>>` unless shared mutability is genuinely needed; prefer passing mutable references through the pipeline.

### Documentation

- Update `docs/diagnostics.md` when adding or changing diagnostic codes.
- Update `README.md` when the public surface area changes (CLI flags, language features).
- Keep `axiom-errors/src/code.rs` in sync with all diagnostic codes in use.

---

## 5. Security

### Memory safety

- Axiom is a systems language with manual memory control (`malloc`/`free`). The compiler itself must never introduce memory unsafety. All FFI calls must be wrapped in safe abstractions.
- When generating code that calls C functions via FFI, validate that signatures match exactly. Mismatched signatures are undefined behavior.

### Input validation

- All user-provided source files must be validated at every pipeline stage. A malformed input must produce a diagnostic, not a panic or segfault.
- The compiler must never execute arbitrary code from source files during compilation. Code generation must produce standalone LLVM IR; no runtime evaluation of user code.

### Dependency hygiene

- Audit `Cargo.lock` before adding new dependencies. Prefer crates with active maintenance and no known CVEs.
- Do not pull in crates with GPL or LGPL licenses unless explicitly approved. The project uses MIT license.
- Use `cargo audit` in CI to detect vulnerable dependencies.

### Toolchain safety

- The native toolchain invocation (`llc`) passes user-controlled file paths. Sanitize paths to prevent command injection or path traversal.
- Never pass unsanitized user input to shell commands. Use `std::process::Command` with explicit argument vectors, not shell strings.

### Compiler-as-trusted-tool

- Because Axiom is designed for agentic programming, agents must treat compiler output as authoritative. When the `ai` diagnostic format reports an error, do not attempt to work around it by modifying source to hide the diagnostic. Fix the root cause.
- When an agent generates Axiom source code, it must compile cleanly with `axiom diagnostics=ai check` and produce zero errors before the code is considered valid.

## 6. Self-Hosting

Axiom is being self-hosted — parts of the compiler are written in Axiom itself. The self-hosted code lives in `self_host/` and demonstrates that the compiler pipeline (lexer, parser, type checker, code generator) can be expressed as Axiom code.

### Self-hosted files

All declarations are **private by default**. Use `pub` to export:

```scheme
(pub :: vecNew Int)
(pub fn (vecNew) (vecWithCapacity (vecDefaultCap)))
```

| File | Purpose |
|---|---|
| `self_host/core.ax` | Core data structures (Span, Token, TokenKind) |
| `self_host/lexer.ax` | Tokenizer — text → tokens |
| `self_host/parser.ax` | Parser — tokens → AST |
| `self_host/typecheck.ax` | Type checker — AST → typed AST |
| `self_host/codegen.ax` | Code generator — typed AST → LLVM IR |
| `self_host/main.ax` | Entry point tying all phases together |

See `docs/reference.md#visibility` for the full `pub` syntax.

### Building self-hosted code

```bash
axiom check self_host/main.ax
axiom build --input self_host/main.ax --output self_host_test
```

The self-hosted code compiles with the existing Rust-based Axiom compiler. The goal is to eventually replace the Rust implementations with Axiom implementations, bootstrapping the compiler.