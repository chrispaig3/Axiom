# Self-hosting Axiom

Status of, and plan for, replacing the Rust implementation of the Axiom
compiler with an implementation written in Axiom.

This document is the working spec for that effort. It is written to be
falsifiable: every capability claim below was checked against the
compiler in this repository, and every gap is recorded with the probe
that exposed it, so a reader can re-run the probe rather than take the
claim on trust.

---

## 1. Where things stand

### 1.1 The Rust compiler being replaced

Lines are `src/` only, measured at the commit this effort started from.

| Crate | Lines | Responsibility |
|---|---:|---|
| `axiom-cli` | 2,835 | Driver, module resolution, REPL, `fmt`, `symbols` |
| `axiom-sema` | 2,265 | Name resolution, type checking, effects, AXTAG validation |
| `axiom-parser` | 1,973 | S-expression parser |
| `axiom-ir` | 1,827 | IR definition and lowering from AST |
| `axiom-errors` | 1,583 | Diagnostics, AXDL/AXSYM rendering, source maps |
| `axiom-codegen` | 1,090 | LLVM text emission, target/syscall ABI |
| `axiom-lexer` | 723 | Tokenizer |
| `axiom-ast` | 714 | AST, tokens, spans |
| **Total** | **13,010** | |

That is the whole surface to be reimplemented, and it is small enough
that self-hosting is a realistic goal rather than an aspiration. The
hard part is not the line count; it is that Axiom cannot yet *express*
several things the Rust code relies on. Section 2 is that list.

### 1.2 What has already changed

Before this work, Axiom had no standard library and no way to reach the
operating system except a C foreign-function binding. Any Axiom program
that printed a line called `printf`; any program that allocated called
`malloc`. A compiler written in that language would have been a C
program wearing Axiom syntax, and the "no C FFI for stdlib operations"
requirement would have been unmeetable by construction.

That layer is now gone:

- **Freestanding primitives** (`axiom_sema::PRIMITIVES`): `__syscall0`
  through `__syscall6`, `__load8`/`__store8`, `__load64`/`__store64`,
  `__alloc`, `__addr`. These are the only operations the standard
  library cannot define in terms of anything else.
- **Per-target syscall ABI** (`axiom_codegen::Target`): Darwin and Linux
  on both x86-64 and AArch64, each with its own register convention and
  inline-assembly sequence. The Darwin sequences normalise Darwin's
  carry-flag error protocol into Linux's `-errno` convention, so the
  standard library has a single portable error test instead of a per-OS
  special case.
- **An Axiom-owned allocator**: `HeapAlloc` no longer calls `malloc`. The
  backend emits an `mmap`-backed bump allocator, and a program that
  defines `axiom_alloc` itself replaces it - the seam that lets the
  allocator move into Axiom later without another backend change.
- **A standard library in Axiom** (`stdlib/`): `Pre`, `Mem`, `Str`,
  `Vec`, `Map`, `Fmt`, `Intern`, `Sys`, `IO`, with per-platform
  syscall tables under `Sys/`.
- **Module resolution with a search path** and target-specific file
  selection (`Foo.linux-x86_64.ax` before `Foo.linux.ax` before
  `Foo.ax`), so platform differences live in Axiom source rather than in
  a table inside the compiler.
- **Transitive effect inference**, without which every
  `;@axiom:effect(io)` claim above the standard library was
  unverifiable: effects used to be detected only where a `foreign` call
  appeared literally in a body.

Verified end to end: `tests/stdlib/` compiles and runs on the host,
assembles for all four targets, emits no libc call, produces
byte-identical IR across runs, and links to an executable with no libc
imports. See `scripts/check-freestanding.sh`,
`scripts/check-cross-targets.sh`, `scripts/check-reproducible.sh`.

---

## 2. Capability gaps (measured)

These are the reasons the compiler cannot yet be written in Axiom. Each
is stated with the observation that established it. Ordering is by how
hard it blocks the bootstrap.

