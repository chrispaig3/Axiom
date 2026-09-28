# Unboxed small sums — making `Option` and `Result` free

This record measures what boxing `Option` and `Result` costs, shows a
representation that removes the cost, and records how the compiler
builds it. It is built: a function that returns an eligible `Option` or
`Result` hands back two registers, and a heap block is built only at a
call site that needs one. [§7](#7-status) has the timeline.

Without it, `(Some v)`, `(Ok v)` and `(Err e)` each allocate a 16-byte
heap block holding a refcount, a shape word, a tag and the field. The
block is built by `axiom_alloc` and handed back to the arena by
`axiom_release`. That is the whole cost of `Option` and `Result`. It is
also why `compat/SENTINELS` carried seven absence rows and nine failure
rows that the error-model migration wanted and couldn't have.

Every number below comes from a command in this record. The prototype
in §1 to §3 is hand-written LLVM IR derived from the compiler's own
output, so it measures the representation, not an implementation.

## 1. What the box costs, measured

The benchmark is a string interner with 2,000 names and 20,000,000
round-robin lookups, built with `--opt 2`, best of five whole-process
runs. That is the method `scripts/bench-datastructures.sh` and
`scripts/bench-compile.sh` both use. The timing distribution is
one-sided, so the minimum is the closest estimate of the cost itself.

Three variants of the same program differ only in what the lookup
returns:

| variant | total | per lookup | wrapper |
|---|---|---|---|
| raw `-1` sentinel, no `Option` at all | 1.6060s | 80.30 ns | — |
| `(Option Int)`, boxed (before this change) | 1.8432s | 92.16 ns | **11.86 ns** |
| `(Option Int)`, two registers (prototype) | 1.6133s | 80.67 ns | **0.36 ns** |

The box costs 11.86 ns and the register pair costs 0.36 ns. The
prototype recovers 96.9% of the cost and lands 0.45% above having no
`Option` in the language at all. At the resolution of this measurement,
that is free.

`None` was already free and stays free. A nullary constructor is an
immediate below 4096, with no block behind it, which is why the `none`
arm of `tests/diagnostics/384-restrict-no-alloc-ctor.ax` is silent.

### What that is worth at scale

`internFind` answering `(Option Int)` cost +3.5% on the compiler's
code-generation stage (`compat/SENTINELS`, its `internFind` entry).
Dividing that 46 ms by the 11.86 ns above puts roughly 3.9 million
`Some` blocks in one self-compile, from nine call sites. The
representation below deletes all of them. §6a shows that this
estimate was wrong.

## 2. The representation

A sum type whose constructors carry at most one word of payload is
passed and returned as `{ i64, i64 }`, meaning `{tag, payload}`,
instead of as a pointer to a block. `Option T` qualifies for every `T`.
`Result T E` qualifies whenever both arms are one word, which is the
shape `stdlib/Err.ax` uses everywhere.

The two-word cutoff comes from the ABI. Both supported architectures
return two words in registers: `x0`/`x1` on aarch64 and `rax`/`rdx` on
x86-64 SysV. At 16 bytes the ABI is still register-based on both. Past
that, both spill to memory through an indirect pointer and the win is
gone.

The backend already handles multi-word returns.
[checked-arithmetic-design.md](checked-arithmetic-design.md) notes that
`@llvm.sadd.with.overflow.i64` returns `{i64, i1}`, the same structure
as the division-by-zero trap the code generator already emits.
What is new here is using it for Axiom's own types.

### Why one word cannot be made to work

The obvious cheaper idea is a niche: represent `(Some x)` as `x` itself
and `None` as an immediate, the way a nullable pointer works. That is
correct for `Option T` when every `T` is a heap value, because heap
values are all at or above 4096 and can't collide with an immediate
tag.

It fails for the case that matters most. An `Int` in Axiom is a raw
`i64`, so `(Some 5)` would be `5`. Every `match` opens with the test
`icmp slt %v, 4096`, and under it `5` can't be told apart from an
immediate constructor tag. `Option Int` needs 65 bits, and one word
doesn't have them. The niche is a real optimisation for
`Option String` and similar types, but it can't replace this one.

## 3. The prototype, and what it proves

The prototype starts from the compiler's own emitted IR for the
benchmark above, with `Intern$internFind` and its one call site
rewritten by hand. The allocating tail of the function:

```llvm
.L8:
  %.t10 = call i64 @axiom_alloc(i64 16)
  %.t11 = add i64 %.t10, -8
  store i64 4, ptr %.t12          ; shape word
  store i64 0, ptr %.t14          ; tag
  store i64 1, ptr %.t16          ; refcount
  store i64 %.t3, ptr %.t18       ; the field
```

becomes:

```llvm
.L8:
  %.s0  = insertvalue { i64, i64 } undef, i64 0, 0    ; tag = Some
  %.s1p = insertvalue { i64, i64 } %.s0, i64 %.t3, 1  ; payload = the id
  ret { i64, i64 } %.s1p
```

The caller's twenty-eight instructions of immediate test, tag load,
field load and `axiom_release` collapse to:

```llvm
  %.pair = call { i64, i64 } @Intern$internFind(i64 %.t23, i64 %.t31)
  %.tag  = extractvalue { i64, i64 } %.pair, 0
  %.pay  = extractvalue { i64, i64 } %.pair, 1
  %.t51  = icmp eq i64 %.tag, 0
```

Both programs print the same checksum (`19990000000`) through the same
`opt -O2` / `llc -O2` / `cc` pipeline that `bench-compile.sh` uses.

This proves the representation is correct on this target (aarch64) and
costs nothing. It doesn't prove that the compiler can produce it for
arbitrary programs. §4 lists why that is a real project and not an
afternoon's work.

## 3a. The cheap alternative, measured and rejected

`axiom_alloc` and `axiom_release` are both defined in the emitted
module, but at `-O2` LLVM inlines neither. The optimised IR still reads
`tail call i64 @axiom_alloc(i64 16)` inside `internFind` and
`tail call void @axiom_release` in the caller, so each wrapper costs
two real calls. That suggests a far cheaper fix than changing any ABI:
emit the allocator's fast path inline at the construction site.

To measure it, both functions were marked `alwaysinline` and the same
pipeline was re-run. This is an upper bound on the idea, since it
inlines the slow paths too:

| variant | total | recovers |
|---|---|---|
| boxed, calls as emitted | 1.8454s | — |
| boxed, allocator and releaser inlined | 1.8112s | **14.3%** |
| two registers | 1.6080s | **99.2%** |

The call overhead is 14% of the box. The other 86% is the work itself:
the free-list pop, the shape word, the tag, the refcount, the field
store, the caller's immediate test and two loads, and the release's
refcount decrement and free-list push. Inlining removes none of that.
Not allocating removes all of it.

So changing the ABI is the only option that pays. This section exists
so the cheap idea isn't proposed again.

## 4. What building it actually touches

This plan replaced a first draft, which proposed a general
type-directed representation: every eligible value unboxed in flight
and boxed when stored (§4a). That draft named the storage boundary as
its largest piece of work and ownership without a shape word as the
next. Specialisation avoids both, and it is smaller and strictly safer.

### Specialisation, not a global representation change

Emit a second definition for a function whose declared return type is
an eligible sum: `@F` unchanged, plus `@F$pair` returning
`{ i64, i64 }`. Rewrite only the call sites where the result is
immediately matched, `(match (F args) arms)`, to call `@F$pair` and
read the tag and payload from registers. Every other caller keeps the
boxed `@F`, bit for bit.

This is the right shape for three reasons:

* **The storage boundary disappears.** The only rewritten site consumes
  the pair on the spot, so a pair never reaches a `let` that outlives
  the match, a `Vec`, a struct field or another function's argument.
  There is nothing to coerce, so no coercion can go wrong.
* **No per-node types are needed**, which matters because code
  generation doesn't have them. It needs exactly one fact it can
  already look up: the callee's declared return type, through
  `findFSigCg`.
* **It is opt-in and reversible per call site.** A shape the tail walk
  doesn't recognise keeps the boxed path, so the failure mode is "no
  speedup" rather than "wrong answer".

### Restrict the payload to a non-reference, at least at first

If the single field is a reference, the box owns a share of it, and
`axiom_release` on the wrapper hands that share back. A pair has no
refcount, so ownership would have to pass to the consumer. Getting that
wrong is a use-after-free, not a slowdown. `eFieldFlags` already
records which fields are references, so the eligibility test is
available where the decision is made.

Restricting to a non-reference payload gives up nothing that matters
here. `Option Int` is the shape of every row this unblocks:
`internFind`, `strHexVal`, `utf8DecodeAt`, `utf8CharAt`, `keyStrEnd`
and `strFindByte`. Reference payloads are a later slice with their own
ownership argument, and §5a adds them.

### What is left to build, in order

This is the plan as written before the build. §5a, §5b and §7 record
what was built.

1. **Eligibility.** A `data` type with `rep 2` whose fieldful
   constructors carry exactly one non-reference field. This is decided
   once per type, from the table `lookupType` already answers.
2. **`@F$pair` emission.** The body again, with tail-position
   constructor applications building `insertvalue` pairs instead of
   calling `emitConstructor`. The tail is a walk through `if`, `match`,
   `let` and `{}` down to the constructor applications. Any tail the
   walk doesn't recognise falls back to computing the boxed value and
   converting it, which is correct, just not faster.
3. **Call-site rewrite.** At `(match (F args) arms)`, call `@F$pair`
   and feed the existing arm lowering from the two `extractvalue`s
   instead of from the immediate test and the word loads.
4. **`restrict(no-alloc)` and the effect row.** `@F$pair` performs no
   `Alloc`, so `#effects=` narrows for the specialised path. §5 explains
   why that narrowing is the goal. `compat/BREAKING` still needs a
   `NARROWED` kind, and `scripts/check-compat.sh` needs to accept it.
5. **A gate.** The pair path must be proved taken, not assumed. The
   direct assertion counts `axiom_alloc` calls in the emitted IR for a
   fixture with a known number of matched lookups. An ablation that
   forces the boxed path must move that count.

### What this plan does not need

No FFI classification, because no `extern` sees a pair. No second
general `match` lowering path, because only the rewritten call sites
change. No container widening, and no change to how values are stored.
All of those came from the general design (§4a).

## 4a. Superseded: the general representation change

This design is kept as the fallback if specialisation doesn't cover
enough call sites, and because two of its items are real work any wider
version would still face. The items are ordered by how likely each is
to be the one that stops it.

1. **Storage is where the design can go wrong.** Unboxing works for
   values in flight: arguments, returns, locals and registers. A
   `(Option Int)` stored as a field inside another heap block is one
   word with boxing and would be two without it. So either every
   container widens, or the representation is coerced at the storage
   boundary. The rule would be "unboxed in flight, boxed when stored",
   with a coercion at each crossing. That is well understood, and it
   is the largest single piece of work here.
2. **Ownership needs the shape word.** A block's shape word tells the
   runtime which of its fields are references, and releasing the
   wrapper releases the payload too. An unboxed pair has no block and
   no shape word. When the payload is a reference, the consumer must
   emit the retain and release itself, from the static type. This is
   the same shape word this project's memory keystone already names as
   the wall (`K1 -> K2 -> K3`), approached from a new side.
3. **Effect rows narrow, which is a breaking change of a new kind.**
   `(Some v)` would stop performing `Alloc`, so every function whose
   only allocation was wrapping a result loses `Alloc` from
   `#effects=`. The kinds `compat/BREAKING` records are `CHANGED`,
   `WIDENED`, `REMOVED` and `RETIRED`. This needs `NARROWED`, and
   `check-compat.sh` has to treat narrowing as a contract change even
   though no caller pays for it.
4. **`restrict(no-alloc)` starts accepting constructor applications**
   of these types. The `some` arm of
   `tests/diagnostics/384-restrict-no-alloc-ctor.ax` would go from
   `AX3049` to silent. That changes both the golden output and the
   claim, and the fixture's own header says the `some`/`none` pair is
   the measurement. It would need rewriting around a type that still
   boxes.
5. **FFI.** `{i64, i64}` can be returned across the C ABI on both
   targets, but `rust/axiom-ffi-classify` would need a rule. The cheap
   first answer is to forbid unboxed sums across `extern` and revisit
   later.
6. **Match lowering.** For these types the tag is already in a
   register, so the `icmp slt %v, 4096` immediate test disappears and
   `match` grows a second lowering path, selected by the scrutinee's
   type.

## 5. What it unblocks, which is the actual argument for doing it

This is more than a speed change. When this section was written,
`compat/SENTINELS` recorded seven absence rows and nine failure rows,
after a correction removed three rows that were never portable
([error-model.md](error-model.md) §10.1). After §5b and the two ports
it permitted, it recorded three and zero. `docs/error-model.md` §10
keeps the current count.

Five of the seven couldn't move, for the reason `docs/error-model.md`
§10 gave. `strHexVal`, `utf8DecodeAt`, `utf8CharAt` and `keyStrEnd`
all read `#restrict=no-io,no-alloc,no-foreign`, so they couldn't
become `Option` without withdrawing a checked claim.

`strFindByte` reads the same three restrictions and is the fifth. It is
listed apart from the other four because its exclusion was argued on
cost (7.4× per call over its scanning-path sites) rather than on the
claim, but the claim refuses it either way.

The argument was: if `(Some v)` doesn't allocate, that blocker is gone.
Those four become `Option` and keep the claim they already make. The
argument in `docs/error-model.md` §10 (`Option` carries no `Error` and
still allocates) stops being true, because its second half stops being
true. The first slice didn't deliver this (§5b explains why), and §5b
does.

It also removes the standing objection to the rest of the failure
column. Every ERR-ADOPT-1 row in `compat/BREAKING` is `WIDENED`,
because building a `Result` allocates. `sysWriteFd`, `sysReadFd`,
`netAccept`, `netAcceptFrom` and `netPollWait` are excluded because
that widening lands under `println`'s 804 expansions. An unboxed
`Result` whose `Ok` arm carries one word widens nothing. The `Err` arm
still builds an `Error`, so the failure path still allocates, but the
failure path isn't the one those exclusions are about.

So the order is this change first, then the rest of ERR-ADOPT-1.
Doing the migration first would mean porting functions twice.

<a id="5a-result-and-reference-payloads-2026-09-01"></a>
## 5a. `Result` and reference payloads

The first slice refused both. They are admitted now, and the ownership
rule is the whole of the change.

A reference payload is a share. The block it replaces owned one, but
the pair has no refcount, so the share travels in the payload register
and the consumer gives it back. Construction retains only when
`valueOwnedRef` says the value didn't already own a share. When it did,
the pair moves that share and emits nothing. `emitFieldStores` makes
the same move for a block, written as a retain followed by a release.

The release belongs to the arm. For a block, one release reaches every
field through the shape word, but a pair has no shape word.
`(Result Int Error)` carries a machine word in `Ok` and a share in
`Err`, so releasing unconditionally would hand `axiom_release` an `Int`
above 4096 to read as a block header. `pairPayloadClass` decides per
arm, by position: `Some` and `Ok` take type argument 0, and `Err` takes
argument 1. It works by position because the constructor entries are
polymorphic and can't answer the question. A third type would need its
own line there, which is why a third type is refused rather than
guessed.

`scrutineeReleasable` is reused unchanged, so a binder that escapes
still disables the release for the whole match.

A wrong retain leaks rather than crashes, and it did happen. Retaining
unconditionally double-counted an owned temporary:
`(Err (mkError ...))` at 100,000 iterations used 13.5 MB against
1.28 MB boxed. After the fix it uses 1.30 MB. The gate reads the arena
mark across 40,000 iterations and requires the bump to move by less
than 4096 bytes. It measures 208.

<a id="5b-the-box-belongs-to-the-caller-2026-09-03--and-the-claim-is-lifted"></a>
## 5b. The box belongs to the caller, and the claim is lifted

<a id="the-no-alloc-claim-was-not-lifted-by-the-first-slice-measured-after-building"></a>
### Why the first slice did not lift the `no-alloc` claim

After the first slice, a `restrict(no-alloc)` function answering
`(Option Int)` in the specialised shape still drew `AX3049`, and the
checker was right. The boxed `@F` was still emitted for every caller
that didn't match immediately, so whether the function allocated
depended on the caller. `no-alloc` is a property of a function, but the
true version of it had become a property of the function *and* its
call sites: a whole-program question the effect walk didn't ask.

That question has a local answer: build the block where it is needed,
and charge the allocation there. That takes three changes: one in the
emitter, one in the checker, and a gate that holds the two to one
answer.

### The emitter writes the body once

A function in the pair set is emitted only as `@F$pair`. `@F` becomes a
wrapper that calls the pair and boxes what comes back
(`emitPairWrapper`). The wrapper is kept for a reference taken as a
value, and otherwise pruned along with every other unreferenced
definition. Every direct call to `F` calls the pair:

* a `match` on it reads the registers, as before;
* a tail leaf of another pair function forwards the two registers
  (`pairFwdOK`; `utf8CharAt` ends in `(utf8DecodeAt s i)`);
* any other site, such as a `let` that outlives the match, an argument,
  a field store or a statement, boxes the pair in the caller's own
  definition. It writes the same shape word, tag, count and field that
  a boxed constructor writes (`emitPairBox`).

Since nothing is written twice, the "body shape" refusal that kept a
`while`, a `set` or a lambda out of the pair is gone. A tail match that
the tail emitter could only lower boxed is routed to the ordinary
emitter (`pairTailDelegates`), so every `pairMatchOK` match reads
registers. On the compiler's own source, this grew the pair set from 8
functions to 24.

### The checker charges the block where the emitter builds it

`self_host/typecheck.ax` carries a mirror of `pairFnOK`: the same
eligibility test, asked of the checker's own tables (`tcPairFnOK`,
`tcPairTails`, `tcPairMatchOK`). The effect walk uses it in three ways:

