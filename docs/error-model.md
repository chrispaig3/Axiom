# The Axiom error model

How an Axiom program represents failure, passes it along, recovers from
it, and hears about it from the compiler.

## In brief

In Axiom, failure is a value. A function that can fail returns a
`Result` from `stdlib/Err.ax`, and its caller matches on it. There are
no exceptions and no unwinding.

This page is the contract behind that: the types, how errors travel,
what they cost in memory, how a program recovers from a trap, and what
the compiler reports. You don't need it to write everyday code. For
that, read [Standard library](reference.md#standard-library) in the
reference, and [Fallible main](reference.md#fallible-main) for a
`main` that returns a `Result`. Read on if you're writing a library,
porting code that returns sentinel values, or changing the compiler.

---

## 0. How to read this document

Like [memory-model.md](memory-model.md), this page backs every claim
about the implementation with the probe that shows it, and marks every
claim about the design as one.

### 0.1 Rule identifiers

Every normative statement has a stable identifier, such as `ERR-TYPE-2`
or `ERR-PROP-3`. Like diagnostic codes, identifiers are never renamed
and never reused. A withdrawn rule keeps its number and is marked
retired.

### 0.2 Conformance language

`MUST`, `MUST NOT`, `SHOULD` and `MAY` are used as in RFC 2119. Each
rule says which of two audiences it binds:

- **Implementation obligations** bind the compiler and the runtime it
  emits.
- **Program obligations** bind you, the programmer. Nothing checks
  them, so each one is written down. `ERR-PROP-3` is the one that costs
  a program its stack if you ignore it.

### 0.3 Status markers

| Marker | Meaning |
|---|---|
| **H** | **Holds today.** The rule names the probe that shows it. |
| **P** | **Planned.** Required of a conforming implementation, and this one doesn't conform yet. The rule says what happens today instead. |
| **R** | **Refused.** The language doesn't provide this, by design, and the rule says why. |
| **B** | **Blocked.** Specified, but a defect elsewhere prevents it. The rule names the defect. |

An **H** rule with no evidence is a bug in this document. A marker can
carry a note: *gated* means a test or check in CI holds the rule, and
*program obligation* is defined in §0.2.

### 0.4 Reproducing the measurements

Every probe here runs against the compiler in your working tree:

```bash
axiom="$PWD/.axiom-bin/axiom"
"$axiom" --diagnostic-format=ai check probe.ax
"$axiom" --diagnostic-format=ai build --input probe.ax --output probe.bin
./probe.bin; echo $?
```

A program's answer is its **exit status**, the low 8 bits of `main`'s
result. That's why several numbers below are reported modulo 256, and
why `ERR-PROP-3`'s probe checks that the program finishes rather than
what it returns.

**A `memAlloc` address delta measures allocation only below the
allocator's chunk size.** The same loop reads 32.0 bytes per iteration
at 10,000 and at 50,000 iterations, but 795.7 at 100,000. At about
3.2 MB the allocator moves into a chunk that isn't next to the last
one, and the subtraction counts the gap. Every delta below stays inside
one chunk. Where that isn't possible, the page reports a per-iteration
cost worked out from two points.

---

## 1. What exists today

### 1.1 `Option` is built in, `Result` is imported

`Some` and `None` are built-in constructors. They are registered before
any user constructor (`self_host/typecheck.ax`), need no declaration and
no import, and are written `(Option Int)` in a signature.

`Ok`, `Err` and `Result` are not built in. They are ordinary
declarations in `stdlib/Err.ax` (§2), and you reach them with
`(import Err)`. Without that import, `(Ok 1)` is `AX3001` in an
expression and `AX3003` in a pattern. That asymmetry is `ERR-TYPE-2`
holding, not a gap. It's the one difference to carry into §2: `Option`
needs no import, and `Result` does.

<a id="12-failure-was-a-sentinel-in-64-places-by-a-proxy-that-has-since-inverted"></a>
### 1.2 Sentinel values, and how the migration is sized

A *sentinel* signals failure with a value from the success type's own
range, such as `-1` or a negated `errno`. The standard library was
written that way, and most of it has since moved to `Result` and
`Option` (§10).

A sentinel is worse than inelegant. It is a value of the success type,
so nothing in the type system tells "the file is 4 bytes long" from
"the call failed with `errno` 4, negated". Every sentinel depends on
the caller remembering to check.

The migration's baseline came from a `grep` proxy:
`grep -cE "errno|sentinel|\(- 0 1\)"` across `stdlib/*.ax` and
`stdlib/Sys/*.ax`, excluding `Err.ax` itself. As the baseline, it
counted 64 sites over 12 files. This is the table `ERR-ADOPT-1` and §10
refer to:

| Module | Sites | Convention |
|---|---|---|
| `stdlib/Sys.ax` | 21 | `-errno`, Darwin's carry-flag protocol normalised into it |
| `stdlib/IO.ax` | 11 | `-errno`, forwarded from `Sys` |
| `stdlib/Utf8.ax` | 6 | `-1` |
| `stdlib/Map.ax` | 6 | `-1` / absent-key |
| `stdlib/Json.ax`, `stdlib/Path.ax`, `stdlib/Rpc.ax` | 3 each | `-1` |
| `stdlib/Str.ax`, `stdlib/Intern.ax`, `stdlib/Sys/Platform.darwin.ax` | 2 each | `-1` / `-errno` |
| `stdlib/Par.ax` | 1 | `-errno`, in the private `parRunWord` only: the one word a join can carry |
| `stdlib/Vec.ax` | 1 | `-1` |

The platform shim is counted because `Platform.darwin.ax` is where the
carry-flag protocol is normalised. It is the one place the convention is
implemented rather than forwarded.

**The proxy no longer sizes anything.** Recounted once the migration
was well under way, the same command read 120 hits over 17 files, while
the public declarations it stood for had fallen from 38 to 2. It has
kept rising since.

Of those 120 hits, 94 were comment lines, and the migration wrote them.
`stdlib/Sys.ax` alone had 52 in comments against 5 in code, each
comment explaining what an `errno` meant at a call that no longer
returns one. *The proxy rises when the migration succeeds.* The header
of `compat/SENTINELS` records the same flaw in that census's old
metric, which counted doc-comments and so rewarded silence. Both sized
a population by matching text instead of reading declarations.

None of the 26 code hits is a public declaration that answers a
sentinel:

| What the line does | Hits | Where |
|---|---|---|
| Seeds a loop accumulator, such as `(mut found (- 0 1))`; never an answer | 4 | `Str.strFind` (which already answers `(Option Int)`), `rdFindHeaderEnd`, `rdContentLength`, `rpcReadMsg` |
| A private helper below a wrapper that already answers `Option`, keeping `-1` on the recursion (§10's rule for `internFindFrom`) | 4 | `internFindFrom` (twice), `pathLastSlashFrom`, `pathLastDotFrom` |
| `Map.ax`'s private probe walk below `mapGet`, whose absent-key answer is a caller-supplied default and not a sentinel | 4 | `mapFindSlot`, `mapFindLoop` (twice), `mapInsertNoGrow` |
| Passes `-1` as an argument, or sets a local to it, in `stdlib/Sys.ax` | 3 | `netAddrText`'s zero-run seed, `netSignalOpenRaw`'s syscall slot, `sysRandomBytes`' `(set rc (- 0 1))` |
| A bitwise NOT written as XOR with all ones, `(^ x (- 0 1))` | 2 | `netSetBlocking`, `termFlagClear` |
| `EVFILT_READ`, a kernel constant that happens to be -1 | 2 | `pollReadFilter` on Darwin and FreeBSD |
| A private peek | 1 | `Json.ax`'s `jcPeek` |
| Renders an `errno` into a message | 1 | `IO.ax`'s `ioResult` |

The two public sentinels that remain, `keyStrEnd` and `keyInFill`
(§10.1), are invisible to the command for a third reason: they live in
`stdlib/Tui/`, outside its glob. Counted directly, they hold 6 and 7
hits. So the proxy over-counts prose in 17 files and misses the only
two rows still owed.

The proxy is kept here as a record, not as a metric. What sizes the
migration is `compat/SENTINELS`. It counts public *declarations* by what
their bodies answer: *failure*, a raw negative `errno` that `Result` is
for, and *absence*, a `-1` for "not found" that wants `Option`. Every
run of `scripts/check-compat.sh` recomputes it
(`tests/compat/verify-compat.py`'s `sentinel_census`), and the result
must match the committed file row for row. It reads **0 failure and 2
absence**. §10.1 names both, and what stops each from being ported.

### 1.3 Five traps

- **Division or remainder by zero** writes `axiom: division by zero` to
  fd 2 and exits with status **72**. Probe: `(fn (main) (/ 10 (- 1 1)))`
  exits 72. This confirms `MM-VAL-3a`.
- **An effect operation with no handler in its dynamic extent** traps
  and exits with status **71**. See [Effects](reference.md#effects) in
  the reference.
- **`MM-VAL-3b`**: `INT_MIN / -1` writes `axiom: division overflow`
  to fd 2 and exits with status **83**, and a left or right shift by
  an amount below 0 or above 63 writes `axiom: shift amount out of
  range` and exits **84**. Until 0.8.0 these cases were undefined:
  their answers changed with `--opt`, and nothing trapped.

`ERR-REC-2` gives division, remainder and the trapped cases a
value-returning alternative you can call instead. `ERR-REC-6` lets a
program that didn't call one contain the trap at an arena mark, instead
of dying of it. The runtime has other traps, such as running out of
memory (70) and an index out of range (77). `MM-EXEC-16` in the memory
model lists every reserved exit status.

---

## 2. The canonical types

**ERR-TYPE-1 (H). The failure type is `Result`, a two-parameter sum.**
It ships in `stdlib/Err.ax`:

```scheme
(pub data Result (a e)
  (Ok a)
  (Err e))
```

The constructors' types are `(a -> Result a e)` and `(e -> Result a e)`.
The success parameter comes first because that's the order you read the
computation in: `Result Int IoErr` is "an `Int`, or an `IoErr`".

**ERR-TYPE-2 (H). `Result` ships as an ordinary declaration in
`stdlib/`, not as a built-in.** A user-declared two-parameter ADT
already does everything a built-in would:

- It checks: `(data Res (a e) (Good a) (Bad e))` passes `check`. The
  type parameters are **one** group, `(a e)`. Written `(a) (e)`, the
  second group reads as a constructor named `e`. The declaration still
  checks, but a `match` over the type fails with a confusing
  non-exhaustive-match error (`AX3005`, "missing e").
- It is pure to inspect (`ERR-PROP-2`).
- It is classified as a reference and reclaimed at a release boundary,
  even when applied polymorphically (`ERR-MEM-3`).

A built-in would mean changing `self_host/typecheck.ax`, and so a seed
rebuild with `scripts/reseed.sh`, on a compiler whose bootstrap
fixpoint is a v1 exit criterion. Nothing measured justifies that cost
before the model has users. Making `Result` built in is deferred, not
refused. What would trigger it is a measured cost of writing the
`(import ...)`, not a preference.

**ERR-TYPE-3 (H). The canonical error payload is a concrete record, and
conversion between error types is explicit.**

```scheme
(pub struct Error
  (code : Int)          ; a stable AXERR number, never reused
  (message : String)    ; what happened, no trailing punctuation
  (context : String))   ; what the caller was doing, "" when none
```

In Rust, `From<E>` lets `?` convert an error on the way out. Axiom has
no such mechanism, by design. A conversion is an ordinary value the
caller supplies, and nothing searches for one:

```scheme
(import Err)
(import IO)

(struct ConvertOf (a b)
  (convert : (-> a b)))

(:: mapErrWith (-> (ConvertOf e f) (Result a e) (Result a f)))
(fn (mapErrWith c r)
  (match r
    ((Ok x) (Ok x))
    ((Err y) (Err ((c.convert) y)))))       ; dispatch is application

(:: errOfInt (-> Int Error))
(fn (errOfInt n) (mkError n "low-level failure"))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (mapErrWith (ConvertOf errOfInt) (Err 5))
    ((Ok x) x)
    ((Err e) { (println (errorText e)) (errCode e) })))
```

It prints this and exits with status 5, the error's code:

```text
low-level failure
```

What Axiom lacks is *instance search*: Rust's compiler finds the
`From` instance from the types at the call site. In Axiom, dispatch is
application, and an instance is a value someone wrote down. The checker
does resolve a format hole from its argument's static type, but that is
one built-in form rewriting to a known renderer, not a search over
declared instances. So a conversion is a function the program calls
(`mapErr`) or a record it passes, never an instance the compiler
supplies. The two-parameter trait this replaces is blocker `B2` in §8,
resolved by removal in 0.6.0.

**ERR-TYPE-3a (retired). An error-inspecting combinator MAY read the
error's fields off the `match` binder.** The rule once said MUST NOT.
That was a checker limitation, not a design choice, and the limitation
is gone:

```scheme
(import Err)
(import IO)

(:: reContext (-> (Result a Error) String (Result a Error)))
(fn (reContext r ctx)
  (match r
    ((Ok x) (Ok x))
    ((Err y) (Err (Error y.code y.message ctx)))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (reContext (divChecked 10 0) "splitting the bill")
    ((Ok n) n)
    ((Err e) { (println (errorText e)) (errCode e) })))
```

It prints this and exits with status 1, the code `divChecked` gives a
division by zero:

```text
divided by zero while splitting the bill
```

The checker instantiated `(Result a Error)`'s constructor field to a
fresh variable and never resolved it against the signature, so `y` had
no fields: `AX3004 type mismatch: expected struct or data type, found
_a`. `ctorPatEnv` removed the limitation. A constructor pattern's field
types are now instantiated against the scrutinee's before its binders
are bound. §8 (`B5`) records how the rule outlived the limitation.

The number stays burned and is never reused. `stdlib/Err.ax` keeps
`errContextOf`, because it is public, `docs/stdlib-api.md` lists it,
and removing an exported name would break importers for no gain. It is
now a convenience, not a requirement. `tests/stdlib/371-err-module.ax`
term 2 checks the two spellings against each other: changing the field
the direct read uses drops that term and no other (exit 253 against
255).

**ERR-TYPE-4 (H). `Option` is not an error type, and the conversion is
named.** `Option` says *absent*; `Result` says *failed, and here is
why*. `(okOr o e)` and `(toOption r)` convert explicitly, and there is
no implicit coercion in either direction. A missing map key and a
failed syscall are different facts, and the type keeps them apart.

**ERR-TYPE-5 (H). Error payload fields MUST declare their real types.**
Not `Int`. A `String` stored through a field declared `Int` is
invisible to reclamation and leaks, so this is a memory-safety
obligation as much as a type-design one (`ERR-MEM-1`).

---

## 3. Propagation

**ERR-PROP-1 (H). An error is an ordinary value.** It travels through
calls, lambdas, closures, data structures and pattern matching with no
special mechanism, because Axiom has none to offer: no unwinding, no
early return and no exceptions. A function that can fail says so in its
return type, and every caller does something about it or doesn't
compile.

**ERR-PROP-2 (H, amended). Inspecting an error is pure. Constructing
one is not.** A function that only takes a value apart may carry
`;@axiom:effect(pure)`. A function that builds one allocates, and `pure`
refuses it:

```scheme refused
(data Pair (P Int Int) (Nil))

;@axiom:effect(pure)
(:: mkPair (-> Int Pair))
(fn (mkPair n) (P n n))

;@axiom:effect(pure)
(:: first (-> Pair Int))
(fn (first p) (match p ((P a b) a) ((Nil) 0)))

(:: main Int)
(fn (main) (first (mkPair 3)))
```

```text
error[AX3010]: AXTAG mismatch on `mkPair`: `effect(pure)` claim contradicted: body performs Alloc
```

`first` is accepted, and `axiom symbols` reports it as `#effect=pure` with no
`#effects=` beside it. So you can take a `Result` apart inside a
function that claims purity, but you can't build one there.

Counting constructor allocation is what lets `restrict(no-alloc)`
catch a constructor. With constructors left out of the inferred effect
set, as this rule once allowed, a function that built a value checked `OK` while its
IR called `axiom_alloc`. With them counted, the same function is
refused with `AX3049`:

```scheme refused
(data W (Wrap Int) (Empty))

;@axiom:restrict(no-alloc)
(:: mk (-> Int Int))
(fn (mk n) (match (Wrap n) ((Wrap x) x) ((Empty) 0)))

(:: main Int)
(fn (main) (mk 3))
```

`MM-EXEC-9a` in the memory model records the change and the effect
rows it moved.

**`Alloc` is not exempted from `pure`, by decision.** `pure` means an
empty definite effect row. An exemption would have to be carved out for
every reader of that row, not just for this rule, and `Alloc` is the
effect `restrict(no-alloc)` exists to name. So construction allocates,
and a constructing function is not pure. No `;@axiom:effect(pure)` claim in
`stdlib/` or `self_host/` sits on a constructing function.

**ERR-PROP-3 (H, program obligation). In a recursive function, the
fallible call MUST be the `match` scrutinee and the recursive call MUST
be what an arm answers. Never the reverse.**

The rest of the model depends on this rule, and it isn't a matter of
style. Here is the safe shape. The self call is in tail position inside
an arm, so the compiler turns the function into a loop:

```scheme
(fn (total n acc)
  (if (== n 0)
      (Ok acc)
      (match (step n)
        ((Err e) (Err e))
        ((Ok v) (total (- n 1) (+ acc v))))))
```

And the unsafe one. The `match` waits on the self call, so it isn't a
tail call, the loop conversion doesn't fire, and every level holds a
stack frame:

```scheme
(fn (total n acc)
  (if (== n 0)
      (Ok acc)
      (match (total (- n 1) (+ acc 1))
        ((Err e) (Err e))
        ((Ok x) (Ok x)))))
```

At the default `--opt 1` with an 8 MiB stack, the unsafe shape costs
**48 bytes of stack per call** and dies of `SIGSEGV` after about
**174,000** calls. The safe shape completes **5,000,000** iterations
with a flat stack.

The shape a propagation form generates, with the continuation in the
arm, is the shape that converts: `try` (`ERR-SUGAR-2`) expands to
exactly this. So the convenient spelling and the safe one agree.

Gated by `tests/stdlib/370-error-propagation.ax` term 16, with the
scrutinee shape run as its ablation.

**ERR-PROP-4 (H, gated). The compiler warns on a self-recursive call
in the scrutinee of a `match`.** The warning is `AX3045`,
`recursion-in-scrutinee`, and its help names the arm-tail rewrite.

It fires on any call to the enclosing function, at any depth of any
`match` scrutinee in its body, whatever the scrutinee's own type. A
call nested inside a larger scrutinee holds its frame just the same. A
condition on the scrutinee's return type, as first proposed, would
have missed the same hazard one expression up.

It doesn't report:

- a call to any other function, including mutual recursion through a
  scrutinee, which is the same hazard one call away, because the
  checker sees one declaration at a time;
- a name that the match's own scope binds;
- a scrutinee that didn't check cleanly.

Shallow recursion is correct, so this is a warning. It costs a line of
output and no build, where an error would refuse working programs.

Gated by `tests/diagnostics/1005-recursion-in-scrutinee.ax`, which
expects two warnings, for the bare call and for one nested deeper. The
arm-tail shape, a call to another function, shadowing spellings and a
poisoned scrutinee all stay silent. `tests/diagnostics/severity.policy`
and `scripts/check-diagnostic-coverage.sh` also hold it.

**ERR-PROP-5 (H). Higher-order propagation carries the callee's
effects, not the error.** A combinator that takes a fallible function,
such as `andThen`, is effect-transparent in that parameter, and
`axiom symbols` reports it with `#effect-params=`. Its own row holds
only what its body does, which is `Alloc` when it builds a `Result`
(`ERR-PROP-2`). No rule of this model changes effect inference.

---

## 4. Memory

The rules in this section are obligations on the design. They say what
gets reclaimed, and what your program must do so a loop that carries
errors runs in constant memory.

**ERR-MEM-1 (H). A payload field's declared type decides whether its
contents are reclaimed.** `fldClass` in `self_host/codegen.ax` builds a
block's reference map from its declared field types:

- *reference*: `String`, a declared `data` or `struct` type, a tuple
  and an arrow;
- *scalar*: the `Int`/`Float`/`Bool`/`Char` family;
- *unclassifiable*: a type variable, a `Ptr` or an alias. One
  unclassifiable field forces the whole block to an empty map.

A `String` stored through a field declared `Int` is invisible to
release, so it leaks. That is why `ERR-TYPE-5` exists: an error record
that declares `(message : Int)` and casts a `String` into it leaks.

**ERR-MEM-2 (H, program obligation). An error value handed to a self
tail call MUST pass through a `let` binding.**

```scheme
; from tests/stdlib/370-error-propagation.ax: bind the error, then pass it
(fn (carry r n)
  (if (<= n 0)
    0
    (let ((next (Bad (wide n))))
      (carry next (- n 1)))))
```

A `data` block is born owned, at count 1. Built inline in a tail-call
argument, the boundary retain (`MM-LIFE-2c` event 4) takes it to 2,
and the single boundary release brings it back to 1. It never reaches
0, so it is never reclaimed. Bound to a `let` first, the frame's scope
release spends the birth count and the loop stays flat.

This measurement set the rule: 2000 iterations, each allocating a fresh
32-byte `String` inside the error value.

| The value is… | bump moves |
|---|---|
| constructed inline in the tail-call argument | 288,176 bytes |
| returned from a function, passed inline | 288,176 bytes |
| **bound to a `let`, then passed** | **176 bytes** |

That is 144 bytes leaked per iteration, in the two spellings people
write first. `tests/stdlib/370-error-propagation.ax` term 4 holds the
`let`-bound spelling flat.

The current compiler no longer leaks on the inline spellings: they
stay flat over the same 2000 iterations too. So removing the `let` is
no longer an ablation of term 4, and term 64's retained allocation is
what shows the instrument can see growth. Nothing in
`tests/stdlib/370-error-propagation.ax` holds the inline spellings
flat, so the rule stands. A conforming implementation
**SHOULD** make it unnecessary by spending the birth count at the
boundary.

**ERR-MEM-3 (H). A polymorphic `Result` applied at concrete arguments
is classified and reclaimed.** `fldClass` classifies an applied type by
its head, so this needed its own probe beside `ERR-MEM-2`'s monomorphic
one. The same loop over 2000 `let`-bound iterations moves the bump 176
bytes monomorphic and 288 bytes polymorphic, at `(Result Int String)`.
Both are flat, so the model works polymorphically, which is the only
way it is worth having. `370-error-propagation.ax` term 4 runs over a
polymorphic error type.

**ERR-MEM-4 (H). The block a fallible call returns is reclaimed.** A
call answering a `Result` allocates one block. It is released after the
`match`, whether you match the call directly or bind it first:

```scheme
(match (step i) ((Ok v) v) ((Err e) 0))

(let ((r (step i)))
  (match r ((Ok v) v) ((Err e) 0)))
```

A `match` scrutinee is released after the merge only when no arm's
binder escapes through that arm's body (`scrutineeReleasable` and
`escapesViaBinders` in `self_host/codegen.ax`). A binder that reaches
its arm's value, bare or through arithmetic, counts as an escape unless
it is a machine scalar. A scalar can't alias the block it was copied
out of. A field read can be classified where it stands
(`fieldReadIsScalar`), but a match binder is a bare variable by the
time the escape walk reaches it. So the checker records the binder's
type.

The declared type isn't enough. `Ok`'s field is declared `a`, and only
the match site knows that `(step i)` at `(-> Int (Result Int String))`
makes it an `Int`. So the checker records the *instantiated* type. In
`bindOnePatArg`, where a constructor pattern's binders are bound at
their instantiated field types, `stampPatBinderTy` writes the type
constructor's name onto the binder's own node. Codegen's
`binderIsScalar` classifies that name with `scalarTyName`, the same
list `fldClass` uses for a declared field. A binder the checker could
not resolve is left unstamped, which reads as "assume it can alias".

Three details of the stamp:

- It lives in a twelfth word on `ASTNode`, not in word 6. Word 6
  already carries an evidence stamp for a call's spine head, which is
  also a `TAG_E_VAR` node, and a type name there would be read as a
  node.
- It is a name, not a type node. The unifier writes through type nodes
  in place, so a pointer kept across phases can be overwritten.
  `stampFieldStruct` records a name for the same reason.
- The escape walk has its own binder collection, `patBindersEsc`,
  instead of a flag on the shared one. The five other callers of
  `patBindersCg` want the binders as a scope, for shadowing and for
  the flow environment, and a scalar binder is still a binding. Only
  the escape question treats it differently.

The stamp has three states: `0` for never stamped, a name when every
check that reached the node agreed, and the empty string when two
checks disagreed. The empty string reads back as conservative.
Last-write-wins would be unsafe: a binder node checked at two types
could hand codegen an `Int` for a binder that is really a `String`, and
codegen would then release a block the binder still points into.

Trait default bodies once reached that state. `checkImplComplete`
shared one default body's nodes across every impl that omitted the
method, so two impls at two types checked one AST, and the emitted IR
released a block a returned `String` still lived in. The same sharing
caused `MM-LIFE-2j` in [memory-model.md](memory-model.md). Traits were
removed in 0.6.0, and the path went with them. A compiler built with
last-write-wins stamps now emits byte-identical IR across 278 fixtures,
every `stdlib/` module and `self_host/main.ax`, so nothing Axiom can
express checks one pattern binder twice at two types. The disagreement
arm stays as a guard against that class of mistake, and
`scripts/check-fallible-reclaim.sh` asserts that nothing reaches it.

Without the stamp, every fallible call leaks its 32-byte block. A
compiler that runs once can survive a cost linear in fallible calls.
The LSP, which runs per keystroke, and the pre-forked server, which
runs per request, can't. `ERR-ADOPT-3`'s workaround for that cost is
no longer needed.

`tests/stdlib/370-error-propagation.ax` holds the rule with three
terms:

- term 32 asserts the reclamation over 20,000 calls, 10,000 in each
  spelling;
- term 8 runs the same loop with no `Result` in it, so a difference is
  attributed to the error value and not to the loop;
- term 64 requires a retained allocation to move the same probe pair,
  because flat lines alone can't tell reclamation from a blind
  instrument.

`scripts/check-fallible-reclaim.sh` rebuilds the compiler with
`binderIsScalar` ablated and requires the fixture to fail at term 32
and no other. Ablated, it exits 95 instead of 127, and the probe delta
returns to 640,032 bytes over 20,000 calls: this rule's 32 bytes a
call, to the byte.

**ERR-MEM-5 (H). An error record may declare at most 46 payload
words.** `AX3029` refuses a wider block: the reference map covers 47
payload words, and a data cell spends one on its tag. `AX3030` caps a
declaration at 64 type variables. `Error` as specified declares 3
fields, far below the limit. The rule exists so a future cause chain
doesn't walk into it.

**ERR-MEM-6 (R). The model does not use linear types, and neither does
the language.** `linear` and `consume` parsed but enforced nothing: no
use was counted, so a value could be used twice or not at all.
`Linear T` was a real nominal barrier (`AX3004` against `T`), enough to
keep a wrapper distinct in a signature but not enough to build
ownership on. Every rule above is correct without linearity, and a
marker that reads as an ownership guarantee but supplies none is worse
than no marker. So the keywords are refused instead of reserved: they report
`AX2004` with migration advice, alongside `union`, `foreign` and
`deriving`. `region` was once in that list and is now a checked scope
([Regions](reference.md#regions)).

`MM-LIFE-7`, if it lands, would add two things to this model and change
none of its rules: an error value could **move** into a callee without
retain/release, and a `Result` discarded on a branch could be dropped
early instead of at scope end. Both would optimise `ERR-MEM-2` and
`ERR-MEM-4`, not replace them.

---

## 5. Recovery

**ERR-REC-1 (R). There is no unwinding, no early return and no
exception, and the model does not add one.** Recovery is a value
arriving at a `match`. The runtime leaves no other option.
`ERR-REC-6` describes the one narrow exception, and why it is not the
general mechanism this rule refuses.

General unwinding is refused for three reasons, each measured:

- Every call would become a two-destination `invoke`, so the emitter
  would need to know the enclosing landing pad. An `invoke` in argument
  position splits a block underneath a `phi` that the emitter builds
  from "whichever block actually reaches the merge", because there is
  no block graph to ask.
- A cleanup pad must release pending values at an arbitrary point.
  That needs liveness, which needs a control-flow graph, and there
  isn't one.
- The unwinder is a hosted link: 188 undefined symbols for every
  program, not only the ones that use it.

**ERR-REC-2 (H). Every trap gets a value-returning alternative; the
raw operator keeps its semantics.** `stdlib/Err.ax` ships them:

```scheme
(import Err)
(import IO)

(:: report (-> (Result Int Error) Int))
;@axiom:effect(io)
(fn (report r)
  (match r
    ((Ok q) (println "quotient {q}"))
    ((Err e) (println (errorText e)))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (report (divChecked 10 2))
    (report (divChecked 10 0))
    0
  })
```

```text
quotient 5
divided by zero
```

| The trap | Alternative | Answers |
|---|---|---|
| `(/ a 0)`: fd 2, exit 72 | `(divChecked a b)` | `(Err DivideByZero)` |
| `(% a 0)`: the same | `(remChecked a b)` | `(Err DivideByZero)` |
| `INT_MIN / -1`: fd 2, exit 83 | `divChecked` | `(Err Overflow)` |
| `(<< 1 100)`, `(>> x 64)`: fd 2, exit 84 | `shlChecked`, `shrChecked` | `(Err ShiftTooWide)` |

A checked operator is a different function with a different type, so
no existing program changes meaning, and no hot loop pays for a check
it didn't ask for. The raw cases trap instead of answering (`MM-VAL-3b`):
name the sharp edge instead of silently rounding it off. Until 0.8.0
the last two rows were undefined and `--opt`-dependent; the guard is
what ended that, and the checked operators are unchanged by it.

All four are pinned by `tests/stdlib/371-err-module.ax`. Term 64 pins
`divChecked`'s zero case, term 32 its `INT_MIN / -1` guard together
with `shlChecked` refusing a shift of 100, and term 128 the codes
`remChecked` and `shrChecked` raise.

**ERR-REC-3 (R). Effects are not an error channel.** `handle` is
evidence-passing and **tail-resumptive**: the handler's return value is
the operation's result, and execution continues where the operation was
performed. A handler **cannot abort the computation it handles**,
because there is no mechanism for it to do so. An operation with no
handler traps and exits 71 instead of answering. So an `effect` can't
express "stop, unwind, recover", and a program that models failure as
an effect gets a trap where it wanted a `catch`. Use `effect` for
*capabilities* and `Result` for *failure*.

One capability does look like an error channel: asking the caller what
to do with a malformed record, then carrying on with the answer. That
is `ERR-REC-7`, shipped as `stdlib/Fallible.ax`. The handler decides
per record and cannot abort, and the loop it serves never learns that
anything happened.

**ERR-REC-4 (H, gated). `main` renders an error and exits with a code
reserved for the purpose.**

```scheme
(import Err)

(:: main (Result Int Error))
(fn (main)
  (withContext (Err (mkError 7 "disk full")) "saving records"))
```

This prints to fd 2 and exits with status 70:

```text
axiom: disk full while saving records
```

A `main` answering `(Result Int Error)` writes `axiom: {message}`, plus
the `context` when it is non-empty, to fd 2 and exits **70**. An `Ok`
payload is the exit status. 70 sits next to two statuses the runtime
already owns: 71 is the unhandled-operation trap and 72 the division
trap. Exit codes 1–69 stay your program's own. The
dispatch understands exactly `(Result Int Error)` with `errorText` in
scope, and any other `main` shape behaves as before. The reference
shows it in use under [Fallible main](reference.md#fallible-main).

Tested by `tests/stdlib/490-main-result-ok.ax` (an `Ok` payload answers
as the status) and `tests/stdlib/491-main-result-err.ax` (the sentence
on fd 2 via `NAME.err`, status 70 via `NAME.exit`). Like every stdlib
golden, `scripts/check-stdlib-selfhost.sh` runs them at `--opt` 0 and
2.

**ERR-REC-6 (H). A trap may be contained, and only a trap.**
`(__axiom_recover mark thunk)` arms a **recovery point** at an arena
mark and runs `thunk`. A trap listed in the table below, raised inside
it, answers the *arming call* with its status instead of writing to
fd 2 and exiting:

```scheme
(import IO)

(:: divide (-> Int Int Int))
(fn (divide a b)
  (/ a b))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((status
    (__axiom_recover
      __axiom_arena_mark
      (lambda (x) (divide 10 0)))))
    {
      (println "recovered {status}")
      (divide 10 0)
    }))
```

```text
recovered 72
```

The second division runs outside any recovery point, so it ends the
program: `axiom: division by zero` on fd 2, and exit status 72.

| Inside a recovery point | Outside one |
|---|---|
| out of memory answers **70** | `axiom: out of memory (mmap failed)`, exit 70 |
| a reference count at its maximum answers **70** | `axiom: reference count limit exceeded`, exit 70 (`MM-LIFE-2l`, `tests/stdlib/527-retain-overflow.ax`, both halves at `--opt` 0-3) |
| an unhandled effect answers **71** | `axiom: unhandled effect`, exit 71 |
| division by zero answers **72** | `axiom: division by zero`, exit 72 |
| division overflow answers **83** | `axiom: division overflow`, exit 83 (`tests/stdlib/695-intmin-div-trap.ax`, both halves at `--opt` 0-3) |
| a shift amount out of range answers **84** | `axiom: shift amount out of range`, exit 84 (`tests/stdlib/696-shift-wide-trap.ax`, both halves at `--opt` 0-3) |
| an index out of range answers **77** | `axiom: vector index out of range`, exit 77 (`tests/stdlib/525-vec-set-bounds.ax`) |
| a violated contract answers **80** | ``axiom: precondition failed in `half`: (> n 0)``, exit 80 |
| a `parallel` spawn the kernel refused answers **78** | `axiom: parallel: could not spawn the binding`, exit 78 (emitted, not yet executed) |
| `parallel` on a target with no lowering answers **79** | `axiom: parallel is not available on this target`, exit 79 (windows-x86_64, windows-aarch64; emitted, not executed) |
| a `__syscallN` on a target with no syscall ABI answers **74** | `axiom: no syscall ABI on this target`, exit 74 (windows-x86_64, windows-aarch64; emitted, not executed) |

Out of memory, an unhandled effect and division by zero each have both
halves in one program, at four optimisation levels:
`tests/stdlib/401-recover-effect.ax`, `402-recover-oom.ax` and
`403-recover-div.ax`, gated by `scripts/check-recover.sh`. Division
overflow and an out-of-range shift are the same shape:
`tests/stdlib/695-intmin-div-trap.ax` and
`tests/stdlib/696-shift-wide-trap.ax`, each with `.optstable`, under
the stdlib runner rather than `check-recover.sh`, which would only
re-assert what those runs already pin.

The contract row covers `;@axiom:pre(...)` and `post(...)`. A violated
contract is programmer error in the same sense as a division by zero:
the arena is intact, nothing half-wrote a structure, and a process that
armed a recovery point asked to survive exactly this. So
`@__axiom_contract_fail` calls `__axiom_recover_abort` first, as the
division trap does. Section 1 of `scripts/check-contracts.sh` holds both
halves in one program: the arming call answers `recovered 80` on
stdout, and a second violation outside every recovery point exits 80
with the sentence on fd 2. Both halves share one program for the reason
`403-recover-div.ax` gives: with `__axiom_recover` unreferenced, the
mechanism is dead code and the armed test folds to false.

Two traps are not in the table, 75 and 76, because each fires inside an
arena reset, and a recovery point's abort *is* an arena reset to the
arming mark:

- 75 (`MM-ALLOC-16a`) fires when a reset is handed a mark whose chunk
  is no longer on the active list. By then the reset's walk has pushed
  every chunk it passed onto the free list while hunting for the
  missing one. That is the list an abort would reset through, so
  answering with another reset asks the corrupted structure the same
  question.
- 76 (`MM-ALLOC-16b`) fires when a reset would reclaim the evidence
  record a live `handle` still dispatches through. An abort's whole job
  is restoring evidence slots, so running it to answer "a slot points
  into memory this reset is about to reclaim" repeats the fault. The
  abort restores every slot *before* it resets, so its own reset never
  trips this check.

The line is drawn on whose invariant broke, not on how bad it sounds.
The traps in the table are conditions a program can be written to
survive. A violated contract, for one, is the programmer's own sentence
about their own values. 75 and 76 are violated implementation invariants
(`I8`, and `MM-ALLOC-16b`'s evidence-record extent), which sit nearer
the memory-safety faults this rule refuses to contain.

A recovery point is not unwinding, a `catch` or an early return, so
`ERR-REC-1` stands for everything outside the table. There is no
landing pad and no cleanup, and nothing runs on the way out. The point
is wherever `__axiom_recover` was called: a program can't place it at a
frame of its choosing, and a recovered extent can't be resumed. It does
**not** contain a memory-safety fault either. A SIGSEGV is not a trap,
nothing asks the recovery point, and afterwards the heap invariants are
unknown. Java, Go and Rust all abort there too.

This narrow version is sound because there is nothing to unwind. Axiom
has no destructors, no finalizers and no stack-allocated data, so
"unwinding" reduces to restoring the stack pointer, the arena and the
effect slots.

Two things stay yours. The abort reclaims everything the thunk
allocated, so a structure older than the point must not be made to hold
any of it: return the thunk's answer through the arming call and store
it afterwards. And a descriptor, mapping or lock the thunk took stays
taken, because nothing runs on the way out. `MM-ALLOC-23` in the memory
model states both, and `tests/stdlib/561-failed-operations.ax` shows the
safe shape. `MM-ALLOC-23` in the memory model gives the memory
argument, including the one cost it doesn't avoid: a retain abandoned
below the mark. The measurement bounds it: 100,000 aborts hold max RSS
at 1,376 KiB, against 419,328 KiB for the same program with nothing to
recover from.

Failure divides into three classes, and a recovery point serves only
one of them:

- *Expected* failure, such as bad input, a missing file or a timeout,
  is `Result` (`ERR-TYPE-1`).
- A *memory-safety fault* can't be contained by any language, because
  afterwards the heap invariants are unknown.
- *Programmer error*, such as out of memory, an unhandled effect or a
  division by zero, sits between them. It is the only class an
  in-process abort can serve.

So a worker in a pre-forked pool that divides by zero on one request no
longer takes the process with it. The request boundary is already an
arena scope (`MM-ALLOC-22`), and the recovery point is the same
boundary answering a status. A recovery point doesn't replace `Result`:
`ERR-REC-5`'s obligation applies to a recovered status exactly as it
does to an `Err` arriving at a `match`.

`axiom test` is built on it ([Testing](reference.md#testing)). A test
runner needs exactly what this mechanism gives: one failure ends one
unit of work, and the process carries on. `axiom test` arms one
recovery point per test and reports the status it answers with.
`stdlib/Test.ax` makes a failed assertion an unhandled operation of an
`Assert` effect, so it answers 71 through the row above, with no new
machinery. `tests/testrunner/mixed-tests.ax` fails in three of these
ways and still reports the test declared after all three
(`scripts/check-test-runner.sh`).

A program that never arms a recovery point pays nothing. The
mechanism's only mutable state is a single global that only the arm
site writes. With no arm site anywhere, `opt` folds the load in the
abort to the initialiser, deletes the global, deletes the three calls
the traps make, and folds all three functions to `ret i64 0`.
`scripts/check-recover.sh` asserts those three properties separately at
`opt -O1` instead of counting lines, because P1's symbol table takes
the address of every function a module defines, and so keeps three
names alive in every program either way.

**ERR-REC-7 (H, gated). A batch loop's malformed record is a question
for the loop's handler, answered where it arises, and the answer costs
the record nothing.**

```scheme
(import IO)
(import Fallible)

; Deep in the batch: report a bad record and carry on with the answer.
(:: parseRecord (-> Int Int))
(fn (parseRecord i)
  (if (== (% i 7) 0)
    (fallibleMalformed "record malformed")
    i))

(:: total (-> Int Int))
(fn (total n)
  (let (
    (mut i 1)
    (mut acc 0)
  )
    {
      (while (<= i n)
        (let ((v (parseRecord i)))
          {
            (set acc (if (fallibleIsSkipped v)
              acc
              (+ acc v)))
            (set i (+ i 1))
          }))
      acc
    }))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (cast Int (handle (total 20) (Fallible) fallibleSkip)))
    (println (cast Int (handle (total 20) (Fallible) (fallibleDefault 100))))
    0
  })
```

```text
189
389
```

`stdlib/Fallible.ax` declares one effect with one operation,
`(fallibleMalformed message)`, which answers an `Int`. A callee at any
depth below the loop performs it on a record it can't parse, and
continues with whatever the innermost handler answers. Three handlers
ship, each a value you hand to `handle`:

- `fallibleSkip` answers `fallibleSkipped`, the most negative `Int`,
  which the loop checks once per record with `fallibleIsSkipped`;
- `(fallibleDefault d)` answers `d`;
- `(fallibleCounting tally next)` counts in `tally` and answers as
  `next` would.

Nesting shadows and restores as `handle` always does: an inner
`fallibleSkip` wins while its `handle` is live, and the outer
`(fallibleDefault 100)` answers again after it exits.
`tests/stdlib/410-fallible.ax` pins all of that line by line.

This rule leaves `ERR-REC-3` as it is: the handler cannot abort. An
operation performed with no handler is the unhandled-effect row of
`ERR-REC-6`: 71 to a recovery point, and `axiom: unhandled effect` with
exit 71 outside one. A `main` that reaches `fallibleMalformed` with no
handler draws the `AX3053` warning at compile time
(`tests/diagnostics/389-unhandled-at-main.ax`).

*The cost is the rule.* A batch loop has no request boundary, so there
is no arena reset (`MM-ALLOC-22`), and a byte per record is a byte the
process keeps for the whole run. The operation's shape was chosen by
measuring the alternatives with the arena mark cell, the instrument
`370-error-propagation.ax` uses, over 10,000 records of which 1,428
performed the operation:

| operation shape | bytes per operation, when the shape was chosen | now |
|---|---|---|
| one argument, a literal message | 0 | 0 |
| one argument, an `Int` | 0 | 0 |
| two arguments, `(op message fallback)` | 32: the curried handler's inner closure, which the dispatch did not release | 0 |
| one argument, a message built per record | 80: the string, because an application through a closure did not release its owned argument | 0 |

So the operation takes one argument, and the fallback comes from the
handler: `(fallibleDefault d)` allocates its closure once, at the
`handle`. A program **MUST** pass a literal, or a value it already
holds, never a message built for the record: the loop knows which
record it is on. `410`'s memory terms hold the three handlers at 0
bytes per record, and require a handler that keeps a string per record
to move the same instrument.

`scripts/check-steady-state.sh`'s `batch` probe checks resident memory:
2,000,000 records under `fallibleSkip` hold **1,376 KiB**, the same as
200,000, and its `keeping` twin must grow past 5×. The same gate builds
`examples/batch-fallible/batch-fallible.ax`, the same loop reading
every record as text, and holds it to the same band at 100,000 and
1,000,000 records.

*Why a sentinel and not `Option`.* `(Some v)` on every well-formed
record is a block per record, allocated and released a million times,
where a sentinel is one comparison. A `handle` expression's own type is
also the checker's wildcard, so an `Option` would arrive through a
`cast` at every site. If your records can hold the most negative `Int`,
write a one-line handler that answers your own sentinel.

*What this does not change.* `ERR-REC-3` stands: the handler answers,
it does not unwind. The two costs in the table were facts about closure
application, not defects in this module. A compiler that releases the
closure and the string makes both spellings free, and this rule's
obligation then shrinks to a preference. The current compiler does both:
`tests/stdlib/410-fallible.ax` term `e` holds the built message flat,
and `scripts/check-closure-reclaim.sh` ablates the closure release and
requires the cost back.

**ERR-REC-5 (P, program obligation). A recovered error MUST NOT be
discarded silently.** `(match r ((Ok x) x) ((Err _) 0))` compiles, and
it is sometimes right. It is also how a migration away from sentinel
values brings back the problem it set out to fix. The compiler can't
tell the two apart, so the obligation falls on the program and its
review. `ERR-DIAG-2` proposes the lint that would make it visible.

---

## 6. Diagnostics

**ERR-DIAG-1 (H). Every diagnostic this model adds goes through
`mkDiag`/`mkDiagFix` at the site that detects the condition, carries a
stable code and a kebab-case slug, and has long-form text in
`self_host/explain.ax`.** Error handling doesn't change how the
compiler reports. This rule keeps it that way, so no one adds a second
channel for "error-model errors".

**ERR-DIAG-2 (P). Proposed codes.** This section reserves numbers for
diagnostics this model needs and the compiler doesn't build yet. The
rest of the compiler keeps growing, so it can spend a reserved number
first. Three rules keep the numbering straight:

- A proposal renumbers when the compiler spends its number first.
- A new code takes the next number above the highest one in use, the
  *free end*, and never a number from the reserved block.
- A retired number **MUST NOT** be reused. `AX3008` and `AX3032` are
  retired.

No codes are proposed right now. When one is, it goes in this table:

| Proposed | Slug | Condition |
|---|---|---|

Before a proposed code is built, it needs:

- a construction site;
- `explain.ax` text;
- a `tests/diagnostics/` case with `.axdl`, `.human` and `.json`
  goldens, blessed by `AXIOM_BLESS=1 scripts/check-diagnostics.sh NNN`;
- a run of that case against a compiler built before the change, to
  show the case isn't vacuous.

`scripts/check-doc-drift.sh` fails when a row in the table above
proposes a number the compiler already constructs. It also requires the
codes the compiler constructs and the codes `explain.ax` explains to be
the same set, so explaining a code before it is built turns the gate
red.

This section records the codes below. All of them are built, and
`axiom explain` gives the long form of each.

| Code | What it reports | Notes |
|---|---|---|
| `AX3035` `macro-binder-target` | a macro argument in a binder position that is not a name | The expander defect this model ran into (§7, `B1`). |
| `AX3036` `extern-type` | an `extern` item whose type can't cross the boundary | |
| `AX3037` `axtag-unverifiable` | an `effect(pure)` claim over a call the effect walk can't resolve | A warning. |
| `AX3038` `effect-unverifiable` | the same condition under a `handle` | A warning. |
| `AX3039` `axtag-key-typo` | an AXTAG key one edit away from a key the compiler checks | A warning. |
| `AX3040` `result-only-tyvar` | a type variable the caller chooses and the callee produces | The slug names the shape it was built for and stays as the machine key. The rule also covers a function-typed parameter's own variable. |
| `AX3041` `extern-library-name` | an `extern` block's library name that isn't one | Reported by the parser. |
| `AX3042` `undeclared-effect` | a function that performs a required effect (`IO`, `Entropy`, `Spawn` or `Block`) and doesn't declare it | |
| `AX3043` `error-payload-untyped` | a reference smuggled through a field declared `Int` | A warning. `tests/diagnostics/1008-error-payload-untyped.ax` |
| `AX3044` `ambiguous-type` | a bare type name declared in more than one imported module | Reported by the namespace pass. |
| `AX3045` `recursion-in-scrutinee` | a self-recursive call in the scrutinee of a `match` | A warning. `ERR-PROP-4` |
| `AX3046` `discarded-result` | a `Result`-typed expression in statement position, its value unused | A warning. |
| `AX3047` `sized-integer-type` | a C or Rust primitive spelling in type position | Without it, the name is read as a type variable and silently accepted. |
| `AX3048` `deprecated-name` | a reference to a name its declaration marks `;@axiom:deprecated` | A warning by design. |
| `AX3049` `restriction-violated` | a `restrict(...)` claim the declaration breaks | An error. |
| `AX3050` `contract-malformed` | a `;@axiom:pre(...)` or `post(...)` that can't be compiled into a check | An error. See below. |
| `AX3051` `restriction-unverifiable` | a `restrict(...)` claim the effect walk can't check | A warning. |
| `AX3052` `restriction-unknown` | a name inside `restrict(...)` that isn't a restriction | An error. |
| `AX3053` `unhandled-operation` | a custom effect still in `main`'s effect row when inference finishes | A warning by design. See below. |
| `AX3054` `effect-name-reserved` | an `effect` declared with a built-in effect's name | An error with no warning stage. See below. |
| `AX3055` `effect-op-untyped` | an effect operation that declares no type | An error, because the handler check and the call's arity check both depend on that arrow. |
| `AX3056` `struct-field-untyped` | a struct field whose type the parser couldn't read | An error. See below. |
| `AX3067` `struct-arity-mismatch` | a `struct` built with the wrong number of fields | Split from `AX3008`. |
| `AX3068` `nullary-lambda` | a parameterless `lambda` applied | Split from `AX3008`. |
| `AX3069` `sizeof-arity` | a surplus argument to `sizeof` or `alignof` | Split from `AX3008`. |
| `AX3070` `unsafe-field-access` | a field read on a `data` type with a nullary constructor beside a fielded one | Split from `AX3008`. |
| `AX3071` `unretained-store` | a bare `__store64` of a reference-typed value through `cast` | `tests/diagnostics/1002-unretained-store.ax` |
| `AX3072` `addr-nonliteral` | `__addr` of anything but a string literal | `tests/diagnostics/1003-addr-nonliteral.ax` |
| `AX3073` `undeclared-unsafe` | a declaration performs a raw primitive, calls a precondition interface or forges a reference without `;@axiom:effect(unsafe)` | An error. `tests/diagnostics/1004-undeclared-unsafe.ax`, `tests/diagnostics/1040-forging-cast.ax`, `tests/diagnostics/1041-precondition-call.ax` |
| `AX3079` `precondition-without-unsafe` | `;@axiom:precondition(...)` appears without `effect(unsafe)` | An error. `tests/diagnostics/1043-precondition-tag.ax` |
| `AX3080` `precondition-empty` | a precondition states nothing | An error. `tests/diagnostics/1043-precondition-tag.ax` |
| `AX3089` `signature-needed` | a function with no signature, called from inside its own body or from a declaration above it, before its type is known | An error. `tests/diagnostics/1032-signature-needed.ax` |
| `AX3090` `recover-thunk-unseen` | a recovery point's thunk that isn't a lambda written at the call or a top-level function, so the region check can't walk it | An error. `tests/diagnostics/1033-recover-escape.ax` |
| `AX3091` `inline-asm` | an `asm` form the compiler can't lower: an unknown architecture or operand kind, a second arm for one architecture, a template naming no operand, a second output, or a register an arm can't name | An error, where the form is written. `tests/diagnostics/1044-inline-asm.ax` |

Every warning in the table is listed, with its reason, in
`tests/diagnostics/severity.policy`. The `restrict(...)` codes are
described under [AXTAG metadata](reference.md#axtag-metadata) in the
reference.

`AX3050` gets a closer look, because a contract is the first claim in
the AXTAG namespace this compiler can't decide. `restrict(...)` is
checked by analysis the checker already performs. `(> n 0)` is a
statement about a value, and the compiler has no value analysis:
`grep -v '^ *;' FILE | grep -c 'constFold\|constantFold\|interval\|rangeOf\|abstractVal'`
answers 0, 0 and 0 over `self_host/typecheck.ax`, `self_host/codegen.ax`
and `self_host/expand.ax`. Comment lines are excluded because a comment
stating this claim matches the pattern.

So the claim is enforced at run time. `expLowerContracts` compiles the
check into the body, and a failure writes
``axiom: precondition failed in `half`: (> n 0)`` on fd 2 and exits 80.
`AX3050` covers everything about the contract that *is* static, as four
questions under one code:

1. The value must parse, as exactly one expression.
2. It must type as `Bool`, with the parameters in scope and against
   this declaration's own signature.
3. `result` must name something: the declared result of a `post`, and
   nothing anywhere else. A `pre` runs before the body, and a
   declaration with no `::` declares no result type for it to have.
4. It must perform nothing. A contract is evaluated on every call, so
   one that allocates or writes changes the program just by being
   stated.

They share one code because they share a remedy: correct the
expression, or delete the tag to withdraw the claim. `AX3010` and
`AX3049` group their arms for the same reason. Question 4 isn't a
blanket refusal. `vecLen`, `vecGet`, `strLen`, `strEq`, `strByte` and
`memGetWord` carry an empty effect row, while `concat`, `fmtInt` and
`vecNew` carry `Alloc,Mut`. A contract may compare, index, measure and
test, but it may not build. The design note is
[contracts-design.md](contracts-design.md), and
`scripts/check-contracts.sh` is the gate.

`AX3053` means nothing handled a custom effect: a `handle` is the only
construct that discharges one. An operation of that effect would write
`axiom: unhandled effect` on fd 2 and exit 71. It is a warning by
design, like `AX3048`, and `severity.policy` gives the reason. On the
two closure shapes the evidence is one-sided in both directions, so an
error would refuse a program that runs and accept one that traps.

`AX3054` has no warning stage, because no correct program is on the
other side of it. A handle list resolves a built-in effect's name to
the built-in, so an `effect` declared with that name can never be
handled. The row it produces would also say the program reaches the
outside world when it doesn't. `Err` is no longer a built-in effect
name, because nothing inferred it and its own AXTAG spelling couldn't
reach it. A handle list naming `Err` draws `AX3016`, like any other
undeclared name.

`AX3056` is an error for the same kind of reason as `AX3055`, one form
over. `fldClass` can't classify the empty type variable the parser
answers for a missing `:`, so the field leaves the block's reference
map and `MM-LIFE-2c` event 5. Without the error, a value stored into
it would be freed under the program, which then exits 139.

`AX3008` (`semantic-error`) was a catch-all for four shapes with
unrelated remedies, so `grep AX3008` conflated a miscount, a non-call,
a discarded argument and an unsafe load. It is split into
`AX3067`–`AX3070`, and `AX3008` itself is retired. Each new code keeps
its old message word for word, and only the code and slug changed. The
four corpus fixtures `270`, `390`, `395` and `480` are their primaries.

`AX3071` exists because `cast` takes no share: the owner's release
frees a block the stored word still names. `AX3072` exists because
anything but a string literal has no interned bytes behind it.

`AX3073` covers every primitive in `MM-EXEC-9c`, a call to a
precondition interface and a cast that forges a reference. The
operation's declaration must say `effect(unsafe)`. A declaration with
that tag alone is a trusted wrapper: its caller inherits no unsafe
obligation. Add `precondition(...)` when callers must meet a condition
the wrapper cannot establish itself. Every call to that interface is
then an unsafe operation in the caller. `AX3079` refuses a precondition
without `effect(unsafe)`, and `AX3080` refuses an empty one.

`AX3076` was spent on 2026-09-27 by `effect-tag-list`: an
`;@axiom:effect(...)` tag naming more than one effect -
`effect(io, unsafe)` - which was read as ONE custom effect spelled with
the comma, so `AX3010` reported it "missing" from a body that performed
both (`tests/diagnostics/1018-effect-tag-list.ax`). A list is refused
rather than accepted: one tag line per effect is the spelling every
reader of tags already agrees on. From the free end as well. The four
other refusals the seeded fuzzer's findings added that day reuse
existing codes, because each is the mistake an existing code already
names: a parameter list naming one name twice is `AX3006`
(`duplicate-definition`), a cast form or one-argument primitive with
no value to take is `AX3013` (`partial-application`), `set` on a
built-in or an imported function is `AX3012`, and an effect's name
where a value goes is `AX3001`.

`AX3077` (`axtag-misplaced`) and `AX3078` (`pure-tag-spelling`) are
the two tag refusals that followed. `AX3077` is a key the compiler
checks on a declaration it can't check it on, such as
`restrict(no-alloc)` above a `data`: the claim was recorded and never
read (`tests/diagnostics/1030-axtag-misplaced.ax`). `AX3078` makes
purity one spelling, `;@axiom:effect(pure)`: `;@axiom:pure` and its
slips are refused wherever they stand
(`tests/diagnostics/1031-pure-tag-spelling.ax`). An unknown key is
still legal metadata, so the tag namespace stays open.

**ERR-DIAG-3 (P). Poisoning, not cascading.** Where a check on an error
type fails, propagate `TError` and guard downstream comparisons, so one
mistake draws one diagnostic. Reach for a group key only when a real
cascade survives poisoning. The `dedup` pass in the retired Rust
compiler never had a call site, and the lesson recorded in
[diagnostics.md](diagnostics.md) is to build it *with* one.

---

## 7. Surface

**ERR-SUGAR-1 (R). There is no `?` postfix operator, and there will not
be one spelled that way.** `?` isn't an identifier character: `empty?`
is `AX1001`, and the compiler's own help says so: *"`?`, `~` and `@`
are not identifier characters at all"*. Admitting it is a language
change that moves the lexer, `tree-sitter-axiom/` and
`self_host/format.ax` together. Even that wouldn't be enough. Rust's
`?` means *return from the enclosing function*, and Axiom has no early
return, so the operator would have nothing to expand into.

**ERR-SUGAR-2 (H). The propagation form is a binding form.**
`(try x e body)` binds `x` to the success value of `e` and runs
`body`. If `e` is an `Err`, it answers that error unchanged:

```scheme
(import Err)

(:: halveTwice (-> Int (Result Int Error)))
(fn (halveTwice n)
  (try a (divChecked n 2)
    (try b (divChecked a 2)
      (Ok b))))

(fn (main)
  (match (halveTwice 40)
    ((Ok v) v)
    ((Err e) 1)))
```

`(halveTwice 40)` answers `(Ok 10)`, so the program exits 10.

`try` is a macro in `stdlib/Err.ax`. Expansion runs before the
checker (`self_host/expand.ax`), so everything it generates is
type-checked, and a macro costs no seed rebuild. Here is what it
expands to:

```scheme
(try x (mayFail 1)
  (use x))

; expands to
(match (mayFail 1)
  ((Err er) (Err er))
  ((Ok x) (use x)))
```

The body lands in the arm, which is exactly `ERR-PROP-3`'s safe shape.
So the form makes the TCO-correct spelling the default, and you have to
write the dangerous spelling out by hand. That is the whole case for
having it.

`try` depends on `MAC-HYG-10` in [macro-system.md](macro-system.md): a
binder position holding a macro parameter takes the *argument's* name
and isn't renamed. A binder introduced through one parameter then
scopes over syntax arriving through another:

```scheme
(macro (bind! x e body) (let ((x e)) body))
(fn (main) (bind! v 41 (+ v 1)))   ; exits 42
```

This holds in all three binder positions the expander owns: `let`,
`lambda` parameters and pattern binders. An argument that isn't a name
is `AX3035`. `tests/stdlib/371-err-module.ax` term 16 gates `try`, and
it doesn't compile against an expander without `MAC-HYG-10`.

**ERR-SUGAR-3 (H). A contextual wrapper is a function, not a form.**
`(withContext r "reading the manifest")` replaces an `Err`'s `context`
and passes `Ok` through. It needs no binder, so it never depended on
`MAC-HYG-10`. It reads the error's fields through `errContextOf` rather
than in the arm, because `ERR-TYPE-3a` required that when it was
written. That rule is retired, so the indirection is now a kept name
rather than a necessity, and `371` term 2 checks the direct spelling
against it.

---

## 8. What this specification found

Probing this model's claims, rather than reading them, found five
defects that nothing had recorded. All five are closed: four are
fixed, and `B2` was resolved by removal in 0.6.0.

**B1 — A macro binder did not scope over another parameter's syntax.
Fixed.** `(macro (bind! x e body) (let ((x e)) body))` put the
caller's `body` outside the binding `x` introduced, so `body` couldn't
see it and drew `AX3001` (`undefined-variable`). A macro that binds and
reads through the *same* parameter worked, because the rename table
mapped the template's `x` to the gensym on both sides:

```scheme
(macro (bindSelf! x e) (let ((x e)) x))
(fn (main) (bindSelf! v 42))     ; exits 42
```

That right answer for the wrong reason kept the defect hidden. It
blocked every binding-form macro: `let*`, `for`, `with` and `try`.
`docs/macro-system.md` recorded binder-direction hygiene as complete,
which it was only for the direction anyone had tested. It is fixed as
`MAC-HYG-10`, with `AX3035` for an argument that isn't a name.
`ERR-SUGAR-2` is the form it unblocked.

**B2 — A two-parameter trait declared and checked, and could not be
implemented. Resolved by removal in 0.6.0.**
`(trait (From a b) where (from :: (-> a b)))` was accepted, but
`(impl (From Int Bool) where ((from ...)))` was `AX2003 syntax error`
at the `impl`, while the one-parameter control compiled and ran. That
was `documented-but-inert` in its purest form: the declaration surface
admitted something the implementation surface couldn't express. Both
keywords now report `AX2004` before anything else runs. The capability
record that replaced them takes two parameters with no asymmetry:
`(struct ConvertOf (a b) (convert : (-> a b)))` declares, checks and
runs. `From`-style *implicit* conversion, which the defect blocked, is
now refused by design, and `ERR-TYPE-3` states the design.

**B3 — `newtype` was a documented keyword the compiler does not
implement. Fixed.** `docs/reference.md`'s keyword table listed
`newtype` as a *"Newtype wrapper"*. The compiler answers `AX3027`:
*"`newtype` is neither a declaration keyword nor a visible macro"*. The
row is gone and the compiler is unchanged, so the table now says what
is true: there is no `newtype`. This is the kind of drift
`scripts/check-doc-drift.sh` exists to catch, but that gate doesn't
read the keyword table, so a probe found it instead.

**B4 — A fallible call leaked 32 bytes. Fixed.** This is `ERR-MEM-4`.
It wasn't a defect of this model, but this model was the first to put
a number on it, and the number is what closed it. The release was
already emitted, and a `match` binder was suppressing it. `MM-LIFE-2c`'s
ownership events weren't the cause. A field-class test on the binder
path alone closes a concrete `Int` field and leaves `(Ok v)` untouched,
because the useful type is the *instantiated* one, and only the checker
has it.

**B5 — A `match` binder over a polymorphic scrutinee had no type.
Fixed.** `(match r ((Err y) y.code))` where `r : (Result a Error)` was
`AX3004 expected struct or data type, found _a`. The checker
instantiated the constructor's field to a fresh variable and never
resolved it against the signature, so the binder had no fields.
Passing the binder to a function whose parameter is declared at the
concrete type recovered it, and that workaround was `ERR-TYPE-3a`.
Every combinator in `stdlib/Err.ax` is still written that way, because
those are public names and the shape costs nothing, not because the
rule still binds.

`ctorPatEnv` closed it (`a388fc1`), as a side effect of unrelated work
on nested patterns. The claim then survived a sweep that re-ran every
fixture the documents name, because B5 named no fixture: a defect has
none. A claim that something does *not* work is invisible to a gate
built out of things that do. `ERR-ADOPT-3`'s uniqueness claim, recorded
in [memory-model.md](memory-model.md) §9.1, is the same mistake.
`tests/stdlib/371-err-module.ax` term 2 now pins it with a program: it
runs the direct read and the routed one and compares their answers.

---

## 9. Conformance summary

| Rule | Status | Held by |
|---|---|---|
| `ERR-TYPE-1`, `2` | **H, gated** | `stdlib/Err.ax`; `tests/stdlib/371-err-module.ax` |
| `ERR-TYPE-3` | **H, gated** | `mapErr`, `371-err-module.ax` term 8 |
| `ERR-TYPE-3a` | **R** | Retired: the limitation it recorded is gone (`ctorPatEnv`); `371` term 2 pins both spellings |
| `ERR-TYPE-4` | **H, gated** | `okOr`/`toOption`, `371` term 4 |
| `ERR-TYPE-5` | H | `fldClass` classifies from declared types |
| `ERR-PROP-1` | H | the language having no other mechanism |
| `ERR-PROP-2` | H | `#effect=pure` accepted when inspecting an error; refused with `AX3010` when constructing one |
| `ERR-PROP-3` | **H, gated** | `tests/stdlib/370-error-propagation.ax` term 16 + ablation |
| `ERR-PROP-4` | **H, gated** | `tests/diagnostics/1005-recursion-in-scrutinee.ax` + `severity.policy` + `scripts/check-diagnostic-coverage.sh` |
| `ERR-PROP-5` | H | effect inference, unchanged |
| `ERR-MEM-1` | H | `fldClass`, `self_host/codegen.ax` |
| `ERR-MEM-2` | **H, gated** | `370-error-propagation.ax` term 4 + ablation |
| `ERR-MEM-3` | H | 176 / 288 bytes, mono / poly, 2000 iterations |
| `ERR-MEM-4` | **H, gated** | `370-error-propagation.ax` terms 32 + 64, and `scripts/check-fallible-reclaim.sh` ablates the compiler |
| `ERR-MEM-5` | H | `AX3029` / `AX3030` |
| `ERR-MEM-6` | R | `linear` enforces nothing |
| `ERR-REC-1` | R | no unwinding exists |
| `ERR-REC-2` | **H, gated** | `371-err-module.ax` terms 64 and 32; `312-checked-arithmetic.ax` boundary terms for all seven operators, pinned at `--opt` 0, 1, 2 and 3 by the case's `.optstable` marker in `scripts/run-stdlib-tests.sh` |
| `ERR-REC-3` | R | handlers are tail-resumptive |
| `ERR-REC-4` | **H, gated** | `tests/stdlib/490-main-result-ok.ax`, `491-main-result-err.ax` (+ `.out`/`.exit`/`.err`) |
| `ERR-REC-5` | P | — |
| `ERR-REC-7` | **H, gated** | `stdlib/Fallible.ax`; `410-fallible.ax`: thirteen values, four of them memory terms with an ablation; `tests/diagnostics/389-unhandled-at-main.ax` for the missing handler, which `AX3053` names at compile time; `scripts/check-steady-state.sh`'s `batch` probe, and `examples/batch-fallible` under the same gate |
| `ERR-REC-8` | **R, superseded** | Range-constrained subtypes were refused as a type (roadmap item 11, D2), then built: `(subtype N is Int range lo..hi)` (`tests/selfhost/134-subtype-checked.ax`, `135-subtype-violated.ax`), with narrowing conversions checked by the contract trap (80). The `;@axiom:pre(...)` vehicle still stands beside it. `docs/subtypes-design.md` keeps the case for, the reversal and the re-measured counts |
| `ERR-DIAG-1` | H | `mkDiag` is the only channel |
| `ERR-DIAG-2`, `3` | P | No proposal is open: the last one, `AX3043`, is built (`1008-error-payload-untyped.ax`). `scripts/check-doc-drift.sh` fails on a proposal whose number is spent |
| `ERR-SUGAR-1` | R | `?` is `AX1001` |
| `ERR-SUGAR-2` | **H, gated** | `try`; `371` term 16, `MAC-HYG-10` |
| `ERR-SUGAR-3` | **H, gated** | `withContext`; `371` term 2 |

Every rule marked **H** names what holds it. What remains open is
`ERR-REC-5`, `ERR-DIAG-2` and `ERR-DIAG-3`, whose rows say so, and the
migration itself (§10).

---

## 10. Adoption

**ERR-ADOPT-1 (P). The migration is 64 sites by §1.2's `grep` proxy,
and 19 public functions over 6 modules by the metric that is gated:
10 `failure` and 9 `absence`. It is not one commit.**

§10.1 has what is left today, and §10.2 has the order in which the
slices actually landed. `compat/BREAKING` declares every ported
function against the version that retyped it.

A `Result` whose `Err` arm builds its message pays more than one with a
literal message. `axiom symbols` shows the difference:

```text
F openish  "(Int -> Result Int Error)"  #effects=Alloc,Mut
F openLit  "(Int -> Result Int Error)"  #effects=Alloc
```

The first builds its message with `concat`, and the second uses a
literal. A function that pays `Alloc, Mut` cannot carry `pure`, cannot
pass `restrict(no-alloc)`, and cannot sit in a `handle` checked
exhaustive against a narrower row. P6 in
[memory-model-v2-proposal.md](memory-model-v2-proposal.md) was proposed
to remove this cost. It stays refuted, because its `Mut` half is
unsound, and the migration doesn't need it.

The two populations barely overlap. All 29 failure sentinels, the ones
that become `Result`, sit in modules with no `no-alloc` or `restrict`
claim. `Sys.ax` holds 26 of them: syscall wrappers in a module that
already declares `effect(io)` seventy times. The modules dense with
`no-alloc` and `restrict` claims (`Str.ax`, `Tui/Keys.ax`, `Utf8.ax`
and `Tui/Term.ax`) carry absence sentinels. Those become `Option`,
which carries no `Error` and builds no message.

An `Option` still needs a block once something stores it. `(Some v)` is
a constructor application, and `restrict(no-alloc)` refuses an
allocating one with `AX3049`. Five absence lookups carry that claim
themselves: `strHexVal`, `utf8DecodeAt`, `utf8CharAt`, `keyStrEnd` and
`strFindByte`.

A function whose every tail is `None` or `(Some e)` is emitted as a
two-register pair, with no boxed body beside it. A caller that needs a
block builds it at the call, and the effect walk charges that caller's
row, not the lookup's
([unboxed-sums-design.md](unboxed-sums-design.md) §5b). So
`restrict(no-alloc)` holds for a lookup of that shape, checked against
its IR. The pair doesn't yet take a function that tail-calls itself,
which is why `strFindByte` needed a different fix (§10.1).

`tests/diagnostics/384-restrict-no-alloc-ctor.ax` pins the rule. Its
`some` and `none` arms stay silent. Its `held` arm `let`-binds the
answer past its match and gets `AX3049`: the block didn't vanish, it
moved to whoever stores the answer.

The `grep` proxy sizes the work and is recomputed rather than quoted
(§1.2). The gated unit is a public function whose body answers a
sentinel: what the migration ports, and what a caller depends on.
`compat/SENTINELS` records the count per module, split into `failure`
and `absence`.

`scripts/check-compat.sh` recomputes the census and requires it to
agree with `compat/SENTINELS` row for row. A module whose count rises
fails. A port that lowers a count must lower the file in the same
commit, or it fails too. An ablation probe plants a public function
that forwards a raw syscall in a copy of `stdlib/`, and the census must
count it. The gate reports every disagreement before it exits.

The census is `sentinel_census` in `tests/compat/verify-compat.py`.
A body that mentions a syscall counts as `failure` only when the
syscall's result reaches the answer, directly or through a `let`
binder. A version that followed only direct returns wrongly moved
`sysNowMonotonic`, a real failure that forwards `clock_gettime`'s errno
through such a binder. A body with no `-1` in return position never
reaches the rule, so `netAccept` is untouched by it.

The slices, in order, each green before the next starts:

1. `stdlib/Err.ax`. Done. It provides `Result`, `Error`, `mapErr`,
   `withContext`, `okOr`, `toOption`, `andThen`, `mapOk`, `unwrapOr`,
   the `ERR-REC-2` checked operators and `try`. It went first because
   nothing else in `stdlib/` had to change.
   `tests/stdlib/371-err-module.ax` exercises it across a module
   boundary. The FFI fixtures match `Ok` and `Err` across the Rust
   boundary (`tests/ffi/demo/050-fallible.ax`,
   `tests/ffi/demo/184-nested-fallible.ax`).

   By this repository's rule, an export that no term reaches is
   documentation, not specification. `isOk`, `isErr`, `errMessage`,
   `errContext`, `mapOk`, `unwrapOr`, `remChecked` and `shrChecked`
   were once in that state. All eight have callers now, some only
   through `371-err-module.ax`. Recount before deleting any of them.
2. `stdlib/Utf8.ax`, `stdlib/Str.ax` and `stdlib/Path.ax`. The proxy
   counts 11 sites: no `errno`, pure, and no callers outside `stdlib/`.
   It was planned as the rehearsal. §10.2 recounts it and explains why
   it landed last.
3. `stdlib/IO.ax` and `stdlib/Sys.ax`: the `-errno` convention.
   `Error.code` is the errno, negated back, so no information is
   invented and none is lost.

   **Files.** In `IO.ax`, `writeFile`, `appendFile`, `removeFile`,
   `renamePath`, `fileSize`, `makeDirAll`, `removeDir` and `copyFile`
   answer `(Result Int Error)` through one converter, `ioResult`. In
   `Sys.ax`, `sysWriteFile`, `sysAppendFile`, `sysUnlink`, `sysMkdir`,
   `sysRmdir`, `sysRename` and `sysFileSize` answer it through
   `sysResult`. `IO`'s wrappers re-wrap `Sys`'s `Result` rather than
   convert it: `Sys` has the errno and `IO` has the path, so the code
   carries through and only the message is rebuilt.

   `IO.writeStr` still answers a byte count or a negative errno. It is
   the hot printing path rather than a filesystem call, so it is its
   own decision.

   `self_host/` calls none of these. Porting the one internal use and
   two test fixtures gave `unwrapOr`, `isErr` and `errCode` callers.
   `tests/stdlib/055-filesystem.ax` asserts an errno through `errCode`
   instead of comparing against `(- 0 2)`. With a sentinel, "it failed
   with 2" and "it answered 2" are the same `Int`, and a `Result` tells
   them apart.

   `Sys` doesn't sit below `Err` in the import graph. `Err` imports
   only `Str`, and `Str` imports `Mem` and `Vec`, so `(import Err)` in
   `Sys.ax` compiles with no cycle. Read the import graph before you
   trust an ordering claim about it.

   A port can also produce wrong code that the checker cannot see.
   `makeDir`'s body
   is one `sysMkdir` call, and its signature says `Int`. When `sysMkdir`
   began answering a `Result`, `makeDir` still type-checked and returned
   a heap address where an errno belonged, because `Int` is the
   universal heap-handle type. The compiler accepted it.
   `tests/stdlib/055-filesystem.ax` caught it by printing
   `got=4372103456 want=0`. A fixture that asserts an observed value
   covers the ground the type system doesn't.

   **Processes.** `sysSpawn`, `sysWaitPid`, `sysRun`, `sysRunPath` and
   `sysRandomBytes` answer `(Result Int Error)`. `sysRun`'s three-way
   contract is split by type rather than by sign. `Err` means the child
   never ran, and carries the spawn's own errno. `Ok` means it ran, and
   carries what it answered, including `128+n` for a signal.

   **Socket configuration.** `netBind`, `netListen`, `netConnect`,
   `netShutdown`, `netSetOptInt`, `netSetBlocking` and
   `netSetNonBlocking` answer `(Result Int Error)` through `sysResult`.
   Each answers only whether it did what it was asked, so `Ok 0` is the
   whole of success and the errno is `Error.code`. Call sites that
   compared the answer against `0` use `isOk` or `isErr`, and
   `tests/net/echo-server.ax` reports a failed bind through
   `errMessage` and `errCode`.

   **"Did it work" calls.** `sysCloseFd`, `netPollAddRead`,
   `netPollDelRead`, `sysSignalBlock` and `sysKill` answer
   `(Result Int Error)`. Porting `sysCloseFd` widened one other row:
   `sysFileExists` gains `Alloc`, because it closes the descriptor it
   opened. `verify-compat.py generate` over `stdlib/` differs in
   exactly those two rows before and after, because every other
   function that closes a descriptor already allocated. No `no-alloc`
   module reaches either name.

   **Descriptors.** `sysOpenPath`, `netSocketTcp`, `netSocketTcp6`,
   `netPollCreate` and `netSignalOpen` answer `(Result Int Error)`.
   These head a resource lifetime, so they cost the most. A "did it
   work" call is one expression at each site, but a call that answers a
   descriptor retypes `lsn`, `cli`, `pfd` and everything downstream.
   Nine fixtures moved from `(let ((lsn netSocketTcp)) BODY)` to a
   `match` whose `Err` arm says what the program does with no socket.
   That is the point: seven of `netSocketTcp`'s seventeen call sites
   never tested the result.

   **Private raw forms.** `sysOpenPath` keeps a private raw form,
   `sysOpenRaw`. Ten functions in `Sys.ax` open a descriptor, test it
   and convert the errno into their own answer: a `sysResult` with
   their own operation name, a `Bool` or a `String`. Routing them
   through the public wrapper would build a `Result` only to take it
   apart. `sysReadFile`, `sysFileExists`, `sysReadDir` and `sysGetCwd`
   are unchanged in `axiom symbols` across the port.

   `netSetNonBlocking` keeps one too, for a sharper reason.
   `netAcceptFinish`, shared by `netAccept` and `netAcceptFrom`, calls
   it once per accepted connection on targets where the kernel doesn't
   take `SOCK_NONBLOCK`. Porting that callee gave `netAccept` and
   `netAcceptFrom` `Alloc`: an `(Ok 0)` per connection, allocated below
   the echo server's arena mark and never reclaimed. The fix is a
   private `netSetNonBlockingRaw` that answers the raw result, with the
   `Result` as the public skin over it. `axiom symbols` is what showed
   the problem, so after porting a callee, check its callers'
   `#effects=` rows.

   `scripts/check-net.sh` doesn't catch this. With the allocation
   restored to the accept path, the gate stayed green at 182× against
   its floor of 50 (344× with the split). The scoped arm's growth over
   9,800 connections rose from 400 KiB to 512 KiB, about 12 bytes per
   connection, which is within what a page-granular RSS reading can
   resolve. The ratio floor is sized to catch an arena that stopped
   reclaiming, not one 32-byte block per connection. What holds a
   hot-path exclusion is `#effects=` in `axiom symbols`, which is
   exact.

   **Hot paths.** The slice line is where a call runs, not what it
   does. The calls above run once per socket. `netAccept` and
   `netAcceptFrom` run once per connection, `netPollWait` and
   `netPollSignalAt` once per wake, and `sysWriteFd` and `sysReadFd`
   once per write. In `tests/net/echo-server.ax`, `netAccept`,
   `netAcceptFrom` and `netPollWait` are reached below the
   per-connection `__axiom_arena_mark`, so a boxed `(Ok n)` there is a
   block per call that the reset never rewinds.

   The hot-path calls were held out of this slice for that reason (`netPollSignalAt` also
   for the one below). Once a `Result` became an unboxed pair, a direct
   match builds no block on success
   ([unboxed-sums-design.md](unboxed-sums-design.md) §5b), and §10.1
   records their port. `runTool` in `self_host/driver.ax` unwraps
   at the stdlib boundary, because the compiler's own phases are
   slice 4.

   `netPollSignalAt` reports an absence. It answers the signal named by
   event `i`, and every bad-path answer it wrote was a hand-written
   `-1` meaning "this event is not a signal". All five call sites read
   it as a presence test, and `tests/stdlib/315-signal-in-poll.ax`
   checks that a socket event is not read as a signal. That is
   `ERR-REC-3`'s absence, so it answers `(Option Int)`. The census had
   filed it under `failure`, because a mention of a syscall in its body
   outweighed its `-1` returns. On Linux, a short `signalfd` read also
   answered `-1`, so the port had two outcomes to place, not one. It
   answers `None` for both.

   The descriptor port surfaced two defects. In `311-preforked-server.ax`, the
   connect loop's `Err` arm didn't advance `sent`, whose bound is the
   loop condition, so the fixture could hang. In
   `315-signal-in-poll.ax`, the assertion `(>= sh 0)` could no longer
   fail once `sh` was an `Ok` binder, because `sysResult` builds `Ok`
   only for a non-negative answer. The assertion moved to the `Err`
   arm, where it can fail.

   Porting a callee can force its caller. `platformWriteFd` in
   `stdlib/Sys/Platform.darwin.ax` couldn't move before `sysWriteFd`,
   which forwards it wherever `usesSyscallAbi` is 0. Porting it alone
   gave two errors at once:

   ```text
   E AX3010 ... `effect(pure)` claim contradicted: body performs Alloc
   E AX3004 stdlib/Sys.ax:160 ... expected Int, found Result Int Error
   ```

   The first came from the `;@axiom:effect(pure)` tag on Darwin's `-ENOSYS`
   stubs, since a boxed `Result` allocates. The second is the caller.
   `scripts/check-stdlib-api.sh` requires all five `Sys/Platform.*`
   files to declare the same names, so a change there touches five
   files, and the real implementation is in `Platform.windows.ax`.

   `unwrapOr` with a constant is not a port. Where the sentinel
   carried which failure happened, a fallback value destroys that and
   nothing complains. It caused three defects:

   - A job pool turned a failed spawn into pid `0`. That is not `< 0`,
     so the pool counted it live, and `sysWaitPid 0` waited for any
     child in the group. The test hung rather than failed.
     `stdlib/Par.ax` matches on `parRunOne`'s `Result` instead of
     unwrapping it, and its comment says why.
     `tests/stdlib/476-par-pool.ax` checks that a missing program
     answers a negative errno in its own slot.
   - In `993-filesystem-verbs`, `(== (unwrapOr … 0) -2)` was silently
     false, so the case counted one fewer success and exited 1 for 77.
   - `305-path-search` printed the fallback for every failure: the
     vacuous pass that fixture's own comment exists to prevent.

   All three use `match` now. **`unwrapOr` is safe only where the
   fallback is genuinely equivalent to the error.**
4. `self_host/`: the compiler's own phases, where the model stops
   being a library and becomes the thing that proves it.

   Twenty-five declarations in `self_host/` carry a sentinel contract.
   Classified by what the sentinel means, twenty-one are absence, not
   failure. `namedFieldIndex` answers "where the pattern mentions field
   `n`, or -1". `structFieldOf` answers "0 when the struct does not
   declare the name". `findExternUnit`, `scopeFindIdx`,
   `slotFirstIndex`, `expRepIndex` and the rest have the same shape.
   They are lookups, and a lookup that finds nothing has not failed.

   Of the other four, `tcAddExtern`'s comment is about a parameter,
   not a return. `targetCode`'s `-1` is an unknown target name, which
   the caller already refuses loudly. `runTool` is the one genuine
   failure, bounded at the stdlib edge, where it unwraps `sysRunPath`
   to 127. So the `Result` work in this slice is one function, and it
   is done.
5. The REPL surface: `check-repl-selfhost.sh`'s session bank, extended
   with an `Err` at the prompt.

`internFind` in `stdlib/Intern.ax` answers `(Option Int)`. That module
carries no `restrict` claim, so its cost was a question for measurement
rather than a refusal. Two compilers were built by the same compiler
from sources differing only in this port, and each compiled the same
197,338-line input, best of five. This measures a boxed `Option`:

| stage | -1 | `(Option Int)` | |
|---|---|---|---|
| check (lex, parse, expand, typecheck) | 0.4484s | 0.4469s | flat |
| serialise and write the IR | 1.2980s | 1.3440s | **+3.5%** |
| in the `axiom` process | 1.7464s | 1.7909s | +2.5% |
| `axiom build`, end to end | | | +0.4% |

A second pair read +4.6% and +3.4% for the same two rows, so the cost
is about +4% on code generation, quoted as a range. End to end it is
+0.4%, because 84% of a build is `opt` and `llc`.

`#effects=` predicted which callers would pay. `internFind` had nine
external callers, each testing `(< id 0)`. The two in
`self_host/namespace.ax` already read `Alloc,Mut` and run during
resolve, and the check stage didn't move. The five in
`self_host/codegen.ax` had an empty row, and the whole +4.6% is in the
stage they run in. Read the effect row before a port: it sorts the
callers into those that pay and those that don't.

The interner's own hot path pays nothing. `internFindFrom` keeps the
`-1` and stays private, and `internIntern` calls it directly rather
than through the public wrapper. `Path.ax` makes the same exception
for `pathExtIndex`. A public boundary is worth a type, and a recursion
is not.

Check `#restrict=` as well as `#effects=`. They answer different
questions, and `axiom symbols` prints both.

The boxed cost is removable.
[unboxed-sums-design.md](unboxed-sums-design.md) makes `(Option Int)` a
`{tag, payload}` register pair instead of a heap block. Through the
real `opt`, `llc` and `cc` pipeline, the wrapper goes from 11.86 ns to
0.36 ns, recovering 96.9% of the box's cost. With `(Some v)` no longer
allocating, the absence lookups that carry `restrict(no-alloc)` stop
being blocked, and a `Result`'s success path stops widening its row.
Its failure path still builds an `Error`, so those rows still widen
(§10.1). Unboxed sums come before the rest of ERR-ADOPT-1, so no
function is ported twice.

<a id="101-what-is-actually-left-measured-rather-than-planned"></a>
### 10.1 What is left

Every remaining sentinel reports either **absence** (it wants `Option`)
or **failure** (it wants `Result`). That is §5's distinction, and
sorting the sentinels by it changes what finishing the migration means.

| | absence (wants `Option`) | failure (wants `Result`) |
|---|---|---|
| `stdlib/`, by the census that read prose | 8 | 5 |
| `stdlib/`, by the census that reads bodies | **9** | **29** |
| `self_host/`, slice 4's 25 | 21 | 1 |
| `stdlib/`, after slices 1–4 and the type correction below | 7 | 9 |
| `stdlib/`, after the box moved to the caller (`docs/unboxed-sums-design.md` §5b) and the two ports it permitted | 3 | 0 |
| `stdlib/`, today, after `strFindByte` became a loop | **2** | **0** |

The floor is two absence rows and no failure rows. The rest of this
section explains how the census reached those numbers.

#### The census reads bodies

The first census matched a doc-comment against six phrases. The census
in `compat/SENTINELS`, gated by `scripts/check-compat.sh`, reads the
declared return type and the body instead. That changed both columns.

The prose census counted five failures, and one of them was wrong.
`sysRandomNum` is `(pub fn (sysRandomNum) 33554932)`, the `getentropy`
syscall number: a constant with no failure path. It was counted because
the comment walk climbed a `; ---` banner into prose about
`getentropy`'s `0 or -errno` contract. The real entropy call,
`sysRandomBytes`, answers `(Result Int Error)`.

The prose census also missed most of the failures. Almost every `net*`
and `sys*` call forwards a raw syscall result, in wording the six
phrases did not match: `netListen`, `netAccept`, `netBind`,
`netConnect`, `sysWriteFd`, `sysReadFd`, `sysOpenPath`, `sysCloseFd`
and eighteen more. `stdlib/Sys.ax` alone had 26. The prose metric
rewarded silence: writing the house sentence above any one of them
would have raised its module's count and failed
`scripts/check-compat.sh` for a commit that changed no contract.

So the `Result` migration started from 29 public functions that hand a
caller a negative errno, not from four.

#### The failure column

The `Sys.ax` slices of §10 took most of the 29: seven in the
socket-configuration slice, five in the "did it work" slice, five in
the descriptor slice and one in the working-directory slice. One more
turned out to be an absence the census had misfiled. That left ten,
and the type correction below removed `platformExitWith`. The nine
that remained, seven in `stdlib/Sys.ax` and two in
`stdlib/Sys/Platform.darwin.ax`, were each excluded on a measurement.

`sysGetCwd` was the one exclusion that rested on shape rather than a
measurement: "it answers a `String` and its failure is `""` rather
than an errno". Every other exclusion in the module rests on
`#effects=IO` widening to `Alloc,IO` under `writeStr` and `println`.
`sysGetCwd`'s row is `Alloc,IO,Mut` before and after the port, because
it already `memAlloc`s its buffer and `strDup`s its answer. It and
`IO.cwd` are the only ERR-ADOPT-1 rows in `compat/BREAKING` marked
`CHANGED` rather than `WIDENED`, so they cost a caller nothing. The
sentinel had a cost: `ERANGE`, `ENOENT` and `EACCES` all arrived as the same
`""`, and all five call sites read it as a presence test.

Unchecked sentinels are why the migration exists. `netSocketTcp` has 17
call sites, and seven of them never test the result at all.

The hot-path calls were excluded because a boxed `(Ok n)` would
allocate per call (`IO.writeStr`), per connection or per wake (the
`net` accepting and polling calls), outside the per-request arena
scope. `#effects=` in `axiom symbols` is what holds that line, not
`scripts/check-net.sh`. §10's slice-3 note has the measurement: with a
per-connection allocation restored to the accept path, that gate stayed
green at 182× against its floor of 50. Its ratio is sized to catch an
arena that stopped reclaiming, not one 32-byte block per connection.

#### The absence column

Seven lookups in `stdlib/` answered `-1` for "not found" and wanted
**`Option`**, which is built in and needs no import (§1).

- Two of the seven are in `stdlib/Str.ax`, which cannot import `Err`
  because `Err` imports `Str`. They could never have been `Result`
  debt.
- `netPollSignalAt` was counted as a failure until the census learned
  to follow a syscall result through a `let` binder. It is `Option`
  debt, and `compat/SENTINELS` records it as a declared rise, not a
  new sentinel.

`Option` has two costs. At `--opt 2`, over 20,000,000 calls, a `-1`
return costs **1.4 ns** and a boxed `(Some v)` costs **10.4 ns**
(7.4×) for the allocate, store, match and release round trip. The
allocation is also a refusal wherever the lookup claims
`restrict(no-alloc)`. Five of the seven did, so porting them meant
withdrawing a checked claim.

The arena bump moves zero bytes for that loop, because the block is
recycled through its size class. A bytes-only measurement therefore
reports `Option` as free, and it is wrong: the cost is instructions.
`strFindByte` has 62 call sites on the compiler's own scanning path.

The census in `compat/SENTINELS` counts both kinds, so its number does
not reach zero by porting failures alone.

#### Three rows were not debt

A later correction took the census from 19 to 16 without moving a line
of `stdlib/`. The body census decided from what a body *contains*
without asking what the declaration can *hold*.

A struct return has no integer channel. `mkKeyIn` answers `KeyIn` and
`keyNext` answers `KeyEv`, and the checker refuses a `-1` there
outright. A two-line probe reports `AX3004: type mismatch: expected
Int, found Pair`. In `mkKeyIn` the census had found the `pfd` field
inside its constructor, the descriptor-or-`-1` the module documents
just above it. In `keyNext` it had found the timeout argument
`(- 0 1)` passed to `keyInFill` to mean "block". Neither is an answer,
and no `(Option Int)` could replace either. `keyInFill` is the one real
absence row of the three, and it stays.

A function nobody observes has no outcome to report.
`platformExitWith` exits the process. On Windows it is
`(winExitProcess code)`, which does not return. The four syscall-ABI files
answer `-ENOSYS` from a stub their own comment calls "never reached".
Its one caller, `sysExitWith`, puts it in statement position inside a
`{ ... 0 }` and discards the value. A `(Result Int Error)` there would
allocate on the process-exit path, break the function's `effect(pure)` claim,
and encode an outcome no caller reads. `platformWriteFd` and
`platformReadFd` are not excluded with it, because they answer a real
count on Windows.

We rejected the obvious fix in the census itself. Both phantom absence
rows come from `in_return_position` not being transitive: it climbs to
the enclosing form, sees `if`, and stops without asking whether that
`if` is an answer or an argument. Making it climb further
under-reports thirteen rows, among them `strFindByte`, `utf8DecodeAt`
and `keyStrEnd`, the clearest absence sentinels in the tree. That
happens because `let` and `fn` are transparent to return position, and
the obvious climb treats them as opaque.

Under-reporting is the failure the body census exists to prevent. So
the census checks the declared type instead, and the position rule is
left alone and named in `tests/compat/verify-compat.py`. Both
directions were checked. A new `Int`-returning `(- 0 1)` planted in
`Utf8.ax` takes its count from 2 to 3, and the same body declared to
answer a struct stays at 2.

#### The pair shape moved the rest

That correction moved no row of the migration. Every one of the sixteen
was blocked or excluded on a measurement. What moved them was a change
to the measurement's premise.

A function returning `(Option Int)` or `(Result Int Error)` in the pair
shape no longer allocates on any path. The emitter writes its body once
as a two-register pair, and a caller that needs a block builds it at
the call, where the checker charges it
(`docs/unboxed-sums-design.md` §5b).

The absence column went from 7 to 3, and then to 2.

- `strHexVal`, `utf8DecodeAt`, `utf8CharAt` and `netPollSignalAt`
  answer `(Option Int)`. The three `restrict(no-alloc)` claims among
  them stand, checked against the emitted IR by
  `scripts/check-unboxed-sums.sh`. `netPollSignalAt`'s row stays `IO`
  alone.
- `strFindByte` tail-calls itself, and a self tail call is the one
  shape the pair does not take yet, because a loop header and a pair
  return are not reconciled. Ported as it stood, it would keep the
  boxed body and refuse its own claim. Rewritten as a loop, it keeps
  its claim.
  See *The floor is 2* below.
- `keyStrEnd` and `keyInFill` answer three outcomes each, which is not
  `Option`'s shape.

The failure column went from 9 to 0. The nine waited on one question:
may `println`'s effect row widen?

With `sysWriteFd` ported alone, the row widens from `IO` to `Alloc,IO`
on **11 functions** in the compiler's whole closure. Six are public
(`sysWriteFd`, `sysWriteAllFd`, `writeStr`, `printLit`, `printlnLit`,
`rpcPut`) and five are in `self_host/`. There are **zero**
`restrict(no-alloc)` refusals, because nothing in the tree claims to
print without allocating.

The failure path is what widens the row. A failed `write` builds an
`Error` through `sysResult`, and a row is a fact about every path. The
success path is the pair, read from two registers by the direct match
in `sysWriteAllFd`, and it builds nothing.

So the answer is: **`println`'s row may widen, because `println` can
allocate, and only when a write fails.**

- `sysWriteFd`, `sysReadFd`, `netAccept`, `netAcceptFrom`,
  `netPollWait`, `sysNowMicros`, `sysNowMonotonic`, `platformWriteFd`
  and `platformReadFd` answer `(Result Int Error)`.
- `sysWriteAllFd` and `writeStr` keep their `Int` channel. `println`'s
  value is that `Int` in 804 expansions, and the channel above the seam
  is a separate decision.
- Every widened row is declared in `compat/BREAKING` under 0.6.4.

We measured an alternative and did not take it: a private raw twin of
`sysWriteFd` under `sysWriteAllFd`, which keeps `println`'s row at `IO`
exactly. The seam defeats it. `platformWriteFd`, the public Windows
implementation, builds the same `Error` on its own failure path, so the
row widens through the seam whichever way the wrapper is written.

#### The floor is 2

`strFindByte` was held out because "a self tail call is the one shape
the pair does not take yet". That is true of the emitter: `wantsTCO` is
a refusal in the pair's eligibility test in `self_host/codegen.ax`. It
is a fact about the body, not the function, and the body can be written
the other way. Both versions were probed on a copy of the tree:

```text
; the recursive spelling, declared (Option Int)
E AX3049 stdlib/Str.ax:352 `strFindByte` claims `restrict(no-alloc)`
         and the body performs Alloc

; the same function as a `while` loop over `hit` and `i`
OK
```

`Str.strFind`, further down the same file, was already a loop
that answered `(Option Int)`. So `strFindByte` answers `(Option Int)`
and keeps `restrict(no-io,no-alloc,no-foreign)`.

It had **71 call expressions over 18 files**, and 73 after the port,
which adds two arms to `tests/stdlib/030-str.ax` and drops the
self-call. Each was a `(< x 0)` or `(>= x 0)` test or a printed index.
Each is now a `match` at the point of production, so the pair is
consumed in two registers and no caller builds the block that
`384-restrict-no-alloc-ctor` calls `held`.

The port surfaced a defect of the class §10 slice 3 already names: a
`-1` reaching arithmetic that nothing refused.

- `driver.ax`'s directory walk called `strFindByte` a second time to
  find a `.` its own guard had just located at `strLen - 3`. That call
  is now the index.

The floor is 2, and these two rows are not a backlog. `keyStrEnd`
answers an index, "incomplete" or "too long", and `keyScanStr` reads
all three. `keyInFill` answers a
count, end of input, or a full buffer that is still a prefix. Three
outcomes are not `Option`'s shape. Each wants a `data` of its own,
which the register pair refuses by name until a third sum type is
admitted. Both rows rest on that one refusal.

<a id="102-the-order-was-backwards-and-the-sizes-counted-prose-re-derived-2026-09-04"></a>
### 10.2 How the slices landed, and how to size one

The numbered list in §10 is the plan. This table is the order the
slices actually landed in.

| stated | landed | slice |
|---|---|---|
| 1 | **1st** | `stdlib/Err.ax` |
| 3 | **2nd** | `stdlib/IO.ax`, then `stdlib/Sys.ax`'s filesystem and process halves |
| 4 | **3rd** | `self_host/`: one function, `runTool` |
| 2 (part) | **4th** | `stdlib/Path.ax`'s two, and `stdlib/Agent/Tags.ax`'s two, which the list never named |
| 3 | 5th–8th | `Sys.ax` socket-configuration, "did it work", descriptor-answering, `sysGetCwd` |
| — | 9th | `stdlib/Intern.ax`'s `internFind`, a module the list never named |
| 2 (rest) | **10th** | `stdlib/Str.ax`'s `strHexVal`, `stdlib/Utf8.ax`'s two, `Sys.ax`'s `netPollSignalAt` |
| 3 | 11th | `sysWriteFd`, `sysReadFd` and seven more: the failure column reaches 0 |
| 2 (last) | **12th** | `stdlib/Str.ax`'s `strFindByte` |

Slice 2 was called "the rehearsal", and it finished last, over four
separate commits. Slice 3 was called the hard one, "the `-errno`
convention", and it went second, in one day, because `self_host/`
called none of it (§10 slice 3 records this). The list was ordered by
how complicated each convention looked: `-1` is simpler than `-errno`,
so the `-1` modules came first.

What a slice costs depends on two other questions:

1. **Does the module carry a `restrict` claim the port would have to
   withdraw?** `Str.ax` and `Utf8.ax` are the most restricted modules
   in the tree. `Sys.ax` declares `effect(io)` seventy times and
   restricts nothing. So slice 2 was blocked by `AX3049` on
   `(Some v)`, and slice 3 was never blocked at all.
2. **Does the answer get bound, or only tested?** A call whose whole
   answer is "did it work" is one expression at each site. A call that
   answers a descriptor or an index retypes every binding downstream
   of it. That is why the descriptor slice cost nine fixtures and the
   "did it work" slice cost almost nothing, though both sit inside one
   numbered entry.

The plan's sizes came from the `grep` proxy, which counts comment
lines. Slice 2 is stated as "11 sites": `Utf8.ax` 6, `Path.ax` 3 and
`Str.ax` 2, from §1.2's table. Recounted against `9f99ccd`, the tree as
it stood when that table was written, those three files have twelve
hits (the table is one low on `Str.ax`):

| module | hits | comments | code | public functions |
|---|---|---|---|---|
| `Utf8.ax` | 6 | 2 | 4 | **2**: `utf8DecodeAt` (three of the four), `utf8CharAt` |
| `Str.ax` | 3 | 1 | 2 | **2**: `strFindByte`, `strHexVal` |
| `Path.ax` | 3 | 0 | 3 | **2**: `pathLastSlash`, `pathExtIndex` (the third hit is `pathLastDotFrom`, their private helper) |

That is six public functions, not eleven sites. The proxy doubled the
number: three hits were prose, and three more came from counting one
function's three `(- 0 1)` branches as three items and a private
helper as a fourth. It also missed `stdlib/Agent/Tags.ax`'s two, which
landed in the same slice and are not in §1.2's table at all.

The lesson: **size a migration by counting declarations, and order it
by what refuses each one, not by how the convention reads.**
`compat/SENTINELS` does the first and is
gated by `scripts/check-compat.sh`. The second is not gated, which is
why §10.1 names the refusal behind each remaining row.

**ERR-ADOPT-2 (P). Every slice keeps `stage2 == stage3`.** No slice
touches the seed until one has to. The one that does, a built-in
`Result` under `ERR-TYPE-2` if it is ever justified, lands as the
feature first and then `scripts/reseed.sh`, never as both at once.

**ERR-ADOPT-3 (H, discharged). The long-lived programs were the
constraint on `ERR-MEM-4`, and there are two of them.** A compiler
process runs once and exits, so 32 bytes per fallible call was noise
there. The two programs below are where it was not. `ERR-MEM-4` has
closed, so the constraint this rule states is discharged. The rule
stays because these two programs are still what any future per-call
cost has to be measured against.

- `self_host/lsp.ax`, the language server, measured per edit by
  `scripts/check-lsp-selfhost.sh`.
- `tests/net/echo-server.ax` is a pre-forked server whose workers run
  until they are signalled, driven in CI by `scripts/check-net.sh`. It
  is the larger constraint: its budget is a request handler's rather
  than a keystroke's, and the gate drives ten thousand connections
  through it.

Both hold their memory flat the same way: a `__axiom_arena_mark` /
`__axiom_arena_reset` bracket around the unit of work.
`docs/memory-model.md`'s `MM-ALLOC-22` states this as the reclamation
strategy, not an interim one. A `Result` allocated inside the bracket
is reclaimed at the boundary, and one that escapes it is not. That is
what `ERR-MEM-4` had to be measured against, and why the 32 bytes were
a per-*call* figure and not a per-*process* one.

Migrating the compiler's phases to `Result` **MUST** still be
re-measured against `scripts/check-lsp-selfhost.sh`'s per-edit figure
**and** `scripts/check-net.sh`'s scoped-against-unscoped ratio.
`ERR-MEM-4` itself is no longer a precondition. It closed before either
program's own request path migrated, which is the order this rule asked
for.

---

## 11. Worked example

Every rule above converges on one shape. The fallible step is the
scrutinee, the continuation is the arm, and the error value is bound
before it crosses a boundary:

```scheme
(import Err)

; The fallible call is the scrutinee and the recursion is the arm's
; answer. `try` writes that shape for you.
(:: parseAll (-> Int Int (Result Int Error)))
(fn (parseAll toks acc)
  (if (== (vecLen toks) 0)
      (Ok acc)
      (try v (parseOne (vecGet toks 0))
        (parseAll (vecTail toks) (+ acc v)))))   ; ERR-PROP-3: the arm

; The caller says what it was doing. `withContext` takes the whole
; `Result`, not the error, so nothing here reads an `Err` binder's
; fields, which the retired ERR-TYPE-3a once forbade.
(:: parseManifest (-> Int (Result Int Error)))
(fn (parseManifest toks)
  (withContext (parseAll toks 0) "parsing the manifest"))
```

The recursion sits where `ERR-PROP-3` requires it, because that is
where `try` puts it. Each rule behind this shape rests on a probe.
What made the shape writable was a hygiene fix in the macro expander,
not a change to the error types.
