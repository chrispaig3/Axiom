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
| The twenty-six `Unsafe` primitives are refused under `no-unsafe` and `pure`, and a declaration that calls one says `effect(unsafe)` (R-A6) | `tests/diagnostics/1010-unsafe-primitives.ax` and `tests/diagnostics/1020-unsafe-device-primitives.ax`; `scripts/check-diagnostics.sh`: 270 pass |
| Links in dead blocks can't be decremented as counts (R-A7) | `tests/stdlib/521-release-filed.ax`; the `MM-LIFE-2k` release path |
| Foreign joins are refused before waiting, and the owner still joins (R-A8) | §12c: `foreign 78 status 123 answer 42`, for processes and threads, raising and checked |
| A parameter is read, not called, beside a nullary function of its name; a cast's type operand and a named pattern's binders resolve as written; a module's bare call never reaches the entry file; so an unused declaration changes nothing else (R-A10) | `tests/selfhost/1006-cast-type-operand.ax`, `tests/stdlib/573-entry-name-shadows-import.ax`; `scripts/check-metamorphic.sh`: 350 programs keep the first relation and 186 the shadow relation, seven ablations each red |
| Count exhaustion traps with 70 before the write, and is recoverable (R-A9) | `tests/stdlib/527-retain-overflow.ax` (`.optstable` 0 to 3); the model's `exhaust` ablation |
| A standard-library function that hands the kernel or a raw primitive a word its caller supplied says so as a precondition, and a record a trusted function hands on that way is private to its module (R-B10, steps 1 and 2 of 3) | `tests/stdlib/580-kernel-precondition.ax`; `compat/BREAKING`'s `KeyIn` and `HttpReader` rows |
| `vecSet` traps with 77 before it mutates (R-B1) | `tests/stdlib/525-vec-set-bounds.ax` |
| A million-deep chain is released whole under a 64 KiB stack, and no share is released twice through the safe surface (R-B7) | `tests/stdlib/555-release-deep-chain.ax`, `556-count-balance.ax`; `scripts/check-reclaim-soak.sh` §1 and its recursive-walk ablation |
| Reuse plateaus under a mixed-size soak, a cycle costs exactly its bytes until a reset, resets leave no stale list head, and `__axiom_mem_stat` reads it all (R-B8) | `tests/stdlib/557-cycle-backlog.ax` to `559-reset-metadata.ax`; `scripts/check-reclaim-soak.sh` §2 to §4, with four ablations |
| A recovery point allocates nothing, a contained trap leaves the heap consistent, and a child spawned in the extent is swept (R-B9) | `tests/stdlib/560-recover-record.ax`, `561-failed-operations.ax`; `scripts/check-reclaim-soak.sh` §5 and §6 |
| Pool handles are O(min(n, w)), with one checked-join cell (R-B2) | `tests/stdlib/523-par-pool-bounded.ax` (`.optstable` 0 to 3) |
| `MM-RGN-1…7` are normative, with H and P markers (R-B3) | `memory-model.md` §3.6; the `check-region-*.sh` gates |
| Obligation dispositions are registered (R-B4) | [memory-audit.md](memory-audit.md); `scripts/check-doc-drift.sh` |
| Forging casts and precondition calls require an unsafe declaration; trusted wrappers admit ordinary code under `no-unsafe` (R-B6) | `tests/diagnostics/1040-forging-cast.ax` to `1043-precondition-tag.ax`; `tests/selfhost/1010-trusted-wrapper.ax`; `tests/stdlib/545-no-unsafe-practical.ax` |
| No `Vec` is shared between `--threads` siblings (R-C1) | `tests/diagnostics/656-parallel-container-capture.ax`; row 5 of `642`; `471` builds inside |
| A bounded channel carries every word once between bindings, in both lowerings, blocking in the kernel (R-C2a) | `tests/stdlib/528-chan.ax`; `scripts/check-chan.sh`: 15 pass |
| A channel, mutex, cancellation token or spawn handle is a sealed handle: safe code can't forge one or pass an `Int` or another handle as one, and a freed, forged or rejoined one traps with 85 instead of reading an unmapped page (R-C6, MM-PAR-8) | `tests/diagnostics/1060` to `1066`; `tests/stdlib/570-handle-freed.ax`, `571-handle-table.ax`, `572-spawn-joined-twice.ax`; `scripts/check-handles.sh`: 42 pass, including four ablations |
| A single-bit fault injected into a live channel's handle word traps 85 before the object is touched, at each of the 64 bits, unless the flip spells the other live channel, which the gate predicts from the two words. This is fault injection at the one boundary the runtime checks, not protection from hardware faults (HZ-E4) | `tests/litmus/handle-bitflip.ax`; `scripts/check-handles.sh` §7 at `--opt` 0 and 2, red with the table's compares removed |
| A mutex excludes and refuses every unearned unlock, a dead holder poisons it, every blocking call has a timed form, and tasks answer typed results by serialization with each failure, deadline and cancellation in its slot (R-C2) | `tests/stdlib/540-wait-timeout.ax` to `543-task-failures.ax`; `scripts/check-task.sh`: 69 pass, including eleven ablations and two controls that measure stated limits |
| Atomics lower to their ordering instructions on 7 targets × 4 levels, and with LSE on the three AArch64 targets. The SB, MP, LB, 2+2W, R, S, counter and four coherence litmus tests are clean on two threads, WRC, ISA2 and 3.SB on three and IRIW on four, with SB, MP, R and S also fenced, beside controls that show the forbidden outcomes (R-C3) | `scripts/check-atomics.sh`: 252 pass (`tests/litmus/atomics.ax`, `tests/stdlib/440-atomics.ax`) |
| Happens-before, the meaning of the atomics and the data-race boundary are stated normatively (R-C4) | `docs/memory-model.md` `MM-PAR-9`; the R-C3 evidence plus `scripts/check-parallel.sh` |
| A restricted profile refuses recursion, unfollowable calls, unnamed foreign items, spawns, steady-state allocation, a blocking call under an interrupt handler and unnamed inline assembly across the whole program, enumerates each function's trap statuses, and bounds the stack from AArch64 and x86-64 machine code (R-D1) | `scripts/axiom-report.py`; `scripts/check-report.sh`: 52 pass. `tests/profile/ok-periodic.ax` is bounded at 192 bytes and `tests/embedded/blink.ax` at 320 |
| Device registers are reached at their own width by volatile accesses the optimiser keeps, with AArch64 barriers, and an instruction the target lacks is `AX4008` (R-D2a) | `scripts/check-embedded.sh` A11 |
| A periodic step runs on real timer interrupts within a checked profile and a stack budget, and a DMA driver keeps a contract-checked ownership protocol with an interrupt deadline (R-D2c) | `scripts/check-embedded.sh` A13 and A14, under QEMU with drills that must go red. Emulator evidence, not hardware |
| Inline assembly is refused where it is malformed, emitted only for the target's architecture, kept as a side effect, and an unsafe operation of the declaration holding it; the restricted profile refuses it unless named (R-D2d) | `tests/stdlib/581-inline-asm.ax`, `tests/diagnostics/1044-inline-asm.ax`, `1045-inline-asm-unsafe.ax`; `scripts/check-embedded.sh` A15, with `tests/embedded/asm-el.ax` under QEMU; `scripts/check-report.sh` RP-9 |
| An unhandled CPU exception on bare metal exits 81 naming the fault, and `isr(irq)` binds the IRQ vector (R-D2b) | `scripts/check-embedded.sh` A12: `tests/embedded/fault.ax` under QEMU exits 81 with ESR `0x96000021`. Emulator evidence, not hardware |
| The executable allocator, arena and region model agrees with the runtime, size classes and filed count included (R-E1, model half) | `scripts/lib/runtime-model.py`; `scripts/check-runtime-model.sh`: 15 pass |
| Seeded compiler fuzzing: on the mutants run, `check` never dies by a signal, trap status or hang, never refuses without a code, writes well-formed JSON and terminal-safe reports; accepted programs emit IR that `llc` accepts, format to a fixed point that still checks, and on a sample answer the same at `--opt 0` and `--opt 2` (R-E1, fuzzing half) | `scripts/lib/fuzz.py`; `scripts/check-fuzz.sh`: 46 pass, on 600 mutants from seed 20260927. All twenty-one reproducers are fixed and replayed as regressions |
| ThreadSanitizer reports an unlocked shared word and three ablated synchronisers, and nothing in the mutex, the channel, the pipeline example or the seq_cst litmus rows but `MM-PAR-12`'s documented read, whose suppression hides nothing else on the runs made (R-E1, race detector) | `scripts/check-race.sh`: 32 pass on H3 and on linux-aarch64 in a container; `tests/litmus/tsan-suppressions.txt` |
| The channel, mutex and task-pool protocols are clean in every interleaving of two and three bindings or tasks the model explores, every planted protocol defect is found with its schedule, and the transcription matches the source and a recorded run of the channel (R-E1, protocol model) | `scripts/lib/protocol-model.py`, `scripts/lib/task_model.py`; `scripts/check-protocol-model.sh`: 137 pass, 84 scenarios and 1,309,841 states by default, 107 and 6.95 million with `--long` |
| A binding that dies holding a channel's lock poisons the channel: every waiter answers within about 100 ms, the timed forms answer `chanOwnerDead`, and nothing touches the half-updated ring (AN-10, R-C2) | `tests/stdlib/590-chan-dead-holder.ax` at `--opt` 0 to 3; `scripts/check-chan.sh` §6 in both lowerings, with the holder test and the child look each ablated red |
| A lock-order inversion between two mutexes and two bindings each waiting on the other's channel answer `sysTimedOut` on both sides under the timed calls, and stay deadlocked under the untimed ones until a watchdog ends them; the mutex's starvation is measured, not promised (R-C2, AN-17) | `tests/litmus/liveness.ax`; `scripts/check-protocol-model.sh` §5, both lowerings |
| The qualification-readiness package exists and states its limits (R-E2) | [hazards.md](hazards.md), [threats.md](threats.md), [trusted-components.md](trusted-components.md), [tool-qualification.md](tool-qualification.md), [safety-manual.md](safety-manual.md), [anomalies.md](anomalies.md), [support-policy.md](support-policy.md), [demonstrators.md](demonstrators.md) |

