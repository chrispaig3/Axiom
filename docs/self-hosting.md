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

What genuinely remains: no type checking -
`self_host/typecheck.ax` is a stub - so a program stage0 would reject
with a diagnostic, stage1 compiles into whatever the code happens to
mean. No lambda expressions or partial application (refused loudly).
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
