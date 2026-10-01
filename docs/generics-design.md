# Parameterised containers, and what `Vec a` actually costs

`Vec` carries its element type, and `for` walks a vector as a keyword.
Here you'll find why, what the port cost, and why `vecGet` traps on an
index out of range. Every item on the plan has landed, from the element
type (§5 item 5, `68f145b`) to `for` as a keyword (§5 item 6). §7 sums
up what landed and what did not.

Here is the result. A vector of strings reads back a `String` with no
cast, `for` walks it, `vecTry` asks whether an index holds an element,
and `vecGet` stops the program when it doesn't:

```scheme
(import IO)
(import Vec)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((names vecNew))
    {
      (vecPush names "ada")
      (vecPush names "grace")
      (for n in names (println n))
      (match (vecTry names 5)
        ((Some n) (println n))
        (None (println "nothing at 5")))
      (println (vecGet names 5))
      0
    }))
```

Saved as `names.ax` and run with `axiom run names.ax`, it prints:

```text
ada
grace
nothing at 5
axiom: vector index out of range
axiom: backtrace (most recent call first)
  at __axiom_index_out_of_range
  at __axiom_user_main names.ax:15:8
  at main
```

The program exits with status 77. Tested by
`tests/stdlib/466-for-loop.ax` and `tests/stdlib/464-index-trap.ax`.

The work started from `for`. It could not become a keyword covering
both a range and a container until a container had an element type,
and `Vec` had none. It was an `Int` handle, and you read an element
through `vecGetStr` or `vecGetWord`, depending on what it held. That is
why `stdlib/Html.ax`, the HTML DSL since deleted, carried two loop
macros for one idea. A keyword written before the port would have been
just as type-specific: the problem would have moved from the macros
into the code generator.

The gap was visible in the signatures before the port:

```scheme
(pub :: vecPush (-> Int a Int))     ; the element going in is polymorphic
(pub :: vecGet  (-> Int Int Int))   ; the element coming out is an Int
(pub :: vecGetStr (-> Int Int String))
```

`vecPush` took an `a`, but nothing tied that `a` to what `vecGet`
answered, because there was no `Vec a` to carry it. That was the whole
of the generics problem. The same functions now read:

```scheme
(pub :: vecPush (-> (Vec a) a (Vec a)))
(pub :: vecGet  (-> (Vec a) Int a))
(pub :: vecGetStr (-> (Vec a) Int String))
```

## 1. `Vec` is a type now

`Vec` is seeded in `typecheck.ax` beside `Option`, as a `DataEnt` with
no constructors: abstract and parameterised. You make a `Vec` with
`vecNew` and read it with `vecGet`. You never match on one, so there
is nothing for a pattern to name. `(Vec a)` is a type you can write;
before this change it was `AX3002 undefined type`.

The runtime shape is unchanged. A `Vec` is still a one-word handle,
allocated by `vecNew`. Because this is purely a type-level change, it
could land before the migration that uses it. With §4b's fix,
`fldClass` answers for `Vec` exactly what it answered for the `Int` it
replaces.

## 2. `AX3040` had to narrow, and it was wrong as written

`(pub :: vecNew (Vec a))` drew `AX3040` result-only-tyvar: "the caller
chooses the type and a `cast` fabricates the value."

That is not what happens here. `(-> Int (Vec a))` returns a `Vec`, not
an `a`, and an empty container holds no value of type `a` for anything
to have fabricated. The rule's own sentence says "returns type
variable `a`", and that is now all it checks: a *bare* result
variable. `(-> Int a)` still fires. A variable nested under a type
constructor does not.

`None : (Option a)` has had exactly this shape since `Option` was
seeded. It was never refused only because a builtin constructor never
passes through the check. Before the narrowing, every polymorphic
empty constructor was refused, so no generic container could declare
the one function it can't do without. Tested by
`tests/diagnostics/347-result-only-tyvar.ax`, which keeps the bare case
refused and the nested case silent.

The narrowing is right, but its argument is incomplete (§4d). "An empty
container holds no value of type `a`" is true at the moment of
construction, and stops being the whole story one line later. The
caller still chooses `a`, then mutates the container at that choice.
Where nothing pins the choice, such as an un-annotated `let`, the same
binding can be written at one type and read at another. That reaches
`AX3040`'s own exit 139 with no `cast` written anywhere.

The refusal `AX3040` gives up here is paid for by pinning (§5 item 4),
now built, and not by widening the rule again. The nested case really
is a different shape, and a bare result variable is still the only one
a `cast` alone can produce.

## 3. What the migration costs, measured

