# Checked arithmetic — Phase 1 design

Ada round 1 shipped restriction profiles (`no-io`, `no-alloc`,
`no-cast`, `no-cast:deep`, `no-recursion`, `no-foreign`;
`05fb064`/`4a55781`/`7540524`). Three items stayed unstarted:
pre/post contracts (`AX3050` reserved for them,
`docs/error-model.md:871`), range-constrained subtypes, and this one
— checked arithmetic. This note is the design pass required before
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
  only path `no-wrap` leaves open.
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
