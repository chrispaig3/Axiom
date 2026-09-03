# Regions — a design pass at Axiom's own memory model

This is a **design note**, not a specification. `docs/memory-model.md`
remains the normative source; nothing here is binding until a rule
moves there. It follows the convention
[docs/checked-arithmetic-design.md](checked-arithmetic-design.md) set:
every claim below carries the command that established it, and the
claims that are *not* measured say so in the same sentence.

It answers a narrower question than its title. Three decisions were
taken rather than argued for, and the note reasons from them:

- the mechanism is **typed regions**, declared rather than inferred —
  Ada's accessibility rules rather than Rust's lifetime inference;
- concurrency is **one surface with two lowerings** — threads inside a
  process, processes across, the same source and the same determinism
  guarantee under both;
- **typed regions are the destination, S3 included** (2026-08-31).
  This note's own §5 was written as a case for deferring the
  type-system stage until three probes had been run. That was a
  recommendation and it was overruled: the direction is settled, and
  §5's probes now **size** S3 rather than decide whether it happens.

**What that decision is buying, and it is better than it looked when
the decision was taken.** §5's probes 1 and 2 were run the same day and
both came back for the design; only probe 3, which is S4's own gate,
remains. The measurement in §1.1 that cuts the other way still stands —
counting buys a **2.4×** reduction in peak RSS for **no wall-clock cost
this machine could measure** — but the scaling argument now rests on a
measurement rather than on an expectation (§5, probe 2, run
2026-08-31 over the IR that `scripts/check-static-release.sh` counts):
**69.7–80.8%** of the call-result
releases have no escape channel out of their function, so a region
model takes this compiler's release traffic from 10,849 sites to
roughly **1,300–1,900** (§5, probe 2).

The safety argument does not depend on any of that and is not in doubt:
two of the arena's three program obligations are unchecked today
(§1.3), the surface syntax for scoping was deleted on the strength of
an inference that was then withdrawn (§1.4), and typed regions make
`MM-PAR-6`'s "no cross-thread reference" a corollary rather than a
second system (§3.2). Those are the reasons to build this that were
already measured when the decision was taken.

Rule identifiers below are proposed, marked **(D)** for *design*, and
belong to a new `MM-RGN-*` series. None is normative and none appears
in §9's conformance table. `scripts/check-doc-drift.sh` section 8
refuses a rule header defined twice, so the series is reserved by being
written down here.

Measured on the compiler built from this worktree at `19cb860` by
`./scripts/build-shared-axc.sh /tmp/axc-mm2/axc`, on darwin-aarch64.

---

## 1. The measured starting point

### 1.1 What reference counting costs, measured by removing it

The compiler's own emitted IR is the largest Axiom program there is.

```
$ /tmp/axc-mm2/axc emit-llvm self_host/main.ax -o selfhost.ll
$ wc -l selfhost.ll ; grep -c '^define' selfhost.ll
  197562 selfhost.ll
    3469
$ grep -c 'call void @axiom_release' selfhost.ll   # 10849
$ grep -c 'call void @axiom_retain'  selfhost.ll   #   679
```

Deleting **all 10,849** `axiom_release` call sites from that IR, then
rebuilding with the same `llc` and `cc` the arena-rate gate uses
(`llc -filetype=obj -relocation-model=pic`, `cc … -e _main`), gives a
compiler that is not a correct program — it never frees anything — but
is the same *function*: asked to compile `self_host/main.ax` it writes
byte-identical output.

| | peak RSS | binary | output |
|---|---|---|---|
| as emitted | **406,032 KiB** | 1,552,840 B | — |
| every release deleted | **954,464 – 973,984 KiB** | 1,404,080 B | byte-identical |

So the counting traffic buys a **2.4× reduction in peak RSS** and costs
**9.6% of the binary**. The RSS figure is deterministic on the baseline
arm — 406,032 KiB on all five runs, to the kilobyte.

