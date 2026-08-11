# The Axiom Memory Model

The normative specification of how an Axiom program represents,
allocates, mutates and reclaims memory, and of what a compiler author
may assume while doing it.

This document is the specification; [v1-roadmap.md §4.1](v1-roadmap.md)
is the design sketch it expands, and
[self-hosting.md](self-hosting.md) is the history that explains several
of the decisions. Where they disagree with this document, this document
is wrong until it is fixed: the roadmap is a plan and this is a
contract.

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

An **H** rule with no evidence is a bug in this document. A **P** rule
that does not say what happens today is the failure mode
[macros.md](macros.md) calls *documented-but-inert*: a reader builds on
a sentence and the compiler disagrees.

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
`IO.printlnInt` instead.

---

## 1. Execution semantics

### 1.1 The abstract machine

**MM-EXEC-1 (H).** An Axiom program is a set of top-level declarations
and one entry point, `main`. Evaluation is the reduction of `main`'s
body. There is no separate initialization phase: a top-level `fn` with
no parameters is a *function*, not a constant, and every reference to it
is a call (`self-hosting.md` S3).

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
`tail`/`musttail` marker is emitted — the loop is built by Axiom's
codegen, not delegated to LLVM. Measured: a self-recursive loop of
5,000,000 iterations answers correctly.

The tail positions recognised are exactly: the expression itself, both
arms of an `if`, the last expression of a `{}` block, every `match` arm,
and every `cond` clause. **A `let` body is not a tail position.**

> `docs/reference.md` attributes this to LLVM — "at `--opt 0` each
> recursive iteration costs a stack frame; `--opt 1` … turn[s]
> self-tail-recursion into a real loop". Measured, the loop is in the
> emitted IR at `--opt 0` too. (`axiom run` ignores `--opt` entirely and
> always builds at 1, which is a separate defect.)

**MM-EXEC-6c (H).** **A mutual tail call does not.** The compiler emits
a plain `call`; mutual tail recursion runs in constant space only
because LLVM's passes handle it at `--opt >= 1`, and overflows the stack
at `--opt 0`. A program **MUST NOT** rely on mutual tail calls for
unbounded recursion.

**MM-EXEC-6d (H).** Non-tail recursion is bounded by the machine stack.
Measured on an 8176 KiB stack: **174,000–175,000** frames at `--opt 0`
and **260,000–262,000** at `--opt 1`, beyond which the process dies with
SIGSEGV (status 139).

> `stdlib/Mem.ax` writes its byte loops as `while` and explains that
> "stage1 emits no tail-call optimisation at all", so the recursive
> spelling "was a real call chain that overflowed the stack". That
> reason is **stale** — `MM-EXEC-6b` is measured on today's binary, and
> those loops are self tail calls. The `while` spelling is still the
> right one (it needs no optimisation to be flat, and `MM-EXEC-6c` means
> a mutual spelling would still be unsafe), but the comment's stated
> cause no longer holds.

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
reported by `axiom symbols` as `#effects=...`. Effects do **not** appear
in function types. `;@axiom:effect(...)` and `;@axiom:pure` are opt-in
*claims*, validated against the inference; a mismatch is `AX3010`, a
warning. An untagged function is not policed.

**MM-EXEC-9a (H).** **The inferred effect set is an
under-approximation, and a specification must say so.** A conforming
implementation **SHOULD** make it an over-approximation; today it is
not, in six measured ways:

| A function that... | is inferred |
|---|---|
| calls `__store8`/`__store64` — writes arbitrary memory | effect-free |
| calls `__alloc`, or any `Vec`/`Map`/`Str` operation | effect-free (`Alloc` comes only from the `(alloc T)` keyword and from installing a dynamic handler, neither of which allocates much) |
| reads `__argc`/`__argv` — the process command line | effect-free |
| calls the arena primitives | effect-free |
| calls a **trait method** whose implementation does I/O | effect-free, and so are its callers — inference runs before trait dispatch is resolved |
| calls through a local, a parameter, or an unresolved name | contributes nothing but a transparency mark |

`IO` is introduced by a **direct** call to `__syscall0`–`__syscall6` and
by nothing else. Measured — `axiom symbols` reports no `#effects=` at
all for any of these three:

```scheme
(fn (allocs n)    (memAlloc n))       ; allocates
(fn (writes a)    (__store64 a 0 42)) ; writes arbitrary memory
(fn (readsArgs n) (__argc))           ; reads the command line
```

**MM-EXEC-9b (H).** What a purity claim therefore guarantees, precisely:
**`;@axiom:pure` that the checker accepted means the function's body
reaches no `__syscallN` by a path the inference can follow.** It does
**not** mean the function is a mathematical function of its arguments —
it may write memory, read the command line, mutate a heap field through
an alias (`MM-MUT-2`), or print through a trait method. `AX3010` is a
**warning** that does not fail the build.

