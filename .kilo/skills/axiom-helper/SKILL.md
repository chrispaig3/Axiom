---
name: axiom-helper
description: Guides for working with the Axiom compiler, ensuring correctness (proper diagnostic usage, AXTAG validation, exhaustive pattern matching), robustness (cascade suppression awareness, FFI safety, poison propagation handling), and productivity (quick reference commands, project structure, diagnostic code lookup, AXSYM symbol lookup).
---

# Axiom Helper — Agent Skill

## 1. Compiler invocation: always use `axiom diagnostics=ai`

Every Axiom compiler command must pass the AI-optimized diagnostic format:

```bash
axiom diagnostics=ai check source.ax
axiom diagnostics=ai build --input source.ax --output myprog
axiom diagnostics=ai symbols source.ax
axiom diagnostics=ai run source.ax
axiom diagnostics=ai emit-llvm source.ax -o output.ll
```

This is shorthand for `--diagnostic-format=ai` on every subcommand. It produces one dense, greppable, colorless AXDL line per diagnostic — no re-rendered source text, no ANSI codes, no Unicode box drawing. The `human` renderer is for human consumption only; use it only when `ai` output is insufficient.

## 2. Project structure at a glance

```
axiom/
├── axiom-ast/          # AST, token, and span definitions
├── axiom-lexer/        # Tokenizer
├── axiom-parser/       # S-expression parser (Lisp-style)
├── axiom-sema/         # Two-pass type checker (name resolution + effect analysis)
├── axiom-ir/           # IR definitions and generator
├── axiom-codegen/      # LLVM IR emitter
├── axiom-cli/          # CLI entry point, REPL
├── axiom-errors/       # Diagnostic types, rendering, code lookup, SymbolFact
├── hello_world/        # Sample program
├── docs/               # docs/diagnostics.md (AXDL/AXSYM reference)
├── Cargo.toml          # Workspace manifest
└── README.md
```

The compiler pipeline is always:

```
Source (.ax) → axiom-lexer → axiom-parser → axiom-sema → axiom-ir → axiom-codegen → LLVM IR → llc → cc → Executable
```

Cross-crate dependencies flow in one direction: lexer → parser → sema → ir → codegen. The lexer must not know about types; the parser must not know about effects; the codegen must not know about semantic analysis.

## 3. Correctness patterns

### 3.1 Validate AXTAG annotations

AXTAG metadata (`;@axiom:<key>(<value>)` comments above declarations) is compiler-checked. The most important validation is that `effect(io)` claims match actual foreign calls in the body, and `pure` claims match no foreign calls. Mismatches emit `AX3010` (`axtag-mismatch`).

When writing or reviewing Axiom source:
- Always pair `;@axiom:effect(io)` with actual `foreign` calls or `handle` expressions.
- Never annotate a function as `pure` if it calls a `foreign` function.
- Use `axiom diagnostics=ai symbols source.ax` to verify which AXTAG metadata was accepted (`#effect=io`, `#pure`, etc.).

### 3.2 Check pattern matching exhaustiveness

Axiom checks exhaustive pattern matching at compile time. Missing constructors and wrong-arity constructor patterns are compile errors (`AX3005` / `AX3009`). When writing `match` expressions, ensure every constructor of the matched type is covered.

```scheme
;; Correct: all constructors covered
(match val
  ((Nothing) default)
  ((Just x) x))

;; Incorrect: Missing Nothing arm — compile error AX3005
(match val
  ((Just x) x))
```

Nested constructor patterns are supported and checked recursively:

```scheme
(match lst
  ((Cons h (Cons h2 t)) ...)   ; correctly matches and binds h, h2, t
  ((Nil) ...))
```

### 3.3 Use stable diagnostic codes for pattern matching

Diagnostic codes are stable across wording changes. Never rename or reuse a code. Ranges are namespaced by compiler stage:

| Range | Stage |
|---|---|
| `AX1xxx` | Lexical analysis |
| `AX2xxx` | Parsing / syntax |
| `AX3xxx` | Semantic analysis / type checking |
| `AX4xxx` | IR lowering, codegen, native toolchain |
| `AX5xxx` | Module / import resolution |

Look up any code with `axiom explain AX3001` or see all codes with `axiom explain --list`.

### 3.4 Prefer Poison propagation over ad-hoc cascade suppression