## Open defects and gaps

- AN-39: a function with no signature, called from inside its own
  body or from above its definition, needs its signature (`AX3089`).
  `scripts/check-metamorphic.sh`'s second relation holds it as its one
  known divergence.
- R-C2 limits: no fairness or priority inheritance; the mutex isn't
  reentrant; a dead holder is found only when the kernel says so
  (AN-56); Darwin's clock is the realtime one; FreeBSD spins.
- AN-58 (R-B10 step 3): `__syscallN` isn't in the unsafe set, so
  `restrict(no-unsafe)` accepts a direct syscall, and `sysReadFd`,
  `sysWriteFd`, the path calls, `sysRandomBytes` and the terminal calls
  still take an `Int` buffer unmarked.
- R-D2d limits: `check` doesn't assemble an `asm` template, operands
  are `Int` words in general-purpose registers, and the instructions
  are the declaration's to vouch for.
- R-B6 limits: the checker cannot prove that a trusted wrapper makes
  its raw operations safe, or that a caller meets a stated
  precondition. A buffer typed `Int` is forged without a cast, so no
  tag marks it. Channels, mutexes, cancellation tokens and spawn
  handles are typed, and forging one takes a tagged `cast` (`MM-PAR-8`).
- R-C3 limits: fifteen litmus families run, not the whole catalogue.
  Dependency variants can't be written: Axiom has one ordering, so a
  dependency could only order a racing plain read. The fence rows use
  racing plain accesses, so they measure the compiler and hardware, not
  the language. The LB, IRIW, WRC, ISA2, R, S and 3.SB plain-access
  controls are reported, not required; each family's reordered-program
  control is required instead. The coherence families can have no plain
  control on x86-64 or AArch64, which keep one word coherent for every
  access. The driver never builds LSE code: `llc` picks no LSE CPU for
  any AArch64 target, so the LSE rows inspect code a program only gets
  by asking for the CPU itself. The new families have no ablation of
  their own yet; their controls back them. A litmus zero is evidence,
  not proof.
