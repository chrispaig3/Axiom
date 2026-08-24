# The Axiom Error Model

How an Axiom program represents failure, propagates it, recovers from
it, and is told about it by the compiler.

This document is written the way [memory-model.md](memory-model.md) is:
every claim about the implementation carries the observation that
established it, and every claim about the *design* is marked as such so
nobody mistakes a specification for a description. It was written after
a measurement pass and not before one, which is why several of its rules
say the opposite of what the obvious design would have said.

---

## 0. How to read this document

### 0.1 Rule identifiers

Every normative statement carries a stable identifier — `ERR-TYPE-2`,
`ERR-PROP-3`. Identifiers follow the same discipline as diagnostic
codes: **never renamed, never reused**. A withdrawn rule keeps its
number and is marked withdrawn.

### 0.2 Conformance language

`MUST`, `MUST NOT`, `SHOULD`, `MAY` as in RFC 2119, binding two
audiences, each rule saying which:

- **Implementation obligations** bind the compiler and its emitted
  runtime.
- **Program obligations** bind the Axiom programmer. Nothing checks
  these; each is named rather than left implicit. `ERR-PROP-3` is the
  one that costs a program its stack if ignored.

### 0.3 Status markers

| Marker | Meaning |
|---|---|
| **H** | **Holds today.** The rule names the probe that shows it. |
| **P** | **Planned.** Normative for a conforming implementation; this one does not conform. The rule states what happens *today* instead. |
| **R** | **Refused.** The language deliberately does not provide this, and the rule says why. |
| **B** | **Blocked.** Specified, and prevented from being implemented by a defect elsewhere, which the rule names. |

An **H** rule with no evidence is a bug in this document.

### 0.4 Reproducing the measurements

Every probe here runs against the compiler in the working tree:

```bash
axiom="$PWD/.axiom-bin/axiom"
"$axiom" --diagnostic-format=ai check probe.ax
"$axiom" --diagnostic-format=ai build --input probe.ax --output probe.bin
./probe.bin; echo $?
```

A program's answer is its **exit status**, the low 8 bits of `main`'s
result. That is why several numbers below are reported modulo 256, and
why `ERR-PROP-3`'s probe asserts *completion* rather than a value.

**A `memAlloc` address delta is only a valid measure of allocation
below the allocator's chunk size.** The same loop reads 32.0 bytes per
iteration at 10,000 and at 50,000 iterations and 795.7 at 100,000,
because at roughly 3.2 MB the bump crosses into a chunk that is not
contiguous with the last and the subtraction counts the gap. Every
delta quoted below stays inside one chunk; measurements that cannot be
kept there are reported as per-iteration costs derived from two points.

---

## 1. What exists today

Measured 2026-08-16 against `.axiom-bin/axiom` 0.1.0 (self-hosted), and
re-counted 2026-08-22 where the numbers below say so.

### 1.1 `Option` is built in, `Result` is imported

`Some` and `None` are built-in constructors, registered ahead of every
user constructor (`self_host/typecheck.ax`), usable with no declaration
and no import, and spelled in signatures as `(Option Int)`.

`Ok`, `Err` and `Result` are not built in. They are ordinary
declarations in `stdlib/Err.ax` since 2026-08-16 (§2), reached by
`(import Err)`; without that import `(Ok 1)` is still `AX3001` in
expression position and `AX3003` in pattern position. That asymmetry is
`ERR-TYPE-2` holding rather than a gap, and it is the one difference a
reader of §2 has to carry: `Option` needs no import and `Result` does.

### 1.2 Failure is a sentinel, in 64 places

The standard library signals failure by returning a value from the
success type's own range:

| Module | Sites | Convention |
|---|---|---|
| `stdlib/Sys.ax` | 21 | `-errno`, Darwin's carry-flag protocol normalised into it |
| `stdlib/IO.ax` | 11 | `-errno`, forwarded from `Sys` |
| `stdlib/Utf8.ax` | 6 | `-1` |
| `stdlib/Map.ax` | 6 | `-1` / absent-key |
| `stdlib/Job.ax` | 4 | `-errno` |
| `stdlib/Json.ax`, `stdlib/Path.ax`, `stdlib/Rpc.ax` | 3 each | `-1` |
| `stdlib/Str.ax`, `stdlib/Intern.ax`, `stdlib/Sys/Platform.darwin.ax` | 2 each | `-1` / `-errno` |
| `stdlib/Vec.ax` | 1 | `-1` |

64 sites over 12 files, counted 2026-08-22 with
`grep -cE "errno|sentinel|\(- 0 1\)"` across `stdlib/*.ax` and
`stdlib/Sys/*.ax`, excluding `Err.ax` itself. Recompute it rather than
quoting it: it is a proxy, and the tree moves under it — deleting
`IO.readAll` as unreachable on 2026-08-22 took a site with it. The
count is the migration's size and the baseline for `ERR-ADOPT-1`; the
platform shim is in it because
`Platform.darwin.ax` is where the carry-flag protocol is normalised,
which is the one place the convention is *implemented* rather than
forwarded.