A program that needs a real purity guarantee cannot get one from this
mechanism today. Stating that is more useful than the alternative,
which is a reader trusting a tag that four constructs walk straight
through.

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
  with status **71**;
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
(fn (main) (handle (greet 7) (Console IO) (lambda (s) { (println s) 0 })))
```
prints `from deep`, exits 7; with the `handle` removed, exits 71.

> `docs/reference.md` states that "Stage1 does not parse `effect`/`handle`
> yet". That sentence is **stale**: the self-hosted compiler parses,
> checks and emits both, including the evidence globals
> (`codegen.ax:3468–3700`). The probe above is the refutation.

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

| Escape hatch | What leaks |
|---|---|
| `(__alloc n)` | the address itself, as an `Int` |
| `(__addr "lit")` | a literal's address |
| `Vec`/`Map`/`Str` handles | addresses, since a handle *is* an address |
| `sysGetPid`, `sysNowMicros` | process and wall-clock state |
| `sysEnv`, `sysArg` | the environment |

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
    %t0 = mul i64 2, 3
    %t1 = add i64 1, %t0
```

Folding happens later, in `opt`, on IR — never on the source, and never
by running a function the source defined.

### 1.4 Process lifecycle

**MM-EXEC-15 (H).** The emitted `@main(i64 %argc, i64 %argv)` stores its
two parameters into `@__axiom_argc`/`@__axiom_argv` and calls the user's
`main`, which is emitted under the name `@__axiom_user_main` and takes
no arguments. The process's exit status is the low 8 bits of `main`'s
result. Measured: a `main` answering 5,000,001 exits 65.

**MM-EXEC-15a (H, defective).** The rename covers the *definition* and
not *references*. A call to `main` — recursive, or from another
entry-file function — emits the undefined register `%main`:

```scheme
(:: main Int)
(fn (main) (if (< 1 0) (main) 5))
```
```
$ axiom check mainrec.ax
OK
$ axiom run mainrec.ax
opt: ...ll:252:19: error: use of undefined value '%main'
  %t6 = phi i64 [ %main, %label_3 ], [ 5, %label_4 ]
```

