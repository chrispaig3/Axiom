# Axiom

![GitHub CI](https://github.com/chrispaig3/axiom/actions/workflows/ci.yml/badge.svg)

<img width="1500" height="1024" alt="Image" src="https://github.com/user-attachments/assets/38a9afb6-3570-4797-ba57-488e004f4e66" />

A functional systems programming language for humans and agents.
Axiom blends the expressive power of functional programming with the performance and control of systems languages. It uses a clean Lisp‑style S‑expression syntax, a Hindley–Milner‑inspired type system, and an LLVM backend to produce fast, native executables — with no VM and no runtime. Memory comes from an `mmap`-backed bump allocator, with explicit arena reclamation where peak memory matters.

Axiom is intentionally small, explicit, and transparent. It’s designed not only for developers, but also for agentic programming, where AI systems generate, analyze, and manipulate code. Its uniform structure and predictable semantics make it uniquely easy for agents to understand and work with.

Axiom explores a new frontier: languages built with AI, and built for AI‑assisted development.

---

## Why Axiom?

| If you like... | Axiom gives you... |
|---|---|
| **Rust's safety** | A strong static type system with algebraic data types, pattern matching, and no null pointers — but with simpler syntax and faster compilation |
| **Python's expressiveness** | First-class functions, lambdas, and a REPL that compiles to native code — not interprets |
| **Go's pragmatism** | A small, learnable language with a single compilation step — no crazy build systems, no messy dependency managers, no toolchain sprawl |
| **Haskell's elegance** | Curried functions, polymorphic data types, and a clean mathematical foundation — without the 30-minute compile times |

### What makes Axiom different

- **S-expression syntax** — Code is data. Every program is a tree of lists. This makes macros, code generation, and AST manipulation trivial.
- **Prefix operators** — `(+ x y)` instead of `x + y`. Operators are just functions. Uniform syntax means fewer parsing edge cases.
- **LLVM native compilation** — Programs compile to machine code, not bytecode. No VM, no JIT overhead, no runtime.

### Agent-facing notation

Axiom is built for agents as first-class users. Three notations make this possible:

- **AXSYM** — A dense, one-line-per-symbol notation that tells an agent exactly what a file declares and the type of each symbol. Run `axiom symbols` to see it. No re-reading files, no re-deriving signatures by eye.
- **NID** — Stable node IDs: content-derived hashes of `(kind, name)` that survive edits and reformatting, unlike line numbers. Every named declaration gets one automatically.
- **AXTAG** — Source-embedded agent metadata via `;@axiom:<key>(<value>)` comments above declarations. The compiler validates these (e.g., `effect(io)` claims are checked against the syscalls the body actually reaches), so agents can annotate intent and trust the compiler to verify it.

---

## Installation

### Prerequisites

- **LLVM** — `llc` must be on your PATH (for code generation)
- **A C compiler** — `cc`, `clang`, or `gcc` on your PATH (for final linking)

That is the whole list. Axiom's compiler is written in Axiom, so there
is no other language's toolchain to install first.

On macOS:
```bash
brew install llvm
```

On Ubuntu/Debian:
```bash
sudo apt install llvm clang
```

### Build the compiler

```bash
git clone https://github.com/chrispaig3/Axiom
cd axiom
./scripts/bootstrap-from-seed.sh --install .axiom-bin
```

The binary is at `./.axiom-bin/axiom`.

**How a compiler written in itself gets built the first time.**
`bootstrap/` holds the compiler's own LLVM IR, one file per target,
committed. The script runs `llc` and `cc` over the one matching your
host to get a *seed* compiler, uses that to compile `self_host/` into a
real one, and then does it twice more — requiring the last two to be
byte-identical before it hands you anything. So the binary you end up
with was built by a compiler built from the source in front of you, and
the fixpoint is checked on the way, every time.

The seed is allowed to lag the source; what is checked is that it can
still *build* it. When it can no longer do that,
`scripts/bootstrap-from-seed.sh` fails saying so and
`scripts/reseed.sh` moves it forward. See `bootstrap/README.md`.

---

## Quick Start

### Your first program

Create a file called `hello.ax`:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println "Hello from Axiom! 🚀")
    0
  })
```

`IO` is part of Axiom's own standard library - the compiled binary calls
no C function at all, not for printing, not for allocation, not for file
I/O. The `;@axiom:effect(io)` tag is checked: the compiler verifies that
`main` really does perform I/O, and would reject the claim if it did not.

That `"Hello from Axiom!"` is a **first-class string**, not a `char*`
needing conversion. It goes straight into `println`, and its length is
known at compile time — see [Strings](#strings).

Run it:
```bash
axiom run hello.ax
```

Compile it:
```bash
axiom build --input hello.ax --output hello
./hello
```

### How Axiom works

Every Axiom program needs a `main` function that returns `Int`. The compiler pipeline:

```
Source (.ax) → Lexer → Parser → Type Checker → IR → LLVM IR → llc → cc → Executable
```



## Language Guide

### Syntax basics

Axiom uses **S-expressions** — everything is wrapped in parentheses. This takes a moment to get used to, but the payoff is a language with almost no syntax rules to memorize.

#### Comments

```scheme
; This is a line comment

#| This is a block comment.
   They can nest: #| inner |# |#
```

#### Literals

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

String escape sequences: `\n`, `\t`, `\r`, `\\`, `\"`, `\'`, `\0`

### Strings

A string literal **is** a string. No wrapper, no conversion, no
allocation:

```scheme
(import IO)
(import Str)

(println "Hello, Axiom!")
(strLen "Hello")                    ; 5
(strConcat "sum=" (fmtInt 42))      ; "sum=42"
(strSlice "abcdef" 2 3)             ; "cde"
(strEq "abc" "abc")                 ; true
```

The compiler emits two globals per literal — the bytes, and a header
whose visible half holds the length, the byte address, and the block
owning those bytes (the same layout `Str.strWrap` builds at run
time), preceded by the two reference-count header words every heap
block carries, with the static's count pinned at the immortal `-1`
sentinel and its owner word at zero — a literal's bytes belong to the
loader, and nothing may free them:

```llvm
@str_0    = private unnamed_addr constant [14 x i8] c"Hello, Axiom!\00"
@strhdr_0 = private constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 13, ptr @str_0, i64 0 }, align 16
```

The literal evaluates to the visible half's address, so a literal and a
constructed `Str` are the same thing to every consumer. Its **length is
a compile-time constant**, which means `(strLen "Hello")` is a load
rather than a scan, and a literal costs no allocation at all.

The bytes stay NUL-terminated as well as length-counted, so a literal
can still be handed to a syscall or a C function that wants a C string.
`__addr` reaches them:

```scheme
"hello"                             ; the Str
(__addr "hello")                    ; its bytes, as an address
```

<details>
<summary>What this replaced</summary>

Every string in every program used to be written like this:

```scheme
(println (strFromLit (__addr "Hello, Axiom!")))
```

`__addr` took the literal's address and `strFromLit` scanned it with
`cstrLen` to recover a length the compiler already knew. There were 350
such sites across `stdlib/`, `self_host/` and the tests; all are now
plain literals.

`strFromLit` still exists, for NUL-terminated bytes that genuinely
arrive without a length — from a syscall buffer, say. Applied to a
literal it is merely redundant: `(strFromLit (__addr "hi"))` and `"hi"`
are the same value.

</details>

> **A `String` is a machine word.** Every Axiom value is one word, and a
> `String` is the address of a `Str` header, so `String` and `Int` are
> interchangeable. That is what lets a literal be stored in a `Vec`,
> used as a `Map` key, or read by the `Int`-typed accessors that
> implement `Str`. The cost is that `(+ 1 "hi")` type-checks — it adds
> one to an address — the same latitude the language gives every other
> handle.

### Functions

Functions are the heart of Axiom. Every function has an optional type signature and a definition.

```scheme
; Type signature: name takes two Ints, returns an Int
(:: add (-> Int Int Int))

; Definition using 'fn' (modern style): parameters in parens, body follows
(fn (add x y)
  (+ x y))

; Definition using 'define' (classic style)
(define (add x y)
  (+ x y))

; Multi-statement body with braces
(fn (verboseAdd x y)
  { (println "adding {x}")
    (+ x y) })

; A constant (function with no parameters)
(:: answer Int)
(fn answer 42)
```

The type `(-> A B C)` means a function that takes `A`, then `B`, and returns `C`. It's curried — you can partially apply it.

#### Calling functions

```scheme
(add 3 4)           ; Returns 7
(add 10 (add 2 3))  ; Returns 15
```

There are no special calling conventions. Function application is just `(f arg1 arg2 ...)`.

### Operators

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

### Let bindings

Use `let` to introduce local variables:

```scheme
(:: compute (-> Int Int))
(fn (compute n)
  (let ((x (+ n 1))
        (y (* x 2)))
    (+ x y)))
```

