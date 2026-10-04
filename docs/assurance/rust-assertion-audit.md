# Rust assertion audit, 2026-10-03

The public `Ret::direct_payload` query accepts every return shape.
It answers `Some(payload)` for direct cell returns and `None` for
scalars, opaque handles and status returns. Callers can inspect a
classified return without triggering an assertion.

Tested by `direct_payload_is_total_over_return_shapes` in
`rust/axiom-ffi-classify/src/lib.rs`.

## Scope and result

This audit covers every `unreachable!` in Rust source under `rust/`,
including the committed generated host binding. The public query was
the reachable assertion and is repaired. The remaining assertions
guard private control flow, validated classifier output or unsafe
typed-value contracts. None uses `unreachable_unchecked`.

Reproduce the inventory from the repository root:

```bash
rg -n 'unreachable!|unreachable_unchecked' rust --glob '*.rs'
cargo test --manifest-path rust/Cargo.toml \
  -p axiom-ffi-classify -p axiom-ffi-macros -p axiom-bindgen
```

## Classifier

| Site in `rust/axiom-ffi-classify/src/lib.rs` | Proof or handling |
|---|---|
| `classify_payload`, empty outer wrapper for `Option`/`Result` | Its caller, `classify_return_with`, uses the same `status_wrapper` path classification first. Every recognised wrapper takes the status arm; missing payloads return an error there. Nested wrappers reach payload classification with a nonempty outer name. `malformed_status_wrappers_are_reported_before_payload_dispatch` exercises bare, empty, nested and qualified wrappers |
| `descriptors`, expected `Param::Record` | The test classifies `Point` through its fixed `Table` registry, which defines a record |
| `classify_point`, expected `Param::Record` | The same fixed registry supplies `Point`; the assertion makes a classifier regression fail the test |
| `classify_opaque`, expected `Ret::Opaque` | `Counter` is a bare named return under `NoRecords`, which classifies it as opaque |

The macro and bindgen consumers check the direct-cell return arm before
unwrapping `direct_payload`. These private checks remain assertions;
the public query no longer requires that control-flow invariant.

## Proc macros

These sites are in `rust/axiom-ffi-macros/src/lib.rs`. The private
`expand_shim` receives the result of `classify_signature`, which reports
unsupported shapes before generating a shim.

| Site | Proof or handling |
|---|---|
| `expand_record`, unit field | `classify_record_fields` refuses unit fields before constructing the field list |
| `expand_shim`, receiver | `classify_signature` refuses `FnArg::Receiver` before filling parameters |
| `expand_shim`, scalar unit parameter | `classify_param` refuses a unit parameter |
| `expand_shim`, unit word slice | `classify_param` refuses `&[()]` |
| `expand_shim`, narrow mutable slice | Mutable slices are classified only for `i64`, `u64` and `f64` |
| `expand_shim`, nested unit slice | `classify_param` refuses `&[&[()]]` |
| `expand_shim`, record in the scalar dispatch | The preceding record arm reconstructs its fields and executes `continue` |
| `expand_shim`, scalar or opaque return in the cell dispatch | `needs_cell` is false for exactly those two variants |
| `expand_shim`, cell return in the direct conversion | The complementary `needs_cell` branch admits only scalar and opaque returns |

The rejection tests call both classification and expansion. They cover
receivers, unit parameters, unit slices, nested unit slices, narrow
mutable slices and invalid nested status returns. Unit record fields
have a separate expansion probe.

Tested by `refused_signature_shapes_never_reach_shim_assertions` and
`unit_record_fields_are_reported_before_record_assertions` in
`rust/axiom-ffi-macros/src/lib.rs`.

## Binding generator

These sites are in `rust/axiom-bindgen/src/lib.rs`. `Decl` and its
generation methods are private. The parser populates its parameters
and return from the shared classifier.

| Site | Proof or handling |
|---|---|
| `collection_build`, noncollection payload | Direct collection return arms call it only for Bytes, Words, WordLists, Strs or Records. The status arm first tests `is_collection`, which lists the same variants |
| `collection_free`, noncollection payload | It shares those call sites and the same predicate with `collection_build` |
| `status_ctors`, nonstatus return | Its caller is the explicit Result, Option, ResultOption or OptionResult match arm |
| `Decl::raw_type`, cell return in the direct branch | The branch requires `!needs_cell`, whose variants are Scalar and Opaque |
| `Decl::wrapper_body`, collection in the scalar payload arm | That arm is the `else` of the exhaustive `is_collection` predicate |
| `Decl::wrapper_body`, no alternate status state | Every `status_ctors` branch supplies `none`, `err` or both; none supplies neither |

The nested fixture covers the return families, records, collections
and their optional or fallible wrappers. Malformed exported types
return generator errors; they cannot construct an unchecked `Decl`.

Tested by `rust/axiom-bindgen/tests/snapshot.rs` and
`rust/axiom-ffi-classify/src/lib.rs`.

## Generated host binding

`rust/examples/host/src/hostlib.rs` has one invalid-constructor arm in
each of these decoders:

| Decoder | Valid constructor indices |
|---|---|
| `__from_Option_Int` | 0, 1 |
| `__from_Result_Int_String` | 0, 1 |
| `__from_Pair` | 0 |
| `__from_Shape` | 0, 1, 2 |
| `__from_Named` | 0 |
| `__from_List_Int` | 0, 1 |
| `__from_Option_Pair` | 0, 1 |
| `__from_Tagged` | 0 |

The generator, `rbFromFn` in `self_host/rustbind.ax`, emits every
constructor of the declared type. Each decoder is unsafe: its caller
promises a live, owned value of that type. Safe wrappers decode values
returned by the corresponding typed Axiom export. Raw-word conversion
keeps that safety precondition visible to Rust callers.

An invalid index violates the typed-value contract and raises a Rust
panic. This assertion does not validate an arbitrary pointer: the raw
tag accessor already requires a live value before reading it.
The source binding is generated and must be changed through its generator.

Tested by `tests/ffi/host/hostlib.ax` and `scripts/check-ffi.sh`.

## Limits

This audit establishes why the remaining assertion arms are excluded
by their callers. It does not establish provenance of foreign addresses,
prove every Unsafe vouch or replace the raw FFI safety contracts.
Those obligations remain in the [FFI contract audit](ffi-contract-audit.md).
