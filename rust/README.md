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
| `axiom-abi` | `#![no_std]`. The value layouts and the retain/release protocol. The only place that knows Axiom's representation, shared by both directions. |
| `axiom-ffi` | The facade a crate author depends on. `std` by default, `no_std` by feature. |
| `axiom-ffi-macros` | `#[axiom_export]` — generates the `#[no_mangle] extern "C"` shim. |
| `axiom-bindgen` | Reads the Rust source and emits the Axiom `extern` block. Source-based, like `cbindgen`, because a life-before-main registry does not survive `no_std`. |
| `examples/demo` | `std`. Scalars, strings, `Result`, opaque handles. |
| `examples/nostd` | `no_std` + `alloc` over `axiom_alloc`. Links with `nm -u` == 0. |

## The two modes, measured

On darwin-aarch64, the same Axiom program:

| build | `nm -u` | forbidden libc names |
|---|---|---|
| no FFI | **0** | 0 |
| FFI → `examples/nostd` | **0** | 0 |
| FFI → `examples/demo` (`std`) | 188 | 14 |

`no_std` is the mode to reach for: it keeps `MM-FFI-1`'s freestanding
property fully intact while still crossing the boundary. `std` is the
mode that reaches the ecosystem, and `scripts/check-ffi.sh` is what
prices it — each crate's `axiom-allow.txt` enumerates exactly what it may
import, which is `MM-FFI-5`'s fourth requirement.

## Regenerating bindings

```sh
cargo run -p axiom-bindgen -- \
  --src examples/demo/src --lib axiom_demo --module Demo \
  -o examples/demo/axiom/Demo.ax
```

The `.ax` files are **committed**, because `axiom check` and `axiom fmt`
must work on a checkout with no cargo. `check-ffi.sh` regenerates and
diffs them, the same shape as `check-fmt.sh --check`.
