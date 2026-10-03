# Pre/post contracts — design and measurement

A `;@axiom:pre(...)` or `;@axiom:post(...)` contract is checked each
time the function runs, and a malformed one is rejected at compile time.
This record answers four design questions about contracts and records
the holes found on the way.

Contracts are one of three items left open after the first Ada-inspired
round, which shipped restriction profiles with `AX3049`, `AX3051` and
`AX3052`, followed by `restrict(no-wrap)` in 0.6.0
([checked-arithmetic-design.md](checked-arithmetic-design.md)). The
other two are range-constrained subtypes, which
[subtypes-design.md](subtypes-design.md) designed, measured and
recommended against as a type, and checked arithmetic. `AX3050` was
reserved for contracts in [error-model.md](error-model.md).

Every claim below carries the command that establishes it. The gate is
`scripts/check-contracts.sh`. The fixtures are
`tests/diagnostics/385-contract-malformed.ax` for the static half, and
`tests/selfhost/132-contract.ax` and
`tests/selfhost/133-contract-violated.ax` for the run-time half.

## Question 1 — what does a contract do?

**It does both.** The static half is `AX3050`. The dynamic half is a
check compiled into the function's body. Neither is behind a flag.

This follows from what the checker can see. `restrict(...)` is refused
statically because the analysis that answers it already exists: the
effect row and the call graph are fixpoints that `inferEffects`
computes for every program, so a `no-io` claim is answered by reading a
set the compiler has already built.

A contract is a different kind of claim. `(> n 0)` is a statement about
a *value*, and this compiler has no value analysis at all:

```text
$ for f in self_host/typecheck.ax self_host/codegen.ax self_host/expand.ax; do
    grep -v '^ *;' $f | grep -c 'constFold\|constantFold\|interval\|rangeOf\|abstractVal'
  done
0
0
0
```

There is no constant folder, no interval domain and no abstract value
of any kind. The command skips comment lines because this record's own
sentence saying so is quoted into those three files, and would
otherwise count as a hit.

So the static refusal a `restrict` gets isn't available for a
contract at a call site the compiler hasn't seen. Even at one it has
seen, deciding `(> n 0)` for a non-literal argument would need
machinery that doesn't exist.

The project's rule is that a claim nothing checks is a comment, and
comments that read like guarantees are refused. `AX3039`'s note makes
the same argument: "the tag reads like a guarantee and buys silence".
That left two options: refuse every contract the compiler can't
decide, which is every contract, or check it at run time, as Ada does.
We chose the second.

```scheme
;@axiom:pre((> n 0))
(:: half (-> Int Int))

(fn (half n) (/ n 2))

(:: main Int)

(fn (main) (half 0))
```

```text
$ axiom run --input c2.ax
axiom: precondition failed in `half`: (> n 0)
axiom: backtrace (most recent call first)
  at __axiom_contract_fail
  at __axiom_user_main c2.ax:8:13
  at main
$ echo $?
80
```

There is no flag because a check that is off by default is a comment
by default.

### Exit status 80

A violated contract exits with **80**, a status of its own. The other
trap statuses are:

- 70, 71 and 72, which `MM-EXEC-16` reserves;
- 73, the FFI boundary ([ffi.md](ffi.md) §5.1);
- 74, a `__syscallN` on a target with no syscall ABI;
- 75, an arena reset handed an invalid mark (`MM-ALLOC-16a`);
- 76, a reset past a live handle (`MM-ALLOC-16b`);
- 77, an out-of-range index (`__indexTrap`);
- 78 and 79, `parallel` failing to spawn or unavailable on the target.

The number was decided in D3 (roadmap item 11), and `MM-EXEC-16`
carries the 80 row. The trap was designed on 75 and passed through 76
and 77 before settling. At 77 it shared a status with `__indexTrap`, so
a violated contract and an out-of-range index differed only in the
sentence on fd 2.

Two failures at one status can't be told apart. That is the defect
`ffi.md` §5.1 refused when it took 73, because a Rust panic and
an Axiom division were indistinguishable at 72. `__indexTrap` held 77
first, so the contract trap moved to 80, the first free number.

### Where the lowering lives

Contracts are lowered in `expandProgram`, the pass whose header says it
"rewrites the declaration list". It is the one pass every consumer of a
compiled program runs. Lowering in `codegen.ax` would need the same
call in `main.ax`, `repl.ax`, `lsp.ax` and `emitModule`, and a caller
that forgot it would carry a contract that silently checked nothing.

