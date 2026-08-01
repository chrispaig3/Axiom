# Axiom

<img width="1500" height="1024" alt="Image" src="https://github.com/user-attachments/assets/38a9afb6-3570-4797-ba57-488e004f4e66" />

A functional systems programming language for humans and agents.
Axiom blends the expressive power of functional programming with the performance and control of systems languages. It uses a clean Lisp‑style S‑expression syntax, a Hindley–Milner‑inspired type system, and an LLVM backend to produce fast, native executables — without a VM, runtime, or garbage collector.

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
- **AXTAG** — Source-embedded agent metadata via `;@axiom:<key>(<value>)` comments above declarations. The compiler validates these (e.g., `effect(io)` claims are checked against actual foreign calls), so agents can annotate intent and trust the compiler to verify it.

---

## Installation

### Prerequisites

- **Rust 1.70+** — to build the compiler
- **LLVM** — `llc` must be on your PATH (for code generation)
- **A C compiler** — `cc`, `clang`, or `gcc` on your PATH (for final linking)

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
cargo build --release
```

The binary is at `./target/release/axiom`.

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
    (println (strFromLit (__addr "Hello, Axiom!")))
    0
  })
```

`IO` is part of Axiom's own standard library - the compiled binary calls
no C function at all. The `;@axiom:effect(io)` tag is checked: the
compiler verifies that `main` really does perform I/O, and would reject
the claim if it did not.

Run it:
```bash
./target/release/axiom run hello.ax
```

Compile it:
```bash
./target/release/axiom build --input hello.ax --output hello
./hello
```

### How Axiom works

Every Axiom program needs a `main` function that returns `Int`. The compiler pipeline:

```
Source (.ax) → Lexer → Parser → Type Checker → IR → LLVM IR → llc → cc → Executable
```

### A larger example

[game_of_life/](game_of_life/) is Conway's Game of Life in pure Axiom: the
biggest Axiom program in the tree, and the one that shows what the language
can and cannot do today. Life is Turing-complete, so a working
implementation settles that Axiom can express arbitrary computation — and
because Axiom has no loop form, no mutable locals, and no closures that
survive code generation, it has to do so with recursion over immutable
algebraic data and nothing else.

```bash
AXIOM_STDLIB=stdlib ./target/release/axiom run game_of_life/main.ax
```

Its README records the measurements, including the allocator behaviour that
drives the [v1 roadmap](docs/v1-roadmap.md), and the two bugs that the
demo's position-sensitive board digest caught but a population count would
not have.

---

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
(fn (verbose-add x y)
  { (printf "adding %d + %d\n" x y)
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
  (printf "Starting...\n")
  (printf "Working...\n")
  0
}
```

The value of a brace block is the value of its last expression. Single expressions in braces are unwrapped automatically — `{ 42 }` is just `42`.

Function bodies, `let` bodies, `if` branches, and `lambda` bodies also support implicit sequencing without braces:

```scheme
(fn main
  (printf "Starting...\n")
  (printf "Working...\n")
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

Every value of a `data` type - nullary constructors like `Nothing` included -
is a heap-allocated, tagged block: word `0` is an integer tag identifying
which constructor built it, and words `1..` are its fields, one 8-byte word
each. This one uniform representation (rather than, say, an unboxed integer
for nullary constructors and a pointer for everything else) is what lets
`match` compare *any* constructor pattern against *any* value of that type
the same way, and it's what makes recursive types - `List`, `Tree` - work
with no special-casing at all: a field that's itself another `data` value
is just another 8-byte word holding that value's own heap address.

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

Current limitations, honestly stated:

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
- There is no garbage collection or reference counting: every constructor
  application `malloc`s and nothing ever `free`s it. Fine for short-lived
  CLI programs and this README's examples; not something to build a
  long-running server on yet.
- Struct **field access** (`.field`-style reads) still has no expression
  syntax at all, independent of `data` - see the Structs section below for
  what does and doesn't work there.

### Structs

Products of named fields:

```scheme
; Basic struct
(struct Point
  (x : Int)
  (y : Int))

; Packed (no padding)
(struct PackedPoint packed
  (x : Int)
  (y : Int))

; C-compatible layout
(struct CPoint repr(C)
  (x : I32)
  (y : I32))

; Aligned to 16 bytes
(struct AlignedData align(16)
  (data : I64))
```

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

; A trait with multiple methods and supertraits
(trait (Ord a)
  (Eq a)
  where
    (cmp :: (-> a a Int))
    (lt :: (-> a a Bool))
    (gt :: (-> a a Bool))))
```

Implement a trait for a specific type:

```scheme
(impl (Eq Int)
  where
    ((eq (lambda (x y) (== x y)))))

(impl (Ord Int)
  where
    ((cmp (lambda (x y) (if (== x y) 0 (if (< x y) (- 0 1) 1)))))
    ((lt (lambda (x y) (< x y))))
    ((gt (lambda (x y) (> x y))))))
