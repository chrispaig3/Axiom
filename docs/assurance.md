# Assurance

This page is for anyone weighing Axiom for safety-related, embedded or
operating-system work. It lists what the compiler and runtime
guarantee, the evidence behind each guarantee, the configurations that
evidence covers, the known defects, and what still stands between
Axiom and a certified system.

Four words mean different things here:

- **Implemented**: the code is in this repository.
- **Verified**: a named check or fixture tests the property, within the
  limits stated beside it.
- **Qualification-ready**: the evidence an assessor would ask for exists
  for one frozen configuration.
- **Approved**: an independent, competent assessor has accepted that
  evidence for a specific application, platform, configuration and
  development process.

Axiom has no qualified tool configuration or approved application.
Nothing here claims compliance with a standard. Whether a system built with Axiom is fit for a mission
depends on that system, its hardware and its development process, and
an independent assessment of them.

## Reference configurations

The evidence on this page comes from these configurations. A check
that passes on one doesn't extend its claim to another.

| | H3 | H2 | E1 |
|---|---|---|---|
| Target | `darwin-aarch64` | `linux-aarch64` | `baremetal-aarch64` |
| Machine | Apple silicon, macOS 15 runner | AArch64, Ubuntu 24.04 runner | Cortex-A72 as modelled by QEMU, `virt` board, EL1 |
| LLVM | 23 (Homebrew `llvm@23`) | 18 (Ubuntu `llvm-18`) | the host's |
| Runtime | processes by default, `--threads` | processes by default, `--threads` | one thread plus `isr(irq)` and `isr(fault)` |
| Heap | `mmap` arena | `mmap` arena | static arena with `--heap-ceiling` |
| Runs in CI | the whole test battery | the whole test battery | compile-time checks, and the QEMU runs on the H3 leg |

CI also builds the compiler from the seed on `linux-x86_64`, and on
`freebsd-x86_64` and `freebsd-aarch64` in virtual machines, and
assembles code for every hosted target. Nothing has run on embedded
hardware.

Each CI job that sets up LLVM through the provisioning action records
the `opt`, `llc`, `clang`, `ld.lld` and `lld-link` versions it used,
and stops if `llc` reports another LLVM major. The other four versions
are recorded but not compared. The FreeBSD jobs and the seed-only
bootstrap job print `llc --version` and compare nothing.
Optimisation levels 0 to 3 are exercised by the `.optstable` fixtures
under `tests/stdlib/`; the default is 1.

## Guarantees and evidence

The rules are in [the memory model](memory-model.md) and
[the restricted profile](restricted-profile.md). The IDs match the
memory model's *Assurance evidence* table.

### The safety contract

The [safety contracts and trusted boundary inventory](safety-contracts.md)
give the source obligations, counterexamples and unproved limits behind
this table.

Safe code is code with no `effect(unsafe)` declaration of its own and no
`extern` block. Its safety depends on the trusted interfaces it reaches.
This table maps its safety obligations to their checks, refusals and
limits.