`check` and `build` disagree, and the emitter's own comment claims the
opposite ("a reference to `main` … must reach the renamed user
function"). Only an entry file's `main` is renamed at all; an imported
module's `main` is module-mangled and coexists with the wrapper.

**MM-EXEC-16 (H).** These exit statuses are **reserved** by the emitted
runtime and **MUST NOT** be reused by a program as a normal result:

| Status | Raised by | Evidence |
|---|---|---|
| 70 | allocator out of memory (`mmap` failed) | the `oom:` block; not reproduced here |
| 71 | operation performed with no handler in extent | measured (`MM-EXEC-10`) |
| 72 | division by zero | measured: `(fn (main) (/ 10 0))` — `check` says `OK`, the run prints `axiom: division by zero` to fd 2 and exits 72 |

Each writes nothing to stdout. I/O is unbuffered — `println` is a direct
`write` loop with no flush — so output produced before one of these
aborts is still visible.

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

**MM-VAL-3c (H, defective).** The sized integer types — `I8`…`I128`,
`U8`…`U128`, `Isize`, `Usize` — are **recognised names with no
representational effect**. All lower to a full-width `i64` with no
truncation, no sign or zero extension, and no width-specific
arithmetic. They are also incompatible with `Int`, so no operator
accepts one: they are inhabited only by bare literals and by `cast`.
There are **no unsigned operations at all**. A conforming
implementation **MUST** either give them widths or remove them.

**MM-VAL-4 (H).** A `Float` is an IEEE-754 binary64 **bit-cast into the
same word**. The compiler decides statically, from declared types, which
words to reinterpret as `double`:

```
define i64 @addf(i64 %a, i64 %b) #0 {
  %d0 = bitcast i64 %a to double
  %d1 = bitcast i64 %b to double
  %d2 = fadd double %d0, %d1
  %t3 = bitcast double %d2 to i64
  ret i64 %t3
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

**MM-VAL-4b (H, defective).** Float arithmetic is selected by the type
name `Float` **and no other**. `Double`, `F32` and `F64` are accepted as
type names and emit **integer** `add` on double bit patterns — silently
wrong numerics, with no diagnostic. `F32` and `F64` additionally reject
float literals, so nothing can construct one. A conforming
implementation **MUST** refuse these names or implement them.

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

**MM-VAL-7 (H).** A `Str` is the address of a two-word header:

| Word | Contents |
|---|---|
| 0 | length in bytes |
| 1 | address of the bytes |

The bytes are NUL-terminated *in addition to* being length-counted, so
`strCStr` hands a path to a syscall without copying, and a `Str` may
contain an interior NUL. `strSlice` **shares** the original's bytes
rather than copying them, so a slice keeps its parent's buffer live and
points into its middle (`MM-LIFE-6`).

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
%t0 = call i64 @axiom_alloc(i64 16)     ; B1: (1 + arity) * 8
store i64 4, ptr %t2                    ; word 0 = tag 4
store i64 7, ptr %t4                    ; word 1 = the field
%t5 = add i64 3, %t0                    ; (A2) IS the immediate 3
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

**MM-VAL-9a (H, defective).** The guard is emitted by `match` and **not**
by field access. `d.v` on a `data` value emits an unguarded load at the
field's word offset with no tag check, so on a mixed-representation type
it dereferences a small immediate:

```scheme
(data T () (E) (N { v : Int }))
(fn (main) (let ((x (E))) x.v))     ; check: OK      run: exit 139 (SIGSEGV)
```

A conforming implementation **MUST** either emit the same guard or
refuse field access on a type whose representation is mixed.

**MM-VAL-9b (H, defective).** A `match` whose arms are **all literals**
is not checked for exhaustiveness. When no arm matches, control falls
through to the merge block and the match yields the contents of its
freshly allocated result cell — which `MM-ALLOC-6` guarantees is zero:

```scheme
(fn (main) (match 7 ((1) 11) ((2) 22)))   ; check: OK      run: exit 0
```

So a non-matching literal `match` answers `0` rather than trapping, and
`0` is indistinguishable from a legitimate result. A conforming
implementation **MUST** require a `_` arm on a literal match, or trap.

**MM-VAL-10 (H).** A `struct` is a heap block of `fields * 8` bytes with
field *i* at word *i*, in declaration order, and **no tag**. The
keyword form `(struct P a b)` and the application form `(P a b)` build
the identical block.

**MM-VAL-11 (H).** A struct variant — `(Circle { r : Int })` — is an
ordinary constructor block under `MM-VAL-8`; the field names are a
compile-time mapping to positions, honoured by patterns in any order.
Field *access* by name is available on a `struct` type only: `c.r` on a
`data` type is `AX3007`, because which variant a sum holds is not known
without a match.

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
(`macros.md` §6): a list-shaped *value* is always a constructor
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
`@_lam_N(i64 %_env, i64 %p)` — environment first, then **exactly one**
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
`mmap`-mapped chunks**, with exactly five words of mutable global state:

| Global | Meaning |
|---|---|
| `@__axiom_bump` | next free address in the current chunk |
| `@__axiom_bump_end` | end of the current chunk |
| `@__axiom_chunk` | head of the active-chunk list |
| `@__axiom_free` | head of the reclaimed-chunk free list |
| `@__axiom_high` | dirty watermark for the current chunk — a **conservative upper bound** on how far into it memory has ever been handed out |

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

**MM-ALLOC-5 (H).** `mmap` returns chunks in **no particular address
order**. No rule in this document may assume that a later chunk has a
higher address; `MM-ALLOC-13` depends on this being stated.

**MM-ALLOC-5a (H).** The dirty watermark is **conservative in the safe
direction**: two paths set it to the chunk's *end* even though most of
that range was never handed out — installing a chunk recycled off the
free list (which is dirty to its last byte), and a reset that crosses
chunks. The consequence is that `MM-ALLOC-6` may scrub bytes that were
already zero, never that it skips bytes that were not.

**MM-ALLOC-6 (H).** **Allocation answers zeroed memory. Always.** This
is a promise the standard library spends — `Map` and `Intern` read an
all-zero state array as "every slot empty", `strAlloc` reserves a byte
for a NUL terminator and never writes one — and it is delivered by
scrubbing at hand-out, below the high-water mark, rather than by
inheriting the kernel's zeroes. It held for free until a reset first
handed the same bytes out twice, at which point `strAlloc 3` produced a
string whose `cstrLen` measured 17.

**MM-ALLOC-7 (H).** Allocation failure exits the process with status 70.
There is no recoverable out-of-memory condition and no way for a program
to observe one.

**MM-ALLOC-8 (P, and three documents are wrong about it).** The
allocator **SHALL** be replaceable by a program that defines
`axiom_alloc`, which then assumes `MM-ALLOC-6`'s zeroing and
`MM-ALLOC-3`'s alignment obligations, and in which the arena primitives
of §3.3 **SHALL** be refused with a diagnostic, since they move the
position of an allocator that is no longer there.

*Today: none of that is true.* `emitAllocator` runs unconditionally, so
a program defining `axiom_alloc` emits **two** definitions of the
symbol; `check` reports `OK`, and the build dies in the native
toolchain:

```
$ axiom check aa.ax
OK
$ axiom build --input aa.ax --output aa
opt: aa.ll:242:12: error: invalid redefinition of function 'axiom_alloc'
```

There is no diagnostic for the arena primitives either — no code, no
check. `stdlib/Mem.ax:21`, `docs/reference.md` and
`docs/self-hosting.md` each describe this seam as working. It does not,
and a conforming implementation **MUST** either build it (emit the
runtime allocator only when no declaration named `axiom_alloc` is in
scope, and specify the required signature `Int -> Int` returning
16-byte-aligned zeroed memory, with failure behaviour) or delete the
claim from all three documents.

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
| a `match`'s result | a one-word cell, the idiom the emitter uses instead of a phi |
| a mixed-representation tag read | a one-word cell (`emitCondTagRead`) |
| `__axiom_arena_mark` | a three-word cell |
| `handle` on a declared effect | a two-word evidence record `{handler, previous}`; the form performs `Alloc` |

**MM-ALLOC-9a (H).** An evidence record is never freed, so entering a
`handle` inside a loop costs 16 bytes per entry, retained until the
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

**MM-ALLOC-16b (H, program obligation).** An **evidence record is an
ordinary arena object** (`MM-ALLOC-9a`) with no protection from
reclamation. A program **MUST NOT** reset past a mark taken before a
`handle` whose extent is still live: the reset reclaims the evidence
record the slot still points at, and the next operation dispatches
through it. This is the sharpest instance of `MM-ALLOC-16`, because the
memory in question is one the program never named.

**MM-ALLOC-16a (H, program obligation).** Marks **MUST** be reset in
nesting order, innermost first. Resetting an inner mark after its outer
mark has already been reset is **undefined**: the unwind loop's guard
stops the list walk when the marked chunk is no longer on the active
list, but the saved bump/end/chunk triple is still restored, so
allocation resumes at a position that no longer describes a live chunk.
The implementation does not trap, and a conforming implementation
**SHOULD**.

The measured shape of a correct use — the "managed" variant of
`scripts/measure-memory-baseline.sh` — is: mark once before the loop;
each iteration computes the next value, copies it *up*, resets to the
mark, and copies *down* from the up-copy, whose bytes sit above the
restored pointer and survive by `MM-ALLOC-14`. Flat at ~1.4 MiB from 80
through 20,000 generations, against ~16 KiB per generation forever for
the same loop unbracketed.

### 3.4 The inferred model

This section is the specification of the model
[v1-roadmap.md §4.1](v1-roadmap.md) describes and the implementation
does not yet have. Every rule is **P**.

**MM-ALLOC-17 (P).** Each function activation **SHALL** have an implicit
arena. A value allocated during the activation and not escaping it
**SHALL** be reclaimed when the activation returns, by restoring the
watermark — O(1) per activation, with no per-object bookkeeping.

*Today:* nothing is reclaimed at return. Peak memory is proportional to
total allocation.

**MM-ALLOC-18 (P).** A value that **escapes** — returned, stored into a
longer-lived structure, or captured by an escaping closure — **SHALL**
be allocated in the caller's arena instead. This is Tofte–Talpin region
inference with the annotations removed, which is why `region` was
deleted from the surface syntax rather than kept: an annotation the
compiler can derive is an annotation that will eventually be wrong.

*Today:* there is **no escape analysis of any kind** in the compiler.

**MM-ALLOC-19 (P).** A **self tail call SHALL reset its activation's
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

**MM-ALLOC-20 (P).** Before any of `MM-ALLOC-17`–`MM-ALLOC-19` can be
implemented, **the implementation MUST be able to tell a pointer from an
integer**. It cannot today, for two independent reasons, and both are
prerequisites rather than details:

1. **No runtime discrimination.** A word carries no tag (`MM-VAL-2`) and
   a heap block no header (`MM-VAL-6`), so a runtime scan cannot
   identify roots or trace fields.
2. **No static discrimination.** `String` and `Int` are *unified by
   fiat* in `tyCompat` (`typecheck.ax:180`) — a deliberate compatibility
   rule that makes `Int` the universal heap-handle type. Every `Vec`,
   `Map`, `Intern` and `Str` handle is an `Int` to the checker. An
   escape analysis over today's types would therefore have to treat
   every `Int` as possibly-a-pointer, which is the same as treating
   nothing as one.

A conforming implementation of §3.4 **MUST** first introduce a
type-level distinction between a heap handle and an integer, or a
per-type shape map the emitter records for each block it allocates.
This rule exists because a compiler-inserted copy has already been
tried without it once — the `ArenaCompact` instruction, removed rather
than finished, which misidentified a `Vec` header as a constructor
cell, wrote past the end of its chunk, and could not see `Str` or `Vec`
at all (`self-hosting.md`).

**MM-ALLOC-21 (P).** Mutation and arenas interact, and
[v1-roadmap.md §4.1](v1-roadmap.md) does not account for it because it
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

---

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

**MM-MUT-1a (H, defective).** `set` on a binding a lambda merely
captured, and `set` on a function parameter, both pass `axiom check` and
fail in codegen with `AX4002 set target is not a mut binding`, whose own
note reads *"this is a compiler bug: the check that should have refused
this program did not run"*. A conforming implementation **MUST** refuse
both in the checker.

**MM-MUT-2 (H).** `(set e.f v)` stores into a heap field **in place**,
and the write is visible through **every** alias of `e`. It performs the
`Mut` effect, precisely because it is visible where a local's mutation
is not. The form evaluates to `0`, and its static type is `I64` — which
does **not** stop it being the value of a function returning `Int`:
`(fn (bump p) (set p.x 1))` declared `(-> P Int)` checks `OK`.

```scheme
(let ((p (P 1 2)) (q p))
  { (set p.x 99) (printlnInt q.x) })   ; prints 99
```

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

**MM-LIFE-1 (H).** The lifetime of every heap value is **the process**,
unless a program reclaims explicitly with §3.3. There is no `free`, no
destructor, no reference count, and no collector.

**MM-LIFE-2a (P) — the chosen strategy: reference counting.**
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
became visible to the checker. Inference over the tree has since brought
that to **1,431**, by annotating **604 declarations across 25 files**.

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
[v1-roadmap.md §4.1](v1-roadmap.md) gives for not needing cycle
collection — "Axiom's data is immutable and inductive, so cycles are not
constructible" — is **false as written**. Two independent routes,
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

This costs nothing today — `MM-LIFE-1` reclaims nothing, so an
unreachable cycle is no worse than an unreachable tree. It is recorded
here because it is a **precondition on every future reclamation
strategy**: a collector for Axiom must handle cycles, and a
reference-counting scheme (ARC) is therefore **not** a sound choice for
this language without a cycle collector beside it.

**MM-LIFE-4 (H).** What a program may assume about a value's lifetime,
stated positively:

1. A value is valid from the moment its constructor returns until the
   process exits, **or**
2. until a `__axiom_arena_reset` whose mark preceded its allocation,
   after which reading it is undefined (`MM-ALLOC-16`).

There is no third case. In particular, no value's lifetime is tied to a
lexical scope, a function activation, or a variable going out of scope.

**MM-LIFE-5 (P).** Under §3.4 a third case is added: a value's lifetime
is its arena's. `MM-LIFE-4` **SHALL** then read "until its arena is
reclaimed", and the compiler **SHALL** guarantee that no reachable
reference outlives it — which is the whole content of `MM-ALLOC-18`
and `MM-ALLOC-21`.

**MM-LIFE-6 (H, program obligation).** A `strSlice` result keeps its
parent's byte buffer live and points into its middle. A program that
resets an arena containing the parent invalidates every slice of it,
and nothing says so.

**MM-LIFE-7 (P).** **Linear types.** `(linear T)` and `(consume e)`
parse today and enforce nothing: a linear value may be used twice or
zero times, consumed twice, or never, and no memory is reclaimed at any
point.

"Parsed only" understates one half and overstates the other, and both
matter to anyone building on it:

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
   value's storage is reclaimed there.
3. A linear value's arena is its owner's arena, which is what makes
   `MM-ALLOC-19`'s discharge B available: a linear loop parameter is
   provably dead at the tail call, so no copy is needed.

*Today:* all three are unimplemented, and `;@axiom:owned(arena=frame)`
is an accepted tag with no meaning.

---

## 6. Parallelism

**MM-PAR-1 (H).** Axiom has **no language-level concurrency**: no
threads, no tasks, no async, no scheduler, and no atomics. Nothing in
this section is a compiler feature.

**MM-PAR-2 (H).** The unit of parallelism is the **process**, provided
by `stdlib/Job.ax` over `sysSpawn`/`sysWaitPid`. This is forced rather
than chosen: on macOS a freestanding binary cannot create OS threads —
thread creation needs `bsdthread_register`, and Mach-O has no local-exec
TLS, so `__thread` lowers to `tlv_get_addr` — both of which live in
libSystem, and the language has no construct that can name an external
symbol (`MM-FFI-1`).

**MM-PAR-3 (H).** **Memory safety across processes is by construction,
not by discipline.** *Every* process-wide mutable global — the five
allocator words of `MM-ALLOC-2`, the two argument words `@__axiom_argc`
and `@__axiom_argv`, and one evidence slot per declared effect — is
private after `fork` and fresh after `exec`.

> [v1-roadmap.md §4.4](v1-roadmap.md) counts "all seven" as the five
> allocator words plus the evidence slots. Measured, the seven are the
> five plus argc/argv; evidence slots are additional, and a program with
> no declared effects has exactly seven globals and no slots. The
> conclusion is unaffected — it is *all* of them, whatever the count. The allocator therefore
needs no atomics, no lock and no thread-local storage, and the effect
slots inherit correctly for free. This is why `Job` needed no compiler
change at all.

**MM-PAR-4 (H, with a stated escape).** **Nothing the language or the
standard library provides shares mutable memory between processes.**
Values cross a process boundary as bytes, through a file descriptor or
the filesystem, and `Job`'s determinism (`MM-PAR-5`) rests on that.

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
`tests/stdlib/302-job.ax` pins ascending output with children whose
completion order is deliberately reversed.

**MM-PAR-6 (P).** Should a future implementation add threads on a
platform that permits them, this specification **SHALL** require: one
arena per thread with no cross-thread reference, values handed to a
thread copied or moved, results moved into the parent's arena at join,
and combination in argument order so that scheduling nondeterminism
stays unobservable. The five allocator globals **MUST** then become
thread-local rather than acquiring a lock, since a shared bump pointer
is the one thing this allocator's design cannot absorb.

---

## 7. Foreign memory

**MM-FFI-1 (R).** **Axiom has no FFI.** `foreign` was removed and is a
reserved word reporting `AX2004`; so are `union` and `region`. The
language has **no way to name an external symbol**, so a program cannot
call into C at all, and generated code links no C library.
`scripts/check-freestanding.sh` gates that it stays that way.

This is not an omission awaiting a section. It is the property that
makes `MM-PAR-3`, `MM-ALLOC-1` and the whole of §3 true, and any FFI
design must be evaluated against what it costs each of them.

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

**MM-FFI-5 (P).** Should an FFI ever be added, this specification
**SHALL** require, at minimum: that foreign memory be a distinct type
from `Int` (which `MM-ALLOC-20` needs anyway), that no arena primitive
apply to it, that a foreign call be an inferred effect like a syscall,
and that `check-freestanding.sh` be replaced by a gate that enumerates
permitted external symbols rather than forbidding all of them.

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
| **I8** | Marks nest, and a mark is never reclaimed by its own reset | `MM-ALLOC-12` | a doubly-reset mark restores a position from freed memory |
| **I9** | Chunk addresses are unordered | `MM-ALLOC-5` | a backward copy across chunks corrupts |
| **I10** | The stack holds no data, only frames and `mut` cells | `MM-ALLOC-11` | dangling values would become possible |
| **I11** | All allocator state is process-private | `MM-PAR-3` | `Job` would need atomics |
| **I12** | Compilation is deterministic and reproducible | `MM-EXEC-13` | `check-reproducible.sh` |
| **I13** | The compiler executes no user code | `MM-EXEC-14` | the threat model |
| **I14** | The heap graph **may** contain cycles | `MM-LIFE-3` | ARC would leak; a future collector must trace |
| **I15** | Nothing is reclaimed except by §3.3 or process exit | `MM-LIFE-1` | — |

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

---

## 9. Conformance summary

Ranges below EXCLUDE any rule listed in another column of the same row —
a range that swallowed a **P** or **R** rule would report the opposite of
that rule's status, which is the failure this table exists to prevent.

| Area | Holds today | Planned | Refused |
|---|---|---|---|
| Execution | EXEC-1…6d, 8…13, 15…17 | — | EXEC-7, EXEC-14 |
| Representation | VAL-1…11, 14…20 | — | VAL-12, VAL-13 |
| Allocation | ALLOC-1…7, 8a…16b | ALLOC-8, ALLOC-17…21 | — |
| Mutation | MUT-1…5 | — | MUT-6 |
| Lifetimes | LIFE-1, 3, 4, 6 | LIFE-5, LIFE-7 | LIFE-2 |
| Parallelism | PAR-1…5 | PAR-6 | — |
| Foreign | FFI-2…4 | FFI-5 | FFI-1 |

`MM-VAL-21` appears in no column: it is neither held, planned nor
refused, but **defective** — see §9.0.

### 9.0 Defects this specification records

Each is a place where the implementation does something a reader of the
existing documentation would not predict. They are listed together
because the list, not any single entry, is the argument for gating this
document.

| Rule | Defect |
|---|---|
| `MM-ALLOC-8` | the `axiom_alloc` override seam does not exist; `check` says `OK` and `opt` refuses a duplicate symbol. Three documents describe it as working |
| `MM-ALLOC-8b` | `(__alloc 0)` returns an unadvanced bump pointer — address 0 before any chunk exists |
| `MM-VAL-3c` | `I8`…`U128` have no width; incompatible with `Int`; no unsigned operations exist |
| `MM-VAL-4b` | `Double`/`F32`/`F64` emit **integer** arithmetic on double bit patterns, silently |
| `MM-VAL-4c` | `(!= NaN NaN)` is `false`; `Fmt.fmtFloat` cannot render inf or NaN |
| `MM-VAL-3b` | `INT_MIN / -1` and shifts ≥ 64 are undefined and answer differently per `--opt` |
| `MM-VAL-9a` | field access on a `data` value is unguarded; on a mixed type it dereferences an immediate and segfaults |
| `MM-VAL-9b` | an all-literal `match` is not exhaustiveness-checked and answers 0 on no match |
| `MM-VAL-21` | `alloc` types as `*mut T`, which is unspellable, evaluates to 0, and still reports `#effects=Alloc` |
| `MM-MUT-1a` | `set` on a captured binding or a parameter reaches codegen as `AX4002`, whose own note says a check that should have run did not |
| `MM-EXEC-9a` | effect inference is an under-approximation in five measured ways, including across trait dispatch |
| `MM-EXEC-15a` | a reference to `main` emits an undefined register; `check` says `OK` and `opt` refuses |
| `MM-LIFE-7` | `consume` and `alloc` win as expression heads, so a function of either name is definable but uncallable |

### 9.1 What is gated, and what is only written down

`check-doc-drift.sh` exists because nine claims in the normative
documents were measurably false on 2026-08-10. This section is the
equivalent honesty for this one.

| Pinned by a gate | Rules |
|---|---|
| `tests/stdlib/165-arena-keep.ax` | ALLOC-14, ALLOC-15 (overlap over 500 rounds, chunk crossing, a 2 MiB oversize block, zeroing) |
| `tests/stdlib/160-arena.ax` | ALLOC-12, ALLOC-13 (waterline, 64-byte contiguity, reuse, nesting, chunk crossing, zero-on-reuse) |
| `tests/stdlib/110-tail-loop-alloc.ax` | that a self tail call does **not** reclaim what its iteration allocated — the negative of ALLOC-19 |
| `tests/stdlib/040-mem.ax` | the `Mem` primitives over ALLOC-3, ALLOC-6 |
| `tests/stdlib/220-while-mut.ax` | MUT-1 across 1,000,000 iterations |
| `tests/stdlib/035-string-equality.ax` | VAL-7's content equality, including the Unicode and interior-NUL cases |
| `scripts/measure-memory-baseline.sh --gate` | ALLOC-16's managed contract; the unsound variant must *fail* |
| `scripts/check-freestanding.sh` | ALLOC-1, ALLOC-8c, FFI-1 |
| `scripts/check-cross-targets.sh` | that every target's allocator and syscall lowering assembles at `-O0` and `-O2` |
| `scripts/check-bootstrap.sh` | that the compiler survives compiling itself under this allocator |
| `scripts/check-reproducible.sh` | EXEC-13 |
| `tests/stdlib/302-job.ax` | PAR-5 |
| `tests/selfhost/500-while-mut.ax` | MUT-1 in constant stack |

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

Everything else is pinned by nothing, and the probes quoted inline are
the only evidence. In this repository's terms those rules are
documentation, not specification, until a fixture exists. The
highest-value gaps, in order: `MM-VAL-9`'s 4096 boundary (a silent
wrong-arm bug if it ever moves), `MM-MUT-2`'s visibility through
aliases, `MM-EXEC-6b`'s self-TCO (which a reader of `reference.md` would
attribute to LLVM), and `MM-LIFE-3`'s cycles stated *as* a property.

