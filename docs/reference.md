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

`axiom fmt` prints by the same rule since 2026-08-28: a keyword in
parameter, `let` binder, pattern, argument or effect-name position is
printed as the identifier it is (`tests/fmt/parity/190-keyword-param.axp`
through `195-effect-keyword-atom.axp`, and `070-keyword-in-expr.axp`,
which pinned the refusal until then), and the formatter refuses exactly
the heads the parser refuses - `consume` and `begin`, `AX2004`
(`196-consume-head-refused.axp`, `197-begin-head-refused.axp`) - plus
`mut` at a `let` binding's head, which is the marker and not a name
(`194-mut-binder-head-refused.axp`, `AX2001` from `check` too). Until
then the formatter reserved every word in this table in every position,
which was the retired Rust compiler's lexer rule, and refused
`(fn (g data) data)` while `check` accepted it.

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
| `linear` | **Reserved** — removed 2026-08-25, reports `AX2004` |
| `consume` | **Reserved** — removed 2026-08-25, reports `AX2004` |
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

**The `:` is not optional.** It is what makes the form a field
declaration at all — the grammar's own note is that a declaration and
a construction "only become visible at the `:`" — so `(x Int)` is not
a shorter spelling of `(x : Int)`. It used to be accepted anyway, with
the written type skipped and the field left at the empty type
variable, and the consequence was not cosmetic: `fldClass` cannot
classify a variable, so the field was left out of the block's
reference map and out of `MM-LIFE-2c` event 5, and a value stored into
it was released by its own owner while the field still pointed at the
block — a use-after-free out of a program `check` accepted, measured
at exit 139. It is now `AX3056`, an error, at the field's name, on all
three spellings that reach the empty variable: no `:`, a `:` whose
type is not a type, and a bare `(x)`
(`tests/diagnostics/388-struct-field-untyped.ax`).

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
what it inferred. A refuted claim is an **error** (`AX3010`); one the
walk was not in a position to check is a warning (`AX3037`). Effects do
not appear in function types. Untagged functions ARE policed: silence
is the claim "performs no IO", and a body performing IO under it is
`AX3042`, an error. Only `IO` is REQUIRED - `Alloc` and `Mut` are
ambient, inferred and reported but never demanded, because 1,664 of
the 2,095 effectful functions in this repository perform exactly those
two. They are still DECLARABLE, and checked when declared:
`;@axiom:effect(mut)` over a body that writes a field is accepted, and
over one that does not it is `AX3010`. The same holds for a custom
effect. What is special about `IO` is that its absence is itself a
claim. `axiom symbols --diagnostic-format
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

#### Definite and possible

The opposite departure is an effect the body MAY perform without the
walk being able to say it does, and it is recorded **per effect**, not
per row. Two shapes produce it:

| shape | example |
|---|---|
| a bare arrow-typed name outside argument position | `(fn (handoff k) shout)` - `shout` is handed back, not called |
| a trait method with more than one implementation | `(show x)` under four `impl`s - dispatch picks one, the walk cannot say which |

Every effect the referent's row carries arrives as *possible*: the
body may perform it, through whoever calls the value or whichever
implementation dispatch selects. An effect the body reaches by a call
is *definite*. The two spellings of one effect can both be present -
a body that calls `shout` and also names it - and each consumer reads
the half it is entitled to:

- `AX3042` and the *contradicted* arm of `AX3010` read the definite
  half. An untagged function whose row holds IO only as possible is
  not accused; a `;@axiom:pure` over it draws `AX3037`, cannot be
  checked, exactly as over a lower bound. A definite IO beside a
  possible `Alloc` is accused: until 2026-08-29 one row-global marker
  excused the whole row, so every untagged function one hop above a
  `println` with a `{hole}` compiled clean and printed - the hole goes
  through `show`'s four implementations, and the excuse for their
  `Alloc` was excusing the `writeStr`.
- `AX3011`, the *missing* arm of `AX3010` and `restrict(...)` read the
  union. A `handle` list must name what the body may reach, and a
  claimed effect the body may perform is not missing.
- `symbols` prints the union as `#effects=`, and when some member is
  possible and not definite adds `#effects-overapprox` with
  `#effects-possible=A,B` naming which. `(fn (handoff k) shout)`
  renders `#effects=IO #effects-overapprox #effects-possible=IO`; a
  function that prints `"n={n}"` renders `#effects=Alloc,IO,Mut` with
  no admission, because everything `show` can contribute is also
  definite there.

