# Road to Axiom v1

What "v1" means, what is done, what is left, and — the part that changes
how the work should be scheduled — what actually blocks what.

This document follows the convention of
[docs/self-hosting.md](self-hosting.md): every capability claim is stated
with the observation that established it, so a reader can re-run the probe
rather than take the claim on trust. Where a number appears, the command
that produced it appears with it.

---

## 1. The dependency structure

The v1 feature list reads as a set of parallel workstreams. It is not one.
Four of the headline items cannot be started until earlier items land, and
scheduling them in parallel is the single most likely way for this effort
to produce a large amount of code that does not work.

```
                        ┌──────────────────────────┐
                        │  P0  green CI, no legacy │  ← done
                        └────────────┬─────────────┘
                                     │
              ┌──────────────────────┼──────────────────────┐
              ▼                      ▼                      ▼
     ┌─────────────────┐   ┌──────────────────┐   ┌──────────────────┐
     │ B1 closures     │   │ B2 guaranteed    │   │ ADT revision     │
     │ (function       │   │ tail calls       │   │ (struct variants)│
     │  values)        │   │                  │   │                  │
     └────────┬────────┘   └────────┬─────────┘   └────────┬─────────┘
              │                     │                      │
              │            ┌────────▼─────────┐            │
              │            │ B3 Vec/Map/      │            │
              │            │ Intern in Axiom  │            │
              │            └────────┬─────────┘            │
              │                     │                      │
              ▼                     ▼                      ▼
     ┌───────────────────────────────────────────────────────────────┐
     │  Memory model: arena inference + deterministic drop           │
     └──────────────────────────────┬────────────────────────────────┘
                                    │
              ┌─────────────────────┼─────────────────────┐
              ▼                     ▼                     ▼
     ┌────────────────┐   ┌──────────────────┐  ┌──────────────────┐
     │ Macro system   │   │ Concurrency      │  │ B4 namespacing   │
     └────────┬───────┘   └────────┬─────────┘  └────────┬─────────┘
              │                    │                     │
              │                    ▼                     │
              │           ┌──────────────────┐            │
              │           │ HTTP library     │            │
              │           └──────────────────┘            │
              │                                           │
              └──────────────┬────────────────────────────┘
                             ▼
                    ┌──────────────────┐
                    │ Self-hosting     │
                    └────────┬─────────┘
                             ▼
                    ┌──────────────────┐
                    │ LSP in Axiom     │
                    └──────────────────┘
```

The three edges worth arguing about, because they are the ones that look
optional:

**Macros depend on the memory model, not the reverse.** A macro expander
allocates heavily and transiently: it walks a syntax tree and builds
another one, discarding intermediate forms. Under the current allocator
that cost is unbounded — see §2.2 for the measurement. Writing the
expander first means writing it against an allocator it will have to be
rewritten for.

**HTTP depends on concurrency depends on the memory model.** A
non-blocking HTTP library is an event loop plus per-connection state. Both
require concurrency primitives; concurrency requires knowing which arena a
value belongs to before two tasks can share or hand off a value. Writing
HTTP first produces a blocking library that has to be discarded.

**The LSP is last, and this is the least negotiable edge.** An LSP is
mostly maps and closures: a symbol index, an incremental cache, a table of
request handlers. Axiom today has `Vec`/`Map`/`Intern` (which compile but
lack golden tests and scale validation), but still no function
values that survive code generation (`B1`), and no way for two modules to
define the same name (`B4`). It is also the largest program that would be
written in Axiom, which makes it the worst possible vehicle for
discovering that the language cannot express something. Self-hosting the
compiler first is the cheaper way to find that out, because the compiler
already exists in Rust and can be differentially tested against itself —
see [self-hosting.md §3](self-hosting.md).

What genuinely *is* parallel: the ADT revision, guaranteed tail calls,
closures, and the data structures. None depends on another, and together
they unblock everything downstream.

---

## 2. Where things stand

### 2.1 Done, and verified

