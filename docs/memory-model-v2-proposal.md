# Toward Axiom's own memory model — a design proposal

This is a design proposal, not a specification. Its rule inventory and
present-tense descriptions record the compiler at commit `6cfa571`,
not today's status.

The binding contract and the current conformance table are in
[memory-model.md](memory-model.md). The region rules now live in its
§3.6, and the current status of each obligation is in
[assurance/memory-audit.md](assurance/memory-audit.md). Nothing here
binds until a rule moves into the specification.

Phase 1 maps the status of every rule area. Phase 2 finds the seams,
where the model reads as inherited rather than designed, each backed by
a command run against the compiler. Phase 3 makes proposals, each with
its cost and the gate that would hold it.

Every number comes from `/tmp/axc-mem/axc`, built at `6cfa571` with
`./scripts/build-shared-axc.sh`. The four targeted gates,
`check-container-reclaim`, `check-closure-reclaim`,
`check-steady-state` and `check-memory-baseline`, all pass on that
build.

---

## Phase 1 — the map

### 1.1 Rule inventory, by status

From `docs/memory-model.md`, read end to end (4,125 lines at the
baseline) and cross-checked against its own §9 conformance table:

| Area | Held (H) | Planned (P) | Withdrawn (W) | Refused (R) |
|---|---|---|---|---|
| Execution (EXEC) | 1–6d, 8–13, 15–17 | — | — | 7, 14 |
| Representation (VAL) | 1–11, 14–20 | — | — | 12, 13 |
| Allocation (ALLOC) | 1–7, 8a–16b, 22 | 8, 20 | 17–19, 21 | — |
| Mutation (MUT) | 1–5 | — | — | 6 |
| Lifetimes (LIFE) | 1, 3, 4, 6, 2g | 5, 7 | 2a–2f | 2 |
| Parallelism (PAR) | 1–5 | 6 | — | — |
| Foreign (FFI) | 1–6 | — | — | — |

`MM-VAL-21` (`alloc` and `*mut T`) appears in no column. The
specification itself calls it defective: neither implemented nor
refused. Proposal P1 addresses that gap.

<a id="12-the-central-fact-two-reclamation-stories-one-strategy-one"></a>

### 1.2 The central fact: two reclamation stories, and machinery that outlived its strategy

`MM-LIFE-2a` chose automatic reference counting (ARC) as the strategy
and specified it in `MM-LIFE-2b` to `2g`. It then withdrew ARC in
favour of `MM-ALLOC-22`, which makes the arena scope the reclamation
strategy itself, rather than a bridge to one:

- A stateless request handler bracketed by
  `__axiom_arena_mark`/`reset` uses 100–313× less peak RSS than the
  same binary unscoped (`scripts/check-net.sh`).
- The LSP's per-edit footprint is 840 bytes bracketed, against
  193,247 unbracketed.

But `MM-LIFE-2a` is withdrawn in §0.3's second sense: abandoned in
place. Its machinery is all still live:

- All seven of `MM-LIFE-2c`'s ownership events emit on every build
  (`tests/stdlib/355-arc-events.ax` and its siblings).
- `MM-LIFE-2b`'s 16-byte header is on both allocation paths.
- `MM-LIFE-2d`'s evidence word and shape word hold.
- `MM-LIFE-2e`'s release path files dead blocks onto sixteen-byte size
  classes.

None of it is coming out. Removing it would need its own measurement,
and this machinery took the compiler's self-compile from 2.93 s /
314 MiB to 1.94 s / 248 MiB. The seven ownership events (§5,
`MM-LIFE-2c`):

| # | Event | Emits since |
|---|---|---|
| 1 | a call borrows its arguments (no retain) | always (no-op by design) |
| 2 | a function returns its result owned | 2026-08-21 |
| 3 | frame slots own; scope-end release of a direct construction | 2026-08-21/15 (direct-construction subset) |
| 4 | self-tail-call boundary retains/releases per jump | 2026-08-15 |
| 5 | field store retains new, releases old | 2026-08-15 |
| 5b | closure-application intermediate record given back | 2026-08-30 |
| 6 | building a block stores reference fields owned | 2026-08-15 |
| 7 | `handle` releases its evidence record at exit | 2026-08-15 |

Event 5b is the newest. It closed the closure-argument leak (commits
`07ee175` through `89003cb`), which §2.2 covers.

The arena is a separate mechanism that you bracket by hand
(`__axiom_arena_mark`, `reset` and `reset_keeping`, specified in
`MM-ALLOC-12` to `16b`). Its three primitives move the allocator's bump
pointer, and they come with three unchecked program obligations:

- `MM-ALLOC-16`: what may be read after a reset.
- `MM-ALLOC-16a`: the nesting order in which marks may be reset.
- `MM-ALLOC-16b`: a reset must not go past an evidence record's extent.

The two systems compose instead of replacing each other. An arena reset
first scrubs all 4,097 slab-class free-list heads, so that a dangling
ARC free-list head can't hand out the same storage twice after the
reset (`MM-LIFE-2e`). That runtime guard exists only because both
systems are live in the same binary. It costs 1.7–1.8% of a
per-connection budget (`scripts/check-arena-reset-rate.sh`).

### 1.3 The evidence word and the invisible-store rule

Under `MM-VAL-2`, a machine word carries no tag. So reference counting
needs a second channel to tell, at a polymorphic call site, whether an
argument typed by a type variable is a reference. That channel is
`MM-LIFE-2d`'s *evidence word*: one hidden trailing `i64` per
polymorphic function, with bit *k* set if and only if type parameter
*k* is instantiated at a reference type
(`self_host/typecheck.ax:2807`–`2835`).

