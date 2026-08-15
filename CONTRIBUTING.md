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
./scripts/bootstrap-from-seed.sh --install .axiom-bin
```

The binary is at `./.axiom-bin/axiom`.

The compiler is written in Axiom, so building it needs a compiler.
`bootstrap/` holds its own LLVM IR, one file per target, committed;
the script turns the one matching your host into a *seed* with `llc`
and `cc`, compiles `self_host/` with it, and repeats until two
successive compilers are byte-identical. There is no Rust, and no
other toolchain, anywhere in that path — see `bootstrap/README.md`
for why the seed is allowed to lag the source and what stops it
drifting.

Every gate script provisions the same way if `$AXIOM` is unset, so
you can also just run one and let it build what it needs.

### Verify it works

```bash
echo '(import IO)
(:: main Int)
;@axiom:effect(io)
(fn (main)
  { (println "Hello from Axiom!")
    0 })' > hello.ax

./.axiom-bin/axiom run hello.ax
```

You should see `Hello from Axiom!` printed to the terminal.

---

## Project Structure

```
axiom/
├── self_host/          THE COMPILER, written in Axiom
│   ├── core.ax           tokens and spans
│   ├── lexer.ax          tokenizer
│   ├── parser.ax         S-expression parser, AST
│   ├── expand.ax         macro expansion, hygiene, expansion diagnostics
│   ├── typecheck.ax      name resolution, types, effects, AXTAG validation
│   ├── codegen.ax        IR and LLVM text emission, import resolution
│   ├── diag.ax           diagnostics, AXDL and JSON rendering, source maps
│   ├── render.ax         the human diagnostic renderer
│   ├── driver.ax         `build`: opt, llc, cc, and cleaning up after them
│   ├── main.ax           the CLI entry point and subcommand dispatch
│   ├── format.ax  repl.ax  symbols.ax  explain.ax  lsp.ax
│   └── Host.<target>.ax  the host triple and syscall ABI, chosen at compile time
├── bootstrap/          the compiler's own LLVM IR, one file per target — how a
│                       clean checkout builds a compiler with no compiler
├── stdlib/             standard library, in Axiom (Pre, Mem, Str, Vec, Map, Fmt,
│                       Intern, Sys, IO, Json, Rpc, Utf8)
├── tree-sitter-axiom/  editor grammar for highlighting and structural editing
├── tests/              stdlib/ diagnostics/ selfhost/ fmt/ repl/ lsp/ tools/
├── scripts/            the gates — each one is what CI runs, runnable locally
├── docs/               reference.md, memory-model.md, macro-system.md, diagnostics.md,
│                       self-hosting.md, v1-roadmap.md, macros.md
└── README.md
```

### Module dependency flow

Dependencies flow in one direction — no module knows about a downstream one:

```
core → lexer → parser → expand → typecheck → codegen → driver → main
```

- The lexer must not know about types.
- The parser must not know about effects.
- The emitter must not know about semantic analysis.

`diag.ax` sits beside all of them: every stage constructs diagnostics,
and none of them renders one.

---

## How the Compiler Works

Every Axiom program goes through this pipeline:

```
Source (.ax) → Lexer → Parser → Imports → Macro Expansion → Type Checker → IR → LLVM IR → llc → cc → Executable
```

1. **Lexer** (`self_host/lexer.ax`) — turns source text into tokens.
2. **Parser** (`self_host/parser.ax`) — turns tokens into an AST (S-expression tree).
3. **Expander** (`self_host/expand.ax`) — rewrites every macro invocation into
   its template, renaming the binders the template introduces so they cannot
   capture a caller's names. It runs *before* the checker, which is what makes
   everything a macro generates ordinary code as far as every later stage is
   concerned.
4. **Type checker** (`self_host/typecheck.ax`) — two-pass: collects declarations,
   then checks bodies. Propagates a poison type after a mismatch so one mistake
   draws one diagnostic.
5. **Emitter** (`self_host/codegen.ax`) — resolves imports, mangles names, and
   writes LLVM IR text.
6. **Driver** (`self_host/driver.ax`) — runs `opt`, `llc` and `cc`, and reports
   which of them failed rather than passing their errors through.

The compiler is a freestanding binary: it calls no libc function, and reaches
the operating system through syscalls it emits itself. That is why the host
target is chosen when the compiler is *compiled* (`Host.<target>.ax`) rather
than detected at run time — there is nothing to ask.

---

## Making Changes

### The development workflow

1. **Build** — `./scripts/bootstrap-from-seed.sh --install .axiom-bin`, once.
   After that, most gates rebuild the compiler under test themselves.
2. **Make your change** — edit the relevant file(s).
3. **Test** — run the relevant gates (see [Testing](#testing)). There is no
   single "run all the tests" command by design: each gate is a script, and
   the script is what CI runs.
4. **Commit** — write a clear, concise commit message that matches the
   project style. Read a few first: they are narrative, and they carry the
   measurement that justified the change.

Do **not** run `axiom fmt` over the repository. The tree is not kept in
the formatter's normal form, and the formatting gates check
behaviour-preservation on a copy rather than fixed-point-ness of the
tree.

### Where to make changes

The compiler is `self_host/`, written in Axiom. It is one program: a
change to the lexer and the gate that pins it are the same language and
the same build.

| What you want to do | Where to look |
|---|---|
| Add a new token | `self_host/core.ax` (the `TokenKind` list) + `self_host/lexer.ax` |
| Change lexing rules | `self_host/lexer.ax` |
| Add a new AST node | `self_host/parser.ax` (the `TAG_*` constants and `ASTNode`) |
| Change parsing rules | `self_host/parser.ax` |
| Change what a macro expands to, or add a template form | `self_host/expand.ax` |
| Add a type-checking rule | `self_host/typecheck.ax` |
| Change LLVM emission | `self_host/codegen.ax` |
| Add a CLI command | `self_host/main.ax`, and `self_host/driver.ax` for `build` |
| Add a diagnostic code | `self_host/diag.ax` at the construction site, plus `self_host/explain.ax` for its long-form text |
| Change how diagnostics look | `self_host/render.ax` (human) — AXDL and JSON are in `self_host/diag.ax` |
| Work on the formatter, REPL, `symbols`, or the language server | `self_host/{format,repl,symbols,lsp}.ax` |
| Add a stdlib function | `stdlib/` (e.g. `IO.ax`, `Mem.ax`, `Str.ax`, `Vec.ax`, `Map.ax`, `Fmt.ax`, `Intern.ax`, `Pre.ax`) |
| Add a new syntax feature | `tree-sitter-axiom/grammar.js` + parser + ast + lexer |

---

## Testing

Axiom has several layers of testing. Run them all before submitting a PR.

### There are no unit tests, and that is deliberate

The compiler is written in Axiom, and Axiom has no test-attribute
machinery. Every gate is a **shell script in `scripts/`** that runs the
real binary on real input and checks what came out — which is also
exactly what CI runs, so a contributor can reproduce any CI failure with
one command.

The consequence worth knowing: a gate can only see what it actually
compares. Several of these scripts used to compare the Axiom compiler
against the Rust one, and when that one was deleted the comparisons
would have silently become a compiler compared with itself — swept
everything, found nothing, exit 0. So each gate now carries at least one
assertion **derived from something other than the compiler's own
output**: the fixture's source bytes, a different golden file, or a
second implementation in Python. When you add a gate, add that half too,
and prove it by breaking the thing it should catch.

### Golden tests (stdlib)

The standard library has golden tests in `tests/stdlib/`. Each test is a pair of files:

- `NNN-name.ax` — the Axiom source
- `NNN-name.out` — the expected stdout
- `NNN-name.exit` — (optional) the expected exit status (default 0)

Run them:

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

1. **Grammar** — the tree-sitter grammar accepts every `.ax` file. It gates
   the rest because it is the one job that needs no compiler at all.
2. **Test** — the gate scripts, on three platforms (linux-x86_64,
   linux-aarch64, darwin-aarch64). Each job provisions a compiler from
   `bootstrap/` first.
3. **Cross-target** — IR assembles for all four targets
4. **Reproducible** — two runs produce identical IR
5. **Bootstrap from seed** — the load-bearing one: a clean checkout builds
   the compiler from `bootstrap/` with only `llc` and `cc`, and the ladder
   reaches `stage2 == stage3`. If this fails, the repository cannot be
   built at all, and a stale seed is the usual reason
   (`scripts/reseed.sh`).

### What the CI tests actually do

The tests compile and **run** Axiom programs rather than only type-checking them. This catches a class of bugs that a type-check-only CI would miss — for example, a syscall lowering that assembles correctly but returns the wrong value.

---

## Code Style and Conventions

### Formatting

- The repository is **not** kept in `axiom fmt`'s normal form, and running
  the formatter over it is a mistake that buries real changes in churn.
  The formatting gates check that formatting *preserves behaviour*, on a
  copy — not that the tree is already a fixed point.
- New files may be committed in hand style; the gates only need them to
  round-trip.
- Match the surrounding code. `self_host/` uses long explanatory comments
  above anything non-obvious, and they carry the measurement that
  justified the code. That convention is the project's main defence
  against re-litigating decisions.

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

- Use `;` for line comments in Axiom source. `#| ... |#` block comments
  exist and nest, but nothing in this tree uses one: a commented-out
  region is a region that no gate compiles, and the reason to reach for
  a block comment is almost always to keep code that should be deleted.
  This file used to claim there was no such thing, while `README.md` and
  `docs/reference.md` documented it and the lexer refused it — see
  `docs/self-hosting.md` §10.
