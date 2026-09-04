# Pre/post contracts — design and measurement

Ada round 1 shipped restriction profiles and `AX3049`/`AX3051`/`AX3052`;
`restrict(no-wrap)` followed in 0.6.0
(`docs/checked-arithmetic-design.md`). That note recorded three items
still unstarted: **pre/post contracts**, range-constrained subtypes
(`docs/subtypes-design.md` since 2026-08-31: designed, measured, and
recommended against as a type),
and checked arithmetic. This is the first, and `AX3050` was reserved
for it on 2026-08-29 — taken from between two numbers the restrictions
were spending the same day, so the contracts would land on the number
their design named (`docs/error-model.md`).

Every claim below carries the command that established it. The gate is
`scripts/check-contracts.sh`; the fixtures are
`tests/diagnostics/385-contract-malformed.ax` (the static half) and
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
$ for f in self_host/typecheck.ax self_host/codegen.ax self_host/expand.ax; do
    grep -v '^ *;' $f | grep -c 'constFold\|constantFold\|interval\|rangeOf\|abstractVal'
  done
0
0
0
```

There is no constant folder, no interval domain, no abstract value of
any kind.

**The comment lines are excluded, and that is not a thumb on the
scale.** Without the exclusion the same grep answers 1, 1, 1 on the
merged tree, and all three hits are this note's own sentence, quoted
into those three files, saying there are none. A measurement that its
own citation falsifies is worth spelling correctly rather than
quietly: the command above is the one that stays 0 as the sentence
spreads. So the refusal a `restrict` gets is *not available* for a
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
77
```

**Not behind a flag.** A check that is off by default is a comment by
default, which is the thing being refused. The three statuses
`MM-EXEC-16` reserves are 70/71/72; 73 is the FFI boundary's
(`docs/ffi.md` §5.1, taken precisely because a Rust panic and an Axiom
division were indistinguishable at 72), 74 is a `__syscallN` on a
target with no syscall ABI, and 75 is an arena reset handed an invalid
mark (`MM-ALLOC-16a`) and 76 is a reset past a live handle
(`MM-ALLOC-16b`). A violated contract gets **77**.

**It was designed on 75, it has moved twice, and the second move landed
on an occupied number.** `MM-ALLOC-16a`'s trap and this one were
written on two branches on 2026-08-31 and both took 75; the one that
had not shipped is the one that moved, to 76. It moved again to 77 in
the merge `3f2f39a`, as a conflict resolution, onto the number
`91f33f7` had given `__indexTrap` on trunk in the meantime.

**So 77 is shared, and this note's own argument indicts it.** The whole
reason for taking 73 was that two failures at one status cannot be told
apart; that is now true of a violated contract and an out-of-range
index, which differ only in the sentence on fd 2. Corrected here
2026-09-04, along with the AX3050 help text, `explain.ax`'s AX3050
page, `codegen.ax`'s header comment, `docs/reference.md`,
`docs/error-model.md` and `CONTRIBUTING.md`, all of which said 76 — a
number that means `MM-ALLOC-16b`. **The status itself is not moved**,
because that is a compatibility decision rather than a correction; the
two candidates are recorded in `docs/subtypes-design.md`.

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

**And a program that states no contract still carries none of it**, on
the merged tree, which is a stronger property than this note originally
claimed and is not the emitter's doing. `pruneDeadDefs` (2026-08-31)
walks the rendered line buffer and drops every `define` no root
reaches:

```
$ axiom emit-llvm --input plain.ax | grep -c '@__axiom_contract_fail'   # (fn (main) 7)
0
$ axiom emit-llvm --input plain.ax | grep -c '^define'
12
```

The division trap and the string-equality helper are absent from the
same module for the same reason, and section 3 of the gate asserts all
three together — so a `0` there is the pruner working, not
`emitContractTrap` having quietly become conditional, which is the
failure `emitDivTrap`'s note is about.

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
F memGetWord ... #restrict=no-io,no-alloc,no-foreign #calls=__load64
F vecNew     ... #restrict=no-io,no-foreign #effects=Alloc,Mut
F vecLen     ... #restrict=no-io,no-alloc,no-foreign #calls=Mem$memGetWord
F vecGet     ... #restrict=no-io,no-alloc,no-foreign #calls=<,>=,Mem$memGetWord,...
F strLen     ... #restrict=no-io,no-alloc,no-foreign #calls=Mem$memGetWord
F strByte    ... #restrict=no-io,no-alloc,no-foreign #calls=<,>=,Str$strData,...
F strEq      ... #restrict=no-io,no-alloc,no-foreign #calls=!=,==,Mem$memCmp,...
F strConcat  ... #restrict=no-io,no-foreign #effects=Alloc,Mut
F fmtInt     ... #restrict=no-io,no-foreign #effects=Alloc,Mut
```

**Re-run against the merged tree on 2026-08-31, after the constructor
row closed** (below), because that fix moved 123 effect rows and this
measurement is the whole argument that the purity rule is livable. The
six predicate functions still carry `no-alloc` and still carry no
`#effects=` at all; the three builders still carry `Alloc,Mut`. The
rule survives its own soundness fix.

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

