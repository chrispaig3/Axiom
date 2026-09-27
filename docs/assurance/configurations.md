# Reference configurations

Evidence is meaningless without the configuration it was observed
on. These four IDs are what [requirements.md](requirements.md) and
[scorecard.md](scorecard.md) cite. A claim marked H1–H3 was observed
on all three CI runners; a claim marked narrower names the runner it
needs and the hosts where it is SKIP or unverified.

## Hosted configurations

| ID | Target triple | Runner | OS / arch |
|---|---|---|---|
| H1 | linux-x86_64 | ubuntu-latest | Linux / x86-64 |
| H2 | linux-aarch64 | ubuntu-24.04-arm | Linux / AArch64 |
| H3 | darwin-aarch64 | macos-14 | macOS / AArch64 |

All three run the full gate battery (`.github/workflows/ci.yml`):
`build-shared-axc.sh` builds the compiler under test once from
`self_host/`, and every gate reuses that build while the source stamp
matches. `check-gate-lib.sh` proves the sharing cannot hide a source
change.

## Freestanding configuration

| ID | Target | What runs |
|---|---|---|
| E1 | all seven `--target` values | emission and assembly checks only: `check-cross-targets.sh` (position-independent objects from one host), `check-freestanding.sh` (no libc import), `check-embedded.sh` (allocator constants, 3-syscall minimal program) |

The seven values are darwin-aarch64, darwin-x86_64, linux-aarch64,
linux-x86_64, freebsd-x86_64, freebsd-aarch64, windows-x86_64. No
Axiom program is *executed* on freebsd, windows, or darwin-x86_64 in
CI; execution evidence on those targets is unverified, never passed.

## Toolchain, measured 2026-09-27 on H3-class hardware

The compiler shells out to `llc` and `cc` by name; CI's provision
step puts them on PATH. Versions below are the machine that produced
the local measurements in this directory, not a pin: the repository
pins the Rust toolchain (`dtolnay/rust-toolchain`, stable branch at
2026-08-05) and the LLVM package comes from the runner image
(apt llvm-18 legs and Homebrew llvm both appear in CI).

| Tool | Version |
|---|---|
| `llc` | Homebrew LLVM 23.1.2, default target arm64-apple-darwin27.0.0 |
| `cc` | Apple clang 21.0.0 (clang-2100.3.34.2) |
| `rustc`/`cargo` | 1.98.1 (FFI side only; the compiler build needs neither) |
| Host | darwin 27.0, arm64 |
| `--opt` | 0–3; `.optstable` fixtures pin identical stdout and exit at all four |

## Runtime profiles

- **Hosted processes** (default): `parallel` bindings and
  `stdlib/Par.ax` pools lower to forked processes; each child has its
  own address space and arena. No behaviour in this profile depends on
  threads.
- **Hosted threads** (`--threads`): bindings lower to pthreads with
  per-thread arenas; ten thread-local globals in a spawning module
  (`MM-PAR-3`, `check-thread-local.sh`). Refcount updates stay
  non-atomic by design; sharing rules are the checker's, not the
  lowering's.
- **Freestanding**: no libc import; the allocator is the emitted
  `mmap`/static-arena runtime. Behavioural evidence is E1 only.

## Known configuration gaps

- §12a (thread-arena VmSize) needs Linux procfs: SKIP on H3.
- `timeout(1)` is absent from the macOS runner image, so §12b/§12c
  fail there on the harness rather than on the property; they pass on
  H1/H2 and locally with a compatible `timeout` on PATH.
- Sanitizer, race-detector, coverage, and fault-injection runs exist
  nowhere yet (R-E1, R-C3 open).