One shape is a lower bound wearing an upper bound's clothes and is
recorded as the lower bound it is: a call that supplies more arguments
than the callee's own parameters - `((handoff 1) n)` - applies the
callee's *result*, a value the walk cannot follow, so the row is
`#effects-incomplete` as well.

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
could pick from is a subset of the ones unioned here. With one
implementation it is exact and every effect arrives definite; with
more than one, every effect any implementation contributes arrives
*possible* (above), because dispatch will pick one and the walk cannot
say which. Trait *defaults* need no special case: a missing method is
lowered through the same `traitImplName`, so it is an ordinary
declaration by the time the fixpoint runs.

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

A key one edit - or one change of case - from a key the compiler knows
- `pure`, `effect`, `raw`, `pre`, `post`, `restrict`, `unhandled` -
draws `AX3039`.
`;@axiom:pur` is not a purity claim, so nothing checks it as one, and a
body performing IO under it drew no `AX3010` at all: the tag read like
a guarantee and bought silence. A key the compiler knows is never a
near miss of another one it knows: `pre` is one insertion from `pure`,
and drew "did you mean `pure`?" until 2026-08-29. Knowing a key and
checking it are separate: `pre`, `post` and `restrict` are known ahead
of their checks, and until a key's check lands it is recorded and not
checked exactly as an unknown one is - what knowing it buys is that a
slip FROM it is reported. A key containing `:` is never reported,
because a namespaced key is deliberate by construction and its
distance from `pure` is not evidence about anything.

#### `restrict(...)` - what a declaration does NOT do

`;@axiom:restrict(name, name, ...)` is a claim that this declaration
does not do something, answered from analysis the checker already
performs and used to throw away. The list is CLOSED - a name outside
it is `AX3052`, an error, because inside the one key the compiler has
said it checks an unknown name is a claim and not metadata. Seven
restrictions are checked:

| Restriction | Decided by | Scope |
|---|---|---|
| `no-io` | `IO` is not in the effect row | transitive |
| `no-alloc` | `Alloc` is not in the effect row | transitive |
| `no-foreign` | no call-graph path reaches an `extern` item | transitive |
| `no-cast` | no `cast` head in this body | LOCAL |
| `no-cast:deep` | no `cast` head in this body or in any function it reaches | transitive, opt-in |
| `no-recursion` | no cycle in the call graph reachable from this declaration | transitive |
| `no-wrap` | no `+`, `-` or `*` head in this body | LOCAL |

Every transitive violation names its path. The checker walks the call
graph breadth-first from the claiming declaration to the nearest entry
where the effect *enters* - a syscall primitive, an `extern`, a builtin
whose row is seeded (`__argc`, `__alloc`), or a function whose row
carries the effect while no callee does, which is an `alloc` form or a
`handle` in that body and is said so - and renders the hops in the
resolved spellings `symbols --calls` prints, `Mod$name` and
`Trait#Type#method`, so a path cross-checks `#calls=` hop for hop:

```
E AX3049 ... "`parseConfig` claims `restrict(no-io)` and the body performs IO: parseConfig -> readSection -> IO$writeStr -> Sys$sysWriteAllFd -> Sys$sysWriteFd -> __syscall3"
```

`no-recursion` is a cycle, which is global by definition: a
depth-first walk over the same graph, and the diagnostic renders the
walk from the declaration to the repeated function -
`ping -> pong -> pang -> ping`, or `entry -> countdown -> countdown`
when the cycle is below the claim. A `while` loop is not recursion. It
pairs with `scripts/check-stack-depth.sh`, which measures the
compiler's stack need dynamically: a region under `no-recursion` is
one whose stack need is bounded by its depth rather than by its input,
the same property from the static side.

Three are transitive by construction and two are not, and the
difference is not a policy choice. `no-io` and `no-alloc` read the
effect row, which is already a transitive fixpoint (effects are
inferred transitively, above): a function calling an IO-performing
function *has* `IO` in its row, and a check reading the row has no
local reading available to it. `no-foreign` walks the call graph
`symbols --calls` prints, through every implementation of a trait
method the body calls, because the row cannot tell IO through a
syscall from IO through an `extern` and the graph can. `no-cast` is
lexical - a cast is an act the body that writes it performs, not a
property that propagates - so it is checked in this body only and
reported at the cast, and a callee's casts are the callee's claim to
make. Measured: 653 `(cast ` in `self_host/` and `stdlib/` against
3,196 `fn` declarations, so a transitive `no-cast` would refuse nearly
every program that reaches the standard library - which is why the
transitive reading is the separate, opt-in spelling `no-cast:deep`:
this body's casts at their spans, and the nearest reachable function
whose body casts, once, at the declaration, with the path. `sizeof`
and `alignof` are not casts here: they read a layout and reinterpret
nothing. `no-wrap` is lexical for the same reason: `+`, `-` and `*`
lower to plain `add`/`sub`/`mul` with no `nsw` (measured:
`self_host/codegen.ax` emits no `with.overflow` intrinsic and no
`nsw`/`nuw` flag anywhere), so a silent wraparound is an act the body
performs by writing the operator, reported at the operator itself.
`stdlib/Err.ax`'s `addChecked`, `subChecked` and `mulChecked` are the
checked alternative, every one `(-> Int Int (Result Int Error))`; a
body that switches to one pulls `Alloc` into its own effect row
(constructing the `Result` allocates), which is why `no-wrap` cannot
be satisfied together with `no-alloc` or `pure` by a body that needs
arithmetic - `docs/checked-arithmetic-design.md` is the design note.

