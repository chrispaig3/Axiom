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

Nothing in Axiom is approved, and nothing here claims compliance with a
standard. Whether a system built with Axiom is fit for a mission
depends on that system, its hardware and its development process, and
an independent assessment of them.

## Reference configurations

The evidence on this page comes from these configurations. A check
that passes on one doesn't extend its claim to another.

| | H3 | H2 | E1 |
|---|---|---|---|
| Target | `darwin-aarch64` | `linux-aarch64` | `baremetal-aarch64` |
| Machine | Apple silicon, macOS 14 runner | AArch64, Ubuntu 24.04 runner | Cortex-A72 as modelled by QEMU, `virt` board, EL1 |
| LLVM | 23 (Homebrew `llvm@23`) | 18 (Ubuntu `llvm-18`) | the host's |
| Runtime | processes by default, `--threads` | processes by default, `--threads` | one thread plus `isr(irq)` and `isr(fault)` |
| Heap | `mmap` arena | `mmap` arena | static arena with `--heap-ceiling` |
| Runs in CI | the whole test battery | the whole test battery | compile-time checks, and the QEMU runs on the H3 leg |

CI also builds the compiler from the seed on `linux-x86_64`, and on
`freebsd-x86_64` and `freebsd-aarch64` in virtual machines, and
assembles code for every hosted target. Nothing has run on embedded
hardware.

Each CI run records the `opt`, `llc`, `clang`, `ld.lld` and `lld-link`
versions it used, and stops if a runner delivers another LLVM major.
Optimisation levels 0 to 3 are exercised by the `.optstable` fixtures
under `tests/stdlib/`; the default is 1.

## Guarantees and evidence

The rules are in [the memory model](memory-model.md) and
[the restricted profile](restricted-profile.md). The IDs match the
memory model's *Assurance evidence* table.

### A. Correctness of the runtime

| ID | Guarantee | Rule | Evidence |
|---|---|---|---|
| R-A1 | A `parallel` binding that traps inside a recovery point answers its status once | `MM-PAR-7` | `tests/stdlib/522-parallel-recover.ax`, `scripts/check-parallel.sh` |
| R-A2 | No child outlives its scope on abort, trap, return or end | `MM-PAR-7` | `scripts/check-parallel.sh`, `scripts/check-task.sh` |
| R-A3 | A refused spawn or failed join is status 78, never success | `MM-PAR-7` | `scripts/check-parallel.sh` |
| R-A4 | A finished thread returns its arena | `MM-PAR-6a` | `scripts/check-parallel.sh` (H2 only) |
| R-A5 | The allocator refuses a negative or unrepresentable size with status 70 | `MM-ALLOC-7a` | `tests/stdlib/520-alloc-size.ax` |
| R-A6 | Every unsafe primitive, syscall, `asm` form and `extern` call needs `effect(unsafe)` | `MM-EXEC-9c` | `tests/diagnostics/1010-unsafe-primitives.ax`, `tests/diagnostics/1080-unsafe-syscalls.ax` |
| R-A7 | A released block's free-list link can't be released as a count | `MM-LIFE-2k` | `tests/stdlib/521-release-filed.ax` |
| R-A9 | A count that would overflow traps with status 70 before the write | `MM-LIFE-2l` | `tests/stdlib/527-retain-overflow.ax` |
| R-A10 | An unused declaration changes no other declaration's meaning | none | `scripts/check-metamorphic.sh` |

Runtime traps exit with statuses 70 to 85, each with one meaning, at
every optimisation level (`scripts/check-trap-statuses.sh`; the table
is in [the memory model](memory-model.md)).

### B. Ownership and safe interfaces

