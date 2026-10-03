# Memory audit: disposition of program obligations

[`memory-model.md`](../memory-model.md) §0.2 places obligations on the
programmer. For each one, it requires a statement of whether a static
check or a runtime trap enforces it, and what remains unchecked. This
page is that disposition table. Each row is one of these:

- **static**: the compiler refuses the program (an `AX…` code and a
  fixture).
- **dynamic**: the runtime traps or reports (a `status …` and a
  fixture).
- **boundary**: the obligation is confined to an explicit unsafe
  operation with stated preconditions, and meeting it is the caller's
  job.
- **open**: none of the above yet. The rule says what the programmer
  must do, and nothing checks it.

The rule text is normative in `memory-model.md`. This page records how
each rule is enforced. Run the evidence commands from the repository
root.

## Arena and regions

| Obligation | Disposition | Evidence |
|---|---|---|
| After a raw reset, no reclaimed allocation is read again (`MM-ALLOC-16`) | Boundary and open. Raw marks are `Int`s. Escapes from the checked `region` form are static (`MM-RGN-1…4`, `AX3058–AX3063`). Arbitrary raw resets are unchecked | `scripts/check-region-scope.sh`, `scripts/check-region-escape.sh`, diagnostics 630, 631, 645–648 and 653; raw-reset misuse has no fixture |
| Nothing older than a recovery point is made to hold what its thunk allocated (`MM-ALLOC-23`) | Static: the region pass walks a recovery thunk written as a lambda, and a store of what it allocates into an older structure is `AX3060`; a thunk it can't see is `AX3090` | `tests/diagnostics/1033-recover-escape.ax`; `tests/stdlib/561-failed-operations.ax` case 3 shows the safe shape |
| A reset leaves no stale allocator metadata, in any class, chunk or thread (`MM-ALLOC-13`, `MM-LIFE-2e`) | Implementation: the reset scrubs every list head and the filed count | `tests/stdlib/559-reset-metadata.ax`; `scripts/check-reclaim-soak.sh` §4 with the no-scrub and shared-lists ablations |
| A reset keeps exactly one contiguous carried block, and kept fields aren't recursively promoted (`MM-ALLOC-16`) | Boundary: the `reset_keeping` contract. Referencing a dead allocation through a kept block is the caller's responsibility | Stated; no fixture |
| A mark names a live arena position, and evidence is live at reset (`MM-ALLOC-16a`, `16b`) | Dynamic: the runtime checks marks and live evidence | The `6527bea0` fixtures |
| A lexical region answers a scalar, and names don't rebind inside themselves (`MM-RGN-1`) | Static: `AX3058`, `AX3059` | `tests/stdlib/168-region.ax`; `check-region-scope.sh`, including the unsafe-escape ablation |
| No reference escapes to an outliving region by store, return, capture or argument (`MM-RGN-2…4`) | Static within the tracked-origin domain: `AX3059–AX3063`. Unresolved calls include their captures. Origin overflow and unconverged facts are refused | `scripts/check-region-escape.sh`; `tests/region/escape-closure-call.ax` beside the accepted `tests/region/closure-local.ax` |
| Erased addresses, hand-built layouts and foreign memory obey the region rules | Open: §3.6 covers typed origins only, and raw words keep `MM-ALLOC-16` and `MM-LIFE-2g` | — |

## Lifetimes and counting