- R-E1 remainder: the race detector sees threads only, and only the
  interleavings run, so forked bindings and the task pool have none.
  ASan sees globals, not the arena's heap blocks. The LSP and the REPL
  aren't fuzzed, and the miscompilation oracle compares two
  optimisation levels on a sample. The full fuzzing budget runs
  nightly, not per push. The protocol model is a proof about the model
  at two and three bindings and small bounds, not about the
  implementation; the mutex, the timed forms and the task pool have no
  replay, and the pool's clock is the model's.
- `MM-PAR-7` limits: reparented grandchildren and uninterruptible
  sweeps.
- R-C6 limits: a free that races another binding's use of the same
  handle is unchecked, and a `cast` to a handle type forges one.
- R-B5 (`MM-FFI-7`): the checker can't see foreign code, so a
  captured `Foreign`'s thread-safety is unchecked.
- R-B2's budgets are allocator-mark measurements on one shape, not RSS
  or an asymptotic proof.
- R-B8 and R-B9 limits: reuse is bounded by each class's peak, so a
  drifting size mix keeps old bands until a reset. There is no cycle
  collector. A recovery extent doesn't release descriptors, mappings or
  locks (AN-44).

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
| `check-diagnostics.sh` | 270 pass |
| `check-render-selfhost.sh` | 263 pass |
| `check-atomics.sh` | 252 pass |
| `check-chan.sh` | 35 pass |
| `check-task.sh` | 76 pass |
| `check-handles.sh` | 42 pass |
| `check-protocol-model.sh` | 137 pass |
| `check-report.sh` | 52 pass, 0 skipped |
| `check-embedded.sh` | 45 pass, QEMU legs run |
| `check-runtime-model.sh` | 15 pass |
| `check-fuzz.sh` | 46 pass |
| `check-metamorphic.sh` | 15 pass |
| `check-reclaim-soak.sh` | 22 pass |

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
- A reset-free loop keeping 1,000 strings of random length up to
  60,000 bytes live (about 30 MB) peaks at 40,432, 47,104 and 51,392
  KiB after 10^4, 10^5 and 10^6 replacements, and the arena holds 1.7
  times the live bytes. With exact 16-byte classes it peaked at 117,
  267 and 379 MB (`scripts/check-reclaim-soak.sh` §2).
