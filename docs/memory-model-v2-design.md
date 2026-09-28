# Regions — design and implementation history (non-normative)

This record explains why Axiom has checked lexical regions and a
`parallel` form, with the measurements behind each stage. It defines no
rules. The `MM-RGN-*` contract lives in
[memory-model.md §3.6](memory-model.md#36-checked-lexical-regions),
whose conformance table marks each entry implemented (**H**), planned
(**P**) or withdrawn (**W**). To use regions in a program, read
[Regions](reference.md#regions) in the language reference.

Where things stand: S4 release elision is complete. Typed sibling task
regions and heap-result promotion are still planned. Raw-word lifetimes
and foreign sharing remain programmer obligations; see
[the memory audit](assurance/memory-audit.md).

The first measurements were taken at commit `19cb860` on
darwin-aarch64, and the staging table in §4 dates each later stage.
Present-tense claims in the historical sections describe the snapshot
they report, not an extra current contract.

The starting direction was typed regions over the existing arena, plus
one parallel surface with a process lowering and a thread lowering.
The measurements below sized that work. They don't establish a general
memory-safety or timing guarantee.

---

## 1. The measured starting point

### 1.1 What reference counting costs, measured by removing it

The compiler's own emitted IR is the largest Axiom program there is.

```text
$ /tmp/axc-mm2/axc emit-llvm self_host/main.ax -o selfhost.ll
$ wc -l selfhost.ll ; grep -c '^define' selfhost.ll
  197562 selfhost.ll
    3469
$ grep -c 'call void @axiom_release' selfhost.ll   # 10849
$ grep -c 'call void @axiom_retain'  selfhost.ll   #   679
```

We deleted all 10,849 `axiom_release` call sites from that IR. We then
rebuilt it with the same `llc` and `cc` the arena-rate gate uses
(`llc -filetype=obj -relocation-model=pic`, `cc … -e _main`). The
result isn't a correct program, because it never frees anything. It
computes the same function, though: asked to compile
`self_host/main.ax`, it writes byte-identical output.

| | peak RSS | binary | output |
|---|---|---|---|
| as emitted | **406,032 KiB** | 1,552,840 B | — |
| every release deleted | **954,464 – 973,984 KiB** | 1,404,080 B | byte-identical |

So the counting traffic buys a **2.4× reduction in peak RSS** and costs
**9.6% of the binary**. The RSS figure is deterministic on the
baseline: 406,032 KiB on all five runs, to the kilobyte.

This record claims no wall-clock effect, in either direction. A first
set of three runs put the ablated compiler 9% faster. Re-run on the
same machine under a different load, the two arms overlapped (24.4–27.5
s ablated, 26.4–26.6 s as emitted) and the difference was gone. A
design that needs a timing claim must measure it on an idle machine.
`MM-ALLOC-16a`'s A/B comparison needed the same correction.

### 1.2 The traffic is 16:1 in one direction, and half of it is a no-op

`axiom_release` appears at 10,849 sites and `axiom_retain` at 679, a
ratio of **16:1**. Per function:

| | functions | share |
|---|---|---|
| release sites, and **no retain site at all** | **1,211** | 34.9% |
| both | 390 | 11.2% |
| retain only | 80 | 2.3% |
| neither: no ownership traffic | 1,788 | 51.5% |

The 1,211 release-only functions carry **9,341 of the 10,849
releases**, 86% of the program's release traffic. A count that is only
ever decremented isn't really a reference count. It is a scope,
implemented one object at a time.

Here is every release site, classified by what defines the value it
releases:

| defined by | sites | share |
|---|---|---|
| **a static string literal** (`@strhdr_*`) | **5,762** | **53.1%** |
| the result of a call (callee-allocated, owned) | 4,636 | 42.7% |
| a load: a field or a frame slot | 338 | 3.1% |
| a phi | 110 | 1.0% |
| a parameter (borrowed) | 3 | 0.0% |

Each of the 5,762 is a `@strhdr_*` global: a literal whose count word
is the static sentinel `-1`. `@axiom_release` loads the count, compares
it with `-1`, and returns. **Over half the release traffic in the
compiler is a call that can't free anything**, and the operand's
definition shows that at compile time.

Removing only those 5,762 calls gives byte-identical output and a
binary **5.3%** smaller (1,470,256 B). Peak RSS sits at or slightly
below the baseline (361,856–405,984 KiB), as it must: deleting a call
that frees nothing can't cost memory.

This finding needs no region, no type-system change and no new rule,
just a compile-time test on the operand's definition. It is Stage 0 in
§4.

The three releases on a *parameter* sit at the other end. Under
`MM-LIFE-2c` event 1, a call borrows its arguments and takes no share,
so passing one costs nothing. The table's last row is the probe for
that rule, produced by the same pass over `selfhost.ll` as the other
four rows.

### 1.3 The arena already wins, and two of its three obligations are unchecked

`MM-ALLOC-22` settled the strategy question: the arena scope *is* the
reclamation strategy. The evidence is `scripts/check-net.sh`, where a
request handler bracketed by `__axiom_arena_mark` and
`__axiom_arena_reset` uses **100–313× less peak RSS** than the same
binary unscoped. The language server's per-edit footprint agrees:
**840 bytes bracketed, against 193,247**.

What the arena lacked was a checker. Three program obligations
(`MM-ALLOC-16`, `16a` and `16b`) say what a program must not do, and
nothing reported it when a program did. `16a` had just become an
implementation obligation that traps with status 75
(`tests/stdlib/166-arena-bad-mark.ax`). **`16` and `16b` were still
unchecked**: what may be read after a reset, and that a reset must not
pass an evidence record's extent. Stage S1 in §4 later checked `16b`.

### 1.4 The syntax for scoping memory was deleted on a promise that was then withdrawn

`region` had been a keyword. When this work began, the compiler refused
it:

```scheme refused
(region r)
(:: main Int)
(fn (main) 0)
```

The refusal read:

```text
error[AX2004]: `region` is no longer part of Axiom
  = `region` was removed: allocation lifetime is inferred from where a
    value is created and how far it escapes, not written by hand
  = help: delete the `region` wrapper and keep its body; values are
    dropped deterministically at the end of the arena they belong to
```

Both sentences described a model that didn't exist. The inference they
name is that of
[memory-model.md §3.4](memory-model.md#34-the-inferred-arena-model--withdrawn),
and every rule there is **W**:

- `MM-ALLOC-17`, the implicit per-activation arena. Its own status line
  says nothing is reclaimed at return.
- `MM-ALLOC-18`, escape promotion. It described itself as Tofte–Talpin
  region inference with the annotations removed, "which is why `region`
  was deleted from the surface syntax".
- `MM-ALLOC-19`, the tail-call reset.

§3.4's own verdict is the correction: what replaced the inferred arena
is one that a program brackets, not one the compiler infers.

So the language deleted the annotation because it would be derived,
then withdrew the derivation. The diagnostic still told everyone who
wrote `region` that the compiler did the work. Nobody had re-opened the
question, so this record did.

The answer is stage S2 in §4: `region` is a keyword again. The false
advice is gone from the parser, from `axiom explain AX2004`, from the
README and from the language reference. One more measurement belongs
beside the refusal above: it fired only at the top level. In expression
position, where a region belongs, `(region r 0)` drew
`AX3001 undefined variable region` and a second `AX3001` for `r`. A
reader who wrote a region where it made sense was never told about the
removal at all.

---

## 2. Design decisions and dispositions

These are historical decisions. The linked specification owns their
current wording, evidence and status. The original proposal text is in
this file's version history.

### 2.1 The runtime already existed

`MM-RGN-1` used the existing arena position and reset operation for a
lexical scope. S2 implemented a stack mark cell and a scalar-result
restriction. It didn't implement automatic promotion of a heap result.

### 2.2 Lexical outlives order

`MM-RGN-2` chose a lexical tree order. The implementation also treats
distinct signature region names as unordered, each one outliving the
caller's current allocation region. It doesn't build sibling region
nodes for `parallel` bindings.

### 2.3 The escape rule

`MM-RGN-3` became the checked-origin rule for stores, returns and
captures. The original claim that it would subsume every raw-reset,
live-evidence and invisible-store obligation was too broad. Erased
addresses keep their programmer obligations, and the dynamic mark and
evidence guards remain. The canonical rule states the domain it covers.

### 2.4 Annotations and the common case

`MM-RGN-4` originally proposed that every reference parameter and
result share the caller's region. S3 reads callee facts instead, which
allows a read-only use of an outer value while refusing an escaping
store. This replaces the invariance proposal without adding runtime
arguments. The comparison of annotated and stripped programs remains a
gate.

### 2.5 The witness changed during implementation

The original `MM-RGN-5` proposed a hidden trailing mark-cell word per
region parameter. We declined that proposal, and the specification
marks it withdrawn. Receiving an outer mark can't make the bump
allocator place a new value below an inner waterline.

`MM-RGN-5a` records what shipped instead: freshness stamps computed
after the fixpoint and consumed at release sites, with no runtime
witness word. The S4 entries below keep the measurements and the
path-specific ablations.

### 2.6 Reclamation and counting

`MM-RGN-6` keeps counting except where a particular release is proved
redundant. The original claim, that counting survives *only* for values
that outlive their region, wasn't implemented as a general rule. Nor
is a reset's total work a single pointer move: it also clears
size-class heads and processes surplus chunks. The canonical contract
states the composition once, including the destructor and shallow-copy
limits.

### 2.7 What is taken from Ada, precisely

- **Accessibility levels.** Ada refuses an access value that would
  outlive the scope of the object it designates. `MM-RGN-3` is that
  rule, with regions as the levels. Ada checks statically where it can
  and dynamically where it must. Axiom has the dynamic half too: the
  status-75 trap of `MM-ALLOC-16a` covers cases the static rule can't
  reach.
- **Storage pools.** Ada lets a type name the pool it allocates from. A
  region parameter is that idea, made a type parameter.
- **`pragma Restrictions`.** Axiom already has and checks this:
  `restrict(no-io, no-alloc, …)`, `AX3049` and
  `scripts/check-restrictions.sh`. Regions add `restrict(no-escape)`, a
  declaration that allocates only in its own region. It uses the same
  mechanism and is checked by the same walk.

Not taken: Ada's **controlled types and finalization**. Axiom has no
destructors, and `ERR-REC-1` depends on that: nothing runs on the way
out. A region reset runs no user code, and we want to keep it that way.

---

## 3. Concurrency — one surface, two lowerings

### 3.1 The thread lowering is one primitive and one function body away

`cgThreads` (`self_host/codegen.ax`) is the one predicate that decides
whether the emitted runtime's mutable globals are thread-local. When
this work began it answered `false` for every program. Its comment
named what was missing: the body, a scan of the resolved declarations
for `__thread_spawn`. That primitive didn't exist yet, so neither did
the scan.

Everything downstream was already built:

- `cgMutGlobal` is consulted at all eight sites: the five allocator
  words, the slab array, `@__axiom_recover_top`, and one evidence slot
  per declared effect.
- The storage class is `internal thread_local(localexec) global`.
  Local-exec is required, not just preferred. The general-dynamic model
  imports `__tls_get_addr`, and `scripts/check-freestanding.sh`
  requires zero undefined symbols.
- `scripts/check-thread-local.sh` measured the thread-local path by
  ablating the body of `cgThreads`. No program could select that
  storage class, so no ordinary gate could reach it.

The default path matters more. On Darwin, a thread-local access is an
indirect call through libSystem's `__tlv_bootstrap`, and `axiom_alloc`
touches four of these globals on its fast path. Making every program
pay for threads would take the whole tree out of `MM-FFI-1`'s tier 1.
It doesn't: a program that spawns no thread is byte-identical on every
target.

### 3.2 Region-per-thread makes `Send` structural

`MM-PAR-6` commits the specification to "one arena per thread with no
cross-thread reference, values handed to a thread copied or moved,
results moved into the parent's arena at join, and combination in
argument order."

The design argued that, with typed regions, "no cross-thread reference"
is just `MM-RGN-3` applied to sibling regions. A thread's region isn't
nested inside another thread's, so by `MM-RGN-2` neither outlives the
other. The rule that already serves single-threaded code would then
refuse every cross-thread reference.

That would mean no `Send`, no `Sync` and no auto-trait. Thread safety
would follow from the memory model instead of being a second system
layered on it. That payoff is why this record treats regions and the
parallel surface as one decision. The sibling-region typing didn't ship
with S3; §3.2b explains what did.

<a id="32b-the-sibling-region-rule-did-not-ship-and---threads-is-unsound-without-it"></a>
### 3.2b The sibling-region rule did not ship, and what keeps `--threads` sound instead

`self_host/codegen.ax` cited §3.2's sibling-region typing as work S3
would deliver. S3 delivered region-annotated signatures and
the escape rule (`AX3060`, `AX3061`, `AX3062`), and none of this. We
checked three findings:

1. `rgnCheckAll` returns at once unless `rgnProgramUsesRegions` answers
   1, and it answers 1 only for a signature carrying an `@r`. A
   `parallel` program with no region annotation runs the region pass
   zero times.
2. The sibling regions were never created. `mkParallel` binds the
   region name `p` with an ordinary `let` to `__axiom_arena_mark`, a
   machine word. There is no region node, so there are no siblings to
   leave unordered.
3. A program capturing a heap `String` into two concurrent bindings
   compiled with no diagnostic and ran under `--threads`.

The consequence is corruption, not a leak. `axiom_retain` and
`axiom_release` are a plain load-add-store, not an `atomicrmw`. Two
threads touching one block's count can lose an increment, and the block
is then freed while a live reference still names it.

At that point, processes were the default lowering and safe by
construction (`MM-PAR-3`). `--threads` was opt-in and carried a capture
discipline that the compiler didn't enforce.
`tests/stdlib/470-parallel.ax` captured only words because that was
the discipline, not because anything checked it. `AX4006` refuses
`--threads` where there is no thread runtime, which is a separate
question.

#### The fix, as scoped

The fix is a checker rule at the `__par_spawn` or `__thread_spawn`
application, not a codegen one. Codegen has `fldClass`, but it has no
capture types before emission and no way to report a diagnostic. At
`parScan` time the type table is still empty. So `fldClass` would
answer "not a reference" for every `struct` and every `data`, and the
check would pass on exactly the types that matter.

The checker has all the pieces:

- `parallel` is desugared in the parser, so the checker sees a plain
  application with a lambda argument.
- Scope entries carry types (`sEntTy`), and the lambda boundary is
  `tc` slot 22.
- `checkSet` already uses `scopeFindIdx` against that boundary.

The rule is unconditional, not dependent on `--threads`. Otherwise the
diagnostic would appear and disappear with a codegen flag, which
nothing else in the AX3xxx band does.

#### What shipped

`checkSpawnCaptures` (`self_host/typecheck.ax`) scans a literal-lambda
thunk and refuses a captured reference with `AX3064`. Two further
changes closed the ways around it.

The indirection half: a thunk that is a frame-local name of arrow type
is refused. A spawn through a one-line wrapper (`viaHop` in the
fixture) draws `AX3064` at the wrapper's parameter `f`. A bare
top-level name stays silent. A local that isn't an arrow is left to
the argument checker, so one mistake draws one diagnostic.
`tests/diagnostics/643-parallel-capture-hop.ax` pins the refused shape
and both controls.

The opaque-thunk half: a thunk that is neither a lambda nor a bare name
is walked structurally (`capWalkThunk`). A conditional, a `match`, a
`let` and a brace block are transparent. Every lambda they can answer
is scanned where it stands, and whatever they read to choose or build
it is collected as a capture. A call result and a field are refused at
the shape (`emitSpawnOpaque`), because no walk can see their captures.
`tests/diagnostics/644-parallel-thunk-shape.ax` pins the four refused
shapes and three controls: a word-only conditional, a word-only match,
and the `__proc_spawn` exemption.

This doesn't build the sibling-region typing that §3.2 describes. No
region nodes are created for bindings, and `rgnCheckAll` still runs
only under `@r` signatures. The safety property that typing was meant
to provide, that no unrefused capture reaches a thread, holds by
refusal instead. Every shape the checker can see is either scanned or
refused. Typed precision, accepting captures that a region discipline
proves safe, waits for S4 with everything else.

### 3.3 The surface, and the two lowerings

The original `MM-RGN-7` proposal put each binding in a typed sibling
region and promoted its result into the parent at join. That remains
**P** in [the specification](memory-model.md#36-checked-lexical-regions).

S5 and S6 built the surface, the two lowerings, joins in written order,
and word transport. Neither a word crossing a join nor the capture
refusals amount to recursive typed heap promotion.

The surface is `MM-RGN-7`'s, with `p` bound to the enclosing region's
arena mark, a machine word. `--threads` selects the thread lowering;
processes are the default. Two things the proposal promised turned out
narrower than they read:

- "Results are moved into `p` at join" holds for a *word*. The thunk
  is `(-> Int Int)`, so a binding whose expression is a `String` is
  refused at that expression (`AX3004`). Under processes the answer
  crosses an address space through one page. Under threads it would
  need the typed promotion of §2.6, which belongs to S3 and S4.
- The proposal made `MM-RGN-3` a static check that thread safety rests
  on. When S5 and S6 were built, that check didn't exist: a binding
  could capture any heap value in scope, and under threads that value's
  count was touched from two threads with no fence. The process
  lowering has no such hazard, which is why it is the default. §3.2b
  records how capture refusal later closed this for threads.

`scripts/check-parallel.sh` covers the rest; S6 in §4 lists what it
checks.

---

## 4. Staging

Each stage is valuable and gated on its own, and no later stage is a
prerequisite for an earlier one's win. Every gate follows the
repository's convention of ablation before fix: it shows the check
fails without the change.

| Stage | Status | What it does | Gate |
|---|---|---|---|
| S0 | Done 2026-08-31 | Stops emitting the 5,762 no-op releases on static literals (§1.2) | `scripts/check-static-release.sh` |
| S1 | Done 2026-08-31 | Traps a reset that would reclaim a live `handle`'s evidence record (`MM-ALLOC-16b`) | `tests/stdlib/167-arena-live-handle.ax` |
| S2 | Done 2026-09-03 | Brings `region` back as a checked scope, with no region types yet | `scripts/check-region-scope.sh` |
| S3 | Built 2026-09-03, except the witness | Region-parameterised signatures, `MM-RGN-3` checked, `restrict(no-escape)`, the §5 sweep as a gate | `scripts/check-region-escape.sh` |
| S4 | Verdict run 2026-09-26 | Deletes ownership traffic the region proves dead | `scripts/check-region-verdict.sh` |
| S5 | Done 2026-09-03 | Adds `__thread_spawn` and `__thread_join`, and the body of `cgThreads` | `scripts/check-thread-local.sh` |
| S6 | Done 2026-09-03, with the limit stated | Adds `parallel`, with both lowerings | `scripts/check-parallel.sh` |

**S0: no-op releases on static literals.** The cost is one
compile-time test on the operand's definition, with no rule and no type
change. The 5,762 static releases became 5, and total release sites
fell from 10,849 to 5,117. The compiler binary shrank by 5.6%, and its
emitted output is byte-identical. The gate ablates
`isStaticSentinelNode`'s answer, rebuilds, and requires the count to
return to the thousands. It also checks that a join over a literal
still gives its share back, which is the trap the obvious one-line fix
falls into.

**S1: `MM-ALLOC-16b` checked.** Like `16a`, it now traps. The cost is
one gated call in `resetbody`, one on the unwind walk, and
`@__axiom_ev_check` over the effect slots.
`tests/stdlib/167-arena-live-handle.ax` exits **76**. Before S1, the
operation ran on reclaimed memory and the program exited 0. The two
legal shapes beside it stay silent. `tests/stdlib/401-recover-effect.ax`
still exits 71: the recovery path needs no exemption, because it
restores every slot *before* it resets. A program that declares no
effect gets byte-identical IR, `self_host/` included.

**S2: `region` as a checked scope.** It is a mark and reset on a stack
cell, with region names scope-checked (`AX3058`) and `AX2004`'s false
advice deleted. The plan said S2 needed no typechecker change, and that
was wrong. Even without types, the checker has to refuse, as `AX3059`,
the two escape channels a scope can see:

- the region's own value, when it isn't a scalar;
- a `set` on a binding bound outside the region, when the stored value
  isn't a scalar.

Without that, the reset hands the program a dangling descriptor while
every gate passes. The cost is a real node (`TAG_E_REGION`, so S3 can
find extents), the open-region stack, and the value and store rule in
`typecheck.ax`. `emitRegion` is three loads, one hoisted `alloca` and
the existing `@__axiom_arena_reset_fn`.

`scripts/check-region-scope.sh` checks that:

- a program without a region emits no cell;
- for 4,000 × 64 KiB, peak RSS is 185× lower with the region than
  without;
- `tests/diagnostics/631-region-escape.ax` draws exactly its three
  rows;
- the ablation, `rgTyScalar` answering 1, builds a compiler under which
  `hello world` stored out of a region reads back as `XXXXXXXXXXX`, the
  next allocation.

`tests/stdlib/168-region.ax` has ten terms. A program with no region
gets byte-identical IR: compiling `self_host/main.ax` with the previous
commit's compiler and with this one gives 202,021 lines both ways. S2
doesn't cover a reference leaving a region, which needs typed
promotion. Nor does it cover the two channels a scope can't see, a call
that stores and a raw `Int`. Those stay `MM-ALLOC-16`'s obligation.

**S3: region-parameterised signatures.** Signatures take region
annotations, as in `(Str @r)`, and `MM-RGN-3` is checked over every
body. The cost falls on the typechecker (`rgnCheckAll`, a facts
fixpoint over the call graph plus one reporting walk), the parser, the
formatter and the grammar. S3 has no codegen: the witness of §2.5 was
deferred to S4. `scripts/check-region-escape.sh` checks that:

- an annotated program and its stripped twin emit byte-identical IR
  (1,652 lines);
- `tests/diagnostics/645-region-escape-store.ax` through
  `tests/diagnostics/649-restrict-no-escape.ax` cover one escape shape
  each, `AX3060` to `AX3063`;
- the ablation, `rgnCheckAll` answering 0, accepts all four shapes, and
  the program it lets through reads reclaimed memory;
- the sweep reads 241 of 6,206 (3.88%).

**S4: deleting dead ownership traffic.** This is codegen work. The
success criterion is to re-run §1.1's ablation and see the binary win
with the RSS win intact. That one measurement decides whether the work
was worth it. `scripts/check-region-verdict.sh` reports 7,951 literal
releases on `self_host`, per-fixture deltas of 18/23/21/24/21/26/10,
an aggregate binary change of −32 B, RSS at 99–100%, and identical
answers. The S4 verdict, after the slice notes below, gives the full
numbers.

**S5: threads.** S5 adds the primitive pair, the scan (`parScan` in
`codegen.ax`, before `emitAllocator`) and the thread runtime.
`emitParThread` calls the platform's `pthread_create` with an entry
that runs the thunk and writes its word. `scripts/check-thread-local.sh`
now reaches the thread-local path through a program that spawns, with
no ablation:

- eight globals move, and nothing else does;
- the default path imports no TLS symbol;
- a thread costs `pthread_create` plus `pthread_join`, and
  `__tlv_bootstrap` on Darwin;
- both Linux targets use local-exec.

FreeBSD and Windows refuse threads at build time (`AX4006`).

**S6: `parallel`.** The surface is a parser desugaring over
`__par_spawn` and `__par_join`, with no AST tag. `--threads` chooses
between two backends. `emitParProc` forks, maps one `MAP_SHARED` page
per binding, and uses `wait4` to re-raise a child's status.
`emitParThread` uses threads. `scripts/check-parallel.sh` runs
`tests/stdlib/470-parallel.ax` and `tests/stdlib/471-parallel-trap.ax`
under both lowerings, and checks that:

- stdout is byte-identical, and the exit is the same (77 under both for
  the trap);
- processes add no import, and threads add exactly their own two
  symbols (three on Darwin);
- the flag has no effect on a program that spawns nothing;
- Windows emits a status-79 trap in place of both primitives.

The limit: what crosses a join is a word, and at S6 captures were
unchecked under threads. See §3.3, and §3.2b for why S3 didn't close
that and what did.

**S4 slice 1: direct-construction temporaries.**
`isRegionCoveredCon` (`self_host/codegen.ax`) answers whether a release
operand is a fully applied construction that the emitter is building
right here. `releaseOwnedArgs` then skips emitting its release, while
`argOwnedRelease` still says 1, so `mustTailOK` stays conservative. A
region-depth count (pair slot 9) bounds the textual extent.
`emitLamDef` clears it, because a lambda may run after the reset.

`tests/stdlib/479-region-reclaim.ax` (eight terms) and
`scripts/check-region-reclaim.sh` show that:

- six releases are gone from the fixture's IR, and the diff is those
  six lines and nothing else;
- both compilers give the same eight answers;
- peak RSS is 98% across 300,000 regions;
- an ablation answering 0 brings all six back.

Slice 1 leaves out three things, each for a reason:

- **Call results.** A callee may alias an outer value, so freshness
  needs the `MM-RGN-5` witness. That is slice 2.
- **`VAR` operands and field stores.** The first needs def-tracking.
  The second balances a retain in the same step.
- **A constructor-registry hit on its own.** A hit alone doesn't decide,
  so the head check follows `dispatchCall`'s order: locals shadow,
  effect operations dispatch, and the cast path aliases. A `let`-bound lambda named `MkBox` turns
  `(MkBox 1)` into a closure call, which leaked without this guard.
  Constructors can also be named `cast`, and a probe confirms it.

### Sizing S4's next slice

We classified every `axiom_release` site in the compiler's own IR
(`emit-llvm self_host/main.ax`, 387,162 lines) by what defines its
operand. The walk is the same per-`define` walk that
`check-static-release.sh` uses. There are 6,501 sites:

| Operand defined by | Sites |
|---|---|
| a call result | 5,916 |
| a `load`ed local | 408 |
| a `phi` join | 157 |
| an `extractvalue` projection | 13 |
| a static literal | 7 |

So the witness can reach at most 5,916 sites. `VAR` operands need
def-tracking and joins need per-arm reasoning, and each is its own
later slice.

The top callees show why the witness must be computed rather than
syntactic. `strConcat` (1,203), `strDup`, `strSlice` and `fmtInt`
construct their result. `memGetWordStr`,
`vecGetStr`, `tokenLexeme`, `bareOf`, `nodeAName`, `fpSrc` and `sysArg`
read into memory the callee didn't build. A witness that called every
call result fresh would say so for the readers too. Telling the two
groups apart per callee, by reading callees as `rgnRounds` does, is
`MM-RGN-5`'s job, and this census is its worksheet.

### The fixpoint runs only where a region asks for it

Forcing the fixpoint on every build costs about 14 s, so the trigger
stays and grows. On the compiler itself (`symbols self_host/main.ax`,
4,614 rows), `symbols` takes 3.98 s without `--mir` and 18.11 s with
it. The difference, about 14.1 s, is the fixpoint plus projection, and
bootstrap would pay it three times over. The real tree converges: no
row is `#mir-truncated`, and 1,656 carry `#mir-result-fresh`.

The trigger can stay cheap. `self_host` holds no real region form: its
seven textual hits are the printer's spelling, an error message and
comments. `stdlib` holds one, in `Http.ax`. So "a region form is
present" keeps the compiler's own build and every region-free program
at zero added cost, as long as the test is O(1) rather than a body scan
on every check.

That is slice 2b's shape: one bit, ORed with the `@r` test.

### Slice 2b: the trigger

`checkRegion` sets TC word 39 (`rgnHasForm`) during the S2 walk, which
already visits every region form once. `rgnCheckAll` reads the bit in
O(1), with no extra body scan. The checker sets it rather than the
parser, because the parser has no TC to set, and changing
`parseModuleWith`'s `PResult` shape would touch every caller.

The bit is ORed with the `@r` test:

- `@r` present: ensure facts and run the reporting pass.
- A region form with no `@r`: ensure facts for the witness. Slice 2b
  ran no reporting pass here, because it would double-report every S2
  shape (`AX3059` with `AX3060` on 631). The reporting pass now runs
  here too, with the double suppressed; see
  [the callee-mediated hole](#the-callee-mediated-hole-is-closed)
  below.
- Neither: 0.

A truncated fixpoint still means the witness abstains.
`rgnEnsureFacts` records truncation on words 28 and 33, and the elision
keeps every release.

Against a baseline built the same way, `emit-llvm self_host/main.ax` is
byte-identical (389,450 lines both ways) and takes 2.6 s against 2.6 s.
631 still draws only its three `AX3059`s, and 479 checks OK.

### S4 slice 2: fresh call results passed to a call

The witness is a stamp, not a query. The region pass records a
proven-fresh call result on its own node (`nodeResWord` 0 to 2). It
stamps only after the fixpoint, never while facts are still moving, and
never when truncation made every row a lower bound. TC word 40
(`rgnStamping`) tells the stamp walks apart from the fixpoint's own
passes.

The abstention is global. A truncated fixpoint stamps nothing anywhere
and keeps every release. That is the safe direction: a missed elision,
never an early free.

`releaseOwnedArgs` spends the stamp exactly where slice 1 spends its
construction test. `argOwnedRelease` still says 1, so `mustTailOK`
stays conservative.

A call result is fresh when the callee's facts say the answer derives
from CUR0, from no heap parameter, and from no call the walk couldn't
resolve:

- A scalar-typed parameter contributes no alias, so a cell built over
  words is still fresh. `mkBox` over `Int` is stamped, and `idBox` over
  `Box` isn't.
- A callee that takes a heap parameter without letting it reach the
  result is stamped too. `wrapBox` over `Box` and `Int` answers a cell
  built over the word alone. Term 9 pins that elision, so a walker that
  abstained on any heap parameter would fail the gate.
- The call must be saturated. An annotated result is never stamped, and
  a word answer is never touched, because every older reader asks
  `== 1`.

Constructors aren't stamped. Slice 1 owns them syntactically, so the
two deltas never overlap. The code is inlined rather than factored, so
no new top-level function moves the effect-distribution pins.

The evidence is `tests/stdlib/480-region-fresh-call.ax` (nine terms)
and `scripts/check-region-fresh.sh`. Seven releases leave the fixture's
IR, and the diff is those seven lines and nothing else. Both compilers
give the same nine answers, and peak RSS is 100% across 300,000 regions
of fresh calls. Ablating the args-path spend brings all seven back.

This path doesn't cover a fresh call result bound by `let` and released
at scope end, because `releaseOwnedArgs` never sees it. Term 4 pins
one. The scope-end walker below elides it under both compilers in this
gate's comparison, so it doesn't show in the delta.

### S4 slice 2: the same stamp at `let` scope end

A result bound by `let` never reaches `releaseOwnedArgs`.
`valueOwnedRef` answers 0 for a local, so the argument position stays
silent and `MM-LIFE-2c` event 3 pays the share at the binding's scope
end instead.

`emitLetAt` spends the stamp there, with the same witness and the same
depth gate. The `releasable` decision is untouched, and only its
spending is conditional. The pending vector still takes the share for
the tail-jump path, which keeps its release. `emitLetMAt` needs
nothing: a mutable binding keeps its alloca and has no scope-end
release to spend.

The evidence is `tests/stdlib/481-region-fresh-let.ax` (eight terms)
and `scripts/check-region-fresh-let.sh`. Every fresh call in the
fixture is a `let` initialiser and every consuming argument is a bare
name, so the args path has nothing to spend. Eight releases go, and the
diff is those eight lines and nothing else. Both compilers give the
same eight answers, and peak RSS is 100% across 300,000 regions of
bound fresh calls. Ablating the scope-end spend brings all eight back.

Both slice 2 ablations are path-specific. Ablating the shared stamp
would restore traffic the walker under test never owned.

### S4 slice 3: joins whose every arm is fresh, passed to a call

A join answers whichever arm it took, so freshness needs per-arm
reasoning rather than a callee fact. The region pass stamps the join
itself (`nodeResWord` 2) if and only if every arm's value node already
carries the stamp. That means a proven-fresh call result, or such a
join: the inner join is stamped before the outer reads it, in the same
post-fixpoint walk.

Anything else in an arm makes the join abstain:

- a reader arm;
- an arm through a call the walk can't resolve;
- a construction arm, which is slice 1's syntactic domain and never
  stamped, so the stamp keeps its one meaning;
- a bare name;
- a missing `else`, which isn't a stamped arm.

The guards are the call stamp's: post-fixpoint walks only under TC
word 40, converged facts only, and an upgrade from 0 to 2.
`releaseOwnedArgs` spends the stamp where slices 1 and 2 spend theirs.
`argOwnedRelease` still says 1, so `mustTailOK` stays conservative.

The stamp is threaded through the existing arm walkers, `rgnArms` and
`rgnCondClauses`. The `else` still walks last inside the cond walker,
so no side-effect order and no diagnostic moves. The code is inlined at
`if` and at both spend sites, so no new top-level function moves the
effect-distribution pins.

The evidence is `tests/stdlib/482-region-phi-call.ax` (eleven terms)
and `scripts/check-region-phi.sh`. Seven releases leave the fixture's
IR, and the diff is those seven lines and nothing else. Both compilers
give the same eleven answers, and peak RSS is 99% across 300,000
regions of fresh joins. Ablating the args-path join spend brings all
seven back.

A fresh join bound by `let` belongs to the scope-end path, because
`releaseOwnedArgs` never sees it. Term 5 pins one. The scope-end walker below elides it under both compilers in this
gate's comparison, so it doesn't show in the delta.

### S4 slice 3: the same stamp at `let` scope end

A join bound by `let` never reaches `releaseOwnedArgs`, for the same
reason as in slice 2, so `MM-LIFE-2c` event 3 pays the share at scope
end. `emitLetAt` spends the join's stamp there exactly as slice 2
does, with the tail-jump path keeping its release. `emitLetMAt` again
needs nothing.

The evidence is `tests/stdlib/483-region-phi-let.ax` (eight terms) and
`scripts/check-region-phi-let.sh`. Every join in the fixture is a
`let` initialiser and every consuming argument is a bare name, so the
args path has nothing to spend. Eight releases go, and the diff is
those eight lines and nothing else. Both compilers give the same eight
answers, and peak RSS is 100% across 300,000 regions of bound fresh
joins. Ablating the scope-end join spend brings all eight back.

Both slice 3 ablations are path-specific, for the same reason as slice
2's.

### The load census behind slice 4

Classified as in the sizing above, the compiler's own IR has 404
release sites on frame-slot loads and 6 on heap-field loads.

Of the 404, all but one sit on a function's return path. These are
tail-loop parameter slots, the counterpart of the entry retain
(`releaseRefParamSlots`), in callee-shared code that no call site may
elide. The rest, frame and heap alike, are the old values of `set`:
retain-new/release-old pairs whose provenance is unknown. Slice 3
already spends the match-result scratch loads, and its elided operands
on the fixtures include `load` definers.

A field read is a borrow at every site. Passed to a call, bound by
`let`, matched on, or taken as a join arm, it answers unowned
(`valueOwnedRef` 0), so there is no release site to spend on. It was
probed in all four positions and kept everywhere. That is why slice 4
is one spend site and a page of measured negatives.

### S4 slice 4: match scrutinee temporaries

A `match` consumes its scrutinee. It releases the scrutinee after the
merge when `scrutineeReleasable` says no arm binder escapes through its
body (binders are the block's fields).

Slice 4 adds no stamp. The spend in `releaseScrutinee` reads the
`nodeResWord` 2 stamp from slices 2 and 3, under the same depth gate.
That covers a fresh call or a fresh join, including a nested match
whose result register is a scratch-cell load. That is the one "match
temp" shape that counts as a `load` in the census. `releaseScrutinee`
is shared by the tail and non-tail emitters. The pending vector still
takes the share for the tail-jump path. `argOwnedRelease` isn't asked,
so `mustTailOK` can't drift.

The evidence is `tests/stdlib/484-region-scrutinee.ax` (twelve terms)
and `scripts/check-region-scrutinee.sh`. Eight releases leave the
fixture's IR, and the diff is those eight lines and nothing else. Both
compilers give the same twelve answers, and peak RSS is 99% across
300,000 regions of fresh scrutinees. Ablating the scrutinee spend
brings all eight back.

### S4's counted remainder

The stamp spends leave a counted remainder in S4:

- pair-error projections, `extractvalue` of an errno out of a two-word
  pair (13 sites in the compiler's own IR);
- scope-end releases of string literals, which are runtime no-ops
  through the `-1` sentinel (7 sites).

Slice 5 and the pair-error trace below settle both. The call and join
traffic the witness keeps (readers, escapes and unknown callees) is
correct to keep.

Field stores are excluded for good. A field store's release balances a
retain in the same step: `emitSetF` retains the value into the field
beside releasing the temporary. The field slot outlives any region the
walk can prove, so no reset covers both halves, and eliding one half
would leak.

### S4 slice 5: string literals at scope end and in tail temporaries

Slice 5 settles the string-literal half of the counted remainder.
`isStaticSentinelNode` is asked at all four sites that emit a release
for a value that is the literal:

- `emitLetAt` skips the scope-end release when the initialiser is a
  bare `TAG_E_STR`. The binding is immutable, so SSA still holds the
  literal there.
- `releaseTailTemps` skips an argument temporary that is a literal,
  such as the `""` a tail loop threads through. Two of these appear in
  `codegen$scanLineMarks`.

It has the same shape as the stamp spends: `releasable` still says 1,
and the pending vector still takes the share for the tail-jump path.
So the shared predicate's ablation restores all of these along with the
other sites.

On the compiler's own IR, static-literal release operands go from 7 to
0. Every other bucket is unchanged: 6,380 call, 451 load, 168 phi and
13 extractvalue.

`scripts/check-static-release.sh` covers the new sites. Its fixture
binds and tail-passes literals, and ablated it shows 5 static releases,
so all four positions are live. The corpus cap is 0, and the join guard
still requires the join's own share back.

### The pair-error remainder is required

All 13 sites are `Err` arms over `$pair` calls whose slot 1 holds
`call i64 @Err$mkError(...)`. That is a fresh heap `Error`, traced
through `sysResult$pair` in the compiler's own IR. Each release frees
the block its own failed call built, so eliding any of them leaks one
`Error` per failure.

The bucket stays at 13 by construction and grows legitimately with new
syscall wrappers. So no gate checks the count: a static count here
would churn without guarding anything. S4's counted remainder is empty.

### The S4 verdict

`scripts/check-region-verdict.sh` is the criterion in S4's table row.
It runs three workloads against one fully ablated compiler, with slice
1's depth guard, the stamp and the static-sentinel answer all disabled
at once.

- **W1** is §1.1's workload. Both compilers emit `self_host/main.ax`,
  and 7,951 releases come back, every one on a `@strhdr_*` literal
  (4,293 headers). So where no region form stands, the region elisions
  are provably inert. The emitting compiler's peak RSS is 692,672 KiB
  against 694,160 KiB ablated (99%).
- **W2** runs the six S4 fixtures plus a literal probe. Per-file
  release deltas are 18/23/21/24/21/26/10, against slice floors of
  6/7/8/7/8/8/4. Every file's answers are identical both ways and no
  binary grows. The seven files' aggregate was 251,248 bytes against
  251,280 ablated; the amendment below measures the code instead.
- **W3** loops 300,000 regions of combined construction, call and
  literal traffic. It prints the same 90001800000 both ways, at 100%
  peak RSS.

The verdict makes no wall-clock claim, per §1.1's own correction.

Counted against both IRs, each fixture's delta breaks down by operand
definer:

| Fixture | Slice floor | Other released operands |
|---|---|---|
| 479 | 6 constructions | 12 literals |
| 480 | 7 calls | 13 literals, 2 constructions, 1 call |
| 481 | 8 calls | 12 literals, 1 construction |
| 482 | 6 joins + 1 scratch load | 15 literals, 1 construction, 1 load |
| 483 | 6 joins + 2 scratch loads | 12 literals, 1 construction |
| 484 | 4 calls + 4 joins | 16 literals, 1 construction, 1 load |
| probe | 4 guarded literals | 6 println-machinery literals |

Most of the cross-traffic is literals: the strings every fixture
prints.

The verdict caught two mechanisms instead of assuming them:

- Restored releases flip `musttail` decisions downstream. The W1
  comparison normalises registers and cancels alignment drift. It
  allows only the flip vocabulary, plus the `@__axiom_line*` and
  `filen` tables, which scale with the release count.
- Function alignment absorbs a few removed calls into padding. Three
  fixtures tie to the byte, which is why the strict win is pinned on
  the aggregate.

S4 is closed. The traffic the region proves dead is gone, the binary
is smaller for it, and nothing that freed anything went with it.

### Amendment: the win is measured in code, not file bytes

On darwin at `99bd5415`, the gate failed on 483 and 484. Their files
were 8 and 16 bytes larger under test, while their `__text` sections
were 288 bytes smaller each. The file carries linker tables that don't
track the code. `LC_FUNCTION_STARTS`, an unsigned LEB128 list of
function-start deltas padded to 8, went from 64 to 72 bytes. The code
signature follows the file's own length.

The gate now reads the text section (`llvm-size -A`, `__text` or
`.text`) for both the per-file must-not-grow rule and the aggregate's
strict win. It prints file bytes without asserting them.

On darwin-aarch64, every fixture's code shrinks, by 224–296 bytes
each. The seven files' aggregate is 57,884 bytes against 59,764
ablated. The 32-byte file-level figure above understated the win by two
orders of magnitude.

### The callee-mediated hole is closed

Consider a callee that stores a fresh construction into an outer cell,
called from inside an un-annotated region. That shape checked OK and
read back wrong: it stored 1 and read 0 after reuse, with every gate
green.

S3's reporting walk now runs for region-form programs too. The facts
were already computed for the witness; only the diagnostics were
gated. The walk refuses the call with a precise `AX3060` naming the
parameter and the store path
(`tests/diagnostics/653-region-escape-callee.ax`).

S2 records its refused store spans on TC word 41, and the reporting
walk skips those spans, so each shape still draws exactly one
diagnostic. 631 keeps its three `AX3059`s and the escaping shape draws
one `AX3060`. The escape probes in the six S4 gates, written for the
day both compilers refuse, take the refusal arm.

The elision still gives the same outcome there, because the reset frees
unconditionally. S3's "over every body" now holds, including the
bodies no signature annotates.

### Why not run `rgnCheckAll` everywhere

Forcing the trigger on everywhere is a one-line change. It refuses the
escaping shape with a precise `AX3060`. It is silent across
`self_host`, `stdlib` and 558 test files, except
`tests/diagnostics/631-region-escape.ax`. There it adds two `AX3060`s
on top of the two `AX3059`s S2 already draws on the same stores. The
S3 walk covers the textual shapes S2 owns, so a universal trigger
double-reports every one of them.

There were two ways out:

- Retire `AX3059` into the walk. That retires a diagnostic code,
  re-derives the S2 gate's counts, and pays the fixpoint on every
  program.
- Suppress one finding where the other fires.

We took the second, in its smallest form. It isn't span coordination
between two walk architectures. S2 records the spans it refused, and S3
skips them: one vector on the TC record both passes already share,
matched by exact span. Each shape keeps its own diagnostic. No code is
retired, no S2 count is re-derived, and the fixpoint still runs only
where a region form or `@r` asks for it.

### S3 as built

Every signature may name regions, as in `(Vec String @r)`. The rule of
§2.3 is checked after the type checker has run, over every body in the
program. It covers a store (`set`, a field write, `__store64`, or a
store a callee makes through its parameter), a return, and a capture.

What makes this tractable is that an un-annotated callee is read, not
assumed. `rgnRounds` computes, per function, which parameters the body
stores a fresh value into and which parameters flow into which. It is
a monotone fixpoint over the call graph, exactly as `inferEffects` is.
So `(vecPush v x)` is refused across regions and accepted within one,
with no annotation on `vecPush`.

§2.4's "region-monomorphic in the caller's current region" is that rule
made precise by reading the callee. Stated as invariance, it would
refuse `(strLen s)` on an outer string.

The same facts answer `restrict(no-escape)` (§2.7). A claim is refuted
by name, through the callee the store went through. Over a call the
walk can't resolve, it is unverifiable. Both ride the
`AX3049`/`AX3051`/`AX3057` rail.

S3 doesn't do three things, each measured rather than assumed:

- **Nothing allocates into a named region.** A value the body makes
  lives in the caller's current region (§2.4), and no named region is
  inside that. So storing it into a `@r` place, or answering it as
  `(T @r)`, is refused. That includes `vecPush` on a `@r` vector,
  because growing it allocates
  (`tests/diagnostics/645-region-escape-store.ax`, row 3). That reading
  holds until S4 hands a callee a region to allocate in, which is what
  the witness is for.
- **The witness of §2.5 isn't plumbed.** Its value is a region's mark
  cell, which S2's lowering defines, and its only reader is S4's
  allocation. A hidden trailing word on a region-polymorphic function
  would change the IR of exactly the programs this stage can otherwise
  prove inert. That would break the byte-identity of
  `check-region-escape.sh` section 1, for no consumer. The witness
  lands with its first reader.
- **A value promoted out of a `(region r ...)` form is treated as the
  enclosing region's, shallowly.** The walk has the arm for S2's node,
  written against its contract. Can `reset_keeping` carry a value
  whose fields point into the region? `MM-ALLOC-15` carries one
  contiguous block. That is S2's lowering question, and this stage
  doesn't answer it.

Two readings are conservative. Each gives a false refusal rather than a
missed escape:

- A call the compiler can't resolve, through a parameter, a closure or
  a field, is assumed to store every argument into every argument.
- A `match` binder takes the scrutinee's origins. So an element
  unwrapped from a freshly built `Some` carries the wrapper's region as
  well as the payload's. That is why
  `tests/stdlib/468-region-signatures.ax` writes `left` over a `@r`
  value.

### `MM-ALLOC-16` is not in S1

The first draft of the staging table put it there, and that was wrong.
The row read "`MM-ALLOC-16`/`16b` become checked, as `16a` did — one
branch each". `MM-ALLOC-16`'s own text refuses the premise: *"These
three carry a contract the compiler **cannot** check: after a reset,
nothing allocated since the matching mark may be read again."*

Deciding whether a value is read after its arena reset is a dataflow
question about where values came from. That is `MM-RGN-3`, which is
S3, not a branch in a runtime helper. `16b` is different. It names a
fault whose two operands, the evidence record's address and the
reset's waterline, are both concrete at run time. That is why `16b`
stays in S1 and its sibling doesn't.

We record the error instead of quietly correcting it, because this
document catalogues the same error elsewhere: §1.4's `region` removal,
and the three withdrawn proposals of
[`memory-model-v2-proposal.md`](memory-model-v2-proposal.md). Each was
a cost estimated from a sentence nobody re-read. This one was caught
before anything was built, by reading the rule the row cited.

### S0 and S2 pay off either way

S0 and S2 are worth doing whether or not the rest is ever built. S0 is
a measured 5.3% of the binary for a compile-time test. S2 stops a
diagnostic advertising a model that was withdrawn.

---

## 5. What would falsify this

Each claim is stated as a probe, because §1.1 holds a number that
didn't survive being measured twice.

These probes size S3; they no longer decide whether it is built. Probe
1 sets how much annotation the design costs a reader. Probe 2 sets how
much traffic it can actually delete. Probe 3 is S4's own gate. A bad
answer to probe 2 doesn't cancel the work, but it narrows what the work
may claim.

1. **The two-region sweep.** Run, and it gives two numbers.

   §2.4 claims the common case needs no annotation. A structural proxy
   looks for a store whose target arrives through one parameter and
   whose value derives from a different one. Over 5,841 `fn`
   declarations in 575 files, it finds **349, 5.98%**. A hand audit of
   a 40-function sample narrows the real figure to **3.5–5.2%**.
   52.8% of declarations can't need an annotation, simply because they
   take fewer than two parameters. `stdlib/` accounts for only 36 of
   the 349: the containers are written once and instantiated
   everywhere, which is the shape the ergonomics claim wants.

   The second number is the risk, and it belongs beside the first.
   Region polymorphism instantiates at the call site, so a caller whose
   arguments share a region writes nothing. But a caller that is itself
   split across two regions must name them, and that propagates.
   Following the relation up the call graph reaches **1,006
   declarations, 17.2% of the corpus and 29.9% of `self_host/`**. They
   include `substTpl`, `expandExpr`, `emitExpr`, `emitDiag` and
   `walkEffects`, the compiler's main spines.

   5.98% and 29.9% are the two ends of the real answer. Where a program
   lands depends on how deep a region split it makes. Today's code
   can't say, because it has no region to split on. §2.4 isn't
   refuted, but it is no longer free, and it shouldn't be quoted
   without this paragraph.

2. **The escape fraction.** Run, and it carries the scaling argument.
   Of the **4,668** releases on call results in the compiler's own IR,
   **69.7% to 80.8%** are on values with no escape channel out of their
   function. Most are string-concatenation intermediates. The claim
   this probe tested, "if most of those values escape, typed regions
   delete very little", is **falsified**: most don't escape. With S0's
   static-literal fix in place, a region model takes the release
   traffic from 10,849 sites to roughly **1,300–1,900**.

   The result doesn't license two things. First, the residue isn't
   noise; it is the design's hard case. `vecPush`, `memSetWord` and
   `mkNodeAt` store a short-lived value into a longer-lived structure.
   That is exactly the shape probe 1 says makes `MM-RGN-4`'s default
   wrong, and it sets a floor of about **840 release sites** that
   genuinely relate two regions.

   Second, the census is **biased in the flattering direction**.
   `Vec`, `Map` and `Intern` declare their handles `Int`, so **595**
   call-allocated values are published into containers and struct
   fields with no retain and no release at all. They escape, and this
   count can't see them, because the ownership events that would show
   them never fire. That is `MM-ALLOC-20`'s prerequisite arriving from
   a third direction. It means S3 lands on a substrate where the
   containers are still outside the model.

3. **Whether the RSS survives S4.** Run, and it does. §1.1's ablation
   deleted the releases and lost 2.4× on peak RSS. Each S4 slice
   carries its own RSS check: 300,000 regions under the test compiler
   against the path-ablated one. Peak RSS is 98–100% in every slice
   gate (`check-region-reclaim.sh`, `check-region-fresh.sh`,
   `check-region-fresh-let.sh`, `check-region-phi.sh`,
   `check-region-phi-let.sh`, `check-region-scrutinee.sh`). The reset
   returns in one pointer move what counting would have freed, per path
   and not just in total.

4. **The wall-clock question.** Run, and there is no difference to
   find. The 300,000-region loop from slice 2's gate was built with the
   test compiler and with the args-path ablation (releases kept). It
   was timed with hyperfine, best of 10, on an Apple M1. One order gave
   404.3 ms against 401.3 ms, and the other gave 397.6 ms against
   402.8 ms. The faster side flips with the order, and both gaps sit
   inside the runs' own ±10 ms spread.

   Deleting 300,000 release calls buys no measurable time either way.
   The win is binary size with the RSS intact, which is what the gates
   above hold.

---

## 6. Open questions

- **Where does a region's name live in the type?** `(Str @r)` is
  written above as if regions were an extra parameter list. Whether
  they are a second binder or share the existing type-variable binder
  decides how much of `typecheck.ax` moves.

  *Answered: in neither binder.* The name sits in a spare word of the
  annotated type node (`tyRegion`, `parser.ax`, word 7). The region
  pass reads it from the declared signature, and nothing else reads
  it. No type-checker function moved for it. `tyCompat`, `tyResolve`,
  `tyRender`, `evClassOf` and codegen's `fldClass` all read a type
  through its tag and payload words and never see the name. That is
  why an annotated program emits byte for byte what its stripped twin
  emits (`check-region-escape.sh` section 1). The cost: an
  instantiation copy of a type carries no annotation, so the pass reads
  declarations, never inferred types.

- **What is `main`'s region?** Naming it `@global` makes today's
  programs the one-region instance (§2.4). Whether it can be reset at
  all is a separate decision.

  *Answered: it has no name, and needs none.* Every function's own
  region is its caller's current region (identity 0 in the walk).
  `main`'s caller is the runtime, so `main`'s region is the arena as a
  whole. A static literal has no region at all and instantiates any.
  Whether the root can be reset is S2's question about the `region`
  form, not this stage's.

- **Does `restrict(no-escape)` need a new diagnostic code, or does it
  join `AX3049`?** The restriction rail is closed (`AX3052`), unlike
  the AXTAG key namespace, so adding a code is a table edit.

  *Answered: it joins the rail.* A refuted claim draws `AX3049`, naming
  the parameter and the callee the fresh value went in through. An
  unverifiable claim draws `AX3051`, and `AX3057` under `strict`.
  `tests/diagnostics/649-restrict-no-escape.ax` holds all three. The
  four new codes, `AX3060` to `AX3063`, belong to the escape rule, not
  to the restriction.

- **Cycles promoted out of a region still leak** (§2.6). This design
  neither fixes nor worsens `MM-LIFE-3`.