| | Evidence |
|---|---|
| CI green on all four targets | §3 below; two root-caused failures fixed |
| `union` removed, `region` removed | `AX2004` with migration advice; 3 regression tests |
| Turing-completeness demonstrated | [game_of_life/](../game_of_life/), verified against an independent implementation |
| Editor grammar | [tree-sitter-axiom/](../tree-sitter-axiom/), 18/18 repo files, ~18 MB/s |
| Freestanding stdlib | `Pre`, `Mem`, `Str`, `Vec`, `Map`, `Fmt`, `Intern`, `Sys`, `IO` over syscalls; no libc |
| Reproducible builds | byte-identical IR across runs, gated in CI |

Reproduce all of it:

```bash
cargo test --release --all
./scripts/run-stdlib-tests.sh
./scripts/check-freestanding.sh
./scripts/check-cross-targets.sh
./scripts/check-reproducible.sh
./scripts/check-game-of-life.sh
./scripts/check-tree-sitter.sh
```

### 2.2 The measurement that drives the schedule

The Game of Life demo exists to produce one number. A 24×24 board, one
board live at any moment (~10 KiB), `--opt 2`:

| Generations | Peak RSS | Overhead vs live set |
|---:|---:|---:|
| 10 | 5.2 MiB | ~500× |
| 80 | 31.8 MiB | ~3,000× |
| 2000 | 744 MiB | ~76,000× |

Linear in generations, flat in live data. The allocator is a bump pointer
over `mmap` with no reclamation, so memory use tracks *total allocations*
rather than reachable data. Reproduce with
[game_of_life/stress.ax](../game_of_life/stress.ax); the method is in
[game_of_life/README.md](../game_of_life/README.md).

This is not a pathological program. It is a loop that builds a value from
the previous value, which is the shape of every compiler pass, every
request handler, and every macro expansion. It is why the memory model is
the hinge of this roadmap rather than one item on a list.

### 2.3 `axiom fmt` cannot round-trip source

Found while checking this work and worth stating separately, because it is
a data-loss bug rather than a missing feature.

`fmt` regenerates source from the syntax tree. Comments never reach the
tree — the lexer discards them so that no later stage has to skip them — so
formatting a file *deleted every comment in it*, in place, and printed a
success message. Every file in `stdlib/` would have lost its documentation
to one invocation. It went unnoticed because `fmt` is the only part of the
CLI with no CI gate, which is itself a consequence of its output not
round-tripping.

Two things changed. The lexer now records the span of every comment it
discards, so the condition is detected exactly rather than by scanning for
`;` outside string literals. And `fmt` refuses to rewrite a file it cannot
round-trip, reporting the count and the reason, instead of succeeding
destructively. Three regression tests pin it, including one asserting the
file is byte-identical afterwards and one asserting that AXTAGs — which are
real tokens and do survive — still format.

`fmt` is consequently unusable on almost every real file, which is the
truth it was previously hiding. The fix is trivia preservation: attach
comments to the syntax they precede and re-emit them. It is scheduled with
the LSP work in **P5** rather than earlier, because the LSP needs the same
machinery for every operation that rewrites source, and building it twice
would be waste.

### 2.4 Open blockers, unchanged

