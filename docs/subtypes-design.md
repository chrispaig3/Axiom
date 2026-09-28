# Range-constrained subtypes — the design pass, and what it costs

This record covers Ada-style range-constrained subtypes in Axiom: how
they are checked, how many places would use one, what the check costs,
and what stood in the way. The design pass recommended against building
them as a type. They were built anyway, and this page keeps both the
case and the reversal. For how to use them, see
[the reference](reference.md#range-constrained-subtypes).

The Ada feature is this:

```ada
subtype Positive is Integer range 1 .. Integer'Last;
```

It was the third Ada item after checked arithmetic
([`checked-arithmetic-design.md`](checked-arithmetic-design.md)) and
pre/post contracts ([`contracts-design.md`](contracts-design.md)).
Every number below carries the command that produced it.

| Date | Event |
|---|---|
| 2026-08-31 | Design pass. Recommends a `pre` on the parameter instead of building subtypes as a type. |
| 2026-09-04 | First re-measurement. Condition 1 (a value analysis) is met by LLVM for the loop shape. A stale census is refreshed, and the contract trap's status collision is found. |
| 2026-09-08 | Second re-measurement. Decision D2 (roadmap item 11) refuses subtypes as a type (`ERR-REC-8`). Decision D3 moves the contract trap to status 80. |
| 2026-09-09 | Built by direction, superseding D2. |

<a id="what-the-feature-would-be"></a>

## What the feature is

A subtype is a named type whose values are a subset of another type's.
A predicate gives the subset, and the compiler checks it at every
*conversion* into the subtype, not at every use. In Ada,
`X : Positive := Y;` with `Y : Integer` is a checked assignment. `Constraint_Error`
is raised at that assignment, not at whatever later use would have gone
wrong.

The value is that the check sits at the boundary instead of being
scattered through the body. It is the value a `pre` has, moved from a
declaration to a type.

As built, a subtype is declared over `Int`:

```scheme
(subtype Positive is Int range 1 .. 10)

(:: takePos (-> Positive Int))
(fn (takePos x)
  x)

(:: main Int)
(fn (main)
  (+ (takePos 7) (takePos 99)))
```

```text
$ axiom run positive.ax 2>/dev/null; echo $?
80
```

The range is half-open, so `1 .. 10` accepts 1 to 9. `(takePos 7)`
passes its check. `(takePos 99)` is out of range, so the call traps
with the contract trap's status, 80, before the body runs. Narrowing conversions are checked: an explicit `cast`, a call
argument and a declared return. Widening, such as `(cast Int p)`, is
free. A lower-only range, `(subtype NonNeg is Int range 0)`, checks
`>=` with no upper bound. Arithmetic on subtype values computes in the
base type, so adding two `Positive` values gives an `Int`.

Tested by `tests/selfhost/134-subtype-checked.ax` and `135-subtype-violated.ax`.

## Question 1 — how would it be checked?

At run time, by the machinery `AX3050` already ships. That answer
decides the rest of this record.

This compiler has no value analysis:

```text
$ for f in self_host/typecheck.ax self_host/codegen.ax self_host/expand.ax; do
    grep -v '^ *;' $f | grep -c 'constFold\|constantFold\|interval\|rangeOf\|abstractVal'
  done
0
0
0
```

[`contracts-design.md`](contracts-design.md) opens with the same
measurement. Comment lines are excluded for the same reason there: the
sentence making the claim matches the pattern it quotes.

The consequence is the same too. `1 .. Int'Last` is a statement about a
value. A conversion into `Positive` can't be discharged statically for
an argument the compiler hasn't seen, which is every argument that isn't
a literal. So a subtype is checked the way a contract is: a compare, a
branch and a trap.

That means the feature was already half-built. `__contract` is the
primitive, `@__axiom_contract_fail` is the trap, and `expLowerContracts`
is the pass that writes the check into the body. A subtype adds no new
enforcement mechanism. It adds a different *attachment point* for the
same check, and that is where both the cost and the argument against it
lie.

The design pass took the trap's exit status to be 76. That was wrong
twice over, and the second error was a defect in the contracts feature.
See [The status this note got wrong](#the-status-this-note-got-wrong-and-what-that-turned-out-to-be).

## Question 2 — how many places would carry one?

Measured over `self_host/` and `stdlib/`, pairing every top-level
`(:: f (-> ...))` with its `fn` header so that parameter names and
types line up:

```text
functions with a signature and a header: 3691
Int-typed parameters:                    6720
of those, index/length/count-named:      1305   (19.4%)
functions carrying at least one:         1179
```

The name census behind the 1,305: `i` 694, `n` 207, `pos` 129, `off`
47, `k` 33, `len` 31, `idx` 25, `width` 25, `j` 21, `start` 19, `cap`
19, `at` 14, and a tail. These four counts come from the design pass
and were not re-run.

The range checks already written at those positions, over the same
corpus:

```bash
grep -ohE '\((<|<=|>|>=) [a-zA-Z_][a-zA-Z0-9_]* 0\)' self_host/*.ax stdlib/*.ax | wc -l
grep -ohE '\((<|>=) [a-zA-Z0-9_]+ \((vecLen|strLen) [a-zA-Z0-9_]+\)\)' self_host/*.ax stdlib/*.ax | wc -l
```

| Count | Design pass | First re-run | Second re-run |
|---|---|---|---|
| comparisons against 0 | 499 | 538 | 509 |
| comparisons against `vecLen`/`strLen` | 780 | 887 | 897 |

The tree grew between runs, and the shape of the answer held. At the
first re-run the case for the feature was, if anything, slightly
stronger. In the second re-run, the first count fell while the tree grew: sites were
refactored faster than they were added. That supports the
recommendation below. Hand-written range checks churn with the code
around them, while the boundary they guard doesn't.

So the population is real. About a fifth of this compiler's `Int`
parameters are numbers with a range, and roughly 1,300 hand-written
comparisons already assert those ranges one site at a time. That is the
case for the feature, and the strongest thing that can be said for it.

## Question 3 — what would it cost, and where

A contract is checked once per call, at the callee. A subtype is
checked at every conversion. Those are different populations, and the
second isn't bounded by the number of declarations that carry the
annotation.

For a parameter the two coincide: one check on entry. For a loop
counter they don't. In `(fn (loop i n) (if (>= i n) 0 (loop (+ i 1) n)))`
with `i : Index`, the check runs once per iteration. `(+ i 1)` is an
`Int`, and storing it back into an `Index` is a conversion.

That cost can be measured directly, because a `pre` on a self-recursive
function is already a per-iteration check. `tailCallsSelf` rewrites the
self tail call into a loop, and the `pre` rides inside it. So the range
check a subtype would insert is exactly the code a `pre` emits today.
One function, two ways:

```scheme
(:: loop (-> Int Int Int))
(fn (loop n acc) (if (== n 0) acc (loop (- n 1) (+ acc 1))))
```

```text
$ axiom emit-llvm --input lp-bare.ax | sed -n '/define i64 @loop(/,/^}/p' | grep -c '^  '
20
$ axiom emit-llvm --input lp-pre.ax  | sed -n '/define i64 @loop(/,/^}/p' | grep -c '^  '   # ;@axiom:pre((>= n 0))
28
```

That's eight more lines of IR inside the loop. The hot path runs a
compare and a branch, and never enters the failing block. On the clock,
at 200,000,000 iterations and `--opt 0`, with the two binaries run
alternately five times:

```text
bare  0.51  0.51  0.54  0.56  0.56
pre   0.73  0.72  0.75  0.75  0.74
```

The check adds 37% on the median, and the two sets of timings never
overlap. The loop body is a decrement and an add, which is the worst
case and also what an index loop looks like. At `--opt 2` this loop is
constant-folded away and both binaries answer in 0.00s. So the figure
is the cost of the check where the check runs, not a claim about a
release build.

<a id="re-measured-2026-09-04-on-a-loop-that-does-not-fold"></a>

### Re-measured on a loop that does not fold

Condition 1 below needs the release-build cost, and measuring it takes
no new analysis. It needs a loop LLVM can't reduce to a closed form.
This one has the same shape and the same `pre` standing in for the
range check. The body is a multiply and a remainder, so scalar
evolution has nothing to solve, and the trip count comes from `sysArgc`
so it isn't a constant:

```scheme
(fn (loop n acc) (if (== n 0) acc (loop (- n 1) (% (* acc 31) 1000003))))
```

At 10^8 iterations, with the two binaries run alternately, in `user`
seconds:

```text
--opt 2   bare     0.61  0.61  0.67
          checked  0.61  0.63  0.61
--opt 0   bare     1.14  1.07  1.08
          checked  1.11  1.10  1.11
```

At both `--opt 2` and `--opt 0` the timings overlap. The check is one
`icmp` and one `br` against a value the loop already constrains. Neither
the backend nor the branch predictor charges for it here.

This doesn't refute the +37%. This body does a multiply and a
remainder where the original does an add, so the check is a much
smaller share of the work. On a body that is one `add`, a compare and
a branch really are a third of the work, and that measurement stands.

The narrower claim is the one condition 1 asks for. The release-build
cost is not measurable, and the value analysis that discharges the
check belongs to the backend, not to anything this compiler has to
grow. A subtype on a hot index loop costs what a `pre` costs. At
`--opt 2` that is nothing this instrument can see.

That moves condition 1 from unmet to "met by LLVM, for the loop shape".
It doesn't move conditions 2 and 3, and the recommendation below still
rests on those two.

One cost holds either way. A contract can be left off a declaration,
but a subtype can't be opted out of per declaration. The constraint
travels with the type, so every caller of every function taking an
`Index` pays, whether or not it wanted the check.

## Question 4 — the blocker, and it is not the cost

`cast` launders the constraint, and `cast` is everywhere:

```bash
grep -oh '(cast Int' self_host/*.ax stdlib/*.ax | wc -l
grep -oh '(cast [A-Za-z]' self_host/*.ax stdlib/*.ax | wc -l
```

| Count | Design pass | First re-run | Second re-run |
|---|---|---|---|
| `(cast Int ...)` | 441 | 780 | 796 |
| `(cast T ...)`, any type | 651 | 1,015 | 1,031 |
| `fn` declarations | 3,691 | 4,197 | 4,252 |

The re-runs count `fn` declarations with
`grep -cE '^\(pub fn \(|^\(fn \('`, and three spellings of the count
agree. Casts and declarations grew by roughly half together, so the
ratio and the argument are unchanged. The absolute number is the one
this section leans on, and it keeps growing with the tree: every cast
is a place a constraint could be laundered. That argues for a
structural conversion discipline, typed accessors, over a per-site one.

For a subtype to mean anything, `(cast Index x)` would have to be a
checked conversion, and `(cast Int i)` would have to drop the
constraint. Dropping it is correct. It is also how each of those 441
sites would silently produce an unconstrained `Int` from a constrained
one.

This repository has already recorded this failure in another system.
[`memory-model.md`](memory-model.md) `MM-VAL-23` (§3.5) says "the safe
vehicle is a typed accessor, not a call-site cast", because a cast at a
call site loses what the value was. A range constraint is evidence of
the same kind and is lost the same way. There is no `MM-VAL-23` to
protect it.

`Int` is also already doing two jobs. 5,415 of the 6,720 `Int`
parameters, 80.6%, have a name that isn't index-, length- or
count-shaped. The tree's own idiom says what most of them are: a
machine word holding a structure is spelled `Int`.

- 191 of the 441 `(cast Int ...)` sites widen a construction directly,
  as in `(cast Int (TC ...))`.
- 288 of the 341 struct fields in the tree are declared `Int`, across
  58 structs. They hold an `ASTNode`, a `Vec`, a `Span` or a handle.

So a subtype of `Int` would sit on a type that is already overloaded.
This compiler's own type-error history runs along that seam:
`Int`-as-handle colliding with `Int`-as-number.

The 80.6% is a name census, not proof that each one is a handle. The
argument doesn't need that. It needs `Int` to be a type whose values
are not all numbers, and the 288 struct fields and 191 casts show it.

## Recommendation

The design pass recommended this: don't build range-constrained
subtypes as a type. If they are wanted, write them as a `pre` that
names the parameter. That already ships, and it costs a caller nothing
it doesn't ask for.

```scheme
;@axiom:pre((&& (>= i 0) (< i (vecLen v))))
(:: at (-> Int Int Int))
```

This expresses the same constraint at the boundary that matters, the
call, with a check the compiler can actually perform. The mechanism is
already gated by `scripts/check-contracts.sh`, with 34 checks and three
ablations. A program that doesn't use it pays nothing for it, byte for
byte: `(fn (main) 7)` emits no `@__axiom_contract_fail`.

What a subtype adds over that is the *conversion* discipline: the check
at the assignment instead of at the call. That is the half `cast` can't
be trusted with and the loop can't afford.

Three conditions would change this recommendation:

1. **A value analysis.** With even an interval domain, a conversion
   whose source range is provably inside the target's is free, and the
   loop cost above collapses to the entry check. The measurement in
   Question 1 reads `0, 0, 0`. When it doesn't, re-run this record.

   This condition is met, though not by this compiler. The
   [re-measurement](#re-measured-on-a-loop-that-does-not-fold) under
   Question 3 shows the per-iteration check costing nothing measurable
   at `--opt 2` on a loop that doesn't fold. The analysis that
   discharges it is LLVM's, so a frontend interval domain isn't needed
   for the cost argument. It would still be needed to refuse a
   conversion statically, which is a different and smaller claim. This
   condition is no longer part of the case against building.
2. **A `cast` that can't launder a constraint.** Either `no-cast` on the
   constrained module, which exists and is checked, or typed accessors
   in place of the 441 `(cast Int ...)` sites. The second is the route
   `MM-VAL-23` took for the same problem.
3. **A first-class integer type that isn't the handle word.** While
   `Int` is both, a subtype of it inherits both.

None of the three is small, and none is on the release path. After
the first re-measurement, two of the three still stood, and that was
enough to keep subtypes unbuilt.

<a id="decision-d2-2026-09-08-roadmap-item-11-refused-as-a-type"></a>

## Decision D2: refused as a type

Roadmap item 11 closed range-constrained subtypes as not built,
recorded as [`error-model.md`](error-model.md) `ERR-REC-8` (R). The
sanctioned vehicle for a ranged number is `;@axiom:pre(...)` at the
boundary, which ships and is gated by `scripts/check-contracts.sh`
(34 checks, three ablations).

The case for the feature stood, re-measured: 509 hand-written
comparisons against 0, 897 against a length, and 796 `(cast Int ...)`
sites against 4,252 `fn` declarations. Two of the three reversal
conditions stood as well: a `cast` that can't launder, and an integer
type that isn't the handle word. The value-analysis condition is met
by LLVM's backend, not by a frontend domain, and it buys cost but not
static refusal. D2 said to reopen the item only by meeting the two
standing conditions, re-measured, not by re-arguing the case for it.

<a id="built-2026-09-09-d2-superseded-by-direction-not-by-measurement"></a>

## Built: D2 superseded by direction

D2 was reversed by direction, without meeting its two conditions.
`ERR-REC-8` is marked superseded.

`(subtype Positive is Int range 1 .. 10)` declares a distinct type over
`Int`. It is checked at every narrowing conversion (an explicit `cast`,
a call argument, a declared return) by the contract trap, status 80.
Widening is free. `tests/selfhost/134-subtype-checked.ax` and
`135-subtype-violated.ax` pin both halves.

Here is where the two standing conditions land under this design:

1. **The `cast` condition is met structurally, in one direction.** A
   narrowing `(cast Subtype v)` always checks, so a constraint can't be
   laundered *into* a subtype silently. A widening `(cast Int p)` drops
   the constraint visibly, which is the documented semantics. Nothing
   refuses anything yet: a program that widens and never narrows pays
   nothing and proves nothing.
2. **The integer-type condition still stands.** The base is `Int` and
   only `Int`, so a subtype inherits both of `Int`'s jobs, number and
   handle word. A ranged handle checks its range as a number. That is
   true of the word, and may not be what the author meant. Revisit this
   when a first-class integer type lands.

The cost condition stays where the re-measurement left it. The
per-conversion check costs what a `pre` costs, and at `--opt 2` that is
nothing this instrument can see.

## The status this note got wrong, and what that turned out to be

The design pass said a contract failure exits 76, taking the number
from [`contracts-design.md`](contracts-design.md). Checking it before
reusing it showed that 76 was wrong, and that the status actually
emitted, 77, was also wrong. The second was a live defect in the
contracts feature, not a transcription slip.

A violated `pre` and an `__indexTrap` both exited 77. `MM-EXEC-16` in
`memory-model.md` gives 77 to `__indexTrap`, an index out of range
([`generics-design.md`](generics-design.md) §4, pinned by
`tests/stdlib/464-index-trap.exit`). It gives 76 to `MM-ALLOC-16b`, an
arena reset past a live handle. The contract trap was documented at 76,
which belongs to the arena, and emitted 77, which belongs to the index
trap. It was the only trap in the emitter whose documented and actual
statuses disagreed. The census is
`grep -n 'emitRuntimeExit cg "7' self_host/codegen.ax`, and every other
row matched its table entry.

The contract trap was designed on 75. It moved to 76 in `4bcd7eb`,
when a merge found `MM-ALLOC-16a` already using 75. It moved again to
77 in the merge `3f2f39a`, as a conflict resolution, onto the number
`91f33f7` had given `__indexTrap` on trunk in the meantime. Its header comment in `codegen.ax` still read
`; STATUS 76, AND IT WAS DESIGNED AS 75`, two moves out of date. The
paragraph under that comment argued that "two broken invariants sharing
one status would be that defect again", which is what it had become.

Nothing caught it because each party was consistent on its own.
`scripts/check-contracts.sh` asserted 77 and passed.
`tests/stdlib/464-index-trap.exit` asserts 77 and passed. No gate
compared one trap's status with another's. `error-model.md` said a
violated contract answers 77, while `memory-model.md` said 77 was the
index trap, in two tables that never read each other.

The fix was a decision about a shipped exit status, so it wasn't made
here. There were two options. The contract trap could move to 80, the
first free number. Or the collision could be accepted, with both tables
saying so. Correcting the prose from 76 to 77 without that decision
would have written the collision into the documents meant to prevent
it.

**Decision D3: the contract trap moves to 80.** This record's reading
won. `__indexTrap` held 77 on trunk first, and the contract trap's
number was twice a merge artefact. [`ffi.md`](ffi.md) §5.1 set the
precedent: the FFI boundary took its own status, 73, so a supervisor
could tell an FFI boundary abort from an Axiom division by zero. The move changed
`emitContractTrap`'s abort code and exit from 77 to 80, added an 80 row
to `MM-EXEC-16`, and made `scripts/check-contracts.sh` assert 80 at
every `--opt` level. `tests/stdlib/464-index-trap.exit` still asserts
77, so the two traps are now told apart by status as well as by
sentence:

```text
$ axiom run half.ax 2>&1 | head -1        # a violated ;@axiom:pre
axiom: precondition failed in `half`: (> n 0)
$ axiom run half.ax 2>/dev/null; echo $?
80
$ axiom run idx.ax 2>&1 | head -1         # (__indexTrap)
axiom: vector index out of range
$ axiom run idx.ax 2>/dev/null; echo $?
77
```
