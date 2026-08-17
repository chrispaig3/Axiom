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

Measured 2026-08-16 against `.axiom-bin/axiom` 0.1.0 (self-hosted).

### 1.1 There is no `Result`, and `Option` is built in

`Some` and `None` are built-in constructors, registered ahead of every
user constructor (`self_host/typecheck.ax`), usable with no declaration
and no import, and spelled in signatures as `(Option Int)`.

`Ok`, `Err` and `Result` are defined nowhere. `(Ok 1)` is `AX3001` in
expression position and `AX3003` in pattern position.

### 1.2 Failure is a sentinel, in 65 places

The standard library signals failure by returning a value from the
success type's own range:

| Module | Sites | Convention |
|---|---|---|
| `stdlib/Sys.ax` | 21 | `-errno`, Darwin's carry-flag protocol normalised into it |
| `stdlib/IO.ax` | 12 | `-errno`, forwarded from `Sys` |
| `stdlib/Utf8.ax` | 6 | `-1` |
| `stdlib/Map.ax` | 6 | `-1` / absent-key |
| `stdlib/Job.ax` | 4 | `-errno` |
| `stdlib/Json.ax`, `stdlib/Path.ax`, `stdlib/Rpc.ax` | 3 each | `-1` |
| `stdlib/Str.ax`, `stdlib/Intern.ax`, `stdlib/Sys/Platform.darwin.ax` | 2 each | `-1` / `-errno` |
| `stdlib/Vec.ax` | 1 | `-1` |

65 sites over 12 files, counted with
`grep -cE "errno|sentinel|\(- 0 1\)"` across `stdlib/*.ax` and
`stdlib/Sys/*.ax`. The count is the migration's size and the baseline
for `ERR-ADOPT-1`; the platform shim is in it because
`Platform.darwin.ax` is where the carry-flag protocol is normalised,
which is the one place the convention is *implemented* rather than
forwarded.

A sentinel is not merely inelegant: it is a value of the success type,
so nothing in the type system distinguishes "the file is 4 bytes long"
from "the call failed with `errno` 4 negated". Every one of these 65
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

**ERR-TYPE-1 (P). The failure type is `Result`, a two-parameter sum.**

```scheme
(pub data Result (a e)
  (Ok a)
  (Err e))
```

Constructor types come out `(a -> Result a e)` and `(e -> Result a e)`.
The success parameter comes first because that is the reading order of
the thing being computed; `Result Int IoErr` is "an `Int`, or an
`IoErr`".

**ERR-TYPE-2 (P). `Result` ships as an ordinary declaration in
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

**ERR-TYPE-3 (P). The canonical error payload is a concrete record, and
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

**ERR-TYPE-4 (P). `Option` is not an error type, and the conversion is
named.** `Option` says *absent*; `Result` says *failed, and here is
why*. `(okOr o e)` and `(toOption r)` convert explicitly. There is no
implicit coercion in either direction: a missing map key and a failed
syscall are different facts and the type is where they stay different.

**ERR-TYPE-5 (P). Error payload fields MUST declare their real types.**
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
(`docs/v1-roadmap.md` P4).

The happy consequence is that the shape a propagation *form* has to
generate — the continuation in the arm — is the shape that converts.
The ergonomics and the stack agree, which is not something to rely on
without checking, and is why this was checked first.

Gated by `tests/stdlib/370-error-propagation.ax`, term 16, with the
scrutinee shape run as its ablation.

**ERR-PROP-4 (P). The compiler SHOULD diagnose a self-recursive call in
the scrutinee of a `match` on its own return type.** Proposed
`AX3035`, `recursion-in-scrutinee`, a **warning**, with a help naming
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

Nothing in the reference-counting work released it: the value is
neither a parameter crossing a boundary (`ERR-MEM-2`) nor a `let`
binding whose scope ends before it is used. Closing it needs the escape
analysis that `MM-LIFE-2c` events 2 and 3 are waiting on, and this
model is now a second caller for that work with a number attached.

A conforming implementation **MUST** reclaim it. Until then the cost is
linear in fallible calls, which is survivable for a compiler that runs
once and is not survivable for the LSP, and `ERR-ADOPT-3` says what to
do about that.

`370-error-propagation.ax` term 8 asserts the **control** — the same
loop with no `Result` allocates nothing — rather than the leak. A
fixture asserting the leak would have to be rewritten the day it is
fixed; a control that isolates it survives the fix.