| ID | Guarantee | Rule | Evidence |
|---|---|---|---|
| R-B1 | `vecGet` and `vecSet` trap with status 77 on a bad index before any read or write | `MM-MUT-5a` | `tests/stdlib/525-vec-set-bounds.ax` |
| R-B2 | Task pools keep at most their width of workers and handles | `MM-PAR-13` | `tests/stdlib/523-par-pool-bounded.ax`, `scripts/check-task.sh` |
| R-B3 | A region-allocated value can't escape its region by store, return, capture or argument | `MM-RGN-1` to `MM-RGN-6` | `scripts/check-region-escape.sh` |
| R-B7 | A dead chain of any depth is released without deep recursion, and no share is released twice | `MM-LIFE-2k` | `tests/stdlib/555-release-deep-chain.ax`, `scripts/check-reclaim-soak.sh` |
| R-B8 | Reuse is bounded by the allocator's size classes, and held, reusable and mapped bytes are readable with `memStats` | `MM-ALLOC-24`, `MM-ALLOC-25` | `tests/stdlib/703-memory-stats.ax`, `scripts/check-reclaim-soak.sh` |
| R-B9 | A recovery point allocates nothing, and a contained trap leaves the heap consistent | `MM-ALLOC-23` | `tests/stdlib/560-recover-record.ax` |
| R-B10 | A typed read or write checks its range before the kernel sees it | `MM-EXEC-9f` | `tests/stdlib/610-typed-io-bounds.ax` |
| — | Releasing the last share of a `File`, socket or database connection closes it once | `MM-EXEC-17` | `tests/stdlib/697-resource-owner.ax`, `tests/stdlib/698-file-lifetime.ax` |
| — | A `mut` local of a reference type releases the value a `set` overwrites and its last value at scope end, each once, and a lambda that captured it keeps its own share | `MM-MUT-1`, `MM-VAL-16` | `tests/stdlib/708-mut-slot-reassign.ax`, `tests/stdlib/709-mut-slot-capture.ax` |

A `mut` local releases only when the compiler can show that no read of
it is still in use at the `set` or the scope end, and never when its
type is a type variable or a `Vec`. Any other `mut` local keeps what it
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
| R-C1 | No container or unborrowed reference is captured by a concurrent binding | `MM-PAR-6` | `tests/diagnostics/656-parallel-container-capture.ax` |
| R-C2 | A mutex excludes, and its guard releases it once on every way out of its scope, a recovered trap included; every blocking call has a timed form; tasks report failure, deadline and cancellation per slot | `MM-PAR-11` to `MM-PAR-13`, `MM-PAR-15` | `tests/stdlib/800-mutex-guard.ax`, `scripts/check-task.sh`, `scripts/check-protocol-model.sh` |
| R-C2a | A bounded channel delivers every word exactly once, in order per sender | `MM-PAR-10` | `tests/stdlib/528-chan.ax`, `scripts/check-chan.sh` |
| R-C3 | Atomics are sequentially consistent on every hosted target, and the litmus tests show no forbidden outcome | `MM-PAR-1`, `MM-PAR-9` | `scripts/check-atomics.sh` |
| R-C4 | A misaligned atomic traps with status 82 | `MM-PAR-9` | `tests/stdlib/544-misaligned-atomic.ax` |
| R-C6 | Channels, mutexes and tokens are sealed, and a freed or forged handle traps with status 85 | `MM-PAR-8` | `tests/stdlib/570-handle-freed.ax`, `scripts/check-handles.sh` |
| R-C7 | A `parallel` binding can borrow its parent's strings and immutable data, and no binding's count traffic reaches the parent | `MM-PAR-6b` | `tests/stdlib/630-parallel-borrow.ax`, `scripts/check-race.sh` |
| R-C8 | A pure parallel computation answers the same at every width and in both lowerings | `MM-PAR-14` | `tests/stdlib/620-par-float-order.ax` |

`scripts/check-race.sh` runs the threaded programs under
ThreadSanitizer. It covers the thread lowering only.

### D. Embedded and real-time

