# Regions — design and implementation history (non-normative)

The authoritative `MM-RGN-*` contract is now
[memory-model.md §3.6](memory-model.md#36-checked-lexical-regions), with
implemented **H**, planned **P**, and withdrawn **W** entries in its
conformance table. This record supplies dated measurements and the
reasoning behind decisions. It defines no normative rules.

The initial measurements were taken at `19cb860` on darwin-aarch64;
later entries name their own dates. Present-tense claims in the
historical sections describe those snapshots, not an additional current
contract. In particular, S4 release elision is complete, but typed
sibling task regions and heap-result promotion remain planned. Raw-word
lifetimes and foreign sharing are still programmer obligations; see
[the memory audit](assurance/memory-audit.md).

The original direction was declared typed regions over the existing
arena, and one parallel surface with process and thread lowerings.
The measurements below sized that work; they did not establish a
universal memory-safety or timing guarantee.

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

## 2. Design decisions and dispositions

These are historical decisions. The linked specification owns their
current wording, evidence and status; the original proposal text is
available in the version history of this file.

### 2.1 The runtime already existed

`MM-RGN-1` used the existing arena position and reset operation for a
lexical scope. S2 implemented a stack mark cell and a scalar-result
restriction. It did not implement automatic promotion of a heap result.

### 2.2 Lexical outlives order

`MM-RGN-2` selected a lexical tree order. The implementation also treats
distinct signature region names as unordered, each outliving the
caller's current allocation region. It does not construct sibling
region nodes for `parallel` bindings.

### 2.3 The escape rule

`MM-RGN-3` became the checked-origin store/return/capture rule. The
original claim that it would subsume all raw-reset, live-evidence and
invisible-store obligations was too broad: erased addresses retain
programmer obligations, and the dynamic mark/evidence guards remain.
The canonical rule states the covered domain.

### 2.4 Annotations and the common case

`MM-RGN-4` originally proposed that every reference parameter and result
share the caller's region. S3 instead reads callee facts, allowing a
read-only use of an outer value while refusing an escaping store.
This supersedes the invariance proposal without adding runtime
arguments. The annotated-versus-stripped comparison remains a gate.

### 2.5 The witness changed during implementation

The original `MM-RGN-5` proposed a hidden trailing mark-cell word per
region parameter. That proposal was declined on 2026-09-26 and is
withdrawn in the specification. The bump allocator cannot place a new
value below an inner waterline merely by receiving an outer mark.

`MM-RGN-5a` records what actually shipped: post-fixpoint freshness
stamps consumed at release sites, with no runtime witness word. The
S4 entries below retain the measurements and path-specific ablations.

### 2.6 Reclamation and counting

`MM-RGN-6` retains counting except where a particular release is proved
redundant. The original claim that counting survives *only* for values
outliving their region was not implemented as a general rule. Nor is
reset's total work a single pointer move: it also clears size-class
heads and processes surplus chunks. The canonical contract states the
composition once, including destructor and shallow-copy limits.

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

The original `MM-RGN-7` proposal put each binding in a typed sibling
region and promoted its result into the parent at join. That remains
**P** in [the specification](memory-model.md#36-checked-lexical-regions).
S5/S6 implemented the surface, the two lowerings, written-order joins,
and word transport. Neither a word crossing a join nor the capture
refusals is recursive typed heap promotion. The following dated account
explains why the stronger sibling-region claim did not follow from S3.

### 3.2b The sibling-region rule did not ship, and `--threads` is unsound without it

*Measured 2026-09-03. This section exists because the tree said the
opposite in two places.*

§3.2 says each `parallel` binding runs in its own region, siblings are
unordered by MM-RGN-2, and therefore every cross-thread reference is
refused by MM-RGN-3 "for free - no `Send`, no `Sync`, no auto-trait."
`self_host/codegen.ax` cited that as work S3 would deliver. **S3
delivered region-annotated signatures and the escape rule (`AX3060`,
`AX3061`, `AX3062`) and none of this.** Three findings, each checked:

1. `rgnCheckAll` returns immediately unless `rgnProgramUsesRegions`
   answers 1, and that answers 1 only for a signature carrying an `@r`.
   **A `parallel` program with no region annotation runs the region
   pass zero times.**
2. The sibling regions were never created. `mkParallel` binds the
   region name `p` with an ordinary `let` to `__axiom_arena_mark` — a
   machine word. There is no region node, so there are no siblings to
   be unordered.
3. A program capturing a heap `String` into two concurrent bindings
   **compiles with no diagnostic and runs** under `--threads`.

The consequence is corruption rather than a leak: `axiom_retain` and
`axiom_release` are a plain load-add-store, not an `atomicrmw`, so two
threads touching one block's count lose an increment and the block is
freed while a live reference names it.

**What holds today.** Processes are the default lowering and are safe by
construction (MM-PAR-3). `--threads` is opt-in and carries a capture
discipline *the compiler does not enforce* — `tests/stdlib/470-parallel.ax`
captures only words because that is the discipline, not because anything
checks it. `AX4006` refuses `--threads` where there is no thread runtime,
which is a different question.

**The fix, scoped.** A checker rule at the `__par_spawn` /
`__thread_spawn` application, not a codegen one. Codegen has `fldClass`
but no capture types before emission and no way to report a diagnostic;
at `parScan` time the type table is unpopulated, so `fldClass` would
answer "not a reference" for every `struct` and every `data` — a check
that passes on exactly the types that matter. The checker has the
pieces: `parallel` is desugared in the *parser*, so the checker sees a
plain application with a lambda argument; scope entries carry types
(`sEntTy`), the lambda boundary is `tc` slot 22, and `checkSet` already
uses `scopeFindIdx` against it. Make it **unconditional** rather than
`--threads`-dependent, or the diagnostic appears and disappears with a
codegen flag, which nothing else in the AX3xxx band does.

**Closed 2026-09-11, the indirection half.** `checkSpawnCaptures`
(`self_host/typecheck.ax`) scans a literal-lambda thunk as before, and
now refuses a thunk that is a frame-local name of arrow type: the
`viaHop` wrapper above draws `AX3064` at `f`, a bare top-level name
stays silent, and a non-arrow local stays the argument checker's (one
mistake, one diagnostic). `tests/diagnostics/643` pins the refused
shape and both controls.

**Closed 2026-09-16, the opaque-thunk half.** What 09-11 left open —
a thunk that is neither a lambda nor a bare name — is walked
structurally now (`capWalkThunk`): a conditional, a match, a `let`
and a brace block are transparent, so every lambda they can answer
is scanned where it stands, while whatever they read to choose or
build it is collected as a capture; a call result and a field are
refused at the shape (`emitSpawnOpaque`), whose captures no walk
can see. `tests/diagnostics/644` pins the four refused shapes and
the three controls (word-only conditional and match, `__proc_spawn`
exemption). What this does NOT build is the sibling-region
typing §3.2 describes — no region nodes are created for bindings, and
`rgnCheckAll` still runs only under `@r` signatures. The safety
property that typing was meant to provide (no unrefused capture reaches
a thread) now holds by refusal instead: every shape the checker can see
is either scanned or refused. Typed precision (accepting captures
a region discipline proves safe) waits for S4 with everything else.

---

**Built 2026-09-03 (S5 and S6), and two things the table above promised
are narrower than it reads.** The surface is exactly MM-RGN-7's, with
`p` bound to the arena mark of the enclosing region (§2.5's witness, a
word until S3 types it), and the two lowerings are selected by
`--threads` with processes the default. *"Results are moved into `p`
at join"* is true of a **word**: the thunk is `(-> Int Int)`, so a
binding whose expression is a `String` is refused at that expression
(`AX3004`), because under processes the answer crosses an address space
through one page and under threads it would need the typed promotion
of §2.6, which is S3/S4's. And the last row of the table - *"`MM-RGN-3`
is a load-bearing static check"* under threads - is the check that does
NOT exist yet: a binding may capture any heap value in scope, and under
threads that value's count is touched from two threads with no fence.
The process lowering has no such hazard, which is why it is the
default; the thread lowering is what §3.2's corollary will make safe
once regions are typed, and until then a program that opts into it
captures words. `scripts/check-parallel.sh` holds the rest: the same
bytes out of both lowerings, a trapping binding exiting 77 out of both,
processes importing nothing, threads importing their own two symbols
(three on Darwin), and the flag inert on a program that spawns nothing.

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
| S3 | **BUILT 2026-09-03, save the witness.** Region-parameterised signatures, `(Str @r)`, and `MM-RGN-3` checked over every body; `restrict(no-escape)`; the sweep of §5 as a gate | typecheck (`rgnCheckAll`, a facts fixpoint over the call graph plus one reporting walk), parser, formatter, grammar; NO codegen — the witness of §2.5 is deferred to S4, see below | `scripts/check-region-escape.sh`: an annotated program and its stripped twin emit byte-identical IR (1,652 lines); `tests/diagnostics/645`–`649` one per escape shape, AX3060–AX3063; the ablation — `rgnCheckAll` answering 0 — accepts all four and the program it then lets through reads reclaimed memory; the sweep reads 241 of 6,206 (3.88%) |
| S4 | **VERDICT RUN 2026-09-26.** Delete ownership traffic the region proves dead | codegen | **re-run §1.1's ablation and expect the binary win with the RSS win intact** — the one measurement that decides whether any of this was worth it. Run: `check-region-verdict.sh` — 7,951 literal releases on self_host, per-fixture deltas 18/23/21/24/21/26/10, aggregate binary −32 B, RSS 99–100%, answers identical. The verdict row below carries the numbers |
| **S5** | **DONE 2026-09-03. `__thread_spawn`/`__thread_join`, and `cgThreads`'s owed body** | the primitive pair, the scan (`parScan` in codegen.ax, before `emitAllocator`), the thread runtime (`emitParThread`: the platform's `pthread_create`, an entry that runs the thunk and writes its word) | `scripts/check-thread-local.sh` reaches the ON path through a program that spawns, no ablation: eight globals move and nothing else, the OFF path imports no TLS symbol, a thread's cost is `pthread_create`+`pthread_join` (+`__tlv_bootstrap` on Darwin), local-exec on both Linux targets. freebsd and windows refuse it at build time (`AX4006`) |
| **S6** | **DONE 2026-09-03, with the limit stated. `parallel`, both lowerings** | the surface is a parser desugaring over `__par_spawn`/`__par_join` (no AST tag); the two backends are `emitParProc` (fork, one `MAP_SHARED` page per binding, `wait4` re-raising a child's status) and `emitParThread`, selected by `--threads` | `scripts/check-parallel.sh`: `tests/stdlib/470-parallel.ax` and `471-parallel-trap.ax` under both lowerings, byte-identical stdout and the same exit (77 out of both for the trap); processes add no import, threads add exactly their own; the flag is inert on a program that spawns nothing; windows emits a status-79 trap in place of both primitives. **What crosses a join is a word, and captures are unchecked under threads** - §3.3 below, and §3.2b for why S3 did not close it |

**S4 slice 1, BUILT 2026-09-11 - direct-construction temporaries, and
the hole beside it.** `isRegionCoveredCon` (`self_host/codegen.ax`)
answers whether a release operand is a fully-applied construction the
emitter is building right here; `releaseOwnedArgs` skips emitting its
release while `argOwnedRelease` still says 1, so `mustTailOK` stays
conservative. A region-depth count (pair slot 9) bounds the textual
extent; `emitLamDef` clears it because a lambda may run after the
reset. `tests/stdlib/479-region-reclaim.ax` (eight terms) plus
`scripts/check-region-reclaim.sh`: six releases gone from the
fixture's IR and the diff is those six lines and nothing else, the
same eight answers under both compilers, peak RSS 98% across
300,000 regions, and an ablation answering 0 bringing all six back.

Three things this slice is not, each with the reason. Call results
are not covered: a callee may alias an outer value, and freshness
needs the MM-RGN-5 witness - the next slice. `VAR` operands and
field stores are not covered: the first needs def-tracking, the
second balances a retain in the same step. And the head check
mirrors `dispatchCall`'s order (locals shadow, effect ops dispatch,
the cast path aliases) because a registry hit alone is not the
decision - a `let`-bound lambda named `MkBox` turns `(MkBox 1)` into
a closure call, measured leaking without the guard, and constructors
CAN be named `cast`, probed.