| Obligation | Disposition | Evidence |
|---|---|---|
| No use after free, double release or count tampering through the safe surface | Dynamic and partial. Free-list links are encoded (`MM-LIFE-2k`), release paths emit retains and releases, and count exhaustion traps with 70 (`MM-LIFE-2l`). Closures, containers, field stores, `Str` slices and a `Handle` were probed and hold | `tests/stdlib/355-arc-events.ax`, `check-container-reclaim.sh`, `527-retain-overflow.ax` (optstable 0–3), `556-count-balance.ax` with its over-release control |
| A dead structure of any depth is released without exhausting the stack (`MM-LIFE-2d`) | Implementation: the walk keeps a dead list in the dead blocks' own count words and never recurses | `tests/stdlib/555-release-deep-chain.ax`; `scripts/check-reclaim-soak.sh` §1 under a 64 KiB stack, with the recursive-walk ablation red |
| Cycles under counting (`MM-LIFE-2f`: the rule is withdrawn, the obligation is live) | Boundary, measured: there is no tracing collector, so cyclic garbage waits for an arena reset or the end of the process. A dropped two-node knot costs 64 bytes of backlog; inside an arena scope, nothing | `tests/stdlib/557-cycle-backlog.ax`; `scripts/check-reclaim-soak.sh` §3 (RSS at 10^5 and 10^6, scoped and acyclic controls) |
| A value whose count never reaches zero is released explicitly or scoped to an arena (the `MM-LIFE-4` cases) | Boundary and open. `Handle` carries foreign destructors (`MM-FFI-6`), and there is no universal finalisation. An arena reset reclaims a `Handle`'s block without running its destructor | The `Handle` fixtures |
| The deferred-reclamation backlog is observable (`MM-ALLOC-24`) | Implementation: `(__axiom_mem_stat k)` answers held, filed and mapped bytes; held less filed is the backlog | `tests/stdlib/557-cycle-backlog.ax`, `558-size-classes.ax`; the model predicts filed at every step (`scripts/check-runtime-model.sh`); `scripts/check-reclaim-soak.sh` §2 holds held against peak RSS |
| Reuse doesn't ratchet under a mixed size distribution (`MM-ALLOC-25`) | Implementation, bounded by each class's peak: a size mix that drifts keeps the old band's blocks until a reset | `tests/stdlib/558-size-classes.ax`; `scripts/check-reclaim-soak.sh` §2 and its no-rounding ablation |
| No mutable aliasing of a live value (`MM-MUT-4`) | Static where the checker tracks it. `cast` and raw words escape it | The checker and the `AX3012` family; raw-word aliasing is open |

## Concurrency and tasks

| Obligation | Disposition | Evidence |
|---|---|---|
| A binding shares at most a word with its parent (`MM-PAR-6`) | Static: `AX3064`, over the captures the checker can see, in both lowerings | Diagnostics 642–644, 655 and 656; the §11 opaque-shape probes |
| A captured `Vec` isn't mutated across `--threads` siblings | Static: `AX3064` refuses class-0 containers with their own message | `tests/diagnostics/656-parallel-container-capture.ax` (direct, aliased, nested and struct-wrapped); `tests/stdlib/471-parallel-trap.ax` builds inside |
| A spawned child is joined in its scope, and join failures are observed | Dynamic: the registry sweeps on abort, trap, return and end (`MM-PAR-7`), and failures are status 78 | §12b (`kill -0`), §12c (`foreign 78 … answer 42`) |
| Grandchildren of a killed child, and threads that never finish | Open by statement: the three `MM-PAR-7` limits | — |
| A spawn handle is joined at most once, by the binding that spawned it (`MM-PAR-8`) | Static and dynamic: `Spawn` is its own type and isn't captured (`AX3004`, `AX3064`); a second join, a join of the other lowering's handle and the pid of a joined binding trap 85; a cross-thread join is 78 (`MM-PAR-7`) | `tests/diagnostics/1066-spawn-handle.ax`; `tests/stdlib/572-spawn-joined-twice.ax`; `scripts/check-handles.sh` §2 |
| A child spawned inside an aborted recovery extent is ended | Dynamic: the abort sweeps the extent's children before it resets (`MM-PAR-7`) | `scripts/check-reclaim-soak.sh` §5 |
| Descriptors, shared mappings and locks taken inside a recovery extent are released on every path (`MM-ALLOC-23`) | Open program obligation: an abort runs nothing, and the runtime can't know what the thunk acquired (AN-44) | `scripts/check-reclaim-soak.sh` §5 measures one descriptor leaked per trapped cycle, and none for the control that closes first |
| A `Foreign` shared with a thread is made safe by the foreign side (`MM-FFI-7`) | Open program obligation | — |
| A channel, mutex or cancellation token is one its module made, and still live when used (`MM-PAR-8`, `MM-PAR-10`, `MM-PAR-11`, `MM-PAR-13`) | Static and dynamic: the seal (`AX3085`, `AX3086`) and a distinct type (`AX3004`) refuse a forged handle; the handle table traps 85 on a freed, forged or other-kind one. Open: a free that races another binding's use | `tests/diagnostics/1060`-`1063`; `tests/stdlib/570-handle-freed.ax`; `scripts/check-handles.sh` |

