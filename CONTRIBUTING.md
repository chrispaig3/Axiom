# Contributing to Axiom

This page takes you from a fresh clone to a tested change. It covers
building the compiler, how its source is laid out, running the tests,
and adding a diagnostic, a standard library function or documentation.

---

## Table of contents

1. [Quick start](#quick-start)
2. [Project structure](#project-structure)
3. [How the compiler works](#how-the-compiler-works)
4. [Making changes](#making-changes)
5. [Testing](#testing)
6. [CI/CD](#cicd)
7. [Code style and conventions](#code-style-and-conventions)
8. [Adding a diagnostic code](#adding-a-diagnostic-code)
9. [Adding a standard library function](#adding-a-standard-library-function)
10. [The agent-facing notation system](#the-agent-facing-notation-system)
11. [Contributor guidelines](#contributor-guidelines)
12. [Writing documentation](#writing-documentation)
13. [Resources](#resources)

---

## Quick start

Install the prerequisites and clone the repository as
[README § Install](README.md#install) describes. Then, from the
checkout, build the compiler:

```bash
./scripts/bootstrap-from-seed.sh --install .axiom-bin
```

The compiler lands at `./.axiom-bin/axiom`.
[README § Quick start](README.md#quick-start) shows how to run a
program with it.

That path is also where every gate looks for a compiler by default. A
*gate* is a check script in `scripts/` that CI runs: it tests one
property of the tree and fails the build when that property breaks.
When `$AXIOM` is unset and no compiler is there yet, a gate bootstraps
one the same way, so you can also just run a gate. That logic is
`gate_init` in `scripts/lib/gate.sh`.

The compiler is written in Axiom, so building it needs a compiler.
`bootstrap/` holds the compiler's own LLVM IR, one committed file per
target. The script turns the file for your host into a *seed* with
the native LLVM toolchain, compiles `core/` with the seed, and repeats until
two successive compilers are byte-identical.
[bootstrap/README.md](bootstrap/README.md) explains why the seed may lag
the source, and what stops it drifting.

You don't need Rust to build the compiler. `pkg/axiom-oxide/` is a cargo workspace
for the FFI's Rust side, and nothing in the compiler's build reads it.

After the clone, the build needs the checkout and your host's toolchain:
`llc` and `cc` on POSIX; Git Bash, `llc`, `llvm-dlltool`, `lld-link` and
`llvm-readobj` for the Windows link path. Windows installs as
`.axiom-bin/axiom.exe`. The seed directory lists the available inputs.

The build uses no network or published binary. The POSIX bootstrap has
reached a verified compiler in a container with networking disabled.
`scripts/check-offline-bootstrap.sh` audits the bootstrap and its three
helpers: `seed-sums.sh`, `imports.sh` and `seed-toolchain.sh` in
`scripts/lib/`. A new source dependency or network tool fails that check.

`scripts/install.sh` is the other way to get a compiler. It downloads a
prebuilt release archive, so it depends on a maintainer having
published one.

---

## Project structure

```text
axiom/
├── core/          the compiler, written in Axiom
│   ├── core.ax           tokens and spans
│   ├── lexer.ax          tokenizer
│   ├── parser.ax         S-expression parser, AST
│   ├── frontpack.ax      parsed syntax packets for process workers
│   ├── namespace.ax      how a bare name reaches a declaration, and what `pub` lets out
│   ├── expand.ax         macro expansion, hygiene, expansion diagnostics
│   ├── typecheck.ax      name resolution, types, effects, AXTAG validation
│   ├── checked.ax        sealed final-check handoff, the emitter's one way in
│   ├── raw.ax            the compiler's own raw memory layer, since a program
│   │                     cannot import the library's `Internal.Raw` (AX5002)
│   ├── codegen.ax        import resolution, name mangling, LLVM text emission
│   ├── diag.ax           diagnostics, AXDL and JSON rendering, source maps
│   ├── render.ax         the human diagnostic renderer
│   ├── style.ax          the ANSI palette used by that renderer and nothing else
│   ├── driver.ax         `build`: opt, llc, cc, archives, and cleaning up after them
│   ├── main.ax           the CLI entry point and subcommand dispatch
│   ├── format.ax  repl.ax  symbols.ax  explain.ax  lsp.ax
│   ├── doc.ax  markdown.ax  doccomment.ax
│   │                     `axiom doc`, its Markdown renderer, and the doc-comment rule
│   ├── replcomp.ax  replhist.ax  replhl.ax
│   │                     the REPL's completion, history and highlighting
│   ├── mir.ax  mireval.ax  the mid-level IR and its evaluator (test-only:
│   │                     no compiler module imports `mireval`)
│   ├── axir.ax  pkg.ax  build.ax
│   │                     the `.axir` record form, the package manifest, the build id
│   └── Host.<target>.ax  the host triple and syscall ABI, one file per
│                         target, chosen at compile time
├── bootstrap/          the compiler's own LLVM IR, one file per target, so a
│                       clean checkout can build a compiler without one
├── stdlib/             standard library, in Axiom (Pre, Mem, Str, Utf8, Vec,
│                       Map, Fmt, Err, Fallible, Intern, Sys, Path, IO,
│                       Cereal, Rpc, Task, Chan, Http, Test, Agent.Tags, Tui.Keys,
│                       Tui.Edit, Tui.Term), plus Sys/Platform.<target>.ax
├── pkg/                official standalone Axiom packages, libraries and tools
│   └── axiom-oxide/    the Rust FFI package: Axiom helpers, axiom-ffi,
│                       axiom-ffi-macros, axiom-ffi-classify, axiom-abi,
│                       axiom-bindgen, the axiom-oxide command and examples/.
│                       Nothing in the compiler's own build reads it
├── tree-sitter-axiom/  editor grammar for highlighting and structural editing
├── tests/              stdlib/ selfhost/ diagnostics/ frontend/ fmt/ repl/
│                       lsp/ tools/ ffi/ docs/ axir/ mir/ net/ region/
│                       replcomp/ ddc/ compat/ tailpos/ testrunner/ agent/
│                       embedded/ fuzz/ litmus/
├── scripts/            the gates, and lib/gate.sh, the preamble they share
├── docs/               the language reference, the status table, the
│                       specifications (memory-model.md, macro-system.md,
│                       error-model.md), guides such as diagnostics.md,
│                       ffi.md and lsp.md, and design records
├── examples/           complete programs, each one run in CI
├── compat/             the public surface each release published
├── embedded/           the linker script and reset code for baremetal-aarch64
├── web/                the project website
├── CHANGELOG.md
└── README.md
```

### Module dependency flow

Dependencies flow one way: no module knows about one downstream of it.
The shape is a DAG rather than a chain:

- `core` imports no compiler module. `lexer` imports `core`, and
  `parser` imports `lexer`.
- `expand` reads `parser` and `namespace`. `typecheck` reads `parser`.
- `codegen` reads `parser`, `namespace` and `expand`, with shared type
  queries from `typecheck`. Emission reads checked function types for
  numeric representation, alongside the AST and the mangled namespace.
- `checked` reads `typecheck` and `codegen`. The CLI and the REPL hand
  their final successful check to emission through a sealed
  `CheckedProgram`. Its `FunctionTypes` view carries checked types and
  definition arities into numeric lowering. The emitter has no other way in
  (`tests/tools/checked-program.py`).
- `driver` reads `parser` and `codegen`. `main` imports what the
  command line needs, and reaches `namespace` through `expand` and
  `codegen`. `mireval` stays outside that set.
- `symbols`, `axir`, `lsp` and the REPL modules (`repl`, `replcomp`,
  `replhist`, `replhl`) are side tools that read the stages above.
  They aren't links in the chain.

Three rules keep the stages apart:

- The lexer must not know about types.
- The parser must not know about effects.
- The emitter must not know about semantic analysis.

`diag.ax` sits beside all of them, because every stage but the lexer
builds diagnostics. `style.ax` is imported only on the human renderer's
path (`render.ax`, `repl.ax`, `replcomp.ax`, `replhl.ax` and
`main.ax`). `diag.ax` doesn't import it, which keeps escape codes out
of AXDL, AXSYM and JSON.

`namespace.ax` sits beside `expand.ax` and `codegen.ax`. Both need the
same answer about what a bare name reaches, and the import graph won't
let either of them own it.

---

## How the compiler works

Every Axiom program goes through this pipeline:

```text
Source (.ax) → Lexer → Parser → Imports → Macro expansion → Type checker → LLVM IR text → llc → cc → Executable
```

1. **Lexer** (`core/lexer.ax`) turns source text into tokens.
2. **Parser** (`core/parser.ax`) turns tokens into an AST, an
   S-expression tree.
3. **Imports** (`core/codegen.ax`) resolves each `(import M)` to a
   file, merges the declarations it exports, and mangles them to
   `M$name`.
4. **Expander** (`core/expand.ax`) rewrites every macro invocation
   into its template. It renames the binders the template introduces,
   so they can't capture a caller's names. It runs before the type
   checker, so to every later stage, whatever a macro generates is
   ordinary code.
5. **Type checker** (`core/typecheck.ax`) works in two passes: it
   collects declarations, then checks bodies. After a mismatch it
   propagates a poison type, so one mistake draws one diagnostic.
6. **Emitter** (`core/codegen.ax`) mangles names and writes LLVM
   IR text straight from the checked AST. A function whose whole body
   is one basic block of arithmetic can instead be emitted from the
   mid-level IR in `mir.ax`.
7. **Driver** (`core/driver.ax`) runs `opt`, `llc` and `cc`, and
   reports which of them failed rather than passing their errors
   through.

The compiler is a freestanding binary. It calls no C library function,
and reaches the operating system through syscalls it emits itself. So
the host target is chosen when the compiler is *compiled*
(`Host.<target>.ax`), not detected at run time: there is nothing to
ask.

A program you compile is freestanding on the same terms, unless it uses
an `extern` block. That is the one way out, described in
[docs/ffi.md](docs/ffi.md). `scripts/check-ffi.sh` checks that it opens
only what it declares.

---

## Making changes

### The development workflow

Keep `stable` ready to release and develop new work on `nightly`.
Start from the latest stable code, switch to `nightly`, and run the
relevant gates there before proposing a merge into `stable`.

1. **Build** once, with
   `./scripts/bootstrap-from-seed.sh --install .axiom-bin`. After that,
   most gates rebuild the compiler under test themselves.
2. **Make your change** in the relevant files.
3. **Test** by running the gates your change could affect (see
   [Testing](#testing)). Each gate is its own script, and
   `.github/workflows/ci.yml` runs each one by name.
4. **Commit** with a clear message in the project's style. Read a few
   first: they tell the story of the change, and carry the measurement
   that justified it.

Every `.ax` file in the tree is in `axiom fmt`'s normal form, and
`scripts/check-fmt.sh` keeps it that way. Run `axiom fmt` on each file
you change before you commit; `axiom fmt --check FILE` reports without
rewriting. The formatter keeps a form on one line when it fits in 100
columns, and breaks it when it doesn't, with each argument on its own
line two columns past the call's opening paren.

A few files are exempt because their layout is what they test: the
formatter's own inputs under `tests/fmt/`, the fuzz reproducers under
`tests/fuzz/`, the grammar's fixtures under `tree-sitter-axiom/`, the
generated bindings under `pkg/axiom-oxide/examples/` (section 1b of the same gate
holds those), and the files `tests/fmt/unformatted.list` names, each
with its reason. Leave `tests/fmt/parity/*.axp` and the `*.axbad`
refusal cases alone: they are inputs the formatter must refuse.

Use `.ax` for standalone compiler inputs. Source that needs a driver's
private modules or injected declarations belongs in an `.axp` file. Its
driver copies the bytes to a private `.ax`, checks the formatting and
compiles it in that context. Keep that driver in its gate so the input
still runs.

### Migrate local bindings and struct construction

Review a source migration before applying it:

```bash
python3 scripts/migrate-route-b.py --review path/to/Main.ax
python3 scripts/migrate-route-b.py --write path/to/Main.ax
axiom fmt path/to/Main.ax
```

The tool converts grouped bindings to block-local declarations and
positional struct construction to labelled fields. It preserves lexical
scope, comments and evaluation order. Add `-I path/to/modules` when imports
need another search directory.

An uncertain constructor or malformed source stops the file's migration.
Review those sites by hand. Explicit Markdown, Python, shell, Rust and
JavaScript files can supply embedded source; interpolated generators and
expected output need separate review.

### Where to make changes

The compiler lives in `core/` and is written in Axiom.

| What you want to do | Where to look |
|---|---|
| Add a new token | `core/core.ax` (the `TokenKind` list) and `core/lexer.ax` |
| Change lexing rules | `core/lexer.ax` |
| Add a new AST node | `core/parser.ax` (the `TAG_*` constants and `ASTNode`) |
| Change parsing rules | `core/parser.ax` |
| Change what a macro expands to, or add a template form | `core/expand.ax` |
| Change how a bare name reaches a declaration, or what `pub` lets out | `core/namespace.ax`, which both `expand.ax` and `codegen.ax` ask |
| Add a type-checking rule | `core/typecheck.ax` |
| Change LLVM emission | `core/codegen.ax` |
| Add a CLI command | `core/main.ax`, and `core/driver.ax` for `build` |
| Add a diagnostic code | `mkDiag` at the site that detects it: `parser.ax`, `typecheck.ax`, `expand.ax`, `codegen.ax` or `driver.ax` (the lexer reports through the parser). Add its long-form text to `core/explain.ax`. See [Adding a diagnostic code](#adding-a-diagnostic-code) |
| Change how diagnostics look | `core/render.ax` for the human report and `core/style.ax` for its palette. AXDL and JSON are in `core/diag.ax` |
| Work on the formatter, REPL, `symbols` or the language server | `core/{format,repl,symbols,lsp}.ax` |
| Work on the Rust FFI | `pkg/axiom-oxide/`: its Axiom helpers, Rust crates and `axiom-oxide` command. See [docs/ffi.md](docs/ffi.md) |
| Add a stdlib function | `stdlib/`: `Pre`, `Mem`, `Str`, `Utf8`, `Vec`, `Map`, `Fmt`, `Err`, `Fallible`, `Intern`, `Sys`, `Path`, `IO`, `Cereal`, `Rpc`, `Task`, `Chan`, `Http`, `Test`, `Agent.Tags`, `Tui.Keys`, `Tui.Edit`, `Tui.Term` |
| Add a new syntax feature | `tree-sitter-axiom/grammar.js`, plus the lexer and the parser and its AST |

---

## Testing

Axiom's tests are gates: shell scripts in `scripts/`, one per property.
Before you open a pull request, run the ones your change could affect.

### Reuse successful CI gates

GitHub CI keeps successful gate results for unchanged inputs for seven days.
It checks source files, fixtures, compiler binaries, toolchain versions and
runner images before reusing a result. Reviewed fixture boundaries let a
change to one suite preserve passes from unrelated suites. Other gates use
the whole tree, and compiler source changes invalidate every cached gate.

Passing gates are saved even when another gate fails. Failed gates run again;
the job summary names each reused pass and its original run. Bootstrap,
seed provenance, reproducibility and cache audits run fresh. Pull requests
can read the cache; only pushes to stable save results.

Local gate commands always run fresh. To bypass reuse when invoking
`scripts/ci-gate.py`, set `AXIOM_CI_FRESH=1`. Tested by
`tests/ci/gate-cache.py` through `scripts/check-ci-coverage.sh`.

<a id="there-are-no-unit-tests-in-the-compiler-and-that-is-deliberate"></a>
### Why the compiler has no unit tests

The compiler is written in Axiom, and Axiom has no test-attribute
machinery. Instead, every gate runs the real binary on real input and
checks what comes out, so you can reproduce a CI failure with one
command.

The one place with ordinary unit tests is `pkg/axiom-oxide/`, the FFI's Rust side.
`axiom-ffi-classify` has unit tests, `axiom-bindgen` a snapshot suite
and `axiom-ffi-macros` a trybuild suite. Run them with
`cd pkg/axiom-oxide && cargo test`.

A gate can only see what it compares, and a compiler compared with its
own output finds nothing. So every gate carries at least one assertion
derived from something other than the compiler's output: the fixture's
source bytes, a different golden file, or a second implementation in
Python. When you add a gate, add that half too. Then prove it works by
breaking the thing it should catch.

<a id="writing-one"></a>
### Writing a gate

A gate opens with the preamble they all share:

```bash
source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc
```

After that, these variables mean the same in your gate as in every
other one:

- `$repo_root` is the repository root, and the working directory.
- `$axiom` is the compiler that *builds* the subject. It is `$AXIOM`
  when that is set, otherwise `$AXIOM_AXC` when that names an
  executable, otherwise `.axiom-bin/axiom`, bootstrapped from
  `bootstrap/` if it isn't there yet.
- `$work` is a temporary directory, removed on exit.
- `$axc` is the compiler under test, built from `core/`.

`scripts/lib/gate.sh` holds nothing that runs the compiler on test
cases, counts cases or reports results. Those differ per gate for real
reasons, and a shared helper for them would be a framework you'd have
to learn before you could read a single gate.

### Which command runs what

- `scripts/run-gates.sh` runs every gate except
  `check-windows-hello.sh`, which needs arguments and a Windows runner.
  This is the `full` profile, and the default.
- `scripts/run-gates.sh --profile fast` runs the fast set: the thirty
  entries in `FAST_RE`, each measured at 15 seconds or less on a warm
  cache in a full run. Together they take about a minute, which suits
  edit-and-rerun checks. The set leaves out the two corpora, the
  diagnostics goldens, the formatter, LSP and tools sweeps, and the
  reclamation gates, which take one to five minutes each.
- `scripts/run-gates.sh --profile expensive` runs only the platform,
  bootstrap and measurement gates, for scheduled runs and release
  checks.
- `scripts/run-gates.sh --list` shows the split without running
  anything.
- Extra arguments select the gates whose names contain them, as in
  `scripts/run-gates.sh fmt lsp`.
- `scripts/check-gate-lib.sh` holds the profile lists to the tree:
  every name they spell must be a script that exists.

### The gates

`.github/workflows/ci.yml` runs every gate in this table. The table
isn't the full list: `scripts/run-gates.sh --list` prints them all.

Two words come up often below. A *golden* is a checked-in file holding
the output a case must produce. An *ablation* breaks one thing in a
copy of the compiler or its input and requires the gate to fail, which
shows the check can fail at all.

| Script | What it checks |
|---|---|
| `check-tree-sitter.sh` | The checked-in grammar parses every `.ax` file in the repository, and the Axiom blocks in the documentation balance their delimiters. `check-tools-selfhost.sh` checks whole programs and verifies displayed output where a `doc-gate:run` marker opts in. It needs the tree-sitter CLI (`npm install --prefix tree-sitter-axiom tree-sitter-cli`) and fails without it. Set `AXIOM_TREE_SITTER_OPTIONAL=1` to skip it instead (`tree-sitter-axiom/README.md`) |
| `check-vscode.sh` | The VS Code extension in `editors/vscode/` agrees with the compiler: its grammar's head-keyword alternation equals the set derived from `core/parser.ax`'s `kwEq` sites and `core/lsp.ax`'s `lspKeywords`, every semantic token type and modifier it maps is in the server's legend and every legend type is mapped, `package.json` states `VERSION`, the three JSON files parse, `extension.js` is JavaScript and `scripts/sync-keywords.mjs` is a fixed point. Needs `node` and no compiler. One ablation, required: a grammar missing `while` |
| `check-ci-coverage.sh` | Every `scripts/check-*.sh` in the tree is named on a `run:` line in `.github/workflows/ci.yml`, and every gate a step names exists. It reads `run:` lines rather than the whole file, because the workflow's comments name gates too, including deleted ones. It runs no compiler. Three ablations, all required: a step deleted, a step naming a script that isn't there, and an uncovered gate named only in a comment |
| `run-stdlib-tests.sh` | Every case in `tests/stdlib` compiles, runs with its `.in` file as standard input (`/dev/null` when it has none), prints its `.out` file and exits with the status its `.exit` file gives |
| `check-freestanding.sh` | Generated code needs no C library. On windows-x86_64 and windows-aarch64, where the runtime must import kernel32, every symbol the IR declares must be on `scripts/platform-allow.windows.txt`, a reviewed list that may not hold a libc name |
| `check-nostd-subset.sh` | The freestanding subset (`Pre`, `Mem`, `Str`, `Vec`, `Map`, `Fmt`, `Float`, `Utf8`, `Err`) is closed. Its transitive imports stay inside it and the library's internal modules, and none of them declares an `extern` block. A probe importing all nine imports nothing a hello world doesn't: linked imports on the host, IR declarations on every other supported target. Two planted breakages must each turn it red |
| `check-platform-constants.sh` | The syscall numbers the backend emits match the ones `stdlib/Sys/Platform.*.ax` declares on the six POSIX targets, and on windows-x86_64 and windows-aarch64 both halves reach the same kernel32 entry points. On every target, the two halves also agree on whether a syscall ABI exists at all. Host mocks check Windows time, paths, poller lifetime, buffered readiness and console controls; emitted runtime harnesses check reader cancellation, close and mode changes against the reference implementation |
| `check-terminal-restore.sh` | A program that puts a terminal into raw mode restores it byte for byte, on a pty the gate allocates itself. Two independent witnesses check it: the probe's own `memCmp` over all 72, 36 or 44 bytes (Darwin, Linux, FreeBSD), and `tcgetattr` from outside the process. Raw mode must change something first, `ISIG` must follow the caller's argument both ways, and a pipe and a bad descriptor must answer `ENOTTY` and `EBADF`. Four ablations, all required: restore a mutated copy, make raw mode a no-op, invert the `ISIG` argument, swallow the errno |
| `check-windows-entry.sh` | The Windows entry shim's command-line and environment parsers, cut out of the emitted Windows IR and run on the current host against known answers. Two rules are ablated, and each must make the harness disagree with the golden |
| `check-windows-hello.sh` | A Windows hello world, large stack frame, console input and console controls, for windows-x86_64 and windows-aarch64. `--emit` runs on any host. `--run` runs on a Windows runner: it assembles each program, links it with `lld-link` against import libraries `llvm-dlltool` generates for its machine, holds its imports to the allowlist, by name and by DLL, and runs the one for the runner's own architecture against its golden; it then links the compiler and runs it over the hello case, the tree audit and the standard-library battery, skipping the cases `tests/stdlib/windows-skip.txt` names. Console fixture imports have their own allowlist. The leaky `MessageBoxA` probe must be refused. `--link` does everything except run it, for a host that can't |
| `check-self-host.sh` | Every case in `tests/selfhost` compiles, assembles, runs and exits with the status on its first line (`; expect N`). This drives the compiler end to end, so it catches IR that `llc` rejects and code that assembles but computes the wrong answer |
| `check-driver.sh` | `axiom build`: the command-line surface, and that a failing `llc` fails the build while a missing `opt` doesn't |
| `check-stdlib-selfhost.sh` | Both corpora compiled and run through the same `llc`/`cc` pipeline at `-O0` and `-O2`, each case fed its `.in` or `/dev/null` as `run-stdlib-tests.sh` does. A `.in` that can't be read, or one with no matching case, fails before any compiler is built |
| `check-diverging-tyvar.sh` | `AX3040` is an error, and the analysis behind it tells a function that never returns from one that fabricates a value. Eight diverging spellings must be accepted and three fabricating ones refused. Changing one word of an accepted program, so the `(exit 70)` a cast wraps becomes the literal `70`, must get it refused |
| `check-vec-field-shape.sh` | A `Vec` field is a mapped reference, beside any `String` in the same record. When `fldClass` can't classify a field, the whole block falls back to the leaf shape and loses the reference map for its other fields, so a record holding a `Vec` would read shape word 8. Four rows, two of which must read a different number, so the checks can't pass vacuously |
| `check-region-scope.sh` | `(region r body)` is a checked scope (stage S2 of `docs/memory-model.md`). A program with no region emits no region cell. Four thousand 64 KiB regions, against the same body without `region`, must show a peak-RSS ratio of at least 8x. `631-region-escape.ax` and `630-region-name-shadowed.ax` draw exactly their `AX3059` and `AX3058` rows. The ablation makes `rgTyScalar` answer 1, rebuilds the compiler, and shows the refused store reading the next allocation's bytes |
| `check-region-escape.sh` | Lexical region origins through stores, callees, captures and loop back edges. Valid local calls run; escaping references are refused. Origin capacity and fixpoint completeness are enforced. An ablated reporter accepts unsafe stores and exposes reclaimed memory. Signature region annotations are refused by the checker and formatter |
| `check-type-pinning.sh` | A type placeholder that is bound stays bound, so a let-bound container can't be written at `Int` and read at `String`. Without it, `check` accepts that program with no `as` written, and it exits 139. There are two halves, because a checker that refused everything would pass the first: the unsound shapes are refused, and the correct ones are still accepted, including two containers pinned to different element types in one scope |
| `check-diagnostics.sh` | The AXDL corpus against its goldens, with every span recomputed from the fixture's own bytes |
| `check-degenerate.sh` | Degenerate input gets a diagnostic, not a signal |
| `check-symbol-names.sh` | Every name the frontend accepts is one the backend can emit: all 94 printable bytes, in three positions |
| `check-backtrace.sh` | A dying program names the frames it died in. The whole trace is checked byte for byte at `--opt 0`, every name is cross-checked against `nm` at every level, and the frame-pointer attribute is ablated per target |
| `check-dead-code.sh` | A program contains only what it uses. Every `define` a hello world emits is reachable from `main` by a walk the gate writes itself, and `nm` on the linked binary names nothing that walk can't reach. An address-taken callback (a bare reference through a thunk, or a comparator through a lifted lambda) survives and still works. With the pass off in a shadow tree, the binary check must go red and name the unreachable symbols |
| `check-stack-depth.sh` | How much stack the compiler needs for the largest Axiom program there is, found by bisection and reported |
| `check-tail-calls.sh` | A tail call runs in constant stack at `--opt 0`: a self call in every tail position, and a mutual call whose prototypes match, which the emitter marks `musttail`. Ten million alternating calls run under a 512 KiB stack, and the same IR with the marker deleted must die by signal. The two refusals, a mismatched prototype and an owned temporary, must stay plain calls, and the compiler's own IR must carry at least 300 marked sites |
| `check-concurrent-run.sh` | Two `axiom run`s in one directory don't corrupt each other |
| `check-fmt.sh` | Every `.ax` file outside the fixtures is already in `axiom fmt`'s normal form, and formatting doesn't change what a file means: the tree is formatted on a copy, and the suites are re-run against it. The bindings in `pkg/axiom-oxide/examples/*/axiom/*.ax` must also be fixed points of `axiom fmt`, because `pkg/axiom-oxide/axiom-bindgen/src/sexp.rs` restates the formatter's layout in Rust and `check-ffi.sh` only compares bindgen with itself. One ablation per binding adds two spaces to one indented line and must turn that check red |
| `check-fmt-selfhost.sh` | The self-hosted formatter's bytes, exit statuses and refusals, over the corpus and a bank of refusal cases |
| `check-tools-selfhost.sh` | `explain` and `symbols`, including that every code the corpus emits has an `explain` entry. It also compiles the Axiom programs in the documentation |
| `check-render-selfhost.sh` | The human and JSON renderers, cross-checked against the AXDL goldens and against the palette `core/style.ax` declares |
| `check-repl-selfhost.sh` | The REPL, one piped session at a time. The `150-axtag-shape` session checks that `;@axiom:` tag lines typed at the prompt are read, not dropped as comments, and that redefining a tagged function drops its old tag lines too. A `restrict(no-io)` typed at the prompt must then refuse a function that performs IO |
| `check-lsp-selfhost.sh` | The language server's framed session bytes, with every published position converted into LSP's 0-based UTF-16 and every answer derived from documents the driver writes itself. A sweep sends every advertised request at every kind of position, over a real module, a truncated one and an empty one |
| `check-stdlib-api.sh` | `docs/stdlib-api.md` is generated by `examples/axdoc/axdoc.ax`, an Axiom program, and this gate regenerates it and requires identical bytes. Every `(pub` name in `stdlib/` must appear there exactly once, the `Sys/Platform.*.ax` files must declare the same names, and a documentation-coverage ratchet applies. The module table in `docs/reference.md` and the Standard library row in `docs/status.md` must match the library too, names and spelled-out count together. The negative probes add a public name to a copy of the library, which the regenerated page must show, and drop a module from a copy of each document, which must turn that list red |
| `check-doc-drift.sh` | Every prose document `gate_prose_docs` lists in `scripts/lib/gate.sh`, this one included, against the tree: every stated count is recomputed, and every fixture a document or a comment names must exist |
| `check-agent-policy.sh` | The standard library performs exactly the effects it declares, and the set of declarations performing any is the one in `tests/agent/stdlib-effects.allow`. This is the policy from `docs/agent-harness.md` §3.4, run as a gate over AXSYM rather than as a compiler mode, on the allowlist model `check-ffi.sh` uses |
| `check-frontend-parity.sh` | The frontend's five consumers (`check`, `symbols`, `fmt`, the REPL's `:load` and the language server) agree on the value as well as the verdict. Worker parsing preserves complete syntax packets, source overlays, diagnostics, symbols and emitted IR |
| `check-embedded.sh` | The runtime assumptions an embedded port changes (`docs/embedded-guide.md` 4.1 to 4.3, and section 6): a per-target arena chunk size, pages from `mmap` or a static region, and a trap write that can be silenced. Every supported target must still emit the allocator it always did, and the minimal program imports only the platform's startup set and makes exactly 3 distinct syscalls. Variant compilers with rows of the target table changed must move only the lines those rows reach. With a 256 KiB static arena on the host, a program that fits must answer as the `mmap` build does, and one that outgrows it must exit 70 where the `mmap` build exits 0. A10 boots `tests/embedded/blink.ax` for `baremetal-aarch64` under QEMU: its UART bytes and exit status must match the host build, and an oversized twin must exit 70. It skips loudly when that target or QEMU is missing. `--ablations` requires every ablation to go red |
| `check-memory-baseline.sh` | The managed Life probe holds RSS flat over 2000 generations, where its unmanaged twin grows linearly |
| `check-cross-targets.sh` | Every target's IR assembles from one host, at every `--opt` level, with no object that isn't position-independent. `--self-test` runs the relocation rules against known input, so the gate's own verdict is tested too |
| `check-seed-provenance.sh` | The seed is the emission of source in this repository's history. Every declared seed is regenerated from the commit that last wrote the cohort and must come back byte-identical, after that commit's sources are checked against the hash in `bootstrap/STAMP`. It runs in its own CI job, because it needs the full history (`fetch-depth: 0`) and several minutes |
| `check-seed-lineage.sh` | The seed's ancestry, back to a compiler no Axiom seed touched. For every committed seed, `bootstrap/CHAIN` names the seed it reproduces from and how. The gate replays each row: the previous seed, built with `llc` and `cc`, compiles the next seed's tree, and the emission (or its re-emission) must equal the next seed byte for byte. The first row is the Rust compiler at `bb730db`. A `restore` row is checked instead of replayed: its whole `bootstrap/` tree must be an earlier row's, and `tests/bootstrap/seed-restores.py` holds that check to its controls. Seeds compare with the directory inside an `; axiom-asm-file` comment read as `<stdlib>`. `--replay-seed-link FROM SEED` replays one link and prints the row it measured. `--full` (the nightly job, or `AXIOM_LINEAGE_FULL=1`) replays every row and needs cargo. A default run replays the newest row and every row `bootstrap/CHAIN.checkpoint` doesn't certify. The checkpoint's digest is recomputed from `CHAIN` on every run, so a covered row that moved forces a full replay, and only `AXIOM_BLESS=1 ... --full` advances it. Five probes, each checked to have applied and each required red: one byte of the seed, a file name changed inside an `; axiom-asm-file` comment, the newest row's predecessor, one byte of the Rust anchor's codegen, and one byte of the `.ax` tree it compiles |
| `check-bootstrap.sh` | The self-hosting fixpoint: `stage2 == stage3`, byte for byte |
| `check-poisoned-alloc.sh` | Poisoned allocator generations emit identical compiler IR, and allocation remains zeroed |
| `check-reproducible.sh` | Compiling the same source twice produces identical bytes |
| `bootstrap-from-seed.sh` | A clean checkout builds a working compiler from `bootstrap/` with the native LLVM toolchain; the Windows link path uses Git Bash and checks PE architecture and imports |
| `build-shared-axc.sh` | Not an assertion, but the step the others rest on. It builds the compiler under test once and stamps it, and the ninety-seven gates that call `gate_build_axc` reuse it while the stamp matches the tree. It builds a second time and compares the IR both compilers emit, because those gates rely on the artifact being exactly what you would have built |
| `check-gate-lib.sh` | The shared artifact can't hide a source change. This is the probe that makes the reuse above safe to rely on |
| `check-install.sh` | The script `README.md` tells new users to pipe into bash. A release built from this tree is served over the loopback and installed. A tampered archive, one with no checksum and one with no `stdlib/` must each be refused. The gate's own probe deletes `install.sh`'s checksum comparison in a copy and requires the tampered case to stop being refused. Host tests check Windows preview inventories and shell dispatch; native Windows jobs run PowerShell rollback contracts and install the packaged compiler |
| `check-release-targets.sh` | What a release builds and what `install.sh` refuses are one fact split across two files. A target in both uploads an archive the installer won't fetch, and a target in neither gives the user a bare `curl` 404. It also keeps the two axes apart: nothing ships that README doesn't call supported, and nothing is supported but unshipped without a CI leg or a README paragraph saying why (`darwin-x86_64`) |
| `check-version.sh` | Every place the project states its own version agrees with `VERSION`, counted per site, and the built compiler prints it too |
| `check-build-id.sh` | A shipped binary names the tree it was built from, as well as its version. An unstamped build says `unstamped` rather than a plausible value, the id is a function of the source (one changed byte moves it), and the id `build-stamped.sh` computes is the one `axiom version` reports |
| `check-crypto.sh` | The cryptography suite's known-answer and negative tests in `tests/crypto/`, each compared with its golden output, and each run again against vectors with every expected value corrupted, which must make it fail |
| `check-net.sh` | A request handler bracketed as an arena scope holds worker RSS flat across ten thousand connections. The same binary without the scope must use at least 50 times as much |
| `check-examples.sh` | `examples/` holds only sources and static assets, none of them executable, and every program is named in `examples/README.md`, which `README.md` links to. Five ablations, all required: a planted build artefact, an `.ax` tracked as 100755, an empty file list, a program the table doesn't name, and a row naming a program that's gone. It runs no Axiom program and builds no compiler |
| `check-agent-calls.sh` | `symbols --calls`: no callee's effect escapes its caller, every inferred effect row carries a call edge, and every `IO` reaches a syscall or an `extern` |
| `check-mir-roundtrip.sh` | The `.axir` record file survives its own reader: emit, read back and emit again gives identical bytes over the stdlib corpus and `core/main.ax`, with no golden that could be re-blessed. A file written with doubled spaces must come back normalised, and the normal form must be a fixed point, which shows the reader decomposes lines rather than passing them through. Each `tests/axir/*.bad` fixture must be refused with a message, and the magic first line, not the file name, selects the reader in both directions. Its ablations include a writer that drops the nid, a reader that keeps raw lines, and an arm deleted from the kind table |
| `check-mir-projection.sh` | `symbols --mir`: the gate re-derives every `#mir-*` key itself from the raw region words of the matching `.axir` record, so it compares two independent derivations. Rows and records are matched in order on the whole header tuple, because the nid isn't unique across modules. Without `--mir` no row carries the key, and deleting every `#mir-*` token from the `--mir` stream gives the default stream byte for byte. `#mir-truncated` must be absent at call-chain depth 5 and at depth 60, where the escape must reach the first function's row; this is the one check in the tree that watches `rgnRounds`' round cap. Four ablations, all required. The silence ablation removes both guards, because the facts fixpoint runs only on demand |
| `check-restrictions.sh` | `;@axiom:restrict(...)` is a check, never a transformation. Restricting every `fn` of every accepted corpus program without an `extern` changes no emitted IR byte and no AXSYM row beyond `#restrict=`. It draws `AX3051` only on rows marked `#effects-incomplete`, `#effects-overapprox` or `#effect-params=` (a body that calls its own parameter leaves the answer to its caller). Satisfied restrictions are silent on every control, and each restriction goes red when its violation is planted in a copy (the `no-cast` plant at the cast's own span). A compiler whose `checkRestricts` answers nothing fails the fixtures, and every restricted declaration in the tree is on `tests/agent/restrictions.allow` with the compiler's verdict |
| `check-contracts.sh` | `;@axiom:pre(...)` and `;@axiom:post(...)` are checked. A violated contract exits 80, its own status among the trap statuses `MM-EXEC-16` reserves in `docs/memory-model.md`, and writes a line naming the kind, the function and the contract as written, at every `--opt` level. A satisfied contract answers what the same program with the tags deleted answers, and only modules that call `@__axiom_contract_fail` define it. `tests/diagnostics/385-contract-malformed.ax` draws seven `AX3050`s and nothing on its controls. A `pre` keeps the tail-call rewrite and a `post` spends it. Three ablations, each required: a compiler whose `expandProgram` lowers no contract, one whose `tcCheckFn` checks none, and one that lets a program's own `__contract` switch its contract off |
| `check-isr.sh` | `;@axiom:isr` marks an interrupt entry point. It takes no parameters (`AX3010`) and implies `no-alloc`, so an allocation draws `AX3049`; a typo such as `isrr` suggests it and fails the build (`AX3039`). With `--emit-staticlib`, a `pub` ISR beside a plain function archives both symbols, and an allocating one is refused. Two ablations, each required: the implication deleted, and an allocation planted in the good probe |
| `check-report.sh` | `scripts/axiom-report.py` (R-D1): the per-function resource report read off `symbols --calls` (allocation, IO, direct Unsafe use, `#extern`, recursion, calls the graph cannot follow, spawns and joins, kernel entries), the restricted profile's refusals RP-1..RP-7 over `tests/profile/` - each negative fixture refused by exactly the rule its name gives, conforming ones passing - and the stack bound computed from AArch64 machine code, held to the sum of its path's frames and to `llvm-readobj --stack-sizes`. Every rule ablated in a copy of the tool; the bound's cycle check ablated against the selftest and tree recursion |
| `check-ffi.sh` | Every FFI tier and the symbols each one imports, priced against a per-crate `axiom-allow.txt`, as MM-FFI-5 requires. It runs in its own CI job, on darwin-aarch64, because it needs `cargo` |
| `check-packages.sh` | `axiom.pkg`: a project's declared dependencies join the module search path after its own directory and before `$AXIOM_PATH`, and two dependencies providing one module are refused rather than ordered. Every project is built in the gate's work directory, and every module answers a distinct number, so the exit status shows which file the resolver chose. The negative probe removes the manifest and requires the same program to stop resolving |
| `check-name-scale.sh` | Resolving a module's private names costs no more than resolving its public ones, and doubling a module's declaration count costs under 3.0x rather than a scan's 4x. Both are ratios rather than wall-clock bounds, so a shared runner can't make them flaky. An ablated twin that scans must fail the doubling check |
| `check-type-namespace.sh` | A type name means what its own module says it means, whatever the import order, and finding that declaration costs a bucket lookup rather than a scan |
| `check-recover.sh` | Each of the three traps (out of memory, an unhandled effect, division by zero) recovers inside a recovery point and still stops the process outside one, at four optimisation levels. A hundred thousand aborts don't grow memory, against an ablated twin that must grow. Every aborted extent holds a `handle`, because the retain it abandons is the one thing the arena's wholesale reclaim doesn't cover |
| `check-container-reclaim.sh` | The reset-free half of the memory story: containers built and dropped in a loop must not grow. Each probe comes in two spellings one word apart, and the gate requires them to disagree by more than 5x, so a broken instrument can't pass |
| `check-test-runner.sh` | `axiom test`: a passing suite passes, every declared test is reported (checked against a list `grep` derives from the fixture's own bytes), and one failure ends one test and no other. The negative probe mutates each `assertEq` in the passing fixture in turn, and every mutant must exit 1 with a `FAIL` line |
| `check-arena-reset-rate.sh` | What an arena reset costs. Timing gates here assert ratios so that a slow runner can't fail them, so this one turns a rate into a ratio. One program in three spellings a word apart (reset, mark, neither) attributes the cost, and the emitted IR is read with no clock in the assertion. The negative probe deletes the `slabclear` block from the IR and rebuilds, so the two binaries differ only in the scrub |
| `check-steady-state.sh` | A long-running job reaches a measured steady state (P3 of the readiness plan): a bounded live set has bounded memory in a process that frees no container and resets no arena. It measures three magnitudes, because a plateau is what tells a steady state from a slope |
| `check-reclaim-soak.sh` | Reclamation and reuse under stress. A million-deep list, tree and closure chain are released whole under a 64 KiB stack; a reset-free soak of random sizes up to 60,000 bytes must plateau across three magnitudes; a dropped two-node cycle must cost exactly 64 bytes, and nothing inside an arena scope; resets across every size class, nested chunks and four threads must leave no stale list head; a trap inside a recovery point must leave its descriptors to the program and its children to the sweep. Five ablations, each required red: a recursive release walk, no size-class rounding, no list scrub on reset, one set of lists for every thread, and the recovery record back in the arena. `--long` adds ten million replacements |
| `check-fallible-reclaim.sh` | The block a call returning `Result` answers is reclaimed (ERR-MEM-4). Term 32 of `tests/stdlib/370-error-propagation.ax` is the flat line. This gate makes it evidence: it ablates `binderIsScalar` in `core/codegen.ax`, rebuilds the compiler from the ablated tree, and requires the fixture to fail at term 32 and at no other term |
| `check-static-release.sh` | No `axiom_release` is emitted for a static string literal: its `@strhdr_*` count word is the sentinel -1, so the call could never free anything. `isStaticSentinelNode` guards the two sites that release the literal itself, an argument position and a block-construction field store. `valueOwnedRef` still answers 1 for `TAG_E_STR`, so in `(if c "lit" (mkStr))` the other branch's share is still released, and the second assertion checks that. The compiler's own IR (`emit-llvm core/main.ax`) must hold no static releases. The ablation turns the predicate off for `TAG_E_STR`, rebuilds the compiler, and requires the count back in the thousands |
| `check-simd.sh` | What LLVM's vectorizer does with an Axiom loop, counted in the IR. `opt -O2` vectorizes a `for` over a `(Vec Int)` that only reads and a byte scan over a `String`, the driver's default `--opt 1` runs no vectorizer, and a Collatz `while` is the control that must not vectorize. The emitter change it holds is the trap runtime marked `noreturn cold` (`trapFnAttrs`), which keeps inlined copies of `vecGet`'s trap out of hot loops so the vectorizer accepts them. The ablation blanks the attributes, rebuilds the compiler and requires the copies back in the fixture's loop. A census over `core/main.ax` holds a ceiling of 2 trap copies and a floor on vectorized loops |
| `check-effect-fixpoint.sh` | The effect fixpoint's worklist: after the first round, only the callers of what grew are walked again, so an order that defeats both passes (`f2 f1 f4 f3 ...`, as a generator writes) doesn't cost a full walk per round. The check is a ratio (`swap/fwd <= 3`), so a slow runner can't fail it, and `symbols --calls` must match the ablated compiler byte for byte, since a wrong frontier shows up as a missing effect. The ablation makes `nextFrontier` mark every declaration dirty and must push the ratio back over 10 |
| `check-effect-argpos.sh` | `#effects-incomplete` marks an effect row as a lower bound, so a claim of absence over it draws a warning (`AX3037`, `AX3038`, `AX3051`) rather than a verdict. The mark follows the callee's declared argument position, not the argument's shape, because a value passed to an `Int` position can hide no effect. Generic `vecSortBy` and `vecSiftDownBy` retain `Mut` and `cmp` transparency while carrying the mark; the same bodies specialised to `Int` have complete rows. Four of the eight probe declarations are controls that must keep the mark: a type variable, an arrow position, a callee with one position of each, and a head that isn't a name. The ablation drops the type test from `escapeArgs`; the two rows must become lower bounds again, and the controls must not move |
| `check-thread-local.sh` | The emitted runtime's mutable globals (the allocator's words, the slab array, `@__axiom_recover_top`, one evidence slot per effect, and the `parallel` runtime's bookkeeping words) move to `thread_local(localexec)` in a program that spawns a thread by naming `__thread_spawn`, and in no other. `@__axiom_argc` and `@__axiom_argv` stay shared, because `@main`'s prologue writes them once. A program that spawns nothing gets no `thread_local` and imports no TLS or thread symbol, which matters on Darwin, where a thread-local access is an indirect call through `__tlv_bootstrap`. Assertion 5 requires no dynamic TLS resolver on either Linux target, and assertion 6 drops `(localexec)` and requires the resolver to appear (`__tls_get_addr` on x86-64, `tlsdesc` on AArch64) |
| `check-parallel.sh` | `parallel` has two lowerings, and a program can't tell which it got. `tests/stdlib/470-parallel.ax` and `471-parallel-trap.ax`, built as processes (the default) and as threads (`--threads`), answer the same bytes and exit status, the trap's 77 included, and a control binding exits 0. Under processes the join re-raises the child's status. Processes add no import over a program that spawns nothing; threads add exactly `pthread_create`, `pthread_join` and, on Darwin, `__tlv_bootstrap`. The runtime globals move under threads only, and `--threads` changes nothing where nothing spawns. `--threads` for freebsd-x86_64 is refused as `AX4006` before any IR is written, and windows-x86_64 emits and assembles with both primitives lowered to the status-79 trap |
| `check-handles.sh` | Typed handles (`MM-PAR-8`). A freed or forged channel or mutex, and a second free, exit 85 at every `--opt` and in both lowerings, without touching the object's unmapped pages. The handle table holds under four bindings at once, and exactly one of two racing frees returns. `build` and `build --threads` both refuse a captured unshared handle, and a record holding a handle maps as one holding an `Int`. Three ablations, each required: the table's check, the channel's retirement and the free's compare |
| `check-race.sh` | ThreadSanitizer finds the data races `--threads` programs can reach. Each program's IR is marked `sanitize_thread`, its `mmap` and `munmap` calls go through the C library so TSan sees the runtime's arenas, and it links with `clang -fsanitize=thread`. The unlocked control in `tests/litmus/sync-load.ax` must be reported. The mutex, a stale guard, the channel, `examples/concurrency/pipeline.ax` and the seq_cst rows of `tests/litmus/atomics.ax` must run clean at `--opt` 0 and 2. The one suppression in `tests/litmus/tsan-suppressions.txt` names MM-PAR-12's plain read in `sysWaitWordTimeout`: it must match, and runs without it must report that race and nothing else. Three ablations, all required: the mutex's compare-and-swap, the channel's lock, and an atomic add made plain. An ASan probe must report a read past a string literal. With no sanitizer runtime it skips, unless `AXIOM_TSAN_REQUIRED=1` |
| `check-protocol-model.sh` | Explores the channel, mutex and Task pool protocols at bounded sizes: exclusion, ordered delivery, deadlines, cancellation and checked spawn-refusal cleanup must hold, with every started child reaped. Planted defects must be detected with schedules. Source citations are checked against `stdlib/`, and recorded channel operations replay through the model. `tests/litmus/liveness.ax` measures starvation and distinguishes timed calls from untimed deadlock |
| `check-metamorphic.sh` | A declaration nothing uses changes nothing else. For every program the compiler accepts in `tests/stdlib`, `tests/selfhost` and `examples`, it appends unused functions named `a` to `z` and requires the same verdict, the same `symbols` row for every original declaration and the same IR for every original function (`scripts/lib/metamorphic.py`). Three compilers rebuilt with one name-resolution fix taken out must fail it. `--long` adds the compiler and the stdlib modules as entry files |
| `check-surface-agreement.sh` | The compiler's four doors agree about every diagnostics fixture: `check`'s diagnostics equal the language server's published ones (lints set aside), `build` refuses what `check` refuses with the same codes, and the REPL reports the same codes for every fixture small enough to type in. |
| `check-assurance-controls.sh` | The rule tables in `docs/assurance.md`, every table headed `Area`, `Refused as`, `A refusal` and `An acceptance`, are checked claims: each refusal path draws one of its row's codes, each acceptance path checks clean, and a missing path or a table with no rows fails. Three negative controls rebuild the compiler from a copy of `core/` with one enforcement removed, `AX3042`, `AX3010` and `AX3005` in turn, and require the refusal fixtures that name the code to be accepted by it. Every seam is counted before it is edited, so a reformatted seam fails rather than ablating nothing |
| `check-mir.sh` | The mid-level IR in `core/mir.ax`: SSA with block parameters instead of phis, a printer, and a verifier (one terminator per block, single assignment, branch arity, dominance). Goldens hold the printer, and a differential holds the meaning: each fixture, run by the real compiler and lowered and run by `core/mireval.ax`, must print the same bytes. No build emits from the IR: `axir.ax` and `mireval.ax` are its only importers, and `codegen.ax` must not import it. A floor on how much of `core/` and `stdlib/` lowers catches a subset that narrows itself. Each ablation must fire its own check; one breaks only dominance, so that rule is shown to fail |

The rest of `scripts/` doesn't run in CI. `.github/workflows/ci.yml` is
the authority on which scripts do, so check it rather than this table.

| Script | What it's for |
|---|---|
| `bench-frontend.sh` | Compares serial module lexing and parsing with bounded process workers. It checks ordered fingerprints and failure results before timing. Add `--ast-transfer` to compare direct serial parsing against workers including syntax transfer and reconstruction. `--phase-profile` measures encoding and reconstruction separately. Use `--jobs 1 2 4 --reps 5`, with `--json report.json` to save samples |

Command-line compilation can parse imported modules in worker processes.
Workers run by default with `check`, `build`, `run`, `emit-llvm` or
`symbols` once an import frontier reaches eight modules, on four
workers. A smaller frontier stays serial, because forking one module
costs more than parsing it. Set `AXIOM_FRONTEND_JOBS=1` to force the
serial path, or `2` through `8` to set the worker width. Workers read,
lex and parse independent modules; the parent restores their syntax
and resolves imports in the usual depth-first order. Expansion and
checking stay serial. An unavailable worker or an oversized syntax
packet falls back to parsing in the parent. Editor and REPL requests
keep serial resolution.

Tested by `tests/frontend/parallel/verify.py`.
| `bench-compile.sh` | Prints where a compile spends its time. It's a profile, not an assertion |
| `run-gates-linux.sh` | Runs the same gates on Linux, in a container, before CI sees them. The local battery is darwin-only, so this catches Linux-only gate defects early. It copies the tree into the container rather than bind-mounting it, because `gate_init` bootstraps into `$repo_root/.axiom-bin` and a Linux binary left there breaks the next darwin run. It asserts nothing, and `run-gates.sh` doesn't call it |
| `bench-datastructures.sh` | Compares `Vec`, `Map` and `Intern` against their Rust equivalents. `--check` enforces the "within 2×" bound; it's optional because a wall-clock threshold on a shared runner is a flaky test. `--fx` switches the Rust side to a fast hasher, which is the fair comparison against `stdlib/Map.ax`, so `./scripts/bench-datastructures.sh --fx --check` is the bound worth quoting. It prints a ratio only when both sides' work clears launch cost and ten times its jitter, raising the round count until it does. Otherwise it reports INCONCLUSIVE, and `--check` exits 3. Both sides' checksums must equal the closed form, and every hyperfine sample is kept (`BENCH_OUT`) |
| `measure-memory-baseline.sh` | Prints the before and after numbers that drive the memory-model schedule |
| `measure-coverage.sh` | Prints block and decision coverage of the compiler's object code over its own test corpora. A measurement, not an assertion: it fails only when the instrument itself is broken |
| `reseed.sh` | A maintenance tool. It regenerates `bootstrap/` with a generator built from the committed seed, never from a compiler of unrecorded ancestry, and appends the link to `bootstrap/CHAIN`. When the committed seed can't compile the tree, it stops and says so. `--bridge` records the link as one that still needs certifying |

---

## CI/CD

Every push to `stable` or `nightly`, and every pull request, runs
`.github/workflows/ci.yml`. Development lands on `nightly`; validated
changes merge into `stable`.
A change that touches only `web/` skips it, because the website has its
own workflow, `pages.yml`.

The jobs are staged so that a cheap failure shows up before an
expensive one. A `scope` job first works out whether the change is
documentation only. If it is, the Documentation gates job runs and
the platform jobs are skipped. Otherwise the grammar job runs first,
because it needs no compiler, and every other job depends on it. The
jobs that need a compiler get it through the same composite action,
`.github/actions/provision`.

1. **Tree-sitter grammar.** The checked-in grammar parses every `.ax`
   file in the repository.
2. **Tests.** The gate battery above, on linux-aarch64 and
   darwin-aarch64, the two supported targets. Four independent shards
   run on each target. Each provisions a compiler from `bootstrap/`
   first, and both Tests checks require every shard to pass.
   Successful gates are reused only when their input fingerprints match.
   No Tests leg runs on a source-only
   target (README's *Targets* section lists them).
   `scripts/check-release-targets.sh` refuses a target that is on the
   supported list and has an advisory (`continue-on-error`) leg.
   After the compiler builds, gates continue after a failed check.
   Each failure keeps the job failed. Cancelling a job stops the
   remaining gates.
3. **FFI.** `check-ffi.sh` on darwin-aarch64. The
   `extern` boundary opens exactly the symbols it declares, the
   generated bindings match a fresh generation, and the `pkg/axiom-oxide/`
   workspace's own suites run (`cargo test`).
4. **Cross-target codegen.** Every target's IR assembles from a single
   host at `--opt` 0, 1 and 2, and every committed seed assembles.
   This job also emits the Windows hello world, the compiler and the
   tree audit for the Windows targets (`scripts/check-windows-hello.sh
   --emit`), which two Windows legs then run: on `windows-2025`, the
   x86_64 hello, the compiler and the tree audit; on `windows-11-arm`,
   the same checks for aarch64. Both run the standard-library battery
   against `tests/stdlib/windows-skip.txt`. Both targets stay
   source-only until that list is empty. Each Windows leg also includes
   a committed-seed fixpoint check and a comparison with the host's
   cross-emission.
5. **Self-hosting fixpoint.** `check-bootstrap.sh` checks that
   `stage2 == stage3`, byte for byte, with the ladder rooted at the
   committed seed.
6. **Seed provenance.** `check-seed-provenance.sh` regenerates every
   declared seed from the commit that last wrote them. Each must come
   back byte-identical. It has its own job because it needs
   `fetch-depth: 0` and takes about five minutes.
7. **Reproducible build.** Two independent runs produce identical
   bytes.
8. **Bootstrap from seed**, on linux-x86_64 and darwin-aarch64, and on
   freebsd-x86_64 in a FreeBSD 14.4 VM on the Ubuntu runner
   (`vmactions/freebsd-vm`, pinned by SHA). A clean checkout builds the
   compiler from `bootstrap/` with only `llc` and `cc`. This is the job
   everything rests on: if it fails, nobody can build the repository.
   The usual cause is a stale seed, which `scripts/reseed.sh` fixes.
   For linux-x86_64 and freebsd-x86_64 it's the only leg: both are
   source-only, and `scripts/check-release-targets.sh` requires this
   job for each.
9. **Seed lineage.** `check-seed-lineage.sh` replays the rows of
   `bootstrap/CHAIN` that `bootstrap/CHAIN.checkpoint` doesn't certify,
   and always at least the newest one: the previous seed compiles the
   tree of the current seed and must reproduce it. It runs on every
   push or pull request that touches `bootstrap/`, and otherwise logs
   that it skipped. Every run recomputes the checkpoint's
   digest from `CHAIN`, and a covered row that moved voids it and
   forces the full replay. It has its own job because it needs
   `fetch-depth: 0`.

One more job, **Seed lineage (full)**, replays every row with `--full`,
with cargo installed for the Rust anchor. It runs only on the nightly
`schedule:` and on `workflow_dispatch`, and on those triggers it's the
only job that runs.

### What the CI tests actually do

The tests compile and run Axiom programs rather than only
type-checking them. That catches bugs a type-check-only CI would miss,
such as a syscall lowering that assembles correctly but returns the
wrong value.

### Cutting a release

Releases come from a second workflow, `.github/workflows/release.yml`,
which runs only when you push a `v*` tag. It's separate from `ci.yml`
because `ci.yml` runs on pull requests from anyone and holds
`permissions: contents: read`, while publishing a release needs a token
that can write. Keeping them apart lets the everyday workflow stay
read-only.

`ci.yml` doesn't run on tags, and nothing enforces the steps below, so
they're up to whoever cuts the release:

1. **Land the release commit on `stable` and let CI go green.** A tag
   points at a commit, and the gates run on the push, not on the tag.
   Tagging a commit whose CI is red or still running publishes a
   compiler nothing checked.
2. **Update `VERSION`, and every site that must agree with it, in that
   same commit.** `./scripts/check-version.sh` checks every site that
   `scripts/lib/version-sites.sh` lists, and fails if one disagrees or
   stops stating a version. It's quick, so run it locally first.
3. **Write the `CHANGELOG.md` entry**, under a heading that starts
   `## <version>` like the ones before it. `release.yml` publishes that
   section as the release notes, and stops if it's missing or empty.
   GitHub takes at most 125,000 characters, so a section over 120,000
   opens with a short highlights block ending at the line
   `<!-- release-notes: end of highlights -->`. The release then
   publishes the highlights and a link to the whole section, and stops
   if the line is missing. Credit contributors by their GitHub handle
   in the highlights as well as in their entries.
   `check-doc-drift.sh` checks the changelog like any other prose
   document.
4. **Don't stamp anything by hand.** `release.yml` builds the archive
   from the seed through the fixpoint, then has `stage3` build one more
   compiler with `scripts/build-stamped.sh`. The shipped binary reports
   the tree it came from beside its version, and the workflow refuses
   to publish one that says `(build unstamped)`.
5. **Tag and push:**

   ```bash
   git tag -a v0.2.0 -m "Axiom 0.2.0"
   git push origin v0.2.0
   ```

The workflow builds nothing until the tag, `VERSION` and the version
the freshly built compiler prints are the same string. It builds two
targets, `linux-aarch64` and `darwin-aarch64`, from the committed seed
rather than from `.axiom-bin/`, so the artifact comes out of the same
path a user's build takes. Before uploading, it unpacks each archive
somewhere else and compiles a program that imports the standard
library, calling the compiler by bare name on `PATH`.

Each archive includes `toolchain.json`: the source and seed digests,
compiler digest, exact tool versions and digests, runner image, and native
SDK or package versions. Release records require a clean checkout and a
compiler whose build stamp matches that source. CI also saves a record
for each supported target. These records identify the build inputs;
macOS linker UUIDs can still differ between linked executables.

Every source-only target (`darwin-x86_64`, `freebsd-aarch64`,
`freebsd-x86_64`, `linux-x86_64`) gets the same message from the
installer: no archive is published for it, and it points to the seed.
A binary for one of them would imply support that doesn't exist.

The Windows targets have CI preview ZIPs rather than published release
archives. `scripts/package-windows.py` packages the compiler that its
native job has executed, with its library, docs, source commit and
checksums. `scripts/check-windows-install.ps1` installs it from a path
containing spaces and checks an upgrade before the job uploads it.

`scripts/install.ps1` accepts a local ZIP, verifies its sidecar and exact
file inventory, and stages it under an owned prefix. Both the staged and
installed compiler build and run an `IO` program through bare `PATH`.
Failed switches restore the earlier installation. This preview path
does not change the release matrix or the supported-target list.

---

## Code style and conventions

### Formatting

- Every `.ax` file is in `axiom fmt`'s normal form, and `check-fmt.sh`
  fails on one that isn't. It also formats a copy of the tree and
  re-runs the suites against it, so formatting can't change behaviour.
- Format a new file before you commit it. The gates need it to
  round-trip either way, but an unformatted file shows up as churn in
  whichever commit next touches it.
- Match the surrounding code. `core/` puts long explanatory
  comments above anything non-obvious, and they record the measurement
  that justified the code. That's how the project avoids arguing the
  same decision twice.

### Naming conventions

| Item | Convention | Example |
|---|---|---|
| Functions | `camelCase` | `sysWriteFd`, `fmtInt`, `vecPush` |
| Types | `PascalCase` | `Maybe`, `Point`, `Console` |
| Constructors | `PascalCase` | `Nothing`, `Just`, `Cons` |
| Type parameters | single lowercase letter | `a`, `b`, `t` |
| Public library modules | `PascalCase` | `IO`, `Mem`, `Str` |
| Stdlib files | `PascalCase.ax` | `IO.ax`, `Mem.ax` |
| Compiler files | lowercase `.ax` | `lexer.ax`, `typecheck.ax` |
| Diagnostic codes | `AX` + stage number + 3 digits | `AX3001`, `AX5001` |

The module convention applies to reusable public libraries. Compiler
implementation modules keep lowercase names; example entry files may
use `Main.ax` or a descriptive lowercase name. Script filenames use
kebab-case, including Python modules loaded by path.

### Diagnostic codes

Every diagnostic carries a stable code of the form `AX{stage}{number}`
and a kebab-case slug that doesn't depend on the message's wording. The
range table, the slug convention and the steps for adding a code live
in [docs/diagnostics.md](docs/diagnostics.md), so there's only one copy
to keep up to date.

### Comments

- Use `;` for line comments in Axiom source, `;;` for the doc comment
  of the declaration below and `;;!` for a module's own doc comment at
  the head of its file ([doc comments](docs/reference.md#doc-comments)).
- `#| ... |#` block comments exist and nest
  (`tests/selfhost/170-block-comment.ax`,
  `tests/diagnostics/335-axtag-in-block-comment.ax`), but no file in
  `core/` or `stdlib/` uses one. A commented-out region is code no
  gate compiles, and it's usually code that should be deleted.
- Document public APIs with comments that explain *why*, not just
  *what*.

---

## Adding a diagnostic code

The steps are in
[docs/diagnostics.md § Adding a new diagnostic](docs/diagnostics.md#adding-a-new-diagnostic).
In short:

1. Pick the next free number in the stage's range.
2. Construct the diagnostic with `mkDiag` (or `mkDiagFix` when the help
   is machine-applicable) at the site that detects the condition.
3. Write its long-form text into `core/explain.ax`.
4. Poison rather than cascade.
5. Add a `tests/diagnostics/` case with its `.axdl` and `.human`
   goldens.

Three things worth knowing before you start:

- `explain.ax` isn't optional. `scripts/check-tools-selfhost.sh` checks
  every code the corpus emits against `explain --list`, so a new
  diagnostic can't ship undocumented.
- A blessed golden only records what your compiler says.
  `AXIOM_BLESS=1 scripts/check-diagnostics.sh NNN` writes it down. The
  real test is that a compiler built from *before* your change fails
  the case.
- The construction site isn't always the frontend. `AX4001` is
  constructed in `core/main.ax`, `AX4002` in
  `core/codegen.ax`, `AX4003`–`AX4005` in `core/driver.ax`,
  and the macro codes `AX3018`–`AX3035` in `core/expand.ax`.

---

## Adding a standard library function

The standard library is written entirely in Axiom, over syscall
primitives. To add a function:

1. **Add it to the right module** in `stdlib/`: `Pre`, `Mem`, `Str`,
   `Utf8`, `Vec`, `Map`, `Fmt`, `Err`, `Fallible`, `Intern`, `Sys`,
   `Path`, `IO`, `Cereal`, `Rpc`, `Task`, `Chan`, `Http`, `Test`,
   `Agent.Tags`, `Tui.Keys`, `Tui.Edit` or `Tui.Term`. That's the list
   the [Modules at a glance](docs/reference.md#modules-at-a-glance)
   table prints, in the same order.
2. **Use `::` for the type signature** and `fn` for the definition,
   with `pub` on both if the function is part of the module's surface.
3. **If the function performs I/O**, annotate it with
   `;@axiom:effect(io)`. Effects propagate transitively, so a caller
   that claims fewer effects than its callees is a diagnostic, not a
   warning.
4. **If the function allocates**, declare the real field types. Every
   heap block carries a reference count and a shape word, and a block
   whose count reaches zero is freed along with whatever its reference
   map says it owned. That map is computed from the *declared* types,
   so a `String` stored through a field declared `Int` is invisible to
   release and leaks. A cast there is a bug, not a style issue
   ([docs/error-model.md](docs/error-model.md) `ERR-MEM-1`,
   [docs/memory-model.md](docs/memory-model.md)).
5. **Reach the machine through the primitives**: `__syscallN`,
   `__load8`/`__store8`, `__alloc` and `__addr`. The FFI is the
   `extern` block, and it binds Rust, not libc
   ([docs/ffi.md](docs/ffi.md)). `foreign` isn't that feature under an
   old name; it's still refused with `AX2004`.
6. **Add a test.** Use a golden in `tests/stdlib/`, an `.ax` source
   with its expected `.out`, to pin every byte a program writes. Use a
   `test`-named function that `axiom test` discovers when you want to
   assert one value, so a failure names the fact that was wrong. Both
   kinds are gated. See [Testing](docs/reference.md#testing).

   A golden case is `NNN-name.ax` beside a required `NNN-name.out`.
   Three more files are optional, and both runners read them the same
   way:
   - `NNN-name.exit`: the expected exit status (0 without it).
   - `NNN-name.err`: the expected stderr, compared exactly up to a
     backtrace marker.
   - `NNN-name.in`: the program's standard input. Without it the
     program reads `/dev/null`, never the terminal the runner started
     from. A `.in` that exists but can't be read fails the case, and a
     `.in` with no `.ax` beside it fails the corpus check.

   Tested by `tests/stdlib/477-read-input.ax` and
   `tests/stdlib/478-read-input-empty.ax`.
7. **Update the module table** in `docs/reference.md`.

### The doc-comment convention

The library's comments are its API reference.
`examples/axdoc/axdoc.ax` turns them into
[docs/stdlib-api.md](docs/stdlib-api.md), and
`scripts/check-stdlib-api.sh` keeps that page byte-identical to its
output.

- A symbol's documentation is the `;;` lines of the comment block
  directly above its `(pub :: NAME TYPE)`, up to a `; ---` banner. It
  goes above the signature, not the `(pub fn ...)`, because the AXTAG
  goes there and the formatter keeps the two apart. Plain `;` lines in
  the same block are notes for maintainers: measurements, refusals and
  the reasons behind a shape. Hover, the reference and `axiom doc`
  leave them out.
- The first `;;` paragraph is the summary the reference prints, and a
  bare `;;` ends a paragraph. Write the sentence that tells a reader
  whether to open the file first.
- A module's own documentation is the `;;!` lines at the head of the
  file. The reference opens the module's section with them.
- Prose about a whole section goes inside the banner, between its two
  rules, not under it. `axiom fmt` deletes a blank line between two
  comment blocks, so a preamble under a banner joins the first
  declaration below it. With `;` notes that is harmless; with `;;`
  lines it becomes that declaration's summary.
- A blank Summary cell in the reference is an undocumented name.
  `check-stdlib-api.sh` counts them and ratchets the total, so a
  public name with no `;;` line above it moves a number that only a
  deliberate edit should move. `axiom doc --missing` lists them.

### Example: adding a new IO function

```scheme
; Write a string to a file and follow it with a newline.
; `println` and `eprintln` are macros over `syntax/formatln`; this is
; the plain function underneath them.
(pub :: writeLn (-> File String Int))
;@axiom:effect(io)
(pub fn (writeLn f s)
  {
    (writeStr f s)
    (writeStr f "\n")
  })
```

---

## The agent-facing notation system

Axiom treats agents as first-class users, and four notations serve
them:

- **AXDL**: one dense, colourless, greppable line per diagnostic, from
  `axiom --diagnostic-format=ai`.
- **AXSYM**: one line per symbol, showing what a file declares and its
  type, from `axiom symbols`.
- **NID**: a content-derived hash of `(kind, name)` that survives edits
  and reformatting, where a line number doesn't. Every named
  declaration gets one.
- **AXTAG**: `;@axiom:<key>(<value>)` comments above a declaration,
  recording intent that an agent wrote and the compiler checks.

The grammars, worked examples and reasoning for each are in
[docs/diagnostics.md](docs/diagnostics.md).

When you change the compiler:

- Send every compiler message through `core/diag.ax`'s `Diag`,
  with a stable code, slug, severity, span and message. Never print a
  raw string from a compiler phase, because no output format can render
  it.
- Prefer poison propagation over ad hoc cascade suppression.
- Give a new diagnostic its long-form text in `core/explain.ax`
  before it ships. `scripts/check-tools-selfhost.sh` fails otherwise.

---

## Contributor guidelines

### Before you start

1. Read the [README](README.md) for the project overview.
2. Read [docs/reference.md](docs/reference.md) for the language
   reference.
3. Read [docs/diagnostics.md](docs/diagnostics.md) for the diagnostic
   and symbol notation.
4. Read [docs/status.md](docs/status.md) for what's ready today, and
   [docs/roadmap.md](docs/roadmap.md) for what's left before 1.0.

### Submitting a PR

1. **Fork the repository** and create a branch from `nightly`.
2. **Make your changes**, focused on a single concern.
3. **Run the gates** locally before you submit. There's no single
   command, so run the ones your change could affect, and always run
   `bootstrap-from-seed.sh`:

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

   Check each one's exit status, not its printed output. A script that
   prints "1 failed" can look green if you only read the tail of a
   pipeline.
4. **Write a clear commit message**: what was wrong, why nothing caught
   it, what changed, and the numbers. Read a few recent ones first.
5. **Open a pull request** that describes the change and any relevant
   context.

### PR review

- Every PR needs at least one review before it merges.
- Reviewers check that the change is correct, well tested and follows
  the project's conventions.
- If a review asks for changes, push more commits to the same branch.

### Reporting issues

When you report a bug, include:

- the Axiom source that triggers it;
- the exact compiler output (`--diagnostic-format=ai` gives the
  machine-readable form);
- the compiler version (`axiom --version`);
- your platform.

### Asking questions

If you're unsure how something works or where a change belongs, open an
issue or ask in the project's discussion forum. The maintainers are
happy to help.

---

## Writing documentation

Every Markdown page follows the house style in
[`.claude/skills/docs-style/SKILL.md`](.claude/skills/docs-style/SKILL.md).
The rules that matter most:

- Write to the reader in short, plain sentences, and describe what's
  true now. History belongs in [`CHANGELOG.md`](CHANGELOG.md).
- Every Axiom example compiles. CI compiles each block that declares
  `main`, so run yours first.
- Keep the headings other pages link to, or put
  `<a id="old-anchor"></a>` above a renamed one.
- Keep the sentences, table rows and generated blocks that gates read.
  The style guide lists them.

Check a page before you commit it:

```bash
python3 scripts/lib/doc-style.py --axiom .axiom-bin/axiom path/to/page.md
```

---

## Trusted components

Every executable trusts the committed seed and its lineage, the
self-hosted compiler, the emitted allocator and trap runtime, LLVM's
optimiser and assembler, the linker, and any linked foreign code.
`bootstrap/STAMP`, `bootstrap/CHAIN` and their checks record the seed's
provenance. The host `opt`, `llc`, `cc` and linker come from `PATH`;
record their versions for a frozen application build. A generated
Rust binding also trusts its Rust compiler, crates and unsafe shims.
QEMU provides emulator evidence only.

The toolchain and the gate harness may introduce or miss defects.
`scripts/check-reproducible.sh` checks repeatability, and gate ablations
show that planted defects are detected. Neither establishes that every
accepted program compiles with the intended meaning.

## Verification evidence

The compiler's contract is the [language reference](docs/reference.md)
and [memory specification](docs/memory-model.md). Diagnostic, runtime,
formatting, bootstrap and target gates exercise it. The resource report
is checked by `scripts/check-report.sh`; model and fuzz checks are
`scripts/check-runtime-model.sh`, `scripts/check-protocol-model.sh`
and `scripts/check-fuzz.sh`. `scripts/measure-coverage.sh` measures
compiler block and decision coverage. It does not measure an
application, establish MC/DC or certify a tool. ThreadSanitizer sees
threads and globals; it cannot observe forked processes or the arena's
internal block bounds. Record passes, failures, skips and unverified
targets separately.

## Releases and support

Publish a version tag only after the stable CI run for that commit is
green. Record a defect with a reproducer and a regression before
closing it. [SECURITY.md](SECURITY.md) defines the supported release,
response window and private vulnerability channel. Earlier release
lines receive no fixes. Independent verification and application
approval remain the deploying organisation's work.

## Resources

| Resource | Description |
|---|---|
| [README](README.md) | Project overview, installation and quick start |
| [docs/reference.md](docs/reference.md) | The Axiom language reference |
| [docs/status.md](docs/status.md) | What's ready today, feature by feature, with the tests behind each row |
| [docs/memory-model.md](docs/memory-model.md) | The memory model specification: reference counting, rules MM-* |
| [docs/macro-system.md](docs/macro-system.md) | The macro system specification, rules MAC-* |
| [docs/error-model.md](docs/error-model.md) | How a program signals failure: `Result`, `Error`, `?`, rules ERR-* |
| [docs/diagnostics.md](docs/diagnostics.md) | AXDL, AXSYM, NID and AXTAG notation, the diagnostic-code ranges, and how to add a code |
| [docs/ffi.md](docs/ffi.md) | The `extern` block, `axiom-bindgen`, and what may cross the boundary |
| [docs/lsp.md](docs/lsp.md) | The language server: running `axiom lsp`, editor configurations, what each request answers and refuses, the semantic-token legend, and the cost rule |
| [tree-sitter-axiom/](tree-sitter-axiom/) | Editor grammar for syntax highlighting |

Two retired documents live only in git history. The compiler's
comments still cite the second one as *the self-hosting record*:

```bash
git show d7622c2:docs/v1-roadmap.md     # roadmap to v1: what's done, what's left, what blocked what
git show d7622c2:docs/self-hosting.md   # how the Rust compiler was replaced, stage by stage
```

---

## Implementation status

The status table is [docs/status.md](docs/status.md).
`scripts/check-doc-drift.sh` reads it: every **Complete** row must name
a fixture under `tests/` that exists, and every count it states is
recomputed against the tree.

---

Thank you for contributing to Axiom. Every contribution, from fixing a
typo to adding a language feature, makes the language better for
everyone.