```

Traits support:
- **Type parameters** — `(trait (Eq a) ...)` binds `a` for all method signatures
- **Supertraits** — `(trait (Ord a) (Eq a) ...)` requires `Eq` to be implemented too
- **Default methods** — `(where (method :: type = default_body))`
- **Effects** — traits and methods can carry effect annotations

### Effects

Axiom tracks side effects at the type level. Effects are checked by the compiler, so you know exactly what a function does.

Built-in effects:

| Effect | Meaning |
|---|---|
| `IO` | Calls foreign functions (C FFI) |
| `Pure` | No side effects |
| `Alloc` | Heap allocation (`alloc`) |
| `Mut` | Mutable state (`set-field`) |
| `Div` | Divergence (infinite loops) |

Declare an effect type:

```scheme
(effect Console
  (print :: (-> String ())))
```

Annotate a function with its effects using AXTAG metadata:

```scheme
;@axiom:effect(io)
(fn main (printf "hello"))
```

The compiler validates that the body actually performs the declared effects.

Handle effects with `handle`:

```scheme
(handle body (effects...) handler)
```

`handle` runs `body`, intercepting the declared `effects` via `handler`. Effects not listed propagate out.

```scheme
; A handler that catches IO and returns a default value
(handle (printf "hello") (IO) 0)
```

Effect annotations are also supported on traits and implementations:

```scheme
(trait (Console a)
  where
    (print :: (-> String a)))

(impl (Console IO)
  where
    (print (lambda (s) (printf "%s\n" s))))
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
| `String` | String (pointer) | `ptr` |
| `Unit` / `()` | Unit (no value) | `void` |
| `Void` | Void | `void` |
| `Any` | Generic pointer | `ptr` |

### Sized integers and floats

| Type | Size |
|---|---|
| `I8`, `I16`, `I32`, `I64`, `I128` | Signed integers |
| `U8`, `U16`, `U32`, `U64`, `U128` | Unsigned integers |
| `Isize`, `Usize` | Pointer-sized integers |
| `F32`, `F64` | Floating point |

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
(cast I32 someInt)
```

---

## Standard library

Axiom ships a standard library written **in Axiom**. It reaches the
operating system through raw syscalls, not through C, so a compiled
Axiom program contains no call to libc - not for printing, not for
allocation, not for file I/O. `foreign` bindings still work and are
still supported (see
[Foreign Function Interface](#foreign-function-interface)), but nothing
in the standard library needs them.

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (strFromLit (__addr "hello, world")))
    (printlnInt 42)
    (println (strConcat (strFromLit (__addr "sum=")) (fmtInt (+ 1 2))))
    0
  })
```

### Modules

| Module | Provides |
|---|---|
| `Pre` | `when`, `unless`, `cond2`, `cond3` (conditional macros) |
| `Mem` | `memAlloc`, `memCopy`, `memSet`, `memCmp`, `memGetByte`/`memPutByte`, `memGetWord`/`memSetWord` |
| `Str` | `strFromLit`, `strAlloc`, `strLen`, `strByte`, `strCmp`, `strEq`, `strSlice`, `strDup`, `strConcat`, `strFindByte`, `strStartsWith`, `strCStr` |
| `Vec` | `vecNew`, `vecPush`, `vecPop`, `vecGet`, `vecSet`, `vecLen`, `vecCap`, `vecReserve`, `vecClear` |
| `Map` | `mapNew`, `mapHas`, `mapGet`, `mapInsert`, `mapRemove`, `mapLen`, `mapCap`, `mapNew`, `mapRehash` (open-addressing `Int→Int` hash map) |
| `Fmt` | `fmtInt`, `fmtHex`, `fmtPadLeft`, `fmtIntWidth` |
| `Intern` | `internNew`, `internIntern`, `internFind`, `internLookup`, `internCount` (string interner) |
| `Sys` | `sysWriteFd`, `sysReadFd`, `sysOpenPath`, `sysCloseFd`, `sysSeek`, `sysExitWith`, `sysFailed`, `sysErrno`, `stdin`/`stdout`/`stderr` |
| `IO` | `print`, `println`, `printLit`, `printlnLit`, `printInt`, `printlnInt`, `eprint`, `eprintln`, `writeStr`, `readUpTo`, `readAll`, `readFile`, `readFileLit`, `exit`, `die` |

