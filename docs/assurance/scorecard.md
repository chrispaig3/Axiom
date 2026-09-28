# Scorecard

What has landed, with the command or fixture that shows it. Every row
either has evidence or is open with a requirement ID; nothing is "in
progress". The full matrix is in
[requirements.md](requirements.md), and
[configurations.md](configurations.md) defines the H1, H2, H3 and E1
configuration IDs. Figures come from the commit that adds this page,
unless a row names another.

## Guarantees enforced

| Claim | Evidence |
|---|---|
| A recovery point gets a single, correct trap answer (R-A1) | `tests/stdlib/522-parallel-recover.ax`; `PATH=<with-timeout>:$PATH scripts/check-parallel.sh` §12b: 69 checks pass, with §12a skipped on Darwin |
| No child outlives its scope on abort, trap, return or end (R-A2) | Same gate: `kill -0` on the recorded pids |
| Join and spawn failures surface as status 78, never as success (R-A3) | Same gate: `foreign 78` in every §12c probe |
| Thread arenas are returned, so 6,000 threads hold VmSize flat (R-A4) | §12a on H1 and H2 (6.16 GB was mapped before the fix) |
| The allocator refuses negative sizes and sizes it can't hold (R-A5) | The `6527bea0` fixtures |
| The sixteen `Unsafe` primitives are refused under `no-unsafe` and `pure`, and a declaration that calls one says `effect(unsafe)` (R-A6) | `tests/diagnostics/1010-unsafe-primitives.ax` (all three renderings); fifteen stdlib wrappers carry `effect(unsafe)`; `bash scripts/check-diagnostics.sh`: 245 pass |
| Links in dead blocks can't be decremented as counts (R-A7) | `tests/stdlib/521-release-filed.ax`; the `MM-LIFE-2k` release path |
| Foreign joins are refused before waiting, and the owner still joins (R-A8) | §12c: `foreign 78 status 123 answer 42`, for proc and thread × raising and checked |
| Count exhaustion traps with 70 before the write, and is recoverable (R-A9) | `tests/stdlib/527-retain-overflow.ax` (optstable 0–3); the model's `exhaust` ablation |
| `vecSet` traps with 77 before it mutates (R-B1) | `tests/stdlib/525-vec-set-bounds.ax`; `bash scripts/run-stdlib-tests.sh 525` |
| Pool handles are O(min(n,w)), with one checked-join cell (R-B2) | `tests/stdlib/523-par-pool-bounded.ax`; `bash scripts/run-stdlib-tests.sh 523` (optstable 0–3) |
| `MM-RGN-1…7` are normative, with H and P markers (R-B3) | `memory-model.md` §3.6; `bash scripts/check-region-scope.sh check-region-escape.sh …` |
| Obligation dispositions are registered (R-B4) | [memory-audit.md](memory-audit.md); `bash scripts/check-doc-drift.sh` |
| No `Vec` is shared between `--threads` siblings (R-C1) | `tests/diagnostics/656-parallel-container-capture.ax`; row 5 of `642`; `471` builds inside |
| A bounded channel carries every word once between bindings, in both lowerings, blocking in the kernel (R-C2a) | `tests/stdlib/528-chan.ax`; `bash scripts/check-chan.sh`: 15 pass on H3 |
| Atomics lower to their ordering instructions on 7 targets × 4 levels. The SB, MP and counter litmus tests are clean on two threads, beside controls that show the forbidden outcomes (R-C3) | `bash scripts/check-atomics.sh`: 69 pass on H3 (`tests/litmus/atomics.ax`, `tests/stdlib/440-atomics.ax`) |
| Happens-before, the meaning of the atomics and the data-race boundary are stated normatively (R-C4) | `docs/memory-model.md` `MM-PAR-9`; the R-C3 evidence plus `check-parallel.sh` |
| The executable allocator, arena and region model agrees with the runtime (R-E1, model half) | `scripts/lib/runtime-model.py`; `bash scripts/check-runtime-model.sh`: 13 pass (selftest, 18 trace builds at opt 0 and 3, canary, hand control, 5 ablations) |
| Seeded compiler fuzzing, on the mutants run: `check` never dies by a signal, trap status or hang, and never refuses without a code. JSON refusals are well formed, and accepted programs emit IR that `llc` accepts (R-E1, fuzzing half) | `scripts/lib/fuzz.py`; `bash scripts/check-fuzz.sh`: 28 pass on H3. 600 mutants from seed 20260927 in 32 s; a planted wrapper compiler's seven failure kinds reported; 8 reproducers replayed (2 fixed crashes pass, 6 open defects still fail as recorded). `--long` runs 6,000 mutants |

