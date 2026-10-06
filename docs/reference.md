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
- [Formatting](#printing-and-formatting), [memory](#memory), [concurrency](#concurrency) and [Rust](#calling-rust)
- [Library](#standard-library), [metadata](#axtag-metadata), [commands](#cli-commands), [tests](#testing) and [targets](#cross-compilation)


## Hello, Axiom

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

Save this as `hello.ax` and run `axiom run hello.ax`. It prints
`Hello, Axiom!`. `axiom build hello.ax -o hello` creates a native executable.

`import` brings in a module, `::` declares a type, and `fn` defines a
function. `main` returns the exit status. The `effect(io)` tag declares
its I/O; the compiler checks that declaration. Braces evaluate
expressions in order and answer the last one.

### Fallible main

`main` may return `(Result Int Error)` instead. Import `Err`: `(Ok n)`
exits with `n`; `(Err e)` prints `axiom: ` followed by `errorText e` and
exits 70. Use `try` to propagate failures. See [error handling](stdlib.md#err-and-fallible).

Tested by `tests/stdlib/490-main-result-ok.ax` and `tests/stdlib/491-main-result-err.ax`.


## Syntax basics

<a id="forms"></a>

<a id="whitespace"></a>

<a id="comments"></a>

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


## Literals

<a id="escape-sequences"></a>

<a id="string-literals-are-str-values"></a>

<a id="strings-and-integers-are-different-types"></a>

| Value | Spelling |
|---|---|
| integer | `42`, `-7`, `1_000_000` |
| floating point | `3.5`, `1000000.0` |
| Boolean | `true`, `false` |
| character | `'A'`, `'é'`, `'\n'` |
| string | `"hello"`, `"line one\nline two"` |

Numbers are decimal; source literals have no hexadecimal or exponent form.

Escapes include `\n`, `\r`, `\t`, `\0`, `\\`, `\"` and `\'`.
Strings may span source lines. A string literal is a `String` value;
`Str` reads its bytes and `Utf8` reads code points.

String equality compares contents. Use `strCmp` for ordering. A string and an integer
have different types even though both occupy a machine word.

See [strings and collections](stdlib.md#strings-and-collections).


## Identifiers and keywords

<a id="identifiers"></a>

<a id="keywords"></a>

<a id="removed-keywords"></a>

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

<a id="parameters"></a>

<a id="several-expressions-in-a-body"></a>

<a id="fill-in-an-argument-later-with-_"></a>

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

A signature `(-> A B C)` takes `A`, then `B`, and returns `C`. A
function taking no parameters has its result type as its signature.
Write signatures for public functions and callback interfaces.

### Lambdas

A lambda is a function value. It can capture values in its enclosing scope.

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


This prints `42` twice. A bare `_` elsewhere in an expression is
undefined; in a pattern it is a wildcard.


## Operators

<a id="integer-arithmetic"></a>

<a id="floats-and-strings"></a>

<a id="operator-types"></a>

All operators are prefix. Parentheses decide grouping.

| Operation | Operators |
|---|---|
| arithmetic | `+`, `-`, `*`, `/`, `%`; unary `-` negates |
| comparison | `==`, `!=`, `<`, `>`, `<=`, `>=` |
| Boolean | `&&`, `||`, `!` |
| bits | `&`, `|`, `^`, `<<`, `>>` |

`&&` and `||` short-circuit. Integer arithmetic uses signed 64-bit
words. Addition, subtraction and multiplication wrap; division by zero,
`intMin / -1`, and shifts outside 0..63 trap. Use `Err`'s checked
arithmetic when failure should be a `Result`.

Float arithmetic uses two `Float` operands. Convert numeric types with
`__intToFloat` and `__floatToInt`; `cast` alone does not perform that
numeric conversion. `String` equality reads contents; ordering uses `strCmp`.


## Let bindings

<a id="mutable-bindings-and-while"></a>

<a id="conditionals"></a>

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

Bindings are sequential: `y` can read `x` above. A later binding can
shadow an earlier name. The body answers its last expression.

### Mutable bindings

Declare a mutable binding with `mut`, then change it with `set`:

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


This prints `2`. Assignment returns the assigned value. A closure may
capture an immutable binding; mutable captures have additional
restrictions described in [memory](#memory).


## Control flow

<a id="for--the-counted-loop-and-the-container-loop"></a>

<a id="when-a-loop-is-refused"></a>

<a id="loop-over-a-string-or-a-map"></a>

<a id="for-as-a-name"></a>

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

<a id="type-signatures"></a>

<a id="sized-integers-and-floats--removed"></a>

<a id="compound-types"></a>

<a id="type-variables-and-polymorphism"></a>

<a id="type-casting"></a>

<a id="effect-types"></a>

### Primitive types

| Type | Meaning |
|---|---|
| `Int` | signed 64-bit integer |
| `Float` | IEEE 754 binary64 |
| `Bool` | `true` or `false` |
| `Char` | Unicode code point |
| `String` | byte string |
| `Foreign` | externally owned pointer; ARC does not follow it |
| `Handle` | counted owner with an external destructor |
| `()` | empty tuple type, with no expression value |

Compound types include `(Vec Int)`, `(-> Int String)` and `(* Int)`.
Use `struct` for products and `data` for sums; list and non-empty tuple
types are removed. `Int` and `Float` are the numeric types; sized
integer and float names are refused.

Lowercase type parameters describe polymorphism. For example,
`(-> a a)` returns the same type it takes. A caller's concrete argument
witnesses a type parameter; a result-only parameter requires the
explicit low-level contract described in [diagnostics](diagnostics.md).

`cast` changes the declared representation type. It does not make a
raw address valid or extend its lifetime. Raw memory and foreign
operations belong behind an `effect(unsafe)` declaration. Library
functions that take a raw address, such as `memGetWord`, trust it, so
passing one a bad address crashes the program.

A function's result is checked like an argument. A record, closure,
`String` or type variable returned where the signature says `Int` is
`AX3004`, so declare the type the body answers. `(cast Int v)` still
turns a reference into a word that holds no share.

### Region annotations

Signature region annotations describe lifetime relationships. They do
not name a `region` expression's arena or implement general promotion.
The current enforcement and remaining gaps are in the
[memory model](memory-model.md) and [region design](memory-model.md).


## Type aliases

`(type Name = String)` gives another name to `String`; the two are
interchangeable. An alias takes no type parameters: `(type Pair (a) =
(Vec a))` is refused with `AX3096` where you declare it. Write the
target type where you use it, or declare a `struct` or `data` type.
Tested by `tests/diagnostics/1133-alias-params.axbad`.

### Range-constrained subtypes

`(subtype Percent is Int range 0..101)` makes a distinct integer type.
The upper bound is excluded. Narrowing with `(cast Percent n)`, or at
a declared parameter/result boundary, checks the range at run time and
traps with status 80 on failure. Widening to `Int` needs no check.
Arithmetic does not prove that its result stays within the range.

Use an alias for naming, a subtype for a checked integer range, and a
`struct` or `data` wrapper for another nominal type.

Tested by `tests/selfhost/973-type-alias.ax` and `tests/selfhost/134-subtype-checked.ax`.


## Algebraic data types

<a id="struct-variants--named-fields-per-constructor"></a>

<a id="deriving"></a>

<a id="how-adts-actually-run"></a>

<a id="how-adts-are-represented"></a>

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

Construct a value with `(Just 42)` or `(Cons 1 (Nil))`. Nullary
constructors can also be written bare. The `(a)` declares a type
parameter. Constructors can refer to the type recursively.

A variant may name its fields, for example `(Circle { r : Int })`.
Construction remains positional; named fields support the variant's
structural view.

`Pre` supplies `deriveEq` and `deriveArity`. Formatting already handles
renderable data types; no derive is needed for printing.


## Pattern matching

<a id="matching-constructors-with-fields"></a>

<a id="matching-literals"></a>

<a id="nested-patterns"></a>

<a id="wildcard-pattern"></a>

<a id="exhaustiveness-checking"></a>

<a id="the-built-in-option-type"></a>

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

Arms can match constructors, nested patterns or literals. `_` matches
anything and binds nothing. Every possible constructor must be covered,
or the compiler reports AX3005. Constructor patterns need the right
number of fields, and arm results must agree in type.

`Option` is built in: `Some` holds a value and `None` means absence.
`Err` supplies `Result`, whose constructors are `Ok` and `Err`.


## Structs

<a id="constructing-binding-and-reading-a-field"></a>

<a id="build-a-struct-and-read-its-fields"></a>

<a id="writing-a-field"></a>

<a id="write-a-field"></a>

<a id="every-field-needs-a-type"></a>

<a id="type-parameters"></a>

<a id="fields-that-hold-functions"></a>

<a id="limits"></a>

Declare typed fields; construct in declaration order and read through
a bound name. Field access attaches to a name, so bind a call's result
before using `.field`.

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


A struct is built by calling its name, `(Point 1 2)`; `struct` only
declares, and `(struct Point 1 2)` in an expression is refused with
`AX2004`. A mutable field is declared `(mut x : Int)` and assigned with
`(set p.x 9)`. Structs may have type parameters and function fields.
Each function field must carry its complete arrow type.

### Make a handle other modules can't forge

`(pub struct File sealed (owner : Handle))` is a counted reference whose
constructor and fields are private to its module. Public operations
control access and closing.

`(struct Ticket word (slot : Int))` is an unallocated single-word
handle. It has one immutable `Int` field, no type parameters, and only
its declaring module can construct it or read the field. Add `shared`
only when its operations are safe across concurrent bindings.


## Capability records

<a id="effects-through-a-record"></a>

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

An interface is a parameterised struct of functions. Calling a member,
such as `(s.render value)`, is ordinary function application. Each
member declares its own effects. Records replace traits and `impl`.


## Effects

<a id="how-inference-works"></a>

<a id="built-in-effects"></a>

<a id="annotating-functions-with-effects"></a>

<a id="annotate-a-function"></a>

<a id="declaring-an-effect-type"></a>

<a id="declare-an-effect"></a>

<a id="handling-effects"></a>

<a id="handle-an-effect"></a>

<a id="when-nothing-handles-an-operation"></a>

<a id="effect-polymorphism"></a>

<a id="the-unsafe-layer"></a>

<a id="when-the-walk-cannot-answer"></a>

<a id="when-inference-cant-answer"></a>

<a id="definite-and-possible"></a>

<a id="axtag-keys"></a>

<a id="effect-tags"></a>

<a id="restrict---what-a-declaration-does-not-do"></a>

<a id="the-restrictions"></a>

<a id="read-a-violation"></a>

<a id="when-the-walk-cant-settle-a-claim"></a>

<a id="make-an-unproven-claim-an-error-with-strict"></a>

<a id="where-a-restriction-attaches"></a>

<a id="isr---an-interrupt-entry-point"></a>

<a id="pre--post---a-claim-the-compiler-cannot-decide"></a>

<a id="unhandledtrap---an-effect-whose-unhandled-operation-is-the-design"></a>

<a id="unhandledtrap-an-effect-that-may-abort"></a>

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
| `Div` | possible divergence |
| `Unsafe` | caller-established low-level obligations |
| `Spawn`, `Block`, `Entropy` | process/task creation, waiting, and randomness |

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


An operation runs the innermost installed handler. The handler's return
value becomes the operation's result and execution continues. Nested
handlers restore the previous one when their extent ends.

`handle` lists every effect the body performs. A custom effect in the
list is intercepted; a built-in is acknowledged and still reaches the
caller. The handler's own effects also reach the caller. An operation
cannot be passed bare as a callback; wrap it in a lambda.

### restrict: what a function never does

Use `;@axiom:restrict(no-alloc,no-io)` to forbid operations transitively.
Other restrictions include `no-unsafe`, `no-block`, `no-spawn`,
`no-recursion` and `no-trap`. Add `strict` to refuse an unresolved claim
instead of receiving a warning. The [restricted profile](restricted-profile.md)
lists the supported restrictions and their limits.

### Contracts: pre and post

`pre` checks arguments and `post` checks the bound name `result`:

```scheme
;@axiom:pre((> n 0))
;@axiom:post((>= result 0))
(:: half (-> Int Int))
(fn (half n) (/ n 2))
```

Checks run on every call and trap with status 80 on failure. They
cannot be disabled. They are runtime conditions, rather than proofs
of value ranges.

### isr: an interrupt entry point

`isr` checks a no-argument handler for allocation, recursion and waiting.
On `baremetal-aarch64`, `isr(irq)` binds the interrupt handler and
`isr(fault)` supplies a fault policy. See the [embedded guide](embedded-guide.md)
for signatures, startup and interrupt assumptions.

### nolint: quiet the editor's Hints

`nolint` suppresses the selected editor hints; it does not suppress
compiler errors. Effect-inference facts and metadata are described in
[symbol tags](diagnostics.md#read-symbol-tags) and [diagnostics](diagnostics.md).


## Modules and imports

<a id="visibility"></a>

<a id="how-imports-work"></a>

<a id="import-a-module"></a>

<a id="qualified-names"></a>

<a id="the-search-order-stated-exactly"></a>

<a id="where-modules-are-found"></a>

<a id="when-an-import-fails"></a>

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


## Packages

<a id="projects"></a>

<a id="start-a-project"></a>

<a id="the-manifest"></a>

<a id="depend-on-a-directory-of-modules"></a>

<a id="depend-on-a-rust-crate"></a>

<a id="registry-dependencies"></a>

<a id="depend-on-a-git-repository"></a>

<a id="what-packages-dont-do"></a>

Start a project with `axiom new app`, then run `axiom build` or
`axiom run` inside it. The `axiom.pkg` manifest supplies the entry file,
optimisation default and dependencies.

```text
main Main.ax
opt 1
depend vendor/lib
crate vendor/native
```

A dependency may be a directory of modules or a git URL. `axiom fetch`
checks out git dependencies under `.axiom/deps/`. Packages do not yet
pin versions or resolve a registry. Crates provide generated Axiom
wrappers and native archives; see [calling Rust](ffi.md).


## Macros

<a id="write-an-expression-macro"></a>

<a id="hygiene"></a>

<a id="generate-declarations"></a>

<a id="ask-about-the-programs-types"></a>

<a id="match-on-the-arguments"></a>

<a id="match-a-fixed-spelling"></a>

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

`(macro (name argument ...) template)` substitutes syntax before type
checking. Arguments used twice are evaluated twice; bind a temporary
when the operation should happen once. Template-local binders are
renamed hygienically.

Macros can generate declarations and inspect syntactic type
information. They do not execute arbitrary source code during
compilation. Use `Pre`'s common macros, and read the
[macro specification](macro-system.md) for declaration templates,
`syntax` queries, pattern matching and expansion limits.


## Printing and formatting

<a id="holes"></a>

<a id="specifiers"></a>

<a id="mistakes-the-compiler-catches"></a>

<a id="print-your-own-types"></a>

<a id="choose-a-different-rendering"></a>

<a id="when-the-type-isnt-known"></a>

<a id="replacing-removed-print-functions"></a>

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

<a id="the-functions"></a>

<a id="save-and-restore"></a>

<a id="what-raw-mode-changes"></a>

<a id="window-size"></a>

<a id="targets"></a>

Use `IO`'s terminal operations for dimensions, raw mode and saved
settings. `Tui.Keys` decodes key events, `Tui.Edit` implements a pure
line editor, and `Tui.Term` connects it to terminal I/O. Restore saved
settings when leaving raw mode. The [library API](stdlib-api.md#tuiterm)
lists the exact operations.


## Memory

<a id="how-memory-is-reclaimed"></a>

<a id="choosing-a-memory-manager"></a>

<a id="work-with-arena-marks"></a>

<a id="containers-that-own-what-they-hold"></a>

<a id="recover-from-a-trap"></a>

<a id="memory-primitives"></a>

<a id="low-level-primitives"></a>

<a id="system-calls-and-platforms"></a>

Heap values use reference counting. Releasing the final share releases
the block's owned fields and makes storage reusable. The executable
includes its allocator. There is no tracing collector or `--gc` mode.
Reference cycles require explicit application management.

### Regions
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

A `region` reclaims allocations made inside it when its body ends.
Its result and stores into outer bindings must be scalar. References
that outlive a region are refused where the compiler can see their
escape. Raw addresses and remaining low-level escape gaps are explicit
Unsafe obligations; a region is not a general lifetime proof.

Nested regions reset innermost first and cannot reuse an open name.
A region performs `Alloc`. Signature region annotations and expression
arena names are separate mechanisms.

Owning containers use `vecNewRef` or `mapNewRefVals` to retain their
contents. Files, sockets and foreign owners close at their last share;
explicit close retires them early. Cycles and destruction costs are
covered by the [memory contract](memory-model.md).

Recovery points catch runtime traps in an isolated extent. They cannot
undo external I/O. See [error recovery](error-model.md).

### Inline assembly

The low-level layer includes raw memory, syscalls, volatile MMIO and
`asm`. A function that uses them says `;@axiom:effect(unsafe)`. Inline
assembly operands, clobbers and target checks are in the
[embedded guide](embedded-guide.md).


## Concurrency

<a id="parallel--bindings-that-run-beside-the-caller"></a>

<a id="run-expressions-side-by-side-with-parallel"></a>

<a id="processes-or-threads"></a>

<a id="when-two-bindings-fail"></a>

<a id="what-a-binding-may-answer"></a>

<a id="pass-words-between-bindings-with-a-channel"></a>

<a id="wait-with-a-deadline"></a>

<a id="guard-shared-state-with-a-mutex"></a>

<a id="run-a-pool-of-tasks-with-par"></a>

<a id="what-stays-the-same-from-run-to-run"></a>

<a id="where-parallel-is-available"></a>

<a id="under-the-hood"></a>

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

`parallel` starts the bindings and joins them in source order before
running the body. Declare `effect(io)`, `effect(spawn)` and
`effect(block)`. Ordered answers do not order side effects.

The default hosted lowering uses isolated processes. `--threads` selects
threads on Linux and macOS. Captures remain restricted in both modes;
process boundaries do not transfer general managed pointers.

### What a binding may capture

Bindings may capture immutable scalars, borrowed strings and immutable
`data` graphs, and explicitly
shared word handles. Mutable bindings, ordinary heap structs, resource
owners and closures are refused. A shared handle's module must enforce
synchronisation. Thread arenas and reference counts alone do not make
payload mutation safe.

Each binding answers an `Int`. Use `Chan` for bounded word channels and
`Sync` for shared mutexes. Their timeout, close and owner-death behaviour
is in the [library API](stdlib-api.md#chan).
Free a channel, mutex or cancellation token after its concurrent users
finish. A use after the free traps 85, but nothing catches a free
that races a use still in flight.

### Run tasks that answer values with `Task`

`taskMap worker count width limit` runs `(-> Int String)` tasks with at
most `width` children and a per-result byte limit. Results are
`(Result String Error)` values in submit order. `TaskOpts` adds deadlines,
cancellation and fail-fast behaviour. `taskFold` consumes answers with
a scalar accumulator; the callback must not retain region-owned values.

`Par` offers word and external-command pools. The
[library reference](stdlib.md#task-par-chan-and-sync) gives the entry
points, and the [memory model](memory-model.md) defines publication,
atomic ordering and lifecycle rules.


## Calling Rust

<a id="rules-for-an-extern-block"></a>

<a id="when-a-symbol-doesnt-link"></a>

<a id="call-axiom-from-rust"></a>

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

<a id="the-filesystem"></a>

<a id="work-with-files-and-directories"></a>

<a id="a-str-is"></a>

<a id="connect-over-tcp"></a>

<a id="strings-are-bytes"></a>

<a id="text-is-utf-8-and-str-stays-bytes"></a>

<a id="work-with-utf-8-text"></a>

<a id="build-a-line-editor"></a>

<a id="hold-a-growing-list"></a>

<a id="map-keys-to-values"></a>

<a id="say-what-can-go-wrong"></a>

<a id="keep-going-past-bad-records"></a>

<a id="render-values-as-text"></a>

<a id="parse-and-print-floats"></a>

<a id="work-with-paths"></a>

<a id="parse-and-write-json"></a>

<a id="read-dates-and-times"></a>

<a id="store-rows-in-a-file"></a>

<a id="hash-seal-and-sign"></a>

<a id="frame-messages-for-tools"></a>

<a id="wrap-values-from-rust"></a>

<a id="intern-repeated-strings"></a>

<a id="use-the-prelude-macros"></a>

<a id="find-the-modules-covered-elsewhere"></a>

Use the [standard-library reference](stdlib.md) to choose modules and
copy small recipes. It includes a [Net section](stdlib.md#net) for TCP.
The [generated API](stdlib-api.md) is the complete signature and effect
listing. Every module is Axiom source; hosted programs reach the kernel
without a C library unless they link foreign code. Windows uses
kernel32 through its platform layer.

<details>
<summary>Browse every module</summary>

### Modules at a Glance

Sixty-two modules, all of them Axiom source under `stdlib/`, plus the six
`Sys.Platform.*` target files covered by `Sys`. Only names marked `pub`
are exported.

| Module | Public API |
|---|---|
| `Pre` | [API](stdlib-api.md#pre) |
| `Mem` | [API](stdlib-api.md#mem) |
| `Str` | [API](stdlib-api.md#str) |
| `Utf8` | [API](stdlib-api.md#utf8) |
| `Vec` | [API](stdlib-api.md#vec) |
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
| `Par` | [API](stdlib-api.md#par) |
| `Chan` | [API](stdlib-api.md#chan) |
| `Sync` | [API](stdlib-api.md#sync) |
| `Task` | [API](stdlib-api.md#task) |
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
functions and signatures. Effect claims, restrictions, contracts and
interrupt tags affect validation. Descriptive tags remain metadata;
they do not establish a proof by themselves.

A key one slip from a checked key, such as `;@axiom:restirct(no-alloc)`
or `;@axiom:Effect(io)`, is refused with `AX3039`, so a claim never
drops out unnoticed. Give a key of your own a namespace, such as
`;@axiom:my:owner(storage)`, and it is recorded without being checked.
Tested by `tests/diagnostics/1134-axtag-near-miss.ax`.

Use `axiom --diagnostic-format=ai symbols file.ax` to inspect accepted
tags and inferred facts. [Symbol tags](diagnostics.md#read-symbol-tags) describes reading
those rows, and [diagnostics](diagnostics.md) documents their format.


## CLI commands

<a id="checking-and-building"></a>

<a id="using-the-ai-optimized-format"></a>

<a id="symbol-listing"></a>

<a id="diagnostic-lookup"></a>

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
| `explain AX3001`, `explain --list` | explain diagnostics |
| `repl`, `lsp`, `version`, `help` | interactive session, editor server, version and help |

`axiom help COMMAND` is the option reference. The first operand is
always a command, so `axiom file.ax` is refused; write
`axiom emit-llvm file.ax --target TARGET` to emit IR.

### Build and run

`--opt 0..3` sets optimisation. `--threads` selects hosted thread
lowering. `--heap-ceiling BYTES` bounds the arena and refuses threads.
`--obfuscate` obscures literals and internal names in executables;
[obfuscation](obfuscation.md) explains its limits and asset packing.

### Machine-readable output

Use `--diagnostic-format=ai` for AXDL diagnostics and AXSYM symbols.
JSON diagnostics use `--diagnostic-format=json`. `symbols` refuses
JSON with status 2; use AXSYM. Diagnostics go to standard error.

### List a file's symbols

`symbols FILE --calls` includes resolved call edges. Add `--mir --axir`
for inspection records. Native compilation uses the AST backend;
AXIR is not a build input. See [compiler inspection](compiler-guide.md).

### Look up a diagnostic code

`axiom explain AX3001` describes the error and a correction. The
[diagnostic reference](diagnostics.md) documents codes, spans and fixes.


## Testing

<a id="discovery-and-the-two-anti-silence-rules"></a>

<a id="choose-which-tests-run"></a>

<a id="setup-and-teardown"></a>

<a id="set-up-and-tear-down"></a>

<a id="assertions-take-a-label-first"></a>

<a id="assertions"></a>

<a id="one-failure-ends-one-test"></a>

<a id="marking-a-test-expected-to-fail"></a>

<a id="mark-a-test-expected-to-fail"></a>

Import `Test`, then declare no-argument functions whose names start
with `test`. Assertions take a label first:

```scheme
(import Test)

(:: testAddition Int)
;@axiom:effect(io)
(fn (testAddition)
  { (assertEq "two plus two" 4 (+ 2 2)) 0 })
```

Run `axiom test tests.ax`. A directory runs its immediate `.ax` files
in name order; `--filter TEXT` selects names. No tests or no matching
tests is a failure. `setup` and `teardown` run around each test.

A failed assertion or trap fails that test and the runner continues.
Use `expect` for a known failing test; a passing expected failure is
reported as XPASS and fails the run.

Tested by `scripts/check-test-runner.sh`.


## The REPL

<a id="example-session"></a>

<a id="a-short-session"></a>

<a id="repl-commands"></a>

<a id="editing-at-a-terminal"></a>

Run `axiom repl` to evaluate expressions and add definitions. Completed
forms run; incomplete forms continue onto another line. `:help` lists
commands, including `:type`, `:load`, `:reset` and `:quit`.

```text
Axiom 0.7.8 - REPL
```

For editor completion, navigation, formatting and fixes, configure
[the language server](lsp.md).


## Cross-compilation

<a id="supported-is-not-the-same-as-shipped"></a>

<a id="freebsd"></a>

<a id="windows"></a>

Supported targets: `darwin-aarch64`, `linux-aarch64`. The host is the default.

A target is supported when a CI job executes what the compiler emits there.
`darwin-x86_64`, `freebsd-aarch64`, `freebsd-x86_64`, `linux-x86_64`,
`windows-aarch64` and `windows-x86_64` are source-only: CI builds or
assembles their code, without the whole execution battery. They have
no prebuilt release archive. See [targets](../README.md#targets).

Select a target with `--target=linux-aarch64`. Windows is an output
target; the compiler does not run there. Linking Windows executables
requires `lld-link` and a matching `kernel32.lib`, supplied through
`--link-search`. Windows static-library emission is refused.

For `baremetal-aarch64`, use the [embedded guide](embedded-guide.md) for
the board, linker layout, static heap and fault policy. Emulator
execution and hardware validation are distinct.


## Optimisation

<a id="how-deep-a-loop-can-go"></a>

<a id="link-time-optimisation"></a>

<a id="vectorization"></a>

<a id="compiler-pipeline"></a>

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
`try` replaces `try!`, `for` replaces `range`, and `restrict(no-trap)`
replaces `restrict(no-untrapped)`.

Foreign libraries use `extern`; the older `foreign` keyword is reserved.
See [compatibility](compatibility.md) and `compat/BREAKING` for migration
records.


## Tips and patterns

<a id="write-a-function-that-does-io"></a>

<a id="name-intermediate-values-with-let"></a>

<a id="handle-a-missing-result-with-option"></a>

<a id="build-and-walk-a-list"></a>

<a id="use-the-standard-library"></a>

Keep I/O at a boundary, name intermediate values with `let`, and use
`Option` for absence and `Result` for failure. Use `try` to keep result
handling flat. Prefer typed library operations to raw-memory calls.

[Library recipes](stdlib.md) and [complete examples](../examples/README.md)
show these patterns in programs.


## Further reading

[Library recipes](stdlib.md), [exact API](stdlib-api.md),
[editor setup](lsp.md), [Rust FFI](ffi.md),
[current feature status](status.md) and [contributing](../CONTRIBUTING.md).
