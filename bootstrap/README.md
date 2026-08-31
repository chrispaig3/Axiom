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
and assembled exactly as the other four are. `freebsd-x86_64` has been
EXECUTED since 2026-08-30 - `Tests (freebsd-x86_64)` boots FreeBSD 14.4
in a VM and bootstraps from this very seed - and is a supported target.
`freebsd-aarch64` has not: an aarch64 guest is TCG-emulated on every
runner GitHub offers. A seed
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

What that alone does not answer is Ken Thompson's *Reflections on
Trusting Trust*: the compiler doing the regenerating is itself
descended from this seed, so a compiler that reproduces a backdoor in
its own output reproduces it there too. Answering that needs a
compiler that is NOT descended from any Axiom seed, and this repository
has one in its history: the Rust implementation it deleted on
2026-08-08 (`430a138`, 28,082 lines), whose last commit `bb730db` still
builds with `cargo`. The next section is what that buys.

## The lineage

**`scripts/check-seed-lineage.sh`** (2026-08-29) replays `CHAIN`: one
row per seed ever committed, each naming the seed it reproduces from
and how. The first row is the root and it is not an Axiom seed: the
Rust compiler at `bb730db` compiles the `self_host/` tree of the first
seed commit `60445dc` into a stage1 whose emission of that tree is
byte-identical to the first seed - Wheeler's diverse double-compile,
with the Rust codegen's own IR (93,471 lines) demonstrably not the
seed (61,473). Every row after it is a seed reproduced from the seed
before it: the previous seed is built with `llc` and `cc`, compiles the
next seed's tree, and the emission - or its own re-emission, when the
two compilers differ - must equal the next seed byte for byte. So a
seed on this chain is the honest emission of readable source by a
compiler that is itself on the chain, back to a root anyone can read in
Rust; a backdoor would have to be in that Rust, or in the `.ax` files,
and in no 7 MB of IR. The gate replays every row nightly (`--full`);
on a push that touches `bootstrap/` it replays the rows
`CHAIN.checkpoint` does not certify, and never fewer than the newest
one. Each run refuses one byte flipped in a copy of the seed and a row
re-pointed at another predecessor.

`CHAIN.checkpoint` is what makes the push run cheap without making it
possible to hide a broken link. It names a PREFIX of `CHAIN` and the
sha256 of exactly that prefix - the rows verbatim, their short hashes
resolved to full commits, the git object id of every seed those commits
carry, and the sha256 of every walk list and patch file they name - and
the gate RECOMPUTES that digest from `CHAIN` as it stands on every run
before it skips anything. A covered row that moved by a byte digests
differently, and the checkpoint is then void: the gate replays the
whole chain from the Rust anchor and stays red until the prefix is
blessed again. Editing an old row cannot shrink the work.

It is written only by `AXIOM_BLESS=1 scripts/check-seed-lineage.sh
--full`, over rows that same process replayed from the anchor, and
never as a side effect of a passing run - a gate that writes its own
trust anchor when it passes proves nothing. It never covers the newest
row, so the link a push adds is replayed on that push. And it is a
record rather than a signature: whoever can edit a row can recompute
the digest too, and what the file buys is that they must do it in the
same diff, in front of a reviewer, while the nightly `--full` re-derives
every row from `bb730db` regardless.

**What is answered, and what remains.** Answered: the seed in the tree
descends, by replayable steps, from a compiler that no Axiom seed ever
touched. What remains is the trust base of that replay, and it is
this list and nothing shorter: `git` (the history the rows name),
`llc` and `cc` (and `opt`, optional - they turn every seed on the path
into a running compiler), `cargo` and `rustc` and the 84 crates
`bb730db`'s `Cargo.lock` pins (they build the root), and the 28,082
lines of Rust at `bb730db` - which share an author with `self_host/`,
a weakness of "diverse" in the social sense and not the technical one.
No Axiom binary is called before the comparison, and the gate reads its
own text to assert it. Removing `llc` and `cc` from that list needs a
witness that never assembles anything - an interpreter for the
compiler's subset - and that is a separate track, not this one.

**The gap, by name.** Three committed seeds are not their own tree's
emission - `1c682ef` and `24bdf29` (2026-08-15) and `79c8ebc`
(2026-08-29) - because `reseed.sh` used to generate with whatever
compiler `$AXIOM` named, and those three were generated by compilers
built from trees that were never committed. Nothing in the history
reproduces them; they are declared `orphan` in `CHAIN`, have no row,
and are bypassed: `93a74e5` reproduces from `74a0680` by a walk over
the 63 commits between that touched the sources, each compiled by the
compiler built from the one before, with two recorded bridges where the
plain step yields a compiler that cannot run (a mixed tree at
`1c682ef`, where the `Str` header widened; a seven-site patch at
`24bdf29`, where `__retainref` was defined and used in one commit -
`lineage/` holds both, and the gate requires the plain step to fail
before it takes a bridge); and `991e8bd` reproduces from `c98924c`
directly, over `79c8ebc`. The walk measures the orphans as it passes:
the compiler each bridge builds re-emits its own tree to a fixpoint
67 and 1,282 lines from what was committed, and `79c8ebc`'s tree
reaches a fixpoint from `c98924c` 87,624 lines from its seed. The plain
walk over the same commits - no bridges - was run first and fails at
the seventh step, because the compiler built from `1c682ef`'s tree by
its predecessor SIGSEGVs on any input: that is the finding the bridges
answer. An orphan is not evidence of tampering; each is explained by
the line in `reseed.sh` that has since been removed. But none can sit
on a trusted path, and this paragraph is where that is said.

Two more facts the replay established. The first link, `60445dc ->
3b6d485`, cannot be replayed seed-to-seed (the commit changed which
names leave a module and its own message says the seed could not
survive it); the mixed tree closes it, and a 53-commit walk closes it
independently. And reproduction at *stage2* is a property of the tree,
not of the predecessor: any working compiler reaches the tree's own
fixpoint, so a nearby seed reproduces a stage2 row as well as the named
one does. A *stage1* row is the stronger statement - the previous
seed's direct emission IS the next seed - and every reseed generated
the way `reseed.sh` now generates is one.

## Regenerating

```bash
scripts/reseed.sh                       # from the committed seed, and it writes the CHAIN row
scripts/bootstrap-from-seed.sh          # always, before committing
```

`reseed.sh` builds its generator from the committed seed and nothing
else: the host's seed through `llc` and `cc` compiles this tree, and
the result emits the six files. So the seed it writes is the previous
seed's emission of this tree, or that emission's own re-emission, and
the row it appends to `CHAIN` says which (`stage1` or `stage2`); the
row's first column is `next` until the commit that carries the seed
exists, and the following reseed fills the hash in. When the committed
seed cannot compile the tree - the routine reason to reseed - it says
so and stops, because that is the moment a link would break:
`--bridge <compiler>` generates with a named compiler and records the
row as `bridge-needed`, which the lineage gate refuses until the link
is certified by a method that replays. The way to never need that is
the rule every reseed since `991e8bd` has followed: land the construct
the compiler must learn, reseed, then use it.

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
until the commit it found hashes to it, and by
`scripts/check-seed-lineage.sh`, which will not replay a link into a
tree the stamp does not describe.

A seed may also land in a commit of its own, after the source change
it answers to rather than with it - the FreeBSD seeds did, because
only a compiler that already knows a target can emit that target's
seed. Such a commit's parent is the same source tree and hashes the
same, and the provenance gate compares STAMP against the nearest
ancestor whose sources moved rather than against the parent.
