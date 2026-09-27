# Assurance programme: plan and acceptance criteria

This is the working plan for bringing Axiom's memory model,
concurrency, parallelism, compiler and runtime to a defensible
production standard, and for collecting the evidence that a
safety-critical user would need. It is a plan, so it states what is
intended; what has landed is recorded in
[scorecard.md](scorecard.md) with the command or fixture that shows it.

Four words are kept apart everywhere in this directory:

- **Implemented** — the code exists in this tree.
- **Verified** — a named gate, fixture or analysis checks the property,
  and the method's limits are stated beside it.
- **Qualification-ready** — the evidence a qualification authority
  would ask for exists for a named configuration.
- **Approved** — an independent, competent assessor has accepted that
  evidence for a specific application, platform, configuration and
  development process. Nothing in this repository is approved, and no
  document here says otherwise.

## 1. Baseline (measured 2026-09-27 at `5cc493f`)

Four read-only inventories and the probes below established the
starting point. Each finding cites the source line or probe that shows
it; the probes are reproduced by the fixtures named when the fix lands.

| # | Finding | Evidence |
|---|---|---|
| F1 | `check-doc-drift.sh` red at HEAD: a prose document listed but never committed, and a stale `.ax` census | fixed by `442d906` |
| F2 | A forked `parallel` binding that traps inside a recovery point jumps to the **parent's** arm site in the child, runs the parent's continuation (duplicate output), and the parent then reads the child's exit 0 as success with answer 0 | probe: `after recover: status 72` printed by the child, `status 1` by the parent |
| F3 | Thread-lowered bindings never return their arena: 6,000 threads leave 6.16 GB of address space mapped (processes: 3.6 MB flat) | probe: `VmSize` 634,556 kB at 600 threads, 6,164,156 kB at 6,000 |
| F4 | `axiom_alloc` accepts a negative size; the bump pointer moves backwards and the next block's header overwrites live data | probe: `(memAlloc -32)` then `(memAlloc 64)` rewrote words 6 and 7 of an earlier block |
| F5 | The `Unsafe` effect misses primitives that dereference, free or call an arbitrary word: `__retain`, `__release`, `__call_word`, the four atomics, `__axiom_arena_reset`; all pass `restrict(no-unsafe)` and `pure` | probe: seven declarations, one refused |
| F6 | A released block's free-list link overwrites its count word, so a second release of a filed block decrements a pointer and corrupts the size-class list | `self_host/codegen.ax` release path; the "never decrements 0" claim holds only before filing |
| F7 | When a join re-raises a child's status, sibling children are neither killed nor reaped; a spawn failure leaks its page and abandons running siblings; a `wait4` error other than `EINTR` is read as success | `emitParProc`, `emitParTrap` |
| F8 | `stdlib/Par.ax` keeps one handle per submission (O(n)) although at most `width` are live, and `parJoinChecked` allocates a cell per join | `Par.ax` `hs`, `parJoinChecked` |
| F9 | `vecSet` silently ignores an out-of-range index where `vecGet` traps 77 | `stdlib/Vec.ax` |
| F10 | Region rules `MM-RGN-1…7` are normative in practice (S2–S6 built and gated) but are written only in a design note, outside the conformance table | `docs/memory-model-v2-design.md` §2–§4 |
| F11 | Under `--threads` a captured `Vec` is shared by reference: `AX3064` refuses counted captures only, so sibling bindings can mutate one container with no synchronisation | `self_host/typecheck.ax` `evScalarName` |
| F12 | No mutex, channel, timeout or cancellation exists; only a word crosses a join; no fuzzing, sanitizer, coverage or executable model exists | inventories |

## 2. Milestones, in dependency order

Each milestone lists what must be true before it is called complete. A
criterion names the command that decides it; one that cannot be run on
the available hardware is recorded as *unverified*, never as passed.

### A. Baseline, contracts, confirmed correctness fixes

- F1–F7 fixed in the compiler and runtime, each with a fixture that
  fails against the pre-fix compiler.
- Programs that must still work: the whole stdlib corpus
  (`scripts/run-stdlib-tests.sh`), the self-host corpus, the bootstrap
  fixpoint (`scripts/bootstrap-from-seed.sh`), `check-parallel.sh`,
  `check-thread-local.sh`, `check-recover.sh`.
- Programs that must be refused: every F5 shape under
  `restrict(no-unsafe)` and `pure`.
- Runtime behaviour under failure: a trapping forked binding inside a
  recovery point answers the trap status at the arming call with no
  duplicate output; an abort or trap exit leaves no child running
  (verified by `kill -0` on recorded pids); thread churn holds address
  space flat.
- Reference configurations and the requirements matrix written
  ([configurations.md](configurations.md), [requirements.md](requirements.md)).

### B. Enforced ownership and safe interfaces

- One authoritative memory contract: `MM-RGN-*` moved into
  [memory-model.md](../memory-model.md) with **H**/**P** markers, the
  reclamation contract between regions and counting stated once, and
  every program obligation given a disposition (static check, dynamic
  check, or explicit unsafe boundary).
- F8–F9 fixed; typed interfaces where raw words cross a supposedly safe
  boundary are listed and the unsafe layer's preconditions written.
- Positive examples that must keep compiling beside each new refusal.

### C. Typed concurrency and parallel execution

- The happens-before relation, publication and data-race semantics of
  `parallel`, the process pool and the atomics stated normatively.
- Typed results across the process boundary by explicit serialization
  with a stated per-task byte bound; per-task `Result`; timeout and
  cancellation that kill and reap; no child outlives its scope.
- A bounded producer/consumer channel with defined blocking and
  end-of-stream.
- Atomics lowering inspected in machine code on x86-64 and AArch64 at
  every `--opt` level; litmus tests executed on the host.
- Bounded handle storage and streaming reduction measured, outputs
  compared against the sequential answer.

### D. Bounded embedded and real-time execution

- A restricted profile whose restrictions are checked transitively,
  with unknown behaviour reported as an obligation rather than passed.
- A compiler resource report: allocation, IO, unsafe, foreign,
  recursion and unresolved calls per function.
- Volatile MMIO access at device widths; an interrupt and DMA
  ownership demonstrator; the bare-metal image executed under QEMU and
  recorded as emulator evidence, not hardware evidence.

### E. Qualification evidence and release readiness

- An executable model of the arena, region and task-lifecycle rules,
  connected to runtime tests by a differential harness.
- Compiler-input fuzzing with a fixed seed budget in CI.
- Hazard and threat analysis, trusted-component list, tool operational
  requirements, qualification strategy per standard, verification
  independence, configuration management, known limitations, safety
  manual, support policy, and the scorecard.

## 3. Ownership

One integration owner merges every change, keeps the census and gate
counts, and runs the comprehensive battery before a milestone is
declared. Independent investigation and review run as parallel agents;
implementation is split by file ownership so no two agents edit the
same module: compiler and runtime (`self_host/`), the concurrency
standard library (`stdlib/Par.ax`, new `stdlib/Task.ax`,
`stdlib/Chan.ax`), and verification tooling (`scripts/`, new
`scripts/lib/*.py`). Agent work is AI-assisted engineering; it is not
independent assessment in any standard's sense
([qualification.md](qualification.md) §4).