A sentinel is not merely inelegant: it is a value of the success type,
so nothing in the type system distinguishes "the file is 4 bytes long"
from "the call failed with `errno` 4 negated". Every one of these 64
sites depends on a caller remembering.

### 1.3 Two traps and three undefined cases

- **Division or remainder by zero** writes `axiom: division by zero` to
  fd 2 and exits **72**. Probe: `(fn (main) (/ 10 (- 1 1)))`, run,
  status 72. Confirms `MM-VAL-3a`.
- **An effect operation with no handler in dynamic extent** traps and
  exits **71** (`docs/reference.md` §Handling Effects).
- **`MM-VAL-3b`**: `INT_MIN / -1` and shifts of 64 or more are
  genuinely undefined and change answer with `--opt`. No trap.

These are the entire set of ways an Axiom program stops without
returning, and `ERR-REC-2` is the rule that fixes it.

---

## 2. The canonical types

**ERR-TYPE-1 (H). The failure type is `Result`, a two-parameter sum.**
Shipped in `stdlib/Err.ax`.

```scheme
(pub data Result (a e)
  (Ok a)
  (Err e))
```

Constructor types come out `(a -> Result a e)` and `(e -> Result a e)`.
The success parameter comes first because that is the reading order of
the thing being computed; `Result Int IoErr` is "an `Int`, or an
`IoErr`".

**ERR-TYPE-2 (H). `Result` ships as an ordinary declaration in
`stdlib/`, not as a built-in.** This is a deliberate reversal of the
obvious design, and the reason is that a user-declared two-parameter
ADT already does everything a built-in would:

- it checks (`(data Res (a e) (Good a) (Bad e))`, `check` OK — note the
  type-parameter list is **one** group, `(a e)`; `(a) (e)` reads the
  second group as a constructor named `e` and fails with a
  non-exhaustive-match diagnostic pointing somewhere confusing);
- it is **pure** to construct and inspect (§3);
- it is classified as a reference and reclaimed at a release boundary
  even when applied polymorphically (`ERR-MEM-3`).

A built-in costs a change to `self_host/typecheck.ax` and therefore a
seed rebuild plus `scripts/reseed.sh`, on a compiler whose bootstrap
fixpoint is a v1 exit criterion. Nothing measured justifies paying that
before the model has users. Promotion to built-in stays available and
is deferred, not refused; the trigger would be a measured ergonomic
cost of the `(import ...)`, not a preference.

**ERR-TYPE-3 (H). The canonical error payload is a concrete record, and
conversion between error types is explicit.**

```scheme
(pub struct Error
  (code : Int)          ; a stable AXERR number, never reused
  (message : String)    ; what happened, no trailing punctuation
  (context : String))   ; what the caller was doing, "" when none
```

Rust reaches `From<E>` here so `?` can convert on the way out. **Axiom
cannot**: a two-parameter trait *declares and checks*, and its `impl`
is a syntax error —

```scheme
(trait (From a b) where (from :: (-> a b)))   ; OK
(impl (From Int Bool) where ((from ...)))     ; AX2003 syntax error
```

— while the identical one-parameter shape compiles. So conversion is a
function the program calls (`mapErr`), not an instance the compiler
finds. This is recorded as blocker **B2** in §8; if two-parameter
`impl` ever lands, `ERR-TYPE-3` may be revisited, and it keeps its
number when it is.

**ERR-TYPE-3a (H). An error-inspecting combinator MUST take the error
through a parameter declared at its concrete type.** Reading a field
off a `match` binder does not work when the scrutinee is polymorphic:

```scheme
(fn (withContext r ctx)
  (match r
    ((Err y) (Err (Error y.code y.message ctx)))))
; AX3004 type mismatch: expected struct or data type, found _t206
```

The checker instantiates `(Result a Error)`'s constructor field to a
fresh variable and never resolves it against the signature, so `y` has
no fields as far as the arm is concerned. Handing `y` to a function
whose *parameter* is declared `Error` gets the concrete type back, and
`stdlib/Err.ax`'s `errContextOf` exists for exactly that reason.

This is a checker limitation rather than a design choice, and it is
recorded as **B5** in §8. It shapes every combinator in the module, so
it is a rule and not a footnote.

**ERR-TYPE-4 (H). `Option` is not an error type, and the conversion is
named.** `Option` says *absent*; `Result` says *failed, and here is
why*. `(okOr o e)` and `(toOption r)` convert explicitly. There is no
implicit coercion in either direction: a missing map key and a failed
syscall are different facts and the type is where they stay different.

**ERR-TYPE-5 (H). Error payload fields MUST declare their real types.**
Not `Int`. See `ERR-MEM-1` — this is a memory-safety obligation wearing
a type-design hat.

