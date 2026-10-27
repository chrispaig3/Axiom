# `axiom-oxide`

Call Rust from Axiom, or call an Axiom archive from Rust. This official
package owns the Rust FFI helpers, binding generators and examples, keeping
them outside the compiler and standard library. `pkg/` is the home of Axiom's
official library and binary packages.

The compiler needs no Rust toolchain. Install these tools only when you bind
Rust code:

```bash
cargo install --path pkg/axiom-oxide
cargo install --path pkg/axiom-oxide/axiom-bindgen
```

## Call Rust from Axiom

Mark Rust functions `#[axiom_export]`, then generate the Axiom module and
build the static archive:

```bash
axiom-oxide prepare --crate pkg/axiom-oxide/examples/demo --release
AXIOM_PATH="$PWD/pkg/axiom-oxide/examples/demo/axiom:$PWD/pkg/axiom-oxide/axiom" \
AXIOM_LINK_SEARCH="$PWD/pkg/axiom-oxide/target/release" \
axiom build /path/to/program.ax
```

The generated `extern` declarations use the compiler's generic native linking.
Use `--link-search` and `--link-lib` when you prefer explicit command-line
arguments. A manifest's `depend` entry adds Axiom modules without running
Cargo or another project's build.

## Call Axiom from Rust

From `pkg/axiom-oxide`, generate record accessors and Rust wrappers, then
build the archive:

```bash
cargo run -p axiom-oxide -- host \
  --input ../../tests/ffi/host/hostlib.ax \
  --rust /some/dir/hostlib.rs \
  --archive /some/dir/libaxiom_hostlib.a
AXIOM_HOST_ARCHIVE_DIR=/some/dir cargo run -p axiom-host
# host: addTwo=42 shout=HELLO halve=2.5 isEven=true nextChar=b answer=42 same=ok structured=ok otherThread=refused agree
```

`host` accepts `--axiom PATH` to select the compiler and `--no-build` to
validate and generate bindings without writing an archive. `--keep-source`
retains the instrumented Axiom input for diagnosis.

## Package layout

| Crate or directory | What it provides |
|---|---|
| `axiom.pkg`, `axiom/Ffi.ax` | The official Axiom library manifest and foreign ownership helpers |
| `src/` | The `axiom-oxide` binary for both preparation and host generation |
| `axiom-abi` | `#![no_std]` value layouts, callbacks and the retain/release protocol |
| `axiom-ffi-classify` | The closed type table, attribute grammar and signature descriptors |
| `axiom-ffi` | The facade, plus `nostd-runtime` and `host` features |
| `axiom-ffi-macros` | `#[axiom_export]`, `#[axiom_opaque]` and `#[axiom_record]` |
| `axiom-bindgen` | Rust source to Axiom wrapper generation |
| `examples/demo` | Scalars, strings, fallible values, handles, callbacks, vectors and records |
| `examples/nostd` | `no_std` and `alloc` over Axiom's allocator, in its own workspace |
| `examples/host` | A Rust binary calling an Axiom archive through generated wrappers |
| `examples/leaky` | The negative probe for the external-symbol allowlist |

The full wire, ownership and safety contract is
[`docs/ffi.md`](../../docs/ffi.md). Its examples use the same commands as this
page. The compiler retains generic `extern` and `--emit-staticlib`; it has no
Cargo or Rust binding generator built in.

## Regenerate and test

Run these commands from `pkg/axiom-oxide`:

```bash
cargo run -p axiom-bindgen -- \
  --src examples/demo/src --lib axiom_demo --module Demo \
  -o examples/demo/axiom/Demo.ax
cargo test --workspace --exclude axiom-host
cargo fmt --all --check
cargo clippy --workspace --exclude axiom-host --all-targets -- -D warnings
```

The generated modules and host binding are checked in. `check-ffi.sh` compares
them with fresh output, runs both directions and checks the allowed symbols.
From the repository root, run `AXIOM="$PWD/.axiom-bin/axiom"
./scripts/check-ffi.sh`.