Bindings are evaluated in order — later bindings can reference earlier ones.

### Mutable bindings and `while`

A binding is immutable unless marked `mut`. `set` assigns to one, and
`while` loops while its condition holds:

```scheme
(:: sumTo (-> Int Int))
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
two variables needs no extra brackets. The form evaluates to `0` — a
loop that ran zero times has no last iteration to take a value from.

Assigning to a binding that is not `mut` is a compile error, and the
report points at the *declaration* as well as the assignment, because
the declaration is where the fix goes:

<!-- doc-gate:source set.ax -->
```scheme refused
(:: main Int)
(fn (main)
  (let ((x 0)) { (set x 1) x }))
```

<!-- doc-gate:render set.ax human -->
```
error[AX3012]: cannot assign to immutable binding `x`
 --> set.ax:3:23
  |
3 |   (let ((x 0)) { (set x 1) x }))
  |          - `x` is bound here
3 |   (let ((x 0)) { (set x 1) x }))
  |                       ^ `x` cannot be assigned
  |
  = help: declare it mutable: `(mut x ...)` ~> mut x
  = help: only a binding introduced by `(let ((mut x ...)) ...)` may be the target of `set`
  = help: run `axiom explain AX3012` for a full explanation

compilation failed due to 1 previous error
```

The `~> mut x` is not decoration: it is the replacement text, and a tool
can apply it as a byte-range substitution. See
[Error Messages](#error-messages).

`set` also writes a field, through a dotted path — `(set c.n 40)`. The
field is resolved by name, so its offset is the compiler's problem, and
a field write needs no `mut`, which governs rebinding the local rather
than mutating what it points at. What `set` will not take is an
arbitrary place expression: `(set (f x) 1)` is a syntax error naming
what is wrong. Raw memory is still reachable through `memSetWord`, which
is what `Vec` and `Map` do.

### Conditionals

```scheme
(:: abs (-> Int Int))
(fn (abs n)
  (if (< n 0)
      (- 0 n)
      n))
```

`if` is an expression — it returns a value. Both branches are required.

### Lambda (anonymous functions)

```scheme
; A function that adds 1
(lambda (x) (+ x 1))

; A function with two parameters
(lambda (x y) (+ x y))

; Ignoring a parameter with wildcard
(lambda (_) 42)
```

### Sequencing with `{ }`

When you need to evaluate multiple expressions in order, use braces:

```scheme
{
  (println "Starting...")
  (println "Working...")
  0
}
```

The value of a brace block is the value of its last expression. Single expressions in braces are unwrapped automatically — `{ 42 }` is just `42`.

Function bodies, `let` bodies, `if` branches, and `lambda` bodies also support implicit sequencing without braces:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (println "Starting...")
  (println "Working...")
  0)
```

### Data types (Algebraic Data Types)

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

### Struct variants

A constructor's fields can be named rather than positional:

```scheme
(data Shape
  (Circle { r : Int })
  (Rect { w : Int, h : Int })
  (Point))
```

Values are built positionally, in declaration order — `(Circle 7)`,
`(Rect 3 4)` — and read back by name, either through field access or in
a pattern:

```scheme
(fn (area s)
  (match s
    ((Circle { r })    (* 3 (* r r)))
    ((Rect { w, h })   (* w h))
    ((Point)           0)))
```

`{ w, h }` is punning: it means `{ w = w, h = h }`. Named patterns buy
three things a positional pattern cannot:

| | |
|---|---|
| **Order independence** | `{ h = h, w = w }` binds what its names say. Reordering two same-typed fields in a declaration cannot silently swap them at every match site. |
| **Partiality** | A field the arm does not name is simply not bound — no `_` placeholder to keep in step with the constructor's arity. |
| **Punning** | `{ w, h }` rather than `{ w = w, h = h }`. |

Named patterns nest, and mix with explicit binding:

```scheme
(match x
  ((Wrap { inner = (Rect { w, h }), tag = t }) (+ (* w h) t))
  ((Wrap { tag = t })                          t))
```

Positional patterns keep working on the same type; named fields add a
spelling rather than replacing one.

### Pattern matching with `match`

```scheme
(:: fromMaybe (-> Int (Maybe Int) Int))
(fn (fromMaybe default val)
  (match val
    ((Nothing) default)
    ((Just x) x)))
```

Patterns can match constructors, literals, tuples, lists, and wildcards:

```scheme
(match x
  (42 "the answer")
  ((Cons head tail) head)
  (_ "anything else"))
```

The built-in `Option` type provides safe null handling without exceptions:

```scheme
(match (Some 42)
  ((Some v) v)
  ((None) 0))
```

#### Algebraic data types: how they actually run

A `data` value takes one of two runtime shapes:

- A constructor **with fields** is a heap block: word `0` is an integer
  tag saying which constructor built it, and words `1..` are its fields,
  one 8-byte word each.
- A nullary constructor of an **all-nullary type** — `(data Color (Red)
  (Green) (Blue))` — *is* its tag. No block, no allocation.

The second shape is why an enum costs nothing. It also means matching
has to know where the tag lives, and it takes that from the constructor
*named in the pattern*, which is static — not by inspecting the value,
which is ambiguous, since one machine word cannot say whether it means
an integer, a tag, or a pointer.

A mixed type keeps the uniform shape: in `(data L (Nil) (Cons Int L))`,
`Nil` is a block like `Cons`, because a value of `L` has to be matchable
the same way whichever constructor built it. That uniformity is also
what makes recursive types work with no special-casing: a field that is
itself a `data` value is just another 8-byte word holding that value's
address.

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

What works, and what to know:

- **Exhaustiveness and arity are checked** (missing constructors and
  wrong-arity constructor patterns are compile errors - `AX3005`/`AX3009`).
- **Nested constructor patterns work** - `((Cons h (Cons h2 t)) ...)`
  correctly matches and binds all three variables. Inner constructor tags
  are checked recursively and fields are extracted at each level.
- **Tuple and list patterns inside `match` now compare elements**
  - `PTuple` and `PList` patterns check each element at the correct
  offset and branch to the next arm on a mismatch, just like `PCon`
  arms. Tuples and lists are heap-allocated blocks with elements stored
  at contiguous 8-byte offsets (no tag word).
- **Named fields per variant** work - see [Struct variants](#struct-variants).
- **Allocation** comes from an `mmap`-backed bump allocator, not `malloc`,
  and since 2026-08-15 dead blocks ARE freed implicitly: every heap
  block carries a reference count and a shape word, and a block whose
  count reaches zero is walked and re-issued from a size class. A
  thousand build-and-drop iterations move the allocator's bump by 384
  bytes where they moved it by 80,304
  (`tests/stdlib/359-arc-str-bytes.ax`). This bullet read "nothing is
  freed implicitly, so memory use tracks *total* allocations rather
  than live data" until 2026-08-16 — true of every day before the
  counts landed, and true today only of the ownership events that do
  not emit yet, which are the two that need an escape analysis
  ([docs/memory-model.md](docs/memory-model.md) MM-LIFE-2c events 2
  and 3). `__axiom_arena_mark` and
  `__axiom_arena_reset` reclaim explicitly by rolling the allocator's
  waterline back, which is how the language server holds flat memory
  across an editing session. There is no tracing collector: the retired
  Rust compiler had one behind `--gc`, it was not ported, and the flag is
  now refused by name rather than silently ignored
  (`docs/self-hosting.md` §8.4). See the memory model specification in
  [docs/memory-model.md](docs/memory-model.md).
- **Field access by name** works on `data` and `struct` alike: `s.r`
  reads a field of a value whose constructor declared one.

### Structs

Products of named fields:

```scheme
(struct Point
  (x : Int)
  (y : Int))
```

There are no layout modifiers. `packed`, `repr(C)` and `align(N)` were
documented here and accepted by nothing - the parser has always answered
`AX2001` for all three - and C layout means nothing in a language that
links no C.

### Type aliases

```scheme
(type StringList () = [String])
```

### Traits

Define interfaces with typed methods:

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

Implement a trait for a specific type:

```scheme
(impl (Eq Int) where
  ((eq (lambda (x y) (== x y)))))

; Again one group, holding every method.
(impl (Ord Int) where
  ((cmp (lambda (x y) (if (== x y) 0 (if (< x y) (- 0 1) 1))))
   (lt (lambda (x y) (< x y)))
   (gt (lambda (x y) (> x y)))))
```

A call is dispatched on the **static type of an argument**, resolved at
compile time to a direct call:

```scheme
(eq 3 3)        ; the (Eq Int) implementation
(eq true true)  ; the (Eq Bool) one, same spelling
```

Traits support:
- **Type parameters** — `(trait (Eq a) ...)` binds `a` for all method signatures, and it is what an implementation is selected by
- **Default methods** — `(ne :: (-> a a Bool) = (lambda (x y) (if (eq x y) false true)))`. An implementation that omits the method gets the default generated for its type, and the default's own calls to the trait's other methods dispatch normally
- **Supertraits** — `(trait (Ord a) (Eq a) ...)` requires every type with an `Ord` implementation to have an `Eq` one, and says so if it does not
- **Effects** — traits and methods can carry effect annotations

Not yet: a function generic over a trait cannot call its methods, because
dispatch needs a concrete type at the call site rather than a type
variable. Every unsupported shape is `AX3025` — run `axiom explain AX3025`.

### Effects

Axiom tracks side effects at the type level. Effects are checked by the compiler, so you know exactly what a function does.

Built-in effects:

| Effect | Meaning |
|---|---|
| `IO` | Reaches the outside world — a syscall |
| `Pure` | No side effects |
| `Alloc` | Heap allocation (`alloc`) |
| `Mut` | Mutable state (`set` on a `mut` binding, field mutation) |
| `Div` | Divergence (infinite loops) |

Declare an effect type:

```scheme
(effect Console
  (print :: (-> String ())))
```

Annotate a function with its effects using AXTAG metadata:

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main) { (println "hello") 0 })
```

The compiler validates that the body actually performs the declared effects.

Handle effects with `handle`:

```scheme
(handle body (effects...) handler)
```

`handle` runs `body`, intercepting the declared `effects` via `handler`. Effects not listed propagate out.

```scheme
; A handler that catches IO and returns a default value
(handle (println "hello") (IO) 0)
```

Effect annotations are also supported on traits and implementations:

```scheme
(trait (Console a)
  where
    (print :: (-> String a)))

