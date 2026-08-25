# Axiom Language Reference

A friendly, comprehensive guide to the Axiom programming language — a functional systems language that compiles to native code via LLVM, with no VM and no runtime. Memory comes from an `mmap`-backed bump allocator, and dead blocks are reclaimed by reference counting ([memory-model.md](memory-model.md) MM-LIFE-2).

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
16. [Effects](#effects) — `effect`, `handle`, and inference
17. [Modules and Imports](#modules-and-imports)
18. [Macros](#macros)
19. [Printing and Formatting](#printing-and-formatting)
20. [Memory Primitives](#memory-primitives)
21. [Standard Library](#standard-library)
22. [AXTAG Metadata](#axtag-metadata)
23. [Linear Types and Consume](#linear-types-and-consume)
24. [Removed Features](#removed-features)
25. [The REPL](#the-repl)
26. [CLI Commands](#cli-commands)
27. [Compiler Pipeline](#compiler-pipeline)
28. [Cross-Compilation](#cross-compilation)
29. [Optimisation](#optimisation)
30. [Tips and Patterns](#tips-and-patterns)
31. [Further Reading](#further-reading)

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

That's it. No headers, no build system, no runtime. The `IO` module is part of Axiom's own standard library, which reaches the kernel through raw syscalls, so this program links and calls no C function. An `extern` block is the one door that changes that ([ffi.md](ffi.md)).

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
whose last three words are the `Str` triple: length, byte address and
owner, exactly the layout `Str.strWrap` builds. The first two words
are the MM-LIFE-2b count/shape header every heap block carries, with
the count all-ones:
a static is never reclaimed, and the runtime's retain/release read the
sentinel and leave it untouched. The literal's value points at the
{length, bytes, owner} triple, so every consumer loads at +0/+8 as
before; the owner word is zero, because a literal's bytes are
loader-resident and no block's death may free them (`MM-VAL-7`):

```llvm
@str_0    = private unnamed_addr constant [14 x i8]  c"\48\65\6C\6C\6F\2C\20\41\78\69\6F\6D\21\00"
@strhdr_0 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 13, ptr @str_0, i64 0 }, align 16
```

The emitter escapes every byte, so `\48\65\6C...` is `Hello, Axiom!`
and its NUL; `axiom emit-llvm` on `(strLen "Hello, Axiom!")` prints
exactly these two lines.

The literal evaluates to the triple's address. Its **length is computed
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
the self-hosting record.

### Keywords

These words carry grammar rules. There is no reserved-word list in the
lexer: each is an ordinary identifier everywhere except the position
its rule claims — the head of a form, and for `mut` the head of a
`let` binding. `(let ((match 1)) match)` binds a variable called
`match`; `(cast e)` is read as the cast form whatever `cast` is bound
to. Shadowing one is legal and a bad idea.

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

These words still have a rule, and the rule is a refusal (`AX2004`). Using one in head position reports what to write instead:

| Keyword | Replacement |
|---|---|
| `union` | Use `data` for a tagged sum or `struct` for a product |
| `region` | Delete the `region` wrapper; lifetimes are inferred |
| `foreign` | Write an `extern` block (see below); or use the standard library, which needs no FFI |

### `extern` — binding Rust

An `extern` block names symbols in a static archive. Each item carries
its type inline and the linker symbol it binds:

```scheme
(pub extern "axiom_demo"
  (add         :: (-> Int Int Int) (symbol "axffi_add"))
  (countVowels :: (-> String Int)  (symbol "axffi_count_vowels")))
```

Build against the crate with one flag — the driver runs
`axiom-bindgen` when the crate's `axiom/` module is missing or older
than its `src/`, runs `cargo build --release` when the archive is
missing (each only if the tool is on `PATH`), and links the archive
because the block's library name says so:

```
axiom build --input p.ax --output p --crate path/to/crate
```

(`--link-lib NAME --link-search DIR` and `$AXIOM_LINK_SEARCH` remain
as explicit overrides; an `$AXIOM_PATH` entry's `../target/release` is
searched too.) The emitter writes `declare i64 @axffi_add(i64, i64)
#0` for every item the program CALLS and the call site emits the same
`call i64 @sym(...)` an internal call does. Five rules:

- The type is **inline and required**. A separate `(:: name Type)`
  draws `AX3015`; an item without `:: type` is a parse error.
- An item's signature names only `Int`, `Float`, `Bool`, `Char`,
  `String` and `Foreign` — one machine word each way — plus a
  callback parameter: an arrow of arity one to three whose leaves are
  words (`Int`, `Float`, `Bool`, `Char`). A type variable, a tuple, any
  other function type or a declared type (`(Option Int)`, `Handle`, a struct) is
  `AX3036`: such values cross as a `Foreign` handle or through the
  generated wrapper (a `Vec<T>` result becomes a `Vec`; a Rust
  `#[axiom_record]` struct becomes a `data` type whose fields cross
  one word each).
- `(symbol "...")` is the **only clause**; any other head is a parse
  error naming it. Write it explicitly — a static link is one flat
  namespace and the default is the Axiom name.
- Calling one contributes the **`IO` effect**, exactly as `__syscallN`
  does, and it propagates transitively.
- A `fn` spelled like an item is a duplicate (`AX3006`); two blocks
  naming one library are not.

A symbol no linked archive defines is `AX4004` at the item, before the
toolchain runs — in three voices: nothing linked at all, an archive
linked that lacks the name (with the nearest `axffi_*` name it does
hold), and the search path it used. The check reads the archives'
symbol tables, so a prefix of a real name is refused as the typo it is.
A symbol the archive exports under a different shape — every
`#[axiom_export]` shim carries a descriptor, `axffi_add__sig_ii_i` —
is `AX4005` at the item.

The other direction is `--emit-staticlib`: `axiom build --input lib.ax
--output libaxiom_lib.a --emit-staticlib` archives a module with no
`main`, every `pub fn` a C symbol under its own name, for a Rust (or
C) host to link; `--emit-rust-binding lib.rs` beside it writes the
Rust module that declares and wraps them (`Int`→`i64`, `Float`→`f64`,
`Bool`→`bool`, `Char`→`char`, `String`→`&str` in and `AxString` out, a
`data`/`struct`→a Rust `struct`/`enum`, `Option`/`Result`→Rust's own),
synthesising the accessor shims those conversions need into the
archive, and naming in a comment any function whose type it does not
carry (a type variable, a tuple, an arrow).

`foreign` is not this feature renamed and remains `AX2004`. See
[docs/ffi.md](ffi.md).

---

## Types

### Primitive Types

| Type | Description |
|---|---|
| `Int` | 64-bit signed integer |
| `Float` | 64-bit floating point |
| `Bool` | Boolean (`true` / `false`) |
| `Char` | A Unicode code point: `'A'` is 65, `'é'` is 233, `'世'` is 19990, `'😀'` is 128512 |
| `String` | String (pointer) |
| `()` | Unit (no value). A **type** only — `(:: main ())` and `(:: f (-> () Int))` are accepted, and `symbols` renders the empty tuple as `()`. There is no unit *value*: `()` in expression position is `AX2001 expected expression`, as it is in `[]` and `(set)`, and nothing in the language produces or consumes one |
| `Unit` | A distinct type constructor spelled `Unit`, **not** a synonym for `()`: `symbols` renders `(:: a (-> () Int))` as `(() -> Int)` and `(:: b (-> Unit Int))` as `(Unit -> Int)`. `Unit` was missing from the parser's type-keyword set until 2026-08-10, so it was a bare unresolvable constructor that nothing asked about until signature types began to be resolved — see the self-hosting record |
| `Void` | Void |
| `Any` | Generic pointer |
| `Foreign` | An opaque pointer into memory Axiom did not allocate and does not own, held as one word (see [ffi.md](ffi.md)). Distinct from `Int` on purpose: `tyCompat` matches named constructors by name, and the distinction is load-bearing rather than documentary — a `Foreign` field is left OUT of the ARC reference map (`docs/memory-model.md` MM-LIFE-2d), so `@axiom_release` never follows it. Measured on `(struct T (a : String) (b : Foreign) (c : String))`: the map is payload words `[0, 2]`. `(cast Foreign x)` is the explicit way in and out |
| `Handle` | A Rust value Axiom OWNS a share of: a counted block of the foreign form holding the Rust pointer and its destructor (`stdlib/Ffi.ax`, [ffi.md](ffi.md)). A reference like `String` — mapped in a cell that holds it, released at a `let`'s scope end — and when its last share goes the release runtime runs the Rust `Drop` once. `axiom-bindgen` wraps each opaque Rust type in its own `data` type around a `Handle`, so `Counter` and `Widget` stay distinct; `ffiHandleClose` destroys the value early and leaves the block inert |

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

`[Int]` and `(Int String Bool)` are **type syntax only**. There is no
list or tuple literal, no list or tuple pattern, and no runtime
representation: `[1 2 3]` is `AX2001 expected expression`, and `(1 2)`
in expression position is read as an application of `1`. A signature
may name these types; nothing can build a value of one.

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

This says `add` is a function that takes two `Int`s and returns an `Int`. The `(-> A B C)` syntax means a function that takes `A`, then `B`, and returns `C`. The type is curried; a *top-level* function still is not partially applicable (see [Partial Application](#partial-application--not-supported)).

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

### Partial Application — Not Supported

A curried *signature* does not make a top-level function partially
applicable. Supplying fewer arguments than a top-level function takes
is `AX3013`: a partial application has to hold the arguments it was
not given, and a top-level function has no closure record to hold them
in (`tests/diagnostics/110-partial-application.ax` pins the refusal).

```scheme refused
(:: add (-> Int Int Int))
(fn (add x y) (+ x y))

(:: addFive (-> Int Int))
(define addFive (add 5))

(:: main Int)
(fn main (addFive 1))
; error[AX3013]: partial application of `add`: it takes 2 argument(s)
;                and 1 were supplied
```

A `lambda` does get a closure record, so bind the missing argument
there:

```scheme
(:: add (-> Int Int Int))
(fn (add x y) (+ x y))

(:: main Int)
(fn main
  (let ((addFive (lambda (y) (add 5 y))))
    (addFive 3)))                        ; 8
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
(>= 1 2)            ; false

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
value yields itself rather than a positive number, which is why `Fmt`
detects that value with a predicate rather than by comparing against a
literal: there is no literal for it, and `(- 0 9223372036854775807)`
is one greater than it.

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
(:: safeDiv (-> Int Int (Option Int)))
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

A `data` type is assigned one of three representations, computed once
per type from its constructors (`codegen.ax`'s `ctorsRep`;
[memory-model.md](memory-model.md) MM-VAL-8 is normative). Tags are
globally unique across the program, not per type.

| Condition | Representation |
|---|---|
| every constructor is nullary | a value **is** its tag, an immediate below 4096; nothing allocates |
| mixed nullary and fieldful | nullary constructors are immediate tags; fieldful ones are heap blocks |
| no nullary constructor, or the type's tags would reach 4096 | every value is a heap block |

A heap block holds the tag in word 0 and its fields in words 1.., one
8-byte word each. Because an immediate tag and a block address can
arrive in the same slot, a `match` over a mixed type tells them apart
with a runtime `< 4096` test — every address a value is handed out at
is at or above that bound (MM-VAL-9). In `(data L (Nil) (Cons Int L))`
the constructor `(Nil)` lowers to the immediate `2` and matching it is
an `icmp eq i64 2, 2` with no allocation at all;
`tests/stdlib/270-nullary-unboxed.ax` and
`tests/selfhost/400-mixed-nullary.ax` pin the two unboxing shapes.

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
`AX2001` for all three. Axiom does cross the C ABI now — an `extern`
block links a static archive — but nothing crosses it as a struct: a
scalar goes one word each way, and a record crosses as its fields
([ffi.md](ffi.md) §8). There is no layout for a modifier to change.

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

A type alias gives a name to an existing type. It does not create a new type — `StringList` and `[String]` are interchangeable: the alias is expanded before checking in every position that names a type — a function signature, a struct field, and a `data` constructor's fields — and its float flags are rewritten with it, so the checker and the emitter cannot disagree about a `(type Real = Float)`. The two record positions were added on 2026-08-23: an alias there stayed nominal, so `(R 1 s)` drew `AX3004` against its own field, and behind that the emitter's `fldClass` could not classify the alias, forced the block to a leaf, and dropped the reference map that a `String` in the NEXT field needed — 80 bytes an iteration, on the field that was spelled correctly (`tests/stdlib/374-arc-alias-field.ax`). A PARAMETERISED alias — `(type Pair a = ...)` — needs substitution and is not expanded; it behaves nominally. `tests/selfhost/973-type-alias.ax`

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
- **Effects** — traits, impls and methods accept an effect list, which is parsed and discarded; nothing is checked against it, and on a `trait`/`impl` header the first parenthesised group is the supertrait list

---

## Effects

Axiom infers each function's side effects transitively - a fixpoint
over every function body, so a syscall three calls down still counts -
and validates any `;@axiom:effect(...)`/`;@axiom:pure` claims against
what it inferred (`AX3010`, a warning). Effects do not appear in
function types, and untagged functions are not policed: the tags are
opt-in claims, checked when made. `axiom symbols --diagnostic-format
ai` reports the inferred set as `#effects=...` beside any declared
tags; the default `human` table has no metadata column and shows
neither.

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
lambda literal answers for its body where the literal appears.

### When the Walk Cannot Answer

A call whose head the walk cannot resolve to a function makes the
inferred set a **lower bound** rather than the set. Four shapes reach
it:

| shape | example |
|---|---|
| a head that is not a name | `((b.f) x)`, an `if` or `match` in head position |
| a `let` bound to anything but a name or a lambda literal | `(let ((g b.f)) (g 7))` |
| a pattern binder | `(match h ((Wrap f) (f 7)))` |
| an unfollowable value handed to an effect-transparent position | `(fn (p h b) (h b.f))` |

The first three are one route through memory wearing three spellings -
a function value goes into a struct, a data constructor or a container
in one place and is called in another, and no call edge runs between
them.

The fourth is not a memory read at the call. `h` is a parameter, so
calling it *is* modelled; that is what effect transparency is for. What
is not modelled is the value handed **into** the transparent position.
"Pure modulo its function parameters" excuses `h`; it does not excuse
an argument the walk cannot name, and `b.f` is a word out of a struct
that the transparent parameter will call.

The walk records that, `symbols` prints it as `#effects-incomplete`,
and claim checking splits on it:

- a claim of ABSENCE (`;@axiom:pure`, `;@axiom:effect(pure)`) cannot be
  validated against a lower bound, so it draws `AX3037`, a warning;
- a claim of PRESENCE (`;@axiom:effect(io)`) is left alone, because an
  unresolved call may be exactly where the effect comes from, and
  reporting `missing IO` there would be a mis-report rather than an
  omission.

A lambda's own parameter is marked identically and is unreachable
today: a called lambda parameter does not type-check (`AX3004`), so no
well-typed program gets there. The marker is set anyway, because the
alternative would record that the binder was attributed somewhere, and
it is not.

The same lower bound reaches `handle`. A handled-effects list cannot be
checked against a lower bound either, so a `handle` whose body contains
an unresolved call draws `AX3038` - a warning, where `AX3011` (the same
question *answered*) is an error. That gap was not cosmetic: an effect
operation reached with no handler installed aborts the process with
status 71, and until 2026-08-24 with no message at all, so a handle
whose body reached an effect through a struct field turned a
compile-time refusal into a runtime trap. The trap now prints `axiom:
unhandled effect` on stderr - which makes the fault legible without
making it any less a runtime fault, and is why `AX3038` is still worth
having.

### Trait Methods

A trait method is dispatched on the static type of an argument, and
that type is not available to the effect fixpoint - the fixpoint runs
before any body is checked, and `traitRewrite` picks the implementation
*during* body checking. The fixpoint does not repeat the dispatch. It
unions **every** implementation of the method instead, which is what a
dynamically dispatched call means: the effects any implementation can
perform are the effects the call can perform.

The union is a true upper bound, and usually exact - `traitRewrite` can
only choose a name for which the implementation exists, so the set it
could pick from is a subset of the ones unioned here. Trait *defaults*
need no special case: a missing method is lowered through the same
`traitImplName`, so it is an ordinary declaration by the time the
fixpoint runs.

Before this, a trait-method call contributed nothing at all. A function
calling one still drew its own `AX3010`, because the claim check
re-walks the body *after* the rewrite - but its entry stayed empty, so
every caller of it inferred nothing and `symbols` printed the caller
`#pure`. The diagnostic and the symbol table disagreed about the same
function on the same run, and the transitive case was reported nowhere
(`tests/diagnostics/344-trait-effect-transitive.ax`).

### AXTAG Keys

The key namespace is open: a key the compiler does not know is
metadata, is recorded, and is not checked. `agent:readonly` draws
nothing and is meant to.

A key one edit - or one change of case - from `pure` or `effect` draws
`AX3039`. `;@axiom:pur` is not a purity claim, so nothing checks it as
one, and a body performing IO under it drew no `AX3010` at all: the tag
read like a guarantee and bought silence. A key containing `:` is never
reported, because a namespaced key is deliberate by construction and
its distance from `pure` is not evidence about anything.

Until 2026-08-22 neither happened. The sentinel that records an
unresolved call had been in the source, skipped by two consumers and
produced by nobody since `f6ddc2e` removed its last producer, so an
empty set read as an acquittal:

```scheme
(struct Box (f : (-> Int Int)))

;@axiom:pure
(fn (runner b) ((b.f) 7))   ; accepted, ran, wrote to stdout
```

`runner` compiled clean and `symbols` printed `#pure` with no
`#effects=` beside it. The same shape under `;@axiom:effect(io)` drew
a **false** `claim unsupported: missing IO`.

The mark is deliberately conservative. An `if` or `match` head whose
arms are all named functions *is* attributed by the reference-site
rule and is still called incomplete, because the walk did not resolve
the call; so is a lambda's own parameter, and so is a `let` bound to
the result of a call that returned a closure the walk had already
walked. Being loud about a limit is the same choice `AX3021` makes,
and for the same reason: the alternative is a silence that reads as an
answer.

Six files in the 269 swept by `scripts/check-diagnostics.sh` carry a
mark - `tests/stdlib/140-function-values.ax`,
`tests/stdlib/280-function-application.ax`,
`tests/selfhost/530-fn-in-ctor.ax`, `590-lambda-nested.ax`,
`950-multi-param-lambda.ax` and `999-placeholder-under-arrow.ax`, ten
marks between them. All six are the corpus's own function-value tests,
none makes a claim, and no function in `self_host/` or `stdlib/` is
marked at all.

Getting there needed one thing removed rather than added. `findFnEnt`
answers 0 for every form parsed as an application without being a
function - `cast` first of all, and every struct and data constructor
with it - and that branch used to run the escape walk, which marked a
parameter effect-transparent for appearing inside a `cast`.
`memSetWord` carried `#effect-params=value` on the strength of `(cast
Int value)` alone, and it does not call `value`. That was not only
imprecise: a transparent parameter *suppresses* the missing-effect half
of `AX3010`, so the wrong mark bought silence. With it left in, marking
unfollowable arguments put the sentinel on 7,768 functions; with it
gone, ten.

The remaining honest gap: passing an effect-polymorphic function
itself as a callback does not instantiate the callee's marks
(higher-rank flows).

### The Unsafe Layer

A signature whose result names a type variable that **no parameter
mentions** is not parametric polymorphism:

```scheme
(:: conjure (-> Int a))
```

The caller chooses what `a` is, nothing witnesses the choice, and the
callee cannot have produced a value of it. `forall a. Int -> a` is
inhabited only by non-termination in a sound system; here it is
inhabited by a machine word, so the signature is an unchecked coercion
wearing a polymorphic spelling. Measured: `(strWrap (conjure 42) 8)`
type-checks `OK` and the binary exits **139** - 42 dereferenced as a
String pointer. The same shape reaches through `vecGet`, because a
`Vec` carries no element type, which is how a `Vec` holding an `Int`
reads back as a `String`.

Such a declaration draws `AX3040` unless it is tagged `;@axiom:raw`.
The tag is **not permission and does not make the read safe**. What it
buys is that the unsafe layer is finite and can be asked about:

```
axiom symbols FILE --diagnostic-format ai | grep '#raw'
```

**No declaration in this repository carries it any more.** Fourteen did
when the tag was introduced on 2026-08-23; all fourteen were migrated
the same day, and the tag remains as the guard against a fifteenth.

**The obvious repair was wrong, and the compiler would not have told
you.** Making all fourteen concrete produces 1,223 type errors, and
writing `(cast T ...)` at each site fixes every one of them - while
classifying that value's evidence 0, which suppresses its retain where
the parameter is a type variable and its release where it is concrete.
Measured both ways in [memory-model.md](memory-model.md) MM-LIFE-2e.
That would have traded a type-system unsoundness for a memory-model
regression, 1,223 times, in silence.

The vehicle that works is a **typed accessor**: the cast goes at a
RETURN, inside a function whose declared type carries the truth, so
callers see that type and the evidence word is computed from it
(MM-LIFE-2f). Each raw reader was split into the word and a view -
`nodeA`/`nodeAName`, `memGetWord`/`memGetWordStr`,
`vecGet`/`vecGetStr` - and the call sites renamed, driven by the
compiler's own `AX3004`s and verified one flip at a time.

Two readers got `(Option String)` instead, because a view has to
re-derive its value and they cannot: `replReadLine` reads stdin and
`readModuleSrc` reads a file. The hot readers deliberately did not -
`nodeModule` and `modOf` are asked per declaration and per name, and
boxing there would cost more than the question is worth.

What this does NOT fix: a `Vec` still carries no element type, so
`vecGetStr` is an unchecked reading of a word rather than a checked
one. The difference is that it is now *said*, at the call, in one
word - where before the type system agreed silently that a `Vec`
holding an `Int` could be read as a `String`.

Ordinary parametric polymorphism is unaffected. `(:: witnessed (-> a
a))` is silent, because the argument supplies the value and witnesses
the choice.

### Built-in Effects

| Effect | Meaning |
|---|---|
| `IO` | Reaches the outside world through a `__syscallN` |
| `Pure` | No side effects |
| `Alloc` | Heap allocation: a call reaching the `__alloc` primitive — every `Vec`/`Map`/`Str` growth, every `memAlloc`. The `(alloc T)` keyword contributes it too and was the only contributor until 2026-08-23, which had it exactly inverted (`memory-model.md` MM-EXEC-9a) |
| `Mut` | Mutable heap state: `(set base.field v)`. Plain `set` on a `mut` local is deliberately *not* `Mut` - a local's mutation is invisible outside its function, while a field store is visible through every alias of the value |
| `Div` | Divergence (infinite loops). **Spellable, never inferred** — nothing in the compiler produces it, so a `;@axiom:effect(div)` claim is always reported unsupported, even over a body that plainly does not terminate. Inferring it needs a termination analysis this compiler does not have; the cheapest sound rule (self-call or any `while`) marks 65% of the compiler divergent and is false on almost all of them |

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
an effect named after a built-in (`IO`, `Alloc`, ...) is **accepted**:
nothing refuses the shadowing.

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

`handle` plays two roles, decided per effect in its list, and it NAMES
a larger set than it DISCHARGES.

Naming is exhaustive and is checked: an effect the body performs that
the list omits is `AX3011`, an error. That is what makes the list a
description of the region rather than a wish, and it means a built-in
in the list is never an accident — the form does not compile without
it.

Discharging is narrower. For a *built-in* effect the handler
expression is not evaluated and the whole form lowers to its body, so
nothing intercepts anything: the syscall still runs, and the effect
still reaches the caller. Naming `IO` acknowledges it; it does not
remove it.

```scheme
; Names IO, which AX3011 requires. Does NOT discharge it: `IO` is still
; in this function's inferred set, and a `;@axiom:pure` claim on the
; enclosing function is contradicted.
(handle (println "hello") (IO) 0)
```

This is the rule the *declared*-effect section below already stated —
"the list documents, the declaration decides what dispatches" — and
until 2026-08-23 this section contradicted it and the compiler
implemented this one. A named built-in *was* subtracted, and the
erasure ran the wrong way in three shapes, all measured
(`tests/diagnostics/348-handle-discharge.ax`):

- a function could claim `;@axiom:pure`, acknowledge `IO` inside, be
  reported `#pure`, and write to stdout — while the only diagnostic
  landed on its honest caller, for truthfully declaring the I/O the
  callee had hidden;
- an inner `handle` subtracted before an outer `(Pure)` measured, so
  the one construct in the language that refuses to emit could be
  switched off by the code it was guarding;
- and it did not need anyone to be lying: `(Console IO)`, the spelling
  the section below documents, silently erased the I/O from an honest
  function, which AXSYM then reported as `#effects=Alloc`.

For a *declared* effect, `handle` installs its handler for the body's
dynamic extent - evidence-passing, tail-resumptive: an operation
performed anywhere in that extent (any call depth) invokes the
innermost installed handler in the operation's place, the handler's
return value is the operation's result, and execution continues.

```scheme
(handle
  (log "hi")            ; dispatches to the lambda below
  (Console)
  ; `cast String`: a handler parameter's type is a variable, and
  ; `println` is a macro over `show`, whose implementation is keyed on
  ; a type NAME (AX3025).
  (lambda (s) { (println (cast String s)) 0 }))
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
and the unhandled-operation trap included (`docs/memory-model.md`
MM-EXEC-10 is the measured probe).

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

Both halves matter, and until 2026-08-10 there was only one: a private declaration was *deleted* from the program by whatever imported it, which broke the module's own calls to it — and if the importing file happened to define the same name, those calls silently reached that definition instead. See the self-hosting record.

`macro` obeys `pub` like everything else since 2026-08-14: a macro without it is `AX3023` at the invocation, naming the module it belongs to, and a name list that asks for a private macro is refused at the import (`tests/diagnostics/485-qualified-private-macro.ax`, `tests/diagnostics/440-import-name-list.ax`). `effect` is the remaining exception and is exported unconditionally — an operation of an unmarked `effect` is callable from any importer, because an operation name carries no module.

### How Imports Work

- A dotted module path maps directly to a file path: `Math.Ops` resolves to `Math/Ops.ax`, looked up in the entry file's own directory first and then in the rest of the search path — the project's `axiom.pkg` dependencies, `$AXIOM_PATH`, and the standard library, in that order. The SUFFIX ladder is the outer loop, so a more target-specific file anywhere beats a less specific one nearer the entry file: a project's `Sys/Platform.ax` loses to the standard library's `Sys/Platform.darwin.ax` (measured 2026-08-25). [README § Standard library](../README.md#standard-library) states the whole order; `scripts/check-packages.sh` gates it.
- `(import Mod.Sub)` with no name list makes every `pub` top-level declaration visible.
- `(import Mod.Sub (a b))` makes only the named ones visible; the module's other `pub` names stay out of scope.
- An import's name list **is** checked, at the import: a name the module does not declare, or declares without `pub`, is `AX3023` on the import form itself and says which of the two it was (`tests/diagnostics/440-import-name-list.ax`).
- Imports are transitive (`A` imports `B` imports `C` brings `C`'s declarations into `A` too) and diamond-safe (two different modules both importing `C` merges `C` exactly once).
- Qualified access is supported: `Mod::name` resolves to `name` declared in `Mod`. Imported declarations still join the importing module's flat top-level namespace by default; use `Mod::name` to disambiguate when the same name exists in multiple modules.
- **Types resolve by module, not by import order** (2026-08-24). A `data`, `struct` or `type` name is not rewritten to `Mod$Name` the way a `fn` is, and the lookup used to take the first declaration in the merged list — so two modules that each declared a `Config` had one winner for the whole program, chosen by which `(import ...)` came first, and the loser's own bodies were compiled against the winner's field offsets at exit 0 with no diagnostic. A bare type name now means, in order: a declaration in the referencing module, then a module-less one (the entry file, or a builtin like `Option`), then the single module that declares it. A name two or more modules declare, referenced from a module that declares neither, is `AX3044` naming them. `Mod::Name` is **not** the escape — it does not parse in type position; narrow one of the imports with a name list, or rename one declaration.
- A module path that doesn't resolve to a real file is `AX5001`. Two of a project's declared dependencies providing one module is refused before compilation, naming both files and the manifest — see [README § Packages](../README.md#packages).

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

Templates may generate `fn`, `::`, `data`, `struct`, `type`, `effect`
and `impl` declarations and further macro invocations; an argument standing in a
name position must be a bare identifier; a macro is invocable from the
entry file and from a module over its own declarations, where the
template's own `pub` decides what leaves the module. Everything
outside that surface is refused loudly — `AX3027` at the invocation (`axiom explain
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

Macros match on the shape of their arguments and repeat a template
over a variable number of them, both since 2026-08-16. A rule-form
macro's parameters are PATTERNS — a binder, `_`, a literal matched by
value, or a parenthesised form of patterns — its rules are tried in
order with the first match winning, and its last element may repeat,
which is how a macro becomes variadic
(`tests/selfhost/392-macro-patterns.ax` 127,
`393-macro-ellipsis.ax` 63).

What they still cannot do: dispatch on an argument's *spelling* rather
than its shape — a literal identifier in a pattern needs two
identifiers spelled alike to be the same pattern only when they mean
the same binding, which is scope sets; and carry rules on the
expression form, which stays one parameter list and one template
because the two forms differ in what a template is. (`deriving (Eq)`
is refused outright — see Deriving Traits.)
The normative specification is [macro-system.md](macro-system.md);
[macro-system.md](macro-system.md) is the measured detail and the order the rest
is planned in.

---

## Printing and Formatting

Printing is **two macros and no per-type functions**. `println` and
`eprintln` come from `IO`; `format`, which answers a `String` instead
of writing one, comes from `Show` (and arrives with `IO`, which imports
it).

There is deliberately no newline-less `print`. A partial-line printer
exists in C-descended libraries because assembling a line out of pieces
was expensive, so you emitted the pieces instead; here the line is
assembled at compile time, so `(println "ok {name} in {ms:>4}ms")` is
one call and one syscall where four `print`s were four. For bytes with
no newline and no rendering there is `writeStr`, which is the
primitive and is also one call.

```scheme
(import IO)

;@axiom:effect(io)
(fn (main)
  (let ((name "world") (n 42) (pi 3.14159))
    {
      (println "Hello {name}")            ; Hello world
      (println "n={n} pi={pi:.2}")        ; n=42 pi=3.14
      (println n)                         ; 42
      (let ((row (format "{name:<10}{n:>5}")))
        (println "[{row}]"))              ; [world        42]
      0
    }))
```

### Holes

A hole names a binding **in scope at the call**. There is no argument
list and no positional `{}`: the name goes in the string.

```
{name}          render `name` through its `Show` instance
{name:SPEC}     render it the way SPEC says
{{   }}         a literal brace
```

`name` may be anything the language can name, because the hole uses
the lexer's own identifier charset — `{empty-list}` works.

### Specifiers

```
SPEC := [align] ['0'] [width] ['.' precision] [type]
align := '<' (left) | '^' (centre) | '>' (right, the default)
type  := 'x' (lowercase hex) | 'X' (uppercase hex)
```

| Written | Means | Expands to |
|---|---|---|
| `{n}` | the value's own rendering | `(show n)` |
| `{n:x}` | hexadecimal | `(fmtHex n)` |
| `{x:.2}` | two decimal places | `(fmtFloatPrec x 2)` |
| `{n:>8}` | right-aligned in 8 columns | `(fmtPadLeft (show n) 8)` |
| `{s:<8}` | left-aligned | `(fmtPadRight (show s) 8)` |
| `{s:^8}` | centred | `(fmtPadCenter (show s) 8)` |
| `{n:04}` | zero-padded, sign kept in front | `(fmtPadZerosLeft (show n) 4)` |
| `{x:>10.2}` | both, composed | `(fmtPadLeft (fmtFloatPrec x 2) 10)` |

**Everything above happens at compile time.** A specifier is not
interpreted while the program runs — it *chooses a function*, once,
during macro expansion. `(println "hi")` compiles to a single
`writeStr` of a single static constant whose bytes already end in a
newline; nothing parses a format string at run time, because no format
string survives to run time.

### Both halves are checked

- **Shape** is the expander's: an unclosed `{`, a stray `}`, an empty
  `{}`, or a malformed specifier is `AX3031`, with the caret inside
  the string on the offending byte.
- **Type** is the checker's: a specifier picks a function with a type,
  so `{s:.2}` on a `String` is `AX3004` on `fmtFloatPrec`'s `Float`
  parameter. An unbound hole is `AX3001`; a type with no `Show`
  instance is `AX3025`.

### Rendering your own types

`show` is an ordinary trait method, so a type becomes interpolable by
implementing it. `Pre`'s `deriveShow` writes the function half:

```scheme
(import IO)
(import Pre)

(data Colour (Red) (Green) (Blue))
(deriveShow Colour)                       ; gives showColour : Colour -> String

(impl (Show Colour) where
  ((show (lambda (v) (showColour v)))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((c (Green)))
    { (println "the colour is {c}")       ; the colour is Green
      0 }))
```

### When the type is not known

Dispatch is on the **static** type, so a value whose type the compiler
cannot name selects no instance and is `AX3025`. Two shapes do this:

```scheme
(println (vecGet v 0))                    ; AX3025: vecGet answers `a`
(println (handle (ask 3 4) (Ask) h))      ; AX3025: an effect result
```

Name the type and both work — which is exactly the information the old
`printlnInt` carried in its name:

```scheme
(println (cast Int (vecGet v 0)))
```

### Migrating from the old surface

`IO` used to export a function per type. It no longer does.

| Was | Now |
|---|---|
| `(println s)` where `s : String` | unchanged — `Show`'s `String` instance is the identity |
| `(printlnInt n)` | `(println n)` |
| `(printInt n)` | `(println n)`, or `(writeStr stdout (format "{n}"))` to keep the line open |
| `(println (fmtInt n))` | `(println n)` |
| `(println (fmtHex n))` | `(println "{n:x}")` |
| `(println (fmtPadLeft (fmtInt n) 8))` | `(println "{n:>8}")` |
| `(println (fmtFloatPrec x 2))` | `(println "{x:.2}")` |
| `(println (strConcat "n=" (fmtInt n)))` | `(println "n={n}")` |
| `(print "a") (print b) (println c)` | `(println "a{b}{c}")` — one call, one syscall |
| `(print s)` (no newline wanted) | `(writeStr stdout s)` |
| `(println (vecGet v 0))` | `(println (cast Int (vecGet v 0)))` |
| a literal containing `{` or `}` | double it: `{{`, `}}` |

`printlnLit` is unchanged: it takes an address of NUL-terminated
bytes, which is not a type-rendering question. (`printLit`, the
newline-less form, is private to `IO` — calling it is `AX3023`.)

---

## Memory Primitives

The standard library is built on these low-level primitives, and so is any code that needs to talk to the machine directly. They are the layer where the type system stops — every argument and result is an `Int`.

| Primitive | Meaning |
|---|---|
| `(__syscall0 n)` ... `(__syscall6 n a1 ... a6)` | Raw syscall |
| `(__load8 base i)` / `(__store8 base i v)` | Byte at `base + i` |
| `(__load64 base i)` / `(__store64 base i v)` | Machine word at `base + i * 8` |
| `(__alloc bytes)` | Address of `bytes` fresh zeroed bytes |
| `(__retain h)` / `(__release h)` | Take or hand back a share of the counted block at `h` |
| `(__retainref v)` | Take a share of `v` **iff `v` is a reference** — decided from the call's type, so an `Int` argument emits nothing. The store that hides a value behind a `cast Int` uses this |
| `(__addr "literal")` | Address of a string literal's bytes |

Syscall numbers are not built into the compiler — they live in `stdlib/Sys/Platform.<os>[-<arch>].ax`, and the module resolver picks the file matching `--target`.

### Allocation

```scheme
(:: memAlloc (-> Int Int))
(fn (memAlloc bytes)
  (__alloc bytes))
```

Memory comes from the backend's `mmap`-backed bump allocator. There is no `free` to call, and there is no wait for process exit either: every heap block carries a reference count, and a block whose count reaches zero is walked and re-issued from a size class (`docs/memory-model.md` MM-LIFE-2b/2c, `tests/stdlib/359-arc-str-bytes.ax`). Defining `axiom_alloc` yourself does **not** replace the allocator: the name is refused (`AX3026`) — the override seam does not exist. Before that refusal the program passed `check` and failed in `opt` with `invalid redefinition of function 'axiom_alloc'` (`docs/memory-model.md` MM-ALLOC-8).

---

## Standard Library

Axiom ships a standard library written **in Axiom**. It reaches the operating system through raw syscalls, not through C, so a program that links nothing else contains no call to libc — `scripts/check-freestanding.sh` is the gate on that, and an `extern` block linking a Rust crate is the deliberate exception ([ffi.md](ffi.md) §15).

### Modules at a Glance

| Module | Provides |
|---|---|
| `Pre` | `when`, `unless`, `cond2`, `cond3` (conditional macros), `deriveEq`, `deriveShow`, `deriveArity`, `showOr` |
| `Mem` | `memAlloc`, `memAllocMapped`, `memMarkArray`/`memMarkLeaf`, `memCopy`, `memSet`, `memCmp`, `memGetByte`/`memPutByte`, `memGetWord`/`memSetWord` |
| `Str` | `strFromLit`, `strAlloc`, `strLen`, `strByte`, `strCmp`, `strEq`, `strSlice`, `strDup`, `strConcat`, `strFindByte`, `strStartsWith`, `strCStr` |
| `Utf8` | `utf8Len`, `utf8CharAt`, `utf8DecodeAt`, `utf8FromChar`, `utf8Next`, `utf8Offset`, `utf8Slice`, `utf8Width`, `utf8SeqLen`, `utf8IsCont`, `utf8Valid` (the character view of a `Str`) |
| `Vec` | `vecNew`, `vecNewRef`, `vecWithCapacity`, `vecWithCapacityRef`, `vecFree`, `vecPush`, `vecPop`, `vecGet`, `vecSet`, `vecLen`, `vecCap`, `vecLast`, `vecClear` |
| `Map` | `mapNew`, `mapNewRefVals`, `mapWithCapacity`, `mapWithCapacityRefVals`, `mapFree`, `mapHas`, `mapGet`, `mapInsert`, `mapRemove`, `mapLen`, `mapCap`, `mapUsed` (open-addressing `Int→Int` hash map) |
| `Fmt` | `fmtInt`, `fmtHex`, `fmtHexUpper`, `fmtFloat`, `fmtFloatPrec`, `fmtPadLeft`, `fmtPadRight`, `fmtPadCenter`, `fmtPadZerosLeft`, `fmtIntWidth` — the functions a format specifier selects |
| `Show` | the `Show` trait and its `show` method (`Int`, `String`, `Bool`, `Float`), and the `format` macro |
| `Err` | `Result` (`Ok`/`Err`), the `Error` record, `isOk`/`isErr`, `okOr`, `unwrapOr`, `mapOk`/`mapErr`, `andThen`, `try!`, `toOption`, `withContext`, and the checked arithmetic `divChecked`, `remChecked`, `shlChecked`, `shrChecked` ([error-model.md](error-model.md) is the specification) |
| `Intern` | `internNew`, `internFree`, `internIntern`, `internFind`, `internLookup`, `internCount` (string interner) |
| `Sys` | `sysWriteFd`, `sysReadFd`, `sysWriteAllFd`, `sysOpenPath`, `sysCloseFd`, `sysExitWith`, `sysFailed`, `sysErrno`, `stdin`/`stdout`/`stderr`; the filesystem (below); and the process layer `sysSpawn`, `sysRun`, `sysRunPath`, `sysWaitPid`, `sysEnv`, `sysArgc`, `sysArg`, `sysGetPid`, `sysNowMicros` |
| `Path` | `pathDir`, `pathBase`, `pathExt`, `pathStem`, `pathJoin`, `pathReplaceExt`, `pathWithSlash`, `pathIsAbsolute`, `pathLastSlash`, `pathExtIndex` — decisions about bytes, no syscalls |
| `IO` | `println`, `eprintln` (**macros** — see Printing and Formatting), `writeStr`, `printlnLit`, `readFileLit`, `exit`, `die`; and the filesystem (below) |
| `Ffi` | `ffiHandleNew`/`ffiHandlePtr`/`ffiHandleClose`, the out-cell (`ffiCellNew`, `ffiCellWord`, `ffiCellFree`) and the `Vec` conversions a generated binding needs ([ffi.md](ffi.md)) |
| `Json` | `jsonParse`, `jsonWrite`, and the constructors and accessors between them — written for JSON-RPC |
| `Rpc` | the LSP base protocol's framing over a file descriptor: `rpcRead`, `rpcWrite`, and the reader `rdNew`/`rdBuf`/`rdFilled` |
| `Job` | `jobRunAll` — a bounded pool of child processes, joined in submit order |
| `Test` | `assertEq`, `assertNe`, `assertStrEq`, `assertTrue`, `assertFalse`, `testFail`, and the `Assert` effect a failed assertion performs — what `axiom test` discovers and isolates ([error-model.md](error-model.md) ERR-REC-6) |
| `Agent.Tags` | `axsymParse`, `axsymLine`, and the accessors over one parsed line: `symTag`, `symHasTag`, `symEffects`, `symDerivedPure`, `symAgentTag`, `symHasAgentTag`. Reads the AXSYM stream rather than the compiler's internals ([agent-harness.md](agent-harness.md) §3.2) |

### The Filesystem

Two layers over the same syscalls. `Sys` takes a raw NUL-terminated
`char*` because it hands one straight to the kernel; `IO` takes a
`Str`, copies it so a `strSlice` cannot be handed on unterminated, and
is the one to reach for.

| Question | `IO` (takes a `Str`) | `Sys` (takes a `char*`) |
|---|---|---|
| read a whole file | `readFile` | `sysReadFile` |
| write one, truncating | `writeFile` | `sysWriteFile` |
| add to the end of one | `appendFile` | `sysAppendFile` |
| duplicate one | `copyFile` | — |
| move or rename | `renamePath` | `sysRename` |
| delete a file | `removeFile` | `sysUnlink` |
| is it there? | `fileExists` | `sysFileExists` |
| is it a directory? | `isDir` | `sysIsDir` |
| how big? | `fileSize` | `sysFileSize` |
| *why* can it not be read? | `readErrno` | `sysReadErrno` |
| make a directory | `makeDir` | `sysMkdir` |
| make it and its parents | `makeDirAll` | — |
| remove an empty directory | `removeDir` | `sysRmdir` |
| what is in a directory? | `listDir` | `sysReadDir` |
| where am I? | `cwd` | `sysGetCwd` |

Every call answers a value or a negative errno; nothing throws.

Three things are worth knowing before using them.

**`readFile` answers `""` for four different situations** — a missing
file, an empty file, a directory, and a file that could not be opened.
`readErrno` is the discriminator: `0` readable, `2` missing, `13` not
permitted, `21` a directory.

**`listDir` is sorted and drops `.` and `..`.** `readdir` order is the
filesystem's and differs between machines, so a program that walks a
directory is not reproducible unless something sorts.
`Sys.sysReadDir` is the unsorted primitive, and it keeps the two dot
entries — which is what lets its empty answer mean *failure* and
nothing else, since a readable directory always holds them.

**There is no `stat`, and no `chdir`.** `struct stat`'s layout differs
on all four targets, so the questions it answers are `open`, `read`
and `lseek` here instead. `chdir` exists on every target and is absent
because nothing calls it: a process that changes directory has
invalidated every relative path anything else is holding. See
the self-hosting record.

```scheme
(import IO)
(import Path)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (makeDirAll "build/out")
    (writeFile (pathJoin "build/out" "notes.txt") "first\n")
    (appendFile "build/out/notes.txt" "second\n")
    (println (readFile "build/out/notes.txt"))
    (println (pathExt "build/out/notes.txt"))       ; .txt
    (println (pathStem "build/out/notes.txt"))      ; notes
    (println (pathReplaceExt "build/out/notes.txt" ".md"))
    (removeFile "build/out/notes.txt")
    (removeDir "build/out")
    (removeDir "build")
    0
  })
```

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
(fn (legacyFn x) x)

;@axiom:owned(arena=frame)
(fn (ownedFn x) x)
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

**Parsed only.** `consume` is a parse-time identity that keeps the `Linear` wrapper; consuming twice is accepted, and the form itself reclaims nothing. What reclaims is the reference counting every heap block carries: a block whose count reaches zero is freed and re-issued, with nothing written in the source (`docs/memory-model.md` MM-LIFE-2b/2c). `__axiom_arena_mark` / `__axiom_arena_reset_keeping` remain the explicit fallback for a program that wants to choose the point.

---

## Removed Features

These features existed in earlier versions of Axiom but have been removed. Each word keeps a grammar rule whose only job is to report `AX2004` and say what to write instead.

### `union` — Removed

C interoperability is no longer a goal, and an untagged union has no meaning under linear types. Use `data` for a tagged sum or `struct` for a product.

### `region` — Removed

Reclamation is never written by hand as a region annotation — the chosen automatic strategy is reference counting, and the region-inference sketch that originally justified this sentence is withdrawn (`docs/memory-model.md` MM-LIFE-2a, §3.4). Delete the `region` wrapper and keep its body.

### `foreign` — Removed

`foreign` never worked: it emitted a call to a symbol the module never declared, so a program that used one passed `check` and then failed inside `opt` or the linker. It was refused rather than repaired, and the FFI that replaced it is the [`extern` block](#extern--binding-rust) — a different feature with a different contract, not this one renamed ([ffi.md](ffi.md)). For the kernel, reach the standard library instead, which is written in Axiom over `__syscall0`-`__syscall6` and needs no FFI at all.

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
| `:help` | `:h` | Show all commands |
| `:quit` | `:q`, `:exit` | Exit the REPL |
| `:type <expr>` | `:t <expr>` | Show the type of an expression |
| `:load <file>` | `:l <file>` | Load a file into the REPL |
| `:reset` | `:r` | Clear all definitions |
| `:defs` | `:d` | Show all definitions in scope |
| `:llvm <expr>` | — | Show the generated LLVM IR |
| `:time <expr>` | — | Time how long an expression takes |

### Example Session

There is no prompt: the loop reads a line, answers it, and reads the
next one, so a piped session and a typed one produce the same bytes.

```
$ axiom repl
axiom (self-hosted) 0.2.0 - Axiom REPL
Type :help for commands, :quit to exit

(:: add (-> Int Int Int))
OK: add defined
(define (add x y) (+ x y))
OK: add defined
(add 3 4)
type : Int
result 7
:type (add 3 4)
(add 3 4) : Int
```

The REPL accumulates definitions — functions you define persist across
inputs. Nothing else persists: there is no line editing, no arrow-key
history and no history file, because the loop reads plain lines rather
than driving a terminal. `:help`'s own text still advertises `?` and
arrow keys; only a line beginning with `:` reaches the command
dispatcher, so `?` is read as an expression and answered with a parse
error. The editor-grade interface is the LSP's business
(the self-hosting record).

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
# Default: an mmap-backed bump allocator, with per-block reference
# counts since 2026-08-15 - a block whose count reaches zero is walked
# and re-issued from a size class, so a dead value is freed with no
# reclamation written in the source.
axiom build --input source.ax --output program

```

The build is freestanding — it does not call libc.

There is no tracing collector. The retired Rust compiler had one behind
a `--gc` flag; it was not ported, and `--gc` is now refused by name
rather than silently ignored (see the self-hosting record). What
reclaims instead is reference counting: every heap block carries a
count and a shape word, and a thousand build-and-drop iterations move
the allocator's bump by 384 bytes where they moved it by 80,304
(`tests/stdlib/359-arc-str-bytes.ax`). Every ownership event
[memory-model.md](memory-model.md) MM-LIFE-2c specifies now emits:
events 2 and 3, the two that needed an escape analysis, shipped on
2026-08-21 (`tests/stdlib/372-arc-owned-results.ax`), so peak memory
tracks live data rather than total allocation. Where a program wants
reclamation at a point of its own choosing, `__axiom_arena_mark`,
`__axiom_arena_reset` and `__axiom_arena_reset_keeping` roll the
allocator's waterline back — which is how the language server holds
flat memory across an editing session.

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

**A container can own what it holds, and be freed.** Since 2026-08-24
each of the three has an owning constructor beside its ordinary one -
`vecNewRef`, `mapNewRefVals`, and `internNew`, which is owning outright
because an interner has no other use - and a `Free` that hands the
whole structure back:

```axiom
(let ((v vecNewRef))
  {
    (vecPush v (strDup "hello"))   ; the vector takes a share
    (vecFree v)                    ; header, data block, and the string
  })
```

The two constructors differ in ONE WORD at allocation: the data block
of a `vecNewRef` carries the **array form** (`Mem.memMarkArray`), which
says every payload word of it is a handle, so releasing the block
releases them all. `vecNew`'s data block is a leaf and makes no claim
about its contents. For the `Int`s a compiler's vectors are full of that
is exactly right and free - the store emits no instruction at all. For a
REFERENCE it is not a borrow: the store still takes a share
(`memory-model.md` `MM-LIFE-2g`) and nothing hands it back, so the
element is immortal. Closing that is what the owning constructor is
for. Growth,
overwriting and removal all hand back what they displace, and `vecPop`
zeroes the slot it vacates - the popped value's share becomes the
caller's. `memory-model.md` `MM-LIFE-2h` states the encoding and the two
obligations that come with it; `MM-LIFE-2i` is the acceptance property
and its measurement.

A fourth form turns a mark into a **recovery point**.
`(__axiom_recover mark thunk)` runs `thunk` — a `(-> Int Int)`, called
with `0` — and answers what it answered. If instead the program runs out
of memory, performs an effect with no handler in dynamic extent, or
divides by zero anywhere inside that extent, the arming call answers
**70**, **71** or **72** and the program carries on; outside a recovery
point those three still write their sentence to fd 2 and exit, exactly
as before. Points nest and an abort takes the innermost armed one.

The abort restores the stack pointer, resets the arena to `mark`, and
restores every evidence slot — that last one is why this is sound where
calling `__axiom_arena_reset` by hand across a live `handle` is not
(`memory-model.md` `MM-ALLOC-16b`, `MM-ALLOC-17`). Nothing runs on the
way out: there are no destructors to call and no landing pads. It is not
a `catch` and cannot contain a memory-safety fault — a SIGSEGV is not a
trap and asks nothing. `error-model.md` `ERR-REC-6` states the whole
contract; `tests/stdlib/403-recover-div.ax` is the smallest example.

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

# Also print each function's resolved call edges as `#calls=`
axiom symbols source.ax --diagnostic-format=ai --calls
```

`--calls` prints the graph the effect fixpoint already walks: the edges
`inferEffects` resolved in order to derive each `#effects=` row. It is
opt-in because it would otherwise appear on every row of every symbols
golden. `scripts/check-agent-calls.sh` gates the relationship between
the two keys - no callee's effect escapes its caller, every inferred
effect has an edge accounting for it, and every IO reaches a syscall or
an `extern`. See [agent-harness.md](agent-harness.md) §3.5.

The default rendering is an aligned human table. `--diagnostic-format=ai`
gives AXSYM instead, one line per symbol; `--diagnostic-format=json`
has no symbol renderer, says so on the first line, and falls back to
AXSYM.

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
Source (.ax) → Lexer → Parser → Imports → Macro Expansion → Type Checker → LLVM IR → opt → llc → cc → Executable
```

There is no separate IR stage: `codegen.ax` writes LLVM IR text
straight from the checked AST. The retired Rust compiler had a
three-address IR crate between the two; it was not ported
(the self-hosting record).

### Compiler Structure

The compiler is written in Axiom, in `self_host/`.

| Module | Purpose |
|---|---|
| `core.ax` | Tokens and spans |
| `lexer.ax` | Tokenizer |
| `parser.ax` | S-expression parser and AST |
| `expand.ax` | Macro expansion, hygiene, expansion diagnostics |
| `typecheck.ax` | Name resolution, type checking, effects, AXTAG validation |
| `namespace.ax` | The declaration namespace: how a bare name reaches a definition, and which names may leave a module |
| `codegen.ax` | Import resolution, name mangling, LLVM emission |
| `diag.ax` | Diagnostics, AXDL/JSON rendering, source maps |
| `render.ax` | The human diagnostic renderer |
| `style.ax` | ANSI colour for the human renderer, and for nothing else |
| `driver.ax` | `build`: `opt`, `llc`, `cc`, and the crate/archive linking the FFI needs |
| `rustbind.ax` | The Rust binding `--emit-rust-binding` writes for an Axiom archive ([ffi.md](ffi.md) §10) |
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

Axiom has `while` with `mut` and `set` (see [Mutable Bindings and `while`](#mutable-bindings-and-while)), used 316 times in the compiler's own sources (`grep -o '(while ' self_host/*.ax | wc -l`). Iteration may also be written as recursion. A **self** tail call runs in constant stack at every `--opt` level, including 0 — the loop is built by Axiom's own codegen, not by LLVM (`docs/memory-model.md` MM-EXEC-6b). What still needs `--opt 1` (the default) and above is **mutual** tail recursion and a tail call sitting in a `let` body, which only LLVM's passes flatten (MM-EXEC-6c):

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
  (let ((total (+ 1 2)))
    {
      (println 42)
      (println "sum={total}")
      0
    }))
```

---

## Further Reading

- [The Memory Model](memory-model.md) — the normative specification: representation, allocation, mutation, lifetimes; reference counting is the chosen reclamation strategy
- [The Macro System](macro-system.md) — the normative specification: expansion, hygiene, budgets, and what `derive` will be built on
- [Macros](macro-system.md) — what expansion guarantees, what it does not, and the probes behind each claim
- [The Error Model](error-model.md) — `Result`, the `Error` record, and `stdlib/Err.ax`
- [The Rust FFI](ffi.md) — `extern` blocks, `--emit-staticlib`, and what crosses the boundary
- [Diagnostics & Agent Notations](diagnostics.md) — AXDL, AXSYM, NID, AXTAG reference
- [Contributing](../CONTRIBUTING.md) — the gates, the conventions, and the two documents retired into history
- [README](../README.md) — project overview and installation guide