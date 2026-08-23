# `rust/` — the Axiom ⇄ Rust FFI

**Cargo is not required to build the Axiom compiler.**
`scripts/bootstrap-from-seed.sh` still goes from the committed
`bootstrap/*.ll` through `llc` and `cc` with no Rust toolchain anywhere.
Cargo is required only to run `scripts/check-ffi.sh` and to build a crate
a program actually binds. A checkout with no cargo skips that gate rather
than failing it.

The contract is [`docs/ffi.md`](../docs/ffi.md): the `extern` grammar,
the closed type table, the protocols, handles, callbacks, `Vec`s and
records, the host direction, the diagnostics and the gate, each claim
naming the source or fixture that shows it. This file is the crate-side
view — what lives in which crate, and how the checked-in bindings are
regenerated — and states nothing the contract does not.

## Layout

| Crate | What it is |
|---|---|
| `axiom-abi` | `#![no_std]`. The value layouts (`AxStr`, `AxVec` with its mutable view, the out-cell), the callback types `AxFn1..3`, the `AxRecord` trait and the retain/release protocol. The only place that knows Axiom's representation, shared by both directions. |
| `axiom-ffi-classify` | The ONE type table, attribute grammar, naming rule and signature-descriptor derivation, shared by the macro and bindgen so the two passes over an annotation cannot drift. Closed: every accepted type is enumerated, anything else is refused with the list. Both callers enter through the `_with` forms, which carry the registry that says what a bare named type is. |
| `axiom-ffi` | The facade a crate author depends on. `std` by default; `nostd-runtime` supplies the allocator, panic handler and memory intrinsics a `no_std` crate needs; `host` supplies the other direction's helpers. Defines `axffi_free_bytes`, `axffi_free_words`, `axffi_free_str_list`, `axffi_free_word_lists` and `axffi_abi_version` (ABI 2). |
| `axiom-ffi-macros` | `#[axiom_export]` — generates the `#[no_mangle] extern "C"` shim and its `__sig_` descriptor; `#[axiom_opaque]` — marks a handle type and generates its `axffi_<t>_drop` / `axffi_<t>_drop_fn` pair; `#[axiom_record]` — marks a struct that crosses as its fields and derives `AxRecord`. UI-tested with `trybuild`. |
| `axiom-bindgen` | Reads the Rust source and emits the Axiom binding module (`extern` block, one `data T (T Handle)` per opaque type, one `data T (T Int Float ..)` per record plus its `Vec` loops, `Result`/`Option`/`String`/record wrappers over `stdlib/Ffi.ax`). Source-based, like `cbindgen`, because a life-before-main registry does not survive `no_std`. Output is `axiom fmt --check` clean. |
| `examples/demo` | `std`. Scalars (`char` and `u64` included), narrow ints, strings, bytes, `Result`, `Option` and their nesting, opaque handles, callbacks, `Vec`s over every word scalar and over records, nested `Vec`s, `&[&str]`, `&mut [i64]`, a record. |
| `examples/nostd` | `no_std` + `alloc` over `axiom_alloc` via the `nostd-runtime` feature. Links with `nm -u` == 0. Its own workspace, because feature unification would give it `std`'s panic handler. |
| `examples/leaky` | The negative probe: it reaches for `std::env`, which drags `getenv` into the link, and its `axiom-allow.txt` deliberately omits it. `check-ffi.sh` requires the allowlist check to FAIL on it; if it ever passes, the gate has stopped checking. |
| `examples/host` | The OTHER direction: a binary that links an archive `axiom build --emit-staticlib` wrote from `tests/ffi/host/hostlib.ax` and calls every `pub fn` of it. A member but not a DEFAULT member (it needs the archive, named by `$AXIOM_HOST_ARCHIVE_DIR`), so a bare `cargo test` at the root leaves it out. |

## Where each thing is written down

One document owns each of these, so a reader cannot meet two versions
of the type table.

| Question | `docs/ffi.md` |
|---|---|
| What an `extern` block may say | §3 |
| Which Rust types cross, and as what — the closed table both passes read | §4 |
| Scalars, the out-cell, `Result`/`Option` | §5 |
| Opaque handles and their destructors | §6 |
| Callbacks (`AxFn1..3`) | §7 |
| `Vec`s, slices and records | §8 |
| The signature descriptor and `AX4005` | §9 |
| An Axiom archive a Rust host links | §10 |
| `--crate`, and the bindgen/cargo runs the driver makes | §12 |
| The gate, the allowlists and the tiers measured (`nm -u` 0 / 0 / 188, 18 of them on `check-freestanding.sh`'s 47-name list) | §14 |
| `no_std` mode | §15 |
| What is not supported, and why | §16 |

## The other direction, in two commands

```sh
axiom build --input tests/ffi/host/hostlib.ax \
            --output /some/dir/libaxiom_hostlib.a --emit-staticlib
AXIOM_HOST_ARCHIVE_DIR=/some/dir cargo run -p axiom-host
# host: addTwo=42 shout=HELLO halve=2.5 isEven=true nextChar=b answer=42 same=ok structured=ok agree
```

Every `pub fn` of the archive's entry file is a C symbol under its own
name. `examples/host` calls the twenty the binding carries — the
twenty-first, `identity`, is `(-> a a)` and the binding names it in a
trailing comment instead — round-trips the structured ones ten thousand
times to show the shares balance, and prints the line above; `src/hostlib.rs` is the binding
`--emit-rust-binding` generated, checked in and diffed against a fresh
generation by `check-ffi.sh`. The facade's `host` feature is what that
binding uses: `AxString::from_str` builds an argument through the
archive's own `Str$strAlloc`, and `AxString::from_owned` adopts a
result. See [`docs/ffi.md`](../docs/ffi.md) §10.

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
diffs them, the same shape as `check-fmt-selfhost.sh`'s corpus golden, and
`cargo test -p axiom-bindgen` does the same plus the
`tests/fixtures/nested` snapshot (`UPDATE_SNAPSHOTS=1` rewrites it) and
five fixtures that must be refused: `collision`, `unmarked`,
`unrecorded`, `unrecorded_vec`, `vec_opaque`.
