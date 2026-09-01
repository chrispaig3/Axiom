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
  axiom: 'Axiom 0.6.2',
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
    axiom: '0.700 s',
    rust: '0.700 s',
    c: '0.699 s',
    note: 'One millisecond apart across all three. Axiom emits LLVM IR, so a loop that is only arithmetic and branches gets the machine code the other two get.',
  },
  {
    metric: 'Compile to a native binary',
    how: 'one file, cold · best of 15, interleaved',
    axiom: '0.186 s',
    rust: '0.128 s',
    c: '0.181 s',
    note: 'Axiom is still the slowest of the three, by fifty-eight milliseconds against rustc. Published because it is what was measured. The gap NARROWED — 1.54x to 1.46x against rustc, and 1.19x to 1.02x against clang — but read the ratio, not the seconds: all three arms also got faster between the two measurements, so the machine was quieter, not Axiom 1.8x better.',
  },
  {
    metric: 'Binary size',
    how: 'the executable on disk',
    axiom: '35,432 B',
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
 * RE-MEASURED 2026-09-01 against the compiler this page ships with,
 * after the emitter's un-indexed name lookups were replaced with the
 * indexes the compiler already built. Interleaved, best of 15 for the
 * compile row and best of 20 for the run row, on an Apple M1.
 *
 * THREE OF THE FOUR ROWS COULD NOT HAVE MOVED, and that is checkable
 * rather than assumed: the indexing change was verified to emit
 * byte-identical LLVM IR over 132 files including the compiler itself,
 * so it produces the same binary. Run time, undefined symbols and the
 * Rust and C binary sizes are unchanged within noise, which is what
 * that verification predicts. Axiom's binary moved 32 bytes, from the
 * tree growing between the two measurements, not from the change.
 *
 * THE COMPILE ROW IS THE ONE THAT MOVED, AND THE SECONDS OVERSTATE IT.
 * Every arm got faster — rustc 0.222 -> 0.128, clang 0.288 -> 0.181 —
 * so the earlier pass ran on a busier machine and the absolute drop is
 * mostly that. The comparable figure is the ratio: 1.54x -> 1.46x
 * against rustc, 1.19x -> 1.02x against clang. Real, and modest.
 *
 * It is modest HERE for a reason worth stating, because the same
 * change is worth 4.95x on the compiler's own source: the win scales
 * with how many declarations a lookup has to scan, and this program is
 * twenty-five lines. A one-file benchmark is the case that flatters
 * this optimisation least, which is why it is the one published.
 */

/** The exact commands, so the table can be reproduced. */
export const BENCH_CMDS = `axiom build --input collatz.ax --output out-axiom
rustc -O collatz.rs -o out-rust
clang -O2 collatz.c -o out-c`
