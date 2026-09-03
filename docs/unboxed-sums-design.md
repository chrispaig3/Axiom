# Unboxed small sums — making `Option` and `Result` free

`(Some v)`, `(Ok v)` and `(Err e)` allocate. Every one of them is a
16-byte heap block with a refcount, a shape word, a tag and the field,
built by `axiom_alloc` and handed back to the arena by
`axiom_release`. That is the entire cost of `Option` and `Result` in
Axiom today, and it is the reason `compat/SENTINELS` still carries seven
absence rows and nine failure rows that the migration wants and cannot
have.

This note measures that cost, prototypes a representation that removes
it, and states what building the real thing would touch. Every number
below is from a command in this note; nothing here is estimated. **No
compiler code was changed** — the prototype is hand-written LLVM IR
derived from the compiler's own output, which is what makes it a
measurement of the representation rather than of an implementation.

## 1. What the box costs, measured

A string interner with 2,000 names, 20,000,000 round-robin lookups,
`--opt 2`, best of five whole-process runs (the methodology
`bench-datastructures.sh` and `bench-compile.sh` both use — the
distribution is one-sided, so the minimum is the closest estimate of
the cost itself).

Three variants of the same program, differing only in what the lookup
returns:

| variant | total | per lookup | wrapper |
|---|---|---|---|
| raw `-1` sentinel, no `Option` at all | 1.6060s | 80.30 ns | — |
| `(Option Int)`, boxed — **today** | 1.8432s | 92.16 ns | **11.86 ns** |
| `(Option Int)`, two registers — **prototype** | 1.6133s | 80.67 ns | **0.36 ns** |

**The box costs 11.86 ns and the register pair costs 0.36 ns.** The
prototype recovers **96.9%** of it and lands **0.45%** above having no
`Option` in the language at all — at the resolution of this
measurement, free.

`None` was already free and stays free: a nullary constructor is an
immediate below 4096, with no block behind it, which is why
`tests/diagnostics/384-restrict-no-alloc-ctor.ax` has a silent `none`
arm beside a refused `some` one.

### What that is worth at scale

`internFind` answering `(Option Int)` cost **+3.5% on the compiler's
code-generation stage** (`compat/SENTINELS`, the 2026-09-01 entry).
Dividing that 46 ms by the 11.86 ns above puts roughly **3.9 million**
`Some` blocks in one self-compile, from nine call sites. The
representation below deletes all of them.

## 2. The representation

A sum type whose constructors carry **at most one word of payload** is
passed and returned as `{ i64, i64 }` — `{tag, payload}` — instead of a
pointer to a block. `Option T` qualifies for every `T`; `Result T E`
qualifies whenever both arms are one word, which is the shape
`stdlib/Err.ax` uses everywhere.

Two words is not an arbitrary cutoff. It is what both supported
architectures return in registers: `x0`/`x1` on aarch64 and
`rax`/`rdx` on x86-64 SysV. At 16 bytes the ABI is still register-based
on both; past it, both spill to memory through an indirect pointer and
the win is gone.

The compiler already speaks this language. `docs/checked-arithmetic-design.md`
notes that `@llvm.sadd.with.overflow.i64` returns `{i64, i1}` and calls
that "structurally identical" to a trap codegen already emits, so
multi-word returns are not new ground for this backend — only for its
own types.

### Why one word cannot be made to work

The obvious cheaper idea is a niche: represent `(Some x)` as `x` itself
and `None` as an immediate, the way a nullable pointer works. It is
correct for `Option T` where every `T` is a heap value, because those
are all at or above 4096 and cannot collide with an immediate tag.

**It fails for exactly the case that matters.** An `Int` in Axiom is a
raw `i64`, so `(Some 5)` would be `5`, and `5` is indistinguishable
from an immediate constructor tag under the `icmp slt %v, 4096` test
that every `match` opens with. `Option Int` needs 65 bits and one word
does not have them. The niche is a real optimisation for
`Option String` and friends and it is not a substitute for this one.

## 3. The prototype, and what it proves

Taken from the compiler's own emitted IR for the benchmark above, with
`Intern$internFind` and its one call site rewritten by hand. The
allocating tail of the function:

