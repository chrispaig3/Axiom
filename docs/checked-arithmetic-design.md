# Checked arithmetic — phase 1 design

This record explains `restrict(no-wrap)`. It is a claim you put on a
function to say its body never writes `+`, `-` or `*` on `Int`, the
three operators that wrap silently on overflow. It covers the shapes we
considered, why we chose this one, and what we left out.

| Date | Status |
|---|---|
| 2026-08-31 | Phase 1 built in `b7a8e1b`, the same commit as this design. |
| 2026-09-04 | Corrected: the `for` counter and `Float` operators are no longer refused. |
| 2026-09-08 | Decision D1 (roadmap item 11) closes checked arithmetic as designed. |
| 2026-09-10 | `remChecked` and `shrChecked` have fixtures, and `ERR-REC-2` reads "H, gated". |
| 2026-10-02 | The deferred corners now trap: `INT_MIN / -1` exits 83, an out-of-range shift exits 84 (`MM-VAL-3b`). The follow-up is renamed `no-trap`, and this record's `no-untrapped` means that. |

The sections from "What already exists" to "Gate plan" are the design
pass, written before the code. What changed after it shipped is in
[What phase 1 turned out to be](#what-phase-1-turned-out-to-be). The
items we left out are decided, not open: see
[What isn't built, and why](#what-isnt-built-and-why).

## In short

A function that claims `no-wrap` does its arithmetic through the checked
functions in `stdlib/Err.ax`:

```scheme
(import IO)
(import Err)

;@axiom:restrict(no-wrap)
(:: total (-> Int Int Int))
(fn (total a b)
  (unwrapOr (addChecked a b) 0))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (total 40 2))
    (println (total 9223372036854775807 1))
    0
  })
```

```text
42
0
```

`addChecked` returns an `Err` on overflow, and `unwrapOr` turns it into
`0`. Write `(+ a b)` in `total` instead and `axiom check` refuses it at
the operator:

```text
error[AX3049]: `+` in the body of `total`, which claims `restrict(no-wrap)`
 --> bad.ax:7:4
  |
7 |   (+ a b))
  |    ^
```

Checked arithmetic is one of three items left after the first round of
restriction profiles (`no-io`, `no-alloc`, `no-cast`, `no-cast:deep`,
`no-recursion` and `no-foreign`, in `05fb064`, `4a55781` and
`7540524`). The other two are pre/post contracts, designed in
[contracts-design.md](contracts-design.md) and built with `AX3050`, and
range-constrained subtypes, designed in
[subtypes-design.md](subtypes-design.md) and not built.

<a id="what-already-exists-measured-not-assumed"></a>
## What already exists

`stdlib/Err.ax` already has the full checked-arithmetic library:
`addChecked`, `subChecked`, `mulChecked`, `divChecked`, `remChecked`,
`shlChecked` and `shrChecked`. Each has the type
`(-> Int Int (Result Int Error))`. They report `errOverflow` (code 2),
`errDivideByZero` (code 1) and `errShiftTooWide` (code 3).

`tests/stdlib/312-checked-arithmetic.ax` pins their answers
byte-identical at `--opt` 0, 1, 2 and 3. It held 30 cases when this
design was written. [error-model.md](error-model.md)'s `ERR-REC-2` then
read "H, partly gated", because `remChecked` and `shrChecked` had no
fixture yet. That gap is now closed.

So Shape C below, checked alternatives that return `Result`, needed no
building. The open question was *enforcement*. Can a function claim it
uses only the checked path, the way `;@axiom:restrict(no-cast)` lets a
function claim it never fabricates a value?

## Question 1 — what would `checked-arith` mean, and which of the three shapes is it

### Shape A: codegen traps on overflow

LLVM offers `@llvm.sadd.with.overflow.i64`,
`@llvm.ssub.with.overflow.i64` and `@llvm.smul.with.overflow.i64`. Each
returns `{i64, i1}`, so codegen can branch on the overflow bit. That is
the same structure as the division-by-zero trap `/` and `%` already
emit: an explicit runtime test that writes `axiom: division by zero` to
fd 2 and exits 72 (`MM-VAL-3a`).

Axiom's codegen emits nothing like this today:

```bash
grep -c 'with\.overflow\|\bnsw\b\|\bnuw\b' self_host/codegen.ax   # prints 0
```

`+`, `-` and `*` lower to plain `add`, `sub` and `mul` with neither
flag. The comment in `stdlib/Err.ax` on "the three that wrap" says the
same.

We rejected Shape A. Every restriction upholds one invariant: a
restriction is a check and never a transformation, so it changes no
emitted byte. Section 1 of `scripts/check-restrictions.sh` proves this
by comparing IR byte for byte over 168+ corpus programs, its largest
section.

A trapping restriction breaks that invariant by construction. A `+`
under it would emit an intrinsic call and a branch, where an
unrestricted `+` emits one instruction. That is a different feature, an
opt-in codegen mode, and it would need its own invariant and its own
gate section.

### Shape B: refuse unchecked operators

This adds a new name to the closed `restrict(...)` list. Mechanically it
is `no-cast` with a different predicate. `no-cast` is local: a cast is
an act this body performs, so it is checked in this body only and
reported at the cast itself
([reference.md](reference.md#restrict---what-a-declaration-does-not-do)).

Raw `+`, `-` and `*` have the same shape. Writing the operator is an act
of the body, not a fact that flows through the call graph. So the
implementation is a twin of `castScanInto`. It walks the body's
expression tree once, matches an application's head against `+`, `-`
and `*` instead of `cast`, and reports `AX3049` at the operator's span.

An application's span is its head's span. The parser builds
`TAG_E_APP f x 0 (nodeSpan f)` in `self_host/parser.ax`, which carries
the span down to the leaf `Var`. That is how `no-cast` underlines the
word `cast` rather than the declaration.

Shape B needs no codegen change and no new diagnostic code. It reuses
`AX3049` (`restriction-violated`) and `AX3052` (`restriction-unknown`)
exactly as `no-cast` does. It has no `AX3051`
(`restriction-unverifiable`) path, because a lexical scan resolves no
calls. It needs no new fixpoint, no call-graph walk and no effect-row
machinery.

### Shape C: checked alternatives returning `Result`

These already exist (see above). Shape B's job is to make them
required rather than optional. Without it, nothing stops a function
from writing a raw `+` three lines away from a call to `addChecked`.

### Chosen: Shape B

We named it `no-wrap`. It is the only shape of the three that:

- keeps the invariant that a restriction is a check, never a
  transformation, which the other six restrictions were built to prove;
- needs no new runtime behaviour, diagnostic code or analysis pass,
  only about 90 lines mirroring the roughly 80 of `castScanInto`;
- has its remedy already shipped, tested and documented.

## Question 2 — the effect-row interaction

Constructing `Ok` or `Err` allocates. So a function that returns
`Result` carries `Alloc`, and usually `Mut`, in its effect row, even
when its caller asked only for `IO`.

Effect rows are transitive, as the definition of `no-io` in the
reference says: a function that calls an IO-performing function has `IO`
in its row. The same fixpoint applies to `Alloc`. A function that
satisfies `no-wrap` by calling `addChecked` takes on `Alloc` the moment
it makes the call. That holds whether it passes the `Err` on or unwraps
it straight away with `unwrapOr`.

`Alloc` is ambient, not a declarable claim. Only `IO` is declared, and
`AX3042` checks it. So this draws no diagnostic by itself, but it
conflicts with two other claims:

- `restrict(no-wrap, no-alloc)` can't be satisfied by a function
  that adds two numbers it didn't receive as a checked value.
  `no-alloc` refuses the only path `no-wrap` leaves open. The compiler
  says so, with the path:

  ```text
  error[AX3049]: `addSafe` claims `restrict(no-alloc)` and the body performs Alloc: addSafe -> Err$addChecked -> Err$mkError, in `mkError`'s own body
  ```

  That is `(fn (addSafe a b) (unwrapOr (addChecked a b) 0))` under both
  restrictions. The compiler at `9116167` accepted the same file,
  because a constructor application added no `Alloc` to the row. That
  was a hole in `no-alloc`, closed by `MM-EXEC-9a`'s constructor row,
  which withdrew seven claims. [contracts-design.md](contracts-design.md)
  records both runs.
- `;@axiom:effect(pure)` with `restrict(no-wrap)` can't be satisfied either.
  A pure function can't allocate, and the only arithmetic `no-wrap`
  allows allocates. The compiler reports `AX3010`, "`effect(pure)`
  claim contradicted: body performs Alloc".

So a checked `add` that returns `Result` can't be used by a `pure`
function. This is the price of the safety, not a defect to route
around. `AX3049`'s help text for `no-wrap` states it, so you don't have
to discover it. `CHANGELOG.md`
records the parallel trade for `Sys.ax`.

## Question 3 — does codegen already emit anything like `llvm.*.with.overflow`

No. The `grep` under Question 1 finds none in `self_host/codegen.ax`,
and the comment in `stdlib/Err.ax` agrees.

## Scope decision — which operators `no-wrap` refuses

`no-wrap` refuses `+`, `-` and `*` only. These are the three that
`stdlib/Err.ax` calls the ones that wrap: plain `add`, `sub` and `mul`,
with no `nsw`, and silent two's-complement wraparound on overflow. That
is the shape of the `stdlib/Rpc.ax` bug the same file cites as the
motivating incident.

The other operators carry different hazards:

- `/` and `%` trap on a zero divisor at run time, exiting 72. They are
  undefined only on the `INT_MIN / -1` corner (`MM-VAL-3b`).
- `<<` and `>>` are undefined on an out-of-range shift amount, with no
  runtime check at all. That is arguably sharper than `+`, `-` and `*`.

We left both pairs out. "No undefined shift" is a different claim from
"no silent wraparound", and it deserves its own name and reasoning.
`no-foreign` and `no-recursion` got separate names in the same way,
rather than one catch-all name. The closed list has room, and
`divChecked`, `remChecked`, `shlChecked` and `shrChecked` already
exist for that follow-up.

Raw arithmetic is everywhere, so a broad scope would reach far. At
design time, across
`self_host/*.ax` and `stdlib/*.ax`, `grep -oE '\(\+ '` found 2417
matches, `\(- ` found 836 and `\(\* ` found 127. `no-wrap` is a narrow,
opt-in claim. It is meant for boundary code where wraparound safety is
worth the `Alloc` price.

`no-cast` takes the same position. There were 653 casts against 3196
`fn`, and the comment on it in `self_host/typecheck.ax` notes that a
transitive reading "would refuse nearly every program that reaches the
standard library".

## Mechanism, concretely

- The name: `no-wrap` joins the closed list and is checked in
  `checkOneRestrict` beside `no-cast`, in the local branch. It needs no
  effect-row or call-graph argument.
- The walk: `isWrapOp`, `wrapScanInto`, `wrapScanIn`,
  `wrapScanVec`, `wrapScanCond` and `wrapScanArms` are a full copy of
  the `castScanInto` walk. The predicate changes from "head named
  `cast`" to "head named `+`, `-` or `*`". We duplicated rather than
  parameterised it to match the file's convention. `castScanInto`'s own
  comment says its arms "mirror `walkEffects` form for form": the file
  already keeps one hand-written walk per collected fact.
- The report: `restrictNoWrap`, `restrictEmitWraps` and
  `emitRestrictWrap` have the same shape as `restrictNoCast`,
  `restrictEmitCasts` and `emitRestrictCast`. The message names the
  operator it found, because each has its own fix: `addChecked`,
  `subChecked` or `mulChecked`.
- The lists: there is no new diagnostic code. The restrict table in
  [reference.md](reference.md#restrict---what-a-declaration-does-not-do), the closed-list string in
  `emitRestrictUnknown`, and the `AX3049`, `AX3051` and `AX3052` text in
  `self_host/explain.ax` each gain `no-wrap`, in the same places that
  name `no-cast`.

## Gate plan

This extends `scripts/check-restrictions.sh` rather than adding a
script. `no-wrap` is a new name inside the mechanism that gate already
proves.

- Section 2 (fixtures answer, controls are silent) adds the fixture
  `tests/diagnostics/383-restrict-no-wrap.ax` to
  `fixture_expectations`.
- Section 3 (a planted violation is refused) gives the `clean.ax`
  program a `quietWrap` declaration that satisfies the claim with
  checked arithmetic. A `plant no-wrap` step swaps its body for a raw
  `+`.
- Sections 1, 4 and 5 already generalise. Section 1 is specific to
  `no-foreign` and is unaffected. Section 4 ablates the single
  `checkRestricts` hook, which covers every restriction name. Section
  5's manifest sweep covers whatever `#restrict=` values `symbols`
  prints.
- Ablation: to prove the new checks bite, `isWrapOp` is made to
  answer 0 unconditionally, so `no-wrap` can never fire. The gate must
  go red, then green once restored.

<a id="what-phase-1-turned-out-to-be-20260904"></a>
## What phase 1 turned out to be

Phase 1 shipped as designed. `checkOneRestrict` gained its arm, and
`isWrapOp`, `wrapScanInto` and the rest went in as described.
`tests/diagnostics/383-restrict-no-wrap.ax` and the `plant no-wrap`
step in `scripts/check-restrictions.sh` pin it, and no diagnostic code
was added. The Gate plan above describes what shipped. The mechanism
needed no correction.

The design was wrong about one thing. A lexical check matches a
*spelling*, and two things that use these spellings can't wrap. Both
were refused, and neither refusal had a fix you could apply.

### The `for` keyword

The parser desugars `for` in `forWhileBody`. It becomes
`(set for$i (+ for$i 1))` beneath a `(< for$i for$n)` guard, and every
generated node carries the keyword's span. Against `5d61c6a`, before
the fix, a nine-line program whose only arithmetic was a `for` loop
drew this:

```text
E AX3049 p1-for.ax:9:8-11 restriction-violated "`+` in the body of
`countUp`, which claims `restrict(no-wrap)`"
```

Columns 8 to 11 of line 9 spell `for`. The diagnostic named an operator
the source doesn't contain and underlined a keyword. It also prescribed
`addChecked`, but a loop counter can't be a `Result`. So
`restrict(no-wrap)` and the language's own loop keyword were mutually
exclusive, and nothing said so.

Skipping the counter is sound. The body runs only while
`for$i < for$n`, both `Int`, so `for$i + 1` is at most `INT_MAX` and
can't overflow. Only the parser can produce this shape: `$` inside an
identifier is `AX1001` (unexpected character), so no author can write
`for$i`.

`isForBump` matches the whole shape: the target, the head and both
operands. If the desugaring drifts, it stops matching and the fixture
fails rather than going quiet. A loop written out by hand is still
refused, and so is arithmetic in a loop's body.

### `Float` operands

`(+ a b)` on two `Float`s lowers to `fadd`. `fbinopToLLVM` in
`self_host/codegen.ax` does this, and `emitBinop2` picks it from the
operands' float flags. `fadd`, `fsub` and `fmul` have no wraparound to
refuse, so the design's premise that these operators lower to `add`,
`sub` and `mul` is false for them.

Worse, the fix the diagnostic named doesn't typecheck against a
`Float`, because `addChecked` is `(-> Int Int (Result Int Error))`. So
`restrict(no-wrap)` couldn't be satisfied by any body doing float
arithmetic.

Operand types exist only in `checkNumeric`, and the checker keeps no
per-node types. So `checkNumeric` records the float-typed
operator heads (`TC` word 37, `tcFloatOpAdd`), and `restrictEmitWraps`
reads them once. This works because of an ordering `tcWalkDecls`
already guarantees: the body is checked first, then its tags. A `Float`
`+` nested inside an `Int` `+` still reports the outer operator.

### Both fixes are checks

Neither fix is a transformation. No `emitExpr` case moved and no
emitted byte changed. Section 1 of `check-restrictions.sh` proves that
invariant again over the corpus on every run.

Three checks pin the exemptions:

- `tests/diagnostics/394-restrict-no-wrap-exempt.ax` has both
  exemptions, each beside the case that keeps it narrow: a hand-written
  loop counter, arithmetic in a loop's body, and a `Float` `+` inside an
  `Int` one.
- `tests/selfhost/465-restrict-no-wrap-runs.ax` runs a restricted `for`
  loop and float arithmetic, and must exit 60.
- Section 6 of `check-restrictions.sh` builds a compiler with each
  exemption's predicate fixed to a constant, and requires both
  declarations to draw `AX3049` again.

<a id="what-the-designs-other-blockers-measured-rerun-20260904"></a>
## The other blockers, re-measured

Two of the design's three blockers still hold against the tree:

- `grep -c 'with\.overflow\|\bnsw\b\|\bnuw\b' self_host/codegen.ax`
  still prints `0`, so Shape A's premise holds.
- `restrict(no-wrap, no-alloc)` on `(unwrapOr (addChecked a b) 0)` is
  still refused with the path
  `addSafe -> Err$addChecked -> Err$mkError`. `;@axiom:effect(pure)` beside
  `no-wrap` is still `AX3010`. The pair can't be satisfied, and the
  diagnostic's help says so.

The corpus counts have moved, and the conclusion hasn't. `no-wrap` is a
narrow, opt-in claim about a region, not a mode anything acquires by
accident.

| Pattern in `self_host/` and `stdlib/` | Design pass | Phase 1 review | Decision D1 |
|---|---|---|---|
| `(+ ` | 2417 | 2705 | 2741 |
| `(- ` | 836 | 1018 | 1044 |
| `(* ` | 127 | 141 | 147 |

<a id="what-is-not-built-and-why--decided-not-open"></a>
## What isn't built, and why

These are decided, not open.

- Shape A, a codegen trap (`llvm.sadd.with.overflow`), is not
  a follow-up of `no-wrap`. A restriction changes no emitted byte, and
  section 1 of `check-restrictions.sh` proves that over the corpus. An
  opt-in trapping mode is a different feature, with its own invariant
  and gate. It must not be spelled as a `restrict(...)` name.
- `/` and `%` are outside `no-wrap`. They trap on a zero
  divisor (`axiom: division by zero`, exit 72), so their only hazard is
  `INT_MIN / -1` (`MM-VAL-3b`). That is a different claim from "no
  silent wraparound", and it has its own name.
- `<<` and `>>` are undefined on an out-of-range shift amount,
  with no runtime check. That is sharper than `+`, `-` and `*` in one
  way and unrelated in another. `divChecked`, `remChecked`,
  `shlChecked` and `shrChecked` in `stdlib/Err.ax` answer them.

The named follow-up for these four operators is
`restrict(no-trap)` (spelled `no-untrapped` when this section was
written), pinned by `tests/diagnostics/396-restrict-no-trap.ax`. It
is not a gap in phase 1.

The `remChecked` and `shrChecked` fixture gap is closed.
`tests/stdlib/312-checked-arithmetic.ax` carries their boundary terms
beside the other five operators: the remainder's one wraparound
(`intMin % -1`), the zero divisor, and shift amounts of 63, 64 and -1.
The case's `.optstable` marker holds stdout and exit status identical at
`--opt` 0, 1, 2 and 3. `ERR-REC-2` in
[error-model.md](error-model.md) reads "H, gated" over exactly this.

<a id="decision-d1-20260908-roadmap-item-11-built-shape-b"></a>
## Decision D1: built, Shape B

| Decision | Date | Roadmap item |
|---|---|---|
| D1: checked arithmetic is closed as designed | 2026-09-08 | 11 |

- Built: `no-wrap` (Shape B, a restriction that checks) and its two
  exemptions.
- Rejected: Shape A as a `restrict` spelling, because it would emit
  bytes.
- Deferred: `/`, `%`, `<<` and `>>`, to the named `no-untrapped`
  follow-up.
- `ERR-REC-2` stayed "H, partly gated" at this decision, only over
  the `remChecked`/`shrChecked` fixture gap, which has since closed.

The evidence was re-measured for the decision. `with.overflow`, `nsw`
and `nuw` occur 0 times in `self_host/codegen.ax`, and the corpus
counts are in the table above. The `no-wrap` with `no-alloc` and `pure`
with `no-wrap` refusals still fire. They are pinned by
`tests/diagnostics/383-restrict-no-wrap.ax`,
`tests/diagnostics/394-restrict-no-wrap-exempt.ax`,
`tests/selfhost/465-restrict-no-wrap-runs.ax`, section 6 of
`scripts/check-restrictions.sh`, and the restrict table in
[reference.md](reference.md).

Revisit this only with a new measurement, not a new argument.