A `Str` is a length-prefixed, NUL-terminated string: slicing shares
storage, and `strCStr` hands the bytes to a syscall without copying.

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

Axiom has no loop construct: iteration is written as recursion. At
`--opt 0` (the default) each iteration costs a stack frame, which caps
loops at a few hundred thousand iterations. `--opt 1` and above run
LLVM's mid-level passes, which turn self-tail-recursion into a real
loop:

```bash
axiom build --input main.ax --output main --opt 2
```

Use `--opt 2` for anything that iterates over a large input. Non-tail
recursion remains bounded by the stack either way.

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
    (println (strFromLit (__addr "a literal")))
    (printlnInt 42)
    (println (strConcat (strFromLit (__addr "formatted: ")) (fmtInt 42)))
    0
  })
```

No `foreign` binding and no `printf`: `IO` is Axiom code over the
syscall primitives.

### Read a file

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((contents (readFileLit (__addr "input.txt"))))
    {
      (printlnInt (strLen contents))
      (print contents)
      0
    }))
```

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

Split a program across files with `(import Mod.Sub ...)`:

```scheme
; Math/Ops.ax
(:: square (-> Int Int))
(fn (square x) (* x x))
```

```scheme
; main.ax
(import Math.Ops (square))       ; only bring in `square`
; (import Math.Ops)               would bring in every top-level decl

(:: main Int)
(fn main (square 5))
```

```bash
./target/release/axiom run main.ax
```

How it works:

- A dotted module path maps directly to a file path: `Math.Ops` resolves
  to `Math/Ops.ax`, **always relative to the entry file's own directory**
  (the file you passed to `check`/`build`/`run`/`emit-llvm`) - not to
  whichever file happens to contain the `(import ...)`, so a deeply nested
  module can still `(import Math.Ops)` using the same path the entry file
  would.
- `(import Mod.Sub)` with no name list brings in every top-level
  declaration from that file; `(import Mod.Sub (a b))` brings in only the
  named declarations (functions, `data`/`struct`/`type` decls,
  `foreign` bindings, ...).
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
./target/release/axiom check source.ax

# Compile to a native executable
./target/release/axiom build --input source.ax --output program

# Emit LLVM IR to stdout
./target/release/axiom emit-llvm source.ax

# Emit LLVM IR to a file
./target/release/axiom emit-llvm source.ax -o output.ll

# Compile and run immediately
./target/release/axiom run source.ax

# Start interactive REPL
./target/release/axiom repl

# Look up a diagnostic code
./target/release/axiom explain AX3001

# Render diagnostics in Axiom's AI-optimized notation (see docs/diagnostics.md)
./target/release/axiom --diagnostic-format=ai check source.ax

# List every top-level symbol (functions, types, constructors, structs,
# aliases, traits, ...) and its type/shape in Axiom's AI-optimized
# "AXSYM" notation (see docs/diagnostics.md); resolves (import ...) too, and
# attributes each symbol to the file that actually declared it
./target/release/axiom --diagnostic-format=ai symbols source.ax

# Same, but also include the dozen always-in-scope built-in operators
# (omitted by default to keep output minimal)
./target/release/axiom --diagnostic-format=ai symbols source.ax --builtins
```

See [`docs/diagnostics.md`](docs/diagnostics.md) for the full agent-facing
notation architecture: stable error codes (`AX####`), cascade suppression,
the human report format, the AI-optimized "AXDL" diagnostic notation, and
the AI-optimized "AXSYM" symbol/type notation.

---

## REPL

The REPL compiles expressions to native code — it doesn't interpret them. This means you get real performance even in interactive mode.