Flipping four signatures in `stdlib/Vec.ax` (`vecNew`, `vecLen`,
`vecGet` and `vecPush`) produces 3,934 errors across the tree, 7,866
`AX3004`s among them. The whole compiler passed vectors as `Int`, so
every signature that takes or returns one has to say so.

This section first called that "mechanical", with the type checker
driving it. That claim is withdrawn: §4c drove it and measured
otherwise. The checker does name a file, line and column for every
error, and "no errors" is a strong acceptance condition. What doesn't
follow is that a rule can reach it. Widening a parameter because a
`Vec` arrives there breaks the callers that pass an `Int`, and the tree
diverges instead of converging. Read §4c before planning a port like
this one.

**The port has landed**, taking 4,432 errors to zero. `stdlib/`, every
REPL module and the whole closure of `self_host/main.ax` typecheck
clean, and the stdlib fixture corpus passes against its goldens. The
self-hosting fixpoint holds: stage2 and stage3 are byte-identical at
201,920 lines of emitted IR.

A rule did not close it. The mechanical driver stopped at 181 errors
over 130 declarations, for the reason §4c records, and people decided
the rest: three readers chose the element types from the code, and
three fixers applied them.

The byte-identical-IR acceptance test did not survive, and that
corrects this section; it is not a failure of the port. The reasoning
was that `(Vec a)` and `Int` have the same runtime representation, so
a type-level migration should emit identical code. The representation
claim is still true. The conclusion was wrong.

The pre-port tree emits 200,155 lines and the ported tree 201,920. The
difference sits in one place: `__evw` appears on 157 `define` lines, up
from 36. A genuinely polymorphic parameter carries an evidence word, so
ARC can decide at run time whether the value it holds is a reference.
Typing these containers is exactly what created genuinely polymorphic
parameters.

So the IR moved because ARC is doing its job on types that didn't exist
before. The acceptance test that survived is the fixpoint, stage2
against stage3, and it is the one that mattered.

## 4. The blocker: `vecGet` cannot answer `a`

Flipping all thirty container positions leaves 42 errors inside
`Vec.ax` itself, and they are not bookkeeping. Two shapes matter:

* **The implementation must reach through the abstraction.**
  `(memGetWord (vecData v) i)` needs the handle as a word. Inside the
  module a `Vec` *is* an `Int`, so these are legitimate `cast`s at the
  boundary. But the [memory model](memory-model.md) records that `cast`
  kills ARC evidence, so a generic accessor built out of casts isn't
  free.
* **`vecGet`'s sentinel cannot survive.** Its body answered `0` for an
  out-of-range index. Under `(-> (Vec a) Int a)` that fabricates an
  `a`, and for a reference element it is a null a caller would
  dereference. You can't make up an `a`.

So generics forces a decision about `vecGet` that has nothing to do
with types:

1. `vecGet` answers `(Option a)` and the sentinel goes. That is
   `vecTry` today, and it would make the safe accessor the only one.
2. `vecGet` traps out of range.
3. `vecGet` stays raw, tagged `;@axiom:raw`, with `vecTry` as the
   checked surface. That keeps the unsafe layer finite and enumerable,
   which is what `#raw` in AXSYM is for.

### Decided: `vecGet` traps, `vecTry` stays the checked read

We chose option (2). The case rests on three decisions the repository
had already made:

* **`Vec.ax`'s own comment already called the sentinel the worse
  failure.** Zero is a value a caller may have pushed, so a read past
  the end and a read of a stored zero get the same answer, and the
  caller can't tell which happened. On a parser fed by a peer, that is
  "not a crash, a wrong answer that keeps going". The file argued for
  the crash. It just couldn't have one while the element was an
  untyped word.
* **The same comment already chose the split.** `vecGet` is the right
  call where the index is already known good, such as a loop bounded
  by `vecLen`, and `vecTry` is the checked read. Trapping keeps that
  design. Option (1) discards it and forces a match at every in-range
  access.
* **Axiom already answers this class of bug with a trap.** Division by
  zero exits 72 with `axiom: division by zero`. An index out of range
  is the same class of programmer error, and answering it with a value
  was the odd one out.

The trap is also recoverable, which makes it acceptable rather than
blunt. At a recovery point, `__axiom_recover` answers 70, 71 or 72
instead of exiting, and it answers 77 the same way. A trap in Axiom is
an outcome you can catch, not unconditional process death.

Option (1) is the runner-up, rejected on cost rather than principle.
It is `compat/SENTINELS`'s direction rule applied to the literal-`0`
sentinel, and the register-pair work makes `(Option a)` free at a
direct match, so the old 11.86 ns objection is gone. What it doesn't
answer is ergonomics. `vecGet` has hundreds of call sites, most of them
indices a loop already bounded, and forcing a match there adds noise
without adding safety. `vecTry` exists for the sites that need it.