* a constructor leaf in an eligible function's tail contributes no
  `Alloc`;
* a call to a pair function contributes `Alloc` unless it is a recorded
  site, meaning a matched direct call or a forwarding leaf;
* a pair function named as a value contributes `Alloc` for the wrapper
  it reaches.

So `internFind`, `pathLastSlash` and `scopeFindIdx` show no `Alloc` in
`axiom symbols` now. A caller that stores their answer past its match
shows the `Alloc` they used to carry.

### A gate holds the two to one answer

Section 5 of `scripts/check-unboxed-sums.sh` asks `axiom check` about
three claims at once. `restrict(no-alloc)` is accepted on the lookup,
accepted on a caller that matches it directly, and refused with
`AX3049` on a caller that `let`-binds the answer. The gate reads the
same split from `symbols` and from the IR.

Section 6 runs `scripts/lib/alloc-rows.py` over the whole self-compile.
It holds every function whose row lacks `Alloc` to a definition with no
`axiom_alloc`: 3,482 rows held, 0 disagreements. The mirror may
over-charge but must never under-charge. Both files state that
direction, and section 6 is what would notice it going the other way.

The `some` arm of `tests/diagnostics/384-restrict-no-alloc-ctor.ax` is
silent now. Its `held` arm stores the answer and is refused, which
shows the silence is earned.

