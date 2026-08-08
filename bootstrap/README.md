# The bootstrap seed

The Axiom compiler is written in Axiom. These four files are how a
clean checkout builds it without already having it.

```
axiom-darwin-aarch64.ll   the compiler, as LLVM IR, one file per target
axiom-darwin-x86_64.ll
axiom-linux-aarch64.ll
axiom-linux-x86_64.ll
SHA256SUMS                what each of them should hash to
STAMP                     which commit they were generated from, and when
```

`scripts/bootstrap-from-seed.sh` picks the file matching the host,
runs `llc` and `cc` over it to get a compiler, and uses that compiler
to build the compiler from `self_host/` — then does it twice more and
requires the last two to be byte-identical. It needs `llc` and a C
compiler on `PATH` and nothing else. Not `cargo`, not `rustc`.

## Why the IR and not a binary

A binary is opaque, is four times larger, and has to be rebuilt for
every libc and linker anyone might have. The IR is text, it is
reviewable in a diff, `git` delta-compresses the four files against
each other well because they differ in 193 lines out of 61,473 — the
target triple, the syscall instruction, and the syscall numbers — and
the same `llc` invocation the project already relies on turns it into
whatever the host needs.

Measured: 2.10 MB per target, 8.38 MB for the four.

## Why it is allowed to lag the source

The seed is **not** asserted to be the IR of the source next to it. If
it were, every commit touching the compiler would carry 8.4 MB of
regenerated text, and the property that buys — "the seed is exactly
this source" — is not what a fresh clone needs.

What a clone needs is *"the seed can build this source"*, and that is
what the script checks, by building it. A seed that falls behind far
enough to stop compiling `self_host/` fails there, naming the stage
that could not do it, and `scripts/reseed.sh` moves it forward. This
is the same arrangement Go and Rust have with their bootstrap
toolchains, for the same reason.

Measured, so the arrangement is not merely asserted: a seed generated
from the *previous commit's* compiler builds the current tree to a
byte-identical `stage2 == stage3`.

## What this does and does not prove

A tampered seed would have to compile the whole compiler from source,
have its output compile the compiler again to a byte-identical
fixpoint, and have that build and run a working program. Ken
Thompson's *Reflections on Trusting Trust* still applies here, as it
does to every bootstrapped compiler, and no checked-in artifact can
answer it. Everything short of it is answered.

`SHA256SUMS` is a corruption check, not a trust check: a hash and a
file committed together move together. It exists so that a damaged
seed is reported here, by name, instead of as a link error three steps
downstream.

## Regenerating

```bash
AXIOM=<a working compiler> scripts/reseed.sh
scripts/bootstrap-from-seed.sh          # always, before committing
```

The seeds are reproducible — `scripts/check-reproducible.sh` is the
gate that says so, and re-running `reseed.sh` against an unchanged
tree was measured to leave all four `.ll` files and `SHA256SUMS`
byte-identical. If one of them moves without the compiler moving, the
compiler has a nondeterminism bug, and that is the thing to fix rather
than the diff to commit.

`STAMP` does move on every run: it records the time. It is the one
file here that carries no signal about the compiler.