---

## 3. Propagation

**ERR-PROP-1 (H). An error is an ordinary value.** It propagates
through calls, lambdas, closures, data structures and pattern matching
with no special mechanism, because there is none to have: Axiom has no
unwinding, no early return, and no exception. A function that can fail
says so in its return type and every caller does something about it or
does not compile.

**ERR-PROP-2 (H). Constructing and inspecting an error is pure.**
Probe: a two-parameter ADT, a constructor function and a `match`
consumer, both tagged `;@axiom:pure`. `check` is OK and `axiom symbols`
reports `#pure` on both with no `#effects=` beside it. So a `Result`
may be built and taken apart inside a function that claims purity, and
the claim validates.

Recorded honestly: this also means **constructor allocation does not
enter the inferred effect set**. `Alloc` is a built-in effect and a
constructor allocates, so the inference is an under-approximation here
in the sense `MM-EXEC-9a` already names. The error model relies on the
convenient half of that; a conforming implementation that made `Alloc`
precise would make every `Result` constructor `#effects=Alloc`, and
`ERR-PROP-2`'s purity claim would need `Alloc` exempted explicitly
rather than by omission.

**ERR-PROP-3 (H, program obligation). In a recursive function, the
fallible call MUST be the `match` scrutinee and the recursive call MUST
be what an arm answers. Never the reverse.**

This is the load-bearing rule of the whole model and it is not a
stylistic preference:

```scheme
; SAFE - the self call is in tail position inside an arm, and the
; compiler converts the function to a loop
(fn (total n acc)
  (if (== n 0)
      (Ok acc)
      (match (step n)
        ((Err e) (Err e))
        ((Ok v) (total (- n 1) (+ acc v))))))

; UNSAFE - the self call is what the match returns INTO, so it is not
; a tail call, the loop conversion does not fire, and the function
; costs one frame per iteration
(fn (total n acc)
  (if (== n 0)
      (Ok acc)
      (match (total (- n 1) (+ acc 1))
        ((Err e) (Err e))
        ((Ok x) (Ok x)))))
```