### What this does not do

* A self-tail-recursive function still keeps the boxed shape.
  `tailCallsSelf` is still a refusal, because the loop header and the
  pair return haven't been reconciled. So a recursive `strFindByte`
  can't take the pair. `stdlib/Str.ax` writes it as a loop, which can.
* A `match` in tail position of a pair function is still not a tail the
  pair recognises.
* Any third sum type, meaning anything but `Option` and `Result`, is
  still refused by name.

Each of these is a refusal, not a wrong answer. The fallback is the
boxed path with `Alloc` charged, and the mirror charges it too.

## 6. Reproducing the measurement

```bash
axiom build --opt 2 --input bench.ax --output bench     # the three variants
axiom emit-llvm --input bench.ax -o bench.ll            # then hand-edit
opt -O2 bench.ll -S -o bench.opt.ll
llc bench.opt.ll -filetype=obj -o bench.o -O2 -relocation-model=pic
cc bench.o -o bench.exe
```

The benchmark interns 2,000 `"name{i}"` strings into one `Intern` and
pre-builds the handles into a `Vec`, so the timed loop allocates no
strings of its own. It sums the ids over 20,000,000 round-robin lookups
so nothing is dead code. The three variants differ only in the
body of the loop: a raw `-1` compared against zero, a `match` on a
boxed `(Option Int)`, and a `match` on the register pair.