| Invariant | Enforced by | A program it refuses | Limit |
|---|---|---|---|
| A reference is made only by a constructor, by an allocation the library types, or by a trusted function that says so | `AX3073` on a forging `as`; `AX5002` keeps `Internal.Raw` and `Internal.RawVec` inside the library (`MM-EXEC-9d`, `MM-EXEC-9g`) | `(as 7 Hid)` in an untagged function; `(import Internal.Raw)` from a program | A trusted body is reviewed, never proved |
| A word that reaches the kernel or a primitive as an address was made by the function that passes it, or its caller said so | `effect(unsafe)` on every user of a primitive; `restrict(no-unsafe)` names the path to any untrusted one (`MM-EXEC-9d`) | `(__load64 a 0)` in an untagged function | A public function that still takes an address as an `Int`, such as `Sys.sysSpawn`, trusts its caller |
| A typed read or write checks its range before memory or the kernel sees it | The index trap, status 77, in `vecGet`, `vecSet`, `strByte`, `strSlice` and `fileRead` (`MM-MUT-5a`, `MM-EXEC-9f`) | `(vecGet v 9)` over three elements | A raw `Int` index into a raw block has no range |
| Every value is released once, by its owner, and never while a share is live | The ownership events of `MM-LIFE-2`, the counted stores of `MM-LIFE-2g`, the `result(owned)` claims | a `set` that drops a `File` without its release | A cycle leaks until an arena reset. The compiler and the library can still untrack a value with `(as v Int)`. User files in a directory named `core` share the exemption (`MM-VAL-24`, `MM-EXEC-9d`) |
| A region's values do not outlive it | `MM-RGN-1` to `MM-RGN-6`: typed origins, store, return, capture and argument escapes are refused (`AX3059`, `AX3060`) | storing a region value into an outer struct | Promoting an owned reference out of a region is `MM-RGN-7`, planned |
| A `parallel` or spawned binding reaches nothing its parent still owns, except what it borrows under a count freeze | `AX3064` on captures; the lend block of `MM-PAR-6` | a `Vec` captured by a spawned thunk | A trusted accessor inside the library could still hand a word back |
| A trap is a defined exit status, never undefined behaviour | The trap table of the memory model, statuses 70 to 86, and the recovery record (`MM-ALLOC-23`) | division by zero exits 72 | A trusted body or an `extern` can still corrupt memory |
| The emitter visits the accepted declaration list and snapshotted nested syntax | The sealed `CheckedProgram` handoff compares exact node fields, child lists and name lists before its single emission | changing checked declarations or a nested body stops emission with status 80 (`tests/selfhost/1034-checked-declarations-stale.ax`, `tests/selfhost/1036-checked-nested-stale.ax`) | Packed metadata internals and raw writes through string aliases remain outside the snapshot |

Four properties are kept apart. Memory safety is the first seven rows:
no read, write or release outside what the types allow. Resource
cleanup is `MM-LIFE-2`'s owners releasing their `File`, `Poller` and
`TermGuard` values at scope end. Leak freedom would reclaim every
unreachable allocation; a cycle can leak until its arena resets. Bounded
execution is promised only where a trap or a budget says so: the index
and count traps, `Task`'s stacks and deadlines, and the restricted
profile's rules.

The contract does not cover the trusted boundaries, so a review must.
They are the compiler's own raw layer (`core/raw.ax`) and every
`effect(unsafe)` body in `core/`. They are the runtime the
compiler emits, from the allocator to the traps. They are
`Internal.Raw`, `Internal.RawVec` and every `effect(unsafe)` body in
the standard library, which `tests/agent/stdlib-effects.allow` lists.
And they are the `extern` blocks of `Ffi.ax` and
`Sys/Platform.windows.ax`, with any crate a program links
([the FFI guide](ffi.md)).

What is not promised: a trusted body's correctness, the behaviour of an
`extern`, timing, and anything after a hardware fault.

### Type soundness, rule by rule

Each area the type checker is responsible for has a program it accepts
and a program it refuses by code, and `scripts/check-diagnostics.sh`
holds every refusal to its code, span and exit status. The fixtures
named are one of each; the diagnostics corpus holds the rest.

| Area | Refused as | A refusal | An acceptance |
|---|---|---|---|
| Generic instantiation | `AX3124` wrong number of type arguments | `tests/diagnostics/1420-generic-alias-arity.ax` | `tests/selfhost/972-polymorphic-signature.ax` |
| Recursive unification and aliases | `AX3126` a type alias that expands recursively; `AX3125` an invalid type parameter | `tests/diagnostics/1422-recursive-alias.ax` | `tests/selfhost/973-type-alias.ax` |
| Nominal identity | `AX3044` a type name declared in two imported modules; `AX3006` a duplicate definition; `AX3004` one module's struct where another module's same-named struct is declared | `tests/diagnostics/1473-cross-module-nominal.ax` | `tests/selfhost/134-subtype-checked.ax` |
| Mutation | `AX3012` assignment to an immutable binding | `tests/diagnostics/1015-set-not-binding.ax` | `tests/selfhost/561-field-store-mut.ax` |
| Callable signatures | `AX3040` a type variable the caller chooses and the callee produces; `AX3036` an `extern` type that cannot cross | `tests/diagnostics/353-callback-tyvar.ax` | `tests/selfhost/1011-cast-arrow-alias.ax` |
| Constructor layouts | `AX3067` a struct built with the wrong field count; `AX3132` invalid named construction; `AX3056` a field with no type | `tests/diagnostics/270-struct-field-count.ax` | `tests/selfhost/1003-data-field-agree.ax` |
| Pattern exhaustiveness | `AX3005` a match that misses a case; `AX3009` a constructor pattern of the wrong arity; `AX3134` an arm that can never match | `tests/diagnostics/1107-match-literal-column.ax` | `tests/selfhost/750-builtin-option-match.ax` |
| Macros | `AX3018` an invocation no rule accepts; `AX3133` a rule that does not open with its macro's name | `tests/diagnostics/478-json-control-bytes.ax` | `tests/selfhost/1028-macro-syntax-identity.ax` |
| Module boundaries | `AX3023` a name its module does not export; `AX3085` a sealed struct built outside its module; `AX5002` an internal module reached from a program | `tests/diagnostics/1470-internal-import.ax` | `tests/selfhost/1032-imported-signatures.ax` |