### 2.1 Blockers

**B1. Function values. (RESOLVED)** The representation is a closure
record: word 0 is the code pointer, words 1.. are the captured values,
and the record itself is passed as the callee's hidden first parameter.
Building that record already worked; calling it did not. An application
spine was flattened into a single direct call, so `((adder 10) 5)`
became `@adder(0, 10, 5)` — five handed to a one-parameter function,
the second application never performed, and the closure's *address*
returned as the answer. A call now applies as many arguments as the
callee declares and passes the surplus through `CallIndirect` on the
returned closure, one at a time, since each step may yield another
closure.

Verified end to end by `tests/stdlib/140-function-values.ax`: capture,
multi-argument capture, curried nesting (`(((add3 1) 2) 3)`), a closure
as an argument, an inline `lambda`, a top-level function used as a
value, and a closure stored in and recovered from a `data` constructor.

**B2. Deep recursion is stack-bounded, and Axiom has no loop.**
Measured on an 8 MiB stack: a tail-recursive counter survives 200,000
iterations and dies at 400,000. Since iteration in Axiom *is*
recursion, this caps input size. Partly mitigated: `--opt 1..3` now runs
LLVM's mid-level passes, which promote self-tail-recursion to a loop -
a 500,000-byte string scan through `Str.cstrLen` fails at `-O0` and
succeeds at `--opt 2`. That is a workaround, not a fix: correctness now
depends on an optimisation flag, non-tail recursion is still bounded,
and `opt` becomes a de-facto dependency. Axiom needs either guaranteed
tail calls in the IR or an explicit loop form.

**B3. Hash map, growable array, and interner exist but are untested at
scale.** `Vec` (growable array of `Int`), `Map` (open-addressing
`Int→Int` hash map with delete support), and `Intern` (string interner)
are now implemented in `stdlib/` and compile cleanly. The Rust compiler
uses `HashMap`/`HashSet`/`Vec` throughout (scopes, string interning,
diamond-import dedup, constructor tables). The Axiom implementations
exist and type-check, but they lack golden tests and have not been
exercised at the scale a self-hosted compiler would demand. Writing and
exercising those tests, and ensuring the data structures meet the
performance requirements of a 13,000-line compiler's type checker, is
the remaining work on this item.

**B4. One flat namespace across all modules. (RESOLVED)** Qualified
access via `Mod::name` is supported. Same-named declarations from
different modules coexist without collision. Two modules can both define
`new`; ambiguous names are disambiguated with `Mod::name`. The
language-level decision is qualified names, and it is implemented in
`sema` (module tracking on info structs, `check_qualified_var` for
`EQualified` resolution) and `ir` (name mangling, `fn_mangle_map`).

### 2.2 Serious but workable

**S1. `data` values are boxed unconditionally.** Every constructor,
including nullary ones, is a heap block. A compiler allocates a
constructor per token and per AST node; with a bump allocator and no
`free`, memory use is proportional to total allocations, not live data.
Acceptable for a single-shot compiler process, and worth revisiting
before anything long-running is written in Axiom.

**S2. No first-class strings in the language.** A literal is a
NUL-terminated byte array with no length. `Str` fixes this in the
library, but source-level string handling still goes through
`(strFromLit (__addr "..."))`.

**S3. Nullary functions are the only named constants.** `(fn (x) 42)`
plus a reference to `x` lowers to a call. It works (and is what the
platform syscall tables use), but every constant read is a function
call at `-O0`.

**S4. Diagnostics are Rust-shaped.** `axiom-errors` renders three
formats and carries a source map. Reproducing AXDL byte-for-byte in
Axiom needs `Str` formatting facilities the library does not have yet
(padding exists; escaping and quoting do not).

**S5. No `while`, no mutable local bindings.** Mutation goes through
`memSetWord` on an allocated cell. Workable, verbose.

### 2.3 Non-issues, confirmed