```llvm
.L8:
  %.t10 = call i64 @axiom_alloc(i64 16)
  %.t11 = add i64 %.t10, -8
  store i64 4, ptr %.t12          ; shape word
  store i64 0, ptr %.t14          ; tag
  store i64 1, ptr %.t16          ; refcount
  store i64 %.t3, ptr %.t18       ; the field
```

becomes

```llvm
.L8:
  %.s0  = insertvalue { i64, i64 } undef, i64 0, 0    ; tag = Some
  %.s1p = insertvalue { i64, i64 } %.s0, i64 %.t3, 1  ; payload = the id
  ret { i64, i64 } %.s1p
```

and the caller's twenty-eight instructions of immediate-test, tag load,
field load and `axiom_release` collapse to

```llvm
  %.pair = call { i64, i64 } @Intern$internFind(i64 %.t23, i64 %.t31)
  %.tag  = extractvalue { i64, i64 } %.pair, 0
  %.pay  = extractvalue { i64, i64 } %.pair, 1
  %.t51  = icmp eq i64 %.tag, 0
```

Both programs print the same checksum (`19990000000`), through the same
`opt -O2` / `llc -O2` / `cc` pipeline `bench-compile.sh` uses.

**What this proves:** the representation is correct on this target and
costs nothing. **What it does not prove:** that the compiler can
produce it for arbitrary programs. Section 4 is the list of reasons
that is a real project and not an afternoon.

## 3a. The cheap alternative, measured and rejected

`axiom_alloc` and `axiom_release` are both defined in the emitted
module, and at `-O2` LLVM inlines **neither** — the optimised IR still
reads `tail call i64 @axiom_alloc(i64 16)` inside `internFind` and
`tail call void @axiom_release` in the caller. Two real calls per
wrapper. That invites an obvious, far cheaper fix than changing any
ABI: emit the allocator's fast path inline at the construction site.

Measured, by marking both functions `alwaysinline` and re-running the
same pipeline — an upper bound on that idea, since it inlines the slow
paths too:

| variant | total | recovers |
|---|---|---|
| boxed, calls as today | 1.8454s | — |
| boxed, allocator and releaser inlined | 1.8112s | **14.3%** |
| two registers | 1.6080s | **99.2%** |

**The call overhead is 14% of the box and the other 86% is the work
itself** — the free-list pop, the shape word, the tag, the refcount,
the field store, the caller's immediate test and two loads, and the
release's refcount decrement and free-list push. Inlining moves none of
that; not allocating removes all of it.

So the ABI change is not one of several options. It is the only one
that pays, and this section exists so the cheap idea is not
re-proposed.

## 4. What building it actually touches

**The plan below replaced an earlier one.** The first draft of this
note proposed a general type-directed representation — every eligible
value unboxed in flight, boxed when stored — and named the storage
boundary as the largest piece and ownership-without-a-shape-word as the
next. Both are avoidable, and the plan that avoids them is smaller and
strictly safer.

### Specialisation, not a global representation change

Emit a **second definition** for a function whose declared return type
is an eligible sum: `@F` unchanged, plus `@F$pair` returning
`{ i64, i64 }`. Rewrite only those call sites where the result is
**immediately matched** — `(match (F args) arms)` — to call `@F$pair`
and read the tag and payload from registers. Every other caller keeps
the boxed `@F`, bit for bit.

Why this is the right shape:

* **The storage boundary disappears.** A pair never reaches a `let`
  that outlives the match, a `Vec`, a struct field or another
  function's argument, because the only rewritten site consumes it on
  the spot. There is nothing to coerce, so there is no coercion to get
  wrong.
* **No per-node types are needed**, which matters because codegen does
  not have them. It needs exactly one fact it can already look up:
  the callee's declared return type, through `findFSigCg`.
* **It is opt-in per call site and reversible per call site.** A shape
  the tail walk does not recognise simply keeps the boxed path, so the
  failure mode is "no speedup", not "wrong answer".

### Restrict the payload to a non-reference, at least at first