<a id="6a-benchmarked-after-building-2026-09-01"></a>
## 6a. Benchmarked after building

### Where `Option` lookups dominate, it does what it was designed to do

The interner benchmark from §1, rebuilt by two stage-matched compilers
(same bootstrap stage, same source and input, differing only in whether
the code generator has the specialisation), best of seven:

| variant | total | per lookup | wrapper |
|---|---|---|---|
| no `Option` at all | 0.9909s | 49.54 ns | — |
| boxed | 1.1340s | 56.70 ns | **7.15 ns** |
| register pair | 0.9917s | 49.59 ns | **0.04 ns** |

The pair recovers 99.4% of the boxing cost and takes 12.5% off the
workload. It lands 0.08% above having no `Option` in the language at
all. That beats the hand-written prototype's 96.9%, because the
compiler also removes the match on a block that the prototype left in
place.

### On the compiler's own self-compile, it is a wash

Two stage-matched pairs, in-process time:

```text
axcB (no specialisation)   1.1302s   1.1422s
axc3 (with it)             1.1286s   1.1528s
```

The differences, −0.14% and +0.93%, bracket zero: run-to-run noise.
Seven of the nine `internFind` sites specialise, `pruneMark` among them. The two that don't are the ones whose
scrutinee is a `let`-bound variable rather than a direct call, which is
the restriction working as designed. `internFind` isn't hot enough in a
self-compile for seven specialised sites to move a 1.13s number. The
estimate of 3.9 million wrappers per self-compile in §1 came from a
compile-time delta rather than a count, and it was wrong.

