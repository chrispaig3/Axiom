# Scorecard

This page lists what has landed, each claim with the command or
fixture that shows it. Every row either has evidence or is open with a
requirement ID. Nothing is "in progress". The full matrix is
[requirements.md](requirements.md), and
[configurations.md](configurations.md) defines the configuration IDs
H1, H2, H3 and E1. Figures come from the local full battery on H3 at
the commit that last changed this page, unless a row names another
source.

## Guarantees enforced

| Claim | Evidence |
|---|---|
| A recovery point gets a single, correct trap answer (R-A1) | `tests/stdlib/522-parallel-recover.ax`; `scripts/check-parallel.sh` §12b |
| No child outlives its scope on abort, trap, return or end (R-A2, R-C5) | The same gate, with `kill -0` on the recorded pids; under `--threads`, `scripts/check-task.sh` §4 and its §8 `gkill` ablation |
| Join and spawn failures surface as status 78, never as success (R-A3) | The same gate: `foreign 78` in every §12c probe |
| Thread arenas are returned, so 6,000 threads hold VmSize flat (R-A4) | §12a on H1 and H2 (6.16 GB was mapped before the fix) |
| The allocator refuses negative sizes and sizes it can't hold (R-A5) | The `6527bea0` fixtures |
| The twenty-six `Unsafe` primitives are refused under `no-unsafe` and `pure`, and a declaration that calls one says `effect(unsafe)` (R-A6) | `tests/diagnostics/1010-unsafe-primitives.ax` and `tests/diagnostics/1020-unsafe-device-primitives.ax`; `scripts/check-diagnostics.sh`: 255 pass |
| Links in dead blocks can't be decremented as counts (R-A7) | `tests/stdlib/521-release-filed.ax`; the `MM-LIFE-2k` release path |
| Foreign joins are refused before waiting, and the owner still joins (R-A8) | §12c: `foreign 78 status 123 answer 42`, for processes and threads, raising and checked |
| Count exhaustion traps with 70 before the write, and is recoverable (R-A9) | `tests/stdlib/527-retain-overflow.ax` (`.optstable` 0 to 3); the model's `exhaust` ablation |
| `vecSet` traps with 77 before it mutates (R-B1) | `tests/stdlib/525-vec-set-bounds.ax` |
| Pool handles are O(min(n, w)), with one checked-join cell (R-B2) | `tests/stdlib/523-par-pool-bounded.ax` (`.optstable` 0 to 3) |
| `MM-RGN-1…7` are normative, with H and P markers (R-B3) | `memory-model.md` §3.6; the `check-region-*.sh` gates |
| Obligation dispositions are registered (R-B4) | [memory-audit.md](memory-audit.md); `scripts/check-doc-drift.sh` |
| No `Vec` is shared between `--threads` siblings (R-C1) | `tests/diagnostics/656-parallel-container-capture.ax`; row 5 of `642`; `471` builds inside |
| A bounded channel carries every word once between bindings, in both lowerings, blocking in the kernel (R-C2a) | `tests/stdlib/528-chan.ax`; `scripts/check-chan.sh`: 15 pass |
| A mutex excludes and refuses every unearned unlock, a dead holder poisons it, every blocking call has a timed form, and tasks answer typed results by serialization with each failure, deadline and cancellation in its slot (R-C2) | `tests/stdlib/540-wait-timeout.ax` to `543-task-failures.ax`; `scripts/check-task.sh`: 69 pass, including eleven ablations and two controls that measure stated limits |
| Atomics lower to their ordering instructions on 7 targets × 4 levels. The SB, MP, LB, 2+2W and counter litmus tests are clean on two threads and IRIW on four, beside controls that show the forbidden outcomes (R-C3) | `scripts/check-atomics.sh`: 96 pass (`tests/litmus/atomics.ax`, `tests/stdlib/440-atomics.ax`) |
| Happens-before, the meaning of the atomics and the data-race boundary are stated normatively (R-C4) | `docs/memory-model.md` `MM-PAR-9`; the R-C3 evidence plus `scripts/check-parallel.sh` |
| A restricted profile refuses recursion, unfollowable calls, unnamed foreign items, spawns and steady-state allocation across the whole program, and bounds the stack from AArch64 machine code (R-D1) | `scripts/axiom-report.py`; `scripts/check-report.sh`: 36 pass. `tests/profile/ok-periodic.ax` is bounded at 192 bytes and `tests/embedded/blink.ax` at 320 |
| Device registers are reached at their own width by volatile accesses the optimiser keeps, with AArch64 barriers, and an instruction the target lacks is `AX4008` (R-D2a) | `scripts/check-embedded.sh` A11 |
| A periodic step runs on real timer interrupts within a checked profile and a stack budget, and a DMA driver keeps a contract-checked ownership protocol with an interrupt deadline (R-D2c) | `scripts/check-embedded.sh` A13 and A14, under QEMU with drills that must go red. Emulator evidence, not hardware |
| An unhandled CPU exception on bare metal exits 81 naming the fault, and `isr(irq)` binds the IRQ vector (R-D2b) | `scripts/check-embedded.sh` A12: `tests/embedded/fault.ax` under QEMU exits 81 with ESR `0x96000021`. Emulator evidence, not hardware |
| The executable allocator, arena and region model agrees with the runtime (R-E1, model half) | `scripts/lib/runtime-model.py`; `scripts/check-runtime-model.sh`: 13 pass |
| Seeded compiler fuzzing: on the mutants run, `check` never dies by a signal, trap status or hang, never refuses without a code, writes well-formed JSON and terminal-safe reports; accepted programs emit IR that `llc` accepts, format to a fixed point that still checks, and on a sample answer the same at `--opt 0` and `--opt 2` (R-E1, fuzzing half) | `scripts/lib/fuzz.py`; `scripts/check-fuzz.sh`: 43 pass, on 600 mutants from seed 20260927. All seventeen reproducers are fixed and replayed as regressions |
| ThreadSanitizer reports an unlocked shared word and three ablated synchronisers, and nothing in the mutex, the channel, the pipeline example or the seq_cst litmus rows but `MM-PAR-12`'s documented read, whose suppression hides nothing else on the runs made (R-E1, race detector) | `scripts/check-race.sh`: 32 pass on H3 and on linux-aarch64 in a container; `tests/litmus/tsan-suppressions.txt` |
| The qualification-readiness package exists and states its limits (R-E2) | [hazards.md](hazards.md), [threats.md](threats.md), [trusted-components.md](trusted-components.md), [tool-qualification.md](tool-qualification.md), [safety-manual.md](safety-manual.md), [anomalies.md](anomalies.md), [support-policy.md](support-policy.md), [demonstrators.md](demonstrators.md) |

