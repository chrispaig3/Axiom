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
│                       diagnostics.md, error-model.md, ffi.md, lsp.md
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
the 589 `.ax` files in the repository apart from the two named below,
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
all eleven documents `gate_prose_docs` lists now, this one among them,
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
| `check-tree-sitter.sh` | the checked-in grammar parses every `.ax` file in the repository, and the documentation's Axiom blocks balance their delimiters (compiling them is `check-tools-selfhost.sh`). It needs the tree-sitter CLI (`npm install --prefix tree-sitter-axiom tree-sitter-cli`) and **fails** without it rather than skipping — a gate that exits 0 when its checker is absent reports success without checking anything. Set `AXIOM_TREE_SITTER_OPTIONAL=1` to skip it deliberately (`tree-sitter-axiom/README.md`) |
| `run-stdlib-tests.sh` | every case in `tests/stdlib` compiles, runs, prints its `.out` and exits as its `.exit` says |
| `check-freestanding.sh` | generated code needs no C library; and on windows-x86_64, where the runtime must import kernel32, every symbol the IR declares is on `scripts/platform-allow.windows.txt`, a reviewed list that may not carry a libc name |
| `check-platform-constants.sh` | the syscall numbers the backend emits and the ones `stdlib/Sys/Platform.*.ax` declares are the same numbers on the six POSIX targets, and on windows-x86_64 the same kernel32 entry points; and on every target the two halves agree on whether a syscall ABI exists at all - they disagreed silently once |
| `check-terminal-restore.sh` | a program that puts a terminal into raw mode puts it back BYTE FOR BYTE - asserted on a pty the gate allocates itself, never on the caller's terminal, by two independent witnesses: the library's own `memCmp` over all 72/36/44 bytes, and `tcgetattr` from outside the process. The round trip is asserted together with its own precondition, that raw mode CHANGED something first, because a `sysTermRaw` that does nothing round-trips perfectly. ISIG is checked to follow the caller's argument both ways, and a pipe and a bad descriptor must answer ENOTTY and EBADF. Four ablations, all required: restore a mutated copy, stub raw mode to a no-op, invert the ISIG argument, swallow the errno |
| `check-windows-entry.sh` | the Windows entry shim's command-line and environment parsers, cut out of the emitted Windows IR and executed on THIS host against known answers, with two rules ablated to show the golden move |
| `check-windows-hello.sh` | `--emit` on any host, `--run` on a Windows runner: a hello world assembled, linked with `lld-link` against `llvm-dlltool`-generated import libraries, its imports held to the allowlist, and EXECUTED against its golden; the leaky `MessageBoxA` probe must be refused. `--link` does everything but execute, for a host that cannot |
| `check-self-host.sh` | every case in `tests/selfhost` compiles, assembles, runs and exits as the fixture says — the only gate that drives the compiler end to end |
| `check-driver.sh` | `axiom build`: the command-line surface, and that a failing `llc` fails the build while a missing `opt` does not |
| `check-stdlib-selfhost.sh` | both corpora compiled *and run* through the identical `llc`/`cc` pipeline at `-O0` and `-O2` |
| `check-diverging-tyvar.sh` | `AX3040` is an error, and the analysis that made that possible tells a function that never returns from one that fabricates a value. Eight diverging spellings must be accepted, three fabricating ones refused, and the accepted program with ONE WORD changed - the `(exit 70)` a cast wraps becoming the literal `70` - must be refused |
| `check-diagnostics.sh` | the AXDL corpus against its goldens, with every span recomputed from the fixture's own bytes |
| `check-degenerate.sh` | degenerate input answers with a diagnostic, not with a signal |
| `check-symbol-names.sh` | every name the frontend accepts is a name the backend can emit — all 94 printable bytes, in three positions |
| `check-backtrace.sh` | a dying program names the frames it died in: the whole trace byte for byte at `--opt 0`, every name cross-checked against `nm` at every level, and the frame-pointer attribute ablated per target |
| `check-dead-code.sh` | a program contains only what it uses: every `define` a hello world emits is reachable from `main` by a walk written in the gate, `nm` on the LINKED BINARY names nothing that walk could not reach, and an address-taken callback — a bare reference through a thunk, a comparator through a lifted lambda — survives and still answers. Turning the pass off in a shadow tree must name 361 of 397 symbols |
| `check-stack-depth.sh` | how much stack the compiler needs for the largest Axiom program there is, bisected and reported |
| `check-concurrent-run.sh` | two `axiom run`s in one directory do not corrupt each other |
| `check-fmt.sh` | formatting a file does not change what it means: the tree formatted on a copy, with the suites re-run against it |
| `check-fmt-selfhost.sh` | the self-hosted formatter's bytes, exit statuses and refusals, over the corpus and a bank of deliberate refusals |
| `check-tools-selfhost.sh` | `explain` and `symbols` — including that every code the corpus emits has an `explain` entry |
| `check-render-selfhost.sh` | the human and JSON renderers, cross-checked against the AXDL goldens and against the palette `self_host/style.ax` declares |
| `check-repl-selfhost.sh` | the REPL, piped session by piped session - including `150-axtag-shape`, which defines an IO-performing function at the PROMPT (impossible before 2026-08-31, because every `;@axiom:` line was discarded with the comment it looks like), redefines a tagged function ABOVE it so the stale claim would land on that IO function if the drop did not take the tag lines with it, and is then refused for a `restrict(no-io)` typed at the prompt |
| `check-lsp-selfhost.sh` | the language server: its framed session bytes, every published position converted into LSP's 0-based UTF-16, every request's answer derived from documents the driver writes itself, and a sweep of every advertised request at every kind of position over a real module, a truncated one and an empty one |
| `check-stdlib-api.sh` | `docs/stdlib-api.md` is generated - by `examples/axdoc/axdoc.ax`, an Axiom program - and this regenerates it and requires byte-identity, plus that every `(pub` name a `grep` finds in `stdlib/` appears in it exactly once, that the `Sys/Platform.*.ax` files declare the same names, and a documentation-coverage ratchet. Its negative probe adds a public name to a COPY of the library and requires the regenerated document to carry it |
| `check-doc-drift.sh` | this file and its ten siblings against the tree: every stated count recomputed, and every fixture a doc or a comment names must exist |
| `check-agent-policy.sh` | the standard library performs exactly the effects it declares, and the set of declarations performing any is the one in `tests/agent/stdlib-effects.allow` — `docs/agent-harness.md` §3.4's policy, as a gate over AXSYM rather than a compiler mode, on `check-ffi.sh`'s allowlist model |
| `check-frontend-parity.sh` | the frontend's five consumers agree — on the value, not only on the verdict |
| `check-memory-baseline.sh` | the managed Life probe holds RSS flat over 2000 generations where its unmanaged twin grows linearly |
| `check-cross-targets.sh` | every target's IR assembles from one host, at every `--opt` level, with no non-position-independent object. `--self-test` runs the relocation rules against known input, because a gate whose verdict is never tested is how a broken one goes unnoticed |
| `check-seed-provenance.sh` | the other half of the seed's story: it IS the emission of source in this history. All six seeds are regenerated from the commit that last wrote the six `.ll` files and must come back byte-identical, after that commit's sources are required to hash to `bootstrap/STAMP`. Its own CI job, because it needs `fetch-depth: 0` and about seven minutes |
| `check-seed-lineage.sh` | the seed's ancestry, back to a compiler no Axiom seed touched: `bootstrap/CHAIN` names, for every seed ever committed, the seed it reproduces from and how, and this replays it - the previous seed built with `llc` and `cc` compiles the next seed's tree and the emission, or its re-emission, must be the next seed byte for byte; the first row is the Rust compiler at `bb730db` reproducing the first seed. Every row under `--full` (the nightly job, with cargo, or `AXIOM_LINEAGE_FULL=1`); on a default run, the rows `bootstrap/CHAIN.checkpoint` does not certify and never fewer than the newest. The checkpoint carries the digest of the prefix it covers and the gate recomputes it from `CHAIN` on every run, so a covered row that moved voids it and forces the full replay; only `AXIOM_BLESS=1 ... --full` advances it, over rows that run replayed from the anchor. Its probes flip one byte of a copy of the seed, re-point the newest row at another predecessor, change one byte of the Rust anchor's codegen and one byte of the `.ax` tree it compiles - each must go red, and each is asserted applied first |
| `check-bootstrap.sh` | the self-hosting fixpoint: `stage2 == stage3`, byte for byte |
| `check-reproducible.sh` | compiling the same source twice produces identical bytes |
| `bootstrap-from-seed.sh` | a clean checkout builds a working compiler from `bootstrap/` with nothing but `llc` and `cc` |
| `build-shared-axc.sh` | not an assertion but the step the others rest on: it builds the compiler under test ONCE and stamps it, and the fifty-three gates that call `gate_build_axc` reuse it while the stamp matches the tree. It builds a second time and compares the IR both compilers emit, because "this artifact is what you would have built" is the claim fifty-three gates then rest on |
| `check-gate-lib.sh` | that the shared artifact cannot hide a source change - the probe that makes the reuse above safe to believe |
| `check-install.sh` | the script `README.md` tells a stranger to pipe into bash. A release built from this tree is served over the loopback and installed; a tampered archive, one with no checksum and one with no `stdlib/` must each be refused. Its own probe deletes `install.sh`'s checksum comparison in a copy and requires the tampered case to stop being refused |
| `check-release-targets.sh` | what a release BUILDS and what `install.sh` REFUSES are one fact split across two files on opposite sides of the project. A target in both uploads an archive the installer will not fetch; a target in neither gives the user a bare `curl` 404. Also holds the two axes apart: nothing is shipped that README does not call supported, and nothing is supported-but-unshipped without a CI leg or a README paragraph saying why (`darwin-x86_64`) |
| `check-version.sh` | every place the project states its own version says what `VERSION` says, counted per site, and the built compiler prints it too |
| `check-build-id.sh` | a shipped binary names the TREE it was built from, not only the version it promises: an unstamped build says `unstamped` and not a plausible value, the id is a function of the source (one changed byte moves it), and the id `build-stamped.sh` computes is the one `axiom version` reports |
| `check-net.sh` | a request handler bracketed as an arena scope holds worker RSS flat across ten thousand connections, against a floor of 50x over the same binary unscoped |
| `check-web.sh` | the same claim of a server that does a web server's work: `examples/web`, on `Html` and `Http`, answers every page and file byte for byte against responses the script writes by hand - the `<script>` a peer sent escaped in text and in an attribute, a PNG with NUL bytes whole, a traversal refused before the filesystem - and holds worker RSS flat across ten thousand page requests against a floor of 20x over the same binary unscoped. Four ablations, all required: a flipped byte in an expected page, the escaper bypassed, the path check compiled out, the arena switched off |
| `check-agent-calls.sh` | `symbols --calls`: no callee's effect escapes its caller, every inferred effect row carries a call edge, and every `IO` reaches a syscall or an `extern` |
| `check-restrictions.sh` | `;@axiom:restrict(...)` is a check and never a transformation: restricting every `fn` of 168 corpus programs changes no emitted IR byte and no AXSYM row beyond `#restrict=`, and draws AX3051 only on rows that justify the word - `#effects-incomplete`, `#effects-overapprox`, or `#effect-params=`, the third added on 2026-08-31 with the reading that a restriction over a body calling its own parameter is the caller's to decide; a satisfied restriction is silent on every control; each restriction goes red when its violation is planted in a copy, the `no-cast` plant at the cast's own span; a compiler whose `checkRestricts` answers nothing fails the fixtures; and every restricted declaration in the tree is on `tests/agent/restrictions.allow` with the verdict the compiler gave |
| `check-contracts.sh` | `;@axiom:pre(...)` and `;@axiom:post(...)` are checked, both halves. A violated contract exits **76** - its own status beside 70/71/72, the FFI's 73, 74's absent syscall ABI and 75's invalid arena mark - and writes a line naming the kind, the function and the contract as written, at every `--opt` level; a satisfied one answers exactly what the same program with the tags deleted answers; `@__axiom_contract_fail` is defined in every module, called only where a contract is; `tests/diagnostics/385` draws seven `AX3050`s and nothing on five controls; and the cost the design names is measured in both directions - a `pre` keeps the tail-call rewrite, a `post` spends it. Two ablations, both required: a compiler whose `expandProgram` lowers no contract fails section 1, and one whose `tcCheckFn` checks none fails section 4 |
| `check-ffi.sh` | every FFI tier and the symbols each one imports, priced against a per-crate `axiom-allow.txt`; the one MM-FFI-5 requires. Runs in its own CI job, on linux-x86_64 and darwin-aarch64, because it is the only gate that needs `cargo` |
| `check-packages.sh` | `axiom.pkg`: a project's declared dependencies join the module search path after its own directory and before `$AXIOM_PATH`, and two of them providing one module are REFUSED rather than ordered. Every project is built in the gate's work directory and every module answers a distinct number, so the exit status says which file the resolver chose; the negative probe removes the manifest and requires the same program to stop resolving |
| `check-name-scale.sh` | resolving a module's private names costs no more than resolving its public ones, and doubling a module's declaration count costs under 2.8x rather than a scan's 4x - both ratios rather than wall-clock bounds, so it is not flaky on a shared runner - paired with an ablated twin whose scan must fail the doubling arm |
| `check-type-namespace.sh` | a type name means what its own module says it means, whatever the import order - and finding out which declaration that is costs a bucket rather than a scan, which is why the semantics and the index landed together |
| `check-recover.sh` | each of the three traps recovers inside a recovery point and still stops the process outside one, at four optimisation levels, and 100,000 aborts do not grow memory - paired with an ablated twin that must grow, and with a `handle` inside every aborted extent because the retain it abandons is the one thing the arena's wholesale reclaim does not cover |
| `check-container-reclaim.sh` | the reset-FREE half of the memory story: containers built and dropped in a loop must not grow. Each probe ships in two spellings one word apart and the gate asserts they DISAGREE by more than 5x, so it cannot pass on a broken instrument |
| `check-test-runner.sh` | `axiom test`: that a passing suite passes, that every test declared is a test reported - against a list `grep` derives from the fixture's own bytes - and that one failure ends one test and no other. Its negative probe mutates every `assertEq` in the passing fixture in turn and requires each mutant to exit 1 with a `FAIL` line, because a test runner whose tests cannot fail is the defect a test runner exists to prevent |
| `check-arena-reset-rate.sh` | what an arena reset COSTS, which is the one measurement this repository had no gate for: every timing gate here asserts a ratio so a slow runner cannot fail it, which left rate uncovered. One program in three spellings a word apart attributes the cost - reset, mark, neither - and the emitted IR is read with no clock in the assertion at all. Its negative probe deletes the `slabclear` block from the IR and rebuilds, so the two binaries differ in the scrub and nothing else |
| `check-steady-state.sh` | the acceptance measurement above that one, and P3 stated so it can be falsified: a bounded LIVE SET has bounded memory in a process that frees no container and resets no arena. Three magnitudes, because a plateau is what tells steady state from a slope |
| `check-fallible-reclaim.sh` | the block a call returning `Result` answers is reclaimed - ERR-MEM-4, 32 bytes a call until 2026-08-25. `tests/stdlib/370-error-propagation.ax` term 32 is the flat line; this gate is what makes it evidence, by ablating `binderIsScalar` in `self_host/codegen.ax`, rebuilding the compiler from the ablated tree and requiring the fixture to go red at term 32 and at NO other term. `127 - 95 = 32`, so the one thing that moved is the one thing removed |
| `check-static-release.sh` | over half the release traffic in the compiler's own IR was calls that could not free anything, and the operand's definition said so at compile time: classifying every `axiom_release` site in `emit-llvm self_host/main.ax` (197,562 lines, 3,469 functions) by what DEFINES the value released put 5,762 of 10,849 - 53.1% - on a static string literal, whose `@strhdr_*` count word is the sentinel -1, so the call loads a count, compares it against -1 and returns. 5762 -> 5 now (the residue is release paths holding no AST node to ask), 10,849 -> 5,117 sites in total, emitted output byte-identical. NOT done by making `valueOwnedRef` answer 0 for `TAG_E_STR`: it answers 1 on purpose so `(if c "lit" (mkStr))` stays owned and the OTHER branch's share is still given back, and 0 there would silence this release and leak the join's - so `isStaticSentinelNode` is asked at the two sites that emit a release for a value that IS the literal, argument position and the block-construction field store, and assertion 2 goes red if the join stops giving its share back. The ablation turns the predicate's answer off for `TAG_E_STR`, rebuilds the compiler from the ablated tree and requires the count back in the thousands |
| `check-effect-fixpoint.sh` | the effect fixpoint re-walked every body every round, and a declaration order that defeats both of its passes at once - `f2 f1 f4 f3 ...`, a helper beside each of its callers, which is what a generator emits - cost 56s at n=8000 against 0.09s for the same call graph declared in order. Rounds 2+ now walk only the callers of what grew. A RATIO (`swap/fwd <= 3`) so a slow runner cannot fail it, `symbols --calls` byte-identical across the ablation because a wrong frontier is a missing effect rather than a crash, and the ablation itself - `nextFrontier` answering "every declaration is dirty" - required to bring the ratio back over 10, since assertion 1 would otherwise pass with the worklist deleted |
| `check-effect-argpos.sh` | `#effects-incomplete` marks a row as a LOWER bound, and a claim of absence over one cannot be answered - `AX3037`, `AX3038` and `AX3051` are all warnings for that reason. The mark used to fire on the ARGUMENT's shape rather than the CALLEE'S DECLARED POSITION, so `vecSiftDownBy` calling `(cmp (memGetWord d r) (memGetWord d k))` published the standard library's sort as a lower bound on the strength of two machine words its own signature calls integers, and `restrict(no-io)` over anything reaching it answered `cannot be checked`. Eight probe declarations, of which FOUR are controls that must keep the mark - a type variable, an arrow position, a callee with one position of each, and a head that is not a name - because deleting the mark outright would pass every other assertion; plus `vecSortBy`/`vecSiftDownBy` asserted in both directions (mark gone, row still `Mut` through a transparent `cmp`) so a walk that stopped reporting anything cannot pass. The ablation drops the type test from `escapeArgs` and requires the two complete rows to go back to lower bounds while all four controls stay put |
| `check-thread-local.sh` | the eight mutable globals of the emitted runtime - five allocator words, the 4,097-word slab array, `@__axiom_recover_top`, one evidence slot per effect - move to `thread_local(localexec)` under `cgThreads` and NOTHING else does (16 changed IR lines, eight globals, one line each side; `@__axiom_argc`/`argv` stay shared because they are written once in `@main`'s prologue). The half worth more is the OFF path: no `thread_local` at all and 0 undefined symbols, because on Darwin a thread-local access is an indirect call through `__tlv_bootstrap` - measured here at 1 undefined symbol on, 0 off. Local-exec is mandatory rather than preferred, so assertion 5 requires no dynamic TLS resolver on the three non-Darwin targets and assertion 6 drops `(localexec)` and requires the resolver to APPEAR - on both Linux targets, whose markers differ (x86-64 `__tls_get_addr` x13, AArch64 `tlsdesc` x160), which a gate grepping only for the first would have been half vacuous about |

The rest of `scripts/` is not a CI step. `ci.yml` is the authority on
which scripts run there — read it rather than this table; what follows
was re-derived against it on 2026-08-24. The two entries that used to
sit here, `check-ffi.sh` and `check-name-scale.sh`, are CI steps and
have moved up: the table said otherwise for two days because it was
written by hand and nothing compared it to the workflow.

| Script | Why it is not a CI step |
|---|---|
| `bench-compile.sh` | prints where a compile spends its time. A profile, not an assertion |
| `run-gates-linux.sh` | the same battery, the same scripts, on LINUX, before CI sees them. The local battery is darwin-only, which is how two Linux-only gate defects landed in two days — `check-thread-local.sh` asserting a Darwin fact as universal, and `check-steady-state.sh`'s symmetric band, which Darwin's 16 KiB stability never reached. Neither was a defect in the target. Copies the tree into the container rather than bind-mounting it, because `gate_init` bootstraps into `$repo_root/.axiom-bin` and a Linux binary left there breaks the next darwin run. Not a gate: it asserts nothing and `run-gates.sh` does not call it |
| `bench-datastructures.sh` | prints `Vec`, `Map` and `Intern` against the Rust equivalents. `--check` enforces the roadmap's "within 2×" criterion; unconditionally, a wall-clock threshold on a shared runner is a flaky test. `--fx` switches the Rust side to a fast hasher, which is the fair comparison against `stdlib/Map.ax` — `./scripts/bench-datastructures.sh --fx --check` is the bound worth quoting |
| `measure-memory-baseline.sh` | prints the before/after numbers the memory-model schedule is driven by |
| `reseed.sh` | a maintenance tool rather than a gate: it regenerates `bootstrap/` with a generator built from the committed seed - never from a compiler of unrecorded ancestry - and appends the link to `bootstrap/CHAIN`; when the committed seed cannot compile the tree it stops and says so, and `--bridge` records the link as one that still needs certifying |

---

## CI/CD

Every push to `trunk` and every pull request runs
`.github/workflows/ci.yml`. Ten jobs, staged so that a cheap failure
is reported before an expensive one — the grammar job gates the other
nine, because it is the only one that needs no compiler at all. Seven of
them provision a compiler through the same composite action,
`.github/actions/provision`. An eleventh, the full lineage replay,
runs on the nightly `schedule:` and on `workflow_dispatch` only, and
on those triggers it is the only job that runs:

1. **Tree-sitter grammar** — the checked-in grammar parses every `.ax`
   file in the repository.
2. **Tests** — the gate battery above, on three platforms
   (linux-x86_64, linux-aarch64, darwin-aarch64). Each job provisions a
   compiler from `bootstrap/` first. A fourth leg, `Tests
   (windows-x86_64)` on `windows-latest`, takes the hello-world modules
   the cross-target job emits on Linux and assembles, links and
   executes them (`scripts/check-windows-hello.sh --run`). It
   provisions no compiler: none hosts on Windows yet. A fifth, `Tests
   (freebsd-x86_64)`, boots FreeBSD 14.4 in a VM on the Ubuntu runner
   (`vmactions/freebsd-vm`, SHA-pinned) and runs the bootstrap plus the
   standard library and the syscall-table gates there.

   **Both were `continue-on-error` until 2026-08-30 and neither is
   now**, each line coming off after its leg had been seen green on 13
   of the previous 15 runs — which is what made `freebsd-x86_64` and
   `windows-x86_64` supported, since README's *Targets* section defines
   the word as a leg that executes. The two legs do not cover the same
   amount and that section says so: FreeBSD runs the whole corpus,
   Windows runs one program. `scripts/check-release-targets.sh` now
   refuses a target that is on the supported list and has an advisory
   leg, which nothing checked before.

   `freebsd-aarch64` has no job: an aarch64 guest is TCG-emulated on
   every runner GitHub offers (a 300-minute budget, measured and
   dropped 2026-08-29), so it stands as darwin-x86_64 does - assembled
   and relocation-checked, executed by no runner, and the one FreeBSD
   target that is not supported.
3. **FFI** — `check-ffi.sh` on linux-x86_64 and darwin-aarch64: the
   `extern` boundary opens exactly the symbols it declares, the
   generated bindings match a fresh generation, and the `rust/`
   workspace's own suites run (`cargo test`).
4. **Cross-target codegen** — every target's IR assembles from a single
   host, at `--opt` 0, 1 and 2, and all six committed seeds assemble.
   It also emits the Windows hello and hands it to the Windows leg.
5. **Self-hosting fixpoint** — `check-bootstrap.sh`: `stage2 ==
   stage3`, byte for byte, with the ladder rooted at the committed seed.
6. **Seed provenance** — `check-seed-provenance.sh`: all six committed
   seeds are regenerated from the commit that last wrote them and must
   come back byte-identical. Its own job because it needs
   `fetch-depth: 0` and about five minutes.
7. **Reproducible build** — two independent runs produce identical
   bytes.
8. **Bootstrap from seed** — the load-bearing one, on linux-x86_64 and
   darwin-aarch64: a clean checkout builds the compiler from
   `bootstrap/` with only `llc` and `cc`. If this fails, the repository
   cannot be built at all, and a stale seed is the usual reason
   (`scripts/reseed.sh`).
9. **Seed lineage** — `check-seed-lineage.sh`: the rows of
   `bootstrap/CHAIN` that `bootstrap/CHAIN.checkpoint` does not certify,
   and never fewer than the newest - the previous seed compiles the tree
   of the seed in the tree and must reproduce it - on every push or pull
   request that touches `bootstrap/`, and skipped by name otherwise. The
   checkpoint's digest is recomputed from `CHAIN` on every run, and a
   covered row that moved voids it and forces the full replay. Its own
   job because it needs `fetch-depth: 0`. The nightly
   **Seed lineage (full)** job replays every row with `--full`, cargo
   installed for the Rust anchor.

The `push:` trigger names `trunk`, which is this repository's only
branch.

### What the CI tests actually do

The tests compile and **run** Axiom programs rather than only type-checking them. This catches a class of bugs that a type-check-only CI would miss — for example, a syscall lowering that assembles correctly but returns the wrong value.

### Cutting a release

Releases are a **second workflow**, `.github/workflows/release.yml`,
triggered by pushing a `v*` tag and by nothing else. It is separate
from `ci.yml` on purpose: `ci.yml` runs on every pull request from
anywhere and holds `permissions: contents: read`, and cutting a release
needs a token that can write. Keeping the two apart is what lets the
everyday workflow stay read-only.

`ci.yml` does **not** trigger on tags. That is deliberate and it puts
one obligation on whoever cuts the release, because nothing enforces
it:

1. **Land the release commit on `trunk` and let CI go green.** The tag
   is a pointer to a commit; the gates run on the push, not on the tag.
   Tagging a commit whose CI is red or still running publishes a
   compiler nothing checked.
2. **Update `VERSION`, and the sites that must agree with it, in that
   same commit.** `./scripts/check-version.sh` names all eleven sites
   and their counts, and fails if any disagrees or if a site stops
   stating a version at all. Run it locally first; it is cheap.
3. **Write the `CHANGELOG.md` entry.** `release.yml` passes this file
   to `gh release create --notes-file`, so it *is* the release notes.
   It is swept by `check-doc-drift.sh` like every other prose document.
4. **Nothing needs stamping by hand.** `release.yml` builds the archive
   from the seed through the fixpoint and then has `stage3` build one
   more compiler with `scripts/build-stamped.sh`, so the shipped binary
   reports the tree it came from beside the version it promises. It
   refuses to publish one that says `(build unstamped)`.
5. **Tag and push:**

   ```bash
   git tag -a v0.2.0 -m "Axiom 0.2.0"
   git push origin v0.2.0
   ```

The workflow then refuses to build anything until the tag, `VERSION`
and the number the freshly built compiler prints are the same string.
It builds two targets **from the committed seed** rather than from
`.axiom-bin/`, so the artifact comes out of the path a consumer takes,
and it unpacks each archive somewhere else and compiles a program that
imports the standard library through a bare-name `PATH` invocation
before uploading it.

There is deliberately **no `darwin-x86_64` artifact**. It is assembled
and byte-compared by `check-cross-targets.sh` and executed by no runner
anywhere, so publishing a binary for it would imply a support level
that does not exist. `scripts/install.sh` says so and points at the
seed, which is supported there. The two FreeBSD targets are refused by
the installer in DIFFERENT words since 2026-08-30, and the split inside
one operating system is the point: `freebsd-x86_64` is supported and
unshipped, so it gets the build-from-source paragraph `linux-x86_64`
gets; `freebsd-aarch64` is not supported and gets the one
`darwin-x86_64` gets. Same seed, same syscall table, and only one of
them has a leg that runs any of it.

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
   `Rpc`, `Utf8`, `Show`, `Err`, `Job`, `Html`, `Http`, `Ffi`.
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
   `.out` expected output — or a `test`-named function `axiom test`
   discovers, if what you want to assert is a value rather than a
   program's whole output. The two are for different things and both
   are gated: a golden pins every byte a program wrote, and an
   assertion names the one fact that was wrong. See
   [Testing](README.md#testing).
7. **Update the module table** in `README.md` and `docs/reference.md`.

### The doc-comment convention

There is one, it is what the library already does, and since
2026-08-25 it is READ: `examples/axdoc/axdoc.ax` turns it into
[docs/stdlib-api.md](docs/stdlib-api.md) and
`scripts/check-stdlib-api.sh` holds the result byte-identical.

- **A symbol's documentation is the contiguous run of `;` comment
  lines immediately above its `(pub :: NAME TYPE)`**, up to a `; ---`
  banner. Not above the `(pub fn ...)` — the AXTAG goes there, and the
  formatter keeps the two apart.
- **Its FIRST paragraph is the summary** the reference prints. A
  paragraph ends at a bare `;`. Write the sentence that tells a reader
  whether to open the file first, and the measurements and refusals
  after it.
- **Prose that belongs to a SECTION goes inside the banner**, between
  its two rules — not under it. `axiom fmt` deletes a blank line
  between two comment blocks, so a preamble written under a banner is
  glued to the first declaration below it and becomes that
  declaration's summary. Measured on `stdlib/Test.ax`, whose
  `assertEq` came out documented by a paragraph about the whole
  section.
- **A blank Summary cell in the reference is an undocumented name.**
  `check-stdlib-api.sh` counts them and ratchets the total, so adding
  a public name with no block above it lowers a number somebody has to
  lower on purpose.

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
| [docs/lsp.md](docs/lsp.md) | The language server — running `axiom lsp`, editor configurations, what each request answers and refuses, the semantic-token legend, the cost rule |
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