- Recursive algebraic data types, pattern matching (including nested
  constructor patterns and exhaustiveness), and multi-argument functions
  all work: a `List`/`length` program compiles and returns the right
  answer.
- Polymorphism works by uniform representation - every value is a
  machine word - so no monomorphisation is required.
- Imports are transitive and diamond-safe.
- `struct` works, with the syntax `(struct Point (x : Int) (y : Int))`.

---

## 3. Bootstrap strategy

Three stages, in the classic order, with the compatibility shim
maintained throughout:

```
stage0  Rust compiler (this repository)             — trusted, kept
stage1  Axiom compiler, compiled by stage0          — the new code
stage2  Axiom compiler, compiled by stage1          — must equal stage1's output
```

Self-hosting is declared when `stage2` and a `stage3` built by it are
byte-identical, and the full conformance suite passes under `stage2`.
Byte-identity is why `scripts/check-reproducible.sh` exists now, before
there is anything to bootstrap: a compiler whose output varies between
runs of the same binary cannot produce a meaningful fixpoint.

The Axiom compiler is written in **Axiom-0**: the subset that stage0 can
compile correctly today. Every language feature the new compiler wants
that Axiom-0 lacks is added to stage0 *first*, with tests, before any
Axiom code depends on it. This keeps the bootstrap always-green rather
than accumulating a pile of Axiom source that nothing can compile.

---

## 4. Plan

Each phase lists its exit criteria. Phases 1-3 can proceed in parallel
once phase 0 lands.

### Phase 0 - Foundations (done)

Freestanding primitives, target/syscall ABI, Axiom-owned allocator,
`stdlib/{Pre,Mem,Str,Vec,Map,Fmt,Intern,Sys,IO}`, module search path
with per-target selection, transitive effect inference,
golden/freestanding/cross-target/reproducibility gates in CI.

*Exit criteria met:* a pure-Axiom program prints, formats integers,
manipulates strings, reads and writes files, and exits with a chosen
status, calling no libc function, on four targets.

### Phase 1 - Close the blockers

| Item | Work | Exit criteria |
|---|---|---|
| B2 | Guaranteed tail calls in the IR (self-call → parameter reassignment + branch), independent of `opt` (DONE) | 10-million-iteration tail-recursive loop at `-O0`; stdlib loops keep constant stack |
| B3 | `Vec`, `Map` (open addressing), `Intern` — golden tests and scale validation | Golden tests for all three; 10⁵-element insert/lookup within 2× of the Rust equivalent |
| B1 | Function values: representation decision, indirect call in IR and codegen (DONE) | Higher-order probe from §2.1 compiles and runs; closure capture tested |
| B4 | Namespacing: qualified access `Mod::name` (DONE) | Two modules define the same name without collision; `Mod::name` access works; existing programs unaffected |

B2's loop conversion is in place and holds at `-O0`. It does *not*
reclaim what an iteration allocated: an earlier version reset the bump
allocator to a mark taken before the self call, which is sound only if
every live object is reachable from a root the compactor can trace, and
it can trace nothing but `data`-typed roots — a raw struct pointer has
no tag word to walk. Loops that allocated into a `Vec` behind a struct
field had that memory freed under them. A loop now leaks into the arena,
which is the allocator's documented model (§2.2 S1); reclaiming it needs
a real tracing story. `tests/stdlib/110-tail-loop-alloc.ax` covers this.

### Phase 2 - Frontend in Axiom

Lexer, then parser, then AST, each with golden tests against the Rust
implementation's output on a corpus of `.ax` files. Differential testing
is the mechanism: both implementations tokenize/parse the same input and
their serialised output must match exactly.

*Exit criteria:* Axiom lexer and parser agree with the Rust ones on
every file in the corpus, including every error case, with identical
spans.

### Phase 3 - Semantic analysis in Axiom

