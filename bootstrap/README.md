# The bootstrap seed

The Axiom compiler is written in Axiom. These six files are how a
clean checkout builds it without already having it.

```
axiom-darwin-aarch64.ll   the compiler, as LLVM IR, one file per target
axiom-darwin-x86_64.ll
axiom-linux-aarch64.ll
axiom-linux-x86_64.ll
axiom-freebsd-x86_64.ll
axiom-freebsd-aarch64.ll
SHA256SUMS                what each of them should hash to
STAMP                     the hash of the source they were generated from
CHAIN                     every seed ever committed, and what reproduces it
lineage/                  the commit list and the one patch a CHAIN row names
```

The two FreeBSD seeds (2026-08-29) are emitted, hashed, regenerated
and assembled exactly as the other four are, and have never been
executed: no runner for FreeBSD exists in this repository yet. A seed
is not evidence that its target runs - `darwin-x86_64`'s has sat here
under the same gates since the beginning and ships no artifact for the
same reason.

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
diff; `git` delta-compresses the six files against each other well,
because they are one program compiled for six targets and differ only
in the target triple, the syscall instruction and the syscall numbers;
and the same `llc` invocation the project already relies on turns it
into whatever the host needs.

Every one of those sizes moves with every reseed, so measure them
rather than read them here:

```bash
du -sh bootstrap                       # all six, plus SHA256SUMS and STAMP
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
last wrote the six `.ll` files, and since 2026-08-25 that is asserted by
regenerating it (`scripts/check-seed-provenance.sh`). The lag is a lag
in TIME, not a gap in provenance.

## What this does and does not prove

`SHA256SUMS` is a corruption check, not a trust check: a hash and a
file committed together move together. It exists so that a damaged
seed is reported here, by name, instead of as a link error three steps
downstream.

**The trust check is `scripts/check-seed-provenance.sh`**, added
2026-08-25. It regenerates all six of these files from the source at
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

## The lineage

`CHAIN` is one row per seed ever committed, in history order: the
commit that wrote it, the commit it reproduces from, how, which stage
matched, and the measured time. Its first row is not an Axiom seed: the
Rust compiler this repository deleted on 2026-08-08 (`430a138`) is
still in the history at `bb730db`, still builds with `cargo`, and
compiles the first seed commit's `self_host/` into a stage1 whose
emission of that tree is byte-identical to the first seed. Every row
after it is a seed reproduced from the seed before it - the previous
seed built with `llc` and `cc` compiles the next seed's tree, and the
emission or its own re-emission equals the next seed byte for byte -
by the method the row names (`seed`, a `mixed-tree` bridge, a `skip`
over an orphan, a `walk` over every source commit between two seeds;
the file's header defines each). Every row was replayed on
2026-08-29 before it was written, and the replay is what
`scripts/check-seed-lineage.sh` repeats.

**The gap, by name.** Three committed seeds have no row, because
nothing in the history reproduces them: `1c682ef` and `24bdf29`
(2026-08-15) and `79c8ebc` (2026-08-29) were each generated by a
compiler built from a tree that was never committed - `reseed.sh`
generated with whatever `$AXIOM` named - and are not their own tree's
emission. They are declared `orphan` in `CHAIN` and bypassed: `93a74e5`
reproduces from `74a0680` by a walk over the 63 source commits between
them with two recorded bridges (`lineage/`), and `991e8bd` reproduces
from `c98924c` directly, over `79c8ebc`. An orphan is not evidence of
tampering; each is explained by the line in `reseed.sh` that built the
generator from an unrecorded compiler. But none can sit on a trusted
path, and this paragraph is where that is said.

**What the certification measured.** The plain walk over the 114
source commits from `74a0680` to `8d266e8` - each tree compiled by the
compiler built from the one before, no bridges - was run first and
fails at its seventh step: the compiler built from `1c682ef`'s tree by
its predecessor SIGSEGVs on any input, because that commit widened the
`Str` header and the old compiler emits the new stdlib's literals in
the old layout. That is the finding the bridges answer. The walk the
row records takes a mixed tree there (`self_host@1c682ef` over the
previous commit's `stdlib`) and, at `24bdf29`, where `__retainref` was
defined and used in one commit, a seven-site patch that removes the
uses in a copy so the previous compiler can build an intermediate that
knows the primitive; the gate runs the plain step first at both and
requires it to fail. The walk measures the two orphans as it passes -
the compiler each bridge builds re-emits its own tree to a fixpoint 67
lines (`1c682ef`) and 1,282 lines (`24bdf29`) from what was committed -
and ends at `93a74e5` byte-identical (63 steps, 494 s). `79c8ebc`'s
tree reaches a fixpoint from `c98924c` 87,624 lines from its seed. The
first link, `60445dc -> 3b6d485`, cannot replay seed-to-seed (the
commit changed which names leave a module); the mixed tree closes it
and a 53-commit walk closes it independently (735 s, byte-identical).
And reproduction at *stage2* is a property of the tree, not of the
predecessor - any working compiler reaches the tree's own fixpoint, so
a nearby seed reproduces a stage2 row as well as the named one does; a
*stage1* row is the stronger statement, the previous seed's direct
emission, and every reseed generated from the committed seed is one.

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

Re-running `reseed.sh` against an unchanged tree leaves all six `.ll`
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

A seed may also land in a commit of its own, after the source change
it answers to rather than with it - the FreeBSD seeds did, because
only a compiler that already knows a target can emit that target's
seed. Such a commit's parent is the same source tree and hashes the
same, and the provenance gate compares STAMP against the nearest
ancestor whose sources moved rather than against the parent.