```text
;@axiom:pre(P)    (fn (f a) BODY)  ->  (fn (f a) { (__contract P m) BODY })
;@axiom:post(Q)   (fn (f a) BODY)  ->  (fn (f a)
                                         (let ((result BODY))
                                           { (__contract Q m) result }))
```

`__contract` is a primitive (`isPrimName`, `emitPrimContract`). It
emits a compare, a branch, and a call to `@__axiom_contract_fail` in
the failing block only. A satisfied contract costs the compare and the
branch, and nothing else.

The trap helper is emitted unconditionally, beside the division trap
and the string-equality helper, for the reason `emitDivTrap`'s note
records. A helper emitted only when the program looks like it needs one
is a call to a symbol nothing defines, and a contract's predicate
would have to be evaluated in two passes that could disagree.

A program that states no contract still carries none of the mechanism.
That is the work of `pruneDeadDefs`, not the emitter: it walks the
rendered line buffer and drops every `define` no root reaches.

```text
$ axiom emit-llvm --input plain.ax | grep -c '@__axiom_contract_fail'   # (fn (main) 7)
0
$ axiom emit-llvm --input plain.ax | grep -c '^define'
15
```

The division trap and the string-equality helper are absent from the
same module for the same reason. Section 3 of the gate asserts all
three absences together, and that a program with a contract emits both
the call and the `define`. So a `0` there is the pruner working, not
`emitContractTrap` having become conditional, which is the failure
`emitDivTrap`'s note describes.

## Question 2 — purity

**A contract expression must carry no definite effect other than
`Unsafe`.** The check reads the same row `restrict(no-alloc)` reads,
`effDefiniteOnly (collectEffects tc p sc)`, drops `Unsafe` from it
(`effDropUnsafe`), and reports anything left as `AX3050`.

The design note behind this question found a trap. `Alloc` is
ambient in Axiom, not declarable, so "must not allocate" can't be
written the way "must not do IO" can. That is a fact about what you can
declare, not about the row. Only `IO` can be written in an
`effect(...)` claim, but `Alloc` is in the effect row like any other
effect, and `restrict(no-alloc)` already reads it. A check inside the
compiler needs the row, not a keyword, so nothing in the effect system
had to change.

The rule isn't a blanket refusal, and the measurement shows it:

```text
$ axiom --diagnostic-format=ai symbols --calls --input self_host/main.ax \
    | grep -E '^F (vecLen|vecGet|strLen|strEq|strByte|memGetWord|concat|fmtInt|vecNew) '
F memGetWord ... #restrict=no-io,no-alloc,no-foreign #effect=unsafe #effects=Unsafe #calls=__load64
F vecNew     ... #restrict=no-io,no-foreign #effects=Alloc,Mut,Unsafe #calls=Vec$vecDefaultCap,...
F vecLen     ... #restrict=no-io,no-alloc,no-foreign #effects=Unsafe #calls=Mem$memGetWord
F vecGet     ... #restrict=no-io,no-alloc,no-foreign #effects=Unsafe #calls=<,>=,Mem$memGetWord,...
F strLen     ... #restrict=no-io,no-alloc,no-foreign #effects=Unsafe #calls=Mem$memGetWord
F strByte    ... #restrict=no-io,no-alloc,no-foreign #effect=unsafe #effects=Unsafe #calls=<,>=,Str$strData,...
F strEq      ... #restrict=no-io,no-alloc,no-foreign #effects=Unsafe #calls=!=,==,Mem$memCmp,...
F concat  ... #restrict=no-io,no-foreign #effects=Alloc,Mut,Unsafe #calls=+,Mem$memCopy,...
F fmtInt     ... #restrict=no-io,no-foreign #effects=Alloc,Mut,Unsafe #calls=-,<,Fmt$fmtNat,...
```

Every function a predicate is written from, the ones that compare,
index, measure and test, carries `no-alloc` and no effect but `Unsafe`.
They read raw memory to do their work, so refusing `Unsafe` would make
a contract unwritable. A read doesn't change the program by being
stated. A write still draws `AX3050` through `Mut`, an allocation
through `Alloc`, and outside reach through `IO`.