`B1`–`B4` and `S1`–`S5` from
[self-hosting.md §2](self-hosting.md#2-capability-gaps-measured) all still
hold. The ones on the critical path here:

- **B1** — function values do not survive codegen. A higher-order function
  type-checks and emits invalid LLVM.
- **B2** — recursion depth depends on `--opt`. Correctness must not.
- **B3** — `Vec`, `Map`, and `Intern` exist (in `stdlib/`) and compile
  cleanly. Golden tests and scale validation are the remaining work.
- **B4** — one flat namespace across all modules.
- **S1** — every constructor, including nullary ones, is a heap block.

---

## 3. CI: the two failures, root-caused

Both were real, and both are worth recording because each was invisible in
the configuration where development happens.

**`llc: command not found` on darwin-aarch64.** The workflow ran
`echo "$(brew --prefix llvm)/bin" >> "$GITHUB_PATH"`. `brew --prefix
<formula>` prints the path a formula *would* occupy and exits zero when it
is absent, so the step succeeded while appending a non-existent directory,
and the failure surfaced one step later with no connection to its cause.
Fixed by installing before resolving the prefix.

**PIE link failure on linux-x86_64.** Four tests failed with
`relocation R_X86_64_32S against '.bss' can not be used when making a PIE
object`. `llc`'s default relocation model for ELF is `static`; every
current Linux distribution links PIE by default; and Axiom always has a
`.bss` global, the bump allocator's `@__axiom_bump` cursor.

Two things hid it. At `-O2` the x86 backend picks PC-relative addressing
anyway, so only `-O0` fails — and `axiom run` is the `-O0` path. And
Darwin is position-independent unconditionally, so it cannot be reproduced
on macOS at all. Measured directly:

```
llc adt.ll -relocation-model=static -O0  →  5× R_X86_64_32S
llc adt.ll -relocation-model=pic    -O0  →  0× R_X86_64_32S
```

Fixed by passing `-relocation-model=pic` explicitly. Emitting a
`!"PIC Level"` module flag instead does *not* work — `llc` ignores it,
which was also measured — so every `llc` invocation in the project must
carry the option.

The gate that should have caught this now does:
`check-cross-targets.sh` assembles at `-O0` as well as `-O2`, and inspects
relocations rather than trusting `llc`'s exit status. Previously it
assembled only at the default `-O2` and only checked for a clean exit,
which is precisely why a linker-level bug passed a codegen gate.

---

## 4. Designs

Sketches at the level of detail needed to start, with the decisions that
have to be made called out as decisions rather than buried.

### 4.1 Memory model — arena inference with deterministic drop

**Requirements.** Compile-time arenas; type-checked lifetimes;
deterministic drop; no GC; no manual `free`; works with linear types,
lambdas, lists, tuples, and ADTs; supports self-hosting.

**The shape.** Every allocation belongs to an arena. Arenas are inferred
from where a value is created and how far it escapes — never written. That
inference is the reason `region` was deleted from the surface syntax: an
annotation the compiler can derive is an annotation that will be wrong.

1. **Per-activation arenas.** Each function body has an implicit arena. A
   value allocated in it and not escaping is reclaimed when the body
   returns, by rewinding a watermark. O(1) per activation, no per-object
   bookkeeping.
2. **Escape promotion.** A value that is returned, stored into a
   longer-lived structure, or captured by an escaping closure is allocated
   in the caller's arena instead. This is Tofte–Talpin region inference
   with the annotations removed.
3. **Linearity as the precision mechanism.** Inference alone cannot always
   decide. A linear value has exactly one owner, so its arena is its
   owner's arena, and `consume` is a deterministic drop point. This is what
   `linear`/`consume` were always for and why they are currently
   parsed-but-unused.

**The hard part, stated precisely.** Per-activation arenas do not help a
tail-recursive loop, and a tail-recursive loop is the case that matters
(§2.2). In `(advance (step board) (- n 1))` the activation never returns,
so a watermark is never rewound and the measurement stays linear. Fixing
it requires resetting the arena to the entry watermark at the tail call,
which is sound only if the new argument does not point into the memory
being reclaimed — a no-alias obligation on `step : Board -> Board`.

Three ways to discharge it, in increasing order of ambition:

| Approach | Discharges the obligation by | Cost |
|---|---|---|
| Copy at the boundary | copying the new argument down to the watermark | O(live) per iteration, always sound, simple |
| Linear consumption | requiring the loop parameter be linear, so the old value is provably dead | needs linear types finished; changes signatures |
| Full region inference | computing region-annotated types for the whole program | most precise, most research risk |

**Recommendation:** implement the first, because it is sound, simple, and
turns the §2.2 number from linear into constant, and it establishes the
watermark machinery the other two need. Then the second, since linear
types are already in the surface syntax. Treat the third as optional.

**Acceptance criterion.** `game_of_life/stress.ax` at 2000 generations
uses O(1) memory in the generation count: peak RSS within 2× of the same
program at 20 generations. The current ratio is 82×.

**What this does not do.** Nothing here reclaims a cycle, and nothing here
reclaims a value whose lifetime genuinely outlives every arena. Both are
accepted: Axiom's data is immutable and inductive, so cycles are not
constructible, and a value that outlives all arenas is a value that lives
until process exit — which is the correct answer for a compiler process.

### 4.2 Macro system — pattern-based, hygienic, no compile-time evaluation

**The tier decision, made explicitly.** There are two designs available,
and they differ in a security property this project has already committed
to.

- **Tier 1, pattern-based** (`syntax-rules`-shaped): a macro is a set of
  pattern/template pairs. Expansion is a rewrite. The compiler executes no
  user code.
- **Tier 2, procedural**: a macro is an Axiom function from syntax to
  syntax, run at compile time. Strictly more expressive, and it requires
  the compiler to execute arbitrary code from a source file — which
  directly contradicts the existing invariant that "the compiler must
  never execute arbitrary code from source files during compilation".

**Recommendation: tier 1 for v1.** Axiom is an S-expression language, so
pattern matching on syntax is a natural fit and covers the stated use
cases — deriving instances, eliminating the boilerplate that
[game_of_life/main.ax](../game_of_life/main.ax) is full of, and generating
the repetitive parts of a self-hosted compiler. Tier 2 should not be
smuggled in as an implementation detail of tier 1; it is a change to the
compiler's threat model and needs a sandbox and an explicit decision.

**Hygiene.** The mechanism is scope sets: an identifier becomes a
`(name, scopes)` pair rather than a bare name, every macro expansion
introduces a fresh scope, and resolution matches on both. Free identifiers
in a template resolve at the macro's *definition* site; binders introduced
by a template are renamed. Concretely this means adding a scope field to
`Ident` in `axiom-ast/src/span.rs` and teaching name resolution in
`axiom-sema` to compare scope sets. That is the first commit, and it is
independently testable before any macro exists.

**Type-checked output is free; good diagnostics are not.** Expansion runs
before semantic analysis, so expanded code is type-checked like any other
code. The problem is that a type error in expanded code points *inside the
macro*, at source the author never wrote. `Diagnostic` needs an expansion
backtrace — the chain of macro invocations a span passed through — and the
AXDL renderer needs a field for it. Without this, macros make the
diagnostic quality worse, and diagnostic quality is this project's
distinguishing feature.

**Acceptance criteria.**
- A `derive`-style macro generates a working `Eq` instance for a `data`
  type, with exhaustiveness still checked on the generated `match`.
- A macro that introduces a binding named `x` does not capture a
  user's `x`, and the reverse (the classic `swap!`/`or` hygiene tests).
- A type error inside an expansion reports the macro *and* the invocation
  site, both with real spans.
- Macros work over `data`, `struct`, lambdas, lists, and tuples — one
  corpus case each.

### 4.3 ADT revision — smaller than it sounds

Axiom already has Rust-style ADTs: tagged sums, recursive types, nested
constructor patterns, and compile-time exhaustiveness checking. That is
verified — `game_of_life/` is built on it. The actual gap against Rust is
narrow:

1. **Struct variants.** Rust's `enum Shape { Circle { r: f64 } }` has no
   Axiom equivalent; `data` constructor fields are positional only. This
   is the substance of the item: named fields per variant, matchable and
   accessible by name.
2. **Nullary constructors should not allocate** (`S1`). `(Nil)` is
   currently a heap block. A nullary constructor is a constant and should
   be an immediate.
3. **Field punning in patterns**, once (1) exists.

Item 2 interacts with the memory model and should land with it; the
allocation it removes is a large fraction of what the §2.2 measurement is
measuring.

### 4.4 Concurrency — structured, arena-scoped

**Requirements.** Deterministic; linear-type-safe; region-free;
arena-aware; suitable for parallel compilation and agent workloads.

**The shape.** Structured concurrency with no shared mutable state. Axiom
has no mutable aliasing to begin with, so data races are not constructible;
what needs designing is the arena discipline at task boundaries and the
determinism guarantee.

- Each task gets its own arena. A task's allocations are reclaimed when it
  joins.
- A value handed to a task is either copied into that task's arena or moved
  (if linear). Moving is the interesting case and is what makes linear
  types load-bearing rather than decorative.
- Results are moved into the parent arena at join.
- **Determinism** means results are combined in a fixed order regardless of
  completion order — `parMap` returns results in argument order, not
  arrival order. Scheduling is free to be nondeterministic; observable
  behaviour is not.

Parallel compilation is the driving use case and the natural first test:
independent modules type-check in independent arenas with no shared state.

### 4.5 HTTP library — deferred on purpose

Small, resilient, non-blocking, pure Axiom. It needs, in order: `Vec` and
`Map` (`B3`) for headers and routing; the concurrency model (§4.4) for an
event loop; and non-blocking syscalls, which are new `Sys` surface
(`epoll`/`kqueue`) with a per-platform module — the pattern
`stdlib/Sys/Platform.*.ax` already establishes.

Written before those, it is a blocking library with a socket API, which is
not the deliverable.

### 4.6 LSP — after self-hosting, not before

Requires `B1` (closures, for handler tables), `B3` (maps, for the symbol
index and incremental cache), and `B4` (namespacing, for a program of that
size). It should reuse the self-hosted frontend rather than reimplement
parsing, which is the whole architectural argument of rust-analyzer and
the reason self-hosting comes first.

The [tree-sitter grammar](../tree-sitter-axiom/) already covers the part of
the editor experience that does not need semantic analysis — highlighting
and structural selection — so this ordering costs users less than it
appears to.

---

## 5. Phases

Each phase lists its exit criterion. Within a phase, items are genuinely
parallel.

| Phase | Items | Exit criterion |
|---|---|---|
| **P0** *(done)* | Green CI; `union`/`region` removed; Game of Life; tree-sitter grammar | All seven gates green on all four targets |
| **P1** | `B2` tail calls · `B3` `Vec`/`Map`/`Intern` golden tests and scale validation · `B1` closures · ADT struct variants | 10⁷-iteration tail loop at `-O0`; higher-order probe runs; struct variants match exhaustively |
| **P2** | Memory model (§4.1) · `S1` unboxed nullary constructors | `stress.ax` at 2000 generations within 2× of 20 generations |
| **P3** | Macro system (§4.2) · `B4` namespacing · concurrency (§4.4) | Hygiene test suite passes; two modules define the same name; `parMap` is order-deterministic |
| **P4** | Self-hosting phases 2–5 · HTTP library (§4.5) | `stage2 == stage3`; HTTP server serves a request under load |
| **P5** | LSP (§4.6) · trivia preservation for `fmt` (§2.3) · benchmarking · docs | Completion and diagnostics in a real editor; `fmt` round-trips every file in the repo, gated in CI; published performance profile |

**On effort.** P1 is weeks. P2 is the research risk and could be a month
or several depending on which option in §4.1 proves sufficient. P3–P5 are
each larger than everything before them combined; the LSP alone is
comparable in size to the current compiler. Any plan that shows these
completing together is not a plan.

---

## 6. Risks

| Risk | Mitigation |
|---|---|
| The memory model is attempted at full generality and stalls | Ship the copy-at-boundary option first; it is sound and turns the §2.2 number constant. Treat region inference as optional |
| Procedural macros arrive as an implementation detail and silently make the compiler an arbitrary-code executor | Tier 1 only; tier 2 requires an explicit, documented decision and a sandbox |
| Macros degrade diagnostics | Expansion backtrace in `Diagnostic` is part of the macro work, not a follow-up |
| The LSP is started early "in parallel" and blocks on missing language features | The dependency edges in §1 are the schedule; the tree-sitter grammar covers editor basics meanwhile |
| A gate passes while the property it protects is broken — as happened for PIE relocations | Every new gate gets a negative test proving it fails when it should. Done for the relocation and grammar gates |
| A tool with no CI gate is silently broken, as `fmt` was | Either gate it or make it fail loudly. `fmt` now refuses rather than destroying; the remaining ungated surfaces are `repl` and `explain` |
| Removing `union`/`region` breaks unknown external code | Both stay reserved and report `AX2004` with the replacement, rather than being silently reinterpreted |