Two of `MM-EXEC-16`'s three exit statuses are already gated — 71 by
`tests/stdlib/310-effect-unhandled.ax` and 72 by the division fixtures —
so only 70 is unpinned, and it is the one no fixture can reach without
exhausting memory.

**This document is not yet read by `check-doc-drift.sh`.** That gate
scans a fixed list — `README.md`, `docs/reference.md`, `CONTRIBUTING.md`,
`docs/v1-roadmap.md`, `docs/self-hosting.md`, `docs/macros.md` — and a
document outside it drifts exactly as the nine claims it was built to
catch did. Adding `docs/memory-model.md` and `docs/macro-system.md` to
that tuple is a one-line change and **SHOULD** be made in the commit
that lands them; every `tests/` path named here already exists, which is
the gate's rule 4.

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

**Why not reference counting.** ARC is the obvious alternative to a
tracing collector for a language with no runtime type information, and
it is **unsound for Axiom as specified**: `MM-LIFE-3` shows a cycle
built from `stdlib/Vec` alone. Adopting ARC would mean either a cycle
collector beside it — which needs `MM-ALLOC-20`'s discrimination anyway,
so nothing is saved — or a language change that makes cycles
unconstructible, which means removing `MM-MUT-2`. That is a real option
and this specification does not foreclose it; it just names the price.

