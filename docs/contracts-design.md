# Pre/post contracts — design and measurement

Ada round 1 shipped restriction profiles and `AX3049`/`AX3051`/`AX3052`;
`restrict(no-wrap)` followed in 0.6.0
(`docs/checked-arithmetic-design.md`). That note recorded three items
still unstarted: **pre/post contracts**, range-constrained subtypes,
and checked arithmetic. This is the first, and `AX3050` was reserved
for it on 2026-08-29 — taken from between two numbers the restrictions
were spending the same day, so the contracts would land on the number
their design named (`docs/error-model.md`).

Every claim below carries the command that established it. The gate is
`scripts/check-contracts.sh`; the fixtures are
`tests/diagnostics/384-contract-malformed.ax` (the static half) and
`tests/selfhost/132-contract.ax` / `133-contract-violated.ax` (the
run-time half).

## Question 1 — what does a contract DO?

**Answered: BOTH halves, and neither behind a flag.** The static half
is `AX3050`; the dynamic half is a check compiled into the body.

The reason is not a preference. It is what the checker can see.

`restrict(...)` is refused *statically* because the analysis that
answers it already exists: the effect row and the call graph are
fixpoints `inferEffects` computes for every program anyway, so a
`no-io` claim is answered by reading a set the compiler already built.
A contract is a different kind of claim. `(> n 0)` is a statement about
a **value**, and this compiler has no value analysis at all:

```
$ grep -c 'constFold\|constantFold\|interval\|rangeOf\|abstractVal' \
      self_host/typecheck.ax self_host/codegen.ax self_host/expand.ax
self_host/typecheck.ax:0
self_host/codegen.ax:0
self_host/expand.ax:0
```

There is no constant folder, no interval domain, no abstract value of
any kind. So the refusal a `restrict` gets is *not available* for a
contract, at any call site the compiler has not seen — and even at one
it has seen, deciding `(> n 0)` for a non-literal argument would need
machinery that does not exist and that this slice is not the place to
introduce.

This repository's standing rule is that a claim nothing checks is a
comment, and it refuses comments that read like guarantees — the
argument `AX3039`'s own note makes ("the tag reads like a guarantee and
buys silence"). Two options remain: refuse every contract the compiler
cannot decide, which is every contract; or check it at run time, which
is Ada's answer. The second is what shipped.

```scheme
;@axiom:pre((> n 0))
(:: half (-> Int Int))

(fn (half n) (/ n 2))
```

```
$ axiom run --input c2.ax     # (half 0)
axiom: precondition failed in `half`: (> n 0)
axiom: backtrace (most recent call first)
  at __axiom_contract_fail
  at half
  at __axiom_user_main
  at main
$ echo $?
75
```

**Not behind a flag.** A check that is off by default is a comment by
default, which is the thing being refused. The three statuses
`MM-EXEC-16` reserves are 70/71/72; 73 is the FFI boundary's
(`docs/ffi.md` §5.1, taken precisely because a Rust panic and an Axiom
division were indistinguishable at 72) and 74 is a `__syscallN` on a
target with no syscall ABI. A broken invariant is a fifth thing and
gets **75**, so a supervisor reading a status can tell it from a broken
machine.

**Where the lowering lives, and why not in the emitter.**
`expandProgram` — the pass whose own header says it "rewrites the
declaration list" — because it is the ONE pass every consumer of a
compiled program runs. Putting it in `codegen.ax` would need the same
call in `main.ax`, `repl.ax`, `lsp.ax` and `emitModule`, and a caller
that forgot it would be a contract that silently checked nothing.

```
;@axiom:pre(P)    (fn (f a) BODY)  ->  (fn (f a) { (__contract P m) BODY })
;@axiom:post(Q)   (fn (f a) BODY)  ->  (fn (f a)
                                         (let ((result BODY))
                                           { (__contract Q m) result }))
```

`__contract` is a primitive (`isPrimName`, `emitPrimContract`): a
compare, a branch, and a call to `@__axiom_contract_fail` in the
failing block only, so a satisfied contract costs the compare and the
branch and nothing else. The trap helper is emitted **unconditionally**
beside the division trap and the string-equality helper, for the reason
`emitDivTrap`'s own note records — a helper emitted only when the
program looks like it needs one is a call to a symbol nothing defines,
and a contract's predicate would have to be evaluated in two passes
that could disagree.

## Question 2 — purity

**Answered: a contract expression must carry no DEFINITE effect.** The
check reads the same row `restrict(no-alloc)` reads
(`effDefiniteOnly (collectEffects tc p sc)`), and a non-empty answer is
`AX3050`.