## Unsafe layer and FFI

| Obligation | Disposition | Evidence |
|---|---|---|
| The thirty-six `Unsafe` primitives, the seven syscalls among them, are called only where `effect(unsafe)` is declared and their preconditions hold | Boundary and static: `restrict(no-unsafe)` and `pure` refuse them (`AX3049`, `AX3010`), and `AX3073` reads all thirty-six | `tests/diagnostics/1010-unsafe-primitives.ax`, `tests/diagnostics/1080-unsafe-syscalls.ax`, `tests/diagnostics/1020-unsafe-device-primitives.ax`; the precondition interfaces in `Mem`, `Vec`, `Map`, `Intern`, `Ffi` and `Sys` state their conditions |
| The kernel is handed only addresses whose extent the caller vouches for (`MM-EXEC-9e`) | Static boundary: every `Sys` call that hands the kernel a caller's address is a precondition interface, and `IO`'s typed calls check a `String` range before the syscall (status 77) | `tests/diagnostics/1081-sys-buffer-calls.ax`, `tests/stdlib/610-typed-io-bounds.ax`, `tests/stdlib/545-no-unsafe-practical.ax` |
| `__addr` takes a literal's address, and `strCStr` bytes aren't used after the `Str` is gone (`MM-FFI-2a`, `MM-FFI-4`) | Boundary: caller preconditions | Stated; misuse fixtures are absent |
| A `Handle` destructor runs once, from Rust, with the documented `axiom-allow.txt` symbol set | Dynamic: the release path and the FFI gate | `check-ffi.sh` per-crate allowlists |
| A cast that makes a reference from another type preserves a valid representation | Static boundary: `AX3073` requires `effect(unsafe)` where the cast forges; `restrict(no-unsafe)` refuses it directly and through untrusted callees. The programmer still validates the word | `tests/diagnostics/1040-forging-cast.ax`, `tests/diagnostics/1042-no-unsafe-indirect.ax` |
| A type-preserving cast keeps the operand's ownership and evidence | Static: the cast proof preserves temporary cleanup and borrowed aliases; scalar casts take no reference share | `tests/stdlib/701-cast-ownership.ax`; `scripts/check-cast-arg-root.sh` |
| A precondition interface is called only after its stated condition holds | Static boundary: `AX3073` requires `effect(unsafe)` on the caller; `AX3079` and `AX3080` require the interface to state a nonempty condition. The caller still checks that condition | `tests/diagnostics/1041-precondition-call.ax`, `tests/diagnostics/1043-precondition-tag.ax`; `tests/selfhost/1010-trusted-wrapper.ax` |

## Closures and containers

| Obligation | Disposition | Evidence |
|---|---|---|
| A closure doesn't outlive its frame's data | Static for tracked captures. The closure-outlives-frame dangle through erased words is recorded and open | `AX3062` (`tests/diagnostics/647-region-capture.ax`); the erased-word dangle has no fixture |
| `vecSet` and `vecGet` indices are in range | Dynamic: trap 77, with `vecSet` trapping before mutation | `tests/stdlib/525-vec-set-bounds.ax`, `tests/stdlib/070-vec.ax` |
| Pool results are consumed in submit order, and the pool isn't re-entered concurrently | Boundary: one status cell serves one pool's sequential joins, and concurrent pool invocations never share it | `tests/stdlib/523-par-pool-bounded.ax` |
