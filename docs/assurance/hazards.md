# Hazard analysis

This page lists how Axiom's compiler, emitted runtime and standard
library can fail a system that uses them. For each failure mode it
names the effect a program would see, the controls this repository
has, and what the integrator still has to do. It is one input to a
system safety assessment and can't replace one. Only the system hazard
analysis knows whether a failure mode is catastrophic or harmless, so
severity and acceptability are the integrator's to assign.

The method is a functional failure-mode analysis at the component's
boundary. The contract is [memory-model.md](../memory-model.md),
[reference.md](../reference.md) and
[restricted-profile.md](../restricted-profile.md). Each control listed
names the gate or fixture that exercises it, such as
`scripts/check-task.sh`. A control that exists in prose alone is listed
as an obligation instead. Status words are
[plan.md](plan.md)'s, and nothing here is approved.

## Compiler hazards

The output is not the program that was written.

| ID | Failure mode | Effect in the system | Causes | Controls and evidence | Residual | Integrator obligation |
|---|---|---|---|---|---|---|
| HZ-C1 | Miscompilation: an accepted program compiles to code whose behaviour differs from the source's meaning | Wrong output with no diagnostic. This is the most dangerous class, because nothing signals it | An emitter defect, an optimiser (`opt`/`llc`) defect, or a checker that accepts an ill-typed program | The bootstrap fixpoint (`stage2 == stage3`, `scripts/check-bootstrap.sh`); agreement across `--opt` 0 to 3 on `.optstable` fixtures (`scripts/run-stdlib-tests.sh`); the executable runtime model (`scripts/check-runtime-model.sh`); the stdlib and self-host corpora | No miscompilation oracle beyond these. Fuzzing checks only that `llc` accepts the IR ([verification.md](verification.md)). The fixpoint can't see a defect present in both stages | Verify the executable against its requirements on the target. Take no credit for compiler correctness from this repository alone |
| HZ-C2 | An invalid program is accepted and lowered to IR the toolchain rejects or misreads | A late build failure, which is benign, or HZ-C1 where `llc` accepts the IR | Checker gaps. The fuzzer found eight, all fixed (`tests/fuzz/MANIFEST`) | `scripts/check-fuzz.sh` replays every reproducer as a regression | Mutation fuzzing reaches only the corpus's neighbourhood | Treat a toolchain error on a program `check` accepted as a compiler defect, and report it |
| HZ-C3 | A safety check is silently missing from the object: a bounds, division, count or contract trap | The program continues past a violated invariant, with memory corruption or wrong output | A codegen regression, or an optimiser deleting a check it wrongly proves dead | Trap fixtures at every `--opt` (`tests/stdlib/464-index-trap.ax`, `tests/stdlib/525-vec-set-bounds.ax`, `tests/stdlib/527-retain-overflow.ax`, `scripts/check-contracts.sh`); every new check is shown to fail under an ablation | A check removed by a later change whose fixture changed with it | Fix the configuration's `--opt` level, and re-run the trap fixtures on the frozen configuration |
| HZ-C4 | Two builds of one source differ | Evidence gathered on one binary doesn't apply to the shipped one | Nondeterminism in emission or in the toolchain | `scripts/check-reproducible.sh`; `scripts/build-shared-axc.sh` builds twice and compares the IR | The host toolchain's versions aren't pinned ([trusted-components.md](trusted-components.md)) | Freeze the `llc`, `opt`, `cc` and `ld.lld` versions per configuration and archive them |
| HZ-C5 | A compromised seed or toolchain (a trusting-trust attack) | Arbitrary behaviour in every compiled program | A malicious seed, `llc`, `cc` or Rust crate | `scripts/check-seed-provenance.sh`, `scripts/check-seed-lineage.sh`, `scripts/check-seed-supply-chain.sh` ([bootstrap/THREATS.md](../../bootstrap/THREATS.md)) | `llc`, `cc` and the Rust anchor's author are the trust base | Obtain the toolchain from a controlled source; see [threats.md](threats.md) |
| HZ-C6 | A restriction is claimed and not checked (`restrict`, `isr`, the profile) | A published guarantee the program doesn't keep | An unsound analysis, or a claim the walk can't settle treated as kept | `AX3049` for a refuted claim, `AX3051` and `AX3057` for an unsettled one (an error under `strict`); `scripts/check-report.sh` ablates every profile rule | A claim is only as strong as the effect and call-graph fixpoint. `restrict(no-cast)` is lexical | Use `strict` on every safety-relevant claim. Run the profile and honour its exit status |