A violation is `AX3049`, an **error** with no warning stage, for the
argument that made `AX3010` one: the tag is a claim the author wrote,
and a build shipping a false one publishes a guarantee the program
does not keep. Deleting the tag silences it and *withdraws* the claim;
an unrestricted function is never asked. A claim over a row the walk
could not close is `AX3051`, a warning in
`tests/diagnostics/severity.policy`, in exactly one direction per
reading: an effect ABSENT from a row that is a lower bound
(`#effects-incomplete`), or present only as a POSSIBLE effect
(`#effects-possible=`, the row's `#effects-overapprox` admission). An
effect present in a lower bound, or definite beside a possible one, is
a violation. `no-cast` and `no-wrap` never draw `AX3051`: both are
lexical and are checked whether or not a call resolved.

A restriction is a **per-declaration** claim. A tag attaches to the
declaration written below it, on the `::` or on the `fn`, and both
are read as one set; `symbols` renders it as `#restrict=no-io,no-alloc`
on the function's row. There is no module-wide form - measured, a tag
above `(import IO)` attaches to the import and to no function's row -
and module scope is deferred: a module-wide claim is written on each
declaration, where `symbols` shows it. A `restrict` tag is not an
effect claim and does not stand in for one: a restricted function
that performs IO without `effect(io)` draws `AX3042` like any other,
and `restrict(no-io)` over it draws `AX3049` as well.

#### `unhandled(trap)` - an effect whose unhandled operation is the design

`;@axiom:unhandled(trap)` is written above an `(effect ...)`
declaration and is the one AXTAG key that belongs to a declaration
other than a function or a signature. It says that reaching an
operation of this effect with no handler installed is a **deliberate
abort** rather than a missing handler, and it is what `AX3053` reads
before deciding whether to report one.

The value is exactly `trap`. Any other word leaves the check on -
`unhandled(abort)` buys no silence - which is the visible failure
rather than the quiet one, and a key one slip from `unhandled` draws
`AX3039` at the effect declaration like any other near miss. `symbols`
renders the tag on the effect's own row as `#unhandled=trap`, so a
policy gate over the AXSYM stream can list which effects a program
allows to abort.

`stdlib/Test.ax` carries it on `Assert`, and load-bearingly: `axiom
test` generates a `main` that runs each test inside its own recovery
point, so every assertion in a file under test reaches that `main`
undischarged, and the 71 an unhandled `assertFail` raises is exactly
how a failed assertion ends one test while the tests declared after it
still run. `stdlib/Fallible.ax` deliberately does NOT carry it - its
own header calls an unhandled operation "a programmer error and not a
record's fault" - so a batch loop that forgets its handler is named at
compile time.

`tests/diagnostics/371`-`379` pin each restriction with the controls
that keep it from being a blanket refusal - a callee that casts under
`no-cast`, a syscall under `no-foreign`, `Alloc,Mut` under `no-io` -
and the path through a trait impl, a module boundary, a seeded builtin,
a callback and an `alloc` form; 379 pins direct, mutual-at-depth-three
and through-a-trait-method recursion beside a four-deep chain and a
`while` loop that stay silent. `scripts/check-restrictions.sh` is the
gate: a restriction changes no emitted byte, a compiler whose
`checkRestricts` answers nothing goes red, and every restricted
declaration in the tree is on `tests/agent/restrictions.allow` with
the verdict the compiler gave it - the manifest is why `symbols` had
to union a signature's tags with the function's.

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

The same unsoundness reaches one level in, through a **function-typed
parameter**, where the callee still chooses the type:

```scheme
(:: apply1 (-> (-> a Int) Int))
(fn (apply1 f) (f (cast a 42)))
(apply1 strLen)
```

`a` is on a left side, so a rule reading SIDES calls it witnessed. It is
not: a parameter is a position the caller fills, and the left of an
arrow *inside* that parameter flips back to one the **callee** fills -
`apply1` has to make an `a` to call `f` at all, and nothing the caller
hands over says what one is. Until 2026-08-25 that drew nothing, checked
`OK` and exited **139**. The spine is split by variance now, so a
variable with a position the callee produces and none the caller
supplies is refused wherever it sits.

Two shapes follow from reading variance rather than sides.
`(-> (-> Int a) Int)` is **accepted** - the caller's own function
produces the `a`, which is the shape all ordinary higher-order code has,
and `(-> (-> a b) a b)` is witnessed on both counts. And the rule reads
the *signature*, so `(fn (apply1 f) 0)` - a body that never calls its
callback and therefore never fabricates anything - is refused too.

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
| `IO` | Reaches the outside world: a `__syscallN`, or `__argc`/`__argv` — reading the command line is reading input the process did not compute. The second half arrived 2026-08-25 (`memory-model.md` MM-EXEC-9a); before it, a `;@axiom:pure` function could read the command line and the claim was accepted |
| `Pure` | No side effects |
| `Alloc` | Heap **machinery**, not strictly allocation: a call reaching `__alloc` — every `Vec`/`Map`/`Str` growth, every `memAlloc` — and, since 2026-08-25, the three arena primitives, because a reset ends every block allocated since a mark. `handle` contributes it too, for installing evidence, which allocates nothing either. The `(alloc T)` keyword contributes it and was the only contributor until 2026-08-23, which had it exactly inverted (`memory-model.md` MM-EXEC-9a) |
| `Mut` | Mutable heap state: `(set base.field v)`, and the `__store8`/`__store64` primitives it lowers to — the second half arrived 2026-08-25 (`memory-model.md` MM-EXEC-9a), which is why `vecPush` and `mapInsert` carry it. Since 2026-08-29 the atomic writers `__atomic_store`/`__atomic_add`/`__atomic_cas` and `__fence` carry it too; `__atomic_load` deliberately does not, for `__load64`'s reason. Plain `set` on a `mut` local is deliberately *not* `Mut` - a local's mutation is invisible outside its function, while a field store is visible through every alias of the value |
| `Div` | Divergence (infinite loops). **Spellable, never inferred** — nothing in the compiler produces it, so a `;@axiom:effect(div)` claim is reported **unverifiable** (`AX3037`, a warning) rather than unsupported, even over a body that plainly does not terminate — a claim the compiler never looks for is a fact about the analysis, not the body. Inferring it needs a termination analysis this compiler does not have; the cheapest sound rule (self-call or any `while`) marks 65% of the compiler divergent and is false on almost all of them |

### Declaring an Effect Type

```scheme
(effect Console
  (log :: (-> String Int)))
```

An `effect` declaration introduces each operation as a callable name:
`(log "hi")` type-checks against the operation's signature and
dispatches at runtime through the innermost installed handler (below).
An operation must declare that signature: `(effect E (op))` is
`AX3055`, an error, because the handler check and the call's arity
check both stand on the arrow and on nothing else - without it the
operation registered as a wildcard of arity -1, and `(op 1 2 3)` on a
one-argument handler checked clean and SIGSEGVed.
Calling an operation performs the effect - `log`'s callers infer
`#effects=Console`, transitively, and `;@axiom:effect(console)` claims
validate against it (custom tag values match declarations
case-insensitively). Operation names join the ordinary value
namespace: colliding with a function in the same module is a duplicate
definition (`AX3006`, `tests/diagnostics/455-effect-op-collision.ax`),
cross-module collisions resolve by the one-bare-name rule,
and an operation cannot be used as a bare value - wrap it in a lambda
(`(lambda (x) (log x))`) where a function value is needed. Declaring
an effect named after a built-in (`IO`, `Pure`, `Alloc`, `Mut`, `Div`,
or the lowercase `alloc`) is **`AX3054`**, an error. It used to be
accepted, and the acceptance was useless in a way nothing reported: a
handle list resolves a built-in name to the BUILT-IN, so the custom
effect could never be handled - `(handle (emit 1) (IO) h)` around its
own call drew `AX3011 unhandled effect IO`, on the handle that names
it. Without a handle it was quieter and worse: an untagged `main`
performing the custom `IO` read `#effects=IO` with no `#effect=io` and
drew nothing, so the row said the program reached the outside world
when it did nothing of the kind.

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
  (lambda (s) { (println s) 0 }))   ; `s` is the `String` `log` declares
