# Contributing to Axiom

Welcome! Whether you're here to fix a typo, add a feature, write a new stdlib module, or just explore how a functional systems language works — you're in the right place. This guide will walk you through everything you need to know to get started.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Project Structure](#project-structure)
3. [How the Compiler Works](#how-the-compiler-works)
4. [Making Changes](#making-changes)
5. [Testing](#testing)
6. [CI/CD](#cicd)
7. [Code Style and Conventions](#code-style-and-conventions)
8. [Adding a Diagnostic Code](#adding-a-diagnostic-code)
9. [Adding a Standard Library Function](#adding-a-standard-library-function)
10. [The Agent-Facing Notation System](#the-agent-facing-notation-system)
11. [Contributor Guidelines](#contributor-guidelines)
12. [Resources](#resources)

---

## Quick Start

### Prerequisites

- **Rust 1.70+** — to build the compiler
- **LLVM** — `llc` must be on your PATH (for code generation)
- **A C compiler** — `cc`, `clang`, or `gcc` on your PATH (for final linking)

On macOS:

```bash
brew install llvm
```

On Ubuntu/Debian:

```bash
sudo apt install llvm clang
```

### Build the compiler

```bash
git clone https://github.com/chrispaig3/Axiom
cd axiom
cargo build --release
```

The binary is at `./target/release/axiom`.

### Verify it works

```bash
echo '(import IO)
(:: main Int)
;@axiom:effect(io)
(fn (main)
  { (println "Hello from Axiom!")
    0 })' > hello.ax

./target/release/axiom run hello.ax
```

You should see `Hello from Axiom!` printed to the terminal.

---

## Project Structure

```
axiom/
├── axiom-ast/          AST, token, and span definitions
├── axiom-lexer/        Tokenizer
├── axiom-parser/       S-expression parser
├── axiom-sema/         Two-pass type checker (name resolution + effect analysis)
├── axiom-ir/           IR definitions and generator
├── axiom-codegen/      LLVM IR emitter
├── axiom-cli/          CLI entry point, REPL, fmt, symbols
├── axiom-errors/       Diagnostics, AXDL/AXSYM rendering, code lookup, SymbolFact
├── stdlib/             Standard library written in Axiom (Pre, Mem, Str, Vec, Map, Fmt, Intern, Sys, IO)
├── tree-sitter-axiom/  Editor grammar for syntax highlighting and structural editing
├── tests/stdlib/       Golden tests: compile, run, compare output
├── scripts/            CI gates, each runnable locally
├── docs/               Documentation (diagnostics.md, self-hosting.md, v1-roadmap.md, reference.md)
├── Cargo.toml          Workspace manifest
└── README.md
```

### Crate dependency flow

Dependencies flow in one direction — no crate knows about a downstream crate:

```
lexer → parser → sema → ir → codegen
```

- The lexer must not know about types.
- The parser must not know about effects.
- The codegen must not know about semantic analysis.

---

## How the Compiler Works

Every Axiom program goes through this pipeline:

```
Source (.ax) → Lexer → Parser → Type Checker → IR → LLVM IR → llc → cc → Executable
```

1. **Lexer** (`axiom-lexer`) — turns source text into tokens.
2. **Parser** (`axiom-parser`) — turns tokens into an AST (S-expression tree).
3. **Type Checker** (`axiom-sema`) — two-pass: collects declarations, then checks bodies. Propagates `TypeId::TError` (poison) after a type mismatch to suppress cascading errors.
4. **IR** (`axiom-ir`) — lowers the AST to three-address code with basic blocks.
5. **LLVM CodeGen** (`axiom-codegen`) — emits LLVM IR text, which `llc` compiles to an object file, and `cc` links to an executable.

---

## Making Changes

### The development workflow

1. **Build** — `cargo build --release` (or `cargo build` for faster debug builds).
2. **Make your change** — edit the relevant file(s).
3. **Test** — run the relevant test suite (see [Testing](#testing)).
4. **Format** — `cargo fmt` before committing.
5. **Lint** — `cargo clippy --all-targets --all-features -- -D warnings` — treat warnings as errors.
6. **Commit** — write a clear, concise commit message that matches the project style.

### Where to make changes

| What you want to do | Where to look |
|---|---|
| Add a new AST node | `axiom-ast/src/ast.rs` |
| Add a new token | `axiom-ast/src/token.rs` |
| Change parsing rules | `axiom-parser/src/lib.rs` |
| Add a type-checking rule | `axiom-sema/src/lib.rs` |
| Add a new IR instruction | `axiom-ir/src/lib.rs` |
| Change LLVM emission | `axiom-codegen/src/lib.rs` |
| Add a CLI command | `axiom-cli/src/lib.rs` |
| Add a diagnostic code | `axiom-errors/src/code.rs` |
| Add a stdlib function | `stdlib/` (e.g. `IO.ax`, `Mem.ax`, `Str.ax`, `Vec.ax`, `Map.ax`, `Fmt.ax`, `Intern.ax`, `Pre.ax`) |
| Add a new syntax feature | `tree-sitter-axiom/grammar.js` + parser + ast + lexer |

---

## Testing

Axiom has several layers of testing. Run them all before submitting a PR.

### Unit tests

Unit tests live in the same file as the code they test, under `#[cfg(test)]` modules:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_something() {
        // ...
    }
}
```

Run all unit tests:

```bash
cargo test --release --all
```

### Integration tests

Integration tests live in `tests/` directories within each crate.

### Golden tests (stdlib)

The standard library has golden tests in `tests/stdlib/`. Each test is a pair of files:

- `NNN-name.ax` — the Axiom source
- `NNN-name.out` — the expected stdout
- `NNN-name.exit` — (optional) the expected exit status (default 0)

Run the golden tests:

```bash
cargo test --release --all
```

Or run them manually through the script:

```bash
./scripts/run-stdlib-tests.sh        # every case
./scripts/run-stdlib-tests.sh 030-str  # one case, by name prefix
```

### Freestanding check

Verify that compiled programs contain no libc calls:

```bash
./scripts/check-freestanding.sh
```

### Cross-target codegen

Verify that IR assembles for every supported target from a single host:

```bash
./scripts/check-cross-targets.sh
```

### Reproducible build

Verify that two independent runs produce byte-identical IR:

```bash
./scripts/check-reproducible.sh
```



Verify that the grammar accepts every `.ax` file in the repository:

```bash
npm install --prefix tree-sitter-axiom --no-save tree-sitter-cli
./scripts/check-tree-sitter.sh
```

---

## CI/CD

Every push and pull request triggers the CI pipeline in `.github/workflows/ci.yml`. The pipeline is staged so that cheap failures are reported before expensive ones:

1. **Lint** — `cargo fmt --all --check` and `cargo clippy --all-targets --all-features -- -D warnings`
2. **Test** — unit, integration, and golden tests on three platforms (linux-x86_64, linux-aarch64, darwin-aarch64)
3. **Grammar** — tree-sitter grammar accepts every `.ax` file
4. **Cross-target** — IR assembles for all four targets
5. **Reproducible** — two runs produce identical IR

### What the CI tests actually do

The tests compile and **run** Axiom programs rather than only type-checking them. This catches a class of bugs that a type-check-only CI would miss — for example, a syscall lowering that assembles correctly but returns the wrong value.

---

## Code Style and Conventions

### Formatting

- Run `cargo fmt` before committing.
- The project uses the default Rust formatter configuration.

### Linting

- Run `cargo clippy --all-targets --all-features -- -D warnings` locally.
- Warnings are treated as errors in CI (`RUSTFLAGS: -D warnings`).

### Naming conventions

| Item | Convention | Example |
|---|---|---|
| Functions | `snake_case` | `sysWriteFd`, `fmtInt` |
| Types | `PascalCase` | `Maybe`, `Point`, `Console` |
| Constructors | `PascalCase` | `Nothing`, `Just`, `Cons` |
| Type parameters | single lowercase letter | `a`, `b`, `t` |
| Modules | `PascalCase` | `IO`, `Mem`, `Str` |
| Files | `PascalCase.ax` | `IO.ax`, `Mem.ax` |
| Diagnostic codes | `AX` + stage number + 3 digits | `AX3001`, `AX5001` |

### Diagnostic codes

Every diagnostic carries a stable code in the format `AX{stage}{number}`:

| Range | Stage |
|---|---|
| `AX1xxx` | Lexical analysis |
| `AX2xxx` | Parsing / syntax |
| `AX3xxx` | Semantic analysis / type checking |
| `AX4xxx` | IR lowering, codegen, native toolchain |
| `AX5xxx` | Module / import resolution |

### Comments

- Use `;` for line comments in Axiom source.
- Use `//` for line comments in Rust source.
- Use `/* */` for block comments in Rust source.
- Document public APIs with comments that explain *why*, not just *what*.

---

## Adding a Diagnostic Code

When adding a new compiler error or warning, follow these steps:

1. **Add a `CodeInfo` entry** to the `registry!` macro invocation in `axiom-errors/src/code.rs` with the next free number in the appropriate `AX{1,2,3,4}xxx` range, a kebab-case slug, a one-line title, and a full explanation paragraph.

2. **Add or extend an error variant** in the owning crate (`axiom-lexer`, `axiom-parser`, or `axiom-sema`) and implement/extend `to_diagnostic()` to build a `Diagnostic` using the new code, a primary span, and a helpful suggestion.

3. **If the new error can be a downstream consequence** of another error in `axiom-sema`, prefer the poisoning pattern: return/propagate `TypeId::TError` from the failing check instead of a fresh placeholder, and guard every later comparison with `.is_error()` so a poisoned value never triggers a second, redundant diagnostic. See `EApp`/`EIf`/`ECond` in `axiom-sema/src/lib.rs` for the pattern.

4. **Add a test case** for the new diagnostic code.

5. **Verify** by running `cargo test --release --all` and confirming the new diagnostic fires correctly.

---

## Adding a Standard Library Function

The standard library is written entirely in Axiom — no C bindings needed. When adding a new stdlib function:

1. **Add it to the appropriate module** in `stdlib/` (e.g. `IO.ax`, `Mem.ax`, `Str.ax`, `Vec.ax`, `Map.ax`, `Fmt.ax`, `Intern.ax`, `Pre.ax`).
2. **Use `::` for the type signature** and `fn` for the definition.
3. **If the function performs I/O**, annotate it with `;@axiom:effect(io)`.
4. **If the function allocates memory**, note that memory comes from the backend's bump allocator and is reclaimed at process exit.
5. **Prefer the standard library primitives** (`__syscallN`, `__load8`/`__store8`, `__alloc`, `__addr`) over `foreign` bindings.
6. **Add a golden test** in `tests/stdlib/` with the `.ax` source and `.out` expected output.
7. **Update the module table** in `README.md` and `docs/reference.md`.

### Example: adding a new IO function

```scheme
; Print a string followed by a newline, but to stderr
(:: eprintln (-> Int Int))
;@axiom:effect(io)
(fn (eprintln s)
  {
    (writeStr stderr s)
    (writeStr stderr "\n")
  })
```

---

## The Agent-Facing Notation System

Axiom is built for agents as first-class users. Three notations make this possible:

### AXDL (Axiom eXchange Diagnostic Line)

One dense, colorless, greppable line per diagnostic. Used by `axiom --diagnostic-format=ai check`.

```
E AX3001 main.ax:6:4-9 undefined-variable "undefined variable `helpr`" ?6:4-9:"a similarly named binding `helper` is in scope; did you mean this?"~>"helper"
```

### AXSYM (Axiom eXchange Symbol Line)

One line per symbol, showing what a file declares and its type. Used by `axiom symbols`.

```
F add main.ax:11:5-8 "(Int -> (Int -> Int))"
D Maybe main.ax:3:7-12 "data Maybe" #ctors=Nothing,Just
```

### NID (Stable Node ID)

Content-derived hashes of `(kind, name)` that survive edits and reformatting, unlike line numbers. Every named declaration gets one automatically.

### AXTAG (Source-Embedded Agent Metadata)

` ;@axiom:<key>(<value>)` comments above declarations for agent-authored, compiler-checked intent.

When contributing, remember:
- All compiler messages go through `axiom_errors::Diagnostic` with a stable code, severity, span, and message.
- Never print raw strings from compiler phases.
- When adding a new diagnostic, update `axiom-errors/src/code.rs`, add the variant in the owning crate, and implement `to_diagnostic()`.
- Prefer poison propagation over ad-hoc cascade suppression.

---

## Contributor Guidelines

### Before you start

1. **Read the [README](README.md)** for the project overview.
2. **Read [docs/reference.md](docs/reference.md)** for the language reference.
3. **Read [docs/diagnostics.md](docs/diagnostics.md)** for the diagnostic and symbol notation system.
4. **Read [docs/v1-roadmap.md](docs/v1-roadmap.md)** for what's planned and what blocks what.

### Submitting a PR

1. **Fork the repository** and create a branch from `main`.
2. **Make your changes** — keep them focused on a single concern.
3. **Run the full test suite** locally before submitting:
   ```bash
   cargo test --release --all
   ./scripts/check-freestanding.sh
   ./scripts/check-cross-targets.sh
   ./scripts/check-reproducible.sh
   ./scripts/check-game-of-life.sh
   ```
4. **Format your code** — `cargo fmt --all`.
5. **Run lints** — `cargo clippy --all-targets --all-features -- -D warnings`.
6. **Write a clear commit message** that describes what you changed and why.
7. **Open a pull request** with a description of the change and any relevant context.

### PR Review

- All PRs require at least one review before merging.
- Reviewers will check that the change is correct, well-tested, and follows the project's conventions.
- If a review requests changes, address them and push additional commits to the same branch.

### Reporting Issues

When reporting a bug, please include:
- The Axiom source code that triggers the issue.
- The exact compiler output (use `--diagnostic-format=ai` for machine-readable output).
- The version of the compiler (`axiom --version`).
- The platform you're running on.

### Asking Questions

If you're unsure about how something works or where to make a change, open an issue or reach out in the project's discussion forum. The maintainers are happy to help!

---

## Resources

| Resource | Description |
|---|---|
| [README](README.md) | Project overview, installation, quick start |
| [docs/reference.md](docs/reference.md) | Comprehensive Axiom language reference |
| [docs/diagnostics.md](docs/diagnostics.md) | AXDL, AXSYM, NID, AXTAG notation reference |
| [docs/self-hosting.md](docs/self-hosting.md) | Plan to replace the Rust compiler with Axiom |
| [docs/v1-roadmap.md](docs/v1-roadmap.md) | Roadmap to v1 — what's done, what's left |
| [tree-sitter-axiom/](tree-sitter-axiom/) | Editor grammar for syntax highlighting |

---

## Implementation Status

| Feature | Status | Notes |
|---|---|---|
| Functions & types | **Complete** | Curried, polymorphic signatures, proper return values |
| Operators (prefix) | **Complete** | All arithmetic, comparison, logical |
| Let bindings | **Complete** | Variable resolution, sequential evaluation |
| if expressions | **Complete** | Proper branching with result values |
| begin blocks | **Removed** | Replaced by `{ }` brace blocks and implicit sequencing |
| brace blocks | **Complete** | Modern sequencing, returns last value |
| fn keyword | **Complete** | Modern alias for `define` |
| FFI | **Complete** | Call any C function with `foreign` declarations (stdlib no longer uses it) |
| Standard library | **Functional** | `Pre`, `Mem`, `Str`, `Vec`, `Map`, `Fmt`, `Intern`, `Sys`, `IO`, written in Axiom over syscall primitives |
| Syscalls | **Complete** | `__syscall0`-`__syscall6` on Darwin and Linux, x86-64 and AArch64 |
| Allocation | **Functional, unbounded** | `mmap`-backed bump allocator; no `free` |
| Cross-compilation | **Functional** | `--target` selects ABI and platform stdlib modules |
| Self-hosting | **In progress** | Foundations landed; see [docs/self-hosting.md](docs/self-hosting.md) |
| ADTs / data types | **Complete** | Constructors (nullary and with fields), recursive types, match exhaustiveness |
| Structs | **Complete** | Declarations, LLVM emission, field access, construction, `mut` fields, mutation |
| Pattern matching (`match`) | **Complete** | Constructor patterns, variables, wildcards, literals, nested patterns, exhaustiveness/arity diagnostics |
| Lambda | **Partial** | Parsed and type-checked; codegen pending |
| Lists | **Partial** | Syntax and type checking; runtime representation pending |
| Tuples | **Partial** | Syntax and type checking; codegen pending |
| Traits | **Complete** | Declarations, supertraits, effects, default methods, implementations (`impl`) |
| Effects | **Complete** | Effect declarations, `handle` expressions, effect checking, AXTAG validation, transitive inference |
| Loops | **Missing** | Iteration is recursion; `--opt 1`+ turns tail recursion into a loop |
| Linear types | **Parsed only** | `linear T`, `consume` — the ownership facts the memory model needs |
| Macros | **Complete** | Pattern-substitution expansion before sema with hygiene |
| Concurrency | **Delegated** | External/third-party library concern; memory model provides safety foundation |
| Editor support | **Functional** | Tree-sitter grammar with highlighting queries; no LSP yet |
| Imports | **Functional** | `(import Mod.Sub ...)` with transitive/diamond-safe resolution, qualified access |

---

Thank you for contributing to Axiom! Every contribution — from fixing a typo to adding a new language feature — makes the language better for everyone.