The design note that raised this question found a trap: `Alloc` is
AMBIENT in this language, not declarable, so "must not allocate" is not
expressible the way "must not do IO" is. **That is a fact about
declarability, not about the row.** Only `IO` can be written in an
`effect(...)` claim, but `Alloc` is in the effect row like any other
effect and `restrict(no-alloc)` already reads it. A compiler-internal
check needs the row, not a keyword, so nothing in the effect system had
to move.

**And it is not a blanket refusal** — measured, which is the half that
matters:

```
$ axiom --diagnostic-format=ai symbols --calls --input self_host/main.ax \
    | grep -E '^F (vecLen|vecGet|strLen|strEq|strByte|memGetWord|strConcat|fmtInt|vecNew) '
F vecLen    ... #restrict=no-io,no-alloc,no-foreign #calls=Mem$memGetWord
F vecGet    ... #restrict=no-io,no-alloc,no-foreign #calls=<,>=,Mem...
F strEq     ... #restrict=no-io,no-alloc,no-foreign #calls=!=...
F strByte   ... #restrict=no-io,no-alloc,no-foreign #calls=<,>=
F memGetWord... #restrict=no-io,no-alloc,no-foreign #calls=__load64
F strConcat ... #effects=Alloc,Mut
F fmtInt    ... #effects=Alloc,Mut
F vecNew    ... #effects=Alloc,Mut
```

Every function a predicate is written from — compare, index, measure,
test — carries an **empty** effect row. Everything that builds carries
`Alloc,Mut`. So the rule a contract lives under is *may compare, index,
measure and test; may not build*, and that is a rule real contracts can
satisfy rather than a rule that forbids the feature.

**Only a DEFINITE effect is refused.** An effect that reaches the row
only as POSSIBLE arrived because the expression NAMES an arrow-typed
function without calling it (`effRefSiteAt`), and naming one performs
nothing — so the silence there is correct, not merely conservative. A
row marked `#effects-incomplete` is a lower bound and is not evidence
either way; refusing over it would be refusing a program for a limit of
the analysis, which is `AX3037`'s argument.

**A measured hole this check inherits, and does not close.** See
"Constructor allocation" below: a struct construction and a fieldful
data constructor allocate and contribute nothing to the row, so a
contract that constructs one is not refused today. That is one bug, in
`walkEffects`, and it is `restrict(no-alloc)`'s bug before it is this
check's.

### The distribution behind the ambient-`Alloc` decision

The effect-enforcement design left `Alloc` ambient and asked that the
distribution be measured before revisiting. Over the AXSYM of the
largest program there is:

```
$ axiom --diagnostic-format=ai symbols --calls --input self_host/main.ax > main.axsym
$ grep -c '^F ' main.axsym
3452
```

3,450 distinct `F` rows; 1,935 (56%) carry `Alloc`. But the shape of
that 56% is the fact that matters, and it is not what a declarable
claim would be about. Walking the `#calls=` graph from every
`Alloc`-carrying row to the nearest allocator seed (`__alloc`, the
three arena primitives):

| hops to the allocator | rows |
|---|---|
| 1 | 3 |
| 2 | 41 |
| 3 | 115 |
| 4 | 622 |
| 5 | 756 |
| 6 | 270 |
| 7 | 99 |
| 8 | 24 |
| 9–10 | 5 |

**Three functions in the whole compiler are where `Alloc` enters** —
`Mem.memAlloc`, `Mem.memAllocMapped` and `lspMain` — and 99.8% of
`Alloc` rows are two or more hops away. The 56% is therefore almost
entirely *inherited*, and a declarable `Alloc` claim would be a claim
about call-graph reachability rather than about the body. **That claim
already exists and is already enforced: `restrict(no-alloc)`.** So the
recommendation is: not an `AX3042` sibling, and not inside this task —
the lever that would pay is making `restrict(no-alloc)` *sound*
(next section), not adding a second way to say the same thing.

## Question 3 — `result` in a `post`

**Answered:** `result` names the function's answer; its type is the
**declared** result — the signature's arrows peeled by as many
parameters as the definition has (`peelArrows`, which `tcCheckFn`
already computes for `checkDeclaredReturn`). It names nothing anywhere
else, and both "anywhere else" cases are `AX3050`:

```
$ axiom --diagnostic-format=ai check --input bad.ax
E AX3050 ...:9:16-22 contract-malformed "`result` names nothing in a `pre`:
  a precondition is checked BEFORE the body runs, so there is no result yet"
E AX3050 ...:6:17-23 contract-malformed "`result` names nothing here: this
  declaration has no `::` signature, so it declares no result type for
  `result` to have"
```

The second arm is the one `AX3050`'s reserved meaning names — "names
`result` where the declared result is absent" — and a `fn` with no
`::` is exactly that case, since such a definition gets a placeholder
type variable rather than a declared type:

```
$ printf '(pub fn (g n) (* n 2))\n\n(:: main Int)\n\n(pub fn (main) (g 3))\n' > q2.ax
$ axiom check --input q2.ax
OK
```

**How the question is asked, and why not by walking the contract.** A
hand-written walk for a `result` reference would have to mirror every
expression form, and one it missed would answer `AX3001 undefined
variable` for a shape it did not cover — a check reporting less than it
knows, which is this repository's second most-refused defect. Instead
`tc` carries the contract being checked (`inContract`, word 34) and
`checkVar` asks one question at the top: the name is `result`, we are
inside a contract, and nothing in the frame binds it. That is total by
construction, because every reference goes through `checkVar`.

## Question 4 — where the expression is checked, and what is NOT done

**Answered: the parameters are in scope in BOTH `pre` and `post`, and
there is no `'Old`.**

Ada pairs `Post` with `'Old` because Ada's parameters can be assigned,
so `X` in a postcondition is not the `X` the caller passed. Axiom's
cannot:

```
$ axiom check --input q3.ax     # (fn (h n) { (set n 5) n })
error[AX3012]: cannot assign to `n`: it is a parameter, and parameters
               are immutable
```

So for a scalar parameter the name means in the `post` exactly what it
meant in the `pre`, and `'Old` would be a synonym for the name itself.

**What is deliberately NOT done, stated rather than implied:**

- **`'Old` for a reference parameter.** A parameter's *pointee* can be
  mutated — `memSetWord` into a struct the caller still holds — and a
  `post` cannot see the pre-state of that. Snapshotting it would mean
  copying arbitrary structure at every call, which is a cost the
  language's arena model would pay on every guarded call whether or not
  the contract fails. Left out, named here.
- **Contracts on anything but a function.** No `struct` invariants, no
  loop invariants, no `type` predicates.
- **Inheritance / refinement.** There is nothing to inherit from since
  traits went in 0.6.0.
- **Static discharge.** A `pre` that a call site's literal arguments
  would refute is not refused. The fragment is decidable and the
  machinery (substitute the argument, fold, refuse a constant `false`)
  is real work with its own gate; it is a strict addition to what
  shipped and does not change anything here.

### The cost a `post` has, measured

```
$ axiom emit-llvm --input t1.ax | grep -c 'call i64 @loopA('   # bare
1                                        # main's call only: the self
                                         # tail call became a loop
$ axiom emit-llvm --input t2.ax | grep -c 'call i64 @loopB('   # let-wrapped
2                                        # main's, plus a real recursion
```

`tailCallsSelf` treats a `let`'s BODY as a tail position and its
INITIALISER as not one, which is correct. A `post` binds the body to
`result`, so the call it wraps stops being a tail call and the loop
rewrite does not fire. A `pre` is a block whose last expression is the
body, and a block's last expression IS a tail position, so it costs
nothing — `tests/selfhost/132-contract.ax` recurses 200,000 deep under
a `pre` and answers. Both directions are section 5 of the gate; the
cost is inherent to what a postcondition is (the result must be
observed) and is stated so that it is not rediscovered as a regression.

## The hazard the previous design note found

`docs/checked-arithmetic-design.md` states that `restrict(no-wrap,
no-alloc)` are **unsatisfiable together** for a body that adds two
numbers, because satisfying `no-wrap` means calling `addChecked`, whose
`Result` construction allocates — and that a user writing the pair gets
a confusing `AX3049` about the thing they did to comply.

**Probed. Today it is not what happens, and the reason is worse than
the hazard.**

```scheme
(import Err)

;@axiom:restrict(no-wrap,no-alloc)
(:: addSafe (-> Int Int Int))

(fn (addSafe a b) (unwrapOr (addChecked a b) 0))
```

```
$ axiom check --input unsat.ax
OK
$ axiom --diagnostic-format=ai symbols --calls --input unsat.ax | grep '^F addSafe '
F addSafe ... #restrict=no-wrap,no-alloc #calls=Err$addChecked,Err$unwrapOr
```