## Open defects and gaps

- R-C2 limits: no fairness or priority inheritance; the mutex isn't
  reentrant; a channel's lock doesn't notice a dead holder; Darwin's
  clock is the realtime one; FreeBSD spins.
- R-C4 limits: `restrict(no-unsafe)` also refuses `vecPush`, so there
  is no practical, checkable refusal for a call to an `effect(unsafe)`
  wrapper, or for a user `cast` of a word into a handle.
- R-C3 limits: six litmus families run, not the whole catalogue (no
  WRC, ISA2 or coherence tests). The LB and IRIW plain-access controls
  are reported, not required, because H3 shows LB never and IRIW only
  in bursts; each family's reordered-program control is required
  instead. No LSE-lowered AArch64 code has been inspected. A litmus
  zero is evidence, not proof.
- R-E1 remainder: the race detector sees threads only, and only the
  interleavings run, so forked bindings and the task pool have none.
  ASan sees globals, not the arena's heap blocks. The LSP and the REPL
  aren't fuzzed, and the miscompilation oracle compares two
  optimisation levels on a sample. The full fuzzing budget runs
  nightly, not per push.
- `MM-PAR-7` limits: reparented grandchildren, uninterruptible sweeps
  and unmapped-handle words (`MM-PAR-8`, planned).
- R-B5 (`MM-FFI-7`): the checker can't see foreign code, so a
  captured `Foreign`'s thread-safety is unchecked.
- R-B2's budgets are allocator-mark measurements on one shape, not RSS
  or an asymptotic proof.

