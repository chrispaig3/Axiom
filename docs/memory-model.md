# The Axiom memory model

This is the specification of how an Axiom program represents,
allocates, changes and reclaims memory, and of what a compiler author
may assume while doing it.

## In brief

The page covers execution semantics, how values are laid out, the
allocator, mutation, lifetimes and reclamation, parallelism and foreign
memory. It ends with the formal invariants, a conformance summary, the
rationale and worked examples.

Read it if you work on the compiler or its runtime, write code that
crosses the foreign boundary, or want the exact meaning of a rule id
such as `MM-ALLOC-9` in a compiler message. For everyday programs,
start with [Memory](reference.md#memory) in the language reference.

---

## 0. How to read this document

### 0.1 Rule identifiers

Every normative statement has a stable identifier, such as `MM-VAL-4`
or `MM-ALLOC-9`. Like diagnostic codes, identifiers are never renamed
and never reused, so a test, commit message or compiler comment that
cites one keeps its meaning. A withdrawn rule keeps its number and is
marked withdrawn.

### 0.2 Conformance language

`MUST`, `MUST NOT`, `SHOULD` and `MAY` are used as in RFC 2119. They
bind two audiences, and each rule says which:

- **Implementation obligations** bind the compiler and the runtime it
  emits. A conforming implementation that breaks one is defective.
- **Program obligations** bind you, the Axiom programmer. The rule says
  whether a static check or a runtime trap enforces it, and names any
  part left unchecked. Checking one use of a primitive doesn't
  discharge the obligation for another use of it.

The disposition register is
[assurance/memory-audit.md](assurance/memory-audit.md).

### 0.3 Status markers

Axiom's docs state each claim with the observation behind it. A
specification also describes what doesn't exist yet, so every rule
carries one of these markers:

| Marker | Meaning |
|---|---|
| **H** | Holds today. The implementation conforms, and the rule names the probe or source that shows it. |
| **P** | Planned. Normative for a conforming implementation, but the current one doesn't conform. The rule says what happens *today* instead. |
| **R** | Refused. The language doesn't provide this, and the rule says why. |
| **W** | Withdrawn. The rule was normative and is no longer to be implemented. It keeps its number and its text (§0.1), and the marker names what replaced it, so citations still resolve. |

An **H** rule with no evidence is a bug in this document. A **P** rule
that doesn't say what happens today is what
[macro-system.md](macro-system.md) calls *documented-but-inert*: a
reader builds on the sentence and the compiler disagrees.

A rule can be withdrawn in two ways. Every **W** rule in §3.4 was
replaced before it was implemented, so withdrawing it changed only this
page. `MM-LIFE-2a` was *abandoned in place*: part of it is emitted
today, other rules build on that part, and withdrawing it here doesn't
remove that code. A rule withdrawn this way **MUST** state what its
landed half still costs, in §9.0 beside the defects. No plan owns that
cost any more, so otherwise nobody would be watching it.

### 0.4 Reproducing the measurements

Every probe on this page runs against the compiler in the working
tree:

```bash
axiom="$PWD/.axiom-bin/axiom"          # or your own build
"$axiom" --diagnostic-format=ai run probe.ax; echo $?
"$axiom" --diagnostic-format=ai emit-llvm probe.ax
```

A probe's answer is its **exit status**: the low 8 bits of `main`'s
result (`MM-EXEC-11`). Probes that print use `IO.println` instead.

---

## 1. Execution semantics

### 1.1 The abstract machine

**MM-EXEC-1 (H).** An Axiom program is a set of top-level declarations
and one entry point, `main`. Evaluation reduces `main`'s body. There is
no separate initialisation phase. A top-level `fn` with no parameters
is a *function*, not a constant, and every reference to it is a
call. Measured: a
zero-parameter `fn` that prints, referenced twice, prints twice.

**MM-EXEC-2 (H).** Evaluation is **strict** and **call-by-value**.
Every argument of an application is evaluated to a value before the
callee's body begins.

**MM-EXEC-3 (H).** Arguments are evaluated **left to right**. A `let`'s
bindings are evaluated **in order**, and each is in scope for the ones
after it and for the body.

```scheme
(import IO)

(:: side (-> Int Int))
;@axiom:effect(io)
(fn (side n)
  {
    (println n)
    n
  })

(:: two (-> Int Int Int))
(fn (two a b) (+ a b))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((s (two (side 1) (side 2)))  ; prints 1, then 2
        (x (side 3))                 ; prints 3
        (y (+ x 1)))                 ; x is in scope for y
    (- (+ s y) 7)))
```

```text
1
2
3
```

**MM-EXEC-4 (H).** These are the **only** non-strict positions in the
language:

| Form | Non-strict positions |
|---|---|
| `(if c t e)` | `t` and `e`: exactly one is evaluated |
| `(if t1 b1 t2 b2 ... els)` | every branch but the selected one. A variadic `if` is the nested chain, so each pair is strict in its test and non-strict in its branch |
| `(match s arms)` | every arm but the selected one |
| `(&& a b)`, `(\|\| a b)` | `b`, when `a` decides the answer |
| `(while c body)` | `body`, zero or more times |
| `(handle body effs h)` | `h`, when no operation dispatches to it |
| a macro argument | see `MAC-EXP-6`: a template that drops a parameter drops its argument unevaluated |

Everything else evaluates all of its operands, including every operator
not listed. Measured: `(&& (== 0 1) (== (side 8) 8))` prints nothing.

**MM-EXEC-5 (H).** A brace block `{ e1 e2 ... en }` evaluates its
elements in order and has the value of `en`.

**MM-EXEC-6 (H).** Application is **curried in the type system and
uncurried in the emitted call**. A direct call to a known top-level
function of arity *n* passes *n* arguments in one machine call, using
LLVM's default C convention. A syntactically saturated curried spine
such as `((add 1) 2)` is **flattened** into that one direct call, and
never builds an intermediate closure. A call *through a value* passes
one argument per call (`MM-VAL-18`).

**MM-EXEC-6a (H).** A constructor's heap block is allocated and its tag
stored **before** any field expression is evaluated. The fields are
then evaluated and stored left to right. A `match` evaluates its
scrutinee exactly once, before it tries any arm.

**MM-EXEC-6b (H).** **A self tail call runs in constant stack.** The
compiler does this itself, at every optimisation level. It promotes the
function's parameters to `alloca` slots, turns the call into stores
into them, and branches back to a loop header. It emits no `tail` or
`musttail` marker for the call, so the loop doesn't depend on LLVM.
Measured: a self-recursive loop of 5,000,000 iterations answers
correctly.

The tail positions are exactly:

- the expression itself;
- both arms of an `if`, and every branch of a variadic `if`, which is
  the nested chain;
- the last expression of a `{ }` block;
- every arm of a `match`;
- the body of a `let`, and of a `mut` binding.

A `while` body, a `handle` body and the operands of `&&` and `||` are
not tail positions. Measured: ten million iterations through each tail
position at `--opt 0`. `tests/stdlib/467-mutual-tail.ax` term 6 runs
ten million iterations through a `let` body, and
`scripts/check-tail-calls.sh` runs it at `--opt 0` under a 512 KiB
stack.

Two details make the `let` body safe as a tail position:

- Every `alloca` a function emits sits in its entry block, so a `mut`
  binding inside any loop allocates once per activation. Measured:
  5,000,000 iterations at `--opt 0`.
- The emitter resolves a call's head as a local before it considers
  the rewrite, so a local that shadows the function's own name is never
  turned into a jump. A `let` that binds the name itself is never a
  tail.

The compiler can't leave the `let` body to LLVM. `MM-LIFE-2c` event 3
releases a `let`'s owned temporary *after* the call its body makes, and
that release stops LLVM's sibling-call pass. Left to LLVM,
`(let ((s (strConcat s "x"))) (grow s (- n 1)))` would overflow the
stack 200,000 calls deep.

**MM-EXEC-6c (H).** **A mutual tail call runs in constant stack when
the prototypes match and nothing is owed after it.** The emitter marks
such a call `musttail`, LLVM's *guaranteed* tail call: `llc` lowers it
to a jump at every optimisation level, or refuses the module. The
emitter marks a call when all of the following hold (`mustTailOK` in
`self_host/codegen.ax` is the list):

- The call sits in tail position with no leaf retain owed.
- The callee is a defined function applied to exactly its arity.
- The caller is a plain `fn`. It isn't a lambda or thunk, whose
  prototypes carry the closure record, or a self-tail-call loop, whose
  retained parameter slots are released after the body.
- No `let` temporary is waiting to be released at the end of the
  scope.
- The two prototypes are identical. Every parameter is `i64`, so this
  means the same parameter count, the hidden evidence word included,
  and both return `i64`.
- No argument is an owned temporary that the caller would release
  after the call.

`tests/stdlib/467-mutual-tail.ax` runs ten million alternating calls
through `ev`/`od`, through a `let` body and a `match` arm, and around a
three-way cycle. `scripts/check-tail-calls.sh` runs these at
`--opt 0` under a 512 KiB stack, then deletes the marker from the same
IR and requires the program to die by signal.

Two shapes stay a plain `call`, and a program **MUST NOT** rely on
either for unbounded recursion:

1. **A callee of a different arity.** Under the C calling convention,
   LLVM requires a `musttail` caller and callee to have identical
   prototypes. Many of the compiler's own tail calls have this shape.
   The `tailcc` convention lifts the requirement: `llc -O0` accepts
   `musttail` between `tailcc` functions of two and three parameters
   and emits a jump (`b`/`jmp`) on all seven triples, and the darwin
   binary runs ten million such calls under 512 KiB. Adopting it would
   change the convention of every function in the module, including
   the runtime's callback trampoline and every `extern` boundary. It is
   recorded here as the measured next step, and isn't built.
2. **A call that hands over an owned temporary**, such as
   `(od (+ i 1) (strConcat s "x"))`. The caller releases the temporary
   after the callee returns (`MM-LIFE-2c` event 3). Releasing it before
   the call would free a block the callee is about to read, and moving
   the release into the callee would change the convention for every
   function.

These two shapes run in constant space only at `--opt 1` and above,
and only while the release after them is dead. That depends on LLVM's
sibling-call pass succeeding, and nothing guarantees it.

**MM-EXEC-6d (H).** Non-tail recursion is bounded by the machine stack.
An 8176 KiB stack holds **174,000–175,000** frames at `--opt 0` and
**260,000–262,000** at `--opt 1`. Beyond that, the process dies with
SIGSEGV (status 139).

> `stdlib/Mem.ax` writes its byte loops as `while`. The standard
> library must not owe its stack safety to an optimisation or to a
> call's exact shape. A `while` loop is flat by construction, and a
> mutual respelling would depend on the call's shape (`MM-EXEC-6c`).

**MM-EXEC-7 (R).** A top-level function **MUST NOT** be partially
applied. It has no closure record to hold the missing arguments. The
compiler refuses it with `AX3013`, which names the lambda that
expresses the same value:

```text
E AX3013 partial-application "partial application of `+`: it takes 2 argument(s) and 0 were supplied"
  ?"bind the missing arguments with a lambda: `(lambda (y) (f x y))` builds the value `(f x)` would mean"
```

### 1.2 Purity

**MM-EXEC-8 (H).** Axiom is not a pure language. Three constructs
perform observable effects:

1. `__syscall0`–`__syscall6`, and everything in `stdlib/Sys` built on
   them, reach the operating system.
2. `(set x v)` on a `mut` local mutates a function-local cell
   (`MM-MUT-1`).
3. `(set e.f v)` mutates a heap field, visibly through every alias of
   `e` (`MM-MUT-2`).

**MM-EXEC-9 (H).** Effects are inferred transitively, as a fixpoint
over every function body, so a syscall three calls down counts.
`axiom --diagnostic-format=ai symbols` reports them as `#effects=...`.

The fixpoint is a worklist. Round 1 is a forward pass and a reverse
pass, which also records every call edge. Later rounds re-examine only
the callers of a function whose row grew. This matters for generated
code, which often puts a helper beside each of its callers (`f2 f1 f4
f3 …`): that order defeats both passes at once, and the worklist makes
it cost about the same as the same call graph declared in order.
`scripts/check-effect-fixpoint.sh` holds the ratio between those two
orders. It also holds `symbols --calls` byte-identical across an
ablation of the frontier, because a wrong worklist shows up as a
missing effect on one row, not as a crash.

Effects don't appear in function types. `;@axiom:effect(...)` and
`;@axiom:effect(pure)` are claims, checked against the inference, and a refuted
claim is `AX3010`, an error. Claims aren't opt-in: an untagged function
claims to perform no `IO`, and a body that performs it anyway is
`AX3042`. The same holds for the three effects that refine `IO` -
`Entropy` (drawing randomness), `Spawn` (starting a binding, thread or
process) and `Block` (waiting for one, a lock or time) - and each is
asked of every declaration, so an `effect(io)` claim doesn't answer
for them. `Alloc` and `Mut` stay ambient and are never required.

**MM-EXEC-9a (H).** The inferred effect set is an under-approximation,
and this specification says so. A conforming implementation **SHOULD**
make it an over-approximation. Seven gaps were measured. Six are
closed, and one remains:

| A function that... | is inferred | why it is still open |
|---|---|---|
| calls through a local, a parameter, or an unresolved name | contributes nothing but a transparency mark | it needs the flow analysis that `MM-EXEC-9b` describes, and the language doesn't have it. The gap announces itself: the row carries `#effects-incomplete`, and an `effect(pure)` claim over it draws `AX3037`. You get a lower bound labelled as one, not a set that looks complete |

A call through an effect-transparent parameter often passes it an
argument the walk can't follow, such as a load, a call result or an
`if`. That argument sets the mark only when the position it lands in
can hold a callable value. The test is `paramCallablesOf`'s own, one
level down: an arrow, a type variable or poison can hold a callable
value, and a concrete `Int` can't. It is the argument `markEparam`
already uses for the parameter itself, applied to that parameter's own
argument positions. A value in an `Int` position can hide no effect,
because applying it is `AX3004` and the program doesn't compile.

So `vecSiftDownBy`, whose body compares two `(memGetWord ...)` results
with a `cmp` declared `(-> Int Int Int)`, carries no mark, and neither
does `vecSortBy`. That keeps `restrict(no-io)` answerable over a
function that sorts. With the mark, it would come back `AX3051`,
unanswerable.

The walk meets three shapes, and only the last one is closable:

| what the walk met | closable? |
|---|---|
| a head that isn't a name; an opaque `let`; a pattern binder; over-application; a lambda's own parameter | **no**. This is `MM-EXEC-9b`'s flow analysis, and dispatch through a capability record (`stdlib/Http.ax`'s `httpCall`, `((h.run) fd r)`) is the shape that matters |
| an unfollowable value in a position whose declared type is a type variable | **no, and correctly**: a caller may instantiate it to an arrow. `tests/selfhost/999-placeholder-under-arrow.ax`'s `twice` is `(-> (-> a a) a a)`, with the same body as the `(-> (-> Int Int) Int Int)` version in `tests/stdlib/140-function-values.ax`, and only the second one closed |
| an unfollowable value in a position whose declared type can't hold a function | **closed**. No well-typed program can put a function there: applying a nominal type is `AX3004`, and so is handing an arrow to one. This holds for both alias forms, `(type F = ...)` expanded and `(type F a = ...)` nominal |

`scripts/check-effect-argpos.sh` holds this. Its four controls are the
shapes that must keep the mark, and its ablation drops the type test
and requires the closed rows to reopen. The type test moves no
`#effects=` set and no diagnostic anywhere in the tree.

Applying a `data` or `struct` constructor of arity 1 or more adds
`Alloc`, so `restrict(no-alloc)` sees the allocation the emitted code
performs. Here `emit-llvm` puts a `call i64 @axiom_alloc(i64 16)`
inside `@mk`, and the compiler refuses the claim with `AX3049`:

```scheme refused
(data W (Wrap Int) (Empty))
;@axiom:restrict(no-alloc)
(:: mk (-> Int Int))
(fn (mk n) (match (Wrap n) ((Wrap x) x) ((Empty) 0)))

(fn (main) (mk 3))
```

`typecheck.ax`'s `ctorAllocArity` asks the same tables that
`checkSaturation` asks, `rfindCtor` for a `data` constructor and
`findStruct` for a struct, and `walkCallHead` adds `Alloc` when the
answer is above zero. Arity decides, not whether the head is a
constructor. `(Wrap n)` emits one `axiom_alloc` and `(Empty)` emits
none, because a nullary constructor is an immediate tag with no block
behind it. [reference.md](reference.md) says the same: *"every
constructor is nullary | a value **is** its tag ... nothing
allocates"*. Adding `Alloc` for `(Empty)` would refuse a `no-alloc`
claim the emitted code keeps, which is the opposite error.

Every effect row this moved gained `Alloc`, and none lost anything.
Seven `restrict(no-alloc)` claims in the tree were false and were
withdrawn at their sites, each with the reason beside it: `mkSpan` and
`mkToken` (`self_host/core.ax`), `mkDiagBase` (`self_host/diag.ax`),
`vecTry` (`stdlib/Vec.ax`), `strFind` and `strParseInt`
(`stdlib/Str.ax`), and `histFindBack` (`self_host/replhist.ax`), the
last through `strFind`'s `Some`. No `;@axiom:effect(pure)` claim in the tree
broke, since none is on a constructing function. `ERR-PROP-2` in
[error-model.md](error-model.md) relied on the old behaviour, and its probe
is what changed: a constructor function tagged `pure` now draws
`AX3010`.

The closed rows, and what each now reports:

| Row | Now |
|---|---|
| calls `__alloc` | `Alloc` |
| calls a **trait method** whose implementation does I/O. The construct was removed in 0.6.0 | the fixpoint unioned **every** implementation of the method, because the rewrite that selects one ran elsewhere and this walk couldn't say which. The effect reached the caller and its callers: definite with a single implementation, and `#effects-possible=` with more than one |
| calls `__store8`/`__store64`/`__store8v`, which write arbitrary memory | `Mut` |
| reads `__argc`/`__argv`, the process command line | `IO` |
| calls the arena primitives | `Alloc` |
| applies a `data`/`struct` **constructor** of arity >= 1 | `Alloc`. A nullary constructor stays silent, and allocates nothing to be silent about |

Most of these were the same defect: a primitive that performs
something, registered as computing. `scripts/check-agent-policy.sh`
asserts the mapping one primitive at a time. A population golden can't
hold this rule, because re-blessing it after a regression makes the
check agree with whatever the compiler now says. The script's controls
report `Unsafe` (`MM-EXEC-9c`) but not `Mut`: the raw loads `__load64`
and `__load8`, the atomic load `__atomic_load`, and
`__retain`/`__release`. `__retainref` must stay silent.

The trait-method row no longer applies. `trait` and `impl` are
`AX2004`, and an interface is a capability record: a struct holding the
functions, passed as an ordinary value. Dispatch is `((c.render) x)`, a
call through a field the walk can't resolve, so it falls under the open
row above. This checks `OK` with `AX3037` beside it, and its row reads
`#effect=pure #effects-incomplete` with no `IO`:

```scheme
(struct Logger (emit : (-> String Int)))
;@axiom:effect(pure)
(:: runIt (-> Logger String Int))
(fn (runIt l s) ((l.emit) s))
```

`__alloc`, the primitive the whole heap goes through, contributes
`Alloc`.

The store, command-line and arena rows follow the definitions already
in [reference.md](reference.md):

- `__store64` is what `(set base.field v)` lowers to, and `Mut` is
  defined by a field store being visible through every alias, where a
  `mut` local is not.
- `__argc` broadens `IO` from "reaches a `__syscallN`" to "reaches the
  outside world", which is the reading `MM-EXEC-9b` needs.
- `Alloc` is the heap-machinery effect, not strictly an allocation.
  `handle` contributes it for installing evidence, which allocates
  nothing. An arena reset ends every block since a mark, so a function
  that performs one is as far from pure as one that allocates.
  `__axiom_arena_mark` only reads the bump pointer and is
  over-approximated, as this rule's **SHOULD** asks, because a mark is
  only ever written to be paired with a reset.

`__retain` and `__release` get no `Mut`. Their writes are the runtime's
own bookkeeping, invisible to the program's meaning. Giving them `Mut`
would mark every function that touches a reference and lose the
distinctions the rest of this table draws.

The rows discriminate rather than blanket the library. `memAlloc`,
`vecPush` and `strConcat` carry `Alloc`, and the last two also carry
`Mut` because they store. `vecGet` and `strEq` carry neither.
`scripts/check-agent-policy.sh` pins the whole population against
`tests/agent/stdlib-effects.allow`.

Because `println` reaches `__store64`, two `handle` lists had to grow
when the store row closed, since `AX3011` requires such a list to be
exhaustive. One is in the fixture
`tests/stdlib/320-effect-gc-roots.ax`. The other is in a program that
`scripts/check-recover.sh` builds from a heredoc, which a sweep over
`tests/**/*.ax` can't see. A check that generates a program is a second
corpus, and an inference change has to be measured against both.

`axiom symbols` reports an effect for each of these:

```scheme
(fn (writes a)    (__store64 a 0 42)) ; writes arbitrary memory -> Mut, Unsafe
(fn (readsArgs n) (__argc))           ; reads the command line  -> IO
```

**MM-EXEC-9b (H).** What a purity claim guarantees: **a
`;@axiom:effect(pure)` claim that the checker accepted means the function's
body reaches no effectful primitive by a path the inference can
follow.** It doesn't mean the function is a mathematical function of
its arguments. It may still mutate a heap field through an alias
(`MM-MUT-2`). It may still perform anything at all through a call the
inference couldn't resolve, which is `MM-EXEC-9a`'s remaining row.
`AX3010` refuses the build only where a claim was written and refuted.
The unresolved call yields `AX3037`, which doesn't refuse it.

Writing memory and reading the command line are inferred, so a `pure`
claim over either is reported. Dispatch through an interface is not
resolvable: an interface is a capability record, so `((l.emit) s)` is a
call through a struct field, which is `MM-EXEC-9a`'s remaining row. The
`runIt` claim in `MM-EXEC-9a` checks `OK`, carries
`#effect=pure #effects-incomplete` with no `IO`, and prints at run time. That
route covers every dispatch in the language, and it is always
announced, by `#effects-incomplete` on the row and `AX3037` on the
claim.

A program that needs a real purity guarantee can't get one from this
mechanism today. An `effect(pure)` tag doesn't cover the calls in
`MM-EXEC-9a`'s remaining row.

**MM-EXEC-9c (H). `Unsafe` is every primitive that reads, writes, frees
or calls through a word the type system does not bound.** There are
thirty-six:

- `__load8`, `__store8`, `__store8v`, `__load64`, `__store64`,
  `__alloc` and `__addr`;
- `__retain` and `__release`, which write the count word below an
  arbitrary address and can file it on a free list;
- `__call_word`, which calls it;
- the four atomics, which dereference it;
- `__axiom_arena_reset` and `__axiom_arena_reset_keeping`, which rewind
  the allocator to it (`MM-ALLOC-16`);
- `__handle_new`, `__handle_get` and `__handle_free`, which take or
  answer an address their caller dereferences (`MM-PAR-8`);
- `__syscall0` to `__syscall6`, whose arguments the kernel reads and
  writes through: `read` fills the buffer it is handed, `open` reads
  the path, and `munmap` frees the range;
- the ten device primitives (`MM-FFI-8`): the eight volatile accesses
  `__vload8`…`__vstore64`, which load or store at an arbitrary word,
  and the cache operations `__arm_dc_cvac`/`__arm_dc_civac`, which
  clean or invalidate the line holding one.

`restrict(no-unsafe)` refuses each of them with `AX3049`, and `pure`
refuses them with `AX3010`. `__fence`, `__retainref` (a typed value)
and `__axiom_arena_mark` are outside the set.

Inline assembly is in the set as well: an `asm` form (`MM-FFI-9`)
lowers to a primitive of its own, and the diagnostics name it `asm`
(`tests/diagnostics/1045-inline-asm-unsafe.ax`).

`AX3073` also covers calls to precondition interfaces and casts that
forge references. `MM-EXEC-9d` defines where a declaration must state
its unsafe boundary.

Tested by `tests/diagnostics/1010-unsafe-primitives.ax` (the sixteen),
`tests/diagnostics/1080-unsafe-syscalls.ax` (the seven syscalls and the
handle table's three) and `tests/diagnostics/1020-unsafe-device-primitives.ax`
(the ten device primitives). Every row draws `AX3073` beside its
`AX3049`, except the `pure` rows, which draw `AX3010`, and the controls
(`__fence`, `__retainref`, `__axiom_arena_mark`, 1020's `fenced` and
`slot`, and 1080's tagged `declared` and its `no-unsafe` caller), which
stay silent under every rule.

**MM-EXEC-9d (H).** A declaration that performs an unsafe operation
**MUST** say `;@axiom:effect(unsafe)`. There are three unsafe
operations:

- a primitive in `MM-EXEC-9c`;
- a call to, or a reference to, a *precondition interface*: a function
  whose tags say `;@axiom:precondition(...)` as well as
  `effect(unsafe)`, because its safety depends on what its caller
  passes, such as `Mem.memGetWord`;
- a *forging cast*: `(cast T x)`, where `T` is a reference type and
  `x` isn't already a `T`. The reference types are `String`, `Vec`,
  `Handle`, a struct, a `data` type with a field, a function, a
  non-empty tuple, and a type variable, which a caller may instantiate
  at any of them.

An untagged operation is `AX3073`, even when the declaration claims
another effect, such as `effect(io)`. Under `effect(pure)` it is
`AX3010` instead, since a purity claim already answers it.

```scheme refused
(struct Hid (name : String) (n : Int))

(:: peek (-> Int Int))
(fn (peek k)
  (let ((h (cast Hid k)))
    h.n))
```

`peek`'s cast draws `AX3073`. It makes a `Hid` out of whatever word it
is given, so `(peek 7)` reads a field at address 7 and dies with
SIGSEGV.

A cast that only observes forges nothing, so these stay silent:

- a reference read as an `Int`, or a number converted to another;
- a `Foreign` read as an `Int`, or back;
- an `Int` read as a `data` type whose constructors are all nullary,
  since its values are tags;
- a value cast to the type it already has;
- an ascription that chooses the element type of a value nothing else
  in the body constrains, such as `(:: vecNew (Vec Int))`;
- a cast of a value that never returns, such as `(cast a (exit 70))`,
  the diverging spelling `AX3040` accepts.

A cast is judged once its whole body is typed, so the type a value
ends up with decides. An empty vector cast to `(Vec String)` and then
filled with `Int`s forges, wherever the push is written.

The two tags give a declaration one of two roles:

- A *trusted encapsulation* says `effect(unsafe)` alone. Its author
  vouches that every well-typed call is safe, so its `Unsafe` ends at
  the declaration: a caller's inferred row doesn't carry it, and a
  caller needs no tag. `vecPush`, `strConcat` and `mapInsert` are
  trusted.
- A *precondition interface* says `effect(unsafe)` and
  `;@axiom:precondition(...)`. The text states what a caller must make
  true. Every call is an unsafe operation in the caller, so it carries
  `Unsafe` into the caller's row. `memGetWord`, `vecGetStr`, `vecFree`
  and `strWrap` are precondition interfaces.

A precondition without `effect(unsafe)` is `AX3079`, and an empty one
is `AX3080`. `symbols` reports each role as `#unsafe=trusted` or
`#unsafe=precondition` (the text rides along as `#precondition=`), so
the trusted set of a program is one `grep`.

`restrict(no-unsafe)` refuses a body that performs an unsafe operation
or reaches one through a callee that is not a trusted encapsulation,
and names the path. The walk stops at a trusted declaration. A forging
cast in a callee that says nothing is found after every body is typed,
because the checker learns a cast's source type only there; the answer
does not depend on which is declared first.

The compiler checks where the boundary is declared and that a
precondition states something. It does not prove that a trusted body
keeps its promise, or that a caller meets a precondition. Those are
review obligations, and the trusted set is the list to review
([assurance/trusted-components.md](assurance/trusted-components.md)).

Tested by `tests/diagnostics/1040-forging-cast.ax` to
`tests/diagnostics/1043-precondition-tag.ax`. The accepted wrapper in
`tests/selfhost/1010-trusted-wrapper.ax` and the ordinary workload in
`tests/stdlib/545-no-unsafe-practical.ax`, which claims
`restrict(no-unsafe)` over `Vec`, `Map`, `Str`, `Chan` and `Task`, keep
the trusted side compiling.

**MM-EXEC-9e (H). No safe interface hands a caller's word to the
kernel, or to a primitive, as an address.** A declaration that passes
a word it didn't make to an address argument of a `__syscallN`, of a
platform function or of an `Unsafe` primitive **MUST** be a
precondition interface (`MM-EXEC-9d`). Its precondition names the
extent the callee reads or writes, such as "`buf` names `count` live
writable bytes". A declaration that passes only addresses it made
itself, from a `String`'s bytes or a fresh allocation, is a trusted
encapsulation. A struct whose fields a trusted function hands on that
way **MUST** be private to its module, so that only the module builds
one or reads or sets a field. Another module can still name the type
in a signature.

Every `Sys` call that hands the kernel an address to read or write is
a precondition interface. That covers the descriptor reads and writes
(`sysReadFd`, `sysWriteFd`, `sysWriteAllFd`), every call taking a
NUL-terminated path (`sysOpenPath`, `sysReadFile`, `sysWriteFile`,
`sysRename`, `sysFileExists` and the rest), `sysRandomBytes` and the
terminal calls. It covers the socket-address readers, the poll and
signal calls, the clock reads, `sysChildExited`, `sysSpawn` and the
`sysRun` family, `sysUnmapShared` and the word waits too. So are `IO`'s `readFileLit` and `printlnLit`,
`rdReseat` and `Fmt`'s digit writers. `KeyIn` and `IO`'s `TermState`
are private. A syscall is an unsafe
operation of its own (`MM-EXEC-9c`), so a function that makes one says
`effect(unsafe)`, and `restrict(no-unsafe)` refuses
`(__syscall3 sysRandomNum 4096 64 0)`.

Ordinary code uses `IO`'s typed calls instead, which are trusted
encapsulations. Every path is a `String`. `writeStr` and `writeSlice`
write a string or a range of one, `readInto` reads into a range of a
`String` buffer, and `readLine`, `readAll` and `randomBytes` answer
fresh strings. `termSave`, `termRaw`, `termRestore` and `termSize` keep
a terminal's saved settings in a `TermState`. A range outside its
string is the index trap, status 77, before the kernel is called
(`tests/stdlib/610-typed-io-bounds.ax`).

What the kernel does with the word decides three calls. `sysWakeWord`
is trusted: `futex(FUTEX_WAKE)` and `__ulock_wake` use the address only
to find a wait queue and never read or write it, and a wake that
reaches another waiter is a spurious wake, which every waiter already
tolerates. `sysMapShared` is trusted, because the kernel chooses the
address it answers. `sysWaitWord` is a precondition interface, because
the kernel reads the word.

Out of scope: the modules that hand out raw `Int` handles to records
they allocate, `Json`, `Intern` and `Rpc`'s reader. A handle is forged
without a cast, so the functions that read one trust their caller
without a tag saying so.

Tested by `tests/diagnostics/1081-sys-buffer-calls.ax`, which refuses
an untagged call to each descriptor, path, entropy, terminal, unmap and
wait interface and accepts the typed calls under `restrict(no-unsafe)`,
`tests/stdlib/580-kernel-precondition.ax`
and `tests/stdlib/545-no-unsafe-practical.ax`, which does file,
entropy and terminal work under `restrict(no-unsafe)`.

**MM-EXEC-10 (H).** Handlers for a declared effect are installed by
`handle` and dispatch through a per-effect evidence slot:

- installation is dynamically scoped over the body's extent, at any
  call depth;
- handlers are **tail-resumptive**: the handler's return value *is* the
  operation's result, and execution continues at the operation's site.
  No continuation is captured (`MM-VAL-12`);
- a handler runs under the evidence in scope at its **installation**, so
  an operation it performs itself dispatches outward, never back into
  itself;
- an operation performed with no handler in extent exits the process
  with status **71**. Where the compiler can see this coming, it says
  so first: `AX3053` reports a custom effect still in `main`'s row
  after inference, which is an effect no `handle` discharged. It is a
  warning, because the two closure shapes make the evidence one-sided in
  both directions (`tests/diagnostics/severity.policy`). Write
  `;@axiom:unhandled(trap)` on the `effect` declaration to silence it
  for an effect whose unhandled operation is a deliberate abort, as
  `stdlib/Test.ax`'s `Assert` is;
- a handler **cannot abort** the computation it handles. There is no
  non-local exit from a handler, and the only way out is process exit;
- installation is **dynamic extent, not lexical capture**: a closure
  built inside a `handle` and invoked after that `handle` has returned
  performs its operation with the slot restored, and traps.

End to end:

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

This prints `from deep` and exits 7. With the `handle` removed, it
exits 71.

### 1.3 Determinism

**MM-EXEC-11 (H).** A program's observable behaviour **MUST** be a
function of its inputs alone, **provided it observes no address**.
Its inputs are the process's arguments, its environment, and the bytes
it reads. The implementation adds no hash seed, no scheduler, no
finalizer, and no iteration order:

- `Map` exposes no iteration API, only the order-independent
  `mapSumKeys`/`mapSumVals`;
- slot placement is a pure function of key and capacity;
- `Intern` hands out dense ids in insertion order.

**MM-EXEC-12 (H).** The proviso matters. **Heap and literal addresses
are ordinary `Int` values, and they differ between runs of the same
binary, because the loader randomises the address space.** The ways to
observe one are few and listed here, and each is a **program
obligation**:

| Escape hatch | What leaks |
|---|---|
| `(__alloc n)`, `memAlloc` | the address itself |
| `(__addr "lit")`, `strData` | a literal's or a string's data address |
| `(cast Int v)` on any heap value | that value's address |
| `Vec`/`Map`/`Str` handles | addresses, since a handle *is* an address |
| `sysGetPid`, `sysNowMicros` | process and wall-clock state |
| `sysEnv`, `sysArg` | the environment |

**MM-EXEC-12a (H).** **`==` and `!=` on two `String`s compare
content.** The comparison is over bytes, which makes it correct for
Unicode, since UTF-8 byte equality is code-point-sequence equality. The
length word bounds it, so an interior NUL is an ordinary byte, and a
`strSlice` result, which isn't NUL-terminated, compares correctly.

```scheme
(import IO)
(import Str)

;@axiom:effect(io)
(fn (main)
  (let ((a "hi") (b (strDup "hi")))
    { (println (if (== a b) "equal" "different"))
      (println (if (== (cast Int a) (cast Int b)) "same object" "two objects"))
      0 }))
```

```text
equal
two objects
```

Two consequences you **MUST** know:

- **It fires on what the checker concluded**: both sides exactly
  `String` (`tyIsStringTy`, not `tyCompat`, because under the fiat in
  `MM-ALLOC-20` asking for compatibility would answer yes for every
  `Int`). If one side is a string and the other an `Int`, the integer
  comparison stays, rather than dereferencing a number. This is the
  same static dispatch the language already performs for `fadd` against
  `add`.
- **Identity is a different question from equality.** A program asking
  whether two handles are the *same object* **MUST** say
  `(== (cast Int a) (cast Int b))`, as the example does.
  Identical literals within a module share one header, so they are the
  same object. `tests/stdlib/090-intern.ax` uses this test to prove an
  interner's inputs were distinct handles.

Ordering (`<`, `>`, …) on strings still compares addresses. Use
`strCmp` when you need content order. Making `<` mean `strCmp` is a
larger decision than fixing equality, and an address ordering is at
least not a wrong answer to a question anyone asks.

Tested by `tests/stdlib/035-string-equality.ax`. Its cases include the
Unicode pair, the interior-NUL and slice case, and the integer
comparisons that must not change.

A program that prints `(__alloc 8)` prints a different number under a
different allocation history. This is a **program obligation**: a
program that requires deterministic output **MUST NOT** make an address
part of it. Every byte-comparing check in this repository depends on the
compiler itself honouring this, which is why `Intern` keys on content
and `Map` iteration is never exposed in output order.

**MM-EXEC-13 (H).** Compilation is deterministic: the same source
produces byte-identical LLVM IR, and `scripts/check-reproducible.sh`
checks it. Every counter the compiler exposes in a name is a per-run
monotonic integer, never an address or a hash of one. That covers the
macro expander's gensym (`MAC-HYG-3`), the register allocator's
counter, and the type variable numbering.

**MM-EXEC-14 (R).** The compiler **MUST NOT** evaluate user code during
compilation. This is a threat-model invariant, not a performance
decision, and the macro system shares it and is built around it
([macro-system.md §1.4](macro-system.md)). You can observe it: the
compiler doesn't even constant-fold. This program:

```scheme
(fn (main) (+ 1 (* 2 3)))
```

emits this IR for its body:

```text
    %.t0 = mul i64 2, 3
    %.t1 = add i64 1, %.t0
```

Folding happens later, in `opt`, on IR. It never happens on the source,
and never by running a function the source defined.

### 1.4 Process lifecycle

**MM-EXEC-15 (H).** The emitted `@main(i64 %argc, i64 %argv)` stores its
two parameters in `@__axiom_argc` and `@__axiom_argv`, then calls the
user's `main`. That function is emitted as `@__axiom_user_main` and
takes no arguments. The process's exit status is the low 8 bits of
`main`'s result: a `main` answering 5,000,001 exits 65.

**MM-EXEC-15a (H).** The rename covers references as well as the
definition. A call to `main`, whether recursive or from another
function in the entry file, reaches `@__axiom_user_main`. This program
exits 5:

```scheme
(:: main Int)
(fn (main) (if (< 1 0) (main) 5))
```

Under the hood, the emitter's tables (`isNullaryFn`, `isDefinedFn`,
`fnArityOf`, `findFSig`) hold the declared spelling, so every lookup
normalises the emitted symbol through `declSpellingOf`. Only an entry
file's `main` is renamed. An imported module's `main` is
module-mangled and coexists with the wrapper. Tested by
`tests/selfhost/371-main-recursive.ax`, which exits 5.

**MM-EXEC-16 (H).** The emitted runtime **reserves** these exit
statuses. A program **MUST NOT** reuse them as a normal result:

| Status | Raised by | Evidence |
|---|---|---|
| 70 | allocator out of memory (`mmap` failed) | measured: `tests/stdlib/314-out-of-memory.ax` asks for 2^47 bytes; the run prints `axiom: out of memory (mmap failed)` to fd 2 and exits 70 |
| 71 | operation performed with no handler in extent | measured (`MM-EXEC-10`): `tests/stdlib/310-effect-unhandled.ax` prints `axiom: unhandled effect` to fd 2 and exits 71; `tests/stdlib/310-effect-unhandled.err` pins the message |
| 72 | division by zero | measured: `(fn (main) (/ 10 0))` checks `OK`; the run prints `axiom: division by zero` to fd 2 and exits 72 |
| 74 | a `__syscallN` reached on a target with no syscall ABI (windows-x86_64, windows-aarch64) | emitted, not yet executed: `emitPrimSyscall` lowers the primitive there to `__axiom_no_syscall`, which prints `axiom: no syscall ABI on this target` (37 bytes) and exits 74. Status 73 belongs to the FFI (`ffiHandleClose`) |
| 75 | `__axiom_arena_reset` handed a mark whose chunk is no longer on the active list (`MM-ALLOC-16a`) | measured: `tests/stdlib/166-arena-bad-mark.ax` resets an inner mark after its outer one; the run prints `axiom: arena reset to an invalid mark` to fd 2 and exits 75. The fixture's first two blocks (nested marks reset innermost-first, and one mark reset twice) must still exit silently, so the trap is pinned against firing on legal use |
| 76 | `__axiom_arena_reset` handed a mark taken before a `handle` whose extent is still live (`MM-ALLOC-16b`) | measured: `tests/stdlib/167-arena-live-handle.ax` resets a mark that predates the extent; the run prints `axiom: arena reset past a live handle` to fd 2 and exits 76. Its first two blocks (a mark taken inside the extent, and a mark with no handle in scope) must still exit silently. `tests/stdlib/401-recover-effect.ax` must still exit 71, because a recovery abort performs this same reset legitimately |
| 77 | an index out of range, raised by `(__indexTrap)`: `vecGet` and its kin, and `IO`'s range checks on `writeSlice`, `readInto` and `randomBytes` | measured: `tests/stdlib/464-index-trap.ax` prints `axiom: vector index out of range` to fd 2 and exits 77; `tests/stdlib/610-typed-io-bounds.ax` refuses each typed call's out-of-range argument before its syscall |
| 78 | `parallel`: the kernel refused the fork or the pthread (`__axiom_par_spawn_failed`) | measured by `scripts/check-parallel.sh` §12d: under a per-user process limit of 1 a `parallel` form's fork answers EAGAIN, a recovery point armed around it answers 78, and the unrecovered spawn prints `axiom: parallel: could not spawn the binding` and exits 78 (processes on every non-root runner, threads too on Linux, where the limit counts threads) |
| 79 | `parallel` on a target with neither `fork` nor a pthread (windows-x86_64, windows-aarch64) | emitted, not executed: both primitives compile there to `__axiom_par_unsupported`, which prints `axiom: parallel is not available on this target` and exits 79. The program builds for every target and says at its first spawn what it can't do (`scripts/check-parallel.sh` reads the IR) |
| 80 | a violated `;@axiom:pre(...)`/`post(...)` contract | measured by `scripts/check-contracts.sh` §1: a violated `pre`/`post` prints ``axiom: precondition failed in `half`: (> n 0)`` to fd 2, prints the backtrace, and exits 80 at every `--opt` level. Inside `__axiom_recover` it answers 80 to the arming call |
| 81 | an unhandled CPU exception on `baremetal-aarch64` | measured under QEMU (TCG): `tests/embedded/fault.ax` takes an alignment fault; the vector table writes the vector offset, ESR, ELR and FAR to the UART and exits 81 (`MM-EXEC-18`, `scripts/check-embedded.sh` A12). A stack overflow is one too, reported with a line naming the guard (`tests/embedded/overflow.ax`, A17). Not recoverable: no armed recovery point is jumped to. With an `isr(fault)` hook bound, the hook's answer is the status instead, for this row and for every trap above (`MM-EXEC-19`) |
| 82 | an atomic whose address is not 8-byte aligned (`emitAtomicAlignGuard`, `MM-PAR-9`) | measured: `tests/stdlib/544-misaligned-atomic.ax` hands each of the four atomics an address 4 bytes into a word inside a recovery point, which answers 82 each time, then prints `axiom: misaligned atomic access` to fd 2 and exits 82, at every `--opt` level |
| 83 | `INT_MIN / -1`, raised by the division guard (`emitDivGuard`): `sdiv`/`srem` overflow has no representable answer | measured: `tests/stdlib/695-intmin-div-trap.ax` divides inside a recovery point, which answers 83, then prints `axiom: division overflow` to fd 2 and exits 83, at every `--opt` level |
| 84 | a shift amount below 0 or above 63, raised by the shift guard (`emitShiftGuard`): an overshift is poison in LLVM | measured: `tests/stdlib/696-shift-wide-trap.ax` shifts inside a recovery point, which answers 84, then prints `axiom: shift amount out of range` to fd 2 and exits 84, at every `--opt` level |
| 85 | a handle that isn't live: a freed, forged or other-kind channel, mutex or cancellation token, a second free of one, or a spawn handle joined twice or by the other lowering's join (`@__axiom_handle_dead`, `MM-PAR-8`) | measured: `tests/stdlib/570-handle-freed.ax` runs every channel and mutex operation on a freed handle, a second free, a forged word and a mutex's word used as a channel, each inside a recovery point, which answers 85 each time, then prints `axiom: not a live handle (freed, or never made)` to fd 2 and exits 85, at every `--opt` level. `tests/stdlib/572-spawn-joined-twice.ax` does the same for a second join, the pid of a joined binding and a freed token, and `tests/stdlib/571-handle-table.ax` pins the table: 65,536 live handles, the next refused, and a reused slot under a new generation |

`(__indexTrap)` never returns, so it fits every result type. It exists
because traps are `internal` LLVM functions emitted by the runtime
block, and nothing in `stdlib/` could otherwise reach one. A container
that refuses an out-of-range index, rather than answering a value,
needs exactly that (`docs/generics-design.md` §4). The same fixture
uses the trap in an `Int` result and a `String` result in one program,
which a concrete-typed trap couldn't do.

Each broken invariant gets its own status. The contract trap takes 80,
the first free number, so it never shares a status with another trap.
This follows the FFI's precedent in `docs/ffi.md` §5.1, which took 73
so a panic and a division by zero stay distinguishable. The history of
the choice is in `docs/subtypes-design.md`.

I/O is unbuffered: `println` is a direct `write` loop with no flush. So
output produced before one of these aborts is still visible.

**MM-EXEC-17 (H).** Releasing the final share of a resource owner
MUST run its cleanup callback once. Files and sockets close; database
connections close, statements finalise and unfinished transactions roll
back. Explicit close retires the owner before cleanup, so later releases
MUST NOT repeat it. Region release optimisation MUST preserve callbacks.

Process exit and trap recovery do not unwind owners or run atexit hooks.
Cycles and values escaped through raw words need explicit close. The
operating system reclaims a process's descriptors at exit.

Tested by `tests/stdlib/697-resource-owner.ax` and
`tests/axqlite/616-api-auto-close.ax`.

**MM-EXEC-18 (H, 2026-09-27). Interrupt handlers: one at a time, no
allocation, no recovery, state shared only through the unsafe layer.**
On `baremetal-aarch64` a function tagged `;@axiom:isr(irq)` is the IRQ
exception vector's handler (`emitIsrBinding`, `emitBaremetalVectors`);
the tag is refused as `AX4008` on every other target, for a vector name
other than `irq` or `fault` (`MM-EXEC-19`), and for a second handler.
The rules:

- **No nesting.** The core masks IRQs on exception entry and `eret`
  restores the interrupted code's mask, and the handler runs with them
  masked throughout, so a handler is never re-entered and never
  interrupted by another IRQ. Nothing in the port unmasks inside one.
- **The interrupted code is preserved.** The entry saves every register
  AAPCS64 lets a callee clobber - x0-x18, x29, x30, ELR_EL1, SPSR_EL1,
  FPCR, FPSR, q0-q7, q16-q31 - in 592 bytes of the interrupted stack,
  and restores them before `eret`. That stack must have room: the
  handler's own frames sit on top of the deepest point the main loop
  reaches.
- **No allocation** (implementation obligation, checked). `isr` implies
  `restrict(no-alloc)`, refused as `AX3049`: the bump allocator is not
  reentrant (`docs/embedded-proposal.md` section 7), and a handler that
  allocated while the main loop was mid-allocation would corrupt the
  arena. No `region`, no `parallel`, no `Vec` growth, no string
  building, and no `println` - which builds its line.
- **No recursion** (implementation obligation, checked). `isr` implies
  `restrict(no-recursion)` as well, refused as `AX3049`: the handler's
  frames sit on a stack it doesn't own, so its depth must be one the
  stack bound (RP-7) can compute.
- **No waiting** (implementation obligation, checked where it can be).
  A call path from the handler to `__arm_wfi`, which sleeps with the
  interrupt that should wake it masked, or to a `__syscallN`, where
  every blocking library call ends and which traps 74 on this target,
  is refused as `AX4009` with the path. A loop polling a word is a wait
  the walk can't see, and stays the program's obligation below.
- **No recovery across the boundary** (implementation obligation). The
  dispatch clears the recovery slot for the handler's extent and puts
  it back before returning, so a trap inside a handler - a division by
  zero, a violated contract, an index out of range - exits with its
  own status rather than unwinding into a recovery point the
  interrupted code armed, which would resume that code in exception
  context with interrupts still masked. An effect operation inside a
  handler finds no handler in extent and traps 71.
- **What is interrupt-safe** (program obligation). A handler MUST NOT
  wait for anything the main loop does (it cannot run until the handler
  returns), so no lock the main loop can hold and no unbounded poll; it
  SHOULD be bounded, since the main loop's deadlines wait on it. State
  shared with the main loop is reached through the unsafe layer - the
  language has no top-level mutable state (`MM-PAR-9`) - and on one core
  that sharing needs two things: volatile accesses on the main-loop
  side, so the compiler re-reads a word the handler writes
  (`MM-FFI-8`), and the main loop MASKING IRQs around any read or
  write of more than one word that must be consistent, which is the
  only lock a single core needs. A handler finds its state through
  `TPIDR_EL1` (`__arm_tpidr`), set before interrupts are unmasked,
  pointing at a block that is not reclaimed while they are.

*Evidence:* `scripts/check-embedded.sh` A12 holds the table, the entry's
save/restore and the dispatch in the IR, and the fault exit under QEMU.
`scripts/check-isr.sh` §4 holds the recursion and waiting refusals
(`tests/diagnostics/1091-isr-waits.ax`, `1092-isr-recursion.ax`), each
with an ablation under which its fixture checks clean. Emulator
evidence at most: whether a given part's interrupt latency meets a
deadline is a hardware question this tree does not answer.

**MM-EXEC-19 (H). On `baremetal-aarch64` the memory map turns wild
accesses into faults, and what a fault ends in is the program's
choice.** The language can't know a system's safe state. It provides
the mechanism: a fault that is caught, reported and handed to one
function. The program supplies the policy. A trap is never by itself a
safe state.

*The memory map* (implementation obligation). `_start` builds
identity-mapped stage-1 tables with the MMU off (`emitMmuTables`) and
then sets `SCTLR_EL1` M, C, I, A, SA and WXN (`mmuEnableAsm`), before
`main` runs:

- code is read-only and executable at EL1; read-only data is read-only
  and execute-never; data, `.bss` and both stacks are read-write and
  execute-never, and WXN makes every writable page execute-never
  whatever its descriptor says;
- a 64 KiB guard below the program's stack, and 4 KiB below the fault
  stack, are not mapped, and neither is anything past the image, the
  page tables included;
- below RAM only two 2 MiB Device-nGnRnE blocks are mapped, the GIC
  (`0x08000000`) and the UART, RTC, `fw_cfg` and GPIO (`0x09000000`);
  address 0 is not mapped;
- RAM is Normal memory, inner and outer write-back, inner shareable, so
  a device that isn't coherent needs `MM-FFI-8`'s cache maintenance;
- `SCTLR_EL1.A` keeps every misaligned access an alignment fault, which
  the bare target's `+strict-align` keeps LLVM from writing.

The MMU is always on for this target: there is no opt-out.

*The fault exit* (implementation obligation). Every vector but a bound
IRQ switches to the fault stack before its first memory access, so a
fault taken with the stack pointer in the guard is still reported. It
writes the vector offset, ESR, ELR and FAR, and a second line when the
fault is a data abort at an address in a stack guard. It never returns
to the faulting code and never jumps to a recovery point the program
armed. A fault while the report is written exits 81 without writing.

*The hook.* `;@axiom:isr(fault)` binds one function of type
`(-> Int Int Int Int Int Int)`. With it bound:

- a CPU exception, after its report line, calls the hook with status
  81, the vector offset, ESR_EL1, ELR_EL1 and FAR_EL1;
- a software trap outside any recovery point (`MM-EXEC-16`'s statuses
  70 to 85), after its sentence, calls the hook with its own status, a
  vector of -1 and three zeros, having masked D, A, I and F and moved
  to the fault stack;
- the hook runs with D, A, I and F masked and no recovery point armed,
  and its answer is the exit status; it may instead never return (a
  halt, or a reset);
- a CPU exception while the hook runs is reported once more, as a
  fault in the fault handler, and exits 81; a software trap while the
  hook runs exits with its own status; neither calls the hook again.

The tag implies what `isr` does (`MM-EXEC-18`): `no-alloc` and
`no-recursion` (`AX3049`), and no path to a system call (`AX4009`).
Halting in `wfi` is allowed, because never returning is one of the
answers the hook exists to give. The declaration must be the type
above (`AX3010`); a second hook, and the tag on any other target, are
`AX4008`. With no hook bound, every exit is what it was: the report
and 81, or the trap's own sentence and status.

*What the program must decide* (program obligation). What each status
means for the system: restart, degrade, or hold a safe state. The hook
must also be safe with the program's state possibly corrupt. It reads
only what it needs and follows no pointer the failed code built. On
hardware it ends in a reset, a halt or a watchdog, because without a
debugger semihosting's exit is itself an exception.

*Evidence:* `scripts/check-embedded.sh` A16 decodes the descriptors
from the IR, and reads `SCTLR_EL1`, `TCR_EL1` and `MAIR_EL1` back under
QEMU. A17 ends `tests/embedded/overflow.ax` in the guard. A18 faults a
store to code, a branch into data and a read of address 0 where the
map says. A19 runs the hook after a fault, after a trap and through a
PSCI reset, and A20 faults inside the hook. Each has a drill that goes
red (`mmuoff`, `guard`, `excstack`, `codewrite`, `hookoff`, `reenter`).
`scripts/check-isr.sh` §4 holds the hook's shape
(`tests/diagnostics/1090-isr-fault-signature.ax`). *Limit:* all of it
is QEMU TCG, which models no cache, so no run shows a missing cache
clean or invalidate; nothing here ran on hardware.

---

## 2. Value representation

### 2.1 The uniform word

**MM-VAL-1 (H).** **Every Axiom value is exactly one 64-bit machine
word.** Every function takes and returns `i64`. There is no other
width, no aggregate passed by value, and no unboxed pair.

**MM-VAL-1a (H).** Because of `MM-VAL-1`, generics use a uniform
representation. A polymorphic function is emitted exactly once, and
every call site calls the same symbol, whatever the type argument.
There is no monomorphisation. `sizeof` and `alignof` answer 8 for every
type. Nothing in this model produces per-instantiation code, so
polymorphism can't grow code size.

**MM-VAL-2 (H).** A word carries **no tag**. Nothing at runtime can tell
from a word alone whether it holds an integer, a float, a boolean, a
character, a constructor tag or a heap address. This is the most
consequential fact in this document. It is why there is no tracing
collector (`MM-LIFE-2`), why escape analysis can't be added without a
type-level change (`MM-ALLOC-15`), and why the compiler must track
float-ness statically (`MM-VAL-4`).

**MM-VAL-3 (H).** Integers are 64-bit two's complement. `+`, `-` and
`*` **wrap**, with no `nsw`/`nuw` flag and no check. Division and
remainder are signed and truncate toward zero (`(/ -7 2)` = −3,
`(% -7 2)` = −1). Comparisons are signed, `>>` is arithmetic, and `<<`
is a plain shift.

Wrapping is how these operators are defined, and it won't change. When
your program can't afford it, use `stdlib/Err.ax`'s `addChecked`,
`subChecked` and `mulChecked`. They answer `(Result Int Error)` and
report `errOverflow` instead (`MM-VAL-3b`).

**MM-VAL-3a (H).** Division or remainder **by zero is a guarded trap**,
not undefined. The compiler emits a zero test even for a literal zero
divisor, and the trap writes `axiom: division by zero` to fd 2 and
exits 72.

**MM-VAL-3b (H).** Three integer cases are **guarded traps**,
like `MM-VAL-3a`: `INT_MIN / -1` writes `axiom: division overflow`
to fd 2 and exits 83, and a shift amount below 0 or above 63 writes
`axiom: shift amount out of range` and exits 84. The guards are in
the operators, so only `/`, `%`, `<<` and `>>` pay for them, and
both traps are recoverable: inside `__axiom_recover` the arming
call answers the status instead of dying of it.

Until 0.8.0 these cases were undefined, and a specification **MUST**
name what they did, so that no reader infers the traps were always
there. Each showed up as an answer that changed with `--opt`:

| Expression | `--opt 0` | `--opt 1` |
|---|---|---|
| `INT_MIN / -1` | −9223372036854775808 | 1 |
| `(>> 1024 64)` | 1024 | 1 |
| `(<< 1 100)` | 68719476736 | 1 |

The remedy is still in `stdlib/Err.ax`: `addChecked`, `subChecked`
and `mulChecked` for the wrapping operators of `MM-VAL-3`, and
`divChecked` and `shlChecked` for the trapped cases. `mulChecked`
rules out `intMin * -1` before the division that would hit this
rule's first case, in both operand orders, so it never performs the
trapping operation. Keep that guard even though output can't show
it's needed: the trap it avoids is one the raw operator would take.

`tests/stdlib/695-intmin-div-trap.ax` and
`tests/stdlib/696-shift-wide-trap.ax` pin the sentence, the status
and the recovery answer. Each traps once inside a recovery point,
which answers the status, and once outside it, which exits; each
carries `.optstable`, so stdout and exit status are identical at
`--opt` 0, 1, 2 and 3.
That is the property the table above says the raw operators
couldn't claim before the guard.
`tests/stdlib/312-checked-arithmetic.ax` cites `MM-VAL-3b` by name
and pins byte-identical stdout at `--opt` 0, 1, 2 and 3 for the
checked side.

**MM-VAL-3c (H).** The sized integer types (`I8`…`I128`, `U8`…`U128`,
`Isize`, `Usize`) are **refused** (`AX3002`). There are **no unsigned
operations**, and `Int` is the one integer type. Tested by
`tests/diagnostics/495-widthless-types.ax`.

`I64` survives as a leaked internal. The checker constructs it as the
type of the `set` form, and diagnostics may print it, but a program
can't spell it.

**MM-VAL-4 (H).** A `Float` is an IEEE-754 binary64 **bit-cast into the
same word**. The compiler decides statically, from declared types,
which words to reinterpret as `double`:

```llvm
define i64 @addf(i64 %a, i64 %b) #0 {
  %.d0 = bitcast i64 %a to double
  %.d1 = bitcast i64 %b to double
  %.d2 = fadd double %.d0, %.d1
  %.t3 = bitcast double %.d2 to i64
  ret i64 %.t3
}
```

This puts an obligation on your program. Float-ness is static and
can't be recovered at runtime, so a `Float` that reaches a position the
compiler believes is an `Int` is reinterpreted, not converted.

**MM-VAL-4a (H).** `cast` performs **no conversion**. It reinterprets
the same 64-bit word. Its only effect on code generation is to set the
compiler's float flag when the target type is spelled `Float`. The real
numeric conversions are `__intToFloat` and `__floatToInt`, which lower
to `sitofp` and `fptosi`.

**MM-VAL-4b (H).** Float arithmetic is selected by the type name
`Float` **and no other**. The spellings `Double`, `F32` and `F64` are
**refused** (`AX3002`). The emitter keys float arithmetic on `Float`
alone, so accepting another name would lower its arithmetic as integer
`add` on double bit patterns. `tyIsFloatTy` matches the emitter's
one-name rule. Tested by `tests/diagnostics/495-widthless-types.ax`.

**MM-VAL-4c (H).** Float comparisons use LLVM's **ordered** predicates,
so every comparison involving NaN is false. That **includes `!=`**,
which is `fcmp one`: `(!= NaN NaN)` is `false`, where IEEE-754 says
true. Division by zero is unguarded, yields ±inf or NaN, and the
program continues. `Fmt.fmtFloat` can't render either value: `+inf`
prints as `-9223372036854775808.9223372036853775807` and NaN as
`0.000000`.

**MM-VAL-5 (H).** `Bool` is 0 or 1. `Char` is a Unicode code point as
an integer. Both are ordinary words.

### 2.2 Heap blocks

**MM-VAL-6 (H).** A heap block is an array of machine words at a
16-byte-aligned address. **A heap block is not self-describing.** It
carries no size, no layout map, and no header other than the
constructor tag that `MM-VAL-8` places at word 0 for one of the three
representations. Given an address, nothing in the running program can
recover what is stored there.

**MM-VAL-7 (H).** A `Str` is the address of a
**three-word** header:

| Word | Contents |
|---|---|
| 0 | length in bytes |
| 1 | address of the bytes |
| 2 | the block that owns those bytes, or 0 |

The bytes are NUL-terminated as well as length-counted. So `strCStr`
hands a path to a syscall without copying, and a `Str` may contain an
interior NUL.

`strSlice` **shares** the original's bytes instead of copying them.
A slice keeps its parent's buffer live and points into its middle
(`MM-LIFE-6`). Word 2 lets that keeping be counted: a slice inherits its
parent's owner instead of naming the parent. The chain is therefore one
hop deep however many times you cut a slice, and the counted address is
never interior.

Zero in word 2 means no block owns the bytes, and nothing may free
them. A literal's bytes are loader-resident, a syscall buffer's are the
kernel's, and an arena keep block's interior belongs to the arena.
`strAlloc` names the buffer it just allocated and takes one share of
it. Every `strSlice` takes one more.

Every header that names an owner holds a share of it.
`Sys.sysReadAll` answers a second header over the read buffer's bytes,
inherits the buffer's owner, and takes its own share. Tested by
`tests/stdlib/358-str-owner-shares.ax`, which answers 63. A library
that skips the share answers 51.

Nothing releases a `Str` header yet, so a missing share has no effect
today. Once `MM-LIFE-2e`'s extension work lands, it becomes a
use-after-free into a block already on a size-class free list. §9.0
holds defects of this kind, which stay inert until a later change.

**MM-VAL-7a (H).** A **string literal allocates nothing**. It evaluates
to the address of a static constant header whose length is a
compile-time constant. Literals are **interned by content**, so two
occurrences of the same text in a module share one header. Only
`strAlloc`, `strDup`, `strConcat` and their callers allocate.

**MM-VAL-8 (H).** Each `data` type gets one of three representations,
computed once per type from its constructors (`codegen.ax`
`ctorsRep`). Tags are **unique across the whole program**, not per
type.

| Code | Condition | Representation |
|---|---|---|
| 0 | no nullary constructor, **or** the type's tags would reach 4096 | every value is a heap block; word 0 is the tag, fields at words 1.. |
| 1 | every constructor is nullary | every value *is* its tag, an immediate below 4096; nothing allocates |
| 2 | mixed | nullary constructors are immediate tags; fieldful ones are heap blocks |

One probe shows all three facts. With `(data A () (A1) (A2))` and
`(data B () (B1 Int) (B2 Int Int))`, the expression
`(+ (cast Int (A2)) (cast Int (B1 7)))` emits:

```llvm
%.t0 = call i64 @axiom_alloc(i64 16)    ; B1: (1 + arity) * 8
store i64 4, ptr %.t2                   ; word 0 = tag 4
store i64 7, ptr %.t4                   ; word 1 = the field
%.t5 = add i64 3, %.t0                  ; (A2) IS the immediate 3
```

A1 = 2, A2 = 3, B1 = 4, B2 = 5: one counter, across both types.

**MM-VAL-8a (H).** Tags come from **one global counter starting at 2**.
It spans the whole compilation unit, including imported modules, whose
constructors are numbered first. A type's tag values therefore depend
on the import graph and on declaration order. That is observable only
through `MM-VAL-8b`, and it is why nothing may serialise a tag.

**MM-VAL-8b (H).** There is a hard **representation cliff at 4096
tags**. When a type's first tag plus its constructor count reaches
4096, the whole type falls back to representation 0, and its nullary
constructors become 8-byte heap blocks. **The same type, declared later
in a larger program, has a different machine representation.** Nothing
in the language shows which one is in force, and nothing may depend on
it.

**MM-VAL-9 (H).** For representation 2, a match site tells the two
kinds apart with one runtime test. **A word below 4096 is an immediate
tag, and a word at or above 4096 is an address.** The bound is sound
because tag assignment refuses to cross it (`MM-VAL-8b`), and because
every heap address comes from `mmap`, which never returns the zero
page.

```llvm
%c5 = icmp slt i64 %v, 4096
br i1 %c5, label %immediate, label %boxed
```

**MM-VAL-9a (H).** `match` emits that guard, and field access does
**not**. So field access on a `data` type **with a nullary
constructor** is **refused** (`AX3070`). A value of such a type may be
an immediate tag, and an unguarded load would dereference a small
integer.

```scheme refused
(data T () (E) (N { v : Int }))
(fn (main) (let ((x (E))) x.v))     ; AX3070
```

On a `data` type whose constructors all have fields, access is legal
only when every constructor declares the field at the same word with
the same type. Otherwise the load would read another field's slot, or
a word past a shorter block, so that access is refused too (`AX3070`).
We chose refusal over a guard because a guard would have to invent an
answer for the missing-field case.

`tests/stdlib/210-struct-variants.ax` exercises the legal access, where
every constructor agrees on the field. `tests/diagnostics/480-field-on-mixed-data.ax` and
`tests/diagnostics/484-field-on-partial-data.ax` pin the two refusals,
and `tests/selfhost/1003-data-field-agree.ax` pins the accepted shape.

**MM-VAL-9b (H).** A `match` whose arms cover no constructor and bind
no catch-all is **refused** (`AX3005`). It could fall through, and a
fall-through would answer the match's freshly allocated result cell.
`MM-ALLOC-6` guarantees that cell is zero, which is indistinguishable
from a real `0`. Tested by
`tests/diagnostics/476-literal-match-fallthrough.ax`.

```scheme refused
(fn (main) (match 7 ((1) 11) ((2) 22)))   ; AX3005
```

One all-literal shape stays accepted, because it can't fall through: a
`Bool` match with **both** a `true` and a `false` arm. Those two are
literal tests that add nothing to constructor coverage (`MAC-HYG-5`
measured why), and having both is exhaustive.

**MM-VAL-10 (H).** A `struct` is a heap block of `fields * 8` bytes,
with field *i* at word *i* in declaration order, and **no tag**. The
keyword form `(struct P a b)` and the application form `(P a b)` build
the identical block.

**MM-VAL-10a (H). A `word` struct is one machine word, sealed to its
module.** A struct declared with the marker `word` isn't a heap block.
Its one field, an `Int`, is the whole value:

```scheme
(pub struct Chan word shared
  (slot : Int))
```

`(Chan w)` is the word `w`, and `c.slot` is the word `c`. The value
allocates nothing and takes no share. It has no bit in any reference
map and costs a polymorphic call no evidence word, so a heap block that
holds one maps exactly as it would for an `Int`.

The type is sealed. Only the module that declares it can build one, in
either spelling, or read its field, whatever `pub` says (`AX3085`,
`AX3086`). A function declared to answer `Int` can't answer one
(`AX3004`). `pub` exports the name, so another module's signatures can
mention the type and pass it on, but can't make or open one. Every
value of the type is therefore one its module made. A `cast` to the
type forges one, and that belongs to the unsafe layer (`MM-VAL-22`).

The checker holds the shape (`AX3084`): exactly one field, typed `Int`,
not `mut`, and no type parameters. The second marker, `shared`, needs
`word`. It says every operation the module offers on the type is safe
from several bindings at once, and `MM-PAR-6` lets a concurrent binding
capture exactly those word structs. The checker lowers construction and
field reads to the word itself, so the emitter never sees either, and
`symbols` reports the representation as `#repr=word` or
`#repr=word,shared`.

Tested by `tests/diagnostics/1062-handle-sealed-build.ax`,
`tests/diagnostics/1063-handle-sealed-field.ax` and
`tests/diagnostics/1065-struct-marker.ax`. `scripts/check-handles.sh`
compares the shape word of a record holding a handle with the same
record holding an `Int`.

**MM-VAL-11 (H).** A struct variant such as `(Circle { r : Int })` is
an ordinary constructor block under `MM-VAL-8`. The field names are a
compile-time mapping to positions, and patterns may use them in any
order.

Field *access* by name works on a `struct` type. On a `data` type, it
works only when every constructor declares the field at the same word
with the same type. Otherwise the value may be an immediate, another
constructor's block or a shorter block, and the single-index load the
emitter resolves has no sound slot to read. On a type with a nullary
constructor, or with a constructor that doesn't declare the field at
that word, access is refused (`AX3070`, `MM-VAL-9a`). A field name that
no constructor of the receiver's type declares is `AX3007`.

**MM-VAL-12 (R).** There are **no first-class continuations**, and none
of the machinery for them: no stack copying, no segmented stack, no
`call/cc`, no generators and no re-entrant handlers. `handle` is the
only non-local control construct, and it is tail-resumptive
(`MM-EXEC-10`). The handler's frame replaces nothing and captures
nothing: the operation's site simply receives the handler's return
value. The evidence a `handle` installs is a heap-allocated record
holding the handler closure and the previous evidence, saved and
restored around the body.

**MM-VAL-13 (R).** There are **no list or tuple values.** `[T]` and
`(A B)` are refused in type position (`AX2004`), and `[` in expression
position is `AX2001`. A sequence is a `data` type your program
declares, or a `Vec`. This is why the macro expander needs no case for
either (`macro-system.md` §11.3): a list-shaped value is always a
constructor application.

### 2.3 Closures

**MM-VAL-14 (H).** A `lambda` is lifted to a top-level function
`_lam_N` whose hidden first parameter is a **closure record**:

| Word | Contents |
|---|---|
| 0 | code pointer |
| 1.. | captured values, one word each |

**MM-VAL-15 (H).** Capture is **by value**, and it captures everything
in scope: every enclosing parameter and binding the lambda doesn't
shadow, not just the body's free variables. The extra capture can't be
observed. We chose it because a free-variable walker that misses one
case (a pattern binder, a nested arm's variable) captures the wrong
value silently, while an extra record word costs nothing.

**MM-VAL-16 (H).** A `mut` local is captured as **the value it held
when the record was built**. A closure never sees a later `set`
(`MM-MUT-1`).

**MM-VAL-17 (H).** A closure record built from a bare top-level
function points at a **forwarding thunk** `_thunk_N`. The thunk ignores
the record and calls the function with its arguments unshifted, so
every call through a value uses one calling convention.

**MM-VAL-17a (H).** A lifted lambda's signature is
`@_lam_N(i64 %.env, i64 %p)`: the environment first, then **exactly
one** user parameter. A multi-parameter lambda is curried into a chain
of one-parameter lambdas, **each allocating its own record**. Only an
arity-1 top-level function can become a function value at all
(`MM-EXEC-7`), and an arity-0 name is a call, not a value.

**MM-VAL-18 (H).** A call through a value applies **one argument per
step**. Each step loads word 0 of the current record as the code
pointer, calls it with `(record, argument)`, and treats the result as
the record for the next step. So a flat spine `(h 3 4)` over a curried
`h` means *apply, then apply the result*.

**MM-VAL-19 (H).** Partial application therefore exists only for
lambdas (`MM-EXEC-7`). The intermediate value of a partial application
is an ordinary closure record.

### 2.4 Pointers

**MM-VAL-20 (H).** The type system has a pointer type, spelled `(* T)`.
No expression a program can write produces one.

**MM-VAL-21 (R).** `(alloc T)` **MUST** be refused. The form typed as
`*mut T` and evaluated to the constant 0, with no dereference, no
field access and no store through the result, so a program holding
one held no memory. The parser answers `AX2004` and the help points to
`__alloc`, `vecNew`, `strAlloc` or a struct. The formatter refuses it
too. The `Alloc` effect has one site-level witness, a call to
`__alloc`.

*Evidence:* `tests/diagnostics/1102-alloc-removed.axbad`.

---

## 3. Allocation model

### 3.1 The allocator

**MM-ALLOC-1 (H).** A conforming implementation emits its allocator into
the program. Nothing is linked: a compiled Axiom program contains no
call to libc. Checked by `scripts/check-freestanding.sh`.

**MM-ALLOC-2 (H).** The allocator is a **bump allocator over
`mmap`-mapped chunks**. Its mutable global state is five scalar words
and one array:

| Global | Meaning |
|---|---|
| `@__axiom_bump` | next free address in the current chunk |
| `@__axiom_bump_end` | end of the current chunk |
| `@__axiom_chunk` | head of the active-chunk list |
| `@__axiom_free` | head of the reclaimed-chunk free list |
| `@__axiom_high` | dirty watermark for the current chunk: a **conservative upper bound** on how far into it memory has ever been handed out |
| `@__axiom_slabs` | the array: one free-list head per size class (`MM-ALLOC-25`), indexed by the class's size / 16, used by `MM-LIFE-2e`'s release path (4,097 words). Slot 0 is no class: it holds the filed-bytes count of `MM-ALLOC-24` |

The array is zero-initialised BSS. Like the five words, it is private
after `fork` (`MM-PAR-3`), and it holds only addresses of blocks the
program has released.

**MM-ALLOC-3 (H).** Every allocation is rounded up to a multiple of 16
bytes, and every returned address is 16-byte aligned
(`%sz = and (add %size, 15), -16`).

**MM-ALLOC-4 (H).** A chunk is `targetArenaChunkBytes`. When one
request needs more, the chunk is the request plus a 16-byte header,
rounded up to `targetArenaGrainBytes`. **Every supported target answers
1 MiB and 64 KiB.** Both are per-target rows of `codegen.ax`'s table
(`docs/embedded-proposal.md` 4.1), read at emission time, so a
program's chunk size is a constant in its text.

The grain is derived from the chunk: where the chunk is smaller than
64 KiB, the grain is the chunk. So a part with 4 KiB chunks can't round
a 5 KiB request up to sixteen chunks' worth. There is no growth policy,
and the chunk size never adapts.

Each chunk begins with a two-word header: its total size and one link.
The **active** chunks form a list, newest first, and the address handed
out from a fresh chunk is `base + 16`. The link word serves **both**
lists, so a chunk is on exactly one of them at a time, and a freed
chunk is unreachable from `@__axiom_chunk`. The fit test is inclusive:
a request that exactly reaches `bump_end` is served from the current
chunk.

**MM-ALLOC-4a (H).** Chunks come from a raw inline-assembly `mmap`
(`PROT_READ|PROT_WRITE`, `MAP_PRIVATE|MAP_ANON`, no address hint, no
guard pages) and are **never unmapped**. `munmap` appears nowhere in
the emitted runtime. The only reuse is the free list.

**MM-ALLOC-4c (H).** That is one of **two** backing strategies. Which
one a program carries is decided at emission time by
`targetArenaStaticBytes`:

- **Zero**, on every supported target, means the `mmap` above
  (`VirtualAlloc` on Windows).
- **Non-zero** means a single region of that many bytes, reserved once
  at link time. A cursor carves chunks out of it in ten branchless
  instructions. The region's base is either a zero-initialised global
  the linker places, or an absolute address the target names
  (`targetArenaStaticBase`). It must be 16-byte aligned, so that
  `MM-ALLOC-3` holds for every chunk carved from it.

The cursor never rewinds. A reset moves chunks to the free list and
gives no bytes back to the region, so a carve is always memory that
nothing has been handed before. That keeps `MM-ALLOC-6`'s zeroing
promise true of a `.bss` region, just as it is of a fresh mapping.

Exhaustion answers 0, which the `%failed_low` test already treats as a
refused `mmap`. So it reaches `__axiom_out_of_memory` and exits **70**
as usual. Only the trap's sentence differs: it names the region instead
of `mmap`. See `docs/embedded-proposal.md` 4.2 and
`scripts/check-embedded.sh`.

**MM-ALLOC-4b (H).** The free list is **first fit on the whole
mapping**. A chunk is taken if its total size is at least the requested
chunk size, and free chunks are never split and never coalesced. So a
small request may adopt a multi-megabyte free chunk whole, and several
free 1 MiB chunks can never serve one 2 MiB request. When a request
doesn't fit the current chunk, that chunk's remaining tail is
abandoned.

This policy could in principle ratchet memory upward. On a stateless
workload, it doesn't. `scripts/check-net.sh`'s third measurement is built to make it
ratchet: a request handler whose response size cycles from 8 to 488
concatenations, about 1 KiB to 3.8 MiB of intermediates per connection.
That produces and reuses free chunks of many sizes, and crosses the
1 MiB chunk boundary in both directions on every cycle.

Peak worker RSS is 3,968, 4,192 and 4,864 KiB at 1,000, 5,000 and
20,000 connections. It starts at the working set of the largest single
connection, which is the real cost of serving one. It then grows about
47 bytes per connection, which is the per-connection process baseline
the gate establishes with a zero-allocation control, and not the Axiom
heap. The gate asserts the plateau (a run 100× longer must stay within
2× of the short one) rather than a ceiling, because a ceiling would pin
the kernel's socket accounting.

The measurement covers **the stateless case** only: nothing keeps
per-connection state, and the live set at each reset is empty.
Keep-alive, where the live set outlives the request and the arena
boundary stops being free, is outside that measurement and outside this
claim.

**MM-ALLOC-5 (H).** `mmap` returns chunks in **no particular address
order**. No rule in this document may assume that a later chunk has a
higher address. `MM-ALLOC-13` depends on this.

**MM-ALLOC-5a (H).** The dirty watermark errs **in the safe
direction**. Two paths set it to the chunk's *end*, even though most of
that range was never handed out: installing a chunk recycled off the
free list (which is dirty to its last byte), and a reset that crosses
chunks. So `MM-ALLOC-6` may scrub bytes that were already zero, but
never skips bytes that were not.

**MM-ALLOC-5b (H).** The watermark describes **the current
chunk**, so nothing may compare it against an address from another
chunk. This is `MM-ALLOC-5` applied to the allocator's own code.

It matters on `MM-LIFE-2e`'s release path. A block popped off a
size-class free list may come from any chunk the program ever mapped. A
scrub bounded by `min(block end, watermark)` would fail for a block
above the current chunk's watermark: the bound falls *below* the
block's own base, the wipe runs zero times, and the block comes back
**with its previous contents**, breaking `MM-ALLOC-6`. A recycled block
is dirty to its last byte, so the pop path scrubs all of it and leaves
the watermark alone. The two bump-allocating paths are unchanged.

This costs nothing extra, because for a block below the watermark the
bounded scrub already ran to the block's end. With 8 KiB blocks over
20,000 iterations, the bounded scrub took 0.30 s and the full one
0.29 s, with the same peak RSS.

No test reaches the broken case. Reaching it needs `mmap` to place a
later chunk **below** an earlier one. `MM-ALLOC-5` says that may
happen, but no program can force it: the pool, the reset and the free
list all keep the current chunk the newest one. The arena reset also
scrubs the slab heads (`MM-LIFE-2e`), which closes the one route a
program could steer. So the hazard is argued from the code rather than
measured. `tests/stdlib/351-arc-reuse.ax` and
`tests/stdlib/363-arc-large-block.ax` pass with either scrub, so they
don't cover it.

**MM-ALLOC-6 (H).** **Allocation always answers zeroed memory.** The
standard library relies on this. `Map` and `Intern` read an all-zero
state array as "every slot empty", and `strAlloc` reserves a byte for a
NUL terminator and never writes one. The allocator delivers the promise
by scrubbing at hand-out, below the high-water mark, rather than by
relying on the kernel's zeroes. Without the scrub, bytes handed out a
second time after a reset would keep their old contents, and a string
from `strAlloc 3` could measure longer than 3 under `cstrLen`.

**MM-ALLOC-7 (H).** Allocation failure writes
`axiom: out of memory (mmap failed)` (35 bytes) to fd 2 and exits the
process with status 70. There is no recoverable out-of-memory condition
and no way for a program to observe one.

The message is part of the rule. Without it, a worker in a pre-forked
pool that runs out of memory vanishes with only a status, and its
supervisor respawns it with nothing saying why. The trap for 70 has the
same shape as `emitDivTrap`'s for 72 (`MM-EXEC-16`).

Tested by `tests/stdlib/314-out-of-memory.ax`, which asks for 2^60
bytes. The size has to be past the user address space on every target
this compiler emits for, so the mapping is refused rather than merely
unbacked. Smaller sizes aren't enough: macOS overcommits, so a request
for a terabyte succeeds, and FreeBSD 14.4/arm64 (48 bits of user
address space, no overcommit accounting) grants 2^47.

The fixture's `.err` pins the sentence and its `.exit` pins the status,
and neither is checked by the other. A program that prints the right
sentence and exits 0 fails on the status. One that exits 70 in silence
fails on the stderr. The last expression of `main` is a print, not a
numeral. If the allocator ever answers instead of exiting, that print
runs, stdout gains a line, and the golden fails. This pins the rule's
second sentence.

**MM-ALLOC-7a (H).** **A size that no address space can
hold is out of memory, and this is decided before any arithmetic on
it.** A request above 2^62 bytes, which includes every negative `Int`
read as unsigned, takes status 70 with
`axiom: out of memory (allocation size out of range)`. It is
recoverable exactly as the mapping refusal is (`ERR-REC-6`).

Without this check, a negative size would reach the rounding. The
unsigned small-block test would send it to the bump path, the bump
pointer would move backwards, and the next block's header would
overwrite live data. `tests/stdlib/520-alloc-size.ax` pins both halves.
Inside a recovery point, a negative request answers 70 at the arming
call. Outside every recovery point, 2^62 + 1 bytes exits 70 with the
sentence above.

**MM-ALLOC-8 (R; previously **P**).** Refused. The rule
read as follows. The allocator **SHALL** be replaceable by a program
that defines `axiom_alloc`. That program then takes on `MM-ALLOC-6`'s
zeroing and `MM-ALLOC-3`'s alignment obligations. In it, the arena
primitives of §3.3 **SHALL** be refused with a diagnostic, since they
move the position of an allocator that is no longer there.

It was refused because the need behind it went away. `MM-ALLOC-22`
makes the arena scope the reclamation strategy. A program that wants control over reclamation has `__axiom_arena_mark`,
`__axiom_arena_reset` and `__axiom_arena_reset_keeping`, three
primitives a conforming implementation **MUST NOT** refuse. A second,
independent allocator underneath them is a different feature, with no
stated acceptance criteria, and it would interact with the release path
of `MM-LIFE-2e`. Under §0.1, a feature like that needs a fresh rule
with its own acceptance criteria, not a Planned row.

Such a rule would have to show how a replacement upholds `I1`–`I15`.
Nine of those fifteen invariants are about the emitted allocator
itself: the 16-byte header on both allocation paths (`MM-LIFE-2b`), the
4,097 slab-class heads a reset scrubs (`MM-LIFE-2e`), and the chunk
list that `MM-ALLOC-23`'s abort walks. A program-supplied
`axiom_alloc` would have to uphold every one, and the implementation
would have no way to check that it does. That doesn't make it
impossible. It is the acceptance criterion a future **P** rule would
owe.

A real seam would also mean emitting the runtime allocator only when no
declaration named `axiom_alloc` is in scope, and specifying the
required signature: `Int -> Int`, returning 16-byte-aligned zeroed
memory, with failure behaviour. None of that is specified. §9's Planned
column holds `ALLOC-20` alone.

The seam doesn't exist, and the name is refused. An entry-file
definition of `axiom_alloc` is `AX3026` `reserved-runtime-name` at
`check` time. Only the entry file can collide: a module's declaration
is mangled to `Mod$axiom_alloc`, a different symbol. Tested by
`tests/diagnostics/471-reserved-runtime-name.ax`.

**MM-ALLOC-8a (H).** `__alloc` is an **unshadowable primitive name**. A
program may declare a function called `__alloc`, and it type-checks and
is emitted. But every call site is intercepted and lowered to
`axiom_alloc`, so the program's own definition is unreachable code.

**MM-ALLOC-8b (H).** `(__alloc 0)` returns the current bump pointer
**without advancing it**. Before any chunk exists that is the address
0, and afterwards it is an address the next allocation will also
return. A program **MUST NOT** allocate zero bytes.

**MM-ALLOC-8c (H).** Every emitted runtime function carries the
attribute group `#0 = { "no-builtins" }`. Without it, LLVM's loop-idiom
recogniser rewrites the scrub loop of `MM-ALLOC-6` and the copy loop of
`MM-ALLOC-15` into calls to `memset` and `memcpy`. That would be a libc
dependency in a freestanding binary (`MM-ALLOC-1`).

**MM-ALLOC-24 (H). A program can read what the allocator holds.**
`(__axiom_mem_stat k)` answers one of the allocator's own counts, in
bytes, for the calling thread's arena:

| `k` | Count | What it covers |
|---|---|---|
| 0 | held | every byte of the active chunks the bump has handed out: live values, blocks waiting on a size-class list, dead blocks too large for one, unreachable cycles, and each chunk's header and abandoned tail |
| 1 | filed | bytes, headers included, of the blocks on the size-class lists, which the next request of their class reuses |
| 2 | mapped | every chunk byte mapped, active or on the chunk free list; chunks are never unmapped (`MM-ALLOC-4a`), so this only grows |

Any other `k` answers -1. Held less filed is the *backlog*: what an
arena reset would give back and counting hasn't, which is where an
unreachable cycle shows (`MM-LIFE-2f`). The primitive performs `Alloc`,
as `__axiom_arena_mark` does, so no `pure` body depends on it. It is
not `Unsafe`: it names no address and writes nothing.

Filed is one word, slot 0 of `@__axiom_slabs`: a filing adds the
block's bytes, a pop subtracts them, and a reset zeroes the word with
the same scrub that empties the lists. Held and mapped walk the two
chunk lists when asked. So the bump path pays nothing, and a pop or a
filing pays one load, one add and one store. Tested by
`tests/stdlib/557-cycle-backlog.ax` and `tests/stdlib/558-size-classes.ax`;
the executable model predicts filed after every step of every trace
(`scripts/check-runtime-model.sh`).

**MM-ALLOC-25 (H). Size classes: every 16 bytes up to 1 KiB, then
eight per doubling up to 64 KiB.** Every request is rounded to 16
bytes (`MM-ALLOC-3`). One between 1 KiB and 64 KiB is then rounded *up*
to its class, a multiple of 2^(floor(log2(size − 1)) − 3). There are
113 classes: 64 of them 16 bytes apart, then 1,152, 1,280 … 2,048,
2,304 … 4,096, and so on to 65,536. A dead block files on the largest
class not above its size (`MM-LIFE-2e`), so every block on a list is at
least as big as the class it serves, and a block born on a class files
back on it. A popped block keeps its own size in its header.

So a block freed at one size serves every request of its class: 1,100
bytes then 1,150 reuse one 1,152-byte block. The rounding costs at most
an eighth of a block between 1 KiB and 64 KiB, and nothing at or below
1 KiB, where constructors, closures and string headers live. Without
it, each of 4,096 exact classes kept the most blocks it had ever held.
A reset-free loop holding 1,000 strings of random length up to 60,000
bytes, about 30 MB live, peaked at 379 MB after a million replacements
and 478 MB after ten million. With the classes it peaks at 51 MB and
54 MB, and the arena holds 1.7 times the live bytes.

The bound is on the sum of each class's peak, not on the live set:
blocks don't split or coalesce, so a workload whose sizes drift from
one band to another keeps the old band's blocks on their lists until a
reset. A reset-free service whose sizes drift belongs in an arena scope
(`MM-ALLOC-22`). Tested by `tests/stdlib/558-size-classes.ax`, by the
executable model's `classes` witness, which an IR ablation of the
request rounding turns red (`scripts/check-runtime-model.sh`), and by
the soak in `scripts/check-reclaim-soak.sh` section 2, whose ablation of
the same rounding must see memory grow.

### 3.2 What allocates

**MM-ALLOC-9 (H).** These, and only these, allocate:

| Construct | Block |
|---|---|
| a constructor with fields | `(1 + arity) * 8` bytes under representation 0/2 |
| `(struct P ...)` / `(P ...)` for a struct | `fields * 8` bytes, no tag |
| `Str` construction, `strDup`, `strConcat`, `strAlloc` | 2-word header, plus bytes where not shared |
| a `lambda` that is evaluated | closure record, `(1 + captures) * 8` bytes |
| `Vec`, `Map`, `Intern` operations | library-level, over `memAlloc` |
| a `match`'s result | one scratch `alloca` per function, shared by every merge. A cell lives from the store at an arm's end to the load at the merge, with nothing between, so one slot serves nested and tail shapes alike |
| a mixed-representation tag read | the same shared scratch `alloca` (`emitCondTagRead`), with its fall-through zero stored explicitly |
| `__axiom_arena_mark` | a three-word cell |
| `handle` on a declared effect | a two-word evidence record `{handler, previous}`; the form performs `Alloc` |

**MM-ALLOC-9a (H).** An evidence record is released
when its `handle` pops: `MM-LIFE-2c`'s event 7 releases it, and the
block recycles. So entering a `handle` inside a loop doesn't accumulate
records. Tested by `tests/stdlib/355-arc-events.ax`. A `handle` naming
only built-in effects allocates nothing, because it lowers to its body.

**MM-ALLOC-10 (H).** A nullary constructor of an all-nullary or mixed
type allocates **nothing** (`MM-VAL-8`). `(Nil)`, `(None)` and every
other fieldless constructor is an immediate.

**MM-ALLOC-11 (H).** **There is no stack allocation of data.** The
machine stack holds activation frames, spilled registers, and the
`alloca` cell of each `mut` local (`MM-MUT-1`), and nothing else. No
aggregate, closure or string is ever stack-allocated, so no value can
dangle by outliving a frame.

### 3.3 Explicit reclamation

**MM-ALLOC-22 (H). The arena scope is the reclamation strategy, not a
bridge to one.** A conforming implementation **MUST NOT** refuse
`__axiom_arena_mark`, `__axiom_arena_reset` or
`__axiom_arena_reset_keeping`, and **MUST NOT** make them depend on any
automatic strategy. This rule has a new number rather than an edit in
place (§0.1), because it retires a `MUST` that pointed the other way:
`MM-LIFE-2e` ordered all three refused once ARC landed, and
`MM-LIFE-2a`'s ARC is withdrawn (§5, §9).

The **MUST NOT** is unconditional. `MM-ALLOC-8` once reserved the right
to refuse the three inside a program that defines its own
`axiom_alloc`, since they move the position of an allocator that is no
longer there. That seam is **R** and never existed in any build:
defining `axiom_alloc` is `AX3026` at `check`. No program can be in the
state the exception described.

Evidence is a gated workload. `scripts/check-net.sh` builds one
pre-forked server (`tests/net/echo-server.ax`) and runs it twice under
the same load. The only difference is whether a mark and a reset
bracket the request handler. Each connection builds its response by
repeated `strConcat`, leaving about 16 KiB of unreachable intermediates
to reclaim. Peak worker RSS:

| connections | handler scoped | handler unscoped |
|---|---|---|
| 1,000 | **192 KiB** | 19,136 KiB |
| 10,000 | **608 KiB** | 190,128 KiB |

That is 100× at a thousand connections and 313× at ten thousand. The
gate requires at least 50×, which leaves room for a slower machine and
still catches an arena that stopped rewinding. It also carries a
negative probe: the unscoped run **MUST** grow past 2× between the two
loads. Without it, a measurement that read the wrong pid, sampled after the
workers died or read nothing at all would also show a flat column. The
same pair holds the language server at **840 bytes per edit**, against
**193,247** with the boundary removed (`MM-LIFE-2e`).

The target workload is a stateless request/response service. The live
set at the reset is empty by construction, so the boundary costs one
waterline restore and gives back everything the request touched.
`MM-ALLOC-16` remains the obligation for raw mark/reset callers. The
checked `region` form inserts its own mark and reset and rejects the
escapes described by `MM-RGN-1`–`4`. That narrower guarantee does not
validate an arbitrary raw reset. Keep-alive, where per-connection state
outlives the request, is outside the measurement and outside this
rule's claim (`MM-ALLOC-4b`).

**MM-ALLOC-12 (H).** Three primitives move the allocator's position:

```scheme
(__axiom_arena_mark)                        ; -> mark cell
(__axiom_arena_reset mark)                  ; -> 0
(__axiom_arena_reset_keeping mark addr n)   ; -> new address of the kept block
```

A **mark** captures the whole allocator position in a three-word cell:
the bump pointer, the end, and the chunk the bump points into. A bump
pointer alone means nothing once allocation has moved to another chunk.
The cell is allocated *before* the position is read, so it sits below
its own waterline. A reset therefore never reclaims its own mark, and
**the same mark may be reset more than once**.

**MM-ALLOC-13 (H).** A **reset** restores that position and moves every
chunk mapped since the mark onto the free list, where the next refill
finds it. Without the chunk list, a reset could only restore a waterline
and would strand every chunk mapped after the mark. That leak measured
576 KiB per iteration on a loop whose body crosses a chunk boundary.

**MM-ALLOC-14 (H).** **A reset writes no byte of what it reclaims.**
Memory above the restored waterline keeps its contents until it is
handed out again, and then `MM-ALLOC-6` scrubs it. This ordering is
what lets a program read a value *after* the reset that reclaimed it,
for exactly as long as it takes to copy it down.

**MM-ALLOC-15 (H).** `__axiom_arena_reset_keeping` reclaims to the mark
**and** carries one contiguous block across the reclaim in a single
operation. It answers the block's new address. A caller can't build
this from the other two primitives. Written as a reset followed by an
ordinary allocate-and-copy, the destination comes from `axiom_alloc`,
which scrubs it. When the kept block is larger than the garbage around
it, **the scrub runs over the source before the copy reads it**. That
measured 39,841 of 40,000 bytes wrong on the first round. It is the
ordinary case of a server holding a document and answering a short
request.

The copy runs forwards, which covers both directions it can face.
Within one chunk, the source was allocated after the mark, so
`dst <= src`. Across chunks, the ranges are separate mappings that
can't overlap at all, which matters because of `MM-ALLOC-5`. When the
kept block doesn't fit in what remains of the marked chunk, the
destination comes from a **fresh mapping, never the free list**. At
that moment the free list holds the chunks this call just reclaimed,
and one of them may hold the source.

**MM-ALLOC-15a (H).** The destination of `reset_keeping` is **not**
scrubbed, because the copy initialises it. The padding between `bytes`
and the 16-byte rounding holds whatever was there before. No caller can
name those bytes.

**MM-ALLOC-16 (H, program obligation; checked subset in §3.6).** After
a raw reset, no reclaimed allocation may be read again, except through
the new address of the contiguous block carried by `reset_keeping`.
A raw mark or address is an `Int`, and the compiler does not prove this
obligation for arbitrary uses of the primitives. A kept block's fields
are not promoted recursively: each allocation it references must still
outlive every later read. `MM-RGN-1`–`4` provide static checks for the
lexical `region` form and typed origins, not a general validation of
raw words. `MM-ALLOC-16a` and `16b` state the separate dynamic checks
and their limits.

**MM-ALLOC-16b (H, program obligation; implementation obligation).** An
**evidence record is an ordinary arena object** (`MM-ALLOC-9a`) with no
protection from reclamation. A program **MUST NOT** reset past a mark
taken before a `handle` whose extent is still live. The reset reclaims
the evidence record the slot still points at, and **the next operation,
or the extent's own pop, dispatches through it**. The pop does this
because it stores the displaced record back through the reclaimed one.
This is the sharpest case of `MM-ALLOC-16`, because the program never
named the memory in question. An implementation **MUST** detect it and
trap with status **76** (`MM-EXEC-16`).

Without the check, the operation runs on memory the same call has
reclaimed and the program exits 0. With it, the shape this rule names
(mark, then `handle`, then a reset inside the extent, then an operation)
prints `axiom: arena reset past a live handle` on fd 2 and exits 76.
Tested by `tests/stdlib/167-arena-live-handle.ax`.

The test is sound because a non-null slot always names a live extent.
The `handle` pop doesn't null the slot. It stores back the record it
displaced, so a completed extent leaves the slot exactly as it found
it, and the outermost pop leaves it 0. A stale pointer from a finished
`handle` therefore can't cause a false positive. Two shapes that look
like false positives are not:

- A record recycled off a size-class free list (`MM-LIFE-2e`) can sit
  *below* the waterline. The reset doesn't reach it, and the range test
  is correctly silent.
- `emitEffectOp` installs the *displaced* record for the duration of a
  handler call. That record is older than the current one, so it can
  only under-report.

The recovery path needs no exemption and has none.
`__axiom_recover_abort` *is* an arena reset across a live extent; that
is its job (`MM-ALLOC-23`). But `emitRecoverRuntime` calls
`@__axiom_recover_load` *before* `@__axiom_arena_reset_fn`. By the time
the check runs, every slot holds its arm-time value, which was installed
before the arm and so sits below the arm's mark. The test is false on
its own. `tests/stdlib/401-recover-effect.ax`, which aborts out of a
live `handle`, still exits 71 with unchanged stdout.

Not detected: a reset performed lexically **inside a handler body**.
For the duration of that call the slot holds the displaced record, so
the innermost record is in no slot at all. That shape remains a program
obligation.

A program that declares no effect pays nothing, byte for byte. The
check is emitted only when the program has at least one evidence slot.
At zero slots, `emitLiveHandleTrap` and `emitEvCheck` both answer `cg`
unchanged, so no trap, message constant or call is written.
`tests/stdlib/010-hello.ax` and `tests/stdlib/160-arena.ax` emit
byte-identical IR with and without the check. `self_host/` declares no
effect at all, so the compiler itself is in that class.

**MM-ALLOC-16a (H, program obligation; implementation obligation).**
Marks **MUST** be reset in nesting order, innermost first. Resetting an
inner mark after its outer mark has been reset is a **fault the
implementation MUST detect**. An implementation **MUST NOT** restore an
allocator position from a mark whose chunk is no longer on the active
list, and **MUST** trap with status **75** (`MM-EXEC-16`) instead.

Take a program that marks an outer position, allocates past a chunk,
marks an inner position, resets the outer mark, resets the inner mark,
then allocates. Without the check, it writes and reads back a word in a
chunk the same call has just pushed onto the free list, and exits 0.
With it, the program prints `axiom: arena reset to an invalid mark` on
fd 2 and exits 75. Tested by `tests/stdlib/166-arena-bad-mark.ax`.

In `@__axiom_arena_reset_fn`, the unwind walk has two ways to stop. It
finds the marked chunk (`%reached`), or it runs off the end of the
active list without finding it (`%ranout`), which is this fault. The two
conditions branch separately, and `%ranout` calls `@__axiom_bad_mark`.

Not detected, by design: resetting the **same** mark twice is legal and
stays silent. A mark cell is allocated before the position it saves is
read, so it sits below its own waterline and no reset reclaims it. After
the first reset, `@__axiom_chunk` *is* the marked chunk, so
`@__axiom_arena_reset_fn` takes its equal-chunk fast path and never
enters the unwind walk (see the comment in `emitArenaHelpers`). The
fixture asserts this silence.

The check costs nothing measurable. It adds no comparison: the two stop
conditions each get their own branch instead of sharing one merged
`%stop`. Everything before `unwind:` is
byte-identical in the emitted IR, so the equal-chunk fast path, which a
bracketed request handler takes on nearly every reset, is untouched.
`scripts/check-arena-reset-rate.sh`, alternating two compilers built
one branch apart on a busy machine, measured:

| | per-reset |
|---|---|
| with the split branch | 2.146, 2.142, 2.517, 3.012 µs |
| with the merged `%stop` | 2.849, 2.200 µs |

The two sets interleave, so the change doesn't show above run-to-run
spread. Both sit above §9.0's **1.35 µs** because that figure, taken on
an idle machine, is a floor for the *workload*, not a threshold.

A correct use looks like the "managed" variant of
`scripts/measure-memory-baseline.sh`. Mark once before the loop. Each
iteration computes the next value, copies it *up*, resets to the mark,
and copies *down* from the up-copy. The up-copy's bytes sit above the
restored pointer and survive by `MM-ALLOC-14`. Memory stays flat at
about 1.4 MiB from 80 through 20,000 generations. The same loop
unbracketed grows by about 16 KiB per generation, forever.

**MM-ALLOC-23 (H, renumbered from a second `MM-ALLOC-17`). A trap may
abort to a mark, and the abort discharges `MM-ALLOC-16b` on its own
path.** `(__axiom_recover mark thunk)` arms a recovery point and runs
`thunk`. Out of memory (70), an unhandled effect (71) and a division by
zero (72) then answer the *arming call* with their status, instead of
writing to fd 2 and exiting. With nothing armed, they behave as they
always do. Recovery points nest, and an abort takes the innermost armed
one. That is `MM-ALLOC-16a`'s ordering rule, and here the mechanism
enforces it for the program.

The abort restores three things and runs nothing: the stack pointer,
the arena (a reset to `mark`, `MM-ALLOC-13`), and every evidence slot.
The third makes it sound where a program calling `__axiom_arena_reset`
by hand is not. `MM-ALLOC-16b` is a *program obligation* because a
reset can't know which `handle` extents it cuts through. An abort can:
the arm site snapshots every slot into the recovery record before the
extent begins, and the abort writes them all back before the reset. On
this one path, the sharpest case of `MM-ALLOC-16` is discharged
mechanically.

The recovery point's record, which holds the saved stack and registers,
the mark, the displaced point and the evidence snapshot, is a cell in
the arming function's own frame. The abort jumps back into that frame,
so the record is intact when it lands, and arming allocates nothing:
10,000 arms whose thunk answers leave the arena where it was
(`tests/stdlib/560-recover-record.ax`). An arm still evaluates its mark
argument, and `__axiom_arena_mark` allocates a cell that no reset
reclaims (`MM-ALLOC-12`), so a loop that writes
`(__axiom_recover __axiom_arena_mark thunk)` pays 48 bytes an arm. Take
the mark once, before the loop.

The jump abandons N frames of pending `axiom_release` calls. They are
harmless because of `MM-ALLOC-14` and `MM-LIFE-2e`: the reset reclaims
everything above the mark regardless of any count, and scrubs all 4,097
slab heads first, so nothing filed survives to be issued twice. What is
*not* free is a retain taken on a block **below** the mark whose
matching release was above it. `emitHandleDyn` takes one on the record
its push displaces, and `emitPrimRecover` takes one on a thunk that
isn't a lambda built at the call. Those counts are abandoned.

The residue is bounded by the number of aborts, not by the work inside
them. With 100,000 aborts and a `handle` inside every aborted extent,
max RSS holds at **1,376 KiB**, byte-identical at 10,000 and at
100,000. The same program with the trap removed, so nothing ever
resets, reaches **419,328 KiB** (`scripts/check-recover.sh`).

This is not unwinding, and won't become it. There is no landing pad, no cleanup, no
resumption and no way to catch anything at a chosen frame. A recovery
point can only contain one of the three traps. `ERR-REC-6` in
[the error model](error-model.md) states what that does and doesn't
buy.

Two rules follow. The compiler checks the first, and the second is a
program obligation:

- **Nothing older than the point may be made to hold what the thunk
  allocated.** The abort reclaims everything the thunk allocated, so a
  structure older than the point would keep a block the next
  allocation reuses. A thunk is checked as a region is: written as a
  lambda at the call, it is walked by the region pass, and storing
  anything it allocates into an older structure, such as growing a
  `Vec` made before the arm, is `AX3060`. A top-level function passed
  by name captures nothing and passes. Any other thunk is `AX3090`,
  because its body was never walked there
  (`tests/diagnostics/1033-recover-escape.ax`). Carry the thunk's
  answer out as the arming call's result and store it afterwards
  (`tests/stdlib/561-failed-operations.ax` case 3).
- **Resources the thunk acquired stay acquired.** A file descriptor
  opened in an aborted extent stays open, a shared mapping stays mapped
  and a mutex stays locked: the runtime can't know they were taken.
  Acquire them outside the point, or release them before anything in
  the extent can trap. The one resource the runtime owns, a child
  spawned inside the extent, is swept by the abort (`MM-PAR-7`).
  `scripts/check-reclaim-soak.sh` section 5 measures both halves.

### 3.4 The inferred arena model — withdrawn

This section specified the model the roadmap sketched: per-activation
arenas with escape promotion and a tail-call reset. **The
reference-counting decision of `MM-LIFE-2a` superseded it**, as worked
out in `MM-LIFE-2b`–`2f`, and §10 records why. Its rules stay under
§0.1's convention: withdrawn, numbered, cited, never deleted.

**`MM-LIFE-2a` was itself later withdrawn** in favour of `MM-ALLOC-22`'s
arena scope. A rule superseded by a rule that is later withdrawn does
**not** revive. This section lost on its own measurements, and none of
them has moved. `MM-ALLOC-19`'s tail-call reset could be discharged only
by a copy, a linearity proof or region inference, and the copy was
built, gated and measured corrupting memory (§10). What replaced it is
an arena the *program* brackets, not one the compiler infers.

Two rules keep their content. `MM-ALLOC-20` is the prerequisite for
*any* automatic strategy and is not withdrawn. `MM-ALLOC-21`'s
write-barrier obligation lives on as the field-store event of
`MM-LIFE-2c`.

**MM-ALLOC-17 (W).** Each function activation **SHALL** have an implicit
arena. A value allocated during the activation and not escaping it
**SHALL** be reclaimed when the activation returns, by restoring the
watermark: O(1) per activation, with no per-object bookkeeping.

*Today:* nothing is reclaimed at return. Peak memory is proportional to
total allocation.

*Withdrawn:* the returning-frame case is `MM-LIFE-2c`'s event 3.
Frame-owned references are released at return, per object rather than
per watermark, and without needing to know what escaped.

**MM-ALLOC-18 (W).** A value that **escapes** (returned, stored into a
longer-lived structure, or captured by an escaping closure) **SHALL**
be allocated in the caller's arena instead. This is Tofte–Talpin region
inference with the annotations removed. That is why `region` was
deleted from the surface syntax: an annotation the compiler can derive
is one that will eventually be wrong.

*Today:* an escape analysis exists, and it arrived with counting rather
than with regions. `escapes` and `escapesViaBinders`
(`self_host/codegen.ax`), over the two call-graph fixpoints
`inferOwnership` and `inferFlows`, decide whether a frame-owned
reference may outlive the frame that built it. The walk shipped with
`MM-LIFE-2c`'s events 2 and 3.

*Withdrawn:* counting doesn't need *region* inference. Its walk asks one
local question, whether this release may fire here, where this rule
asked which arena a value belongs in. Ownership then follows the
reference wherever it is stored (`MM-LIFE-2c`, events 2 and 6).

*Amended:* `region` is back in the surface syntax as `MM-RGN-1`'s
checked scope (§3.6). It is a scope the program brackets, which is what
§3.4's own verdict asked for, and not the annotation this rule said the
compiler would derive. The sentences above describe the inferred model,
not the keyword.

**MM-ALLOC-19 (W).** A **self tail call SHALL reset its activation's
arena to the entry watermark**, and this is the rule that matters. A
tail-recursive loop never returns, so `MM-ALLOC-17` alone reclaims
nothing from the one shape every compiler pass, request handler and
macro expansion has:

```scheme
(advance (step board) (- n 1))
```

The reset is sound only if the new argument doesn't point into the
memory being reclaimed. There are three ways to discharge that
obligation, in increasing order of ambition:

| Discharge | Mechanism | Cost |
|---|---|---|
| **A. Copy at the boundary** | carry the new argument across the reset with `MM-ALLOC-15` | O(live) per iteration; always sound |
| **B. Linear consumption** | require the loop parameter to be linear, so the old value is provably dead | needs `MM-LIFE-7`; changes signatures |
| **C. Full region inference** | region-annotated types for the whole program | most precise; most research risk |

**A SHALL be implemented first**, because it is sound and simple, turns
the measured curve from linear into constant, and builds the machinery
the other two need. That machinery is already built and gated
(`MM-ALLOC-12`–`MM-ALLOC-16`, `tests/stdlib/165-arena-keep.ax`). What
remains is for the compiler to *insert* it.

*Withdrawn:* under ARC the same boundary reclaims with no copy and no
discharge obligation at all (`MM-LIFE-2c`, event 4). This rule was the
hard case of the arena design, and its dissolving is most of the reason
the design lost (§10).

**MM-ALLOC-20 (P).** Before any automatic reclamation strategy
(`MM-LIFE-2a`'s ARC, the withdrawn rules above, or any collector) can be
implemented, **the implementation MUST be able to tell a pointer from
an integer**. It can't today, for two independent reasons, and both are
prerequisites rather than details:

1. **No runtime discrimination. Partly resolved.** A word carries no
   tag (`MM-VAL-2`), but a heap block now knows its own words.
   `MM-LIFE-2b`'s header exists on every allocation path.
   `MM-LIFE-2d`'s monomorphic half writes the shape word's reference map
   at constructor and struct sites from the *declared* field types, so
   release walks a dead block's fields transitively. A type variable
   still hides pointerhood from *static* classification, and the
   evidence word now answers that at run time (`MM-LIFE-2d`'s evidence
   half). Roots remain untrackable until the ownership events
   land (`MM-LIFE-2c`).
2. **No static discrimination. Resolved.** `String` and `Int` were once
   unified in `tyCompat`, a compatibility rule that made `Int` the
   universal heap-handle type. That rule is gone. A string is a `String`
   to the checker everywhere in the compiler, the standard library and
   the corpus, and the containers carry type variables instead.
   `(+ 1 "hi")` is `AX3004`
   (`tests/diagnostics/555-string-int-distinct.ax`). String *equality*
   survives through the content rewrite, which answers `Bool` ahead of
   the numeric matrix. Static discrimination still can't see through a
   type *variable*, which hides pointerhood by design. `MM-LIFE-2d`'s
   evidence word is the answer to that, not more checking.

A conforming implementation of automatic reclamation **MUST** first
introduce a type-level distinction between a heap handle and an
integer. That is the static half, whose measured progress `MM-LIFE-2a`
quotes. `MM-LIFE-2d` adds the runtime half: a per-block reference map,
plus pointerhood evidence where a type variable hides the answer.

This rule exists because a compiler-inserted copy has already been
tried without it: the `ArenaCompact` instruction, removed rather than
finished (the self-hosting record). It misidentified a `Vec` header as a
constructor cell, wrote past the end of its chunk, and couldn't see
`Str` or `Vec` at all.

**MM-ALLOC-21 (W).** Mutation and arenas interact. The roadmap didn't
account for this, because it assumed Axiom's data is immutable, and it
isn't (`MM-MUT-2`). A field store can install a reference to a
*younger* value into an *older* one:

```scheme
(set old.next young)     ; `young` now outlives `young`'s arena
```

A conforming implementation of escape promotion **MUST** therefore treat
the target of a field store as an escape of the stored value into the
target's arena. A generational collector discharges the same obligation
with a write barrier. Without it, a per-activation arena reclaims memory
that an older value still points at.

*Withdrawn with the model, but the obligation remains.* It is
`MM-LIFE-2c`'s event 5, where a field store retains the stored value and
releases the overwritten one. It is the same barrier, holding a count
instead of promoting an arena.

---

<a id="35-cast-degrades-the-evidence-word--measured"></a>
### 3.5 `cast` degrades the evidence word

**MM-VAL-22 (H, renumbered from a second `MM-LIFE-2e`). A
type-preserving cast preserves ownership and evidence.** When checking
proves that a cast's operand and target have the same type, the result
keeps the operand's ownership. An owned temporary moves through the
cast; a borrowed reference remains borrowed. Calls, bindings and
discarded expressions use the same cleanup decision as the operand.
Scalar casts take no reference share.

`checkCastForm` records this proof as `nodeResWord` 3. It is distinct
from word-result evidence and region freshness. `evStampFill`,
`valueOwnedRef` and `escapes` spend the proof without treating an
unproved reinterpretation as an owned reference.

A cast that changes the type still receives evidence 0 at an argument
root. Erasing a reference to a word makes its lifetime the programmer's
obligation. Forging a reference requires `effect(unsafe)` and a valid
representation (`MM-EXEC-9d`).

Evidence: [check-cast-arg-root.sh](../scripts/check-cast-arg-root.sh)
compares releases with the uncast spelling and a scalar control.
[701-cast-ownership.ax](../tests/stdlib/701-cast-ownership.ax) checks
exactly one destructor call through temporary, binding, discard,
polymorphic, borrowed-alias and nested-cast paths.

**MM-VAL-23 (H, renumbered from a second `MM-LIFE-2f`). The safe
vehicle for a reinterpreted word is a typed accessor.** Put the cast at a
*return*, inside a function whose declared type states the truth.
Callers then see that declared type, and the evidence word is computed
from it:

```scheme
;@axiom:raw
(:: getStr (-> Int Int String))
;@axiom:effect(unsafe)
;@axiom:precondition(word `i` at `a` holds a live `String`)
(fn (getStr a i) (cast String (memGetWord a i)))

(memSetWord p 0 (getStr p 0))     ; evidence word 1, releases emitted
```

The cast still forges a reference out of a word, so the accessor says
`effect(unsafe)`, and the word it trusts is its caller's to vouch for
(`MM-EXEC-9d`).

The accessor's declared type must match what the word holds. A default
value cannot establish the type of a stored word. Use a typed container
or a reader whose precondition identifies the stored representation.

### 3.6 Checked lexical regions

This section is the authoritative contract for the `MM-RGN-*` rules.
The [design record](memory-model-v2-design.md) keeps the measurements
and the rejected proposals, but it isn't a second specification. It
reserved these rule numbers with status **D**. The status each rule
carries here is what shipped, and planned behaviour is stated
separately.

The guarantees cover the typed origins the analysis tracks. They don't
make arbitrary `Int` addresses, foreign memory or raw reset calls safe.

**MM-RGN-1 (H). A region is a lexical allocation scope.**
`(region r EXPR)` binds the region name `r` over `EXPR`. On entry, the
emitted code saves the current bump pointer, end and chunk in a
three-word stack cell. On normal return it resets the allocator to that
saved position and answers the body's scalar result.

- Rebinding a live region name inside itself is refused (`AX3058`).
- A reference-valued result is refused (`AX3059`). A region form never
  promotes a heap result for you.
- Recovery has its own reset and unwind contract (`MM-ALLOC-23`).

```scheme
(import IO)
(import Str)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((id 42))
    (let ((n (region r (strLen (format "GET /orders/{id}")))))
      { (println "rendered {n} bytes") 0 })))
```

```text
rendered 14 bytes
```

The string is built inside `r` and reclaimed when `r` ends. Only its
length, an `Int`, leaves. Answering the string itself is refused:

```scheme refused
(import IO)
(import Str)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((id 42))
    (let ((s (region r (format "GET /orders/{id}"))))
      { (println s) 0 })))
```

```text
error[AX3059]: region `r` answers a value of type `String`, which may point into the memory the region reclaims
```

Evidence: [codegen.ax](../self_host/codegen.ax), `emitRegion` and
`emitRegionCell`; [typecheck.ax](../self_host/typecheck.ax),
`rgTyScalar`; [check-region-scope.sh](../scripts/check-region-scope.sh),
with its unsafe-escape ablation and its no-region and two-region
controls; [168-region.ax](../tests/stdlib/168-region.ax).

**MM-RGN-2 (H). Region extents nest.** For lexical regions, an extent
outlives itself and its descendants, and siblings are unordered. In a
region-annotated signature, each distinct named region outlives the
caller's current allocation region and its lexical descendants, but
different named regions are unordered. This is the ordering the checker
declares, not lifetime inference at run time. A signature can't promise
a result region that no parameter supplies (`AX3063`). A `parallel`
binding doesn't create a typed sibling region yet (`MM-RGN-7`).

Evidence: [typecheck.ax](../self_host/typecheck.ax), `rgnOutlives`,
`rgnFormNestedIn`, and `rgnWalkFn` for the result region;
[646-region-escape-return.ax](../tests/diagnostics/646-region-escape-return.ax)
and [648-region-argument.ax](../tests/diagnostics/648-region-argument.ax),
held by [check-region-escape.sh](../scripts/check-region-escape.sh).

**MM-RGN-3 (H, within the tracked-origin domain). The escape rule.**
A reference **MUST NOT** be stored into, returned into, or captured by
an object whose region outlives any region that reference depends on.
The checker enforces this with five refusals:

| Code | What it refuses |
|---|---|
| `AX3059` | a non-scalar value leaving a region as its result, or through a direct store to an outer binding |
| `AX3060` | a store, including one made inside a callee |
| `AX3061` | a return that doesn't match the declared result region |
| `AX3062` | an escaping capture |
| `AX3063` | region arguments that don't agree |

`AX3059` is a scope check on the region form. The other four come
from the region facts. The pass that reports them runs over function
bodies when the program contains a region form or a region-annotated
signature.

Facts propagate through resolved calls to a fixpoint. An unresolved
call may store arguments and fresh values into any argument or capture.
Its result depends on those captures too. This conservative rule can
refuse a call whose body would be safe.

The checker refuses unrepresentable origins and unconverged facts as
`AX3060`. Each function can track 61 parameter and lexical-extent
origins together. An annotation alone adds no extent origin. Split a
function that exceeds the capacity instead of relying on an incomplete
lifetime proof.

This is not a proof about arbitrary words. Erased addresses, hand-built
layouts and raw mark and reset calls keep the obligations of
`MM-ALLOC-16` and `MM-LIFE-2g`. The dynamic checks on marks and live
evidence are still needed (`MM-ALLOC-16a`, `MM-ALLOC-16b`), and the
region rule doesn't replace them.

Evidence: [typecheck.ax](../self_host/typecheck.ax), `rgnCheckAll`,
`rgnEnsureFacts`, `rgnStoreOk`, `rgnUnknownCall`.
[check-region-escape.sh](../scripts/check-region-escape.sh) tests each
refusal, and ablates the rule to expose the read of reclaimed memory.
[653-region-escape-callee.ax](../tests/diagnostics/653-region-escape-callee.ax)
pins the store made by an unannotated callee, beside the accepted cases
in [479-region-reclaim.ax](../tests/stdlib/479-region-reclaim.ax).
The same gate covers callback captures and origin capacity, with
[escape-closure-call.ax](../tests/region/escape-closure-call.ax) beside
the accepted [closure-local.ax](../tests/region/closure-local.ax).

**MM-RGN-4 (H, amended from the design default). Origins are
inferred, not invariant.** A function without region
annotations allocates in its caller's current region. Its parameter and
result origins come from the facts of its body, and they aren't forced
to be identical. So reading an outer string inside a shorter region is
legal, while a call that stores a fresh inner value into an outer
container is refused. This replaces the design's proposal that every
reference parameter and result be invariant. Region annotations add no
runtime arguments and don't select another allocation arena.

A program with no region form emits no lexical-region mark cell.
Annotations alone leave the emitted program unchanged, apart from
source-location attribution. Evidence:
[check-region-scope.sh](../scripts/check-region-scope.sh) and
[check-region-escape.sh](../scripts/check-region-escape.sh), which
compares its annotated fixture with a stripped twin.

`restrict(no-escape)` reads the same facts. It claims that a function
stores none of its fresh allocations into its parameters. It doesn't
claim that the function allocates nothing or returns no reference. A
proven violation is `AX3049`. An unresolved call or a truncated
analysis is `AX3051`, or `AX3057` under `strict`. `AX3051` is a
warning: the claim is unverified, not proven. Evidence:
`restrictNoEscape` in [typecheck.ax](../self_host/typecheck.ax),
[649-restrict-no-escape.ax](../tests/diagnostics/649-restrict-no-escape.ax)
and [check-restrictions.sh](../scripts/check-restrictions.sh).

**MM-RGN-5 (W, design withdrawn).** The proposed rule was: “A
region-polymorphic function takes one hidden trailing word per region
parameter, holding that region's mark cell.” It was never implemented,
and `MM-RGN-5a` replaces its role as a freshness witness. Nothing under
this identifier allocates into an arbitrary outer region or checks
erased addresses at run time. Passing a mark wouldn't, by itself, let
the current bump allocator allocate below an inner region's waterline.
[The design record](memory-model-v2-design.md) keeps the decision and
its measurement, in §2.5 and §4.

**MM-RGN-5a (H). Freshness evidence is a compile-time stamp.** Once the
region facts converge, the reporting walk stamps `nodeResWord` 2 on a
call result it proves fresh, and on a join whose every arm is already
stamped. The stamp is not a runtime word. It is withheld for unresolved
or aliasing results, and when the facts truncate.

Codegen spends the stamp only at the implemented release sites inside a
lexical region. It clears the region depth when it emits a lambda body,
because the lambda can run after the enclosing region has ended.
Tail-call ownership classification stays conservative, even when an
ordinary release is elided.

Evidence: `rgnStamping`, `rgnCheckAll`, `rgnApp`, `rgnArms` in
[typecheck.ax](../self_host/typecheck.ax); `releaseOwnedArgs`,
`emitLetAt`, `releaseScrutinee` in [codegen.ax](../self_host/codegen.ax).
The call, binding, join and scrutinee paths each have an ablation check:
[check-region-fresh.sh](../scripts/check-region-fresh.sh),
[check-region-fresh-let.sh](../scripts/check-region-fresh-let.sh),
[check-region-phi.sh](../scripts/check-region-phi.sh),
[check-region-phi-let.sh](../scripts/check-region-phi-let.sh), and
[check-region-scrutinee.sh](../scripts/check-region-scrutinee.sh).

**MM-RGN-6 (H, narrowed from the design proposal). Regions and counting
compose.** A region reset reclaims its extent whatever the reference
counts say. Inside the region, the emitter omits only the releases that
the implemented construction or freshness checks prove are covered. All
other counting traffic is still emitted, including field-store ownership
transfers, unknown or borrowed results, and foreign destruction paths.
Outside a region, those checks never justify dropping a release that
reclaims. Static-literal release elision is separate: it applies without
a region, because the sentinel release was already inert.

Two phrases from the design proposal don't describe the implementation:

- “Reference counting survives only where a value outlives its region”
  is withdrawn as a universal description. It doesn't promise to remove
  every retain and release inside a region.
- “In one pointer move” describes the waterline, not the cost of the
  whole reset. A reset also clears 4,097 size-class heads and walks
  surplus chunks, so counting's free lists can't hold on to reclaimed
  storage.

A reset doesn't run a destructor for each reclaimed object. A program
must close any external resource that needs destruction before a raw
reset discards its last handle.

`reset_keeping` copies one contiguous block (`MM-ALLOC-15`). It is not
typed recursive promotion, so retaining a field doesn't make that field
survive the reset. Cycles wholly inside a reset extent are discarded
with it. Counting alone still doesn't collect cycles (`MM-LIFE-3`).

Evidence: `emitArenaHelpers`, `isRegionCoveredCon` and the release
sites in [codegen.ax](../self_host/codegen.ax);
[check-region-reclaim.sh](../scripts/check-region-reclaim.sh),
[check-static-release.sh](../scripts/check-static-release.sh),
[check-arena-reset-rate.sh](../scripts/check-arena-reset-rate.sh), and
[check-region-verdict.sh](../scripts/check-region-verdict.sh). The
verdict compares answers, emitted releases, aggregate code size (the
text section, not file bytes) and peak RSS against an ablated compiler. It makes no
wall-clock or worst-case execution-time claim.

**MM-RGN-7 (P; the surface and word transport are H). Regions for
`parallel`.** The proposed `parallel` contract needs typed sibling task
regions, with results transferred into the parent's region at the join.
None of this is implemented yet: the region nodes, the typed transfer of
heap results, and accepting safe shared captures on the strength of a
region proof. It remains planned, and in the current compiler it
doesn't follow from `MM-RGN-3`.

Today, `parallel` desugars to spawn and join calls. It uses processes by
default, and `--threads` selects the supported thread lowering. Each
binding answers an `Int` word, and results are joined in the order
written. `AX3064` conservatively refuses counted or `Vec` captures and
opaque thunk shapes. Raw addresses can still be carried as words, and
sharing a `Foreign` value is the foreign side's responsibility.
`MM-PAR-5` to `MM-PAR-8` and `MM-FFI-7` give the transport, cleanup and
capture contracts.

Evidence: `mkParallel` in [parser.ax](../self_host/parser.ax),
`checkSpawnCaptures` in [typecheck.ax](../self_host/typecheck.ax),
[check-parallel.sh](../scripts/check-parallel.sh) and
[check-thread-local.sh](../scripts/check-thread-local.sh).

---

## 4. Mutation

**MM-MUT-1 (H).** `(let ((mut x e)) ...)` introduces a mutable local,
which `(set x v)` assigns. It lowers to an `alloca` with loads and
stores, is invisible outside its function, and is captured by snapshot
(`MM-VAL-16`). It performs no effect, because nothing else can observe
a local's mutation.

```scheme
(:: main Int)
(fn (main)
  (let ((mut x 0))
    { (set x 3) x }))
```

`axiom emit-llvm` shows the slot:

```llvm
define i64 @__axiom_user_main() #0 {
  %.s0 = alloca i64
  store i64 0, ptr %.s0
  store i64 3, ptr %.s0
  %.t1 = load i64, ptr %.s0
  ret i64 %.t1
}
```

**MM-MUT-1a (H).** `set` on a binding that a lambda only captured, and
`set` on a function parameter, are both refused by the checker with
`AX3012`. Each case gets its own message. A parameter is immutable and
has no `mut` spelling to suggest. A captured binding may well be `mut`,
but the lambda holds its value (`MM-VAL-16`), so a store could never be
observed. `AX4002` in codegen stays as a backstop in case the check
ever misses one. Tested by `tests/diagnostics/465-set-on-parameter.ax`
and `466-set-captured.ax`.

**MM-MUT-2 (H).** `(set e.f v)` stores into a heap field in place, and
every alias of `e` sees the write. It performs the `Mut` effect, because
unlike a local's mutation it is visible elsewhere. The form evaluates to
`0`, and its static type is `I64`. That doesn't stop it being the value
of a function that returns `Int`: `(fn (bump p) (set p.x 1))` declared
`(-> P Int)` checks `OK` when `P` declares `(mut x : Int)`.

```scheme
(import IO)

(struct P
  (mut x : Int)
  (y : Int))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((p (P 1 2)) (q p))
    {
      (set p.x 99)
      (let ((seen q.x))
        (println "q.x is {seen}"))
      0
    }))
```

```text
q.x is 99
```

**MM-MUT-2a (H).** The field must be declared `mut`. A store into a
field that isn't is `AX3012`, reported at the field name in the write.
This is the `let` rule applied to fields. Only the last segment of a
path is governed: `(set a.b.c v)` needs `c` declared `mut` and says
nothing about `b`, because the store changes the value `b` points at,
not the `b` slot. `memSetWord` is outside the rule entirely. It takes a
block and a word index, which is how `Vec` and `Map` write slots that
aren't fields.

**MM-MUT-3 (H).** Field stores work only on named fields of a `struct`
type. A `data` constructor's positional fields have no name to store
through (`AX2001`), and a struct variant's fields are reachable only by
pattern match (`AX3007`). So constructed `data` values are immutable in
practice: no rule forbids a store into one, but there is no way to
write it.

**MM-MUT-4 (H, program obligation).** There are no aliasing
restrictions. Any number of names may refer to one heap block. The
language has no uniqueness, no borrow checking and no read-only
reference. A program that relies on a value not changing under it
**MUST** copy it, with `strDup` or an explicit rebuild.

**MM-MUT-5 (H).** The standard library's containers are mutable in
place, not persistent. `vecPush` mutates and returns the handle it was
given, so a `Vec` keeps its identity as it grows, even though its data
buffer moves. `Map` rehashes in place. We made this trade because the
containers serve a compiler that runs in milliseconds. It means no
structure in `stdlib/` is safe to share across a mutation.

**MM-MUT-5a (H).** `vecSet`, like `vecGet`, **MUST** trap with status
**77** when the index is negative or at least the vector's length. The
check comes before the element store and any ownership change, so a
recovered failed write leaves the vector unchanged. This checks the
index into a valid vector. It doesn't validate a forged vector handle,
or prove that an element read through a typed raw-word accessor has
that type. Evidence: [Vec.ax](../stdlib/Vec.ax), `vecSet`, and
[525-vec-set-bounds.ax](../tests/stdlib/525-vec-set-bounds.ax).

**MM-MUT-6 (R).** Axiom provides no persistent data structures, and no
structural sharing beyond `strSlice`'s byte sharing (`MM-VAL-7`). A
program that needs them builds them from `data` types, which are
immutable by `MM-MUT-3` and so share freely and safely.

---

## 5. Lifetimes and reclamation

**MM-LIFE-1 (H).** Memory is reclaimed by two mechanisms working
together: explicit arena and region resets (`MM-ALLOC-22`, `MM-RGN-6`),
and the reference-counting events the compiler already emits
(`MM-LIFE-2c`). The counting roadmap is withdrawn, but its header,
reference maps, ownership events and release path are all implemented.
When a block's count reaches zero, its mapped children are released,
and eligible small blocks are reused through size-class lists. Larger
blocks wait for an arena reset. A lexical region reclaims its extent
whatever those counts say.

There is no tracing collector. A value that nobody releases stays
allocated until its arena is reset or its process ends. A thread's
arena is also unmapped when the thread completes (`MM-PAR-6a`). `Handle`
provides the explicit foreign destructor path (`MM-FFI-6`); it isn't a
universal finalizer. `MM-LIFE-4` and [the audit](assurance/memory-audit.md)
cover the lifetime cases and the unsafe obligations. Evidence:
[the ownership-event fixture](../tests/stdlib/355-arc-events.ax),
[container reclamation](../scripts/check-container-reclaim.sh), and
[region scopes](../scripts/check-region-scope.sh).

**MM-LIFE-2a (W). Reference counting as the reclamation strategy.**
Withdrawn, and superseded by `MM-ALLOC-22`. It is withdrawn in the
sense §0.3 calls *abandoned in place*: part of it shipped, still emits,
and still costs something, as the end of this rule describes. Nothing
below is a plan.

The withdrawn rule: automatic reclamation **SHALL** be automatic
reference counting. Every heap block gains a count. The compiler emits
a retain where a reference is copied into a longer-lived place, and a
release where one dies. A block whose count reaches zero is reclaimed
at once, so reclamation is deterministic. That is the property
`MM-LIFE-7`'s `consume` was introduced to express, obtained without
linear types.

Cycles leak, and the rule accepted that cost. `MM-LIFE-3` shows that
cycles can be built, one way with nothing but `stdlib/Vec`, so counting
alone doesn't reclaim everything, and this specification **MUST NOT**
claim otherwise. Counting is memory-safe, since a live object is never
freed, and incomplete, since an unreachable cycle is never freed. Swift
makes the same bargain.

Counting needs to know which words are references (`MM-ALLOC-20`). The
static half of that is in place. The `String`/`Int` fiat, the rule in
`tyCompat` that made the two types interchangeable, is deleted, and the
checker sees a string as a `String` throughout the compiler, the
standard library and the test corpus
(`tests/diagnostics/555-string-int-distinct.ax`). The containers carry
type variables instead, and their accessors `cast` at the machine
boundary. A signature's type variable is rigid inside its own body, so
such a body needs an explicit `cast a`. Typing the tree changed no generated code,
because `String` and `Int` share a representation and `cast` is free.

`MM-LIFE-2b` to `MM-LIFE-2f` give what the strategy needs from the
machine: a count word, the ownership events, a reference map, a release
path in the allocator, and a stated cycle obligation. Each says what
happens today, and each is withdrawn with this rule, in the same sense.

The arena replaced it because Axiom's target workload is a stateless
request/response service, and the reclamation that fits it is the arena
scope. `MM-ALLOC-22` measures a request handler bracketed by a mark and
a reset at 100–313× less memory than the same binary unscoped, checked
with a negative probe. The same pair holds the language server at 840
bytes per edit, against 193,247 with the boundary removed. The arena is
the strategy, not a bridge to counting. Reference counting is no longer
scheduled, and no rule in this document may cite `MM-LIFE-2a` as
something to come.

Withdrawing the strategy doesn't remove the half that landed. That
half is emitted on every build:

- `MM-LIFE-2b`'s 16-byte header is on both allocation paths.
- All seven of `MM-LIFE-2c`'s ownership events emit
  (`tests/stdlib/355-arc-events.ax`, `361-arc-field-store.ax`,
  `362-arc-tail-boundary.ax`, `364-arc-frame-release.ax`,
  `372-arc-owned-results.ax`).
- `MM-LIFE-2d`'s monomorphic, evidence and `Str` halves hold.
- `MM-LIFE-2g`'s `__retainref` is on the hottest store in the compiler.
- `MM-LIFE-2e`'s release path files dead blocks onto `@__axiom_slabs`.

Removing any of it is a compiler change with its own measurements, not
a documentation edit. The same machinery took the compiler's
self-compile from 2.93 s to 1.94 s, and from 314 MiB to 248 MiB. This
document describes it in the present tense.

**What it costs: 1.7–1.8% of each request.**
`__axiom_arena_reset_fn` scrubs 4,097 slab heads on every reset, the
path `MM-ALLOC-22`'s workload takes once per request. It has to,
because releases file blocks into those heads. A head left dangling
across a reset hands out the same storage twice on the next allocation
of that size class. Counting bought the scrub, and the arena pays for
it on every request.

`scripts/check-arena-reset-rate.sh` attributes the cost by running one
program in three spellings, each a word apart. At `--opt 1` a reset
takes about 1.35 µs and a mark under 10 ns. That is 1.7–1.8% of a
per-connection budget near 77 µs.

The budget comes from two workers serving 5,000 loopback connections,
with the same binary either side of its arena flag: 12,864 and 12,986
conn/s scoped, against 13,282 and 13,032 unscoped. Those runs overlap,
so the cost can't be read off them. They couldn't isolate the scrub
anyway: `tests/net/echo-server.ax` takes `__axiom_arena_mark`
unconditionally and puts only the reset behind the flag, so its two
arms remove the whole reset, not just the scrub.

Two of the six checks in `scripts/check-arena-reset-rate.sh` use no
clock at all. One asserts the emitted scrub from the IR. The negative
probe deletes that block and rebuilds, and the cost drops 42×. §9.0
closes `MM-LIFE-2a`'s row on that ground: a change in this cost would
now be caught.

The residue is the price of combining §3.3 with counting at all, and it
stays while `MM-LIFE-2a` is abandoned in place. It is small, so it
doesn't argue for putting the strategy back on the schedule. It is also
large enough to act on.

**MM-LIFE-2b (W, abandoned in place; see `MM-LIFE-2a`). The count
word.** What already emits is recorded below, and it stays. Every
counted block **SHALL** carry a 16-byte header immediately below its
address:

- word −2 is the reference count;
- word −1 is the shape word of `MM-LIFE-2d`, which carries the block's
  word count as well as its reference map.

Release needs both: the map to walk the dead block's fields, and the
size to hand the block to the right free list (`MM-LIFE-2e`). A block
that didn't record its own size would make the release path impossible
to implement against `MM-VAL-6`'s blocks, which record nothing about
themselves.

The block's own address and every field offset are unchanged. The
header is invisible to every existing consumer. Only `axiom_alloc`,
retain, release and the map writer know it is there. It costs exactly
16 bytes per counted block: `MM-ALLOC-3` rounds every size to a
multiple of 16, so the header moves each block up by one rounding step
and never more.

Three classes of word are exempt, each by a check that already exists:

- **Immediates.** A word below 4096 is a tag, not an address
  (`MM-VAL-9`, `I3`). Retain and release on a reference-typed position
  **MUST** skip it, with the same compare a mixed-representation
  `match` already emits. Rep-1 values and rep-2 nullary constructors
  therefore cost nothing, just as they allocate nothing
  (`MM-ALLOC-10`).
- **Statics.** A literal's header and bytes are loader-resident and
  **MUST NOT** be written (`MM-FFI-2`). The emitter **SHALL** lay static
  constants out under the same header shape, with the count word all
  ones. Retain and release **MUST** read the count first and leave a
  sentinel untouched: a static is never reclaimed, and never written,
  even by the machinery that reclaims.
- **Non-reference positions.** An `Int`, `Float`, `Bool` or `Char`
  position is never retained or released. The decision is static, which
  is why `MM-ALLOC-20` is a prerequisite rather than an optimisation.

*Holds* (`tests/stdlib/350-arc-header.ax`, exit 22). A raw `__alloc`
block's count word reads 0 at birth, and `__retain` and `__release`
move it. The release that takes the count to zero files the block, and
a further release is a no-op (`MM-LIFE-2k`). A literal's all-ones count
is read and never written, and a negative immediate is skipped by the
signed compare.

The header is written on both allocation paths: `axiom_alloc`, and the
arena keep helper, which the language server crosses on every message.
`MM-LIFE-2e` makes the allocator write the shape word's size, and
`MM-LIFE-2d` defines the word's encoding and its map writers.

This rule amends `MM-VAL-6` by two words of self-description and no
more. A block still does not know its type. It knows its count and,
through the shape word, its size and which of its words are
references.

**MM-LIFE-2c (W, abandoned in place; see `MM-LIFE-2a`). Ownership.**
What already emits is recorded below and stays. Each event is a place
where the compiler **SHALL** emit a retain (+1), a release (−1,
reclaiming at zero), or, where the event says so, neither:

1. **A call borrows its arguments.** There is no retain at the call
   boundary. The caller's frame outlives the callee's (`MM-ALLOC-11`:
   frames strictly nest and the stack holds no data), so the caller's
   ownership covers the callee's use.
2. **A function returns its result owned.** The caller receives +1 and
   must release it, store it, or return it in turn. Returning a
   borrowed argument therefore retains it first.
3. **Frame slots own.** A reference bound or `set` into a local slot is
   owned by the slot: an owned value moves in, and a borrowed one is
   retained on the way in. `(set x v)` releases the owned value it
   overwrites (`MM-MUT-1`), which is sound because the slot retained
   what it holds, whatever its provenance. A returning frame, or event
   4's boundary, releases every live owned slot that did not escape by
   being returned or stored. The elision licence below keeps the
   common borrow, bind and read shape free of count traffic.
4. **A self tail call is a release boundary, and its function owns its
   reference parameters.** Entry retains each reference parameter
   once. Without that, the first iteration would hold its arguments
   borrowed while every later one holds them owned, and no caller frame
   is left to do the borrowing (`MM-EXEC-6b` replaces the frame with a
   branch). Owned references that are dead across the call are released
   before control branches back to `MM-EXEC-6b`'s loop header.

   This event replaces the withdrawn `MM-ALLOC-19`, and it is the reason
   for the strategy. The loop shape that defeats per-activation arenas,
   the activation that never returns, reclaims each dead generation at
   the boundary. It needs no copy, no linearity requirement and no
   region inference, so the trilemma `MM-ALLOC-19` tabulated dissolves.
   The sharing that made copying at the boundary corrupt (`MM-ALLOC-15`'s
   reason to exist) is plain arithmetic under counts: substructure the
   new generation shares ends the release walk at a nonzero count.
5. **A field store retains the new value and releases the old**
   (`(set e.f v)`, `MM-MUT-2`). This is `MM-ALLOC-21`'s old-to-young
   obligation, which outlives that rule's withdrawal. It is a write
   barrier by another name, and it is why mutation composes with
   counting when it did not compose with arena inference.
6. **Building a block stores its reference fields owned.** That covers
   constructor fields, struct fields, closure captures and both words
   of an evidence record. `MM-VAL-15`'s over-capture now has a price: a
   captured reference is a retained reference.
7. **`handle` releases its evidence record at exit**, which closes
   `MM-ALLOC-9a`'s sixteen bytes per loop entry.

A callee that ends a parameter's share *consumes* it, and neither event
1 nor event 3 applies to that handoff. `Map.mapFree`'s `(__release
(cast Int m))` ends the caller's share, so a `let`-bound map passed to
it takes no scope-end release, and an owned temporary handed to it is
not released after the call. The compiler records this in
`FSig.consume` (`fnConsumeMask` in `self_host/codegen.ax`), computed in
the flow fixpoint beside `stash`. Every caller-side release decision
reads it. The return path never does, because a consumed parameter
still owes its slot release there. Without it, the map is released
twice, by the free and at the scope end: silent at small scale, a
segfault at a thousand iterations (issue #35; `tests/stdlib/489-map-free.ax` and the `chain`
arm of `scripts/check-container-reclaim.sh`).

A conforming implementation **MAY** cancel a retain against a release it
can pair statically. The licence costs nothing observable. A conforming
program observes no address (`MM-EXEC-12`), so reclamation timing shows
only as peak RSS. Determinism (`MM-EXEC-11`) holds, because counts are a
function of program text and input, never of layout.

*Holds in part* (`tests/stdlib/355-arc-events.ax`, exit 7, which
reclaims with no `__retain` or `__release` in its source;
`tests/stdlib/352-arc-shape.ax` and `354-arc-evidence.ax` hold under
the same arithmetic). What emits:

- Every block the compiler builds to create ownership is born at count
  1, the constructing expression's own share: constructor cells, struct
  blocks, closure records and evidence records. Raw `__alloc`,
  `memAlloc` and `strWrap` stay born at 0, because a second birth would
  double-count every `String`.
- Event 6's field retains happen at construction. They follow the shape
  word's classification exactly, and a directly built argument moves
  into its field instead of being retained.
- Event 7 releases the evidence record when the handler is popped, so a
  `handle` in a loop recycles its record: a thousand entries move the
  bump by less than 8 KiB.
- A directly built construction discarded in statement position is
  released on the spot.

The slice's rule: every retain it emits is one an existing reference
map can hand back.

**Event 5 emits** (`tests/stdlib/361-arc-field-store.ax`, exit 63; a
compiler without it answers 7). `(set e.f v)` into a reference field
retains the new value and then releases the one it overwrites, so a
self-assignment cannot free what it just stored. A thousand overwrites
of one field with a fresh 48-byte string move the bump by under 4 KiB.

Its balance is local and provable without escape analysis. A mapped
field's old value is owned by the block, because the store that put it
there took a share: `emitFieldStores` at construction, or this same
store earlier. Handing that share back is arithmetic, not a judgement
about who else holds it. The classification is `fldClass`'s, the same
one that wrote the block's map, so the release set and the walk set
cannot disagree.

That argument needs every field to have a type `fldClass` can classify.
A field written without its `:`, such as `(struct Box (msg String))`,
would get the empty type variable. It would then fall out of the map
and out of this retain, and a value stored in it would be freed under
the program (exit 139, SIGSEGV). The compiler refuses such a field at
its declaration with `AX3056`
(`tests/diagnostics/388-struct-field-untyped.ax`).

**Event 5b, the closure half, emits** (`tests/stdlib/460-closure-reclaim.ax`,
exit 255; `scripts/check-closure-reclaim.sh`). An application through a
closure gives back the intermediate record a curried chain builds.
Every function value absorbs exactly one argument, so a two-argument
handler is a chain. The record its first step answers is born at count
1 and nothing else holds it. Once the next step has loaded that
record's code pointer and called it, the share is the walker's to
return.

Its balance is local in event 5's sense, with no escape analysis,
because the record is one this walk made. The two chain walkers,
`emitApplyRegsOwned` and `emitApplyChainOwned`, carry `recOwned` to
tell it from a record the caller handed in. A handler out of the
evidence slot, or a closure value another `let` holds, is never theirs
to release. Left unreleased, the intermediate costs 32 bytes per
application.

The other half is the owned argument a closure application consumes,
which a direct call releases under `MM-LIFE-2g`. It rests on a
prerequisite: a lifted lambda takes an evidence word for its own
argument, so a store inside one takes its share like any other store.
Term 64 of `460-closure-reclaim.ax` checks that a parked argument
survives the application because the park is counted.

With the park counted, the walkers release the last step's argument
when all of these hold:

- the argument is owned, and neither static nor nullary;
- the checker's stamped answer is a word (`nodeResWord`, proven words
  only: `Int`, `Float`, `Bool`, `Char` and the empty tuple, and never
  `Vec`, which takes no share while still being a block).

Intermediate steps keep their arguments, because the next step loads
the answer's word 0 as a code pointer and so may alias them. Surplus
arguments, from the `cast` spine and the over-applied tail, keep theirs
too: they are unmeasured, not known to be safe. `stdlib/Fallible.ax`
records both halves at 0 bytes per operation, and
`tests/stdlib/410-fallible.ax` term `e` pins the built-message case.
`scripts/check-closure-reclaim.sh` ablates the `nodeResWord` stamp and
requires term `e`, and nothing else, to fail.

**Event 4 emits** (`tests/stdlib/362-arc-tail-boundary.ax`, exit 63).
This is the event the strategy exists for: the activation that never
returns, which no per-activation arena can reclaim. A tail loop that
allocates a fresh 32-byte string each iteration and drops the previous
one moves the bump by 480 bytes over 2,000 iterations. Without the
event, the same run moves it 224,304 bytes.

The emitted shape:

1. Before the loop header, retain each reference parameter once. That
   turns the caller's borrow (event 1) into a share this frame owns.
2. At each jump, retain every new value, release every old one, and
   only then store. The order matters: a parameter passed through
   unchanged, the common shape, would otherwise release the block it is
   about to keep.
3. At the return, release the last iteration's shares, after the tail
   leaf has taken its own share (event 2) and before the `ret`
   (`releaseRefParamSlots`).

The declared type decides which parameters take part, through
`fldClass`. That is the same classifier that writes a block's reference
map, so the release set agrees with every other ownership decision in
this backend. An `Int` parameter is never retained or released, which
is why `MM-LIFE-2e`'s Life probe is untouched: its board is a `Vec`
behind `(-> Int Int Int)`.

What made this event unsafe was the stashes, not its arithmetic, and
`MM-LIFE-2g` closed that. The fixture asserts both halves, because
either alone leads to the wrong conclusion. With the event but without
`memSetWord`'s share, the loop is still flat, yet a `Vec` element
pushed 300 boundaries earlier reads a length of 2: freed, re-issued and
read back as garbage.

Closure captures follow the same logic. A lambda captures everything in
scope, so a closure escaping the loop would hold a parameter the next
boundary releases. A capture that is a reference parameter of the
enclosing function therefore takes a share. A captured `let` binding
stays unretained, because nothing releases a binding a lambda mentions
(event 3 treats the lambda as an escape). The rule is "retain what
something else may hand back", not "retain every capture".

**Event 3 emits** (`tests/stdlib/364-arc-frame-release.ax`, exit 127).
A `let` binding whose initialiser is a direct construction is released
when its scope ends, unless the binding can outlive the frame. Events 2
and 3 below widen the initialiser to any owned value.

The initialiser condition makes the frame the owner: the block is born
at count 1, and that birth is the binding's. The escape condition is a
positional walk. The release is emitted at the binding's scope end, in
the block that defines its register, not before the function's `ret`,
because a `let` inside a branch defines a register that does not
dominate the return.

What the walk permits is the part that matters. Each permission is a
place where an ownership event already guarantees a share:

- Passing the binding to a function in statement or argument position
  is a borrow (event 1). Every store a callee can make takes a share: a
  field store by event 5, a constructor field by event 6, and a
  container or any other word store through `memSetWord`, which retains
  by `MM-LIFE-2g`.
- Sequencing, conditions and loops move no value out.
- A read of a machine-scalar field answers a word.

The binding escapes wherever that guarantee stops:

- when it is the `let`'s own value, since nothing took a share on the
  way out;
- when a lambda mentions it, since a capture takes no share
  (`MM-VAL-15`);
- when it is the right-hand side of a `set`, since a slot store takes
  none;
- under `cast`, `__addr`, `strData` or `strOwner`, the four ways to get
  a word out of a reference, which counting cannot see (`MM-LIFE-2g`'s
  own stated limit).

A tag the walk does not recognise answers "escapes", so the permitted
surface grows only when someone edits the walk.

Three more cases escape, each found where a permission above was too
generous. First, a reference field read in value position. Reading a
field answers the field, not the block, but the field's share belongs
to the block, and the block's death hands it back. Released at the end
of its `let`, `b` here would take its string with it, and the `match`
would answer freed storage:

```scheme
(let ((b (Mk (strConcat "id-" t))))
  (match b ((Mk s) s)))
```

Second, a `match` binder, which is the same field under another name.
It is asked the same question in the match's own position: value
position, or any position for a `set` right-hand side or a lambda.

Third, a call whose arguments mention the binding, when the callee
stashes that parameter or, in value position with a word result, may
answer it (the callee's own flow masks, under "Where an argument goes"
below). A callee whose result is a counted reference answers a share of
its own (event 2), so the argument's share is untouched.

A parameter or local that merely shares a global's name is a function
value nothing signed, so every argument it is given escapes. A `let`
whose initialiser may alias the block asks the question again of its
own binder. Each of these cases errs toward a leak, never an early
free.
`tests/selfhost/997-let-box-value-escapes.ax` holds eight spellings.

Measured in five directions:

| Record | Bump growth | Released |
|---|---|---|
| built, read and dropped, 20,000 calls | 256 bytes (640,224 without the event) | yes |
| built, passed to a function and dropped, 20,000 calls | 256 bytes (640,224 without the event) | yes |
| returned from `keep` and read by `readA`, 5,000 iterations | under 4,096 bytes | yes |
| its word escapes through a `cast`, 5,000 iterations | 291,328 bytes | no |
| captured by a lambda, 5,000 iterations | 400,224 bytes | no |

The last two must grow: a release there would free a block something
else still names.

Direct constructions alone barely reach the compiler itself. It builds
its records through `mk*` functions that return `Int`-declared handles,
which is also why `MM-LIFE-2e`'s acceptance measurements cannot move.
This part of the event is for programs.

**Events 2 and 3 emit, with owned temporaries**
(`tests/stdlib/372-arc-owned-results.ax`, where every shape reads 0
bytes per iteration). Event 2 makes every reference result one share
the caller holds, and event 3 releases a `let` bound to such a call.

The key is adoption. A string that `strConcat` builds is born through
`__alloc` at count 0: free-floating, and owned by nobody until a store
takes the first share. The `A1` comment on `storeCountOneAt` states the
convention: constructors are born at 1, while raw allocation and
`strWrap` stay at 0 and "the type-gated machinery supplies their +1
elsewhere". Retaining such a result to 1 is not a leak. It is the
adoption the allocator leaves to the type layer.

Two things go wrong without the analysis below. Retaining a result that
already carries a share leaks. Releasing only `let`-bound results
reclaims nothing, because every temporary in argument position keeps
its share forever. A version that retained every tail that was not a
direct construction did both: it added 285 retain sites for 8 release
sites to the compiler's own IR and reclaimed nothing.

The pair is sound and cheap once the emitter knows who owns each
result, who releases it, and where each argument goes. It learns these
from three fixpoints over the call graph (`inferOwnership` and
`inferFlows` in `self_host/codegen.ax`):

<!-- doc-gate:negative-exempt narrative: a definition of the ownership lattice. The negative quantifier belongs to the BORROWED arm and has nothing to do with the test corpus. -->
- **Who owns a result.** A signed global's result is *owned* when every
  tail its body can answer is a construction, a literal (statics are
  immortal), a lambda, or a call to a reference-returning global, which
  by this same rule answers one share. It is *borrowed* when some tail
  is a parameter, a field read, a match binder, a raw load or a raw
  allocation. This is a greatest fixpoint, so recursion through an
  owned-result function stays owned.

  Event 2 follows from this. A reference-returning global retains each
  borrowed tail leaf as it is emitted, not at `ret`, so a body owned on
  one branch and borrowed on another retains only the borrowed branch.
  Every reference-returning global therefore hands its caller exactly
  one share. `strWrapOwned`'s `(cast String s)` of a raw allocation is
  where every string is adopted, once.
- **Who releases it.** Event 3 releases a `let` bound to any owned
  reference value, unless the escape walk says it escapes. An owned
  value is a direct construction, or a call to a reference-returning
  global applied at its arity, joined over `if`, `match`, `let` and a
  block. An owned value discarded in statement position is released on
  the spot. An owned temporary is released:
  - once the call returns, when it is passed to a global whose result
    is a word or a reference;
  - right after the store, when it is stored into a constructor's or
    struct's reference field, which retained it;
  - after the merge, when it is a `match`'s scrutinee and no binder
    escapes.
- **Where an argument goes.** A callee can do one thing to an argument
  that counting does not see: erase its type. It can park the argument
  in a field declared `Int` through a `cast`, in a mutable slot through
  `set`, in raw memory through `__store64`, or in a closure's record.
  It can also hand it to a callee that does one of those. For example, `mkDiag`
  parks its message through `(cast Int msg)`. Each signed global
  therefore carries a stash mask and a ret mask (`FSig.stash` and
  `FSig.ret`), both least fixpoints.

The stash mask names the parameters a function parks in one of those
ways. A `__retainref` or `__retain` of the parameter makes the store
counted and cancels the bit, as in `memSetWord`, `mkNode` and
`strSlice`.

The ret mask names the parameters whose reference may be part of a word
the function answers. That happens through `cast`, `__addr`, `strData`,
`strOwner`, or a 64-bit load of a header word past index 0. Other loads
answer scalars: word 0 of a handle is a length, a header's own count
and shape words are numbers, and a byte is never a pointer. So
`strLen`, `strByte` and a count probe answer scalars.

Each mask has three forms per parameter:

- the *arrival*: the parameter as it came, a typed reference or a type
  variable's value;
- the *header word*: the handle laundered through `cast`, `__addr` or
  arithmetic (an `Int` parameter arrives as one);
- the *owner word*: `strData`, `strOwner` or a header word past index
  0, a pointer to or into the block the string's header owns.

A count cancels a park of the same thing. `__retainref` counts a typed
arrival only. `__retain` counts what it is given: a header in both
header forms, and an owner as the owner. So `strSlice` and
`sysReadAll`, which retain the owner and park the owner, are balanced,
while a retain of the owner licenses no park of the header.

A count is credited only to what the retained expression must be: the
parameter, a `cast` of it, or a `let` alias of either, and only one
parameter. It is never credited to a field, a binder or a join, so a
match binder's `__retainref` never stands for its scrutinee.

A callee's arrival bit and owner bit are *strong* parks: whatever it is
given there is parked, uncounted. An owner word is never what
`__retainref` counted, so `(__store64 m 0 (strData s))` keeps a typed
`s` alive at the call, at the loop's boundary and at its exit. The
header bit is a *weak* park: it parks only when a header word arrives,
because a typed arrival is counted. So `memSetWord` of a typed string
is counted, and `memSetWord` of `(cast Int s)` parks `s` however it
arrived. A polymorphic `put` that forwards its parameter to
`memSetWord` inherits the weak bit.

The flow analysis follows values through a few more places:

- A `mut` slot's flow is its initialiser joined with every `set` in its
  scope, to a fixpoint, so what is parked or answered through the slot
  is seen.
- Arithmetic and `&&`/`||` pass their position to their operands.
- The word-taking heads look through a reference-returning call or a
  construction to its arguments: `(strOwner (strSlice s 1 3))` is the
  owner of `s`.

Counts pair with stashes per path. Every `if` test, `if` branch,
`while` condition, `while` body, `match` arm, right operand of
`&&`/`||`, and `handle` handler is a region. A count cancels a stash in
its own region or in one it encloses. It never cancels one in a sibling
region, or in a test it does not dominate. An `if` test parks on the
false path, where its branch's count never runs, and a `handle` naming
only built-in effects never evaluates its handler.

A temporary is not released past a callee that stashes or answers it,
and the escape walk treats such an argument as the binding escaping. A
`(set k v)` makes the binding escape when `v` flows it or parks it,
through a lambda capturing it, a constructor's word field or a callee
that stashes. A `v` that is only a length computed from the binding
does not. Retaining at every `cast` instead was measured and rejected:
`strLen` and `strData` are casts, and every string in the compiler grew
a share per read.

The self-tail-call boundary retains each new slot value, releases an
owned temporary's own share, and releases the old slot value. Three
kinds of parameter are exceptions, and keep the share their slot
holds:

- A parameter passed through as itself, the shape of every linear
  scan. Its slot keeps the block it had. The traffic is skipped while
  the name still resolves to the slot, and paid when a `let` shadows
  it.
- A parameter the function parks a word of, recorded in its own stash
  mask. For example, `parseModPathRest` hands `acc` to `pOk`, which
  stores it through a `cast`. The slot's share is the stash's keeper,
  so neither the boundary nor the return path takes it back, and the
  parked value holds exactly one share.
- A parameter the function answers a word of, such as `(cast Int s)`
  as a tail. The word has no other keeper, so the block leaks rather
  than dangles.

The pass-through skip is what makes the reclaiming compiler faster
than the leaking one. Without it, the new releases in the scans raised
the time from 1.7 s to 2.1 s.

A type-variable slot is retained and released by evidence. Entry
retains it by the word the call arrived with. The boundary retains the
new value by the next iteration's word, and releases the old one by
the word that was current for it. The exit releases by the word
current then. So a typed reference arriving there holds exactly one
share, and an arriving word is parked: that is the weak header bit,
which only a word-form argument pairs with.

An `Int` slot stays a park. Whatever flows into it, such as a `let`'s
word through a helper or a parameter's header, is never released at
the jump or by the caller. That errs in the leak direction, which is
the safe one.

A function value, meaning a bare reference to a top-level function, is
born at count 1, like a lambda. Born at 0, it would be adopted by a
record it was stored in, and freed under the frame still calling it.

The release walk has no depth. A dead record is linked into a dead
list through its own count word, which is dead storage from that
moment and becomes the free-list link once the block is filed. The
drain pops one record at a time, releases what its map names, then
files it. A child that dies joins the list and is never recursed into.
There is no recursion and no auxiliary stack: the walk uses one word
the block already owns.

A walk that recurses fails on some long chain. A recursive walk crashes the
process on a 400,000-cell list (`tests/selfhost/700-tco.ax`).
Deferring the last field does the same for a link that isn't last. A
4,096-entry worklist with a recursive fallback does the same for
`(Cons String L)`, where each of 170,000 levels leaves a string pending
until the chain ends. The drain drops a 1,000,000-cell list in either
field order, a 400,000-level caterpillar tree and a 20-deep full tree,
all whole, in 0.45 s and 129 MiB
(`tests/selfhost/994-deep-release-first-field.ax`).

On the compiler compiling itself (emit-llvm of `self_host/main.ax`,
same machine and load for both), reclamation takes the time from
2.93 s to 1.94 s and the peak from 314 to 248 MiB. Release
sites go from 143 to 5,817 and retain sites from 399 to 559, with
`stage2 == stage3`. The compiler is a third faster and a fifth smaller
because it reclaims its own strings and stops counting what a scan
passes through.

`tests/stdlib/372-arc-owned-results.ax` measures the bytes the arena
grows per iteration over 10,000 iterations, on six shapes:

1. a record with a `fmtInt`+`strConcat` String field, read through an
   accessor;
2. `(strLen (fmtInt i))`;
3. a `let`-bound `strConcat`;
4. a record with a static field;
5. `(Some (fmtInt i))`, matched;
6. a String answered borrowed through two helpers.

All six read 0. The previous compiler read 80, 80, 80, 0, 112 and 0.

The instrument is the mark cell's bump word, not the cell's address.
The cell is a 24-byte block, and once any block that size has died,
the allocator hands the next cell out from a free list. So two cells'
addresses say nothing about growth under reclamation. By the bump
word, the previous compiler reads 80, then crosses chunks.

The return path completes event 4. The TCO prologue retains every
reference parameter into its slot, and the boundary keeps the slots
balanced per jump. The return path then releases the last iteration's
shares, after the tail leaf has taken its own. Without that, every
self-recursive function would leak one share of each reference
parameter per call. A temporary handed to a self tail call hands its
share back after the boundary retain, as after any call.

A join is owned when every arm is owned: a construction, a static, a
call to a reference-returning global, or a nullary constructor such as
`None` or `Nil`, which is an immediate that costs nothing to release.
So `(if c (Some x) None)` gives its `Some` back, where the previous
compiler leaked 104 bytes per iteration. A `set` makes a
binding escape only when the binding, or a word of it, reaches the
slot. A length or a sum computed from it doesn't.

These still leak, which is the safe direction:

- a temporary passed to a primitive, to a `cast`, to a local function
  value, or to a function whose result is a type variable, since none
  of those retains what it hands back;
- a temporary that a `match` binder escapes from;
- a temporary stored through `set`;
- a `let` whose value is a field of the block it binds;
- a join of an owned temporary with a borrowed arm (a parameter or a
  field) stored into a field: the field retains, and the owned arm's
  birth share has no path back;
- a polymorphic self-tail-call loop matching an owned `(Some x)`;
- a `let` cast to `Int` in value position, kept whole (in argument
  position, its consumer decides, by the masks);
- a self-tail-calling function's `Int` slots, and a parameter whose
  word it parks or answers, which keep their slot's share;
- blocks above the 64 KiB pool ceiling, which are never filed;
- the free list's order, which a rebuild of a 1,000,000-cell list
  scrambles a little more each generation.

A function whose result is a type variable retains nothing on return,
so a `let` bound to `(vecGet v i)` is never released. The compiler is
written to that container convention.

These cases don't leak:

- A closure record carries a reference map for the captures it
  retained (the reference-class parameters), so its death hands them
  back.
- A lambda captures only the names its body mentions. Capturing every
  name in scope would chain a closure built per loop iteration to the
  one before it, through a parameter it never uses.
- A lambda handed to a self tail call is an owned temporary at the
  boundary.
- A `handle` as a reference-returning tail retains once.

The next rule removes what blocked counting in containers and in the
compiler's own data. Whether a store emits a retain is decided by
`fldClass`, from the declared type of the place stored into. The
containers store through `memSetWord`, where the checker sees a machine
word, and `ASTNode` declares all ten of its fields `Int`. Without the
rule, a `String` whose header count reads 0 still reads **0** after it
is pushed into a `Vec` and interned into an `Intern`. Stored into a
struct field, the same string reads **0** through a field declared
`Int` and **1** through a field declared `String`. Every reference the
compiler holds in its own data structures would be in the first group.

Freeing early is worse than leaking. Entry retains a reference
parameter and the boundary releases it, which balances for the
parameter. But the value an iteration is about to drop reached count 1
only through that entry retain, so the boundary release takes it to 0
and files the block. If any iteration stashed it where counting could
not follow, that stash now points into a block on a size-class free
list, which `axiom_alloc` pops before bumping. The next allocation of
that size hands the same bytes to someone else. Under-reclaiming leaks,
while this frees early, and the two are not symmetric.

**MM-LIFE-2g (H). The invisible-store rule.** A store that erases a
value's type **SHALL** take a share of it. This implementation has
exactly two such places, and both are a `cast Int` inside a polymorphic
function:

- `Mem.memSetWord`, which every container and every raw word store
  goes through;
- the AST's `mkNode`/`mkNodeAt`, whose three payload words are
  `ASTNode`'s `Int`-declared fields.

The share is taken by `__retainref`, `__retain`'s type-directed twin,
and the only primitive designed with a polymorphic signature. It
retains exactly when its argument is a reference, and the call's
evidence stamp (`MM-LIFE-2d`) decides that:

- a constant, for a known type;
- a bit of the caller's own evidence word, for a type variable;
- nothing emitted at all, for an `Int`.

That last case makes the rule affordable on the hottest store in the
compiler: a tag, a span or a length costs zero instructions. With the
rule, self-compile takes 1.22 s and 492.6 MiB peak RSS, against 1.24 s
and 492.4 MiB without it.

A lambda parameter needs one more step. `bindLamParams` binds it to a
minted placeholder, and `evClassOf` answers a placeholder `-1`, which
means "says nothing" rather than "not a reference". On that answer
alone, no `__retainref` would be emitted for a parameter that is a
reference, and a parked reference would sit in its container uncounted.

That would be an observable use-after-free. The open event-5b leak
(`MM-LIFE-2c`) doesn't cancel it: that leak only offsets a release a
closure call would emit. Event 5 is a release from a different frame
that never consults the closure, and it is enough on its own. Under the
placeholder answer,
three programs that differ in one ingredient each read `strByte` of
the recorded value, at `--opt 0` through `--opt 3` alike:

| the closure parks | then | reads |
|---|---|---|
| a struct field's value | the field is overwritten | **`z`**, a string allocated after |
| a fresh temporary | the field is overwritten | `a`, correct |
| a struct field's value | nothing | `a`, correct |

Both ingredients are needed, and neither is exotic. The field holds the
only counted share, the closure's park takes none, and the overwrite
releases the last share while the closure's container still points at
the block. The program is a factory returning a logging closure over a
`Session` whose `name` is recorded and then reassigned. It uses no
`cast`, no `__load64` and no header arithmetic, and `axiom check`
prints `OK`.

Two changes close it, and they close different things.

First, `checkLamAgainst` binds the type the author wrote instead of a
placeholder, and a `fn` whose declared result is an arrow and whose
body is a lambda checks through it. That reaches the factory above and
nothing else, because the guard is syntactic.

Second, the evidence word reaches the rest. A lifted lambda takes a
hidden `%__evwa.h` for its own argument, and the application passes
it:

- `applyOneArg` emits it as a third operand.
- `emitLamDef` and `emitThunkDef` both declare it. Every code pointer a
  closure record can hold must take it, whether or not it reads it.
- `emitEvWordVal` turns the witness `EV_LAMARG` into a retain under
  bit 0 of that word.
- The checker names the one placeholder an application can witness,
  `curLamVar`, the innermost lambda's own parameter. It records each
  application's argument class on the `E_APP` node, for `walkAppChain`
  to read back beside the arguments.

Together, the two changes fix all seven shapes measured, at `--opt 0`
and `--opt 3` alike:

| the shape | without the changes | with them |
|---|---|---|
| a factory's declared result, where the body is the lambda | `z` | **`a`** |
| a `let` inside the factory | `z` | **`a`** |
| an `if` in the factory | `z` | **`a`** |
| no factory at all: bound and applied in `main` | `z` | **`a`** |
| passed to a declared arrow parameter | `z` | **`a`** |
| forced by a use in its own body before the park | `z` | **`a`** |
| a declared result arrow carrying a type variable | `z` | **`a`** |

The last row needs the most care. `(:: mk (-> Int (-> a Int)))` emits a
correct chain end to end: `mk` takes `%__evw.h` and stores it in the
closure record, and the lambda loads it, shifts bit k and retains under
it. That alone still under-retains, because `a` appears only in `mk`'s
result. Nothing at `mk`'s call site witnesses it, so the caller passes
the constant `0`. A value of type `a` doesn't exist until the closure
is applied.

So `checkLamAgainst` names a type-variable parameter in `curLamVar`,
and `evClassOf` answers it `EV_LAMARG`. The application's word beats
the enclosing function's, which arrives as 0. This is sound because
the evidence word is a fact about a type, not a value. Inside the
body, `a` may denote several values: the parameter, a capture of the
same type, a temporary. But a type variable denotes one type
throughout its scope. If the application hands over a `String` for
`a`, every `a` in that body is a `String`, captures included. Nothing
can shadow it, because type variables come from the signature being
checked and expressions can't introduce their own.

Two probes check the reasoning as well as the conclusion. A lambda
whose parameter and a capture share `a` parks both and answers
correctly. The same factory applied at `Int` stores and reads back
`41`: evidence `0`, no retain, and no count on an integer.

Evidence words travel by depth. The parser turns `(lambda (a b) ..)`
into `(lambda (a) (lambda (b) ..))`, so by the time a store runs, `a`
is a capture inside the inner lambda, whose own word is about `b`. The
word that classifies `a` is the one the outer application passed. So:

- `curLamVar` is a stack, not a single name;
- `evClassOf` answers `EV_LAMARG - d` for a parameter `d` lambdas out;
- `collectCapNames` takes the enclosing lambdas' words into the nested
  record, as it takes the enclosing function's;
- `bindCaps` shifts each word one level as it binds.

Every lambda's own argument is therefore depth 0, and no witness is
renumbered after the fact. Without depth, `(lambda (a b) (vecPush log
a))` is a live use-after-free: it reads `z` where the same lambda
parking `b` reads `a`. `tests/stdlib/461-curried-closure-arg.ax` pins
four depths across two- and three-parameter lambdas. Built by the
compiler one commit before the change, it doesn't answer wrongly: it
exits 139.

The over-applied path and a `cast` spine's surplus arguments carry the
class too. Without it, both are live use-after-frees that `axiom check`
accepts. On the shape `461` uses:

| the application | 0.6.0 | now |
|---|---|---|
| `((lambda (v) (vecPush log v)) h.name)`, the control | 97, the `a` | 97 |
| `((mkParker log) h.name)`, over-applied | **122**, the `z` | 97 |
| `((cast Int (lambda (v) ..)) h.name)`, a cast spine | **122** | 97 |

122 is the first byte of the five-byte string allocated into the block
after `(set h.name ..)` released the only counted share. All three in
one process exit **139** on 0.6.0, for the reason `461`'s header gives:
uncounted parks recycle blocks into each other until a header read
lands outside the heap.

The two had different causes, so the fix is in two places:

- The over-applied path had the class and threw it away. `walkAppChain`
  records one per application node, but `emitApplyChain`'s two callers
  passed it `vecNew`, so `evOperandAt` read 0 at every step. Now
  `dispatchCall` snapshots `spineEvs` beside the arguments, as
  `emitIndirectCall` does, and `emitOverApplied` drops it by the same
  arity as its arguments.
- The `cast` spine never had the class. `checkCastForm` claims the
  whole spine at its outermost node, so the intermediate application
  nodes never reach the arm that stamps them. `checkCastArgs` stamps
  the surplus ones.

`tests/stdlib/462-surplus-closure-arg.ax` pins all three rows, and
`scripts/check-closure-reclaim.sh` ablates each half. Ablating the
checker half strikes out term 8 and nothing else. Ablating the emitter
half, in both callers, makes the program exit 139.

One application path still passes a constant `0`: the effect-operation
path in `emitApplyRegsOwned`. It is correct. `checkHandler` binds a
handler's parameter to the operation's declared type, and `AX3017`
refuses a type variable there, so the type is always ground.
`evClassOf` answers `1` and the retain is unconditional. A handler that
parks a struct field and lets the field be overwritten emits
`call @Vec$vecPush(i64 %.t2, i64 %m, i64 1)`, the constant one, and
answers correctly. The word that path passes is one the handler never
reads.

This makes the argument half of the closure-reclamation design
available: release a closure's owned argument when the application's
result class is a word. It was refused while the park took no share.
The park now takes one wherever the application classifies its
argument, and the `__release` probe reads 16, where it read 3 while
the park was uncounted. Every
application path passes the word whenever the checker can supply it.
A release written without consulting that word would be the same
use-after-free in a new place, so the rule consults it instead of
releasing unconditionally.

`tests/stdlib/460-closure-reclaim.ax` pins both halves. Term 64 is the
parked argument surviving its application, which now holds because the
park is counted, not by accident. Term 128 is the struct-field factory,
`z` without the fix and `a` with it. Reverting `checkLamAgainst`'s
third caller strikes out term 128 and nothing else: 255 becomes 127.

The share `MM-LIFE-2g` takes is unbalanced, and has to be: nothing
tells the unsafe layer when a word is overwritten or its block dies. So
a reference stored through either place is immortal. That is a leak,
the safe direction, and it costs nothing new: a value reachable only
from `memAlloc`'d memory is never reclaimed anyway. What it buys is
that the value is no longer invisible, which every remaining ownership
event depends on. This is §10's unsafe layer discharging its own
obligation at the two points where the layer is crossed, instead of
leaving it to every caller.

The rule doesn't cover a program that casts a reference into an
`Int`-declared field of its own `struct`. That writes a word the rule
never sees. `cast` marks leaving the type system, and keeping such a
value alive is the program's obligation, the same position §10 takes
for `memAlloc`. The compiler's own instance of that shape is `mkNode`,
which the rule covers.

Closure capture words are stored unretained, with the one exception
event 4 requires: a capture that is a reference parameter of the
enclosing function takes a share. The closure record's reference map
names those captures, so the record's death hands the shares
back. For every other capture, the closure-outlives-frame dangle stays
a recorded program obligation, beside `MM-VAL-15`'s price sentence.
The evidence record's two words are not part of that obligation: the
record carries a map, so its retains are legal (`MM-LIFE-2d`,
`tests/stdlib/360-arc-evidence-map.ax`).

The §3.3 primitives are legal, permanently. ARC is withdrawn, and the
arenas are the reclamation (`MM-ALLOC-22`, `MM-LIFE-2a`). Composing
the two is guarded at the runtime: an arena reset scrubs the slab heads
first, because a release to zero inside an arena extent files a block
that the reset would otherwise leave dangling into re-issuable memory.

**MM-LIFE-2h (H). The array form exists, and the three
containers carry it.** `MM-LIFE-2d` specifies two forms: the record
form, which `Str`'s header uses through `memAllocMapped`, and the array
form. This rule moves the containers' data buffers from `memAlloc` to
the array form.

The array form is bit 15 of the shape word. It says that every payload
word `0..count-1` of this block is a handle. It costs one bit and no
second header word. The allocator clamps a payload past 16,383 words to
the unknown-size sentinel, instead of past 32,767, which leaves bit 15
free. The cost is reuse of blocks between 131 KB and 262 KB, which read
as unknown-size instead of being filed.

The `count` is the caller's, in bits 16..62. The allocator's word count
in bits 1..14 is a size class: the allocator clamps it to 0 past 16,383
words, because it won't pool a block that large. Read from there, a
container's element buffer of 131,072 bytes or more would announce
itself as an array of zero handles. The walk would release the block
and none of its elements, so the whole form would be off above one
size. With that encoding, at 16,384 elements over 200 iterations,
`vecNewRef` and `vecNew` both peaked at 335,344 KiB.

Bits 16..62 are the record form's reference bitmap, and the two forms
are disjoint by construction, so the field can be a bitmap for one and
a count for the other. `Mem.memMarkArray` therefore takes the element
count, `(-> Int Int Int)`, a declared break in `compat/BREAKING`. No
one-argument version could recover a number the allocator has already
thrown away. `Mem.memMarkLeaf` clears bits 15..62 together. A leaf that
kept the count would read back as a record whose bitmap names whichever
payload words the count's set bits fall on, which is a wild write
rather than a leak.

`tests/stdlib/406-array-form-large-block.ax` is the fixture: it answers
22 against the old encoding and 31 against this one.
`scripts/check-container-reclaim.sh`'s `big` arm is the measurement.

Not reclaimed yet: the buffer itself. 131,072 bytes is past the release
path's 64 KiB pool ceiling, so the block is never filed, and
`big/mapped` stays linear in the iteration count at about 130 KiB a
turn. The elements come back, and the buffer does not.

A bitmap couldn't do this job. The record form holds **47** words, and
`Intern`'s string vector is **64 words at construction**, before a
single string is interned. A count is the only encoding that describes
a buffer.

| block | shape word | means |
|---|---|---|
| `vecNewRef`'s data | `557072` | array form, size class 8 words, length 8 (`8 << 16`) |
| `vecNew`'s data | `16` | the same block, the same size, no claim about its contents |
| `internNew`'s string vector | `4227200` | array form, size class 64 words, length 64 — past the bitmap's capacity |
| a `Vec` header | `262152` | 4 words, bit 2 — the data block |
| a `Map` header | `1835024` | 8 words, bits 2/3/4 — keys, values, states |
| an `Intern` header | `327688` | 4 words, bits 0 and 2 — the `Vec` and the slot table |

`tests/stdlib/404-container-reference-maps.ax` reads all six back. In
the same eight-bit answer, it pins four more properties:

- transitive reclaim four levels deep (vector, data block, `Str`
  header, its 201-byte buffer), so a 200-byte request gets that buffer
  back;
- the same program built with `vecNew` not getting it back;
- growth handing the abandoned block to the free list;
- `vecPop` zeroing what it vacates.

The bit is written by the container and read only by the runtime.
There is no `memIsArray`, because a reader in the library isn't sound.
Bit 15 is unambiguous only against an allocator that clamps the count
at 16,383 words. A seed that clamps at 32,767, where bit 15 was the
count's top bit, reads every block of 16,384 words or more as an array
of handles. `tests/stdlib/200-scale.ax` builds a `Map` of 262,144
slots, whose value array passes that line. Under such a seed,
`mapRemove` believes the bit and releases a raw integer: **SIGSEGV**,
in a program correct under the compiler this tree builds and wrong
under the one that builds this tree. `stage1` runs on the seed's
runtime, so the bootstrap ladder is exactly where it lands.

The committed seeds at `09f3eb4` clamp at 16,383 and carry
`%aform = and i64 %shw, 32768`, so today's seed agrees with today's
compiler. The rule doesn't rely on that. A reader would be sound only
by accident of what is in `bootstrap/`, and `stdlib/Mem.ax` can't see
what that is. So each container carries a flag word of its own, `Vec`
word 3 and `Map` word 6, written by the same code that reads it, with
no encoding to disagree about. That is why a `Map` header is eight
words for the six it holds.

Two obligations come with the array form, and both fall on the code
that uses it. First, words past `len` **MUST** be zero. The walk
releases every word in the block, because the block knows its size and
nothing else. A stale handle above the waterline would have its share
spent while the caller it was handed to still holds one: a
use-after-free, not a leak. `vecPop` and `mapRemove` zero what they
vacate for that reason.

Second, a buffer that is copied, such as a `Vec` doubling or a `Map`
rehashing, moves its elements' shares rather than duplicating them. So
the abandoned block **MUST** be marked a leaf (`Mem.memMarkLeaf`)
before it is released, or every element it held is freed twice.

**MM-LIFE-2i (H). A bounded live set has bounded memory.** This is
`MM-LIFE-2h`'s acceptance property, and the one a long-running process
needs. A program that never frees a container and never resets the
arena holds flat memory while the container's contents turn over
completely.

Two shapes, run on darwin-aarch64 at 20,000, 200,000 and 2,000,000
iterations. The hundredfold range tells a plateau apart from a slope.
Figures are in KiB:

| Shape | Live set | 20k | 200k | 2M | Ablated twin at 200k |
|---|---|---|---|---|---|
| a 256-entry window, insert and evict | 256 entries | 1,392 | 1,392 | 1,392 | 34,368 (no eviction) |
| 64 fixed keys, values replaced | 64 entries | 1,328 | 1,328 | 1,344 | 16,976 (leaf values) |

Evidence: `scripts/check-steady-state.sh`. The ablated twins are
required, because a flat line also reads flat when the measurement is
broken. The second shape's twin differs by one word (`mapNew` for
`mapNewRefVals`) and prints the same answer. So the two arms do the
same work and differ only in what they hand back.

This rule is why `mapRehashCap` sometimes rehashes without growing.
`mapNeedsGrow` reads `used`, and `used` counts tombstones. Under
insert-and-remove churn, a table reaches the load factor while its live
set stays put, and `mapInsert` would double it for entries that don't
exist. A 256-entry window over 200,000 inserts would climb to about
524,288 slots and 10 MB: a bounded live set with unbounded memory,
exactly what this rule refuses. So when the live entries would sit at
a quarter load or less, `mapRehashCap` rehashes at the same capacity.
That drops every tombstone and grows nothing, taking the window from
10,048 KiB to 1,392 KiB.

`scripts/check-container-reclaim.sh` can't see this failure, because
it frees its containers whole and never removes an entry from one.
`scripts/check-steady-state.sh` can.

**MM-LIFE-2d (W, abandoned in place; see `MM-LIFE-2a`). The reference
map.** What already emits is recorded below and stays.

Release at count zero must release the dead block's own reference
fields, and nothing at runtime can name them. A word carries no tag
(`MM-VAL-2`), and a struct block carries no header at all
(`MM-VAL-10`). Assuming otherwise is how `ArenaCompact` corrupted
`scanDecls` (`I2`). So the header's word −1 **SHALL** hold a *shape
word*, written once at allocation by the allocation site. It comes in
two forms, and both carry the block's word count:

- **Record form**: an inline reference bitmap plus the word count. It
  serves constructor blocks, structs, closure records and evidence
  records, which are all statically small. The form has a capacity,
  and like `MM-VAL-8b` that capacity is a stated cliff: a declaration
  whose block would not fit the bitmap **MUST** be refused with a
  diagnostic, never truncated.
- **Array form**: one element-pointerhood bit plus an element count.
  It serves the homogeneous buffers that the containers and `Str`
  allocate, where a bitmap over the words would not fit and shouldn't
  need to.

`memAlloc` itself **SHALL** answer a *leaf*: a shape word saying there
are no reference words, whatever is stored there later. That keeps the
unsafe layer unsafe (§10). A reference kept only in `memAlloc`'d memory
is invisible to counting. Under ARC that becomes a program obligation;
today it is simply a fact. So the containers migrate their data
buffers from `memAlloc` to an array-form allocation whose element bit
comes from the evidence word below. That migration is part of
`MM-LIFE-2e`'s work, and it is what makes the container claim below
true.

The site knows the bitmap statically except in one place: a
polymorphic field. `(Just x)` is emitted once for every `x`
(`MM-VAL-1a`: uniform representation, no monomorphisation). There is
no Hindley–Milner inference, and a signature's type variable is never
solved (`MAC-INT-2`). So the site that stores `x` can't know whether
`x` is a reference. Three designs answer that, and this specification
chooses the first:

| Design | Mechanism | Price |
|---|---|---|
| **Pointerhood evidence** | A polymorphic function receives one hidden word. Bit *i* is set iff type parameter *i* is instantiated at a reference type, and map-writing sites consult it. | One extra word on polymorphic calls. The first and only runtime type information in the language. |
| Immortalise on unknown | A value stored through a variable-typed position is retained permanently. | Every container leaks. `Vec` and `Map` hold every AST node this compiler builds, which is the workload the strategy exists to serve. |
| Tag the word | Reserve a bit in every value. | Changes `MM-VAL-3`'s arithmetic, every literal and every syscall boundary: a different language. |

Pointerhood evidence keeps `MM-VAL-1a` intact, with one emitted body
per function. It is what gives the containers exact element maps. A
`Vec` releases its elements exactly when its evidence bit says they are
references, because its buffer's array-form shape word was written from
that bit.

It isn't trait dictionary-passing. `MAC-INT-4`'s warning still stands:
generated code must not assume dictionaries exist. The evidence word
answers one bit per type parameter and can call nothing.

The design has three edges:

- **Evidence flows by capture.** A lambda whose body needs a bit
  captures its creator's evidence word as an ordinary capture
  (`MM-VAL-15`).
- **Thunks forward zero.** The design first had a thunk built over a
  polymorphic function bake its instantiation's word into the record
  at build time. That is unreachable under this type system. A bare
  reference instantiates fresh placeholders that are never solved
  (`MAC-INT-2`), so every bit of that word is unknowable by
  construction. The implementation forwards the constant 0 from a
  one-word record instead, and a call through a value stays exactly
  two words (`MM-VAL-18`). `tests/stdlib/354-arc-evidence.ax` pins the
  resulting under-reclaim.
- **One word caps type parameters at 64.** A declaration with more is
  refused as `AX3030`, imported modules included, because the cap is a
  matter of soundness rather than honesty. A variable's bit is read
  with a shift by its index, and a shift of 64 or more is poison in the
  emitted LLVM. Poison is an arbitrary answer, and under reference maps
  that becomes a wrong free.

There are two prerequisites, in order:

1. The *static half* is `MM-ALLOC-20`: a checker that can't tell
   `String` from `Int` can't set a bit. `MM-LIFE-2a` quotes its
   progress.
2. The *`Str` half*: a slice's byte pointer is interior to its parent's
   buffer (`MM-VAL-7`, `MM-LIFE-6`), and no count reachable from the
   slice can free an interior address. Under this rule the byte buffer
   becomes a counted block of its own, the `Str` header gains a third
   word naming it, and `strSlice` retains the owner. A slice then keeps
   its parent alive by arithmetic rather than by accident, and
   `MM-LIFE-6`'s obligation dissolves.

*The monomorphic half holds* (`tests/stdlib/352-arc-shape.ax`, 255,
and `tests/stdlib/353-arc-keep-shape.ax`, 13). The encoding is:

- bit 0: the form (0 = record);
- bits 1..14: the padded payload word count;
- bit 15: the array form (`MM-LIFE-2h`);
- bits 16..62: the record form's reference bitmap over block words;
- bit 63: the i64 sign bit, reserved so every shape constant the
  compiler emits is non-negative.

Indexing is uniform and block-relative, so the walk doesn't care which
form it reads. A constructor cell's word 0 is its tag, so its writer
never sets the bitmap bit for word 0. Reserving bit 63 sets the record
capacity at **47 payload words**. A declaration past that cliff is
refused as `AX3029` (`tests/diagnostics/481-record-bitmap-capacity.ax`).
The compiler's own `CG` record already fills all 47 words, so treat
this limit as reachable.

Constructor and struct sites whose fields are all classifiable write
their record shape over the allocator's leaf. A `Ptr`, an alias or a
qualified type spelling forces the whole block to the leaf.
Under-reclaiming is safe, and a wrong bit is a use-after-free. A
type-variable field takes its bit from the evidence word (below). With
no stamp or a zero witness it contributes no bit, which is the leaf
answer for that field, and every classifiable neighbour keeps its bit.

`@axiom_release`'s dead path walks the map and releases the block
named by each set bit, then files the block. A child that dies joins a
dead list threaded through the dead blocks' own count words, so the
walk never recurses and never allocates: a chain of any depth is
released in the stack of one call. A million-cell list, a million-deep
tree nested through either field, a list of strings and a chain of a
million closures each drop whole under a 64 KiB stack
(`tests/stdlib/555-release-deep-chain.ax`, `scripts/check-reclaim-soak.sh`
section 1, whose ablation makes the walk recurse and dies).

The walk's own guards cover immediates, statics and zero counts. The allocator and the arena's keep helper stamp the
leaf of their dynamic size with a shared clamp: a payload past 16,383
words stores count 0, the unknown-size sentinel that release refuses
to file. The ceiling is 16,383 rather than 32,767 because the array
form takes bit 15. `bootstrap/axiom-*.ll` and `codegen.ax` both carry
`icmp ugt i64 %wcnt, 16383`.

*The evidence half holds* (`tests/stdlib/354-arc-evidence.ax`, 255). A
function whose signature puts a type variable in a parameter position
takes one hidden trailing `i64`. The register and its symbol-table name
both contain a dot, which no Axiom identifier can spell. So the word
can't collide with user code, and no reserved name exists.

The checker stamps every reference to a polymorphic declaration with
per-variable witness codes: constant 0, constant 1, or *bit k of the
caller's own word*. It takes the meet over every occurrence. Any
disagreement, cast-rooted argument or unclassifiable witness collapses
to 0, because first-occurrence-wins generated wrong frees on programs
the checker accepts.

A placeholder occurrence says nothing, and is the meet's identity.
Take `(fn (singleton x) (PCons x (PNil)))`. Treated as a witness, the
`(PNil)` argument's `(PL _t)` would meet x's bit k as "a scalar" and
collapse the site to 0. The cell would then store x uncounted with no
map bit, while the flow model trusted the store (event 6). The caller
would release the temporary under it: a use-after-free.

Codegen passes the word at every direct call. The signature decides
whether it is present, and the stamp decides its value. Lambdas capture
it as an ordinary capture, a self-tail-call recomputes it into a slot
beside the parameters' slots, and construction sites read
variable-field bits out of it at run time. A signature whose every
variable is return-only takes no word, so the hottest accessors
(`memGetWord`, `vecGet`, `nodeA/B/C`) are exempt outright. Thunks
forward the constant 0, as described above. `AX3030` holds the
64-variable cliff (`tests/diagnostics/482-evidence-word-capacity.ax`).
The widest signature in this repository declares 4.

*The `Str` half holds* (`tests/stdlib/357-str-owner.ax`, 63). The
header's third word names the owning block. `strAlloc` and every
`strSlice` take a share, and a literal's zero says its loader-resident
bytes are nobody's to free.

*Its consumer holds too* (`tests/stdlib/359-arc-str-bytes.ax`, 63). The
header is allocated *mapped*, with one bit naming word 2. So when a
header's count reaches zero it releases its owner, and the owner's
count reaches zero in turn. Word 1 isn't mapped, because for a slice it
is an interior address, and no count reachable from a slice may free
one.

A thousand build-and-drop iterations of `(MkBox (strDup <48 bytes>))`
move the allocator's bump by **384 bytes**. Without the bit, the same
run moves it **80,304 bytes**: 80 bytes an iteration, exactly the
payload block and its header. The compiler's own output is unchanged
byte for byte, and its self-compile time and peak RSS are the same
either way.

The stamping needs no new primitive. The shape word is an ordinary
word at `h - 8` and the encoding is arithmetic, so
`Mem.memAllocMapped` is six operations over `__load64` and
`__store64`. That matters because the committed seed compiles
`stdlib/`. A standard library that spells a primitive the seed doesn't
know can't be built until the seed moves. Staying inside the existing
primitive set costs one reseed less than the equivalent backend change,
for the same clamp.

The clamp is real. The map is masked to the block's own recorded word
count and to the 47-word capacity. A caller can mark the wrong word of
its own block, which is its business, just as `memSetWord`'s index is.
It can't mark a word outside the block, set the form bit, or disturb
the count.

*The evidence record's map holds* (`tests/stdlib/360-arc-evidence-map.ax`,
7). It has two payload words, both references: word 0 is the handler
value, and word 1 is the record this entry displaced. So event 7's
release at the pop reaches past the header. Both words are stored owned
under event 6's rule:

- a handler built at the `handle` moves in;
- a handler named by a variable is retained;
- the displaced record is retained, because the slot refers to it again
  after the restore.

A thousand handle entries, each building its own handler lambda, move
the bump by under 4 KiB, with no closure record piling up per entry.
This is the first record whose map made its own retains legal. The
standing rule, that a retain must be one an existing map can return,
reads forwards here instead of as a prohibition.

*Still P:* the array form's writers and the container buffer migration
(the `Vec`/`Map` element maps this word exists to feed), and the
closure record's map. The closure map needs something the evidence
record didn't. The evidence record's two words are references by
construction, but a closure's captures are references only if their
binders are. Codegen's symbol table records a name, a register, a
float flag and a slot kind, and no type. The missing piece is the
binder-class stamp that `MM-LIFE-2c` names.

**MM-LIFE-2e (W, abandoned in place; see `MM-LIFE-2a`). The release
path.** What already emits is recorded below and stays.

A bump pointer can't reuse an interior free. Release at zero **SHALL**
hand the block, header included, to a size-class free list that
`axiom_alloc` consults before bumping. Everything §3.1 promises
survives unchanged:

- alignment (`MM-ALLOC-3`), because every size class is a multiple of
  16;
- zeroing (`MM-ALLOC-6`), because the scrub at hand-out already covers
  recycled bytes, which is `MM-ALLOC-5a`'s safe direction doing its
  job;
- freestanding (`MM-ALLOC-1`), because retain, release and the
  free-list walk are emitted runtime functions under the same
  `no-builtins` attribute (`MM-ALLOC-8c`);
- chunks are still never unmapped (`MM-ALLOC-4a`).

The explicit primitives of §3.3 don't compose with this for free. A
reset reclaims without releasing, so a compiler-emitted release after
one would walk a header the allocator has already re-issued: a write
into someone else's block.

This rule once ordered a refusal, now withdrawn. Its text stays so the
dropped **MUST** can be audited: *"When ARC lands,
`__axiom_arena_mark`, `__axiom_arena_reset` and
`__axiom_arena_reset_keeping` **MUST** be refused under it with a
diagnostic; until it lands they remain the only reclamation there is,
and every rule in §3.3 stays load-bearing."*

ARC is not landing (`MM-LIFE-2a`, withdrawn), and the three primitives
are the reclamation strategy (`MM-ALLOC-22`). The clause's own second
half is the argument against its first: they remain the only
whole-program reclamation there is. Refusing them would take a
stateless service from 608 KiB at ten thousand connections to 190,128
KiB, and the language server from 840 bytes per edit to 193,247.

A runtime guard replaces the refusal. An arena reset scrubs the 4,097
slab heads first, because a release-to-zero inside an arena extent
files a block that the reset would otherwise leave dangling into
re-issuable memory. That pays for the composition hazard at run time
instead of forbidding it at compile time, at 4,097 stores per reset.
`MM-LIFE-2a` prices those stores.

The rule sets two acceptance measurements. Both have been run, neither
passes, and the reason is the same in both. Neither is a blocker any
more: they gated ARC's arrival, and ARC is withdrawn (`MM-LIFE-2a`).
They stay as recorded measurements, and the second is now evidence for
the opposite conclusion: the LSP figure below is half of
`MM-ALLOC-22`'s case for the arena. §9.1 records what they measure now.

*The unmanaged column* of `scripts/measure-memory-baseline.sh` **MUST**
go flat with no bracket in the source. It reads **17,456 KiB at 2,000
generations, 8 KiB per generation**, and it is still linear: 162,576
KiB at 20,000.

Typing the container handle doesn't change that. `stdlib/Vec.ax`
declares `(Vec a)`. The probe's `advance` is declared `(-> (Vec Int)
Int (Vec Int))` and its `step` `(-> (Vec Int) (Vec Int))`, so the
checker can see its board end to end. The same script, run on the tree
before and after handles were typed, agrees row for row. Peak RSS in
KiB:

| Generations | 10 | 80 | 500 | 2000 | 20,000 |
|---|---|---|---|---|---|
| handle is `Int` | 1424 | 1984 | 5360 | 17,456 | 162,576 |
| handle is `(Vec Int)` | 1424 | 1984 | 5360 | 17,456 | 162,576 |

The emitted IR says why: the typed probe contains no `__retainref` and
no `__releaseref` call at all. Typing the handle makes the container
*visible* to the checker without making it *reclaimable*. `MM-LIFE-2g`
records the same distinction for `ASTNode`'s ten `Int` fields, from the
opposite direction. A type the checker can see was a real
precondition, but not the one that binds. What's missing is a
whole-program ownership event, and `MM-LIFE-2a` withdrew the strategy
that would have emitted one. The **MUST** stands, unmet.

*The LSP's 200-edit session* **MUST** hold flat with the explicit
boundary removed. `scripts/check-lsp-selfhost.sh` doesn't run that
ablation. Its six ablations are LSP-correctness drills that patch
`lspChar`, `lspSeverity`, `lspSymKind` and the publish loop, and none
touches the arena boundary at `lsp.ax`'s `__axiom_arena_mark` /
`__axiom_arena_reset_keeping` pair. Run by hand, replacing the reset
with a pass-through of the same snapshot and rebuilding the server:

| Server | 5 edits | 200 edits | Per edit |
|---|---|---|---|
| boundary intact | 2016 KiB | 2176 KiB | **840 bytes** |
| boundary removed | 2672 KiB | 39,472 KiB | **193,247 bytes** |

`MM-LIFE-2g` and event 4 both change what the compiler's frontend
allocates per message, yet they move the per-edit figures by only
0.04% and 0%. The gate's ceiling is 2048 KiB over those 195 edits. The
boundary-removed session misses it by a factor of eighteen, and its
per-edit figure is 230 times the bracketed one.

**The LSP's flatness is entirely the arena boundary's doing.** What the
boundary reclaims is per-message AST garbage, and ARC doesn't reach it.
That is the class `MM-LIFE-2c`'s two probes show counting can't see,
because `ASTNode` declares all ten of its fields `Int`. `MM-LIFE-2g`'s
share makes those words *visible* without making them *reclaimable*.

These figures settle the §3.3 refusal: it is withdrawn, with the
strategy that ordered it. Refusing `__axiom_arena_mark` and its pair
would take the language server from 840 bytes per edit to 193 KB per
edit, because nothing else reclaims what it reclaims. A second, larger
workload says the same. A pre-forked server's request handler is
bracketed by the same pair. Without the bracket it needs 100 times the
memory at a thousand connections (19,136 KiB against 192) and 313 times
at ten thousand (190,128 KiB against 608). `scripts/check-net.sh` gates
that with a negative probe, and `MM-ALLOC-22` states it as a rule. That isn't a program with an unusual
memory profile. It is the shape the project targets.

Here is why the ownership events never reached the compiler's own data.
The declared type is discarded in exactly two places, both a `cast Int`
inside a polymorphic function, and `MM-LIFE-2g` closes them with
`__retainref`. So typing the containers and the AST was never the
prerequisite. `MM-LIFE-2c`'s events 2 and 3 have shipped
(`tests/stdlib/372-arc-owned-results.ax`). Both measurements are still
blocked, because the compiler's own containers and AST declare their
handles `Int`. No type-directed ownership event can fire on them, and
neither figure moves until they carry a type the checker can see.

That order is most of the reason the strategy is withdrawn rather than
rescheduled. Twice, the step that looked next was neither the one that
unblocked this nor the one that landed. What moved the numbers in the
end was a workload the arena already served (`MM-ALLOC-22`).

One allocation class is outside `MM-LIFE-2c`'s events: the emitter's
own one-word cells, such as a `match`'s result cell or a
mixed-representation tag read (`MM-ALLOC-9`). Counting them would put a
header and a release on every `match` in the program. They **SHALL**
stop being heap allocations at all. The idiom becomes a register or an
`alloca`, amending `MM-ALLOC-9` and `I10` in the commit that lands it.
While §3.3 was to be refused, the alternative was a sixteen-byte leak
per `match` executed. The obligation outlived that refusal, and it is
discharged.

*Holds* (`tests/stdlib/356-match-no-heap.ax`, 3): one scratch `alloca`
per function serves every merge cell, and the bump pointer doesn't move
across a thousand-iteration `match` loop. The fall-through zero is an
explicit store, not an inherited allocator promise.

*The mechanism holds* (`tests/stdlib/351-arc-reuse.ax`, 42). Release at
zero hands the block, header included, to the largest size class not
above its size (`MM-ALLOC-25`). Classes run from 16 to 65536, and the
dead block's count word doubles as the link. `axiom_alloc` pops before bumping, and re-enters the same
`handout` scrub every landing takes. So `MM-ALLOC-6`'s zeroing runs on
the same path; the fixture writes garbage before the release and reads
zero after the reuse.

The shape word carries the size half `MM-LIFE-2b` demanded, and, with
`MM-LIFE-2d`'s monomorphic slice, the map beside it. Bit 0 is the
form, bits 1..14 the padded payload word count, bit 15 the array form,
and bits 16..62 the record form's reference bitmap. The size class is
the largest class not above count × 8 bytes, which at or below 1 KiB is
count >> 1, and a block files iff 0 < count <= 8192.
Release's class lookup reads the count field, and the dead-path walk
reads the map.

*The large-block policy holds* (`tests/stdlib/363-arc-large-block.ax`,
63), and the measurement it waited for is a **cliff**, not a gradient.
Twenty thousand iterations of a tail loop that allocates one string per
iteration and drops the previous one, peak RSS:

| payload | ceiling 1 KiB | ceiling 64 KiB |
|---|---|---|
| 1008 B | 1,312 KiB | 1,312 KiB |
| 1024 B | **21,936 KiB** | 1,312 KiB |
| 2048 B | 41,936 KiB | 1,312 KiB |
| 8192 B | 162,560 KiB | 1,328 KiB |
| 65536 B | 321,312 KiB | 321,312 KiB |

Under a 1 KiB ceiling, a program whose buffers were a kilobyte and a
byte reclaimed nothing. Its RSS tracked the iteration count rather than
the live set, while the same program one byte smaller stayed flat. The
8 KiB row is also faster pooled: 0.27 s against 0.44 s over the same
20,000 iterations. Reusing a hot block beats faulting in fresh pages,
so the handout scrub more than pays for itself, even though a recycled
large block has to be wiped again.

The ceiling is 64 KiB rather than the 262,128 bytes the count field
can describe, because the wider array buys nothing. A self-compile
peaks at the same memory under a 1 KiB, a 64 KiB and a 256 KiB
ceiling. Nothing large dies in it: the compiler's own containers are
`Int`-typed, so the ownership events are emitted around them rather
than on them. A ceiling costs its head array (4,097 words of BSS, 352
bytes of binary) and the per-reset scrub, and neither is worth paying
for classes no measurement reaches. The table's last row shows the
ceiling itself: a 64 KiB payload plus its NUL and header lands above
it, and nothing above the ceiling is pooled.

What remains of this rule will not be built:

- Pooling blocks above 64 KiB. They are one-shot in every workload
  measured here, and a class for them would hold at most an eighth of
  its block in slack for reuse nothing measured asks for.
- The acceptance measurements. They would need the compiler's own
  container and AST handles to carry a type the checker can see, and
  the container element maps under them.

The §3.3 refusal is withdrawn (`MM-ALLOC-22`). The match-cell
amendment is done: those cells are no longer allocations (`MM-ALLOC-9`,
`tests/stdlib/356-match-no-heap.ax`). The free list of `MM-ALLOC-4b`
still holds whole chunks, unchanged and separate.

**MM-LIFE-2f (W, abandoned in place; see `MM-LIFE-2a`; program obligation). Cycles under counting.**
An unreachable cycle is never reclaimed. `MM-LIFE-3` shows both ways to
build one, and this is the cost `MM-LIFE-2a` accepts. A program that
builds a knot and needs the memory back **MUST** break the cycle before
dropping its last external reference. To do so, store a non-reference
into one edge, as in `(set a.next (cast Node 0))`. The word 0 is below
4096, and release skips it. Nothing checks this, which is what
*program obligation* means throughout this document.

*Today:* the obligation applies, but narrowly. Reclamation exists
(`MM-LIFE-2e`'s path and `MM-LIFE-2c`'s first events), so a knot built
from the block shapes those events release is leaked exactly as this
rule says. A knot built from anything else is leaked because nothing
releases it at all. The obligation matters for every shape once the
remaining events land.

*The policy*: cyclic garbage waits for an arena reset or the end of
the process, and nothing else reclaims it. Inside an arena scope that
costs nothing: 1,000 two-node knots, each dropped inside a scope reset
every iteration, leave no backlog, and a million of them hold RSS flat.
Outside one, each knot costs its blocks' bytes for the rest of the
process: 64 bytes for two 16-byte nodes and their headers, measured by
`__axiom_mem_stat` at 100,000 and a million knots, with peak RSS
growing eightfold between the two. Breaking one edge before the drop, as above,
costs nothing too. A service can watch the backlog as held less filed
(`MM-ALLOC-24`) and decide when to reset. Tested by
`tests/stdlib/557-cycle-backlog.ax` and `scripts/check-reclaim-soak.sh`
section 3.

*The decision*: no cycle collector, because the arena policy covers the
workloads measured. The target workload is a request handler in an
arena scope, where a cycle's cost ends at the request. A reset-free
program pays for exactly the knots it ties, at a price it can now read.
A collector would
be a new rule with its own acceptance criteria. Its hard part is
already paid for: the reference maps of `MM-LIFE-2d` are exactly the
tracing information whose absence made the last collector conservative
and wrong (`MM-ALLOC-20`, §10).

**MM-LIFE-2k (H). A dead block's count word holds an
encoded link, so no retain or release can corrupt the allocator.** A
block whose count reaches zero reuses its count word as a link. It
serves first on the release's dead list while its children are walked,
then on its size class's free list. The link is stored as `-2 - link`.
Every filed or dead block therefore reads as a count of at most -2, -1
stays the static sentinel, and `axiom_retain` and `axiom_release` skip
every negative count.

A raw link would let a second release of a filed block read an address
as a count and decrement it. The free list would then point one byte
below the next block, and the allocator would hand that address out.
With a raw link, a double release followed by two allocations of the
class answered the misaligned address `base + 15`. Evidence:
`tests/stdlib/521-release-filed.ax`, and the third term of
`tests/stdlib/350-arc-header.ax`, which once read the raw link as a
count of 0 only because its class list happened to be empty.

This rule protects the integrity of the allocator's own metadata. It
doesn't make the program that caused the imbalance safe. A block
released one time too many is still a block whose storage the next
allocation may reuse, and a reference to it is still a dangling
reference. What it rules out is an imbalance (a compiler defect,
an unsafe store, a race under `--threads`) turning into an allocation
outside the heap's alignment and extent.

**MM-LIFE-2l (H). The count is finite, and the last
representable retain is the last one.** A block's count word is a
signed 64-bit integer, and `axiom_retain` refuses to move it past
`2^63 - 1`. A retain of a block already at the limit traps with status
70 (`axiom: reference count limit exceeded`) *before* writing the
header. The trap is recoverable like every other: a recovery point
answers 70 at the arming call, with the header still holding
`2^63 - 1`. It shares the exhaustion status without claiming that an
allocation failed.

Without the guard, the increment would wrap from `2^63 - 1` to `-2^63`.
That reads as negative, so every later retain and release would skip
the block (`MM-LIFE-2k`). It would never be reclaimed, and every new
share would go uncounted.

No program reaches the limit by retaining, so the fault is injected.
`tests/stdlib/527-retain-overflow.ax` forges the count through a header
store, retains once to `2^63 - 1`, recovers 70 with the header unchanged,
and exits 70 on the final retain. Its `.optstable` pins the behaviour
at `--opt 0–3`. The executable model covers the rule from the other
side: its `exhaust` witness requires the trap, and the ablation with
the guard removed must return (`scripts/check-runtime-model.sh` §5).

**MM-LIFE-2 (R).** Axiom has no tracing garbage collector, and `--gc`
is refused by name rather than silently ignored. The retired Rust
backend had one: conservative and non-moving, with per-chunk
object-start bitmaps to resolve the interior pointers `strSlice`
creates, and free-run coalescing that took the self-hosted compiler
from 402 MB to 8.7 MB. It was not ported. Bringing a collector back
requires `MM-ALLOC-20`'s discrimination, just as escape analysis does,
plus a decision about `strSlice`'s interior pointers.

**MM-LIFE-3 (H, correcting the roadmap).** Cycles in the heap graph
are constructible. The roadmap once argued that Axiom needs no cycle
collection because "Axiom's data is immutable and inductive, so cycles
are not constructible". That is false as written, and the roadmap
records the correction. There are two independent routes:

```scheme
; 1. Through the standard library, with no unsafe form at all:
(let ((v vecNew)) { (vecPush v 7) (vecPush v v) ... })   ; v contains v

; 2. Through a struct's mutable field, using `cast` to seed the knot:
(let ((a (Node 1 (cast Node 0))) (b (Node 2 (cast Node 0))))
  { (set a.next b) (set b.next a) ... })                 ; walks forever
```

The first needs nothing but `stdlib/Vec`, because a `Vec` element is an
`Int` and a `Vec` handle *is* an `Int` (`MM-ALLOC-20`).

This now has a cost. Where the ownership events release, an
unreachable tree is reclaimed and an unreachable cycle is not. The
rule is a precondition on every reclamation strategy: a tracing
collector for Axiom must trace cycles, and a counting scheme must
either carry a cycle collector or state the leak as a cost. This rule
once concluded that ARC was not sound for Axiom without a cycle
collector beside it. The decision went the other way: `MM-LIFE-2a`
prices the leak in, and `MM-LIFE-2f` states the obligation. §10 argues
the reversal, because both positions stand on the measurement above.

**MM-LIFE-4 (H, amended).** A heap allocation stays valid only until
the first reclamation event that applies to it:

1. its count reaches zero through an emitted ownership event or a raw
   release (`MM-LIFE-2c`, `2e`);
2. an arena reset reclaims it, including the reset emitted at the end
   of a lexical region (`MM-ALLOC-16`, `MM-RGN-1`);
3. its thread's arena is unmapped at completion (`MM-PAR-6a`); or
4. its process exits.

A non-owning alias can't extend that lifetime. Neither an extra retain
nor a cycle prevents an arena reset. `reset_keeping` preserves only its
copied contiguous block at the returned address, not a graph of values
reached through its fields. A `Foreign` word follows the foreign
owner's lifetime instead (`MM-FFI-3`, `7`). Evidence: the source and
gates cited in `MM-LIFE-1` and `MM-RGN-6`.

**MM-LIFE-5 (W).** The withdrawn text was: "Under
`MM-LIFE-2a`–`2f` a third case is added: a value's lifetime ends when its
last reference dies. `MM-LIFE-4` **SHALL** then read ‘until its count
reaches zero’, and the compiler **SHALL** guarantee that no reachable
value is reclaimed."

`MM-LIFE-4` and `MM-RGN-6` supersede it. Count-zero reclamation already
exists, and the automatic-counting roadmap this rule waited for was
withdrawn. Its unconditional reachability guarantee is not a current
claim: raw resets, erased addresses and unsupported ownership routes
remain programmer obligations. The withdrawal removes no runtime code.
Its standing cost is the counting and reset composition recorded in
`MM-RGN-6` and §9.0.

**MM-LIFE-6 (H, program obligation; counting half implemented).** A
`strSlice` keeps the owning byte block live through its three-word
header's mapped owner field. `strWrapOwned` allocates that header with
`memAllocMapped 24 4`, and the header's death releases the owner. This
is implemented today (source: [Str.ax](../stdlib/Str.ax), `strWrapOwned`,
`strAlloc`, `strSlice`;
[357-str-owner.ax](../tests/stdlib/357-str-owner.ax),
[358-str-owner-shares.ax](../tests/stdlib/358-str-owner-shares.ax), and
[container reclamation](../scripts/check-container-reclaim.sh)).

Counting doesn't protect the byte block against an arena reset. A
program using raw reset **MUST** stop reading every slice of reclaimed
bytes. The typed-region checks discharge only `MM-RGN-3`'s covered
paths. `strWrap` supplies no owner, so its caller must keep the
supplied bytes readable for the whole lifetime of every header or
slice that uses them. Refusing the arena primitives is not a planned
way to discharge this obligation (`MM-ALLOC-22`).

**MM-LIFE-7 (P, its syntax refused).** **Linear types.** `(linear T)`
and `(consume e)` no longer parse. Both report `AX2004`: `axiom check`
on `(fn (main) (consume 0))` answers "`consume` parsed and reclaimed
nothing, and is now refused". A `(linear Int)` annotation answers
"`linear` parsed and enforced nothing, and is now refused". Each exits 1 ([Removed
features](reference.md#removed-features); `error-model.md` ERR-MEM-6).
To update old source, delete the wrapper and keep its argument:
`(consume e)` always meant `e`.

Only the inert syntax was refused, not the discipline, so this rule
keeps **P**. The clauses below are still normative for a conforming
implementation, and still unimplemented. `error-model.md` ERR-MEM-6
states the same status from its side: "`MM-LIFE-7`, if it lands, would
add two things to this model and change none of its rules". A rule
whose spelling is gone but whose obligation is not is neither **R** nor
**W**, so §9's Lifetimes row keeps `LIFE-7` under Planned.

The old spellings enforced nothing. A linear value could be used twice
or not at all, and no memory was reclaimed at any point. For readers
of old source:

- `(linear T)` in type position built the nominal type `Linear T`,
  which is incompatible with `T`: passing `x : linear Int` where `Int`
  was expected was `AX3004 expected Int, found Linear Int`. `Linear T`
  written directly still parses and behaves this way. `Linear` has no
  declaration, arity check or constructors, so `(Linear)` and
  `(Linear Int Bool)` are accepted.
- `linear` is a keyword in type position only. In expression position
  it is an ordinary identifier, and as `cast`'s type argument
  `(linear T)` still builds a different, lowercase constructor
  `linear T`, incompatible with `Linear T`.
- `consume` was erased in the parser. The operand came back directly,
  with its `Linear` wrapper intact, so no later stage ever saw a
  consume.

`consume` and `alloc` still win as expression heads, so a program can
declare a function named `consume` or `alloc` but never call it. A
conforming implementation **MUST** refuse such a declaration rather
than accept an uncallable one.

A conforming implementation **SHALL** enforce:

1. A value of linear type **MUST** be consumed **exactly once** on every
   path. Using it twice is an error, and not using it is an error.
2. `(consume e)` is that use, and is a **deterministic drop point**: the
   value's storage is reclaimed there. Under `MM-LIFE-2c`, that is a
   release emitted at the consume rather than at frame exit.
3. A linear value **moves**: handing it to a callee or into a block
   transfers ownership, so no retain and release pair is emitted on the
   hand-off.

The memory model no longer depends on linear types. While
§3.4 was the plan, linearity was discharge B of `MM-ALLOC-19`: the
proof that a tail-call arena reset was sound. The chosen ARC needs no
such proof (`MM-LIFE-2c`, event 4), so linear types are now an
optimisation and a protocol checker, still worth having. `MM-LIFE-2a` says the same from
its side: deterministic reclamation, "obtained without linear types".

*Today:* all three clauses are unimplemented, and
`;@axiom:owned(arena=frame)` is an accepted tag with no meaning.

---

## 6. Parallelism

**MM-PAR-1 (H, its reason amended; its atomics clause and its first
sentence withdrawn).** Axiom has no scheduler, no tasks and no async.
The language has one concurrency form, `parallel`, and five atomic
primitives.
The withdrawn first sentence read: "Axiom has no language-level
concurrency: no threads, no tasks, no async, and no scheduler."

The form is `(parallel p ((a e1) (b e2)) body)`. The parser desugars it
into `let`s over the `__par_spawn` and `__par_join` primitives, and
codegen lowers that pair in one of two ways
([`memory-model-v2-design.md`](memory-model-v2-design.md) §3.3, and
[`parallel`](reference.md#parallel--bindings-that-run-beside-the-caller)
in the reference):

- **The default lowering** is `MM-PAR-2`'s unit: a forked child per
  binding, with the answer crossing through one `MAP_SHARED` page. A
  program that writes `parallel` and nothing else pays neither of the
  prices below. It imports nothing, and every global stays
  process-private (`MM-PAR-3`).
- **The thread lowering**, under `axiom build --threads` or by naming
  `__thread_spawn`, pays both. The program imports `pthread_create` and
  `pthread_join` (and `__tlv_bootstrap` on Darwin), which is tier 3 of
  `MM-FFI-1`'s table. The eight mutable globals of the emitted runtime
  become `thread_local(localexec)`. That is the obligation `MM-PAR-6`
  states, discharged by `cgThreads` in `self_host/codegen.ax`: a scan
  that answers 1 exactly for a module that spawns a thread.

A program that spawns no thread is emitted byte for byte as it would be
without the form, on every target. `scripts/check-thread-local.sh`
holds that path, and `scripts/check-parallel.sh` measures the
differences.

A join hands back a word. What a thread may capture is refused as
`AX3064` at the occurrence:

- a literal-lambda thunk is scanned for captures;
- a thunk that is a frame-local name of arrow type is refused outright;
- a conditional, a `match`, a `let` and a brace block are walked to
  every lambda they can answer;
- a call result and a field are refused at the shape, because their
  captures aren't visible where the spawn stands.

Evidence: `tests/diagnostics/642-parallel-capture.ax`,
`643-parallel-capture-hop.ax` and `644-parallel-thunk-shape.ax`, and
`scripts/check-parallel.sh` section 11. `MM-PAR-6` below says which of
its clauses hold.

The atomics clause, and only that clause, is withdrawn. The emitter
lowers `__atomic_load`, `__atomic_store`, `__atomic_add`, `__atomic_cas`
and `__fence` as sequentially consistent LLVM atomics on one `i64` at a
byte address. They are text-only, with no target arm, and freestanding
on every target. `scripts/check-freestanding.sh` and
`scripts/check-cross-targets.sh` measure this over the fixture that
spells them, `tests/stdlib/440-atomics.ax`.

They give `MM-PAR-4`'s stated escape an instruction: a program that
maps `MAP_SHARED` memory itself has a word it can update without a torn
read. No mutable global of the emitted runtime is touched by one, and
`MM-PAR-3`'s by-construction argument stands as written. The
four that write or order carry `Mut` (`MM-EXEC-9a`, asserted primitive
by primitive in `scripts/check-agent-policy.sh`). `__atomic_load` does
not: it is the one silent read left since `__load64` joined `Unsafe`,
and it is the control that keeps the other four discriminating. The
atomics are the first phase of discharging `MM-PAR-6`'s obligation.

`scripts/check-atomics.sh` inspects and runs them. It counts the
instruction each primitive lowers to on all seven targets at
`-O0`…`-O3`: `xchg`, `lock xadd`, `lock cmpxchg` and a locked `or` to
the stack on x86-64, and `ldar`, `stlr`, an `ldaxr`/`stlxr` loop and
`dmb ish` on AArch64. Five weakenings of the IR must each turn that
count red.

It also runs twelve litmus families on `--threads` threads
(`tests/litmus/atomics.ax`). On two threads: store buffering, message
passing, load buffering (LB), two writes on each thread (2+2W), a
counter, and the four coherence tests on one word (CoRR, CoWW, CoWR
and CoRW). On three: write-to-read causality (WRC) and ISA2. On four:
IRIW (independent reads of independent writes).

Store buffering and the counter each have a plain-access control that
must show the outcome the atomics exclude. Every other family runs
again with the reordering written into the program, which must show
it too. The other plain-access controls are reported, because the
hardware shows them rarely or never; x86-64 and AArch64 keep one word
coherent for every access, so the coherence families' plain rows can
show nothing. The exception is 2+2W on Apple silicon above `-O0`,
which must show.

A seq_cst load on x86-64 is a plain `mov`, which looks the same in
machine code as a monotonic one. The gate checks that the two assemble
identically rather than skipping the case.

Threads are a matter of price, not possibility. On macOS, thread
creation needs `bsdthread_register`, and Mach-O has no local-exec TLS,
so `__thread` lowers to `tlv_get_addr`. Both live in libSystem, and the
language can name them: an `extern` item makes the emitter write a
`declare` (`MM-FFI-1`). `rust/examples/demo/axiom-allow.txt` already
lists `_tlv_bootstrap` and `_tlv_atexit` among the 188 symbols a `std`
link pulls in.

The price is two things this document relies on elsewhere, and only a
program that asks for threads pays it:

- **The freestanding property.** A program with no `extern` links
  **0** undefined symbols, and so does one calling a `no_std` crate. A
  `std` link is **188**, 18 of them forbidden libc names (`MM-FFI-1`'s
  table, gated by `scripts/check-ffi.sh`). Creating a thread means
  naming a libSystem symbol, `bsdthread_register` or the
  `pthread_create` that allowlist already carries. That puts the
  program in the third tier, where `MM-ALLOC-1` and the whole of §3
  stop being unconditional.
- **The whole of `MM-PAR-3`.** Every process-wide mutable global is
  private after `fork` by construction. Threads share them, so the five
  allocator words, the 4,097 size-class heads and every evidence slot
  need atomics or thread-local storage. That is `MM-PAR-6`'s
  obligation, which also records that a shared bump pointer is the one
  thing this allocator's design can't absorb.

**MM-PAR-2 (H, amended).** The unit of parallelism is the
**process**. `stdlib/Par.ax` provides a bounded pool with a
submit-order guarantee and the `sysRun` error contract. It is built on
`__proc_spawn` and `__proc_join`, the forked lowering of `parallel`.
`parMapWords` runs an Axiom closure, and `parRunAll` is that function
over a closure which runs one argv, so running external programs is a
special case of the general pool. `Par` replaces the old `Job` module,
which could only exec an external program. Evidence:
`tests/stdlib/476-par-pool.ax`, which reproduces the old `Job`
fixture's output byte for byte and adds a fourth term `Job` could not
run.

The pool uses `__proc_spawn` rather than `__par_spawn` for a reason.
`__par_spawn` follows `--threads`, so `AX3064` refuses a captured
reference at it. `__proc_spawn` names the forked lowering, whose
isolation is `MM-PAR-3` by construction, and `capSpawnHead` exempts it
for that reason. The pool therefore takes a caller's capture safely
without weakening the rule. `AX3064` can't see a capture through
`parMapWords`'s parameter, so `scripts/check-parallel.sh` section 6b
checks the substitute directly: the module emitted for the pool is
byte-identical with `--threads` and without.

`stdlib/Sys.ax`'s `sysForkProcess` is the other route, and it leaves
the child running *this* program's code. It answers the POSIX
convention on every target: 0 in the child, the child's pid in the
parent, and a negative errno on failure. Darwin needs one fix to reach
it. Its `fork` hands the child pid to both processes and distinguishes
them in a register no primitive here reads, so one `getpid` separates
them. `tests/net/echo-server.ax` needs this: a pre-forked pool whose
workers inherit one listening socket created before the fork, then run
an Axiom request handler. CI drives it with `scripts/check-net.sh`, and
`tests/stdlib/311-preforked-server.ax` has the same shape in the stdlib
corpus. `MM-ALLOC-22`'s measurement is taken on those workers.

Forking needs no compiler support at all, because of `MM-PAR-3`. The
emitted runtime forks too. `@__axiom_par_spawn_proc` is what a
`parallel` binding lowers to by default: `fork` through the syscall
template, the thunk run in the child, and its word written through a
shared page. `@__axiom_par_join_proc` is a `wait4`, and when the
child's status is not 0 it is re-raised as the parent's own exit
(`tests/stdlib/471-parallel-trap.ax`: 77 out of a child that trapped).
Darwin's two-register `fork` is normalised the same way as in
`sysForkProcess`, with one `getpid`.

**MM-PAR-3 (H).** **Memory safety across processes is by construction,
not by discipline.** *Every* process-wide mutable global is private
after `fork` and fresh after `exec`. That covers the five allocator
words of `MM-ALLOC-2`, its size-class head array, the two argument
words `@__axiom_argc` and `@__axiom_argv`, and one evidence slot per
declared effect.

The allocator therefore needs no atomics, no lock and no thread-local
storage, and the effect slots inherit correctly for free. This is why
the process pool needed no compiler change at all.

Threads buy the same property by making the same globals thread-local,
one for one: the five allocator words, the size-class array,
`@__axiom_recover_top`, and one evidence slot per declared effect.
That makes **eight**, a count taken by enumerating `@__axiom_` in
`self_host/codegen.ax`. A module that spawns has *ten*: the child
registry's head and sequence counter (`MM-PAR-7`) are per thread too,
because each thread sweeps the children it spawned.
`@__axiom_argc` and `@__axiom_argv` are not among them. They are
written once in `@main`'s prologue, before any thread can exist, and
never again. Every constant, such as the symbol table,
`@__axiom_bt_mainaddr` and the four trap messages, is shareable by
construction.

`cgThreads` (`codegen.ax`) is the one predicate that decides. It
answers true only for a module that spawns a thread, by naming
`__thread_spawn` or by writing `parallel` under `--threads`. For every
other program it answers false, and the emitted module is byte for byte
what it would be without the thread machinery, on every target. That
half matters more. On Darwin a thread-local access is not an
addressing mode but an indirect call through libSystem's
`__tlv_bootstrap`: **1 undefined symbol** with thread-local globals on,
against **0** with them off. `axiom_alloc` touches four of these
globals on its fast path, so making every program pay would take the
whole tree out of `MM-FFI-1`'s tier 1. This is `ERR-REC-6`'s shape: a
mechanism a program doesn't ask for costs it nothing, and
`scripts/check-thread-local.sh` measures that.

The storage class is `internal thread_local(localexec) global`, and
local-exec is required, not just preferred. A bare `thread_local` takes
the general-dynamic model, which needs a dynamic resolver. That means a
dynamic link, and `scripts/check-freestanding.sh` refuses it because it
requires zero undefined symbols. With local-exec, an access is
`%fs:…@TPOFF` on linux-x86_64 (no extra instructions), `mrs TPIDR_EL0`
on linux-aarch64, and `@TPOFF` on freebsd-x86_64.

`scripts/check-thread-local.sh` checks both directions on both Linux
targets. It requires no dynamic resolver there, and it requires one to
appear when `(localexec)` is dropped. The two Linux
targets show the resolver differently. x86-64 calls `__tls_get_addr`.
AArch64 uses TLS descriptors and never names it, so a check that looked
for `__tls_get_addr` alone would pass an AArch64 build that imports
`__tlsdesc_resolve` through the PLT.

**MM-PAR-4 (H, with a stated escape).** Nothing the language or the
standard library provides shares mutable memory between processes.
Values cross a process boundary as bytes, through a file descriptor or
the filesystem. `Par`'s determinism (`MM-PAR-5`) rests on this.

The rule covers what is *provided*, not what is *reachable*. A program
holds raw `mmap` through `__syscallN`, so it can map a `MAP_SHARED`
region itself and share memory with a child. Nothing stops it and
nothing checks it. A program that does this steps outside this
section's guarantees. The region is outside every arena (`MM-FFI-3`),
the allocator's globals are still not shared, and `MM-PAR-3`'s safety
by construction no longer covers what the program built.

**MM-PAR-5 (H).** Results **MUST** be answered in submit order, always.
Completion order is not exposed at all. A pool whose output depended on
which core was free would make every byte-comparing gate in this
repository nondeterministic.

Eight `sleep 0.5` children take 4.61 s at width 1 and 0.93 s at width 8.
`tests/stdlib/476-par-pool.ax` pins ascending output with children
whose completion order is reversed.

**MM-PAR-6 (P; three of its five clauses H).** If a future
implementation adds threads on a platform that permits them, this
specification **SHALL** require:

- one arena per thread, with no cross-thread reference;
- values handed to a thread are copied or moved;
- results are moved into the parent's arena at join;
- results are combined in argument order, so scheduling
  nondeterminism stays unobservable.

The five allocator globals **MUST** then become thread-local instead of
taking a lock. A shared bump pointer is the one thing this allocator's
design cannot absorb.

*What the thread lowering of `parallel` holds, and what it doesn't*
(`scripts/check-parallel.sh`, `scripts/check-thread-local.sh`):

- **One arena per thread: holds.** In a module that spawns, all eight
  mutable globals, the five allocator words included, are
  `thread_local(localexec)`. A thread starts from the zeroed image, and
  its first `axiom_alloc` maps a chunk of its own. No lock exists
  anywhere.
- **Results moved into the parent's arena at join: holds, for a word.**
  The join hands back the thunk's `Int` through a page the parent
  mapped. A heap value can't be a binding's answer yet (`AX3004` at the
  expression). Moving one out of the child's arena needs the typed
  transfer still planned in `MM-RGN-7`.
- **Combination in argument order: holds by construction.** The parser
  joins in the order written, and a child's completion order isn't
  observable through the form.
- **No cross-thread reference, values copied or moved: held by refusal
  (`AX3064`), except a borrowed `String` (`MM-PAR-6b`).** The refusal covers a thunk that is a frame-local name
  of arrow type. It also covers opaque thunks: a conditional, a match,
  a `let` and a brace block are walked to every lambda they can answer,
  and a call result or a field is refused at the shape. Every shape the
  checker can see is either scanned or refused, so no unrefused capture
  reaches a thread.

  Typed acceptance of captures proved safe across sibling task regions
  is still planned in `MM-RGN-7`. S4's completed release elision does
  not implement it. The process lowering, where the same program is
  safe by `MM-PAR-3`, stays the default, and threads stay opt-in.
- **A captured `Vec`: refused.** `AX3064` refuses every capture that
  `evClassOf` doesn't answer 0 for. A `Vec` answers 0, because it takes
  no share of a count. But its handle names a mutable buffer, so two
  bindings could grow one container at once, and `MM-PAR-6a` makes that
  a memory-safety fault, not only a data race. So a captured `Vec` is
  refused, with its own message.
  `tests/diagnostics/642-parallel-capture.ax` row 5 covers it.
  `tests/diagnostics/656-parallel-container-capture.ax` pins the
  direct, aliased and nested shapes, and the struct-wrapped shape that
  the class rule refuses beside them. A `Foreign` stays accepted, for
  `MM-FFI-7`'s reason.
- **A captured handle: admitted when its type says so.** A word struct
  its module declares `shared` (`MM-VAL-10a`), such as `Chan`, `Mutex`
  and `CancelToken`, is one word the module built for use from several
  bindings at once, so `AX3064` admits it in either lowering. A word
  struct without `shared` is refused with its own message, and so is a
  `Spawn` (`MM-PAR-8`), because a join belongs to the binding that
  spawned it. `tests/diagnostics/1064-parallel-capture-handle.ax` and
  `tests/diagnostics/1066-spawn-handle.ax` pin them, at `parallel` and
  at `__thread_spawn`, and `scripts/check-handles.sh` holds them under
  `build` and `build --threads`.

**MM-PAR-6a (H). A thread-lowered binding returns its arena when it
ends.** Under the thread lowering every mutable runtime global is
thread-local, so a binding's first allocation maps a chunk of its own.
When the thread ends, its entry sweeps its own children (`MM-PAR-7`),
then unmaps every chunk on its active list and its free list. 600
bindings and 6,000 bindings each hold 20 MB of address space
(`VmSize`). Without the unmapping, 600 bindings left 634 MB mapped and
6,000 left 6.16 GB, where the same program forked held 3.6 MB.

This is sound because nothing a thread allocated is reachable once it
ends. What crosses the join is a word (`AX3004` at the binding).
`AX3064` refuses every captured reference and every captured `Vec`,
whose buffer a push would otherwise reallocate out of the thread's
arena, leaving the parent naming unmapped memory.

What remains belongs to the unsafe layer, and it is a **program
obligation**: a word that is the address of thread-arena memory,
laundered through `cast` or stored through a raw address, dangles after
the join.

**MM-PAR-6b (H). A `parallel` binding may borrow a `String` its parent
holds.** The binding reads the parent's string, and nothing it does
changes a count the parent relies on:

```scheme
(import IO)
(import Str)

(:: shout (-> String Int))
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (shout s)
  (parallel p ((a (strLen s))
               (b (strLen (strConcat s "!"))))
    (+ a b)))

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  (shout (strConcat "hello, " "world")))
```

The form keeps a borrow record. Before it builds any binding, it lends
the record every `String` a binding captures: the block's count, and
the count of every block it reaches through a reference map, is saved
and replaced with -1, the static sentinel that `axiom_retain` and
`axiom_release` leave alone (`MM-LIFE-2k`). After the last join, and
before the body runs, every count is put back. So a binding may keep
the string in a list, slice it or copy it, in either lowering, and the
parent's counts are exactly what they were. Every retain and release
between the lends and the return is a no-op on a lent block, the
bindings' closures included, so the saved count is the one to restore.

It is sound because the parent runs nothing between the lends and the
return except building the bindings, spawning them and joining them.
That is why only `parallel`'s own bindings borrow: a hand-written
`__par_spawn` lends nothing, and a `String` it captures is still
`AX3064`. A string's bytes and owner are immutable in safe code, so a
read-only share is the whole of what the binding needs. A `Vec`, a
struct, an `Option` and a function value are not borrowable and stay
refused. A trap that unwinds past the form's end leaves the lent
blocks frozen, which leaks them and nothing else.

The checker lends only what it accepts: each `String` a binding
captures is added to its form's lend list as the capture is checked,
and a capture with no list to join is refused. Codegen freezes what
the list names (`emitParLends`, `__axiom_par_lend`).

Tested by `tests/stdlib/630-parallel-borrow.ax`, which runs at every
`--opt` in both lowerings and reads the counts back, and
`tests/diagnostics/1100-parallel-borrow-refused.ax`.
`scripts/check-race.sh` runs `tests/litmus/borrow-load.ax`, four
bindings borrowing one string thousands of times, under
ThreadSanitizer, and the same program with the lends removed must be
reported.

**MM-PAR-7 (H). No spawned child outlives the scope that could still
observe it.** Every spawn links its handle page onto a registry that
belongs to the spawning thread, and every join unlinks it. Three places
sweep what is still linked. A process is sent `SIGKILL` and reaped. A
thread is joined, because nothing can stop one mid-flight soundly. In
both cases the thunk is released and the page unmapped.

| When | What is swept |
|---|---|
| a recovery abort, before it resets the arena | every child spawned since that recovery point was armed |
| a trap that nothing recovers, before it exits | every child on the trapping thread's registry; under `--threads`, then every process child any thread forked |
| `main` returning | every child the program never joined |
| a forked child's or a thread's own end | the children that binding spawned and did not join |

This rule also closed four defects:

- **A forked child inherited the parent's recovery point.** A binding
  that trapped inside `__axiom_recover` jumped to the parent's arm site
  in the child, and ran the parent's continuation there. The parent
  read the child's exit 0 as success with the answer 0. The result was
  two lines of output where one belonged, and the second was wrong. Now
  the child starts disarmed with an empty registry, and the raising
  join re-raises its child's status through the parent's recovery point
  (`tests/stdlib/522-parallel-recover.ax`).
- **A join that re-raised abandoned its siblings.** They ran on after
  the parent had exited or recovered.
- **A spawn the kernel refused leaked its page and its thunk's share.**
  Status 78 is recoverable, so this leaked on every retry.
- **A join that couldn't reach its child read success.** When `wait4`
  failed with anything but `EINTR`, the status word stayed unwritten
  and 0 was read as a clean exit. `pthread_join`'s answer was ignored.
  Both are now status 78, `axiom: parallel: could not join the
  binding`. So is a handle joined by a thread that didn't spawn it: the
  two registries are unsynchronised, so that join is refused, not raced.

Under `--threads` each thread has its own registry, so a trap that
nothing recovers can't see a process child another thread forked, such
as a task in a pool that thread runs. Every process child is therefore
also on one kill list shared by all threads. The fork and the link
happen under the list's lock, and the trap's sweep takes that lock,
sends `SIGKILL` to every listed pid, and keeps the lock while the
process ends, so no fork can follow it.

A join waits for its child's
exit without reaping it (`waitid` with `WNOWAIT`) and leaves the list
before it reaps, so a listed pid is never one the kernel has reused.
A forked child starts with an empty list. Tested by
`scripts/check-task.sh` §4 and its §8 `gkill` ablation.

On Darwin a process child is forked through libSystem's `fork` in a
module that uses threads, so the child can start a thread of its own.
With the raw system call, the child's libSystem kept the parent's Mach
task port and `pthread_create` faulted. Tested by
`tests/litmus/thread-in-fork.ax` and `scripts/check-task.sh` §8's
`libcfork` ablation.

Three limits:

- A killed child can't sweep its own children, so the grandchildren of
  a killed binding are reparented, not killed.
- A raw exit (`sysExitWith`) sweeps nothing.
- A thread can't be interrupted, so a sweep of a binding that never
  finishes never finishes.

A handle joined twice isn't one of them: the second join traps with
status 85 before it reads the page (`MM-PAR-8`).

What it costs: the registry adds two thread-local globals, so the
eight of `MM-PAR-3` become ten in a module that spawns
(`scripts/check-thread-local.sh`). It also adds five words per handle
page, and a sweep call in the abort, in `@main`'s wrapper and at each
child's end. Under `--threads` the kill list adds two plain globals,
three more words per process page, a `waitid` per process join, and,
on Darwin, the `fork` import. A module that names no spawn primitive emits none of it,
and its output is byte for byte what it would be without the registry.

**MM-PAR-8 (H). A spawn handle SHALL be a value the type system
tracks, joined exactly once.** A spawn primitive answers a `Spawn`,
and only a join, a checked join and `__spawn_pid` take one. `Spawn` is
a builtin word type that nothing but the runtime can build or open, so
an `Int` joined, a handle used as an `Int` and a function declared
`Int` that answers one are `AX3004`. A concurrent binding may not
capture one (`AX3064`), because a join belongs to the binding that
spawned it (`MM-PAR-7`'s 78).

The handle is a slot in the runtime's handle table, and the table says
whether the slot is live. A join asks the table for the binding's page
before it reads it, and the page's end retires the slot
(`@__axiom_par_finish`, on every path: a join, a sweep, a failed
spawn). So *at most once* is checked: a second join, a checked join
after a join, and the pid of a joined binding trap with status 85 and
never read the unmapped page. *At least once* is `MM-PAR-7`'s sweep. A
forked binding's handle and a thread's are different kinds, so one
lowering's handle joined by the other's join traps 85 too, and
`__spawn_pid` answers only a process's pid.

The same table carries the standard library's handles: a channel
(`MM-PAR-10`), a mutex (`MM-PAR-11`) and a cancellation token
(`MM-PAR-13`), each a word struct its module declares `shared`
(`MM-VAL-10a`). Every operation asks the table for the object first,
so a freed, forged or other-kind handle traps 85, and so does a second
free.

A mutex's guard is a word struct too, `MutexGuard`, which only a lock
call answers. It isn't in the table and isn't `shared`. Safe code can't
pass an `Int`, a `Mutex` or another handle as a guard (`AX3004`), build
one (`AX3085`) or hand one to a concurrent binding (`AX3064`). A stale
guard, or another mutex's, is still a real `MutexGuard`, and the
unlock's compare-and-swap refuses it at run time (`MM-PAR-11`).

*The table.* A handle word is `(generation << 16) | index`. A slot
holds a state, the generation with a live bit and a kind, and the
address it names. A get reads the state on both sides of the address
and reads nothing the object owns. A free retires the slot with one
compare-and-swap, so of two frees exactly one returns. There are
65,536 slots per address space, like the mappings they describe,
mapped on first use and lock-free. A module that names no handle or
spawn primitive emits none of it. §10.7 records why liveness lives in
a table.

*Limits.* A free that races another binding's operation on the same
handle is a data race (`MM-PAR-9`): the table catches every use ordered
after the free, not one already in flight. A `cast` to a handle type
forges one, which is the unsafe layer's (`MM-VAL-22`). At most 65,536
handles are live at once: a spawn beyond that is refused as a refused
fork is (78), and a library call answers `EMFILE`.

*Evidence.* `tests/stdlib/570-handle-freed.ax`,
`tests/stdlib/571-handle-table.ax` and
`tests/stdlib/572-spawn-joined-twice.ax`, at every `--opt`;
`tests/diagnostics/1060-handle-int-for-chan.ax` to
`tests/diagnostics/1066-spawn-handle.ax`. The guard's refusals are
`tests/diagnostics/1070-mutex-guard-int.ax` and
`tests/diagnostics/1071-mutex-guard-sealed.ax`. `scripts/check-handles.sh`:
both lowerings, 80,000 handles made and freed by four bindings at once,
racing frees, both kinds of spawn handle, the capture rule under
`build --threads`, a single-bit fault at each of a live handle's 64
bits (`tests/litmus/handle-bitflip.ax`), and four ablations.

**MM-PAR-9 (H). What orders memory between bindings, what the atomics
mean, and what a race is.** This rule says when one binding's write is
visible to another binding's read.

*Happens-before has exactly these edges, and no others:*

1. **Program order** within one binding.
2. **Spawn.** Everything the spawning binding did before a spawn
   happens-before everything the spawned binding does. Under threads,
   the parent writes the thunk and its argument to the handle page, then
   calls `pthread_create` (`__axiom_par_spawn_thread`), which POSIX
   lists among its memory-synchronizing functions. Under processes it
   is `fork`. The child starts from a copy of the parent's memory, and
   nothing either side writes afterwards is visible to the other,
   except the answer.
3. **Join.** Everything a binding did happens-before its join returns.
   Under threads, the answer is read from the handle page after
   `pthread_join`, which POSIX lists. Under processes, the child writes
   its answer to the `MAP_SHARED` page and exits, and the parent reads
   it after `wait4` returns. `wait4` is the BSD and Linux form of
   `waitpid`, which POSIX lists. This edge relies on the kernel's exit
   and wait path. `stdlib/Par.ax` is the process lowering
   (`__proc_spawn`/`__proc_join`) and inherits both edges.
4. **Atomics.** The five primitives are sequentially consistent. There
   is one total order over every atomic operation in the program,
   consistent with program order and with the edges above. An atomic
   load that reads an atomic store synchronizes with it, so a plain
   write made before the store is visible to a plain read made after
   the load. This is publication, the message-passing shape.

There is no condition variable and no volatile access between
bindings. A bounded channel (`MM-PAR-10`), a mutex (`MM-PAR-11`),
timed waits (`MM-PAR-12`) and a task pool's cancellation token
(`MM-PAR-13`) are built on the atomics. None adds an edge of its own:
each one's ordering follows from edge 4, and a wait that times out
orders nothing. The blocking operations are a join, a channel's send
and receive, a mutex's lock, and a pool's wait for its tasks. The
untimed ones wait for ever, and each has a timed form.

*The atomics, precisely.* There is one width, a 64-bit word, and one
ordering, `seq_cst`, with no weaker spelling in the language. The
operand is a byte address that **MUST** be 8-aligned, and the compiler
checks it: before each of the four that take an address, a misaligned
one traps with status 82 (`MM-EXEC-16`), recoverable like the index
trap. Without the check the same program was different on each
architecture: on darwin-aarch64 a word crossing a 16-byte granule died
of `SIGBUS` (exit 138, no message), and on x86-64 it was a slow
split-lock access. The check is an `and`, a compare and a predictable
branch beside the atomic instruction. Tested by
`tests/stdlib/544-misaligned-atomic.ax` at every `--opt`.

All five primitives lower inline on every target, to the instructions
`scripts/check-atomics.sh` counts, so they are lock-free everywhere.
There is no locking fallback.

*A data race* is two accesses to one location from different bindings,
where at least one is a write, at least one is not atomic, and neither
happens-before the other. A race doesn't mean "one of the two values".
A racing plain read may answer anything, and the compiler may assume no
race exists. A race on a handle or a count word corrupts the
allocator's metadata (`MM-PAR-6a`, `MM-LIFE-2k`). No race is harmless,
so no race is defined.

*The safe-language guarantee, and where it ends.* A race needs a
location two bindings can both reach, and the language builds none:

- it has no top-level mutable state (`def` is not a form, and a
  top-level binding is a function);
- every mutable runtime global is thread-local (`MM-PAR-6`);
- a spawned thunk captures no reference and no `Vec` (`AX3064`, R-C1);
- what crosses a join is a word;
- the process lowering shares nothing (`MM-PAR-3`).

So a race needs one of two routes:

- **The unsafe layer.** A primitive, a call to a precondition
  interface, or a cast that forges a reference requires
  `effect(unsafe)` at its declaration (`MM-EXEC-9d`).
  `restrict(no-unsafe)` refuses them directly and through untrusted
  callees. It admits a trusted encapsulation such as `vecPush`, whose
  author takes responsibility for its raw operations. A cast from a
  word to a handle is one such operation (`MM-VAL-22`).
- **An `extern` call**, whose side decides (`MM-FFI-7`).
  `restrict(no-foreign)` refuses it, and admits ordinary code.

That leaves two things the compiler doesn't check:

- **What the unsafe layer promises.** A trusted encapsulation vouches
  for every well-typed call, and a caller of a precondition interface
  vouches for the condition. The compiler checks where those promises
  are declared, not that they are kept. The trusted set is the list to
  review ([assurance/trusted-components.md](assurance/trusted-components.md)).
- **A buffer typed `Int`.** `Sys` takes buffer addresses as `Int`s.
  An `Int` is not a reference, so writing `7` where a buffer belongs
  needs no cast and no tag, and the function can't tell a forged or
  freed word from a live one. A `Sys` function that only passes a
  buffer to the kernel carries no tag at all. Channels, mutexes,
  cancellation tokens and spawn handles are typed handles the runtime
  checks (`MM-PAR-8`), and a `cast` to one is a forging cast, so this
  hole doesn't reach them.

*Evidence.*

- `scripts/check-atomics.sh`: the instructions, with and without the
  LSE atomics, and their ablations. Litmus tests run on two threads
  (store buffering, message passing, load buffering, 2+2W, R, S, a
  counter, and the coherence tests CoRR, CoWW, CoWR and CoRW), on three
  (WRC, ISA2 and 3.SB) and on four (IRIW). Store buffering, message
  passing, R and S also run with `__fence` between plain accesses.
  Dependency variants aren't run: with one ordering, the only
  access a dependency could order is a racing plain read, whose value
  is undefined.
- `scripts/check-parallel.sh`: both lowerings answer byte-identically;
  joins, sweeps and foreign-join refusal.
- `tests/diagnostics/642`, `643`, `644` and `656`: the capture
  refusals.
- `scripts/check-thread-local.sh`: the thread-local globals.

The spawn and join edges come from the platform, so they are cited, not
tested. No litmus test could show a missing `pthread_create` barrier
more directly than every parallel fixture already would.

**MM-PAR-10 (H). A bounded channel carries words between bindings, in
both lowerings.** In `stdlib/Chan.ax`, `chanNew cap` maps a ring of
`cap` words (1 to 1,048,576), with a lock and an event counter beside
it. The mapping is `MAP_SHARED` and made before the spawn. So the
parent, every forked child and every thread see the same pages, and one
channel serves both lowerings without the program choosing.

*What it promises.*

- **Order.** The words received are the words sent, each once, in one
  total order over all senders that is FIFO within each sender.
- **Blocking.** `chanSend` waits while the ring is full. `chanRecv`
  waits while it is empty and open. `chanTrySend` answers whether the
  word went in, and `chanTryRecv` answers `None` when nothing is there
  now. `chanClosed` tells full or empty apart from closed, so neither
  needs a sentinel.
- **The end of the stream.** `chanClose` is idempotent. After it, every
  send is refused (`False`), including one already waiting. A receive
  drains what is left, then answers `None`, the end of the stream, to
  every receiver.
- **Publication.** A send of `w` happens-before the receive that
  answers `w`. Both access the ring inside the lock, whose acquire is a
  seq_cst compare-and-swap and whose release is a seq_cst add
  (`MM-PAR-9`, edge 4). Between threads, that orders any plain memory
  the sender wrote before the send. Between processes, the only shared
  memory is the mapping, so the edge carries the word.
- **Waiting is the kernel's.** A waiter sleeps in `sysWaitWordTimeout`
  on a counter that every change bumps, in slices of at most 100 ms. On
  Linux that is `futex` without `FUTEX_PRIVATE_FLAG`, and on Darwin
  `__ulock_wait` with the 64-bit shared compare. The waiter reads the
  counter under the lock, so a change between its release and its sleep
  is seen on entry, and no wake is lost. One caveat, on Linux only:
  `futex` compares the counter's low 32 bits, so a waiter preempted
  across exactly a multiple of 2^32 changes would sleep through them.
  FreeBSD has no blocking wait wired (`waitWordKind` 0) and spins, which
  is correct and costs a core.
- **The lock names its holder.** Word 0 is the mutex's word
  (`MM-PAR-11`): 0 when free, otherwise the holder's pid shifted left
  twice, with bit 0 set when someone waits. The compare-and-swap that
  takes the lock writes the pid, so the word names the holder at every
  instant the lock is held. An uncontended acquire and release are one
  compare-and-swap each, with no wait or wake. Each public call asks
  `getpid` once for the mark.
- **A holder that dies poisons the channel.** A binding can die between
  taking the lock and letting it go, for example a forked binding that
  `MM-PAR-7`'s sweep killed. When a slice of a lock wait runs out, the
  waiter asks `kill(pid, 0)` about the pid the word names, and `waitid`
  with `WNOWAIT` too when that pid is its own child. `ESRCH`, or a child
  that has exited unreaped, means the holder died holding the lock. One
  compare-and-swap then takes the word from that holder's mark to the
  poison mark, so it lands only while the word still names the dead
  holder, and every waiter on the lock or the ring is woken.
- **A poisoned channel answers as closed and drained.** It never hands
  the lock on, because a holder that died published nothing and its
  plain stores to the ring are in no order anyone can rely on. Every
  call answers at once and touches no ring word:

  | Call | Answer |
  |---|---|
  | `chanSend`, `chanTrySend` | `False` |
  | `chanRecv`, `chanTryRecv` | `None` |
  | `chanSendTimeout`, `chanRecvTimeout` | `Err` with code `chanOwnerDead` (1004, the mutex's `syncOwnerDead`) |
  | `chanClose` | 0, and changes nothing |
  | `chanClosed` | `True` |
  | `chanLen` | 0 |
  | `chanPoisoned` | `True`: a holder died holding the lock |
  | `chanFree` | frees it: it takes no lock |

  A binding already asleep, on the lock or on the ring, answers within
  one slice of the holder being found dead.
- **Retained memory is the mapping.** Nothing is kept per word. A
  wait that sleeps takes a scratch block and gives it back.

*Limits.*

- `chanSend` and `chanRecv` have no timeout. A receive on a channel
  nobody sends to or closes waits forever, and a thread can't be killed
  out of it, because `MM-PAR-7` joins threads. `chanSendTimeout` and
  `chanRecvTimeout` are the bounded forms (`MM-PAR-12`).
- No fairness between waiters. A wake wakes all, and the first to take
  the lock wins. The load gate prints the consumers' shares instead of
  asserting them.
- No priority inheritance.
- Not usable from a signal handler, because the lock doesn't re-enter.
- A dead holder is found only once the kernel says it is gone. One that
  is dead but not yet reaped, a zombie its parent hasn't joined, looks
  alive to every binding but that parent. A pid that an unrelated
  process has taken makes a dead holder look alive for good. In both
  cases the untimed calls wait and the timed ones answer `sysTimedOut`.
- The mark costs a `getpid` system call per public call, which is most
  of an uncontended send and receive (`scripts/bench-concurrency.sh`).
- A binding killed while it waits leaves its announcement in word 2
  and its bit in word 0, so later changes make a wake call nobody
  needs. That costs time, not correctness.

*Program obligations.* What crosses a channel is an `Int`. A heap value
would name memory the receiver doesn't own: a forked child's arena, or
a thread's, which is unmapped when it ends (`MM-PAR-6a`). Typed values
cross between tasks by serialization (`MM-PAR-13`).

The handle is a `Chan` (`MM-VAL-10a`): only `chanNew` makes one, and
every operation asks the runtime's handle table for the mapping before
it touches the ring (`MM-PAR-8`). So an operation on a freed channel,
and a second `chanFree`, trap with status 85 instead of reading an
unmapped page, and no other kind of handle passes as a channel. `Chan`
is declared `shared`, so a `parallel` binding may capture it in either
lowering. What stays a program obligation is the order: call
`chanFree` only once no binding can still use the channel, after the
`parallel` form that used it. A free that races another binding's
operation is a data race (`MM-PAR-9`), which the table doesn't catch.

The raw words are private helpers that say `effect(unsafe)` alone,
trusted encapsulations (`MM-EXEC-9d`), so `Unsafe` stops at them and
the public functions' rows don't carry it (`docs/stdlib-api.md`). The
two timed forms say `effect(unsafe)` themselves, because they hand
back a scratch block, and they are trusted too. That trust rests on the
handle obligation above, which the type `Int` can't express. The rows
of the calls that lock carry `Alloc`, because a lock wait takes a
scratch block.

*Evidence.*

- `tests/stdlib/528-chan.ax`: every answer above, one binding at a
  time, and three forked producers into two consumers with exact
  totals.
- `scripts/check-chan.sh`: three producers and three consumers at
  capacities 1 and 64, in both lowerings, at `--opt` 0 and 2, with
  exact count, sum and sum of squares. It also checks one wait call
  through a 200 ms delay, and a receive nobody satisfies still blocked
  at 2 s. The lock and the wake are each ablated on a copy of the
  standard library, and each turns the load test red. RSS stays flat
  over ten times the words.
- `scripts/check-chan.sh` §6 kills a holder in both lowerings
  (`tests/litmus/chan-dead.ax`). A binding asleep on the ring and one
  asleep on the lock each answer `None`, poisoned, about 100 ms after
  the kill, and a timed receive beside the live holder answers
  `sysTimedOut` no sooner than asked. A zombie holder's parent finds it
  dead. Recovered traps whose sweep kills a binding in the middle of
  its calls leave the lock held in about one round in 200, and every
  round answers. Ablating the dead-holder test, or the look at the
  waiter's own child, leaves the probe with no answer.
- `tests/stdlib/590-chan-dead-holder.ax`: every call's answer on a
  poisoned channel, at every `--opt`.
- `scripts/check-platform-constants.sh`: the library's `mmap` and
  `munmap` numbers agree with the runtime's on all six targets.
- `scripts/check-protocol-model.sh`: the protocol, transcribed step by
  step in `scripts/lib/protocol-model.py`, is clean in every
  interleaving of two and three bindings at capacities 1 and 2 with
  one to four words, and under one pid as threads have: exactly once,
  FIFO per sender, close and drain, and no lost wakeup or deadlock. A
  sender, receiver or timed sender killed at any step, with the lock
  held or not, leaves every other binding able to finish, and the
  channel is poisoned only by a holder that died holding it.
- The same gate plants defects in the model, and finds each with a
  schedule: a waiter that parks after releasing the lock, a release or
  notify that wakes nobody, and each part of the dead-holder rule taken
  back in turn. A run recorded on an instrumented copy of this library
  replays through the model operation by operation. Two bindings each
  waiting to receive from the other time out under `chanRecvTimeout`
  and stay blocked under `chanRecv`.

**MM-PAR-11 (H). A mutex excludes between bindings, in both
lowerings.** In `stdlib/Sync.ax`, `mutexNew` maps one page,
`MAP_SHARED` and made before the spawn, as `Chan` does. So the parent,
every forked child and every thread see one lock word. `mutexLock`
waits until the caller holds the mutex. `mutexTryLock` doesn't wait,
`mutexLockTimeout` waits at most a given time (`MM-PAR-12`), and
`mutexUnlock` lets the next holder in.

*What it promises.*

- **Mutual exclusion.** At most one binding holds the mutex at a time.
  The lock word goes from 0 to the holder's mark only by a seq_cst
  compare-and-swap, and back to 0 only in `mutexUnlock`.
- **Happens-before.** An unlock synchronizes with the lock that next
  acquires the mutex. The release is a seq_cst compare-and-swap or
  store, and the acquire is a seq_cst compare-and-swap that reads it
  (`MM-PAR-9`, edge 4). Everything the holder did before `mutexUnlock`
  is visible to the next holder once its lock call answers. Between
  processes, the memory that edge carries is a shared mapping. Between
  threads, it is all of memory.
- **Blocking is the kernel's.** A waiter marks the word contended and
  sleeps in `sysWaitWordTimeout` on it, in slices of at most 100 ms. An
  unlock that finds the mark wakes every waiter. An uncontended lock and
  unlock make no wait or wake call, though each lock call asks `getpid`
  once for the mark.
- **The holder is named.** The mark is the holder's pid shifted left
  twice, with bit 0 as the waiters' flag. Bit 0 is in the low half, the
  half Linux's `futex` compares. The compare-and-swap that takes the
  lock also writes the pid, so the word names the holder at every
  instant the lock is held.
- **The guard is typed.** Every acquisition draws a *guard* from a
  counter and publishes it as the holder's, right after its
  compare-and-swap takes the lock word. The lock call answers it as a
  `MutexGuard`, a word struct only `Sync` builds or opens, so safe code
  can't offer an `Int` or another handle as one (`MM-PAR-8`).
- **Misuse is refused.** `mutexUnlock` claims the published guard with
  one compare-and-swap, from the guard to 0, before it touches the lock
  word. An unlock of a free mutex, with a stale guard (a double
  unlock), with another mutex's guard or with any guard but the
  holder's fails that compare-and-swap, answers `Err` code
  `syncNotHeld` (1005), and changes nothing. That includes a stale guard that lands between a new
  holder's lock and its publication, because the published word holds 0
  then.
- **The guard is the check**, because every binding has the same pid
  under `--threads`. Each mutex's counter starts at its page number
  times 2^24, so the guards of two live mutexes differ unless one has
  been locked 2^24 times.
- **A dead holder is found.** When a slice of a wait runs out, the
  waiter asks `kill(pid, 0)` about the pid the word names, and `waitid`
  with `WNOWAIT` too when that pid is its own process's child, as the
  channel does (`MM-PAR-10`). `ESRCH`, or a child that has exited
  unreaped, while the word still names that pid, means the holder died
  holding the lock: a forked binding that `MM-PAR-7`'s sweep killed, or
  a child that exited holding it before its parent joined it.
- **A dead holder poisons it.** The mutex is then poisoned: a flag is
  set and every waiter is woken. From then on every lock call answers
  `Err` code `syncOwnerDead` (1004), `mutexTryLock` answers `None`, and
  `mutexOwnerDead` says why. The lock isn't handed over, because what
  it protected may be half-written and only the program can say whether
  that is survivable. On H3 a timed
  lock answered 1004 101 ms after the holder was killed and reaped, and
  an untimed one at once. A parent whose child exited holding the lock
  answered 1004 101 ms into a 2 s timed lock, in both lowerings, before
  it joined the child.

*Limits.*

- No fairness. A wake wakes every waiter and the first
  compare-and-swap wins, so a binding can starve.
- No priority inheritance. A low-priority holder can be preempted while
  a high-priority waiter waits. Priority inversion is possible, and
  nothing raises the holder.
- Not reentrant. A holder that locks again waits for itself, for ever
  with `mutexLock`. So it isn't callable from a signal or interrupt
  handler.
- A holder that is dead but not yet reaped, a zombie its parent hasn't
  joined, still answers `kill(pid, 0)`. Only its parent's process can
  ask `waitid` about it, so it looks alive to every other binding. A pid
  that an unrelated process has taken looks alive too. In both cases the
  lock looks held: a timed lock answers timed out and an untimed one
  waits.
- A thread can't die holding the lock alone. A trap under `--threads`
  ends the process.

*Program obligations.* The handle is a `Mutex`, as `Chan`'s is a
`Chan`: every call on a freed mutex, and a second `mutexFree`, traps
with status 85. Call `mutexFree` only once no binding can reach the
mutex; a free that races a lock call is a data race (`MM-PAR-9`). A
guard made with a `cast` is the unsafe layer's (`MM-VAL-22`): the
unlock still refuses it unless its word is the holder's current guard,
which a program can read out of the page only through that layer too.
What the lock protects is protected only if every access to it happens
under the lock. A plain access outside it is a data race (`MM-PAR-9`).

*Evidence.*

- `tests/stdlib/541-sync-mutex.ax`: every answer above, one binding at
  a time, another mutex's live guard and a guard made by a `cast` among
  the refused unlocks; two forked bindings making 3,000 increments
  each, exact; and a holder killed and reaped while holding the lock.
  Its `.optstable` pins `--opt` 0 to 3.
- `tests/diagnostics/1070-mutex-guard-int.ax` and
  `tests/diagnostics/1071-mutex-guard-sealed.ax`: an `Int`, the mutex
  and a channel refused as a guard, a guard refused as an `Int`, and a
  guard built, opened or captured by a concurrent binding refused.
- `scripts/check-task.sh` §1: four bindings each add 1 to one plain
  shared word 100,000 times under the mutex, exact in both lowerings at
  `--opt` 0 and 2. Beside each run, an unlocked control must lose
  updates. On H3 the four controls lost 230,071 to 272,503 of 400,000.
- `tests/stdlib/600-mutex-dead-child.ax`: a child that exits holding
  the lock, not yet joined, poisons it for its parent's timed lock, at
  every `--opt`.
- `scripts/check-task.sh` §2 checks the dead holder, killed and reaped
  or exited and unreaped, and the refused unlocks. The unreaped holder's
  parent answers 1004 well inside a 2 s timed lock in both lowerings, and
  so does a sibling thread under `--threads`, while a sibling process,
  which can't look, times out. One of the refused unlocks is the stale
  guard presented in the window
  between a new holder's lock and its publication, built exactly
  rather than raced for. Under load, one binding double-unlocks
  200,000 times beside two correct ones: every stale unlock is refused,
  every earned one accepted, and the count exact, in both lowerings.
- `scripts/check-task.sh` §6 ablates the lock's compare-and-swap, the
  dead-holder test, the look at the waiter's own child and the guard
  claim (compared against the counter instead, which accepts the stale
  guard in the window), each on a copy of the library, and each turns
  its check red.

- `scripts/check-protocol-model.sh` explores the protocol, transcribed
  in `scripts/lib/protocol-model.py`, in every interleaving of two and
  three bindings in both lowerings, with a stale guard, a timed lock, a
  try-lock and a holder killed at any step, reaped by nobody but its
  parent when a waiter is that parent. Every state keeps exclusion,
  refuses the stale guard and poisons only for a dead holder, and no
  lost wakeup or deadlock is reachable. A lock taken by a plain load
  and store, a release without its wake, a waiter without its mark, the
  guard compared with the counter, the dead-holder test without its
  re-read and a waiter that never asks `waitid` about its own child are
  each found with a schedule. On the
  machine, a lock-order inversion answers `sysTimedOut` on both sides
  under `mutexLockTimeout` and deadlocks under `mutexLock`, and four
  contending bindings' shares and worst waits are measured.

A load test that passes is evidence about the runs made, and the model
is a proof about the model at its bounds. The implementation isn't
proved.

**MM-PAR-12 (H). A wait may be bounded, and says why it ended.**
`sysWaitWordTimeout addr expected nanos` blocks while the word at
`addr` holds `expected`, for at most `nanos`. It answers:

- **0**, woken: by a wake, a signal, or spuriously.
- **1**, timed out: the kernel measured the whole wait and nobody woke
  it.
- **2**, changed: the word didn't hold `expected` when the call began.

Every answer means "check your own condition again". None is a promise
about the word.

*How each target measures it.*

- Linux (`waitWordKind` 1): `FUTEX_WAIT` without the private flag, with
  a relative timespec the kernel measures on `CLOCK_MONOTONIC`.
- Darwin (2): `__ulock_wait`, whose timeout is in microseconds. The
  library rounds up, so the wait is never shorter than asked, and caps
  it at 2^32-1 µs (71.6 minutes), deciding the cap before it rounds so
  a request near the largest `Int` can't wrap. A longer request that
  times out answers 0, and the caller waits again. A 200,000 µs wait answered
  `-ETIMEDOUT` after 200,201 µs. A word that already differed answered
  0 at once, which is why the library decides answer 2 with a load
  before it asks the kernel.
- No blocking wait (0, FreeBSD for now): a spin that reads the word and
  the clock. It is correct, and it costs a core.

*The timed library calls.* `chanRecvTimeout`, `chanSendTimeout`,
`mutexLockTimeout` and a task's deadline (`MM-PAR-13`) answer `Err`
with code `sysTimedOut` (1001) when their time runs out. By then they
have taken nothing out of the channel, put nothing in, and acquired
nothing. A channel's timed call counts its wait for the channel's lock
against the same time, so a holder that never lets go costs it its
deadline and no more. 1001 isn't an errno, because `ETIMEDOUT` is 60 on
Darwin and 110 on Linux.

These calls wait in slices of at most 100 ms. A slice costs the whole
slice when the kernel timed it out, and otherwise the clock's step
clamped to [0, slice]. So a wait nobody ends is never shorter than asked on any
target, because the kernel measured the last slice. A wait that is
woken early and must wait again is charged what `sysTimeoutMicros`
saw.

That clock is `CLOCK_MONOTONIC` on Linux and FreeBSD. On Darwin it is
the realtime clock, because Darwin has no monotonic clock reachable
without libSystem (`clockHasMonotonic`). A step of the Darwin clock
moves a wait by at most the one slice it lands in. Each timed call
checks its condition once more after its last wait, so a word that
arrives as the time runs out is still taken.

*Timeouts add no edge.* A wait that times out has synchronized with
nothing. What a caller may read afterwards is what `MM-PAR-9`'s edges
already ordered.

*An implementation reliance.* `sysWaitWordTimeout`'s entry load is a
plain 64-bit load of a word other bindings write with atomics. By
`MM-PAR-9`'s definition that is a data race. `Sys.ax` is compiled by
the committed seed, which has no atomic primitive. Three facts keep the
load sound in practice:

- its answer is only advisory;
- the syscall that follows clobbers memory, so the compiler can neither
  hoist nor merge the load;
- an aligned 64-bit load is single-copy atomic on both instruction sets
  the blocking kinds run on.

This relies on the implementation and sits outside the language's
guarantee. Linux's `futex` also compares only the word's low 32 bits
(`MM-PAR-10`'s caveat).

*Evidence.*

- `tests/stdlib/540-wait-timeout.ax`: the three answers, a timed-out
  wait no shorter than asked, and the channel's timed forms and their
  answers after close. It has an `.optstable`.
- `scripts/check-task.sh` §2: a receive, a send and a lock each asked
  to wait 200 ms answer 1001 within [200, 1000] ms in both lowerings
  (200 to 203 ms on H3). A receive and a lock satisfied at about 100 ms
  of a 2 s wait answer then.
- `scripts/check-task.sh` §6 asks the kernel for a tenth of the time,
  on a copy of the library. The timed receive comes back early and the
  check turns red.

The bounds hold on the runs made. A loaded host can exceed any slack.

**MM-PAR-13 (H). Tasks answer typed results across the process
boundary by serialization, bounded, with deadlines, cancellation and
per-task failure, and no child outlives the call.** In
`stdlib/Task.ax`, `taskMap f n width limit` runs `f i` for every `i` in
`0 .. n`, each in a forked child, at most `width` at once. It answers
one `(Result String Error)` per task, in submit order. `taskMapWith`
takes every option (`TaskOpts`), and `taskFold` streams the answers
into an accumulator instead of keeping them. A task always uses
`__proc_spawn`, whatever `--threads` says, because `MM-PAR-3`'s
isolation is what makes a task's captures its own.

*What it promises.*

- **Transfer is by serialization, and bounded.** A task answers a
  `String`. Its bytes are written into the task's slot of a
  `MAP_SHARED` slab, then copied into the parent's arena when the
  result is delivered. A heap value can't cross, because its handle
  would name the child's arena. A program that wants a record back
  encodes it in the task and decodes it in the parent. An answer over
  `limit` bytes answers `Err` code `taskTooLargeCode` (1003): none of
  it crosses, and the parent is unharmed.
- **Failure is a value in its slot.** A task that traps or dies answers
  `Err` with its wait status: 1 to 255, an exit code or 128 plus the
  signal, as in `Par.ax`. Its siblings still run and answer. The
  library's own codes are above 255, so none can be mistaken for a
  status.
- **A deadline** runs per task from the clock read after its spawn,
  and is enforced by `SIGKILL` and a reap. The task answers
  `sysTimedOut` (1001). A task that finished, or died on its own,
  before the kill answers that instead. Durations are converted to
  microseconds with saturation, so a deadline or grace near the
  largest `Int` means for ever.
- **Cancellation** uses a token: a `CancelToken` from `taskTokenNew`,
  a handle naming a shared word, which `taskCancel` sets from anywhere,
  a sibling binding or a task, and `taskCancelled` polls. A binding may
  capture it, and a call on a freed one traps with status 85
  (`MM-PAR-8`). A pool that sees it set starts nothing
  more, and every unstarted task answers `taskCancelledCode` (1002).
  Running tasks get `grace` to finish, then the pool kills and reaps
  the rest, which answer 1002. `failFast` sets the pool's token at the
  first task that answers an error. `taskCancel`'s store synchronizes
  with the `taskCancelled` load that reads it (`MM-PAR-9`, edge 4).
- **Results are deterministic, side effects are not.** The answers are
  in submit order and depend only on what each task answered. What
  tasks write to fd 1, a file or a shared mapping interleaves as the
  scheduler ran them, and the clock decides a deadline or a grace.
- **Everything is bounded.** At most `width` children exist at once.
  The parent's per-slot state is a ring of `width` entries, and the
  slab is `width × limit` bytes, reused. Submission blocks while
  `width` tasks are outstanding, so there is no queue. A slot is freed
  when its result is delivered in submit order, so a slow task holds
  back the tasks `width` places behind it (`MM-PAR-5`'s price).
  `taskMap`'s answer is O(n), because it is n results. `taskFold`
  delivers each answer inside a `region` (`MM-RGN-1`) and keeps
  nothing. On H3 its peak RSS was 1,888 KiB at 500, 5,000 and 20,000
  tasks of 4 KiB answers.
- **A refused spawn is a value too.** A spawn the kernel refuses, or
  one the handle table has no slot for, answers `Err` 78 in its task's
  slot, or 70 when no page could be mapped for the handle. It cancels
  the pool as a cancellation does, but leaves the token alone: nothing
  more starts, the tasks still running get `grace` and are then killed
  and reaped, and the pool returns through its normal path, which
  unmaps the slab and frees a private token. The spawn runs inside a
  recovery point of its own (`taskSpawn`), so the runtime's 78 comes
  back to the pool instead of unwinding past its cleanup.
- **`Par`'s pools answer a refusal too.** `stdlib/Par.ax`'s
  `parMapWordsChecked` answers it in its slots the same way, and kills
  and joins its running children at once. `parMapWords` raises 78 to
  its caller as it raises a child's trap, and the runtime's sweep
  (`MM-PAR-7`) kills and reaps its children.
- **No child outlives the call** on any path the program has. A normal
  return has joined every child. A trap in the parent in the middle of
  a pool is `MM-PAR-7`'s case: the children are on the spawning
  thread's registry, and the unrecovered trap, or the recovery point
  armed around the pool, kills and reaps them. Under `--threads`, a
  trap in any other thread reaches them through `MM-PAR-7`'s kill
  list.
- **The join owns the reap.** The parent looks at a running child with
  `sysChildExited`, which is `waitid` with `WNOWAIT` on Linux and
  Darwin and `wait6` on FreeBSD. The look doesn't reap the child, so a
  handle's pid names its child until the join, and a sweep can never
  kill a pid the kernel has reused. The look runs every 10 ms while the
  parent sleeps. A task that answers, or a cancellation, wakes the
  parent at once through the token's event counter.
- **An answer isn't an exit.** A task is joined when the look reports
  its exit. One that has answered but not exited, because its process
  is still ending, stays under its deadline and a cancellation's grace
  like any running task. While one exists the look starts 20 µs after
  the answer and doubles each time it finds nothing, up to the 10 ms
  period, so a task that exits promptly is joined at once and one that
  can't exit neither blocks the pool in the kernel nor keeps it
  polling.

*Limits.*

- A parent killed by a signal nothing handles, such as `SIGKILL` from
  outside, runs no sweep. Its tasks are reparented and run on. The
  gate's control measures exactly that.
- A pool inside a `parallel` binding that `MM-PAR-7`'s sweep kills
  can't sweep its own tasks (`MM-PAR-7`'s grandchildren limit). A
  task's own children are the task's responsibility.
- A raw `sysExitWith` sweeps nothing.
- A pool's mappings aren't returned when any other trap unwinds
  through it, such as one in `taskFold`'s step. Its children are still
  killed and reaped (`MM-PAR-7`).
- Where no look at a child exists (`sysChildExited` answers `Err`), a
  death without an answer is found at the task's deadline. With no
  deadline, it is found by blocking on the oldest running task's join,
  and a cancellation then waits for that join.
- On Darwin, deadlines are measured on the realtime clock
  (`MM-PAR-12`).

*Program obligations.*

- `taskFold`'s step may keep only what its `Int` accumulator carries.
  The region check sees the pool's call but not into the step's
  captures. A step that stores an answer, or grows a captured `Vec`,
  names reclaimed memory, which is why `taskFold` claims
  `effect(unsafe)`.
- A token passed in is shared state: cancelling it cancels every pool
  using it. Free it only once no pool and no task can still use it.

*Evidence.*

- `tests/stdlib/542-task-codec.ax`: twelve tasks each build a record
  with a `Vec` in it and send it through JSON. The decoded records equal
  the sequential ones, and an encoding over the limit is refused whole.
- `tests/stdlib/543-task-failures.ax`: a trap, a deadline and an
  oversized answer, each in its slot with the siblings answering; a
  cancelled token starting nothing; and `failFast` killing two stuck
  tasks after the grace. Both fixtures have an `.optstable`.
- `scripts/check-task.sh` §3: 300 answers equal to the sequential ones
  in both lowerings at `--opt` 0 and 2; a trap with no deadline, found
  by looking; the deadline's two pids gone before the pool returned and
  after; a cancellation from a sibling binding at 300 ms that stops the
  cooperative task, kills the stubborn one and starts nothing more, in
  about 450 ms; and `failFast`.
- `scripts/check-task.sh` §3 also runs a grace of the largest `Int`,
  which must let a cancelled task finish.
- `scripts/check-task.sh` §3 also runs a task that answers and then
  can't exit, which its deadline ends with its answer kept.
- `scripts/check-task.sh` §4: the parent's trap mid-pool takes both
  running tasks with it, and under `--threads` so does a trap in a
  sibling thread. A control measures the stated limit: an external
  `SIGKILL` leaves the tasks alive. §5: the fold stays within 1 MiB
  from 500 to 5,000 tasks, and the keeping control must grow by 8 MiB.
- `tests/stdlib/601-task-spawn-refused.ax` and
  `tests/stdlib/602-par-spawn-refused.ax`: the third spawn refused,
  each answer in its slot, the running children gone and every handle
  slot back, at every `--opt`.
- `scripts/check-task.sh` §9 refuses a pool's third spawn in both
  lowerings. The two running tasks' pids are gone while the program
  still lives, it has no child left, every handle slot comes back, and
  eight refused rounds with a 128 MiB slab each leave the address space
  where one round left it. With the recovery point around the spawn
  taken out, the same eight rounds kept about 900 MiB. The kernel's own
  refusal is run too: a fold that lowers `RLIMIT_NPROC` mid-pool, and
  `ulimit -u 1` refusing the first fork.
- `scripts/check-task.sh` §6 ablates the deadline's kill, the pid the
  kill reads, the child look, the result slot, the byte limit, the
  cancellation's kill, the saturating microseconds conversion and the
  exit wait, each on a copy of the library, and each turns its check
  red.
- `scripts/check-protocol-model.sh` explores the pool, transcribed in
  `scripts/lib/task_model.py`, in every interleaving of two and three
  tasks at widths 1 to 3. Each task's body answers, answers over the
  limit, traps, exits unanswered, runs for ever, cannot exit after
  answering, or answers after a while, beside deadlines, a
  cancellation from a sibling, fail-fast and no look at a child. The
  model's clock moves only while the pool waits and nothing else can
  step.
- In every state of that model, every task is delivered once, in
  submit order, as what happened to it. At most `width` children and
  handles exist, and nothing starts once a cancellation is seen. The
  pool never sleeps past a running task's deadline or the grace's end,
  and every child is reaped when it returns. Nine planted defects, among
  them the deadline's kill, the exit wait and the result slot above,
  are each found with a schedule. §8 ablates the runtime's kill list and Darwin's libSystem fork
  in copies of the compiler. §7 builds and runs the three programs in
  `examples/concurrency/`, which check themselves, in both lowerings.

**MM-PAR-14 (H). A pure parallel computation answers what its parts
answered, combined in index order, whatever finished first.** This
rule says which parts of a parallel computation's answer are
reproducible and which are not. It covers `parallel` bindings, `Par`'s
pools (`parMapWords`, `parMapWordsChecked`) and `Task`'s
(`taskMap`, `taskMapWith`, `taskFold`), at any width and in both
lowerings.

A workload is *pure* here when every binding and task computes from
its argument and its captures alone. It reads no clock, pid, input or
shared mapping, and nothing another task writes.

*Result order.* A `parallel` form joins in the order written
(`MM-PAR-6`). The pools answer in submit order: slot `i` holds task
`i`'s answer (`MM-PAR-5`). The width decides only how many run at once.

*Reduction order.* Every combination the language and the library make
is in index order. `taskFold`'s step sees the answers in submit order,
so it is the left fold `step(... step(step(init, 0, r0), 1, r1) ...)`
at every width. A `parallel` body combines the joined words as its
source says. No library fold combines in completion order, and none
exposes it. What a program builds itself can: a fold over what one
channel receives from several senders sees the words in the order the
sends took the channel's lock, which is the scheduler's order. The
price of index order is `MM-PAR-5`'s: a slow task holds back the tasks
`width` places behind it.

*Floating point.* `+`, `-`, `*` and `/` on `Float` are IEEE 754
binary64 operations, rounded to nearest. The emitter writes no
fast-math flag, no `fmuladd` and no fp-math attribute, and neither
`opt` nor `llc` adds contraction or reassociation where the IR doesn't
ask. So the same operations in the same order give the same bits at
every `--opt` level, width and lowering, on both instruction sets.
`__intToFloat` rounds to nearest. `__floatToInt` truncates toward
zero and saturates: a NaN answers 0, and a value beyond `Int`'s range
answers the nearest end. A different association is a different
answer: 2,000 terms summed in 2, 3, 4 or 8 chunks and in index order
differ in their last bits, and each is right for its association.

Three limits:

- A NaN's payload and sign are the hardware's, so only its NaN-ness is
  reproducible.
- `fmtFloat` rounds to six places. Send a `Float` between tasks as the
  `Int` of its bits (`cast`), which is exact.
- A float literal is converted by the parser in two roundings, and one
  whose integer part is 2^63 or more, or with 19 or more fractional
  digits, wraps. Reproducible, but not the nearest double.

*Errors.* When several parts fail:

| Construct | The failure the caller sees | Deterministic |
|---|---|---|
| `parallel`, processes | the first binding in written order whose child failed | yes |
| `parallel`, threads | whichever binding trapped first | no |
| `parMapWords` | the status of the lowest failing index: the joins run in submit order and the first failed join raises | yes |
| `parMapWordsChecked`, `taskMap`, `taskMapWith`, `taskFold` | every failure, each in its own slot with its own status | yes |
| any pool with `failFast` | the first failure the pool *observes* cancels the rest; which slots answer 1002 is the clock's | no |

A refused spawn (78, or 70) is the environment's answer, not the
workload's, and where it lands depends on the kernel. The trap
messages on fd 2 interleave in the order the parts died.

*Cancellation and timeouts.* A deadline, a grace and a cancellation
from another binding all read a clock, so whether a task answers or
answers `sysTimedOut` or `taskCancelledCode` depends on timing. Two
things don't: a pool whose token is set before it starts answers
`taskCancelledCode` for every task, and a pool with no deadline, no
`failFast` and no token another binding can set has nothing timed in
it.

*Side effects.* Ordered collection orders the answers, not what the
parts do. Writes to fd 1, files, shared mappings and channels
interleave as the scheduler ran them.

*Evidence.*

- `scripts/check-task.sh` §10 adds 2,000 terms through `taskFold`,
  `taskMap`, `parMapWords` and `parMapWordsChecked` at widths 1, 2, 3,
  4 and 8 in both lowerings, with the tasks made to finish out of
  order. Each answer is the sequential sum's bits, and Python's IEEE
  doubles compute the same bits.
- The same section runs `parallel` with 1 to 8 bindings, each equal to
  the chunked association. The reverse, pairwise and chunked sums each
  differ from index order, which shows the data can see an order.
- `parMapWords` raises the lowest failing index's 77 in fifteen runs
  per lowering, while 72 and 82 arrive first.
- The IR, and `opt` and `llc -O3` output, hold no contraction or
  reassociation, beside controls whose IR asks for each and shows it.
- Two ablations turn the section red: a pool that delivers in
  completion order, and a raising pool that joins newest first.
- `tests/stdlib/620-par-float-order.ax` and
  `tests/stdlib/621-par-first-failure.ax` pin the bits and the
  failures, and `tests/stdlib/622-float-to-int.ax` the conversion's
  answers, each at every `--opt` level (`.optstable`). The goldens are
  darwin-aarch64's, and every leg that runs
  `scripts/run-stdlib-tests.sh` holds its target to the same bits;
  built for linux-x86_64, the three print them at `--opt` 0 and 2.
- `scripts/check-parallel.sh` §9 measures the two lowerings' two
  traps.

---

## 7. Foreign memory

**MM-FFI-1 (H, amended).** Axiom has an FFI, and a program that doesn't
use it is unchanged.

The FFI is the `extern` block ([ffi.md](ffi.md)), and the emitter
writes a `declare` for every item in it.

`foreign` is removed, and using it reports `AX2004`, as does `union`.
`foreign` named one symbol and emitted a call without a `declare`, so
programs using it passed `check` and failed in `opt`. Use an `extern`
block instead. `region` is different: it is `MM-RGN-1`'s checked scope
([§3.6](#36-checked-lexical-regions)), a scope the program brackets
rather than an annotation.

The freestanding property comes in tiers. Each tier is measured with
`nm -u` on the linked executable (darwin-aarch64):

| program | undefined symbols | forbidden libc names |
|---|---|---|
| no `extern` | **0** | 0 |
| no `extern`, `parallel` under `--threads` | **3** on Darwin (`pthread_create`, `pthread_join`, `__tlv_bootstrap`), **2** elsewhere | 0 |
| `extern` → a `no_std` Rust crate | **0** | 0 |
| `extern` → a `std` Rust crate | 188 | 18 |

So the FFI keeps the property that makes `MM-PAR-3`, `MM-ALLOC-1` and
all of §3 true. A program gives it up only by linking `std`, and only
for that link. A `no_std` crate whose `alloc` is wired to `axiom_alloc`
puts Rust's allocations inside the arena, where §3 governs them.

*Evidence:* `scripts/check-freestanding.sh` checks the first tier and
ends with a negative probe that `foreign` is refused as `AX2004`.
`scripts/check-ffi.sh` checks the other two against the allowlist
`MM-FFI-5` requires.

**MM-FFI-2 (H).** Foreign *memory* still exists, because the kernel
writes into the process and a program can call `mmap` itself. There are
five boundaries:

| Boundary | Who owns the memory | Rules |
|---|---|---|
| `__syscall0`–`__syscall6` | the kernel writes into buffers the program allocated | the program **MUST** pass an address and a length it owns; nothing is checked |
| `argv` / `envp` | the kernel, outside every chunk | valid for the process's whole life; **MUST NOT** be freed or reset. The memory is writable: `(__store8 (strData (sysArg 0)) 0 88)` succeeds and the next read sees the change. A program **MUST NOT** write it, but nothing stops one |
| `mmap` regions the allocator maps | the allocator | §3 |
| `mmap` regions the **program** maps through `__syscallN` | the program | outside every arena; not scrubbed, not reclaimed, not counted (`MM-FFI-3`). This is also the one route to `MM-PAR-4`'s escape |
| `(__addr "literal")` | the loader; a read-only constant | valid for the process's life; **MUST NOT** be written |

**MM-FFI-2a (H, program obligation).** `__addr` takes the address of a
literal's bytes, so its argument must be syntactically a string
literal. Any other argument is refused as `AX3072`
(`tests/diagnostics/1003-addr-nonliteral.ax`). The emitter would
evaluate it like any expression, so `(__addr s)` on a `Str`-valued
variable would yield the two-word *header* address of `MM-VAL-7`, not
the data pointer, and a caller would read the length word as text.

**MM-FFI-3 (H).** Memory that didn't come from `axiom_alloc` is
*outside the arena*. It is not scrubbed (`MM-ALLOC-6`), not reclaimed
by a reset (`MM-ALLOC-13`), and not counted by the high-water mark.

Passing such an address to `__axiom_arena_reset_keeping` as the kept
block is **undefined**. The primitive copies from it into arena memory,
which is well-defined only if the source stays readable across the
reset. Kernel memory does, but a reclaimed chunk's interior may not.

**MM-FFI-4 (H, program obligation).** `strCStr` hands a `Str`'s bytes
to a syscall without copying, relying on `MM-VAL-7`'s NUL terminator.
A program that builds a `Str` by any other route than the `Str` module,
including `__store8` into a buffer it allocated, **MUST** keep that
terminator, or the syscall reads past the end.

**MM-FFI-5 (H, discharged).** The FFI meets all four minimum
requirements this clause set for it.

| # | Requirement | How |
|---|---|---|
| 1 | foreign memory is a distinct type from `Int` | `Foreign` is a builtin type name (`typeKeywordCanon`). `tyCompat` requires two named constructors to match by name, so `Foreign` is distinct wherever a type is compared, not only at a return. `tyIsReprScalar` adds the declared-return-vs-body case. `Handle` is the second builtin (`typeKeywordCanon`, `tyIsReprScalar`), distinct from both `Int` and `Foreign`. Requirements 1 and 2 cover it with the opposite classification: it is a reference in `fldClass` and `evClassOf`, so its map bit is set and release follows it into the foreign form (`MM-FFI-6`) |
| 2 | no arena primitive applies to it | `scalarTyName` classifies `Foreign` as class 0, so `fldClass` leaves its bit clear in the reference map and `@axiom_release` never follows it. For `(struct T (a : String) (b : Foreign) (c : String))`, the emitted shape word maps payload words `[0, 2]`: the map skips the `Foreign` and carries on past it |
| 3 | a foreign call is an inferred effect like a syscall | an `extern` item's `FnEnt` is seeded with `IO` and `Unsafe` at registration. Its caller declares `effect(unsafe)` (`AX3073`); a reviewed wrapper contains `Unsafe` as in MM-EXEC-9d. `restrict(no-unsafe)` rejects a path reaching an extern before such a wrapper |
| 4 | `check-freestanding.sh` replaced by an enumerating gate | `scripts/check-ffi.sh` reads each crate's `axiom-allow.txt`. The original gate stays alongside it, because a program with no `extern` still has to pass the strict version |

Requirement 2 matters most, and half of it is being *classifiable*. An
unknown type name is unclassifiable, which forces the whole block to
leaf. A record holding an unregistered foreign type would lose the
reference map for all its other fields and leak them. Registering
`Foreign` is what keeps the rest of such a record reclaimed.

Axiom has no `Slice` or `Outcome` type, and doesn't need one. A shim
that returns bytes, or that can fail, needs two words back, but Axiom
emits `ret i64` for everything. Those shims take a trailing out-cell,
and the decoding half is generated Axiom, not a compiler feature. This
keeps the rule the whole design rests on: only Axiom's own emitter
writes an Axiom heap block, because only it knows the shape word.

**MM-FFI-6 (H). The foreign form and the `Handle`.** A `Handle` is a
Rust value the program *owns a share of*, as opposed to a `Foreign`
word it merely holds. It is a counted heap block whose shape word has
bit 0 set. This is the *foreign form*, a third form beside
`MM-LIFE-2d`'s record and array forms.

Its two payload words are the address of a C destructor `i64 (i64)`
(word 0) and the Rust pointer that destructor takes (word 1). Its count
word is an ordinary count, retained and released by the same events as
any block. The form has exactly one writer in the tree, `ffiHandleNew`
in `stdlib/Ffi.ax`. `memAllocMapped` masks its map to bits 16..62 and
can't set bit 0, and a constructor site never does.

A raw `extern` item **MUST NOT** answer `Handle` (`AX3036`,
`tcCheckExternTypes`). It answers `Foreign`, and `ffiHandleNew` is the
only way to turn a word into a share.

The implementation obligations:

- `Handle` **SHALL** be a reference class in every classification.
  `fldClass` answers 2 and `evClassOf` answers 1 (their reference
  classes), so a cell holding one maps it, a `let` of one is released
  at scope end, and it is never matched against a literal. `Foreign`
  stays class 0, a word that is never walked, so requirement 2 of
  `MM-FFI-5` is unchanged.
- When a foreign-form block's count reaches zero, `@axiom_release`
  (`codegen.ax`, label `foreign:`) **SHALL** read both words. If both
  are non-zero, it stores 0 into word 1 and calls word 0 with the old
  word 1, *once*. Then it files the block by its size class like any
  other. A block of this form has no reference map and is never
  walked. A closed handle, with word 1 already 0, dies calling nothing.
- `ffiHandleClose` is the early close. It runs the destructor now,
  zeroes word 1 and answers 0. A second close is a no-op, and the
  block's own later death calls nothing. A shim that borrows a closed
  handle aborts rather than dereference 0: it prints
  ``axiom-ffi: `f`: handle is closed`` and exits with status 73. That
  is the FFI's own status, separate from `MM-EXEC-16`'s 72.
- Re-entrancy is permitted: the destructor **MAY** call
  `axiom_release`, as a Rust `Drop` does when it returns shares the
  shim took under [ffi.md](ffi.md) C1. Each invocation of
  `@axiom_release` keeps its dead list in a local and stores nothing
  else anywhere. So the re-entrant call is an ordinary one, and the
  outer invocation's list is undisturbed.

The program obligations are [ffi.md](ffi.md) C5 and C7: the destructor
is `i64 (i64)`, null-safe, and never unwinds. `#[axiom_opaque]`
generates one that is, and a hand-written one must match it.

*Evidence:* `tests/ffi/demo/060-opaque-handle.ax` builds 200 `Counter`s
and lets them go in a loop, with no close call anywhere. The Rust
`Drop` runs 200 times through the handle, and one explicit
`counterClose` on a handle still held makes 201. The emitted
`@axiom_release` carries the `foreign:` arm (`grep foreign: <out>.ll`
after `--emit-llvm`). `tests/ffi/demo/410-foreign-not-walked.ax` and
`tests/ffi/demo/420-null-foreign.ax` pin the converse for `Foreign`.
`tests/ffi/demo/430-reentrant-drop.ax` covers the re-entrancy clause:
100 values are freed through a `Drop` that calls back into
`axiom_retain`/`axiom_release` mid-release, and the drop and retain
counters agree at 100.

**MM-FFI-7 (H, program obligation). A `Foreign` captured by
a thread binding is shared, and its thread-safety is the foreign
side's.** `AX3064` accepts a captured `Foreign` because the release
walk never follows one, so there is no Axiom count to race. That is all
the checker can say (`tests/diagnostics/655-parallel-capture-foreign.ax`).

Under the thread lowering, both threads hold the same foreign object.
Whether it may be used from two threads at once depends on the code
behind it, which no Axiom rule can see. Under the process lowering,
each child holds its own copy-on-write copy of any foreign state in the
process image. A foreign object backed by something outside the image,
such as a file descriptor, a mapping or a device, is shared exactly as
the kernel shares it.

**MM-FFI-8 (H, 2026-09-27). Device memory is reached by volatile
access at the device's width, and volatile is not synchronisation.** A
memory-mapped device register is foreign memory in `MM-FFI-3`'s sense -
outside the arena, never scrubbed, reclaimed or counted - and it has
two properties ordinary memory does not: an access can have an effect
beyond the value (a read pops a FIFO or acknowledges an interrupt, a
write rings a doorbell), and the WIDTH of the access is part of its
meaning. The eight primitives for it:

| Primitive | Lowers to | Answers |
|---|---|---|
| `(__vload8 a)` `(__vload16 a)` `(__vload32 a)` `(__vload64 a)` | one `load volatile iN, ptr a, align N/8` | the value, zero-extended to the word |
| `(__vstore8 a v)` `(__vstore16 a v)` `(__vstore32 a v)` `(__vstore64 a v)` | one `store volatile iN (trunc v), ptr a, align N/8` | 0 |

`a` is the byte address itself - not `__store8v`'s `base + i` (that
older primitive is unchanged and keeps working). Each is `Unsafe`
(`MM-EXEC-9c`) and carries `Mut`: a store writes, and a device read may
change device state, so a load is not the side-effect-free read
`__load64` is.

*What the implementation guarantees* (implementation obligation). The
compiler **MUST NOT** delete, duplicate, merge, split, widen or narrow a
volatile access, and **MUST NOT** reorder two volatile accesses against
each other in one thread of execution. That is LLVM's `volatile`
contract, and it is what a device needs: a 32-bit register read as two
16-bit halves, or a doorbell write dropped because nothing reads it
back, is a wrong program even when every value is right.

*What it does NOT guarantee*, and each is a program obligation:

- **Alignment.** `a` **MUST** be a multiple of the access width. A
  misaligned volatile access is undefined in the IR, and on the
  bare-metal port, which maps devices Device-nGnRnE and sets
  `SCTLR_EL1.A` (`MM-EXEC-19`), it is an alignment fault.
  `stdlib/Mmio.ax` checks alignment once, where a register handle is
  made.
- **Ordering against ordinary memory.** The compiler may move a
  non-volatile load or store across a volatile one. Where a device
  reads memory the CPU wrote with ordinary stores - a DMA descriptor -
  the program **MUST** place a barrier between them: `__arm_dmb` orders
  (`DMB SY`: every memory access before it, as observed by every
  observer in the system, device included, before every access after
  it) and `__arm_dsb` completes (`DSB SY`: no instruction after it
  executes until the accesses before it have completed). Every
  `__arm_` primitive that orders, waits or writes is also a COMPILER
  barrier (`~{memory}`), so no load or store is moved across one.
- **Synchronisation.** A volatile access is not an atomic and creates
  no happens-before edge. A flag written volatile by one binding and
  polled volatile by another does not publish the data written before
  it: that is `MM-PAR-9`'s atomics, and a race through volatile is
  still a data race. Volatile IS the right tool on ONE core for a word
  an interrupt handler writes and the interrupted code polls, because
  what must be prevented there is the compiler caching the word in a
  register - interrupt entry and return are context-synchronising, so
  the hardware needs nothing more (`MM-EXEC-18`, where the handler's
  rules are).
- **Atomicity beyond one access.** A naturally aligned access of 8 to 64
  bits is single-copy atomic on AArch64; a read-modify-write
  (`mmioModify`) is three operations and is not.

*The AArch64 set*, `__arm_*`, is one instruction each: `__arm_dmb`,
`__arm_dsb`, `__arm_isb` (`DMB SY`, `DSB SY`, `ISB`); `__arm_cntvct`
and `__arm_cntfrq` (read `CNTVCT_EL0`, `CNTFRQ_EL0` - the counter read
is also a compiler barrier, because it is a timestamp); `__arm_ctr`
(`CTR_EL0`, the cache geometry); `__arm_set_cntv_cval`,
`__arm_set_cntv_ctl` (the virtual timer's compare value and control);
`__arm_irq_mask`, `__arm_irq_unmask` (`msr daifset/daifclr, #2`);
`__arm_wfi`; `__arm_dc_cvac`, `__arm_dc_civac` (clean, and clean and
invalidate, the data-cache line holding an address to the point of
coherency - both `Unsafe`); `__arm_tpidr`, `__arm_set_tpidr`
(`TPIDR_EL1`, a word of software state the hardware keeps for the
program). The barriers and the two counter reads run at EL0 on an
aarch64 host; everything else needs EL1, which only
`baremetal-aarch64` runs a program at. A primitive the target cannot
execute is refused at build time as `AX4008`, reading the module after
unreachable functions are pruned, so a helper nothing calls is never
refused - a refusal rather than a lowering to nothing, because a
barrier that silently vanished is a program that is wrong at run time
for a reason known at build time.

*Evidence:* `scripts/check-embedded.sh` A11 - each width is two
volatile loads and two volatile stores at natural alignment in the IR;
after `opt -O2` the dead-looking first write of every pair survives
while the same double write through `__store8`/`__store64` - the
control - loses it; `llc` keeps each width (`strb`/`strh`/`str w`/
`str x` and their loads); every `__arm_` primitive is its instruction in
the IR and in the assembly; and `AX4008` draws the target line, with
an EL1 primitive in an uncalled function accepted. The `volatile`,
`barrier` and `refusal` drills each turn it red. *Limit:* QEMU's TCG
models neither caches nor the reordering a real memory system does, so
no execution in this tree can observe a missing barrier; the barriers
are verified as EMITTED, not as effective on hardware
(`docs/embedded-guide.md`).

**MM-FFI-9 (H). Inline assembly is an `asm` form, checked where it is
written and emitted only for the architecture it names.** Use it for
an instruction no primitive covers:

```scheme
(:: cycles Int)
;@axiom:effect(unsafe)
(fn (cycles)
  (asm
    (aarch64 "mrs {t}, cntvct_el0" (out t))
    (x86_64 "rdtsc\nshlq $32, %rdx\norq %rdx, %rax" (out t "rax") (clobber "rdx"))))

(:: main Int)
(fn (main)
  (if (> (cycles) 0)
    0
    1))
```

A form is `(asm ARM...)`, and an arm is `(ARCH "template" operand...)`
with `ARCH` either `aarch64` or `x86_64`, one arm each at most. The
operands are:

| Operand | Meaning |
|---|---|
| `(in name value)` | `value`, an `Int`, in a general-purpose register |
| `(out name)` | a register the form answers when the instructions end |
| `(inout name value)` | starts as `value` and is answered, in one register |
| `(clobber "reg"...)` | registers the instructions write that no operand names |

Any of the first three may name its register, as in `(in a "x8" v)`.
An arm answers at most one value; with no `out` or `inout` the form
answers 0. In the template, `{name}` is the operand's register,
`{name:m}` a view of it (`w` or `x` on aarch64; `b`, `h`, `w`, `k` or
`q` on x86_64), and `{{` and `}}` are literal braces. Everything else
reaches the assembler as written, `$` included. x86_64 templates use
AT&T syntax.

*What the implementation guarantees.* The compiler **MUST** refuse a
malformed form where it is written, with `AX3091`. That covers an
unknown architecture or operand kind, a second arm for one
architecture, a template naming no operand, a second output, two
operands in one register, and a register an arm can't name. The stack
pointer, the frame pointer and AArch64's `x18` are never nameable, and
`x30` only as a clobber.

It **MUST** emit only the arm for the target's architecture. That arm's
inputs are evaluated once each, in the order written, before its
instructions, and no other arm's inputs are evaluated, though every arm
is type-checked. A form with no arm for the target is `AX4008` when a
function the program reaches holds it, so a portable module may hold an
arm per architecture.

Every block is kept and ordered as a side effect (`sideeffect`) and
clobbers memory and the condition flags, so it moves across no load,
store or other side effect. An `out` never shares a register with an
input (`=&r`).

*What it does not guarantee*, each a program obligation:

- **The instructions.** The compiler can't see what they do, so an
  `asm` form is an unsafe operation of the declaration holding it
  (`MM-EXEC-9c`). That declaration says `;@axiom:effect(unsafe)` and
  vouches that the instructions keep every rule of this document,
  exactly as a trusted encapsulation vouches for a raw access
  (`MM-EXEC-9d`). Any IO, blocking or trap they perform is the
  declaration's to state.
- **The registers and the stack.** The instructions **MUST** leave the
  stack pointer and the frame pointer as they found them, write no
  register but the outputs and the clobbers, and use no stack. The
  stack bound of `restricted-profile.md` rests on that.
- **Control flow.** The instructions **MUST** end by falling through:
  no branch out of the block, no return and no exception return.
- **The assembler.** `check` does not assemble a template. An
  instruction the target's assembler rejects fails the build with the
  assembler's message.

*Limits.* Operands are `Int` words in general-purpose registers: no
memory, floating-point or vector operands, and one output. Vector
registers may be clobbered.

*Evidence:* `tests/stdlib/581-inline-asm.ax` answers the same on
aarch64 and x86_64 at every `--opt` (`.optstable`).
`tests/diagnostics/1044-inline-asm.ax` refuses each malformed shape
beside a well-formed control, and
`tests/diagnostics/1045-inline-asm-unsafe.ax` holds the unsafe boundary.
`scripts/check-embedded.sh` A15 keeps an unused block through
`opt -O2`, checks the lowering on every target, and draws `AX4008` for
a reached form with no arm and nothing for an unreached one.

---

## 8. Formal invariants

These are the guarantees a compiler author can build on. Each row says
what breaks if the invariant is violated.

| # | Invariant | Depends on | If violated |
|---|---|---|---|
| **I1** | Every value is one 64-bit word | `MM-VAL-1` | every calling convention in the emitter |
| **I2** | No word is self-describing; no heap block has a layout header | `MM-VAL-2`, `MM-VAL-6` | nothing, but code that assumes the *opposite* breaks: that is how `ArenaCompact` corrupted `scanDecls` |
| **I3** | Every heap address handed out for a value is ≥ 4096, and no immediate tag is | `MM-VAL-9` | a mixed-representation `match` silently picks the wrong arm |
| **I4** | Constructor tags are globally unique | `MM-VAL-8` | one runtime tag read can't serve every constructor's compare |
| **I5** | Every allocation is 16-byte aligned | `MM-ALLOC-3` | unaligned `double` loads; `Str` headers straddling |
| **I6** | Memory obtained *through `axiom_alloc`* reads as zero | `MM-ALLOC-6` | `Map` reads stale occupancy; `strAlloc` loses its terminator |
| **I7** | A reset writes nothing to what it reclaims | `MM-ALLOC-14` | copy-at-boundary reads scrubbed bytes, with 39,841 of 40,000 bytes wrong |
| **I8** | Marks nest, and a mark is never reclaimed by its own reset | `MM-ALLOC-12` | a mark reset out of nesting order restores a position from freed memory. This is enforced: it traps with status 75 (`MM-ALLOC-16a`, `tests/stdlib/166-arena-bad-mark.ax`). Resetting the *same* mark twice is legal and harmless: the cell is never reclaimed by its own reset, so it stays readable, and the second reset finds its chunk still active and takes the equal-chunk fast path. The harm comes from resetting an inner mark after its outer one |
| **I9** | Chunk addresses are unordered | `MM-ALLOC-5` | a backward copy across chunks corrupts |
| **I10** | Language heap values are not stack allocated; frames, `mut` cells, merge scratch and lexical region mark cells may be on the stack | `MM-ALLOC-11`, `MM-RGN-1` | a stack address escaping its activation could dangle |
| **I11** | All allocator state is process-private | `MM-PAR-3` | a shared-address-space pool would need atomics |
| **I12** | Compilation is deterministic and reproducible | `MM-EXEC-13` | `scripts/check-reproducible.sh` |
| **I13** | The compiler executes no user code | `MM-EXEC-14` | the threat model |
| **I14** | The heap graph **may** contain cycles | `MM-LIFE-3` | the chosen ARC leaks them at a stated cost (`MM-LIFE-2f`); any future cycle collector must trace them, with the maps `MM-LIFE-2d` specifies |
| **I15** | Reclamation occurs at the events enumerated by `MM-LIFE-4`, including lexical-region reset and thread-arena teardown | `MM-LIFE-1`, `MM-RGN-6`, `MM-PAR-6a` | an alias surviving one of those events can dangle |

Three invariants need a closer reading than their one-line form:

- **I3** says "handed out for a value" because `(__alloc 0)` answers
  the unadvanced bump pointer, which is address 0 before any chunk
  exists (`MM-ALLOC-8b`). No value is ever stored there, since a
  zero-byte request stores nothing, so the `< 4096` test still works.
  But the plain sentence "every heap address is ≥ 4096" is false.
- **I6** says "through `axiom_alloc`" because
  `__axiom_arena_reset_keeping` carves its destination directly and
  leaves it unscrubbed (`MM-ALLOC-15a`). The copy initialises it, and
  the padding up to the 16-byte rounding holds whatever was there
  before. Memory that reaches a program by that route has not been
  zeroed.
- **I15** includes release: through `MM-LIFE-2e`'s release path, dead
  blocks reach a size-class free list, and `MM-LIFE-2c`'s seven events
  release. What §3 may assume still holds almost entirely. The default
  is unchanged (`MM-LIFE-1`): a value nobody releases lives as long as
  the process. The compiler's own containers and AST declare their
  handles `Int`, so no type-directed ownership event fires on them.
  With `MM-LIFE-2a` withdrawn (§9), this is the invariant's permanent
  form.

---

## 9. Conformance summary

Each range below excludes any rule listed in another column of the same
row. A range that swallowed a **P** or **R** rule would report the
opposite of that rule's status.

| Area | Holds today | Planned | Withdrawn | Refused |
|---|---|---|---|---|
| Execution | EXEC-1…6d, 8…13, 15…17 | — | — | EXEC-7, EXEC-14 |
| Representation | VAL-1…11, 10a, 14…20, VAL-22, VAL-23 | — | — | VAL-12, VAL-13 |
| Allocation | ALLOC-1…7, 7a, 8a…16b, ALLOC-22…25 | ALLOC-20 | ALLOC-17…19, ALLOC-21 | ALLOC-8 |
| Regions | RGN-1…4, 5a, 6 | RGN-7 | RGN-5 | — |
| Mutation | MUT-1…5a | — | — | MUT-6 |
| Lifetimes | LIFE-1, 3, 4, 6, 2g…2i, 2k | LIFE-7 | LIFE-2a…2f (superseded by ALLOC-22), LIFE-5 (superseded by LIFE-4/RGN-6) | LIFE-2 |
| Parallelism | PAR-1…5, 6a, 7…13 | PAR-6 | — | — |
| Foreign | FFI-1…7 | — | — | — |

`MM-VAL-21` is refused: see §2.4.

The Lifetimes row's Withdrawn column is §0.3's second kind, abandoned
in place. `LIFE-2a…2f` were withdrawn *after* most of their machinery
shipped:

- all seven of `LIFE-2c`'s events emit;
- `LIFE-2b`'s header is on both allocation paths;
- `LIFE-2d`'s monomorphic, evidence and `Str` halves hold;
- `LIFE-2e`'s release path files dead blocks.

None of that comes out. That is why `LIFE-2g` is **H**, and why §9.0
records the standing cost of the half-finished state. Read the column
as *no longer being finished*, not as *not there*.

Three identifiers in this document were once defined twice, which §0.1
forbids. In each pair, the rule with fewer citations and the later
arrival was renumbered. The two criteria agree on all three pairs.
`scripts/check-doc-drift.sh` now rejects a rule identifier defined
twice.

| Was | Meaning | Cited | Now |
|---|---|---|---|
| `MM-LIFE-2e` (§5) | the ARC release path | 19 | unchanged |
| `MM-LIFE-2e` (§3.5) | `cast` degrades the evidence word | 1 | **`MM-VAL-22`** |
| `MM-LIFE-2f` (§5) | cycles under counting | 1 (plus `I14`) | unchanged |
| `MM-LIFE-2f` (§3.5) | the typed accessor is the safe vehicle | 1 | **`MM-VAL-23`** |
| `MM-ALLOC-17` (§3.4) | the implicit per-activation arena, **W** | 0 outside this file | unchanged |
| `MM-ALLOC-17` (§3.3) | a trap may abort to a mark, **H** | 1 | **`MM-ALLOC-23`** |

The §3.5 pair became `MM-VAL-*` because both rules are about the
evidence word and `cast`, which are §2's subject rather than §5's.

### 9.0 Defects this specification records

Each row is a place where the implementation does something the rest
of the documentation wouldn't lead you to predict. A rule withdrawn in
place also records its standing cost here (§0.3). A closed defect is
either struck through and marked **CLOSED**, or listed after the table
with the fixture that pins it.

| Rule | Defect |
|---|---|
| `MM-ALLOC-8b` | `(__alloc 0)` returns the bump pointer without advancing it, which is address 0 before any chunk exists |
| `MM-VAL-4c` | `(!= NaN NaN)` is `false`, and `Fmt.fmtFloat` can't render inf or NaN |
| ~~`MM-VAL-3b`~~ | **CLOSED.** `INT_MIN / -1` and shifts of 64 or more were undefined, and answered differently at each `--opt` level. Both are guarded traps now: `INT_MIN / -1` exits 83, an out-of-range shift exits 84, and each is recoverable. `tests/stdlib/695-intmin-div-trap.ax` and `tests/stdlib/696-shift-wide-trap.ax` gate them, and `restrict(no-trap)` - spelled `no-untrapped` until the guards landed - still refuses the raw operators in favour of `stdlib/Err.ax`'s checked arithmetic |
| `MM-EXEC-9a` | Effect inference under-approximates. Of seven known gaps, six are closed: `__alloc`, trait dispatch, `__store8`/`__store64` (`Mut`), `__argc`/`__argv` (`IO`), the arena primitives (`Alloc`) and constructor allocation. One remains: a call through a local, a parameter or an unresolved name. It sets `#effects-incomplete` instead of reporting a set that looks complete |
| `MM-LIFE-7` | `consume` and `alloc` win as expression heads, so you can define a function with either name but can't call it |
| `MM-LIFE-2j` | **Resolved by removal in 0.6.0.** A trait default body's shape word depended on `impl` declaration order. `checkImplComplete` synthesised the default into every impl that omitted the method without copying the body's nodes, so one AST was checked once per implementing type, and per-node stamps were last-write-wins across the monomorphisations. On the fixture `373-shared-default-binder` in 0.3.0, `Ident#String#ident` got header `131076` and `axiom_retain(%x)` with the `Int` impl declared first, and header `4` (a leaf) with no retain with the `String` impl first. Removing traits removed the only way to check one body under two type environments. Emitted IR from a last-write-wins compiler is byte-identical to the tree's across 278 fixtures, every `stdlib/` module and `self_host/main.ax`. `scripts/check-fallible-reclaim.sh` asserts that the case stays unreachable, so the rule stays listed: a future construct that re-checks a body per instantiation would bring it back |
| ~~`MM-EXEC-16`~~ | **CLOSED.** Status **72** meant division by zero here, and also, in `docs/ffi.md` C7, the exit a `no_std` crate's panic handler took. A supervisor reading the status couldn't tell an Axiom division from a Rust panic. The FFI exit moved to **73**, which `MM-EXEC-16` doesn't reserve, and `tests/ffi/demo/115-abort-status.ax` gates it |
| ~~`MM-LIFE-2a`~~ | **CLOSED.** The defect was that nothing measured this cost. The cost itself stays, by design: every arena reset charges **4,097** slab-head stores on the once-per-request path, because releases file blocks into those heads and a head left dangling across a reset double-issues storage. `scripts/check-arena-reset-rate.sh` measures it. Three spellings of one program, one word apart, put a reset at **about 1.35 µs** against a mark's few nanoseconds. A fourth binary, built by deleting the `slabclear` block from the emitted IR, shows the scrub is the cost. The emitter's `[4097 x i64]` and loop bound are asserted with no clock involved. The cost is **1.7–1.8%** of the 77 µs per-connection budget |

These defects are fixed, and each is pinned by the fixture its rule
names:

- `MM-ALLOC-8`'s silent duplicate symbol is `AX3026` at `check`.
- `MM-VAL-9a`'s unguarded field access is `AX3070` on any `data` type
  with a nullary constructor.
- `MM-VAL-9b`'s literal-match fall-through is `AX3005`.
- `MM-MUT-1a`'s `set` on a parameter or capture is `AX3012` in the
  checker.
- `MM-VAL-3c`'s and `MM-VAL-4b`'s width-less type names are removed
  (`AX3002`). The float spellings had the checker treating them as
  floats while the emitter emitted integer arithmetic.
- `MM-EXEC-15a`'s `main` reference: the table lookups normalise the
  emitted symbol back to the declared spelling, so a recursive `main`
  compiles and runs.

### 9.1 What is gated, and what is only written down

This section lists the rules a gate pins, and names the ones that are
only written down.

| Pinned by a gate | Rules |
|---|---|
| `tests/stdlib/165-arena-keep.ax` | ALLOC-14, ALLOC-15 (overlap over 500 rounds, chunk crossing, a 2 MiB oversize block, zeroing) |
| `tests/stdlib/160-arena.ax` | ALLOC-12, ALLOC-13 (waterline, 64-byte contiguity, reuse, nesting, chunk crossing, zero-on-reuse) |
| `tests/stdlib/166-arena-bad-mark.ax` | ALLOC-16a's implementation half. Resetting an inner mark after its outer one traps with status 75. The two legal shapes beside it (nested marks reset innermost first, and the same mark reset twice) stay silent, so the trap is pinned against firing on correct use as well as against failing to fire |
| `tests/stdlib/167-arena-live-handle.ax` | ALLOC-16b's implementation half. Resetting a mark that predates a live `handle` traps with status 76. Two legal shapes stay silent: a mark taken inside the extent, and a mark with no handle in scope. `401-recover-effect.ax` still exiting 71 pins the recovery path, because an abort performs this reset legitimately |
| `tests/stdlib/110-tail-loop-alloc.ax` | that a self tail call does **not** reclaim what its iteration allocated, the negative of ALLOC-19 |
| `tests/stdlib/040-mem.ax` | the `Mem` primitives over ALLOC-3, ALLOC-6 |
| `tests/stdlib/358-str-owner-shares.ax` | VAL-7's counting rule: every header that names an owner holds a share of it |
| `tests/stdlib/359-arc-str-bytes.ax` | LIFE-2d's `Str` half end to end: a dead string frees its bytes, and a live slice keeps its parent's |
| `tests/stdlib/360-arc-evidence-map.ax` | LIFE-2c event 6 for the evidence record: its map, its two retains, and the handler lambda reclaimed with it |
| `tests/stdlib/361-arc-field-store.ax` | LIFE-2c event 5: a field store's retain and release, both counts measured, and `(set e.f e.f)` surviving |
| `tests/stdlib/362-arc-tail-boundary.ax` | LIFE-2c event 4 and LIFE-2g together: 480 bytes over 2000 iterations, and a stashed parameter surviving 300 boundaries |
| `tests/stdlib/363-arc-large-block.ax` | LIFE-2e's large-block policy: a 2 KiB block reused and scrubbed, class separation above 1 KiB, and the 64 KiB ceiling pinned in both directions |
| `tests/stdlib/364-arc-frame-release.ax` | LIFE-2c event 3's direct-construction subset: 640,224 bytes down to 256 over 20,000 builds, with the escaping control still growing |
| `tests/stdlib/220-while-mut.ax` | MUT-1 across 1,000,000 iterations |
| `tests/stdlib/035-string-equality.ax` | VAL-7's content equality, including the Unicode and interior-NUL cases |
| `scripts/measure-memory-baseline.sh --gate` | ALLOC-16's managed contract; the unsound variant must *fail* |
| `scripts/check-freestanding.sh` | ALLOC-1, ALLOC-8c, FFI-1 |
| `scripts/check-cross-targets.sh` | that every target's allocator and syscall lowering assembles at `-O0` and `-O2` |
| `scripts/check-bootstrap.sh` | that the compiler survives compiling itself under this allocator |
| `scripts/check-reproducible.sh` | EXEC-13 |
| `tests/stdlib/476-par-pool.ax` | PAR-5 |
| `tests/stdlib/520-alloc-size.ax` | ALLOC-7a: a negative size answers 70 at a recovery point, and 2^62 + 1 bytes exits 70, where the unfixed compiler answered an address |
| `tests/stdlib/521-release-filed.ax` | LIFE-2k: a double release of a filed block leaves the next two allocations aligned and reusing it, where the unfixed compiler handed out `base + 15` |
| `tests/stdlib/522-parallel-recover.ax` | PAR-7's recovery half: a trapping forked binding inside a recovery point answers 72 once, where the unfixed compiler printed twice |
| `tests/diagnostics/1010-unsafe-primitives.ax` | EXEC-9c: the nine primitives refused under `restrict(no-unsafe)` and `pure`, with three controls silent |
| `scripts/check-parallel.sh` section 12 | PAR-6a and PAR-7: thread churn holds address space flat, and no child outlives an abort, a trap or `main` |
| `scripts/check-handles.sh` | VAL-10a and PAR-8: a freed or forged channel or mutex, and a spawn handle joined twice or of the other lowering's kind, trap 85 at every `--opt` and in both lowerings; the table holds under four bindings at once and exactly one of two racing frees returns; the capture rule holds under `build --threads`; a record holding a handle maps as one holding an `Int`; three ablations each go red |
| `tests/selfhost/500-while-mut.ax` | MUT-1 in constant stack |
| `tests/diagnostics/465-set-on-parameter.ax`, `466-set-captured.ax` | MUT-1a: both refusals, byte-pinned in all three renderings |
| `tests/diagnostics/471-reserved-runtime-name.ax` | ALLOC-8's refusal arm (`AX3026`) |
| `tests/diagnostics/476-literal-match-fallthrough.ax` | VAL-9b |
| `tests/diagnostics/480-field-on-mixed-data.ax` + `tests/stdlib/210-struct-variants.ax` | VAL-9a: the refusal, and the half where every constructor has fields, which is still legal |
| `tests/diagnostics/495-widthless-types.ax` | VAL-3c, VAL-4b: the removed names are refused |
| `tests/selfhost/371-main-recursive.ax` | EXEC-15a: exits 5, where the unfixed compiler exits 4 |
| `tests/stdlib/314-out-of-memory.ax` | EXEC-16's status 70 and ALLOC-7: the sentence pinned in `.err` and the status in `.exit`, each checked on its own, reached deterministically at 2^60 bytes |
| `tests/stdlib/312-checked-arithmetic.ax` | VAL-3b's remedy: `addChecked`, `subChecked` and `mulChecked` at every boundary they have, with byte-identical stdout at `--opt` 0, 1, 2 and 3 |
| `scripts/check-net.sh` | ALLOC-22 (a request handler scoped as an arena uses 100–313× less memory than the same binary unscoped, with the negative probe that makes the flat column mean something) and ALLOC-4b (request sizes varying across three orders of magnitude don't ratchet the watermark) |
| `tests/stdlib/557-cycle-backlog.ax` | LIFE-2f's cost and ALLOC-24: 64 bytes a two-node knot, none for a chain, a broken knot or a scoped one |
| `tests/stdlib/558-size-classes.ax` | ALLOC-25 and ALLOC-24: each request's class, reuse across sizes of one class, and the exact filed count of one block per class |
| `tests/stdlib/560-recover-record.ax` | ALLOC-23: an arm allocates nothing, whether its thunk answers or traps |
| `tests/stdlib/555-release-deep-chain.ax` | LIFE-2d's walk: million-deep lists, trees and closure chains dropped whole, each second round served by the first |
| `tests/stdlib/556-count-balance.ax` | LIFE-2c and LIFE-2k through closures, containers, field stores, slices and a `Handle`: nothing freed while reachable, with a control that one release too many is seen |
| `tests/stdlib/559-reset-metadata.ax` | ALLOC-13 and LIFE-2e: every block zeroed and disjoint after a reset of every class, nested marks across chunks, a reset inside a recovery point and a released large block |
| `tests/stdlib/561-failed-operations.ax` | ALLOC-23: the heap is consistent after a trap inside a constructor and a refused `Vec` of 2^58 elements, and the obligation's safe shape |
| `scripts/check-reclaim-soak.sh` | LIFE-2d's bounded stack under 64 KiB, ALLOC-25's plateau, LIFE-2f's cycle cost, per-thread resets, and ALLOC-23's two obligations, each beside an ablation or a control that must move |

Some rules are only covered incidentally. Fixtures written for another
purpose exercise them, so a regression would surface, but under a name
that says nothing about the rule. That isn't the same as pinned:

- `tests/stdlib/170-gc.ax` and `200-scale.ax` allocate heavily, and
  would notice a broken allocator without asserting anything in §3.
- `320-effect-gc-roots.ax` keeps evidence records live across
  allocation without exercising `MM-ALLOC-16b`'s reset.
- The `Vec` fixtures build cycle-shaped structures (`MM-LIFE-3`) tens
  of thousands of times, without asking whether a cycle is
  constructible.

`MM-LIFE-2e`'s two acceptance measurements measure a withdrawn
strategy. They were the gate on ARC's arrival: the unmanaged Life
column at **33,568 KiB / 16 KiB per generation**, and the LSP's
**193,247 bytes per edit** with the boundary removed, against 840 with
it. `MM-LIFE-2a` is withdrawn, so nothing waits on either, and failing
them now blocks nothing. Both still matter as evidence. The LSP pair is
half the evidence for `MM-ALLOC-22`, and the Life column is the
contrast `scripts/measure-memory-baseline.sh --gate` measures its
managed variant against.

<!-- doc-gate:negative-exempt an inventory of gaps, which is the safe direction - it claims rules are UNGATED. A false version of this paragraph under-claims coverage; the defect this rule exists for over-claims it. -->
Every other rule is pinned by nothing, and the probes quoted inline
are its only evidence. Until a fixture exists, those rules are
documentation rather than specification. The highest-value gaps, in
order: `MM-VAL-9`'s 4096 boundary (a silent wrong-arm bug if it ever
moves), `MM-MUT-2`'s visibility through aliases, `MM-EXEC-6b`'s
self-TCO (a fixture would stop `reference.md` from misattributing it to
LLVM again), and `MM-LIFE-3`'s cycles stated *as* a property.

All twelve of `MM-EXEC-16`'s executable POSIX exit statuses are gated:

- 70 by `tests/stdlib/314-out-of-memory.ax`;
- 71 by `tests/stdlib/310-effect-unhandled.ax`;
- 72 by the division fixtures;
- 75 by `tests/stdlib/166-arena-bad-mark.ax`;
- 76 by `tests/stdlib/167-arena-live-handle.ax`;
- 77 by `tests/stdlib/464-index-trap.ax`;
- 78 by `scripts/check-parallel.sh` §12d, under a per-user process limit;
- 80 by `scripts/check-contracts.sh` §1;
- 82 by `tests/stdlib/544-misaligned-atomic.ax`;
- 83 by `tests/stdlib/695-intmin-div-trap.ax`;
- 84 by `tests/stdlib/696-shift-wide-trap.ax`;
- 85 by `tests/stdlib/570-handle-freed.ax`.

The 75 and 76 fixtures each pin the sentence, the status, and the
legal shapes the trap must stay silent on.

The remaining statuses belong to targets no POSIX runner executes:
74 and 79 to the two Windows targets, 81 to `baremetal-aarch64`
(measured under QEMU instead, `scripts/check-embedded.sh`).
`scripts/check-platform-constants.sh` reads 74's emission,
`scripts/check-parallel.sh` reads 79's, and README's *Targets*
section says no runner runs those targets yet.

Status 70 is reached deterministically, without exhausting anything.
`314` asks for 2^60 bytes, which is past the user address space on
every target, so the kernel refuses the mapping outright and macOS's
overcommit can't swallow the request as it does a terabyte. A smaller
size isn't enough: FreeBSD 14.4/arm64 granted 2^47. The message is
pinned in the case's `.err` and the status in its `.exit`, and each is
checked on its own (`MM-ALLOC-7`).

`scripts/check-doc-drift.sh` reads this document, so every `tests/`
path named here is checked for existence (the gate's rule 4).
`tests/docs/verify-doc-code.py` checks that delimiters balance in its
fenced code, and the fence markers (`fragment`, `refused`, `excerpt`)
mean here what they mean everywhere else. The prose itself isn't
checked. A status-row rule can't see that a sentence is false: the
README's Macros row stayed **Complete** for a season while wrong, as
the preamble of [macro-system.md](macro-system.md) records.

<!-- doc-gate:negative-exempt this paragraph is the rule's own statement and worked example; the quoted negative is the specimen being condemned, not a claim the document makes. -->
There is a sharper version of that problem. `check-doc-drift.sh`
proves reference *integrity*: every fixture a document names exists.
Integrity isn't truth. Its strongest check reads a sentence, extracts
a `tests/` path, and asks the filesystem whether the file is there. A
sentence claiming a fixture is *absent*, such as "70 … is the one no
fixture can reach without exhausting memory", names no path, so the
gate has nothing to resolve. That sentence was false, with every gate
green, until a person noticed.

The class is large. Any claim of the form "no X exists", "X is the only
Y" or "X cannot be reached" can't be checked by resolving paths, and a
specification's most useful sentences are often about what is absent.
Three were false at the same time, and none failed anything:

- the exit-status sentence above;
- `error-model.md`'s `ERR-ADOPT-3`, calling `self_host/lsp.ax` "the one
  long-lived Axiom program v1 ships", while a pre-forked server ran
  under CI;
- `MM-PAR-2`'s "the language has no construct that can name an
  external symbol", with `extern` blocks shipped and two `_tlv_*`
  symbols already listed in a reviewed allowlist.

The remedy is a documentation rule: *a normative sentence asserting a
negative **MUST** name the probe that would fail if the negative became
true.*

For example, "70 is the one no fixture can reach" names nothing. By
contrast, "70 is unpinned, and `tests/stdlib/314-out-of-memory.ax` is
the fixture that would exist if it were not" names a path. Once the
sentence carries a path, the existing rule 4 checks it in the direction
that matters. The day the fixture lands, the gate resolves the name
that proves the sentence wrong. That turns an unfalsifiable claim into
a claim about a file.

`scripts/check-doc-drift.sh` enforces the rule as its rule 5b. A
paragraph that pairs a negative with a word such as "fixture", "probe"
or "corpus" must name a `tests/` or `scripts/` path, carry a
`doc-gate:negative` marker naming its probe, or carry a
`doc-gate:negative-exempt` marker that says why it is narrative.

---

## 10. Rationale

### 10.1 Why no garbage collector

Collection isn't wrong, but Axiom can't implement a correct collector
yet. That needs the implementation to tell a pointer from an integer
(`MM-ALLOC-20`), and today it only partly can: a word carries no tag
(`MM-VAL-2`), and a type variable hides pointerhood from static
classification. A collector under those conditions has to be
conservative, and the last conservative collector here was deleted
along with the backend that emitted it. Stating `MM-ALLOC-20` as a
*prerequisite* is worth more than shipping code that misidentifies a
`Vec` header, as the removed `ArenaCompact` copy once did.

### 10.2 Why reference counting was chosen and then not finished

We chose reference counting (`MM-LIFE-2a`) and then withdrew it. This
section keeps the record of that decision. Three of the four reasons
below are still true, and the strategy still lost.

What beat it was a workload. A stateless request handler bracketed by
an arena mark and reset uses 100–313× less memory than the same binary
unscoped, gated with a negative probe (`MM-ALLOC-22`). Reason 2 is the
one that dissolved. The loop that never returns was ARC's decisive
case, and a request handler isn't that loop: it is an activation that
*does* return, at a boundary the program already knows. A watermark
serves that shape for free. The counting machinery that landed stays,
and §9.0 records what it costs per reset.

Cycles are constructible (`MM-LIFE-3`), so counting is incomplete for
Axiom. It isn't unsound: a counting scheme never frees a live object.
What it fails to do is free a dead knot. `MM-LIFE-2a` chose it anyway
and priced the leak in, for four reasons, each backed by a measurement
elsewhere in this document:

1. **Every alternative needs `MM-ALLOC-20` just as much.** Pointer
   discrimination is the shared prerequisite of counting, tracing and
   escape analysis alike. Paying for it buys progress toward all three
   and rules out none.
2. **The loop case reclaims with no copy.** The activation that never
   returns is every pass, request and expansion this compiler runs.
   Per-activation arenas can't help that shape, and `MM-ALLOC-19`'s
   tail-call reset could serve it only through a copy, a linearity
   proof or region inference. Under counts, the dead generation is
   released at the same boundary for free (`MM-LIFE-2c`, event 4). The
   shared substructure that made the copy corrupt (`MM-ALLOC-15`) is
   just arithmetic.
3. **Reclamation is deterministic.** A block is reclaimed when its last
   reference dies. That is the property `consume` was reaching for,
   obtained without finishing linear types (`MM-LIFE-7`).
4. **The deferral builds its own escape hatch.** The reference maps ARC
   requires (`MM-LIFE-2d`) are exactly the tracing information whose
   absence made the last collector conservative and wrong. If the
   cycle leak ever costs more than it saves, the collector that fixes
   it arrives with its hard part already built.

The other way out, making cycles unconstructible by removing
`MM-MUT-2`, is still possible. It just isn't the cheapest.

### 10.3 Why the inferred-arena model lost

Its own argument was the measured workload: a loop whose activation
never returns, served by a watermark at no per-object cost. But
`MM-ALLOC-17` can't touch that shape, because nothing returns. The
design's whole weight fell on `MM-ALLOC-19`'s tail-call reset, and its
soundness obligation could be met only by one of:

- a copy, priced at the live set per iteration;
- a linearity proof, which needs `MM-LIFE-7` finished;
- region inference.

The copy was built, gated, and measured corrupting the moment shared
substructure entered (`MM-ALLOC-15`). Counting makes the same sharing
arithmetic, and needs no region inference. The escape walk that
`MM-LIFE-2c`'s events 2 and 3 do need asks only whether one release may
fire, not which arena a value belongs in. Counting also turns
`MM-ALLOC-21`'s write barrier into an ordinary field-store event
(`MM-LIFE-2c`).

The inferred `region` annotation stays deleted either way. An
annotation the compiler can derive will eventually disagree with the
compiler, silently. The `region` keyword is back as `MM-RGN-1`'s
checked scope, which the program brackets itself: the opposite of an
annotation the compiler derives.

### 10.4 Why explicit primitives are the strategy

`MM-ALLOC-12`–`MM-ALLOC-16` are what a programmer uses. `MM-ALLOC-22`
is the rule and `scripts/check-net.sh` is the measurement: a request
handler scoped as an arena uses 100–313× less memory than the same
binary unscoped, with the LSP's 840 bytes per edit beside it. Their
gates are also what proved the allocator could be trusted at all. The
automation was meant to be built over them. The ARC design that was
chosen ended up refusing them instead (`MM-LIFE-2e`'s retired clause),
which shows how far that plan drifted from the one thing already known
to work.

### 10.5 Why the unsafe layer is named

`Mem` hands out addresses as plain `Int`s, and says so in its own
header. It is the layer where the type system stops and the machine
begins. A language that claims to have no such layer just moves it
somewhere unlabelled.

### 10.6 Why processes rather than threads

The platform forbids threads in a freestanding binary. The constraint
helped: it made `MM-PAR-3` true by construction, and made the
concurrency library a library.

### 10.7 Why a handle is a sealed word with its liveness in a table

A channel, a mutex and a cancellation token each name a shared mapping
that a free unmaps, and a spawn handle names the page its join reads
and then unmaps. Typed as an `Int`, any word would pass as one, and a
freed one would point at an unmapped page. We weighed three designs.

- **A word type the checker seals, which we chose.** It is one
  uncounted word, distinct to the checker, built and opened only by
  its module (`MM-VAL-10a`). It is a struct with markers instead of a
  new declaration form, so construction, field access, `pub`,
  `symbols`, the formatter and the LSP needed teaching only where the
  markers go. The word takes no share, so it has no shape-word bit and
  costs a polymorphic call no evidence word, and capturing it races no
  count.
- **A private struct marked shareable, counted atomically or made
  immortal.** A struct is a counted block. Generic code retains through
  the evidence word with the plain `axiom_retain`, so an atomic count
  would need every retain to test the block's header first. An immortal
  count, the static sentinel, avoids that. But the block would live in
  the creating binding's arena, where a region or a raw reset reclaims
  it along with any liveness flag it held, and every operation would
  load the object's address out of it.
- **A liveness flag in the object.** A free unmaps the object, so a
  check that read the object would be the fault it exists to prevent.

So a handle is a word, and its liveness lives in a table the runtime
owns: a slot with a generation, retired by one compare-and-swap. The
table is per address space, like the mappings it describes. A check is
four atomic loads, with no allocation and no lock. The markers appear
only in library modules the committed seed doesn't compile, so the
compiler builds from the seed unchanged.

One gap remains by choice. A free that races another binding's
operation on the same handle is a data race (`MM-PAR-9`): the table
catches every use ordered after the free, not one already in flight.
Catching that too would need a count of operations in flight, updated
on every call, and that is contended traffic on one cache line shared
by every binding that uses the handle.

---

## 11. Worked examples

### 11.1 A loop with flat memory, today

This is the contract of `MM-ALLOC-16`, written the way a program writes
it: mark once, then on each iteration copy up, reset and copy down. It
has the same shape as the "managed" variant that
`scripts/measure-memory-baseline.sh` gates.

Nothing will insert these calls for you, because `MM-LIFE-2a`'s ARC is
withdrawn. A server writes `MM-ALLOC-22`'s shape instead: mark, handle
the request, reset. Nothing is live at that boundary, so no copy is
needed.

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
;@axiom:effect(unsafe)
(fn (advance b n)
  (let ((m (__axiom_arena_mark)) (mut bb b) (mut nn n))
    {
      (while (> nn 0)
        (let ((b2 (step bb)))
          (let ((up (copyBoard b2)))
            {
              (__axiom_arena_reset m)          ; `up` is now above the waterline
              (set bb (copyBoard up))          ; and survives being read: MM-ALLOC-14
              (set nn (- nn 1))
            })))
      bb
    }))
```

Memory stays flat at about 1.4 MiB from 80 to 20,000 generations.
Without the bracket, the same loop grows by about 8 KiB per generation,
with no ceiling:

| generations | unmanaged peak RSS | managed |
|---|---|---|
| 10 | 1.4 MB | ~1.4 MB |
| 80 | 2.0 MB | ~1.4 MB |
| 500 | 5.4 MB | ~1.4 MB |
| 2000 | 17.5 MB | ~1.4 MB |
| 20000 | 162.6 MB | ~1.4 MB |

The table is in MB, not MiB. The script reports peak RSS in kibibytes,
and these figures are that number divided by 1000, as
`measure-memory-baseline.sh` prints it. The gate's own ceiling is stated
in KiB (4096), so it is unaffected.

One board, about 10 KiB, is live at every count. The unmanaged column
is the allocator never reclaiming: **peak memory tracks total
allocation, not reachable data**. That is why the memory model is the
hinge of the roadmap rather than one item on a list.

Some older figures are still quoted in places, and they are stale. The
pre-`B3` numbers were 10 → 5.2 MiB, 80 → 31.8 MiB and 2000 → 744 MiB.
The figure of about 16 KiB per generation is also stale. §9.1 records
that correction, with the measurements either side of the `Vec` port
that caused it.

Only one of these rows is enforced: the gate checks the managed
variant's ceiling at N = 2000. The unmanaged column is a recorded
measurement, not an acceptance criterion (`MM-LIFE-2e`, §9.1). No CI job
runs `scripts/measure-memory-baseline.sh` in its reporting mode, so
nothing regenerates that column.

The copy is sound here, but not in general. The down-copy is an
ordinary allocation, so `MM-ALLOC-6` scrubs it, and `MM-ALLOC-15` says
that scrub can run over the source before the copy reads it. That
doesn't happen here for one reason only: `vecWithCapacity` makes both
copies *exact*. The destination is the same size as the source, so it
can never reach past it.

Change the shape and the same code silently corrupts memory. Two
examples are a live set larger than the iteration's garbage, and a
server holding a document while it answers a short request.
`__axiom_arena_reset_keeping` exists to prevent this.

The gate also runs the ablated variant, which resets with no copy at
all, and requires it to fail. It checks that the population is *not* 5,
which proves the check detects the unsoundness the contract exists to
prevent.

### 11.2 Reading a value's representation off its type

Here is what `MM-VAL-8` means in practice, and why it is worth knowing:

```scheme
(data Color () (Red) (Green) (Blue))          ; rep 1: values are tags, 0 allocations
(data Shape () (Circle Int) (Square Int))     ; rep 0: every value is a 2-word block
(data Tree  () (Leaf) (Node Tree Int Tree))   ; rep 2: (Leaf) is immediate, (Node ...) is a 4-word block
```

A `(Leaf)` costs nothing and a `(Node l v r)` costs 32 bytes. A match
on `Tree` emits the `< 4096` test of `MM-VAL-9`. A match on `Color`
emits a plain compare, and a match on `Shape` loads word 0. The program
never writes any of this down: it all follows from the constructor
list.

### 11.3 The aliasing hazard, in the smallest program that shows it

```scheme
(struct Cfg (mut verbose : Int))

(:: configure (-> Cfg Cfg))
(fn (configure c) { (set c.verbose 1) c })    ; mutates the caller's value

(fn (main)
  (let ((base (Cfg 0))
        (loud (configure base)))
    (- loud.verbose base.verbose)))           ; 0, not 1
```

`configure` looks like it returns a modified copy. It returns its
argument, modified in place: `MM-MUT-2` and `MM-MUT-4` together. The
fix is to rebuild the value with `(Cfg 1)`. Nothing in the language will
point this out.

### 11.4 What a linear loop parameter would buy

Neither `linear` nor `consume` parses today. Both are `AX2004`
(`MM-LIFE-7`), so the two blocks below are refused at `check` and exit
1. They are kept because old source still carries them, and because
`MM-LIFE-7` records what they were accepted as.

Under the withdrawn arena model, this example carried weight: discharge
B of `MM-ALLOC-19` replaced §11.1's copy with a proof. Under ARC the
loop reclaims without it (`MM-LIFE-2c`, event 4). What `MM-LIFE-7`
would still buy here is smaller but real. The hand-off moves instead of
retaining, and `consume` releases the old board at the call rather than
at the boundary.

```scheme refused
(:: advance (-> (linear Board) Int (linear Board)))
(fn (advance board n)
  (if (== n 0)
      board
      (advance (step (consume board)) (- n 1))))   ; old board provably dead
```

`consume` is the drop point. The tail call resets the arena with no
copy, because nothing can still refer to what it reclaims.

Before the refusal, this shape compiled: `axiom check` reported `OK`,
and the program behaved exactly as if `linear` and `consume` were not
written. Its negation compiled too. A linear value used twice, consumed
twice or not used at all was accepted:

```scheme refused
(:: dup (-> (linear Int) Int))
(fn (dup x) (+ (cast Int (consume (consume x))) (cast Int x)))   ; once accepted
(:: drop (-> (linear Int) Int))
(fn (drop x) 0)                                                  ; once accepted
```

That was `MM-LIFE-7`'s point: the syntax existing was no evidence that
the discipline did. `linear` buys nothing today, because it does not
parse.

What survives is the type barrier from the constructor the keyword used
to build. Handing `x` to an `Int` parameter in
`(:: mk (-> (Linear Int) Int))` is still
`AX3004 expected Int, found Linear Int`. `Linear` has no declaration, no
arity check and no constructors.
