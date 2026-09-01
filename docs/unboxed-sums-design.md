# Unboxed small sums — making `Option` and `Result` free

`(Some v)`, `(Ok v)` and `(Err e)` allocate. Every one of them is a
16-byte heap block with a refcount, a shape word, a tag and the field,
built by `axiom_alloc` and handed back to the arena by
`axiom_release`. That is the entire cost of `Option` and `Result` in
Axiom today, and it is the reason `compat/SENTINELS` still carries nine
absence rows and ten failure rows that the migration wants and cannot
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

This is not only a speed change. `compat/SENTINELS` records **nine
absence rows and ten failure rows**, and the reason four of the nine
cannot move is stated there and in `docs/error-model.md` §10:

> `strHexVal`, `utf8DecodeAt`, `utf8CharAt` and `keyStrEnd` all read
> `#restrict=no-io,no-alloc,no-foreign`. They cannot become `Option`
> without WITHDRAWING a checked claim.

**If `(Some v)` does not allocate, that blocker is gone** — those four
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