```

The handler is checked against the operation's declared arrow. A
lambda handler's parameters take the arrow's parameter types - `s`
above is a `String`, so `println` renders it with no `cast` - and its
result is held to the arrow's result; any other handler expression (a
top-level function passed bare, a closure a call built, a literal) is
checked as it is and its type compared. A handler that does not fit is
`AX3004`: the integer `0` for a `(-> Int Int)` operation, or a lambda
answering a `String` where the operation answers `Int`. Both checked
clean until 2026-08-29 and were memory-unsafe at run time - a SIGSEGV
when the dispatch applied `0`, a string's address plus one flowing into
the caller's arithmetic (`tests/diagnostics/386-handler-type.ax`). The
form's own type is its body's, so `(println (handle (ask 1) (Ask) h))`
selects `show` on the `Int` that `ask` declares; until the same day the
form answered the checker's wildcard, which is why every `handle` in the
tree was spelled `(cast Int (handle ..))`.

The rules that make this predictable:

- **Nesting shadows and restores.** The innermost handler wins while
  its `handle` is live; the previous one answers again when it exits.
- **A handler runs under the evidence at its installation.** An
  operation the handler itself performs dispatches *outward* to the
  next handler, never back into itself - which also matches the
  static story, since a handler's own effects propagate past its own
  `handle`.
- **No handler in dynamic extent is a trap.** The program exits with
  code 71 rather than continuing on a value nothing produced — and the
  compiler now says so where it can see it. A `handle` is the only
  construct that discharges a custom effect, so an effect still in
  `main`'s row when inference finishes is one nothing handled, and that
  is `AX3053`, a WARNING. Two approximations decide its severity rather
  than caution: a lambda's operations count where the lambda is
  *written*, so a worker bound before the `handle` that covers its call
  is reported although it runs (exit 20); and the `let` of a `handle`
  form is an opaque local, so a closure built inside a handle and called
  after it pops is *not* reported although it traps (exit 71). An error
  would refuse the first and accept the second.
  `;@axiom:unhandled(trap)` on the `effect` declaration says the trap is
  the design and silences it; see "AXTAG Keys" above.
- **A multi-argument operation's handler is a curried chain** -
  `(lambda (a) (lambda (b) ...))` - because application is one
  argument per step. A flat `(lambda (a b) ...)` is the same chain -
  the parser curries every multi-parameter lambda - and is checked
  against `(-> A B R)` exactly as the nested spelling is; this bullet
  said it was tuple-typed and refused, which was false, and
  `386-handler-type.ax` pins both spellings accepted.
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
{name}          render `name` with `show`
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
  parameter. An unbound hole is `AX3001`; a hole `show` has no
  rendering for — a type variable, a function value, a `Foreign`, or a
  `data`/`struct` holding one of those — is `AX3025`.

### Rendering your own types

`show` is a compiler-known head (0.3.8). The checker resolves it from
the argument's **static** type at the call — the way it already
resolves `==` on two `String`s into a content comparison — and a
`data` or `struct` needs no declaration to be interpolable: its
rendering is derived from the declaration, in the language's own
spelling.

```scheme
(import IO)