If the single field is a reference, the box today owns a share of it
and `axiom_release` on the wrapper hands that share back. A pair has no
refcount, so ownership would have to transfer to the consumer, and
getting that wrong is a use-after-free rather than a slowdown.
`eFieldFlags` already records which fields are references, so the
eligibility test is available where the decision is made.

Restricting to a non-reference payload gives up nothing that matters
here: `Option Int` is the shape of **every** row this unblocks —
`internFind`, `strHexVal`, `utf8DecodeAt`, `utf8CharAt`, `keyStrEnd`,
`strFindByte`. Reference payloads are a later slice with its own
ownership argument.

### What is left to build, in order

1. **Eligibility**: a `data` type with `rep 2` whose fieldful
   constructors carry exactly one non-reference field. Decided once per
   type, from the table `lookupType` already answers.
2. **`@F$pair` emission**: the body again, with tail-position
   constructor applications building `insertvalue` pairs instead of
   calling `emitConstructor`. The tail is a walk through `if`, `match`,
   `let` and `{}` to the constructor applications underneath; any tail
   the walk does not recognise falls back to computing the boxed value
   and converting, which is correct and merely not faster.
3. **Call-site rewrite**: at `(match (F args) arms)`, call `@F$pair`
   and feed the existing arm lowering from the two `extractvalue`s
   instead of from the immediate test and the word loads.
4. **`restrict(no-alloc)` and the effect row**: `@F$pair` performs no
   `Alloc`, so `#effects=` narrows for the specialised path. Section 5
   is why that is the point rather than a complication — but
   `compat/BREAKING` still needs a `NARROWED` kind and
   `check-compat.sh` needs to accept it.
5. **A gate**: the pair path must be *proved taken*, not assumed.
   Counting `axiom_alloc` calls in the emitted IR for a fixture with a
   known number of matched lookups is the direct assertion, and an
   ablation that forces the boxed path must move that count.

### What this plan does NOT need

FFI classification (no `extern` sees a pair), a second general `match`
lowering path (only the rewritten call sites change), container
widening, and any change to how values are stored. Those were all
consequences of the general design and none survives specialisation.

## 4a. Superseded: the general representation change

Kept because it is the fallback if specialisation turns out not to
cover enough call sites, and because two of its items are real work
that a wider version would still face. Ordered by how likely each is to
be the thing that stops it.

**Storage is where the design can go wrong.** Unboxing works for values
*in flight* — arguments, returns, locals, registers. A `(Option Int)`
stored as a field inside another heap block is one word today and would
be two, so either every container widens or the representation is
coerced at the storage boundary. The honest rule is **unboxed in
flight, boxed when stored**, with a coercion at each crossing; that is
well understood and it is the largest single piece of work here.

**Ownership, and the shape word.** Today a block's shape word tells the
runtime which of its fields are references, and releasing the wrapper
transitively releases the payload. An unboxed pair has no block and no
shape word, so when the payload is a reference the *consumer* must emit
the retain and release itself, from the static type. That is the same
shape word this project's memory keystone already names as the wall
(`K1 -> K2 -> K3`), approached from a new side.

**Effect rows narrow, and that is a breaking change in a direction
`compat/BREAKING` has never recorded.** `(Some v)` would stop
performing `Alloc`, so every function whose only allocation was
wrapping a result loses `Alloc` from `#effects=`. That file's kinds are
`CHANGED`, `WIDENED`, `REMOVED` and `RETIRED`; this needs `NARROWED`,
and `check-compat.sh` has to learn that narrowing is still a contract
change even though no caller pays for it.

**`restrict(no-alloc)` starts accepting constructor applications** of
these types. `tests/diagnostics/384-restrict-no-alloc-ctor.ax`'s `some`
arm would go from `AX3049` to silent — a golden change that is also a
claim change, and the fixture's own header says the `some`/`none` pair
is the measurement. It would need rewriting around a type that still
boxes.

**FFI.** `{i64, i64}` is returnable across the C ABI on both targets,
but `rust/axiom-ffi-classify` would need a rule. The cheap first answer
is to forbid unboxed sums across `extern` and revisit later.

**Match lowering.** The `icmp slt %v, 4096` immediate test disappears
for these types — the tag is already in a register — so `match` grows a
second lowering path selected by the scrutinee's type.

