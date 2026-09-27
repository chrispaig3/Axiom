# Requirements matrix

Each guarantee names its normative rule, the implementation that
carries it, who is responsible for it, the evidence that checks it,
the configurations it holds on, and the gaps that remain. Status
words are plan.md's: implemented, verified, qualification-ready,
approved. Nothing here is approved.

Configurations are [configurations.md](configurations.md) IDs: `H1`
is hosted linux-x86_64, `H2` hosted linux-aarch64, `H3` hosted
darwin-aarch64, `E1` the freestanding emitter check. A gate that runs
on all three CI runners covers H1–H3; a gate that needs procfs or a
behaviour this host cannot show is marked with where it was actually
observed.

## Milestone A — baseline and correctness fixes

| ID | Guarantee | Rule / implementation | Owner | Evidence | Configs | Gaps |
|---|---|---|---|---|---|---|
| R-A1 | A forked binding that traps inside a recovery point answers the trap status at the arming call, once, with no duplicate output | `MM-PAR-7`; child starts disarmed with an empty registry; raising join re-raises through the parent's recovery point (`emitParProc`) | compiler/runtime | `tests/stdlib/522-parallel-recover.ax`, gate §12b abort arm | H1–H3 | grandchildren of a killed child are reparented, not swept |
| R-A2 | An abort, an unrecovered trap, a returning `main`, and a finishing child leave no child running or unreaped | `MM-PAR-7`; per-thread child registry, three sweep sites | runtime | `scripts/check-parallel.sh` §12b (`kill -0` on recorded pids) | H1–H3 | a sweep over a thread that never finishes never finishes |
| R-A3 | A failing `wait4` (other than `EINTR`), an ignored `pthread_join` answer, and a refused spawn surface as status 78, never as success | `MM-PAR-7`; join paths, spawn path | runtime | §12b trap arm (exit 72 path exercises the re-raise; 78 is `parallel: could not join`) | H1–H3 | the spawn-refused path has no dedicated failing-spawn fixture |
| R-A4 | Thread churn holds address space flat: a finished thread's arena is unmapped | `MM-PAR-6a` (`emitParThread` teardown) | runtime | gate §12a: 600 and 6,000 bindings, VmSize flat | H1, H2 (procfs; SKIP on H3) | unverified on H3 and on freebsd/windows runners |
| R-A5 | `axiom_alloc` refuses a negative size; a size no address space can hold is out-of-memory | `MM-ALLOC-7a` | runtime | plan F4 probe; fixtures from `6527bea0` | H1–H3 | — |
| R-A6 | The sixteen `Unsafe` primitives are refused under `restrict(no-unsafe)` and `pure`; the declaration calling one says `effect(unsafe)` | `MM-EXEC-9c`; `isUnsafePrim`, `AX3049`/`AX3010`/`AX3073` | compiler | `tests/diagnostics/1010-unsafe-primitives.ax` (all three renderings); fifteen stdlib wrappers claimed; `check-diagnostics.sh` 245/245 | H1–H3 | claimed declarations are checked only for the claimed effect (`AX3073`/`AX3042` silence half, stated in `checkUndeclaredUnsafe`) |
| R-A7 | A dead block's count word holds an encoded free-list link; a second release cannot decrement a pointer | `MM-LIFE-2k`; release path | runtime | `tests/stdlib/521-release-filed.ax`; codegen release path | H1–H3 | — |
| R-A8 | A join from a thread that did not spawn the handle is refused (78) before waiting or writing a status cell; the owner's later join still succeeds | `MM-PAR-7` registry ownership; `__axiom_par_check_owner` at every join entry | runtime | gate §12c, all four proc/thread × raising/checked probes (`foreign 78 status 123 answer 42`) | H1–H3 | a handle whose page was already unmapped is a dangling address (`MM-PAR-8`, planned) |
| R-A9 | A retain past the 2^63-1 count limit traps 70 before writing the header, recoverably | `MM-LIFE-2l`; retain path + `__axiom_refcount_exhausted` | runtime | `tests/stdlib/527-retain-overflow.ax` (`.optstable` pins --opt 0–3); model `exhaust` witness + ablation (`check-runtime-model.sh` §5) | H1–H3 | the boundary is fault-injected, never reached by retaining |

## Milestone B — ownership and safe interfaces

