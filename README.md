# Axiom

<img width="1500" height="1024" alt="Image" src="https://github.com/user-attachments/assets/38a9afb6-3570-4797-ba57-488e004f4e66" />

A functional systems programming language for humans and agents.
Axiom blends the expressive power of functional programming with the performance and control of systems languages. It uses a clean Lisp‑style S‑expression syntax, a Hindley–Milner‑inspired type system, and an LLVM backend to produce fast, native executables — without a VM, runtime, or garbage collector.

Axiom is intentionally small, explicit, and transparent. It’s designed not only for developers, but also for agentic programming, where AI systems generate, analyze, and manipulate code. Its uniform structure and predictable semantics make it uniquely easy for agents to understand and work with.

Co‑authored with Qwen3.6 Plus, Axiom explores a new frontier: languages built with AI, and built for AI‑assisted development.

---

## Why Axiom?

| If you like... | Axiom gives you... |
|---|---|
| **Rust's safety** | A strong static type system with algebraic data types, pattern matching, and no null pointers — but with simpler syntax and faster compilation |
| **C's simplicity** | Direct FFI to C libraries, manual memory control via `malloc`/`free`, and predictable performance — without the decades of legacy baggage |
| **Python's expressiveness** | First-class functions, lambdas, and a REPL that compiles to native code — not interprets |
| **Go's pragmatism** | A small, learnable language with a single compilation step — no crazy build systems, no messy dependency managers, no toolchain sprawl |
| **Haskell's elegance** | Curried functions, polymorphic data types, and a clean mathematical foundation — without the 30-minute compile times |

### What makes Axiom different

- **S-expression syntax** — Code is data. Every program is a tree of lists. This makes macros, code generation, and AST manipulation trivial.
- **Prefix operators** — `(+ x y)` instead of `x + y`. Operators are just functions. Uniform syntax means fewer parsing edge cases.
- **LLVM native compilation** — Programs compile to machine code, not bytecode. No VM, no JIT overhead, no runtime.
- **Work-in-progress ambition** — The parser already recognizes effects, regions, linear types, and type classes. The foundation is being laid for a language that can express memory safety, effect tracking, and zero-cost abstractions — all at the type level.

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
(foreign printf :: (-> String Int) = "printf")

(:: main Int)
(fn main
  (printf "Hello, Axiom!\n")
  0)
```

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
- Struct/union **field access** (`.field`-style reads) still has no
  expression syntax at all, independent of `data` - see the Structs/Unions
  sections below for what does and doesn't work there.

### Structs

For C-compatible data layouts:

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

### Unions

```scheme
(union Value
  (asInt : I64)
  (asFloat : F64))
```

### Type aliases

```scheme
(type StringList () = [String])
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

## Built-ins and FFI

Axiom has no standard library. System operations are done through FFI bindings to C, which you declare in your code.

### FFI bindings

```scheme
(foreign printf :: (-> String Int) = "printf")
(foreign malloc :: (-> Int (* Any)) = "malloc")
(foreign free :: (-> (* Any) ()) = "free")
(foreign memset :: (-> (* Any) Int Int (* Any)) = "memset")
(foreign memcpy :: (-> (* Any) (* Any) Int (* Any) (* Any)) = "memcpy")
(foreign exit :: (-> Int ()) = "exit")
```

See the [Foreign Function Interface](#foreign-function-interface) section for details.

### Common data types (define as needed)

```scheme
(data Maybe (a) (Nothing) (Just a))
(data Ordering (LT) (EQ) (GT))
(data List (a) (Nil) (Cons a (List a)))
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
(foreign printf :: (-> String Int) = "printf")

(:: main Int)
(fn main
  (printf "Formatted: %d\n" 42)
  0)
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
  named declarations (functions, `data`/`struct`/`union`/`type` decls,
  `foreign` bindings, ...).
- Imports are transitive (`A` imports `B` imports `C` brings `C`'s
  declarations into `A` too) and diamond-safe (two different modules both
  importing `C` merges `C` exactly once, not twice).
- There's no namespacing or qualified names yet - an imported declaration
  joins the importing module's flat top-level namespace exactly as if it
  had been pasted in, so two files defining the same name is a normal
  `AX3006` duplicate-definition error, not a "which one did you mean"
  ambiguity.
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
# unions, aliases, classes, ...) and its type/shape in Axiom's AI-optimized
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

Axiom can call any C function. Declare it with `foreign`:

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
| FFI | **Complete** | Call any C function with `foreign` declarations |
| ADTs / data types | **Complete** | Constructors (nullary and with fields, including recursive types like `List`/`Tree`) compile to heap-boxed tagged values; see [Algebraic data types](#algebraic-data-types-how-they-actually-run) |
| Structs / unions | **Complete** | Declarations, LLVM emission, field access (`.field`), struct construction (`(StructName expr1 expr2 ...)`), `mut` fields, and field mutation (`(set-field expr field value)`) all work |
| Pattern matching (`match`) | **Complete** | Constructor patterns (nullary and with-field), variables, wildcards, literals, nested constructor patterns, and tuple/list patterns all compare and bind correctly, plus non-exhaustiveness/arity/undefined-constructor diagnostics |
| Lambda | **Partial** | Parsed and type-checked; codegen pending |
| Lists | **Partial** | Syntax and type checking; runtime representation pending |
| Tuples | **Partial** | Syntax and type checking; codegen pending |
| Type classes | **Stub** | Parsed, not enforced |
| Effect annotations | **Parsed only** | `handle`, `IO`, `Pure`, etc. |
| Region syntax | **Parsed only** | `region r body` |
| Linear types | **Parsed only** | `linear T`, `consume` |
| Imports | **Functional** | `(import Mod.Sub ...)` resolves and merges declarations from other files; see [Modules and imports](#modules-and-imports) |

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
├── axiom-ast/          # AST definitions
├── axiom-lexer/        # Tokenizer
├── axiom-parser/       # Parser
├── axiom-sema/         # Type checker
├── axiom-ir/           # IR + generator
├── axiom-codegen/      # LLVM codegen
├── axiom-cli/          # CLI + REPL
├── axiom-errors/       # Error types
├── hello_world/        # Sample program
└── Cargo.toml          # Workspace manifest
```

---

## License

MIT
