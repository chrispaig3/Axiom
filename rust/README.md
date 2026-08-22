# `rust/` — the Axiom ⇄ Rust FFI

**Cargo is not required to build the Axiom compiler.**
`scripts/bootstrap-from-seed.sh` still goes from the committed
`bootstrap/*.ll` through `llc` and `cc` with no Rust toolchain anywhere.
Cargo is required only to run `scripts/check-ffi.sh` and to build a crate
a program actually binds. A checkout with no cargo skips that gate rather
than failing it.

## Layout

| Crate | What it is |
|---|---|
| `axiom-abi` | `#![no_std]`. The value layouts (`AxStr`, `AxVec` with its mutable view, the out-cell), the callback types `AxFn1..3`, the `AxRecord` trait and the retain/release protocol. The only place that knows Axiom's representation, shared by both directions. |
| `axiom-ffi-classify` | The ONE type table, attribute grammar, naming rule and signature-descriptor derivation, shared by the macro and bindgen so the two passes over an annotation cannot drift. Closed: every accepted type is enumerated, anything else is refused with the list. |
| `axiom-ffi` | The facade a crate author depends on. `std` by default; `nostd-runtime` supplies the allocator, panic handler and memory intrinsics a `no_std` crate needs; `host` supplies the other direction's helpers. Defines `axffi_free_bytes`, `axffi_free_words`, `axffi_free_str_list`, `axffi_free_word_lists` and `axffi_abi_version` (ABI 2). |
| `axiom-ffi-macros` | `#[axiom_export]` — generates the `#[no_mangle] extern "C"` shim and its `__sig_` descriptor; `#[axiom_opaque]` — marks a handle type and generates its `axffi_<t>_drop` / `axffi_<t>_drop_fn` pair; `#[axiom_record]` — marks a struct that crosses as its fields and derives `AxRecord`. UI-tested with `trybuild`. |
| `axiom-bindgen` | Reads the Rust source and emits the Axiom binding module (`extern` block, one `data T (T Handle)` per opaque type, one `data T (T Int Float ..)` per record plus its `Vec` loops, `Result`/`Option`/`String`/record wrappers over `stdlib/Ffi.ax`). Source-based, like `cbindgen`, because a life-before-main registry does not survive `no_std`. Output is `axiom fmt --check` clean. |
| `examples/demo` | `std`. Scalars (`char` and `u64` included), narrow ints, strings, bytes, `Result`, `Option` and their nesting, opaque handles, callbacks, `Vec`s over every word scalar and over records, nested `Vec`s, `&[&str]`, `&mut [i64]`, a record. |
| `examples/nostd` | `no_std` + `alloc` over `axiom_alloc` via the `nostd-runtime` feature. Links with `nm -u` == 0. |
| `examples/host` | The OTHER direction: a binary that links an archive `axiom build --emit-staticlib` wrote from `tests/ffi/host/hostlib.ax` and calls its `addTwo` and `shout`. Not a default workspace member (it needs the archive, named by `$AXIOM_HOST_ARCHIVE_DIR`). |

## The two modes, measured

On darwin-aarch64, the same Axiom program:

| build | `nm -u` | forbidden libc names |
|---|---|---|
| no FFI | **0** | 0 |
| FFI → `examples/nostd` | **0** | 0 |
| FFI → `examples/demo` (`std`) | 188 | 18 |

(18 against `check-freestanding.sh`'s current 47-name list; 14 when
first measured, against a shorter one. The 188 are enumerated in
`examples/demo/axiom-allow.txt`.) `no_std` is the mode to reach for: it keeps `MM-FFI-1`'s freestanding
property fully intact while still crossing the boundary. `std` is the
mode that reaches the ecosystem, and `scripts/check-ffi.sh` is what
prices it — each crate's `axiom-allow.txt` enumerates exactly what it may
import, which is `MM-FFI-5`'s fourth requirement.

## Writing an export

```rust
use axiom_ffi::{axiom_export, axiom_opaque};

#[axiom_opaque]                       // Axiom holds it as a Handle; dropped with the last reference
pub struct Counter { n: i64 }

#[axiom_export]
pub fn counter_new(start: i64) -> Counter { Counter { n: start } }

#[axiom_export]
pub fn counter_value(c: &Counter) -> i64 { c.n }

#[axiom_export(utf8 = "lossy")]       // keys: symbol = "...", utf8 = "lossy"
pub fn shout(text: &str) -> String { text.to_uppercase() }

#[axiom_export]
pub fn maybe(n: i64) -> Option<i64> { (n >= 0).then_some(n) }
```

