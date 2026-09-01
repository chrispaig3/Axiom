# The benchmark the website publishes

`web/src/data/bench.ts` prints a four-row table comparing Axiom with
Rust and C. These are the three programs it times.

They were not in the tree until 2026-09-01, and their absence made one
claim on the site false. `site.ts` states the rule — *"a figure that
cannot be produced by running something against the repository does not
belong here"* — and `bench.ts` published the three build commands under
the heading *"so the table can be reproduced"*, against sources nobody
could reach. Re-measuring for a release meant reconstructing them, which
is the failure mode the rule exists to prevent.

## The workload

Collatz step counts for 1..3,000,000, summed and printed. Signed 64-bit
integers throughout, no allocation, and no library call in the hot loop.

All three binaries print `428343467`. That is the cross-check, and it is
the reason the figure is quoted in `BENCH_ENV`: a program that prints
anything else is not running this workload, and its timings mean nothing
beside the other two.

## Building

    axiom build --input collatz.ax --output out-axiom
    rustc -O collatz.rs -o out-rust
    clang -O2 collatz.c -o out-c

## Methodology

Inherited from `scripts/bench-datastructures.sh`:

- Every stage is timed as a **whole process** doing the real work, not
  as an in-process timer, because that is what a user waits for.
- The figure is the **best of N** runs, not the mean. The distribution is
  one-sided — interference only ever makes a run slower — so the minimum
  is the closest estimate of the cost itself.
- The runs are **interleaved**: one repetition of each binary, in turn,
  rather than all of A's and then all of B's. Blocks compare two
  different load conditions. That is not hypothetical — a block-scheduled
  pass once reported a 1.6x gap that was entirely a background build
  landing on one block, and interleaving collapsed the four figures onto
  each other.

Run time is best of 20; compile is best of 15, cold.

## Provenance, and what is not comparable

The Rust and C programs reproduce the previously published binary sizes
**exactly** — 466,024 B and 33,432 B — and all three undefined-symbol
counts. That is the evidence that this workload is the one earlier
passes timed.

The Axiom program does not reproduce its published size: 35,384 B
against 35,432 B. It is an equivalent implementation, not a
byte-for-byte recovery of a source that was never committed. So the
**absolute seconds** from passes before 2026-09-01 are not comparable
with these, and the table no longer chains them into one series. The
ratios are what carries across.
