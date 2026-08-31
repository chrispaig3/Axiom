/**
 * A like-for-like measurement, run on one machine before publishing.
 *
 * Methodology is the repository's own (`scripts/bench-datastructures.sh`,
 * `scripts/bench-compile.sh`): every stage is timed as a whole process
 * doing the real work, because that is what a user waits for, and the
 * figure reported is the BEST of five runs rather than the mean —
 * interference only ever makes a run slower, so the minimum is the
 * closest estimate of the cost itself.
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
  reps: 'best of 5',
  answer: '428343467',
}

export interface BenchRow {
  metric: string
  /** How the figure was produced. */
  how: string
  axiom: string
  rust: string
  c: string
  /** Which column wins, for the highlight. */
  note: string
}

export const BENCH: BenchRow[] = [
  {
    metric: 'Run time',
    how: '3,000,000 Collatz sequences',
    axiom: '0.732 s',
    rust: '0.733 s',
    c: '0.738 s',
    note: 'Identical within noise. Axiom emits LLVM IR, so an integer loop gets the same machine code the other two get.',
  },
  {
    metric: 'Compile to a native binary',
    how: 'one file, cold, no cache',
    axiom: '0.233 s',
    rust: '0.162 s',
    c: '0.216 s',
    note: 'Axiom is the slowest of the three here, by seventy milliseconds. Published because it is what was measured.',
  },
  {
    metric: 'Binary size',
    how: 'the executable on disk',
    axiom: '35,368 B',
    rust: '466,024 B',
    c: '33,432 B',
    note: 'Thirteen times smaller than the Rust binary, and within six percent of C — with no C runtime in it at all.',
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