A lifted lambda carries a second evidence channel for its own
parameter, `EV_LAMARG` = −2 (`typecheck.ax:845`). That witness travels
by depth: `EV_LAMARG - d` for a parameter *d* lambdas out
(`typecheck.ax:948`, `857`). A curried lambda chain nests one frame per
parameter, so the witness has to say which frame it belongs to.

`MM-LIFE-2g` is the *invisible-store rule*. A store that erases a
value's type takes a share through `__retainref`, the one primitive
whose signature is polymorphic by design. Such a store is a `cast Int` inside a
polymorphic function, and the whole implementation has exactly two:
`Mem.memSetWord` and the AST's `mkNode`. This is the sanctioned escape
from the reference model. Every other route out (`__addr`, `strData`,
`strOwner`, a raw `__store64`) is a program obligation with no check.

### 1.4 The shape word — record and array forms

Under `MM-LIFE-2d` and `2h`, header word −1 of every counted block
holds a *shape word*. It has two forms:

- **Record form** (bit 0 = 0): an inline reference bitmap over up to
  47 payload words. A wider record is refused with `AX3029`. Constructor blocks, structs, closures and evidence
  records use it: anything statically small.
- **Array form** (bit 15 set): one bit saying whether the elements are
  pointers, plus an element count. The homogeneous data buffers of
  `Vec`, `Map` and `Intern` use it, and so does `Str`'s byte buffer.
  A per-word bitmap wouldn't fit there, and shouldn't need to.

Both forms have one reader, the dead path of `@axiom_release`, and one
writer, the allocation site. There is no `memIsArray` query (§3.5,
`MM-LIFE-2h`).

---

## Phase 2 — the seams, each measured

<a id="21-you-always-pay-for-reference-counting-whether-or-not-you-use"></a>

### 2.1 You always pay for reference counting, whether or not you use the arena

This program constructs a struct and never calls the arena:

```scheme
(import Str)
(struct Pt (x : Int) (y : String))
(:: mk (-> Int Int))
(fn (mk n) { (let ((p (Pt n (strDup "hi")))) (cast Int p)) })
(fn (main) 0)
```

For `@mk`, `axiom emit-llvm` produces:

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

That is six runtime calls for a two-field struct, and it is the cheap
case. Because `MM-VAL-2`'s word is untagged, every reference-typed
position pays this, whether or not the program ever calls
`__axiom_arena_mark`.

`MM-LIFE-2a`'s own accounting prices only the interaction cost: 1.7–1.8%
of a request, from the slab-head scrub. The specification never prices
the baseline retain and release traffic of a program that never touches
the arena. Nobody chose that cost. It is left over from a withdrawn
strategy.

So a program gets neither ARC's completeness (cycles still leak,
`MM-LIFE-3`/`2f`) nor the arena's simplicity (three unchecked
primitives, §1.2) for free. It pays for the first and, if it wants
bounded memory, still has to bracket the second by hand.

This costs most where the compiler's own convention leaves things
untyped. `Vec`, `Map` and `Intern` handles are `Int` in every stdlib
signature. In `MM-ALLOC-20`'s words: "the compiler's own containers and
AST declare their handles `Int`, so no type-directed ownership event
can ever fire on them." `Int` handles are the only idiom the standard
library offers for a growable collection. A program that follows it gets no
benefit from the per-object tracking it still pays for on every struct,
closure and field store elsewhere.

<a id="22-the-evidence-word-by-depth-mechanism-is-a-live-bug-class-and"></a>

### 2.2 The evidence-word-by-depth mechanism is a live bug class, and it exists only because closures are curried

`MM-VAL-17a` says: "A multi-parameter lambda is curried into a chain of
one-parameter lambdas, each allocating its own record." Compare these
two functions:

```scheme
(:: addDirect (-> Int Int Int))
(fn (addDirect a b) (+ a b))

(:: viaLambda (-> Int Int Int))
(fn (viaLambda x y) (let ((f (lambda (a b) (+ a b)))) ((f x) y)))
```

`@addDirect` compiles to one instruction, `%.t0 = add i64 %a, %b`.
`@viaLambda` compiles to:

1. one `axiom_alloc(8)` for the outer curry frame;
2. an indirect call into `_lam_0`, which does a second
   `axiom_alloc(24)` for three words: the code pointer, the captured
   `a`, and the captured evidence word `__evwa.h`;
3. a second indirect call, into `_lam_1`;
4. an `axiom_release` on the intermediate 24-byte record.

Both `a` and `b` are `Int`, so the captured evidence word is provably
always 0 here. That is 32 bytes and two heap round-trips to do what `addDirect` does
in one add.

The depth-indexed evidence mechanism exists to make this
representation safe:

- `curLamVar` is a stack instead of a name (`typecheck.ax:2044`).
- `evClassOf` answers `EV_LAMARG - d` (`typecheck.ax:948`).
- `collectCapNames` shifts each enclosing lambda's word one level as
  it binds nested lambdas (cited in `docs/memory-model.md` §5,
  `MM-LIFE-2g`).

The bug this mechanism closed was a live use-after-free, not a leak. A
curried lambda's own parameter had no evidence word at all, so a store
inside the lambda took no share (described under `MM-LIFE-2g`; commits
`c09a198`, `89003cb`, `07ee175`). The fix is correct and gated by
`tests/stdlib/460-closure-reclaim.ax` and `461-curried-closure-arg.ax`,
both green on this build. But it is real machinery, and the curried
representation is its only reason to exist.

A corpus search finds no use of what that representation buys. Every
multi-parameter `lambda` in `self_host/`, `stdlib/` and `tests/**` is
applied at its full arity in one syntactic spine. That happens either
immediately or when a stored callback (an `HttpFn`, a trait method, an
FFI callback) is later invoked. None is partially applied and stored as
a reusable intermediate value.