Option (3) is refused outright. The raw layer has been closed from 14
declarations to 0, as `axiom explain AX3040` records. Tagging `vecGet`,
one of the most-called functions in the tree, `;@axiom:raw` would
reopen it at the worst possible place.

<a id="what-2-needs-and-why-it-is-not-in-this-commit"></a>

### What (2) needed, and why it landed in two steps

1. A trap, `@__axiom_index_out_of_range`, with status 77. Statuses 70
   to 76 were taken, and 73 is the FFI's. It mirrors `emitDivTrap`:
   the message, `__axiom_recover_abort` first, a backtrace, then exit.
2. A diverging nullary primitive, so `stdlib/Vec.ax` can reach the
   trap. Traps are `internal` LLVM functions emitted by the code
   generator, and Axiom source can't call them.
3. The primitive types as `(-> a)`. It never returns, so it inhabits
   every result type. That is the way out `AX3040`'s own help text
   offers: make the function diverge, so every path ends in a call
   that never returns, which is what makes a `forall a` result sound.
4. `vecGet` calls it.

Steps 1 to 3 were built first. `(__indexTrap)` is a nullary primitive
typed `(mkTVar "a")`: a bare variable, freshly instantiated at each
use, so one call can stand in an `Int` result and a `String` result in
the same program. Tested by `tests/stdlib/464-index-trap.ax`.

The divergence fixpoint never examines it. That fixpoint decides
whether a *declaration* with a result-only variable is sound, and a
builtin registered in `fns` has no declaration to ask about.

Step 4 had to wait for the bootstrap. `scripts/build-shared-axc.sh`
compiles `stdlib/` with the installed compiler, so a library that uses
a primitive the seed doesn't know can't be built:

```text
error[AX3001]: undefined variable `__indexTrap`
   --> stdlib/Vec.ax:225:7
```

A new primitive lands in the compiler first, and the library uses it
once the seed advances. That is the ordinary order for adding one to a
bootstrapped language. The seed now carries `__indexTrap`, and `vecGet`
calls it on an out-of-range index (§5 item 2).

## 4b. `Vec` as a field type was a silent leak, measured

Seeding `Vec` as a writable type had a consequence §1 did not look
for. It was a live defect, not a migration blocker: `fldClass` had no
arm for `Vec`.

`fldClass` in `self_host/codegen.ax` answers 0 (a machine scalar, never
walked), 2 (a reference, walked and released) or 1 (unclassifiable).
An answer of 1 doesn't mean "skip this field". It forces the whole
block to the leaf shape, because "under-reclaiming leaks, a wrong bit
use-after-frees, and only one of those is survivable".

A `Vec` reached that arm. It is not a scalar name, and not one of the
`String`, `Option` and `Handle` trio. Because the checker seeds it
instead of a module declaring it, it was not in the module's data list
either.

Here is one record, one field type apart:

| the record | shape word | the `String` field |
|---|---|---|
| `(data Rec (MkRec Int String))` | `262152` | walked |
| `(data Rec (MkRec (Vec Int) String))` | **`8`** | **never walked** |

`262152` is `0x40008`, where bit 18 names block word 2, the `String`.
At `8` the map is empty, so the sibling's share is never handed back.
There was no diagnostic and every gate was green, and ordinary source
could reach it as soon as `Vec` became writable.

`Vec` is class 0. That is an ownership decision, not a claim that a
vector is a number. `stdlib/Vec.ax` says "a vector is born owned ...
and `vecFree` is the only thing that ends one", so a record that
merely holds a vector doesn't own it and must not release it.

Class 0 is also exactly what such a field got while it was spelled
`Int`, so typing the handle is a type-level change with no
reclamation consequence. Class 2, walking and releasing it as `String`
and `Handle` are, is the other defensible answer. It is a separate
decision: it would first have to audit every `vecFree` in the tree,
because an automatic release beside an explicit one is a double free.

The name is spelled in the two lists the tree requires to agree,
`scalarTyName` in the code generator and `evScalarName` in the type
checker, so evidence reaches the same answer the reference map does.

The fix was inert for everything that existed when it landed.
Stage-matched emission of `self_host/main.ax` before and after gave
199,765 lines of IR, byte for byte identical. The classification can
only move code that has a `Vec`-typed field, and nothing in the tree
had one yet.

