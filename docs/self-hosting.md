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

*Throughput*, measured by `scripts/bench-datastructures.sh` at 10⁶
elements, `axiom --opt 2` against `rustc -O` with a fast
non-cryptographic hasher on the Rust side (the map a compiler would
actually pick), whole processes timed with startup subtracted:

| | Axiom | Rust | ratio |
|---|---:|---:|---:|
| `Vec` | 0.0075s | 0.0016s | 2.5× |
| `Map` | 0.331s | 0.024s | 14× |
| `Intern` | 0.259s | 0.347s | **0.75×** |

`Intern` beats the Rust equivalent. `Map` misses the 2× criterion by a
lot, and ablation says the hash and the probe are not why:

| 10⁶ keys | time |
|---|---:|
| `mapSlotOf` alone | 0.005s |
| + one probe read | 0.017s |
| + full insert into a **pre-sized** table | 0.034s |
| full insert into a table **grown** from 8 | 0.214s |

Steady-state insert is 34 ns/key, within 1.4× of Rust. **Six sevenths
of the cost is table growth**, and it is an allocator problem rather
than a `Map` problem: doubling from 8 to 2²¹ slots allocates
3 × (8 + 16 + … + 2²¹) words ≈ 100 MB for a table whose live size is
48 MB, and the bump allocator never reuses the superseded ones —
measured at 102 MB peak RSS.

Two things that do *not* fix it, both measured rather than assumed.
Growing by 4× instead of 2× buys 35% and by 8× buys 43%, still 5.3×
Rust, at proportional memory overshoot. `--gc` is *worse* on this shape
— 0.33s and 137 MB — because the tables are large, long-lived and
conservatively scanned, so collection costs more than the garbage it
finds is worth.

The remaining work is therefore the memory model (roadmap P2), not
`Map`. One `Map`-local improvement has already landed: `mapHash`
performed six hardware divisions per call, and every divisor is a power
of two or the Mersenne prime 2³¹−1, so all of them are now shifts and
masks. That is worth ~9% and, being the same function rather than an
approximation, leaves every pinned hash and slot value in `080-map.ax`
byte-identical; the test checks the fast path against the retained
division-based specification over both signs and both limb boundaries.

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
top-level function builds the one-word closure record stage0 gives a
captureless function - the code pointer in word 0 - and a call whose
head is a local or parameter goes indirect through it, all arguments
at once (`tests/selfhost/520-fn-values.ax`, `530-fn-in-ctor.ax`).
Partial application would need runtime arity in the record, and a
lambda expression needs capture analysis and lifting; both are refused
loudly rather than miscompiled.

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
It emits for darwin-aarch64
only. And the driver reads `in.ax` from the working directory and
writes to stdout, with no argument parsing. Float literals with more
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