`AX3013` already refuses partial application in the far more common
case, top-level named functions (`typecheck.ax:8107`, `10400`). Its
reason: "a partial application has to hold the arguments it was not
given, and a top-level function has no closure record to hold them
in." Lambdas pay for a full generality that this codebase never uses.

<a id="23-a-documented-should-trap-is-in-the-generated-code-silent"></a>

### 2.3 A documented "SHOULD trap" is, in the generated code, silent corruption with no branch that tells the cases apart

Under `MM-ALLOC-16a`, resetting an inner mark after its outer mark has
already been reset is undefined: "the implementation does not trap, and
a conforming implementation SHOULD." Here is the generated reset
helper, `@__axiom_arena_reset_fn` from `emitArenaHelpers`
(`self_host/codegen.ax:8396`–`8452`):

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

The helper computes two conditions separately:

- `%reached`: the mark's chunk is still live.
- `%ranout`: the walk fell off the active-chunk list without finding
  it, which is exactly the "already reset" case.

It then merges them into one `%stop` before the branch, so both
outcomes fall through to the same `tail` and `restore` sequence. That
sequence restores the allocator's bump, end and chunk position from
the saved mark cell unconditionally, even when the cell describes a
chunk the allocator no longer owns. So the undefined behaviour is a
concrete three-line merge, in the one function whose job is to keep
the allocator's position sound.

<a id="24-two-more-documented-but-inert-surfaces-same-class-the"></a>

### 2.4 Two more "documented but inert" surfaces, a class the project already knows how to close

`(linear T)` and `(consume e)` are refused with `AX2004`. That closed
this failure mode for them: syntax that parses but enforces nothing.
Two more instances are still open.

- **`(alloc T)` and `*mut T` (`MM-VAL-21`).** On this build:

  ```scheme
  (struct P (x : Int))
  (:: mk Int)
  (fn (mk) (cast Int (alloc P)))
  ```

  `axiom check` says `OK`, and `axiom --diagnostic-format=ai symbols`
  reports `#effects=Alloc` on `mk`. `axiom run` exits 0, having
  evaluated `(alloc P)` to the constant 0 and cast it. A form that
  allocates nothing claims the allocation effect, and the type it
  produces can't even be named in a signature.

- **`;@axiom:owned(arena=frame)`, left over from `MM-LIFE-7`.** On this
  build:

  ```scheme
  ;@axiom:owned(arena=frame)
  (fn (leaky x) x)
  ;@axiom:owned(nonsense=whatever)
  (fn (leaky2 x) x)
  ```

  Both check `OK`. The tag doesn't even validate its own advertised
  vocabulary (`arena=frame`): it accepts any payload silently.
  `docs/reference.md` already documents it as "accepted and
  unenforced". But a reader who trusts the syntax has no way to learn
  that from the language itself. That is the same reader
  `MM-LIFE-7`'s `linear`/`consume` refusal was written to protect.

<a id="25-the-effect-systems-constructors-are-invisible-decision-is"></a>

### 2.5 The effect system's "constructors are invisible" decision is coherent, and it misled its own author

> **Superseded.** The decision this section analyses has been
> reversed. A `data` or `struct` constructor of arity >= 1 now
> contributes `Alloc` at the application site (`typecheck.ax`,
> `ctorAllocArity`). It changed because `restrict(no-alloc)` reads the
> effect row: against a row built to omit allocation, it could not
> refuse a body whose only act was to allocate. `MM-EXEC-9a` now lists the row as
> CLOSED with its measured cost (123 of 3,725 rows, seven false
> `no-alloc` claims), and `ERR-PROP-2` was amended to match.
>
> The four probes below still measure what they measured, which is why
> this section stays. Their expected answers have moved: `mkOk` and
> `mkErrLit` now report `#effects=Alloc`, not nothing. The section's
> conclusion still holds: the cost the commit blamed on `Ok`/`Err` was
> really `strConcat`'s.

`ERR-PROP-2` and `MM-EXEC-9a`'s table state a decision: applying a
`data` or `struct` constructor adds nothing to the inferred effect row,
even though it allocates. `walkEffectsSpine`
(`self_host/typecheck.ax:10927`–`10986`) implements exactly that.
`findFnEnt` answers 0 for a constructor head, as it does for `cast`, so
no effect is added and no "unresolved call" mark fires either.

The baseline commit, `6cfa571` ("A short write stopped looking like a
complete one, and the Result migration's blocker is the effect row"),
measured a wider row. Porting `sysWriteAllFd` to `(Result Int Error)`
moved its row from `IO` to `IO, Alloc, Mut`, and the commit blamed that
on "`Ok`/`Err` allocate". Narrowing probes against this build isolate
the real mechanism:

```scheme
(fn (mkOk n) (Ok n))                                              ; no #effects=
(fn (mkErrLit n) (Err (mkError n "fixed literal")))                ; no #effects=
(fn (mkErrFmt n) (Err (mkError n (strConcat "errno " (fmtInt n)))))  ; #effects=Alloc,Mut
(fn (mkErrCat n) (Err (mkError n (strConcat "op: errno " ""))))      ; #effects=Alloc,Mut, even both operands literal
```

`Ok`, `Err` and `mkError` (itself a plain struct constructor) are
exactly as effect-free as the decision says. The cost comes from
`strConcat` alone. It fires even when concatenating two string
literals, with no `fmtInt` involved.

So the real finding is narrower than the commit's. Any
`Result`-returning wrapper whose `Err` arm explains the failure with a
computed message, which is what error messages are for, pays
`Alloc, Mut`. Such a wrapper:

- can't carry a `pure` or `IO`-only claim;
- can't sit inside a `handle` whose list is checked exhaustive against
  a narrower row (`AX3011`);
- can't keep an `AXTAG` claim that predates the port.

A canned literal message costs nothing. The commit's author,
mid-migration, blamed the wrong AST node. That mistake is itself
evidence that the mechanism, though correctly implemented and decided,
is hard to read from outside.

This also shows that `Mut` is attributed purely by syntax.
`MM-EXEC-9a` defines `Mut` as "a field store is visible through every
alias". But the effect walker fires on any call to the store
primitives, through `TAG_E_SETF` in `walkEffects` (`typecheck.ax:10634`)
and the `__store8`/`__store64` attribution. It doesn't know whether the
target is a parameter or global, which really is visible through
aliases, or a block the function just allocated and hasn't returned
yet, which no alias the caller holds can see. `strConcat`'s internal
byte-writing loop is the second kind.

The compiler already computes almost exactly this distinction one pass
later, for `MM-LIFE-2c`'s ownership fixpoint (`inferOwnership` and
`inferFlows` in `codegen.ax`). Effect inference and ownership inference
answer closely related questions with two unrelated analyses, and the
effect walk can't see what the other already knows.