The port changed that, which is why this section is a prerequisite.
`HttpReq`, `HttpRouter` and `Sym` declare `Vec`-typed fields, and
`HtmlBuf` did until `Html.ax` was deleted. They are the four `S` rows
in `compat/BREAKING`'s 0.6.4 block, so `fldClass` decides real records
today. Had the port landed first, each of them would have lost the
reference map for its *other* fields, which is the defect this section
describes.

Gated by `scripts/check-vec-field-shape.sh`. Its table has four rows so
the equality can't pass vacuously: two of them must read a different
number, and the `(Vec Int)`/`String` row read `8` before the fix.

## 4c. What the migration actually costs, re-measured

Read this section as a record of what the automation reached. It no
longer describes a blocker: the port has landed (§3, §7). Every number
below was measured while driving the port and still holds. What
changed is the ending. The driver stopped at 181 errors over 130
declarations, for reasons this section establishes, and people made
the per-function decisions it concludes only a person can make.

The negative results stay. They show that the residue was a decision
problem rather than a missing rule, and they are worth reading before
you attempt a port of this shape.

§3 first said "3,934 errors ... mechanical, and the checker drives it".
Driving it showed that the first half is right and the second half is
wrong.

Flipping `Vec.ax`'s thirty container positions (`vecGet` answering
`a`, `vecTry` answering `(Option a)`, `vecPush` as
`(-> (Vec a) a (Vec a))`) typechecks `Vec.ax` itself with zero errors.
It leaves 4,406 errors in the tree, every one `AX3004`. A
checker-driven rewriter then took that to 1,916 with four rules. Each
rule was verified by recompiling, and rolled back when it made things
worse:

| rule | what it does | effect |
|---|---|---|
| typed view | `(memGetWord n i)` becomes `(memGetWordVec n i)`; `nodeB` becomes `nodeBVec` | **converges** |
| param | a parameter *used* as a `Vec` gets `(Vec a)` | **converges** |
| null check | `(== v 0)` on a handle becomes `(== (cast Int v) 0)` | **converges** |
| callee param | a parameter that *receives* a `Vec` gets `(Vec a)` | **diverges** |

The last row is the finding. Widening a parameter because one caller
passes a `Vec` breaks the callers that pass an `Int`, and those are not
a small residue. Run unguarded, the tree goes from 1,916 to 5,990 to
10,102 to 14,392 errors and never comes back.

The compiler uses `Int` as a universal word type by design, and many
functions are genuinely polymorphic by punning. Separating `Vec` out of
that is a decision per function, not a rewrite.

The vehicle that works is the typed view, which the repository already
uses for the same problem. `nodeAName` casts word 1 to `String` at a
return, inside a signature that carries the type. It does not cast at
the call sites, because "a cast at an argument root classifies that
value's evidence 0 and drops its retain or its release"
(`memory-model.md` MM-VAL-22). `memGetWordVec` and `nodeAVec`,
`nodeBVec` and `nodeCVec` are the same move for containers.

### Re-run with pinning and the full rule set: it plateaus at ~370

The numbers above were taken before §4d was built. With pinning in the
tree, six syntactic rules and three verified passes take the port from
4,432 to about 370, and it stops there. The rules, in the order they
were found to matter:

| rule | what it decides |
|---|---|
| typed view | `(memGetWord n i)` becomes `memGetWordVec`; `nodeB` becomes `nodeBVec` |
| let-init view | the same, one hop through the `let` that bound the value: **1,531 to 1,068 on its own** |
| param | a parameter *used* as a container takes its type |
| absent `0` | the "no vector" literal becomes `(cast (Vec T) 0)` |
| null check | `(== v 0)` on a handle becomes `(== (cast Int v) 0)` |
| struct field | a `(struct ...)` or `(data ...)` field the constructor is called with |
| verified result / param / retype | applied one at a time and kept only if the count drops |

### The rules that came out of driving it further

Four more rules and three accessors took the port from 370 to 210.
Each is a piece of design rather than a heuristic:

* **`vecGetVec`**, typed `(-> (Vec a) Int (Vec b))`, with the cast at
  the return. Some of this compiler's vectors are heterogeneous by
  construction. `pruneMark`'s `ctx` has an interner in slot 0 and
  vectors in slots 1 to 3, so no element type describes it. Retyping
  the container is wrong; the *read* is what needs the type. The result
  variable is `b`, not `a`, because what the vector holds and what one
  slot holds are different questions, and pinning lets each call site
  answer its own.
* **`vecPushStr` and `vecPushVec`** solve the same problem for writes.
  They exist instead of a call-site cast because of MM-VAL-22.
  `(vecPush r (cast Int s))` type-checks and is a use-after-free.
  `vecPush`'s element parameter is a type variable, a cast at an
  argument root there classifies the evidence 0, and `memSetWord`'s
  `__retainref` then emits nothing. The vector holds a `String` whose
  share nobody took. So the accessor takes the share explicitly and
  pairs it with the cast. That is one retain here, and the one `vecPush`
  would have taken is exactly the one the cast suppresses, so the count
  matches a `(Vec String)` push.