## 5. What it unblocks, which is the actual argument for doing it

This is not only a speed change. `compat/SENTINELS` recorded **seven
absence rows and nine failure rows** when this section was written
(nine and ten until the 2026-09-03 correction removed three rows that
were never portable — `docs/error-model.md` §10.1); after §5b and the
two ports it permitted it records **three and zero**. The reason five
of the seven could not move was stated here and in
`docs/error-model.md` §10:

> `strHexVal`, `utf8DecodeAt`, `utf8CharAt` and `keyStrEnd` all read
> `#restrict=no-io,no-alloc,no-foreign`. They cannot become `Option`
> without WITHDRAWING a checked claim.

`strFindByte` reads the same three restrictions and is the fifth; it is
listed apart from the four above because its own exclusion was argued
on cost (7.4× per call over its scanning-path sites) rather than on the
claim, and the claim refuses it either way.

**~~If `(Some v)` does not allocate, that blocker is gone~~ — MEASURED FALSE, 2026-09-01** — those four
become `Option` while keeping the claim they already make, and the
argument in §10 that was corrected on 2026-09-01 (`Option` carries no
`Error` and still allocates) stops being true because the second half
stops being true.

It also removes the standing objection to the rest of the failure
column. Every ERR-ADOPT-1 row in `compat/BREAKING` is `WIDENED`
because building a `Result` allocates; `sysWriteFd`, `sysReadFd`,
`netAccept`, `netAcceptFrom` and `netPollWait` are excluded precisely
because that widening lands under `println`'s 804 expansions. An
unboxed `Result` whose `Ok` arm carries one word does not widen
anything. The `Err` arm still builds an `Error`, so the failure path
still allocates — but the failure path is not the one those exclusions
are about.

**So the order is: this first, then the rest of ERR-ADOPT-1.** Doing
the migration first means porting functions twice.

## 6. Reproducing the measurement

```
axiom build --opt 2 --input bench.ax --output bench     # the three variants
axiom emit-llvm --input bench.ax -o bench.ll            # then hand-edit
opt -O2 bench.ll -S -o bench.opt.ll
llc bench.opt.ll -filetype=obj -o bench.o -O2 -relocation-model=pic
cc bench.o -o bench.exe
```

The benchmark interns 2,000 `"name{i}"` strings into one `Intern`,
pre-builds the handles into a `Vec` so the timed loop allocates no
strings of its own, and sums the ids over 20,000,000 round-robin
lookups so nothing is dead. The three variants differ only in the body
of the loop: a raw `-1` compared against zero, a `match` on a boxed
`(Option Int)`, and a `match` on the register pair.

### The `no-alloc` claim was NOT lifted by the first slice, measured after building

*Superseded by §5b on 2026-09-03; kept because the measurement was
right about the code as it stood.*

A `restrict(no-alloc)` function answering `(Option Int)` in the
specialised shape still drew `AX3049`, and the checker was right. **The
boxed `@F` was still emitted** for every caller that did not
immediately match, so the function genuinely could allocate — which
caller it got decided. `no-alloc` is a property of a function; after
the first slice the honest version of it was a property of the function
AND its call sites, a whole-program question the effect walk did not
ask.

### 5b. The box belongs to the caller, 2026-09-03 — and the claim is lifted

The whole-program question has a local answer: **build the block where
it is needed, and charge it there.** Three changes, one in each of the
two files and one that holds them together.

**The emitter writes the body once.** A function in the pair set is
emitted only as `@F$pair`. `@F` is a wrapper — call the pair, box what
comes back — kept for a reference taken as a value, and pruned with
every other unreferenced definition otherwise (`emitPairWrapper`).
Every direct call to `F` calls the pair: a `match` on it reads the
registers as before, a tail leaf of another pair function FORWARDS the
two registers (`pairFwdOK` — `utf8CharAt` ends in `(utf8DecodeAt s
i)`), and any other site — a `let` that outlives the match, an
argument, a field store, a statement — boxes the pair **in the
caller's own definition**, with the shape word, tag, count and field
store a boxed constructor writes (`emitPairBox`). Since nothing is
written twice, the "body shape" refusal that kept a `while`, a `set`
or a lambda out of the pair is gone, and a tail match the tail
emitter could only lower boxed is routed to the ordinary emitter
(`pairTailDelegates`), so every `pairMatchOK` match reads registers.
On the compiler's own source the pair set went from **8 functions to
24** for it.

