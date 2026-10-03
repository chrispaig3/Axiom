# The Axiom Rust FFI

This page shows you how to call a Rust crate from an Axiom program, and
how Rust calls back. It covers binding a crate, the types that cross
the boundary, and the rules each side keeps.

The memory rules behind it are `MM-FFI-1` to `MM-FFI-6` in
[memory-model.md](memory-model.md) §11. This page is the user-facing
contract, so it cites those rules rather than restating them.
The [contract audit](assurance/ffi-contract-audit.md) lists reviewed
routes, caller obligations and the remaining Unsafe vouches.

---

## 1. What it is, and is not

Axiom calls Rust, Rust calls back, and a host can call in. An `extern`
block declares the linker symbols a static archive defines. The emitter
writes a `declare` for each one the module calls, and the call site is
the same `call i64 @sym(i64, ...)` an internal Axiom call compiles to.

Rust reaches Axiom in three ways, and no others:

- the ownership primitives every emitted module exports:
  `axiom_retain`, `axiom_release` and `axiom_alloc`;
- a callback Axiom passed it as an argument, valid for that call (§7);
- every `pub fn` of an Axiom module built with `--emit-staticlib`, as a
  C symbol (§10). There the Rust program is the host and owns `main`.

In the other direction, the destructor a `Handle` carries (§6) is the
one standing call, and Axiom makes it.

Every Axiom value is one 64-bit word (`MM-VAL-1`), so every shim
`#[axiom_export]` generates is `extern "C" fn(i64, ...) -> i64`.
Anything that needs two words back, such as bytes, a `Result` or an
`Option`, goes through a trailing out-cell and a status word. The
decoding half is generated Axiom code, not a compiler feature (§5).

Rust borrows and Axiom owns. A shim borrows its arguments for the
duration of the call and no longer (C1). When Axiom keeps a Rust value,
it holds it through a `Handle`: a counted Axiom block that runs the
Rust destructor when its last share dies (§6). Rust never writes an
Axiom block header. Bytes Rust hands back are copied into an Axiom
`String` and freed on the Rust side (C4).

How freestanding your executable stays depends on the crate you link.
Here is what `nm -u` reports on darwin-aarch64 for the three
executables `scripts/check-ffi.sh` builds:

| program | undefined symbols | forbidden libc names |
|---|---|---|
| no `extern` (`tests/ffi/no-extern`) | **0** | 0 |
| `extern` → `rust/examples/nostd` (`no_std`) | **0** | 0 |
| `extern` → `rust/examples/demo` (`std`) | 188 | 18 |

`rust/examples/demo/axiom-allow.txt` lists the 188, one per line, and
the gate fails on any name outside that file (§14). The 18 are the
names on `scripts/check-freestanding.sh`'s forbidden list that the
`std` executable imports, such as `malloc`, `free`, `memcpy`, `getenv`
and `fork`.

---

## 2. Quickstart

Mark the Rust functions you want with `#[axiom_export]`, and
`axiom-bindgen` writes the Axiom module for them. Here is a small crate:

```toml
# Cargo.toml of the crate you are binding
[package]
name = "axiom-my-crate"
version = "0.1.0"
edition = "2021"
[lib]
crate-type = ["staticlib"]
[dependencies]
axiom-ffi = { path = "/path/to/.axiom/rust/axiom-ffi" }
```

```rust
// src/lib.rs
use axiom_ffi::{axiom_export, axiom_opaque};

#[axiom_export]
pub fn add(a: i64, b: i64) -> i64 { a.wrapping_add(b) }

#[axiom_export]
pub fn shout(text: &str) -> String { text.to_uppercase() }

#[axiom_opaque]
pub struct Counter { n: i64 }

#[axiom_export]
pub fn counter_new(start: i64) -> Counter { Counter { n: start } }

#[axiom_export]
pub fn counter_value(c: &Counter) -> i64 { c.n }
```

Install the binding generator once:

```sh
cargo install --path /path/to/.axiom/rust/axiom-bindgen
```

Then import the generated module and call the functions by their
camelCase names:

```scheme fragment
; p.ax. MyCrate is the module axiom-bindgen writes for your crate.
(import IO)
(import Fmt)
(import MyCrate)

;@axiom:effect(io)
(pub fn (main)
  (let ((c (counterNew 41)))
    { (println (shout "hi")) (println (fmtInt (add 1 (counterValue c)))) 0 }))
```

```sh
axiom build --input p.ax --output p --crate /path/to/mycrate && ./p
```

The program prints:

```text
HI
42
```

`--crate DIR` does the whole job. The driver:

- runs `axiom-bindgen` when `DIR/axiom/MyCrate.ax` is missing or no
  longer matches what `DIR/src` generates;