Name resolution, type checking, effects, exhaustiveness, AXTAG
validation. Diagnostics must match AXDL output byte-for-byte, which is
what makes the comparison mechanical.

*Exit criteria:* identical AXDL for every case in the diagnostic corpus,
including cascade suppression and grouping behaviour.

### Phase 4 - IR and backend in Axiom

IR definition, lowering, LLVM text emission, and the target/syscall
tables. The emitted `.ll` must match the Rust backend's byte-for-byte on
the corpus - a stricter and much easier-to-debug criterion than
"produces a working program".

*Exit criteria:* identical LLVM IR for the corpus; all four targets.

### Phase 5 - Driver, bootstrap, and fixpoint

Module resolution, CLI, `symbols`, `fmt`, `explain`. Then stage1 →
stage2 → stage3 until byte-identical.

*Exit criteria:* `stage2 == stage3`; full test suite green under stage2;
reproducible from source per `docs/` instructions.

### Phase 6 - Performance

Only after correctness. Baseline the Rust compiler's wall-clock and peak
RSS on a corpus, then close the gap to within 20%. Expected hot spots,
in order: allocation volume (S1), `Map` quality (B3), and the absence of
loops (B2).

*Exit criteria:* published comparison, within 20% on compile throughput,
with profiles attached.

### Phase 7 - Migration and release

Ship stage2 alongside the Rust compiler; make it opt-in
(`AXIOM_COMPILER=axiom`), then default, then remove the Rust
implementation one crate at a time in dependency order (lexer first,
driver last).

---

## 5. Risks and mitigations

| Risk | Mitigation |
|---|---|
| A stage0 bug is baked into stage1 and reproduced by stage2, making a wrong compiler look self-consistent | Differential testing against stage0 at every phase, not just at the end; keep the Rust compiler runnable and CI-tested for at least two releases past self-hosting |
| Correctness depends on `--opt` (B2) | Treat guaranteed tail calls as phase-1 blocking work; until then, CI runs the golden suite at both `-O0` and `--opt 2` |
| Bump allocator makes a long-running Axiom program leak by design (S1) | Document as compiler-process-only; keep `axiom_alloc` overridable so a real allocator can be dropped in from Axiom |
| Inline assembly is per-target and unverifiable by the type system | `scripts/check-cross-targets.sh` assembles every target on every CI run; the CI matrix *runs* the suite on Linux x86-64, Linux AArch64, and macOS ARM |
| Flat namespace (B4) forces sweeping renames late in the port | (RESOLVED) B4 implemented with qualified access before any Axiom code was written |
| A regression in diagnostics is invisible to output-only tests | Byte-for-byte AXDL comparison is the acceptance criterion for phase 3 |

## 6. Rollback

Rollback is cheap by construction, and stays cheap because the Rust
compiler is never deleted while the Axiom one is unproven.

- **Trigger:** any of - self-hosting fixpoint lost; conformance
  regression; >20% compile-throughput regression; a miscompilation with
  no root cause within one working day.
- **Action:** revert the default compiler selection to stage0. Since
  stage0 remains in the tree and in CI, this is a one-line change with
  no data migration.
- **Blast radius:** none for downstream users while the Axiom compiler is
  opt-in; the public CLI, diagnostic formats, and ABI are unchanged by
  the port, which is why "identical output" is the acceptance criterion
  at every phase rather than "equivalent behaviour".

---

## 7. Reproducing the claims in this document

```bash
cargo test --release --all           # unit, integration, and golden suites
./scripts/run-stdlib-tests.sh        # standard library, compiled and run
./scripts/check-freestanding.sh      # no libc in the IR or in the linked binary
./scripts/check-cross-targets.sh     # every target assembles from one host
./scripts/check-reproducible.sh      # two runs produce identical IR
```

The capability probes in §2 are single files; each is quoted in full
where it is cited, and `axiom --diagnostic-format=ai check <file>` plus
`axiom build --input <file> --output <bin>` is enough to reproduce every
result.
