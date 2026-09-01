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
returning. `ERR-REC-2` gives each trap a value-returning alternative the
program can call instead; `ERR-REC-6` lets a program that did not call
one CONTAIN the trap rather than die of it, at an arena mark, since
2026-08-24.

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
does not**, and since 0.6.0 that is a design decision rather than a
hole: a conversion is an ordinary value the caller supplies, and
nothing searches for one —

```scheme
(struct ConvertOf (a b)
  (convert : (-> a b)))                     ; declares, checks, runs

(:: mapErrWith (-> (ConvertOf e f) (Result a e) (Result a f)))
(fn (mapErrWith c r)
  (match r
    ((Ok x) (Ok x))
    ((Err y) (Err ((c.convert) y)))))       ; dispatch is application
```

— and the caller passes the record: `(mapErrWith (ConvertOf errOfInt) r)`.
Probed 2026-08-31: `check` OK, and the program runs. So the
two-parameter shape is no longer the asymmetry it was; what Axiom still
does not have is INSTANCE SEARCH. `From`'s whole point in Rust is that
the compiler finds the instance from the types at the call site, and
nothing in Axiom searches for a conversion — dispatch is application,
and an instance is a value someone wrote down. (`show` is resolved by
the checker from its argument's static type, but that is one built-in
head rewriting to a known renderer, not a search over declared
instances.) Conversion therefore stays a function the program calls
(`mapErr`) or a record it passes, never an instance the compiler
supplies. This was blocker **B2** in §8, resolved by removal in 0.6.0.

**ERR-TYPE-3a (RETIRED 2026-08-25). An error-inspecting combinator
MAY read the error's fields off the `match` binder.** This rule said
MUST NOT, and it was a checker limitation from the start rather than a
design choice. The limitation is gone:

```scheme
(:: reContext (-> (Result a Error) String (Result a Error)))
(fn (reContext r ctx)
  (match r
    ((Ok x) (Ok x))
    ((Err y) (Err (Error y.code y.message ctx)))))
; compiles; code 1, message "divided by zero", context as given
```

Written 2026-08-16, that was `AX3004 type mismatch: expected struct or
data type, found _a` — the checker instantiated `(Result a
Error)`'s constructor field to a fresh variable and never resolved it
against the signature, so `y` had no fields as far as the arm was
concerned. `ctorPatEnv` landed 2026-08-21 (`a388fc1`) and resolves
exactly that: a constructor pattern's field types are instantiated
against the scrutinee's before its binders are bound. Nothing recorded
the consequence, and the sweep of 2026-08-22 that re-checked every
claim in every document did not catch it — that sweep resolves the
fixtures a document NAMES, and this rule named none.

The number is kept and burned rather than reused, and `stdlib/Err.ax`
keeps `errContextOf`: it is public, `docs/stdlib-api.md` lists it, and
removing an exported name to tidy a rule that no longer binds would
break importers for no gain. What changes is why it is there — a
convenience now, not a requirement. `tests/stdlib/371-err-module.ax`
term 2 pins both spellings against each other, and mutating the direct
read's field drops that term and no other (exit 253 against 255).

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

**ERR-PROP-2 (H, amended 2026-08-31). INSPECTING an error is pure.
CONSTRUCTING one is not, and this rule used to say it was.**

The original probe was a two-parameter ADT, a constructor function and
a `match` consumer, both tagged `;@axiom:pure`; `check` answered OK and
`axiom symbols` reported `#pure` on both with no `#effects=` beside it.
The consumer still does. The constructor no longer does:

```scheme
(data Pair (P Int Int) (Nil))
;@axiom:pure
(:: mkPair (-> Int Pair))
(fn (mkPair n) (P n n))
```

now draws `AX3010 axtag-mismatch: \`pure\` claim contradicted: body
performs Alloc`, while the `match` consumer beside it is accepted
unchanged. **So a `Result` may still be taken apart inside a function
that claims purity; it may no longer be BUILT there.**

**Why the amendment, and what it cost.** This rule used to record, as a
deliberate under-approximation, that *constructor allocation does not
enter the inferred effect set* - and it relied on the convenient half
of that, noting that a conforming implementation which made `Alloc`
precise "would make every `Result` constructor `#effects=Alloc`, and
`ERR-PROP-2`'s purity claim would need `Alloc` exempted explicitly
rather than by omission."

That implementation arrived, and not for precision's sake.
`restrict(no-alloc)` reads the effect row and turns it into a refusal,
and against a row built to omit allocation the refusal could not fire:

```scheme
(data W (Wrap Int) (Empty))
;@axiom:restrict(no-alloc)
(:: mk (-> Int Int))
(fn (mk n) (match (Wrap n) ((Wrap x) x) ((Empty) 0)))
```

checked `OK` while the emitted IR held a `call i64 @axiom_alloc(i64 16)`
inside `@mk`. A claim that cannot be refuted is not a claim, and 0.6.0
shipped 273 of them. `MM-EXEC-9a` records the close and its measured
blast radius: 123 of 3,725 effect rows gained `Alloc`, and seven
`no-alloc` claims in the tree turned out to be false.

**`Alloc` is NOT exempted from `pure`, by decision.** The sentence
above offered that as the alternative and it is refused: `pure` means
an empty definite row, an exemption would have to be carved for every
reader of the row rather than for this one rule, and `Alloc` is the
effect `restrict(no-alloc)` exists to name. The honest statement is the
one at the top - construction allocates, and a constructing function is
not pure. **Measured cost inside this repository: zero.** No
`;@axiom:pure` claim in `stdlib/` or `self_host/` sits on a
constructing function, so nothing here changed but this paragraph.

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
`AX3045`, `recursion-in-scrutinee`, a **warning**, with a help naming
the arm-tail rewrite. Today nothing says anything: the program compiles,
runs, and dies on an input large enough, which is the failure mode
`ERR-PROP-3` exists to prevent and the one a programmer is least
equipped to see. This code is *proposed*, not allocated: it is not
constructed anywhere, and `scripts/check-doc-drift.sh` checks
construction against `explain --list` in both directions, so it must
not be listed until it is built.

**ERR-PROP-5 (H). Higher-order propagation carries the callee's
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

**ERR-MEM-4 (H). The block a fallible call returns is reclaimed.
CLOSED 2026-08-25.** This was the model's standing cost for nine days,
and the specification stated it rather than discovering it later:

> A call returning `Result` allocates one block that nothing frees.
> Measured at **32 bytes per fallible call**, identically whether the
> call is matched directly or bound to a `let` first — 32.0 bytes per
> iteration at both 10,000 and 50,000 iterations, against a flat
> control loop with no `Result` in it.

Every one of those numbers is 0 now, measured the same way. What
follows is the measurement that closed it, kept in full because the
two wrong prerequisites this rule carried before it are the reason it
took three passes to name the right one.

The prerequisite this rule used to name is gone and the leak was not.
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