- Document public APIs with comments that explain *why*, not just *what*.

---

## Adding a Diagnostic Code

When adding a new compiler error or warning, follow these steps:

1. **Pick the number** — the next free one in the appropriate range:
   `AX1xxx` lexical, `AX2xxx` parse, `AX3xxx` semantic, `AX5xxx` module
   resolution.

2. **Construct it** with `mkDiag` (or `mkDiagFix` when the help is
   machine-applicable) at the site that detects the condition, in
   `self_host/lexer.ax`, `self_host/parser.ax`, or
   `self_host/typecheck.ax`. It needs a severity, the code, a kebab-case
   slug, a span, a message, and a help.

3. **Write its long-form text** into `self_host/explain.ax`, so
   `axiom explain AX....` answers. `check-tools-selfhost.sh` fails if a
   code the corpus emits has no entry — a new diagnostic cannot ship
   undocumented.

4. **If it can be a downstream consequence** of another error, poison
   rather than report: propagate the error type from the failing check and
   guard later comparisons, so one mistake draws one diagnostic. The
   existing sites in `typecheck.ax` show the pattern.

5. **Add a case** to `tests/diagnostics/` — `NNN-name.ax` plus its `.axdl`
   and `.human` goldens (`.axbad` if the case deliberately does not parse,
   because the formatter and grammar gates sweep every `*.ax` and require
   it to parse). Bless with
   `AXIOM_BLESS=1 scripts/check-diagnostics.sh NNN`.