Everything that builds carries `Alloc,Mut`. So a contract lives under
this rule: *it may compare, index, measure and test, but it may not
build.* Real contracts can meet that rule. The measurement still holds
after the constructor-row fix described below, which moved 123 effect
rows.

Only a *definite* effect is refused. An effect reaches the row as
*possible* only when the expression names an arrow-typed function
without calling it (`effRefSiteAt`). Naming a function performs
nothing, so accepting it is correct, not just conservative. A row
marked `#effects-incomplete` is a lower bound and isn't evidence either
way. Refusing over it would refuse a program for a limit of the
analysis, which is `AX3037`'s argument.

### A hole the check inherited, and its fix

A struct construction and a fieldful `data` constructor allocate, but
they once contributed nothing to the effect row. So a contract that
constructed one was accepted. This was `restrict(no-alloc)`'s bug
first, and it was fixed there, in `MM-EXEC-9a`'s constructor row.

Because the purity rule reads the same row rather than a rule of its
own, it inherited the fix without a line changing:

```text
$ axiom --diagnostic-format=ai check --input ctorc.ax
E AX3050 ctorc.ax:3:13-28 contract-malformed "`(> (boxed n) 0)` is the `pre` on
  `constructs` and performs Alloc"
```

That is the `constructs` arm of
`tests/diagnostics/385-contract-malformed.ax`. It is there so that the
inherited fix is checked, not just hoped for.

### The distribution behind the ambient-`Alloc` decision

The effect-enforcement design left `Alloc` ambient and asked for the
distribution to be measured before revisiting that. This is the
measurement, over the AXSYM of the largest program in the tree:

```text
$ axiom --diagnostic-format=ai symbols --calls --input self_host/main.ax > main.axsym
$ grep -c '^F ' main.axsym
3647
```

These figures were taken when this design was settled. The compiler
has grown since, so the same command now counts more rows.

There were 3,645 distinct `F` rows, and 2,160 of them (59.3%) carried
`Alloc`. The shape of that 59% matters more than its size. The table
walks the `#calls=` graph from every `Alloc`-carrying row to the
nearest row that carries `Alloc` while none of its callees does. That
is the place where the effect *enters*.

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

An earlier draft measured 3,450 rows, 56% carrying `Alloc`, and only
three entry points: `Mem.memAlloc`, `Mem.memAllocMapped` and `lspMain`.
That analysis couldn't see the commonest way to allocate, because
applying a constructor contributed nothing to the row. With the
constructor row fixed, `Alloc` also enters at every function whose own
body constructs: `mkNode`, `mkSpan`, `mkToken`, `mkError`, `pOk`,
`vecTry`, `strFind` and the rest of the forty.

The conclusion survives the correction. 98.9% of `Alloc` rows are two
or more hops from where the effect enters, so the 59% is almost
entirely *inherited*. A declarable `Alloc` claim would be a claim about
call-graph reachability, not about the body.

That claim already exists and is enforced: `restrict(no-alloc)`. So the
recommendation stands: no `AX3042` sibling for `Alloc`.
The lever that paid was making `restrict(no-alloc)` sound, and that
fix has landed.

## Question 3 — `result` in a `post`

**`result` names the function's answer.** Its type is the *declared*
result: the signature's arrows peeled by as many parameters as the
definition has (`peelArrows`, which `tcCheckFn` already computes for
`checkDeclaredReturn`). It names nothing anywhere else, and both other
cases are `AX3050`:

```text
$ axiom --diagnostic-format=ai check --input bad.ax
E AX3050 ...:9:16-22 contract-malformed "`result` names nothing in a `pre`:
  a precondition is checked BEFORE the body runs, so there is no result yet"
E AX3050 ...:6:17-23 contract-malformed "`result` names nothing here: this
  declaration has no `::` signature, so it declares no result type for
  `result` to have"
```

The second case is the one `AX3050`'s reserved meaning names: "names
`result` where the declared result is absent". A `fn` with no `::` is
exactly that case, because such a definition gets a placeholder type
variable rather than a declared type:

```text
$ printf '(pub fn (g n) (* n 2))\n\n(:: main Int)\n\n(pub fn (main) (g 3))\n' > q2.ax
$ axiom check --input q2.ax
OK
```

### How the check finds `result`

A hand-written walk looking for `result` references would have to
mirror every expression form. Any form it missed would answer
`AX3001 undefined variable` instead, a check reporting less than it
knows.

