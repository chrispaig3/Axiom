# Parameterised containers, and what `Vec a` actually costs

`for` cannot become a language keyword covering both a range and a
container until a container has an element type. `Vec` does not: it is
an `Int` handle, and an element is read through `vecGetStr` or
`vecGetWord` depending on what it holds. That is why `stdlib/Html.ax`
carries **two** loop macros for one idea, and why a keyword written
today would be as type-specific as those macros — the problem would
move from the macro layer into the code generator, not go away.

The asymmetry is already in the signatures:

```
(pub :: vecPush (-> Int a Int))     ; the element going IN is polymorphic
(pub :: vecGet  (-> Int Int Int))   ; the element coming OUT is an Int
(pub :: vecGetStr (-> Int Int String))
```

`vecPush` takes an `a`. Nothing ties that `a` to what `vecGet` answers,
because there is no `Vec a` to carry it. **That is the whole of the
generics problem.**

> **Status, 2026-09-03.** The paragraph above is the framing this
> document was written under and is kept as it was. `Vec` carries its
> element type (§5 item 5, `68f145b`), and **`for` is a keyword** —
> §5 item 6, the last item on the list, `tests/stdlib/466-for-loop.ax`.
> Nothing on the list remains; §7 says what landed and what did not.

## 1. `Vec` is a type now

`Vec` is seeded in `typecheck.ax` beside `Option`: a `DataEnt` with
**no constructors** — abstract and parameterised. A `Vec` is made by
`vecNew` and read by `vecGet`, never matched, so there is nothing for
a pattern to name. `(Vec a)` is a writable type; before this it was
`AX3002 undefined type`.

**The runtime shape does not move.** A `Vec` is the handle it always
was, one word, allocated by `vecNew`. This is a type-level change, and
that separability is the point: it can land before the migration that
uses it, and `fldClass` keeps answering for `Vec` exactly what it
answered for the `Int` it replaces.

## 2. `AX3040` had to narrow, and it was wrong as written

`(pub :: vecNew (Vec a))` drew **`AX3040` result-only-tyvar**: "the
caller chooses the type and a `cast` fabricates the value."

It does not. `(-> Int (Vec a))` returns a **`Vec`**, not an `a`, and an
empty container holds no value of type `a` for anything to have
fabricated. The rule's own sentence says "returns type variable `a`",
and that is now what it checks: only a **bare** result variable.
`(-> Int a)` still fires; a variable nested under a type constructor
does not.

`None : (Option a)` has had exactly this shape since `Option` was
seeded — it was never refused only because a builtin constructor never
passes through the check. Before the narrowing, **every polymorphic
empty constructor was refused**, so no generic container could declare
the one function it cannot do without.
`tests/diagnostics/347-result-only-tyvar.ax` carries both arms: the
bare case still refused, the nested case silent.

**THE NARROWING IS RIGHT AND ITS ARGUMENT IS INCOMPLETE**, measured in
§4d. "An empty container holds no value of type `a` for anything to
have fabricated" is true at the moment of construction, and it stops
being the whole story one line later: the caller still CHOOSES `a`, and
then mutates the container at that choice. Where nothing pins the
choice — an un-annotated `let` — the same binding can be written at one
type and read at another, and `AX3040`'s own exit 139 is reached with
no `cast` written anywhere. The refusal `AX3040` gives up here has to
be paid for by pinning (§5 item 4), not by re-widening the rule: the
nested case really is a different shape, and a bare result variable is
still the only one a `cast` alone can produce.

## 3. What the migration costs, measured

Flipping **four** signatures in `stdlib/Vec.ax` — `vecNew`, `vecLen`,
`vecGet`, `vecPush` — produces **3,934 errors** across the tree, 7,866
`AX3004`s among them. The whole compiler passes Vecs as `Int`, so every
signature that takes or returns one has to say so.

**"That is mechanical and the type checker drives it" is WITHDRAWN**
— §4c drove it and measured otherwise. The checker does name a file,
line and column for every error, and the fixpoint is "no errors",
which is a strong acceptance condition; what does not follow is that a
rule can reach it. Widening a parameter because a `Vec` arrives there
breaks the callers that pass an `Int`, and the tree diverges rather
than converging. Read §4c before planning the port.

**THE PORT IS LANDED.** 4,432 errors to **zero**: `stdlib/`, every
REPL module and the whole closure of `self_host/main.ax` typecheck
clean, the stdlib fixture corpus passes against its goldens, and the
self-hosting fixpoint holds — stage2 and stage3 are byte-identical at
201,920 lines of emitted IR. What closed it was not a rule. The
mechanical driver reached **181 errors over 130 declarations** and
stopped there for the reason §4c records; three readers then decided
the remaining element types from the code, and three fixers applied
them.

