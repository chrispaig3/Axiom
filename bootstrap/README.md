# The bootstrap seed

The Axiom compiler is written in Axiom. The files in this directory let
a clean checkout build it without already having a compiler.

## Build from the seed

```bash
./scripts/bootstrap-from-seed.sh --install .axiom-bin
```

You need `llc` and a C compiler on `PATH`, and nothing else: no `cargo`
and no `rustc`.

The script picks the seed that matches your host and runs `llc` and
`cc` over it to get a `seed` compiler. That compiler builds `self_host/`
into `stage1`. Then the usual ladder runs, `stage1 -> stage2 ->
stage3`, and `stage2` and `stage3` must be byte-identical.

With `--install DIR`, the script copies `stage3` to `DIR/axiom`, which
is where every other gate looks for a compiler. That is the compiler
that came out of the fixpoint, not the seed or `stage1`.

## What's here

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
CHAIN.checkpoint          the prefix of CHAIN a push run may skip
THREATS.md                what the seed is defended against, and what it is not
lineage/                  the commit list and the one patch a CHAIN row names
```

All six seeds are emitted, hashed, regenerated and assembled the same
way. A seed is not evidence that its target runs, though:

- `freebsd-x86_64` is executed. The `Tests (freebsd-x86_64)` job boots
  FreeBSD 14.4 in a VM and bootstraps from this seed, so it is a
  supported target.
- `freebsd-aarch64` is not executed, because an aarch64 guest is
  emulated by TCG on every runner GitHub offers.
- `darwin-x86_64` sits under the same gates and ships no prebuilt
  archive, for the same reason: no runner executes it.

The [README's Targets section](../README.md#targets) has the full list.

## Why the IR and not a binary

A binary would be smaller than the IR that produces it, but it is the
wrong thing to commit. Nobody can review an opaque binary before
trusting it, and it would need rebuilding for every libc and linker.

The IR is text, so you can review it in a diff. The six files are one
program compiled for six targets, differing only in the target triple,
the syscall instruction and the syscall numbers, so `git`
delta-compresses them well. The same `llc` call the project already
uses turns the IR into whatever your host needs.

Every size moves with every reseed, so measure them yourself:

```bash
du -sh bootstrap                       # all six, plus SHA256SUMS and STAMP
wc -l bootstrap/*.ll                   # lines per target
ls -l .axiom-bin/axiom                 # what one of them turns into
diff bootstrap/axiom-darwin-aarch64.ll \
     bootstrap/axiom-linux-x86_64.ll | grep -c '^[<>]'   # how far apart two are
```

## Why it is allowed to lag the source

The seed isn't required to be the IR of the source beside it, and
`bootstrap-from-seed.sh` doesn't check that it is. If it did, every commit that
touched the compiler would carry a regenerated seed in its diff. A
fresh clone doesn't need "the seed is exactly this source".

A clone needs "the seed can build this source", and the script checks
that by building it. If the seed falls far enough behind that it can't
compile `self_host/`, the build fails and names the stage that
couldn't. `scripts/reseed.sh` then moves the seed forward. Go and Rust
treat their bootstrap toolchains the same way, for the same reason.

A seed generated from the previous commit's compiler builds the current
tree to a byte-identical `stage2 == stage3`.

Lagging in time is not a gap in provenance. The seed is the IR of the
source at the commit that last wrote the six `.ll` files, and
`scripts/check-seed-provenance.sh` asserts that by regenerating it.

## What this does and does not prove

### Corruption: `SHA256SUMS`

`SHA256SUMS` catches corruption. It can't establish trust, because a
hash and a file committed together move together. It exists so that a
damaged seed is reported here, by name, instead of as a link error
three steps later.

`shasum -a 256 -c` on its own checks only the rows it is given, so
deleting a row and replacing the file it named would pass. The rows and
the `.ll` files are therefore compared as sets, in both directions,
before any hash is checked. One function does this, `seed_sums_verify`
in `scripts/lib/seed-sums.sh`, and both `bootstrap-from-seed.sh` and
`check-bootstrap.sh` call it. `scripts/check-seed-supply-chain.sh` runs
that attack against a copy of the seeds on every CI run.

[`THREATS.md`](THREATS.md) turns the rest of this section into a table.
It has one row per adversary capability, saying what is defended, by
which gate and which assertion, and what is left.
`scripts/check-seed-supply-chain.sh` refuses a `yes` row that no gate
backs.

### Provenance: `check-seed-provenance.sh`

The trust check is `scripts/check-seed-provenance.sh`. It finds the
commit that last wrote the six `.ll` files, regenerates all six from
that commit's source, and requires the result to be byte-identical. It
looks for the `.ll` files specifically, because this directory also
holds metadata about them. So the seed is a build product of `.ax`
files you can read, and the regeneration is the proof.

`STAMP` records a hash of the source bytes, which is always right when
it is written, and the gate works back from that to the commit. A
commit id recorded by `reseed.sh` would be wrong: the tree is dirty
while you reseed, so `git rev-parse HEAD` names the commit before the
one that carries the seed.

### Trusting trust

Regeneration alone doesn't answer Ken Thompson's *Reflections on
Trusting Trust*. The compiler doing the regenerating descends from this
seed, so a compiler that copies a backdoor into its own output would
copy it there too.

The answer needs a compiler that doesn't descend from any Axiom seed,
and this repository's history has one. It is the Rust implementation the
repository later deleted (`430a138`, 28,082 lines). Its last commit,
`bb730db`, still builds with `cargo`. The next section shows what that
buys.

## The lineage

`scripts/check-seed-lineage.sh` replays `CHAIN`. `CHAIN` has one row
per seed ever committed, and each row names the seed it reproduces from
and how.

The first row is the root, and it isn't an Axiom seed. The Rust
compiler at `bb730db` compiles the `self_host/` tree of the first seed
commit, `60445dc`, into a `stage1`. That `stage1`'s emission of the
same tree is byte-identical to the first seed. This is Wheeler's
diverse double-compile. The Rust codegen's own IR (93,471 lines)
differs from the seed (61,473 lines).

Every later row reproduces a seed from the one before it. The previous
seed is built with `llc` and `cc` and compiles the next seed's tree.
That emission, or its own re-emission when the two compilers differ,
must equal the next seed byte for byte.

So every seed on the chain is the faithful emission of readable source,
by a compiler that is itself on the chain, back to a root anyone can
read in Rust. A backdoor would have to be in that Rust or in the `.ax`
files, not hidden in megabytes of generated IR.

The gate replays every row nightly (`--full`). On a push that touches
`bootstrap/`, it replays the rows `CHAIN.checkpoint` doesn't certify,
and never fewer than the newest one. Every run also checks that it
refuses a copy of the seed with one byte flipped, and a row re-pointed
at a different predecessor.

### The checkpoint

`CHAIN.checkpoint` keeps the push run cheap without letting it hide a
broken link. It names a prefix of `CHAIN` and the sha256 of exactly
that prefix. The digest covers:

- the rows, verbatim;
- their short hashes, resolved to full commits;
- the git object id of every seed those commits carry;
- the sha256 of every walk list and patch file they name.

The gate recomputes that digest from `CHAIN` on every run, before it
skips anything. If a covered row changes by one byte, the checkpoint is
void. The gate then replays the whole chain from the Rust anchor and
stays red until the prefix is blessed again. Editing an old row can't
shrink the work.

Only `AXIOM_BLESS=1 scripts/check-seed-lineage.sh --full` writes the
checkpoint, over rows that the same process replayed from the anchor. An
ordinary passing run never writes it, because a gate that writes its own trust
anchor when it passes proves nothing. It never covers the newest row,
so the link a push adds is replayed on that push.

The checkpoint is a record rather than a signature. Whoever can edit a
row can recompute the digest too, but they must do it in the same diff,
in front of a reviewer. The nightly `--full` run re-derives every row
from `bb730db` regardless.

### What is answered, and what remains

Answered: the seed in the tree descends, by replayable steps, from a
compiler that no Axiom seed ever touched.

What remains is the trust base of that replay, and it is exactly this
list:

- `git`, for the history the rows name;
- `llc` and `cc`, and optionally `opt`, which turn every seed on the
  path into a running compiler;
- `cargo`, `rustc` and the 84 crates that `bb730db`'s `Cargo.lock`
  pins, which build the root;
- the 28,082 lines of Rust at `bb730db`.

That Rust shares an author with `self_host/`. This is a weakness of
"diverse" in the social sense, not the technical one.

No Axiom binary runs before the comparison, and the gate reads its own
text to assert that. Taking `llc` and `cc` off the list needs a witness
that never assembles anything, such as an interpreter for the
compiler's subset. That is separate work.

### The orphan seeds

Three committed seeds are not their own tree's emission: `1c682ef`,
`24bdf29` and `79c8ebc`. Each was generated by a compiler built from a
tree that was never committed, because `reseed.sh` once generated with
whatever compiler `$AXIOM` named. That line has been removed. An orphan
is not evidence of tampering, but nothing in the history reproduces
these three, so none of them can sit on a trusted path.

`CHAIN` declares them `orphan`, gives them no row, and bypasses them:

- `93a74e5` reproduces from `74a0680` by a walk over the 63 commits in
  between that touched the sources. Each commit is compiled by the
  compiler built from the one before.
- `991e8bd` reproduces from `c98924c` directly, skipping `79c8ebc`.

The walk needs two recorded bridges, at the two places where the plain
step yields a compiler that can't run:

- a mixed tree at `1c682ef`, where the `Str` header widened;
- a seven-site patch at `24bdf29`, where `__retainref` was defined and
  used in the same commit.

`lineage/` holds the walk's commit list and the patch. The gate
requires the plain step to fail before it takes a bridge.

The plain walk over the same commits, without bridges, fails at the
seventh step. The compiler built from `1c682ef`'s tree by its
predecessor crashes with `SIGSEGV` on any input, and the bridges
answer that.

The walk also measures the orphans as it passes. The compiler each
bridge builds re-emits its own tree to a fixpoint 67 and 1,282 lines
from what was committed. `79c8ebc`'s tree reaches a fixpoint from
`c98924c` that is 87,624 lines from its seed.

### Two more facts from the replay

The first link, `60445dc -> 3b6d485`, can't be replayed seed to seed.
That commit changed which names leave a module, and its own message
says the seed couldn't survive it. The mixed tree closes the link, and
a 53-commit walk closes it independently.

Reproduction at *stage2* is a property of the tree, not of the
predecessor. Any working compiler reaches the tree's own fixpoint, so a
nearby seed reproduces a `stage2` row as well as the named one does. A
*stage1* row is the stronger statement: the previous seed's direct
emission is the next seed.

## Regenerating

```bash
scripts/reseed.sh                       # from the committed seed, and it writes the CHAIN row
scripts/bootstrap-from-seed.sh          # always, before committing
```

`reseed.sh` builds its generator from the committed seed and nothing
else. The host's seed goes through `llc` and `cc`, compiles this tree,
and the result emits the six files. So the new seed is the previous
seed's emission of this tree, or that emission's own re-emission. The
row `reseed.sh` appends to `CHAIN` says which, `stage1` or `stage2`.

The row's first column reads `next` until the commit that carries the
seed exists. The following reseed fills in the hash.

### When the seed can't compile the tree

Sometimes the committed seed can't compile the tree, which is the usual
reason to reseed. `reseed.sh` then says so and stops, because this is
the moment a link would break.

`--bridge <compiler>` generates with a compiler you name and records
the row as `bridge-needed`. The lineage gate refuses that row until the
link is certified by a method that replays.

To avoid needing a bridge, land the construct the compiler must learn,
reseed, and only then use it.

### Determinism

Re-running `reseed.sh` on an unchanged tree leaves all six `.ll` files
and `SHA256SUMS` byte-identical, because the compiler is deterministic.

`scripts/check-reproducible.sh` holds it to that. It compiles every
case in `tests/stdlib/` twice, in separate processes, and compares the
IR. Separate processes catch a per-process hash seed, the kind of
nondeterminism that would otherwise first show up as a seed that moves
on its own. If a `.ll` file here changes when the compiler hasn't,
determinism has broken: fix that bug instead of committing the diff.

### `STAMP`

`STAMP` changes on every run, because it records the time as well as
the source hash. Two gates read the hash:

- `scripts/check-seed-provenance.sh` won't regenerate anything until
  the commit it found hashes to `STAMP`.
- `scripts/check-seed-lineage.sh` won't replay a link into a tree that
  `STAMP` doesn't describe.

A seed can also land in a commit of its own, after the source change
it answers to. The FreeBSD seeds did, because only a compiler that
already knows a target can emit that target's seed. That commit's
parent has the same source tree and the same hash, so the provenance
gate compares `STAMP` with the nearest ancestor whose sources changed,
not with the parent.

## See also

- [`THREATS.md`](THREATS.md): what each gate defends, and what it
  leaves to the trust base.
- [CONTRIBUTING](../CONTRIBUTING.md#quick-start): where the bootstrap
  fits in a first build.