Instead, `tc` carries the contract being checked (`inContract`, word
34), and `checkVar` asks one question at the top: is the name `result`,
are we inside a contract, and does nothing in the frame bind it? Every
reference goes through `checkVar`, so this covers every form by
construction.

## Question 4 — where the expression is checked, and what is not done

**The parameters are in scope in both `pre` and `post`, and there is no
`'Old`.**

Ada pairs `Post` with `'Old` because Ada's parameters can be assigned,
so `X` in a postcondition isn't necessarily the `X` the caller passed.
Axiom's parameters can't be assigned:

```text
$ axiom check --input q3.ax     # (fn (h n) { (set n 5) n })
error[AX3012]: cannot assign to `n`: it is a parameter, and parameters
               are immutable
```

So for a scalar parameter, the name means the same in the `post` as in
the `pre`, and `'Old` would just be a synonym for the name.

These are not done:

- **`'Old` for a reference parameter.** A parameter's *pointee* can be
  mutated, for example by `memSetWord` into a struct the caller still
  holds, and a `post` can't see the state before that. Snapshotting it
  would mean copying arbitrary structure at every call, a cost the
  arena model would pay on every guarded call whether or not the
  contract fails.
- **Contracts on anything but a function.** There are no `struct`
  invariants, loop invariants or `type` predicates.
- **Inheritance or refinement.** Traits were removed in 0.6.0, so there
  is nothing to inherit from.
- **Static discharge.** A `pre` that a call site's literal arguments
  would refute isn't refused. That fragment is decidable, and the
  machinery (substitute the argument, fold, refuse a constant `false`)
  is real work with its own gate. It would be a strict addition to what
  shipped and change nothing here.

<a id="the-cost-a-post-has-measured"></a>
### The cost of a `post`

```text
$ axiom emit-llvm --input t1.ax | grep -c 'call i64 @loopA('   # bare
1                                        # main's call only: the self
                                         # tail call became a loop
$ axiom emit-llvm --input t2.ax | grep -c 'call i64 @loopB('   # under a post
2                                        # main's, plus a real recursion
```

`tailCallsSelf` treats a `let`'s body as a tail position and its
initialiser as not one, which is correct. A `post` binds the body to
`result`, so the call it wraps stops being a tail call and the loop
rewrite doesn't fire. This cost is inherent: a postcondition has to
observe the result.

A `pre` is a block whose last expression is the body, and a block's
last expression is a tail position, so a `pre` costs nothing here.
`tests/selfhost/132-contract.ax` recurses 200,000 deep under a `pre`
and answers. Section 5 of the gate checks both directions, so the cost
of a `post` isn't mistaken for a regression later.

## The hazard the previous design note found, and what became of it

[checked-arithmetic-design.md](checked-arithmetic-design.md) states
that `restrict(no-wrap, no-alloc)` can't both hold for a body that adds
two numbers. Satisfying `no-wrap` means calling `addChecked`, whose
`Result` construction allocates. It predicted that a user writing the
pair would get a confusing `AX3049` about the very thing they did to
comply.

Probed against 0.6.0, the answer was worse than the hazard:

```scheme
(import Err)

;@axiom:restrict(no-wrap,no-alloc)
(:: addSafe (-> Int Int Int))

(fn (addSafe a b) (unwrapOr (addChecked a b) 0))
```

```text
$ axc-0.6.0 check --input unsat.ax
OK
$ axc-0.6.0 --diagnostic-format=ai symbols --calls --input unsat.ax | grep '^F addSafe '
F addSafe ... #restrict=no-wrap,no-alloc #calls=Err$addChecked,Err$unwrapOr
```

There was no diagnostic and no `#effects=` at all, because applying a
constructor contributed nothing to the effect row. `walkCallHead`'s
`findFnEnt` answered 0 for every constructor, and `TAG_E_STRUCTCON`
walked its fields and added nothing either. A `restrict(no-alloc)`
claim therefore couldn't fail, which is the same defect as the check
not existing.

<a id="re-run-against-the-merged-tree-and-it-is-closed"></a>
### The hazard now reports itself

`MM-EXEC-9a`'s constructor row closed this. The fix withdrew seven
restriction claims and moved 123 of 3,725 effect rows. An earlier probe
of the same fix counted six declarations refused and 113 of 3,488 rows
moving. Its sweep lost the seventh claim, `histFindBack`, to an import
failure.