```bash
./target/release/axiom repl
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

## Foreign Function Interface

Axiom does not *need* C for standard-library work any more - see
[Standard library](#standard-library) - but it can still call any C
function. Declare it with `foreign`:

```scheme
(foreign name :: (-> ReturnType Param1 Param2 ...) = "c_symbol_name")
```

Examples:

```scheme
; printf from stdio.h
(foreign printf :: (-> String Int) = "printf")

; malloc from stdlib.h
(foreign malloc :: (-> Int (* Any)) = "malloc")

; A custom C function
(foreign my_c_function :: (-> Int String Int) = "my_c_function")
```

The string after `=` is the symbol name as it appears in the C library. For most C library functions, this is the same as the Axiom name.

When compiling, you may need to link additional libraries:

```bash
cc output.o -lcurl -lssl -lcrypto -o program
```

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

### Crate structure

| Crate | Purpose |
|---|---|
| `axiom-ast` | AST, token, and span definitions |
| `axiom-lexer` | Tokenizer |
| `axiom-parser` | S-expression parser |
| `axiom-sema` | Two-pass type checker |
| `axiom-ir` | IR definitions and generator |
| `axiom-codegen` | LLVM IR emitter |
| `axiom-cli` | CLI and REPL |
| `axiom-errors` | Error types with pretty diagnostics |

---

## Implementation Status

| Feature | Status | Notes |
|---|---|---|
| Functions & types | **Complete** | Curried, polymorphic signatures, proper return values |
| Operators (prefix) | **Complete** | All arithmetic, comparison, logical (`+`, `-`, `*`, `/`, `%`, `==`, `!=`, `<`, `>`, `<=`, `>=`, `&&`, `\|\|`) |
| Let bindings | **Complete** | Variable resolution, sequential evaluation |
| if expressions | **Complete** | Proper branching with result values |
| begin blocks | **Removed** | Replaced by `{ }` brace blocks and implicit sequencing |
| brace blocks | **Complete** | `{ expr1 expr2 ... }` — modern sequencing, returns last value |
| fn keyword | **Complete** | Modern alias for `define` |
| FFI | **Complete, no longer required** | Call any C function with `foreign` declarations. The standard library no longer uses it: see [Standard library](#standard-library) |
| Standard library | **Functional** | `Pre`, `Mem`, `Str`, `Vec`, `Map`, `Fmt`, `Intern`, `Sys`, `IO`, written in Axiom over syscall primitives |
| Syscalls | **Complete** | `__syscall0`-`__syscall6` on Darwin and Linux, x86-64 and AArch64; errors normalised to `-errno` on every platform |
| Allocation | **Functional, unbounded** | `mmap`-backed bump allocator emitted by the backend, overridable by defining `axiom_alloc`. No `free` - memory is reclaimed at process exit, so memory use tracks *total* allocations rather than live data. Measured at 76,000x the live set for a 2000-generation loop; see [game_of_life/README.md](game_of_life/README.md) and the memory model design in [docs/v1-roadmap.md](docs/v1-roadmap.md) |
| Cross-compilation | **Functional** | `--target` selects ABI and platform stdlib modules; codegen verified for all four targets |
| Self-hosting | **In progress** | Foundations landed; see [docs/self-hosting.md](docs/self-hosting.md) for the measured gap analysis and plan |
| ADTs / data types | **Complete** | Constructors (nullary and with fields, including recursive types like `List`/`Tree`) compile to heap-boxed tagged values; see [Algebraic data types](#algebraic-data-types-how-they-actually-run) |
| Structs | **Complete** | Declarations, LLVM emission, field access (`.field`), struct construction (`(StructName expr1 expr2 ...)`), `mut` fields, and field mutation (`(set-field expr field value)`) all work |
| Pattern matching (`match`) | **Complete** | Constructor patterns (nullary and with-field), variables, wildcards, literals, nested constructor patterns, and tuple/list patterns all compare and bind correctly, plus non-exhaustiveness/arity/undefined-constructor diagnostics. Built-in `Option` type with `Some`/`None` constructors. |
| Lambda | **Partial** | Parsed and type-checked; codegen pending |
| Lists | **Partial** | Syntax and type checking; runtime representation pending |
| Tuples | **Partial** | Syntax and type checking; codegen pending |
| Type classes | **Replaced** | Renamed to traits; see [Traits](#traits) |
| Unions | **Removed** | C interoperability is not a goal, and an untagged union has no meaning under linear types. Use `data` for a tagged sum or `struct` for a product. `union` stays reserved and reports `AX2004` |
| Region syntax | **Removed** | Allocation lifetime is inferred, not written by hand. `region` stays reserved and reports `AX2004` |
| Traits | **Complete** | Declarations, supertraits, effects, default methods, implementations (`impl`) |
| Effects | **Complete** | Effect declarations, `handle` expressions, effect checking (`IO`, `Pure`, `Alloc`, `Mut`, `Div`), AXTAG validation. Effects propagate transitively through calls, so a claim on a caller is checked against what its callees do |
| Loops | **Missing** | Iteration is recursion; `--opt 1`+ turns tail recursion into a loop, and without it deep loops exhaust the stack |
| Linear types | **Parsed only** | `linear T`, `consume`. The ownership facts they express are what the planned memory model needs; see [docs/v1-roadmap.md](docs/v1-roadmap.md) |
| Macros | **Complete** | Pattern-substitution expansion before sema with hygiene (scope sets + gensym); `stdlib/Pre.ax` defines `when`, `unless`, `cond2`, `cond3`; cross-module macro import works; expansion backtrace on diagnostics |
| Concurrency | **Delegated** | Not a native feature; external/third-party library concern. The memory model (arena inference, linear types) provides the safety foundation. Design in [docs/v1-roadmap.md §4.4](docs/v1-roadmap.md) |
| Editor support | **Functional** | [tree-sitter grammar](tree-sitter-axiom/) with highlighting queries, verified against every `.ax` file in the repo. No LSP yet |
| Imports | **Functional** | `(import Mod.Sub ...)` resolves and merges declarations from other files; qualified access via `Mod::name` disambiguates; see [Modules and imports](#modules-and-imports) |

---

## Error Messages

Axiom uses pretty diagnostics with source snippets:

```
Error: Type error: expected Int, found Bool
  ╭─[source.ax:5:10]
  │