## Open defects and gaps

- R-C2 (plan F12): there is no mutex, timed wait or cancellation, and
  only words cross a join or a channel. R-C2a limits: no fairness,
  FreeBSD spins, and the `Int` handle is freed by obligation.
- R-C4 limits: a misaligned atomic raises SIGBUS rather than a trap
  (measured: exit 138). `restrict(no-unsafe)` also refuses `vecPush`,
  so there is no practical, checkable refusal for a call to an
  `effect(unsafe)` wrapper, or for a user `cast` of a word into a
  handle.
- R-C3 limits: litmus families beyond SB, MP and counter (LB, IRIW,
  2+2W) aren't covered, and no LSE-lowered AArch64 code has been
  inspected. A litmus zero is evidence, not proof.
- R-A3 remainder: no dedicated spawn-refused fixture.
- R-E1 remainder: no sanitizers or race detectors. The fuzzer found
  six defects that are still open (`tests/fuzz/MANIFEST`): duplicate
  parameters, value-less names reaching codegen three ways, and
  ill-formed UTF-8 in JSON diagnostics. `--long` fuzzing isn't
  scheduled. `build`, `run`, `fmt`, the LSP and the REPL aren't fuzzed,
  and there is no miscompilation oracle.
- `MM-PAR-7` stated limits: reparented grandchildren, uninterruptible
  sweeps and unmapped-handle words (`MM-PAR-8`, planned).
- R-B5 (`MM-FFI-7`) is stated but not checked.
- R-B2 budgets are allocator-mark measurements on one shape, not RSS
  or an asymptotic proof.
- `stdlib/Task.ax` doesn't exist yet (plan §3). `stdlib/Chan.ax` has
  landed (R-C2a).
- R-D1 and R-D2: no checked restricted profile, no resource report,
  no QEMU execution, and no MMIO, interrupt or DMA demonstrator.

## Verified configurations

H1, H2 and H3 run in CI. E1 is emission only. Local full runs on
H3-class hardware:

| Gate | Result |
|---|---|
| `check-parallel.sh` | 69/69, with a `timeout` shim (§12a skipped) |
| `check-diagnostics.sh` | 245/245 |
| `check-render-selfhost.sh` | 238/238 |
| `run-stdlib-tests.sh 527` | Pass with optstable |
| `check-runtime-model.sh` | 13/13 |
| `check-atomics.sh` | 69/69 |
| `check-chan.sh` | 15/15 |
| `check-fuzz.sh` | 28/28, and `--long` over 6,000 mutants |
| `check-doc-drift.sh` | Green |

`timeout(1)` is missing from the macOS image, so §12b and §12c fail
there on the harness. Execution on freebsd, windows and darwin-x86_64
is unverified everywhere.

## Memory bounds (measured, not proven)

- `tests/stdlib/523-par-pool-bounded.ax`: 256 submissions at width 3
  fit in 6 KiB (words) and 14 KiB (checked) of parent-arena growth. The
  previous shape took 8,432 and 24,816 bytes on the same input. The
  fixture fails closed if marks leave their chunk or the cursor moves
  backwards.
- §12a: 6,000 thread bindings hold VmSize flat. Before the fix,
  VmSize reached 6,164,156 kB.

## Qualification gaps

Everything in R-E2 is open. There is no hazard or threat analysis, no
trusted-component list beyond the seed and toolchain closure, no
coverage evidence, no safety manual and no support policy.
[qualification.md](qualification.md) is a strategy skeleton only.
Nothing is approved.