When a type check fails, the checker propagates `TypeId::TError` rather than producing new diagnostics for every downstream use. `dedup` is a secondary safety net for diagnostics that are truly independent but logically related.

If you see multiple diagnostics sharing the same `group` key in `ai` output, only the first is the root cause — the rest are cascading consequences of the same root-cause error.

### 3.5 Never duplicate diagnostic logic across renderers

All compiler messages must go through `axiom_errors::Diagnostic` with a stable code, severity, span, and message. Never print raw strings from compiler phases. When adding a new diagnostic, update `axiom-errors/src/code.rs`, add the variant in the owning crate, and implement `to_diagnostic()`.

## 4. Robustness patterns

### 4.1 Understand AXDL parsing rules

AXDL lines follow this grammar:

```
<SEV> <CODE> <FILE>:<LOC> <SLUG> "<MESSAGE>" [^<LOC>:"<related>"]* [!<note>]* [?<field>]*
```

- `SEV` is one of `E` (error), `W` (warning), `N` (note), `H` (help)
- `LOC` is `file:line:col`, `file:line:col-col`, or `file:line:col-line:col`
- Slug is kebab-case and wording-independent
- Machine-applicable fixes use `~>` in the suggestion field

**Parsing pitfall**: `"msg"` and `"replacement"` are Rust `Debug`-style escaped strings. A correct consumer must parse each quoted field as a proper escaped string and only look for `~>` in the unquoted gap *between* fields — never do a naive `str.split("~>")`, which can misfire if `~>` appears inside the message itself.

### 4.2 FFI safety

Axiom has no standard library. All system operations are through FFI bindings declared with `foreign`:

```scheme
(foreign printf :: (-> String Int) = "printf")
(foreign malloc :: (-> Int (* Any)) = "malloc")
(foreign free :: (-> (* Any) ()) = "free")
```

When generating or reviewing FFI code:
- Verify C function signatures match exactly. Mismatched signatures are undefined behavior.
- Use `cc` to link additional libraries: `cc output.o -lcurl -lssl -lcrypto -o program`
- Sanitize file paths before passing them to native toolchain invocations (`llc`, `cc`). Never pass unsanitized user input to shell commands. Use `std::process::Command` with explicit argument vectors.

### 4.3 Memory safety discipline

Axiom uses manual memory control (`malloc`/`free`). The compiler itself must never introduce memory unsafety. All FFI calls must be wrapped in safe abstractions. In generated code, ensure that every `malloc` has a corresponding `free` path.

### 4.4 Handle input validation at every pipeline stage

All user-provided source files must be validated at every pipeline stage. A malformed input must produce a diagnostic, not a panic or segfault. The compiler must never execute arbitrary code from source files during compilation — code generation produces standalone LLVM IR; no runtime evaluation of user code.

### 4.5 Recognize cascade suppression vs. poison propagation

Two distinct mechanisms suppress cascading errors:
1. **Poison propagation** (type checker): `TypeId::TError` is propagated after a type mismatch; subsequent checks on a poisoned type are skipped via `is_error()` guards. This prevents the primary cascade.
2. **`dedup` with grouping** (`Diagnostic::with_group`): Suppresses truly independent diagnostics that are logically related to a root cause already reported. Use this only when poisoning cannot apply (e.g., diagnostics from unrelated compiler stages that share a root cause).

If you are adding a new diagnostic site and find yourself grouping multiple diagnostics together, prefer poisoning first. Only reach for `.with_group(...)` + `dedup()` when a concrete cascade exists that poisoning and `is_error()` guards cannot prevent.

## 5. Productivity patterns

### 5.1 Quick reference: common commands

```bash
# Check syntax and types (no code generation) — MUST use diagnostics=ai
axiom diagnostics=ai check source.ax

# Compile to native executable
axiom diagnostics=ai build --input source.ax --output program

# Emit LLVM IR to stdout
axiom diagnostics=ai emit-llvm source.ax

# Emit LLVM IR to a file
axiom diagnostics=ai emit-llvm source.ax -o output.ll

# Compile and run immediately
axiom diagnostics=ai run source.ax

# Start interactive REPL
axiom diagnostics=ai repl

# Look up a diagnostic code
axiom explain AX3001

# List all known diagnostic codes
axiom explain --list

# List every top-level symbol and its type (AXSYM notation)
axiom diagnostics=ai symbols source.ax

# Same, including always-in-scope built-in operators
axiom diagnostics=ai symbols source.ax --builtins

# Verify AXTAG annotations are accepted
axiom diagnostics=ai symbols source.ax | grep '@'
```