The checker's answers reach a program through four doors, and they give
one answer: for every diagnostics fixture, `check` on the command line,
the language server, the REPL and `build` report the same diagnostics
(`scripts/check-surface-agreement.sh`).

The final handoff also carries function types into native numeric
lowering. An inferred `Float` result uses floating-point arithmetic,
including through imports. Tested by
`tests/selfhost/1044-checked-function-types.ax` and
`tests/lsp/checked-function-types.py`.

Not yet: the backend's full semantic representation is
[on the roadmap](roadmap.md#checks-and-claims).

### Compiler representation

Typed compiler containers keep their owners through lookups, sorting
and replacement. An optional lookup returns `Some` or `None`; a
required emitter lookup reports `AX4002` when its entry is missing.
An `if let` chooses a branch and may fall through. Exhaustive `match`
checking remains a separate obligation.

| Invariant | Enforcement and evidence | Limit |
|---|---|---|
| Checker contexts and function tables retain their typed children and distinguish missing entries | Owning `TC`, typed body scopes and `Option FnEnt`; `tests/selfhost/typecheck-function-registry.ax`, `tests/selfhost/typecheck-bound-scope.py` | Parser arena handles and mutable checked stamps remain trusted boundaries |
| Expansion preserves present empty repetitions and keeps binding and frame owners | Typed matches, binding vectors and `Option` results; `tests/tools/expansion-option-sequences.py`, `tests/tools/expansion-option-frames.py` | Syntax-identity metadata still crosses the raw AST arena boundary |
| Emitter metadata keeps each live share through replacement and restoration | Owning `CG` context and typed tables; `tests/selfhost/emitter-symbol-scope.py`, `tests/selfhost/emitter-type-registry.py` | Remaining packed state and reference erasures require separate review |
| Region facts retain their buffers without a cached checker backedge | Typed facts and scratch records; `tests/selfhost/typecheck-region-records.py`, `tests/selfhost/region-fact-projections.ax` | This checks representation and cleanup, not lifetime-analysis completeness |
| Compact exact-name indexes preserve entry ownership, lookup order and missing results | Sealed owning tables with `UInt32` Links and an overflow scan fallback; `tests/selfhost/typecheck-compact-index.py` | The measured layout is for a 64-bit host; suffix indexes retain full-width owners |
| Failed pattern tests continue without exposing branch bindings | `Some` and `None` paths; `tests/selfhost/typecheck-if-let-control-flow.ax`, `tests/diagnostics/1496-if-let-scope.ax` | Conditional matching does not require an `else` |

The compiler representation probes run natively at optimisation levels
0 and 2 with allocation poisoning. They check the named ownership and
absence cases; they do not establish memory-model soundness. Raw arena
stores, alias revision tracking and the trusted interfaces above remain
outside that claim. Qualification also requires evidence for a frozen
application and target configuration.

### Effects, rule by rule

The effect walk infers each function's row from its body and its
callees, and a declaration is a claim the walk answers. `Alloc` and
`Mut` need no declaration, and `effect(pure)` excludes them. `IO`,
`Spawn`, `Block` and `Entropy` must be declared where they are
performed, and `Unsafe` where a raw operation, a syscall, an `asm` form
or an `extern` call appears. A claim the walk cannot check is a warning
on its own declaration and never a fact about the callee. A caller's
row comes from the callee's body and from the callbacks it is given, so
an unverifiable claim cannot certify the claim above it
(`tests/diagnostics/1472-claim-does-not-launder.ax`).

| Area | Refused as | A refusal | An acceptance |
|---|---|---|---|
| A claim the body contradicts | `AX3010` an `effect(...)` or `effect(pure)` claim the body performs against | `tests/diagnostics/1201-field-dispatch.ax` | `tests/selfhost/1032-imported-signatures.ax` |
| A required effect undeclared | `AX3042` IO, Spawn, Block or Entropy performed and not declared | `tests/diagnostics/1472-claim-does-not-launder.ax` | `tests/stdlib/470-parallel.ax` |
| An unsafe operation undeclared | `AX3073` a raw operation, syscall, `asm` form or `extern` call in a body with no `effect(unsafe)` | `tests/diagnostics/1004-undeclared-unsafe.ax` | `tests/selfhost/1010-trusted-wrapper.ax` |
| An unsafe claim over a safe body | `AX3010` an `effect(unsafe)` claim where the body itself performs no unsafe operation | `tests/diagnostics/1200-unsafe-claim-open-row.ax` | `tests/selfhost/1010-trusted-wrapper.ax` |
| A claim the walk cannot check | `AX3037`, a warning; the symbol row carries `#effects-overapprox`, `#effects-possible` or `#effect-params`, and a caller's purity or restriction is judged by what flows through the call | `tests/diagnostics/343-axtag-unverifiable.ax` | `tests/diagnostics/1257-nolint-warning.ax` |
| Restrictions | `AX3049` a restriction the body or a callback violates; `AX3051`, a warning, one the walk cannot check; `AX3057` a `strict` one it cannot prove | `tests/diagnostics/393-restrict-strict.ax` | `tests/selfhost/132-contract.ax` |
| Handlers and operations | `AX3011` a handle body that reaches an effect its list does not name; `AX3053` an operation with no handler; `AX3038`, a warning, a handle list the walk cannot check | `tests/diagnostics/320-unhandled-effect.ax` | `tests/stdlib/300-effect-handlers.ax` |
| FFI | an `extern` call performs IO and is an unsafe operation: `AX3010` a claim over one that says otherwise, and the two rows above a caller that leaves them undeclared | `tests/diagnostics/1041-trusted-call.ax` | `tests/selfhost/1010-trusted-wrapper.ax` |

One limit has no row, because nothing refuses it yet. A value's drop
runs at the end of the scope that held it, with the effects declared
where the value was made. So a `no-io` function that stores a new file
over an old one closes the old one without the restriction seeing it
([roadmap](roadmap.md)). `tests/stdlib/712-drop-effects-at-creation.ax`
holds that behaviour in place.

### A. Correctness of the runtime

| ID | Guarantee | Rule | Evidence |
|---|---|---|---|
| R-A1 | A `parallel` binding that traps inside a recovery point answers its status once | `MM-PAR-7` | `tests/stdlib/522-parallel-recover.ax`, `scripts/check-parallel.sh` |
| R-A2 | No child outlives its scope on abort, trap, return or end | `MM-PAR-7` | `scripts/check-parallel.sh`, `scripts/check-task.sh` |
| R-A3 | A refused spawn or failed join is status 78, never success | `MM-PAR-7` | `scripts/check-parallel.sh` |
| R-A4 | A finished thread returns its arena | `MM-PAR-6a` | `scripts/check-parallel.sh` (H2 only) |
| R-A5 | The allocator refuses a negative or unrepresentable size with status 70 | `MM-ALLOC-7a` | `tests/stdlib/520-alloc-size.ax` |
| R-A6 | Every unsafe primitive, syscall, `asm` form and `extern` call needs `effect(unsafe)` | `MM-EXEC-9c`, `MM-EXEC-9d` | `tests/diagnostics/1010-unsafe-primitives.ax`, `tests/diagnostics/1080-unsafe-syscalls.ax`, `tests/diagnostics/1045-inline-asm-unsafe.ax`, `tests/diagnostics/1116-extern-unsafe.ax` |
| — | Unsafe declarations retain type checks, required effects and restrictions; handler values propagate their effects | `MM-EXEC-9d`, `MM-EXEC-10` | `tests/diagnostics/1395-unsafe-checks-retained.ax`, `tests/diagnostics/1390-handler-effects.ax`, `tests/stdlib/940-handler-values.ax` |
| R-A7 | A released block's free-list link can't be released as a count | `MM-LIFE-2k` | `tests/stdlib/521-release-filed.ax` |
| R-A8 | A join of a handle another binding spawned is status 78, refused before it waits or writes | `MM-PAR-7` | `scripts/check-parallel.sh` |
| R-A9 | A count that would overflow traps with status 70 before the write | `MM-LIFE-2l` | `tests/stdlib/527-retain-overflow.ax` |
| R-A10 | An unused declaration changes no other declaration's meaning | none | `scripts/check-metamorphic.sh` |
| R-A11 | A malformed `asm` form is refused at the part that is wrong before any assembler runs, and a template line the assembler rejects is reported at that line | `MM-FFI-9` | `scripts/check-embedded.sh` (A15), `tests/diagnostics/1280-inline-asm-forms.ax` |

Runtime traps exit with the reserved statuses 70 to 86 at every
optimisation level (`scripts/check-trap-statuses.sh`). The table in
[the memory model](memory-model.md) says what raises each.

### B. Ownership and safe interfaces

| ID | Guarantee | Rule | Evidence |
|---|---|---|---|
| R-B1 | `vecGet` and `vecSet` trap with status 77 on a bad index before any read or write | `MM-MUT-5a` | `tests/stdlib/464-index-trap.ax`, `tests/stdlib/525-vec-set-bounds.ax` |
| R-B2 | `Task` pools keep at most their width of workers and handles; a byte-result pool also keeps its `keep` budget of answers and its `memory` and `stack` budgets per task, and running out of a budget is an answer in a slot | `MM-PAR-13`, `MM-PAR-17` | `tests/stdlib/523-par-pool-bounded.ax`, `tests/stdlib/852-task-budgets.ax`, `tests/stdlib/920-task-stack.ax`, `scripts/check-task.sh` |
| R-B3 | A region-allocated value can't escape its region by store, return, capture or argument | `MM-RGN-1` to `MM-RGN-6` | `scripts/check-region-escape.sh` |
| R-B6 | A cast that forges a reference needs `effect(unsafe)`, and the declaration that says it is a trusted encapsulation whose callers inherit nothing | `MM-EXEC-9d` | `tests/diagnostics/1040-forging-cast.ax`, `tests/diagnostics/1260-spawn-forging-cast.ax` |
| R-B7 | A dead chain of any depth is released without deep recursion, and a second release of a dead block can't corrupt the allocator | `MM-LIFE-2d`, `MM-LIFE-2k` | `tests/stdlib/555-release-deep-chain.ax`, `scripts/check-reclaim-soak.sh` |
| R-B8 | Reuse is bounded by the allocator's size classes, and held, reusable and mapped bytes are readable with `memStats` | `MM-ALLOC-24`, `MM-ALLOC-25` | `tests/stdlib/703-memory-stats.ax`, `scripts/check-reclaim-soak.sh` |
| R-B9 | A recovery point allocates nothing, and a contained trap leaves the heap consistent | `MM-ALLOC-23` | `tests/stdlib/560-recover-record.ax`, `tests/stdlib/561-failed-operations.ax` |
| R-B10 | A typed read or write checks its range before the kernel sees it | `MM-EXEC-9f` | `tests/stdlib/610-typed-io-bounds.ax` |
| — | Releasing the last share of a `File`, socket or database connection closes it once | `MM-EXEC-17` | `tests/stdlib/697-resource-owner.ax`, `tests/stdlib/698-file-lifetime.ax` |
| — | An element `vecPop` hands over is released by the caller, through the `result(owned)` claim a trusted function makes | `MM-LIFE-2n` | `tests/stdlib/846-vec-pop-release.ax`, `scripts/check-container-reclaim.sh` |
| — | A `mut` local of a reference type releases the value a `set` overwrites and its last value at scope end, each once, and a lambda that captured it keeps its own share | `MM-MUT-1`, `MM-VAL-16` | `tests/stdlib/708-mut-slot-reassign.ax`, `tests/stdlib/709-mut-slot-capture.ax` |

A `mut` local releases only when the compiler can show that no read of
it is still in use at the `set` or the scope end, and never when its
type is a type variable. Any other `mut` local keeps what it
held: the memory stays allocated and a `File` stays open.
[The memory model](memory-model.md) lists those shapes under event 3.

A function that performs an unsafe operation says `effect(unsafe)`,
which makes it a trusted encapsulation. Nothing proves a trusted body
correct. A raw function
that takes an address or a handle as an `Int` can still crash safe code
that passes it a bad one. `axiom symbols` marks every trusted function
`#unsafe=trusted`, so you can list the set to review.

### C. Concurrency

| ID | Guarantee | Rule | Evidence |
|---|---|---|---|
| R-C1 | No container or unborrowed reference is captured by a concurrent binding | `MM-PAR-6` | `tests/diagnostics/656-parallel-container-capture.ax`, `scripts/check-parallel.sh` |
| R-C2 | A mutex excludes, and its guard releases it once on every way out of its scope, a recovered trap included; every blocking call has a timed form; tasks report failure, deadline and cancellation per slot | `MM-PAR-11` to `MM-PAR-13`, `MM-PAR-15` | `tests/stdlib/800-mutex-guard.ax`, `scripts/check-task.sh`, `scripts/check-protocol-model.sh` |
| R-C2a | A bounded channel delivers every word exactly once, in order per sender | `MM-PAR-10` | `tests/stdlib/528-chan.ax`, `scripts/check-chan.sh` |
| R-C3 | Atomics are sequentially consistent on every hosted target, and the litmus tests show no forbidden outcome | `MM-PAR-1`, `MM-PAR-9` | `scripts/check-atomics.sh` |
| R-C4 | A misaligned atomic traps with status 82 | `MM-PAR-9` | `tests/stdlib/544-misaligned-atomic.ax` |
| R-C5 | A process binding can start and join threads, and a task whose thread never ends is still ended by its deadline, in both lowerings | `MM-PAR-7` | `tests/litmus/thread-in-fork.ax`, `scripts/check-task.sh` |
| R-C6 | Channels, mutexes and tokens are sealed owners, freed when their last holder lets go and never while a binding uses them; safe code can't cast a word to a spawn handle, a guessed word names a live one only by a chance near 2^-40, and a rejoined or forged one traps with status 85 | `MM-PAR-8`, `MM-PAR-16` | `tests/stdlib/803-shared-owner.ax`, `tests/diagnostics/1260-spawn-forging-cast.ax`, `scripts/check-handles.sh` |
| R-C7 | A `parallel` binding can borrow its parent's strings and immutable data, and no binding's count traffic reaches the parent | `MM-PAR-6b` | `tests/stdlib/630-parallel-borrow.ax`, `scripts/check-race.sh` |
| R-C8 | A pure parallel computation answers the same at every width and in both lowerings | `MM-PAR-14` | `tests/stdlib/620-par-float-order.ax`, `scripts/check-task.sh` |
| R-C9 | A sleep ends no sooner than asked, measured on a monotonic clock that never steps backwards | `MM-PAR-12` | `tests/stdlib/851-instant-sleep.ax`, `scripts/check-task.sh` |
| R-C10 | A `parallel` form keeps no arena storage once it returns, however many run, in both lowerings | `MM-RGN-7` | `tests/litmus/par-forms.ax`, `scripts/check-parallel.sh` |

`scripts/check-race.sh` runs the threaded programs under
ThreadSanitizer. It covers the thread lowering only.

### D. Embedded and real-time

| ID | Guarantee | Rule | Evidence |
|---|---|---|---|
| R-D1 | The restricted profile checks every selected entry and its reachable helpers, refuses the RP rules and bounds stack use from machine code; invalid exceptions fail closed | RP-1 to RP-9 | `scripts/check-report.sh`, `scripts/check-stack-bound.sh` |
| R-D2a | Device registers are read and written at their own width, with barriers | `MM-FFI-8` | `scripts/check-embedded.sh` |
| R-D2b | An unhandled CPU exception exits 81, and an `isr(fault)` hook chooses the exit once | `MM-EXEC-16`, `MM-EXEC-19` | `tests/embedded/fault.ax`, `tests/embedded/fault-hook.ax`, `scripts/check-isr.sh` |
| R-D2c | A periodic interrupt workload and a DMA driver keep their budgets and ownership protocol | `MM-EXEC-18`, `MM-FFI-8` | `tests/embedded/periodic.ax`, `tests/embedded/dma.ax` |
| R-D2e | The MMU and caches are on before `main`, with read-only code, non-executable data and stack guards | `MM-EXEC-19` | `tests/embedded/overflow.ax`, `scripts/check-embedded.sh` |

R-D2b, R-D2c and R-D2e run under QEMU on the darwin-aarch64 CI leg.
Emulator evidence is not hardware evidence: QEMU models no caches,
timing or bus faults.

### E. The evidence itself

| ID | Property | Evidence |
|---|---|---|
| R-E1 | Executable models of the allocator and the channel protocol agree with the runtime, seeded mutants never crash the compiler, accepted mutants produce IR `llc` accepts, and the threaded programs run clean under ThreadSanitizer | `scripts/check-runtime-model.sh`, `scripts/check-protocol-model.sh`, `scripts/check-fuzz.sh`, `scripts/check-race.sh` |
| R-E2 | The compiler rebuilds itself byte for byte, two builds agree, and a diverse double compile agrees with an independent checker | `scripts/check-bootstrap.sh`, `scripts/check-reproducible.sh`, `scripts/check-ddc.sh` |
| — | The seed is its source's emission, and its lineage replays to the original anchor | `scripts/check-seed-provenance.sh`, `scripts/check-seed-lineage.sh` |
| — | A gate never reuses a compiler built from another tree | `scripts/check-gate-lib.sh` |

The rule-by-rule tables are checked claims: `scripts/check-assurance-controls.sh`
checks every refusal and acceptance they name, and builds the compiler
with an enforcement removed to show that the refusal fixtures reach it.

Each method has limits. Bootstrap convergence doesn't prove the
compiler correct, a model proves only the model, and fuzzing explores
the neighbourhood of the corpus.

## Known defects

- The compiler and the standard library can still turn a reference into
  a word with `(as v Int)`, and an `Int` slot can hold that word. A
  user file outside a directory named `core` gets `AX3073` unless the
  declaration says `effect(unsafe)`. The directory-name exemption also
  applies to user files (`MM-EXEC-9d`). A function result can't erase
  its type (`MM-VAL-24`).
- Some public functions still take a raw address, such as
  `Sys.sysSpawn`, so safe code can crash by passing
  a bad one (`MM-EXEC-9d`, [roadmap](roadmap.md)). Clock reads take no
  address and release their own scratch storage
  (`tests/stdlib/1005-clock-owned-scratch.ax`). Entropy returns owned
  bytes; its address-taking fills are internal
  (`tests/diagnostics/1512-entropy-addresses.ax`). Child polling owns its
  scratch too (`tests/stdlib/1006-child-poll-owned-scratch.ax`).
  Signal masking accepts only the mask
  (`tests/stdlib/1007-signal-mask-owned-scratch.ax`). Socket addresses own
  their bytes; raw builders and readers are internal
  (`tests/diagnostics/1515-socket-addresses.ax`). Wait and mapping addresses
  also stay internal (`tests/diagnostics/1516-wait-addresses.ax` and
  `tests/diagnostics/1517-mapping-addresses.ax`). Raw platform buffer, path
  and descriptor operations are internal
  (`tests/diagnostics/1518-platform-addresses.ax`).
- A closure with more than 46 captures retains counted captures without
  a reference map to release them (`MM-LIFE-2c`,
  `tests/stdlib/1004-capture-map-limit.ax`).
- A `lambda` that captures a value a `match` arm bound keeps a share of
  it that is never released, so a captured `File` never closes.
- Some `match` shapes keep a value they could release. A `let` bound
  to a `match` can keep the match's answer or the binding the match
  reads, and a function handed an owned `Option` that it reads a field
  out of keeps the `Option`. Each leaks, and none frees early.
- Cycles hold their memory until an arena reset.

## Using Axiom in a safety-related system

- Freeze the configuration: the commit, `--target`, `--opt`, `--threads`
  or not, the seed's `bootstrap/CHAIN` row, and the exact `opt`, `llc`
  and linker versions. Make sure `opt` is installed: a build without
  it only warns.
- Use the [restricted profile](restricted-profile.md) and its report.
  Its claims are checked over the whole program.
- Decide your safe state. A trap exits with a defined status; what the
  system does next is yours. On bare metal, an `isr(fault)` hook
  chooses the exit.
- Review the trusted set (`#unsafe=trusted` in `axiom symbols`) and
  every `extern` block, since nothing checks their bodies.
- Bound long-running memory with regions, and watch it with
  `memStats`.
- Hardware faults are out of scope. The handle table catches a flipped
  handle word; nothing else in the language detects memory corruption.

## Gaps to qualification

| Gap | What closes it | Needs |
|---|---|---|
| No independent review; one maintainer, with AI assistance, wrote the code and the checks | Reviewers separate from the implementation, working to a written plan | people |
| No plans written against a licensed standard | Development, verification, configuration and tool plans agreed with the assessor | licensed standards, assessor |
| No structural coverage of application object code | Statement, decision or MC/DC coverage on the target, plus analysis of compiler-added code | target, tools |
| Compiler-added code (counting, traps, the allocator, start-up) isn't traced to source | A per-construct analysis with tests reaching every emitted path | work |
| Nothing has run on embedded hardware; only QEMU boots the images | A named board running the embedded checks | hardware |
| No worst-case execution time or multicore interference analysis | Static or measurement-based timing analysis on the target processor | hardware, tools |
| No tool qualification data for the compiler or the report tool | Tool operational requirements, a qualification plan and traced test cases for one frozen configuration | assessor |
| LLVM is outside the project's control | Verify the executable rather than the toolchain, or use a qualified backend | assessor |

## Standards

Aviation and space projects need evidence for a frozen application and
toolchain. The links below identify the source documents; the evidence
column is Axiom's mapping, not a claim that an objective is satisfied.

| Basis | Scope | Axiom evidence and limits |
|---|---|---|
| [FAA AC 20-115D](https://www.faa.gov/documentLibrary/media/Advisory_Circular/AC_20-115D.pdf) | Recognises DO-178C for airborne software and DO-330 for software tool qualification | Seed lineage, reproducibility and the restricted profile provide inputs. Tool qualification and application verification remain project obligations. |
| [FAA AC 20-193](https://www.faa.gov/documentLibrary/media/Advisory_Circular/AC_20-193.pdf) | Assurance objectives for airborne multicore processors | Concurrency tests exercise language behaviour. They establish no timing or interference bound for an aircraft processor. |
| [NASA NPR 7150.2D](https://nodis3.gsfc.nasa.gov/displayDir.cfm?t=NPR&c=7150&s=2D) | Software engineering requirements, with applicability determined by software classification and approved tailoring | Specifications, configuration records and regression results are inputs. A mission needs its own classification, requirements traceability, verification and approved tailoring. |
| [NASA-STD-8739.8B](https://standards.nasa.gov/standard/NASA/NASA-STD-87398) | Software assurance, software safety and independent verification and validation throughout the software life cycle | The trusted set and known defects support review. Hazard analysis, verification independence and mission-specific assurance evidence remain project obligations. |
| [ECSS-Q-ST-80C Rev.2](https://ecss.nl/standard/ecss-q-st-80c-rev-2-software-product-assurance-30-april-2025/) | Software product assurance, including development tools and other software affecting the delivered product | Clause 5.6 covers tool selection, suitability and correct use; 6.2.6.12 covers milestone traceability review. The guarantee tables above provide trace links, with qualification gaps listed separately. |
| [ECSS-E-ST-40C Rev.1](https://ecss.nl/standard/ecss-e-st-40c-rev-1-software-30-april-2025/) | Space software engineering from requirements through operations and maintenance | Specifications and tests cover parts of the implementation. A mission still needs its own requirements, verification records and selected configuration. |

For a multicore deployment, freeze the processor, active cores, scheduler
and dynamic frequency settings. Identify shared cache, memory, interconnect
and device interference, then verify mitigations and timing on that target.
Ordered task answers and worker budgets provide no time-partitioning or
worst-case execution-time guarantee ([AC 20-193, section 5](https://www.faa.gov/documentLibrary/media/Advisory_Circular/AC_20-193.pdf)).

The two ECSS editions are dated 30 April 2025. Apply the edition and
tailoring agreed for your project. In particular, emulator runs provide
no evidence for radiation tolerance, hardware fault recovery or timing
on the flight hardware.

Automotive and general functional-safety projects need their own
assessment against ISO 26262 or IEC 61508-3. No clause mapping for those
standards is claimed here.

## Support

The supported release and its window are in [SECURITY.md](../SECURITY.md),
along with how to report a vulnerability. Every change is recorded in
[CHANGELOG.md](../CHANGELOG.md), and breaks to the standard library are
declared in `compat/BREAKING` ([compatibility](compatibility.md)).
Report a defect as a GitHub issue.