(impl (Console IO)
  where
    (print (lambda (s) (println s))))
```

---

## Type System

### Primitive types

| Type | Description | LLVM type |
|---|---|---|
| `Int` | 64-bit signed integer | `i64` |
| `Float` | 64-bit floating point | `f64` |
| `Bool` | Boolean | `i1` |
| `Char` | Character | `i8` |
| `String` | A `Str` handle - the address of a `{ length, bytes }` header. Interchangeable with `Int`; see [Strings](#strings) | `i64` |
| `()` | Unit (no value) | `void` |
| `Unit` | A distinct constructor, **not** a synonym for `()` — `symbols` renders them differently; see [reference.md](docs/reference.md#types) | `void` |
| `Void` | Void | `void` |
| `Any` | Generic pointer | `ptr` |

### Sized integers and floats — removed

`I8`–`I128`, `U8`–`U128`, `Isize`/`Usize`, `Double` and `F32`/`F64`
were accepted names with **no representational effect**: every one
lowered to a full-width `i64` with no truncation, no extension and no
width-specific arithmetic while being incompatible with `Int`, and the
float spellings were worse — the checker called them floats while the
emitter keyed float arithmetic on `Float` alone, so `Double` arithmetic
was integer `add` on double bit patterns, silently. All are refused
since 2026-08-14 (`AX3002`; their corpus population was zero), per
[docs/memory-model.md](docs/memory-model.md) MM-VAL-3c/MM-VAL-4b:
"give them widths or remove them". `Float` is the one floating type;
`Int` the one integer.

### Compound types

```scheme
(-> Int Int)           ; Function: Int -> Int
(-> Int Int Int)       ; Curried: Int -> Int -> Int
(* Int)                ; Pointer to Int
[Int]                  ; List of Int
(Int String Bool)      ; 3-tuple
```

### Type casting

```scheme
(cast Float someBits)
```

---

## Standard library

Axiom ships a standard library written **in Axiom**. It reaches the
operating system through raw syscalls, not through C, so a compiled
Axiom program contains no call to libc - not for printing, not for
allocation, not for file I/O. There is no FFI to reach for either:
`foreign` has been removed, and the language has no way to name an
external symbol.

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((total (+ 1 2)))
    {
      (println "hello, world")
      (println 42)                ; any type with a `Show` instance
      (println "sum={total}")     ; a hole names a binding in scope
      (println "hex={total:>6x}") ; ...with a Rust-style specifier
      0
    }))
```

Printing is two macros and no per-type functions — `println` and
`eprintln`, with `format` beside them in `Show` for the string a
program builds instead of writes. This sentence said *five* from
2026-08-15 until 2026-08-16: it counted `print` and `eprint`, which
were never written. `stdlib/IO.ax` says why there is deliberately no
newline-less printer — the line is assembled at compile time, so
emitting it in pieces buys nothing and costs a syscall each — and
`(print "hi")` is `AX3001 undefined variable`. The format string is
parsed by the compiler, each hole becomes a `show` call chosen by the
value's static type, and each specifier chooses a `Fmt` function.
Nothing is parsed at run time, so a malformed format string or a
specifier applied to the wrong type is a compile error. See
[Printing and Formatting](docs/reference.md#printing-and-formatting).

### Modules

| Module | Provides |
|---|---|
| `Pre` | `when`, `unless`, `cond2`, `cond3` (conditional macros) |
| `Mem` | `memAlloc`, `memCopy`, `memSet`, `memCmp`, `memGetByte`/`memPutByte`, `memGetWord`/`memSetWord` |
| `Str` | `strLen`, `strByte`, `strCmp`, `strEq`, `strSlice`, `strDup`, `strConcat`, `strFindByte`, `strStartsWith`, `strCStr`, `strAlloc`, `strFromLit`. String *literals* are already `Str` values — see [Strings](#strings) |
| `Vec` | `vecNew`, `vecPush`, `vecPop`, `vecGet`, `vecSet`, `vecLen`, `vecCap`, `vecReserve`, `vecClear` |
| `Map` | `mapNew`, `mapHas`, `mapGet`, `mapInsert`, `mapRemove`, `mapLen`, `mapCap`, `mapNew`, `mapRehash` (open-addressing `Int→Int` hash map) |
| `Fmt` | `fmtInt`, `fmtHex`, `fmtPadLeft`, `fmtIntWidth` |
| `Intern` | `internNew`, `internIntern`, `internFind`, `internLookup`, `internCount` (string interner) |
| `Sys` | `sysWriteFd`, `sysReadFd`, `sysWriteAllFd`, `sysOpenPath`, `sysCloseFd`, `sysExitWith`, `sysFailed`, `sysErrno`, `sysArgc`/`sysArg`, `stdin`/`stdout`/`stderr`; the filesystem — `sysReadFile`, `sysWriteFile`, `sysAppendFile`, `sysRename`, `sysUnlink`, `sysMkdir`, `sysRmdir`, `sysReadDir`, `sysFileExists`, `sysIsDir`, `sysFileSize`, `sysReadErrno`, `sysGetCwd`; and processes — `sysSpawn`, `sysRun`, `sysRunPath`, `sysWaitPid`, `sysEnv` |
| `Path` | `pathDir`, `pathBase`, `pathExt`, `pathStem`, `pathJoin`, `pathReplaceExt`, `pathWithSlash`, `pathIsAbsolute` — bytes only, no syscalls |
| `IO` | `println`, `eprintln` — **macros**, with compile-time format strings — plus `writeStr` (bytes, no newline, no rendering), `exit`, `die`, the raw-address variants `printlnLit`, `readFileLit`, and the `Str`-taking filesystem surface: `readFile`, `writeFile`, `appendFile`, `copyFile`, `removeFile`, `renamePath`, `fileExists`, `isDir`, `fileSize`, `readErrno`, `makeDir`, `makeDirAll`, `removeDir`, `listDir`, `cwd` |
| `Show` | the `Show` trait (`show`) and the `format` macro |

A `Str` is a length-prefixed, NUL-terminated string: slicing shares
storage, and `strCStr` hands the bytes to a syscall without copying.

The `Lit` names take a raw NUL-terminated address rather than a `Str`.
They are rarely what you want now that a literal is a `Str` —
`(println "hi")` is both shorter and cheaper than
`(printlnLit (__addr "hi"))` — but they remain the way to print bytes
that arrived without a length, such as a syscall buffer.

The library is found automatically - `AXIOM_STDLIB` overrides its
location, and `AXIOM_PATH` (colon-separated) adds further module search
directories. A module in the entry file's own directory always wins, so
a project can shadow a standard-library module with its own.

### Freestanding primitives

The standard library is built on these, and so is any code that needs to
talk to the machine directly. They are the layer where the type system
stops: every argument and result is an `Int`, and a safe, typed wrapper
around them is the standard library's job.

| Primitive | Meaning |
|---|---|
| `(__syscall0 n)` ... `(__syscall6 n a1 ... a6)` | Raw syscall. Returns the result, or `-errno` on failure, on every platform |
| `(__load8 base i)` / `(__store8 base i v)` | Byte at `base + i` |
| `(__load64 base i)` / `(__store64 base i v)` | Machine word at `base + i * 8` |
| `(__alloc bytes)` | Address of `bytes` fresh zeroed bytes |
| `(__addr "literal")` | Address of a string literal's bytes |

Syscall numbers are *not* built into the compiler: they live in
`stdlib/Sys/Platform.<os>[-<arch>].ax`, and the module resolver picks the
file matching `--target`. Adding a syscall is a standard-library change.

### Targets

`--target` selects the platform to generate code for, and with it both
the syscall ABI and which platform modules the standard library
resolves to:

```bash
axiom --target=linux-x86_64 emit-llvm main.ax -o main.ll
```

Supported: `darwin-aarch64`, `darwin-x86_64`, `linux-aarch64`,
`linux-x86_64`. Defaults to the host.

### Optimisation and recursion depth

Iteration has three spellings, and only one of them is bounded:

| | Depth at `-O0` |
|---|---|
| `while` | Unbounded — it is a real loop. 10⁷ iterations in constant stack |
| **Self** tail recursion | Unbounded — the loop is built by Axiom's own codegen at every `--opt` level ([docs/memory-model.md](docs/memory-model.md) MM-EXEC-6b). Mutual tail recursion is flattened only by LLVM at `--opt 1`+ (MM-EXEC-6c) |
| **Non-tail** recursion | **Bounded**: 60,000–80,000 frames on an 8 MiB stack |

So the shape to avoid at scale is a fold whose combining step happens
*after* the recursive call:

```scheme
; Bounded: the `+` runs after the call, so every level keeps a frame.
(fn (count v i hi)
  (if (>= i hi) 0 (+ (vecGet v i) (count v (+ i 1) hi))))

; Unbounded: an accumulator makes the call a tail call.
(fn (count v i hi acc)
  (if (>= i hi) acc (count v (+ i 1) hi (+ acc (vecGet v i)))))
```

`--opt 1` and above additionally run LLVM's mid-level passes:

```bash
axiom build --input main.ax --output main --opt 2
```

Worth using for anything hot, and still needed for the *correctness* of
mutual tail recursion — only a **self** tail call is a loop without the
optimiser ([docs/memory-model.md](docs/memory-model.md) MM-EXEC-6b/6c).

## Built-ins

### Common data types (define as needed)

```scheme
(data Maybe (a) (Nothing) (Just a))
(data Ordering (LT) (EQ) (GT))
(data List (a) (Nil) (Cons a (List a)))
```

### Built-in types

`Option` is a built-in generic type with `Some` and `None` constructors,
always available without a `data` declaration. It works with `match`
for safe null handling:

```scheme
(:: safe_div (-> Int Int (Option Int)))
(fn (safe_div a b)
  (match b
    ((0) (None))
    (_ (Some (/ a b)))))

(:: main Int)
(fn main
  (match (safe_div 10 2)
    ((Some x) x)
    ((None) 0)))
```

### Built-in operators (always available)

| Operator | Signature |
|---|---|
| `+`, `-`, `*`, `/`, `%` | `(Int -> (Int -> Int))` |
| `==`, `!=`, `<`, `>`, `<=`, `>=` | `(Int -> (Int -> Bool))` |
| `&&`, `||` | `(Bool -> (Bool -> Bool))` |

---

## Recipes

### Print to stdout

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println "a literal")
    (println 42)
    (println (strConcat "formatted: " (fmtInt 42)))
    0
  })