No diagnostic, and no `#effects=` at all. `addChecked` itself renders
`#calls=&,+,<,Err$errOverflow,Err$mkError,^` and **no effect row**,
although its body constructs `Ok` and `Err`.

### Constructor allocation is invisible to the effect walk

```scheme
(data Box (Wrap Int) (Empty))

;@axiom:restrict(no-alloc)
(:: mk (-> Int Int))

(fn (mk n) (match (Wrap n) ((Wrap x) x) ((Empty) 0)))
```

```
$ axiom check --input ctor.ax
OK
$ axiom emit-llvm --input ctor.ax | sed -n '/define i64 @mk/,/^}/p' | grep -c axiom_alloc
1
```

`check` says OK on a body that claims `no-alloc` and emits a call to
the allocator. The same holds for a struct construction
(`(let ((p (Pair n n))) (p.a))` — one `axiom_alloc`, `OK`), and
`addChecked` emits two.

The cause is one branch. A constructor application reaches
`walkCallHead`, whose `findFnEnt` answers 0 for every constructor —
which the branch's own comment states, and which it uses to avoid
marking the row incomplete — and then adds nothing. `TAG_E_STRUCTCON`
walks its fields and adds nothing either. `TAG_E_ALLOC`, the explicit
`alloc` form, is the only shape that seeds `Alloc` from a body.

**A `restrict(no-alloc)` claim is therefore unsound today**, and the
design note's hazard is real but invisible.

### What a fix costs, measured on a probe compiler

A probe compiler was built from a copy of `self_host/` with `Alloc`
added in `walkCallHead` for a fieldful data constructor and for a
struct construction (about fifteen lines). Against it:

```
$ axc-alloc check --input ctor.ax
E AX3049 ...:6:6-8 restriction-violated "`mk` claims `restrict(no-alloc)`
  and the body performs Alloc in its own body ..."
$ axc-alloc check --input unsat.ax
E AX3049 ... "`addSafe` claims `restrict(no-alloc)` and the body performs
  Alloc: addSafe -> Err$addChecked -> Err$mkError, in `mkError`'s own body"
```

— which is exactly the diagnostic the previous design note predicted,
with the path. And the blast radius is small:

```
# every declaration in self_host/ and stdlib/ that the probe refuses
mkDiagBase  mkSpan  mkToken  strFind  strParseInt  vecTry

# effect rows that would change, over self_host/main.ax
113 of 3488
```

**Six** false `restrict(no-alloc)` claims in the shipped tree, out of
172 `no-alloc` claims in `tests/agent/restrictions.allow`; three of
them (`vecTry`, `strFind`, `strParseInt`) construct `Some`/`None` and
three (`mkSpan`, `mkToken`, `mkDiagBase`) are struct constructions. 3%
of effect rows move.

### Verdict on the hazard: out of scope, and here is why

It is a soundness fix to `restrict(no-alloc)`, not a contracts feature,
and it lands in the pass every other claim reads. Doing it inside this
task would mean moving 113 effect rows and withdrawing six shipped
claims in the same commit that introduces a new diagnostic code — and
`check-compat`'s baseline and `tests/agent/stdlib-effects.allow` both
read those rows, so it needs its own re-bless and its own ablation
pass. It is a well-scoped follow-up with a measured cost, which is
worth more than a half-done version of it here.

What is *not* deferred is the answer to the question the hazard asked.
A jointly-impossible restriction set **is** diagnosable, and the way to
diagnose it is not a new "these two cannot both hold" check over the
closed list: it is to make each restriction answer honestly, at which
point the pair reports itself with a path — `addSafe -> Err$addChecked
-> Err$mkError` — which is a place to put the fix rather than a
statement that two names conflict. A pairwise-conflict table would have
had to be written by hand, would have gone stale the first time a
restriction's own analysis changed, and would have said less.

## What shipped

| | |
|---|---|
| Keys | `pre`, `post` — already known to `axtagKnownKey`, now checked |
| Read from | the `::` and the `fn`, as one list in source order, exactly as `restrict(...)` |
| Diagnostic | `AX3050` `contract-malformed`, an error, four arms |
| Lowering | `expLowerContracts` at the end of `expandProgram` |
| Primitive | `__contract`, `(-> a String Int)`, no effect row |
| Runtime | `@__axiom_contract_fail`, emitted unconditionally, exit **75** |
| Fixtures | `tests/diagnostics/384`, `tests/selfhost/132`, `tests/selfhost/133` |
| Gate | `scripts/check-contracts.sh`, six sections, two ablations |