* **The let-init typed view.** `(let ((v (nodeB t))) ... (vecLen v))`
  is fixed at the binding, not at each use. On its own it took the
  count from 1,531 to 1,068.
* **Discarding a container result.** `vecPush` answers the handle, so
  `(if c 0 (vecPush ...))` has two types where it had one. The value
  was always discarded there, and `{ (vecPush ...) 0 }` says so.

### The error count is the wrong measure, and that is why every search stalled

A correct coupled change *raises* the error count. Typing
`parseNamedFieldTypes`'s `names` as `(Vec String)` is right, and it
turns every call site red. So a search that accepts a move only when
errors drop rejects the correct move every time. Every plateau above
came from that measure, not from the port.

The measure that only ever falls is how many *declarations* the
errors touch. Fixing one removes it and adds only the callers that
were always going to need fixing, so the count falls even while the
error count rises. We switched the objective and fanned the trials out
across eight workers, because each trial is a convergence pass. That
moved a search that had been stuck at 210 for hours:

```text
149 declarations / 202 errors   ->   130 / 181
```

A second bug was hiding inside the first. The trial's rollback
restored the *file* it had edited but not the tree, while its
convergence pass had rewritten dozens of other files. So a round that
kept two moves came out 37 declarations worse than it started, and
read as evidence against the method. It was evidence about the harness.

The plateau was real, at 130 declarations. The search accepted one
move a round rather than none. That would close the port in about a
hundred rounds of eight minutes each, which was not a plan.

The candidates were the limit. They come from positions an error
already names, and a coupled fix needs the positions that have no error
*yet*. That calls for the whole-chain inference this record keeps
arriving at, and the next subsection measures why that would not have
closed it either.

What actually closed it, from 181 to zero, was reading. Three readers
took the 130 declarations and decided each one's element type from the
code around it: what the vector is pushed, what its elements are used
as, what the function is for. Three fixers applied the decisions and
the call-site changes they coupled to. That is not a rule the driver
was missing. The driver's 4,432 → 181 is what automation was worth
here, and it was worth a great deal. The last 181 took people.

### Why whole-chain inference cannot close it either, measured

The obvious next move was an inferencer over the source graph. Its
nodes are declaration positions, its edges are the places the language
forces two of them to agree, and it runs union-find, solves once and
writes once. We built it. It decides 417 positions from the source
alone, taking the count from 4,432 to 3,889 in one pass with no
error-driven guessing. Then it stops, and the reason matters more than
the inferencer.

The classes come out as one giant component. Generic positions have to
be excluded, because `vecAppendFrom : (-> (Vec a) ...)` is one
declaration every vector in the program is passed to, and unifying
through it merges them all. Even with them excluded, the largest class
is 8,866 of about 12,000 positions.

Modelling `Int` as a real type, rather than as "undecided", doesn't
break it up either. A `Vec` refines a word, so every `Int` position
that touches any container joins the same class, and 11,457 end up in
one.

That is not a defect in the solver. It is the answer. The compiler
passes an undifferentiated machine word everywhere, and inference can
only recover what the program still says. The positions it can decide
are exactly the ones where something concrete is stored, such as a
`String` literal pushed or a nested container read back. Those are the
417.

For the rest, the source has erased the distinction, so there is
nothing to infer. `(Vec Int)` is the truthful answer there, and it is
already what the driver writes.

So the residue was not waiting on a better algorithm. It was 130
declarations whose element type is known to a reader and to nobody
else, and closing the port meant someone deciding them.

The structural plateau shows the same thing. At 210 the same wall
stands, and it is now possible to say exactly what it is: the port
needs a declaration and its callers to change together, and nothing
available decides both.

Fixing a parameter from how its body uses it (`reparam`) is right, and
turns every call site red. Propagating that back to the callers
(`argfix`) is also right, and turns *their* callers red. Run together
and unjudged for twenty rounds, they oscillate between 219 and 238
errors and never reach 210. Each is correct locally, and neither
closes.

The original four experiments show it too. Restarting from a clean
tree with every rule available lands at 370, and the incremental run
reached 354. Applying every candidate at once goes to 5,611. Applying
only the 183 positions every error agrees about goes to 5,462. Trying
candidates one at a time with a full convergence lookahead, serially or
across eight workers, buys about two errors a round.

