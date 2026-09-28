# `compat/` — what a version number promises

This directory holds the evidence behind each release's version
number. `scripts/check-version.sh` holds nineteen literals across
sixteen files to `VERSION`, which proves the number is *stated*. The
files here show it is *earned*: they record the public surface each
version published and every break declared against it.

| File | What it is |
|---|---|
| `<version>.axsym` | The public surface that version published, one normalised row per name. |
| `BREAKING` | Every break, declared against the version that makes it. |
| `UNCOVERED` | Public names the symbol stream can't carry yet, as a set. |
| `SENTINELS` | Per module, how many public functions answer a sentinel from their body: a `failure` (a negative errno, which wants `Result`) or an `absence` (-1 for "not found", which wants `Option`). |

`tests/compat/verify-compat.py` generates each baseline. Its header
explains why a name's AXSYM `@nid` is its identity and its type plus
effect row is its contract.

Cutting a release adds a new `<version>.axsym` and keeps the earlier
ones, so every published surface stays on record.
[`docs/compatibility.md`](../docs/compatibility.md) is the policy, and
`scripts/check-compat.sh` enforces it.