**THE BYTE-IDENTICAL-IR ACCEPTANCE TEST DID NOT SURVIVE, and that is a
correction to this section rather than a failure of the port.** The
reasoning was that `(Vec a)` and `Int` have the same runtime
representation, so a type-level migration should emit identical code.
The representation claim is still true; the conclusion was wrong.
Measured, the pre-port tree emits 200,155 lines and the ported tree
201,920, and the difference is concentrated in one place: `__evw`
appears on **157 `define` lines, up from 36**. A genuinely
polymorphic parameter carries an evidence word so ARC can decide at
run time whether the value it holds is a reference, and typing these
containers is exactly what created genuinely polymorphic parameters.
The IR moved because the ARC system is doing its job on types that did
not exist before. The fixpoint — stage2 against stage3 — is the
acceptance test that survived, and it is the one that was load-bearing.

## 4. The blocker: `vecGet` cannot answer `a`

Flipping all thirty container positions leaves **42 errors inside
`Vec.ax` itself**, and they are not bookkeeping. Two shapes matter:

* **The implementation must reach through the abstraction.**
  `(memGetWord (vecData v) i)` needs the handle as a word. Inside the
  module a `Vec` IS an `Int`, so these are honest `cast`s at the
  boundary — but `docs/memory-model.md` records that **`cast` kills ARC
  evidence**, so a generic accessor built out of casts is not free.

* **`vecGet`'s sentinel cannot survive.** Its body answers `0` for an
  out-of-range index. Under `(-> (Vec a) Int a)` that is fabricating an
  `a` — and for a reference element it is a null a caller would
  dereference. **You cannot make up an `a`.**

So generics forces a decision about `vecGet` that has nothing to do
with types:

1. `vecGet` answers `(Option a)` and the sentinel goes — which is
   `vecTry` today, and would make the safe accessor the only accessor.
2. `vecGet` traps out of range.
3. `vecGet` stays raw, tagged `;@axiom:raw`, with `vecTry` the checked
   surface — the unsafe layer made finite and enumerable, which is what
   `#raw` in AXSYM is for.

### DECIDED: `vecGet` traps, `vecTry` stays the checked read

**(2)**, and the case rests on three decisions this repository has
already made rather than on taste.

* **`Vec.ax`'s own comment already calls the sentinel the worse
  failure.** "0 IS A VALUE A CALLER MAY HAVE PUSHED — so a caller who
  reads past the end and one who reads a stored zero receive the same
  answer and cannot tell which happened. On a parser fed by a peer that
  is the worse of the two failure modes: **not a crash, a wrong answer
  that keeps going**." The file argues for the crash; it just could not
  have one while the element was an untyped word.
* **The same comment already chose the split.** "`vecGet` is unchanged
  and stays. It is the right call where the index is already known good
  — a loop bounded by `vecLen`." `vecGet` direct, `vecTry` checked, is
  the design on file. Trapping keeps it; option (1) discards it and
  forces a match at every in-range access.
* **Axiom already answers this class of bug with a trap.** Division by
  zero exits 72 with `axiom: division by zero`. An index out of range
  is the same class of programmer error, and answering it with a value
  is the odd one out.

And the trap is **recoverable**, which is what makes it acceptable
rather than merely blunt: `__axiom_recover` answers 70, 71 or 72 at a
recovery point instead of exiting, and 77 would join them. A trap in
Axiom is a catchable outcome, not unconditional process death.

**(1) is the runner-up and is rejected on cost, not principle.** It is
`compat/SENTINELS`'s direction rule applied to the literal-`0`
sentinel, and today's register-pair work makes `(Option a)` free at a
direct match — the 11.86 ns objection that governed this for months is
gone. What it does not answer is the ergonomics: `vecGet` has hundreds
of call sites, most of them indices a loop already bounded, and forcing
a match there adds noise without adding safety. `vecTry` exists for the
ones that need it.

**(3) is refused outright.** `docs/memory-model.md` records the raw
layer closed 14 → 0; making `vecGet` — one of the highest-traffic
functions in the tree — `;@axiom:raw` would reopen it at the worst
possible place.

### What (2) needs, and why it is not in this commit

