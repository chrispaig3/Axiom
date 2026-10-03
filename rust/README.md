# `rust/` — the Axiom ⇄ Rust FFI

This directory is the Rust side of Axiom's foreign function interface
(FFI): the crates a Rust library uses to talk to Axiom, the binding
generator, and examples in both directions.

You don't need cargo to build the Axiom compiler.
`scripts/bootstrap-from-seed.sh` goes from the committed
`bootstrap/*.ll` through `llc` and `cc`, with no Rust toolchain
anywhere. You need cargo only to run `scripts/check-ffi.sh` and to build
a crate your program binds. On a checkout with no cargo, that check is
skipped rather than failed.

The contract is [`docs/ffi.md`](../docs/ffi.md): the `extern` grammar,
the closed type table, the protocols, handles, callbacks, `Vec`s and
records, the host direction, the diagnostics and the gate. Each claim
there names the source or fixture that shows it. This page is the
crate-side view: what lives in which crate, and how to regenerate the
checked-in bindings. It adds no rules of its own.

## Layout

| Crate | What it is |
|---|---|
| `axiom-abi` | `#![no_std]`. The value layouts (`AxStr`, `AxVec` with its mutable view, the out-cell), the callback types `AxFn1..3`, the `AxRecord` trait and the retain/release protocol. The only crate that knows Axiom's representation. Both directions share it. |
| `axiom-ffi-classify` | The single type table, attribute grammar, naming rule and signature-descriptor derivation. The macro and bindgen both use it, so their two passes over an annotation can't drift apart. The table is closed: every accepted type is listed, and anything else is refused with the list. Both callers enter through the `_with` forms, which carry the registry that says what a bare named type is. |
| `axiom-ffi` | The facade your crate depends on. `std` by default. The `nostd-runtime` feature supplies the allocator, panic handler and memory intrinsics a `no_std` crate needs, and `host` supplies helpers for the other direction. Defines `axffi_free_bytes`, `axffi_free_words`, `axffi_free_str_list`, `axffi_free_word_lists` and `axffi_abi_version` (ABI 3). |
| `axiom-ffi-macros` | `#[axiom_export]` generates the `#[no_mangle] extern "C"` shim and its `__sig_` descriptor. `#[axiom_opaque]` marks a handle type and generates its `axffi_<t>_drop` / `axffi_<t>_drop_fn` pair. `#[axiom_record]` marks a struct that crosses as its fields, and derives `AxRecord`. UI-tested with `trybuild`. |
| `axiom-bindgen` | Reads the Rust source and emits the Axiom binding module: the `extern` block, one `data T (T Handle)` per opaque type, one `data T (T Int Float ..)` per record plus its `Vec` loops, and `Result`/`Option`/`String`/record wrappers over `stdlib/Ffi.ax`. It reads source, like `cbindgen`, because a life-before-main registry doesn't survive `no_std`. Its output passes `axiom fmt --check`. |
| `examples/demo` | `std`. Scalars (`char` and `u64` included), narrow ints, strings, bytes, `Result`, `Option` and their nesting, opaque handles, callbacks, `Vec`s over every word scalar and over records, nested `Vec`s, `&[&str]`, `&mut [i64]`, a record. |
| `examples/nostd` | `no_std` + `alloc` over `axiom_alloc` via the `nostd-runtime` feature. Links with `nm -u` == 0. It is its own workspace, because feature unification would give it `std`'s panic handler. |
| `examples/leaky` | The negative probe. It uses `std::env`, which pulls `getenv` into the link, and its `axiom-allow.txt` leaves `getenv` out. `check-ffi.sh` requires the allowlist check to fail on it. If it ever passes, the check has stopped working. |
| `examples/host` | The other direction: a binary that links an archive `axiom build --emit-staticlib` wrote from `tests/ffi/host/hostlib.ax`, and calls every `pub fn` its binding carries. It is a workspace member but not a default member, because it needs the archive named by `$AXIOM_HOST_ARCHIVE_DIR`. A bare `cargo test` at the root leaves it out. |

## Where each thing is written down

Each topic has one home in `docs/ffi.md`, so there is only ever one
version of the type table.

| Question | `docs/ffi.md` |
|---|---|
| What an `extern` block may say | §3 |
| Which Rust types cross, and as what: the closed table both passes read | §4 |
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

<a id="the-other-direction-in-two-commands"></a>
## Call Axiom from a Rust host

Two commands build an Axiom archive and run a Rust program against it:

```bash
axiom build --input tests/ffi/host/hostlib.ax \
            --output /some/dir/libaxiom_hostlib.a --emit-staticlib
AXIOM_HOST_ARCHIVE_DIR=/some/dir cargo run -p axiom-host
# host: addTwo=42 shout=HELLO halve=2.5 isEven=true nextChar=b answer=42 same=ok structured=ok otherThread=refused agree
```

Every `pub fn` in the archive's entry file becomes a C symbol under its
own name. `examples/host` calls the twenty-three the binding carries.
The twenty-fourth, `identity`, is `(-> a a)`, so the binding names it
in a trailing comment instead. The example round-trips the structured
functions ten thousand times to show the shares balance, checks that a
second thread can't claim the runtime, and prints the line above.

`src/hostlib.rs` is the binding `--emit-rust-binding` generated. It is
checked in, and `check-ffi.sh` diffs it against a fresh generation. It
uses the facade's `host` feature:

- `AxRuntime::claim` gives the one thread allowed to touch the runtime
  its token.
- `AxString::from_str(rt, ..)` builds an argument through the archive's
  own `Str$strAlloc`.
- `AxString::from_owned` adopts a result.

See §10 of `docs/ffi.md` for the full contract.

<a id="regenerating-bindings"></a>
## Regenerate the bindings

```bash
cargo run -p axiom-bindgen -- \
  --src examples/demo/src --lib axiom_demo --module Demo \
  -o examples/demo/axiom/Demo.ax
cargo run -p axiom-bindgen -- --src examples/demo/src --lib axiom_demo \
  --check examples/demo/axiom/Demo.ax      # exit 1 when stale (--quiet: status only)
```

`--lib` is the archive stem (`libaxiom_demo.a`) and the string the
`extern` block carries. `--module` must match the output file's stem,
because an Axiom module is named by its file. `--help` lists the other
options.

The generated `.ax` files are committed, so `axiom check` and
`axiom fmt` work on a checkout with no cargo. `check-ffi.sh` regenerates
and diffs them, as `check-fmt-selfhost.sh` does for its corpus golden.
`cargo test -p axiom-bindgen` does the same, and also checks the
`tests/fixtures/nested` snapshot (`UPDATE_SNAPSHOTS=1` rewrites it) and
five fixtures that must be refused: `collision`, `unmarked`,
`unrecorded`, `unrecorded_vec` and `vec_opaque`.