**Sizing the next slice, measured 2026-09-16.** Every `axiom_release`
site in the compiler's own IR (`emit-llvm self_host/main.ax`, 387,162
lines), classified by what defines its operand with the same per-`define`
walk `check-static-release.sh` uses: 6,501 sites — 5,916 on call
results, 408 on `load`ed locals, 157 on `phi` joins, 13 on
`extractvalue` projections, 7 on static literals. So the witness's
ceiling is the 5,916: `VAR` operands need def-tracking and joins need
per-arm reasoning, each its own later slice, and neither is this one.
The top callees say why the witness is computed and never syntactic:
`strConcat` (1,203), `cat2`/`cat3`/`cat4`, `strDup`, `strSlice`,
`fmtInt` construct, while `memGetWordStr`, `vecGetStr`, `tokenLexeme`,
`bareOf`, `nodeAName`, `fpSrc` and `sysArg` read into memory the callee
did not build. A witness answering "fresh" for every call result
answers it for those too; telling the two columns apart per callee —
read, as `rgnRounds` reads callees — is exactly MM-RGN-5's job, and
this census is its worksheet.

**Forcing the fixpoint on every build costs ~14s, so the trigger stays
and grows.** Timed 2026-09-16 on the compiler itself (`symbols
self_host/main.ax`, 4,614 rows): 3.98s without `--mir`, 18.11s with
it — the fixpoint plus projection, ~14.1s, which every build would
pay three times over in bootstrap. The real tree converges: zero
`#mir-truncated` rows, 1,656 carrying `#mir-result-fresh`. And the
trigger can stay cheap: `self_host` holds no real region form (the
seven textual hits are the printer's spelling, an error message, and
comments), while `stdlib` holds one (`Http.ax:379`) — so "a region
form is present" keeps the compiler's own build and every region-free
program at zero added cost, provided the test itself is O(1) and not
a body scan on every check. That is slice 2b's shape: a parser-set
bit, ORed with the `@r` test, with truncated still meaning the
witness abstains and codegen keeps every release.