6. **Prove the case is not vacuous**: build a compiler from before your
   change and confirm the new case FAILS against it. A golden blessed from
   the only implementation that has ever produced it proves nothing on its
   own.

---

## Adding a Standard Library Function

The standard library is written entirely in Axiom — no C bindings needed. When adding a new stdlib function:

1. **Add it to the appropriate module** in `stdlib/` (e.g. `IO.ax`, `Mem.ax`, `Str.ax`, `Vec.ax`, `Map.ax`, `Fmt.ax`, `Intern.ax`, `Pre.ax`).
2. **Use `::` for the type signature** and `fn` for the definition.
3. **If the function performs I/O**, annotate it with `;@axiom:effect(io)`.
4. **If the function allocates memory**, note that memory comes from the backend's bump allocator and is reclaimed at process exit.
5. **Reach the machine through the standard library primitives** (`__syscallN`, `__load8`/`__store8`, `__alloc`, `__addr`). There is no FFI: `foreign` was removed and reports `AX2004`.
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
- All compiler messages go through `self_host/diag.ax`'s `Diag` with a stable code, slug, severity, span, and message.
- Never print raw strings from compiler phases.
- When adding a new diagnostic, construct it with `mkDiag` at the site that detects it and write its long-form text into `self_host/explain.ax` — the tools gate fails if a code the corpus emits has no entry.
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
3. **Run the gates** locally before submitting. There is no single
   command; run the ones your change could affect, and
   `bootstrap-from-seed.sh` always:
   ```bash
   ./scripts/bootstrap-from-seed.sh     # the compiler still builds itself
   ./scripts/run-stdlib-tests.sh
   ./scripts/check-self-host.sh
   ./scripts/check-diagnostics.sh
   ./scripts/check-freestanding.sh
   ./scripts/check-cross-targets.sh
   ./scripts/check-reproducible.sh
   ```
   Check each one's **exit status**, not its printed output — a script
   that prints "1 failed" and is judged by a pipeline's tail reads as
   green.