5 │   (if x (+ 1 2) "wrong")
  │          ───┬──
  │             ╰──── expected Int, found Bool
──╯
Help: Both branches of `if` must have the same type.
```

---

## Project structure

```
axiom/
├── axiom-ast/          # AST, token, and span definitions
├── axiom-lexer/        # Tokenizer
├── axiom-parser/       # S-expression parser
├── axiom-sema/         # Name resolution, type checking, effects
├── axiom-ir/           # IR definitions and lowering
├── axiom-codegen/      # LLVM emission, target/syscall ABI
├── axiom-cli/          # Driver, REPL, `fmt`, `symbols`
├── axiom-errors/       # Diagnostics, AXDL/AXSYM rendering
├── stdlib/             # Standard library, written in Axiom
├── game_of_life/       # Turing-completeness proof and memory profile
├── tree-sitter-axiom/  # Editor grammar, queries, corpus
├── tests/stdlib/       # Golden tests: compiled, run, output compared
├── scripts/            # CI gates, each runnable locally
├── docs/               # diagnostics.md, reference.md, self-hosting.md, v1-roadmap.md
└── Cargo.toml          # Workspace manifest
```

Every CI gate is a script in `scripts/`, so a contributor runs locally
exactly what CI runs:

```bash
cargo test --release --all           # unit, integration, golden suites
./scripts/run-stdlib-tests.sh        # stdlib, compiled and run
./scripts/check-freestanding.sh      # no libc in the IR or the binary
./scripts/check-cross-targets.sh     # every target assembles, at -O0 and -O2,
                                     # with no absolute relocations
./scripts/check-reproducible.sh      # two runs produce identical IR
./scripts/check-game-of-life.sh      # the demo, against golden output
./scripts/check-tree-sitter.sh       # grammar accepts every .ax in the repo
```

---

## Roadmap

[docs/v1-roadmap.md](docs/v1-roadmap.md) is the plan to v1: what is done,
what is left, and — the part that determines the schedule — which items
actually block which. The headline result is that most of the remaining
work is *not* parallelizable: the macro system, the HTTP
library, and the LSP all depend on the memory model, and the LSP depends on
self-hosting.

[docs/self-hosting.md](docs/self-hosting.md) is the measured gap analysis
for replacing the Rust compiler with one written in Axiom.

---

## License

MIT
