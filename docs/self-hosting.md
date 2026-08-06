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

*The collector, and why it is shaped the way it is.* `--gc` replaces the
bump allocator with a conservative, non-moving mark-sweep collector, so
peak memory tracks live data instead of total allocation. Measured on
`tests/stdlib/170-gc.ax`, which churns garbage while holding a list
alive:

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

Recorded open from the same scout, for later: bare references
*inside* an imported module also resolve entry-first (in
`320-mangle`, `Str.ax`'s own internal `strLen` call reaches the
entry's shadowing definition, and the test passes only because both
answers land on the same side of its comparison) - fixing that means
module-internal references bind module-locally, which revisits B4's
flat-namespace decision.

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
parses neither form yet - recorded here as the standing parity gap.

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
code rather than an unsupported feature. stage1 still cannot lower
the effect system, but it now refuses with exit 3 and names the
effects it could not compile. An unsupported feature should say so.

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

`AX3010` stays unreported, on a dependency stage1 does not have at
all: AXTAG claims are comments, and stage1's lexer drops them. So
does the `AX3004` checking a handler against its operation's declared
arrow, which needs the operation type the `effect` parser discards.
Both omit lines; neither reorders or invents one.

`AX3013` remains under-reported in one direction recorded in
`typecheck.ax`: stage0 also measures builtins and foreign bindings
through their arrow depth. Duplicates *inside an imported module* also
go unreported, because stage1's merged declaration list does not
record which module each declaration came from; checking the entry
file alone is the sound subset, never inventing a diagnostic stage0
would not produce.

What genuinely remains for phase 3: `AX3010`, which needs AXTAG
comments to survive stage1's lexer at all; `AX3014` ambiguous-name,
which needs the per-declaration module tracking stage1's merged
declaration list does not keep; effect polymorphism, without which
the inferred sets stay a sound subset; diagnostic grouping; and
type-checking the bodies of imported modules against their own
filenames. That is every remaining `AX30xx` code accounted for:
stage1 emits fifteen of the seventeen. Lowering the effect system
itself is phase 4 work, not phase 3 — the checker's job is finished
when it agrees about what is wrong.

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