**Slice 2b, BUILT 2026-09-17 - the trigger, without the report.** TC
word 39 (`rgnHasForm`) is set by `checkRegion` as a side effect of
the S2 walk that already visits every region form, so `rgnCheckAll`
reads it in O(1) with no additional body scan. It is checker-set
during that walk rather than parser-set, because the parser has no TC
to set and changing `parseModuleWith`'s PResult shape touches every
caller, while the S2 walk already sees every form exactly once.
ORed with the `@r` test: `@r` present means ensure facts plus the
reporting pass, as before; a region form with no `@r` means ensure
facts for the coming witness and no reporting pass; neither means 0.
No report when only the form is present, because reporting there
double-reports every S2 shape (AX3059 with AX3060 on 631, measured
2026-09-12); the callee-mediated hole below stays open, pinned, and
stated. Truncated still means the witness abstains:
`rgnEnsureFacts` records it on words 28/33 and the future elision
keeps every release. Measured on a baseline built the same way:
`emit-llvm self_host/main.ax` byte-identical (389,450 lines both
ways), 2.6s against 2.6s; 631 still draws only its three AX3059s;
479 checks OK.

**S4 slice 2, args path, BUILT 2026-09-17 - fresh call results handed
to a call.** The witness is a stamp, not a query: the region pass
records a proven-fresh call result on its own node (`nodeResWord` 0
to 2, post-fixpoint only, never while facts are still moving and
never when truncation made every row a lower bound - TC word 40,
`rgnStamping`, is what distinguishes the stamp walks from the
fixpoint's own passes; the abstention is global, a truncated
fixpoint stamps nothing anywhere and keeps every release, which is
the safe direction, a missed elision and never an early free), and `releaseOwnedArgs` spends the stamp
exactly where slice 1 spends its construction test, while
`argOwnedRelease` still says 1 so `mustTailOK` stays conservative.
Fresh means the callee's facts say the answer derives from CUR0,
from no heap parameter (a scalar-typed parameter contributes no
alias, so a cell built over words is still a fresh cell - `mkBox`
over `Int` stamps and `idBox` over `Box` does not - and a callee
that TAKES a heap parameter without letting it reach the result
stamps too: `wrapBox` over `Box` and `Int` answers a cell built
over the word alone, and term 9 pins the elision, so a walker that
abstained on any heap parameter would fail the gate), and from no call
the walk could not resolve; the call must be saturated, an annotated
result is never stamped, and a word answer is never touched (every
old reader asks `== 1`). Constructors are not stamped - slice 1 owns
them syntactically, so the two deltas never overlap. Inlined rather
than factored, so no new top-level function moves the
effect-distribution pins. `tests/stdlib/480-region-fresh-call.ax`
(nine terms) plus `scripts/check-region-fresh.sh`: seven releases
gone from the fixture's IR and the diff is those seven lines and
nothing else, the same nine answers under both compilers, peak RSS
100% across 300,000 regions of fresh calls, and an ablation of the
args-path spend bringing all seven back. What is NOT this slice is a
fresh call result bound by `let` and released at scope end:
`releaseOwnedArgs` never sees it, so the stamp sits unused on it
(term 4 pins one, kept) until the scope-end walker learns to read
it.

