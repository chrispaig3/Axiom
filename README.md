# Axiom

![GitHub CI](https://github.com/chrispaig3/axiom/actions/workflows/ci.yml/badge.svg)

> **Like what you see?** [⭐ Star the repo](https://github.com/chrispaig3/axiom/stargazers) and [🍴 fork it](https://github.com/chrispaig3/axiom/fork) — a star helps other people find Axiom, and a fork is where your first contribution starts.

<img width="1500" height="1024" alt="Image" src="https://github.com/user-attachments/assets/38a9afb6-3570-4797-ba57-488e004f4e66" />

A functional systems programming language for humans and agents.
Axiom blends the expressive power of functional programming with the performance and control of systems languages. It uses a clean Lisp‑style S‑expression syntax, a Hindley–Milner‑inspired type system, and an LLVM backend to produce fast, native executables — with no VM and no runtime. Memory comes from an `mmap`-backed bump allocator; every heap block carries a reference count and is freed when that count reaches zero, with explicit arena reclamation where peak memory matters.

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

- **AXSYM** — A dense, one-line-per-symbol notation that tells an agent exactly what a file declares and the type of each symbol. Run `axiom --diagnostic-format=ai symbols` to see it; plain `axiom symbols` prints the same facts as an aligned table for a human reader. No re-reading files, no re-deriving signatures by eye.
- **NID** — Stable node IDs: content-derived hashes of `(kind, name)` that survive edits and reformatting, unlike line numbers. Every named declaration gets one automatically.
- **AXTAG** — Source-embedded agent metadata via `;@axiom:<key>(<value>)` comments above declarations. The compiler validates the claims it knows — `effect(io)`/`pure` are checked against the syscalls the body actually reaches, and `restrict(no-io, no-alloc, no-foreign, no-cast, no-cast:deep, no-recursion)` against the same effect row, the call graph and the body (`AX3049` when violated, an error naming the path of calls to where the effect enters, or the cycle) — so an agent can annotate intent and have it verified. The key namespace is otherwise open by design: a key the compiler does not know is recorded, re-emitted on the symbol line, and not checked.

---

## Installation

### Prerequisites

- **LLVM** — `llc` must be on your PATH (for code generation)
- **A C compiler** — `cc`, `clang`, or `gcc` on your PATH (for final linking)

That is the whole list **to build and use the compiler**. Axiom's
compiler is written in Axiom, so there is no other language's toolchain
to install first. (Rust's is needed only if you use the FFI: `axiom
build --crate DIR` runs `cargo` over the crate on the far side — see
[docs/ffi.md](docs/ffi.md).)

Running the *gate battery* needs more, and the difference is worth
stating because the sentence above is otherwise read as covering it:
**`python3`** drives fifteen of the gates, **Node 22** builds the
tree-sitter grammar, and **`cargo`** is needed by the FFI gate
(`scripts/check-ffi.sh`) and by the `rust/` workspace's own suites.
None of the three is needed to compile a program.

On macOS:
```bash
brew install llvm
```

On Ubuntu/Debian:
```bash
sudo apt install llvm clang
```

### Install a release

```bash
curl -fsSL https://raw.githubusercontent.com/chrispaig3/axiom/trunk/scripts/install.sh | bash
export PATH="$HOME/.axiom/bin:$PATH"
```

Downloads the archive for your platform, **verifies its SHA-256**, and
then builds and runs a program that *imports a standard-library module*
— by the bare name `axiom` found on `PATH`, which is the invocation the
line above sets up — before reporting success. A check that compiled a
program importing nothing would pass on an archive that shipped no
`stdlib/` at all, which is how the first version of it behaved.

**Archives are published for `linux-aarch64` and `darwin-aarch64`.** On
any other host the script tells you so and points at the source build
below rather than failing on a download. `linux-x86_64` is the case
worth naming: it is a **fully supported and tested** target — its CI
leg runs the whole gate battery on every change — and since 2026-08-30
it simply has no prebuilt archive, because that leg was the slowest and
most-often-re-run part of cutting a release and its users are the
likeliest to already have a toolchain. Building it is one command:

```bash
git clone https://github.com/chrispaig3/axiom && cd axiom
./scripts/bootstrap-from-seed.sh --install .axiom-bin
```

`darwin-x86_64` and the two FreeBSD targets get a different message,
because theirs is a different situation: those are assembled and
byte-compared but executed by no runner, so they are not supported.

Piping into `bash` passes no arguments, so the knobs are environment
variables: `AXIOM_VERSION=0.2.0` picks a release and
`AXIOM_PREFIX=/opt/axiom` picks where it goes. Run the script as a file
and `--version` / `--prefix` do the same. It refuses to install into a
directory it does not own — `/usr/local`, `$HOME`, or a git checkout —
because it removes `$prefix/bin` and `$prefix/stdlib` before installing.

The compiler finds its standard library relative to **the directory it
was found in** — the installed layout is `bin/axiom` beside `stdlib/`,
so keep the two together. `AXIOM_STDLIB` overrides it. Both halves are
gated by `scripts/check-driver.sh`, which installs a layout, resolves
through it by bare name, and then requires the same invocation to fail
once `stdlib/` is removed.

**There is no release binary for `darwin-x86_64`, deliberately.** It is
assembled and byte-compared in CI, but no runner for it exists, so it
has never been executed - and publishing a binary implies a support
level that does not exist. Build it from the seed below, which is
supported. The installer says this rather than handing over something
untested. The same is true of `freebsd-x86_64` and `freebsd-aarch64`
(seeds since 2026-08-29, a CI leg that is advisory until it is green,
no release job); the installer refuses those hosts with the same
paragraph, and the seed builds there.

### Build the compiler from source

Always supported, on every target, and what a contributor uses.

```bash
git clone https://github.com/chrispaig3/axiom
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
Source (.ax) → Lexer → Parser → Imports → Macro expansion → Type Checker → LLVM IR → llc → cc → Executable
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
@str_0    = private unnamed_addr constant [14 x i8]  c"\48\65\6C\6C\6F\2C\20\41\78\69\6F\6D\21\00"
@strhdr_0 = private unnamed_addr constant { i64, i64, i64, ptr, i64 } { i64 -1, i64 0, i64 13, ptr @str_0, i64 0 }, align 16
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

> **A `String` is a machine word, but it is not an `Int`.** Every Axiom
> value is one word, and a `String` is the address of a `Str` header —
> which is why a literal stores in a `Vec`, keys a `Map`, and is read by
> the `Int`-typed accessors that implement `Str`, all through type
> variables. The two types are nonetheless **distinct**: `(+ 1 "hi")` is
> `AX3004 type mismatch: expected Int, found String`, and `(cast Int s)`
> is the explicit crossing. The fiat that made them interchangeable was
> deleted on 2026-08-15, because reference counting has to know which
> words are references and the fiat was exactly what made that
> undecidable ([docs/memory-model.md](docs/memory-model.md)
> MM-ALLOC-20).

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

The type `(-> A B C)` means a function that takes `A`, then `B`, and
returns `C`. The signature is curried, but a **top-level** function is
not partially applicable: `(add 5)` is `AX3013`, because a partial
application would need a closure record to hold the arguments it was not
given and a top-level function has none. Write the lambda instead —
`(lambda (y) (add 5 y))`. A `lambda` of several parameters *is* several
lambdas and may be applied one argument at a time; see
[Lambda](#lambda-anonymous-functions).

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

(& 12 10)           ; 8    bitwise and
(| 12 10)           ; 14   bitwise or
(^ 12 10)           ; 6    bitwise xor
(<< 1 10)           ; 1024 shift left
(>> 1024 3)         ; 128  shift right, arithmetic (the sign bit is kept)

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

Patterns match constructors, literals, variables and wildcards:

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

A constructor **with fields** is always a heap block: word `0` is an
integer tag saying which constructor built it, and words `1..` are its
fields, one 8-byte word each. A **nullary** constructor is a heap block
only when it has to be. Which of the three representations a type gets
is decided once, for the whole type, by `ctorsRep` in
`self_host/codegen.ax`:

| Type | Representation |
|---|---|
| Every constructor takes fields | **Boxed.** Each value is a tagged block. |
| Every constructor is nullary — `(data Color (Red) (Green) (Blue))` | **All-nullary.** Each value *is* its tag. No block, no allocation, so an enum costs nothing. |
| **Mixed** — `(data L (Nil) (Cons Int L))` | Nullary constructors are immediate tags, fieldful ones are heap blocks. `Nil` is its tag; `Cons` is a block. |

Tags are assigned from a single counter across the program, so a type
whose tags would reach 4096 falls back to boxed: every heap address is
mmap-page memory at or above 4096, which is exactly what lets a match
site over a **mixed** type tell an immediate tag from a pointer with a
runtime `< 4096` test before it loads a tag word. Where the type is not
mixed no such test is emitted, because the constructor *named in the
pattern* already says statically where the tag lives — one machine word
on its own cannot say whether it means an integer, a tag, or a pointer.
`tests/stdlib/270-nullary-unboxed.ax` pins the unboxing and
`tests/selfhost/400-mixed-nullary.ax` the guarded load.

Recursive types need no special-casing either way: a field that is
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
- **Tuples and lists are type syntax only.** `(Int String Bool)` and
  `[Int]` are writable in a signature, but there is no tuple or list
  *literal* (`[1 2 3]` is `AX2001`) and no tuple or list *pattern* — a
  `match` arm spelled `((a b) ...)` is read as a constructor pattern,
  not as a pair. Use a `data` declaration for either shape.
- **Named fields per variant** work - see [Struct variants](#struct-variants).
- **Allocation** comes from an `mmap`-backed bump allocator, not `malloc`,
  and since 2026-08-15 dead blocks ARE freed implicitly: every heap
  block carries a reference count and a shape word, and a block whose
  count reaches zero is walked and re-issued from a size class. A
  thousand build-and-drop iterations move the allocator's bump by 384
  bytes where they moved it by 80,304
  (`tests/stdlib/359-arc-str-bytes.ax`). All six of `MM-LIFE-2c`'s
  ownership events emit: the last two, which needed to know whether a
  value escapes the frame that made it, shipped on 2026-08-21, and the
  shapes they cover now reclaim everything they build
  (`tests/stdlib/372-arc-owned-results.ax`, where every measured line
  must read 0 bytes per iteration).
  `__axiom_arena_mark` and
  `__axiom_arena_reset` reclaim explicitly by rolling the allocator's
  waterline back, which is how the language server holds flat memory
  across an editing session. There is no tracing collector: the retired
  Rust compiler had one behind `--gc`, it was not ported, and the flag is
  now refused by name rather than silently ignored
  (the self-hosting record). See the memory model specification in
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
`AX2001` for all three. The FFI did not bring them back: a value crosses
the boundary as one machine word each way, and a `#[axiom_record]`
struct crosses **as its fields**, one word each, rather than as a laid-out
block ([docs/ffi.md](docs/ffi.md) §8). Nothing on either side of an
`extern` ever reads an Axiom struct's memory, so there is no layout to
agree on.

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
- **Effects** — traits, impls and methods accept an effect list, and it is currently parsed and discarded: nothing checks an implementation against it (`self_host/parser.ax` skips the group). On a `trait` or `impl` header the first parenthesised group is read as the *supertrait* list, so an effect list written there is diagnosed as a missing supertrait

Not yet: a function generic over a trait cannot call its methods, because
dispatch needs a concrete type at the call site rather than a type
variable. Every unsupported shape is `AX3025` — run `axiom explain AX3025`.

### Effects

Axiom infers each function's side effects transitively — a fixpoint over
every body, so a syscall three calls down still counts. Effects do **not**
appear in function types: `symbols` renders an I/O-performing function as a
plain `(Int -> Int)` and carries the inferred set beside it as `#effects=IO`.
The checking is **not** opt-in. A `;@axiom:effect(...)`/`;@axiom:pure`
claim is validated against what was inferred, and a claim the compiler
can refute is an **error** (`AX3010`); a claim it is not in a position
to check is a warning (`AX3037`). An untagged function is not an
unchecked one — silence is itself the claim *"performs no IO"*, and a
body that performs IO under it is `AX3042`, also an error.

Only `IO` is **required**, and the line is measured rather than chosen:
of 3,421 functions in the compiler and its standard library, 2,095
perform something and **1,664 of those perform exactly `Alloc,Mut`** —
every function that touches a `String` or a `Vec`. (Required, not
*declarable*: `;@axiom:effect(mut)` over a body that writes a field
checks OK, and over one that does not it is `AX3010`, an error. `Alloc`,
`Mut` and every custom effect are declarable and checked. What is
special about `IO` is that its ABSENCE is a claim.) `Alloc` and `Mut`
are ambient, still inferred and still reported; `IO` is the one a
caller cannot learn without opening the callee. A trait-method
implementation declares its own effects, with the tag written inside
the `impl`.

Built-in effects:

| Effect | Meaning |
|---|---|
| `IO` | Reaches the outside world — a `__syscallN`, or `__argc`/`__argv`, because reading the command line is reading input the process did not compute (`docs/memory-model.md` MM-EXEC-9a, closed 2026-08-25) |
| `Pure` | No side effects |
| `Alloc` | Heap **machinery**, not strictly allocation: a call reaching `__alloc`, which is every `Vec`/`Map`/`Str` growth and every `memAlloc`; the three arena primitives since 2026-08-25, because a reset ends every block allocated since a mark; and `handle`, for installing evidence. The `(alloc T)` keyword also contributes it and is the reason it used to be the *only* contributor — a form that allocates nothing, while the primitive the heap goes through contributed nothing (`docs/memory-model.md` MM-EXEC-9a, whose table lost that row on 2026-08-23) |
| `Mut` | Mutable heap state: `(set base.field v)`, and the `__store8`/`__store64` primitives it lowers to (`docs/memory-model.md` MM-EXEC-9a, closed 2026-08-25) — which is why `vecPush` and `mapInsert` carry it. Since 2026-08-29 the atomic writers `__atomic_store`/`__atomic_add`/`__atomic_cas` and `__fence` carry it too; `__atomic_load` deliberately does not, for `__load64`'s reason. A plain `set` on a `mut` **local** is deliberately not `Mut` — a local's mutation is invisible outside its function, while a field store is visible through every alias of the value |
| `Div` | Divergence (infinite loops). **Spellable, never inferred** — nothing in the compiler produces it, so a `;@axiom:effect(div)` claim is reported **unverifiable** (`AX3037`, a warning) rather than unsupported, even over a body that plainly does not terminate — a claim the compiler never looks for is a fact about the analysis, not the body. Inferring it needs a termination analysis this compiler does not have; the cheapest sound rule (self-call or any `while`) marks 65% of the compiler divergent and is false on almost all of them |

There were **six** until 2026-08-30. `Err` was accepted as a sixth
built-in effect name — a handle list could write it — and nothing in
the compiler ever inferred it, so the name resolved and denoted
nothing. A handle list was also the only place it resolved at all: the
AXTAG path lowercases the value, so `;@axiom:effect(err)` looked for an
undeclared *custom* effect named `err` and reported `missing err`. A
name a list may write, that nothing produces, and that its own tag
spelling cannot reach, is a hole in a table rather than an effect.
`(handle 5 (Err) 0)` now draws `AX3016`, which is what a list naming
something undeclared has always drawn, and `Err` is an ordinary name
again — `(effect Err ...)` declares an ordinary effect.

Declaring an effect named after one of the five is `AX3054`, an error:
a handle list resolves a built-in name to the built-in, so such a
declaration can never be handled.

`Div` is the one that resolves to a built-in nothing produces, so a
`;@axiom:effect(div)` claim is `AX3037` — a **warning** saying nothing
infers that effect — and not the `AX3010` error a refuted claim gets.
An accusation the compiler never looked for would be unanswerable.

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

Effects cross a trait boundary like any other call: a method whose
implementation performs I/O contributes `IO` to whoever calls it, and an
`effect(io)` claim on that caller checks out.

An implementation declares its own effects, with the tag written inside
the `impl`. It is a declaration like any other and it is checked like
one — an implementation that performs I/O and says nothing draws
`AX3042` at its mangled `Console#String#print` name.

```scheme
(import IO)

(trait (Console a)
  where
    (print :: (-> a Int)))

; One parenthesised group, holding every method — see Traits above.
(impl (Console String)
  where
    (;@axiom:effect(io)
     (print (lambda (s) (println s)))))

(:: main Int)
;@axiom:effect(io)
(fn (main) (print "hi"))
```

---

## Type System

### Primitive types

| Type | Description | LLVM type |
|---|---|---|
| `Int` | 64-bit signed integer | `i64` |
| `Float` | 64-bit IEEE-754 double. The **word holds the bit pattern**; each arithmetic site `bitcast`s to `double`, operates (`fadd double`, `fdiv double`, …) and `bitcast`s back | `i64` |
| `Bool` | Boolean. A distinct type from `Int` — `if` consumes it, and `true`/`false` are its literals | `i64` |
| `Char` | Character. A codepoint word at run time, a distinct **type** from `Int` | `i64` |
| `String` | A `Str` handle - the address of a `{ length, bytes, owner }` header. One word wide like `Int`, and a **distinct type** from it: `(cast Int s)` is the crossing; see [Strings](#strings) | `i64` |
| `()` | Unit (no value) | `i64` |
| `Unit` | A distinct constructor, **not** a synonym for `()` — `symbols` renders them `(Int -> ())` and `(Int -> Unit)`; see [reference.md](docs/reference.md#types) | `i64` |
| `Void` | Void. Accepted and distinct — a mismatch reports "found `Void`" — and not a removed name | `i64` |
| `Any` | Generic pointer. Accepted, and one word like everything else | `i64` |

**Every column-three entry is `i64`, and that is the fact rather than a
formatting accident.** The emitter is uniformly word-wide: a type is a
CHECKING-time distinction and carries no representation of its own, so
`Bool`, `Char`, `Any`, `()`, `Unit` and `Void` are all one machine word
and `(-> Bool Bool)` emits `define i64 @f(i64)`. `Float` is the only one
whose word is interpreted differently, and only at the operator.

That column read `f64`/`i1`/`i8`/`ptr`/`void` until 2026-08-25 —
inherited from the Rust-era compiler, which did lower narrowly — and was
wrong for seven of nine rows against the self-hosted one. It is also
why `docs/memory-model.md`'s MM-LIFE-2a calls codegen's shape word the
wall: the representation is uniform, so nothing about a value's type
survives into the emitted code to be relied on.

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
allocation, not for file I/O. The library needs no FFI to do any of it.
Naming an external symbol is possible, and is the `extern` block —
Rust on the other side, through the C ABI ([docs/ffi.md](docs/ffi.md));
`foreign`, the construct that used to spell this, is removed and
reserved at `AX2004`.

```scheme
(import IO)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((total (+ 1 2)))
    {
      (println "hello, world")
      (println 42)                ; any type `show` can render
      (println "sum={total}")     ; a hole names a binding in scope
      (println "hex={total:>6x}") ; ...with a Rust-style specifier
      0
    }))
```

Printing is two macros and no per-type functions — `println` and
`eprintln`, with `format` beside them in `Show` for the string a
program builds instead of writes. `stdlib/IO.ax` says why there is
deliberately no newline-less printer — the line is assembled at compile time, so
emitting it in pieces buys nothing and costs a syscall each — and
`(print "hi")` is `AX3001 undefined variable`. The format string is
parsed by the compiler, each hole becomes a `show` call chosen by the
value's static type, and each specifier chooses a `Fmt` function.
Nothing is parsed at run time, so a malformed format string or a
specifier applied to the wrong type is a compile error. See
[Printing and Formatting](docs/reference.md#printing-and-formatting).

### Modules

Twenty-two modules, all of them Axiom source under `stdlib/`. The
per-module export lists are in
[reference.md](docs/reference.md#standard-library); this table says what
each module is for. A name a module does not mark `pub` is not part of
its surface — reaching one is `AX3023` — so `grep '^(pub' stdlib/M.ax`
is always the authoritative answer.

| Module | For |
|---|---|
| `Pre` | The prelude macros: `when`, `unless`, `cond2`, `cond3`, and the derivers `deriveEq`, `deriveShow`, `deriveArity`, `showOr` |
| `Mem` | Raw memory: `memAlloc`, `memCopy`, `memSet`, `memCmp`, `memGetByte`/`memPutByte`, `memGetWord`/`memSetWord` |
| `Str` | The byte view of a `Str`: `strLen`, `strByte`, `strCmp`, `strEq`, `strSlice`, `strDup`, `strConcat`, `strFindByte`, `strStartsWith`, `strSplit`, `strCStr`, `strAlloc`, `strFromLit`. String *literals* are already `Str` values — see [Strings](#strings) |
| `Utf8` | The character view of the same bytes: `utf8Len`, `utf8CharAt`, `utf8DecodeAt`, `utf8Slice`, `utf8Width`, `utf8Valid` |
| `Vec` | Growable `Int` array: `vecNew`, `vecWithCapacity`, `vecPush`, `vecPop`, `vecGet`, `vecSet`, `vecLen`, `vecCap`, `vecLast`, `vecClear`, `vecSort`, `vecSortBy` |
| `Map` | Open-addressing `Int→Int` hash map: `mapNew`, `mapWithCapacity`, `mapHas`, `mapGet`, `mapGetStr`, `mapInsert`, `mapRemove`, `mapLen`, `mapCap`. `mapGet` answers `Int` — the truth about a machine word — and `mapGetStr` is the typed reader beside it, the same pair `Vec` and `Mem` carry. It answered a *type variable* until 2026-08-25, which let a caller name a type the table does not hold and exit **139** |
| `Fmt` | The functions a format specifier selects: `fmtInt`, `fmtIntWidth`, `fmtHex`, `fmtHexUpper`, `fmtFloat`, `fmtFloatPrec`, `fmtPadLeft`, `fmtPadRight`, `fmtPadCenter`, `fmtPadZerosLeft` |
| `Intern` | String interner: `internNew`, `internIntern`, `internFind`, `internLookup`, `internCount` |
| `Sys` | The syscall layer: I/O (`sysWriteFd`, `sysReadFd`, `sysWriteAllFd`, `sysOpenPath`, `sysCloseFd`, `stdin`/`stdout`/`stderr`), the filesystem (`sysReadFile`, `sysWriteFile`, `sysAppendFile`, `sysRename`, `sysUnlink`, `sysMkdir`, `sysRmdir`, `sysReadDir`, `sysFileExists`, `sysIsDir`, `sysFileSize`, `sysGetCwd`), processes (`sysSpawn`, `sysRun`, `sysRunPath`, `sysWaitPid`, `sysEnv`), and the process's own facts (`sysArgc`/`sysArg`, `sysGetPid`, `sysNowMicros`, `sysErrno`, `sysExitWith`) |
| `Path` | Decisions about path bytes, no syscalls: `pathDir`, `pathBase`, `pathExt`, `pathStem`, `pathJoin`, `pathReplaceExt`, `pathWithSlash`, `pathIsAbsolute` |
| `IO` | `println`, `eprintln` — **macros**, with compile-time format strings — plus `writeStr` (bytes, no newline, no rendering), `exit`, `die`, `todo` (a hole that types as anything and exits 70 - what AX3005's fix writes into each missing arm), the raw-address variants `printlnLit`, `readFileLit`, and the `Str`-taking filesystem surface: `readFile`, `writeFile`, `appendFile`, `copyFile`, `removeFile`, `renamePath`, `fileExists`, `isDir`, `fileSize`, `readErrno`, `makeDir`, `makeDirAll`, `removeDir`, `listDir`, `cwd` |
| `Show` | The `Show` trait and its instances for `Int`, `String`, `Bool` and `Float`, plus the `format` macro |
| `Err` | `Result`, an `Error` record, `mapErr`/`andThen`/`mapOk`/`okOr`/`toOption`/`withContext`, the checked arithmetic `divChecked`/`remChecked`/`shlChecked`/`shrChecked`, and the `try!` propagation macro — see [docs/error-model.md](docs/error-model.md) |
| `Fallible` | The `Fallible` effect — `fallibleMalformed`, performed by the callee that finds a malformed record — and the handlers a batch loop installs to answer it per record without unwinding: `fallibleSkip`, `(fallibleDefault d)`, `(fallibleCounting tally next)`, with `fallibleSkipped`/`fallibleIsSkipped` as the sentinel a skipping loop checks. Tail-resumptive, and 0 bytes a record ([docs/error-model.md](docs/error-model.md) ERR-REC-7) |
| `Json` | JSON values, `jsonParse` and `jsonWrite`, with the accessors between them |
| `Rpc` | Framed reads and writes over a file descriptor — what `self_host/lsp.ax` speaks LSP over |
| `Job` | `jobRunAll`: a bounded pool of child processes over `Sys`'s `sysSpawn`/`sysWaitPid`, answering in submit order |
| `Html` | A templating DSL written in the macro system: one macro per element over an explicit builder (`div`/`divA` and thirty-odd tags, `br`/`img`/`link`/`meta`, `el` for any other), one per common attribute (`class`, `id`, `href`, …) with `attr` for the rest, `for`/`forInt` over a `Vec`, `text` escaped by default and `raw` the only way out, `style`/`script` with `</` neutralised at run time; the builder `hNew`/`hPut`/`hFinish` and the escapers `hEscText`/`hEscAttr` underneath. The module header is the proof of which macro-system rule each part rests on and which it works around |
| `Http` | An HTTP/1.1 server's pieces over `Sys`'s sockets: a buffered request parser (`httpRead` - request line, case-insensitive headers, `Content-Length` bodies, partial reads, a 16 KiB head ceiling and an 8 MiB body ceiling, every refusal an `Error` whose code is the status), the query accessors (`httpQueryParam`, `httpHeader`), a response writer (`httpRespond`/`httpRespondRaw`, `Connection: close` on every reply), a router of function-value handlers with static prefixes (`routerNew`, `routeAdd`, `routeStatic`, `routeDispatch`), the path check that refuses `..` before the filesystem is touched (`httpPathSafe`), content types by extension, and `httpServeOne` for one connection start to finish `examples/web/server.ax` is a site on both: `axiom run examples/web/server.ax` listens on http://127.0.0.1:8080/ (port, worker count and arena-per-request are its three optional arguments), and `scripts/check-web.sh` holds its pages and its memory |
| `Ffi` | The helpers `axiom-bindgen` emits calls to — handles, out-cells and the `Vec`/`String` conversions an `extern` result arrives through ([docs/ffi.md](docs/ffi.md)) |
| `Test` | Assertions, and the `Assert` effect a failed one performs: `assertEq`, `assertNe`, `assertStrEq`, `assertTrue`, `assertFalse`, `testFail`. What `axiom test` runs, and what a failed assertion aborts to ([CLI Commands](#cli-commands)) |
| `Agent.Tags` | Parses the AXSYM stream `axiom --diagnostic-format=ai symbols` prints, so a program can read what the compiler already says about a program — kind, name, span, type, NID, the derived effect row, and every AXTAG including the unchecked `agent:*` namespace ([docs/agent-harness.md](docs/agent-harness.md)) |

A `Str` is a length-prefixed, NUL-terminated string: slicing shares
storage, and `strCStr` hands the bytes to a syscall without copying.

The `Lit` names take a raw NUL-terminated address rather than a `Str`.
They are rarely what you want now that a literal is a `Str` —
`(println "hi")` is both shorter and cheaper than
`(printlnLit (__addr "hi"))` — but they remain the way to print bytes
that arrived without a length, such as a syscall buffer.

**Every public name, with its type, its effects and a one-line
summary, is in [docs/stdlib-api.md](docs/stdlib-api.md)** — 431 of
them across these modules. That document is GENERATED, by an Axiom
program (`examples/axdoc/axdoc.ax`) that reads the library's own source
for the public surface and `axiom symbols` for the effect row, and
`scripts/check-stdlib-api.sh` regenerates it on every CI run and
requires the result to be byte-identical. The table above says what
each module is *for*; the reference says what is in it.

The library is found automatically - `AXIOM_STDLIB` overrides its
location, `axiom.pkg`'s `depend` lines add a project's own
dependencies (see [Packages](#packages)), and `AXIOM_PATH`
(colon-separated) adds further module search directories.

**The search order, stated exactly**, because a shorter version of this
sentence was wrong for a year. Resolution is a ladder of SUFFIXES over
a list of DIRECTORIES, and the suffix is the outer loop:

```
for suffix in .<os>-<arch>.ax, .<os>.ax, .ax:
    for dir in  the entry file's own directory
                each `depend` in axiom.pkg, in file order
                each $AXIOM_PATH entry, in order
                each --crate DIR's axiom/ directory
                $AXIOM_STDLIB, or the stdlib beside the binary:
        if <dir><module><suffix> is a readable file, that is the module
```

So a project *does* shadow a standard-library module with its own file
of the same name — but only at the same suffix. A more target-specific
file anywhere on the path beats a less specific one nearer the entry
file: measured 2026-08-25, a project's own `Sys/Platform.ax` loses to
the standard library's `Sys/Platform.darwin.ax`, which is the mechanism
that makes one `(import Sys.Platform)` resolve per target and is not a
bug. The claim this paragraph replaced — "a module in the entry file's
own directory always wins" — was false on exactly that case.

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
| `(__atomic_load p)` / `(__atomic_store p v)` / `(__atomic_add p v)` / `(__atomic_cas p expected new)` / `__fence` | Sequentially consistent atomics on the machine word at **byte address** `p` (the address itself, not `base + i * 8`): a load; a store; an add that answers the word **before** it; a compare-and-swap that answers the word it found, so it stored `new` iff the answer equals `expected`; and a full fence. A store and the fence answer 0. The four that write or order carry `Mut`; the load computes, as `__load64` does. There is no thread for them to synchronise with yet — they are the escape [docs/memory-model.md](docs/memory-model.md) MM-PAR-4 names, for memory a program mapped itself — and `tests/stdlib/440-atomics.ax` pins their single-threaded meaning at every optimisation level and on every target |
| `(__alloc bytes)` | Address of `bytes` fresh zeroed bytes |
| `(__retain h)` / `(__release h)` | Take or hand back a share of the counted block at `h` |
| `(__retainref v)` | Take a share of `v` **iff `v` is a reference** — decided from the call's type, so an `Int` argument emits nothing at all. This is what makes a store that hides a value behind a `cast Int` visible to the reference counting |
| `__axiom_arena_mark` / `(__axiom_arena_reset m)` | Read the allocator's waterline (it takes no argument), and roll it back to a mark |
| `(memMarkArray h)` / `(memMarkLeaf h)` | Say that every payload word of the block at `h` is a handle, or that none is — the array form, `Mem`. There is no reader: the bit is the RUNTIME's instruction and is ambiguous against an allocator with a different clamp, so a container carries its own flag ([docs/memory-model.md](docs/memory-model.md) MM-LIFE-2h) |
| `(__axiom_recover m thunk)` | Arm a recovery point at mark `m` and run `thunk`: out of memory, an unhandled effect and a division by zero answer this call with 70, 71 or 72 instead of exiting. Outside one they still exit ([docs/error-model.md](docs/error-model.md) ERR-REC-6) |
| `(__addr "literal")` | Address of a string literal's bytes |

`axiom symbols --builtins <file>` prints the full list, primitives and
operators together, with the type of each.

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

Supported: `darwin-aarch64`, `darwin-x86_64`, `freebsd-x86_64`,
`linux-aarch64`, `linux-x86_64`, `windows-x86_64`. Defaults to the
host.

**A target joins that list when a CI leg executes what the compiler
emits there.** That is the definition of *supported* in this
repository, stated here once; `docs/reference.md`, `SECURITY.md` and
`CONTRIBUTING.md` point at this paragraph rather than restating it, and
`scripts/check-doc-drift.sh` holds the copies of the list to each other
and to the compiler's own `--target` table. Everything in the list is
emitted for and assembled by `check-cross-targets.sh` from one host;
`darwin-x86_64` predates the rule and is executed by no runner, which
is why it ships no artifact (see *Install*). **`freebsd-x86_64` and
`windows-x86_64` joined the list on 2026-08-30**, each after its leg
had been seen green on 13 of the previous 15 runs with no failures and
its `continue-on-error` was removed — the line comes off after the
evidence, never in the commit that adds the job.

**The two legs do not cover the same amount, and the word should not
hide it.** FreeBSD boots a real 14.4 kernel in a VM, bootstraps from
the committed seed, and runs the whole standard-library corpus plus
five gates including `check-net.sh`, which opens a real listener on
`::1`. Windows runs **one program** — `hello.exe`, executed against
`tests/stdlib/010-hello.out`, with its imports held to an allowlist and
a leaky probe proving the allowlist refuses. Both satisfy the rule
above, because both execute what the compiler emits. Only one of them
would catch a Windows-only miscompile in a module that hello does not
touch, and widening it means linking and running the corpus the `cross`
job already assembles.

**Supported and shipped are different questions.** *Supported* is the
paragraph above: a CI leg executes what the compiler emits there.
*Shipped* is whether a release carries a prebuilt archive, and since
2026-08-30 `linux-x86_64` is supported and **not** shipped — its leg
runs the whole battery on every change and always will, but the
release builds only `linux-aarch64` and `darwin-aarch64`, because that
leg was the slowest and most-often-re-run part of cutting a release and
its users are the likeliest to have a toolchain already. On such a host
`scripts/install.sh` says so and points at `bootstrap-from-seed.sh`
rather than fetching a 404; `scripts/check-release-targets.sh` holds
the release matrix and the installer's refusal list to each other so
the two cannot drift.

`freebsd-aarch64` is the one FreeBSD target that is **not** supported,
and the split is worth reading because both halves have the same seeds
and the same syscall table. `scripts/check-cross-targets.sh` assembles
every standard-library case for both under their own triples on every
PR, `check-platform-constants.sh` holds the emitted runtime's syscall
numbers to `stdlib/Sys/Platform.freebsd.ax`'s, and `bootstrap/` carries
a seed for each. What only `freebsd-x86_64` has is a leg that RUNS any
of it: `Tests (freebsd-x86_64)` boots FreeBSD 14.4 in a VM and runs the
bootstrap and the syscall-table gates there, and it is blocking.
`freebsd-aarch64` has no job — an aarch64 guest is TCG-emulated on
every runner GitHub offers, a 300-minute budget measured and dropped on
2026-08-29 — so it stands as `darwin-x86_64` does: assembled and
relocation-checked, executed by no runner. (It has run, once, in a
FreeBSD 14.4 arm64 VM on the maintainer's machine, which is a
measurement and not a leg, and the rule is about legs.) Neither FreeBSD
target ships an archive; a `freebsd-x86_64` host gets the
build-from-source paragraph `linux-x86_64` gets, and a
`freebsd-aarch64` host the not-supported one. FreeBSD 12 is the floor
the numbers need; the triple pins 14.

Where Windows stands: `--target=windows-x86_64` is accepted and emits,
cross, from any host (triple `x86_64-pc-windows-msvc`; the runtime
calls kernel32 - `VirtualAlloc`, `WriteFile`, `ExitProcess` - where
the others make syscalls, and enters at `mainCRTStartup` with no C
runtime). `check-cross-targets.sh` assembles every stdlib case for it
at three levels, `check-platform-constants.sh` holds its runtime and
its `Sys/Platform.windows.ax` to the same kernel32 entry points, and
`check-windows-entry.sh` executes its command-line parser on the host.
`axiom build --target=windows-x86_64` links a `.exe` through `lld-link`
(no C compiler on that path) given a `kernel32.lib` on a `--link-search`
directory - the SDK's, or one `llvm-dlltool` generates from a `.def` -
and `check-driver.sh` asserts every branch of that link on hosts that
cannot run the result. A CI leg, `Tests (windows-x86_64)`, assembles,
links and executes a hello world on `windows-latest` from modules the
Linux `cross` job emitted. That leg is **blocking** since 2026-08-30
and windows-x86_64 is on the supported list — one program executed, as
the paragraph above the list says, which is the rule satisfied and the
scope stated. **Supported as a TARGET is not supported as a HOST:** the
compiler does not run on Windows, there is no Windows seed in
`bootstrap/`, and `install.sh` refuses a Windows host outright. What is
supported is the binary this compiler emits. A `__syscallN` reached on
that target traps with status 74.

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
| `&`, `\|`, `^`, `<<`, `>>` | `(Int -> (Int -> Int))` — bitwise and, or, xor, shift left, shift right (arithmetic) |
| `==`, `!=`, `<`, `>`, `<=`, `>=` | `(Int -> (Int -> Bool))` |
| `&&`, `\|\|` | `(Bool -> (Bool -> Bool))` |

Eighteen in all. `axiom symbols --builtins <file>` prints them with the
freestanding primitives beside them.

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

No libc and no `printf`: `IO` is Axiom code over the syscall
primitives. Reaching a foreign symbol on purpose is the `extern` block
([docs/ffi.md](docs/ffi.md)), and no part of `IO` uses it.

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
(import Err)

; Every `.ax` file in `dir`, with its size, one per line.
(:: report (-> String Int Int Int))
;@axiom:effect(io)
(fn (report dir names i)
  (if (>= i (vecLen names))
      0
      (let ((p (pathJoin dir (cast String (vecGet names i)))))
        {
          (if (strEq (pathExt p) ".ax")
              ; `fileSize` answers a `Result`: the failure is in the
              ; type, so a size and an errno are no longer the same Int.
              (let ((size (unwrapOr (fileSize p) 0))) (println "{p}  {size}"))
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

There is no `stat`: its answer is a struct whose layout differs by
platform, so `isDir`, `fileExists` and `fileSize` are `open`, `read`
and `lseek` instead — see the self-hosting record.

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

Note: constructor patterns compile to real branching code (see
[Algebraic data types: how they actually run](#algebraic-data-types-how-they-actually-run)) -
each arm's constructor tag is checked in order and only a matching arm's
body actually runs. Nested constructor patterns bind at every level.
There are no tuple or list patterns; `data` is how you match either
shape.

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
> module and the reason. See the self-hosting record.

How it works:

- A dotted module path maps directly to a file path: `Math.Ops` resolves
  to `Math/Ops.ax`, relative to the entry file's own directory (the file
  you passed to `check`/`build`/`run`/`emit-llvm`) - not to whichever
  file happens to contain the `(import ...)`, so a deeply nested
  module can still `(import Math.Ops)` using the same path the entry file
  would. Other directories are searched after it, in the order under
  [Standard library](#standard-library).
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

# Run every test in a file, or in a directory
axiom test tests/testrunner/pass-tests.ax
axiom test tests/testrunner/

# ...or only the ones whose name contains a string
axiom test tests/testrunner/ --filter Map

# Start interactive REPL
axiom repl

# Print the version, and the build id: a hash of every source byte the
# compiler was built from, plus the commit when there is one. Two builds
# of two different trees at one version are different builds, and say so
axiom version
#   Axiom 0.5.0 (build 7ce43b921d1d 23b97d8285b4)

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

# Same, but also include the always-in-scope built-in operators and
# primitives (omitted by default to keep output minimal)
axiom --diagnostic-format=ai symbols source.ax --builtins

# Also print the call graph the effect fixpoint already resolves, as a
# `#calls=` field beside `#effects=` — so an agent can see WHY a
# function carries an effect, not only that it does
axiom --diagnostic-format=ai symbols source.ax --calls
```

See [`docs/diagnostics.md`](docs/diagnostics.md) for the full agent-facing
notation architecture: stable error codes (`AX####`), cascade suppression,
the human report format, the AI-optimized "AXDL" diagnostic notation, and
the AI-optimized "AXSYM" symbol/type notation.

---

## Packages

A project says what it depends on in an `axiom.pkg` beside its source,
or at any directory above it up to eight levels:

```
# axiom.pkg
name     myapp
version  0.1.0

depend   vendor/axiom-json
depend   ../shared/modules
```

`depend` names a **directory of modules**, resolved against the
manifest's own directory so the project relocates, and each one joins
the module search path after the entry file's directory and before
`$AXIOM_PATH`. The manifest travels with the source; the variable
travels with the shell, so when both can answer the declared dependency
wins. `name` and `version` are recorded and read by nothing yet.

**Two dependencies may not provide one module.** That is the property
that makes this more than a search path, and it is refused before a
byte is compiled:

```
$ axiom check app.ax ; echo $?
error: two dependencies in ./axiom.pkg provide the module `Widget`:
       a/Widget.ax
       b/Widget.ax
       One of them would win by declaration order and the other's
       modules would compile against declarations they never named.
3
```

Before this, whichever directory came first won, silently, and the
loser's modules compiled against a package they had never named — the
value-namespace twin of the type collision `AX3044` closed on
2026-08-24, with the same failure mode: a wrong answer at exit 0.

**What this is not**, said out loud so nobody has to discover it: there
is no registry, no lockfile, no version constraint and no fetching. A
dependency is a path on this machine. Each of those is a policy
decision that wants a maintainer to make it, and a half-made one is
worse than the mechanism it would rest on. `scripts/check-packages.sh`
is the gate, 11 checks, and its negative probe removes the manifest and
requires the same program to stop resolving — so nothing else can be
what found the module.

---

## Testing

A test is a top-level function whose name begins with `test` and which
takes no parameters. There is no attribute to write, nothing to
register, and no manifest — `axiom test` reads the file and finds them.

```scheme
; a file of your own - `tests/testrunner/pass-tests.ax` is this
; repository's
(import Test)

(import Vec)

(:: testVecGrows Int)

;@axiom:effect(io)
(fn (testVecGrows)
  (let ((v vecNew))
    {
      (vecPush v 41)
      (vecPush v 1)
      (assertEq "length after two pushes" 2 (vecLen v))
      (assertEq "sum" 42 (vecSum v))
      0
    }))
```

```bash
$ axiom test tests/testrunner/pass-tests.ax
ok   testVecGrowsAndKeepsItsElements
ok   testMapRoundTrips
ok   testStrSlicesShareBytes
ok   testPathSplitsIntoItsParts
ok   testAssertNeSeparatesTwoValues

5 test(s), 0 failed
```

`stdlib/Test.ax` is the assertion surface: `assertEq`, `assertNe`,
`assertStrEq`, `assertTrue`, `assertFalse`, and `testFail` for the
branch that must not be reached. Every one takes a **label** first,
because Axiom's macros cannot stringify an expression — the label is
what the failure has to say instead.

**A failed assertion ends the test it is in, and no other.** It
performs an operation of the `Assert` effect, which with no handler in
dynamic extent is the unhandled-effect trap, and `axiom test` arms one
recovery point per test — so the three ways an Axiom program can stop
without returning all end exactly one test and answer the runner with
a status ([docs/error-model.md](docs/error-model.md) `ERR-REC-6`):

```
ok   testTheFirstOnePasses
     deliberate: want 3, got 4
FAIL testAFailedAssertionEndsTheTest - a failed assertion, or an unhandled effect (status 71)
FAIL testADivisionByZeroIsContained - division by zero (status 72)
FAIL testAnUnhandledEffectIsContained - a failed assertion, or an unhandled effect (status 71)
ok   testTheLastOneStillRuns

5 test(s), 3 failed
```

That last line is the point of the mechanism: the test declared after
all three failures still ran. A memory-safety fault is the one thing
this does not contain, and no language contains it.

Two rules exist so that nothing is skipped in silence, which is a
runner's characteristic defect — a skipped test reads exactly like a
passing one:

- A file that declares **no** test is a failure, not an empty success.
- A `test`-named function that **takes parameters** is refused by name,
  rather than passed over.

A directory runs every `.ax` file directly inside it, in name order;
`--filter TEXT` runs only the tests whose name contains `TEXT`, and a
filter that matches nothing is a failure for the same reason an empty
file is. The gate is `scripts/check-test-runner.sh`, whose fixtures
are `tests/testrunner/`.

---

## REPL

The REPL compiles expressions to native code — it doesn't interpret them. This means you get real performance even in interactive mode.

```bash
axiom repl
```

### REPL commands

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

The REPL's own help text still lists a `?` alias and arrow-key history;
neither exists. `?` is read as an expression and does not parse.

### Example session

The banner is two lines, there is no prompt, and every line of output
goes to stdout. The session below is pinned by
`scripts/check-repl-selfhost.sh` — except the banner itself, which that
gate never sees, because it drives the REPL as `repl --no-banner`. The
version in it is held instead by `scripts/check-version.sh`, which
names this file as one of its sites:

```
Axiom 0.5.0 - REPL
Type :help for commands, :quit to exit

(:: add (-> Int Int Int))
OK: add defined
(define (add x y) (+ x y))
OK: add defined
(add 3 4)
type : Int
result 7
:type (add 10 20)
(add 10 20) : Int
:defs
Definitions in scope:
  add
  add
:llvm (+ 1 2)
Generated LLVM IR:
target triple = "arm64-apple-macosx14.0.0"
...
```

(The input lines are shown interleaved for readability; the REPL echoes
nothing it was given.)

The REPL accumulates definitions — functions you define persist across
inputs — and that is all it accumulates. There is no line editing, no
arrow-key recall and no history file: stage1 reads plain lines, and the
editor-grade interface is the language server's job
(`self_host/repl.ax` records the divergence).

---

## Compiler Architecture

```
Source (.ax)
    │
    ▼
[1/6] Lexer            → Tokens
    │
    ▼
[2/6] Parser           → AST (S-expression tree)
    │
    ▼
[3/6] Import resolution → One merged declaration list, each entry
    │                     remembering the module it came from
    ▼
[4/6] Macro expansion  → To a fixpoint, before any body is walked
    │
    ▼
[5/6] Type Checker     → Two-pass: collect declarations, then check bodies
    │
    ▼
[6/6] LLVM CodeGen     → LLVM IR text → llc → .o → cc → executable
```

There is no separate IR stage: `self_host/codegen.ax` walks the checked
AST and writes LLVM IR text directly. The three-address IR crate that
used to sit between them belonged to the retired Rust compiler
(the self-hosting record).

### Compiler structure

The compiler is `self_host/`, and it is written in Axiom. Every stage of
the pipeline above is a module you can read in the language it compiles.

| Module | Purpose |
|---|---|
| `core.ax` | Tokens and spans |
| `lexer.ax` | Tokenizer |
| `parser.ax` | S-expression parser and AST |
| `expand.ax` | Macro expansion, to a fixpoint, with the `syntax/*` query vocabulary |
| `namespace.ax` | Module names, qualified spellings and the `pub` rule |
| `typecheck.ax` | Name resolution, types, effects, AXTAG validation |
| `codegen.ax` | Import resolution, name mangling, LLVM IR emission |
| `diag.ax` | Diagnostics, AXDL and JSON rendering, source maps |
| `render.ax` | The human diagnostic renderer |
| `driver.ax` | `build`: `opt`, `llc`, `cc`, and blaming the right one; `--crate` running `cargo` and `axiom-bindgen`; grounding externs |
| `rustbind.ax` | `--emit-rust-binding`: the Rust module that calls an Axiom archive |
| `main.ax` | CLI entry point and subcommand dispatch |
| `build.ax` | one string literal: the build id `scripts/build-stamped.sh` rewrites in a copy of this directory, so a shipped binary names the tree it came from |
| `style.ax` | The one palette table every coloured render reads |
| `format.ax`, `repl.ax`, `symbols.ax`, `explain.ax`, `lsp.ax` | The tools |
| `Host.<target>.ax` | Host triple and syscall ABI, chosen when the compiler is *compiled* — a freestanding binary has no `uname` to ask |

---

## Implementation Status

| Feature | Status | Notes |
|---|---|---|
| Functions & types | **Complete** | Curried signatures, exact return types. A signature's type variables BIND: rigid inside the body, so `(:: f (-> a Int))` may not do arithmetic on its argument, and instantiated at every reference, so a caller may still pass anything. Two arguments that disagree with *each other* are not yet reported. `tests/selfhost/972-polymorphic-signature.ax`, `tests/diagnostics/460-signature-type-variable.ax` |
| Operators (prefix) | **Complete** | `tests/selfhost/910-operator-coverage.ax`. Eighteen: arithmetic (`+`, `-`, `*`, `/`, `%`), bitwise (`&`, `\|`, `^`, `<<`, `>>`), comparison (`==`, `!=`, `<`, `>`, `<=`, `>=`) and logical (`&&`, `\|\|`) |
| Let bindings | **Complete** | Variable resolution, sequential evaluation. `tests/selfhost/030-let.ax`, `tests/selfhost/100-letnest.ax` |
| if expressions | **Complete** | Proper branching with result values. `tests/selfhost/040-if.ax` |
| begin blocks | **Removed** | Replaced by `{ }` brace blocks and implicit sequencing. Reserved since 2026-08-26: `(begin a b c)` answers `AX2004` naming the brace block, where before it fell through to an application of a bare name and drew `AX3001 undefined variable begin` — a diagnostic that named no replacement (`tests/diagnostics/943-removed-begin.axbad`) |
| brace blocks | **Complete** | `{ expr1 expr2 ... }` — modern sequencing, returns last value. `tests/selfhost/080-seq.ax` |
| fn keyword | **Complete** | Modern alias for `define`. `tests/selfhost/020-call.ax` |
| FFI | **Functional** | The FFI is the `extern` BLOCK, and Rust is the language on the other side (`docs/ffi.md`). `(pub extern "lib" (add :: (-> Int Int Int) (symbol "axffi_add")))` emits `declare i64 @axffi_add(i64, i64) #0` for every item the program calls, and a call compiles to the same `call i64 @sym(...)` an internal call does - Axiom has no VM, so there is no trampoline and nothing to marshal for a scalar. On the Rust side `#[axiom_export]` writes the all-`i64` shim and `#[axiom_opaque]` the destructor; `axiom-bindgen` writes the Axiom module (a `String` result is copied, a `Result`/`Option` comes back through a status word and an out-cell, an opaque type is a `data` cell around a `Handle`), and `axiom build --crate DIR` is the whole build line: the driver runs `axiom-bindgen` and `cargo build` itself when the module or the archive is stale or missing, and the block's library links by itself. A callback crosses as `AxFn1`/`AxFn2`/`AxFn3` on the Rust side and `(-> Int Int)`, `(-> Int Int Int)`, `(-> Int Int Int Int)` on the Axiom side (`tests/ffi/demo/130`); a `Vec<T>` result and a `&[T]` parameter cross as a `Vec` for every word scalar `T` (`char` and `u64` included), `Vec<String>` out and `&[&str]` in likewise, `Vec<Vec<T>>` and `&[&[T]]` one level down, `&mut [i64]` in place (`140`, `160`, `170`, `180`–`184`); a `#[axiom_record]` struct crosses by value as its fields, one word each, and is a `data` type on the Axiom side, alone or in a `Vec` (`150`, `181`); `Result<Option<T>,E>` and `Option<Result<T,E>>` nest through the three statuses (`184`); every shim carries a descriptor (`axffi_add__sig_ii_i`) and a declaration of another shape is `AX4005` at the item before any tool runs. The other direction is `--emit-staticlib`: an Axiom module archived without `main`, every `pub fn` a C symbol, and `--emit-rust-binding` writes the Rust module that calls them in Rust's own types (`i64`, `f64`, `bool`, `char`, `&str` in, `AxString` out, and a `struct`/`enum` per `data` type, `Option<T>`, `Result<T,E>`, a user `List`, an `AxVecBuf` for a `Vec` — through accessor shims the same build synthesises into the archive), which `rust/examples/host` checks in and the gate regenerates, diffs and runs ten thousand round trips through. A `Handle` is a counted block of the FOREIGN FORM whose death runs the Rust `Drop` (`MM-FFI-6`): `tests/ffi/demo/060` builds 200 `Counter`s and lets them go, and Rust counts 200 drops. Calling an extern contributes `IO` and propagates transitively (`MM-FFI-5` requirement 3); `Foreign` is a compiler-known word outside the reference map (requirements 1 and 2); an item's signature is one word each way or `AX3036`; a symbol no linked archive defines is `AX4004` at the item, read from the archives' symbol tables, with the nearest `axffi_*` name. `foreign` is NOT this feature under a new name and stays reserved at `AX2004`. Freestanding is tiered and measured: a program with no `extern` imports **0** symbols, one bound to a `no_std` Rust crate (the facade's `nostd-runtime` feature) also imports **0**, and one bound to a `std` crate imports 188 - gated by `scripts/check-ffi.sh`, which runs every fixture and enumerates permitted symbols instead of forbidding all of them. Fixtures in `tests/ffi/`; the Rust support crates and their tests in `rust/` |
| Standard library | **Functional** | Twenty-two modules — `Pre`, `Mem`, `Str`, `Utf8`, `Vec`, `Map`, `Fmt`, `Intern`, `Sys`, `Path`, `IO`, `Show`, `Err`, `Fallible`, `Json`, `Rpc`, `Job`, `Html`, `Http`, `Ffi`, `Test`, `Agent.Tags` — written in Axiom over the syscall primitives; see [Modules](#modules). `Vec`/`Map`/`Intern` are golden-tested and validated at 10⁵ elements; against Rust at 10⁶, `Intern` is *faster* (0.73×), `Vec` is 3.4×, and `Map` is 1.80× — the cause was an affine hash, not the allocator, and the self-hosting record records the theories that were measured and rejected first. `scripts/bench-datastructures.sh` |
| Error handling | **Functional; not yet adopted** | `tests/stdlib/371-err-module.ax`, `tests/stdlib/370-error-propagation.ax`. `stdlib/Err.ax` ships `Result`, an `Error` record, `mapErr`/`andThen`/`mapOk`/`okOr`/`toOption`/`withContext`, checked `divChecked`/`remChecked`/`shlChecked`/`shrChecked` for the traps that otherwise exit 72, and the `try!` propagation form. `Result` is an ordinary declaration rather than a built-in beside `Option`, because a user-declared two-parameter ADT already checks, is pure to construct and inspect, and is reclaimed at a release boundary — a built-in would have cost a seed rebuild for none of that. Two measured rules decide how it is written and both are gated: the recursion in a propagating loop MUST be a match ARM's answer, never the scrutinee (the scrutinee shape costs 32 bytes of stack per call and dies at 262,144 where the arm shape runs 5,000,000 flat), and an error value crossing a tail-call boundary MUST be `let`-bound (288,176 bytes leaked over 2000 iterations otherwise, against 176). The block a fallible call returns **is reclaimed** as of 2026-08-25: it leaked 32 bytes a call under every spelling until then, and closing it took the checker recording the INSTANTIATED type of a `match` binder (`Ok`'s field is declared `a`; only the match site knows this one arrived as `Int`) so codegen could stop treating a machine scalar as something that can alias the block it was copied out of. `370-error-propagation.ax` terms 32 and 64 assert it, and `scripts/check-fallible-reclaim.sh` ablates the one word and requires that fixture to go red at term 32 and no other. The batch case — record 4,000,001 is malformed, skip it — is the `Fallible` effect since 2026-08-29 (`stdlib/Fallible.ax`, `ERR-REC-7`): one operation a callee performs on a bad record, answered per record by the loop's handler — `fallibleSkip`, `(fallibleDefault d)`, `(fallibleCounting tally next)` — without unwinding and at **0 bytes a record**; the two-argument and built-message spellings cost 32 and 80 and were refused by measurement. `tests/stdlib/410-fallible.ax` pins the handlers, the nesting and the bytes; the TRAP moved to compile time on 2026-08-30 and left that fixture - `Fallible` carries no `;@axiom:unhandled(trap)`, because its own header calls an unhandled operation a programmer error, so a `main` reaching `fallibleMalformed` undischarged draws `AX3053` before the program is built and `tests/diagnostics/389-unhandled-at-main.ax` pins that on this effect by name, and the `batch` probe of `scripts/check-steady-state.sh` holds 2,000,000 records at 1,376 KiB, the same as 200,000, with `examples/batch-fallible` under the same gate. What is NOT done is adoption: the standard library still signals failure with `-errno` and `-1` sentinels at **13 public functions over 7 modules**, and that number is gated — `compat/SENTINELS` records it per module and `scripts/check-compat.sh` refuses any module that RISES. The 84 this row used to claim came from a `grep` proxy that mostly counts comment lines; recomputed today that proxy reads 89, of which around sixty are prose. [docs/error-model.md](docs/error-model.md) marks every rule H/P/R and says which |
| Syscalls | **Complete** | `tests/selfhost/230-syscall.ax`. `__syscall0`-`__syscall6` on Darwin and Linux, x86-64 and AArch64; errors normalised to `-errno` on every platform |
| Allocation | **Functional; unbounded by default** | `mmap`-backed bump allocator emitted by the backend. (Defining `axiom_alloc` yourself does *not* override it — the name is refused outright, `AX3026`, because the override seam does not exist — [docs/memory-model.md](docs/memory-model.md) MM-ALLOC-8.) There is no manual `free`; every heap block carries a reference count and a shape word, and a block whose count reaches zero joins a size class and is handed out again — walking its reference map on the way, so a dead value takes what it owned with it: a discarded constructor cell holding a string frees the string's header *and* the string's bytes, and a thousand build-and-drop iterations move the allocator's bump by 384 bytes where they used to move it by 80,304 (`tests/stdlib/359-arc-str-bytes.ax`). **The self tail call is a release boundary since 2026-08-15** (MM-LIFE-2c event 4), which is the shape the strategy exists for - the activation that never returns: a loop allocating a fresh string per iteration and dropping the previous one moves the bump **480 bytes over 2000 iterations** where it used to move **224,304** (`tests/stdlib/362-arc-tail-boundary.ax`). What unblocked it was making the invisible stores visible: `Mem.memSetWord` and the AST's `mkNode` each `cast Int` a value out of the type system's sight, and both now take a share through `__retainref`, a type-directed retain that emits nothing at all when the stored word is an integer. **Events 2 and 3 shipped on 2026-08-21**, with owned temporaries: a reference a function answers is one share the caller holds and hands back, so the shapes they cover reclaim everything they build - every measured line of `tests/stdlib/372-arc-owned-results.ax` reads 0 bytes per iteration where three of them leaked 80. All seven of MM-LIFE-2c's events emit. **The arena scope IS the reclamation strategy as of 2026-08-24** (`MM-ALLOC-22`): `__axiom_arena_mark`/`__axiom_arena_reset` are what a request handler reclaims with, measured at 291× less memory than the same binary unscoped at ten thousand connections (`scripts/check-net.sh`, run 2026-08-24: 512 KiB scoped against 149,328 KiB; the exact ratio moves with the machine, so the gate asserts a floor of 50× rather than a number), and reference counting — `MM-LIFE-2a` — is **abandoned in place** rather than pending. What already emits stays and is not being finished; the residue it charges is 4,097 slab-head stores per reset, measured at under one percent of throughput. **The containers stopped being leaves on 2026-08-24** (`MM-LIFE-2h`): the shape word gained an ARRAY FORM - one bit saying every payload word of a block is a handle - which is the only encoding that can describe an element buffer, because the record form's bitmap holds 47 words and `Intern`'s string vector is 64 words before a single string is interned. `vecNewRef`, `mapNewRefVals` and `internNew` own what they hold; `vecFree`, `mapFree` and `internFree` hand it back, four levels deep (vector → data block → `Str` header → its bytes), and the identical program built with `vecNew` does not (`tests/stdlib/404-container-reference-maps.ax`, 255 - eight probes, one bit each). And the acceptance property above it (`MM-LIFE-2i`): a bounded LIVE SET has bounded memory in a process that frees no container and resets no arena - a 256-entry window over 2,000,000 inserts holds **1,392 KiB flat across a hundredfold** in iterations, against 34,368 KiB for the same program with the eviction removed (`scripts/check-steady-state.sh`). That gate found what the container gate could not: `mapNeedsGrow` counts tombstones, so an insert-and-remove workload doubled the table for entries that did not exist and reached 10 MB with 256 live keys. No tracing collector — the Rust compiler's `--gc` was not ported and the flag is now refused (the self-hosting record). See the memory model specification, [docs/memory-model.md](docs/memory-model.md) |
| Crash diagnosis | **Function-level only** | `tests/stdlib/400-backtrace.ax`, `scripts/check-backtrace.sh`. A trap writes its message, then `axiom: backtrace (most recent call first)` and one `  at <function>` line per stack frame — the OOM path names `__axiom_out_of_memory`, `axiom_alloc`, `Mem$memAlloc`, `__axiom_user_main`, `main`. Three pieces, none of them debug metadata: `"frame-pointer"="all"` on the module's one attribute group, a table of address-beside-name over every symbol the module defines, and a walker that resolves each return address at `ra - 1` (at `ra`, a call that is a function's last instruction resolves to the *next* function — measured, and it printed `axiom_alloc` for `main`). Cost at `--opt 2`: a hello-world binary 65,704 → 82,536 bytes, the compiler +1.3%, `check self_host/main.ax` unchanged at 0.51 s. **No line numbers**, no DWARF, `-g` still never passed; a SIGSEGV still yields nothing, because nothing catches the signal. Above `--opt 0` a trace is shorter than the source suggests because the frames were inlined away rather than lost |
| Releases and versioning | **Functional** | The installer is gated: `scripts/check-install.sh` serves a release built from the tree over the loopback, installs it, and requires a tampered archive, a missing checksum and an archive with no `stdlib/` to each be refused — with an ablation of `install.sh`'s own comparison proving that is what refuses them. `VERSION` is the single source of truth and `scripts/check-version.sh` holds eleven literals across eight files to it, each named with the count it must yield, plus what the built binary prints. A `v*` tag fires `release.yml`, which refuses a tag disagreeing with `VERSION` and builds two targets from the committed seed through the fixpoint. Since 2026-08-25 the shipped binary also names the TREE it was built from — `axiom version` prints a build id, twelve hex characters of a hash over every `.ax` byte under `self_host/` and `stdlib/` plus the commit, so two builds of two different trees at one version are distinguishable to whoever holds one (`scripts/check-build-id.sh`, `self_host/build.ax`). No `darwin-x86_64` artifact: it is assembled and byte-compared and executed by no runner. No `linux-x86_64` or `freebsd-x86_64` artifact either, for the opposite reason — it is fully supported and tested on every change, and only the prebuilt archive was dropped (2026-08-30); `scripts/check-release-targets.sh` holds the release matrix and `install.sh`'s refusal list to each other, ablated both ways |
| Cross-compilation | **Functional** | `--target` selects ABI and platform stdlib modules; every stdlib case assembled from one host for all seven targets at three levels and relocation-checked (`scripts/check-cross-targets.sh`); executed in CI on five of them — `darwin-aarch64`, `linux-aarch64`, `linux-x86_64`, `freebsd-x86_64` (a real 14.4 kernel in a VM, the whole stdlib corpus and five gates) and `windows-x86_64` (one hello world, linked and run on `windows-latest`, imports held to an allowlist). All five legs are blocking as of 2026-08-30; `darwin-x86_64` and `freebsd-aarch64` are assembled and relocation-checked only, and are the two the word *supported* does not cover (see *Targets*) |
| Self-hosting | **Done** | Axiom's compiler is written in Axiom. It compiles itself and reproduces itself byte-for-byte (`stage2 == stage3`, as objects and as IR), and a clean checkout builds it from `bootstrap/` with nothing but `llc` and a C linker. The Rust implementation it replaced has been removed. See the self-hosting record |
| ADTs / data types | **Complete** | `tests/selfhost/140-data.ax`, `tests/selfhost/400-mixed-nullary.ax`, `tests/stdlib/270-nullary-unboxed.ax`. A constructor with fields is a heap-boxed tagged value; a nullary constructor *is* its tag, in a mixed type as well as an all-nullary one, and a match over a mixed type reads the tag through a runtime `< 4096` immediate-vs-pointer guard. Recursive types like `List`/`Tree` need no special case. See [Algebraic data types](#algebraic-data-types-how-they-actually-run) |
| Structs | **Complete** | `tests/selfhost/150-struct.ax`. Declarations, LLVM emission, field access (`.field`), construction (`(StructName expr1 expr2 ...)`), `mut` fields, field mutation |
| Struct variants | **Complete** | `tests/selfhost/810-struct-variant-pattern.ax`. Named fields per `data` constructor, matchable by name and in any order, with field punning (`{ w, h }`) and partial patterns. `tests/stdlib/210-struct-variants.ax` |
| String literals | **Complete** | `tests/selfhost/310-strlit.ax`, `tests/selfhost/890-lexical-edges.ax`. A literal *is* a `Str`: a static `{ length, bytes }` header, length known at compile time, no allocation and no runtime scan. See [Strings](#strings) |
| Pattern matching (`match`) | **Complete** | `tests/selfhost/385-literal-in-ctor.ax`, `tests/selfhost/810-struct-variant-pattern.ax`. Constructor patterns (nullary and with-field), variables, wildcards, literals and nested constructor patterns all compare and bind correctly, plus non-exhaustiveness/arity/undefined-constructor diagnostics. There are no tuple or list patterns. Built-in `Option` type with `Some`/`None` constructors. |
| Lambda / function values | **Complete** | `tests/selfhost/950-multi-param-lambda.ax`. Closure record (code pointer + captures), passed as the callee's hidden first parameter; curried application, closures in `data` fields. A lambda of several parameters IS several lambdas — `(lambda (x y) b)` is `(lambda (x) (lambda (y) b))` — so it can be applied one argument at a time or all at once. Until 2026-08-10 only the one-parameter form existed: two were typed as taking a tuple, which no syntax can supply, and on the paths that got past the checker the emitter dropped the lambda and folded the call to its last argument at exit 0. `tests/stdlib/140-function-values.ax`, `tests/selfhost/950-multi-param-lambda.ax` |
| Lists | **Type syntax only** | `[Int]` parses and checks in a signature. There is no list literal (`[1 2 3]` is `AX2001`), no list pattern and no runtime representation |
| Tuples | **Type syntax only** | `(Int String Bool)` parses and checks in a signature. There is no tuple literal, no tuple pattern and no runtime representation |
| Type classes | **Replaced** | Renamed to traits; see [Traits](#traits) |
| Unions | **Removed** | C interoperability is not a goal, and an untagged union has no meaning under linear types. Use `data` for a tagged sum or `struct` for a product. `union` stays reserved and reports `AX2004` |
| Struct layout modifiers | **Removed** | `packed`, `repr(C)` and `align(N)` were documented and formatted but never parsed - all three are `AX2001`. The FFI needs none of them: a `#[axiom_record]` struct crosses as its fields, one word each, so no foreign caller ever reads an Axiom struct's layout ([docs/ffi.md](docs/ffi.md) §8) |
| Region syntax | **Removed** | Reclamation is never written by hand as a region annotation — the chosen automatic strategy is reference counting ([docs/memory-model.md](docs/memory-model.md) MM-LIFE-2a). `region` stays reserved and reports `AX2004` |
| Traits | **Functional** | Declarations, implementations (`impl`), and compile-time dispatch on the type of an argument: a call to a trait method resolves to the `impl` for that type and becomes a direct call, with no table and no indirection. Until 2026-08-10 `impl` was consumed as an inert node — its body was never type-checked and its methods were bound to nothing, so the example below was `AX3001 undefined variable eq` on its first use. Supertraits are enforced and default method bodies are generated; what remains is that a function generic over a trait cannot call its methods, because dispatch needs a concrete type at the call site. Every other shape is `AX3025`. `tests/selfhost/970-traits.ax` |
| Effects | **Enforced; two limits stated** | `tests/selfhost/820-effect-handlers.ax`, `tests/diagnostics/450-effect-op-arity.ax`. Effect declarations, `handle` expressions, effect checking (`IO`, `Pure`, `Alloc`, `Mut`, `Div` — `Err` was a sixth built-in NAME until 2026-08-30 and is retired: nothing ever inferred it and its own tag spelling reported it missing, so a handle list naming it now draws `AX3016`), AXTAG validation. This row said **Complete** while the design it was measured against had seven open items; five landed on 2026-08-29/30 and the row now says what holds and what does not. Since then: a handler is checked against its operation's arrow and `handle` answers its body's type (`AX3055`, `tests/diagnostics/386`, `387`); over-approximation is per effect rather than per row, closing the `AX3042` bypass every `{hole}` opened; an operation the program reaches with no handler is `AX3053`, a **warning** by design — on the two closure shapes the evidence is one-sided in both directions at once, so an error would refuse a program that exits 20 and accept one that exits 71, and `;@axiom:unhandled(trap)` is how a program says the trap is intended (`tests/diagnostics/severity.policy` carries the measurement); an effect named after a built-in is `AX3054`, an error, because a handle list resolves such a name to the built-in and the declaration could never be handled; and the fixpoint is a **worklist**, which took the order a generator emits — a helper beside each of its callers — from 56 s to 0.10 s at 8,000 functions. **What remains, stated rather than implied:** a closure application does not release its owned argument (96 bytes per operation, `stdlib/Fallible.ax`'s header carries the measurement), and `docs/memory-model.md` `MM-EXEC-9a`'s two under-approximations below. Effects propagate transitively through calls, so a claim on a caller is checked against what its callees do — including through a **trait method**, where the union covers every implementation because that is what dynamic dispatch means. The *inference* is not complete and the specification says so: `docs/memory-model.md` `MM-EXEC-9a` enumerates seven under-approximations, of which five are closed (the last three on 2026-08-25 — `__store8`/`__store64` as `Mut`, `__argc`/`__argv` as `IO`, the arena primitives as `Alloc`, asserted one primitive at a time by `scripts/check-agent-policy.sh` against controls that must stay silent). The two left are a call the compiler cannot resolve, which reports `#effects-incomplete` rather than a set that looks complete, and constructor allocation, which `ERR-PROP-2` relies on |
| Loops | **Complete** | `tests/selfhost/500-while-mut.ax`. `while` plus `mut` local bindings and `set`; 10⁷ iterations in constant stack at `-O0`. Self tail calls are guaranteed in the IR independently of `--opt`; mutual tail recursion still needs `--opt 1`+ ([docs/memory-model.md](docs/memory-model.md) MM-EXEC-6b/6c). Non-tail recursion is still stack-bounded at 60,000–80,000 frames |
| Linear types | **Removed** | `linear` and `consume` were refused on 2026-08-25 and now report `AX2004` with migration advice, joining `union`, `region`, `foreign` and `deriving`. They parsed and enforced nothing: no use was counted, so a value could be consumed twice or never, and `(consume e)` was a parse-time identity that reclaimed nothing. The memory model never relied on them — deterministic reclamation is the reference counting every heap block carries ([docs/memory-model.md](docs/memory-model.md)) — so a marker that read as an ownership guarantee and supplied none was worse than no marker |
| Macros | **Partial** | `tests/selfhost/365-macro-pattern-literal.ax`, `tests/selfhost/361-macro-hygiene.ax`. Macros come in two forms: the head-list form, one flat parameter list over one expression template, pure substitution; and the rule form, a list of one or more rules whose parameters are PATTERNS, selected by a match in rule order. The head-list form stays single-template by decision, because the two forms differ in what a template is. Both expand in their own pass (`self_host/expand.ax`) between import resolution and the checker, so everything a macro generates is type-checked; hygiene by renaming (`<name>.<counter>` gensym) — binder direction complete, and a module-defined macro's template resolves free identifiers at its definition site. `stdlib/Pre.ax` defines `when`, `unless`, `cond2`, `cond3` and the derivers `deriveEq`/`deriveShow`/`deriveArity`/`showOr`; cross-module macro import works, `Mod::name` qualification works (a qualified private macro is `AX3023`), an entry-file function outranks an imported macro of the same name, and a diagnostic inside an expansion carries a backtrace naming each enclosing macro with its declaration's own file and span (`tests/diagnostics/490-expansion-backtrace.ax`). Declaration macros v1 (2026-08-14): a rule-form macro — `(macro name ((name p...) decl...))` — invoked in declaration position generates `fn` and `::` declarations and further macro invocations, expanded to a fixpoint before any body is walked, checked and compiled like hand-written code, with parameters substituting in name, type (float flags recomputed) and expression positions (`tests/selfhost/372-decl-macro.ax`, 144; `373-decl-macro-types.ax`, 10); a typo'd declaration keyword is now `AX3027` naming the head instead of a bare `syntax error` that hid every later diagnostic. Invocation is no longer entry-file only (2026-08-15): a module invokes declaration macros over its own declarations, and its products join that module's namespace with the template's `pub` deciding what leaves it — which is what lets a library spend `stdlib/Pre.ax`'s `deriveEq` on its own types (`tests/selfhost/388-module-side-decl-macro.ax`, 239). The `syntax/*` query vocabulary landed the same day — `(syntax/join eq T)` names a generated declaration, `(syntax/constructors T)` and `(syntax/fields S)` answer from the declaration list at expansion time (no user code runs, ever — the vocabulary is closed and compiler-implemented), `(syntax/for (C seq) ...)` splices per element in match-arm, declaration, and argument positions, `(syntax/same f g)` decides a lens's diagonal at expansion time, `(syntax/binders C x)` names a constructor's fields as hygienic pattern binders, and `(syntax/fold && true ...)` chains a comparison over them (zipped in lockstep, the empty fold answering the zero) — which is enough for a working `deriveEq` over any sum type including fieldful constructors, a working `deriveLenses` over any struct, and the `impl`-generating form whose derived instances compose through static trait dispatch — all written as ordinary macros from the spec's worked examples (`tests/selfhost/374-derive-eq.ax`, `375-derive-lenses.ax`, `377-derive-eq-fieldful.ax`, `378-derive-eq-impl.ax`) — and `stdlib/Pre.ax` ships `deriveEq`, which derives over imported types too (`379-derive-imported.ax`). **The query table closed on 2026-08-15**: `(syntax/name C)` answers a constructor's spelling as a `String` and `(syntax/arity C)` its field count as an `Int` — neither is recoverable at run time, where a block records its tag and nothing else — `(syntax/defined n)` answers whether a name is declared and folds the `if` around it at expansion time so the losing branch is deleted rather than compiled, and a join now stands where a *reference* stands, so a macro can call what it names. Each landed with the prelude macro that spends it: `deriveShow`, `deriveArity`, `showOr` (`tests/selfhost/380-syntax-scalar-queries.ax`, 41). **A template may generate types**, not only functions (2026-08-15): `data` and `struct` joined `impl` on the template surface, a constructor's name is a name position so `(syntax/join Off N)` names one, two invocations of one macro give two distinct types, and a type generated in a round is queryable in that same round — `deriveEq` derives over a type a macro invented (`tests/selfhost/381-macro-type-templates.ax`, 32). **The iteration form's last two gaps closed on 2026-08-15**: several sequences zip in lockstep in every position `syntax/for` owns — `(syntax/for ((C (syntax/constructors T)) (D (syntax/constructors U))) ...)` converts one enumeration into a parallel one, and a length mismatch is `AX3028` rather than a truncation (`tests/selfhost/386-syntax-parallel-for.ax`, 63) — and a join may nest, so a generated name carries more than two parts: with two, a lens set over two structs sharing a field name generated `getX` twice and the program was `AX3006` (`tests/selfhost/387-syntax-nested-join.ax`, 47). `type` and `effect` joined the template surface the same day, which closes MAC-CAP-8's kind list: a macro generates a type alias and an effect declaration, names both from its arguments, and a joined name is writable in TYPE position so the signature beside a generated alias can name it (`tests/selfhost/389-type-effect-templates.ax`, 38). `import` and nested `macro` refuse by decision, because each would reopen a phase that has already run. **Multi-rule declaration macros landed 2026-08-15**: a rule-form macro is a list of rules and the invocation's ARITY selects one, two rules of one arity are refused at the macro's line, and an invocation matching none names every arity the macro offers (`tests/selfhost/390-multi-rule-macro.ax`, 51). **And on 2026-08-16 the rules stopped being chosen by counting**: a rule's parameters are PATTERNS (MAC-LANG-15) — a binder, `_`, an int/float/char/string literal, or a parenthesised form of patterns — and selection is a match tried in rule order, first match winning (MAC-LANG-18), so three rules of one arity told apart by shape are ordinary (`tests/selfhost/392-macro-patterns.ax`, 127; the compiler before it refuses the file at the first pattern's paren). Both refusals around it were re-derived rather than carried over: the "two rules of one arity" test narrowed to *unreachability* — an earlier all-binder rule of that arity starves the later one — and took its own code (`AX3033`) because a repeated PARAMETER and an unreachable RULE are not the same claim, and the no-match diagnostic names every SHAPE (`(defN (a b))` or `(defN T 7)`) where it used to name arities. **Repetition followed the same day** (MAC-LANG-16 v1): a rule's last element may REPEAT — `(build T v ...)` takes one argument and then any number, `v` binds all of them at once, and `(T v ...)` splices them — so one rule generates a two-field constructor call and a three-field one (`tests/selfhost/393-macro-ellipsis.ax`, 63). That is the variadic macro the language did not have. Its token half cost ONE implementation and not the four the spec predicted: `...` lexes as an ordinary identifier, three dots and no new token kind, so the formatter needed nothing and tree-sitter already parsed it. Breaking the depth rule — a repeating name used without `...`, `...` after something that does not repeat, two `...` in one rule, or a repeat over a pattern rather than a bare name — is `AX3034` in four shapes, split by whether the author can act at the macro or at the invocation. What patterns still do NOT do is dispatch on a head's *spelling* (literal identifiers, which need scope sets), which is the last of the spec's four dispatch axes. It is not the only thing that spec's `simplify` table needs: `(- e e)` wants a repeated binder read as a same-form test, which `MAC-LANG-15` refuses as last-wins (`AX3020`); `(f a ...)` wants a repeat INSIDE a nested pattern, which v1's rule-final repeat does not reach (`AX3034`); and its templates are expressions, which the rule form does not take. **And the last documented hygiene hole closed on 2026-08-16** — MAC-HYG-8 is done, all four. An entry-file macro's free identifier shadowed at the invocation used to compute with the local binding at exit 0 — 0 where the macro's own function answers 40 — then refused, and now resolves. The spec said this needed scope sets, an identifier becoming a `(name, scopes)` pair; it needed one bit of that and no representation change, because a macro is a top-level declaration and its template's free identifiers therefore have exactly one definition scope. Both resolvers had to learn it: with only the checker taught, the program type-checked against the macro's function and the emitter still called the local (`tests/selfhost/394-macro-entry-capture.ax`, 130). `AX3032` would now reject correct programs, so it is retired and out of the registry — the number burned, never reused. **The hole beside it closed outright on 2026-08-16**: a template naming something the macro's module merely *imported* used to stay bare and mean whatever the call site could see, and now resolves to the module that declares it — the spec had recorded this as blocked on import edges the merged declaration list does not carry, and it needs none, because every declaration in that list carries the module it came from (`tests/selfhost/391-macro-imported-name.ax`, 31; the compiler before it answers 13 with the capture term removed). Two modules declaring the name is an ambiguity the rewrite has no right to settle, so it leaves the name bare and the invocation reports `AX3014` carrying the expansion frame (`tests/diagnostics/595-macro-imported-ambiguous.ax`). The spec is [docs/macro-system.md](docs/macro-system.md); hygiene is renaming rather than the scope sets it once claimed, and the expansion backtrace is real and gated. **And the hole none of that had noticed closed on 2026-08-16** (MAC-HYG-10): a macro parameter standing in a BINDER position was renamed like a template's own binder, so `(macro (bind! x e body) (let ((x e)) body))` bound `x.N` and spliced a body that still said `v` — `AX3001`, on the macro whose whole job is to bind it. It blocked **every binding form the language could have** — `let*`, `for`, `with`, `try!` — and it hid behind the case that works: when a template binds and reads through the SAME parameter the rename table maps both sides to the gensym and the answer is right for the wrong reason, with the caller's name appearing nowhere. Only a macro taking a separate body could see it, and `stdlib/Pre.ax`'s are all single-expression templates, so none did. A parameter in binder position now takes the argument's name across all three positions the expander owns — `let`, `lambda` parameters, pattern binders — and an argument that is not a name is `AX3035` rather than the silent wrong expansion it used to be (`tests/diagnostics/590-macro-binder-target.ax`; `tests/stdlib/371-err-module.ax` is the first program that depends on the rule and does not compile without it) |
| Concurrency | **Library** | No language support and no compiler change: `stdlib/Job.ax` is a bounded pool of child processes over `Sys`'s existing `sysSpawn`/`sysWaitPid` pair, answering in submit order. Processes rather than threads, because a freestanding binary cannot create an OS thread on macOS. See the roadmap |
| API reference | **Generated** | [docs/stdlib-api.md](docs/stdlib-api.md): every public name of every standard-library module, with its source-spelled type, the effect row the compiler derived, and the first paragraph of the comment above it. Written by `examples/axdoc/axdoc.ax` — an Axiom program — and held byte-identical by `scripts/check-stdlib-api.sh`, which also requires every `(pub` name a `grep` finds in `stdlib/` to appear in it exactly once, so a dropped module fails against a source outside the generator. 586 names, 459 with a summary; the coverage number is a ratchet, so a new public name with no comment above it lowers it and has to be a conversation |
| Performance gates | **Rate covered** | Every timing gate here asserts a RATIO, deliberately, so a slow runner cannot fail one — which left *rate* uncovered until 2026-08-25. `scripts/check-arena-reset-rate.sh` makes the rate a ratio anyway: one program in three spellings a word apart attributes the cost of an arena reset at **about 1.35 µs** against a mark's few nanoseconds, **1.7–1.8%** of the 77 µs per-connection budget the memory model states — correcting that document, which said "under one percent" from an estimate. Two of its checks have no clock in them: the emitted IR's scrub is asserted directly, and the negative probe deletes that block from the IR and rebuilds, dropping the cost 42× |
| Type soundness | **Three classes closed** | A PARAMETERISED type answered through a bare `Int` is refused since 2026-08-26. `Int` is the universal heap handle and the tree relies on it — `mkSpan` declares `Int` and answers a `Span` — so `tyReprClash` names only `Bool` and `Float`, and a 2026-08-10 attempt at the general rule reported 21 of 271 files that were all correct. A parameterised constructor is different in kind: the handle keeps the address and throws the type ARGUMENTS away, so nothing downstream can recover what it holds. Measured twice during the `Result` migration, both silent — `IO.makeDir` returned a heap address where an errno belonged and `check` printed OK. Swept: **0 over 516 files**, with the monomorphic handle as a control that must stay accepted (`tests/diagnostics/498-param-through-int.ax`). And `AX3047` is an **error** since 2026-08-26: a C or Rust primitive type name written in type position. A lowercase name there is a type VARIABLE and there is no such thing as an unknown one, so `(:: f (-> u64 Int))` did not fail — it succeeded as `forall n. n -> Int`, and `(f "not a number")` checked **OK** and ran. The uppercase near-misses were already safe by a different route (`Double` and `I64` draw `AX3002`, because an unknown uppercase name is an unknown type *constructor*), which is why only the lowercase half was silent. The refusal is a **named set** and not a rule about length: refusing every multi-letter type variable would reject `(-> (Vec elem) (-> elem out) (Vec out))`, and the corpus licenses the set — across 3,456 AXSYM rows the whole type-variable vocabulary is six single letters. 26 spellings refused, 11 ordinary variables still accepted, a differential over 598 files showing zero divergences (`tests/diagnostics/496-sized-integer-type.axbad`, beside `495-widthless-types.ax` which pins the uppercase half). And `AX3040` is an **error** since 2026-08-25: a signature whose result is a type variable no parameter mentions, whose body produces that result rather than never returning. It was a warning because the rule conflated two shapes and only one is unsound — `(:: conjure (-> Int a))` casting a word out, and `(:: panic (-> String a))` never returning — which checked identically and then exited **139** and **70** respectively. The compiler now tells them apart exactly, because the type system admits only two ways to produce such a result: a `cast`, or a call to another such function. The set is solved by a fixpoint over tail positions — assume all diverge, strike out any whose tail can produce a value — with `sysExitWith` as the base case for "never returns", inherited by anything whose every tail reaches it. Eight diverging spellings are accepted and three fabricating ones refused. **The second shape closed 2026-08-25**: the rule asked whether the variable appears in a PARAMETER, and every left side of the arrow spine counted as one — so `(:: f (-> (-> a Int) Int))` with `(f (cast a 42))` drew *nothing*, checked OK and exited **139**, the same dereference one level in. The spine is now split by **variance** rather than by side: a variable with a position the callee must produce and none the caller supplies is unwitnessed wherever it sits, and that arm never consults the divergence fixpoint, because a function that fabricates on its way to returning an `Int` has no diverging reading to appeal to — nor does one that fabricates on its way to *not* returning: `(:: divDemand (-> (-> a Int) a))` has its result variable excused for diverging and still hands its callback a fabricated `a`, which is why the two arms decide their overlap rather than subtract it (measured, **139** again). The corpus does not move — 19 signatures here nest an arrow and the four with variables in one mention every variable on both sides. It reads the SIGNATURE, so a body that never calls its callback is refused too, which is asserted rather than left to be found (`scripts/check-diverging-tyvar.sh`, 26 checks; `tests/diagnostics/347`, `352`, `353`, `tests/selfhost/976`) |
| Test runner | **Functional** | `axiom test` and `stdlib/Test.ax`, gated by `scripts/check-test-runner.sh` over `tests/testrunner/`. A test is a top-level `test`-named function taking no parameters; the runner appends a `main` to the file's own bytes and arms one recovery point per test, so a failed assertion, an unhandled effect, an allocation failure and a division by zero each end ONE test and answer with a status (`ERR-REC-6`) — measured on a fixture that fails in three of those ways and still reports the test declared after all three. Nothing is skipped in silence: a file with no test fails, and a `test`-named function that takes parameters is refused by name. What is NOT here: no test may run in parallel with another, there is no setup/teardown, and a test cannot be marked expected-to-fail. See [Testing](#testing) |
| Editor support | **Functional** | [tree-sitter grammar](tree-sitter-axiom/) with highlighting and rainbow-bracket queries, gated against all 570 `.ax` files in the repo and a 38-case tree-shape corpus. The language server is `self_host/lsp.ax`, listed in the [Compiler structure](#compiler-structure) table above among *The tools*, and gated by `scripts/check-lsp-selfhost.sh`; [docs/lsp.md](docs/lsp.md) is the editor guide. It answers twenty requests. Navigation: go-to-definition for a macro invocation, a same-file function, `data` or `struct`, a name imported from another module (jumping into that module's own file) and — since 2026-08-28 — a local binding, landing on the `let`, parameter or pattern variable that binds it; `references`, `documentHighlight`, `prepareRename` and `rename`, all projections of one scope-aware walk over the raw parse tree, with references and rename reaching every other open document whose imports resolve to this file; `typeDefinition` for a signed function's result, a header parameter or a constructor. Reading: hover over that same set of names and over locals, quoting the declaration in an `axiom` fence — a `fn` as its `(:: f T)` signature rather than its body, a parameter as `x : Int` from the signature — with the comment paragraph written above it and, for an imported name, the module it came from; completion offering the parser's own head keywords, this document's declarations and constructors, and every imported module's names, prefix-filtered and sent `isIncomplete`; `signatureHelp` with the active parameter counted from the bytes; `inlayHint` for parameter names at call sites and parameter and result types from the signature; `foldingRange`, `selectionRange`, `documentLink` over imports, `documentSymbol` and `workspace/symbol`. Highlighting is the grammar's alone — `queries/highlights.scm` by syntactic role and `queries/rainbows.scm` for bracket pairs by depth — and the server sends no semantic tokens. Changing and running: `formatting` as one whole-document edit from the same `fmtFormat` the command runs; `codeAction` offering the compiler's machine-applicable fixes as quickfixes and an *Add type signature* assist written from the type the checker inferred; a `codeLens` to run `main`; and `axiom/expandMacro`, the analogue of rust-analyzer's, rendering what a macro generated as source through the compiler's first node-to-source printer. Every per-keystroke request reads the raw parse tree with no expansion (`MAC-TOOL-3`), so a name a macro would generate is not in the menu; only code actions and macro expansion run the pipeline, because a quickfix *is* a checker diagnostic and an expansion *is* the expander's output. The gate derives every expected answer from documents it writes itself, then fires every advertised request at every 97th byte of a real module, a truncated copy and an empty document — every advertised request at every kind of position, all answered |
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
parser, `AX3xxx` semantics, `AX4xxx` code generation and the build
driver, `AX5xxx` modules — and are stable across wording changes, so
they can be grepped and matched on.
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
├── rust/               # The FFI's other side: the support crates
│                       # (axiom-abi, axiom-ffi, axiom-bindgen, the macros
│                       # and the classifier) and the worked examples
├── examples/           # Programs, not fixtures. `axdoc/` generates
│                       # docs/stdlib-api.md from the library's own source
├── tree-sitter-axiom/  # Editor grammar, queries, corpus
├── tests/stdlib/       # Golden tests: compiled, run, output compared
├── tests/selfhost/     # Conformance cases: compiled, run, exit status checked
├── tests/diagnostics/  # AXDL and human-render goldens, per diagnostic code
├── tests/frontend/     # Parse-and-check cases, no code generation
├── tests/ffi/          # Axiom-calls-Rust and Rust-calls-Axiom fixtures
├── tests/docs/         # The checker that compiles the code blocks in these docs
├── tests/{fmt,repl,lsp,tools}/  # Goldens for each tool surface
├── scripts/            # The gates
└── docs/               # reference.md, stdlib-api.md (generated),
                        # memory-model.md, macro-system.md,
                        # diagnostics.md, error-model.md, ffi.md, lsp.md,
```

Every gate is a script in `scripts/`, and `.github/workflows/ci.yml` is
the list of the ones CI runs — so a contributor runs locally exactly
what CI runs. The ones you will reach for most:

```bash
./scripts/bootstrap-from-seed.sh     # seed -> stage1 -> stage2 == stage3
./scripts/run-stdlib-tests.sh        # stdlib, compiled and run
./scripts/check-self-host.sh         # conformance suite under the Axiom compiler
./scripts/check-bootstrap.sh         # the same ladder, driven by the compiler itself
./scripts/check-freestanding.sh      # no libc in the IR or the binary; on Windows,
                                     # every import on scripts/platform-allow.windows.txt
./scripts/check-platform-constants.sh # the emitted runtime and Sys.Platform
                                     # agree on every syscall number
./scripts/check-cross-targets.sh     # every target assembles, at -O0 and -O2,
                                     # with no PIE-hostile relocations
./scripts/check-reproducible.sh      # two runs produce identical IR
./scripts/check-tree-sitter.sh       # grammar accepts every .ax in the repo
./scripts/check-doc-drift.sh         # every number and fixture path in these docs
./scripts/check-ffi.sh               # the FFI fixtures, and what each one imports
```

`check-ffi.sh` is the one gate that needs a toolchain the rest do not:
it runs `cargo` over `rust/`, because the far side of the FFI is Rust.

`check-tree-sitter.sh` needs the tree-sitter CLI
(`npm install --prefix tree-sitter-axiom tree-sitter-cli`) and *fails*
without it rather than skipping — set `AXIOM_TREE_SITTER_OPTIONAL=1` to
skip deliberately — a gate that exits 0 when its checker is absent
reports success without checking anything.

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

The roadmap to v1 — what is done, what is left, and, the part that
determined the schedule, which items blocked which — was retired on
2026-08-23, along with the self-hosting record. Its ordering result had
been spent: the macro system and the LSP both waited on the memory
model, and the LSP on self-hosting, and all three have since landed.
What it still recorded is what v1 is *not*: HTTP is out of scope for the
standard library — the core owes an external package non-blocking
sockets, and nothing above them.

Both of the roadmap's open designs are decided, specified as normative
documents, and shipped. The memory model
([docs/memory-model.md](docs/memory-model.md)) is reference counting:
the `String`/`Int` fiat that blocked it is gone, blocks carry a count
and a shape word, dead blocks are freed, and all seven of MM-LIFE-2c's
ownership events emit as of 2026-08-21 - though the strategy
they belong to was abandoned in place on 2026-08-24 in favour of
the arena scope (`MM-ALLOC-22`), so what emits is what there will
be. The macro system
([docs/macro-system.md](docs/macro-system.md)) has shipped `derive`
into `stdlib/Pre.ax` and the pattern language, repetition and multi-rule
selection into the rule form; what is still only specified is dispatch
on a head's *spelling*, which needs scope sets.

What is left is adoption rather than mechanism: the standard library
still signals failure with `-errno` sentinels rather than `Result`
([docs/error-model.md](docs/error-model.md)). The cost that used to sit
beside that sentence — a fallible call leaking the 32-byte block it
returns — closed on 2026-08-25 (`ERR-MEM-4`).

Both documents are in history rather than in the tree, on the same
reasoning `docs/ffi.md` §17 gives for the design note it retired: a plan
whose ordering has been spent, and working notes whose every slice has
landed, describe a project that no longer exists, and a reader who
follows them is reading about the wrong compiler. What they measured is
in the specifications that outlived them — the memory model, the macro
system, the error model — and in the gates, which assert it on every
run instead of asserting it once in prose.

They are still the record of *how* it was done, so they are still
readable:

```bash
git show d7622c2:docs/v1-roadmap.md     # the plan, and what blocked what
git show d7622c2:docs/self-hosting.md   # replacing the Rust compiler, slice by slice
```

The second is the measured gap analysis that started the self-hosting
work and the working notes of every slice that closed a gap; comments
throughout `self_host/` still cite it by name as *the self-hosting
record*.

---

## License

MIT
