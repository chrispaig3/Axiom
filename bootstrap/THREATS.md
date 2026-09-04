# What the seed is defended against, and what it is not

`bootstrap/README.md` says at length what the three seed gates prove.
This file says what they do NOT, in one table, because a trust story
told only in prose is a story where the gap between "we check this" and
"we say this" is invisible.

One row per adversary capability. A row is `yes` only when a gate in
this repository would go red, and the `Defended by` cell must name that
gate and the assertion inside it —
`scripts/check-seed-supply-chain.sh` refuses this file if a `yes` row
names a script that does not exist or that `.github/workflows/ci.yml`
does not run, so a row cannot promise a check that nobody performs.
Everything else is a `no` row. Six of the eleven say yes and five say
no, and the five are not an oversight: they are the trust base and the
things a gate cannot reach, and a truthful "not defended" is worth more
here than a "defended" the tree cannot back. Row 3 says yes in a sense
narrow enough that the cell spells the narrowness out.

## The table

| # | Adversary capability | Defended | Defended by | Residual |
|---|---|---|---|---|
| 1 | Bits damaged in transit or on disk: a seed corrupted between the git host and a clone | yes | `scripts/check-bootstrap.sh` and, on the toolchain-free path, `scripts/bootstrap-from-seed.sh`, both through `seed_sums_verify` in `scripts/lib/seed-sums.sh`: every `.ll` present is named by exactly one row of `SHA256SUMS`, every row names a file present, then every hash is verified. `scripts/check-seed-supply-chain.sh` §2 probes it | None for damage. This says nothing about a seed that was tampered with *and* re-hashed — that is rows 2–4. Before 2026-09-03 a *deleted* row also passed here: `shasum -c` is silent about a file it was given no row for |
| 2 | A malicious commit to `bootstrap/*.ll` alone, hashes updated to match | yes | `scripts/check-seed-provenance.sh`: it finds the commit that last wrote the six `.ll` files, requires that commit's `self_host/` and `stdlib/` bytes to hash to `STAMP`'s `Source stamp:`, and regenerates all six seeds from them, requiring byte-identity | The tamper has to move into the `.ax` sources instead, where it is reviewable — which is row 3, not a closed door |
| 3 | A malicious commit to `self_host/` or `stdlib/`, with the seed regenerated honestly from it | yes, in one narrow sense only | `scripts/check-seed-provenance.sh` — the seed must be that source's emission, so the backdoor is in `.ax` files a reviewer can read rather than in 1,235,917 lines of LLVM IR (`wc -l bootstrap/*.ll`, 2026-09-03) | **This is code review, not a gate.** Nothing here decides whether the `.ax` change is malicious. What the gate buys is only that the change cannot hide in the generated text |
| 4 | A Thompson attack: a compiler that inserts a backdoor into its own emission, so the backdoor survives with no trace in any source | yes | `scripts/check-seed-lineage.sh`: every row of `bootstrap/CHAIN` replayed back to the Rust compiler at `bb730db`, which no Axiom seed ever touched — Wheeler's diverse double-compile. `--full` nightly; the uncertified rows on any push touching `bootstrap/` | The Rust anchor shares an author with `self_host/`. That is a weakness of "diverse" in the social sense, and it is the honest limit of this row. Also rows 5–7: the replay's own trust base |
| 5 | A compromised `llc`, `cc` or `opt` on the machine doing the verifying | no | — | On the trust base. Every seed on the replayed path is turned into a running compiler by them, so a backdoor in `llc` reaches every rung including the anchor's. Removing them needs a witness that never assembles anything — an interpreter for the compiler's subset — which `bootstrap/README.md` calls a separate track |
| 6 | A compromised `rustc`, `cargo`, or one of the crates `bb730db`'s `Cargo.lock` pins | no | — | On the trust base, and it is the ROOT of it: the anchor is what makes row 4 mean anything. 84 packages, 76 byte-pinned by `checksum` (`git show bb730db:Cargo.lock \| grep -c '^checksum = '`); the 8 without are the workspace's own path crates. But CI builds it under `toolchain: stable`, which moves, so the pinning stops at the crates and does not reach the compiler that consumes them. The nightly `--full` is the canary for that root rotting, not a defence against it |
| 7 | A compromised CI runner, or a compromised `actions/*` step | no | — | On the trust base. Every gate in this table runs there. The mitigations that exist are pinning (`uses:` by SHA, `dtolnay/rust-toolchain` at a commit) and the fact that a maintainer can run any of these gates locally and get the same answer — neither is a defence against a runner that lies |
| 8 | A maintainer who edits a `CHAIN` row and recomputes `CHAIN.checkpoint`'s digest in the same commit | no, by design | — | The checkpoint "is a record rather than a signature: whoever can edit a row can recompute the digest too, and what the file buys is that they must do it in the same diff, in front of a reviewer" (`bootstrap/README.md`). Signing it would move the question to key custody without answering it. The nightly `--full` re-derives every row from `bb730db` regardless of what the checkpoint says, which is the property that makes this row survivable |
| 9 | A compromised git host that rewrites history — replacing `bb730db`, a `CHAIN` row's commit, or a seed's blob | no | — | Every gate here reads history through `git` and believes it. A clone that already has the objects would see the rewrite; a fresh clone would not. Defending it needs an out-of-band record of the commit ids, which this repository does not have |
| 10 | A seed committed for a target that no list knows about, or a target dropped from one list and not another | yes | `scripts/check-seed-supply-chain.sh` §1: the six-target set is compared across five sites — `seed_targets` in `scripts/lib/seed-sums.sh`, the `.ll` files on disk, the rows of `SHA256SUMS`, the file box in `bootstrap/README.md`, and `scripts/check-seed-provenance.sh`'s regeneration list | Names only. A target present in all five with a tampered seed is rows 1–4's business, not this one |
| 11 | A refactor that quietly puts a seed-descended Axiom binary on the lineage gate's compared path, making the diverse double-compile compare a compiler against itself | yes | `scripts/check-seed-lineage.sh` reads its own text: nothing below `# === the compared path begins here ===` may name `$axiom`, `.axiom-bin`, `AXIOM_AXC` or `gate_build_axc`. `scripts/check-seed-supply-chain.sh` §4 requires the marker and that self-read to still be there, in that order | Textual. A binary reached under a name none of those four patterns match would pass |

## What a `yes` row costs to keep

Rows 1, 2, 3, 4, 10 and 11 are the ones a change can break. The gates that
hold them are `check-bootstrap.sh`, `check-seed-provenance.sh`,
`check-seed-lineage.sh` and `check-seed-supply-chain.sh`, and each
carries negative probes that must go red — a gate that only ever passes
is this repository's most common defect, and a *trust* gate that only
ever passes is the worst instance of it.

Rows 5, 6, 7 and 9 are the trust base. They do not shrink by writing
more gates; they shrink by removing a dependency, and each removal is
its own piece of work with its own cost. Row 5's removal is named in
`bootstrap/README.md` and is not scheduled.

Row 3 is the one this table most wants a reader to notice. "The seed is
the emission of source you can read" is a strong property and it is not
the same as "the source is not malicious". No mechanism in this
repository claims the second one.
