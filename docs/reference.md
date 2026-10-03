# The Axiom language reference

Everything you need to write Axiom, from your first program to macros
and memory. Read it front to back to learn the language, or jump to a
chapter when you need an answer.

New to Axiom? Install it with the steps in the [README](../README.md),
then start with [Hello, Axiom](#hello-axiom). To see which features are
finished and which are still growing, read [What's ready
today](status.md).

Every example that declares `main` is a complete program, and CI
compiles each one against the current compiler, so you can copy any of
them and run it.

## Contents

**Getting started**

1. [Hello, Axiom](#hello-axiom)
2. [Syntax basics](#syntax-basics)
3. [Literals](#literals)
4. [Identifiers and keywords](#identifiers-and-keywords)

**The core language**

5. [Functions](#functions)
6. [Operators](#operators)
7. [Let bindings](#let-bindings)
8. [Control flow](#control-flow)
9. [Types](#types)
10. [Type aliases](#type-aliases)
11. [Algebraic data types](#algebraic-data-types)
12. [Pattern matching](#pattern-matching)
13. [Structs](#structs)
14. [Capability records](#capability-records)

**Effects, modules and macros**

15. [Effects](#effects)
16. [Modules and imports](#modules-and-imports)
17. [Packages](#packages)
18. [Macros](#macros)

**Working with the system**

19. [Printing and formatting](#printing-and-formatting)
20. [Terminals](#terminals)
21. [Memory](#memory)
22. [Concurrency](#concurrency)
23. [Calling Rust](#calling-rust)
24. [Standard library](#standard-library)
25. [AXTAG metadata](#axtag-metadata)

**Tools**

26. [CLI commands](#cli-commands)
27. [Testing](#testing)
28. [The REPL](#the-repl)
29. [Cross-compilation](#cross-compilation)
30. [Optimisation](#optimisation)
31. [How the compiler works](#how-the-compiler-works)

**Appendix**

32. [Removed features](#removed-features)
33. [Tips and patterns](#tips-and-patterns)
34. [Further reading](#further-reading)

## Hello, Axiom

Every Axiom program starts at a function called `main`. It returns an
`Int`, the program's exit status, or a `(Result Int Error)`
([Fallible main](#fallible-main)). Here is the smallest program that
prints something:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println "Hello, Axiom!")
    0
  })
```

Save it as `hello.ax` and run it:

```bash
axiom run hello.ax
```

```text
Hello, Axiom!
```

Each line has one job:

- `(import IO)` brings in `println` from the standard library.
- `(:: main Int)` is the type signature: `main` takes nothing and
  returns an `Int`.
- `;@axiom:effect(io)` says that `main` performs I/O. The compiler
  checks it, and rejects a function that performs I/O without saying
  so ([Effects](#effects)).
- `{ ... }` runs its expressions in order and answers the last one.
  Here that's `0`, the exit status.

`axiom build hello.ax -o hello` writes a native executable instead.
There are no headers and no build file. The `IO` module is part of
Axiom's own standard library, which reaches the kernel through raw
syscalls, so this program neither links nor calls a C function. An
`extern` block is the one way to change that
([Calling Rust](#calling-rust), [ffi.md](ffi.md)).

### Fallible main

`main` can also return `(Result Int Error)`. A failure is then
reported the way the runtime reports its own:

```scheme
(import Err)

(:: main (Result Int Error))
(fn (main)
  (Err (mkError 7 "disk full")))
```

Running it writes this to standard error (fd 2) and exits with status
70:

```text
axiom: disk full
```

- `(Ok n)` exits with status `n`.
- `(Err e)` writes `axiom: ` and the error's message to fd 2, then
  exits 70.
- Context added with `withContext` is part of the message. Wrapping
  the error above as `(withContext r "saving records")` prints
  `axiom: disk full while saving records`.

Status 70 sits beside the runtime's own 71 (an unhandled effect) and
72 (division by zero). Exit codes 1–69 stay yours. Only the exact type
`(Result Int Error)` is treated this way, and it needs `Err`'s
`errorText` in scope, which `(import Err)` provides. The contract is
`ERR-REC-4` in [error-model.md](error-model.md).

Tested by `tests/stdlib/490-main-result-ok.ax` and `tests/stdlib/491-main-result-err.ax`.

## Syntax basics

Axiom is written in S-expressions: every compound form is a list in
parentheses. It takes a moment to get used to, and then there's
almost no syntax left to learn.

### Forms

```scheme
(keyword arg1 arg2 ...)
```

The first element says what the form is: a keyword such as `if` or
`let`, or the function to call. The rest are its arguments.
Parentheses make the structure explicit, so there are no precedence
rules to memorise:

```scheme
(+ 1 (* 2 3))   ; 7
```

A literal such as `42` or a name such as `total` is an expression on
its own, with no parentheses. A few other pieces of punctuation come
up often:

- `{ a b c }` is a brace block. It runs its expressions in order and
  answers the last one ([Functions](#functions)).
- `(:: name type)` gives a declaration's type signature
  ([Types](#types)).
- `Mod::name` names a declaration in another module
  ([Modules and imports](#modules-and-imports)).
- `s.x` reads the field `x` of a struct ([Structs](#structs)).

### Whitespace

Spaces, tabs and newlines separate tokens, and mean nothing beyond
that. Lay your code out however you like, or let `axiom fmt` do it.

### Comments

```scheme
; A line comment runs to the end of the line.

#| A block comment.
   #| Block comments nest. |#
   This line is still inside the outer comment. |#
```

A line comment starts with `;`. A block comment is written
`#| ... |#` and can sit between any two tokens, even inside an
expression. Its contents are not read as source.

Block comments nest, so each `|#` closes the innermost comment still
open. A block comment that is never closed runs to the end of the file,
and that is not an error. A `#` that isn't followed by `|` is `AX1001`:
on its own, `#` doesn't start a comment.

`;@axiom:` metadata, such as `;@axiom:effect(io)`, is recognised only
in a line comment. Inside a block comment it is ordinary comment text.

Tested by `tests/selfhost/170-block-comment.ax` and `tests/diagnostics/335-axtag-in-block-comment.ax`.

## Literals

Here are Axiom's literals and the type each one has:

| Literal | Type | Notes |
|---|---|---|
| `42`, `-7` | `Int` | 64-bit signed integer |
| `1_000_000` | `Int` | Underscores separate digits for readability |
| `3.14` | `Float` | 64-bit floating point |
| `true`, `false` | `Bool` | Reserved: neither is bindable (`AX3094`) |
| `"hello world"` | `String` | A ready-to-use `Str` value (below) |
| `'x'` | `Char` | One character |

Numbers are decimal. A float is digits, a point and more digits, such
as `3.14`. There's no hexadecimal or exponent form. A `-` written
directly against a digit is part of the literal, so `-7` is a negative
number. An integer literal must fit in 64 bits, and one that doesn't
is `AX1004`.

A character literal holds one character, which may be outside ASCII:
`(cast Int 'A')` is 65, and `(cast Int 'é')` is 233.

### Escape sequences

Strings and character literals accept the same seven escapes:

| Sequence | Meaning |
|---|---|
| `\n` | Newline |
| `\t` | Tab |
| `\r` | Carriage return |
| `\\` | Backslash |
| `\"` | Double quote |
| `\'` | Single quote |
| `\0` | Null byte |

Any other escape, such as `\q`, is rejected with `AX1005`.

### String literals are `Str` values

A string literal is a complete `Str`, the standard library's string
type. It needs no conversion, and works anywhere a `Str` does:

```scheme
(import IO)
(import Str)
(import Fmt)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println "Hello, Axiom!")
    (println (fmtInt (strLen "Hello")))
    (println (strConcat "sum=" (fmtInt 42)))
    (println (strSlice "abcdef" 2 3))
    0
  })
```

```text
Hello, Axiom!
5
sum=42
cde
```

A literal's length is worked out at compile time, so `(strLen "Hello")`
reads a stored number instead of scanning the bytes. A literal
allocates nothing at run time.

The bytes are also NUL-terminated, so a literal can go straight to a
syscall or a C function that expects a C string. `__addr` gives you
the address of the bytes:

```scheme
"hello"             ; the Str value
(__addr "hello")    ; the address of its bytes
```

`Str.strFromLit` builds a `Str` from NUL-terminated bytes that arrive
without a length, such as a syscall buffer. You never need it for a
literal: `(strFromLit (__addr "hi"))` scans for a length the compiler
already knew, and gives the same value as `"hi"`.

### Strings and integers are different types

Every Axiom value is one machine word, and a `String` is the address of
a `Str`. Even so, `String` and `Int` are distinct types, and the checker
won't mix them:

```scheme refused
(:: main Int)
(fn (main)
  (+ 1 "hi"))   ; AX3004: expected Int, found String
```

A string literal can still go into a `Vec`, or be a `Map` value,
because the containers are generic. When you really do need a
string handle as a word, say so with `(cast Int s)`
([Type casting](#type-casting)).

*Under the hood:* a literal is a constant `Str` header in the
executable, pointing at its bytes, and two identical literals in one
module share a header. `axiom emit-llvm` shows it. The rules are
`MM-VAL-7` and `MM-VAL-7a` in [memory-model.md](memory-model.md).

## Identifiers and keywords

### Identifiers

Function and variable names start with a lowercase letter by
convention, and the standard library uses camelCase (`strLen`,
`vecPush`):

```scheme
myVariable
compute_sum
```

The character set is wider than that. An identifier's first character
is a letter, `_`, or one of

```text
+ - * / % < > = ! & | ^
```

and each character after the first is one of those, a letter, a digit,
or `'`. That's why `+` is a name rather than punctuation: `(+ a b)` is
an ordinary call to a function called `+`. It also means `set!`,
`half'`, `empty-list` and `a+b` are all names you can declare:

```scheme
(import IO)
(import Fmt)

(:: half' (-> Int Int))
(fn (half' n') (/ n' 2))

(:: a+b (-> Int Int Int))
(fn (a+b a b) (+ a b))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((empty-list 0))
    {
      (println (fmtInt (half' 10)))
      (println (fmtInt (a+b 2 3)))
      empty-list
    }))
```

```text
5
5
```

Some characters are left out:

- `?`, `~` and `@` are not identifier characters, so `empty?` is
  `AX1001`, not a name.
- `.` is field access and `::` is qualified module access
  (`Mod::name`), so neither can be part of a name. `tmp.1` is refused.
- A name can't begin with a digit or with `'`.

Any name `check` accepts also builds and runs. Tested by `scripts/check-symbol-names.sh`.

### Keywords

These words have grammar rules. None of them is reserved: each is an
ordinary identifier everywhere except the position its rule claims.
That position is the head of a form, for `mut` the head of a `let`
binding, for `in` the word after a `for` loop's binder, and for `by`
the word after its range. So `(let ((match 1)) match)` binds a
variable called `match`, and `(cast Int x)` is always the cast form,
whatever `cast` is bound to. Shadowing a keyword is legal, but it makes code hard to
read.

| Keyword | Purpose | More |
|---|---|---|
| `fn` | Define a function | [Functions](#functions) |
| `lambda` | Anonymous function | [Functions](#functions) |
| `let` | Local variable binding | [Let bindings](#let-bindings) |
| `mut` | Marks a `let` binding assignable | [Mutable bindings](#mutable-bindings) |
| `set` | Assign to a `mut` binding | [Mutable bindings](#mutable-bindings) |
| `if` | Conditional expression, variadic: `(if t1 b1 t2 b2 ... els)` | [if](#if) |
| `while` | Loop while a condition holds | [while loops](#while-loops) |
| `for` | Loop over a range, `(for i in lo..hi body)`, with a step, `(for i in lo..hi by step body)`, or over a `(Vec a)`, `(for x in xs body)` and `(for (x k) in xs body)` | [for loops](#for-loops) |
| `in` | After a `for` loop's binder: `(for x in xs body)` | [for loops](#for-loops) |
| `by` | After a `for` loop's range, before its step: `(for i in 0..10 by 2 body)` | [for loops](#for-loops) |
| `match` | Pattern matching | [Pattern matching](#pattern-matching) |
| `data` | Algebraic data type | [Algebraic data types](#algebraic-data-types) |
| `struct` | Product type with named fields | [Structs](#structs) |
| `type` | Type alias | [Type aliases](#type-aliases) |
| `subtype` | Range-constrained subtype of `Int` | [Range-constrained subtypes](#range-constrained-subtypes) |
| `cast` | Type cast | [Type casting](#type-casting) |
| `effect` | Declare an effect type | [Effects](#effects) |
| `handle` | Handle effects | [Effects](#effects) |
| `import` | Import a module | [Modules and imports](#modules-and-imports) |
| `pub` | Public visibility | [Visibility](#visibility) |
| `macro` | Define a macro | [Macros](#macros) |
| `region` | Bracket an allocation scope: `(region r body)` reclaims everything `body` allocated when it ends, and answers `body`'s value | [Regions](#regions) |
| `sizeof` | Size of a type in bytes: `(sizeof Int)` is 8 | |
| `alignof` | Alignment of a type in bytes | |
| `parallel` | Run bindings beside the caller and join them in the order written: processes by default, threads under `--threads` | [parallel](#parallel--bindings-that-run-beside-the-caller) |
| `extern` | Declare Rust functions to call | [Calling Rust](#calling-rust) |
| `asm` | Inline assembly, one arm per architecture. A local binding named `asm` shadows it | [Inline assembly](#inline-assembly) |

`axiom fmt` follows the same rule. It prints a keyword used as a
parameter, `let` binder, pattern, argument or effect name as the
identifier it is. Like `check`, it refuses `begin`, `cond` and
`consume` at the head of a form (`AX2004`), and `mut` as the name of a
`let` binding (`AX2001`), where `mut` is the marker.

Tested by `tests/fmt/parity/190-keyword-param.axp` through `197-begin-head-refused.axp`.

### Removed keywords

These words still have a rule, and the rule is a refusal: each one
reports `AX2004`. The message, or `axiom explain AX2004`, says what to
write instead:

| Keyword | Write instead |
|---|---|
| `begin` | A brace block, `{ a b c }`. A `fn` body already runs its expressions in order, so often you can just delete it |
| `cond` | The variadic `if`: `(if t1 b1 t2 b2 ... els)` |
| `define` | `fn`: `(fn (add x y) (+ x y))`, and `(fn (answer) 42)` when it takes no parameters |
| `union` | `data` for a tagged sum, or `struct` for a product |
| `foreign` | An `extern` block ([Calling Rust](#calling-rust)), or the standard library, which needs no FFI |
| `trait` | A [capability record](#capability-records): a struct of functions, passed as a value |
| `impl` | An ordinary value of a capability record, bound with `fn` |
| `deriving` | An explicit derive macro such as `(deriveEq T)` ([macro-system.md](macro-system.md), `MAC-CAP-9`) |
| `linear` | The type itself. Reference counting reclaims memory (`MM-LIFE-2b` and `MM-LIFE-2c` in [memory-model.md](memory-model.md)) |
| `consume` | The argument itself: `(consume e)` always meant `e` |
| `alloc` | `__alloc`, or `vecNew`, `strAlloc` or a struct |

[Removed features](#removed-features) has more on most of them.
The removed type forms `[T]` and `(A B)` are under
[Compound types](#compound-types).

## Functions

You declare a function with `fn`, usually with a type signature above
it. Here is a two-parameter function and a call to it:

```scheme
(import IO)

(:: add (-> Int Int Int))
(fn (add x y)
  (+ x y))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (println (add 2 3))
  0)
```

It prints `5`.

`(:: add (-> Int Int Int))` is the signature. The last type in the
arrow is the result and the ones before it are the parameters, so `add`
takes two `Int`s and returns an `Int`. The signature is optional: leave
it out and the compiler infers the type from the body. A function
that calls itself, or is called from a declaration above it, needs
its signature: declarations are checked in the order they are
written, so those calls come before the body that would answer them
(`AX3089`). [Types](#types) covers the type syntax.

### Parameters

A function takes as many parameters as its head names:

```scheme
(:: add3 (-> Int Int Int Int))
(fn (add3 x y z)
  (+ x (+ y z)))
```

A function with no parameters has a plain type as its signature:

```scheme
(:: answer Int)
(fn (answer) 42)
```

Each use of its name calls it, so `answer` and `(answer)` both give
`42`. The name always sits in parentheses, with its parameters:
`(fn answer 42)` is `AX2001`.

### Several expressions in a body

A function body can hold several expressions. They run in order, and
the last one is the function's value:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (println "Starting...")
  (println "Working...")
  0)
```

Function bodies, `let` bodies and `while` bodies all work this way. An
`if` branch and a `lambda` body take one expression, so group several
in braces:

```scheme
;@axiom:effect(io)
(fn (verbose-add x y)
  { (println "adding") (+ x y) })
```

A brace block's value is the value of its last expression. A single
expression in braces is just that expression: `{ 42 }` is `42`.

### Lambdas

`lambda` makes a function value with no name:

```scheme
(lambda (x) (+ x 1))

(lambda (x y) (+ x y))

(lambda (_) 42)    ; `_` ignores the argument
```

In expression position, `fn` parses as the same node: `(fn (x) (+ x 1))`
is a lambda. It is the older spelling; write `lambda`, which is what
`axiom fmt` prints.

A lambda captures the variables it uses from the surrounding scope, and
you can pass it anywhere a function type is expected:

```scheme
(import IO)

(:: apply (-> (-> Int Int) Int Int))
(fn (apply f x) (f x))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((offset 100))
    (println (apply (lambda (x) (+ x offset)) 5))
    0))
```

It prints `105`.

A lambda's parameters carry no declared type, so an argument of the
wrong type isn't caught: `((lambda (x y) (- x y)) 10 "oops")` compiles.

### Partial application

Apply a lambda to fewer arguments than it takes, and you get a function
that waits for the rest. A top-level function can't be applied that
way. Wrap it in a lambda, or leave a [`_` hole](#fill-in-an-argument-later-with-_).

```scheme
(import IO)

(:: mkAdder (-> Int (-> Int Int)))
(fn (mkAdder n)
  ((lambda (x y) (+ x y)) n))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((subFrom10 ((lambda (x y) (- x y)) 10))
        (addTen (mkAdder 10)))
    (println (subFrom10 3))    ; 10 - 3
    (println (addTen 5))
    0))
```

It prints `7`, then `15`.

One rule explains the difference. A partial application has to hold the
arguments it wasn't given, and it keeps them in a closure record: the
block a closure stores its captured values in. A lambda has one. A
top-level function doesn't, however its signature is written.

A partially applied lambda is an ordinary value:

- It takes the missing arguments in order, and you can supply them one
  application at a time.
- It keeps the variables the lambda captured, alongside the arguments
  it was given.
- It can leave the function that built it, which is how `mkAdder`
  works.
- It can be stored in a struct field typed `(-> Int Int)` and called
  back through that field.

A top-level function applied to too few arguments is `AX3013`:

```scheme refused
(:: add (-> Int Int Int))
(fn (add x y) (+ x y))

(:: addFive (-> Int Int))
(fn (addFive) (add 5))

(:: main Int)
(fn (main) (addFive 1))
; error[AX3013]: partial application of `add`: it takes 2 argument(s)
;                and 1 were supplied
```

Wrap it in a lambda, `(lambda (y) (add 5 y))`, or write `(add 5 _)`.

The compiler counts arguments across the whole chain of applications,
starting from the function at its root. So on a three-parameter
top-level `add3`, `((add3 1 2) 3)` is one call with three arguments and
compiles. `(let ((h (add3 1 2))) (h 3))` gives the chain only two, and
is `AX3013`. For the same reason, `(((lambda (x y z) ...) 1 2) 3)` is
an ordinary complete call.

Too many arguments is a different error. Once the arrows run out, the
result isn't a function any more, and applying it reports `AX3004`:
"expected function type, found `Int`".

Tested by `tests/selfhost/988-lambda-partial-application.ax` and
`tests/diagnostics/110-partial-application.ax`.

#### Fill in an argument later with `_`

A bare `_` among a call's direct arguments turns the call into a
lambda, with one parameter per `_`, taken left to right. Use it when
the missing argument isn't the last one. It works on top-level
functions too, because the lambda it builds supplies the closure
record:

```scheme
(import IO)

(:: sub (-> Int Int Int))
(fn (sub x y) (- x y))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((subFrom50 (sub 50 _))    ; (lambda (y) (sub 50 y))
        (minus8 (sub _ 8)))       ; (lambda (x) (sub x 8))
    (println (subFrom50 8))
    (println (minus8 50))
    0))
```

It prints `42` twice.

A call with no `_` is unchanged, so a top-level function applied to
too few arguments is still `AX3013`. Holes work on a lambda's
arguments too: `((lambda (x y) (- x y)) 50 _)` is a one-parameter
function. Anywhere else in an expression, a bare `_` is `AX3001`. As a
pattern, `_` keeps its separate meaning as a wildcard.

Tested by `tests/selfhost/989-hole-partial-application.ax`.

## Operators

Every operator is prefix: it goes before its arguments, like any other
call. There are no precedence rules, because the parentheses say
what applies to what.

```scheme
(+ 1 2)             ; 3
(- 10 3)            ; 7
(* 4 5)             ; 20
(/ 10 2)            ; 5
(% 10 3)            ; 1

(== 1 2)            ; false
(!= 1 2)            ; true
(< 1 2)             ; true
(> 1 2)             ; false
(<= 1 2)            ; true
(>= 1 2)            ; false

(&& true false)     ; false
(|| true false)     ; true
(! true)            ; false

(- 5)               ; -5 (negation, unary)
```

```scheme
(& 12 10)           ; 8   bitwise and
(| 12 10)           ; 14  bitwise or
(^ 12 10)           ; 6   bitwise xor
(<< 1 10)           ; 1024
(>> 1024 3)         ; 128
```

`&&` and `||` short-circuit: they evaluate the right operand only when
the left one doesn't already decide the answer. So a guard means what
it looks like: `(&& (< i n) (== (strByte s i) c))` never reads `s` at
`i` unless `i` is in range. `!` is the `Bool` its operand is not, so
`(! (strEq a b))` reads as it sounds.

Tested by `tests/stdlib/582-not.ax`.

### Integer arithmetic

`Int` is 64-bit two's complement, and `+`, `-` and `*` wrap silently
on overflow. Negating the most negative value gives that same value
back. There's no literal for it: `(- 0 9223372036854775807)` is one
greater, and `Err` names it `intMin`.

- `/` truncates toward zero, and `%` takes the sign of its left
  operand: `(/ -7 2)` is `-3` and `(% -7 2)` is `-1`.
- `>>` is an arithmetic shift, so it keeps the sign bit:
  `(>> -1024 3)` is `-128`.
- Dividing by zero with `/` or `%` stops the program. It prints
  `axiom: division by zero` to stderr and exits with status 72
  ([memory-model.md](memory-model.md)).
- Two cases have no defined result, and can give different answers at
  different `--opt` levels: `intMin` divided by `-1`, and a shift
  amount outside `0`–`63`.

When you need to catch these cases, `Err` has checked versions that
return a `Result`: `addChecked`, `subChecked`, `mulChecked`,
`divChecked`, `remChecked`, `shlChecked` and `shrChecked`.

### Floats and strings

`+`, `-`, `*`, `/` and the six comparisons also take two `Float`s:
`(+ 1.5 2.25)` is `3.75`. Both operands must be `Float`. Mixing an
`Int` with a `Float` is `AX3004`, so convert first with `__intToFloat`.
`%`, the bitwise operators and the shifts take `Int`s only.

Float arithmetic is IEEE 754 double precision, with nothing fused or
reordered, so the same operations in the same order give the same bits
at every `--opt` level. `__floatToInt` truncates toward zero. A NaN
converts to 0, and a value beyond `Int`'s range to the nearest end.

Tested by `tests/stdlib/622-float-to-int.ax`.

To read or print a float exactly, use the `Float` module. `floatParse`
reads decimal text correctly rounded, and `floatToString` prints the
shortest text that reads back to the same bits, so `0.1` prints as
`0.1` and every finite value survives the round trip.

Tested by `tests/stdlib/690-float-repr.ax` and
`tests/stdlib/691-float-parse.ax`.

`==` and `!=` on two `String`s compare their contents, so
`(== "ab" (strConcat "a" "b"))` is `true`. The orderings `<`, `>`,
`<=` and `>=` don't take strings. Use `strCmp` from `Str` instead.

### Operator types

The nineteen operators are built in and always available. No import
brings them in. No declaration can take an operator's name: a
function, constructor or type spelled `+`, as in `(fn (+ a b) ...)`,
is `AX2001`, because every use of `+` reaches the built-in. A local
binding or parameter with that name does shadow it inside its own
scope.

Tested by `tests/selfhost/1005-operator-binder-shadows.ax`.

An operator can't be passed as a bare value:
handing `+` to another function is `AX3013`. Pass a lambda instead,
`(lambda (a b) (+ a b))`.

These are the types `axiom symbols --builtins <file>` prints for them,
beside the [memory primitives](#memory-primitives):

| Operator | Signature |
|---|---|
| `+`, `-`, `*`, `/`, `%` | `(Int -> (Int -> Int))` |
| `&`, `\|`, `^`, `<<`, `>>` | `(Int -> (Int -> Int))`: bitwise and, or, xor, shift left, shift right (arithmetic) |
| `==`, `!=`, `<`, `>`, `<=`, `>=` | `(Int -> (Int -> Bool))` |
| `&&`, `\|\|` | `(Bool -> (Bool -> Bool))` |
| `!` | `(Bool -> Bool)` |

The signatures are curried because that is how the checker holds every
function type. A call supplies both arguments at once, as the examples
above do.

## Let bindings

`let` binds local names for use in its body:

```scheme
(import IO)

(:: compute (-> Int Int))
(fn (compute n)
  (let ((x (+ n 1))
        (y (* x 2)))
    (+ x y)))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (println (compute 4))
  0)
```

It prints `15`.

The bindings are evaluated in order, so a later one can use an earlier
one: `y` reads `x` above. Nesting `let`s does the same thing:

```scheme
(let ((x 1))
  (let ((y (+ x 1)))
    (+ x y)))
```

A `let` body can hold several expressions, and its value is the last
one. A binding can't be assigned unless you mark it `mut`.

<a id="mutable-bindings-and-while"></a>
### Mutable bindings

Mark a binding `mut` and you can assign it with `set`:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((mut count 0))
    (set count (+ count 1))
    (set count (+ count 1))
    (println count)
    0))
```

It prints `2`.

Assigning a binding that isn't `mut` is `AX3012`:

```scheme refused
(:: main Int)
(fn (main)
  (let ((x 0))
    (set x 1)))
; error[AX3012]: cannot assign to immutable binding `x`
```

The report points at the declaration as well as the assignment, and it
carries a fix your tools can apply: `x` becomes `mut x` where the
binding is introduced.

`set` also writes a struct field through a dotted path. Here the
*field* carries the `mut`, and the binding doesn't need to:

```scheme
(struct Counter (mut n : Int) (step : Int))

(:: bump (-> Counter Int))
(fn (bump c)
  (set c.n (+ c.n c.step)))
```

`mut` on a binding lets you assign the name itself. Writing a field
changes the value the name refers to, which is a different operation,
so only the field's `mut` counts. Writing a field that isn't `mut` is
also `AX3012`.

In `(set a.b.c v)` it is `c` that must be `mut`, not `b`, because the
write changes the value at `a.b` and not the slot holding it.
[Structs](#structs) has more on writing fields.

The target of `set` is a name or a field path, never a computed
expression. `(set (f x) 1)` is a syntax error, `AX2001`: "expected the
name of a `mut` binding, or a field path".

<a id="conditionals"></a>
## Control flow

Axiom has `if` for choosing between branches, and `while` and `for`
for loops. Each one is an expression. To choose by the shape of a
value, use `match` ([Pattern matching](#pattern-matching)).

### if

`if` takes a test, a branch for true, and a branch for false. It
returns the value of the branch it takes:

```scheme
(import IO)

(:: abs (-> Int Int))
(fn (abs n)
  (if (< n 0)
      (- 0 n)
      n))

(:: classify (-> Int String))
(fn (classify n)
  (if (< n 0) "negative" (== n 0) "zero" "positive"))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (println (abs -7))
  (println (classify -3))
  (println (classify 0))
  (println (classify 12))
  0)
```

It prints:

```text
7
negative
zero
positive
```

`classify` shows that `if` takes any number of test and branch pairs.
`(if t1 b1 t2 b2 ... els)` is the nested chain
`(if t1 b1 (if t2 b2 ... els))`. The parser builds that chain, so it
checks and compiles exactly as the nested `if`s would.

- The final else is required. Leaving it out is `AX2001`.
- Both branches of each `if` must have the same type. Otherwise the
  checker reports `AX3004`.
- Each branch is one expression. Group several in braces,
  `{ (println "big") 1 }`.

To combine tests without branching, use `&&` and `||`.

`cond` has been removed and reports `AX2004`; run `axiom explain AX2004`
for the migration. Rewrite `(cond (t1 b1) (t2 b2) (else els))` as
`(if t1 b1 t2 b2 els)`, and write out an else where the `cond` had
none. `cond` never compared its clause types, and `if` does, so
clauses that returned different types now report `AX3004` until they
agree.

### while loops

`while` runs its body for as long as its test holds. It usually works
with a `mut` counter:

```scheme
(import IO)

(:: sumTo (-> Int Int))
(fn (sumTo n)
  (let ((mut i 0)
        (mut acc 0))
    (while (< i n)
      (set acc (+ acc i))
      (set i (+ i 1)))
    acc))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (println (sumTo 5))
  0)
```

It prints `10`.

The body takes any number of expressions, so a loop that updates two
variables needs no braces. A `while` evaluates to `0`, because a loop
that ran zero times has no last iteration to take a value from.

`while` is a real loop, so it runs in constant stack at every `--opt`
level. You can also iterate by recursion, and a self tail call runs in
constant stack too. Recursion that isn't a tail call is limited by the
machine stack, so avoid a fold like `(+ (f i) (loop (+ i 1)))` over
large inputs. [Optimisation](#optimisation) compares the spellings.
Tested by `tests/selfhost/500-while-mut.ax`.

<a id="for--the-counted-loop-and-the-container-loop"></a>
### for loops

`for` counts through a range of integers or walks the elements of a
`(Vec a)`. The binder comes first, then `in`, then what to loop over:

```scheme
(import IO)
(import Vec)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((mut total 0)
        (names vecNew))
    (vecPush names "ada")
    (vecPush names "grace")
    (for i in 0..5              ; 0, 1, 2, 3, 4
      (set total (+ total i)))
    (println total)
    (for i in 0..10 by 3        ; 0, 3, 6, 9
      (println i))
    (for i in 3..0 by -1        ; 3, 2, 1
      (println i))
    (for name in names          ; each element
      (println name))
    (for (name k) in names      ; each element with its index
      (println "{k}: {name}"))
    0))
```

It prints:

```text
10
0
3
6
9
3
2
1
ada
grace
0: ada
1: grace
```

| Shape | Runs the body |
|---|---|
| `(for i in lo..hi body)` | once for each `i` from `lo` up to, but not including, `hi` |
| `(for i in lo..hi by step body)` | stepping by `step`: up while below `hi` when the step is positive, down while above `hi` when it is negative |
| `(for x in xs body)` | once for each element of the `(Vec a)` `xs`, with `x` bound to it at type `a` |
| `(for (x k) in xs body)` | the same, with `k` counting 0, 1, 2 beside the elements |

The rules:

- `in` follows the binder in every shape. `in` and `by` are keywords
  only in those positions, so a variable named `in` or `by` works
  anywhere else.
- Either end of a range can be any expression: `0..n`,
  `lo..(+ lo 3)`, `0..(strLen s)` and `p.x..p.y` all work. Spaces
  around `..` are allowed, and `axiom fmt` removes them.
- A range whose `hi` is at or below `lo` runs zero times. To count
  down, give a negative step.
- `lo`, `hi`, the step and the container are each evaluated once,
  before the first iteration. A body that pushes onto `xs` doesn't
  change how many times the loop runs, and a step expression with a
  side effect runs only once.
- The body is exactly one expression. Put several in `{ ... }`: a
  second one would leave `(for x in xs a b)` ambiguous.
- Every `for` evaluates to `0`, as `while` does. Nested loops each
  keep their own counter.
- The loop's own hidden bindings use names no program can write, so
  they never capture a variable of yours, such as an `i` or `n` bound
  around the loop.
- The container shapes call `Vec::vecLen` and `Vec::vecGet` by their
  full names, so a `vecLen` of your own doesn't interfere.

Tested by `tests/stdlib/466-for-loop.ax`.

#### When a loop is refused

- A missing `in` is `AX2001` at the token where it belongs, with a fix
  that inserts it (`tests/diagnostics/634-for-missing-in.axbad`).
- A literal step of `0` never moves the counter, so it is refused
  where it stands with `AX2001`
  (`tests/diagnostics/632-for-zero-step.axbad`).
- After the range or the container, the body is the only element
  left. A second body is `AX2001`
  (`tests/diagnostics/625-for-shape.axbad`).
- An element-index binder `(x k)` works with the container shape only,
  because a range counts its own index
  (`tests/diagnostics/633-for-pair-range.axbad`).
- Looping over something that isn't a `Vec` is reported at your
  expression: `(for x in n body)` over an `Int` underlines `n` with
  `AX3004 type mismatch: expected Vec _a, found Int`. A second row
  points at the `for` keyword, because the loop reads the container
  twice. Each row's help names what fits instead: a range for an
  `Int`, and the idioms below for a `String` or a `Map`
  (`tests/diagnostics/626-for-not-a-container.ax`).
- The container shapes need `Vec` in reach through an import. Without
  it, the `for` reports `AX3001 undefined variable Vec::vecLen`.

#### Loop over a string or a map

A `String` is read byte by byte over its length, and a `Map` through
its keys vector:

```scheme
(import IO)
(import Str)
(import Map)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((s "hi")
        (m mapNew)
        (mut total 0))
    (for i in 0..(strLen s)        ; each byte
      (println (strByte s i)))
    (mapInsert m 1 10)
    (mapInsert m 2 20)
    (for k in (mapKeys m)          ; each key, in no fixed order
      (set total (+ total (mapGet m k 0))))
    (println total)
    0))
```

It prints `104`, `105`, then `30`.

Byte values are `Int`s, not characters. Decoding multibyte text is the
`Utf8` module's job. `mapGet` takes a default to return for a missing
key, and a loop over `mapKeys` only asks about keys that are there, so
any value of the right type will do.

#### `for` as a name

`for` is a keyword only at the head of a form, like every keyword in
[Identifiers and keywords](#identifiers-and-keywords). Everywhere else
it is an ordinary name: a parameter, a `let` binder or a pattern
variable. `axiom fmt` prints it that way too
(`tests/fmt/parity/199-for-arg-position.axp`). It lays out a `for` as
it lays out `while`, with the binder and the range or container on the
head line and the body indented below
(`tests/fmt/parity/198-for-head-layout.axp`).

Limit: a macro of your own named `for` never runs. The keyword wins,
with no diagnostic, so the macro is dead code that still type-checks.

*Under the hood:* the parser rewrites every `for` into `let`, `while`
and `set`, with its bounds bound before the loop. Nothing after the
parser knows the keyword exists, and a `for` compiles to the same code
as that loop written by hand.

<a id="type-system"></a>
## Types

Every value in Axiom has a type, and the compiler checks them all
before your program runs. You can write a signature for any function,
and the compiler infers the rest.

```scheme
(import IO)

(:: average (-> Int Int Float))
(fn (average a b)
  (/ (__intToFloat (+ a b)) 2.0))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (average 3 4))
    0
  })
```

```text
3.500000
```

### Type signatures

A signature is declared with `::`, before the function:

```scheme
(:: add (-> Int Int Int))
```

This says `add` takes two `Int`s and returns an `Int`. `(-> A B C)`
means a function that takes `A`, then `B`, and returns `C`. The type
is curried, but a top-level function still isn't partially applicable.
A `lambda` is (see [Partial application](#partial-application)).

### Primitive types

| Type | Description |
|---|---|
| `Int` | 64-bit signed integer |
| `Float` | 64-bit floating point |
| `Bool` | Boolean (`true` / `false`) |
| `Char` | A Unicode code point: `'A'` is 65, `'é'` is 233, `'世'` is 19990, `'😀'` is 128512 |
| `String` | String (pointer) |
| `()` | The empty tuple type, with no value. `(:: main ())` and `(:: f (-> () Int))` are accepted, and `symbols` shows the empty tuple as `()`. `()` in an expression is `AX2001 expected expression`, as are `[]` and `(set)` |
| `Foreign` | An opaque pointer into memory Axiom didn't allocate and doesn't own, held as one word. It is distinct from `Int` because reference counting never follows a `Foreign` field. `(cast Foreign x)` converts in and out. See [ffi.md](ffi.md) |
| `Handle` | A share of a Rust value that Axiom owns: a counted block holding the Rust pointer and its destructor (`stdlib/Ffi.ax`). It is a reference like `String`: each share is released at the end of its `let`'s scope, and when the last share goes, Rust's `Drop` runs once. `axiom-bindgen` wraps each opaque Rust type in its own `data` type around a `Handle`, so `Counter` and `Widget` stay distinct. `ffiHandleClose` destroys the value early and leaves the block inert |

### Sized integers and floats — removed

`Int` is the one integer type and `Float` the one floating-point type.
The sized names `I8`–`I128`, `U8`–`U128`, `Isize`/`Usize`, `Double`
and `F32`/`F64` are rejected as `AX3002`. To convert between the two
numeric types, use `__intToFloat` and `__floatToInt`.

### Compound types

```scheme
(-> Int Int)           ; Function: Int -> Int
(-> Int Int Int)       ; Curried: Int -> Int -> Int
(* Int)                ; Pointer to Int
```

The list type `[T]` and the tuple type `(A B)` are rejected as
`AX2004 removed-construct`, with advice naming the replacement. No
value could ever have either type. Use `(Vec T)` for a sequence,
[`struct`](#structs) for a product and [`data`](#algebraic-data-types)
for a sum. `()` is unaffected: it stays the empty tuple type, with no value.

### Type variables and polymorphism

```scheme
(data Maybe (a)
  (Nothing)
  (Just a))
```

The `(a)` after the type name introduces a type parameter, so the same
`Maybe` can hold a value of any type.

A generic value bound by `let` keeps the type its uses choose. Push a
`String` into an empty vector and that binding becomes a
`(Vec String)`. A later `Int` push is a type mismatch (`AX3004`).
Separate empty vectors can take different element types.

Inferred types must be finite. Inserting a vector into itself would
need its element type `a` to equal `(Vec a)`, so the compiler rejects
it with `AX3004`, and it rejects an indirect cycle through two vectors
the same way. Finite nested vectors are fine, and so are explicitly
recursive data declarations such as
`(data Tree () (Leaf Int) (Branch (Vec Tree)))`. Name a recursive
structure with a data type rather than relying on an infinite inferred
type. This rule is about types: it doesn't establish ownership or
prevent cycles between objects at run time.

### Type casting

`cast` reinterprets one word as another type. The type comes first and
the expression second:

```scheme
(cast Float someBits)
```

The word itself is unchanged. There is no conversion, no check and no
run-time cost, which is why the numeric conversions have their own
names (`__intToFloat`, `__floatToInt`). Use `cast` to cross a
distinction the checker is otherwise keeping for you: `(cast Foreign x)`
in and out of an opaque pointer, or `(cast Int s)` to read a `String`
handle as a word. It is the entry point to the unsafe layer (see
[Effects](#effects)), and everything that layer says about what the
checker stops proving applies from here.

A type ascription, `(:: e T)`, reads as the same cast with its
operands swapped: `(:: someBits Float)` casts `someBits` to `Float`.
Write `(cast T e)`.

Tested by `tests/selfhost/870-ascription-and-negation.ax`.

### Region annotations

A signature can name the *region* a reference lives in, with `@name`
as the last thing inside a type's parentheses:

```scheme
(:: lookup (-> (Vec String @r) Int (String @r)))
(:: intern (-> (String @s) (Table @r) (Sym @r)))
```

`@r` and `@s` are region parameters. The caller chooses them through
the arguments, once per call, as it does a type variable. A region
named in a signature outlives the function's own region, which is its
caller's current region. Two named regions are unordered: neither is
known to outlive the other. A
signature that names no region uses the caller's current region, so a
program that never writes `@` works in a single region throughout.

The annotation buys one rule, `MM-RGN-3` in
[memory-model-v2-design.md](memory-model-v2-design.md) §2.3: **a value
may be stored into, returned into or captured by a place only if the
value's region outlives the place's.** Breaking it is one of four
errors:

| Code | Rejects |
|---|---|
| `AX3060` | a store whose place outlives the value: a `set`, a field write, a raw `__store64`, or a store a callee makes through its parameter |
| `AX3061` | a result that doesn't live in the region the signature names for it |
| `AX3062` | either of the above when the value is a closure, reported against the capture that makes it short-lived |
| `AX3063` | a call whose arguments disagree on a region the callee names, or a signature naming a region on its result that no parameter supplies |

A callee without annotations is checked by reading its body. For each
function, the checker works out which parameters the body stores a
fresh value into, and which parameters flow into which. `vecPush`
stores its second parameter into its first, so `(vecPush v x)` is
rejected when `x`'s region doesn't outlive `v`'s, and accepted when
both live in one region. `(strLen s)` is fine on a string from any
region, because nothing flows into `s`. The same facts answer
[`restrict(no-escape)`](#restrict---what-a-declaration-does-not-do).

Two limits:

- A call the compiler can't resolve, such as one through a parameter,
  a closure or a field, is assumed to store every argument into every
  argument.
- Nothing yet allocates *into* a named region. A value the body
  allocates lives in the caller's region, so it can't be stored into
  a `@r` place or returned as `(T @r)`. That includes growing a
  container that lives in `@r`, because `vecPush` allocates.
  Allocating into a named region is planned for stage S4 of the
  design note.

`@` on its own is `AX1001`, and `@r` anywhere but the end of a type's
parentheses is `AX2001`. The annotation doesn't change the code the
compiler emits.

Tested by `tests/stdlib/468-region-signatures.ax` and
`tests/diagnostics/645-region-escape-store.ax` to `649-restrict-no-escape.ax`.

### Effect types

A function can also declare the effects it performs, and the compiler
checks that its body matches:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main) (println "hello"))
```

[Effects](#effects) covers them in full.

## Type aliases

A type alias gives a new name to an existing type:

```scheme
(import IO)

(type Name = String)
(type Celsius = Float)

(struct Reading
  (place : Name)
  (temp : Celsius))

(:: label (-> Reading Name))
(fn (label r) r.place)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (let ((r (Reading "Oslo" 4.5)))
      (println (label r)))
    0
  })
```

```text
Oslo
```

An alias doesn't create a new type, so `Name` and `String` are
interchangeable. The compiler expands the alias wherever a type is
named: a function signature, a struct field and a `data` constructor's
fields. An alias of `Float` computes as a `Float` everywhere.

Limit: a parameterised alias such as `(type Pair a = ...)` is not
expanded. It behaves as a separate, nominal type.

Tested by `tests/selfhost/973-type-alias.ax` and
`tests/stdlib/374-arc-alias-field.ax`.

### Range-constrained subtypes

A subtype names a range of `Int` values. The compiler checks the range
whenever a plain `Int` becomes the subtype:

```scheme
(import IO)

(subtype Percent is Int range 0..101)

(:: describe (-> Percent String))
(fn (describe p)
  (if (>= p 50) "at least half" "under half"))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (describe (cast Percent 75)))
    (println (+ (cast Percent 20) 1))
    0
  })
```

```text
at least half
21
```

`range 0..101` accepts `0 <= v < 101`: the upper bound is excluded.
A range with only a lower bound, such as `(subtype NonNeg is Int range 0)`,
checks `>=` and nothing else.

A subtype is a distinct type, not an alias. A `Percent` is not an `Int`
where the checker compares names, and the base type is always `Int`.
The check happens at the conversion, at run time:

- `(cast Percent v)` stops the program with exit status 80 unless `v`
  is in range. This is the same trap a failed contract uses.
- Passing an `Int` to a `(-> Percent Int)` parameter, or returning one
  through `(-> Int Percent)`, is checked at the boundary the same way.
- Widening needs no check. A `Percent` has already proved its range,
  so `(cast Int p)` and passing one where `Int` is declared are free.

Subtype values compute as `Int`: arithmetic and `println` treat a
`Percent` as the `Int` it holds. The compiler doesn't try to prove a
range statically, so every conversion is checked when it runs.

Tested by `tests/selfhost/134-subtype-checked.ax` and
`tests/selfhost/135-subtype-violated.ax`.

## Algebraic data types

A `data` declaration defines a type by listing its constructors. Each
constructor is one shape a value can take, with its own fields:

```scheme
; Optional value
(data Maybe (a)
  (Nothing)
  (Just a))

; Linked list
(data List (a)
  (Nil)
  (Cons a (List a)))

; Binary tree
(data Tree (a)
  (Leaf)
  (Node (Tree a) a (Tree a)))

; Ordering result
(data Ordering
  (LT)
  (EQ)
  (GT))
```

The `(a)` after the type name is a type parameter, like generics in
other languages. A constructor is called like a function to build a
value, `(Cons 1 (Nil))`, and taken apart with
[`match`](#pattern-matching). Recursive types such as `List` need
nothing special. [Tips and patterns](#tips-and-patterns) builds a
`List` in a whole program.

### Struct variants — named fields per constructor

A constructor's fields can be named instead of positional:

```scheme
(import IO)

(data Shape
  (Circle { r : Int })
  (Rect { w : Int, h : Int })
  (Point))

(:: area (-> Shape Int))
(fn (area s)
  (match s
    ((Circle { r })   (* 3 (* r r)))
    ((Rect { h, w })  (* w h))
    ((Point)          0)))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (area (Circle 2)))
    (println (area (Rect 3 4)))
    (println (area (Point)))
    0
  })
```

```text
12
12
0
```

You build values positionally, in declaration order: `(Rect 3 4)` has
`w` 3 and `h` 4. You read them back by name in a pattern. Named
patterns give you three things a positional pattern can't:

- **Order independence.** `{ h = h, w = w }` binds what its names say,
  so reordering two fields of the same type in the declaration can't
  silently swap them at every match site.
- **Partiality.** A field the arm doesn't name isn't bound. There's no
  `_` placeholder to keep in step with the constructor's arity.
- **Punning.** `{ w, h }` means `{ w = w, h = h }`.

Punning and explicit binding mix freely, and named patterns nest:

```scheme
(match x
  ((Wrap { inner = (Rect { w, h }), tag = t }) (+ (* w h) t))
  ((Wrap { tag = t })                          t))
```

Positional patterns still work on the same type. Named fields add a
spelling rather than replacing one.

Field access such as `s.r` works only when every constructor declares
`r` at the same position with the same type. Otherwise it is rejected
as `AX3070`, because a value built by another constructor might not
hold `r` there.

### Deriving

To get equality for a `data` type, invoke the derive macro from
`Pre` where you want the function; to print a value, `(format x)`
renders it in full - no macro needed:

```scheme
(import IO)
(import Pre)

(data Colour
  (Red)
  (Green)
  (Blue))

(deriveEq Colour)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (format Green))
    (println (eqColour Red Red))
    (println (eqColour Red Blue))
    0
  })
```

```text
Green
true
false
```

`(deriveEq Colour)` generates `eqColour : Colour -> Colour -> Bool`,
an ordinary function, checked and compiled like one you wrote, and
called by name. In `axiom symbols --diagnostic-format ai`, its `F`
row carries `#generated=deriveEq`.

`Pre`'s `deriveEq` covers types whose constructors have no fields.
[Macros](#macros) shows how the macro is written, and
[macro-system.md](macro-system.md) §10.2 covers equality over fieldful
constructors. (`deriveShow` and `showOr` did the printing half before
`(format x)` existed; deprecated since 0.3.8, removed in 0.8.0.)

A `deriving` clause on the declaration is rejected as `AX2004`. Use the
macros above instead:

```scheme refused
(data Colour () (Red) (Green) deriving (Eq Show))
; error[AX2004]: `deriving` parsed and derived nothing, and is now refused
```

<a id="how-adts-actually-run"></a>
### How ADTs are represented

You don't need this to write correct programs. Each `data` type gets
one of three representations, chosen from its constructors:

| Condition | Representation |
|---|---|
| every constructor is nullary | a value is its tag, a small immediate integer, and nothing allocates |
| a mix of nullary and fieldful | nullary constructors are immediate tags, and fieldful ones are heap blocks |
| no nullary constructor, or too many tags | every value is a heap block |

A heap block holds the tag and then one word per field. A field whose
type is the type being declared is just another word holding that
value's address, so recursion needs no special handling. Tags are
unique across the whole program. [memory-model.md](memory-model.md)
`MM-VAL-8` and `MM-VAL-9` give the full rules.

Tested by `tests/stdlib/270-nullary-unboxed.ax` and
`tests/selfhost/400-mixed-nullary.ax`.

## Pattern matching

`match` takes a value apart by its shape. Each arm is a pattern and a
result, and the first arm that fits wins:

```scheme
(import IO)

(data List (a)
  (Nil)
  (Cons a (List a)))

(:: describe (-> (List Int) String))
(fn (describe xs)
  (match xs
    ((Nil)                   "empty")
    ((Cons _ (Nil))          "one item")
    ((Cons h (Cons h2 _))    (if (== h h2) "starts with a pair" "two or more"))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (describe (Nil)))
    (println (describe (Cons 7 (Nil))))
    (println (describe (Cons 7 (Cons 7 (Nil)))))
    (println (describe (Cons 1 (Cons 2 (Cons 3 (Nil))))))
    0
  })
```

```text
empty
one item
starts with a pair
two or more
```

### Matching constructors with fields

A constructor pattern names the constructor and binds one name per
field:

```scheme
(:: fromMaybe (-> Int (Maybe Int) Int))
(fn (fromMaybe default val)
  (match val
    ((Nothing) default)
    ((Just x) x)))
```

For constructors with named fields, you can match by name instead. See
[Struct variants](#struct-variants--named-fields-per-constructor).

### Matching literals

```scheme
(match x
  (42 "the answer")
  (-1 "minus one")
  (_ "anything else"))
```

A negative literal is written against its digits, `-1`, as it is in
an expression.

Tested by `tests/selfhost/1013-negative-literal-pattern.ax`.

### Nested patterns

```scheme
(match lst
  ((Cons h (Cons h2 t)) ...)
  ((Nil) ...))
```

Nesting is checked and bound all the way down. Inner constructors are
tested in turn and each level's fields are extracted, so this arm binds
all three of `h`, `h2` and `t`.

### Wildcard pattern

Use `_` to match anything and ignore the value:

```scheme
(match val
  ((Just x) x)
  (_ 0))
```

### Exhaustiveness checking

The compiler checks that every constructor of the matched type is
covered. A missing constructor is a compile error, `AX3005`:

```scheme
;; Correct: all constructors covered
(match val
  ((Nothing) default)
  ((Just x) x))

;; Incorrect: missing Nothing arm, compile error AX3005
(match val
  ((Just x) x))
```

Arity is checked too. A constructor pattern with the wrong number of
fields, such as `((Just) ...)` or `((Just x y) ...)` for a one-field
`Just`, is `AX3009`.

### The built-in Option type

`Option`, with its constructors `Some` and `None`, is always available
without a `data` declaration:

```scheme
(import IO)

(:: safeDiv (-> Int Int (Option Int)))
(fn (safeDiv a b)
  (match b
    (0 (None))
    (_ (Some (/ a b)))))

(:: orZero (-> (Option Int) Int))
(fn (orZero r)
  (match r
    ((Some x) x)
    ((None)   0)))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (orZero (safeDiv 10 2)))
    (println (orZero (safeDiv 10 0)))
    0
  })
```

```text
5
0
```

## Structs

A struct groups named fields into one value. You build it by listing
its fields in order, read a field with `.name`, and print the whole
thing without writing any formatting code:

```scheme
(import IO)

(struct Point
  (x : Int)
  (y : Int))

(:: shift (-> Point Int Point))
(fn (shift p n) (Point (+ p.x n) p.y))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((p (shift (Point 1 2) 10)))
    (let ((total (+ p.x p.y)))
      {
        (println "{p}")
        (println "x + y = {total}")
        0
      })))
```

```text
{x = 11, y = 2}
x + y = 13
```

Each field is `(name : Type)`. The `:` is required: it is what makes
the form a field declaration. Like a `let` binding, a field is
immutable unless it is declared `mut` (see [Write a field](#write-a-field)).

<a id="constructing-binding-and-reading-a-field"></a>

### Build a struct and read its fields

Construction is positional. The constructor is the struct's own name,
and its arguments are the fields in declaration order. A struct value
binds to a `let`, passes to a function and returns from one like any
other value.

There is no named-field spelling. The two that readers reach for both
fail, and neither error mentions structs. `(Point (x 1) (y 2))` reads
`x` and `y` as variables:

```scheme refused
(struct Point (x : Int) (y : Int))

(:: main Int)
(fn (main)
  (let ((p (Point (x 1) (y 2)))) p.x))
; error[AX3001]: undefined variable `x`
; error[AX3001]: undefined variable `y`
```

`(Point :x 1 :y 2)` stops at the colon, with `AX2001` "expected
expression, found `:`". Other mistakes at the constructor:

- The wrong number of fields is `AX3067`, "struct `Point` expects 2
  field(s), found 1". An `AX3004` follows wherever the half-built
  value is used.
- A field of the wrong type is `AX3004` at that argument.

A field access is an ordinary expression, usable anywhere a value is
wanted. `a.b.c` chains left to right: it reads the `c` of the value at
`a.b`.

The `.field` suffix attaches to a name, not to an expression. So you
can't read a field straight off a call's result: `(mk 5).x`, and even
`(p).x`, are `AX2001` at the dot. Bind the result to a name first.

```scheme refused
(struct Point (x : Int) (y : Int))

(:: mk (-> Int Point))
(fn (mk n) (Point n 2))

(:: main Int)
(fn (main) (mk 5).x)
; error[AX2001]: expected expression, found `.`
```

Asking for a field the type doesn't have is `AX3007`, reported at the
field name. It applies to every type, not only structs: `n.x` where `n`
is an `Int` reports "field `x` not found on type `Int`".

Any struct renders without a declaration of yours: `(format (Point 1
2))` is `{x = 1, y = 2}`, and `"{p}"` in a format string does the same.

<a id="writing-a-field"></a>

### Write a field

`set` writes through a dotted path ([Mutable bindings](#mutable-bindings)
has the general rule). The write needs `mut` on the field, and nothing
on the binding. `mut` goes inside the field's parentheses. This program
exits 9:

```scheme
(struct Point
  (mut x : Int)
  (y : Int))

(:: main Int)
(fn (main)
  (let ((p (Point 1 2)))
    { (set p.x 9) p.x }))
```

`p` is an immutable `let`, and that's fine. `mut` on a binding controls
whether you can rebind the name. `mut` on a field controls whether you
can change the value the name points at.

Drop the `mut` from `x` and the same program is refused:

```scheme refused
(struct Point
  (x : Int)
  (y : Int))

(:: main Int)
(fn (main)
  (let ((p (Point 1 2)))
    { (set p.x 9) p.x }))
; error[AX3012]: cannot assign to field `x` of `Point`: the field is not declared `mut`
```

The error points at `x` in `(set p.x 9)`, not at the declaration,
because the struct is often in another file. The help names the line to
write, `` `(mut x : Int)` ``. For the same reason there is no
machine-applicable fix.

Code written before 0.6.0, when `mut` on a field was ignored, needs
`mut` added to each field it writes.

Because the write goes through the value, it reaches through a
parameter, and the caller sees a callee's store. This program exits 42.
`inn` needs no `mut`, because the store changes the `Inner` that `inn`
points at, not `inn` itself:

```scheme
(struct Inner (mut v : Int))
(struct Outer (inn : Inner))

(:: bump (-> Outer Int))
(fn (bump o) { (set o.inn.v (+ o.inn.v 1)) o.inn.v })

(:: main Int)
(fn (main)
  (let ((o (Outer (Inner 40))))
    { (bump o) (bump o) o.inn.v }))
```

A field without `mut` is protected from `set`, not from raw memory.
`memSetWord` takes a block and a word index and writes it, and `Vec`
and `Map` use it for slots that aren't declared fields.

Tested by `tests/diagnostics/467-set-immutable-field.ax` and `tests/selfhost/561-field-store-mut.ax`.

### Every field needs a type

`(x Int)` is not a shorter spelling of `(x : Int)`. A field whose type
is missing or isn't a type is `AX3056`, an error at the field's name.
Three spellings reach it:

- no `:`, as in `(msg String)`;
- a `:` followed by something that isn't a type;
- a bare name such as `(msg)`, anywhere but first. In first position,
  a group of bare names is read as a type-parameter list (see
  [Type parameters](#type-parameters)).

The compiler needs each field's type to decide whether releasing the
struct should also release what the field holds. An untyped field
would leave that undecided, and a value stored in it could be freed
while the field still pointed at it. The field-store rule is
`MM-LIFE-2c` in [memory-model.md](memory-model.md).

Tested by `tests/diagnostics/388-struct-field-untyped.ax`.

### Type parameters

A struct can take type parameters, written as a parenthesised group
right after the name, as `data` does: `(struct Boxed (a) (val : a))`.

A struct's fields are parenthesised and start lowercase too, so the
rule is strict. A parameter list is lowercase names and nothing else:

- `(a b)` is a parameter list;
- `(start : Int)` is a field, because of the colon;
- `(msg String)` is a field, because `String` is uppercase. It has no
  colon, so it is `AX3056`.

Construction stays positional, and the parameter is fixed by the value
you pass in. One declaration serves every instantiation in the same
program. This exits 10:

```scheme
(import Str)

(struct Boxed (a)
  (val : a))

(:: main Int)
(fn (main)
  (let ((bi (Boxed 7)) (bs (Boxed "abc")))
    (+ bi.val (strLen bs.val))))
```

Tested by `tests/selfhost/901-parameterised-struct.ax`.

### Fields that hold functions

A field's type can be a function type. That is what turns a
parameterised struct into an interface, covered in full under
[Capability records](#capability-records). Here are the struct
mechanics.

Call a function field by applying it directly: `(c.render 7)`.
`((c.render) 7)` reads the field first and compiles to the same call;
`axiom fmt` prints the direct form. This exits 5:

```scheme
(import Fmt)
(import Str)

(struct ShowOf (a)
  (render : (-> a String)))

(:: showInt (ShowOf Int))
(fn (showInt) (ShowOf fmtInt))

(:: main Int)
(fn (main)
  (let ((c showInt))
    (+ (strLen (c.render 123))
       (strLen ((c.render) 45)))))
```

**You can't pass a top-level function of two or more arguments by
name.** This is the limit you'll meet first. It isn't specific to
structs: naming `add` where a value is wanted is `AX3013`, because a
top-level function has nowhere to keep arguments it wasn't given.

```scheme refused
(struct Ops (g : (-> Int Int Int)))

(:: add (-> Int Int Int))
(fn (add x y) (+ x y))

(:: main Int)
(fn (main)
  (let ((o (Ops add)))
    (o.g 5 3)))
; error[AX3013]: partial application of `add`: it takes 2 argument(s)
;                and 0 were supplied
```

Wrap it in a `lambda` instead. A lambda gets a closure record to keep
arguments in, so once the field holds one you can also apply it to some
of its arguments ([Partial application](#partial-application)). Here
`(o.g 5)` is a value, and the program exits 8:

```scheme
(struct Ops (g : (-> Int Int Int)))

(:: add (-> Int Int Int))
(fn (add x y) (+ x y))

(:: main Int)
(fn (main)
  (let ((o (Ops (lambda (x y) (add x y)))))
    (let ((add5 (o.g 5)))
      (add5 3))))
```

A top-level function of one argument can be passed by name, which is
why `showInt` above can hold `fmtInt` directly.

### Limits

Structs have no layout modifiers. `packed`, `repr(C)` and `align(N)`
are all `AX2001`. When you [call Rust](#calling-rust), a record crosses
the boundary one word per field, so there is no layout to change
([ffi.md §8](ffi.md#8-vec-slices-and-records-across-the-boundary)).

### Make a handle other modules can't forge

A struct declared `word` is one machine word, and only the module that
declares it can build one or read its field. Use it for a *handle*: a
value whose word means something only its module understands, such as
a slot in a table.

```scheme
(import IO)

(struct Ticket word
  (slot : Int))

(:: issue (-> Int Ticket))
(fn (issue n) (Ticket (* n 10)))

(:: redeem (-> Ticket Int))
(fn (redeem t) t.slot)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((t (issue 4)))
    {
      (println "{t}")
      (println (redeem t))
      0
    }))
```

```text
<Ticket>
40
```

`word` goes between the struct's name and its fields. A word struct
has exactly one field, an `Int`, not `mut`, and no type parameters
(`AX3084`). It allocates nothing: `(Ticket 40)` is the word 40, with
its own type. A `Ticket` isn't an `Int`, and passing one where the
other is expected is `AX3004`. It prints as its type's name.

Only the declaring module can build one, in either spelling, or read
its field, whether or not the struct is `pub` (`AX3085`, `AX3086`).
Another module can name the type in its signatures and pass values on,
so every `Ticket` it holds is one this module made.

Add `shared` when every operation the module offers on the type is
safe from several bindings at once, as in `(struct Chan word shared
(slot : Int))`. A `parallel` binding may capture a shared handle
([What a binding may capture](#what-a-binding-may-capture)). The
standard library's `Chan`, `Mutex` and `CancelToken` are declared this
way.

Tested by `tests/diagnostics/1062-handle-sealed-build.ax` and
`tests/diagnostics/1065-struct-marker.ax`.

## Capability records

Axiom has no traits or `impl`. An interface is a *capability record*: a
parameterised struct whose fields are functions. You declare the shape
once, and each implementation is a value built by handing the
constructor the functions that do the work.

```scheme
(import IO)
(import Fmt)

(struct ShowOf (a)
  (render : (-> a String)))

(:: showInt (ShowOf Int))
(fn (showInt) (ShowOf fmtInt))

(:: showSwitch (ShowOf Bool))
(fn (showSwitch) (ShowOf (lambda (b) (if b "on" "off"))))

(:: report (-> (ShowOf a) String a Int))
;@axiom:effect(io)
(fn (report s label v)
  (let ((text (s.render v)))
    (println "{label}: {text}")))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (report showInt "retries" 3)
    (report showSwitch "verbose" true)
    0
  })
```

```text
retries: 3
verbose: on
```

`report` is generic over the interface, and calling its method is
plain function application: `(s.render v)`. Because the record is an
ordinary value, you can build it at run time, pass it as an argument,
store it in a `Vec`, or generate it with a macro.

The rules for function fields, including which functions you can pass
by name, are in [Fields that hold functions](#fields-that-hold-functions).

### Effects through a record

A record's members are ordinary functions, so each declares its own
effects the way every other function does. There is no separate rule
for members, no effect list on the struct declaration, and no
exemption. An untagged `writeLine` whose body calls `println` gets
`AX3042` at its own name, just as it would outside a record.

```scheme
(import IO)

(struct ConsoleOf (a)
  (print : (-> a Int)))

;@axiom:effect(io)
(:: writeLine (-> String Int))

;@axiom:effect(io)
(fn (writeLine s) (println s))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((c (ConsoleOf writeLine)))
    (c.print "hi")))
```

The effects of a call through a field are *possible*, not definite.
Calling `c.print` applies a value the compiler can't resolve to one
function, so the effects `writeLine` brings in are marked possible. The
symbol listing shows it on `main`'s row:

```bash
axiom --diagnostic-format=ai symbols console.ax
```

```text
F main console.ax:12:5-9 "Int" @6159d363201f7f2a #effect=io #effects=Alloc,IO,Mut,Unsafe #effects-incomplete #effects-overapprox #effects-possible=IO,Mut,Unsafe
```

Each check reads that row as [Effects](#effects) describes for definite
and possible effects:

- `;@axiom:effect(io)` on `main` is accepted. A claimed effect that the
  body may perform is not missing.
- With no tag at all, `main` is not accused. `AX3042` reads only the
  definite effects, and `IO` here is only possible.
- `;@axiom:effect(pure)` over a call through a field is `AX3037`, a warning,
  not the `AX3010` error that a refuted claim gets. On `main` itself,
  `effect(pure)` is still `AX3010`, because building the record is a
  definite `Alloc`.

```scheme
;@axiom:effect(pure)
(:: greet (-> (ConsoleOf String) Int))
;@axiom:effect(pure)
(fn (greet c) (c.print "hi"))
; warning[AX3037]: AXTAG unverifiable on `greet`: `effect(pure)` claim cannot be
;                  checked: the body calls a value the compiler could not resolve
```

To swap the implementation, hand the constructor a different value. A
`ConsoleOf` built from a function that appends to a buffer type-checks
against the same field signature. The row stays an upper bound, so
where a claim has to be checked rather than merely permitted, name the
function at the call.

## Effects

An effect is something a function does besides computing its result:
printing, writing to the heap, allocating. Axiom infers every
function's effects and checks what you declare about them, so a
declaration tells a reader whether a call can reach the outside world.

```scheme
(import IO)

(:: square (-> Int Int))
(fn (square n) (* n n))

(:: report (-> Int Int))
;@axiom:effect(io)
(fn (report n)
  (let ((sq (square n)))
    (println "{n} squared is {sq}")))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (report 7)
    0
  })
```

```text
7 squared is 49
```

`square` has no tag, and it performs no I/O. `report` prints, so it
declares `;@axiom:effect(io)`. So does `main`, because it calls
`report`. Remove the tag from `report` and the compiler rejects it
with `AX3042`.

### How inference works

The compiler works out each function's effects from its body, and it
follows calls all the way down: a syscall three calls deep still
counts. Effects aren't part of a function's type. They're a separate
set, checked against what the declaration says.

- A claim the body contradicts is an error, `AX3010`.
- A claim the compiler can't check is a warning, `AX3037`. See
  [When inference can't answer](#when-inference-cant-answer).
- No tag is a claim too: it says "performs no I/O". A body that does
  I/O under it is an error, `AX3042`.

`IO`, `Entropy`, `Spawn` and `Block` are required all the way up the
call chain: silence says the body does none of them, and a body that
does one draws `AX3042` naming it, even when the declaration already
says `effect(io)`. `Alloc` and `Mut` are inferred and reported, but
callers aren't asked to declare them. `Unsafe` marks the declaration that performs an unsafe operation.
It stops at a trusted wrapper and reaches callers of a precondition
interface. `scripts/check-effect-distribution.sh` measures the effect
split over the compiler and standard library.

You can still declare the ambient effects, and a declaration is
checked. `;@axiom:effect(mut)` over a body that writes a field is
accepted, and over one that doesn't it's `AX3010`. The same holds for
a custom effect.

`Unsafe` is required at the declaration that performs an unsafe
operation (`AX3073`): a raw primitive, a call to a precondition
interface, or a cast that makes a reference out of a value of another
type. Write `;@axiom:effect(unsafe)` above it.

```scheme
(import Mem)

(:: firstWord (-> Int Int))
;@axiom:effect(unsafe)
;@axiom:precondition(`block` names at least one live word)
(fn (firstWord block)
  (memGetWord block 0))
```

The tag alone makes a *trusted wrapper*: it takes responsibility for
making every well-typed call safe, so its callers need no tag. Add
`;@axiom:precondition(...)` when safety depends on the caller, as it
does for `firstWord`. Then every call is the caller's unsafe
operation, and a caller that doesn't say `effect(unsafe)` draws
`AX3073`.

The compiler checks the tags and which casts forge. It can't prove
that a wrapper's checks, or a caller's precondition, are enough.

To see what the compiler inferred, ask `axiom symbols` for its
machine-readable format. The inferred set is `#effects=`, beside any
declared tags. The listing includes the standard library, so filter it
to your file:

```bash
axiom symbols effects.ax --diagnostic-format ai | grep effects.ax
```

```text
F square effects.ax:3:5-11 "(Int -> Int)" @23c60beb9aad6e54
F report effects.ax:6:5-11 "(Int -> Int)" @c9dfa4d37f242eb5 #effect=io #effects=Alloc,IO,Mut,Unsafe
F main effects.ax:12:5-9 "Int" @6159d363201f7f2a #effect=io #effects=Alloc,IO,Mut,Unsafe
```

The default `human` table has no metadata column, so it shows neither.
The full contract for the inferred set is `MM-EXEC-9a` in
[memory-model.md](memory-model.md).

### Built-in effects

| Effect | What performs it |
|---|---|
| `IO` | Reaching the outside world: a `__syscallN`, or reading the command line with `__argc` or `__argv`. The AArch64 reads of registers the hardware owns (`__arm_cntvct`, `__arm_cntfrq`, `__arm_ctr`) and `__arm_wfi`, which waits on the outside world, carry it too (MM-FFI-8). |
| `Pure` | Nothing. `;@axiom:effect(pure)` claims it, and `(handle BODY (Pure) 0)` rejects a body that performs any effect. |
| `Alloc` | Heap machinery, which is wider than allocation. Any call that reaches `__alloc` (every `Vec`, `Map` and `Str` growth, every `memAlloc`), the three arena primitives, and `handle`, which installs its handler's evidence. An arena reset counts because it ends every block allocated since the mark. |
| `Mut` | Heap state that other code can see: a field store `(set base.field v)`, the `__store8` and `__store64` primitives it lowers to, the atomic writers `__atomic_store`, `__atomic_add` and `__atomic_cas`, and `__fence`. That's why `vecPush` and `mapInsert` carry it. `__atomic_load` is a read and doesn't, just as `__load64` doesn't. A `set` on a `mut` local isn't `Mut`, because nothing outside the function can see it. The eight volatile device accesses carry it (a device read can change device state), as do the `__arm_` barriers, timer writes, interrupt masks, cache maintenance and `__arm_set_tpidr` (MM-FFI-8). |
| `Entropy` | Drawing randomness, which makes the answer different from run to run: `__arm_rndr`, and any use of a syscall number tagged `;@axiom:syscall(entropy)`. The platform tables tag `sysRandomNum`, so `Sys.sysRandomBytes`, `IO.randomBytes`, everything in `Crypto.Random` and every key generator perform it. |
| `Spawn` | Starting another binding, thread or process: `parallel` and the spawn primitives it lowers to, and syscall numbers tagged `syscall(spawn)`. The platform tables tag the fork and `posix_spawn` numbers, so `Sys.sysSpawn`, `sysRun` and `sysRunPath` perform it. |
| `Block` | Waiting for another binding, a lock, a child or time: the joins `parallel` lowers to, and syscall numbers tagged `syscall(block)`. The platform tables tag the wait-on-a-word and wait-for-a-child numbers, so `Sys.sysWaitPid`, the blocking `Chan` and `Sync` operations and `sysRun` perform it. |
| `Div` | Divergence. You can write it, but nothing infers it, so `;@axiom:effect(div)` draws `AX3037` (unverifiable), even over a body that plainly never ends. Inferring it would need a termination analysis the compiler doesn't have. |
| `Unsafe` | The thirty-six raw primitives (`MM-EXEC-9c`), the seven `__syscallN` among them, a call to a precondition interface, or a cast that forges a reference (`MM-EXEC-9d`). A declaration performing one must say `;@axiom:effect(unsafe)` (`AX3073`). A declaration that also says `;@axiom:precondition(...)` passes the obligation to callers; otherwise it is a trusted wrapper. |

`Err` isn't a built-in effect. A handle list naming it draws `AX3016`,
as any undeclared name does, and `(effect Err ...)` declares an
ordinary effect. Errors themselves are covered in
[error-model.md](error-model.md).

<a id="annotating-functions-with-effects"></a>

### Annotate a function

Put the tag on the line above the declaration:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println "hello")
    0
  })
```

The compiler checks that the body really performs what the tag
declares.

| Tag | Claims |
|---|---|
| `;@axiom:effect(io)` | The function reaches the outside world. Required when it does. |
| `;@axiom:effect(mut)`, `effect(alloc)`, `effect(unsafe)` | The function performs that ambient effect. `effect(unsafe)` is required for a raw primitive, a precondition call or a forging cast. |
| `;@axiom:effect(console)` | The function performs a custom effect. The value matches the `effect` declaration case-insensitively. |
| `;@axiom:effect(pure)` | The function performs nothing. |

Tags that promise *more* than this, such as `restrict(no-io)` and
contracts, are in [Effect tags](#effect-tags).

<a id="declaring-an-effect-type"></a>

### Declare an effect

Your own effects work like the built-in ones, with one addition: a
handler decides what each operation does.

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

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (handle
      (greet "Ada")
      (Console)
      (lambda (s) { (println "log: {s}") 0 }))
    (handle
      (greet "Grace")
      (Console)
      (lambda (s) 0))
    0
  })
```

```text
log: hello
log: Ada
```

`greet` doesn't know who is listening. The first handler prints each
line, and the second throws them away.

An `effect` declaration makes each operation a callable name. `(log
"hi")` is type-checked against the operation's signature, and at run
time it goes to the innermost handler that's installed.

- **Every operation declares a signature.** `(effect E (op))` is
  `AX3055`, because both the handler check and the call's arity check
  rely on it.
- **Calling an operation performs the effect.** Callers of `log` infer
  `#effects=Console`, transitively, and a `;@axiom:effect(console)`
  claim is checked against that.
- **Operation names share the value namespace.** An operation with the
  same name as a function in its module is a duplicate definition,
  `AX3006` (`tests/diagnostics/455-effect-op-collision.ax`). Across
  modules, the one-bare-name rule in
  [Modules and imports](#modules-and-imports) applies.
- **An operation isn't a value.** Passing `log` bare is `AX3017`. Wrap
  it where you need a function: `(lambda (x) (log x))`.
- **Built-in names are reserved.** An effect named `IO`, `Pure`,
  `Alloc`, `Mut`, `Div` or `Unsafe`, or the lowercase `alloc`, is
  `AX3054`. A handle list reads those names as the built-ins, so such
  an effect could never be handled.

<a id="handling-effects"></a>

### Handle an effect

`(handle BODY (E ...) HANDLER)` runs `BODY`. Its list does two jobs,
decided effect by effect: it *names* every effect the body performs,
and it *intercepts* the declared ones.

Naming is exhaustive. An effect the body performs that the list
leaves out is `AX3011`, and that includes built-ins such as `Alloc`
and `Unsafe`. So the list always describes the region accurately.

A built-in in the list is only acknowledged. The handler expression
isn't evaluated, and the form runs as its body: the syscall still
happens, and the effect still reaches the caller.

```scheme
; Names IO, as AX3011 requires, but doesn't remove it: IO is still in
; the enclosing function's inferred set, and a `;@axiom:effect(pure)` claim
; on that function is contradicted.
(handle (println "hello") (IO Alloc Unsafe) 0)
```

Tested by `tests/diagnostics/348-handle-discharge.ax`.

A declared effect is intercepted for the body's dynamic extent. An
operation performed anywhere inside, at any call depth, runs the
innermost installed handler in its place. The handler's return value
becomes the operation's result, and execution carries on.

The handler is checked against the operation's signature. A lambda
handler's parameters take the signature's parameter types, so `s` in
the example above is a `String` with no `cast`, and its result must
match the signature's result. Any other handler, such as a top-level
function passed bare, a closure or a literal, is checked as it is. A
handler that doesn't fit is `AX3004`: the integer `0` for a
`(-> Int Int)` operation, say, or a lambda returning a `String` where
the operation returns an `Int`
(`tests/diagnostics/386-handler-type.ax`).

The `handle` form has its body's type, so
`(println (handle (ask 1) (Ask) h))` prints the `Int` that `ask`
declares.

The rules that make handlers predictable:

- **Nesting shadows and restores.** The innermost handler wins while
  its `handle` is live. The previous one answers again when it exits.
- **A handler runs under the handlers that were live when it was
  installed.** An operation the handler performs itself goes *outward*
  to the next handler, never back into itself. That matches inference,
  where a handler's own effects propagate past its own `handle`.
- **A multi-argument operation takes a curried handler.** Write
  `(lambda (a) (lambda (b) ...))`, or the flat `(lambda (a b) ...)`,
  which the parser curries into the same chain. Both are checked
  against `(-> A B R)`.
- **Inference subtracts the handled effect.** The body's custom effect
  stops at the `handle`. The handler's own effects count at the
  `handle`, since installing it means it may run, and the form performs
  `Alloc` for the handler's evidence. The list still names every effect
  the body performs: a body whose inner handlers print lists
  `(Console IO Alloc Unsafe)`, though only `Console` is intercepted.

```scheme
(import IO)

(effect Ask
  (ask :: (-> Int Int Int)))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (handle (ask 3 4) (Ask) (lambda (a b) (+ a b))))
    0
  })
```

```text
7
```

#### When nothing handles an operation

An operation performed with no handler in its dynamic extent writes
`axiom: unhandled effect` to stderr and exits with status 71.

The compiler warns where it can see this coming. A `handle` is the
only thing that removes a custom effect, so a custom effect still in
`main`'s inferred set is one nothing handled: `AX3053`, a warning. It's
a warning because two approximations cut both ways:

- A lambda's operations count where the lambda is *written*. A worker
  bound before the `handle` that covers its call is reported, although
  it runs.
- The value of a `handle` form bound with `let` is opaque. A closure
  built inside a `handle` and called after it exits isn't reported,
  although it traps.

If the trap is what you want, as it is for an assertion, put
`;@axiom:unhandled(trap)` on the `effect` declaration to silence the
warning (see [Effect tags](#effect-tags)).

#### Limits

Each of these is a stable diagnostic rather than a miscompile:

- One custom effect per `handle`. Nest `handle` forms for more.
- Only single-operation effects are handled dynamically.
- A handle list naming an undeclared effect is `AX3016`.

*Under the hood:* handlers are evidence-passing and tail-resumptive.
`MM-EXEC-10` in [memory-model.md](memory-model.md) is the contract and
its probe.

### Effect polymorphism

A higher-order function performs whatever its callback performs, and
Axiom tracks that without making you declare it:

```scheme
(import IO)

(:: apply (-> (-> Int Int) Int Int))
;@axiom:effect(pure)
(fn (apply f x) (f x))

(:: shout (-> Int Int))
;@axiom:effect(io)
(fn (shout n)
  {
    (println "n = {n}")
    n
  })

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (apply shout 3)
    0
  })
```

```text
n = 3
```

Its `axiom symbols` rows, filtered to `apply.ax` as before:

```text
F apply apply.ax:3:5-10 "((Int -> Int) -> (Int -> Int))" @9fde5fb4f32622ed #effect=pure #effect-params=f
F shout apply.ax:7:5-10 "(Int -> Int)" @cc70b00d8093fca4 #effect=io #effects=Alloc,IO,Mut,Unsafe
F main apply.ax:15:5-9 "Int" @6159d363201f7f2a #effect=io #effects=Alloc,IO,Mut,Unsafe
```

A function's effects have two halves: what its own body performs, and
its *effect-transparent parameters*. Those are the parameters it
calls, directly, through a `let` alias, or by passing them on to
another function's transparent parameter. `apply` performs nothing
itself and everything `f` performs. `axiom symbols` shows that as
`#effect-params=f`, and each call site fills it in with the argument
it passes, so `main` picks up `IO` from `shout`.

Claims are checked against the body's own half:

- `;@axiom:effect(pure)` on `apply` stands. On a higher-order function, pure
  means pure apart from its function parameters.
- A declared effect the body doesn't perform is accepted when a
  callback could supply it.
- A claimed effect that no declaration introduces at all can never be
  supplied, so it warns regardless.

`restrict(...)` is read differently. "No I/O apart from its function
parameters" isn't what a reader takes `restrict(no-io)` to mean, so a
transitive restriction on a body that calls its own parameter is
`AX3051`, unverifiable. `effect(pure)` describes a body, while a restriction
is a guarantee about calling it. See
[restrict](#restrict---what-a-declaration-does-not-do).

A *reference* to a named function answers for that function's effects
where the reference appears. A lambda literal answers for its body
where the literal is written.

### The unsafe layer

A result type variable that no parameter mentions isn't
polymorphism. The caller chooses what `a` is and nothing checks the
choice, so the signature is an unchecked coercion. The compiler
rejects it with `AX3040`:

```scheme refused
(:: conjure (-> Int a))
(fn (conjure n) (cast a n))
```

If this compiled, `(strWrap (conjure 42) 8)` would read 42 as a
`String` pointer and crash with status 139.

The same hole opens one level in, through a function-typed parameter:

```scheme refused
(:: apply1 (-> (-> a Int) Int))
(fn (apply1 f) (f (cast a 42)))
```

A parameter is a position the caller fills. The left side of an arrow
*inside* that parameter flips back to a position the callee fills:
`apply1` must make an `a` to call `f`, and nothing the caller passes
says what one is. So the rule reads variance. A type variable that the
callee must produce, and that no caller supplies, is refused wherever
it sits.

These are fine:

- `(-> a a)`: the argument supplies the value.
- `(-> (-> Int a) Int)`: the caller's own function produces the `a`,
  which is the shape of ordinary higher-order code.
- `(-> (-> a b) a b)`: witnessed on both counts.
- A function that never returns, such as
  `(fn (panic msg) (cast a (exit 70)))` under `(-> String a)`. Every
  path ends in a call that doesn't return, so no `a` is ever made.

Limit: the rule reads the *signature*, so `(fn (apply1 f) 0)` is
refused too, although it never calls `f`.

When you really do need to read a raw word as a typed value, write a
typed accessor: a function whose declared result names the real type,
with the `cast` at its return. The standard library does this:
`memGetWord` answers `Int`, and `memGetWordStr` is its `String` view.
Callers see the declared type, and reference counting is
computed from it (`MM-VAL-23`). A `cast` at each call site instead
silences the type error but tells the memory model not to trust the
value, which drops its retain or its release (`MM-VAL-22`). Both rules
are in [memory-model.md](memory-model.md). For `cast` itself, see
[Type casting](#type-casting).

A `(Vec a)` reads back its element type with no cast. A vector whose
slots hold different kinds of value still needs one, and `vecGetStr`
is that cast: an unchecked read of a word, which the call names.

The last resort is `;@axiom:raw` on the declaration, which silences
`AX3040`. The tag isn't permission, and it doesn't make the read safe.
It makes the unsafe layer a finite list you can ask for:

```bash
axiom symbols FILE --diagnostic-format ai | grep '#raw'
```

The compiler and standard library carry no `;@axiom:raw` declarations.

<a id="when-the-walk-cannot-answer"></a>

### When inference can't answer

Sometimes the compiler can't see which function a call reaches. Then
the inferred set is a *lower bound*: the body performs at least these
effects, and maybe more. Four shapes cause it:

| Shape | Example |
|---|---|
| A call head that isn't a name | `((b.f) x)`, or an `if` or `match` in head position |
| A `let` bound to anything but a name or a lambda literal | `(let ((g b.f)) (g 7))` |
| A pattern binder | `(match h ((Wrap f) (f 7)))` |
| A value the compiler can't follow, passed to an effect-transparent parameter whose type could hold a function | `(fn (p h b) (h b.f))` |

The first three are one situation written three ways: a function value
goes into a struct, a data constructor or a container in one place and
is called in another.

The fourth is about the argument, not the call. Calling `h` is tracked,
because `h` is a transparent parameter. What isn't tracked is `b.f`,
the value `h` will call. The callee's signature decides whether that
matters. An arrow, a type variable, or a type the checker already
failed on can hold a function. An `Int` can't, because applying one is
`AX3004`. So `(fn (twice f x) (f (f x)))` is complete under
`(-> (-> Int Int) Int Int)`, and the same body is a lower bound under
`(-> (-> a a) a a)`, because a caller may choose an arrow for `a`.

`axiom symbols` marks a lower bound `#effects-incomplete`, and claims
split on it:

- **A claim of absence**, `;@axiom:effect(pure)`,
  can't be checked against a lower bound. It draws `AX3037`, a warning.
- **A claim of presence**, such as `;@axiom:effect(io)`, is accepted.
  The unresolved call may be exactly where the effect comes from.
- **A handle list** can't be checked either. A `handle` whose body
  contains an unresolved call draws `AX3038`, a warning, where
  `AX3011` would be an error. It's worth heeding: if that call reaches
  an operation with no handler, the program exits with status 71.

#### Definite and possible

The opposite case is an effect the body *may* cause without performing
it. One shape produces it: a function-typed name used as a value
rather than called. `(fn (handoff k) shout)` hands `shout` back, and
`(ConsoleOf writeLine)` stores it in a
[capability record](#capability-records).

Every effect of the named function arrives as *possible*: whoever
calls the value may perform it. An effect the body reaches by a call
is *definite*. The same effect can be both, in a body that calls
`shout` and also names it. The compiler tracks this per effect, and
each check reads the half it needs:

- **`AX3042` and a contradicted `AX3010` read the definite half.** An
  untagged function whose `IO` is only possible isn't accused, and
  `;@axiom:effect(pure)` over it draws `AX3037`, as over a lower bound. A
  definite `IO` is accused, whatever else is possible.
- **`AX3011`, a missing `AX3010` and `restrict(...)` read both
  halves.** A handle list names everything the body may reach, and a
  claimed effect the body may perform isn't missing.
- **`axiom symbols`** prints both halves as `#effects=`. When some
  effect is only possible, it adds `#effects-overapprox` and names
  those effects in `#effects-possible=`.

With `shout` from the previous example, `handoff` renders:

```text
#effects=Alloc,IO,Mut,Unsafe #effects-overapprox #effects-possible=Alloc,IO,Mut,Unsafe
```

`shout` itself prints `"n = {n}"` and renders
`#effects=Alloc,IO,Mut,Unsafe` with no admission, because everything
it performs is definite.

Two related cases are lower bounds instead:

- Calling through a record's field, such as `(c.print "hi")`, isn't a
  resolved call. It adds nothing to the set and marks it
  `#effects-incomplete`.
- A call with more arguments than the callee has parameters, such as
  `((handoff 1) n)`, applies the callee's *result*, which the compiler
  can't follow. That row is `#effects-incomplete` too.

<a id="axtag-keys"></a>
### Effect tags

Some tags go further than naming an effect. They make a promise about
a function, and the compiler holds you to it. Write one on the line
above the declaration, like any other `;@axiom:` tag.

| Tag | Promise | Checked |
|---|---|---|
| `restrict(...)` | this function never does the listed things | at compile time |
| `isr` | an interrupt entry point: no parameters, no allocation | at compile time |
| `pre(...)`, `post(...)` | a condition on the arguments, or on the result | on every call, at run time |
| `unhandled(trap)` | reaching this effect with no handler is a deliberate abort | at compile time |
| `precondition(...)` | beside `effect(unsafe)`: what a caller must make true for a call to be safe, so every call is the caller's unsafe operation | at compile time, that it is stated (`AX3079`, `AX3080`); the condition itself is the caller's to meet |
| `ct(...)` | the function's timing doesn't depend on the named parameters: `key` for a secret value, `*buf` for an address whose memory is secret | at compile time (`AX3092`, `AX3093`) |
| `nolint(...)` | quiet the editor's lint Hints for this declaration | by the language server |

The compiler knows ten keys: `effect`, `raw`, `pre`, `post`,
`restrict`, `isr`, `unhandled`, `precondition`, `ct` and `syscall`. The last
belongs on a platform module's syscall number, as in
`;@axiom:syscall(block)`, and says what the call behind the number
does, so every function that names the number performs that effect. Any other key is
metadata: the compiler records it and doesn't check it, so
`agent:readonly` draws nothing.

**Purity is `effect(pure)`.** An effect claim is always an
`effect(...)` tag, and purity has that one spelling.
`;@axiom:pure`, and a slip of it such as `;@axiom:pur`, is `AX3078`
wherever it stands.

**A checked key belongs on its declaration.** `effect`, `raw`, `pre`,
`post`, `restrict`, `isr`, `precondition` and `ct` are checked on a
function, above its `(:: ...)` or its `(fn ...)`, and `unhandled` on
an `effect` declaration. Above a `data`, a `struct`, an import, a
macro or an alias, the claim would be recorded and never read, so it
is `AX3077`.

**One effect per tag.** A body that performs two effects declares
them on two lines, `;@axiom:effect(io)` and `;@axiom:effect(unsafe)`.
A list inside one tag — `effect(io, unsafe)` or `effect(io unsafe)` —
is `AX3076`: it reads as one custom effect spelled with the comma,
and `AX3010` reports it missing from a body that performs both.
`restrict(...)` is the tag that takes a comma list.

An effect's name is not a value. `IO`, a declared `Console`, or
`handle` where an expression goes is `AX3001`, as `Unsafe` and the
keywords always were.

A key one edit or one change of case away from a known key draws
`AX3039`, a warning that suggests the key you probably meant. A
misspelt key makes no claim, so nothing checks `;@axiom:efect(io)` as
an effect claim. A key containing `:` is never reported, because a
namespaced key is always intentional. The known keys are never
reported as near misses of each other, or of `pure`, so `pre` is safe
even though it is one letter from `pure`.

<a id="restrict---what-a-declaration-does-not-do"></a>
### restrict: what a function never does

`;@axiom:restrict(...)` promises that a function never does something:
never performs IO, never allocates, never recurses. The compiler
answers the promise from the effect and call-graph analysis it already
runs.

```scheme
(import IO)

;@axiom:restrict(no-io, no-alloc, no-recursion)
(:: clamp (-> Int Int Int Int))
(fn (clamp lo hi x)
  (if (< x lo) lo (if (> x hi) hi x)))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((n (clamp 0 10 42)))
    {
      (println "clamped to {n}")
      0
    }))
```

```text
clamped to 10
```

When a function breaks its promise, the error names the path from the
function to the place where the effect enters:

```scheme refused
(import IO)

(:: logLine (-> String Int))
;@axiom:effect(io)
(fn (logLine s) { (println s) 0 })

(:: readSection (-> Int Int))
;@axiom:effect(io)
(fn (readSection n)
  { (logLine "reading") n })

;@axiom:restrict(no-io)
(:: parseConfig (-> Int Int))
;@axiom:effect(io)
(fn (parseConfig n) (readSection n))

(:: main Int)
;@axiom:effect(io)
(fn (main) (parseConfig 0))
```

```text
error[AX3049]: `parseConfig` claims `restrict(no-io)` and the body performs IO: parseConfig -> readSection -> logLine -> IO$writeStr -> Sys$sysWriteAllFd -> Sys$sysWriteFd -> __syscall3
```

#### The restrictions

The list is closed. A name that isn't on it is `AX3052`, an error,
because an unknown name inside `restrict(...)` would read like a
guarantee that nothing checks. Separate names with commas inside one
`restrict(...)`.

| Restriction | The function… | Scope |
|---|---|---|
| `no-io` | has no `IO` in its effect row | transitive |
| `no-alloc` | has no `Alloc` in its effect row | transitive |
| `no-unsafe` | performs no unsafe operation, including through a callee without a trusted boundary | transitive to a trusted boundary |
| `no-foreign` | reaches no `extern` item through the call graph | transitive |
| `no-recursion` | reaches no cycle in the call graph | transitive |
| `no-cast` | writes no `cast` in its own body | local |
| `no-cast:deep` | writes no `cast`, and reaches no function that does | transitive |
| `no-wrap` | writes no integer `+`, `-` or `*` | local |
| `no-trap` | writes no integer `/`, `%`, `<<` or `>>` | local |
| `no-escape` | lets nothing it allocates flow into one of its parameters | transitive |
| `no-entropy` | has no `Entropy` in its effect row, so it answers the same on every run | transitive |
| `no-spawn` | has no `Spawn` in its effect row, so it starts no binding, thread or process | transitive |
| `no-block` | has no `Block` in its effect row, so it never waits on another binding, a lock or a child | transitive |
| `strict` | a modifier, not a restriction: see [strict](#make-an-unproven-claim-an-error-with-strict) | |

A *transitive* restriction covers everything the function calls. A
*local* one covers only the code written in this body. The difference
follows from what each one reads:

- `no-io` and `no-alloc` read the transitive effect row: a function
  that calls an IO-performing function has `IO` in its own row.
  `no-unsafe` follows unsafe operations through callees, and stops at
  a trusted encapsulation (`MM-EXEC-9d`).
- `no-foreign` walks the call graph that `symbols --calls` prints. The
  row can't tell IO through a syscall from IO through an `extern`, and
  the graph can.
- `no-recursion` looks for a cycle, which is a property of the whole
  graph. The error shows the cycle, such as
  `ping -> pong -> pang -> ping`, or `entry -> countdown -> countdown`
  when the cycle is below the function. A `while` loop isn't
  recursion. A function under `no-recursion` has a stack need bounded
  by its call depth, whatever its input.
- `no-escape` reads the region facts described in
  [Region annotations](#region-annotations). A callee that grows its
  argument, such as `vecPush`, refutes it. A call the walk can't
  resolve leaves it unverifiable.
- `no-cast` is local because a cast is something a body does, not a
  property that spreads to callers. The error points at the cast, and
  a callee's casts are the callee's business. The standard library
  casts widely, so a transitive `no-cast` would refuse nearly every
  program that uses it. Spell `no-cast:deep` when you want that: it
  reports this body's casts where they are, and the nearest reachable
  function that casts, once, at the declaration, with the path.
  `sizeof` and `alignof` aren't casts.
- `no-wrap` is local for the same reason. On `Int` operands, `+`, `-`
  and `*` wrap silently with no overflow check, so the error points at
  the operator you wrote.
- `no-trap` is local too. On `Int` operands, `/` and `%` trap on a
  zero divisor (exit 72) and on the `INT_MIN / -1` corner (exit 83),
  and `<<` and `>>` trap on an out-of-range shift amount (exit 84).
  Called `no-untrapped` until 0.8.0, when those corners were
  undefined; the guards landed and the rename followed them.

`stdlib/Err.ax` has checked alternatives for all seven operators:
`addChecked`, `subChecked` and `mulChecked` for `no-wrap`, and
`divChecked`, `remChecked`, `shlChecked` and `shrChecked` for
`no-trap`. Each has the type `(-> Int Int (Result Int Error))`.
Building the `Result` allocates, so calling one puts `Alloc` in your
function's row. That means a body that needs arithmetic can't keep
`no-wrap` or `no-trap` together with `no-alloc` or `effect(pure)`. The
design note is [checked-arithmetic-design.md](checked-arithmetic-design.md).

Two things that look like these operators can't wrap, so neither is
refused:

- `+`, `-`, `*` and `/` on `Float` operands. A `Float` `+` nested
  inside an `Int` `+` still reports the outer operator.
- The counter increment of a `for` loop, which the parser writes for
  you. The loop's guard stops the counter before it can pass
  `INT_MAX`. A loop you write out by hand is still refused, and so is
  arithmetic in a `for` loop's body.

Tested by `tests/diagnostics/394-restrict-no-wrap-exempt.ax`.

#### Read a violation

A broken promise is `AX3049`, an error with no warning stage. The tag
is a claim you wrote, and a build that ships a false claim publishes a
guarantee the program doesn't keep. Deleting the tag silences the
error by withdrawing the claim: the compiler never asks an unrestricted
function.

Every transitive violation names its path. The checker searches the
call graph breadth-first from your function to the nearest place where
the effect enters:

- a syscall primitive, such as `__syscall3`
- an `extern` item
- a builtin whose row the compiler seeds, such as `__argc` or `__alloc`
- a function whose own body brings the effect in with a constructor or a
  `handle`, which the message says ("in `makes`'s own
  body")

The hops use the spellings `symbols --calls` prints, including
`Mod$name` for a function from another module, so you can check the
path against `#calls=` hop by hop.

A restriction never changes the code the compiler emits.

Tested by `tests/diagnostics/371-restrict-no-io.ax` to
`379-restrict-no-recursion.ax`, each beside controls that must stay
silent.

#### When the walk can't settle a claim

Sometimes the checker can't tell whether a function keeps a transitive
restriction. That's `AX3051`, a warning, and it happens in three ways:

- The effect is absent from a row that is only a lower bound
  (`#effects-incomplete`), because the body calls something the walk
  couldn't resolve.
- The effect is present only as a *possible* effect
  (`#effects-possible=`), because the body names a function without
  calling it.
- The body calls one of its own parameters (`#effect-params=f`), so
  what it performs depends on the argument each caller passes.

`no-escape` has a fourth: the region analysis hit its round limit
before its facts settled.

An effect that is present in a lower-bound row, or definite beside a
possible one, is a violation, `AX3049`. So is a body that performs the
effect itself and also calls a parameter.

The third case is where `restrict` and `effect(pure)` part ways. `;@axiom:effect(pure)`
on `(fn (apply f x) (f x))` stands, because purity describes a body
and "pure apart from its function parameters" is what purity means for
a higher-order function. A restriction is a promise about calling the
function, and nobody reads `restrict(no-io)` as "no IO apart from its
parameters". So this function gets a warning:

```scheme
(:: runIt (-> (-> String Int) Int Int))
;@axiom:restrict(no-io)
(fn (runIt f n) { (f "x") n })
```

```text
warning[AX3051]: `runIt` claims `restrict(no-io)` and the claim cannot be checked: the body CALLS its own parameter `f`, so what it performs is decided by the argument each caller passes - the effect row is complete about this body and says nothing about that call
```

The same goes for `no-recursion`: a cycle that runs through a
parameter, such as `runIt -> back -> runIt`, has an edge the graph
can't see.

The walk marks a row incomplete conservatively. A call whose head is
an `if` or `match` is incomplete even when every arm is a named
function, whose effects still count. So is a call to a lambda's own
parameter, and a call to a `let` name bound to a closure that another
call returned, even when the walk has already seen that closure. One gap remains: passing an
effect-polymorphic function itself as a callback doesn't instantiate
that function's parameter marks, because that is a higher-rank flow.

The local restrictions, `no-cast`, `no-wrap` and `no-trap`, never
draw `AX3051`. They read only the body's own code, which a parameter
can't change.

<a id="make-an-unproven-claim-an-error-with-strict"></a>
#### Make an unproven claim an error with strict

Add `strict` when an unproven claim should stop the build:

```scheme refused
;@axiom:restrict(no-io, strict)
(:: runIt (-> (-> String Int) Int Int))
(fn (runIt f n) { (f "x") n })
```

```text
error[AX3057]: `runIt` claims `restrict(no-io, strict)` and the claim cannot be PROVEN: the body CALLS its own parameter `f`, so what it performs is decided by the argument each caller passes - the effect row is complete about this body and says nothing about that call
```

Now the claim the walk can't settle is `AX3057`, an error, in place of
`AX3051`. The default is a warning because calling through a stored
function is a correct program the walk can't follow, and refusing it
would make that shape impossible to write under any restriction. On a
sensitive operation, though, a reader who sees `restrict(no-io)` will
assume it was checked. `strict` makes sure it was.

`strict` names nothing a body must not do, so `restrict(strict)` on its
own restricts nothing and is silent. It isn't an unknown name, so it
never draws `AX3052`. A claim the walk refutes is still `AX3049`, and a
claim the walk settles and finds kept is silent.

Tested by `tests/diagnostics/393-restrict-strict.ax`.

#### Where a restriction attaches

A restriction belongs to the declaration below it. You can write it on
the `::` signature or on the `fn`, and the compiler reads both as one
set. `axiom --diagnostic-format=ai symbols` shows it on the function's
row, such as `#restrict=no-io,no-alloc`.

There's no module-wide form. A tag above `(import IO)` attaches to the
import and to no function. To restrict a whole module, tag each
declaration.

A restriction doesn't replace an effect annotation. A restricted
function that performs IO without `;@axiom:effect(io)` draws `AX3042`
like any other, and `restrict(no-io)` over it draws `AX3049` as well.

<a id="isr---an-interrupt-entry-point"></a>
### isr: an interrupt entry point

`;@axiom:isr` marks a function that hardware calls by name, with no
arguments, and that must not allocate. Build the file as a static
library and every `pub fn` becomes a C symbol under its own name:

```scheme
(pub :: ticks Int)
(pub fn (ticks) 0)

(pub :: onTimer Int)

;@axiom:isr
(pub fn (onTimer) (+ (ticks) 1))
```

```bash
axiom build --input timer.ax --output timer.a --emit-staticlib
```

```text
Build successful: timer.a
```

The tag makes three promises, and the compiler checks all of them:

- No parameters: a parameterised `isr` draws `AX3010` at the
  declaration.
- No allocation: the tag adds `no-alloc` to the function's
  restrictions, so an allocating `isr` draws `AX3049` naming
  `no-alloc`, with the same path, the same `AX3051` warning when the
  walk can't settle it, and the same `strict` behaviour. Writing
  `restrict(no-alloc)` as well is checked once.
- No recursion: the tag adds `no-recursion` the same way. A handler
  runs on a stack it doesn't own, so its depth must be one the stack
  bound can compute.
- No waiting: the tag adds `no-block` too. A handler that waits for a
  lock or a child waits with the interrupted code stopped underneath
  it, which is how an interrupt deadlocks.

Only `pub` functions become symbols, but a private `isr` is checked
too, so the tag protects a helper that nobody calls from C.

**`isr(irq)` binds the function to a vector.** On `baremetal-aarch64`
every executable carries an exception vector table, and
`;@axiom:isr(irq)` makes the tagged function the IRQ vector's handler.
The vector saves the interrupted code's caller-saved registers and
calls the handler with IRQs masked and no recovery point armed. Then
it restores the registers and `eret`s. [memory-model.md](memory-model.md) MM-EXEC-18 has
the rules: no nesting, no allocation, and state shared only through
the unsafe layer, with the main loop masking around multi-word reads.
A handler bound to a vector may not wait: a path to `__arm_wfi` or to
a system call is `AX4009`. Every vector that isn't bound (a
synchronous fault, an SError, an unbound IRQ) writes the fault's
registers on the UART and exits with status **81**.

**`isr(fault)` binds your fault policy.** The tagged function, of type
`(-> Int Int Int Int Int Int)`, is called once after any unhandled
CPU exception or unrecovered trap, with the status the fixed exit
would answer, the vector offset (-1 for a trap), ESR, ELR and FAR. Its
answer is the exit status, or it never returns: a halt, or a reset.
It runs on its own stack with interrupts masked, may halt in `wfi`,
and is refused a system call (`AX4009`) and any other shape
(`AX3010`). A fault inside it takes the fixed 81 without calling it
again ([memory-model.md](memory-model.md) MM-EXEC-19).

Each binding is refused as `AX4008` on any other target, for a vector
name other than `irq` or `fault`, and for a second function bound to
the same one: a handler dispatches on the interrupt id inside it.
[embedded-guide.md](embedded-guide.md) is the whole story.

Tested by `tests/diagnostics/651-isr-params.ax` and
`tests/diagnostics/652-isr-alloc.ax`.

<a id="pre--post---a-claim-the-compiler-cannot-decide"></a>
### Contracts: pre and post

A contract states a condition on a function's arguments (`pre`) or its
result (`post`). The compiler builds the check into the function, and
it runs on every call:

```scheme
(import IO)

;@axiom:pre((> n 0))
;@axiom:post((>= result 0))
(:: half (-> Int Int))
(fn (half n) (/ n 2))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((a (half 9)))
    {
      (println "half of 9 is {a}")
      (half 0)
    }))
```

```text
half of 9 is 4
axiom: precondition failed in `half`: (> n 0)
axiom: backtrace (most recent call first)
  at __axiom_contract_fail
  at __axiom_user_main contract.ax:14:8
  at main
```

The program exits with status 80, the contract trap's own status. The
runtime reserves statuses 70 to 80 for its traps, and `MM-EXEC-16` in
[memory-model.md](memory-model.md) lists them. A failed `post` prints
the same kind of line, such as
``axiom: postcondition failed in `dec`: (> result 0)``. There is no
flag to turn the checks off.

Contracts are checked at run time because `(> n 0)` is a statement
about a value, and the compiler does no value analysis. A claim that
nothing checks would be a comment, so the check goes into the body, as
Ada does it.

| | |
|---|---|
| Where | On the `::` or on the `fn`. Both are read as one list, in source order. Every `pre` and every `post` is checked, in the order written. |
| Scope | The parameters, in both. `result` too, in a `post`. |
| Type | `Bool` |
| Effects | None. The expression's row must hold no definite effects. |
| Refused by | `AX3050`, an error |
| Cost | A `post` costs the tail-call rewrite. |

A contract may not have effects. It runs on every call, so one that
allocates or writes would change the program just by being stated.
That includes `Alloc`. A contract may compare, index, measure and test, but it may
not build: `vecLen`, `vecGet`, `strLen`, `strEq`, `strByte` and
`memGetWord` carry no effects, while `strConcat`, `fmtInt` and `vecNew`
carry `Alloc,Mut`. Only a definite effect is refused. Naming a function
without calling it makes an effect only possible, and naming performs
nothing.

In a `post`, `result` is the function's answer. Its type is the
declared result: the `::` signature with one arrow peeled off for each
parameter the definition names. `result` names nothing in a
`pre`, which runs before the body, or on a declaration with no `::`.
Both are `AX3050`. There's no `'Old` as in Ada: parameters can't be
reassigned (`AX3012`), so a scalar parameter means the same in the
`post` as in the `pre`. A `post` can't see a change made through a
reference parameter, such as a `memSetWord` into a struct the caller
still holds.

A `post` has a cost. To check the body's value, the compiler binds it
with a `let`, and a `let`'s initialiser isn't a tail position. So a
self-recursive function under a `post` loses the rewrite that turns
its tail call into a loop. A `pre` runs before the body and costs
nothing.

Tested by `tests/diagnostics/385-contract-malformed.ax` (six refusals,
five controls) and `tests/selfhost/132-contract.ax`, which includes a
call 200,000 deep under a `pre`. The design note is
[contracts-design.md](contracts-design.md).

<a id="unhandledtrap---an-effect-whose-unhandled-operation-is-the-design"></a>
### unhandled(trap): an effect that may abort

When your program can reach an effect operation with no handler
installed, the compiler warns with `AX3053`. At run time, that
operation writes `axiom: unhandled effect` and exits with status 71.
Sometimes that abort is exactly what you want. Say so with
`;@axiom:unhandled(trap)` above the `(effect ...)` declaration:

```scheme
;@axiom:unhandled(trap)
(effect Abort
  (abort :: (-> String Int)))

(:: checked (-> Int Int))
(fn (checked n)
  (if (< n 0) (abort "negative input") n))

(:: main Int)
(fn (main) (checked 3))
```

This compiles without a warning, and `(checked -1)` would stop the
program with status 71.

- It's the one tag that belongs to an effect declaration, not to a
  function or a signature.
- The value must be exactly `trap`. Any other value, such as
  `unhandled(abort)`, leaves the warning on. A misspelt key draws
  `AX3039` at the effect declaration.
- `axiom --diagnostic-format=ai symbols` shows the tag on the effect's
  row as `#unhandled=trap`, so a policy check can list every effect a
  program allows to abort.

The standard library's `Assert` effect, in `stdlib/Test.ax`, carries
the tag. `axiom test` runs each test inside its own recovery point, so
an unhandled `assertFail` ends that one test and the tests after it
still run. `Fallible`, in `stdlib/Fallible.ax`, doesn't carry it: an
unhandled operation there is a programmer error, so a batch loop that
forgets its handler is named at compile time.

<a id="nolint---quieting-the-editors-hints"></a>
### nolint: quiet the editor's Hints

The language server publishes three lints as LSP Hints:
`lint-dead-branch`, `lint-bool-if` and `lint-unused-let`. `axiom
check` never emits them. `;@axiom:nolint(...)` quiets one for the
whole declaration below it:

```scheme
;@axiom:nolint(lint-unused-let)
(:: area (-> Int Int Int))
(fn (area w h)
  (let ((unused 0))
    (* w h)))

(:: main Int)
(fn (main) (- (area 2 3) 6))
```

`;@axiom:nolint(all)` quiets every lint. As with `restrict`, you can
write the tag on either half of a `::`/`fn` pair.

The compiler treats `nolint` as metadata and says nothing about it. A
lint name it doesn't recognise is ignored, so a misspelt name shows up
as the Hint it failed to quiet. See [lsp.md](lsp.md) for the lints
themselves.

Tested by `tests/lsp/103-lint-nolint.ax`.

## Modules and imports

Split a program across files. Each file is a module, and `(import ...)`
brings another module's public names into scope.

```scheme
; Math/Ops.ax
(pub :: square (-> Int Int))
(pub fn (square x) (* x x))
```

```scheme fragment
; main.ax
(import IO)
(import Math.Ops (square))    ; bring in `square` only

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (square 5))
    0
  })
```

```bash
axiom run main.ax
```

```text
25
```

A module's name is its path with dots for slashes: `Math.Ops` is the
file `Math/Ops.ax`. `(import Math.Ops)` with no name list brings in
every `pub` declaration, and `(import Math.Ops (square))` brings in
only the names you list.

### Visibility

Every declaration is private to its file unless you mark it `pub`.
Only `pub` names can be imported.

```scheme
(pub :: square (-> Int Int))  ; public: other modules can import it
(pub fn (square x) (* x x))

(:: helper (-> Int Int))      ; private: visible only in this file
(fn (helper x) (+ x 1))
```

`pub` goes first, inside the declaration's own parentheses:

| Private | Public |
|---|---|
| `(:: name type)` | `(pub :: name type)` |
| `(fn (name args) body)` | `(pub fn (name args) body)` |
| `(data Name ...)` | `(pub data Name ...)` |
| `(struct Name ...)` | `(pub struct Name ...)` |
| `(macro (name pat) body)` | `(pub macro (name pat) body)` |

`pub` decides which names leave a module, not what the program
contains. A module's own code always reaches its private helpers,
wherever the module is imported, so making a helper private never
changes what the module does.

Naming a declaration that a module doesn't export is `AX3023`, and the
message says which module the name belongs to. Macros follow the same
rule: a macro without `pub` is `AX3023` where it's invoked, and a name
list that asks for a private macro is refused at the import.

The one exception is `effect`. An operation's name carries no module,
so an effect declaration is always exported, and any importer can call
its operations.

Tested by `tests/diagnostics/485-qualified-private-macro.ax`.

<a id="how-imports-work"></a>
### Import a module

- `(import Mod.Sub)` makes every `pub` top-level declaration of
  `Mod/Sub.ax` visible.
- `(import Mod.Sub (a b))` makes only `a` and `b` visible. The module's
  other `pub` names stay out of scope.
- The name list is checked at the import. A name the module doesn't
  declare, or declares without `pub`, is `AX3023` on the import form,
  and the message says which of the two it is.
- Imports are transitive. If `A` imports `B` and `B` imports `C`, then
  `C`'s public declarations reach `A` too.
- Diamonds are safe. When two modules both import `C`, the program
  contains `C` once.
- The compiler looks for `Mod/Sub.ax` starting from the entry file's
  directory. [Where modules are found](#where-modules-are-found) has
  the full order.

Tested by `tests/diagnostics/440-import-name-list.ax`.

### Qualified names

An imported name joins your file's top-level namespace, so you
normally call it bare. Write `Mod::name` to say which module you mean:

```scheme
(import IO)
(import Str)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (Str::strLen "hello"))
    0
  })
```

This prints `5`. The module part is the whole dotted name, as in
`Math.Ops::square`. A qualified name still respects the import's name
list: after `(import Math.Ops (square))`, a reference to
`Math.Ops::cube` is `AX3023`.

When two imported modules export the same name, a bare reference to it
is `AX3014`. The compiler suggests both qualified spellings, and either
one resolves it.

Your entry file may declare a function with an imported name, such as
its own `strLen`. Your file's references then reach your function. A
module's references never do, because a module can't import your
file, so `println` still measures strings with `Str`'s `strLen`.

Tested by `tests/stdlib/573-entry-name-shadows-import.ax`.

Type names follow their own lookup. A bare type name such as `Config`
means, in order:

1. a declaration in the module that mentions it;
2. a declaration with no module: one in the entry file, or a built-in
   type like `Option`;
3. the one imported module that declares it.

If two modules declare `Config` and the module that mentions it
declares neither, the reference is `AX3044`, naming both modules. To
fix it, import one of them with a name list that leaves `Config` out,
or rename one of the declarations. `Mod::Name` also works in type
position, as in `(-> Geo::Point Int)`.

Tested by `tests/selfhost/1002-qualified-type.ax`.

<a id="the-search-order-stated-exactly"></a>
### Where modules are found

The compiler looks for a module in a list of directories. The first is
the entry file's own directory: the file you passed to `check`,
`build`, `run` or `emit-llvm`, not the file that contains the
`import`. So a module in a subdirectory reaches a sibling of the entry
file by the same name the entry file would use. If `sub/Mid.ax`
imports `Helper`, it finds the `Helper.ax` beside `main.ax`.

The rest of the list comes from your project and your environment:

- `axiom.pkg`'s `depend` and `crate` lines add the project's own
  dependencies (see [Packages](#packages)).
- `AXIOM_PATH` adds more directories, separated by colons.
- `AXIOM_STDLIB` says where the standard library is. Without it, the
  compiler finds the library beside its own binary.

A module's file name is tried with three suffixes, most specific
first. Every directory is searched for one suffix before the next
suffix is tried:

```text
for suffix in .<os>-<arch>.ax, .<os>.ax, .ax:
    for dir in  the entry file's own directory
                each `depend` in axiom.pkg, in file order
                DIR/axiom/ for each `crate DIR` in axiom.pkg, in file order
                each $AXIOM_PATH entry, in order
                DIR/axiom/ for each --crate DIR
                $AXIOM_STDLIB, or the stdlib beside the binary:
        if <dir><module><suffix> is a readable file, that is the module
```

The manifest's entries sit above `AXIOM_PATH` because the manifest
travels with the source and the variable travels with the shell. A
`--crate` flag sits below both: it's something you typed, not something
the project declared.

Two things follow from this order:

- Your own file can shadow a standard-library module of the same name,
  but only from the entry file's directory, and only at the same
  suffix. A `depend` or `crate` that would displace a library module is
  refused (see [Packages](#packages)).
- A more target-specific file anywhere on the list beats a less
  specific one nearer the entry file. On macOS, a project's own
  `Sys/Platform.ax` loses to the library's `Sys/Platform.darwin.ax`.
  That's how one `(import Sys.Platform)` finds the right file for each
  target.

Tested by `scripts/check-packages.sh`.

### When an import fails

| Code | What it means |
|---|---|
| `AX5001` | The module path doesn't resolve to a file. It's reported before type checking, and the help lists every file name and directory that was tried. |
| `AX3023` | The module doesn't declare the name, or doesn't export it. Reported at the import's name list, or where the name is used. |
| `AX3014` | Two imported modules export the same name, and the reference doesn't say which. |
| `AX3044` | Two modules declare the same type name, and the reference doesn't say which. |

Two declared dependencies that provide the same module are refused
before compilation, naming both files and the manifest (see
[Packages](#packages)).

In a multi-file build, a diagnostic names the file it came from and
points at that file's own text, in the `human`, `ai` and `json`
formats alike. An error in the third of four files is reported against
the third file.

## Packages

A project is a directory with an `axiom.pkg` manifest beside its
source. The manifest names the program, its entry file and its
dependencies, and it travels with the code.

<a id="projects"></a>
### Start a project

`axiom new` creates a directory holding a hello-world program and a
manifest that names it:

```text
$ axiom new hello
Created new Axiom project in `hello` (Main.ax, axiom.pkg)
$ cd hello
$ axiom run
Hello from Axiom! 🚀
$ axiom build
Build successful: hello
```

The manifest it writes:

```text
name     hello
version  0.1.0
# `depend` names a directory of modules (or a git URL to check out
# under `.axiom/deps/`), `crate` a native crate directory, `opt` the
# default optimisation level (0-3) and `main` the entry file.
# depend  vendor/lib
# opt     1
```

Inside a project, `run` and `build` need no file name. `run` compiles
and runs the entry file. `build` writes the executable in the working
directory under the manifest's `name`, so `axiom build` above writes
`hello`.

A bare operand is always a file, never an argument for your program.
In a project directory, put program arguments after `--`:

```bash
axiom run -- --port 8080
```

With no manifest in the working directory or above it, both commands
need a file, and say so: `run needs an input file`.

### The manifest

`axiom.pkg` holds one `key value` pair per line. Any run of spaces or
tabs separates the key from its value, `#` starts a comment, and blank
lines are ignored. The compiler uses the nearest `axiom.pkg` in the
entry file's directory or up to eight directories above it. Paths in
it are resolved against the manifest's own directory, so the project
can move.

| Key | Takes | What it does |
|---|---|---|
| `name` | a word | The file `axiom build` writes when neither `--output` nor `-o` is given. Without a manifest, that file is `output`. |
| `version` | a word | Recorded. Nothing reads it yet. |
| `depend` | a directory, or a git URL | A directory of modules to search. Write one line per dependency. |
| `crate` | a crate directory | A native Rust dependency: its generated module and its archive. |
| `opt` | `0` to `3` | The project's default optimisation level. `--opt` wins when you give it. |
| `main` | a file | The entry file. Without it, the entry is `Main.ax` beside the manifest. |

Because `name` becomes a file name, it may hold only letters, digits,
`.`, `-` and `_`, and it can't be `.` or `..`. A name such as
`../escaped` is refused, never turned into a path.

A line that can't mean what it says is refused at `axiom.pkg:LINE`,
with exit status 3, before anything compiles:

- an unknown key;
- a key with no value;
- a second `name`, `version`, `opt` or `main` (`depend` and `crate`
  repeat freely);
- a `name` that isn't a file name, or an `opt` outside 0 to 3.

```text
$ axiom check app.ax ; echo $?
error: ./axiom.pkg:2: unknown key `dependd`
       The manifest's keys are `name`, `version`, `depend`, `crate`, `opt`
       and `main`, and `#` starts a comment. An unknown key used to be ignored, which
       made a misspelled `depend` report as every module it would have
       provided going missing - one at a time, naming this file never.
3
```

When `run` or `build` is given no file and the entry file doesn't
exist, the command is refused, naming the manifest and the file it
wanted.

### Depend on a directory of modules

Give each directory its own `depend` line:

```text
# axiom.pkg
name     myapp
version  0.1.0

depend   vendor/axiom-json
depend   ../shared/modules
```

Each `depend` joins the module search path after the entry file's
directory and before `$AXIOM_PATH` (see
[Where modules are found](#where-modules-are-found)). When a declared
dependency and the environment could both provide a module, the
declared dependency wins. A `depend` whose directory doesn't exist is
refused.

Two dependencies may never provide the same module. Otherwise the first
would win silently, and the other's modules would compile against
declarations they never named. The manifest is refused before anything
compiles:

```text
$ axiom check app.ax ; echo $?
error: two dependencies in ./axiom.pkg provide the module `Widget`:
       ./a/Widget.ax
       ./b/Widget.ax
       One of them would win by declaration order and the other's
       modules would compile against declarations they never named.
3
```

The rule covers `crate` directories too, and nested modules as deep as
`A.B.C`. Two dependencies that each hold `Sub/Widget.ax` are refused,
and the message names the module the way an import spells it:
`Sub.Widget`.

A dependency may not provide a standard-library module either.
Dependencies sit above the library in the search order, so a
dependency's `Fmt.ax` would replace the real one for the whole
program, in every module that imports `Fmt`. The manifest is refused,
naming both files. A module in the entry file's own directory still
shadows a library module, because that's a file you wrote.

### Depend on a Rust crate

`crate` names a crate directory: a `Cargo.toml` beside an `axiom/`
directory holding the generated binding module. `DIR/axiom/` joins the
module search path in `depend`'s slot. `DIR/target/release`, and a
workspace's `target/release` one or two levels up, join the link
search path, as they do for `--crate DIR`. So the archive is found and
linked with no flag:

```text
$ cat axiom.pkg
name  myapp
crate vendor/axiom-greeter
$ axiom build app.ax
Build successful: myapp
```

The manifest refuses three things before anything compiles: a crate
directory that isn't there, one with no `Cargo.toml`, and one with no
`axiom/`.

A manifest `crate` never runs cargo. `--crate DIR` on the command line
does: it regenerates a stale binding module and builds a missing
archive (see [Linking and the driver](ffi.md#12-linking-and-the-driver)). A command line is
you asking. A manifest is a file that arrives with a clone, and the
compiler never runs code because a file asked it to (see
[Macros](#macros)).

So build the crate once, with `cargo build --release` or one
`axiom build --crate DIR`, and the manifest carries it from then on.
An archive that isn't built yet is `AX4004`, and its help says what to
run.

Tested by `scripts/check-packages.sh`.

<a id="registry-dependencies"></a>
### Depend on a git repository

A `depend` can name a git URL instead of a directory, which makes it a
*registry dependency*. The URL starts with `https://`, `http://`,
`ssh://`, `git://`, `git@` or `file://`.

```text
# axiom.pkg
name     hello
version  0.1.0
depend   https://github.com/example/axiom-greeter.git
```

The compiler never fetches code by itself. `axiom fetch` does, when you
ask: for every `depend` URL in the nearest manifest, it clones a
checkout if none is there, and leaves an existing one alone.

```text
$ axiom fetch
fetching ./.axiom/deps/github.com-example-axiom-greeter-e1d118389ae2db5e5b06a6258203b7fa/
$ axiom fetch
present ./.axiom/deps/github.com-example-axiom-greeter-e1d118389ae2db5e5b06a6258203b7fa/
$ axiom build
Build successful: hello
```

Until the checkout exists, a build is refused, and the message says
how to make it:

```text
$ axiom build
error: ./axiom.pkg names a dependency directory that is not there:
       ./.axiom/deps/github.com-example-axiom-greeter-e1d118389ae2db5e5b06a6258203b7fa/
       `depend` names a DIRECTORY of modules, resolved against the
       manifest's own directory.
       `https://github.com/example/axiom-greeter.git` is a registry dependency: check it out with `axiom fetch`,
       or by hand with
       git clone https://github.com/example/axiom-greeter.git ./.axiom/deps/github.com-example-axiom-greeter-e1d118389ae2db5e5b06a6258203b7fa/
```

The checkout lives at `.axiom/deps/<key>/` beside the manifest. The key
starts with a readable slug: the URL without its scheme, one trailing
`/` and one trailing `.git`, with every byte outside letters, digits,
`.`, `_` and `-` turned into `-`, and cut to 64 bytes. Then comes a
`-` and the first 32 hex digits of the SHA-256 of the whole URL as the
manifest spells it. The hash keeps two URLs in two checkouts even when
their slugs match, as `file:///repos/a/b` and `file:///repos/a-b` do.

A checkout must be a clone of its URL, not just a directory at the
right path. `fetch` and `build` both read the origin git recorded in
the checkout's `.git/config`. They refuse a directory with no recorded
origin, or one cloned from anywhere else: `fetch` with exit status 4,
`build` with 3. A checkout you make by hand, with the `git clone` the
message prints, works as well as one `fetch` made.

The clone is all or nothing. It goes to `.axiom/deps/.fetch-<key>-<pid>`
and is renamed to its key only when it finishes, so a failed clone
leaves nothing behind and the next `fetch` tries again.

Once it's checked out, the directory joins the search path exactly like
a vendored `depend`, and the rule against two dependencies providing
one module applies to it. A checkout that disappears gets the same
refusal as a deleted directory.

`fetch` takes no operands and needs `git` on your `PATH`. A `file://`
URL clones a local repository from disk, with no network.

Not yet: a URL isn't a version. `fetch` clones the default branch and
never updates a checkout that's already there, and you can't pin a
revision.

Tested by `scripts/check-driver.sh`.

### What packages don't do

There is no central index, no lockfile and no version constraint. A
`depend` URL says exactly where its code lives, so there's nothing to
publish to and nothing to resolve. The compiler never fetches on its
own: only `axiom fetch` does, when you run it. It never runs another
project's build system either, unless your command line asks with
`--crate`.

## Macros

A macro rewrites code before the type checker sees it. Use one to
remove repetition that a function can't, such as a new control form or
a family of declarations. Expansion is substitution: no code from your
source file runs at compile time.

```scheme
(import IO)

(macro (when test body) (if test body 0))
(macro (unless test body) (if test 0 body))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((n 40))
    { (println (when (== n 40) 5))      ; becomes (if (== n 40) 5 0)
      (println (unless (== n 40) 5))    ; becomes (if (== n 40) 0 5)
      0 }))
```

```text
5
0
```

You don't have to write these two yourself: the prelude module, `Pre`,
ships `when`, `unless` and the derive macros described below.

### Write an expression macro

`(macro (name param ...) template)` declares a macro, and
`(pub macro ...)` exports it from its module. The name goes inside the
head parens, as it does for a function. The template is one
expression.

A macro takes exactly as many arguments as it declares parameters. Too
few or too many is `AX3018`. A macro with no parameters can be written
bare or in parens, and both mean the same thing.

Arguments are substituted as syntax, not evaluated first. An argument
used twice in the template runs twice:

```scheme
(import IO)

(macro (twice x) (+ x x))

(:: noisy Int)
;@axiom:effect(io)
(fn (noisy)
  { (println "evaluated")
    21 })

(:: main Int)
;@axiom:effect(io)
(fn (main)
  { (println (twice (noisy)))    ; (+ (noisy) (noisy))
    0 })
```

```text
evaluated
evaluated
42
```

### Hygiene

A name the template binds can't capture a name from the call site. A
macro's name isn't a keyword either: a binding with the same name wins
inside its scope.

```scheme
(import IO)

(macro (addTo x) (let ((tmp 100)) (+ tmp x)))
(macro (v) 9)

(:: f (-> Int Int))
(fn (f v) v)                                ; the parameter, not the macro

(:: main Int)
;@axiom:effect(io)
(fn (main)
  { (println (let ((tmp 1)) (addTo tmp)))   ; the caller's tmp, so 101
    (println (f 3))
    (println v)                             ; the macro
    0 })
```

```text
101
3
9
```

The expansion is checked like code you wrote, so a mistake inside a
template gets an ordinary diagnostic. That includes exhaustiveness on a
`match` the macro generated. The diagnostic points at the invocation.

### Generate declarations

The rule form generates declarations. Write the macro's bare name, then
a rule: a pattern that repeats the name, followed by the declarations
to produce. Invoke it at top level.

```scheme
(import IO)

(macro defWrap
  ((defWrap nm target extra)
   (:: nm (-> Int Int))
   (fn (nm x) (+ (target x) extra))))

(:: base (-> Int Int))
(fn (base x) (* x 2))

(defWrap w1 base 1)             ; declares w1
(defWrap w2 base 100)           ; and w2: names are parameters too

(:: main Int)
;@axiom:effect(io)
(fn (main)
  { (println (w1 5))
    (println (w2 5))
    0 })
```

```text
11
110
```

The rules for declaration templates:

- A template may generate `fn`, `::`, `data`, `struct`, `type` and
  `effect` declarations, and further macro invocations.
- An argument that lands in a name position must be a bare identifier.
- You can invoke a declaration macro from the entry file, and from a
  module over that module's own declarations. The template's own `pub`
  decides what leaves the module.
- A declaration macro can't stand where an expression goes, and an
  expression macro can't stand at top level.

Anything outside these rules is refused. A bad invocation is `AX3027`
at the call, and an unsupported template form is `AX3021` at the
macro's own line. Run `axiom explain AX3027` for the full list. A
mistyped declaration keyword, such as `(fnn (broken) 3)`, is also
`AX3027`, and the message names `fnn`.

### Ask about the program's types

A declaration macro can ask questions about the program's declarations
through the `syntax/*` queries. The expander answers them from the
declaration list at compile time, and no user code runs. Three queries
are enough to write `deriveEq` for any sum type whose constructors
carry no fields:

```scheme
(import IO)

(macro deriveEq
  ((deriveEq T)
   (:: (syntax/join eq T) (-> T T Bool))       ; names eqColour
   (fn ((syntax/join eq T) a b)
     (match a
       (syntax/for (C (syntax/constructors T)) ; one arm per constructor
         ((C) (match b ((C) true) (_ false))))))))

(data Colour () (Red) (Green) (Blue))
(deriveEq Colour)                              ; writes eqColour

(:: main Int)
;@axiom:effect(io)
(fn (main)
  { (println (eqColour Red Red))
    (println (eqColour Red Blue))
    0 })
```

```text
true
false
```

Structs and constructors with fields are covered too:

- `(syntax/fields S)` iterates a struct's field names.
- `(syntax/binders C x)` names a constructor's fields as hygienic
  pattern binders.
- `(syntax/fold && true ...)` chains a comparison over them.

With these, the specification's
[`deriveEq`](macro-system.md#102-deriving-structural-equality) and
[`deriveLenses`](macro-system.md#103-deriving-lenses) run as written,
and a derived function can feed the next derive.

Three more queries answer a single value:

| Query | Answers | Example |
|---|---|---|
| `(syntax/name C)` | the constructor's spelling, as a `String` literal | `deriveCtorName` in `tests/selfhost/380-syntax-scalar-queries.ax` writes `showShape : Shape -> String`. A tag is an integer at run time, so this is the only way to get a constructor's name. |
| `(syntax/arity C)` | its field count, as an `Int` literal | `(deriveArity Shape)` writes `arityShape : Shape -> Int`. A value records its tag but not its field count, so this is the only way to get that number too. |
| `(syntax/defined n)` | whether `n` names a visible declaration | `ctorNameOr` in the same file renders with `showT` if the program derived one, and answers the fallback if not. The `if` is decided at expansion time and the losing branch is deleted, so the `showT` branch never has to type-check in a program without it. |

```scheme
(import IO)
(import Pre)

(data Shape () (Circle Int) (Rect Int Int) (Dot))

(macro deriveCtorName ((deriveCtorName T)
   (:: (syntax/join show T) (-> T String))
   (fn ((syntax/join show T) v)
     (match v
       (syntax/for (C (syntax/constructors T))
         ((C (syntax/binders C f)) (syntax/name C)))))))

(macro (ctorNameOr T x fallback) (if (syntax/defined (syntax/join show T))
  (syntax/join show T x)
  fallback))

(deriveCtorName Shape)                   ; writes showShape
(deriveArity Shape)                      ; writes arityShape

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((s (Rect 3 4)))
    { (println (showShape s))
      (println (arityShape s))
      (println (ctorNameOr Shape s "?"))
      (println (ctorNameOr Int 5 "?"))   ; no showInt, so the fallback
      0 }))
```

```text
Rect
2
Rect
?
```

`(syntax/join a b)` also works where a reference goes, so a macro can
call what it names, as in `((syntax/join show T) x)` above. It can also feed
another query's argument, which is how `ctorNameOr` asks about a name no
source file spells.

A query with no answer is `AX3028`, never a default. That covers an
unknown `syntax/` head, `constructors` of a struct, and a `syntax/join`
name or `syntax/for` written outside a macro template. Declaration names can't start with the
reserved `syntax/` prefix. Run `axiom explain AX3028` for the full
list.

### Match on the arguments

In the rule form, each parameter is a pattern: a binder, `_`, a literal
matched by value, or a parenthesised form of patterns. A macro can have
several rules. They are tried in order, and the first match wins. The
last element of a pattern may repeat with `...`, which makes a macro
variadic.

`macro` with a bare name heads declaration rules. `emacro` heads
expression rules, each with one expression template:

```scheme
(import IO)

; Rules are tried in order, and the first match wins.
(emacro simp (literals + *)
  ((simp (+ a 0)) a)                     ; a parenthesised shape with a literal 0
  ((simp (* a 1)) a)
  ((simp e) e))                          ; a bare binder matches anything

; The last element of a pattern may repeat.
(emacro total
  ((total x) x)
  ((total x rest ...) (+ x (total rest ...))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((n 7))
    { (println (simp (+ n 0)))
      (println (simp (* n 1)))
      (println (simp (- n 2)))
      (println (total 1 2 3 4))
      0 }))
```

```text
7
7
5
10
```

Tested by `tests/selfhost/392-macro-patterns.ax` and `tests/selfhost/403-expr-rule-macro.ax`.

### Match a fixed spelling

A `(literals ...)` header, like `simp`'s `(literals + *)` above,
reserves head spellings across the rule list. A reserved identifier
matches one binding and binds nothing. It is compared by binding, not
spelling, so the `+` the macro means isn't hijacked by a `+` the caller
declares. A reserved name that no pattern uses is `AX3066`.

Tested by `tests/selfhost/402-literal-dispatch.ax`.

### Limits

- A pattern can't use one binder twice as a sameness test. `(- e e)`
  is refused with `AX3020`.
- A template can't generate `import` or a nested `macro` (`AX3021`).
  Each would reopen a compiler phase that has already run.
- The `deriving (Eq)` clause is refused with `AX2004`. Invoke a derive
  macro instead, as in [Algebraic data types](#algebraic-data-types).

The full specification, with every rule and the test behind it, is
[macro-system.md](macro-system.md).

## Printing and formatting

`println` prints a line to standard output and `eprintln` prints one to
standard error. `format` builds the same text and gives it back as a
`String`. Each takes a value, or a string literal with named holes in
it.

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((name "world") (n 42) (pi 3.14159))
    {
      (println "Hello {name}")
      (println "n={n} pi={pi:.2}")
      (println n)
      (let ((row (format "{name:<10}{n:>5}")))
        (println "[{row}]"))
      0
    }))
```

```text
Hello world
n=42 pi=3.14
42
[world        42]
```

`println` and `eprintln` come from `IO`. `format` works once you import
`Fmt` or `IO`. All three are macros, and there are no per-type print
functions: every type goes through them.

There is no `print`, and `(print "hi")` is `AX3001`. You don't need
one to build a line from pieces, because the line is assembled at
compile time. `(println "ok {name} in {ms:>4}ms")` is one call and one
system call. To write bytes with no newline, use `writeStr`:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((n 3))
    { (writeStr stdout "loading")
      (writeStr stdout (format "... {n} files"))
      (println " done")
      0 }))
```

```text
loading... 3 files done
```

### Holes

A hole names a binding that is in scope at the call. There is no
argument list and no positional `{}`: the name goes in the string. To
print an expression, bind it with `let` first.

```text
{name}          render `name` by its static type
{name:SPEC}     render it the way SPEC says
{{   }}         a literal brace
```

A hole accepts any identifier the language accepts, so `{empty-list}`
works.

### Specifiers

```text
SPEC  := [align] ['0'] [width] ['.' precision] [type]
align := '<' (left) | '^' (centre) | '>' (right, the default)
type  := 'x' (lowercase hex) | 'X' (uppercase hex)
```

| Written | Means | Expands to |
|---|---|---|
| `{n}` | the value's own rendering | `(format n)` |
| `{n:x}` | hexadecimal | `(fmtHex n)` |
| `{x:.2}` | two decimal places | `(fmtFloatPrec x 2)` |
| `{n:>8}` | right-aligned in 8 columns | `(fmtPadLeft (format n) 8)` |
| `{s:<8}` | left-aligned | `(fmtPadRight (format s) 8)` |
| `{s:^8}` | centred | `(fmtPadCenter (format s) 8)` |
| `{n:04}` | zero-padded, sign kept in front | `(fmtPadZerosLeft (format n) 4)` |
| `{x:>10.2}` | both, composed | `(fmtPadLeft (fmtFloatPrec x 2) 10)` |

All of this happens at compile time. A specifier picks a function once,
during macro expansion, and no format string is left to parse while the
program runs. `(println "hi")` compiles to one `writeStr` of a constant
whose bytes already end in a newline.

### Mistakes the compiler catches

- A malformed string is `AX3031`: an unclosed `{`, a stray `}`, an
  empty `{}`, or a bad specifier. The caret points at the offending
  byte inside the string.
- A specifier that doesn't fit the type is a type error, because the
  specifier picks a function with a type. `{s:.2}` on a `String` is
  `AX3004` on `fmtFloatPrec`'s `Float` parameter.
- A hole that names no binding is `AX3001`.
- A value with no rendering is `AX3025`. That means a type variable, a
  function value, a `Foreign`, or a `data` or `struct` that holds one
  of those.

### Print your own types

Every `data` and `struct` value prints with no extra code. Its
rendering comes from its declaration, in the language's own spelling:

```scheme
(import IO)

(data Colour (Red) (Green) (Blue))
(struct Point (x : Int) (y : Int))
(struct User (name : String) (age : Int))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((c Green) (p (Point 1 -2)) (u (User "bo\"b" 7)))
    { (println "the colour is {c}")
      (println p)
      (println (Some p))
      (println u)
      0 }))
```

```text
the colour is Green
{x = 1, y = -2}
(Some {x = 1, y = -2})
{name = "bo\"b", age = 7}
```

The rendering is chosen by the value's static type:

| Static type | Renders as |
|---|---|
| `Int`, `Float` | `fmtInt`, `fmtFloat`: `42`, `2.500000` |
| `Bool` | `true` or `false` |
| `Char` | the character literal, escaped as the lexer spells it: `'x'`, `'\n'`, `'é'` |
| `String` | its own bytes at top level, so `(println s)` prints `s`. Inside a structure it is quoted, with escapes: `{name = "bo\"b"}` |
| a `data` value | a constructor application, with a nullary constructor bare: `(Some 3)`, `(Cons 1 (Cons 2 Nil))`, `None`. A constructor with named fields prints positionally: `(Circle 7)` |
| a `struct` value | `{x = 1, y = 2}`, fields in declaration order |

Nesting composes, as in `(Wrap {x = 3, y = 4} Green (Some "hi"))`, and
a recursive type prints in full. A value that reaches itself prints
`...` at the back-edge instead of looping forever. A `mut` field makes
such a value possible:

```scheme
(import IO)

(struct Node (v : Int) (mut next : (Option Node)))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((c (Node 7 None)))
    { (set c.next (Some c))
      (println c)
      0 }))
```

```text
{v = 7, next = (Some ...)}
```

`(format x)` gives you the same rendering as a `String`.

Tested by `tests/stdlib/450-show-builtin.ax`.

### Choose a different rendering

The compiler decides how a type prints, and a program can't override
it. Declaring your own `show` doesn't change what a hole prints. To
print a value another way, write a function that returns a `String`
and interpolate its result:

```scheme
(import IO)

(data Colour (Red) (Green) (Blue))

(:: showColour (-> Colour String))
(fn (showColour c)
  (match c ((Red) "red") ((Green) "green") ((Blue) "blue")))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((c Green) (s (showColour c)))
    { (println "the colour is {c}")
      (println "the colour is {s}")
      0 }))
```

```text
the colour is Green
the colour is green
```

`Pre`'s `deriveShow` writes such a function for you: `showT` is an
ordinary function you call by name. The standard library doesn't
declare `show`, so `(show 1)` is `AX3001`. `impl` is `AX2004` (see
[Removed features](#removed-features)).

Tested by `tests/selfhost/383-format-capture.ax` and `tests/diagnostics/621-show-removed.ax`.

### When the type isn't known

Rendering follows the static type, so a value whose type the compiler
can't name has no rendering. One shape does this, a generic accessor:

```scheme fragment
(println (vecGet v 0))                    ; AX3025: vecGet answers `a`
```

Name the type with `cast`, and it prints:

```scheme fragment
(println (cast Int (vecGet v 0)))
```

### Replacing removed print functions

`IO` no longer has a print function per type. If you have older code:

| Was | Now |
|---|---|
| `(printlnInt n)` | `(println n)` |
| `(printInt n)` | `(println n)`, or `(writeStr stdout (format "{n}"))` to keep the line open |
| `(println (strConcat "n=" (fmtInt n)))` | `(println "n={n}")` |
| `(print "a") (print b) (println c)` | `(println "a{b}{c}")`: one call, one system call |
| `(print s)`, with no newline | `(writeStr stdout s)` |
| a literal containing `{` or `}` | double it: `{{`, `}}` |

`printlnLit` is unchanged. It takes the address of NUL-terminated
bytes, so no rendering is involved. `printLit`, its newline-less form,
is private to `IO`, and calling it is `AX3023`.

*Under the hood.* A hole lowers to a reserved head, `format#`, that the
checker resolves from the argument's static type. `#` isn't an
identifier character (`AX1001`), so no program can declare that head.
The compiler generates one renderer per concrete type at its first use,
as an ordinary function that is checked and compiled like any other.
`symbols` doesn't list it, because a generated name isn't a symbol.
The format-string rules are specified in
[macro-system.md](macro-system.md#46-format-strings).

## Terminals

`IO` gives you the terminal control a line editor or a full-screen
program is built on. It tells you whether a descriptor is a terminal,
switches it to raw mode, puts it back exactly as it was, and reports
its size. Key decoding, escape sequences and history aren't included.
Build those on top.

This program reads one key without waiting for Return, then restores
the terminal:

```scheme
(import IO)
(import Sys)
(import Str)

(:: readKey (-> TermState Int))
;@axiom:effect(io)
(fn (readKey saved)
  (let (
    (key (strAlloc 1))
    (got (readInto stdin key 0 1))
    (back (termRestore saved))
  )
    (match got
      ((Ok n) (if (== n 1) (strByte key 0) -1))
      ((Err _) -1))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (termRaw stdin true)                 ; true keeps ^C as SIGINT
    ((Err _) { (println "stdin is not a terminal") 1 })
    ((Ok saved)
      (let ((code (readKey saved)))
        { (println "you pressed byte {code}") 0 }))))
```

Press `q` and it prints:

```text
you pressed byte 113
```

With its input piped from somewhere else, it prints
`stdin is not a terminal`.

### The functions

`termSave`, `termRaw`, `termRestore` and `termSize` answer a `Result`,
and an `Err` carries the errno: `ENOTTY` for a descriptor that isn't a
terminal.

| Call | Does |
|---|---|
| `(sysIsatty fd)` | `true` when `fd` is a terminal |
| `(termSave fd)` | `(Ok state)`, a `TermState` holding `fd`'s current settings |
| `(termRaw fd keepSignals)` | saves the current settings, then switches `fd` to raw mode, and answers `(Ok state)` to restore them with |
| `(termRestore state)` | puts back the settings `state` holds, on the descriptor they came from |
| `(termSize fd)` | `(Ok size)`, a `TermSize` whose `rows` and `cols` fields are the window size |

A `TermState` is sealed: only `IO` builds one or reads its bytes, so a
restore can only ever put back settings a save took.

`Sys` has the same calls over buffers you allocate yourself:
`sysTermSave`, `sysTermRaw`, `sysTermRestore` and `sysTermSize`, which
answer 0 or a negative result, with `sysTermRows` and `sysTermCols` to
read a size back. They are precondition interfaces, so a function
that calls one says `;@axiom:effect(unsafe)`. Size those buffers with
`sysTermStateBytes` and `sysTermSizeBytes`, never by hand: `struct termios` is 72 bytes on
Darwin, 36 on Linux and 44 on FreeBSD, and a size picked by hand can
round-trip on the machine you tested it on and still be wrong on
another.

### Save and restore

`termRaw` saves the settings, then edits a private copy. It never
writes to the saved bytes again, so `termRestore` always puts back the
original settings. Restore before every exit: a program that leaves
the terminal in raw mode hands the user a shell with no echo and no
line editing.

Entering and leaving raw mode let pending output drain and discard
unread input before the change takes effect. Type-ahead meant for the
old mode never arrives as keystrokes.

### What raw mode changes

Raw mode clears `ECHO`, `ICANON` and `IEXTEN`; `IXON`, `ICRNL`,
`ISTRIP` and `BRKINT`; and `OPOST`. It sets `VMIN` to 1 and `VTIME` to
0. In practice:

- A read returns as soon as one byte arrives, and your program draws
  every character itself.
- Return arrives as a carriage return (13), and bytes keep their eighth
  bit, so UTF-8 input survives.
- ^S, ^Q and ^V arrive as ordinary bytes instead of controlling the
  terminal.
- Output isn't processed, so write `"\r\n"` where you want a new line.

`ISIG` is your choice, through `termRaw`'s second argument. Pass
`true` and ^C still raises `SIGINT`, which a REPL usually wants. Pass
`false` and ^C arrives as byte 3 for your program to bind, which suits
a full-screen editor. `c_cflag` isn't touched.

### Window size

`termSize` answers the rows and columns together. A terminal may
answer 0 rows and 0 columns and still report success, as an unsized
pty or some CI runners do. Treat 0 as unknown and fall back to 80 by
24.

### Targets

Terminal control works on `darwin-aarch64`, `darwin-x86_64`,
`linux-x86_64`, `linux-aarch64` and `freebsd-x86_64`.

It isn't available on Windows (`windows-x86_64`, `windows-aarch64`),
which has no `termios` and no `ioctl`. The Windows console works through `GetConsoleMode` and
`SetConsoleMode` on a handle, which this library doesn't implement.
There, `sysIsatty` answers `false`, `termSave`, `termRaw`,
`termRestore` and `termSize` answer an `Err`, and the `Sys` forms a
negative result, never a plausible one.
`stdlib/Sys/Platform.windows.ax` records the mechanism a Windows port
would need.

*Under the hood.* Every request number, struct offset and flag bit
comes from the target's `Sys.Platform` module, and each constant
carries a comment saying how it was established. On Windows,
`Sys.Platform.ttyUsesTermios` is 0. An `ioctl` request number encodes a
byte count, so a number borrowed from the wrong platform doesn't fail
cleanly: it names some other command, or copies the wrong number of
bytes.

## Memory

Axiom frees memory for you. Every heap block carries a reference
count, and a block whose count reaches zero is reclaimed and reused.
There's no garbage collector to tune and no `free` to call. When you
want a batch of allocations gone at a point you choose, wrap the work
in a `region`:

```scheme
(import IO)
(import Str)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((mut i 0) (mut total 0))
    {
      (while (< i 1000)
        {
          (region req
            (let ((line (format "request {i}")))
              (set total (+ total (strLen line)))))
          (set i (+ i 1))
        })
      (println "built {total} bytes")
      0
    }))
```

```text
built 10890 bytes
```

Each string the loop builds is reclaimed when `req` ends. `total` is an
`Int`, so it survives the reset.

Your program carries its own allocator, and the build is freestanding:
it doesn't call the C library.

### How memory is reclaimed

Memory comes from an `mmap`-backed bump allocator that is compiled into
your program. Every heap block carries a reference count and a shape
word. When a block's count reaches zero, the block is walked, releasing
what it holds, and re-issued from a size class. Peak memory tracks your
live data rather than everything you ever allocated.

There is no tracing collector, and `axiom build --gc` is refused rather
than ignored. You can't replace the allocator either: defining
`axiom_alloc`, `axiom_retain` or `axiom_release` in your entry file is
`AX3026`, because the emitted runtime owns those names
([memory-model.md](memory-model.md) MM-ALLOC-8).

Tested by `tests/stdlib/359-arc-str-bytes.ax` and `tests/stdlib/372-arc-owned-results.ax`.

### Regions

`(region r body)` opens an allocation scope. The allocator's waterline
is read when `body` starts and rolled back when `body` ends, so
everything `body` allocated is reclaimed in one pointer move. The form's
value is `body`'s value.

The usual shape is one region per loop iteration, as in the example
above. A server that handles each request inside `(region req ...)`
returns to the same waterline after every request (MM-ALLOC-22).

A region does the job of a hand-written `__axiom_arena_mark` and reset,
with one difference that matters in a loop. A hand-written mark
allocates its 24-byte cell on the heap, below the waterline it records,
so that cell is never reclaimed. A region keeps its mark on the stack,
so two thousand iterations leave the waterline where they found it.

The compiler checks three rules:

- **The value must be a scalar**: an `Int`, `Bool`, `Char` or `Float`.
  These pass the reset by value. A `String` is a descriptor
  over a second block, a struct is a block and a closure is a record,
  so each would point at reclaimed memory. A region that answers any
  other type is `AX3059` at the body. Answer a count, a status or a
  hash, and build a reference outside the region.
- **A store out of the region must be a scalar.** Inside the region,
  `(set x v)` on an `x` bound before the region opened is `AX3059` when
  `v` isn't a scalar, and so is `(set x.f v)`. Storing an `Int`, as the
  example does with `total`, is fine.
- **A nested region can't reuse an open name.**
  `(region r (region r ...))` is `AX3058`, because regions are ordered
  by nesting (MM-RGN-2) and one name can't mean two open scopes.
  Sibling regions may share a name
  (`tests/diagnostics/630-region-name-shadowed.ax`).

```scheme refused
(import IO)
(import Str)

(:: main Int)
(fn (main)
  (let ((mut out ""))
    {
      (region r
        (strConcat "a" "b"))            ; AX3059: the region answers a String
      (region s
        {
          (set out (strConcat "a" "b")) ; AX3059: a String stored outside
          0
        })
      0
    }))
```

A call that stores a region-allocated value for you is refused as
`AX3060` where the compiler can see the store, as with `memSetWord` into
an outer block. It doesn't see every such call: `vecPush` onto an outer
vector passes, and so does a raw `Int` that holds an address. Those are
your responsibility under MM-ALLOC-16, as they are for a hand-written
mark.

Nothing can refer to a `region` by its name yet. The `@r` of
[Region annotations](#region-annotations) is a signature's region
parameter, not a `region` form's name.

The runtime's traps still guard you. A region takes its mark inside
whatever `handle` scope encloses it, so the status-76 trap
(MM-ALLOC-16b) never fires for it. Nested regions reset innermost
first, so the status-75 trap (MM-ALLOC-16a) doesn't either. Resetting
an *outer* hand-written mark inside a region is still a fault, and
traps as usual.

A region adds `Alloc` to its function's effect row, as the arena
primitives do, because a reset works on the heap even when the body
allocates nothing. So a
[`restrict(no-alloc)`](#restrict---what-a-declaration-does-not-do) body
can't contain one.

`region` is an ordinary identifier except at the head of a form, like
every keyword ([Identifiers and keywords](#identifiers-and-keywords)).
`axiom fmt` lays it out the way it lays out `while`.

Tested by `tests/stdlib/168-region.ax` and `tests/diagnostics/631-region-escape.ax`.

### Choosing a memory manager

Axiom has one allocator. What you choose is how much of the reclaiming
you steer yourself:

- **Nothing.** Reference counting frees each block when its last
  reference goes. This is the default and needs no flag.
- **A `region`**, for a scope of work you want reclaimed in one move.
- **The arena primitives** `__axiom_arena_mark`, `__axiom_arena_reset`
  and `__axiom_arena_reset_keeping`, for full control. The language
  server uses them to keep its memory flat across an editing session.

```bash
# The default: a bump allocator with per-block reference counts.
axiom build --input source.ax --output program
```

#### Work with arena marks

The arena primitives carry a contract the compiler can't check: after
a reset, nothing allocated since the matching mark may be read again.
The allocator makes these promises around them:

- `memAlloc` always answers zeroed memory, including memory a reset
  reclaimed and handed out again.
- `memAlloc` answers a *leaf*: a block declared to hold no references,
  because a byte count is all it was told. `(memAllocMapped bytes map)`
  allocates the same way, with bit *i* of `map` marking payload word
  *i* as a handle to another counted block, so releasing this block
  releases that one too. `Str`'s header uses it: word 2 owns the bytes,
  so a dead string frees its buffer as well as its header. The map is
  clamped to the block, so it can name the wrong word of your block but
  never a word outside it.
- A reset writes nothing to what it reclaims. Memory above the restored
  waterline keeps its contents until it's handed out again.
- `(__axiom_arena_reset_keeping mark addr bytes)` reclaims to `mark`,
  carries the `bytes` at `addr` across, and answers their new address.
  This is how you keep a value. A reset followed by an ordinary copy is
  unsound, because the copy's destination is scrubbed on allocation and
  the scrub can run over the source.

### Containers that own what they hold

`Vec`, `Map` and `Intern` each have an owning constructor: `vecNewRef`,
`mapNewRefVals` and `internNew`. An interner is always owning, because
it has no other use. Each has a `Free` (`vecFree`, `mapFree`,
`internFree`) that hands the whole structure back:

```scheme
(import IO)
(import Str)
(import Vec)

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main)
  (let ((names vecNewRef))
    {
      (vecPush names (strDup "ada"))     ; the vector takes a share
      (vecPush names (strDup "grace"))
      (println (vecLen names))
      (vecFree names)                    ; header, data block and both strings
      0
    }))
```

```text
2
```

The two `Vec` constructors differ in one word at allocation. A
`vecNewRef` data block is marked with the array form
(`Mem.memMarkArray`), which says its first `cap` payload words are
handles, so releasing the block releases them all. A `vecNew` data
block is a leaf and makes no claim about its contents.

For `Int` elements, a leaf is right and costs nothing: the store emits
no instruction at all. For references it leaks. The store still takes a
share (MM-LIFE-2g) and nothing hands it back, so the element is never
freed. Use the owning constructor when a container holds references.

In an owning vector, growth, overwriting and removal all hand back what
they displace. `vecPop` zeroes the slot it vacates, so the popped
value's share becomes yours. MM-LIFE-2h states the encoding and the
obligations that come with it, and MM-LIFE-2i the property it delivers:
a bounded live set has bounded memory.

### Recover from a trap

`(__axiom_recover mark thunk)` turns an arena mark into a *recovery
point*. It calls `thunk`, a `(-> Int Int)`, with `0` and answers what
the thunk answered. If the program instead runs out of memory, performs
an effect with no handler, or divides by zero anywhere inside that call,
`__axiom_recover` answers **70**, **71** or **72** and the program
carries on:

```scheme
(import IO)

(:: zero Int)
(fn (zero)
  0)

(:: divide (-> Int Int))
(fn (divide x)
  (/ 10 zero))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((status (__axiom_recover __axiom_arena_mark (lambda (x) (divide x)))))
    {
      (println "recovered with status {status}")
      0
    }))
```

```text
recovered with status 72
```

Outside a recovery point, those three traps still write their message
to standard error and exit. Recovery points nest, and an abort goes to
the innermost one.

The abort restores the stack pointer, resets the arena to `mark`, and
restores every effect handler's evidence slot. That last step is why
this is safe where calling `__axiom_arena_reset` by hand across a live
`handle` is not (MM-ALLOC-16b, MM-ALLOC-23).

Nothing runs on the way out: there are no destructors and no landing
pads. This isn't a `catch`, and it can't contain a memory-safety fault,
because a segmentation fault isn't a trap. [error-model.md](error-model.md)
ERR-REC-6 states the whole contract.

Two limits follow from the reset. Don't store anything the thunk
allocated into a value older than the recovery point; return it through
the arming call instead. And close files and release locks before
anything in the thunk can trap, because an abort doesn't. Take the mark
once, outside a loop: each `__axiom_arena_mark` costs a 48-byte cell.

Tested by `tests/stdlib/403-recover-div.ax`.

<a id="memory-primitives"></a>

### Low-level primitives

The standard library is built on these primitives, and so is any code
that talks to the machine directly. This is where the type system
stops: every argument and result is an `Int`.

| Primitive | Meaning |
|---|---|
| `(__syscall0 n)` ... `(__syscall6 n a1 ... a6)` | Raw system call. Answers the result, or `-errno` on failure, on every platform. `IO` and `Unsafe`: the kernel reads and writes through the arguments |
| `(__load8 base i)` / `(__store8 base i v)` | Byte at `base + i` |
| `(__store8v base i v)` | Byte at `base + i`, as a volatile store: every store is kept, in order, which `__store8` doesn't promise. Use it for memory-mapped registers. Otherwise the same as `__store8`, effect row included |
| `(__vload8 a)` / `(__vload16 a)` / `(__vload32 a)` / `(__vload64 a)` | ONE volatile read of 8/16/32/64 bits at the byte address `a` (the address itself, not `base + i`), naturally aligned, zero-extended to the word - a device register at its own width. `Mut` and `Unsafe`: a device read can change device state. `a` MUST be aligned to the width ([memory-model.md](memory-model.md) MM-FFI-8) |
| `(__vstore8 a v)` / `(__vstore16 a v)` / `(__vstore32 a v)` / `(__vstore64 a v)` | ONE volatile write of the low 8/16/32/64 bits of `v` at the byte address `a`, naturally aligned; answers 0. Volatile keeps every access, its width and its order against other volatile accesses - and is NOT a synchronisation edge: across threads that is the atomics above, and against ordinary memory a device reads (a DMA descriptor) it is `__arm_dmb`/`__arm_dsb` |
| `__arm_dmb` / `__arm_dsb` / `__arm_isb` | AArch64 `DMB SY` (order every access before against every access after, for every observer including a device), `DSB SY` (complete them before the next instruction) and `ISB` (context synchronisation - after writing a system register). Each is also a compiler barrier. Any AArch64 target |
| `__arm_rndr` | One word from `RNDR`, the random-number register of FEAT_RNG, or 0 when the hardware couldn't produce one in time. `IO` and `Entropy`. `baremetal-aarch64` only, where the CPU has FEAT_RNG |
| `__arm_cntvct` / `__arm_cntfrq` | The virtual counter `CNTVCT_EL0` and its frequency `CNTFRQ_EL0`, in ticks and ticks per second. `IO`; the counter read is a compiler barrier, because it is a timestamp. Any AArch64 target |
| `__arm_ctr` / `__arm_tpidr` / `(__arm_set_tpidr v)` | `CTR_EL0` (the cache geometry: `4 << ((ctr >> 16) & 15)` is the smallest data-cache line in bytes, `DminLine`), and `TPIDR_EL1`, a word of software state the hardware keeps - how an interrupt handler, which takes no argument, finds its state. `baremetal-aarch64` only |
| `(__arm_set_cntv_cval t)` / `(__arm_set_cntv_ctl c)` | The virtual timer: fire when the counter reaches `t`; control bit 0 enables it, bit 1 masks its interrupt. `baremetal-aarch64` only |
| `__arm_irq_mask` / `__arm_irq_unmask` / `__arm_wfi` | `msr daifset, #2` / `msr daifclr, #2` (mask and unmask IRQs) and `wfi` (sleep until an interrupt is pending - it wakes even while masked). Each is a compiler barrier. `baremetal-aarch64` only |
| `(__arm_dc_cvac a)` / `(__arm_dc_civac a)` | Clean, and clean and invalidate, the data-cache line holding `a` to the point of coherency - the maintenance around a DMA transfer. `Unsafe`. `baremetal-aarch64` only |
| `(__load64 base i)` / `(__store64 base i v)` | Machine word at `base + i * 8` |
| `(__atomic_load p)` / `(__atomic_store p v)` / `(__atomic_add p v)` / `(__atomic_cas p expected new)` / `__fence` | Sequentially consistent atomics on the word at *byte address* `p` (the address itself, not `base + i * 8`). `__atomic_add` answers the word before the add. `__atomic_cas` answers the word it found, so it stored `new` exactly when that equals `expected`. A store and the fence answer 0. The four that write or order carry `Mut`; the load computes, as `__load64` does |
| `(__alloc bytes)` | Address of `bytes` fresh zeroed bytes |
| `(__retain h)` / `(__release h)` | Take or hand back a share of the counted block at `h` |
| `(__retainref v)` | Take a share of `v` only if `v` is a reference. This is decided from the call's type, so an `Int` argument emits nothing. Use it when you store a value behind a `cast Int` |
| `__axiom_arena_mark` / `(__axiom_arena_reset m)` | Read the allocator's waterline (it takes no argument), and roll it back to a mark |
| `(__axiom_mem_stat k)` | The allocator's own counts for this thread, in bytes: 0 held by the arena, 1 filed on the size-class lists for reuse, 2 mapped. Held less filed is what a reset would give back and counting hasn't, such as unreachable cycles. Any other `k` answers -1 ([memory-model.md](memory-model.md) MM-ALLOC-24) |
| `(memMarkArray h n)` / `(memMarkLeaf h)` | From `Mem`. Declare that payload words `0..n-1` of the block at `h` are handles, or that none is. `n` is your element count, not the block's size, because the allocator's own word count is a size class, clamped to 0 past 16,383 words. There's no reader, so a container keeps its own flag (MM-LIFE-2h) |
| `(__axiom_recover m thunk)` | Arm a recovery point at mark `m` and run `thunk`. See [Recover from a trap](#recover-from-a-trap) |
| `(__addr "literal")` | Address of a string literal's bytes |

A device primitive the target cannot execute is refused at build time
as `AX4008`. The volatile accesses lower everywhere, the barriers and
the two counter reads on any AArch64 target (they run at EL0), and the
rest only on `baremetal-aarch64`, the one target that runs a program at
EL1. The check reads the module after unreachable functions are
pruned, so a helper nothing calls is never refused.
[embedded-guide.md](embedded-guide.md) is the whole bare-metal story
these serve.

`axiom symbols --builtins <file>` prints the full list, primitives and
built-in operators together, with the type of each (see
[CLI commands](#cli-commands)). The atomics' single-threaded meaning is
tested by `tests/stdlib/440-atomics.ax`.

#### System calls and platforms

Syscall numbers aren't built into the compiler. They live in
`stdlib/Sys/Platform.<os>[-<arch>].ax`, and the module resolver picks
the file that matches `--target`. Adding a syscall is a standard-library
change, not a compiler change.

The same goes for everything else that is ABI rather than language.
`Sys.Platform` is a table of numbers, not of OS names. Portable code
branches on a capability it exposes, such as `openNeedsDirFd`,
`pollUsesKqueue`, `usesSyscallAbi` or `ttyUsesTermios`, rather than on
which file resolved.

A target can answer no to a whole facility. `ttyUsesTermios` is 0 on
both Windows targets, which have no `termios` and no `ioctl`, so every
terminal call there answers a negative result instead of a made-up one.
See [Terminals](#terminals) for the support matrix. Every
`Sys/Platform.*.ax` file declares the same public names, so a target
that lacks a facility gives a declared answer, never a missing symbol.

#### Inline assembly

When no primitive covers an instruction, write it with `asm`. Give one
arm per architecture your program builds for, and the compiler emits
the one for the target:

```scheme
(import IO)

(:: add (-> Int Int Int))
;@axiom:effect(unsafe)
(fn (add x y)
  (asm
    (aarch64 "add {r}, {a}, {b}" (out r) (in a x) (in b y))
    (x86_64 "leaq ({a},{b}), {r}" (out r) (in a x) (in b y))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (add 40 2))
    0
  })
```

It prints `42` on either architecture.

An arm is the architecture, `aarch64` or `x86_64`, then the template,
then its operands:

| Operand | Meaning |
|---|---|
| `(in name value)` | `value`, an `Int`, in a register |
| `(out name)` | a register the form answers when the instructions end |
| `(inout name value)` | starts as `value` and is answered |
| `(clobber "reg"...)` | registers the instructions write that no operand names |

In the template, `{name}` is the operand's register and `{name:w}`
picks a view of it, such as the 32-bit `w` register on aarch64 or `k`
on x86_64. Write `{{` and `}}` for literal braces. Everything else
reaches the assembler as written; x86_64 uses AT&T syntax. To put an
operand in a particular register, name it: `(in a "x8" v)`. An arm
answers at most one value, and a form with no `out` or `inout` answers
0.

The compiler can't see what the instructions do, so a function holding
an `asm` form says `;@axiom:effect(unsafe)`, and vouches for them. Its
callers need nothing. Every block is kept and ordered as a side effect,
and clobbers memory and the flags.

What is checked and when:

- A malformed form, such as an unknown operand kind, a template naming
  no operand, or the stack or frame pointer as a register, is
  `AX3091`, where it is written.
- A form with no arm for the target is `AX4008` when the program
  builds, if a function the program reaches holds it. A function
  nothing calls may hold an arm for another architecture.
- The instructions themselves are checked by the target's assembler
  when the program builds, not by `axiom check`.

Not yet: operands are `Int` words in general-purpose registers, with
no memory, floating-point or vector operands, and one output. The full
contract, with what the instructions must leave as they found it, is
`MM-FFI-9` in [memory-model.md](memory-model.md).

Tested by `tests/stdlib/581-inline-asm.ax` and `tests/diagnostics/1044-inline-asm.ax`.

## Concurrency

Axiom has one concurrency form, `parallel`. It runs a few expressions at
once and hands their answers back to your code in a fixed order. Four
modules build on it: `Chan` passes words between bindings, `Sync` has a
mutex, and `Par` and `Task` run pools of tasks. There's no scheduler
and no async.

<a id="parallel--bindings-that-run-beside-the-caller"></a>

### Run expressions side by side with `parallel`

```scheme
(import IO)

(:: slowSum (-> Int Int))
(fn (slowSum n)
  (let ((mut i 0) (mut acc 0))
    {
      (while (< i n)
        {
          (set acc (+ acc i))
          (set i (+ i 1))
        })
      acc
    }))

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  (let ((n 1000000))
    (parallel p ((a (slowSum n))
                 (b (* n 2)))
      {
        (println "a = {a}")
        (println "b = {b}")
        0
      })))
```

```text
a = 499999500000
b = 2000000
```

`(parallel p ((a e1) (b e2) ...) body...)` evaluates every binding's
expression at once, beside the caller. It binds each answer to its name
and runs the body with them.

The bindings are joined in the order written, always: `a` is bound
before `b`, whichever finished first. So your program can't observe
which child finished first (MM-PAR-5 in
[memory-model.md](memory-model.md)). Above, `a` takes far longer than
`b`, and the output is the same on every run.

`p` names the region the form runs in. Today it's bound to that
region's arena mark, a word. The typed regions of
[memory-model-v2-design.md](memory-model-v2-design.md) will give it a
type.

`parallel` performs `IO`, `Spawn` and `Block`: it starts the bindings
and waits for them. So a function that uses it declares
`effect(io)`, `effect(spawn)` and `effect(block)`, and a body that
claims `no-io`, `no-spawn` or `no-block` can't contain one.

### Processes or threads

By default, each binding runs in its own *process*: a `fork`, one
shared page for the answer, and `wait4`. The child can't touch the
parent's memory (MM-PAR-3), and the program imports nothing.

Build with `--threads` and each binding runs in a *thread*, from the
platform's `pthread_create`. Every thread allocates in an arena of its
own (MM-PAR-6).

```bash
axiom build --input server.ax --output server --threads
```

Both give the same output and the same exit status, including when a
binding traps. Under processes the child dies and the join re-raises
its status. Under threads the trap ends the whole process.
`tests/stdlib/471-parallel-trap.ax` exits with status 77 either way.

A trap inside a binding prints a backtrace. It stops at `main`, or, in
a thread, at the binding's entry point.

Tested by `scripts/check-parallel.sh`, which builds the same programs
both ways and compares their output and exit status.

#### When two bindings fail

With one failing binding, the two lowerings agree. With two, they
differ:

- Under processes, the joins run in the order written. The first join
  re-raises its child's status and nothing after it runs, so the exit
  status is always that of the binding written first.
- Under threads, a trap exits from the thread that took it and there's
  no join to reach. The status is whichever binding failed first, and
  it can change from run to run. The two backtraces can interleave on
  standard error as well.

If two bindings can fail at once and your program's exit status
matters, use the default lowering. It's the deterministic one.

### What a binding may answer

A word. Each expression is wrapped in a `(-> Int Int)` thunk and the
join answers an `Int`, so a binding whose expression is a `String` is
refused where it's written:

```scheme refused
(import IO)

(:: main Int)
(fn (main)
  (parallel p ((s "x") (n 2))
    n))
```

```text
error[AX3004]: type mismatch: expected (Int -> Int), found (_a -> String)
```

Under processes, the answer crosses between address spaces through one
page. Under threads, a reference would have to be promoted out of
another thread's arena, which is work for typed regions, not for this
form.

`mut` on a binding is a parse error (`AX2001`): a binding is bound once,
at its join.

Tested by `tests/diagnostics/641-parallel-word.ax` and `tests/diagnostics/640-parallel-shape.axbad`.

### What a binding may capture

Words, and strings. A binding may read a `String` its parent holds:

```scheme
(import IO)
(import Str)

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  (let ((name (strConcat "axi" "om")))
    (parallel p ((n (strLen name))
                 (m (strLen (strConcat name "!"))))
      {
        (println "{n} {m}")
        0
      })))
```

```text
5 6
```

The form lends the string to its bindings. Until the last join, the
string's reference count is frozen, so no binding's retain or release
touches the parent's count, in either lowering (MM-PAR-6b). A string's
bytes can't change in safe code, so a read-only share is all a binding
needs.

Any other reference the parent holds is `AX3064` at the name:

```scheme refused
(import IO)

(struct Counter (n : Int))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((c (Counter 1)))
    (parallel p ((n c.n))   ; AX3064: `c` is a Counter
      n)))
```

Under threads, that value would be shared with the parent, and its
reference count updated from two threads with no fence. The update
isn't atomic, so an increment could be lost and a block still in use
freed (MM-PAR-6). A struct's fields can also be set, so a frozen count
wouldn't make sharing it safe. The rule is the language's, not the
lowering's, so it applies without `--threads` too: a program means the
same thing however it's built.

Pass the value in through the thunk's word argument, or build a copy
inside the binding. To share other read-only input with several
workers, use [`Par`](#run-a-pool-of-tasks-with-par).

A bare `Foreign` may be captured: it points into memory Axiom never
allocated, so there's no count to race. A `Handle` may not, because
it's a counted block that carries a destructor.

A handle whose type is declared `shared` may be captured too: a
`Chan`, a `Mutex` or a `CancelToken` is one word its module built for
use from every binding at once ([Make a handle other modules can't forge](#make-a-handle-other-modules-cant-forge)).
A word struct without `shared` may not, and neither may a `Vec`, which
two bindings could grow at once, or a spawn's `Spawn` handle, which
only the binding that spawned it may join.

Only `parallel`'s own bindings borrow. A `String` captured by a
hand-written `__par_spawn` is still `AX3064`, since the parent may run
code between that spawn and its join.

Tested by `tests/stdlib/630-parallel-borrow.ax`,
`tests/diagnostics/1100-parallel-borrow-refused.ax` and
`tests/diagnostics/1064-parallel-capture-handle.ax`.

### Pass words between bindings with a channel

`Chan` carries words from one binding to another. `chanNew` makes a
bounded channel, `chanSend` and `chanRecv` wait while it is full or
empty, and `chanClose` ends the stream:

```scheme
(import IO)
(import Chan)
(import Err)

(:: produce (-> Chan Int Int))
;@axiom:effect(io)
;@axiom:effect(block)
(fn (produce ch n)
  {
    (for i in 1..(+ n 1)
      (chanSend ch i))
    (chanClose ch)
    n
  })

(:: total (-> Chan Int))
;@axiom:effect(io)
;@axiom:effect(block)
(fn (total ch)
  (let ((mut sum 0) (mut going 1))
    {
      (while (== going 1)
        (match (chanRecv ch)
          ((Some v) (set sum (+ sum v)))
          ((None) (set going 0))))
      sum
    }))

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  (match (chanNew 8)
    ((Ok ch)
      (parallel p ((sent (produce ch 100)) (sum (total ch)))
        {
          (println "sent {sent}, received a total of {sum}")
          (match (chanFree ch)
            ((Ok z) 0)
            ((Err e) 1))
        }))
    ((Err e) 1)))
```

```text
sent 100, received a total of 5050
```

`ch` is a `Chan`, a handle: only `chanNew` makes one, and the bindings
may capture it because `Chan` is declared `shared`. It works the same
in both lowerings. Free a channel after the `parallel` form that used
it. A call on a freed channel, and a second `chanFree`, exits with
status 85 and `axiom: not a live handle (freed, or never made)`
instead of reading memory that is gone. `Mutex`, from `Sync`, works
the same way.

Tested by `tests/stdlib/528-chan.ax` and
`tests/stdlib/570-handle-freed.ax`.

### Wait with a deadline

`chanSend` and `chanRecv` wait for as long as it takes. Their timed
forms, `chanSendTimeout` and `chanRecvTimeout`, take a limit in
nanoseconds and answer `Err` with `sysTimedOut` when it passes:

```scheme
(import IO)
(import Sys)
(import Chan)
(import Err)

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(block)
(fn (main)
  (match (chanNew 4)
    ((Ok ch)
      {
        (match (chanRecvTimeout ch 20000000)
          ((Ok (Some v)) (println "received {v}"))
          ((Ok (None)) (println "closed"))
          ((Err e)
            (let ((code (errCode e)))
              (if (== code sysTimedOut)
                (println "nothing arrived in 20 ms")
                (println "failed with {code}")))))
        (match (chanFree ch)
          ((Ok z) 0)
          ((Err e) 1))
      })
    ((Err e) 1)))
```

```text
nothing arrived in 20 ms
```

A binding that dies while it holds a channel's lock, for example one
killed by a signal, leaves the channel *poisoned*. Every waiter wakes
within about 100 ms, the timed forms answer `Err` with `chanOwnerDead`,
and `chanPoisoned` answers `true`. Nothing reads the ring the dead
binding may have left half-written.

A waiter finds a dead holder only when the kernel reports it. A holder
that is a zombie seen by anyone but its parent, or whose process id the
kernel has reused, still looks alive. Use the timed forms wherever a
dead holder must not stop your program.

Tested by `tests/stdlib/540-wait-timeout.ax` and
`tests/stdlib/590-chan-dead-holder.ax`.

### Guard shared state with a mutex

`Sync`'s `Mutex` gives one binding at a time the right to go on.
`mutexLock` answers a `MutexGuard`, and `mutexUnlock` takes it back:

```scheme
(import IO)
(import Sync)
(import Err)

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(block)
(fn (main)
  (match mutexNew
    ((Ok m)
      (match (mutexLock m)
        ((Ok g)
          {
            (match (mutexTryLock m)
              ((Some other) (println "locked twice"))
              ((None) (println "held, so a second lock waits")))
            (match (mutexLockTimeout m 50000000)
              ((Ok other) (println "locked twice"))
              ((Err e) (println "a timed lock gave up after 50 ms")))
            (match (mutexUnlock m g)
              ((Ok z) (println "unlocked"))
              ((Err e) (println "not held")))
            (match (mutexFree m)
              ((Ok z) 0)
              ((Err e) 1))
          })
        ((Err e) 1)))
    ((Err e) 1)))
```

```text
held, so a second lock waits
a timed lock gave up after 50 ms
unlocked
```

Only a lock call makes a `MutexGuard`, so safe code can't unlock a
mutex it never locked. An unlock with a guard from another mutex, or
with one already spent, answers `Err` with `syncNotHeld` and leaves the
lock alone. Like a channel, a mutex is `shared`, so `parallel` bindings
may capture it. It works in both lowerings.

The mutex isn't reentrant: the holder that locks again waits for
itself, as the timed lock above shows. A holder that dies makes the
next lock answer `Err` with `syncOwnerDead`. The lock isn't fair and
has no priority inheritance, so a binding can starve, and a program
with real-time deadlines shouldn't rely on it.

Tested by `tests/stdlib/541-sync-mutex.ax`, which also adds to one
word from two bindings under the lock.

### Run a pool of tasks with `Par`

`(parMapWords f n width)` runs `(f i)` for every `i` from `0` up to
`n`, at most `width` at a time, and answers the results as a
`(Vec Int)` in submit order:

```scheme
(import IO)
(import Par)
(import Vec)

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  (let ((squares (parMapWords (lambda (i) (* i i)) 6 3)))
    {
      (for x in squares
        (println x))
      0
    }))
```

```text
0
1
4
9
16
25
```

`parMapWordsChecked` runs the same pool and answers one `Result` per
slot: `Ok` with the thunk's word, or `Err` with the wait status of a
slot that trapped. A batch survives a trapped slot. `parRunAll` runs a
list of external commands through the same pool.

`Par` forks a process per task, so its closures may capture whatever
the caller has. Each child reads its own copy-on-write copy
(MM-PAR-3).

Tested by `tests/stdlib/476-par-pool.ax`.

### Run tasks that answer values with `Task`

`Task` runs a pool whose tasks answer a `String`, and gives you one
`(Result String Error)` per task, in submit order. `(taskMap f n width
limit)` runs `(f i)` for every `i` from `0` up to `n`, at most `width`
at a time, and accepts answers of up to `limit` bytes:

```scheme
(import IO)
(import Task)
(import Vec)
(import Err)

(:: square (-> Int String))
(fn (square i)
  (fmtInt (* i i)))

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  (let ((results (taskMap square 5 2 64)))
    {
      (for r in results
        (match r
          ((Ok s) (println s))
          ((Err e) (let ((code (errCode e))) (println "task failed with {code}")))))
      0
    }))
```

```text
0
1
4
9
16
```

Each task runs in its own process, under `--threads` too, and only its
answer's bytes come back. To return a record, a `Vec` or a tree,
encode it in the task and decode it in the parent, for example with
`Json`. `examples/concurrency/typed-tasks.ax` sends a `struct` holding
a `Vec` back this way.

Every failure is a value in the task's slot:

| `Err` code | Meaning |
|---|---|
| 1 to 255 | the task trapped or died: its exit code, or 128 plus the signal |
| `taskTooLargeCode` | the answer was longer than `limit`, and none of it crossed |
| `sysTimedOut` | the task ran past its deadline and was killed |
| `taskCancelledCode` | the pool was cancelled before the task finished |
| 78 or 70 | the task's spawn was refused, which also cancels the pool |

Build the options with `taskOpts width limit`, then add a deadline, a
grace period, fail-fast, or a `CancelToken` shared with other code:

```scheme
(import IO)
(import Sys)
(import Task)
(import Vec)
(import Err)

(:: work (-> Int String))
(fn (work i)
  (if (== i 2)
    {
      (while true
        0)
      ""
    }
    (fmtInt (* i 10))))

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  (let ((opts (taskWithDeadline (taskOpts 4 64) 200000000)))
    {
      (for r in (taskMapWith work 4 opts)
        (match r
          ((Ok s) (println "answered {s}"))
          ((Err e)
            (let ((code (errCode e)))
              (if (== code sysTimedOut)
                (println "ran past its deadline")
                (println "failed with {code}"))))))
      0
    }))
```

```text
answered 0
answered 10
ran past its deadline
answered 30
```

`taskCancel` on the token stops the pool from starting anything more.
Running tasks get the grace period to finish and are then killed. No
task outlives the call: a return, a trap in your code or a cancellation
kills and reaps every task that is still running. `taskFold` streams
the answers through a step function instead of keeping them all, so a
pool of any length runs in flat memory.

Tested by `tests/stdlib/542-task-codec.ax` and
`tests/stdlib/543-task-failures.ax`.

### What stays the same from run to run

When every binding and task computes from its own inputs alone, the
answer doesn't depend on which one finished first:

- Answers come back in the order written or submitted, at every width
  and in both lowerings.
- `taskFold` combines them in that order too, so a `Float` sum over
  tasks has the same bits as a loop adding the same values in turn. A
  sum grouped another way, in chunks say, rounds differently.
- When several tasks fail, `parMapWords` raises the lowest-numbered
  task's status. `parMapWordsChecked` and `taskMap` answer every
  failure in its own slot.

What can change between runs is anything a clock decides (a deadline,
a cancellation, `failFast`), which trap wins when two bindings fail
under `--threads`, and the order of what the tasks print. MM-PAR-14 in
[memory-model.md](memory-model.md) has the full rule.

Tested by `tests/stdlib/620-par-float-order.ax` and
`tests/stdlib/621-par-first-failure.ax`.

### Where `parallel` is available

- **Linux and darwin** have both lowerings.
- **FreeBSD** has the process lowering, and CI runs the `parallel`
  tests there. `--threads` is refused at build time with `AX4006`, and
  so is `__thread_spawn`.
- **Windows**, `windows-x86_64` and `windows-aarch64`, has no `fork`
  and no thread lowering. `--threads`
  and `__thread_spawn` are `AX4006`. Without them, a program that uses
  `parallel` builds with an `AX4007` warning, and every spawn and join
  is lowered to a trap. A
  program whose `parallel` sits on a path it never takes builds and
  runs. One that reaches it prints
  `axiom: parallel is not available on this target` and exits with
  status 79.

A spawn the kernel refuses exits with status 78 on every target.

### Under the hood

The parser desugars `parallel` into `let`s over pairs of primitives.
`__par_spawn`/`__par_join` follow `--threads`, while
`__thread_spawn`/`__thread_join` and `__proc_spawn`/`__proc_join` name
their lowering. Each spawn is `(-> (-> Int Int) Int Spawn)`, each join
is `(-> Spawn Int)`, and all of them carry `IO`. A `Spawn` is a handle:
an `Int` isn't one, a binding may not capture one, and a join of a
handle already joined exits with status 85 without touching the
binding's page. `(__spawn_pid h)` answers the pid a forked binding runs
as.

Each join has a non-raising twin: `__par_join_nr`, `__thread_join_nr`
and `__proc_join_nr`, each `(-> Spawn Int Int)` over a handle and an
out-cell. It stores the child's decoded wait status (0, an exit code,
or 128 plus the signal) instead of re-raising it. It answers the
thunk's word, or 0 when the child never answered. `parallel` always
uses the raising join; `parMapWordsChecked` uses the twins.

A hand-written `__par_spawn` or `__thread_spawn` gets extra `AX3064`
checks, since `parallel` itself always passes a literal lambda:

- A thunk that is a frame-local name of arrow type, such as a
  parameter or a `let`-bound function, is refused at the name. The
  function it holds may capture a reference the checker can't see.
  Write the lambda at the spawn, or name a top-level function.
- A conditional, a `match` or a `let`-built closure is walked to every
  lambda it can answer, and each is checked where it stands.
- Any other shape, such as a call result or a field, is refused, since
  its captures aren't visible.

`__proc_spawn` and `__proc_join` are exempt, because they name the
forked lowering, whose isolation holds by construction. `stdlib/Par.ax`
is built on that exemption.

Tested by `tests/diagnostics/643-parallel-capture-hop.ax` and `tests/diagnostics/644-parallel-thunk-shape.ax`.

## Calling Rust

An `extern` block lets you call functions from a Rust crate, or any
static archive, as ordinary Axiom functions. [ffi.md](ffi.md) is the
full guide: writing the crate, the generated wrappers and what crosses
the boundary.

```scheme
(pub extern "axiom_demo"
  (add         :: (-> Int Int Int) (symbol "axffi_add"))
  (countVowels :: (-> String Int)  (symbol "axffi_count_vowels")))
```

Each item carries its type inline and the linker symbol it binds. Build
against the crate with one flag:

```bash
axiom build --input p.ax --output p --crate path/to/crate
```

The driver runs `axiom-bindgen` when the crate's `axiom/` module is
missing or older than its `src/`. It runs `cargo build --release` when
the archive is missing, each only if the tool is on `PATH`. Then it
links the archive, because the block's library name says to.

`--link-lib NAME --link-search DIR` and `$AXIOM_LINK_SEARCH` override
the search. An `$AXIOM_PATH` entry's `../target/release` is searched
too.

A call to an item compiles like a call to an Axiom function, and only
the items your program calls are declared.

### Rules for an `extern` block

- **The type is inline and required.** A separate `(:: name Type)` is
  `AX3015`, and an item without `:: type` is a parse error.
- **Only word types cross.** A signature names only `Int`, `Float`,
  `Bool`, `Char`, `String` and `Foreign`, one machine word each way. It
  may also take a callback parameter: an arrow of one to three
  arguments whose argument and result types are all `Int`, `Float`,
  `Bool` or `Char`. A type
  variable, a tuple, any other function type or a declared type (such
  as `(Option Int)`, `Handle` or a struct) is `AX3036`.
- **`(symbol "...")` is the only clause.** Any other head is a parse
  error that names it. Write it explicitly: a static link is one flat
  namespace, and the default is the Axiom name.
- **Calling an item performs `IO`**, as `__syscallN` does, and the
  effect propagates to every caller.
- **An item's name is taken.** A `fn` spelled like an item is a
  duplicate (`AX3006`). Two blocks naming one library are fine.

Richer values cross as a `Foreign` handle or through the generated
wrapper. A Rust `Vec<T>` result becomes a `Vec`, and a Rust
`#[axiom_record]` struct becomes a `data` type whose fields cross one
word each.

### When a symbol doesn't link

A symbol that no linked archive defines is `AX4004` at the item, before
the toolchain runs. The message covers three cases: nothing linked at
all, an archive linked that lacks the name (with the nearest `axffi_*`
name it does hold), and the search path it used. The check reads the
archives' symbol tables, so a prefix of a real name is refused as the
typo it is.

Every `#[axiom_export]` shim carries a shape descriptor, as in
`axffi_add__sig_ii_i`. A symbol the archive exports with a different
shape is `AX4005` at the item.

### Call Axiom from Rust

`--emit-staticlib` goes the other way. It archives a module with no
`main`, with every `pub fn` a C symbol under its own name, for a Rust
or C host to link. `--emit-rust-binding` beside it writes the Rust
module that declares and wraps those functions:

```bash
axiom build --input lib.ax --output libaxiom_lib.a --emit-staticlib --emit-rust-binding lib.rs
```

| Axiom | Rust |
|---|---|
| `Int` | `i64` |
| `Float` | `f64` |
| `Bool` | `bool` |
| `Char` | `char` |
| `String` | `&str` in, `AxString` out |
| a `data` or `struct` type | a Rust `struct` or `enum` |
| `Option`, `Result` | Rust's own |

The build adds the accessor shims those conversions need to the
archive. A function whose type the binding can't carry (a type
variable, a tuple or an arrow) is named in a comment instead.

`foreign` is a removed construct and is still `AX2004`. Use `extern`.

## Standard library

Axiom's standard library is written in Axiom. It gives you strings,
collections, files, processes, formatting, testing and more, and it
reaches the operating system through raw syscalls, so your program
needs no C library.

```scheme
(import IO)
(import Map)
(import Str)
(import Vec)

; Count how often each word length appears in a sentence.
(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((words (strSplit "the quick brown fox jumps over the lazy dog" 32))
        (counts mapNew))
    {
      (for w in words
        (let ((n (strLen w)))
          (mapInsert counts n (+ (mapGet counts n 0) 1))))
      (for n in (vecSort (mapKeys counts))
        (let ((c (mapGet counts n 0)))
          (println "{n} letters: {c}")))
      0
    }))
```

```text
3 letters: 4
4 letters: 2
5 letters: 3
```

A program that links nothing else makes no libc call at all, whether
it prints, allocates or reads a file. The one exception is an `extern`
block that links a Rust crate through the C ABI ([Calling
Rust](#calling-rust), and [ffi.md](ffi.md) §15). The older `foreign`
keyword is removed and reserved, and using it is `AX2004` ([Removed
features](#removed-features)).

On Windows, which has no syscall ABI, the same library reaches the OS
through kernel32 instead, on both `windows-x86_64` and `windows-aarch64`. Every import it may use is listed in
`scripts/platform-allow.windows.txt`, and that list holds no libc name.

Checked by `scripts/check-freestanding.sh`.

### Modules at a Glance

Sixty-one modules, all of them Axiom source under `stdlib/`, plus the six `Sys.Platform.*` files — one target's syscall numbers each, covered by the `Sys` row. A module exports only the
names it marks `pub`, and reaching any other name is `AX3023`, so
`grep '^(pub' stdlib/M.ax` always tells you what module `M` exports.

The table says what each module is for and names its main functions.
For every public name, with its type, its effects and a one-line
summary, see [stdlib-api.md](stdlib-api.md). That page is generated
from the library's own source by `examples/axdoc/axdoc.ax`, and CI
regenerates it on every run to keep it exact.

| Module | Provides |
|---|---|
| `Pre` | The prelude macros: `when` and `unless` (conditionals), `deriveEq`, `deriveShow`, `deriveArity`, `showOr`. |
| `Mem` | Raw memory: `memAlloc`, `memAllocMapped`, `memMarkArray`/`memMarkLeaf`, `memCopy`, `memSet`, `memCmp`, `memGetByte`/`memPutByte`, `memGetWord`/`memSetWord`. |
| `Str` | The byte view of a `Str`: `strFromLit`, `strAlloc`, `strLen`, `strByte`, `strCmp`, `strEq`, `strSlice`, `strDup`, `strConcat`, `strFindByte`, `strStartsWith`, `strSplit`, `strCStr`, and the `format` macro. String literals are already `Str` values ([Literals](#literals)). |
| `Utf8` | The character view of a `Str`: `utf8Len`, `utf8CharAt`, `utf8DecodeAt`, `utf8FromChar`, `utf8Next`, `utf8Offset`, `utf8Slice`, `utf8Width`, `utf8SeqLen`, `utf8IsCont`, `utf8Valid`, `utf8WellFormedAt`. |
| `Vec` | A growable array, `(Vec a)`: `vecNew`, `vecNewRef`, `vecWithCapacity`, `vecWithCapacityRef`, `vecFree`, `vecPush`, `vecPop`, `vecGet`, `vecSet`, `vecLen`, `vecCap`, `vecLast`, `vecClear`, `vecSort`, `vecSortBy`. `vecGet` traps on an index it can't serve. |
| `Map` | An open-addressing `Int→Int` hash map: `mapNew`, `mapNewRefVals`, `mapWithCapacity`, `mapWithCapacityRefVals`, `mapFree`, `mapHas`, `mapGet`, `mapGetStr`, `mapInsert`, `mapRemove`, `mapKeys`, `mapLen`, `mapCap`, `mapUsed`. `mapGet` takes the default to answer when a key is absent. |
| `Fmt` | The functions a format specifier selects: `fmtInt`, `fmtHex`, `fmtHexUpper`, `fmtFloat`, `fmtFloatPrec`, `fmtPadLeft`, `fmtPadRight`, `fmtPadCenter`, `fmtPadZerosLeft`, `fmtIntWidth`. The `format` macro itself lives in `Str` and arrives via transitivity. |
| `Float` | IEEE 754 binary64 values exactly: `floatParse` reads decimal text correctly rounded, `floatToString` prints the shortest text that reads back to the same bits (in Python's `repr` format), and `floatToBits`/`floatFromBits` convert to and from the 64-bit encoding. Also `floatIsNan`, `floatIsInfinite`, `floatIsFinite`, `floatInfinity` and `floatNan`. |
| `Err` | `Result` (`Ok`/`Err`), the `Error` record, `isOk`/`isErr`, `okOr`, `unwrapOr`, `mapOk`/`mapErr`, `andThen`, `try`, `toOption`, `withContext`, and checked arithmetic: `addChecked`, `subChecked`, `mulChecked`, `divChecked`, `remChecked`, `shlChecked`, `shrChecked`. The specification is [error-model.md](error-model.md). |
| `Fallible` | `fallibleMalformed`, the operation a batch loop's callee performs on a malformed record, and the handlers that answer it without unwinding: `fallibleSkip`, `fallibleDefault`, `fallibleCounting`. Also the skip sentinel `fallibleSkipped`/`fallibleIsSkipped`, and the `FallibleTally` a counting handler writes, read with `fallibleTally`/`fallibleCount` (error-model.md ERR-REC-7). |
| `Intern` | A string interner: `internNew`, `internFree`, `internIntern`, `internFind`, `internLookup`, `internCount`. |
| `Sys` | The syscall layer: `sysWriteFd`, `sysReadFd`, `sysWriteAllFd`, `sysReadAllFd`, `sysReadLineFd`, `sysOpenPath`, `sysCloseFd`, `sysExitWith`, `sysFailed`, `sysErrno`, `stdin`/`stdout`/`stderr`. The [filesystem](#work-with-files-and-directories) calls, and processes: `sysSpawn`, `sysRun`, `sysRunPath`, `sysWaitPid`, `sysEnv`, `sysArgc`, `sysArg`, `sysGetPid`, `sysNowMicros`. Shared memory and waiting on it: `sysMapShared`/`sysUnmapShared`, `sysWaitWord`/`sysWakeWord`, the timed `sysWaitWordTimeout` (0 woken, 1 timed out, 2 changed) with `sysTimeoutMicros` and `sysTimedOut`, and `sysChildExited`, which looks at a child without reaping it. |
| `Path` | Path strings, with no syscalls: `pathDir`, `pathBase`, `pathExt`, `pathStem`, `pathJoin`, `pathReplaceExt`, `pathWithSlash`, `pathIsAbsolute`, `pathLastSlash`, `pathExtIndex`, `pathClean`. |
| `IO` | The `println` and `eprintln` macros ([Printing and formatting](#printing-and-formatting)), `writeStr` and `writeSlice` (bytes as given, with no newline and no rendering), `readLine`, `readAll` and `readInto` over descriptors, the owned `File` with `fileClose`, `fileReadLine`, `fileReadAll`, `fileReadInto` and `fileWrite`, the [filesystem](#work-with-files-and-directories) calls, `randomBytes`, the [terminal](#terminals) calls, the raw-address `printlnLit`/`readFileLit`, `exit`, `die` and `todo`. |
| `Ffi` | Helpers a generated Rust binding needs: `ffiHandleNew`/`ffiHandlePtr`/`ffiHandleClose`, the out-cell (`ffiCellNew`, `ffiCellWord`, `ffiCellFree`) and the `Vec` conversions ([ffi.md](ffi.md)). |
| `Json` | `jsonParse`, `jsonWrite`, and the constructors and accessors between them. Written for JSON-RPC. |
| `Rpc` | The LSP base protocol's framing over a file descriptor: `rpcReadMsg` (`None` once the stream ends, `Some` every whole frame, an empty one included), `rpcRead`, `rpcWrite`, and the reader `rdNew`/`rdBuf`/`rdFilled`. |
| `Par` | `parMapWords`, a bounded pool of concurrent tasks joined in submit order. `parRunAll` is the same pool over external commands, and `parRunOne`/`parArgvVector` are the pieces underneath. |
| `Chan` | `chanNew`, a bounded channel of words between [`parallel`](#parallel--bindings-that-run-beside-the-caller) bindings, in shared memory so forked children and threads both see it. The channel is a `Chan`, a handle only this module makes, and a call on a freed one exits with status 85. `chanSend`/`chanRecv` block while it is full or empty, and `chanClose` ends the stream. Also `chanTrySend`, `chanTryRecv`, `chanLen`, `chanClosed`, `chanCap`, `chanFree`. `chanSendTimeout`/`chanRecvTimeout` wait at most a given time and answer `Err` code `sysTimedOut` when it runs out ([memory-model.md](memory-model.md) `MM-PAR-10`, `MM-PAR-12`). |
| `Sync` | `mutexNew`, a mutex between [`parallel`](#parallel--bindings-that-run-beside-the-caller) bindings in a shared word, in both lowerings. The mutex is a `Mutex`, a handle only this module makes, and a call on a freed one exits with status 85. `mutexLock`/`mutexTryLock`/`mutexLockTimeout` answer a guard that `mutexUnlock` takes back (an unlock the caller did not earn is `Err` `syncNotHeld`), a holder found dead poisons it (`syncOwnerDead`, `mutexOwnerDead`), `mutexFree`. No fairness, no priority inheritance, not reentrant ([memory-model.md](memory-model.md) `MM-PAR-11`). |
| `Task` | `taskMap`/`taskMapWith`: `(-> Int String)` tasks in forked children, at most `width` at once, one `(Result String Error)` each in submit order. Answers cross as bytes under a per-task limit (`taskTooLargeCode`), a trap answers its wait status, a deadline kills and reaps (`sysTimedOut`), a token cancels (`taskTokenNew` answers a `CancelToken` handle; `taskCancel`, `taskCancelled`, `taskCancelledCode`), `failFast`; `TaskOpts` via `taskOpts` and `taskWith*`; `taskFold` streams the answers without keeping them ([memory-model.md](memory-model.md) `MM-PAR-13`). |
| `Net` | TCP, the way Rust's `std::net` has it: `tcpListen`, `tcpAccept` and `tcpConnect` answer sealed `TcpListener` and `TcpStream` handles, read with `tcpRead`, `tcpReadSome` and `tcpReadAll`, and write with `tcpWrite`. Also `tcpShutdown`, the peer and local addresses, `tcpSetNoDelay`, read and write timeouts, non-blocking mode, and `SocketAddr` with `socketAddrParse` for numeric IPv4 and IPv6 addresses ([Connect over TCP](#connect-over-tcp)). |
| `Chrono` | Dates, times and durations with no time zones: `Date`, `Time`, `NaiveDateTime` and `Duration`, made with `dateNew`, `timeNew`, `datetimeNew` and `durationFromSeconds` and their kin. ISO 8601 text in and out (`dateParse`, `datetimeParse`, `durationParse`, `datetimeToString`), RFC 3339 timestamps read as UTC (`datetimeParseUtc`), the clock (`datetimeNowUtc`), a small formatter (`datetimeFormat`), and arithmetic that answers `Err` `chronoOutOfRange` instead of wrapping ([chrono.md](chrono.md)). |
| `Axqlite` | An embedded database in one file, with transactions. `axqOpen` answers a `Connection`, `axqExec` runs AXQL text, and `axqPrepare` makes a `Statement` to run with bound values (`axqRun`, `axqQuery`, `axqQueryEach`). `axqBegin`, `axqCommit` and `axqRollback`, or `axqTransaction`, group writes, and `rowInt`, `rowText` and their kin read a row. The guide is [axqlite.md](axqlite.md). |
| `Axqlite.AxqlMacro` | AXQL statements written as Axiom forms and checked when the program compiles: `axqlSelect`, `axqlInsert`, `axqlUpdate`, `axqlDelete`, the table and index forms, and `axqlTable`, which declares a struct and the queries that read and write it. Each expands to a `Query` whose values are bound parameters. |
| `Axqlite.Value` | The values a column holds, `VNull`, `VInt`, `VReal`, `VText` and `VBlob`, and the error codes every Axqlite module answers. |
| `Axqlite.AxqlParse` | AXQL text to statements: `axqlParse` and `axqlParseScript`. [axql.md](axql.md) is the language reference. For implementers. |
| `Axqlite.AxqlAst` | The parsed form of one AXQL statement. For implementers. |
| `Axqlite.AxqlEval` | What AXQL's operators do to values: three-valued logic, checked integer arithmetic and exact mixed comparison (`axqlCompare`, `axqlArith`). For implementers. |
| `Axqlite.AxqlSchema` | The tables and indices a database holds, read from its schema table: `axqlLoadSchema` and `axqlTableDef`. For implementers. |
| `Axqlite.AxqlExec` | Planning and running one statement: binding names, checking types, choosing an index and undoing a failed statement (`axqlPlanSelect`, `axqlRunSelect`, `axqlRunWrite`). For implementers. |
| `Axqlite.Btree` | The B+tree tables and indices are stored in: `btreeCreate`, `btreeGet`, `btreePut`, `btreeDelete` and `btreeScan` over byte-string keys. For implementers. |
| `Axqlite.Record` | Rows as bytes, and keys whose byte order is their values' order: `recEncode` and `recDecode`. For implementers. |
| `Axqlite.Pager` | One database file as numbered pages: the page cache, the file lock, the rollback journal, commit, rollback and recovery (`pagerOpen`, `pagerBeginWrite`, `pagerCommit`). [axqlite-format.md](axqlite-format.md) is the file format. For implementers. |
| `Test` | `assertEq`, `assertNe`, `assertStrEq`, `assertTrue`, `assertFalse`, `testFail`, and the `Assert` effect a failed assertion performs, which `axiom test` uses to find and isolate failures (error-model.md ERR-REC-6). |
| `Agent.Tags` | Reads the AXSYM stream, not the compiler's internals: `axsymParse`, `axsymLine`, and the accessors over one parsed line, `symTag`, `symHasTag`, `symEffects`, `symDerivedPure`, `symAgentTag`, `symHasAgentTag` ([agent-harness.md](agent-harness.md) §3.2). |
| `Tui.Keys` | Terminal input bytes to key events, as pure functions ([line editor](#build-a-line-editor)). |
| `Tui.Edit` | A line editor that performs no I/O ([line editor](#build-a-line-editor)). |
| `Tui.Term` | The part of the line editor that reads the terminal ([line editor](#build-a-line-editor)). |
| `Crypto.Random` | Secure random values from the kernel: `secureRandomBytes`, `randomBelow`, `randomRange`, `randomShuffle`, `randomWord`, the tokens `randomTokenHex`/`randomTokenUrl`, and `randomFill` for key generators. Where the target has no secure source, each call answers `Err`; none falls back to a clock or a counter. |
| `Crypto.Secret` | Where keys live. `SecretBytes` is a handle that prints as `<SecretBytes>`, over locked memory outside the arena: `secretRandom`, `secretFromString`, `secretLen`, `secretEq`, `secretWipe`, and `secretExposeCopy` for the one time you mean to write a key out. Using a wiped secret exits with status 85. |
| `Crypto.Bytes` | Byte strings for cryptography: `bytesEqCt` compares in constant time, `hexEncode`/`hexDecode` and the base64 codecs (`b64Encode`, `b64EncodeNoPad`, `b64UrlEncode` and their strict decoders) run in constant time, and `bytesU32Be` and its kin encode integers. |
| `Crypto.Sha2` | SHA-256, SHA-384 and SHA-512 (FIPS 180-4): `sha256`, `sha384` and `sha512` hash a string, and `Sha256` and its kin hash a stream (`sha256New`, `sha256Update`, `sha256Final`, `sha256Copy`, `sha256Wipe`). |
| `Crypto.Sha3` | SHA3-224 to SHA3-512 and the SHAKE128 and SHAKE256 extendable-output functions (FIPS 202): `sha3_256` and its kin, `shake128` and `shake256`, streaming `Sha3`, and `Shake128`/`Shake256` states you absorb into once and squeeze as often as you like. `keccakF1600` is the permutation. |
| `Crypto.Blake2b` | BLAKE2b (RFC 7693), unkeyed or keyed, 1 to 64 bytes of output: `blake2b`, `blake2b512`, `blake2b256`, and the streaming `Blake2b` (`blake2bNew`, `blake2bNewKeyed`, `blake2bUpdate`, `blake2bFinal`). |
| `Crypto.Hmac` | HMAC-SHA-256 and HMAC-SHA-512 (RFC 2104) over sealed keys: `hmacSha256` and `hmacSha256Verify`, which compares in constant time, over an `HmacSha256Key` from `hmacSha256KeyGenerate` or `hmacSha256KeyFromSecret`, streaming `HmacSha256`, and the same for 512. |
| `Crypto.Hkdf` | HKDF (RFC 5869) with SHA-256 or SHA-512: `hkdfSha256` derives keys from input keying material, a salt and an info string, and `hkdfSha256Extract` and `hkdfSha256Expand` are its two halves. Keys go in and come out as `SecretBytes`. |
| `Crypto.AesGcm` | AES-GCM authenticated encryption (NIST SP 800-38D) with 256- and 128-bit keys: `aes256GcmSeal` and `aes256GcmOpen` over an `Aes256GcmKey`, which `aes256GcmKeyGenerate`, `aes256GcmKeyFromSecret`, `aes256GcmKeyExport` and `aes256GcmKeyWipe` manage, and the same for 128 ([Authenticated encryption](crypto.md#authenticated-encryption)). |
| `Crypto.ChaCha20Poly1305` | ChaCha20-Poly1305 authenticated encryption (RFC 8439): `chacha20Poly1305Seal` and `chacha20Poly1305Open` over a `ChaCha20Poly1305Key`, with the same key functions. |
| `Crypto.Aead` | The 12-byte `AeadNonce` both ciphers take (`aeadNonceFromBytes`, `aeadNonceRandom`), and `NonceSequence`, a counter that answers a fresh nonce until it runs out and never repeats one (`nonceSequenceNew`, `nonceSequenceNext`, `nonceSequenceResume`). |
| `Crypto.X25519` | Key agreement over Curve25519 (RFC 7748): `x25519` answers the shared secret for your `X25519SecretKey` and a peer's `X25519PublicKey`, as `SecretBytes`. Keys come from `x25519KeyGenerate` or `x25519KeyFromSecret`, and `x25519PublicKeyFromBytes` reads a peer's key. |
| `Crypto.Ed25519` | Ed25519 signatures (RFC 8032): `ed25519Sign` signs a message with an `Ed25519SecretKey`, and `ed25519Verify` checks an `Ed25519Signature` against an `Ed25519PublicKey`. Public keys and signatures decode strictly (`ed25519PublicKeyFromBytes`, `ed25519SignatureFromBytes`). |
| `Crypto.Aes` | The AES block cipher (FIPS 197) with 128-, 192- and 256-bit keys, bitsliced so no table is indexed by a secret: `aesKeyExpand`, `aesEncryptBlocks`, `aesDecryptBlocks`, and `aesCtr32Xor`, GCM's counter mode. For implementers. |
| `Crypto.Ghash` | GCM's authenticator, `ghashUpdate`, a carry-less multiply with no tables. For implementers. |
| `Crypto.ChaCha20` | The ChaCha20 stream cipher (RFC 8439): `chacha20Block` and `chacha20Xor`. For implementers. |
| `Crypto.Poly1305` | The Poly1305 one-time authenticator (RFC 8439): `poly1305Mac`, and the incremental `poly1305Init`, `poly1305Blocks`, `poly1305AbsorbPadded` and `poly1305Finish`. For implementers. |
| `Crypto.Curve25519` | The Ed25519 group: point addition and doubling, the constant-time fixed-base multiplication `ge25519ScalarMultBase`, and strict encoding and decoding. For implementers. |
| `Crypto.Field25519` | Arithmetic modulo 2²⁵⁵ − 19 on ten-limb field elements at raw addresses: `fe25519Mul`, `fe25519Invert`, `fe25519CSwap` and their kin. For implementers. |
| `Crypto.Curve25519Scalar` | Arithmetic modulo the Ed25519 group order: `sc25519Reduce`, `sc25519MulAdd` and `sc25519IsCanonical`. For implementers. |
| `Crypto.Ct` | The constant-time layer the other Crypto modules are built from: masks and `ctSelect`, the `ctBarrier` value barrier, byte-order loads and stores, and `ctWipe`, an erasure the optimiser can't remove. For implementers. |
| `Crypto.Errors` | The error codes every Crypto module answers, from `cryptoInvalidLength` (1101) to `cryptoInvalidKey` (1109), and the helpers that build them. |

A few `IO` names need a word more:

- `(readLine stdin)` is how a program reads what was typed or piped
  at it. `readAll` reads the rest of a descriptor.
- `todo` stands in for code you haven't written yet. It has whatever
  type the context needs, and when it runs it prints `todo: <what>`
  and exits 70. `AX3005`'s machine-applicable fix writes one into each
  missing `match` arm.
- `format`, `println` and `eprintln` choose each hole's rendering at
  compile time from the value's static type: `Int`, `Float`, `Bool`,
  `Char`, `String`, and any `data` or `struct` built from them. An
  argument with no rendering is `AX3025`.

<a id="the-filesystem"></a>
### Work with files and directories

`IO` gives you files and directories by name:

```scheme
(import IO)
(import Path)
(import Err)

(:: main (Result Int Error))
;@axiom:effect(io)
(fn (main)
  (let ((file (pathJoin "notes" "today.txt")))
    (try _ (makeDirAll "notes")
      (try _ (writeFile file "first\n")
        (try _ (appendFile file "second\n")
          {
            (println (readFile file))
            (println (pathExt file))
            (println (pathStem file))
            (println (pathReplaceExt file ".md"))
            (try _ (removeFile file)
              (removeDir "notes"))
          })))))
```

```text
first
second

.txt
today
notes/today.md
```

Nothing throws. Most calls that can fail answer a `Result`, and
`(try x e body)` binds `x` to the value inside `Ok` and continues with
`body`, or returns the `Err` as it is. An `Err` from `IO` carries the
errno as its code and names the path or descriptor in its message.
`readFile` and `listDir` answer an empty value instead, as described
below. `makeDirAll` treats a directory that already exists as success,
so you can call it without checking first.

There are two layers over the same syscalls. `Sys` takes a raw
NUL-terminated `char*`, because it hands one straight to the kernel.
`IO` takes a `Str` and copies it, so a `strSlice` can't reach the
kernel unterminated. Reach for `IO`.

`Sys` is the unsafe layer. Each call that hands the kernel an address
is a precondition interface, so a function that calls one must say
`;@axiom:effect(unsafe)` (`AX3073`), and `restrict(no-unsafe)` refuses
it. `IO`'s calls hand the kernel only bytes a `Str` holds, so they need
no tag and hold under `restrict(no-unsafe)`.

| Task | `IO` (takes a `Str`) | `Sys` (takes a `char*`) |
|---|---|---|
| open one, for an owned file | `openPath` | `sysOpenPath` |
| open one inside a directory, following no link | `openBeneath` | `sysOpenBeneath` |
| read a whole file | `readFile` | `sysReadFile` |
| read one line of a descriptor | `readLine` | `sysReadLineFd` |
| read a descriptor to end of input | `readAll` | `sysReadAllFd` |
| read what a descriptor has into a buffer | `readInto` | `sysReadFd` |
| write a string, or part of one, to a descriptor | `writeStr`, `writeSlice` | `sysWriteAllFd` |
| write one, truncating | `writeFile` | `sysWriteFile` |
| add to the end of one | `appendFile` | `sysAppendFile` |
| duplicate one | `copyFile` | — |
| move or rename | `renamePath` | `sysRename` |
| delete a file | `removeFile` | `sysUnlink` |
| is it there? | `fileExists` | `sysFileExists` |
| is it a directory? | `isDir` | `sysIsDir` |
| how big? | `fileSize` | `sysFileSize` |
| *why* can it not be read? | `readErrno` | `sysReadErrno` |
| make a directory | `makeDir`, `makeDirMode` | `sysMkdir` |
| make it and its parents | `makeDirAll` | — |
| make a symbolic link | `makeSymlink` | `sysSymlink` |
| remove an empty directory | `removeDir` | `sysRmdir` |
| what is in a directory? | `listDir` | `sysReadDir` |
| where am I? | `cwd` | `sysGetCwd` |
| random bytes | `randomBytes` | `sysRandomBytes` |

`openPath` answers a `File`, not a descriptor. The file closes when
its last owner leaves scope, or earlier with `fileClose`. Read it
with `fileReadLine`, `fileReadAll` and `fileReadInto`, and write it
with `fileWrite`. The descriptor calls take an `Int` in both layers:
`stdin`, or what `fileFd` borrows from a file. `readInto` fills a
range of a `String` buffer you made with `strAlloc`, and `writeSlice`
writes a range of a string. A range that runs outside the string stops
the program with status 77, the index trap, before the kernel sees it.

`readLine` and `readAll` answer a `Result`, with end of input inside
the `Ok`: `(Ok None)` for a line, `(Ok "")` for the rest. A read
that fails isn't an input that ended, and you can't ask a stream
`readErrno` afterwards. `readLine` makes one `read(2)` call per byte so
it never takes a byte it doesn't return. `stdlib/Sys.ax` notes the cost
and what to use for bulk input.

Walking a directory is a `for` loop over the `Vec` that `listDir`
answers:

```scheme
(import IO)
(import Path)
(import Str)
(import Err)

; Print every `.ax` file in `dir` with its size, one per line.
(:: report (-> String Int))
;@axiom:effect(io)
(fn (report dir)
  {
    (for name in (listDir dir)
      (let ((p (pathJoin dir name)))
        (if (strEq (pathExt p) ".ax")
            (match (fileSize p)
              ((Ok size) (println "{p}  {size}"))
              ((Err e)   (let ((why (errorText e)))
                           (eprintln "{p}  unreadable: {why}"))))
            0)))
    0
  })

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (report "stdlib"))
```

`listDir` answers a `(Vec String)` of names, sorted, without `.` and
`..`. `fileSize` answers a `Result`, so a size and an errno can't be
mixed up. Match on it: `(unwrapOr (fileSize p) 0)` would report an
unreadable file as zero bytes. Use `unwrapOr` only where the fallback
really means the same as the error ([error-model.md](error-model.md)).

Three things to know before you use these:

- **`readFile` answers `""` in four situations:** a missing file, an
  empty file, a directory, and a file that couldn't be opened. Ask
  `readErrno` to tell them apart: `0` readable, `2` missing, `13` not
  permitted, `21` a directory.
- **`listDir` is sorted and drops `.` and `..`.** `readdir` order
  depends on the filesystem and differs between machines, so an
  unsorted walk isn't reproducible. `Sys.sysReadDir` is the unsorted
  primitive. It keeps the two dot entries, so an empty answer always
  means failure: a readable directory always holds them.
- **There is no `stat` and no `chdir`.** `struct stat`'s layout differs
  by platform, so the questions it answers are asked with `open`,
  `read` and `lseek` instead. `chdir` is left out because nothing
  needs it, and a process that changes directory breaks every relative
  path anything else is holding.

Tested by `tests/stdlib/698-file-lifetime.ax`.

<a id="a-str-is"></a>
### Connect over TCP

`Net` is the standard library's networking: TCP listeners and streams,
and the socket addresses they open on. Protocols above TCP, such as
HTTP and TLS, are libraries a program brings.

```scheme
(import IO)
(import Err)
(import Net)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (match (andThen (socketAddrParse "127.0.0.1:0") tcpListen)
    ((Err e) (die (errorText e) 1))
    ((Ok lsn)
      (match (andThen (tcpListenerAddr lsn) tcpConnect)
        ((Err e) (die (errorText e) 1))
        ((Ok client)
          (match (tcpAccept lsn)
            ((Err e) (die (errorText e) 1))
            ((Ok server)
              {
                (let ((_ (tcpWrite client "ping")))
                  (println (unwrapOr (tcpReadSome server 64) "")))
                (let ((_ (tcpClose client)) (_ (tcpClose server)) (_ (tcpListenerClose lsn)))
                  0)
              })))))))
```

```text
ping
```

Port 0 asks the kernel for a free port, and `tcpListenerAddr` says
which one it chose. A loopback connection lands in the listener's
queue straight away, so one program can be both ends.

- Streams block by default. `tcpSetNonBlocking` switches one, and
  `tcpStreamFd` hands its descriptor to `Sys`'s readiness calls
  (`netPollCreate`, `netPollWait`).
- A write to a peer that has closed answers `Err`. It doesn't end the
  program with SIGPIPE.
- A stream or listener closes when its last owner leaves scope.
  `tcpClose` and `tcpListenerClose` close one early.
- A closed stream or listener used again stops the program with status
  85, before the descriptor number reaches a file the kernel has since
  given it to.
- `socketAddrParse` reads numbers only, `127.0.0.1:80` or `[::1]:80`.
  There's no name lookup, because the only resolver a freestanding
  program could call is the C library's.

Tested by `tests/stdlib/650-net-tcp.ax` and
`tests/stdlib/651-net-closed.ax`.

### Strings are bytes

A `Str` is a length-counted string of bytes, and `Str`'s own functions
work on bytes. `strLen` counts bytes, `strByte` reads one, and
`strSlice` cuts at byte offsets. Every syscall write, every hash and
every buffer size works in bytes too, so a `strLen` that counted
characters would write the wrong number of bytes to a file descriptor.

Because a `Str` knows its length, it can hold a NUL byte. The strings
`Str` builds are also NUL-terminated, so `strCStr` hands one to a
syscall without copying. A slice shares its parent's bytes and isn't
necessarily terminated, which is why `IO` copies a path first.

`printlnLit` and `readFileLit` take a raw NUL-terminated address
instead of a `Str`. Since a literal is already a `Str`, you rarely want
them: `(println "hi")` is shorter and cheaper than
`(printlnLit (__addr "hi"))`. They are for bytes that arrived without a
length, such as a syscall buffer.

*Under the hood:* a `Str` is the address of a three-word header: the
length in bytes, the address of the bytes, and the block that owns
them (or 0 when no block does). A slice shares its parent's bytes and
inherits that owner, so it keeps the buffer alive however many times
it is cut. See [memory-model.md](memory-model.md) MM-VAL-7.

<a id="text-is-utf-8-and-str-stays-bytes"></a>
### Work with UTF-8 text

Text is UTF-8, and the character view of a `Str` lives in `Utf8`:

```scheme
(import IO)
(import Str)
(import Utf8)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (strLen "héllo"))                 ; bytes
    (println (utf8Len "héllo"))                ; characters
    (println (utf8Offset "aé世" 2))            ; byte offset of the third character
    (println (utf8Slice "héllo, 世界" 7 2))    ; characters 7 and 8
    (println (utf8FromChar (cast Int '世')))   ; a new one-character Str
    (match (utf8CharAt "aé世" 2)
      ((Some c) (println c))                   ; the code point of 世
      (None     (println "no character there")))
    (match (utf8CharAt "aé世" 9)
      ((Some c) (println c))
      (None     (println "no character there")))
    0
  })
```

```text
6
5
3
世界
世
19990
no character there
```

This is the same split Rust draws between `len()` and
`chars().count()`. It works because a `Char` is already a code point:
`(utf8DecodeAt "é" 0)` answers `(Some 233)`, and `'é'` is 233.
`utf8Slice` shares the original's bytes.

Character indexing is O(n) in the byte length, because UTF-8 is
variable-width and nothing builds an index. Walk a string with
`utf8Next`, not by a rising character index, or the loop is quadratic.

The rules for bad input:

- Decoding answers `None` when there is no character to read: past
  the end, on a sequence cut short by the end of the string, or on a
  byte that begins no sequence. `utf8DecodeAt`, `utf8CharAt` and
  `strFindByte` all answer `(Option Int)` and allocate nothing. A guess
  would be worse: read as bytes padded with zeros, the first byte of
  `世` decodes to `U+4000`, an ordinary CJK character, and the tail
  byte of `é` to `©`.
- Iteration never stalls. `utf8SeqLen` answers 1 for a byte it
  doesn't understand, so `utf8Next` always advances and no decoding
  loop can hang on a corrupt file. Ask `utf8Valid` for a verdict on a
  whole string. `utf8Valid` checks structure: lead byte and
  continuation count, not ranges. `utf8WellFormedAt` is the strict
  question, Unicode's Table 3-7 at one offset, so an overlong form, an
  encoded surrogate and a code point past U+10FFFF answer 0 there. It
  is what the compiler's diagnostic writers ask before they copy a
  byte: every renderer writes a byte that begins no well-formed
  character as U+FFFD (`\ufffd` in the JSON), and so does `Json`'s
  string escaper.
- Encoding always succeeds. `utf8FromChar` always produces
  well-formed UTF-8. Anything that isn't a Unicode scalar value
  (negative, a surrogate, or past `U+10FFFF`) is encoded as `U+FFFD`, so
  `(utf8Valid (utf8FromChar x))` holds for every `x`.

Most of `Str` is already correct on text. UTF-8 orders bytes the same
way Unicode orders code points, so `strCmp`, `strEq` and
`strStartsWith` work unchanged. And no multi-byte sequence contains a
byte below `0x80`, so `strFindByte` searching for an ASCII byte never
matches the middle of a character.

<a id="build-a-line-editor"></a>
### Build a line editor

The three `Tui` modules make an interactive line editor, split so that
most of it can be tested without a terminal. For the terminal
primitives underneath, see [Terminals](#terminals).

- `Tui.Keys` turns input bytes into key events, as pure functions:
  the `KeyEv` record and its `KEY_*`/`MOD_*` tables, `keyScan` (buffer,
  valid length, offset → one event), and `keyResolve` for a prefix that
  stopped arriving. CSI and SS3 sequences are parsed in full before
  they are interpreted. So an unbound but well-formed sequence, such as
  a mouse report, a cursor-position reply or an OSC title report, is
  consumed whole and reported as `KEY_NONE`, not typed into the line a
  byte at a time. Multi-byte characters go through `Utf8`. Every
  function is `restrict(no-io,no-foreign)`.
- `Tui.Edit` is a line editor over a gap buffer of code points:
  insert, backspace, delete, moving by character and by word, line
  start and end, the four kills with one 16-entry kill ring, and yank
  and yank-pop. Its redraw stays correct when the line wraps. It
  performs no I/O: `ledRefresh` appends fragments to a `Vec` you pass
  in. You say what counts as a word with `wordChars`, and the prompt
  arrives already painted and is measured with `tuiVisLen`, so the
  editor knows nothing about what language is being typed. It also has
  `tuiCat`, the allocate-once join the redraw uses.
- `Tui.Term` is the only part that touches a descriptor. It has
  the `KeyIn` reader over `sysReadFd`, and a 30 ms timed wait, built on
  the `netPoll*` readiness layer, that resolves a lone ESC.
  `termRawEnter`/`termRawLeave` wrap a single call, `termFlush` writes
  out, and `termEditLoop` answers a line, or `None` at end of input.
  Raw mode is entered for each line and left while your program
  evaluates it. So your ordinary output needs no carriage returns
  added, and an exit from inside a command can't leave the terminal in
  raw mode.

Tested by `tests/selfhost/975-key-decode.ax`, which checks the whole
escape grammar with no terminal involved.

## AXTAG metadata

An AXTAG is a comment that records a claim about a declaration, for
people and for tools. You write `;@axiom:<key>(<value>)` on the line
directly above the declaration. The compiler checks the claims it can,
and `axiom symbols --diagnostic-format ai` prints each accepted tag as
`#` metadata on the declaration's AXSYM line
([agent-harness.md](agent-harness.md)).

```scheme fragment
;@axiom:effect(io)
(fn (main) (println "hello"))

;@axiom:effect(pure)
(fn (pureFn x) (* x x))

;@axiom:no_refactor
(fn (legacyFn x) x)

;@axiom:owned(arena=frame)
(fn (ownedFn x) x)
```

| Key | Meaning |
|---|---|
| `effect(io)` | The function performs I/O. |
| `effect(pure)` | The function has no side effects. |
| `no_refactor` | Automated refactoring should leave this declaration alone. |
| `owned(arena=frame)` | Ownership metadata. It is accepted but not enforced, and its wording comes from before Axiom chose reference counting (`docs/memory-model.md` MM-LIFE-7). |

The compiler checks an `effect(io)` claim against what the body
performs: a `__syscallN`, or a call to something that performs one. It
checks an `effect(pure)` claim against the absence of any effect. A mismatch it
can decide is an error, `AX3010`:

```scheme refused
(import IO)

(:: shout (-> Int Int))
;@axiom:effect(pure)
(fn (shout x)
  {
    (println "hi")
    x
  })
```

```text
error[AX3010]: AXTAG mismatch on `shout`: `effect(pure)` claim contradicted: body performs Alloc, IO, Unsafe
```

A claim it can't check, because the body calls a value it couldn't
resolve, is a warning, `AX3037`. A function with no tag makes no
claim, so `AX3010` has nothing to check. The tags that make promises about effects, such as
`restrict(...)`, are covered under [Effects](#effects).

## CLI commands

Everything goes through one `axiom` command. These are the ones you
will use most:

```bash
axiom check source.ax                             # check syntax and types, generate no code
axiom run source.ax                               # compile and run straight away
axiom build --input source.ax --output program    # compile to a native executable
axiom test tests/                                 # run the tests in a file or directory
axiom fmt source.ax                               # format a file in place (--check only reports)
axiom repl                                        # start the REPL
```

`axiom help` lists every command, and `axiom help <COMMAND>` explains
one. The full set:

| Command | What it does |
|---|---|
| `build` | Compile a source file to an executable |
| `check` | Check syntax and types, emitting no code |
| `run` | Compile a source file and run it, forwarding any further arguments |
| `new` | Start a new project: `Main.ax` and `axiom.pkg` in a new directory |
| `fetch` | Check out the project's registry dependencies |
| `test` | Run every `test`-named function in a file or directory ([Testing](#testing)) |
| `emit-llvm` | Print the generated LLVM IR |
| `fmt` | Format a source file in place (`--check` to only report) |
| `explain` | Describe a diagnostic code (`--list` for all codes) |
| `symbols` | List every top-level symbol and its type |
| `repl` | Start the interactive read-eval-print loop ([The REPL](#the-repl)) |
| `lsp` | Run the language server on stdin and stdout (JSON-RPC) |
| `version` | Print the version |
| `help` | Print the help, or `help <COMMAND>` for one command |

<a id="checking-and-building"></a>
### Build and run

```bash
# Emit LLVM IR to stdout, or to a file
axiom emit-llvm source.ax
axiom emit-llvm source.ax -o output.ll

# Lower `parallel` to the platform's threads instead of forked processes
axiom build --threads --input source.ax --output program

# Carve the heap from a fixed 1 MiB region instead of asking the kernel
axiom build --heap-ceiling 1048576 --input source.ax --output program
```

`--threads` works with `build`, `run` and `test`, on darwin and linux.
See [parallel](#parallel--bindings-that-run-beside-the-caller) for what
it buys and what it costs.

`--heap-ceiling` bounds the heap: when the region is used up, an
allocation traps with status 70, which a recovery point can catch. A
program that spawns threads is refused under it with `AX4006`, since
every thread needs an arena of its own. `--target` and `--opt` are covered in
[Cross-compilation](#cross-compilation) and
[Optimisation](#optimisation).

<a id="using-the-ai-optimized-format"></a>
### Machine-readable output

Tools and agents should pass `--diagnostic-format=ai`. It prints
diagnostics in AXDL and symbols in AXSYM, one line each:

```bash
axiom --diagnostic-format=ai check source.ax
axiom --diagnostic-format=ai build --input source.ax --output program
axiom --diagnostic-format=ai symbols source.ax
```

`--diagnostic-format=json` prints diagnostics as JSON Lines. The default
is `human`. [diagnostics.md](diagnostics.md) is the full reference for
all three formats and the AXDL and AXSYM notations.

<a id="symbol-listing"></a>
### List a file's symbols

```bash
# Every top-level symbol and its type
axiom symbols source.ax

# Include the built-in operators too
axiom symbols source.ax --builtins

# Also print each function's resolved call edges as `#calls=`
axiom symbols source.ax --diagnostic-format=ai --calls
```

The default output is an aligned table for people.
`--diagnostic-format=ai` gives AXSYM instead, one line per symbol.
`symbols` has no JSON renderer: with `--diagnostic-format=json` it prints
AXSYM, with a note on stderr saying so.

A function with no signature can have type variables the checker made
up. `symbols` numbers them from `_t0` within each row, so
`(Int -> (_t0 -> _t0))` stays the same when you add other functions.

`--calls` shows the call graph behind each `#effects=` row: the edges
the effect inference resolved for that function. The two always agree:
no callee's effect escapes its caller, every inferred effect has
an edge that accounts for it, and every IO reaches a syscall or an
`extern`. See [agent-harness.md](agent-harness.md) §3.5.

Tested by `scripts/check-agent-calls.sh`.

<a id="diagnostic-lookup"></a>
### Look up a diagnostic code

```bash
axiom explain AX3001     # what AX3001 means and how to fix it
axiom explain --list     # every known diagnostic code
```

## Testing

A test is a top-level function whose name begins with `test` and which
takes no parameters. There is nothing to register and no attribute to
write: `axiom test` reads the file and finds them.

```scheme
(import Test)
(import Vec)

(:: testVecSum Int)
;@axiom:effect(io)
(fn (testVecSum)
  (let ((v vecNew))
    {
      (vecPush v 41)
      (vecPush v 1)
      (assertEq "length after two pushes" 2 (vecLen v))
      (assertEq "sum" 42 (vecSum v))
      0
    }))

(:: testAddition Int)
;@axiom:effect(io)
(fn (testAddition)
  {
    (assertEq "two plus two" 5 (+ 2 2))
    0
  })

(:: testStillRuns Int)
;@axiom:effect(io)
(fn (testStillRuns)
  {
    (assertTrue "one is less than two" (< 1 2))
    0
  })
```

```bash
$ axiom test math-tests.ax
ok   testVecSum
     two plus two: want 5, got 4
FAIL testAddition - a failed assertion, or an unhandled effect (status 71)
ok   testStillRuns

3 test(s), 1 failed
```

`axiom test` exits with status 1 when any test fails, and 0 when they
all pass. `tests/testrunner/pass-tests.ax` is a passing suite you can
run as it is.

<a id="discovery-and-the-two-anti-silence-rules"></a>
### Choose which tests run

Give `axiom test` a directory and it runs every `.ax` file directly
inside it, in name order. `--filter TEXT` runs only the tests whose name
contains `TEXT`:

```bash
axiom test --filter Vec math-tests.ax
```

A skipped test looks just like a passing one, so the runner never skips
in silence:

- A file that declares no test fails, rather than passing empty.
- A `--filter` that matches nothing fails for the same reason.
- A `test`-named function that takes parameters is rejected by name,
  rather than passed over (`tests/testrunner/arity-tests.ax`).

Tested by `scripts/check-test-runner.sh`, whose fixtures are in
`tests/testrunner/`.

<a id="setup-and-teardown"></a>
### Set up and tear down

A file can declare two hooks: `setup` and `teardown`, each an ordinary
top-level `fn` of exactly that name, taking no arguments. They run
around every test: setup, then the test, then teardown.

```scheme
(:: setup Int)
;@axiom:effect(io)
(fn (setup)
  (unwrapOr (appendFile "hook-log.txt" "s") 0))
```

The hooks run inside the test's own recovery point. A hook that traps
fails the test it opened or closed, and the run carries on.
`tests/testrunner/teardown-fails.ax` has a teardown that divides by
zero: the result is one `FAIL` at status 72, and exit status 1.

A `setup` or `teardown` that takes parameters is rejected by name,
because it could never run correctly
(`tests/testrunner/setup-arity-tests.ax`). Tested by
`tests/testrunner/setup-tests.ax`, which checks the full `setup, test,
teardown, setup, test` order.

<a id="assertions-take-a-label-first"></a>
### Assertions

`stdlib/Test.ax` provides the assertions: `assertEq`, `assertNe`,
`assertStrEq`, `assertTrue`, `assertFalse`, `assertFloatNear`, and
`testFail` for a branch that must never be reached.

Every one takes a label first. Axiom's macros can't turn an expression
into a string ([macro-system.md](macro-system.md)), so the runner has no
way to print the comparison that failed. The label says it instead, as
in `two plus two: want 5, got 4` above.

<a id="one-failure-ends-one-test"></a>
### One failure ends one test

A failed assertion ends the test it is in, and no other. It performs an
operation of the `Assert` effect. With no handler for it, that is the
unhandled-effect trap, and `axiom test` arms one recovery point per
test. So each of the three ways an Axiom program can stop without
returning ends exactly one test, and reports a status:

```text
ok   testTheFirstOnePasses
     deliberate: want 3, got 4
FAIL testAFailedAssertionEndsTheTest - a failed assertion, or an unhandled effect (status 71)
FAIL testADivisionByZeroIsContained - division by zero (status 72)
FAIL testAnUnhandledEffectIsContained - a failed assertion, or an unhandled effect (status 71)
ok   testTheLastOneStillRuns

5 test(s), 3 failed
```

The test declared after all three failures still ran
(`tests/testrunner/mixed-tests.ax`). The one thing a recovery point
can't contain is a memory-safety fault, and no language contains that.
[error-model.md](error-model.md) specifies this as `ERR-REC-6`.

<a id="marking-a-test-expected-to-fail"></a>
### Mark a test expected to fail

Put `;@axiom:expect` above a test's `fn`, or above its `::` signature.
A tagged test that fails is reported as `xfail` and doesn't count
against the run:

```scheme
;@axiom:expect
(:: testKnownBug Int)
;@axiom:effect(io)
(fn (testKnownBug)
  {
    (assertEq "not fixed yet" 1 2)
    0
  })
```

```text
     not fixed yet: want 1, got 2
xfail testKnownBug - a failed assertion, or an unhandled effect (status 71), as expected
```

The tag goes by the status the recovery point reports, not by the
`Assert` effect in particular. A tagged test that ends in a division by
zero is `xfail` too.

A tagged test that passes is reported as `FAIL`, with its own message,
and counts as a failure. So the tag can't silence a test: once its
assertion stops failing, the run tells you:

```text
FAIL testXFailButItPassesAnyway - expected to fail, but passed
```

Tested by `tests/testrunner/xfail-tests.ax`.

## The REPL

The REPL compiles each expression to native code rather than
interpreting it, so what you try interactively runs at full speed.

```bash
axiom repl
```

<a id="example-session"></a>
### A short session

Define a function, call it, and ask about it:

```text
$ axiom repl
Axiom 0.7.7 - REPL
Type :help for commands, :quit to exit

(:: add (-> Int Int Int))
OK: add defined
(fn (add x y) (+ x y))
OK: add defined
(add 3 4)
type : Int
result 7
:type (add 3 4)
(add 3 4) : Int
:defs
Definitions in scope:
  add
  add
```

The input lines are shown between the answers for readability. At a
terminal, each one follows an `axiom> ` prompt. When you pipe input in,
the REPL shows no prompt and echoes nothing, and all output goes to
stdout. It reads a line, answers it, and reads the next,
so a piped session and a typed one print the same answers.
`--no-banner` skips the two banner lines.

Definitions persist across inputs: a function you define stays in
scope until `:reset`. `:defs` lists each declaration, so `add` appears
once for its signature and once for its body. Input with unbalanced
brackets continues on the next line, and two blank lines abort it.

### REPL commands

Only a line that begins with `:`, or the single `?`, is a command.
Anything else is read as Axiom.

| Command | Aliases | What it does |
|---|---|---|
| `:help` | `:h`, `?` | Show all commands |
| `:quit` | `:q`, `:exit` | Exit the REPL |
| `:type <expr>` | `:t <expr>` | Show the type of an expression |
| `:load <file>` | `:l <file>` | Load a file into the REPL |
| `:reset` | `:r` | Clear all definitions |
| `:defs` | `:d` | Show all definitions in scope |
| `:llvm <expr>` | none | Show the generated LLVM IR |
| `:time <expr>` | none | Time how long an expression takes |

Ctrl+D ends the session.

### Editing at a terminal

When both stdin and stdout are a terminal, the REPL gives you a line
editor:

- Arrow keys, Ctrl-A/E/B/F/K/U/W/Y and Alt-b/f/d edit the line, and
  Ctrl+C cancels it.
- Up and Down (Ctrl-P and Ctrl-N) recall history, and Ctrl-R searches
  back through it for the text you've typed.
- Tab completes names, imports, keywords and commands. Escape closes
  the menu.
- Syntax highlighting follows as you type, and marks the bracket pair at
  the cursor.

History is kept across sessions in `$XDG_CONFIG_HOME/axiom/repl-history`,
or in `$HOME/.config/axiom/repl-history` when `XDG_CONFIG_HOME` isn't
an absolute path. If neither holds an absolute path, history stays in
memory.
Set `AXIOM_REPL_HISTORY` to an absolute path to use a different file,
or to `off` to keep history in memory only.

Not yet: a line is final once you press Enter. You can't go back and
edit an earlier line of a multi-line entry, and history recalls such an
entry flattened onto one line.

When stdin or stdout isn't a terminal, none of this applies: there is
no line editing and no history, and Ctrl+C kills the session. For editor integration, use the language
server (`axiom lsp`).

## Cross-compilation

`--target` picks the platform to generate code for. That sets the
syscall ABI and the standard library's platform modules:

```bash
axiom --target=linux-aarch64 emit-llvm main.ax -o main.ll
```

Supported targets: `darwin-aarch64`, `linux-aarch64`. Defaults to the host.

A target is supported when a CI job executes what the compiler emits there.
Both supported targets run the whole test battery on every change.

`darwin-x86_64`, `freebsd-aarch64`, `freebsd-x86_64`, `linux-x86_64`,
`windows-aarch64` and `windows-x86_64` are source-only. `--target` accepts each, and CI
assembles what the compiler emits for them, but runs no test battery
there, so none of them is supported. README's
[Targets](../README.md#targets) section says where CI builds the
compiler from the seed.

### Supported is not the same as shipped

Release archives with a prebuilt compiler exist for `linux-aarch64` and
`darwin-aarch64` only. On any other macOS, Linux or FreeBSD host,
`scripts/install.sh` says so and points you to `scripts/bootstrap-from-seed.sh`, which builds the
compiler from source.

### FreeBSD

On `freebsd-x86_64` and `freebsd-aarch64`, CI boots FreeBSD 14.4 in a
VM and builds the compiler there from the seed. It runs no test battery
there, so the
standard library, [parallel](#parallel--bindings-that-run-beside-the-caller)
included, is assembled for FreeBSD but not run. FreeBSD 12 is the oldest
release the syscall numbers support, and the target triple pins 14.

`freebsd-aarch64` shares the seed and the syscall table. Its VM is
emulated, so that build takes longer than the others.

### Windows

`windows-x86_64` and `windows-aarch64` are targets, not hosts. The
compiler doesn't run on Windows yet, and `scripts/install.sh` refuses a
Windows host. Build on Linux or macOS instead:

```bash
axiom build --target=windows-x86_64 --input p.ax --output p
axiom build --target=windows-aarch64 --input p.ax --output p
```

This links `p.exe` with `lld-link`
(`/subsystem:console /entry:mainCRTStartup`, and `/machine:arm64` for
`windows-aarch64`), which ships with LLVM's `lld`. `--link-search DIR`
becomes `/libpath:DIR`, and `--link-lib NAME` becomes `NAME.lib`.

The runtime calls kernel32, so a `kernel32.lib` for the target's machine
must sit in a search directory. Use the Windows SDK's
(`Lib\<ver>\um\x64` or `Lib\<ver>\um\arm64`), or generate one from a
`kernel32.def` that names the symbols in
`scripts/platform-allow.windows.txt`:

```bash
llvm-dlltool -m i386:x86-64 -d kernel32.def -l kernel32.lib   # windows-x86_64
llvm-dlltool -m arm64 -d kernel32.def -l kernel32.lib         # windows-aarch64
```

Windows is the one OS without a syscall ABI. On both architectures the
standard library reaches kernel32 by call through
`stdlib/Sys/Platform.windows.ax`, and your program starts at
`mainCRTStartup` with no C runtime. If a program
reaches a `__syscallN` anyway, it prints
`axiom: no syscall ABI on this target` and exits with status 74.

Limits:

- CI runs no Windows program. It assembles every standard-library test
  for both Windows targets, and `scripts/check-windows-hello.sh --emit`
  emits a hello world for each that a Windows runner would link and run.
- `--emit-staticlib` is refused for both targets.

*Under the hood:* `Sys.Platform.usesSyscallAbi` is 0 on Windows, so
`Sys.ax` calls the platform module's `platformWriteFd`, `platformReadFd`
and `platformExitWith` instead of `__syscallN`.

---

## Optimisation

`--opt` sets the optimisation level, from 0 to 3. The default is 1, or
the `opt` in your project's `axiom.pkg`:

```bash
axiom build --input main.ax --output main --opt 2
```

Use `--opt 2` for anything that iterates over a large input. It's the
lowest level at which LLVM vectorizes loops.

### How deep a loop can go

You can write a loop as `while` with `mut` and `set` (see
[Mutable bindings](#mutable-bindings) and
[while loops](#while-loops)), or as recursion. Here's how far each shape
goes, even at `--opt 0`:

| Shape | Depth |
|---|---|
| `while` | Unbounded. It's a real loop. |
| Self tail call | Unbounded at every `--opt` level. Axiom's code generator turns it into a loop itself. |
| Mutual tail call | Unbounded when the two functions' prototypes match and nothing is owed after the call. Otherwise bounded. |
| Non-tail recursion | Bounded by the machine stack. On an 8176 KiB stack, 174,000–175,000 frames at `--opt 0` and 260,000–262,000 at `--opt 1`. Past that, the process dies with SIGSEGV, status 139. |

A tail position is the last expression of a `{ }` block, any arm of an
`if` or `match`, or the body of a `let`. A `while` body, a `handle` body
and the operands of `&&` and `||` are not tail positions.

A mutual tail call that qualifies is marked `musttail`, LLVM's
guaranteed tail call. Two shapes stay plain calls and are bounded: a
callee with a different number of arguments, and a call that hands over
an owned temporary, such as `(od (+ i 1) (strConcat s "x"))`. LLVM may
flatten these at `--opt 1` and above, but nothing guarantees it.

So the shape to avoid at scale is recursion whose work happens *after*
the recursive call. Carry the running result in an argument instead:

```scheme
(import IO)

; Bounded: the `+` runs after the call returns, so every level keeps a frame.
(:: sumTo (-> Int Int))
(fn (sumTo n)
  (if (== n 0) 0 (+ n (sumTo (- n 1)))))

; Unbounded: the running total rides along, so the call is a tail call.
(:: sumAcc (-> Int Int Int))
(fn (sumAcc n acc)
  (if (== n 0) acc (sumAcc (- n 1) (+ acc n))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (sumTo 1000))
    (println (sumAcc 10000000 0))
    0
  })
```

```text
500500
50000005000000
```

The rules are `MM-EXEC-6b`, `MM-EXEC-6c` and `MM-EXEC-6d` in
[memory-model.md](memory-model.md).

Tested by `tests/stdlib/467-mutual-tail.ax` and `scripts/check-tail-calls.sh`.

### Link-time optimisation

There's no flag for link-time optimisation because every build already
gets it. Each program is emitted as one LLVM module: your code, every
standard library module it imports, and the runtime allocator. `opt`
runs over that whole module, so inlining and dead-code elimination work
across all of it. The compiler also drops every function that nothing
reachable from `main` calls.

A linker flag such as `-Wl,-dead_strip` (or `--gc-sections` on ELF)
would add almost nothing: on a hello world it finds only ten unused
runtime helpers.

Not yet: the compiler doesn't inline calls across an
[`extern`](#calling-rust) boundary into Rust. You can do it by hand:

1. Build the crate with `rustc --emit=llvm-bc`. A `staticlib` built with
   `-C linker-plugin-lto` carries no bitcode, so ask for it separately.
2. Join it to the Axiom module with `llvm-link`.
3. Strip rustc's `"target-cpu"` and `"target-features"` attributes.
   LLVM won't inline across them.
4. Run `opt -O2` over the result, and link it against the crate's
   archive for the rest.

The C-ABI contract in [ffi.md](ffi.md) is the same either way.

### Vectorization

Axiom emits LLVM IR, so SIMD is automatic wherever LLVM's loop
vectorizer accepts your loop. That happens only at `--opt 2` and above:
the default `--opt 1` runs neither the loop nor the SLP vectorizer.

| Loop | At `--opt 2` | LLVM's reason |
|---|---|---|
| `(for x in xs (set acc (+ acc x)))` over a `(Vec Int)` | Vectorized, width 2, interleave 4. 3.1x faster than `--opt 1`. | Nothing is stored in the loop, so the vector's header reads move out of it and the range check folds. |
| `(for i in 0..n (if (== (strByte s i) 97) ...))` over a `String` | Vectorized, width 16. 1.9x faster. | The same shape, with byte elements. |
| `(for i in 0..n (vecSet v i (+ (vecGet v i) 1)))`, in place | Not vectorized. | `control flow cannot be substituted for a select`, `call instruction cannot be vectorized`, and an early exit: the range check's trap |
| A `while` with a data-dependent trip count, such as `web/bench/collatz.ax` | Not vectorized, correctly. | `Cannot vectorize uncountable loop` |

Not yet: loops that write into a vector don't vectorize. Every memory
access is a load or store through an integer address, so LLVM assumes a
store into one vector's data might change another vector's length. It
re-reads the length, data pointer and ownership flag on every
iteration. The range check, which traps with status 77 on a bad index,
stays inside the loop as an exit.

A multiply can block vectorization even without those checks. An `i64`
multiply has no vector instruction on baseline NEON or SSE2. A map that
multiplies each element by 3 over raw words isn't vectorized, because
LLVM's cost model finds no benefit. The same loop with `+ 1` vectorizes
at width 2.

To see what LLVM decides about your own loop:

```bash
axiom emit-llvm main.ax -o main.ll
opt -O2 -S main.ll -o main.O2.ll \
  --pass-remarks-output=main.yaml --pass-remarks-filter=loop-vectorize
grep -B2 -A2 'Function: *yourFunction' main.yaml
```

A `Vectorized` remark names the width and interleave count. A
`MissedDetails` remark follows the analysis remarks that say why. In
the compiler's own code, most loops that don't vectorize give one of two
reasons: `CantVectorizeLibcall`, a call in the loop body, or
`UnsupportedUncountableLoop`, a `while` whose bound isn't a counter.

*Under the hood:* the six runtime trap functions, such as
`__axiom_index_out_of_range`, are emitted `noreturn cold`. Inlining
`vecGet` therefore leaves the trap as a call instead of copying it into
every caller. The block after the call is `unreachable`, so the trap
never leads back into the loop.

Tested by `scripts/check-simd.sh`.

---

<a id="compiler-pipeline"></a>
## How the compiler works

The compiler is written in Axiom, in `self_host/`. Your source passes
through these stages:

```text
Source (.ax) → Lexer → Parser → Imports → Macro Expansion → Type Checker → LLVM IR → opt → llc → cc → Executable
```

- **Imports** merges every module into one declaration list. Each entry
  remembers its file, so a bare name resolves across files and a
  diagnostic still names the right one.
- **Macro expansion** runs to a fixpoint before any body is checked.
- **The type checker** makes two passes: it collects declarations, then
  checks bodies.
- **LLVM IR** is written as text by `codegen.ax`, straight from the
  checked syntax tree. There's no separate intermediate stage.

| Module | What it does |
|---|---|
| `core.ax` | Tokens and spans |
| `lexer.ax` | Tokenizer |
| `parser.ax` | S-expression parser and syntax tree |
| `expand.ax` | Macro expansion to a fixpoint, the `syntax/*` query vocabulary, hygiene, expansion diagnostics |
| `typecheck.ax` | Name resolution, type checking, effects, AXTAG validation |
| `namespace.ax` | How a bare name reaches a definition, and which names may leave a module |
| `codegen.ax` | Import resolution, name mangling, LLVM emission |
| `diag.ax` | Diagnostics, AXDL and JSON rendering, source maps |
| `render.ax` | The human diagnostic renderer |
| `style.ax` | The colour palette the human renderer uses |
| `driver.ax` | `build`: running `opt`, `llc` and `cc` and naming the stage that failed; `--crate` with `cargo` and `axiom-bindgen`; grounding `extern` symbols and linking crates and archives for the FFI |
| `rustbind.ax` | The Rust binding `--emit-rust-binding` writes for an Axiom archive ([ffi.md](ffi.md) §10) |
| `main.ax` | The CLI and its subcommands. `format.ax`, `repl.ax`, `symbols.ax`, `explain.ax` and `lsp.ax` are the tools. |
| `build.ax` | The build id, which `scripts/build-stamped.sh` rewrites so a shipped binary names the tree it came from |
| `Host.<target>.ax` | The host triple and syscall ABI, chosen when the compiler itself is compiled |

To work on the compiler, start with [CONTRIBUTING.md](../CONTRIBUTING.md).

---

## Removed features

These words are reserved. Each one reports `AX2004` and tells you what
to write instead. The full table is under [Removed
keywords](#removed-keywords); what follows is the longer story for the
removals that need one.

For example:

```scheme refused
(trait (Eq a) where
  (eq :: (-> a a Bool)))

(:: main Int)
(fn (main) 0)
; error[AX2004]: `trait` is no longer part of Axiom
```

```scheme refused
(impl (Eq Int) where
  ((eq (lambda (x y) (== x y)))))

(:: main Int)
(fn (main) 0)
; error[AX2004]: `impl` is no longer part of Axiom
```

With a capability record, a call is an ordinary application,
`((c.eq) x y)`. Printing needs no record at all, because the compiler
renders every value from its static type
([Printing and formatting](#printing-and-formatting)). Supertraits,
default method bodies and the effect list on a `trait` or `impl` header have no
replacement. A record's members are ordinary functions, so they declare
their own effects. `where` is an ordinary identifier again.

Reserving these words gets you a useful message. Without it,
`(begin 1 2 42)` would report `AX3001 undefined variable begin`, and
`(impl (Eq Int) where ...)` would say that no macro named `impl` exists.

The struct layout modifiers `packed`, `repr(C)` and `align(N)` are gone
too. The parser rejects all three.

`region` is not removed. It's a scope your program brackets: see
[Regions](#regions). A `(region ...)` at the top level isn't a
declaration, so it reports `AX3027` like any other expression head.

---

## Tips and patterns

### Write a function that does I/O

A function that prints declares `effect(io)`:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println "Hello from Axiom!")
    0
  })
```

```text
Hello from Axiom!
```

### Name intermediate values with `let`

Each binding can use the ones before it:

```scheme
(fn (compute n)
  (let ((x (+ n 1))
        (y (* x 2)))
    (+ x y)))
```

### Handle a missing result with `Option`

```scheme
(:: safeDiv (-> Int Int (Option Int)))
(fn (safeDiv a b)
  (match b
    ((0) (None))
    (_ (Some (/ a b)))))
```

### Build and walk a list

```scheme
(data List (a)
  (Nil)
  (Cons a (List a)))

(:: sum (-> (List Int) Int))
(fn (sum lst)
  (match lst
    ((Nil) 0)
    ((Cons h t) (+ h (sum t)))))

(:: main Int)
(fn (main)
  (sum (Cons 1 (Cons 2 (Cons 3 (Nil))))))   ; exits with status 6
```

### Use the standard library

```scheme
(import IO)
(import Str)
(import Fmt)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((total (+ 1 2)))
    {
      (println 42)
      (println "sum={total}")
      0
    }))
```

```text
42
sum=3
```

---

## Further reading

- [The memory model](memory-model.md): the specification for
  representation, allocation, mutation and lifetimes, including
  reference counting.
- [The macro system](macro-system.md): the specification for expansion,
  hygiene and budgets, with what expansion guarantees and the probes
  behind each claim.
- [The error model](error-model.md): `Result`, the `Error` record, and
  `stdlib/Err.ax`.
- [The Rust FFI](ffi.md): `extern` blocks, `--emit-staticlib`, and what
  crosses the boundary.
- [Diagnostics and agent notations](diagnostics.md): AXDL, AXSYM, NID
  and AXTAG.
- [Contributing](../CONTRIBUTING.md): the checks and the conventions.
- [README](../README.md): the project overview and installation.
