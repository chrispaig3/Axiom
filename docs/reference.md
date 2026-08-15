# Axiom Language Reference

A friendly, comprehensive guide to the Axiom programming language — a functional systems language that compiles to native code via LLVM, with no VM and no runtime. Memory comes from an `mmap`-backed bump allocator.

---

## Table of Contents

1. [Hello, Axiom!](#hello-axiom)
2. [Syntax Basics](#syntax-basics)
3. [Comments](#comments)
4. [Literals](#literals)
5. [Identifiers and Keywords](#identifiers-and-keywords)
6. [Types](#types)
7. [Functions](#functions)
8. [Operators](#operators)
9. [Let Bindings](#let-bindings)
10. [Conditionals](#conditionals)
11. [Pattern Matching](#pattern-matching)
12. [Algebraic Data Types](#algebraic-data-types)
13. [Structs](#structs)
14. [Type Aliases](#type-aliases)
15. [Traits](#traits)
16. [Effects](#effects)
17. [Handle Expressions](#handle-expressions)
18. [Modules and Imports](#modules-and-imports)
18b. [Macros](#macros)
19. [Memory Primitives](#memory-primitives)
20. [Standard Library](#standard-library)
21. [AXTAG Metadata](#axtag-metadata)
22. [Linear Types and Consume](#linear-types-and-consume)
23. [Removed Features](#removed-features)
25. [The REPL](#the-repl)
26. [CLI Commands](#cli-commands)
27. [Compiler Pipeline](#compiler-pipeline)

---

## Hello, Axiom!

Every Axiom program needs a `main` function that returns `Int`. Here is the smallest possible program:

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

Run it:

```bash
axiom run hello.ax
```

That's it. No headers, no build system, no runtime. The `IO` module is part of Axiom's own standard library — compiled programs call no C function at all.

---

## Syntax Basics

Axiom uses **S-expressions** — everything is wrapped in parentheses. This takes a moment to get used to, but the payoff is a language with almost no syntax rules to memorize.

### The General Form

```scheme
(keyword arg1 arg2 ...)
```

Every expression is a list. The first element is always a keyword or operator, and the rest are arguments. There are no precedence rules to memorize — parentheses make the structure explicit.

### Whitespace

Whitespace (spaces, tabs, newlines) separates tokens. It is not significant beyond that — you can format your code however you like.

---

## Comments

```scheme
; This is a line comment

#| This is a block comment.
   They can nest: #| inner |# |#
```

Line comments start with `;`. Block comments use `#| ... |#` and can nest arbitrarily.

A block comment is trivia: it may sit between any two tokens, and its
contents are not source. Nesting is counted, so the first `|#` closes
only the innermost open comment. A block comment that is never closed
runs to the end of the file and is not an error. A `#` that is not
followed by `|` is `AX1001`, so `#` is not a comment character on its
own.

`;@axiom:` metadata is recognised only in a line comment. Inside a
block comment it is comment text like anything else.

---

## Literals

```scheme
42              ; Integer (64-bit)
3.14            ; Float (64-bit)
.5              ; Float (leading dot allowed)
1_000_000       ; Underscore separators for readability
true            ; Boolean
false           ; Boolean
"hello world"   ; String
'x'             ; Character
```

### String Escape Sequences

| Sequence | Meaning |
|---|---|
| `\n` | Newline |
| `\t` | Tab |
| `\r` | Carriage return |
| `\\` | Backslash |
| `\"` | Double quote |
| `\'` | Single quote |
| `\0` | Null byte |

### String Literals Are `Str` Values

A string literal is a first-class string. It needs no conversion and can
go anywhere a `Str` from the standard library can:

```scheme
(println "Hello, Axiom!")
(strLen "Hello")                    ; 5
(strConcat "sum=" (fmtInt 42))
(strSlice "abcdef" 2 3)             ; "cde"
```

The compiler emits two globals per literal — the bytes, and a header
whose last two words hold the length and the byte address, exactly the
layout `Str.strWrap` builds. The first two words are the MM-LIFE-2b
count/shape header every heap block carries, with the count all-ones:
a static is never reclaimed, and the runtime's retain/release read the
sentinel and leave it untouched. The literal's value points at the
{length, bytes, owner} triple, so every consumer loads at +0/+8 as
before; the owner word is zero, because a literal's bytes are
loader-resident and no block's death may free them (`MM-VAL-7`):

```llvm
@str_0    = private unnamed_addr constant [14 x i8] c"Hello, Axiom!\00"
@strhdr_0 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 13, ptr @str_0, i64 0 }
```

The literal evaluates to the header's address. Its **length is computed
at compile time**, so `(strLen "Hello")` is a load rather than a scan,
and a literal costs no allocation at run time.

The bytes stay NUL-terminated as well as length-counted, so a literal
can still be handed to a syscall or a C function that expects a C
string. `__addr` is how you reach them:

```scheme
"hello"                             ; the Str header
(__addr "hello")                    ; the bytes, as an address
```

`Str.strFromLit` remains the bridge for NUL-terminated bytes that arrive
without a length — from a syscall buffer, say. Applied to a literal it
is redundant: `(strFromLit (__addr "hi"))` scans for a length the
compiler already knew, and `"hi"` is the same value.

> **A `String` is a machine word, and the checker knows which words
> are strings.** Every Axiom value is one word, and a `String` is the
> address of a `Str` header — but since 2026-08-15 `String` and `Int`
> are DISTINCT types: the fiat that unified them is deleted, and
> `(+ 1 "hi")` is the `AX3004` it always deserved. A literal still
> goes into a `Vec` or a `Map` value slot, because the containers
> carry type variables rather than spending the fiat; the explicit
> crossing where a handle is deliberately read as a word is spelled
> `(cast Int s)`, and it appears exactly once in `Str` itself.

---

## Identifiers and Keywords

### Identifiers

Names are lowercase by convention:

```scheme
myVariable
compute_sum
->
```

**The character set is wider than that suggests, and deliberately so.**
An identifier's first byte is a letter, `_`, or one of

```
+ - * / % < > = ! & | ^
```

and every byte after the first is one of those, a letter, a digit, or
`'`. That is what makes `+` a name rather than punctuation — `(+ a b)`
is an ordinary application of a function called `+` — and it means
`set!`, `foo'`, `empty-list` and `a+b` are all ordinary names you may
declare:

```scheme
(:: half' (-> Int Int))
(fn (half' n') (/ n' 2))
```

Two exclusions are on purpose. `?` is **not** an identifier character,
so `empty?` is a lexer error (`AX1001`) rather than a name; admitting it
is a language change to be made deliberately, with the tree-sitter
grammar and the formatter moved alongside. And `.` is not one either,
so `tmp.1` is refused — `.` is field access, and `::` is qualified
module access (`Mod::name`), neither of which can be part of a name.

Names outside LLVM's own identifier set are quoted on the way into the
generated code, so every name the frontend accepts is one the backend
can emit. Twelve of these characters used to pass `check` and then kill
`opt`; `scripts/check-symbol-names.sh` now sweeps all 94 printable bytes
in three positions and requires each to be either refused with a span or
compiled and run. See
[self-hosting.md §15.2](self-hosting.md).

### Keywords

These words are reserved and cannot be used as identifiers:

| Keyword | Purpose |
|---|---|
| `define` | Define a function (classic style) |
| `fn` | Define a function (modern style, alias for `define`) |
| `lambda` | Anonymous function |
| `let` | Local variable binding |
| `mut` | Marks a `let` binding assignable |
| `set` | Assign to a `mut` binding |
| `while` | Loop while a condition holds |
| `if` | Conditional expression |
| `cond` | Multi-branch conditional |
| `match` | Pattern matching |
| `data` | Algebraic data type |
| `struct` | Product type with named fields |
| `type` | Type alias |
| `newtype` | Newtype wrapper |
| `trait` | Interface / type class |
| `impl` | Trait implementation |
| `import` | Import a module |
| `pub` | Public visibility |
| `deriving` | **Refused** (`AX2004`, 2026-08-14) — it parsed and derived nothing; `derive` is explicit declaration macros ([macro-system.md](macro-system.md) MAC-CAP-9) |
| `where` | Trait method bodies |
| `effect` | Declare an effect type |
| `handle` | Handle effects |
| `linear` | Linear type marker |
| `consume` | Consume a linear value |
| `alloc` | Allocate memory |
| `sizeof` | Size of a type |
| `alignof` | Alignment of a type |
| `cast` | Type cast |

### Removed Keywords

These words are reserved but no longer have a grammar rule. Using them reports a helpful error with advice on what to write instead:

| Keyword | Replacement |
|---|---|
| `union` | Use `data` for a tagged sum or `struct` for a product |
| `region` | Delete the `region` wrapper; lifetimes are inferred |
| `foreign` | Use the standard library; generated code links no C |

---

## Types

### Primitive Types

| Type | Description |
|---|---|
| `Int` | 64-bit signed integer |
| `Float` | 64-bit floating point |
| `Bool` | Boolean (`true` / `false`) |
| `Char` | A Unicode code point: `'A'` is 65, `'é'` is 233, `'世'` is 19990, `'😀'` is 128512. (This table used to say "8-bit", which was wrong - a char literal has always carried the whole code point.) |
| `String` | String (pointer) |
| `()` | Unit (no value). A **type** only — `(:: main ())` and `(:: f (-> () Int))` are accepted, and `symbols` renders the empty tuple as `()`. There is no unit *value*: `()` in expression position is `AX2001 expected expression`, as it is in `[]` and `(set)`, and nothing in the language produces or consumes one |
| `Unit` | A distinct type constructor spelled `Unit`, **not** a synonym for `()`. This row used to read ``| `Unit` / `()` |``, and the equivalence was never true: `symbols` renders `(:: a (-> () Int))` as `(() -> Int)` and `(:: b (-> Unit Int))` as `(Unit -> Int)`. `Unit` was also missing from the parser's type-keyword set until 2026-08-10, so it was a bare unresolvable constructor that nothing asked about until signature types began to be resolved — see [self-hosting.md §30.2](self-hosting.md) |
| `Void` | Void |
| `Any` | Generic pointer |

### Sized Integers and Floats — Removed

`I8`–`I128`, `U8`–`U128`, `Isize`/`Usize`, `Double` and `F32`/`F64`
are refused (`AX3002`) since 2026-08-14. They were accepted names with
no representational effect — every one lowered to a full-width `i64`,
incompatible with `Int` so no operator accepted one — and the float
spellings emitted **integer** arithmetic on double bit patterns,
silently, because the emitter keys float arithmetic on the name
`Float` alone (`docs/memory-model.md` MM-VAL-3c, MM-VAL-4b). `Int` is
the one integer type and `Float` the one floating type; the real
conversions are `__intToFloat`/`__floatToInt`.

### Compound Types

```scheme
(-> Int Int)           ; Function: Int -> Int
(-> Int Int Int)       ; Curried: Int -> Int -> Int
(* Int)                ; Pointer to Int
[Int]                  ; List of Int
(Int String Bool)      ; 3-tuple
```

### Type Variables and Polymorphism

```scheme
(data Maybe (a)
  (Nothing)
  (Just a))
```

The `(a)` after the type name introduces a type parameter. Types can be polymorphic — the same `Maybe` can hold any type.

### Type Signatures

Every function has an optional type signature declared with `::`:

```scheme
(:: add (-> Int Int Int))
```

This says `add` is a function that takes two `Int`s and returns an `Int`. The `(-> A B C)` syntax means a function that takes `A`, then `B`, and returns `C`. It is curried — you can partially apply it.

### Effect Types

Functions can carry effect annotations that the compiler checks:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main) (println "hello"))
```

The compiler validates that the body actually performs the declared effects.

---

## Functions

Functions are the heart of Axiom. Every function has an optional type signature and a definition.

### Modern `fn` Style

```scheme
(:: add (-> Int Int Int))
(fn (add x y)
  (+ x y))
```

### Classic `define` Style

```scheme
(:: add (-> Int Int Int))
(define (add x y)
  (+ x y))
```

Both styles are identical. `fn` is the modern alias for `define`.

### Multi-Parameter Functions

```scheme
(:: add3 (-> Int Int Int Int))
(fn (add3 x y z)
  (+ x (+ y z)))
```

### Functions with No Parameters

```scheme
(:: answer Int)
(fn answer 42)
```

### Multi-Statement Bodies

Use braces for sequencing:

```scheme
(fn (verbose-add x y)
  { (println "adding") (+ x y) })
```

The value of a brace block is the value of its last expression. Single expressions in braces are unwrapped automatically — `{ 42 }` is just `42`.

Function bodies, `let` bodies, `if` branches, and `lambda` bodies also support **implicit sequencing** without braces:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (println "Starting...")
  (println "Working...")
  0)
```

### Lambda (Anonymous Functions)

```scheme
(lambda (x) (+ x 1))

(lambda (x y) (+ x y))

(lambda (_) 42)    ; Ignoring a parameter with wildcard
```

### Partial Application

Because functions are curried, you can partially apply them:

```scheme
(:: add (-> Int Int Int))
(fn (add x y) (+ x y))

(:: addFive (-> Int Int))
(define addFive (add 5))    ; addFive is now a function that adds 5
```

---

## Operators

All operators are **prefix** — they go before their arguments, just like any other function.

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
(>= 1 2)            ; true

(&& true false)     ; false
(|| true false)     ; true

(- 5)               ; -5 (negation, unary)
```

```scheme
(& 12 10)           ; 8   bitwise and
(| 12 10)           ; 14  bitwise or
(^ 12 10)           ; 6   bitwise xor
(<< 1 10)           ; 1024
(>> 1024 3)         ; 128
```

`>>` is arithmetic, so the sign bit is preserved: `(>> -1024 3)` is
`-128`.

`&&` and `||` short-circuit: the right-hand operand is evaluated only
when the left one does not already decide the answer. This is what makes
a guard mean what it looks like — `(&& (< i n) (== (strByte s i) c))`
never reads `s` at `i` unless `i` is in range.

`Int` is 64-bit and two's complement. Negation of the most negative
value yields itself rather than a positive number, which is why
`Fmt.intIsMostNegative` exists: there is no literal for that value, and
`(- 0 9223372036854775807)` is one greater than it.

---

## Let Bindings

Use `let` to introduce local variables:

```scheme
(fn (compute n)
  (let ((x (+ n 1))
        (y (* x 2)))
    (+ x y)))
```

Bindings are evaluated **in order** — later bindings can reference earlier ones.

### Mutable Bindings and `while`

A binding is immutable unless it is marked `mut`. A `mut` binding can be
assigned with `set`, and `while` loops while its condition holds:

```scheme
(fn (sumTo n)
  (let ((mut i 0)
        (mut acc 0))
    {
      (while (< i n)
        (set acc (+ acc i))
        (set i (+ i 1)))
      acc
    }))
```

The `while` body takes any number of expressions, so a loop that updates
two variables needs no extra brackets. The whole form evaluates to `0` —
a loop that ran zero times has no last iteration to take a value from.

`set` also writes a field, through a dotted path:

```scheme
(struct Counter (n : Int) (step : Int))

(fn (bump c)
  (set c.n (+ c.n c.step)))
```

The path is resolved by name, so the offset — and the tag word a `data`
constructor carries ahead of its fields — is the compiler's problem
rather than yours. `(set a.b.c v)` writes `c` on the value at `a.b`.

What `set` will not take is an arbitrary place expression: the target is
a name or a field path, never a computed one, so `(set (f x) 1)` is a
syntax error that says so instead of type-checking its way to a report
about a non-assignable expression. A field write needs no `mut` — `mut`
governs rebinding the local, not mutating what it points at. Raw memory
is still reachable through `memSetWord`, which is what `Vec` and `Map`
use to write slots that are not declared fields.

Assigning to a binding that is not `mut` is a compile error:

```scheme
(let ((x 0))
  (set x 1))     ; AX3012: cannot assign to immutable binding `x`
```

The report points at the *declaration* as well as the assignment, with a
machine-applicable fix rewriting `x` to `mut x` — the fix belongs where
the binding is introduced, not where it is used.

> **This is a real loop.** `while` lowers to a branch back to a
> condition block, so a million iterations run in constant stack at
> `-O0`. Iteration by recursion still works and tail calls are
> guaranteed, but *non*-tail recursion remains stack-bounded — measured
> at 60,000–80,000 frames on an 8 MiB stack — so a fold written as
> `(+ (f i) (loop (+ i 1)))` is the shape to avoid at scale.

### Sequential Let Bindings

You can also write `let` bindings sequentially:

```scheme
(let ((x 1))
  (let ((y (+ x 1)))
    (+ x y)))
```

---

## Conditionals

### `if` Expressions

```scheme
(:: abs (-> Int Int))
(fn (abs n)
  (if (< n 0)
      (- 0 n)
      n))
```

`if` is an expression — it returns a value. Both branches are required.

### `cond` — Multi-Branch Conditional

```scheme
(:: classify (-> Int String))
(fn (classify n)
  (cond ((< n 0) "negative")
        ((== n 0) "zero")
        ((> n 0) "positive")))
```

Each branch is a `(test body)` pair. The first matching branch wins. An optional `else` clause can be added as the last argument.

---

## Pattern Matching

`match` is one of Axiom's most powerful features. It lets you destructure values by their shape.

### Basic Matching

```scheme
(:: fromMaybe (-> Int (Maybe Int) Int))
(fn (fromMaybe default val)
  (match val
    ((Nothing) default)
    ((Just x) x)))
```

### Matching Constructors with Fields

```scheme
(match val
  ((Cons h t) h)
  ((Nil) 0))
```

### Matching Literals

```scheme
(match x
  (42 "the answer")
  (_ "anything else"))
```

### Nested Patterns

```scheme
(match lst
  ((Cons h (Cons h2 t)) ...)
  ((Nil) ...))
```

### Wildcard Pattern

Use `_` to match anything and ignore the value:

```scheme
(match val
  ((Just x) x)
  (_ 0))
```

### Exhaustiveness Checking

Axiom checks at compile time that every constructor of the matched type is covered. Missing constructors are a compile error (`AX3005`).

```scheme
;; Correct: all constructors covered
(match val
  ((Nothing) default)
  ((Just x) x))

;; Incorrect: Missing Nothing arm — compile error AX3005
(match val
  ((Just x) x))
```

### The Built-in `Option` Type

Axiom provides a built-in `Option` type with `Some` and `None` constructors, always available without a `data` declaration:

```scheme
(:: safeDiv (-> Int Int Int))
(fn (safeDiv a b)
  (match b
    ((0) (None))
    (_ (Some (/ a b)))))

(:: main Int)
(fn main
  (match (safeDiv 10 2)
    ((Some x) x)
    ((None) 0)))
```

---

## Algebraic Data Types

Define custom types with constructors:

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

The `(a)` after the type name is a type parameter — like generics in other languages.

### Struct Variants — Named Fields Per Constructor

A constructor's fields can be named instead of positional:

```scheme
(data Shape
  (Circle { r : Int })
  (Rect { w : Int, h : Int })
  (Point))
```

Values are built positionally, in declaration order:

```scheme
(Circle 7)
(Rect 3 4)
```

and read back by name, either through field access or in a pattern:

```scheme
(fn (describe s)
  {
    s.r                                    ; field access by name

    (match s
      ((Circle { r = r })       r)         ; named
      ((Rect   { h = h, w = w }) (* w h))  ; order does not matter
      ((Point)                  0))
  })
```

Named patterns buy three things a positional pattern cannot:

| | |
|---|---|
| **Order independence** | `{ h = h, w = w }` binds what its names say. Reordering two same-typed fields in a declaration cannot silently swap them at every match site. |
| **Partiality** | A field the arm does not name is simply not bound — no `_` placeholder to keep in step with the constructor's arity. |
| **Punning** | `{ w, h }` means `{ w = w, h = h }`. |

So the common case is short:

```scheme
(match s
  ((Circle { r })    r)
  ((Rect { w, h })   (* w h))
  ((Point)           0))
```

Punning and explicit binding mix freely, and named patterns nest:

```scheme
(match x
  ((Wrap { inner = (Rect { w, h }), tag = t }) (+ (* w h) t))
  ((Wrap { tag = t })                          t))
```

Positional patterns keep working on the same type; named fields add a
spelling rather than replacing one.

### How ADTs Actually Run

Every value of a `data` type — nullary constructors like `Nothing` included — is a heap-allocated, tagged block. Word 0 is an integer tag identifying which constructor built it, and words 1.. are its fields, one 8-byte word each. This uniform representation is what lets `match` compare any constructor pattern against any value of that type the same way.

### Deriving Traits

`derive` is **explicit declaration macros**, not a clause: write
`(deriveEq T)` where you want the instance, and the macro generates a
real `impl` — checked, compiled, and dispatched like a written one
(see [Macros](#macros) for a complete `deriveEq` and
[macro-system.md](macro-system.md) §10.2 for the fieldful form whose
derived instances compose).

The `deriving` **clause is refused** (`AX2004`, since 2026-08-14). It
had parsed and been silently discarded from the day it was written —
its names never reached the AST, and no instance was ever derived —
and a clause that does nothing is worse than one that does not parse
(MAC-CAP-9's settled decision):

```scheme fragment
(data Colour () (Red) (Green) deriving (Eq Show))
; error[AX2004]: `deriving` parsed and derived nothing, and is now refused
```

---

## Structs

Products of named fields:

```scheme
(struct Point
  (x : Int)
  (y : Int))
```

There are no layout modifiers. `packed`, `repr(C)` and `align(N)` were
documented here and accepted by nothing: the parser has always answered
`AX2001` for all three. C layout has no meaning in a language that links
no C.

Struct fields can be mutable. `mut` goes on the field, inside its
parentheses — not on the struct:

```scheme
(struct Counter
  (mut count : Int))
```

---

## Type Aliases

```scheme
(type StringList () = [String])
```

A type alias gives a name to an existing type. It does not create a new type — `StringList` and `[String]` are interchangeable: the alias is expanded in every signature position before checking, and its float flags are rewritten with it, so the checker and the emitter cannot disagree about a `(type Real = Float)`. A PARAMETERISED alias — `(type Pair a = ...)` — needs substitution and is not expanded; it behaves nominally. `tests/selfhost/973-type-alias.ax`

---

## Traits

Traits define interfaces with typed methods — similar to type classes in Haskell or protocols in Swift.

### Declaring a Trait

```scheme
; A trait with one method
(trait (Eq a)
  where
    (eq :: (-> a a Bool)))

; A trait with multiple methods and supertraits. Every method
; signature goes in ONE parenthesised group - a group per method is
; `AX2003`, and used to be discarded in silence.
(trait (Ord a) (Eq a) where
  (cmp :: (-> a a Int)
   lt :: (-> a a Bool)
   gt :: (-> a a Bool)))
```

### Implementing a Trait

```scheme
(impl (Eq Int) where
  ((eq (lambda (x y) (== x y)))))

; Again one group, holding every method.
(impl (Ord Int) where
  ((cmp (lambda (x y) (if (== x y) 0 (if (< x y) (- 0 1) 1))))
   (lt (lambda (x y) (< x y)))
   (gt (lambda (x y) (> x y)))))
```

### Traits Support

- **Type parameters** — `(trait (Eq a) ...)` binds `a` for all method signatures
- **Supertraits** — `(trait (Ord a) (Eq a) ...)` requires `Eq` to be implemented too
- **Default methods** — `(where (method :: type = default_body))`
- **Effects** — traits and methods can carry effect annotations

---

## Effects

Axiom infers each function's side effects transitively - a fixpoint
over every function body, so a syscall three calls down still counts -
and validates any `;@axiom:effect(...)`/`;@axiom:pure` claims against
what it inferred (`AX3010`, a warning). Effects do not appear in
function types, and untagged functions are not policed: the tags are
opt-in claims, checked when made. `axiom symbols` reports the inferred
set as `#effects=...` beside any declared tags.

### Effect Polymorphism

A higher-order function's summary has two halves: the concrete effects
its own body performs, and the *effect-transparent parameters* - the
parameters it calls (directly, through a `let` alias, or by passing
them onward to another function's effect-transparent position). `(fn
(apply f x) (f x))` performs nothing concretely and everything its
first argument performs; `axiom symbols` reports that as
`#effect-params=f` beside `#effects=...`, and every call site
instantiates the mark with the argument actually passed.

Claims are validated against the concrete half. `;@axiom:pure` on
`apply` stands - "pure modulo its function parameters" is what purity
means on a higher-order function - and a declared effect the body does
not perform concretely is accepted when a callback could supply it.
The exception is a claimed effect that no declaration introduces at
all: nothing could ever supply it, so it warns regardless.

Attribution is otherwise unchanged: a *reference* to a named function
answers for that function's effects at the reference site, and a
lambda literal answers for its body where the literal appears, which
is what keeps function values that escape into structures sound. The
remaining honest gaps: a function value returned from a call or loaded
from a structure contributes nothing at its *invocation* site (its
creation site was attributed); and passing an effect-polymorphic
function itself as a callback does not instantiate the callee's marks
(higher-rank flows).

### Built-in Effects

| Effect | Meaning |
|---|---|
| `IO` | Reaches the outside world through a `__syscallN` |
| `Pure` | No side effects |
| `Alloc` | Heap allocation (`alloc`) |
| `Mut` | Mutable heap state: `(set base.field v)`. Plain `set` on a `mut` local is deliberately *not* `Mut` - a local's mutation is invisible outside its function, while a field store is visible through every alias of the value |
| `Div` | Divergence (infinite loops) |

### Declaring an Effect Type

```scheme
(effect Console
  (log :: (-> String Int)))
```

An `effect` declaration introduces each operation as a callable name:
`(log "hi")` type-checks against the operation's signature and
dispatches at runtime through the innermost installed handler (below).
Calling an operation performs the effect - `log`'s callers infer
`#effects=Console`, transitively, and `;@axiom:effect(console)` claims
validate against it (custom tag values match declarations
case-insensitively). Operation names join the ordinary value
namespace: colliding with a function in the same module is a duplicate
definition (`AX3006`, `tests/diagnostics/455-effect-op-collision.ax`),
cross-module collisions resolve by the one-bare-name rule,
and an operation cannot be used as a bare value - wrap it in a lambda
(`(lambda (x) (log x))`) where a function value is needed. Declaring
an effect named after a built-in (`IO`, `Alloc`, ...) is **accepted**;
the refusal this paragraph used to claim is not implemented, measured
2026-08-10.

### Annotating Functions with Effects

Use AXTAG metadata above the function declaration:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main) (println "hello"))
```

The compiler validates that the body actually performs the declared effects.

### Handling Effects

`handle` plays two roles, decided per effect in its list. For built-in
effects it is a *static* scope, exactly as before: listed effects are
subtracted from what the body contributes to the enclosing function's
inferred set, the handler expression is not evaluated, and the whole
form lowers to its body.

```scheme
; The body's IO stops here for inference purposes
(handle (println "hello") (IO) 0)
```

For a *declared* effect, `handle` installs its handler for the body's
dynamic extent - evidence-passing, tail-resumptive: an operation
performed anywhere in that extent (any call depth) invokes the
innermost installed handler in the operation's place, the handler's
return value is the operation's result, and execution continues.

```scheme
(handle
  (log "hi")            ; dispatches to the lambda below
  (Console)
  (lambda (s) { (println s) 0 }))
```

The rules that make this predictable:

- **Nesting shadows and restores.** The innermost handler wins while
  its `handle` is live; the previous one answers again when it exits.
- **A handler runs under the evidence at its installation.** An
  operation the handler itself performs dispatches *outward* to the
  next handler, never back into itself - which also matches the
  static story, since a handler's own effects propagate past its own
  `handle`.
- **No handler in dynamic extent is a trap.** The program exits with
  code 71 rather than continuing on a value nothing produced.
- **A multi-argument operation's handler is a curried chain** -
  `(lambda (a) (lambda (b) ...))` - because application is one
  argument per step; a flat two-parameter lambda is tuple-typed and
  refused by the handler type check.
- **In inference,** the handled effect subtracts from the body's
  contribution like a built-in, the handler's own effects count at the
  handle site (installing it entails maybe running it), and the form
  performs `Alloc` (the evidence record). `AX3011` still requires the
  list to name *every* effect the body performs, so a body whose
  inner handlers do I/O lists `(Console IO)` even though only
  `Console` is intercepted - the list documents, the declaration
  decides what dispatches.

Current limits, each a stable diagnostic rather than a silent
miscompile: one custom effect per `handle` (nest them for more), only
single-operation effects handled dynamically, and a `handle` list
naming an undeclared effect is `AX3016`. The self-hosted compiler
parses, checks and emits both `effect` and `handle`, evidence globals
and the unhandled-operation trap included — this paragraph said the
opposite until 2026-08-14, long after it stopped being true
(`docs/memory-model.md` MM-EXEC-10 is the measured probe).

---

## Modules and Imports

Split a program across files with `(import Mod.Sub ...)`:

```scheme
; Math/Ops.ax
(pub :: square (-> Int Int))
(pub fn (square x) (* x x))
```

```scheme fragment
; main.ax
(import Math.Ops (square))    ; only bring in `square`
; (import Math.Ops)            ; would bring in every pub decl

(:: main Int)
(fn main (square 5))
```

### Visibility

All declarations are **private by default** — they are only visible within the defining file. Mark a declaration with `pub` to make it importable from other modules:

```scheme
(pub :: square (-> Int Int))  ; public — importable
(pub fn (square x) (* x x))   ; public — importable

(:: helper (-> Int Int))      ; private — only visible in this file
(fn (helper x) (+ x 1))       ; private — only visible in this file
```

The `pub` keyword goes before the declaration keyword, inside the same parenthesized form:

| Private | Public |
|---|---|
| `(:: name type)` | `(pub :: name type)` |
| `(fn (name args) body)` | `(pub fn (name args) body)` |
| `(data Name ...)` | `(pub data Name ...)` |
| `(struct Name ...)` | `(pub struct Name ...)` |
| `(macro (name pat) body)` | `(pub macro (name pat) body)` |

`pub` controls **which names are visible outside the module**, not which declarations the program contains. A module's own bodies reach its own declarations whether or not they are `pub`, so a module with private helpers imports and behaves exactly like one without. Naming a declaration a module does not export is `AX3023`, which says which module it belongs to.

Both halves matter, and until 2026-08-10 there was only one: a private declaration was *deleted* from the program by whatever imported it, which broke the module's own calls to it — and if the importing file happened to define the same name, those calls silently reached that definition instead. See [self-hosting.md §14](self-hosting.md).

`macro` and `effect` declarations are the exception and are exported unconditionally; their names carry no module, so visibility is not yet expressible for them.

### How Imports Work

- A dotted module path maps directly to a file path: `Math.Ops` resolves to `Math/Ops.ax`, always relative to the entry file's own directory.
- `(import Mod.Sub)` with no name list makes every `pub` top-level declaration visible.
- `(import Mod.Sub (a b))` makes only the named ones visible. A name the module does not export stays invisible even when the list asks for it.
- An import's name list is **not** itself checked: `(import M (noSuch))` is accepted in silence, and the mistake surfaces as `AX3001` wherever the name is used, or as nothing at all if it never is.
- Imports are transitive (`A` imports `B` imports `C` brings `C`'s declarations into `A` too) and diamond-safe (two different modules both importing `C` merges `C` exactly once).
- Qualified access is supported: `Mod::name` resolves to `name` declared in `Mod`. Imported declarations still join the importing module's flat top-level namespace by default; use `Mod::name` to disambiguate when the same name exists in multiple modules.
- A module path that doesn't resolve to a real file is `AX5001`.

---

## Macros

A macro rewrites its invocation into a template, before the type
checker runs. The compiler executes no code from a source file:
expansion is substitution and nothing else.

```scheme
(macro (when test body) (if test body 0))
(pub macro (unless test body) (if test 0 body))

(when (== n 40) 5)          ; becomes (if (== n 40) 5 0)
```

The name lives inside the head parens, like a function's. A macro is
applied to **exactly** as many arguments as it declares parameters —
too few or too many is `AX3018`.

Arguments are substituted as syntax, so one used twice in a template is
evaluated twice:

```scheme
(macro (twice x) (+ x x))
(twice (readLine))          ; reads twice
```

**Expansion is hygienic in the binder direction.** A binder the
template introduces cannot capture a name from the call site:

```scheme
(macro (addTo x) (let ((tmp 100)) (+ tmp x)))
(let ((tmp 1)) (addTo tmp))     ; 101, not 200
```

**A macro name is not a keyword.** A binding of the same name wins:

```scheme
(macro (v) 9)
(fn (f v) v)                    ; the parameter, not the macro
```

Because the expansion is checked like ordinary code, a mistake inside a
template is an ordinary diagnostic — including exhaustiveness on a
`match` the macro generated. The diagnostic anchors at the invocation.

**A macro can also produce declarations** (2026-08-14). The rule form
— the macro's bare name, then one rule whose pattern head repeats it —
generates one declaration per template form when invoked at top level:

```scheme
(macro defWrap
  ((defWrap nm target extra)
   (:: nm (-> Int Int))
   (fn (nm x) (+ (target x) extra))))

(defWrap w1 base 1)             ; declares w1, a wrapped base
(defWrap w2 base 100)           ; and w2 - names are parameters
```

Templates may generate `fn` and `::` declarations and further macro
invocations; an argument standing in a name position must be a bare
identifier; invocation is entry-file only. Everything outside that
surface is refused loudly — `AX3027` at the invocation (`axiom explain
AX3027`), or `AX3021` at the macro's own line for an unsupported
template kind. A useful side effect of the form existing: a typo'd
declaration keyword like `(fnn (broken) 3)` is now `AX3027` naming
`fnn`, where it used to be a bare `syntax error` that stopped the
parse.

**A declaration macro can ask about the program's types** — through
the `syntax/*` query vocabulary, a closed set of questions the
expander answers from the declaration list at compile time, with no
user code running. Three of them are enough to make `deriveEq` over
any sum type an ordinary macro:

```scheme
(pub macro deriveEq
  ((deriveEq T)
   (:: (syntax/join eq T) (-> T T Bool))       ; names eqColor
   (fn ((syntax/join eq T) a b)
     (match a
       (syntax/for (C (syntax/constructors T)) ; one arm per ctor
         ((C) (match b ((C) true) (_ false))))))))

(data Color () (Red) (Green) (Blue))
(deriveEq Color)                               ; eqColor, checked code
```

A query with no answer — an unknown `syntax/` head, `constructors` of
a struct, a query outside a template — is `AX3028` (`axiom explain
AX3028`), never a default. The `syntax/` prefix is reserved in
declaration names.

Structs and fieldful constructors are covered too: `(syntax/fields
S)` iterates a struct's field names, `(syntax/binders C x)` names a
constructor's fields as hygienic pattern binders, and `(syntax/fold
&& true ...)` chains a comparison over them — the spec's `deriveEq`
and `deriveLenses` both run verbatim, and a derived `impl` composes
with the next derive.

Three more answer one value where one value is needed, and each is
what a shipped prelude macro is written in terms of:

| Query | Answers | The macro that spends it |
|---|---|---|
| `(syntax/name C)` | the constructor's spelling, as a `String` literal | `deriveShow` — `(deriveShow Shape)` gives you `showShape : Shape -> String`. A tag is an integer at run time, so this is the only route from a constructor to its name |
| `(syntax/arity C)` | its field count, as an `Int` literal | `deriveArity` — a heap block records its tag and never its arity, so this is the only route to that number either |
| `(syntax/defined n)` | whether `n` names a visible declaration | `showOr` — `(showOr T x "?")` renders with `showT` if the program derived one and answers the fallback if it did not. The `if` is decided at expansion time and the losing branch is deleted, which is what makes the query useful: the branch naming `showT` would not type in a program without it |

`(syntax/join a b)` also stands where a *reference* stands, so a macro
can call what it names — `((syntax/join show T) x)` — and can feed
another query's argument, which is how `showOr` asks about a name no
source file spells.

What macros cannot do yet: match on the shape
of their arguments, or repeat a template over a variable number of
them (`deriving (Eq)` is refused outright — see Deriving Traits).
The normative specification is [macro-system.md](macro-system.md);
[macros.md](macros.md) is the measured detail and the order the rest
is planned in.

---

## Memory Primitives

The standard library is built on these low-level primitives, and so is any code that needs to talk to the machine directly. They are the layer where the type system stops — every argument and result is an `Int`.

| Primitive | Meaning |
|---|---|
| `(__syscall0 n)` ... `(__syscall6 n a1 ... a6)` | Raw syscall |
| `(__load8 base i)` / `(__store8 base i v)` | Byte at `base + i` |
| `(__load64 base i)` / `(__store64 base i v)` | Machine word at `base + i * 8` |
| `(__alloc bytes)` | Address of `bytes` fresh zeroed bytes |
| `(__addr "literal")` | Address of a string literal's bytes |

Syscall numbers are not built into the compiler — they live in `stdlib/Sys/Platform.<os>[-<arch>].ax`, and the module resolver picks the file matching `--target`.

### Allocation

```scheme
(:: memAlloc (-> Int Int))
(fn (memAlloc bytes)
  (__alloc bytes))
```

Memory comes from the backend's `mmap`-backed bump allocator. There is no `free` — an Axiom process reclaims everything at exit. Defining `axiom_alloc` yourself does **not** replace the allocator: the name is refused (`AX3026`) — the override seam does not exist. Until 2026-08-14 the program instead passed `check` and failed in `opt` with `invalid redefinition of function 'axiom_alloc'` (`docs/memory-model.md` MM-ALLOC-8).

---

## Standard Library

Axiom ships a standard library written **in Axiom**. It reaches the operating system through raw syscalls, not through C, so a compiled Axiom program contains no call to libc.

### Modules at a Glance

| Module | Provides |
|---|---|
| `Pre` | `when`, `unless`, `cond2`, `cond3` (conditional macros) |
| `Mem` | `memAlloc`, `memAllocMapped`, `memCopy`, `memSet`, `memCmp`, `memGetByte`/`memPutByte`, `memGetWord`/`memSetWord` |
| `Str` | `strFromLit`, `strAlloc`, `strLen`, `strByte`, `strCmp`, `strEq`, `strSlice`, `strDup`, `strConcat`, `strFindByte`, `strStartsWith`, `strCStr` |
| `Utf8` | `utf8Len`, `utf8CharAt`, `utf8DecodeAt`, `utf8FromChar`, `utf8Next`, `utf8Offset`, `utf8Slice`, `utf8Width`, `utf8SeqLen`, `utf8IsCont`, `utf8Valid` (the character view of a `Str`) |
| `Vec` | `vecNew`, `vecPush`, `vecPop`, `vecGet`, `vecSet`, `vecLen`, `vecCap`, `vecReserve`, `vecClear` |
| `Map` | `mapNew`, `mapHas`, `mapGet`, `mapInsert`, `mapRemove`, `mapLen`, `mapCap`, `mapNew`, `mapRehash` (open-addressing `Int→Int` hash map) |
| `Fmt` | `fmtInt`, `fmtHex`, `fmtPadLeft`, `fmtIntWidth` |
| `Intern` | `internNew`, `internIntern`, `internFind`, `internLookup`, `internCount` (string interner) |
| `Sys` | `sysWriteFd`, `sysReadFd`, `sysOpenPath`, `sysCloseFd`, `sysSeek`, `sysExitWith`, `sysFailed`, `sysErrno`, `stdin`/`stdout`/`stderr` |
| `IO` | `print`, `println`, `printLit`, `printlnLit`, `printInt`, `printlnInt`, `eprint`, `eprintln`, `writeStr`, `readUpTo`, `readAll`, `readFile`, `readFileLit`, `exit`, `die` |

### A `Str` Is...

A `Str` is a length-prefixed, NUL-terminated string. It is the address of a three-word header:

- Word 0: length in bytes
- Word 1: address of the bytes
- Word 2: the block owning those bytes, or 0 when no block does

The owner word (added 2026-08-15) is what lets a slice keep its
parent's buffer alive by arithmetic: `strSlice` shares the bytes and
inherits the owner rather than naming its parent, so the chain is one
hop deep however many times a slice is cut. Zero means the bytes are
nobody's to free — a literal's belong to the loader, a syscall
buffer's to the kernel. See [memory-model.md](memory-model.md)
MM-VAL-7.

The bytes are always NUL-terminated in addition to being length-counted. This means `strCStr` can hand a path straight to a syscall without copying, and a `Str` can contain a NUL byte.

### Text Is UTF-8, and `Str` Stays Bytes

A `Str` holds bytes, and `Str`'s own operations are byte operations:
`strLen` counts bytes, `strByte` reads one, `strSlice` cuts at byte
offsets. That is deliberate and will not change. Every syscall write
hands `(strData s)` and `(strLen s)` straight to `write`, every hash
folds over bytes, and every buffer sizes itself in bytes - a `strLen`
that answered in characters would write the wrong number of bytes to a
file descriptor.

The character view lives beside it, in `Utf8`:

```scheme
(import Str)
(import Utf8)

(strLen  "héllo")            ; 6 - bytes
(utf8Len "héllo")            ; 5 - characters
(utf8CharAt "aé世" 2)        ; 19990, the code point of 世
(utf8Offset "aé世" 2)        ; 3, the byte offset it starts at
(utf8Slice "héllo, 世界" 7 2) ; "世界", sharing the original's bytes
(utf8FromChar (cast Int '世')) ; a new one-character Str
```

This is the same split Rust draws between `len()` and
`chars().count()`, and it works because a `Char` is already a code
point: `(utf8DecodeAt "é" 0)` and `'é'` are both 233. Character
indexing is O(n) in the byte length - UTF-8 is variable-width and
nothing builds an index - so walk a string with `utf8Next` rather than
by rising character index, or the loop is quadratic.

Decoding answers `-1` rather than a guess when there is no character
to read: past the end, on a sequence cut short by the end of the
string, or on a byte that begins no sequence at all. `-1` and not `0`
because `0` is a real character, and a sentinel rather than an
`Option` because every `data` value heap-boxes - the same argument
`strFindByte`, `vecGet` and `mapGet` already make. Inventing a value
would be worse than refusing one: read as bytes-with-zeros, the first
byte of `世` decodes to U+4000, an ordinary CJK character, and the
tail byte of `é` to `©`.

Iteration is never blocked by bad input, though: `utf8SeqLen` answers
1 for a byte it does not understand, so `utf8Next` always advances and
no decoding loop can hang on a corrupt file. `utf8Valid` is the
explicit question when a caller needs a verdict on the whole string.

Encoding is total in the other direction: `utf8FromChar` always
produces well-formed UTF-8, because anything that is not a Unicode
scalar value - negative, a surrogate, or past U+10FFFF - is encoded as
U+FFFD. So `(utf8Valid (utf8FromChar x))` holds for every `x`.

Most of `Str` needed no change at all, for two reasons worth knowing
rather than rediscovering. UTF-8 orders bytes the same way Unicode
orders code points, so `strCmp`, `strEq` and `strStartsWith` are
already correct on text. And UTF-8 is self-synchronizing - no
multi-byte sequence contains a byte below `0x80` - so `strFindByte`
searching for an ASCII byte can never match the middle of a character.

---

## AXTAG Metadata

AXTAGs are source-embedded agent metadata preserved from `;@axiom:<key>(<value>)` comments immediately above a declaration. The compiler validates what it can and surfaces accepted tags as `#`-metadata on AXSYM lines.

### Syntax

```scheme fragment
;@axiom:effect(io)
(fn (main) (println "hello"))

;@axiom:pure()
(fn (pureFn x) (* x x))

;@axiom:no_refactor
(def legacyFn ...)

;@axiom:owned(arena=frame)
(defn ownedFn ...)
```

### Common AXTAG Keys

| Key | Meaning |
|---|---|
| `effect(io)` | Declares that the function performs I/O |
| `pure` | Declares that the function has no side effects |
| `no_refactor` | Hints that the declaration should not be modified by automated refactoring |
| `owned(arena=frame)` | Ownership metadata; accepted and unenforced — the wording predates the reference-counting decision (`docs/memory-model.md` MM-LIFE-7) |

The compiler validates `effect(io)` claims against what the body actually performs - a `__syscallN`, or a call to something that performs one - and `pure` claims against the absence of any effect. Mismatches emit a warning (`AX3010`).

---

## Linear Types and Consume

Axiom parses linear type syntax — intended for types where values have exactly one owner and cannot be duplicated or discarded. Nothing enforces it today.

### Linear Type Marker

```scheme
(linear T)
```

**Parsed only.** `linear T` parses to the nominal type constructor `Linear T`, and nothing counts uses: a value used twice, or zero times, is accepted and runs. The memory model no longer depends on this — deterministic reclamation is the chosen reference counting, obtained without linear types (`docs/memory-model.md` MM-LIFE-2a); what linearity would still buy is retain/release-free moves and early drops (MM-LIFE-7). The enforcement is not written.

### Consume

```scheme
(consume expr)
```

**Parsed only.** `consume` is a parse-time identity that keeps the `Linear` wrapper; consuming twice is accepted, and no memory is reclaimed at that point or any other — there is no `free`. Deterministic reclamation today is `__axiom_arena_mark` / `__axiom_arena_reset_keeping`, written by hand; the specified end state is reference counting — see `docs/memory-model.md`.

---

## Removed Features

These features existed in earlier versions of Axiom but have been removed. The keywords remain reserved and will report a helpful error if used.

### `union` — Removed

C interoperability is no longer a goal, and an untagged union has no meaning under linear types. Use `data` for a tagged sum or `struct` for a product.

### `region` — Removed

Reclamation is never written by hand as a region annotation — the chosen automatic strategy is reference counting, and the region-inference sketch that originally justified this sentence is withdrawn (`docs/memory-model.md` MM-LIFE-2a, §3.4). Delete the `region` wrapper and keep its body.

### `foreign` — Removed

C interoperability is no longer a goal, and the binding never worked: it emitted a call to a symbol the module never declared, so a program that used one passed `check` and then failed inside `opt` or the linker. Generated code links no C library. Reach the kernel through the standard library, which is written in Axiom over `__syscall0`-`__syscall6`.

Struct layout modifiers went with it. `packed`, `repr(C)` and `align(N)` appeared in this document and in the formatter; the parser rejected all three.

---

## The REPL

The REPL compiles expressions to native code — it doesn't interpret them. This means you get real performance even in interactive mode.

```bash
axiom repl
```

### REPL Commands

| Command | Aliases | What it does |
|---|---|---|
| `:help` | `:h`, `?` | Show all commands |
| `:quit` | `:q`, `:exit` | Exit the REPL |
| `:type <expr>` | `:t <expr>` | Show the type of an expression |
| `:load <file>` | `:l <file>` | Load a file into the REPL |
| `:reset` | `:r` | Clear all definitions |
| `:defs` | `:d` | Show all definitions in scope |
| `:llvm <expr>` | — | Show the generated LLVM IR |
| `:time <expr>` | — | Time how long an expression takes |

### Example Session

```
axiom> 1 (:: add (-> Int Int Int))
OK: add defined

axiom> 2 (define (add x y) (+ x y))
OK: add defined

axiom> 3 (add 3 4)
type : Int
result 7
```

The REPL accumulates definitions — functions you define persist across inputs. History is saved between sessions.

---

## CLI Commands

### Checking and Building

```bash
# Check syntax and types (no code generation)
axiom check source.ax

# Compile to a native executable
axiom build --input source.ax --output program

# Emit LLVM IR to stdout
axiom emit-llvm source.ax

# Emit LLVM IR to a file
axiom emit-llvm source.ax -o output.ll

# Compile and run immediately
axiom run source.ax
```

### Choosing a Memory Manager

```bash
# Default: an mmap-backed bump allocator. Nothing is ever freed, so peak
# memory is proportional to *total* allocation. Right for a process that
# exits in milliseconds, and it costs nothing at runtime.
axiom build --input source.ax --output program

```

The build is freestanding — it does not call libc.

There is no tracing collector. The retired Rust compiler had one behind
a `--gc` flag; it was not ported, and `--gc` is now refused by name
rather than silently ignored (see `docs/self-hosting.md` §8.4). Peak
memory therefore tracks *total* allocation, not live data. Where that
matters, `__axiom_arena_mark`, `__axiom_arena_reset` and
`__axiom_arena_reset_keeping` let a program reclaim explicitly by
rolling the allocator's waterline back — which is how the language
server holds flat memory across an editing session. (Two claims stood
here until 2026-08-14 and both were false: defining `axiom_alloc` did
not replace the allocator — it was a duplicate-symbol failure in `opt`,
and is now refused outright as `AX3026` — and no compile error ever
refused the arena primitives alongside such a definition.
`docs/memory-model.md` MM-ALLOC-8 records both.)

The three carry a contract the compiler cannot check: after a reset,
nothing allocated since the matching mark may be read again. What the
allocator does guarantee around them is worth stating, because the
one useful pattern depends on it:

- `memAlloc` answers **zeroed** memory always, including memory a
  reset has reclaimed and handed out again.
- `memAlloc` also answers a **leaf**: a block it hands out is declared
  to hold no references, because a byte count is all it was told.
  `(memAllocMapped bytes map)` is the same allocation with bit *i* of
  `map` naming payload word *i* as a handle to another counted block,
  so releasing this block releases that one too. `Str`'s header is the
  first user — word 2 owns the bytes — and it is what makes a dead
  string free its buffer rather than just its header. The map is
  clamped to the block, so it can name the wrong word of your own
  block and never a word outside it.
- A reset **writes nothing** to what it reclaims. Memory above the
  restored waterline keeps its contents until it is handed out again.
- `(__axiom_arena_reset_keeping mark addr bytes)` reclaims to `mark`
  and carries the `bytes` at `addr` across the reclaim, answering
  their new address. This is how a value is kept: doing it as a reset
  followed by an ordinary copy is unsound, because the copy's
  destination is scrubbed on allocation and the scrub can run over
  the source.

### Using the AI-Optimized Format

For machine-readable output, always use `--diagnostic-format=ai`:

```bash
axiom --diagnostic-format=ai check source.ax
axiom --diagnostic-format=ai build --input source.ax --output program
axiom --diagnostic-format=ai symbols source.ax
```

See [docs/diagnostics.md](diagnostics.md) for the full AXDL and AXSYM notation reference.

### Symbol Listing

```bash
# List every top-level symbol and its type
axiom symbols source.ax

# Also include built-in operators
axiom symbols source.ax --builtins
```

### Diagnostic Lookup

```bash
# Look up a diagnostic code
axiom explain AX3001

# List all known diagnostic codes
axiom explain --list
```

---

## Compiler Pipeline

```
Source (.ax) → Lexer → Parser → Imports → Macro Expansion → Type Checker → IR → LLVM IR → llc → cc → Executable
```

### Compiler Structure

The compiler is written in Axiom, in `self_host/`.

| Module | Purpose |
|---|---|
| `core.ax` | Tokens and spans |
| `lexer.ax` | Tokenizer |
| `parser.ax` | S-expression parser and AST |
| `expand.ax` | Macro expansion, hygiene, expansion diagnostics |
| `typecheck.ax` | Name resolution, type checking, effects, AXTAG validation |
| `codegen.ax` | Import resolution, name mangling, LLVM emission |
| `diag.ax` | Diagnostics, AXDL/JSON rendering, source maps |
| `render.ax` | The human diagnostic renderer |
| `driver.ax` | `build`: `opt`, `llc`, `cc` |
| `main.ax` | CLI entry point; `format.ax`, `repl.ax`, `symbols.ax`, `explain.ax`, `lsp.ax` are the tools |
| `Host.<target>.ax` | Host triple and syscall ABI, selected when the compiler is compiled |

---

## Cross-Compilation

Use `--target` to select the platform:

```bash
axiom --target=linux-x86_64 emit-llvm main.ax -o main.ll
```

Supported targets: `darwin-aarch64`, `darwin-x86_64`, `linux-aarch64`, `linux-x86_64`. Defaults to the host.

---

## Optimisation

Axiom has `while` with `mut` and `set` (see [Mutable Bindings and `while`](#mutable-bindings-and-while)), used 241 times in the compiler's own sources. Iteration may also be written as recursion. A **self** tail call runs in constant stack at every `--opt` level, including 0 — the loop is built by Axiom's own codegen, not by LLVM (`docs/memory-model.md` MM-EXEC-6b; this sentence attributed it to `--opt 1`'s LLVM passes until 2026-08-14). What still needs `--opt 1` (the default) and above is **mutual** tail recursion and a tail call sitting in a `let` body, which only LLVM's passes flatten (MM-EXEC-6c):

```bash
axiom build --input main.ax --output main --opt 2
```

Use `--opt 2` for anything that iterates over a large input.

---

## Tips and Patterns

### Writing a Function with I/O

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

### Using `let` for Intermediate Values

```scheme
(fn (compute n)
  (let ((x (+ n 1))
        (y (* x 2)))
    (+ x y)))
```

### Pattern Matching on ADTs

```scheme
(data Maybe (a)
  (Nothing)
  (Just a))

(:: safeDiv (-> Int Int (Option Int)))
(fn (safeDiv a b)
  (match b
    ((0) (None))
    (_ (Some (/ a b)))))
```

### Building a List

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
(fn main
  (sum (Cons 1 (Cons 2 (Cons 3 (Nil))))))   ; => 6
```

### Using the Standard Library

```scheme
(import IO)
(import Str)
(import Fmt)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (printlnInt 42)
    (println (strConcat "sum=" (fmtInt (+ 1 2))))
    0
  })
```

---

## Further Reading

- [The Memory Model](memory-model.md) — the normative specification: representation, allocation, mutation, lifetimes; reference counting is the chosen reclamation strategy
- [The Macro System](macro-system.md) — the normative specification: expansion, hygiene, budgets, and what `derive` will be built on
- [Macros](macros.md) — what expansion guarantees, what it does not, and the probes behind each claim
- [Diagnostics & Agent Notations](diagnostics.md) — AXDL, AXSYM, NID, AXTAG reference
- [Self-Hosting](self-hosting.md) — how the Rust compiler was replaced with one written in Axiom, and how a clean checkout builds it
- [v1 Roadmap](v1-roadmap.md) — what is done, what is left, and what blocks what
- [README](../README.md) — project overview and installation guide