### The 38% was entirely a stage artefact

A stage-1 against stage-2 comparison showed 38% off in-process time.
`axcB` and `axc3` are both stage-2 and differ by less than 1%. So the
38% was the difference between two builders, not between two code
generators.

This also corrects the port that motivated this work.
`compat/SENTINELS` records `internFind`'s move to `(Option Int)` as
costing "about +4% on code generation", from two pairs reading +3.5%
and +4.6%. Removing that same cost now yields nothing measurable. Those
runs read 1.75s in-process against 1.13s here, so the machine was
around 55% slower: it was loaded. Compiler-level differences of a few
percent can't be resolved on this machine, so read that +4% as an upper
bound, not a measurement. The block count is exact, and it is what
`scripts/check-unboxed-sums.sh` gates.

## 7. Status

| Date | Status | Sections |
|---|---|---|
| — | Designed, prototyped and costed, with no compiler code changed | §1 to §4 |
| 2026-09-01 | Built: `@F$pair` beside an unchanged `@F`, and a call-site rewrite for a `match` on a direct call | §4, §7 |
| 2026-09-01 | `Result` and reference payloads admitted | §5a |
| 2026-09-01 | Benchmarked; `restrict(no-alloc)` still not lifted | §5b, §6a |
| 2026-09-03 | Box moved to the caller; `restrict(no-alloc)` claim lifted | §5b |

