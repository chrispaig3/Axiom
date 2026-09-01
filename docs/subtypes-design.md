# Range-constrained subtypes — the design pass, and what it costs

Ada round 1 shipped restriction profiles; round 1.5 shipped checked
arithmetic (`docs/checked-arithmetic-design.md`) and pre/post contracts
(`docs/contracts-design.md`). Both of those notes recorded the same
third item as unstarted: **range-constrained subtypes**, Ada's

```ada
subtype Positive is Integer range 1 .. Integer'Last;
```

This is the design pass that has to come before any code, and its
conclusion is a **recommendation not to build it as a type**. Every
number below carries the command that produced it, over the merged tree
at `HEAD`.

## What the feature would be

A named type whose values are a subset of another type's, with the
subset given by a predicate the compiler enforces at every *conversion*
into the subtype — not at every use. In Ada that is what separates a
subtype from a comment: `X : Positive := Y;` where `Y : Integer` is a
checked assignment, and `Constraint_Error` is raised at that
assignment rather than at whatever later use would have gone wrong.

The value is exactly that the check is at the boundary and not
scattered through the body. It is the same value a `pre` has, moved
from a declaration to a type.

## Question 1 — how would it be CHECKED?

**Answered, and the answer decides the rest of the note: at run time,
by the machinery `AX3050` already ships.**

There is no value analysis in this compiler:

```
$ for f in self_host/typecheck.ax self_host/codegen.ax self_host/expand.ax; do
    grep -v '^ *;' $f | grep -c 'constFold\|constantFold\|interval\|rangeOf\|abstractVal'
  done
0
0
0
```

That is the same measurement `docs/contracts-design.md` opens with -
comment lines excluded there for the same reason, since the sentence
making the claim matches the pattern it quotes - and it has the same
consequence. `1 .. Int'Last` is a statement about a
VALUE, so a conversion into `Positive` cannot be discharged statically
for any argument the compiler has not seen — which is every argument
that is not a literal. So a constrained subtype is checked the way a
contract is: a compare, a branch, and a trap.

**Which means the feature is already half-built.** `__contract` is the
primitive, `@__axiom_contract_fail` is the trap, 76 is the status, and
`expLowerContracts` is the pass that writes the check into the body.
A subtype adds no new enforcement mechanism at all. What it adds is a
different *attachment point* for the same check — and that is where the
cost is, and where the argument against it is.

## Question 2 — how many places would carry one?

**Measured over `self_host/` and `stdlib/`.** Pairing every top-level
`(:: f (-> ...))` with its `fn` header, so parameter names and
parameter types line up:

```
functions with a signature and a header: 3691
Int-typed parameters:                    6720
of those, index/length/count-named:      1305   (19.4%)
functions carrying at least one:         1179
```

The name census behind the 1,305: `i` 694, `n` 207, `pos` 129, `off`
47, `k` 33, `len` 31, `idx` 25, `width` 25, `j` 21, `start` 19, `cap`
19, `at` 14, and a tail.

And the range checks those positions are already written with, over the
same corpus:

```
$ grep -ohE '\((<|<=|>|>=) [a-zA-Z_][a-zA-Z0-9_]* 0\)' self_host/*.ax stdlib/*.ax | wc -l
499
$ grep -ohE '\((<|>=) [a-zA-Z0-9_]+ \((vecLen|strLen) [a-zA-Z0-9_]+\)\)' self_host/*.ax stdlib/*.ax | wc -l
780
```

So the population is real: about a fifth of this compiler's `Int`
parameters are numbers with a range, and roughly 1,300 hand-written
comparisons already assert those ranges one site at a time. That is the
case FOR the feature, and it is the strongest thing that can be said
for it.

## Question 3 — what would it cost, and where

**A contract is checked once per call, at the callee. A subtype is
checked at every conversion.** Those are different populations, and
the second one is not bounded by the number of declarations that carry
the annotation.

For a parameter the two coincide: one check on entry. For a loop
counter they do not. `(fn (loop i n) (if (>= i n) 0 (loop (+ i 1) n)))`
with `i : Index` converts once per iteration, because `(+ i 1)` is an
`Int` and storing it back into an `Index` is a conversion.

**That cost is measured, not estimated, because a `pre` on a
self-recursive function ALREADY is a per-iteration check.**
`tailCallsSelf` rewrites the self tail call into a loop and the `pre`
rides inside it, so the range check a subtype would insert is exactly
the code a `pre` emits today. One function, two ways:

```scheme
(:: loop (-> Int Int Int))
(fn (loop n acc) (if (== n 0) acc (loop (- n 1) (+ acc 1))))
```

