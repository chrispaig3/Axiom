# FFI contract audit, 2026-10-03

The reviewed binding path uses generated Rust shims and Axiom wrappers.
Raw wire calls still require live addresses, correct types and exclusive
mutable borrows. Runtime layout checks cannot establish pointer provenance.

## Inventory the vouches

Run this from the repository root:

```bash
axiom --diagnostic-format=ai symbols stdlib/Ffi.ax --calls |
  python3 scripts/lib/unsafe-inventory.py > ffi-boundaries.json
```

Each JSON row names the declaration, its source location, resolved calls
and callers in that program. `trusted` contains an Unsafe obligation.
`precondition` passes the obligation to callers and includes its text.
Choose another entry file to include the wrappers that program imports.

The inventory describes declarations; it does not prove their vouches.
Review each trusted wrapper against its inputs, allocation source,
cleanup paths and any callbacks it invokes.

Tested by `tests/ffi/verify-unsafe-inventory.py`.

## Reviewed routes

| Route | Disposition | Evidence |
|---|---|---|
| An extern is called with forged pointer or length words | The calling declaration needs `effect(unsafe)`. Typed wrappers must establish the raw call's preconditions | `tests/diagnostics/1116-extern-unsafe.ax` |
| Two direct or nested vector inputs overlap a mutable slice | The shim checks overlap before constructing mutable references | `rust/axiom-ffi/tests/contracts.rs` |
| An opaque value is borrowed twice, with one mutable borrow | The shim refuses repeated nonzero addresses before borrowing | `rust/axiom-ffi/tests/contracts.rs` |
| A handle is rewrapped as another Rust type | Generated owners are sealed structs; constructors and fields stay in their binding module | `tests/ffi/probe-sealed/010-forged-owner.axbad` and `tests/ffi/probe-sealed/020-exposed-handle.axbad` |
| A callback mutates a vector or closes an owner while Rust borrows it | The generated wrapper states a caller precondition and propagates Unsafe | `tests/ffi/probe-sealed/030-callback-borrow.axbad` |
| Rust stores a borrowed callback after the call | Callback values carry a borrow lifetime; exported parameters refuse named and static lifetimes | The `AxFn1` compile-fail doctest in `rust/axiom-abi/src/lib.rs` |
| An owner is explicitly closed twice or dropped after close | Close clears the pointer before invoking the destructor; the counted handle then calls nothing | `tests/ffi/demo/060-opaque-handle.ax` |
| A destructor re-enters cleanup | The pointer is cleared before the call | `tests/ffi/demo/430-reentrant-drop.ax` |
| A generated wrapper frees a returned buffer | It copies the payload and returns the same allocation pair once | `tests/ffi/demo/040-owned-bytes.ax` |
| A raw free receives a negative or overflowing length | The free shim checks length, layout and pair-count overflow before reclaiming memory | `rust/axiom-ffi/tests/contracts.rs` |
| A raw free receives a stale address or is called twice | Caller precondition: the pair must still name the original allocation. The layout checks cannot establish this | `rust/axiom-ffi/src/lib.rs`, `axffi_free_bytes` and `axffi_free_words` safety contracts |

The callback precondition covers nested calls too. A callback must preserve
every borrowed vector and owner named by that wrapper until the shim
returns. Copying scalar inputs into Rust storage removes that borrow.
Hand-written shims and unsafe Rust inside exports remain separate review
obligations.

## Records and out-cells

`records<R>` first reads a live vector promised by its unsafe caller.
The word-count check then rejects a partial record before conversion.
Divisibility protects the decoded shape; it cannot validate an address.
Generated wrappers flatten typed records into their own temporary vector.
Rust reconstructs owned record values, so the exported body borrows that
copy rather than the caller's record objects.

An out-cell belongs to one call and has enough words for its return shape.
Generated wrappers allocate it before the call and release it afterwards.
Raw Rust callers must also keep it aligned, writable and disjoint from
arguments. The cell helpers expose these obligations through preconditions.

The [Rust assertion audit](rust-assertion-audit.md) records the
classifier, macro, bindgen and generated-host invariants. Unsupported
source shapes are reported before private generation assertions.

## Remaining review

Panic probes cover scalar returns, fallible out-cells and destructors
in the default, release and host builds. An unwind cannot reach the
Rust caller's catcher across a generated `extern "C"` shim.
The freestanding runtime's panic handler exits with status 73.

Tested by `rust/axiom-ffi/tests/panic_boundary.rs` and
`tests/ffi/nostd/020-panic-boundary.ax`.

The full Unsafe vouch set remains open. Prioritise erased pointer and
heterogeneous vector helpers, hand-written shims, retained raw callback
words and foreign values shared between threads. A trusted wrapper can
still hide an unsatisfied obligation; the inventory makes that reviewable.

See [the FFI guide](../ffi.md) for the wire contract and
[the memory audit](memory-audit.md) for the wider programme obligations.
