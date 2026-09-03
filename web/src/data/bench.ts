/**
 * A like-for-like measurement, re-run against a compiler built from the
 * commit this page ships with.
 *
 * THE THREE PROGRAMS ARE IN THE TREE: `web/bench/collatz.{ax,rs,c}`,
 * with the methodology and the reproduction commands beside them. They
 * were not, until 2026-09-01, and that made the one table on this site
 * which is entirely figures the one thing on it nobody could check —
 * `site.ts` states the rule ("a figure that cannot be produced by
 * running something against the repository does not belong here") and
 * this file published build commands "so the table can be reproduced"
 * against sources that did not exist. Re-measuring for a release meant
 * reconstructing them, which is exactly the cost the rule exists to
 * prevent.
 *
 * Methodology is the repository's own (`scripts/bench-datastructures.sh`,
 * `scripts/bench-compile.sh`): every stage is timed as a whole process
 * doing the real work, because that is what a user waits for, and the
 * figure reported is the BEST of N runs rather than the mean —
 * interference only ever makes a run slower, so the minimum is the
 * closest estimate of the cost itself.
 *
 * ONE ADDITION, and it changed the answer. The first pass ran all of
 * A's repetitions, then all of B's, and reported Axiom at 0.732s against
 * Rust's 0.733s. A second pass on a busier machine reported Axiom at
 * 1.204s against Rust's 0.745s — a 1.6x gap that would have been a
 * finding if it were real. It was not: running the binaries in BLOCKS
 * compares two different load conditions, because a background build
 * that starts midway through the run taxes whichever block it lands on.
 * Interleaving the runs — one repetition of each binary, in turn, twenty
 * times — gives every binary the same distribution of interference, and
 * the four figures collapse onto each other. That is the measurement
 * below, and the block-scheduled numbers were discarded.
 *
 * The workload is identical in all three languages: Collatz step counts
 * for 1..3,000,000, summed and printed. Signed 64-bit integers
 * throughout, no allocation, and no library call in the hot loop. All
 * three binaries print 428343467.
 *
 * Go and Haskell are absent from this table on purpose: no toolchain for
 * either was present on the machine, and this project does not publish a
 * number it has not measured.
 */

export const BENCH_ENV = {
  machine: 'Apple M1, macOS 26.6.2, darwin-aarch64',
  axiom: 'Axiom 0.7.0',
  rust: 'rustc 1.97.1',
  c: 'clang 23.1.0',
  answer: '428343467',
}

export interface BenchRow {
  metric: string
  /** How the figure was produced. */
  how: string
  axiom: string
  rust: string
  c: string
  note: string
}

export const BENCH: BenchRow[] = [
  {
    metric: 'Run time',
    how: '3,000,000 Collatz sequences · best of 20, interleaved',
    axiom: '0.428 s',
    rust: '0.429 s',
    c: '0.429 s',
    note: 'Within one millisecond across all three. Axiom emits LLVM IR, so a loop that is only arithmetic and branches gets the machine code the other two get.',
  },
  {
    metric: 'Compile to a native binary',
    how: 'one file, cold · best of 15, interleaved',
    axiom: '0.115 s',
    rust: '0.088 s',
    c: '0.115 s',
    note: 'Axiom is the slowest of the three, by twenty-seven milliseconds against rustc — 1.31x — and level with clang at 1.00x. Published because it is what was measured. It is NOT chained to the passes before it: those timed sources that were never committed, so their seconds are not comparable with these.',
  },
  {
    metric: 'Binary size',
    how: 'the executable on disk',
    axiom: '35,384 B',
    rust: '466,024 B',
    c: '33,432 B',
    note: 'Thirteen times smaller than the Rust binary, and within six percent of C — with no C runtime inside it at all.',
  },
  {
    metric: 'Undefined symbols',
    how: 'nm -u <binary> | wc -l',
    axiom: '0',
    rust: '70',
    c: '1',
    note: 'The whole program is in the file. Nothing is resolved at load time, because there is nothing left to resolve.',
  },
]

/*
 * RE-MEASURED 2026-09-01 for this release, against the compiler this
 * page ships with and from the three sources now committed beside it.
 * Interleaved, best of 15 for the compile row and best of 20 for the
 * run row, on an Apple M1. Two prior passes on the same machine agreed
 * with this one to within a millisecond on every arm.
 *
 * WHAT ESTABLISHES THAT THIS IS THE SAME WORKLOAD, rather than a new
 * one wearing the old table's heading. The reconstructed Rust and C
 * programs compile to binaries of exactly the previously published
 * sizes — 466,024 B and 33,432 B — and reproduce all three
 * undefined-symbol counts. Those are four figures that had to be
 * guessed right and were not guessed.
 *
 * WHAT DOES NOT MATCH, said plainly. The Axiom binary is 35,384 B
 * against a published 35,432 B, so the `.ax` program is an equivalent
 * implementation and not a byte-for-byte recovery of one that was never
 * committed. The seconds are also much lower across ALL THREE arms than
 * the last published pass (run 0.699 -> 0.428 for every language;
 * compile 0.182/0.129/0.180 -> 0.115/0.088/0.115). Three arms moving
 * together is a machine that was quieter, not a compiler that got
 * 1.6x faster, and this file has made that mistake in the other
 * direction before.
 *
 * SO THE SERIES IS CUT HERE. Earlier notes chained the compile ratio
 * across passes - 1.54x, then 1.46x, then 1.41x - as though one
 * measurement continued another. It cannot be continued across sources
 * nobody kept, and the ratio it reports now (1.31x against rustc, 1.00x
 * against clang) is a fresh reading from files anyone can run. Future
 * passes CAN be chained to this one, because the programs they time are
 * in the repository and gated by the same fmt and grammar sweeps as
 * every other `.ax` file.
 *
 * The compile row remains the case that flatters this compiler least,
 * and that is why it is the one published: the emitter's indexing work
 * is worth 4.95x on the compiler's own source, where a lookup has tens
 * of thousands of declarations to scan, and close to nothing on a
 * twenty-seven-line program.
 */

/** The exact commands, so the table can be reproduced. */
export const BENCH_CMDS = `axiom build --input collatz.ax --output out-axiom
rustc -O collatz.rs -o out-rust
clang -O2 collatz.c -o out-c`