## Runtime hazards

The emitted runtime misbehaves.

| ID | Failure mode | Effect | Causes | Controls and evidence | Residual | Integrator obligation |
|---|---|---|---|---|---|---|
| HZ-R1 | Use after free or double free of a heap block | Memory corruption | A release on a dead block, an arena reset under a live reference, or a handle crossing a thread's arena teardown | `MM-LIFE-2k`'s encoded free-list link (`tests/stdlib/521-release-filed.ax`); the reset traps 75 and 76; the `MM-RGN-*` escape refusals; the container-capture refusal (R-C1); the executable model | `cast` of a word into a handle, `__retain`, `__release` and `__call_word`, all in the unsafe layer ([memory-audit.md](memory-audit.md)) | Keep application code out of `effect(unsafe)`, and review every unsafe function the report lists |
| HZ-R2 | Out of memory | Trap 70 and exit, on bare metal through semihosting | Unbounded allocation, or fragmentation: free lists are per size class and memory never returns to the OS | The trap is defined and recoverable; `--heap-ceiling`'s static region; `scripts/check-steady-state.sh`; RP-5 refuses allocation under a steady root | An application whose live set grows | Budget the heap per configuration, use RP-5 for steady-state code, and decide the system's response to status 70 |
| HZ-R3 | Reference count exhaustion | Trap 70 before the header is written | More than 2^63-1 retains | `tests/stdlib/527-retain-overflow.ax` at every `--opt` | Reached only by fault injection | None beyond HZ-R2 |
| HZ-R4 | Stack overflow | A segmentation fault on a hosted target. On bare metal with the MMU off, silent corruption below the stack | Deep recursion, or large frames on the failure path | `scripts/check-stack-depth.sh` for the compiler; the profile's stack bound read from machine code (RP-7) | No guard page on thread stacks is asserted here, and bare metal has no guard region | Run the stack bound on every build, reserve it plus a margin, and consider an MPU region below the stack (not provided) |
| HZ-R5 | A trap with no safe state | The process exits with a status from 70 to 82. A bare-metal image writes its fault registers and exits through semihosting, or stops in `wfi` without a debugger | Any trap, or an unhandled CPU exception on bare metal (81) | The statuses are defined in [memory-model.md](../memory-model.md); recovery points (`MM-EXEC-10`); `scripts/check-recover.sh`; the vector table's fault report (`scripts/check-embedded.sh` A12) | A trap is not a safe state, and the language can't choose one | Define the system's response to every status: restart, degrade or hold a safe state ([safety-manual.md](safety-manual.md)) |
| HZ-R6 | A reclamation latency spike | A pause while a large graph is released | `axiom_release` walks a dead graph iteratively, in time proportional to its size | An iterative worklist, with no recursion, confirmed by the stack bound | Time is proportional to what dies | Keep steady-state code allocation-free (RP-5), so nothing large dies there |

## Concurrency hazards

