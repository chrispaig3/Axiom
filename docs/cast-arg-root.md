# Casts and ownership

```scheme fragment
(strLen (cast String (strDup "hi")))
```

The checker proves that this cast preserves the operand's type. The
temporary therefore has the same cleanup as `(strLen (strDup "hi"))`.
A borrowed string stays borrowed, and an owned string stays owned.

## What happens

`checkCastForm` in `self_host/typecheck.ax` records a type-preserving
cast as `nodeResWord` 3. This proof has three consumers:

- `evStampFill` preserves the argument's reference evidence.
- `valueOwnedRef` follows the operand's ownership through the cast.
- `escapes` follows the operand's lifetime dependencies.

The proof covers a cast's value, including nested casts. Surplus
arguments apply the resulting function and use application evidence.
An unproved reinterpretation keeps conservative evidence 0; scalar
casts take no reference share.

Tested by `scripts/check-cast-arg-root.sh` and
`tests/stdlib/701-cast-ownership.ax`.

<a id="why-the-fix-is-a-migration-not-a-one-line-change"></a>
## Reinterpreting a word

A cast that changes a word into a reference still requires a valid
representation and `effect(unsafe)`. Put that conversion inside a typed
accessor whose precondition says what the word holds. Its callers then
receive the declared type and its reference evidence.

[The memory model](memory-model.md) specifies this boundary as
`MM-VAL-22` and `MM-VAL-23`. The cast census in
`scripts/check-cast-arg-root.sh` records uses in `stdlib/`, `tests/`
and `examples/`; `self_host/` and the fuzzer reproducers are excluded.

## Lifetime guarantees

Checked lexical regions reject stores into older bindings, fields,
containers and callback captures. The compiler also rejects origin
overflow and unconverged lifetime facts. Calls confined to one region
remain valid.

These guarantees cover tracked typed origins. Raw addresses and resets
retain their unsafe preconditions. Reference counting can retain
unreachable cycles, and a checked region reclaims cycles confined to
its extent. See `MM-RGN-3`, `MM-LIFE-3` and `MM-LIFE-4` in
[the memory model](memory-model.md).

Tested by `scripts/check-region-escape.sh`.