**ERR-MEM-5 (H). An error record may declare at most 46 payload
words.** `AX3029` refuses a wider block (47 mappable payload words, one
spent on a data cell's tag), and `AX3030` caps a declaration at 64 type
variables. `Error` as specified declares 3. The cliff is nowhere near,
and the rule exists so a future cause-chain does not walk into it.

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

**ERR-REC-2 (P). Every trap gets a value-returning alternative; the
raw operator keeps its semantics.**

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

**ERR-DIAG-2 (P). Proposed codes, none allocated.** The next free
semantic number is `AX3035` (`AX3034` is the highest constructed;
`AX3032` is retired and **MUST NOT** be reused):

| Proposed | Slug | Condition |
|---|---|---|
| `AX3035` | `recursion-in-scrutinee` | `ERR-PROP-4` — warning |
| `AX3036` | `discarded-result` | a `Result`-typed expression in statement position, its value unused — warning |
| `AX3037` | `error-payload-untyped` | a payload field declared `Int` in a type whose constructor is applied to a reference — warning, `ERR-TYPE-5`/`ERR-MEM-1` |

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

**ERR-SUGAR-2 (B). The propagation form is a binding form, and it
cannot be written today.**

The specified surface is a macro, because expansion runs before the
checker (`self_host/expand.ax`) so everything it generates is
type-checked, and because a macro costs no seed rebuild:

```scheme
(try! x (mayFail 1)
  (use x))

; expands to
(match (mayFail 1)
  ((Err e) (Err e))
  ((Ok x) (use x)))
```

The body lands in the **arm**, which is exactly `ERR-PROP-3`'s safe
shape — so the sugar makes the TCO-correct spelling the default one and
the dangerous spelling the one you have to write out by hand. That is
the whole argument for having it.

**It does not work.** A macro parameter used as a binder is renamed by
hygiene, and the renaming does not extend to syntax arriving through a
*different* parameter, so the caller's body cannot see the binding:

```scheme
(macro (bind! x e body) (let ((x e)) body))
(fn (main) (bind! v 41 (+ v 1)))
; E AX3001 undefined-variable "undefined variable `v`"
```

The mechanism is pinned rather than guessed. A template that binds and
reads through the **same** parameter works:

```scheme
(macro (bindSelf! x e) (let ((x e)) x))
(fn (main) (bindSelf! v 42))     ; exits 42
```

So it is not "a macro parameter cannot be a binder". It is precisely:
**a binder introduced through one macro parameter does not scope over
the syntax arriving through another.** That is blocker **B1** in §8, it
blocks every binding form and not just this one — `let*`, `for`, `with`
and any `try!` — and `ERR-SUGAR-2` is `B` rather than `P` because the
design is finished and the expander is what stands in the way.

Until it lifts, the propagation spelling is the `match` above, written
out. It is four lines, it is checked, and it has the right stack
behaviour; it is only the repetition that the sugar was going to buy.

**ERR-SUGAR-3 (P). A contextual wrapper is a function, not a form.**
`(withContext r "reading the manifest")` replaces an `Err`'s `context`
and passes `Ok` through. It needs no binder, so `B1` does not reach it,
and it can ship with the stdlib slice.

---

## 8. What this specification found

Four defects, none of them recorded anywhere before, each found by
probing a claim rather than reading one.

**B1 — a macro binder does not scope over another parameter's syntax.**
`(macro (bind! x e body) (let ((x e)) body))` puts the caller's `body`
outside the binding `x` introduces, so `body` cannot see it; the
same-parameter form works and answers 42. Blocks every binding-form
macro. `docs/macro-system.md` records binder-direction hygiene as
complete; this is the case it does not cover. Blocks `ERR-SUGAR-2`.

**B2 — a two-parameter trait declares and checks, and cannot be
implemented.** `(trait (From a b) where (from :: (-> a b)))` is
accepted; `(impl (From Int Bool) where ((from ...)))` is `AX2003
syntax error` at the `impl`. The one-parameter control compiles and
runs. This is `documented-but-inert` in its purest form: the
declaration surface admits something the implementation surface cannot
express. Blocks `From`-style error conversion; `ERR-TYPE-3` routes
around it.

**B3 — `newtype` is a documented keyword the compiler does not
implement.** `docs/reference.md`'s keyword table lists `newtype` with
the purpose *"Newtype wrapper"*. The compiler answers `AX3027`:
*"`newtype` is neither a declaration keyword nor a visible macro"*.
Doc drift of the exact class `scripts/check-doc-drift.sh` exists to
catch, in a table that gate does not read.

**B4 — a fallible call leaks 32 bytes.** `ERR-MEM-4`. Not a defect of
this model; a defect this model is the first to have a number for.

---

## 9. Conformance summary

| Rule | Status | Held by |
|---|---|---|
| `ERR-TYPE-1`…`5` | P | — design only |
| `ERR-PROP-1` | H | the language having no other mechanism |
| `ERR-PROP-2` | H | `#pure` accepted on construct and inspect |
| `ERR-PROP-3` | **H, gated** | `tests/stdlib/370-error-propagation.ax` term 16 + ablation |
| `ERR-PROP-4` | P | — proposed `AX3035`, not constructed |
| `ERR-PROP-5` | H | effect inference, unchanged |
| `ERR-MEM-1` | H | `fldClass`, `self_host/codegen.ax` |
| `ERR-MEM-2` | **H, gated** | `370-error-propagation.ax` term 4 + ablation |
| `ERR-MEM-3` | H | 176 / 288 bytes, mono / poly, 2000 iterations |
| `ERR-MEM-4` | P | 32 bytes per call; control gated as term 8 |
| `ERR-MEM-5` | H | `AX3029` / `AX3030` |
| `ERR-MEM-6` | R | `linear` enforces nothing |
| `ERR-REC-1` | R | no unwinding exists |
| `ERR-REC-2` | P | traps measured: 72, 71 |
| `ERR-REC-3` | R | handlers are tail-resumptive |
| `ERR-REC-4`, `5` | P | — |
| `ERR-DIAG-1` | H | `mkDiag` is the only channel |
| `ERR-DIAG-2`, `3` | P | — no code allocated |
| `ERR-SUGAR-1` | R | `?` is `AX1001` |
| `ERR-SUGAR-2` | **B** | blocked by B1 |
| `ERR-SUGAR-3` | P | — |

Two rules are gated. Nothing else in this document is implemented, and
the document says so in every row rather than in a note at the end.

---

## 10. Adoption

**ERR-ADOPT-1 (P). The migration is 65 sites and it is not one
commit.** Order, each slice green before the next:

1. `stdlib/Err.ax` — `Result`, `Error`, `mapErr`, `withContext`,
   `okOr`, `toOption`, `andThen`, and the `ERR-REC-2` checked
   operators. Nothing else changes; nothing imports it yet.
2. `stdlib/Utf8.ax`, `stdlib/Str.ax`, `stdlib/Path.ax` — 11 sites, no
   `errno`, pure, no callers outside `stdlib/`. The rehearsal.
3. `stdlib/IO.ax` and `stdlib/Sys.ax` — 33 sites and the `-errno`
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

**ERR-ADOPT-3 (P). The LSP is the constraint on `ERR-MEM-4`.** A
compiler process runs once and exits; 32 bytes per fallible call is
noise. `self_host/lsp.ax` is the one long-lived Axiom program v1 ships,
and it is already the case `docs/v1-roadmap.md` P2 measures. Migrating
the compiler's phases to `Result` therefore **MUST** be re-measured
against `scripts/check-lsp-selfhost.sh`'s per-edit figure, and
`ERR-MEM-4` closed before the LSP's own request path migrates.

---

## 11. Worked example

The shape every rule above converges on — fallible step in the
scrutinee, continuation in the arm, error value bound before it
crosses a boundary:

```scheme
(import Err)

(:: parseAll (-> Vec Int (Result Int Error)))
(fn (parseAll toks acc)
  (if (== (vecLen toks) 0)
      (Ok acc)
      (match (parseOne (vecGet toks 0))          ; fallible: scrutinee
        ((Err e)
         (let ((wrapped (withContext e "parsing the manifest")))
           (Err wrapped)))                        ; ERR-MEM-2: let-bound
        ((Ok v)
         (parseAll (vecTail toks) (+ acc v)))))) ; ERR-PROP-3: the arm
```

Three rules, one shape, and each of them is there because a probe said
so rather than because it reads well.