| ID | Failure mode | Effect | Causes | Controls and evidence | Residual | Integrator obligation |
|---|---|---|---|---|---|---|
| HZ-P1 | A data race on shared memory | Torn or stale values, or corrupted counts | Two bindings touching one word with no happens-before edge | `MM-PAR-9` defines the edges; captures are refused (`AX3064`, R-C1); the atomics are lowered and litmus-tested (`scripts/check-atomics.sh`); the mutex is load-tested beside a control that must lose updates (`scripts/check-task.sh` §1) | A word shared through a `MAP_SHARED` page is the program's to synchronise; a handle freed while another binding uses it is a race the handle table doesn't see | Guard every shared word with `Sync`, `Chan` or the atomics. The restricted profile refuses spawns altogether (RP-4) |
| HZ-P2 | Deadlock or livelock | A binding blocks for ever | A lock held across a wait, locks taken in different orders, or a binding killed holding a channel's lock | Timed forms of every blocking call (`MM-PAR-12`); the mutex finds a dead holder and poisons itself (`MM-PAR-11`, `scripts/check-task.sh` §2); the channel and mutex protocols show no lost wakeup or deadlock in any interleaving the model explores, and a lock-order inversion or a channel pair times out on both sides under the timed calls (`scripts/check-protocol-model.sh`) | No lock ordering is enforced. A channel's lock doesn't notice a dead holder (`MM-PAR-10`). A reentrant lock waits for itself | Design a lock order, use the timed forms where a wait could last for ever, and after a sweep call only `chanFree` on a channel |
| HZ-P3 | Starvation or priority inversion | A binding makes no progress, or a high-priority binding waits on a low-priority holder | No fairness and no priority inheritance in `Sync` or `Chan` | Stated limits of `MM-PAR-10` and `MM-PAR-11`; the channel load test prints each consumer's share | Both are possible by design | Don't rely on either primitive for real-time scheduling; the restricted profile has no threads |
| HZ-P4 | An orphaned child | A process outlives its scope and holds resources | A parent trap, abort or join failure | `MM-PAR-7`'s sweeps and `MM-PAR-13`'s pool (`scripts/check-parallel.sh` §12b, `scripts/check-task.sh` §4, both checked with `kill -0`) | Grandchildren are reparented, and a parent killed from outside runs no sweep | Don't spawn from children, and supervise the process from outside |
| HZ-P5 | Failure reported as success at a join | A crashed task reads as a result | Swallowed wait errors | R-A3: status 78, never success, including a spawn the kernel refuses (`scripts/check-parallel.sh` §12d); a task's failure is an `Err` in its slot (`tests/stdlib/543-task-failures.ax`) | A pool's refused spawn traps rather than answering in its slot | Check every join result |

## Embedded hazards

These apply to `baremetal-aarch64`.

| ID | Failure mode | Effect | Causes | Controls and evidence | Residual | Integrator obligation |
|---|---|---|---|---|---|---|
| HZ-E1 | An MMIO access elided, split or reordered | A misconfigured device | A plain store where a volatile one was needed, or a missing barrier | The volatile primitives at device widths and the AArch64 barriers (`MM-FFI-8`; `scripts/check-embedded.sh` A11 checks that `opt -O2` keeps every volatile access and deletes the plain control) | Ordering against ordinary memory is the program's barrier to insert | Use only the volatile primitives for device registers, and a barrier wherever a device must see ordinary memory in order |
| HZ-E2 | An interrupt handler allocates or blocks | Heap corruption in an interrupted allocation | Allocation in an ISR | `;@axiom:isr` implies `restrict(no-alloc)` (`AX3049`, `scripts/check-isr.sh`); RP-5 | Blocking in an ISR isn't refused: there is no `no-block` restriction | Keep ISRs to volatile access and flags |
| HZ-E3 | Emulator evidence taken for hardware evidence | A property believed true on hardware that was only seen under QEMU | QEMU's TCG models no caches, timing or bus faults | Every QEMU result is labelled as emulator evidence | No hardware validation exists in this repository | Validate on the target hardware |
| HZ-E4 | A hardware fault: a bit flip, an ECC error or a radiation upset | Arbitrary | The physical environment | None. Language memory safety doesn't address hardware faults | Total | Provide ECC, watchdogs, redundancy, scrubbing and a safe-state design at system level |

## Tool hazards

The evidence is wrong.

| ID | Failure mode | Effect | Controls | Residual |
|---|---|---|---|---|
| HZ-T1 | A gate passes vacuously | A property believed verified isn't | Every check is shown to fail under an ablation; planted controls run on every invocation (`scripts/check-fuzz.sh` §4, `scripts/check-report.sh` §5); floors on swept counts | An ablation not run for a check added later |
| HZ-T2 | The stack bound underestimates | Stack overflow in the field | A selftest on hand-answered graphs; path-sum consistency; agreement with `llvm-readobj` on every frame; ablations | The assumptions in [restricted-profile.md](../restricted-profile.md): no forged code pointers, inline assembly within its frame, the interrupt stub not counted |
| HZ-T3 | A platform-specific gate defect, green on one host and wrong on another | A Linux-only failure ships | CI on H1 to H3; the podman Linux battery (`scripts/run-gates-linux.sh`) | FreeBSD, Windows and darwin-x86_64 execution evidence is thin or absent ([configurations.md](configurations.md)) |