| ID | Guarantee | Rule / implementation | Owner | Evidence | Configs | Gaps |
|---|---|---|---|---|---|---|
| R-B1 | `vecSet` traps 77 on an out-of-range index before mutating the slot, like `vecGet` | `stdlib/Vec.ax` bounds check | stdlib | `tests/stdlib/525-vec-set-bounds.ax`, `070-vec.ax` | H1–H3 | — |
| R-B2 | The process pool keeps O(min(n, w)) handle storage and one reusable checked-join cell; results stay O(n) in submit order | `stdlib/Par.ax` ring + shared cell | stdlib | `tests/stdlib/523-par-pool-bounded.ax` (6/14 KiB budgets reject the old 8,432/24,816-byte shape; `.optstable` pins --opt 0–3) | H1–H3 | budgets are allocator-mark measurements on one input shape, not RSS or asymptotic proof; spawn failures still raise through the runtime and bypass pool cleanup |
| R-B3 | `MM-RGN-1…7` are normative in `memory-model.md` §3.6 with H/P markers; the region/escape refusals fire and the accepted shapes keep compiling | §3.6; `rgnCheckAll`, `rgTyScalar`, `emitRegion` | compiler | diagnostics 630/631/645–648/653, stdlib 168/479/468/479–484, `check-region-*.sh` with ablations | H1–H3 | heap-result promotion and typed sibling task regions stay planned (P) |
| R-B4 | Every program obligation carries a disposition: static check, dynamic check, or explicit unsafe boundary | §0.2; [memory-audit.md](memory-audit.md) register | docs + compiler/runtime | `check-doc-drift.sh` holds the register's references; each row names its gate | H1–H3 | dispositions are review claims; no mechanized model checks them |
| R-B5 | A `Foreign` captured by a thread is the foreign side's to make safe | `MM-FFI-7` (program obligation) | programmer | stated; no positive/negative fixture | H1–H3 | unenforced by any check |

## Milestone C — typed concurrency (partial)

| ID | Guarantee | Rule / implementation | Owner | Evidence | Configs | Gaps |
|---|---|---|---|---|---|---|
| R-C1 | No `Vec` shared by reference between `--threads` siblings (plan F11) | `MM-PAR-6`; `capReport` + `capTyIsVec` refuse class-0 containers | compiler | `tests/diagnostics/656-parallel-container-capture.ax` (direct, aliased, nested, struct-wrapped); `642` row 5; `471-parallel-trap.ax` builds inside | H1–H3 | the refusal is by head constructor after alias expansion; a `Vec` behind an unresolved type variable is refused by the class rule instead |
| R-C3 | The five atomic primitives lower to their sequentially consistent instructions on x86-64 and AArch64 at every `--opt`, and two threads never show an outcome sequential consistency forbids in the store-buffering, message-passing and counter families | `MM-PAR-1` atomics clause; `emitPrimAtomic` (`seq_cst` IR, no target arm) | compiler | `scripts/check-atomics.sh` §1: ordering instructions counted against `tests/stdlib/440-atomics.ax`'s uses, 7 targets × `-O0`…`-O3`, a no-atomics control clean; §2: five IR weakenings each turn §1 red, and the x86-64 load is measured invisible; §3: `tests/litmus/atomics.ax` under `--threads`, 3 × 500,000 rounds per row per level, with `sb plain` and `add split` controls required to show the forbidden outcome | §1 all seven targets (emission); §3 H1–H3 | a litmus zero is evidence on the rounds run, not proof; only SB, MP and counter (no LB, IRIW, 2+2W); AArch64 is inspected as LL/SC because the IR names no LSE-capable CPU; at `-O0` AArch64 lowers every RMW with `ldaxr`/`stlxr` whatever its ordering, so §1's `-O0` RMW rows discriminate nothing; the `mp plain` control is reported, not required, because x86 hardware never reorders it |
| R-C4 | Memory ordering between bindings is stated: happens-before is program order, spawn, join and the seq_cst atomics, and nothing else; a data race is defined as never harmless; the safe-language guarantee names its exact boundary | `MM-PAR-9`; `__axiom_par_spawn_thread`/`join_thread` (`pthread_create`/`pthread_join`), `__axiom_par_spawn_proc`/`join_proc` (`fork`, `MAP_SHARED`, `wait4`) | compiler/runtime (edges); programmer (the two holes) | `check-atomics.sh` (atomic edge, publication, litmus); `check-parallel.sh` (both lowerings, joins); diagnostics 642/643/644/656 (captures); `check-thread-local.sh`; misaligned-atomic probe measured SIGBUS (exit 138) across a 16-byte granule on H3 | H1–H3 | spawn/join edges rest on POSIX and the kernel's exit/wait path, cited not tested; an 8-byte alignment precondition is stated, not trapped; `restrict(no-unsafe)` also refuses ordinary `Vec` code, so the unsafe-wrapper call and a user `cast` of a word into a handle have no practical checkable refusal |

## Open (milestones C–E)

| ID | Guarantee | Status |
|---|---|---|
| R-C2 | Mutex, bounded channel, timeout, cancellation; typed results by explicit serialization with a per-task byte bound | open: only a word crosses a join; platform-constant fragments in `.claude/worktrees/` agent dirs do not stand alone (no `Shared`/`Chan`/`Task`, no `Sys.ax` branches) |
| R-D1 | Checked restricted profile with transitive enforcement and a per-function resource report | open; one worktree holds a typecheck fragment referencing undefined profile/MMIO helpers and a missing doc — not integrated |
| R-D2 | Bare-metal image executed under QEMU; MMIO/interrupt/DMA ownership demonstrator | open |
| R-E1 | Executable model with differential harness; seeded compiler fuzzing in CI | partial: model + gate landed (`scripts/lib/runtime-model.py`, `scripts/check-runtime-model.sh`, 13 checks); seeded compiler-input fuzzing in CI still open |
| R-E2 | Hazard/threat analysis, trusted components, tool qualification strategy, coverage, safety manual, support policy | open; strategy skeleton in [qualification.md](qualification.md) |
