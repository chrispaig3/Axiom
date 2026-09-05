# Checked arithmetic — Phase 1 design

**Status: phase 1 BUILT `b7a8e1b` (2026-08-31), CORRECTED 2026-09-04.**
This note was written as a design pass and committed in the same commit
as its own implementation, so the sections below still read in the
future tense; they are kept as written, and everything that happened
since is in "What phase 1 turned out to be" at the end. Read that
section first if you are here to find out what exists. In short:
Shape B (`no-wrap`) shipped on 2026-08-31; on 2026-09-04 it was found
to refuse two operators that cannot wrap, and that is fixed. The
deferred items are decided rather than open — see "What is NOT built,
and why".

Ada round 1 shipped restriction profiles (`no-io`, `no-alloc`,
`no-cast`, `no-cast:deep`, `no-recursion`, `no-foreign`;
`05fb064`/`4a55781`/`7540524`). Three items stayed unstarted:
pre/post contracts (`AX3050` reserved for them,
`docs/error-model.md`), range-constrained subtypes
(`docs/subtypes-design.md`, designed 2026-08-31 and deliberately not
built), and this one
— checked arithmetic. The contracts landed on 2026-08-31 and spent
`AX3050`; `docs/contracts-design.md` is their note, and it re-measures
the hazard this one records below (see "Question 2 — the effect-row
interaction"): the pair really is unsatisfiable, and since
`MM-EXEC-9a`'s constructor row closed on the same day the compiler says
so, with the path. This note is the design pass required before
touching any code, per the task brief; every claim below carries the
command that established it.

## What already exists (measured, not assumed)

`stdlib/Err.ax` already has the full checked-arithmetic library:
`addChecked`, `subChecked`, `mulChecked`, `divChecked`, `remChecked`,
`shlChecked`, `shrChecked`, every one `(-> Int Int (Result Int
Error))`, using `errOverflow` (code 2), `errDivideByZero` (code 1) and
`errShiftTooWide` (code 3). `tests/stdlib/312-checked-arithmetic.ax`
pins 30 cases byte-identical at `--opt` 0/1/2/3
(`docs/memory-model.md:3761`). `docs/error-model.md`'s `ERR-REC-2`
already names this "H, partly gated" — `remChecked`/`shrChecked` are
built but not yet exercised by a fixture (`docs/error-model.md:1069`,
a pre-existing gap this task does not close).

So Shape C from the task brief — "offer checked alternatives
returning Result" — is not something to build. It is already built,
tested, and documented. The open question is entirely about
*enforcement*: is there a way for a function to CLAIM it only uses
the checked path, the way `;@axiom:restrict(no-cast)` lets a function
claim it never fabricates a value?

## Question 1 — what would `checked-arith` mean, and which of the three shapes is it

**Shape A: codegen traps on overflow (`llvm.sadd.with.overflow` etc.)**

What LLVM offers: `@llvm.sadd.with.overflow.i64` /
`@llvm.ssub.with.overflow.i64` / `@llvm.smul.with.overflow.i64`,
each returning `{i64, i1}` so codegen can branch on the overflow bit
— structurally identical to the div-by-zero trap `/` and `%` already
emit today (an explicit runtime test, `axiom: division by zero` to
fd 2, exit 72 — `stdlib/Err.ax`'s own comment, MM-VAL-3a).

Measured whether Axiom's codegen already emits anything like this:

```
$ grep -c 'with\.overflow\|\bnsw\b\|\bnuw\b' self_host/codegen.ax
0
```

Zero. `+`, `-`, `*` lower to plain `add`/`sub`/`mul` with neither
flag — confirmed independently by `stdlib/Err.ax`'s own comment
("The three that WRAP... emit plain `add`/`sub`/`mul` with no `nsw`")
written before this task started.

Rejected for this slice. Every restriction shipped in round 1 upholds
one invariant, and `scripts/check-restrictions.sh` section 1 spends
its largest section (a sweep of 168+ corpus programs, IR compared
byte-for-byte) proving it: *"Assert that `;@axiom:restrict(...)` is a
CHECK and never a TRANSFORMATION... a restriction changes no emitted
byte."* A codegen-trap restriction breaks that invariant by
construction — a satisfied `+` under it would emit an intrinsic call
and a branch where an unrestricted `+` emits one instruction. That
is not a bigger version of the existing feature, it is a different
feature (an opt-in codegen mode), and it would need its own new
invariant and its own new gate section rather than extending the one
that exists. Out of scope for "smallest."

**Shape B: refuse unchecked operators (a new name in the closed `restrict(...)` list)**

Mechanically this is `no-cast` with a different predicate. `no-cast`
is documented as LOCAL — "a cast is an act this body performs...
checked in this body only and reported at the cast itself"
(`docs/reference.md:1238`) — because casts are lexical, not a
propagated effect-row fact. Raw `+`/`-`/`*` are the same shape: an
act the body performs by writing the bare operator, not a fact that
flows through the call graph. The implementation is `castScanInto`'s
twin: walk this body's expression tree once, match an application's
head against `{"+", "-", "*"}` instead of `{"cast"}`, report AX3049
at the operator's own span. An application's span is its head's
(`self_host/parser.ax:652`, `TAG_E_APP f x 0 (nodeSpan f)`
propagating down to the leaf `Var` — the same mechanism that lets
`no-cast`'s diagnostic underline the word `cast` and not the
declaration).

No codegen change. No new diagnostic code — reuses AX3049
(`restriction-violated`) and AX3052 (`restriction-unknown`) exactly
as `no-cast` does; no AX3051 (`restriction-unverifiable`) path,
because — same reasoning as `no-cast` — a lexical scan needs no call
resolved. No new fixpoint, no call-graph walk, no dependency on the
effect-row machinery at all.

**Shape C: offer checked alternatives returning `Result`**

Already exists (see above). Shape B's entire job is to make Shape C
load-bearing instead of optional — before this task, nothing stops a
function from writing raw `+` right next to a call to `addChecked`
three lines later.

**Chosen: Shape B**, named `no-wrap`. It is the only one of the three
that (a) does not contradict the "restriction is a check, never a
transformation" invariant the other six restrictions were built to
prove, (b) needs no new runtime behavior, diagnostic code, or
analysis pass — about 90 lines mirroring `castScanInto`'s ~80 — and
(c) has its remedy already shipped, tested, and documented rather
than invented for this task.

## Question 2 — the effect-row interaction

The constraint handed down for this task, measured while porting
`sysWriteAllFd`: constructing `Ok`/`Err` allocates, so a function
that returns `Result` carries `Alloc` (and usually `Mut`) in its
effect row even when its caller only asked for `IO`
(`CHANGELOG.md`, Unreleased, "the `Result` migration's real blocker
turned out to be the EFFECT ROW" — ten gates went red on that
port).

Effect rows are transitive by construction — this is not new to
`no-wrap`, it is the exact sentence `no-io`'s own definition uses:
*"a function calling an IO-performing function HAS `IO` in its row"*
(`docs/reference.md`, AXTAG Keys). The same fixpoint applies to
`Alloc`. So: a function that satisfies `no-wrap` by calling
`addChecked` inherits `Alloc` into its own effect row the moment it
makes the call, independent of whether it re-propagates the `Err` or
unwraps immediately with `unwrapOr`. `Alloc` is ambient rather than a
declarable claim (only `IO` is declared and checked by AX3042 per
this project's effect-enforcement design), so this does not draw a
diagnostic — but it is real and it composes badly with two other
restrictions:

- `restrict(no-wrap, no-alloc)` together are unsatisfiable for any
  function that needs to add two numbers it did not get from a
  caller already carrying a checked value — `no-alloc` refuses the
  only path `no-wrap` leaves open. **Probed twice on 2026-08-31, and
  the second probe is the one that stands.** Against `9116167` the
  prediction was right about the program and wrong about the compiler:
  `(fn (addSafe a b) (unwrapOr (addChecked a b) 0))` under both
  restrictions checked `OK`, because a constructor application
  contributed no `Alloc` to the effect row at all. That was
  `restrict(no-alloc)` being unfalsifiable rather than this pair being
  satisfiable, and it closed the same day (`MM-EXEC-9a`'s constructor
  row, seven claims withdrawn). Against the merged tree the same file
  answers what this bullet predicted, with the path:
  `E AX3049 ... "`addSafe` claims `restrict(no-alloc)` and the body
  performs Alloc: addSafe -> Err$addChecked -> Err$mkError, in
  `mkError`'s own body"`. `docs/contracts-design.md` records both runs
  and why the first one's numbers are kept rather than corrected.
- `;@axiom:pure` and `restrict(no-wrap)` together are unsatisfiable
  for the same reason: a pure function cannot allocate, and the only
  sanctioned arithmetic under `no-wrap` allocates.

This is the same trade the task brief states directly — "a checked
`add` that returns `Result` cannot be used by a `pure` function" —
and it is written into the diagnostic's own help text below rather
than left for someone to discover. It is not a defect to route
around; it is the honest price of the safety, and this project's own
`CHANGELOG.md` already states the parallel trade for `Sys.ax` in the
same words ("What is NOT free is the effect row").

## Question 3 — does codegen already emit anything like `llvm.*.with.overflow`

No. Answered under Question 1: `grep -c 'with\.overflow\|nsw\|nuw'
self_host/codegen.ax` → `0`. This was checked directly rather than
inferred from the stdlib comment, though the stdlib comment (written
before this task) says the same thing.

## Scope decision — which operators `no-wrap` refuses

`+`, `-`, `*` only — the three `stdlib/Err.ax`'s own comment calls
"the three that WRAP" (plain `add`/`sub`/`mul`, no `nsw`, silent
two's-complement on overflow; this is also the exact shape of the
`Rpc.ax` bug the same file cites as the motivating incident). `/` and
`%` are already a DIFFERENT hazard, handled a different way: they
trap on a zero divisor today (a runtime check, exit 72), and are
undefined only on the single `INT_MIN / -1` corner (`MM-VAL-3b`).
`<<`/`>>` are undefined on out-of-range shift amounts with no runtime
check at all today — arguably a sharper hazard than `+`/`-`/`*`; it
is left out of this slice anyway, deliberately, because "no
undefined shift" is a different claim from "no silent wraparound"
and deserves its own name and its own reasoning pass, the same way
`no-foreign` and `no-recursion` got separate names for separate
mechanisms instead of one `no-unsafe` grab-bag. Follow-up, not
blocked by this slice: the closed list has room, and `divChecked` /
`remChecked` / `shlChecked` / `shrChecked` already exist to answer a
future `no-untrapped` or similar.

Measured cost of scoping broadly instead: `grep -oE '\(\+ '
self_host/*.ax stdlib/*.ax | wc -l` → 2417; `\(- ` → 836; `\(\* ` →
127. `no-wrap` is not something any function acquires by accident —
it is a narrow, deliberately opt-in claim for the boundary code where
wraparound safety is worth the `Alloc` price, the same posture
`no-cast` already takes (653 casts against 3196 `fn` — a transitive
reading "would refuse nearly everything that reaches the standard
library," `self_host/typecheck.ax:15861`).

## Mechanism, concretely

- New closed-list name `no-wrap`, checked in `checkOneRestrict`
  alongside `no-cast` (LOCAL branch, no effect-row/call-graph
  argument needed).
- `isWrapOp` / `wrapScanInto` / `wrapScanIn` / `wrapScanVec` /
  `wrapScanCond` / `wrapScanArms`: a full copy of
  `castScanInto`'s walk, predicate swapped from "head named `cast`"
  to "head named `+`, `-` or `*`". Duplicated rather than
  parameterized, matching this file's existing convention —
  `castScanInto`'s own comment says its arms "mirror `walkEffects`
  form for form," i.e. this codebase already hand-duplicates a full
  tree walk per collected fact rather than sharing one generic
  walker; `wrapScanInto` follows that precedent instead of
  introducing a new abstraction the file does not otherwise use.
- `restrictNoWrap` / `restrictEmitWraps` / `emitRestrictWrap`: same
  shape as `restrictNoCast` / `restrictEmitCasts` / `emitRestrictCast`,
  except the emitted message names which operator was found (`+`,
  `-`, or `*`) since three different fixes exist (`addChecked`,
  `subChecked`, `mulChecked`) rather than one.
- No new diagnostic code. `docs/reference.md`'s restrict table,
  `emitRestrictUnknown`'s closed-list string, and
  `self_host/explain.ax`'s AX3049/3051/3052 text all get `no-wrap`
  added to their enumerations, the same three places `no-cast`
  appears in each.

## Gate plan

Extend `scripts/check-restrictions.sh`, not a new script — `no-wrap`
is a new name inside the mechanism that gate already exists to
prove, not a new mechanism:

- Section 2 (fixtures answer, controls silent): new fixture
  `tests/diagnostics/383-restrict-no-wrap.ax` added to
  `fixture_expectations`.
- Section 3 (planted violation refused): the `clean.ax` program gets
  a `quietWrap` declaration (checked-only arithmetic, satisfied) and
  a `plant no-wrap` that swaps its body for a raw `+`.
- Sections 1, 4, 5 already generalize (1 is `no-foreign`-specific by
  construction and is unaffected; 4 ablates the single
  `checkRestricts` hook, which covers every restriction name at
  once; 5's manifest sweep is generic over whatever `#restrict=`
  values `symbols` prints).
- The new checks are ablated per the house rule: broken deliberately
  (scope `isWrapOp` to answer 0 unconditionally, so `no-wrap` can
  never fire), confirmed red, restored, confirmed green — reported
  in the implementation follow-up.

## What phase 1 turned out to be (2026-09-04)

Phase 1 as this note defines it — Shape B, the closed-list name
`no-wrap` — was **built on 2026-08-31 in `b7a8e1b`**, in the same
commit that added this file. `checkOneRestrict` gained its arm,
`isWrapOp`/`wrapScanInto` and the rest went in as described,
`tests/diagnostics/383-restrict-no-wrap.ax` and
`scripts/check-restrictions.sh`'s `plant no-wrap` pin it, and no
diagnostic code was minted. The "Gate plan" section above is a
description of what shipped, not of what was planned. Nothing in the
mechanism needed correcting.

**The design was wrong about one thing, and the compiler proves it: a
lexical check matches a SPELLING, and two things wearing those
spellings cannot wrap.** Both were refused, and neither refusal had a
fix the author could take.

*The `for` keyword.* `for` landed on 2026-09-03, three days after
`no-wrap`, and it is desugared **in the parser** (`forWhileBody`) into
`(set for$i (+ for$i 1))` beneath a `(< for$i for$n)` guard, with every
generated node carrying the *keyword's* span. Measured against `5d61c6a`
before the fix, a nine-line program whose only arithmetic is a `for`
loop:

```
E AX3049 p1-for.ax:9:8-11 restriction-violated "`+` in the body of
`countUp`, which claims `restrict(no-wrap)`"
```

Columns 8-11 of line 9 spell `for`. The diagnostic names an operator
the source does not contain, underlines a keyword, and prescribes
`addChecked` — a loop counter cannot be a `Result`. `restrict(no-wrap)`
and the language's own loop keyword were mutually exclusive, and
nothing said so.

Skipping it is **sound and not merely convenient**: the body runs only
while `for$i < for$n`, both `Int`, so `for$i + 1` is at most `INT_MAX`
and the increment cannot overflow. The shape is the parser's alone —
`$` is `AX1001 unexpected character` inside an identifier (measured),
so `for$i` is a name no author can write — and `isForBump` matches the
whole shape (target, head, both operands) so that a desugar which
drifts stops matching and the fixture goes red rather than quiet. A
loop written out by hand is still refused, and so is arithmetic in a
loop's body.

*`Float` operands.* `(+ a b)` on two `Float`s lowers to `fadd`
(`fbinopToLLVM`, `self_host/codegen.ax`; `emitBinop2` picks it from the
operands' float flags), and `fadd`/`fsub`/`fmul` have no wraparound to
refuse. This note's own premise — "`+`, `-` and `*` lower to plain
`add`/`sub`/`mul`" — is false for them. Worse, the fix the diagnostic
named does not typecheck against a `Float`: `addChecked` is
`(-> Int Int (Result Int Error))`. `restrict(no-wrap)` was unsatisfiable
for any body doing float arithmetic.

The operand types exist in exactly one place, `checkNumeric`, and the
checker keeps no per-node types, so the float-typed operator heads are
recorded there (`TC` word 37, `tcFloatOpAdd`) and read once by
`restrictEmitWraps`. The ordering that makes this work is already
written down in `tcWalkDecls`: *"The body first, then its tags"* — a
body is checked before its own `restrict` claim is read. A `Float` `+`
nested inside an `Int` `+` still reports the outer operator.

Both fixes are **checks, not transformations**: no `emitExpr` case
moved and no emitted byte changes, which is the invariant
`check-restrictions.sh` section 1 exists to prove and which it
re-proves over the corpus on every run.

Gated by: `tests/diagnostics/394-restrict-no-wrap-exempt.ax` (the two
exemptions, each beside the case that keeps it narrow — a hand-rolled
loop counter, arithmetic in a loop's body, a `Float` `+` inside an
`Int` one); `tests/selfhost/465-restrict-no-wrap-runs.ax`, which
**runs** a restricted `for` loop and float arithmetic and must exit 60;
and `check-restrictions.sh` section 6, whose negative probe builds a
compiler with each exemption's predicate scoped to a constant and
requires *both* declarations to draw AX3049 again.

## What the design's other blockers measured, re-run 2026-09-04

Two of the three stated blockers still stand against the tree, checked
rather than assumed:

- `grep -c 'with\.overflow\|\bnsw\b\|\bnuw\b' self_host/codegen.ax` is
  still **0**. Shape A's premise holds.
- `restrict(no-wrap, no-alloc)` on `(unwrapOr (addChecked a b) 0)` is
  still refused, with the path:
  `` `addSafe` claims `restrict(no-alloc)` and the body performs Alloc:
  addSafe -> Err$addChecked -> Err$mkError ``. `;@axiom:pure` beside
  `no-wrap` is still `AX3010`, "`pure` claim contradicted: body
  performs Alloc". The pair really is unsatisfiable, and it is in the
  diagnostic's help.

The corpus counts have moved and are re-derived: `(+ ` is **2705** in
`self_host/` and `stdlib/` (was 2417), `(- ` **1018** (was 836), `(* `
**141** (was 127). The conclusion is unchanged — `no-wrap` is a narrow,
deliberately opt-in claim about a region, not a mode anything acquires
by accident.

## What is NOT built, and why — decided, not open

- **Shape A, a codegen trap** (`llvm.sadd.with.overflow`). Not built,
  and not a follow-up of *this* feature. The reason is the one above:
  a restriction changes no emitted byte, and `check-restrictions.sh`
  section 1 spends its largest section proving that over the corpus. An
  opt-in trapping arithmetic mode is a different feature with a
  different invariant and its own gate; it does not extend `no-wrap`
  and must not be spelled as a `restrict(...)` name.
- **`/` and `%`.** Not in `no-wrap`, deliberately. They trap on a zero
  divisor today (`axiom: division by zero`, exit 72), so the hazard
  they carry is `INT_MIN / -1` alone (`MM-VAL-3b`) — a different claim
  from "no silent wraparound", and one that wants its own name.
- **`<<` and `>>`.** Undefined on an out-of-range shift amount with no
  runtime check. Sharper than `+`/`-`/`*` in one way and unrelated in
  another; `divChecked`, `remChecked`, `shlChecked` and `shrChecked`
  already exist in `stdlib/Err.ax` to answer a future `no-untrapped`
  or similarly-named restriction. The closed list has room. This is a
  named follow-up, not a gap in phase 1.
- **`remChecked`/`shrChecked` have no fixture.** Still true: neither
  has a case in `tests/stdlib/312-checked-arithmetic.ax`, which is
  where the other five are pinned at `--opt` 0/1/2/3. Still
  `docs/error-model.md` `ERR-REC-2`'s "H, partly gated", still not
  closed here.