The first slice implemented §4's specialisation in
`self_host/codegen.ax`, gated by `scripts/check-unboxed-sums.sh`. It
added `@F$pair` returning `{ i64, i64 }` beside an unchanged `@F`, a
call-site rewrite for a `match` on a direct call, and a refusal list
that keeps the boxed path for everything it doesn't handle. On the
compiler's own source it fired three times and rewrote eleven call
sites. The gated claim is the block count: 1 and 1 before, 0 and 0
after. No speed claim is made. The [CHANGELOG](../CHANGELOG.md) entry
explains why the 38% a stage-1/stage-2 comparison showed is a stage
artefact, and why 2.6% is what this change can account for.

§5b then made `@F` a boxing wrapper and boxed a pair only at the call
that needs a block. The checker's mirror of the eligibility test charges
the block there. `restrict(no-alloc)` now holds for
a pair-shaped function on the strength of its emitted IR, and the five
absence sentinels §5 names became portable on their own terms.

### Before it was built

This record first stopped at design, prototype and cost, having
established three things:

* the representation is free on aarch64 through the real toolchain
  (§1, §3);
* a one-word niche can't express `Option Int` (§2);
* inlining the allocator recovers 14% of the box against the pair's
  99%, so there is no cheaper fix (§3a).

It had not established that `@F$pair` emission handles every tail
shape in the tree, which was the first thing that could fail. §4 item 2
gives it a correct fallback.

The change is in the code generator of a self-hosted compiler that has
to reach a byte-identical fixpoint, and a half-right return convention
fails as a silent miscompile, not a failing gate. So it needed its own
change with its own gate (§4 item 5), not a tail added to the port that
measured it.
