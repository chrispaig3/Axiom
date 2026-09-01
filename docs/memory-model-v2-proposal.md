# Toward Axiom's own memory model — a design proposal

This is not a specification. `docs/memory-model.md` remains the
normative source of truth; nothing here is binding until a rule moves
there. This document is Phase 1 (a map, with the withdrawn/held/planned
status of every rule area), Phase 2 (the seams — where the model reads
as inherited rather than designed, each backed by a command run against
the compiler in this worktree), and Phase 3 (proposals, each priced and
each naming the gate that would hold it).

Every number below was measured on `/tmp/axc-mem/axc`, built from this
worktree at commit `6cfa571` via `./scripts/build-shared-axc.sh`. The
four targeted gates named in the task (`check-container-reclaim`,
`check-closure-reclaim`, `check-steady-state`, `check-memory-baseline`)
all pass against that build before any of what follows.

---

## Phase 1 — the map

### 1.1 Rule inventory, by status

Reading `docs/memory-model.md` end to end (4125 lines) and cross-checked
against §9's own conformance table:

| Area | Held (H) | Planned (P) | Withdrawn (W) | Refused (R) |
|---|---|---|---|---|
| Execution (EXEC) | 1–6d, 8–13, 15–17 | — | — | 7, 14 |
| Representation (VAL) | 1–11, 14–20 | — | — | 12, 13 |
| Allocation (ALLOC) | 1–7, 8a–16b, 22 | 8, 20 | 17–19, 21 | — |
| Mutation (MUT) | 1–5 | — | — | 6 |
| Lifetimes (LIFE) | 1, 3, 4, 6, 2g | 5, 7 | 2a–2f | 2 |
| Parallelism (PAR) | 1–5 | 6 | — | — |
| Foreign (FFI) | 1–6 | — | — | — |

`MM-VAL-21` (`alloc`/`*mut T`) is in **no column** — the document
itself calls it defective, neither implemented nor refused. That gap is
Phase 3 proposal P1 below.

### 1.2 The central fact: two reclamation stories, one strategy, one
machinery that outlived it

- **`MM-LIFE-2a`** chose automatic reference counting (ARC) as the
  strategy on 2026-08-11, specified it in `MM-LIFE-2b`–`2g`, and
  **withdrew it on 2026-08-24** in favour of `MM-ALLOC-22`: "the arena
  scope IS the reclamation strategy, not a bridge to one." A stateless
  request handler bracketed by `__axiom_arena_mark`/`reset` measures
  **100–313× less peak RSS** than the same binary unscoped
  (`scripts/check-net.sh`), and the LSP's per-edit footprint is **840
  bytes bracketed against 193,247 unbracketed**.
- But `MM-LIFE-2a` is withdrawn in §0.3's *second* sense —
  **abandoned in place**. All seven of `MM-LIFE-2c`'s ownership events
  emit on every build today (`tests/stdlib/355-arc-events.ax` and
  siblings), `MM-LIFE-2b`'s 16-byte header is on both allocation paths,
  `MM-LIFE-2d`'s evidence word and shape word hold, `MM-LIFE-2e`'s
  release path files dead blocks onto sixteen-byte size classes. None
  of that machinery is coming out — ripping it out is its own
  measurement, and the machinery is what took the compiler's own
  self-compile from 2.93 s / 314 MiB to 1.94 s / 248 MiB.
- The **seven ownership events**, and which emit (§5, `MM-LIFE-2c`):

  | # | Event | Emits since |
  |---|---|---|
  | 1 | a call borrows its arguments (no retain) | always (no-op by design) |
  | 2 | a function returns its result owned | 2026-08-21 |
  | 3 | frame slots own; scope-end release of a direct construction | 2026-08-21/15 (direct-construction subset) |
  | 4 | self-tail-call boundary retains/releases per jump | 2026-08-15 |
  | 5 | field store retains new, releases old | 2026-08-15 |
  | 5b | closure-application intermediate record given back | **2026-08-30** |
  | 6 | building a block stores reference fields owned | 2026-08-15 |
  | 7 | `handle` releases its evidence record at exit | 2026-08-15 |

  All seven emit. Event 5b is the newest and is what the recent
  "closure-argument leak is load-bearing" work (commits `07ee175`
  through `89003cb`) closed — see §2.2 below.

- **The arena** (`__axiom_arena_mark`/`reset`/`reset_keeping`,
  `MM-ALLOC-12`–`16b`) is a *separate, manually-bracketed* mechanism:
  three primitives that move the allocator's bump pointer, with **three
  unchecked program obligations** (`MM-ALLOC-16`, `16a`, `16b`) about
  what may be read after a reset, in what nesting order marks may be
  reset, and that an evidence record's extent must not be reset past.
  The two systems are made to *compose* rather than replace each other:
  an arena reset scrubs all 4,097 slab-class free-list heads first,
  specifically so a dangling ARC free-list head does not double-issue
  storage after the reset (`MM-LIFE-2e`) — a runtime guard whose entire
  reason to exist is that both systems are live in the same binary at
  once, costing **1.7–1.8% of a per-connection budget**,
  `scripts/check-arena-reset-rate.sh`.

### 1.3 The evidence word and the invisible-store rule

`MM-VAL-2`: a machine word carries no tag. Reference counting therefore
needs a second channel to know, at a polymorphic call site, whether a
type-variable-typed argument is a reference — `MM-LIFE-2d`'s **evidence
word**: one hidden trailing `i64` per polymorphic function, bit *k* set
iff type parameter *k* is instantiated at a reference type
(`self_host/typecheck.ax:2807`–`2835`). A lifted lambda now carries a
second evidence channel for *its own* parameter,
`EV_LAMARG` = −2 (`typecheck.ax:845`), and since 2026-08-30 that witness
travels **by depth** — `EV_LAMARG - d` for a parameter *d* lambdas out
(`typecheck.ax:948`, `857`) — because a curried lambda chain nests one
frame per parameter and the witness has to identify which frame it
belongs to.