**S4 slice 2, scope-end path, BUILT 2026-09-17 - the same stamp at
`let` scope end.** A result bound by `let` never reaches
`releaseOwnedArgs` at all - `valueOwnedRef` answers 0 for a local,
so the argument position keeps its silence and MM-LIFE-2c event 3
pays the share at the binding's scope end instead. `emitLetAt`
spends the stamp there: same witness, same depth gate, same
`releasable` decision left untouched with only its spending
conditional, and the pending vector still taking the share for the
tail-jump path, which keeps its release. `emitLetMAt` needs nothing:
a mutable binding keeps its alloca and has no scope-end release to
spend. `tests/stdlib/481-region-fresh-let.ax` (eight terms, every
fresh call a `let` initialiser and every consuming argument a bare
name, so the args path has nothing to spend) plus
`scripts/check-region-fresh-let.sh`: eight releases gone and the
diff is those eight lines and nothing else, the same eight answers
under both compilers, peak RSS 100% across 300,000 regions of bound
fresh calls, and an ablation of the scope-end spend bringing all
eight back. Both ablations are path-specific on purpose - ablating
the shared stamp would restore traffic the walker under test never
owned. What remains of S4 is counted, not promised: pair-error
projections (`extractvalue` of an errno out of a two-word pair, 13
sites in the compiler's own IR), scope-end releases of string
literals (runtime no-ops through the `-1` sentinel, 7 sites), and
the call/join traffic the witness correctly keeps (readers,
escapes, unknown callees). Field
stores are not among them, finally and not deferred: a field
store's release balances a retain in the same step (`emitSetF`
retains the value into the field beside releasing the temporary),
and the field slot outlives any region the walk can prove, so no
reset covers both halves and eliding one half would leak.

