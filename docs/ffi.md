# The Axiom Rust FFI

What the boundary between an Axiom program and a Rust crate is, as it
ships. Every claim here names the source or the fixture that shows it,
and everything it describes was built, run and measured on 2026-08-22
(darwin-aarch64, the installed compiler, `rust/` at the same tree).
The design record this replaces — six drafts describing an FFI that was
largely never built — is in git rather than in the tree (§17).

The normative memory rules are `MM-FFI-1` to `MM-FFI-6` in
[memory-model.md](memory-model.md) §11; this document is the user-facing
contract and cites them rather than restating them.

---

## 1. What it is, and is not

**Axiom calls Rust; Rust calls back, and a host calls in.** An
`extern` block declares linker symbols a static archive defines, the
emitter writes a `declare` for each one the module calls, and the call
site is the same `call i64 @sym(i64, ...)` an internal Axiom call
compiles to. Rust reaches Axiom in three ways and no other: the
ownership primitives every emitted module exports (`axiom_retain`,
`axiom_release`, `axiom_alloc`); a callback Axiom handed it as an
argument (§7), valid for that call; and, when the Axiom module was
built with `--emit-staticlib`, every `pub fn` of the module as a C
symbol (§10) — there the Rust program is the host and owns `main`.
The destructor a `Handle` carries (§6) is the other direction's one
standing call, and Axiom makes it.

**One word each way.** Every Axiom value is one 64-bit word
(`MM-VAL-1`), so every shim `#[axiom_export]` generates is
`extern "C" fn(i64, ...) -> i64`. Anything that needs two words back —
bytes, a `Result`, an `Option` — goes through a trailing out-cell and a
status word, and the decoding half is *generated Axiom*, not a compiler
feature (§5).

**Rust borrows; Axiom owns.** A shim borrows its arguments for the
duration of the call and no longer (C1). A Rust value Axiom keeps is
held through a `Handle`, a counted Axiom block that runs the Rust
destructor when its last share dies (§6). Rust never writes an Axiom
block header; bytes Rust hands back are copied into an Axiom `String`
and freed on the Rust side (C4).

**The freestanding property is tiered, not traded away.** Measured on
the three programs `scripts/check-ffi.sh` builds (re-measured for this
document: `nm -u` on the linked executable, darwin-aarch64):

| program | undefined symbols | forbidden libc names |
|---|---|---|
| no `extern` (`tests/ffi/no-extern`) | **0** | 0 |
| `extern` → `rust/examples/nostd` (`no_std`) | **0** | 0 |
| `extern` → `rust/examples/demo` (`std`) | 188 | 18 |

The 188 are enumerated, one per line, in
`rust/examples/demo/axiom-allow.txt` (188 non-comment lines), and the
gate fails on any name outside that file (§14). The 18 are the names
on `scripts/check-freestanding.sh`'s 47-name list that the `std`
executable imports (`malloc`, `free`, `memcpy`, `getenv`, `fork`, ...).

---

## 2. Quickstart

```toml
# Cargo.toml of the crate you are binding
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

```sh
cargo install --path /path/to/.axiom/rust/axiom-bindgen   # once
```

```scheme fragment
; p.ax — `fragment` because `MyCrate` is the module axiom-bindgen writes
; for YOUR crate; there is no such file in this repository, so the doc
; sweep balance-checks this block rather than compiling it.
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