Measured: the unsafe shape costs **32 bytes of stack per call**,
survives 250,000 iterations and dies of `SIGSEGV` at **262,144** — 8
MiB of stack, exactly. The safe shape completes **5,000,000**
iterations with a flat stack. The same asymmetry killed the lexer once
already, at a different scale: `lexTokens`/`dispatchChar` cost a frame
pair per token and died between 96 KB and 146 KB of input
(the roadmap's phase 4).

The happy consequence is that the shape a propagation *form* has to
generate — the continuation in the arm — is the shape that converts.
The ergonomics and the stack agree, which is not something to rely on
without checking, and is why this was checked first.

Gated by `tests/stdlib/370-error-propagation.ax`, term 16, with the
scrutinee shape run as its ablation.

**ERR-PROP-4 (P). The compiler SHOULD diagnose a self-recursive call in
the scrutinee of a `match` on its own return type.** Proposed
`AX3041`, `recursion-in-scrutinee`, a **warning**, with a help naming
the arm-tail rewrite. Today nothing says anything: the program compiles,
runs, and dies on an input large enough, which is the failure mode
`ERR-PROP-3` exists to prevent and the one a programmer is least
equipped to see. This code is *proposed*, not allocated: it is not
constructed anywhere, and `scripts/check-doc-drift.sh` checks
construction against `explain --list` in both directions, so it must
not be listed until it is built.

**ERR-PROP-5 (P). Higher-order propagation carries the callee's
effects, not the error.** A combinator taking a fallible function
(`mapResult`, `andThen`) is effect-transparent in that parameter and
`axiom symbols` reports `#effect-params=`; its own body stays pure. No
rule of this model changes effect inference.

---

## 4. Memory

The error model is the first feature designed *after* reference
counting started landing, so these rules are obligations on the design
rather than notes about it.

**ERR-MEM-1 (H). A payload field's declared type decides whether its
contents are reclaimed.** The reference map is computed from declared
field types by `fldClass` (`self_host/codegen.ax`), which answers
*reference* for `String`, for a declared `data` or `struct` type, for a
tuple and for an arrow; *scalar* for the `Int`/`Float`/`Bool`/`Char`
family; and *unclassifiable* for a type variable, a `Ptr` or an alias —
which forces the whole block to an empty map. A `String` stored through
a field declared `Int` is invisible to release and leaks.

So `ERR-TYPE-5`. An error record that declares `(message : Int)` and
casts is not a style problem, it is a leak.

**ERR-MEM-2 (H, program obligation). An error value handed to a self
tail call MUST pass through a `let` binding.**

A `data` block births owned at count 1. Constructed inline in a
tail-call argument, the boundary retain (`MM-LIFE-2c` event 4) takes it
to 2 and the single boundary release returns it to 1 — never 0, so it
never files. Bound to a `let` first, the frame's scope release spends
the birth count and the loop is flat.

Measured over 2000 iterations, each allocating a fresh 32-byte
`String` inside the error value:

| The value is… | bump moves |
|---|---|
| constructed inline in the tail-call argument | 288,176 bytes |
| returned from a function, passed inline | 288,176 bytes |
| **bound to a `let`, then passed** | **176 bytes** |

144 bytes per iteration, leaked, in the two spellings anyone writes
first. Gated by `370-error-propagation.ax` term 4, whose ablation is
exactly the removal of that `let`.

This rule is a program obligation because nothing enforces it. A
conforming implementation **SHOULD** make it unnecessary by spending the
birth count at the boundary, and until one does, the rule stands and
the fixture holds it.

**ERR-MEM-3 (H). A polymorphic `Result` applied at concrete arguments
is classified and reclaimed.** `fldClass` classifies an applied type by
its head, so the question had to be asked separately from `ERR-MEM-2`'s
monomorphic probe. Same loop, same 2000 iterations, `let`-bound:
monomorphic 176 bytes, polymorphic `(Result Int String)` 288 bytes.
Both flat. The model is viable polymorphically, which is the only way
it is worth having.

**ERR-MEM-4 (P). The block a fallible call returns is not reclaimed.**
This is the model's standing cost today and the specification states it
rather than discovering it later:

> A call returning `Result` allocates one block that nothing frees.
> Measured at **32 bytes per fallible call**, identically whether the
> call is matched directly or bound to a `let` first — 32.0 bytes per
> iteration at both 10,000 and 50,000 iterations, against a flat
> control loop with no `Result` in it.

The prerequisite this rule used to name is gone and the leak is not.
`MM-LIFE-2c`'s events 2 and 3 — the ownership pair this rule blamed for
it — shipped on 2026-08-21 (`tests/stdlib/372-arc-owned-results.ax`),
and the 32 bytes survived them untouched. Re-measured 2026-08-22 with
the instrument `372` uses, the arena mark cell's word 0, over 10,000
iterations after a 1,000-iteration warm-up, against
`step : (-> Int (Result Int String))`:

| the call's result is… | bytes/iteration |
|---|---|
| the scrutinee of `(match (step i) ((Ok v) v) ((Err e) 0))` | **32** |
| `let`-bound, then that same `match` | **32** |
| the scrutinee of a `match` whose arms bind nothing | 0 |
| the same call at `(Result String String)` | 0 |
| the control loop with no `Result` in it | 0 |

So the release is emitted and something suppresses it, and the thing
that does is a **binder**. A `match` scrutinee is released after the
merge only when no arm's binder escapes through that arm's body
(`scrutineeReleasable`, `escapesViaBinders` in `self_host/codegen.ax`),
and a binder that reaches its arm's value — bare, or through
arithmetic, which passes value position to its operands — reads as an
escape whatever its type.
The decisive pair, same measurement: the same `Int` read out of the
same frame-owned block by a **field read** costs 0 bytes per iteration
and by a **match binder** costs 32 — because `escapes` tests
`fieldReadIsScalar` on the field-read path and has nothing to test on
the binder path, where the field has already become a bare variable. A
machine scalar cannot alias the block it was copied out of, so the
answer is a field-class test inside a walk that already exists. That is
a narrower prerequisite than the one this rule carried, and naming it
narrowly is the point of re-measuring.

A conforming implementation **MUST** reclaim it. Until then the cost is
linear in fallible calls, which is survivable for a compiler that runs
once and is not survivable for either program that does not — the LSP
per keystroke, the pre-forked server per request — and `ERR-ADOPT-3`
says what to do about that.

`370-error-propagation.ax` term 8 asserts the **control** — the same
loop with no `Result` allocates nothing — rather than the leak. A
fixture asserting the leak would have to be rewritten the day it is
fixed; a control that isolates it survives the fix.

**ERR-MEM-5 (H). An error record may declare at most 46 payload
words.** `AX3029` refuses a wider block (47 mappable payload words, one
spent on a data cell's tag), and `AX3030` caps a declaration at 64 type
variables. `Error` as specified declares 3. The cliff is nowhere near
for an error record — the widest declaration in this repository, the
compiler's own `CG`, sits at 45 — and the rule exists so a future
cause-chain does not walk into it.

**ERR-MEM-6 (R). The model does not use linear types.** `linear` and
`consume` parse and enforce nothing: no use is counted, a linear value
may be used twice or not at all. `Linear T` *is* a real nominal barrier
(`AX3004` against `T`), which is enough to keep a wrapper honest in a
signature and not enough to build ownership on. Every rule above is
correct without linearity.

`MM-LIFE-7`, if it lands, would add two things to this model and change
none of its rules: an error value could **move** into a callee without
retain/release, and a `Result` discarded on a branch could be dropped
early instead of at scope end. Both are optimisations of `ERR-MEM-2`
and `ERR-MEM-4`, not replacements.

---

## 5. Recovery

**ERR-REC-1 (R). There is no unwinding, no early return and no
exception, and the model does not add one.** Recovery is a value
arriving at a `match`. This is not asceticism; it is the only option
the runtime leaves open, and §5.2 says why.

**ERR-REC-2 (H). Every trap gets a value-returning alternative; the
raw operator keeps its semantics.** Shipped in `stdlib/Err.ax`. Two of
the four are gated: `tests/stdlib/371-err-module.ax` term 64 pins
`divChecked`'s zero case, and term 32 pins its `INT_MIN / -1` guard
together with `shlChecked` refusing a shift of 100. `remChecked` and
`shrChecked` ship unpinned, which §10 records with the rest of the
unreached surface.

| Trap today | Alternative | Answers |
|---|---|---|
| `(/ a 0)` — fd 2, exit 72 | `(divChecked a b)` | `(Err DivideByZero)` |
| `(% a 0)` — the same | `(remChecked a b)` | `(Err DivideByZero)` |
| `INT_MIN / -1` — UB, `--opt`-dependent | `divChecked` | `(Err Overflow)` |
| `(<< 1 100)`, `(>> x 64)` — UB | `shlChecked`, `shrChecked` | `(Err ShiftTooWide)` |

`/` and `<<` are unchanged. A checked operator is a different function
with a different type, so no existing program's meaning moves and no
hot loop pays for a check it did not ask for. This is the same decision
`MM-VAL-3b` records for the raw cases: name the sharp edge rather than
round it off silently.

**ERR-REC-3 (R). Effects are not an error channel.** `handle` is
evidence-passing and **tail-resumptive**: the handler's return value is
the operation's result and execution continues at the operation's site.
A handler **cannot abort the computation it handles** — there is no
mechanism by which it could — and an operation with no handler traps
and exits 71 rather than answering. So an `effect` cannot express
"stop, unwind, recover", and a program that models failure as an effect
gets a trap where it wanted a `catch`. `effect` is for *capabilities*;
`Result` is for *failure*.

**ERR-REC-4 (P). `main` renders an error and exits with a code
reserved for the purpose.** A `main` answering `(Result Int Error)`
writes `axiom: {message}` — and `context` when it is non-empty — to fd
2, and exits **70**. The number is chosen to sit beside the two the
runtime already owns and below neither: 71 is the unhandled-operation
trap and 72 is the division trap, so 70 completes the block and a
reader who has seen one has seen the family. Exit codes 1–69 stay the
program's own.

**ERR-REC-5 (P, program obligation). A recovered error MUST NOT be
discarded silently.** `(match r ((Ok x) x) ((Err _) 0))` compiles and
is sometimes right; it is also how a 65-site sentinel migration
recreates the problem it set out to fix. The compiler cannot tell the
two apart, so the obligation is on the program and the review, and
`ERR-DIAG-2` proposes the lint that would make it visible.

---

## 6. Diagnostics

**ERR-DIAG-1 (H). Every diagnostic this model adds goes through
`mkDiag`/`mkDiagFix` at the site that detects the condition, carries a
stable code and a kebab-case slug, and has long-form text in
`self_host/explain.ax`.** Nothing about error handling changes how the
compiler reports; the rule is here so a future contributor does not
invent a second channel for "error-model errors".

**ERR-DIAG-2 (P). Proposed codes.** Six times now this model has
proposed a number and the compiler has spent it first. `AX3035` went on
2026-08-16 to the expander defect that stood in this model's way
(`macro-binder-target`, §7), `AX3036` went on 2026-08-22 to the FFI
(`extern-type`, an `extern` item whose type cannot cross the boundary),
three went to the effect walk: `AX3037` on 2026-08-22
(`axtag-unverifiable`, a `pure` claim over a call the walk cannot
resolve), then `AX3038` (`effect-unverifiable`, the same condition
under a `handle`) and `AX3039` (`axtag-key-typo`, a key one edit from
one the compiler checks) on 2026-08-23; and `AX3040` the same day to
the type system (`result-only-tyvar`, a signature returning a variable
no parameter mentions). The next free semantic number is therefore
`AX3041` (`AX3032` is retired and **MUST NOT** be reused),
and a proposal renumbers again if something builds one before this
model does — which is exactly why these are proposals and not
allocations. Six renumberings is itself evidence: a table of reserved
numbers ages badly beside a compiler under active repair, and the only
thing that keeps it honest is `check-doc-drift.sh` comparing
constructed against listed in both directions.

| Proposed | Slug | Condition |
|---|---|---|
| `AX3041` | `recursion-in-scrutinee` | `ERR-PROP-4` — warning |
| `AX3042` | `discarded-result` | a `Result`-typed expression in statement position, its value unused — warning |
| `AX3043` | `error-payload-untyped` | a payload field declared `Int` in a type whose constructor is applied to a reference — warning, `ERR-TYPE-5`/`ERR-MEM-1` |

Each needs, before it is listed: a construction site, `explain.ax`
text, a `tests/diagnostics/` case with `.axdl`, `.human` and `.json`
goldens blessed by `AXIOM_BLESS=1 scripts/check-diagnostics.sh NNN`,
and a run of that case against a compiler built before the change to
prove it is not vacuous. `scripts/check-doc-drift.sh` checks
constructed-against-listed in **both** directions, so listing one early
turns the gate red.

**ERR-DIAG-3 (P). Poisoning, not cascading.** Where a check on an error
type fails, propagate `TError` and guard downstream comparisons, so one
mistake draws one diagnostic. Reach for a group key only when a real
cascade survives poisoning — the `dedup` pass in the retired Rust
compiler had no call site for its whole life, and the lesson recorded
in [diagnostics.md](diagnostics.md) is to build it *with* one.

---

## 7. Surface

**ERR-SUGAR-1 (R). There is no `?` postfix operator, and there will not
be one spelled that way.** `?` is not an identifier byte: `empty?` is
`AX1001`, and the compiler's own help says so — *"`?`, `~` and `@` are
not identifier characters at all"*. Admitting it is a language change
that moves the lexer, `tree-sitter-axiom/` and `self_host/format.ax`
together. And the change would not be enough, because Rust's `?` means
*return from the enclosing function* and Axiom has no early return: the
operator would have nothing to expand into.

**ERR-SUGAR-2 (H). The propagation form is a binding form.**

The surface is a macro, because expansion runs before the checker
(`self_host/expand.ax`) so everything it generates is type-checked, and
because a macro costs no seed rebuild:

```scheme
(try! x (mayFail 1)
  (use x))

; expands to
(match (mayFail 1)
  ((Err er) (Err er))
  ((Ok x) (use x)))
```

The body lands in the **arm**, which is exactly `ERR-PROP-3`'s safe
shape — so the sugar makes the TCO-correct spelling the default one and
the dangerous spelling the one you have to write out by hand. That is
the whole argument for having it.

**It could not be written until 2026-08-16, and this rule is the
reason the expander changed.** A macro parameter standing in a binder
position was gensymed like a template's own binder, and the renaming
did not extend to syntax arriving through a *different* parameter, so
the caller's body could not see the binding:

```scheme
(macro (bind! x e body) (let ((x e)) body))
(fn (main) (bind! v 41 (+ v 1)))
; before: E AX3001 undefined-variable "undefined variable `v`"
; after:  42
```

The mechanism was pinned rather than guessed, and the pinning is what
made the fix small. A template that binds and reads through the
**same** parameter always worked —

```scheme
(macro (bindSelf! x e) (let ((x e)) x))
(fn (main) (bindSelf! v 42))     ; exits 42, before and after
```

— because the rename table mapped the template's `x` to the gensym on
both sides. Right answer, wrong reason, and the caller's chosen name
appearing nowhere. So it was never "a macro parameter cannot be a
binder"; it was precisely **a binder introduced through one macro
parameter did not scope over the syntax arriving through another**.

The fix is `docs/macro-system.md` **MAC-HYG-10**: a binder position
holding a parameter takes the *argument's* name and is not renamed,
across all three binder positions the expander owns — `let`, `lambda`
parameters, and pattern binders. An argument that is not a name is
`AX3035` rather than the silent wrong expansion it used to be.

`try!` ships in `stdlib/Err.ax` and is gated by
`tests/stdlib/371-err-module.ax` term 16, which does not compile
against an expander without the rule.

**ERR-SUGAR-3 (H). A contextual wrapper is a function, not a form.**
`(withContext r "reading the manifest")` replaces an `Err`'s `context`
and passes `Ok` through. It needs no binder, so it never depended on
`MAC-HYG-10`; it does depend on `ERR-TYPE-3a`, which is why it reads
the error's fields through `errContextOf` rather than in the arm.

---

## 8. What this specification found

Five defects, none of them recorded anywhere before, each found by
probing a claim rather than reading one. Two are fixed.

**B1 — a macro binder did not scope over another parameter's syntax.
FIXED 2026-08-16.** `(macro (bind! x e body) (let ((x e)) body))` put
the caller's `body` outside the binding `x` introduced, so `body` could
not see it; the same-parameter form worked and answered 42, which is
what kept it hidden. It blocked every binding-form macro — `let*`,
`for`, `with`, and `try!` — and `docs/macro-system.md` recorded
binder-direction hygiene as complete, which it was for the direction
anyone had tested. Fixed as `MAC-HYG-10`, with `AX3035` for the
argument that is not a name; `ERR-SUGAR-2` is the form it unblocked.

**B2 — a two-parameter trait declares and checks, and cannot be
implemented.** `(trait (From a b) where (from :: (-> a b)))` is
accepted; `(impl (From Int Bool) where ((from ...)))` is `AX2003
syntax error` at the `impl`. The one-parameter control compiles and
runs. This is `documented-but-inert` in its purest form: the
declaration surface admits something the implementation surface cannot
express. Blocks `From`-style error conversion; `ERR-TYPE-3` routes
around it.

**B3 — `newtype` was a documented keyword the compiler does not
implement. FIXED 2026-08-22.** `docs/reference.md`'s keyword table
listed `newtype` with the purpose *"Newtype wrapper"* for as long as
the table existed. The compiler answers `AX3027`: *"`newtype` is
neither a declaration keyword nor a visible macro"*. The row is gone
and the compiler is unchanged — there is still no `newtype`, which is
now what the table says. Doc drift of the exact class
`scripts/check-doc-drift.sh` exists to catch, in a table that gate does
not read, which is why a probe found it and no gate did.

**B4 — a fallible call leaks 32 bytes.** `ERR-MEM-4`. Not a defect of
this model; a defect this model is the first to have a number for.

**B5 — a `match` binder over a polymorphic scrutinee has no type.**
`(match r ((Err y) y.code))` where `r : (Result a Error)` is `AX3004
expected struct or data type, found _t206`: the checker instantiates
the constructor's field to a fresh variable and never resolves it
against the signature, so the binder has no fields. Passing the binder
to a function whose parameter is declared at the concrete type
recovers it, which is `ERR-TYPE-3a` and the shape every combinator in
`stdlib/Err.ax` takes. Found while writing `withContext`, which is the
first function in this repository to read a field off a polymorphic
match binder.

---

## 9. Conformance summary

| Rule | Status | Held by |
|---|---|---|
| `ERR-TYPE-1`, `2` | **H, gated** | `stdlib/Err.ax`; `tests/stdlib/371-err-module.ax` |
| `ERR-TYPE-3` | **H, gated** | `mapErr`, `371-err-module.ax` term 8 |
| `ERR-TYPE-3a` | H | `AX3004 _t206`; `errContextOf` is the workaround |
| `ERR-TYPE-4` | **H, gated** | `okOr`/`toOption`, `371` term 4 |
| `ERR-TYPE-5` | H | `fldClass` classifies from declared types |
| `ERR-PROP-1` | H | the language having no other mechanism |
| `ERR-PROP-2` | H | `#pure` accepted on construct and inspect |
| `ERR-PROP-3` | **H, gated** | `tests/stdlib/370-error-propagation.ax` term 16 + ablation |
| `ERR-PROP-4` | P | — proposed `AX3041`, not constructed |
| `ERR-PROP-5` | H | effect inference, unchanged |
| `ERR-MEM-1` | H | `fldClass`, `self_host/codegen.ax` |
| `ERR-MEM-2` | **H, gated** | `370-error-propagation.ax` term 4 + ablation |
| `ERR-MEM-3` | H | 176 / 288 bytes, mono / poly, 2000 iterations |
| `ERR-MEM-4` | P | 32 bytes per call; control gated as `370` term 8 |
| `ERR-MEM-5` | H | `AX3029` / `AX3030` |
| `ERR-MEM-6` | R | `linear` enforces nothing |
| `ERR-REC-1` | R | no unwinding exists |
| `ERR-REC-2` | **H, partly gated** | `371-err-module.ax` terms 64 and 32; `remChecked`/`shrChecked` unpinned |
| `ERR-REC-3` | R | handlers are tail-resumptive |
| `ERR-REC-4`, `5` | P | — |
| `ERR-DIAG-1` | H | `mkDiag` is the only channel |
| `ERR-DIAG-2`, `3` | P | — `AX3041`–`AX3043` not constructed |
| `ERR-SUGAR-1` | R | `?` is `AX1001` |
| `ERR-SUGAR-2` | **H, gated** | `try!`; `371` term 16, MAC-HYG-10 |
| `ERR-SUGAR-3` | **H, gated** | `withContext`; `371` term 2 |

Eighteen rules hold, nine of them named by a fixture that carries an
ablation — and one of those nine, `ERR-REC-2`, has a fixture that
reaches two of its four operators, which the row says. What remains is
`ERR-PROP-4`, `ERR-MEM-4`, `ERR-REC-4`/`5`, `ERR-DIAG-2`/`3` and the
migration itself — and the document says so in every row rather than in
a note at the end.

---

## 10. Adoption

**ERR-ADOPT-1 (P). The migration is 65 sites and it is not one
commit.** Order, each slice green before the next:

1. ~~`stdlib/Err.ax`~~ **DONE 2026-08-16** — `Result`, `Error`,
   `mapErr`, `withContext`, `okOr`, `toOption`, `andThen`, `mapOk`,
   `unwrapOr`, the `ERR-REC-2` checked operators, and `try!`. Nothing
   else in `stdlib/` changed and nothing there imports it yet, which is
   the point of doing it first: `tests/stdlib/371-err-module.ax`
   exercises it across a module boundary and no existing caller moved,
   and the FFI fixtures match `Ok`/`Err` across the Rust boundary
   without touching the rest of the module
   (`tests/ffi/demo/050-fallible.ax`,
   `tests/ffi/demo/184-nested-fallible.ax`).

   What that fixture reaches, checked 2026-08-22: `divChecked`,
   `shlChecked`, `try!`, `mapErr`, `andThen`, `okOr`, `toOption`,
   `withContext`, `errorText`, `errCode`, `mkError`, `intMin` and the
   three error codes. **Eight exports are reached by nothing** — no
   fixture, no caller in `self_host/` or `stdlib/`: `isOk`, `isErr`,
   `errMessage`, `errContext`, `mapOk`, `unwrapOr`, `remChecked` and
   `shrChecked`. By this repository's own rule they are documentation
   and not specification until a term reaches them, and there are two
   honest ways out: a term that calls them, or a deletion. Slice 2
   decides it, because it is the first slice with a caller.
2. `stdlib/Utf8.ax`, `stdlib/Str.ax`, `stdlib/Path.ax` — 11 sites, no
   `errno`, pure, no callers outside `stdlib/`. The rehearsal.
3. `stdlib/IO.ax` and `stdlib/Sys.ax` — 32 sites and the `-errno`
   convention. The `Error.code` for these is the errno itself, negated
   back, so no information is invented and none is lost.
4. `self_host/` — the compiler's own phases, which is where the model
   stops being a library and starts being the thing that proves it.
5. The REPL surface, `check-repl-selfhost.sh`'s session bank extended
   with an `Err` at the prompt.

**ERR-ADOPT-2 (P). Every slice keeps `stage2 == stage3`.** No slice
touches the seed until one has to, and the one that does — a built-in
`Result` under `ERR-TYPE-2`, if it is ever justified — lands as
feature-then-`scripts/reseed.sh`, never as both at once.

**ERR-ADOPT-3 (P, amended 2026-08-24). The long-lived programs are the
constraint on `ERR-MEM-4`, and there are two of them.** A compiler
process runs once and exits; 32 bytes per fallible call is noise.

This rule said `self_host/lsp.ax` was "the one long-lived Axiom program
v1 ships". That stopped being true when the socket work landed:
`tests/net/echo-server.ax` is a pre-forked server whose workers run
until they are signalled, driven under CI by `scripts/check-net.sh`, and
it is the larger of the two constraints — its per-request budget is a
request handler's rather than a keystroke's, and the gate drives ten
thousand connections through it. (The sentence was a uniqueness claim
with no probe behind it, which is the class `docs/memory-model.md` §9.1
records as structurally invisible to `check-doc-drift.sh`: the gate
resolves the fixtures a document NAMES and can say nothing about one it
asserts does not exist.)

Both programs hold their memory flat by the same mechanism — a
`__axiom_arena_mark` / `__axiom_arena_reset` bracket around the unit of
work, which `docs/memory-model.md`'s `MM-ALLOC-22` states as the
reclamation strategy rather than as an interim one — so a `Result`
allocated inside the bracket is reclaimed at the boundary and one that
escapes it is not. That is the whole of what `ERR-MEM-4` has to be
measured against, and it is why the 32 bytes are a per-*call* figure and
not a per-*process* one.

Migrating the compiler's phases to `Result` therefore **MUST** be
re-measured against `scripts/check-lsp-selfhost.sh`'s per-edit figure
**and** `scripts/check-net.sh`'s scoped-against-unscoped ratio, and
`ERR-MEM-4` closed before either program's own request path migrates.
Its cause is now named narrowly enough to cost one walk rather than one
analysis, which moves it from a blocker to a task.

---

## 11. Worked example

The shape every rule above converges on — fallible step in the
scrutinee, continuation in the arm, error value bound before it
crosses a boundary:

```scheme
(import Err)

; The form: the fallible call is the scrutinee, the recursion is the
; arm's answer, and `try!` is what writes that without saying it.
(:: parseAll (-> Int Int (Result Int Error)))
(fn (parseAll toks acc)
  (if (== (vecLen toks) 0)
      (Ok acc)
      (try! v (parseOne (vecGet toks 0))
        (parseAll (vecTail toks) (+ acc v)))))   ; ERR-PROP-3: the arm

; The caller attaches what it was doing. `withContext` takes the
; RESULT, not the error - ERR-TYPE-3a is why nothing here reaches into
; an `Err` binder for its fields.
(:: parseManifest (-> Int (Result Int Error)))
(fn (parseManifest toks)
  (withContext (parseAll toks 0) "parsing the manifest"))
```

The recursion sits where `ERR-PROP-3` measured that it must, because
that is where `try!` puts it. Each rule behind this shape is there
because a probe said so rather than because it reads well — and the
one that made the shape *writable* was a hygiene defect in the
expander, not anything about errors at all.