**And it was still half of one.** A field-class test over the field as
DECLARED closes `(RInt Int)` and leaves `(Ok v)` exactly where it was,
because `Ok`'s field is declared `a`. Measured 2026-08-25 before the
fix, same instrument: a concrete sum type with an `Int` field cost 32
bytes per iteration, and so did `(Option Int)`, whose field is a type
variable that happens to arrive as `Int`. `Result` is the second kind.
A fixture built from the first would have gone green over a fix that
changed nothing about this rule's own subject.

The useful type is therefore the **instantiated** one, and only the
match site has it: `(step i)` at `(-> Int (Result Int String))` is what
makes this `Ok`'s field an `Int`. So the checker records it. In
`bindOnePatArg` — where a constructor pattern's binders are already
bound at their instantiated field types — `stampPatBinderTy` writes the
type's constructor name onto the binder's own node, and codegen's
`binderIsScalar` classifies that name with `scalarTyName`, the same
list `fldClass` classifies a declared field by. A binder the checker
could not resolve is left unstamped, which reads as "assume it can
alias" and is the answer every compiler before this one gave.

Three things about the shape of that fix, each of which was a choice
rather than the only option:

- It is a **twelfth word on `ASTNode`**, not word 6. Word 6 already
  carries an evidence stamp for a call's spine head, which is a
  `TAG_E_VAR` node too, and a type name landing there would be read as
  a node.
- It is a **name, not a type node**. The unifier writes through type
  nodes in place, so a pointer kept across phases can be overwritten;
  `stampFieldStruct` records a name for the same reason.
- The escape walk gets its **own** binder collection, `patBindersEsc`,
  rather than a flag on the shared one. The five other callers of
  `patBindersCg` want the binders as a SCOPE — for shadowing, and for
  the flow environment — and a scalar binder is still a binding. It is
  only the escape question it cannot answer yes to.

**The stamp refuses to take a last answer, and that is measured rather
than defensive.** Its word has three states: `0` for never stamped, a
NAME for "every check that reached this node agreed", and the EMPTY
STRING for "two checks disagreed", which reads back conservative. One
binder node genuinely was checked twice at different types:
`checkImplComplete` synthesized a trait's DEFAULT body into every impl
that omitted the method **without copying the body's nodes**, so two
impls at two types checked one AST, and `impl` declaration order alone
decided which name would survive.

Measured 2026-08-25 on `373-shared-default-binder`, a fixture removed
with traits in 0.6.0: with the disagreement arm removed,
`Ident#String#ident` contained
`call void @axiom_release(i64 %.t0)` — a release of the block the
returned `String` still lives in — and with it present, none. One line
of IR from one word in the checker, and
`scripts/check-fallible-reclaim.sh` asserted both directions until the
construct went (see below).

No program was found that **observes** that release: the field has
another owner at every call site built for it, so nothing reached count
0 and both compilers answered correctly. The honest statement is that
the hazard is real in the emitted code and latent at run time — which
is also why the gate reads the IR rather than an exit status, since a
golden would be green with the release present.

The same sharing had two other symptoms, neither fixed at the time: a
default body whose scrutinee was a **dispatched** trait method was
refused outright (`AX3004`, identically at 0.3.0); and the block's
**shape word** depended on `impl` declaration order in the compiler as
shipped, recorded as `MM-LIFE-2j` in `docs/memory-model.md`.

**All three went with the construct in 0.6.0.** Re-measured 2026-08-31
by building the last-write-wins compiler and diffing emitted IR across
278 fixtures, every `stdlib/` module and `self_host/main.ax` itself:
byte-identical everywhere. Nothing Axiom can now express checks one
pattern binder twice at two types. The disagreement arm is kept as a
guard on a *class* of mistake rather than on any one construct, and
`scripts/check-fallible-reclaim.sh` now asserts that nothing reaches
it — so the day something does, that gate says so.

The cost was linear in fallible calls, which was survivable for a
compiler that runs once and was not survivable for either program that
does not — the LSP per keystroke, the pre-forked server per request.
`ERR-ADOPT-3` said what to do about that; it no longer has to.

`370-error-propagation.ax` said, of its own term 8, that "a fixture
asserting the leak would have to be rewritten the day it is fixed".
This was that day. Term 8 stays — it is what attributes a difference to
the error value rather than to the loop — and **term 32** asserts the
reclamation over 20,000 calls in both spellings. Because three flat
lines cannot tell reclamation from a blind instrument, **term 64**
requires a retained allocation to move the same probe pair, and
`scripts/check-fallible-reclaim.sh` requires the fixture to go RED
under an ablation of `binderIsScalar` — at term 32, and at no other
term. Ablated: exit 95 against 127, and the probe delta back to 640,032
bytes over 20,000 calls, which is this rule's 32 to the byte.

