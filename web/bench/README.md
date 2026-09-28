# The benchmark the website publishes

`web/src/data/bench.ts` publishes a four-row table comparing Axiom with
Rust and C. This directory holds the three programs it times, and the
script that times them, so you can reproduce every figure.

## Run it

```bash
web/bench/run-bench.sh              # uses `axiom` and `hyperfine` on PATH
AXIOM=.axiom-bin/axiom web/bench/run-bench.sh
RUN_REPS=20 COMPILE_REPS=15 web/bench/run-bench.sh
```

The script also needs `rustc`, `clang` and `nm`. It prints the versions
it measured with, then one line per table cell, ready to copy into
`bench.ts`.

The site's rule, stated in `web/src/data/site.ts`, is that *"a figure
that cannot be produced by running something against the repository
does not belong here"*. These sources and this script are what let the
table meet it.

## The workload

Collatz step counts for 1..3,000,000, summed and printed. Signed 64-bit
integers throughout, no allocation, and no library call in the hot loop.

All three binaries print `428343467`. That is the cross-check, and it is
why `BENCH_ENV` quotes the figure. A program that prints anything else
isn't running this workload, and its timings mean nothing beside the
other two. `run-bench.sh` stops if any binary prints something else.

<a id="building"></a>
## Build the programs

```bash
axiom build --input collatz.ax --output out-axiom
rustc -O collatz.rs -o out-rust
clang -O2 collatz.c -o out-c
```

## Methodology

The method comes from `scripts/bench-datastructures.sh`, and the timer
is [hyperfine](https://github.com/sharkdp/hyperfine).

- Each stage is timed as a whole process doing the real work, because
  that is what you wait for. Hyperfine takes one sample per invocation
  (`--runs 1`, `--warmup 0`). The script loops it round-robin and keeps
  the minimum of its per-sample times.
- The figure is the best of N runs, not the mean. Interference only
  ever makes a run slower, so the minimum is the closest estimate of
  the true cost.
- The runs are interleaved: one repetition of each binary in turn,
  rather than all of A's and then all of B's. Blocks compare two
  different load conditions. A block-scheduled pass once reported a
  1.6x gap that was entirely a background build landing on one block.
  Interleaving brought the four figures back together.
- Hyperfine itself schedules in blocks, so the round-robin lives in the
  script around it.

Run time is best of 20. Compile time is best of 15, cold.

## Provenance, and what is not comparable

The Rust and C programs reproduce the previously published binary sizes
exactly, 466,024 B and 33,432 B, and all three undefined-symbol counts.
That shows this is the workload earlier passes timed.

The Axiom program doesn't reproduce its published size: 35,384 B
against 35,432 B. It is an equivalent implementation, not a
byte-for-byte recovery of a source that was never committed. So the
absolute seconds from passes timed before these sources were in the
tree aren't comparable with these, and the table doesn't chain them
into one series. Compare the ratios instead.