## Verified configurations

H1, H2 and H3 run the gates in CI. E1 is emission only, plus QEMU runs
where QEMU is installed. The local full battery on H3 passed every
gate but three, and all three were re-run green after their causes
were fixed: re-pinned effect counts, a stray Finder file the install
gate copied, and symbol goldens that listed five new platform
constants.

| Gate | Result on H3 |
|---|---|
| `check-parallel.sh` | 69 pass, §12a skipped (procfs) |
| `check-diagnostics.sh` | 255 pass |
| `check-render-selfhost.sh` | 248 pass |
| `check-atomics.sh` | 96 pass |
| `check-chan.sh` | 15 pass |
| `check-task.sh` | 69 pass |
| `check-report.sh` | 36 pass, 0 skipped |
| `check-embedded.sh` | 35 pass, QEMU legs run |
| `check-runtime-model.sh` | 13 pass |
| `check-fuzz.sh` | 43 pass |

Execution on freebsd, windows and darwin-x86_64 has narrower evidence
([configurations.md](configurations.md)). Nothing has run on
hardware other than the hosted development machines.

## Memory bounds

These are measurements, not proofs.

- `taskFold` over 500, 5,000 and 20,000 tasks of 4 KiB answers peaks at
  1,888 KiB, while `taskMap` keeping the same answers grows by more
  than 8 MiB (`scripts/check-task.sh` §5).
- A channel carrying 60,000 and 600,000 words peaks at 2,016 and 2,048
  KiB (`scripts/check-chan.sh`).
- 10,000 echo-server connections peak at 384 KiB of worker RSS, and
  the unscoped control grows 49-fold (`scripts/check-net.sh`).
- `tests/stdlib/523-par-pool-bounded.ax`: 256 submissions at width 3
  fit in 6 KiB (words) and 14 KiB (checked) of parent-arena growth.
- `scripts/check-parallel.sh` §12a: 6,000 thread bindings hold VmSize
  flat. Before the fix, VmSize reached 6,164,156 kB.

## Timing

These are measured latencies on H3, not bounds.

- A 200 ms timed receive, send or lock answers `sysTimedOut` after 200
  to 203 ms. The gate accepts [200, 1000] ms, because it runs beside
  other gates (`scripts/check-task.sh` §2).
- A cancellation from a sibling binding at 300 ms, with a 100 ms grace,
  ends the pool in about 450 ms (`scripts/check-task.sh` §3).
- A mutex whose holder was killed and reaped answers `syncOwnerDead`
  101 ms later to a timed lock, and at once to an untimed one.

`scripts/bench-concurrency.sh` measures what each primitive costs. Every
figure below is the best of seven runs on H3 at `--opt 2`, with the
median in brackets, and each run checks its own answer.

| Workload | Processes | Threads |
|---|---|---|
| `parallel` spawn and join, per binding | 71.5 µs (73.7) | 15.5 µs (16.0) |
| Mutex lock and unlock, uncontended | 129 ns (129) | 131 ns (132) |
| Mutex lock and unlock, four bindings contending, per operation | 121 ns (124) | 119 ns (120) |
| Channel, one sender to one receiver, capacity 64, per word | 793 ns (963) | 812 ns (911) |

- A task pool at width 8 costs 51 µs of wall time per task with
  64-byte answers, 54 µs with 4 KiB answers and 66 µs with 64 KiB ones,
  whose bytes cross at 992 MB/s.
- A pool of one task, 500 in a row, has a round trip of 180 µs at the
  median, 258 µs at the 99th percentile and 290 µs at worst.
- Of an uncontended lock and unlock's 129 ns, the `getpid` the lock
  makes for its mark (`MM-PAR-11`) is 113 ns when measured alone.

No worst-case execution time is claimed for anything.

## Qualification gaps

The R-E2 package exists and is a starting point, not a qualification.
It was written from AMC 20-193's public text. DO-178C, DO-330, ISO
26262, IEC 61508 and the ECSS standards weren't consulted in licensed
text. There is no independent review, no MC/DC or decision coverage,
no coverage of an application's object code, and no hardware evidence.
Nothing is approved.