**A hole this check inherited, and that closed under it.** The first
draft of this note recorded a bug it could not fix inside its own
slice: a struct construction and a fieldful `data` constructor allocate
and contributed nothing to the effect row, so a contract that
constructed one was accepted. It was `restrict(no-alloc)`'s bug before
it was this check's, and `restrict(no-alloc)` is where it was fixed —
`MM-EXEC-9a`'s constructor row, closed on trunk on 2026-08-31, in the
same hours this branch was being written. Because the purity rule reads
the same row rather than a rule of its own, it inherited the fix
without a line changing here:

```
$ axiom --diagnostic-format=ai check --input ctorc.ax
E AX3050 ctorc.ax:3:13-28 contract-malformed "`(> (boxed n) 0)` is the `pre` on
  `constructs` and performs Alloc"
```

That is the `constructs` arm of
`tests/diagnostics/385-contract-malformed.ax`, and it is there because
a fix this note only *hopes* it inherits is a claim nothing checks.

### The distribution behind the ambient-`Alloc` decision

The effect-enforcement design left `Alloc` ambient and asked that the
distribution be measured before revisiting. Over the AXSYM of the
largest program there is:

```
$ axiom --diagnostic-format=ai symbols --calls --input self_host/main.ax > main.axsym
$ grep -c '^F ' main.axsym
3647
```

3,645 distinct `F` rows; 2,160 (59.3%) carry `Alloc`. But the shape of
that 59% is the fact that matters, and it is not what a declarable
claim would be about. Walking the `#calls=` graph from every
`Alloc`-carrying row to the nearest row that carries `Alloc` while no
callee of it does — the places the effect *enters*:

| hops to where `Alloc` enters | rows |
|---|---|
| 1 (it enters here) | 40 |
| 2 | 253 |
| 3 | 334 |
| 4 | 637 |
| 5 | 579 |
| 6 | 232 |
| 7 | 64 |
| 8 | 17 |
| 9–10 | 4 |

**RE-MEASURED AGAINST THE MERGED TREE, AND THE FIRST ROW MOVED FROM 3
TO 40.** The draft of this note measured 3,450 rows, 56% carrying
`Alloc`, and three entry points — `Mem.memAlloc`, `Mem.memAllocMapped`
and `lspMain`. That was a fact about a compiler in which applying a
constructor contributed nothing to the row. Since `MM-EXEC-9a`'s
constructor row closed, `Alloc` also enters at every function whose own
body constructs: `mkNode`, `mkSpan`, `mkToken`, `mkError`, `pOk`,
`vecTry`, `strFind` and the rest of the forty. **The number this note
originally reported is not merely stale, it was reported by an analysis
that could not see the commonest way to allocate**, and it is written
out here rather than quietly corrected, because a design note that
carries a number nobody re-ran is the defect three withdrawn proposals
in `docs/memory-model-v2-proposal.md` were withdrawn for.

The CONCLUSION survives the correction, which is why it is still here:
98.9% of `Alloc` rows are two or more hops from where the effect
enters, so the 59% is almost entirely *inherited*, and a declarable
`Alloc` claim would still be a claim about call-graph reachability
rather than about the body. **That claim already exists and is already
enforced: `restrict(no-alloc)`.** So the recommendation stands — not an
`AX3042` sibling. What has changed is the second half of it: the lever
that would pay was making `restrict(no-alloc)` sound, and that landed
on trunk while this branch was being written.

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

## The hazard the previous design note found, and what became of it

`docs/checked-arithmetic-design.md` states that `restrict(no-wrap,
no-alloc)` are **unsatisfiable together** for a body that adds two
numbers, because satisfying `no-wrap` means calling `addChecked`, whose
`Result` construction allocates — and that a user writing the pair gets
a confusing `AX3049` about the thing they did to comply.

**Probed on 2026-08-31 against the branch's own base, and the answer
was worse than the hazard:**

```scheme
(import Err)

;@axiom:restrict(no-wrap,no-alloc)
(:: addSafe (-> Int Int Int))

(fn (addSafe a b) (unwrapOr (addChecked a b) 0))
```

```
$ axc-0.6.0 check --input unsat.ax
OK
$ axc-0.6.0 --diagnostic-format=ai symbols --calls --input unsat.ax | grep '^F addSafe '
F addSafe ... #restrict=no-wrap,no-alloc #calls=Err$addChecked,Err$unwrapOr
```

No diagnostic and no `#effects=` at all, because a constructor
application contributed nothing to the effect row: `walkCallHead`'s
`findFnEnt` answers 0 for every constructor and the branch added
nothing, and `TAG_E_STRUCTCON` walked its fields and added nothing
either. A `restrict(no-alloc)` claim could therefore not fail, which is
the same defect as the check not existing.