```
$ axiom emit-llvm --input lp-bare.ax | sed -n '/define i64 @loop(/,/^}/p' | grep -c '^  '
20
$ axiom emit-llvm --input lp-pre.ax  | sed -n '/define i64 @loop(/,/^}/p' | grep -c '^  '   # ;@axiom:pre((>= n 0))
28
```

Eight more lines of IR inside the loop, of which the hot path executes
a compare and a branch; the failing block is never entered. On the
clock, 200,000,000 iterations at `--opt 0`, the two binaries run
alternately five times:

```
bare  0.51  0.51  0.54  0.56  0.56
pre   0.73  0.72  0.75  0.75  0.74
```

**+37% on the median, and the arms never interleave** — on a loop whose
body is a decrement and an add, which is the worst case and is also
what an index loop looks like. At `--opt 2` this particular loop is
constant-folded away entirely and both binaries answer in 0.00s, so the
figure above is the cost of the check where the check runs, not a claim
about a release build.

What can be said without it: unlike a contract, a subtype cannot be
opted out of per declaration. The whole point of the constraint is that
it travels with the type, so every caller of every function taking an
`Index` pays, whether or not that caller wanted the check.

## Question 4 — the blocker, and it is not the cost

**`cast` launders the constraint, and `cast` is everywhere.**

```
$ grep -oh '(cast Int' self_host/*.ax stdlib/*.ax | wc -l
441
$ grep -oh '(cast [A-Za-z]' self_host/*.ax stdlib/*.ax | wc -l
651
```

651 casts against 3,691 `fn` declarations. `(cast Index x)` would have
to be a checked conversion for the subtype to mean anything, and
`(cast Int i)` would have to lose the constraint — which is correct and
is also how every one of those 441 sites would silently produce an
unconstrained `Int` from a constrained one. This repository has already
recorded this exact failure in another system: `docs/memory-model.md`
`MM-VAL-23` (§3.5) says "the safe vehicle is a typed accessor, not a
call-site cast", because a cast at a call site loses what the value
was. A range constraint is evidence of the same kind and dies the same
way, and there is no `MM-VAL-23` for it to hide behind.

**And `Int` is already doing two jobs.** 5,415 of the 6,720 `Int`
parameters — 80.6% — carry a name that is not index-, length- or
count-shaped, and the tree's own idiom says what most of them are: a
machine word holding a structure is spelled `Int`. 191 of the 441
`(cast Int ...)` sites widen a construction directly (`(cast Int (TC
...))`), and **288 of the 341 struct fields in the tree are declared
`Int`** — an `ASTNode`, a `Vec`, a `Span`, a handle — out of 58
structs. So a subtype OF `Int` would sit on a type that is already
overloaded, and this compiler's own type-error history is exactly that
seam: `Int`-as-handle colliding with `Int`-as-number.

The 80.6% is a name census and not a proof that each one is a handle;
what is proved is the two-jobs claim, by the 288 and the 191. The
distinction matters here, because the argument does not need every one
of the 5,415 to be a handle — it needs `Int` to be a type whose values
are not all numbers, and 288 struct fields say so.

## Recommendation

**Do not build range-constrained subtypes as a type. Build them, if
they are wanted, as a `pre` that names the parameter — which is what
shipped on 2026-08-31 and costs a caller nothing it does not ask for.**

```scheme
;@axiom:pre((&& (>= i 0) (< i (vecLen v))))
(:: at (-> Int Int Int))
```

That expresses the same constraint, at the boundary that matters (the
call), with the check the compiler can actually perform, in a
mechanism that is already gated (`scripts/check-contracts.sh`, 34
checks, three ablations) and that a program which does not use it pays
nothing for, byte for byte (measured: `(fn (main) 7)` emits zero
`@__axiom_contract_fail`).

What a subtype would add over that is the *conversion* discipline —
the check at the assignment rather than at the call — and that is the
half `cast` cannot be trusted with and the loop cannot afford.

**What would change this recommendation**, stated so that it is a
condition and not a mood:

1. **A value analysis.** With even an interval domain, a conversion
   whose source range is provably inside the target's is free, and the
   loop cost above collapses to the entry check. The measurement above
   is `0, 0, 0`; when it is not, this note should be re-run.
2. **A `cast` that cannot launder a constraint** — either `no-cast` on
   the constrained module, which exists and is checked, or typed
   accessors in place of the 441 `(cast Int ...)` sites, which is the
   route `docs/memory-model.md` `MM-VAL-23` took for the same problem.
3. **A first-class integer type that is not the handle word.** While
   `Int` is both, a subtype of it inherits both.

None of the three is a small piece of work, and none of them is on the
release path. This note exists so that the item stops being carried as
"unstarted" and starts being carried as "designed, and deliberately not
built, for three reasons that are each a measurement".