The same two programs, run today:

```text
$ axiom --diagnostic-format=ai check --input unsat.ax
E AX3049 unsat.ax:6:6-13 restriction-violated "`addSafe` claims `restrict(no-alloc)`
  and the body performs Alloc: addSafe -> Err$addChecked -> Err$mkError, in
  `mkError`'s own body"

$ axiom --diagnostic-format=ai check --input ctorc.ax
E AX3050 ctorc.ax:3:13-28 contract-malformed "`(> (boxed n) 0)` is the `pre` on
  `constructs` and performs Alloc"
```

Both predictions the previous note made are now the compiler's answer,
with the path. The restriction pair that can't both hold reports
itself, the way that note argued it should. It doesn't come from a
hand-written table of conflicting pairs, which would go stale the first
time a restriction's analysis changed and would name two keywords
instead of a place. It comes from each restriction answering
correctly, so the pair shows up as a call chain you can go and fix.

Nothing in the contracts feature changed to get this. The purity rule
reads the effect row rather than keeping a rule of its own, so it
inherited a fix made in another pass.

<a id="a-hole-this-feature-shipped-with-for-one-commit"></a>
## A program can't turn its own contract off

`__contract` is the primitive the lowering writes. The first version of
the lowering skipped any body that already *looked* lowered: a block
whose first statement applies `__contract`, under an optional `result`
binding. The aim was that a second `expandProgram` over the same
declarations wouldn't wrap the body twice. It assumed a source program
couldn't reach `__contract`, because `isPrimName` claims it in the
emitter and nothing documents it.

That assumption was wrong. `__contract` is registered in `fns` and
intercepted by `checkApp`, exactly as `__streq` is, so a program can
write it. One that did turned its own contract off:

```scheme
;@axiom:pre((> n 0))
(:: f (-> Int Int))

(fn (f n) { (__contract true "never\n") n })

(:: main Int)

(fn (main) (f 0))
```

With the guard, this checked `OK` and exited 0. The same file without
that first statement exited 80. The `post` arm had the same shape,
under a `let` binding `result`. A claim a program can withdraw by
writing one expression is a check that can't fail.

The guard was deleted rather than made cleverer, because the body can
forge any shape-based test of the body. Today the program above fails
as it should:

```text
$ axiom run --input h1.ax; echo $?
axiom: precondition failed in `f`: (> n 0)
axiom: backtrace (most recent call first)
  at __axiom_contract_fail
  at __axiom_user_main h1.ax:8:13
  at main
80
```

Deleting the guard costs nothing:

- No path in this tree calls `expandProgram` twice over one declaration
  list. `main.ax`, `lsp.ax`, `repl.ax`, `symbols` and `emitModule` each
  parse first.
- A diamond import splices each node once. With `(import B) (import C)`,
  where both import a contract-carrying `D`, the module emits exactly
  one `call i64 @__axiom_contract_fail`.
- A doubled lowering would do nothing anyway. `AX3050` refuses a
  contract that performs anything, and evaluating a pure predicate
  twice can't differ from evaluating it once.

So the guard defended a case nothing reaches, against a consequence
that doesn't exist, and cost soundness in a case a program can write.
Section 6 of the gate runs both programs, and the third ablation puts
the guard back and requires section 6 to fail.

The check also travels with the function. Because the compare is inside
the body, there is no call site for a caller to miss. A contract fires
through an indirect call, `(apply half 0)` where `apply` takes the
function as a parameter, and through a lambda,
`((lambda (x) (half x)) 0)`. Both exit 80.

## What shipped

| | |
|---|---|
| Keys | `pre`, `post`: already known to `axtagKnownKey`, now checked |
| Read from | the `::` and the `fn`, as one list in source order, exactly as `restrict(...)` |
| Diagnostic | `AX3050` `contract-malformed`, an error, four arms |
| Lowering | `expLowerContracts` at the end of `expandProgram` |
| Primitive | `__contract`, `(-> a String Int)`, no effect row |
| Runtime | `@__axiom_contract_fail`, emitted unconditionally and pruned where nothing calls it, exit **80**, its own row in `MM-EXEC-16` (D3) |
| Fixtures | `tests/diagnostics/385`, `tests/selfhost/132`, `tests/selfhost/133` |
| Gate | `scripts/check-contracts.sh`, seven sections, three ablations |