1. A trap `@__axiom_index_out_of_range`, status **77** (70–76 are
   taken; 73 is the FFI's), mirroring `emitDivTrap` — message,
   `__axiom_recover_abort` first, backtrace, exit.
2. A **diverging nullary primitive** so `stdlib/Vec.ax` can reach it.
   Traps today are `internal` LLVM functions emitted by codegen and
   unreachable from Axiom source.
3. **The primitive must type as `(-> a)`** — it never returns, so it
   inhabits every result type, which is `AX3040`'s own stated way out
   ("make it DIVERGE, so every path ends in a call that never returns,
   which is what makes `for all a` honest").

**Steps 1–3 are built.** `(__indexTrap)` is a nullary primitive typed
`(mkTVar "a")` — a bare variable, freshly instantiated at each use, so
one call stands in an `Int` result and a `String` result in the same
program. The divergence fixpoint never entered it: that fixpoint
decides whether a DECLARATION with a result-only variable is honest,
and a builtin registered in `fns` has no declaration to ask about. The
teeth were in the wrong place.

**Step 4 — `vecGet` calling it — is not built, and the reason is the
bootstrap.** `scripts/build-shared-axc.sh` compiles `stdlib/` with the
INSTALLED compiler, so a library that uses a primitive the seed does
not know cannot be built:

```
error[AX3001]: undefined variable `__indexTrap`
   --> stdlib/Vec.ax:225:7
```

A primitive lands in the compiler first and the library uses it after
the seed advances. That is the ordinary shape of adding one to a
bootstrapped language, and it is why this commit stops one step short
of the change it exists for.

## 4b. `Vec` as a FIELD type was a silent leak, measured

Seeding `Vec` as a writable type had a consequence section 1 did not
look for, and it is a live defect rather than a migration blocker:
**`fldClass` had no arm for `Vec`.**

`self_host/codegen.ax`'s `fldClass` answers 0 (machine scalar, never
walked), 2 (reference, walked and released) or 1 (UNCLASSIFIABLE) —
and 1 does not mean "skip this field". It forces the whole block to
the LEAF shape, on the stated grounds that "under-reclaiming leaks, a
wrong bit use-after-frees, and only one of those is survivable". A
`Vec` reached that arm: not a scalar name, not one of the
`String`/`Option`/`Handle` trio, and — being seeded by the checker
rather than declared — not in the module's data list either.

Measured on one record, one field type apart:

| the record | shape word | the `String` field |
|---|---|---|
| `(data Rec (MkRec Int String))` | `262152` | walked |
| `(data Rec (MkRec (Vec Int) String))` | **`8`** | **never walked** |

`262152` is `0x40008`: bit 18 names block word 2, the `String`. At `8`
the map is empty, so the sibling's share is never handed back. No
diagnostic, every gate green, and reachable from ordinary source the
day `Vec` became writable.

**`Vec` is class 0, and that is an ownership decision rather than a
claim that a vector is a number.** `stdlib/Vec.ax` says "a vector is
born owned ... and `vecFree` is the only thing that ends one", so a
record that merely HOLDS a vector does not own it and must not release
it. Class 0 is also exactly what such a field got while it was spelled
`Int`, which is what makes typing the handle a type-level change with
no reclamation consequence. Class 2 — walking and releasing it, as
`String` and `Handle` are — is the other defensible answer and is a
SEPARATE decision: it would have to audit every `vecFree` in the tree
first, because an automatic release beside an explicit one is a double
free.

The name is spelled in the two lists the tree requires to agree —
`scalarTyName` in codegen and `evScalarName` in typecheck — so
evidence reaches the same answer the reference map does.

**It was inert for everything that existed WHEN IT LANDED.**
Stage-matched emission of `self_host/main.ax` before and after:
**199,765 lines of IR, byte for byte identical**. The classification
can only move code that has a `Vec`-typed field, and nothing in the
tree had one yet.

**That last clause expired with the port, which is what makes this
section a prerequisite rather than a curiosity.** `HtmlBuf`,
`HttpReq`, `HttpRouter` and `Sym` now declare `Vec`-typed fields — the
four `S` rows in `compat/BREAKING`'s 0.6.4 block — so `fldClass` is
load-bearing for real records today. Had the port landed first, each
of them would have lost the reference map for its OTHER fields, which
is the defect §4b was written to describe.

Gated by `scripts/check-vec-field-shape.sh`, whose table has four rows
so the equality cannot pass vacuously: two of them must read a
different number, and the `(Vec Int)`/`String` row read `8` before the
fix.

## 4c. What the migration actually costs, re-measured

**READ THIS SECTION AS A RECORD OF WHAT THE AUTOMATION REACHED, NOT AS
A BLOCKER.** The port is landed (§3, §7). Everything below was measured
while driving it and every number in it still holds; what changed is
the ending. The mechanical driver got to **181 errors over 130
declarations** and stopped, for reasons this section establishes and
which are still the right reasons. The last 130 declarations were then
decided by three readers working from the code and applied by three
fixers — people doing what the section concludes only a person can do.
The negative results are kept deliberately: they are what says the
residue was a decision problem rather than a missing rule, and they are
the part worth reading before attempting a port of this shape again.

Section 3 records "3,934 errors ... mechanical, and the checker drives
it". The first half is right and **the second half is wrong**,
measured 2026-09-01 by driving it.

Flipping `Vec.ax`'s thirty container positions — `vecGet` answering
`a`, `vecTry` `(Option a)`, `vecPush` `(-> (Vec a) a (Vec a))` —
typechecks **`Vec.ax` itself with zero errors** and leaves **4,406**
in the tree, every one `AX3004`. A checker-driven rewriter then took
it to **1,916** over four rules, each verified by recompiling and
rolled back when it made things worse:

| rule | what it does | effect |
|---|---|---|
| typed view | `(memGetWord n i)` becomes `(memGetWordVec n i)`; `nodeB` becomes `nodeBVec` | **converges** |
| param | a parameter USED as a `Vec` gets `(Vec a)` | **converges** |
| null check | `(== v 0)` on a handle becomes `(== (cast Int v) 0)` | **converges** |
| callee param | a parameter that RECEIVES a `Vec` gets `(Vec a)` | **diverges** |

**THE LAST ROW IS THE FINDING.** Widening a parameter because one
caller passes a `Vec` breaks the callers that pass an `Int`, and those
are not a residue: run unguarded, the tree goes 1,916 to 5,990 to
10,102 to 14,392 and never comes back. The compiler uses `Int` as a
universal word type on purpose, and many functions are genuinely
polymorphic by punning. Separating `Vec` out of that is a decision per
function, not a rewrite.

**The vehicle that works is the typed view**, and it is the one this
repository already uses for the same problem: `nodeAName` casts word 1
to `String` at a RETURN, inside a signature that carries the type,
"and not at the call sites — a cast at an argument root classifies
that value's evidence 0 and drops its retain or its release"
(`docs/memory-model.md` MM-VAL-22). `memGetWordVec` and
`nodeAVec`/`nodeBVec`/`nodeCVec` are the same move for containers.

### Re-run with pinning and the full rule set: it plateaus at ~370

The numbers above were taken before §4d was built. With pinning in the
tree and six syntactic rules plus three verified passes, the port goes
**4,432 to about 370**, and stops there. The rules, in the order they
were found to matter:

| rule | what it decides |
|---|---|
| typed view | `(memGetWord n i)` becomes `memGetWordVec`; `nodeB` becomes `nodeBVec` |
| let-init view | the same, one hop through the `let` that bound the value — **1,531 to 1,068 on its own** |
| param | a parameter USED as a container takes its type |
| absent `0` | the "no vector" literal becomes `(cast (Vec T) 0)` |
| null check | `(== v 0)` on a handle becomes `(== (cast Int v) 0)` |
| struct field | a `(struct ...)` or `(data ...)` field the constructor is called with |
| verified result / param / retype | applied one at a time and kept only if the count drops |

### The rules that came out of driving it further

Four more rules and three accessors took the port from 370 to **210**,
and each is a piece of design rather than a heuristic:

* **`vecGetVec`** {D} `(-> (Vec a) Int (Vec b))`, the cast at the
  return. Some of this compiler's vectors are HETEROGENEOUS by
  construction: `pruneMark`'s `ctx` has an interner in slot 0 and
  vectors in slots 1..3, so no element type describes it. Retyping the
  container is wrong; the READ is what needs the type. The result
  variable is `b`, not `a`, because what the vector holds and what one
  slot holds are different questions, and pinning lets each call site
  answer its own.
* **`vecPushStr` / `vecPushVec`** {D} the same problem writing, and the
  reason they exist rather than a call-site cast is MM-VAL-22.
  `(vecPush r (cast Int s))` type-checks and is a USE-AFTER-FREE:
  `vecPush`'s element parameter is a type variable, a cast at an
  argument root there classifies the evidence 0, and `memSetWord`'s
  `__retainref` then emits nothing {D} the vector holds a `String`
  whose share nobody took. So the accessor takes the share EXPLICITLY
  and pairs it with the cast: one retain here, and the one `vecPush`
  would have taken is exactly the one the cast suppresses, so the count
  matches a `(Vec String)` push.
* **the let-init typed view** {D} `(let ((v (nodeB t))) ... (vecLen v))`
  is fixed at the BINDING, not at each use. Worth 1,531 to 1,068 alone.
* **discarding a container result** {D} `vecPush` answers the handle,
  so `(if c 0 (vecPush ...))` has two types where it had one. The value
  was always discarded there; `{ (vecPush ...) 0 }` says so.

### The error count is the wrong measure, and that is why every search stalled

**A correct coupled change RAISES the error count.** Typing
`parseNamedFieldTypes`'s `names` as `(Vec String)` is right and reddens
every call site, so a search that accepts a move only when errors drop
rejects the correct move every time. Every plateau above was that
measure, not the port.

The measure that IS monotone is **how many DECLARATIONS the errors
touch**. Fixing one removes it and adds only the callers that were
always going to need fixing, so the count falls even while the error
count rises. Switching the objective, and fanning the trials out
across eight workers because each is a convergence pass, moved a
search that had been stuck at 210 for hours:

    149 declarations / 202 errors   ->   130 / 181

**A second bug was hiding inside the first.** The trial's rollback
restored the FILE it had edited and not the tree, while the
convergence pass it ran had rewritten dozens of others {D} so a round
that kept two moves came out 37 declarations WORSE than it started,
and read as evidence against the method. It was evidence about the
harness.

**AND THE PLATEAU WAS REAL, at 130 declarations.** The search
accepted one move a round rather than none, which closes the port in
about a hundred rounds of eight minutes each and was not a plan. The
candidates were the limit: they come from positions an error already
names, and a coupled fix needs the positions that have no error YET.
That is the whole-chain inference this document keeps arriving at —
and the subsection below measures why that would not have closed it
either.

**WHAT ACTUALLY CLOSED IT: 181 to zero, by reading.** Three readers
took the 130 declarations and decided each one's element type from the
code around it — what the vector is pushed, what its elements are used
as, what the function is for — and three fixers applied the decisions
and the call-site changes they coupled to. That is not a rule the
driver was missing. It is the per-function decision this section had
already concluded was the only thing left, done by the only thing that
can do it. The driver's 4,432 → 181 is what automation was worth here,
and it was worth a great deal; the last 181 cost people.

### Why whole-chain inference cannot close it either, measured

The obvious next move was an inferencer over the source graph {D}
declaration positions as nodes, the places the language forces two to
agree as edges, union-find, solve once, write once. It was built, and
it decides **417 positions from the source alone**, taking 4,432 to
3,889 in one pass with no error-driven guessing. Then it stops, and the
reason is worth more than the inferencer.

**The classes come out as one giant component.** With generic positions
excluded {D} `vecAppendFrom : (-> (Vec a) ...)` is one declaration every
vector in the program is passed to, and unifying through it merges them
all {D} the largest class is still 8,866 of about 12,000 positions.
Modelling `Int` as a real type rather than as "undecided" does not
break it up either: a `Vec` refines a word, so every `Int` position
that touches any container joins the same class, and 11,457 end up in
one.

**That is not a defect in the solver. It is the answer.** The compiler
passes an undifferentiated machine word everywhere, and inference can
only recover what the program still says. The positions it CAN decide
are exactly the ones where something concrete is actually stored {D} a
`String` literal pushed, a nested container read back {D} which is what
the 417 are. **For the rest the source has erased the distinction, so
there is nothing to infer**, and `(Vec Int)` is the honest answer,
which is already what the driver writes.

So the residue was not waiting on a better algorithm. **It is 130
declarations whose element type is known to a reader and to nobody
else**, and closing the port meant someone deciding them {D} which is
the same thing §4c said, now with the reason underneath it. That is
what happened, and this paragraph is the prediction that turned out to
be the plan.

**THE STRUCTURAL PLATEAU, unchanged in what it shows.** At 210 the
same wall stands, and it is now possible to say exactly what it is:
**the port needs a declaration and its callers to change together, and
nothing available decides both.** Fixing a parameter from how its body
uses it (`reparam`) is right and turns every call site red; propagating
that back to the callers (`argfix`) is also right and turns their
callers red. Run together and unjudged for twenty rounds they
oscillate between 219 and 238 and never reach 210 {D} each is correct
locally and neither closes.

**THE ORIGINAL FOUR EXPERIMENTS, unchanged in what they show.** Restarting
from a clean tree with every rule available lands at **370**; the
incremental run reached **354**. Applying every candidate at once goes
to **5,611**, and applying only the positions every error AGREES about
— 183 of them — goes to **5,462**. Trying candidates one at a time
with a full convergence lookahead, serial or across eight workers,
buys about **two errors a round**.

So the residue is not a rule that has not been written. **It is ~370
errors over 224 declarations, each needing a decision about what a
particular vector holds**, and the decisions are COUPLED: typing
`parseNamedFieldTypes`'s `names` as `(Vec String)` raises the count
until every caller moves with it, which is why one-at-a-time
verification rejects it and why bulk application, which moves them all
including the wrong ones, is worse still.

The head of the list is the compiler's context constructors —
`newCG`, `tcNew`, `smNew`, `symbolsRenderGens` — which build records
of many `Vec` fields through raw words, and the widest single shape is
44 `vecPush` sites whose element is a `String` in a vector the port
typed `(Vec Int)`.

**A `cast` at those sites is NOT the way out, and the memory model
says why.** `(vecPush v (cast Int s))` would typecheck, and
`vecPush`'s element parameter is a type VARIABLE, so MM-VAL-22's
measured rule applies: a cast at an argument root in a type-variable
position classifies the value's evidence 0 and **suppresses the
retain**. The `String`'s share would never be taken. The honest fix is
the element type, not a cast.

**"What would finish it is element-type inference over declaration
positions" — WITHDRAWN, and it is the last wrong prediction this
section made.** The proposal was a union-find whose nodes are
parameters, results and fields, seeded by the certain sites (a
`String` literal pushed, an `Int` arithmetic use) and propagated
through calls — §4d's pinning, one level up. It was built. The
subsection above measures what it does: 417 positions decided from the
source alone, 4,432 to 3,889 in one pass, and then a single class of
8,866 positions, because `vecAppendFrom : (-> (Vec a) ...)` is a
declaration every vector in the program passes through. What finished
the port was people reading 130 declarations and deciding them.

**`vecPop` is a second `vecGet`, and section 4 did not name it.
LANDED.** Its body answered `0` on an empty vector, and under
`(-> (Vec a) a)` that fabricates an `a` exactly as `vecGet`'s sentinel
did. It took the same answer — `__indexTrap` at status 77 — and
`vecLast` inherits the trap for free because it delegates to `vecGet`.
Nothing else in the module has the shape. This is the port's one
BEHAVIOUR break as opposed to a retype, and `compat/BREAKING` declares
it as one.

## 4d. The migration's PREMISE only half holds, measured

`(Vec a)` exists to stop a caller putting an `Int` in and taking a
`String` out. It does that **exactly where a declaration says the
element type, and nowhere else** — and the second half is not a
rough edge, it is the shape `AX3040` was promoted to an error for.

Measured against a migrated `Vec.ax`, four probes:

| the program | `check` | runs |
|---|---|---|
| push a `String` into a declared `(Vec Int)` parameter | **refused** | — |
| pass a `(Vec Int)` where `(Vec String)` is declared | **refused** | — |
| read an element through a declared return type at the wrong type | **refused** | — |
| `(let ((v vecNew)) { (vecPush v 42) (needVec (vecGet v 0)) })` | **OK** | **exit 139** |

The last row has **no `cast` anywhere in it**. An `Int` goes in, a
`(Vec Int)` comes out, and `vecLen` dereferences 42 as a block header.
That is `conjure`'s exit 139 reached without writing the coercion
`AX3040`'s own help text says is the only way to produce it.

**THE CAUSE IS THAT THE CHECKER DOES NOT UNIFY.** `tyCompat` is a
COMPATIBILITY PREDICATE — it answers 1 or 0 and records nothing.
A minted placeholder "still matches anything — that is the whole
reason it exists", and since no binding is ever written down, `(Vec
_a)` is compatible with `(Vec Int)` and then, just as happily, with
`(Vec String)`. The let-bound vector's placeholder is never pinned,
because each `vecPush` matches against its own fresh one.

It is NOT a general unifier defect, which is worth stating because it
narrows the fix. A user-defined `(Box a)` behaves:
`(needStr (unbox (MkBox 42)))` is refused, because the constructor
hands over a concrete `(Box Int)` and nothing has to be remembered.
`(-> a a)` behaves for the same reason. The hole needs a placeholder
that OUTLIVES the expression that could have pinned it, which is
precisely what a `let`-bound mutable container is.

**So `Vec` is not the subject here.** Any parameterised type reached
through an un-annotated `let` has it; `Vec` is where it bites because
a container is the thing you bind and then mutate.

**WHAT THIS MEANS FOR THE ORDER.** The migration must not land before
pinning exists. Landing it would replace a visible unsafety with an
invisible one: today reading an element back at a reference type is
spelled `vecGetStr` or an explicit `cast` and `#raw`/`AXSYM` can
enumerate it, whereas afterwards `(vecGet v 0)` would silently become
whatever the context asked for. The type-level win at declared
boundaries is real and is worth having — it is the first three rows
above — but it is not worth buying with the fourth.

