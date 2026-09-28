# Anomaly log

This page lists the known defects and limitations that affect a user,
one row each, with the evidence that shows them and a workaround. A row
closes only through a commit that names it and a test that fails
without the fix. Closed rows stay, marked with that commit, so you can
read what a given release contained. The process is in
[support-policy.md](support-policy.md).

Severity is the effect on a program that meets the anomaly:

- **W**: a wrong result or memory unsafety is possible;
- **R**: a correct program is refused, or a build fails late;
- **D**: a diagnostic or tool defect with no effect on generated code;
- **L**: a stated limitation.

It isn't a system severity. The integrator assigns that
([hazards.md](hazards.md)).

## Open

| ID | Sev | Summary | Evidence | Workaround |
|---|---|---|---|---|
| AN-8 | L | A misaligned atomic faults with `SIGBUS` (exit 138) instead of trapping | R-C4 in [requirements.md](requirements.md) | Keep atomic words 8-byte aligned |
| AN-9 | L | Grandchildren of a swept child are reparented, not swept, and a sweep over a thread that never finishes never finishes | `MM-PAR-7`'s stated limits | Don't spawn from a binding, and bound every binding's work |
| AN-10 | L | A binding killed while holding a channel's lock leaves it held, and later calls on that channel block, the timed forms included | `MM-PAR-10` | After a sweep, only `chanFree` the channel. The mutex (`MM-PAR-11`) doesn't have this limit |
| AN-12 | L | A spawn the kernel refuses has no dedicated fixture: the 78 path is emitted, not executed | R-A3's gap; `scripts/check-parallel.sh` §12c executes the other status-78 paths | Treat 78 as fatal |
| AN-13 | L | The stack bound reads AArch64 ELF only; x86-64 is unsupported | [restricted-profile.md](../restricted-profile.md) | Bound on an AArch64 configuration |
| AN-14 | L | Integer `+`, `-` and `*` wrap silently. `<<` and `>>` out of range, and `INT_MIN / -1`, are undefined in LLVM's terms | `no-wrap` and `no-untrapped` in [reference.md](../reference.md) | Claim `restrict(no-wrap, no-untrapped)` and use the checked operations |
| AN-15 | L | Waits on FreeBSD spin, because that target has no blocking wait | `MM-PAR-10`, `MM-PAR-12` | None; it costs a core |
| AN-17 | L | Neither the mutex nor the channel is fair or has priority inheritance, so a binding can starve and priority inversion is possible | `MM-PAR-10`, `MM-PAR-11` | Don't rely on either for real-time scheduling |
| AN-18 | L | On Darwin, timed waits and task deadlines use the realtime clock, so a clock step can move them, by at most one 100 ms slice per wait | `MM-PAR-12` | Keep the clock stepped by slewing only, or run deadline-sensitive work on Linux |

## Closed

| ID | Summary | Closed by | Regression |
|---|---|---|---|
| AN-1 | A parameter list naming one variable twice checked OK and failed at `llc` | `79c0be12` | `tests/fuzz/dup-param-llc.axfuzz`; `AX3006` |
| AN-2 | `cast`, `sizeof`, `alignof`, `handle` and the effect names in value position checked OK and failed at `llc` | `79c0be12` | `tests/fuzz/builtin-name-value.axfuzz`; `AX3001`, `AX3013` |
| AN-3 | `(cast T)` with no operand checked OK and failed at `llc` | `79c0be12` | `tests/fuzz/cast-missing-operand.axfuzz`; `AX3013` |
| AN-4 | A one-argument primitive named bare, or applied to nothing, failed at `llc` | `79c0be12` | `tests/fuzz/primitive-value.axfuzz`; `AX3013` |
| AN-5 | `--diagnostic-format json` could write ill-formed UTF-8 | `79c0be12` | `tests/fuzz/json-ax1001-partial-char.axfuzz`, `tests/fuzz/json-restrict-illformed.axfuzz` |
| AN-6 | The human renderer echoed raw control bytes from a source line into the terminal | `79c0be12` | `scripts/check-fuzz.sh`'s terminal-safety check |
| AN-7 | `;@axiom:effect(io, unsafe)` was read as one effect named `io, unsafe`, and `AX3010` said it was missing | `79c0be12` | `AX3076` names the list and asks for one tag per effect |
| AN-11 | No mutex, timed wait, cancellation, or typed transfer across a join | The R-C2 commit | `tests/stdlib/540-wait-timeout.ax` to `543-task-failures.ax`; `scripts/check-task.sh` |
| AN-19 | A double unlock landing between another binding's lock and its guard being drawn was accepted, and released a lock someone else held | The R-C2 commit, before it landed | `scripts/check-task.sh` §2's exact stale-in-window check and the `guard` ablation |
| AN-21 | A grace or deadline near the largest `Int` wrapped negative while it was rounded to microseconds, so a cancelled pool killed its tasks at once | The R-C2 commit, before it landed | `scripts/check-task.sh` §3's largest-grace run and the `micros` ablation |
| AN-16 | Under `--threads`, a trap in one thread ended the process having swept only that thread's registry, so a task pool on a sibling thread left its tasks running | The R-C5 commit | `scripts/check-task.sh` §4's sibling-trap check and §8's `gkill` ablation |
| AN-20 | On Darwin, a thread spawned inside a forked binding or a task crashed that process with `SIGSEGV` (139), because the runtime forked with the raw system call | The R-C5 commit | `tests/litmus/thread-in-fork.ax` and `scripts/check-task.sh` §8's `libcfork` ablation |
| AN-22 | A task that answered was joined at once, so one whose process could not then exit blocked the pool in `wait4` with no deadline enforced | The R-C2 commit; its test landed with R-C5, when Darwin could run it | `scripts/check-task.sh` §3's stuck task and §6's `exitjoin` ablation; `tests/litmus/thread-in-fork.ax` |
| AN-C1 | The fuzzing harness read a refusal whose report held a NUL as a codeless one | `61f1e0ef` | `scripts/check-fuzz.sh` §4's NUL control |
| AN-C2 | Two `check` segmentation faults found by the fuzzer, in the human renderer and the region pass | `878b17be` | `tests/fuzz/render-spanless-cross.axfuzz`, `tests/fuzz/region-nonarrow-sig.axfuzz` |
| AN-C3 | A forked binding that trapped inside a recovery point ran the parent's continuation (F2) | Milestone A | `tests/stdlib/522-parallel-recover.ax` |
| AN-C4 | Thread arenas were never unmapped, and 6,000 threads mapped 6.16 GB (F3) | Milestone A | `scripts/check-parallel.sh` §12a |
| AN-C5 | `axiom_alloc` accepted a negative size (F4) | `6527bea0` | That commit's fixtures |
| AN-C6 | Seven raw primitives escaped the unsafe set (F5) | Milestone A | `tests/diagnostics/1010-unsafe-primitives.ax` |
| AN-C7 | A second release of a filed block decremented a pointer (F6) | Milestone A | `tests/stdlib/521-release-filed.ax` |
| AN-C8 | `vecSet` ignored an out-of-range index (F9) | Milestone B | `tests/stdlib/525-vec-set-bounds.ax` |
| AN-C9 | A `Vec` could be shared by reference between `--threads` siblings (F11) | Milestone C | `tests/diagnostics/656-parallel-container-capture.ax` |