<a id="26-two-rule-identifiers-are-reused-and-the-reused-pair-is-the"></a>

### 2.6 Two rule identifiers are reused, and the reused pair is the newer one

`docs/memory-model.md` §9 records this itself. §3.5 states a second
`MM-LIFE-2e` ("`cast` degrades the evidence word") and a second
`MM-LIFE-2f` ("the typed accessor is the safe vehicle"). These differ
from §5's `MM-LIFE-2e` and `2f`, the ARC release path and cycles.

Citation counts show which meaning carries weight. The release-path
`MM-LIFE-2e` is cited 17 times across `self_host/`, `stdlib/` and
`tests/`. The `cast`-degrades-evidence meaning is cited once, in
`docs/reference.md:1461`. So the pair with the smaller footprint breaks
§0.1's rule that identifiers are "never renamed, never reused", and the
specification says so.

<a id="27-the-compilers-flagship-workload-validates-the-arenas-story"></a>

### 2.7 The compiler's flagship workload validates the arena's story, not reference counting's

`Vec`, `Map`, `Intern` and every `ASTNode` field in the compiler's own
data structures are declared `Int` (§2.1). `MM-ALLOC-20`, `MM-LIFE-2e`
and `MM-LIFE-2i` all say so directly: "no type-directed ownership event
can ever fire on it."

The specification's two headline performance figures are:

- the self-compile improvement, from 2.93 s / 314 MiB to 1.94 s /
  248 MiB;
- the LSP's per-edit footprint, 840 bytes bracketed against 193,247
  unbracketed.

The first is a build-then-exit workload. An arena around the whole
compile would serve it at no per-object cost, with no reset at all. The
second, in the specification's own words, is "entirely" the arena
boundary's doing.

Neither figure shows per-object reference counting earning its place as
a general-purpose default for a program that isn't a bounded request or
message. The compiler's own workload never exercises that case, because
its own containers opted out of typed tracking from the start.

---

## Phase 3 — proposals

The proposals are ordered cheapest and most certain first. Each one
names its cost and the gate that would hold it. Every gate follows the
project's convention: an ablation that fails before the fix and passes
after.

### P1 — Refuse `alloc`/`*mut T` outright (deletes MM-VAL-20/21's gap)

**Status: not taken.** The proposal assumed nothing in the tree uses
the form. Fourteen sites would need migrating.

**What.** `(alloc T)` and the `*T`/`*mut T` type syntax would become
`AX2004` refusals, like `foreign`, `union`, `region`, `linear` and
`consume`. `MM-VAL-20` and `MM-VAL-21` would be withdrawn as
"superseded before landing", §0.3's first kind, because this form never
shipped correctly. That would close the "appears in no column" defect
that §9 records.

**Cost.** The first estimate called this a parser and checker refusal,
mechanically identical to the `linear`/`consume` refusal, with no
runtime or codegen change. It gave the corpus population of the unsafe
shape as zero, taking that figure from `MM-VAL-21`'s own text.

The population is not zero, and never was:

```text
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

Thirteen of the fourteen hits are `(alloc ...)` expressions in eight
corpus files, across four gates: `check-diagnostics`, `check-fmt`,
`check-restrictions` and `check-self-host`. The fourteenth is not a use
site. It is the formatter's printer for the form, in
`self_host/format.ax`. `axiom fmt` has its own grammar, so refusing
`alloc` in the parser leaves a printer that can still write it. The
`tests/fmt/syntax-zoo.ax` fixture and its expected output hold six of
the thirteen, and would become unformattable as well as unacceptable.

The count was already wrong on the commit this document was written
against: `git grep -c '(alloc ' 6cfa571` returns the same nine files.
The claim came verbatim from `MM-VAL-21`. That rule's
`doc-gate:negative-exempt` comment calls it "a population count, not an
existence claim". It says any `.ax` file spelling the form falsifies it,
and that the right probe is "a corpus counter, which this gate does not
have yet". Nobody ran one.

The cost is also larger than the count. `(alloc T)` is one of only two
forms that introduce `Alloc` at the site rather than through a call.
The other is a `handle` naming a resolved custom effect, per the table
in `self_host/typecheck.ax`. `tests/diagnostics/372-restrict-no-alloc.ax`
exists to tell those two routes apart. Its `direct` case is there
because "`(alloc T n)` adds `Alloc` at the site rather than through a
call", and refusing the form removes the only cheap way to write that
case. So P1 is not the cheapest proposal here. It is a refusal, a
fourteen-site migration, and the loss of a diagnostic capability with no
stated replacement.

**Rescoped plan.**

1. Decide what replaces `alloc` as the site-level `Alloc` witness.
2. Migrate the fourteen sites.
3. Refuse the form.

Land the `MM-VAL-21` corpus counter that the doc-gate comment asks for
first, so this number is held by a gate rather than a paragraph.

**Gate (once built).** A diagnostics fixture named for the rule it
pins, shaped like `495-widthless-types.ax`, asserting `AX2004` on
`(alloc T)` and on a `*mut T` type position. To ablate, revert the
refusal and confirm today's behaviour returns: `#effects=Alloc`, the
form evaluates to 0, and `check` says `OK`. The fixture must fail
against today's compiler and pass only once the refusal lands.