### Pinning, built

**A placeholder from INSTANTIATION now binds.** Word 2 of a
`TAG_T_VAR` node is 0 until something pins it; `parser.ax` documents
that tag as `a=name` and every consumer dispatches on the tag and
reads only the name, so the slot aliases nothing. `tyCompat` resolves
both sides before it dispatches, and `tyVarCompat` pins instead of
merely matching. All four probes above reverse: the two unsound rows
are refused, the two sound ones still pass.

**Four obligations make it sound, and each is a rule in the code
rather than a hope.**

1. **Only an INSTANTIATION placeholder binds.** `freshTVar` mints for
   two different jobs and only one may be pinned. Instantiating a
   declared signature mints "the type the caller chose for `a` here",
   and two uses of one binding must agree about that. Every other use
   {D} a `cond` with no arms yet, a pattern binder, a missing
   parameter type {D} mints "not known", and pinning THAT reports an
   error where the checker simply has no information. The two are
   separated by name: `_iN` binds, `_tN` does not, and the empty-named
   `mkSilentWild` never does.
2. **Nothing binds to poison.** `TAG_T_ERR` is compatible with
   everything so one error does not cascade; pinning to it would
   spread the error instead of stopping it.
3. **The occurs check is not optional.** Binding `_i` to a type
   containing `_i` builds a cycle that `tyResolve` and the
   reference-map walk would both follow forever.
