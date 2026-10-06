# Axiom 1.0 roadmap

This is the one plan for Axiom 1.0: what 1.0 means, what is done and
what is left. [What's ready today](status.md) describes the current
release, and the [assurance page](assurance.md) maps each guarantee to
its evidence. When work lands, its row here changes in the same commit.

## What 1.0 means

Axiom 1.0 is a release you can build production software on with the
confidence you would have in Rust or Ada.

- **Safe code is memory-safe and resource-safe.** Code without
  `;@axiom:effect(unsafe)` can't free a value twice, use one after it
  is freed, forge a reference, or leak an owner it dropped. Files,
  sockets and other resources close themselves.
- **Every check means what it says.** A claim the compiler can't back
  is an error. A warning stays only for a stated limit of the analysis,
  with a way to make the code answerable.
- **There's one way to do each thing.** The standard library has one
  spelling per operation, and no legacy form is accepted.
- **The surface is stable.** At 1.0 the compatibility rules become
  enforceable (`COMPAT-6`), and every break before then has a row in
  `compat/BREAKING`.
- **Trunk is green** on linux-aarch64 and darwin-aarch64, with a
  reproducible toolchain record.

Qualification against a safety standard is not part of 1.0. The
[assurance page](assurance.md#gaps-to-qualification) lists what an
integrator would still need.

## Where things stand

| Workstream | State |
|---|---|
| [Memory and resource safety](#memory-and-resource-safety) | In progress |
| [Checks and claims](#checks-and-claims) | In progress |
| [One way to do each thing](#one-way-to-do-each-thing) | In progress |
| [Standard library](#standard-library) | In progress |
| [Concurrency and bounded execution](#concurrency-and-bounded-execution) | In progress |
| [Tools](#tools) | Not started |
| [Platforms and release](#platforms-and-release) | In progress |

## Memory and resource safety

| Item | State | Where it's specified or tested |
|---|---|---|
| A `mut` slot owns what it holds, and releases what `set` overwrites | Done | `MM-MUT-1`, `tests/stdlib/708-mut-slot-reassign.ax` |
| A heap value returned where the signature says `Int` is refused | Done | `MM-VAL-24`, `tests/diagnostics/1240-record-through-int.ax` |
| Identity and hashing of a heap value use the typed `Addr`, not a cast | Done | `tests/stdlib/810-addr-identity.ax` |
| A container owns its elements: a `Vec` is released at scope end, and ownership follows the element type, not the constructor | Done | `MM-LIFE-2m`, `tests/stdlib/770-vec-files.ax` |
| An element passed beside its container to a function that overwrites its slot keeps a share, as one bound by a `let` does | Done | `MM-LIFE-2m`, `tests/stdlib/778-vec-lent-argument.ax` |
| A field passed beside its struct, or a result typed by a type variable, keeps a share for the call | Not started | `MM-LIFE-2m` |
| An element taken out with `vecPop` is released, and a vector passed straight to `vecGet` is not leaked | Not started | `MM-LIFE-2m` |
| `vecFree` and `mapFree` leave safe code, so an early drop can't free a block still in use | Not started | |
| CI builds the compiler with a poisoned allocator and checks it still reaches its fixpoint | Not started | |
| No cast, `Int` container or raw store lets a heap value become an untracked word in safe code | Not started | `MM-VAL-24` |
| Raw-address functions leave the public library, so safe code can't forge an address | Not started | |
| `fileFd` and the raw descriptor calls can't close a descriptor a `File` owns | In progress | |
| Standard input, output and error are `File` values, with one owned poller and one terminal raw-mode guard | Not started | |
| Secrets and keys wipe themselves when dropped, and a child process is an owner | Not started | |
| A reference can be promoted out of a region | Planned | `MM-RGN-7` |
| Cycles leak until an arena reset | Accepted for 1.0 | `MM-LIFE-3` |

## Checks and claims

| Item | State | Where it's specified or tested |
|---|---|---|
| A misspelt checked AXTAG key is an error | Done | `AX3039` |
| An `effect(unsafe)` claim is judged by what the body itself performs | Done | `AX3010`, `tests/diagnostics/1200-unsafe-claim-open-row.ax` |
| A statically certain defect or a refuted claim is an error, not a warning | In progress | `tests/diagnostics/severity.policy` |
| Retired and never-assigned codes are recorded and never reused | Done | `ERR-DIAG-2` |
| A check after an error is poisoned, not cascaded | Planned | `ERR-DIAG-3` |
| A cast to a spawn handle counts as forging | Not started | |
| Two signatures for one name are refused, instead of the later one winning | Done | `tests/diagnostics/1255-duplicate-signature.ax` |

## One way to do each thing

| Item | State | Where it's specified or tested |
|---|---|---|
| Legacy CLI and syntax removed: `axiom FILE`, expression `fn`, keyword struct construction, format aliases | Done | `compat/BREAKING` |
| The precondition tag removed; contracts are `pre` and `post` | Done | `AX3095` |
| Macro hygiene has one implementation | Done | `MAC-HYG-10` |
| Literal identifiers in macro patterns compare by binding, not spelling | Planned | `MAC-HYG-9`, `MAC-LANG-14a` |
| `macro` and `emacro` become one form | Not started | [macro-system.md](macro-system.md) |
| One code-generation route: the MIR route is finished or removed | Not started | |

## Standard library

| Item | State | Where it's specified or tested |
|---|---|---|
| Shorter, consistent names, with duplicates removed and internals private | In progress | `compat/BREAKING` |
| Failure answers a `Result` or `Option`, never a sentinel | In progress | `ERR-ADOPT-1`, `compat/SENTINELS` |
| `Map` is generic, and `vecSortBy` takes a typed comparator | Not started | |
| `Par` folds into `Task` | Not started | |
| Sleep, a monotonic clock and a would-block test for sockets | Not started | |

## Concurrency and bounded execution

| Item | State | Where it's specified or tested |
|---|---|---|
| Channels, mutexes and cancel tokens are owners, so disposal can't race a use | Done | `MM-PAR-15`, `MM-PAR-16`, `tests/stdlib/803-shared-owner.ax` |
| Owned task inputs and results, with cleanup across joins, cancellation and failure | In progress | `MM-PAR-6` |
| Fixed worker, queue, memory and stack budgets, with exhaustion and shutdown tests | Not started | `MM-ALLOC-20` |
| Shared mutable heap graphs across tasks | Not started | |

## Tools

| Item | State |
|---|---|
| Debug information (DWARF), a message on SIGSEGV, and inlined frames in backtraces | Not started |
| An assembler error inside an `asm` template is reported at the form | Not started |
| The test runner runs tests in parallel | Not started |
| The language server answers inside macro invocations | Not started |
| Packages can pin a version | Not started |
| A published performance profile | Not started |

## Platforms and release

| Item | State |
|---|---|
| CI green on linux-aarch64 and darwin-aarch64 | Done |
| Reproducible toolchain records for every supported target | In progress |
| The compiler hosts itself on Windows, and crypto runs there | Not started |
| The embedded checks run on a named board | Not started |
| Compatibility rules enforced at 1.0 (`COMPAT-6`) | Planned |

The maintainer cuts releases.
