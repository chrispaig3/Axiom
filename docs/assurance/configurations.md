# Reference configurations

Evidence only means something alongside the configuration it was
observed on. [requirements.md](requirements.md) and
[scorecard.md](scorecard.md) cite the four IDs defined here. A claim
marked H1–H3 is observed on H2 and H3 in CI on every change. H1 is
source-only, so its part of such a mark is where the claim was last
observed, not a leg that still runs. A claim with a narrower mark names
the runner it needs, and the hosts where it is skipped or unverified.

## Hosted configurations

| ID | Target triple | Runner | OS / arch |
|---|---|---|---|
| H1 | linux-x86_64 (source-only) | ubuntu-latest | Linux / x86-64 |
| H2 | linux-aarch64 | ubuntu-24.04-arm | Linux / AArch64 |
| H3 | darwin-aarch64 | macos-14 | macOS / AArch64 |

H2 and H3 run the full set of gates in `.github/workflows/ci.yml`. H1
runs only `Bootstrap from seed (linux-x86_64)`: CI builds the compiler
there from the seed and runs one program with it, and runs no gates.
`build-shared-axc.sh` builds the compiler under test once from
`self_host/`, and every gate reuses that build while the source stamp
matches. `check-gate-lib.sh` shows that this sharing can't hide a
source change.

## Freestanding configuration

| ID | Target | What runs |
|---|---|---|
| E1 | All seven `--target` values | Emission and assembly checks only: `check-cross-targets.sh` (position-independent objects from one host), `check-freestanding.sh` (no libc import) and `check-embedded.sh` (allocator constants, a minimal program with 3 syscalls) |

The seven values are darwin-aarch64, darwin-x86_64, linux-aarch64,
linux-x86_64, freebsd-x86_64, freebsd-aarch64 and windows-x86_64. All
but the two aarch64 hosted targets are source-only (README, Targets):
CI runs no gates on them. It builds the compiler from the seed, and
runs one program with it, on linux-x86_64 and freebsd-x86_64 only, so
execution evidence on all five is unverified rather than passed.

<a id="toolchain-measured-2026-09-27-on-h3-class-hardware"></a>
## Toolchain

The compiler calls `llc` and `cc` by name, and CI's provision step puts
them on `PATH`. The versions below are from the machine that produced
the local measurements in this directory. They aren't a pin.

The repository pins the Rust toolchain action (`dtolnay/rust-toolchain`)
to a commit on its stable branch, recorded in
`.github/workflows/ci.yml`. The LLVM package comes from the runner
image, and CI uses both apt llvm-18 and Homebrew llvm.

| Tool | Version |
|---|---|
| Measured on | 2026-09-27, H3-class hardware |
| `llc` | Homebrew LLVM 23.1.2, default target arm64-apple-darwin27.0.0 |
| `cc` | Apple clang 21.0.0 (clang-2100.3.34.2) |
| `rustc`/`cargo` | 1.98.1 (FFI side only; the compiler build needs neither) |
| Host | darwin 27.0, arm64 |
| `--opt` | 0–3; `.optstable` fixtures pin identical stdout and exit status at all four levels |

## Runtime profiles

- **Hosted processes** (the default): `parallel` bindings and
  `stdlib/Par.ax` pools lower to forked processes. Each child has its
  own address space and arena, and nothing in this profile depends on
  threads.
- **Hosted threads** (`--threads`): bindings lower to pthreads with
  per-thread arenas, and a spawning module has ten thread-local globals
  (`MM-PAR-3`, `check-thread-local.sh`). Reference-count updates stay
  non-atomic by design. The checker enforces the sharing rules, not the
  lowering.
- **Freestanding**: there is no libc import, and the allocator is the
  emitted `mmap` or static-arena runtime. Behavioural evidence comes
  from E1 only.

## Known configuration gaps

- §12a (thread-arena VmSize) needs Linux procfs, so it is skipped on H3.
- `timeout(1)` is missing from the macOS runner image, so §12b and §12c
  fail there because of the harness, not the property. They pass on H2,
  and locally with a compatible `timeout` on `PATH`.
- Only the thread lowering runs under a race detector
  (`scripts/check-race.sh`), and no sanitizer sees the arena's heap
  blocks. No fault-injection runs exist yet.
