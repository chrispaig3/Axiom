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
| AN-9 | L | Grandchildren of a swept child are reparented, not swept, and a sweep over a thread that never finishes never finishes | `MM-PAR-7`'s stated limits | Don't spawn from a binding, and bound every binding's work |
| AN-10 | L | A binding killed while holding a channel's lock leaves it held, and later calls on that channel block, the timed forms included | `MM-PAR-10` | After a sweep, only `chanFree` the channel. The mutex (`MM-PAR-11`) doesn't have this limit |
| AN-14 | L | Integer `+`, `-` and `*` wrap silently. `<<` and `>>` out of range, and `INT_MIN / -1`, are undefined in LLVM's terms | `no-wrap` and `no-untrapped` in [reference.md](../reference.md) | Claim `restrict(no-wrap, no-untrapped)` and use the checked operations |
| AN-15 | L | Waits on FreeBSD spin, because that target has no blocking wait | `MM-PAR-10`, `MM-PAR-12` | None; it costs a core |
| AN-17 | L | Neither the mutex nor the channel is fair or has priority inheritance, so a binding can starve and priority inversion is possible | `MM-PAR-10`, `MM-PAR-11` | Don't rely on either for real-time scheduling |
| AN-37 | D | `axiom symbols` prints an unsigned function's fresh type variables with a global counter, so `(Int -> (_t3 -> _t3))` becomes `(Int -> (_t13 -> _t13))` when unrelated declarations are added | `tests/selfhost/770-over-application.ax`'s `adder`, with ten functions appended | Give a function a `::` signature; `scripts/lib/metamorphic.py` compares fresh variables by order of appearance |
| AN-39 | L | A function with no `::` signature can't be called from inside its own body or from a declaration above it: declarations are checked in the order they are written. `(fn (main) (twice 4))` above `(fn (twice x) (* x 2))` is refused, and so is any recursive function without a signature. It is `AX3089`, which asks for the signature; it was `AX3004`, "expected function type, found `_a`" | `tests/diagnostics/1032-signature-needed.ax`; `scripts/check-metamorphic.sh` §2b (`tests/selfhost/770-over-application.ax` reversed) | Write the signature |
| AN-18 | L | On Darwin, timed waits and task deadlines use the realtime clock, so a clock step can move them, by at most one 100 ms slice per wait | `MM-PAR-12` | Keep the clock stepped by slewing only, or run deadline-sensitive work on Linux |
| AN-44 | L | A descriptor, shared mapping or lock taken inside a recovery extent stays taken when a trap aborts it | `MM-ALLOC-23`; `scripts/check-reclaim-soak.sh` §5 | Acquire outside the point, or release before anything in the extent can trap |
| AN-45 | L | A closure a function receives as an argument and returns is never released: 32 bytes a call, 64 when it is wrapped once more | A loop of `(keep (lambda (x) (+ x k)))` with `(fn (keep f) f)`, read with `__axiom_mem_stat` | Scope such loops in an arena, or keep the closure in the caller |
| AN-48 | L | A free that races another binding's operation on the same channel, mutex or cancellation token is a data race: the handle table catches every use ordered after the free, not one already in flight | `MM-PAR-8`, §10.7 of [memory-model.md](../memory-model.md) | Free a handle only after the `parallel` form that used it |

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
| AN-8 | A misaligned atomic faulted with `SIGBUS` (exit 138) on AArch64 and was a split-lock access on x86-64, instead of trapping | The R-C4 commit | `tests/stdlib/544-misaligned-atomic.ax`; `scripts/check-trap-statuses.sh` |
| AN-12 | A spawn the kernel refuses had no test: the 78 path was emitted and never executed | The R-A3 commit | `scripts/check-parallel.sh` §12d |
| AN-16 | Under `--threads`, a trap in one thread ended the process having swept only that thread's registry, so a task pool on a sibling thread left its tasks running | The R-C5 commit | `scripts/check-task.sh` §4's sibling-trap check and §8's `gkill` ablation |
| AN-20 | On Darwin, a thread spawned inside a forked binding or a task crashed that process with `SIGSEGV` (139), because the runtime forked with the raw system call | The R-C5 commit | `tests/litmus/thread-in-fork.ax` and `scripts/check-task.sh` §8's `libcfork` ablation |
| AN-22 | A task that answered was joined at once, so one whose process could not then exit blocked the pool in `wait4` with no deadline enforced | The R-C2 commit; its test landed with R-C5, when Darwin could run it | `scripts/check-task.sh` §3's stuck task and §6's `exitjoin` ablation; `tests/litmus/thread-in-fork.ax` |
| AN-23 | A `match` answered its last arm's type and compared no arm with another, so a function declared `Int` could return a `String` arm's address, differently at each `--opt` level | The P4 and P5 commit | `tests/fuzz/match-arms-disagree.axfuzz`; `tests/diagnostics/1021-match-arms-disagree.ax` |
| AN-24 | `pub` written twice, or inside an expression, was skipped by the parser, so `check` accepted a file `fmt` refused with no code | The P4 and P5 commit | `tests/fuzz/pub-twice.axfuzz`; `tests/diagnostics/1022-pub-twice.axbad`, `1023-pub-in-expression.axbad` |
| AN-25 | A type in expression position that couldn't be converted, such as a literal nested in `(:: e (Vec 2))` or an `if`, became the wildcard and typed the value as anything | The second P4 commit | `tests/fuzz/ascription-literal-arg.axfuzz`; `tests/diagnostics/1024-type-part-not-a-type.axbad` |
| AN-26 | A `data` field type that didn't parse became the wildcard, and a struct field's types after the first were skipped | The second P4 commit | `tests/fuzz/struct-field-one-type.axfuzz`; `tests/diagnostics/1025-data-field-not-a-type.axbad`, `1027-struct-field-one-type.axbad` |
| AN-27 | `()` after bare type parameters, or any group opening with a lowercase name, was read as a type-parameter list, and what else it held was skipped | The second P4 commit | `tests/fuzz/data-params-then-list.axfuzz`, `tests/fuzz/data-params-names-only.axfuzz`; `tests/diagnostics/1026-data-params-then-list.axbad` |
| AN-28 | `fmt` refused, with no code, programs `check` accepts: a cast with surplus operands, an operator name outside stage0's list, and a field access at the nesting limit | The second P4 commit | `tests/fuzz/cast-surplus-flat.axfuzz`, `tests/fuzz/operator-name-template.axfuzz`, `tests/fuzz/deep-field-chain.axfuzz` |
| AN-29 | A `;@axiom:` tag with no declaration after it was dropped with no word, and a top-level function spelled like an operator compiled though no call could reach it | The third P4 commit | `tests/fuzz/axtag-trailing.axfuzz`, `tests/fuzz/operator-param.axfuzz`; `tests/diagnostics/1028-trailing-axtag.axbad`, `1029-operator-fn-name.axbad` |
| AN-30 | `fmt` refused a parameter or `let` binder spelled like an operator, which shadows the operator in its scope | The third P4 commit | `tests/fuzz/operator-param.axfuzz`; `tests/selfhost/1005-operator-binder-shadows.ax` |
| AN-31 | A checked tag, such as `restrict(no-alloc)`, above a `data`, `struct`, import, macro or alias was recorded and never checked | The tag-rules commit | `tests/diagnostics/1030-axtag-misplaced.ax`; `AX3077` |
| AN-32 | Purity had three accepted spellings, `pure`, `effect(pure)` and a slip of `pure` read as metadata, and the slip claimed nothing | The tag-rules commit | `tests/diagnostics/1031-pure-tag-spelling.ax`; `AX3078` |
| AN-33 | A `data` constructor or type spelled like an operator compiled though nothing could reach it | The tag-rules commit | `tests/fuzz/data-ctor-operator.axfuzz`; `tests/diagnostics/1029-operator-fn-name.axbad` |
| AN-13 | The stack bound read AArch64 ELF only; x86-64 was unsupported | The x86-64 stack-bound commit | `scripts/check-report.sh` §4b and its `x86call` ablation |
| AN-41 | A function's NID hashed whichever of its `::` and `fn` came last, so moving a signature below its definition gave the function a new identity | The NID commit | `scripts/check-metamorphic.sh` §2c and its `nid-fn-wins` ablation |
| AN-40 | A declaration macro whose `syntax/*` query named a `data` another macro generates below it was refused with `AX3028`, against `MAC-LANG-3a` | The macro-query-order commit | `tests/selfhost/1008-macro-query-order.ax`; `scripts/check-metamorphic.sh` §2b |
| AN-42 | A recovery point's abort reclaimed everything its thunk allocated, including a block the thunk stored into a structure older than the point, so a `Vec` grown inside the extent kept a reclaimed data block | The recovery-region commit | `tests/diagnostics/1033-recover-escape.ax`; `AX3060`, `AX3090` |
| AN-43 | `vecWithCapacity` multiplied the element count by 8 unchecked, so 2^61 elements asked the allocator for 0 bytes and the vector's pushes wrote over later blocks | The Vec-range commit | `tests/stdlib/562-vec-capacity-range.ax` |
| AN-34 | A parameter, a lambda parameter or a captured parameter spelled like a nullary top-level function compiled as a call to that function, in its own module and across modules | The R-A10 commit | `tests/selfhost/1007-param-shadows-nullary.ax`; `scripts/check-metamorphic.sh` §3 `param-first` |
| AN-35 | The effect walk read `cast`'s type operand as a reference, so an entry file's function `a` gave `Vec`'s element readers its effects, and a program importing `Vec` was refused | The R-A10 commit | `tests/selfhost/1006-cast-type-operand.ax`; `scripts/check-metamorphic.sh` §3 `cast-operand` |
| AN-36 | The effect walk skipped a named pattern's binders, so `{tag = t}` read `t` as a free name | The R-A10 commit | `tests/selfhost/1006-cast-type-operand.ax`; `scripts/check-metamorphic.sh` §3 `named-pattern` |
| AN-38 | `scripts/axiom-report.py` read every line opening `E ` as a compiler error, and `E` is also the `symbols` kind of an `effect` declaration, so it refused to report on any program declaring an effect | The trap-enumeration commit | `scripts/check-report.sh` §2's trap program declares `Ask` |
| AN-49 | A channel, mutex, cancellation token or spawn handle was an `Int`: any word passed as one, a call on a freed one read an unmapped page, a second free unmapped whatever the kernel had mapped there since, and a second join read a page already unmapped | The two typed-handles commits | `tests/stdlib/570-handle-freed.ax`, `572-spawn-joined-twice.ax`; `scripts/check-handles.sh` §1, §2, §6 |
| AN-50 | A `while` with no body checked OK and `fmt` refused it with no code | The typed-handles commits, when the fuzzer's corpus grew | `tests/fuzz/while-no-body.axfuzz` |
| AN-C1 | The fuzzing harness read a refusal whose report held a NUL as a codeless one | `61f1e0ef` | `scripts/check-fuzz.sh` §4's NUL control |
| AN-C2 | Two `check` segmentation faults found by the fuzzer, in the human renderer and the region pass | `878b17be` | `tests/fuzz/render-spanless-cross.axfuzz`, `tests/fuzz/region-nonarrow-sig.axfuzz` |
| AN-C3 | A forked binding that trapped inside a recovery point ran the parent's continuation (F2) | Milestone A | `tests/stdlib/522-parallel-recover.ax` |
| AN-C4 | Thread arenas were never unmapped, and 6,000 threads mapped 6.16 GB (F3) | Milestone A | `scripts/check-parallel.sh` §12a |
| AN-C5 | `axiom_alloc` accepted a negative size (F4) | `6527bea0` | That commit's fixtures |
| AN-C6 | Seven raw primitives escaped the unsafe set (F5) | Milestone A | `tests/diagnostics/1010-unsafe-primitives.ax` |
| AN-C7 | A second release of a filed block decremented a pointer (F6) | Milestone A | `tests/stdlib/521-release-filed.ax` |
| AN-C8 | `vecSet` ignored an out-of-range index (F9) | Milestone B | `tests/stdlib/525-vec-set-bounds.ax` |
| AN-C9 | A `Vec` could be shared by reference between `--threads` siblings (F11) | Milestone C | `tests/diagnostics/656-parallel-container-capture.ax` |
| AN-46 | A reset-free loop of mixed sizes above 1 KiB grew with time, because each exact 16-byte class kept its peak | `30c433ed` | `tests/stdlib/558-size-classes.ax`; `scripts/check-reclaim-soak.sh` §2 |
| AN-47 | A recovery point whose thunk answered left its 144-byte record in the arena | `7e4992b6` | `tests/stdlib/560-recover-record.ax` |