`--crate DIR` does the whole job: the driver runs `axiom-bindgen` when
`DIR/axiom/MyCrate.ax` is missing or older than `DIR/src`, runs `cargo
build --release` when `libaxiom_mycrate.a` is missing, searches
`DIR/axiom/` for the generated module and `DIR/target/release` (or the
workspace's, one or two levels up) for the archive, and links it
because the generated `extern` block names it (§12). The module name is
the package name in CamelCase — each `-`/`_`-separated piece
capitalised, an `axiom-` prefix dropped: `axiom-my-crate` → `MyCrate`,
`mycrate` → `Mycrate` — or the stem of the one `.ax` already in
`DIR/axiom/`, and the archive stem is the package name with `-` as `_`.
Run the tool by hand to choose another name — `axiom-bindgen --src
DIR/src --lib axiom_mycrate --module MyCrate -o DIR/axiom` — since an
Axiom module *is* its file name, and the driver keeps whatever is
there. `counterNew`'s `Counter` is dropped on the Rust
side when `c` goes out of scope; nothing is closed by hand.

The worked example is `rust/examples/demo` (every shape, `std`) with
its generated `axiom/Demo.ax`, and `rust/examples/nostd` (`no_std`,
imports nothing); `rust/README.md` is the crate-side view — what lives
in which crate, and how the checked-in bindings are regenerated.

---

## 3. The `extern` grammar

Exactly what `self_host/parser.ax` `parseExternDecl` / `parseExternItems`
/ `parseExternClauses` accept, strict since 2026-08-22:

```scheme
(pub extern "axiom_demo"                                  ; the library string
  (add      :: (-> Int Int Int) (symbol "axffi_add"))     ; an item
  (abiProbe :: Int              (symbol "axffi_abi_probe")))  ; nullary: a bare result type
```

- The block head is `extern` followed by **a library name in quotes**;
  anything else is `AX2001 expected a library name in quotes`. The string
  is live: the driver links `-l<lib>` when `lib<lib>.a` is found in a
  search directory (§12), and names it in an `AX4004`.
- An item is `(name :: type clause*)`. The type is **required** — an
  untyped item is `AX2001 expected `:: type` after extern item `name``
  (`tests/diagnostics/700`). Until 2026-08-22 an untyped item became an
  any-arity wildcard that linked and answered garbage.
- A nullary item writes a bare result type (`Int`), not `(-> Int)`.
- **`(symbol "string")` is the only clause**, at most once. A different
  head is `AX2001 expected `symbol` (unknown extern clause `x`; the
  clauses an extern item takes are: symbol)` (`tests/diagnostics/701`);
  an unquoted symbol is `AX2001 expected a quoted linker symbol after
  `symbol``. The clauses the old drafts proposed (`effects`, `opaque`,
  `drop`) are refused by this rule rather than skipped; `(opaque Thing
  ...)` used to bind an item named `opaque`.
- When the clause is absent the linker symbol is the item's own name.
  `axiom-bindgen` always writes the clause; so should you — a static link
  is one flat namespace.
- A type in the signature may be only `Int`, `Float`, `Bool`, `Char`,
  `String` or `Foreign` (§13, `AX3036`). `Handle` is refused here on
  purpose: a raw extern answers a `Foreign` word, and only
  `ffiHandleNew` turns one into a `Handle`.
- `pub` makes the items importable like any other declaration; a
  non-`pub` block binds within its own file.
- An item defines a value name: a `fn` of the same spelling in the same
  file is `AX3006 duplicate definition`; two blocks naming one library
  are not duplicates of each other (`tests/diagnostics/702`).
- Calling an item contributes the `IO` effect (C6): `tcAddExtern` seeds
  the item's `FnEnt` with `IO` and the ordinary fixpoint propagates it
  (`tests/ffi/demo/070-extern-effect-transitive.ax`).

The emitter (`codegen.ax` `emitExternItems`) writes
`declare i64 @sym(i64, ...) #0` **only for a symbol the module calls**;
a program that imports a twenty-item binding module and calls two
declares two, and every declare must ground against a linked archive
(§12). The `#0` attribute group on the declare is what keeps `opt` from
reasoning about a declared name as a libc function it knows.

---

## 4. The type table

One table, in `rust/axiom-ffi-classify/src/lib.rs`, consulted by both
the proc macro and `axiom-bindgen` — each through the `_with` form,
which takes the registry that says what a bare named type is (a
record's fields, an opaque handle) — so the two passes over one
annotation cannot drift. It is **closed**: anything not listed is a
compile error whose message lists what is accepted.

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

Refused, with the reason in the message: `u128`/`i128` ("split it into
two `u64`s"), `String`/`Vec` by value ("borrow it"), `Option`/`Result`
("may only be returned"), a by-value opaque `T` ("Axiom holds a
handle, so take `&T` or `&mut T`, or return it"), `&mut str`,
`&mut [T]` for a `T` that is not 64 bits wide ("take `&[T]` and return
a `Vec<T>`" — a converted copy could not be written back as the same
words), `&i64`, tuples, `()`.

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
type, a `Vec` or a record. Refused: `u128`/`i128`, `Vec<Vec<String>>`
and `Vec<Vec<Record>>` ("one level of word scalars"), a `Vec` of
opaque handles, a borrow (`&str`: "a borrow cannot outlive
the call"), nesting past `Result<Option<_>, _>`/`Option<Result<_, _>>` ("three
states is what the status word has"), `Option<()>` ("is a `bool`;
return one"),
`Box`/`Rc`/`Arc`, a bare `Result`/`Option` with no payload written out.

The refusals are pinned as compiler-message snapshots in
`rust/axiom-ffi-macros/tests/ui/fail/*.stderr` (20 cases) and the
accepted shapes are compiled *and run* by `tests/ui/pass/accepted_shapes.rs`.

**Names.** The symbol is `axffi_<rust_name>` unless
`#[axiom_export(symbol = "...")]` says otherwise; the Axiom name is the
Rust name in camelCase (`counter_try_new` → `counterTryNew`); a wrapped
item's raw binding adds `Raw`. `#[axiom_export]` also takes
`utf8 = "lossy"`; any other key is `unknown `axiom_export` key `k`; the
keys are `symbol = "name"` and `utf8 = "lossy"``.

---

## 5. The three protocols

### 5.1 Scalar

```rust
#[axiom_export]
pub fn add(a: i64, b: i64) -> i64 { a.wrapping_add(b) }
```

generates `#[no_mangle] pub extern "C" fn axffi_add(a0: i64, a1: i64) -> i64`
and binds as `(add :: (-> Int Int Int) (symbol "axffi_add"))` with no
wrapper. The call is one instruction sequence, identical to an internal
call (`tests/ffi/demo/010-add.ax`); a `Float` crosses as the bits it is
already stored as (`020-float-bits.ax`, `210-differential-float.ax`).

Three things the shim checks at the door, because an infallible call
has no channel for an error and the alternative is a silent wrong answer:

- a **narrow integer** out of range aborts:
  ``axiom-ffi: `byte_plus`: argument 1 (`b`: u8) is out of range: 256``
  (measured and gated: `tests/ffi/demo/115-abort-status.ax` runs
  `(bytePlus 256 1)`, prints that on fd 2 and exits 73);
- a **`&str` that is not UTF-8** aborts in an infallible shim
  (``argument 1 of `parse_int` is not valid UTF-8`` is the text), comes
  back as `Err` of that text from a `Result` shim (measured), and is
  converted with `from_utf8_lossy` under `#[axiom_export(utf8 = "lossy")]`;
  an `Option` shim aborts, since only `Result` can carry the message.
  Take `&[u8]` when the bytes are not text (`120-bytes-param.ax`);
- a **closed handle** aborts (§6).

Exit status **73**, and the message is prefixed `axiom-ffi:` on fd 2.

**73 rather than 72, since 2026-08-24.** It was 72 on the stated ground
that 72 "is what Axiom's own runtime traps use" — which is precisely
what made it useless. `MM-EXEC-16` reserves 70 for allocation failure,
71 for an operation performed with no handler, and 72 for division by
zero; all three are raised by code the Axiom compiler emitted. A
boundary abort is raised on the other side of that boundary, by a Rust
precondition the caller violated. A supervisor reading 72 in a log
could not tell *a peer sent a length that does not fit a `u32`* from
*you divided by zero*, and those two have no remedy in common. The
message always named which; the status now matches it.

**And until that day nothing executed this path at all.** Every one of
the 35 FFI cases carried `; expect 0`, so a shim that never aborted, or
aborted with any status whatever, passed every gate in this repository.
`tests/ffi/demo/115-abort-status.ax` is the probe; reverting the status
to 72 fails it with `exit 72, expected 73`.

### 5.2 Bytes (the out-cell)

```rust
#[axiom_export]
pub fn shout(text: &str) -> String { ... }
```

A `String` needs a pointer and a length back and every shim returns one
word, so the shim takes a trailing **out-cell** — `extern "C" fn
axffi_shout(a0: i64, out: i64) -> i64` — writes `{ptr, len}` into it and
answers status 0. The raw item is `(shoutRaw :: (-> String Int Int)
(symbol "axffi_shout"))` and `axiom-bindgen` writes the wrapper
(`rust/examples/demo/axiom/Demo.ax`):

```scheme
(pub :: shout (-> String String))

(pub fn (shout text)
  (let (
    (__c ffiCellNew)                    ; a 16-byte counted cell, zeroed
    (__st (shoutRaw text __c))          ; the call; status ignored here
    (__p (ffiCellWord __c 0))
    (__n (ffiCellWord __c 1))
    (__v (ffiBytesToStr __p __n))       ; COPY into a fresh Axiom String
  )
    {
      (ffiFreeBytes __p __n)            ; give the Rust bytes back
      (ffiCellFree __c)
      __v
    }
  )
)
```

The copy is the design's central safety rule (C4): only Axiom's
emitter writes an Axiom block header, because only it knows
`MM-LIFE-2d`'s shape word. The window in which Rust memory is reachable
from Axiom is one copy long. Every generated local is `__`-prefixed and
a Rust parameter may not start with `__`, so a parameter named `cell`
or `p` reaches Rust intact (`080-param-named-cell.ax`; the old generator
shadowed it and answered a heap address).

The helpers live once, in `stdlib/Ffi.ax` (imports `Mem`, `Str` and
`Vec` only), so two generated modules import together without colliding:

```scheme
(pub :: ffiCellNew     Int)                 ; a 16-byte out-cell, zeroed, held by one share
(pub :: ffiCellFree    (-> Int Int))        ; releases it
(pub :: ffiCellWord    (-> Int Int Int))    ; (cell i) -> word i
(pub :: ffiBytesToStr  (-> Int Int String)) ; (ptr len) -> a fresh COPY; does not free
(pub :: ffiStatusOk    Int)  ; 0
(pub :: ffiStatusErr   Int)  ; 1
(pub :: ffiStatusNone  Int)  ; 2
(pub extern "axiom_ffi"
  (ffiFreeBytes  :: (-> Int Int Int) (symbol "axffi_free_bytes"))
  (ffiAbiVersion :: Int (symbol "axffi_abi_version")))
```

`axiom_ffi` has no archive of its own: `axffi_free_bytes` and
`axffi_abi_version` are defined in every crate that depends on the
facade, the driver links a library string only when its archive exists,
and a declare grounds against whatever archives are linked. So a
program that imports `Ffi` and calls nothing links with no archive at
all.

### 5.3 Fallible: `Result` and `Option`

Same cell, plus the status word. `Result<T, E>` answers 0 with the
payload in the cell, or **1** with the `Display` text of the error as
`{ptr, len}`; `Option<T>` answers 0 with the payload, or **2** with the
cell untouched. A global last-error slot would be sound (`MM-PAR-1`, no
threads) but makes every call site order-dependent; a wider return is
impossible. The wrapper turns the status into the ordinary `Result` of
`stdlib/Err.ax` or the builtin `Option`:

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

(Shown compacted; the generated file is laid out as `axiom fmt` lays
it out, and is `axiom fmt --check` clean.) A `Result<String, _>` copies
the payload bytes as §5.2 does; a `Result<Counter, String>` builds the
handle on `Ok` — `(Ok (Counter (ffiHandleNew __p counterDropFn)))` —
and builds nothing on `Err`, so no value is ever boxed and lost
(`100-result-opaque.ax`). A `Result<(), E>` binds as `(Result Int
String)` answering `(Ok 0)`: `()` has no value in Axiom. Measured:
`(parseInt s)` for a two-byte `s` of `FF 31` → ``Err "argument 1 of
`parse_int` is not valid UTF-8"``, `(maybe -1)` → `None`,
`(counterTryNew -3)` → `Err "counter cannot start below zero (got -3)"`.

Before the classifier was closed, `Option<i64>` fell through a
`_ => Opaque` arm and came back as a leaked box address typed `Foreign`
(measured: `(maybe 5)` printed 4308868288). That arm no longer exists.

---

## 6. The handle protocol

An arbitrary Rust type — a `sha2::Sha256`, a `reqwest::Client` — never
has to be describable in Axiom's type system. It is marked, boxed, and
held through a counted Axiom block that knows how to destroy it.

**Rust side.** `#[axiom_opaque]` on a `struct` or `enum` (monomorphic;
a generic type is refused, "a symbol cannot be generic") generates:

```rust
#[no_mangle] pub unsafe extern "C" fn axffi_counter_drop(h: i64) -> i64   // null-checked Box::from_raw; answers 0
#[no_mangle] pub extern "C" fn axffi_counter_drop_fn() -> i64             // the address of the above
```

(stem = snake_case of the type name; `#[axiom_opaque(symbol = "x")]`
overrides it) and an `impl AxiomOpaque for Counter`. That trait bound
is what makes "an opaque return needs `#[axiom_opaque]`" a compile
error rather than a leak: the shim for a function returning or
borrowing `T` calls helpers that require it, and an unmarked type reads
`` `Plain` crosses the Axiom boundary as an opaque handle but is not marked
`#[axiom_opaque]` `` with the note to put the attribute on the
declaration. `axiom-bindgen` refuses the same case from its side.

A returning shim boxes the value and answers its address; a borrowing
shim (`&T`, `&mut T`) reads the word, **aborts if it is 0** —
``axiom-ffi: `counter_value`: handle is closed`` (measured, exit 73) —
and otherwise borrows for the call. Axiom has no threads (`MM-PAR-1`),
so the only way to alias a `&mut` is to pass one handle twice in one
call; that is a program obligation.

**Axiom side.** The builtin type `Handle` is a counted heap block of
the **foreign form**: shape-word bit 0 set, two payload words —
word 0 the destructor's address, word 1 the Rust pointer
(`stdlib/Ffi.ax`; `MM-FFI-6`). `ffiHandleNew` is the one door that
writes it; `memAllocMapped` masks its map to bits 16..62 and cannot set
the form bit, and no constructor site does.

```scheme
(pub :: ffiHandleNew   (-> Int Int Handle))  ; (ptr dropFnAddr) -> a fresh Handle, one share
(pub :: ffiHandlePtr   (-> Handle Int))      ; the raw pointer, 0 once closed
(pub :: ffiHandleLive  (-> Handle Bool))     ; ptr != 0
(pub :: ffiHandleClose (-> Handle Int))      ; destructor NOW, once; pointer zeroed; answers 0
```

`Handle` is a **reference** in every classification — `fldClass`
answers 2 and `evClassOf` 1, their reference classes — so a `data` cell
holding one maps it, a `let` of one releases it at scope end, and a
share is retained and released by the same events as a `String`.
`Foreign` stays a word (class 0) that nothing walks. A raw `extern`
item never answers `Handle` (`AX3036`).

**Death.** When the count reaches zero, `@axiom_release` (the emitted
release runtime, `codegen.ax`, label `foreign:`) reads the two words;
if both are non-zero it stores 0 into the pointer word, calls the
destructor **once** as `i64 (i64)`, and files the block by its size
class like any other. A block of the foreign form has no reference map
and is never walked. The destructor may re-enter `@axiom_release` — a
Rust `Drop` giving back Axiom values the shim retained — because each
invocation keeps its dead list in a local, so the re-entrant call is
an ordinary one.

**Early close.** `ffiHandleClose` runs the destructor now and zeroes
the pointer; the block's own death then calls nothing, and a second
close is a no-op. A later borrow through that handle is the abort above
rather than a dereference of null. Use it for the value that must go
*now* — a file, a lock — and nothing else.

**The generated shape** (`Demo.ax`):

```scheme
(pub data Counter (Counter Handle))          ; one per #[axiom_opaque] type

(pub :: counterNew (-> Int Counter))
(pub fn (counterNew start)
  (let ((__p (cast Int (counterNewRaw start)))
        (__h (ffiHandleNew __p counterDropFn)))
    (Counter __h)))

(pub :: counterValue (-> Counter Int))
(pub fn (counterValue c)
  (match c
    ((Counter __h0)
      (let ((__a0 (cast Foreign (ffiHandlePtr __h0)))
            (__r (counterValueRaw __a0)))
        __r))))

(pub :: counterClose (-> Counter Int))       ; explicit early close, optional
(pub fn (counterClose c)
  (match c ((Counter __h) (ffiHandleClose __h))))
```

The cell holds the `Handle`, so the cell's death releases the handle,
whose death runs the Rust `Drop`; `Counter` and `Widget` stay distinct
Axiom types because each is its own `data`. `(cast Int x)` /
`(cast Foreign x)` are bit-reinterpretations and the documented way
across the `Foreign`/`Int` line.

**Measured** (`tests/ffi/demo/060-opaque-handle.ax`, run for this
document: prints `opaque handle: agree`, exit 0): a loop builds 200
`Counter`s and lets each go at the end of its `let`; the crate's
`Drop` counter — read through `countersDropped` — answers **200** with
no close call anywhere, and **201** after one explicit `counterClose`
on a handle still held (closed only after its last read, since a read
after it would abort). `400-arc-retain.ax` churns 500 strings
through `axiom_retain`/`axiom_release` from the Rust side;
`410-foreign-not-walked.ax` and `420-null-foreign.ax` pin that a bare
`Foreign` field — including 0 — is skipped by the release walk.

---

## 7. Callbacks

A Rust function can take an Axiom function. On the Rust side the
parameter is `axiom_ffi::AxFn1`, `AxFn2` or `AxFn3` — a `Copy` struct
around the closure word with `.call(a)`, `.call(a, b)`, `.call(a, b, c)`,
every argument and the result a plain `i64`:

```rust
#[axiom_export]
pub fn apply_twice(f: AxFn1, x: i64) -> i64 { f.call(f.call(x)) }

#[axiom_export]
pub fn fold3(f: AxFn2, a: i64, b: i64, c: i64) -> i64 { f.call(f.call(a, b), c) }
```

and on the Axiom side the parameter is the arrow with the matching
arity — `(-> Int Int)` for `AxFn1`, `(-> Int Int Int)` for `AxFn2`,
`(-> Int Int Int Int)` for `AxFn3` — which is what `axiom-bindgen`
writes:

```scheme
(applyTwice :: (-> (-> Int Int) Int Int) (symbol "axffi_apply_twice"))
(fold3 :: (-> (-> Int Int Int) Int Int Int Int) (symbol "axffi_fold3"))

(applyTwice (lambda (x) (+ x k)) 1)         ; 21 when k is 10 - a capture
(applyTwice triple 2)                       ; 18 - a top-level function
(fold3 (lambda (a b) (plus a b)) 1 2 3)     ; 6
```

`tests/ffi/demo/130-callbacks.ax` is the fixture. What crosses is the
closure record's address: word 0 of an Axiom closure is its code, an
`extern "C" fn(env, arg) -> i64` that takes the record itself as `env`,
so `AxFn1::call` is one indirect call with no trampoline. Axiom
functions are curried — `(lambda (a b) ...)` is a one-argument lambda
answering a one-argument lambda — so `AxFn2::call` and `AxFn3::call`
apply one argument per step, exactly as the emitter's own
`emitApplyChain` does, and release each intermediate link they were
answered (those links are owned, `MM-LIFE-2c` event 2). A bare
top-level function is a value at arity 1 only (`AX3013`: a partial
application has nowhere to hold its arguments), so a two-argument
function reaches `fold3` through `(lambda (a b) (plus a b))`, as the
diagnostic's help says.

The callback is **borrowed** (C1): valid for the call, not after it. A
shim that stores one takes a share with `axiom_retain` and pairs it
with `axiom_release`. The type discipline admits as a *parameter* any
arrow of arity one to three whose every leaf is a **word** — `Int`,
`Float`, `Bool`, `Char` (`allIntArrow` in `tcCheckExternTypes`): a
`(-> Float Float)` callback is called with the argument's bits and
answers bits, so the Rust side writes `f64::from_bits(f.call(x.to_bits()
as i64) as u64)`. An arrow with a `String` leaf is refused (`AX3036`):
a String argument or result would carry a share that the Rust side has
no wrapper to release. An arrow in result position, and `AxFn` as a
Rust return type or behind a reference, are refused on their respective
sides (the macro's `tests/ui/fail/callback_return.rs`,
`callback_ref_param.rs`): Rust cannot build an Axiom closure record
(C4). A callback that panics aborts the process (C7); a callback has
no way to unwind back through the Rust frame.

---

## 8. `Vec`, slices and records across the boundary

All over words, none of them writing an Axiom block from Rust (C4):

| Rust | Axiom | wire |
|---|---|---|
| `-> Vec<T>`, `T` a word scalar (`i64`, the narrow ints other than `u8`, `usize`/`isize`, `bool`, `f64`, `f32`) | `(Vec Int)` | the out-cell holds `{ptr, len}` of words — each element widened to its word (ints extended, `bool` 0/1, floats as `f64` bits); the wrapper copies with `ffiWordsToVec` and returns the buffer with `ffiFreeWords` → `axffi_free_words(ptr, len)` |
| `-> Vec<String>` | `(Vec String)` | the cell holds `{ptr, n}`, `ptr` at `2n` words of `(bytes, len)` pairs; `ffiStrsToVec` copies each string, `ffiFreeStrList` → `axffi_free_str_list(ptr, n)` frees every string and the pair buffer |
| `&[T]` parameter, `T` a word scalar other than `u8` | `(Vec Int)` | the `Vec` handle itself; Rust reads it as `axiom_abi::AxVec` (word 0 `len`, 1 `cap`, 2 the data pointer) for the call only — `&[i64]` and `&[f64]` as the words are, any other `T` through a range-checked temporary (out of range **aborts**, §5.1) |
| `&[&str]` parameter | `(Vec String)` | the `Vec` handle; each word a `Str`, viewed as `&str` for the call, UTF-8 checked |
| `Point` parameter, `#[axiom_record]` | `Point` (a `data` type) | **one word per field**, in declaration order; the wrapper destructures with `match` |
| `-> Point` | `Point` | the out-cell holds the field words (`ffiCellNewN n`); the wrapper constructs the `data` value |
| `&[Point]` parameter | `(Vec Point)` | the wrapper flattens into a words `Vec` (`ARITY` per element, a private loop bindgen writes); the shim chunks them with `from_words` |
| `-> Vec<Point>` | `(Vec Point)` | the cell holds `{ptr, n}` over `n × ARITY` words; the wrapper rebuilds each element with `ffiWordAt` and frees with `ffiFreeWords` |
| `-> Vec<Vec<T>>`, `T` a word scalar | `(Vec (Vec Int))` | the cell holds `{ptr, n}`, `ptr` at `2n` words of `(words, len)`; `ffiWordListsToVec` copies, `ffiFreeWordLists` → `axffi_free_word_lists(ptr, n)` |
| `&[&[T]]` parameter | `(Vec (Vec Int))` | the outer `Vec` handle; the shim reads each inner `AxVec` for the call |
| `&mut [i64]`, `&mut [f64]`, `&mut [u64]` | `(Vec Int)` | the `Vec`'s live elements, written in place |

(`&[u8]` and `Vec<u8>` are not in this table because they were already
in §5: a byte slice is a `String`'s bytes, and stays one.)

**A `Vec` parameter is always wrapped**, even where the return is a
plain scalar and nothing else would need one. `AX3036` refuses `(Vec
a)` in an `extern` item — the boundary names six word types and a `Vec`
is not one of them — so the raw item takes the handle as `Int` and the
wrapper is the one place that casts:

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

Without the wrapper the ergonomic name would be the raw item and its
signature would say `Int`, putting a `cast` at every call in user code
— which is the shape `MM-VAL-22` measures as a lost retain. One
generated wrapper puts that cast in one reviewed place and lets the
caller pass the vector it has.

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
(sumWords (rangeVec 5))                     ; 10 - the Vec goes in as itself
(cast Float (vecGet (halves 3) 1))          ; 0.5 - a Float element is its bits
(joinWords (vecOf "a" "b"))                 ; "a b"
(match (pointScale (Point 1 2.5) 2)
  ((Point x y) ...))                        ; x = 2, y = 5.0
```

A **record** is a plain struct with named fields, every field a word
scalar (`i64`, the narrow ints, `bool`, `f64`, `f32`) — not a `String`,
not `char`, not an opaque type, not another record (each refused with
the accepted set in the message). `#[axiom_record]` derives `AxRecord`
(`ARITY`, `from_words`, `write_words`; a narrow field out of range
aborts like a narrow parameter), the shim takes or writes one word per
field, and `axiom-bindgen` emits `(pub data Point (Point Int Float))`
beside the opaque types and wraps each use:

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

How the macro knows `Point` is a record when it sees only the
function: `#[axiom_record]` and `#[axiom_opaque]` each emit a companion
`macro_rules!` named like the type, and `#[axiom_export]` over a bare
`T` expands through it, so the shape is resolved at the use site
whatever the order of the items or the module they came from. A type
marked with neither is refused twice over: the companion is missing,
and an `AxiomMarked` assertion says ``crosses the Axiom boundary but is
not marked `#[axiom_opaque]` or `#[axiom_record]` ``.

`Result<Point, E>` and `Option<Point>` put the field words after the
status as any payload; the cell is `max(ARITY, 2)` words so an error
message fits. Descriptors count one tag per field (§9), so a record
that gains a field changes the shim's shape and a stale binding module
is `AX4005`, not a misread register. `Result<Option<T>, E>` and
`Option<Result<T, E>>` use the three statuses as three states —
`Ok(Some)`/`Ok(None)`/`Err`, `Some(Ok)`/`Some(Err)`/`None` — and the
wrapper nests the constructors. `tests/ffi/demo/140-vec.ax`,
`150-records.ax`, `160-str-slice.ax`, `170-vec-scalars.ax`,
`180-char.ax`, `181-vec-records.ax`, `182-nested-vec.ax`,
`183-mut-slice.ax` and `184-nested-fallible.ax` are the fixtures.
Still refused, each with its reason: `&[String]` and `Vec<String>` as
parameters (say `&[&str]`), `Vec<Vec<String>>`/`Vec<Vec<Record>>` (one
level of word scalars), `&mut [T]` for a `T` narrower than a word, a
`Vec` of opaque handles, nesting past one `Result`/`Option` inside
the other (three states).

---

## 9. The shape check (`AX4005`)

Every `#[axiom_export]` shim `axffi_x` is accompanied by a no-op
**descriptor** symbol whose name spells the shim's shape:

```
axffi_add__sig_ii_i            add(i64, i64) -> i64
axffi_shout__sig_si_i          shout(&str) -> String        (s = string; the out-cell is a word)
axffi_map3__sig_ciii_i         map3(AxFn1, i64, i64, i64)   (c = callback)
axffi_scale__sig_f_f           scale(f64) -> f64            (f = float)
axffi_abi_version__sig__i      abi_version() -> i64
```

One tag per parameter, then `_`, then the result: `i` a plain word
(`Int`, `Bool`, `Char`, a `Foreign` or `Handle`, a narrow int, a `Vec`
handle, the out-cell, a unit result), `f` a `Float`, `s` a `String`
parameter, `c` a callback. The driver derives the same string
from the Axiom item's declared type (`sigTagOf` in `driver.ax`) and,
when the archive holds a descriptor for the symbol, refuses a
disagreement at the item, before any tool runs:

```
error[AX4005]: `axffi_add` is exported by the crate for `(-> Int Int Int)`; the `extern` item declares `(-> Int Int)`
 --> 050-shape-mismatch.axbad:10:4
  = help: the Rust shim and the `extern` item must agree on every parameter and the result
    (docs/ffi.md, the type table); regenerate the binding module with `axiom-bindgen`, or
    fix the hand-written item
```

A symbol with no descriptor in any archive — a hand-written raw shim —
is grounded (`AX4004`) but not shape-checked; the `#[axiom_opaque]`
drop shims carry none. Until this check existed a two-argument
declaration over a three-argument shim built, linked, and answered
whatever sat in the third register; `tests/ffi/probe-ungrounded/050`
is the fixture and `scripts/check-ffi.sh` runs it. `axiom explain
AX4005` has the long form.

---

## 10. The other direction: an Axiom archive for a Rust host

`--emit-staticlib` builds an Axiom module as a static archive with no
`main` of its own, for a program written in another language to link:

```sh
axiom build --input hostlib.ax --output libaxiom_hostlib.a --emit-staticlib
```

The codegen omits the `@main` wrapper (`cgStaticlib`), the driver
assembles and archives with `ar rcs`, and the file need not define
`main` at all. Every `pub fn` of the entry module is a C symbol under
its own name; the stdlib it pulls in is there under the `Module$name`
spelling, so a host can build Axiom strings with the archive's own
allocator:

```scheme
; hostlib.ax
(import Str)
(pub :: addTwo (-> Int Int Int))
(pub fn (addTwo a b) (+ a b))
(pub :: shout (-> String String))
(pub fn (shout s) ...)                      ; ASCII upper-case, a fresh String
```

A host can write the `extern "C"` block by hand — the ABI is one
`i64` per word — or have the build write it:

```sh
axiom build --input hostlib.ax --output libaxiom_hostlib.a \
            --emit-staticlib --emit-rust-binding hostlib.rs
```

`--emit-rust-binding PATH` writes, from the same declarations the IR
came from, the Rust view of the file's `pub` surface (`self_host/rustbind.ax`):
one `extern "C"` declaration per function in a `raw` module, and one
safe wrapper per function in Rust's own types —

```rust
mod raw {
    extern "C" {
        pub fn addTwo(a0: i64, a1: i64) -> i64;
        pub fn shout(a0: i64) -> i64;
    }
}

/// `(pub :: addTwo (-> Int Int Int))`
pub fn add_two(a: i64, b: i64) -> i64 {
    // SAFETY: the archive defines the symbol with exactly this shape (one word each way).
    let __r = unsafe { raw::addTwo(a, b) };
    __r
}

/// `(pub :: shout (-> String String))`
pub fn shout(s: &str) -> AxString {
    let __a0 = AxString::from_str(s);
    // SAFETY: the archive defines the symbol with exactly this shape (one word each way).
    let __r = unsafe { raw::shout(__a0.as_word()) };
    // SAFETY: a String a function answers is an owned share (MM-LIFE-2c event 2).
    unsafe { AxString::from_owned(__r) }
}
```

— which a host uses as a module:

```rust
mod hostlib;
fn main() {
    println!("{}", hostlib::add_two(40, 2));                         // 42
    println!("{}", hostlib::shout("hello").as_str().unwrap());       // HELLO
}
```

| Axiom | Rust parameter | Rust result | how |
|---|---|---|---|
| `Int` | `i64` | `i64` | the word |
| `Float` | `f64` | `f64` | `to_bits` / `from_bits` |
| `Bool` | `bool` | `bool` | `as i64` / `!= 0` |
| `Char` | `char` | `char` | the code point; `from_u32(..).unwrap_or('\u{FFFD}')` |
| `String` | `&str` | `AxString` | `AxString::from_str` (the archive's `Str$strAlloc`) for the call; the result adopted with `from_owned` |
| `Handle`, `Foreign` | `AxWord` | `AxWord` | the bare word |
| `()` result | — | `()` | the word dropped |

Names are snake-cased (`addTwo` → `add_two`; a Rust keyword gets a
trailing underscore).

**Values with structure.** A `data` or `struct` of the file, `Option`,
`Result`, and any instantiation a `pub` signature mentions (`(Option
Pair)`, `(List Int)` of the file's own `List`) cross as values. The
archive cannot be read from outside — only the emitter knows a block's
layout — so the same build **synthesises accessor shims into the
module** before it is checked and compiled (`rbAppendShims` in
`self_host/rustbind.ax`; they are ordinary `pub fn`s, type-checked like
the file's own):

```
axh_<T>_tag v             the constructor's index, in declaration order
axh_<T>_<Ctor> f0 f1 ..   a fresh value (an owned share)
axh_<T>_<Ctor>_<i> v      field i (a reference field: an owned share)
axh_vec_new / axh_vec_push / axh_vec_len / axh_vec_get
```

and the binding writes, per type, a Rust `struct` (one constructor;
the declared field names, or `f0..`) or `enum` (tuple variants) with
`from_axiom`/`to_axiom`, maps `(Option T)` to `Option<T>` and
`(Result T E)` to `Result<T, E>`, boxes a field that reaches its own
type (`Cons(i64, Box<List_Int>)`), and converts at every boundary:

```scheme
(pub data Shape (Circle Float) (Rect Int Int) (Empty))
(pub struct Named (name : String) (score : Int))
(pub :: shapeGrow (-> Shape Int Shape))
(pub :: safeDiv (-> Int Int (Result Int String)))
```

```rust
pub enum Shape { Circle(f64), Rect(i64, i64), Empty }
pub struct Named { pub name: AxString, pub score: i64 }
pub fn shape_grow(s: &Shape, k: i64) -> Shape
pub fn safe_div(a: i64, b: i64) -> Result<i64, AxString>

let grown = hostlib::shape_grow(&Shape::Rect(2, 3), 2);     // Shape::Rect(4, 6)
let err = hostlib::safe_div(1, 0);                          // Err("division by zero")
```

An Axiom `Vec` carries its element type on the Axiom side and nothing
on the Rust one, so a signature naming `(Vec Int)` spells `AxWord` in
the binding and the host builds and reads one through `AxVecBuf`
(`from_words`, `as_word`, `words`; released on drop). The ownership rule the binding follows is the emitter's own,
read from its IR: an **argument is borrowed** (a callee that keeps one
retains it — a constructor does), a **result is an owned share**
(`MM-LIFE-2c` event 2). So `to_axiom` answers an owned word the
wrapper releases after the call, `from_axiom` consumes the word it was
given, and every accessor's answer is adopted or released.
`rust/examples/host` round-trips each of these shapes ten thousand
times through the allocator to show the shares balance.

A `pub fn` whose signature names a type variable, a tuple, an arrow or
a `[T]` list type — or a `data` whose fields reach one — or that has
no `(pub :: name Type)` signature is **named in a comment at the end
of the file** rather than silently omitted:

```
// Not bound - call these through the archive by hand, or change the type:
// `identity`: `(-> a a)` names `a`, which the binding does not carry
```

The file is laid out by `rustfmt` when one is on `PATH` (the build
runs it, as it runs `cargo`); without one the raw text compiles all
the same.

The result adoption rests on `MM-LIFE-2c` event 2: a function that
answers a counted reference answers a share of its own, so the host
owns what it gets even when the function answered its argument —
`hostlib.ax`'s `(pub fn (same s) s)` compiles to a `@axiom_retain`
before its `ret`, and `rust/examples/host` calls it ten thousand times
against the free list to prove the two releases are two shares. The
runtime needs no init call: the allocator initialises on first use.
`IO` functions work — the archive contains the syscall layer — and a
panic in Axiom (an `assert`, an out-of-range index) exits the process
as it would from `main`. Effects are not checked across the boundary:
the host is outside the effect system and calls what it likes.

`rust/examples/host` is the worked host: `src/hostlib.rs` is the
generated binding, checked in, and `build.rs` links
`$AXIOM_HOST_ARCHIVE_DIR/libaxiom_hostlib.a`. The gate builds both
from `tests/ffi/host/hostlib.ax`, diffs the checked-in binding against
the fresh one and requires it `rustfmt`-clean (when `rustfmt` is
present), runs the host and checks that it reports agreement (§14).
What does not exist: an `export` block — every `pub fn` is exported,
and so, as a matter of fact, is every other function of the entry
file, under its own name; the binding declares only the `pub` ones.

---

## 11. The contract

Eight rules, each defined here and cited from the code (`codegen.ax`
`scanExternSigs` cites C1; `tests/ffi/demo/040-owned-bytes.ax` cites
C2).

- **C1 — A shim borrows; retain to keep.** Every argument is valid for
  the call and no longer: ARC may release the block the moment the shim
  returns, and an arena reset may reclaim it wholesale. A shim that
  wants an Axiom value past the call takes its own share with
  `axiom_retain` and pairs it 1:1 with `axiom_release`; both have
  external linkage in every emitted module. The emitter gives an extern
  item **empty STASH and RET flow masks** (`scanExternSigs`): it parks
  nothing and answers nothing of what it was handed. Before that entry
  existed every extern call parked every argument and a `Counter` cell
  handed to `counterValueRaw` never died. The demo's hand-written
  `axffi_str_keep`/`axffi_str_recall`/`axffi_str_drop` are the worked
  example (`400-arc-retain.ax`); a literal's count word is −1, the
  statics sentinel, so retaining one is free and releasing one a no-op.
- **C2 — One word each way; every shim returns `i64`.** One word in per
  argument, one word out, `extern "C"`, no exceptions; a `void` shim
  would make the call site read a register the callee never set. `()`
  crosses as 0. Anything that needs two words back takes the out-cell.
- **C3 — Status words are 0, 1, 2.** `AX_OK = 0`, `AX_ERR = 1` (message
  `{ptr, len}` in the cell), `AX_NONE = 2` (cell untouched). There is no
  panic status (C7). The out-cell is two words the caller owns; the shim
  writes it and never keeps its address.
- **C4 — Only Axiom writes block headers.** Bytes from Rust are copied
  by `ffiBytesToStr` and returned by `ffiFreeBytes`; Rust never
  constructs a `Str` header or any other Axiom block, because only the
  emitter knows the shape word (`MM-LIFE-2d`).
- **C5 — Destructors are `i64 (i64)` and null-safe.** The function a
  `Handle` carries takes the pointer word, frees it if non-zero, answers
  0, and is called at most once per handle (the runtime zeroes the word
  before the call; `ffiHandleClose` zeroes it too). `#[axiom_opaque]`
  generates exactly this; a hand-written one must match it.
- **C6 — An extern call is `IO`.** Reaching Rust is an effect like a
  syscall, seeded at registration and propagated transitively. There is
  no distinct `FFI` effect; `;@axiom:effect(ffi)` is not a claim the
  checker knows.
- **C7 — No unwinding; a panic aborts.** Axiom's emitter never writes
  an `invoke` or a landing pad, and `extern "C"` aborts on unwind (Rust
  1.81+). The workspace and the examples build with `panic = "abort"`;
  a `no_std` crate's panic handler writes the message to fd 2 and exits
  73 — the same status as every other boundary abort (§5.1), and
  deliberately not one of `MM-EXEC-16`'s. A panic that reaches the
  boundary ends the process, with a message; it never returns a status.
- **C8 — The wire has a version.** `axffi_abi_version` answers **2**
  and is bumped on any change to a wire representation (the word, the
  `Str` layout, the cell, the statuses); `tests/ffi/demo/310-abi-version.ax`
  pins it and `ffiAbiVersion` reads it from Axiom. Version 1 was the
  first boundary (statuses 0/1); 2 added status 2, the drop function and
  the narrow-int checks.

---

## 12. Linking and the driver

`self_host/driver.ax` `effectiveLinkArgs` builds the link line in this
order, each directory once, existing directories only:

1. explicit `--link-search DIR` (`-L`) and `--link-lib NAME` (`-l`), as given;
2. every directory of `$AXIOM_LINK_SEARCH` (colon-separated);
3. `<entry>/../target/release` and `<entry>/../../target/release` for
   each `$AXIOM_PATH` entry — a crate's `axiom/` binding directory sits
   beside its `target/`;
4. `DIR/target/release`, `DIR/../target/release` and
   `DIR/../../target/release` for each `--crate DIR` (a crate inside a
   workspace builds into the workspace's `target`; `rust/examples/demo`
   builds into `rust/target`);
5. then `-l<lib>` for every `extern` block's library string whose
   `lib<lib>.a` some directory above holds and no explicit `-l` already
   names.

The library string travels from the emitter to the driver as a comment
line in the IR (`; axiom-extern-lib axiom_demo`) beside the declares.
`--crate DIR` (repeatable; `build`, `run`, `check`) additionally puts
`DIR/axiom/` on the module search path, so `(import Demo)` finds the
generated module. `--link-lib`/`--link-search` remain as overrides.

**The crate builds itself.** `prepareCrates` runs before the entry is
read: for each `--crate DIR`, when `DIR/axiom/*.ax` is missing or older
than the newest file under `DIR/src` and `axiom-bindgen` is on `PATH`,
the driver regenerates the module (`--src DIR/src --lib <stem>
--module <Name> -o DIR/axiom`, saying so on stderr); when no `lib<stem>.a`
exists in any of the crate's `target/release` directories and `cargo`
is on `PATH`, it runs `cargo build --release --manifest-path
DIR/Cargo.toml`. The stem and the name come from `DIR/Cargo.toml`'s
`[package] name` (`-` → `_` for the stem; CamelCase, `axiom-` prefix
dropped, for the module — or the single `.ax` already in `DIR/axiom/`).
Neither tool being present is not an error: the driver then expects the
artefacts to exist and reports `AX4004` or an unresolved import if they
do not. `cargo install --path rust/axiom-bindgen` puts `axiom-bindgen`
on `PATH`. Measured on the demo crate: 4 s from a clean `target/`, 0.7 s
when nothing has changed (the checks are file-time comparisons and one
`axiom-bindgen --check --quiet`, whose exit status is the answer).

**Grounding.** Before a byte is written or a tool spawned,
`groundExternsSpanned` reads every archive on the line and checks that
each `declare`d name appears **whole** in an archive's symbol table —
`\0_name\0` (Mach-O) or `\0name\0` (ELF). Until 2026-08-22 this was a
substring scan, so `axffi_ad` grounded against `axffi_add` and died in
the linker with a message about `cc`. A name that fails is `AX4004` at
the item's span, in three voices (each measured for this document):

```
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

The did-you-mean is the `axffi_*` name in the archives sharing the
longest prefix with the missing one, when that prefix reaches past
`axffi_`. The span is the item's, in whichever module declared it — an
imported binding module, usually. `groundDeclares` remains as the
span-less fallback (`no archive on the link line defines `x``) for IR
built by a path without declarations. The check is one-directional: it
proves nothing on the line can define the name, and does not claim a
name that appears is a definition rather than a string constant.

---

## 13. Diagnostics

| code | when | message |
|---|---|---|
| `AX2001` | an extern item without `:: type` | ``expected `:: type` after extern item `add` (an extern item declares its type: `(name :: (-> Int Int) (symbol "c_name"))`), found `(` `` |
| `AX2001` | a clause head other than `symbol` | ``expected `symbol` (unknown extern clause `symbo`; the clauses an extern item takes are: symbol), found `symbo` `` |
| `AX2001` | an unquoted symbol | ``expected a quoted linker symbol after `symbol`, found `axffi_add` `` |
| `AX2001` | a block without a quoted library name | `expected a library name in quotes` |
| `AX3036` | a type the boundary cannot carry | ``an `extern` item cannot carry the type variable `a` across the boundary`` — also `a tuple`, `a list`, ``a function-typed argument (a callback is an arrow over words only - `Int`, `Float`, `Bool`, `Char` - such as `(-> Int Float)`)`` (the word-leaf arrows of §7 pass), ``the type `Option` ``, ``the type `Handle` ``, `` `Int` applied to type arguments`` |
| `AX3002` | a type name nothing declares | ``undefined type `Slice` `` with the help "use `Foreign` for an opaque handle" |
| `AX3006` | a `fn` spelled like an item | ``duplicate definition `add` `` pointing at both |
| `AX4004` | a declared symbol no linked archive defines | §12, three voices |
| `AX4005` | a declared type that disagrees with the shim's descriptor | §9 |
| `AX2004` | `foreign` | a removed construct; migration advice names `extern`. Permanent |

`AX3036`'s help: "an `extern` signature names only `Int`, `Float`,
`Bool`, `Char`, `String` and `Foreign` (one machine word each way); a
Rust value of any other shape crosses as a `Foreign` handle, or through
the wrapper `axiom-bindgen` generates (a `String` result, a `Result`,
an `Option`, an opaque type)". `tcCheckExternTypes` walks the
signature's own arrow spine; an arrow in parameter position passes
only as a callback over word leaves (`allIntArrow`), and an arrow
anywhere else is refused. `tests/diagnostics/700`–`702` are the
goldens; `axiom explain AX3036`, `AX4004` and `AX4005` carry the long
form.

On the Rust side, every refusal is a compile error at the offending
type or key, with the accepted set in the message (§4), and the
runtime refusals — out of range, not UTF-8, closed handle — abort with
`axiom-ffi: ...` on fd 2 and exit 73 (§5.1, §6). `axiom-bindgen`
refuses an unmarked opaque type, a camelCase collision (``Axiom name
`fooBar` is generated twice: for ... and for ...; rename one (camelCase
folds `foo_bar` and `fooBar` together, and wrapped items also claim
`<name>Raw`)``), two opaque types of one name, a `__`-prefixed
parameter, and `self`.

---

## 14. The gate

`scripts/check-ffi.sh` is the gate `MM-FFI-5` requires: the one that
*enumerates* permitted external symbols rather than forbidding all of
them. It needs `cargo` (the compiler itself never does — a checkout
without cargo skips this gate rather than failing it) and proves, in
order:

1. **Tier 1** — every program in `tests/ffi/no-extern/` builds and
   imports **nothing** (`nm -u` empty); at least three cases must reach
   this check.
2. **Tiers 2 and 3** — for each `rust/examples/<crate>/` with an
   `axiom-allow.txt`: build the crate (`nostd` by its own manifest, since
   it is its own workspace), then for each `tests/ffi/<crate>/*.ax`:
   build it with `--crate`, **run it**, compare the exit status with the
   fixture's `; expect N` trailer, require an `agree` line when the
   fixture contains one, and fail on any imported symbol the manifest
   does not permit. A manifest may not launder `printf`, `puts`,
   `fopen`, `fwrite`, `fread`, `system`, `popen`, `execv`, `execve` or
   `posix_spawn`. The run step is new: a gate that builds and never
   runs cannot tell a silent wrong answer from a pass, and the silent
   wrong answer is this boundary's whole failure class.
3. **Regeneration** — every checked-in `rust/examples/*/axiom/*.ax` is
   regenerated by `axiom-bindgen` and must be byte-identical.
4. **Nine negative probes**, because a set relation is also satisfied
   by an empty corpus, an `nm` that answers nothing and a manifest that
   permits everything: the symbol reader sees an undefined symbol in a C
   object; the manifest comparison flags an unpermitted name; and leaves
   a permitted one alone; `foreign` is still `AX2004`; the allowlist
   goes RED on `rust/examples/leaky` (which calls `std::env::var`
   against a manifest permitting nothing); an ungrounded symbol is
   `AX4004` **and** the strings `opt:` and `AX4003` are absent (a
   refusal from the toolchain would be the `foreign` bug wearing a new
   name); a prefix of a real symbol is `AX4004` naming the real one;
   nothing linked is said in those words, at the item; a declaration
   of the wrong shape is `AX4005` (§9), not a build.
5. **The host direction** — `tests/ffi/host/hostlib.ax` is archived
   with `--emit-staticlib --emit-rust-binding`, the archive is checked
   to define no `main`, the fresh binding must be byte-identical to the
   checked-in `rust/examples/host/src/hostlib.rs` and `rustfmt`-clean
   (when `rustfmt` is present), and `rust/examples/host` is built
   against the archive and run; its output must end in `agree` (§10).

The fixtures: `tests/ffi/demo/` — 010 add, 020 float bits, 030 string
borrow, 040 owned bytes, 050 fallible, 060 opaque handle, 070 effect
transitive, 080 param named cell, 090 option, 100 result opaque, 110
narrow ints, 120 bytes param, 130 callbacks, 140 vec, 200/210/220
differential int/float/string
(Axiom and Rust compute the same answer), 300 arity sweep (arity 0 is
the one distinct emitter path), 310 ABI version, 400 ARC retain, 410
foreign not walked, 420 null foreign; `tests/ffi/nostd/010-fnv1a.ax`;
`tests/ffi/probe-ungrounded/*.axbad`. The Rust side has its own, run in
CI beside this gate as `cargo test --workspace --exclude axiom-host`
(the host example is excluded because it links an archive this gate
builds, not cargo): the classifier's unit tests, the `trybuild` suite
(one pass file that runs every accepted shape, 20 fail snapshots), and
`axiom-bindgen`'s snapshot tests — `tests/fixtures/nested` is the
snapshot of every wrapper kind and `collision`, `unmarked`,
`unrecorded`, `unrecorded_vec` and `vec_opaque` are the five refusals,
plus demo/nostd freshness, CLI behaviour, and `axiom fmt --check` on the
output when a compiler is reachable.

`scripts/check-freestanding.sh` is **kept**, unchanged: a program with
no `extern` still has to answer the strict version.

---

## 15. `no_std` mode

The mode to reach for when the crate can live in `core` + `alloc`:

```toml
[dependencies]
axiom-ffi = { path = "...", default-features = false, features = ["nostd-runtime"] }
[profile.release]
panic = "abort"
```

and `#![no_std]` with `extern crate alloc;` in the crate
(`rust/examples/nostd/src/lib.rs` is under fifty lines). The `nostd-runtime`
feature (`rust/axiom-ffi/src/nostd_runtime.rs`) supplies what such a
crate otherwise pastes by hand: a `GlobalAlloc` over `axiom_alloc`, the
panic handler (message to fd 2, exit 73), `rust_eh_personality` and
`_Unwind_Resume` (the precompiled sysroot `alloc` rlib references them
even under `panic = "abort"` — the profile governs your crates, not the
sysroot's), the six memory intrinsics (`memcpy`, `memmove`, `memset`,
`memcmp`, `bzero`, `strlen`) LLVM assumes exist, and raw `write`/`exit`
syscalls for the four Darwin and Linux targets (there is no FFI leg
for FreeBSD, and windows-x86_64 has no syscall to number: its runtime
calls kernel32), numbered as `codegen.ax`'s own trap tables number
them. Combining the feature with
`std` is a `compile_error!`.

Rust's allocations then land **inside Axiom's arena**, counted by the
high-water mark and reclaimed by a reset along with everything else;
`dealloc` is a no-op, which is the one constraint to know about
(`ffiFreeBytes` frees nothing in this mode, and a long-lived process
that churns Rust allocations should size its resets accordingly).
Measured: the linked executable imports nothing, the same answer a
program with no `extern` gives.

The two modes **cannot share a cargo workspace** — feature unification
would enable `axiom-ffi/std` for the `no_std` member and its
`#[panic_handler]` would collide with std's `panic_impl` — so
`rust/examples/nostd` is its own workspace and the gate builds it by
`--manifest-path`.

---

## 16. Not supported

Stated plainly, with the reason, so nobody builds on a sentence the
compiler disagrees with. Nothing here is a refusal by taste; each
names the fact in the way.

- **A `String` leaf in a callback, and an arrow as a result.** A
  callback crosses as the closure record, called through its code
  word with words in and a word out (§7). A `String` argument or
  result would carry a share the Rust side has no wrapper to release;
  and Rust cannot *build* an Axiom closure record, because only the
  emitter writes block headers (C4).
- **`u128`/`i128`** — two words; the message says to split into two
  `u64`s. **`&mut [T]` for a `T` narrower than a word** — a converted
  copy could not be written back as the same words; take `&[T]` and
  return a `Vec<T>`. **`Vec<Vec<String>>`, `Vec<Vec<Record>>`** — one
  level of word scalars; flatten or hold in an `#[axiom_opaque]`
  type. **`Box`/`Rc`/`Arc` across the boundary** — an
  `#[axiom_opaque]` type already *is* the box, with a destructor the
  runtime runs (§6).
- **A `pub fn` the Rust binding names in its trailing comment** (§10):
  one over a type variable, a tuple, an arrow, or a `[T]` list type.
  The archive exports it all the same; call it by hand.
- **Panics unwinding into Axiom.** A panic aborts the process (C7); no
  status reports one.
- **32-bit targets.** A word is 64 bits, `usize`/`isize` are
  range-checked against it, and the only targets are the four Axiom
  emits for (darwin/linux × aarch64/x86_64).
- **A distinct `FFI` effect**, a per-item `pub`, a second extern clause,
  any manifest or lockfile. The library string and `(symbol "...")` are
  the whole surface.
- **Threads from Rust.** A Rust crate that spawns a thread and touches an
  Axiom value from it is outside the model. The RESTRICTION is unchanged;
  its reason is not, and the old reason — "Axiom has no threads" — stopped
  being true on 2026-09-03, when `parallel` shipped with a `--threads`
  lowering that names the platform's `pthread_create`
  (`self_host/codegen.ax`, `emitParThread`).

  What actually holds is narrower and stronger. The emitted runtime's
  `axiom_retain` and `axiom_release` are a plain load-add-store, not an
  `atomicrmw`, so two threads touching one block's count race and lose
  increments. Axiom's own thread lowering survives that by giving each
  thread its own arena — the eight runtime globals become
  `thread_local(localexec)`, so a child's first allocation maps a chunk of
  its own — and by letting only a machine WORD cross a join. Neither
  protection extends to a Rust thread: it shares the address space, holds
  whatever handle you passed it, and nothing makes its retain atomic.

  So the rule for a binding is: an Axiom value may be touched only from
  the thread that called into Rust, for the duration of that call. That is
  what "the lifetime is the call" already says about every borrowed view
  here; this is the same sentence about threads.

---

## 17. History

The FFI was designed on paper first and the paper outran the tree. The
record of that month — `docs/ffi-design/00-drafts-2026-08.md`, six
drafts concatenated, 5,014 lines — was kept in the tree under a banner
saying which of its decisions shipped, and then deleted: a document
whose banner has to warn a reader that most of what follows describes
behaviour that does not exist is not documentation, and git holds it.
Read it with `git show 3a83f19:docs/ffi-design/00-drafts-2026-08.md`.

What survived from it is here: the measured tiers, the three facts that
shaped the design, and the out-cell protocol. What did not — `(pub
export axiom ...)` and every Rust-to-Axiom direction, `ffi.manifest.json`,
`ffi.lock`, `--ffi`, `--staticlib`, `__axiom_abi_guard`, a distinct
`FFI` effect, `(opaque T (drop f))` with AX3037–AX3046, `Slice` and
`Outcome` as types, `axiom_rt_init` — is named here so nobody has to
read 5,014 lines to find out.

The surface this document describes was built in four commits —
`3a83f19`, `c560b50`, `3b52c05`, `8b3a39f` — each of whose messages says
what it closed. The fixtures are the durable record:
`tests/diagnostics/700`–`702` for the extern discipline,
`tests/ffi/demo/080`–`184` for every shape that crosses,
`tests/ffi/probe-ungrounded/030`–`050` for grounding and shape checking,
and `tests/ffi/host/` with `rust/examples/host` for the host direction.