Parameters: `i64 i32 i16 i8 u64 u32 u16 u8 usize isize bool char f64
f32 &str &[u8] &[&str] &[T] &[&[T]] &mut [i64] &mut [f64] &mut [u64]
AxFn1 AxFn2 AxFn3 &T &mut T`, a by-value record and `&[Record]`.
Returns: the scalars, plus `() String Vec<u8> Vec<T> Vec<Vec<T>>
Vec<String> Vec<Record> Option<T> Result<T, E> Result<Option<T>, E>
Option<Result<T, E>>`, an owned `T` and a record. `T` in `&[T]` /
`Vec<T>` / `Vec<Vec<T>>` is a word scalar (`&[u8]` and `Vec<u8>` stay
the byte view of a String); an owned `T` must carry `#[axiom_opaque]`,
a by-value one `#[axiom_record]`; anything else (`u128`,
`Vec<Vec<String>>`, `&[String]`, `&mut [i32]`,
`Result<Option<Option<T>>, E>`, a returned `AxFn1`) is a compile error
that lists the set and says what to do instead. Narrow integers are
range-checked at the boundary (an argument, a `&[T]` element, a record
field), a `char` word must be a Unicode scalar value, invalid UTF-8
into a `&str` or a `&[&str]` element is an abort (or an `Err` from a
`Result` function), and a borrow of a closed handle aborts - Axiom has
no way to receive an error from an infallible call, so the shim
refuses loudly rather than answer wrongly. Aborts print
`axiom-ffi: ...` on fd 2 and exit 72, the status Axiom's own runtime
traps use.

| Rust | Axiom | How it crosses |
|---|---|---|
| `char` | `Char` | the code point in the word; a word that is no Unicode scalar value aborts |
| `u64` / `usize` | `Int` | the word's bits, unsigned, no range check (>= 2^63 reads negative in Axiom) |
| `Vec<Record>` / `&[Record]` | `Int` (a `Vec` of the record `data`) | `n * ARITY` words; the generated module's `__pointFromWords` / `__pointToWords` loops rebuild and flatten |
| `Vec<Vec<T>>` / `&[&[T]]` | `Int` (a `Vec` of `Vec`s) | `(pairs, n)` of word buffers out (`ffiWordListsToVec`, `axffi_free_word_lists`); a `Vec` of `Vec` handles in |
| `&mut [i64]` `&mut [f64]` `&mut [u64]` | `Int` | the `Vec`'s live elements, written in place |
| `Result<Option<T>, E>` | `(Result (Option T) String)` | status 0 `(Ok (Some v))`, 2 `(Ok None)`, 1 `(Err m)` |
| `Option<Result<T, E>>` | `(Option (Result T String))` | status 0 `(Some (Ok v))`, 1 `(Some (Err m))`, 2 `None` |

A `no_std` crate depends on the facade with
`default-features = false, features = ["nostd-runtime"]` and writes
nothing else: see `examples/nostd`.

### Callbacks and vectors

```rust
use axiom_ffi::{axiom_export, AxFn1, AxFn2};

#[axiom_export]
pub fn apply_twice(f: AxFn1, x: i64) -> i64 { f.call(f.call(x)) }   // (-> (-> Int Int) Int Int)

#[axiom_export]
pub fn fold3(f: AxFn2, a: i64, b: i64, c: i64) -> i64 { f.call(f.call(a, b), c) }

#[axiom_export]
pub fn range_vec(n: i64) -> Vec<i64> { (0..n).collect() }           // an Axiom Vec (Int)

#[axiom_export]
pub fn sum_words(xs: &[i64]) -> i64 { xs.iter().sum() }             // reads a Vec handle in place
```

An `AxFn<n>` is the closure record Axiom passes for an argument typed
`(-> Int ...)` of `n` arguments - a lambda or a one-argument top-level
function - and `call` goes through word 0 with the record as the hidden
environment. Every Axiom function value absorbs ONE argument (a
two-parameter lambda is two nested lambdas), so `AxFn2::call` and
`AxFn3::call` apply one argument per step and release the intermediate
links. The record is borrowed for the call; keep one with
`axiom_retain`. A `Vec<i64>` / `Vec<String>` return crosses the out-cell
as `(ptr, len)` / `(pairs, n)` and the generated wrapper builds an Axiom
`Vec` from it (`ffiWordsToVec` / `ffiStrsToVec` in `stdlib/Ffi.ax`) and
frees the Rust side (`axffi_free_words` / `axffi_free_str_list`).

A `Vec<T>` over any other word scalar (`Vec<f64>`, `Vec<bool>`,
`Vec<char>`, `Vec<u16>`, ...) is widened into the same words - an
integer as the word, a bool as 0/1, a char as its code point, a float
as f64 bits - so the Axiom side is the same `Int` handle and reads each
element as what it is: `(cast Float (vecGet v i))`. A `&[T]` parameter
is the `Vec` handle read the other way: `&[i64]`, `&[u64]` and `&[f64]`
in place, every other `T` through a checked temporary (an element out
of range, or a char word that is no scalar value, aborts with its
index). A `&[&str]` parameter is a `Vec` of Strings, each borrowed as
`&str` for the call. A `Vec<Vec<T>>` result is one buffer per row
behind a `(pairs, n)` cell, a `&[&[T]]` parameter a `Vec` of `Vec`
handles; a `&mut [i64]` (`f64`, `u64`) parameter is the `Vec`'s own
elements, written in place.