### Re-run against the merged tree, and it is closed

This branch drafted the section above, measured the blast radius of a
fix on a probe compiler (six declarations refused, 113 of 3,488 rows
moving) and deferred it as a separate slice. **On trunk it was not
deferred: `MM-EXEC-9a`'s constructor row closed on 2026-08-31**, with
seven claims withdrawn and 123 of 3,725 rows moving — the seventh being
`histFindBack`, which the probe's copy-to-a-temp-directory sweep lost
to an import failure. So the numbers in the paragraph above are a
record of what was true at `9116167` and of nothing else, and the same
two programs, re-run against the merged tree:

```
$ axiom --diagnostic-format=ai check --input unsat.ax
E AX3049 unsat.ax:6:6-13 restriction-violated "`addSafe` claims `restrict(no-alloc)`
  and the body performs Alloc: addSafe -> Err$addChecked -> Err$mkError, in
  `mkError`'s own body"

$ axiom --diagnostic-format=ai check --input ctorc.ax
E AX3050 ctorc.ax:3:13-28 contract-malformed "`(> (boxed n) 0)` is the `pre` on
  `constructs` and performs Alloc"
```

Both predictions the previous note made are now the compiler's own
answer, with the path. **The jointly-impossible restriction set reports
itself**, and it does so exactly the way that note argued it should: not
from a hand-written table of pairs that conflict — which would have
gone stale the first time a restriction's own analysis moved, and would
have named two keywords instead of a place — but because each
restriction now answers honestly, so the pair renders as a call chain a
reader can go and fix.

**Nothing in this feature changed to get that.** The purity rule reads
the effect row rather than a rule of its own, which is the whole reason
it inherited a fix landed in another pass on another branch. That is
the argument for reading the row restated as a measurement.

## A hole this feature shipped with for one commit

`__contract` is the primitive the lowering writes. The first draft of
this note said it "is not a name a source program can reach, because
`isPrimName` claims it in the emitter and nothing documents it", and
the lowering leaned on that: it skipped any body that already *looked*
lowered — a block whose first statement applies `__contract`, under an
optional `result` binding — so that a second `expandProgram` over the
same declaration list would not wrap the body twice.

**Undocumented is not unreachable.** `__contract` is registered in
`fns` and intercepted by `checkApp` exactly as `__streq` is, so a
program can write it, and one that did turned its own contract off:

```scheme
;@axiom:pre((> n 0))
(:: f (-> Int Int))

(fn (f n) { (__contract true "never\n") n })

(:: main Int)

(fn (main) (f 0))
```

```
$ axc check --input h1.ax     # the branch as first written
OK
$ axc run --input h1.ax ; echo $?
0
```

The same file without that first statement exits 77. The `post` arm was
the same shape, under a `let` binding `result`. A checked claim a
program can withdraw by writing one expression is a check that cannot
fail, which is the defect this whole feature exists to prevent, and it
was in the feature itself.

**The guard is deleted rather than made cleverer, because any
shape-based test of the body is forgeable by the body.** What it bought
is measured rather than assumed: no path in this tree calls
`expandProgram` twice over one declaration list — `main.ax`, `lsp.ax`,
`repl.ax`, `symbols` and `emitModule` each parse first — and a diamond
import splices one node once (`(import B) (import C)` where both import
a contract-carrying `D` emits exactly one
`call i64 @__axiom_contract_fail`). And a doubled lowering would be
semantically a no-op anyway, since `AX3050` refuses a contract that
performs anything: evaluating a pure predicate twice cannot differ from
evaluating it once. So the guard defended a case nothing reaches
against a consequence that does not exist, and cost soundness in a case
a program can write.

Section 6 of the gate is the two programs above, and the third ablation
puts the guard back and requires section 6 to go red.

**And the check travels, which is the other half of putting it in the
body.** There is no call site for a caller to miss: a contract fires
through an indirect call (`(apply half 0)` where `apply` takes the
function as a parameter) and through a lambda (`((lambda (x) (half x))
0)`), both exit 77, because the compare is inside `half` and not at
either call.

## What shipped

| | |
|---|---|
| Keys | `pre`, `post` — already known to `axtagKnownKey`, now checked |
| Read from | the `::` and the `fn`, as one list in source order, exactly as `restrict(...)` |
| Diagnostic | `AX3050` `contract-malformed`, an error, four arms |
| Lowering | `expLowerContracts` at the end of `expandProgram` |
| Primitive | `__contract`, `(-> a String Int)`, no effect row |
| Runtime | `@__axiom_contract_fail`, emitted unconditionally and pruned where nothing calls it, exit **77** — shared with the index trap, see below |
| Fixtures | `tests/diagnostics/385`, `tests/selfhost/132`, `tests/selfhost/133` |
| Gate | `scripts/check-contracts.sh`, seven sections, three ablations |