**Wall-clock is not among the findings, and the reason is worth more
than a number would have been.** A first set of three runs put the
ablated compiler 9% faster and looked conclusive. Re-run later on the
same machine under a different load, the arms interleaved
(24.4–27.5 s ablated against 26.4–26.6 s as emitted) and the signal was
gone. This note therefore claims **no wall-clock effect**, in either
direction, and a design that needs one owes the measurement on an idle
machine. That is the same correction `MM-ALLOC-16a`'s A/B made on this
branch a day earlier, and making it twice in two days is the argument
for making it a habit.

### 1.2 The traffic is 16:1 in one direction, and half of it is a no-op

`axiom_release` appears at 10,849 sites and `axiom_retain` at 679 — a
ratio of **16:1**. Per function:

| | functions | share |
|---|---|---|
| release sites, and **no retain site at all** | **1,211** | 34.9% |
| both | 390 | 11.2% |
| retain only | 80 | 2.3% |
| neither — no ownership traffic | 1,788 | 51.5% |

The 1,211 release-only functions carry **9,341 of the 10,849
releases — 86% of the program's release traffic**. A reference count
that is only ever decremented is not a reference count. It is a scope,
implemented one object at a time.

Classifying every release site by what defines the value released:

| defined by | sites | share |
|---|---|---|
| **a static string literal** (`@strhdr_*`) | **5,762** | **53.1%** |
| the result of a call (callee-allocated, owned) | 4,636 | 42.7% |
| a load — a field or a frame slot | 338 | 3.1% |
| a phi | 110 | 1.0% |
| a parameter (borrowed) | 3 | 0.0% |

Every one of the 5,762 is a `@strhdr_*` global — a literal whose count
word is the static sentinel `-1`. `@axiom_release` handles it by
loading the count, comparing against `-1`, and returning. **Over half
the release traffic in the compiler is a call that cannot free
anything, and the operand's definition says so at compile time.**

Ablating only those 5,762 gives byte-identical output, a binary
**5.3%** smaller (1,470,256 B), and peak RSS at or slightly below
baseline (361,856–405,984 KiB) — as it must be, since deleting a call
that frees nothing cannot cost memory.

**This is a finding, not a design.** It needs no region, no type-system
change and no new rule: it is a compile-time test on the operand's
definition, and it is worth reporting separately from everything below.
It is Stage 0 in §4.

The three releases on a *parameter* are the other end of the same
story. `MM-LIFE-2c` event 1 — a call borrows its arguments, taking no
share — is a no-op by design, and the three sites are what the same
classification above reports for it: the probe is the last row of that
table, produced by the same pass over `selfhost.ll` that produced the
other four, not a separate assertion.

### 1.3 The arena already wins, and two of its three obligations are unchecked

`MM-ALLOC-22` settled the strategy question on 2026-08-24: the arena
scope *is* the reclamation strategy. Its evidence is
`scripts/check-net.sh` — a request handler bracketed by
`__axiom_arena_mark`/`__axiom_arena_reset` measures **100–313× less
peak RSS** than the same binary unscoped — and the LSP's per-edit
footprint, **840 bytes bracketed against 193,247**.

What the arena does not have is a checker. Three program obligations
(`MM-ALLOC-16`, `16a`, `16b`) say what a program must not do and, until
2026-08-31, nothing said it when a program did. `16a` is now an
implementation obligation that traps with status 75
(`tests/stdlib/166-arena-bad-mark.ax`). **`16` and `16b` remain
unchecked**: what may be read after a reset, and that an evidence
record's extent must not be reset past.

### 1.4 The syntax for scoping memory was deleted on a promise that was then withdrawn

`region` was a keyword. It is refused today, and the refusal explains
itself:

```scheme refused
(region r)
(:: main Int)
(fn (main) 0)
```

```text
error[AX2004]: `region` is no longer part of Axiom
  = `region` was removed: allocation lifetime is inferred from where a
    value is created and how far it escapes, not written by hand
  = help: delete the `region` wrapper and keep its body; values are
    dropped deterministically at the end of the arena they belong to
```