**S4 slice 4, scrutinee path, BUILT 2026-09-17 - match scrutinee
temporaries.** A `match` consumes its scrutinee, released after
the merge when `scrutineeReleasable` says no arm binder escapes
through its body (binders are the block's fields). No new stamp:
the spend reads slices 2 and 3's (`nodeResWord` 2 - a fresh call,
or a fresh join, including a nested match whose result register is
a scratch-cell load, the one "match temp" shape that is a `load`
in the census's terms), under the same depth gate, in
`releaseScrutinee`, shared by the tail and non-tail emitters. The
pending vector still takes the share for the tail-jump path;
`argOwnedRelease` is not asked, so `mustTailOK` cannot drift.
`tests/stdlib/484-region-scrutinee.ax` (twelve terms) plus
`scripts/check-region-scrutinee.sh`: eight releases gone from the
fixture's IR and the diff is those eight lines and nothing else,
the same twelve answers under both compilers, peak RSS 99% across
300,000 regions of fresh scrutinees, and an ablation of the
scrutinee spend bringing all eight back.

**The load census behind slice 4, measured 2026-09-17.** Every
`axiom_release` site in the compiler's own IR, classified by what
defines its operand as in the S4 sizing above: 404 on frame-slot
loads, 6 on heap-field loads. Of the 404, all but one sit on a
function's return path - tail-loop parameter slots, the entry
retain's counterpart (`releaseRefParamSlots`) - callee-shared code
no call site may elide, finally. The rest, frame and heap alike,
are `set` old values, retain-new/release-old paired with
provenance unknown. Match-result scratch loads spend in slice 3
already (its elided operands include `load` definers, measured on
the fixtures). And a field read is a borrow at every site - a
field read handed to a call, bound by a `let`, matched on, or
taken as a join arm all answer unowned (`valueOwnedRef` 0), so no
release site exists to spend on; probed in all four positions,
kept everywhere. That is why the slice is one spend site and a
page of measured negatives.

**S4 slice 3, args path, BUILT 2026-09-17 - joins whose every arm
is fresh, handed to a call.** A join answers whichever arm it
took, so freshness needs per-arm reasoning rather than a
callee fact: the region pass stamps the join itself
(`nodeResWord` 2) iff every arm value node already carries the
stamp - a proven-fresh call result, or such a join, the inner
stamping before the outer reads it in the same post-fixpoint walk.
Anything else for an arm abstains, and so does the join: a reader
arm, an arm through a call the walk cannot resolve, a construction
arm (slice 1's syntactic domain, never stamped, so the stamp keeps
its one meaning), a bare name, and a missing `else`, which is not
a stamped arm. Same guards as the call stamp (post-fixpoint walks
only under TC word 40, converged facts only, upgrade 0 to 2), and
`releaseOwnedArgs` spends the stamp exactly where slices 1 and 2
spend theirs while `argOwnedRelease` still says 1, so `mustTailOK`
stays conservative. Threaded through the existing arm walkers
(`rgnArms`, `rgnCondClauses` - the `else` walks last inside the
cond walker, exactly where it walked before, so no side-effect
order and no diagnostic moves) and inlined at `if` and both spend
sites, so no new top-level function moves the
effect-distribution pins. `tests/stdlib/482-region-phi-call.ax`
(eleven terms) plus `scripts/check-region-phi.sh`: seven releases
gone from the fixture's IR and the diff is those seven lines and
nothing else, the same eleven answers under both compilers, peak
RSS 99% across 300,000 regions of fresh joins, and an ablation of
the args-path join spend bringing all seven back. What is NOT this
slice is a fresh join bound by `let` and released at scope end:
`releaseOwnedArgs` never sees it, so the stamp sits unused on it
there (term 5 pins one, elided in both arms of this gate's delta
by the scope-end walker, the sibling entry below).

**S4 slice 3, scope-end path, BUILT 2026-09-17 - the same stamp at
`let` scope end.** A join bound by `let` never reaches
`releaseOwnedArgs` at all - `valueOwnedRef` answers 0 for a local,
so the argument position keeps its silence and MM-LIFE-2c event 3
pays the share at the binding's scope end instead. `emitLetAt`
spends the stamp there: same witness, same depth gate, same
`releasable` decision left untouched with only its spending
conditional, and the pending vector still taking the share for the
tail-jump path, which keeps its release. `emitLetMAt` needs
nothing: a mutable binding keeps its alloca and has no scope-end
release to spend. `tests/stdlib/483-region-phi-let.ax` (eight
terms, every join a `let` initialiser and every consuming argument
a bare name, so the args path has nothing to spend) plus
`scripts/check-region-phi-let.sh`: eight releases gone and the
diff is those eight lines and nothing else, the same eight answers
under both compilers, peak RSS 100% across 300,000 regions of
bound fresh joins, and an ablation of the scope-end join spend
bringing all eight back. Both ablations are path-specific on
purpose - ablating the shared stamp would restore traffic the
walker under test never owned.

**S4 slice 5, BUILT 2026-09-26 - scope-end and tail-temp releases
of string literals.** The second half of the counted remainder:
`isStaticSentinelNode` is now asked at all four sites that emit a
release for a value that IS the literal. `emitLetAt` skips the
scope-end release when the initialiser is a bare `TAG_E_STR` (the
binding is immutable, so SSA still holds the literal there), and
`releaseTailTemps` skips an argument temporary that is one (the
`""` a tail loop threads through, measured twice in
`codegen$scanLineMarks`). Same shape as the stamp spends -
`releasable` still says 1, the pending vector still takes the
share for the tail-jump path - so the shared predicate's ablation
restores every one of these with the other sites'. Census on the
compiler's own IR: static-literal release operands 7 to 0, every
other bucket unchanged (6,380 call, 451 load, 168 phi, 13
extractvalue). `scripts/check-static-release.sh` grows the
coverage: the fixture binds and tail-passes literals (ablated: 5
static releases, so all four positions are live), the corpus cap
goes 20 to 0, and the join guard still requires the join's own
share back. What remains of S4 is the first half of that
remainder: pair-error projections (`extractvalue` of an errno out
of a two-word call pair, 13 sites).

**The pair-error remainder, TRACED 2026-09-26 - required, not
dead.** All 13 sites are `Err` arms over `$pair` calls whose slot
1 holds `call i64 @Err$mkError(...)` - a fresh heap `Error`,
traced through `sysResult$pair` in the compiler's own IR. Each
release frees the block its own failed call built; eliding any of
them leaks one `Error` per failure. The bucket stays at 13 by
construction and grows legitimately with new syscall wrappers,
so there is no gate on the count - a static count here would
churn, not guard. S4's counted remainder is empty.

**The S4 verdict, RUN 2026-09-26 - the binary win with the RSS win
intact.** The S4 table row's criterion, `scripts/check-region-verdict.sh`,
three workloads against one fully-ablated compiler (slice 1's depth
guard, the stamp, and the static-sentinel answer all killed at once).
W1 is §1.1's workload itself: both compilers emit `self_host/main.ax`
and 7,951 releases come back, every one on a `@strhdr_*` literal
(4,293 headers) - the region kills provably inert where no region
form stands - while the emitting compiler's own peak RSS reads
692,672 KiB against 694,160 ablated (99%). W2 runs the six S4
fixtures plus a literal probe: per-file release deltas 18/23/21/24/21/26/10
against slice floors 6/7/8/7/8/8/4, every file's answers identical
both ways, every binary no bigger and the seven files' aggregate
251,248 bytes against 251,280 ablated. W3 loops 300,000 regions of
combined construction/call/literal traffic: the same 90001800000 both
ways, peak RSS 100%. No wall-clock claim, per §1.1's own correction.

The full pins decompose by operand definer, counted against both
IRs: 479 is 6 constructions (the slice pin) + 12 literals; 480 is 7
calls + 13 literals, 2 constructions, 1 call; 481 is 8 calls + 12
literals, 1 construction; 482 is 6 joins + 1 scratch load + 15
literals, 1 construction, 1 load; 483 is 6 joins + 2 scratch loads +
12 literals, 1 construction; 484 is 4 calls + 4 joins + 16 literals, 1
construction, 1 load; the probe is 4 guarded literals + 6
println-machinery literals. The dominant cross-traffic is literals -
the strings every fixture prints through. Two mechanisms the verdict
caught rather than assumed: restored releases flip `musttail`
decisions downstream (the W1 comparison normalises registers, cancels
alignment drift, and allows only the flip vocabulary plus the
release-count-scaled `@__axiom_line*`/`filen` tables), and function
alignment absorbs a few removed calls into padding (three fixtures
tie to the byte, which is why the strict win is pinned on the
aggregate). S4 is closed: the traffic the region proves dead is gone,
the binary is smaller for it, and nothing that freed anything went
with it.

**The adjacent hole, CLOSED 2026-09-17.** A callee-mediated store
of a fresh construction into an outer cell from inside an
UN-annotated region used to check OK and read back wrong (measured:
stored 1, read 0 after reuse, every gate green). S3's reporting
walk now runs for region-form programs too - the facts were already
computed for the witness, only the diagnostics were gated - and
refuses the call with a precise AX3060 naming the parameter and the
store path (`tests/diagnostics/653-region-escape-callee.ax`). S2
records its refused store spans on TC word 41 and the reporting
walk suppresses the same-store double, so each shape still draws
exactly one diagnostic: 631 keeps its three AX3059s, the evil shape
draws one AX3060, and the six S4 gates' evil probes - written for
the day both compilers refuse - take the refusal arm. The elision
stays outcome-identical there, because the reset frees
unconditionally. S3's "over EVERY body" holds now, including the
bodies no signature annotates.

**Why the fix is not "run `rgnCheckAll` everywhere", measured
2026-09-12 - and what landed instead.** Forcing the trigger on (one
line) refuses the evil shape with a precise AX3060 - and is silent
across self_host, stdlib and 558 test files EXCEPT
`tests/diagnostics/631`, where it adds two AX3060s on top of the two
AX3059s S2 already draws at 52:16 and 58:18. Same store, two
diagnostics: the S3 walk covers the textual shapes S2 owns, so a
universal trigger double-reports every one of them. The ways out
were retiring AX3059 into the walk (a diagnostic code retired, the
S2 gate's counts re-derived, the fixpoint paid on every program) or
suppressing one finding where the other fires. What landed is the
second, in its smallest form: not span coordination between two
walk architectures, but S2 recording the spans it refused and S3
skipping those spans - one vector on the TC record both passes
already share, an exact-span match, each shape keeping its own
diagnostic. No code retired, no S2 count re-derived, and the
fixpoint still runs only where a region form or `@r` asks for it.

**S3 as built, 2026-09-03 — what it is and what it is not.** Every
signature may name regions, `(Vec String @r)`, and the rule of §2.3 is
checked after the type checker has run, over EVERY body in the program:
a store (`set`, a field write, `__store64`, or a store a callee makes
through its parameter), a return, and a capture. The half that made it
tractable is that an un-annotated callee is read rather than assumed:
`rgnRounds` computes per function, as a monotone fixpoint over the
call graph exactly as `inferEffects` does, which parameters the body
stores a fresh value into and which parameters flow into which, so
`(vecPush v x)` is refused across regions and accepted within one
without any annotation on `vecPush`. §2.4's "region-monomorphic in the
caller's current region" is that rule made precise by reading the
callee; stated as invariance it would refuse `(strLen s)` on an outer
string. The same facts answer `restrict(no-escape)` (§2.7): refuted by
name through the callee the store went through, unverifiable over a
call the walk cannot resolve, on AX3049/AX3051/AX3057's rail.

Three things S3 does NOT do, each measured rather than assumed:

- **Nothing allocates INTO a named region.** A value the body makes
  lives in the caller's current region (§2.4), which no named region
  is inside of, so storing it into a `@r` place or answering it as
  `(T @r)` is refused - and that includes `vecPush` on a `@r` vector,
  because growing it allocates (`tests/diagnostics/640`, row 3). That is
  the honest reading until S4 hands a callee a region to allocate in,
  which is what the witness is for.
- **The witness of §2.5 is not plumbed**, and deliberately. Its value is
  a region's mark cell, which S2's lowering defines, and its only reader
  is S4's allocation. Adding a hidden trailing word to a
  region-polymorphic function now would change the IR of exactly the
  programs this stage can otherwise prove inert - the byte-identity of
  `check-region-escape.sh` section 1 - for no consumer. It lands with
  its first reader.
- **A value promoted out of a `(region r ...)` form is treated as the
  enclosing region's, shallowly.** The walk has the arm for S2's node,
  written against its contract; whether `reset_keeping` can carry a
  value whose FIELDS point into the region (MM-ALLOC-15 carries one
  contiguous block) is S2's lowering question and is not answered here.

And two conservative readings, each a false refusal rather than a
missed escape: a call the compiler cannot resolve - through a
parameter, a closure, a field - is assumed to store every argument into
every argument; and a `match` binder takes the SCRUTINEE's origins, so
an element unwrapped from a freshly built `Some` carries the wrapper's
region as well as the payload's (`tests/stdlib/468`'s `left` is written
over a `@r` value for that reason).

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

3. **Whether the RSS survives S4 — RUN 2026-09-17, and it does.**
   §1.1's ablation deleted the releases and lost 2.4× on peak RSS.
   Each S4 slice carries its own RSS half: 300,000 regions under the
   test compiler against the path-ablated one, peak RSS 98–100% in
   every slice gate (`check-region-reclaim.sh`,
   `check-region-fresh.sh`, `check-region-fresh-let.sh`,
   `check-region-phi.sh`, `check-region-phi-let.sh`,
   `check-region-scrutinee.sh`). The reset returns in one pointer
   move what counting used to free, per path, not just in total.
4. **The wall-clock question — RUN 2026-09-17, and there is none to
   find.** The same 300,000-region loop from slice 2's gate, built
   with the test compiler and with the args-path ablation (releases
   kept), timed with hyperfine best-of-10 on an Apple M1: 404.3ms
   against 401.3ms one way round, 397.6ms against 402.8ms the other
   - the faster side flips with the order, and both gaps sit inside
   the runs' own ±10ms spread. Three hundred thousand deleted
   release calls buy no measurable time either way; the win is
   binary size with the RSS intact, which is what the gates above
   hold.

---

## 6. Open questions

- **Where does a region's name live in the type?** `(Str @r)` is
  written above as if regions were an extra parameter list. Whether
  they are a second binder or share the existing type-variable binder
  decides how much of `typecheck.ax` moves.
  *Answered 2026-09-03: in neither binder.* The name sits in a spare
  word of the annotated type NODE (`tyRegion`, parser.ax, word 7), read
  by the region pass from the declared signature and by nothing else.
  The count of type-checker functions that moved for it is **zero** -
  `tyCompat`, `tyResolve`, `tyRender`, `evClassOf`, codegen's `fldClass`
  all read a type through its tag and payload words and never see it -
  which is what makes an annotated program emit byte for byte what its
  stripped twin emits (`check-region-escape.sh` section 1). The cost:
  an instantiation copy of a type carries no annotation, so the pass
  reads declarations, never inferred types.
- **What is `main`'s region?** Naming it `@global` makes today's
  programs the one-region instance (§2.4). Whether it is resettable at
  all is a separate decision.
  *Answered 2026-09-03: it has no name, and needs none.* Every function's
  own region is "its caller's current region" (identity 0 in the walk),
  and `main`'s caller is the runtime, so `main`'s region is the arena
  as a whole; a static literal has no region at all and instantiates
  any. Whether the root is resettable is S2's question about the
  `region` form, not this stage's.
- **Does `restrict(no-escape)` need a new diagnostic code**, or does it
  join `AX3049`? The restriction rail is closed by design (`AX3052`),
  unlike the AXTAG key namespace, so adding one is a table edit.
  *Answered 2026-09-03: it joins the rail.* AX3049 refuted (naming the
  parameter and the callee the fresh value went in through), AX3051
  unverifiable, AX3057 under `strict`; `tests/diagnostics/644` holds
  the three. The four codes that ARE new, AX3060-AX3063, belong to the
  escape rule and not to the restriction.
- **Cycles promoted out of a region still leak** (§2.6). This design
  neither fixes nor worsens `MM-LIFE-3`, and says so rather than
  leaving a reader to hope.