### P2 — Refuse `;@axiom:owned(...)` (deletes a silent-accept AXTAG)

**Status: not taken as written.** There is no lookup table to edit, and
the real defect is in `docs/reference.md`.

**What.** The `owned(...)` AXTAG key would be refused at `check` time,
with a new low-numbered `AX30xx`, or the unrecognised-tag diagnostic if
one exists. This is the same closure `linear` and `consume` received.
`docs/reference.md`'s AXTAG table would drop the row.

**Cost.** There is no lookup table, and the key namespace is open by an
explicit decision. The string `owned` appears nowhere in `self_host/` or
`stdlib/` in an AXTAG sense: `grep -rn '\bowned\b' self_host/*.ax
stdlib/*.ax` finds only prose, such as the ownership-inference comments
in `codegen.ax`.
So `owned(...)` is not an accepted key. It is an unknown key, and the
compiler accepts unknown keys by design. `AX3039`'s explain text states
the policy:

> The AXTAG key namespace is OPEN on purpose: a key the compiler does
> not know is metadata, it is recorded, and nothing checks it.

`AX3052`'s explain text draws the contrast: the list of restrictions is
closed, unlike `AX3039`, which warns about a key one slip from a known
one and leaves the key namespace open. Refusing
`owned(...)` would close one name in an intentionally open namespace.
That needs a blocklist the compiler doesn't have. It also needs a reason
that doesn't apply equally to `no_refactor`, the other unenforced key
in the same table.

**The real defect.** `docs/reference.md`'s *Common AXTAG Keys* table
lists `owned(arena=frame)` beside `pure` and `effect(io)`, the two keys
that are checked. That is the failure `AX3039` exists to name, a tag
that reads like a guarantee and buys silence, committed by the reference
manual rather than by a program. On this build, both payloads,
`arena=frame` and `nonsense=whatever`, still check `OK`. So §2.4's
observation stands, but its proposed remedy does not.

**Rescoped plan.** Edit `docs/reference.md`: drop the row, or move both
unenforced keys to a clearly labelled "recorded, never checked" list.
If a refusal is still wanted after that, it becomes a decision about
whether the AXTAG key namespace stays open at all. That is a language
decision, with `agent:*` keys and every user's own metadata downstream
of it, not a lookup-table change.

**Gate.** A diagnostics fixture asserting the refusal on a well-formed
payload (`arena=frame`) and on a garbage one (`nonsense=whatever`). To
ablate, accept the key again and confirm both pass silently, as they do
on this build.

<a id="p3--fix-the-duplicate-rule-identifiers---built-2026-08-31"></a>
### P3 — Fix the duplicate rule identifiers

**Status: built.** There were three duplicate pairs, not two.

Running the grep this proposal asks for, before any edit, found
`MM-ALLOC-17` defined twice as well, which §9 had not noticed. One was a
**W** rule (the implicit per-activation arena) and the other an **H**
rule (a trap may abort to a mark). In each of the three pairs, the later
and less-cited rule moved, to `MM-VAL-22`, `MM-VAL-23` and
`MM-ALLOC-23`. The check is section 8 of `scripts/check-doc-drift.sh`,
with a floor of 200 definitions; it counted 274 when it was built.
Ablated against `docs/memory-model.md` at `9116167`, it prints three
FAIL lines and exits 1.

**What.** Renumber §3.5's `MM-LIFE-2e`/`MM-LIFE-2f`, the
`cast`/typed-accessor pair with one citation each, to fresh identifiers
such as `MM-VAL-22`/`MM-VAL-23`. Both concern the evidence word and
`cast`, which is §2's subject rather than §5's lifetimes. §5's
`MM-LIFE-2e`/`2f`, with 17 citations, keep their numbers.

**Cost.** A documentation edit in `memory-model.md` (two rule headers
and their own self-references), plus two citation fixes in
`docs/reference.md`. No runtime cost.

**Gate.** A cheap check that greps every `MM-`, `ERR-` and `I`
identifier header in `memory-model.md` and `error-model.md`, and asserts
each is defined as a rule header exactly once. It can live in
`scripts/check-doc-drift.sh` or in its own script. To ablate,
reintroduce a duplicate header and confirm the check fails. Without it,
the only thing catching a duplicate is a sentence in §9.

<a id="p4--retire-mm-alloc-8s-replaceable-allocator-seam-from-planned"></a>
### P4 — Retire `MM-ALLOC-8`'s replaceable-allocator seam from Planned to Refused

**Status: built as specified.** `MM-ALLOC-8` is **R**, and §9's Planned
column is `ALLOC-20` alone. `MM-ALLOC-22`'s "one refusal survives"
exception went with it, so that rule's **MUST NOT** is now
unconditional. `AX3026`'s explain text now states the decision, instead
of saying the seam would be "re-decided with the reclamation work"
(`tests/tools/explain.golden`).

**What.** `MM-ALLOC-8`, a program-supplied `axiom_alloc` seam, had been
**P** since before arenas were chosen as the strategy. Its own text
said building it "would be re-decided against" the release path that
arenas depend on. A pluggable global allocator would undermine the
invariants `I1`–`I15` that the arena and counting composition relies
on, for a benefit nobody has specified precisely. Move it to **R**, and say why.
A program that wants control over reclamation already has it, through
`MM-ALLOC-22`'s three primitives. A second, independent allocator
identity is a different, unscoped feature.

