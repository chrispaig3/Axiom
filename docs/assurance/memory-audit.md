# Memory audit: disposition of program obligations

`memory-model.md` §0.2 binds the programmer with obligations and
requires each to state whether a static check or a runtime trap
enforces it, and what unchecked remainder is left. This register is
that disposition table. A row is one of:

- **static** — the compiler refuses the program (`AX…` + fixture);
- **dynamic** — the runtime traps or reports (`status …` + fixture);
- **boundary** — confined to an explicit unsafe operation with stated
  preconditions, and the obligation is the caller's;
- **open** — none of the above yet; the rule says what the programmer
  must do and nothing checks it.

Rule text is normative in `memory-model.md`; this file dispositions
it. Evidence commands are run from the repository root.

## Arena and regions

| Obligation | Disposition | Evidence |
|---|---|---|
| After a raw reset, no reclaimed allocation is read again (`MM-ALLOC-16`) | boundary + open: raw marks are `Int`s; the checked `region` form's escapes are static (`MM-RGN-1…4`, `AX3058–AX3063`); arbitrary raw resets unchecked | `check-region-scope.sh`, `check-region-escape.sh`, diagnostics 630/631/645–648/653; raw-reset misuse has no fixture |
| A reset keeps exactly one contiguous carried block; kept fields are not recursively promoted (`MM-ALLOC-16`) | boundary: `reset_keeping` contract; referencing a dead allocation through a kept block is the caller's | stated; no fixture |
| A mark names a live arena position; evidence is live at reset (`MM-ALLOC-16a`, `16b`) | dynamic: the runtime checks marks and live evidence | `6527bea0` fixtures |
| A lexical region answers a scalar; names do not rebind inside themselves (`MM-RGN-1`) | static: `AX3058`, `AX3059` | `168-region.ax`, `check-region-scope.sh` incl. unsafe-escape ablation |
| No reference escapes to an outliving region by store, return, capture, or argument (`MM-RGN-2…4`) | static within the tracked-origin domain: `AX3059–AX3063`; conservatively refuses through unresolved calls | `653-region-escape-callee.ax` beside accepted `479-region-reclaim.ax`; escape ablations expose the reclaimed read |
| Erased addresses, hand-built layouts, and foreign memory obey region rules | open: §3.6 covers typed origins only; raw words retain `MM-ALLOC-16`/`MM-LIFE-2g` | — |

## Lifetimes and counting

| Obligation | Disposition | Evidence |
|---|---|---|
| No use after free, double release, or count tampering through the safe surface | dynamic + partial: encoded free-list links (`MM-LIFE-2k`); release paths emit retains/releases; count exhaustion traps 70 (`MM-LIFE-2l`) | `355-arc-events.ax`, `check-container-reclaim.sh`, `527-retain-overflow.ax` (optstable 0–3) |
| Cycles under counting (`MM-LIFE-2f`, withdrawn rule, live obligation) | boundary: no tracing collector; cyclic garbage waits for arena reset or process end | stated; long-lived cyclic workloads have no bounded-reclamation fixture |
| A value whose count never reaches zero is explicitly released or arena-scoped (`MM-LIFE-4` cases) | boundary + open: `Handle` carries foreign destructors (`MM-FFI-6`); universal finalization does not exist | `Handle` fixtures; deferred-reclamation backlog unmeasured |
| No mutable aliasing of a live value (`MM-MUT-4`) | static where the checker tracks it; `cast` and raw words escape it | checker + `AX3012` family; raw-word aliasing open |

## Concurrency and tasks

| Obligation | Disposition | Evidence |
|---|---|---|
| A binding shares at most a word with its parent (`MM-PAR-6`) | static: `AX3064` over captures the checker can see, both lowerings | diagnostics 642–644, 655, 656; §11 opaque-shape probes |
| Captured `Vec` is not mutated across `--threads` siblings | static: `AX3064` refuses class-0 containers with their own message | `656-parallel-container-capture.ax` (direct, aliased, nested, struct-wrapped); `471-parallel-trap.ax` builds inside |
| A spawned child is joined in its scope; join failures are observed | dynamic: registry sweeps on abort/trap/return/end (`MM-PAR-7`); failures are status 78 | §12b (`kill -0`), §12c (`foreign 78 … answer 42`) |
| grandchildren of a killed child, threads that never finish, unmapped-handle words | open by statement: the three `MM-PAR-7` limits; `MM-PAR-8` planned | — |
| A `Foreign` shared with a thread is made safe by the foreign side (`MM-FFI-7`) | open program obligation | — |

## Unsafe layer and FFI

| Obligation | Disposition | Evidence |
|---|---|---|
| The sixteen `Unsafe` primitives are called only where `effect(unsafe)` is declared and their preconditions hold | boundary + static: `restrict(no-unsafe)`/`pure` refuse them (`AX3049`/`AX3010`); `AX3073` reads all sixteen since the reseed | `1010-unsafe-primitives.ax`; fifteen stdlib wrappers claimed; unsafe preconditions stated in `Mem`/`Vec`/`Map`/`Intern`/`Ffi` headers |
| `__addr` takes a literal's address; `strCStr` bytes are not used past the `Str` (`MM-FFI-2a`, `MM-FFI-4`) | boundary: caller preconditions | stated; misuse fixtures absent |
| A `Handle` destructor runs once, from Rust, with the documented `axiom-allow.txt` symbol set | dynamic: release path + FFI gate | `check-ffi.sh` per-crate allowlists |
| `cast` preserves the representation its target claims | boundary: `cast` is the programmer asserting a type the checker cannot prove | `cast-arg-root` gate pins the root rule; misuse is unchecked by design |

## Closures and containers

| Obligation | Disposition | Evidence |
|---|---|---|
| A closure does not outlive its frame's data | static for tracked captures; the closure-outlives-frame dangle through erased words stays recorded and open | `AX3062`; erased-word dangle has no fixture |
| `vecSet`/`vecGet` indices are in range | dynamic: trap 77, `vecSet` before mutation | `525-vec-set-bounds.ax`, `070-vec.ax` |
| Pool results are consumed in submit order; the pool is not re-entered concurrently | boundary: one status cell serves one pool's sequential joins; concurrent pool invocations never share it | `523-par-pool-bounded.ax` |
