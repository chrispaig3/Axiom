# The Axiom Memory Model

The normative specification of how an Axiom program represents,
allocates, mutates and reclaims memory, and of what a compiler author
may assume while doing it.

This document is the specification. The design sketch it expands and
the history that explains several of its decisions were both retired
into git on 2026-08-23, and are read with:

```bash
git show d7622c2:docs/v1-roadmap.md     # §4.1, the design sketch
git show d7622c2:docs/self-hosting.md   # the self-hosting record
```

Where either disagrees with this document, this document is wrong until
it is fixed: the roadmap was a plan and this is a contract. That
ordering is why they could be retired and this could not.

---

## 0. How to read this document

### 0.1 Rule identifiers

Every normative statement carries a stable identifier — `MM-VAL-4`,
`MM-ALLOC-9`. Identifiers follow the same discipline as diagnostic
codes: **never renamed, never reused**. A test, a commit message or a
compiler comment may cite one and mean the same thing a year later. A
rule that is withdrawn keeps its number and is marked withdrawn.

### 0.2 Conformance language

`MUST`, `MUST NOT`, `SHOULD` and `MAY` are used as in RFC 2119. They
bind two different audiences, and each rule says which:

- **Implementation obligations** bind the compiler and its emitted
  runtime. A conforming implementation that violates one is defective.
- **Program obligations** bind the Axiom programmer. Nothing checks
  these — they are the places where the language's safety stops, and
  each is named rather than left implicit.

### 0.3 Status markers

Axiom's documentation convention is that a claim is stated with the
observation that established it. A specification cannot follow that
convention unchanged, because a specification also describes what does
not exist yet. Every rule therefore carries one of:

| Marker | Meaning |
|---|---|
| **H** | **Holds today.** The implementation conforms, and the rule names the probe or source that shows it. |
| **P** | **Planned.** Normative for a conforming implementation; the current one does not conform. The rule states what happens *today* instead, so nobody mistakes the specification for a description. |
| **R** | **Refused.** The rule states something the language deliberately does not provide, and why. |
| **W** | **Withdrawn.** The rule was normative and is no longer to be implemented. It keeps its number and its text (§0.1), and the marker names what superseded it — a withdrawn rule that vanished would leave its citations dangling and its lesson unlearned. |

An **H** rule with no evidence is a bug in this document. A **P** rule
that does not say what happens today is the failure mode
[macro-system.md](macro-system.md) calls *documented-but-inert*: a reader builds on
a sentence and the compiler disagrees.

**Withdrawal has two kinds, and the difference is whether there is code
behind it.** Every **W** rule in §3.4 was superseded *before it was
implemented*, and withdrawing one cost a paragraph and nothing else.
`MM-LIFE-2a` is the first of the other kind — **abandoned in place**:
part of it emits today, other rules were built on the half that landed,
and no edit to this document takes it back out. A rule withdrawn that
way **MUST** say what the landed half still costs, in §9.0 beside the
defects, because that cost has stopped belonging to anybody's plan and
is therefore the cost nobody is watching.

### 0.4 Reproducing the measurements

Every probe in this document runs against the compiler in the working
tree:

```bash
axiom="$PWD/.axiom-bin/axiom"          # or your own build
"$axiom" --diagnostic-format=ai run probe.ax; echo $?
"$axiom" --diagnostic-format=ai emit-llvm probe.ax
```

A program's answer is observed as its **exit status**, which is the low
8 bits of `main`'s result (`MM-EXEC-11`). Probes below that print use
`IO.println` instead.

---

## 1. Execution semantics

### 1.1 The abstract machine

**MM-EXEC-1 (H).** An Axiom program is a set of top-level declarations
and one entry point, `main`. Evaluation is the reduction of `main`'s
body. There is no separate initialization phase: a top-level `fn` with
no parameters is a *function*, not a constant, and every reference to it
is a call (the self-hosting record).

**MM-EXEC-2 (H).** Evaluation is **strict** and **call-by-value**.
Every argument of an application is evaluated to a value before the
callee's body begins.

**MM-EXEC-3 (H).** Arguments are evaluated **left to right**, and a
`let`'s bindings are evaluated **in order**, each in scope for the ones
after it and for the body.

```scheme
(fn (two a b) (+ a b))
(two (side 1) (side 2))              ; prints 1 then 2
(let ((x (side 3)) (y (+ x 1))) ...) ; x is in scope for y
```

Measured: the probe prints `1 2 3` in that order.

**MM-EXEC-4 (H).** The **only** non-strict positions in the language
are:

| Form | Non-strict positions |
|---|---|
| `(if c t e)` | `t` and `e` — exactly one is evaluated |
| `(cond ...)` | every arm but the selected one |
| `(match s arms)` | every arm but the selected one |
| `(&& a b)`, `(\|\| a b)` | `b`, when `a` decides the answer |
| `(while c body)` | `body`, zero or more times |
| `(handle body effs h)` | `h`, when no operation dispatches to it |
| a macro argument | see `MAC-EXP-6`: a template that drops a parameter drops its argument unevaluated |

Everything else, including every operator not listed, evaluates all of
its operands. Measured: `(&& (== 0 1) (== (side 8) 8))` does not print.

**MM-EXEC-5 (H).** A brace block `{ e1 e2 ... en }` evaluates its
elements in order and has the value of `en`.

**MM-EXEC-6 (H).** Application is **curried in the type system and
uncurried in the emitted call**. A direct call to a known top-level
function of arity *n* passes *n* arguments in one machine call, using
LLVM's default C convention. A syntactically saturated curried spine
`((add 1) 2)` is **flattened** into that one direct call and never
builds an intermediate closure. A call *through a value* passes one
argument per call (`MM-VAL-18`).

**MM-EXEC-6a (H).** A constructor's heap block is allocated and its tag
stored **before** any field expression is evaluated; the fields are then
evaluated and stored left to right. A `match` evaluates its scrutinee
exactly once, before any arm is tried.

**MM-EXEC-6b (H).** **A self tail call runs in constant stack.** The
compiler performs this itself, at every optimisation level: the
function's parameters are promoted to `alloca` slots, the call becomes
stores into them, and control branches back to a loop header. No
`tail`/`musttail` marker is emitted for it — the loop is built by
Axiom's codegen, not delegated to LLVM. Measured: a self-recursive loop
of 5,000,000 iterations answers correctly. **Every tail position
counts**: the last expression of a `{ }` block, both arms of an `if`,
every arm of a `match` and of a `cond` (lowered to `if` first), and the
body of a `let` — the last since 2026-08-22, and measured again on
2026-09-03 at `--opt 0` with ten million iterations through each
(`tests/stdlib/467-mutual-tail.ax` term 6 for the `let` body;
`scripts/check-tail-calls.sh` runs it under a 512 KiB stack). What is
NOT a tail position: a `while` body, a `handle` body, and the operands
of `&&`/`||`.

The tail positions recognised are exactly: the expression itself, both
arms of an `if`, the last expression of a `{}` block, every `match` arm,
every `cond` clause, and — since 2026-08-22 — **the body of a `let`**
(and of a `mut` binding; not a `while` body or an `&&`/`||` operand). The
`let` body was excluded for two defects that following stage0's
omission avoided: a `mut` binding inside the loop re-ran its `alloca`
each iteration — every `alloca` a function emits now sits in its entry
block, so a `mut` binding inside any loop allocates once per activation
(measured: 5,000,000 iterations at `--opt 0`, where the body-block
`alloca` overflowed) — and a local shadowing the function's own name
was rewritten as a jump — the emitter resolves a call's head as a local
before it considers the rewrite, and a `let` binding the name itself is
never a tail. What made the inclusion necessary: `MM-LIFE-2c` event 3
releases a `let`'s owned temporary AFTER the call its body makes, and
that release is exactly what stopped LLVM's sibling-call pass from
rescuing `(let ((s (strConcat s "x"))) (grow s (- n 1)))` — 200,000
deep, it overflowed the stack where the leaking compiler had not.

> `docs/reference.md` attributed this to LLVM until 2026-08-14 — "at
> `--opt 0` each recursive iteration costs a stack frame; `--opt 1` …
> turn[s] self-tail-recursion into a real loop" — and now records the
> correction. Measured, the loop is in the emitted IR at `--opt 0` too.
> (`axiom run` ignores `--opt` entirely and always builds at 1, which
> is a separate defect, and still current.)

**MM-EXEC-6c (H).** **A mutual tail call runs in constant stack when
the prototypes match and nothing is owed after it.** Since 2026-09-03
the emitter marks such a call `musttail` — LLVM's *guaranteed* tail
call, which `llc` lowers to a jump at every optimisation level or
refuses the module — when every one of these holds (`mustTailOK` in
`self_host/codegen.ax` is the list): the call sits in tail position
with no leaf retain owed; the callee is a defined function applied to
exactly its arity; the caller is a plain `fn` (not a lambda or thunk,
whose prototypes carry the closure record) and not a self-tail-call
loop (whose retained parameter slots are released after the body); no
`let` temporary is pending release at the scope end; the two prototypes
are identical — every parameter is `i64`, so identical means the same
count, the hidden evidence word included, and both answer `i64`; and no
argument is an owned temporary the caller would release after the call.
Measured: `tests/stdlib/467-mutual-tail.ax` runs ten million
alternating calls through `ev`/`od`, through a `let` body and a `match`
arm, and around a three-way cycle at `--opt 0` under a 512 KiB stack,
and `scripts/check-tail-calls.sh` deletes the marker from the same IR
and requires the program to die by signal. On the compiler's own IR
(`emit-llvm self_host/main.ax`, 2026-09-03), 386 of the 1,059 calls
sitting immediately before a `ret` are marked.

**Two shapes stay a plain `call`, and a program MUST NOT rely on either
for unbounded recursion.** (1) **A callee of a different arity.** Under
the C calling convention LLVM requires a `musttail` caller and callee
to have identical prototypes; 603 of the compiler's own tail calls are
of this shape. The `tailcc` convention lifts the requirement — measured
2026-09-03: `llc -O0` accepts `musttail` between `tailcc` functions of
two and three parameters and emits a jump (`b`/`jmp`) on all seven
triples, and the darwin binary runs ten million such calls under 512
KiB — but adopting it means every function in the module changes
convention, the runtime's callback trampoline and every `extern`
boundary with it, so it is recorded here as the measured next step
rather than built. (2) **A call that hands over an owned temporary**
(`(od (+ i 1) (strConcat s "x"))`): the caller releases the temporary
after the callee returns (event 3), and releasing it before the call
would free a block the callee is about to read; moving the release
into the callee would change the convention for every function.
These two run in constant space only at `--opt >= 1` and only while
the release after them is dead, which is LLVM's sibling-call pass
happening to succeed, not a guarantee.

**MM-EXEC-6d (H).** Non-tail recursion is bounded by the machine stack.
Measured on an 8176 KiB stack: **174,000–175,000** frames at `--opt 0`
and **260,000–262,000** at `--opt 1`, beyond which the process dies with
SIGSEGV (status 139).

> `stdlib/Mem.ax` writes its byte loops as `while`, and until
> 2026-08-14 its comment gave the reason as "stage1 emits no tail-call
> optimisation at all" — stale, since `MM-EXEC-6b` is measured on
> today's binary and those loops are self tail calls. The comment now
> quotes its old reason as history and keeps the spelling for the rule
> that outlives it: the `while` needs no optimisation to be flat, and
> `MM-EXEC-6c` means a mutual respelling would still be unsafe (a
> let-bound one is a jump since 2026-08-22).

**MM-EXEC-7 (R).** A top-level function **MUST NOT** be partially
applied. It has no closure record to hold the missing arguments, and
the refusal is `AX3013`, which names the lambda that expresses the same
value:

```
E AX3013 partial-application "partial application of `+`: it takes 2 argument(s) and 0 were supplied"
  ?"bind the missing arguments with a lambda: `(lambda (y) (f x y))` builds the value `(f x)` would mean"
```

### 1.2 Purity

**MM-EXEC-8 (H).** Axiom is **not a pure language**, and this
specification does not pretend otherwise. Three constructs perform
observable effects:

1. `__syscall0`–`__syscall6`, and everything in `stdlib/Sys` built on
   them, reach the operating system.
2. `(set x v)` on a `mut` local mutates a function-local cell
   (`MM-MUT-1`).
3. `(set e.f v)` mutates a heap field, visibly through every alias of
   `e` (`MM-MUT-2`).

**MM-EXEC-9 (H).** Effects are **inferred transitively** — a fixpoint
over every function body, so a syscall three calls down counts — and
reported by `axiom symbols` as `#effects=...`. Since 2026-08-30 it is a
**worklist**: round 1 is a forward pass and a reverse pass, which is
also what records every call edge, and rounds 2+ re-examine only the
callers of a function whose row grew. The order it exists for is the
one a GENERATOR emits — a helper beside each of its callers, `f2 f1 f4
f3 …` — which defeats both passes at once and cost 56 s on an
8,000-function chain against 0.09 s for the same call graph declared in
order; it is 0.10 s now. `scripts/check-effect-fixpoint.sh` holds it as
a RATIO between those two orders, and holds `symbols --calls`
byte-identical across an ablation of the frontier, because a wrong
worklist is a missing effect on one row rather than a crash.

Effects do **not** appear in function types. `;@axiom:effect(...)` and
`;@axiom:pure` are *claims*, validated against the inference; a refuted claim is
`AX3010`, an **error**. They are not opt-in: an untagged function
claims to perform no `IO`, and a body that performs it anyway is
`AX3042`. `Alloc` and `Mut` stay ambient and are never required.

**MM-EXEC-9a (H).** **The inferred effect set is an
under-approximation, and a specification must say so.** A conforming
implementation **SHOULD** make it an over-approximation. It was not, in
**seven** measured ways — six this table listed and one it did not.
**Six are closed.** One remains:

| A function that... | is inferred | why it is still open |
|---|---|---|
| calls through a local, a parameter, or an unresolved name | contributes nothing but a transparency mark | needs the flow analysis `MM-EXEC-9b` describes and the language does not have. **It announces itself**: the row carries `#effects-incomplete` and a `pure` claim over it draws `AX3037`, so a reader is handed a lower bound labelled as one rather than a set that looks complete |

**The row is narrower than it was, and the part that closed on
2026-08-31 is the part a TYPE could answer.** Setting the mark is
right; setting it for every argument the walk could not follow was
not. A call through an effect-transparent parameter asked only about
the ARGUMENT's shape — a load, a call result and an `if` are all
"unfollowable" — and never about the position it landed in. So
`vecSiftDownBy`, whose whole body is `(cmp (memGetWord d r)
(memGetWord d k))` against a `cmp` declared `(-> Int Int Int)`,
published the standard library's sort as a lower bound:

    F vecSiftDownBy ... #effects=Mut #effects-incomplete #effect-params=cmp
    F vecSortBy     ... #effects=Mut #effects-incomplete #effect-params=cmp

Two machine words the signature itself calls integers were enough, and
`restrict(no-io)` over any function that sorted came back `AX3051`,
unanswerable. The rule now asked is `paramCallablesOf`'s own, one
level down — *an arrow, a type variable or poison can hold a callable
value; a concrete `Int` cannot* — which is the argument `markEparam`
already rested on for the parameter itself, applied to that
parameter's own argument positions. A value in an `Int` position can
hide no effect: applying it is `AX3004` and the program does not
compile.

**Measured with `symbols` file by file across every source under
`stdlib/`, `self_host/`, `tests/`, `examples/` and `compat/` — 578 of
them — 34 declarations carried the mark and 30 do.** The four that closed are
`vecSiftDownBy`, `vecSortBy` and the two fixtures that reach them. The
thirty that remain carry the first two shapes below, and the third is
what closed — a separation the table could not previously state,
because until now one mark stood for all three:

| what the walk met | closable? |
|---|---|
| a head that is not a name; an opaque `let`; a pattern binder; over-application; a lambda's own parameter | **no** — this is `MM-EXEC-9b`'s flow analysis, and dispatch through a capability record (`stdlib/Http.ax`'s `httpCall`, `((h.run) fd r)`) is the shape that matters |
| an unfollowable value in a position whose declared type is a TYPE VARIABLE | **no, and correctly**: a caller may instantiate it to an arrow. `tests/selfhost/999-placeholder-under-arrow.ax`'s `twice` is `(-> (-> a a) a a)` with the same body as `tests/stdlib/140-function-values.ax`'s `(-> (-> Int Int) Int Int)` version, and only the second one closed |
| an unfollowable value in a position whose declared type cannot hold a function | **closed 2026-08-31** — 4 declarations, and no well-typed program can put a function there: applying a nominal type is `AX3004`, and so is handing an arrow to one (probed on both alias forms, `(type F = ...)` expanded and `(type F a = ...)` nominal) |

Held by `scripts/check-effect-argpos.sh`, whose four controls are the
shapes that must KEEP the mark; the ablation drops the type test and
requires the closed rows to reopen. No `#effects=` set moved anywhere
in the tree and no diagnostic did: 883 diagnostic lines over every
`.ax` before and after, byte-identical.

**The constructor row closed on 2026-08-31, and it closed because it
was not survivable.** It stood here as a DECISION — applying a `data`
or `struct` constructor contributed nothing to the row, though the
constructor allocates — and `error-model.md` `ERR-PROP-2` relied on the
convenient half of it. What that decision cost was invisible until
`restrict(no-alloc)` existed to read the row. `no-alloc` is not a
description, it is a CLAIM the compiler answers, and against a row
built to omit allocation it answered `OK` to this:

```scheme
(data W (Wrap Int) (Empty))
;@axiom:restrict(no-alloc)
(:: mk (-> Int Int))
(fn (mk n) (match (Wrap n) ((Wrap x) x) ((Empty) 0)))
```

while `emit-llvm` on the same file put a `call i64 @axiom_alloc(i64 16)`
inside `@mk` itself. A decision that makes a checked claim
unfalsifiable is not a decision about precision; it is the check not
existing. `no-alloc` shipped in 0.6.0 across 273 declarations on the
strength of a row that could not hold the effect it names.

So the row is precise now. `typecheck.ax`'s `ctorAllocArity` asks the
same tables `checkSaturation` asks — `rfindCtor` for a `data`
constructor, `findStruct` for a struct — and `walkCallHead` adds `Alloc`
when the answer is above zero. **ARITY decides, not constructor-ness,
and it was measured rather than assumed**: `(Wrap n)` emits one
`axiom_alloc` and `(Empty)` emits none, because a nullary constructor
is an immediate tag with no block behind it — which is
[reference.md](reference.md)'s own row, *"every constructor is nullary
| a value **is** its tag ... nothing allocates"*. Adding `Alloc` for
`(Empty)` would refuse a `no-alloc` claim the emitted code keeps, which
is the opposite error and no better.

**The measured cost of closing it**, over `self_host/` and `stdlib/` on
2026-08-31: **123 of 3,725 effect rows** move, every one of them by
GAINING `Alloc` and none by losing anything, and 111 of the 123 carried
no `#effects=` at all before. **Seven** `restrict(no-alloc)` claims in
the tree were false and are withdrawn at their sites, each with the
reason written beside it — `mkSpan` and `mkToken`
(`self_host/core.ax`), `mkDiagBase` (`self_host/diag.ax`), `vecTry`
(`stdlib/Vec.ax`), `strFind` and `strParseInt` (`stdlib/Str.ax`), and
`histFindBack` (`self_host/replhist.ax`), the last of them
transitively, through `strFind`'s `Some`. **Zero** `;@axiom:pure`
claims in the tree break: none of them is on a constructing function,
so the only thing that pays for this is `ERR-PROP-2`'s documented
probe, not any code in this repository.

The row was found while closing the others and had been **added** to
this table rather than left where it was. `error-model.md` had named it
since it was written, "an under-approximation here in the sense
`MM-EXEC-9a` already names" — and `MM-EXEC-9a` did not name it. A table
whose whole job is to enumerate was short by one for as long as the
sentence pointing at it existed.

**The five that closed, and what each was.** All but one were the same
defect: a primitive that PERFORMS something, registered like `__load64`,
which computes. `scripts/check-agent-policy.sh` asserts the mapping one
primitive at a time, with `__load64`, `__load8` and `__retain` as the
controls that must stay silent — a population golden cannot hold this
rule, because re-blessing it after a regression makes the gate agree
with whatever the compiler now says.

| Row | Closed | Now |
|---|---|---|
| calls `__alloc` | 2026-08-23 | `Alloc` |
| calls a **trait method** whose implementation does I/O — the construct was removed in 0.6.0 | 2026-08-23 | the fixpoint unioned **every** implementation of the method, because the rewrite that selects one ran elsewhere and this walk could not say which; the effect reached the caller and its callers — definite with a single implementation, and `#effects-possible=` with more than one |
| calls `__store8`/`__store64` — writes arbitrary memory | 2026-08-25 | `Mut` |
| reads `__argc`/`__argv` — the process command line | 2026-08-25 | `IO` |
| calls the arena primitives | 2026-08-25 | `Alloc` |
| applies a `data`/`struct` **constructor** of arity >= 1 | 2026-08-31 | `Alloc`. A nullary constructor stays silent, and allocates nothing to be silent about |

The trait-method row closed and then stopped existing. `trait`/`impl`
are `AX2004` since 0.6.0 and an interface is a capability record — a
struct holding the functions, passed as an ordinary value — so dispatch is
`((c.render) x)`, a call through a field the walk cannot resolve. That
is the FIRST row of the OPEN table above, not this closed one.
Measured: over `(struct Logger (emit : (-> String Int)))`,
`;@axiom:pure (fn (runIt l s) ((l.emit) s))` checks `OK` with `AX3037`
beside it and its row reads `#pure #effects-incomplete` with no `IO`.
The union this row bought was bought for a construct the language no
longer has, and nothing closes in its place.

The `__alloc` row was the inverted one: `Alloc` fired for the
`(alloc T)` keyword, a form that allocates nothing and that `MM-LIFE-7`
records as definable-but-uncallable, and never for the primitive the
whole heap goes through — so the effect existed, was spellable, was
checkable, and was attached to the wrong thing.

The 2026-08-25 three are chosen against the definitions already in
[reference.md](reference.md), not invented for them. A `__store64` is
what `(set base.field v)` lowers to, and `Mut`'s whole definition is
that a field store is visible through every alias while a `mut` local
is not. `__argc` **broadens** `IO` from "reaches a `__syscallN`" to
"reaches the outside world", which is the honest reading and the one
`MM-EXEC-9b` needs; that table is corrected rather than left to
disagree. `Alloc` is the heap-**machinery** effect and not strictly an
allocation — `handle` already contributed it for installing evidence,
which allocates nothing — and an arena reset ends every block since a
mark, so a function performing one is exactly as far from pure as one
performing the allocation. `__axiom_arena_mark` only reads the bump
pointer and is over-approximated **on purpose**: this rule's own SHOULD
asks for that, and a mark is only ever written to be paired with a
reset.

`__retain`/`__release` deliberately get nothing. Their writes are the
runtime's own bookkeeping, invisible to the program's meaning, and
giving them `Mut` marks every function that touches a reference and
deletes the discrimination the rest of this buys.

**Measured, and it discriminates rather than blankets.** Counted the way
`scripts/check-agent-policy.sh` counts — one probe importing every
module, 578 declarations listed — **216** carried an effect before the
2026-08-25 three and **261** after; of the 431 arrow-typed ones, **187
are still effect-free**, down from 230. The reach is what a reader would
expect: `memAlloc`, `vecPush` and `strConcat` carry `Alloc`, the last
two carry `Mut` as well because they store, and `vecGet` and `strEq`
carry neither. **Two** `handle` lists moved, and where the
second one lives is the measurement lesson. `AX3011` requires such a
list to be exhaustive, and `println` reaches `__store64`:
`tests/stdlib/320-effect-gc-roots.ax` is a checked-in fixture and a
differential over `tests/**/*.ax` found it; the other is a program
`scripts/check-recover.sh` builds from a heredoc, which that sweep
cannot see at all. **A gate that generates a program is a second
corpus**, and an inference change has to be measured against both.
Neither is a cost — both are the check working. `scripts/check-agent-policy.sh` pins the
whole population against `tests/agent/stdlib-effects.allow`.

Measured on the compiler before the correction, `axiom symbols`
reported no `#effects=` at all for either of these; both report one now:

```scheme
(fn (writes a)    (__store64 a 0 42)) ; writes arbitrary memory -> Mut
(fn (readsArgs n) (__argc))           ; reads the command line  -> IO
```

**MM-EXEC-9b (H).** What a purity claim therefore guarantees, precisely:
**`;@axiom:pure` that the checker accepted means the function's body
reaches no effectful primitive by a path the inference can follow.** It
does **not** mean the function is a mathematical function of its
arguments — it may still mutate a heap field through an alias
(`MM-MUT-2`), and it may still perform anything at all through a call
the inference could not resolve, which is one of `MM-EXEC-9a`'s two
remaining rows. `AX3010` refuses the build as of 2026-08-25 — but only
where a claim was written and refuted; the unresolved call yields
`AX3037`, which still does not.

Two of the escapes this rule listed are gone. Writing memory and
reading the command line are inferred now, so a `pure` claim over
either is reported rather than accepted. The third was closed for
traits and REOPENED when they were removed: an interface is a
capability record since 0.6.0, so dispatch is `((l.emit) s)` — a call
through a struct field, which is `MM-EXEC-9a`'s first remaining row and
not a resolvable call edge. Measured: `;@axiom:pure (fn (runIt l s)
((l.emit) s))` over `(struct Logger (emit : (-> String Int)))` checks
`OK` with `AX3037` beside it, carries `#pure #effects-incomplete` and no
`IO`, and prints at run time. The unresolved-call route is therefore
the reason this rule still says what it says, and it now covers every
dispatch in the language — but that route is at least *announced*, by
`#effects-incomplete` on the row and `AX3037` on the claim. The other
survivor, constructor allocation, is silent and deliberate; see
`MM-EXEC-9a`'s table for the rule that depends on it.

A program that needs a real purity guarantee cannot get one from this
mechanism today. Stating that is more useful than the alternative,
which is a reader trusting a tag that `MM-EXEC-9a`'s two remaining
rows walk straight through.

**MM-EXEC-10 (H).** Handlers for a declared effect are installed by
`handle` and dispatch through a per-effect evidence slot:

- installation is dynamically scoped over the body's extent, at any
  call depth;
- handlers are **tail-resumptive**: the handler's return value *is* the
  operation's result and execution continues at the operation's site.
  No continuation is captured (`MM-VAL-12`);
- a handler runs under the evidence in scope at its **installation**, so
  an operation it performs itself dispatches outward, never back into
  itself;
- an operation performed with no handler in extent exits the process
  with status **71** — and since 2026-08-30 the compiler says so first,
  where it can see it: `AX3053` reports a custom effect still in `main`'s
  row after inference, which is an effect no `handle` discharged. A
  WARNING, because the two closure shapes make the evidence one-sided in
  both directions (`tests/diagnostics/severity.policy`), and silenced by
  `;@axiom:unhandled(trap)` on the `effect` declaration for an effect
  whose unhandled operation is a deliberate abort, as `stdlib/Test.ax`'s
  `Assert` is;
- a handler **cannot abort** the computation it handles. There is no
  non-local exit from a handler; the only way out is process exit;
- installation is **dynamic extent, not lexical capture**: a closure
  built inside a `handle` and invoked after that `handle` has returned
  performs its operation with the slot restored, and traps.

Measured end to end:

```scheme
(import IO)

(effect Console (log :: (-> String Int)))
;@axiom:effect(console)
(fn (greet n) { (log "from deep") n })
;@axiom:effect(io)
; `s` is the `String` that `log` declares: the handler is checked against
; the operation's arrow, so `println` renders it with no cast
(fn (main) (handle (greet 7) (Console IO) (lambda (s) { (println s) 0 })))
```
prints `from deep`, exits 7; with the `handle` removed, exits 71.

> `docs/reference.md` stated, until 2026-08-14, that "Stage1 does not
> parse `effect`/`handle` yet" — stale long before it was corrected:
> the self-hosted compiler parses, checks and emits both, including
> the evidence globals (`codegen.ax:3468–3700`). The probe above is
> the refutation, and reference.md now records the correction.

### 1.3 Determinism

**MM-EXEC-11 (H).** A program's observable behaviour **MUST** be a
function of its inputs alone — where "inputs" are the process's
arguments, its environment, and the bytes it reads — **provided it
observes no address**. The implementation adds no hash seed, no
scheduler, no finalizer, and no iteration order: `Map` exposes no
iteration API at all (only the deliberately order-independent
`mapSumKeys`/`mapSumVals`), slot placement is a pure function of key and
capacity, and `Intern` hands out dense ids in insertion order.

**MM-EXEC-12 (H).** The proviso is not decorative. **Heap and literal
addresses are ordinary `Int` values and they differ between runs of the
same binary, because the loader randomises the address space.** The ways
to observe one are enumerable rather than pervasive, and each is a
**program obligation**:

| Escape hatch | What leaks |
|---|---|
| `(__alloc n)`, `memAlloc` | the address itself |
| `(__addr "lit")`, `strData` | a literal's or a string's data address |
| `(cast Int v)` on any heap value | that value's address |
| `Vec`/`Map`/`Str` handles | addresses, since a handle *is* an address |
| `sysGetPid`, `sysNowMicros` | process and wall-clock state |
| `sysEnv`, `sysArg` | the environment |

**MM-EXEC-12a (H).** **`==` and `!=` on two `String`s compare CONTENT.**
The comparison is over bytes, which is what makes it correct for
Unicode: UTF-8 byte equality is code-point-sequence equality. The length
word bounds it, so an interior NUL is an ordinary byte and a `strSlice`
result — which is not NUL-terminated — compares correctly.

This is a **change**. `==` previously lowered to `icmp eq` on the two
handles and therefore compared *addresses*: `(== "hi" (strDup "hi"))`
was false while `(strEq ...)` was true, and identical literals within a
module intern to one header, so `(== "hi" "hi")` was true — the pattern
that let the bug survive every obvious test. Its corpus population was
zero: all 551 string comparisons in this repository are spelled
`strEq`.

Two consequences a reader **MUST** know:

- **It fires on what the checker concluded**, both sides exactly
  `String` (`tyIsStringTy`, not `tyCompat` — see `MM-ALLOC-20`, since
  under the fiat asking for compatibility would answer yes for every
  `Int`). One side a string and the other an `Int` keeps the integer
  comparison rather than dereferencing a number. This is the same
  static dispatch the language already performs for `fadd` against
  `add`.
- **Identity is now a different question from equality.** A program
  asking whether two handles are the *same object* **MUST** say
  `(== (cast Int a) (cast Int b))`. Exactly one place in this
  repository asked it — `tests/stdlib/090-intern.ax`, proving an
  interner's inputs were distinct handles — and it now says so.

Ordering (`<`, `>`, …) on strings is untouched and still compares
addresses; making it mean `strCmp` is a larger decision than fixing
equality, and an address ordering is at least not a wrong answer to a
question anyone asks.

Pinned by `tests/stdlib/035-string-equality.ax`, whose thirteen cases
include the Unicode pair, the interior-NUL/slice case, and the integer
comparisons that must NOT change; the pre-change compiler answers six of
them differently.

A program that prints `(__alloc 8)` prints a different number under a
different allocation history. This is a **program obligation**: a
program that requires deterministic output **MUST NOT** make an address
part of it. Every gate in this repository that compares bytes depends on
the compiler itself honouring this, which is why `Intern` keys on
content and `Map` iteration is never exposed in output order.

**MM-EXEC-13 (H).** Compilation is deterministic: the same source
produces byte-identical LLVM IR, and `scripts/check-reproducible.sh`
gates it. Every counter the compiler exposes in a name — the macro
expander's gensym (`MAC-HYG-3`), the register allocator's, the type
variable numbering — is a per-run monotonic integer, never an address or
a hash of one.

**MM-EXEC-14 (R).** The compiler **MUST NOT** evaluate user code during
compilation. This is a threat-model invariant, not a performance
decision, and it is shared with the macro system, which is built around
it ([macro-system.md §1.4](macro-system.md)). It is observable: the
compiler does not even constant-fold.

```
(fn (main) (+ 1 (* 2 3)))
    %.t0 = mul i64 2, 3
    %.t1 = add i64 1, %.t0
```

Folding happens later, in `opt`, on IR — never on the source, and never
by running a function the source defined.

### 1.4 Process lifecycle

**MM-EXEC-15 (H).** The emitted `@main(i64 %argc, i64 %argv)` stores its
two parameters into `@__axiom_argc`/`@__axiom_argv` and calls the user's
`main`, which is emitted under the name `@__axiom_user_main` and takes
no arguments. The process's exit status is the low 8 bits of `main`'s
result. Measured: a `main` answering 5,000,001 exits 65.

**MM-EXEC-15a (H).** The rename covers references as well as the
definition, since 2026-08-14: a call to `main` — recursive, or from
another entry-file function — reaches `@__axiom_user_main`, and
`tests/selfhost/371-main-recursive.ax` runs to 5 where the unfixed
compiler exits 4. Until then it emitted the undefined register
`%main`:

```scheme
(:: main Int)
(fn (main) (if (< 1 0) (main) 5))
```
```
$ axiom check mainrec.ax        # before the fix
OK
$ axiom run mainrec.ax
opt: ...ll:252:19: error: use of undefined value '%main'
  %t6 = phi i64 [ %main, %label_3 ], [ 5, %label_4 ]
```

`check` and `build` disagreed while the emitter's own comment claimed
the opposite ("a reference to `main` … must reach the renamed user
function") — `mangledFor` did map the name, and then every table
lookup (`isNullaryFn`, `isDefinedFn`, `fnArityOf`, `findFSig`) asked
for the *emitted* symbol in tables that hold the *declared* spelling,
missed, and fell through to the parameter arm. The lookups now
normalise through `declSpellingOf`. Only an entry file's `main` is
renamed at all; an imported module's `main` is module-mangled and
coexists with the wrapper.

**MM-EXEC-16 (H).** These exit statuses are **reserved** by the emitted
runtime and **MUST NOT** be reused by a program as a normal result:

| Status | Raised by | Evidence |
|---|---|---|
| 70 | allocator out of memory (`mmap` failed) | measured: `tests/stdlib/314-out-of-memory.ax` asks for 2^47 bytes, the run prints `axiom: out of memory (mmap failed)` to fd 2 and exits 70 |
| 71 | operation performed with no handler in extent | measured (`MM-EXEC-10`) |
| 72 | division by zero | measured: `(fn (main) (/ 10 0))` — `check` says `OK`, the run prints `axiom: division by zero` to fd 2 and exits 72 |
| 74 | a `__syscallN` reached on a target with no syscall ABI (windows-x86_64) | emitted, not yet executed: `emitPrimSyscall` lowers the primitive there to `__axiom_no_syscall`, which prints `axiom: no syscall ABI on this target` (37 bytes) and exits 74; 73 is the FFI's (`ffiHandleClose`) |
| 75 | `__axiom_arena_reset` handed a mark whose chunk is no longer on the active list (`MM-ALLOC-16a`) | measured: `tests/stdlib/166-arena-bad-mark.ax` resets an inner mark after its outer one, the run prints `axiom: arena reset to an invalid mark` to fd 2 and exits 75. The same fixture's first two blocks — nested marks reset innermost-first, and the same mark reset twice — must still exit silently, so the trap is pinned against firing on legal use |
| 77 | an index out of range, raised by `(__indexTrap)` — a call that never returns, so it inhabits every result type. It exists because traps are `internal` LLVM functions the runtime block emits and nothing in `stdlib/` could reach one: a container that refuses an out-of-range index rather than answering a value needs exactly that (`docs/generics-design.md` §4). Measured: `tests/stdlib/464-index-trap.ax` prints `axiom: vector index out of range` to fd 2 and exits 77, and the same trap stands in an `Int` result and a `String` result in one program, which a concrete-typed trap could not | measured |
| 78 | `parallel`: the kernel refused the fork or the pthread (`__axiom_par_spawn_failed`) | emitted 2026-09-03 and not yet executed - a refused spawn needs a process at its limits; the trap is recoverable, as 77 is, and prints `axiom: parallel: could not spawn the binding` |
| 79 | `parallel` on a target with neither `fork` nor a pthread - windows-x86_64 | emitted, not executed: both primitives compile there to `__axiom_par_unsupported`, which prints `axiom: parallel is not available on this target` and exits 79, so the program builds for every target and says at its first spawn what it cannot do (`scripts/check-parallel.sh` reads the IR) |
| 76 | `__axiom_arena_reset` handed a mark taken before a `handle` whose extent is still live (`MM-ALLOC-16b`) | measured: `tests/stdlib/167-arena-live-handle.ax` resets a mark that predates the extent, the run prints `axiom: arena reset past a live handle` to fd 2 and exits 76. Its first two blocks — a mark taken inside the extent, and a mark with no handle in scope — must still exit silently, and `tests/stdlib/401-recover-effect.ax` must still exit 71, because a recovery abort performs this very reset legitimately |
`tests/stdlib/310-effect-unhandled.err` pins its sentence beside the
`.exit` that had pinned the status alone since the case was written.

That `.err` is the whole reason the silence lasted: `run-stdlib-tests.sh`
compares stderr only when a `NAME.err` exists and discards it
otherwise, so a fixture with `.exit` 71 and no `.err` was green over a
program that printed nothing at all.

I/O is unbuffered — `println` is a direct `write` loop with no flush —
so output produced before one of these aborts is still visible.

**MM-EXEC-17 (H).** There are **no finalizers, no destructors and no
atexit hooks.** A process's memory is reclaimed by the operating system
at exit and by nothing else before it (`MM-LIFE-1`).

---

## 2. Value representation

### 2.1 The uniform word

**MM-VAL-1 (H).** **Every Axiom value is exactly one 64-bit machine
word.** Every function takes and returns `i64`. There is no other width,
no aggregate passed by value, and no unboxed pair.

**MM-VAL-1a (H).** Because of `MM-VAL-1`, generic instantiation is
**uniform representation, not monomorphisation**: a polymorphic function
is emitted exactly once and every call site calls the same symbol,
whatever the type argument. `sizeof` and `alignof` answer the constant 8
for every type without exception. Nothing in this model produces
per-instantiation code, so nothing in it can produce code-size growth
from polymorphism.

**MM-VAL-2 (H).** A word carries **no tag**. Nothing at runtime can
determine, from a word alone, whether it holds an integer, a float, a
boolean, a character, a constructor tag, or a heap address. This is the
single most consequential fact in this document: it is why there is no
tracing collector (`MM-LIFE-2`), why escape analysis cannot be added
without a type-level change (`MM-ALLOC-15`), and why the compiler must
track float-ness statically (`MM-VAL-4`).

**MM-VAL-3 (H).** Integers are 64-bit two's complement. `+`, `-` and `*`
**wrap** — no `nsw`/`nuw`, no check. Division and remainder are signed
and truncate toward zero (`(/ -7 2)` = −3, `(% -7 2)` = −1).
Comparisons are signed, `>>` is arithmetic, `<<` is a plain shift.

The wrap is the operators' definition and does not change. Where a
program cannot afford it there is now a remedy in the library rather
than only a warning here: `stdlib/Err.ax`'s `addChecked`, `subChecked`
and `mulChecked` answer `(Result Int Error)` and report `errOverflow`
instead (`MM-VAL-3b`).

**MM-VAL-3a (H).** Division or remainder **by zero is a guarded trap**,
not undefined: the compiler emits a zero test even for a literal zero
divisor, and the trap writes `axiom: division by zero` to fd 2 and exits
72.

**MM-VAL-3b (H, undefined behaviour).** Three integer cases are
genuinely undefined, and a specification **MUST** name them rather than
let a reader infer safety from `MM-VAL-3a`. Each is observable as an
answer that changes with `--opt`:

| Expression | `--opt 0` | `--opt 1` |
|---|---|---|
| `INT_MIN / -1` | −9223372036854775808 | 1 |
| `(>> 1024 64)` | 1024 | 1 |
| `(<< 1 100)` | 68719476736 | 1 |

Shift amounts of 64 or more, and negative shift amounts, are undefined;
no masking is emitted. A conforming implementation **SHOULD** guard the
first and define the rest.

**The remedy exists in the library, and the link is deliberately
two-way.** This rule pointed at no way out for as long as there was
none; `stdlib/Err.ax` now ships `addChecked`, `subChecked` and
`mulChecked` for the wrapping operators of `MM-VAL-3`, beside
`divChecked` and `shlChecked` for the cases in the table above.
`mulChecked` excludes `intMin * -1` **before** the division that would
otherwise ask for this rule's first row, in both operand orders, so the
implementation never performs the undefined operation — removing that
guard was tried and the fixture still passed, because the undefined
division happens to answer something usable at every level this compiler
emits, and a checked operator whose correctness rests on what undefined
behaviour happens to do is not a checked operator.
`tests/stdlib/312-checked-arithmetic.ax` cites `MM-VAL-3b` by name and
pins byte-identical stdout at `--opt` 0, 1, 2 and 3 — which is exactly
the property the table above says the raw operators cannot claim. A
reader who arrives here at the undefined behaviour should find the
remedy, and the fixture that arrives at the remedy already names this
rule; a one-way citation is how the two drift apart.

**MM-VAL-3c (H).** The sized integer types — `I8`…`I128`, `U8`…`U128`,
`Isize`, `Usize` — are **refused** (`AX3002`), the "remove them" arm of
the choice this rule used to demand, taken 2026-08-14. Until then they
were recognised names with **no representational effect**: all lowered
to a full-width `i64` with no truncation, no sign or zero extension,
and no width-specific arithmetic, while being incompatible with `Int`
so that no operator accepted one — inhabited only by bare literals and
`cast`. There are still **no unsigned operations at all**, and `Int`
is the one integer type. Their corpus population was zero. Pinned by
`tests/diagnostics/495-widthless-types.ax`. (`I64` survives as a
**leaked internal**: the checker constructs it as the `set` form's
type, and diagnostics may print it, but a program can no longer spell
it.)

**MM-VAL-4 (H).** A `Float` is an IEEE-754 binary64 **bit-cast into the
same word**. The compiler decides statically, from declared types, which
words to reinterpret as `double`:

```
define i64 @addf(i64 %a, i64 %b) #0 {
  %.d0 = bitcast i64 %a to double
  %.d1 = bitcast i64 %b to double
  %.d2 = fadd double %.d0, %.d1
  %.t3 = bitcast double %.d2 to i64
  ret i64 %.t3
}
```

Consequence, and a **program obligation**: because float-ness is
static and unrecoverable at runtime, a `Float` that reaches a position
the compiler believes is an `Int` is reinterpreted, not converted.

**MM-VAL-4a (H).** `cast` performs **no conversion**. It reinterprets
the same 64-bit word, and its only code-generation effect is to set the
compiler's float flag when the target type is spelled `Float`. The real
numeric conversions are `__intToFloat` and `__floatToInt`, which lower
to `sitofp` and `fptosi`.

**MM-VAL-4b (H).** Float arithmetic is selected by the type name
`Float` **and no other**, and since 2026-08-14 the other spellings are
**refused** (`AX3002`) rather than accepted-and-lied-about: `Double`,
`F32` and `F64` used to check as float types (`tyIsFloatTy` listed
them) while the emitter keyed float arithmetic on `Float` alone, so
their arithmetic was **integer** `add` on double bit patterns —
silently wrong numerics, with no diagnostic — and `F32`/`F64` rejected
float literals besides, so nothing could even construct one. The
refusal is the choice this rule demanded; `tyIsFloatTy` now matches
the emitter's one-name rule by construction. Pinned by
`tests/diagnostics/495-widthless-types.ax`.

**MM-VAL-4c (H).** Float comparisons use LLVM's **ordered** predicates,
so every comparison involving NaN is false — **including `!=`**, which
is `fcmp one`. `(!= NaN NaN)` is `false`, where IEEE-754 says true.
Division by zero is unguarded and yields ±inf or NaN, and the program
continues. `Fmt.fmtFloat` cannot render either: `+inf` prints as
`-9223372036854775808.9223372036853775807` and NaN as `0.000000`.

**MM-VAL-5 (H).** `Bool` is 0 or 1. `Char` is a Unicode code point as
an integer. Both are ordinary words.

### 2.2 Heap blocks

**MM-VAL-6 (H).** A heap block is an array of machine words at a
16-byte-aligned address. **A heap block is not self-describing**: it
carries no size, no layout map, and no header other than the
constructor tag that `MM-VAL-8` places at word 0 for one of the three
representations. Given an address, nothing in the running program can
recover what is stored there.

**MM-VAL-7 (H, amended 2026-08-15).** A `Str` is the address of a
**three-word** header:

| Word | Contents |
|---|---|
| 0 | length in bytes |
| 1 | address of the bytes |
| 2 | the block that OWNS those bytes, or 0 |

The bytes are NUL-terminated *in addition to* being length-counted, so
`strCStr` hands a path to a syscall without copying, and a `Str` may
contain an interior NUL. `strSlice` **shares** the original's bytes
rather than copying them, so a slice keeps its parent's buffer live and
points into its middle (`MM-LIFE-6`) — and word 2 is what makes that
keeping *arithmetic* rather than accident: a slice INHERITS its
parent's owner rather than naming the parent, so the chain is one hop
deep however many times a slice is cut, and the counted address is
never interior. Zero means no block owns the bytes and nothing may
free them: a literal's are loader-resident, a syscall buffer's are the
kernel's, an arena keep block's interior belongs to the arena.
`strAlloc` names the buffer it just allocated and takes one share of
it; every `strSlice` takes one more.

**The rule is: every header that NAMES an owner holds a share of it**,
and the one place that broke it was found by writing this sentence
down. `Sys.sysReadAll` answers a second header over the read buffer's
bytes, inheriting the buffer's owner — and took no share, so two
headers claimed one count. Nothing releases a `Str` header yet, so it
was inert; the day `MM-LIFE-2e`'s extension work lands it is a
use-after-free into a block already on a size-class free list, not a
dangle into quiet memory. Fixed and gated 2026-08-15,
`tests/stdlib/358-str-owner-shares.ax` (63; the unfixed library
answers 51, and the two terms it loses are exactly the two that
measure the share). A defect that is *inert until a later rung* is
the class this specification's §9.0 exists to hold, and it is the
class a fixture written at the time of the rule cannot catch — this
one needed the rule stated in one sentence and then checked against
every caller.

**MM-VAL-7a (H).** A **string literal allocates nothing**. It evaluates
to the address of a static constant header whose length is a
compile-time constant, and literals are **interned by content**, so two
occurrences of the same text within a module share one header. Only
`strAlloc`, `strDup`, `strConcat` and their callers allocate.

**MM-VAL-8 (H).** A `data` type is assigned one of three
representations, computed once per type from its constructors
(`codegen.ax` `ctorsRep`). Tags are **globally unique across the
program**, not per type.

| Code | Condition | Representation |
|---|---|---|
| 0 | no nullary constructor, **or** the type's tags would reach 4096 | every value is a heap block; word 0 is the tag, fields at words 1.. |
| 1 | every constructor is nullary | every value **is** its tag, an immediate below 4096; nothing allocates |
| 2 | mixed | nullary constructors are immediate tags; fieldful ones are heap blocks |

All three facts are visible in one probe. With
`(data A () (A1) (A2))` and `(data B () (B1 Int) (B2 Int Int))`,
`(+ (cast Int (A2)) (cast Int (B1 7)))` emits:

```llvm
%.t0 = call i64 @axiom_alloc(i64 16)    ; B1: (1 + arity) * 8
store i64 4, ptr %.t2                   ; word 0 = tag 4
store i64 7, ptr %.t4                   ; word 1 = the field
%.t5 = add i64 3, %.t0                  ; (A2) IS the immediate 3
```

A1 = 2, A2 = 3, B1 = 4, B2 = 5: one counter, across both types.

**MM-VAL-8a (H).** Tags are drawn from **one global counter starting at
2**, spanning the whole compilation unit including imported modules,
whose constructors are numbered first. A type's tag values therefore
depend on the import graph and on declaration order — which is
observable only through `MM-VAL-8b`, and is why nothing may serialise a
tag.

**MM-VAL-8b (H).** There is a hard **representation cliff at 4096
tags**: when a type's first tag plus its constructor count reaches 4096,
the whole type falls back to representation 0, and its nullary
constructors become 8-byte heap blocks. **The same type, declared later
in a larger program, has a different machine representation.** Nothing
in the language exposes which one is in force, and nothing may depend on
it.

**MM-VAL-9 (H).** For representation 2, a match site tells the two apart
with a single runtime test: **a word below 4096 is an immediate tag; a
word at or above 4096 is an address.** The bound is sound because tag
assignment refuses to cross it (`MM-VAL-8b`) and because every heap
address comes from `mmap`, which never returns the zero page.

```
%c5 = icmp slt i64 %v, 4096
br i1 %c5, label %immediate, label %boxed
```

**MM-VAL-9a (H).** The guard is emitted by `match` and **not** by field
access, so field access on a `data` type **with a nullary constructor**
is **refused** (`AX3008`): a value of such a type may be an immediate
tag, and the unguarded load would dereference a small integer. On a
`data` type whose every constructor is fieldful the access stays legal
— no value can be an immediate — and
`tests/stdlib/210-struct-variants.ax` exercises that half beside
`tests/diagnostics/480-field-on-mixed-data.ax`, which pins the refusal.

```scheme refused
(data T () (E) (N { v : Int }))
(fn (main) (let ((x (E))) x.v))     ; AX3008 since 2026-08-14
```

Until then that program was `check: OK, run: exit 139` — a SIGSEGV
after a clean check. The rule offered a guard or a refusal; refusal is
what landed, because a guard needs an invented answer for the
missing-field case, and a silently invented value is this repository's
best-documented failure class. The corpus population of the unsafe
shape was **one** — the struct-variants fixture itself, whose comment
said "on a value whose constructor is known": known to the author,
invisible to the checker. It now matches.

**MM-VAL-9b (H).** A `match` whose arms cover no constructor and bind
no catch-all is **refused** (`AX3005`): it could fall through, and a
fall-through answered the match's freshly allocated result cell — which
`MM-ALLOC-6` guarantees is zero, indistinguishable from a legitimate
`0`. Pinned by `tests/diagnostics/476-literal-match-fallthrough.ax`.

```scheme refused
(fn (main) (match 7 ((1) 11) ((2) 22)))   ; AX3005 since 2026-08-14
```

Until then that program was `check: OK, run: exit 0`, answering the
zeroed cell. One all-literal shape stays accepted, because it cannot
fall through: a `Bool` match carrying **both** `true` and `false` arms
— those two are literal *tests* that contribute nothing to constructor
coverage (`MAC-HYG-5` measured why), and both present is exhaustive.

**MM-VAL-10 (H).** A `struct` is a heap block of `fields * 8` bytes with
field *i* at word *i*, in declaration order, and **no tag**. The
keyword form `(struct P a b)` and the application form `(P a b)` build
the identical block.

**MM-VAL-11 (H).** A struct variant — `(Circle { r : Int })` — is an
ordinary constructor block under `MM-VAL-8`; the field names are a
compile-time mapping to positions, honoured by patterns in any order.
Field *access* by name is available on a `struct` type, and on a `data`
type only when every constructor is fieldful — no value can then be an
immediate, so the load always reads a block. On a type with a nullary
constructor it is refused (`AX3008`, `MM-VAL-9a`); a field name that no
type declares is `AX3007`.

**MM-VAL-12 (R).** There are **no first-class continuations**, and none
of the machinery for them: no stack copying, no segmented stack, no
`call/cc`, no generators, and no re-entrant handlers. `handle` is the
only non-local control construct and it is tail-resumptive
(`MM-EXEC-10`) — the handler's frame *replaces* nothing and captures
nothing; the operation's site simply receives the handler's return
value. The evidence installed by a `handle` is a heap-allocated record
holding the handler closure and the previous evidence, saved and
restored around the body.

**MM-VAL-13 (R).** There are **no list or tuple values.** `[T]` and
tuple types are type-level constructions only; `[` in expression
position is `AX2001`. A sequence is a `data` type the program declares,
or a `Vec`. This is why the macro expander needs no case for either
(`macro-system.md` §11.3): a list-shaped *value* is always a constructor
application.

### 2.3 Closures

**MM-VAL-14 (H).** A `lambda` is lifted to a top-level function
`_lam_N` whose hidden first parameter is a **closure record**:

| Word | Contents |
|---|---|
| 0 | code pointer |
| 1.. | captured values, one word each |

**MM-VAL-15 (H).** Capture is **by value** and captures *everything in
scope* — every enclosing parameter and binding the lambda does not
shadow — rather than the body's free variables. The over-capture is
unobservable and deliberate: a free-variable walker's one missed case (a
pattern binder, a nested arm's variable) is a silent wrong capture,
while an extra record word is nothing.

**MM-VAL-16 (H).** A `mut` local is captured as **the value it held when
the record was built**. A closure never observes a later `set`
(`MM-MUT-1`).

**MM-VAL-17 (H).** A closure record built from a bare top-level function
points at a **forwarding thunk** `_thunk_N`, which ignores the record
and calls the function with its arguments unshifted. Every call through
a value therefore has one calling convention.

**MM-VAL-17a (H).** A lifted lambda's signature is
`@_lam_N(i64 %.env, i64 %p)` — environment first, then **exactly one**
user parameter. A multi-parameter lambda is curried into a chain of
one-parameter lambdas, **each allocating its own record**. Only an
arity-1 top-level function can become a function value at all
(`MM-EXEC-7`), and an arity-0 name is a call, not a value.

**MM-VAL-18 (H).** A call through a value applies **one argument per
step**: each step loads word 0 of the current record as the code
pointer, calls it with `(record, argument)`, and treats the result as
the record for the next step. A flat spine `(h 3 4)` over a curried `h`
means *apply, then apply the result*.

**MM-VAL-19 (H).** Partial application therefore exists only for
lambdas (`MM-EXEC-7`), and the intermediate value of a partial
application is an ordinary closure record.

### 2.4 Pointers

**MM-VAL-20 (H).** The type system has a pointer type, spelled
`*T` / `*mut T`, produced by `(alloc T)` and by nothing else a program
can write.

**MM-VAL-21 (H, defective).** `(alloc T)` **allocates nothing and
evaluates to the constant 0**, while typing as `*mut T`. There is no
dereference, no field access and no store through the result: every use
is `AX3004 expected struct or data type, found *mut Node`.

```
(fn (main) (cast Int (alloc P)))
    define i64 @__axiom_user_main() #0 { ret i64 0 }
```

Three further facts make the form unusable rather than merely
unimplemented:

- **`*mut` is unspellable in source.** No signature can name the type,
  so an `alloc` result can only be `let`-bound and `cast` — never passed
  to a declared parameter, never returned.
- **`alloc`'s type operand is never resolved.** An undefined type name
  inside `alloc` draws no `AX3002`, where the same name in a signature
  does. Its *count* operand is fully checked.
- **`alloc` nonetheless contributes the built-in `Alloc` effect**, which
  is inferred, surfaced on AXSYM as `#effects=Alloc`, and checked
  against a `;@axiom:pure` claim. A form that allocates nothing reports
  that it allocates.

<!-- doc-gate:negative-exempt a population count, not an existence claim. What falsifies it is any .ax file spelling the form, and the MUST in this same paragraph is what such a file would violate. The honest probe is a corpus counter, which this gate does not have yet. -->
This is a documented form with no semantics, at a shape whose corpus
population is zero — the failure class this repository names
*the corpus is the specification*.
**A conforming implementation MUST either give `alloc` the semantics of
`MM-ALLOC-11` or refuse it**; this specification does not bless the
current behaviour. Until that is decided, `alloc` **MUST NOT** be used
in a program, and the emitted 0 **MUST NOT** be relied on.

---

## 3. Allocation model

### 3.1 The allocator

**MM-ALLOC-1 (H).** A conforming implementation emits its allocator into
the program. Nothing is linked: a compiled Axiom program contains no
call to libc, and `scripts/check-freestanding.sh` gates it.

**MM-ALLOC-2 (H).** The allocator is a **bump allocator over
`mmap`-mapped chunks**, with five words of scalar mutable global state:

| Global | Meaning |
|---|---|
| `@__axiom_bump` | next free address in the current chunk |
| `@__axiom_bump_end` | end of the current chunk |
| `@__axiom_chunk` | head of the active-chunk list |
| `@__axiom_free` | head of the reclaimed-chunk free list |
| `@__axiom_high` | dirty watermark for the current chunk — a **conservative upper bound** on how far into it memory has ever been handed out |

Beside them, since `MM-LIFE-2e`'s release path, one **array**:
`@__axiom_slabs`, a free-list head per 16-byte size class (4,097
words, classes 16..65536). This row is stated because the sentence
above it said "exactly five words" for as long as the array has
existed; the count was the drift, not the design. Nothing else about
that sentence changes — the array is zero-initialised BSS, is
private after `fork` exactly as the five words are (`MM-PAR-3`), and
holds only addresses of blocks the program has released.

**MM-ALLOC-3 (H).** Every allocation is rounded up to a multiple of 16
bytes and every returned address is 16-byte aligned
(`%sz = and (add %size, 15), -16`).

**MM-ALLOC-4 (H).** A chunk is 1 MiB, or, when one request needs more,
the request plus a 16-byte header rounded up to 64 KiB. There is no
growth policy: the chunk size never adapts. Each chunk begins with a
two-word header — its total size and one link — so the **active** chunks
form a list, newest first, and the address handed out from a fresh chunk
is `base + 16`. The link word serves **both** lists, so a chunk is on
exactly one of them at a time and a freed chunk is unreachable from
`@__axiom_chunk`. The fit test is inclusive, so a request that exactly
reaches `bump_end` is served from the current chunk.

**MM-ALLOC-4a (H).** Chunks are obtained by a raw inline-assembly
`mmap` (`PROT_READ|PROT_WRITE`, `MAP_PRIVATE|MAP_ANON`, no address hint,
no guard pages) and are **never unmapped**. `munmap` appears nowhere in
the emitted runtime; the only reuse is the free list.

**MM-ALLOC-4b (H).** The free list is **first fit on the whole
mapping**: a chunk is taken if its total size is at least the requested
chunk size, and free chunks are never split and never coalesced. A small
request may therefore adopt a multi-megabyte free chunk whole, and
several free 1 MiB chunks can never serve one 2 MiB request. When a
request does not fit the current chunk, that chunk's remaining tail is
abandoned.

*That mechanism is a hazard with a measured bound, not a standing one.*
It read as unbounded here because nothing had measured it.
`scripts/check-net.sh`'s third measurement is the workload built to make
it ratchet: a request handler whose response size cycles from 8 to 488
concatenations — about 1 KiB to 3.8 MiB of intermediates per connection
— so free chunks of many sizes are produced and reused, and the 1 MiB
chunk boundary is crossed in both directions on every cycle. Peak worker
RSS reads **3,968 / 4,192 / 4,864 KiB at 1,000 / 5,000 / 20,000
connections**. It does **not** ratchet: it starts at the working set of
the largest single connection, which is the honest cost of serving one,
and then grows about 47 bytes per connection — the same per-connection
process baseline that gate establishes with a zero-allocation control,
and not the Axiom heap. The gate asserts the plateau (a run 100× longer
must stay within 2× of the short one) rather than a ceiling, because a
ceiling would pin the kernel's socket accounting.

Carry the gate's own scoping with the number: **this is the stateless
case**, where nothing keeps per-connection state and the live set at
each reset is empty. Keep-alive, where the live set outlives the request
and the arena boundary stops being free, is outside that measurement and
outside this paragraph's claim.

**MM-ALLOC-5 (H).** `mmap` returns chunks in **no particular address
order**. No rule in this document may assume that a later chunk has a
higher address; `MM-ALLOC-13` depends on this being stated.

**MM-ALLOC-5a (H).** The dirty watermark is **conservative in the safe
direction**: two paths set it to the chunk's *end* even though most of
that range was never handed out — installing a chunk recycled off the
free list (which is dirty to its last byte), and a reset that crosses
chunks. The consequence is that `MM-ALLOC-6` may scrub bytes that were
already zero, never that it skips bytes that were not.

**MM-ALLOC-5b (H, 2026-08-15).** The watermark describes **the current
chunk**, so nothing may compare it against an address from another one
— which is `MM-ALLOC-5`'s rule applied to the allocator's own code, and
`MM-LIFE-2e`'s release path was breaking it. A block popped off a
size-class free list may come from any chunk the program ever mapped;
the hand-out scrub bounded its wipe by `min(block end, watermark)` and
the store that follows moved the watermark to the block's end. Where
the block sat above the current chunk's watermark, the bound came out
*below* the block's own base, the wipe ran zero times, and the block
was handed back **with its previous contents** — `MM-ALLOC-6` broken by
a comparison `MM-ALLOC-5` forbids, and the watermark left pointing into
a foreign mapping. A recycled block is dirty to its last byte by
construction, so the pop path now scrubs all of it and leaves the
watermark alone; the two paths that bump-allocate are unchanged, and so
is the cost, because for a block below the watermark the old bound was
already the block's end (8 KiB × 20,000 iterations: 0.30 s before,
0.29 s after, same peak RSS).

*Not gated, and the reason is worth stating rather than leaving to be
discovered.* Reaching the broken case requires `mmap` to place a later
chunk **below** an earlier one, which is exactly what `MM-ALLOC-5` says
may happen and exactly what no program can force: the pool, the reset
and the free list all cooperate to keep the current chunk the newest
one, and the arena reset scrubs the slab heads (`MM-LIFE-2e`) which
closes the one route a program could steer. The hazard is therefore
argued from the code and priced at zero, not measured — and the
fixtures that do exist (`tests/stdlib/351-arc-reuse.ax`,
`363-arc-large-block.ax`) pass both before and after, which is the
honest statement of what they cover.

**MM-ALLOC-6 (H).** **Allocation answers zeroed memory. Always.** This
is a promise the standard library spends — `Map` and `Intern` read an
all-zero state array as "every slot empty", `strAlloc` reserves a byte
for a NUL terminator and never writes one — and it is delivered by
scrubbing at hand-out, below the high-water mark, rather than by
inheriting the kernel's zeroes. It held for free until a reset first
handed the same bytes out twice, at which point `strAlloc 3` produced a
string whose `cstrLen` measured 17.

**MM-ALLOC-7 (H, amended 2026-08-24).** Allocation failure writes
`axiom: out of memory (mmap failed)` — 35 bytes — to fd 2 and exits the
process with status 70. There is no recoverable out-of-memory condition
and no way for a program to observe one.

**The message is half of the rule and this rule did not record it.**
`emitOomTrap`'s own comment names the gap in those terms:
"`MM-ALLOC-7` records the status; it did not record that the status
arrives alone." Both `oom:` labels ended in a bare `exit(70)`, so a
program that ran out of memory vanished with a number and no output —
survivable for a compiler an operator is watching, not for a worker in a
pre-forked pool that disappears while the supervisor respawns it and
nothing anywhere says why. 70 now has the shape `emitDivTrap` already
had for 72 (`MM-EXEC-16`).

Pinned by `tests/stdlib/314-out-of-memory.ax`, which asks for 2^60
bytes: macOS overcommits, so a request for a terabyte SUCCEEDS and the
failure path is never reached, and the size has to be past the user
address space on every target this compiler emits for, so the mapping
is refused rather than merely unbacked. It asked for 2^47 until
2026-08-29, when FreeBSD 14.4/arm64 - 48 bits of user address space,
no overcommit accounting - granted it. The sentence is pinned in that case's
`.err` and the status in its `.exit`, neither checked by the other — a
program that printed the right sentence and exited 0 fails on the
status, and one that exited 70 in silence, which is what this tree did
until the trap was written, fails on the stderr. Its tail is
deliberately not a numeral, which is also the tripwire for this rule's
second sentence: the day the allocator ANSWERS instead of exiting, that
line runs, stdout gains a line, and the golden says so.

**MM-ALLOC-8 (R 2026-08-31; **P** from 2026-08-11, and three documents
described the seam as working until 2026-08-14, when all three were
corrected).** The rule as written was: the allocator **SHALL** be
replaceable by a program that defines `axiom_alloc`, which then assumes
`MM-ALLOC-6`'s zeroing and `MM-ALLOC-3`'s alignment obligations, and in
which the arena primitives of §3.3 **SHALL** be refused with a
diagnostic, since they move the position of an allocator that is no
longer there.

*Refused, and the reason is that the thing it was a prerequisite for
was decided against.* This rule was written while `MM-LIFE-2a`'s ARC was
the chosen strategy and a program that wanted control over reclamation
had nowhere else to get it. `MM-ALLOC-22` settled that question the
other way on 2026-08-24 — "the arena scope IS the reclamation strategy"
— and a program that wants control now has `__axiom_arena_mark`,
`__axiom_arena_reset` and `__axiom_arena_reset_keeping`, three
primitives a conforming implementation **MUST NOT** refuse. A *second,
independent allocator identity* underneath those is a different feature
with no stated acceptance criteria, and this rule's own text already
conceded that building it "interacts with the release path `MM-LIFE-2e`
left behind and would be re-decided against it". A **P** row that says
it would be re-decided before it is built is not a plan; it is a
question, and §0.1's answer to a question is a fresh rule with its own
acceptance criteria, not a status row that ages.

What it would have to survive, if it came back: `I1`–`I15`. Nine of
those fifteen invariants are statements about the emitted allocator
specifically — the 16-byte header on both allocation paths
(`MM-LIFE-2b`), the 4,097 slab-class heads a reset scrubs
(`MM-LIFE-2e`), the chunk list `MM-ALLOC-23`'s abort walks — and a
replaceable `axiom_alloc` is a program-supplied function that would have
to uphold every one of them with no way for the implementation to check
that it does. That is not an argument that it is impossible; it is the
acceptance criterion a future **P** rule owes, and this one never had.

*The half of the obligation that WAS taken stays taken, and is
unaffected:* an entry-file definition of `axiom_alloc` is refused.

*Today the seam does not exist, and the name is **refused**:* an
entry-file definition of `axiom_alloc` is `AX3026`
`reserved-runtime-name` at `check` time, pinned by
`tests/diagnostics/471-reserved-runtime-name.ax`. That is the
"refuse the declaration" arm of this rule's obligation, taken on
2026-08-14. Until then `emitAllocator` ran against the definition
unconditionally, so the program emitted **two** definitions of one
symbol; `check` reported `OK`, and the build died in the native
toolchain:

```
$ axiom check aa.ax        # before 2026-08-14
OK
$ axiom build --input aa.ax --output aa
opt: aa.ll:242:12: error: invalid redefinition of function 'axiom_alloc'
```

(Only the entry file could ever collide: a module's declaration is
mangled to `Mod$axiom_alloc`, a different symbol.) The three documents
that described the seam as working — `stdlib/Mem.ax`,
`docs/reference.md`, and the self-hosting record — were corrected the same
day, each keeping the false claim as quoted history. The rule's *head* —
a real replacement seam — is what moved to **R**: building one would
mean emitting the runtime allocator only when no declaration named
`axiom_alloc` is in scope, and specifying the required signature
`Int -> Int` returning 16-byte-aligned zeroed memory, with failure
behaviour. Nobody has specified any of that, and §9's Planned column now
holds `ALLOC-20` alone — the one genuine prerequisite left.

**MM-ALLOC-8a (H).** `__alloc` is an **unshadowable primitive name**. A
program may declare a function called `__alloc`, and it type-checks and
is emitted, but every call site is intercepted and lowered to
`axiom_alloc`, so the user's definition is unreachable code.

**MM-ALLOC-8b (H).** `(__alloc 0)` returns the current bump pointer
**without advancing it**, which before any chunk exists is the address
0, and afterwards is an address the next allocation will also return. A
program **MUST NOT** allocate zero bytes.

**MM-ALLOC-8c (H).** Every emitted runtime function carries the
attribute group `#0 = { "no-builtins" }`. This is load-bearing rather
than cosmetic: without it LLVM's loop-idiom recogniser rewrites the
scrub loop of `MM-ALLOC-6` and the copy loop of `MM-ALLOC-15` into calls
to `memset` and `memcpy`, which is a libc dependency in a freestanding
binary (`MM-ALLOC-1`).

### 3.2 What allocates

**MM-ALLOC-9 (H).** These, and only these, allocate:

| Construct | Block |
|---|---|
| a constructor with fields | `(1 + arity) * 8` bytes under representation 0/2 |
| `(struct P ...)` / `(P ...)` for a struct | `fields * 8` bytes, no tag |
| `Str` construction, `strDup`, `strConcat`, `strAlloc` | 2-word header, plus bytes where not shared |
| a `lambda` that is evaluated | closure record, `(1 + captures) * 8` bytes |
| `Vec`, `Map`, `Intern` operations | library-level, over `memAlloc` |
| a `match`'s result | since 2026-08-15: one scratch `alloca` per function, shared by every merge - a cell's live range is store-at-the-arm's-end to load-at-the-merge with nothing between, so one slot serves nested and tail shapes alike; before that, a one-word heap cell per `match` |
| a mixed-representation tag read | the same shared scratch `alloca` (`emitCondTagRead`); the fall-through zero a heap cell got from the allocator is stored explicitly now |
| `__axiom_arena_mark` | a three-word cell |
| `handle` on a declared effect | a two-word evidence record `{handler, previous}`; the form performs `Alloc` |

**MM-ALLOC-9a (H, amended 2026-08-15).** The cost this rule recorded
is paid no longer: `MM-LIFE-2c`'s event 7 releases the record at the
pop and the block recycles (`tests/stdlib/355-arc-events.ax`). The
original text, kept for the ledger: an evidence record is never
freed, so entering a `handle` inside a loop costs 16 bytes per
entry, retained until the
enclosing arena scope is reclaimed. A `handle` naming only built-in
effects allocates nothing, because it lowers to its body.

**MM-ALLOC-10 (H).** A nullary constructor of an all-nullary or mixed
type allocates **nothing** (`MM-VAL-8`). `(Nil)`, `(None)` and every
other fieldless constructor is an immediate.

**MM-ALLOC-11 (H).** **There is no stack allocation of data.** The
machine stack holds activation frames, spilled registers, and the
`alloca` cell of each `mut` local (`MM-MUT-1`) — nothing else. No
aggregate, closure or string is ever stack-allocated, and therefore no
value can dangle by outliving a frame.

### 3.3 Explicit reclamation

**MM-ALLOC-22 (H, 2026-08-24). The arena scope IS the reclamation
strategy, not a bridge to one.** A conforming implementation **MUST
NOT** refuse `__axiom_arena_mark`, `__axiom_arena_reset` or
`__axiom_arena_reset_keeping`, and **MUST NOT** condition their
availability on any automatic strategy. This is a new number rather than
an edit in place (§0.1) because it retires a `MUST` that pointed the
other way: `MM-LIFE-2e` ordered all three refused when ARC landed, and
`MM-LIFE-2a`'s ARC is withdrawn (§5, §9).

*The one refusal that used to survive this rule is gone with the seam it
belonged to.* `MM-ALLOC-8` reserved the right to refuse the three inside
a program that defines its own `axiom_alloc`, because they move the
position of an allocator that is no longer there. That seam is **R** as
of 2026-08-31 and never existed in any build (the name is `AX3026` at
`check`), so the exception describes a state no program can be in, and
this rule's **MUST NOT** is now unconditional.

*The evidence is a workload rather than an argument, and it is gated.*
`scripts/check-net.sh` builds one pre-forked server
(`tests/net/echo-server.ax`) and runs it twice against the same load,
differing only in whether the request handler is bracketed by a mark and
a reset. Each connection builds its response by repeated `strConcat` —
about 16 KiB of unreachable intermediates, so there is something real to
reclaim. Peak worker RSS:

| connections | handler scoped | handler unscoped |
|---|---|---|
| 1,000 | **192 KiB** | 19,136 KiB |
| 10,000 | **608 KiB** | 190,128 KiB |

**100× at a thousand connections, 313× at ten thousand.** The gate
asserts a floor of 50× — far enough under the measurement to survive a
slower machine, far enough over 1 to catch an arena that stopped
rewinding — and it carries the negative probe without which the flat
column would mean nothing: the unscoped run **MUST** grow past 2×
between the two lengths, because a measurement that reads the wrong pid,
samples after the workers died, or reads nothing at all also reads flat.
The same pair holds the language server at **840 bytes per edit**
against **193,247** with the boundary removed (`MM-LIFE-2e`).

*What the target workload is, stated rather than implied.* A stateless
request/response service is the shape this reclamation fits exactly: the
live set at the reset is empty by construction, so the boundary costs a
waterline restore and gives back everything the request touched.
`MM-ALLOC-16`'s program obligation is what a caller pays for that and is
unchanged — nothing verifies it, and the compiler still never inserts
these calls itself. Keep-alive, where per-connection state outlives the
request, is outside the measurement and outside this rule's claim
(`MM-ALLOC-4b`).

**MM-ALLOC-12 (H).** Three primitives move the allocator's position:

```scheme
(__axiom_arena_mark)                        ; -> mark cell
(__axiom_arena_reset mark)                  ; -> 0
(__axiom_arena_reset_keeping mark addr n)   ; -> new address of the kept block
```

A **mark** captures the whole allocator position — bump, end, *and* the
chunk the bump points into — in a three-word cell, because a bump
pointer alone is meaningless once allocation has moved to another chunk.
The cell is allocated *before* the position is read, which places it
below its own waterline; a reset therefore never reclaims its own mark,
and **the same mark may be reset more than once**.

**MM-ALLOC-13 (H).** A **reset** restores that position and moves every
chunk mapped since the mark onto the free list, where the next refill
finds it. Without the chunk list a reset could only restore a waterline
and would strand every chunk mapped after the mark — measured at 576 KiB
per iteration on a loop whose body crosses a chunk boundary.

**MM-ALLOC-14 (H).** **A reset writes no byte of what it reclaims.**
Memory above the restored waterline keeps its contents until it is
handed out again, at which point `MM-ALLOC-6` scrubs it. This ordering
is load-bearing: it is what lets a value be read *after* the reset that
reclaimed it, for exactly as long as it takes to copy it down.

**MM-ALLOC-15 (H).** `__axiom_arena_reset_keeping` reclaims to the mark
**and** carries one contiguous block across the reclaim in a single
operation, answering where it landed. It exists because a caller cannot
build it from the other two: written as a reset followed by an ordinary
allocate-and-copy, the destination is handed out by `axiom_alloc`, which
scrubs it, and when the kept block is larger than the garbage around it
**the scrub runs over the source before the copy reads it** — measured
at 39,841 of 40,000 bytes wrong on the first round. That is not a corner
case; it is a server holding a document and answering a short request.

The copy runs forwards, which covers both directions it can face:
within one chunk the source was allocated after the mark, so
`dst <= src`; across chunks the ranges are separate mappings that cannot
overlap at all — which matters precisely because of `MM-ALLOC-5`. When
the kept block does not fit in what remains of the marked chunk, the
destination comes from a **fresh mapping, never the free list**, because
the free list at that moment holds the chunks this call just reclaimed,
one of which may be the source's.

**MM-ALLOC-15a (H).** The destination of `reset_keeping` is deliberately
**not** scrubbed — the copy is what initialises it — so the padding
between `bytes` and the 16-byte rounding holds whatever was there
before. No caller can name those bytes.

**MM-ALLOC-16 (H, program obligation).** These three carry a contract
the compiler **cannot** check: *after a reset, nothing allocated since
the matching mark may be read again*, except the one block carried by
`reset_keeping`. Nothing verifies it, and the compiler never inserts
these calls itself.

**MM-ALLOC-16b (H, program obligation; implementation obligation since
2026-08-31).** An **evidence record is an ordinary arena object**
(`MM-ALLOC-9a`) with no protection from reclamation. A program **MUST
NOT** reset past a mark taken before a `handle` whose extent is still
live: the reset reclaims the evidence record the slot still points at,
and **the next operation — or the extent's own pop, which stores the
displaced record back through it — dispatches through it.** This is the
sharpest instance of `MM-ALLOC-16`, because the memory in question is
one the program never named. An implementation **MUST** detect it and
trap with status **76** (`MM-EXEC-16`).

*Measured before the check existed,* on the compiler at `ac169e1`, with
exactly the shape this rule names — mark, then `handle`, then reset
inside the extent, then perform an operation:

```
$ axiom run illegal.ax
dispatched through a freed evidence record
$ echo $?
0
```

The operation ran off memory the same call had reclaimed and the
program exited successfully. It exits **76** now.

*Why a non-null slot is always a live extent, which is what makes the
test sound rather than merely plausible.* The `handle` pop does not
null the slot — it stores back the record it displaced — so a completed
extent leaves the slot exactly as it found it, and the outermost pop
leaves it 0. A slot reading non-zero therefore names an extent that has
not ended, and a stale pointer from a finished handle cannot be there
to false-positive on. Two shapes that look like false positives are
not: a record recycled off a size-class free list (`MM-LIFE-2e`) can
sit *below* the waterline, where the reset does not reach it and the
range test is correctly silent; and `emitEffectOp` transiently installs
the *displaced* record for the duration of a handler call, which is
older than the current one and can only under-report.

*The recovery path needs no exemption and is given none,* which is the
result worth recording because it looked like the thing that would make
this uncheckable. `__axiom_recover_abort` **is** an arena reset across a
live extent — that is its whole job (`MM-ALLOC-23`) — but
`emitRecoverRuntime` calls `@__axiom_recover_load` *before*
`@__axiom_arena_reset_fn`, so by the time the check runs every slot
holds its arm-time value, which was installed before the arm and hence
below the arm's mark. The abort arranges for the test to be false on
its own. `tests/stdlib/401-recover-effect.ax`, whose entire purpose is
aborting out of a live `handle`, still exits 71 with unchanged stdout.

*What it does not catch, stated so nobody builds on it.* A reset
performed lexically **inside a handler body** is invisible: for the
duration of that call the slot holds the displaced record, so the
innermost one is in no slot at all. That shape is unchanged by this
rule and remains a program obligation.

*The cost to a program that declares no effect is zero, byte for byte.*
The check is emitted only when the program has at least one evidence
slot; `emitLiveHandleTrap` and `emitEvCheck` both answer `cg` unchanged
at zero slots, so neither the trap, its message constant, nor any call
is written. Measured: `tests/stdlib/010-hello.ax` and
`tests/stdlib/160-arena.ax` emit byte-identical IR before and after.
`self_host/` declares no effect at all, so the compiler itself is in
that class.

**MM-ALLOC-16a (H, program obligation; implementation obligation since
2026-08-31).** Marks **MUST** be reset in nesting order, innermost
first. Resetting an inner mark after its outer mark has already been
reset is a **fault the implementation MUST detect**: an implementation
**MUST NOT** restore an allocator position from a mark whose chunk is no
longer on the active list, and **MUST** trap with status **75**
(`MM-EXEC-16`) instead.

*This rule said the opposite until 2026-08-31,* and the sentence it said
is worth keeping: "The implementation does not trap, and a conforming
implementation **SHOULD**." It did not, and the reason was three lines
of `@__axiom_arena_reset_fn`. The unwind walk has two ways to stop —
the marked chunk found (`%reached`), and the walk falling off the end of
the active list without ever finding it (`%ranout`, which IS this
fault) — and they were merged into one `%stop` before the branch, so
both fell through to the same unconditional restore. Measured on the
compiler at `9116167` (v0.6.0) with exactly the shape this rule names:

```
$ axiom run illegal.ax     # mark outer, burn past a chunk, mark inner,
111                        # reset outer, reset inner, then allocate
987654321
$ echo $?
0
```

— a program that wrote and read back a word in a chunk that same call
had just pushed onto the free list, and said nothing. Since 2026-08-31
the two comparisons branch separately, `%ranout` calls
`@__axiom_bad_mark`, and the same program prints `axiom: arena reset to
an invalid mark` on fd 2 and exits 75. `tests/stdlib/166-arena-bad-mark.ax`
pins it.

*What this does NOT detect, stated so nobody builds on it.* Resetting
the **same** mark twice is legal and stays silent. A mark cell is
allocated before the position it saves is read, so it sits below its own
waterline and no reset reclaims it; after the first reset
`@__axiom_chunk` **is** the marked chunk, so `@__axiom_arena_reset_fn`
takes its equal-chunk fast path and the unwind walk is never entered.
That is the design (`emitArenaHelpers`'s own comment: "so the same mark
can be reset twice"), not a gap in the trap, and the fixture asserts the
silence rather than a trap so that a future change to either cannot
drift from what this paragraph says.

*The cost was re-measured rather than argued.* The two comparisons are
the same two — only the `or` that merged them is gone — and everything
before `unwind:` is byte-identical in the emitted IR, so the
equal-chunk fast path, which is what a bracketed request handler takes
on nearly every reset, cannot see this change at all.
`scripts/check-arena-reset-rate.sh` A/B on 2026-08-31, alternating two
compilers built from the same tree one branch apart, on a machine with
five other builds running:

| | per-reset |
|---|---|
| with the split branch | 2.146, 2.142, 2.517, 3.012 µs |
| with the merged `%stop` | 2.849, 2.200 µs |

The two sets interleave, so the change is not measurable above this
machine's own run-to-run spread — which is itself the reason both
columns sit above the **1.35 µs** §9.0 records: that figure was taken
on an idle machine on 2026-08-25 and is a floor for the *workload*, not
a threshold either column crosses here. What the A/B establishes is the
only claim this rule needs: the branch split does not move the number.

The measured shape of a correct use — the "managed" variant of
`scripts/measure-memory-baseline.sh` — is: mark once before the loop;
each iteration computes the next value, copies it *up*, resets to the
mark, and copies *down* from the up-copy, whose bytes sit above the
restored pointer and survive by `MM-ALLOC-14`. Flat at ~1.4 MiB from 80
through 20,000 generations, against ~16 KiB per generation forever for
the same loop unbracketed.

**MM-ALLOC-23 (H, renumbered 2026-08-31 from a second `MM-ALLOC-17`).
A trap may abort to a mark, and the abort discharges `MM-ALLOC-16b` on
its own path.** `(__axiom_recover mark thunk)` arms a
recovery point and runs `thunk`. Out of memory (70), an unhandled effect
(71) and a division by zero (72) then answer the *arming call* with
their status instead of writing to fd 2 and exiting; with nothing armed
they do exactly what they always did. Points nest, and an abort takes
the innermost armed one — `MM-ALLOC-16a`'s ordering rule, enforced by
the mechanism rather than left to the program.

The abort restores three things and runs nothing: the stack pointer, the
arena (a reset to `mark`, `MM-ALLOC-13`), and every evidence slot. The
third is what makes it sound where a program calling `__axiom_arena_reset`
by hand is not. `MM-ALLOC-16b` is a *program obligation* precisely
because a reset cannot know which `handle` extents it is cutting through;
an abort can, because the arm site snapshots every slot into the recovery
record before the extent begins and the abort writes them all back before
the reset. So the sharpest instance of `MM-ALLOC-16` is, on this one
path, discharged mechanically.

The N frames of pending `axiom_release` calls the jump abandons are
harmless, and it is `MM-ALLOC-14` and `MM-LIFE-2e` that make them so: the
reset reclaims everything above the mark regardless of any count, and
scrubs all 4,097 slab heads first, so nothing filed survives to be
double-issued. What is *not* free is a retain taken on a block **below**
the mark whose matching release was above it — `emitHandleDyn` takes one
on the record its push displaces, and `emitPrimRecover` takes one on a
thunk that is not a lambda built at the call. Those counts are abandoned.
The residue is bounded by the number of aborts, not by the work inside
them, and it is measured rather than argued: 100,000 aborts with a
`handle` inside every aborted extent hold max RSS at **1,376 KiB**,
byte-identical at 10,000 and at 100,000, against **419,328 KiB** for the
same program with the trap removed so nothing ever resets
(`scripts/check-recover.sh`).

This is not unwinding and does not become it. There is no landing pad,
no cleanup, no resumption and no way to catch anything at a chosen frame:
the only thing a recovery point can contain is one of the three traps,
and `docs/error-model.md` `ERR-REC-6` states what that does and does not
buy.

### 3.4 The inferred arena model — withdrawn

This section was the specification of the model
The roadmap sketched per-activation arenas
with escape promotion and a tail-call reset. **It is superseded by the
reference-counting decision of `MM-LIFE-2a`** (the decision landed
2026-08-11; these rules were marked withdrawn on 2026-08-14, when the
choice was fleshed out into `MM-LIFE-2b`–`2f`) — §10
records why — and its rules are kept under §0.1's convention:
withdrawn, numbered, cited, never deleted.

**`MM-LIFE-2a` was itself withdrawn on 2026-08-24** in favour of
`MM-ALLOC-22`'s arena scope, and a rule superseded by a rule that is
later withdrawn does **not** revive: this section lost on its own
measurements — `MM-ALLOC-19`'s tail-call reset could be discharged only
by a copy, a linearity proof, or region inference, and the copy was
built, gated and measured corrupting (§10) — and none of those
measurements moved. What replaced it is an arena a PROGRAM brackets,
not one a compiler infers, which is the half of this design that was
already built and gated when it was written down. Two survive with their
content intact: `MM-ALLOC-20` is the prerequisite for *any* automatic
strategy and is not withdrawn, and `MM-ALLOC-21`'s write-barrier
obligation lives on as the field-store event of `MM-LIFE-2c`.

**MM-ALLOC-17 (W).** Each function activation **SHALL** have an implicit
arena. A value allocated during the activation and not escaping it
**SHALL** be reclaimed when the activation returns, by restoring the
watermark — O(1) per activation, with no per-object bookkeeping.

*Today:* nothing is reclaimed at return. Peak memory is proportional to
total allocation.

*Withdrawn:* the returning-frame case is `MM-LIFE-2c`'s event 3 —
frame-owned references release at return, per object instead of per
watermark, and without needing to know what escaped.

**MM-ALLOC-18 (W).** A value that **escapes** — returned, stored into a
longer-lived structure, or captured by an escaping closure — **SHALL**
be allocated in the caller's arena instead. This is Tofte–Talpin region
inference with the annotations removed, which is why `region` was
deleted from the surface syntax rather than kept: an annotation the
compiler can derive is an annotation that will eventually be wrong.

*Today:* an escape analysis exists, and it arrived with counting rather
than with regions. `escapes` and `escapesViaBinders`
(`self_host/codegen.ax`), over the two call-graph fixpoints
`inferOwnership` and `inferFlows`, decide whether a frame-owned
reference may outlive the frame that built it; the walk shipped with
`MM-LIFE-2c`'s events 2 and 3 on 2026-08-21.

*Withdrawn:* what counting does not need is *region* inference. Its walk
asks one local question — may this release fire here — where this rule
asked which arena a value belongs in; ownership then follows the
reference wherever it is stored (`MM-LIFE-2c`, events 2 and 6), and
`region` stays deleted either way.

*Amended 2026-09-03:* `region` is back in the surface syntax, as
`MM-RGN-1`'s checked scope (`docs/memory-model-v2-design.md` §4, S2)
— a scope the PROGRAM brackets, which is what §3.4's own verdict asked
for, and not the annotation this rule said the compiler would derive.
The sentences above stand for the inferred model; they no longer
describe the keyword.

**MM-ALLOC-19 (W).** A **self tail call SHALL reset its activation's
arena to the entry watermark**, and this is the rule that matters. A
tail-recursive loop never returns, so `MM-ALLOC-17` alone reclaims
nothing from the one shape every compiler pass, request handler and
macro expansion has:

```scheme
(advance (step board) (- n 1))
```

The reset is sound only if the new argument does not point into the
memory being reclaimed. Three ways to discharge that obligation, in
increasing order of ambition:

| Discharge | Mechanism | Cost |
|---|---|---|
| **A. Copy at the boundary** | carry the new argument across the reset with `MM-ALLOC-15` | O(live) per iteration; always sound |
| **B. Linear consumption** | require the loop parameter to be linear, so the old value is provably dead | needs `MM-LIFE-7`; changes signatures |
| **C. Full region inference** | region-annotated types for the whole program | most precise; most research risk |

**A SHALL be implemented first**, because it is sound, simple, turns the
measured curve from linear into constant, and builds the machinery the
other two need. The machinery in question is already built and gated
(`MM-ALLOC-12`–`MM-ALLOC-16`, `tests/stdlib/165-arena-keep.ax`); what
remains is the compiler *inserting* it.

*Withdrawn:* under ARC the same boundary reclaims with no copy and no
discharge obligation at all — `MM-LIFE-2c`, event 4. This rule was the
hard case of the arena design, and its dissolving is most of the reason
the design lost (§10).

**MM-ALLOC-20 (P).** Before any automatic reclamation strategy —
`MM-LIFE-2a`'s ARC, the withdrawn rules above, or any collector —
can be implemented, **the implementation MUST be able to tell a pointer
from an integer**. It cannot today, for two independent reasons, and
both are prerequisites rather than details:

1. **No runtime discrimination — PARTLY RESOLVED 2026-08-15.** A word
   carries no tag (`MM-VAL-2`), but a heap block now knows its own
   words: `MM-LIFE-2b`'s header exists on every allocation path, and
   `MM-LIFE-2d`'s monomorphic half writes the shape word's reference
   map at constructor and struct sites from DECLARED field types, so
   release walks a dead block's fields transitively. A type variable
   still hides pointerhood from STATIC classification, and the
   evidence word now answers it at run time (`MM-LIFE-2d`'s evidence
   half, held 2026-08-15); roots remain untrackable until the
   ownership events land (`MM-LIFE-2c`).
2. **No static discrimination — RESOLVED 2026-08-15.** `String` and
   `Int` were *unified by fiat* in `tyCompat`, the deliberate
   compatibility rule that made `Int` the universal heap-handle type.
   The fiat is DELETED: a string is a `String` to the checker
   everywhere in the compiler, the stdlib and the corpus, the
   containers carry type variables instead of spending the rule, and
   `(+ 1 "hi")` is the `AX3004` it always deserved
   (`tests/diagnostics/555-string-int-distinct.ax`; string EQUALITY
   survives through the content rewrite, answering Bool ahead of the
   numeric matrix). What static discrimination still cannot see: a
   type VARIABLE hides pointerhood by design — `MM-LIFE-2d`'s
   evidence word is that answer, not more checking.

A conforming implementation of automatic reclamation **MUST** first
introduce a type-level distinction between a heap handle and an integer
— the static half, whose measured progress `MM-LIFE-2a` quotes — and
`MM-LIFE-2d` adds the runtime half: a per-block reference map, plus
pointerhood evidence where a type variable hides the answer. This rule
exists because a compiler-inserted copy has already been tried without
it once — the `ArenaCompact` instruction, removed rather than finished,
which misidentified a `Vec` header as a constructor cell, wrote past
the end of its chunk, and could not see `Str` or `Vec` at all
(the self-hosting record).

**MM-ALLOC-21 (W).** Mutation and arenas interact, and
The roadmap did not account for it because it
assumes Axiom's data is immutable — which is false (`MM-MUT-2`). A field
store can install a reference to a *younger* value into an *older* one:

```scheme
(set old.next young)     ; `young` now outlives `young`'s arena
```

A conforming implementation of escape promotion **MUST** therefore treat
the target of a field store as an escape of the stored value into the
target's arena — the obligation a generational collector discharges with
a write barrier. Without it, a per-activation arena reclaims memory that
an older value still points at.

*Withdrawn with the model; the obligation did not die.* It is
`MM-LIFE-2c`'s event 5, where a field store retains the stored value
and releases the overwritten one — the same barrier, holding a count
instead of promoting an arena.

---

### 3.5 `cast` degrades the evidence word — measured

**MM-VAL-22 (H, renumbered 2026-08-31 from a second `MM-LIFE-2e`).
`cast` is not a type-level no-op. It is also an
instruction to the reference model, and the instruction is "do not
trust this word".** `evStampFill` (`self_host/typecheck.ax`) classifies
an argument whose root is a `cast` as evidence **0** outright, on the
stated grounds that "the cast launders a word past the checker, and
evidence must not trust it".

The consequence is not confined to arguments in type-variable
positions, and it is not a warning anywhere. Measured on the emitted
LLVM, same program either way:

| the call | evidence word | `axiom_release` |
|---|---|---|
| `(memSetWord p 0 "hi")` | `1` | emitted |
| `(memSetWord p 0 (cast String "hi"))` | **`0`** | **gone** |
| `(strEq (mk 1) "ab")` — concrete parameter | — | 4 releases |
| `(strEq (cast String (mk 1)) "ab")` | — | **3 releases** |

So a `cast` at an argument root suppresses a retain where the parameter
is a type variable, and suppresses a release where it is concrete. The
first direction risks a **premature free**; the second **leaks**.

**Why this matters more than it looks.** `cast` is the language's only
reinterpretation operator, so it is the obvious tool for repairing the
type-soundness hole `AX3040` reports — a signature returning a variable
no parameter mentions. Making all fourteen of those concrete produces
**1,223 type errors**, and the obvious repair is a `cast` at each site.
That repair would trade a type-system unsoundness for a memory-model
regression at 1,223 places, silently.

**MM-VAL-23 (H, renumbered 2026-08-31 from a second `MM-LIFE-2f`).
The safe vehicle is a typed accessor, not a call-site cast.** A cast placed at a RETURN, inside a function whose
declared type carries the truth, leaves callers seeing that declared
type — and the evidence word is computed from it. Measured:

```scheme
;@axiom:raw
(:: getStr (-> Int Int String))
(fn (getStr a i) (cast String (memGetWord a i)))

(memSetWord p 0 (getStr p 0))     ; evidence word 1, releases emitted
```

That is the migration recipe for the `#raw` layer. `mapValAt` was moved
off it by casting inside `mapGet`, "where `a` is already witnessed by
the `dflt` parameter" — **and that reason was wrong, measured
2026-08-25.** `dflt` witnesses what the caller wants back when the key
is ABSENT; the cast sat on the found path, where the word came out of a
table that carries no element type. The two are unrelated, so the
signature let a caller name a type the table does not hold:
`(mapInsert m 1 100000000)` then `(strLen (mapGet m 1 "absent"))`
checked `OK` and exited **139**.

`mapGet` answers `Int` now — the truth about a machine word — and
`mapGetStr` is the typed reader beside it, which is the
`vecGet`/`vecGetStr` and `memGetWord`/`memGetWordStr` shape `Map` was
the last container to be missing. The cast is still at a RETURN and
still not at the call, which is the part of the recipe that was right:
what changed is which position is honest about what it produces, not
where the cast goes.

## 4. Mutation

**MM-MUT-1 (H).** `(let ((mut x e)) ...)` introduces a mutable local,
assignable with `(set x v)`. It lowers to an `alloca` with loads and
stores, is invisible outside its function, is captured by snapshot
(`MM-VAL-16`), and performs **no** effect — a local's mutation cannot be
observed by anyone else.

```
%a0 = alloca i64
store i64 0, ptr %a0
```

**MM-MUT-1a (H).** `set` on a binding a lambda merely captured, and
`set` on a function parameter, are both **refused in the checker** —
`AX3012`, with a message per shape: a parameter is immutable and has no
`mut` spelling to suggest, and a captured binding may well be `mut` but
the lambda holds its *value* (`MM-VAL-16`), so no store could ever be
observed. Pinned by `tests/diagnostics/465-set-on-parameter.ax` and
`466-set-captured.ax`. Until 2026-08-14 both passed `axiom check` and
failed in codegen with `AX4002 set target is not a mut binding`, whose
own note read *"this is a compiler bug: the check that should have
refused this program did not run"* — the parameter case because the
refusal was suppressed whenever the binding recorded no binder span,
which is exactly the parameters, and the capture case because the
target lookup ignored the lambda boundary. `AX4002` remains as the
backstop it was always meant to be.

**MM-MUT-2 (H).** `(set e.f v)` stores into a heap field **in place**,
and the write is visible through **every** alias of `e`. It performs the
`Mut` effect, precisely because it is visible where a local's mutation
is not. The form evaluates to `0`, and its static type is `I64` — which
does **not** stop it being the value of a function returning `Int`:
`(fn (bump p) (set p.x 1))` declared `(-> P Int)` checks `OK` when `P`
declares `(mut x : Int)`.

```scheme
(let ((p (P 1 2)) (q p))
  { (set p.x 99) (println q.x) })   ; prints 99
```

**MM-MUT-2a (H).** The field must be declared `mut`; a store into one
that is not is `AX3012` at the field name in the write. This is the
`let` rule applied to fields, and it is checked from 0.6.0 — before
that the marker was parsed and dropped, and every field of every struct
was writable. Only the LAST segment of a path is governed: `(set
a.b.c v)` needs `c` declared `mut` and says nothing about `b`, because
the store mutates the value `b` points at rather than the `b` slot.
`memSetWord` is outside the rule entirely — it takes a block and a word
index, which is how `Vec` and `Map` write slots that are not fields.

**MM-MUT-3 (H).** Field stores are available on **named fields of a
`struct` type only**. A `data` constructor's positional fields have no
name to store through (`AX2001`), and a struct variant's fields are
reachable only by pattern match (`AX3007`). Constructed `data` values
are therefore immutable in practice — by the absence of a spelling,
not by a rule.

**MM-MUT-4 (H, program obligation).** There are **no aliasing
restrictions**. Any number of names may refer to one heap block; the
language has no uniqueness, no borrow checking, and no read-only
reference. A program that relies on a value not changing under it
**MUST** copy it (`strDup`, or an explicit rebuild).

**MM-MUT-5 (H).** The standard library's containers are **mutable in
place**, not persistent. `vecPush` mutates and returns the handle it was
given, so a `Vec`'s identity is stable across growth even though its
data buffer moves. `Map` rehashes in place. This is a deliberate trade —
these exist to serve a compiler that runs in milliseconds — and it means
**no structure in `stdlib/` is safe to share across a mutation**.

**MM-MUT-6 (R).** Axiom provides **no persistent data structures** and
no structural sharing beyond `strSlice`'s byte sharing (`MM-VAL-7`). A
program needing them builds them from `data` types, which are immutable
by `MM-MUT-3` and therefore share freely and safely.

---

## 5. Lifetimes and reclamation

**MM-LIFE-1 (H, amended 2026-08-15).** The lifetime of every heap value
is **the process**, unless a program reclaims explicitly with §3.3 — or
unless the counting machinery reclaims it, which since the first
ownership events (`MM-LIFE-2c`) it does for the shapes those events
reach: a directly-built construction discarded in statement position,
and a `handle`'s evidence record at its exit. There is no `free` and no
destructor, and there is still no collector; there IS now a reference
count on every heap block, and a block whose count reaches zero joins
its size class and is handed out again (`MM-LIFE-2b`, `2e`). What has
not changed is the DEFAULT: a value nobody releases still lives as long
as the process, because most of the events are not emitted yet.

**MM-LIFE-2a (W, 2026-08-24) — the chosen strategy: reference counting.**

*Withdrawn: superseded by `MM-ALLOC-22`, and withdrawn in §0.3's second
sense — **abandoned in place**, not superseded before implementation.
The paragraph at the end of this rule is what that costs; read it before
reading anything below as a plan.*

Automatic reclamation **SHALL** be automatic reference counting. Every
heap block gains a count; the compiler emits a retain where a reference
is copied into a longer-lived place and a release where one dies; a
block whose count reaches zero is reclaimed immediately, which makes
reclamation **deterministic** — the property `MM-LIFE-7`'s `consume` was
introduced to express, obtained without linear types.

**Cycles leak, and that is the accepted cost.** `MM-LIFE-3` measures
that cycles ARE constructible — one route uses nothing but `stdlib/Vec`
— so ARC alone does not reclaim everything, and this specification
**MUST NOT** claim otherwise. It is memory-*safe* (a live object is
never freed) and incomplete (an unreachable cycle is never freed), which
is the same bargain Swift makes. Today nothing is reclaimed at all, so
even a leaky ARC is strictly better than the status quo; a cycle
collector beside it stays available as a later, separable decision.

**The prerequisite, and how far it has come.** ARC needs to know which
words are references, and `MM-ALLOC-20` records why nothing can tell
today. That blocker is the `String`/`Int` fiat, and this specification
can now quote its price and its progress rather than estimate either.

Removing the fiat from `tyCompat` produced **2,733** type errors when
first measured, and **3,882** once `stdlib/Str.ax` declared its own
string positions — the rise is progress, not regression: more strings
became visible to the checker. Inference over the tree brought that to
**1,431** by annotating **604 declarations across 25 files** — and on
2026-08-14/15 a four-slice campaign took it to **ZERO for the compiler
and the entire standard library** (`5399acf`..`ba57f65`: constructor
families first, then eleven parallel per-file judgement passes, then
the cross-file producers those passes named). The fiat was DELETED on
2026-08-15, one commit after the measurement: the 17 dependent
fixtures were retyped honestly (container VALUE positions became type
variables; the fixtures' own helper signatures told the truth; string
equality gained its Bool answer ahead of the numeric matrix), the
corpus's exit-status differential read zero across all 297 files, and
the clause came out of `tyCompat` with its history recorded in place.

The annotations were derived from **what each body does with the value**,
not from the diagnostic list. A parameter handed to `strLen` is a string,
and that conclusion does not depend on which call site the checker
happened to complain about — which is why this pass converges (it
terminated with zero further changes) where an error-driven rewrite
oscillates. Three rules, applied to a fixpoint:

- a parameter passed to a `String` position of any declared signature is
  a `String`, the table of such positions being *derived from the tree's
  own declarations* so that typing one function propagates to its
  callers;
- a function whose **every** tail position is a string — literal,
  `String` parameter, or a call to a `String`-returning function —
  returns a `String`. Every tail, not any: a function answering `""` on
  one branch and a node handle on another is not a string function;
- `let`-bound locals are typed from their initialisers, one level down
  by the same rule.

**The change is provably behaviour-neutral.** `String` and `Int` share a
representation and `cast` is free, so annotating cannot alter generated
code — and it did not: the IR emitted from the annotated tree is
**byte-identical** to the IR from before it, compared with the same
compiler. The full gate battery passes, including the stage2/stage3
fixpoint.

Two things remain, and they are the reason this is not finished:

1. **The untyped containers had to become parametric first.** `Vec`,
   `Map` and every AST node word hold either a handle or an integer, so
   their accessors take a type variable and `cast` at the machine
   boundary — `memGetWord`, `vecGet`/`vecPush`/`vecSet`, `nodeA`/`nodeB`/
   `nodeC` and `mkNode` are converted. A signature's type variable is
   **rigid inside its own body**, so each such body needs an explicit
   `cast a`. (One visible consequence: a parametric parameter is read as
   effect-transparent, so `memSetWord` now reports `#effect-params=value`.)
2. **The last 1,431 need per-declaration judgement.** They are dominated
   by values that reach a string position through a local whose producer
   is still untyped, and by positions that genuinely carry both. No
   syntactic rule decides these; deciding them is what makes an
   annotation *true* rather than merely accepted, and it is the
   remaining work before the fiat can actually be deleted.

What the strategy requires of the machine — a count word, the ownership
events, a reference map, a release path in the allocator, and a stated
cycle obligation — is `MM-LIFE-2b`–`MM-LIFE-2f`. Each says what happens
today, and together they are the specification the one-paragraph
decision above was not. Each was **P** until 2026-08-24 and each is now
**W** with this rule, for the reason below and in the same sense.

**Withdrawn 2026-08-24. What that means, and what it does not.** The
project's target workload is stateless request/response service, and the
reclamation for it is the arena scope: `MM-ALLOC-22` measures a request
handler bracketed by a mark and a reset at **100–313× less memory** than
the same binary unscoped, gated with a negative probe, with the language
server's 840 bytes per edit against 193,247 beside it. The arena is the
strategy, not a bridge to this one. Reference counting is no longer
scheduled, and no rule in this document may cite `MM-LIFE-2a` as
something that is coming.

**The machinery that landed is not withdrawn, because it cannot be.**
"Retire ARC" means "stop finishing it", and the half that shipped emits
on every build today: `MM-LIFE-2b`'s 16-byte header is on both
allocation paths, **all seven** of `MM-LIFE-2c`'s ownership events emit
(`tests/stdlib/355-arc-events.ax`, `361-arc-field-store.ax`,
`362-arc-tail-boundary.ax`, `364-arc-frame-release.ax`,
`372-arc-owned-results.ax`), `MM-LIFE-2d`'s monomorphic, evidence and
`Str` halves hold, `MM-LIFE-2g`'s `__retainref` is on the hottest store
in the compiler, and `MM-LIFE-2e`'s release path files dead blocks onto
`@__axiom_slabs`. Taking any of that out is a compiler change carrying
its own measurements — the self-compile that this machinery took from
2.93 s to 1.94 s and 314 MiB to 248 is the same machinery — and not a
documentation edit. This document will not write about it in the past
tense.

**The half-finished state carries a permanent per-request cost, and it
is 1.7–1.8% of a request** — a figure this paragraph had as *“under one
percent”* until 2026-08-25, when a gate measured it instead of a bench.
The correction is below, where the estimate that produced the old number
is. `__axiom_arena_reset_fn` scrubs **4,097** slab
heads on every reset — 4,097 stores on the exact path `MM-ALLOC-22`'s
workload takes once per request — and it does that **precisely
because** releases file blocks into those heads: a head left dangling
across a reset double-issues storage on the next same-class allocation.
Counting bought that scrub and the arena pays it, once per request,
forever, on a strategy nobody is finishing.

It was priced at *unknown* here until 2026-08-24, on the correct ground
that nobody had run it, and the number turned out to be small. Two
workers, 5,000 loopback connections, the same binary either side of its
arena flag: **12,864 and 12,986 conn/s scoped against 13,282 and 13,032
unscoped** — runs that overlap. 32 KiB of stores costs about 0.6 µs
against a per-connection budget near 77 µs, which is where the
sub-one-percent figure came from rather than from the ratio directly.

**That estimate was wrong, and the way it was wrong is the argument for
the gate.** `tests/net/echo-server.ax` takes `__axiom_arena_mark`
unconditionally and only the reset sits behind the arena flag, so its
two arms ablate the WHOLE reset rather than the scrub — and they
overlap, which is why the number had to be reasoned from 32 KiB of
stores instead of read off. `scripts/check-arena-reset-rate.sh` runs one
program in three spellings a word apart, so the cost is *attributed*: a
reset is **~1.35 µs** and a mark under 10 ns at `--opt 1`, which is
**1.7–1.8%** of the same 77 µs budget, not under one.

Both halves of that are worth keeping. The residue is real — it is the
price of composing §3.3 with counting at all, and it does not go away
while `MM-LIFE-2a` stays abandoned in place. And it is small, which is
why it does not argue the strategy back onto the schedule; it is no
longer *noise*, because 1.7–1.8% is a figure a reader can act on and
0.6% was not.

What this paragraph argued until 2026-08-25 was narrower still, and it
is **closed**: `check-net.sh` measures memory and not time, so the
figure came from a bench and not from a gate, and nothing here compared
a reset carrying the scrub against one without it.
`scripts/check-arena-reset-rate.sh` does, in six checks, two of which
have no clock in them at all — the emitted scrub is asserted from the
IR, and the negative probe deletes that block and rebuilds, dropping the
cost 42×. §9.0 records the row as closed on that ground: not that the
cost became known, but that something would now notice it changing.

**MM-LIFE-2b (W 2026-08-24, abandoned in place —
see `MM-LIFE-2a`; what already emits is recorded below and stays).
The count word.** Every counted block **SHALL** carry
a 16-byte header immediately below its address: word −2 the reference
count, word −1 the shape word of `MM-LIFE-2d` — which carries the
block's word count as well as its reference map, because release needs
both: the map to walk the dead block's fields, and the size to hand the
block to the right free list (`MM-LIFE-2e`). A block that did not
record its own size would make the release path unimplementable against
`MM-VAL-6`'s blocks, which know nothing. The block's own
address and every field offset are unchanged — the header is invisible
to every consumer that exists today, and only `axiom_alloc`, retain,
release and the map writer know it is there. The cost is exactly 16
bytes per counted block: `MM-ALLOC-3` rounds every size to a multiple
of 16, so a 16-byte header moves each block up by one rounding step and
never more.

Three classes of word are exempt, each by a test that already exists:

- **Immediates.** A word below 4096 is a tag, not an address
  (`MM-VAL-9`, `I3`). Retain and release on a reference-typed position
  **MUST** skip it with the same compare a mixed-representation `match`
  already emits. Rep-1 values and rep-2 nullary constructors therefore
  cost nothing — exactly as they allocate nothing (`MM-ALLOC-10`).
- **Statics.** A literal's header and bytes are loader-resident and
  **MUST NOT** be written (`MM-FFI-2`). The emitter **SHALL** lay
  static constants out under the same header shape with the count word
  all-ones, and retain and release **MUST** read the count first and
  leave a sentinel untouched: a static is never reclaimed, and never
  written even by the machinery that reclaims.
- **Non-reference positions.** An `Int`, `Float`, `Bool` or `Char`
  position is never retained or released at all. The decision is
  static, which is why `MM-ALLOC-20` is a prerequisite rather than an
  optimisation.

*Held since 2026-08-15* (`tests/stdlib/350-arc-header.ax`, 19 — the
count word reads 0 at birth, `__retain`/`__release` move it, a
release at zero floors rather than forging the statics sentinel, a
literal's all-ones count is read and never written, and a negative
immediate is skipped by the signed compare). The header is written on
BOTH allocation paths — `axiom_alloc` and the arena keep helper,
which the design review caught as a second path the LSP crosses every
message. The shape word was emitted zero and read by nothing when
this held; `MM-LIFE-2e` then made the allocator the size writer and
`MM-LIFE-2d`'s monomorphic slice re-encoded the word and added the
map writers, as each of those rules records. This rule amends
`MM-VAL-6` by exactly two words of self-description, and no more — a
block still does not know its own size or type, only its count and
which of its words are references.

**MM-LIFE-2c (W 2026-08-24, abandoned in place —
see `MM-LIFE-2a`; what already emits is recorded below and stays).
Ownership.** The events, exactly — each is a place
the compiler **SHALL** emit a retain (+1), a release (−1, reclaiming at
zero), or deliberately neither:

1. **A call borrows its arguments.** No retain at the call boundary:
   the caller's frame outlives the callee's (`MM-ALLOC-11` — frames
   strictly nest and the stack holds no data), so the caller's
   ownership covers the callee's use.
2. **A function returns its result owned.** The caller receives +1 and
   must release it, store it, or return it in turn; returning a
   borrowed argument therefore retains it first.
3. **Frame slots own.** A reference bound or `set` into a local slot
   is owned by the slot: an owned value *moves* in, a borrowed one is
   retained on the way in. `(set x v)` releases the owned value it
   overwrites (`MM-MUT-1`) — sound precisely because the slot retained
   what it holds, whatever its provenance — and a returning frame, or
   event 4's boundary, releases every live owned slot that did not
   escape by being returned or stored. The elision licence below is
   what keeps the common borrow-bind-read shape free of traffic.
4. **A self tail call is a release boundary, and its function owns its
   reference parameters.** Entry retains each reference parameter once
   — without this, iteration one would hold its arguments borrowed
   where every later iteration holds them owned, and there is no
   caller frame left to do the borrowing (`MM-EXEC-6b` replaces the
   frame with a branch). Owned references dead across the call are
   then released before control branches back to
   `MM-EXEC-6b`'s loop header. This is the rule that replaces the
   withdrawn `MM-ALLOC-19`, and it is the point of the strategy: the
   loop shape that defeats per-activation arenas — the activation that
   never returns — reclaims each dead generation at the boundary with
   no copy, no linearity requirement and no region inference. The
   trilemma `MM-ALLOC-19` tabulated dissolves rather than being solved,
   and the sharing that made a copy-at-the-boundary corrupt
   (`MM-ALLOC-15`'s reason to exist) is under counts just arithmetic:
   substructure the new generation shares ends the release walk at a
   nonzero count.
5. **A field store retains the new value and releases the old**
   (`(set e.f v)`, `MM-MUT-2`). This is `MM-ALLOC-21`'s old-to-young
   obligation surviving that rule's withdrawal — a write barrier by
   another name, and the reason mutation composes with counting where
   it did not compose with arena inference.
6. **Building a block stores its reference fields owned** — constructor
   fields, struct fields, closure captures (`MM-VAL-15`'s over-capture
   acquires a price: a captured reference is a retained reference), and
   both words of an evidence record.
7. **`handle` releases its evidence record at exit**, closing
   `MM-ALLOC-9a`'s sixteen bytes per loop entry.

A conforming implementation **MAY** cancel a retain against a release
it can pair statically. The licence costs nothing observable: a
conforming program observes no address (`MM-EXEC-12`), so reclamation
timing surfaces only as peak RSS — and determinism (`MM-EXEC-11`)
holds, because counts are a function of program text and input, never
of layout.

*Held in part since 2026-08-15* (`tests/stdlib/355-arc-events.ax`,
7 - reclamation with no `__retain`/`__release` in the source; `352`
and `354` re-pinned under the new arithmetic). What emits: every
compiler-built ownership-creating block - constructor cell, struct
block, closure record, evidence record - is BORN at count 1, the
constructing expression's own share (raw `__alloc`/`memAlloc` and
`strWrap` stay birth-0: a second birth would double-count every
String); event 6's field retains land at construction, mirroring
the shape word's classification exactly and MOVING a directly-built
argument instead of retaining it; event 7 releases the evidence
record at the pop, so a `handle` in a loop recycles its record - a
thousand entries move the bump by less than one block; and a
directly-built construction discarded in statement position
releases on the spot. Every retain this slice emits is one an
EXISTING map can return - that is the slice's rule.

**Event 5b — the closure half — emits since 2026-08-30**
(`tests/stdlib/460-closure-reclaim.ax`, 63 against the unfixed
compiler's 7; `scripts/check-closure-reclaim.sh`): an application
through a CLOSURE gives back the intermediate record a curried chain
builds. Every function value absorbs exactly one argument, so a
two-argument handler is a chain, the record its first step answers is
born at count 1, nothing else ever holds it, and once the next step
has loaded its code pointer and called it that share is the walk's to
return. Its balance is local in event 5's sense — no escape analysis,
because the record is one this walk made — and the two walkers carry
`recOwned` to tell it from the record the caller handed in (a handler
out of the evidence slot, or a closure value someone else's `let`
holds), which is never theirs to release.

Unreleased it was **32 bytes per application**, and the cost was not
only bytes: `stdlib/Fallible.ax` names it as the reason its operation
takes ONE argument, so a compiler defect had become a language design
decision. That row now reads 0. The other half of the closure gap —
the owned ARGUMENT a closure application consumes, which a direct call
has released since `MM-LIFE-2g` — is still open, and is 96 bytes for a
message built per record.

**It is open because THE LEAK IS LOAD-BEARING, and that is a stronger
statement than "not done yet".** The rule this was to be closed with —
release the argument where the application's result class is known to
be a word, on the reasoning that a word answer cannot *be* the
argument — is **unsound**, measured 2026-08-30. A lambda that PARKS
its argument and answers `0` satisfies it, and the park takes no
share:

    in a named `fn`   call @Vec$vecPush(i64 %box, i64 %s, i64 1)
    in `_lam_0`       call @Vec$vecPush(i64 %.t2, i64 %m, i64 0)

The trailing operand is `MM-LIFE-2d`'s evidence word, and `0` means
`__retainref` emits nothing. So `releaseOwnedArgs`' governing premise —
"every store it could make took a share (events 5/6, `MM-LIFE-2g`)" —
**is false inside a lifted lambda**, and is false for the same reason
on both application paths.

Today the two defects cancel: nothing releases the argument, so the
uncounted park is harmless, and a lambda parameter is never
`valueOwnedRef` so the two never meet. **Closing the leak is precisely
what makes them meet.** Simulated with `__release` at exactly the point
the walker would emit it, a parked 16-byte String reads back as 3 —
the length of the string allocated into the block after it was filed.
`tests/stdlib/460-closure-reclaim.ax` term 64 pins that: 127 today, 63
the moment the release is added.

What this half really waits on is therefore not a guard but a
prerequisite: **a lifted lambda taking an evidence word**, so that a
store inside one takes its share like a store anywhere else. Until
that lands the 96 bytes stay, deliberately.

**Event 5 emits since 2026-08-15** (`tests/stdlib/361-arc-field-store.ax`,
63 against the unfixed compiler's 7): `(set e.f v)` into a reference
field retains the new value and releases the one it overwrites, in
that order, so a self-assignment cannot free what it just stored. It
went ahead of events 2, 3 and 4 because its balance is **local and
provable without escape analysis**: a mapped field's old value is
owned BY THE BLOCK, since the store that put it there took a share —
`emitFieldStores` at construction, or this same function on a
previous pass — so handing that share back is arithmetic rather than
a judgement about who else is holding it. The classification is
`fldClass`'s, the same one that wrote the block's map, so the release
set and the walk set cannot disagree. What that argument rests on is
that every field HAS a classifiable type, and until `AX3056`
(2026-08-30) one did not have to: a field spelled without its `:` was
given the empty type variable, which `fldClass` cannot classify, so it
left the map and this retain together and a value stored into it was
freed under the program — measured at exit 139
(`tests/diagnostics/388-struct-field-untyped.ax`). A field that cannot
be classified is now refused at its declaration, which is what makes
the sentence above true rather than true of well-spelled programs. A thousand overwrites of one
field with a fresh 48-byte string move the bump by under 4 KiB.

**Event 4 emits since 2026-08-15**
(`tests/stdlib/362-arc-tail-boundary.ax`, 63), and it is the event
this whole strategy exists for: the activation that never returns,
which no per-activation arena can reclaim. A tail loop allocating a
fresh 32-byte string per iteration and dropping the previous one
moves the allocator's bump by **480 bytes over 2000 iterations**,
where the same run without the event reads **224,304**.

The shape is: retain each reference parameter once before the loop
header - converting the caller's borrow (event 1) into a share this
frame owns - then at each jump **retain every new value, release
every old one, and only then store**. The retain-first order is not
a nicety: a parameter passed through unchanged, which is the common
shape, would otherwise release the block it is about to keep. The
last iteration's share is never handed back, which leaks one value
per loop; that is the safe direction.

Which parameters is a question the DECLARED TYPE answers, through
`fldClass` - the same classifier that writes a block's reference map,
so the release set and every other ownership decision in this backend
agree by construction. An `Int` parameter is never retained and never
released, which is exactly why the Life probe of `MM-LIFE-2e` is
untouched by this: its board is a `Vec` behind `(-> Int Int Int)`.

What made this event unsafe for so long was never its arithmetic but
the stashes, and `MM-LIFE-2g` is what closed that. The fixture asserts
both halves, because either alone is a wrong conclusion: with the
event and without the share, the loop is still flat and a `Vec`
element pushed 300 boundaries ago reads a length of **2** - freed,
re-issued, and read back as garbage.

One further hole had to close with it, and it is the reason closure
captures are no longer uniformly unretained: a lambda captures
everything in scope, so a closure escaping the loop would hold a
parameter the next boundary releases. A capture that is a **reference
parameter of the enclosing function** now takes a share. Captures that
are `let` bindings stay unretained on purpose - nothing releases a
binding, so nothing can free one out from under a closure. The rule is
not "retain every capture" but "retain what something else may hand
back".

**Event 3 emits since 2026-08-15**
(`tests/stdlib/364-arc-frame-release.ax`, 127): a `let` binding whose
initialiser is a DIRECT CONSTRUCTION is released when its scope ends,
unless the binding can outlive the frame. The initialiser condition is
what makes the frame the owner - the block is born at count 1 and that
birth is the binding's - and the escape condition is a POSITIONAL
walk. The release is emitted at the binding's scope end, in the block
that defines its register, rather than before the function's `ret`: a
`let` inside a branch defines a register that does not dominate the
return.

**What the walk PERMITS is the load-bearing half, and each permission
is a place an ownership event already guarantees a share.** Passing
the binding to a function in STATEMENT or ARGUMENT position is a
borrow (event 1); every store a callee can make takes one - a field
store by event 5, a constructor field by event 6, a container or any
other word store through `memSetWord`, which retains by `MM-LIFE-2g`.
Sequencing, conditions and loops move no value out. A read of a
machine-scalar field answers a word. The corpus agrees by count:
`__store64` appears at exactly two store sites in
`stdlib/` + `self_host/`, one of them `memSetWord`'s own body, and no
site anywhere stashes a `strData` pointer.

**What escapes** is each place that guarantee stops: the binding being
the let's own value (nothing took a share on the way out); a LAMBDA
that mentions it (a capture takes no share, deliberately -
`MM-VAL-15`); a `set` RHS (a slot store takes none); and `cast`,
`__addr`, `strData`, `strOwner` - the four ways to get a WORD out of a
reference, which is invisible to counting by construction
(`MM-LIFE-2g`'s own stated limit). A tag the walk does not recognise
answers ESCAPE, so the surface widens by deliberate edit and never by
omission.

Three more since 2026-08-21, each a place the permission above was
taken at its word and found wanting (the QA sweep of 2026-08-18, and
the refutation pass on its fix). A REFERENCE FIELD read in value
position escapes: the walk used to say "reading a field answers the
field, never the block", and it does - but the field's share belongs
to the block, whose death hands it back, so
`(let ((b (Mk (strConcat "id-" t)))) (match b ((Mk s) s)))` returned
a string the allocator had already scrubbed. A `match` BINDER is the
same field under another name, and is asked the same question in the
match's own position - value, or, for a `set` RHS and a lambda,
any. And a CALL whose arguments mention the binding escapes when
the callee STASHES that parameter, or - in value position, for a
callee whose result is a word - may answer it (the callee's own flow
masks, "Where an argument goes" below); a callee whose result is a
counted reference answers a share of its own (event 2, shipped the
same day, below), so the argument's is untouched. A parameter or
local that merely shares a global's name is a function value
nothing signed, and every argument it is given escapes. A `let`
whose initialiser may alias the block asks the question again of its
own binder. Each of these leaks where it used to free early;
`tests/selfhost/997-let-box-value-escapes.ax` holds the eight
spellings.

Measured, all five directions. A record built, read and dropped:
20,000 calls move the bump **256 bytes where they moved 640,224**. A
record built, PASSED TO A FUNCTION and dropped: the same 256 against
640,224, which is what the positional walk buys over "field reads
only". And the three controls still grow - 160,224 bytes when the
record is returned, 291,328 when its word escapes through a `cast`,
400,224 when a lambda captures it - because a release there would free
a block something else still names.

*What it does not reach, measured rather than assumed:* the compiler's
own IR gains **zero** release sites under this event (112 before, 112
after, across 36,000 lines). 13 of 2,337 `let` bindings in
`self_host/` and `stdlib/` bind a direct construction at all, and none
survives the escape test - the corpus builds its records through `mk*`
functions that return `Int`-declared handles, which is the same reason
`MM-LIFE-2e`'s acceptance measurements cannot move. The event is for
programs, not for this one.

**Events 2 and 3 ship, with owned temporaries, since 2026-08-21 —
and the measurement that declined them for a year was measuring the
wrong thing.** The paragraph that stood here recorded the pair as
built and measured: retain every reference result before returning
it, release a `let` bound to such a call, and

| | before | after |
|---|---|---|
| release sites in the compiler's own IR | 112 | 120 |
| retain sites | 335 | 620 |
| self-compile peak RSS | 535 MiB | 535 MiB |
| self-compile wall clock | 6.3 s | 6.9 s |

— 285 retains for 8 releases and nothing reclaimed, so not shipped.
The 285 were real and the diagnosis was wrong. That version retained
EVERY tail that was not a direct construction, and a string that
`strConcat` builds is born through `__alloc` at count **0** — free-
floating, owned by nobody until a store takes the first share (the
`A1` comment in `storeCountOneAt` says so: constructors birth at 1,
raw allocation and `strWrap` stay at 0 and "the type-gated machinery
supplies their +1 elsewhere"). Retaining such a result to 1 is not a
leak, it is the adoption the allocator left for the type layer to
perform; what leaked was retaining *again* every result that already
carried a share, and what reclaimed nothing was releasing only
`let`-bound results while every argument-position temporary kept its
share forever. The pair is sound and cheap once the emitter can tell
the three cases apart, and it can, by three fixpoints over the call
graph (`inferOwnership`, `inferFlows` in codegen.ax):

<!-- doc-gate:negative-exempt narrative: a definition of the ownership lattice. The negative quantifier belongs to the BORROWED arm and has nothing to do with the test corpus. -->
- **Who owns a result.** A signed global's result is OWNED when every
  tail the body can answer is a construction, a literal (statics are
  immortal), a lambda, or a call to a reference-returning global —
  which by this very rule answers one share — and BORROWED when some
  tail is a parameter, a field read, a match binder, a raw load, or a
  raw allocation. Greatest fixpoint, so recursion through an
  owned-result function stays owned. A reference-returning global
  retains each borrowed tail **leaf** as it is emitted — per leaf,
  not at `ret`, so a body owned on one branch and borrowed on another
  retains the borrowed branch only. That is event 2, exact: every
  reference-returning global hands its caller exactly one share, and
  `strWrapOwned`'s `(cast String s)` of a raw allocation is where
  every string is adopted, once.
- **Who releases it.** Event 3 releases a `let` bound to any OWNED
  reference value — a direct construction, a call to a
  reference-returning global applied at its arity, joined over `if`,
  `cond`, `match`, `let` and a block — unless the walk below says it
  escapes. An owned value discarded in statement position is released
  on the spot. An owned temporary passed to a global whose result is a
  word or a reference is released once the call returns; one stored
  into a constructor's or struct's reference field, which retained it,
  right after the store; a `match`'s owned scrutinee after the merge
  when no binder escapes.
- **Where an argument goes.** The one thing a callee can do to an
  argument that counting does not see is ERASE its type: park it in a
  field declared `Int` through a `cast`, in a mutable slot through
  `set`, in raw memory through `__store64`, in a closure's record, or
  hand it to a callee that does one of those — `mkDiag` parks its
  message through `(cast Int msg)`. So each signed global carries a
  STASH mask (the parameters it parks that way; a `__retainref` or
  `__retain` of the parameter makes the store counted and cancels the
  bit — `memSetWord`, `mkNode`, `strSlice`) and a RET mask (the
  parameters whose reference may be part of a WORD it answers —
  through `cast`, `__addr`, `strData`, `strOwner`, or a 64-bit load
  of a header word past index 0; word 0 of a handle is a length, a
  header's own count and shape words are numbers, and a byte is
  never a pointer, so `strLen`, `strByte` and a count probe are
  scalars). Least fixpoints. Each mask has THREE forms per parameter:
  as it arrived (a typed reference, or a type variable's value), as
  a HEADER WORD (laundered through `cast`, `__addr` or arithmetic; an
  `Int` parameter is one already), and as an OWNER WORD (`strData`,
  `strOwner`, a header word past index 0: a pointer to or into the
  block the string's header owns). `__retainref` counts a typed
  arrival only; `__retain` counts what it is given — a header in
  both header forms, an owner as the owner — and a count cancels a
  park of the SAME thing: `strSlice` and `sysReadAll` retain the
  owner and park the owner, and are balanced; a retain of the owner
  licenses no park of the header, which two forms could not say, and
  a match binder's `__retainref` never stands for its scrutinee —
  a count is credited only to what the retained expression MUST be:
  the parameter, a `cast` of it, a `let` alias of one of those, and
  one parameter only, never a field, a binder or a join. A callee's
  arrival bit and its owner bit are STRONG parks (whatever it is
  given is parked, uncounted — an owner word is never what
  `__retainref` counted, so `(__store64 m 0 (strData s))` keeps a
  typed `s` alive at the call, at the loop's boundary and at its
  exit); its header bit is WEAK (parked only when a header word
  arrives, the typed arrival being counted), so `memSetWord` of a
  typed string is counted and `memSetWord` of `(cast Int s)` parks
  `s` however it arrived, and a polymorphic `put` forwarding its
  parameter to `memSetWord` inherits the weak bit. A `mut` slot's
  flow is its initialiser joined with every `set` in its scope, to a
  fixpoint, so what is parked or answered through the slot is seen;
  arithmetic and `&&`/`||` pass their position to their operands. The word-taking heads look THROUGH a
  reference-returning call or a construction to its arguments —
  `(strOwner (strSlice s 1 3))` is the owner of `s`. And the count
  pairs with the stash per PATH: every `if` arm, `cond` test, `cond`
  body, `while` condition, `while` body, `match` arm, right operand
  of `&&`/`||`, and `handle` handler is a region, and a count cancels
  a stash in its own region or one it encloses, never a sibling's,
  never the test it does not dominate — a `cond` test parks on the
  false path where its body's count never runs, and a `handle`
  naming only built-in effects never evaluates its handler. A
  temporary is not released past a callee that stashes or answers
  it, and the escape walk treats such an argument as the binding
  escaping; a `(set k v)` escapes the binding when `v` flows it or
  parks it (a lambda capturing it, a constructor's word field, a
  callee that stashes), not when `v` is a length computed from it.
  Retaining at every `cast` instead was measured and rejected:
  `strLen` and `strData` are casts, and every string in the compiler
  grew a share per read.

The self-tail-call boundary retains each new slot value, releases an
owned temporary's own share, and releases the old slot value — except
a parameter passed through AS ITSELF, the shape of every linear scan,
whose slot keeps the block it had (skipped when the name still
resolves to the slot, paid when a `let` shadows it), and except a
parameter the function PARKS a word of (its own STASH mask —
`parseModPathRest` hands `acc` to `pOk`, which stores it through a
`cast`): the slot's share is the stash's keeper, so neither the
boundary nor the return path takes it back, and the parked value is
exactly one share. One more keeps its slot's share: a parameter
the function ANSWERS A WORD OF (`(cast Int s)` as a tail — the word
has no other keeper, so the block leaks rather than dangles). A
TYPE-VARIABLE slot is retained and released BY EVIDENCE (since
2026-08-22): the entry retains it by the word the call arrived with,
the boundary retains the new value by the next iteration's word and
releases the old by the word that was current for it, and the exit
releases by the word current then — so a typed reference arriving
there is one share, exactly, and a word arriving is parked (the weak
header bit, which only a word-form argument pairs with). An `Int`
slot stays a park: what flows into it — a `let`'s word through a
helper, a parameter's header — is never released at the jump or by
the caller, the leak direction.
A function value — a bare reference to a top-level function — is
born at count 1 like a lambda: born at 0, a record it was stored in
adopted it and freed it under the frame still calling it. Read through the loop's name that the function
epilogue had already cleared, that mask was 0 at every `ret`, and the
fixed compiler's first self-build resolved no import: `pOk`'s parked
module name was freed at the parser's return.
That skip is what made the reclaiming compiler faster than the
leaking one rather than slower: measured before it, the new releases
in the scans cost 1.7 → 2.1 s. And the release walk has NO DEPTH: a
dead record is linked into a dead list through its own count word —
dead storage from that moment, and the free-list link once it files —
and the drain pops one record at a time, releases what its map names
(a child that dies joins the list, it is never recursed into), then
files it. No recursion, no auxiliary stack, one word the block already
owns. The recursive walk took the process down on a 400,000-cell list
(`tests/selfhost/700-tco.ax`); deferring the last field did the same
for a link that was not last; a 4,096-entry worklist with a recursive
fallback did the same for `(Cons String L)`, whose every level left a
string pending until the chain ended (170,000 levels). Measured now: a
1,000,000-cell list in either field order, a 400,000-level caterpillar
tree, a 20-deep full tree, dropped whole, in 0.45 s and 129 MiB
(`tests/selfhost/994-deep-release-first-field.ax`).

Measured on the compiler compiling itself, emit-llvm of
`self_host/main.ax`, same machine and load for both: **2.93 s → 1.94
s**, **314 → 248 MiB peak**, 143 → 5,817 release sites, 399 → 559
retain sites, `stage2 == stage3`. The compiler got a third faster and
a fifth smaller because it now reclaims its own strings and stops
counting what a scan passes through. Measured
on programs, bytes the arena grows per iteration over 10,000
iterations (`tests/stdlib/372-arc-owned-results.ax`, six shapes: a
record with a `fmtInt`+`strConcat` String field read through an
accessor; `(strLen (fmtInt i))`; a `let`-bound `strConcat`; a record
with a static field; `(Some (fmtInt i))` matched; a String answered
borrowed through two helpers): **0, 0, 0, 0, 0, 0**, where the
previous compiler measured 80, 80, 80, 0, 112, 0. The instrument is
the mark cell's BUMP word, not the cell's address: the cell is a
24-byte block, and once anything that size has died the allocator
hands the next cell out from a free list, so two cells' addresses
say nothing about growth under reclamation (the fixture compared
addresses until 2026-08-22, and read its zeros by the accident of
the same block coming back; by the bump word the previous compiler
reads 80, then crosses chunks).

Event 4's other end shipped with it: the TCO prologue retained every
reference parameter into its slot and the boundary kept the slots
balanced per jump, but nothing gave the last iteration's shares back,
so every self-recursive function leaked one share of each reference
parameter per call; they are released on the return path now, after
the tail leaf took its own. And a temporary handed to a self tail
call hands its share back after the boundary retain, as after any
call.

A join is owned when every arm is: a construction, a static, a call to
a reference-returning global — and a nullary constructor, `None` or
`Nil`, an immediate that costs nothing to release, so `(if c (Some x)
None)` gives its `Some` back (104 bytes per iteration before). A `set`
escapes a binding only when the binding or a word of it reaches the
slot, not a length or a sum computed from it.

What is still leaked, each the leak direction and each narrower than
before: a temporary passed to a primitive, to a `cast`, to a local
function value, or to a function whose result is a type variable
(none of those retains what it hands back); a temporary a `match`
binder escapes from; a temporary stored through `set`; a `let` whose
value is a field of the block it binds; a join of an owned temporary
with a BORROWED arm (a parameter, a field) stored into a field — the
field retains, and the owned arm's birth share has no path back; a
polymorphic self-tail-call loop matching an owned `(Some x)`; a
`let` cast to `Int` in VALUE position, kept whole (in argument
position its consumer decides, by the masks); a self-tail-calling
function's `Int` slots, and a parameter whose word it parks or
answers, which keep their slot's share; blocks above the 64 KiB pool
ceiling, never filed; and the free list's order, which a rebuild of
a 1,000,000-cell list scrambles a little more per generation. Closed
since the ledger was written: a closure record carries a reference
map for the captures it retained (the reference-class parameters),
so its death hands them back, and a lambda captures only the names
its body mentions — every name in scope was captured before, and a
closure per loop iteration chained each to the one before it through
a parameter it never used; a lambda handed to a self tail call is an
owned temporary at the boundary; a `handle` as a reference-returning
tail retains once. A function whose result is a
type variable retains nothing on return, so a `let` bound to
`(vecGet v i)` is never released — the container convention this
compiler is written in stays where it was.

**The blocker was two numbers, and it is solved.** Probed
2026-08-15, before: a `String` whose header count reads 0, pushed into
a `Vec` and interned into an `Intern`, read **0 after both** - the
containers took no share, because they store through `memSetWord` and
the checker sees a machine word. The same string stored into a struct
field read **0** through a field declared `Int` and **1** through a
field declared `String`. The declared type was the entire difference,
because `fldClass` is what decides whether a site emits a retain -
and `ASTNode` declares all ten of its fields `Int`, so every
reference this compiler holds in its own data structures was in the
first column.

What that cost is worth writing out, because the balance argument for
event 4 is seductive. Entry retains a reference parameter and the
boundary releases it, which is balanced *for the parameter*. But the
value an iteration is about to drop reached count 1 only through that
entry retain, so the boundary release takes it to 0 and files the
block - and if any iteration stashed it where counting could not
follow, that stash became a pointer into a block on a size-class free
list, which `axiom_alloc` pops before bumping. The next allocation of
that size hands the same bytes to someone else. Under-reclaiming
leaks; this frees early, and the two are not symmetric.

**MM-LIFE-2g (H, 2026-08-15). The invisible-store rule.** A store that
erases a value's type **SHALL** take a share of it. There are exactly
two such places in this implementation, and both are a `cast Int`
inside a polymorphic function:

- `Mem.memSetWord`, which every container and every raw word store
  goes through;
- the AST's `mkNode`/`mkNodeAt`, whose three payload words are
  `ASTNode`'s `Int`-declared fields.

The share is taken by **`__retainref`**, `__retain`'s type-directed
twin and the only primitive whose signature is polymorphic on purpose.
It retains exactly when its argument is a reference, and the call's
evidence stamp (`MM-LIFE-2d`) answers that: a constant for a known
type, a bit of the caller's own evidence word for a type variable, and
**nothing emitted at all** for an `Int`. That last case is why this is
affordable on the hottest store in the compiler - a tag, a span or a
length costs zero instructions. Measured: self-compile 1.22 s and peak
RSS 492.6 MiB, against 1.24 s and 492.4 MiB without it.

**THE HOLE, and how it was closed on 2026-08-30.** `bindLamParams`
binds a lambda parameter to a MINTED placeholder, and `evClassOf`
answers a placeholder `-1` — "says nothing", not "not a reference" — so
no `__retainref` was emitted at all for a parameter that is one. The
share was not taken, and a parked reference sat in its container
uncounted.

That was **observable, and a use-after-free**. The paragraph that stood
here until 2026-08-30 said the opposite — that nothing releases a
closure's argument, so an uncounted park is kept alive by the very leak
`MM-LIFE-2c`'s event-5b note calls open, and "the two cancel". That
reasoning covers only the release a *closure call* would emit. **Event
5 is a release from a different frame that never consulted the
closure**, and it is enough on its own. Measured at `07ee175`, three
programs differing in one ingredient each, `strByte` of the recorded
value, at `--opt 0` through `--opt 3` alike:

| the closure parks | then | reads |
|---|---|---|
| a struct FIELD's value | the field is overwritten | **`z`** — a string allocated after |
| a fresh temporary | the field is overwritten | `a` — correct |
| a struct field's value | nothing | `a` — correct |

Both ingredients are needed and neither is exotic: the field holds the
only counted share, the closure's park takes none, and the overwrite
releases the last one while the closure's container still points at the
block. The program is a factory returning a logging closure over a
`Session` whose `name` is recorded and then reassigned — no `cast`, no
`__load64`, no header arithmetic — and `axiom check` prints `OK`.

**TWO CHANGES CLOSE IT, and they close different things.**

`checkLamAgainst` binds the type the AUTHOR WROTE rather than a
placeholder, and a `fn` whose declared result is an arrow and whose
body is a lambda now checks through it. That reaches the factory above
and nothing else, because the guard is syntactic.

**The evidence word reaches the rest.** A lifted lambda takes a hidden
`%__evwa.h` for its own argument, and the APPLICATION passes it —
`applyOneArg` emits a third operand, `emitLamDef` and `emitThunkDef`
both declare it (every code pointer a closure record can hold must take
it, whether it reads it or not), and `emitEvWordVal` turns the witness
`EV_LAMARG` into a retain under bit 0 of that word. The checker names
the one placeholder an application can witness — `curLamVar`, the
innermost lambda's own parameter — and records each application's
argument class on the `E_APP` node for `walkAppChain` to read back
beside the arguments.

The two together move **all seven** shapes measured that day, at
`--opt 0` and `--opt 3` alike:

| the shape | before | after |
|---|---|---|
| a factory's declared result — the body IS the lambda | `z` | **`a`** |
| a `let` inside the factory | `z` | **`a`** |
| an `if` in the factory | `z` | **`a`** |
| no factory at all — bound and applied in `main` | `z` | **`a`** |
| passed to a declared arrow PARAMETER | `z` | **`a`** |
| forced by a use in its own body before the park | `z` | **`a`** |
| a declared result arrow carrying a TYPE VARIABLE | `z` | **`a`** |

**THE LAST ROW WAS THE INSTRUCTIVE ONE, and it was open for a day on a
reason that turned out to be wrong.** `(:: mk (-> Int (-> a Int)))`
emits a correct chain end to end: `mk` takes `%__evw.h`, stores it in
the closure record, and the lambda loads it, shifts bit k and retains
under it. It under-retained anyway, because `a` appears only in `mk`'s
RESULT, so nothing at MK'S CALL SITE witnesses it and the caller passes
the constant `0`. The value of type `a` does not exist until the
closure is APPLIED.

The stated reason for leaving it was that a SOURCE variable cannot be
matched by name the way a minted placeholder can — "`a` may denote
other values in the same body". That conflates values with types. `a`
does denote several values inside the body: the parameter, a capture of
the same type, a temporary. But **the evidence word is a fact about a
TYPE**, and a type variable denotes one type throughout its scope: if
the application hands over a `String` for `a`, every `a` in that body
is a `String`, captures included. There is no shadowing to confuse it
with, because type variables come from the signature being checked and
expressions cannot introduce their own. So `checkLamAgainst` names a
type-variable parameter in `curLamVar` and `evClassOf` answers it
`EV_LAMARG` — the application's word beats the enclosing function's,
which is the one that arrives as 0.

Two probes hold the reasoning rather than the conclusion: a lambda
whose parameter and a CAPTURE share `a` parks both and answers
correctly, and the same factory applied at `Int` stores and reads back
`41` — evidence `0`, no retain, no count on an integer.

**THE TWO CASES THIS SECTION USED TO NAME AS OPEN WERE BOTH WRONG, and
in opposite directions.** They were written from the emitter's shape
rather than measured, and both were corrected on 2026-08-30 by probes
that should have been written first.

*The effect-operation path was never a hole.* It passes the constant
`0` to `applyOneArg`, which is what the claim was read off. But a
handler's parameter is bound to the OPERATION's declared type by
`checkHandler`, and `AX3017` refuses a type variable there, so it is
always ground: `evClassOf` answers `1` and the retain is
unconditional. Measured on a handler that parks a struct field and
lets the field be overwritten — `call @Vec$vecPush(i64 %.t2, i64 %m,
i64 1)`, the constant one, and the program answers correctly. The word
that path passes is one the handler never reads.

*The outer parameter of a curried lambda was worse than stated.* It
was called a leak. It was a **live use-after-free**: `(lambda (a b)
(vecPush log a))` read `z` where the same lambda parking `b` read `a`.
`(lambda (a b) ..)` is `(lambda (a) (lambda (b) ..))` by the parser, so
by the time the store runs `a` is a CAPTURE inside the inner lambda,
whose own word is about `b`. The word that classifies `a` is the one
the OUTER application passed, one level out — and nothing carried it.

So the evidence words travel by DEPTH. `curLamVar` is a stack rather
than a name, `evClassOf` answers `EV_LAMARG - d` for a parameter `d`
lambdas out, `collectCapNames` takes the enclosing lambdas' words into
the nested record the way it already took the enclosing function's, and
`bindCaps` shifts each one level as it binds — so every lambda's own
argument is depth 0 and no witness is renumbered after the fact.
`tests/stdlib/461-curried-closure-arg.ax` pins four depths across
two- and three-parameter lambdas; built by the compiler one commit
back it does not answer wrongly, it **exits 139**.

*The two that were left unmeasured were the same sentence wrong a
third and fourth time, and both are closed as of 2026-08-31.* They
were recorded as "the surplus arguments of a `cast` spine and the
over-applied path — both under-retain, which leaks, and neither has a
probe yet". Probed, on the shape `461` uses, against `9116167` (0.6.0)
with a compiler built from that tree: neither leaked. Both were **live
use-after-frees**, and `axiom check` printed OK on each.

| the application | 0.6.0 | now |
|---|---|---|
| `((lambda (v) (vecPush log v)) h.name)` — the control | 97, the `a` | 97 |
| `((mkParker log) h.name)` — over-applied | **122**, the `z` | 97 |
| `((cast Int (lambda (v) ..)) h.name)` — a cast spine | **122** | 97 |

122 is the first byte of the five-byte string allocated into the block
after `(set h.name ..)` released the only counted share. All three in
one process exit **139** on 0.6.0, for the reason `461`'s header gives:
uncounted parks recycle blocks into each other until a header read
lands outside the heap.

The two had different causes, which is why the fix is in two places.
The over-applied path had the class and threw it away — `walkAppChain`
records one per application node, and `emitApplyChain` passed `vecNew`
to both of its callers, so `evOperandAt` read 0 at every step;
`dispatchCall` now snapshots `spineEvs` beside the arguments, exactly
as `emitIndirectCall` already did, and `emitOverApplied` drops it by
the same arity its arguments are dropped by. The `cast` spine never
had the class at all: `checkCastForm` claims the whole spine at its
outermost node, so the intermediate application nodes never reached
the arm that stamps them, and `checkCastArgs` now stamps the surplus
ones. `tests/stdlib/462-surplus-closure-arg.ax` pins all three rows
above and `scripts/check-closure-reclaim.sh` ablates each half: the
checker half strikes out term 8 and nothing else, the emitter half
takes both callers and exits 139.

What still passes a constant `0` is the effect-operation path in
`emitApplyRegsOwned`, and that one is measured and correct — a
handler's parameter is the operation's declared type, which `AX3017`
will not let be a variable, so its store's retain is unconditional and
the word is one the handler never reads.

**WHAT THIS UNBLOCKS.** The argument half of the closure-reclamation
design — release a closure's owned argument when the application's
result class is a word — was refused because the park took no share.
It now takes one wherever the application classifies its argument, and
the `__release` probe that read **3** before reads **16** after. The
rule is therefore available for those applications, and since
2026-08-31 there is no application path left that passes a word the
checker could have supplied and did not — a release written without
consulting that word would still be the identical use-after-free in a
new place, which is why the rule is stated as consulting it rather
than as unconditional.

`tests/stdlib/460-closure-reclaim.ax` pins both halves. **Term 64** is
the parked argument surviving its application — true by accident
before, true because the park is counted now. **Term 128** is the
struct-field factory, `z` before and `a` after. Reverting
`checkLamAgainst`'s third caller strikes out term 128 and nothing else:
255 becomes 127.

The share is deliberately **unbalanced**, and cannot be otherwise:
nothing tells the unsafe layer when a word is overwritten or its block
dies. So a reference stored through either place is immortal - a
**leak**, the safe direction, and no worse than before, since a value
reachable only from `memAlloc`'d memory was never reclaimed anyway.
What it buys is that the value is no longer *invisible*, which is the
precondition every remaining ownership event was waiting on. This is
§10's unsafe layer discharging its own obligation at the two points
where the layer is actually crossed, rather than leaving it to every
caller.

*What the rule does NOT cover, stated rather than discovered:* a
program that casts a reference into an `Int`-declared field of its own
`struct` writes a word this rule never sees. `cast` is the marker for
leaving the type system, and keeping such a value alive is the
program's obligation - the same position §10 already takes for
`memAlloc`. The compiler's own instance of that shape is `mkNode`, and
it is discharged above.

Closure capture
words are stored UNRETAINED until closure records carry maps - with
the one exception event 4 required, a capture that is a reference
PARAMETER of the enclosing function, which takes a share. A retain no
walk can return is a permanent leak, and that is what those are; the
closure-outlives-frame dangle stays a recorded program obligation
beside `MM-VAL-15`'s price sentence for every other capture. **The evidence
record's two words stopped being in that sentence on 2026-08-15**,
when its map landed and its retains became legal
(`MM-LIFE-2d`, `tests/stdlib/360-arc-evidence-map.ax`). The §3.3 primitives are LEGAL, permanently -
this sentence said "through this interim", and there is no interim:
ARC is withdrawn and the arenas are the reclamation
(`MM-ALLOC-22`, `MM-LIFE-2a`). An earlier revision said the refusal
"ships with the container rung"; that was a schedule written before
the measurement, and the measurement went the other way. Composing the
two is not a temporary arrangement either, and it is guarded at the runtime: an arena reset
scrubs the slab heads first, because a release-to-zero inside an
arena extent files a block the reset would otherwise leave dangling
into re-issuable memory.

**MM-LIFE-2h (H, 2026-08-24). The array form exists, and the three
containers carry it.** `MM-LIFE-2d` above specified two forms and
shipped one: every block the allocator answered was a **leaf**, one call
site in the whole tree said otherwise (`Str`'s header, through
`memAllocMapped`), and the sentence *"the containers therefore migrate
their data buffers from `memAlloc` to an array-form allocation"* was a
plan. This rule is that migration, measured.

The array form is **bit 15** of the shape word, and it says *every
payload word `0..count-1` of this block is a handle*. It costs one bit
and no second header word: the allocator already clamped a payload past
32,767 words to the unknown-size sentinel, and the clamp now sits at
16,383. What that costs is reuse of blocks between 131 KB and 262 KB,
which read as unknown-size rather than being filed.

**The `count` is the caller's, in bits 16..62, and that is a
correction** (2026-09-03). It was read out of the allocator's word
count in bits 1..14 until then, and that field is a **size class**: the
allocator clamps it to 0 past 16,383 words precisely because it will
not pool a block that large. A container's element buffer of 131,072
bytes or more therefore announced itself as *an array of zero handles*,
and the walk released the block and none of its elements — the whole
form, silently off, above one specific size. Measured at 16,384
elements over 200 iterations: `vecNewRef` and `vecNew` both peaked at
**335,344 KiB**, identical to the kilobyte.

Bits 16..62 are the record form's reference bitmap, and the two forms
are disjoint by construction, so the field can be a bitmap for one and
a count for the other. `Mem.memMarkArray` therefore takes the element
count — `(-> Int Int Int)`, a declared break in `compat/BREAKING` —
because no spelling of a one-argument version could recover a number
the allocator had already thrown away. `Mem.memMarkLeaf` clears bits
15..62 together: a leaf that kept the count would read back as a record
whose bitmap names whichever payload words the count's set bits fall
on, which is a wild write rather than a leak.

`tests/stdlib/406-array-form-large-block.ax` is the fixture (it answers
22 against the old encoding and 31 against this one) and
`scripts/check-container-reclaim.sh`'s `big` arm is the measurement.
**What is still not reclaimed is the buffer itself**: 131,072 bytes is
past the release path's 64 KiB pool ceiling, so the block is never
filed and `big/mapped` stays linear in the iteration count at about
130 KiB a turn. The elements come back; the buffer does not.

A bitmap could not have done this job, and the number is the argument:
the record form holds **47** words, and `Intern`'s string vector is
**64 words at construction**, before a single string is interned. A
count is the only encoding that describes a buffer.

| block | shape word | means |
|---|---|---|
| `vecNewRef`'s data | `557072` | array form, size class 8 words, length 8 (`8 << 16`) |
| `vecNew`'s data | `16` | the same block, the same size, no claim about its contents |
| `internNew`'s string vector | `4227200` | array form, size class 64 words, length 64 — past the bitmap's capacity |
| a `Vec` header | `262152` | 4 words, bit 2 — the data block |
| a `Map` header | `1835024` | 8 words, bits 2/3/4 — keys, values, states |
| an `Intern` header | `327688` | 4 words, bits 0 and 2 — the `Vec` and the slot table |

`tests/stdlib/404-container-reference-maps.ax` reads all six back and
pins four more properties in the same eight-bit answer: transitive
reclaim four levels deep (vector → data block → `Str` header → its
201-byte buffer, and a 200-byte request gets that buffer back), the
same program built with `vecNew` NOT getting it back, growth handing
the abandoned block to the free list, and `vecPop` zeroing what it
vacates.

**The bit is written by the container and read only by the runtime.**
There is no `memIsArray`, and its absence is a measured result rather
than an omission. Bit 15 is unambiguous only against an allocator that
clamps the count at 16,383 words, and the seed that made this a crash
clamped at 32,767 — where the bit used to be the count's top — so under
*that* seed's runtime every block of 16,384 words or more read back as
an array of handles. `tests/stdlib/200-scale.ax` builds a `Map` of
262,144 slots, whose value array passes that line, and `mapRemove`
believed the bit and released a raw integer: **SIGSEGV**, in a program
correct under the compiler this tree builds and wrong under the one that
builds this tree. `stage1` runs on the seed's runtime, so the bootstrap
ladder is exactly where it lands. (Checked 2026-09-03: the committed
seeds at `09f3eb4` clamp at 16,383 and carry
`%aform = and i64 %shw, 32768`, so today's seed agrees with today's
compiler. The rule outlives that particular seed — a reader would be
sound only by accident of what is in `bootstrap/`, and `stdlib/Mem.ax`
cannot see what that is.) Each container therefore carries a flag word
of its own
— `Vec` word 3, `Map` word 6 — written by the same code that reads it,
with no encoding to disagree about. That is why a `Map` header is eight
words for the six it holds.

**Two obligations come with the form, and both are the user's.** First,
words past `len` **MUST** be zero: the walk releases the whole block's
words, because the block knows its size and nothing else, so a stale
handle above the waterline has its share spent while the caller that
was handed it still holds one — a use-after-free, not a leak. `vecPop`
and `mapRemove` zero what they vacate for that reason. Second, a buffer
that is COPIED — a `Vec` doubling, a `Map` rehashing — moves its
elements' shares rather than duplicating them, so the abandoned block
**MUST** be marked a leaf (`Mem.memMarkLeaf`) before it is released, or
every element it held is freed twice.

**MM-LIFE-2i (H, 2026-08-24). A bounded live set has bounded memory,
and it did not before.** This is `MM-LIFE-2h`'s acceptance property and
the one a long-running process actually needs: not that a container can
be freed, but that a program which never frees one and never resets the
arena holds flat memory while its contents turn over completely.

Two shapes, measured on darwin-aarch64 at 20,000, 200,000 and 2,000,000
iterations — a hundredfold, so a plateau is told apart from a slope:

| shape | live set | 20k | 200k | 2M | ablated twin at 200k |
|---|---|---|---|---|---|
| a 256-entry window, insert and evict | 256 entries | 1,392 | 1,392 | 1,392 KiB | 34,368 KiB — no eviction |
| 64 fixed keys, values replaced | 64 entries | 1,328 | 1,328 | 1,344 KiB | 16,976 KiB — leaf values |

`scripts/check-steady-state.sh`. The ablated twins are mandatory rather
than decorative: a flat line also reads flat when the measurement is
broken, and the aggregate's twin differs by ONE WORD (`mapNew` for
`mapNewRefVals`) and prints the same answer, so the two arms are the
same work and differ only in what they hand back.

**That gate found a defect the container gate could not.** `mapNeedsGrow`
reads `used`, and `used` counts tombstones, so a table under
insert-and-remove churn reached the load factor with a live set that had
not moved, and `mapInsert` doubled the table for entries that did not
exist: a 256-entry window over 200,000 inserts climbed to roughly
524,288 slots and 10 MB. A **bounded live set with unbounded memory** —
exactly what this rule refuses — with every other gate in the tree green
across it, `check-container-reclaim.sh` included, because that one frees
its containers whole and never removes an entry from one. `mapRehashCap`
now rehashes at the SAME capacity when the live entries would sit at a
quarter load or less, which drops every tombstone and grows nothing:
10,048 → 1,392 KiB.

**MM-LIFE-2d (W 2026-08-24, abandoned in place —
see `MM-LIFE-2a`; what already emits is recorded below and stays).
The reference map.** Release at count
zero must release the dead block's own reference fields, and nothing at
runtime can name them: a word carries no tag (`MM-VAL-2`), a struct
block carries no header at all (`MM-VAL-10`), and assuming otherwise is
how `ArenaCompact` corrupted `scanDecls` (`I2`). The header's word −1
therefore **SHALL** hold a **shape word**, written once at allocation
by the allocation site, in one of two forms and carrying the block's
word count in both:

- **record form** — an inline reference bitmap plus the word count, for
  constructor blocks, structs, closure records and evidence records,
  all of which are statically small. The form has a capacity, and the
  capacity is a stated cliff in the style of `MM-VAL-8b`: a declaration
  whose block would not fit the bitmap **MUST** be refused with a
  diagnostic, not truncated.
- **array form** — one element-pointerhood bit plus an element count,
  for the homogeneous buffers the containers and `Str` allocate, where
  a bitmap over the words would not fit and should not need to.

`memAlloc` itself **SHALL** answer a **leaf** — a shape word saying *no
reference words*, whatever is stored there later. That is the unsafe
layer staying the unsafe layer (§10): a reference kept *only* in
`memAlloc`'d memory is invisible to counting, which under ARC becomes a
program obligation where today it is merely a fact. The containers
therefore migrate their data buffers from `memAlloc` to an array-form
allocation whose element bit comes from the evidence word below — that
migration is part of `MM-LIFE-2e`'s work, not an afterthought, and it
is what makes the container claim below true rather than asserted.

The site knows the bitmap statically **except in one place**, and the
place is structural: a polymorphic field. `(Just x)` is emitted once
for every `x` (`MM-VAL-1a` — uniform representation, no
monomorphisation), there is no Hindley–Milner inference and a
signature's type variable is never solved (`MAC-INT-2`), so the site
that stores `x` cannot know whether `x` is a reference. Three designs
answer that, and this specification chooses the first:

| Design | Mechanism | Price |
|---|---|---|
| **Pointerhood evidence** | a polymorphic function receives one hidden word: bit *i* set iff type parameter *i* is instantiated at a reference type; map-writing sites consult it | one extra word on polymorphic calls; the first and only runtime type information in the language |
| Immortalise on unknown | a value stored through a variable-typed position is retained permanently | every container leaks — `Vec` and `Map` hold this compiler's every AST node, which is the workload the strategy exists to serve |
| Tag the word | reserve a bit in every value | changes `MM-VAL-3`'s arithmetic, every literal, and every syscall boundary — a different language |

Pointerhood evidence keeps `MM-VAL-1a` intact — still one emitted body
per function — and it is what gives the containers exact element maps:
a `Vec` releases its elements precisely when its evidence bit says they
are references, because its buffer's array-form shape word was written
from that bit. It is **not** trait dictionary-passing, and
`MAC-INT-4`'s warning that generated code must not assume dictionaries
exist still stands: the evidence word answers one bit per type
parameter and can call nothing. Two edges of the design are stated
rather than discovered later. **Evidence flows by capture, not by
convention**: a lambda whose body needs a bit captures its creator's
evidence word as an ordinary capture (`MM-VAL-15`). The second edge
as originally written — a thunk built over a polymorphic function
*bakes its instantiation's word into the record at build time* — is
**unreachable under this type system**: a bare reference
instantiates fresh placeholders that are never solved (`MAC-INT-2`),
so every bit of that word is unknowable *by construction*, and the
implementation forwards the constant 0 from a one-word record
instead — a call through a value stays exactly two words
(`MM-VAL-18`, `tests/stdlib/354-arc-evidence.ax` pins the honest
under-reclaim). And **one word caps type parameters at 64**: a
declaration with more is refused as `AX3030`, on the merged list,
because the cap is *soundness* rather than honesty — a variable's
bit is read with a shift by its index, and a shift of 64 or more is
poison in the emitted LLVM, an arbitrary answer that under reference
maps becomes a wrong free.

Two prerequisites, in order. The **static half** is `MM-ALLOC-20` — a
checker that cannot tell `String` from `Int` cannot set a bit — and its
measured progress is quoted in `MM-LIFE-2a`. The **`Str` half** is that
a slice's byte pointer is interior to its parent's buffer (`MM-VAL-7`,
`MM-LIFE-6`), and no count reachable from the slice can free an
interior address: under this rule the byte buffer becomes a counted
block of its own, the `Str` header gains a third word naming it, and
`strSlice` retains the owner — a slice then keeps its parent alive by
arithmetic rather than by accident, and `MM-LIFE-6`'s obligation
dissolves.

*The monomorphic half holds since 2026-08-15*
(`tests/stdlib/352-arc-shape.ax`, 255, and
`tests/stdlib/353-arc-keep-shape.ax`, 13): the encoding is decided —
bit 0 the form (0 = record), bits 1..15 the padded payload word
count, bits 16..62 the record form's reference bitmap over block
words, uniform block-relative indexing so the walk is form-blind (a
constructor cell's writer simply never sets bit 0, the tag). Bit 63
is the i64 sign bit, reserved so every shape constant the compiler
emits is non-negative — which sets the record capacity at **47
payload words**, refused past the cliff as `AX3029` at the
declaration (`tests/diagnostics/481-record-bitmap-capacity.ax`; the
widest real declaration is the compiler's own `CG` record, 45 fields as
of 2026-08-22 — two short of the cliff, so this is a limit a reader
should treat as reachable).
Constructor and struct sites whose fields are all classifiable write
their record shape over the allocator's leaf; a `Ptr`, an alias, or
a qualified type spelling forces the whole block to the leaf —
under-reclaiming is safe, a wrong bit is a use-after-free. A
TYPE-VARIABLE field takes its bit from the evidence word since the
evidence half landed (below); with no stamp or a zero witness it
contributes no bit, which is the leaf answer for that field with
every classifiable neighbour's bit kept. `@axiom_release`'s dead path walks the map and calls
itself per set bit (its own guards cover immediates, statics, and
zero counts), then files the block. The allocator and the arena keep
helper stamp the LEAF of their dynamic size with a shared clamp: a
payload past 16383 words stores count 0, the unknown-size sentinel
release refuses to file. (16,383 and not the 32,767 this said until
2026-09-03: the ceiling moved down a bit when the array form took bit
15 on 2026-08-24, and `bootstrap/axiom-*.ll` and `codegen.ax` have both
carried `icmp ugt i64 %wcnt, 16383` since.)

*The evidence half holds since 2026-08-15*
(`tests/stdlib/354-arc-evidence.ax`, 255): a function whose
signature puts a type variable in a PARAM position takes one hidden
trailing `i64` — the register and its symbol-table name both
contain a dot no Axiom identifier can spell, so collision with user
code is impossible by construction and no reserved name exists. The
checker stamps every reference to a polymorphic declaration with
per-variable witness codes (constant 0, constant 1, or *bit k of
the caller's own word*), MEETING over every occurrence — any
disagreement, cast-rooted argument, or unclassifiable witness
collapses to 0, because first-occurrence-wins was a wrong-free
generator on programs the checker accepts. A PLACEHOLDER occurrence
says nothing and is the meet's identity (since 2026-08-22): inside
`(fn (singleton x) (PCons x (PNil)))` the `(PNil)` argument's `(PL
_t)` met x's bit k as "a scalar" and collapsed the site to 0, so the
cell stored x uncounted with no map bit while the flow model trusted
the store (event 6), and the caller released the temporary under it
— inert while nothing released, a use-after-free once events 2/3
shipped. Codegen passes the word
at every direct call (presence signature-driven, value
stamp-driven), lambdas capture it as an ordinary capture, a
self-tail-call recomputes it into a slot beside the parameters',
and construction sites read variable-field bits out of it at run
time. Signatures whose every variable is return-only take no word —
the hottest accessors (`memGetWord`, `vecGet`, `nodeA/B/C`) are
exempt outright. Thunks forward the constant 0 (see the unreachable
baking edge above). `AX3030` holds the 64-variable cliff
(`tests/diagnostics/482-evidence-word-capacity.ax`); the widest
signature in this repository declares 4.

*The `Str` half holds since 2026-08-15*
(`tests/stdlib/357-str-owner.ax`, 63): the header's third word names
the owning block, `strAlloc` and every `strSlice` take a share, and
a literal's zero says its loader-resident bytes are nobody's to
free.

*And its consumer landed the same day* (`tests/stdlib/359-arc-str-bytes.ax`,
63): the header is now allocated **mapped**, one bit, naming word 2,
so a header whose count reaches zero releases its owner and the
owner's count reaches zero in turn. Word 1 is deliberately not
mapped — for a slice it is an INTERIOR address, and no count
reachable from a slice may free one. A thousand build-and-drop
iterations of `(MkBox (strDup <48 bytes>))` move the allocator's
bump by **384 bytes**; without the bit the same run reads **80,304**,
which is 80 bytes an iteration — exactly the payload block and its
header. The compiler's own output is unchanged, byte for byte, and
its self-compile time (1.18 s) and peak RSS (484.3 MiB) are the same
to the digit either way.

The stamping needed **no new primitive**, which is a property worth
recording rather than a coincidence: the shape word is an ordinary
word at `h - 8` and the encoding is arithmetic, so `Mem.memAllocMapped`
is six operations over `__load64`/`__store64`. `stdlib/` is compiled
by the committed seed, and a standard library that spells a primitive
the seed does not know cannot be built at all until the seed moves —
so an implementation that stays inside the existing primitive set
costs one reseed less than the equivalent backend change, for the
same clamp. The clamp is real: the map is masked to the block's own
recorded word count and to the 47-word capacity, so a caller can mark
the wrong word of its own block — its business, exactly as
`memSetWord`'s index is — and cannot mark a word outside it, set the
form bit, or disturb the count.

*The evidence record's map holds since 2026-08-15*
(`tests/stdlib/360-arc-evidence-map.ax`, 7): two payload words, both
references — word 0 the handler value, word 1 the record this entry
displaced — so event 7's release at the pop stopped being
header-deep. Both words are now stored OWNED under event 6's rule: a
handler built AT the handle moves in, one named by a variable is
retained, and the displaced record is retained because the slot
refers to it again after the restore. A thousand handle entries each
building their own handler lambda move the bump by under 4 KiB where
they used to accumulate one closure record per entry. This is the
first record whose map made its own retains legal — the standing
rule, that a retain must be one an existing map can return, read
forwards instead of as a prohibition.

*Still P:* the array form's writers and the container buffer
migration (the `Vec`/`Map` element maps this word exists to feed),
and the CLOSURE record's map — which needs something the evidence
record did not: the evidence record's two words are references by
construction, where a closure's captures are references only if
their binders are, and codegen's symbol table records a name, a
register, a float flag and a slot kind, and no type. That is the
binder-class stamp `MM-LIFE-2c` names.

**MM-LIFE-2e (W 2026-08-24, abandoned in place —
see `MM-LIFE-2a`; what already emits is recorded below and stays).
The release path.** A bump pointer cannot reuse an
interior free. Release at zero **SHALL** hand the block — header
included — to a size-class free list that `axiom_alloc` consults before
bumping. Everything §3.1 promises survives unchanged: alignment
(`MM-ALLOC-3`), because every size class is a multiple of 16; zeroing
(`MM-ALLOC-6`), because the scrub at hand-out already covers recycled
bytes — `MM-ALLOC-5a`'s safe direction doing its job; freestanding
(`MM-ALLOC-1`), because retain, release and the free-list walk are
emitted runtime functions under the same `no-builtins` attribute
(`MM-ALLOC-8c`); and chunks are still never unmapped (`MM-ALLOC-4a`).

The explicit primitives of §3.3 do not compose with this for free. A
reset reclaims without releasing, so a compiler-emitted release after
one would walk a header the allocator has already re-issued — a write
into someone else's block.

**The refusal this paragraph ordered is retired, and its text is kept
because a dropped `MUST` that leaves no trace is a change a reader
cannot audit.** It read: *"When ARC lands, `__axiom_arena_mark`,
`__axiom_arena_reset` and `__axiom_arena_reset_keeping` **MUST** be
refused under it with a diagnostic; until it lands they remain the only
reclamation there is, and every rule in §3.3 stays load-bearing."* ARC
is not landing (`MM-LIFE-2a`, withdrawn), the three primitives are the
reclamation rather than the interim (`MM-ALLOC-22`), and the clause's
own second half turned out to be the argument against its first: they
remain the only whole-program reclamation there is, so refusing them
takes a stateless service from 608 KiB at ten thousand connections to
190,128 and the language server from 840 bytes per edit to 193,247.

What replaced the refusal is a runtime guard, and it shipped before the
decision did: an arena reset scrubs the 4,097 slab heads first, because
a release-to-zero inside an arena extent files a block the reset would
otherwise leave dangling into re-issuable memory. That is the
composition hazard paid for at run time instead of forbidden at compile
time, and `MM-LIFE-2a` prices what it costs — 4,097 stores per reset,
measured by nothing.

**The acceptance measurement is written twice, and on 2026-08-15 both
halves were run rather than quoted.** Neither passes, and the reason
is the same one in both — which is what made it a prerequisite rather
than a schedule.

*Both are KEPT as recorded numbers and neither is a blocker any more.*
They were the gate on ARC's arrival and ARC is withdrawn
(`MM-LIFE-2a`), so nothing is waiting on them. They are kept because
they are measurements and this document does not delete those, and
because the second of them is now evidence for the opposite conclusion:
the LSP figure below is half of `MM-ALLOC-22`'s case for the arena.
§9.1 records what they measure now.

*The unmanaged column* of `scripts/measure-memory-baseline.sh` **MUST**
go flat with no bracket in the source. It reads **17,456 KiB at 2000
generations — 8 KiB per generation**, and it is still linear: 162,576
KiB at 20,000. It has not gone flat.

**The reason this paragraph gave for that is falsified, and the number
it quoted was already stale when it was falsified.** It read, of the
probe `scripts/measure-memory-baseline.sh` emits: *"It reads
**33,568 KiB at 2000 generations — 16 KiB per generation**, unchanged.
It cannot move under this strategy as the probe is written: `advance` is
declared `(-> Int Int Int)` and the board it carries is a `Vec`, whose
handle is an `Int` in every signature `stdlib/Vec.ax` has. A
type-directed ownership event can never fire on it. The measurement is
not failing because the events are missing; it is unreachable until
container handles carry a type the checker can see."*

Container handles carry that type now. `stdlib/Vec.ax` declares
`(Vec a)`; the probe's `advance` is declared `(-> (Vec Int) Int
(Vec Int))`, its `step` `(-> (Vec Int) (Vec Int))`, its board a
`(Vec Int)` the checker can see end to end. **The column did not move.**
Measured 2026-09-02 on both sides of that port — the pre-port tree in a
worktree at its own last commit, the post-port tree with the same script
— the two runs agree row for row, peak RSS in KiB:

| generations | 10 | 80 | 500 | 2000 | 20,000 |
|---|---|---|---|---|---|
| handle is `Int` | 1424 | 1984 | 5360 | 17,456 | 162,576 |
| handle is `(Vec Int)` | 1424 | 1984 | 5360 | 17,456 | 162,576 |

The emitted IR says why in one line: the typed probe contains **no
`__retainref` and no `__releaseref` call at all**. Typing the handle
makes the container *visible* to the checker without making it
*reclaimable* — the same distinction `MM-LIFE-2g` records for
`ASTNode`'s ten `Int` fields, reached here from the opposite direction.
So the precondition this paragraph named was real and is now met, and it
was not the binding one: what is missing is a whole-program ownership
event, and `MM-LIFE-2a` withdrew the strategy that would have emitted
one. The `MUST` stands, unmet, with its excuse gone.

(The 33,568 KiB figure was stale independently of the port: the pre-port
tree measures 17,456 KiB too, so the halving happened earlier and under
some other change, and this paragraph carried "unchanged" past it.)

*The LSP's 200-edit session* **MUST** hold flat with the explicit
boundary removed. An earlier revision of this paragraph said that was
"exactly the ablation that gate already knows how to run" — **false,
and now corrected**: `scripts/check-lsp-selfhost.sh`'s six ablations
are LSP-correctness drills that patch `lspChar`, `lspSeverity`,
`lspSymKind` and the publish loop, and not one of them touches the
arena boundary at `lsp.ax`'s `__axiom_arena_mark` / 
`__axiom_arena_reset_keeping` pair. Run by hand, replacing the reset
with a pass-through of the same snapshot and rebuilding the server:

| server | 5 edits | 200 edits | per edit |
|---|---|---|---|
| boundary intact | 2016 KiB | 2176 KiB | **840 bytes** |
| boundary removed | 2672 KiB | 39,472 KiB | **193,247 bytes** |

(Re-run after `MM-LIFE-2g` and event 4 landed, since both change what
the compiler's frontend allocates per message. The per-edit figures
move by 0.04% and 0%: what the boundary reclaims is AST garbage, and
ARC does not reach it — `ASTNode`'s ten `Int` fields are why, and
`MM-LIFE-2g`'s share makes those words *visible* without making them
*reclaimable*.)

The gate's ceiling is 2048 KiB over those 195 edits. The
boundary-removed session misses it by a factor of eighteen, and the
per-edit figure is 230× the bracketed one. **The LSP's flatness is the
arena boundary's doing, entirely**, and what the boundary is
reclaiming is per-message AST garbage — the class `MM-LIFE-2c`'s two
probes show counting cannot see, because `ASTNode` declares all ten of
its fields `Int`.

**The consequence for the §3.3 refusal, written here as a schedule and
settled on 2026-08-24 as a withdrawal.** This paragraph said the refusal
"does not ship yet, and shipping it on schedule would be a regression",
and argued it from ONE workload: refusing `__axiom_arena_mark` and its
pair takes the language server from 840 bytes per edit to 193 KB per
edit, because nothing else reclaims what it reclaims. The argument was
right and it was too narrow — one long-lived program reads as a special
case, and a special case is what a schedule survives.

It has a second workload now and a larger one. A pre-forked server's
request handler, bracketed by the same pair, is **100× at a thousand
connections and 313× at ten thousand** — 192 KiB against 19,136 and 608
against 190,128 — gated with a negative probe in `scripts/check-net.sh`
and stated as a rule in `MM-ALLOC-22`. That is not a program with an
unusual memory profile; it is the shape the project has committed to as
its target. The refusal is not deferred to a later rung. It is
withdrawn, with the strategy that ordered it.

What the rest of this paragraph recorded about the acceptance
measurements is kept, because the blocked-on story is still the true
account of why the events never reached the compiler's own data.

What the measurements were gated on was recorded here as the
container-and-AST typing campaign, and **that was superseded the same
day**: the declared type is discarded in exactly two places, both a
`cast Int` inside a polymorphic function, and `MM-LIFE-2g` closes them
with `__retainref` — so the campaign was never the prerequisite. What
remains between here and the acceptance measurements is not the
ownership events: `MM-LIFE-2c`'s events 2 and 3 shipped 2026-08-21
(`tests/stdlib/372-arc-owned-results.ax`), and both measurements are
still blocked on what blocked them above — the compiler's own containers
and AST declare their handles `Int`, so no type-directed ownership event
can fire on them, and neither figure moves until they carry a type the
checker can see. Recording the order that way is still the point, and
it is most of the reason the strategy is withdrawn rather than
rescheduled: twice the rung that looked next was not the one that
unblocked this and was not the one that landed either, and the thing
that finally moved the numbers was a workload the arena already served
(`MM-ALLOC-22`).

One allocation class the events of `MM-LIFE-2c` deliberately do not
reach: the emitter's own one-word cells — a `match`'s result cell, a
mixed-representation tag read (`MM-ALLOC-9`). Counting them would put a
header and a release on every `match` in the program. They **SHALL**
stop being heap allocations at all — the idiom becomes a register or an
`alloca`, amending `MM-ALLOC-9` and `I10` in the commit that lands it —
because the alternative, when §3.3 was to be refused, was a sixteen-byte
leak per `match` executed. That obligation outlived the refusal that
motivated it, and is discharged. *Held since 2026-08-15*
(`tests/stdlib/356-match-no-heap.ax`, 3): one scratch `alloca` per
function serves every merge cell, the bump pointer no longer moves
across a thousand-iteration match loop, and the fall-through zero is
an explicit store rather than an inherited allocator promise.

*The mechanism holds since 2026-08-15* (`tests/stdlib/351-arc-reuse.ax`,
42): release at zero hands the block - header included - to its exact
16-byte size class (classes 16..65536; the dead block's count word
doubles as the link), and `axiom_alloc` pops before bumping, re-entering
the same `handout` scrub every landing takes - MM-ALLOC-6's zeroing on
the same path, measured by the fixture writing garbage before the
release and reading zero after the reuse. The shape word now carries
the size half MM-LIFE-2b demanded, and — since `MM-LIFE-2d`'s
monomorphic slice — the map beside it: bit 0 the form, bits 1..15 the
padded payload WORD count (the class is count >> 1, one convention at
every writer; a block files iff 0 < count <= 8192), bits 16..62 the
record form's reference bitmap. Release's class lookup reads the
count field, and the dead-path walk reads the map.

*The large-block policy landed 2026-08-15*
(`tests/stdlib/363-arc-large-block.ax`, 63), and the measurement this
rule was waiting for is a **cliff**, not a gradient. Twenty thousand
iterations of a tail loop allocating one string per iteration and
dropping the previous one, peak RSS:

| payload | ceiling 1 KiB | ceiling 64 KiB |
|---|---|---|
| 1008 B | 1,312 KiB | 1,312 KiB |
| 1024 B | **21,936 KiB** | 1,312 KiB |
| 2048 B | 41,936 KiB | 1,312 KiB |
| 8192 B | 162,560 KiB | 1,328 KiB |
| 65536 B | 321,312 KiB | 321,312 KiB |

A program whose buffers were a kilobyte and a byte reclaimed
**nothing**, and its RSS tracked the iteration count rather than the
live set — while the same program one byte smaller was flat. The 8 KiB
row is also **faster** pooled (0.27 s against 0.44 s over the same
20,000 iterations): reusing a hot block beats faulting fresh pages, so
the handout scrub is more than repaid, which is the answer to the
obvious objection that recycling a large block means re-wiping it.

The ceiling is 64 KiB rather than the 262,128 bytes the count field
can describe, and that choice is measured too: **the wider array buys
nothing.** A self-compile peaks at 534.3 MB under a 1 KiB ceiling, a
64 KiB one and a 256 KiB one alike, because nothing large *dies* in
it (the absolute figure is 393 MB since 2026-08-16, when `escBody`
stopped escaping string literals quadratically — the three ceilings
still measure alike, which is the claim) — the compiler's own
containers are `Int`-typed, so the ownership events emit around them
rather than on them. What a ceiling costs is the head array (4,097
words of BSS, 352 bytes of binary) and the per-reset scrub, and neither is
worth paying for classes no measurement reaches. The last row of the
table is the new ceiling stated as a measurement rather than a
constant: a 64 KiB payload plus its NUL plus the header lands above
it, and above the ceiling nothing is pooled.

What remains of this rule is now what will not be built rather than
what is next: blocks above 64 KiB (recorded, with the measurement that
says they are one-shot in every workload here — two source files rarely
share a size, so exact-size pooling could not reuse them anyway), and
the acceptance measurements (which would need the compiler's own
container and AST handles to carry a type the checker can see, and the
container element maps under them). The §3.3 refusal is not on that
list at all: it is withdrawn (`MM-ALLOC-22`). The
match-cell amendment is done - those cells are not allocations any more
(`MM-ALLOC-9`, `tests/stdlib/356-match-no-heap.ax`).
The free list of `MM-ALLOC-4b` still holds whole chunks, unchanged and
separate.

**MM-LIFE-2f (W 2026-08-24, abandoned in place — see `MM-LIFE-2a`; program obligation). Cycles under counting.** An
unreachable cycle is never reclaimed — `MM-LIFE-3` measures both
construction routes — and that is the cost `MM-LIFE-2a` accepts. A
program that builds a knot and needs the memory back **MUST** break the
cycle before dropping its last external reference: store a
non-reference into one edge (`(set a.next (cast Node 0))` — the word 0
is below 4096, and release skips it). Nothing checks this, which is
what *program obligation* means everywhere else in this document.

*Today:* the obligation is no longer vacuous, but it is still narrow.
Reclamation exists (`MM-LIFE-2e`'s path, `MM-LIFE-2c`'s first events),
so a knot built out of the block shapes those events release will be
leaked exactly as this rule says — and a knot built out of everything
else is leaked because nothing releases it at all, which is the older
and blunter reason. The obligation becomes load-bearing across the
board when the remaining events land.

The deferral is separable, and choosing ARC builds **toward** the
alternative rather than away from it: the reference maps of
`MM-LIFE-2d` are exactly the tracing information whose absence made the
last collector conservative and wrong (`MM-ALLOC-20`, §10). A cycle
collector beside ARC is a later decision that arrives with its hard
part already paid for.

**MM-LIFE-2 (R).** Axiom has **no tracing garbage collector**, and
`--gc` is refused by name rather than silently ignored. The retired Rust
backend had one — conservative, non-moving, with per-chunk object-start
bitmaps to resolve the interior pointers `strSlice` creates, and free-run
coalescing that took the self-hosted compiler from 402 MB to 8.7 MB. It
was not ported. Reintroducing it requires `MM-ALLOC-20`'s discrimination
just as escape analysis does, plus a decision about `strSlice`'s
interior pointers.

**MM-LIFE-3 (H, correcting the roadmap).** **Cycles in the heap graph
are constructible**, so the justification
the roadmap gave for not needing cycle
collection — "Axiom's data is immutable and inductive, so cycles are not
constructible" — is **false as written**; the roadmap has recorded the
correction since 2026-08-14. Two independent routes,
measured:

```scheme
; 1. Through the standard library, with no unsafe form at all:
(let ((v vecNew)) { (vecPush v 7) (vecPush v v) ... })   ; v contains v

; 2. Through a struct's mutable field, using `cast` to seed the knot:
(let ((a (Node 1 (cast Node 0))) (b (Node 2 (cast Node 0))))
  { (set a.next b) (set b.next a) ... })                 ; walks forever
```

The first needs nothing but `stdlib/Vec`, because a `Vec` element is an
`Int` and a `Vec` handle *is* an `Int` (`MM-ALLOC-20`).

This cost nothing while `MM-LIFE-1` reclaimed nothing, and it is
beginning to cost something now: where the ownership events do release,
an unreachable tree is reclaimed and an unreachable cycle is not, which
is the first place the two differ. It is recorded
here because it is a **precondition on every future reclamation
strategy**: a tracing collector for Axiom must trace cycles, and a
counting scheme must either carry a cycle collector or state the leak
as a cost. This rule used to end "ARC is therefore **not** a sound
choice for this language without a cycle collector beside it", and the
arbitration went the other way — `MM-LIFE-2a` prices the leak in and
`MM-LIFE-2f` states the obligation. The reversal is argued in §10
rather than hidden by rewording, because the measurement above is what
both positions stand on.

**MM-LIFE-4 (H).** What a program may assume about a value's lifetime,
stated positively:

1. A value is valid from the moment its constructor returns until the
   process exits, **or**
2. until a `__axiom_arena_reset` whose mark preceded its allocation,
   after which reading it is undefined (`MM-ALLOC-16`).

There is no third case. In particular, no value's lifetime is tied to a
lexical scope, a function activation, or a variable going out of scope.

**MM-LIFE-5 (P).** Under `MM-LIFE-2a`–`2f` a third case is added: a
value's lifetime ends when its last reference dies. `MM-LIFE-4`
**SHALL** then read "until its count reaches zero", and the compiler
**SHALL** guarantee that no reachable value is reclaimed — which is the
whole content of `MM-LIFE-2c` and `MM-LIFE-2d`. (While §3.4 was the
plan, this rule read "a value's lifetime is its arena's"; the
withdrawal note there says why it no longer is.)

**MM-LIFE-6 (H, program obligation — half discharged 2026-08-15).** A
`strSlice` result keeps its parent's byte buffer live and points into
its middle. A program that resets an arena containing the parent
invalidates every slice of it, and nothing says so. Under `MM-LIFE-2d`
this obligation dissolves: the byte buffer becomes a counted block the
slice retains, and the reset that could strand a slice is refused under
ARC anyway (`MM-LIFE-2e`). The COUNTING half is done
(`tests/stdlib/357-str-owner.ax`, 63): the buffer is named by word 2,
`strAlloc` and every `strSlice` take a share, and the arithmetic a
release rule needs is already correct in every running program. What
remains is the release side — a `Str` header is a `memAlloc` leaf, so
its death returns nothing yet — and the §3.3 refusal; both ride with
the container rung.

**MM-LIFE-7 (P, its syntax refused 2026-08-25).** **Linear types.**
`(linear T)` and `(consume e)` no longer parse. Both report `AX2004`:
`axiom check` on `(fn (main) (consume 0))` answers "`consume` parsed
and reclaimed nothing, and is now refused", a `(linear Int)`
annotation answers the same for `linear`, and each exits 1
(`reference.md`, Removed Features; `error-model.md` ERR-MEM-6).

**What was refused is the inert syntax, not the discipline, which is
why this rule keeps P.** The clauses below are still normative for a
conforming implementation and still unimplemented; `error-model.md`
ERR-MEM-6 states the same status from the other side — "`MM-LIFE-7`,
if it lands, would add two things to this model and change none of its
rules". A rule whose spelling is gone and whose obligation is not is
neither **R** nor **W**, so §9's Lifetimes row keeps `LIFE-7` under
Planned.

Until 2026-08-25 both spellings parsed and enforced nothing: a linear
value could be used twice or zero times, consumed twice, or never, and
no memory was reclaimed at any point. "Parsed only" understated one
half and overstated the other, and the record is kept below because old
source still carries both spellings:

- **`Linear T` is a real nominal barrier.** It is the type constructor
  `Linear` applied to `T`, and it is *incompatible* with `T`:
  `(fn (mk x) (takesInt x))` with `x : linear Int` is
  `AX3004 expected Int, found Linear Int`. So the wrapper already
  separates linear from non-linear values in signatures — what is
  missing is only the use counting. `Linear` has no declaration, no
  arity check and no constructors, so `(Linear)`, `(Linear Int Bool)`
  and `(linear (linear Int))` are all accepted.
- **`linear` is a keyword in type position only.** In expression
  position it is an ordinary identifier, and `(linear T)` written as
  `cast`'s type argument produces a *different*, lowercase constructor
  `linear T`, incompatible with `Linear T`.
- **`consume` is erased in the parser.** No node is built; the operand
  is returned directly, so neither the checker nor codegen ever sees a
  consume, and a diagnostic anchors at the operand rather than the form.
  It does **not** strip the `Linear` wrapper.
- **`consume` and `alloc` unconditionally win as expression heads**, so
  a program may define a function named `consume` or `alloc` and never
  be able to call it — the call site silently becomes the built-in form.
  A conforming implementation **MUST** refuse such a declaration rather
  than accept an uncallable one.

A conforming implementation **SHALL** enforce:

1. A value of linear type **MUST** be consumed **exactly once** on every
   path — using it twice is an error, and not using it is an error.
2. `(consume e)` is that use, and is a **deterministic drop point**: the
   value's storage is reclaimed there — under `MM-LIFE-2c`, a release
   emitted at the consume rather than at frame exit.
3. A linear value **moves**: handing it to a callee or into a block
   transfers ownership, so no retain/release pair is emitted on the
   hand-off.

Clause 3 read differently while §3.4 was the plan — linearity was
discharge B of `MM-ALLOC-19`, the *proof* that a tail-call arena reset
was sound. The chosen ARC needs no such proof (`MM-LIFE-2c`, event 4),
which demotes linear types from the memory model's precision mechanism
to an optimisation and a protocol checker: still worth having, no
longer load-bearing. `MM-LIFE-2a` says the same thing from the other
side — deterministic reclamation, "obtained without linear types".

*Today:* all three are unimplemented, and `;@axiom:owned(arena=frame)`
is an accepted tag with no meaning.

---

## 6. Parallelism

**MM-PAR-1 (H, its reason amended 2026-08-24; its atomics clause
withdrawn 2026-08-29; its first sentence withdrawn 2026-09-03).** Axiom
has **no language-level concurrency**: no threads, no tasks, no async,
and no scheduler. Nothing in this section is a compiler feature except
the five atomic primitives, which are stated next because the clause
that denied them was true until the day it was not.

**The first sentence is withdrawn, and the price it named is now paid
only by the programs that ask.** Since 2026-09-03 the language has one
concurrency form, `(parallel p ((a e1) (b e2)) body)`, and it is a
compiler feature: the parser desugars it into `let`s over the
`__par_spawn`/`__par_join` primitives, and codegen lowers the pair two
ways (`docs/memory-model-v2-design.md` §3.3, `docs/reference.md`'s
`parallel` section). The DEFAULT lowering is `MM-PAR-2`'s unit, a
forked child per binding with the answer crossing through one
`MAP_SHARED` page, so a program that writes `parallel` and nothing else
pays none of the two prices below - it imports nothing and every
global stays process-private (`MM-PAR-3`). The THREAD lowering, under
`axiom build --threads` or by naming `__thread_spawn`, pays both and
pays them knowingly: the program imports `pthread_create` and
`pthread_join` (and `__tlv_bootstrap` on Darwin), which is tier 3 of
`MM-FFI-1`'s table, and the eight mutable globals of the emitted
runtime take `thread_local(localexec)` - the obligation `MM-PAR-6`
states, discharged by `cgThreads` in `self_host/codegen.ax`, a scan
that answers 1 exactly for a module that spawns a thread. A program
that spawns none is byte-identical to what the compiler emitted before
the form existed, on every target: `scripts/check-thread-local.sh`
holds the OFF path, `scripts/check-parallel.sh` measures the deltas.
There is still no scheduler and no async; what a join hands back is a
word; and what a thread may capture is not yet checked - `MM-PAR-6`
below says which of its clauses hold.

**The atomics clause is withdrawn, and only that clause.** Since
2026-08-29 the emitter lowers `__atomic_load`, `__atomic_store`,
`__atomic_add`, `__atomic_cas` and `__fence` as sequentially consistent
LLVM atomics on one `i64` at a byte address — text-only, no target arm,
and freestanding on every target, which
`scripts/check-freestanding.sh` and `scripts/check-cross-targets.sh`
measure over the fixture that spells them,
`tests/stdlib/440-atomics.ax`. They are `MM-PAR-4`'s stated escape
given an instruction: a program that maps `MAP_SHARED` memory itself
now has a word it can update without a torn read. Nothing else moved.
There is still no thread for them to synchronise with, no mutable
global of the emitted runtime is touched by one, and `MM-PAR-3`'s
by-construction argument stands as written. The four that write or
order carry `Mut` (`MM-EXEC-9a`, asserted primitive by primitive in
`scripts/check-agent-policy.sh`); `__atomic_load` deliberately does
not, as `__load64` does not, and is the control that keeps the other
four discriminating. They are the first phase of `MM-PAR-6`'s
obligation being discharged; the rest of this rule — the price, and
that it is chosen against — is unchanged until that obligation is.

**The conclusion is unchanged and the argument for it was false.** It
was carried in `MM-PAR-2`'s sentence rather than here: thread creation
on macOS needs `bsdthread_register`, Mach-O has no local-exec TLS so
`__thread` lowers to `tlv_get_addr`, both live in libSystem — "and the
language has no construct that can name an external symbol
(`MM-FFI-1`)". **That last clause is no longer true.** `MM-FFI-1` was
amended when the `extern` block landed: an `extern` item makes the
emitter write a `declare`, so the language names external symbols by
design, and `rust/examples/demo/axiom-allow.txt` already enumerates
`_tlv_bootstrap` and `_tlv_atexit` — the exact machinery the old
argument said was unreachable — among the 188 a `std` link pulls in.
Threads are therefore **chosen against, not forced against**. A rule
that keeps something out of scope on a false premise is the dangerous
kind: nobody re-examines an impossibility, and this one had stopped
being one.

The conclusion stands on price, and the price is two things this
document sells elsewhere:

- **The freestanding property.** A program with no `extern` links
  **0** undefined symbols, and so does one calling a `no_std` crate; a
  `std` link is **188**, 18 of them forbidden libc names (`MM-FFI-1`'s
  table, gated by `scripts/check-ffi.sh`). Creating a thread means
  naming a libSystem symbol — `bsdthread_register`, or the
  `pthread_create` that allowlist already carries — so it puts every
  program that wants one in the third tier permanently, where
  `MM-ALLOC-1` and the whole of §3 stop being unconditional.
- **The whole of `MM-PAR-3`.** Every process-wide mutable global is
  private after `fork` **by construction**. Threads share them, so the
  five allocator words, the 4,097 size-class heads, argc/argv and every
  evidence slot would need atomics or thread-local storage — which is
  exactly `MM-PAR-6`'s obligation, and it already records that a shared
  bump pointer is the one thing this allocator's design cannot absorb.

Neither price is prohibitive by nature and neither is being paid. That
is the honest shape of a refusal: a cost named, and declined.

**MM-PAR-2 (H, amended 2026-08-24, again 2026-09-03).** The unit of
parallelism is the **process**. `stdlib/Job.ax` over
`sysSpawn`/`sysWaitPid` was the only route to it when this rule was
written, and its limit was the one this paragraph used to state:
**`Job` could not run an Axiom closure** — it execs an external program
and answers what that program wrote, so the work had to be a binary on
the filesystem.

**That limit is gone, and `Job` with it.** `stdlib/Par.ax` replaced it
at 0.7.4: the same bounded pool, the same submit-order guarantee and
the same `sysRun` error contract, built on `__proc_spawn` /
`__proc_join` — the primitives `(parallel ...)` desugars to — instead
of on `posix_spawn`. `parMapWords` runs an **Axiom closure**, and
`parRunAll` is that function over a closure which runs one argv, so the
external-program pool is now a special case of the general one rather
than the only thing on offer. `tests/stdlib/476-par-pool.ax` is the
evidence, and it was the `302-job` fixture first: the port produced its
predecessor's golden byte for byte, and then grew a fourth term the old
pool could not have run at all.

The primitive is `__proc_spawn` and not `__par_spawn` deliberately.
`__par_spawn` follows `--threads`, so `AX3064` refuses a captured
reference at it; `__proc_spawn` names the **forked** lowering, whose
isolation is `MM-PAR-3` by construction, and `capSpawnHead` exempts it
for that reason rather than as a concession to a build flag. The pool
therefore takes a caller's capture safely without the rule being
weakened — and because `AX3064` cannot see a capture through
`parMapWords`'s parameter, `scripts/check-parallel.sh` section 6b
measures the substitute directly: the module the compiler emits for the
pool is byte-identical with `--threads` and without.

`stdlib/Sys.ax`'s `sysForkProcess` is the other route, and it leaves
the child running **this** program's code. It answers the POSIX
convention on every target — 0 in the child, the child's pid in the
parent, a negative errno on failure — and one platform is normalised to
reach it: Darwin's `fork` hands the child pid to both processes and
distinguishes them in a register no primitive here reads, so one
`getpid` separates them. `tests/net/echo-server.ax` is the case that
needs it: a pre-forked pool whose workers inherit one listening socket
created before the fork and then run an Axiom request handler, driven
under CI by `scripts/check-net.sh`, with
`tests/stdlib/311-preforked-server.ax` the same shape in the stdlib
corpus. `MM-ALLOC-22`'s measurement is taken on those workers.

Why forking needs no compiler support at all is unchanged, and it is
`MM-PAR-3`. Since 2026-09-03 the emitted runtime forks too:
`@__axiom_par_spawn_proc` is what a `parallel` binding lowers to by
default - `fork` through the syscall template, the thunk run in the
child, its word written through a shared page, and `@__axiom_par_join_proc`
a `wait4` whose status is re-raised as the parent's own exit when it is
not 0 (`tests/stdlib/471-parallel-trap.ax`, 77 out of a child that
trapped). Darwin's two-register `fork` is normalised the way
`sysForkProcess` normalises it, with one `getpid`.

**MM-PAR-3 (H).** **Memory safety across processes is by construction,
not by discipline.** *Every* process-wide mutable global — the five
allocator words of `MM-ALLOC-2`, its size-class head array, the two
argument words `@__axiom_argc` and `@__axiom_argv`, and one evidence
slot per declared effect — is private after `fork` and fresh after
`exec`.

> The roadmap counted "all seven" as the five
> allocator words plus the evidence slots. Measured, the seven are the
> five plus argc/argv; evidence slots are additional, and a program with
> no declared effects has exactly seven globals and no slots. The
> conclusion is unaffected — it is *all* of them, whatever the count.

The allocator therefore needs no atomics, no lock and no thread-local
storage, and the effect slots inherit correctly for free. This is why
the process pool needed no compiler change at all — first `Job` over
`posix_spawn`, and now `Par` over the emitted runtime's own `fork`.

**The same set is what threads would have to buy, and since 2026-08-30
the emitter can spell the purchase.** Under `fork` the property is
free; under threads it is bought by making the identical globals
thread-local, one for one — the five allocator words, the size-class
array, `@__axiom_recover_top`, and one evidence slot per declared
effect. **Eight**, and the number is an enumeration of `@__axiom_` in
`self_host/codegen.ax` rather than a restatement of the sentence above,
which is how the roadmap's "all seven" came to be short by two.
`@__axiom_argc`/`@__axiom_argv` are **not** among them and the reason
is worth stating rather than leaving symmetric: they are written once
in `@main`'s prologue, before any thread can exist, and never again.
Every constant — the symbol table, `@__axiom_bt_mainaddr`, the four
trap messages — is shareable by construction.

`cgThreads` (`codegen.ax`) is the one predicate that decides, and it
answers **false for every program**: no `__thread_spawn` exists for it
to find, so the emitted module is byte-identical to what it was before
the machinery existed, on every target. That half is worth more than
the other. On Darwin a thread-local access is not an addressing mode
but an indirect call through libSystem's `__tlv_bootstrap` — measured
at **1 undefined symbol** with the flag on against **0** with it off —
and `axiom_alloc` touches four of these globals on its fast path, so a
language that made every program pay for a feature it never used would
have taken the whole tree out of `MM-FFI-1`'s tier 1. This is
`ERR-REC-6`'s shape exactly: a mechanism a program does not ask for
costs it nothing, and `scripts/check-thread-local.sh` measures that
rather than arguing it.

The storage class is `internal thread_local(localexec) global`, and
**local-exec is mandatory rather than preferred**: a bare
`thread_local` takes the general-dynamic model, which needs a dynamic
resolver, which is a dynamic link, which `scripts/check-freestanding.sh`
refuses at zero undefined symbols. With local-exec the cost is
`%fs:…@TPOFF` on linux-x86_64 (**+0 instructions**), `mrs TPIDR_EL0` on
linux-aarch64, `@TPOFF` on freebsd-x86_64. The gate requires no dynamic
resolver on those three **and** requires one to appear when
`(localexec)` is dropped, on both Linux targets — whose markers differ,
which is a fact a reader would guess wrongly: x86-64 calls
`__tls_get_addr`, AArch64 uses TLS **descriptors** and never names it,
so a check grepping for the first alone would pass an AArch64 build
that imports `__tlsdesc_resolve` through the PLT.

**MM-PAR-4 (H, with a stated escape).** **Nothing the language or the
standard library provides shares mutable memory between processes.**
Values cross a process boundary as bytes, through a file descriptor or
the filesystem, and `Par`'s determinism (`MM-PAR-5`) rests on that.

The claim is about what is *provided*, not about what is *reachable*: a
program holds raw `mmap` through `__syscallN`, so it can map a
`MAP_SHARED` region itself and share memory with a child. Nothing stops
it and nothing checks it. A program that does so leaves this section's
guarantees — the region is outside every arena (`MM-FFI-3`), the
allocator's globals still are not shared, and `MM-PAR-3`'s
by-construction safety no longer covers what it built.

**MM-PAR-5 (H).** Results **MUST** be answered in **submit order**,
always. Completion order is not exposed at all, because a pool whose
output depended on which core was free would make every byte-comparing
gate in this repository nondeterministic. Measured: eight `sleep 0.5`
children take 4.61 s at width 1 and 0.93 s at width 8, and
`tests/stdlib/476-par-pool.ax` pins ascending output with children whose
completion order is deliberately reversed.

**MM-PAR-6 (P; three of its five clauses H since 2026-09-03).** Should
a future implementation add threads on a platform that permits them,
this specification **SHALL** require: one arena per thread with no
cross-thread reference, values handed to a thread copied or moved,
results moved into the parent's arena at join, and combination in
argument order so that scheduling nondeterminism stays unobservable.
The five allocator globals **MUST** then become thread-local rather
than acquiring a lock, since a shared bump pointer is the one thing
this allocator's design cannot absorb.

*What the thread lowering of `parallel` holds, and what it does not
(`scripts/check-parallel.sh`, `scripts/check-thread-local.sh`):*

- **one arena per thread** - holds. All eight mutable globals, the five
  allocator words included, are `thread_local(localexec)` in a module
  that spawns, so a thread starts from the zeroed image and its first
  `axiom_alloc` maps a chunk of its own; no lock exists anywhere.
- **results moved into the parent's arena at join** - holds, for a
  WORD: the join hands back the thunk's `Int` through a page the
  parent mapped. A heap value cannot be a binding's answer yet
  (`AX3004` at the expression), because moving one out of the child's
  arena is the typed promotion S3/S4 of `docs/memory-model-v2-design.md`
  own.
- **combination in argument order** - holds by construction: the
  parser joins in the order written, and a child's completion order is
  not observable through the form.
- **no cross-thread reference, values copied or moved** - NOT held. A
  binding's expression may capture any name in scope, and under
  threads a captured heap value is shared with the parent, its count
  touched from two threads with no fence. The rule that refuses this
  is `MM-RGN-3` over sibling regions (the design's §3.2), which is why
  the process lowering - where the same program is safe by `MM-PAR-3`
  - is the default and threads are opt-in.

---

## 7. Foreign memory

**MM-FFI-1 (H, amended).** **Axiom has an FFI, and a program that does
not use it is unchanged.** This clause read "Axiom has no FFI" and was
marked **(R)** until the `extern` block landed; it is amended rather
than deleted, because the property it protected is still protected and
the amendment is what says how.

`foreign` remains removed and remains a reserved word reporting
`AX2004`, as does `union`; `region` returned on 2026-09-03 as
`MM-RGN-1`'s checked scope (`docs/memory-model-v2-design.md` §4, S2),
a scope the program brackets rather than the annotation this section's
history refused. It is not the FFI under a new
name: `foreign` named ONE symbol and emitted a call the emitted module
never declared, so every program using one passed `check` and died in
`opt`. The FFI is the `extern` BLOCK (docs/ffi.md), and the entire
difference is that the emitter now writes a `declare`.

The freestanding property is now **tiered rather than absolute**, and
all three tiers are measured (darwin-aarch64, `nm -u` on the linked
executable):

| program | undefined symbols | forbidden libc names |
|---|---|---|
| no `extern` | **0** | 0 |
| no `extern`, `parallel` under `--threads` (2026-09-03) | **3** on Darwin (`pthread_create`, `pthread_join`, `__tlv_bootstrap`), **2** elsewhere | 0 |
| `extern` → a `no_std` Rust crate | **0** | 0 |
| `extern` → a `std` Rust crate | 188 | 18 |

So the property that makes `MM-PAR-3`, `MM-ALLOC-1` and the whole of §3
true is **not** traded away for the FFI. It is traded away only for
`std`, only by the programs that ask for it, and only for the duration
of that link. A `no_std` crate whose `alloc` is wired to `axiom_alloc`
puts Rust's allocations INSIDE the arena, where §3 governs them.

`scripts/check-freestanding.sh` still gates the first tier, unchanged,
and still ends in the negative probe asserting `foreign` is refused as
`AX2004`. `scripts/check-ffi.sh` gates the other two, by the allowlist
`MM-FFI-5` requires.

**MM-FFI-2 (H).** Foreign *memory* nonetheless exists, because the
kernel writes into the process, and because a program can call `mmap`
itself. There are five boundaries:

| Boundary | Who owns the memory | Rules |
|---|---|---|
| `__syscall0`–`__syscall6` | the kernel writes into buffers the program allocated | the program **MUST** pass an address and a length it owns; nothing is checked |
| `argv` / `envp` | the kernel, outside every chunk | valid for the process's whole life; **MUST NOT** be freed or reset. It is **writable** — `(__store8 (strData (sysArg 0)) 0 88)` succeeds and the next read sees the change — so a program **MUST NOT** write it, but nothing stops one |
| `mmap` regions the allocator maps | the allocator | §3 |
| `mmap` regions the **program** maps through `__syscallN` | the program | outside every arena; not scrubbed, not reclaimed, not counted (`MM-FFI-3`). This is also the one route to `MM-PAR-4`'s escape |
| `(__addr "literal")` | the loader; a read-only constant | valid for the process's life; **MUST NOT** be written |

**MM-FFI-2a (H, program obligation).** `__addr` takes the address of a
literal's bytes **only when its argument is syntactically a string
literal**. For any other expression it is a silent identity
pass-through, so `(__addr s)` on a `Str`-valued variable yields the
two-word *header* address of `MM-VAL-7`, not the data pointer — a
plausible-looking call that reads the length word as text. Its declared
`String` parameter does not catch this, because `String` and `Int` are
mutually compatible (`MM-ALLOC-20`); only a `Bool` argument is refused.

**MM-FFI-3 (H).** Memory that did not come from `axiom_alloc` is
**outside the arena**: it is not scrubbed (`MM-ALLOC-6`), not reclaimed
by a reset (`MM-ALLOC-13`), and not counted by the high-water mark.
Passing such an address to `__axiom_arena_reset_keeping` as the kept
block is **undefined**: the primitive copies from it into arena memory,
which is well-defined only if the source stays readable across the
reset, and for kernel memory it does but for a reclaimed chunk's
interior it may not.

**MM-FFI-4 (H, program obligation).** `strCStr` hands a `Str`'s bytes
to a syscall without copying, relying on `MM-VAL-7`'s NUL terminator. A
program that builds a `Str` by any route other than the `Str` module —
including `__store8` into a buffer it allocated — **MUST** maintain that
terminator, or the syscall reads past the end.

**MM-FFI-5 (H, discharged).** All four minimum requirements this clause
set for a future FFI are met.

| # | Requirement | How |
|---|---|---|
| 1 | foreign memory is a distinct type from `Int` | `Foreign` is a builtin type name (`typeKeywordCanon`). `tyCompat` requires two named constructors to match BY NAME — the `Int`/`String` fiat was deleted 2026-08-15 — so `Foreign` is distinct wherever a type is compared, not only at a return. `tyIsReprScalar` adds the declared-return-vs-body case. Since 2026-08-22 `Handle` is the second builtin (`typeKeywordCanon`, `tyIsReprScalar`), distinct from both `Int` and `Foreign`, and the status of requirements 1 and 2 covers it with the OPPOSITE classification — a reference in `fldClass` and `evClassOf`, so its map bit is SET and release follows it into the foreign form (`MM-FFI-6`) |
| 2 | no arena primitive applies to it | `scalarTyName` classifies `Foreign` as class 0, so `fldClass` leaves its bit CLEAR in the reference map and `@axiom_release` never follows it. Measured on the emitted shape word for `(struct T (a : String) (b : Foreign) (c : String))`: the map is payload words `[0, 2]` — the `Foreign` is skipped, not truncated at |
| 3 | a foreign call is an inferred effect like a syscall | an `extern` item's `FnEnt` is seeded with `IO` at registration, exactly as an effect operation is seeded with its `Custom(E)`; the existing monotone fixpoint propagates it transitively. `isSyscallPrim` is untouched and neither effect walk learned a shape |
| 4 | `check-freestanding.sh` replaced by an enumerating gate | `scripts/check-ffi.sh` reads each crate's `axiom-allow.txt`. The original gate is KEPT rather than replaced, because a program with no `extern` still has to answer the strict version |

Requirement 2 is the one with teeth, and being *classifiable* is half of
it. An unknown type name answers "unclassifiable", which forces the
whole block to LEAF — so before `Foreign` was registered, every record
holding a foreign handle silently lost the reference map for all its
other fields and leaked them. Correctness and reclamation moved
together.

There is no `Slice` type and no `Outcome` type, and there was never a
need for one. A shim returning bytes, or one that can fail, needs two
words back and Axiom emits `ret i64` for everything; those shims take a
trailing out-cell and the decoding half is **generated Axiom**, not a
compiler feature. That keeps the rule the whole design rests on: only
Axiom's own emitter writes an Axiom heap block, because only it knows
this section's shape word.

**MM-FFI-6 (H). The foreign form and the `Handle`.** A Rust value the
program *owns a share of* — as opposed to a `Foreign` word it merely
holds — is a `Handle`: a counted heap block whose shape word has bit 0
set, the **foreign form**, a third form beside `MM-LIFE-2d`'s record
and array forms. Its two payload words are the address of a C
destructor `i64 (i64)` (word 0) and the Rust pointer that destructor
takes (word 1); its count word is an ordinary count, retained and
released by the same events as any block. The form has exactly one
writer in the tree, `stdlib/Ffi.ax`'s `ffiHandleNew`: `memAllocMapped`
masks its map to bits 16..62 and cannot set bit 0, and a constructor
site never does. A raw `extern` item **MUST NOT** answer `Handle`
(`AX3036`, `tcCheckExternTypes`); it answers `Foreign`, and
`ffiHandleNew` is the one door from a word to a share.

The implementation obligations:

- `Handle` **SHALL** be a reference class in every classification:
  `fldClass` answers 2 and `evClassOf` 1 (their reference classes), so a
  cell holding one maps it, a `let` of one is released at scope end, and
  it is never matched against a literal. `Foreign` stays class 0 — a
  word, never walked — which is requirement 2 of `MM-FFI-5` unchanged.
- When a foreign-form block's count reaches zero, `@axiom_release`
  (`codegen.ax`, label `foreign:`) **SHALL** read both words and, iff
  both are non-zero, store 0 into word 1 and call word 0 with the old
  word 1, **once**; then file the block by its size class like any
  other. A block of this form has no reference map and is never walked.
  A closed handle — word 1 already 0 — dies calling nothing.
- `ffiHandleClose` is the early close: it runs the destructor now,
  zeroes word 1, and answers 0; a second close is a no-op, and the
  block's own later death calls nothing. A shim borrowing a closed
  handle aborts (``axiom-ffi: `f`: handle is closed``, exit 73 — the
  FFI's own status, not `MM-EXEC-16`'s 72) rather than dereference 0.
- Re-entrancy is permitted: the destructor **MAY** call `axiom_release`
  (a Rust `Drop` returning shares the shim took under docs/ffi.md C1).
  Each invocation of `@axiom_release` keeps its dead list in a local and
  stores nothing else anywhere, so the re-entrant call is an ordinary
  one and the outer invocation's list is undisturbed.

The program obligations are docs/ffi.md C5 and C7: the destructor is
`i64 (i64)`, null-safe, and never unwinds; `#[axiom_opaque]` generates
one that is, and a hand-written one must match it.

*Evidence:* `tests/ffi/demo/060-opaque-handle.ax` — 200 `Counter`s
built and let go in a loop run the Rust `Drop` 200 times through the
handle with no close call anywhere, and one explicit `counterClose` on
a handle still held makes 201; the emitted `@axiom_release` carries the
`foreign:` arm (`grep foreign: <out>.ll` after `--emit-llvm`).
`tests/ffi/demo/410` and `420` pin the converse for `Foreign`.

---

## 8. Formal invariants

These are the guarantees a compiler author may build on. Each names what
breaks if it is violated, because that is the useful half.

| # | Invariant | Depends on | If violated |
|---|---|---|---|
| **I1** | Every value is one 64-bit word | `MM-VAL-1` | every calling convention in the emitter |
| **I2** | No word is self-describing; no heap block has a layout header | `MM-VAL-2`, `MM-VAL-6` | nothing — but assuming the *opposite* is how `ArenaCompact` corrupted `scanDecls` |
| **I3** | Every heap address handed out for a VALUE is ≥ 4096, and no immediate tag is | `MM-VAL-9` | mixed-representation `match` picks the wrong arm, silently |
| **I4** | Constructor tags are globally unique | `MM-VAL-8` | one runtime tag read cannot serve every constructor's compare |
| **I5** | Every allocation is 16-byte aligned | `MM-ALLOC-3` | unaligned `double` loads; `Str` headers straddling |
| **I6** | Memory obtained *through `axiom_alloc`* reads as zero | `MM-ALLOC-6` | `Map` reads stale occupancy; `strAlloc` loses its terminator |
| **I7** | A reset writes nothing to what it reclaims | `MM-ALLOC-14` | copy-at-boundary reads scrubbed bytes — 39,841 of 40,000 wrong |
| **I8** | Marks nest, and a mark is never reclaimed by its own reset | `MM-ALLOC-12` | a mark reset OUT OF NESTING ORDER restores a position from freed memory. **Enforced since 2026-08-31**, status 75 (`MM-ALLOC-16a`, `tests/stdlib/166-arena-bad-mark.ax`) — the first of these fifteen to move from argued to trapped. The consequence column said "a doubly-reset mark" until then, and that was the wrong shape: resetting the SAME mark twice is legal by this invariant's own first clause (the cell is never reclaimed by its own reset, so it stays readable) and is measurably harmless — the second reset finds its chunk still active and takes the equal-chunk fast path. What is not harmless is an INNER mark reset after its outer one |
| **I9** | Chunk addresses are unordered | `MM-ALLOC-5` | a backward copy across chunks corrupts |
| **I10** | The stack holds no data, only frames, `mut` cells, and the per-function merge scratch (one `alloca` whose value never outlives the merge that loads it - amended 2026-08-15 with `MM-ALLOC-9`) | `MM-ALLOC-11` | dangling values would become possible |
| **I11** | All allocator state is process-private | `MM-PAR-3` | a shared-address-space pool would need atomics |
| **I12** | Compilation is deterministic and reproducible | `MM-EXEC-13` | `check-reproducible.sh` |
| **I13** | The compiler executes no user code | `MM-EXEC-14` | the threat model |
| **I14** | The heap graph **may** contain cycles | `MM-LIFE-3` | the chosen ARC leaks them by stated cost (`MM-LIFE-2f`); any future cycle collector must trace them, with the maps `MM-LIFE-2d` specifies |
| **I15** | Nothing is reclaimed except by §3.3, by process exit, or by the ownership events that emit today | `MM-LIFE-1` | — |

**Two invariants are narrower than their one-line form**, and the
narrowing is stated here rather than left to careful reading:

- **I3** says "handed out for a value" because `(__alloc 0)` answers the
  unadvanced bump pointer, which before any chunk exists is the address
  0 (`MM-ALLOC-8b`). No *value* is ever stored there — a zero-byte
  request stores nothing — so the `< 4096` discrimination is unaffected,
  but the literal sentence "every heap address is ≥ 4096" is false.
- **I6** says "through `axiom_alloc`" because
  `__axiom_arena_reset_keeping` carves its destination directly and
  deliberately leaves it unscrubbed (`MM-ALLOC-15a`): the copy is what
  initialises it, and the padding up to the 16-byte rounding holds
  whatever was there. Memory that reaches a program by that route has
  not been zeroed.
- **I15** was written as the status quo `MM-LIFE-2a` existed to end,
  and it stopped holding in that form the day `MM-LIFE-2e`'s release
  path shipped: dead blocks do reach a size-class free list, and
  `MM-LIFE-2c`'s seven events do release. The row is amended rather
  than deleted, because what §3 may assume is still nearly all of it —
  the DEFAULT is unchanged (`MM-LIFE-1`), a value nobody releases lives
  as long as the process, and the compiler's own containers and AST
  declare their handles `Int`, so no type-directed ownership event
  fires on them. With `MM-LIFE-2a` withdrawn (§9) this is the permanent
  shape of the invariant and not a waypoint on the way to a stronger
  one.

---

## 9. Conformance summary

Ranges below EXCLUDE any rule listed in another column of the same row —
a range that swallowed a **P** or **R** rule would report the opposite of
that rule's status, which is the failure this table exists to prevent.

| Area | Holds today | Planned | Withdrawn | Refused |
|---|---|---|---|---|
| Execution | EXEC-1…6d, 8…13, 15…17 | — | — | EXEC-7, EXEC-14 |
| Representation | VAL-1…11, 14…20, VAL-22, VAL-23 | — | — | VAL-12, VAL-13 |
| Allocation | ALLOC-1…7, 8a…16b, ALLOC-22, ALLOC-23 | ALLOC-20 | ALLOC-17…19, ALLOC-21 | ALLOC-8 |
| Mutation | MUT-1…5 | — | — | MUT-6 |
| Lifetimes | LIFE-1, 3, 4, 6, 2g | LIFE-5, LIFE-7 | LIFE-2a…2f (2026-08-24, superseded by ALLOC-22) | LIFE-2 |
| Parallelism | PAR-1…5 | PAR-6 | — | — |
| Foreign | FFI-1…6 | — | — | — |

`MM-VAL-21` appears in no column: it is neither held, planned nor
refused, but **defective** — see §9.0.

**The Lifetimes row's Withdrawn column is §0.3's second kind, and the
column heading alone would misreport it.** `LIFE-2a…2f` were withdrawn
*after* most of the machinery shipped, not before it was implemented:
all seven of `LIFE-2c`'s events emit, `LIFE-2b`'s header is on both
allocation paths, `LIFE-2d`'s monomorphic, evidence and `Str` halves
hold, and `LIFE-2e`'s release path files dead blocks. None of that
comes out, `LIFE-2g` is **H** in the first column for exactly that
reason, and §9.0 carries the standing cost the half-finished state
leaves behind. Read the column as *no longer being finished*, never as
*not there*.

**Three identifiers in this document were used twice, and all three
were repaired on 2026-08-31.** A duplicate identifier is a §0.1
violation, and this section used to record two of them rather than fix
them, on the ground that "every citation in this document and in
`self_host/` resolves by number and a rename silently redirects
whichever side it does not touch". That objection is about a rename
being unmeasurable, and it stopped applying the moment the rename was
measured: citation counts, taken over `self_host/`, `stdlib/`, `tests/`
and every prose document, are what decided which side moved, and
`scripts/check-doc-drift.sh` now refuses a rule header that appears
twice at all — which is how the THIRD one was found, since this
paragraph had never noticed it.

| Was | Meaning | Cited | Now |
|---|---|---|---|
| `MM-LIFE-2e` (§5) | the ARC release path | 19 | unchanged |
| `MM-LIFE-2e` (§3.5) | `cast` degrades the evidence word | 1 | **`MM-VAL-22`** |
| `MM-LIFE-2f` (§5) | cycles under counting | 1 (plus `I14`) | unchanged |
| `MM-LIFE-2f` (§3.5) | the typed accessor is the safe vehicle | 1 | **`MM-VAL-23`** |
| `MM-ALLOC-17` (§3.4, 2026-08-14) | the implicit per-activation arena, **W** | 0 outside this file | unchanged |
| `MM-ALLOC-17` (§3.3, 2026-08-25) | a trap may abort to a mark, **H** | 1 | **`MM-ALLOC-23`** |

The rule that moved is in every case the one with the smaller footprint
AND the later arrival — the two criteria agree on all three pairs, which
is why this is a repair and not a judgement call. The §3.5 pair became
`MM-VAL-*` because both are about the evidence word and `cast`, §2's
subject, not §5's lifetimes. The Lifetimes row of the table above
therefore now means what it says, with no second reading needed.

Measured with:

```
grep -o '^\*\*\(MM\|ERR\|I\)[A-Z-]*[0-9][0-9a-z]*' docs/memory-model.md \
  | sed 's/^\*\*//' | sort | uniq -c | awk '$1>1'
```

which printed `2 MM-ALLOC-17`, `2 MM-LIFE-2e`, `2 MM-LIFE-2f` before
this change and nothing after it.

### 9.0 Defects this specification records

Each is a place where the implementation does something a reader of the
existing documentation would not predict. They are listed together
because the list, not any single entry, is the argument for gating this
document.

| Rule | Defect |
|---|---|
| `MM-ALLOC-8b` | `(__alloc 0)` returns an unadvanced bump pointer — address 0 before any chunk exists |
| `MM-VAL-4c` | `(!= NaN NaN)` is `false`; `Fmt.fmtFloat` cannot render inf or NaN |
| `MM-VAL-3b` | `INT_MIN / -1` and shifts ≥ 64 are undefined and answer differently per `--opt`. The operators are unchanged; what closed is the absence of an alternative — `stdlib/Err.ax`'s checked arithmetic, `tests/stdlib/312-checked-arithmetic.ax` |
| `MM-VAL-21` | `alloc` types as `*mut T`, which is unspellable, evaluates to 0, and still reports `#effects=Alloc`. **The population is not zero, measured 2026-08-31**: thirteen `(alloc ...)` expressions in eight corpus files across four gates (`check-diagnostics`, `check-fmt`, `check-restrictions`, `check-self-host`), plus a fourteenth hit that is not a use site at all and matters more than the thirteen — `self_host/format.ax:3629`, the FORMATTER's own printer for the form, which is a second grammar a refusal has to delete from as well. This rule's own `doc-gate:negative-exempt` comment asked for "a corpus counter, which this gate does not have yet"; the count above is that counter's first reading, and refusing the form is therefore a migration and the loss of the only cheap way to write a site-level `Alloc` witness (`tests/diagnostics/372-restrict-no-alloc.ax`'s `direct` case), not the near-zero edit `memory-model-v2-proposal.md` P1 priced |
| `MM-EXEC-9a` | effect inference is an under-approximation. Seven measured ways; **six closed** — `__alloc` and trait dispatch on 2026-08-23, `__store8`/`__store64` (`Mut`), `__argc`/`__argv` (`IO`) and the arena primitives (`Alloc`) on 2026-08-25, and constructor allocation on 2026-08-31, which stood as a decision `ERR-PROP-2` relied on until `restrict(no-alloc)` made it an unfalsifiable claim. One left: a call through a local, a parameter or an unresolved name, which sets `#effects-incomplete` rather than reporting a set that looks complete |
| `MM-LIFE-7` | `consume` and `alloc` win as expression heads, so a function of either name is definable but uncallable |
| `MM-LIFE-2j` | **RESOLVED BY REMOVAL, 0.6.0.** The rule was that a trait DEFAULT body's shape word depended on `impl` declaration order: `checkImplComplete` synthesized the default into every impl that omitted the method **without copying the body's nodes**, so one AST was checked once per implementing type and per-node stamps were last-write-wins across the monomorphizations. Measured 2026-08-25 against the compiler as shipped at 0.3.0, on the fixture `373-shared-default-binder` and the same file with its two `impl` blocks swapped: `Ident#String#ident` built its block with header `131076` and `axiom_retain(%x)` when the `Int` impl was declared first, and with header **`4`** — a LEAF — and no retain when the `String` impl was. One program, two orderings, two ownership shapes for the same monomorphization. Traits were removed in 0.6.0, and with them the only way to check one body under two type environments. Re-measured 2026-08-31 by diffing emitted IR from a last-write-wins compiler against the tree's across 278 fixtures, every `stdlib/` module and `self_host/main.ax`: byte-identical everywhere. `scripts/check-fallible-reclaim.sh` asserts that unreachability, so the rule stays listed — a future construct that re-checks a body per instantiation brings it back, and the gate is what would say so. |
| ~~`MM-EXEC-16`~~ | **CLOSED 2026-08-24.** Status **72** was division by zero here *and*, in `docs/ffi.md` C7, the exit a `no_std` crate's panic handler took — an Axiom division and a Rust panic were indistinguishable to a supervisor reading a status. The FFI side moved to **73**, which `MM-EXEC-16` does not reserve, and the path is gated by `tests/ffi/demo/115-abort-status.ax`. Worth recording why it survived: all 35 FFI cases carried `; expect 0`, so the abort had never been executed by anything and any status whatever would have passed |
| ~~`MM-LIFE-2a`~~ | **CLOSED 2026-08-25** as an ungated cost; the cost itself stays, by design. Every arena reset still charges **4,097** slab-head stores on the once-per-request path, because releases file blocks into those heads and a head left dangling across a reset double-issues storage. What was the defect was that nothing measured it. `scripts/check-arena-reset-rate.sh` does: three spellings of one program one word apart put a reset at **about 1.35 µs** against a mark's few nanoseconds, a fourth binary built by deleting the `slabclear` block from the emitted IR shows the scrub is what costs it, and the emitter's own `[4097 x i64]` and loop bound are asserted with no clock in the assertion at all. It also corrected this document: the cost is **1.7–1.8%** of the 77 µs per-connection budget, not the "under one percent" estimated from a bench whose arms overlap |

Seven rows left this table on 2026-08-14, each fixed and pinned by
the fixture its rule names: `MM-ALLOC-8`'s silent duplicate symbol
(now `AX3026` at `check`), `MM-VAL-9a`'s unguarded field access (now
`AX3008` on any `data` type with a nullary constructor),
`MM-VAL-9b`'s literal-match fall-through (now `AX3005`),
`MM-MUT-1a`'s parameter/capture `set` (now `AX3012` in the checker,
where `AX4002` had been catching it after the fact), `MM-VAL-3c`'s
and `MM-VAL-4b`'s width-less type names (removed - `AX3002`; the
float spellings had the checker calling them floats while the
emitter emitted integer arithmetic), and `MM-EXEC-15a`'s `main`
reference (the table lookups now normalise the emitted symbol back
to the declared spelling, so a recursive `main` compiles and runs).
The rows are recorded here rather than silently deleted, because a
shrinking defect table is a claim, and a claim needs its evidence.

### 9.1 What is gated, and what is only written down

`check-doc-drift.sh` exists because nine claims in the normative
documents were measurably false on 2026-08-10. This section is the
equivalent honesty for this one.

| Pinned by a gate | Rules |
|---|---|
| `tests/stdlib/165-arena-keep.ax` | ALLOC-14, ALLOC-15 (overlap over 500 rounds, chunk crossing, a 2 MiB oversize block, zeroing) |
| `tests/stdlib/160-arena.ax` | ALLOC-12, ALLOC-13 (waterline, 64-byte contiguity, reuse, nesting, chunk crossing, zero-on-reuse) |
| `tests/stdlib/166-arena-bad-mark.ax` | ALLOC-16a's implementation half (2026-08-31) — an inner mark reset after its outer one traps with status 75, and the two legal shapes beside it (nested marks reset innermost-first, the same mark reset twice) stay silent, so the trap is pinned against firing on correct use as well as failing to fire on incorrect |
| `tests/stdlib/167-arena-live-handle.ax` | ALLOC-16b's implementation half (2026-08-31) — a reset of a mark that predates a live `handle` traps with status 76, beside the two legal shapes that must stay silent (a mark taken inside the extent, and a mark with no handle in scope). The recovery path is pinned by `401-recover-effect.ax` continuing to exit 71, because an abort performs this reset legitimately |
| `tests/stdlib/110-tail-loop-alloc.ax` | that a self tail call does **not** reclaim what its iteration allocated — the negative of ALLOC-19 |
| `tests/stdlib/040-mem.ax` | the `Mem` primitives over ALLOC-3, ALLOC-6 |
| `tests/stdlib/358-str-owner-shares.ax` | VAL-7's counting rule — every header that NAMES an owner holds a share of it |
| `tests/stdlib/359-arc-str-bytes.ax` | LIFE-2d's `Str` half end to end — a dead string frees its bytes, a live slice keeps its parent's |
| `tests/stdlib/360-arc-evidence-map.ax` | LIFE-2c event 6 for the evidence record — its map, its two retains, and the handler lambda reclaimed with it |
| `tests/stdlib/361-arc-field-store.ax` | LIFE-2c event 5 — a field store's retain and release, both counts measured, and `(set e.f e.f)` surviving |
| `tests/stdlib/362-arc-tail-boundary.ax` | LIFE-2c event 4 and LIFE-2g together — 480 bytes over 2000 iterations, and a stashed parameter surviving 300 boundaries |
| `tests/stdlib/363-arc-large-block.ax` | LIFE-2e's large-block policy — a 2 KiB block reused and scrubbed, class separation above 1 KiB, and the 64 KiB ceiling pinned in both directions |
| `tests/stdlib/364-arc-frame-release.ax` | LIFE-2c event 3's direct-construction subset — 640,224 bytes to 256 over 20,000 builds, with the escaping control still growing |
| `tests/stdlib/220-while-mut.ax` | MUT-1 across 1,000,000 iterations |
| `tests/stdlib/035-string-equality.ax` | VAL-7's content equality, including the Unicode and interior-NUL cases |
| `scripts/measure-memory-baseline.sh --gate` | ALLOC-16's managed contract; the unsound variant must *fail* |
| `scripts/check-freestanding.sh` | ALLOC-1, ALLOC-8c, FFI-1 |
| `scripts/check-cross-targets.sh` | that every target's allocator and syscall lowering assembles at `-O0` and `-O2` |
| `scripts/check-bootstrap.sh` | that the compiler survives compiling itself under this allocator |
| `scripts/check-reproducible.sh` | EXEC-13 |
| `tests/stdlib/476-par-pool.ax` | PAR-5 |
| `tests/selfhost/500-while-mut.ax` | MUT-1 in constant stack |
| `tests/diagnostics/465-set-on-parameter.ax`, `466-set-captured.ax` | MUT-1a — both refusals, byte-pinned in all three renderings |
| `tests/diagnostics/471-reserved-runtime-name.ax` | ALLOC-8's refusal arm (`AX3026`) |
| `tests/diagnostics/476-literal-match-fallthrough.ax` | VAL-9b |
| `tests/diagnostics/480-field-on-mixed-data.ax` + `tests/stdlib/210-struct-variants.ax` | VAL-9a — the refusal and the still-legal all-fieldful half |
| `tests/diagnostics/495-widthless-types.ax` | VAL-3c, VAL-4b — the removed names refuse |
| `tests/selfhost/371-main-recursive.ax` | EXEC-15a — 5, where the unfixed compiler exits 4 |
| `tests/stdlib/314-out-of-memory.ax` | EXEC-16's status 70 and ALLOC-7 — the sentence in `.err`, the status in `.exit`, neither checked by the other, reached deterministically at 2^47 bytes |
| `tests/stdlib/312-checked-arithmetic.ax` | VAL-3b's remedy — `addChecked`/`subChecked`/`mulChecked` at every boundary they have, byte-identical stdout at `--opt` 0, 1, 2 and 3 |
| `scripts/check-net.sh` | ALLOC-22 (a request handler scoped as an arena, 100–313× under the same binary unscoped, with the negative probe that makes the flat column mean something) and ALLOC-4b (request sizes varying across three orders of magnitude do not ratchet the watermark) |

**Incidentally covered, which is not the same as pinned.** Several rules
are *exercised* by fixtures written for another purpose, so a regression
would surface — but under a name that says nothing about the rule, which
is how a gate stops being read. `tests/stdlib/170-gc.ax` and `200-scale.ax`
allocate heavily and would notice a broken allocator without asserting
anything in §3; `320-effect-gc-roots.ax` keeps evidence records live
across allocation without exercising `MM-ALLOC-16b`'s reset; the `Vec`
fixtures build cycle-shaped structures (`MM-LIFE-3`) tens of thousands of
times without ever asking whether a cycle is constructible. Reading those
as coverage is the mistake this section exists to prevent.

**`MM-LIFE-2e`'s two acceptance measurements now measure a withdrawn
strategy**, and this section is where that has to be said, because a
criterion nobody can fail is the same drift class as a **Complete** row
with no fixture. They were the gate on ARC's arrival — the unmanaged
Life column at **33,568 KiB / 16 KiB per generation**, and the LSP's
**193,247 bytes per edit against 840** with the boundary removed — and
`MM-LIFE-2a` is withdrawn, so nothing is waiting on either. Neither is
dead weight: the LSP pair is half the evidence for `MM-ALLOC-22`, and
the Life column is still the contrast
`scripts/measure-memory-baseline.sh --gate` measures its managed variant
against. What changed is that failing them now blocks nothing, and a
number labelled *acceptance* with nothing behind the label is a sentence
this section exists to catch.

<!-- doc-gate:negative-exempt an inventory of gaps, which is the safe direction - it claims rules are UNGATED. A false version of this paragraph under-claims coverage; the defect this rule exists for over-claims it. -->
Everything else is pinned by nothing, and the probes quoted inline are
the only evidence. In this repository's terms those rules are
documentation, not specification, until a fixture exists. The
highest-value gaps, in order: `MM-VAL-9`'s 4096 boundary (a silent
wrong-arm bug if it ever moves), `MM-MUT-2`'s visibility through
aliases, `MM-EXEC-6b`'s self-TCO (which `reference.md` misattributed to
LLVM until 2026-08-14 — a fixture would keep it from drifting back),
and `MM-LIFE-3`'s cycles stated *as* a property.

**All five of `MM-EXEC-16`'s executable POSIX exit statuses are
gated**: 71 by `tests/stdlib/310-effect-unhandled.ax`, 72 by the
division fixtures, 70 by `tests/stdlib/314-out-of-memory.ax`, and — both
on 2026-08-31 — **75** by `tests/stdlib/166-arena-bad-mark.ax` and
**76** by `tests/stdlib/167-arena-live-handle.ax`, each pinning the
sentence, the status, and the legal shapes its trap must stay silent
on. This paragraph said *three* until 75 existed and *four* until 76
did; it is amended each time rather than rewritten, because the count
is the claim. The remaining row,
74, is windows-x86_64's and is gated by nothing that executes: `scripts/check-platform-constants.sh`
reads its emission, and README's *Targets* section says no runner runs
that target yet. This paragraph said 70 was
"the one no fixture can reach without exhausting memory", which was
false in the strong direction: `314` reaches it **deterministically and
without exhausting anything**, by asking for 2^60 bytes — past the user
address space on every target (2^47 was not: FreeBSD 14.4/arm64 granted
it, 2026-08-29), so the kernel refuses the mapping outright and macOS's
overcommit cannot swallow the request the way it swallows a terabyte.
The message is pinned in the case's `.err` and the status in its
`.exit`, neither checked by the other (`MM-ALLOC-7`). The sentence is
worth more than its correction, and it is corrected here rather than
quietly, because of the *shape* of the claim rather than its subject —
the last three paragraphs of this section are what that shape costs.

**This document is read by `check-doc-drift.sh`** — both specifications
joined the gate's fixed list in the commit that landed them, so every
`tests/` path named here is checked for existence (the gate's rule 4).
What was *not* swept until 2026-08-14 was the fenced code:
`verify-doc-code.py`'s balance check read five documents and neither
specification — the same drift class this repository keeps finding, a
document outside a sweep's list being invisible to it. Both specs are
in that sweep now, and the fence markers (`fragment`, `refused`,
`excerpt`) mean here what they mean everywhere else. What no gate
checks is still the prose itself: a status-row rule cannot see that a
sentence is false, which is how the README's Macros row stayed
**Complete** for a season of being wrong — the arbitration recorded in
[macro-system.md](macro-system.md)'s preamble.

<!-- doc-gate:negative-exempt this paragraph is the rule's own statement and worked example; the quoted negative is the specimen being condemned, not a claim the document makes. -->
**There is a sharper version of that, and the exit-status correction
above is an instance of it.** `check-doc-drift.sh` proves reference
INTEGRITY — every fixture a document names exists — and integrity is not
truth. Its strongest check reads a sentence, extracts a `tests/` path,
and asks the filesystem whether the file is there. A sentence asserting
that a fixture is **absent** — "70 … is the one no fixture can reach
without exhausting memory" — names no path, so there is nothing for the
gate to resolve. It is the exact dual of what the gate checks, and it is
structurally invisible to it: the sentence was false for as long as it
took a person to notice, with every gate green.

The class is much larger than the one sentence. **Every claim of the
form "no X exists", "X is the only Y", or "X cannot be reached" is
unfalsifiable by the current design** — and this repository writes them
constantly, because a specification's most useful sentences are often
about what is absent. Three were false at once on 2026-08-24 and not one
of them failed anything: this one; `error-model.md`'s `ERR-ADOPT-3`
calling `self_host/lsp.ax` "the one long-lived Axiom program v1 ships",
with a pre-forked server running under CI; and `MM-PAR-2`'s "the
language has no construct that can name an external symbol", with
`extern` blocks shipped and two `_tlv_*` symbols already enumerated in
a reviewed allowlist. A gate cannot enumerate what does not exist, so it
can check none of them, and the population only grows.

**The remedy is a documentation rule rather than a bigger gate**, and
this section proposes it: *a normative sentence asserting a negative
**MUST** name the probe that would fail if the negative became true.*
"70 is the one no fixture can reach" names nothing. "70 is unpinned, and
`tests/stdlib/314-out-of-memory.ax` is the fixture that would exist if
it were not" names a path — and once the sentence carries a path, the
gate that already exists checks it in the direction that matters: the
day the fixture lands, the sentence claiming it cannot exist is standing
next to it, and rule 4 resolves the name that proves the sentence wrong.
That converts an unfalsifiable claim into a claim about a file, which is
the only kind of claim this repository has ever managed to keep honest.
The rule is not gated: a gate for it would sweep the prose docs for
negative and uniqueness phrasings and require a `tests/` path inside the
sentence, and writing it down here is the first half of asking for
one.

---

## 10. Rationale

**Why no garbage collector.** Not because collection is wrong, but
because this language cannot currently implement one correctly: a word
is untagged, a block is unheadered, and the type system unifies `Int`
with `String` by fiat. A collector under those conditions is
conservative by necessity, and the last conservative collector here was
deleted along with the backend that emitted it. Stating `MM-ALLOC-20` as
a *prerequisite* is worth more than shipping a collector that
misidentifies a `Vec` header — which has already happened once.

**Why reference counting was chosen and then not finished.** This
paragraph and the next are kept as the record of a decision that has
since been withdrawn (`MM-LIFE-2a`, 2026-08-24), and they are worth
reading in that light rather than deleted: three of the four reasons
below are still true, and the strategy still lost. What beat it was not
a counter-argument but a workload — a stateless request handler
bracketed by an arena mark and reset, measured at 100–313× less memory
than the same binary unscoped and gated with a negative probe
(`MM-ALLOC-22`). Reason 2 below is the one that dissolved: the loop that
never returns was ARC's decisive case, and a request handler is not that
loop. It is an activation that DOES return, at a boundary the program
already knows, which is the one shape a watermark serves for free. The
counting machinery that landed stays; §9.0 records what it still costs
per reset.

An
earlier revision of this paragraph was titled *Why not reference
counting* and called ARC "unsound for Axiom as specified", because
`MM-LIFE-3` measures cycles as constructible. That argument mistook
*incomplete* for *unsound*: a counting scheme never frees a live
object; what it fails to do is free a dead knot. `MM-LIFE-2a` chooses
it anyway and prices the leak in, for four reasons, each of which is a
measurement elsewhere in this document rather than a preference:

1. **Every alternative needs `MM-ALLOC-20` just as much.** Pointer
   discrimination is the shared prerequisite of counting, tracing and
   escape analysis alike, so paying it buys progress toward all three
   and forecloses none.
2. **The loop case reclaims with no copy.** The activation that never
   returns — every pass, request and expansion this compiler runs — is
   the shape per-activation arenas cannot help and `MM-ALLOC-19`'s
   tail-call reset could serve only through a copy, a linearity proof,
   or region inference. Under counts the dead generation releases at
   the same boundary for free (`MM-LIFE-2c`, event 4), and the shared
   substructure that made the copy corrupt (`MM-ALLOC-15`) is just
   arithmetic.
3. **Reclamation is deterministic** — at the last reference's death,
   the property `consume` was reaching for, obtained without finishing
   linear types (`MM-LIFE-7`).
4. **The deferral builds its own escape hatch.** The reference maps ARC
   requires (`MM-LIFE-2d`) are exactly the tracing information whose
   absence made the last collector conservative and wrong. If the
   cycle leak ever costs more than it saves, the collector that fixes
   it arrives with its hard part already built.

The alternative the old paragraph named — making cycles unconstructible
by removing `MM-MUT-2` — remains real and remains unforeclosed; it just
stopped being the cheapest honest option.

**Why the inferred-arena model lost.** Its own argument was the
measured workload: a loop whose activation never returns, served by a
watermark at no per-object cost. But that exact shape is the one
`MM-ALLOC-17` cannot touch — nothing returns — so the design's whole
weight fell on `MM-ALLOC-19`'s tail-call reset, whose soundness
obligation could be discharged only by a copy priced at the live set
per iteration, a linearity proof requiring `MM-LIFE-7` finished, or
region inference. The copy was built, gated, and measured corrupting
the moment shared substructure entered (`MM-ALLOC-15`); counting makes
the same sharing just arithmetic, needs no region inference — the escape
walk `MM-LIFE-2c`'s events 2 and 3 do need asks only whether one release
may fire, not which arena a value belongs in — and turns
`MM-ALLOC-21`'s write barrier into an ordinary field-store event
(`MM-LIFE-2c`). And `region` stays deleted either way: an annotation
the compiler can derive is one that will eventually disagree with the
compiler, silently. *Amended 2026-09-03:* the keyword is back as
`MM-RGN-1`'s checked scope — a scope the program brackets, which is the
opposite of an annotation the compiler derives, and what this
paragraph's own verdict asked for.

**Why explicit primitives are the strategy.** This paragraph read "why
explicit primitives exist anyway", and called `MM-ALLOC-12`–`MM-ALLOC-16`
what a programmer uses *until* ARC lands. They are what a programmer
uses. `MM-ALLOC-22` is the rule and `scripts/check-net.sh` is the
measurement: a request handler scoped as an arena, 100–313× under the
same binary unscoped, with the LSP's 840 bytes per edit beside it. They
are also the machinery whose gates proved the allocator could be trusted
at all, which is why the automation was going to be built over them
rather than beside them — and the automation that was chosen ended up
refusing them (`MM-LIFE-2e`'s retired clause) rather than inserting
them, which is a fair summary of how far that plan drifted from the one
thing already known to work.

**Why the unsafe layer is named rather than hidden.** `Mem` hands out
addresses as plain `Int`s and says so in its own header: it is the layer
where the type system stops and the machine begins. A language that
pretends it has no such layer just moves it somewhere unlabelled.

**Why processes rather than threads.** The platform forbids threads in a
freestanding binary, and the constraint turned out to be a gift: it made
`MM-PAR-3` true by construction, and made the concurrency library a
library.

---

## 11. Worked examples

### 11.1 A loop with flat memory, today

The contract of `MM-ALLOC-16`, written the way a program writes it. The
bracket does not disappear later: `MM-LIFE-2a`'s ARC is withdrawn, so
nothing is going to insert these calls, and this script's *unmanaged*
column is a recorded measurement rather than an acceptance criterion
(`MM-LIFE-2e`, §9.1). What a server writes instead of this loop is
`MM-ALLOC-22`'s shape — mark, handle the request, reset — where the live
set at the boundary is empty and no copy is needed at all.

This is the "managed" variant `scripts/measure-memory-baseline.sh`
gates, verbatim in shape: mark once, then per iteration **copy up,
reset, copy down**.

```scheme
(:: copyBoard (-> (Vec Int) (Vec Int)))
(fn (copyBoard src)
  (let ((dst (vecWithCapacity 576)) (mut i 0))
    {
      (while (< i 576)
        { (vecPush dst (vecGet src i)) (set i (+ i 1)) })
      dst
    }))

(:: advance (-> (Vec Int) Int (Vec Int)))
(fn (advance b n)
  (let ((m (__axiom_arena_mark)) (mut bb b) (mut nn n))
    {
      (while (> nn 0)
        (let ((b2 (step bb)))
          (let ((up (copyBoard b2)))
            {
              (__axiom_arena_reset m)          ; `up` is now above the waterline
              (set bb (copyBoard up))          ; and survives being read — MM-ALLOC-14
              (set nn (- nn 1))
            })))
      bb
    }))
```

Flat at ~1.4 MiB from 80 through 20,000 generations. The same loop
without the bracket, at ~8 KiB per generation, forever:

| generations | unmanaged peak RSS | managed |
|---|---|---|
| 10 | 1.4 MB | ~1.4 MB |
| 80 | 2.0 MB | ~1.4 MB |
| 500 | 5.4 MB | ~1.4 MB |
| 2000 | 17.5 MB | ~1.4 MB |
| 20000 | 162.6 MB | ~1.4 MB |

The unit is **MB, not MiB**: the script reports max RSS in kibibytes and
these are that figure divided by 1000, which is what
`measure-memory-baseline.sh` prints. The gate's own ceiling is stated in
KiB (4096) and is unaffected.

One board — about 10 KiB — is live at every count. The unmanaged column
is the allocator never reclaiming; **peak memory tracks total
allocation, not reachable data**, and that is the whole reason the
memory model is the hinge of the roadmap rather than one item on a list.
(The pre-`B3` numbers, still quoted in places: 10 → 5.2 MiB, 80 → 31.8
MiB, 2000 → 744 MiB. The column above was re-measured 2026-09-02, and
the ~16 KiB per generation this section used to quote is a third stale
figure — §9.1 records the same correction and the measurement either
side of the `Vec` port that occasioned it.)

Only one of these rows is enforced: the gate checks the **managed**
variant's ceiling at N = 2000. The unmanaged column is regenerated by
nobody, because no CI job runs the script in its reporting mode.

**Why this is sound here and not in general.** The down-copy is an
ordinary allocation, so `MM-ALLOC-6` scrubs it — and `MM-ALLOC-15` says
that scrub can run over the source before the copy reads it. It does not
here for one reason only: `vecWithCapacity` makes both copies *exact*,
so the destination is the same size as the source and can never reach
past it. Change the shape — a live set larger than the iteration's
garbage, a server holding a document and answering a short request — and
the same code silently corrupts, which is what
`__axiom_arena_reset_keeping` exists to prevent. The ablated variant
(reset with no copy at all) is gated too, and **must** fail: the gate
checks that the population is *not* 5, proving the check discriminates
the unsoundness the contract exists to prevent.

### 11.2 Reading a value's representation off its type

What `MM-VAL-8` means in practice, and why it is worth knowing:

```scheme
(data Color () (Red) (Green) (Blue))          ; rep 1: values ARE tags, 0 allocations
(data Shape () (Circle Int) (Square Int))     ; rep 0: every value is a 2-word block
(data Tree  () (Leaf) (Node Tree Int Tree))   ; rep 2: (Leaf) is immediate, (Node ...) is a 4-word block
```

A `(Leaf)` costs nothing and a `(Node l v r)` costs 32 bytes. A match on
`Tree` emits the `< 4096` test of `MM-VAL-9`; a match on `Color` emits a
plain compare; a match on `Shape` emits a load of word 0. None of this
is written down in the program, and all of it follows from the
constructor list.

### 11.3 The aliasing hazard, in the smallest program that shows it

```scheme
(struct Cfg (mut verbose : Int))

(:: configure (-> Cfg Cfg))
(fn (configure c) { (set c.verbose 1) c })    ; mutates the CALLER's value

(fn (main)
  (let ((base (Cfg 0))
        (loud (configure base)))
    (- loud.verbose base.verbose)))           ; 0, not 1
```

`configure` looks like it returns a modified copy. It returns the
argument, modified — `MM-MUT-2` and `MM-MUT-4` together. The fix is a
rebuild (`(Cfg 1)`), and nothing in the language will point this out.

### 11.4 What a linear loop parameter would buy

Under the withdrawn arena model this example was load-bearing:
discharge B of `MM-ALLOC-19` replaced §11.1's copy with a proof. Under
ARC the loop reclaims without it (`MM-LIFE-2c`, event 4), and what
`MM-LIFE-7` would still buy here is thinner and still real — the
hand-off moves instead of retaining, and `consume` releases the old
board at the call rather than at the boundary:

```scheme refused
(:: advance (-> (linear Board) Int (linear Board)))
(fn (advance board n)
  (if (== n 0)
      board
      (advance (step (consume board)) (- n 1))))   ; old board provably dead
```

`consume` is the drop point; the tail call resets the arena with no
copy, because nothing can still refer to what it reclaims.

Neither spelling parses since 2026-08-25 (`MM-LIFE-7`): `linear` and
`consume` are both `AX2004`, so the block above and the one below are
refused at `check` and exit 1. They are kept because old source still
carries them, and because what they were accepted as is the record
`MM-LIFE-7` keeps. Until then the shape **compiled** — `axiom check`
reported `OK` — and behaved exactly as if `linear` and `consume` were
not written, and so did its negation: a linear value used twice,
consumed twice, or not used at all was accepted too.

```scheme refused
(:: dup (-> (linear Int) Int))
(fn (dup x) (+ (cast Int (consume (consume x))) (cast Int x)))   ; once OK
(:: drop (-> (linear Int) Int))
(fn (drop x) 0)                                                  ; once OK
```

That was `MM-LIFE-7`'s point, and it is why the syntax existing was not
evidence that the discipline did. `linear` buys nothing today — it does
not parse. What survives is the barrier under the type constructor the
keyword used to build: `(:: mk (-> (Linear Int) Int))` handing `x` to
an `Int` parameter is still `AX3004 expected Int, found Linear Int`,
and `Linear` has no declaration, no arity check and no constructors.