**The checker charges the block where the emitter builds it.**
`self_host/typecheck.ax` carries a mirror of `pairFnOK` — the same
eligibility test, asked of the checker's own tables (`tcPairFnOK`,
`tcPairTails`, `tcPairMatchOK`) — and the effect walk uses it three
ways: a constructor leaf of an eligible function's tail contributes no
`Alloc`; a call to a pair function contributes `Alloc` unless it is a
recorded site (a matched direct call, a forwarding leaf); a pair
function named as a value contributes `Alloc` for the wrapper it
reaches. So `internFind`, `pathLastSlash` and `scopeFindIdx` read no
`Alloc` in `symbols` now, and a caller that stores their answer past
its match reads the `Alloc` they used to carry.

**And the two are held to one answer.** `scripts/check-unboxed-sums.sh`
section 5 asks `check` the three claims at once — `restrict(no-alloc)`
on the lookup (accepted), on a caller that matches it directly
(accepted), on a caller that `let`-binds the answer (`AX3049`) — and
reads the same split from `symbols` and from the IR; section 6 runs
`scripts/lib/alloc-rows.py` over the whole self-compile, holding every
function whose row lacks `Alloc` to a definition with no `axiom_alloc`
(3,482 rows held, 0 disagreements). The mirror may over-charge and
never under-charge; the direction is stated in both files and section
6 is what would notice it going the other way.
`tests/diagnostics/384-restrict-no-alloc-ctor.ax`'s `some` arm is
silent now, and a `held` arm that stores the answer is the refusal
that keeps the silence honest.

**What this does NOT do.** A self-tail-recursive function still keeps
the boxed shape (`tailCallsSelf` is still a refusal — the loop header
and the pair return have not been reconciled), so `strFindByte`
cannot take the pair as written; a `match` in tail position of a pair
function is still not a tail the pair recognises; and a third sum
type — anything but `Option` and `Result` — is still refused by name.
Every one of those is a refusal, not a wrong answer: the fallback is
the boxed path with `Alloc` charged, which the mirror charges too.

## 5a. `Result` and reference payloads, 2026-09-01

The first slice refused both. They are admitted now, and the ownership
rule is the whole of the change.

**A reference payload is a SHARE.** The block it replaces owned one;
the pair has no refcount, so the share travels in the payload register
and the consumer gives it back. Construction retains only when
`valueOwnedRef` says the value did not already own one — a move, where
`emitFieldStores` writes the same move as a retain followed by a
release.

**The release belongs to the ARM.** One release reached every field of
a block through the shape word. A pair has no shape word, and
`(Result Int Error)` carries a machine word in `Ok` and a share in
`Err`; releasing unconditionally would hand `axiom_release` an `Int`
above 4096 to read as a block header. `pairPayloadClass` decides per
arm, positionally — `Some` and `Ok` take type argument 0, `Err` takes
argument 1 — because the constructor entries are polymorphic and
cannot answer it. A third type wants its own line there, which is why
it refuses rather than guesses.

**`scrutineeReleasable` is reused unchanged**, so a binder that escapes
still disables the release for the whole match.

**Getting the retain wrong is a leak, not a crash, and it happened.**
Retaining unconditionally double-counted an owned temporary:
`(Err (mkError ...))` at 100,000 iterations read **13.5 MB against
1.28 MB boxed**. After the fix, 1.30 MB. The gate now reads the arena
mark across 40,000 iterations and requires the bump to move under 4096
bytes; it measures 208.

## 6a. Benchmarked after building, 2026-09-01

Three findings, and the third corrects an earlier number in this
repository.

**1. Where `Option` lookups dominate, it does what it was designed to
do.** The interner benchmark of section 1, rebuilt by two STAGE-MATCHED
compilers - same source, same input, differing only in whether the code
generator has the specialisation - best of seven:

| variant | total | per lookup | wrapper |
|---|---|---|---|
| no `Option` at all | 0.9909s | 49.54 ns | — |
| boxed | 1.1340s | 56.70 ns | **7.15 ns** |
| register pair | 0.9917s | 49.59 ns | **0.04 ns** |

**99.4% of the boxing cost recovered, and 12.5% off the workload.** The
pair lands 0.08% above having no `Option` in the language at all —
better than the hand-written prototype's 96.9%, because the compiler
also removes the match-on-a-block the prototype left in place.

**2. On the compiler's own self-compile it is a wash.** Two
stage-matched pairs, in-process time:

    axcB (no specialisation)   1.1302s   1.1422s
    axc3 (with it)             1.1286s   1.1528s

−0.14% and +0.93% — the difference brackets zero and is run-to-run
noise. Seven of the nine `internFind` sites specialise, `pruneMark`
among them; the two that do not are the ones whose scrutinee is a
`let`-bound variable rather than a direct call, which is the
restriction working. **`internFind` is simply not hot enough in a
self-compile for seven specialised sites to move a 1.13s number.** An
earlier estimate of 3.9 million wrappers per self-compile, derived from
a compile-time delta rather than counted, was wrong.

**3. THE 38% WAS ENTIRELY A STAGE ARTIFACT, and this is what proves
it.** A stage-1 against stage-2 comparison read 38% off in-process
time. `axcB` and `axc3` are both stage-2 and differ by less than 1%.
The 38% was the difference between two BUILDERS, not two code
generators.

**AND IT CORRECTS THE PORT THAT MOTIVATED THIS WORK.**
`compat/SENTINELS` records `internFind`'s move to `(Option Int)` as
costing "about +4% on code generation", from two pairs reading +3.5%
and +4.6%. Removing that same cost now yields nothing measurable. Those
runs were taken when in-process time read 1.75s against 1.13s today —
the machine was around 55% slower, i.e. loaded — so the honest reading
is that **compiler-level differences of a few percent are not
resolvable on this machine**, and that +4% should be read as an upper
bound rather than a measurement. The block count is not subject to
this: it is exact, and it is what `check-unboxed-sums.sh` gates.

## 7. Status

**BUILT, 2026-09-01.** Section 4's specialisation is implemented in
`self_host/codegen.ax` and gated by `scripts/check-unboxed-sums.sh`:
`@F$pair` returning `{ i64, i64 }` beside an unchanged `@F`, a
call-site rewrite for a `match` on a direct call, and a refusal list
that keeps the boxed path for everything it does not handle. On the
compiler's own source it fires three times and rewrites eleven call
sites. The gated claim is the block count - 1 and 1 before, 0 and 0
after. The speed claim is NOT made: see the CHANGELOG entry for why the
38% a stage-1/stage-2 comparison showed is a stage artifact and 2.6% is
what this change can account for.

**THE CLAIM IS LIFTED, 2026-09-03** (§5b). `@F` is a boxing wrapper
rather than a second body, a pair is boxed at the call that needs a
block and charged there by the checker's mirror of the eligibility
test, and `restrict(no-alloc)` holds for a pair-shaped function on the
strength of its emitted IR. The five absence sentinels §5 names are
portable on their own terms, and the port is the next commit's.

The remainder of this section is what was written before it was built.

### Before it was built

**Designed, prototyped and costed. NOT built — no compiler code has
been changed.** What is established: the representation is free on
aarch64 through the real toolchain (§1, §3); a one-word niche cannot
express `Option Int` (§2); and inlining the allocator recovers 14% of
the box against the pair's 99%, so there is no cheaper fix (§3a).

What is not established: that `@F$pair` emission handles every tail
shape in the tree. That is the first thing to write and the first thing
that can fail, and §4 item 2 gives it a fallback that is correct when
it does.

**The honest reason this stops here rather than landing:** the change
is in the code generator of a self-hosted compiler that has to reach a
byte-identical fixpoint, and the failure mode of getting a return
convention half-right is a silent miscompile, not a red gate. It wants
its own change with its own gate (§4 item 5), not a tail added to the
port that measured it.