| ID | Guarantee | Rule | Evidence |
|---|---|---|---|
| R-D1 | The restricted profile refuses recursion, steady-state allocation and the other RP rules over the whole program, and bounds stack use from machine code | RP-1 to RP-9 | `scripts/check-report.sh`, `scripts/check-stack-bound.sh` |
| R-D2a | Device registers are read and written at their own width, with barriers | `MM-FFI-8` | `scripts/check-embedded.sh` |
| R-D2b | An unhandled CPU exception exits 81, and an `isr(fault)` hook chooses the exit once | `MM-EXEC-16`, `MM-EXEC-19` | `tests/embedded/fault-hook.ax`, `scripts/check-isr.sh` |
| R-D2c | A periodic interrupt workload and a DMA driver keep their budgets and ownership protocol | `MM-EXEC-18` | `tests/embedded/periodic.ax`, `tests/embedded/dma.ax` |
| R-D2e | The MMU and caches are on before `main`, with read-only code, non-executable data and stack guards | `MM-EXEC-19` | `tests/embedded/overflow.ax` |

R-D2b, R-D2c and R-D2e run under QEMU on the darwin-aarch64 CI leg.
Emulator evidence is not hardware evidence: QEMU models no caches,
timing or bus faults.

### E. The evidence itself

| ID | Property | Evidence |
|---|---|---|
| R-E1 | The compiler rebuilds itself byte for byte, two builds agree, and a diverse double compile agrees with an independent checker | `scripts/check-bootstrap.sh`, `scripts/check-reproducible.sh`, `scripts/check-ddc.sh` |
| — | The seed is its source's emission, and its lineage replays to the original anchor | `scripts/check-seed-provenance.sh`, `scripts/check-seed-lineage.sh` |
| — | Executable models of the allocator and the channel protocol agree with the runtime | `scripts/check-runtime-model.sh`, `scripts/check-protocol-model.sh` |
| — | Seeded mutants never crash the compiler, and accepted mutants produce IR `llc` accepts | `scripts/check-fuzz.sh` |
| — | Every gate fails when the property it checks is removed | `scripts/check-gate-lib.sh` |

Each method has limits. Bootstrap convergence doesn't prove the
compiler correct, a model proves only the model, and fuzzing explores
the neighbourhood of the corpus.

## Known defects

- A counted element taken out of a `Vec` by `vecPop`, and a vector
  passed straight to `vecGet` without a binding, are never released.
- Safe code can still turn a reference into a word with `(cast Int v)`,
  or by storing it in an `Int` container slot or through `memSetWord`.
  A value that leaves this way stops being tracked. A function result
  can't do it (`MM-VAL-24`).
- `fileFd` with `sysCloseFd` can close a descriptor its `File` still
  owns.
- Disposing of a channel or mutex while another binding uses it is a
  race the handle table catches only after the free.
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

The route that fits Axiom's evidence is to verify the executable your
compiler produces, and treat the compiler as an unqualified tool whose
checks reduce risk. Its evidence could contribute to these areas:

- **DO-178C and DO-330**: configuration management (reproducible
  builds, seed lineage); coding standards (the restricted profile);
  inputs to tool qualification if you choose that route. Multicore
  objectives in AC 20-193 need evidence from your processor.
- **ISO 26262**: Part 6 coding and design guidelines (typing, the
  restricted profile, no recursion or steady-state allocation); Part 8
  tool confidence (validation by the checks, reproducibility).
- **IEC 61508-3**: support tools and translators, and the language
  subset.
- **ECSS-Q-ST-80 and ECSS-E-ST-40**: tool justification, and the
  bootstrap's independence from a supplier.

These mappings were made without the licensed texts. Check every one
against the edition your project uses.

## Support

The supported release and its window are in [SECURITY.md](../SECURITY.md),
along with how to report a vulnerability. Every change is recorded in
[CHANGELOG.md](../CHANGELOG.md), and breaks to the standard library are
declared in `compat/BREAKING` ([compatibility](compatibility.md)).
Report a defect as a GitHub issue.