So the residue is not a rule nobody has written. At that stage it was
~370 errors over 224 declarations, each needing a decision about what a
particular vector holds, and the decisions are coupled. Typing
`parseNamedFieldTypes`'s `names` as `(Vec String)` raises the count
until every caller moves with it. That is why one-at-a-time
verification rejects it, and why bulk application, which moves every
position including the wrong ones, is worse still.

The head of the list was the compiler's context constructors: `newCG`,
`tcNew`, `smNew` and `symbolsRenderGens`. They built records of many
`Vec` fields through raw words. The widest single shape was 44
`vecPush` sites whose element is a `String`, in a vector the port had
typed `(Vec Int)`.

A `cast` at those sites is not the way out, and the memory model says
why. `(vecPush v (cast Int s))` would typecheck, and `vecPush`'s
element parameter is a type variable, so MM-VAL-22 applies: a cast at
an argument root in a type-variable position classifies the value's
evidence 0 and suppresses the retain. The `String`'s share would never
be taken. The right fix is the element type.

This section once predicted that "what would finish it is element-type
inference over declaration positions". That prediction is withdrawn,
and it was the last wrong one the section made. The proposal was a
union-find over parameters, results and fields, seeded by certain
sites such as a `String` literal pushed or an `Int` arithmetic use, and
propagated through calls: §4d's pinning, one level up. It is the
inferencer measured above.

**`vecPop` was a second `vecGet`**, which §4 did not name, and its fix
has landed. Its body answered `0` on an empty vector, and under
`(-> (Vec a) a)` that fabricates an `a` exactly as `vecGet`'s sentinel
did. It took the same answer, `__indexTrap` at status 77. `vecLast`
inherits the trap for free, because it delegates to `vecGet`. Nothing
else in the module has the shape. This is the port's one behaviour
break, as opposed to a retype, and `compat/BREAKING` declares it as
one. Tested by `tests/stdlib/465-pop-empty-trap.ax`.

## 4d. The migration's premise only half holds, measured

