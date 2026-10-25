# The Axiom language reference

Use this page for syntax and language rules. Start with the [first
program](#hello-axiom), then follow the chapters you need. Library
recipes live in the [standard-library reference](stdlib.md); exact
signatures live in the [generated API](stdlib-api.md).

For installation and editor setup, start at [Read Axiom's docs](README.md).

## Contents

- [First program](#hello-axiom), [syntax](#syntax-basics), [literals](#literals) and [names](#identifiers-and-keywords)
- [Functions](#functions), [operators](#operators), [bindings](#let-bindings) and [control flow](#control-flow)
- [Types](#types), [aliases](#type-aliases), [data](#algebraic-data-types), [matching](#pattern-matching) and [structs](#structs)
- [Capabilities](#capability-records), [effects](#effects), [modules](#modules-and-imports), [packages](#packages) and [macros](#macros)
- [Formatting](#printing-and-formatting), [memory](#memory), [inline assembly](#inline-assembly), [concurrency](#concurrency) and [Rust](#calling-rust)
- [Library](#standard-library), [TCP](#talk-over-tcp-with-net), [metadata](#axtag-metadata), [commands](#cli-commands), [tests](#testing) and [targets](#cross-compilation)

## Hello, Axiom

```scheme
(import IO)

(:: main ())
;@axiom:effect(io)
(fn (main)
  (println "Hello, Axiom!"))
```

Save this as `hello.ax` and run `axiom run hello.ax`. It prints
`Hello, Axiom!`. `axiom build hello.ax -o hello` creates a native executable.

`import` brings in a module, `::` declares a type, and `fn` defines a
function. `main` is declared `()`, the unit type: it runs for what it
does, and the program exits 0 when it finishes. The `effect(io)` tag
declares its I/O; the compiler checks that declaration. Braces evaluate
expressions in order and answer the last one.

### Choose the exit status

Declare `(:: main Int)` when the program decides its own exit status,
such as a test runner that exits 1 on a failure. `main`'s answer is the
status:

```scheme
(:: main Int)
(fn (main)
  (if (> (+ 2 2) 4)
    1
    0))
```

### Fallible main

`main` may return `(Result Int Error)` or `(Result () Error)` instead.
Import `Err`: `(Ok n)` exits with `n` and `(Ok ())` exits 0; `(Err e)`
prints `axiom: ` followed by `errorText e` and exits 70. A `main` that
answers any other type is AX3135, since a process exits with a number. These are `Err::Result`, `Err::Error` and Err's constructors;
local declarations with those names keep their own meanings. Use `?` to propagate failures (below). See [error handling](stdlib.md#err-and-fallible).

Tested by `tests/stdlib/490-main-result-ok.ax` and `tests/stdlib/493-main-result-unit.ax`.

### Propagate an error with `?`

`e?` answers the `Ok` payload of the `Result` `e`. When `e` is an
`Err`, the function you are in answers that `Err`, and nothing after
the `?` runs:

```scheme
(import IO)
(import Err)

(:: halveTwice (-> Int (Result Int Error)))
(fn (halveTwice n)
  {
    (let a (divChecked n 2)?)
    (let b (divChecked a 2)?)
    (Ok b)
  })

(:: main (Result Int Error))
;@axiom:effect(io)
(fn (main)
  {
    (let v (halveTwice 40)?)
    {
      (println "{v}")
      (Ok 0)
    }
  })
```

```text
10
```

Use `?` in a function's tail, in a branch, in a `let` body, in a loop,
or in anything evaluated on the way there: an argument, a `let`'s
value, an `if` test, a `match` scrutinee or a block statement.
Arguments before the `?` run first, as written. A `?` inside a lambda
answers the lambda. A `?` inside a `region` propagates when the
`Result`'s payload and error are both scalars; a reference error is
`AX3059`, because the region would reclaim it.

The compiler moves the rest of the expression into the `Ok` arm of a
`match` on `e`. A branch, a `let` body or a loop is rewritten so it
answers a `Result`: `Err` skips the rest, and the `Ok` payload is the
value that form would have had.

In a function that answers a `Result`, the operand is a `Result` and
the error passes through as it is. In a function that answers an
`Option`, the operand is an `Option`: `None` skips the rest. Change an
error's type with `mapErr`, or turn an `Option` into a `Result` with
`okOr`, before the `?`.

Tested by `tests/stdlib/847-propagate.ax`.

## Syntax basics

Calls and declarations use parentheses: `(add 2 3)`. The first item
is the function or form; the rest are its arguments. Spaces and newlines
separate tokens. Indentation carries no meaning.

```scheme
; A line comment.
#| A block comment; #| nested comments |# also work. |#
(+ 1 (* 2 3))
```

A body with several expressions evaluates them in order and answers
the last. Use braces where several expressions must occupy one
expression position, as in an `if` branch.

### Doc comments

A `;;` line documents the declaration below it. A `;;!` line at the
top of a file documents the module. Both are Markdown. A plain `;`
line is a note for whoever maintains the code, and tools leave it out.

```scheme
;;! Counters for the examples.
(import IO)

;; Add one to `n`.
;;
;; A second paragraph, with `code` and *emphasis* as in any Markdown.
; A note about the implementation, which hover and the reference skip.
(:: bump (-> Int Int))
(fn (bump n)
  (+ n 1))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let v (bump 1))
    (println "{v}")
  })
```

Write the doc comment above the `::` signature when there is one, and
put AXTAGs between the signature and the `fn`. Hover in your editor
shows the doc comment, the [standard library reference](stdlib-api.md)
prints its first paragraph, and `axiom doc` renders the whole of it.

## Literals

| Value | Spelling |
|---|---|
| integer | `42`, `-7`, `1_000_000` |
| floating point | `3.5`, `1000000.0` |
| Boolean | `true`, `false` |
| character | `'A'`, `'é'`, `'\n'` |
| string | `"hello"`, `"line one\nline two"` |

Numbers are decimal; source literals have no hexadecimal or exponent form.
Integer literals are `Int`, from `-9223372036854775808` through
`9223372036854775807`, inclusive. Out-of-range digits are refused before
code generation; separators do not change the bound.

Tested by `tests/selfhost/1016-integer-literal-boundaries.ax`.

Escapes include `\n`, `\r`, `\t`, `\0`, `\\`, `\"` and `\'`.
Strings may span source lines. A string literal is a `String` value;
`Str` reads its bytes and `Utf8` reads code points.

String equality compares contents. Use `strCmp` for ordering. A string and an integer
have different types even though both occupy a machine word.

See [strings and collections](stdlib.md#strings-and-collections).

## Identifiers and keywords

Names are case-sensitive. Public modules use PascalCase, functions
usually use camelCase, and data constructors start with a capital.
Operators such as `+` are callable names.

A keyword is recognised at the head of a form. Elsewhere ordinary names
such as `region` and `for` can be bound. `#` cannot appear in a source
identifier; it is reserved for compiler-generated names.

The core forms are `fn`, `lambda`, `let`, `if`, `while`, `for`, `match`,
`data`, `struct`, `type`, `subtype`, `effect`, `handle`, `region`,
`parallel`, `macro`, `import`, `pub` and `extern`.

## Functions

```scheme
(import IO)

(:: add (-> Int Int Int))
(fn (add x y)
  (+ x y))

(:: main ())
;@axiom:effect(io)
(fn (main)
  (println (add 2 3)))
```

A signature `(-> A B C)` takes `A`, then `B`, and returns `C`. A
function taking no parameters has its result type as its signature.
Write signatures for public functions and callback interfaces.

A bare `fn` name can be a value when the function takes one parameter.
That value uses an immutable static descriptor and allocates no memory.
A lambda allocates a closure record for its code pointer and captures.
Tested by `tests/stdlib/966-function-value-reclaim.ax`.

### Lambdas

A lambda is a function value. It can capture values in its enclosing scope.

```scheme
(import IO)

(:: apply (-> (-> Int Int) Int Int))
(fn (apply f x)
  (f x))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let offset 100)
    {
      (println (apply (lambda (x) (+ x offset)) 5))
      ()
    }
  })
```

This prints `105`. Function parameters and record fields may hold
arrows such as `(-> Int Int)`. A lambda is always spelled `lambda`:
`fn` declares a named function at the top level, and `(fn (x) ...)`
inside an expression is refused with `AX2004`.

### Partial application

A lambda can be applied to fewer arguments and return another lambda.
A top-level function needs all its arguments. Put `_` in a call to
build a lambda for the missing arguments, from left to right:

```scheme
(import IO)

(:: sub (-> Int Int Int))
(fn (sub x y)
  (- x y))

(:: main ())
;@axiom:effect(io)
(fn (main)
  ; (lambda (y) (sub 50 y))
  ; (lambda (x) (sub x 8))
  {
    (let subFrom50 (sub 50 _))
    (let minus8 (sub _ 8))
    {
      (println (subFrom50 8))
      (println (minus8 50))
      ()
    }
  })
```

This prints `42` twice. A bare `_` elsewhere in an expression is
undefined; in a pattern it is a wildcard.

### Pipe values through calls

```scheme
(import IO)

(:: main ())
;@axiom:effect(io)
(fn (main)
  (println (|> 5 (+ 1) (* 3) (- 100 _))))
```

This prints `82`. Each stage receives the preceding result as its first
argument. One direct `_` argument places that value elsewhere, as in
`(- 100 _)`. A bare function name is a unary stage.

The input and each intermediate result are evaluated once, from left to
right. A pipeline uses ordinary calls, so their types, effects and region
checks apply. It requires at least one stage and refuses multiple direct
holes in a stage.

Tested by `tests/stdlib/945-pipelines.ax` and
`tests/diagnostics/1430-pipeline-boundaries.ax`.

## Operators

All operators are prefix. Parentheses decide grouping.

| Operation | Operators |
|---|---|
| arithmetic | `+`, `-`, `*`, `/`, `%`; unary `-` negates |
| comparison | `==`, `!=`, `<`, `>`, `<=`, `>=` |
| Boolean | `&&`, `||`, `!` |
| bits | `&`, `|`, `^`, `<<`, `>>` |

`&&` and `||` short-circuit. `Int` arithmetic uses signed 64-bit
words. Addition, subtraction and multiplication wrap; division by zero,
`intMin / -1`, and shifts outside 0..63 trap. Use `Err`'s checked
arithmetic when failure should be a `Result`.

Numeric conversions are always explicit. Numeric types never widen or
narrow implicitly, including in calls, returns, assignments and ADT
payloads. An expected type does not convert a literal: `1` is `Int`,
whereas `1.0` is `Float`.

Float arithmetic uses two `Float` operands. `(as 1 Float)` answers
`1.0`, so `(+ (as 1 Float) 2.0)` answers `3.0`. `(as 3.75 Int)`
truncates towards zero and answers `3`. Float-to-Int conversion saturates
at the integer bounds; a NaN answers zero. Integer-to-Float conversion
rounds to the nearest representable value, with ties to even.

Use `Float.floatFromIntExact` or `Float.floatToIntExact` when a conversion
must preserve the numeric value. Both answer a `Result` and refuse loss
with `floatConversionFailed`. The first refuses integers binary64 would
round; the second refuses fractions, non-finite values and values outside
the signed 64-bit range. Both signed zeros convert to `0`.

```scheme
(import Float)
(import IO)

(:: main ())
;@axiom:effect(io)
(fn (main)
  (match (floatFromIntExact 9007199254740993)
    ((Ok _) (println "exact"))
    ((Err _) (println "rounding refused"))))
```

```text
rounding refused
```

Tested by `tests/stdlib/947-exact-numeric-conversions.ax`.

Use `Float.floatToBits` and `Float.floatFromBits` to reinterpret a
binary64 encoding. `String` equality reads contents; ordering uses
`strCmp`.

An `(Option Int)` cannot stand in for `(Option Float)`. Convert the payload
and construct a new `Option` with the required type.

Tested by `tests/diagnostics/1410-explicit-numeric-boundaries.ax` and
`tests/stdlib/942-explicit-numeric-conversions.ax`.

## Let bindings

```scheme
(import IO)

(:: compute (-> Int Int))
(fn (compute n)
  {
    (let x (+ n 1))
    (let y (* x 2))
    (+ x y)
  })

(:: main ())
;@axiom:effect(io)
(fn (main)
  (println (compute 4)))
```

Declare local values directly inside a `{ ... }` block. Bindings are
sequential: `y` can read `x` above. A later binding can shadow an earlier
name. Each name stays in scope through the rest of its block, and the
block answers its last expression.

### Mutable bindings

Declare a mutable binding with `mut`, then change it with `set`:

```scheme
(import IO)

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let mut count 0)
    (set count (+ count 1))
    (set count (+ count 1))
    (println count)
    ()
  })
```

This prints `2`. Assignment returns the assigned value. A closure may
capture an immutable binding; mutable captures have additional
restrictions described in [memory](#memory).

## Control flow

<a id="type-system"></a>

### if

`if` has a condition, a true branch and a false branch. Conditions are
`Bool`; branches must agree in type. Additional condition/branch pairs
form a chain, followed by the final default branch.

```scheme
(import IO)

(:: abs (-> Int Int))
(fn (abs n)
  (if (< n 0)
    (- 0 n)
    n))

(:: classify (-> Int String))
(fn (classify n)
  (if (< n 0)
    "negative"
    (== n 0)
    "zero"
    "positive"))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (println (abs -7))
    (println (classify -3))
    (println (classify 0))
    (println (classify 12))
  })
```

Leave out the else when the branch is there for what it does. The `if`
then answers `()`, the [unit value](#the-unit-type), and the branch's
own value is dropped:

```scheme
(import IO)
(import Vec)

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let seen vecNew)
    {
      (for n in 0..10
        (if (== (% n 3) 0)
          (vecPush seen n)))
      (if (> (vecLen seen) 3)
        (println "more than three"))
      (println (vecLen seen))
    }
  })
```

```text
more than three
4
```

A `()` branch does the same for an `if` with an else, and a `()` arm
for a `match`: the form answers `()` and the other branches' values
are dropped. Reading that `()` where a value is wanted is a type error,
`expected Int, found ()`. Tested by `tests/stdlib/890-unit-and-if.ax`
and `tests/diagnostics/1302-unit-value-used.ax`.

An `if` or `match` whose value nobody reads, a statement in a block or
a loop body, answers `()` whatever its branches answer, so branches
that are there for what they do need not agree:

```scheme
(import IO)

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let mut hits 0)
    (let mut seen false)
    {
      (for n in 0..5
        (if (== (% n 2) 0)
          (set hits (+ hits 1))
          (set seen true)))
      (println "{hits} {seen}")
    }
  })
```

```text
3 true
```

Where the value is read, a `let`'s value or a function's tail, the
branches must agree as before. Tested by
`tests/stdlib/892-dropped-branches.ax` and
`tests/diagnostics/1304-branches-read.ax`.

### if let

Unwrap an `Option` without writing a whole `match`, as Rust's
`if let` does. `(if (let (Some n) o) then else)` runs `then` with `n`
bound to the value inside `o`, and `else` when `o` is `None`:

```scheme
(import IO)

(:: describe (-> (Option Int) ()))
;@axiom:effect(io)
(fn (describe o)
  (if (let (Some n) o)
    (println "got {n}")
    (println "nothing")))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (describe (Some 4))
    (describe None)
  })
```

```text
got 4
nothing
```

A `let` test can stand at any test position of a chain, beside ordinary
`Bool` tests. Without an else, an `if let` answers `()` as any `if`
does:

```scheme
(import IO)

(:: firstOf (-> (Option Int) (Option Int) Int))
(fn (firstOf a b)
  (if (let (Some n) a)
      n
    (let (Some m) b)
      m
    0))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (println (firstOf None (Some 5)))
    (println (firstOf None None))
    (if (let (Some n) (Some 7))
      (println "seven is {n}"))
  })
```

```text
5
0
seven is 7
```

The pattern is anything a `match` arm accepts, so `(Ok v)` unwraps a
`Result` the same way, and nested patterns and literals work too. Its
names are visible only in the branch it chooses. `(if (let (Some n) o) a b)` means `(match o ((Some n) a) (_ b))`,
so the same checks apply to it. A pattern that always matches, a
lowercase name or `_`, is refused, because its else could never run.
Bind the value with `(let x value)` in a block instead.

Tested by `tests/stdlib/993-if-let.ax` and
`tests/diagnostics/1496-if-let-scope.ax`.

### while loops

`while` repeats its body while its `Bool` condition is true. There is
no `break` or `continue`; put the stopping condition in the guard.
A constant `true` guard describes a loop that does not return.

### for loops

Count with `(for i in lo..hi body)`; `hi` is excluded. Add `by step`
for another stride, including a negative one. A literal zero stride is refused.
Walk a `Vec` with `(for x in values body)` or get indices with
`(for (x i) in values body)`. Evaluate the sequence once before walking it.

For strings and maps, use their accessors to walk bytes or key/value
vectors. A `for` body is for effects; the form answers 0.

Tested by `tests/stdlib/466-for-loop.ax`.

## Types

### Primitive types

| Type | Meaning |
|---|---|
| `Int` | signed 64-bit integer |
| `Int8`, `Int16`, `Int32` | signed 8-, 16- and 32-bit integers |
| `UInt8`, `UInt16`, `UInt32`, `UInt64` | unsigned 8-, 16-, 32- and 64-bit integers |
| `Float` | IEEE 754 binary64 |
| `Bool` | `true` or `false` |
| `Char` | Unicode code point |
| `String` | byte string |
| `Foreign` | externally owned pointer; ARC does not follow it |
| `Handle` | counted owner with an external destructor |
| `()` | the unit type, whose one value is `()` |

### Fixed-width integers

```scheme
(import IO)

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let byte (as 255 UInt8))
    {
      (println (as (+ byte (as 1 UInt8)) Int))
      (println (as byte Int))
    }
  })
```

```text
0
255
```

Each integer type has its own precision and signedness. Signed values use
two's complement. Both operands of an arithmetic, bitwise or comparison
operator must have the same type. Literals remain `Int`; use `as` to
construct a fixed-width value. In-range literal patterns test that value
without converting the scrutinee.

`+`, `-`, `*` and left shifts wrap at the declared width. Right shifts
preserve the sign for signed types and insert zeroes for unsigned types.
Division and remainder trap on zero; signed minimum divided by `-1`
also traps. A negative shift count, or one reaching the type's width, traps.
These rules hold at every optimisation level. `restrict(no-wrap)` rejects
addition, subtraction, multiplication and left shifts. `restrict(no-trap)`
rejects division, remainder and shifts.

Integer `as` conversions keep the low destination bits when narrowing.
Widening sign-extends a signed source and zero-extends an unsigned source.
A same-width conversion preserves the bits. Integer-to-`Float` conversions
round to nearest, with ties to even. `Float`-to-integer conversions truncate
towards zero, saturate at the destination's bounds and map NaN to zero.

Values use one machine word in calls, closures, ADT fields and `Vec`
elements. Ordinary [struct fields](#structs) use their declared integer
width with natural alignment. `sizeof` and `alignof` describe the value,
so both remain 8. `UInt64` covers its full unsigned range;
construct values above the literal range through explicit casts and arithmetic.

Not yet: integer widths beyond 64 bits, wider literal syntax and fixed-width
`extern` signatures. See the [roadmap](roadmap.md).

Tested by `tests/stdlib/948-fixed-width-integers.ax` and
`tests/stdlib/949-fixed-width-alias-callback.ax`.

### The unit type

`()` is a type with one value, also written `()`. A function declared to
answer `()` is a procedure: its body's value is dropped, so it ends
where its work does.

```scheme
(import IO)

(:: report (-> String Int ()))
;@axiom:effect(io)
(fn (report what n)
  (println "{what}: {n}"))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (report "files" 3)
    (report "errors" 0)
  })
```

```text
files: 3
errors: 0
```

An `if` without an else answers `()` too (see [if](#if)). A dropped
value is released as a statement's is, and a dropped `Result` is still
`AX3046`.

Compound types include `(Vec Int)`, `(-> Int String)` and `(* Int)`.
Use `struct` for products and `data` for sums; list and non-empty tuple
types are removed. Fixed-width integers use the names in the table above.
`I8`, `U64`, lowercase Rust spellings and sized float names are refused.

Lowercase type parameters describe polymorphism. For example,
`(-> a a)` returns the same type it takes. The body is checked for
every type that `a` can represent. Arithmetic on an unconstrained `a`,
or returning an `Int` as `a`, is refused. Repeated parameters must agree
within a call; separate calls can choose different types.

Parameters stay rigid inside returned containers, ADTs, records and
callbacks. A function promising `(Option a)` must preserve `a`; returning
`(Some 42)` is refused unless `a` is known to be `Int`. Empty containers
can remain polymorphic.

Tested by `tests/diagnostics/1443-generic-result-rigidity.ax` and
`tests/stdlib/956-generic-result-rigidity.ax`.

A caller's concrete argument witnesses a type parameter. A result-only
parameter requires the explicit low-level contract described in
[diagnostics](diagnostics.md). Tested by
`tests/diagnostics/1423-generic-rigidity.ax`.

`(as value Type)` makes an explicit conversion. Numeric conversions
operate on values; reference conversions preserve the existing lifetime.
A conversion cannot make a raw address valid or extend its lifetime. Raw memory and foreign
operations belong behind an `effect(unsafe)` declaration. Library
functions that take a raw address, such as `sysRandomBytes`, trust it, so
passing one a bad address crashes the program.

A function's result is checked like an argument. A record, closure,
`String` or type variable returned where the signature says `Int` is
`AX3004`, so declare the type the body answers. `(as v Int)` still
turns a reference into a word that holds no share. To compare values
by identity, use `addrOf` (see
[Compare values by identity](#compare-values-by-identity)).

<a id="region-annotations"></a>

### Inferred region origins

The compiler infers reference origins from parameters, allocations and
calls. Use `(region r body)` to choose a reclamation scope; signatures
carry ordinary types. `@r` annotations are removed: delete the
annotation and keep the type, such as `(Vec String)`.
See [Regions](#regions) and the [memory model](memory-model.md).

## Type aliases

```scheme
(type Name String)
(type Items a (Vec a))
(type Mapping a b (-> a b))

(:: apply (-> (Mapping a b) a b))
(fn (apply f x) (f x))
```

`Name` and `String` are interchangeable. `(Items Int)` expands to
`(Vec Int)`, and `(Mapping Int String)` expands to `(-> Int String)`.
An alias gives an existing type another name; it creates no wrapper
or separate identity.

Declare each lowercase parameter once, before the target, and supply exactly
that many arguments at each use. Every variable in the target must be
one of those parameters, and every alias parameter must appear in the
target. Parameters substitute simultaneously, so a
replacement cannot capture another parameter's name.

Aliases work in signatures, fields, nested type arguments and explicit
conversion targets. A target's names resolve in its declaring module.
Targets must name declared types. Direct and indirect recursive aliases
are refused, including unused ones. Use `data` or `struct` for recursive types.

Tested by `tests/stdlib/946-generic-aliases.ax` and
`tests/diagnostics/1422-recursive-alias.ax`.

`data`, `struct` and `subtype` declarations keep their module identity.
`A::Thing` and `B::Thing` are different types even when their layouts
match. Aliases and generic arguments preserve that identity. You can
use a bare name in its declaring module; qualify a name shared by
several imports. Entry-file declarations cannot change an imported module's types.
Qualified constructor patterns select the same declaration as qualified calls.

Tested by `tests/stdlib/954-nominal-identity.ax` and
`tests/diagnostics/1438-nominal-module-boundaries.ax`.

### Range-constrained subtypes

`(subtype Percent is Int range 0..101)` makes a distinct integer type.
The upper bound is excluded. Narrowing with `(as n Percent)`, or at
a declared parameter/result boundary, checks the range at run time and
traps with status 80 on failure. Widening to `Int` needs no check.
Arithmetic does not prove that its result stays within the range. A
subtype is a checked range, not a nominal type: a value of one subtype
passes where another subtype of the same base is declared, with the
target's range checked at run time, and so does a same-named subtype
from another module.

Use an alias for naming, a subtype for a checked integer range, and a
`struct` or `data` wrapper for another nominal type.

Tested by `tests/selfhost/973-type-alias.ax` and `tests/selfhost/134-subtype-checked.ax`.

## Algebraic data types

```scheme
; Optional value
(data Maybe a
  (Nothing)
  (Just a))

; Linked list
(data List a
  (Nil)
  (Cons a (List a)))

; Binary tree
(data Tree a
  (Leaf)
  (Node (Tree a) a (Tree a)))

; Ordering result
(data Ordering
  (LT)
  (EQ)
  (GT))
```

Construct a value with `(Just 42)` or `(Cons 1 (Nil))`. Nullary
constructors can also be written bare. The `(a)` declares a type
parameter. Constructors can refer to the type recursively. Type parameters are
unique, and every variable in a field must be declared on the type.
A type use supplies exactly the declared number of arguments.

A variant may name its fields, for example `(Circle { r : Int })`.
Construction remains positional; named fields support the variant's
structural view.

`Pre` supplies `deriveEq` and `deriveArity`. Formatting already handles
renderable data types; no derive is needed for printing.

## Pattern matching

```scheme
(import IO)

(data List a
  (Nil)
  (Cons a (List a)))

(:: describe (-> (List Int) String))
(fn (describe xs)
  (match xs
    ((Nil) "empty")
    ((Cons _ (Nil)) "one item")
    ((Cons h (Cons h2 _))
      (if (== h h2)
        "starts with a pair"
        "two or more")
    )))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (println (describe (Nil)))
    (println (describe (Cons 7 (Nil))))
    (println (describe (Cons 7 (Cons 7 (Nil)))))
    (println (describe (Cons 1 (Cons 2 (Cons 3 (Nil))))))
  })
```

Arms can match constructors, nested patterns or literals. `_` matches
anything and binds nothing. Every possible constructor must be covered,
or the compiler reports AX3005. Constructor patterns need the right
number of fields, and arm results must agree in type.

`Option` is built in: `Some` holds a value and `None` means absence.
`Err` supplies `Result`, whose constructors are `Ok` and `Err`.

## Structs

Declare typed fields, name them when constructing a value, and read
through a bound name. Field access attaches to a name, so bind a call's
result before using `.field`.

```scheme
(import IO)

(struct Point
  (x : Int)
  (y : Int))

(:: shift (-> Point Int Point))
(fn (shift p n)
  (Point :x (+ p.x n) :y p.y))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let p (shift (Point :x 1 :y 2) 10))
    (let total (+ p.x p.y))
    (println "{p}")
    (println "x + y = {total}")
  })
```

A struct is built by calling its name with labelled fields,
`(Point :x 1 :y 2)`. Supply every field exactly once. Unknown, repeated
and missing fields are refused with `AX3132`. Values evaluate in written
order; storage follows declaration order.

`struct` declares a type. Using it in an expression is refused with
`AX2004`. A mutable field is declared `(mut x : Int)` and assigned with
`(set p.x 9)`. Structs may have type parameters and function fields.
Each function field must carry its complete arrow type.

Fixed-width integer fields occupy 1, 2, 4 or 8 bytes, aligned to that
size, in declaration order. Adjacent narrow fields can share a machine
word. Other fields, including references and type variables, occupy an
aligned 8-byte word. Reading a narrow field restores its signed or
unsigned value; assignment changes just that field's bytes. A nested
struct remains a counted handle. Generic fields keep their declared word
storage even when instantiated with a narrow integer. Their type arguments
remain invariant when you assign a new value.

The allocator rounds payloads to 16 bytes and adds its ownership header.
Packing can reduce allocation size; the result depends on the whole layout.
Use `.field` access for this layout rather than raw word indices.
Tested by `tests/stdlib/959-compact-struct-fields.ax`.

### Make a handle other modules can't forge

`(pub struct File sealed (owner : Handle))` is a counted reference whose
constructor and fields are private to its module. Public operations
control access and closing.

`(struct Ticket word (slot : Int))` is an unallocated single-word
handle. It has one immutable `Int` field, no type parameters, and only
its declaring module can construct it or read the field. Add `shared`
only when its operations are safe across concurrent bindings.

A `word` struct can also pack several fixed-width fields into that
word. `Int8`, `Int16`, `Int32`, `Int64`, `UInt8`, `UInt16`, `UInt32`,
`UInt64`, and a `Link` of width `UInt8`, `UInt16` or `UInt32` are the
fields it accepts. Their widths must total 64 bits or fewer. Building
one packs the fields, and reading one shifts and masks. A vector of
them is a vector of words. The fields are readable from any module
unless you also write `sealed`. There is no `mut` field: replace the
whole value. Tested by `tests/stdlib/999-packed-word.ax`.
`(pub struct Chan sealed shared (owner : Handle))` is a shared counted
handle: a `parallel` form lends it to its bindings, and it can't have a
`mut` field.

### Link the elements of a vector

```scheme
(import IO)
(import Vec)
(import Link)

(struct Node
  (key : Int)
  (mut left : (Link Node UInt16))
  (mut right : (Link Node UInt16)))

(:: insert (-> (Vec Node) (Link Node UInt16) Int ()))
(fn (insert nodes at key)
  {
    (let n (linkGet nodes at))
    (let next
      (if (< key n.key)
        n.left
        n.right))
    (if (linkIsSome next)
      (insert nodes next key)
      {
        (vecPush nodes (Node :key key :left linkNone :right linkNone))
        (let fresh (linkTo nodes (- (vecLen nodes) 1)))
        (if (< key n.key)
          (set n.left fresh)
          (set n.right fresh))
      })
  })

(:: total (-> (Vec Node) (Link Node UInt16) Int))
(fn (total nodes at)
  (if (linkIsSome at)
    {
      (let n (linkGet nodes at))
      (+ n.key (+ (total nodes n.left) (total nodes n.right)))
    }
    0))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let nodes (:: vecNew (Vec Node)))
    (vecPush nodes (Node :key 50 :left linkNone :right linkNone))
    (let root (linkTo nodes 0))
    (insert nodes root 30)
    (insert nodes root 70)
    (insert nodes root 60)
    (let sum (total nodes root))
    (println "sum {sum}")
  })
```

```text
sum 210
```

A link names one element of a vector. `(Link Node UInt16)` is an index
into a `(Vec Node)` that a struct field stores in two bytes, so each
node above spends four bytes on its children where two references
would spend sixteen. `UInt8` and `UInt32` take one and four bytes. Any
other width is `AX3145`.

A link takes no share. The vector owns each element once, so following
a link changes no count and releasing the vector walks no links. Links
may form cycles, such as a ring or links back to a parent, and the
whole structure is still freed with its vector. Use a reference when
one value owns another, and a link when values share one owner.

`Link` has five operations:

- `(linkTo v i)` links to element `i`, and stops with status 77 when
  `v` has none.
- `(linkGet v l)` reads the element, as `vecGet` does.
- `linkNone` links to nothing. A zeroed field holds it.
- `(linkIsSome l)` asks whether a link names an element.
- `(linkIndex l)` answers the index.

Following `linkNone` stops the program with status 77. A link is a
word everywhere but a struct field, and storing one in a field it
doesn't fit stops the program with status 80.

A link carries its element type but not its vector. Following it
checks the index against the vector you pass, so after you remove
elements a kept link can name a different one, as any index can.

Tested by `tests/stdlib/997-links.ax` and
`tests/stdlib/998-link-width-trap.ax`.

## Capability records

```scheme
(import IO)
(import Fmt)

(struct ShowOf (a)
  (render : (-> a String)))

(:: showInt (ShowOf Int))
(fn (showInt)
  (ShowOf :render fmtInt))

(:: showSwitch (ShowOf Bool))
(fn (showSwitch)
  (ShowOf
    :render
      (lambda (b)
        (if b
          "on"
          "off")
      )))

(:: report (-> (ShowOf a) String a Int))
;@axiom:effect(io)
(fn (report s label v)
  {
    (let text (s.render v))
    (println "{label}: {text}")
  })

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (report showInt "retries" 3)
    (report showSwitch "verbose" true)
  })
```

An interface is a parameterised struct of functions. Calling a member,
such as `(s.render value)`, is ordinary function application. Records
replace traits and `impl`.

By default a call through a member may reach any function the program
stores in a field of that name, so its effects are the union of theirs.
One record that prints makes every call through every `render` a
possible print.

### Declare what a member may do

Write `;@axiom:effect(...)` above a function-typed field, as you would
above a function. A call through the field is then charged what the
field declares and nothing else:

```scheme
(import IO)
(import Vec)

(struct Eq (a)
  ;@axiom:effect(alloc)
  (eq : (-> a a Bool)))

(:: member (-> (Eq a) a (Vec a) Bool))
;@axiom:restrict(no-io,strict)
(fn (member e x xs)
  {
    (let mut found false)
    (for y in xs
      (if (e.eq x y)
        (set found true)))
    found
  })

(:: intEq (Eq Int))
(fn (intEq)
  (Eq :eq (lambda (a b) (== a b))))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let xs vecNew)
    (vecPush xs 3)
    (vecPush xs 5)
    (println (member intEq 5 xs))
  })
```

This prints `true`, and `member`'s `no-io` claim is proven however many
records elsewhere in the program print.

`effect(pure)` says the stored functions perform nothing. Otherwise write
one line per effect they may perform: `io`, `spawn`, `block`, `entropy`
or a declared effect. Every declaration but `pure` also admits `Alloc`
and `Mut`, which a function never declares, so `effect(alloc)` alone
admits those two and nothing more. A lambda of two or more parameters allocates the
closure for each argument but the last, so a field like `eq` above
declares `effect(alloc)` at least.

The compiler checks every value where it enters the field, in a
construction or a `set`. A named function is checked by its effect row,
and a lambda by what its body performs, including what it captures.
Copying another field is accepted when that field declares no more:

- A value that performs more than the field declares is refused with
  `AX3142`.
- A value whose effects the compiler can't see is refused with
  `AX3143`: a parameter, a call's result, a container's element, a
  function that calls a function it is given, or a lambda that calls a
  parameter.
- A declaration the compiler can't read, such as one on a field that
  isn't a function, is `AX3144`.

A function written into a record through a cast or a raw store is
outside these checks, like any other claim, and needs `effect(unsafe)`.

`symbols` lists each declared field and what a call through it is
charged, as `#field-effects=eq:Alloc+Mut`. Not yet: a function that
stores its own parameter in a declared field can't pass that
requirement on to its callers ([roadmap](roadmap.md)).

Tested by `tests/stdlib/994-field-effects.ax` and
`tests/diagnostics/1501-field-effect-parameter.ax`.

## Effects

<a id="nolint---quieting-the-editors-hints"></a>

The compiler infers effects through calls. Declare I/O with
`;@axiom:effect(io)`; raw-memory operations require `effect(unsafe)`.
A `pure` claim must match a body that performs no effects. Required
effects omitted from a function's declaration are diagnosed.

| Effect | Meaning |
|---|---|
| `IO` | syscalls and external calls |
| `Alloc` | allocation or arena reset |
| `Mut` | mutation |
| `Div` | possible divergence. Nothing infers it, so an `effect(div)` claim is refused (`AX3110`) |
| `Unsafe` | caller-established low-level obligations |
| `Spawn`, `Block`, `Entropy` | process/task creation, waiting, and randomness |

An unsafe declaration keeps ordinary type checks, restrictions and
checks for other effects. Its author must uphold the raw operation's
memory obligations and expose a safe interface to callers.

A custom effect declares callable operations with signatures:

```scheme
(import IO)

(effect Console
  (log :: (-> String Int)))

(:: greet (-> String Int))
(fn (greet name)
  {
    (log "hello")
    (log name)
  })

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (handle
      (greet "Ada")
      (Console)
      (lambda (s)
        {
          (println "log: {s}")
          0
        }
      ))
    (handle
      (greet "Grace")
      (Console)
      (lambda (s) 0))
  })
```

An operation runs the innermost installed handler. The handler's return
value becomes the operation's result and execution continues. Nested
handlers restore the previous one when their extent ends.

`handle` lists every effect the body performs. A custom effect in the
list is intercepted; a built-in is acknowledged and still reaches the
caller. The handler's own effects also reach the caller, including a handler
stored in a local or supplied as a parameter. A handle listing only
built-in effects does not evaluate its handler expression. An operation
cannot be passed bare as a callback; wrap it in a lambda.

### restrict: what a function never does

Use `;@axiom:restrict(no-alloc,no-io)` to forbid operations transitively.
Other restrictions include `no-unsafe`, `no-block`, `no-spawn`,
`no-recursion` and `no-trap`. Add `strict` to refuse an unresolved claim
instead of receiving a warning. The [restricted profile](restricted-profile.md)
lists the supported restrictions and their limits.

For effect restrictions, the compiler also checks known callbacks at
call sites. The requirement follows parameter aliases, forwarding
functions and captured lambdas. An IO callback passed to a `no-io`
function is refused with `AX3049`.

An unresolved callback keeps its effect row incomplete through local
aliases, captures and mutable bindings. A purity claim draws `AX3037`;
a strict effect restriction is refused with `AX3057`.
Tested by `tests/diagnostics/1482-callback-alias-effects.ax`.

A restriction speaks for what the function and its callees perform. A
value made elsewhere drops at the end of the scope that held it, with
the effects declared where it was made. `openPath` is IO, so a `no-io`
function that stores a new file over an old one closes the old one
without the restriction seeing it. Not yet: a drop's effects count
where the value drops ([roadmap](roadmap.md)).

Tested by `tests/diagnostics/1463-callback-restrictions.ax` and
`tests/stdlib/712-drop-effects-at-creation.ax`.

### Contracts: pre and post

Use a contract to state what a function accepts and what it promises.
A `pre` clause runs before the body. A `post` clause runs after it,
with `result` bound to the returned value:

```scheme
(import IO)

;@axiom:pre((<= lo hi))
;@axiom:post((&& (>= result lo) (<= result hi)))
(:: clamp (-> Int Int Int Int))
(fn (clamp n lo hi)
  (if (< n lo)
    lo
    (if (> n hi)
      hi
      n)))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let n (clamp 18 0 10))
    (println "{n}")
  })
```

```text
10
```

Put clauses above the signature or the definition. You can write more
than one: signature clauses run first, followed by definition clauses,
in their written order. A postcondition can also read the parameters.
It sees their current contents; a mutable container has no saved copy
of its entry state.

Each clause must be one `Bool` expression. Comparisons, indexing and
allocation-free queries such as `strLen` and `vecLen` are useful here.
A clause that allocates, mutates state or performs I/O is `AX3050`.
Malformed expressions and expressions of another type are refused too.
`result` is available only in a postcondition.

A failed clause writes its kind, the function name and the expression
to stderr, followed by a backtrace. For example, `(clamp 7 10 0)` writes:

```text
axiom: precondition failed in `clamp`: (<= lo hi)
```

Failure traps with status 80. Inside a recovery point, that status
returns to the handler; otherwise it ends the program. Checks run at
every optimisation level and cannot be disabled. See
[recovery points](error-model.md#5-recovery).

Contracts check values at run time. A subtype expresses a value range
in a type; `restrict` checks what a function's implementation does;
`effect` declares its effects. A contract adds a condition at the
function boundary. It does not prove a caller's arguments valid at
compile time. A precondition preserves the self-recursive tail-call
rewrite; a postcondition must observe the result and prevents it.

Hover and signature help show the clauses alongside the signature.
Completion inside a clause offers the parameters, plus `result` in a
postcondition. `axiom doc` and the generated library reference include
contracts on public functions.

Run [the contracts example](../examples/contracts/contracts.ax) to see
both kinds of clause on a complete program.

Tested by `scripts/check-contracts.sh` and `tests/lsp/drive.py`.

### isr: an interrupt entry point

`isr` checks a no-argument handler for allocation, recursion and waiting.
On `baremetal-aarch64`, `isr(irq)` binds the interrupt handler and
`isr(fault)` supplies a fault policy. See the [embedded guide](embedded-guide.md)
for signatures, startup and interrupt assumptions.

<a id="nolint-quiet-the-editors-hints"></a>
### nolint: quiet hints and warnings

`;@axiom:nolint(...)` is Axiom's `#[allow(...)]`. While you prototype,
it keeps the editor's hints and the compiler's warnings out of your
way, one declaration or one file at a time. It never quiets an error.

Name what to quiet: a hint (`lint-dead-branch`, `lint-bool-if`,
`lint-unused-let`, `lint-axql`), a warning by its code (`AX3037`), or a group
(`hints`, `warnings`, `all`). The tag goes above either half of a
declaration:

```scheme
(struct Box
  (f : (-> Int Int)))

;@axiom:nolint(AX3037)
(:: call (-> Box Int))
;@axiom:effect(pure)
(fn (call b)
  (b.f 1))

;@axiom:nolint(lint-dead-branch, lint-unused-let)
(:: sketch (-> Int Int))
(fn (sketch n)
  {
    (let later n)
    (if true
      n
      0)
  })

(:: box (-> (-> Int Int) Box))
(fn (box f)
  (Box :f f))

(:: main Int)
(fn (main)
  (+ (call (box (lambda (x) x))) (sketch 2)))
```

The factory stores a parameter whose effects are unknown there.
`call` keeps its unverifiable purity claim without the AX3037 warning,
and `sketch` draws no hints.

A tag above an `import` covers the whole file, like Rust's `#![allow]`
at the top of a module:

```scheme fragment
;@axiom:nolint(all)
(import IO)
```

`axiom check`, `build` and `run` honour the warning half, so the
terminal and the editor agree. A name nothing answers to, such as
`nolint(lint-unused-lte)`, draws the editor hint `lint-unknown-nolint`
at the tag and quiets nothing. Your editor offers a *Suppress* code
action on every hint, which writes the tag for you.

Effect-inference facts and metadata are described in
[symbol tags](diagnostics.md#read-symbol-tags) and [diagnostics](diagnostics.md).
Tested by `tests/diagnostics/1257-nolint-warning.ax` and
`tests/lsp/105-lint-nolint-names.ax`.

## Modules and imports

Imports form the module header, before every signature, function and
other declaration. An import cannot appear inside an expression.

An imported module exports names marked `pub`. Import all public names
with `(import Vec)`, selected names with `(import Vec (vecNew vecPush))`,
or qualify access as `Vec::vecNew`. If two imported modules export the
same bare name, qualify it or select the import you need.

A dotted module name maps to directories: `Crypto.Random` maps to
`Crypto/Random`. Search roots are the entry directory, manifest
modules and crates, `AXIOM_PATH`, command-line crates, then the standard
library. For each target suffix, roots are searched in that order:
`.<os>-<arch>.ax`, then `.<os>.ax`, then `.ax`.

`AXIOM_PATH` names module roots and `AXIOM_STDLIB` selects the library
root. Otherwise the compiler finds the library beside its executable.
The working directory supplies no implicit compiler or library root.

Private names remain inaccessible through transitive imports. See
[compiler inspection](compiler-guide.md) for search and linking details.

The standard library keeps its raw memory layer in `Internal.Raw` and
`Internal.RawVec`. Only the library's own modules may import them or
name what they define, so your program reaches memory through typed
interfaces such as `Vec`, `Str` and `Map`:

```scheme refused
(import Internal.Raw)   ; AX5002: internal to the standard library
```

When a program does need raw memory, write that access in your own
function with the primitives, such as `__load64`, under
`;@axiom:effect(unsafe)`. The function is then a trusted encapsulation
you vouch for, and `axiom symbols` lists it as `#unsafe=trusted`. A file
of the same name in your project is your own module, and the rule
doesn't touch it. Tested by `tests/diagnostics/1470-internal-import.ax`.

## Packages

Start a project with `axiom new app`, then run `axiom build` or
`axiom run` inside it. The `axiom.pkg` manifest supplies the entry file,
optimisation default and dependencies.

```text
main Main.ax
opt 1
depend vendor/lib
crate vendor/native
```

A dependency may be a directory of modules or a git URL. Pin a Git
URL to an exact commit with a separate line:

```text
depend https://example.com/team/library.git
pin https://example.com/team/library.git 0123456789abcdef0123456789abcdef01234567
```

Use a full lowercase commit hash: 40 hexadecimal digits, or 64 for a
SHA-256 repository. Each pin must name a declared Git dependency.
`axiom fetch` clones it into `.axiom/deps/` and checks out that commit.
Changing a pin creates a separate checkout and preserves the previous
one, including local edits. Keep dependency checkouts unmodified when
you need reproducible source contents.

After fetching, `check`, `build` and `run` use the local checkout without
calling Git or accessing the network. They check its recorded origin
and detached commit, and refuse a checkout that no longer matches the
pin. Unpinned URLs use the branch selected by their first fetch.

Tested by `tests/tools/package-pins.py`.

Not yet: packages cannot resolve a registry or version ranges; see the
[roadmap](roadmap.md). Crates provide generated Axiom wrappers and native
archives; see [calling Rust](ffi.md).

## Macros

```scheme
(import IO)

(macro (clamp lo hi x) (if (< x lo)
  lo
  (> x hi)
  hi
  x))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (println (clamp 0 10 42))  ; becomes (if (< 42 0) 0 (> 42 10) 10 42)
    (println (clamp 0 10 -3))
  })
```

```text
10
0
```

`(macro (name argument ...) template)` substitutes syntax before type
checking. Arguments used twice are evaluated twice; bind a temporary
when the operation should happen once. Template-local binders are
renamed hygienically.

The rule form, `(macro name ((name pattern ...) template) ...)`, tries
its rules in order and uses the first whose pattern matches. A rule's
template is declarations or one expression, and where you invoke the
macro picks which:

```scheme
(import IO)

(macro total ((total x) x)
  ((total x rest ...) (+ x (total rest ...))))

(:: main ())
;@axiom:effect(io)
(fn (main)
  (println (total 1 2 3 4)))
```

```text
10
```

A repeated pattern binder constrains equal syntax:

```scheme
(macro same
  ((same x x) 1)
  ((same x y) 0))

(fn (main)
  (same (+ 1 2) (+ 1 2)))
; 1
```

Identifiers compare by binding, literals by value, and compound forms
by their structure. Literal identifiers declared with `(literals ...)`
respect local shadowing and retain their original module when forwarded.
These comparisons never evaluate an argument.

Macros can generate declarations and inspect syntactic type
information. They do not execute arbitrary source code during
compilation. `Pre` supplies two derivers, `deriveEq` and
`deriveArity`. Read the
[macro specification](macro-system.md) for declaration templates,
`syntax` queries, pattern matching and expansion limits.

## Source formatting

```bash
axiom fmt Main.ax Helpers.ax
axiom fmt --check Main.ax
axiom fmt --diff Main.ax
axiom fmt --emit stdout Main.ax
cat Main.ax | axiom fmt -
```

`fmt` gives your source one canonical layout, with two-space indentation
and a 100-column target. Calls stay together when they fit; longer calls
pack complete arguments into rows. Control flow and multiline arguments
keep their structural breaks.

In an `if` chain, each branch sits two columns deeper than its test.
The final else returns to the tests' indent. Two- and three-operand
forms share one branch indent.

Headers, signatures, types, imports and positional patterns share the
width budget. Comments stay beside their source elements. Long strings
and other indivisible tokens remain whole.

Every batch input is prepared and verified before writing starts. A
formatting refusal leaves all batch files untouched. Unchanged files keep
their modification time. `--check` and `--diff` write no source files and
exit 1 when formatting would change them. `--diff` prints a unified diff.
Use `-` to read stdin, or `--emit stdout` to format one file into a pipe.

The editor uses the same formatter. Formatting verifies comment
preservation and a fixed point before returning its output.

Tested by `tests/fmt/workflow.py` and
`tests/stdlib/958-formatter-packed-calls.ax`.

## Printing and formatting

```scheme
(import IO)

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let name "world")
    (let n 42)
    (let pi 3.14159)
    {
      (println "Hello {name}")
      (println "n={n} pi={pi:.2}")
      (println n)
      {
        (let row (format "{name:<10}{n:>5}"))
        (println "[{row}]")
      }
    }
  })
```

`println` and `eprintln` format a value and add a newline. `format`
returns a string. `writeStr` writes existing bytes without formatting
or a newline.

A hole names a binding, as in `{name}`. Bind an expression with `let`
before using it in a hole. Renderable types are integers, floats,
Booleans, characters, strings, and data/struct values built from them.
A function, unresolved type variable or unsupported field draws AX3025.

| Specifier | Use |
|---|---|
| `x`, `X` | lower/upper hexadecimal |
| `.2` | two fractional digits |
| `<10`, `>10`, `^10` | left, right, centre padding |
| `04` | zero padding |

Double braces write literal braces. For custom rendering, pass a
function in a capability record or call it before formatting.

## Terminals

<a id="targets"></a>

`termRaw` puts a terminal into raw mode and answers a `TermGuard`.
Releasing the guard puts the terminal back as it was, and `termRestore`
does it early. `termSize` and `isTerminal` ask about a `File` such as
`stdin`. `Tui.Keys` decodes key events, `Tui.Edit` implements a pure
line editor, and `Tui.Term` connects it to terminal I/O. The
[library API](stdlib-api.md#tuiterm) lists the exact operations.

Windows console and pipe reads share a buffer with `Poller`, so a
readiness check preserves bytes left by an earlier read. Changing
console mode or closing a file stops its pending reader first.
Open owned Windows console files with `oRdwr` when using `termRaw`;
read-only handles return `EACCES` when the mode change is attempted.
`pollerAddSignals` accepts `sigInt` for Ctrl-C and `sigBreak` for
Ctrl-Break on Windows. Other signal bits answer `Err` 78. The process
keeps its control mask after a poller closes; competing pollers consume
each pending control once between them. Console close, logoff and
shutdown retain Windows' termination behaviour.

Tested by `tests/platform/windows-console.ax` and
`tests/platform/windows-controls.ax`.

## Memory

Axiom calls its memory model **RECAP**: region-scoped, effect-checked,
counted, arena-hybrid, predictable reclamation. It combines checked
lexical regions, automatic reference counting and arena resets. The
executable includes its allocator and ownership support; there is no
tracing collector or `--gc` mode.

### What RECAP guarantees

| Part | Meaning |
|---|---|
| Region-scoped | A lexical `region` resets its allocation extent when its body ends. The compiler checks visible reference escapes. |
| Effect-checked | Calls carry inferred `Alloc`, `Mut` and `Unsafe` effects. Allocation, arena resets and raw-memory operations participate in effect checks and restrictions. |
| Counted | The compiler inserts ownership bookkeeping. Releasing the final share releases owned fields and makes eligible small blocks reusable. |
| Arena-hybrid | Region resets reclaim their extent regardless of counts, including cycles within that extent. Counting also operates inside regions where releases remain necessary. |
| Predictable reclamation | Ownership events and explicit reset boundaries determine reclamation. This gives defined reclamation points, without promising constant-time destruction or reset. |

Reference counting does not collect unreachable cycles. A structure
built with [links](#link-the-elements-of-a-vector) can hold cycles and
is still freed with its vector. Larger dead blocks wait for an arena
reset. Automatic reclamation is incomplete:
some mutable slots and closure paths retain shares. Registered resource
owners receive cleanup during region reset and recovery; raw foreign
resources remain your responsibility. The
[memory contract](memory-model.md#5-lifetimes-and-reclamation) states the
ownership events and remaining limits.

Effects describe operations and calls, rather than every generated
instruction. Automatic retains and releases are runtime work; they do
not introduce a separate drop effect. An `effect(unsafe)` declaration
records a trusted boundary whose author must uphold its obligations.
It does not prove that a raw address is valid.

At a memory boundary, the compiler explains the obligation it can check.
A conversion that forges a reference reports its source type and points
to the value being trusted. The terminal and editor share the same
guidance: prefer typed construction, or establish the target's layout,
validity and backing lifetime. An unsafe tag keeps ordinary type,
effect and restriction checks in place.

Hover over `as`, or run `axiom explain as`, for ownership guidance.
A word obtained from a reference holds no share; keep its owner alive
while using the word. Use `addrOf` for identity comparisons and hashing.
`axiom symbols FILE --diagnostic-format=ai` reports `#erasures=n` on
functions that turn references into words. These conversions do not
promote a value out of a region.

`Alloc` covers allocation and arena reset; `Mut` covers visible heap
updates. Both are inferred through calls, and their claims are optional
and checked. Generated retains and releases have no separate `Reclaim`
effect. Region escape checks concern value origins and scope, rather
than an `Escape` effect.

Axiom uses region and escape analysis rather than Rust's borrow checker.
It also has a MIR representation and compiler-generated runtime helpers.
Use `axiom symbols FILE --mir --diagnostic-format=ai` to inspect region
facts. RECAP does not imply the absence of lifetime analysis or runtime
costs, nor a worst-case execution-time bound. See
[assurance](assurance.md) for the evidence needed by restricted builds.

RECAP names Axiom's integration of these mechanisms. Combining regions
and reference counting has [prior art](https://www2.eecs.berkeley.edu/Pubs/TechRpts/2000/5340.html).
Rust also supports [reference-counted values with cycle obligations](https://doc.rust-lang.org/stable/book/ch15-06-reference-cycles.html).
The name does not claim a unique reclamation algorithm.

Tested by `tests/stdlib/479-region-reclaim.ax` and
`tests/stdlib/557-cycle-backlog.ax`.

Memory-boundary guidance is tested by `tests/lsp/memory-boundaries.py`.

### Regions
```scheme
(import IO)
(import Str)

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let mut i 0)
    (let mut total 0)
    {
      (while (< i 1000)
        {
          (region req
            {
              (let line (format "request {i}"))
              (set total (+ total (strLen line)))
            })
          (set i (+ i 1))
        })
      (println "built {total} bytes")
    }
  })
```

A `region` reclaims allocations made inside it when its body ends.
Its result and stores into outer bindings must be scalar. References
that outlive a region are refused where the compiler can see their
escape. Raw addresses and remaining low-level escape gaps are explicit
Unsafe obligations; a region is not a general lifetime proof.

Nested regions reset innermost first and cannot reuse an open name.
A region performs `Alloc`. Its name identifies the lexical scope in
diagnostics and macro expansion; it is not a type parameter. Escape
diagnostics point to the reclaiming scope and suggest moving the
allocation or call outside it, or computing a scalar inside it. The
language server shows the same remedies and related locations.

A `Vec` or `Map` owns what you put in it. When its last reference goes,
it releases every string, vector, record or `File` it holds, so a
vector built and dropped in a loop holds memory flat. A container that
is also given plain words, such as the `Int`s of a heterogeneous
record, makes no claim on what it holds. Files, sockets and foreign
owners close at their last share; explicit close retires them early.
Cycles and destruction costs are covered by the
[memory contract](memory-model.md).

Recovery points catch runtime traps in an isolated extent. They cannot
undo external I/O, but they do run the cleanup of the owners the extent
made, so its files close and its locks are released. A region's end
does the same for an owner it leaked. See
[error recovery](error-model.md).

### Compare values by identity

`addrOf` from `Mem` answers where a value lives as an `Addr`. Two
values are the same value exactly when their addresses are equal:

```scheme
(import IO)
(import Mem)

(data Box
  (Bx String))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let a (Bx "one"))
    (let b (Bx "one"))
    (let c a)
    {
      (println
        (if (addrEq (addrOf a) (addrOf c))
          "a is c"
          "a is not c"))
      (println
        (if (addrEq (addrOf a) (addrOf b))
          "a is b"
          "a is not b"))
    }
  })
```

```text
a is c
a is not b
```

`addrHash` hashes an `Addr` for a table keyed by identity. An `Addr`
takes no share and keeps nothing alive, and nothing turns it back into
the value. Compare two only while both values are live, because a
freed block's address is reused.

Tested by `tests/stdlib/810-addr-identity.ax`.

### Inline assembly

`asm` runs instructions the language has no form for: a cycle counter,
a barrier, a system register, a call in a calling convention of your
own. A function that uses it says `;@axiom:effect(unsafe)`, because the
compiler can't see what the instructions do. Callers of that function
inherit nothing.

<!-- doc-gate:run -->
```scheme
(import IO)

(:: add (-> Int Int Int))
;@axiom:effect(unsafe)
(fn (add x y)
  (asm
    (aarch64 "add {r}, {a}, {b}" (out r) (in a x) (in b y))
    (x86_64 "leaq ({a},{b}), {r}" (out r) (in a x) (in b y))))

(:: main ())
;@axiom:effect(io)
(fn (main)
  (println (fmtInt (add 40 2))))
```

```text
42
```

An `asm` form holds one arm per architecture, `aarch64` or `x86_64`,
each at most once. The compiler emits only the arm for the target it
builds for, so one function can carry both. Building for a target with
no arm is refused (`AX4008`) when your program reaches the function.

#### Operands

After its template, an arm lists its operands, and then anything it
clobbers and the options it promises:

| Item | Meaning |
|---|---|
| `(in name value)` | `value`, an `Int`, in a register |
| `(out name)` | a register the instructions write, which the form answers |
| `(lateout name)` | as `out`, but it may share a register with an input |
| `(inout name value)` | starts as `value` and is answered, in one register |
| `(inlateout name value)` | as `inout`, but it may share a register with another input |
| `(const name n)` | an integer the compiler works out, written into the template as text |
| `(sym name f)` | the symbol of `f`, a top-level `fn` or an `extern` item |
| `(clobber "reg" ...)` | registers the instructions write that no operand names |
| `(clobber_abi "C")` | every register a call may overwrite under the platform's C convention |
| `(options word ...)` | what the instructions promise (see [Options](#options)) |

`in`, `out` and the other register operands can name their register,
as in `(in a "x8" x)`. A `const` is a literal, or `+`, `-` and `*` over
literals.

An arm answers one output at most. Every other output ends with
`into` and the `mut` binding it is stored in, as in
`(out r into rem)`, and the binding must be an `Int` this function can
assign. With no answered output, the form answers 0. Inputs are
evaluated once each, in the order written, before the instructions run.

`out` and `inout` get a register no input uses, so the instructions may
write them before they have read every input. `lateout` and
`inlateout` drop that guarantee to save a register: use them when the
instructions read every input before they write the output.

<!-- doc-gate:run -->
```scheme
(import IO)

; Two outputs: the quotient is the answer, and the remainder is stored
; in `rem`.
(:: divmod (-> Int Int Int))
;@axiom:effect(unsafe)
(fn (divmod n d)
  {
    (let mut rem 0)
    {
      (let q
        (asm
          (aarch64 "udiv {q}, {a}, {b}\nmsub {r}, {q}, {b}, {a}" (out q) (out r into rem) (in a n)
            (in b d))
          (x86_64 "xorl %edx, %edx\ndivq {b}" (inout q "rax" n) (out r "rdx" into rem) (in b d))))
      (+ (* q 100) rem)
    }
  })

; One instruction reads its input before it writes its output, so the
; two may share a register.
(:: bump (-> Int Int))
;@axiom:effect(unsafe)
(fn (bump x)
  (asm
    (aarch64 "add {r}, {a}, #1" (lateout r) (in a x))
    (x86_64 "leaq 1({a}), {r}" (lateout r) (in a x))))

; A number written into the template.
(:: times8 (-> Int Int))
;@axiom:effect(unsafe)
(fn (times8 x)
  (asm
    (aarch64 "lsl {r}, {a}, #{n}" (out r) (in a x) (const n 3))
    (x86_64 "movq {a}, {r}\nshlq ${n}, {r}" (out r) (in a x) (const n 3))))

(:: triple (-> Int Int))
(fn (triple y)
  (* y 3))

; The instructions call `triple`. `clobber_abi` tells the compiler the
; call may overwrite any register the C convention lets it, so the
; answer names its register.
(:: viaCall (-> Int Int))
;@axiom:effect(unsafe)
(fn (viaCall x)
  (asm
    (aarch64 "mov x0, {a}\nbl {f}" (out r "x0") (in a x) (sym f triple) (clobber_abi "C"))
    (x86_64 "movq {a}, %rdi\ncall {f}" (out r "rax") (in a x) (sym f triple) (clobber_abi "C"))))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (println (fmtInt (divmod 47 5)))
    (println (fmtInt (bump 41)))
    (println (fmtInt (times8 5)))
    (println (fmtInt (viaCall 14)))
  })
```

```text
902
42
40
42
```

#### Templates

The template is a string literal that reaches the assembler as
written. `{name}` stands for an operand's register, a `const`'s value
or a `sym`'s symbol, and `{{` and `}}` are literal braces. `{name:m}`
picks a view of a register: `w` or `x` on AArch64, and `b`, `h`, `w`,
`k` or `q` on x86-64. Separate instructions with `\n`. x86-64 templates
use AT&T syntax unless the arm says `intel_syntax`, and a literal `$`
is written as is.

A template can't define a named label such as `spin:`, because the
optimiser may copy a block: into each caller it inlines, or into each
pass of a loop it unrolls. Each copy would define the label again. Use
a numbered label, `1:`, and branch to it as `1b` (back) or `1f`
(forward).

This program reads a register through its 32-bit view, uses fixed
registers with a scratch register, reads the CPU's counter, puts a
barrier between two reads, and counts down in a loop:

<!-- doc-gate:run -->
```scheme
(import IO)

; The low 32 bits of `x`: one register in and out, written through its
; 32-bit view, which zeroes the top half.
(:: low32 (-> Int Int))
;@axiom:effect(unsafe)
(fn (low32 x)
  (asm
    (aarch64 "mov {v:w}, {v:w}" (inout v x))
    (x86_64 "movl {v:k}, {v:k}" (inout v x))))

; `x + 1` through fixed registers and a scratch register the
; instructions overwrite.
(:: viaRegs (-> Int Int))
;@axiom:effect(unsafe)
(fn (viaRegs x)
  (asm
    (aarch64 "mov x9, {a}\nadd {r}, x9, #1" (out r "x0") (in a "x8" x) (clobber "x9"))
    (x86_64 "movq {a}, %rdx\nleaq 1(%rdx), {r}" (out r "rax") (in a "rcx" x) (clobber "rdx"))))

; The CPU's cycle or tick counter.
(:: cycles Int)
;@axiom:effect(unsafe)
(fn (cycles)
  (asm
    (aarch64 "mrs {t}, cntvct_el0" (out t))
    (x86_64 "rdtsc\nshlq $32, %rdx\norq %rdx, %rax" (out t "rax") (clobber "rdx"))))

; No instructions and no operands: a barrier the compiler moves no
; load, store or call across. It answers 0.
(:: fence Int)
;@axiom:effect(unsafe)
(fn (fence)
  (asm
    (aarch64 "")
    (x86_64 "")))

; Counts `n` down to zero with a branch back to label 1, in a loop the
; optimiser may unroll. It answers 1.
(:: countdown (-> Int Int))
;@axiom:effect(unsafe)
(fn (countdown n)
  (asm
    (aarch64 "mov {r}, {a}\n1: subs {r}, {r}, #1\nb.ne 1b\nadd {r}, {r}, #1" (out r) (in a n))
    (x86_64 "movq {a}, {r}\n1: decq {r}\njnz 1b\nincq {r}" (out r) (in a n))))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (let before cycles)
    (let _ fence)
    (let after cycles)
    (let mut total 0)
    (let mut i 0)
    {
      (println (low32 (+ 4294967296 7)))
      (println (viaRegs 41))
      (println (>= after before))
      (while (< i 3)
        {
          (set total (+ total (countdown 5)))
          (set i (+ i 1))
        })
      (println total)
    }
  })
```

```text
7
42
true
3
```

#### Options

An `(options ...)` list says what the instructions do:

| Option | The instructions |
|---|---|
| `pure` | have no effect but their outputs |
| `nomem` | read and write no memory |
| `readonly` | read memory and write none |
| `preserves_flags` | leave the condition flags as they found them |
| `noreturn` | never finish |
| `nostack` | use no stack, a red zone included |
| `att_syntax` | are in AT&T syntax, the x86-64 default |
| `intel_syntax` | are in Intel syntax, on x86-64 |

The compiler builds on those promises. It may drop a `pure` block
whose outputs nothing reads, or merge two that are alike. It moves
loads and stores across a `nomem` block, and loads across a
`pure readonly` one. It keeps the flags live across `preserves_flags`,
and treats the code after a `noreturn` block as unreachable. Without
`nostack`, the instructions may push to the stack: the compiler aligns
the stack pointer for a call and keeps nothing below it.

A `pure` arm needs an output and `nomem` or `readonly`, and a
`noreturn` arm has no outputs. Options that contradict each other or
the arm are `AX3119`.

<!-- doc-gate:run -->
```scheme
(import IO)
(import Str)

; The answer depends on the input alone.
(:: square (-> Int Int))
;@axiom:effect(unsafe)
(fn (square x)
  (asm
    (aarch64 "mul {r}, {a}, {a}" (out r) (in a x) (options pure nomem nostack))
    (x86_64 "movq {a}, {r}\nimulq {a}, {r}" (out r) (in a x) (options pure nomem nostack))))

; Reads a string's first byte through its address, and writes nothing.
(:: firstByte (-> String Int))
;@axiom:effect(unsafe)
(fn (firstByte s)
  (asm
    (aarch64 "ldrb {r:w}, [{p}]" (out r) (in p (strData s)) (options pure readonly nostack))
    (x86_64 "movzbq ({p}), {r}" (out r) (in p (strData s)) (options pure readonly nostack))))

; A spin-wait hint: no outputs, no memory, flags untouched.
(:: relax Int)
;@axiom:effect(unsafe)
(fn (relax)
  (asm
    (aarch64 "yield" (options nomem nostack preserves_flags))
    (x86_64 "pause" (options nomem nostack preserves_flags))))

; Stops the program at a breakpoint when `x` is negative.
(:: checked (-> Int Int))
;@axiom:effect(unsafe)
(fn (checked x)
  (if (< x 0)
    (asm
      (aarch64 "brk #1" (options noreturn nomem nostack))
      (x86_64 "ud2" (options noreturn nomem nostack)))
    x))

(:: main ())
;@axiom:effect(io)
(fn (main)
  {
    (println (fmtInt (square 7)))
    (println (fmtInt (firstByte "Axiom")))
    (println (fmtInt relax))
    (println (fmtInt (checked 42)))
  })
```

```text
49
65
0
42
```

#### When the assembler rejects a line

`check` doesn't assemble a template, so its instructions meet the
assembler when you build. A line it rejects, or one whose operands the
register allocator can't place, fails the build with `AX3117` at that
line, and the build exits 1. Building a program that calls this
function:

```scheme
(:: next (-> Int Int))
;@axiom:effect(unsafe)
(fn (next x)
  (asm (aarch64 "add {r}, {a}, #1\nfrobnicate {r}" (out r) (in a x))))
```

```text
error[AX3117]: llc rejected this line of an `asm` template: unrecognized instruction mnemonic
 --> calc.ax:4:36
  |
4 |   (asm (aarch64 "add {r}, {a}, #1\nfrobnicate {r}" (out r) (in a x))))
  |                                    ^^^^^^^^^^^^^^
  |
  = note: the assembler read `frobnicate x8`, with the operands in their registers
```

The note shows the instruction as the assembler read it, with each
operand in its register. Tested by `tests/embedded/asm-rejected.ax`.

#### What the compiler checks

The compiler refuses a malformed form where you write it, at the part
that is wrong:

| Mistake | Code |
|---|---|
| an unknown architecture, operand kind or option, a second arm for one architecture, or a template that isn't a string literal | `AX3091` |
| a `{name}` that names no operand, an unbalanced `{` or `}`, or a modifier the architecture has no view for | `AX3091` |
| two operands with one name, an input and an output with one name, two operands or a clobber in one register, or a register the arm can't name | `AX3091` |
| a template that defines a named label | `AX3091` |
| a second answered output, an `into` on an input, or an option given twice | `AX3091` |
| a `const` that isn't worked out from literals, or a `sym` naming a local, an operator or a polymorphic function | `AX3091` |
| an operand the template never names, unless it has a register of its own | `AX3118` |
| options that contradict each other or the arm | `AX3119` |
| an `into` binding that isn't a `mut` `Int` this function can assign | `AX3012`, `AX3004` |
| a reached form with no arm for the target | `AX4008` |
| a template line the assembler rejects, when you build | `AX3117` |

No operand or clobber may name the stack pointer, the frame pointer or
AArch64's `x18`, and `x30` may appear only as a clobber. Operands are
`Int` words in general-purpose registers. Vector registers may be
clobbered.

#### What the compiler does, and what you promise

The compiler keeps every block, in order, as a side effect unless it
says `pure`. Unless an option says otherwise, a block reads and writes
memory and clobbers the condition flags, so no load, store or call
moves across it.

It doesn't check the instructions. Your function promises that they:

- leave the stack pointer and frame pointer as they found them, and,
  with `nostack`, use no stack;
- write no register but the outputs and the clobbers;
- end by falling through, with no branch out, return or exception
  return, unless the arm says `noreturn`;
- keep every promise their options make;
- perform no IO, blocking or trap the function doesn't declare.

Not yet: floating-point, vector and memory operands, labels shared
between blocks, and Rust's `may_unwind` and `raw`; see the
[roadmap](roadmap.md#tools).

The restricted profile refuses `asm` unless `--allow-asm` names the
function (`RP-9`). The full contract is `MM-FFI-9` in the
[memory model](memory-model.md).

Tested by `tests/stdlib/870-inline-asm-operands.ax` and
`tests/diagnostics/1280-inline-asm-forms.ax`.

## Concurrency

<a id="parallel--bindings-that-run-beside-the-caller"></a>

```scheme
(import IO)

(:: slowSum (-> Int Int))
(fn (slowSum n)
  {
    (let mut i 0)
    (let mut acc 0)
    {
      (while (< i n)
        {
          (set acc (+ acc i))
          (set i (+ i 1))
        })
      acc
    }
  })

(:: main ())
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  {
    (let n 1000000)
    (parallel p (
      (a (slowSum n))
      (b (* n 2))
    )
      {
        (println "a = {a}")
        (println "b = {b}")
      })
  })
```

`parallel` starts the bindings and joins them in source order before
running the body. Declare `effect(io)`, `effect(spawn)` and
`effect(block)`. Ordered answers do not order side effects.

The default hosted lowering uses isolated processes. `--threads` selects
threads on Linux and macOS. Windows has no `fork`, so `parallel` runs on
threads there without the flag. Captures remain restricted in both
modes; process boundaries do not transfer general managed pointers.

### What a binding may capture

Bindings may capture immutable scalars, borrowed strings and immutable
`data` graphs, and shared handles such as a `Chan`, `Mutex` or
`CancelToken`. Mutable bindings, ordinary heap structs, resource
owners and closures are refused. A shared handle's module must enforce
synchronisation. Thread arenas and reference counts alone do not make
payload mutation safe.

Each binding answers an `Int`. Use `Chan` for bounded word channels and
`Sync` for shared mutexes. Their timeout, close and owner-death behaviour
is in the [library API](stdlib-api.md#chan).
A channel, mutex or cancellation token is freed when its last owner
lets go, and never while a binding still uses it: a `parallel` form
lends it to its bindings until every one has joined. There is no free
to call, and a hand-written `__thread_spawn` can't capture one.
Tested by `tests/stdlib/803-shared-owner.ax`.

A lock call answers a guard, and the lock is held until the guard's
scope ends, on any path out of it. There is no unlock call:

```scheme fragment
(match (mutexLock mx)
  ((Ok g) (bumpShared cell))
  ((Err e) 0))
```

A trap that a recovery point catches inside the guard's scope releases
the lock too, and poisons the mutex, so later lock calls answer
`syncOwnerDead`. Tested by `tests/stdlib/800-mutex-guard.ax`.

### Run tasks that answer values with `Task`

`taskMap worker count width limit` runs `(-> Int String)` tasks with at
most `width` children and a per-result byte limit. Results are
`(Result String Error)` values in submit order. `TaskOpts` adds deadlines,
cancellation and fail-fast behaviour, and three budgets. `taskWithKeep`
bounds the answer bytes a call holds. `taskWithMemory` caps each task's
memory, so a task that runs away answers `Err` 70 instead of taking the
machine with it. `taskWithStack` sets the stack each task runs on, so a
task that recurses too deep answers `Err` 86. `taskFold` consumes answers with a scalar
accumulator. Its checked `scoped(step)` contract refuses callbacks that
retain an answer or a fresh allocation in captured state. Pass a lambda
directly, a non-nullary function declaration, or a parameter carrying the
same scoped contract.

The pool checks cancellation before every spawn attempt. An attempt
already in progress can race cancellation; once observed, no later attempt
starts. Running tasks get their grace period from that observation before
being killed and reaped. A deadline applies to each task from its own
spawn. Tested by `tests/stdlib/960-task-launch-cancellation.ax`.

Width is clamped to the input count, with a minimum of one for non-empty
inputs. A slab size that exceeds the `Int` range returns `Err` 22 before
mapping the answer slab or starting tasks.

Use `taskMapRanges worker count grain opts` for small jobs that benefit
from sharing a process start. `worker` receives the start and exclusive
end of a contiguous range, at most `grain` items. Each range runs in a
fresh child and returns one result. Options and budgets apply per range.

`taskMapCompute worker count opts` returns `(Result Int Error)` slots.
Its checked `compute(worker)` contract accepts numeric computations with
primitive captures and local accumulators. Each invocation still runs in
a fresh child; successful words cross as eight bytes, counted by `limit`
and `keep`. See [AXTAG metadata](#axtag-metadata) for the checked boundary.

`taskMapWords` returns word results, while `taskMapWordsChecked`
returns a `Result` for each word. `taskRunCommand` runs one argument
vector; `taskRunCommands` runs a bounded command pool. The
[library reference](stdlib.md#task-chan-and-sync) gives the entry points, and the [memory model](memory-model.md) defines publication,
atomic ordering and lifecycle rules.

`Task.Worker.workerMap argv inputs opts` starts a fresh executable per
encoded input and returns bounded byte results in input order. The
endpoint's `main` calls `workerServe handler`; the caller's captured
state never crosses the boundary. `workerOpts` takes a width, input
limit and result limit. It defaults to `NativeStack`; a guarded
`StackBytes` budget is refused on Windows before launch. See
[executable workers](stdlib.md#executable-workers) for examples and
the precise memory and cleanup limits.

Windows command and executable-worker pools require Windows 10 or
later. Not yet: arbitrary captured-closure `Task` calls on Windows;
see the [platform roadmap](roadmap.md#platforms-and-release).

## Calling Rust

`extern` declares symbols supplied by a native library. Calls infer
IO and Unsafe; direct callers vouch with `effect(unsafe)`. Link a crate
with `--crate DIR` or the manifest's `crate` entry.

`#[axiom_export]` and `axiom-bindgen` generate Rust shims and Axiom
wrappers. Generated owners are sealed; use their operations rather
than manufacturing handles. Callbacks borrow their environment for the
call. A borrowing wrapper's comment names the arguments a callback must
leave alone.

Use [the Rust FFI guide](ffi.md) for supported wire types, callbacks,
hosting Axiom with `--emit-staticlib`, linking and panic boundaries.

## Standard library

Use the [standard-library reference](stdlib.md) to choose modules and
copy small recipes, and the [generated API](stdlib-api.md) is the complete signature and effect
listing. Every module is Axiom source; hosted programs reach the kernel
without a C library unless they link foreign code. Windows uses
kernel32 and ws2_32 through its platform layer.

### Talk over TCP with `Net`

`Net` gives you TCP the way Rust's `std::net` does. This program runs a
server and a client in one process: the client sends a name, and the
server answers with a greeting.

```scheme
(import Err)
(import IO)
(import Net)
(import Str)

; The server's side of one connection: read a name, answer a greeting.
(:: serve (-> TcpStream Int))
;@axiom:effect(io)
(fn (serve conn)
  (match (tcpReadLine conn 1024)
    ((Ok (Some name))
      (match (tcpWrite conn (concat "hello, " (concat name "\n")))
        ((Ok _) 0)
        ((Err e) (die (errorText e) 1)))
    )
    ((Ok (None)) 0)
    ((Err e) (die (errorText e) 1))))

; Take the next connection off the queue and serve it.
(:: acceptOne (-> TcpListener Int))
;@axiom:effect(io)
(fn (acceptOne server)
  (match (tcpAccept server)
    ((Ok conn) (serve conn))
    ((Err e) (die (errorText e) 1))))

(:: main ())
;@axiom:effect(io)
(fn (main)
  (match (tcpListen "127.0.0.1:0")
    ((Err e) (die (errorText e) 1))
    ((Ok server)
      (match (andThen (tcpListenerLocalAddr server) tcpConnectAddr)
        ((Err e) (die (errorText e) 1))
        ((Ok client)
          {
            (let _ (tcpWrite client "Ada\n"))
            (let _ (acceptOne server))
            (match (tcpReadLine client 1024)
              ((Ok (Some reply)) (println reply))
              (_ (die "no reply" 1)))
          }
        ))
    )))
```

```text
hello, Ada
```

- Listen and connect with an address as text, as in
  `(tcpListen "0.0.0.0:8080")` or `(tcpConnect "10.0.0.5:22")`. Port 0
  asks the kernel for a free port, and `tcpListenerLocalAddr` says
  which. `tcpListenAddr` and `tcpConnectAddr` take a `SocketAddr` you
  already hold, and `tcpConnectTimeout` gives up after a number of
  milliseconds.
- `(tcpReadLine conn max)` answers one line without its newline, or
  `None` when the peer closes, and refuses a line longer than `max`.
  `tcpReadExact` reads a fixed-size frame. `tcpWrite` writes
  everything, and `tcpWriteSome` writes what fits and says how much.
- Every failure is a `Result`. Match on `(errorKind e)` from `IO` to
  tell them apart: `ConnectionRefused`, `TimedOut`, `WouldBlock`,
  `BrokenPipe` and the rest of Rust's `std::io::ErrorKind`, the same on
  every target.
- Streams block by default. `(tcpSetReadTimeout conn (Some 250))`
  bounds a wait in milliseconds. `tcpSetNonBlocking` and an `IO`
  `Poller` serve many clients from one thread.
- A listener or stream closes when its last share goes.
  `(tcpShutdown conn ShutdownWrite)` half-closes the connection: the
  peer reads end of stream, and you can still read its reply.
- Addresses are numeric. `ipV4`, `ipV6`, `ipParse` and `socketAddrNew`
  build them, and there is no name resolver.

The [standard-library reference](stdlib.md#net) has a complete echo
server, a client with timeouts and a non-blocking server on a
`Poller`. The [generated API](stdlib-api.md#net) lists every
signature.

Tested by `tests/stdlib/841-net-ip.ax` and `tests/stdlib/843-net-stream.ax`.

<details>
<summary>Browse every module</summary>

### Modules at a Glance

Sixty-four modules, all of them Axiom source under `stdlib/`, plus the six
`Sys.Platform.*` target files covered by `Sys`. Only names marked `pub`
are exported.

| Module | Public API |
|---|---|
| `Pre` | [API](stdlib-api.md#pre) |
| `Mem` | [API](stdlib-api.md#mem) |
| `Str` | [API](stdlib-api.md#str) |
| `Utf8` | [API](stdlib-api.md#utf8) |
| `Uuid` | [API](stdlib-api.md#uuid) |
| `Vec` | [API](stdlib-api.md#vec) |
| `Link` | [API](stdlib-api.md#link) |
| `Map` | [API](stdlib-api.md#map) |
| `Fmt` | [API](stdlib-api.md#fmt) |
| `Float` | [API](stdlib-api.md#float) |
| `Err` | [API](stdlib-api.md#err) |
| `Fallible` | [API](stdlib-api.md#fallible) |
| `Intern` | [API](stdlib-api.md#intern) |
| `Sys` | [API](stdlib-api.md#sys) |
| `Path` | [API](stdlib-api.md#path) |
| `IO` | [API](stdlib-api.md#io) |
| `Ffi` | [API](stdlib-api.md#ffi) |
| `Cereal` | [API](stdlib-api.md#cereal) |
| `Rpc` | [API](stdlib-api.md#rpc) |
| `Chan` | [API](stdlib-api.md#chan) |
| `Sync` | [API](stdlib-api.md#sync) |
| `Task` | [API](stdlib-api.md#task) |
| `Task.Worker` | [API](stdlib-api.md#taskworker) |
| `Net` | [API](stdlib-api.md#net) |
| `Chrono` | [API](stdlib-api.md#chrono) |
| `Axqlite` | [API](stdlib-api.md#axqlite) |
| `Axqlite.AxqlMacro` | [API](stdlib-api.md#axqliteaxqlmacro) |
| `Axqlite.Value` | [API](stdlib-api.md#axqlitevalue) |
| `Axqlite.AxqlParse` | [API](stdlib-api.md#axqliteaxqlparse) |
| `Axqlite.AxqlAst` | [API](stdlib-api.md#axqliteaxqlast) |
| `Axqlite.AxqlEval` | [API](stdlib-api.md#axqliteaxqleval) |
| `Axqlite.AxqlSchema` | [API](stdlib-api.md#axqliteaxqlschema) |
| `Axqlite.AxqlExec` | [API](stdlib-api.md#axqliteaxqlexec) |
| `Axqlite.Btree` | [API](stdlib-api.md#axqlitebtree) |
| `Axqlite.Record` | [API](stdlib-api.md#axqliterecord) |
| `Axqlite.Pager` | [API](stdlib-api.md#axqlitepager) |
| `Test` | [API](stdlib-api.md#test) |
| `Agent.Tags` | [API](stdlib-api.md#agenttags) |
| `Tui.Keys` | [API](stdlib-api.md#tuikeys) |
| `Tui.Edit` | [API](stdlib-api.md#tuiedit) |
| `Tui.Term` | [API](stdlib-api.md#tuiterm) |
| `Crypto.Random` | [API](stdlib-api.md#cryptorandom) |
| `Crypto.Secret` | [API](stdlib-api.md#cryptosecret) |
| `Crypto.Bytes` | [API](stdlib-api.md#cryptobytes) |
| `Crypto.Sha2` | [API](stdlib-api.md#cryptosha2) |
| `Crypto.Sha3` | [API](stdlib-api.md#cryptosha3) |
| `Crypto.Blake2b` | [API](stdlib-api.md#cryptoblake2b) |
| `Crypto.Hmac` | [API](stdlib-api.md#cryptohmac) |
| `Crypto.Hkdf` | [API](stdlib-api.md#cryptohkdf) |
| `Crypto.Obfuscate` | [API](stdlib-api.md#cryptoobfuscate) |
| `Crypto.AesGcm` | [API](stdlib-api.md#cryptoaesgcm) |
| `Crypto.ChaCha20Poly1305` | [API](stdlib-api.md#cryptochacha20poly1305) |
| `Crypto.Aead` | [API](stdlib-api.md#cryptoaead) |
| `Crypto.X25519` | [API](stdlib-api.md#cryptox25519) |
| `Crypto.Ed25519` | [API](stdlib-api.md#cryptoed25519) |
| `Crypto.Aes` | [API](stdlib-api.md#cryptoaes) |
| `Crypto.Ghash` | [API](stdlib-api.md#cryptoghash) |
| `Crypto.ChaCha20` | [API](stdlib-api.md#cryptochacha20) |
| `Crypto.Poly1305` | [API](stdlib-api.md#cryptopoly1305) |
| `Crypto.Curve25519` | [API](stdlib-api.md#cryptocurve25519) |
| `Crypto.Field25519` | [API](stdlib-api.md#cryptofield25519) |
| `Crypto.Curve25519Scalar` | [API](stdlib-api.md#cryptocurve25519scalar) |
| `Crypto.Ct` | [API](stdlib-api.md#cryptoct) |
| `Crypto.Errors` | [API](stdlib-api.md#cryptoerrors) |

</details>

## AXTAG metadata

`;@axiom:` comments attach checked claims and tool metadata to
functions and signatures. Effect claims, restrictions, contracts,
interrupt tags and `result(owned)` (a trusted function handing over a
type-variable result, [memory model](memory-model.md) `MM-LIFE-2n`)
affect validation. Descriptive tags remain metadata; they do not
establish a proof by themselves.

A key one slip from a checked key, such as `;@axiom:restirct(no-alloc)`
or `;@axiom:Effect(io)`, is refused with `AX3039`, so a claim never
drops out unnoticed. Give a key of your own a namespace, such as
`;@axiom:my:owner(storage)`, and it is recorded without being checked.
Tested by `tests/diagnostics/1134-axtag-near-miss.ax`.

A scoped callback can read invocation-owned values and return a scalar:

```scheme
(import Str)

(:: withText (-> String (-> String Int) Int))
;@axiom:scoped(step)
(fn (withText text step)
  (step text))

(:: length Int)
(fn (length)
  (withText "hello" (lambda (text) (strLen text))))
```

`scoped(step)` requires a declared callback type with a scalar result.
The compiler checks a lambda as a fresh invocation: its reference
arguments and new allocations cannot be stored in older captured state.
Pass the lambda directly, a non-nullary function declaration, or a
parameter carrying the same tag. Opaque callbacks are `AX3130`; an
escaping store is `AX3060`, with the invocation boundary attached.
Call the tagged function directly with all its declared arguments so
the precondition remains visible.

The tag establishes the callback's retention rule. A callee that resets
raw storage still needs a trusted unsafe implementation: it must supply
valid values, keep them alive through the invocation and reclaim them
only after it returns. Normal type, effect and region checks still apply.
Raw addresses retain their unsafe validity and lifetime obligations.
Tested by `tests/stdlib/953-scoped-task-fold.ax` and
`tests/diagnostics/1440-scoped-callback-escape.ax`.

A compute callback accepts an `Int` and returns an `Int`:

```scheme
(:: applyKernel (-> (-> Int Int) Int Int))
;@axiom:compute(worker)
(fn (applyKernel worker value)
  (worker value))

(:: main Int)
(fn (main)
  {
    (let offset 7)
    (applyKernel (lambda (i) (+ i offset)) 5)
  })
```

`compute(worker)` requires that exact callback type, after expanding
aliases. Pass a lambda directly, a non-nullary function declaration with
a visible body, or the exact parameter carrying the same contract.
Call the tagged function directly with all its declared arguments.
An invalid declaration, opaque callback or erased precondition is
`AX3131`.

The compiler checks the callback and every helper it calls against a
closed numeric operation basis: primitive numeric, Boolean and character
values, arithmetic, comparisons, Boolean operations, explicit numeric
conversions, local bindings, `if`, loops and sequences. Captures must be
canonical primitive values. Local scalar accumulators are allowed and
keep their `Mut` effects. References, handles, allocation, heap or
captured stores, raw loads, runtime observers, foreign calls, assembly
and opaque calls are refused, including through helpers. An empty effect
row alone does not establish this contract.

Normal type and effect checks still apply. Convert fixed-width and
floating-point results to `Int` explicitly. The contract restricts what
the callback can observe and mutate; it does not transfer ownership or
extend a region's lifetime. Tested by
`tests/stdlib/961-task-compute-contract.ax` and
`tests/diagnostics/1445-compute-callback.ax`.

Use `axiom --diagnostic-format=ai symbols file.ax` to inspect accepted
tags and inferred facts. [Symbol tags](diagnostics.md#read-symbol-tags) describes reading
those rows, and [diagnostics](diagnostics.md) documents their format.

## CLI commands

| Command | Use |
|---|---|
| `check FILE` | parse and type-check |
| `run FILE` | build and run, forwarding following arguments |
| `build --input FILE --output BIN` | write an executable |
| `emit-llvm FILE -o FILE.ll` | write LLVM IR |
| `fmt FILE` | format; `--check` reports without writing |
| `test FILE_OR_DIR` | run named tests |
| `new DIR`, `fetch` | create a project; fetch dependencies |
| `symbols FILE` | inspect declarations, tags and calls |
| `explain AX3001`, `explain let`, `explain @restrict`, `explain --list` | explain a diagnostic, a word of the language or an AXTAG key |
| `doc` | render the docs and the library reference, and open them |
| `repl`, `lsp`, `version`, `help` | interactive session, editor server, version and help |

`axiom help COMMAND` is the option reference. The first operand is
always a command, so `axiom file.ax` is refused; write
`axiom emit-llvm file.ax --target TARGET` to emit IR.

### Build and run

`--opt 0..3` sets optimisation. `--threads` selects hosted thread
lowering. `--heap-ceiling BYTES` bounds the arena and refuses threads.
`--obfuscate` obscures literals and internal names in executables;
[obfuscation](obfuscation.md) explains its limits and asset packing.

For memory debugging, pass `--alloc-poison` to `build`, `run`, `test` or
`emit-llvm`. Freed payloads are overwritten when their blocks enter the
reuse lists. New allocations still start zeroed. This helps expose stale
references; it does not check every invalid memory access or poison an
arena reset.

Tested by `scripts/check-poisoned-alloc.sh`.

### Machine-readable output

Use `--diagnostic-format=ai` for AXDL diagnostics and AXSYM symbols.
JSON diagnostics use `--diagnostic-format=json`. `symbols` refuses
JSON with status 2; use AXSYM. Diagnostics go to standard error.

### List a file's symbols

`symbols FILE --calls` includes resolved call edges. Add `--mir --axir`
for inspection records. Native compilation uses the AST backend;
AXIR is not a build input. See [compiler inspection](compiler-guide.md).

### Look up a diagnostic code or a word

`axiom explain AX3001` describes the error and a correction. The
[diagnostic reference](diagnostics.md) documents codes, spans and fixes.

`axiom explain let` describes a keyword, a builtin type, an effect, an
operator or a literal, with the section of this page that covers it,
and `axiom explain @restrict` describes an AXTAG key. Hover in your
editor shows the same entry. An operator that starts with a dash goes
after `--`, as in `axiom explain -- ->`.

### Read the docs offline

`axiom doc` renders this documentation set and one page per standard
library module to HTML, then opens the index in your browser. Add
`--no-open` to print the index's path instead, `--out DIR` to choose
where the pages go, and name a `.ax` file to render your own module
the same way. `axiom doc --missing` lists every public library name
that has no `;;` doc comment yet.

An installed compiler finds `docs/`, `README.md` and `CHANGELOG.md`
beside itself. `CONTRIBUTING.md` and the examples page need a source
checkout, or `AXIOM_DOC` naming one.

Tested by `scripts/check-tools-selfhost.sh`.

## Testing

Import `Test`, then declare no-argument functions whose names start
with `test`. Assertions take a label first:

```scheme
(import Test)

(:: testAddition Int)
;@axiom:effect(io)
(fn (testAddition)
  {
    (assertEq "two plus two" 4 (+ 2 2))
    0
  })
```

Run `axiom test tests.ax`. A directory runs its immediate `.ax` files
in name order; `--filter TEXT` selects names, and `--jobs N` runs up
to N of the directory's files at once in child processes and reports
them in name order. No tests or no matching
tests is a failure. `setup` and `teardown` run around each test.

A failed assertion or trap fails that test and the runner continues.
Use `expect` for a known failing test; a passing expected failure is
reported as XPASS and fails the run.

Tested by `scripts/check-test-runner.sh`.

## The REPL

Run `axiom repl` to evaluate expressions and add definitions. Completed
forms run; incomplete forms continue onto another line. Start your session
with imports, before defining functions or values. `:load` follows the
same rule; use `:reset` to start a new module header.

A declaration is checked as you type it, the way `check` checks the file
your session would be: one the compiler refuses is reported with its
code and not kept. A signature may wait for its definition on a later
line. Redefining a name replaces the earlier declaration.

The prompt, syntax and results use Axiom's lime and amber palette. Errors
stand out in coral, with a code you can look up using `:explain AX3004`.
`:explain let` explains a language form; `:explain @restrict` explains a tag.
Use `:help` for commands, Tab for completion and Ctrl-R to search history.
Piped sessions keep plain output without prompts or colour.

Unit, floating-point and fixed-width integer results keep their checked
types when evaluated. Numeric conversions stay explicit with `as`.

```text
Axiom 0.7.9 - REPL
```

For editor completion, navigation, formatting and fixes, configure
[the language server](lsp.md).

## Cross-compilation

Supported targets: `darwin-aarch64`, `linux-aarch64`. The host is the default.

A target is supported when a CI job executes what the compiler emits there.
`darwin-x86_64`, `freebsd-aarch64`, `freebsd-x86_64`, `linux-x86_64`,
`windows-aarch64` and `windows-x86_64` are source-only: CI builds or
assembles their code, without the whole execution battery. They have
no prebuilt release archive. See [targets](../README.md#targets).

Select a target with `--target=linux-aarch64`. Compilers built for
`windows-x86_64` and `windows-aarch64` run on Windows and build themselves
there. CI runs each on a runner of its own architecture. Linking a
Windows executable needs `lld-link` and `llvm-dlltool`, which makes an
import library for each DLL the program uses. An import library on
`--link-search` is used instead when there is one. A Windows executable
reserves an 8 MB stack. Its runtime probes large stack frames without
a C runtime. Windows static-library emission is refused.

For `baremetal-aarch64`, use the [embedded guide](embedded-guide.md) for
the board, linker layout, static heap and fault policy. Emulator
execution and hardware validation are distinct.

## Optimisation

`--opt` accepts 0 to 3. The default is 1, or the manifest's `opt`.
Level 2 enables LLVM loop vectorisation. The runtime and imported Axiom
modules are emitted together, so optimisation already crosses their
boundaries. Rust crates remain external to that LLVM module.

Tail calls lower to loops where supported; ordinary recursion still
uses stack. Resource bounds include allocation, destruction and call
depth. Use the [restricted profile](restricted-profile.md) for checked
restrictions and explicit unresolved obligations.

## How the compiler works

The lexer and parser build syntax; module resolution and macros prepare
it for checking. Type and effect checks annotate the AST. The backend
emits LLVM IR, LLVM lowers machine code, and the linker writes the
executable. The runtime travels with the result.

The compiler is itself Axiom. A clean checkout bootstraps from the
committed seed and requires a self-hosting fixpoint. See
[compiler inspection](compiler-guide.md) and [contributing](../CONTRIBUTING.md).

## Removed features

Traits and `impl` are replaced by capability records. Use `Vec` for
sequences and `struct`/`data` for products and sums. Printing uses
`format`, `println` and `eprintln`; strings join with `concat`.
`for` replaces `range`, `macro` replaces `emacro`, and
`restrict(no-trap)` replaces `restrict(no-untrapped)`.
`as` replaces `cast`, with the value before its target type:
`(as value Type)`.

Foreign libraries use `extern`; the older `foreign` keyword is reserved.
See [compatibility](compatibility.md) and `compat/BREAKING` for migration
records.

## Tips and patterns

Keep I/O at a boundary, name intermediate values with `let`, and use
`Option` for absence and `Result` for failure. Use `?` to keep result
handling flat. Prefer typed library operations to raw-memory calls.

[Library recipes](stdlib.md) and [complete examples](../examples/README.md)
show these patterns in programs.

## Further reading

[Library recipes](stdlib.md), [exact API](stdlib-api.md),
[editor setup](lsp.md), [Rust FFI](ffi.md),
[current feature status](status.md) and [contributing](../CONTRIBUTING.md).
