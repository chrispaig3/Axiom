# Scorecard

What has landed, with the command or fixture that shows it. Every
row is either landed-with-evidence or open-with-an-ID; nothing is
"in progress". See [requirements.md](requirements.md) for the full
matrix and [configurations.md](configurations.md) for the H1/H2/H3/E1
IDs. Measured 2026-09-27 at the commit that adds this file unless a
row names another.

## Guarantees enforced

| Claim | Evidence |
|---|---|
| Recovery-point trap answer is single and correct (R-A1) | `tests/stdlib/522-parallel-recover.ax`; `PATH=<with-timeout>:$PATH scripts/check-parallel.sh` §12b — 69 checks pass, 12a SKIP on Darwin |
| No child outlives its scope on abort/trap/return/end (R-A2) | same gate, `kill -0` on recorded pids |
| Join/spawn failures surface as 78, never success (R-A3) | same gate; `foreign 78` in every §12c probe |
| Thread arenas return; 6,000 threads hold VmSize flat (R-A4) | §12a on H1/H2 (was 6.16 GB mapped before the fix) |
| Allocator refuses negative and unholdable sizes (R-A5) | `6527bea0` fixtures |
| Sixteen `Unsafe` primitives refused under `no-unsafe`/`pure` (R-A6) | `tests/diagnostics/1010-unsafe-primitives.ax`; `bash scripts/check-diagnostics.sh` — 244 pass |
| Dead-block links cannot be decremented as counts (R-A7) | `MM-LIFE-2k` release path |
| Foreign joins refused before waiting; owner still joins (R-A8) | §12c: `foreign 78 status 123 answer 42`, proc/thread × raising/checked |
| `vecSet` traps 77 pre-mutation (R-B1) | `tests/stdlib/525-vec-set-bounds.ax`; `bash scripts/run-stdlib-tests.sh 525` |
| Pool handles O(min(n,w)), one checked-join cell (R-B2) | `tests/stdlib/523-par-pool-bounded.ax`; `bash scripts/run-stdlib-tests.sh 523` (optstable 0–3) |
| `MM-RGN-1…7` normative with H/P markers (R-B3) | `memory-model.md` §3.6; `bash scripts/check-region-scope.sh check-region-escape.sh …` |
| Obligation dispositions registered (R-B4) | [memory-audit.md](memory-audit.md); `bash scripts/check-doc-drift.sh` |

## Open defects and gaps

- R-C1 (plan F11): `Vec` shared by reference under `--threads`; `AX3064` sees counted captures only.
- R-C2/R-C3 (plan F12): no mutex/channel/timeout/cancellation; no atomics machine-code inspection or litmus runs.
- R-A6 remainder: `AX3073` reads seven primitives until the next reseed; fifteen stdlib wrappers unclaimed.
- R-A3 remainder: no dedicated spawn-refused fixture. R-A7 remainder: no double-release fixture.
- `MM-PAR-7` stated limits: reparented grandchildren, uninterruptible sweeps, unmapped-handle words (`MM-PAR-8` planned).
- R-B5 (`MM-FFI-7`) is stated and unchecked.
- R-B2 budgets are allocator-mark measurements on one shape, not RSS or asymptotic proof.
- `stdlib/Task.ax` / `stdlib/Chan.ax` do not exist yet (plan §3 names them as the implementation split).

## Verified configurations

H1, H2, H3 via CI; E1 emission-only. Local full runs on H3-class
hardware: `check-parallel.sh` 69/69 (with a `timeout` shim; 12a
SKIP), `check-diagnostics.sh` 244/244, `run-stdlib-tests.sh 523`
pass with optstable, `check-doc-drift.sh` green. `timeout(1)` is
absent from the macOS image, so §12b/§12c fail there on the harness;
freebsd/windows/darwin-x86_64 execution is unverified everywhere.

## Memory bounds (measured, not proven)

- 523: 256 submissions at width 3 fit 6 KiB (words) / 14 KiB
  (checked) of parent-arena growth; the old shape took 8,432 / 24,816
  bytes on the same input. Fixture fails closed if marks leave their
  chunk or the cursor moves backwards.
- §12a: 6,000 thread bindings hold VmSize flat (was 6,164,156 kB).

## Qualification gaps

Everything in R-E2: no hazard/threat analysis, no trusted-component
list beyond the seed+toolchain closure, no coverage evidence, no
safety manual, no support policy. Strategy skeleton only:
[qualification.md](qualification.md). Nothing is approved.
