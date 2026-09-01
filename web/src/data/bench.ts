/**
 * A like-for-like measurement, re-run against a compiler built from the
 * commit this page ships with.
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
  axiom: 'Axiom 0.6.1',
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
    axiom: '0.702 s',
    rust: '0.701 s',
    c: '0.702 s',
    note: 'One millisecond apart across all three. Axiom emits LLVM IR, so a loop that is only arithmetic and branches gets the machine code the other two get.',
  },
  {
    metric: 'Compile to a native binary',
    how: 'one file, cold · best of 15, interleaved',
    axiom: '0.342 s',
    rust: '0.222 s',
    c: '0.288 s',
    note: 'Axiom is the slowest of the three, by a hundred and twenty milliseconds against rustc. Published because it is what was measured.',
  },
  {
    metric: 'Binary size',
    how: 'the executable on disk',
    axiom: '35,400 B',
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

/** The exact commands, so the table can be reproduced. */
export const BENCH_CMDS = `axiom build --input collatz.ax --output out-axiom
rustc -O collatz.rs -o out-rust
clang -O2 collatz.c -o out-c`
