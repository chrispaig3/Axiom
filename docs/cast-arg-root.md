# Cast at argument root — design note (QA P0 §3 F7/F19)

Status: defect pinned by `scripts/check-cast-arg-root.sh`, not yet fixed.
Target: Axiom 0.7.5, compiler `./.axiom-bin/axiom`.

## What happens

An argument whose root is a `cast` classifies evidence 0 outright:

- `self_host/typecheck.ax:1314-1316` (`evStampFill`): "the cast launders
  a word past the checker, and evidence must not trust it".
- `self_host/codegen.ax:16739-16741`: a missing/foreign stamp answers 0
  ("the same conservative direction `evStampOk` takes everywhere else,
  and the one that leaks rather than frees early").

Consequence (`docs/memory-model.md:1858-1879`, MM-VAL-22 table): the
temporary's release is not emitted. The direction is a leak, never an
early free.

## Reproduction

```bash
axiom --diagnostic-format=ai check cast3.ax   # OK
axiom --diagnostic-format=ai check cast4.ax   # OK
axiom --diagnostic-format=ai emit-llvm cast3.ax -o cast3.ll
axiom --diagnostic-format=ai emit-llvm cast4.ax -o cast4.ll
rg -c 'call void @axiom_release' cast3.ll cast4.ll
# cast3.ll:1  cast4.ll:0  (measured 2026-09-19, darwin-aarch64)
```

`cast3.ax` stores `(strDup "hi")`; `cast4.ax` stores
`(cast String (strDup "hi"))`. Both check `OK`; the cast version emits
one fewer release.

## Why the fix is a migration, not a one-line change

Two candidate one-liners were considered and rejected:

1. Emit unconditional retain+release on evidence 0. This taxes every
   integer `memSetWord` (the shape the 0-answer exists to keep free)
   and hides the laundering instead of removing it.
2. Refuse arg-root casts outright. This needs a new diagnostic code, an
   `explain.ax` entry, `.axdl`/`.human`/`.json` goldens, and a reseed -
   a language change, not a gate change.

The real fix is MM-VAL-23: casts belong at a RETURN under an honest
declared type (the `mapGet` -> `Int` + `mapGetStr` precedent). The
1,223 AX3040 sites migrate that way; `scripts/check-cast-arg-root.sh`
ratchets the user-level `(cast ` census (baseline 326, 2026-09-19,
`stdlib/` + `tests/` + `examples/`, `self_host/` plumbing excluded) so
the hole cannot widen silently while the migration runs.

## When to delete this note

When the probe's release counts become equal because releases are
emitted from honest return-position types - not because codegen was
taught to retain on evidence 0 - delete this note, delete the gate's
section 2, and keep the census ratchet until the migration completes.