- runs `cargo build --release` when `libaxiom_my_crate.a` is missing;
- searches `DIR/axiom/` for the generated module, and
  `DIR/target/release` (or the workspace's, one or two levels up) for
  the archive;
- links the archive, because the generated `extern` block names it
  (§12).

Each step it runs prints a line on stderr.

If neither tool is on `PATH`, nothing is generated and nothing is
built. The missing module is then refused as `AX5001` and the missing
archive as `AX4004`. Those two errors are the signal, not a stalled
build.

The module name is the package name in CamelCase. Each `-` or
`_`-separated piece is capitalised and an `axiom-` prefix is dropped,
so `axiom-my-crate` becomes `MyCrate` and `mycrate` becomes `Mycrate`.
If `DIR/axiom/` already holds one `.ax` file, its stem is the name
instead. The archive stem is the package name with `-` written as `_`.

To choose another name, run the tool by hand:
`axiom-bindgen --src DIR/src --lib axiom_my_crate --module MyCrate -o DIR/axiom`.
An Axiom module *is* its file name, and the driver keeps whatever is
there.

You never close `counterNew`'s `Counter` by hand. Rust drops it when
`c` goes out of scope.

For a worked example, see `rust/examples/demo` (every shape, using
`std`) with its generated `axiom/Demo.ax`, and `rust/examples/nostd`
(`no_std`, imports nothing). [rust/README.md](../rust/README.md) is
the crate-side view: what lives in which crate, and how to regenerate
the checked-in bindings.

---

## 3. The `extern` grammar

An `extern` block binds Axiom names to symbols in a Rust archive. The
parser (`parseExternDecl`, `parseExternItems` and `parseExternClauses`
in `self_host/parser.ax`) accepts exactly this shape:

```scheme
(pub extern "axiom_demo"                                  ; the library string
  (add      :: (-> Int Int Int) (symbol "axffi_add"))     ; an item
  (abiProbe :: Int              (symbol "axffi_abi_probe")))  ; nullary: a bare result type
```

- The block head is `extern` followed by a library name in quotes.
  Anything else is `AX2001 expected a library name in quotes`. The
  driver uses the string: it links `-l<lib>` when it finds `lib<lib>.a`
  in a search directory (§12), and names it in an `AX4004`.
- An item is `(name :: type clause*)`, and the type is required. An
  untyped item is `` AX2001 expected `:: type` after extern item `name` ``
  (`tests/diagnostics/700`).
- A nullary item writes a bare result type (`Int`), not `(-> Int)`.
- `(symbol "string")` is the only clause, and it may appear at most
  once. Any other head is
  ``AX2001 expected `symbol` (unknown extern clause `x`; the clauses an extern item takes are: symbol)``
  (`tests/diagnostics/701`). An unquoted symbol is
  `` AX2001 expected a quoted linker symbol after `symbol` ``. Clauses
  such as `effects`, `opaque` and `drop` are refused by this rule, not
  skipped.
- Without the clause, the linker symbol is the item's own name.
  `axiom-bindgen` always writes the clause, and so should you: a static
  link is one flat namespace.
- A type in the signature may only be `Int`, `Float`, `Bool`, `Char`,
  `String` or `Foreign` (§13, `AX3036`). `Handle` is refused here. A
  raw extern answers a `Foreign` word, and only `ffiHandleNew` turns
  one into a `Handle`.
- `pub` makes the items importable like any other declaration. A block
  without `pub` binds within its own file.
- An item defines a value name. A `fn` with the same spelling in the
  same file is `AX3006 duplicate definition`, but two blocks naming one
  library are not duplicates of each other (`tests/diagnostics/702`).
- Calling an item contributes the `IO` effect (C6). `tcAddExtern` seeds
  the item's `FnEnt` with `IO`, and the ordinary fixpoint propagates it
  (`tests/ffi/demo/070-extern-effect-transitive.ax`).

The emitter (`emitExternItems` in `codegen.ax`) writes
`declare i64 @sym(i64, ...) #0` only for a symbol the module calls. A
program that imports a twenty-item binding module and calls two items
declares two. Every declare must be grounded by a linked archive
(§12). The `#0` attribute group stops `opt` from treating a declared
name as a libc function it knows.

---

## 4. The type table

One table, in `rust/axiom-ffi-classify/src/lib.rs`, decides what
crosses. Both the proc macro and `axiom-bindgen` consult it, each
through the `_with` form, which takes the registry that says what a
bare named type is (a record's fields, an opaque handle). So the two
passes over one annotation can't drift. The table is closed: anything
it doesn't list is a compile error, and the message lists what is
accepted.

**Parameters** (`classify_param_with`):

| Rust | Axiom | on the wire | the shim does |
|---|---|---|---|
| `i64` | `Int` | the word | nothing |
| `bool` | `Bool` | 0 / 1 | `w != 0` |
| `f64`, `f32` | `Float` | IEEE-754 bits in the i64 | `f64::from_bits` (then `as f32`) |
| `i32 i16 i8 u32 u16 u8 usize isize` | `Int` | the word | `TryFrom`; out of range **aborts** (§5.1) |
| `u64` | `Int` | the same 64 bits, read unsigned | `as u64`; no check, nothing lost (≥ 2^63 reads negative on the Axiom side) |
| `char` | `Char` | the code point | `char::from_u32`; not a scalar value **aborts** |
| `&str` | `String` | the `Str` header address | zero-copy view of the bytes; UTF-8 checked (§5.1) |
| `&[u8]` | `String` | the `Str` header address | zero-copy view; no validation |
| `&T`, `&mut T` (`T` marked `#[axiom_opaque]`) | `Foreign` | the boxed value's address | null check, then a borrow for the call |
| `T` marked `#[axiom_record]` | `T` (a `data` type) | one word per field | `AxRecord::from_words` (§8) |
| `&[T]`, `T` a word scalar ≠ `u8`; `&[&str]`; `&[Record]`; `&[&[T]]` | `(Vec Int)` / `(Vec String)` / `(Vec Point)` / `(Vec (Vec Int))` | the `Vec` handle | a borrowed view or a range-checked copy for the call (§8) |
| `&mut [i64]`, `&mut [f64]`, `&mut [u64]` | `(Vec Int)` | the `Vec` handle | the live elements, in place (§8) |
| `AxFn1`, `AxFn2`, `AxFn3` | `(-> Int Int)` … | the closure record | `.call` (§7) |

These parameter types are refused, each with its reason in the message:

- `u128` and `i128`: "split it into two `u64`s";
- `String` or `Vec` by value: "borrow it";
- `Option` and `Result`: "may only be returned";
- a by-value opaque `T`: "Axiom holds a handle, so take `&T` or
  `&mut T`, or return it";
- `&mut str`;
- `&mut [T]` for a `T` that isn't 64 bits wide: "take `&[T]` and return
  a `Vec<T>`", because a converted copy couldn't be written back as the
  same words;
- `&i64`, tuples and `()`.

**Returns** (`classify_return_with`):

| Rust | Axiom (wrapper) | raw item | protocol |
|---|---|---|---|
| `i64 bool f64 f32` and the narrow ints | `Int` / `Bool` / `Float` | same | scalar: the value; narrow ints widen losslessly |
| `()` or no `->` | `Int` (always 0) | same | scalar |
| `T` marked `#[axiom_opaque]` | `data T (T Handle)` | `(-> ... Foreign)` | the boxed address, wrapped in a `Handle` (§6) |
| `String`, `Vec<u8>` | `String` | `(-> ... Int Int)` + `Raw` suffix | bytes/out-cell (§5.2) |
| `Result<T, E>` (`E: Display`) | `(Result T' String)` | `Raw` | fallible: status 0 / 1 (§5.3) |
| `Option<T>` | `(Option T')` | `Raw` | fallible: status 0 / 2 (§5.3) |
| `Vec<T>`, `T` a word scalar ≠ `u8`; `Vec<String>`; `Vec<Record>`; `Vec<Vec<T>>` | `(Vec Int)` / `(Vec String)` / `(Vec Point)` / `(Vec (Vec Int))` | `Raw` | words / string list / record words / word lists out-cell (§8) |
| `T` marked `#[axiom_record]` | `T` (a `data` type) | `Raw` | field words in a cell of `ARITY` words (§8) |
| `Result<Option<T>, E>`, `Option<Result<T, E>>` | `(Result (Option T') String)`, `(Option (Result T' String))` | `Raw` | the three statuses, nested (§5.3) |
| `u64`, `char` | `Int`, `Char` | same | scalar: the bits; the code point |

`T'` is the payload's own row: a scalar, `String`, an opaque `data`
type, a `Vec` or a record. These return types are refused:

- `u128` and `i128`;
- `Vec<Vec<String>>` and `Vec<Vec<Record>>`: "one level of word
  scalars";
- a `Vec` of opaque handles;
- a borrow such as `&str`: "a borrow cannot outlive the call";
- nesting past `Result<Option<_>, _>` or `Option<Result<_, _>>`: "three
  states is what the status word has";
- `Option<()>`: "is a `bool`; return one";
- `Box`, `Rc` and `Arc`;
- a bare `Result` or `Option` with no payload written out.

Tested by `rust/axiom-ffi-macros/tests/ui/fail/*.stderr`, which
snapshots each refusal message, and
`rust/axiom-ffi-macros/tests/ui/pass/accepted_shapes.rs`, which
compiles and runs every accepted shape.

The linker symbol is `axffi_<rust_name>` unless
`#[axiom_export(symbol = "...")]` says otherwise. The Axiom name is the
Rust name in camelCase, so `counter_try_new` becomes `counterTryNew`. A
wrapped item's raw binding adds `Raw`. `#[axiom_export]` also takes
`utf8 = "lossy"`. Any other key is refused with
`` unknown `axiom_export` key `k`; the keys are `symbol = "name"` and `utf8 = "lossy"` ``.

---

## 5. The three protocols

Each export returns its result by one of three protocols, chosen by
its return type: scalar, bytes or fallible.

### 5.1 Scalar

```rust
#[axiom_export]
pub fn add(a: i64, b: i64) -> i64 { a.wrapping_add(b) }
```

This generates `#[no_mangle] pub extern "C" fn axffi_add(a0: i64, a1: i64) -> i64`
and binds as `(add :: (-> Int Int Int) (symbol "axffi_add"))`, with no
wrapper. The call is the same instruction sequence as an internal call
(`tests/ffi/demo/010-add.ax`). A `Float` crosses as the bits it is
already stored as (`020-float-bits.ax`, `210-differential-float.ax`).

The shim checks three things at the door. An infallible call has no
channel for an error, and the alternative is a silent wrong answer.

- A narrow integer out of range aborts with
  ``axiom-ffi: `byte_plus`: argument 1 (`b`: u8) is out of range: 256``.
  `tests/ffi/demo/115-abort-status.ax` runs `(bytePlus 256 1)`, which
  prints that on fd 2 and exits 73.
- A `&str` that isn't UTF-8 aborts in an infallible shim, with the text
  ``argument 1 of `parse_int` is not valid UTF-8``. A `Result` shim
  returns `Err` of that text instead. Under
  `#[axiom_export(utf8 = "lossy")]` the shim converts the bytes with
  `from_utf8_lossy`. An `Option` shim aborts, since only `Result` can
  carry the message. Take `&[u8]` when the bytes aren't text
  (`120-bytes-param.ax`).
- A closed handle aborts (§6).

A boundary abort exits with status **73** and prints a message
prefixed `axiom-ffi:` on fd 2.

The status is kept apart from the runtime's own traps. `MM-EXEC-16`
reserves 70 for allocation failure, 71 for an operation performed with
no handler, and 72 for division by zero. All three are raised by code
the Axiom compiler emitted. A boundary abort is raised on the Rust
side, by a precondition the caller violated. With its own status, a
supervisor reading a log can tell *a peer sent a length that doesn't
fit a `u32`* from *you divided by zero*, and those two have no remedy
in common.

### 5.2 Bytes (the out-cell)

```rust
#[axiom_export]
pub fn shout(text: &str) -> String { ... }
```

A `String` needs a pointer and a length back, but every shim returns
one word. So the shim takes a trailing out-cell,
`extern "C" fn axffi_shout(a0: i64, out: i64) -> i64`, writes
`{ptr, len}` into it and returns status 0. The raw item is
`(shoutRaw :: (-> String Int Int) (symbol "axffi_shout"))`, and
`axiom-bindgen` writes the wrapper (`rust/examples/demo/axiom/Demo.ax`):

```scheme
(pub :: shout (-> String String))

(pub fn (shout text)
  (let (
    (__c ffiCellNew)                    ; a 16-byte counted cell, zeroed
    (__st (shoutRaw text __c))          ; the call; status ignored here
    (__p (ffiCellWord __c 0))
    (__n (ffiCellWord __c 1))
    (__v (ffiBytesToStr __p __n))       ; copy into a fresh Axiom String
  )
    {
      (ffiFreeBytes __p __n)            ; give the Rust bytes back
      (ffiCellFree __c)
      __v
    }
  )
)
```

The copy is the central safety rule (C4). Only Axiom's emitter writes
an Axiom block header, because only it knows `MM-LIFE-2d`'s shape word.
Rust memory is reachable from Axiom for the length of one copy.

Every generated local starts with `__`, and a Rust parameter may not,
so a parameter named `cell` or `p` reaches Rust intact
(`080-param-named-cell.ax`).

The helpers live once, in `stdlib/Ffi.ax`, which imports only `Mem`,
`Str` and `Vec`. So two generated modules can be imported together
without colliding:

```scheme
(pub :: ffiCellNew     Int)                 ; a 16-byte out-cell, zeroed, held by one share
(pub :: ffiCellFree    (-> Int Int))        ; releases it
(pub :: ffiCellWord    (-> Int Int Int))    ; (cell i) -> word i
(pub :: ffiBytesToStr  (-> Int Int String)) ; (ptr len) -> a fresh copy; does not free
(pub :: ffiStatusOk    Int)  ; 0
(pub :: ffiStatusErr   Int)  ; 1
(pub :: ffiStatusNone  Int)  ; 2
(pub extern "axiom_ffi"
  (ffiFreeBytes  :: (-> Int Int Int) (symbol "axffi_free_bytes"))
  (ffiAbiVersion :: Int (symbol "axffi_abi_version")))
```

`axiom_ffi` has no archive of its own. Every crate that depends on the
`axiom-ffi` facade defines `axffi_free_bytes` and `axffi_abi_version`.
The driver links a library string only when its archive exists, and a
declare is grounded by whatever archives are linked. So a program that
imports `Ffi` and calls nothing links with no archive at all.

### 5.3 Fallible: `Result` and `Option`

Fallible calls use the same cell, plus the status word. `Result<T, E>`
returns 0 with the payload in the cell, or 1 with the `Display` text of
the error as `{ptr, len}`. `Option<T>` returns 0 with the payload, or 2
with the cell untouched.

A global last-error slot would be sound (`MM-PAR-1`, no threads), but
it would make every call site order-dependent, and a wider return is
impossible. The wrapper turns the status into the ordinary `Result` of
`stdlib/Err.ax`, or the builtin `Option`:

```scheme
(pub :: parseInt (-> String (Result Int String)))

(pub fn (parseInt text)
  (let (
    (__c ffiCellNew)
    (__st (parseIntRaw text __c))
    (__p (ffiCellWord __c 0))
    (__n (ffiCellWord __c 1))
  )
    (if (== __st 0)
      { (ffiCellFree __c) (Ok __p) }
      (let ((__m (ffiBytesToStr __p __n)))
        { (ffiFreeBytes __p __n) (ffiCellFree __c) (Err __m) }))))

(pub :: maybe (-> Int (Option Int)))

(pub fn (maybe n)
  (let ((__c ffiCellNew) (__st (maybeRaw n __c))
        (__p (ffiCellWord __c 0)) (__n (ffiCellWord __c 1)))
    (if (== __st 0)
      { (ffiCellFree __c) (Some __p) }
      { (ffiCellFree __c) None })))
```

This is shown compacted. The generated file is laid out as `axiom fmt`
lays it out, and passes `axiom fmt --check`.

- A `Result<String, _>` copies the payload bytes, as §5.2 does.
- A `Result<Counter, String>` builds the handle on `Ok`, as
  `(Ok (Counter (ffiHandleNew __p counterDropFn)))`, and builds nothing
  on `Err`. So no value is ever boxed and lost (`100-result-opaque.ax`).
- A `Result<(), E>` binds as `(Result Int String)` and answers
  `(Ok 0)`, since `()` has no value in Axiom.

For example, `(parseInt s)` for a two-byte `s` of `FF 31` returns
``Err "argument 1 of `parse_int` is not valid UTF-8"``. `(maybe -1)`
returns `None`, and `(counterTryNew -3)` returns
`Err "counter cannot start below zero (got -3)"`.

---

## 6. The handle protocol

An arbitrary Rust type, such as a `sha2::Sha256` or a
`reqwest::Client`, never has to be describable in Axiom's type system.
You mark it, the shim boxes it, and Axiom holds it through a counted
block that knows how to destroy it.

On the Rust side, put `#[axiom_opaque]` on a `struct` or `enum`. The
type must be monomorphic: a generic type is refused with "a symbol
cannot be generic". The attribute generates an
`impl AxiomOpaque for Counter` and these two functions:

```rust
#[no_mangle] pub unsafe extern "C" fn axffi_counter_drop(h: i64) -> i64   // null-checked Box::from_raw; answers 0
#[no_mangle] pub extern "C" fn axffi_counter_drop_fn() -> i64             // the address of the above
```

The stem is the type name in snake_case, and
`#[axiom_opaque(symbol = "x")]` overrides it. The shim for a function
that returns or borrows `T` calls helpers whose trait bounds only the
attribute satisfies, so a missing `#[axiom_opaque]` is a compile error
rather than a leak. An unmarked return type fails with
`` `Plain` crosses the Axiom boundary but is not marked `#[axiom_opaque]` or `#[axiom_record]` ``,
and a note says to put the attribute on the declaration
(`rust/axiom-ffi-macros/tests/ui/fail/opaque_unmarked.stderr`).
`axiom-bindgen` refuses the same case from its side.

A returning shim boxes the value and returns its address. A borrowing
shim (`&T`, `&mut T`) reads the word and aborts if it is 0, with
``axiom-ffi: `counter_value`: handle is closed`` and exit status 73.
Otherwise it borrows for the call. Generated shims reject repeated
handles when either borrow is mutable, before constructing references.
Callbacks must preserve the exclusivity of every live mutable borrow.
The generated owner is a sealed struct. Its constructor and `handle`
field stay in the binding module, so callers cannot rewrap a pointer
as another Rust type.

On the Axiom side, the builtin type `Handle` is a counted heap block of
the *foreign form*: shape-word bit 0 is set, and there are two payload
words. Word 0 is the destructor's address and word 1 is the Rust
pointer (`stdlib/Ffi.ax`, `MM-FFI-6`). `ffiHandleNew` is the only way
to write one. `memAllocMapped` masks its map to bits 16..62 and can't
set the form bit, and no constructor site does.

```scheme
(pub :: ffiHandleNew   (-> Int Int Handle))  ; (ptr dropFnAddr) -> a fresh Handle, one share
(pub :: ffiHandlePtr   (-> Handle Int))      ; the raw pointer, 0 once closed
(pub :: ffiHandleLive  (-> Handle Bool))     ; ptr != 0
(pub :: ffiHandleClose (-> Handle Int))      ; runs the destructor now, once; pointer zeroed; answers 0
```

`Handle` is a reference in every classification: `fldClass` answers 2
and `evClassOf` answers 1, their reference classes. So a `data` cell
holding one maps it, a `let` of one releases it at scope end, and a
share is retained and released by the same events as a `String`.
`Foreign` stays a word (class 0) that nothing walks. A raw `extern`
item never answers `Handle` (`AX3036`).

When the count reaches zero, `@axiom_release` (the emitted release
runtime in `codegen.ax`, label `foreign:`) reads the two words. If both
are non-zero, it stores 0 into the pointer word, calls the destructor
once as `i64 (i64)`, and files the block by its size class like any
other. A block of the foreign form has no reference map and is never
walked.

The destructor may re-enter `@axiom_release`, for example when a Rust
`Drop` gives back Axiom values the shim retained. Each invocation keeps
its dead list in a local, so the re-entrant call is an ordinary one.

To close a handle early, call `ffiHandleClose`. It runs the destructor
now and zeroes the pointer. The block's own death then calls nothing,
and a second close does nothing. A later borrow through that handle
aborts, as above, instead of dereferencing null. Use it for a value
that must go *now*, such as a file or a lock, and for nothing else.

`axiom-bindgen` generates this shape (`Demo.ax`):

```scheme
(pub struct Counter sealed (handle : Handle))

(pub :: counterNew (-> Int Counter))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(pub fn (counterNew start)
  (let ((__p (cast Int (counterNewRaw start)))
        (__h (ffiHandleNew __p counterDropFn)))
    (Counter __h)))

(pub :: counterValue (-> Counter Int))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(pub fn (counterValue c)
  (let ((__a0 (cast Foreign (ffiHandlePtr c.handle)))
        (__r (counterValueRaw __a0)))
    __r))

(pub :: counterClose (-> Counter Int))       ; explicit early close, optional
(pub fn (counterClose c)
  (ffiHandleClose c.handle))
```

The struct holds the `Handle`, so its death releases the handle,
and the handle's death runs the Rust `Drop`. `Counter` and `Widget`
stay distinct Axiom types because each is its own sealed struct.
`(cast Int x)` and `(cast Foreign x)` reinterpret the bits, and they
are the documented way across the `Foreign`/`Int` line.

`tests/ffi/demo/060-opaque-handle.ax` shows this working: it prints
`opaque handle: agree` and exits 0. A loop builds 200 `Counter`s and lets each go
at the end of its `let`. The crate's `Drop` counter, read through
`countersDropped`, answers 200 with no close call anywhere. After one
explicit `counterClose` on a handle still held, it answers 201. The
close comes after that handle's last read, since a read after it would
abort.

Other fixtures in `tests/ffi/demo/` cover the rest:

- `400-arc-retain.ax` churns 500 strings through `axiom_retain` and
  `axiom_release` from the Rust side.
- `410-foreign-not-walked.ax` and `420-null-foreign.ax` pin that the
  release walk skips a bare `Foreign` field, including 0.
- `430-reentrant-drop.ax` covers re-entry. It frees 100 `Reentrant`
  values through a Rust `Drop` that retains the shared word once more
  and releases it twice while the outer release still holds the value.
  The drop and retain counters both answer 100.

---

## 7. Callbacks

A Rust function can take an Axiom function. On the Rust side the
parameter is `axiom_ffi::AxFn1`, `AxFn2` or `AxFn3`: a `Copy` struct
around the closure word, with `.call(a)`, `.call(a, b)` or
`.call(a, b, c)`. Every argument and the result are plain `i64`s:

```rust
#[axiom_export]
pub fn apply_twice(f: AxFn1, x: i64) -> i64 { f.call(f.call(x)) }

#[axiom_export]
pub fn fold3(f: AxFn2, a: i64, b: i64, c: i64) -> i64 { f.call(f.call(a, b), c) }
```

On the Axiom side the parameter is the arrow with the matching arity:
`(-> Int Int)` for `AxFn1`, `(-> Int Int Int)` for `AxFn2` and
`(-> Int Int Int Int)` for `AxFn3`. That is what `axiom-bindgen`
writes:

```scheme
(applyTwice :: (-> (-> Int Int) Int Int) (symbol "axffi_apply_twice"))
(fold3 :: (-> (-> Int Int Int) Int Int Int Int) (symbol "axffi_fold3"))

(applyTwice (lambda (x) (+ x k)) 1)         ; 21 when k is 10: a capture
(applyTwice triple 2)                       ; 18: a top-level function
(fold3 (lambda (a b) (plus a b)) 1 2 3)     ; 6
```

What crosses is the closure record's address. Word 0 of an Axiom
closure is its code, an `extern "C" fn(env, arg, evidence) -> i64`
that takes the record itself as `env`. The evidence marks an
intermediate closure result as counted; scalar arguments and results
need no reference bits. `AxFn1::call` is one indirect call.

Axiom functions are curried: `(lambda (a b) ...)` is a one-argument
lambda that answers a one-argument lambda. So `AxFn2::call` and
`AxFn3::call` apply one argument per step, exactly as the emitter's own
`emitApplyChain` does. They release each intermediate link they get
back, because those links are owned (`MM-LIFE-2c` event 2).

A bare top-level function is a value at arity 1 only (`AX3013`),
because a partial application has nowhere to hold its arguments. So a
two-argument function reaches `fold3` through
`(lambda (a b) (plus a b))`, as the diagnostic's help says.

The callback is borrowed (C1): it is valid for the call, not after it.
`AxFn1`, `AxFn2` and `AxFn3` carry that lifetime in Rust. Use an
elided lifetime or `'_` in an exported parameter. A callback cannot
escape into a stored value through safe Rust.
When a callback shares a call with borrowed vectors or opaque owners,
the generated wrapper declares a caller precondition. The callback must
keep those borrows valid: no mutation, growth, early close or release.
The caller needs `effect(unsafe)` to accept that obligation. Slices
copied into temporary Rust storage have no such caller precondition.

Tested by `tests/ffi/probe-sealed/030-callback-borrow.axbad`.
A shim that stores one takes a share with `axiom_retain` and pairs it
with `axiom_release`.

As a parameter, the type checker admits any arrow of arity one to three
whose every leaf is a word: `Int`, `Float`, `Bool` or `Char`
(`allIntArrow` in `tcCheckExternTypes`). A `(-> Float Float)` callback
is called with the argument's bits and answers bits, so the Rust side
writes `f64::from_bits(f.call(x.to_bits() as i64) as u64)`. An arrow
with a `String` leaf is refused (`AX3036`), because a `String` argument
or result would carry a share the Rust side has no wrapper to release.

Rust can't build an Axiom closure record (C4). So an arrow in result
position is refused on the Axiom side, and the macro refuses `AxFn` as
a Rust return type or behind a reference
(`rust/axiom-ffi-macros/tests/ui/fail/callback_return.rs`,
`callback_ref_param.rs`).

A callback that panics aborts the process (C7), since a callback has no
way to unwind back through the Rust frame.

Tested by `tests/ffi/demo/130-callbacks.ax`.

---

## 8. `Vec`, slices and records across the boundary

Vectors, slices and records all cross as words, and Rust never writes
an Axiom block (C4).

Generated shims reject overlapping direct or nested vector views when
one argument is mutable. Callbacks must not access a vector while its
words are borrowed mutably, or grow or release any borrowed vector.
These checks require live, correctly typed values; they do not validate
arbitrary addresses.

When calling a raw shim from Rust, borrowed arguments and out-cells
require an `unsafe` block. Keep each value live, preserve exclusive
mutable borrows and provide a disjoint out-cell large enough for the
return shape. Scalar calls and constructors without borrowed inputs
remain safe. Rust buffer frees reject invalid lengths and layouts;
return each allocation pair exactly once.

Tested by `rust/axiom-ffi/tests/contracts.rs` and `scripts/check-ffi.sh`.

| Rust | Axiom | wire |
|---|---|---|
| `-> Vec<T>`, `T` a word scalar (`i64`, the narrow ints other than `u8`, `usize`/`isize`, `bool`, `f64`, `f32`) | `(Vec Int)` | the out-cell holds `{ptr, len}` of words, each element widened to its word (ints extended, `bool` 0/1, floats as `f64` bits); the wrapper copies with `ffiWordsToVec` and returns the buffer with `ffiFreeWords` → `axffi_free_words(ptr, len)` |
| `-> Vec<String>` | `(Vec String)` | the cell holds `{ptr, n}`, `ptr` at `2n` words of `(bytes, len)` pairs; `ffiStrsToVec` copies each string, and `ffiFreeStrList` → `axffi_free_str_list(ptr, n)` frees every string and the pair buffer |
| `&[T]` parameter, `T` a word scalar other than `u8` | `(Vec Int)` | the `Vec` handle itself; Rust reads it as `axiom_abi::AxVec` (word 0 `len`, 1 `cap`, 2 the data pointer) for the call only; `&[i64]` and `&[f64]` as the words are, any other `T` through a range-checked temporary (out of range **aborts**, §5.1) |
| `&[&str]` parameter | `(Vec String)` | the `Vec` handle; each word a `Str`, viewed as `&str` for the call, UTF-8 checked |
| `Point` parameter, `#[axiom_record]` | `Point` (a `data` type) | **one word per field**, in declaration order; the wrapper destructures with `match` |
| `-> Point` | `Point` | the out-cell holds the field words (`ffiCellNewN n`); the wrapper constructs the `data` value |
| `&[Point]` parameter | `(Vec Point)` | the wrapper flattens into a words `Vec` (`ARITY` per element, a private loop bindgen writes); the shim chunks them with `from_words` |
| `-> Vec<Point>` | `(Vec Point)` | the cell holds `{ptr, n}` over `n × ARITY` words; the wrapper rebuilds each element with `ffiWordAt` and frees with `ffiFreeWords` |
| `-> Vec<Vec<T>>`, `T` a word scalar | `(Vec (Vec Int))` | the cell holds `{ptr, n}`, `ptr` at `2n` words of `(words, len)`; `ffiWordListsToVec` copies, and `ffiFreeWordLists` → `axffi_free_word_lists(ptr, n)` frees |
| `&[&[T]]` parameter | `(Vec (Vec Int))` | the outer `Vec` handle; the shim reads each inner `AxVec` for the call |
| `&mut [i64]`, `&mut [f64]`, `&mut [u64]` | `(Vec Int)` | the `Vec`'s live elements, written in place |

`&[u8]` and `Vec<u8>` aren't in this table because §5 covers them: a
byte slice is a `String`'s bytes, and stays one.

A function with a `Vec` parameter always gets a wrapper, even when it
returns a plain scalar. `AX3036` rejects `(Vec a)` in an `extern` item,
because the boundary names six word types and `Vec` isn't one of them.
So the raw item takes the handle as `Int`, and the wrapper is the one
place that casts:

```scheme
(sumWordsRaw :: (-> Int Int) (symbol "axffi_sum_words"))

(pub :: sumWords (-> (Vec Int) Int))

;@axiom:effect(io)
(pub fn (sumWords xs)
  (let ((__r 
    (sumWordsRaw
      (cast Int xs)
    )
  ))
    __r
  )
)
```

Without the wrapper, the raw item would be the name you call. Its
signature would say `Int`, and every call in your code would need a
`cast`, which is the shape `MM-VAL-22` measures as a lost retain. The
generated wrapper keeps that cast in one reviewed place, so you pass
the vector you have.

```rust
#[axiom_export] pub fn range_vec(n: i64) -> Vec<i64> { (0..n).collect() }
#[axiom_export] pub fn sum_words(xs: &[i64]) -> i64 { xs.iter().sum() }
#[axiom_export] pub fn sum_u16(xs: &[u16]) -> i64 { xs.iter().map(|b| *b as i64).sum() }
#[axiom_export] pub fn halves(n: i64) -> Vec<f64> { (0..n).map(|i| i as f64 / 2.0).collect() }
#[axiom_export] pub fn join_words(parts: &[&str]) -> String { parts.join(" ") }

#[axiom_record]
pub struct Point { pub x: i64, pub y: f64 }

#[axiom_export] pub fn point_scale(p: Point, k: i64) -> Point { Point { x: p.x * k, y: p.y * k as f64 } }
```

```scheme
(sumWords (rangeVec 5))                     ; 10: the Vec goes in as itself
(cast Float (vecGet (halves 3) 1))          ; 0.5: a Float element is its bits
(joinWords (vecOf "a" "b"))                 ; "a b"
(match (pointScale (Point 1 2.5) 2)
  ((Point x y) ...))                        ; x = 2, y = 5.0
```

A *record* is a plain struct with named fields, where every field is a
word scalar: `i64`, the narrow ints, `bool`, `f64` or `f32`. A field
that is a `String`, a `char`, an opaque type or another record is
refused, and the message lists the accepted set. `#[axiom_record]`
derives `AxRecord` (`ARITY`, `from_words`, `write_words`), and a narrow
field out of range aborts like a narrow parameter. The shim takes or
writes one word per field. `axiom-bindgen` emits
`(pub data Point (Point Int Float))` beside the opaque types and wraps
each use:

```scheme
(pub fn (pointScale p k)
  (match p
    ((Point __f0 __f1)
      (let (
        (__c (ffiCellNewN 2))
        (__st (pointScaleRaw __f0 __f1 k __c))
        (__w0 (ffiCellWord __c 0))
        (__w1 (cast Float (ffiCellWord __c 1)))
        (__r (Point __w0 __w1))
      )
        { (ffiCellFree __c) __r }))))
```

The macro sees only the function, so how does it know `Point` is a
record? `#[axiom_record]` and `#[axiom_opaque]` each emit a companion
`macro_rules!` named like the type, and `#[axiom_export]` expands a bare
`T` through it. The shape is resolved at the use site, whatever the
order of the items or the module they came from. A type marked with
neither is refused twice: the companion is missing, and an
`AxiomMarked` assertion says ``crosses the Axiom boundary but is not
marked `#[axiom_opaque]` or `#[axiom_record]` ``.

`Result<Point, E>` and `Option<Point>` put the field words after the
status, like any payload. The cell is `max(ARITY, 2)` words, so an
error message fits. Descriptors count one tag per field (§9), so when a
record gains a field the shim's shape changes, and a stale binding
module fails with `AX4005` instead of misreading a register.

`Result<Option<T>, E>` and `Option<Result<T, E>>` use the three
statuses as three states, and the wrapper nests the constructors. The
states are `Ok(Some)`, `Ok(None)` and `Err`, or `Some(Ok)`, `Some(Err)`
and `None`.

Still refused, each with its reason:

- `&[String]` and `Vec<String>` as parameters. Use `&[&str]`.
- `Vec<Vec<String>>` and `Vec<Vec<Record>>`. Nesting allows one level
  of word scalars.
- `&mut [T]` for a `T` narrower than a word.
- A `Vec` of opaque handles.
- Nesting past one `Result` or `Option` inside the other, since there
  are only three states.

Tested by `tests/ffi/demo/140-vec.ax` through `184-nested-fallible.ax`.

---

## 9. The shape check (`AX4005`)

Every `#[axiom_export]` shim `axffi_x` comes with a no-op *descriptor*
symbol whose name spells the shim's shape:

```text
axffi_add__sig_ii_i            add(i64, i64) -> i64
axffi_shout__sig_si_i          shout(&str) -> String        (s = string; the out-cell is a word)
axffi_map3__sig_ciii_i         map3(AxFn1, i64, i64, i64)   (c = callback)
axffi_scale__sig_f_f           scale(f64) -> f64            (f = float)
axffi_abi_version__sig__i      abi_version() -> i64
```

The name has one tag per parameter, then `_`, then the result:

- `i` is a plain word: `Int`, `Bool`, `Char`, a `Foreign` or `Handle`,
  a narrow int, a `Vec` handle, the out-cell, or a unit result.
- `f` is a `Float`.
- `s` is a `String` parameter.
- `c` is a callback.

The driver derives the same string from the Axiom item's declared type
(`sigTagOf` in `driver.ax`). When an archive holds a descriptor for the
symbol and the two disagree, the driver rejects the item before any
tool runs:

```text
error[AX4005]: `axffi_add` is exported by the crate for `(-> Int Int Int)`; the `extern` item declares `(-> Int Int)`
 --> 050-shape-mismatch.axbad:10:4
  = help: the Rust shim and the `extern` item must agree on every parameter and the result
    (docs/ffi.md, the type table); regenerate the binding module with `axiom-bindgen`, or
    fix the hand-written item
```

A symbol with no descriptor in any archive, such as a hand-written raw
shim, is still grounded (`AX4004`) but not shape-checked. The
`#[axiom_opaque]` drop shims carry no descriptor. Without a descriptor,
a two-argument declaration over a three-argument shim builds, links,
and answers whatever sat in the third register. `axiom explain AX4005`
has the long form.

Tested by `tests/ffi/probe-ungrounded/050-shape-mismatch.axbad`, which
`scripts/check-ffi.sh` runs.

---

## 10. The other direction: an Axiom archive for a Rust host

`--emit-staticlib` builds an Axiom module as a static archive with no
`main` of its own, so a program written in another language can link
it:

```bash
axiom build --input hostlib.ax --output libaxiom_hostlib.a --emit-staticlib
```

The file doesn't need to define `main`. The codegen leaves out the
`@main` wrapper (`cgStaticlib`), and the driver assembles and archives
with `ar rcs`. Every `pub fn` of the entry module becomes a C symbol
under its own name. The stdlib code it pulls in is there too, under the
`Module$name` spelling, so a host can build Axiom strings with the
archive's own allocator:

```scheme
; hostlib.ax
(import Str)
(pub :: addTwo (-> Int Int Int))
(pub fn (addTwo a b) (+ a b))
(pub :: shout (-> String String))
(pub fn (shout s) ...)                      ; ASCII upper-case, a fresh String
```

A host can write the `extern "C"` block by hand, since the ABI is one
`i64` per word. Or the build can write it for you:

```bash
axiom build --input hostlib.ax --output libaxiom_hostlib.a \
            --emit-staticlib --emit-rust-binding hostlib.rs
```

`--emit-rust-binding PATH` writes the Rust view of the file's `pub`
surface, from the same declarations the IR came from
(`self_host/rustbind.ax`). It holds one `extern "C"` declaration per
function in a `raw` module, and one wrapper per function in Rust's own
types. The wrappers are safe, except where a raw `AxWord` crosses:

```rust
mod raw {
    unsafe extern "C" {
        pub fn addTwo(a0: i64, a1: i64) -> i64;
        pub fn shout(a0: i64) -> i64;
    }
}

/// `(pub :: addTwo (-> Int Int Int))`
pub fn add_two(rt: AxRuntime, a: i64, b: i64) -> i64 {
    // SAFETY: the archive defines the symbol with exactly this shape (one word each way).
    let __r = unsafe { raw::addTwo(a, b) };
    __r
}

/// `(pub :: shout (-> String String))`
pub fn shout(rt: AxRuntime, s: &str) -> AxString {
    let __a0 = AxString::from_str(rt, s);
    // SAFETY: the archive defines the symbol with exactly this shape (one word each way).
    let __r = unsafe { raw::shout(__a0.as_word()) };
    // SAFETY: a String a function answers is an owned share (MM-LIFE-2c event 2).
    unsafe { AxString::from_owned(__r) }
}
```

A host uses the binding as a module:

```rust
mod hostlib;
use axiom_ffi::host::AxRuntime;
fn main() {
    let rt = AxRuntime::claim().expect("this thread is the first to ask");
    println!("{}", hostlib::add_two(rt, 40, 2));                     // 42
    println!("{}", hostlib::shout(rt, "hello").as_str().unwrap());   // HELLO
}
```

**Every call takes an `AxRuntime`.** That token is the thread rule
(§16) made into a type. The archive's allocator keeps its state in
plain globals, and `axiom_retain`/`axiom_release` are unsynchronised,
so two Rust threads that each allocate a string race, even with nothing
shared between them. `AxRuntime::claim()` answers `Some` on the first
thread to ask, every time it asks, and `None` on every other thread for
the life of the process.

The token is neither `Send` nor `Sync`, and its field is private, so
it can't be forged or moved to another thread. Nothing reaches the
runtime without it. `AxString`, `AxVecBuf` and every value holding one
are `!Send` as well, so whatever the owning thread built is dropped
there.

| Axiom | Rust parameter | Rust result | how |
|---|---|---|---|
| `Int` | `i64` | `i64` | the word |
| `Float` | `f64` | `f64` | `to_bits` / `from_bits` |
| `Bool` | `bool` | `bool` | `as i64` / `!= 0` |
| `Char` | `char` | `char` | the code point; `from_u32(..).unwrap_or('\u{FFFD}')` |
| `String` | `&str` | `AxString` | `AxString::from_str(rt, ..)` (the archive's `Str$strAlloc`) for the call; the result adopted with `from_owned` |
| `(Vec Int)` | `&AxVecBuf` | `AxVecBuf` | borrowed for the call; the result adopted |
| `Handle`, `Foreign`, any other `Vec` | `AxWord` | `AxWord` | the bare word; a wrapper that takes one is `unsafe` |
| `()` result | — | `()` | the word dropped |

A raw word makes the call `unsafe`. An `AxWord` is any `i64` the caller
writes, and Axiom dereferences a `Handle`, a `Foreign` and every
element of a `(Vec String)`. So a wrapper that hands one to Axiom, as
an argument or as a field of a value passed by reference, is a
`pub unsafe fn` whose `# Safety` section says what the caller promises.
A wrapper that only receives one stays safe: an owned word that nobody
releases only leaks.

Names are snake-cased (`addTwo` becomes `add_two`), and a Rust keyword
gets a trailing underscore.

### Values with structure

A `data` or `struct` of the file, `Option`, `Result`, and any
instantiation a `pub` signature mentions (`(Option Pair)`, or
`(List Int)` of the file's own `List`) cross as values. Only the
emitter knows a block's layout, so the same build synthesises accessor
shims into the module before it is checked and compiled (`rbAppendShims` in
`self_host/rustbind.ax`). They are ordinary `pub fn`s, type-checked
like the file's own:

```text
axh_<T>_tag v             the constructor's index, in declaration order
axh_<T>_<Ctor> f0 f1 ..   a fresh value (an owned share)
axh_<T>_<Ctor>_<i> v      field i (a reference field: an owned share)
axh_vec_new / axh_vec_push / axh_vec_len / axh_vec_get
```

For each type, the binding writes a Rust `struct` if it has one
constructor (with the declared field names, or `f0..`) and an `enum`
with tuple variants otherwise. Each gets `from_axiom` and `to_axiom`:

- `from_axiom(rt, word)` is `unsafe`, because it consumes a share of
  whatever the word points at.
- `to_axiom(rt)` is `unsafe` too when a field is a raw word.

The binding maps `(Option T)` to `Option<T>` and `(Result T E)` to
`Result<T, E>`, and boxes a field that reaches its own type
(`Cons(i64, Box<List_Int>)`). It converts at every boundary:

```scheme
(pub data Shape (Circle Float) (Rect Int Int) (Empty))
(pub struct Named (name : String) (score : Int))
(pub :: shapeGrow (-> Shape Int Shape))
(pub :: safeDiv (-> Int Int (Result Int String)))
```

```rust
pub enum Shape { Circle(f64), Rect(i64, i64), Empty }
pub struct Named { pub name: AxString, pub score: i64 }
pub fn shape_grow(rt: AxRuntime, s: &Shape, k: i64) -> Shape
pub fn safe_div(rt: AxRuntime, a: i64, b: i64) -> Result<i64, AxString>

let grown = hostlib::shape_grow(rt, &Shape::Rect(2, 3), 2); // Shape::Rect(4, 6)
let err = hostlib::safe_div(rt, 1, 0);                      // Err("division by zero")
```

An Axiom `Vec` carries its element type on the Axiom side and nothing
on the Rust side, so the binding types only `(Vec Int)`. A `(Vec Int)`
parameter is `&AxVecBuf`, and a result is an owned `AxVecBuf`
(`from_words(rt, &[i64])`, `words`, `len`; released on drop). That
works because its elements are words, and any `i64` is a valid one.
Every other `Vec` stays a raw word, for the reason in the table above.

The binding follows the emitter's ownership rule, read from its IR.
An argument is borrowed, and a callee that keeps one, such as a
constructor, retains it. A result is an owned share (`MM-LIFE-2c` event 2).
So `to_axiom` answers an owned word that the wrapper releases after the
call, `from_axiom` consumes the word it is given, and every accessor's
answer is adopted or released.

`rust/examples/host` round-trips each of these shapes ten thousand
times through the allocator to show the shares balance. That includes
raw words: `someStrs` goes out, `countStrs` and `taggedLen` come back
in, and the host releases the share. It also checks that a second
thread's `AxRuntime::claim()` is refused.

The generated file makes eight misuses fail to compile, each with its
own error code:

- `from_axiom` without `unsafe`;
- a raw-word wrapper called without `unsafe`;
- `to_axiom` without `unsafe` on a type with a raw field;
- an integer where a `(Vec Int)` is taken;
- `AxVecBuf: Send`;
- `AxRuntime: Send`;
- allocating on another thread;
- forging an `AxRuntime`.

The same eight operations, written correctly, compile. Tested by
`scripts/check-ffi.sh`.

A `pub fn` isn't bound when its signature names a type variable, a
tuple, an arrow or a `[T]` list type, when a `data` it uses has fields
that reach one, or when it has no `(pub :: name Type)` signature. The
binding names each one in a comment at the end of the file:

```rust
// Not bound - call these through the archive by hand, or change the type:
// `identity`: `(-> a a)` names `a`, which the binding does not carry
```

The build runs `rustfmt` on the file when one is on `PATH`, as it runs
`cargo`. Without it, the unformatted text compiles just the same.

### Ownership and the runtime

Adopting results rests on `MM-LIFE-2c` event 2: a function that answers
a counted reference answers a share of its own. So the host owns what
it gets, even when the function answered its argument. `hostlib.ax`'s
`(pub fn (same s) s)` compiles to an `@axiom_retain` before its `ret`,
and `rust/examples/host` calls it ten thousand times against the free
list to show that the two releases are two shares.

The runtime needs no init call, because the allocator initialises on
first use. `IO` functions work, since the archive contains the syscall
layer. A panic in Axiom (an `assert`, an out-of-range index) exits the
process as it would from `main`. Effects aren't checked across the
boundary: the host is outside the effect system and calls what it
likes.

`rust/examples/host` is the worked host. `src/hostlib.rs` is the
generated binding, checked in, and `build.rs` links
`$AXIOM_HOST_ARCHIVE_DIR/libaxiom_hostlib.a`. `scripts/check-ffi.sh`
builds both from `tests/ffi/host/hostlib.ax` and checks that the
checked-in binding matches a fresh one and is `rustfmt`-clean (when
`rustfmt` is present). It then runs the host and checks that it
reports agreement (§14).

There is no `export` block. Every `pub fn` is exported, and in fact so
is every other function of the entry file, under its own name.
The binding declares only the `pub` ones.

---

## 11. The contract

Eight rules govern the boundary. The code cites them by name:
`scanExternSigs` in `codegen.ax` cites C1, and
`tests/ffi/demo/040-owned-bytes.ax` cites C2.

- **C1 — A shim borrows; retain to keep.** Every argument is valid for
  the call and no longer. ARC may release the block as soon as the shim
  returns, and an arena reset may reclaim it wholesale. A shim that
  wants an Axiom value after the call takes its own share with
  `axiom_retain`, and pairs it 1:1 with `axiom_release`. Both have
  external linkage in every emitted module. The emitter gives an extern
  item empty `STASH` and `RET` flow masks (`scanExternSigs`), so it parks
  nothing and answers nothing of what it was handed. The demo's
  hand-written `axffi_str_keep`, `axffi_str_recall` and `axffi_str_drop`
  are the worked example (`400-arc-retain.ax`). A literal's count word
  is −1, the statics sentinel, so retaining one is free and releasing
  one does nothing.
- **C2 — One word each way; every shim returns `i64`.** One word goes in
  per argument and one word comes out, `extern "C"`, with no exceptions.
  A `void` shim would make the call site read a register the callee
  never set. `()` crosses as 0. Anything that needs two words back uses
  the out-cell.
- **C3 — Status words are 0, 1, 2.** `AX_OK = 0`, `AX_ERR = 1` (message
  `{ptr, len}` in the cell) and `AX_NONE = 2` (cell untouched). There is
  no panic status (C7). The out-cell is two words the caller owns. The
  shim writes it and never keeps its address.
- **C4 — Only Axiom writes block headers.** Axiom copies bytes from Rust
  with `ffiBytesToStr` and returns them with `ffiFreeBytes`. Rust never
  constructs a `Str` header or any other Axiom block, because only the
  emitter knows the shape word (`MM-LIFE-2d`).
- **C5 — Destructors are `i64 (i64)` and null-safe.** The function a
  `Handle` carries takes the pointer word, frees it if it's non-zero,
  and answers 0. It is called at most once per handle: the runtime
  zeroes the word before the call, and `ffiHandleClose` zeroes it too.
  `#[axiom_opaque]` generates exactly this, and a hand-written one must
  match it.
- **C6 — An extern call is `IO` and `Unsafe`.** Reaching Rust is an
  effect, like a syscall. Its implementation is outside the safety
  checker, so the calling declaration must say `effect(unsafe)`.
  Both effects are seeded at registration. `Unsafe` propagates until
  a reviewed wrapper contains it with `effect(unsafe)`.
  There is no separate `FFI` effect, and `;@axiom:effect(ffi)` isn't a
  claim the checker knows.
- **C7 — No unwinding; a panic aborts.** Axiom's emitter never writes an
  `invoke` or a landing pad, and `extern "C"` aborts on unwind (Rust
  1.81+). The workspace and the examples build with `panic = "abort"`.
  A `no_std` crate's panic handler writes the message to fd 2 and exits
  73. That is the same status as every other boundary abort (§5.1), and
  it isn't one of the statuses `MM-EXEC-16` reserves. A panic that
  reaches the boundary ends the process with a message. It never
  returns a status.
- **C8 — The wire has a version.** `axffi_abi_version` answers **3**.
  It goes up on any change to a wire representation: the word, the
  `Str` layout, the cell or the statuses. `ffiAbiVersion` reads it from
  Axiom, and `tests/ffi/demo/310-abi-version.ax` pins it. Version 1 had
  statuses 0 and 1. Version 2 added status 2, the drop function and the
  narrow-int checks. Version 3 adds the closure's ownership evidence
  argument; rebuild Rust callback libraries for this ABI.

---

## 12. Linking and the driver

`effectiveLinkArgs` in `self_host/driver.ax` builds the link line in
this order. Each directory appears once, and only if it exists.

1. Explicit `--link-search DIR` (`-L`) and `--link-lib NAME` (`-l`), as
   given.
2. Every directory in `$AXIOM_LINK_SEARCH` (colon-separated).
3. `<entry>/../target/release` and `<entry>/../../target/release` for
   each `$AXIOM_PATH` entry, because a crate's `axiom/` binding
   directory sits beside its `target/`.
4. `DIR/target/release`, `DIR/../target/release` and
   `DIR/../../target/release` for each `--crate DIR`. A crate inside a
   workspace builds into the workspace's `target`, so
   `rust/examples/demo` builds into `rust/target`.
5. The same three for each `crate DIR` in the project's `axiom.pkg`, in
   file order. This lets a project declare its native dependency
   instead of passing it on every command line
   ([reference.md, Packages](reference.md#packages)).
6. Then `-l<lib>` for every `extern` block's library string, when a
   directory above holds `lib<lib>.a` and no explicit `-l` already
   names it.

The library string travels from the emitter to the driver as a comment
line in the IR (`; axiom-extern-lib axiom_demo`), beside the declares.

`--crate DIR` (repeatable; `build`, `run`, `check`) also puts
`DIR/axiom/` on the module search path, so `(import Demo)` finds the
generated module. An `axiom.pkg` line `crate DIR` puts the same
directory on the same path, one slot higher: above `$AXIOM_PATH`, where
the manifest's `depend` lines already sit. `--link-lib` and
`--link-search` still work as overrides.

### Building the crate

On the command line, `--crate` also builds the crate, and only there.
`prepareCrates` runs before the entry is read. For each `--crate DIR`:

- When `DIR/axiom/*.ax` is missing or older than the newest file under
  `DIR/src`, and `axiom-bindgen` is on `PATH`, the driver regenerates
  the module (`--src DIR/src --lib <stem> --module <Name> -o
  DIR/axiom`) and says so on stderr.
- When no `lib<stem>.a` exists in any of the crate's `target/release`
  directories, and `cargo` is on `PATH`, it runs
  `cargo build --release --manifest-path DIR/Cargo.toml`.

The stem and the name come from the `[package] name` in
`DIR/Cargo.toml`. The stem turns `-` into `_`. The module name is
CamelCase with any `axiom-` prefix dropped, or the name of the single
`.ax` already in `DIR/axiom/`. A missing tool isn't an error: the
driver then expects the artefacts to exist, and reports `AX4004` or an
unresolved import if they don't. `cargo install --path
rust/axiom-bindgen` puts `axiom-bindgen` on `PATH`.

The checks are file-time comparisons and one
`axiom-bindgen --check --quiet`, whose exit status is the answer. On
the demo crate the step takes 4 s from a clean `target/`, and 0.7 s
when nothing has changed.

A manifest `crate` line does none of that. It adds the two search paths
and nothing else: no cargo, no `axiom-bindgen`, and no writes anywhere
under `DIR`. A command line is a person asking, but `axiom.pkg` is a
checked-in file that arrives with a clone. If it could start another
project's build system, "the compiler executes no code from a source
file" would be false for the file most worth trusting.

So build the crate once, with `cargo build --release` or one
`axiom build --crate DIR`, and the manifest carries it from then on.
Without the archive, the build fails with `AX4004`, whose help names
`--link-lib`, `--link-search` and the `target/release` it looked in.
`scripts/check-packages.sh` tests both halves: after a manifest build
`DIR/target` must not exist, and passing the same directory as
`--crate` must create it.

### Grounding

Before a byte is written or a tool started, `groundExternsSpanned`
reads every archive on the link line. It checks that each `declare`d
name appears whole in an archive's symbol table: `\0_name\0` (Mach-O)
or `\0name\0` (ELF). A prefix doesn't count, so `axffi_ad` doesn't
ground against `axffi_add`. A name that fails is `AX4004` at the item's
span, in one of three forms:

```text
error[AX4004]: no archive is linked, and `axffi_add` needs one
 --> 040-nothing-linked.axbad:7:4
  = help: pass `--link-lib NAME --link-search DIR` where DIR holds `libNAME.a`, or set
    `AXIOM_LINK_SEARCH` to the directory; the `extern` block names library "axiom_demo",
    and `axiom build` links `lib<name>.a` by itself when a search directory holds it
    (an `AXIOM_PATH` entry's `../target/release` is searched too)

error[AX4004]: no linked archive defines `axffi_ad`
 --> 030-prefix-of-symbol.axbad:9:4
  = help: searched: rust/examples/demo/../../target/release/libaxiom_demo.a; did you mean `axffi_add`?

error[AX4004]: no linked archive defines `axffi_no_such_thing`
 --> 020-missing-symbol.axbad:11:4
  = help: searched: rust/examples/demo/../../target/release/libaxiom_demo.a; check the
    `(symbol "...")` clause against the crate's `#[axiom_export]` names
```

The did-you-mean offers the `axffi_*` name in the archives that shares
the longest prefix with the missing one, when that prefix reaches past
`axffi_`. The span is the item's, in whichever module declared it,
which is usually an imported binding module. `groundDeclares` remains
as the span-less fallback (``no archive on the link line defines `x` ``)
for IR built by a path without declarations.

The check works in one direction. It proves nothing on the line can
define the name. It doesn't claim that a name it finds is a definition
rather than a string constant.

---

## 13. Diagnostics

The mistakes the compiler catches at the boundary, with the message
you see:

| code | when | message |
|---|---|---|
| `AX2001` | an extern item without `:: type` | ``expected `:: type` after extern item `add` (an extern item declares its type: `(name :: (-> Int Int) (symbol "c_name"))`), found `(` `` |
| `AX2001` | a clause head other than `symbol` | ``expected `symbol` (unknown extern clause `symbo`; the clauses an extern item takes are: symbol), found `symbo` `` |
| `AX2001` | an unquoted symbol | ``expected a quoted linker symbol after `symbol`, found `axffi_add` `` |
| `AX2001` | a block without a quoted library name | `expected a library name in quotes` |
| `AX3036` | a type the boundary cannot carry | ``an `extern` item cannot carry the type variable `a` across the boundary``. Other shapes are named as `a tuple`, `a list`, ``a function-typed argument (a callback is an arrow over words only - `Int`, `Float`, `Bool`, `Char` - such as `(-> Int Float)`)``, ``the type `Option` ``, ``the type `Handle` `` and `` `Int` applied to type arguments``. The word-leaf arrows of §7 pass. |
| `AX3002` | a type name nothing declares | ``undefined type `Slice` `` with the help "use `Foreign` for an opaque handle" |
| `AX3006` | a `fn` spelled like an item | ``duplicate definition `add` `` pointing at both |
| `AX4004` | a declared symbol no linked archive defines | three messages, shown in §12 |
| `AX4005` | a declared type that disagrees with the shim's descriptor | see §9 |
| `AX2004` | `foreign` | a removed construct, permanently; the migration advice names `extern` |

The help for `AX3036` reads:

> an `extern` signature names only `Int`, `Float`, `Bool`, `Char`,
> `String` and `Foreign` (one machine word each way); a Rust value of any other shape crosses as a `Foreign`
> handle, or through the wrapper `axiom-bindgen` generates (a `String`
> result, a `Result`, an `Option`, an opaque type)

The check is `tcCheckExternTypes` in `self_host/typecheck.ax`. It walks
the signature's own arrow spine. An arrow in parameter position passes
only as a callback over word leaves (`allIntArrow`), and an arrow
anywhere else is refused. For the long form, run `axiom explain AX3036`,
`AX4004` or `AX4005`.

Tested by `tests/diagnostics/700`–`702`.

On the Rust side, every refusal is a compile error at the offending
type or key, and the message lists the accepted set (§4). The runtime
refusals are a value out of range, bytes that aren't UTF-8 and a closed
handle. Each aborts with `axiom-ffi: ...` on fd 2 and exit status 73
(§5.1, §6).

`axiom-bindgen` refuses:

- an unmarked opaque type;
- a camelCase collision: ``Axiom name `fooBar` is generated twice: for
  ... and for ...; rename one (camelCase folds `foo_bar` and `fooBar`
  together, and wrapped items also claim `<name>Raw`)``;
- two opaque types with the same name;
- a parameter whose name starts with `__`;
- `self`.

---

## 14. The gate

`scripts/check-ffi.sh` is the CI check that `MM-FFI-5` requires. It
lists the external symbols a program may import, rather than forbidding
them all. It needs `cargo`, though the compiler itself never does. A
checkout without `cargo` skips this check rather than failing it.

It proves these, in order:

1. **Tier 1.** Every program in `tests/ffi/no-extern/` builds and
   imports nothing (`nm -u` is empty). At least three cases must reach
   this check.
2. **Tiers 2 and 3.** Each `rust/examples/<crate>/` with an
   `axiom-allow.txt` manifest is built. `nostd` builds by its own
   `Cargo.toml`, since it is its own workspace. Then each
   `tests/ffi/<crate>/*.ax` is built with `--crate` and run, because a
   check that only builds can't tell a silent wrong answer from a pass.
   Its exit status must match the fixture's `; expect N` trailer. If the
   fixture's code (not its comments) mentions `agree`, the program must
   print an `agree` line. Any imported symbol the manifest doesn't
   permit fails the check. A manifest may never permit `printf`,
   `puts`, `fopen`, `fwrite`, `fread`, `system`, `popen`, `execv`,
   `execve` or `posix_spawn`.
3. **Regeneration.** `axiom-bindgen` regenerates every checked-in
   `rust/examples/*/axiom/*.ax`, and each must be byte-identical.
4. **Nine negative probes.** A subset check also passes on an empty
   corpus, an `nm` that answers nothing, or a manifest that permits
   everything. So the gate shows that:
   - the symbol reader sees an undefined symbol in a C object;
   - the manifest comparison flags an unpermitted name;
   - it leaves a permitted name alone;
   - `foreign` is still `AX2004`;
   - the allowlist fails on `rust/examples/leaky`, which calls
     `std::env::var` against a manifest that permits nothing;
   - an ungrounded symbol is `AX4004`, and the output contains neither
     `opt:` nor `AX4003` (a refusal from the toolchain would be the old
     `foreign` bug under a new name);
   - a prefix of a real symbol is `AX4004`, naming the real one;
   - an `extern` with no archive linked gets its own message, at the
     item;
   - a declaration of the wrong shape is `AX4005` (§9), and doesn't
     build.
5. **The host direction** (§10). `tests/ffi/host/hostlib.ax` is
   archived with `--emit-staticlib --emit-rust-binding`, and the
   archive must define no `main`. When `rustfmt` is present, the fresh
   binding must be byte-identical to the checked-in
   `rust/examples/host/src/hostlib.rs` and `rustfmt`-clean. Then `rust/examples/host` is
   built against the archive and run, and its output must end in
   `agree`.

The Axiom fixtures are:

- `tests/ffi/demo/`, one program per shape that crosses:

  | fixtures | what they cover |
  |---|---|
  | `010`–`070` | add, float bits, string borrow, owned bytes, fallible, opaque handle, transitive effect |
  | `080`–`184` | a parameter named `cell`, `Option`, `Result` of an opaque type, narrow ints, abort status, bytes parameter, callbacks, `Vec`, records, `&[&str]` parameters, `Vec` of scalars, `Char`, `Vec` of records, nested `Vec`, `&mut` slices, nested fallible |
  | `200`–`220` | differential int, float and string: Axiom and Rust compute the same answer |
  | `300`, `310` | arity sweep (arity 0 is the one distinct emitter path), ABI version |
  | `400`–`430` | ARC retain, a `Foreign` not walked, a null `Foreign`, a re-entrant drop |

- `tests/ffi/nostd/010-fnv1a.ax`, for `no_std` mode (§15);
- `tests/ffi/probe-ungrounded/*.axbad`, for grounding and the shape
  check.

CI runs the Rust side's own tests beside this gate as
`cargo test --workspace --exclude axiom-host`. The host example is
left out because it links an archive this gate builds. They cover:

- the classifier's unit tests;
- the `trybuild` suite: one pass file that runs every accepted shape,
  and 20 fail snapshots;
- `axiom-bindgen`'s snapshot tests. `tests/fixtures/nested` is the
  snapshot of every wrapper kind, and `collision`, `unmarked`,
  `unrecorded`, `unrecorded_vec` and `vec_opaque` are the five
  refusals. They also check demo and `nostd` freshness, CLI behaviour,
  and `axiom fmt --check` on the output when a compiler is reachable.

`scripts/check-freestanding.sh` still runs unchanged, so a program
with no `extern` must still pass its stricter check.

---

## 15. `no_std` mode

Use this mode when your crate can live in `core` and `alloc`. In its
`Cargo.toml`:

```toml
[dependencies]
axiom-ffi = { path = "...", default-features = false, features = ["nostd-runtime"] }
[profile.release]
panic = "abort"
```

Then put `#![no_std]` and `extern crate alloc;` in the crate.
`rust/examples/nostd/src/lib.rs` is a complete example in under fifty
lines.

The `nostd-runtime` feature (`rust/axiom-ffi/src/nostd_runtime.rs`)
supplies what such a crate would otherwise write by hand:

- a `GlobalAlloc` over `axiom_alloc`;
- the panic handler, which writes the message to fd 2 and exits 73;
- `rust_eh_personality` and `_Unwind_Resume`. The precompiled sysroot
  `alloc` rlib references them even under `panic = "abort"`, because
  the profile governs your crates, not the sysroot's;
- the six memory intrinsics LLVM assumes exist: `memcpy`, `memmove`,
  `memset`, `memcmp`, `bzero` and `strlen`;
- raw `write` and `exit` syscalls for the four Darwin and Linux
  targets, numbered as `codegen.ax`'s own trap tables number them.

There is no FFI leg for FreeBSD. On the Windows targets there is no
syscall to number, since their runtime calls kernel32. Combining the feature with
`std` is a `compile_error!`.

Rust's allocations then land inside Axiom's arena. The high-water mark
counts them, and a reset reclaims them along with everything else.

**`dealloc` is a no-op in this mode**, the one constraint to know
about. `ffiFreeBytes` frees nothing, so a long-lived process that
churns Rust allocations should size its resets to match.

The linked executable imports nothing, the same answer a program with
no `extern` gives.

The two modes can't share a cargo workspace. Feature unification would
enable `axiom-ffi/std` for the `no_std` member, and its
`#[panic_handler]` would collide with std's `panic_impl`. That is why
`rust/examples/nostd` is its own workspace, and the gate builds it by
`--manifest-path`.

---

## 16. Not supported

Each limit below names the fact that stands in the way.

- **A `String` leaf in a callback, and an arrow as a result.** A
  callback crosses as the closure record, called through its code
  word with words in and a word out (§7). A `String` argument or
  result would carry a share the Rust side has no wrapper to release.
  Rust also can't *build* an Axiom closure record, because only the
  emitter writes block headers (C4).
- **`u128` and `i128`.** Each is two words. The message says to split
  it into two `u64`s.
- **`&mut [T]` for a `T` narrower than a word.** A converted copy
  couldn't be written back as the same words. Take `&[T]` and return a
  `Vec<T>` instead.
- **`Vec<Vec<String>>` and `Vec<Vec<Record>>`.** Only one level of
  word scalars crosses. Flatten the data, or hold it in an
  `#[axiom_opaque]` type.
- **`Box`, `Rc` or `Arc` across the boundary.** An `#[axiom_opaque]`
  type already *is* the box, with a destructor the runtime runs (§6).
- **A `pub fn` the Rust binding names in its trailing comment** (§10):
  one over a type variable, a tuple, an arrow, or a `[T]` list type.
  The archive exports it all the same, so call it by hand.
- **Panics unwinding into Axiom.** A panic aborts the process (C7), and
  no status reports one.
- **32-bit targets.** A word is 64 bits, and `usize` and `isize` are
  range-checked against it. The only targets are the four Axiom emits
  for: darwin and linux, each on aarch64 and x86_64.
- **A distinct `FFI` effect, a per-item `pub`, a second extern clause,
  or any manifest or lockfile.** The library string and
  `(symbol "...")` are the whole surface.
- **Threads from Rust.** A Rust crate that spawns a thread and touches
  an Axiom value from it is outside the model.

  Axiom does have threads: `parallel` has a `--threads` lowering that
  calls `pthread_create` (`emitParThread` in `self_host/codegen.ax`).
  The limit comes from the runtime. Its `axiom_retain` and
  `axiom_release` are a plain load, add and store, not an `atomicrmw`,
  so two threads touching one block's count lose increments.

  Axiom's own threads avoid that. Each gets its own arena, because the
  runtime's globals become `thread_local(localexec)`, and only a machine
  word crosses a join. A Rust thread has neither protection: it shares
  the address space, holds whatever handle you passed it, and nothing
  makes its retain atomic.

  So the rule for a binding is: touch an Axiom value only from the
  thread that called into Rust, and only for the duration of that call.
  That is what "the lifetime is the call" already says about every
  borrowed view here, applied to threads.

  In the host direction (§10), the generated binding enforces this.
  Every generated call and allocating constructor takes an `AxRuntime`,
  which one thread per process can claim and none can send. Otherwise
  two Rust threads could each allocate an `AxString` and race on the
  allocator's globals, with no value crossing between them. When Axiom
  calls into Rust, the rule rests on you.

---

## 17. History

The FFI's early design drafts describe much that was never built.
Read them with `git show 3a83f19:docs/ffi-design/00-drafts-2026-08.md`.
This page keeps what survived: the measured tiers, the three facts
that shaped the design, and the out-cell protocol. These never
shipped:

- the drafts' `(pub export axiom ...)` form of the Rust-to-Axiom
  direction (§10 describes the one that shipped);
- `ffi.manifest.json`, `ffi.lock`, `--ffi` and `--staticlib`;
- `__axiom_abi_guard` and `axiom_rt_init`;
- a distinct `FFI` effect;
- `(opaque T (drop f))`, with AX3037–AX3046;
- `Slice` and `Outcome` as types.

The fixtures record what shipped:

- `tests/diagnostics/700`–`702` for the extern discipline;
- `tests/ffi/demo/080`–`184` for every shape that crosses;
- `tests/ffi/probe-ungrounded/030`–`050` for grounding and the shape
  check;
- `tests/ffi/host/` with `rust/examples/host` for the host direction.