```

No FFI and no `printf`: `IO` is Axiom code over the syscall
primitives.

### Read a file

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((contents (readFile "input.txt")))
    {
      (println (strLen contents))
      (writeStr stdout contents)   ; bytes as they are: no newline, no rendering
      0
    }))
```

### Walk a directory

```scheme
(import IO)
(import Path)
(import Str)
(import Vec)

; Every `.ax` file in `dir`, with its size, one per line.
(:: report (-> String Int Int Int))
;@axiom:effect(io)
(fn (report dir names i)
  (if (>= i (vecLen names))
      0
      (let ((p (pathJoin dir (cast String (vecGet names i)))))
        {
          (if (strEq (pathExt p) ".ax")
              (let ((size (fileSize p))) (println "{p}  {size}"))
              0)
          (report dir names (+ i 1))
        })))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (makeDirAll "build/reports")           ; parents included; EEXIST is success
    (report "stdlib" (listDir "stdlib") 0) ; sorted, so two machines agree
    (appendFile "build/reports/log.txt" "swept stdlib\n")
    0
  })
```

`listDir` answers a sorted `Vec` of names with `.` and `..` removed —
sorted because `readdir` order is the filesystem's and differs between
machines, which is enough to make a program that walks a directory
non-reproducible. `Sys.sysReadDir` is the unsorted primitive underneath
for callers that have their own ordering.

There is no `stat`: its answer is a struct whose layout differs on all
four targets, so `isDir`, `fileExists` and `fileSize` are `open`, `read`
and `lseek` instead — see [docs/self-hosting.md §47 and
§49](docs/self-hosting.md).

### Working with data types

```scheme
(data Maybe (a)
  (Nothing)
  (Just a))

(:: fromMaybe (-> Int (Maybe Int) Int))
(fn (fromMaybe default val)
  (match val
    ((Nothing) default)
    ((Just x) x)))

(:: main Int)
(fn main
  (fromMaybe 0 (Just 42)))
```