(data Colour (Red) (Green) (Blue))
(struct Point (x : Int) (y : Int))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((c (Green)) (p (Point 1 -2)))
    { (println "the colour is {c}")       ; the colour is Green
      (println p)                         ; {x = 1, y = -2}
      (println (Some p))                  ; (Some {x = 1, y = -2})
      0 }))
```

| Static type | Renders as |
|---|---|
| `Int`, `Float` | `fmtInt`, `fmtFloat` — `42`, `2.500000` |
| `Bool` | `true` / `false` |
| `Char` | the character literal, escaped as the lexer spells it — `'x'`, `'\n'`, `'é'` |
| `String` | its own bytes at top level, so `(println s)` means what it always meant; **quoted, with escapes**, inside a structure — `{name = "bo\"b"}` |
| a `data` value | a constructor application, a nullary constructor bare — `(Some 3)`, `(Cons 1 (Cons 2 Nil))`, `None`; a struct-variant constructor positionally, as it is written — `(Circle 7)` |
| a `struct` value | `{x = 1, y = 2}`, fields in declaration order |

Nesting composes — `(Wrap {x = 3, y = 4} Green (Some "hi"))` — and a
recursive type prints in full. A value that reaches *itself* (a struct
field is assignable, so `(set c.next (Some c))` builds one) prints
`...` at the back-edge instead of never returning:
`{v = 7, next = (Some ...)}`. One renderer is generated per concrete
type at its first use, as an ordinary function appended to the program
and checked and compiled like anything written; `symbols` does not
list it, because a generated name is not a symbol.
`tests/stdlib/450-show-builtin.ax` pins every row of the table.

**The rule, from 0.3.8: the compiler decides how a type prints, and a
program cannot override it.** The escape hatch is a function whose
result is interpolated:

```scheme
(:: showColour (-> Colour String))
(fn (showColour c)
  (match c ((Red) "red") ((Green) "green") ((Blue) "blue")))

(let ((s (showColour c)))
  (println "the colour is {s}"))          ; the colour is green