4. **There is no backtracking.** Binding is monotone, so it is sound
   only if no caller tries a match and discards it. All 53 `tyCompat`
   call sites were read: every one reports on failure or walks
   positional arguments, and none speculate.

**It is nearly inert on the tree as it stands**, which is what made it
safe to land ahead of the port: 47 of 4,434 signatures in `self_host/`
and `stdlib/` mention a source type variable at all, so almost nothing
is instantiated and almost no placeholder exists to pin. Byte-identical
fixpoint from the seed, `check-self-host` 179/179,
`check-diagnostics` 194/194, `check-stdlib-selfhost` {D} no gate moved.

**Pinning is PER BINDING, not a global substitution**, and that is
gated rather than asserted: two containers from the same polymorphic
constructor may be pinned to different element types in one scope. A
global substitution passes every other check in
`scripts/check-type-pinning.sh` and fails that one.

**One thing it deliberately does NOT change.** An UNDECLARED function
still may not be used at two types {D} `(fn (untyped x) x)` applied to
an `Int` and then a `String` is refused. It was refused before pinning
too. That is a pre-existing rule about inference without
generalisation, and it is written down here so the next reader does
not attribute it to this change.

## 5. The order

1. **`Vec` as a type, and `AX3040` narrowed.** Landed.
2. **`vecGet` traps.** Landed. The seed carries `__indexTrap`, and
   `vecGet` calls it on an out-of-range index (status 77).