Note: constructor patterns now compile to real branching code (see
[Algebraic data types: how they actually run](#algebraic-data-types-how-they-actually-run)) -
each arm's constructor tag is checked in order and only a matching arm's
body actually runs. Nested constructor patterns and tuple/list patterns
inside `match` work correctly (see the limitations below).

---

## Modules and imports

Split a program across files with `(import Mod.Sub ...)`. A declaration
leaves its module only if it is written `pub`:

```scheme
; Math/Ops.ax
(pub :: square (-> Int Int))
(pub fn (square x) (* x x))

; Not `pub`: this module's own business, and callable only from
; inside this file. Naming it from anywhere else is AX3023.
(:: twice (-> Int Int))
(fn (twice x) (+ x x))
```

```scheme fragment
; main.ax
(import Math.Ops (square))       ; only bring in `square`
; (import Math.Ops)               would bring in every `pub` decl

(:: main Int)
(fn main (square 5))
```

```bash
axiom run main.ax
```

> Every version of this example before 2026-08-10 omitted `pub`, and
> every version of it failed: `square` was not exported, so the call
> was `AX3001 undefined variable`. It is now `AX3023`, which names the
> module and the reason. See [docs/self-hosting.md §14](docs/self-hosting.md).

How it works:

- A dotted module path maps directly to a file path: `Math.Ops` resolves
  to `Math/Ops.ax`, **always relative to the entry file's own directory**
  (the file you passed to `check`/`build`/`run`/`emit-llvm`) - not to
  whichever file happens to contain the `(import ...)`, so a deeply nested
  module can still `(import Math.Ops)` using the same path the entry file
  would.
- `(import Mod.Sub)` with no name list makes every `pub` top-level
  declaration of that file visible; `(import Mod.Sub (a b))` makes only
  the named ones visible (functions, `data`/`struct`/`type` decls, ...).
- **`pub` and the name list decide which names you may write, not which
  declarations exist.** A module's own bodies always reach its own
  declarations, `pub` or not, so a module with private helpers is
  importable and behaves the same however it is imported. Reaching a
  name a module does not export is `AX3023`, which names the module.
  Until 2026-08-10 the two were one decision: a private declaration was
  deleted from the program, the module's own calls to it broke — and if
  the importing file defined that name, they silently called *it*
  instead. `(import IO (println))` beside an entry-file `writeStr` made
  the standard library print the entry file's bytes, at exit 0.
- Imports are transitive (`A` imports `B` imports `C` brings `C`'s
  declarations into `A` too) and diamond-safe (two different modules both
  importing `C` merges `C` exactly once, not twice).
- Qualified access is supported: `Mod::name` resolves to `name` declared in
  `Mod`. Two modules can define the same name without collision when only
  one is imported unqualified, or when the ambiguous name is accessed via
  `Mod::name`. Imported declarations still join the importing module's flat
  top-level namespace by default.
- A module path that doesn't resolve to a real file is `AX5001` (`axiom
  explain AX5001`), reported before type-checking even starts.
- Diagnostics from an imported file's own contents (a type error inside
  `Math/Ops.ax`, say) are reported against `Math/Ops.ax`'s real file path
  and line/column, not the entry file's - every diagnostic in a
  multi-file build is attributed to the actual file and source text it
  came from, in every one of the `human`/`ai`/`json` formats.

---

## CLI Commands

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

# Start interactive REPL
axiom repl

# Look up a diagnostic code, or list every one of them
axiom explain AX3001
axiom explain --list

# Render diagnostics in Axiom's AI-optimized notation (see docs/diagnostics.md)
axiom --diagnostic-format=ai check source.ax

# Or as JSON Lines, one object per diagnostic
axiom --diagnostic-format=json check source.ax

# List every top-level symbol (functions, types, constructors, structs,
# aliases, traits, ...) and its type/shape in Axiom's AI-optimized
# "AXSYM" notation (see docs/diagnostics.md); resolves (import ...) too, and
# attributes each symbol to the file that actually declared it
axiom --diagnostic-format=ai symbols source.ax

# Same, but also include the dozen always-in-scope built-in operators
# (omitted by default to keep output minimal)
axiom --diagnostic-format=ai symbols source.ax --builtins
```

See [`docs/diagnostics.md`](docs/diagnostics.md) for the full agent-facing
notation architecture: stable error codes (`AX####`), cascade suppression,
the human report format, the AI-optimized "AXDL" diagnostic notation, and
the AI-optimized "AXSYM" symbol/type notation.

---

## REPL

The REPL compiles expressions to native code — it doesn't interpret them. This means you get real performance even in interactive mode.

```bash
axiom repl
```

### REPL commands

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

### Example session

```
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   Axiom v0.1.0 - Functional Systems Language              ║
║                                                           ║
║   Type :help for commands, :quit to exit                 ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝

axiom> 1 (:: add (-> Int Int Int))
OK: add defined

axiom> 2 (define (add x y) (+ x y))
OK: add defined

axiom> 3 (add 3 4)
type : Int
result 0

axiom> 4 :type (add 10 20)
(add 10 20) : Int

axiom> 5 :defs
Definitions in scope:
  add : (Int -> (Int -> Int))
  + : (Int -> (Int -> Int))
  - : (Int -> (Int -> Int))
  * : (Int -> (Int -> Int))
  / : (Int -> (Int -> Int))
  ...

axiom> 6 :llvm (+ 1 2)
; Generated LLVM IR:
define i64 @__repl_result() {
...
```

The REPL accumulates definitions — functions you define persist across inputs. History is saved between sessions.

---

## Compiler Architecture

```
Source (.ax)
    │
    ▼
[1/5] Lexer        → Tokens
    │
    ▼
[2/5] Parser       → AST (S-expression tree)
    │
    ▼
[3/5] Type Checker → Two-pass: collect declarations, then check bodies
    │
    ▼
[4/5] IR Generator → Three-address code with basic blocks
    │
    ▼
[5/5] LLVM CodeGen → LLVM IR text → llc → .o → cc → executable
```

### Compiler structure

The compiler is `self_host/`, and it is written in Axiom. Every stage of
the pipeline above is a module you can read in the language it compiles.

| Module | Purpose |
|---|---|
| `core.ax` | Tokens and spans |
| `lexer.ax` | Tokenizer |
| `parser.ax` | S-expression parser and AST |
| `typecheck.ax` | Name resolution, types, effects, AXTAG validation |
| `codegen.ax` | Import resolution, name mangling, LLVM IR emission |
| `diag.ax` | Diagnostics, AXDL and JSON rendering, source maps |
| `render.ax` | The human diagnostic renderer |
| `driver.ax` | `build`: `opt`, `llc`, `cc`, and blaming the right one |
| `main.ax` | CLI entry point and subcommand dispatch |
| `format.ax`, `repl.ax`, `symbols.ax`, `explain.ax`, `lsp.ax` | The tools |
| `Host.<target>.ax` | Host triple and syscall ABI, chosen when the compiler is *compiled* — a freestanding binary has no `uname` to ask |

---

## Implementation Status

| Feature | Status | Notes |
|---|---|---|
| Functions & types | **Complete** | Curried signatures, exact return types. A signature's type variables BIND: rigid inside the body, so `(:: f (-> a Int))` may not do arithmetic on its argument, and instantiated at every reference, so a caller may still pass anything. Two arguments that disagree with *each other* are not yet reported. `tests/selfhost/972-polymorphic-signature.ax`, `tests/diagnostics/460-signature-type-variable.ax` |
| Operators (prefix) | **Complete** | `tests/selfhost/910-operator-coverage.ax`. All arithmetic, comparison, logical (`+`, `-`, `*`, `/`, `%`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `&&`, `\|\|`) |
| Let bindings | **Complete** | Variable resolution, sequential evaluation. `tests/selfhost/030-let.ax`, `tests/selfhost/100-letnest.ax` |
| if expressions | **Complete** | Proper branching with result values. `tests/selfhost/040-if.ax` |
| begin blocks | **Removed** | Replaced by `{ }` brace blocks and implicit sequencing |
| brace blocks | **Complete** | `{ expr1 expr2 ... }` — modern sequencing, returns last value. `tests/selfhost/080-seq.ax` |
| fn keyword | **Complete** | Modern alias for `define`. `tests/selfhost/020-call.ax` |
| FFI | **Functional** | The FFI is the `extern` BLOCK, and Rust is the language on the other side (`docs/ffi.md`). `(pub extern "lib" (add :: (-> Int Int Int) (symbol "axffi_add")))` emits `declare i64 @axffi_add(i64, i64) #0`, and `axiom build --link-lib --link-search` puts the archive on the link line. A call compiles to the same `call i64 @sym(...)` an internal call does - Axiom has no VM, so there is no trampoline and nothing to marshal for a scalar. Calling one contributes `IO` and propagates transitively, which is `MM-FFI-5` requirement 3. `foreign` is NOT this feature under a new name and stays reserved at `AX2004`: it named one symbol and emitted a call the module never declared, so it never linked. Freestanding is now tiered and measured: a program with no `extern` imports **0** symbols, one bound to a `no_std` Rust crate also imports **0**, and one bound to a `std` crate imports 188 - gated by `scripts/check-ffi.sh`, which enumerates permitted symbols instead of forbidding all of them. Fixtures in `tests/ffi/`; the Rust support crates in `rust/`. Not yet done: `Foreign` as a compiler-known opaque type (`MM-FFI-5` requirements 1 and 2), and the `Slice`/`Outcome` return protocols |
| Standard library | **Functional** | `Pre`, `Mem`, `Str`, `Vec`, `Map`, `Fmt`, `Intern`, `Sys`, `IO`, written in Axiom over syscall primitives. `Vec`/`Map`/`Intern` are golden-tested and validated at 10⁵ elements; against Rust at 10⁶, `Intern` is *faster* (0.73×), `Vec` is 3.4×, and `Map` is 1.80× — the cause was an affine hash, not the allocator, and `docs/v1-roadmap.md` §2.4 B3 records the three theories that were measured and rejected first. This row read 0.75× and 2.5× until 2026-08-16: those were the 2026-08-04 figures, and the re-measurement that took `Map` from 14× to 1.80× on 2026-08-05 corrected all three in `docs/self-hosting.md` §2.1 B3's table — the doc-drift pass that repaired this row on 2026-08-10 repaired `Map`'s number and left the two beside it, which is the exact failure a sentence citing its own source is supposed to prevent. `scripts/bench-datastructures.sh` |
| Error handling | **Functional; not yet adopted** | `tests/stdlib/371-err-module.ax`, `tests/stdlib/370-error-propagation.ax`. `stdlib/Err.ax` ships `Result`, an `Error` record, `mapErr`/`andThen`/`mapOk`/`okOr`/`toOption`/`withContext`, checked `divChecked`/`remChecked`/`shlChecked`/`shrChecked` for the traps that otherwise exit 72, and the `try!` propagation form. `Result` is an ordinary declaration rather than a built-in beside `Option`, because a user-declared two-parameter ADT already checks, is pure to construct and inspect, and is reclaimed at a release boundary — a built-in would have cost a seed rebuild for none of that. Two measured rules decide how it is written and both are gated: the recursion in a propagating loop MUST be a match ARM's answer, never the scrutinee (the scrutinee shape costs 32 bytes of stack per call and dies at 262,144 where the arm shape runs 5,000,000 flat), and an error value crossing a tail-call boundary MUST be `let`-bound (288,176 bytes leaked over 2000 iterations otherwise, against 176). What is NOT done is adoption: the standard library still signals failure with `-errno` and `-1` sentinels at 65 sites over 12 files, and a fallible call still leaks the 32-byte block it returns, which needs the escape analysis `MM-LIFE-2c` events 2 and 3 are waiting on. [docs/error-model.md](docs/error-model.md) marks every rule H/P/R and says which |
| Syscalls | **Complete** | `tests/selfhost/230-syscall.ax`. `__syscall0`-`__syscall6` on Darwin and Linux, x86-64 and AArch64; errors normalised to `-errno` on every platform |
| Allocation | **Functional; unbounded by default** | `mmap`-backed bump allocator emitted by the backend. (Defining `axiom_alloc` yourself does *not* override it — the name is refused outright, `AX3026`, because the override seam does not exist — [docs/memory-model.md](docs/memory-model.md) MM-ALLOC-8.) No `free`; every heap block now carries a reference count and a shape word, and a block whose count reaches zero joins a size class and is handed out again — walking its reference map on the way, so a dead value takes what it owned with it: a discarded constructor cell holding a string frees the string's header *and* the string's bytes, and a thousand build-and-drop iterations move the allocator's bump by 384 bytes where they used to move it by 80,304 (`tests/stdlib/359-arc-str-bytes.ax`). **The self tail call is a release boundary since 2026-08-15** (MM-LIFE-2c event 4), which is the shape the strategy exists for - the activation that never returns: a loop allocating a fresh string per iteration and dropping the previous one moves the bump **480 bytes over 2000 iterations** where it used to move **224,304** (`tests/stdlib/362-arc-tail-boundary.ax`). What unblocked it was making the invisible stores visible: `Mem.memSetWord` and the AST's `mkNode` each `cast Int` a value out of the type system's sight, and both now take a share through `__retainref`, a type-directed retain that emits nothing at all when the stored word is an integer. Events 2 and 3 still do not emit - they need to know whether a value escaped its frame - so memory still tracks *total* allocations for the shapes they cover. `__axiom_arena_mark`/`__axiom_arena_reset` reclaim explicitly where peak memory matters. No tracing collector — the Rust compiler's `--gc` was not ported and the flag is now refused (`docs/self-hosting.md` §8.4). Not the end state; the chosen strategy is reference counting — see the memory model specification, [docs/memory-model.md](docs/memory-model.md) |
| Cross-compilation | **Functional** | `--target` selects ABI and platform stdlib modules; codegen verified for all four targets |
| Self-hosting | **Done** | Axiom's compiler is written in Axiom. It compiles itself and reproduces itself byte-for-byte (`stage2 == stage3`, as objects and as IR), and a clean checkout builds it from `bootstrap/` with nothing but `llc` and a C linker. The Rust implementation it replaced has been removed. See [docs/self-hosting.md](docs/self-hosting.md) |
| ADTs / data types | **Complete** | `tests/selfhost/140-data.ax`, `tests/selfhost/400-mixed-nullary.ax`. Constructors (nullary and with fields, including recursive types like `List`/`Tree`) compile to heap-boxed tagged values; see [Algebraic data types](#algebraic-data-types-how-they-actually-run) |
| Structs | **Complete** | `tests/selfhost/150-struct.ax`. Declarations, LLVM emission, field access (`.field`), construction (`(StructName expr1 expr2 ...)`), `mut` fields, field mutation |
| Struct variants | **Complete** | `tests/selfhost/810-struct-variant-pattern.ax`. Named fields per `data` constructor, matchable by name and in any order, with field punning (`{ w, h }`) and partial patterns. `tests/stdlib/210-struct-variants.ax` |
| String literals | **Complete** | `tests/selfhost/310-strlit.ax`, `tests/selfhost/890-lexical-edges.ax`. A literal *is* a `Str`: a static `{ length, bytes }` header, length known at compile time, no allocation and no runtime scan. See [Strings](#strings) |
| Pattern matching (`match`) | **Complete** | `tests/selfhost/385-literal-in-ctor.ax`, `tests/selfhost/810-struct-variant-pattern.ax`. Constructor patterns (nullary and with-field), variables, wildcards, literals, nested constructor patterns, and tuple/list patterns all compare and bind correctly, plus non-exhaustiveness/arity/undefined-constructor diagnostics. Built-in `Option` type with `Some`/`None` constructors. |
| Lambda / function values | **Complete** | `tests/selfhost/950-multi-param-lambda.ax`. Closure record (code pointer + captures), passed as the callee's hidden first parameter; curried application, closures in `data` fields. A lambda of several parameters IS several lambdas — `(lambda (x y) b)` is `(lambda (x) (lambda (y) b))` — so it can be applied one argument at a time or all at once. Until 2026-08-10 only the one-parameter form existed: two were typed as taking a tuple, which no syntax can supply, and on the paths that got past the checker the emitter dropped the lambda and folded the call to its last argument at exit 0. `tests/stdlib/140-function-values.ax`, `tests/selfhost/950-multi-param-lambda.ax` |
| Lists | **Partial** | Syntax and type checking; runtime representation pending |
| Tuples | **Partial** | Syntax and type checking; codegen pending |
| Type classes | **Replaced** | Renamed to traits; see [Traits](#traits) |
| Unions | **Removed** | C interoperability is not a goal, and an untagged union has no meaning under linear types. Use `data` for a tagged sum or `struct` for a product. `union` stays reserved and reports `AX2004` |
| Struct layout modifiers | **Removed** | `packed`, `repr(C)` and `align(N)` were documented and formatted but never parsed - all three are `AX2001`. C layout has no meaning without C |
| Region syntax | **Removed** | Reclamation is never written by hand as a region annotation — the chosen automatic strategy is reference counting ([docs/memory-model.md](docs/memory-model.md) MM-LIFE-2a). `region` stays reserved and reports `AX2004` |
| Traits | **Functional** | Declarations, implementations (`impl`), and compile-time dispatch on the type of an argument: a call to a trait method resolves to the `impl` for that type and becomes a direct call, with no table and no indirection. Until 2026-08-10 `impl` was consumed as an inert node — its body was never type-checked and its methods were bound to nothing, so the example below was `AX3001 undefined variable eq` on its first use. Supertraits are enforced and default method bodies are generated; what remains is that a function generic over a trait cannot call its methods, because dispatch needs a concrete type at the call site. Every other shape is `AX3025`. `tests/selfhost/970-traits.ax` |
| Effects | **Complete** | `tests/selfhost/820-effect-handlers.ax`, `tests/diagnostics/450-effect-op-arity.ax`. Effect declarations, `handle` expressions, effect checking (`IO`, `Pure`, `Alloc`, `Mut`, `Div`), AXTAG validation. Effects propagate transitively through calls, so a claim on a caller is checked against what its callees do |
| Loops | **Complete** | `tests/selfhost/500-while-mut.ax`. `while` plus `mut` local bindings and `set`; 10⁷ iterations in constant stack at `-O0`. Self tail calls are guaranteed in the IR independently of `--opt`; mutual tail recursion still needs `--opt 1`+ ([docs/memory-model.md](docs/memory-model.md) MM-EXEC-6b/6c). Non-tail recursion is still stack-bounded at 60,000–80,000 frames |
| Linear types | **Parsed only** | `linear T`, `consume`. No longer what the memory model relies on: deterministic reclamation comes from the chosen reference counting without them ([docs/memory-model.md](docs/memory-model.md) MM-LIFE-2a/MM-LIFE-7); what linearity would still buy is retain/release-free moves and early drops |
| Macros | **Partial** | `tests/selfhost/365-macro-pattern-literal.ax`, `tests/selfhost/361-macro-hygiene.ax`. Macros come in two forms: the head-list form, one flat parameter list over one expression template, pure substitution; and the rule form, a list of one or more rules whose parameters are PATTERNS, selected by a match in rule order. This clause read "Single-rule substitution macros" until 2026-08-16, by which point the rule form's multi-rule selection, its patterns and its repetition were all recorded further down this same row — the head-list form stays single-template by decision, because the two forms differ in what a template is. Both expand in their own pass (`self_host/expand.ax`) between import resolution and the checker, so everything a macro generates is type-checked; hygiene by renaming (`<name>.<counter>` gensym) — binder direction complete, and a module-defined macro's template resolves free identifiers at its definition site. `stdlib/Pre.ax` defines `when`, `unless`, `cond2`, `cond3`; cross-module macro import works, `Mod::name` qualification works (a qualified private macro is `AX3023`), an entry-file function outranks an imported macro of the same name, and a diagnostic inside an expansion carries a backtrace naming each enclosing macro with its declaration's own file and span (`tests/diagnostics/490-expansion-backtrace.ax`). Declaration macros v1 (2026-08-14): a rule-form macro — `(macro name ((name p...) decl...))` — invoked in declaration position generates `fn` and `::` declarations and further macro invocations, expanded to a fixpoint before any body is walked, checked and compiled like hand-written code, with parameters substituting in name, type (float flags recomputed) and expression positions (`tests/selfhost/372-decl-macro.ax`, 144; `373-decl-macro-types.ax`, 10); a typo'd declaration keyword is now `AX3027` naming the head instead of a bare `syntax error` that hid every later diagnostic. Invocation is no longer entry-file only (2026-08-15): a module invokes declaration macros over its own declarations, and its products join that module's namespace with the template's `pub` deciding what leaves it — which is what lets a library spend `stdlib/Pre.ax`'s `deriveEq` on its own types (`tests/selfhost/388-module-side-decl-macro.ax`, 239). The `syntax/*` query vocabulary landed the same day — `(syntax/join eq T)` names a generated declaration, `(syntax/constructors T)` and `(syntax/fields S)` answer from the declaration list at expansion time (no user code runs, ever — the vocabulary is closed and compiler-implemented), `(syntax/for (C seq) ...)` splices per element in match-arm, declaration, and argument positions, `(syntax/same f g)` decides a lens's diagonal at expansion time, `(syntax/binders C x)` names a constructor's fields as hygienic pattern binders, and `(syntax/fold && true ...)` chains a comparison over them (zipped in lockstep, the empty fold answering the zero) — which is enough for a working `deriveEq` over any sum type including fieldful constructors, a working `deriveLenses` over any struct, and the `impl`-generating form whose derived instances compose through static trait dispatch — all written as ordinary macros from the spec's worked examples (`tests/selfhost/374-derive-eq.ax`, `375-derive-lenses.ax`, `377-derive-eq-fieldful.ax`, `378-derive-eq-impl.ax`) — and `stdlib/Pre.ax` ships `deriveEq`, which derives over imported types too (`379-derive-imported.ax`). **The query table closed on 2026-08-15**: `(syntax/name C)` answers a constructor's spelling as a `String` and `(syntax/arity C)` its field count as an `Int` — neither is recoverable at run time, where a block records its tag and nothing else — `(syntax/defined n)` answers whether a name is declared and folds the `if` around it at expansion time so the losing branch is deleted rather than compiled, and a join now stands where a *reference* stands, so a macro can call what it names. Each landed with the prelude macro that spends it: `deriveShow`, `deriveArity`, `showOr` (`tests/selfhost/380-syntax-scalar-queries.ax`, 41). **A template may generate types**, not only functions (2026-08-15): `data` and `struct` joined `impl` on the template surface, a constructor's name is a name position so `(syntax/join Off N)` names one, two invocations of one macro give two distinct types, and a type generated in a round is queryable in that same round — `deriveEq` derives over a type a macro invented (`tests/selfhost/381-macro-type-templates.ax`, 32). **The iteration form's last two gaps closed on 2026-08-15**: several sequences zip in lockstep in every position `syntax/for` owns — `(syntax/for ((C (syntax/constructors T)) (D (syntax/constructors U))) ...)` converts one enumeration into a parallel one, and a length mismatch is `AX3028` rather than a truncation (`tests/selfhost/386-syntax-parallel-for.ax`, 63) — and a join may nest, so a generated name carries more than two parts: with two, a lens set over two structs sharing a field name generated `getX` twice and the program was `AX3006` (`tests/selfhost/387-syntax-nested-join.ax`, 47). `type` and `effect` joined the template surface the same day, which closes MAC-CAP-8's kind list: a macro generates a type alias and an effect declaration, names both from its arguments, and a joined name is writable in TYPE position so the signature beside a generated alias can name it (`tests/selfhost/389-type-effect-templates.ax`, 38). `import` and nested `macro` refuse by decision, because each would reopen a phase that has already run. **Multi-rule declaration macros landed 2026-08-15**: a rule-form macro is a list of rules and the invocation's ARITY selects one, two rules of one arity are refused at the macro's line, and an invocation matching none names every arity the macro offers (`tests/selfhost/390-multi-rule-macro.ax`, 51). **And on 2026-08-16 the rules stopped being chosen by counting**: a rule's parameters are PATTERNS (MAC-LANG-15) — a binder, `_`, an int/float/char/string literal, or a parenthesised form of patterns — and selection is a match tried in rule order, first match winning (MAC-LANG-18), so three rules of one arity told apart by shape are ordinary (`tests/selfhost/392-macro-patterns.ax`, 127; the compiler before it refuses the file at the first pattern's paren). Both refusals around it were re-derived rather than carried over: the "two rules of one arity" test narrowed to *unreachability* — an earlier all-binder rule of that arity starves the later one — and took its own code (`AX3033`) because a repeated PARAMETER and an unreachable RULE are not the same claim, and the no-match diagnostic names every SHAPE (`(defN (a b))` or `(defN T 7)`) where it used to name arities. **Repetition followed the same day** (MAC-LANG-16 v1): a rule's last element may REPEAT — `(build T v ...)` takes one argument and then any number, `v` binds all of them at once, and `(T v ...)` splices them — so one rule generates a two-field constructor call and a three-field one (`tests/selfhost/393-macro-ellipsis.ax`, 63). That is the variadic macro the language did not have. Its token half cost ONE implementation and not the four the spec predicted: `...` lexes as an ordinary identifier, three dots and no new token kind, so the formatter needed nothing and tree-sitter already parsed it. Breaking the depth rule — a repeating name used without `...`, `...` after something that does not repeat, two `...` in one rule, or a repeat over a pattern rather than a bare name — is `AX3034` in four shapes, split by whether the author can act at the macro or at the invocation. What patterns still do NOT do is dispatch on a head's *spelling* (literal identifiers, which need scope sets), which is the last of the spec's four dispatch axes. It is not the only thing that spec's `simplify` table needs, and this row claimed it was on the day the table's own section itemised otherwise: `(- e e)` wants a repeated binder read as a same-form test, which `MAC-LANG-15` refuses as last-wins (`AX3020`); `(f a ...)` wants a repeat INSIDE a nested pattern, which v1's rule-final repeat does not reach (`AX3034`); and its templates are expressions, which the rule form does not take. **And the last documented hygiene hole closed on 2026-08-16** — MAC-HYG-8 is done, all four. An entry-file macro's free identifier shadowed at the invocation used to compute with the local binding at exit 0 — 0 where the macro's own function answers 40 — then refused, and now resolves. The spec said this needed scope sets, an identifier becoming a `(name, scopes)` pair; it needed one bit of that and no representation change, because a macro is a top-level declaration and its template's free identifiers therefore have exactly one definition scope. Both resolvers had to learn it: with only the checker taught, the program type-checked against the macro's function and the emitter still called the local (`tests/selfhost/394-macro-entry-capture.ax`, 130). `AX3032` would now reject correct programs, so it is retired and out of the registry — the number burned, never reused. **The hole beside it closed outright on 2026-08-16**: a template naming something the macro's module merely *imported* used to stay bare and mean whatever the call site could see, and now resolves to the module that declares it — the spec had recorded this as blocked on import edges the merged declaration list does not carry, and it needs none, because every declaration in that list carries the module it came from (`tests/selfhost/391-macro-imported-name.ax`, 31; the compiler before it answers 13 with the capture term removed). Two modules declaring the name is an ambiguity the rewrite has no right to settle, so it leaves the name bare and the invocation reports `AX3014` carrying the expansion frame (`tests/diagnostics/595-macro-imported-ambiguous.ax`). This row closed with "no patterns and no repetition yet" until 2026-08-16, by which point two sentences above it had recorded both landing — the spec is [docs/macro-system.md](docs/macro-system.md). This row read "**Complete** — … hygiene (scope sets + gensym) … expansion backtrace on diagnostics" until 2026-08-14, and every clause of that was false then: the mechanism is renaming, not scope sets, and the backtrace field was populated by nothing — the real backtrace landed the same day the row was corrected. **And the hole none of that had noticed closed on 2026-08-16** (MAC-HYG-10): a macro parameter standing in a BINDER position was renamed like a template's own binder, so `(macro (bind! x e body) (let ((x e)) body))` bound `x.N` and spliced a body that still said `v` — `AX3001`, on the macro whose whole job is to bind it. It blocked **every binding form the language could have** — `let*`, `for`, `with`, `try!` — and it hid behind the case that works: when a template binds and reads through the SAME parameter the rename table maps both sides to the gensym and the answer is right for the wrong reason, with the caller's name appearing nowhere. Only a macro taking a separate body could see it, and `stdlib/Pre.ax`'s are all single-expression templates, so none did. A parameter in binder position now takes the argument's name across all three positions the expander owns — `let`, `lambda` parameters, pattern binders — and an argument that is not a name is `AX3035` rather than the silent wrong expansion it used to be (`tests/diagnostics/590-macro-binder-target.ax`; `tests/stdlib/371-err-module.ax` is the first program that depends on the rule and does not compile without it). "Binder direction complete", four sentences above, meant the direction anyone had tested |
| Concurrency | **Library** | No language support and no compiler change: `stdlib/Job.ax` is a bounded pool of child processes over `Sys`'s existing `sysSpawn`/`sysWaitPid` pair, answering in submit order. Processes rather than threads, because a freestanding binary cannot create an OS thread on macOS. See [docs/v1-roadmap.md §4.4](docs/v1-roadmap.md) |
| Editor support | **Functional** | [tree-sitter grammar](tree-sitter-axiom/) with highlighting queries, gated against all 434 `.ax` files in the repo and a 37-case tree-shape corpus. The language server is `self_host/lsp.ax`, listed in the [Compiler structure](#compiler-structure) table above among *The tools*, and gated by `scripts/check-lsp-selfhost.sh` (this row said "four rows above" until 2026-08-16, and no row of THIS table has ever named it); it answers go-to-definition and hover for macro invocations (2026-08-15), both from the raw parse tree with no expansion |
| Imports | **Functional** | `(import Mod.Sub ...)` resolves and merges declarations from other files; qualified access via `Mod::name` disambiguates; see [Modules and imports](#modules-and-imports) |
| Module visibility | **Complete** | `pub` on a declaration, or an import's name list, decides which names are visible outside a module — not which declarations exist. A module keeps its private helpers and behaves identically however it is imported; naming one from outside is `AX3023`. An import's name list is itself checked since `6a28103`: `(import M (noSuch))` is `AX3023`. `tests/selfhost/920-private-declaration.ax`, `930-selective-import.ax` |

---

## Error Messages

The default render is rustc-flavored: the offending line is quoted, the
exact span is underlined and labelled, and the header carries a stable
code you can look up. Given `err.ax`:

<!-- doc-gate:source err.ax -->
```scheme refused
(:: main Int)
(fn (main)
  (if true (+ 1 2) false))
```

<!-- doc-gate:render err.ax human -->
```
error[AX3004]: type mismatch: expected Int, found Bool
 --> err.ax:3:20
  |
3 |   (if true (+ 1 2) false))
  |                    ^^^^^ this has type `Bool`, expected `Int`
  |
  = help: run `axiom explain AX3004` for a full explanation

compilation failed due to 1 previous error
```

**The real output is coloured** — severity and carets in the severity's
colour, the gutter blue, the `= help:` marker green — and always is,
including when stderr is redirected. It is shown plain here because a
markdown code fence is not a terminal. The palette is one table in
`self_host/style.ax`.

Codes are namespaced by pipeline stage — `AX1xxx` lexer, `AX2xxx`
parser, `AX3xxx` semantics, `AX4xxx` codegen, `AX5xxx` modules — and are
stable across wording changes, so they can be grepped and matched on.
`axiom explain --list` prints them all.

A report with more than one span quotes each of them, eliding the lines
in between rather than printing them. Given `count.ax`:

<!-- doc-gate:source count.ax -->
```scheme refused
(:: main Int)
(fn (main)
  (let ((x 0))
    {
      (set x 1)
      x
    }))
```

<!-- doc-gate:render count.ax human -->
```
error[AX3012]: cannot assign to immutable binding `x`
 --> count.ax:5:12
  |
3 |   (let ((x 0))
  |          - `x` is bound here
...
5 |       (set x 1)
  |            ^ `x` cannot be assigned
  |
  = help: declare it mutable: `(mut x ...)` ~> mut x
  = help: only a binding introduced by `(let ((mut x ...)) ...)` may be the target of `set`
  = help: run `axiom explain AX3012` for a full explanation

compilation failed due to 1 previous error
```

Columns count characters, not bytes, so a caret under a line containing
an em dash lands where the eye expects; tabs expand to the next multiple
of four; and a line wider than 160 columns is quoted as a window, marked
`...` on whichever side was elided.

### For agents and tooling

`--diagnostic-format=ai` renders the same diagnostic as **AXDL**: one
dense, colourless, greppable line per diagnostic — no re-printed source,
no box drawing, so `grep -c '^E '` counts errors and nothing needs a
multi-line state machine.

<!-- doc-gate:render err.ax ai -->
```
E AX3004 err.ax:3:20-25 type-mismatch "type mismatch: expected Int, found Bool" #"this has type `Bool`, expected `Int`"
compilation failed due to 1 previous error
```

Every fact the diagnostic carries is on that one line — the primary
label, every related span, every note and every help. What is *not*
there is the `run axiom explain AX####` footer, which the human render
adds for a reader who wants prose. Where a fix is machine-applicable it
travels with the diagnostic as `<loc>:"<msg>"~>"<replacement>"`, so a
tool can apply it with a byte-range substitution instead of parsing
English — `count.ax` above, in AXDL:

<!-- doc-gate:render count.ax ai -->
```
E AX3012 count.ax:5:12-13 assign-to-immutable "cannot assign to immutable binding `x`" #"`x` cannot be assigned" ^3:10-11:"`x` is bound here" ?3:10-11:"declare it mutable: `(mut x ...)`"~>"mut x" ?"only a binding introduced by `(let ((mut x ...)) ...)` may be the target of `set`"
compilation failed due to 1 previous error
```

Reading order is fixed: severity, code, file and span, slug, message,
then the primary label `#`, related spans `^`, notes `!`, helps `?`, and
macro-expansion frames `&`. `--diagnostic-format=json` emits the same
facts as JSON Lines where a parser is easier than a grammar.

Every block above is real compiler output, re-rendered and compared by
`scripts/check-doc-drift.sh` on every run. See
[docs/diagnostics.md](docs/diagnostics.md) for the full grammar.

---

## Project structure

```
axiom/
├── self_host/          # The compiler, written in Axiom
├── bootstrap/          # Its own LLVM IR, one file per target — how a clean
│                       # checkout builds a compiler without one
├── stdlib/             # Standard library, written in Axiom
├── tree-sitter-axiom/  # Editor grammar, queries, corpus
├── tests/stdlib/       # Golden tests: compiled, run, output compared
├── tests/selfhost/     # Conformance cases: compiled, run, exit status checked
├── tests/diagnostics/  # AXDL and human-render goldens, per diagnostic code
├── tests/{fmt,repl,lsp,tools}/  # Goldens for each tool surface
├── scripts/            # The gates — each one is what CI runs
└── docs/               # reference.md, memory-model.md, macro-system.md, diagnostics.md, self-hosting.md, v1-roadmap.md
```

Every CI gate is a script in `scripts/`, so a contributor runs locally
exactly what CI runs:

```bash
./scripts/bootstrap-from-seed.sh     # seed -> stage1 -> stage2 == stage3
./scripts/run-stdlib-tests.sh        # stdlib, compiled and run
./scripts/check-self-host.sh         # conformance suite under the Axiom compiler
./scripts/check-bootstrap.sh         # the same ladder, driven by the compiler itself
./scripts/check-freestanding.sh      # no libc in the IR or the binary
./scripts/check-cross-targets.sh     # every target assembles, at -O0 and -O2,
                                     # with no PIE-hostile relocations
./scripts/check-reproducible.sh      # two runs produce identical IR
./scripts/check-tree-sitter.sh       # grammar accepts every .ax in the repo
```

`check-tree-sitter.sh` needs the tree-sitter CLI
(`npm install --prefix tree-sitter-axiom tree-sitter-cli`) and *fails*
without it rather than skipping — set `AXIOM_TREE_SITTER_OPTIONAL=1` to
skip deliberately. It used to exit 0 when the CLI was absent, which
meant it reported success without checking anything.

The relocation gate can check itself, because a gate whose verdict is
never tested is how a broken one goes unnoticed:

```bash
./scripts/check-cross-targets.sh --self-test   # the relocation rules, on known input
```

And a measurement rather than a gate — wall-clock against Rust's
equivalent data structures, since a timing threshold on a shared CI
runner is a flaky test:

```bash
./scripts/bench-datastructures.sh              # Vec/Map/Intern vs Rust
./scripts/bench-datastructures.sh --fx --check # fast hasher, enforce the 2x bound
```

---

## Roadmap

[docs/v1-roadmap.md](docs/v1-roadmap.md) is the plan to v1: what is done,
what is left, and — the part that determines the schedule — which items
actually block which. The headline result is that most of the remaining
work is *not* parallelizable: the macro system and the LSP both depend on
the memory model, and the LSP depends on self-hosting. It also records
what v1 is *not*: HTTP is out of scope for the standard library
(§4.5) — the core owes an external package non-blocking sockets, and
nothing above them. Both of the roadmap's open designs are now decided and
specified as normative documents — and both have since shipped past
the line this paragraph drew, which read "reference counting, behind a
measured pointerhood prerequisite" and "substitution macros shipped,
patterns and `derive` specified" until 2026-08-16. The memory model
([docs/memory-model.md](docs/memory-model.md)) is reference counting,
and its pointerhood prerequisite is *discharged*: the `String`/`Int`
fiat is gone, blocks carry a count and a shape word, and dead blocks
are freed — what remains are the two ownership events that need an
escape analysis. The macro system
([docs/macro-system.md](docs/macro-system.md)) has shipped `derive`
into `stdlib/Pre.ax` and the pattern language into the rule form;
what is still only specified is dispatch on a head's *spelling*,
which needs scope sets.

[docs/self-hosting.md](docs/self-hosting.md) is the record of replacing
the Rust compiler with one written in Axiom — the measured gap analysis
that started it, and the working notes of every slice that closed a gap.

---

## License

MIT