```

A written `(impl (Show T))` is still honoured in this release — at the
call it wins over the derived rendering, and `Pre`'s `deriveShow` still
writes the function half of one — but a value *inside* a structure is
always rendered structurally, and the trait is on its way out with the
rest of the trait machinery.

### When the type is not known

Rendering is by the **static** type, so a value whose type the compiler
cannot name has no rendering and is `AX3025`. One shape does this:

```scheme
(println (vecGet v 0))                    ; AX3025: vecGet answers `a`
```

A `handle` was the second until 2026-08-29 - `(println (handle (ask 3
4) (Ask) h))` drew the same code because the form answered the
checker's wildcard; it is typed by its body now and renders the `Int`
that `ask` declares. Name the type and the accessor works too — which
is exactly the information the old `printlnInt` carried in its name:

```scheme
(println (cast Int (vecGet v 0)))
```

### Migrating from the old surface

`IO` used to export a function per type. It no longer does.

| Was | Now |
|---|---|
| `(println s)` where `s : String` | unchanged — a `String` renders as its own bytes |
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
| `(__atomic_load p)` / `(__atomic_store p v)` / `(__atomic_add p v)` / `(__atomic_cas p expected new)` / `__fence` | Sequentially consistent atomics on the machine word at **byte address** `p` (the address itself, not `base + i * 8`): a load; a store; an add that answers the word **before** it; a compare-and-swap that answers the word it found, so it stored `new` iff the answer equals `expected`; and a full fence. A store and the fence answer 0. The four that write or order carry `Mut`; the load computes, as `__load64` does. No thread exists for them to synchronise with (`memory-model.md` MM-PAR-1); `tests/stdlib/440-atomics.ax` pins their single-threaded meaning |
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

Axiom ships a standard library written **in Axiom**. It reaches the operating system through raw syscalls, not through C, so a program that links nothing else contains no call to libc — `scripts/check-freestanding.sh` is the gate on that, and an `extern` block linking a Rust crate is the deliberate exception ([ffi.md](ffi.md) §15). On `windows-x86_64` there is no syscall ABI and the same library reaches the OS through kernel32; there the gate turns around and holds every import to `scripts/platform-allow.windows.txt`, eight names, a list that may not carry a libc name.

### Modules at a Glance

| Module | Provides |
|---|---|
| `Pre` | `when`, `unless`, `cond2`, `cond3` (conditional macros), `deriveEq`, `deriveShow`, `deriveArity`, `showOr` |
| `Mem` | `memAlloc`, `memAllocMapped`, `memMarkArray`/`memMarkLeaf`, `memCopy`, `memSet`, `memCmp`, `memGetByte`/`memPutByte`, `memGetWord`/`memSetWord` |
| `Str` | `strFromLit`, `strAlloc`, `strLen`, `strByte`, `strCmp`, `strEq`, `strSlice`, `strDup`, `strConcat`, `strFindByte`, `strStartsWith`, `strCStr` |
| `Utf8` | `utf8Len`, `utf8CharAt`, `utf8DecodeAt`, `utf8FromChar`, `utf8Next`, `utf8Offset`, `utf8Slice`, `utf8Width`, `utf8SeqLen`, `utf8IsCont`, `utf8Valid` (the character view of a `Str`) |
| `Vec` | `vecNew`, `vecNewRef`, `vecWithCapacity`, `vecWithCapacityRef`, `vecFree`, `vecPush`, `vecPop`, `vecGet`, `vecSet`, `vecLen`, `vecCap`, `vecLast`, `vecClear`, `vecSort`, `vecSortBy` |
| `Map` | `mapNew`, `mapNewRefVals`, `mapWithCapacity`, `mapWithCapacityRefVals`, `mapFree`, `mapHas`, `mapGet`, `mapGetStr`, `mapInsert`, `mapRemove`, `mapLen`, `mapCap`, `mapUsed` (open-addressing `Int→Int` hash map) |
| `Fmt` | `fmtInt`, `fmtHex`, `fmtHexUpper`, `fmtFloat`, `fmtFloatPrec`, `fmtPadLeft`, `fmtPadRight`, `fmtPadCenter`, `fmtPadZerosLeft`, `fmtIntWidth` — the functions a format specifier selects |
| `Show` | the `Show` trait and its `show` method (`Int`, `String`, `Bool`, `Float`), and the `format` macro |
| `Err` | `Result` (`Ok`/`Err`), the `Error` record, `isOk`/`isErr`, `okOr`, `unwrapOr`, `mapOk`/`mapErr`, `andThen`, `try!`, `toOption`, `withContext`, and the checked arithmetic `divChecked`, `remChecked`, `shlChecked`, `shrChecked` ([error-model.md](error-model.md) is the specification) |
| `Fallible` | `fallibleMalformed` — the operation a batch loop's callee performs on a malformed record — and the handlers that answer it without unwinding: `fallibleSkip`, `fallibleDefault`, `fallibleCounting`; the skip sentinel `fallibleSkipped`/`fallibleIsSkipped`; the `FallibleTally` a counting handler writes, `fallibleTally`/`fallibleCount` ([error-model.md](error-model.md) ERR-REC-7) |
| `Intern` | `internNew`, `internFree`, `internIntern`, `internFind`, `internLookup`, `internCount` (string interner) |
| `Sys` | `sysWriteFd`, `sysReadFd`, `sysWriteAllFd`, `sysOpenPath`, `sysCloseFd`, `sysExitWith`, `sysFailed`, `sysErrno`, `stdin`/`stdout`/`stderr`; the filesystem (below); and the process layer `sysSpawn`, `sysRun`, `sysRunPath`, `sysWaitPid`, `sysEnv`, `sysArgc`, `sysArg`, `sysGetPid`, `sysNowMicros` |
| `Path` | `pathDir`, `pathBase`, `pathExt`, `pathStem`, `pathJoin`, `pathReplaceExt`, `pathWithSlash`, `pathIsAbsolute`, `pathLastSlash`, `pathExtIndex` — decisions about bytes, no syscalls |
| `IO` | `println`, `eprintln` (**macros** — see Printing and Formatting), `writeStr`, `printlnLit`, `readFileLit`, `exit`, `die`, `todo`; and the filesystem (below) |
| `Ffi` | `ffiHandleNew`/`ffiHandlePtr`/`ffiHandleClose`, the out-cell (`ffiCellNew`, `ffiCellWord`, `ffiCellFree`) and the `Vec` conversions a generated binding needs ([ffi.md](ffi.md)) |
| `Json` | `jsonParse`, `jsonWrite`, and the constructors and accessors between them — written for JSON-RPC |
| `Rpc` | the LSP base protocol's framing over a file descriptor: `rpcRead`, `rpcWrite`, and the reader `rdNew`/`rdBuf`/`rdFilled` |
| `Job` | `jobRunAll` — a bounded pool of child processes, joined in submit order |
| `Html` | the templating DSL, written in the macro system: the element macros `div`/`divA` and the rest of the tag table, the void elements `br`/`hr`/`img`/`input`/`link`/`meta`, `el`/`elA`/`elVoid`/`elVoidA` for any tag, `text`, `raw`, `for`/`forInt`, `style`/`script`/`scriptA`, the attribute macros (`class`, `id`, `href`, `src`, `name`, `value`, …) and `attr`/`flag`; underneath, the builder `hNew`/`hPut`/`hLen`/`hFinish` and the escapers `hEscText`/`hEscAttr`/`hEscTagEnd` |
| `Http` | the request parser `httpRead` over a buffered `HttpReader` (`httpReaderNew`/`httpReaderWith`), the `HttpReq` record with `httpHeader`/`httpHasHeader`/`httpQueryParam`/`httpDecode`, the writer `httpRespond`/`httpRespondRaw`/`httpFail` with `httpStatusText` and `httpContentType`, the router `routerNew`/`routeAdd`/`routeStatic`/`routeNotFound`/`routeDispatch` over `HttpHandler` cells, `httpPathSafe`, `httpServeFile`, `httpServeOne`, and the ceilings `httpMaxHead`/`httpMaxBody` |
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
by platform, so the questions it answers are `open`, `read`
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

The compiler validates `effect(io)` claims against what the body actually performs - a `__syscallN`, or a call to something that performs one - and `pure` claims against the absence of any effect. A mismatch the compiler can decide is an **error** (`AX3010`); a claim it cannot check - because the body calls a value it could not resolve - is a warning (`AX3037`).

---

## Removed Features

These features existed in earlier versions of Axiom but have been removed. Each word keeps a grammar rule whose only job is to report `AX2004` and say what to write instead.

### `begin` — Removed

`(begin a b c)` was the sequencing form. Brace blocks replaced it:
`{ a b c }` sequences and answers its last expression, and a `fn` body
already sequences, so the wrapper is usually just deletable.

It is **reserved** rather than left as an ordinary name. Until
2026-08-26 it was one, so `(begin 1 2 42)` fell through to an
application and drew `AX3001 undefined variable begin` — a diagnostic
that names no replacement and reads like a typo. It answers `AX2004`
now, like its five siblings.

### `union` — Removed

C interoperability is no longer a goal, and an untagged union cannot be pattern-matched safely — its variants are not distinguishable at run time. Use `data` for a tagged sum or `struct` for a product.

(This sentence used to end "has no meaning under linear types". Linear types were removed on 2026-08-25 for enforcing nothing, so the justification was resting on a feature the language does not have.)

### `linear` — Removed

**Refused rather than implemented.** `linear T` parsed to the nominal type
constructor `Linear T` and enforced nothing else: no use was counted, so a value
could be consumed twice or never, and `Linear T` was a real barrier against `T`
(`AX3004`) and nothing more. A marker that reads as an ownership guarantee and
supplies none is worse than no marker, because a reader spends trust on it —
the same ground `deriving` was refused on.

Delete the marker and use the type. Reclamation is the reference counting every
heap block carries (`docs/memory-model.md` `MM-LIFE-2b`/`2c`), and
`__axiom_arena_mark` / `__axiom_arena_reset_keeping` is the explicit fallback
for a program that wants to choose the point.

### `consume` — Removed

**Refused rather than implemented.** `(consume e)` was a parse-time identity
that kept the `Linear` wrapper: the checker typed it as its operand, the IR
lowered it to its operand, and consuming twice was accepted. The form reclaimed
nothing. Delete the wrapper and keep its argument — `(consume e)` always meant
`e`.

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
Axiom 0.5.0 - REPL
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

Supported targets: `darwin-aarch64`, `darwin-x86_64`, `freebsd-x86_64`, `linux-aarch64`, `linux-x86_64`, `windows-x86_64`. Defaults to the host.

What puts a name on that list is stated once, in README's *Targets* section: a CI leg executes what the compiler emits there. This line is a copy of the README's, and `scripts/check-doc-drift.sh` requires the two to agree.

Being on this list does **not** mean a release carries a prebuilt archive for it. Supported and shipped are separate questions, and since 2026-08-30 `linux-x86_64` answers them differently: its CI leg runs the whole gate battery on every change, and `release.yml` builds only `linux-aarch64` and `darwin-aarch64`. On a host with no archive `scripts/install.sh` says so and points at `scripts/bootstrap-from-seed.sh` instead of failing on a download, and `scripts/check-release-targets.sh` holds the release matrix and that refusal list to each other.

`freebsd-x86_64` joined the list on 2026-08-30, when its leg had been seen green on 13 of the previous 15 runs and its `continue-on-error` was removed: `Tests (freebsd-x86_64)` boots FreeBSD 14.4 in a VM and runs the bootstrap and the syscall-table gates there, and it is blocking. `freebsd-aarch64` did NOT join and is the one FreeBSD target that is not supported — it has the same seed and the same syscall table but no leg, because an aarch64 guest is TCG-emulated on every runner GitHub offers (measured at a 300-minute budget and dropped). Neither FreeBSD target ships an archive: a `freebsd-x86_64` host gets the build-from-source paragraph `linux-x86_64` gets, a `freebsd-aarch64` host the not-supported one. FreeBSD 12 is the floor the syscall numbers need; the triple pins 14.

`windows-x86_64` joined the list on 2026-08-30: `Tests (windows-x86_64)` links and EXECUTES a hello world on `windows-latest` from modules the Linux `cross` job emitted, its imports held to an allowlist, and the leg is blocking. The scope of that word is one program — the FreeBSD leg runs the whole stdlib corpus, this one runs `hello.exe` — and README's *Targets* section states the difference rather than letting `supported` cover both silently. **Supported as a target is not supported as a host:** the compiler does not run on Windows, and `scripts/install.sh` refuses a Windows host outright. It is the one target without a syscall ABI, so the emitted runtime and `stdlib/Sys/Platform.windows.ax` reach kernel32 by call (`Sys.Platform.usesSyscallAbi` is 0 there, and `Sys.ax` calls the platform module's own `platformWriteFd`/`platformReadFd`/`platformExitWith` instead of `__syscallN`), the program enters at `mainCRTStartup` with no C runtime, and a `__syscallN` the program reaches anyway exits 74 after `axiom: no syscall ABI on this target`.

`axiom build --target=windows-x86_64 --input p.ax --output p` links `p.exe` with `lld-link` (`/subsystem:console /entry:mainCRTStartup`), which ships with LLVM's `lld`; `--link-search DIR` is translated to `/libpath:DIR` and `--link-lib NAME` to `NAME.lib`. The runtime's kernel32 imports are grounded like any `extern` block's, so a `kernel32.lib` must sit on a search directory: the Windows SDK's (`Lib\<ver>\um\x64`), or one generated anywhere with `llvm-dlltool -m i386:x86-64 -d kernel32.def -l kernel32.lib` from a `.def` naming the symbols on `scripts/platform-allow.windows.txt` - which is what the gates and the CI leg do. `--emit-staticlib` is refused for this target. Hosting the compiler itself on Windows is a later phase; `scripts/install.sh` and `scripts/bootstrap-from-seed.sh` say so.

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