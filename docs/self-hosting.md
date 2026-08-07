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

Rollback is cheap by construction, and stays cheap because the Rust
compiler is never deleted while the Axiom one is unproven.

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

```scheme
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
rustc-flavored plain text, `error[AX3006]:` headings, char-counted
columns (the em-dash cases pin col 22 where a byte count says 24),
labeled lines in source order, every help rendered, and stage0's
trailer reproduced exactly - `compilation failed due to N previous
error(s)`, errors only, post-suppression. `--diagnostic-format`
accepts stage0's full alias set with stage0's fallback warning, and
`human` is now stage1's default as it is stage0's; every gate that
wants AXDL says so explicitly. A JSON renderer rides along, byte-
compatible with stage0's except `"label":""` where stage0 carries
the primary label message - a field AXDL never printed and stage1
never stored, recorded as the known delta.

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

Three divergences are recorded OPEN as named follow-ups rather than
silently absorbed:

* **the parse/lexer error path**: stage0 renders `AX2002` through
  the human renderer with its own trailer (`compilation failed due
  to a syntax error`) and exit 1; stage1 dies with `parse failed`
  and exit 2, a shape no gate compares because the AXDL corpus is
  all-semantic. Porting it means giving stage1's parser real
  diagnostic objects - a slice of its own.
* **`symbols`' stdout default**: bare `stage0 symbols` prints an
  aligned human table; bare `stage1 symbols` prints AXSYM lines
  (which is what stage0 emits under `--diagnostic-format=ai`, the
  spelling every gate uses). The table is a follow-up; the flag
  surface, not the default, is what the gates pin today.
* **`AX5001` (cannot-resolve-import) as a diagnostic**: stage0
  emits it spanless (`file:-`) with exit 1; stage1's resolver dies
  with `cannot read module` and exit 3 - an exit code
  `check-self-host.sh` asserts on by name. The spanless rendering
  path exists in `render.ax` and is exercised by no current stage1
  diagnostic; converting the resolver's refusal into one is the
  follow-up that unlocks a spanless corpus case.