`(Vec a)` exists to stop a caller putting an `Int` in and taking a
`String` out. Before pinning, it did that only where a declaration
stated the element type. Everywhere else it left a hole with the same
shape that `AX3040` was promoted to an error for. [Pinning,
built](#pinning-built) closes it.

Four probes, run against a migrated `Vec.ax` before pinning:

| The program | `check` | Runs |
|---|---|---|
| push a `String` into a declared `(Vec Int)` parameter | refused | — |
| pass a `(Vec Int)` where `(Vec String)` is declared | refused | — |
| read an element through a declared return type at the wrong type | refused | — |
| `(let ((v vecNew)) { (vecPush v 42) (needVec (vecGet v 0)) })` | OK | **exit 139** |

The last row has no `cast` in it. An `Int` goes in, a `(Vec Int)`
comes out, and `vecLen` dereferences 42 as a block header. That is
`conjure`'s exit 139, reached without the coercion that `AX3040`'s own
help text says is the only way to produce it.

The cause was that the checker didn't unify. `tyCompat` was a
compatibility predicate: it answered 1 or 0 and recorded nothing. A
minted placeholder "still matches anything — that is the whole reason
it exists". Because no binding was ever written down, `(Vec _a)` was
compatible with `(Vec Int)` and then, just as happily, with
`(Vec String)`. The let-bound vector's placeholder was never pinned,
because each `vecPush` matched against its own fresh one.

This isn't a general unifier defect, and that narrows the fix. A
user-defined `(Box a)` behaves: `(needStr (unbox (MkBox 42)))` is
refused, because the constructor hands over a concrete `(Box Int)` and
nothing has to be remembered. `(-> a a)` behaves for the same reason.
The hole needs a placeholder that outlives the expression that could
have pinned it, and a `let`-bound mutable container is exactly that.

So `Vec` isn't the subject here. Any parameterised type reached
through an un-annotated `let` had the hole. `Vec` is where it bites,
because a container is the thing you bind and then mutate.

**The decision: the migration must not land before pinning exists.**
Landing it first would replace a visible unsafety with an invisible
one. Without the migration, reading an element back at a reference type
is spelled `vecGetStr` or an explicit `cast`, and `#raw` or `AXSYM` can
list every such site. After it, `(vecGet v 0)` would silently become
whatever the context asked for. The type-level win at declared
boundaries is real and worth having: it is the first three rows above.
It isn't worth buying with the fourth.

### Pinning, built

A placeholder minted by instantiation now binds. Word 2 of a
`TAG_T_VAR` node is 0 until something pins it. `parser.ax` documents
that tag as `a=name`, and every consumer dispatches on the tag and
reads only the name, so the slot aliases nothing. `tyCompat` resolves
both sides before it dispatches, and `tyVarCompat` pins instead of
merely matching. All four probes above reverse: the two unsound rows
are refused, and the two sound ones still pass.

Four obligations make pinning sound, and each one is a rule in the
code:

1. **Only an instantiation placeholder binds.** `freshTVar` mints
   placeholders for two different jobs, and only one of them may be
   pinned. Instantiating a declared signature mints "the type the
   caller chose for `a` here", and two uses of one binding must agree
   about that. Every other use, such as a pattern binder or a missing
   parameter type, mints "not known". Pinning that would report an
   error where the checker simply has no information. The name tells
   them apart: `_iN` binds, `_tN` doesn't, and the empty-named
   `mkSilentWild` never does.
2. **Nothing binds to poison.** `TAG_T_ERR` is compatible with
   everything, so that one error doesn't cascade. Pinning to it would
   spread the error instead of stopping it.
3. **The occurs check is required.** Binding `_i` to a type that
   contains `_i` builds a cycle, and `tyResolve` and the reference-map
   walk would both follow it forever. The comparison must also fail
   with `AX3004`. Declining to record the binding while reporting
   success loses a real constraint: a vector could contain itself, and
   a later push could pin its element type to `String`, accepting a
   container as a string without any `cast`. Direct and indirect
   recursive equations are refused. Finite nested vectors and nominal
   recursive data types still work. `check-type-pinning.sh` runs both,
   and requires the recursive equations to emit `AX3004` rather than
   fail for some unrelated reason.
4. **There is no backtracking.** Binding is monotone, so it is sound
   only if no caller tries a match and then discards it. All 53
   `tyCompat` call sites were read. Each one reports on failure or
   walks positional arguments, and none speculate.

Pinning was nearly inert on the tree it landed on, which made it safe
to land ahead of the port. Only 47 of 4,434 signatures in `self_host/`
and `stdlib/` mentioned a source type variable at all, so almost
nothing was instantiated and almost no placeholder existed to pin. The
fixpoint from the seed stayed byte-identical, `check-self-host` passed
179/179, `check-diagnostics` passed 194/194, and no gate moved,
`check-stdlib-selfhost` included.

Pinning is per binding. Two containers from the same polymorphic
constructor may be pinned to different element types in one scope.
`scripts/check-type-pinning.sh` checks this: a global substitution
passes every other check in it and fails that one.

One thing pinning doesn't change. An undeclared function still can't
be used at two types: `(fn (untyped x) x)` applied to an `Int` and then
a `String` is refused. It was refused before pinning too. That is an
existing rule about inference without generalisation, recorded here so
that nobody attributes it to pinning.

## 5. The order

1. **`Vec` as a type, and `AX3040` narrowed.** Landed.
2. **`vecGet` traps.** Landed. The seed carries `__indexTrap`, and
   `vecGet` calls it on an out-of-range index (status 77).
3. **The field-shape defect.** Landed. It wasn't on this list until a
   migration attempt found it (see §4b). It is a prerequisite: until
   `fldClass` classifies `Vec`, every record that holds one leaks its
   other fields.
4. **Pinning a placeholder.** Landed. Without it, an un-annotated
   `let` over a container stayed unpinned, and `(vecGet v 0)` answered
   whatever the context wanted (§4d: `check` OK, exit 139). It had to
   come before the migration, which would otherwise have traded a
   visible unsafety for a silent one.
5. **The migration.** Landed, 4,432 errors to zero. It wasn't the
   mechanical change this document assumed, and the checker didn't
   drive it to the end. §4c's driver reached 181 errors over 130
   declarations and stopped, and people decided the rest. The
   acceptance test this document proposed, byte-identical IR, was
   itself wrong and is corrected in §3. The fixpoint (stage2 against
   stage3, byte-identical) is the test that held.
6. **`for` as a keyword.** Landed. One keyword has two shapes, told
   apart by arity, and the parser desugars it to the `let`/`while`/`set`
   loop people already wrote by hand (`parseForExpr`,
   `self_host/parser.ax`). The container form reads through
   `Vec::vecGet`, the read that item 5 gave an element type.
   `tests/stdlib/466-for-loop.ax` pins twelve terms, and the two loop
   macros the HTML DSL carried for one idea are deleted. Nothing
   remains on this list.

## 6. A route that was tried and is the wrong one

Before `Vec` was seeded as a type, the obvious move looked like a
wrapper: `(data Vec (a) (MkVec Int))`, since `axiom-bindgen` already
wraps every opaque Rust type that way. A wrapper costs a heap block. On
`(data Box (MkBox Int))` that is `axiom_alloc(16)` plus four stores.
So it was prototyped as a *transparent newtype*: one constructor with
one field, represented as the field itself. That works and costs
nothing. `mk` becomes `mul; ret`, the fixpoint holds, and the checks
pass 96/96, 179/179 and 194/194.

It is still the wrong route, and two measurements show why:

- **`fldClass` answers from the type name.** A `data` name classifies
  as a reference, because a type name can't reach its constructor's
  entry (`lookupType` is keyed by constructor). A transparent value is
  the field itself. So a newtype over `Int`, classified as a reference,
  hands `axiom_release` an integer to read as a block header.
- **`Handle` has an identity the FFI relies on.** Restricting the
  newtype to reference fields avoids the first problem, but breaks
  `tests/ffi/demo/060-opaque-handle.ax` with
  `exit 73, handle is closed`. `Handle` carries a close/inert protocol. The wrapper and
  the handle were two identities, and collapsing them makes a close
  through one visible through the other.

Seeding `Vec` as an abstract type needs neither: no wrapper, no
allocation and no reclassification. The newtype work is not in the
tree.

## 7. Status

`Vec` is a type, `AX3040` is narrowed, and §4 is built. `vecGet`
refuses an out-of-range index through `(__indexTrap)` at status 77, and
the seed carries both. `vecTry` remains the checked read.

§4b is built and checked. `fldClass` classifies `Vec` as class 0, so a
record holding one keeps the reference map for its other fields. That
was a live defect from the day `Vec` became writable. The fix is
byte-for-byte inert for every existing program, and
`scripts/check-vec-field-shape.sh` would notice the defect coming back.

Pinning is built (§4d), which lifts the block §4d described. A
let-bound container is pinned by its first use, and the exit-139
program is refused. `scripts/check-type-pinning.sh` holds it.

The migration has landed. `stdlib/Vec.ax` hands out a parameterised
`(Vec a)`, and the 4,432 errors that produced are at zero. `stdlib/`,
every REPL module and the whole closure of `self_host/main.ax`
typecheck clean. The `tests/stdlib/` corpus passes against its goldens.
The self-hosting fixpoint holds: stage2 and stage3 are byte-identical
at 201,920 lines of emitted IR.

How the migration closed is itself a finding. §4c's mechanical driver
took it from 4,432 errors to 181 errors over 130 declarations, and
stopped. It didn't stop for want of a rule. §4c measures four
experiments and a whole-chain inferencer against that wall. The
inferencer's own answer is that the source has erased the distinction
at those positions, so there is nothing left to infer. Three readers
then decided the 130 element types from the code, and three fixers
applied them, with the call-site changes each one was coupled to.
Automation was worth 4,432 → 181, and people were worth 181 → 0. §4c is
kept in full because it records which is which.

The IR is not byte-identical, so §3's acceptance test is corrected
rather than met. The emitted IR went from 200,155 lines before the
port to 201,920 after, with `__evw` on 157 `define` lines against 36. Typing
these containers created genuinely polymorphic parameters, and each one
carries an evidence word so that ARC can decide at run time whether it
holds a reference. That is the memory model working on types that
didn't exist before the port, so it isn't a regression. The acceptance
test that survived is the fixpoint.

`compat/BREAKING` declares the port's 0.6.4 breaks: 39 that the census
sees, and eleven `Tui` names it can't. `vecPop` is the only behaviour
break among them. It answered `0` on an empty vector, and now refuses
at status 77, for the same reason as `vecGet`.

Nothing from §6 is in the tree, and neither is §4c's inferencer.

`for` is a keyword, and the list is closed. Item 6 is the reason this
document exists: its opening paragraph says a container loop can't be
a keyword until a container has an element type. It landed on top of
item 5, as one head with two forms, a range marked by `..` and a
container:

- `(for i in lo..hi body)` loops over a range.
- `(for x in xs body)` loops over a `(Vec a)`.

The parser desugars both, so no consumer of the AST changed, and both
ends are read once before the loop. The element read is the qualified
`Vec::vecGet`, so it is the polymorphic accessor the port typed, and
not a per-type spelling. The HTML DSL's `for` and `forInt`, the two
macros for one idea that the opening paragraph names, are deleted
without moving a call site. `tests/stdlib/466-for-loop.ax` holds the
terms, and `tests/diagnostics/625-for-shape` and
`626-for-not-a-container` hold the two refusals.

In-tree code uses the keyword too. The seed predated it, and
`scripts/reseed.sh` states the order: land the construct, reseed, then
use it. The prelude's `range` macro, the one-shape loop the keyword
replaced, is gone, so `for` is the only counted loop.
