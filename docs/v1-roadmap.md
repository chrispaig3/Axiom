# Road to Axiom v1

What v1 still needs, and — kept because it is the half that was worth
writing down — what actually blocked what.

Most of this document was a plan, and the plan is spent. The items it
sequenced have landed, the two designs it sketched
have normative specifications of their own, and the incident reports it
accumulated belong to [self-hosting.md](self-hosting.md), which is where
this project writes a bug up. What survives here is the short list of
what is left, the dependency argument that decided the order, and the
status of the capability gaps `self-hosting.md` measured.

This document is not a status board. [README.md](../README.md)'s
Implementation Status table is, and `scripts/check-doc-drift.sh`
recomputes its counts against the tree; nothing recomputes the ones
below, so they name the script that reproduces them instead.

---

## What is left

| Item | Normative home | What remains |
|---|---|---|
| Automatic reclamation's acceptance measurements | [memory-model.md](memory-model.md) `MM-LIFE-2e`, §9 | All seven of `MM-LIFE-2c`'s ownership events emit — the last two on 2026-08-21 (`tests/stdlib/372-arc-owned-results.ax`). What the acceptance figures wait on is not an event: the compiler's own containers and AST declare their handles `Int`, so no type-directed event can fire on them, and neither figure moves until they carry a type the checker can see |
| Three macro features | [macro-system.md](macro-system.md) §11 | Literal-identifier patterns (`MAC-LANG-17`, which need `MAC-HYG-9`'s scope sets), a repeat over a nested pattern (`MAC-LANG-16`'s second half), and rules over EXPRESSION templates (`MAC-LANG-14`) |
| The LSP past macro invocations | `self_host/lsp.ax`, gated by `scripts/check-lsp-selfhost.sh` | Hover and go-to-definition answer for macro invocations, off the raw parse tree, because that is the one position whose meaning needs no type. Over an ordinary expression they do not, and completion is not implemented at all: all three need a node-to-type table `self_host/typecheck.ax` does not keep |
| A published performance profile | — | `scripts/bench-compile.sh`, `scripts/bench-datastructures.sh` and `scripts/measure-memory-baseline.sh` produce the numbers; nothing publishes them as a profile, and no gate holds one to a floor |
| Cycle collection | [memory-model.md](memory-model.md) `MM-LIFE-3` | Deliberately separable and deliberately deferred. Cycles leak, that is the stated and accepted cost of reference counting, and breaking a knot before dropping its last external reference is a program obligation nothing checks |

Nothing on that list blocks anything else on it, which is the one way
this list differs from every earlier version of it.

---

## 1. The dependency structure

Historical: every edge below has been discharged. It is kept because the
two arguments it encodes were the reason the work happened in this order,
and both held.

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
      │  Memory model: reference counting + deterministic drop        │
      └──────────────────────────────┬────────────────────────────────┘
                                     │
                     ┌───────────────┼───────────────┐
                     ▼                               ▼
            ┌────────────────┐              ┌──────────────────┐
            │ Macro system   │              │ B4 namespacing   │
            └────────┬───────┘              └────────┬─────────┘
                     │                               │
                     └───────────────┬───────────────┘
                                     ▼
                            ┌──────────────────┐
                            │ Self-hosting     │
                            └────────┬─────────┘
                                     ▼
                            ┌──────────────────┐
                            │ LSP in Axiom     │
                            └──────────────────┘