**Cost.** A documentation decision, with no code. §9's Planned column
shrinks from `{ALLOC-8, ALLOC-20}` to `{ALLOC-20}`. That is the one real
prerequisite left, and every future strategy still needs it, P6 and P7
included.

**Gate.** None needed, because this is a status change rather than a
claim about behaviour. If a future revision wants the seam back, it
re-enters as a fresh **P** rule with its own acceptance criteria, per
§0.1.

<a id="p5--trap-on-an-invalid-arena-mark-reset-mm-alloc-16a-should--must---built-2026-08-31"></a>
### P5 — Trap on an invalid arena-mark reset (MM-ALLOC-16a: SHOULD → MUST)

**Status: built as specified**, with one correction to the gate:
resetting the same mark twice cannot trap, and must not.

This was measured before implementing. After the first reset,
`@__axiom_chunk` is the marked chunk. So `@__axiom_arena_reset_fn` takes
its equal-chunk fast path and never enters the unwind walk, where
`%ranout` lives. The comment on `emitArenaHelpers` states this as a
design property: the mark's cell sits below its own waterline, so "a
reset never reclaims it, so the same mark can be reset twice". A
fixture asserting a trap there would contradict the design. So
`tests/stdlib/166-arena-bad-mark.ax` asserts that a double reset is
silent, alongside the legal nested shape. It traps only on the shape
`MM-ALLOC-16a` actually names: an inner mark reset after its outer
mark.

The cost was measured with an A/B comparison rather than assumed. With
the split branch, a reset took 2.146, 2.142, 2.517 and 3.012 µs. With
the merged branch it took 2.849 and 2.200 µs. These were two
interleaved sets on a loaded machine. The benchmark takes the
equal-chunk fast path, whose emitted IR is byte-identical either way.

**What.** In `@__axiom_arena_reset_fn` (`self_host/codegen.ax`), branch
on `%reached` specifically, not the merged `%stop`, at the point that
fell through unconditionally to `tail`/`restore`. Suppose the unwind
walk runs out of active chunks without finding the marked one
(`%ranout` true, `%reached` false). Then this mark was already reset, or
an outer mark reset past it. In that case, call a new trap function
instead of restoring a stale position. It mirrors the shape of
`emitDivTrap`, `emitOomTrap` and `emitUnhandledTrap` (`MM-EXEC-16`): it
writes one line to fd 2 and exits with a newly reserved status, 75, the
next free slot after 74.