3. **The field-shape defect.** Landed, and it was NOT on this list
   until a migration attempt found it — see §4b. It is a
   prerequisite: until `fldClass` classifies `Vec`, every record that
   holds one leaks its OTHER fields.
4. **Pinning a placeholder.** LANDED. The checker compared types and
   recorded nothing, so an un-annotated `let` over a container was
   unpinned and `(vecGet v 0)` answered whatever the context wanted
   (§4d: `check` OK, exit 139). It had to come before the migration,
   which would otherwise have traded a visible unsafety for a silent
   one.
5. **The migration.** LANDED, 4,432 errors to zero. Not the
   mechanical change this document assumed and not driven to the end
   by the checker: §4c's driver reached 181 errors over 130
   declarations and stopped, and people decided the rest. The
   acceptance test this document proposed — byte-identical IR — was
   itself wrong and is corrected in §3; the fixpoint (stage2 against
   stage3, byte-identical) is the one that held.
6. **`for` as a keyword.** LANDED, 2026-09-03. One keyword with two
   shapes told apart by arity, desugared in the parser to the
   `let`/`while`/`set` the hand-written loop already was
   (`parseForExpr`, `self_host/parser.ax`); the container half reads
   `Vec::vecGet`, which is the read item 5 gave an element type.
   `tests/stdlib/466-for-loop.ax` pins twelve terms, and the two
   loop macros `stdlib/Html.ax` carried for one idea are deleted.
   Nothing remains on this list.

