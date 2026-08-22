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
| `axiom-abi` | `#![no_std]`. The value layouts (`AxStr`, `AxVec`, the out-cell), the callback types `AxFn1..3` and the retain/release protocol. The only place that knows Axiom's representation, shared by both directions. |
| `axiom-ffi-classify` | The ONE type table, attribute grammar, naming rule and signature-descriptor derivation, shared by the macro and bindgen so the two passes over an annotation cannot drift. Closed: every accepted type is enumerated, anything else is refused with the list. |
| `axiom-ffi` | The facade a crate author depends on. `std` by default; `nostd-runtime` supplies the allocator, panic handler and memory intrinsics a `no_std` crate needs; `host` supplies the other direction's helpers. Defines `axffi_free_bytes`, `axffi_free_words`, `axffi_free_str_list` and `axffi_abi_version` (ABI 2). |
| `axiom-ffi-macros` | `#[axiom_export]` — generates the `#[no_mangle] extern "C"` shim and its `__sig_` descriptor; `#[axiom_opaque]` — marks a handle type and generates its `axffi_<t>_drop` / `axffi_<t>_drop_fn` pair. UI-tested with `trybuild`. |
| `axiom-bindgen` | Reads the Rust source and emits the Axiom binding module (`extern` block, one `data T (T Handle)` per opaque type, `Result`/`Option`/`String` wrappers over `stdlib/Ffi.ax`). Source-based, like `cbindgen`, because a life-before-main registry does not survive `no_std`. Output is `axiom fmt --check` clean. |
| `examples/demo` | `std`. Scalars, narrow ints, strings, bytes, `Result`, `Option`, opaque handles, callbacks, `Vec`s. |
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

Parameters: `i64 i32 i16 i8 u32 u16 u8 usize isize bool f64 f32 &str
&[u8] &[i64] AxFn1 AxFn2 AxFn3 &T &mut T`. Returns: the scalars, plus
`() String Vec<u8> Vec<i64> Vec<String> Option<T> Result<T, E>` and an
owned `T`. `T` must carry `#[axiom_opaque]`; anything else (`u64`,
`char`, `Vec<i32>`, `&[&str]`, a by-value `T`, a returned `AxFn1`) is a
compile error that lists the set. Narrow integers are range-checked at the
boundary, invalid UTF-8 into a `&str` is an abort (or an `Err` from a
`Result` function), and a borrow of a closed handle aborts - Axiom has
no way to receive an error from an infallible call, so the shim refuses
loudly rather than answer wrongly. Aborts print `axiom-ffi: ...` on fd 2
and exit 72, the status Axiom's own runtime traps use.

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

### Signature descriptors

Beside every shim the macro exports a no-op whose NAME is the shim's
shape - `axffi_add__sig_ii_i`, `axffi_shout__sig_si_i`,
`axffi_abi_probe__sig__i` - one tag per word in (`i` word, `f` float
bits, `s` string, `c` callback; the out-cell is an `i`), `_`, one tag
for the word out. The driver derives the same string from the Axiom
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