**Both sentences describe a model that does not exist.** The inference
they name is §3.4's, and every rule in §3.4 is **W**: `MM-ALLOC-17`
(the implicit per-activation arena), `MM-ALLOC-18` (escape promotion —
"Tofte–Talpin region inference with the annotations removed, **which is
why `region` was deleted from the surface syntax**"), `MM-ALLOC-19`
(the tail-call reset). §3.4's own verdict is the correction: *"What
replaced it is an arena a PROGRAM brackets, not one a compiler
infers."* `MM-ALLOC-17`'s own *Today* line reads "nothing is reclaimed
at return."

So the language deleted the annotation on the ground that it would be
derived, then withdrew the derivation, and the diagnostic still tells
every reader who writes `region` that the compiler does the work. The
question was never re-opened. This note re-opens it.

*Re-opened and answered, 2026-09-03:* `region` is a keyword again — S2
in §4 — and the advice is gone from the parser, from `explain AX2004`,
from README and from reference.md alike. One more measurement belongs
beside the refusal quoted above: it fired only at the TOP level. In
expression position, where a region belongs, `(region r 0)` drew
`AX3001 undefined variable region` and a second `AX3001` for `r`, so a
reader who wrote one where it made sense was never told anything at
all.

---

## 2. The design

### 2.1 The runtime already exists; what is missing is the discipline

**MM-RGN-1 (D). A region is an allocation scope with a statically
known, lexically nested extent.** `(region r EXPR)` binds the region
name `r` over `EXPR`'s dynamic extent.

The critical property is that **this needs no new runtime.**
`@__axiom_bump`, `@__axiom_bump_end` and `@__axiom_chunk` *are* the
current region. `__axiom_arena_mark` captures it, `__axiom_arena_reset`
restores it, `__axiom_arena_reset_keeping` restores it while promoting
one value out (`MM-ALLOC-15`, gated by
`tests/stdlib/165-arena-keep.ax`). Today's allocator is already a
region allocator that has exactly one region and never resets it.

What v2 adds is a **static discipline** over machinery that is built,
measured and gated. That is the whole reason to prefer this mechanism
over the alternatives: the 100–313× is already banked.

### 2.2 Regions are lexical, so "outlives" is a tree order, not an inference

**MM-RGN-2 (D). Region extents nest, and the nesting is the outlives
relation.** `r` outlives `s` iff `s`'s block is inside `r`'s. Two
sibling regions are unordered — neither outlives the other.

This is the single largest simplification over a borrow checker and the
reason the note reaches for Ada rather than Rust. Rust infers lifetimes
from control flow, so it needs inference, variance, and a solver.
Axiom's regions are written, so the order is **known at parse time**
and the check is a tree comparison. `MM-ALLOC-16a`'s nesting
requirement is already exactly this order, stated as a program
obligation and now trapped — §1.3.

### 2.3 One rule does the work

**MM-RGN-3 (D), the escape rule. A value in region `s` MUST NOT be
stored into, returned into, or captured by anything in a region that
outlives `s`.**

That is the whole safety argument. It subsumes:

- `MM-ALLOC-16` — "what may be read after a reset" becomes unspellable
  rather than unchecked, because reading a `@s` value after `s` ends
  requires naming it outside `s`;
- `MM-ALLOC-16b` — an evidence record's extent is a region, and
  resetting past it is an outer region ending before an inner one,
  which the nesting refuses;
- `MM-LIFE-2g`'s invisible store — a store that erases a type is
  refused unless the target's region is the value's or shorter, which
  is what `__retainref` is currently a runtime apology for.

### 2.4 The common case carries no annotation

**MM-RGN-4 (D). A signature that names no region is region-monomorphic
in the caller's current region.** Every reference parameter and the
result share it.

This is the ergonomics half and it is what makes v2 **backward
compatible by construction**: a program that never writes `region` has
exactly one region, never reset, plus today's counting — which is
today's semantics, byte for byte. The 1,211 release-only functions of
§1.2 are precisely the shape this default is for; none of them would
gain an annotation.

Only a function relating **two** regions names them:

```scheme fragment
(:: parse (-> (Str @r) (Ast @r)))

(:: intern (-> (Str @s) (Table @r) (Sym @r)))
```

`intern` is the interesting one: it reads a short-lived string and
answers a symbol in the long-lived table's region. The signature says
so, and `MM-RGN-3` then refuses a `Sym` that points into `@s`.

**This is the claim most likely to be wrong, and §5 says how to falsify
it.** The corpus has never been swept for functions that relate two
regions, because there has never been a region to relate.

### 2.5 What carries the witness at runtime

**MM-RGN-5 (D). A region-polymorphic function takes one hidden trailing
word per region parameter, holding that region's mark cell.**

This is not a new mechanism. `MM-LIFE-2d`'s **evidence word** already
threads one hidden trailing `i64` per polymorphic function, computed at
the call site from static types, and `EV_LAMARG` already extends it to
a lambda's own parameter by depth (`self_host/typecheck.ax`). A region
witness is the same shape and the same call-site computation.

Most functions need none: under `MM-RGN-4` they allocate in the current
region, which is the global bump pointer they already use, so their
emitted code does not change at all.

### 2.6 Reclamation, and what survives of counting

**MM-RGN-6 (D). A region reclaims its own extent in one pointer move.
Reference counting survives only where a value outlives its region.**

Inside a region, a value that does not escape needs no retain and no
release — the reset reclaims it. A value that escapes to an outer
region is promoted at the boundary, which is `reset_keeping`,
which exists.

Counting is not deleted. It stays for: the `Foreign` drop path
(`MM-FFI-*`), values promoted across a region boundary, and any value
whose region cannot be decided statically. `MM-LIFE-3`'s cycles remain
uncollected and this design does not change that — a cycle inside a
region dies with the region, which is strictly better than today, but a
cycle promoted out still leaks.

### 2.7 What is taken from Ada, precisely

Named, so the inspiration can be checked rather than gestured at:

- **Accessibility levels.** Ada refuses an access value that would
  outlive its designated object's scope; `MM-RGN-3` is that rule with
  regions as the levels. Ada checks statically where it can and
  dynamically where it must — and Axiom now has the dynamic half, the
  status-75 trap of `MM-ALLOC-16a`, for the cases the static rule
  cannot reach.
- **Storage pools.** Ada lets a type name the pool it allocates from. A
  region parameter is that, made a type parameter.
- **`pragma Restrictions`.** Already in the tree, already checked:
  `restrict(no-io, no-alloc, …)`, `AX3049`, `scripts/check-restrictions.sh`.
  Regions add `restrict(no-escape)` — a declaration that allocates only
  in its own region — on the same rail, checked by the same walk.

Not taken: Ada's **controlled types and finalization**. Axiom has no
destructors and `ERR-REC-1` depends on there being none — nothing runs
on the way out. A region reset runs no user code, and that is a
property to keep.

---

## 3. Concurrency — one surface, two lowerings

### 3.1 The thread lowering is one primitive and one function body away

`cgThreads` (`self_host/codegen.ax`) is the single predicate deciding
whether the emitted runtime's mutable globals are thread-local. It
answers `false` for every program, and its own comment says why that is
not a limitation but an unwritten line:

> What is still owed is the predicate's body: a scan of the resolved
> declarations for `__thread_spawn` … That primitive does not exist
> yet, so neither does the scan.

Everything downstream is built. `cgMutGlobal` is consulted at all eight
sites (five allocator words, the slab array, `@__axiom_recover_top`,
one evidence slot per declared effect). The storage class is
`internal thread_local(localexec) global`, and local-exec is mandatory
rather than preferred — the general-dynamic model imports
`__tls_get_addr`, and `scripts/check-freestanding.sh` requires zero
undefined symbols. `scripts/check-thread-local.sh` measures the ON path
by ablating `cgThreads`'s body, because a storage class no program can
select is one no ordinary gate can reach.

The OFF path is the half worth more: on Darwin a thread-local access is
an indirect call through libSystem's `__tlv_bootstrap`, and
`axiom_alloc` touches four of these globals on its fast path — so a
language that made every program pay would take the whole tree out of
`MM-FFI-1`'s tier 1. It does not. A program that spawns no thread is
byte-identical on every target.

### 3.2 Region-per-thread makes `Send` structural

`MM-PAR-6` (**P**) already commits the specification to "one arena per
thread with no cross-thread reference, values handed to a thread copied
or moved, results moved into the parent's arena at join, and
combination in argument order."

With regions typed, **"no cross-thread reference" is `MM-RGN-3` applied
to sibling regions.** A thread's region is not nested inside another
thread's; by `MM-RGN-2` neither outlives the other; so every
cross-thread reference is already refused by the rule that is there for
single-threaded code. **There is no `Send`, no `Sync`, and no auto-trait
— thread safety is a corollary of the memory model rather than a second
system layered on it.**

That is the payoff for choosing regions over the alternatives, and it
is why the two decisions in this note's preamble are one decision.

### 3.3 The surface, and the two lowerings

**MM-RGN-7 (D).** One construct:

```scheme fragment
(parallel p
  ((a (handle conn1))
   (b (handle conn2)))
  (combine a b))
```

Each binding runs in **its own region**, siblings under `p`. Results
are moved into `p` at join — the `reset_keeping` promotion of §2.6.
Combination is in **argument order**, always, because `MM-PAR-5`
requires submit-order results and every byte-comparing gate in the
repository depends on it (`tests/stdlib/302-job.ax` pins ascending
output with children whose completion order is deliberately reversed).

| | threads | processes |
|---|---|---|
| sibling regions are | thread-local bump pointers | separate address spaces |
| the eight globals | `thread_local(localexec)` | private after `fork`, free (`MM-PAR-3`) |
| results cross as | a promotion into `p` | bytes, through a descriptor |
| `MM-FFI-1` tier | 3 — thread creation names libSystem | **1 — zero undefined symbols** |
| `MM-RGN-3` is | a load-bearing static check | a redundant check over an isolation that already holds |

The last row is the property that makes two lowerings worth having
rather than a hedge: **the check is the same under both**, so a program
developed and gated under the process lowering — where safety is
`MM-PAR-3`'s by-construction guarantee and costs nothing — is already
proved safe for the thread lowering. Isolation is the conservative
lowering, not the fallback one.

`stdlib/Job.ax` and `sysForkProcess` are the process lowering's
existing machinery; `tests/net/echo-server.ax`'s pre-forked pool is the
shape, and it is where `MM-ALLOC-22`'s measurement is taken.

---

## 4. Staging

Ordered so each stage is independently valuable and independently
gated, and so nothing later is a prerequisite for the win in anything
earlier. Ablation-before-fix is this repository's convention and every
gate below follows it.

| # | Stage | Cost | Gate |
|---|---|---|---|
| **S0** | **DONE 2026-08-31. Stop emitting the 5,762 no-op releases** on static literals (§1.2) | one compile-time test on the operand's definition; no rule, no type change | `scripts/check-static-release.sh`. 5,762 static releases became **5**, total release sites 10,849 -> 5,117, the compiler binary 5.6% smaller, emitted output byte-identical. The gate ablates `isStaticSentinelNode`'s answer, rebuilds, and requires the count back in the thousands — and asserts separately that a join over a literal still gives its share back, which is the trap the obvious one-line fix falls into |
| **S1** | **DONE 2026-08-31. `MM-ALLOC-16b` alone** becomes checked, as `16a` did — a reset that would reclaim a live `handle`'s evidence record | one gated call in `resetbody`, one on the unwind walk, and `@__axiom_ev_check` over the effect slots | `tests/stdlib/167-arena-live-handle.ax`, exit **76**. Before: the operation ran off reclaimed memory and the program **exited 0**. The two legal shapes beside it stay silent, and `401-recover-effect.ax` still exits 71 — the recovery path needs no exemption because it restores every slot *before* it resets. Byte-identical IR for a program declaring no effect, `self_host/` included |
| **S2** | **DONE 2026-09-03. `region` returns as a checked scope with no types yet** — mark/reset on a STACK cell, names scope-checked (`AX3058`), `AX2004`'s false advice deleted. "No typechecker change" was wrong as written and is corrected here: without types the checker still has to refuse the two escape channels a scope can see — the region's own value when it is not a scalar, and a `set` on a binding bound outside the region when the stored value is not one — as `AX3059`, or the reset hands a program a dangling descriptor with every gate green | a real node (`TAG_E_REGION`, so S3 can find extents) + the open-region stack + the value/store rule in `typecheck.ax`; `emitRegion` is three loads, one hoisted `alloca` and the existing `@__axiom_arena_reset_fn` | `scripts/check-region-scope.sh`: a no-region program emits no cell; 4,000 × 64 KiB with the region against without is 185x on peak RSS; `tests/diagnostics/631` draws exactly its three rows; and the ABLATION — `rgTyScalar` answering 1 — builds a compiler under which `hello world` stored out of a region reads back as `XXXXXXXXXXX`, the next allocation. `tests/stdlib/168-region.ax` (ten terms). Byte-identical IR for a program with no region, measured against the previous commit's compiler on `self_host/main.ax`: 202,021 lines both ways. NOT done here, by design: a reference leaving a region, which is S3's typed promotion, and the two channels a scope cannot see (a call that stores, a raw `Int`), which stay `MM-ALLOC-16`'s obligation |
| S3 | Region-parameterised types and `MM-RGN-3` | the real work: typecheck, the witness of §2.5 | `tests/diagnostics/*` per escape shape, plus the two-region corpus sweep of §5 |
| S4 | Delete ownership traffic the region proves dead | codegen | **re-run §1.1's ablation and expect the binary win with the RSS win intact** — the one measurement that decides whether any of this was worth it |
| S5 | `__thread_spawn`, and `cgThreads`'s owed body | the primitive, the scan, the thread runtime | `check-thread-local.sh` already exists for the ON path; `check-freestanding` pins tier 1 for everyone else |
| S6 | `parallel`, both lowerings | surface + two backends | one fixture, two lowerings, byte-identical stdout; `MM-PAR-5`'s argument order under both |

**`MM-ALLOC-16` is not in S1, and the first draft of this table was wrong
to put it there.** That row read "`MM-ALLOC-16`/`16b` become checked,
as `16a` did — one branch each". `MM-ALLOC-16`'s own text refuses the
premise: *"These three carry a contract the compiler **cannot** check:
after a reset, nothing allocated since the matching mark may be read
again."* Deciding whether a value is read after its arena reset is a
dataflow question about where values came from, which is `MM-RGN-3` —
**S3**, not a branch in a runtime helper. `16b` is genuinely different:
it names a fault whose two operands, the evidence record's address and
the reset's waterline, are both concrete at run time, which is why it
survives in S1 and its sibling does not.

The error is recorded rather than quietly corrected because it is the
same error this document catalogues elsewhere — §1.4's `region`
removal, and the three withdrawn proposals of
`memory-model-v2-proposal.md` — a cost estimated from a sentence
nobody re-read. This one was caught before anything was built, by
reading the rule the row cited.

**S0 and S2 are worth doing whether or not the rest is ever built.**
S0 is a measured 5.3% of the binary for a compile-time test. S2 makes a
diagnostic stop advertising a model that was withdrawn.

---

## 5. What would falsify this

Stated as probes, because this note's own §1.1 is an example of a
number that did not survive being taken twice.

**These size S3; they no longer decide it** — see the decision recorded
in §0. Probe 1 sets how much annotation the design costs a reader,
probe 2 sets how much traffic it can actually delete, and probe 3 is
S4's own gate. A bad answer to probe 2 does not now cancel the work; it
narrows what the work is allowed to claim.

1. **The two-region sweep — RUN 2026-08-31, and it comes back with two
   numbers rather than one.** §2.4 claims the common case carries no
   annotation. A structural proxy over 5,841 `fn` declarations in 575
   files — a store whose *target* arrives through one parameter and
   whose *value* derives from a different one — finds **349, 5.98%**,
   and a hand audit of a 40-function sample narrows the real figure to
   **3.5–5.2%**. 52.8% of declarations cannot need an annotation for
   the trivial reason that they take fewer than two parameters, and
   `stdlib/` pays only 36 of the 349 — the containers are written once
   and instantiated everywhere, which is the shape the ergonomics claim
   wants.

   **The second number is the risk and it belongs beside the first.**
   Region polymorphism instantiates at the call site, so a caller whose
   arguments share a region writes nothing — but a caller *itself*
   split across two regions must name them, and that propagates.
   Following the relation up the call graph reaches **1,006
   declarations, 17.2% of the corpus and 29.9% of `self_host/`** —
   `substTpl`, `expandExpr`, `emitExpr`, `emitDiag`, `walkEffects`, the
   compiler's main spines. 5.98% and 29.9% are the two ends of the real
   answer, and which end a program lands on depends on how deep a
   region split it actually makes. Today's corpus cannot say, because
   there is no region in it to split on. §2.4 is not refuted; it is no
   longer free, and it may not be quoted without this paragraph.

2. **The escape fraction — RUN 2026-08-31, and it carries the scaling
   argument.** Of the **4,668** releases on call results in the
   compiler's own IR, between **69.7% and 80.8%** are on values with no
   escape channel out of their function — string-concatenation
   intermediates, overwhelmingly. The claim this probe was set against,
   "if most of those values escape, typed regions delete very little",
   is **falsified**: most do not escape. With the static-literal fix of
   S0 already landed, a region model takes the release traffic from
   10,849 sites to roughly **1,300–1,900**.

   **Two things it does not license.** The residue is not noise, it is
   the design's hard case: `vecPush`, `memSetWord`, `mkNodeAt`, a
   short-lived value stored into a longer-lived structure — verbatim
   the shape probe 1 says makes `MM-RGN-4`'s default wrong, and it puts
   a floor of about **840 release sites** that genuinely relate two
   regions. And the census is drawn from a **biased sample, biased in
   the flattering direction**: because `Vec`, `Map` and `Intern`
   declare their handles `Int`, **595** call-allocated values are
   published into containers and struct fields with *no retain and no
   release at all*. They escape, and they are invisible to this count
   because the ownership events that would have shown them never fire.
   That is `MM-ALLOC-20`'s prerequisite arriving from a third
   direction, and it means S3 lands on a substrate where the containers
   are still outside the model.

3. **Whether the RSS survives S4.** §1.1's ablation deleted the
   releases and lost 2.4× on peak RSS. The design's whole claim is that
   a region reset returns that memory in one pointer move. **Still
   unmeasured** — it is the one probe that needs S4 to exist, and S4's
   gate is exactly this measurement.
4. **The wall-clock question is open**, per §1.1. An idle machine, best
   of N, interleaved arms.

---

## 6. Open questions

- **Where does a region's name live in the type?** `(Str @r)` is
  written above as if regions were an extra parameter list. Whether
  they are a second binder or share the existing type-variable binder
  decides how much of `typecheck.ax` moves.
- **What is `main`'s region?** Naming it `@global` makes today's
  programs the one-region instance (§2.4). Whether it is resettable at
  all is a separate decision.
- **Does `restrict(no-escape)` need a new diagnostic code**, or does it
  join `AX3049`? The restriction rail is closed by design (`AX3052`),
  unlike the AXTAG key namespace, so adding one is a table edit.
- **Cycles promoted out of a region still leak** (§2.6). This design
  neither fixes nor worsens `MM-LIFE-3`, and says so rather than
  leaving a reader to hope.
