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
      │ Macro system   │   │ HTTP library     │  │ B4 namespacing   │
      └────────┬───────┘   └────────┬─────────┘  └────────┬─────────┘
               │                    │                     │
               │                    │                     │
               └──────────────┬─────┴─────────────────────┘
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

**HTTP depends on the memory model, not on native concurrency.** A
non-blocking HTTP library is an event loop plus per-connection state. An
event loop can be implemented in user space with the existing syscall
primitives; it does not require native concurrency. The memory model
provides the safety guarantees (no data races) that make a user-space
concurrency library sound.

**The LSP is last, and this is the least negotiable edge.** An LSP is
mostly maps and closures: a symbol index, an incremental cache, a table of
request handlers. Axiom today has `Vec`/`Map`/`Intern` (golden-tested and
validated at 10⁵; `Map`'s throughput is the open part), function values
(`B1`) and namespacing (`B4`). It is also the largest program that would be
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
| CI green on all four targets | §3 below; two root-caused failures fixed. Re-checked and **was not green** — see §2.5 — for two further reasons, both now fixed. Re-checked 2026-08-07: no run since 2026-07-30, so the row was not evidence of anything. **Re-checked again 2026-08-09 and it is still not: `gh run list` shows nineteen consecutive red runs since pushes to `trunk` began triggering on 2026-08-08, and the last green run remains 2026-07-30 — two days before the self-hosting work started. Six of nine jobs failed, every one of them a Linux job, every one at the same step (`Provision a compiler from the committed seed`) and the same assertion, so no Linux gate has run at all under the seed regime.** The cause was neither the compiler nor any gate: `bootstrap-from-seed.sh` assembled `stage2.ll` and `stage3.ll` in one directory, and on ELF `llc` writes the input's basename into the object, so the fixpoint comparison compared filenames. Fixed by the convention `check-bootstrap.sh` already used for the same hazard in the output direction, and the property is now gated for every target by `check-cross-targets.sh` — see [self-hosting.md §12](self-hosting.md). This row is evidence only of what the checks tab says today; re-read it before citing it |
| `fmt` round-trips every file | §2.3; 190/190, gated by `scripts/check-fmt.sh` |
| The REPL evaluates | §2.4; every result type, freestanding, gated by integration tests |
| Floating point works | §2.4b; arithmetic, comparison, conversion, formatting, and floats through ADTs — `tests/stdlib/240-float.ax` |
| Self-hosting fixpoint `stage2 == stage3` | `scripts/check-bootstrap.sh`, now run in CI (§2.5) |
| `union` removed, `region` removed | `AX2004` with migration advice; 3 regression tests |

| Editor grammar | [tree-sitter-axiom/](../tree-sitter-axiom/), 190/190 repo files, ~17 MB/s. The 18/18 this used to claim was true when the repo had 18 `.ax` files; the gate then silently skipped for want of its CLI while the real figure fell to 27/70. See the risk table |
| Freestanding stdlib | `Pre`, `Mem`, `Str`, `Vec`, `Map`, `Fmt`, `Intern`, `Sys`, `IO` over syscalls; no libc |
| Reproducible builds | byte-identical IR across runs, gated in CI |

Reproduce all of it:

```bash
./scripts/bootstrap-from-seed.sh
./scripts/run-stdlib-tests.sh
./scripts/check-freestanding.sh
./scripts/check-cross-targets.sh
./scripts/check-reproducible.sh
./scripts/check-tree-sitter.sh
./scripts/check-self-host.sh
./scripts/check-bootstrap.sh
./scripts/check-fmt.sh
```

All nine gates pass. There is no separate unit-test suite to run: the
Rust implementation these gates once compared against has been removed,
and each of them now carries its own half derived from something other
than the compiler's output. See `docs/self-hosting.md`.

### 2.2 The measurement that drives the schedule

Restored 2026-08-08: this section was deleted with the Game of Life
demo in 720a0d5 while four references to it stayed behind, so the
number the memory model exists to change had no in-tree reproduction.
`scripts/measure-memory-baseline.sh` is the reproduction now — it
generates the probe, builds it at `--opt 2`, and prints this table.

A 24×24 toroidal Life board — one board live at any moment, ~10 KiB —
advanced by `(advance (step board) (- n 1))`, the exact tail-call
shape §4.1 names as the hard case. The printed population is 5 at
every N (a lone glider), which pins that all N steps really computed
Life:

| Generations | Population | Max RSS | KiB per generation |
|---:|---:|---:|---:|
| 10 | 5 | 1.5 MiB | 148 |
| 80 | 5 | 2.6 MiB | 32 |
| 500 | 5 | 9.3 MiB | 18 |
| 2000 | 5 | 33.3 MiB | 16 |

Linear in generations, flat in live data: the bump allocator tracks
*total allocations*, not reachable data. The historical table here
read 744 MiB at 2000 generations; today's 33.3 MiB is 22× better and
**none of it came from reclamation** — the B3 data-structure work
simply allocates less per step.

**The managed twin (2026-08-08).** The same program with the loop
bracketed by the explicit arena primitives — mark once, then per
iteration copy the new board up, reset, copy down — holds **1.4 MiB
flat from 80 through 20,000 generations, population 5 throughout**,
and the per-generation column reads 0 at N=2000.
`scripts/check-memory-baseline.sh` gates all three claims in CI:
managed flat under 4 MiB, populations exactly 5, and — the negative,
run every time — a reset with *no* copy corrupts the board to
population 0, proving the gate sees the unsoundness class.

**Automatic insertion of that contract was re-scoped out of the
first slice by adversarial review** (three lenses, a judge, five
probes, all measured). The blockers, now the automation slice's
named prerequisites: (1) the compiler cannot see pointerhood —
`Int` is the universal heap-handle type and String unifies with Int
*by fiat*, so a type-directed trigger is either unsound (it fired
on the Life probe and corrupted it to population 0) or vacuous;
(2) ~~`arena_reset` strands chunks mapped after the mark~~
**fixed, see below**; (3) a
compiler-inserted copy-down was tried once before — `ArenaCompact`,
removed because codegen "could not see Str or Vec at all"
([self-hosting.md](self-hosting.md)) — and the review's first draft
re-proposed exactly that failure. The explicit contract is §4.1's
copy-at-boundary made real today; inference is the research half,
and it now has a measured target to hit.

**The allocator now reclaims chunks, and hands reclaimed memory
back zeroed (2026-08-08).** Two defects, one of which nothing had
ever asked about:

- *Stranded chunks.* A mark saved the waterline and the chunk end,
  so a reset could restore a position — but every chunk **mapped
  after** the mark was abandoned, because nothing recorded that it
  existed. Measured on a loop marking, allocating 1.5 MiB and
  resetting: 8.0 MiB at 10 iterations, 117.5 MiB at 200, linear at
  **576 KiB per iteration**. Chunks now carry a two-word header
  (size, previous chunk) and form a list; a reset walks it back to
  the marked chunk and moves what it passes to a free list that the
  next refill fits from. Same loop: **2.9 MiB, flat through 1,000
  iterations**.
- *Reclaimed memory came back dirty.* `Mem.memAlloc` documents that
  it returns **zeroed** memory, and the standard library spends that
  promise in load-bearing places — `Map` and `Intern` read an
  all-zero state array as "every slot empty", `strAlloc` reserves a
  byte for its NUL terminator and never writes one. A fresh mapping
  arrives zeroed from the kernel, so the promise held for free, and
  stopped holding silently the first time a reset handed the same
  bytes out twice. Probed: two bytes of a fresh 256-byte block read
  255, and `strAlloc 3` produced a string whose `cstrLen` was
  **17** — `strCStr` running off the end into whatever the arena
  last held there. So slice 1's "explicit contract" was unsound
  against the standard library the moment it was used with anything
  but `Vec`, and its own gate could not see it: the Life probe
  writes every slot it reads.

The fix is a per-chunk high-water mark. Memory above it has never
been handed out and is still the kernel's zeroes; memory below it
is scrubbed **as it is handed out**, one allocation at a time. That
placement is not an optimisation, it is the contract: §4.1's
copy-at-boundary reads the value being copied *out of the region
the reset just gave back*, so a reset that scrubbed would destroy
it. Scrubbing at the reset was in fact the first version of this
change, and `check-memory-baseline.sh` failed it in one run —
managed population 0. A reset writes no byte of what it reclaims,
and that is now a stated property rather than an accident of the
implementation.

Cost, best-of-7 at n=10⁶: `map` 0.0429 s → 0.0432 s, `intern`
0.2731 s → 0.2764 s, `vec` 0.0079 s → 0.0073 s. The extra load and
compare on the allocation fast path do not show above the noise,
and one self-compile's peak RSS moves 151 → 152 MiB against the
400 MiB ceiling.
`tests/stdlib/160-arena.ax` pins all three properties in both
compilers; on the pre-fix compiler its new cases print 510, 17 and
0 against the 0, 3 and 1 they now require.

This is not a pathological program. A loop that builds a value from
the previous value is the shape of every compiler pass, every request
handler, and every macro expansion. It is why the memory model is the
hinge of this roadmap rather than one item on a list.

### 2.3 `axiom fmt` round-trips source — and did not, in six ways

`fmt` was the one part of the CLI with no CI gate, and it had six
independent ways of silently destroying a source file. Formatting any of
the 70 `.ax` files in this repository lost something, and every loss was
reported as a successful format.

| Loss | Consequence |
|---|---|
| Every `(import ...)` declaration | Imports live in `Module::imports`; the printer walked only `Module::decls`. The formatted file no longer compiled |
| Every `pub` marker | The module's entire export surface. Parses fine, so nothing complains until an importer fails against a name still visibly present in the file |
| Every AXTAG | Real tokens, so the comment guard never counted them — the one category deleted without even a refusal. They are compiler-checked metadata |
| Every block comment | The lexer recorded spans for line comments only, so `#\| ... \|#` was invisible to the guard too |
| `((Red) 1)` → `(Red 1)` | A nullary constructor pattern becomes a *variable* pattern that binds anything. The first arm matches every value and every later arm is unreachable. Compiles, runs, returns the first arm's answer for every input |
| `(Circle { r : Int })` → `(Circle Int)` | A struct variant demoted to positional; every `s.r` and every named pattern then fails to resolve |

plus three spelling changes that were not losses but were not
round-trips either: `fn` rewritten to the legacy `define`, `(-> a b c)`
re-emitted curried as `(-> a (-> b c))` — growing a paren level per
parameter on every run — and `(let ((x 1)))` rewritten to `(let ((x = 1)))`,
a spelling that appears nowhere in the corpus and that the self-hosted
parser does not implement, so formatting a file broke the bootstrap.

Two of these had tests. Both tests asserted only an exit status, which is
why `fmt_counts_axtags_as_preserved` stayed green while the AXTAG it was
named after was being deleted.

**What changed.** Comments are now recovered from the spans the lexer
records as it discards them, and re-emitted by walking the tree and the
comment list together in source order: own-line comments are emitted
above the construct that followed them, trailing comments back onto the
line they annotated. A trailing comment is only re-attached to a
construct the formatter kept on one line, which is what makes the result
a fixed point — a one-line source construct that the printer breaks
across several lines would otherwise move its comment on every run.

`fmt` also verifies its own output before writing: the result must
re-parse, carry exactly the comments the input carried, and be a fixed
point under a second formatting pass. That check is a property rather
than a list of the bugs above, and it is what refuses rather than
destroys when a construct is still printed wrongly.

All 70 files now format. The gate is `scripts/check-fmt.sh`, which
formats a copy of the whole repository and re-runs the standard-library
and self-hosting suites against it — because the nullary-pattern bug
produced a program that parsed, compiled and ran, and only a behavioural
check could see it.

Trivia preservation is consequently **done** rather than scheduled for
P5. The LSP still needs the same machinery, and can reuse it.

**A seventh way arrived on 2026-08-09, and it was the least exotic of
them.** `fscanName` continued a name over its own local character set —
letters, digits, `_` and `'` — which omitted every operator byte
`isIdentChar` admits, so a name containing one was three tokens to the
formatter and one to the compiler. It printed the three:

| written | `fmt` wrote |
|---|---|
| `(fn (g) (h empty-list))` | `(fn (g) (h empty - list))` |
| `(fn (g) (h a+b))` | `(fn (g) (h a + b))` |
| `(fn (g) (h x-5))` | `(fn (g) (h x -5))` |

Written to disk, exit 0, no warning: a one-argument call becomes a
three-argument one. In declaration position it refused instead, so
`axiom fmt` could not format any file declaring a kebab-case name at
all — and `(:: empty-list (-> Int Int))` is a declaration `check`
accepts and runs.

`empty-list` is the point. The other six were exotic enough to be
plausible oversights; this one is the commonest non-alphanumeric naming
convention there is, and it survived because Axiom's own corpus is
camelCase — all 244 `.ax` files formatted byte-identically with it
broken. The fix deletes the local set and asks `lexer`'s `isIdentChar`,
and is measured to move nothing: 243 of 244 files format to identical
bytes and identical exit status, the one difference being the fixture
written to catch it. See
[self-hosting.md §15.3](self-hosting.md).

### 2.4 Open blockers, unchanged

`B1`–`B4` and `S1`–`S5` from
[self-hosting.md §2](self-hosting.md#2-capability-gaps-measured) all still
hold. The ones on the critical path here:

- **B1** — function values. **(DONE)** Closure record, indirect call;
  `tests/stdlib/140-function-values.ax`.
- **B2** — recursion depth no longer depends on `--opt`: tail calls are
  guaranteed in the IR, and `while` (S5) gives an explicit loop that
  runs 10⁷ iterations in constant stack at `-O0`. *Non*-tail recursion
  is still bounded, measured at 60,000–80,000 frames on an 8 MiB
  stack.
- **B3** — `Vec`, `Map`, and `Intern` are golden-tested and validated at
  10⁵ (`tests/stdlib/200-scale.ax`) and benchmarked at 10⁶
  (`scripts/bench-datastructures.sh`). **`Map` now meets the 2×
  criterion: 1.80×**, from 14×. The cause was never the allocator this
  entry used to blame: `mapHash` was affine in the key for keys below
  2²², so sequential keys clustered and linear probing ran 71 probes
  per insert; a real avalanche hash (fmix64) plus byte-wide state tags
  fixed it, and the earlier "growth is six sevenths of the cost"
  ablation was the same bug measured through rehash. `Intern` is
  *faster* than Rust (0.73×); `Vec` is 3.4×, three header loads against
  a register-resident Rust `Vec`, ~5 ms absolute at compiler scale.
  See [self-hosting.md §2.1 B3](self-hosting.md#21-blockers) for the
  full correction.
- **B4** — namespacing: `Mod::name` qualified access works; two modules can define the same name without collision. **(DONE)**
- **S1** — **(DONE)** nullary constructors are immediates rather than
  heap blocks, in mixed types as well as all-nullary ones; a `match`
  over a mixed type reads the tag through a runtime
  immediate-vs-pointer guard. Constructors with fields still box. See
  [self-hosting.md §2.2 S1](self-hosting.md#22-serious-but-workable);
  pinned by `tests/stdlib/270-nullary-unboxed.ax`.

---

### 2.4 The REPL could not evaluate anything

The same reasoning that found six bugs in `fmt` — a surface with no gate
is a surface nobody has checked — applies to the two the risk table
names next. `explain` held up. `repl` did not: it could not evaluate a
single expression.

Typing `(+ 1 2)` produced raw `llc` output and no result. The wrapper the
REPL builds around a typed expression bound C's `printf` to print it, and
since strings became first-class in 7b786e1 a `String` is the address of
a `{len, bytes}` header rather than a `char*`. The call emitted `i64`
where the declaration said `ptr`, so `llc` rejected every module the REPL
produced. Had it assembled, `printf` would have read the length word as
its format string.

That binding also made the REPL the one code path in the project that
called libc, which `check-freestanding.sh` forbids everywhere else — its
output declared `printf`, `puts`, `malloc`, `free`, `memset`, `memcpy`
and `exit`. Printing now goes through `IO`, so the REPL is freestanding
like everything else.

Four further problems were behind that one:

- **Failures printed nothing.** Every stage was wrapped in `if let Ok(..)`
  with no `else`, so an expression that failed to parse, resolve,
  type-check or lower produced no output at all — the REPL printed the
  type and returned to the prompt, which reads as the evaluator having
  decided the answer was nothing.
- **`:time` timed the compiler giving up.** It printed a duration
  whenever code generation succeeded, including for expressions that
  never ran.
- **The wrapper existed in three copies** — evaluation, `:time` and
  `:llvm` each had their own — so `:llvm` still emitted libc calls after
  the first two were fixed. They are now one function.
- **Scratch files were written to the working directory.** The REPL could
  not run at all from a directory without write access, littered a
  project on any early exit, and two concurrent sessions overwrote each
  other's object file. They now go to a private directory under the
  system temp dir.

A `Char` result exposed a bug in the compiler rather than the REPL. A
character literal lowered as `U8` while `Char` maps to `i64` everywhere
else — in signatures, in `strByte`'s `zext i8 to i64`, in `__store8`'s
truncate — so *any* function returning a `Char` emitted `ret i8` from a
function declared `i64`. `axiom check` reported OK and the failure then
arrived from `opt`, about generated code, for a program the compiler had
just called well-typed. Nothing in the standard library returns a `Char`,
so nothing had noticed. Pinned by `tests/stdlib/230-char.ax`.

The REPL and `explain` are now covered by integration tests that drive
the real binary, including one asserting that every code `explain --list`
advertises can actually be explained.

### 2.4b Floating point is implemented

Found by probing whether the `Char` bug above was one of a class: a
literal whose IR type disagrees with what the type maps to in LLVM.
`Float` had exactly the same defect, and rather more behind it.

Axiom had a `Float` type name and a lexer that read `1.5`, and nothing
else. The arithmetic operators were registered as `Int -> Int -> Int`
builtins, so any float operand was a type error; code generation emitted
no floating-point instruction of any kind — no `fadd`, `fmul`, `fsub`,
`fdiv`; and a function declared to return `Float` emitted `ret double`
from a function LLVM declared to return `i64`, so the error arrived from
`opt` after `axiom check` had reported the program well typed. No `.ax`
file in the repository contained a float literal, which is why none of
it had been noticed.

**The representation.** Every Axiom value is one machine word, and a
`double` is 64 bits, so a float is carried as the `i64` holding its
IEEE-754 bit pattern *everywhere* — parameters, returns, constructor
fields, `Vec` slots — and is bitcast to `double` only inside the
arithmetic itself. Nothing else in the compiler learns that floats
exist: `data`, `struct`, closures, `Map` and polymorphism carry them
unchanged, and no calling convention, field layout or type mapping
needed to change. The bitcasts are free at runtime, and the register
allocator keeps a chain of float operations in FP registers.

The cost of that choice is that *nothing about a value says it is a
float* — only its type does, and by lowering time the type checker is
gone. So the IR generator reconstructs it from signatures: which
functions return floats, which parameters are floats, which constructor
fields and struct fields are, and which `let` bindings and pattern
bindings therefore are. That is what decides whether `(+ a b)` lowers to
`add` or `fadd`.

**What works**: arithmetic and ordered comparison (`fcmp o*`, so NaN
compares false), float parameters/returns/locals, floats through `data`
constructor fields and patterns, `__intToFloat`/`__floatToInt` numeric
conversion, and `Fmt`'s `fmtFloat`/`fmtFloatPrec` for fixed-point
output with correct rounding carry. Mixing `Int` and `Float` operands is
an error rather than an implicit widening, since a silent conversion is
how precision is lost with nothing in the source saying so; `cast`
reinterprets rather than converts, which is exactly what lets a float
travel through the `Int`-typed standard library and come back intact.

**What does not**: `%` and the bitwise operators stay `Int`-only, and
formatting is fixed-point rather than shortest-round-trip (Ryu/Grisu
needs big-integer arithmetic and is a module of its own). `F32` is
accepted as a type name but computed at double precision, because one
value is one word.

Covered by `tests/stdlib/240-float.ax` and five integration tests. The
formatter needed a fix of its own to keep up: it printed a float through
`Display`, so `2.0` came out as `2`, which re-lexes as an `Int` — caught
by `check-fmt.sh` rather than by anything about floats.

### 2.4c The representation bugs were a class, not three accidents

`Char`, `Float` and `Bool` each failed in the same shape, and each was
found only by trying it rather than by any gate:

| Type | What it emitted | Why |
|---|---|---|
| `Char` | `ret i8` from an `i64` function | the literal lowered as `U8`, while `Char` maps to `i64` |
| `Float` | `ret double` from an `i64` function | no float lowering existed at all |
| `Bool` | `store i64 true` | `i1` is genuinely narrower than a word, and was stored into a field unwidened |

All three passed `axiom check` and then failed in `llc` or `opt` — a
native-toolchain message about generated code, for a program the
compiler had just called well typed. And all three went unnoticed for
the same reason: nothing in `stdlib/`, `self_host/` or `tests/` puts a
`Char`, `Float` or `Bool` in a field, so the corpus never asked.

The underlying property is one sentence — *every Axiom value is one
machine word, and a field is one word* — and it is now tested as one
thing rather than three: `tests/stdlib/250-field-kinds.ax` is the matrix
of every value kind against `data` constructor fields (single and
multi-field, so offsets are exercised) and `struct` fields.

`Bool` is the only Axiom type narrower than a word, so it is the only
one needing a widening at a word boundary; that widening is now applied
wherever a value enters a word slot, not only in the two arithmetic
sites that already did it.

**A fourth member arrived on 2026-08-09, and it is about names rather
than values.** `foo'`, `a+b` and `set!` are legal Axiom identifiers —
`isIdentChar` admits `! % & ' * + / < > = ^ |` on purpose, so that
`(+ a b)` is a call — and codegen wrote every name into LLVM unquoted,
where the legal set is only `[-A-Za-z0-9$._]`. Twelve of the fourteen
shapes probed passed `check` and then exited 4 with `opt` refusing
`define i64 @foo'(i64 %n)`. Same signature as the three above: accepted
by the frontend, killed by the native toolchain, `AX4003` against
`<toolchain>` with no span into the source. Same reason for surviving,
too — all 1,625 distinct top-level names in `stdlib/` and `self_host/` are inside
LLVM's set, so the corpus never asked.

The difference is what the gate had to be. The three rows above are
pinned by a matrix of value kinds against field positions, which is
finite and writable by hand. A name is not a value, and the property is
an agreement between two character sets, so
`scripts/check-symbol-names.sh` sweeps **the rule**: all 94 printable
bytes, in three positions, each of which must be refused with a span or
run to 42 — and which arm applies is decided by `symbols` rather than by
asking `isIdentChar`, because a backend graded against the lexer's own
answer is one implementation grading itself. See
[self-hosting.md §15.2](self-hosting.md).

### 2.4d A gate is only as wide as the corpus it runs on

`check-fmt.sh` formats every `.ax` file in the repository and re-runs the
suites against the result, which sounds exhaustive and is not: the corpus
uses `data`, `struct`, `fn` and `macro` and nothing else. Counted
directly — `type`, `trait`, `impl`, `effect`, `foreign`, `cond` and
top-level `lambda` appear **zero** times across `stdlib/`, `self_host/`
and `tests/`. So the formatter was broken for most of the language with
the gate green:

- `(type N = Int)` lost its `=`;
- a `trait` lost its `where`, its supertrait parentheses and its method
  `::`, and emitted per-method parentheses the parser does not accept;
- an `impl` lost its `where`;
- a type application lost its grouping, so `(Node (Tree a) a (Tree a))`
  became a **five**-field constructor and `(-> (Tree Int) Int)` became a
  two-argument function.

That last one is the instructive case. It still parses — it is
well-formed source that means something else — so neither `fmt`'s own
round-trip verification nor a re-parse can see it. Only type-checking the
output catches it.

Two changes. `tests/fmt/syntax-zoo.ax` carries every declaration and
expression form the parser accepts, so the gate no longer depends on what
the standard library happens to need; and `check-fmt.sh` now
*type-checks* the formatted zoo rather than only re-parsing it. Verified
to fail when the regrouping bug is reintroduced.

The zoo immediately found the same blind spot in the editor grammar:
`tree-sitter-axiom` described a `trait` syntax the compiler does not
implement — methods individually parenthesised, `where` introducing a
default body inside one — so it accepted no real trait at all. Fixed and
now at 74/74 files, and 190/190 as the corpus has grown since.

### 2.4e The parser could hang

Found while probing malformed trait declarations. Four hand-written
effect-list loops shared a shape:

```rust
while !self.check(RParen) && !self.at_eof() {
    if self.check(IO) { … } else if self.is_ident() { … }
    // no final `else` - and no advance
}
```

A token that was neither a known effect, an identifier, nor `)` left the
position unchanged, and the loop spun forever. `(trait (S a) (x) ((-> a Int)))`
hung the compiler: no diagnostic, no crash, no output. That breaks the
rule the project holds everywhere else — a malformed input produces a
diagnostic, not a hang — and it is the worst failure mode of the three,
because there is nothing to report and nothing to attach a span to.

All four are now one `parse_effect_list` that either consumes a token or
returns `AX2001` with a span. A twelve-case malformed-input sweep over
the other parenthesised loops found no further hangs.

### 2.4f `cond` was implemented everywhere except where it mattered

A feature can be absent while most of its code is present. `cond` had a
lexer token with the syntax written out beside it, an `Expr::ECond` node
in the AST, type-checking in `self_host/typecheck.ax`, effect walking, and a
formatter case. Two stages were missing, at opposite ends of the
pipeline:

- the **parser** had no `cond` case, so the word was reserved and could
  never be written — and every other stage's handling of it was
  unreachable code;
- the **IR generator** had no `ECond` arm either, so once the parser did
  produce one it fell through to the catch-all and the whole form
  evaluated to `0` whichever clause matched.

Both are now present. `cond` lowers to a chain of `if`, which is where
its tail-call behaviour comes from: `if` already detects a self tail call
in either branch, so `cond` inherits it rather than needing its own
analysis — three million iterations in constant stack, tested. A `cond`
with no `else` falls through to `0`, matching `while`, which also has no
last value to report. `else` is deliberately *not* a token: it lexes as
an ordinary identifier and is recognised by name inside `cond`, so it
stays usable as a variable everywhere else.

Covered by `tests/stdlib/260-cond.ax`, two integration tests, and an
entry in the syntax zoo.

The lesson is worth separating from the bug: **grep for a feature's name
across the crates and count the stages that mention it.** `cond`
appeared in five of seven. The two that did not were the two that make
it run.

It has since happened again, and the second time it was found by
running every expression form the parser accepts through both compilers
rather than by grepping. `(:: e T)` — a type ascription in expression
position — had a parser, a type checker and a formatter, and **no arm
in the IR generator**, so it fell through to the same catch-all and
`(fn (main) (:: 42 Int))` answered `0` after `axiom check` had called
the program well typed. Nothing in `stdlib/`, `self_host/` or `tests/`
ascribes an expression, which is the whole reason it survived. Pinned
by `tests/selfhost/870-ascription-and-negation.ax`, which answers 248
against the previous compiler and 42 now; the sweep that found it is
described in
[self-hosting.md](self-hosting.md#sweeping-every-expression-form-rather-than-the-next-one).

### 2.4g Float-ness of a struct field, when two structs disagree

`EField` gives a field's *name* but not the struct it belongs to, and the
type checker is gone by the time the IR generator needs to know whether
`.v` is a float. Float-ness was therefore keyed on the field name alone,
so two structs declaring `v` — one `Float`, one `Int` — collided.

It now resolves towards integer unless *every* struct declaring that name
declares it float. The direction matters: resolving towards float emits
`fadd` for an integer field, silently computing nonsense from the bits;
resolving towards integer costs a float field its arithmetic only in a
program with two same-named fields of different kinds, and that surfaces
as a type error rather than a wrong answer. Pinned by an integration
test.

### 2.4h The zoo covered every form, and one thing inside all of them

§2.4d widened the gate from what the standard library happens to need to
every declaration the parser accepts, and the widening worked — it found
four losses on the spot. It was still narrow in a direction nobody had
thought to name: the zoo carried every *form*, and every type inside
those forms was a bare name or an arrow.

A type application is not either. `(Box Int)` is two tokens with no
delimiter of its own, so a position that prints it bare hands its parent
an extra argument. `format_type_atom` existed to wrap exactly that, and
it was called from three of the twenty places that print a type.
Measured directly, one probe per position, against the formatter as it
stood:

```
18 of 20 positions destroy a parenthesised type application
```

`(:: b (Box Int))` came out as `(:: b Box Int)`, which does not parse at
all; so did a type alias, a `foreign` binding, a struct field, a named
constructor field, a trait method, an `impl`'s type, an effect
operation, `cast`, `alloc`, `sizeof`, `alignof`, a type-signature
expression, a supertrait, and the interiors of `[..]`, `(* ..)` and
`(linear ..)`. The two survivors are the reason it stayed invisible:
`data`'s positional field was one of the three already calling the
wrapping spelling, and `(forall a T)` re-reads its own juxtaposition as
the same thing it printed.

Every one of the eighteen *refused* rather than wrote, because `fmt`
verifies its output before writing — so this was never data loss. It
was `axiom fmt` declining to format any file that named an applied type
outside an arrow, and no file in the repository does.

**The fix is which name is short.** The wrapping spelling is now
`format_type` and the bare one is `format_type_bare`, called from the
single place that supplies the parentheses itself. Renaming rather than
editing eighteen call sites is the point: the default spelling is the
safe one, so the next position to print a type is correct without anyone
remembering this.

Two things fell out of writing the probes, both recorded rather than
fixed:

- **`forall` is not implemented.** `Type::TForall` exists in the AST and
  `fmt` prints it, but `parse_type` has no `forall` branch, so
  `(forall a a)` is read as a three-element *tuple of type variables* —
  `axiom check` renders the mismatch as `expected (forall, a, a)`.
- **The editor grammar's tuple type is the wrong shape.** It requires
  commas (`(A , B)`); the parser refuses a comma there and reads a
  space-separated `(A B)` as the tuple. Neither spelling can go in a
  file that both gates must accept, which is why the zoo has no tuple
  type.

### 2.5 CI was not green, and could not have been

The claim in §2.1 that CI was green on all four targets did not hold when
re-checked, for two reasons that were each enough on their own.

**The `lint` job failed on eleven clippy warnings.** It runs
`cargo clippy --all-targets --all-features -- -D warnings`, and eleven
warnings were present on a clean checkout. Every other job declares
`needs: lint`, so the entire pipeline was blocked behind it — no test job,
no matrix, no cross-target check ever ran. All eleven are now fixed.

**The `test` matrix ran a script that does not exist.** The final step
invoked `scripts/check-game-of-life.sh`, which was removed in 720a0d5
along with the sample it ran; the step referencing it was not. Every run
of that job would have failed on a missing file — on all three matrix
platforms.

Two gates were also present in the tree and wired into nothing:
`check-self-host.sh`, the only gate that exercises stage1 end to end, and
`check-bootstrap.sh`, which checks the `stage2 == stage3` fixpoint that
the whole self-hosting effort is aimed at. Both now run in CI. Both pass;
the fixpoint is reached.

This is the same failure the risk table already names — a gate that
cannot fail, or does not run, reports success without checking anything —
appearing in the workflow file rather than in a script.

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
anyway, so only `-O0` fails — and `axiom run` previously used the `-O0` path.
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

**The watermark machinery is built, and copying at the boundary has
one requirement the table above does not show.** The value being
copied *down* to the watermark is itself sitting above that
watermark — in the memory the reset just reclaimed — so it has to
survive being read after the reset. That is now a stated property of
the allocator rather than an accident of it: a reset writes no byte
of what it reclaims, and the zeroing `memAlloc` promises is
delivered per allocation, as each byte is handed back out (§2.2).

It leaves a sharper obligation than "copy at the boundary" suggests,
and the first version of this work got it wrong. Copying down through
ordinary allocation is only sound when the destination cannot reach
the source — which holds when an iteration's garbage exceeds its live
set, and fails exactly when it does not: a server holding a 150 KB
document and then handling a 200-byte request would allocate its
copy straight over the original. The Life probe never showed this
because its live set is constant and its garbage is larger.

**So the reclaim and the copy are one operation.**
`(__axiom_arena_reset_keeping mark addr bytes)` rolls the waterline
back exactly as `__axiom_arena_reset` does and carries one contiguous
block across the reclaim, answering where it landed. Because the
destination is never handed out through `axiom_alloc`, it is never
scrubbed — the copy is what initialises it — and the copy runs
forwards, which covers both directions it can face: within a chunk the
source was allocated after the mark so `dst <= src`, and across chunks
the two ranges are separate mappings that cannot overlap at all (which
matters, since `mmap` returns chunks in no particular address order).
When the kept block will not fit in what remains of the marked chunk,
the destination comes from a fresh mapping rather than the free list,
because the free list at that moment holds the chunks the same call
just reclaimed — one of which may be the source's.

`tests/stdlib/165-arena-keep.ax` pins it through both compilers over
the overlapping case, a chunk crossing, a block too large for the
marked chunk, and the zeroing promise around it. Written the way a
caller would have to write it without the primitive — reset, then
allocate and copy — the same four cases lose 39,841 of 40,000 bytes,
4,080 of 4,096, 2,088,797 of 2,097,152, and 1,020 of 1,024.



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
the current stdlib is full of, and generating
the repetitive parts of a self-hosted compiler. Tier 2 should not be
smuggled in as an implementation detail of tier 1; it is a change to the
compiler's threat model and needs a sandbox and an explicit decision.

**Hygiene.** The mechanism is scope sets: an identifier becomes a
`(name, scopes)` pair rather than a bare name, every macro expansion
introduces a fresh scope, and resolution matches on both. Free identifiers
in a template resolve at the macro's *definition* site; binders introduced
by a template are renamed. Concretely this means adding a scope field to
an identifier's scope set in `self_host/parser.ax` and teaching name
resolution in `self_host/typecheck.ax` to compare them. That is the first commit, and it is
independently testable before any macro exists.

**Type-checked output is free; good diagnostics are not.** This
paragraph used to open "Expansion runs before semantic analysis, so
expanded code is type-checked like any other code", and **that was
false of this compiler when it was written**. Expansion ran inside
`emitExpr`, at emit time, strictly after `checkModule` — so nothing a
macro generated was type-checked at all. An undefined name, an
under-applied call and a non-exhaustive `match` inside a template each
reported `OK` from `axiom check` and exited 0. It is true now, since
2026-08-09: expansion is `self_host/expand.ax`, between import
resolution and the checker.

The premise being false is why the sentence after it was the wrong
worry. The stated problem was that a type error in expanded code points
*inside the macro*, at source the author never wrote; the actual
problem was that there was no diagnostic to point anywhere. What
remains of the original concern is real and is criterion 3 above:
`Diag` needs an expansion backtrace whose frames carry a span and a
unit, and the AXDL `&` field needs a location. Today a diagnostic from
inside an expansion anchors at the invocation — a real span, in the
right file — and does not name the macro.

**The field is rendered, and it is narrower than this section assumed.**
`Diag` carries a `trace` vector, AXDL renders it as `&"frame"` per
entry, the human renderer as `= note: in this expansion of ...`, the
JSON as an `expansion` array, and the LSP appends it to the message.
Nothing populates it. What re-reading it for the macro work found is
that "the field is ready" was too strong on two counts, neither
visible from the rendering side: its element type is `Vec of Str`, so a
frame can carry pre-rendered English but **not a span**, and a `Diag`
carries **one** unit, so a macro defined in one file and invoked in
another cannot have both its spans resolved against the right source
text. Criterion 3 is therefore a `diag.ax` layout change plus all four
renderers plus the published AXDL grammar plus
`tests/selfhost/645-axdl-repetition`'s hand-built expected string —
not the wiring job the paragraph above described.

**Acceptance criteria, and where each stands (2026-08-09).**

| | Status |
|---|---|
| A `derive`-style macro generates a working `Eq` instance for a `data` type, with exhaustiveness still checked on the generated `match` | **Half.** Exhaustiveness *is* now checked on a generated `match` — the same `AX3005` the hand-written one draws, pinned by `tests/diagnostics/`. The `derive` half is untouched: a template is an expression, a macro in declaration position is `AX2003`, and `deriving (Eq)` still parses and is discarded |
| A macro that introduces a binding named `x` does not capture a user's `x`, and the reverse | **Half, and the halves are not symmetric.** The forward direction is done for every binder a template can introduce — `let`, `let mut`, `lambda`, `match` arm patterns — by renaming to `<name>.<counter>`, gated by `tests/selfhost/361-macro-hygiene.ax` (143; the unfixed compiler answers 208). The reverse direction is **also done for a macro defined in a module** (`tests/selfhost/364-macro-definition-site.ax`, 157 against the unfixed compiler's `AX3004`): a template's free identifier now resolves where the macro was written, which closed a live wrong-answer bug — one macro in one module used to mean two different things depending on the caller's module, 6 against 50, with no diagnostic from either compiler because both were resolving a name that really was in scope. It does **not** reach a macro defined in the ENTRY file, whose declarations are left bare and so have no distinct name to resolve to; that residue is a loud `AX3004` rather than a wrong answer. Nor is the macro NAME itself qualifiable — `Pre::when` is `AX3001`. See [macros.md §3](macros.md) |
| A type error inside an expansion reports the macro *and* the invocation site, both with real spans | **Half.** The invocation site is real and in the right file; the macro is not named. This is a `Diag` data-model limit, not missing wiring — a `Diag` carries one unit, the realistic case is a stdlib macro invoked from a user file, and the `trace` element type is `Vec of Str`, which can hold pre-rendered English but not a span |
| Macros work over `data`, `struct`, lambdas, lists, and tuples — one corpus case each | **Done, and it was not a corpus problem.** Substitution reached 8 of the 16 forms a template can contain and returned the rest *unrebuilt*, so `struct` construction, field access, field store, `let mut`, `set`, `while`, `alloc` and `handle` each leaked the template's own identifiers into the IR — all eight silently, all eight surfacing as `AX4003 opt failed` against `<toolchain>`. Every form now has a case and the default arm **refuses** (`AX3021`) instead of passing the node through, which is what stops the ninth. `tests/selfhost/362-macro-coverage.ax` (57; the unfixed compiler exits 4). Lists and tuples turn out to need no case at all: `[T]` and tuples are TYPE nodes, so a list or tuple value is a constructor application, which was always covered |

**Also landed, and not on the original list.** A macro name used to
outrank every binder in the program — `(macro (v) 9)` made a function
parameter named `v` evaluate to 9 — because emission consulted the
macro table before the symbol table. Expansion now carries the bound
set (`tests/selfhost/363-macro-shadowing.ax`, 3 against 18). A
self-referential macro segfaulted the compiler in ~9 ms with no output
and is now `AX3019`. Arity is checked in both directions (`AX3018`):
under-application used to leave the parameter's own name in the
generated code, and over-application dropped the surplus argument
*without evaluating it*.

### 4.3 ADT revision — smaller than it sounds

Axiom already has Rust-style ADTs: tagged sums, recursive types, nested
constructor patterns, and compile-time exhaustiveness checking. That is
verified. The actual gap against Rust is
narrow:

1. **Struct variants. (DONE)** `(data Shape (Circle { r : Int })
   (Rect { w : Int, h : Int }))` declares named fields per variant.
   They are accessible by name (`s.r`) and matchable by name
   (`((Rect { w = w, h = h }) ...)`), independent of declaration order,
   and an arm may name a subset of the fields rather than supplying a
   placeholder for each one it ignores. Covered by
   `tests/stdlib/210-struct-variants.ax`, which checks the named and
   positional spellings agree on every constructor and that a reversed
   named pattern binds by name rather than by position.
2. **Nullary constructors should not allocate** (`S1`). **(DONE)**
   `(Nil)`, `(None)` and every other fieldless constructor is an
   immediate tag, in mixed types too; only constructors with fields
   allocate.
3. **Field punning in patterns. (DONE)** `{ w, h }` is `{ w = w, h = h }`.
   Mixes freely with explicit binding, and named patterns nest.

What remains of this item is *named construction* — `(Rect { w = 3, h = 4 })`
as an alternative to the positional `(Rect 3 4)`. Values are still built
positionally, in declaration order. This is the one place the type's
field names are not yet honoured, and it is the smaller half: a
constructor call is written once per value, whereas a pattern is written
once per use site, which is why matching was done first.

Item 2 landed ahead of the memory model: the representation change
needed nothing from the allocator, only a runtime immediate-vs-pointer
guard at match sites over mixed types.

### 4.4 Concurrency — delegated to third-party libraries

Concurrency is not a native feature of Axiom. The design below is preserved
as guidance for a future third-party library, but the compiler and standard
library will not ship with native concurrency primitives, a task scheduler,
or constructors like `parMap`.

**Rationale.** Axiom's memory model (arena inference, linear types) already
prevents data races by construction — no mutable aliasing is constructible.
A library author can build a safe, structured concurrency library on top of
this foundation without language-level support. Bundling concurrency into
the language would couple Axiom's release cadence to concurrency design
decisions that are better made independently, and would add surface area to
the compiler for a feature used by a subset of programs.

**Design guidance (for a third-party library).**

- Structured concurrency with no shared mutable state.
- Each task gets its own arena, reclaimed at join.
- Values handed to a task are copied or moved (linear types make moves safe).
- Results are moved into the parent arena at join.
- Determinism: results combined in argument order (`parMap`), independent of
  completion order. Scheduling may be nondeterministic; observable behaviour
  is not.
- Driving use case: parallel compilation (independent modules type-check in
  independent arenas with no shared state).

### 4.5 HTTP library — deferred on purpose

Small, resilient, non-blocking, pure Axiom. It needs, in order: `Vec` and
`Map` (`B3`) for headers and routing; an event loop (implementable in user
space with existing syscall primitives — native concurrency is not
required); and non-blocking syscalls, which are new `Sys` surface
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

**The first slice has landed, and the reuse argument held.** `axiom lsp`
speaks the lifecycle, full-text sync, `publishDiagnostics` and
`documentSymbol`, in 1,400 lines across `self_host/lsp.ax`,
`stdlib/Json.ax` and `stdlib/Rpc.ax` — because every diagnostic comes
from the same `parseModuleWith`/`checkModule` pair `check` runs, and
the outline comes straight off the parse tree. The estimate this
section used to imply — "comparable in size to the current compiler"
— was an estimate of *reimplementing* a frontend, and this does not
reimplement one.

**An editing session no longer grows.** This is where §4.1 stops
being a roadmap item and starts being a feature: the server reuses
the frontend, so every edit re-parses and re-checks, and on an
allocator that never freed, every one of those was retained for the
life of the process. Measured on `didChange` of a 16 KB file: 8.3 MB
after one edit, 693.7 MB after two hundred — **3.4 MB per
keystroke-sized edit**, which is a leak with a language server
attached rather than a language server.

A request's working set is genuinely dead at the request boundary,
so the loop marks the arena once and reclaims to that mark after
every message, carrying the only two things that survive — the
document store and whatever bytes of the next message the reader
already buffered — across the reclaim as one block, through
`__axiom_arena_reset_keeping` (§4.1). The same 200-edit session now
peaks at **6.8 MB, flat**; a two-document session with interleaved
edits, outline requests, closes and reopens reads **6,816 KiB at 4,
12 and 60 rounds** where the old build climbs to 248 MB — and emits
a **byte-identical** protocol stream. `check-lsp-selfhost.sh` gates
it: both the 5-edit and 200-edit sessions must publish diagnostics
for every edit and answer their shutdown before the memory
comparison is allowed to mean anything, and the growth over 195
further edits must stay under 2 MiB. With the boundary removed the
gate reports 60,158 bytes per edit and fails.

What the server still does not do is the part that genuinely needs
new machinery: hover, completion and go-to-definition all want a
type at a position, and `typecheck.ax` retains no node-to-type
table. That is the next LSP slice and it is a real one. Two smaller
gap is recorded rather than hidden: diagnostics for imported
modules are filtered out instead of being published under their own
URIs.

~~a file that does not parse gets one spanless `AX2003`~~ **fixed.**
A parse failure now carries a code and a span, so an editor puts a
squiggle on the offending token instead of one note at line 1 — and
the gate got *stronger* rather than being re-blessed: unparseable
fixtures used to be exempt from the stage0-derived comparison
because stage1 could not agree, and the exemption is gone.

One structural finding, in
[self-hosting.md](self-hosting.md#the-language-server-the-first-surface-with-no-stage0-to-copy):
the frontend was library-shaped everywhere except import resolution,
which calls `sysExitWith` on a module it cannot read. Correct for a
compiler, fatal for a server, so the imports are walked non-fatally
first.

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
| **P0** *(done)* | Green CI; `union`/`region` removed; tree-sitter grammar | All seven gates green on all four targets |
| **P1** *(done)* | `B2` tail calls · `B3` `Vec`/`Map`/`Intern` golden tests and scale validation · `B1` closures · ADT struct variants | 10⁷-iteration loop at `-O0` ✓; higher-order probe runs ✓; struct variants match exhaustively, by name and punned ✓; `Map` within 2× of Rust ✓ (1.80×, was 14× — an affine-hash bug, not the allocator; see §2.4 B3) |
| **P2** | Memory model (§4.1) · ~~`S1` unboxed nullary constructors~~ **(DONE)** · ~~`Map` throughput~~ **(DONE, 1.80×)** | ~~`Map` insert at 10⁶ within 2× of Rust~~ ✓ met — and not by allocator work: the cost was an affine hash, corrected in B3. §4.1's actual subject — deterministic reclamation for long-running programs — is **met for the LSP**, which is the case the roadmap named and the one that had a number: an editing session held 3.4 MB per edit and 693.7 MB after two hundred, and is now flat at 6.8 MB, gated by `check-lsp-selfhost.sh` with the boundary-removed ablation run. Three things got it there: the allocator returns chunks a reset passes rather than stranding them (576 KiB per iteration, measured); reclaimed memory is handed back zeroed, which it was not, and which `Map`, `Intern` and `Str` all assume; and `__axiom_arena_reset_keeping` makes reclaim-and-copy one operation, because as two it scrubs the source whenever the live set exceeds the garbage. **What remains of P2 is inference** — the compiler placing these calls rather than a programmer, whose named blocker is still that the compiler cannot see pointerhood (§2.2). The single-shot compiler process has no P2-blocking measurement, and the HTTP server does not exist yet to have one |
| **P3** | Macro system (§4.2) — expansion moved before the checker, binder hygiene, coverage and refusals done (2026-08-09); `derive`, declaration-level macros, repetition patterns and module-qualified macros remain · ~~`B4` namespacing~~ **(DONE)** | Hygiene test passes (`tests/selfhost/361-macro-hygiene.ax`, 143 against the unfixed compiler's 208); two modules define the same name without collision. A bare reference *inside* a module now binds to that module's own definition first, in both compilers: before it, an entry file defining `helper` silently redirected an imported module's own call to its own `helper` — importing a module changed what that module did, with no diagnostic from either side (`tests/selfhost/850-module-local-binding.ax`). Resolution outward from a module is still the merged declaration list rather than that module's import set, which is the remaining half of the flat-namespace decision |
| **P4** | Self-hosting phases 2–5 · HTTP library (§4.5) | `stage2 == stage3` ✓; HTTP server serves a request under load. Phase 3 (semantic analysis in Axiom) has begun and meets its criterion for the checks that exist: stage1 emits **byte-identical AXDL** for **all seventeen** `AX30xx` codes, gated three-way against a checked-in golden by `scripts/check-diagnostics.sh` (36 cases). Type checking proper is done — `parseSigDecl` keeps type structure, and `AX3004`/`AX3005`/`AX3007`/`AX3008` compare types exactly where stage0 does, with no unifier. Effect inference is a monotone fixpoint over the call graph with effect-transparent parameter marks, so its sets match stage0's. Imported modules are checked too, each rendered against its own filename. Phase 3's exit criterion is met; grouping is a no-op on both sides, since no producer in stage0 ever sets a group key. Phase 4 re-measured (2026-08-07): 0 of 71 comparable `.ll` pairs are byte-identical, and the raw-versus-post-`mem2reg` question the criterion was waiting on is now answered — normalising does not help (46 diff lines becomes 50 on the simplest program). What survives is stage1's calling convention, block structure and register naming, all three deliberate; the arithmetic already matches. So the criterion asked stage1 to adopt the retiring compiler's design choices rather than to converge on lowering, and **it has been replaced**: phase 4 now exits on behavioural equivalence between the compilers over both corpora at both optimisation levels through an identical toolchain, plus the four-target assembly check and the fixpoint (which still requires byte-identity where it carries meaning, `stage2 == stage3`). Widening the differential gate to carry that criterion found stage0's own output overflowing the stack on `320-effect-gc-roots` through a raw `llc` pipeline where stage1's does not, because stage0's frames carry a hidden closure parameter and spill their bindings — converging stage1's IR onto stage0's would have imported that. It also found the gate **was not in CI at all**, which is the risk this table's last-but-four row names; it runs there now, over 106 cases with a counted floor. Scouting also found that **nothing ran `tests/stdlib/` through stage1**, hiding five miscompiles; `scripts/check-stdlib-selfhost.sh` now gates them, and that gate now has **no skip list at all — 33 of 33 agree**, because the effect system lowers through stage1 too (evidence slots, outward dispatch from a handler performing its own effect, and the unhandled-operation trap). Doing it exposed a scalability ceiling underneath: the lexer's `lexTokens`/`dispatchChar` mutual tail calls cost a stage1-built compiler one frame pair per token, so it died between 96 KB and 146 KB of input where a stage0-built one read 396 KB. Both are loops now; measured past 814 KB |
| **P5** | Driver, bootstrap, fixpoint · LSP (§4.6) · ~~trivia preservation for `fmt`~~ **(DONE, §2.3)** · benchmarking · docs. Phase 5's first item — module resolution — is **done**: stage1 reproduces stage0's search order (entry dir, `AXIOM_PATH`, `AXIOM_STDLIB`, exe-relative), where it previously searched two paths relative to its working directory and could not compile a file importing `IO` from anywhere else. Its host target is a per-target `Host` module rather than the literal `"darwin-aarch64"`, which is what the Linux fixpoint job needed to mean anything. `Sys` can now spawn and wait for child processes on all four targets, which is the capability a self-hosted `build` needs. **The driver is done**: `stage1 build --input self_host/main.ax --output stage2` writes the IR, runs `opt`/`llc`/`cc` and cleans up after itself, and the compiler it produces builds a byte-identical successor — `check-bootstrap.sh` runs the ladder a second time with the compiler driving the toolchain instead of the harness, and finishes by building and running a real program through the self-built compiler. `check`, `emit-llvm`, `run` and `version` are the rest of the surface; the old `stage1 FILE [TARGET]` spelling still works, because five harnesses use it. ~~What remains for P5 is `fmt`~~ — **`fmt` is done and gated** (2026-08-07): `stage1 fmt` formats all 194 repository files to byte-identical output with identical exit status under both compilers, `--check` included; the zoo is three-way against the checked-in golden; and a 33-case parity bank pins the deliberate refusals. `scripts/check-fmt-selfhost.sh` is the gate, in CI, floors counted, negative test run (an ablated normalisation fails it). The design held as decided — a concrete syntax tree with its own scanner, thirteen normalisations as rewrites — and the port surfaced stage0 behaviours nobody had documented, now reproduced bug-for-bug or refused exactly as stage0 refuses; see [self-hosting.md](self-hosting.md#the-formatters-back-half-the-same-function-measured). ~~`symbols` and `explain`~~ are **done and gated** (2026-08-07, same day): `explain` generated byte-for-byte from stage0's own output, 40/40 on its first differential; `symbols` at 196/196 files with identical bytes and status in both modes, after moving stage0's nid to a specified hash (FNV-1a 64 - `DefaultHasher` is unspecified across toolchains) and fixing what the port dislodged: stage1's import order now hoists like stage0's, imported modules keep their AXTAGs, `type`/`trait`/`deriving`/multi-body-`fn` parse, and `[` `]` are tokens instead of silently skipped bytes. `scripts/check-tools-selfhost.sh` gates both, live and two-sided, floors counted, negative tests run. ~~The human diagnostic renderer~~ is **done and gated** (2026-08-07): `stage1 check` renders rustc-flavored plain-text reports by default — snippets, char-counted caret columns, every help the diagnostic carries — plus stage0's JSON shape and the exact failure trailer, behind `--diagnostic-format` with stage0's full alias set. Deliberately NOT a byte-clone of stage0's human output: that output is the `ariadne` crate's (probed: per-character ANSI even when piped, and all helps but the last silently dropped), an internal of the retiring compiler — the phase-4 precedent applied to a tool. `scripts/check-render-selfhost.sh` gates it in CI: against 56 checked-in `.human` goldens (36 at the time), cross-checked fact-by-fact against the AXDL goldens stage0 itself equals, exit statuses compared to stage0's per case, floors counted, caret-ablation run (36/36 fail ablated, 36/36 pass restored). The port surfaced two pre-existing divergences the AXDL gate could not see: warnings-only files exited 1 under stage1 where stage0 exits 0 (fixed — only errors gate), and stage0 prints the failure trailer in `ai` mode where stage1 printed none (fixed — every format). ~~The REPL~~ is **done and gated** (2026-08-07): `stage1 repl` reproduces stage0's piped surface byte-for-byte over a 12-session bank — every scalar result type, declarations and state, semantic errors and recovery, the full colon-command dispatch including stage0's unreachable-`?` bug, comment/blank handling, `:quit` semantics — 9 sessions byte-identical three-way (golden == stage0 == stage1), 3 marker-pinned where stage0 is nondeterministic or divergent by decision (`:time` brackets the eval with the new `sysNowMicros` - the clock primitive P5's benchmarking item wanted, landed early because a probe of its syscall found the flags-clobber miscompile; `:llvm` prints each compiler's own IR; `:defs` and stage0's leaked `_fn_0` tyvar under redefinition are recorded, not cloned). Interactive affordances (rustyline editing, history) are deliberately not ported — the piped surface is the tested contract and the editor-grade interface is the LSP's business. Porting it found and fixed a latent lexer bug: a string whose closing quote is the input's last byte lexed as `TK_ERROR`, impossible to hit from a module file and the first thing the REPL fed the lexer. `scripts/check-repl-selfhost.sh` gates it in CI, floors counted, stderr required empty, ablation run (9 sessions fail without the `type :` line; 12/12 restored). **The P5 tool-port list is empty**: every stage0 tool surface — check, build, run, emit-llvm, fmt, symbols, explain, the human renderer, the REPL — now exists in the self-hosted compiler, gated two-sided. What remains of P5 is benchmarking (its clock primitive already landed) and docs. **The LSP's first slice has landed** (2026-08-08): `axiom lsp` speaks the lifecycle, full-text sync, `publishDiagnostics` and `documentSymbol` over JSON-RPC on stdin/stdout, reusing the self-hosted frontend rather than reimplementing it — 1,400 lines across `self_host/lsp.ax`, `stdlib/Json.ax` and `stdlib/Rpc.ax`. It is the first tool surface with no stage0 counterpart to differ against, so `scripts/check-lsp-selfhost.sh` is the native-surface shape the human renderer established: 7 fixtures (floor 7) byte-gated against checked-in goldens for the whole framed session, PLUS every published diagnostic compared fact-by-fact against stage0's own AXDL — severity, code, line, and the column converted from stage0's 1-based character index into LSP's 0-based UTF-16 code unit. Running the mandatory vacuousness drill caught the gate: with `lspChar` ablated to a byte count and every golden RE-BLESSED from the ablated build, the first version passed 7/7, because it compared lines and not columns. It now fails that ablation (server 23, stage0 20) and passes restored. The server built by stage0 and the server built by stage1 emit byte-identical protocol streams; peak RSS for one self-compile moves 176.8 → 187.0 MiB against a 400 MiB ceiling. Hover, completion and definition are NOT in it: they need a type at a position and `typecheck.ax` keeps no node-to-type table, which is the next slice and a real one | Completion and diagnostics in a real editor; ~~`fmt` round-trips every file in the repo, gated in CI~~ ✓ 190/190, gated by `check-fmt.sh`; published performance profile |

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
| Macros degrade diagnostics | Partly realised, in the direction nobody was watching: expansion ran *after* the checker, so an expansion was never checked at all — an undefined name, an under-applied call and a non-exhaustive `match` inside a template each compiled clean and exited 0, and a template using `while` or a field access produced invalid LLVM reported as `AX4003` against `<toolchain>`. Fixed by moving expansion into `self_host/expand.ax` ahead of the checker; those are now `AX3001`/`AX3013`/`AX3005` anchored at the invocation. The remaining half is naming the *macro* as well as the invocation, which the `trace` field cannot express as typed — see §4.2 |
| The LSP is started early "in parallel" and blocks on missing language features | The dependency edges in §1 are the schedule; the tree-sitter grammar covers editor basics meanwhile |
| A gate passes while the property it protects is broken — as happened for PIE relocations | Every new gate gets a negative test proving it fails when it should. Done for the relocation and grammar gates. It happened again on 2026-08-09 in a form no negative test would have caught, because the gate's assertion was satisfied by the compiler *dying*: `check-fmt-selfhost.sh` §5b hands every formatted output back to the compiler and fails if it carries an `AX1xxx` or `AX2xxx`, and `tests/fmt/parity/170-empty-tuple.axp` is the file `(fn (f) ())`, on which `check` was SIGSEGV — no output, so no diagnostic, so the case passed, in CI, for as long as it has existed. **A process killed by a signal satisfies every check written as "the output must not contain X."** Fixed by reading the status before believing the output, and generalised by `scripts/check-degenerate.sh`, whose assertions are about the process rather than its output; see [self-hosting.md §13](self-hosting.md) |
| A tool with no CI gate is silently broken, as `fmt` was | Either gate it or make it fail loudly. `fmt` now verifies its own output before writing and is gated by `check-fmt.sh`, which checks behaviour — it formats a copy of the repo and re-runs the suites — because the worst of its six bugs produced a program that parsed, compiled and ran, and returned the wrong answer. The prediction held for the other two surfaces this row used to name: `repl` could not evaluate a single expression (§2.4), `explain` was sound. Both are now covered by tests that drive the real binary |
| An interactive tool is left untested *because* it is interactive | The REPL went unchecked on exactly that reasoning and was completely broken. It is line-oriented, so driving it over a pipe is all a test needs; `scripts/check-repl-selfhost.sh` drives it over a pipe |
| A step in the workflow file refers to a script that no longer exists, so a job fails for a reason unrelated to the code | Gates are scripts in `scripts/`, and CI steps only invoke them. The `Game of Life` step outlived its script by one commit and failed every matrix run until it was noticed here (§2.5) |
| A cheap job that gates every other job fails, so nothing downstream ever runs | `needs:` on a first job means one failure stops the whole pipeline. Eleven accumulated clippy warnings blocked CI entirely this way (§2.5). The job in that position is now `grammar`, which needs no compiler; when it goes red, nothing else has run, so read it first. It happened again and larger, at the *step* level rather than the job level: the seed-provisioning step is the first step of every job, and it failed on all three Linux jobs for six days, so seventeen gates behind it reported nothing while the darwin jobs stayed green (§2.1, [self-hosting.md §12](self-hosting.md)) |
| A comparison is decided by something neither side computed | Build every artifact you intend to compare **to the same basename in a directory that differs**. macOS `ld` derives the Mach-O `LC_UUID` from the output path; ELF `llc` records the input's basename as an `STT_FILE` symbol. Each hazard was found the hard way, in opposite directions, and each made two byte-identical compilers differ. `check-cross-targets.sh` now asserts per target that an object does not record its path — and asserts that ELF *does* record the name, so the first half cannot quietly become vacuous on a Mach-O host |
| A red CI run is reported on every push and read by nobody | The gates being green locally is what makes this comfortable, and darwin-only agreement is exactly the failure mode: the machine the work is done on agrees with itself. Check the checks tab before citing any row in §2.1 |
| A gate that *skips* when its tool is missing is the same failure wearing a different hat | `check-tree-sitter.sh` exited 0 when the tree-sitter CLI was absent — which is every machine that has not run its `npm install` — so it reported success without checking anything. It hid two live breakages: the grammar rejected every `struct` with fields, and so most of `self_host/`, taking the corpus from a claimed 18/18 to an actual 27/70; and the highlight-query step named `game_of_life/Life.ax`, deleted in 720a0d5. Both fixed, and the gate now fails rather than skips unless `AXIOM_TREE_SITTER_OPTIONAL=1` is set |
| Removing `union`/`region` breaks unknown external code | Both stay reserved and report `AX2004` with the replacement, rather than being silently reinterpreted |

### 2.4i Two more of the same class, in the neighbouring branch

§2.4h fixed the type printer and widened the zoo to ask about applied
types. Asking the *rest* of the questions the zoo had never asked found
two more constructs `fmt` refuses, both in `data`/`struct` and both the
same shape — the formatter emitting syntax the parser does not accept,
invisible because nothing in the repository writes it:

| written | `fmt` printed | the parser wants |
|---|---|---|
| `(data C (Red) (Green) deriving (Eq Show))` | `(deriving Eq Show)` | `deriving` outside the parens |
| `(struct P (mut y : Int))` | `(y : Int) mut` | `mut` inside, before the name |

Both refused rather than wrote, which is the round-trip check doing its
job for the third time. And both are now in `tests/fmt/syntax-zoo.ax`,
so the gate asks.

The pattern is worth naming, because this is the third time it has been
recorded and the second time in one sitting: **a formatter is a second
implementation of the grammar, and the only thing that keeps the two
implementations in agreement is a corpus that uses every rule.** The
`.ax` files in this repository are written by people solving problems in
Axiom, so they use the constructs those problems need. The zoo has to be
written by someone reading the *parser*.