**Why arenas, and why inferred.** The measured shape of every program
this compiler is written to compile — a pass, a request, an expansion —
is a loop whose activation never returns. Per-activation arenas cost one
watermark and no per-object bookkeeping, which is the right price for a
process that exits in milliseconds. They are inferred rather than
written because `region` was a surface annotation for exactly this and
was deleted: an annotation the compiler can derive is one that will
eventually disagree with the compiler, silently.

**Why explicit primitives exist anyway.** `MM-ALLOC-12`–`MM-ALLOC-16`
are what a programmer uses until §3.4 lands, and they are also the
machinery §3.4 needs. Building the automation on primitives that are
already gated is the difference between a plan and a schedule.

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

The contract of `MM-ALLOC-16`, written the way a program must write it
until `MM-ALLOC-19` is implemented. This is the "managed" variant the
memory baseline gates.

This is the "managed" variant `scripts/measure-memory-baseline.sh`
gates, verbatim in shape: mark once, then per iteration **copy up,
reset, copy down**.

```scheme
(:: copyBoard (-> Int Int))
(fn (copyBoard src)
  (let ((dst (vecWithCapacity 576)) (mut i 0))
    {
      (while (< i 576)
        { (vecPush dst (vecGet src i)) (set i (+ i 1)) })
      dst
    }))

(:: advance (-> Int Int Int))
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
without the bracket, at ~16 KiB per generation, forever:

| generations | unmanaged peak RSS | managed |
|---|---|---|
| 10 | 1.5 MB | ~1.4 MB |
| 80 | 2.6 MB | ~1.4 MB |
| 500 | 9.3 MB | ~1.4 MB |
| 2000 | 33.3 MB | ~1.4 MB |

The unit is **MB, not MiB**: the script reports max RSS in kibibytes and
these are that figure divided by 1000, which is what
`measure-memory-baseline.sh` prints. The gate's own ceiling is stated in
KiB (4096) and is unaffected.

One board — about 10 KiB — is live at every count. The unmanaged column
is the allocator never reclaiming; **peak memory tracks total
allocation, not reachable data**, and that is the whole reason the
memory model is the hinge of the roadmap rather than one item on a list.
(The pre-`B3` numbers, still quoted in places: 10 → 5.2 MiB, 80 → 31.8
MiB, 2000 → 744 MiB.)

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
(struct Cfg (verbose : Int))

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

Under `MM-LIFE-7`, discharge B of `MM-ALLOC-19` replaces the copy in
§11.1 with a proof:

```scheme
(:: advance (-> (linear Board) Int (linear Board)))
(fn (advance board n)
  (if (== n 0)
      board
      (advance (step (consume board)) (- n 1))))   ; old board provably dead