```

**Macros depend on the memory model, not the reverse.** A macro expander
allocates heavily and transiently: it walks a syntax tree and builds
another one, discarding intermediate forms. Under a bump allocator that
cost is unbounded — §2.2 is the measurement. Writing the expander first
would have meant writing it against an allocator it had to be rewritten
for.

**The LSP is last, and this was the least negotiable edge.** An LSP is
mostly maps and closures, and it is the largest program that would be
written in Axiom — the worst possible vehicle for discovering that the
language cannot express something. Self-hosting the compiler first was
the cheaper way to find that out, because the compiler already existed
and could be differentially tested against itself. The estimate this
edge carried — that the LSP alone would be "comparable in size to the
current compiler" — was an estimate of *reimplementing* a frontend.
`self_host/lsp.ax` reuses the self-hosted one instead and its first
slice was 1,400 lines across three modules, so the estimate was wrong in
the direction the edge predicted it would be.

---

## 2. Where things stand

### 2.1 Done, and gated

Every row names the gate rather than a count, because the counts move
and the gates do not.

| | Gate |
|---|---|
| Self-hosting: the Rust compiler is gone | `scripts/bootstrap-from-seed.sh` from the committed `bootstrap/*.ll`, and `scripts/check-bootstrap.sh` for the fixpoint `stage2 == stage3` |
| Reproducible builds — byte-identical IR across runs | `scripts/check-reproducible.sh` |
| `fmt` round-trips every file in the repository | `scripts/check-fmt.sh` (behaviour: it formats a copy of the repo and re-runs the suites) and `scripts/check-fmt-selfhost.sh` |
| The REPL evaluates every result type, freestanding | `scripts/check-repl-selfhost.sh`, driven over a pipe |
| Floating point — arithmetic, comparison, conversion, formatting, and floats through ADTs | `tests/stdlib/240-float.ax` |
| Character classification | `tests/stdlib/230-char.ax` |
| Field kinds — the matrix of what a field may hold and how it is read back | `tests/stdlib/250-field-kinds.ax` |
| `cond` | `tests/stdlib/260-cond.ax` |
| Diagnostics: byte-identical AXDL, human and JSON renderings | `scripts/check-diagnostics.sh` against checked-in goldens, plus `tests/diagnostics/verify-axdl-spans.py`, which re-derives every span from the fixture's own bytes and so cannot be satisfied by re-blessing; `scripts/check-render-selfhost.sh` for the human renderer |
| The editor grammar parses every `.ax` file in the repository | `scripts/check-tree-sitter.sh` |
| Freestanding standard library over syscalls, no libc | `scripts/check-freestanding.sh`, `scripts/run-stdlib-tests.sh` |
| The same program builds and behaves the same on all four targets | `scripts/check-cross-targets.sh` |
| `union` and `region` are gone from the language | `AX2004` naming the replacement, with regression fixtures under `tests/diagnostics/` |
| A Rust FFI | [ffi.md](ffi.md), gated by `scripts/check-ffi.sh` — the one gate that needs `cargo`, and it skips rather than fails without it |

The diagnostic corpus is the one figure worth stating here, because it
is the one that used to be quoted wrongly: the compiler defines 35
`AX30xx` codes (`AX3001`–`AX3036` less the retired `AX3032`), and the
checked-in `.axdl` goldens carry **all 35**. Reproduce with
`axiom explain --list` against `grep -oh 'AX30[0-9][0-9]'
tests/diagnostics/*.axdl`.

### 2.2 The measurement that drives the schedule

`scripts/measure-memory-baseline.sh` is the reproduction: a 24×24
toroidal Life board — one board live at any moment, ~10 KiB — advanced
by `(advance (step board) (- n 1))`, the tail-call shape §4.1 named as
the hard case. The printed population is 5 at every N, which pins that
all N steps really computed Life.

| Generations | Population | Max RSS | KiB per generation |
|---:|---:|---:|---:|
| 10 | 5 | 1.5 MiB | 148 |
| 80 | 5 | 2.6 MiB | 32 |
| 500 | 5 | 9.3 MiB | 18 |
| 2000 | 5 | 33.3 MiB | 16 |

Linear in generations, flat in live data: a bump allocator tracks *total
allocations*, not reachable data. The same program with the loop
bracketed by the explicit arena primitives holds 1.4 MiB flat from 80
through 20,000 generations, and `scripts/check-memory-baseline.sh` gates
all three claims — managed flat under 4 MiB, populations exactly 5, and
the negative, run every time, that a reset with no copy corrupts the
board to population 0.

This is not a pathological program. A loop that builds a value from the
previous value is the shape of every compiler pass, every request
handler and every macro expansion. It is why the memory model was the
hinge of this roadmap rather than one item on a list — and why the
Life probe still cannot show automatic reclamation working: its board is
a `Vec` behind `(-> Int Int Int)`, so no type-directed ownership event
can fire on it. That is the same blocker "What is left" names, in the
program that first exposed it.

### 2.3 The bug narratives, and where they went

Six sections here were incident reports: `fmt`'s six ways of silently
destroying a source file, a REPL that could not evaluate anything, a
class of representation bugs, a parser that could hang, `cond`
implemented everywhere except where it mattered, and a formatter
emitting `deriving` and `mut` in positions the parser does not accept.
Each is fixed, each is gated by a script named in §2.1, and each is
written up in [self-hosting.md](self-hosting.md) or
[memory-model.md](memory-model.md) §9.0, which are the documents that
keep defect records.

One pattern is worth restating rather than filing, because it was
recorded three times: **a formatter is a second implementation of the
grammar, and the only thing that keeps the two implementations in
agreement is a corpus that uses every rule.** The `.ax` files in this
repository are written by people solving problems in Axiom, so they use
the constructs those problems need. `tests/fmt/syntax-zoo.ax` has to be
written by someone reading the *parser*.

### 2.4 The capability gaps, `B1`–`B4` and `S1`–`S5`

Named in [self-hosting.md §2](self-hosting.md#2-capability-gaps-measured),
which is their normative home. Status against the tree today:

- **B1** — function values. Done: closure record, indirect call;
  `tests/stdlib/140-function-values.ax`.
- **B2** — recursion depth no longer depends on `--opt`: tail calls are
  guaranteed in the IR, and `while` gives an explicit loop that runs
  10⁷ iterations in constant stack at `-O0`. *Non*-tail recursion is
  still bounded, measured at 60,000–80,000 frames on an 8 MiB stack.
  Still open, with `S3` below; every other gap on the two lists is
  closed.
- **B3** — `Vec`, `Map` and `Intern` are golden-tested and validated at
  10⁵ (`tests/stdlib/200-scale.ax`) and benchmarked at 10⁶
  (`scripts/bench-datastructures.sh`). `Map` meets the 2× criterion at
  **1.80×**, from 14×. The cause was never the allocator this entry
  used to blame: `mapHash` was affine in the key for keys below 2²², so
  sequential keys clustered and linear probing ran 71 probes per
  insert; an avalanche hash (fmix64) plus byte-wide state tags fixed
  it, and the earlier "growth is six sevenths of the cost" ablation was
  the same bug measured through rehash. `Intern` is *faster* than Rust
  (0.73×); `Vec` is 3.4×, three header loads against a
  register-resident Rust `Vec`, ~5 ms absolute at compiler scale.
- **B4** — namespacing. Done: `Mod::name` qualified access works, two
  modules define the same name without collision, and a bare reference
  *inside* a module binds to that module's own definition first
  (`tests/selfhost/850-module-local-binding.ax`). Module visibility is
  real: `pub` and an import's name list decide which names are visible,
  not which declarations exist, and reaching a name a module does not
  export is `AX3023`.
- **S1** — done: nullary constructors are immediates rather than heap
  blocks, in mixed types as well as all-nullary ones, and a `match`
  over a mixed type reads the tag through a runtime
  immediate-vs-pointer guard. Constructors with fields still box.
  Pinned by `tests/stdlib/270-nullary-unboxed.ax`.
- **S2** — closed. `String` is a distinct first-class type, not `Int`
  by fiat: `(+ 1 "hi")` is `AX3004`, pinned by
  `tests/diagnostics/555-string-int-distinct.ax`, and source-level
  string handling no longer goes through `(strFromLit (__addr "..."))`.
- **S3** — stands. Nullary functions are still the only named
  constants, so every constant read is a call at `-O0`.
- **S4** — closed. The Axiom renderer produces AXDL, human and JSON,
  each gated (§2.1); the `axiom-errors` crate it named is gone with the
  rest of the Rust compiler.
- **S5** — closed: `let mut` with `set`, and `while`.

---

## 3. How any of it is verified

The gates are scripts in `scripts/`. They are the contract, not CI's
workflow file, and each is runnable on a laptop. Two conventions make
them worth trusting, and both were bought with a failure:

- **Every gate gets a negative test proving it fails when it should.**
  Written after a PIE-relocation gate passed over a broken property.
- **Read the process status before believing its output.** A gate whose
  assertion is "the output must not contain X" is satisfied by the
  process *dying*, which is how a `check` that was SIGSEGV on
  `(fn (f) ())` passed a formatter gate for as long as that case
  existed. `scripts/check-degenerate.sh` generalises the fix: its
  assertions are about the process rather than its output.

---

## 4. Designs

Each of these sections was a design sketch. Four have been settled by
implementation and two by decision; all six are recorded here because
other documents and sources cite them by number.

### 4.1 Memory model — arena inference with deterministic drop

**Superseded 2026-08-14.** The strategy is decided in
[memory-model.md](memory-model.md): reference counting (`MM-LIFE-2a`–`2f`)
— counts on heap blocks, compiler-emitted retain/release, deterministic
reclamation; cycles leak, and that is the accepted, stated cost with a
cycle collector a later separable decision. The arena-inference sketch
that stood here is preserved in that document as `MM-ALLOC-17`–`19` and
`MM-ALLOC-21`, marked withdrawn, with the reason each rule failed. What
survived it
unchanged: the explicit
`__axiom_arena_mark`/`__axiom_arena_reset`/`__axiom_arena_reset_keeping`
primitives (§2.2), which are still what the compiler's own long-running
loops use. Its closing premise — that cycles are not constructible — was
measured false (`MM-LIFE-3`), and losing that premise is part of why the
decision moved.

### 4.2 Macro system — pattern-based, hygienic, no compile-time evaluation

**Superseded 2026-08-14.** The normative specification is
[macro-system.md](macro-system.md), which carries per-rule status: what
holds, what is normative but unbuilt, and what is refused. The tier-1
decision this section made and that document inherited — **no
compile-time evaluation; expansion is a rewrite and nothing else** — is
`MAC-LANG-13`, and it is a property of the threat model rather than an
implementation convenience.

### 4.3 ADT revision — smaller than it sounds

Done. Struct variants match exhaustively, by name and punned; nullary
constructors are unboxed (`S1` above).

### 4.4 Concurrency — no language support, and a standard-library module

**Decided, and the decision held.** There is no language support, no
scheduler in the compiler, and no new primitive. `stdlib/Job.ax` is a
bounded pool of child processes over `Sys`'s `sysSpawn`/`sysWaitPid`
pair, answering in submit order, and the compiler is its first consumer.

**Processes, not threads, and that is forced rather than chosen.** A
freestanding binary cannot create an OS thread on macOS without libc.

### 4.5 HTTP — out of scope, and the shape it should have outside

**Decided 2026-08-15: HTTP is not a standard-library subject, in v1 or
after it.** There was never anything to delete — no `Http` module, no
socket surface, no `Net` anything has ever existed in `stdlib/`. The
removal was the removal of an *intention*.

The standard library's admission test is the one every module in
`stdlib/` already passes: it is either something the compiler itself
needs (`Str`, `Vec`, `Map`, `Intern`, `Json`, `Rpc`, `Job`, `Sys`), or
something no program can write for itself because it needs a primitive
only the compiler emits (`Mem`, `IO`). HTTP is neither. What changed
since the decision is that a program can now reach one without the
standard library at all, by binding a Rust crate through the FFI
([ffi.md](ffi.md)).

### 4.6 LSP — after self-hosting, not before

**Landed 2026-08-08, and the reuse argument held.** `axiom lsp` speaks
the lifecycle, full-text sync, `publishDiagnostics` and
`documentSymbol`, plus hover and go-to-definition over macro
invocations, in `self_host/lsp.ax` with `stdlib/Json.ax` and
`stdlib/Rpc.ax` — because every diagnostic comes from the same
`parseModuleWith`/`checkModule` pair `check` runs, and the outline comes
straight off the parse tree. It is the first tool surface with no
predecessor to differ against, so `scripts/check-lsp-selfhost.sh` gates
it against checked-in goldens for the whole framed session *plus* a
fact-by-fact comparison of every published diagnostic. The mandatory
vacuousness drill caught the gate's first version, which compared lines
and not columns; it fails that ablation now.

**An editing session no longer grows.** It held 3.4 MB per edit and
693.7 MB after two hundred; it is flat at 6.8 MB, and the gate runs the
boundary-removed ablation to prove the flatness is the boundary's doing.
This is the case §4.1 named and the one that had a number.

What the LSP still lacks is in "What is left".

---

## 5. Phases

The phase plan is complete through P5's tool-port list. Kept in one
table because other documents cite the phase names.

| Phase | Items | Where it stands |
|---|---|---|
| **P0** | Green CI; `union`/`region` removed; tree-sitter grammar | Done |
| **P1** | `B1` closures · `B2` tail calls · `B3` `Vec`/`Map`/`Intern` · ADT struct variants | Done; §2.4 carries each criterion and the number that met it |
| **P2** | Memory model | Strategy decided (reference counting) and the mechanism built: counts and shape words on every block, the release path and size-class reuse, reference maps in both halves, and all seven ownership events. What is left is the acceptance measurements — see "What is left" and [memory-model.md](memory-model.md) §9 |
| **P3** | Macro system · `B4` namespacing | Done but for three features, all named in "What is left". Expansion is a pass of its own ahead of the checker, hygienic in both directions, with declaration macros, a closed `syntax/*` query vocabulary, `derive` shipped in `stdlib/Pre.ax`, pattern rules, repetition, and format strings that make `println` a macro rather than a function per type |
| **P4** | Self-hosting phases 2–5 | Done. The fixpoint `stage2 == stage3` holds, and phase 4's original criterion — byte-identical `.ll` against the retiring compiler — was **replaced** rather than met: 0 of 71 comparable pairs were byte-identical, and what differed was stage1's calling convention, block structure and register naming, all three deliberate. A criterion that asks a new compiler to adopt a retiring one's design choices is the wrong criterion. Phase 4 exits on behavioural equivalence over both corpora at both optimisation levels through an identical toolchain, plus the four-target assembly check and the fixpoint. Widening the differential found a scalability ceiling underneath: the lexer's `lexTokens`/`dispatchChar` mutual tail calls cost a stage1-built compiler one frame pair per token, so it died between 96 KB and 146 KB of input where its predecessor read 396 KB. Both are loops now; measured past 814 KB |
| **P5** | Driver, bootstrap, fixpoint · LSP · `fmt` trivia · benchmarking · docs | The tool-port list is empty: check, build, run, emit-llvm, fmt, symbols, explain, the human renderer, the REPL and the LSP all exist in the self-hosted compiler, each gated. What remains of P5 is the published performance profile and docs |

---

## 6. Risks

The ones still live. Each retired risk was retired by a decision or a
gate, not by being forgotten.

| Risk | Standing |
|---|---|
| Procedural macros arrive as an implementation detail and silently make the compiler an arbitrary-code executor | **Live, and the mitigation is a refusal.** Tier 1 only; tier 2 would require an explicit, documented decision and a sandbox. `MAC-LANG-13` states it normatively |
| Cycles leak and a long-running program grows | **Live and priced in.** [memory-model.md](memory-model.md) `MM-LIFE-3`. A cycle collector stays separable; breaking a knot is a program obligation nothing checks |
| A gate passes while the property it protects is broken | **Live by nature**, mitigated by §3's two conventions. It has been realised twice and caught twice — once by a negative test, once by reading the process status |
| A tool with no CI gate is silently broken, as `fmt` was | **Retired for every tool surface that exists**: each is named with its gate in §2.1. It returns the moment a surface ships without one |
| The LSP is started early "in parallel" and blocks on missing language features | **Retired.** The dependency edges in §1 were the schedule and were followed |
| Macros degrade diagnostics | **Retired.** Realised in the direction nobody was watching — expansion ran *after* the checker, so an expansion was never checked at all — and closed by moving expansion into `self_host/expand.ax` ahead of it. A diagnostic inside an expansion now anchors at the invocation and carries one frame per enclosing macro ([macro-system.md](macro-system.md) `MAC-DIAG-4`) |
| The memory model is attempted at full generality and stalls | **Retired by decision rather than by generality**: reference counting, no whole-program inference at all |
