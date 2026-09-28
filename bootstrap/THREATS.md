# What the seed is defended against, and what it is not

[`README.md`](README.md) explains what the seed gates prove. This page
lists what they don't, in one table, so the gap between "we check
this" and "we say this" stays visible.

Each row is one capability an adversary might have. A row says `yes`
only when a gate in this repository would go red, and its *Defended by*
cell names that gate and the assertion inside it. Every other row says
`no`. `scripts/check-seed-supply-chain.sh` refuses this page if a `yes`
row names a script that doesn't exist, or one that
`.github/workflows/ci.yml` doesn't run.

This table has 12 rows, 7 defended, and the other 5 are the trust base
and the things a gate can't reach. Row 3 says yes only in a narrow
sense, and its cell spells that out. Section 3 of
`scripts/check-seed-supply-chain.sh` recomputes both numbers from the
table.

## The table

| # | Adversary capability | Defended | Defended by | Residual |
|---|---|---|---|---|
| 1 | Bits damaged in transit or on disk: a seed corrupted between the git host and a clone | yes | `scripts/check-bootstrap.sh` and, on the toolchain-free path, `scripts/bootstrap-from-seed.sh`. Both use `seed_sums_verify` in `scripts/lib/seed-sums.sh`: every `.ll` present is named by exactly one row of `SHA256SUMS`, every row names a file present, and then every hash is checked. `scripts/check-seed-supply-chain.sh` §2 probes it | None for damage. A seed that was tampered with *and* re-hashed is the business of rows 2 to 4. `shasum -c` alone would miss a deleted row, because it says nothing about a file it has no row for |
| 2 | A malicious commit to `bootstrap/*.ll` alone, with the hashes updated to match | yes | `scripts/check-seed-provenance.sh`. It finds the commit that last wrote the six `.ll` files, requires that commit's `self_host/` and `stdlib/` bytes to hash to `STAMP`'s `Source stamp:`, and regenerates all six seeds from them, requiring byte-identity | The tamper has to move into the `.ax` sources instead, where it can be reviewed. That is row 3, which is not a closed door |
| 3 | A malicious commit to `self_host/` or `stdlib/`, with the seed regenerated honestly from it | yes, in one narrow sense only | `scripts/check-seed-provenance.sh`. The seed must be that source's emission, so a backdoor sits in `.ax` files a reviewer can read, not in the millions of lines of LLVM IR that `wc -l bootstrap/*.ll` counts | **Only code review defends this row.** No gate decides whether the `.ax` change is malicious. The gate ensures only that the change can't hide in the generated text |
| 4 | A Thompson attack: a compiler that inserts a backdoor into its own emission, so the backdoor survives with no trace in any source | yes | `scripts/check-seed-lineage.sh`. Every row of `bootstrap/CHAIN` is replayed back to the Rust compiler at `bb730db`, which no Axiom seed ever touched: Wheeler's diverse double-compile. It runs `--full` nightly, and on any push touching `bootstrap/` it replays the uncertified rows | The Rust anchor shares an author with `self_host/`, a weakness of "diverse" in the social sense and the real limit of this row. Rows 5 to 7, the replay's own trust base, also apply |
| 5 | A compromised `llc`, `cc` or `opt` on the machine doing the verifying | no | — | Part of the trust base. These tools turn every seed on the replayed path into a running compiler, so a backdoor in `llc` reaches every rung, the anchor's included. Removing them needs a witness that never assembles anything, such as an interpreter for the compiler's subset, which `bootstrap/README.md` calls separate work |
| 6 | A compromised `rustc`, `cargo`, or one of the crates `bb730db`'s `Cargo.lock` pins | no | — | The root of the trust base: the anchor is what gives row 4 its meaning. There are 84 packages, and 76 are byte-pinned by `checksum` (`git show bb730db:Cargo.lock \| grep -c '^checksum = '`). The 8 without are the workspace's own path crates. CI builds the anchor with `toolchain: stable`, which moves, so the pinning covers the crates but not the compiler that builds them. The nightly `--full` run warns when this root rots. It doesn't defend against it |
| 7 | A compromised CI runner, or a compromised `actions/*` step | no | — | Part of the trust base, since every gate in this table runs there. Two things help: pinning (`uses:` by SHA, and `dtolnay/rust-toolchain` at a commit), and the fact that a maintainer can run any of these gates locally and get the same answer. Neither defends against a runner that lies |
| 8 | A maintainer who edits a `CHAIN` row and recomputes `CHAIN.checkpoint`'s digest in the same commit | no, by design | — | The checkpoint is a record, not a signature (`bootstrap/README.md`). Anyone who can edit a row can recompute the digest, but they must do both in the same diff, in front of a reviewer. Signing it would only move the question to who holds the key. The nightly `--full` run re-derives every row from `bb730db` whatever the checkpoint says, which is what makes this row survivable |
| 9 | A compromised git host that rewrites history, replacing `bb730db`, a `CHAIN` row's commit, or a seed's blob | no | — | Every gate here reads history through `git` and believes it. A clone that already has the objects would see the rewrite, and a fresh clone would not. Defending this needs an out-of-band record of the commit ids, which this repository doesn't have |
| 10 | A seed committed for a target that no list knows about, or a target dropped from one list and not another | yes | `scripts/check-seed-supply-chain.sh` §1. It compares the six-target set across five sites: `seed_targets` in `scripts/lib/seed-sums.sh`, the `.ll` files on disk, the rows of `SHA256SUMS`, the file box in `bootstrap/README.md`, and the regeneration list in `scripts/check-seed-provenance.sh` | Names only. A target present in all five with a tampered seed is the business of rows 1 to 4 |
| 11 | A refactor that quietly puts a seed-descended Axiom binary on the lineage gate's compared path, so the diverse double-compile compares a compiler against itself | yes | `scripts/check-seed-lineage.sh` reads its own text: nothing below `# === the compared path begins here ===` may name `$axiom`, `.axiom-bin`, `AXIOM_AXC` or `gate_build_axc`. `scripts/check-seed-supply-chain.sh` §4 requires the marker and that self-read to still be there, in that order | Textual only. A binary reached under a name that none of those four patterns match would pass |
| 12 | A Thompson attack carried by the *current* seed's codegen, which the fixpoint reproduces untouched | yes | `scripts/check-ddc.sh`. Eight subset programs in `tests/ddc/` run on the seed-built compiler and on an independent Python interpreter (`scripts/lib/ddc-interp.py`, written in a different language, with logic derived from the reference rather than ported from the compiler). The results must agree with each other and with the `; expect N` each program states. On every run the gate plants one flipped `icmp sgt` in emitted IR, which must fail the comparison where the fixpoint can't | Covers a subset only: integers, comparisons, and `if`, `let`, calls and recursion. The interpreter shares a maintainer with the compiler, so the social half of "diverse" is still open, as in row 4. Path A still trusts `llc` and `cc` (rows 5 to 7) |

## What a `yes` row costs to keep

A change can break rows 1, 2, 3, 4, 10, 11 and 12. The gates that hold
them are `check-bootstrap.sh`, `check-seed-provenance.sh`,
`check-seed-lineage.sh`, `check-seed-supply-chain.sh` and
`check-ddc.sh`. Each one carries negative probes that must go red,
because a trust gate that can only pass proves nothing.

Rows 5, 6, 7 and 9 are the trust base. Writing more gates doesn't
shrink them. Only removing a dependency does, and each removal is its
own piece of work with its own cost. `bootstrap/README.md` names how
row 5's dependency could be removed, and that work isn't scheduled.

## The row to remember

Row 3 matters most. "The seed is the emission of source you can read"
is a strong property, but it isn't the same as "the source is not
malicious". Nothing in this repository claims the second.