```

`consume` is the drop point; the tail call resets the arena with no
copy, because nothing can still refer to what it reclaims.

Today that shape **compiles** — `axiom check` reports `OK` — and behaves
exactly as if `linear` and `consume` were not written. So does its
negation: a linear value used twice, consumed twice, or not used at all
is accepted too.

```scheme
(:: dup (-> (linear Int) Int))
(fn (dup x) (+ (cast Int (consume (consume x))) (cast Int x)))   ; OK
(:: drop (-> (linear Int) Int))
(fn (drop x) 0)                                                  ; OK
```

That is `MM-LIFE-7`'s point, and it is why the syntax existing is not
evidence that the discipline does. The only thing `linear` buys today is
the nominal barrier: `Linear Int` will not pass where `Int` is expected.

---

## 12. Where this leaves the roadmap

Corrections this specification makes to the normative documents, each
measured. They are listed because a plan built on a false premise costs
more than a missing feature.

**To [v1-roadmap.md §4.1](v1-roadmap.md):**

1. **"Cycles are not constructible" is false** (`MM-LIFE-3`). Two
   routes, one of which uses only `stdlib/Vec`. This makes ARC unsound
   for Axiom without a cycle collector, and it is a requirement on every
   future reclamation strategy.
2. **"Axiom's data is immutable" is false** for `struct` fields
   (`MM-MUT-2`), which adds the old-to-young obligation `MM-ALLOC-21` to
   the escape-promotion design — a write barrier the sketch does not
   mention because it assumed immutability.
3. **Chunk stranding is fixed.** The roadmap lists it among the
   automation slice's prerequisites; the chunk list and free list of
   `MM-ALLOC-13` discharge it. The remaining prerequisites are
   `MM-ALLOC-20`'s pointer discrimination and a compiler-inserted copy
   that survives it.

**To [v1-roadmap.md §4.4](v1-roadmap.md):** the "seven process-wide
mutable globals" are the five allocator words plus argc/argv, not the
five plus the evidence slots (`MM-PAR-3`). The safety conclusion is
unaffected.

**To [reference.md](reference.md):**

4. **"Stage1 does not parse `effect`/`handle` yet"** is stale: both are
   parsed, checked and emitted, with evidence globals and a trap
   (`MM-EXEC-10`).
5. **Self-tail-call optimisation is attributed to LLVM.** It is in
   Axiom's own codegen, at every optimisation level (`MM-EXEC-6b`).
6. **The `axiom_alloc` replacement seam is described as working** in
   `reference.md`, `self-hosting.md` and `stdlib/Mem.ax`. It emits a
   duplicate symbol (`MM-ALLOC-8`).
7. **The arena primitives are described as a compile error** in a
   program defining `axiom_alloc`. No such check exists
   (`MM-ALLOC-8`).

**To [self-hosting.md](self-hosting.md) / `stdlib/Mem.ax`:** the reason
given for writing the `Mem` byte loops as `while` — "stage1 emits no
tail-call optimisation at all" — no longer holds (`MM-EXEC-6d`). The
spelling is still correct; the justification needs replacing with
`MM-EXEC-6c`, which is the one that still bites.
