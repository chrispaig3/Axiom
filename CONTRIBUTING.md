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

Prerequisites, the clone line and what to install on macOS and
Ubuntu/Debian are in [README § Installation](README.md#installation) —
that is the one copy. From a checkout, the whole build is:

```bash
./scripts/bootstrap-from-seed.sh --install .axiom-bin
```

The binary lands at `./.axiom-bin/axiom`, which is where every gate's
default `$AXIOM` looks. To run something with it, see
[README § Quick Start](README.md#quick-start).

The compiler is written in Axiom, so building it needs a compiler.
`bootstrap/` holds its own LLVM IR, one file per target, committed;
the script turns the one matching your host into a *seed* with `llc`
and `cc`, compiles `self_host/` with it, and repeats until two
successive compilers are byte-identical. Nothing else is needed on that
path — see `bootstrap/README.md` for why the seed is allowed to lag the
source and what stops it drifting. (`rust/` is a cargo workspace, but it
is the FFI's Rust side; no part of building the compiler reads it.)

Every gate provisions the same way when `$AXIOM` is unset, so you can
also just run one and let it build what it needs — that is `gate_init`
in `scripts/lib/gate.sh`.

---

## Project Structure

This is the one copy of the tree; README's structure section is the
short form of it.

```
axiom/
├── self_host/          THE COMPILER, written in Axiom
│   ├── core.ax           tokens and spans
│   ├── lexer.ax          tokenizer
│   ├── parser.ax         S-expression parser, AST
│   ├── namespace.ax      how a bare name reaches a declaration, and what `pub` lets out
│   ├── expand.ax         macro expansion, hygiene, expansion diagnostics
│   ├── typecheck.ax      name resolution, types, effects, AXTAG validation
│   ├── codegen.ax        import resolution, name mangling, LLVM text emission
│   ├── diag.ax           diagnostics, AXDL and JSON rendering, source maps
│   ├── render.ax         the human diagnostic renderer
│   ├── style.ax          the ANSI palette that renderer, and nothing else, uses
│   ├── driver.ax         `build`: opt, llc, cc, archives, and cleaning up after them
│   ├── rustbind.ax       the Rust module `--emit-rust-binding` writes for an archive
│   ├── main.ax           the CLI entry point and subcommand dispatch
│   ├── format.ax  repl.ax  symbols.ax  explain.ax  lsp.ax
│   └── Host.<target>.ax  the host triple and syscall ABI, chosen at compile time
├── bootstrap/          the compiler's own LLVM IR, one file per target — how a
│                       clean checkout builds a compiler with no compiler
├── stdlib/             standard library, in Axiom (Pre, Mem, Str, Vec, Map, Fmt,
│                       Intern, Sys, IO, Path, Json, Rpc, Utf8, Show, Err, Job,
│                       Ffi), plus Sys/Platform.<target>.ax
├── rust/               the FFI's Rust side, a cargo workspace: axiom-ffi,
│                       axiom-ffi-macros, axiom-ffi-classify, axiom-abi,
│                       axiom-bindgen, and examples/. Nothing in the compiler's
│                       own build path reads it
├── tree-sitter-axiom/  editor grammar for highlighting and structural editing
├── tests/              stdlib/ selfhost/ diagnostics/ frontend/ fmt/ repl/ lsp/
│                       tools/ ffi/ docs/
├── scripts/            the gates, and lib/gate.sh, the preamble they share
├── docs/               reference.md, memory-model.md, macro-system.md,
│                       diagnostics.md, error-model.md, ffi.md
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
and none of them renders one. `style.ax` sits beside `render.ax` alone,
and `diag.ax` does not import it — that is what keeps escape codes out
of AXDL, AXSYM and JSON. `namespace.ax` sits beside `expand.ax` and
`codegen.ax`, because both need the same answer about what a bare name
reaches and the import graph will not let either of them own it.

---

## How the Compiler Works

Every Axiom program goes through this pipeline:

```
Source (.ax) → Lexer → Parser → Imports → Macro Expansion → Type Checker → LLVM IR text → llc → cc → Executable
```

1. **Lexer** (`self_host/lexer.ax`) — turns source text into tokens.
2. **Parser** (`self_host/parser.ax`) — turns tokens into an AST (S-expression tree).
3. **Imports** (`self_host/codegen.ax`) — resolves each `(import M)` to a
   file, merges the declarations it exports, and mangles them to `M$name`.
4. **Expander** (`self_host/expand.ax`) — rewrites every macro invocation into
   its template, renaming the binders the template introduces so they cannot
   capture a caller's names. It runs *before* the checker, which is what makes
   everything a macro generates ordinary code as far as every later stage is
   concerned.
5. **Type checker** (`self_host/typecheck.ax`) — two-pass: collects declarations,
   then checks bodies. Propagates a poison type after a mismatch so one mistake
   draws one diagnostic.
6. **Emitter** (`self_host/codegen.ax`) — mangles names and writes LLVM IR
   text. There is no separate IR stage: the deleted Rust compiler had one,
   and nothing in `self_host/` does — `codegen.ax` goes from the checked AST
   to LLVM text directly.
7. **Driver** (`self_host/driver.ax`) — runs `opt`, `llc` and `cc`, and reports
   which of them failed rather than passing their errors through.

The compiler is a freestanding binary: it calls no libc function, and reaches
the operating system through syscalls it emits itself. That is why the host
target is chosen when the compiler is *compiled* (`Host.<target>.ax`) rather
than detected at run time — there is nothing to ask. A program *you* compile
is freestanding on the same terms unless it uses an `extern` block, which is
the one door out ([docs/ffi.md](docs/ffi.md)) and the one
`scripts/check-ffi.sh` prices.

---

## Making Changes

### The development workflow

1. **Build** — `./scripts/bootstrap-from-seed.sh --install .axiom-bin`, once.
   After that, most gates rebuild the compiler under test themselves.
2. **Make your change** — edit the relevant file(s).
3. **Test** — run the relevant gates (see [Testing](#testing)). There is no
   single "run all the tests" command by design: each gate is a script,
   and `.github/workflows/ci.yml` runs them by name.
4. **Commit** — write a clear, concise commit message that matches the
   project style. Read a few first: they are narrative, and they carry the
   measurement that justified the change.

Run `axiom fmt` over anything you touch. The tree is kept in the
formatter's normal form as of 2026-08-22 — `fmt --check` is clean on
the 482 `.ax` files in the repository apart from the two named below,
and, measured 2026-08-24, six more that were committed unformatted;
`axiom fmt --check` over every `.ax` file names them. No gate does:
`check-fmt-selfhost.sh` formats a COPY of the tree, so it fails when
formatting changes MEANING, not when a committed file has drifted out
of the normal form — and it fails if more than 60 files stop being
covered by `tests/fmt/corpus-fmt.golden`.

That 482 is recomputed, and recomputing it is why this paragraph was
rewritten. `check-doc-drift.sh` checks every count the normative
documents state, but until 2026-08-24 its `claim()` helper opened
README.md and nothing else — so the sentence above stood 28 files
stale while the README stated the right total four lines of gate away
and passed. Same claim, same class, one file swept. The helper reads
all nine documents `gate_prose_docs` lists now, this one among them,
and a count that goes stale here fails exactly as it fails there.
Which is also why the stale number is not spelled out in this
paragraph: the pattern it matches on is the numeral and its unit, not
one document's phrasing around it, so quoting the old sentence would
reintroduce the drift it describes — the same trap the gate's own
comments avoid by not naming the fixtures they were written for.

Two files are deliberately NOT formatted, and formatting them breaks
what they exist to test: `tests/fmt/syntax-zoo.ax` is the formatter's
input fixture, whose transformation into `syntax-zoo.expected.ax` is
the one golden that pins what the normal form looks like; and
`tests/diagnostics/940-long-line.ax` puts a diagnostic at column 217 of
a very long line, which is the renderer behaviour it pins.

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
| Change how a bare name reaches a declaration, or what `pub` lets out | `self_host/namespace.ax` — both `expand.ax` and `codegen.ax` ask it, which is why it is neither |
| Add a type-checking rule | `self_host/typecheck.ax` |
| Change LLVM emission | `self_host/codegen.ax` |
| Add a CLI command | `self_host/main.ax`, and `self_host/driver.ax` for `build` |
| Add a diagnostic code | `mkDiag` at the site that detects it — `lexer.ax`, `parser.ax`, `typecheck.ax`, `expand.ax`, `codegen.ax` or `driver.ax` — plus `self_host/explain.ax` for its long-form text |
| Change how diagnostics look | `self_host/render.ax` (human) and `self_host/style.ax` (its palette) — AXDL and JSON are in `self_host/diag.ax` |
| Work on the formatter, REPL, `symbols`, or the language server | `self_host/{format,repl,symbols,lsp}.ax` |
| Work on the Rust FFI | `self_host/rustbind.ax` and the crates under `rust/` — [docs/ffi.md](docs/ffi.md) |
| Add a stdlib function | `stdlib/` — `Pre`, `Mem`, `Str`, `Vec`, `Map`, `Fmt`, `Intern`, `Sys`, `IO`, `Path`, `Json`, `Rpc`, `Utf8`, `Show`, `Err`, `Job`, `Ffi` |
| Add a new syntax feature | `tree-sitter-axiom/grammar.js` + parser + ast + lexer |

---

## Testing

Axiom's tests are shell scripts in `scripts/`, one per property. Run the
ones your change could affect before submitting a PR. There is no single
"run everything" command, by design.

### There are no unit tests in the compiler, and that is deliberate

The compiler is written in Axiom, and Axiom has no test-attribute
machinery. Every gate is a **shell script in `scripts/`** that runs the
real binary on real input and checks what came out, so a contributor can
reproduce a CI failure with one command. (The one place ordinary unit
tests do exist is `rust/`, the FFI's Rust side: `axiom-ffi-classify`
carries 16, `axiom-bindgen` a snapshot suite, `axiom-ffi-macros` a
trybuild bank. `cd rust && cargo test` is their only runner.)

The consequence worth knowing: a gate can only see what it actually
compares. Several of these scripts used to compare the Axiom compiler
against the Rust one, and when that one was deleted the comparisons
would have silently become a compiler compared with itself — swept
everything, found nothing, exit 0. So each gate now carries at least one
assertion **derived from something other than the compiler's own
output**: the fixture's source bytes, a different golden file, or a
second implementation in Python. When you add a gate, add that half too,
and prove it by breaking the thing it should catch.

### Writing one

A gate opens with the preamble all of them share:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc
```

After that, `$repo_root` (the root, and the working directory), `$axiom`
(the compiler that *builds* the subject — `$AXIOM` when set, otherwise
`.axiom-bin/axiom`, bootstrapped from `bootstrap/` when it is not there
yet), `$work` (a temporary directory removed on exit) and `$axc` (the
compiler under test, built from `self_host/`) mean in your gate what
they mean in every other one. `scripts/lib/gate.sh` deliberately holds
nothing that runs the compiler, counts cases or reports results: those
differ per gate for real reasons, and a helper that unified them would
be a framework a reader had to learn before reading a single gate.

### The gates

`.github/workflows/ci.yml` runs all of these:

| Script | What it pins |
|---|---|
| `check-tree-sitter.sh` | the checked-in grammar parses every `.ax` file in the repository, and the documentation's Axiom blocks balance their delimiters (compiling them is `check-tools-selfhost.sh`) |
| `run-stdlib-tests.sh` | every case in `tests/stdlib` compiles, runs, prints its `.out` and exits as its `.exit` says |
| `check-freestanding.sh` | generated code needs no C library |
| `check-platform-constants.sh` | the syscall numbers the backend emits and the ones `stdlib/Sys/Platform.*.ax` declares are the same numbers, on all four targets - they disagreed silently once |
| `check-self-host.sh` | every case in `tests/selfhost` compiles, assembles, runs and exits as the fixture says — the only gate that drives the compiler end to end |
| `check-driver.sh` | `axiom build`: the command-line surface, and that a failing `llc` fails the build while a missing `opt` does not |
| `check-stdlib-selfhost.sh` | both corpora compiled *and run* through the identical `llc`/`cc` pipeline at `-O0` and `-O2` |
| `check-diagnostics.sh` | the AXDL corpus against its goldens, with every span recomputed from the fixture's own bytes |
| `check-degenerate.sh` | degenerate input answers with a diagnostic, not with a signal |
| `check-symbol-names.sh` | every name the frontend accepts is a name the backend can emit — all 94 printable bytes, in three positions |
| `check-stack-depth.sh` | how much stack the compiler needs for the largest Axiom program there is, bisected and reported |
| `check-concurrent-run.sh` | two `axiom run`s in one directory do not corrupt each other |
| `check-fmt.sh` | formatting a file does not change what it means: the tree formatted on a copy, with the suites re-run against it |
| `check-fmt-selfhost.sh` | the self-hosted formatter's bytes, exit statuses and refusals, over the corpus and a bank of deliberate refusals |
| `check-tools-selfhost.sh` | `explain` and `symbols` — including that every code the corpus emits has an `explain` entry |
| `check-render-selfhost.sh` | the human and JSON renderers, cross-checked against the AXDL goldens and against the palette `self_host/style.ax` declares |
| `check-repl-selfhost.sh` | the REPL, piped session by piped session |
| `check-lsp-selfhost.sh` | the language server's framed session bytes, and every published position converted into LSP's 0-based UTF-16 |
| `check-doc-drift.sh` | this file and its eight siblings against the tree: every stated count recomputed, and every fixture a doc or a comment names must exist |
| `check-agent-policy.sh` | the standard library performs exactly the effects it declares, and the set of declarations performing any is the one in `tests/agent/stdlib-effects.allow` — `docs/agent-harness.md` §3.4's policy, as a gate over AXSYM rather than a compiler mode, on `check-ffi.sh`'s allowlist model |
| `check-frontend-parity.sh` | the frontend's five consumers agree — on the value, not only on the verdict |
| `check-memory-baseline.sh` | the managed Life probe holds RSS flat over 2000 generations where its unmanaged twin grows linearly |
| `check-cross-targets.sh` | every target's IR assembles from one host, at every `--opt` level, with no non-position-independent object |
| `check-bootstrap.sh` | the self-hosting fixpoint: `stage2 == stage3`, byte for byte |
| `check-reproducible.sh` | compiling the same source twice produces identical bytes |
| `bootstrap-from-seed.sh` | a clean checkout builds a working compiler from `bootstrap/` with nothing but `llc` and `cc` |

The rest of `scripts/` is not a CI step. `ci.yml` is the authority on
which scripts run there — read it rather than this table; what follows
was true on 2026-08-22:

| Script | Why it is not a CI step |
|---|---|
| `check-ffi.sh` | a real gate, and the one MM-FFI-5 requires: every FFI tier, and the symbols each one imports, priced against a per-crate `axiom-allow.txt`. It is also the only script here that needs `cargo`, which nothing else in the build path does. Run it before touching `extern`, `rust/` or the freestanding claim |
| `check-name-scale.sh` | a real gate: resolving a module's private names must cost no more than resolving its public ones. It asserts a ratio rather than a wall-clock bound, so it is not flaky on a shared runner. Run it before touching name resolution |
| `bench-compile.sh` | prints where a compile spends its time. A profile, not an assertion |
| `bench-datastructures.sh` | prints `Vec`, `Map` and `Intern` against the Rust equivalents. `--check` enforces the roadmap's "within 2×" criterion; unconditionally, a wall-clock threshold on a shared runner is a flaky test |
| `measure-memory-baseline.sh` | prints the before/after numbers the memory-model schedule is driven by |
| `reseed.sh` | a maintenance tool rather than a gate: it regenerates `bootstrap/` when the committed seed can no longer compile `self_host/` |

---

## CI/CD

Every push to `trunk` and every pull request runs
`.github/workflows/ci.yml`. Seven jobs, staged so that a cheap failure
is reported before an expensive one — the grammar job gates the other
six, because it is the only one that needs no compiler at all. Five of
them provision a compiler through the same composite action,
`.github/actions/provision`:

1. **Tree-sitter grammar** — the checked-in grammar parses every `.ax`
   file in the repository.
2. **Tests** — the gate battery above, on three platforms
   (linux-x86_64, linux-aarch64, darwin-aarch64). Each job provisions a
   compiler from `bootstrap/` first.
3. **FFI** — `check-ffi.sh` on linux-x86_64 and darwin-aarch64: the
   `extern` boundary opens exactly the symbols it declares, the
   generated bindings match a fresh generation, and the `rust/`
   workspace's own suites run (`cargo test`).
4. **Cross-target codegen** — every target's IR assembles from a single
   host, at `--opt` 0, 1 and 2, and all four committed seeds assemble.
5. **Self-hosting fixpoint** — `check-bootstrap.sh`: `stage2 ==
   stage3`, byte for byte, with the ladder rooted at the committed seed.
6. **Reproducible build** — two independent runs produce identical
   bytes.
7. **Bootstrap from seed** — the load-bearing one, on linux-x86_64 and
   darwin-aarch64: a clean checkout builds the compiler from
   `bootstrap/` with only `llc` and `cc`. If this fails, the repository
   cannot be built at all, and a stale seed is the usual reason
   (`scripts/reseed.sh`).

The `push:` trigger names `trunk`, which is this repository's only
branch.

### What the CI tests actually do

The tests compile and **run** Axiom programs rather than only type-checking them. This catches a class of bugs that a type-check-only CI would miss — for example, a syscall lowering that assembles correctly but returns the wrong value.

---

## Code Style and Conventions

### Formatting

- The repository **is** kept in `axiom fmt`'s normal form, with the two
  exceptions named above. It was not until 2026-08-22; the argument
  against was that formatting buries real changes in churn, and the
  answer is that it buries them once. `check-fmt.sh` still checks the
  property that matters more — that formatting *preserves behaviour*,
  by formatting a copy of the tree and re-running the suites against it.
- Format a new file before committing it. The gates need it to
  round-trip either way, but an unformatted file will show up as churn
  in whichever commit next touches it.
- Match the surrounding code. `self_host/` uses long explanatory comments
  above anything non-obvious, and they carry the measurement that
  justified the code. That convention is the project's main defence
  against re-litigating decisions.

### Naming conventions

| Item | Convention | Example |
|---|---|---|
| Functions | `camelCase` | `sysWriteFd`, `fmtInt`, `vecPush` |
| Types | `PascalCase` | `Maybe`, `Point`, `Console` |
| Constructors | `PascalCase` | `Nothing`, `Just`, `Cons` |
| Type parameters | single lowercase letter | `a`, `b`, `t` |
| Modules | `PascalCase` | `IO`, `Mem`, `Str` |
| Files | `PascalCase.ax` | `IO.ax`, `Mem.ax` |
| Diagnostic codes | `AX` + stage number + 3 digits | `AX3001`, `AX5001` |

### Diagnostic codes

Every diagnostic carries a stable code of the form `AX{stage}{number}`
and a wording-independent kebab-case slug. The range table, the slug
convention and the steps for adding a code are in
[docs/diagnostics.md](docs/diagnostics.md) — one home, because a range
table kept in two files drifts in one of them.

### Comments

- Use `;` for line comments in Axiom source. `#| ... |#` block comments
  exist and nest (`tests/selfhost/170-block-comment.ax`,
  `tests/diagnostics/335-axtag-in-block-comment.ax`), but no file in
  `self_host/` or `stdlib/` uses one: a commented-out region is a region
  that no gate compiles, and the reason to reach for a block comment is
  almost always to keep code that should be deleted.
- Document public APIs with comments that explain *why*, not just *what*.

---

## Adding a Diagnostic Code

The steps live in [docs/diagnostics.md § Adding a new
diagnostic](docs/diagnostics.md#adding-a-new-diagnostic), and only
there: pick the next free number in the range for the stage, construct
it with `mkDiag` (or `mkDiagFix` when the help is machine-applicable) at
the site that detects the condition, write its long-form text into
`self_host/explain.ax`, poison rather than cascade, and add a
`tests/diagnostics/` case with its `.axdl` and `.human` goldens.

Three things that document says once and that are worth knowing before
you start:

- **`explain.ax` is not optional.** `scripts/check-tools-selfhost.sh`
  cross-checks every code the corpus emits against `explain --list`, so
  a new diagnostic cannot ship undocumented.
- **A golden blessed from the only implementation that has ever
  produced it proves nothing.** `AXIOM_BLESS=1
  scripts/check-diagnostics.sh NNN` writes down what your compiler says;
  the assertion is that a compiler built from *before* your change fails
  the case.
- **The construction site is not always the frontend.** `AX4001` is
  constructed in `self_host/main.ax`, `AX4002` in `self_host/codegen.ax`,
  `AX4003`–`AX4005` in `self_host/driver.ax`, and the macro codes
  `AX3018`–`AX3035` in `self_host/expand.ax`.

---

## Adding a Standard Library Function

The standard library is written entirely in Axiom, over syscall
primitives. When adding a new stdlib function:

1. **Add it to the appropriate module** in `stdlib/` — `Pre`, `Mem`,
   `Str`, `Vec`, `Map`, `Fmt`, `Intern`, `Sys`, `IO`, `Path`, `Json`,
   `Rpc`, `Utf8`, `Show`, `Err`, `Job`, `Ffi`.
2. **Use `::` for the type signature** and `fn` for the definition, with
   `pub` on both if the function is part of the module's surface.
3. **If the function performs I/O**, annotate it with
   `;@axiom:effect(io)`. Effects propagate transitively, so a caller
   that claims less than its callees do is a diagnostic, not a warning.
4. **If the function allocates**, declare the real field types. Every
   heap block carries a reference count and a shape word, and a block
   whose count reaches zero is freed along with whatever its reference
   map says it owned. That map is computed from the *declared* types, so
   a `String` stored through a field declared `Int` is invisible to
   release and leaks — a cast is not a style problem there
   ([docs/error-model.md](docs/error-model.md) `ERR-MEM-1`,
   [docs/memory-model.md](docs/memory-model.md)).
5. **Reach the machine through the primitives** (`__syscallN`,
   `__load8`/`__store8`, `__alloc`, `__addr`). The FFI is the `extern`
   block and it binds Rust, not libc ([docs/ffi.md](docs/ffi.md));
   `foreign` is not that feature under an old name and stays refused at
   `AX2004`.
6. **Add a golden test** in `tests/stdlib/` with the `.ax` source and
   `.out` expected output.
7. **Update the module table** in `README.md` and `docs/reference.md`.

### Example: adding a new IO function

```scheme
; Write a string to a descriptor and follow it with a newline.
; `println` and `eprintln` are macros over `syntax/formatln`; this is
; the plain function underneath them.
(pub :: writeLn (-> Int String Int))
;@axiom:effect(io)
(pub fn (writeLn fd s)
  {
    (writeStr fd s)
    (writeStr fd "\n")
  })
```

---

## The Agent-Facing Notation System

Axiom is built for agents as first-class users, and four notations carry
that:

- **AXDL** — one dense, colourless, greppable line per diagnostic, from
  `axiom --diagnostic-format=ai`.
- **AXSYM** — one line per symbol, showing what a file declares and its
  type, from `axiom symbols`.
- **NID** — a content-derived hash of `(kind, name)` that survives edits
  and reformatting, where a line number does not. Every named
  declaration gets one.
- **AXTAG** — `;@axiom:<key>(<value>)` comments above a declaration:
  agent-authored intent that the compiler then checks.

The grammars, the worked examples and the reasoning behind each are in
[docs/diagnostics.md](docs/diagnostics.md).

What that means when you are changing the compiler:

- Every compiler message goes through `self_host/diag.ax`'s `Diag`, with
  a stable code, slug, severity, span and message. Never print a raw
  string from a compiler phase: a phase that prints is a phase no format
  can render.
- Prefer poison propagation over ad-hoc cascade suppression.
- A new diagnostic needs its long-form text in `self_host/explain.ax`
  before it can ship — `scripts/check-tools-selfhost.sh` fails
  otherwise.

---

## Contributor Guidelines

### Before you start

1. **Read the [README](README.md)** for the project overview.
2. **Read [docs/reference.md](docs/reference.md)** for the language reference.
3. **Read [docs/diagnostics.md](docs/diagnostics.md)** for the diagnostic and symbol notation system.
4. **Read the [Implementation Status](README.md#implementation-status) table** for what is done and what is not. The roadmap that used to answer "what blocks what" was retired once its ordering had been spent; see [README § Roadmap](README.md#roadmap) for how to read it.

### Submitting a PR

1. **Fork the repository** and create a branch from `trunk`, which is
   this repository's only branch.
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
   ./scripts/check-platform-constants.sh
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
| [README](README.md) | Project overview, installation, quick start, and the implementation status table |
| [docs/reference.md](docs/reference.md) | Comprehensive Axiom language reference |
| [docs/memory-model.md](docs/memory-model.md) | The memory model specification — reference counting chosen, rules MM-* |
| [docs/macro-system.md](docs/macro-system.md) | The macro system specification — rules MAC-* |
| [docs/error-model.md](docs/error-model.md) | How a program signals failure — `Result`, `Error`, `try!`, rules ERR-* |
| [docs/diagnostics.md](docs/diagnostics.md) | AXDL, AXSYM, NID, AXTAG notation, the diagnostic-code ranges, and how to add a code |
| [docs/ffi.md](docs/ffi.md) | The `extern` block, `axiom-bindgen`, and what may cross the boundary |
| [tree-sitter-axiom/](tree-sitter-axiom/) | Editor grammar for syntax highlighting |

Two documents were retired on 2026-08-23, once what they recorded had
either landed or moved into a specification that a gate asserts. They
are history, not tree, and the compiler's comments still cite the second
by name as *the self-hosting record*:

```bash
git show d7622c2:docs/v1-roadmap.md     # roadmap to v1 — what's done, what's left, what blocked what
git show d7622c2:docs/self-hosting.md   # how the Rust compiler was replaced, stage by stage
```

---

## Implementation Status

The status table lives in [README § Implementation
Status](README.md#implementation-status), and only there. That is the
copy `scripts/check-doc-drift.sh` reads: every **Complete** row in it
must name a fixture under `tests/` that exists, and every count it
states is recomputed against the tree.

This file used to carry a second one. Two tables meant two answers to
the same question, the gate only ever read one of them, and the one it
did not read was the one that went stale.

---

Thank you for contributing to Axiom! Every contribution — from fixing a typo to adding a new language feature — makes the language better for everyone.