`MM-LIFE-2g`, the **invisible-store rule**: a store that erases a
value's type (`cast Int` inside a polymorphic function — exactly two
places in the whole implementation, `Mem.memSetWord` and the AST's
`mkNode`) takes a share via `__retainref`, the one primitive whose
signature is polymorphic on purpose. This is the *sanctioned* escape
from the reference model; every other route out (`__addr`, `strData`,
`strOwner`, a raw `__store64`) is a program obligation with no check.

### 1.4 The shape word — record and array forms

`MM-LIFE-2d`/`2h`: every counted block's header word −1 holds a shape
word. Two forms:

- **record form** (bit 0 = 0): an inline reference bitmap over up to
  **47 payload words**, refused past that cliff as `AX3029`. Used for
  constructor blocks, structs, closures, evidence records — anything
  statically small.
- **array form** (bit 15 set): one element-pointerhood bit plus an
  element count, for `Vec`/`Map`/`Intern`'s homogeneous data buffers and
  `Str`'s byte buffer, where a per-word bitmap would not fit and
  should not need to.

Both forms are read by exactly one consumer, `@axiom_release`'s dead
path, and written by the allocation site alone — there is deliberately
no `memIsArray` query (§3.5, `MM-LIFE-2h`).

---

## Phase 2 — the seams, each measured

### 2.1 You always pay for reference counting, whether or not you use
the arena

A struct construction with **zero** arena calls anywhere in the
program:

```scheme
(import Str)
(struct Pt (x : Int) (y : String))
(:: mk (-> Int Int))
(fn (mk n) { (let ((p (Pt n (strDup "hi")))) (cast Int p)) })
(fn (main) 0)
```

`axiom emit-llvm` on this produces, for `@mk`:

```llvm
%.t0 = call i64 @axiom_alloc(i64 16)
store i64 131076, ptr %.t2        ; shape word
store i64 1, ptr %.t4             ; count word, born at 1
store i64 %n, ptr %.t6            ; field 0, Int, no retain
%.t8 = call i64 @Str$strDup(i64 %.t7)
call void @axiom_release(i64 %.t7)   ; the literal (no-op: static sentinel)
call void @axiom_retain(i64 %.t8)    ; retain before store (event 3/6 order)
store i64 %.t8, ptr %.t10             ; field 1
call void @axiom_release(i64 %.t8)   ; local temp's own share given back
```

Six runtime calls for a two-field struct, and this is the *cheap* case
— `MM-VAL-2`'s untagged word means every reference-typed position pays
this, everywhere, regardless of whether the program ever calls
`__axiom_arena_mark`. `MM-LIFE-2a`'s own accounting only prices the
*interaction* tax (1.7–1.8% of a request, from the slab-head scrub) —
nowhere does the specification price the **baseline** retain/release
traffic for a program that never touches the arena at all, because that
traffic is not a cost anyone chose; it is the leftover of a strategy
that was chosen and then un-chosen. A program gets neither ARC's
completeness (cycles still leak, `MM-LIFE-3`/`2f`) nor the arena's
simplicity (three unchecked primitives, §1.2) for free — it pays the
first's tax and, if it wants bounded memory, still has to hand-bracket
the second.