### Records

```rust
use axiom_ffi::{axiom_export, axiom_record};

#[axiom_record]                       // crosses AS ITS FIELDS, one word each
pub struct Point { pub x: i64, pub y: f64 }

#[axiom_export]
pub fn point_norm2(p: Point) -> f64 { (p.x * p.x) as f64 + p.y * p.y }   // shim: (x, y_bits) -> bits

#[axiom_export]
pub fn point_origin() -> Point { Point { x: 0, y: 0.0 } }                // shim: (out) -> 0
```

A record is a plain struct with named fields, every one a word scalar;
it is never boxed. A parameter is one shim argument per field
(descriptor tag `i`/`f` per field), a result is written into an
out-cell of one word per field (`ffiCellNewN n`), and `Result<Point, E>`
/ `Option<Point>` carry the fields behind the status word. bindgen emits
`(pub data Point (Point Int Float))` and wrappers that destructure
(`(match p ((Point __f0 __f1) (pointNorm2Raw __f0 __f1)))`) and rebuild
(`(Point __w0 (cast Float __w1))`). A `Vec<Point>` result is `n * 2`
words behind a `(ptr, n)` cell, a `&[Point]` parameter a `Vec` of
`Point`s the wrapper flattens; bindgen emits one private loop each
way per record type (`__pointFromWords` over `ffiWordAt`,
`__pointToWords` over `vecGet`), and the shim chunks the words through
`from_words`. A record field may be any word scalar, `char` and `u64`
included.

Because a proc macro sees one item at a time, `#[axiom_record]` and
`#[axiom_opaque]` also declare a companion `macro_rules!` named like the
type, through which `#[axiom_export]` learns what a bare `T` is. It is
re-exported beside the type, so a `use` of the type brings it along;
name the type as you would anywhere (`Point`, `geom::Point`).

### Signature descriptors

Beside every shim the macro exports a no-op whose NAME is the shim's
shape - `axffi_add__sig_ii_i`, `axffi_shout__sig_si_i`,
`axffi_abi_probe__sig__i` - one tag per word in (`i` word, `f` float
bits, `s` string, `c` callback; a record is one tag per field; the
out-cell is an `i`), `_`, one tag for the word out. The driver derives the same string from the Axiom
`extern` item's declared type and refuses a mismatch as AX4005 before
the link. A hand-written `axffi_*` shim has no descriptor and is not
checked.

### The other direction

```sh
axiom build --input tests/ffi/host/hostlib.ax \
            --output /some/dir/libaxiom_hostlib.a --emit-staticlib
AXIOM_HOST_ARCHIVE_DIR=/some/dir cargo run -p axiom-host     # host: addTwo=42 shout=HELLO
```

Every `pub fn` of the archive's entry file is a C symbol under its own
name; the facade's `host` feature gives `AxString::from_str` (an Axiom
String built through the archive's own `Str$strAlloc`) and
`AxString::from_owned` / `read_str` for the answers. See
`examples/host/src/main.rs` for the symbols a host relies on.

## Binding it from Axiom

```sh
cargo build --release                    # the crate: [lib] crate-type = ["staticlib"]
cargo run --release -p axiom-bindgen -- \
  --src path/to/crate/src --lib axiom_mycrate --module MyCrate \
  -o path/to/crate/axiom                 # writes axiom/MyCrate.ax
axiom build --input p.ax --output p --crate path/to/crate && ./p
```

`--crate DIR` puts `DIR/axiom/` on the import path and `DIR/target/release`
(or the workspace's, one or two levels up) on the link search path; the
archive links because the generated `extern` block names it. The program
writes `(import MyCrate)` and calls `add`, `shout`, `counterNew`; a
`Counter` is dropped when its last Axiom reference dies. The full contract
— grammar, type table, protocols, handles, diagnostics, the gate — is
[`docs/ffi.md`](../docs/ffi.md).

## Regenerating bindings

```sh
cargo run -p axiom-bindgen -- \
  --src examples/demo/src --lib axiom_demo --module Demo \
  -o examples/demo/axiom/Demo.ax
cargo run -p axiom-bindgen -- --src examples/demo/src --lib axiom_demo \
  --check examples/demo/axiom/Demo.ax      # exit 1 when stale (--quiet: status only)
```

`--lib` is the archive stem (`libaxiom_demo.a`) and the string the
`extern` block carries; `--module` must match the output file's stem,
because an Axiom module is its file name. `--help` lists the rest.

The `.ax` files are **committed**, because `axiom check` and `axiom fmt`
must work on a checkout with no cargo. `check-ffi.sh` regenerates and
diffs them, the same shape as `check-fmt.sh --check`, and
`cargo test -p axiom-bindgen` does the same plus a snapshot of
`tests/fixtures/nested` (`UPDATE_SNAPSHOTS=1` rewrites it).
