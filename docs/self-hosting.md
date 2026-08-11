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

*Both now exist.* Tail calls are guaranteed in the IR, and `while` (S5)
gives an explicit loop that runs 10⁷ iterations in constant stack at
`-O0`. What remains bounded is *non*-tail recursion, measured at
60,000–80,000 frames on an 8 MiB stack — so a fold written as
`(+ (f i) (loop (+ i 1)))` still caps input size, and the two
replacements for it are an accumulator parameter or `while`.

**B3. Hash map, growable array, and interner: correct at scale;
`Map` misses the throughput criterion, and the reason is measured.**
`Vec` (growable array of `Int`), `Map` (open-addressing `Int→Int` hash
map with delete support), and `Intern` (string interner) are
implemented in `stdlib/`. The Rust compiler uses `HashMap`/`HashSet`/
`Vec` throughout (scopes, string interning, diamond-import dedup,
constructor tables).

*Correctness.* Golden tests are `tests/stdlib/070-vec.ax`,
`080-map.ax`, `090-intern.ax` — small adversarial cases chosen to break
a wrong implementation. `tests/stdlib/200-scale.ax` adds the other
half: all three driven to 10⁵ elements, asserted with totals over every
element rather than spot checks, against closed-form expected values
that exceed 2³² so a truncation cannot hide. All pass.

*Throughput*, measured by `scripts/bench-datastructures.sh --fx` at 10⁶
elements, `axiom --opt 2` against `rustc -O` with a fast
non-cryptographic hasher on the Rust side (the map a compiler would
actually pick), whole processes timed with startup subtracted:

| | Axiom | Rust | ratio |
|---|---:|---:|---:|
| `Vec` | 0.0074s | 0.0022s | 3.4× |
| `Map` | 0.0432s | 0.0240s | **1.80×** |
| `Intern` | 0.268s | 0.365s | **0.73×** |

`Map` meets the 2× criterion and `Intern` beats the Rust equivalent
outright. `Map` previously measured **14×**, and the path from there
to 1.80× is worth recording precisely, because every intermediate
hypothesis was plausible, was measured, and was wrong:

- *Not the allocator.* An earlier ablation attributed six sevenths of
  the cost to table growth and the bump allocator's refusal to reuse
  superseded tables (102 MB peak RSS), and this section used to say
  the remaining work was the memory model, not `Map`. Kernel time
  measured ~0 and page faults cost milliseconds; the RSS figure was
  real but the wall-clock attribution was not.
- *Not the per-probe header reloads.* Every accessor was two dependent
  loads through `__load64`, unhoistable past stores the optimiser must
  assume alias. Threading the array addresses through the probe loops
  as parameters was worth ~20% — real, and nowhere near the gap.
- *Not memory layout or call overhead either* — interleaving the
  arrays, byte-wide states, and peeling the first probe each moved
  nothing while the real cause stood.
- *The hash.* `mapHash` was a fixed-multiplier multiply-mod-prime over
  22-bit limbs, and for keys below 2²² two of the three limbs are
  constant, making it **affine in the key**. Sequential keys — node
  ids, token indices, the keys a compiler actually inserts — landed on
  interleaved arithmetic progressions modulo the table size, and
  linear probing over that structure degenerates: **70,813,730 probe
  steps for 10⁶ sequential inserts, 71 per key**. Replacing it with
  murmur3's fmix64 finaliser (five operations, division-free,
  bijective on the key space) took that to 1,457,580 — 1.46 per key,
  the textbook figure for a half-loaded table — and the benchmark from
  0.354s to 0.054s in one change. The pinned hash values in
  `080-map.ax` now check Axiom's signed shift/mask/wrapping-multiply
  implementation against an independent unsigned reimplementation.
- *Then the states array width.* The state tag is the word every probe
  loads and branches on; at 2²¹ slots a word-wide array is 16 MB and
  probes mostly in DRAM, byte-wide it is 2 MB and probes mostly in
  cache. Bytes took the benchmark from 0.054s to 0.043s. The rehash
  walk still read the *old* states array word-wide after the
  conversion — eight packed states at a time, losing roughly seven
  entries in eight — which `080-map.ax` and `200-scale.ax` both
  caught before it could ship, and which is why a benchmark run on
  failing tests (0.96× at that moment) is a number about nothing.

`Vec` remains at 3.4×. Its loop is three L1 header loads and two
stores per push against Rust's zero — `rustc` keeps a stack-local
`Vec`'s header entirely in registers, which an opaque one-word handle
cannot offer — and the absolute gap at compiler scale is ~5 ms per
million pushes. Worth revisiting if a profile of the self-hosted
compiler ever says so; not the next bottleneck.

The earlier growth measurements stand corrected too: with the affine
hash, a rehash re-inserted every key into the doubled table through
the same degenerate probe sequences, so "growth" was mostly the hash
bug measured a second time. With fmix64, growing from 8 slots to 2²¹
costs 0.014s over a pre-sized table — reinsertion plus first-touch
faults on fresh pages, both proportional to live data.

**B4. One flat namespace across all modules. (RESOLVED)** Qualified
access via `Mod::name` is supported. Same-named declarations from
different modules coexist without collision. Two modules can both define
`new`; ambiguous names are disambiguated with `Mod::name`. The
language-level decision is qualified names, and it is implemented in
`sema` (module tracking on info structs, `check_qualified_var` for
`EQualified` resolution) and `ir` (name mangling, `fn_mangle_map`).

### 2.2 Serious but workable

**S1. `data` values with fields are boxed; nullary constructors are
immediates.** A constructor with fields is a heap block. A *nullary*
constructor is its tag, carried as an immediate — in all-nullary types
and in mixed types alike, so `(Nil)`, `(None)` and every other
fieldless constructor allocates nothing (verified at the IR level: a
program whose `Option` path only ever takes `(None)` emits zero
allocator calls). What makes the mixed case sound is that the two
representations are distinguishable at runtime: tags are small
ordinals and every heap address is mmap-page memory at or above 4096,
so a `match` over a mixed type reads the tag through one
`icmp slt 4096` guard instead of an unconditional load — word 0 of an
immediate is a dereference of a small integer, which is a crash. Tags
are globally unique across all `data` types, so the one guarded read
serves every arm. A type with so many constructors that a nullary tag
reaches 4096 stays boxed, correct and merely unoptimised. Pinned by
`tests/stdlib/270-nullary-unboxed.ax`, the matrix of arm orders,
nested patterns over both representations, `data`/`struct` fields,
`Vec` slots, the builtin `Option`, and both bare-construction
spellings; the identity line (`two separately constructed INil are
the same immediate`) fails under the boxed representation, which is
how the test is known to discriminate.

For constructors *with* fields, memory use under the bump allocator is
still proportional to total allocations, not live data. Acceptable for
a single-shot compiler process, and worth revisiting before anything
long-running is written in Axiom.

*The collector, and why it was shaped the way it was.* **This section
describes the RETIRED Rust compiler. `--gc` no longer exists** — the
collector was not ported and the flag is refused by name; see §8.4. The
numbers and the design are kept because they are the measured case for
building one again, not because the current compiler behaves this way.

`--gc` replaced the bump allocator with a conservative, non-moving
mark-sweep collector, so peak memory tracked live data instead of total
allocation. Measured on `tests/stdlib/170-gc.ax`, which churns garbage
while holding a list alive:

| churned | bump allocator | `--gc` |
|---|---:|---:|
| 25 MB | 32 MB | 3.2 MB |
| 100 MB | 96 MB | 3.2 MB |
| 400 MB | 352 MB | 3.2 MB |

The self-hosted compiler compiling `self_host/main.ax` goes from 482 MB
to 8.7 MB, and emits byte-identical output.

*Conservative*, because Axiom has one runtime representation: every value
is a machine word, and nothing distinguishes the integer 8 from an
address. A precise collector needs a pointer map per object, which that
model cannot supply — `data` cells carry a tag but their fields are
still bare words, and everything else comes from `__alloc`, which is
untyped by contract (`Str` puts a byte pointer in word 0, `Vec` puts a
length). Guessing conservatively costs only false retention.

*Non-moving*, because conservatism forbids relocation: rewriting a word
that turned out to be an integer is silent corruption. It also preserves
pointer identity, which the standard library relies on — `vecPush`
returns the handle it was given.

Two things the design needed that were not obvious up front. **Interior
pointers must resolve**: `Str.strSlice` shares storage rather than
copying, so every token's text points into the middle of a module's
source buffer, and once the source handle dies those are the only
references it has. Accepting only block starts freed those buffers and
the self-hosted compiler emitted functions with garbage for names. Each
chunk therefore carries an object-start bitmap, and a candidate is
resolved by walking it backwards, bounded by that chunk's largest
object. **Free runs must coalesce**: without it a freed block keeps its
old size forever, so a loop whose allocations grow — building a string
by repeated concatenation, as `renderCG` does — can never reuse
anything. Coalescing plus splitting on reuse took the self-hosted
compiler from 402 MB to 8.7 MB.

The collector is emitted as LLVM text (`axiom-codegen/src/gc.rs`) rather
than written in Axiom, because it needs mutable global state and
unrestricted loops, and it is marked `optnone`: it is hand-written
machine-level code reading exact addresses through pointers conjured
from integers, and at `-O1` the optimiser rewrote it into something that
could not find its own chunk header.

It replaced an `ArenaCompact` instruction that tried to copy a loop
iteration's live values down to a saved waterline. That was removed
rather than finished — driven from a harness it misidentified a `Vec`
header as a constructor cell, wrote past the end of its chunk, had no
forwarding pointers or cycle handling, and could not see `Str` or `Vec`
at all, which is what had corrupted `scanDecls`.

`__axiom_arena_mark` and `__axiom_arena_reset` remain for the bump
allocator: save the allocator position, later restore it, reclaiming
everything since. They are sound because the *programmer* asserts
nothing allocated since the mark is still reachable; nothing checks it,
and the compiler never inserts them. Under `--gc` they are a compile
error — a tracing collector decides by reachability and has no waterline
to roll back to. `tests/stdlib/160-arena.ax` covers them.

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

**S5. `while` and mutable local bindings. (RESOLVED)** A `let` binding
marked `mut` is assignable with `set`, and `while` loops while its
condition holds:

```scheme
(let ((mut i 0) (mut acc 0))
  { (while (< i n) (set acc (+ acc i)) (set i (+ i 1))) acc })
```

Immutable stays the default, so nothing that does not use `set` changes
meaning, and `set` on a binding without `mut` is `AX3012` with a
machine-applicable fix at the *declaration*. Parameters and pattern
bindings are never mutable.

The representation needed nothing new: every `let` binding was already
an `alloca` and every read a load, so assignment is the same `store` the
initialiser emits. `while` is the new part - a branch back to a
condition block - and it is a real loop, running 10⁷ iterations in
constant stack at `-O0`. Covered by `tests/stdlib/220-while-mut.ax`,
which includes a 10⁶-iteration loop that non-tail recursion could not
survive.

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

### Phases 2-5 - the fixpoint is reached

**The Axiom compiler compiles itself, and reproduces itself exactly.**

```
stage0  the Rust compiler in this repository        - trusted
stage1  the Axiom compiler, built by stage0
stage2  the Axiom compiler, built by stage1
stage3  the Axiom compiler, built by stage2
```

`stage2` and `stage3` are byte-identical, as objects and as emitted IR.
`scripts/check-bootstrap.sh` runs the whole ladder and checks it, and
also compiles and runs a program through each stage - two compilers can
agree byte-for-byte on their own source and still both be wrong.

`scripts/check-self-host.sh` is the conformance gate: 54 cases in
`tests/selfhost/`, each compiled by stage1, assembled, linked, and
checked by exit status, plus a negative check that an unresolvable
import is refused with the module named rather than skipped. What it
covers, all working: integer arithmetic and comparisons, `let`, `if`,
`{}` blocks, multi-argument calls and recursion, `data` and `struct`
construction, `match` with field binding, short-circuit `&&`/`||`,
nullary functions, `true`/`false`, string literals, the freestanding
primitives including `__syscallN`, file I/O, `import` with
target-specific module selection, name mangling under an
entry-file/import collision, floats (literals, arithmetic, ordered
comparison, both conversions), `Fmt`'s fixed-point float rendering
through an import, `Map` inserts across a rehash, macro definition
with nested expansion, `Pre.ax`'s macros through an import, literal
patterns (bare and inside constructor patterns), nested constructor
patterns, mixed-type nullary constructors, and `Float` fields bound
out of patterns.

**Every module in the repository compiles through stage1** - all
eighteen across `stdlib/` and `self_host/`, including
`self_host/main.ax` itself, compile into LLVM that assembles.

*What the self-hosted compiler still does not do.* ~~It emits unmangled
names, so two modules that export the same name collide.~~ **(RESOLVED)**
Names now mangle exactly as stage0's do: a declaration imported from
module `M` defines `M$name`, the entry file keeps bare names - `@main`
stays `@main` - and a bare reference resolves through one flat map,
entry file first, then imports in resolution order. Pinned by
`tests/selfhost/320-mangle.ax`, whose entry file shadows `Str`'s
`strLen`; under the old scheme that emitted two `define i64 @strLen`
and `llc` rejected the module (verified against the pre-change
codegen). An unresolvable or unparsable import is now also a fatal
diagnostic naming the module (exit 3) rather than a silent skip - the
skip used to surface as `use of undefined value '@fmtInt'` out of llc,
a codegen-shaped report for an import-shaped failure.

Floats are implemented: literals lex and are decoded to their IEEE-754
bits *by the compiler's own float arithmetic* - stage1 is an Axiom
program, so `1.5` is evaluated with the same `fadd`/`fdiv` the program
being compiled will use - and float-ness is reconstructed from
signatures exactly as stage0's IR generator does it, since nothing
about a value at emission time says it is a float. The bitwise
operators emit as instructions rather than as calls to `@>>`, an
identifier LLVM rejects. Together those let `stdlib/Fmt.ax`,
`stdlib/IO.ax`, `stdlib/Map.ax` and `stdlib/Intern.ax` compile and
assemble through stage1. Pinned by `tests/selfhost/330-float.ax`,
`340-fmt-import.ax` and `350-map-import.ax`, each verified to produce
the same exit status under stage0.

Macros are implemented, which closed the last module. stage1's macro
grammar was wrong in a way that refused all of `Pre.ax` - it expected
`(macro name (params) body)`, a spelling that appears nowhere in the
language, where the real form is `(macro (name params...) template)`
with the name inside the head parens like a function's. Expansion is a
rewrite applied where a call would otherwise be emitted: a head naming
a macro with matching arity has its template instantiated and emitted
in the call's place, and emission re-enters the same dispatch, so
nested and chained expansions recurse exactly as stage0's expander
does. Substitution is deliberately unhygienic (no macro in the corpus
introduces a binder; hygiene is macro-system work, roadmap P3) and an
argument used twice shares one tree rather than two clones - the same
double evaluation textual substitution has always meant. Pinned by
`tests/selfhost/360-macro.ax` and `370-pre-import.ax`, both agreeing
with stage0.

Getting there surfaced two latent bugs outside stage1, both now fixed
and pinned. *stage0 misclassified a float expression*: `__intToFloat`
is a primitive, so no signature ever declared its return type, and
`(/ (__intToFloat a) (__intToFloat b))` - with no float literal,
parameter or field anywhere in sight - lowered to `sdiv` on the
converted values, silently computing `5 / 10 = 0` where `0.5` was
meant, in a program the type checker had accepted
(`a_binop_over_two_conversions_is_a_float_operation`). And
*`sysReadFile` truncated at 64 KiB* - one `sysReadFd` chunk, documented
as "enough for the self-host bootstrap source files", which held until
`self_host/codegen.ax` grew past it and the compiler truncated its own
source mid-token, reporting a parse error at a token that does not
exist in the file. It now reads to EOF, doubling its buffer.

*Adversarial differential review.* With every module compiling, the
two compilers were put through an adversarial review: parallel
reviewers per subsystem plus differential fuzzers writing well-typed
programs, running them through both stages, and reporting any exit
code that differed - every finding then independently re-reproduced by
a verifier told to refute it. The first round confirmed 24 findings;
all are fixed and the ones with observable behaviour are pinned as
conformance cases. The stage1 fixes: macro parity in the degenerate
corners (any-arity expansion binding a single parameter to a
begin-block of the arguments, last definition wins, last duplicate
parameter wins, zero-argument macros expanding at bare references),
`cond`, literal patterns bare and nested, recursive nested-constructor
patterns, the mixed-type nullary representation (the segfault above),
constructor-before-function resolution of a bare name with stage0's
tag numbering (the builtin `Option` occupies tags 0 and 1), import
name lists honoured with stage0's exact filter semantics, `Float`
constructor fields keeping float-ness through patterns, digit
separators, and `^` - which the lexer's fallback had been *silently
skipping*, so `(^ a b)` compiled as `(a b)`.

Two of the findings were bugs in **stage0**, which is the differential
method paying for itself in the direction nobody expected. Float-ness
of a `let` binding was keyed by name for the whole function, so an
`Int` binding shadowing a `Float` name still lowered its arithmetic as
`fmul` over the integer's bits - stage1 had it right. And the alloca
map was never restored when a `let` body ended, so
`(let ((x 1)) (+ (let ((x 2)) x) x))` read the inner `x` twice and
answered 4 - an integer scoping miscompile in the trusted compiler,
sitting under every program with a shadowed binding, found because a
fuzzer compared it against the compiler this document is about.
Both are fixed, with scoped bind/restore at `let` boundaries and match
arms, and pinned by `a_shadowing_let_binding_ends_with_its_body` and
`an_int_binding_shadowing_a_float_name_is_integer_arithmetic`.

A second round over the fixed compilers confirmed eleven more - none
from the self-host-style fuzzer, whose programs in the compiler's own
idiom found nothing, but plenty in the language's corners. stage1:
`String` and `Bool` literal patterns bound like variables (the first
literal arm swallowed every scrutinee); its own `let` bindings leaked
past their scope, the same class as stage0's alloca leak; a data
declaration's type-parameter list `(a)` was registered as a nullary
constructor, so every binder named `a` became a tag test that bound
nothing (SIGSEGV); an unknown top-level declaration - `foreign`,
`type` - silently *truncated the module* at that point with exit 0;
`-5` lexed as an identifier and emitted the SSA name `%-5`;
`sizeof`/`alignof` emitted calls to symbols nothing defines; char
literals did not lex; a bare function name in argument position
emitted an undefined local (now refused loudly: function values need
B1's closures); and a *bare* constructor name in pattern position
tag-tested where stage0 binds it as a variable - only parenthesised
`(Nil)` is a constructor test, so stage1 now distinguishes the two
spellings the way stage0's parser does. stage0's own share this round:
`Bool` literals were emitted as LLVM `i1` constants in a word-typed
world, so a `true` pattern produced `icmp eq i64 %x, true` and llc
rejected stage0's own module; and `fmt` printed the parser's
unary-minus desugaring as the infix `(0 - 5)` and stripped the parens
off a data type-parameter list. All fixed; every behavioural fix is a
conformance case, and the gates plus the fixpoint stay green.

`while`/`mut`/`set` (S5) are implemented: a `mut` binding is an
alloca, every read of it a load, `set` a store that evaluates to the
stored value, and `while` a branch back to its condition block
yielding 0 - each matching stage0's observed behaviour, including a
mutable `Float` keeping its float-ness across stores
(`tests/selfhost/500-while-mut.ax`, `510-mut-float.ax`). The alloca
machinery is also the substrate closures (B1 in stage1) will need.

Function values work for the saturated case: a bare reference to a
top-level function builds a closure record, and a call whose head is a
local or parameter goes indirect through it, all arguments at once
(`tests/selfhost/520-fn-values.ax`, `530-fn-in-ctor.ax`). Lambda
expressions work too, captures included: a lambda is lifted to a fresh
top-level function whose hidden first parameter is the closure record
- word 0 the code pointer, words 1.. the captured values - and every
indirect call passes the record itself as that first argument. A
record built from a bare top-level function therefore points at a
forwarding thunk that drops the record and calls the function with
its arguments unshifted; stage0 solves the same problem by giving
every function the hidden parameter instead, and the two conventions
agree on every observable. Capture is by value and captures the whole
enclosing scope minus what the lambda's parameters shadow, rather
than walking the body for free variables - the unused record words
are unobservable, and a free-variable walker's one missed traversal
case is a silent wrong capture. Pinned by
`tests/selfhost/580-lambda.ax` and `590-lambda-nested.ax` (a capture
crossing two lifts), both agreeing with stage0.

Partial application remains unsupported in both compilers, and stage0
now *refuses it loudly* instead of miscompiling. It used to be a
crash wearing a type-checker's approval: `(let ((f (add2 1))) (f 2))`
is well-typed under currying, compiled into a one-argument call to a
two-parameter function - the missing argument simply omitted, the
callee reading register garbage - and SIGSEGVed when the garbage was
dereferenced as a closure. A systematic probe of every application
shape found four such holes, each with a different failure face:
stored partials and stepwise application of a bare multi-parameter
function value crashed at runtime, while an under-applied constructor
and a bare fieldful-constructor reference emitted calls to symbols
that do not exist and surfaced as `llc` errors about generated code.
All four are now `check`-time diagnostics: `AX3013`
(partial-application) for functions - measured against the
*declared parameter count*, not the arrow depth, so a one-parameter
function returning a lambda still over-applies fine - and `AX3009`
(constructor-arity-mismatch), which used to fire only in patterns,
now also at expression sites. Bare references to one-parameter
functions stay allowed; they are the working function-value
representation the conformance suite exercises. A corpus scan of all
106 `.ax` files found zero partial applications, so nothing existing
changed meaning. Currying properly - runtime arity in the closure
record - remains open work if anything ever wants it.

An adversarial review of that change - three independent hunters,
every finding re-reproduced by a verifier told to refute it -
confirmed fourteen findings, and fixing them made application
*uniform* rather than merely refused. The false positives were one
root cause: the arity lookup took the first name match while imports
merge ahead of the entry file's declarations, so an entry-file
`helper` was flagged with an imported `helper`'s arity; lookups now
take the last match, the resolution the type checker itself uses.
Qualified constructor forms (`Mod::MkP`, applied or bare) had
bypassed the expression-site arity check through a `module.is_none()`
gate; both now refuse. A refused spine now types as `TError`, so the
refusal is the one diagnostic instead of being followed by a
consequent mismatch at the same site. And three generator bugs fell
to one principle - every function value absorbs exactly one argument
per call: a flat spine over a local holding a curried chain
(`(h 3 4)`) passed both arguments in one indirect call and answered
with the inner closure's address, in both compilers; an `if` or
`match` in head position lowered to a call to the undefined symbol
`@unknown`; and a lambda head was special-cased into a direct call
passing 0 for the closure, so a capturing lambda applied in place
read captures from address zero. Non-name heads now evaluate as
values and apply one argument at a time, in stage0 and stage1 alike.
Separately, `free_variables` treated a lambda body's reference to a
top-level function as a capture and stored the undefined SSA value
`%add` into the record - which broke exactly the rewrite `AX3013`'s
help text prescribes; global names now resolve globally inside the
lifted body unless an enclosing local shadows them. Pinned by
`tests/stdlib/280-function-application.ax` (the matrix of fixed
shapes), `tests/selfhost/600-curried-flat.ax` (stage1's chain), and
regression tests for the shadowed-import and qualified-constructor
diagnostics.

Both items that review left open are now closed, and the closing
required a design decision rather than a bug fix. A scout of every
bare-name resolution site found *five different winners* in one
binary - sema's flagging took the last declaration, its typing took
the first import, its signature-scope entries were
position-dependent, effect inference ignored the module even on
qualified names, and the IR's mangle map was entry-first-then-first-
import with a nullary-pass wrinkle - so a program importing two
modules that both define `f` could type-check against one and *run*
the other (probed: the checker bound the last import while the
emitted call reached the first). The rule now is **entry file first,
then the unique defining module, and otherwise `AX3014
ambiguous-name`**: a bare reference to a name that two or more
imports define, with no entry-file definition, is refused with the
qualified candidates listed. There is deliberately no
import-versus-import precedence - any choice is one the other stages
could disagree with, and no corpus program wants one (the two
load-bearing collisions, `strLen` in `320-mangle` and `label` in
`150-qualified-modules`, both involve the entry file, which wins
everywhere; the historical `readFile` collision this would have
caught was fixed by renaming). The typing loops, the float tables,
and the generator's constructor lookups are all entry-preferring
now, and the duplicate-definition table is keyed by
`(name, module)` - keyed by name alone it never recorded a second
module's definitions, so genuine duplicates there escaped `AX3006`.
Signature-only declarations are `AX3015 missing-definition`: at the
signature for the entry file, and at the *reference* for an import
that delivered a `pub` signature whose definition stayed private -
the exporting module is internally fine and an unused import of it
is harmless, which is why one site cannot do both jobs.

A second adversarial round over the landed rule confirmed seventeen
findings and their fixes tightened the definitions themselves. A
*definer* is a module with a `fn` or `foreign` - a `pub` signature
alone neither creates ambiguity nor outranks the real definer,
whichever import order merged them; a definition written above its
own signature is still a definition (the checker kept two entries for
the name and the arity lookups landed on the signature-only one);
builtins are module-less winners like the entry file, so two imports
defining a `None` constructor no longer make the builtin spelling
ambiguous; ambiguity spans both namespaces (a function in one module
and a constructor in another is as unresolvable as two functions) and
both positions (patterns refuse exactly as expressions do - an arm
would tag-test one module's constructor and bind fields with the
other's float flags); and the float tables are keyed by mangled name,
because the earlier entry-suppression fixed the entry's call sites by
breaking the import's own float arithmetic and every qualified call
into it. Sig-only names are refused in value position and behind
qualified references too, not only at calls. Deepest of all, the
round exposed a latent clobber the old resolution had been masking:
after checking a body, the checker *overwrote* the declared signature
in its function table with the inferred parameter-and-body type, so
`mkTok :: Int -> Int -> Int` returning a `Tok` struct handle became
`-> Tok` in the table - harmless while a position-dependent scope
walk answered first, and 246 instant type errors across `self_host/`
the moment the table became the single source. Inference now fills
only signature-less placeholders; a declared signature is
authoritative.

Recorded open from the same scout, and **since fixed** - see "A module
binds its own names" at the end of this document: bare references
*inside* an imported module also resolved entry-first (in
`320-mangle`, `Str.ax`'s own internal `strLen` call reached the
entry's shadowing definition, and the test passed only because both
answers landed on the same side of its comparison). They bind
module-locally now.

An earlier revision of this paragraph claimed effect inference "does
not propagate effects through calls at all". That claim was wrong,
and the correction is worth recording as a lesson about probing:
`infer_effects` has been a monotone fixpoint over every function body
since it landed - transitivity is pinned by a test, and a
`;@axiom:pure` claim over a two-call-deep syscall warns exactly as
Phase 0 says. What the probe had actually observed was the
*attribution* bug: effects were written to, and read from, the first
`FnInfo` matching the bare name, so two same-named functions pooled
their effects into one entry - a pure `Bpure::work` inherited its
`Aio::work` namesake's IO, its own entry stayed empty, and a
qualified call to the genuinely pure one drew a false `AX3010` while
the general "propagation is broken" conclusion looked confirmed. The
fixpoint and both effect lookups are now keyed by `(name, module)`
with the same resolution rules as everything else, `EQualified` stops
discarding its qualifier, and `symbols` emits the *inferred* effect
set (`#effects=io`) beside whatever the tags claim - it used to print
`#pure` on a function in the same invocation that warned the
function's body performs I/O.

Both of that paragraph's recorded-open items have since landed, and
each was redesigned once by its own adversarial review before a line
shipped. Effect polymorphism: a function's summary now carries
*effect-transparent parameter* marks beside its concrete effects - a
call through a parameter (or a `let` alias of one, or passing it on
to another function's marked position) marks the parameter, call
sites instantiate marks with the argument actually passed, and
`symbols` prints `#effect-params=f` on `apply` where it used to imply
plain purity. Claims validate against the concrete half only
("`pure` modulo callbacks"), except that a claimed effect no
declaration introduces warns regardless - nothing could supply it.
The review also surfaced two latent collector bugs the tests now pin:
`EIf` never walked its *condition* (a syscall in an `if` condition
vanished from the inferred set), and the mid-recursion `AX3011` check
had no lexical context, so a local shadowing an effectful top-level
name drew a build-failing error the fixpoint's own walk of the same
body contradicted. Reference-site attribution stays as the soundness
net; the honest residue is invocation of function values that arrive
through returns or structure loads, and higher-rank flows.

Dynamic handles: `(effect Console (log :: ...))` now registers, its
operations are callable names carrying `Custom(Console)` as their
inherent effect, and `handle` with a declared effect in its list
installs the handler for the body's dynamic extent - shallow
evidence-passing, tail-resumptive only. Evidence is a per-effect
mutable global holding a heap-allocated `{handler, previous}` record;
dispatch installs `previous` while the handler runs, so a handler
performing its own effect dispatches outward instead of looping - the
naive lowering re-entered itself forever, and the review caught that
the static attribution (a handler's effects pass its own `handle`)
had already committed to outward dispatch. An unhandled operation
traps with exit code 71 (70 belongs to the allocators' OOM path). The
evidence globals are the program's first mutable globals, which made
them the GC's first global roots - `gc.rs` had documented "no global
root set" as a fact the collector's soundness rested on, and the
`--gc` integration test churns two hundred thousand allocations under
an installed handler to pin the marking. Multi-argument operations
take curried handler chains (a flat lambda is tuple-typed and
refused); one custom effect per `handle`, single-operation effects
only, unknown effect names are `AX3016`, the rest of the v1 fence is
`AX3017`. The review's blocker was humbler than any of that: the
documented `(effect ...)` surface form did not parse - the grammar
demanded a wrapper list the docs never showed, the formatter emitted
the docs' form, and tree-sitter accepted a third shape with no `::`
at all. Parser, formatter, and grammar now agree on the documented
flat form, and the fmt zoo and tree-sitter corpus both carry effect
declarations so the three cannot drift apart silently again. Stage1
parsed neither form when this was written; it parses, checks and now
*lowers* both - see "The effect system lowers" below.

Struct field access works: `p.x` resolves the field by name in the
struct registry and loads at its word offset, chains fold left, and
the field's declared type travels - a `Float` field read feeds float
instructions (`tests/selfhost/540-field-access.ax`,
`550-field-chain.ax`). Field stores work too: `(set base.field v)`
evaluates the base once, resolves the field as a read does, stores at
its offset, and the whole form evaluates to 0 - stage0's rule, distinct
from plain `set`, which answers the stored value. A dotted chain in the
target builds the base exactly as expression-position access does, so
only the last segment is written (`tests/selfhost/560-field-store.ax`,
`570-field-store-nested.ax`).

Phase 3 has started, and its acceptance criterion is met for the
checks that exist: stage1 emits **byte-identical AXDL**. What made
that possible was not the checker but the thing underneath it -
stage1's AST was four words (`tag a b c`) and carried no position at
all, so no diagnostic it produced could name a location. Declaration
nodes now carry the span of their *name*, which is the granularity a
declaration-level diagnostic points at (`tests/selfhost/630-decl-spans.ax`
pins the byte offsets), and `self_host/diag.ax` renders AXDL as a
transliteration of stage0's `render_ai_line`.

Two checks replace the stub, both declaration-level, chosen because
they need no type inference, no scope walk, and none of the resolution
subtleties a naive reimplementation gets quietly wrong: `AX3006`
duplicate definition and `AX3015` a signature with no definition
behind it. Between them they exercise every AXDL field stage1 can
produce - primary span, related span, help - so the comparison is
meaningful rather than decorative. Their order is not incidental
either: stage0 runs its duplicate pass over every declaration before
its signature pass runs over any, so every `AX3006` precedes every
`AX3015` whatever order the source puts them in, and two passes in
that order is the whole rule.

The subtlety worth recording is one of *units*. stage0's lexer
tokenizes a `Vec<char>`, so every span it produces is a character
index; stage1's lexer walks bytes. Line numbers agree either way - a
newline is one byte and one character - but columns do not, and the
compiler's own sources are full of em-dashes (`core.ax` carries 18
non-ASCII bytes, `stdlib/Pre.ax` 15). The fix needs no UTF-8 decoding:
a byte is a character start unless it matches `0b10xxxxxx`, so
counting non-continuation bytes from the line start counts characters.
An ASCII-only corpus would never have exposed this and it would have
detonated at phase 5, when stage1 checks its own source, so
`070-nonascii-same-line.ax` puts an em-dash before the error *on the
same line*: stage0 says column 22, a byte count says 24.

`scripts/check-diagnostics.sh` is the gate, and it is three-way -
`golden == stage0 == stage1` - rather than a straight diff between the
compilers, because a two-way comparison cannot see the first risk this
document lists: a stage0 bug baked into stage1, where a wrong compiler
looks self-consistent. It also refuses two failures that look like
success: a golden with no AXDL line in it (agreement by mutual
silence, which is what a comparison against a checker that emits
nothing would always report), and any diagnostic at all on the
compiler's own source, since a false positive there does not annoy,
it stops the compiler compiling itself.

A third check has since joined them, and it is the first that looks
*inside* a function rather than at its declaration: `AX3013`, partial
application. A top-level function applied to fewer arguments than it
declares has no runtime representation - the call site omits the
missing arguments and the callee reads whatever the registers held -
so stage0 refuses it, and stage1 used to emit the broken code
silently.

Reaching inside a body needed one more span. An application's span is
its *head's*: stage0's `Expr::span()` recurses to the function side of
an `EApp`, so a report about `(f 1)` points at `f`. `mkEApp` copies
its function's span at construction, which is exactly equivalent to
that recursion and costs a word rather than a walk
(`tests/selfhost/680-expr-spans.ax`). And it needed scope: a head
shadowed by a local is skipped, because a local may hold a
one-parameter function returning a closure and only that shape
survives stepwise application - so the walk tracks `let`, `mut let`,
lambda parameters and match-arm binders, where a pattern's non-head
variables are its binders.

The bug worth recording is the one the gate caught rather than the
one it prevented. `checkSpine` ran at every `EApp` node instead of
once per spine at its root, so `(f a b c)` re-entered the same spine
one argument shorter at each level and reported three diagnostics, two
of them describing calls the source never made. Nothing in the corpus
noticed - every case there is a single short call - and the
no-false-positives sweep over `self_host/` and `stdlib/` failed
immediately with sixteen reports against real standard-library code.
A checker is not tested by the errors it finds in files written to
provoke it; it is tested by the silence it keeps on files that are
correct.

The other thing this slice found was not a diagnostic at all.
`typecheck.ax` growing pushed `check-bootstrap` and one conformance
case into SIGSEGV, in `Mem$memCopyFrom`, from a program that did
nothing wrong. `Mem`'s byte loops were self tail calls, which cost
nothing where a compiler turns them into jumps - and **stage1 emits no
tail-call optimisation at all**, so each was a real call chain one
frame deep per byte. A hundred kilobyte copy is a hundred thousand
frames. It had been under the limit until the compiler's own output
grew, which is the worst way to meet a scalability ceiling: as an
unrelated change appearing to break an unrelated test. `memCopyFrom`,
`memSetFrom` and `memCmpFrom` are `while` loops now, which need no
optimisation to be flat, and `tests/selfhost/690-large-memcopy.ax`
copies a megabyte through a stage1-built binary; restoring the
recursive spelling fails it.

**stage1 now optimises self tail calls**, which closes that gap at its
source rather than around it. A self call in tail position becomes
parameter reassignment plus a branch to a loop header - stage0's rule.
Three things made it cheap. stage1 already emitted allocas, loads and
labelled blocks for `mut` locals, so the storage machinery existed;
registering a parameter with the same `bindSym ... 1` that `mut` uses
makes every body reference load it without `emitVar` knowing anything
about tail calls; and the whole apparatus is opened only for a
function that a pre-pass finds actually tail-calls itself, so every
other function emits byte for byte the LLVM it emitted before, and
pays nothing.

Tail position is exactly stage0's set and no larger, because the
failure mode of getting it wrong is not a crash: rewriting a call that
is not in tail position silently drops the work waiting on its result
and returns a wrong answer. The set is the last expression of a `{}`
block, both arms of an `if`, and every arm body of a `match` - which
is the shape most recursive Axiom is written in, a walk over a `data`
value, and the case the optimisation is most wanted for. A `let` body
is deliberately NOT one, which is stage0's rule and worth stating
because it is surprising: `(let ((mut s 1)) { (go ...) })` recurses
for real under *both* compilers at `--opt 0`, and survives only
because `--opt 1` hands it to LLVM's own `tailcallelim`. Probed both
ways; the two compilers agree, including in when they overflow.

`tests/selfhost/700-tco.ax` checks the directions separately: two
million iterations in constant stack and a 400,000-element list walk
through `match` arms, against a *non*-tail `(* n (fact (- n 1)))` that
must still compute 10! correctly. It also pins the argument-clobber
case, `(pair (- n 1) n)`, whose second argument must read the original
`n` - every argument is evaluated into its own register before any
parameter slot is written - and a local shadowing the enclosing
function's own name, which must stay a call to the local rather than
becoming a jump to the function, an infinite loop where 10 is the
answer. The rewrite is decided after the macro and local-value checks
for exactly that reason.

Three defects an adversarial scout found in the first cut are worth
recording, because two of them made the feature a no-op where it
mattered. Detection compared the body's bare call head against the
declaration's name - which `mangleDecl` has already rewritten in place
to `Mod$name` - so TCO never fired for a single function in an
imported module, which is all of `self_host/` and `stdlib/`, including
the `Mem` loops that motivated the work. It passed its own test only
because the test was an entry file. Binding parameters as `mut`
storage also made `(set p v)` silently legal inside self-recursive
functions, where stage0 reports AX3012 and pre-TCO stage1 refused it -
a divergence that depended on an unrelated property of the function it
appeared in. Parameters bind at a third kind now: loadable like a
`mut` slot, refused by `set` like a parameter.

The `Mem` loops stay loops. The recursive spelling would now compile
to the same thing, but a standard library whose correctness depends on
an optimisation is a standard library that breaks catastrophically if
the optimisation ever regresses, and the `while` form costs nothing to
keep.

`AX3001`, undefined variable, is the fourth and the most common
diagnostic there is. It rides on the scope walk `AX3013` needed, and
its difficulty was never the walk - it was that every category of name
a program may legally reference has to be recognised, because a
category missed is a valid program stage1 rejects. Top-level
functions, foreign bindings, data constructors, struct names, macros
and signatures come from the resolved declaration list; primitives are
covered by the `__` prefix rather than a list, since every one of them
has it; operators, `true`/`false` and `cast`/`sizeof`/`alignof` are
enumerated. The sweep is what settles it, and it did: the first cut reported `Int`
undefined in three files, because `(cast Int x)` puts a TYPE where an
argument goes and a type name is not a variable reference.

Then an adversarial scout found the one the sweep could not see.
stage1 rejected **every program that uses the effect system** -
`handle`, each effect operation, each effect name, and the built-in
effect names in a handle list - on programs stage0 accepts in silence.
It was invisible because the sweep covered `self_host/` and `stdlib/`,
and neither uses effects. `effect` declarations parse for their names
now, exactly as `foreign` does, and `handle` and the six built-in
effect names are recognised; stage1 still lowers none of it, but a
keyword is not an undefined variable.

The sweep covers `tests/stdlib/` too now, which is the only place in
the repository where effects and the built-in `Option` appear. Adding
it exposed a second hole, this one in the gate itself: the sweep runs
from a scratch directory and names its inputs by repo-relative path,
so `tests/` was not reachable, stage1 read nothing, reported nothing,
and the sweep called it clean - the exact vacuous success the rest of
the script exists to refuse. Ablating `handle` out of the known set
now fails three cases; before the symlink it failed none.

The suggestion is reproduced exactly, which is the part that has to be
byte-identical and has no room to be approximately right: Levenshtein
distance, the `(min(len)/2)` threshold clamped into [1,2], candidates
equal to the name or beginning `__` skipped, and the first
*strictly*-smaller distance winning - so the order candidates are
visited in decides every tie. stage0 visits everything in scope, then
every function, then every constructor, in three separate passes; a
single interleaved walk gets the same answer except when it does not.
Two facts had to be measured rather than read. `Option` is built in,
so `None` and `Some` are candidates in every program without being
declared in any of them. And `Some` is offered before `None` - a
constructor is registered as a function too, and functions come first
- which is the entire difference between printing `Some` and printing
`None` for a name that sits at distance 2 from both.

Two further divergences the same scout listed are closed. `(set name
v)` with an unknown target is `AX3001` now - stage0 reports it there,
with candidates drawn from scope alone rather than from the whole
program, and the span is the target's, so `TAG_E_SET` carries the
name's span rather than the form's. And **`pub` is honoured**:
declarations record their visibility, and import resolution splices
only the public declarations of an imported module, which is what
stage0 does. stage1 had spliced all of them, so a reference to a
private imported name compiled here and was undefined there. Every
declaration in `self_host/` and `stdlib/` is `pub`, so the filter is a
no-op for the compiler's own build - checked before the change, and
the bootstrap fixpoint held after it.

`AX3012` is the fifth diagnostic, and the first whose AXDL uses every
field the renderer has: a primary at the assignment's target, a
secondary at the binding's *binder*, a machine-applicable fix
(`~>"mut c"`) at the same binder, and a second, plain help - which is
one more help than `Diag` carried, so the record grew a slot. Binder
spans had to exist first: a `let` pair now records its name token's
span and the folded `TAG_E_LET`/`TAG_E_LETM` node carries it, a match
binder's span was already on its pattern node, and a *parameter*
target stays silent (the parser records no parameter spans yet) with
emission's prose refusal still behind it - under-reported, never
mis-pointed. A top-level target anchors its secondary at the first
entry-file declaration of the name, which is the signature when one
exists, stage0's anchor; an imported target stays silent, because its
binder's span indexes a different file's text and every span on one
AXDL line renders against one source.

The probe that mattered was for something else. `(set zzz (+ qqq
1))` reports `qqq` before `zzz` under stage0 - the VALUE is checked
before the target resolves - and stage1 had them the other way round:
two correct diagnostics in an order that fails a byte-identical gate.
Probed, fixed, pinned by `200-set-value-before-target`, and ablating
the order fails it.

`AX3003` (undefined constructor) and `AX3009` (wrong field count),
both in match patterns, are the sixth and seventh, and cost one probe
and no surprises: patterns already parse as expressions, so a fieldful
pattern's head carries its span, and `TAG_P_CON0` - the parenthesised
nullary form - gained one. `AX3003`'s suggestion draws from
constructors alone ("a similarly named constructor is visible"), with
the builtin `Option`'s in front as everywhere. One shape stays
unchecked and is worth naming: a NESTED nullary constructor pattern
loses its parens to expression parsing, so `(Nil)` inside
`(Cons h (Nil))` is indistinguishable from a binder by the time the
checker sees it - under-reported, never mis-reported, and the same
erasure stage1's own emitter documents.

Still recorded open, all in the under-reporting direction: stage0
follows `AX3012` on a top-level target with an `AX3004` cascade
(assigning through the binding's type) that stage1 cannot produce, so
that shape stays out of the corpus; `set` on a *parameter* is prose at
emission, as above; stage0 type-checks the bodies of imported modules and renders each diagnostic against its own
filename, while stage1 checks only the entry file against one; the 18
builtin operators are suggestion candidates in stage0 and not in
stage1; and stage0's suggestion threshold counts BYTES while its
distance counts CHARACTERS, which stage1 cannot yet diverge on because
its lexer accepts no non-ASCII identifier to begin with. `&&&` also
lexes as one identifier in stage1 and as `&` plus `&&` in stage0,
which is a lexer gap rather than a checker one.

**Type checking proper has landed**, and with it the eighth through
eleventh diagnostics - the four that need a type to exist before they
can be asked: `AX3004` type-mismatch, `AX3005` non-exhaustive-match,
`AX3007` field-not-found and `AX3008` struct-field-count. What
unblocked them was `parseSigDecl` keeping a signature's type
*structure* rather than its name and a float-flag bitmask; with the
structure discarded, nothing downstream could compare a type to
anything.

The model reproduced is stage0's, and its most important property is
that there is no model to speak of: **no unification and no
substitution exist anywhere**. `compatible_with` is the entire notion
of agreement, and stage1's `tyCompat` is a transliteration of it - a
type VARIABLE on either side at any depth matches anything, so
`Tree a` against `Tree Int` passes without any substitution existing
to make it pass; the poison type matches everything, so one root cause
never cascades; and `String` and `Int` are mutually compatible by
fiat, which is the uniform-representation rule (§2.2 S1) made visible
in one place instead of worked around at every boundary. Writing a
real unifier here would have been easier and wrong: the acceptance
criterion is byte-identical AXDL, and a checker that knows more than
stage0 reports diagnostics stage0 does not.

Two things had to be copied rather than designed. Type *rendering* is
byte-visible, because `_tN` names appear inside AX3004 messages, so
the fresh-variable counter's increment sites are stage0's rather than
a plausible equivalent - `240-type-render.ax` pins this by rendering
`_t3` and `_t4`, numbers that are correct only if every earlier
declaration in the file consumed exactly as many fresh variables in
stage1 as in stage0. And a declared *signature is authoritative*: a
`fn` without one gets a placeholder type variable and every parameter
typed `Int` - Int, not a wildcard (probed) - while parameters beyond a
signature's arrows bind at fresh wildcards.

Where stage1 cannot know a type it uses a *silent* wildcard: a
nameless type variable that matches anything, is never rendered, and
is never the subject of a diagnostic. Effect operations, macro heads,
and types the grammar cannot represent all get one, so the residue is
under-reporting rather than divergence - a handler whose type
disagrees with its effect's declared operation draws `AX3004` from
stage0 and silence from stage1 (probed). Under-report, never
mis-report, is the rule the whole file is written to.

Six corpus cases pin the result: `230-type-mismatch` (the common
shapes - a non-`Bool` `if` condition, an argument against a signature,
a non-function where an arrow is expected), `240-type-render` (an
applied constructor `Box Int` against `Box Bool`, plus the fresh
counter above), `250-non-exhaustive-match`, `260-field-not-found`,
`270-struct-field-count` in both directions, and `280-check-order`,
which puts three diagnostics in one expression to pin the order they
come out in: the field error, its own `I64` cascade, then
exhaustiveness last. A standing bank of 156 differential probes over
the language's corners - generics, recursive types, imports, floats,
chars, `while`/`set`, nested matches, cascade suppression, effects,
mutual recursion - diverges on six, and all six are named gaps rather
than surprises: three are the standing parse-diagnostic gap, since
stage1 emits no `AX2001` at all and refuses with an exit status
instead; two are the silent-wildcard handler type; and one is
`AX3010`, whose AXTAG claims do not survive stage1's lexer.

The bug worth recording is the one this found in the *test suite*
rather than in either compiler. `tests/selfhost/150-struct.ax` passed
a struct handle to `__load64`, and every primitive is declared
`Int -> ... -> Int` (`axiom_sema::PRIMITIVES` - the primitives are
where the type system stops), so stage0 has always rejected that file:
`axiom check` reports two `AX3004`s on it. It sat in the conformance
corpus regardless, because the only compiler that ever read it was
stage1, which had no type checker and compiled it in silence. The
first thing type checking did was refuse it, which looked exactly like
a false positive and was its opposite - two compilers agreeing about a
fixture that was wrong. It reads its words through `(cast Int p)` now,
the documented reinterpretation, which is what the case meant all
along.

That it surfaced in `check-self-host.sh` rather than in the
diagnostics gate is the second half of the finding. The
no-false-positives sweep ran over `self_host/`, `stdlib/` and
`tests/stdlib/`; `tests/selfhost/` - the largest body of programs
written specifically to be compiled by stage1 - was not in the list.
The sweep therefore read 53 files and reported clean while the 71 in
`tests/selfhost/`, more than it covered in total, went unread, and the
failure arrived instead as an unrelated-looking conformance
regression: a type checker landing broke a struct test. The sweep
covers it now - 124 files rather than 53 - and ablating the fixture
back to its `__load64 p` spelling fails the gate, which is how the
extension is known to discriminate. The sweep also counts what it
read and refuses a count under 100, because the way a tree left the
sweep in the first place was silently: a glob that stops matching
removes its files while the section still reports the silence it was
looking for. A checker's silence has to be swept over every tree of
correct programs, not most of them, and the sweep has to say how many
it swept.

`AX3002` undefined-type is the twelfth diagnostic, and finding it
meant asking a different question than "what should stage1 check
next". A survey of the six `AX30xx` codes stage1 did not emit showed
`AX3002` fires from exactly one place in stage0 — an `EStructCon`
whose name resolves to no struct — which is `(struct Name field...)`
in *expression* position, the construction form distinct from the
application spelling `(Name field...)`. stage1's parser had no such
form, so it arrived as an application of a bare name and drew **two
false `AX3001`s on a valid program**: one for `struct`, one for the
type name sitting where an argument goes. That is the failure the
whole checker is written to avoid, and the four-tree sweep could not
see it, because no file in any of those trees uses the form.

Two neighbours were wrong the same way. stage0's expression parser has
sixteen keyword-headed forms; the three stage1 did not know were
`struct`, `consume` and `alloc`, and each drew a false `AX3001` on its
keyword. All three parse now. `consume` collapses at parse time to its
operand, which is exactly faithful — stage0's checker, IR generator
and `Expr::span()` all see through `EConsume` to the operand. `alloc`
types `*mut Type` and evaluates to **zero**: stage0's IR generator has
no `EAlloc` case at all, so the form reaches the generator's catch-all
constant, verified by running a stage0-built `(cast Int (alloc Int
4))` and getting 0. Reproducing that zero rather than allocating is
the point — `730-struct-con-expr.ax` adds an `alloc` term precisely so
the case fails if stage1 ever improves on stage0 here.

The trap this slice had to avoid is the one the checker creates: a
form the type checker accepts and the emitter cannot build. Teaching
`checkExprH` about the construction node without teaching `emitExpr`
made a well-typed program **segfault** through stage1 while stage0 ran
it to 42. Both spellings share one emitter now, through the same
`emitConstructor` that builds the application form's block, because
stage0 lowers both to a heap block of `fields * 8` bytes with argument
*i* at word *i*; and both share one checker body, so the AX3008 and
AX3004 message text cannot drift between the two syntaxes.

Adding the first test files that use the form then found a bug in
**stage0's formatter**, which is the third time this document records
the differential method paying out in that direction. `EStructCon`
printed as a bare `Name field...` — no keyword, no parens — because
nothing in the corpus had ever asked `fmt` to render one. The output
either failed to parse (`expected ), found 40`) or re-parsed as an
application and dropped its arguments on the second pass, so
`check-fmt`'s idempotency check reported a formatter that was not
idempotent. Fixed, and the fmt zoo carries all three forms now, so the
next silent one has to be a fourth. The lesson is the one §4's effect
work already recorded: documented-but-unexercised syntax is untested
syntax, and the exercise has to come from a file in the corpus.

`handle` is the fourth keyword form, and the thirteenth and
fourteenth diagnostics ride on parsing it: `AX3016` unknown-effect
and `AX3017` effect-handler-unsupported. The same survey found it the
same way. `(handle body (Console) h)` parsed as an application, so a
handle list naming an undeclared effect drew `AX3001 undefined
variable \`Nope\`` — complete with a suggestion of `None` — where
stage0 says `AX3016 unknown effect`. That is a **mis-report**, which
is worse than the silence this document keeps apologising for: a
wrong code, a wrong message, and a fix-it hint pointing somewhere
unrelated.

The same misparse had a second cost at the other end of the pipeline.
`(handle body (Console IO Alloc) h)` emitted
`call i64 @Console(i64 %IO, i64 %Alloc)` — a call to a symbol nothing
defines, whose arguments are not values either — so an effect program
compiled to exit 0 and then died inside `llc`, reporting generated
code rather than an unsupported feature. stage1 could not lower the
effect system at that point, so it refused with exit 3 and named the
effects it could not compile - an unsupported feature should say so.
It lowers them now; the refusal is gone.

Three rules here had to be read out of stage0 rather than guessed.
The effect list is **optional** — stage0 only reads one when the next
token opens a paren. The checking order is body, then handler, then
the effect list, so a mistake inside either expression is reported
before `AX3016` on a misspelled effect beside it (pinned: a type
error in the body and an undefined variable in the handler both
precede). And the multi-effect `AX3017` anchors at the *body's* span,
because `Expr::span()` of an `EHandle` recurses into its first field
exactly as it does for an application's head. Only `Custom` effects
are subject to either check: stage0 lexes `IO`/`Pure`/`Mut`/`Div` as
keyword tokens and special-cases `Alloc`/`alloc` and `Err` out of the
identifier path, so none of the six builtins can ever reach the
lookup — `300-unknown-effect.ax` interleaves `IO` and `Alloc` with
the unknown names to pin that they are skipped rather than refused.

**Effect inference is the fifteenth diagnostic's dependency, and it
now runs.** `AX3011` needs to know what a handle's body performs, and
that is a monotone fixpoint over the call graph: one pass per
function, each round propagating at least one edge, bounded by the
function count so termination never depends on the walk staying
monotone. What introduces an effect is a short list and nothing else
does — calling a `foreign` or a `__syscallN` is IO, calling anything
else contributes that callee's inferred set, an effect operation
carries `Custom(E)` inherently (stage0 attaches it at registration so
the collector needs no case for operations at all), `(alloc T)` is
Alloc, `(set base.field v)` is Mut, and a `handle` naming a resolved
custom effect is Alloc because it heap-allocates its evidence record.

What stage1 deliberately does **not** model is effect *polymorphism*:
stage0 marks a parameter effect-transparent when it is called and
instantiates the mark with each call site's argument. Omitting it
makes stage1's sets a strict subset of stage0's, so everything
reading them under-reports rather than inventing a diagnostic — the
direction this file is required to fail in. A call through a local or
a parameter therefore contributes nothing.

Three defects in the first cut are worth recording, because two of
them made the feature a no-op and both hid behind a passing corpus.

The collector seeds `bound` with the names lexically in scope, so a
local shadowing an effectful top-level name cannot re-resolve
globally. Seeding it from scope position **0** rather than from
`frameBase` swept in every module-level entry the walk had pushed so
far — every signature and every foreign — so *every top-level
function looked lexically bound*, every call contributed nothing, and
the entire fixpoint's output was discarded at the one place that
reads it. Direct cases still passed: a syscall or an operation
written straight into the handle body has no call to lose. It took
one indirection to see it, which is why the corpus case runs its
effect through a two-function chain.

The other two were spans, and both suppressed rather than misplaced.
`TAG_E_ALLOC` carried none, so a handle whose body is a bare
`(alloc T)` reported nothing; it takes the `alloc` keyword's span
now, which is stage0's. And `spanOf` had no `TAG_E_HANDLE` arm, so a
handle nested directly inside another reported nothing — stage0's
`Expr::span()` takes an `EHandle`'s first field exactly as it takes
an `EApp`'s function side, so nested handles all anchor at the
innermost body. `320-unhandled-effect.ax` carries all three shapes:
a custom effect through a call chain, a built-in `IO` through a
`__syscallN`, and the `Alloc` a nested dynamic handle introduces.

`AX3010` is the sixteenth, the only diagnostic stage1 emits that is a
**warning** rather than an error, and the only one whose subject is a
comment. AXTAG claims live in `;@axiom:key(value)` comments that
stage1's lexer discarded, so it needed a way in. Emitting a token for
them, as stage0 does, would put a stray token in a stream every parse
path reads; instead a second pass over the source produces
`(offset, content)` pairs, and the parser partitions them by
declaration position. That is the same attachment — stage0 consumes
the contiguous run of AXTAG tokens sitting at each declaration
boundary, and an AXTAG anywhere else is a parse error under stage0
(probed: `expected expression, found ;@axiom:pure`), so no
well-formed program can tell the two rules apart. The scanner has to
skip exactly what the lexer skips, or a `;@axiom:` inside a string
literal becomes a tag.

Two things are copied rather than derived. Effects render **sorted by
display name**, because stage0 collects into a `HashSet` and sorts by
`format!("{}")` before joining with `", "` — insertion order would be
a different string, and the set is rendered *into* the message. And
`effect(console)` matches a declared `Console` case-insensitively and
canonicalises to the **declared** spelling, so the message reads
`missing Console` for a claim written in lowercase.

**Effect polymorphism now closes that gap**, and with it the last
thing keeping stage1's inferred sets a strict subset of stage0's. A
function's summary carries *effect-transparent parameter* marks
beside its concrete effects: calling a parameter marks it, a `let`
whose initialiser is a bare parameter reference is an alias of it and
marks the same index, and a call site instantiates a callee's marks
with whatever it passes there. Marks are gated on `param_callables` -
a parameter declared `Int` cannot hold a callable, and marking one
would claim a transparency the signature forbids.

Marks never add a concrete effect; they only decide *suppression*,
which is why they matter here and not to `AX3011`. stage0 suppresses
a claimed-but-absent effect when a callback could still supply it -
the function has transparent parameters and the effect names
something that exists - and reports it otherwise, because an effect
no declaration introduces can never arrive that way. stage1 now
computes both halves and applies the same rule, so the earlier
completeness gate is gone: measured before the change, three shapes
diverged (a `pure` claim on a higher-order function that also
syscalls, a claim naming no declared effect, and a bare operation
passed as a value), all under-reports, all now byte-identical.

The parameters had to leave the shadow list to make this work.
stage0 keeps them separately so `param_index` can still find one, and
a parameter masked as a shadow of itself is invisible to the very
marks being computed - the same reason its handle-site seed excludes
them.

That last shape was a third `AX3017` stage1 had not implemented at
all: an effect operation used as a **bare value**. It is dispatch,
not data, so there is no closure to hand around; stage0 refuses and
returns poison. stage1 already returned the poison - the comment at
that site recorded the message as unrenderable - and now renders it,
`(lambda (x) (ask x))` suggestion included.

`330-axtag-mismatch.ax` pins a `pure` claim contradicted by two
effects (sorted), the same contradiction reached through a call, a
lowercase custom claim naming no performed effect, an honest claim
that stays silent, a higher-order function whose transparent
parameter suppresses its claim - pinned by its *absence* from the
golden - and two more that transparency does not excuse: a
higher-order function that syscalls anyway, and one claiming an
effect no declaration introduces. `340-effect-op-value.ax` pins the
bare-operation refusal. The swept trees carry 65 real AXTAG lines — 60
`effect`, two `pure` — and stage1 agrees with stage0 in silence on
every one.

The `AX3004` checking a handler against its operation's declared
arrow is still unreported: it needs the operation type the `effect`
parser discards. It omits a line; it does not reorder or invent one.

`AX3013` remains under-reported in one direction recorded in
`typecheck.ax`: stage0 also measures builtins and foreign bindings
through their arrow depth. Duplicates *inside an imported module* also
go unreported, because stage1's merged declaration list does not
record which module each declaration came from; checking the entry
file alone is the sound subset, never inventing a diagnostic stage0
would not produce.

`AX3014` ambiguous-name is the seventeenth, and it needed a change to
the AST rather than a new rule: the merged declaration list recorded
*what* was declared but not *which module* declared it, and that is
the one question this diagnostic asks. Declaration nodes carry a
`module` word now, stamped by `resolveDecls` - the only point in the
pipeline that knows it - before mangling rewrites the name. A
DEFINER is a `fn`, a `foreign` or an effect operation, plus a data
constructor, because candidates are the union across both namespaces:
a function in one module and a constructor of the same name in
another are exactly as unresolvable as two functions. A signature
alone neither creates ambiguity nor outranks a definer, and a
module-less definition wins outright - which covers builtins as well
as the entry file, or two imports defining a `None` would make the
builtin spelling ambiguous.

Testing it exposed a gap underneath it. stage1's module search read
`self_host/` and `stdlib/` relative to the working directory and
nothing else, so **a module sitting next to the program that imports
it could not be found at all** - `(import MA)` beside `main.ax` was
"cannot read module: MA" where stage0 resolves it. The bootstrap
never noticed, because it runs from the repo root with its entry in
`self_host/`, which the hardcoded path already covered; no
conformance case imports a sibling either. The entry file's directory
is searched first now, which is stage0's order, with the old paths
kept as a fallback.

That gap also shaped the gate. A name is only ambiguous when two
IMPORTED modules define it, which one file cannot express, so
`check-diagnostics.sh` now copies helper modules from
`tests/diagnostics/mods/` alongside each case. They live in a
subdirectory so the per-case glob cannot mistake one for a case
needing a golden, and flat in the work directory because a module
name is its filename stem.

That is every `AX30xx` code accounted for: stage1 emits **all
seventeen**, byte-identically.

**Imported modules are checked too, each against its own filename.**
stage0 type-checks the merged declaration list, so a diagnostic can
belong to any file that contributed to the program, and every span on
an AXDL line renders against one source. stage1 therefore carries a
UNIT TABLE - one entry per source file read, with its path, its text
and its module name - and every diagnostic records which unit its
spans index, stamped at a single choke point rather than at the
thirty construction sites, so a new check cannot forget to. The order
needs no sorting: `resolveDecls` accumulates depth-first, dependencies
before dependents and the entry file last, which is the order stage0
reports in (probed with two bad modules and a bad entry file).

Two things went wrong, and both are the same shape - an index that
moved. The `TC` record gained fields, so `units` sat at 13 and
`curUnit` at 14 where the new code assumed 12 and 13, and writing
`curUnit` through the wrong slot corrupted the record. And a blanket
rewrite of every `(vecPush (tcOut tc) ...)` into the new stamping
helper also rewrote the `vecPush` *inside that helper*, turning it
into an unbounded self-call. Both presented identically: a segfault
with no output, which read as "the new check finds nothing".

The measured cost was elsewhere. `AX3014`'s lookup scanned the whole
declaration list at every variable reference, which was affordable
while only the entry file was walked and quadratic the moment every
module was: stage1 stopped terminating on any stdlib-sized input. The
table is built once at collection now, as stage0's is.

What this buys is the strongest statement the sweep has made yet: the
125-file silence sweep now type-checks each file's imports
transitively, so stage1 checking `tests/stdlib/080-map.ax` also
checks `Map`, `Vec`, `Str`, `Mem` and `Pre`, and agrees with stage0
in silence on all of them.

*Diagnostic grouping needs nothing.* `axiom-errors` has a `group` key
and `dedup` drops every diagnostic after the first in a group, and
the CLI calls `dedup` - but **no producer anywhere sets a group**
(`grep with_group` over `axiom-sema`, `axiom-cli`, `axiom-parser`,
`axiom-ir` is empty). It is machinery for a behaviour that does not
occur, the same class `AX3002` was before its one emission site
turned up. Reproducing it in stage1 would be reproducing nothing.

Phase 3's exit criterion is met: identical AXDL for every case in the
diagnostic corpus, cascade suppression included, with grouping a
no-op on both sides.

### Sweeping every expression form, rather than the next one

The `struct`/`consume`/`alloc` slice above found three missing forms by
following one diagnostic to its emission site. That works, and it finds
them one at a time. Running *every* expression form the Rust parser
accepts through both compilers and comparing the answers is a different
question, it takes one script, and it found two more (2026-08-07):

| form | stage0 | stage1 |
|---|---|---|
| `(- x)` | compiles | **`AX3013` partial application, on a valid program** |
| `(:: e T)` | compiles | **`parse failed`, exit 2, no span** |

Both are the shape this document keeps recording, and each is a
different half of it.

`(- x)` is negation. stage0 desugars it in the parser to `0 - x`;
stage1 did the rewrite in `emitCall`, at the far end of the pipeline.
So the type checker met a two-parameter builtin supplied with one
argument and refused the program before the emitter ever saw it — the
emitter's case was correct and **dead**, and nothing that would have
needed it could get there. It is a parser rewrite now, and the
emitter's copy is deleted rather than left as a comment about a case
that cannot occur.

`(:: e T)` is a type ascription in *expression* position — the same
token as the top-level `(:: name T)` declaration and a different form.
Only the declaration was parsed, so an ascribed expression reached
`parseAppForm`, which asked for an expression, found `::`, and answered
a bare `parse failed` with no span attached. stage1 lowers it onto its
existing `cast` spine rather than growing a node, because in stage0 the
two forms *are* the same function: `check_expr` checks the inner
expression and answers the written type for both, and the IR generator
is transparent for both. No new checker case and no new emitter case is
the point — the pairing this compiler has already been bitten by.

**And the ascription was worse in the other compiler.** stage0's parser
and type checker both knew the form; its IR generator had no arm for it
at all, so it fell through to the catch-all and `(:: 42 Int)` evaluated
to **0** — on a program `axiom check` had just called well typed. That
is exactly the `cond` failure from the roadmap's §2.4f, in a form
nobody had used: implemented in every stage but the one that makes it
run. Measured before the fix, `tests/selfhost/870-ascription-and-negation.ax`
answers **248** through stage0 (its `50` term contributing zero, so the
sum comes out −8) and `parse failed` through stage1. Both answer 42 now.

One decision inside that fix is worth stating, because the obvious
version of it would have been wrong. stage0's new arm *drops* the tail
context, exactly as the neighbouring `EGrouped` does. Passing it
through works — measured, it turns a million-deep ascribed self-call
from a stack overflow into an answer — and it would have made stage0
the only compiler that loops, since stage1 lowers the ascription onto
its `cast` spine and its tail-call analysis does not look through one.
Both compilers overflow at 10⁶ and both answer 42 at 10³. Making a
transparent wrapper transparent to tail calls as well is a change to
make in both at once, or not at all.

### What scouting phase 4 found first

Phase 4 asks for byte-identical `.ll`. Re-measured on the current
corpus (2026-08-07): **71 pairs are comparable and none is
byte-identical**, unchanged from the 0-of-62 the first scout found.
The dominant residual is the storage model: stage0 spills parameters,
`let` bindings and pattern binders to `alloca` and joins with
branches, where stage1 emits registers and `phi`.

The design decision this was waiting on - raw output or post-`mem2reg`
- is now **measured rather than open, and the answer is that
normalising does not help.** On `010-arith.ax`, the simplest program
in the corpus, the raw diff is 46 lines and running `opt
-passes=mem2reg` over both sides takes it to *50* (mem2reg annotates
blocks with `; preds`). What survives on that program is three things,
and none is a formatting artifact:

| | stage0 | stage1 |
|---|---|---|
| calling convention | every function takes a hidden `%_closure` | only lifted lambdas do; bare references get a forwarding thunk |
| block structure | `_block_0: br label %_block_1` | one unnamed entry block |
| register naming | `%_t0` | `%t0` |

The bodies are already identical - `mul`, `sub`, `add`, same order,
same operands. So the criterion as written does not ask stage1 to
converge on lowering; it asks stage1 to **abandon three of its own
design decisions and adopt stage0's**, on the simplest program that
exists. Two of the three this document already records as deliberate
and sound: the thunk convention "agrees on every observable" with
stage0's universal hidden parameter, and stage1's register/phi form is
what a backend not built around allocas emits.

That reframes the phase. Byte-identical `.ll` was chosen as "a
stricter and much easier-to-debug criterion than *produces a working
program*", at a time when no other differential machinery existed.
There is now rather a lot of it - behavioural agreement on
`tests/stdlib/` (33 of 33, exit status and stdout),
`tests/selfhost/` end to end (90 cases), byte-identical AXDL gated
three-way against goldens with a 142-file silence sweep, and a
bootstrap fixpoint that already checks byte-identity where it carries
meaning: `stage2 == stage3`, the compiler reproducing *itself*.
Byte-identity between stage0 and stage1 is a different claim from any
of those. It is not a correctness property; it says the two backends
make the same lowering choices, and the compiler whose choices would
have to win is the one being retired.

**The decision is taken: phase 4's exit criterion is no longer
byte-identical `.ll`.** It is behavioural equivalence between the two
compilers over both corpora, at both optimisation levels, through an
identical toolchain, plus the fixpoint and the four-target assembly
check. §4's phase table states it.

Three things decided it, and the third is the one that settles it.

*The criterion asks the wrong compiler to move.* On the simplest
program in the corpus the bodies already match instruction for
instruction; what differs is stage1's calling convention, block
structure and register naming, and normalising cannot remove any of
them. Byte-identity would mean stage1 adopting stage0's hidden closure
parameter on every function, its allocas for every binding, and its
redundant entry block - the design choices of the implementation being
retired.

*The property it was a proxy for is now measured directly.* It was
chosen when no other differential machinery existed. There is now
behavioural agreement over 106 cases at two optimisation levels,
byte-identical AXDL gated three-way against goldens with a 142-file
silence sweep, 90 conformance cases end to end, and a fixpoint that
checks byte-identity where it carries meaning: `stage2 == stage3`.

*And stage1's convention is measurably better, not merely different.*
Widening the differential gate turned up `320-effect-gc-roots`, which
recurses 200,000 frames deep through a `let` body - not tail position
in either compiler. Through a raw `llc` pipeline **stage0's own output
overflows the stack at -O0 and at -O2, and stage1's does not**, at
every level, because stage0's frames carry a hidden parameter and
spill their bindings while stage1's do not. Converging stage1 onto
stage0's IR would have imported that. A criterion that would make the
surviving compiler worse at the thing the language is documented as
being bad at is the wrong criterion.

That case is skipped by the raw-pipeline comparison and named in the
gate, because whether 200,000 frames fit is a question about frame
size rather than about either compiler's semantics; `axiom build` runs
`opt` and both are fine, which is what users get.

The gate that carries the new criterion is
`scripts/check-stdlib-selfhost.sh`, and widening it exposed one more
thing worth recording: **it was not in CI.** It exists because nothing
ran `tests/stdlib/` through stage1 and five miscompiles were hiding in
that gap - and then it ran only when somebody typed its name, which is
the same gap one level up, and precisely the risk `v1-roadmap.md`
already lists ("a tool with no CI gate is silently broken, as `fmt`
was"). It runs in CI now, over both corpora rather than one, with a
counted floor so that a tree quietly leaving the sweep fails instead
of reporting the silence it was looking for.

But byte-identity is downstream of correctness, and looking for it
turned up something worse. **Nothing ran `tests/stdlib/` through
stage1.** `check-self-host.sh` runs `tests/selfhost/` end to end;
`run-stdlib-tests.sh` runs `tests/stdlib/` through stage0 only; and
the diagnostics sweep compiles `tests/stdlib/` with stage1 but reads
only its diagnostics and explicitly exempts a non-zero exit there. So
a stage1 miscompile of a standard-library test was invisible to every
gate, and five of them were:

| case | stage1's behaviour |
|---|---|
| `120-pattern-representation` | output differs |
| `140-function-values` | prints closure *addresses* where stage0 prints values - over-application flattened into one direct call |
| `160-arena` | `llc` rejected the module; now compiles, but `b - a` is a whole 1 MiB chunk instead of 64 |
| `270-nullary-unboxed` | `store i64 %x` with `%x` undefined - a pattern binder never bound |
| `280-function-application` | prints `0` where stage0 prints values - a non-name application head lowers to the constant 0 |

`scripts/check-stdlib-selfhost.sh` is the gate that was missing: it
compiles each case with both compilers, runs both, and compares exit
status and stdout. It carries the five as an explicit known-wrong
list with a diagnosis each, and **a listed case that starts agreeing
fails the gate** - a known-failure list nothing can leave is a list
that rots into a lie.

**Four of the five are fixed**, each root-caused to a single named
place, each with a minimal reproducer promoted to a conformance case
that fails against the previous commit:

- *A nullary constructor nested inside a fieldful pattern.* `(Red)` in
  `(Wrap (Red))` parsed through `parseExpr`, which has no pattern
  context, so it became an ordinary variable - a BINDER matching
  anything, and the first arm swallowed every scrutinee.
  `parseArmPattern` recurses now, so a pattern's arguments are parsed
  as patterns. The same erasure was already recorded as an
  under-reporting gap in the *checker*; in the emitter it was a wrong
  answer (`740-nested-nullary-pattern.ax`).
- *The builtin `Option` was absent from the codegen type registry.* It
  has no declaration for `scanCtors` to walk, so a match on `(Some x)`
  found no entry, bound nothing, and emitted `store i64 %x` naming a
  register that does not exist. The registry is seeded with both
  constructors; `Some` is tag 0 and `None` tag 1, probed directly
  against stage0 - `(cast Int (None))` exits 1 and the tag word of
  `(Some 7)`'s block is 0 - which is the reverse of what the comment
  beside the tag counter claimed (`750-builtin-option-match.ax`).
- *An application whose head is not a name.* The head dispatch had no
  arm for a lambda, an `if` or a `match`, and wrote the constant 0 -
  which does not emit a wrong call, it DELETES the application, so
  `((lambda (x) x) 7)` evaluated to 0. A non-name head is evaluated as
  a value and applied one argument at a time, the rule stage0 reached
  from the other side when its own non-name head lowered to a call to
  the undefined symbol `@unknown` (`760-lambda-head.ax`).
- *An over-applied spine.* `((adder 10) 5)` supplies two arguments to a
  one-parameter function that returns a closure; flattening it into
  one direct call passed both to `adder` and answered with the
  returned closure's *address*. The surplus is applied through the
  returned value now, gated on `isDefinedFn` rather than on arity
  alone, because an unknown name answers arity 0 and every binary
  operator would otherwise be treated as over-applied
  (`770-over-application.ax`).

**`160-arena` was never a stage1 bug**, and finding that out found a
real one underneath. Its arena primitives were genuinely missing and
are fixed - `__axiom_arena_mark` and `__axiom_arena_reset` were absent
from stage1's primitive table, so `(__axiom_arena_mark)`, a bare
reference since it takes no arguments, emitted `%__axiom_arena_mark`,
a value nothing defines. stage0 carries a comment about hitting
exactly this, for exactly this primitive; stage1's `emitVar` carried
the same comment, *naming* `__axiom_arena_mark` while handling only
`__argc`.

But the case still disagreed after that, and the cause was the gate's
own `llc` invocation. **The emitted bump allocator is miscompiled by
`llc` at `-O1` and above** - two consecutive `memAlloc 64` calls come
back a whole 1 MiB chunk apart instead of 64. It reproduces on
**stage0's own IR**, identically, so it is not a self-hosting defect
at all; it is the same hazard `axiom-codegen/src/gc.rs` already
carries `optnone` for, in the allocator beside it. `llc`'s default is
`-O2`, so any script that assembles emitted IR without saying
otherwise measures a broken allocator and attributes the damage to
whichever compiler produced the IR.

`axiom build` escapes it by running `opt` over the IR before `llc`,
which is why nothing noticed: every check that goes through the
driver is fine, and only the scripts that call `llc` directly are
exposed. Those now pass `-relocation-model=pic`, which axiom-cli
already documents as required of *every* `llc` invocation in the
project and which two of them were missing.

The `-O0` half cannot be applied uniformly, and the reason is worth
recording because the two hazards pull opposite ways: at `-O0` the
allocator is correct but there is no tail-call elimination, and stage2
compiling its own source overflows its stack - measured, it
segfaults. So `check-stdlib-selfhost.sh` uses `-O0`, where the
allocator matters and the stack does not, and the bootstrap and
conformance gates keep the optimiser, where the reverse is true. **Root-caused and fixed: an undeclared inline-asm clobber.** Darwin
arm64's `svc` destroys the argument registers - probed directly with a
C program that puts `0x100000` in x1, issues the `mmap` syscall and
reads x1 back, getting 0. The arm64 constraint strings declared
`~{memory}` and no register clobbers at all, while the x86-64 ones had
always declared the `rcx`/`r11` that `syscall` destroys. So LLVM
believed an argument register still held its value after the syscall,
and at `-O1` and above it acted on that belief: `%chunk` lived in x1
across the `svc`, `@__axiom_bump_end` was set to `addr + 0` instead of
`addr + chunk`, every subsequent allocation failed the fast path and
mapped a fresh megabyte. At `-O0` the same IR is correct, because LLVM
spills and reloads across the asm and never trusts the register - which
is the whole `-O0`/`-O1` split, and why it read as an optimiser bug.

Two wrong guesses are worth recording, because each looked right.
Marking the emitted `axiom_alloc` `noinline optnone`, exactly as
`gc.rs` marks the collector, changes nothing at any level - the
allocator's own code was never the problem. And the generated assembly
reads correct at `-O2`: both globals loaded, compared, and stored on
both paths, with two distinct `bl _axiom_alloc` calls in the caller.
Nothing is miscompiled in the sense of "wrong instructions emitted";
the instructions are right and one of the registers they read has been
destroyed by the kernel.

**It had shipped.** A missing `opt` is a warning rather than an error,
and `axiom build` defaults to `--opt 1`, so on any machine with `llc`
and `cc` but no `opt` the raw IR went straight to `llc -O1`. Probed
with exactly that PATH: the build succeeded, warned only that "deeply
recursive code may exhaust the stack", and produced a binary whose
consecutive allocations were a megabyte apart. Both compilers carry
the clobbers now, and `tests/selfhost/780-allocation-contiguous.ax`
pins it - deliberately written to run under the conformance gate's own
`llc` invocation, which does not pass `-O0`, so a test that only ran
at `-O0` could not have seen it.

`__axiom_arena_mark` and `__axiom_arena_reset` were missing from
stage1's primitive table entirely, so `(__axiom_arena_mark)` - a bare
reference, since it takes no arguments - fell through to the ordinary
variable path and emitted `%__axiom_arena_mark`, a value nothing
defines. stage0 carries a comment about hitting exactly this, for
exactly this primitive, calling it "the only one that could go
wrong"; stage1's `emitVar` carried the same comment, naming
`__axiom_arena_mark` while handling only `__argc`. Both primitives
lower now, instruction for instruction as stage0 does - the mark
allocates its two-word cell *before* reading the allocator position,
so the cell sits below the mark and survives the reset. What remains
wrong in that case is downstream of the primitives and in the emitted
bump allocator itself. Lowering the effect system itself was phase 4
work, not phase 3 — the checker's job is finished when it agrees about
what is wrong — and it has since landed; see the end of this document.

(This paragraph used to end "No lambda expressions (refused loudly)".
That was true when it was written and stopped being true two commits
later; stage1 compiles a lambda, and one that captures, and has since
`0c73140`. Probed: `(let ((g (lambda (x) (+ x k)))) (g n))` with `k`
captured from an enclosing `let` answers correctly through a
stage1-built binary. A stale claim in a document whose whole method is
falsifiable claims is worse than no claim, so it is recorded here as
having been one.)
stage1 emits S1's unboxed nullary constructors exactly as stage0
does: the per-type representation code (boxed / all-nullary / mixed)
travels on every constructor's registry entry, construction emits the
immediate tag, an unboxed pattern compares the value directly, and a
fieldful pattern in a mixed type reads the tag through the same
`< 4096` runtime guard - via a one-word heap cell rather than a phi,
the idiom stage1's `match` already uses. Pinned by
`tests/selfhost/620-nullary-unboxed.ax`, which both compilers answer
identically, including the two-`INil`-are-one-word identity that
boxing cannot satisfy. It emits for all four targets: the second argument names one
(`darwin-aarch64` by default), and the whole per-target surface -
triple, syscall register conventions, Darwin's carry-flag error
normalisation, the allocator's mmap/exit numbers and MAP_ANON flags,
and the platform-module suffix search (`.{os}-{arch}.ax`, `.{os}.ax`,
`.ax`) - mirrors stage0's `target.rs` value for value, in one table
in `codegen.ax`. An unknown target name is refused naming the four
that exist, because emitting the wrong syscall convention is a binary
that dies at its first write. `check-self-host.sh` assembles the
syscall-heavy conformance case under every target's own triple, since
a wrong number is invisible on the host - Linux's mmap 9 assembles
fine on Darwin. The driver takes its input path as the first
command-line argument - programs can read their arguments now: the emitted `@main`
is a wrapper that captures `argc`/`argv` into globals before calling
the renamed user entry (`__axiom_user_main`), the `__argc`/`__argv`
primitives read them back, and `Sys.sysArgc`/`sysArg` are the
bounds-checked surface, in both compilers identically
(`tests/selfhost/610-args.ax`, `tests/stdlib/290-args.ax`). With no
argument it still reads `in.ax` from the working directory, and
output is still stdout. Float literals with more
precision than a double round twice where stage0 rounds once, so a
last-ulp divergence is possible for literals outside the corpus;
byte-identical emission (phase 4) needs a single-rounding
conversion.

None of those is on the bootstrap path, which is why the fixpoint holds
without them; all of them are between here and replacing stage0.

*Bugs found and fixed getting here*, each of which had made the emitted
code wrong rather than absent: call arguments lost their type after the
first; name lookup compared string *lengths*, so `(+ a b)` found a
one-letter `struct` in the type registry and was emitted as a
construction; the symbol table was never cleared between functions, so a
`let`-bound name shadowed a later function's parameter; `phi` nodes
named the block a branch *started* in rather than the one that reached
the merge, which is wrong whenever an arm contains a nested `if`;
constructor tags started at -1 and `fmtInt` rendered -1 as `/`; the
lexer had no escape handling, so `"c\""` ended at the middle quote; and
`&&`/`||` did not short-circuit, which crashed the compiler on its own
source, since `isNullaryFn` reads a field that only exists once the
declaration is known to be a function.

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
tables.

This phase used to ask for `.ll` matching the Rust backend
byte-for-byte, "a stricter and much easier-to-debug criterion than
*produces a working program*" - true when it was written, and no longer
the right target. Measured, it asks stage1 to adopt three design
choices of the compiler being retired, one of which measurably costs
stack depth; the section "What scouting phase 4 found first" above
carries the numbers and the reasoning.

*Exit criteria:* every case in `tests/stdlib/` and `tests/selfhost/`
compiled by both compilers agrees on exit status and stdout, with each
compiler's IR put through an identical `llc`/`cc` pipeline at `-O0` and
`-O2` (`scripts/check-stdlib-selfhost.sh`, in CI, with a counted floor);
stage1's output assembles for all four targets; and the bootstrap
fixpoint holds. Byte-identity is still required where it carries
meaning - `stage2 == stage3`, as objects and as emitted IR - which
`scripts/check-bootstrap.sh` checks.

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

**Amended 2026-08-08, when the Rust compiler was deleted.** The
sentence below said rollback stays cheap "because the Rust compiler is
never deleted while the Axiom one is unproven". That was the right rule
while "proven" was an open question. It is now closed by §8: the
compiler builds itself from a committed seed with no Rust in the path,
reaches `stage2 == stage3` every time it does, and every gate that used
to lean on the Rust compiler has been given a half that does not.

Rollback is therefore `git revert` of the deletion commit, plus
`cargo build --release`, against a tree that still contains every other
change. What it is NOT any longer is free: the two compilers have
diverged deliberately in the ways §8.4 records, so reverting changes
`symbols` output, some parse-error codes, and the human diagnostic
layout back. Those are the divergences, listed, so a rollback can be
priced rather than discovered.

The original text, still true of everything except the Rust compiler's
presence:

- **Trigger:** any of - self-hosting fixpoint lost; conformance
  regression; >20% compile-throughput regression; a miscompilation with
  no root cause within one working day.
- **Action:** revert the default compiler selection to stage0. Since
  stage0 remains in the tree and in CI, this is a one-line change with
  no data migration.
- **Blast radius:** none for downstream users while the Axiom compiler is
  opt-in; the public CLI, the machine diagnostic formats (AXDL, JSON),
  and the ABI are unchanged by the port, which is why "identical output"
  is the acceptance criterion for every machine-read surface. The one
  recorded exception (2026-08-07) is the HUMAN diagnostic rendering:
  stage0's is the `ariadne` crate's output and stage1's is native (see
  "The human renderer" below), so reverting the compiler selection
  visibly changes error-report layout - and changes nothing a tool
  parses, because every fact in a human report is pinned through the
  AXDL line for the same diagnostic. A rollback that needs the old
  look needs no code change beyond the selection itself.

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

**Struct variants work end to end.** `(Rect { w : Int, h : Int })` in
a `data` declaration, `(Rect { h = h, w = w })` as a pattern, `{ w, h }`
punning, named patterns nested inside named patterns, and `s.r` field
access by name on a data value - `tests/stdlib/210-struct-variants.ax`
now matches stage0 byte for byte.

The shape of the implementation is the useful part: **a named
constructor is a positional one that also knows what its fields are
called.** The declaration records the names in a spare ASTNode word
and builds arity, per-field float flags and per-field type nodes
exactly as the positional spelling does, so a positional pattern over
a named declaration needs no work anywhere downstream - measured, that
alone made a whole class of program compile. A named PATTERN is
reordered against those recorded names into the positional spine both
the checker and the emitter already understood, so the mixed-rep
`< 4096` tag guard, the word-*i*+1 field loads and the float flags are
all untouched.

It is not desugared at parse time, and cannot be: the declaration
saying what order the fields are in may not have been seen yet. Both
consumers reorder, which is where stage0 does it too. Punning IS
resolved at parse time, because it needs no declaration - `{ w }` is
`{ w = w }` whatever `w` turns out to be.

Four things had to be got right and each was found by a failing
measurement rather than by reading:

- The reversed-order pattern is the only spelling that DISCRIMINATES.
  `{ h = h, w = w }` over `(Rect 3 4)` answers 34 when bound by name
  and 43 when bound by position, so the conformance case reverses them
  deliberately.
- Landing the declaration side alone made things *worse* before it
  made them better: `210` began to parse, so the silence sweep started
  reading it, and its named patterns misparsed into four false
  diagnostics. Half of this feature is worse than none of it.
- Exhaustiveness had to learn that a named arm covers its constructor,
  or every named `match` drew a false `AX3005`.
- A nested named pattern has to recurse in the *checker's* binder walk
  as well as the emitter's; without it `(Wrap { inner = (Rect { w, h }) })`
  bound nothing and every use of `w` was an undefined variable.

Field access by name on a data value reproduces stage0's looseness
rather than tightening it: stage0 scans every data type and every
constructor with named fields, first match winning, without consulting
the scrutinee's type at all. Tightening that would refuse programs
stage0 accepts.

**Qualified references parse.** `Mod::name` is B4's spelling and
stage1 could not read it at all: `parseIdentRef` committed to a
field-access chain as each `.` was consumed, so the `::` was never
reached - the identical mistake stage0 records having made, where a
dotted module name reported "expected expression, found `::`". The
chain is collected first and the decision taken after, which is
stage0's order.

It needs no AST node. The module path joined by `.`, then `$`, then
the name IS the mangled symbol every imported declaration already
carries - `Mem::memAlloc` is `Mem$memAlloc`, exactly what `mangleDecl`
wrote - so a qualified reference resolves to an ordinary variable
reference and the checker and emitter need to know nothing about it.
Pinned by `tests/selfhost/790-qualified-reference.ax`.

`tests/stdlib/150-qualified-modules.ax` compiles and matches stage0
now, which took one more fix than the parser: the gate was handing
stage1 a *copy* of each case, and a case importing a module that sits
beside it - that one imports `Q.Inner`, i.e. `tests/stdlib/Q/Inner.ax` -
cannot resolve it from a copy in a work directory. stage1 derives its
module search directory from its argument, so the gate passes the real
path.


**The effect system lowers.** `(effect E (op :: ...))`, `handle`, and
operation calls all emit code through stage1 now, which was the last
piece of language surface it refused. `check-stdlib-selfhost.sh` has
no skip list left: **33 of 33 cases agree with stage0**, where three
were skipped as "parses and checks it, but does not lower effects".

The lowering is stage0's, transliterated. An effect's evidence is a
mutable global holding either 0 - no handler installed - or the
address of a two-word `{handler, previous}` record; `handle` pushes
one and pops it, and an operation call loads it, installs `previous`
for the duration of the handler, and restores. Three properties of
that shape are worth stating because each has a plausible alternative
that is wrong:

- **The handler runs under the evidence in scope at its
  installation**, not under its own. An operation the handler itself
  performs therefore dispatches *outward*, to the next handler out;
  the naive lowering re-enters the same handler forever. Ablated: the
  conformance case SIGSEGVs.
- **The slot is restored after the body, so the body is not in tail
  position.** stage1 rewrites a self tail call into a jump, and a jump
  out of the body would leave the handler installed for the rest of
  the program. Ablated: the case answers 1 instead of 42, because a
  later operation reaches the inner handler the outer one should have
  replaced.
- **No handler installed is a trap, not a zero.** The operation has no
  result to produce, and continuing on a garbage one turns a missing
  handler into a wrong answer somewhere else entirely. Exit 71, which
  the allocators' out-of-memory 70 deliberately does not collide with.

Arguments are evaluated *before* the slot is read, which is stage0's
order and observable at exactly one point: an argument that prints
must print even when the dispatch below traps. That cost a second
apply helper - `emitApplyChain` interleaves evaluation with
application, which is stage1's existing idiom for every function value
- rather than accepting the difference.

Two deliberate differences from stage0 remain, both unobservable. It
emits an evidence global per *declared* effect where stage0 emits one
per effect the program actually touches, so an effect nothing performs
or handles costs one internal, unreferenced global. And the globals
land after the functions rather than between them, which is where
stage1 emits every global; LLVM does not care, and byte-identical `.ll`
is phase 4's problem, not this one.

`tests/selfhost/820-effect-handlers.ax` is the conformance case, and
its five terms are chosen so that the sum discriminates: dispatch
through a helper that names no handler (dynamic, not lexical), an
inner handle that must shadow *and restore*, a handler performing its
own effect (outward dispatch), a two-argument operation taking a
curried handler chain one argument per indirect call, and a local
shadowing an operation name, which binds the local because that is how
sema resolves it. The two ablations above are how the case is known to
discriminate rather than merely to pass.

**A qualified operation call was a false `AX3001`**, and finding it
took a probe rather than a gate: no file in any swept tree performs an
effect declared in another module. stage1 resolves `EffOps::ask` by
mangling it flat into `EffOps$ask` - the spelling `mangleDecl` gives
every imported declaration - and `effect` is one of the two declaration
kinds `mangleDecl` never rewrites, so the name existed under `ask`
alone and the reference was undefined. stage0 compiles and runs the
same program. Operations of an imported effect are registered under
both spellings now, in the checker and in the emitter, dispatching
through the one slot; the slot itself is keyed by (name, module) as
stage0's is, so two modules each declaring a `Console` get two globals
rather than one shared one (`tests/selfhost/830-effect-import.ax`,
which performs the operation under both spellings).

That case needed a module beside it, which no conformance case had
needed before, and the arrangement is worth recording because the
obvious one fails. A subdirectory - `check-diagnostics.sh`'s `mods/`
pattern - keeps the per-case glob from mistaking a module for a case,
but the diagnostics *sweep* reads every file of `tests/selfhost/` from
its real path, so a case whose import resolves only inside a work
directory fails the sweep, correctly, as "exited 3 with no diagnostic:
it did not get far enough to check". Modules therefore sit beside the
cases and are told apart by name: a case is digit-prefixed and must
declare `; expect N`, anything else is a module.

Which turned up a hole in `check-self-host.sh` itself. A file with no
`; expect N` printed `SKIP` and went on - so a case that lost its
expectation line stopped being run and reported nothing, which is what
success looks like. It is a failure now, and the negative check is a
case file with the line removed.

Writing the fix also found the flat namespace paying out in the strict
direction for once. `tcCollectEffectOps` used `cat3`, which lives in
`codegen.ax`; `typecheck.ax` does not import it. stage0 resolves the
name anyway - B4's flat namespace merges every module's declarations -
and stage1 refused it as an undefined variable, which is the stricter
and better answer, and is the "module-internal references should bind
module-locally" item this document already records as open.

**The lexer is a loop now, and finding out why is the more useful
half.** Adding the effect lowering made `check-fmt` fail on
`tests/selfhost/300-pipeline.ax` - a case about running the whole
pipeline, which touches nothing the change went near - with SIGSEGV.
The gate formats a copy of the repository and re-runs the suites
against it, so the failure needed both the new code *and* formatting
to appear, which is the least informative shape a failure can take.

It was a stack overflow, and the measurement is the point:

| compiler, built by | input it survives |
|---|---|
| stage0 (`opt` runs; mutual tail calls flattened) | 396 KB, no trouble |
| stage1 (self tail calls only) | dies between 96 KB and 146 KB |

`lexTokens` and `dispatchChar` called each other in tail position, one
frame pair per token and none released until EOF. stage1's tail-call
rewrite fires only for a *self* call - deliberately, since that is
stage0's rule - so under a stage1-built compiler the lexer's stack
grew with its input. `codegen.ax` at 183 KB sat just under the line;
formatting expands source, and 188 KB was over it. Nothing about that
failure points at the lexer, which is why the bisect (one import at a
time: `Str`, `Vec`, `Mem`, `Sys`, `lexer`, `parser`, `typecheck` all
fine, `codegen` dead) was worth more than any amount of reading.

The loop makes each branch answer the *next position* rather than
recurse, so the loop owns the only frame; termination is that every
branch advances at least one byte, which is what the recursion got
from running out of input. `skipWhitespace` and `skipLineComment` had
the same shape at a smaller scale - a frame per byte of a
comment-and-whitespace run - and `skipLineComment` returns to the loop
now instead of calling back into it.

Measured after, on the same stage1-built pipeline: 814 KB compiles,
1.24 MB is killed for memory (exit 137 - a stage1-built binary has the
bump allocator and no collector), and 1.66 MB overflows the stack
again somewhere past the lexer. Both are real ceilings and both are
recorded rather than fixed: they sit four to eight times above the
largest module in this repository, where the old one sat *below* it.

`tests/selfhost/840-large-lex.ax` pins it - 19 bytes doubled fourteen
times, ~200,000 tokens through a stage1-built binary - and restoring
the recursive spelling fails it with SIGSEGV, which is how the case is
known to discriminate. It is the same lesson `690-large-memcopy.ax`
already carries, one layer up: **a self-hosted compiler pays for every
mutual tail call its own backend does not eliminate**, and the bill
arrives as an unrelated test breaking after an unrelated change. The
remaining mutual recursions in `self_host/` are the parser's, whose
depth is nesting rather than length, and they are bounded by the same
programs the parser already reads.

**A module binds its own names.** A bare reference inside module `M`
now resolves to `M`'s own definition when `M` has one, before the
entry file is consulted. Before that, importing a module could change
what the module *did*:

```scheme fragment
; Lib.ax
(pub fn (helper x) (* x 10))
(pub fn (libCall x) (helper x))

; main.ax
(import Lib)
(fn (helper x) (+ x 1))          ; the entry file happens to define one
(fn (main) (libCall 5))
```

`Lib.libCall` calls `Lib.helper`, so the answer is 50. Both compilers
answered **6** - the entry file's `helper` - and neither diagnosed
anything, because under B4's flat namespace `helper` had exactly one
winner and the winner was the entry file's, whoever was asking. A
namespace in which importing a module rewrites that module's calls is
not a namespace; this document has carried it as a recorded-open item
since the resolution scout found it, on the strength of `320-mangle`
passing only because both answers landed on the same side of its
comparison.

The rule is a *prepended* candidate and nothing else: **the defining
module's own definition, then the entry file, then the unique defining
module, then `AX3014`.** A name `M` does not define resolves exactly as
it did before, which is the half a test has to pin deliberately,
because replacing the lookup instead of preceding it passes every
other case.

It had to land in four places at once, and that is the real constraint
here rather than any one of the changes: stage0's `mangled_name_for`
(which symbol the call reaches) and `resolve_bare_fn` (which
definition the checker types against), and stage1's `mangledFor` and
`findFnEnt`. A checker that resolves one way while the generator
resolves another is exactly the failure this area was rewritten once
before to remove - a program that type-checked against one definition
and *ran* another.

One thing did not fit. stage1's mangle map holds one winner per bare
name, so it cannot answer "does `M` define this name at all" - the
entry file's claim is the only entry there. The mangled name maps to
itself now, recorded *outside* the dedupe that guards the bare slot,
which makes the membership question a lookup in the map that was
already being consulted. It changes no existing answer: the only
reference that can match one of those entries is a qualified
`Mod::name`, which stage1 already spells `Mod$name` and which already
resolved to itself by falling off the end of the map.

`tests/selfhost/850-module-local-binding.ax` pins three terms, each
failing differently: the module's call to its own `helper` (40, where
the old rule gave 5), the entry file's call to its own (5, which must
not have moved), and a call to a name the module does not define,
reached through a module it imports (104, the term that fails if the
new rule replaced the old lookup rather than preceding it). Both
compilers answered 1 before the change and 42 after. `320-mangle`
still passes, and now for the right reason: `Str.ax`'s internal
`strLen` reaches `Str`'s.

**The rule had to reach effects in the same breath, and not doing so
broke a working program.** Effect *operations* live in the same table
as functions, so `resolve_bare_fn` made them module-local for free.
The effect a `handle` installs resolves somewhere else entirely -
`resolve_effect_decl` - which was still entry-first. A module
declaring its own `Console` then installed its handler in one global
while its own `log` dispatched on another, and the operation found no
handler: **exit 71, the unhandled-effect trap, on valid source that
answered 42 the commit before.** The two lookups had been agreeing by
both being entry-first, which is the kind of agreement that survives
exactly until one side is improved.

Both are module-local now, in both compilers, and stage1 needed the
same pairing: its effect *names* are registered under `Mod$name` as
its operations already were, and the evidence globals are emitted per
SLOT rather than per registry entry, since the two spellings of one
effect share one slot and emitting per entry defined the same global
twice. `tests/selfhost/860-module-local-effect.ax` is the guard: it
answers 42 when the two lookups agree and 71 when they do not.

The semantics this settles are worth stating, because they are a
decision rather than a bug fix: **an effect declared in two modules is
two effects.** stage0 has always given them separate slots
(`effect_slot_name` keys by name *and* module); it was only resolution
that conflated them. So an entry file's handler for its own `Console`
does not handle an imported module's `Console` - probed, both
compilers trap identically rather than dispatching to the wrong
handler. Before this, a module's own effect declaration was simply
unreachable from inside that module, which is the same defect as
`helper` wearing different clothes.

What is *not* fixed is the rest of the flat namespace. A module still
sees names from modules it does not import - resolution outward from a
module is still the merged list, not that module's own import set - so
the reverse hazard remains: a module that references a name it neither
defines nor imports still finds one. That is the same B4 decision, and
the half that needs a real scope per module rather than one more
candidate in front of a flat lookup.

**The compiler can be used from a directory it does not own.** stage1
searched the entry file's directory and then the literal strings
`self_host/` and `stdlib/` *relative to its working directory*, so a
user compiling a hello-world that imports `IO` from anywhere else got
`cannot read module: IO` and exit 3. Probed from a scratch directory,
which is all it took. Every gate in this repository hid it, either by
running from the repo root or by salting a work directory with
`ln -s "$repo_root/stdlib"` - the workaround was so uniform that the
defect read as configuration.

The search is stage0's `module_search_dirs` now, reproduced in order:
the entry file's own directory first, so a project can shadow a
standard-library module; then `AXIOM_PATH` entries, colon-separated;
then the standard library, located by `AXIOM_STDLIB` or, failing that,
relative to the compiler binary (`<exe>/../stdlib` for an installed
layout, `<exe>/../../stdlib` for a build tree). The two CWD-relative
entries are kept at the end as a fallback rather than deleted, because
five harnesses depend on them and breaking all of them in one commit
destroys the ability to bisect the only gates that watch stage1.

`sysArg 0` is argv[0] rather than a real `current_exe`, so a compiler
invoked by a bare name found on `PATH` resolves the exe-relative
entries against the working directory instead. That degrades to the old
behaviour rather than to something wrong, and `AXIOM_STDLIB` overrides
it. The gate is a new case in `check-self-host.sh` that compiles a file
importing `IO` from a *fresh* directory containing nothing else;
restoring the hardcoded pair fails it and nothing else.

Reading the module also stopped happening twice. The path search and
the source read were two independent walks of the same candidate list,
so the filename a diagnostic renders against and the text it renders
from could in principle come from different candidates; there is one
search now, and the read follows it.

**The self-hosted compiler knows what host it is on, and did not.** The
target defaulted to the literal string `"darwin-aarch64"`, written into
`main.ax`. `scripts/check-bootstrap.sh` passes no target argument and
its CI job runs on `ubuntu-latest`, so the Linux fixpoint job was
compiling the compiler with a Mach-O triple: measured, stage1 with no
target emits `target triple = "arm64-apple-macosx14.0.0"`, and `llc`
turns that into a `Mach-O 64-bit object arm64`, which no Linux linker
will accept.

That job has never run. It was added to CI on 2026-08-04 (`d2ed483`);
the most recent CI run on this repository is 2026-07-30. So **none of
the self-hosting work described in this document has been through CI**,
and the fixpoint is verified on macOS ARM only. That is worth stating
plainly next to every "gated in CI" claim above: the gate exists, is
wired up, and has not yet executed once.

The fix is a per-target `Host` module - `self_host/Host.{os}-{arch}.ax`
- selected by the same suffix mechanism the standard library's syscall
tables use. The answer is therefore baked in when the compiler is
*compiled*, which is the only time anything knows: a freestanding
binary has no `uname` to ask. And because stage0 defaults `--target` to
`Target::host`, the property is inherited down the whole ladder without
a target argument anywhere - stage0 on a Linux runner builds a stage1
whose `hostTarget` is `linux-x86_64`, which builds a Linux stage2.
Measured: the four builds of `main.ax` emit four different host
constants and four different triples. There is deliberately no
fallback `Host.ax`, so a target with no file fails loudly at compile
time rather than silently inheriting somebody else's triple.

**`Sys` can start a child process**, which is the capability a compiler
driver is built on and the one thing the standard library could not do
at all. `sysSpawn`, `sysWaitPid`, `sysRun`, `sysRunPath`, `sysEnv` and
`sysEnvp` are the surface; `tests/stdlib/300-process.ax` is the gate,
green on all four targets at both optimisation levels.

The two platforms reach it differently, and the difference is forced
rather than chosen. **Darwin's `fork` returns two values** - the pid in
x0 and an "am I the child" flag in x1 - and `__syscallN` yields one
register, so a Darwin child would read its parent's pid and both
processes would take the parent branch. `posix_spawn` returns the pid
through a pointer, which one register carries. Linux's `fork` returns 0
in the child through that same single register, so there it is
expressible directly; AArch64 Linux has no `fork` in its table at all
and spells it `clone(SIGCHLD)`. `Sys.Platform.spawnUsesPosixSpawn` is
the capability that selects between them, in keeping with
`openNeedsDirFd`: nothing portable names an OS.

The bug worth recording is one of *arity*, and it is nearly invisible.
**Darwin's `posix_spawn` syscall is not libc's `posix_spawn` function.**
libc takes six arguments (pid, path, file_actions, attrp, argv, envp);
the kernel entry point takes five, with the file actions and the
attributes fused into one `_posix_spawn_args_desc`. Passing the libc
shape puts `argv` in the kernel's `envp` slot, and the child receives a
NULL argv - while still running, still being waited for, and still
reporting the right exit status. `/usr/bin/false` answers 1 either way.
The only witness is a child whose behaviour depends on its arguments:
`sh -c "exit 7"` answers **0** under the six-argument spelling, because
`sh` with no arguments reads EOF from stdin and exits successfully, and
**1792** - 7 << 8 - under the five. Both spellings were run; that is
the whole difference between them.

The environment needed no new primitive, which was not obvious. There
is no `__envp`, but the kernel lays the initial process stack out as
`argc, argv[0..n-1], NULL, envp[0..m-1], NULL` contiguously on both
platforms, and `__argv` indexes that vector unchecked - the primitives
are where the type system stops. Probed: `argv[argc]` reads 0 and
`argv[argc+1]` reads a `NAME=value` string. Deriving it beat adding a
third parameter to the entry wrapper, which would have had to land in
both compilers at once to keep the bootstrap building.

`sysRunPath` searches `PATH` by *attempting* each candidate rather than
by testing for the file first. That needs no `access` syscall - AArch64
Linux has none, only `faccessat` - and cannot be raced between the test
and the spawn. The cost is that a candidate which exists but is not
executable is skipped rather than reported, where `execvp` remembers
the EACCES; a driver looking for `llc` wants the next candidate either
way.

Only darwin-aarch64 is *run*-tested here. The other three assemble at
`-O0` and `-O2` under their own triples, and the Linux paths are
executed by CI's Linux runners - which, per the note above, have not
executed anything since 2026-07-30.

**Three gates were measuring less than they claimed, and one latent
miscompile was the same one that already shipped.**

*The freestanding gate could not see a libc spawn.* Its forbidden-name
list was eleven allocation- and stdio-shaped names, so a
`(foreign posix_spawn ...)` binding emitted `call i64 @posix_spawn(...)`,
linked against libc, and passed both the IR grep and the `nm` check -
verified before the list was widened. That matters precisely here,
because `posix_spawn` is a *function* and not a syscall on every system
that documents it, making libc the tempting implementation. The list
now carries the process-control family, and the gate ends with a
negative probe that compiles a program which deliberately calls libc
and fails if either mechanism lets it through. A gate asserting silence
needs one, because a broken grep produces silence too.

*The four-target check passed vacuously for one of its four.*
`check-self-host.sh` emits the syscall-heavy case for each target and
assembles it under that target's triple. But darwin-aarch64's IR
assembles cleanly under `aarch64-unknown-linux-gnu` - `svc #0x80` is a
valid AArch64 instruction whatever the OS, and `{x16}` allocates fine -
so if stage1 ever stopped honouring its target argument, the loop would
emit the same Darwin IR four times and still report three green while
every Linux binary carried Darwin syscall numbers. The four modules are
now required to be pairwise distinct, which is satisfiable today and so
is an assertion about the compiler rather than an aspiration.

*Darwin x86-64 was one undeclared clobber from the bug that shipped on
arm64.* The arm64 templates declare `~{x1}`..`~{x5}` because Darwin's
`svc` destroys the argument registers - probed, and the resulting bump
allocator miscompile reached users. The x86-64 Darwin template declared
only `~{rcx},~{r11}`, the two the `syscall` instruction itself destroys,
while listing `{dx}` as a live input - and `rdx` is Darwin's *second
return register*, the one `fork` and `pipe` answer through. Linux is
exempt because its ABI documents that the kernel preserves everything
else; Darwin documents no such thing and demonstrably does not honour
it. Both compilers declare the argument registers now, and a new test
asserts the general rule - every input register is either the output or
declared clobbered - which fails on the previous constraint string.
darwin-x86_64 is assembled by CI on every run and executed by no
runner, so that assertion is the only thing standing between it and the
identical bug.

## Phase 5: the compiler drives the toolchain itself

**`stage1 build --input self_host/main.ax --output stage2` works, and
the compiler it produces builds a byte-identical successor.** That is
the difference between a compiler and a component, and until now Axiom
had the component: stage1 wrote LLVM text to stdout and stopped.
Producing an executable meant a human - or, in every case that has ever
been measured, a gate script - running `opt`, `llc` and `cc` afterwards.
So the fixpoint above was a statement about the IR stage1 emits, not
about a compiler anyone could use.

`self_host/driver.ax` closes it. `build` writes the IR, runs `opt`,
runs `llc`, runs `cc`, and removes its intermediates, spawning each
child through `Sys.sysRunPath`. `check`, `emit-llvm` (to stdout or
`-o`), `run` and `version` are the rest of the surface.

The order, the argument vectors and the failure rules are stage0's,
deliberately, and not because copying is easier. Two compilers that
drive the toolchain differently produce different binaries from the same
source, and **the bootstrap fixpoint cannot see that**: both stages
carry the same driver, so a wrong `llc` flag is perfectly
self-consistent. That is risk #1 in this document's own table, and
matching stage0 is what keeps the comparison honest while stage0 is
still here to compare against. The rules that had to be copied rather
than invented:

- **A missing `opt` is a warning; a present `opt` that fails is fatal.**
  Both halves are load-bearing in opposite directions. It has to be
  survivable because `opt` is not always installed - and it has to
  actually run, because without its tail-call pass a stage2 compiling
  its own source overflows its stack. Probed both ways with a poisoned
  `PATH`: a `PATH` holding only `llc` and `cc` builds a working binary
  and warns, and an `llc` that exits 1 fails the build with exit 4 and
  leaves no executable behind.
- **`-relocation-model=pic` on every `llc` invocation**, which
  axiom-cli documents as required of all of them and which two scripts
  in this repository had already been caught missing.
- **Intermediates are removed on the failure paths too**, so a failed
  build cannot leave a `.o` that makes the next one ambiguous.

`run` is the one deliberate divergence. stage0 pins its `run` at
`--opt 0`, which is survivable for a small program and is not for this
one: without `opt` the compiler overflows its stack compiling itself, so
a `run` that copied stage0 would fail on the largest Axiom program in
existence. It optimises.

Exit 4 is new and distinguishes a native tool failing or being absent
from exit 1, a program that does not check. Reporting both as 1 sends
the reader to the wrong place - to their source, when the answer is
that `llc` is not installed.

**The argument grammar is strictly additive, and that is a constraint
rather than a courtesy.** Five harnesses invoke stage1 as
`stage1 [FILE [TARGET]]`, and they are the only gates that watch this
compiler at all; a subcommand CLI that replaced that spelling would
break all five in one commit and take with it the ability to bisect
anything that follows. So a first argument naming a known subcommand is
parsed as one and anything else keeps its old meaning. The cost is a
file literally named `build` or `check` with no extension, recorded
rather than defended against.

*The measurement that nearly read as a lost fixpoint.* Built side by
side, the self-driven `stage2` and `stage3` differ - in 48 bytes of
381,672. They are not a compiler disagreement: the emitted IR is
byte-identical, and the differing runs are 16 bytes at offset 1128 and
32 bytes near the end, which are the Mach-O `LC_UUID` and the ad-hoc
code signature that covers it. `ld` derives that UUID from the **output
path**, so `stage2` and `stage3` get different ones by virtue of being
called `stage2` and `stage3`. Built to the same basename in different
directories they are byte-identical, which is how `check-bootstrap.sh`
now does it. A gate that compares linked binaries has to control for
this, and the failure it produces otherwise points squarely at the
compiler and is nothing to do with it.

`Sys` grew `sysWriteFile` and `sysUnlink` for the same slice - the
library could read a file and write to an open descriptor, but nothing
put a string on disk under a name, and nothing removed one. AArch64
Linux has no `unlink`, only `unlinkat`, which is the same shape as
`open`/`openat` and so branches on the existing `openNeedsDirFd`
capability rather than growing a second one.

`check-bootstrap.sh` now runs the ladder twice: once as before, with
the harness driving `llc` and `cc`, and once with the compiler driving
them. The two are kept separate rather than merged so that a bug in the
driver cannot take the fixpoint signal down with it. The second ladder
finishes by building and running a real program through the self-built
compiler, because two compilers can agree on their own source and still
both be wrong.

*What is still stage0's.* `symbols`, `explain`, `fmt` and the REPL have
no stage1 equivalent, and `--diagnostic-format` is accepted nowhere -
stage1 emits AXDL always, which is what the diagnostics gate reads and
what `human` would be invisible to. `fmt` is the load-bearing one:
phase 5's "full test suite green under stage2" needs it, since five gate
call sites use it. `run` does not forward arguments to the program it
runs. None of these is on the bootstrap path, which is why the fixpoint
holds without them.

### The optimiser was linking the freestanding language against libc

`check-freestanding.sh` had only ever been run with stage0. Pointing it
at the self-hosted compiler failed **every case in the corpus**, with
the same symptom each time: the linked executable imported `_strlen`
and `_memset`.

Neither compiler emits either. `opt -O1` synthesises them: LLVM's
loop-idiom recogniser rewrites a byte loop into a call to `strlen` or
`memset`, which are libc symbols in a language that has deliberately
never linked libc. Measured on `010-hello.ax` - stage0's IR comes back
from `opt -O1` with zero mentions of `strlen`, and stage1's with
**seventeen**. The pass fires on stage1's register/`phi` form and not on
stage0's alloca form, which is why the language's central invariant had
been quietly conditional on which backend produced the IR.

The fix is one function attribute, `"no-builtins"`, on every emitted
definition, plus the attribute group at the end of the module. Both
compilers carry it: the freestanding contract belongs to the language,
not to one backend, and stage0 was one optimiser heuristic away from
the same failure.

The attribute that works is **not** the one that looks right.
`nobuiltin` - the enum attribute - left all seventeen `strlen`
references in place, measured on its own. `"no-builtins"`, the string
attribute clang emits for `-fno-builtin`, removes them and the linked
binary imports nothing. Testing the two together would have shipped a
change half of which did nothing.

The accepted cost is that a byte loop stays a byte loop rather than
becoming a tuned `memcpy`. A freestanding language cannot take the
faster option, because the faster option is a symbol it has no way to
define.

`check-freestanding.sh` now runs the whole corpus through **both**
compilers, building each case with stage1's own driver - the only place
in the gates that exercises it end to end - and counts what it read so
that a loop which silently stopped matching cannot report the silence it
was looking for. Before the fix that pass fails all 34 cases; after it,
34 of 34 import no libc.

### How much of the suite runs under the self-hosted compiler

Phase 5 exits on "full test suite green under stage2". Measured today by
pointing each gate's `$AXIOM` at a stage2 built from `self_host/main.ax`:

| gate | under stage2 | checks |
|---|---|---:|
| `run-stdlib-tests.sh` | passes | 34 |
| `check-reproducible.sh` | passes | 34 |
| `check-cross-targets.sh` | passes | 272 |
| `check-freestanding.sh` | passes | 35 |

Every gate whose job is simply *to compile things* now passes with the
Axiom compiler doing the compiling, on all four targets at both
optimisation levels. The remaining gates are not failures of stage2 and
mostly cannot be run against it by construction: `check-self-host.sh`,
`check-bootstrap.sh`, `check-stdlib-selfhost.sh` and
`check-diagnostics.sh` exist *to compare stage0 with stage1*, so stage0
is an input rather than a substitutable component.

The one real gap is `check-fmt.sh`, which needs `axiom fmt` - and
`fmt` has no stage1 implementation. That is the load-bearing item left
in phase 5, ahead of `symbols`, `explain` and the REPL, because five
gate call sites use it.

Getting the gates to run at all needed one CLI fix worth recording:
global flags may precede the subcommand, because stage0's clap accepts
them anywhere and `check-cross-targets.sh` relies on it
(`axiom --target=<t> emit-llvm <file> -o <out>`). Dispatching on argv[1]
read `--target=linux-x86_64` as an input filename and answered `cannot
read input`. The subcommand is now found by scanning past leading flags,
and its operands begin one past *its* index rather than at a fixed 2 -
which is the same bug one level down, and handed the subcommand's own
name back as the input file.

### A gate for the driver, and `--help`

No gate in this repository had ever invoked a compiler *driver*. Every
one of them drives stage1 as `stage1 [FILE [TARGET]]` and runs `llc` and
`cc` itself, so `stage1 build` - the thing a user types - was exercised
by nothing. `scripts/check-driver.sh` is that gate, 17 cases, in CI.

Its load-bearing cases are the negative ones, because a driver that
ignores a child's exit status reports a failed `llc` as a successful
build while every positive test still passes. So it poisons `PATH` in
two directions and requires the outcomes to differ: an `llc` that exits
1 must fail the build with exit 4 and leave no executable, and a `PATH`
holding `llc` and `cc` but no `opt` must warn and still produce a
working binary. It also pins each exit code to its own cause (1 bad
input or failing check, 2 parse error, 3 unresolvable import, 4 native
tool), that `build` removes its intermediates, that `--emit-llvm` keeps
the IR and still removes the object, that `run` propagates the
program's own status, and that both legacy spellings still work.

Two things it found immediately. `--help` did nothing: it begins with
`-`, so the scan that lets global options precede a subcommand skipped
it, no positional remained, and the compiler fell back to reading
`in.ax` and reported `cannot read input`. A compiler whose `--help` is
an obscure file error is a compiler nobody gets past. And that error
did not name the file it could not read, so a mistyped subcommand -
which the additive grammar correctly treats as a filename - reported a
failure with nothing in it to act on. Both fixed; `cannot read input:
frobnicate` is the message now.

### One self-compile cost 16.9 GB, and nothing said so

The self-hosted compiler's dominant cost was not lexing, parsing,
checking or lowering. It was the last line of code generation.

`renderCG` turned the emitted line vector into one string by left-folding
`strConcat` over it. `strConcat` allocates a fresh buffer and copies both
operands, and Axiom's allocator is a bump pointer with no free, so each
line copied everything emitted so far into new memory and left the
previous copy behind. Peak was therefore the **sum** of every
intermediate rather than the largest one, and it grew with the square of
the output.

Measured with `/usr/bin/time -l`, the same compiler source compiled by
the same stage1 before and after:

| | peak footprint | wall |
|---|---:|---:|
| left-fold `strConcat` | 16,973,522,240 | 11.54 s |
| measure, allocate once, copy | 72,958,912 | 0.85 s |

232× less memory, 13.6× faster, and `cmp` says the two outputs are
byte-identical — which is the only interesting property, since a
"faster" code generator that emits different code is a different
compiler.

The replacement walks the vector twice: once adding up
`strLen(line) + 1`, once copying into a single buffer of exactly that
size. Both walks are `while` loops rather than self tail calls, for the
reason `stdlib/Mem.ax` records at length — their depth is the size of
the data, and stage1 emits no tail-call elimination, so the recursive
spelling is a real call chain one frame deep per line.

**The shape mattered more than the constant.** At `(bytes × lines) / 2`,
every module added to `self_host/` paid for itself twice: the compiler
got bigger, so its output got bigger, so the fold got quadratically more
expensive. That is a bad property for a self-hosted compiler to have
while it is still growing — and the next thing to be added to it is a
formatter.

`check-bootstrap.sh` now measures one self-compile's peak RSS and
refuses over 400 MiB. A ceiling, not a benchmark: the number to protect
is the shape. Quadratic growth crosses 400 MiB long before it crosses a
CI runner's limit, and when it does it presents as a SIGKILL in a job
that looks unrelated — which is exactly how the two bootstrap failures
this document already records presented. The measurement fails rather
than skips when neither `/usr/bin/time -l` nor `-v` works, because a
resource check that silently skips is this repository's most-repeated
mistake.

### A negative literal was only a literal outside a form

`(+ x -5)` was three arguments to `+`.

stage0's lexer emits `Minus` then `IntLiteral(5)` for `-5`, on purpose,
with a test that says so: a negative literal is a parser construct, not
a lexical one. But the parser only ever fused the two *outside* a
parenthesised form - the `in_parens` flag guarded the rule - so in
argument position the `-` stayed a bare variable and the form silently
grew an element. Since `+` takes two, that surfaced as
**`AX3013` partial application** pointing at the `-`, on a program
stage1 accepts and runs to 42, because stage1's lexer fuses `-` against
a following digit and so never had the problem.

The fix is one predicate: `-` immediately followed, **with no space
between them**, by a numeric literal is that literal. Adjacency is the
whole rule, and it is what keeps `(- 5)` meaning negation applied to a
positive literal while `(x -5)` means what it looks like. The spans
answer adjacency exactly, which is the one thing keeping the two tokens
separate buys.

It was found through `fmt` rather than through either compiler.
`(- 0 (- 4))` printed as `(- 0 -4)` on the first pass; that re-read as a
three-element form, and the second pass printed `(- 0 - 4)`. Both
spellings parse, so nothing but the idempotency check could see it - and
what it reported was a formatter that is not a fixed point, about a
parser rule two layers down.

Blast radius, measured by emitting IR for all 139 `.ax` files under
`stdlib/`, `tests/stdlib/` and `tests/selfhost/` before and after:
**137 are byte-identical**, and the two that change are the two about
negative literals. Both still answer 42; a `(let ((x -5)) ..)` now
lowers to the constant `-5` rather than to `sub 0, 5`.
`tests/selfhost/460-negative-literals.ax` carries all four positions -
binding, argument, after a leading operand, and the space-separated
spelling that must stay unary minus - and draws two `AX3013`s against
the previous parser.

### The formatter's design, decided by measurement

`fmt` is the last item in phase 5 that any gate depends on, and the two
decisions it turns on were both settled by probes rather than by
preference. Recording them here so the port starts from a decision.

**It formats from a concrete syntax tree, not from the compiler's AST.**
stage1's parser is deliberately lossier than stage0's, and got lossier
still while this was being decided. `type`, `trait` and `impl` are
consumed by `skipUnknownDecl` into an inert node; `foreign` keeps only
its name; `effect` keeps only its operation names. An AST-driven printer
would *delete* those declarations - which is exactly the family of
failure the six original `fmt` bugs were. And the ascription fix above
desugars `(:: e T)` to `(cast T e)` and `(- x)` to `(- 0 x)`, while
stage0 keeps both distinct and prints `(- 8)` back as `-8`. Matching
stage0 from stage1's AST would mean adding nodes back to the parser, the
checker and the emitter - a change on the bootstrap path, bought for a
formatter.

**It carries its own scanner, and must not touch `self_host/lexer.ax`.**
This is the one that inverts the obvious plan. The formatter needs
tokens stage1's lexer does not produce - `[`, `]`, `,`, `#| |#`, and
comment spans - so the obvious move is to add them to the shared lexer.
It is the wrong move, for a reason that has nothing to do with risk:
stage1's lexer fuses `-` against a following digit into a single
negative-integer token, deliberately (`lexer.ax:180-187` records why -
falling through made `-5` an identifier that codegen emitted as the SSA
name `%-5`), and stage0's emits two tokens. A formatter that shares
stage1's tokenisation therefore cannot reproduce stage0's output
whatever else it does. Since it needs its own scan regardless, adding
brackets and commas to the shared stream buys nothing and costs the
parser work to consume them - `{ w : Int, h : Int }` parses today
*because* the comma vanishes. `scanAxtags` is the precedent: a second
pass over the source, beside the tokenizer rather than inside it.

**The printer owes thirteen normalisations**, each measured by running
`axiom fmt` on a two-line file. They are rewrites, not reprints, and a
CST printer gets none of them for free:

| written | printed |
|---|---|
| `(define x 1)` | `(fn (x) 1)` |
| `(fn f = 7)` | `(fn (f) 7)` |
| `1_000_000` | `1000000` |
| `007` | `7` |
| `((g 1) 2)` | `(g 1 2)` |
| `(e)` | `e` |
| `{e}` | `e` |
| `(fn (f n) 1 2)` | a body wrapped in `{ }` |
| `(-> Int (-> Int Int))` | `(-> Int Int Int)` |
| `(Int)` | `Int` |
| `()` (a type) | `Unit` |
| `Integer` | `Int` |
| `Q.Inner::only` | `Q::Inner::only` |

plus: imports hoisted above every other declaration, exactly one blank
line between declarations and none preserved from the source, string and
char literals re-escaped from the *decoded* value, and a float printed
as the shortest decimal that round-trips its `f64`. That last one is
Ryu's job in general and a textual normalisation in practice - every
float literal in this repository is an exact short binary fraction, so
stripping trailing zeros after the point (keeping one) is byte-identical
today. That is a constraint on the corpus, not a property of the
printer, and it belongs in the zoo as a comment.

**The exit criterion is symmetric.** Not "stage1's output is
byte-identical to stage0's": stage0 *refuses* four constructs, one of
them its own non-idempotent unary minus, so a gate that only diffs bytes
on success passes silently in the direction that matters. Write it as:
stage0 and stage1 `fmt` are the same function, on identical bytes **and**
identical exit status, three-way against a checked-in golden - and
either side may be the one that moves.

### The formatter's front half: a second lexer, on purpose

`self_host/format.ax` starts with the two things the design above says
it must own — its own scan and its own tree — and with the gate that
makes both safe to build on.

**A second lexer in one repository is a second chance to drop a byte**,
and this repository's first lexer drops six of them: `[`, `]`, `,`,
`#`, `@` and backtick fall through `stepToken`'s final `(+ pos 1)` with
no token and no error. For a compiler that is a wrong program; for a
formatter it is a deleted one. So `fscanCovers` is a property rather
than a test: every token and every comment covers a byte range, and
everything between those ranges must be whitespace. Nothing can be
dropped without failing it and nothing can be invented either, and it
lives in the module so that `fmt` itself can refuse rather than print
around a byte it did not understand. An unclassifiable byte becomes an
`FT_ERROR` token, which is the same refusal one level down.

**The tree keeps every token**, which is the point of having one. Its
one subtlety is that `a.b` and `Mem::f` are three tokens each and one
form: left unjoined they sit as siblings inside their enclosing group
and hand it two extra elements, so `(g x.y)` would print as an
application of three things. The join is on **adjacency** — the tokens
have to touch — which is exactly what tells `Mem::memAlloc` apart from
a trait method's `show :: (-> a Int)`, where the same `::` separates a
name from a type with spaces around it. Two probes for the two
readings, both in the case below.

`tests/selfhost/880-format-scan.ax` pins all of it through both
compilers, on a source written to contain what is easy to lose: a block
comment, an AXTAG, brackets, a comma, a quasiquote with an unquote and
a splice, a character literal, a string containing both a semicolon and
an escaped quote, `-5` and `(- 5)`, and a field access. It also
requires the reader to REFUSE an unclosed group and a mismatched
closer, because a formatter that guesses at either re-nests the file
silently.

It joins `check-stdlib-selfhost.sh`'s stage0-cannot-build list for the
same reason `270-lex` and `840-large-lex` are on it: the case imports a
self-hosted compiler module, which stage1 resolves and stage0 does not.
`check-self-host.sh` is what covers it, against its `; expect 42`.

### The formatter's back half: the same function, measured

`stage1 fmt` exists, and the exit criterion above is met on everything
measurable today: **all 194 `.ax` files in the repository format to
byte-identical output with identical exit status under both
compilers**, `--check` agrees file-for-file on the unformatted
originals, the zoo formats to the checked-in golden three ways
(`golden == stage0 == stage1`), and a 33-case parity bank of
deliberate refusals and rewrites - unbalanced groups, bad escapes,
i64-overflowing literals, keywords in expression position, fused
constructor patterns, `newtype`, `--check` in both argument orders,
an empty file (formats, exit 0) versus a missing one (refuses) -
agrees case-for-case. `scripts/check-fmt-selfhost.sh` is the gate, in
CI, with counted floors on both sweeps; its negative test was run,
not assumed: ablating one normalisation (`Integer` printed verbatim)
fails the zoo comparison and the corpus sweep, and the restored file
was byte-compared back.

The printer was written from measurement, not from `fmt.rs`'s
apparent intent, and the difference bought most of the parity. Every
uncertain shape was probed through the real stage0 binary before the
matching arm was written, and the probes found stage0 behaviours no
reading would predict, all now reproduced bug-for-bug because the
criterion is bytes, not taste: the broken-application branch prints
its arguments with **no newline between them** (`(f 1 2 3 4 5)` with
five arguments becomes `(f\n  1  2  3  4  5\n))`); `cond`'s `(else `
keeps a trailing space before its newline; a comment sitting between
an AXTAG and its declaration is emitted *above* the AXTAG; AXTAGs
before an `(import ...)` are collected and silently discarded; a
zero-constructor `data` loses its `deriving` clause; and `EInfix`
exists in the AST only as the unary-minus desugar - `(a + b)` is an
application of `a` to `+` and `b` that happens to print back as
written, so the printer needs no infix case at all.

The probes also found dead code wearing living syntax, where the
right move was refusal: `,@` splice has an AST node, a parser arm and
a printer arm, and no lexer that produces it - `,@c` is "expected
expression, found `@`" in every position - and `(* mut T)` prints
from a `TPtr` mutability no parse can construct. stage1 refuses both,
which is what stage0 in fact does, whatever its source suggests it
would do.

A three-lens adversarial critique of the plan ran before the printer
landed (the standing practice), and its judge confirmed 21 changes,
several of which no test would have caught before the gate existed:
`EQualified` is not simple, so `(Q::Inner::only 1)` breaks across
four lines while `(p.x 1)` stays inline - the committed
`isSimpleForm` had it wrong; a bare uppercase identifier fuses with a
following paren group in *pattern* position (`(match v (C (h t) 1))`
means `((C h t) 1)`, and `(match v (Nothing (g 1)))` is a refusal
because the fusion swallows the arm's body); effect lists print
semantically, so `(handle n (mut) 0)` comes back `(Mut)` while
`(alloc)` refuses - the keyword has no effect-list token where the
identifier `Alloc` does; block comments nest, against this document's
own earlier claim; stage0 skips any Unicode whitespace, so the scan
now does too (probed with a NBSP); and the lexer parses every integer
through an i64 *before* any sign applies, so `9223372036854775807`
formats and `-9223372036854775808` refuses.

What stays deliberately unmatched is recorded in the gate's header:
stage1 refuses a few shapes stage0 rewrites - `(- -5)` (stage0 emits
`--5` through its two-token minus lexing), a bare top-level `- x`
body, spaced chains (`p . x`, `X :: y`), type-name keywords in
expression position - every one a refusal with the file untouched,
every one absent from the corpus, none in the parity bank.

The residual asymmetry of the whole exercise: stage0 formats from its
AST after a real parse, stage1 from a form tree after a scan, so
stage1's refusals are structural (a shape no printer arm accepts)
where stage0's are grammatical. The `bad`-flag mechanism - any
printer arm that meets a shape stage0's parser would refuse poisons
the buffer, and the driver then refuses to write - is what makes the
two kinds of refusal answer with one exit status, and the corpus,
zoo, and parity sweeps are what keep the claim honest.

### symbols: the fourth tool, and what porting it dislodged

`stage1 symbols` emits AXSYM at byte parity: **all 196 `.ax` files in
the repository produce identical stdout with identical exit status
under both compilers** - including the 49 deliberately-broken
fixtures, where both sides refuse with an empty stdout and exit 1
(`symbols` folds every failure into 1, parse errors included, where
`check` answers 2) - and `--builtins` agrees byte-for-byte on all 150
builtin rows, whose registration order stage1's `tcNew` had already
copied from stage0 without knowing it would one day be printed.
`scripts/check-tools-selfhost.sh` sweeps it live and two-sided (a
cached golden went stale four times during the port; the gate runs
stage0 fresh), floor 150, from a work directory with deliberately no
`stdlib`/`self_host` entries - stage1 keeps a legacy CWD-relative
search the compile harnesses depend on, and a salted directory would
let it resolve imports stage0 cannot, breaking refusal parity in the
direction that flatters it. The negative test was run: forcing every
nid variant to `DFn:` fails 42 checks.

The `@nid` needed a decision before a line of the port: stage0 hashed
`DVariant:name` through Rust's `DefaultHasher`, whose algorithm std
documents as unspecified - a "stable node ID" stable only until a
toolchain upgrade, and a port that matched it would chain this
compiler to std's internals. **stage0 moved to FNV-1a 64** (nothing
consumed the old values; the two constants specify the whole
function), and stage1 carries the same four lines. The nid's key is
the LAST declaration variant naming the symbol - probed, `(:: f ..)`
then `(fn (f ..))` hashes `DFn:f` while the reverse order hashes
`DSig:f` - and a signature-then-foreign pair emits TWO rows, an `F`
and an `X` at the same span with the same nid, both reproduced
bug-for-bug.

What the port dislodged outside itself is the longer list, because
`symbols` is the first consumer to push the zoo and the whole corpus
through stage1's PARSER and CHECKER rather than its formatter:

- **Import order**: stage0 resolves ALL of a module's imports before
  any of its own declarations, at every level; stage1 spliced each
  import at its source position. Every file with its imports at the
  top agreed - nearly all of them - and `Sys.ax`, with a mid-file
  `(import Mem)`, listed its functions in a different program order.
  stage1's resolver now hoists, which changes the program-wide
  declaration order and held every gate.
- **Imported modules lost their AXTAGs**: the import path parsed with
  `parseModule`, not `parseModuleWith`, so no imported declaration
  carried its tags - `#effect=io` was missing from every stdlib row,
  and every tag check on imported code had silently never run.
- **`type` and `trait` declarations are now parsed**, not skipped
  into inert nodes (names, tyvars, alias targets, method signatures -
  enough for `A` and `T` rows), and `deriving`, multi-expression
  `fn` bodies, and `(fn f = 7)` all parse - each a form the corpus
  never wrote and the zoo carried, refused by stage1 the first time
  the zoo met its parser.
- **`[` and `]` are tokens now.** The compiler's lexer skipped them
  silently, so `[(Box Int)]` arrived as `(Box Int)` and a list-typed
  signature rendered without its list-ness - a skipped delimiter is
  not a smaller token stream, it is a different program. The type
  grammar reads `[T]`; a bracket in expression position is now a
  parse error rather than an invisible deletion.
- **`(mut counter : Int)` struct fields parsed as a field named
  `mut`** with a wildcard type; the marker is now skipped as stage0
  skips it.
- A latent collision class in the tooling itself: an alias's `=`
  lexes as an identifier, and the data-declaration tyvar collector
  accepts any not-uppercase ident - so it swallowed the `=` as a type
  parameter and every alias fell back to the inert skip. Alias
  tyvars now require a lowercase letter.

Two divergences are recorded OPEN rather than closed: an imported
`type`/`trait` keeps its bare name (mangling covers `fn`/`sig` only),
so a same-named entry alias would collide in the span maps - no
corpus file does this - and effect-operation rows for a module
importing an effect rely on the `$`-prefixed duplicate being
suppressed at emission rather than never registered.

### The human renderer: native by decision, cross-checked by construction

The fifth tool surface was the human diagnostic renderer, and it is
the first port that is deliberately NOT a byte-clone - a decision
with the same shape as replacing the phase-4 criterion, and worth its
paper trail.

What the probe found (2026-08-07): stage0's `render_human` is
seventy-five lines of adapter over the third-party `ariadne` crate
(v0.4.1). All layout - the box drawing, the gutter, the label
placement, the coloring - is ariadne's. The output writes ANSI
escapes even when piped, wrapping **every snippet character
individually** in its own color sequence; and ariadne keeps only the
last `with_help`, so stage0's human output **silently drops every
help but one** - the `run axiom explain` pointer appended at render
time. The AXDL line for `AX3006` carries `?"rename one of the
definitions, or remove the duplicate"`; stage0's human report has
never shown it. Byte-cloning that renderer would have meant
reimplementing a retiring dependency's incidental escape stream,
bug-for-bug, in the compiler that outlives it.

So stage1's human renderer (`self_host/render.ax`) is Axiom's own:
rustc-flavored, `error[AX3006]:` headings, char-counted columns (the
em-dash cases pin col 22 where a byte count says 24), labeled lines
in source order, every help rendered, and stage0's trailer
reproduced exactly - `compilation failed due to N previous
error(s)`, errors only, post-suppression. `--diagnostic-format`
accepts stage0's full alias set with stage0's fallback warning, and
`human` is now stage1's default as it is stage0's; every gate that
wants AXDL says so explicitly.

**Both deltas recorded here have since been closed** (2026-08-09),
and the layout has caught up with what a report should say:

* the renderer is COLOURED, always, including into a pipe - stage0's
  behaviour, and the escapes are in all 56 `.human` goldens so the
  bytes a user sees are the bytes a gate checks. Not ariadne's
  per-character stream: whole lexemes only, from a palette declared
  in `self_host/style.ax` that the gate reads to decide whether an
  escape is one the compiler may emit. Byte 27 is synthesised at run
  time, because Axiom's lexer accepts no `\e` escape and `"\e[1;31m"`
  is AX1005 from the compiler's own front end.
* the primary label is STORED and printed, after the carets, which
  is what the JSON's `"label":""` was the visible half of. It also
  reaches AXDL, as `#"..."` - a field stage0 never printed - so the
  gate derives the caret row's label from a machine-readable
  counterpart rather than trusting the golden alone.

The JSON renderer rides along with the same fields plus `expansion`,
and has goldens of its own now: `tests/diagnostics/NAME.json`, with
every field reconstructed from `NAME.axdl` and the fixture by
`verify-json.py`. It had no gate at all before that.

The gate (`scripts/check-render-selfhost.sh`, in CI) pins a native
surface the only way one can be pinned - three-way against checked-in
goldens - and then refuses golden vacuousness with checks the goldens
cannot satisfy by being wrong consistently: every code and every
primary `file:line:col` on the case's AXDL golden (which stage0
itself byte-equals, three-way) must appear in the human golden, one
heading per AXDL line, the trailer counting exactly the E lines,
and - derived from the AXDL span rather than trusted to the golden -
a caret row at exactly the span's column and character width, plus a
dash row for the related span. stdout is compared as its own stream
(stage0's check prints `OK` whenever it does not fail), and exit
status must equal stage0's per case. Two ablations were run. With
the caret row deleted from `labelBlock`, every case fails at the
byte comparison. With the caret column shifted one right AND the
golden re-blessed from the shifted renderer - the golden-vacuousness
scenario, where the byte comparison is satisfied by construction -
the layout assertions still fail it: `no caret row at col 6 width 4
for span 3:6-10`. Restored, 38/38. The count floor is 38; the differ
is negative-tested in the gate itself.

Widening the surface found two pre-existing divergences, both
invisible to the AXDL gate because it compares bytes and not
statuses, and filters to `^[EWNH] ` lines besides:

* **a warnings-only file exited 1 under stage1 and 0 under stage0**
  (probed on `330-axtag-mismatch`). `compileFile` now refuses to
  continue only for errors: warnings print and the build proceeds,
  which is stage0's rule;
* **stage0 prints the failure trailer in `ai` mode too**, and stage1
  never had - the gate's grep was silently discarding stage0's
  trailer before every comparison. stage1 now prints it in every
  format, and `check-diagnostics.sh`'s stage1 invocations pass
  `--diagnostic-format=ai` explicitly, with a comment on why the
  sweep goes blind without it.

What remains of the tool surface for P5 is the REPL.

The adversarial review of this port (three lenses and a judge, run
while the implementation was in flight) confirmed the design and
found what the corpus could not:

* **stage1 ordered errors before warnings; stage0 renders all
  warnings first** (`warnings.chain(errors)` at the CLI print site).
  No corpus case mixed the two severities, so the AXDL gate had
  nothing to compare - the first mixed file showed E-before-W under
  stage1 and W-before-E under stage0. Fixed with a stable
  warnings-first partition applied before rendering, and pinned by
  `370-mixed-warning-error`, whose trailer also pins the
  errors-only count.
* **`check` prints `OK` on stdout** - on success and on
  warnings-only files, in every diagnostic format. stage1's check
  printed nothing; it now matches, and the render gate compares
  stdout as its own stream.
* **CI's push trigger named a branch that does not exist** - `main`,
  in a repository whose only branch is `trunk`. Every push since the
  workflow existed ran nothing; the gates were green only on pull
  requests and local runs. The trigger now names `trunk`.

Three divergences were recorded OPEN as named follow-ups rather than
silently absorbed. All three are now closed:

* ~~**the parse/lexer error path**~~ - DONE (2026-08-08, commits
  `61ed4e8` and `8218a9b`): the parser carries real diagnostic
  objects, the corpus gained fourteen `.axbad` cases covering
  AX1xxx and AX2xxx, and exit 2 became exit 1. AX2005
  (`recursion-limit`), the last code that path could not emit, was
  the final piece - it had been a bare refusal because "the parser
  carries no diagnostic payload", which stopped being true here.
* ~~**`symbols`' stdout default**~~ - DONE (2026-08-09): bare
  `symbols` prints the aligned table again and `ai` still gives
  AXSYM. The table is DERIVED from the AXSYM text rather than
  rendered separately, so the two cannot disagree about what the
  symbols are, and the gate reconstructs every row from the AXSYM
  golden rather than from the table's own.
* ~~**`AX5001` (cannot-resolve-import) as a diagnostic**~~ - DONE
  (2026-08-08): stage1's resolver now emits `E AX5001 <import>:-
  module-not-found` with a help listing every candidate filename and
  every directory its search actually visited, renders it in the
  chosen format - the first real exercise of the spanless human
  path - and exits 1, stage0's code; the old exit 3's only two
  consumers were gates, both updated in the same commit. The
  imagined "spanless corpus case" turned out to be impossible BY
  CONSTRUCTION and the pin is structural instead: the help's paths
  are each binary's own search list, so two differently-located
  compilers legitimately emit different bytes, and
  `check-self-host.sh` asserts the code, the module name and the
  search text rather than a golden.

### The REPL: the last tool, and the bug only it could find

The sixth and final tool surface was the REPL, and its port closes
the P5 tool list: every command stage0's binary answers, the
self-hosted compiler now answers too.

The parity target is the piped surface - stage0 writes no prompt
off-TTY, the `colored` crate suppresses its escapes, and every line
lands on stdout with stderr empty - which is exactly the surface the
stage0 integration tests drive, and the roadmap's own doctrine for
testing an interactive tool. The policy was decided per-behavior
BEFORE any golden was blessed: byte-identity for everything
deterministic (all scalar result types including Float's bit-pattern
print, declaration OK lines, `type :` lines, semantic error texts,
the colon-command surface with stage0's advertised-but-unreachable
`?` alias reproduced by reproducing the dispatch, comment and blank
handling, `:quit`'s no-Goodbye exit); marker-pinned shape for the
rest (`:time`, which stage1 answers honestly until a clock primitive
exists; `:llvm`, where each compiler prints its own IR by phase-4
decision; `:defs`; and stage0's leaked `_fn_0` type variable under
redefinition - the whole redefinition session is byte-identical
BUT that one line, down to the same `Error: duplicate definition`
from the eval, and the leak is a stage0 internal the port does not
clone).

Evaluation is stage0's design re-expressed through stage1's own
machinery: declarations accumulate as source; expressions type
against a fresh check (imports deliberately unresolved, so
`(println "x")` is an undefined variable at the prompt in both
compilers - bug-for-bug); the wrapper module is stage0's template
verbatim; stage1's own emitResolved lowers it; the driver's llc/cc
invocations assemble it; the child's stdout is captured through
`sh -c "exec PROG > OUT"` because Darwin's posix_spawn
file-actions descriptor is not a documented shape. `sysGetPid` (new,
per-target syscall numbers in the Platform modules) suffixes the
scratch files so two sessions cannot collide.

The port found what nothing else could have: **a string whose
closing quote is the last byte of the input lexed as `TK_ERROR`**.
`scanStringEnd` answered a bare position both for "closed" and
"unterminated" and the caller inferred termination from `ep < len` -
true for every string in every module file, where a `)` or newline
always follows, and false for the first thing the REPL fed the
lexer: a line that IS a string. The contract now distinguishes the
two (negative-encoded stop position), and the fix is pinned by the
literals session in the bank. A new consumer is a gate-widening
event, sixth occurrence.

`scripts/check-repl-selfhost.sh` runs 12 sessions (floor 12), 9
byte-identical three-way against checked-in goldens, 3
marker-pinned; exit codes equal and stderr empty required on every
one; stage0 runs with HOME redirected so its history file never
touches the user's; the differ is negative-tested in-gate and the
`type :`-line ablation was run (9 sessions fail; 12/12 restored).

Deliberate divergences, recorded: no rustyline (plain line reads;
piped surface identical, TTY sessions plainer - the editor-grade
interface is the LSP's), stage1's own banner (never compared;
--no-banner in every gated session), `:time` printing stage1's own
duration spelling from `sysNowMicros` - the clock primitive landed
the same day, verified 400,000 reads with zero backwards steps on
darwin-aarch64, its Linux numbers first executed by the REPL gate
on the CI runner - rather than Rust's Duration debug format, and
`:defs` listing the
session's own definitions rather than stage0's builtin table render,
and `Parse error:`/`Lexer error:` message BODIES, which are stage0
Display internals no artifact pins - the bank's error sessions pin
stage1's texts as their own contract.

### The language server: the first surface with no stage0 to copy

Every tool port before this one had a reference implementation to
reproduce: `fmt`, `symbols`, `explain`, the human renderer and the
REPL all exist in the Rust compiler, so "done" meant a two-sided
differential and the only argument was which divergences were
deliberate. `axiom lsp` has no such other side. The Rust compiler has
no language server, so the self-hosted one is not a port; it is the
first thing this compiler does that its predecessor cannot.

**The frontend was already library-shaped, with exactly one
exception.** §4.6 of the roadmap argues the server should reuse the
frontend rather than reimplement parsing, and the reuse turned out to
be almost free: `parseModuleWith`, `resolveImports`, `checkModule` and
`orderDiags` all take values and answer values, which is how
`repl.ax:500` already drives them on an in-memory string. The
exception is import resolution. `resolveImports` reaches
`parseModuleOrDie`, which on a module it cannot read renders AX5001
and calls `sysExitWith` (`codegen.ax:1250`). That is right for a
compiler, whose next act would be to fail anyway, and fatal for a
server: a user halfway through typing `(import Fo` would kill the
session, and the editor would report a crashed server rather than a
typo. So `lspPreflight` walks the import graph first, by
`TAG_D_IMPORT` node exactly as `resolveDeclsPhase` does, and answers
the first unreadable module's name instead of exiting; resolution runs
only once every module is known to be readable. Fixture
`040-missing-import.ax` pins it: the server publishes AX5001 and stays
up.

**Positions are a third unit.** stage0's spans are character indices,
stage1's are bytes (diag.ax says so at length), and LSP wants UTF-16
code units. `lspChar` converts from a byte offset directly, counting
two units for a code point at or above U+10000 and one below. The
three units agree on ASCII, which is why this needs a deliberately
hostile fixture rather than a corpus: `030-utf16-columns.ax` puts
`"é😀"` on the same line BEFORE the undefined name, where the byte
column is 23, the character column 20 and the UTF-16 column also 20 -
so the fixture discriminates bytes from the other two, and stage0's
own character column plus the source text derives the expected answer.

**The gate caught itself being vacuous, which is the point of running
the drill.** The first version compared, per fixture, the set of
(severity, code, line) pairs the server published against the set
stage0's `check --diagnostic-format ai` reports. Ablating `lspChar`
to a byte count and RE-BLESSING every golden from the ablated build -
the mandatory native-surface drill - passed **7 of 7**: the golden
half was satisfied by construction, and the derived half never looked
at columns. The comparison now carries the column, converted from
stage0's 1-based character index through the fixture's own bytes. Re-
run: `030-utf16-columns` fails with `server 23, stage0 20`, exit 1;
restored, 7/7, exit 0. A gate written to catch X routinely catches Y
instead, for the second time in this document.

The same drill found a second defect, in the harness rather than the
server. Goldens are path-independent because the document's absolute
URI is replaced by a placeholder - and the first version did that
substitution on the raw byte stream, leaving every `Content-Length`
header claiming the pre-substitution length. The goldens' frames did
not parse, and two runs made the same way still compared equal, so
nothing showed until the fixtures moved from a scratch directory to
`tests/lsp/` and the path got shorter. The bodies are now
re-framed with recomputed lengths and are otherwise passed through
byte for byte, so the golden still pins the server's exact JSON.

**Measured.** `scripts/check-lsp-selfhost.sh`: 7 fixtures (floor 7),
each a fixed session - initialize, initialized, didOpen,
documentSymbol, an unsupported request, didClose, shutdown, exit -
compared byte-for-byte against a checked-in golden and fact-by-fact
against stage0. stderr required empty, no unframed trailing bytes,
exit 0. The server built by stage0 and the server built by stage1
produce byte-identical protocol streams (1,156 bytes over a
three-message session, both exit 0, both stderr empty). Adding
`lsp.ax`, `Json.ax` and `Rpc.ax` moves one self-compile's peak RSS
from 176.8 MiB to 187.0 MiB, against `check-bootstrap.sh`'s 400 MiB
ceiling.

**What it speaks, and what it does not.** The lifecycle, full-text
sync (`textDocumentSync: 1`), `publishDiagnostics` and
`documentSymbol`. Not hover, not completion, not definition: those
need type information at a position, and `typecheck.ax` does not
retain a node-to-type table - that is a real new mechanism and it is a
later slice, not a half-done one here. Diagnostics for IMPORTED
modules are filtered out (`unit != 0`) rather than published against
the open file's URI, where their offsets would index the wrong text.
And a file that does not parse gets one AX2003 at the top rather than
a positioned error, because stage1's parser still carries no
diagnostic payload - the parse-error port is the slice that fixes it,
and until it lands the gate exempts unparseable fixtures from the code
comparison and asserts only that both sides refuse.

**Two supporting modules, both new.** `stdlib/Json.ax` is a parser and
serialiser over a three-word tagged record rather than a `data`
declaration (every constructor with fields boxes anyway, so an ADT
would cost the same allocation and add a `match` to every accessor).
Numbers keep their raw text beside an integer value, so a fraction is
never silently truncated while no float path goes untested; objects
are parallel vecs written by one lockstep helper; the serialiser sums
lengths and copies once rather than left-folding `strConcat`, the
shape that cost 16.9 GB. `stdlib/Rpc.ax` is the base protocol's
framing, and is buffered because `IO.readUpTo` performs one `read`
and a pipe hands over whatever the writer flushed - the header,
terminator and first body bytes routinely arrive together, and the
rest in several more reads. Both are pinned by 53 assertions that run
byte-identically under compilers built by stage0 and stage1, and the
framing is driven over a real pipe with a message deliberately torn
mid-header and a body split across three writes.

**And the honest limit: one edit costs 198 KB that is never returned.**
The server is a long-running process on a bump allocator with no
`free`, which is the case §4.1 of the roadmap exists for, so the
question is not whether it leaks but how fast. Measured directly —
N `didChange` notifications carrying `self_host/diag.ax` (16,432
bytes), peak RSS from `/usr/bin/time -l`:

| edits | max RSS | bytes/edit |
|---:|---:|---:|
| 1 | 2,523,136 | — |
| 10 | 4,030,464 | 167,481 |
| 50 | 12,517,376 | 203,964 |
| 200 | 41,975,808 | 198,255 |

Linear, ~198 KB per edit of a 16 KB document: one re-parse and
re-check, retained forever. A short session is fine; an eight-hour one
at a modest one edit per second would ask for about 5.7 GB. So the
language server is usable today and is not yet shippable, and the
thing standing between the two is P2 — which is what the dependency
graph in §1 of the roadmap already claimed, now with a number behind
the edge rather than an argument.

The shape of the fix is unusually clear here, and worth recording
before the P2 slice is designed around something else. An LSP
request's working set is genuinely dead when the request ends: the
AST, the diagnostics and the type state for version N are unreachable
once version N+1 arrives. That is precisely the watermark-and-reset
case, without the aliasing obligation that makes the general problem
hard — nothing from the previous check is retained across the
boundary except the document text, which the store owns. `Mem.ax`
already notes that the allocator is replaceable (`define axiom_alloc`
and the backend defers to it), so this need not wait for full arena
inference.

### What a quality pass found the day after, and why the gate had missed it

Two real defects, both in code the language-server gate had signed off
on, and both found by re-reading rather than by any test — which is the
argument for the re-read.

**A message larger than the reader's buffer was silently dropped.**
`Rpc.ax` held ABSOLUTE buffer offsets across a fill, and a fill may
compact: `rdCompact` slides the live region to the front and resets
`consumed` to 0, so an offset taken before it is stale by the old
`consumed` afterwards. The symptom was not a corrupted body but a lost
message — the reader mis-sliced, saw a short body, answered `""`, and
the server read that as the client hanging up and exited. Measured on
an echo of two messages: a 60,000-byte body round-trips, a
100,000-byte body loses the message entirely. The buffer is 64 KiB and
`self_host/codegen.ax` is about 150 KB, so an editor opening the
compiler's own source would have hit it on the first file it read.

It needed two conditions at once — a body bigger than the free space,
and a non-zero `consumed`, which means it cannot be the first message
— and every fixture in the gate is a few hundred bytes. Offsets are
relative to `consumed` now, which is invariant under compaction, so
the question cannot be got wrong again. `rpcRead` also answers a
`strDup` rather than a `strSlice`: a slice shares the reader's buffer,
and the next compaction memcpys within that same allocation, so a body
handed to a caller — or any substring the JSON parser kept of it —
would change underneath them later. The regression is a generated
177,817-byte document sent as the SECOND message with a deliberate
error on its last line, followed by another request; it checks that
the diagnostic lands on line 12,001, that the outline has all 6,001
symbols, and that the stream is still in sync afterwards. Ablated back
to the shipped bug: that case fails with zero diagnostics while all
seven small fixtures still pass.

**The most-negative integer guard was the exact mistake `Fmt.ax`
documents having made.** `jsonIntStr` refused
`(- 0 9223372036854775807)` — which is one GREATER than the most
negative `Int`, so the guard never fired on the value it was for, and
mis-rendered its neighbour as `-9223372036854775808`. The most
negative value itself fell through to `jsonNatStr (- 0 n)`, where
negating it yields itself and the digit lookup walks off the table:
it rendered as `-0`. `Fmt.ax` carries a paragraph about making
precisely this mistake and fixing it with `intIsMostNegative`, three
lines from where this file re-made it. `Json.ax` cannot import `Fmt` —
probed, `AX3014 ambiguous name 'fmtInt': defined in codegen, Fmt`,
because `codegen.ax` carries its own copy and the namespace is flat —
so it carries the predicate rather than the literal.

Both now have a gate that could have caught them, and neither did
before: `tests/stdlib/340-json.ax` is 54 assertions run by BOTH
compilers through `run-stdlib-tests.sh` and
`check-stdlib-selfhost.sh`, covering the integer boundaries, the
escape set, surrogate pairs, ten malformed inputs and round-tripping.
Ablated back to the literal guard, it fails two cases with
`got=-9223372036854775808` and `got=-0`.

The pattern worth keeping: **the LSP gate tested the protocol, and
both bugs were in the layers underneath it.** A gate on a composed
surface exercises its dependencies only along the paths that surface
happens to take — small ASCII messages and small integers — and
reports their silence as agreement.

### The nesting limit: stage1 accepted what stage0 refuses, then crashed

`AX2005` — `nesting is too deep (limit is 1024)` — had no site in the
self-hosted compiler and no depth counter anywhere behind it. The
consequence was two divergences rather than one, and the milder-looking
one is the worse:

| nesting | stage0 | stage1 (before) | stage1 (now) |
|---:|---|---|---|
| 5,000 | exit 1, `AX2005` | **exit 0, checks clean** | exit 2, refused |
| 20,000 | exit 1, `AX2005` | **exit 0, checks clean** | exit 2, refused |
| 100,000 | exit 1, `AX2005` | **SIGSEGV (signal 11)** | exit 2, refused |
| 300,000 | exit 1, `AX2005` | **SIGSEGV (signal 11)** | exit 2, refused |

A crash is loud. Accepting a program the other compiler says is not a
program is not: stage1 type-checked a 20,000-deep expression clean and
would have gone on to emit code for it.

**Counted over the token stream, not threaded through the parser.**
Sixty-odd `parse*` functions would each need a depth parameter
otherwise, which is the parse-error port's shape of work and not this
slice's. A nesting level in this syntax is a delimiter, so
`maxNestDepth` walks the tokens once counting `(`/`{`/`[` against
`)`/`}`/`]`, floors at zero so a stray closer cannot mask real depth
after it, and `parseModuleWith` refuses before `parseDecls` is called —
before, that is, the call whose stack exhaustion is the failure being
prevented. It is deliberately not exact agreement with stage0's
counter, which counts parse recursion; the two coincide on every
nesting form the grammar has, and where they might not, both compilers
still refuse.

**The limit does not touch real code.** The deepest `.ax` file in the
repository is `self_host/format.ax` at 37, against a limit of 1024 —
28× headroom, measured over all 211 files.

What stage1 still does not do is *say* `AX2005`. The parse-error port
since gave the parser a diagnostic channel and a real exit status, so
this is no longer a bare `parse failed` with exit 2 — it is a spanned
`AX2003` syntax error with exit 1, the same status stage0 gives.
Measured on a 2,000-deep file: stage0 says
`AX2005 deep.ax:2:1036-1037 recursion-limit`, stage1 says
`AX2003 deep.ax:1:1-2 syntax-error`. Both refuse with the same status
now; what is left is the code and a span at the offending depth rather
than at the first token, since the guard reports position 0. That is a
small follow-on now that the channel exists.

The gate is a refusal-parity case in `scripts/check-diagnostics.sh` at
the depth that used to **crash** rather than the depth that used to be
accepted, so it pins both halves, and it checks the exit status against
128 as well as against 0 — a signal death is not a refusal. Ablated
(limit raised out of reach), it reports
`stage1 died of signal 11 on 100000-deep nesting instead of refusing`
and exits 1.

### The language server stopped growing, and what that cost the allocator

The LSP's first slice was gated and correct and leaked 3.4 MB per
keystroke. That number is the roadmap's §1 dependency edge with
evidence attached: the server reuses the compiler's frontend, so every
`didChange` re-parses and re-checks the document, and on a bump
allocator that never frees, every one of those re-checks was retained
for the life of the process. Measured on a 16 KB file: 8.3 MB after one
edit, 39.5 MB after ten, 693.7 MB after two hundred.

Fixing it turned out to be three findings deep, and only the first was
the one I set out to fix.

**A reset stranded every chunk mapped after the mark.** A mark saved
the waterline and the chunk end, which is enough to restore a position
and nothing else: chunks mapped after the mark were simply forgotten.
A loop that marks, allocates 1.5 MiB and resets measured 576 KiB of
growth per iteration — the *same linear shape* the memory model exists
to remove, one level below where the roadmap was looking for it.
Chunks now carry a two-word header and form a list; a reset walks it
back to the marked chunk and moves what it passes onto a free list the
next refill fits from. Same loop, 2.9 MiB, flat through 1,000
iterations.

**Reclaimed memory came back dirty, and four modules had been told it
would not.** `Mem.memAlloc` documents that it returns zeroed memory.
Fresh pages arrive zeroed from the kernel, so that held for free until
a reset handed the same bytes out a second time — after which
`strAlloc 3` produced a string whose `cstrLen` was 17, because
`strAlloc` reserves a byte for its NUL terminator and never writes one.
`Map` and `Intern` read an all-zero state array as "every slot empty".
So the explicit contract that landed in the previous memory commit was
unsound against the standard library from the day it landed, and its
gate could not see it, because the Life probe writes every slot it
reads before reading it.

The fix is a per-chunk high-water mark, with the scrub on the
allocation rather than on the reset. That placement is the interesting
part, and I got it wrong first: scrubbing at the reset is the obvious
reading of "hand back clean memory", and `check-memory-baseline.sh`
failed it on the first run with the managed population at 0. The reason
is that §4.1's copy-at-boundary reads the value it is copying *out of
the region the reset just reclaimed* — a reset that scrubs destroys the
thing the caller is trying to keep. A reset writes no byte of what it
reclaims, and that is now a stated property.

**And then copy-at-boundary turned out not to be expressible.** With
the allocator fixed, the LSP's boundary should have been: snapshot the
live state, reset, copy it back down. It is not, and the reason is
exact. The copy's destination is allocated *after* the reset, so it
comes from `axiom_alloc`, so it is scrubbed on the way out — and when
the kept block is bigger than the garbage around it, that scrub runs
over the source before the copy reads it. That is not a corner case,
it is the normal case for a server: a 150 KB document and a 200-byte
request. Probed at 40 KB kept across a 64-byte allocation: **39,841 of
40,000 bytes wrong on the first round**. The Life probe never showed
this because its live set is constant and its garbage is larger, which
is the narrow condition under which the naive spelling happens to work.

So the reclaim and the copy are one primitive,
`__axiom_arena_reset_keeping`, whose destination is never handed out
through the allocator and therefore never scrubbed — the copy is what
initialises it. Its copy runs forwards, which covers both directions it
can face: within a chunk the source was allocated after the mark so
`dst <= src`; across chunks the ranges are separate mappings and cannot
overlap, which is the case to get right, because `mmap` returns chunks
in no particular address order. When the kept block will not fit in the
marked chunk's remainder the destination is a fresh mapping, never the
free list — the free list at that moment holds the chunks the same call
just reclaimed, one of which may be the source's.

With that, the server's loop marks once and reclaims after every
message, carrying the document store and the reader's unconsumed bytes
across as one block. 693.7 MB → **6.8 MB at 200 edits, flat**; a
two-document session with interleaved edits, outline requests, closes
and reopens sits at 6,816 KiB at 4, 12 and 60 rounds where the old
build climbs to 248 MB, and the protocol stream is byte-identical.

The gate is the shape this project keeps arriving at. RSS alone cannot
tell reclamation from a server that died on message three, and a dead
server is *very* flat — so both the 5-edit and the 200-edit session
must publish diagnostics for every edit and answer their shutdown
before the memory numbers are allowed to mean anything. With the
boundary removed, it reports 60,158 bytes per edit and exits 1.


### The ceiling this uncovered: one stack frame per source byte

Adding to `self_host/codegen.ax` broke `check-fmt.sh`, in the way this
project has recorded once before and did not recognise the second time
either: a case that passes in the repository and segfaults in the
formatted copy of it. `300-pipeline` builds a program that embeds the
frontend and reads a module at runtime, so the formatted copy makes it
read a *larger* file — formatting `codegen.ax` takes it from 215,369 to
221,940 bytes — and somewhere in that gap it died.

The diagnosis is worth writing down because it looked like three other
things first. The emitted IR was **byte-identical** between the
formatted and unformatted builds, and so was the object file, which
rules out a formatter bug and a codegen bug together. Copying the
binary into the other directory moved the failure with the
*directory*, not the binary, which says the input decides. `lldb`
could not unwind the stack at all — the frame chain is gone by then —
but dumping raw stack words showed a 64-byte frame repeating with one
field decrementing by exactly one per frame, and its value was the size
of the source. One frame per byte. The return address in that frame
symbolised to `lexer$scanAxtagsFrom`.

It is the same finding as `lexTokens`/`dispatchChar`: a walk written as
a tail call, which is free only where the compiler turns it into a
jump, and a stage1-built binary that has not been through `opt` does
not. `check-self-host.sh` deliberately runs `llc` without `opt`, so
that is exactly the binary under test. Rewritten as a `while`, its
depth is constant.

Two measurements confirm the reading, both on an imported module -
which is what reaches `scanAxtags` at all, since a module is
tag-scanned when it is *resolved*, not when it is the entry file. The
first: 400 KB of comment-free source segfaults the pre-fix binary,
while 400 KB that is almost entirely comment lines does not. That is
the shape of the recursion exactly - the `;` branch skips a whole line
per frame, and an ordinary byte costs one. The second, after the fix:
the same binary reads a 1 MB module, and 2 MB overflows somewhere else
again.

So the margin goes from *below* the real input to several times above
it. The largest module in this project is the formatted `codegen.ax`
at 222 KB, and the number that matters is the first one, because 222 KB
is where the compiler was already standing when this change arrived.

Two things to keep. **A ceiling that no file is big enough to reach is
invisible, and it is reached by ordinary growth** — nothing about the
memory-model work touched the lexer. And `check-fmt.sh` is the gate
that caught it, because a formatted copy of the repository is the
largest input this project compiles; it earns its runtime for reasons
that have nothing to do with formatting.

### The parse-error port: the payload was mostly already there

Every parse failure in the self-hosted compiler reported the same
thing: `parse failed` on stderr, exit 2, against stage0's coded and
spanned diagnostic and exit 1. It was the largest item left on the
backlog and the blocker for two other things — the language server
published one spanless `AX2003` at the top of the file for a typo
anywhere in it, and `AX2005` could refuse a too-deep file but not say
so.

The estimate said "62 `pErr` sites need a diagnostic payload threaded
through them". Measuring first changed the shape of the work
completely, in three ways.

**The position was already threaded.** `PResult` is `(ok, value, pos)`,
and `pos` is the token index where the parse gave up — so on a corpus
of twelve broken programs, stage1's span already agreed with stage0's
on *every single one*, before any of this. What was missing was the
code and the message, not the location.

**stage0 has 16 error sites, not 62,** and about twelve distinct
expectation strings between them. And its AX2001 is derived
mechanically from exactly one of them:

    E AX2001 f.ax:3:4-5 unexpected-token "expected identifier, found `)`"
                                         ?"Axiom expected identifier at this position"

Message and help both come from the noun. So a site does not need a
payload threaded through it — it needs to name what it wanted, in one
string, and everything else follows from `pos`. `PResult` grew one
field, `pErrExp` joined `pErr`, and thirteen sites were taught their
noun.

**The code is derivable, but not the way it looks.** The obvious rule —
"at end of file, report AX2002" — is wrong, and the LSP's own
unparseable fixture is what proved it: stage0 answers *AX2001,
"expected expression, found `EOF`"* there. Reading stage0 rather than
guessing gave the real rule: AX2002 comes from exactly one routine, the
one demanding a *specific token kind*, and every site that wanted a
*category* reports AX2001 even at EOF. That maps onto the same one
field — a site that named its expectation gets AX2001 wherever it
failed, and a site that did not is the specific-token case. One place
still needed stage0's grammar reproduced rather than its output copied:
an expression list at EOF wants an expression when it has parsed none
and a closing paren when it has parsed one, which is why
`(fn (main)` and `(fn (main) (+ 1 2)` get different codes.

Eleven of the twelve corpus cases are now byte-identical through both
compilers, including the two removed constructs, whose migration advice
is the entire reason `union` and `region` are still reserved words.
`scripts/check-diagnostics.sh` carries eight of them as `.axbad` cases
— the extension the LSP gate invented, because `check-fmt.sh` and
`check-tree-sitter.sh` sweep every `*.ax` and require it to parse, and
they are right to. Ablated to the previous parser, all eight fail.

One thing the new cases dislodged, which is the usual reward for
pointing a gate at a shape nothing had produced before. An
end-of-file diagnostic names a line PAST the last one - an unclosed
`(` runs out at the position after the final newline - and stage1's
human renderer treated any span at or beyond the end of the source as
spanless, so the commonest syntax error there is printed no snippet at
all. stage0 does have a line to show and shows it: its AXDL says `2:1`
for a one-line file while its report puts the caret at `1:11`, the end
of the last line. stage1's renderer clamps the same way now, and the
gate derives the clamped position from the fixture's own bytes rather
than trusting the golden - so the two halves still cannot satisfy each
other. No existing golden moved.

The twelfth corpus case is not a parse-error bug and is recorded rather
than papered over: `(:: f (-> ))` is *accepted* by stage1, because
`parseSigDecl` deliberately treats a type it cannot parse as an absent
type — "under-reported, never mis-typed". That is a tolerance with a
documented reason, and this project's own experience is that a
tolerance dies loudly when it dies; killing it needs evidence that
stage1's type grammar covers stage0's, which is its own slice.

### The lexical-error port, and the sweep that found what reading did not

The self-hosted lexer had no diagnostics at all. Five conditions stage0
refuses arrived here as silence, and two of them changed what the
program *meant* rather than merely what it reported:

| source | stage0 | this compiler, before |
|---|---|---|
| `99999999999999999999999` | AX1004 | built it, and printed `200376420520689663` |
| `"A\qB"` | AX1005 | built it, and printed `AqB` |
| `#` | AX1001 | skipped the byte |

The third is the worst of the three even though it prints nothing: a
skipped byte is not a smaller token stream, it is the token stream for
a *different program*, which is the same failure `[` and `]` produced
before `symbols` needed them.

`TK_ERROR` carries no payload. It does not need one for four of the
five conditions, because each can only begin one way — `"` a string,
`'` a char, a digit a number, anything else an unexpected character —
so `lexErrDiag` reads the code off the first byte of the span. The
fifth is the exception that earns its own kind, and it took a
measurement to see: a bad escape starts with `\`, and so does a stray
backslash outside any literal, which is AX1001. Keying off the byte
gave the stray one AX1005. `TK_ERROR_ESC` is the distinction the span
cannot carry.

**The instrument.** Reading two lexers side by side finds some of this.
What actually found it was a sweep: every one of the 94 printable ASCII
bytes, in three positions — alone, after a letter, before a letter —
through both compilers, comparing the diagnostic code. It runs in about
two minutes and it reported **7 divergent bytes of 94**, five of them
real bugs nobody had looked for:

```
byte  36 $    stage0=AX2001   stage1=AX1001
byte  44 ,    stage0=AX2001   stage1=AX1001
byte  63 ?    stage0=AX1001   stage1=AX2001
byte  64 @    stage0=AX2001   stage1=AX1001
byte  92 \    stage0=AX1001   stage1=AX1005
byte  96 `    stage0=AX2001   stage1=AX1001
byte  40 (    stage0=AX2001   stage1=AX2002
```

`,` is the one that mattered. The lexer had been **skipping the comma**,
so `(Rect { w : Int, h : Int })` arrived as `{ w : Int h : Int }` and
parsed *by luck* — S-expression fields are whitespace-separated anyway.
Nothing could see it while unknown bytes vanished; the moment the
fallthrough became AX1001, three corpus files failed at once. The
comma is now `TK_COMMA`, and the two named-field loops consume at most
one immediately after a completed field, which is where stage0 consumes
it (`axiom-parser/src/lib.rs:508` and `:909`) — skipping commas
wherever they appear would accept `{ ,, w : Int }`, which stage0
refuses.

`?` runs the other way: it was in this lexer's identifier set and has
no arm in stage0's dispatch, so every predicate-style name (`empty?`)
was a program only one compiler would take. It is out of the set.
Admitting it is a language change and belongs with the tree-sitter
grammar and the formatter, not in an identifier set that happened to be
wider.

**Two refusals of valid programs, found the same way.** A string
spanning a line break is one string in stage0 — its scan loop has no
newline case — and was refused here, because `scanStringEnd` stopped at
the newline. That was not new: a stage1 built from `61ed4e8` refused it
too, as `AX2001 expected expression, found "one`, which is why nobody
had noticed. And `'\q'` was accepted, because the char literal's width
was computed and its escape never checked. AX1002's help still says
"end of input (or end of line)"; only the first half is true of either
compiler, and banning the line break is a language decision, not a
lexer detail.

**Three divergences kept, on purpose.** `$`, `@` and `` ` `` are bytes
stage0 tokenises and no grammar rule of Axiom uses. stage1 refuses them
lexically, naming the character; stage0 carries them further and
reports something else. The evidence says the lexical refusal is the
better answer in all three:

- `` `42 `` and `,42` are quasiquote and unquote. stage0 **accepts both
  and miscompiles them**: `axiom-sema` unwraps `EQuasiquote`/`EUnquote`/
  `ESplice` to their inner expression for type checking (`lib.rs:873`,
  `:3070`) and `axiom-ir` has no arm for any of the three, so
  `(fn (main) `42)` builds cleanly and the program **exits 0**. Same
  shape as `(:: 42 Int)` evaluating to `0` — a node the checker accepts
  and the IR generator forgot.
- `$` lexes as `TokenKind::Bang`, so stage0's report for a `$` you typed
  reads ``undefined variable `!` `` and suggests `+`.

None of the five sigils (`?`, `$`, `@`, `` ` ``, `~`) occurs in code in
any of the 228 `.ax` files in this repository, so the blast radius of
all of this is zero and the sweep is the only thing that could have
found it.

After the port: **3 divergent bytes of 94**, all three the recorded
decision above. (`(` remains the separate, previously recorded
parse-error code divergence.)

**Gated.** Six `.axbad` cases in `tests/diagnostics/` — one per code
plus the char-literal escape — carry three-way AXDL goldens
(`golden == stage0 == stage1`) and six `.human` goldens whose layout
`check-render-selfhost.sh` derives from the AXDL rather than trusting.
The refusal side is only half of it, and the half a gate written this
way cannot see: `tests/selfhost/890-lexical-edges.ax` compiles and
*runs* a program built from the shapes both compilers accept — a string
spanning a line break, `'\n'`, `'\''`, and a comma between named fields
— and both compilers answer 55.

### The seed: what actually stood between here and deleting the Rust compiler

The self-hosting fixpoint has been reached for a while. `stage2` and
`stage3` are byte-identical, `stage2` builds `stage3` through its own
driver with no Rust involved, and every gate in the repository has been
run against a stage2 binary. None of that lets the Rust crates be
deleted, because every one of those ladders begins by asking the Rust
compiler for a `stage1`. Remove `axiom-*` from the tree and a fresh
clone has nothing to build with at all.

That — not any missing feature — is the critical path. It is closed by
`bootstrap/`: the compiler's own LLVM IR, one file per target,
committed.

```
bootstrap/axiom-<target>.ll   →  llc + cc  →  seed
seed  →  self_host/  →  stage1  →  stage2  →  stage3      (stage2 == stage3)
```

`scripts/bootstrap-from-seed.sh` runs that, and needs `llc` and a C
compiler on `PATH` and nothing else. It is wired into CI as
`bootstrap-no-rust`, the only job with no `rust-toolchain` step, on
both Linux and macOS.

**Measured, because the design turns on the numbers.** 2.10 MB of IR
per target; 8.38 MB for all four. The four differ from each other in
**193 lines of 61,473** — the target triple, the syscall instruction,
and the syscall numbers — so git stores them as near-duplicates. IR
rather than a binary because it is text, it diffs, and one `llc`
invocation adapts it to whatever libc and linker the host has.

**The seed is deliberately not asserted to match the source beside
it.** A seed regenerated on every compiler commit would put 8.4 MB of
generated text into every such diff, to buy the property "the seed is
exactly this source" — which is not the property a clone needs. A
clone needs *"the seed can build this source"*, and the script checks
that by doing it. A seed that falls far enough behind to stop
compiling `self_host/` fails there, naming the stage that could not do
it, and `scripts/reseed.sh` moves it forward. Go and Rust make the
same bargain with their bootstrap toolchains.

That the bargain is safe is measured rather than assumed: **a seed
generated from the previous commit's compiler builds the current tree
to a byte-identical `stage2 == stage3`.**

**The vacuousness drill, run.** Three ablations, all of which had to
fail and did:

1. one byte flipped in a seed → refused at the `SHA256SUMS` check
2. a seed that is a valid Axiom program but *not a compiler* (a
   `hello`-shaped `.ll`) → refused
3. a seed one commit stale → **passes**, which is the design claim

Ablation 2 is the one that improved the script. Its first failure read
`llc rejected the IR seed produced` — true, and blaming the wrong
file, exactly the trap `check-driver.sh` fell into when a poisoned
`PATH` proved the pipeline broke rather than that the check under test
existed. The seeded stage now has to emit something with a target
triple and more than ten thousand lines before `llc` is allowed an
opinion, and the message names the stage: `seed emitted no LLVM module
- it is not a compiler`.

`SHA256SUMS` is a corruption check and not a trust check — a hash and a
file committed together move together. Ken Thompson's attack applies
here as it does to every bootstrapped compiler; everything short of it
is answered by requiring the seed to compile the whole compiler, reach
a fixpoint, and produce a program that runs.

### `Mod::Ctor` was a false diagnostic on a valid program

`axiom explain AX3014` tells the reader to write `Module::name` when
two imports define the same name. The self-hosted compiler refused
that spelling for constructors:

```
$ stage0 check t.ax        OK
$ stage1 check t.ax        E AX3001 undefined variable `Qual$Dim`
```

A qualified reference is parsed into the flat `Mod$name` spelling the
declarations use — the parser says so, and `mangleDecl` is why it
works: import resolution rewrites every imported `fn` and `::`
declaration to `Mod$name`, so `Mod::f` resolves by matching a
declaration that has already been renamed to match it. `mangleDecl`
rewrites nothing else. A `data` or `struct` declaration keeps its bare
constructor names, so `Mod::Ctor` was parsed into a name no
declaration in the program carried, and the checker was right to say
so about the name it was given.

This is the third time that same gap has produced a false positive on
a valid program. Effect operations hit it first, and were fixed by
registering each imported operation under both spellings. Constructors
could not be fixed that way: the checker's `DataEnt` holds the
constructor list that exhaustiveness counts, so a duplicate entry
would make `AX3005` report a constructor missing that the match
covers.

**What it needed instead was for the module part to be checked rather
than ignored.** `DataEnt` and `StructEnt` now record the module that
declared them, and one comparison — `declMatches` — decides every
constructor and struct lookup: a bare reference behaves exactly as
before, and a qualified one resolves only when the declaring module is
the one named. `Box::Red` resolves; `Nope::Red` does not. In codegen,
whose type table is exact string equality over a flat vector, the same
thing is one extra entry per imported constructor carrying the *same*
tag, arity and representation — which is what keeps a constructor
reached under either spelling one constructor and not two.

**Where this is deliberately stricter than stage0.** stage0 checks the
module for data constructors and for functions, and does not for
struct constructors: `(Nope::Pt 1 2)` is accepted there, measured. A
qualified reference that names a module declaring nothing of the sort
is a typo in every case, so stage1 refuses all three uniformly. That
is the one behavioural divergence this change introduces, and it is
recorded rather than smoothed over.

**A second, smaller thing the probe exposed.** stage1's `AX3001`
quoted the internal spelling back at the programmer — ``undefined
variable `Nope$Red` `` for a line that reads `Nope::Red`, a name that
appears nowhere in the source. The message now renders the source
spelling, as stage0's does.

Still divergent, and pre-existing: the **span**. For any qualified
reference, function or constructor, stage0 anchors on the name after
the `::` and stage1 on the module before it. Both compilers refuse the
same programs with the same code and now the same message, so the
refusal-parity case in `check-diagnostics.sh` compares exit status
rather than AXDL and says why.

**Gated.** `tests/selfhost/900-qualified-ctors.ax` reaches a data
constructor, a nullary one applied, a function and a struct
constructor through `Qual::`, and runs — 42. Against a compiler built
from the previous commit it fails with the false `AX3001`, which is
the whole bug. The refusal half is a parity case in
`check-diagnostics.sh`: it is vacuous against the old compiler, which
refused everything qualified, and exists to catch the tempting wrong
fix — stripping the module part instead of checking it.

**And the ceiling it tipped over.** The alias entry is one extra row in
codegen's type table per imported constructor, which is a table
`lookupByIdx` walks linearly — and `lookupByIdx` was a recursion, so
the walk cost **one stack frame per entry**. The self tail call the IR
rewrites into a jump does not fire through the `let` that binds the
entry, so the frames were real. With the table longer, `stage2` died
of SIGSEGV compiling its own source, in the `check-bootstrap.sh` ladder
that deliberately runs `llc` without `opt`.

This is the third appearance of the same ceiling — after `scanAxtags`
and `skipLineComment` — and it presented the way it always does: an
unrelated change tipping something over, two changes needed before
anything looked wrong. `lldb` named it in one backtrace rather than by
reading: twenty-five frames of `codegen$lookupByIdx` under a
`Vec$vecGet` holding an address off the end of the stack.

`lookupByIdx` is a loop now. The alternative — requiring `opt` in the
bootstrap path, which does eliminate those frames — was rejected: the
whole argument for `bootstrap/` is that a clean checkout needs only
`llc` and a C compiler, and `axiom-cli` has always treated a missing
`opt` as a warning. A compiler that cannot compile itself without an
optimiser has a smaller set of machines it can be born on.

`check-bootstrap.sh` found this with no new gate needed, which is what
that ladder's `-O0`/no-`opt` comment has been protecting since it was
written.

---

## 8. Retiring the Rust compiler

The Rust implementation is gone. This section is what it cost, what
replaced it, and what was deliberately not replaced — written while
both compilers still existed, because most of it could not be
established afterwards.

### 8.1 What actually blocked it

Not the fixpoint, which had held for weeks. Not any missing feature.
**Nothing could build the compiler from a clean checkout**, because
every ladder in the repository began by asking the Rust compiler for a
stage1. That is closed by `bootstrap/` (§ "The seed", above).

The second blocker was subtler and is the reason this section is long.

### 8.2 A differential gate does not fail when its reference disappears

Six of the gates compared the two compilers: run both, require identical
bytes. Delete one and point `$axiom` at the other, and every one of them
still passes — comparing a compiler with itself, sweeping two hundred
files, finding nothing, exiting 0. Measured before any of them was
touched: **thirteen gates went green that way**, and that number was
briefly mistaken for good news.

So each was rewritten rather than allowed to degrade, and each now
carries at least one assertion **derived from something other than the
compiler's own output** — the property a re-bless cannot satisfy:

| gate | what replaced the comparison |
|---|---|
| `check-tools-selfhost` | every AXSYM position claim verified against the source bytes (14,123 of them), and `symbols` exiting 0 for exactly the files `check` does |
| `check-diagnostics` | every AXDL span checked against the fixture's own bytes |
| `check-render-selfhost` | expected exit status derived from the `.axdl` golden, not from another compiler |
| `check-lsp-selfhost` | the expected UTF-16 column recomputed in Python from the fixture bytes — a second implementation, in another language |
| `check-fmt-selfhost` | idempotence and reparse: format twice, require byte-identity, require the result to parse |
| `check-repl-selfhost` | each `result` cross-checked against compiling and running the same expression |
| `check-stdlib-selfhost` | a Python model of each case's expected output, derived from the source, cross-checked against the 37 checked-in `.out` goldens |

One claim in an earlier draft of this table was wrong and is worth
recording as such: the `.out` goldens do **not** predate the
self-hosted compiler in git history. The self-hosting work began at
`b32d41e` (2026-07-28) and the earliest `.out` file lands 2026-07-30,
so none of the 37 predates it. The accurate, checkable statement is
that they predate any self-hosted binary having an opinion about this
corpus: 32 of 37 are unchanged since `5f6aaaa`, the commit that added
that gate and first ran `tests/stdlib/` through the Axiom compiler.

The rule these follow: *agreeing with another implementation says two
things agree; checking the answer against the input says it is right.*
Several of the replacements are strictly stronger than the differentials
they replace, and none of them churns when a span moves.

**The drill, on the first one converted.** A compiler was built with
every AXSYM start column shifted by one, and both of that gate's goldens
were regenerated from it. The zoo golden matched. The status manifest
matched. The position verifier failed 14,100 of 14,100 claims and could
not parse 23 more. That is the argument for the derived half, measured
rather than asserted — the goldens are exactly as strong as whoever last
regenerated them.

### 8.3 Provenance, recorded while it could be

Goldens that had never been checked in were materialized from the Rust
compiler and **verified against the self-hosted one at the same commit**,
which is the last moment that comparison was available:

- `symbols`, all 216 files: **14,626 AXSYM lines identical**, and every
  exit status identical, once paths are normalised and the sweep runs
  from a directory that cannot resolve imports for the file under test.
- `explain`, every code and spelling: identical.

Both normalisations are load-bearing and both were found by the
comparison failing first. AXSYM names the file a symbol came from, and
for an imported stdlib module that path is relative to the *binary*, so
two installs disagree about a symbol neither got wrong. And the compiler
keeps a legacy CWD-relative entry in its module search, so running the
sweep from the repository root lets a fixture resolve `(import lexer)`
out of `self_host/` — which moved 4 of the 216 statuses and is a fact
about where the sweep ran.

### 8.4 What was deliberately not replaced

Recorded as this compiler's behaviour rather than fixed to match:

- **`symbols` emits AXSYM only.** The Rust compiler also had an aligned
  human table (its default) and JSON Lines. AXSYM is the notation this
  language is designed around, the human table was a strict subset of it,
  and nothing consumed the JSON. What was *not* acceptable was how it
  diverged: `--diagnostic-format` was read, used for diagnostics, and
  silently ignored for the symbol output, so `symbols
  --diagnostic-format=json` printed AXSYM and claimed success. It now
  says so.
- **Human diagnostics are this compiler's own layout**, not the
  `ariadne` crate's. Decided and gated earlier; see "The human renderer".
- **`$`, `@` and `` ` `` are lexical errors.** The Rust lexer tokenised
  them, and its quasiquote forms *type-checked and then miscompiled* —
  `(fn (main) ``42)` built cleanly and returned 0.
- **A qualified reference must name the module that declares the thing.**
  Stricter than the Rust compiler, which checked this for functions and
  data constructors but not struct constructors.
- **Parse-error codes differ on some malformed input** (AX2001 vs AX2002
  vs AX2003). Spans and exit statuses agree; only the code differs, on
  input that is refused either way.
- **`--gc` is gone, and is now refused by name.** The Rust compiler had
  it as a global boolean that swapped the bump allocator for a
  conservative mark-sweep collector — 1,098 lines in
  `axiom-codegen/src/gc.rs`, deleted with the rest of the crate in
  `430a138`. Nothing in `self_host/` replaced it, and the flag was
  neither implemented nor rejected, so `axiom --gc build …` produced a
  bump-allocator binary and said nothing. That was worse than an
  unimplemented flag: `scripts/bench-datastructures.sh --gc` was
  reporting collector numbers for an allocator binary, and README.md's
  opening paragraph and `docs/reference.md` both promised a memory model
  the compiler did not have. A silent downgrade of a memory-management
  request is precisely the failure its user cannot detect, so the flag
  is now a hard, named refusal (exit 2) and the three documents no
  longer claim it. **This is a capability loss, not a CLI decision**: if
  peak memory tracking live data matters again, the collector has to be
  written in Axiom, and that is a project, not a slice.

One divergence found during this work is recorded as a **defect, not a
decision**, because after the deletion there is no second implementation
to observe it against. At the REPL, a recursive function defined without
a `::` signature:

```
(fn (fact n) (if (== n 0) 1 (* n (fact (- n 1)))))
(fact 10)
```

Both compilers refuse it, both exit 0, both name the same internal
`_fn_0`. But this one types the call as `Int` and prints `type : Int`
first, and only the module check catches it afterwards — so it
**announces a type for an expression that then fails to compile**. The
Rust compiler caught it in the expression check and printed no type
line. With a signature present the two agree exactly. Nothing pins this,
deliberately: pinning it would bless the wrong half as the contract.

### 8.5 The citations in `self_host/`

Comments throughout the compiler cite the implementation they were
written against, by file and line: `axiom-lexer/src/lib.rs:498`,
`axiom-parser/src/lib.rs:508`, `axiom-sema/src/lib.rs:873`. Those files
are gone from the working tree, and the citations were left in place on
purpose. They are the record of *why* a behaviour is the way it is —
several of them are the only remaining evidence that a rule was
reproduced deliberately rather than invented — and they resolve at the
tag:

```bash
git show v0.1.0-rust-final:axiom-lexer/src/lib.rs | sed -n '498,545p'
```

A citation that named nothing would be worse than one that names
something you have to check out. Where a citation described a rule this
compiler now owns rather than inherits, it was repointed instead — the
tree-sitter grammar's, for one, since the grammar's obligation is to
agree with the compiler that exists.

### 8.6 The Rust test suite

286 tests died with the crates. 115 of them were end-to-end language
behaviour, and those are the only ones whose loss means anything — the
rest tested Rust internals of a program that no longer exists. The
end-to-end properties live on in `tests/selfhost/` (compile, run, check
exit status), `tests/stdlib/` (compile, run, compare output),
`tests/diagnostics/` (every code, three-way goldens), and the tool gates.

There is no `cargo test` equivalent, and no single "run all the tests"
command, by design: each gate is a script, and the script is exactly what
CI runs.

### 8.7 What the gates lost, stated plainly

Deleting the Rust compiler **irreducibly weakens** seven gates, and no
amount of rewriting undoes that. It is worth being precise about what
changed, because the mitigations are real but partial.

**Before**, a gate compared this compiler against an independent
implementation of the same language. An adversary who broke one of them
could not regenerate their way out: the other one disagreed, and it was
written by different people from a different design.

**After**, a gate compares against checked-in goldens plus assertions
derived from the fixtures. Goldens are written by the compiler under
test, so anyone who breaks the compiler and then re-blesses gets a green
gate — unless a derived assertion catches the specific defect.

That is not a theory. Every one of the seven rewritten gates was
attacked by an adversary allowed to introduce a real defect and re-bless
every golden, and **all seven went green on the first attempt.** The
derived halves were then strengthened until each attack failed:

- `check-diagnostics` — a hand-maintained severity policy, because the
  golden's severity letter and the exit status are the same field.
- `check-fmt-selfhost` — an indentation-variety floor, because a
  flush-left printer is idempotent, reparses, and preserves every
  comment.
- `check-bootstrap` — `tests/selfhost/910-operator-coverage.ax`, because
  `>>`, `%`, `|` and `^` appeared in **zero** of the 90 conformance
  cases, and a compiler is not self-checking about operators it never
  performs on itself.
- `check-repl`, `check-lsp`, `check-stdlib-selfhost`,
  `check-render-selfhost` — each given a half derived from fixture bytes
  or reimplemented in Python.

A second adversarial round then attacked the hardened gates. The
original attacks are dead; narrower ones survive, and their fixes are
recorded where they belong rather than pretended away.

**The residual risk, honestly.** These gates now defend fully against
*accidental* regression — the case where a gate fails and a developer
investigates. They defend partially against a *careless re-bless* — the
case where someone makes a red gate green without reading it. They do
not defend against a determined adversary, and neither did the
differential, once you notice that the same person could have edited
both compilers.

The lever that matters is cultural and is written into every one of
those scripts: **a bless is not a fix.** Each header now says what its
derived half is and what drill it survived, so a maintainer regenerating
a golden can see what they are being trusted with.

---

## 9. Retiring the C FFI

`foreign` is gone. So are the struct layout modifiers `packed`,
`repr(C)` and `align(N)`, and the `X` (foreign binding) kind in AXSYM.
All three are now spelled the same way `union` and `region` are: a
reserved word that reports `AX2004` with migration advice, so old source
gets an explanation instead of being reinterpreted as an ordinary
identifier.

### 9.1 `foreign` did not work, and nothing said so

The binding parsed, type-checked, contributed `IO` to effect inference,
and appeared in `symbols` with its linked symbol name. What it never did
was emit a `declare`. Measured on trunk `1c3b325`:

```
(foreign putchar :: (-> Int Int) = "putchar")
(:: main Int)
;@axiom:effect(io)
(fn (main) { (putchar 65) 0 })
```

`check` answered `OK` and exited 0. `emit-llvm` produced
`%t0 = call i64 @putchar(i64 65)` in a module that declares no
`@putchar`, and `build` died two stages later:

```
opt: f1.ll:235:18: error: use of undefined value '@putchar'
E AX4003 <toolchain>:- toolchain-failure "opt failed"
```

That is the exact shape `AX3015` exists to prevent — a name that passes
`check` and then fails in the native toolchain with an undefined-symbol
error about generated code — reintroduced by the one construct whose
whole purpose was to name a symbol from outside. Every `foreign` program
in the repository was a fixture that was never built: the diagnostics
case only ever read the AX3006 beside it, and the fmt zoo is formatted
and type-checked, never compiled.

So removing it is not a capability loss. There was no capability.

### 9.2 What it cost to keep

`TAG_D_FOREIGN` was threaded through five of the compiler's modules:
twelve sites in `typecheck.ax` (a namespace rule, the AX3015 definer
test, a collection branch, the ambiguity table, `declDefines`,
`setTargetCovered`, the declaration walk, and an `isForeign` field on
`FnEnt` read by `repArity` and by both effect-inference walks), a
declaration parser plus a two-function symbol scanner in `parser.ax`, a
collection branch and a whole parallel-vec map pair in `symbols.ax`, and
a printer arm plus `fpStrRaw` — its only caller — in `format.ax`.
Dropping the `FnEnt` field shortened the struct from eight words to
seven and renumbered three others; dropping the `symbols.ax` map pair
took `SymMaps` from twenty-two fields to twenty.

### 9.3 The layout modifiers were formatter-only

`packed`, `repr(C)` and `align(N)` were documented in `README.md` and
`docs/reference.md`, printed by `fpDeclStruct`, described by the
tree-sitter grammar, and pinned by a tree-sitter corpus case — and
rejected by the compiler. All three are `AX2001` and always have been:

```
E AX2001 s1.ax:1:11-15 unexpected-token "expected identifier, found `repr`"
```

The formatter could therefore only ever have printed programs that do
not compile. `(struct Counter mut ...)` in `docs/reference.md` was the
same class of defect and is corrected in the same pass; `mut` goes on
the field.

This is the failure mode `check-fmt.sh`'s own header names — "`type`,
`trait`, `impl` and `foreign` were all formatted into source that did
not parse, with CI green" — surviving in the one direction that gate
does not cover, because the zoo carries only what someone wrote into it.

### 9.4 What the freestanding gate lost, and what replaced it

`check-freestanding.sh` ended in a negative probe: an Axiom program
built on `(foreign posix_spawn ...)`, required to produce IR the
forbidden-name grep catches. It worked precisely because `foreign`
emitted an undeclared call. With `foreign` gone the language cannot name
an external symbol at all, so that probe cannot be written any more.

Deleting it would have left the gate asserting silence with nothing
proving the silence is real. It is replaced by two checks that are
together stronger than the one they replace:

1. The grep is run against IR the script writes itself, once per name in
   the list rather than once for `posix_spawn` — the old probe exercised
   one alternative of a 31-name alternation, so a typo anywhere else in
   it was invisible.
2. The grep is shown *discriminating*: `axiom_alloc`, `freelist`,
   `awaited`, `printfmt` and `__syscall1` must not match. A pattern that
   matched everything passed the old probe.

And a third check asserts the source-level door is shut: a `foreign`
binding must be refused, and refused as `AX2004`. That is the fact the
old probe implied by working; it is now stated.

### 9.5 What stays

The `libc_names` list stays, though nothing in the language can emit a
call to one. It is what would notice a *backend* that started lowering
something to a libc name, which is a different door from the
source-level one.

Tag 29 (`TAG_D_FOREIGN`) is retired, not reused. The tag numbers are the
AST's wire format between `parser.ax` and its four readers, and a
recycled one turns a stale reader into a silent misparse rather than a
crash.

---

## 10. The comment syntax three implementations had and the lexer did not

`#| ... |#` block comments, which nest, are documented in `README.md`
and `docs/reference.md` as part of the language. stage0 lexed them
(`consume_block_comment`, `axiom-lexer/src/lib.rs:631`, dispatched at
:159 on `ch == '#' && self.peek() == Some('|')`). `format.ax` scans
them, with nesting, and its comment records that the depth counter was
added after probing stage0. `tests/fmt/verify-fmt.py` — the independent
verifier that reads no golden — scans them too, and its header records
that `fmt` once shipped having deleted every one.

`self_host/lexer.ax` had no case for `#` at all, so the first byte fell
through to the unexpected-character arm. Measured on trunk `5f8d022`,
on the example printed in both of those documents:

```
$ cat readme.ax
#| This is a block comment.
   They can nest: #| inner |# |#
(:: main Int)
(fn (main) 0)
$ axiom check readme.ax
E AX1001 readme.ax:1:1-2 unexpected-char "unexpected character `#`"
```

`CONTRIBUTING.md` said "There is no block comment, and no other language
in the tree to have one." Two documents promising a feature and a third
denying it is not a disagreement anything could report: each was read on
its own.

### 10.1 Why every gate was green

No `.ax` file in the repository contained a block comment. `check-fmt.sh`
formatted 229 of them and re-ran the suites on the result;
`check-tree-sitter.sh` parsed the same 229 under the grammar; neither
can see a construct the corpus does not use. This is the failure mode
`tests/fmt/syntax-zoo.ax` exists for — "the corpus is written by people
solving problems, so it uses only the constructs those problems need" —
and the zoo did not have one either, because the zoo was written by
someone reading the *parser*, and this is a *lexer* form.

The one block comment in the tree is `tests/fmt/parity/110-nested-block-
comment.axp`, a formatter fixture. It is formatted, not compiled, and
what it pinned was that `fmt` leaves it alone:

```
$ axiom fmt case.ax   # exit 0 - "already formatted"
$ axiom check case.ax # exit 1 - E AX1001
```

So the file that proved the formatter handled block comments was the
same file that would have proved the compiler did not, and nothing ran
the second half.

### 10.2 The formatter verifies itself with its own scanner

`fmtFormat` refuses to write unless the output rescans, keeps exactly
the comments the input had, and is a fixed point of a second pass. All
three run inside `format.ax`. `format.ax` has its own scanner by
necessity — it needs the spans of `]`, `,`, `#| |#` and discarded
comments, which the token stream does not carry — and that scanner is
therefore a second implementation of the grammar, checked against
nothing.

`check-fmt-selfhost.sh` §5b closes it: **every formatted output is
handed back to the compiler, and must carry no AX1xxx and no AX2xxx.**
251 outputs: 231 files from the formatted copy of the tree, plus the
20 of the 37 parity cases the formatter accepts. Type errors are
allowed — the parity bank is full of programs about undefined names —
and so is input the compiler would refuse, because migrating legacy
spellings (`$` to `!`, `define` to `fn`) is the formatter's job. What
it may never do is *emit* any.

Ablated by running the new section against a compiler built from
`5f8d022`: exit 1, one failure, `110-nested-block-comment.axp: its
formatted output does not lex or parse`. The old §6 could not have
found it — §6 compiles the formatted *tree*, and the tree has no block
comment.

### 10.3 What the lexer does now

`isBlockOpen` is the two-byte test; `skipBlockComment` is stage0's loop,
counting depth, stopping at EOF with no error (an unterminated block
comment is a file whose tail is comment, which is what stage0 returned
`Ok` for). Both are `while` loops rather than recursions, for the reason
`scanAxtags` was rewritten as one: a stage1-built compiler eliminates
only self tail calls, so a recursive byte-walk costs a frame per byte.
Every call site guards on the byte it already holds, so ordinary source
pays one integer comparison.

`scanAxtags` skips block comments too, and has to: it is a second walk
over the source, not a read of the token stream, so it carries the same
obligation as its string and char arms. stage0 consumed a block comment
before its `;` branch ever ran, so `#| ;@axiom:pure |#` was never a tag
there. `tests/diagnostics/335-axtag-in-block-comment.ax` is that fact as
a fixture: two identical functions with identical `pure` claims, one
claim inside a block comment, and **one** AX3010 in the golden. A
scanner that missed the block would report two.

### 10.4 The grammar needed an external scanner

Nesting is not a token any regular expression describes, and the obvious
rule spelling disagrees with the compiler on input the compiler has an
opinion about. `#| a||# |#` closes at the `|#` inside `a||#` under both
`skipBlockComment` and stage0 — each tests `|` against the next byte and
advances one when that byte is not `#`, so the second `|` starts a fresh
test — while a chunk regex consumes `||` as one match and leaves a `#`
that closes nothing.

`tree-sitter-axiom/src/scanner.c` reproduces the loop instead. Verified
against the compiler on that input: the grammar's `block_comment` node
spans bytes 0–7, and `axiom check` reports AX1001 at column 10 — both
end the comment in the same place and both refuse the file. Ablated by
deleting the depth counter: the corpus fails exactly one case, the one
that nests.

### 10.5 What is not fixed

`fmt` moves a comment that sits *inside* an expression to the end of the
file. `tests/selfhost/170-block-comment.ax` records it, and it is not
about block comments — a line comment in the same position moves the
same way, and has for as long as the formatter has existed. The
formatted file still parses, still preserves every comment byte, and
still answers 55, so every property the gates state is intact; what is
lost is where the reader put the note. Fixing it is comment attachment
in the printer, which is a slice of its own.

---

## 11. A signature the parser read and then threw away

`parseSigDecl` parsed the declaration's type *opportunistically*:
`skipParens` owned the end position, and a type the parser could not
read left `0` in the ty slot, which the checker treats as a silent
wildcard. The note that used to sit there called this "under-reported,
never mis-typed". The first half was true. The second was not, and it
failed in two different directions.

### 11.1 A refusal that was computed and discarded

```
(:: f (-> Int))
(fn (f) 1)
```

`(-> T)` is not the type of a nullary function — a nullary function is
declared with a bare type, `(:: hostTarget Int)` — and both compilers
refuse the one-atom arrow. stage0 said so in words ("-> requires at
least two types", `axiom-parser/src/lib.rs:1019`); `parseTypeParens`
answers `pErrExp pos "type"`. The refusal was then dropped on the floor
by the caller, so `f` had no signature at all and `check` printed `OK`.

The one instance that reached the tree was `explainListColored` in
`main.ax`, declared `(-> Int)` and unchecked for as long as it existed.
What found it was `check-fmt.sh`, as `was not rewritten: formatter
refusal` — which is a strange way to be told that a type was ignored,
and only worked because the file happened to be inside the tree the
formatter sweeps.

### 11.2 A signature that was silently TRUNCATED

```
(:: h Int Bool)
(fn (h x) (== x 1))
```

This reads as `Int -> Bool` and is not. `parseType` reads `Int` and
stops; `skipParens` skipped from there to the declaration's `)`, so
`Bool` was discarded — and `h` was left *typed*, typed wrongly, with no
diagnostic at the signature. The only report was at the call site:

```
E AX3004 s1.ax:5:17-18 type-mismatch
  "type mismatch: expected function type, found Int"
```

which blames the caller for a defect in the declaration above it. That
is the direction the old note said could not happen.

### 11.3 The other two implementations already agreed

The tree-sitter grammar's `type_signature` is `'(' [pub] '::' subject
type ')'` — one type, then the closer — and both shapes above are ERROR
nodes under it. The formatter refuses to rewrite either. This parser
was the one implementation of the three that accepted them, and the
gates could not see the disagreement because nothing compares a
`.axbad` fixture's fate across the three.

### 11.4 What it is now

stage0's shape, both halves: `parse_sig` ran `parse_type()?` with the
`?` propagating, and its caller then ran `expect(RParen)` on what was
left (`axiom-parser/src/lib.rs:473` and :367). So a type this parser
cannot read is that type's own parse error, and a type that does not
reach the closer is `expected ), found \`Bool\`` — `expect`'s rendering
of `TokenKind::RParen` verbatim. `skipParens` is gone from this path;
the end position is one past the closer the check just proved is there.

Measured blast radius before landing it: **231 `.ax` files and 94
`.axbad`/`.axp` fixtures swept through the old and new compilers, zero
divergences.** Nothing in the tree relied on the tolerance — which is
also why nothing in the tree would have noticed it come back, and why
`tests/diagnostics/980-sig-nullary-arrow.axbad` and
`985-sig-trailing-type.axbad` are here.

### 11.5 The same tolerance survives in two smaller places

`parseEffectOps` and `parseAliasDecl` both parse a type
opportunistically and keep `skipParens`' position, on the recorded
argument that acceptance is unchanged and only `symbols` is the poorer.
Probed, and still true of both:

```
(type N = (-> Int))            check: OK
(effect E (op :: (-> Int)))    check: OK
```

They are left alone here because the checker genuinely does not consult
either type — an effect operation keeps a deliberate wildcard, and an
alias whose target did not parse falls back to the old skip. A
signature is different: it is the checker's contract for a function,
which is what made the same tolerance a wrong answer rather than a
missing one.

---

## 12. The fixpoint that two filenames decided

Every Linux job in CI failed, on every run, from 2026-08-08 to
2026-08-09. Nine jobs, six of them red, all six at the same step and
all six with the same three lines of progress before it:

```
ok   the seeds match bootstrap/SHA256SUMS
ok   seed built for linux-x86_64 from bootstrap/axiom-linux-x86_64.ll (no Rust)
ok   the seed compiled the current self_host/ into stage1
FAIL: stage2 and stage3 IR matched but their objects differ
```

The last successful run on this repository was **2026-07-30** — two days
*before* the self-hosting work began at `b32d41e`. Nineteen consecutive
runs were red. `Bootstrap from seed (darwin-aarch64)` and `Tests
(darwin-aarch64)` were green in every one of them, which is why the
failure survived: the machine the work was done on agreed with itself.

### 12.1 The compiler was never wrong

The message is precise and it is worth reading literally: the two
stages' **IR was byte-identical**. Only the objects differed. Identical
input through identical `llc` invocations produced different bytes,
which is not something a self-hosting bug can do.

`scripts/bootstrap-from-seed.sh` assembled the ladder like this:

```
llc -filetype=obj -relocation-model=pic $work/stage2.ll -o $work/stage2.o
llc -filetype=obj -relocation-model=pic $work/stage3.ll -o $work/stage3.o
```

Two files, one directory, different names. `llc` records the module it
was given — the IR carries no `source_filename`, so the input path
becomes the module identifier — and on ELF that identifier is written
into the object as an `STT_FILE` symbol in `.strtab`. Mach-O has no
such record and drops it.

What is recorded is the **basename, not the path**. Probed on
`bootstrap/axiom-linux-x86_64.ll` assembled from two absolute paths
differing only in their directory: objects byte-identical, `axc.ll`
present in `.strtab`, the directory absent (`strings axc.o | grep -c
<tmpdir>` = 0). That is what makes "same basename, different
directory" a fix rather than a coincidence, and it is why
`check-bootstrap.sh`, which passes llc absolute paths, was never
exposed to this.

Measured on the committed seeds, which are the real 8.4 MB compiler and
not a probe. Each seed assembled twice, once from `dN/axc.ll` in two
directories and once from `stage2.ll`/`stage3.ll` in one:

| target | same basename, different dirs | different basenames |
|---|---|---|
| `linux-x86_64` | identical | **differ** |
| `linux-aarch64` | identical | **differ** |
| `darwin-aarch64` | identical | identical |
| `darwin-x86_64` | identical | identical |

On a two-module toy the difference is at char 253, and `strings` shows
the entire divergence: one object says `stage2.ll`, the other says
`stage3.ll`.

### 12.2 The same hazard, already documented, in the other direction

`scripts/check-bootstrap.sh` has built its two stages **to the same
basename in different directories** since it was written, and says why:
macOS `ld` derives the Mach-O `LC_UUID` from the *output* path and the
ad-hoc signature covers it, so two byte-identical compilers linked side
by side as `stage2` and `stage3` differ in 48 bytes of 381,672.

That is the same defect with the roles reversed — output path on
Mach-O, input path on ELF — and the same one-line convention defuses
both. `bootstrap-from-seed.sh` is newer than that comment and never
inherited it. The rule, stated so it covers both:

> **A comparison whose inputs or outputs differ in path is a comparison
> of paths.** Build every artifact you intend to compare to the same
> basename, in a directory that differs instead.

Both scripts now use `dN/axc`. `bootstrap-from-seed.sh` also compares
the linked binaries, which it never did — `check-bootstrap.sh` always
has, and once the basenames match there is no reason for the weaker
ladder to assert less.

### 12.3 Why no gate could see it

Nothing in the repository asserted anything about an object's
relationship to the path it came from, so the property had no owner.
`scripts/check-cross-targets.sh` now owns it, because it is the one
gate that assembles every target from a single host and therefore the
only place a Mach-O machine can observe ELF behaviour at all.

It asserts two things per target, and the second is what keeps the
first honest:

1. the same module assembled from the same basename in two directories
   gives byte-identical objects;
2. on ELF, the object really does carry that basename.

Half 1 alone is satisfied by an `llc` that records nothing — which is
precisely the darwin situation that hid this for six days. Half 2 fails
loudly if a future LLVM stops embedding the name, so the protection
cannot quietly become a no-op; the failure message says to re-measure
and remove the assertion deliberately rather than to work around it.

Ablated, each individually: assembling the probe from two *different*
basenames fails both Linux targets and passes both darwin ones, which
is the outage reproduced inside the gate that now prevents it.

### 12.4 What this cost, stated plainly

Not the fix, which is a convention already written down elsewhere in
the same repository. The cost was six days in which **no Linux gate ran
at all**: the failing step provisions the compiler, so all seventeen
gates behind it — the whole test matrix, the cross-target check, the
reproducibility check and the fixpoint — reported nothing on three of
the four supported targets while a fortnight of self-hosting work
landed.

This document's own risk table names the shape twice ("a cheap job that
gates every other job fails, so nothing downstream ever runs"; "a gate
that is wired up and has not run is indistinguishable from one that
passes"). Both entries were written about jobs that had never executed.
This one executed, failed loudly, and was reported in the checks tab on
every push — the signal was working. What was missing was somebody
reading it, and the honest lesson is the cheapest one in the file:
**check what CI says before trusting what the docs say it says.**

### 12.5 And behind it, `axiom build` had never worked on Linux

With the fixpoint fixed, the same step failed one line later, on both
Linux targets and neither darwin one:

```
ok   stage2 and stage3 are byte-identical - the fixpoint holds from the seed
    error[AX4003]: cc failed
FAIL: stage3 could not build a program
```

`cc` printed nothing, which is the tell: it had never run.

`sysRunPath` implements `execvp`'s rule itself — a bare name is looked
for in each `PATH` entry in order — and the note above it recorded a
deliberate choice to search *by attempting each candidate* rather than
by testing for the file first, because AArch64 Linux has no `access`
and a test can be raced. That reasoning is sound under `posix_spawn`,
which resolves the path itself and answers `-ENOENT` **without creating
a process**. It does not survive the other backend. Under
`fork`+`execve` the fork always succeeds, the failed `execve` happens in
the child, and the only thing that comes back to the parent is the
child's exit status — 127, by this library's own convention. 127 is not
negative, and `sysRunSearch` advanced only on a negative answer, so:

> the search stopped at the **first** `PATH` entry, and reported that
> entry's absence of the tool as the tool's own exit code.

`llc` worked because CI puts LLVM's bindir first; `cc` is in `/usr/bin`
and was never reached. Both Linux architectures failed identically,
which is what ruled out every arch-specific theory (the `-O0` absolute
relocation, the entry symbol, PIE) in one comparison.

The fix is one `sysOpenPath` before the spawn: a candidate that cannot
be opened is skipped without forking, so "no such file" and "the tool
exited 127" stop being the same integer. It needs no new syscall on any
platform — `sysOpenPath` already routes through `openNeedsDirFd` for
exactly the AArch64 `openat`-only asymmetry the original note gave as
its reason. The race that note describes is real and is accepted; the
alternative is a close-on-exec pipe carrying the child's errno, which is
the correct POSIX answer and a larger change than this defect justifies.

`scripts/check-driver.sh` gates it: a `PATH` whose first entry holds
none of the tools must still build and run. **That case is vacuous on
darwin and only discriminates on Linux**, because the backend that had
the bug is the one darwin cannot use — its `fork` returns two values and
`__syscallN` yields one register, which is why `posix_spawn` is there at
all. An ablation on macOS passes. That is a property of the defect, and
saying so in the script is better than a future reader concluding the
test is weak.

Two defects, one shape: **a capability with two backends is two
implementations, and the one your machine does not run is untested.**

### 12.6 The same conflation, one level down, found by the test that had never run

Fixing the provisioning step let the Linux half of the `Tests` job reach
its second step for the first time in six days, and it failed there:

```
FAIL 300-process (stdout)
    4c4
    < 1
    ---
    > 0
36 passed, 1 failed
```

Both Linux targets, identically; darwin green. Line 4 of that case is

```
(printlnInt (if (< (sysRun (strCStr "/nonexistent/tool") (argv3 "x" "" "") env) 0) 1 0))
```

which is the **direct** path — no `PATH` search, nothing for
`sysRunSearch` to do. §12.5's probe went into the search, one level
above the defect, and the identical conflation was still sitting in
`sysSpawn`: the fork succeeds, the `execve` fails in the child, the
child exits 127, and `sysRun` answers 127. Its own doc comment says

> A negative answer is the spawn's own `-errno` — the child never ran —
> which is what distinguishes "could not start llc" from "llc rejected
> the module", two failures a driver must not report the same way.

That sentence had been false on Linux since the day it was written.
`axiom run` goes through the same door: `main.ax` runs the program it
just built as `./axiom_temp_output`, a name with a slash, so it takes
the direct branch too.

The probe therefore belongs in `sysSpawn`'s `fork`+`execve` arm, not in
its caller, and **ENOENT only** — where the search skips a candidate on
any open failure, which is `execvp`'s rule for a `PATH` walk, the direct
path must not. A file that cannot be opened can still be executable
(mode 0711 is readable by nobody and runnable by everyone) and `execve`
is the only thing entitled to decide that, so every other open failure
still forks and asks it.

The gate is `tests/stdlib/300-process.ax` line 4, and it is worth being
precise about what happened to it: **the case was already written, and
already correct.** It did not need adding, weakening, or re-blessing. It
had simply never executed on the platform whose backend it discriminates,
because the job it lives in had been failing an earlier step. Like
`check-driver.sh`'s `PATH` case it is vacuous on darwin — `posix_spawn`
resolves the path in the parent and has always answered `-ENOENT` — so
a local run on macOS cannot see this fix work, and CI is the only
arbiter for it.

That is the sharper form of §12.5's lesson. It is not only that the
untested backend is broken; it is that **the test which would have
caught it can already exist, already be right, and still be telling
nobody anything** — for six days, because something upstream of it was
red and nobody had read down past the first failure.

## 13. The empty form: a node the parser said it built and never made

`axiom check` on this program died of `SIGSEGV`:

```scheme refused
(:: main Int)
(fn (main) ())
```

Exit 139, no output, nothing on stderr, no diagnostic. So did
twenty-two other programs — the same two characters in a different
position each time — and seven of those killed `check` itself rather
than the emitter:

| position | before | after |
|---|---|---|
| `(fn (main) ())` | `check` OK, `run` SIGSEGV | `AX2001` at the `)` |
| `(let ((x ())) 0)` | `check` SIGSEGV | `AX2001` |
| `(())`, `(() 1)` | `check` SIGSEGV | `AX2001` |
| `(:: 1 ())`, `(:: () Int)` | `check` SIGSEGV | `AX2001` |
| `(match 1 (() 0))` | `check` SIGSEGV | `AX2001` |
| `(if () 1 2)`, `(while () 0)`, `(cond (() 1) (else 2))` | `check` OK, `run` SIGSEGV | `AX2001` |
| `(macro (m x) ())` | `check` OK, `run` SIGSEGV | `AX2001` |
| `(fn (main) {})` | `check` OK, `run` exits 4 with `AX4003 opt failed` against `<toolchain>` | `AX2001` at the `}` |

The cause is one line. `parseInner` answered

```scheme excerpt
(if (peekIs tokens pos TK_RPAREN)
    (pOk 0 (advance pos))
```

— a **successful** parse whose node handle is `0`, which is the handle
every other producer in `parser.ax` uses to mean *there is no node
here*. `pErr` is how that file reports failure; `pOk 0` reports success
and hands over the null. Nothing downstream guards a node it has been
told it has, so `checkExpr` and `emitExpr` both dereferenced it. This is
the sentinel-in-the-data-channel defect the effect collector had in
2026-08-06, in its most direct form: the sentinel was not merely stored
beside real data, it was returned *as* real data.

`{}` is the same defect one node further along. It parsed as a real
`EBegin` over an empty vector, survived the checker, and reached codegen,
which emitted a block that assigns no register — invalid IR, which `opt`
rejects and the driver reports as `AX4003 opt failed` against
`<toolchain>`. The compiler blaming the toolchain for its own output,
with no span into the source, is the failure mode
[macros.md §2](macros.md) records for templates and is here for a
two-character program.

### 13.1 The language server died on what typing looks like

`()` is not an exotic input. It is the state of a buffer between the
keystroke that opens a form and the keystroke that fills it, so the
document a language server sees most often is one that contains it.
Driven by hand — `initialize`, `didOpen`, then one `didChange` whose
text is `(fn (main) (let ((x ())) 0))` — the server answered the
lifecycle, published diagnostics for version 1, and was killed by
signal 11 before version 2:

```
returncode: -11
stdout bytes: 382     (initialize result, then one empty diagnostics array)
```

Seven of the twenty-three crashes were inside `check`, which is exactly
the entry point `lsp.ax` calls per edit, so every one of those seven was
a way to end an editing session.

### 13.2 Why five gates were green

The formatter accepted all of it. `axiom fmt` on `(fn (main) ())`
reports `OK: formatted` and writes the file back out, because
`format.ax` — the second implementation of the grammar — has a printer
arm for the empty form. So did the parity bank: **the two programs that
killed the compiler were already checked-in test cases.**

```
$ cat tests/fmt/parity/170-empty-tuple.axp
(fn (f) ())
$ cat tests/fmt/parity/172-empty-brace-body.axp
(fn (f) {})
```

and `tests/fmt/parity.golden` recorded, as the correct answer, that the
formatter rewrites both and exits 0.

That bank compares the formatter with its own previous output, so it
could not see a crash. But `check-fmt-selfhost.sh` §5b exists precisely
to close that loop — it hands every formatted output back to the
compiler and fails if it carries an `AX1xxx` or `AX2xxx` — and it was
green too, for a reason worth stating in full because it generalises:

> **A process killed by a signal prints nothing, so it satisfies every
> check written as "the output must not contain X".**

§5b ran `check` on `(fn (f) ())`, `check` died before printing anything,
the grep found no diagnostic line, and the case passed. The section's
own status was discarded with `|| true`. This is the third entry in this
document's catalogue of failures that look like success — after a golden
with no content, and a sweep that reads fewer files than it should — and
it is the one that cannot be fixed by counting, because the count was
right: 251 outputs were swept, and two of them killed the compiler.

There is a fourth green gate in the list, and it is a different bug in
the same family. `()` at the top level is `AX2003` from this compiler,
and the formatter **deleted the form** and exited 0:

```
$ cat a.ax
()
(fn (f) 1)
$ axiom check a.ax  ->  E AX2003 a.ax:1:2-3 syntax-error   exit 1
$ axiom fmt a.ax    ->  OK: a.ax formatted                 exit 0
$ cat a.ax
(fn (f) 1)
$ axiom check a.ax  ->  OK                                 exit 0
```

`axiom fmt` turning a file the compiler refuses into one it accepts is
the one rewrite a formatter may never make, and it is the only kind that
cannot be caught by asking whether the output means what the input meant
— because the input means nothing. `format.ax`'s comment said
`parse_module` skips an empty `()` form, which was stage0's rule; it has
not been this compiler's for as long as anyone has checked, and nothing
re-read the comment after stage0 was deleted.

### 13.3 What changed

Four sites, all refusals:

- `parseInner` answers `(pErrExp pos "expression")` for `()` in
  expression position. That is what `[]`, `(-> )`, `(* )`, `(set)`,
  `(alloc)`, `(consume)` and `(handle e)` already answer; the empty form
  was the outlier. `()` remains a **type** — the empty tuple, built by
  `parseTypeParens` — and `(:: main ())` still checks and runs. The two
  positions are separate, which `(:: 1 ())` proves: a type ascription in
  expression position parses its type with `parseExpr`, deliberately, so
  it went through the crashing door.
- `parseBlockBody` refuses a block with no expressions. A block's value
  is its last expression; a block with none has no value.
- `format.ax` refuses all three shapes — `()` in expression position,
  `()` in pattern position, `{}` — and no longer deletes a top-level
  `()`. Refusal parity is the contract the `.axp` bank pins, and three
  of its cases changed sides.
- `check-fmt-selfhost.sh` reads the exit status before it believes the
  output, in both §4 and §5b, and now asks the compiler about each
  parity case as well as the formatter.

No unit **value** was invented. Adding one is a language change that
would have to move the type checker, the emitter, `format.ax` and
`tree-sitter-axiom/` together; refusing is the weakest rule that kills
the class, and the class is what was killing the compiler.

### 13.4 The gate, and the ablation

`scripts/check-degenerate.sh` is 88 small adversarial programs — every
position of the empty form, the truncated and unterminated inputs, the
literal boundaries, the empty declaration bodies, a NUL byte — run
through `check`, `fmt --check` and `symbols`. Its assertions are about
the **process**, not its output, which is the whole point:

1. no invocation may be killed by a signal;
2. a refusal must print a diagnostic to act on;
3. an acceptance must print no error;
4. the pinned exit status per case;
5. floors: at least 80 cases, both outcomes present, and at least six
   distinct diagnostic codes among the refusals — a bank that answers
   everything with one code has stopped distinguishing its cases.

It ends by driving `axiom lsp` through five document versions, two of
which contain an empty form, and requires the server to publish
diagnostics for every one of them **and answer its own shutdown**. That
last clause is load-bearing: a server that dies quietly after the first
publish still produces plausible-looking stdout, and only the reply to
the final request proves it was alive at the end.

Measured, on a compiler built from the tree before the fix:

```
FAIL empty-let-val: check was killed by a signal (exit 139)
FAIL empty-let-val: symbols was killed by a signal (exit 139)
...
     88 cases: 23 accepted, 40 refused, 7 killed by a signal
FAIL lsp: the server was killed by signal 11
FAIL: 26 of 88 checks failed
```

and after:

```
     88 cases: 23 accepted, 65 refused, 0 killed by a signal
ok   the refusals name 9 distinct diagnostic codes
ok   the server answered 5 versions and its shutdown
PASS: 88 degenerate inputs, every one answered by a diagnostic or an acceptance
```

The corpus is unmoved: all 241 `.ax` files in the repository produce the
same `fmt --check` status before and after, because no file in it
contains an empty form. That is the reason it survived — the corpus is
written by people solving problems, and nobody's problem needs `()`.

### 13.5 What this did NOT fix, measured and recorded

- **A nullary lambda applied returns the closure, not its result.**
  `((lambda () 7))` answers `4302028816` — a pointer — where `7` is
  meant, and `(let ((k g)) (k))` on a nullary `g` is `AX3004 expected
  Int, found (() -> Int)`. A zero-argument application is parsed as the
  head expression alone. A named nullary call `(g)` is a direct call and
  is correct, which is why nothing noticed. Silent wrong answer, not a
  crash, and a separate defect in the application form.
- **`(match e)` with no arms and `(cond)` with no clauses are accepted**
  and answer 0. Exhaustiveness over a non-ADT scrutinee is not checkable,
  so this is a runtime-trap question rather than a parse question, and
  `173-empty-match.axp` stays a rewrite.
- **An unterminated `#| ... ` runs to end of input and is not an
  error** — `check` on a file whose first line is `#| never closed`
  reports `OK` and compiles an empty module. `lexer.ax` documents this as
  deliberate and matched to stage0's `consume_block_comment`, whose loop
  guard is `pos < len && depth > 0` and which returns `Ok` either way,
  and `format.ax`'s scanner agrees with it byte for byte, so the two
  implementations are consistent. It is left alone here because it is a
  language decision that has to move the lexer, `format.ax` and
  `tree-sitter-axiom/src/scanner.c` together — the same reasoning
  `lexer.ax` already applies to a line break inside a string literal.
  The argument for revisiting it is that an unterminated `"` is `AX1002`
  and an unterminated `'` is `AX1003`, so the block comment is the one
  unterminated construct that silently truncates the file instead, and
  truncation that looks like success is what `parseTopForm`'s own
  comment calls the worst spelling of unsupported.
- The parser's nesting guard fires between depth 1,000 and 5,000
  (`AX2005`, measured at 1,000 → OK and 5,000 → refused), so the deep
  cases in the bank are inside it by construction and pin the accepting
  side.

## 14. A module cannot have a private declaration

**Fixed 2026-08-10.** What follows is the defect as it was measured on
2026-08-09, because the fix is only legible against it; §14.3 records
what it is now, §14.4 the half that was found a day later and is worse
than anything below, and §14.5 what this still leaves.

`R.ax`:

```scheme
(:: helper (-> Int Int))
(fn (helper n) (* n 2))
(pub :: quad (-> Int Int))
(pub fn (quad n) (helper (helper n)))
```

`axiom check R.ax` is `OK`, exit 0. Any file that imports it is not:

```
$ cat useR.ax
(import R)
(:: main Int)
(fn (main) (quad 3))

$ axiom --diagnostic-format=ai check useR.ax
E AX3001 R.ax:5:19-25 undefined-variable "undefined variable `helper`" ...
E AX3001 R.ax:5:27-33 undefined-variable "undefined variable `helper`" ...
exit 1
```

The importing file is fine and the imported file is now broken — reported
at **its own lines**, by a file that merely read it. A module with a
private helper is a module nobody may import.

The selective form of the import has the same defect for a name that is
`pub`. `(import T (quad))`, where `T`'s `quad` calls `T`'s `pub other`,
deletes `other` and fails identically. And a private `macro` fails the
same way, which is how this was found — it looked like a macro bug and is
not one.

`resolveDeclsPhase` (codegen.ax) is the site. It drops a declaration that
is not `pub`, or that the import's name list does not name, and the
comment records the intent exactly:

> A private declaration of an IMPORTED module is not part of the program:
> stage0 splices only `pub` ones, so a reference to a private imported
> name is undefined there and was silently callable here.

Which is right about the NAME and wrong about the CODE. The module's
public bodies are spliced, and they call the declarations that were
dropped. **`pub` and the import list should decide which bare names are
visible, not which declarations exist**, and those are two different
things sharing one `if`.

### 14.1 Why no gate could see it

All **3,094** top-level `fn`/`::`/`define` declarations in `stdlib/` and
`self_host/` are `pub` — every single one — and not one of the 144
imports carries a name list. The entire corpus lives on the only path
that works. A count of the private declarations in this repository, at
the moment this was written, is zero.

That is the same shape as the empty form in §13 and as block comments in
§10: the corpus is written by people solving problems, and none of their
problems needed the construct.

### 14.2 The fix that is not complete

Carrying the declaration is three lines: `mangleRecord` already does two
separable things — it records `Mod$name -> Mod$name`, which is how a
reference *inside* a module reaches its own definition, and `name ->
Mod$name`, which is what makes the bare name visible to everyone else.
Splitting them, splicing every declaration, and recording only the first
for a carried one makes all three cases above compile and run: measured
12, 12 and 12, and the emitted IR shows `R`'s own body calling
`@R$helper` while nothing else can name it.

It is not enough, and the reason is worth recording because it is the
same defect class this session opened with. **The type checker has no
notion of visibility.** `declMatches` resolves a bare reference by
matching the declaration's bare suffix — deliberately, since that is how
an imported `pub` name resolves — so once the private declaration exists,
the checker accepts a reference to it from anywhere. Privacy was being
enforced by the declaration's *absence*, and with the declaration present
the reference passes `check` and fails in `opt`:

```
$ axiom run leak.ax          # (import R) then (helper 3)
opt: error: use of undefined value '@helper'
error[AX4003]: opt failed  --> <toolchain>
```

A clean `AX3001` traded for a link failure blamed on the toolchain is the
exact trade §13 exists to undo, so the half-fix is recorded here rather
than committed. Completing it means giving the checker the visibility it
does not have: the node already carries both `vis` (word 5) and its
declaring `module` (word 8), and the checker already tracks the module
whose declaration it is checking, so the rule is expressible — a bare
reference may not reach a declaration that is invisible and belongs to
another module — but it has to be threaded through `declMatches` and its
call sites, which is name resolution in a compiler that compiles itself
and wants its own slice and its own battery.

This is the other half of the flat-namespace decision the roadmap's P3
row already names: *resolution outward from a module is still the merged
declaration list rather than that module's import set.*

### 14.3 What it is now

Both halves landed together, because either alone is worse than
neither. `resolveDeclsPhase` carries **every** declaration and records
the export decision on the node (word 5, which meant "was written
`pub`" and now means "may anything outside name it"). `mangleDecl` then
splits `mangleRecord`'s two recordings the way §14.2 described: a
carried private declaration records `Mod$name -> Mod$name` and leaves
the bare slot alone.

The checker gets the visibility it did not have, and it is one table,
not a field on every entry. `tc` word 19 holds the mangled name of each
carried-but-not-exported declaration; `findFnEnt`'s module-local step
is unchanged (anything it finds is the module's own), and the two steps
after it — which are the ones that can reach another module — consult
it. `findCtor`, `rfindCtor`, `findStruct` and `findData` do the same
for types, keyed on the module recorded beside them, since `data` and
`struct` names are not rewritten to `Mod$name`.

A reference that gets refused is **`AX3023`**, a new code, and it says
which module the name belongs to rather than claiming the name does not
exist:

```
error[AX3023]: `helper` is private to module `M.Lib`
 --> leak.ax:3:13
  |
3 | (fn (main) (helper 3))
  |             ^^^^^^ `helper` is not exported by its module
  |
  = help: a name leaves its module when its declaration is written `pub`;
          if the import that brought the module in carries a name list,
          the name has to appear there too
```

That diagnostic is the load-bearing half. Without it the reference
reaches `mangledFor`, which holds no bare entry for a private name and
emits it verbatim — `opt: use of undefined value '@helper'`, exit 4,
blaming the toolchain — which is precisely the trade §14.2 refused to
commit.

**The table is 0, not an empty Vec, when the program has nothing
private**, and that is a measured decision rather than a taste. The
first version put an `exported` field on `FnEnt`, `DataEnt` and
`StructEnt`. `findFnEnt` scans `tcFns` linearly and a self-check spends
most of its time there, so one extra word on ~1,600 entries cost
**1.30s → 1.38s** on `check self_host/main.ax`, same builder, same
flags, same input. Moving it to one side table and guarding every
lookup on `(== (memGetWord tc 19) 0)` — a load and a compare against a
constant, no call, no length — brings it back to **1.31s**, which is
inside the run-to-run spread.

Two things had to move with it:

- `inferEffectsPass` looked up a declaration's own `FnEnt` *before*
  setting `tc`'s current module, so every private function's entry came
  back 0 and its body's effects were never accumulated. The symptom was
  the entire standard library drawing `AX3010 effect(io) claim
  unsupported` the moment one import carried a name list. `tcCheckFn`
  already sets the module before its lookup and says why in a comment;
  this is the same rule, and the fix is the same two lines.
- `ambBuildDecl` no longer records a name nothing outside can reach. A
  private helper colliding with an unrelated public name in another
  module would otherwise report `AX3014` about two definitions, only
  one of which the reference could ever have named. `isDefined` refuses
  a private definition for the same reason: an entry-file `(:: f T)`
  with only a private `M$f` behind it is still `AX3015`, and saying so
  is what keeps it from becoming an undefined symbol at link time.

Gated by `tests/selfhost/920-private-declaration.ax` (a private `data`,
its constructor, a private function matching on it, and a private
helper, all reached from public bodies — answers 42, and does not
compile at all against a compiler built from `875b79b`) and
`tests/selfhost/930-selective-import.ax` (the name-list half), plus
`tests/diagnostics/370-private-name.ax` and
`380-private-name-filtered.ax` for the refusal.

**And it is a measured no-op on everything that exists.** §14.1's census
said all 3,094 top-level declarations in `stdlib/` and `self_host/` are
`pub` and not one of the 144 imports carries a name list — so the whole
corpus is on the path where nothing changes, and it is worth checking
that prediction rather than asserting it. All **246** `.ax` files under
`stdlib/`, `self_host/` and `tests/` were run through `check
--diagnostic-format=ai` under a compiler built from `875b79b` and under
this one: **0 divergences**, in bytes and in exit status. The fixpoint
holds, `stage2` and `stage3` emitting identical IR.

### 14.4 The half that was not recorded, and is worse

§14 above says a private helper makes the module fail to compile. That
is the *loud* manifestation, and it is not the dangerous one.

A dropped declaration does not merely go missing. It leaves its bare
name unclaimed in `mangleRecord`'s map, and `recordEntryFns` runs
before any import — so **if the importing program happens to define
that name, the imported module's own call lands on the importer's
definition.** Measured against `875b79b`, with `stdlib/IO.ax` as the
victim and nothing but documented syntax:

```scheme
(import Sys)
(:: writeStr (-> Int Int Int))
(fn (writeStr fd s) (sysWriteFd fd (__addr "PWNED\n") 6))
(import IO (println))
(:: main Int)
(fn main { (println "hello") 0 })
```

```
$ axiom run sel8.ax
PWNED
PWNED
exit 0
```

`IO.println` calls `writeStr` twice. Both calls reached the entry
file's. No diagnostic at any severity, from any pass. The name list is
the entire discriminator: delete `(println)` from that import and the
same program prints `hello`.

The same shape with a private helper and an integer answer, so the
wrongness is a number rather than a string:

| | wanted | `875b79b` | now |
|---|---|---|---|
| private helper, importer defines nothing | 12 | `AX3001` at *the library's* lines, exit 1 | 12 |
| private helper, importer defines `helper` | 12 | **100**, exit 0, silent | 12 |
| name list drops a `pub` sibling | 5 | `AX3001` at *the library's* lines, exit 1 | 5 |
| name list drops it, importer defines it | 5 | **50**, exit 0, silent | 5 |

Importing a module could rewrite what that module does. That is the
sentence the whole slice exists to make false, and it is a strictly
stronger statement than §14's — which is why the fix is not "carry the
declaration" but "carry the declaration *and* refuse the reference".

### 14.5 What this still leaves

- **`macro` and `effect` declarations are exempt, and for `macro` that
  is a widening rather than a no-op — measured, not assumed.**
  `mangleDecl` rewrites only `fn` and `::`, so a macro's name carries
  no module, and the expander runs *before* the checker and resolves an
  invocation by bare name over the declaration order, with nowhere to
  ask whose module the invocation is in. So a non-`pub` macro is now
  visible from outside its module:

  |  | `875b79b` | now |
  |---|---|---|
  | the module's own use of its private macro | 1 (`AX3001`) | 42 |
  | an outside use of it | 1 (`AX3001`) | 42 |

  The first row is the fix. The second is a leak, and it is recorded
  rather than repaired because **no program that previously worked can
  observe it**: a module with a private macro did not compile at all —
  its own call to that macro was the `AX3001` — so nothing could depend
  on the old refusal, which was deletion wearing privacy's clothes.
  Repairing it means giving the expander the invocation site's module,
  and `expand.ax`'s header calls its resolution rule a language
  decision rather than an implementation detail ("changing it is a
  language change, not a bug fix"), so it is its own slice with its own
  design.
- **A constructor of a private `data` is refused as `AX3001`, not
  `AX3023`.** The constructor lookup is a different path and does not
  reach the private table's function branch. The refusal is correct and
  the message is the older, weaker one.
- **An import's name list is still unchecked.** `(import M (noSuch))`
  is accepted in silence and reports nothing at the import; the mistake
  surfaces as `AX3001` wherever the name is used, or as nothing at all
  if it never is. That is its own slice — a diagnostic at the import
  site, naming what the module does export — and it is the last piece
  of the same family.

## 15. The identifier characters two passes did not honour

`lexer.ax` admits `+ - * / % < > = ! & | ^` into an identifier's first
byte and those plus `'` into the rest, deliberately and with the
reasoning written down: leaving `^` out did not make `(^ a b)` an error,
it made the lexer's fallback silently skip the byte, so xor became
application. `?` is deliberately absent for the mirror reason.

Two passes that consume names do not share that set. Both fail in
silence, and both were found by asking what a name may contain rather
than by anything in the corpus — there is not one prime-suffixed
identifier among the **1,629** top-level function names in `stdlib/` and
`self_host/`, and every apostrophe in either tree is inside a comment or
a string, where an earlier arm of the same scanner consumes it.

### 15.1 One apostrophe deleted a file's AXTAG checking (fixed)

`scanAxtags` walks a resolved module's bytes looking for `;@axiom:`
lines, with arms for a string, a char literal and a block comment so that
a tag inside one is not a tag. It had no arm for an identifier. `'` is an
identifier character, so `f'` is one token to `lexTokens` — and to this
scanner the `'` was the opening quote of a char literal, and
`skipCharBody` ran to the next apostrophe in the file, or to end of
input.

Measured on this repository's own AXTAG fixture. Prepending the single
line `(fn (poison' n) n)` to `tests/diagnostics/330-axtag-mismatch.ax`:

```
control  : 5 AX3010 warnings
poisoned : 0
```

AXTAGs are compiler-checked metadata — `pure`, `effect(io)` — so what one
apostrophe deletes is the checking. Nothing reports a dropped tag, `check`
does not fail on warnings anyway, and `fmt` preserves both the name and
the now-inert tag, so the loss has no channel to appear in.

The fix is an identifier arm ahead of the char-literal arm, asking
`isIdentStart` and `skipIdent` — the same two functions `stepIdentToken`
asks — rather than restating the rule, so the two cannot drift apart
again. `tests/diagnostics/336-axtag-after-prime` pins it: two tags, one
of them inside the swallowed span, and a real `'x'` past them so the
char-literal arm is still exercised. Against a compiler built before the
fix the fixture emits one of its two warnings.

### 15.2 Twelve of fourteen legal names could not be emitted (fixed)

The other pass is codegen, which writes names into LLVM unquoted. Every
shape below was accepted by the lexer, the parser, the checker, `fmt` and
`symbols`, and then died. This section previously recorded six of eight,
from the eight shapes that had been probed; sweeping the rest of the
character set found the ratio is worse:

| name | `check` | `run` (before) | `run` (now) |
|---|---|---|---|
| `plain`, `x-5` | 0 | 42 | 42 |
| `foo'`, `a+b`, `set!`, `a*b`, `a=b`, `a^b`, `a<b`, `a\|b`, `a&b`, `a%b`, `a/b`, `a>b` | 0 | **4** | 42 |

Exit 4 was `AX4003 opt failed` against `<toolchain>` — `opt` refusing
`define i64 @foo'(i64 %n)`. `x-5` survives only because `-` happens to be
legal in an unquoted LLVM identifier. It is the same sentence §13 already
records about `{}`: the compiler blaming the toolchain for its own
output, with no span into the source, for a program it told the user was
fine. The same twelve failed in parameter position, where the sigil is
`%` rather than `@` and the message is `expected ')' at end of argument
list`.

**The fix is `llvmSym`** (codegen.ax): a name whose every byte is in
LLVM's unquoted set `[-A-Za-z0-9$._]` is returned unchanged, and any
other is wrapped in `"` with `"` and `\` hex-escaped. It is routed
through the sites that write a *user's* name into IR — the function
definition, the parameter list, the parameter reference, the tail-loop
store, the `ptrtoint` of a function value, the three `call` sites, and
the effect slot's global with its loads and stores. Compiler-generated
names (`_lam_N`, `_thunk_N`, `%aN`, `label_N`) are deliberately not
routed: they are inside the set by construction.

Three things were measured rather than assumed:

- **Quoting, not mangling, and it holds on all four targets.**
  `define i64 @"foo'"`, `%"n'"` and `@"g!x"` through
  `llc -mtriple=<t> -relocation-model=pic -filetype=obj` exit 0 for
  `arm64-apple-macosx14.0.0`, `x86_64-apple-macosx14.0.0`,
  `aarch64-unknown-linux-gnu` and `x86_64-unknown-linux-gnu`, at `-O0`
  and `-O2`, and `nm` shows `_foo'`, `_a+b` and `_set!` surviving into
  the object intact. So the symbol a debugger shows is still the name
  the programmer wrote, which a `$`-escaping mangle would have cost.
- **The change is a no-op on this tree, to the byte.** The compiler's
  own IR — 2,342,271 bytes — is *identical* emitted by a compiler with
  `llvmSym` and one without, and contains zero quoted names, because all
  1,625 distinct top-level names in `stdlib/` and `self_host/` are
  already inside the unquoted set, and `Mod$name` is too (`$` is in both
  sets). That is why `check-bootstrap.sh`'s IR identity and
  `check-reproducible.sh` cannot move. The census is the `fn`/`define`
  heads and the `::` subjects over the 35 files of those two trees,
  deduplicated — 1,426 declarations and 1,674 signatures, 1,625 distinct
  names between them, **0** carrying a byte outside `[-A-Za-z0-9$._]`
  and 0 carrying an operator byte at all. (§15.1's neighbouring figure
  of 1,629 was counted before this section's work added `llvmSym`'s four
  helpers and removed one; the reproducible number is the one above.)
- **The registry key and the emitted name are separate.** An effect slot
  is both a global's name and the key `slotFirstIndex` dedups on, so the
  quoting happens at emission and the key stays bare; quoting the key
  instead would make the global's definition and its loads disagree.

`scripts/check-symbol-names.sh` is the gate, and it asks the question
the corpus cannot. For each of the **94 printable bytes** — not the
sixteen `isIdentChar` admits, because which bytes those are is the other
side of the agreement and has to be free to move — it builds three
probes: the byte inside a function name, at the start of one, and inside
a parameter name. Each must reach exactly one of two outcomes: refused
by `check` with a code *and a span into the probe*, or accepted **and**
built **and** run to 42. There is no third outcome, and "accepted, then
killed by `opt`" was the third outcome for twelve bytes.

Which arm applies is decided by `symbols`, not by consulting the lexer:
if the frontend reports a function whose name is exactly the probe's,
the frontend accepted that *name*, and the backend is then obliged to
emit it. Asking `isIdentChar` what it admits and then checking codegen
against that answer would be one implementation grading itself — the
error this whole section is about. Measured: of the 282 sweep probes,
217 are accepted, and **every one of them is accepted as a name** —
there is no "accepted, but a different program" case to weaken the
assertion.

Seven further probes carry the constructs a three-character name cannot
reach: a self tail call (the parameter is stored into its alloca by
name), a lambda capturing a prime-suffixed binding, a constructor, a
nullary reference, a function value (`ptrtoint` plus the thunk's call),
an effect slot, and the same program at `--opt 2`. One more asserts the
quoting is *minimal* — a plain name still emits `@plain`, since
everything else here passes just as well from a `llvmSym` that quotes
unconditionally, and that version would rewrite every symbol in the
bootstrap.

The ablation drill ran against the ablated **tree**, not merely with an
ablated compiler: `llvmSym` reduced to the identity in a scratch copy,
the compiler under test built from that copy. Exit 1, **42 of 290** — 35
sweep probes (exactly the 35 that need quoting in a good build, so the
two halves account for each other with nothing left over), the five
structural probes, `--opt 2`, and the quoted-path floor reading 0 where
the floor is 12. Restored: 290/290.

Two checks deliberately do *not* move under that ablation, and the file
says so rather than letting a reader over-credit them: "plain names are
unquoted" is an over-quoting check, which the identity satisfies; and
the constructor probe passes, because a constructor is a tag rather than
an emitted symbol.

### 15.3 The third pass, found by the fixture written for the second

`tests/selfhost/366-operator-names.ax` was added to pin §15.2 cheaply,
and `check-fmt.sh` went red on it. That was not the fixture being wrong.
The formatter is a **fourth** implementation of the identifier rule, and
it disagreed with the lexer in the way that costs the most: not by
refusing, but by rewriting.

`fscanName` (format.ax) continued a name over `isFNameChar` — letters,
digits, `_` and `'` — a local restatement that omitted every one of the
operator bytes `isIdentChar` admits. So a name containing one was three
tokens to the formatter and one to the compiler, and the formatter
printed the three. Measured against the compiler as it stood, output
written to disk, **exit 0, no warning**:

| written | `fmt` wrote | what the compiler reads |
|---|---|---|
| `(fn (g) (h empty-list))` | `(fn (g) (h empty - list))` | a 3-argument call where there was 1 |
| `(fn (g) (h a+b))` | `(fn (g) (h a + b))` | a 3-argument call where there was 1 |
| `(fn (g) (h x-5))` | `(fn (g) (h x -5))` | a 2-argument call where there was 1 |

This is the roadmap §2.3 list — the six ways `fmt` silently destroyed a
source file — in a seventh way, and it is the worst-shaped of them
because **`empty-list` is not an exotic name.** Kebab-case is the
commonest non-alphanumeric naming convention there is, and
`(:: empty-list (-> Int Int))` is a declaration `axiom check` accepts
and runs. In declaration position the same split poisoned the buffer
instead, so `axiom fmt` *refused every file that declared such a name* —
which is how a formatter reports that it cannot round-trip a construct,
and is the only reason this was not worse.

Nothing in the repository has such a name. All 244 `.ax` files formatted
byte-identically with this broken, because Axiom's own convention is
camelCase — the same sentence §13, §14 and §15.1 each already record,
now for the fourth time in one document.

**The fix is one line and an import**: `fscanName` asks `lexer`'s
`isIdentChar`, which is exactly the continuation set it wants, and the
local `isFNameChar` is deleted rather than corrected. Correcting it
would have left two statements of one rule and a note asking the next
person to keep them equal; deleting it leaves one. That is §15.1's
repair applied to the pass §15.1 did not cover.

Measured, the same way the `llvmSym` change was: formatting all **244**
`.ax` files under a compiler with the fix and one without produces
**byte-identical output and identical exit status on 243 of them**, the
single difference being `366-operator-names.ax` itself, which goes from
`formatter refusal` to formatted. The `-5` adjacency rule the scanner
exists to preserve is unmoved in both directions — `(+ x -5)` stays two
arguments and `(+ x - 5)` stays three.

**What is deliberately not fixed, and is a real residue of the same
kind.** The dispatch still routes an operator-*initial* token to
`fscanOperator`, which consumes only operator bytes. `isIdentStart`
admits those same twelve bytes, so `+foo` and `-foo` are each one
identifier to the lexer — measured, both compile and run — and two
tokens here. Stated plainly rather than softly: this is still a
rewrite, not merely a split. Measured after the `fscanName` fix,

```
(fn (g) (h +foo))   ->   (fn (g) (h + foo))
```

written to disk at exit 0, exactly as the table above. In declaration
position it refuses, as before.

It is left alone because it is not the one-line change `fscanName`
took, and getting it wrong is worse than leaving it. The lexer's rule
for an operator-initial token is conditional — measured, `(+ 40 -5)` is
**35**, so `-` followed by a digit is a negative literal, while `-foo`
is a name — so a scanner that simply continued over `isIdentChar` after
an operator run would fuse `-5` into an identifier and silently change
every negative literal in the corpus, which is a far larger blast
radius than the defect it repairs. `? ~ $` are also operator bytes to
this scanner and not identifier bytes at all. So it needs the lexer's
*conditional* mirrored, and a probe bank over `-5`, `--5`, `+5`, `->x`
and the adjacency cases, which is a slice with its own gate.

What bounds it: no name in the corpus, and none in any probe written
for §15.2, starts with an operator byte and continues with a letter.
`scripts/check-symbol-names.sh` sweeps names in the two positions the
frontend can *declare* them, and every one of those starts with a
letter or the operator run alone.

## 16. The one editor feature this server has, that no editor would ask for

`axiom lsp` answers `textDocument/documentSymbol` correctly - the
outline is right, its `SymbolKind`s are right, and a 6,001-symbol
document comes back intact. Its `initialize` reply advertised

```json
{"capabilities":{"textDocumentSync":1},"serverInfo":{...}}
```

and nothing else. A conforming client reads that object and sends only
what it names, so the one feature this server has that is not a
diagnostic was implemented, gated, and requested by nobody.

`check-lsp-selfhost.sh` could not see it, and the reason is worth
stating because it is not the usual one. The gate was not vacuous and no
golden was wrong: every fixture sends `documentSymbol` unconditionally,
the way no editor does, so the goldens faithfully record a conversation
that cannot happen. **The gate spoke the protocol; it did not obey it.**

One line adds the capability. The assertion that keeps it is in
`tests/lsp/drive.py`, in the one session that holds both halves at once
- the large-document session sends `initialize` and then
`documentSymbol` - and it is bidirectional: a request the server answers
with a result must be advertised, and the check reads both sides out of
the same run, so no re-bless can satisfy it.

The drill ran. With the capability removed and **every golden re-blessed
from the ablated build**, the bless itself refused and the gate still
failed:

```
FAIL large-document (177,817 bytes): the server answers
textDocument/documentSymbol and does not advertise
documentSymbolProvider, so a conforming client never sends it:
capabilities were ['textDocumentSync']
```

This is the third defect this session that lived in the gap between two
implementations of one agreement - the parser and the formatter (§13),
the lexer and the AXTAG scanner (§15), and now the server's promises and
the server's behaviour. The pattern each time is that both sides were
tested against a third thing (a golden, a corpus) and never against each
other.

## 17. `(true)` is a pattern the compiler runs and the grammar refused

`tests/selfhost/365-macro-pattern-literal.ax` was written to pin a macro
hygiene bug about `true` and `false` in pattern position. Adding it to
the tree took `check-tree-sitter.sh` from 243/243 to **243 of 244**, and
the one failure was the new file:

```
tests/selfhost/365-macro-pattern-literal.ax   (ERROR [23, 27] - [23, 33])
```

The span is `((true`, in this line:

```scheme
(macro (isTrue b) (match b ((true) 1) ((false) 0)))
```

which is a complete, running program — the fixture answers 95 — and
which the editor grammar called a syntax error. Probed one shape at a
time against the grammar as it stood:

| arm pattern | grammar | compiler |
|---|---|---|
| `((Nil) 0)`, `((Just x) x)` | ok | ok |
| `(true 1)`, `(_ 7)` | ok | ok |
| `((true) 1)`, `((false) 0)` | **ERROR** | ok |
| `((_) 7)`, `((1) 10)` | **ERROR** | ok |

The cause is a modelling difference rather than an oversight in a list.
This grammar describes patterns *structurally* — `wildcard_pattern`,
`constructor_pattern`, `tuple_pattern` — and the parenthesised form was
reachable only through `constructor_pattern`, which requires a
`constructor_identifier` (`[A-Z][A-Za-z0-9_']*`). Nothing beginning
`true`, `false`, `_` or a digit can start one. But **Axiom does not
parse patterns structurally**: `parseArmPattern` falls back to
`parseExpr`, so a pattern is an expression that is later *read* as a
pattern, and the nullary-constructor spelling `(Nil)` is therefore
available to a literal too. `emitPattern` then compares the scrutinee
against 1 or 0 for the two boolean names.

The repair is one rule, `parenthesized_pattern`, wrapping a literal or a
wildcard. It cannot be ambiguous against `constructor_pattern` for the
reason the bug existed: the two token classes are disjoint. Pinned by
corpus case 21 in `tree-sitter-axiom/test/corpus/expressions.txt`, which
carries all four shapes and reads them back as
`(parenthesized_pattern (boolean_literal))`,
`(parenthesized_pattern (integer_literal))` and
`(parenthesized_pattern (wildcard_pattern))` rather than as an
acceptance count.

### 17.1 The count that keeps going up

This session touched **four** implementations of one grammar, and found
three of them disagreeing with the compiler in three different ways:

| implementation | how it disagreed | how it showed |
|---|---|---|
| `codegen.ax` | wrote names LLVM cannot read | `AX4003` from `opt`, after `check` said OK (§15.2) |
| `format.ax` | split names at operator bytes | **rewrote the program**, exit 0, no warning (§15.3) |
| `tree-sitter-axiom` | no parenthesised literal pattern | ERROR on source that runs (§17) |
| `lexer.ax`/`parser.ax` | — | the reference the other three were measured against |

Each was invisible for the same reason, now recorded for the fifth time
in this document: the corpus is written by people solving problems, so
it contains only the constructs those problems needed. No repository
file has an operator-charactered name, and none had a parenthesised
literal pattern until a fixture written for an unrelated bug introduced
one.

The useful generalisation is not "add more cases". It is that **a
fixture written for one implementation is a probe of every other**. 365
was written to test macro hygiene and found a grammar bug; 366 was
written to test codegen and found a formatter bug. Neither gate was
vacuous and neither golden was wrong — the files simply had not existed
before, and the moment they did, three passes disagreed with them.

### 15.4 The rule was also wrong in the two places that explain it

Writing the identifier section of `docs/reference.md` — which had never
stated the character set at all, only "names are lowercase by
convention" and three examples — meant checking the set against the
lexer. Doing that surfaced two more statements of it, both inside the
compiler, and both wrong in *both* directions.

The inline help on `AX1001` (`parser.ax`) read:

> identifiers may contain letters, digits, `_`, and `'`; operators are
> built from `+ - * / % ^ = < > ! & | . ? ~ @`

and the long-form `axiom explain AX1001` (`explain.ax`) read:

> Axiom identifiers may contain letters, digits, `_` and `'`; operators
> are built from a fixed set of symbol characters.

Both say an identifier cannot contain an operator byte, which is false —
`set!`, `foo'` and `empty-list` are names, and that is the whole subject
of §15.2 and §15.3. Both present operators as a separate lexical class,
which this language does not have: `+` *is* an identifier, which is why
`(+ a b)` needs no precedence table and why the tree-sitter grammar has
none. And the first lists four bytes as operator characters that the
lexer will not accept anywhere — measured, `?`, `~` and `@` are each
`AX1001`, and `.` is not an operator at all but a token, so `tmp.1` is
`AX2001 expected expression, found `.`` rather than a lexer error.

So the help printed *by the diagnostic that fires when you get the
identifier set wrong* was itself wrong about the identifier set, in the
direction that would send a reader looking for the mistake in the wrong
place. That is the same shape as the rest of this section — a second
statement of one agreement, drifting because nothing compares it to the
first — with the sharpening that these two statements exist *only* to
describe the rule, so being wrong is their whole failure mode rather
than a side effect.

Both now state the lexer's set, and say the thing that makes it make
sense: operators are not a separate class. The reference gained an
Identifiers section that states it too, with the exclusions and the
reason for each. Four goldens across two fixtures move
(`800-unexpected-char` and `930-tab-indent`, `.axdl`/`.human`/`.json`)
plus `tests/tools/explain.golden`, regenerated by replaying
`check-tools-selfhost.sh`'s own loop; the regenerated golden differs
from its predecessor in exactly the `AX1001` block and nowhere else,
checked by diff before it was installed.

No behaviour changes and no code path moves — which is worth stating
plainly, because it means the gates could not have caught any of this.
A help string is compared only against a golden, and a golden records
what the compiler said, not whether it was true.

### 15.4 The rule was also wrong in the two places that explain it

Writing the identifier section of `docs/reference.md` — which had never
stated the character set at all, only "names are lowercase by
convention" and three examples — meant checking the set against the
lexer. Doing that surfaced two more statements of it, both inside the
compiler, and both wrong in *both* directions.

The inline help on `AX1001` (`parser.ax`) read:

> identifiers may contain letters, digits, `_`, and `'`; operators are
> built from `+ - * / % ^ = < > ! & | . ? ~ @`

and the long-form `axiom explain AX1001` (`explain.ax`) read:

> Axiom identifiers may contain letters, digits, `_` and `'`; operators
> are built from a fixed set of symbol characters.

Both say an identifier cannot contain an operator byte, which is false —
`set!`, `foo'` and `empty-list` are names, and that is the whole subject
of §15.2 and §15.3. Both present operators as a separate lexical class,
which this language does not have: `+` *is* an identifier, which is why
`(+ a b)` needs no precedence table and why the tree-sitter grammar has
none. And the first lists four bytes as operator characters that the
lexer will not accept anywhere — measured, `?`, `~` and `@` are each
`AX1001`, and `.` is not an operator at all but a token, so `tmp.1` is
`AX2001 expected expression, found `.`` rather than a lexer error.

So the help printed *by the diagnostic that fires when you get the
identifier set wrong* was itself wrong about the identifier set, in the
direction that would send a reader looking for the mistake in the wrong
place. That is the same shape as the rest of this section — a second
statement of one agreement, drifting because nothing compares it to the
first — with the sharpening that these two statements exist *only* to
describe the rule, so being wrong is their whole failure mode rather
than a side effect.

Both now state the lexer's set, and say the thing that makes it make
sense: operators are not a separate class. The reference gained an
Identifiers section that states it too, with the exclusions and the
reason for each. Four goldens across two fixtures move
(`800-unexpected-char` and `930-tab-indent`, `.axdl`/`.human`/`.json`)
plus `tests/tools/explain.golden`, regenerated by replaying
`check-tools-selfhost.sh`'s own loop; the regenerated golden differs
from its predecessor in exactly the `AX1001` block and nowhere else,
checked by diff before it was installed.

No behaviour changes and no code path moves — which is worth stating
plainly, because it means the gates could not have caught any of this.
A help string is compared only against a golden, and a golden records
what the compiler said, not whether it was true.

## 18. `fmt` moved a decimal point, and every gate was green

Measured and fixed 2026-08-10. `axiom fmt` is the tool a company runs on
every commit, and on one shape it silently changed what the program
computes:

```
$ cat fl.ax
(:: main Int)
(fn (main) (let ((x 0.05)) (if (< x 0.1) 42 7)))

$ axiom fmt fl.ax
OK: fl.ax formatted

$ grep 0. fl.ax
    (let ((x 0.5))

$ axiom run fl.ax; echo $?
7                              # it was 42
```

Exit 0 from the formatter, exit 0 from the program, no warning, no
diagnostic. A tenfold change in a rate, a tolerance or a threshold, and
the only review signal is the literal itself.

### 18.1 One helper, two jobs, one of them wrong

`fpFloat` printed the integer part and the fractional part with the same
routine, `fpDigits`, whose contract is *drop `_` separators and leading
zeros, keeping at least one digit*. That is exactly right for an integer
part — `007` and `7` are the same number, and normalising the spelling is
the formatter's job. On a fraction the same rule changes the value:

| written | printed | |
|---|---|---|
| `0.05` | `0.5` | ×10 |
| `0.0583` | `0.583` | ×10 |
| `1.050` | `1.5` | ×10, and the trailing zero legitimately gone |

The fraction now goes through `fpFracDigits`, which drops `_` and
nothing else. Trailing zeros still go, because the cut is computed
before the digits are emitted and that half was always right; `007.50`
is still `7.5`, and `1_0.0_5` is still `10.05`.

### 18.2 Why five gates were green

The corpus contains **no float literal with a leading zero in its
fractional part outside a comment.** The only two occurrences in the
repository — `0.0583` in `codegen.ax` and `0.05` in `Fmt.ax` — are both
inside prose. So `check-fmt.sh` could format all 255 files, re-run every
suite, and see nothing, because nothing it formatted had the shape.

This is the class §10 and §13 already name, sharpened: the corpus is
written by people solving problems, so it contains the shapes those
problems needed. Sixty-two float literals, all of them `1.5`, `2.5`,
`0.5`, `4.0` — the shapes a benchmark table and a float test need.

And `fmt`'s own round-trip check could not see it either, which is the
part worth keeping. That check re-scans its output and compares the
token stream; `0.5` is a perfectly good float where `0.05` was, so the
scan agrees. **A round-trip check answers "is the output still the same
kind of thing", not "is it still the same thing".**

### 18.3 The gate, and the ablation

Two, at different altitudes.

`tests/selfhost/940-float-literal.ax` is the corpus entry the corpus was
missing: five literals whose value decides whether it answers 42 or 1.
`check-fmt.sh` formats a copy of the repository and re-runs
`check-self-host.sh` against it, so this case turns any recurrence into
a failing test rather than a silent rewrite.

`tests/fmt/verify-fmt.py` gets the general property, and it is the one
the file already exists to provide — a second opinion that reads no
golden. Every float literal in the input and in the output is decoded to
a number and the multisets are compared, so a normalisation of the
SPELLING passes and a change of the VALUE does not. Two details are
load-bearing and both were found by running it:

- **Magnitude, not value.** The printer legitimately fuses a unary minus
  into a literal (`(- 8)` prints `-8`), which moves the sign between the
  expression and the token without changing what the program computes.
  Comparing signed values reported three corpus files.
- **Floats only.** Integer normalisation is value-preserving by
  construction, and counting integers also flags `(- n)` → `(- 0 n)`,
  which introduces a literal `0` without changing a value.

73 float magnitudes over 272 pairs, with a floor of 40, because a
scanner that stops recognising numbers would otherwise pass every time.

The ablation was run rather than assumed: a tree with the old `fpFloat`
and the new gate, bootstrapped and swept, reports

```
940-float-literal.ax: formatting changed the float values:
  lost [(0.05, 1), (0.0583, 1), (1.05, 1)],
  gained [(0.5, 1), (0.583, 1), (1.5, 1)]
```

and exits 1. Restored, it is 0 failures.

Widening `scan`'s return also broke `tests/docs/verify-doc-code.py`,
which loads it rather than copying it — the second consumer doing its
job, and the reason that file loads the scanner instead of duplicating
it.

## 19. A lambda of two parameters was not a lambda

Measured and fixed 2026-08-10. Every lambda in this repository takes one
parameter — 97 of them — so nothing had ever asked what two did. The
answer was: nothing coherent, in two different ways depending on which
path the program took.

```
$ cat L2.ax
(:: main Int)
(fn (main) (let ((f (lambda (x y) (+ x y)))) (f 20 22)))

$ axiom check L2.ax
error[AX3004]: type mismatch: expected (_t0, _t1), found Int
```

`checkLam` typed a multi-parameter lambda as taking a **tuple**
(`typecheck.ax`, the `(vecLen ptys)` cascade), so calling it the way it
was written is a type error naming a type the programmer did not write
and cannot supply — Axiom has no tuple expression syntax.

That is the loud half. The quiet half is worse. On any path that got
past the checker — and the uniform-representation rule makes `cast Int`
an ordinary thing to write — the emitter produced no lambda at all:

```
$ cat F2.ax
(:: main Int)
(fn (main) ((cast Int (lambda (x y) (+ x y))) 20 22))

$ axiom check F2.ax
OK

$ axiom emit-llvm F2.ax -o F2.ll
$ sed -n '/define i64 @__axiom_user_main/,/^}/p' F2.ll
define i64 @__axiom_user_main() #0 {
  ret i64 22
}
```

No `_lam_` function, no call, the application folded to its last
argument, exit 0. README called lambdas **Complete**, citing
`tests/stdlib/140-function-values.ax`, which passes — every lambda in it
takes one parameter.

### 19.1 The fix is the definition

A lambda of several parameters *is* several lambdas. `(lambda (x y) b)`
is now parsed as `(lambda (x) (lambda (y) b))`, in `parseLamExpr`, the
way multi-binding `let` is already parsed as nested single-binding lets
twenty lines below it.

Nothing else had to move, and that is the argument for this shape rather
than a new representation. The curried type is what the language already
claims (`(-> Int Int Int)` is `Int -> (Int -> Int)`, right-folded, and
`arrowDepth` has always counted it that way). The closure
representation already implements it: each lambda is lifted to a
`_lam_N` with a hidden `%_env` first parameter and captures **everything
in scope by value**, so the inner lambda captures the outer parameter
exactly as it captures any other enclosing binding — no free-variable
walk to get wrong. And `emitApplyChain` already applies one argument at
a time through the record's code pointer, because each application may
yield another closure.

Zero parameters stays one lambda: `(lambda () b)` is a thunk, and
currying nothing would answer the body.

`tests/selfhost/950-multi-param-lambda.ax` pins five terms that each
fail differently — two parameters, three, an inner lambda capturing an
enclosing `let` binding, a partial application whose intermediate value
is the inner closure, and an inner parameter shadowing a same-named
outer binding. It answers 42, and against a compiler built from
`2192d61` it does not compile at all.

The formatter is untouched and does not need to be: `format.ax` prints
from its own scanner over the source text, so `(lambda (x y) ...)` is
still written and read the way it was.

### 19.2 What this did not fix, and what came next

Two things were left measured at `53438d8` and are fixed in §20. One
claim recorded here was simply **wrong** and is corrected below.

The `cast Int` case still answered 22, for a reason that turned out not
to be about lambdas at all — see §20.

`(let ((f (lambda () 42))) (f))` answered a heap address — also §20.

**Corrected.** This section previously said that a lambda passed to a
function whose parameter is declared `Int` is `AX3004` because "the
checker has no way to say this parameter is callable". That is wrong,
and the fix is to write the type: `(:: applyTo (-> (-> Int Int) Int Int))`
declares the parameter as a function and the call type-checks, which is
how `tests/stdlib/140-function-values.ax` has always written it. The
`AX3004` was a correct refusal of a signature that said `Int`, and the
probe that produced it was mine, written wrong. Re-measured: a
two-parameter lambda through a properly typed higher-order function
answers 42.

## 20. A spine is not a call, and three heads read it as one

Fixed 2026-08-10, immediately after §19 and found by it.

`walkAppChain` flattens a whole application spine into one argument
accumulator and then dispatches on its head, so `((cast Int f) 41)`
reaches the `cast` branch as `[Int, f, 41]` rather than `[Int, f]`.
That branch emitted the **last** argument — right when there is no
surplus, and wrong the moment there is:

```
((cast Int f) 41)      41   -- and `f` takes ONE parameter
((cast Int f) 20 22)   22
(sizeof Int 99)         8   -- the surplus argument dropped in silence
```

All three `check`-clean, at exit 0. The first is the one that matters:
`cast` is the documented way to move a function value through a plain
`Int`, the uniform-representation rule makes it ordinary to write, and
applying the result is the only reason to do it. So the shape that was
broken is the shape the feature exists for.

`cast` now consumes its two arguments and applies anything beyond them
to its result, one at a time — `emitApplyChain` already takes a start
index, and already applies one argument per step because each
application may yield another closure. `tests/selfhost/960-cast-application.ax`
pins one surplus argument, two through a two-parameter lambda, and a
`cast` with no surplus at all.

### 20.1 Two other implementations already knew

`sizeof` and `alignof` answer a compile-time constant, so a surplus
argument has nowhere to go and is now `AX3008` rather than being
discarded. What makes this worth recording is where the rule already
existed: **`format.ax` refuses `(sizeof Int 99)` outright** (its arm
requires `fnLen == 2`) and **the tree-sitter grammar parses it as an
ERROR node**. Two of the grammar's implementations had encoded the
arity and the checker had not, which is §10's shape again — and the
fixture proved it by failing `check-fmt` and `check-tree-sitter` the
moment it was added as a `.ax` file. It lives as `.axbad` for exactly
that reason.

### 20.2 A lambda of no parameters can never be called

`(lambda () b)` was accepted, lifted to a `_lam_N`, and evaluated to the
closure record's **address**: `(let ((f (lambda () 42))) (f))` answered
16 at exit 0, and `((lambda () 42))` the same.

There is no way to call one, and that is a property of the syntax
rather than a gap in the emitter: **`(f)` and `f` are the same
expression** — a one-element list is its head — which is exactly how a
bare reference to a nullary top-level `fn` calls it, and `vecNew`,
`mkIntTy` and every other nullary function in this repository is
written bare. So there is no spelling left that means "apply this
closure to nothing".

It is therefore refused, with a span on the `lambda` keyword. Getting
that span took a second pass: the node was built with `mkNode`, which
carries none, and `check-render-selfhost.sh` **refused the bless** —
"a golden claims a span the fixture does not have", and four caret-row
assertions besides. A diagnostic with no snippet is not a diagnostic
anyone can act on, and the gate would not let one through.

Zero nullary lambdas exist in the repository — the census that made
refusing them safe — and `check-degenerate.sh`'s `empty-lambda-params`
case, which asserted exit 0, now asserts the refusal. Its subject is
unchanged either way: that an empty parameter list does not take the
compiler down.

## 21. Expansion had a depth cap and no budget, and the pass after it ran anyway

Fixed 2026-08-10. `expand.ax` has had a recursion limit since the macro
port — `AX3019`, 128, for a macro that rewrites to itself — and it
bounds the wrong thing. Two well-formed inputs got past it:

```
(macro (m x) (+ x x))            ; 26 nested invocations, 154 bytes
(fn (main) (m (m (m ... 1))))
```

Doubling per level, so 2²⁶ forms. Measured on `875b79b`: **41.4 s** in
`check`, rising 4× per two levels, and the language server simply never
answered. Depth never exceeds 26, so `AX3019` cannot see it.

```
(macro (g x) <500 deep>)         ; invoked 120 times, 3.5 KB
```

Depth 620 in the file and **60,000 in the tree**. `AX2005` refuses
source past 1024 and this source is nowhere near it — the parser
measures what was written, and expansion produces what was not.
Measured: `SIGSEGV`, no output, from `check`, `run`, `symbols` **and
`axiom lsp`**.

### 21.1 Two budgets, on the output

`expandExpr` recurses structurally, so the depth of its walk *is* the
depth of the tree it is building. It is now a thin wrapper that counts
the node, tracks that depth on the way in and out, and stops at the
limits rather than at the guard page; `expandExprInner` is the walk
that was there before.

- **Depth 1024**, deliberately the parser's own `parseMaxDepth`:
  expansion must not produce a program the parser would have refused.
- **Size 2,000,000 forms**, which no depth limit can see, because
  fan-out is flat.

Both are far above any real macro — the whole of `stdlib/Pre.ax`
expands to depth 1 — and the refusal is `AX3024`, reported once rather
than at every node after it.

### 21.2 The guard fired and the crash moved

With both budgets in, the 3.5 KB file **still** `SIGSEGV`d, and the
guard was not at fault. `lldb -b -o run -o "bt 8"` put the crashing
frame in `typecheck$spineArgVec` — the **checker**, not the expander.

`compileFile` merged expansion's diagnostics with the checker's and
decided afterwards, so the checker ran over a tree expansion had
already given up on. The rule that was missing is the general one: **a
pass that refused does not hand its output to the next.** `check`,
`symbols` and the language server each had their own copy of the merge
and each needed it; the server's copy matters most, because a server
that dies stops answering.

That single change also took the fan-out case from 12.2 s to 0.0 s —
the wait was never the expansion, it was the checker walking two
million abandoned nodes afterwards.

### 21.3 What the survey got wrong, and how it looked right

The scout that found these reported the second one as "macro expansion
bypasses the AX2005 nesting guard", which is true of the *input* and
wrong about the *crash*: the crash was one pass later, in code that had
nothing to do with macros. The evidence that looked conclusive was that
`symbols` crashed too and `symbols` does not expand macros — except it
does (`main.ax` expands before checking, so that a listing tool cannot
disagree with `check` about whether a file is well-formed). Two wrong
inferences that cancelled, and only the debugger settled it.

## 22. Traits were a keyword and a comment

Implemented 2026-08-10. `README.md` called traits **Complete** —
"declarations, supertraits, effects, default methods, implementations"
— and the compiler's whole contribution was to consume `impl` and
throw it away:

```scheme
(trait (Eq a) where (eq :: (-> a a Bool)))
(impl (Eq Int) where ((eq (lambda (x y) (== x y)))))
(fn (main) (if (eq 3 3) 42 7))
```

```
error[AX3001]: undefined variable `eq`
```

That is the README's own example, verbatim. `parser.ax` matched `impl`
by name and called `skipUnknownDecl`, so the declaration became an
inert `TAG_NIL`: **its body was never type-checked** — an `impl` of a
trait that does not exist, whose method calls a name that does not
exist, passed `check` at exit 0 — and no trait method was bound to
anything anywhere.

### 22.1 An impl is ordinary declarations

`impl` now parses to `TAG_D_IMPL`, and a pass in `expand.ax` — beside
macro expansion, because it is the same kind of rewrite and runs at the
same point — lowers each one to declarations the rest of the compiler
already understands:

```
(impl (Eq Int) where ((eq <expr>)))
  =>  (:: Eq#Int#eq (-> Int Int Bool))
      (fn (Eq#Int#eq p#0 p#1) ((<expr> p#0) p#1))
```

The signature is the trait's method type with the implementing type
substituted for the trait's parameter, which is what gives the body a
concrete type to be checked against. The definition is **eta-expanded**
rather than having the lambda spliced in, because the implementing
expression need not be a lambda: `(eq myNamedFunction)` is as
legitimate as `(eq (lambda (x y) ...))`, and applying it is the one
thing both shapes support.

The separator is `#`, not `$`, and that is load-bearing: `bareOf` and
`nameMatches` treat `$` as the module boundary, so `Eq$Int$eq` would
suffix-match a **bare** `eq` and whichever implementation resolved
first would silently win every unqualified call. `#` is not an
identifier byte, so a generated name cannot collide with a written one
— which also makes it the test `symbols` uses to leave these out of its
listing.

### 22.2 Dispatch is a rewrite, at compile time

`checkApp` looks at the spine's head: if it names a trait method, the
checker finds the parameter position whose declared type **is** the
trait's own parameter, types the argument there, and rewrites the head
node's name to that implementation's. Everything downstream — argument
checking, saturation, and later the emitter, which reads the same
nodes — then proceeds as for any ordinary call. So a trait call costs a
direct call: no dictionary, no vtable, no indirection.

Only at the spine root. `checkApp` runs at every level of a curried
spine and `spineHead` answers the same node each time, so dispatching
at each level reported the same missing implementation once per
argument — caught by the fixture, which showed the diagnostic twice.

`AX3025` covers every way the pair (trait, type) fails to be usable: an
unknown trait, a method the trait does not declare, a method the impl
does not define, a trait with no type parameter, no implementation for
the dispatch argument's type, and a method whose signature mentions the
trait's parameter in no parameter position — there is no
return-type-directed dispatch, so `(mk :: (-> Int a))` says so rather
than guessing.

### 22.3 What it does not do

- **A function generic over a trait cannot call its methods.** Dispatch
  needs a concrete type at the call site and a type variable is not
  one. That is the dictionary-passing design, and it is a different
  slice.
- **Supertraits and default bodies parse and are dropped.** Every
  method a trait declares must therefore be implemented, which is what
  `AX3025` says when one is missing.
- **One type parameter per trait**, the first.

### 22.4 What the corpus said, once anything asked

`tests/fmt/syntax-zoo.ax` carried `(impl (Show Int) where ((show ...)))`
for a trait declaring `show` **and** `width`. It was a syntax fixture
and syntax was all anyone checked, so the missing method had never been
a problem; the first thing real `impl` checking did was report it. The
zoo now implements both — the fixture becoming a valid program rather
than only a parsable one.

Two other gates spoke up, and both were right:

- **`check-fmt` refused `self_host/typecheck.ax`.** A helper of mine
  took a parameter named `trait`. The parser accepts a keyword as a
  binder and `format.ax`'s scanner refuses the whole file, with no line
  and no reason. Renamed; the disagreement between those two readings
  of a name is recorded here because nothing else compares them.
- **`tests/selfhost/290-emit.ax` failed after formatting**, which
  looked like a formatter bug and was not. `lowerImpls` had been put in
  `typecheck.ax` and called from `codegen.ax`, which does not import
  it; `main.ax` merges every module into one flat namespace, so the
  compiler built and only a program importing `codegen` alone could
  see the hole. The pure helpers now live in `parser.ax` and the pass
  in `expand.ax` — the modules that both consumers already import.

## 23. A signature that promised a function, and a body that answered an Int

Fixed 2026-08-10.

```scheme refused
(:: g (-> Int Int Int))
(fn (g a) a)
(:: main Int)
(fn (main) (g 41 2))
```

`axiom check` said **OK**. Running it was `SIGSEGV`, exit 139, no
output, and the emitted IR says exactly why:

```llvm
%t0 = call i64 @g(i64 41)
%t1 = inttoptr i64 %t0 to ptr
%t3 = load i64, ptr %t1            ; word 0 of "the closure" g returned
%t5 = call i64 %f4(i64 %t0, i64 2)
```

The call site believes the **signature** — two parameters, one of them
consumed by the definition, so the second argument is an application of
the *result* — and the callee is the **definition**, which takes one and
answers an `Int`. The emitter then loads word 0 of `41` as a code
pointer and calls it.

The checker had no opinion because it never compared the two. It peels
a signature's arrows to type the parameters and it types the body, and
those two facts were never put beside each other.

### 23.1 Why arity alone cannot decide it

The obvious check — "the signature has more arrows than the definition
has parameters" — is wrong, and the reason is in the parser: `->` right-
folds, so `(-> Int Int Int)` and `(-> Int (-> Int Int))` are **the same
type**. A function that genuinely returns a closure is written both
ways, and `tests/stdlib/140-function-values.ax` relies on it:

```scheme
(pub :: adder (-> Int (-> Int Int)))
(pub fn (adder n) (lambda (x) (+ x n)))
```

Two arrows, one parameter, and entirely correct. So the question is not
how many arrows there are; it is whether the **body** answers the thing
the signature's result says it does.

### 23.2 The check, deliberately narrow

After the body is checked, its type is compared with the signature's
result — the arrows peeled by as many parameters as the definition has
— and the mismatch is refused **only when the declared result is an
arrow and the body's type is a concrete type that is not one**. A type
variable, poison and a silent wildcard all mean *not known* rather than
*known to be wrong*, and this compiler under-reports on purpose; they
are all left alone.

That is the whole of the segfault shape and nothing else. Measured
against a compiler built from `689934a` over all **263** `.ax` files in
`stdlib/`, `self_host/` and `tests/`: **0 divergences**, so it costs no
existing program a diagnostic. Both spellings of a genuine curried
return still compile and answer 42.

`tests/diagnostics/420-declared-return.ax` pins it, and the message is
the ordinary one:

```
error[AX3004]: type mismatch: expected (Int -> Int), found Int
 --> 420-declared-return.ax:2:11
```

## 24. The three holes module visibility left

§14.5 recorded three things the visibility slice did not cover. All
three are closed here, and one of them was a *widening* that slice
introduced rather than a defect it inherited.

### 24.1 A private macro was visible everywhere

`mangleDecl` rewrites only `fn` and `::`, so a macro's name carries no
module and `resolveDeclsPhase`'s word-5 flag was the only thing that
knew. Nothing read it, so a non-`pub` macro could be invoked from
anywhere — and that was **new**: before §14, the declaration was
deleted outright and a module with a private macro could not be
imported at all, so no program that worked could observe the
difference. It was recorded honestly and left, and this closes it.

The expander now tracks the **invocation site's module** alongside the
definition site it already tracked, and `expFindMacroIn` refuses a
macro its module does not export. The site is set to the *macro's* own
module while that macro's template is walked, so a public macro whose
template invokes a private one of its own module still expands from
outside — the same definition-site rule `expQualify` applies to a
template's free identifiers.

The checker had to move with it, and the reason is the one this
repository keeps writing down. `tcMacros` held name **strings**, so
`isMacroName` said yes to a private macro, the invocation type-checked
as a macro (silent wildcard), reached codegen as a call to a symbol
nothing defines, and failed in `opt` at **exit 4**. That is the same
clean-diagnostic-for-a-link-failure trade §14.2 refused to commit.
`tcMacros` now holds the declaration nodes, and `isMacroName` asks the
same visibility question the expander does — the two have to agree,
because one decides whether the name type-checks and the other whether
it expands.

### 24.2 A private type's constructors said they did not exist

They were already refused — the lookup filters them — but as `AX3001`
and `AX3003`, which say a name does not exist when it plainly does.
Both sites now name the module, like every other private reference.

### 24.3 An import's name list was never read again

`resolveDeclsPhase` used it to decide visibility and nothing checked
it, so `(import M (noSuch))` was accepted in silence: the mistake
surfaced as an `AX3001` wherever the name was used, or as **nothing at
all** if it never was, which is exactly what a typo in a list of
otherwise-good names looks like. The entry file's import lists are now
checked against what each module declares and exports, with the two
cases told apart:

```
error[AX3023]: module `VisAll` declares no `noSuchName`
error[AX3023]: module `VisAll` declares `privMac` but does not export it
```

That needed the import declaration to carry a span, which it never had
— `mkDImport` used `mkNode`. It carries the module path's token now,
for the same reason the nullary lambda needed one in §20.2: a
diagnostic with no snippet is one the render gate will not bless.

Measured against a compiler built from `4f29a2a` over all 263 `.ax`
files: **0 divergences**. The corpus has no private macro, no private
type and no import name list, which is §14.1's census again and the
reason all three could sit here unnoticed.

## 25. The other two halves of a trait declaration

§22.3 listed supertraits and default method bodies as parsed and
dropped. Both work now, and the second one turned on a detail of the
lowering that had been arbitrary until it was not.

### 25.1 Defaults, and why eta-expansion was not enough

`(ne :: (-> a a Bool) = (lambda (x y) (if (eq x y) false true)))` is
the whole reason defaults exist: `ne` is that expression for every type
there will ever be, and every implementation had to write it out. The
parser had always parsed the default and thrown it away.

It is kept now, and an implementation that omits the method gets the
default lowered for its type exactly as a written one would be. That is
where it stopped working the first time:

```
opt: error: use of undefined value '@eq'
  %t9 = call i64 @eq(i64 %t2, i64 %y)
```

§22.1 lowered an implementing expression by **eta-expansion** —
`(fn (Eq#Int#ne p#0 p#1) ((<expr> p#0) p#1))` — chosen because the
expression need not be a lambda. But a default's body calls the trait's
*other* methods, and dispatch needs the argument's type: under
eta-expansion the argument is a lambda parameter, whose type is a fresh
type variable, so `(eq x y)` could not be dispatched and reached codegen
as a bare `@eq`.

So the lowering now **splices the lambda's own parameters and body**
when the expression is a deep-enough lambda — `(lambda (x y) b)` is
`(lambda (x) (lambda (y) b))` after the parser's currying, so peeling
`arity` of them gives both. The generated definition's signature is the
trait's method type with the concrete type substituted, so those
parameters are typed `Int` and the inner call dispatches. Anything that
is not a deep-enough lambda — `(eq myNamedFunction)` — is eta-expanded
as before. The splice also removes a closure allocation per call on the
common path, which was a real cost nobody had priced.

### 25.2 Supertraits are a requirement on the implementation

`(trait (Ord a) (Eq a) ...)` means every type with an `Ord`
implementation must have an `Eq` one. The list was skipped by the
parser, so it declared nothing:

```
error[AX3025]: trait `Ord` requires `Eq`, and there is no `impl (Eq Int)`
```

The first head name of the group before `where` is kept. Only the
first: a second parenthesised group there is an effect list, and
nothing in the syntax distinguishes them beyond position — which is a
limitation of the grammar rather than of this check, and is recorded
rather than guessed at.

### 25.3 The check from §23 caught its own author

Adding a parameter to `checkImplComplete` and forgetting to widen its
`::` produced, immediately:

```
error[AX3004]: type mismatch: expected function type, found Int
  --> self_host/expand.ax:1224:18
```

which is the diagnostic added two commits earlier for exactly that
mistake, working on the compiler that introduced it. Before it, the
same slip compiled and segfaulted at the call site.

## 26. Division by zero meant two things, and neither was said

Fixed 2026-08-10.

```scheme refused
(:: zero Int)
(fn (zero) 0)
(fn (main) (printlnInt (/ 10 (zero))))
```

```
$ axiom check   OK
$ axiom run     1
```

`sdiv` and `srem` with a zero divisor are **undefined** in LLVM, and
the two targets disagree about what undefined looks like: on
darwin-aarch64 that program prints `1` and exits 0, and the same IR on
linux-x86_64 lowers to `idiv`, which raises `SIGFPE`. A program
developed on macOS and shipped to Linux changed its meaning on the way,
and nothing in the compiler had an opinion about it.

`/` and `%` now compare the divisor against zero and branch to a shared
trap that writes `axiom: division by zero` to fd 2 and exits **72** —
one status along from the unhandled-effect trap's 71, and emitted the
same way, through the target's own syscall template.

The cost is one predictable branch per division, paid only by `/` and
`%`. Measured on `emit-llvm self_host/main.ax`, same input, a compiler
built with the guard against one built without: **1.79–1.89 s versus
1.80–2.00 s** — inside the run-to-run spread. The fixpoint holds and
all 263 `.ax` files check identically.

### 26.1 The trap was emitted where the effects are

The first version put the helper beside `__axiom_unhandled_effect`,
which reads well and is wrong: that one is emitted **only when the
program declares an effect**. Every program that divided and used no
effects reached `opt` with a call to a symbol nothing defined —

```
opt: error: use of undefined value '@__axiom_div_by_zero'
```

— which the first probe after the change found, because a probe that
runs the program is the only thing that could. It is emitted with the
arena helpers now, which every program gets.

## 27. Four ways `fmt` and `check` disagreed about the language

Fixed 2026-08-10. §10 named the rule — *a formatter is a second
implementation of the grammar, and the only thing that keeps the two in
agreement is a corpus that uses every rule* — and these are four rules
the corpus does not use.

| written | `check` | `fmt` before |
|---|---|---|
| `;@axiom:pure()` above `(import M)` | accepted | **deletes the AXTAG** |
| `(- x)`, `x` not a literal | negation | **rewrites to `(- 0 x)`** |
| `(fn (x) ...)` in expression position | accepted | **refuses the whole file** |
| a `\v` or `\f` byte | `AX1001` | **accepts and rewrites** |

Each is a different kind of wrong and the third and fourth are worth
separating: refusing a valid file is loud and merely infuriating,
whereas accepting an invalid one **turns a program the compiler rejects
into one it accepts**, which is the rewrite a formatter may never make.

- **The AXTAG** was collected and discarded, with a comment saying
  stage0 attached none to `DImport`. Whatever the parser does with it,
  an AXTAG is a *comment the programmer wrote*, and preserving comments
  is the formatter's one contract. `verify-fmt.py` counts AXTAGs among
  the comments it compares and could not see this, because no file in
  the corpus has one above an import.
- **`(- x)` → `(- 0 x)`** is a different expression: the parser reads
  the first as negation and the second as a subtraction, and on a
  `Float` operand the second is `Int - Float`, which does not
  type-check. A *literal* still takes its sign back — `(- 3)` prints
  `-3` — because that is the same number spelled shorter, not a
  different expression.
- **Expression-position `fn`** is a spelling `parseInner` accepts and
  documents ("stage0 spells an anonymous function `lambda`; expression
  position `fn` is stage1's older spelling and both stay"). The printer
  knew only `lambda`, so every file using it was refused with no line
  and no reason, by the tool a CI formatting gate runs.
- **`isFSpace`** admitted VT and FF, inherited from the retired
  compiler's `char::is_whitespace`; `lexer.ax`'s `isSpace` never did.
  It is now that function, byte for byte.

`tests/selfhost/985-fmt-agreement.ax` is the first three as a **running
program**, which is the only way to state what the disagreement cost:
`check-fmt.sh` formats a copy of the repository and re-runs that suite,
so a rewrite that changes meaning stops the answer being 42.
`tests/fmt/parity/176-vt-ff-whitespace.axp` is the fourth, in the bank
whose whole subject is refusals.

One corpus golden moves — `870-ascription-and-negation.ax`, which
contains the `(- n)` this fixes — and the parity bank gains a case.
Nothing else in 288 formatted files changes.

## 28. Three documented examples that had never parsed

Fixed 2026-08-10. `tests/docs/verify-doc-code.py` checks that every
Axiom code block in `README.md`, `docs/reference.md` and
`CONTRIBUTING.md` balances its delimiters, and its own docstring says
why it stops there: most blocks are fragments, a fragment is not a
module, and balance is the property fragments and modules share — and
it needs no compiler, which is what lets it run in the grammar job that
gates every other job.

Balance cannot see an example that parses and means nothing. Three did:

| documented | what it is |
|---|---|
| `(fn main (println "a") (println "b") 0)` | `AX2003`. A multi-expression body needs the parenthesised name: `(fn (main) ...)`. The prose around it is about *implicit sequencing*, so the example was the whole point |
| `(fn main (printf "hello"))` ×3 | `printf` is not a function in this language. `README.md` says so, eleven sections later: "No FFI and no `printf`" |
| the `effect(io)` and sequencing blocks | no `(import IO)`, so `println` is undefined and the AXTAG claim it demonstrates cannot hold |

### 28.1 The compiling half, and where it runs

A block is now compiled when it **declares a `main`** — a block
claiming to be a whole program — and opts out by tagging its fence
```` ```scheme fragment ````. Three do, and each for a reason worth
keeping: the two halves of the multi-file `Math.Ops` example need a
companion file, and the AXTAG **syntax** block is deliberately not a
program (`(def legacyFn ...)`).

It is opt-in on a compiler path so the grammar job keeps its property
of needing none; `check-tools-selfhost.sh`, which already builds a
compiler, passes it. 114 blocks balance, **17 of them whole programs
that compile**, with a floor of 12 — because a `main` test that stops
matching would otherwise leave a compile check that compiles nothing
and passes every time.

Ablated by putting `(fn main` back in one example: `FAIL doc snippet
README.md:392: does not compile: AX2003`, exit 1. Restored, 0.

## 29. A signature named a representation the body did not produce

Fixed 2026-08-10.

```scheme refused
(:: f (-> Int Float))
(fn (f x) 42)
(fn (main) (println (fmtFloat (f 1))))
```

```
$ axiom check   OK
$ axiom run     0.000000
```

The answer should be `42.000000`. `checkDeclaredReturn` compared a
declared result type against the body's inferred type only when the
declared result was an **arrow** — the shape §23 added, where a signature
promising a function over a body answering an `Int` segfaulted the call
site. Every other declared result type returned `0` before looking at the
body at all, so a signature naming `Float` over a body answering `Int`
was never checked, the integer bit pattern was handed to `fmtFloat` as a
double, and 42 as a double bit pattern is a denormal that prints
`0.000000`.

`Bool` is the same defect one step quieter:

```scheme refused
(:: b (-> Int Bool))
(fn (b x) 42)
(fn (main) (if (b 1) 7 9))
```

exits **7**, having read 42 as `true`.

Every *other* position already refused both. A `Bool` parameter given an
`Int`, a `Float` parameter given an `Int`, and a `Float` or `Bool` struct
field given an `Int` are all `AX3004` today, because they route through
`tyCompat`, which compares two `TAG_T_CON`s by name. The return position
was the only one that did not ask.

### 29.1 Why the obvious fix is unsound, measured

Comparing the declared result with the inferred one through `tyCompat` —
the same relation every other position uses — reports **21 of this
repository's 271 `.ax` files**, and not one of them is a bug. `Int` is
this language's universal heap-handle type, and the tree relies on it.
The compiler's own:

```scheme
(pub struct Span (start : Int) (end : Int))

(pub :: mkSpan (-> Int Int Int))
(pub fn (mkSpan start end)
  (Span start end))
```

declares `Int` and answers a `Span`; `Job.ax`'s `jobPoolNew` answers a
`JobPool` through an `Int` signature the same way; `(alloc Int 1)` answers
`*mut Int` through one. The handle convention is *implemented by the
absence of this check* — the call site believes the signature, so the
declared `Int` is what every reader downstream sees, and the body's real
type never has to agree.

That is why the rule names the two constructors that are **not** handles.
`tyReprClash` refuses only a pair of argument-free `TAG_T_CON`s with
different names where either name is `Bool` or `Float`. Anything applied
(`Box Int`), any arrow, tuple, list or pointer, and anything either side
does not know — a type variable, poison, a silent wildcard — stay
permitted. Swept old-versus-new over all 271 files: **0 divergences**.
A full `AXIOM_BLESS=1` run of `check-diagnostics.sh` and
`check-render-selfhost.sh` rewrote **none** of the 80 existing golden
sets, which is the same fact from the other side.

`tests/diagnostics/425-declared-return-repr.ax` carries both clashes in
one fixture. Against a compiler built from `6c9294f`'s sources it answers
`OK` at exit 0, so the golden's two `AX3004` lines cannot be satisfied by
the old code.

### 29.2 What this does not reach

A declared result the checker cannot resolve at all. `AX3002
undefined-type` has exactly **one** construction site in `typecheck.ax`,
and it is the `(struct Name ...)` *expression*, so a type constructor
named in a signature is never resolved against anything:

```scheme refused
(:: g (-> Nonexistent Int))
(fn (g x) 1)
(fn (main) (g 5))
```

is accepted, and the diagnostic that eventually arrives is `AX3004` at
the **caller's** line, blaming the caller's `Int` for the declarer's
typo. The same hole is why `type` aliases do not work: `tcAliases` is
pushed to and never read, so `(type Count = Int)` declares a name that
compares equal to nothing, and `docs/reference.md` promises the opposite
("It does not create a new type — `StringList` and `[String]` are
interchangeable"). `explain.ax`'s own `AX3002` text already documents the
check that does not exist: "This type name does not refer to any built-in
type, `data`, `struct`, or `type` alias visible in this module."

Resolving type-constructor names in signature and annotation position is
one pass that closes both, and it is the next slice rather than this one —
it needs a decision about parameterised aliases and it moves diagnostics
on programs this one leaves alone.

## 30. A type name in a signature was never resolved against anything

Fixed 2026-08-10.

```scheme refused
(:: g (-> Nonexistent Int))
(fn (g x) 1)
(fn (main) (g 5))
```

```
$ axiom check
error[AX3004]: type mismatch: expected Nonexistent, found Int
 --> u.ax:4:15
  |
4 | (fn (main) (g 5))
  |               ^ this has type `Int`, expected `Nonexistent`
```

The typo is on line 1 and the diagnostic is on line 4, blaming the
caller's `Int` for the declarer's mistake. `parseTypeAtom` turns every
capitalised name that is not one of `typeKeywordCanon`'s primitives into
a bare `TAG_T_CON` (`parser.ax:1261-1266`), and nothing ever asked
whether it named anything: **`AX3002 undefined-type` had exactly one
construction site in `typecheck.ax`, and it is the `(struct Name ...)`
expression.** No signature, annotation or field type had been resolved
against the type namespace at all — which is also why `explain.ax`'s own
`AX3002` text ("This type name does not refer to any built-in type,
`data`, `struct`, or `type` alias visible in this module") described a
check that did not exist.

`tcCheckSigTypes` now runs once after `tcCollect`, because a signature
may name a type declared later in the file or in another module. It
reports the first unresolvable constructor per signature:

```
error[AX3002]: undefined type `Nonexistent`
 --> u.ax:1:5
  |
1 | (:: g (-> Nonexistent Int))
  |     ^ no type named `Nonexistent` is visible here
```

Type **variables** need no check — `lexStartsLower` sends every
lowercase-initial name to `TAG_T_VAR` before this can see it, so the
subject is exactly the capitalised names. The diagnostic sits on the
signature's own name span because a type node carries no span of its own
(`mkTCon` is `mkNode`, not `mkNodeAt`), and only the first bad
constructor in a signature is named: pointing several at one span would
print the same caret twice.

Existence is asked **ignoring visibility** — `findDataFrom` and
`findStructFrom` skip their privacy filter when `privs` is 0. Reaching a
type another module keeps private is `AX3023`'s subject, and answering
`AX3002` for it would say "no such type" about one that exists.

### 30.1 The cascade this had to suppress

The first version reported the AX3002 and then let every call site
report as well: one bad signature and four calls gave **five errors**,
which is the cascade the poison discipline at the top of `typecheck.ax`
exists to prevent, and which the sibling AX3002 site already avoids by
answering `TAG_T_ERR`. `tyPoisonUnknown` rebuilds the signature with each
unresolvable constructor replaced by poison and stores that in `FnEnt`
word 1, so the declaration is the only thing reported.

The arrow shape is preserved rather than poisoning the type wholesale,
because `peelArrows` and `bindFnParams` read it and a *non-arrow*
signature means "every parameter is `Int`" to them — poisoning wholesale
would quietly retype the parameters instead of excusing them. A fresh
tree is built rather than the nodes edited, because the declaration's own
`ty` slot is what `symbols` renders and only the checker's copy should
carry poison. Verified: `axiom symbols` is byte-identical on all **272**
`.ax` files.

### 30.2 The check immediately found a type the documentation promises

`tests/fmt/syntax-zoo.expected.ax:393` declares `(:: unitArg (-> Unit
Int))`, and `Unit` was **not** in `typeKeywordCanon`. Both `README.md`
and `docs/reference.md` document it as a type; `format.ax:2259` prints
it; the parser's canonical list omitted it, so it became a bare
unresolvable constructor that nothing had ever asked about. Four
implementations, and the only pair anything compared was the formatter
against the corpus.

`Unit` is now in the list, canonicalising to itself. It is deliberately
**not** made equal to the empty tuple, which is what
`docs/reference.md`'s "`Unit` / `()`" spelling claims they share. They do
not, and did not before this — `symbols` already renders `(:: a (-> ()
Int))` as `(() -> Int)` and `(:: b (-> Unit Int))` as `(Unit -> Int)`.
Naming the type the documentation promises is a no-op on every golden;
making the two one type is a semantic change with goldens behind it. Only
the first is done here.

### 30.3 What this does not reach, and why aliases are still a slice

`type` aliases remain opaque. An alias name now counts as *known*, so it
draws no AX3002 — an alias is a declaration and saying "undefined type"
about it would be false — but `tcAliases` is still read by nothing else,
so `(type Count = Int)` declares a name that compares equal to nothing
and `docs/reference.md:807`'s promise that an alias and its target are
interchangeable is still false.

Making it transparent is a larger change than it looks, and the reason is
in the node beside the type. `parseSigDecl` stores per-arrow **float
flags** in the declaration's `b` slot, reconstructed at *parse* time
because float-ness of a value is not observable at runtime and there is
no type checker left by emission time; codegen keys on that exact shape.
Expanding `(type F = Float)` in the checker alone would have the checker
say `Float` where the emitter still says `Int` — trading a missing
diagnostic for a wrong answer, which is the trade this repository twice
records as the wrong one. The alias slice therefore has to expand where
the flags are computed, or recompute them, and that is a decision with a
measurement behind it rather than a line.

Struct field and `data` constructor argument types are also still
unresolved. Measured, so the size is known: **50** `struct`/`data`
declarations and **214** annotated fields in `self_host/` + `stdlib/`,
with zero undeclared type names among them.

## 31. The outline scanned the document once per position

Fixed 2026-08-10.

`lspPos` answered both halves of an LSP position by scanning from byte 0.
`lspLine` calls `diag.lineOf`, which counts newlines from 0; `lspChar`
called `lineStartOf`, which scans from 0 to rediscover the line start it
then walks forward from. `lspRange` calls `lspPos` twice, and
`lspDocumentSymbols` called `lspRange` twice per symbol — so an outline
cost **four whole-document scans per symbol**, and publishing N
diagnostics cost 4N.

Measured over a real JSON-RPC pipe, `textDocument/documentSymbol` alone:

| symbols | documentSymbol | whole `didOpen` (parse + check + publish) |
|---:|---:|---:|
| 1,002 | 0.03 s | 0.01 s |
| 2,002 | 0.13 s | 0.02 s |
| 4,002 | 0.54 s | 0.05 s |
| 8,002 | **2.22 s** | 0.20 s |

At 8,002 symbols the outline cost **eleven times the entire frontend**.
On this repository's own files: `parser.ax` 0.082 s, `typecheck.ax`
0.166 s, `codegen.ax` 0.185 s. The shape is symbols × document length,
at about 8.0M line-steps a second — not a mystery quadratic but exactly
the product of the two loops.

`lspLineIndex` records, in one pass, the offset at which each line
begins. A position is then a binary search and no scan: the line is the
largest index whose offset is at or below the byte, and the character
count starts from that offset instead of rediscovering it.

| file | symbols | before | after |
|---|---:|---:|---:|
| `parser.ax` | 246 | 0.085 s | 0.001 s |
| `typecheck.ax` | 309 | 0.184 s | ~0.000 s |
| `codegen.ax` | 275 | 0.192 s | 0.008 s |

The index is built per **request** and deliberately not cached: the
server reclaims the arena at every message boundary (`lspSnapshot`), so
an index kept across messages would point into storage the reset has
handed back. It is a `while` loop, not a recursion, because its depth
would be the line count and this backend eliminates only self tail
calls.

`lspDiagJson` now takes the index rather than building one, because its
caller reports every diagnostic in the file and building it per
diagnostic would keep the whole cost the index exists to remove.

### 31.1 The gate asserts a ratio, not a stopwatch

Everything `check-lsp-selfhost.sh` already pinned is about what the
server *answers* — and all of it stayed green through this change,
including the two invariants it checks on every symbol of the
6001-symbol generated document and the seven positions it recomputes in
Python from the fixtures' own bytes. That is the half that proves the
index computes the same answers, and it needed no widening.

What nothing pinned was the *cost*. The new section measures two
sessions on the same machine in the same run and requires the outline
request to cost no more than the whole parse-and-check of the same
document. `didOpen` does strictly more work, so a correct index makes
this comfortable and the quadratic makes it impossible. An absolute
millisecond ceiling would have been a machine-speed assertion wearing a
performance costume.

It proves the work happened before reporting the number, because a
server that answers no symbols is extremely fast: the outline must carry
at least 2,000 symbols or the section fails rather than passes. That
floor immediately caught an error in the section itself — the generator
produced one symbol per function, not two, so the first version measured
1,051 symbols against its own floor of 2,000 and refused.

**Ablated** against `ef9e53e`'s `lsp.ax` in the same tree: **11.19×,
exit 1**, against 0.10× restored. The rest of the gate passed in *both*
runs — 10 passed, 0 failed, every derived position correct — so the new
section fails only for its own reason, which is the property this
repository keeps having to check about its own gates. The 11.19× also
independently reproduces the "eleven times the frontend" figure measured
by hand above, from a different document and a different harness.

### 31.2 Non-ASCII, because the columns are the subtle half

LSP characters are UTF-16 code units, and the index only supplies the
line and the line's start — `lspCharFrom` still walks code points from
there. A document mixing two-byte (`é`), three-byte (`中`) and
four-byte (`😀`, a surrogate **pair**, so two units) sequences, with
declarations on lines after them, produces byte-identical protocol
streams before and after. So do all four of `render.ax`, `parser.ax`,
`typecheck.ax` and `codegen.ax`.

### 31.3 What this does not fix

`didChange` still re-parses and re-checks the whole import closure from
disk on every keystroke, caching nothing. Per-edit cost tracks closure
**bytes**, superlinearly: 27 KB 0.003 s, 168 KB 0.016 s, 344 KB 0.049 s,
565 KB **0.369 s**. The older note that this "tracks the import count"
had the mechanism right and the units wrong.

It is deliberately not fixed here. The declared next LSP slice is a
node-to-type table for hover, definition and completion, because
`typecheck.ax` keeps no map from node to type; a cache designed before
that table exists is likely the wrong cache at the wrong granularity,
and building it twice costs more than 42–163 ms a keystroke does.

## 32. Name resolution was three linear scans of a 1,600-entry table, per reference

Fixed 2026-08-10.

`findFnEnt` answered every name reference with up to three full linear
scans of `tcFns`: the module-local `Mod$name` exactly, then the bare name
exactly, then the `$`-suffix pass. On a self-check that table holds about
1,600 entries, and the module-local key was rebuilt with two `strConcat`
allocations per lookup.

A per-call-site sampling profile of `axiom check self_host/main.ax` put
**83% of the program in the two EXACT passes** and under 5% in the suffix
one. So only the exact passes are indexed, and `findFnEntSuffix` is left
byte-for-byte as it was.

That split is the whole design. Indexing an exact match is a statement
about string equality and nothing else. Indexing the suffix pass would
mean reasoning about where `$` falls in a name that module mangling has
already rewritten, and about which of several matches wins — in the
function whose own comment says getting this wrong "is not a missing
diagnostic, it is a link failure".

```
$ axiom check self_host/main.ax     0.89s  ->  0.17s      5.2x
```

The emitted IR is **byte-identical** on all 71,494 lines, `check` output
is identical on all 273 `.ax` files, and `axiom symbols` is identical on
all 273. Peak RSS moves 107.1 → 107.3 MB, so the index is free.

### 32.1 Buckets, because the table is built once

Buckets rather than open addressing: nothing is ever deleted, so probing,
tombstones and growth would be machinery for cases that cannot arise.
Each bucket keeps insertion order and the scan takes the first match,
which is what the linear scan answered — and it **has** to be, because
`tcAddEffectOp` pushes with no presence test, so two entries legitimately
share a name and only the first was ever reachable.

The hash is the shape `stdlib/Intern.ax` uses — a multiplicative hash
with an odd multiplier, reduced mod 2³¹−1 at every step — spelled out in
`typecheck.ax` rather than imported. Importing `Intern` pulls `Map` with
it and puts 63 declarations into six entry files' import closures for one
hash function, in a flat namespace that already carries five separate
`fmtInt`s. Intern's own note explains why the running value stays under
the prime: a value below 2³¹ times a multiplier below 2³¹ is below 2⁶²,
so nothing overflows into the sign bit before the `%` brings it down, and
no negative index can reach `vecGet`.

Every push to `fns` now goes through `tcPushFn`, which updates the index
too. Nothing pushes after the index exists today, but a lookup against a
stale index is a wrong answer rather than a slow one, and that is not a
property to leave resting on an ordering.

### 32.2 The index is built BEFORE collection, and that mattered

The first version built it after `tcCollect`, which is the obvious place:
by then every entry has been pushed. It measured the same 5.2× on
`main.ax` — and left a second quadratic standing, because `tcCollectSig`
and `tcCollectFn` each look a name up *before* deciding whether to push.
With the body-checking scans gone, collection becomes the dominant cost
on a single large module. Measured on a generated module of N
cross-referencing functions, before this correction: N=1000 0.05 s,
N=2000 0.15 s — a ratio of 3.0 where linear is 2.0.

Building it in `tcNew` needs the eventual size in hand, because the table
holds only about sixty builtins at that point and these buckets never
grow. The **declaration count** is the hint: every `::` and `fn` in the
program contributes at most one entry, so it is an upper bound, and the
average bucket stays well under one. Same module, after: N=1000 0.01 s,
N=2000 0.03 s.

### 32.3 The synthetic sweep measures a different quadratic

A generated file of N functions in the **entry file** barely moves —
0.19 s → 0.14 s at N=4000 — and that is not a disappointment, it is the
answer to a question worth recording. That shape is quadratic in
`checkDuplicates`/`firstDefiner` and `checkMissingDefs`/`isDefined`,
which scan the entry file's own declarations, and `main.ax` has 21 of
those against a 1,326-function closure. **Two independent quadratics, and
the one that dominates real programs is the one fixed here.** Anyone
re-measuring with an N-function entry file will conclude nothing changed;
the shape that shows it is a large module reached through an import.

### 32.4 What is left, and what is not guarded

Still linear, deliberately: `findFnEntSuffix`, at under 5% of the
profile; and `findFnEntVisibleExact`/`Suffix`, which only run when a
program declares something private — the count of those in this
repository is zero, and the module-local lookup is indexed on that path
anyway.

**This change has no gate of its own, and that is a considered choice
rather than an omission.** Its correctness is pinned comprehensively by
gates that already exist — identical diagnostics over 273 files,
identical `symbols`, and byte-identical IR through the bootstrap
fixpoint — so a wrong index cannot pass. Its *speed* is what nothing
asserts. Every candidate was measured and rejected: peak RSS does not
move, so the `check-bootstrap` 400 MiB pattern cannot see it; the ratio
of `main.ax` to `typecheck.ax` separates only 22.0× from 8.5× with
`typecheck.ax` at 0.02 s, which is timer resolution; and a doubling-ratio
assertion needs an 8,000-function generated module to make both timings
stable, which is a size this repository has independently measured a
stage1-built compiler dying at. A perf gate that flakes is worse than a
measurement written down with the probe that produced it, which is what
this section is. `scripts/bench-compile.sh` is the tool if the number is
ever in doubt.

## 33. `--input` was documented for one subcommand and swallowed by all of them

Fixed 2026-08-10.

```
$ axiom emit-llvm --input hello.ax
error: emit-llvm needs an input file        exit 1
$ axiom check --input hello.ax
error: check needs an input file            exit 1
```

`flagArity` is one table for the whole command line, so `--input` is
paired with the argument after it for **every** subcommand — that is what
makes `axiom build --opt banana` fail before any work happens, and it is
not per-subcommand. But only `build` ever read the flag back. `check`,
`emit-llvm` and `run` took a bare positional, and the operand scan had
already skipped the `--input FILE` pair, so the filename vanished
between the validator and the subcommand.

The same shape as `build -o PATH` writing to `output`, and as
`--emit-llvm FILE` reading the filename as a flag value: a flag the
help documents and the binary discards.

Per-subcommand flag **ownership** would be the complete fix and is the
wrong one. It was measured and dropped once already: it flips five
`check-driver` assertions written the same day — the legacy
no-subcommand spelling legitimately takes `--emit-llvm`, `--check`,
`--builtins` and `--list` — while fixing nothing a user can see. The
weaker rule that kills the class is to accept the flag wherever a file
is expected, which is what `inputOperand` does, and the usage text now
says `(build, check, run, emit-llvm)` rather than `(build)`.

`check-driver.sh` passes 75/75 unchanged, including its anti-drift
assertion that every name in the accept chain appears in `--help`.

## 34. How much stack the compiler needs, as a number

`scripts/check-stack-depth.sh`, new 2026-08-10.

This backend eliminates only **self** tail calls, and a `let` body is not
a tail position (`codegen.ax`'s `tailCallsSelf`, deliberately — following
it re-executed `alloca` per iteration for `mut` bindings). So

```scheme
(let ((e (vecGet v i))) (if ... e (recur ...)))
```

costs one real stack frame per loop iteration, and that is the shape
almost all of `typecheck.ax` is written in — a file with **no `while` at
all** — so a dozen of its table walks are one frame per table entry.

Three SIGSEGVs in this repository's history are that shape, and each
presented as a crash in whatever was being compiled rather than in the
walk: `memCopyFrom` on a few hundred KB, `lookupByIdx` twenty-five frames
deep in stage2, and `scanAxtagsFrom` one frame per source byte.

**Nothing measured it.** The obvious response — convert every such walk
to a `while` — is a large diff across the most correctness-critical file
in the tree, to buy headroom nobody had priced. So it was priced first:

```
check self_host/main.ax needs 216 KiB of stack (ceiling 1024 KiB)
and dies by 139 at 108 KiB, as it must
```

216 KiB against an 8 MiB default is roughly 36× headroom. The
conversions are not urgent. Knowing when that stops being true is, and
that is now one number in CI.

The gate bisects the minimum stack at which `check` succeeds and reports
it either way, so a change that doubles the requirement is visible in the
log before it is a failure. Two halves keep it honest: the successful run
must print `OK`, because a compiler that exits 0 having done nothing
needs very little stack; and at **half** the discovered minimum the
process must die by SIGNAL rather than merely non-zero, because without
that the bisection could report any number and the ceiling would still
pass — a run that failed for an unrelated reason looks identical to one
that ran out of stack.

The ceiling is deliberately loose at 1 MiB. The property is "nothing
recurses per program element", not "this host's frame layout"; a tight
ceiling would be a gate about the machine.

### 34.1 The ablation found a bug in the gate

Ablated by patching a copy with a 64 KiB ceiling: it failed, exit 1, with
the right number — and printed

```
      and prefer a  over a -bound tail call.
./scripts/check-stack-depth-ABL.sh: line 130: syntax error: unexpected end of file
```

Three of its `echo` lines quoted `while`, `let` and `check $subject` in
**backticks inside double quotes**, which is command substitution, not
quotation. All three were on failure-only paths, so the clean run could
never reach them. That is the same class as `AX4001` sitting in the code
table with no construction site, and as the three flags `usageText`
documented while the binary ignored them: **a message you only see when
something breaks is untested until you break it.** Fixed, re-ablated,
and the failure text now reads as intended.

### 34.2 What this slice deliberately did not do

Three items were surveyed with it and are recorded rather than half
done.

`unitIndexForFrom` (`typecheck.ax`) returns **0 for both "not found" and
"the entry file"**, so a diagnostic about a module whose unit was never
registered would render against the entry file's bytes at the module's
offsets — silent wrong output. It has one caller, and no input reaching
it has been found: `units` is built from the resolved import list, so
every module in a program is in it. Recorded as a latent sentinel
ambiguity of the same family as `mangledForIn` returning its argument
unchanged, not fixed, because a fix with no reachable case is a fix with
no test.

`dieImport` (`codegen.ax`) still writes to fd 2 and exits 3, bypassing
every diagnostic collector — inconsistent with the parse-error port,
which gave parse failures a code and a span at exit 1. Giving codegen a
diagnostic channel is a slice, not a line.

`inferEffectsPass` puts its recursive call inside a `let` **binding**,
which is precisely the shape recorded above as having crashed
`lookupByIdx`. It is on the list because it is the one site where the
conversion is justified on its own merits rather than as part of a sweep
— and with 36× headroom now measured and gated, it can wait for a change
that touches that function for another reason.

## 35. Four documented declarations vanished, and `check` said OK

Fixed 2026-08-10.

```scheme
(trait (Ord a)
  (Eq a)
  where
    (cmp :: (-> a a Int))
    (lt :: (-> a a Bool)))
```

That is `README.md`'s and `docs/reference.md`'s own example of a trait
with several methods. On the compiler before this change:

```
$ axiom check   OK
$ axiom symbols <no Trait row at all>
```

The declaration was **discarded in silence**. `parseTraitRest` reads
`where` and then exactly ONE parenthesised group of method signatures; a
group per method does not match, so it fell through to
`skipUnknownDecl`, which consumes the form and answers `TAG_NIL` — a
successful parse of nothing. Three more documented forms did the same:
the multi-method `impl` example in both files, and `(type Count Int)`
written without the `=` that `parseAliasDecl` requires.

**`check` cannot see this, because a discarded declaration is not an
error.** Only `axiom symbols` can, by not printing a row — which is why
the discriminator for a declaration form is `symbols`, never `check`.
That is the same lesson as `(impl ...)` being consumed inertly forever
until `parseTopForm` shed its own version of this tolerance, and the
same one `parseSigDecl` records in its comment: *a type this parser
cannot read is a parse error.*

There were **22** of these fallbacks, all inside `parseAliasDecl`,
`parseTraitRest` and `parseImplRest`. Every one is now a refusal, so the
form above is `AX2003` with a span on the `trait` keyword.

### 35.1 The tolerance was holding nothing

Converted and swept over every `.ax` file in the repository: **0 of 273
change behaviour.** The corpus population of every shape the tolerance
covered is zero, which is precisely why it survived — the compiler is
written by one consumer solving its own problems, and that consumer never
wrote a trait with two method groups.

So the change that would have been risky is free, and the four examples
that were broken were broken *because* nothing in the tree used them.

### 35.2 What was actually wrong with the examples, isolated

The grammar is fine and the documentation was nearly right. Probing each
axis separately:

| form | result |
|---|---|
| supertrait, one group, split over lines | **OK**, 1 Trait row |
| supertrait, one group per method | `AX2003` |
| no supertrait, one group (the docs' *single*-method example) | **OK** |
| `impl`, one group, two methods | **OK** |
| `impl`, one group per method | `AX2003` |

Supertraits work. Newlines are irrelevant. The *only* defect is **a
parenthesised group per method where the grammar wants one group holding
them all** — and the single-method example, which both files show first,
is correct, which is why the pair read as consistent.

Both files' examples are corrected to one group, and the corrected blocks
were extracted from `docs/reference.md` verbatim and compiled: `check`
OK, two `Trait` rows. A documentation fix that is not run through the
compiler is the defect it is fixing.

### 35.3 Pinned, and the ablation

`tests/diagnostics/427-trait-group-shape.axbad` and
`428-alias-missing-eq.axbad`, both `.axbad` because they deliberately do
not parse and `check-fmt` and `check-tree-sitter` sweep every `.ax`.

Against a compiler built from `34280eb`'s sources both answer **`OK`
with zero declaration rows**, so the goldens' `AX2003` cannot be
satisfied by the old code. That is the ablation, and it is also the
clearest statement of the defect: the old compiler was silent, and
silence is what a golden cannot record.

### 35.4 Two more documented forms that do not parse, and one stale claim

Found by the same sweep, recorded rather than fixed because each is a
language decision rather than a defect:

* **`deriving` as a top-level form** (`docs/reference.md:768`) is
  `AX2003`. `parseTopForm` has no `deriving` head; only the
  inside-`data`, parenthesised spelling is accepted, and it is consumed
  and dropped — which `reference.md:1101` already says.
* **`newtype`** is in the keyword table at `reference.md:244`,
  `format.ax` formats it and rewrites it to `data`, and the tree-sitter
  grammar parses it — and `parseTopForm` has no head for it, so it is
  `AX2003`. Three implementations accept a form the compiler refuses.

And one claim that is simply out of date: `reference.md:993` says
"Stage1 does not parse `effect`/`handle` yet - neither form appears in the
self-hosting subset." Both halves are false.
`tests/selfhost/820-effect-handlers.ax` is in the corpus, and the
self-hosted compiler checks it OK and runs it to 42.

### 35.5 Two readings of my own that were wrong

Recorded because the corrections are the useful part. Probing `effect`, I
read `symbols` printing no row for an `effect` declaration as the same
silent-discard defect — it is not; `symbols` has no effect row at all, so
the discriminator does not apply there. And I wrote a `handle` in the
shape `(handle ((op handler)) body)` and read the resulting error as a
defect in the documented syntax; the real form is `(handle BODY
(Effects) HANDLER)`, which is what both the corpus and
`reference.md:946` show. Two false positives, from the same habit the
repository already warns about: a probe that fails proves the probe ran,
not that the subject is broken.

### 35.6 The gate that named what the tolerance was holding

`check-degenerate.sh` failed on this change, three cases of 88, and it
was right to:

```
FAIL empty-trait:     check exited 1, want 0
FAIL empty-impl:      check exited 1, want 0
FAIL empty-type-decl: check exited 1, want 0
```

`(trait T)`, `(impl T)` and `(type)` are a recognised keyword with a
shape the parser cannot read, and the bank asserted they were
**accepted** — because when those expectations were written,
`skipUnknownDecl` swallowed them and answered `TAG_NIL`. The three `0`s
were the tolerance, written down as a requirement.

They are `1` now: `AX2003` with a span on the keyword, exit 1, no signal
on any of the three. The bank still holds its floors — 88 cases against a
floor of 80, ten distinct diagnostic codes against a floor of six, and
both outcomes still present, which is the check that stops the bank
becoming all-refusals.

This is the third time in this repository's history that converting a
tolerance made a gate fail and the gate turned out to be encoding the
defect: `parseTopForm`'s version broke the syntax zoo on `(impl ...)`,
`parseSigDecl`'s broke a fixture that had passed a struct handle to
`__load64`, and this one asserted that three malformed declarations were
fine. **A gate written while a tolerance was alive records the tolerance
as a promise.**

## 36. A trait method name captured every call with that spelling

Fixed 2026-08-10.

```scheme
(trait (Sz a) where (sz :: (-> a Int)))
(impl (Sz Int) where ((sz (lambda (n) 111))))

(fn (main) (let ((sz (lambda (q) 7))) (sz 5)))
```

`7`, by every rule the language has: a `let` binding shadows whatever the
name meant outside it. The compiler answered **111**, at exit 0.

So did the same program with `sz` a function parameter, and the same
program with `sz` a top-level `(fn (sz n) 7)` — the last of those with no
`AX3006` either, so two definitions of one name coexisted and the
implementation won every call in silence. A fourth shape broke a valid
program outright:

```scheme
(import Str)
(trait (Len a) where (strLen :: (-> a Int)))

(strLen "abcd")   ;; want 4
```

```
error[AX3025]: no implementation of `Len` for `String`
```

Declaring a trait method made that spelling globally unavailable —
parameters, `let` bindings, top-level functions and imported
standard-library functions alike.

### Why

`checkApp` dispatched before it resolved:

```scheme excerpt
(let ((_td (if (&& (== headIsVar 1) (== inHead 0))
               (traitRewrite tc e head (nodeA head))
               0)))
```

`traitRewrite`'s first act is `findTraitOwning (tcTraits tc) hname`, and
if a trait owns the spelling it mutates the head node to the
implementation's mangled name. Trait dispatch **is** name resolution — it
decides which definition a name means — but this call asked no scope and
no declaration list. `checkVar`, two hundred lines away, has always asked
`scopeFindFrame` first and reaches its trait arm only as the last resort;
`checkSaturation`, twenty lines below the dispatch call, has always
guarded on `scopeFindFrame` too. The rule existed in the file twice. The
third consumer re-derived it and got it wrong, which is the shape
`docs/self-hosting.md` records for effect operations and macro heads —
the two other users of `mkSilentWild`, named in `typecheck.ax:31-37`.

### The fix

`traitNameFree` asks the two questions that mean "already taken":

* `scopeFindFrame` — a parameter or a `let` binding, which shadows;
* `findFnEnt` — a real declaration. A trait method is never itself in
  `tcFns` (an `impl` lowers to `Trait#Type#method`, and `checkVar`'s
  trait arm exists precisely because the bare name resolves to nothing),
  so a hit here is always something else.

and dispatch runs only when both say no.

That leaves the top-level collision, which is not a resolution question
but a declaration one. A trait declares one value name per method, so
`declDefinesNS` — the namespaced twin of `declDefines`, which already
knew an `effect` declares its operations — reports each of them, and
`checkDuplicates` grew the loop that a multi-name declaration needs.
`declDefSpan` points the "first defined here" label at the `where`
entry rather than at the trait's own name, because that is the line the
reader has to change.

### What it cost

Nothing measurable, and nothing at all in the corpus: `(trait` and
`(impl` have a population of **0** in `self_host/` and `stdlib/`, and a
273-file old-vs-new sweep of `check` output and exit status diverged on
**0** files.

### What pins it

`tests/selfhost/971-trait-name-scope.ax` asserts the **value** — a `let`
binding, a parameter and an imported `strLen` answering 7, 7 and 4, plus
two dispatching calls that answer 111 and 222 as the control, since a
guard written too wide turns dispatch off and takes them with it. On the
compiler before the change it exits 1 with three `AX3025`s.

`tests/diagnostics/445-trait-method-duplicate.ax` pins both orders of the
collision — the `fn` after the trait and the trait after the `fn` — because
they reach the report through different arms, and one arm working while
the other stayed silent is what hid this.

## 37. An effect operation was registered with no type and no arity

Fixed 2026-08-10.

```scheme
(effect Two
  (two :: (-> Int Int Int)))
```

```
(two 3 4 5)   over-applied    check OK, exit 0  ->  run exit 139 (SIGSEGV)
(two 3)       under-applied   check OK, exit 0  ->  run exit 0, prints 4332585008
                                                    and 4340662320 on the next run
(two 3 4)     correct         run exit 0, prints 12
```

A nondeterministic heap address delivered as the program's answer, at
exit 0, and a segmentation fault from a program the checker called
fine.

A third shape, `docs/reference.md:917`'s own promise, was not
implemented at all: a top-level `fn` whose name collides with an
operation was accepted, built, and trapped at run time with **exit 71,
no stdout and no stderr**.

### Why

```scheme
(pub fn (tcAddEffectOp tc name effName)
  (tcPushFn tc
    (cast Int (FnEnt name mkSilentWild (- 0 1) 0 1 ...))))
```

Wildcard type, arity **-1**. The source recorded it as a deliberate
under-report, and for the TYPE that is a defensible one. For the
ARITY it is not a missing diagnostic, it is a missing bound: `-1`
means "not measurable", so `checkSaturation` skips the operation and
`checkApp`'s arrow walk has no arrow to run out of.

The declared arrow was never missing. `parseEffectDecl` builds two
parallel vectors — `ops`, the bare names, and `opFields`, TAG_FIELD
nodes with the parsed types beside them — and `axiom symbols` has
printed `two  (Int -> (Int -> Int))` off the second one since it was
added. The collector took the first. **One registration site
discarding a type the parser already kept**, which is the sentence
§29 writes about `parseSigDecl`, one subsystem over.

### The fix

`tcCollectEffectOps` reads slot c instead of slot b, so an operation
is registered with its declared arrow and `arrowDepth` of that arrow
as its arity. A type the parser could not read still leaves 0 in the
field and still registers the old wildcard at -1: under-report, never
mis-report. Nothing downstream changed — `checkSaturation` and
`tyCompat` were already correct and had simply never been given
anything to work with.

The collision is a declaration question, so it went where §36 put the
trait one: `declFields` now names the two declarations that define more
than one value name — a `trait` through its methods, an `effect`
through its operations — and `checkDuplicates` reports each. Effect
operation fields gained the NAME's span in the parser, the way a
trait's methods have always carried one, because a spanless diagnostic
is a suppressed one.

### What it cost

Nothing: 20 effect declarations across 14 files, and a 275-file
old-vs-new sweep of `check` output and exit status diverged on **0**.
Every effect call in this repository was already saturated and
correctly typed, which is exactly why nothing had ever noticed.

### What pins it

`tests/diagnostics/450-effect-op-arity.ax` (AX3004 over-applied,
AX3013 under-applied) and `tests/diagnostics/455-effect-op-collision.ax`
(AX3006). Each was run individually against the previous compiler:
exit 0, zero diagnostics, both times.

## 38. A type variable in a signature was strictly weaker than `Int`

Fixed 2026-08-10.

```scheme
(struct Pt (x : Int) (y : Int))

(:: bad (-> Int Int))  (fn (bad x) (+ x 1))
(bad (Pt 3 4))          ->  AX3004: expected Int, found Pt,  exit 1

(:: bad (-> a   Int))  (fn (bad x) (+ x 1))
(bad (Pt 3 4))          ->  exit 0, prints 4372529169
```

Replacing `Int` with `a` turned a caught error into a wrong answer.
The struct handle arrived in `x`, `+` added one to a pointer, and the
program delivered an address — while `README.md:1187` listed
"Curried, **polymorphic signatures**" under **Complete** and
`docs/reference.md:307-315` has a section called "Type Variables and
Polymorphism".

### Why

`tyCompat` returned 1 whenever either side was `TAG_T_VAR`, at any
depth. That was deliberate and documented at the top of the file:
there is no substitution, so `Tree a` had to pass against `Tree Int`.
The rule is right for the two variable flavours the CHECKER mints —
`_tN` for a parameter past a signature's arrows, `_fn_N` for a
function with no signature, and the silent `""` for what stage1 cannot
know. All three mean "I have no type here" and must match anything.

A variable the PROGRAMMER wrote means the opposite: *this stands for
one type, chosen by the caller*. Sharing one rule between the two made
the programmer's version the weakest thing in the language.

### The fix

Three flavours, distinguished by the leading `_`, and the
discrimination is by construction rather than by convention:
`parser.ax`'s `lexStartsLower` admits bytes 97-122 and nothing else,
so a source-written type variable always starts with a lowercase
letter and can never collide with a minted one.

* **Rigid in the body.** `tyVarCompat`: two source variables agree
  when they are the same variable; a source variable against a
  concrete type does not. `(+ x 1)` where `x : a` is now AX3004, which
  is where the wrong answer came from.
* **Instantiated at a reference.** `tyInst` mints a fresh `_tN` per
  distinct variable, shared across occurrences, wherever a
  declaration's type becomes a reference's type — the `FnEnt` arm and
  the constructor arm of `checkVar`, and a constructor's field types
  when a pattern binds them. A caller may still pass anything, and
  `(Some 42)` still works.
* **The declared return.** A signature promising `a` may be satisfied
  only by that same `a`. `(:: f (-> a b a))` over `(fn (f x y) y)` was
  accepted and answered `y`.

Poison moved ahead of variables in `tyCompat`. The two orders differ
on exactly one pair — a source variable against `TAG_T_ERR` — and
getting it wrong turns cascade suppression off for every polymorphic
signature.

### What it does NOT do

It does not SOLVE the minted placeholders. `(id 5)` has a wildcard
type rather than `Int`, and a second argument disagreeing with the
first goes unreported: `(f 1 (Pt 3 4))` on `(-> a a Int)` is accepted.
Under-report, never mis-report — the same trade this file records for
effect operations before §37 gave them their arrow.

### What it cost

Nothing measurable — `check self_host/main.ax` is 0.18 s before and
after, because `tyHasSrcVar` answers 0 on a walk of a small type and
that is every type in the repository. Re-derived here: **0 of 1,733**
signatures in `self_host/` + `stdlib/` and **0 of 549** in `tests/`
use a type variable, and there are **0** parameterised `data`
declarations. The only source-shaped variables in the whole system are
the builtin `Option`'s, in `Some : (-> a (Option a))`. A 277-file
old-vs-new sweep diverged on **0**.

### What pins it

Both directions, which is the point:
`tests/diagnostics/460-signature-type-variable.ax` catches the rule
being too NARROW — on the previous compiler it checks clean at exit 0
and runs to exit 17.
`tests/selfhost/972-polymorphic-signature.ax` catches it being too
WIDE: it passes on both compilers, so it was ablated separately by
making `tyInst` the identity, and then fails with three false AX3004s.
A control that cannot fail is not a control.

## 39. A `type` alias answered two different ways, and `Mod::name` reported the ambiguity it resolves

Fixed 2026-08-10.

```scheme
(type Count = Int)
(:: h (-> Count Int))   (fn (h c) c)

(h 42)                          ->  AX3004: expected Count, found Int,  exit 1
(:: mkc (-> Int Count)) (fn (mkc n) n)
(h (mkc 42))                    ->  exit 0, prints 42
```

The same relation gave opposite answers depending on POSITION, because
argument checking compares constructor names through `tyCompat` while
the declared-return check names only `Bool` and `Float`.
`docs/reference.md:808` promises the opposite: an alias "does not
create a new type — `StringList` and `[String]` are interchangeable".
`tcAliases` was filled at collection and read by `axiom symbols` and by
nothing else.

And, one namespace over:

```scheme
(import DupA)
(import DupB)
(DupA::dup 0)
```

```
error[AX3014]: ambiguous name `dup`: defined in DupA, DupB
  = help: qualify the reference: `DupA::dup` or `DupB::dup`
```

The diagnostic recommended the spelling that was already there.
`checkAmbiguous` asked `bareOf name`, and `bareOf` strips exactly the
qualifier that answers the question — so the documented escape from the
flat namespace did not exist, which is part of why 149 imports still
carry no name list.

### The float flags are what made this a slice and not a line

§30's note said expansion was a larger job because `parseSigDecl`
reconstructs one float flag per arrow position FROM THE TOKENS —
float-ness is not observable at runtime, so by emission time there is no
checker to ask — and codegen reads those flags to choose `fmul` over
`mul`. Expanding `(type Real = Float)` in the checker alone would have
the checker say `Float` where the emitter still says `Int`. That note
was right, and it is measured:

```scheme
(type Real = Float)
(:: area (-> Real Real Real))
(fn (area w h) (* w h))
(println (fmtFloatPrec (area 3.0 1.5) 2))
```

With the flag rewrite: `4.50`, byte-identical to the same program
written with `Float`. With the flag rewrite ablated and everything else
in place: **`0.00`, at exit 0.**

Note the shape of the probe. An earlier version used `(/ x 2.0)`, and it
printed `4.50` under the ablation too — a float LITERAL decides
float-ness on its own, so the flag was never consulted. `area` takes two
parameters and multiplies them with no literal in the body, which is the
only shape where `paramIsFloat` is the deciding reader.

### The fix

`tcExpandSigAliases` runs over every signature, immediately before the
AX3002 pass that already visits those positions, and writes THREE
places so no reader keeps the unexpanded spelling: the declaration
node's type slot, its float-flag slot, and the `FnEnt`'s type — which is
what `checkVar` hands a call site, what `bindFnParams` peels for the
parameters and what `checkDeclaredReturn` compares the body against.
The positions cannot disagree again because there is nothing left for
them to disagree about.

The flags are recomputed from the expanded node at the vector's
ORIGINAL length, which reproduces `sigFloatFlags` exactly: position k is
the k-th peel's parameter for every k but the last, and the last is
whatever is left. Walking the node to exhaustion instead gives
`(-> Int (-> Float Float))` three flags where the parser gives two.

An alias reached through another alias re-enters. A cyclic one stops at
a depth cap and stays nominal, which is what it was. Parameterised
aliases need substitution and are not covered.

`checkAmbiguous` returns early when `modOf name` is non-zero.

### What it cost

`(type` has a corpus population of 0, and a 283-file old-vs-new sweep
moved exactly the two new fixtures — 1 to 0 — and nothing else.

### What pins it

`tests/selfhost/973-type-alias.ax` (argument position, an alias through
an alias, and the `Float` case) and
`tests/selfhost/974-qualified-ambiguous.ax`, which asserts not that the
AX3014 is gone but that each qualified call resolves to the module it
NAMES — the two definitions answer 100 apart, so a fix that merely
silenced the diagnostic and bound both calls to the first definition
still fails.

## 40. The frontend has five consumers and nothing compared them

Added 2026-08-10.

`check`, `symbols`, `fmt`, the REPL's `:load` and the language server
all drive the same `parseModuleWith` / `resolveImports` / `checkModule`
trio, each through its own call site — `resolveImports` from five,
`checkModule` from six. Three of the four defects fixed in §36-§39 exist
because a NEW consumer re-derived a rule the frontend already had, and
the fourth is a consumer that skipped a step:

```
:load accepted   23 of the 219 corpus files `check` accepts
```

`replCmdLoad` handed the entry file's declarations to `checkModule` as
*both* the entry list and the whole program, so no import was ever
resolved and every name an import provides was undefined. Nearly every
file in the repository imports something. (The review that prompted this
reported 178 of 199; re-derived at HEAD it is 196 of 219, which is the
reason for re-deriving.)

Two more, in the same file. `isDeclLine` listed `fn`, `define`, `::`,
`pub`, `data`, `struct`, `import`, `macro`, `effect`, `type` and
`trait` — and not `impl`, so a trait implementation typed at the prompt
went down the EXPRESSION path and was read as an application:
`undefined variable `impl``, then `Sz`, `Int`, `where`. And with that
fixed it parsed but did not dispatch, because `typeExprAgainst` never
lowered `impl`s the way `replCompile` always had, so `(sz 5)` answered
`no implementation of `Sz` for `Int`` about one sitting two lines above
it.

`:load` now accepts 219 of 219; `(sz 5)` answers `result 111`.

### The gate

`scripts/check-frontend-parity.sh` runs a bank of small programs
through all five consumers and requires them to agree on the verdict,
on the diagnostic set, and — the assertion none of the other gates can
make — **on the computed value**. Every defect §36-§39 fixed passed
`check` at exit 0 and differed only in what the program then computed,
so a gate that compares exit statuses cannot see any of them. A
`; refuse` case is additionally required to have produced a diagnostic,
because a SIGSEGV is also a nonzero exit.

The bank is seeded from those defects, plus the control that catches the
type-variable rule being written too WIDE.

Ablated by deleting `traitNameFree`'s body and rebuilding: `check` still
exits 0 on all seven, every diagnostic set still matches, and
`010-trait-scope` runs to 1 instead of 42. One failure, exit 1 — from
the only assertion that could see it.

### What it does not compare

Columns. `check-lsp-selfhost.sh` owns the UTF-16 conversion and derives
it from the fixture's own bytes; restating that derivation here would be
a second implementation of the thing it exists to check. And `fmt` is
compared on CODES rather than lines, because reflowing is the
formatter's job.

`typeExprAgainst` still leaves imports unresolved at the prompt — that is
stage0 parity, recorded in the function's own header, and a separate
question from `:load`.

## 41. Nine documented claims were false, and the fix is gates

Fixed 2026-08-10.

| Location | Claim as written | Measured |
|---|---|---|
| `README.md` status table | `Map` is **14×** Rust, "six sevenths of which is table growth against the bump allocator" | **1.80×**, and the cause was an affine hash — `docs/v1-roadmap.md` §2.4 B3 says so, in the same repository |
| `README.md` editor row | "gated against all **70** `.ax` files and a **22**-case tree-shape corpus. **No LSP yet**" | 290 files; 31 cases; `self_host/lsp.ax` is 812 lines with a CI gate, and the row four above it lists the LSP |
| `README.md` visibility row | "An import's name list is still not itself checked" | checked since `6a28103` |
| `README.md` functions row | "polymorphic signatures" under **Complete** | §38 made that true; the row now also says what it still does not do |
| `reference.md` aliases | an alias "does not create a new type … interchangeable" | §39 made that true for the spelling this section documents; a *parameterised* alias still does not expand |
| `reference.md` effects | "colliding with a function … is a duplicate definition" | §37 made that true |
| `reference.md` effects | "an effect named after a built-in … is refused" | **accepted**, measured; not implemented |
| `reference.md` linear types | "enforced … used exactly once"; memory "reclaimed at that point" | parsed only: a linear value used twice, or zero times, is accepted and runs; `consume` is a parse-time identity and there is no `free` |
| `reference.md` loops | "Axiom has **no loop construct**" | `while` is **Complete**, has its own heading, and is used 241 times in the compiler's own sources |
| `explain AX3025` | "there are no default bodies yet" | default bodies landed in `18537c0` |

Every one of them is corrected. That is the smaller half.

### The fix is gates, because correcting by hand is a treadmill

Seven stale file counts have been fixed one at a time across this
project's history. `scripts/check-doc-drift.sh`:

* **every count is recomputed** — and a claim whose sentence this gate
  can no longer find is a FAILURE, not a skip, because a reworded
  sentence that quietly stops being checked reads exactly like success;
* **every `**Complete**` row names a fixture, and the fixture exists.**
  Three of seventeen did; the other fourteen now do. This is the
  cheapest implementation of the corpus-is-the-spec law: it forces the
  *documented* surface, not the tree, to define coverage — and two of
  the fourteen turned out to be describing behaviour that did not
  exist;
* **the diagnostic registry, both ways.** 39 codes have a construction
  site outside `explain.ax`, 39 are listed, and the sets are equal.
  `check-tools-selfhost.sh` already checked emitted → listed, which is
  weaker in the direction that matters: a code CONSTRUCTED but never
  reached by a corpus fixture escapes it, and `AX4001` sat in the table
  with no construction site for months;
* **every `tests/` path the docs name exists** — 44 of them.

All three sections were ablated: a wrong count, a `**Complete**` row
stripped of its fixture, and a construction site for a code nobody
explains. Each fails, individually.

The registry check strips comments before grepping. Without that it
counts a code MENTIONED in prose, and these files quote codes
constantly.

### And the sweep was widened

`tests/docs/verify-doc-code.py` read `README.md`, `docs/reference.md`
and `CONTRIBUTING.md` — 114 blocks. It did not read `docs/macros.md` or
this file, which is 7,000+ lines, grows by a section per fix, and quotes
real programs throughout: exactly the shape that goes stale unread.
Adding two paths takes it to **148 blocks and 27 whole programs**.

Two markers came with them:

* `excerpt` — a section explaining a defect quotes source mid-form, and
  balance is not a property such a quotation has. Two blocks need it;
  the count is printed on every run and capped at 12, because an
  opt-out nobody counts is how a sweep stops sweeping.
* `refused` — a section that quotes the program a defect lived in can
  now ASSERT it: the block must still fail to compile, **and fail with
  a diagnostic** rather than by dying, since a signal is also a nonzero
  exit. Seven blocks carry it. Ablated by marking a compiling program
  `refused`: `FAIL doc snippet README.md:93: marked `refused` and it
  compiles`.

One correction here was the gate finding its own bug rather than the
tree's: the path-existence regex matched
`tests/fmt/parity/170-empty-tuple.axp` as `…ax` and reported a file that
exists as missing. First run, first finding, and it was mine.

## 42. An imported module that did not parse reported nothing about it

Fixed 2026-08-10.

```
$ axiom check use.ax
error: cannot parse module: Broken
$ echo $?
3
```

No code. No span. No snippet. No help. Byte-identical under
`--diagnostic-format=json`, which it ignored. And checking that same
file directly:

```
$ axiom check Broken.ax
error[AX2002]: unexpected end of file
 --> Broken.ax:2:24
  |
2 | (pub fn (helper x) (* x
  |                        ^ file ends here while a form is still open
  |
  = help: count `(`/`[`/`{` against `)`/`]`/`}` working backward from the end of the file
$ echo $?
1
```

The information was held by the caller and thrown away. This was the
last surface untouched by the parse-error port, and it is the one a
person compiling a multi-module program meets first: it is what the
compiler prints when a file it was told to read is broken.

I met it myself while writing §38 — a missing parenthesis in
`typecheck.ax` reported as `error: cannot parse module: typecheck`, and
the only way to find the line was to run `check` on the file by hand.

### The fix

`parseModuleOrDie` now lexes, checks for lexical errors and parses in
the same order `main.ax` does for the entry file, and `dieModuleParse`
renders the result through `renderDiagsFormat` — the same renderer, the
same trailer, the same exit status 1. `dieImportDiag`, three definitions
above, already had this shape for the module that could not be FOUND;
the module that could not be READ is the same problem one step later.

One thing had to move for it. The diagnostic must name a FILE, and
`readModuleSrc` answered the bytes and threw the resolved path away —
only the search knows which of `Mod.darwin-aarch64.ax`, `Mod.darwin.ax`
and `Mod.ax` won. `moduleSrcPath` now owns that ladder and
`readModuleSrc` reads through it, so the two cannot disagree about which
file was opened.

### What pins it

Four cases in `scripts/check-driver.sh`, and the broken module is
written by the script rather than checked in — `check-fmt.sh` and
`check-tree-sitter.sh` sweep every `*.ax` in the repository and require
it to parse, so a file that deliberately does not parse must be
`.axbad`, and an `.axbad` is not a name the module resolver will ever
find.

The load-bearing one is the last: **the diagnostic an importer gets is
byte-for-byte the diagnostic the module itself gets.** Asserting only
"exit 1" or "mentions AX2002" would be satisfied by any refusal, and
the defect was never that it failed to refuse.

Ablated against a tree with the previous `codegen.ax`: all four fail,
each for its own reason — exit 3, an uncoded line, a mismatch against
the direct check, and JSON ignored.

## 43. What the module cache actually needs, measured

Not fixed. Recorded because the estimate was wrong and the reason is
worth having in writing.

The plan was a cache keyed on path + mtime holding a module's parsed
and checked declarations, at roughly 120 lines, resting on a surveyed
negative result: there is no module-level mutable state anywhere in
`self_host/` or `stdlib/`, so a second `checkModule` in one process
inherits nothing and the cache is purely additive.

That negative result is true and it is about the wrong thing. The
declarations themselves are mutated in place, by three passes:

* `mangleDecl` (`codegen.ax`) renames an imported declaration —
  `(memSetWord node 1 full)` — so `f` becomes `Mod$f` **on the parsed
  node**. Re-resolving a cached module would produce `Mod$Mod$f`;
* `traitRewrite` (`typecheck.ax`) rewrites a call head to an
  implementation's mangled name, deliberately, because the emitter
  reads the same nodes later;
* `tcExpandSigAliases` (§39) rewrites a signature's type slot and its
  float-flag slot for the same reason.

So the cache is not additive; it needs import resolution to stop being
destructive, or a deep copy per reuse that costs much of what it saves.

And the benefit is narrower than the headline suggests. 93% of
`check self_host/main.ax` is its twenty imports, but each is read once
per process, so a fresh `check` cannot be helped by any cache. The
beneficiary is the process that checks repeatedly — the language
server, on every keystroke — which is exactly the workload the ratio
was measured on and exactly the one where the mutation problem bites,
because the same nodes would be reused across edits.

The gate is unchanged and still right: a ratio measured in one run,
second invocation against first. A wall-clock ceiling is a
machine-speed assertion in costume.

## 44. The standard library was 100% public, and the seed could not survive it being otherwise

Fixed 2026-08-10.

Of 361 distinct `pub` names across `stdlib/`, **151 had no consumer
outside their own module** — `Map` exported `mapFindLoop` (seven
parameters) and `mapInsertLoop` (eleven); `Rpc` exported `rdFill`,
`rdCompact` and `rdFindHeaderEnd`. Those are internals, and they were
permanent public API and permanent residents of the flat namespace.

The reason to fix it is not tidiness. `pub` distinguished **nothing**:
every one of the 3,358 top-level declarations in `stdlib/` and
`self_host/` carried it, so module visibility was exercised in its true
branch by all of them and in its false branch by none. That is the
exact shape that hid three bugs when visibility itself landed. 288
declarations are private now, and `tests/diagnostics/470-stdlib-private.ax`
is `AX3023`'s first positive case.

### What it cost, which was not zero

**The committed bootstrap seed could not compile the result.**

```
warning[AX3010]: AXTAG mismatch on `sysOpenPath`: `effect(io)` claim unsupported: missing IO
  --> stdlib/Sys.ax:62:10
FAIL: seed could not compile self_host/main.ax
```

`sysOpenPath` is public and calls `sysOpenPathMode`, which is now
private. `bootstrap/STAMP` says the seeds were generated on
**2026-08-08 from `8218a9bd`** — before module visibility landed in
`2192d61` on 2026-08-10 — and the compiler of that day *deleted* a
private declaration rather than hiding it. So the callee vanished from
the program and the caller's inferred effect set lost `IO`.

That is the seed going stale in the precise sense `scripts/reseed.sh`
names as its only routine reason to move, and it means visibility was
unusable anywhere in the bootstrap path from the day it shipped —
which nothing could notice while every declaration in the repository
was `pub`. Reseeded from `c46e555`; `bootstrap-from-seed.sh` builds
stage1 from it and stage2 equals stage3.

### Two names the tree could not see

The sweep asks whether a name has a consumer, and it read `.ax` files.
Three names had none there and are still public API, because the
DOCUMENTATION teaches them: `readFile`, `eprintln`, `fmtFloat`. The
widened doc-code sweep is what caught it, on the first run after the
change:

```
FAIL doc snippet README.md:919: does not compile:
  E AX3023 ... "`readFile` is private to module `IO`"
```

Which is §41's law arriving from the other direction: the documented
surface defines the API, not the tree.

### What moved, and what did not

`symbols`' zoo goldens moved by four columns — removing `pub ` shifts a
declaration's name — and the 89-symbol count held, which is the half a
re-bless cannot satisfy. A 290-file sweep of `check` output and exit
status against the previous standard library diverged on **0**.

## 45. Three statements of "what is a space"

Fixed 2026-08-10.

`lexer.ax`, `format.ax` and `Json.ax` each carried their own byte
classifiers — three of `isSpace`, two each of `isDigit` and `isAlpha` —
and nothing compared them. `isFSpace` had already drifted once: it
admitted VT (11) and FF (12), inherited from the retired compiler's
`char::is_whitespace`, which this language's lexer never matched. `fmt`
rewrote a file `check` refuses with `AX1001` into one it accepts, at
exit 0. The fix at the time added a comment saying "exactly
`lexer.ax`'s `isSpace`, byte for byte" — a claim checked by nobody.

The rules live in `Str` now (`strIsDigit`, `strIsAlpha`, `strIsSpace`,
`strIsHexDigit`) and the named predicates delegate, so the claim is
structural. `tests/selfhost/990-char-class.ax` sweeps **all 256 byte
values** through every surviving predicate three ways and requires 768
agreements — a count rather than a flag, so a predicate that stopped
being called fails with a number instead of passing by silence.

Ablated by re-introducing the VT/FF drift: exit 1. The bytes that
shipped the bug are 11 and 12, which no corpus file contains and which
no hand-written case would have thought to try. That is why the sweep
is exhaustive rather than illustrative.

## 46. `strSplit`

Added 2026-08-10.

The colon scan was open-coded twice — `codegen.ax`'s `pushPathList` and
`Sys.ax`'s `sysRunSearch`. `strSplit` owns it now and `pushPathList`
uses it.

`sysRunSearch` deliberately keeps its own: it stops at the first
candidate that opens, and building the whole vector first would open
files it never needs. Recording that is the point — the two loops
looked identical and their *control flow* is not.

Empty segments are KEPT, because the two callers disagree about them: an
empty `PATH` entry means the working directory to `sysRunSearch` and
means nothing to a module search path. So the segment count is the
separator count plus one, always, and dropping empties is the caller's
business. `tests/selfhost/991-str-split.ax` pins the five boundary
cases that decision makes observable — no separator, leading, trailing,
adjacent, and the empty string — plus the segments' actual bytes, since
a split answering N empty slices would satisfy all five counts.

## 47. A batteries-included language could not create a directory

Fixed 2026-08-10.

`Sys` had `open`, `read`, `write`, `close`, `seek`, `unlink`,
`readFile` and `writeFile`, and no way to make a directory at all.
`dirOfPath` and `withTrailingSlash` were private helpers in
`codegen.ax` because there was nowhere else to put them.

Added: `sysMkdir`, `sysRmdir`, `sysDirMode`, `sysFileExists`,
`sysFileSize`.

### `stat` is deliberately not among them

It is the obvious way to ask "is it there" and "how big", and it is
four record layouts rather than one syscall number — `struct stat`'s
offsets, widths and padding all differ across the four targets, and
this repository can execute exactly one of them. So those two
questions are answered by calls the module already made:
`sysFileExists` is `open` + `close`, which is what `sysRunSearch` has
always done to test a candidate, and `sysFileSize` is a seek to the
end, which is what the size *is*.

That leaves `mkdir` as the only genuinely new number, and it has the
shape `sysUnlink` already established:

| target | call | number |
|---|---|---|
| darwin | `mkdir(path, mode)` | BSD 136 → `33554568` |
| linux-x86_64 | `mkdir(path, mode)` | `83` |
| linux-aarch64 | `mkdirat(dirfd, path, mode)` | `34` |

AArch64 Linux has no plain `mkdir`, the same way it has no `open` and
no `unlink`, so this branches on the existing `openNeedsDirFd`
capability rather than growing a second one — the rule this file
records for `sysUnlink`, applied unchanged. `sysRmdir` is the same
again, and on AArch64 it shares `unlinkat`'s number with
`AT_REMOVEDIR` (512) in the flags: removing a file and removing a
directory are one call there, distinguished by a flag.

`rmdir` landed WITH `mkdir` rather than after it, because a fixture
that creates a directory in the working tree and cannot remove it is
litter every later gate runs over. `unlink` does not remove a
directory — `EISDIR` on Linux, `EPERM` on Darwin.

### What pins it

`tests/selfhost/992-filesystem.ax` is a round trip, not a status
check: the directory is absent, then created, then present, then
creating it again is `EEXIST`, then removed, then absent. A gate
asserting `(== (sysMkdir p m) 0)` alone would pass against a syscall
number for something else entirely.

Ablated by pointing `sysRmdirNum` at BSD 138 instead of 137: exit 1,
**and it leaves the directory behind**, which is the observation the
round trip exists to make.

The three targets this host cannot execute are covered the way every
other syscall here is — `check-cross-targets.sh` assembles all four
from one host, and the numbers sit in the per-target module beside the
ones already proven.

## 48. Three linear scans behind one quadratic, found one at a time

Fixed 2026-08-10.

`check` on an entry file of N top-level declarations, before:

```
N= 8000    0.46 s
N=32000   12.62 s          ratio 27x for 4x the input
```

`main.ax` hides it with 21 entry declarations. Generated code and
large single-file programs do not.

The review named two passes, and they were both real:
`checkDuplicates`/`firstDefiner` re-scans `decls[0..i)` per
declaration, and `checkMissingDefs`/`isDefined` re-scans the WHOLE
program per signature. Both are indexed now.

That bought 15x and **left the exponent where it was**, which is the
part worth writing down.

### What the profile said after each fix

A sample of the N=32000 check, once the two named passes were indexed:

```
935 of ~1200 samples   typecheck$ambBuild
```

`ambRecord` calls `ambFind` for every name it records and `ambFind`
was a linear scan of a table that grows with the program — so
*building* the ambiguity table was quadratic on its own. The
name-index slice (`8942644`) fixed `tcFns` and left this one; its own
note says the fix was "`Map` for `tcFns` and `ambTbl`", and only the
first half landed. Indexed the same way, on a TC field appended after
`fnIdx` for the same reason.

Then, at N=64000:

```
3019 of ~3100 samples   codegen$resolveImports
```

on a file with **no imports**. `recordEntryFns` calls `mangleRecord`
per entry function, and `mangleRecord` ends with
`(mangleHasIn bares bare 0)` — a linear scan of a Vec that grows with
the entry file. That is the third one, it is in codegen's bare→full
name map rather than in the checker, and it is **not fixed**: `bares`
and `fulls` are threaded through 53 references across four files, and
an index there means either a fourth parallel structure or a record
refactor of codegen's name resolution — which is where this
repository twice records a mistake becoming a link failure rather
than a diagnostic. It is specified, not attempted.

### Where it landed

| N | before | after |
|---|---|---|
| 8,000 | 0.46 s | 0.07 s |
| 16,000 | — | 0.21 s |
| 32,000 | 12.62 s | 0.83 s |
| 64,000 | — | 4.61 s |

**15.2x at N=32000**, and `check self_host/main.ax` is unchanged at
0.49 s — the real workload has 21 entry declarations, so it neither
gains nor pays.

Doubling ratios after: 3.00, 3.95, 5.55. Still about 4 per doubling,
because `mangleRecord` now owns the shape.

### Why there is no gate

The same reason the name index has none, and the reason is now
sharper: a doubling-ratio gate cannot separate before from after,
because the surviving quadratic keeps the ratio near 4 on both sides.
A gate that passed on the old code is worse than a measurement written
down with its probe. **When `mangleRecord` is indexed, a doubling
ratio becomes a real assertion and should be added then.**

### What is pinned instead

Correctness, which is what an index can actually get wrong.
`tests/diagnostics/475-duplicate-namespaces.ax` covers the four things
the duplicate index has to keep right — three definitions producing two
diagnostics that both point at the FIRST, `struct` against `data` in
the type namespace, `macro` against `fn` in the value namespace, and a
`data` against a `fn` of one spelling that must NOT collide. That last
one is an assertion about what is absent from the golden, which a
bucket keyed on the name without the namespace would break.

The missing-definition index reproduces `nameMatches` exactly rather
than approximately, and the argument is written at `defIdxBuild`: the
keys are `full` itself plus the suffix after every `$` at a position
past the first byte. The position is load-bearing — `nameMatches`
demands `m > n + 1`, so `$f` answers only to itself, and inserting that
suffix would invent a definition that satisfies a signature nothing
defines.

Nine adversarial programs were run through both compilers and agree on
every byte: three-definition ordering, both namespace collisions, the
non-collision, a signature satisfied by an imported public `Mod$f`, one
satisfied only by a PRIVATE `Mod$f` (still `AX3015`), one satisfied by
nothing, two modules making a name ambiguous, and a module defining
`None` that must not make the builtin ambiguous. A 294-file corpus
sweep diverged on 0.