This turns `MM-ALLOC-16a` from a program obligation ("SHOULD trap",
which it didn't) into an implementation obligation. It also makes `I8`
an enforced invariant rather than an argued one.

**Cost.** One branch and one call, on the reset walk's already-slow
path. That unwind loop only runs when at least one chunk was mapped
since the mark. The fast, common case is unchanged: a mark reset while
its chunk is still active, or one hop back. Re-measure rather than
assume. Run `scripts/check-arena-reset-rate.sh` before and after, and
confirm the ~1.35 µs reset figure stays inside its noise band. If it
moves, place the branch earlier in the loop rather than at the merge
point.

**Gate.** A new fixture pairing a legal nested mark/reset, which must
still succeed, with two illegal shapes, each asserted to exit 75. The
first resets an inner mark after its outer mark's reset. The second
resets the same mark twice, and as built it asserts silence instead
(see above). To ablate, revert to the unconditional `tail`/`restore`
fallthrough and confirm the illegal cases run to completion with a
wrong answer. The codegen before this change is already that ablated
state.

<a id="p6--give-allocmut-attribution-ownership-awareness-for"></a>
### P6 — Give `Alloc`/`Mut` attribution ownership-awareness for self-contained construction

**Status: blocked, not deferred.** The `Alloc` half has been overtaken,
and the `Mut` half needs an analysis that doesn't exist yet.

The `Alloc` half extended a precedent in `ERR-PROP-2`: that allocating a
not-yet-shared value is invisible to the effect row. That precedent was
withdrawn, and bare constructor application now contributes `Alloc`. So
the `Alloc` half now amounts to "keep `Alloc`", which is what already
happens. Re-derive the gate paragraph below before acting on it.

The `Mut` half is not affordable at the price given, because its cost
paragraph rests on a claim that fails on a second reading. Three
measurements against the merged tree show why.

1. **The prize is real.** `axiom --diagnostic-format=ai symbols
   self_host/main.ax` lists 3,616 declarations. Of these, 2,290 carry an
   effect, and 2,126 of those carry `Mut` (93%). Exactly 1,721 carry
   `Alloc,Mut` and nothing else. Today `Mut` tells almost nothing apart.
2. **The existing analysis does not compute the property.** The
   proposal assumed the compiler already computes almost exactly this
   distinction, in `MM-LIFE-2c`'s ownership fixpoint
   (`inferOwnership`/`inferFlows`). It doesn't.

   `inferOwnership` stores one bit per function: whether the result is
   owned, meaning every tail is a construction rather than a borrow.
   `inferFlows` stores two masks over parameters. The *stash*
   mask marks a parameter whose reference is parked beyond the frame,
   uncounted. The *ret* mask marks one that may be part of a word the
   function returns.

   Neither is indexed by store site, and neither answers "is the address
   this store targets reachable from an alias the caller holds?".
   Option (a) below hoists a bit that doesn't answer the question, and
   option (b) reaches the same non-answer later. Both options are void.
   P6 needs a new analysis, escape or points-to over store targets,
   which is larger than a hoist.
3. **`strConcat`, the headline case, is refuted by its own file.**
   `strConcat` does no store of its own. Its `Mut` comes from
   `(memCopy (strData out) (strData a) la)`, and `memCopy` writes
   through its first parameter. So the question is whether
   `(strData out)` is private. `strData` loads word 1 of the `Str`
   header; it is not the header itself. Whether that word is private
   depends on what put it there. `stdlib/Str.ax` builds both kinds
   through the same `strWrapOwned` (abridged):

   ```scheme
   (fn (strAlloc len)                     ; word 1 := a fresh buffer
     (let ((bytes (memAlloc (+ len 1))))
       { (__retain bytes) (strWrapOwned bytes len bytes) }))

   (fn (strSlice s start count) ...       ; word 1 := into the caller's buffer
     (strWrapOwned (+ (strData s) from) n owner))
   ```

   A rule of the form "the target is a projection of a freshly allocated
   local, so the store is invisible" is therefore unsound, and the
   counterexample is in the same file as the case the proposal names.
   Telling `strAlloc`'s header from `strSlice`'s requires knowing what a
   field points at. That is heap reachability, not the per-function
   owned/borrowed result class, which is all `inferOwnership` has.

A narrower rule is affordable, and was measured before it was adopted.
A value the effect walk cannot follow is a hole only where the callee's
declared position could hold a function (`MM-EXEC-9a`,
`scripts/check-effect-argpos.sh`). That is decidable from a type the
checker already has. `Mut`'s target is not.

To reopen P6, specify the store-target escape analysis on its own terms
and price it, with `strSlice`/`strAlloc` as its first acceptance test.
The distribution above shows why it's worth wanting. Nothing here shows
it is cheap. The proposal as first written follows.

**What.** Extend `ERR-PROP-2`'s precedent, that allocating a
not-yet-shared value is invisible to the effect row by decision, beyond
bare constructor application. A function would qualify when its
codegen-computed result class is owned (`MM-LIFE-2c`'s `inferOwnership`
classification), and every `__store8`/`__store64` site in it targets
only its own freshly allocated block, never a parameter, capture or
global. Such a function is marked `Alloc`, because it still allocates,
but never `Mut`. Nothing it does is visible through any alias the
caller holds, which is `Mut`'s own definition (`MM-EXEC-9a`). The
proposal named `strConcat`, `fmtInt`, `strAlloc` and `mkError` as
qualifying.

**Cost.** Effect inference (`collectEffects`/`walkEffects` in
`typecheck.ax`) is a syntactic AST walk. It has no access to codegen's
ownership fixpoint (`inferOwnership`/`inferFlows` in `codegen.ax`),
which runs later over lowered, monomorphic structure. The proposal needs
one of two changes:

- (a) hoist a cheap version of the owned/borrowed classification into
  `typecheck.ax`, so effect inference can consult it directly;
- (b) run effect inference after codegen's fixpoint, and accept the
  pass-ordering change for every other consumer of `#effects=`:
  diagnostics, `AXTAG` checking and `axiom symbols`.

Neither is small. This is a multi-day design-and-measure task, to be
scoped and reviewed on its own before work starts.

**Gate.** The four probes from §2.5 become a permanent fixture. `mkOk`
and `mkErrLit` must carry no `#effects=`. `mkErrFmt` and `mkErrCat` must
carry `#effects=Alloc,Mut` before this change, and `#effects=Alloc`
(no `Mut`) after. The fixture's two expected answers are the ablation,
so no separate ablation run is needed. The per-primitive population
golden in `scripts/check-agent-policy.sh` uses `__store8`, `__store64`
and `__retain` as controls. It would need a new row for "a store to a
provably private target", as it already has one for
`__retain`/`__release` receiving nothing.

### P7 — Uncurry closures to match the direct-call convention

This is the structural proposal. Its scoping sweep is stale and must be
re-run before P7 is scoped (see *Scoping evidence* below).

**What.** `MM-EXEC-6` already compiles a syntactically saturated spine
over a known top-level function to one flattened call, with no
intermediate closure. Give a `lambda` the same treatment:

- One closure record per declaration (code pointer plus captures, as
  today), not one per parameter.
- One evidence word or bitmap covering all of the lambda's
  reference-classified parameters at once. This generalises
  `MM-LIFE-2d`'s per-type-variable bit, which is already a bitmap in
  the record-form shape word, to a second, parameter-indexed bitmap on
  the closure record itself.
- A call through a value, in one syntactic spine, whose argument count
  matches the callee's static arity, compiles to one indirect call
  carrying every argument. `MM-EXEC-6` already does this for a direct
  call.

Partial application is already refused with `AX3013` for named
functions. It would become a lambda-only path, and a rare one. Applying
fewer than the full arity allocates one record holding the arguments
supplied so far, not one per missing argument.

**What this deletes.** Two subsystems exist only to make the curried
representation safe:

- the depth-indexed evidence-word mechanism (`EV_LAMARG - d`,
  `curLamVar` as a stack, `collectCapNames`'s per-level shifting). When
  all of a lambda's parameters bind in the same record at the same
  time, there is no chain to track depth through;
- `MM-LIFE-2c` event 5b, which gives back the curried intermediate
  record. There would be no intermediate to give back.

§2.2 measured that this codebase never uses the generality the curried
representation buys.

**Cost.** This is the largest proposal here: a second design pass over
closures, not a bug fix. It touches:

- `MM-VAL-14`/`15`/`16`/`17`/`17a`/`18`/`19`, the whole closure
  representation section;
- `MM-LIFE-2c` event 5b and `MM-LIFE-2d`'s evidence-word specification;
- `applyOneArg`, `emitLamDef`/`emitThunkDef`, and the checker's
  `checkLamAgainst`/`curLamVar` machinery;
- every place that assumes one argument per call through a value,
  including the FFI callback convention (`docs/ffi.md`, and the
  `fold3`/`applyTwice` shims in `tests/ffi/demo/130-callbacks.ax`).

It was outside the scope of the worktree this proposal came from, whose
task asked for a design, not an allocator rewrite. It should be its own
milestone with its own rule series, reviewed before any codegen
changes.

**Scoping evidence, now stale.** A corpus sweep covered every
`(lambda (a b ...) ...)` with two or more parameters, across
`self_host/`, `stdlib/` and `tests/**`. Every application it found was
fully saturated: applied to its complete argument count in one
syntactic spine. That happened either immediately or when a stored
callback (`HttpFn`, a trait method, an FFI shim) was later invoked. The
sweep found no partially applied lambda stored, passed on or returned as
a reusable value.

That sweep ran against `6cfa571`, before this document's branch merged.
Two changes that landed in the same release move it:

- `_` holes, for explicit partial application, shipped in 0.6.0.
  `tests/selfhost/989-hole-partial-application.ax` binds
  `(subFrom50 (sub 50 _))` to a name in a `let`. That is a partially
  applied function stored as a reusable value, the exact shape the
  sweep found none of.
- Traits were removed, so a trait method is no longer one of the
  stored-callback routes the sweep listed.

So the sweep's conclusion, that this proposal breaks nothing in the
corpus, doesn't hold as written. Re-run the sweep against the merged
tree before scoping P7.

**Gate (once built).** A synthetic benchmark that generalises §2.2's
`viaLambda` probe across parameter counts 2 to 5 and across application
counts. It measures peak RSS and wall-clock time against the current
curried baseline. It asserts that the allocation count per saturated
call drops from *k* records to 1. A negative probe reintroduces
curry-by-default and confirms the allocation count goes back up.

`tests/stdlib/461-curried-closure-arg.ax` exists to pin the
depth-indexed mechanism this proposal deletes. Either retire it with a
stated reason (the concept it pins no longer exists), or rewrite it to
assert that the new flat evidence bitmap classifies each parameter
correctly. A fixture this safety-critical is never dropped silently.

### P8 — Reframe the model's own narrative (documentation only, no code)

**What.** The specification tells its reclamation story as history. A
strategy (ARC) was chosen, specified in detail, withdrawn and "abandoned
in place". A second strategy (arenas) superseded it, but it is really a
third thing layered on top of the first. From that history, a reader
has to reconstruct the one fact that matters day to day:

> Every value's ownership is tracked precisely by default (the record
> and array forms, always on). A program that wants bounded memory for
> a request, message or iteration boundary brackets it. That is a bulk
> "this generation is over" declaration on top of the same substrate,
> not a competing memory model.

Rewrite the model's framing to lead with that. Demote the
ARC-chosen-then-withdrawn story to what §10 already calls it: rationale,
read after the rule that matters rather than instead of it.

**Cost.** Nothing beyond the writing. It changes how `memory-model.md`
presents its content, not the content. Every rule number, measurement
and gate stays where it is, and §0.1's discipline is unaffected.

**Gate.** None, because this is prose. §9.1 already names this class of
thing a gate can't check: "a status-row rule cannot see that a sentence
is false". The test is a reader. Give a newcomer §0 to §5 of the
rewritten document, and ask them to say in one sentence when to reach
for the arena. Today, answering that means reading the whole withdrawal
history first.

---

## Summary

| # | Proposal | Deletes or adds | Cost | Status, or result if built |
|---|---|---|---|---|
| P1 | Refuse `alloc`/`*mut T` | deletes MM-VAL-21's gap | ~~near zero~~ 14 sites, 4 gates, and the only site-level `Alloc` witness | **Not taken**, 2026-08-31. The zero-population premise is false, and was false at `6cfa571` |
| P2 | Refuse `owned(...)` AXTAG | deletes a silent accept | ~~near zero~~ closes an intentionally open namespace | **Not taken as written**, 2026-08-31. No lookup table exists; the defect is `docs/reference.md`'s table |
| P3 | Renumber the duplicate rule pair | fixes a §0.1 violation | doc-only, plus a new gate | **Built**, 2026-08-31. Three pairs, not two; `check-doc-drift` section 8 |
| P4 | `MM-ALLOC-8`: P → R | deletes a stale Planned row | doc-only | **Built**, 2026-08-31. Planned is `ALLOC-20` alone |
| P5 | Trap on invalid mark reset | turns SHOULD into MUST | one branch, measured at zero | **Built**, 2026-08-31. Status 75, `tests/stdlib/166-arena-bad-mark.ax` |
| P6 | Ownership-aware `Mut`/`Alloc` | precision, not new rules | ~~medium, pass-order risk~~ a new escape analysis over store targets; both stated options are void | **Blocked**, 2026-08-31. `Mut` is on 2,126 of 2,290 effect-carrying rows, so the prize is real. But `inferOwnership` answers a result class and `inferFlows` two parameter masks, neither indexed by store site. `strSlice` and `strAlloc` build the same `Str` header around a borrowed and a fresh buffer |
| P7 | Uncurry closures | deletes EV_LAMARG-by-depth, event 5b | large, own milestone | If built, removes the bug class outright |
| P8 | Reframe the narrative | zero rule changes | doc-only | If built, the model reads as one thing |

P3 to P5 are built. P1 and P2 are not, for the reason P7 also shows: a
scoping sentence that nobody re-ran. Three of the eight proposals rested
on a measurement that didn't survive being taken again. They are P1's
"corpus population is zero", P2's "a lookup-table change" and P7's
"zero partially-applied lambdas". That is a property of this document,
not of the tree. For the remaining proposals, re-run the measurement
before you believe it.

P6 and P8 are where ergonomics and coherence live, and both are priced
as harder than they look. P7 is the one structural change that would
make the model feel designed rather than inherited. Its corpus sweep
said it breaks nothing, but that sweep must be re-run first.