## 6. A route that was tried and is the wrong one

Before seeding `Vec` as a type, the obvious move looked like a wrapper:
`(data Vec (a) (MkVec Int))`, since `axiom-bindgen` already wraps every
opaque Rust type that way. That costs a heap block — measured on
`(data Box (MkBox Int))`, `axiom_alloc(16)` plus four stores — so it
was prototyped as a **transparent newtype**: one constructor with one
field represented AS the field. It works and is free (`mk` becomes
`mul; ret`, fixpoint holds, 96/96, 179/179, 194/194).

It is still the wrong route, and two measurements say why:

* **`fldClass` answers from the TYPE NAME.** A `data` name classifies
  as a reference because a type name cannot reach its constructor's
  entry (`lookupType` is keyed by constructor). Transparent, the value
  IS the field — so a newtype over `Int` classified as a reference
  hands `axiom_release` an integer to read as a block header.
* **`Handle` has an identity the FFI relies on.** Restricting to
  reference fields avoids the first problem and breaks
  `demo/060-opaque-handle`: `exit 73, handle is closed`. `Handle`
  carries a close/inert protocol, the wrapper and the handle were two
  identities, and collapsing them makes a close through one visible
  through the other.

Seeding `Vec` as an abstract type needs neither: no wrapper, no
allocation, no reclassification. The newtype work is not in the tree.