- Two-node knots dropped outside an arena scope cost 64 bytes each,
  7,840 KiB at 10^5 and 64,096 KiB at 10^6; inside a scope reset each
  iteration, 1,632 KiB at both (§3).
- 10,000 recovery points whose thunk answers, traps or nests grow the
  arena by nothing; each fresh mark costs 48 bytes
  (`tests/stdlib/560-recover-record.ax`).

## Timing

These are measured latencies on H3, not bounds.

- A 200 ms timed receive, send or lock answers `sysTimedOut` after 200
  to 203 ms. The gate accepts [200, 1000] ms, because it runs beside
  other gates (`scripts/check-task.sh` §2).
- A cancellation from a sibling binding at 300 ms, with a 100 ms grace,
  ends the pool in about 450 ms (`scripts/check-task.sh` §3).
- In a lock-order inversion, a 200 ms timed lock answers
  `sysTimedOut` on both sides after 201 to 203 ms, and so does a timed
  receive in a channel pair (`scripts/check-protocol-model.sh` §5).
- Four bindings contending for one mutex for 1.5 s made about 1.1
  million acquisitions in each lowering. The largest share was 1.04
  to 1.14 times the smallest, and the longest single wait 3.9 to
  10.4 ms (the same gate).
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

- Since AN-10's lock, a channel call marks the lock with its process
  id. An uncontended send and receive costs 269 ns a word, of which
  about 240 ns is the one `getpid` a call makes, against 22.5 ns
  before. One sender to one receiver, capacity 64, costs 165 ns a
  word, against 840 ns. Both on H3 at `--opt 2`, alike in both
  lowerings (`chan1` and `chan` modes). A cheaper mark needs a process
  id the runtime refreshes after a fork.

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
text. There is no independent review, no MC/DC, no coverage of an
application's object code, and no hardware evidence. The compiler's
own object code has block and decision coverage.
Nothing is approved.