**The place this bites hardest is exactly where the compiler's own
convention says not to type things.** `Vec`, `Map` and `Intern` handles
are `Int` in every stdlib signature (`MM-ALLOC-20`'s own text: "the
compiler's own containers and AST declare their handles `Int`, so no
type-directed ownership event can ever fire on them"). Any Axiom
program that follows that same idiom — which is the *only* idiom the
standard library currently offers for a growable collection — gets
**no** benefit from the per-object tracking it is still paying for on
every struct, closure and field store elsewhere in the same program.

### 2.2 The evidence-word-by-depth mechanism is a live bug class, and
it exists solely because closures are curried

`MM-VAL-17a`: "A multi-parameter lambda is curried into a chain of
one-parameter lambdas, **each allocating its own record**." Measured:

```scheme
(:: addDirect (-> Int Int Int))
(fn (addDirect a b) (+ a b))

(:: viaLambda (-> Int Int Int))
(fn (viaLambda x y) (let ((f (lambda (a b) (+ a b)))) ((f x) y)))
```

`@addDirect` compiles to one instruction: `%.t0 = add i64 %a, %b`.
`@viaLambda` compiles to: one `axiom_alloc(8)` for the outer curry
frame, one indirect call into `_lam_0`, which itself does a *second*
`axiom_alloc(24)` — three words: code pointer, captured `a`, and the
captured evidence word `__evwa.h`, even though both `a` and `b` are
`Int` and the evidence word is provably always 0 here — a second
indirect call into `_lam_1`, and an `axiom_release` on the intermediate
24-byte record. **32 bytes and two heap round-trips to do what
`addDirect` does in one add.**

This representation is exactly what the depth-indexed evidence
mechanism exists to make safe: `curLamVar` is a stack rather than a
name (`typecheck.ax:2044`), `evClassOf` answers `EV_LAMARG - d`
(`typecheck.ax:948`), and `collectCapNames` shifts each enclosing
lambda's word one level as it binds nested lambdas
(cited in `docs/memory-model.md` §5, `MM-LIFE-2g`). **The bug this
closed on 2026-08-30 was a live use-after-free**, not a leak: a
curried lambda's *own* parameter had no evidence word at all, so a
store inside it took no share (`MM-LIFE-2g`'s "THE HOLE" narrative,
commits `c09a198`, `89003cb`, `07ee175`). The fix is correct and
gated (`tests/stdlib/460-closure-reclaim.ax`,
`461-curried-closure-arg.ax`, both green on this build), but it is
real, load-bearing machinery whose entire reason to exist is the
curried representation.

**A corpus search finds zero uses of what that representation buys.**
Every multi-parameter `lambda` in `self_host/`, `stdlib/` and
`tests/**` is applied at its full arity in one syntactic spine, either
immediately or when a stored callback (an `HttpFn`, a trait method, an
FFI callback) is later invoked — never partially applied and stored as
a reusable intermediate value. `AX3013` already refuses partial
application for the far more common case, top-level named functions
(`typecheck.ax:8107`, `10400`): "a partial application has to hold the
arguments it was not given, and a top-level function has no closure
record to hold them in." Lambdas pay full generality's cost for a
generality this codebase does not exercise once.

### 2.3 A documented "SHOULD trap" is, in the generated code, silent
corruption with no discriminating branch at all

`MM-ALLOC-16a`: resetting an inner mark after its outer mark has
already been reset is undefined; "the implementation does not trap,
and a conforming implementation **SHOULD**." Reading the actual
generated reset helper (`self_host/codegen.ax:8396`–`8452`,
`emitArenaHelpers`'s `@__axiom_arena_reset_fn`):

```llvm
unwind:
  %c = phi i64 [ %chead, %resetbody ], [ %cnext, %unwind_body ]
  %reached = icmp eq i64 %c, %schunk
  %ranout  = icmp eq i64 %c, 0
  %stop    = or i1 %reached, %ranout
  br i1 %stop, label %tail, label %unwind_body
...
tail:
  store i64 %send, ptr @__axiom_high
  br label %restore
restore:
  store i64 %sbump, ptr @__axiom_bump
  store i64 %send, ptr @__axiom_bump_end
  store i64 %schunk, ptr @__axiom_chunk
  ret i64 0
```

`%reached` (the mark's chunk is still live) and `%ranout` (the walk
fell off the active-chunk list without ever finding it — exactly the
"already reset" case) are computed **separately** but merged into one
`%stop` before the branch. Both outcomes fall through to the same
`tail`/`restore` sequence, which restores the allocator's bump/end/
chunk position **unconditionally** from the saved mark cell — even
when that cell describes a chunk the allocator no longer owns. This is
not an abstract "undefined behaviour exists somewhere"; it is a
concrete, three-line merge in the one function whose entire job is to
keep the allocator's position sound.

### 2.4 Two more "documented but inert" surfaces, same class the
project already knows how to close

`(linear T)`/`(consume e)` used to parse and enforce nothing; as of
2026-08-25 both are refused outright (`AX2004`), closing exactly this
failure mode. Two more instances of it are still open:

- **`(alloc T)` / `*mut T` (`MM-VAL-21`).** Measured on this build:

  ```scheme
  (struct P (x : Int))
  (:: mk Int)
  (fn (mk) (cast Int (alloc P)))
  ```

  `axiom check` says `OK`; `axiom --diagnostic-format=ai symbols` reports
  `#effects=Alloc` on `mk`; `axiom run` exits 0, having evaluated `(alloc
  P)` to the constant 0 and cast it. A form that allocates nothing
  claims the allocation effect, and the type it produces cannot even be
  named in a signature.

- **`;@axiom:owned(arena=frame)` (leftover of `MM-LIFE-7`).** Measured:

  ```scheme
  ;@axiom:owned(arena=frame)
  (fn (leaky x) x)
  ;@axiom:owned(nonsense=whatever)
  (fn (leaky2 x) x)
  ```

  Both check `OK`. The tag does not even validate its own advertised
  vocabulary (`arena=frame`) — any payload is accepted silently.
  `docs/reference.md` already documents it as "accepted and
  unenforced," but a reader who trusts the syntax (the same reader
  `MM-LIFE-7`'s own `linear`/`consume` refusal was written to protect)
  has no way to discover that from the language itself.

### 2.5 The effect system's "constructors are invisible" decision is
coherent — and it fooled its own author within the week

> **SUPERSEDED 2026-08-31.** The decision this section analyses is
> reversed. A `data`/`struct` constructor of arity >= 1 now contributes
> `Alloc` at the application site (`typecheck.ax`, `ctorAllocArity`),
> because `restrict(no-alloc)` reads the effect row and, against a row
> built to omit allocation, could not refuse a body whose only act was
> to allocate. See `MM-EXEC-9a`, where the row is now listed as CLOSED
> with its measured cost (123 of 3,725 rows, seven false `no-alloc`
> claims), and `ERR-PROP-2`, amended the same day. **The four probes
> below still measure what they measured** — they are why this
> section is kept rather than deleted — but their expected answers
> have moved: `mkOk` and `mkErrLit` now report `#effects=Alloc`, not
> nothing. The section's conclusion, that the tax the commit blamed on
> `Ok`/`Err` was really `strConcat`'s, is unaffected and was correct.

`ERR-PROP-2` / `MM-EXEC-9a`'s table state, as a *decision*: applying a
`data`/`struct` constructor contributes nothing to the inferred effect
row, even though it allocates. Reading `walkEffectsSpine`
(`self_host/typecheck.ax:10927`–`10986`) confirms this is implemented
exactly as documented — `findFnEnt` answers 0 for a constructor head
(the same property `cast` gets), so no effect is added and no
"unresolved call" mark fires either.

The commit at HEAD of this worktree (`6cfa571`, "A short write stopped
looking like a complete one, and the Result migration's blocker is the
effect row") attributes a measured row-widening — porting
`sysWriteAllFd` to `(Result Int Error)` moved its row from `IO` to
`IO, Alloc, Mut` — to "`Ok`/`Err` allocate." Three narrowing probes
against this build isolate the actual mechanism:

```scheme
(fn (mkOk n) (Ok n))                                              ; no #effects=
(fn (mkErrLit n) (Err (mkError n "fixed literal")))                ; no #effects=
(fn (mkErrFmt n) (Err (mkError n (strConcat "errno " (fmtInt n)))))  ; #effects=Alloc,Mut
(fn (mkErrCat n) (Err (mkError n (strConcat "op: errno " ""))))      ; #effects=Alloc,Mut, even both operands literal
```

`Ok`, `Err` and `mkError` (itself a plain struct constructor) are all
exactly as effect-free as the decision says. The tax is `strConcat`
alone — it fires even concatenating two string *literals*, no
`fmtInt` involved. **The real story is narrower and more interesting
than the commit states it:** any `Result`-returning wrapper whose
`Err` arm explains *why* it failed with a computed message — which is
the entire reason error messages exist — pays `Alloc, Mut` and cannot
carry a `pure`/`IO`-only claim, cannot sit inside a `handle` whose list
is checked exhaustive against a narrower row (`AX3011`), and cannot
keep an `AXTAG` claim that predates the port. A canned literal message
costs nothing. The commit's own author, mid-migration, attributed the
cost to the wrong AST node — which is itself evidence that the
mechanism, though correctly implemented and correctly decided, is not
legible from the outside.

**This also exposes that `Mut`'s attribution is purely syntactic.**
`MM-EXEC-9a` defines `Mut` as "a field store is visible through every
alias" — but the effect walker (`TAG_E_SETF` in `walkEffects`,
`typecheck.ax:10634`, and the `__store8`/`__store64` primitive
attribution) fires on *any* call to those primitives, with no
awareness of whether the target is a parameter/global (genuinely
alias-visible) or a block the function itself just allocated and has
not yet returned (never visible to any alias the caller holds).
`strConcat`'s internal byte-writing loop is the second kind. The
compiler already computes almost exactly this distinction, one pass
later, for `MM-LIFE-2c`'s own ownership fixpoint (`inferOwnership`/
`inferFlows` in `codegen.ax`) — effect inference and ownership
inference are answering closely related questions with two unrelated
analyses, one of them (the effect walk) blind to information the other
already has.

### 2.6 Two rule identifiers are reused, and the reused pair is the
newer one

`docs/memory-model.md` §9 admits this itself: §3.5 states a second
`MM-LIFE-2e` ("`cast` degrades the evidence word") and a second
`MM-LIFE-2f` ("the typed accessor is the safe vehicle"), distinct from
§5's `MM-LIFE-2e`/`2f` (the ARC release path / cycles). Citation count
settles which is load-bearing: `MM-LIFE-2e` (release-path meaning)
is cited 17 times across `self_host/`, `stdlib/` and `tests/`; the
`cast`-degrades-evidence meaning is cited **once**, in
`docs/reference.md:1461`. `§0.1`'s own discipline — "never renamed,
never reused" — is violated today, self-admittedly, by the pair with
the smaller footprint.

### 2.7 The compiler's flagship workload validates the arena's story,
not reference counting's

`Vec`, `Map`, `Intern` and every `ASTNode` field the compiler's own
data structures use are declared `Int` (§2.1). `MM-ALLOC-20`,
`MM-LIFE-2e` and `MM-LIFE-2i` all say so directly: "no type-directed
ownership event can ever fire on it." The two headline performance
figures in the specification are the self-compile improvement
(2.93 s / 314 MiB → 1.94 s / 248 MiB) and the LSP's per-edit footprint
(840 bytes bracketed, 193,247 unbracketed). The first is a **build-
then-exit** workload — the kind an arena around the whole compile
would serve at zero per-object cost, needing no reset at all — and the
second is explicitly the arena boundary's doing "entirely," per the
document's own words. Neither figure is evidence that per-object
reference counting is pulling its weight as a *general-purpose
default* for a program shape that isn't a bounded request/message; the
compiler's own workload simply never exercises that case, because its
own containers opted out of typed tracking from the start.

---

## Phase 3 — proposals

Ordered cheapest and most certain first. Every proposal names its cost
and the gate that would hold it; every gate follows this project's own
convention of an ablation that must go red before the fix and green
after.

### P1 — Refuse `alloc`/`*mut T` outright (deletes MM-VAL-20/21's gap)

**What.** `(alloc T)` and the `*T`/`*mut T` type syntax become `AX2004`
refusals, joining `foreign`, `union`, `region`, `linear` and `consume`.
`MM-VAL-20`/`21` are withdrawn in the "superseded before landing" sense
(§0.3's first kind — nothing about this form ever shipped correctly),
closing the "appears in no column" defect §9 currently records.

**Cost — the sentence below was wrong, and this is the correction.**
It said: "A parser/checker refusal, mechanically identical to the
`linear`/`consume` refusal added 2026-08-25. No runtime, no codegen
change. The corpus population of the unsafe shape is already documented
as zero (`MM-VAL-21`'s own text)."

**The population is not zero and never was.** Measured 2026-08-31:

```
$ grep -rn '(alloc ' --include='*.ax' . | grep -v ':[0-9]*: *;'
tests/diagnostics/330-axtag-mismatch.ax:10:    (alloc Int 1)
tests/diagnostics/340-axtag-pure-io.ax:7:    (alloc Int 1)
tests/diagnostics/341-axtag-above-signature.ax:23:    (alloc Int 1)
tests/diagnostics/372-restrict-no-alloc.ax:22:  (let ((p (alloc Int 1)))
tests/diagnostics/377-restrict-witness-path.ax:67:  (let ((p (alloc Int 1)))
tests/diagnostics/377-restrict-witness-path.ax:81:  (let ((p (alloc Int 1)))
tests/fmt/syntax-zoo.ax:180,181,271                (three)
tests/fmt/syntax-zoo.expected.ax:220,221,328       (three)
tests/selfhost/730-struct-con-expr.ax:30:    (z (cast Int (alloc Int 8)))
```

Fourteen hits, and the fourteenth is the interesting one. Thirteen are
`(alloc ...)` expressions in eight corpus files, across four gates
(`check-diagnostics`, `check-fmt`, `check-restrictions`,
`check-self-host`). The last, `self_host/format.ax:3629`, is not a use
site: it is the FORMATTER's printer for the form. `axiom fmt` has its
own grammar, so refusing `alloc` in the parser leaves a printer that
still knows how to write it, and `tests/fmt/syntax-zoo.ax` — six of the
thirteen — is the fixture that would then be unformattable rather than
merely unacceptable. This is not staleness: `git grep -c '(alloc ' 6cfa571`
returns the same nine files, so the claim was already false on the
commit this document was written against. It was inherited verbatim
from `MM-VAL-21`, whose own `doc-gate:negative-exempt` comment says the
quiet part — "a population count, not an existence claim. What
falsifies it is any .ax file spelling the form ... The honest probe is
a corpus counter, which this gate does not have yet." Nobody ran one.

**And the cost is worse than the count.** `(alloc T)` is one of only two
forms that introduce `Alloc` **at the site** rather than through a call
(`self_host/typecheck.ax`'s own table: `(alloc T)`, and a `handle`
naming a resolved custom effect). `tests/diagnostics/372-restrict-no-alloc.ax`
exists to distinguish those two routes — its `direct` case is there
precisely because "`(alloc T n)` adds `Alloc` at the site rather than
through a call" — and refusing the form deletes the only cheap way to
write that case. So P1 is not the cheapest proposal here; it is a
refusal plus a fourteen-site migration plus the loss of a diagnostic
capability with no stated replacement.

**Status: NOT TAKEN, 2026-08-31**, and the reason is worth more than the
implementation would have been. Re-scope it as: (a) decide what replaces
`alloc` as the site-level `Alloc` witness, (b) migrate the fourteen
sites, (c) then refuse. The `MM-VAL-21` corpus counter the doc-gate
comment asks for should land first, so that this number is a gate rather
than a paragraph.

**Gate (once built).** A diagnostics fixture named for the rule it pins, mirroring
`495-widthless-types.ax`'s shape: assert `AX2004` on `(alloc T)` and on
a `*mut T` type position. Ablate by reverting the refusal and
confirming the measured-above behaviour returns (`#effects=Alloc`,
evaluates to 0, `check` says `OK`) — i.e. the fixture must fail against
today's compiler and pass only once the refusal lands.

### P2 — Refuse `;@axiom:owned(...)` (deletes a silent-accept AXTAG)

**What.** The `owned(...)` AXTAG key is refused at `check` time
(a new low-numbered `AX30xx`, or reuse of the unrecognized-tag
diagnostic if one exists), the same closure `linear`/`consume` already
received. `docs/reference.md`'s AXTAG table drops the row.

**Cost — there is no lookup table, and the namespace is open by an
explicit decision.** Measured 2026-08-31: the string `owned` does not
appear anywhere in `self_host/` or `stdlib/` in an AXTAG sense
(`grep -rn '\bowned\b' self_host/*.ax stdlib/*.ax` finds only
`codegen.ax`'s ownership-inference prose). `owned(...)` is not an
accepted key; it is an **unknown** key, and unknown keys are accepted on
purpose. `AX3039`'s own explain text states the policy:

> The AXTAG key namespace is OPEN on purpose: a key the compiler does
> not know is metadata, it is recorded, and nothing checks it.

and `AX3052`'s contrasts it deliberately — "the list of restrictions is
CLOSED ... deliberately unlike AX3039, which warns about a key one slip
from a known one and leaves the key namespace open." So refusing
`owned(...)` is not a table edit. It is closing one name in an
intentionally open namespace, which needs a blocklist the compiler does
not have and a reason that does not equally apply to `no_refactor`, the
other unenforced key in the same documented table.

**The defect is real and it is documentation.** `docs/reference.md`'s
*Common AXTAG Keys* table lists `owned(arena=frame)` beside `pure` and
`effect(io)` — the two keys that ARE checked — which is exactly the
"reads like a guarantee and buys silence" failure `AX3039` was written
to name, committed by the reference manual rather than by a program.
Both `(alloc T)` payloads measured on this build still check `OK`, so
§2.4's observation stands; what does not stand is its proposed remedy.

**Status: NOT TAKEN as written, 2026-08-31.** Re-scope it as a
`docs/reference.md` edit (drop the row, or move both unenforced keys to
a clearly-labelled "recorded, never checked" list), and, if a refusal is
still wanted afterwards, as a decision about whether the AXTAG key
namespace stays open at all — which is a language decision with
`agent:*` and every user's own metadata downstream of it, not a
lookup-table change.

**Gate.** A diagnostics fixture asserting the refusal on both a
well-formed (`arena=frame`) and garbage (`nonsense=whatever`) payload.
Ablate by re-accepting it and confirming both are silently accepted
(measured above on this build).

### P3 — Fix the duplicate rule identifiers  — **BUILT 2026-08-31**

**There were three, not two.** The grep this proposal asks for, run
before any edit, found `MM-ALLOC-17` defined twice as well — a **W**
rule (the implicit per-activation arena, 2026-08-14) and an **H** rule
(a trap may abort to a mark, 2026-08-25) — which §9's own admission had
never noticed. That is the argument for the gate, made by the gate
before it was written down. All three pairs moved the later,
lower-cited member: `MM-VAL-22`, `MM-VAL-23`, `MM-ALLOC-23`. The check
is `check-doc-drift.sh` section 8, floor 200, 274 definitions today;
ablated against `docs/memory-model.md` at `9116167`, it prints three
FAIL lines and exits 1.

**What.** Renumber §3.5's `MM-LIFE-2e`/`MM-LIFE-2f` (the `cast`/typed-
accessor pair, one citation each) to fresh identifiers — e.g.
`MM-VAL-22`/`MM-VAL-23`, since both are about the evidence word and
`cast`, §2's subject, not §5's lifetimes. §5's `MM-LIFE-2e`/`2f` (17
citations) keep their numbers unchanged.

**Cost.** A doc edit in `memory-model.md` (two rule headers, their own
internal self-references) plus one citation fix in
`docs/reference.md:1461`,`1468`. Zero runtime cost.

**Gate.** A new cheap check — grep every `MM-`/`ERR-`/`I` identifier
header in `memory-model.md` and `error-model.md`, assert each appears
as a rule header exactly once — added to `scripts/check-doc-drift.sh`
or as its own script. Ablate by reintroducing a duplicate header and
confirming the new check goes red; today, with no such check, this
document's own §9 admission that the duplicate exists is the only
thing catching it.

### P4 — Retire `MM-ALLOC-8`'s replaceable-allocator seam from Planned
to Refused  — **BUILT 2026-08-31**

Done as specified. `MM-ALLOC-8` is **R**, §9's Planned column is
`ALLOC-20` alone, and `MM-ALLOC-22`'s "one refusal survives" exception
went with it — that rule's **MUST NOT** is now unconditional.
`AX3026`'s explain text, which told a reader the seam was "re-decided
with the reclamation work", says the decision instead
(`tests/tools/explain.golden`).

**What.** `MM-ALLOC-8` (a program-supplied `axiom_alloc` seam) has been
**P** since before the arena was chosen as the strategy, and its own
text already says building it "would be re-decided against" the
release path arenas depend on. A pluggable global allocator would
undermine the invariants (`I1`–`I15`) the arena/counting composition
already leans on, for a benefit nobody has specified precisely. Move it
to **R**, stating why: a program that wants control over reclamation
already has it — `MM-ALLOC-22`'s three primitives — and a *second*,
independent allocator identity is a different, unscoped feature.

**Cost.** A documentation decision, zero code. Shrinks §9's Planned
column from `{ALLOC-8, ALLOC-20}` to `{ALLOC-20}` — the one genuine
prerequisite left, and the one every future strategy (this proposal's
P6 and P7 included) still needs.

**Gate.** None needed; this is a status change, not a behavioural
claim. If a future revision wants it back, it re-enters as a fresh **P**
rule with its own acceptance criteria, per §0.1.

### P5 — Trap on an invalid arena-mark reset (MM-ALLOC-16a: SHOULD → MUST)  — **BUILT 2026-08-31**

Done as specified, with one correction to the gate this section asks
for. **"Reset the same mark twice" cannot trap, and must not.** Measured
before implementing: after the first reset `@__axiom_chunk` IS the
marked chunk, so `@__axiom_arena_reset_fn` takes its equal-chunk fast
path and the unwind walk — where `%ranout` lives — is never entered.
`emitArenaHelpers`'s own comment states this as a design property ("the
cell ... sits below its own waterline: a reset never reclaims it, so
the same mark can be reset twice"). A fixture asserting a trap there
would have been asserting against the design, so
`tests/stdlib/166-arena-bad-mark.ax` asserts the **silence** instead,
beside the legal nested shape, and traps only on the inner-after-outer
shape `MM-ALLOC-16a` actually names.

The cost was A/B'd, not assumed: with the split branch
2.146/2.142/2.517/3.012 µs per reset, with the merged one
2.849/2.200 µs, two interleaving sets on a loaded machine — the
benchmark takes the equal-chunk fast path, whose emitted IR is
byte-identical either way.

**What.** In `@__axiom_arena_reset_fn` (`self_host/codegen.ax:8396`–
`8452`), branch on `%reached` specifically — not the merged `%stop` —
at the point that currently falls through unconditionally to `tail`/
`restore`. When the unwind walk exhausts the active-chunk list without
finding the marked chunk (`%ranout` true, `%reached` false — exactly
the "this mark was already reset, or an outer mark reset past it"
case), call a new trap function instead of restoring a stale position,
mirroring `emitDivTrap`/`emitOomTrap`/`emitUnhandledTrap`'s shape
(`MM-EXEC-16`): write one line to fd 2, exit with a newly reserved
status (75, the next free slot after 74). This converts `MM-ALLOC-16a`
from a program obligation ("SHOULD trap," does not) into an
implementation obligation, and makes `I8` an *enforced* invariant
rather than an argued one.

**Cost.** One branch and one call, on the reset-walk's already-slow
path (an unwind loop that only runs at all when at least one chunk was
mapped since the mark). The fast, common case — a mark reset while its
chunk is still the active one, or one hop back — is unchanged. This
**must be re-measured**, not assumed: rerun
`scripts/check-arena-reset-rate.sh` before and after and confirm the
~1.35 µs reset figure does not move outside its own noise band; if it
does, the branch placement needs to move earlier in the loop rather
than at the merge point.

**Gate.** A new fixture pairing a legal nested mark/reset (must still
succeed, unchanged behaviour) with two illegal shapes — reset an inner
mark after its outer mark's reset, and reset the same mark twice — each
asserted to exit 75 rather than continue. Ablate by reverting to the
unconditional `tail`/`restore` fallthrough and confirming the illegal
cases run to completion with a wrong answer instead of trapping (this
is directly demonstrable: the current codegen, cited above, is already
that ablated state).

### P6 — Give `Alloc`/`Mut` attribution ownership-awareness for
self-contained construction

> **PARTLY OVERTAKEN 2026-08-31.** This proposal's premise — that
> `ERR-PROP-2`'s "allocating a not-yet-shared value is invisible to
> the row" is an existing precedent to EXTEND — no longer holds: that
> precedent was withdrawn, and bare constructor application now
> contributes `Alloc`. The `Mut` half of the proposal is untouched and
> is still the interesting one; the `Alloc` half now reads as "keep
> `Alloc`, which is already what happens". Its gate paragraph below
> should be re-derived before anyone acts on it.

> **AND THE `Mut` HALF IS NOT AFFORDABLE AS PRICED — its cost
> paragraph rests on a claim that does not survive being re-read.**
> Recorded here rather than quietly corrected, for the reason this
> document already gives about P1, P2 and P7: a scoping sentence
> nobody re-ran is how a milestone gets mis-sized. Three measurements,
> all taken 2026-08-31 against the merged tree.
>
> **1. The size of the prize is real.** `axiom --diagnostic-format=ai
> symbols self_host/main.ax` lists 3,616 declarations, 2,290 of which
> carry an effect at all; **2,126 of those 2,290 carry `Mut`** (93%),
> and 1,721 are exactly `Alloc,Mut`. `Mut` discriminates almost
> nothing today, and that much of this section is correct.
>
> **2. The analysis this proposal says already exists does not compute
> the property.** The cost paragraph below says the compiler "already
> computes almost exactly this distinction … for `MM-LIFE-2c`'s own
> ownership fixpoint (`inferOwnership`/`inferFlows`)". Read them:
> `inferOwnership` stores **one bit per function** — is the RESULT
> owned, i.e. is every tail a construction rather than a borrow — and
> `inferFlows` stores **two 30-bit masks over PARAMETERS** (STASH: a
> parameter's reference is parked beyond the frame uncounted; RET: it
> may be part of a word the function answers). Neither is indexed by
> STORE SITE, and neither answers "is the address this store targets
> reachable from an alias the caller holds". So option (a), hoisting a
> cheap version of the classification into `typecheck.ax`, hoists a
> bit that does not answer the question; option (b), reordering the
> passes, arrives at the same non-answer later. **Both stated options
> are void**, and what P6 actually needs is a NEW analysis — escape or
> points-to over store targets — which is a different and larger
> thing than "a hoist".
>
> **3. `strConcat`, the headline case, is refuted by its own file.**
> `strConcat` performs no store of its own; its `Mut` arrives through
> `(memCopy (strData out) (strData a) la)`, and `memCopy` writes
> through its first parameter. So the question is whether
> `(strData out)` is private — and `strData` is a LOAD of word 1 out
> of the `Str` header, not the header itself. Whether that word is
> private depends entirely on what put it there, and `stdlib/Str.ax`
> builds both kinds through the same `strWrapOwned`:
>
> ```scheme
> (fn (strAlloc len)                     ; word 1 := a fresh buffer
>   (let ((bytes (memAlloc (+ len 1))))
>     { (__retain bytes) (strWrapOwned bytes len bytes) }))
>
> (fn (strSlice s from n) ...            ; word 1 := INTO THE CALLER'S buffer
>   (strWrapOwned (+ (strData s) from) n (strOwner s)))
> ```
>
> A rule of the form "the target is a projection of a freshly
> allocated local, so the store is invisible" is therefore **unsound**,
> and the counterexample is four hundred lines from the case the
> proposal names. Telling `strAlloc`'s header from `strSlice`'s needs
> to know what a field points AT, which is heap reachability — not a
> per-function OWNED/BORROWED result class, which is all
> `inferOwnership` has.
>
> What IS affordable, and was measured before it was believed, is the
> narrower rule the same week produced for the other open row: a value
> the walk cannot follow is a hole only where the callee's DECLARED
> POSITION could hold a function (`MM-EXEC-9a`,
> `scripts/check-effect-argpos.sh`). That one is decidable from a type
> the checker already has. `Mut`'s target is not.
>
> **Status: BLOCKED, not deferred.** Re-entering it means specifying
> the store-target escape analysis on its own terms and pricing that,
> with `strSlice`/`strAlloc` as its first acceptance test. The
> distribution above is the argument for wanting it; nothing here is
> an argument that it is cheap.

**What.** Extend `ERR-PROP-2`'s existing precedent — that allocating
a not-yet-shared value is invisible to the effect row **by decision**
— from bare constructor application to any function whose
codegen-computed result class is OWNED (`MM-LIFE-2c`'s existing
`inferOwnership` classification) and whose every `__store8`/
`__store64` site targets only its own freshly-allocated block, never a
parameter, capture, or global. Such a function is marked `Alloc` (it
still allocates) but never `Mut` (nothing it does is visible through
any alias the caller holds, which is `Mut`'s own stated definition,
`MM-EXEC-9a`). `strConcat`, `fmtInt`, `strAlloc` and `mkError` all
qualify today.

**Cost — the honest, non-trivial part.** Effect inference
(`typecheck.ax`'s `collectEffects`/`walkEffects`) currently runs as a
syntactic AST walk that has no access to codegen's ownership fixpoint
(`inferOwnership`/`inferFlows` in `codegen.ax`), which runs later and
operates over lowered/monomorphic structure. This proposal needs one
of: (a) hoisting a cheap version of the OWNED/BORROWED classification
into `typecheck.ax` so effect inference can consult it directly, or
(b) running effect inference after codegen's fixpoint and accepting the
pass-ordering change that implies for every other consumer of
`#effects=` (diagnostics, `AXTAG` checking, `axiom symbols`). Neither
is a small change; this is a multi-day design-and-measure task in its
own right, not a quick patch, and it should be scoped and reviewed
separately before being started.

**Gate.** The four probes measured in §2.5 become a permanent fixture:
`mkOk`/`mkErrLit` must carry no `#effects=`; `mkErrFmt`/`mkErrCat` must
carry `#effects=Alloc,Mut` **before** this change and `#effects=Alloc`
(no `Mut`) **after** — an ablation built into the fixture's own two
expected answers, not a separate ablation run. `scripts/check-agent-
policy.sh`'s per-primitive population golden (`__store8`, `__store64`,
`__retain` as controls) would need a new row for "a store to a
provably-private target" the same way it already has one for
`__retain`/`__release` receiving nothing.

### P7 — Uncurry closures to match the direct-call convention
(the structural proposal)

**What.** `MM-EXEC-6` already gives a syntactically saturated spine
over a *known top-level function* one flattened call, no intermediate
closure. Extend the same treatment to a `lambda`: one closure record
per **declaration** (code pointer + captures, as today), not one per
**parameter**; one evidence word/bitmap covering all of that lambda's
reference-classified parameters at once (generalizing `MM-LIFE-2d`'s
per-type-variable bit — already a bitmap in the record-form shape word
— to a second, parameter-indexed bitmap on the closure record itself);
and a call through a value whose argument count matches the callee's
static arity, in one syntactic spine, compiles to **one** indirect call
carrying every argument, exactly as `MM-EXEC-6` already does for a
direct call. Partial application — already `AX3013`-refused for named
functions — becomes a lambda-only, deliberately rare path: applying to
fewer than the full arity allocates **one** record holding what has
been supplied so far, not one per still-missing argument.

**What this deletes**, not merely improves: the entire depth-indexed
evidence-word-travel mechanism (`EV_LAMARG - d`, `curLamVar` as a
stack, `collectCapNames`'s per-level shifting) — there is no more
chain to track depth through, because a lambda's own parameters all
bind in the same record at the same time; `MM-LIFE-2c` event 5b's
"give back the curried intermediate record" subsystem — there is no
intermediate to give back. Both exist *solely* to make the curried
representation safe, and §2.2 measured that this codebase never
exercises the generality that representation buys.

**Cost — stated in full, not estimated down.** This is the largest
proposal here and is a second design pass over closures, not a
bugfix. It touches: `MM-VAL-14`/`15`/`16`/`17`/`17a`/`18`/`19` (the
whole closure representation section), `MM-LIFE-2c` event 5b and
`MM-LIFE-2d`'s evidence-word specification, `applyOneArg`,
`emitLamDef`/`emitThunkDef`, the checker's `checkLamAgainst`/
`curLamVar` machinery, and every place that currently assumes
one-argument-per-call through a value — including the FFI callback
convention (`docs/ffi.md`, `tests/ffi/demo/130-callbacks.ax`'s
`fold3`/`applyTwice` shims). It is not implementable inside this
worktree's scope (the task explicitly asks for a design, not an
allocator rewrite) and should be its own milestone with its own rule
series, reviewed on its own before a line of codegen changes.

**Scoping evidence, measured — and already overtaken, which is worth
more than the original sweep.** A corpus sweep of every `(lambda (a b
...) ...)` with two or more parameters across `self_host/`, `stdlib/`
and `tests/**` found every application fully saturated — applied to
its complete argument count in one syntactic spine, either immediately
or when a stored callback (`HttpFn`, a trait method, an FFI shim) was
later invoked. Zero instances of a partially-applied lambda being
stored, passed onward, or returned as a distinct reusable value.

**That was measured on a tree that no longer exists.** It was swept
against `6cfa571`, before this document's branch merged, and two
sibling tracks landed in the same release that move it:

  * `_` holes — explicit partial application — shipped in 0.6.0, and
    `tests/selfhost/989-hole-partial-application.ax` binds
    `(subFrom50 (sub 50 _))` to a name in a `let`. That is a
    partially-applied function STORED as a distinct reusable value:
    the exact shape the sweep found zero of.
  * traits were removed, so "a trait method" is no longer one of the
    stored-callback routes the sweep enumerated.

The conclusion the sweep supported — that this proposal costs nothing
in corpus breakage — therefore does NOT carry as written, and the
sweep must be re-run against the merged tree before P7 is scoped. It
is recorded here rather than quietly corrected because a scoping
decision resting on a stale measurement is how a milestone gets
mis-sized, and because the falsifying fixture landed the same day from
a branch that had never seen this document.

**Gate (once built).** A synthetic benchmark generalizing §2.2's
`viaLambda` probe across parameter counts 2–5 and application counts,
measuring peak RSS and wall-clock against the current curried
baseline, asserting the allocation count drops from *k* records to 1
per saturated call. A negative probe reintroducing curry-by-default
and confirming the benchmark's allocation count regresses back up.
`tests/stdlib/461-curried-closure-arg.ax` — a fixture that exists to
pin the depth-indexed mechanism this proposal deletes — must be
either retired with a stated reason (the concept it pins no longer
exists) or rewritten to assert the new flat evidence bitmap classifies
each parameter correctly; a fixture this safety-critical is never
silently dropped.

### P8 — Reframe the model's own narrative (documentation only, no code)

**What.** The specification currently tells its reclamation story as
political history: a chosen strategy (ARC), specified in detail,
withdrawn, "abandoned in place," superseded by a second strategy
(arenas) that is really a third thing layered on top of the first.
A reader has to reconstruct, from that history, the one fact that
actually matters day to day: **every value's ownership is tracked
precisely by default (the record/array forms, always on), and a
program that wants bounded memory for a request/message/iteration
boundary brackets it — a bulk "this generation is over" declaration
riding on top of the same substrate, not a competing memory model.**
Rewrite the model's own framing to lead with that sentence, and demote
the ARC-chosen-then-withdrawn narrative to what §10 already calls it —
rationale, read after the rule that matters, not instead of it.

**Cost.** Zero — a restructuring of `memory-model.md`'s presentation,
not its content. Every rule number, every measurement, every gate stays
exactly where it is; §0.1's discipline is unaffected.

**Gate.** None; this is prose, and this document's own §9.1 already
names the class of thing a gate cannot check ("a status-row rule cannot
see that a sentence is false"). The test is a reader: hand a newcomer
§0–§5 of the rewritten document and ask them to state, in one sentence,
when to reach for the arena — today that answer requires reading the
whole withdrawal history first.

---

## Summary

| # | Proposal | Deletes / Adds | Cost | Status if built |
|---|---|---|---|---|
| P1 | Refuse `alloc`/`*mut T` | deletes MM-VAL-21's gap | ~~near zero~~ **14 sites, 4 gates, and the only site-level `Alloc` witness** | **NOT TAKEN** — the zero-population premise is false and was false at `6cfa571` |
| P2 | Refuse `owned(...)` AXTAG | deletes a silent-accept | ~~near zero~~ **closes a deliberately open namespace** | **NOT TAKEN as written** — no lookup table exists; the defect is `docs/reference.md`'s table |
| P3 | Renumber the duplicate rule pair | fixes §0.1 violation | doc-only + a new gate | **BUILT** — three pairs, not two; `check-doc-drift` section 8 |
| P4 | `MM-ALLOC-8`: P → R | deletes a stale Planned row | doc-only | **BUILT** — Planned is `ALLOC-20` alone |
| P5 | Trap on invalid mark reset | turns SHOULD into MUST | one branch, measured at zero | **BUILT** — status 75, `tests/stdlib/166-arena-bad-mark.ax` |
| P6 | Ownership-aware Mut/Alloc | precision, not new rules | ~~medium, pass-order risk~~ **a new escape analysis over store targets; both stated options are void** | **BLOCKED** — `Mut` is on 2,126 of 2,290 effect-carrying rows, so the prize is real; `inferOwnership` answers a RESULT class and `inferFlows` two parameter masks, neither indexed by store site, and `strSlice`/`strAlloc` build the same `Str` header around a borrowed and a fresh buffer |
| P7 | Uncurry closures | deletes EV_LAMARG-by-depth, event 5b | large, own milestone | removes the bug class outright |
| P8 | Reframe the narrative | zero rule changes | doc-only | model reads as one thing |

P3–P5 were built on 2026-08-31. P1 and P2 were not, and the reason in
both cases is the one this document already learned from P7: a scoping
sentence that nobody re-ran. Three of this document's eight proposals
rested on a measurement that did not survive being taken again — P1's
"corpus population is zero", P2's "a lookup-table change", and P7's
"zero partially-applied lambdas" — which is a property of the document,
not of the tree, and the reader's rule for the remaining proposals
should be to re-run before believing. P6 and P8 are
where "ergonomic" and "coherent" actually live, and both are honestly
priced as harder than they look. P7 is the one structural change that
would make the model feel designed rather than inherited — and the
corpus evidence says it costs nothing to break.