4. **Write a clear commit message** that describes what was wrong, why it
   was invisible, what changed, and the numbers. Read a few first.
5. **Open a pull request** with a description of the change and any
   relevant context.

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
| [docs/memory-model.md](docs/memory-model.md) | The memory model specification — reference counting chosen, rules MM-* |
| [docs/macro-system.md](docs/macro-system.md) | The macro system specification — rules MAC-* |
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
| FFI | **Removed** | `foreign` emitted a call to a symbol the module never declared, so it never linked. `foreign` stays reserved and reports `AX2004` |
| Standard library | **Functional** | `Pre`, `Mem`, `Str`, `Vec`, `Map`, `Fmt`, `Intern`, `Sys`, `IO`, written in Axiom over syscall primitives |
| Syscalls | **Complete** | `__syscall0`-`__syscall6` on Darwin and Linux, x86-64 and AArch64 |
| Allocation | **Functional, unbounded** | `mmap`-backed bump allocator; no `free`. The chosen end state is reference counting — [docs/memory-model.md](docs/memory-model.md) |
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
| Loops | **Complete** | `while` plus `mut` locals and `set`; self tail calls become loops in Axiom's own codegen at every `--opt` level, and mutual tail recursion is flattened by LLVM at `--opt 1`+ ([docs/memory-model.md](docs/memory-model.md) MM-EXEC-6b/6c). This row said "**Missing** — `--opt 1`+ turns tail recursion into a loop" long after both halves stopped being true |
| Linear types | **Parsed only** | `linear T`, `consume` — no longer the memory model's mechanism: deterministic reclamation comes from the chosen reference counting without them ([docs/memory-model.md](docs/memory-model.md) MM-LIFE-2a) |
| Macros | **Partial** | Substitution expansion before sema, hygienic in the binder direction, arity- and depth-checked. One positional parameter list per macro — no multi-rule patterns, no repetition; declaration macros and the query vocabulary exist since 2026-08-14 (rule-form `fn`/`::` generation; `syntax/join`/`constructors`/`fields`/`same`/`for`/`binders`/`fold` — enough for `deriveEq` over sums including fieldful constructors, `deriveLenses` over structs, and the `impl`-generating form with composing instances, verbatim from the spec: `tests/selfhost/374-derive-eq.ax`, `375-derive-lenses.ax`, `377-derive-eq-fieldful.ax`, `378-derive-eq-impl.ax`). The spec is [docs/macro-system.md](docs/macro-system.md); [docs/macros.md](docs/macros.md) is what is measured and what is not. This row read "**Complete** — Pattern-substitution expansion before sema with hygiene" until 2026-08-09, and every clause of it was false: expansion ran inside codegen *after* the checker, there was no hygiene of any kind, and there were no patterns |
| Concurrency | **Library** | `stdlib/Job.ax`: a bounded pool of child processes over `Sys`'s `sysSpawn`/`sysWaitPid`, submit-order results. No language support, no compiler change. Processes, not threads - a freestanding binary cannot create an OS thread on macOS |
| Editor support | **Functional** | Tree-sitter grammar with highlighting queries, and `axiom lsp` — lifecycle, full-text sync, `publishDiagnostics` and `documentSymbol` over JSON-RPC (`self_host/lsp.ax`, gated by `scripts/check-lsp-selfhost.sh`). Hover, completion and go-to-definition are not implemented. This row said "no LSP yet" until 2026-08-09, three commits after the server landed |
| Imports | **Functional** | `(import Mod.Sub ...)` with transitive/diamond-safe resolution, qualified access |

---

Thank you for contributing to Axiom! Every contribution — from fixing a typo to adding a new language feature — makes the language better for everyone.