**ERR-MEM-5 (H). An error record may declare at most 46 payload
words.** `AX3029` refuses a wider block (47 mappable payload words, one
spent on a data cell's tag), and `AX3030` caps a declaration at 64 type
variables. `Error` as specified declares 3. The cliff is nowhere near
for an error record — the widest declaration in this repository, the
compiler's own `CG`, sits at 45 — and the rule exists so a future
cause-chain does not walk into it.

**ERR-MEM-6 (R). The model does not use linear types, and as of
2026-08-25 neither does the language.** `linear` and `consume` parsed
and enforced nothing: no use was counted, so a value could be used twice
or not at all. `Linear T` *was* a real nominal barrier (`AX3004` against
`T`), which was enough to keep a wrapper honest in a signature and not
enough to build ownership on. Every rule above is correct without
linearity — which is why the keywords were **refused** rather than left
reserved-and-inert: they now report `AX2004` with migration advice,
alongside `union`, `region`, `foreign` and `deriving`. A marker that
reads as an ownership guarantee and supplies none is worse than no
marker.

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
the runtime leaves open, and `ERR-REC-6` says what the one narrow
exception is and why it is not the general mechanism this rule refuses.

General unwinding stays refused, on its own measurements rather than by
inheritance. Every call would become a two-destination `invoke`, so the
emitter would have to know the enclosing landing pad — but an `invoke`
in argument position splits a block underneath a `phi` the emitter is
building from "whichever block actually reaches the merge", precisely
because there is no block graph to ask. A cleanup pad must release
pending values at an arbitrary point, which is liveness, which is a
control-flow graph, which does not exist. And the unwinder is a hosted
link: 188 undefined symbols for every program, not only the ones that
ask.

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

The capability that LOOKS like an error channel and is not: asking the
caller what to do with a malformed record, and continuing with the
answer. That is `ERR-REC-7`, and `stdlib/Fallible.ax` ships it — the
handler decides per record, it cannot abort, and the loop it serves
never learns anything happened.

**ERR-REC-4 (P). `main` renders an error and exits with a code
reserved for the purpose.** A `main` answering `(Result Int Error)`
writes `axiom: {message}` — and `context` when it is non-empty — to fd
2, and exits **70**. The number is chosen to sit beside the two the
runtime already owns and below neither: 71 is the unhandled-operation
trap and 72 is the division trap, so 70 completes the block and a
reader who has seen one has seen the family. Exit codes 1–69 stay the
program's own.

**ERR-REC-6 (H). A trap may be contained, and only a trap.** Since
2026-08-24, `(__axiom_recover mark thunk)` arms a **recovery point** at
an arena mark and runs `thunk`. Each of the three ways a program stops
without returning then answers the *arming call* with its status
instead of writing to fd 2 and exiting:

| Inside a recovery point | Outside one |
|---|---|
| out of memory answers **70** | `axiom: out of memory (mmap failed)`, exit 70 |
| an unhandled effect answers **71** | `axiom: unhandled effect`, exit 71 |
| division by zero answers **72** | `axiom: division by zero`, exit 72 |

Both halves are in one program per case, at four optimisation levels:
`tests/stdlib/401-recover-effect.ax`, `402-recover-oom.ax`,
`403-recover-div.ax`, gated by `scripts/check-recover.sh`.

**The table has three rows and gains no fourth from status 75.** An
arena reset handed a mark whose chunk is no longer on the active list
traps with status **75** since 2026-08-31 (`MM-ALLOC-16a`), and it is
deliberately outside this mechanism. A recovery point's abort IS an
arena reset — it resets to the arming mark — so answering an invalid
reset by performing another one asks the same corrupted structure the
same question. By the time the trap is reached the unwind walk has
already pushed every chunk it passed onto the free list hunting for one
that was not there, which is precisely the list an abort would then
reset through. 70, 71 and 72 are the *programmer error* class this
paragraph describes, which a process can be written to survive; 75 and
76 are violated implementation invariants (`I8`, and `MM-ALLOC-16b`'s
evidence-record extent), and both are nearer the memory-safety fault
the paragraph above refuses to contain.

**76's exclusion is the sharper of the two.** An abort's whole job is
restoring evidence slots, so answering "a slot points into memory this
reset is about to reclaim" by running the slot-restoring abort asks the
corrupted structure the same question. It is also why the trap needs no
exemption for the recovery path in the other direction: the abort
restores every slot *before* it resets, so the check is already false
by the time it runs (`docs/memory-model.md` `MM-ALLOC-16b`).

**What it is not.** It is not unwinding, not a `catch`, and not an early
return, so `ERR-REC-1` stands as written for everything except these
three. There is no landing pad and no cleanup, nothing runs on the way
out, the point cannot be placed at a frame of the program's choosing —
it is wherever `__axiom_recover` was called — and a recovered extent
cannot be resumed. It also does **not** contain a memory-safety fault: a
SIGSEGV is not a trap, nothing asks the recovery point, and after one
the heap invariants are unknown, which is why Java, Go and Rust all
abort there too.

**Why the narrow version is sound where general unwinding is refused.**
There are no destructors, no finalizers and no stack-allocated data, so
"unwinding" degenerates to restoring the stack pointer, the arena and the
effect slots — and there is nothing to run on the way out.
`docs/memory-model.md` `MM-ALLOC-23` states the memory argument, including
the one thing it does not buy for free (a retain abandoned below the
mark) and the measurement that bounds it: 100,000 aborts hold max RSS at
1,376 KiB, against 419,328 KiB for the same program with nothing to
recover from.

**What it is for.** Failure divides into three classes, and only one of
them is this. *Expected* failure — bad input, a missing file, a timeout —
is `Result` and always was (`ERR-TYPE-1`). A *memory-safety fault* cannot
be contained by any language: after one the heap invariants are unknown,
which is why the paragraph above refuses it and why Java, Go and Rust all
abort there too. Between them sits *programmer error* — out of memory, an
unhandled effect, a division by zero — which is the only class an
in-process abort can serve, and all three of its members were `exit` and
nothing else. A
worker in a pre-forked pool that divides by zero on one request no longer
takes the process with it; the request boundary is already an arena
scope (`MM-ALLOC-22`), and the recovery point is the same boundary
answering a status. Expected failure is still `Result` (`ERR-TYPE-1`),
and a recovery point is not a substitute for one: `ERR-REC-5`'s
obligation applies to a status recovered here exactly as it does to an
`Err` arriving at a `match`.

**Its first consumer is `axiom test`.** A test runner needs exactly
what this mechanism gives and nothing more: one failure ends one unit
of work and the process carries on. So `axiom test` arms one recovery
point per test and reports the status it answers with — 70, 71 or 72 —
and `stdlib/Test.ax` makes a failed assertion an unhandled operation of
an `Assert` effect, which is 71 by the row above rather than by any new
machinery. Measured on `tests/testrunner/mixed-tests.ax`: a suite that
fails in three of these ways still reports the test declared after all
three (`scripts/check-test-runner.sh`).

**A program that never arms one pays nothing.** The mechanism's only
mutable state is a single global that the arm site alone writes, so with
no arm site anywhere `opt` folds the load in the abort to the
initialiser, deletes the global, deletes the three calls the traps make,
and folds all three functions to `ret i64 0`. `scripts/check-recover.sh`
asserts those three properties separately at `opt -O1`, rather than
asserting a line count, because P1's symbol table takes the address of
every function a module defines and so keeps three names alive in every
program either way.

**ERR-REC-7 (H, gated, 2026-08-29). A batch loop's malformed record
is a question for the loop's handler, answered at the point it arises,
and the answer costs the record nothing.** `stdlib/Fallible.ax`
declares one effect with one operation, `(fallibleMalformed message)`,
answering an `Int`: a callee any depth below the loop performs it on a
record it cannot parse and continues with what the innermost handler
answers. Three handlers ship, each a value a program hands to `handle`.
`fallibleSkip` answers `fallibleSkipped` — the most negative `Int`,
which `fallibleIsSkipped` reads and the loop checks once per record —
`(fallibleDefault d)` answers `d`, and `(fallibleCounting tally next)`
counts in `tally` and answers as `next` would. Nesting shadows and
restores as `handle` always has: an inner `fallibleSkip` wins while
its `handle` is live and the outer `(fallibleDefault 100)` answers
again after it exits. `tests/stdlib/410-fallible.ax` pins all of that
line by line, and pins the two halves of `ERR-REC-3` this rule does
not move: the handler cannot abort, and an operation performed with no
handler is class (ii) of `ERR-REC-6` — 71 to a recovery point,
`axiom: unhandled effect` and exit 71 outside one.

*The cost is the rule.* A batch loop has no request boundary, so there
is no arena reset (`MM-ALLOC-22`) and a byte per record is a byte the
process keeps for the run. Measured 2026-08-29 by the arena mark cell,
`370-error-propagation.ax`'s instrument, over 10,000 records of which
1,428 performed the operation:

| operation shape | bytes per operation |
|---|---|
| one argument, a literal message | **0** |
| one argument, an `Int` | **0** |
| two arguments, `(op message fallback)` | 32 — the curried handler's inner closure, never released |
| one argument, a message built per record | 80 — the string, which a handler parameter (a type variable) hides from the release walk |

So the operation takes one argument, the fallback comes from the
handler — `(fallibleDefault d)` allocates its closure once, at the
`handle` — and a program **MUST** pass a literal, or a value it already
holds, never a message built for the record: the loop knows which
record it is on. `410`'s four memory terms hold the three handlers at
0 bytes per record and require a handler that KEEPS a string per
record to move the same instrument. `scripts/check-steady-state.sh`'s
`batch` probe is the RSS half: 2,000,000 records under `fallibleSkip`
at **1,376 KiB**, the same as 200,000, with its `keeping` twin
required to grow past 5×; and the gate builds
`examples/batch-fallible/batch-fallible.ax`, the same loop reading
every record as text, and holds it to the same band at 100,000 and
1,000,000 records (1,392 KiB at both).

*Why a sentinel and not `Option`.* `(Some v)` on every WELL-FORMED
record is a block per record, allocated and released a million times
where a sentinel is one comparison — and a `handle` expression's own
type is the checker's wildcard, so the `Option` would arrive through
a `cast` at every site. A program whose records can hold the most
negative `Int` writes its own one-line handler answering its own
sentinel.

*What this does not change.* `ERR-REC-3` stands: the handler answers,
it does not unwind. The two costs in the table are facts about the
dispatch that the module documents rather than defects it fixes — a
compiler that released the closure and the string would make both
spellings free, and this rule's obligation would shrink to a
preference.

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

**ERR-DIAG-2 (P). Proposed codes.** Eight times now this model has
proposed a number and the compiler has spent it first. `AX3035` went on
2026-08-16 to the expander defect that stood in this model's way
(`macro-binder-target`, §7), `AX3036` went on 2026-08-22 to the FFI
(`extern-type`, an `extern` item whose type cannot cross the boundary),
three went to the effect walk: `AX3037` on 2026-08-22
(`axtag-unverifiable`, a `pure` claim over a call the walk cannot
resolve), then `AX3038` (`effect-unverifiable`, the same condition
under a `handle`) and `AX3039` (`axtag-key-typo`, a key one edit from
one the compiler checks) on 2026-08-23; and `AX3040` the same day to
the type system (`result-only-tyvar`, a type variable the caller chooses
and the callee produces - the slug names the shape it was built for and
is kept as the machine key; the rule covers a function-typed parameter's
own variable since 2026-08-25).

**Then it happened to a number this table had already written down, and
this table did not notice for two days.** `AX3041` went to the parser on
2026-08-22 (`extern-library-name`, an `extern` block's library name that
is not one) and `AX3044` to the namespace pass (`ambiguous-type`) - and
the row below still proposed `AX3041` for `recursion-in-scrutinee`,
while the paragraph above still called `AX3041` the next free number.
Both were false the moment the parser was built, and the sentence that
was supposed to catch it named the wrong comparison: `check-doc-drift.sh`
compared **constructed against explained**, which is a statement about
`explain.ax`, and looked at this document not at all. It compares
constructed against **proposed** now as well, in the one direction that
can fail - a proposal whose number is already spent - so the next
collision is a red gate rather than a paragraph nobody re-read. Found
2026-08-25 while closing `AX3040`'s second shape.

The next free semantic number is therefore `AX3053`: `AX3042` was
SPENT on 2026-08-25 by `undeclared-effect` (a function that performs IO
and does not declare it), `AX3047` was spent on 2026-08-26 by
`sized-integer-type` (a C or Rust primitive spelling in type position,
which is a type VARIABLE and so was silently accepted), `AX3048` the
same day by `deprecated-name` (a reference to a name its declaration
marks `;@axiom:deprecated`, a warning by design - see
`tests/diagnostics/severity.policy`), `AX3049`, `AX3051` and `AX3052`
on 2026-08-29 by the `restrict(...)` AXTAG (`restriction-violated`, an
error; `restriction-unverifiable`, a warning in the same policy file;
`restriction-unknown`, an error - `docs/reference.md`, AXTAG Keys),
`AX3050` is RESERVED below for the contracts work that follows the
restrictions, `AX3043` and `AX3045` are still unspent and stay where
they are, `AX3044` is the namespace pass's, and `AX3032` is retired and
**MUST NOT** be reused. `AX3055` was spent on 2026-08-29 by
`effect-op-untyped` (an effect operation that declares no type - an
error, because the handler check and the call's arity check both stand
on that arrow); it sits above `AX3053` and `AX3054`, which the
effect-system design of the same day names for `unhandled-operation`
and `effect-name-reserved`, and it was taken from the free end because
the number that design named for it, `AX3052`, had been spent by the
restrictions first - the tenth number this section has had to
reconcile, and the second allocated from the free end rather than
surrendered. `AX3056` was spent on 2026-08-30 by `struct-field-untyped`
(a struct field whose type the parser could not read - an error, for
AX3055's reason one form over: `fldClass` cannot classify the empty
type variable the parser answers for a missing `:`, so the field
leaves the block's reference map and `MM-LIFE-2c` event 5, and a value
stored into it is freed under the program, measured at exit 139). It
too was taken from the free end, above `AX3053` and `AX3054`, which
stayed reserved - the eleventh reconciliation and the third from the
free end.

`AX3053` was SPENT on 2026-08-30 by `unhandled-operation`: a custom
effect still in `main`'s effect row when inference finishes, which - a
`handle` being the only construct that discharges one - means nothing
handled it, and an operation of it would write `axiom: unhandled
effect` on fd 2 and exit 71. It is the first number this section has
recorded as a WARNING that was DESIGNED as one rather than staged
toward an error, alongside `AX3048`, and the reason is in
`tests/diagnostics/severity.policy`: on the two closure shapes the
evidence is one-sided in both directions at once, so an error would
refuse a program that runs and accept one that traps. This is a
reserved number reaching its own proposal rather than a
reconciliation - the first time in this section - so the count of
reconciliations stays at eleven. `AX3054` was SPENT on the same day by
`effect-name-reserved` — an `effect` declared with a built-in effect's
name, which a handle list resolves to the built-in, so the declaration
can never be handled and the row it produces says the program reaches
the outside world when it does not. An error with no warning stage,
because there is no correct program on the other side of it. The same
commit retired `Err` as a sixth built-in effect name: nothing inferred
it, and its own AXTAG spelling could not reach it, so a handle list
naming it draws `AX3016` like any other undeclared name. The reserved
block below is now empty and the next free semantic number is
`AX3057`.

`AX3047` is the ninth number this section has had to reconcile, and the
first one it allocated rather than surrendered: it was taken from the
free end deliberately, leaving the three proposals below untouched.
That is the rule working in the other direction - a new code goes above
the reserved block, not into it. `discarded-result` renumbered to
`AX3046` when `AX3042` was built under it - which is this paragraph's
own rule working, and the collision check below is what caught it. A
proposal renumbers again if something builds one before this model does,
which is exactly why these are proposals and not allocations. Eight
renumberings is itself the evidence: a table of reserved numbers ages
badly beside a compiler under active repair, and prose saying so is not
what keeps it honest.

| Proposed | Slug | Condition |
|---|---|---|
| `AX3046` | `discarded-result` | a `Result`-typed expression in statement position, its value unused — warning (was `AX3042` until that number was built as `undeclared-effect`) |
| `AX3043` | `error-payload-untyped` | a payload field declared `Int` in a type whose constructor is applied to a reference — warning, `ERR-TYPE-5`/`ERR-MEM-1` |
| `AX3045` | `recursion-in-scrutinee` | `ERR-PROP-4` — warning |
| `AX3050` | `contract-malformed` | a `;@axiom:pre(...)`/`post(...)` whose value does not parse as an expression, does not type-check as `Bool` against the signature, or names `result` where the declared result is absent — error; reserved 2026-08-29 between two numbers the restrictions spent, so that the contracts land on the number their design names |

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
`MAC-HYG-10`. It reads the error's fields through `errContextOf`
rather than in the arm because `ERR-TYPE-3a` required that when it was
written; since that rule's retirement on 2026-08-25 the indirection is
a kept name rather than a necessity, and `371` term 2 now checks the
direct spelling against it.

---

## 8. What this specification found

Five defects, none of them recorded anywhere before, each found by
probing a claim rather than reading one. Four are fixed; the fifth,
`B2`, was resolved by removal in 0.6.0, so none is open.

**B1 — a macro binder did not scope over another parameter's syntax.
FIXED 2026-08-16.** `(macro (bind! x e body) (let ((x e)) body))` put
the caller's `body` outside the binding `x` introduced, so `body` could
not see it; the same-parameter form worked and answered 42, which is
what kept it hidden. It blocked every binding-form macro — `let*`,
`for`, `with`, and `try!` — and `docs/macro-system.md` recorded
binder-direction hygiene as complete, which it was for the direction
anyone had tested. Fixed as `MAC-HYG-10`, with `AX3035` for the
argument that is not a name; `ERR-SUGAR-2` is the form it unblocked.

**B2 — a two-parameter trait declared and checked, and could not be
implemented. RESOLVED BY REMOVAL 2026-08-31 (0.6.0).**
`(trait (From a b) where (from :: (-> a b)))` was accepted;
`(impl (From Int Bool) where ((from ...)))` was `AX2003 syntax error`
at the `impl`, while the one-parameter control compiled and ran. That
was `documented-but-inert` in its purest form: the declaration surface
admitted something the implementation surface could not express. Both
keywords now report `AX2004` before anything else runs, and the
capability record that replaced them takes two parameters with no
asymmetry — `(struct ConvertOf (a b) (convert : (-> a b)))` declares,
checks and runs, probed 2026-08-31. What the defect blocked,
`From`-style *implicit* conversion, is refused by design now rather
than by a hole; `ERR-TYPE-3` states the design.

**B3 — `newtype` was a documented keyword the compiler does not
implement. FIXED 2026-08-22.** `docs/reference.md`'s keyword table
listed `newtype` with the purpose *"Newtype wrapper"* for as long as
the table existed. The compiler answers `AX3027`: *"`newtype` is
neither a declaration keyword nor a visible macro"*. The row is gone
and the compiler is unchanged — there is still no `newtype`, which is
now what the table says. Doc drift of the exact class
`scripts/check-doc-drift.sh` exists to catch, in a table that gate does
not read, which is why a probe found it and no gate did.

**B4 — a fallible call leaks 32 bytes. FIXED 2026-08-25.**
`ERR-MEM-4`. Not a defect of this model; a defect this model is the
first to have a number for, and the number is what closed it: the
release was already emitted and a `match` binder was suppressing it,
which no amount of reading the ownership rules would have said. The
first diagnosis blamed `MM-LIFE-2c`'s ownership events and was wrong —
they shipped and the 32 bytes did not move. The second named a
field-class test on the binder path and was half right: it closes a
concrete `Int` field and leaves `(Ok v)` untouched, because the useful
type is the INSTANTIATED one and only the checker has it.

**B5 — a `match` binder over a polymorphic scrutinee has no type.
FIXED 2026-08-21, RECORDED 2026-08-25.** `(match r ((Err y) y.code))`
where `r : (Result a Error)` was `AX3004 expected struct or data type,
found _a`: the checker instantiated the constructor's field to a
fresh variable and never resolved it against the signature, so the
binder had no fields. Passing the binder to a function whose parameter
is declared at the concrete type recovered it, which was `ERR-TYPE-3a`.
Every combinator in `stdlib/Err.ax` is still written that way, because
those are public names and the shape costs nothing — not because the
rule still binds.

`ctorPatEnv` closed it five days later (`a388fc1`), as a side effect of
unrelated work on nested patterns, and **the four days between that
and the sweep of 2026-08-22 are the interesting part**: that sweep
re-checked every claim in every document against the compiler that was
there, and this claim survived it. It could not have done otherwise.
The sweep resolves the fixtures a document names and re-runs them; B5
named no fixture, because a defect has none. A claim that something
does NOT work is invisible to a gate built out of things that do, and
this repository has now made that mistake twice — the other is
`ERR-ADOPT-3`'s uniqueness claim, recorded in `docs/memory-model.md`
§9.1. The fixture that would have existed if the negative had been
false is `tests/stdlib/371-err-module.ax`, and it exists now: term 2
runs the direct read and the routed one and compares their answers, so
the claim is pinned by a program rather than by a sentence.

The fixture it should have had is `tests/stdlib/371-err-module.ax`
term 2, which now carries both spellings and compares them.

---

## 9. Conformance summary

| Rule | Status | Held by |
|---|---|---|
| `ERR-TYPE-1`, `2` | **H, gated** | `stdlib/Err.ax`; `tests/stdlib/371-err-module.ax` |
| `ERR-TYPE-3` | **H, gated** | `mapErr`, `371-err-module.ax` term 8 |
| `ERR-TYPE-3a` | **R** | retired 2026-08-25 — the limitation it recorded is gone (`ctorPatEnv`); `371` term 2 pins both spellings |
| `ERR-TYPE-4` | **H, gated** | `okOr`/`toOption`, `371` term 4 |
| `ERR-TYPE-5` | H | `fldClass` classifies from declared types |
| `ERR-PROP-1` | H | the language having no other mechanism |
| `ERR-PROP-2` | H | `#pure` accepted on INSPECT; refused on CONSTRUCT with `AX3010` since 2026-08-31 |
| `ERR-PROP-3` | **H, gated** | `tests/stdlib/370-error-propagation.ax` term 16 + ablation |
| `ERR-PROP-4` | P | — proposed `AX3045`, not constructed (`AX3041` was spent by the parser) |
| `ERR-PROP-5` | H | effect inference, unchanged |
| `ERR-MEM-1` | H | `fldClass`, `self_host/codegen.ax` |
| `ERR-MEM-2` | **H, gated** | `370-error-propagation.ax` term 4 + ablation |
| `ERR-MEM-3` | H | 176 / 288 bytes, mono / poly, 2000 iterations |
| `ERR-MEM-4` | **H, gated** | `370-error-propagation.ax` terms 32 + 64, and `scripts/check-fallible-reclaim.sh` ablates the compiler |
| `ERR-MEM-5` | H | `AX3029` / `AX3030` |
| `ERR-MEM-6` | R | `linear` enforces nothing |
| `ERR-REC-1` | R | no unwinding exists |
| `ERR-REC-2` | **H, partly gated** | `371-err-module.ax` terms 64 and 32; `remChecked`/`shrChecked` unpinned |
| `ERR-REC-3` | R | handlers are tail-resumptive |
| `ERR-REC-4`, `5` | P | — |
| `ERR-REC-7` | **H, gated** | `stdlib/Fallible.ax`; `410-fallible.ax` — thirteen values, four of them memory terms with an ablation; `389-unhandled-at-main.ax` for the missing handler, which `AX3053` names at compile time since 2026-08-30 (410 gave up its two undischarged terms to it); `scripts/check-steady-state.sh`'s `batch` probe, and `examples/batch-fallible` under the same gate |
| `ERR-DIAG-1` | H | `mkDiag` is the only channel |
| `ERR-DIAG-2`, `3` | P | — `AX3043`, `AX3045`, `AX3046` not constructed; gated against collision (`AX3042` was, and renumbered `discarded-result`) |
| `ERR-SUGAR-1` | R | `?` is `AX1001` |
| `ERR-SUGAR-2` | **H, gated** | `try!`; `371` term 16, MAC-HYG-10 |
| `ERR-SUGAR-3` | **H, gated** | `withContext`; `371` term 2 |

Twenty rules hold, eleven of them named by a fixture that carries an
ablation — and one of those ten, `ERR-REC-2`, has a fixture that
reaches two of its four operators, which the row says. What remains is
`ERR-PROP-4`, `ERR-REC-4`/`5`, `ERR-DIAG-2`/`3` and the migration
itself — and the document says so in every row rather than in a note at
the end.

---

## 10. Adoption

**ERR-ADOPT-1 (P). The migration is 64 sites by §1.2's `grep` proxy,
and 30 public functions over 7 modules by the metric that is gated. It
is not one commit.** The proxy sizes the work and is recomputed rather
than quoted (§1.2). The gated unit is a public function whose own
doc-comment states a sentinel contract - what the migration ports, and
what a caller depends on - recorded in `compat/SENTINELS` and
recomputed by `scripts/check-compat.sh`, which fails any module that
RISES. A module may fall freely, and the number in `compat/SENTINELS`
is lowered in the same commit that lowers the count: that is the
direction, gated before anything is ported. Order, each slice green
before the next:

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
3. `stdlib/IO.ax` and `stdlib/Sys.ax` — the `-errno` convention. The
   `Error.code` for these is the errno itself, negated back, so no
   information is invented and none is lost.

   **`IO.ax`'s half is done, 2026-08-26.** Eight calls answer
   `(Result Int Error)`: `writeFile`, `appendFile`, `removeFile`,
   `renamePath`, `fileSize`, `makeDirAll`, `removeDir` and `copyFile`,
   all through one converter, `ioResult`. `IO.ax`'s census went **8 to
   1** — `writeStr` is what remains, and it is the hot printing path
   rather than a filesystem call, so it is its own decision.

   It was far smaller than this list implied: `self_host/` calls none
   of the eight. The real call sites were **one internal use and two
   test fixtures**, and porting them gave `unwrapOr`, `isErr` and
   `errCode` the callers §10's own note asks for. `055-filesystem.ax`
   now asserts an errno through `errCode` rather than comparing
   against `(- 0 2)` — which is the assertion `Result` makes possible
   and the sentinel convention did not, because "it failed with 2" and
   "it answered 2" were the same Int.

   **`Sys.ax`'s filesystem half is done too, the same day.** Seven raw
   wrappers answer `(Result Int Error)` through `sysResult`:
   `sysWriteFile`, `sysAppendFile`, `sysUnlink`, `sysMkdir`,
   `sysRmdir`, `sysRename`, `sysFileSize`. `IO.ax`'s wrappers RE-WRAP
   rather than convert now — `Sys` has the errno and `IO` has the path,
   so the code carries through and only the message is rebuilt.
   `Sys.ax`'s census: **13 → 7**; the whole library **30 → 17**.

   **The claim that `Sys` sits below `Err` was wrong, and it was load
   bearing.** `Err` imports only `Str`; `Str` imports `Mem` and `Vec`.
   There is no cycle, and `(import Err)` in `Sys.ax` compiles first
   try. This slice was deferred once on a dependency that does not
   exist — *read the import graph before believing an ordering claim
   about it.*

   **The port surfaced a wrong-code path the checker cannot see.**
   `makeDir`'s body is one `sysMkdir` call and its signature says
   `Int`. When `sysMkdir` began answering a `Result`, `makeDir` kept
   type-checking and started returning a **heap address** where an
   errno belonged — because `Int` is the universal heap-handle type.
   Nothing refused it; `tests/stdlib/055-filesystem.ax` printed
   `got=4372103456 want=0`, and that is what caught it. A fixture
   asserting an observed VALUE stands exactly where the type system
   does not.

   **The process half is done too.** `sysSpawn`, `sysWaitPid`,
   `sysRun`, `sysRunPath` and `sysRandomBytes` answer
   `(Result Int Error)`. `sysRun`'s three-way contract is now split by
   the TYPE rather than by a sign: **`Err` means the child never ran**
   (the spawn's own errno), `Ok` means it ran and carries what it
   answered, including `128+n` for a signal. That is the distinction
   this file's own comment says a driver must not lose. `Sys.ax`'s
   census: **13 → 3**; the library **30 → 13**.

   **The three net calls are deliberately NOT ported.** `netPollWait`
   runs inside the echo server's event loop, so an `(Ok n)` block would
   allocate per poll wake, outside the per-connection arena scope —
   and `scripts/check-net.sh` asserts memory ratios on exactly that
   server. Risking a measured gate for no safety gain is the wrong
   trade, and it is the same reasoning that leaves `IO.writeStr` on a
   sentinel. `runTool` in `self_host/driver.ax` unwraps at the stdlib
   boundary for the same reason of scope: the compiler's own phases are
   slice 4.

   **The socket-CONFIGURATION half is done, 2026-08-31.** Seven calls
   answer `(Result Int Error)` through `sysResult`: `netBind`,
   `netListen`, `netConnect`, `netShutdown`, `netSetOptInt`,
   `netSetBlocking` and `netSetNonBlocking`. Each answers nothing but
   whether it managed what it was asked to do, so `Ok 0` is the whole
   of the success and the errno is `Error.code`. `stdlib/Sys.ax`'s
   census: **26 → 19**; the library **29 → 22**
   (`scripts/check-compat.sh`, 30 checks).

   **The slice line is WHERE THE CALL RUNS, not what it does.** All
   seven run once per socket. What is left in `Sys.ax` is per-connection
   (`netAccept`, `netAcceptFrom`), per-wake (`netPollWait`,
   `netPollSignalAt`) or per-write (`sysWriteFd`, which `IO.writeStr`
   forwards) — the exclusions this section already states, and the
   paragraph below is what actually holds them.
   `netSocketTcp`/`netSocketTcp6` are left for a different
   reason: they are nullary and answer the descriptor itself, so
   porting them retypes every `lsn` and `cli` *binding* in eight files
   rather than one expression at each call site.

   The blast radius was **47 call expressions over eight files**, all
   in `tests/` and `examples/`: `stdlib/` and `self_host/` call none of
   the seven. Every site that compared the answer against `0` is now
   `isOk` or `isErr`, and `tests/net/echo-server.ax` renders a failed
   bind through `errMessage` and `errCode`.

   **Slice 1's "eight exports are reached by nothing" is stale, and
   this slice is not what closed it.** Counted 2026-08-31 over
   `stdlib/`, `self_host/`, `tests/` and `examples/`, excluding
   `Err.ax` itself, at the commit before this one: `isOk` 17, `isErr`
   21, `unwrapOr` 73, `errMessage` 3, `errContext` 1, `mapOk` 1,
   `remChecked` 2, `shrChecked` 1. All eight already had a caller —
   four of them only through `tests/stdlib/371-err-module.ax`, which
   grew to reach them. This slice takes `isOk` to 28, `isErr` to 25 and
   `errMessage` to 4. The list above is left in place because it is
   what the decision was made against; it is not a description of the
   tree today, and a reader deciding whether to delete a name must
   recount rather than quote.

   **A CALLEE UNDID THE EXCLUSION FROM UNDERNEATH, and `symbols`
   is what saw it.** `netAcceptFinish` — shared by `netAccept` and
   `netAcceptFrom` — calls `netSetNonBlocking` on the target where the
   kernel does not take `SOCK_NONBLOCK`, which is once per accepted
   connection. Porting that callee gave **`netAccept` and
   `netAcceptFrom` `Alloc`**, an `(Ok 0)` per connection allocated
   *below* the echo server's arena mark and therefore never reclaimed.
   The fix is a private `netSetNonBlockingRaw` answering the raw
   result, with the `Result` as the public skin over it.

   **And `check-net.sh` would NOT have caught it.** Measured
   2026-08-31 with the allocation restored to the accept path: the
   gate stayed green at **182×** against its floor of 50 (344× with
   the split), and the scoped arm's growth over 9,800 connections rose
   from 400 KiB to 512 KiB — about 12 bytes per connection, which is
   inside what a page-granular RSS reading can be asked to resolve.
   So the sentence above — "risking a measured gate" — overstates what
   the gate measures. The ratio floor is sized to catch an arena that
   stopped reclaiming, not one 32-byte block per connection. The
   exclusion still stands, and it now stands on `#effects=` in
   `axiom symbols`, which is exact, rather than on a ratio that is not.

   **The "did it work" half is done, 2026-09-01.** The same rule as the
   slice above, applied to what was left: every call in `Sys.ax` whose
   ENTIRE answer is whether it worked. `sysCloseFd`, `netPollAddRead`,
   `netPollDelRead`, `sysSignalBlock` and `sysKill` answer
   `(Result Int Error)`. `stdlib/Sys.ax`'s census: **19 → 14** by the
   port, and **14 → 13 failure with 0 → 1 absence** by a census fix
   described below. The library is **16 failure + 10 absence**.

   Six WIDENED rows, and the sixth is collateral worth naming:
   `sysFileExists` gains `Alloc` because it closes the descriptor it
   opened. That is the **only** such row — `verify-compat.py generate`
   over `stdlib/` before and after the `sysCloseFd` port differs in
   exactly two rows, `sysCloseFd` and `sysFileExists` — because every
   other function in the library that closes a descriptor already
   allocated. No `no-alloc` module reaches either name.

   **No callee undid an exclusion this time, and it was checked rather
   than assumed.** `netAccept` is `#effects=IO`, `netAcceptFrom`
   `#effects=IO,Mut` and `netPollWait` `#effects=IO,Mut` after the
   port, unchanged. That check is the standing cost of the previous
   slice's finding.

   **`netPollSignalAt` was never a failure, and the census said it
   was.** It answers "the signal named by event `i`, or a negative when
   that event is not a signal at all"; every bad-path answer it writes
   is a hand-written `-1`, and all five call sites read it as a
   presence test — `tests/stdlib/315-signal-in-poll.ax:131` asserts
   `< 0` for "a socket event is not read as a signal". That is
   `ERR-REC-3`'s **absence**, wanting `Option`. It was filed under
   `failure` because `sentinel_census` let a body's mere *mention* of a
   syscall beat its `-1` returns, and its Linux arm reads a `signalfd`
   whose result is compared and never returned.

   `verify-compat.py` follows the syscall result to the answer now,
   through a `let` binder as well as directly. The direct-only version
   was written first and **also moved `sysNowMonotonic`**, which is a
   real failure forwarding `clock_gettime`'s errno through exactly that
   binder — a false positive at a population of two, which is the whole
   argument for following the binding. The rule is narrow by
   construction: a body with no `-1` in return position never reaches
   it, so `netAccept` is untouched. Measured over `stdlib/`, it moves
   exactly one row.

   It is recorded rather than ported. Its Linux arm folds a short
   `signalfd` read into the same `-1`, so it conflates absence with
   failure and porting it means **splitting two outcomes**, not
   rewrapping one.

   **`check-compat.sh`'s census floor expired on this slice, and is
   gone.** It read `total_now < 30` against a population of 38; this
   slice takes the census to 26, so the gate went red for the migration
   *succeeding*. What replaces it is stricter, not looser: the computed
   census must agree with `compat/SENTINELS` **row for row**, which is
   the rule this section already states. It additionally catches a port
   that lowers the count and leaves the file stale — which the floor
   passed in silence — and the "did the rule stop matching" question
   the floor was really asking is a named ablation now: a public
   function forwarding a raw syscall is planted in a copy of `stdlib/`
   and the census must count it. Both directions were ablated.

   **And the gate died halfway through reporting.** Under
   `set -euo pipefail`, the `diff a b | sed | head` that prints a
   census disagreement exits 1 and takes the script with it, so a tree
   with two faults reported one and the probes below never ran. Three
   such pipelines are braced now. This is the "a gate that reports
   LESS than it knows" hazard, found inside the gate written to refuse
   it.

   **`unwrapOr` with a constant is not a port, and it cost three
   defects here.** Wherever the sentinel carried WHICH failure, a
   fallback value destroys it and nothing complains:

   - `Job.jobSubmit` — a failed spawn became pid `0`, which is not
     `< 0`, so the pool counted it live and `sysWaitPid 0` waited for
     any child in the group. `302-job` **hung** rather than failed.
   - `993-filesystem-verbs` — `(== (unwrapOr … 0) -2)` is silently
     false, so the case counted one fewer success and exited 1 for 77.
   - `305-path-search` — printed the fallback for every failure, which
     is the vacuous pass that fixture's own comment exists to prevent.

   All three are `match` now. The rule: **`unwrapOr` is safe only where
   the fallback is genuinely equivalent to the error.**
4. `self_host/` — the compiler's own phases, which is where the model
   stops being a library and starts being the thing that proves it.

   **Measured 2026-08-26, and this slice is almost entirely
   mis-specified.** Twenty-five declarations in `self_host/` carry a
   sentinel contract. Classified by what the sentinel MEANS:
   **twenty-one are absence, not failure** — `namedFieldIndex` answers
   "where the pattern mentions field `n`, or -1"; `structFieldOf`
   answers "0 when the struct does not declare the name";
   `findExternUnit`, `scopeFindIdx`, `slotFirstIndex`, `expRepIndex`
   and the rest are the same shape. They are LOOKUPS. A lookup that
   finds nothing has not failed.

   Of the remaining four, `tcAddExtern`'s comment is about a parameter
   rather than a return, `targetCode`'s `-1` is an unknown target
   *name* the caller already refuses loudly, and `runTool` is the one
   genuine failure — bounded at the stdlib edge, where it unwraps
   `sysRunPath` to 127.

   So the `Result` work in this slice is **one function**, and it is
   done.
5. The REPL surface, `check-repl-selfhost.sh`'s session bank extended
   with an `Err` at the prompt.

### 10.1 What is actually left, measured rather than planned

Classifying every remaining sentinel by whether it reports **absence**
or **failure** — §5's own distinction, the one this model opens with —
changes what "finishing the migration" means.

| | absence (wants `Option`) | failure (wants `Result`) |
|---|---|---|
| `stdlib/`, by the census that read prose | 8 | 5 |
| `stdlib/`, by the census that reads bodies | **9** | **29** |
| `self_host/`, slice 4's 25 | 21 | 1 |

**THE ROW ABOVE IT WAS WRONG IN BOTH COLUMNS, AND THIS SECTION DREW THE
WRONG CONCLUSION FROM IT.** Audited 2026-08-30. The census those numbers
came from matched a doc-comment against six phrases; the one that
replaced it reads the declared return type and the body. Three things
follow.

*The five failures were four.* `sysRandomNum` is
`(pub fn (sysRandomNum) 33554932)` — the `getentropy` **syscall
number**, a constant with no bad path. It was counted because the
comment walk climbed a `; ---` banner into prose describing
`getentropy`'s `0 or -errno` contract twelve lines above. The sentence
below that named it "a platform shim below `Err`" was this document
inheriting a measurement error. The real entropy call,
`sysRandomBytes`, answers `(Result Int Error)` and was ported long ago.

*And four were twenty-nine.* Almost every `net*` and `sys*` call
forwards a raw syscall result and says so in wording the six phrases
did not match, so it went uncounted: `netListen`, `netAccept`,
`netBind`, `netConnect`, `sysWriteFd`, `sysReadFd`, `sysOpenPath`,
`sysCloseFd` and eighteen more. `stdlib/Sys.ax` alone is 26. **The old
metric rewarded silence** — writing the house sentence above any one of
them would have taken its module's count up and failed
`scripts/check-compat.sh` for a commit that changed no contract.

*So the `Result` migration is NOT complete, and this section's claim
that it was is withdrawn.* What remained was 29 public functions handing
a caller a negative errno; the socket-configuration slice took seven of
them on 2026-08-31, the "did it work" slice five more on 2026-09-01,
and one of the remainder turned out to be an absence the census had
misfiled — so **16** are left. None of them is free:
`netSocketTcp` has 17 call sites, **seven of which never test the result
at all**, which is the reason the migration exists rather than an
argument against it.

The hot-path exclusions still stand on their own measurement —
`IO.writeStr` and the `net` accepting and polling calls allocate an
`(Ok n)` per call, per connection or per wake, outside the per-request
arena scope. **What holds them is `#effects=` in `axiom symbols`, not
`scripts/check-net.sh`**, and §10's slice-3 note carries the
measurement: with a per-connection allocation deliberately restored to
the accept path, that gate stayed green at 182× against its floor of
50. Its ratio is sized to catch an arena that stopped reclaiming, not
one 32-byte block per connection. And "excluded" is a decision about a
handful of the twenty-nine, not a description of the whole.

The other half is unchanged in kind and one larger in count: **nine**
lookups in `stdlib/` that answer `-1` for "not found" and want
**`Option`**, which is built in and needs no import (§1). Two of the
nine are in `stdlib/Str.ax`, which **cannot** import `Err` — `Err`
imports `Str` — so they could never have been `Result` debt.

**And `Option` is not free.** Measured 2026-08-30 over 20,000,000 calls
at `--opt 2`: a `-1` return costs **1.4 ns** and a `(Some v)` costs
**10.4 ns**, 7.4×, for the allocate/store/match/release round trip. The
arena bump moves **zero bytes** for that loop — the block is recycled
through its size class — so a bytes-only measurement reports `Option` as
free and is wrong; the cost is instructions. `strFindByte` has 62 call
sites on the compiler's own scanning path. That is the measurement the
`Option` decision turns on, and it is why it stays a decision.

That is a decision to take deliberately, not a slice to grind. It is
recorded here rather than acted on because renumbering the slices is a
change to this section, and because the sentinel census
(`compat/SENTINELS`, gated by `scripts/check-compat.sh`) counts both
kinds — so the number will not reach zero by porting failures alone,
and a reader watching it fall should know why it stops.

**ERR-ADOPT-2 (P). Every slice keeps `stage2 == stage3`.** No slice
touches the seed until one has to, and the one that does — a built-in
`Result` under `ERR-TYPE-2`, if it is ever justified — lands as
feature-then-`scripts/reseed.sh`, never as both at once.

**ERR-ADOPT-3 (H, amended 2026-08-24, discharged 2026-08-25). The
long-lived programs were the constraint on `ERR-MEM-4`, and there are
two of them.** A compiler process runs once and exits; 32 bytes per
fallible call was noise there. The two programs below are why it was
not noise everywhere — and since `ERR-MEM-4` closed, the constraint
this rule existed to state is discharged. The rule is kept because the
two programs it identified are still the ones any future per-call cost
has to be measured against, and identifying them is the part that took
a correction.

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
allocated inside the bracket was reclaimed at the boundary and one that
escaped it was not. That is what `ERR-MEM-4` had to be measured
against, and it is why the 32 bytes were a per-*call* figure and not a
per-*process* one.

Migrating the compiler's phases to `Result` **MUST** still be
re-measured against `scripts/check-lsp-selfhost.sh`'s per-edit figure
**and** `scripts/check-net.sh`'s scoped-against-unscoped ratio. What is
no longer a precondition is `ERR-MEM-4` itself: it closed on
2026-08-25, before either program's own request path migrated, which is
the order this rule asked for.

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
; RESULT, not the error - ERR-TYPE-3a was why nothing here reached into
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