### 5.2 Use AXSYM to understand a codebase without re-reading it

`axiom diagnostics=ai symbols source.ax` produces one line per top-level declaration:

| KIND | Meaning |
|---|---|
| `F` | Function |
| `X` | Foreign binding |
| `D` | Data type |
| `C` | Constructor |
| `S` | Struct |
| `U` | Union |
| `A` | Type alias |
| `L` | Class (trait) |

Example output:

```
X printf main.ax:1:10-16 "(String -> Int)" #symbol=printf
F add main.ax:11:5-8 "(Int -> (Int -> Int))"
D Maybe main.ax:3:7-12 "data Maybe" #ctors=Nothing,Just
C Nothing main.ax:4:4-11 "Maybe" #of=Maybe
C Just main.ax:5:4-8 "(a -> Maybe a)" #of=Maybe
S Point main.ax:7:9-14 "struct Point" #fields=x:Int,y:Int
```

An agent asked to "add a function that formats a `Maybe Int`" can `grep '^D Maybe'` and `grep '^C '` for the exact constructor set and `grep '^X printf'` for the exact FFI signature, instead of re-reading the whole file.

### 5.3 Module imports resolution

Dotted module paths map directly to file paths relative to the entry file's directory:

```scheme
; Math/Ops.ax defines `square`
(import Math.Ops (square))    ; brings in only `square`
(import Math.Ops)             ; brings in every top-level decl
```

Key facts:
- Imports are transitive and diamond-safe (merged exactly once).
- There is no namespacing or qualified names — imported declarations join the flat top-level namespace.
- A module path that doesn't resolve to a real file is `AX5001`.
- Diagnostics from imported files are attributed to the actual file, not the entry file.

### 5.4 Common Axiom patterns

**Functions (modern `fn` style):**
```scheme
(:: add (-> Int Int Int))
(fn (add x y)
  (+ x y))
```

**Let bindings with sequential evaluation:**
```scheme
(fn (compute n)
  (let ((x (+ n 1))
        (y (* x 2)))
    (+ x y)))
```

**Brace blocks for sequencing:**
```scheme
{
  (printf "Starting...\n")
  (printf "Working...\n")
  0
}
```

**Foreign FFI declaration:**
```scheme
(foreign printf :: (-> String Int) = "printf")
```

**Algebraic data types:**
```scheme
(data Maybe (a)
  (Nothing)
  (Just a))
```

**Pattern matching:**
```scheme
(fn (fromMaybe default val)
  (match val
    ((Nothing) default)
    ((Just x) x)))
```

**Effects with AXTAG:**
```scheme
;@axiom:effect(io)
(fn main (printf "hello"))
```

### 5.5 REPL commands for rapid prototyping

```
:help / :h / ?        — Show all commands
:quit / :q / :exit    — Exit the REPL
:type <expr> / :t     — Show the type of an expression
:load <file> / :l     — Load a file into the REPL
:reset / :r           — Clear all definitions
:defs / :d            — Show all definitions in scope
:llvm <expr>          — Show the generated LLVM IR
:time <expr>          — Time an expression
```

The REPL compiles to native code, not interpretation. Definitions accumulate across inputs and history is saved between sessions.

### 5.6 Diagnostic code lookup workflow

When you encounter an error code in AXDL output:
1. Run `axiom explain AX####` (e.g., `axiom explain AX3001`) to get the full explanation.
2. If the explanation mentions a suggestion with a replacement, apply it programmatically — do not parse the English prose.
3. For cascade suppression: if multiple diagnostics share the same group key, fix only the first (root cause).
4. Verify the fix by re-running `axiom diagnostics=ai check source.ax` and confirming zero errors.

### 5.7 Testing and validation

- Unit tests live in the same file as the code they test, under `#[cfg(test)]` modules.
- Integration tests live in `tests/` directories within each crate.
- Every diagnostic code must have at least one test case.
- Use snapshot testing (`insta`) for renderer output to catch formatting regressions.
- Run `cargo fmt` before committing and `cargo clippy` treating warnings as errors.