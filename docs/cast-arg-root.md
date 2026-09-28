# Cast at argument root — design note (QA P0 §3 F7/F19)

Status: defect pinned by `scripts/check-cast-arg-root.sh`, not yet
fixed. Target: Axiom 0.7.5, compiler `./.axiom-bin/axiom`.

When a call argument's root is a `cast`, the compiler drops that
temporary's release: a leak, never an early free.

## What happens

An argument whose root is a `cast` gets evidence 0 outright:

- `evStampFill` in `self_host/typecheck.ax`: "the cast launders a word
  past the checker, and evidence must not trust it".
- `emitPrimRetainRef` in `self_host/codegen.ax`: a missing or foreign
  stamp answers 0, "the same conservative direction `evStampOk` takes
  everywhere else, and the one that leaks rather than frees early".

So, as the MM-VAL-22 table in `docs/memory-model.md` sets out, the
temporary's release isn't emitted.

## Reproduction

```bash
axiom --diagnostic-format=ai check cast3.ax   # OK
axiom --diagnostic-format=ai check cast4.ax   # OK
axiom --diagnostic-format=ai emit-llvm cast3.ax -o cast3.ll
axiom --diagnostic-format=ai emit-llvm cast4.ax -o cast4.ll
rg -c 'call void @axiom_release' cast3.ll cast4.ll
# cast3.ll:1  cast4.ll:0  (darwin-aarch64)
```

`cast3.ax` stores `(strDup "hi")`, and `cast4.ax` stores
`(cast String (strDup "hi"))`. Both check `OK`, but the cast version
emits one fewer release.

<a id="why-the-fix-is-a-migration-not-a-one-line-change"></a>
## Why the fix is a migration

We considered and rejected two one-line fixes:

1. Emit an unconditional retain and release on evidence 0. This taxes
   every integer `memSetWord`, the shape the 0 answer exists to keep
   free. It also hides the laundering instead of removing it.
2. Refuse casts at the argument root outright. This needs a new
   diagnostic code, an `explain.ax` entry, `.axdl`, `.human` and
   `.json` goldens, and a reseed. That makes it a language change, not
   a gate change.

The real fix is MM-VAL-23: casts belong at a return, under a declared
type that tells the truth about the value. `mapGet` returning `Int`,
alongside `mapGetStr`, is the precedent. The 1,223 AX3040 sites migrate that way.

While the migration runs, `scripts/check-cast-arg-root.sh` ratchets
the census of user-level `(cast ` uses, so the hole can't widen
unnoticed. The census covers `stdlib/`, `tests/` and `examples/`, with
a baseline of 337. The plumbing in `self_host/` is excluded.

## When to delete this note

Delete this note when the probe's release counts become equal because
releases are emitted from truthful return-position types. Equal counts
from teaching codegen to retain on evidence 0 don't count. At that
point, also delete section 2 of the gate, and keep the census ratchet
until the migration completes.
