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
- **The `stable` branch is green** on linux-aarch64 and darwin-aarch64, with a
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
| [Tools](#tools) | In progress |
| [Platforms and release](#platforms-and-release) | In progress |

## Memory and resource safety

| Item | State | Where it's specified or tested |
|---|---|---|
| A `mut` slot owns what it holds, and releases what `set` overwrites | Done | `MM-MUT-1`, `tests/stdlib/708-mut-slot-reassign.ax` |
| A heap value returned where the signature says `Int` is refused | Done | `MM-VAL-24`, `tests/diagnostics/1240-record-through-int.ax` |
| Identity and hashing of a heap value use the typed `Addr`, not a cast | Done | `tests/stdlib/810-addr-identity.ax` |
| A container owns its elements: a `Vec` is released at scope end, and ownership follows the element type, not the constructor | Done | `MM-LIFE-2m`, `tests/stdlib/770-vec-files.ax`, `tests/stdlib/895-scalar-element-read.ax` |
| An element passed beside its container to a function that overwrites its slot keeps a share, as one bound by a `let` does | Done | `MM-LIFE-2m`, `tests/stdlib/778-vec-lent-argument.ax` |
| A field passed beside its struct, or an element handed to a function whose result is a type variable, keeps a share for the call, and the result keeps it when it is that element | Done | `MM-LIFE-2m`, `tests/stdlib/894-field-beside-struct.ax`, `tests/stdlib/900-lent-arg-tyvar-result.ax` |
| A `match` over a field or a vector element, and a `let` of one, keep the value while the code under them overwrites its place | Done | `MM-LIFE-2m`, `tests/stdlib/901-match-place-overwrite.ax` |
| A `match` arm that computes a word from its binder, as `(Some (strLen a))` does, lets the scrutinee go | Done | `MM-LIFE-2c`, `tests/stdlib/902-match-arm-over-binder.ax` |
| An element taken out with `vecPop` is released: a trusted function declares `result(owned)` and the caller hands the share back | Done | `MM-LIFE-2n`, `tests/stdlib/846-vec-pop-release.ax` |
| A vector passed straight to `vecGet` is not leaked | Done | `MM-LIFE-2m`, `tests/stdlib/893-vecget-temporary.ax` |
| Final reference results from calls with surplus arguments own one share through temporaries, returns and generic field stores | Done | `tests/stdlib/962-overapplied-result-ownership.ax` |
| `vecFree` and `mapFree` leave safe code, so an early drop can't free a block still in use | Done | `tests/stdlib/406-array-form-large-block.ax`, `tests/stdlib/489-map-free.ax` |
| CI builds the compiler with a poisoned allocator and checks it still reaches its fixpoint | Done | `scripts/check-poisoned-alloc.sh` |
| Released blocks larger than 64 KiB can be reused | Done | `MM-ALLOC-25`, `tests/stdlib/974-large-block-reuse.ax` |
| Large vectors grow inside separate address reservations | Experimental: single-threaded POSIX heaps without a cap | `MM-ALLOC-26`, `tests/stdlib/1002-vec-in-place-growth.ax` |
| Linked data holds no shares: a link is an index into a vector, stored in the width its type names, and links that form a cycle are freed with their vector | Done | `MM-VAL-10b`, `tests/stdlib/997-links.ax` |
| Stack overflow reports a named runtime trap | Native POSIX entry, worker and task stacks; Windows threads; bare-metal guard | `tests/stdlib/977-native-stack-overflow.ax`; host-owned archive stacks remain |
| No cast, `Int` container or raw store lets a heap value become an untracked word in safe code | Not started | `MM-VAL-24` |
| The raw memory layer and the word-to-reference accessors are internal to the library, so safe code can't read memory at an address or forge a reference from a word | Done | `MM-EXEC-9g`, `tests/diagnostics/1470-internal-import.ax` |
| Public functions that take a raw address, such as `sysRandomBytes`, `sysWaitWord` and the clock reads that fill a caller's buffer, take typed values instead | Not started | `MM-EXEC-9d` |
| `fileFd` and the raw descriptor calls can't close a descriptor a `File` owns | Done | `MM-EXEC-17a`, `tests/diagnostics/1225-descriptor-hole.ax` |
| Standard input, output and error are `File` values, with one owned poller and one terminal raw-mode guard | Done | `MM-EXEC-17b`, `tests/stdlib/785-stdio-file.ax`, `tests/stdlib/786-poller-owned.ax` |
| Secrets and keys wipe themselves when dropped, and a child process is an owner | Not started | |
| Handler invocations cannot retain references reclaimed by an operation's region or recovery scope; unseen handler bodies are conservatively refused across shorter extents | Done | `MM-RGN-3`, `tests/diagnostics/1474-handler-keeps-argument.ax`, `tests/region/handler-unseen.ax` |
| Backing views, captures and scalar stores retain valid lifetimes through vector growth, recovery and immutable parallel borrowing | Tested shapes | `tests/region/lifetime-controls.ax`, `scripts/check-region-escape.sh` |
| Typed promotion of owned values out of a region, preserving nested ownership, aliases and sharing | Planned | `MM-RGN-7` |
| Cycles of references leak until an arena reset; cycles of links don't | Accepted for 1.0 | `MM-LIFE-3`, `MM-VAL-10b` |

## Checks and claims

| Item | State | Where it's specified or tested |
|---|---|---|
| Compiler data uses typed structures and checked effect boundaries across every phase | In progress | Typed AST and effect values cross every phase. Function registries, checker and codegen contexts, body scopes, region records, expansion frames, bindings and repetition matches keep typed owners. Exact function indexes use compact Links into owning tables. The CLI and REPL handoff rejects structural syntax edits and supplies checked function types for numeric lowering. Packed metadata, parser result carriers, alias revision tracking and a typed semantic IR remain |
| Optional compiler lookups use typed results throughout the checker, emitter and tools | In progress | Checker scopes, function and type entries, graph searches, emitter tables, module filters, format specifiers, expansion matches and LSP buckets use `Option` for absence. Checker indexes, diagnostic witnesses, function arities, unit identities, named-unit lookup indexes, extern queries, assembler diagnostic locations, native-tool path lookups, optimiser outcomes, split-process outcomes, synchronous native-tool results, and manifest presence and key values also use typed results. Parameter-type queries, match-arm state, emitter symbol indexes, AXIR record kinds and assembler description queries keep explicit Options. Assembler delimiters, fields and target arms are tested by `tests/selfhost/1049-codegen-asm-options.ax`. Optional checker helper inputs, emitter state, expander builders and other tool lookups remain. Child exit codes remain numeric at the OS and CLI boundaries |
| Native tool arguments keep their string vector type to the syscall boundary | Done | `scripts/check-driver.sh`, `scripts/check-bootstrap.sh` |
| Known callback arguments honour effect restrictions through forwarding and captures | Done | `tests/diagnostics/1463-callback-restrictions.ax` |
| Opaque callback aliases preserve incomplete effect rows through forwarding, captures and mutable bindings | Done | `tests/diagnostics/1482-callback-alias-effects.ax`, `tests/selfhost/1042-callback-alias-effects.ax` |
| Stored lambdas contribute their resolved effects at field calls | Done | `tests/diagnostics/1462-lambda-field-effects.ax` |
| Stored lambdas retain cast facts for deep restrictions | Done | `tests/diagnostics/1464-lambda-field-casts.ax` |
| A function-typed field declares its effects, and every store into it is checked against the declaration | Done | `tests/stdlib/994-field-effects.ax`, `tests/diagnostics/1501-field-effect-parameter.ax` |
| A function that stores its parameter in a declared field passes the requirement on to its callers | Planned | `AX3143` refuses the store |
| Contracts are visible in hover, signature help, completion and generated documentation | Done | `tests/lsp/drive.py`, `scripts/check-stdlib-api.sh` |
| Contracts diagnose certainly false calls and postconditions at compile time | Planned | |
| A misspelt checked AXTAG key is an error | Done | `AX3039` |
| Handler values propagate effects through local bindings and handler parameters | Done | `tests/diagnostics/1390-handler-effects.ax`, `tests/stdlib/940-handler-values.ax` |
| Unsafe declarations retain type, effect and restriction checks | Done | `tests/diagnostics/1395-unsafe-checks-retained.ax` |
| Checked memory boundaries explain source representation and lifetime obligations consistently in the compiler and editor | Done | `tests/lsp/memory-boundaries.py` |
| An `effect(unsafe)` claim is judged by what the body itself performs | Done | `AX3010`, `tests/diagnostics/1200-unsafe-claim-open-row.ax` |
| A drop's effects count where the value drops, not only where it was made | Not started | `tests/stdlib/712-drop-effects-at-creation.ax` holds the current limit |
| A statically certain defect or a refuted claim is an error, not a warning | Done | `tests/diagnostics/severity.policy` |
| Retired and never-assigned codes are recorded and never reused | Done | `ERR-DIAG-2` |
| A check after an error is poisoned, not cascaded | Done | `ERR-DIAG-3`, `tests/diagnostics/1380-poisoned-checks.ax` |
| A definition without a signature draws one diagnostic, not one per use of its parameters | Done | `ERR-DIAG-3`, `tests/diagnostics/1484-unsigned-parameter-poison.ax` |
| A cast to a spawn handle counts as forging | Done | `MM-PAR-8`, `tests/diagnostics/1260-spawn-forging-cast.ax` |
| Two signatures for one name are refused, instead of the later one winning | Done | `tests/diagnostics/1255-duplicate-signature.ax` |

## One way to do each thing

| Item | State | Where it's specified or tested |
|---|---|---|
| Imports form the module header and cannot appear later or inside expressions | Done | `tests/diagnostics/1400-late-import.axbad`, `tests/diagnostics/1401-nested-import.axbad`, `tests/diagnostics/1402-lambda-import.axbad` |
| Block-local declarations and named struct construction across compiler, library, documentation and editor tools; retire grouped bindings and positional struct construction | Done | `tests/stdlib/963-block-local-bindings.ax`, `tests/stdlib/964-named-struct-construction.ax` |
| REPL uses the brand palette and shares diagnostic and language help with the CLI | Done | `scripts/check-repl-tui.sh`, `tests/repl/170-explain-shape.txt` |
| Editor and REPL completion exclude retired syntax | Done | `tests/lsp/drive.py`, `scripts/check-replcomp.sh` |
| Fixed-width signed and unsigned integers through 64 bits, with explicit casts and width-correct operators | Done | `tests/stdlib/948-fixed-width-integers.ax`, `tests/stdlib/949-fixed-width-alias-callback.ax` |
| Compact fixed-width integer struct fields, with aligned reference maps and native allocation measurements | Done | `tests/stdlib/959-compact-struct-fields.ax` |
| Compiler bracket and format flags use guarded UInt8 storage with measured allocation savings | Done | `tests/selfhost/1018-compiler-byte-storage.ax`, `tests/selfhost/272-highlight.ax` |
| Compact ADT and vector storage with complete generic storage evidence | Planned | |
| Wider integer literals, widths beyond 64 bits and checked fixed-width FFI shims | Planned | |
| Transparent type aliases support parameters, simultaneous substitution and finite expansion | Done | `tests/stdlib/946-generic-aliases.ax`, `tests/diagnostics/1420-generic-alias-arity.ax`, `tests/diagnostics/1421-generic-alias-parameters.axbad`, `tests/diagnostics/1422-recursive-alias.ax` |
| Generic bodies preserve parameters through returned containers, ADTs and callbacks; each call constrains repeated parameters independently | Done | `tests/diagnostics/1443-generic-result-rigidity.ax`, `tests/stdlib/956-generic-result-rigidity.ax` |
| Generic struct fields substitute receiver arguments simultaneously through reads and writes, including reordered and nested parameters | Done | `tests/selfhost/1040-generic-field-substitution.ax`, `tests/diagnostics/1480-generic-field-substitution.ax` |
| Distinguish homonymous nominal types across module boundaries, runtime protocols and host bindings | Done | `tests/stdlib/954-nominal-identity.ax`, `tests/stdlib/957-main-result-nominal.ax`, `tests/diagnostics/1444-err-protocol-provenance.ax`, `tests/ffi/host/nominal.ax` |
| Numeric conversions are explicit; mixed numeric operands and incompatible ADT parameters are refused | Done | `tests/diagnostics/1117-mixed-numeric-operands.ax`, `tests/diagnostics/1410-explicit-numeric-boundaries.ax` |
| Explicit numeric conversions document rounding and range; exact conversions refuse value loss | Done | `tests/stdlib/947-exact-numeric-conversions.ax` |
| Legacy CLI and syntax removed: `axiom FILE`, expression `fn`, keyword struct construction, format aliases | Done | `compat/BREAKING` |
| Macro hygiene has one implementation | Done | `MAC-HYG-10` |
| Literal identifiers in macro patterns compare by binding, not spelling | Done | `MAC-HYG-9`, `tests/selfhost/1025-macro-literal-scopes.ax` |
| Repeated macro pattern binders constrain equal syntax at one repetition depth | Done | `MAC-LANG-15`, `tests/selfhost/1026-macro-repeated-binders.ax` |
| `macro` and `emacro` become one form: a rule's template is declarations or one expression, and the invocation's position picks | Done | `MAC-LANG-14`, `tests/stdlib/930-macro-both-positions.ax` |
| Errors propagate with a postfix `?` | Done | `ERR-SUGAR-4`, `tests/stdlib/847-propagate.ax`, `tests/diagnostics/1300-propagate-position.ax` |
| A unit type with a value, `()`, so an `if` without an else, a dropped branch and a procedure need no filler `0` | Done | `tests/stdlib/890-unit-and-if.ax`, `tests/stdlib/892-dropped-branches.ax` |
| Explicit numeric conversion uses `(as value Type)`; bit reinterpretation has named Float operations | Done | `tests/stdlib/943-as-numeric.ax`, `tests/diagnostics/1411-as-boundaries.ax` |
| AXQL select aliases use `(alias expression name)` and keep `as` for language conversions | Done | `tests/axqlite/620-macro-text.ax`, `tests/axqlite/625-macro-forms.ax` |
| Prefix pipelines evaluate each stage once, with explicit argument placement | Done | `tests/stdlib/945-pipelines.ax`, `tests/diagnostics/1430-pipeline-boundaries.ax` |
| An `if` test that matches one pattern, `(if (let PATTERN value) then else)`, binding its names for the branch it chooses | Done | `tests/stdlib/993-if-let.ax`, `tests/diagnostics/1496-if-let-scope.ax` |
| One code-generation route: the MIR route is finished or removed | Done | `scripts/check-mir.sh` |

Numeric values never widen or narrow implicitly. Expected types do not
insert conversions into calls, returns, assignments or constructor
payloads. Algebraic data types (ADTs) keep their type arguments and payload
representation. Convert payloads explicitly when constructing a different
ADT instantiation.

## Standard library

| Item | State | Where it's specified or tested |
|---|---|---|
| Shorter, consistent names, with duplicates removed and internals private | In progress | `compat/BREAKING` |
| UUID versions 4 and 7 with injected randomness and deterministic seeded constructors | Done | `tests/stdlib/970-uuid.ax`, `tests/stdlib/973-uuid-properties.ax` |
| Failure answers a `Result` or `Option`, never a sentinel | In progress | `ERR-ADOPT-1`, `compat/SENTINELS` |
| `Map` is generic, and `vecSortBy` takes a typed comparator | Done | `tests/stdlib/081-map-value-type.ax`, `tests/stdlib/405-vec-sort.ax` |
| `Par` folds into `Task` | Done | `tests/stdlib/476-par-pool.ax`, `tests/stdlib/492-par-pool-checked.ax` |
| Sleep and a monotonic clock | Done | `MM-PAR-12`, `tests/stdlib/851-instant-sleep.ax` |
| A would-block test for sockets: `errorKind` answers `WouldBlock` | Done | `tests/stdlib/840-error-kind.ax` |
| AXQLite: links between tables, a dump that loads back, and messages that name the statement and say what to do | Done | `tests/axqlite/513-axql-links.ax`, `tests/axqlite/618-api-errors.ax` |
| AXQLite: aggregates, `GROUP BY`, functions, `LIKE`, `IN`, `UPSERT`, `DEFAULT`, `CHECK` and `ALTER TABLE ADD COLUMN` | Done | `tests/axqlite/512-axql-aggregates.ax`, `tests/axqlite/514-axql-constraints.ax` |
| AXQLite: `DROP COLUMN` and `RENAME COLUMN` | Done | `tests/axqlite/516-axql-alter.ax` |
| AXQLite: link paths of more than one step, and links followed backwards | In progress | Forward paths, including `.*`, predicates and grouping, are tested by `tests/axqlite/517-axql-link-paths.ax` and `tests/axqlite/627-api-link-paths.ax`; backwards traversal remains |
| AXQLite: a change feed a program can watch for a table's changes | Not started | |
| AXQLite: compacting a database file in place | Not started | |

## Concurrency and bounded execution

| Item | State | Where it's specified or tested |
|---|---|---|
| Channels, mutexes and cancel tokens are owners, so disposal can't race a use | Done | `MM-PAR-15`, `MM-PAR-16`, `tests/stdlib/803-shared-owner.ax` |
| Typed promotion of owned task inputs and results across joins, with cleanup on cancellation and failure | In progress | `MM-PAR-6`, `MM-RGN-7` |
| Task slab sizes are checked before mapping or spawning; indices cross without overflow-prone packing | Done | `tests/stdlib/941-task-index-and-size.ax` |
| Explicit task grain with bounded range jobs, ordered answers and per-range budgets | Done | `tests/stdlib/951-task-ranges.ax`, `tests/stdlib/952-task-ranges-lifecycle.ax` |
| Checked streaming callbacks reject retained answers and temporary allocations, with explicit forwarding contracts | Done | `tests/stdlib/953-scoped-task-fold.ax`, `tests/diagnostics/1440-scoped-callback-escape.ax` |
| Cancellation is checked between spawn attempts, and grace starts at the observed shutdown boundary | Done | `tests/stdlib/960-task-launch-cancellation.ax`, `tests/litmus/check-task-launch.py` |
| Checked numeric callbacks with primitive captures, local accumulators and fixed-width task answers | Done | `tests/stdlib/961-task-compute-contract.ax`, `tests/diagnostics/1445-compute-callback.ax` |
| Scale multicore work with bounded worker reuse and scheduling, preserving isolation, submit order and cancellation | Planned | `MM-PAR-3`, `MM-PAR-5`, `MM-PAR-17` |
| A `parallel` form keeps no arena storage once it returns, in both lowerings | Done | `tests/litmus/par-forms.ax`, `scripts/check-parallel.sh` |
| Fixed worker, queue, memory and stack budgets, with exhaustion and shutdown tests | Done | `MM-PAR-17`, `tests/stdlib/920-task-stack.ax` |
| Shared mutable heap graphs across tasks | Not started | |

Worker reuse requires the checked `compute(worker)` boundary: general
callbacks can mutate a captured vector independently in each fresh
process, while serial reuse would accumulate those mutations. The
compute entry still forks each invocation. Persistent scheduling,
measured startup amortisation and a broader checked numeric syntax,
including pattern matching, remain work to do.

## Tools

| Item | State |
|---|---|
| Formatting preserves the import header, doc-comment attachment and literal contents, without trailing layout whitespace | Done |
| Width-aware argument packing and attached call comments, with batch preflight, stdin/stdout and non-writing diffs | Done |
| Long function headers, signatures, types, aliases, selective imports and positional patterns share canonical list layout | Done |
| Doc comments: `;;` documents the declaration below and `;;!` the module, and hover, the library reference and `axiom doc` read them | Done |
| Hover explains every word of the language: keywords, builtin types, effects, operators, AXTAG keys and values, and imported modules | Done |
| Query literals share AXQL's parser and lexer for hints, hover, completion and semantic tokens | Done |
| Every public standard library name carries a doc comment, and every module a `;;!` block | Done |
| `;@axiom:nolint` quiets hints and warnings by name, code or group, per declaration or per file, and never an error | Done |
| The language server sends semantic tokens, so every editor colours keywords, functions, macros, constructors, fields and effects apart from variables | Done |
| A VS Code extension ships in the repository, with a TextMate grammar and the language client (`editors/vscode/`) | Done |
| Tree-sitter colours each token the way VS Code does, gated character by character | Done |
| Tree-sitter colours function and macro uses by their definitions, including forward and imported names | In progress | Later uses of signed functions and local macros are covered by `tree-sitter-axiom/test/highlight/locals-and-records.ax` and `tree-sitter-axiom/test/highlight/local-macros.ax` |
| The VS Code extension is published to the marketplace | Not started |
| `axiom doc` renders the documentation and the library reference locally and opens them in your browser | Done |
| Debug information (DWARF), a message on SIGSEGV, and inlined frames in backtraces | Not started |
| An assembler error inside an `asm` template is reported at the form | Done |
| `asm` takes floating-point, vector and memory operands | Not started |
| The restricted profile requires `nostack` on every selected arm of an allowed `asm` body | Done |
| Selected steady and nonblocking entries are analysed transitively; stale or ambiguous assurance exceptions fail closed | Done |
| Imported foreign items keep separate checker, source and linker identities when their source names match | Done |
| Resource reports consume checked `Spawn` and `Block` effects, preserve handled effect subtraction and refuse unknown kernel calls in nonblocking entries | Done |
| Stack reports cover every selected source entry and the assembled IRQ save and dispatch extent; additional machine roots cannot bypass main | Done |
| Selective foreign-item imports and transitive foreign references preserve visibility and module resolution | Done | `tests/profile/verify-foreign-resolution.py` |
| Selective import lists are validated inside every imported module, including unused names | Done | `tests/diagnostics/441-nested-import-name-list.ax` |
| The test runner runs tests in parallel | Done |
| Compiler scratch buffers and backtrace metadata release their owned Strings | Done; `tests/selfhost/emitter-line-buffer.py`, `tests/selfhost/emitter-pending-strings.py`, `tests/selfhost/emitter-line-metadata.py` |
| Compiler binder summaries and pruning indexes release their temporary interners, memo records and line reads | Done; `tests/selfhost/emitter-binder-summary.py` and `tests/selfhost/emitter-prune-owner.py` |
| Compiler argument register ledgers own and retire their copied text | Done; `tests/selfhost/emitter-argument-registers.py` |
| Extern symbol scans allocate no search string for each emitted line | Done; `tests/tools/emitted-symbol-match.py` |
| UTF-16 ranged document edits apply in order and atomically, with monotonic versions and versioned diagnostics | Done |
| The language server cancels obsolete work and serves requests from revisioned background analysis on hosts with process and poller support | Done |
| Unsaved imported documents feed checks and navigation, with transitive dependency invalidation and diagnostics for open modules | Done |
| Workspace request results are cached by revision, with exact file and module-search validation | Done |
| Parsed and checked semantic models are reused across different requests | Not started |
| Completion uses expected types, offers auto-import edits and resolves expensive details on demand | In progress; negotiated on-demand details and documentation are tested by `tests/lsp/completion-resolve.py`. Expected types and auto-import edits remain |
| Safe assists organise top-level imports and preserve attached comments | Done; `tests/lsp/organize-imports.py` checks source edits and refusals |
| Semantic tokens support range and delta requests | Done |
| The language server answers inside macro invocations | Not started |
| Packages can pin a version | Done; exact Git commits, separate revision checkouts and offline verification are tested by `tests/tools/package-pins.py` |
| Independent module lexing and parsing in bounded workers | Done | Workers run by default once an import frontier reaches eight modules; `AXIOM_FRONTEND_JOBS=1` forces serial and `2` to `8` sets the width. Compact syntax packets share string storage in the parent, and parity with the serial path is tested by `tests/frontend/parallel/verify.py` |
| A published performance profile | Not started |

The editor comparison follows rust-analyzer's
[features](https://rust-analyzer.github.io/book/features.html) and
[architecture](https://rust-analyzer.github.io/book/contributing/architecture.html).
Axiom has navigation, hover, completion, refactoring and formatting.
The rows above track the remaining analysis, responsiveness and completion
work; they do not claim full feature parity.

## Platforms and release

| Item | State |
|---|---|
| CI green on linux-aarch64 and darwin-aarch64 | Done |
| Reproducible toolchain records for every supported target | In progress; CI and release archives save source, seed, compiler and native-tool digests, exact versions, and SDK or package identities. Release records check the source build stamp; both native CI legs remain to validate |
| The compiler hosts itself on Windows, and crypto runs there | In progress |
| Windows clock conversions check overflow, finite sleeps retain their duration, and large stack frames link with page probing | Done; `tests/platform/windows-time.py` and `scripts/check-recover.sh` |
| Windows path roots, closed-poller checks and exclusive listener addresses | Done; `tests/stdlib/980-path-roots.ax`, `tests/stdlib/981-poller-closed.ax` and `tests/stdlib/843-net-stream.ax` |
| Every standard-library case runs on Windows; arbitrary captured-closure `Task` calls and the POSIX cases in `tests/stdlib/windows-skip.txt` remain unsupported | In progress |
| Explicit encoded executable workers preserve process isolation, bounded messages, deadlines and cancellation | Native Windows x64 and ARM64 validated by `tests/platform/worker-pool.py` |
| Guarded usable-byte stack budgets for Windows executable workers | Not yet; `NativeStack` is explicit and `StackBytes` is refused before launch |
| Parent allocator bookkeeping stays flat across repeated executable-worker calls | Not yet; repeated calls can retain bookkeeping despite retired native resources |
| Windows command pools launch native processes at a bounded width, preserve submit order and own their cleanup | Native Windows x64 and ARM64 validated by `tests/stdlib/987-command-pools.ax` |
| Windows pollers watch terminal input, pipes, Ctrl-C and Ctrl-Break without losing buffered bytes or retaining closed files | Native x64 and ARM64 control events and raw-mode restoration pass. Private input handles retire cancelled reads; host regressions pass, and native first-key and repeated-cancellation checks await CI |
| Windows seeds and an installer bootstrap the compiler locally | Native Windows x64 and ARM64 seed bootstraps reach the fixpoint; transactional preview installation validation is pending |
| The embedded checks run on a named board | Not started |
| Compatibility rules enforced at 1.0 (`COMPAT-6`) | Planned |

### Scale target support

A compiler's host is the platform that runs the compiler. Its output
target is the platform selected by `--target`; cross-compilation keeps
those choices separate. LLVM instruction selection is one part of a
port. Axiom also needs a matching ABI, linker, startup code, allocator,
trap and exception paths, atomics and a tested library subset.

The current target queries live in `core/codegen.ax`, linking in
`core/driver.ax`, and host selection in the `core/Host.*.ax` modules.
Platform library modules provide the kernel or host interfaces.
The [embedded guide](embedded-guide.md) describes the existing
`baremetal-aarch64` QEMU configuration and its hardware limits.

| Work | Acceptance |
|---|---|
| Replace repeated target conditionals with typed target descriptors and capabilities | One validated descriptor records word and pointer layout, ABI, object format, CPU features, atomics, allocation, threading and trap strategies; unsupported combinations are refused |
| Share backend, ABI and runtime implementations across targets | Small architecture, operating-system and board adapters supply the differences; a new port reuses the common checker and language syntax |
| Keep hosted and freestanding profiles explicit | Hosted services are available through platform modules; freestanding builds declare startup, memory, interrupts, device access and the permitted library subset |
| Keep optional runtime features out of unused programs | Measure stripped executable size and retained symbols for minimal, embedded and feature-enabled builds; profiles select capabilities without retaining unused services |
| Record each port's evidence and maintenance | Separate compile/link, emulator, hardware and maintained support states; record tool versions, CI coverage, known gaps and an owner before promotion |

Prioritise reusable runtime work, available emulators, accessible boards,
and maintainers who can reproduce failures. The next embedded set is
bounded; these are candidates, not accepted target names or support claims.

| Priority | Candidate | First evidence and limit |
|---|---|---|
| 1 | A named Cortex-A72 board for the existing AArch64 port | Select a board and owner, then validate its boot, memory map, UART, interrupts and fault paths on hardware; QEMU `virt` does not establish board support |
| 2 | A 64-bit RISC-V freestanding port, starting with QEMU `virt` | Prove compile/link, calling convention, startup, atomics and traps before emulator execution; hardware and a maintained CI configuration follow |
| 3 | A Cortex-M microcontroller profile | First resolve the compiler's current 64-bit word and metadata assumptions, small-memory allocation and interrupt ABI; select one board before implementing the port |

Each candidate advances through compile/link checks, emulator execution
where available, real hardware and maintained CI coverage. A port without
a runner stays labelled with the evidence it has. Promotion requires an
owner and a reproducible configuration; hardware evidence cannot be
inferred from another board or LLVM backend availability.

Full Windows support is a prospective v0.8.1 goal. Preview limitations
remain in the table above, including terminal input after mode
cancellation and guarded executable-worker stack budgets. Arbitrary
captured-closure tasks remain outside the encoded-worker design.
The v0.8.0 release labels Windows experimental and lists its working
functionality and known limits against the release's test evidence.
Windows completion is separate from the v0.8.0 gates: compiler-wide
type migration and an evidence-backed memory-model assessment.

The v0.8.0 foundations release includes completed work on nightly, with
proper typing and demonstrated memory soundness within the documented
safe-language contract. The full compiler type migration, Links, Options
and if-let chains belong to this scope. Experimental in-place vector
growth on uncapped, single-threaded POSIX heaps is already on nightly.
Database performance, executable footprint, feature parity and related
enhancements are v0.8.1 work. Compiler-wide migration completion and
demonstrated memory soundness are the final v0.8.0 release gates.

The maintainer cuts releases.
