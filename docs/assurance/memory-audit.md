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
| A reset keeps exactly one contiguous carried block, and kept fields aren't recursively promoted (`MM-ALLOC-16`) | Boundary: the `reset_keeping` contract. Referencing a dead allocation through a kept block is the caller's responsibility | Stated; no fixture |
| A mark names a live arena position, and evidence is live at reset (`MM-ALLOC-16a`, `16b`) | Dynamic: the runtime checks marks and live evidence | The `6527bea0` fixtures |
| A lexical region answers a scalar, and names don't rebind inside themselves (`MM-RGN-1`) | Static: `AX3058`, `AX3059` | `tests/stdlib/168-region.ax`; `check-region-scope.sh`, including the unsafe-escape ablation |
| No reference escapes to an outliving region by store, return, capture or argument (`MM-RGN-2…4`) | Static within the tracked-origin domain: `AX3059–AX3063`. Unresolved calls are refused conservatively | `tests/diagnostics/653-region-escape-callee.ax` beside the accepted `tests/stdlib/479-region-reclaim.ax`; the escape ablations expose the reclaimed read |
| Erased addresses, hand-built layouts and foreign memory obey the region rules | Open: §3.6 covers typed origins only, and raw words keep `MM-ALLOC-16` and `MM-LIFE-2g` | — |

## Lifetimes and counting

| Obligation | Disposition | Evidence |
|---|---|---|
| No use after free, double release or count tampering through the safe surface | Dynamic and partial. Free-list links are encoded (`MM-LIFE-2k`), release paths emit retains and releases, and count exhaustion traps with 70 (`MM-LIFE-2l`) | `tests/stdlib/355-arc-events.ax`, `check-container-reclaim.sh`, `527-retain-overflow.ax` (optstable 0–3) |
| Cycles under counting (`MM-LIFE-2f`: the rule is withdrawn, the obligation is live) | Boundary: there is no tracing collector, so cyclic garbage waits for an arena reset or the end of the process | Stated; bounded reclamation for long-lived cyclic workloads is untested |
| A value whose count never reaches zero is released explicitly or scoped to an arena (the `MM-LIFE-4` cases) | Boundary and open. `Handle` carries foreign destructors (`MM-FFI-6`), and there is no universal finalisation | The `Handle` fixtures; the deferred-reclamation backlog is unmeasured |
| No mutable aliasing of a live value (`MM-MUT-4`) | Static where the checker tracks it. `cast` and raw words escape it | The checker and the `AX3012` family; raw-word aliasing is open |

## Concurrency and tasks

| Obligation | Disposition | Evidence |
|---|---|---|
| A binding shares at most a word with its parent (`MM-PAR-6`) | Static: `AX3064`, over the captures the checker can see, in both lowerings | Diagnostics 642–644, 655 and 656; the §11 opaque-shape probes |
| A captured `Vec` isn't mutated across `--threads` siblings | Static: `AX3064` refuses class-0 containers with their own message | `tests/diagnostics/656-parallel-container-capture.ax` (direct, aliased, nested and struct-wrapped); `tests/stdlib/471-parallel-trap.ax` builds inside |
| A spawned child is joined in its scope, and join failures are observed | Dynamic: the registry sweeps on abort, trap, return and end (`MM-PAR-7`), and failures are status 78 | §12b (`kill -0`), §12c (`foreign 78 … answer 42`) |
| Grandchildren of a killed child, threads that never finish, and unmapped-handle words | Open by statement: the three `MM-PAR-7` limits. `MM-PAR-8` is planned | — |
| A `Foreign` shared with a thread is made safe by the foreign side (`MM-FFI-7`) | Open program obligation | — |
| A channel or mutex handle is one its module made, and still live when used (`MM-PAR-8`, `MM-PAR-10`, `MM-PAR-11`) | Static and dynamic: the seal (`AX3085`, `AX3086`) and a distinct type (`AX3004`) refuse a forged handle; the handle table traps 85 on a freed, forged or other-kind one. Open: a free that races another binding's use | `tests/diagnostics/1060`-`1063`; `tests/stdlib/570-handle-freed.ax`; `scripts/check-handles.sh` |

## Unsafe layer and FFI

| Obligation | Disposition | Evidence |
|---|---|---|
| The sixteen `Unsafe` primitives are called only where `effect(unsafe)` is declared and their preconditions hold | Boundary and static: `restrict(no-unsafe)` and `pure` refuse them (`AX3049`, `AX3010`), and `AX3073` reads all sixteen | `tests/diagnostics/1010-unsafe-primitives.ax`; fifteen stdlib wrappers claimed; the unsafe preconditions are stated in the `Mem`, `Vec`, `Map`, `Intern` and `Ffi` headers |
| `__addr` takes a literal's address, and `strCStr` bytes aren't used after the `Str` is gone (`MM-FFI-2a`, `MM-FFI-4`) | Boundary: caller preconditions | Stated; misuse fixtures are absent |
| A `Handle` destructor runs once, from Rust, with the documented `axiom-allow.txt` symbol set | Dynamic: the release path and the FFI gate | `check-ffi.sh` per-crate allowlists |
| `cast` preserves the representation its target claims | Boundary: `cast` is the programmer asserting a type the checker can't prove | The `cast-arg-root` gate pins the root rule; misuse is unchecked by design |

## Closures and containers

| Obligation | Disposition | Evidence |
|---|---|---|
| A closure doesn't outlive its frame's data | Static for tracked captures. The closure-outlives-frame dangle through erased words is recorded and open | `AX3062` (`tests/diagnostics/647-region-capture.ax`); the erased-word dangle has no fixture |
| `vecSet` and `vecGet` indices are in range | Dynamic: trap 77, with `vecSet` trapping before mutation | `tests/stdlib/525-vec-set-bounds.ax`, `tests/stdlib/070-vec.ax` |
| Pool results are consumed in submit order, and the pool isn't re-entered concurrently | Boundary: one status cell serves one pool's sequential joins, and concurrent pool invocations never share it | `tests/stdlib/523-par-pool-bounded.ax` |
