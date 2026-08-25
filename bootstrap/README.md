# The bootstrap seed

The Axiom compiler is written in Axiom. These four files are how a
clean checkout builds it without already having it.

```
axiom-darwin-aarch64.ll   the compiler, as LLVM IR, one file per target
axiom-darwin-x86_64.ll
axiom-linux-aarch64.ll
axiom-linux-x86_64.ll
SHA256SUMS                what each of them should hash to
STAMP                     the hash of the source they were generated from
```

`scripts/bootstrap-from-seed.sh` picks the file matching the host, runs
`llc` and `cc` over it to get a `seed` compiler, has that seed compile
`self_host/` into `stage1`, and then runs the ordinary ladder
`stage1 -> stage2 -> stage3`, requiring `stage2` and `stage3` to be
byte-identical. It needs `llc` and a C compiler on `PATH` and nothing
else. Not `cargo`, not `rustc`. With `--install DIR` it copies `stage3`
— the compiler that came out of the fixpoint, not the seed and not the
first thing built from it — to `DIR/axiom`, which is where every other
gate looks for one.

## Why the IR and not a binary

A binary would in fact be *smaller* than the IR that produces it. It is
still the wrong artifact: it is opaque, so nobody can review what they
are about to trust, and it would have to be rebuilt for every libc and
linker anyone might have. The IR is text, so it is reviewable in a
diff; `git` delta-compresses the four files against each other well,
because they are one program compiled for four targets and differ only
in the target triple, the syscall instruction and the syscall numbers;
and the same `llc` invocation the project already relies on turns it
into whatever the host needs.

Every one of those sizes moves with every reseed, so measure them
rather than read them here:

```bash
du -sh bootstrap                       # all four, plus SHA256SUMS and STAMP
wc -l bootstrap/*.ll                   # lines per target
ls -l .axiom-bin/axiom                 # what one of them turns into
diff bootstrap/axiom-darwin-aarch64.ll \
     bootstrap/axiom-linux-x86_64.ll | grep -c '^[<>]'   # how far apart two are
```

## Why it is allowed to lag the source

The seed is **not** asserted to be the IR of the source next to it, and
`bootstrap-from-seed.sh` does not check that it is. If it were, every
commit touching the compiler would carry the whole seed regenerated in
its diff, and the property that buys — "the seed is exactly this
source" — is not what a fresh clone needs.

What a clone needs is *"the seed can build this source"*, and that is
what the script checks, by building it. A seed that falls behind far
enough to stop compiling `self_host/` fails there, naming the stage
that could not do it, and `scripts/reseed.sh` moves it forward. This is
the same arrangement Go and Rust have with their bootstrap toolchains,
for the same reason.

Measured, so the arrangement is not merely asserted: a seed generated
from the *previous commit's* compiler builds the current tree to a
byte-identical `stage2 == stage3`.

Lagging the tree is not the same as corresponding to nothing, and the
distinction is the whole of the next section. The seed is not the IR of
the source *beside* it; it is the IR of the source at the commit that
last wrote the four `.ll` files, and since 2026-08-25 that is asserted by
regenerating it (`scripts/check-seed-provenance.sh`). The lag is a lag
in TIME, not a gap in provenance.

## What this does and does not prove

`SHA256SUMS` is a corruption check, not a trust check: a hash and a
file committed together move together. It exists so that a damaged
seed is reported here, by name, instead of as a link error three steps
downstream.

**The trust check is `scripts/check-seed-provenance.sh`**, added
2026-08-25. It regenerates all four of these files from the source at
the commit that last wrote THEM - the `.ll` files, not this directory,
which also holds metadata about them - and requires the result to be
byte-identical - so the seed is not an artifact you have to take on
trust, it is a build product of `.ax` files you can read, and the
regeneration is the proof. Until that gate existed nothing in this
repository related the seed to any source in either direction, and the
one file that claimed a provenance fact was wrong: `STAMP` recorded
`git rev-parse HEAD` at the moment `reseed.sh` ran, which is the commit
BEFORE the one that carries the seed, because the tree is dirty by
construction when you reseed. Measured 2026-08-25: it named `ee0e4e1`,
and regenerating from `ee0e4e1` differs from the committed seed by
1,532 lines. It now records a hash of the source bytes instead, which
cannot be wrong at the moment it is written, and the gate resolves the
commit the other way round.

What that still does not answer is Ken Thompson's *Reflections on
Trusting Trust*, and no checked-in artifact can. A tampered seed would
have to compile the whole compiler from source, have its output compile
the compiler again to a byte-identical fixpoint, have that build and
run a working program, AND have the source it claims to come from
regenerate it exactly - but the compiler doing the regenerating is
itself descended from this seed, so a compiler that reproduces a
backdoor in its own output reproduces it here too. Answering that needs
a second implementation to cross-compile against, and this repository
deliberately deleted the one it had (`430a138`, 2026-08-08, 28,082
lines of Rust) with the cost stated in its own commit message.
Everything short of it is answered.

## Regenerating

```bash
AXIOM=<a working compiler> scripts/reseed.sh
scripts/bootstrap-from-seed.sh          # always, before committing
```

`reseed.sh` will not bootstrap a compiler for itself, deliberately: the
routine reason to run it is that bootstrapping from the committed seed
has just failed, so quietly attempting that again here would replace a
clear "the seed is stale" with a confusing one. Name a compiler that
works — the previous commit's `.axiom-bin/axiom` is the usual answer.

Re-running `reseed.sh` against an unchanged tree leaves all four `.ll`
files and `SHA256SUMS` byte-identical, because the compiler is
deterministic. `scripts/check-reproducible.sh` is the gate that holds
it to that: it compiles every case in `tests/stdlib/` twice, in
separate processes, and compares the IR — separate processes because a
per-process hash seed is exactly the kind of nondeterminism that would
otherwise show up first as a seed that moves on its own. If a `.ll`
here moves without the compiler moving, that determinism has broken,
and the bug is the thing to fix rather than the diff to commit.

`STAMP` moves on every run: it records the time as well as the source
hash. Both halves are read - the hash by
`scripts/check-seed-provenance.sh`, which will not regenerate anything
until the commit it found hashes to it.