## 7. Status

`Vec` is a type, `AX3040` is narrowed, and **§4 is built**: `vecGet`
refuses an out-of-range index through `(__indexTrap)` at status 77,
and the seed carries both. `vecTry` remains the checked read.

**§4b is built and gated** — `fldClass` classifies `Vec` as class 0,
so a record holding one keeps the reference map for its other fields.
That was a live defect from the day `Vec` became writable, it is
byte-for-byte inert for every program that exists, and
`scripts/check-vec-field-shape.sh` is what would notice it coming
back.

**Pinning is BUILT** (§4d), so the block §4d described is lifted: a
let-bound container is now pinned by its first use, and the exit-139
program is refused. `scripts/check-type-pinning.sh` holds it.

**THE MIGRATION IS LANDED.** `stdlib/Vec.ax` hands out a parameterised
`(Vec a)`, and the 4,432 errors that produced are at **zero**:
`stdlib/`, every REPL module and the whole closure of
`self_host/main.ax` typecheck clean, the `tests/stdlib/` corpus passes
against its goldens, and the self-hosting fixpoint holds — stage2 and
stage3 byte-identical at 201,920 lines of emitted IR.

**HOW IT CLOSED, because the shape of that is the finding.** The
mechanical driver of §4c took it from 4,432 to **181 errors over 130
declarations** and stopped. It did not stop for want of a rule: §4c
measures four experiments and a whole-chain inferencer against that
wall, and the inferencer's own answer is that the source has erased
the distinction for those positions, so there is nothing left to
infer. Three readers then decided the 130 element types from the code
and three fixers applied them with the call-site changes each one
coupled to. Automation was worth 4,432 → 181; people were worth 181 →
0, and §4c is kept in full because it is the record of which is which.

**THE IR IS NOT BYTE-IDENTICAL, and §3's acceptance test is corrected
rather than met.** 200,155 lines before, 201,920 after, with `__evw`
on **157 `define` lines against 36**. Typing these containers created
genuinely polymorphic parameters, and a genuinely polymorphic
parameter carries an evidence word so ARC can decide at run time
whether it holds a reference. That is the memory model working on
types that did not exist before the port, not a regression. The
acceptance test that survived is the fixpoint.

`compat/BREAKING` declares the port's 0.6.4 breaks — 39 the census
sees, eleven `Tui` names it cannot — and `vecPop` is the only
BEHAVIOUR break among them: it answered `0` on an empty vector and now
refuses at status 77, for `vecGet`'s reason.

Nothing from §6 is in the tree, and §4c's inferencer is not either.

**`for` IS A KEYWORD, and the list is closed.** Item 6 was the reason
this document exists — its opening paragraph is the statement that a
container loop cannot be a keyword until a container has an element
type — and it landed on 2026-09-03 on top of item 5: `(for i lo hi
body)` over a range and `(for x xs body)` over a `(Vec a)`, one head
discriminated by arity, desugared in the parser so no consumer of the
AST moved, both ends read once before the loop. The element read is
the qualified `Vec::vecGet`, so it is the polymorphic accessor the port
typed and not a per-type spelling; `stdlib/Html.ax`'s `for` and
`forInt` — the two macros for one idea the opening paragraph names —
are deleted with no call site moved. `tests/stdlib/466-for-loop.ax`
holds twelve terms, `tests/diagnostics/625-for-shape` and
`626-for-not-a-container` the two refusals. What the keyword does NOT
yet do is appear in `self_host/` or `stdlib/`: the seed must learn it
first, and `range` stays in the prelude until it has.
