# Safety contracts and trusted boundaries

Use this inventory when reviewing an Axiom interface that turns words
into typed values, stores references or reclaims memory. It connects
the [assurance contract](assurance.md#the-safety-contract) to source
and existing evidence. The [memory model](memory-model.md) owns the
rules and their status markers.

For example, `vecGet` checks an index before reading a slot. Its
internal cast also trusts that the slot holds the vector's declared
element type. A range check establishes the first fact; the library's
construction and mutation rules must establish the second.

An untagged caller may call a trusted function. `effect(unsafe)` marks
the declaration that performs the raw operation; its `Unsafe` does not
propagate to callers. Safe source therefore still depends on the
trusted code it reaches. The compiler checks the declaration of that
boundary, without proving the body's preconditions or implementation.

## Keep the guarantees separate

| Property | What your program needs | What the current contract leaves open |
|---|---|---|
| Memory safety | Reads, writes and releases use live storage, valid layouts and permitted access | A trusted function can misuse a word, foreign code can corrupt memory, and explicit reference erasure can lose lifetime evidence |
| Resource cleanup | Each owned external resource runs its cleanup once when its final share is released | Cycles and untracked words may delay cleanup; reset sweeps registered owners, while process exit and unrecovered traps skip callbacks |
| Leak freedom | Every unreachable allocation is eventually reclaimed | ARC, automatic reference counting, does not collect cycles; some ownership shapes retain storage conservatively |
| Bounded execution | A stated bound covers steps, stack, memory or elapsed time | A memory-safe loop can run forever; a task deadline or allocation budget does not establish whole-program worst-case execution time |

A leaked allocation can remain memory-safe. Reclaiming storage can
still miss an external destructor. Releasing all owners says nothing
about how long a loop runs. Each property needs its own evidence.

## Invariants to review

### Type validity

A value's type must describe its representation wherever it is
constructed, passed, stored, returned or read. Axiom's machine words
are not self-describing. A word with a valid address can still have
the wrong layout, element type or ownership map.

[`tyCompat` in typecheck.ax](../core/typecheck.ax) compares types
at uses and results. `checkStructConAt` and `checkStructFieldsInst`
check construction against field types. `checkCastForm` records the
source and target types of explicit conversions. These checks remain
enabled inside an `effect(unsafe)` body.

Returning a struct where a signature declares `Int` is refused as
`AX3004`. An ordinary typed return is accepted. A trusted cast can
still assert a false layout; the assertion is a review obligation.

Tested by `tests/diagnostics/1240-record-through-int.ax` and
`tests/diagnostics/1395-unsafe-checks-retained.ax`.

Not yet: the checks are not a type-soundness proof, and the compiler
handoff does not carry a typed semantic IR ([roadmap](roadmap.md)).

### Reference validity

A reference needs live storage, a representation matching its type
and a lifetime covering every use. Raw accesses also need sufficient
extent, alignment and initialisation. A bounds check cannot recover
those facts from an arbitrary address.

`checkCastForm` and the unsafe-operation checks require a declaration
for a forging cast (`MM-EXEC-9d`). Module resolution keeps
`Internal.Raw` and `Internal.RawVec` inside the selected standard
library (`MM-EXEC-9g`). These restrictions reduce the public surface;
they do not validate the contents of a raw block.

[`vecGet` and `vecSet`](../stdlib/Vec.ax),
[`strByte` and `strSlice`](../stdlib/Str.ax), and
[`fileRead`](../stdlib/IO.ax) check their typed ranges before access.
`fileRead` takes a sealed `ReadBuffer`, so it cannot write through a
literal or an aliased string view (`MM-EXEC-9f`).

An untagged `(as 7 String)` is refused. An out-of-range vector access
traps with status 77. A valid vector index still relies on the library
having stored the declared element type.

Tested by `tests/diagnostics/1040-forging-cast.ax` and
`tests/stdlib/610-typed-io-bounds.ax`.

Internal access is refused by `tests/diagnostics/1470-internal-import.ax`
and `tests/diagnostics/1471-internal-name.ax`.

Not yet: public raw-address interfaces remain, and explicit
reference-to-word casts can erase lifetime evidence
([roadmap](roadmap.md#memory-and-resource-safety)).

### Ownership

Every counted owner must hold a share for every live reference it
keeps. Replacement must retain the incoming share before releasing
the outgoing one. Moving a share must remove it from its old place.
The runtime's map must name managed references, with zero in unused
mapped slots.

[`valueOwnedRef`, `emitRetainOf` and `emitReleaseOf` in codegen.ax](../core/codegen.ax)
select ownership traffic. The emitted allocator and release walk
interpret the maps described by `MM-LIFE-2d`. A map is an instruction
to the release walk, not a runtime proof of a slot's type.

`vecSet` retains before replacement. `vecPop` clears the vacated slot
and declares `result(owned)`, transferring its share to the caller
(`MM-LIFE-2n`). Raw map changes in
[`Internal.Raw`](../stdlib/Internal/Raw.ax) require the caller to
account for each share before removing its mark.

If a popped slot kept its old word, destroying the vector could
release the caller's live result. If a map marked an integer as a
reference, the release walk could follow an invalid address. Neither
case is made safe by declaring `effect(unsafe)`.

Tested by `tests/stdlib/846-vec-pop-release.ax` and
`tests/stdlib/778-vec-lent-argument.ax`.

Leak freedom is unproved. `MM-LIFE-3` permits cycles, and the memory
model's lifetime rules describe conservative retention. A `mut` local
keeps its value when a read may survive replacement, or when its type
is a type variable. `MM-VAL-24` still permits explicit erasure to
`Int`. A leaked resource owner may also delay its destructor
indefinitely.

### Regions

A region reset invalidates the storage it reclaims, regardless of
reference counts. Every use that depends on that storage must finish
before reset. Retaining a nested field does not promote it into a
longer-lived extent.

The existing contract is
[checked lexical regions](memory-model.md#36-checked-lexical-regions):
`MM-RGN-1` restricts region results, `MM-RGN-3` states the escape rule
within the tracked-origin domain, and `MM-RGN-6` describes how reset
and counting compose. These are limited analysis guarantees; raw
addresses and foreign memory remain caller obligations.

The established scalar-result example is `tests/stdlib/168-region.ax`.
Its acceptance does not establish every escape case. A reset does
not trace the reclaimed graph and run every destructor. It does
sweep registered resource owners under `MM-EXEC-20`, while their
storage remains live; raw foreign handles need separate cleanup.

Process exit and unrecovered traps skip cleanup callbacks
(`MM-EXEC-17`, `MM-EXEC-20`). The operating system reclaiming a
descriptor does not establish that application cleanup ran.

Checked regions track a reference's origin and refuse an escape
(`AX3059`, `AX3060`). Not yet: promoting an owned reference out of a
region, and typed sibling task regions, under `MM-RGN-7`
([roadmap](roadmap.md)).

### Sharing

A worker must not release or mutate a heap graph its parent still
uses. Ordinary captured references and mutable containers cannot be
treated as scalar words. Shared runtime objects need their own
ownership and synchronisation rules.

[`checkSpawnCaptures` in typecheck.ax](../core/typecheck.ax)
conservatively refuses counted captures and opaque thunk shapes with
`AX3064`. `MM-PAR-6b` permits an explicit immutable borrow while the
parent keeps the graph live and counts remain frozen.
[`Chan`](../stdlib/Chan.ax), [`Mutex`](../stdlib/Sync.ax) and
[`CancelToken`](../stdlib/Task.ax) use sealed shared owners under
`MM-PAR-16`.

Capturing a mutable vector in a concurrent binding is refused.
Accepted shared owners do not establish arbitrary shared-heap safety.
A raw address carried as an `Int`, or a `Foreign` value, still needs
an external lifetime and synchronisation argument.

`MM-EXEC-20` also records a cleanup limit: an owner in a lent graph
stays frozen when a trap leaves the `parallel` form, so its cleanup
does not run.

Tested by `tests/diagnostics/656-parallel-container-capture.ax` and
`tests/stdlib/803-shared-owner.ax`.

Not yet: general shared mutable heap graphs and typed task-value
transfer are incomplete ([roadmap](roadmap.md#concurrency-and-bounded-execution)).

## Trusted boundary inventory

Review these classes for the configuration and dependencies your
program actually uses. Changing a platform, standard library directory
or linked archive changes the code you trust.

| Boundary | Source and enforcement | Obligation beyond the type checker |
|---|---|---|
| Compiler semantic decisions | [typecheck.ax](../core/typecheck.ax); the [checked handoff](../core/checked.ax) seals final-check admission | Accepted types and effect facts must agree with emitted layouts and calls. Declaration membership and order are checked; nested AST payloads remain mutable |
| Compiler raw storage | [raw.ax](../core/raw.ax) and the compiler's unsafe bodies | Word offsets, typed views, maps and explicit ownership must agree with their writers. The compiler's own raw layer is part of its trusted implementation |
| Library raw storage | [Internal.Raw](../stdlib/Internal/Raw.ax), [Internal.RawVec](../stdlib/Internal/RawVec.ax); `AX5002` limits import and name access | Addresses must be live and aligned; reads must be initialised; copies must obey overlap rules; typed views and maps must match stored values |
| Typed library wrappers | [Vec.ax](../stdlib/Vec.ax), [Str.ax](../stdlib/Str.ax), [IO.ax](../stdlib/IO.ax) and other trusted wrappers | Range arithmetic must avoid overflow, references must stay live, and construction, mutation and release must preserve layout and shares |
| Emitted runtime | [codegen.ax](../core/codegen.ax), including `emitArenaHelpers` | Allocation, reuse, reference maps, overflow checks, traps and cleanup must preserve the memory model on the selected target |
| Public address-taking calls | [Sys.ax](../stdlib/Sys.ax): `sysRandomBytes`, `sysUnmapShared`, `sysWaitWord` | An `Int` must identify the required live extent with the right access and synchronisation. These interfaces do not prove that precondition |
| Foreign ownership helpers | [Ffi.ax](../pkg/axiom-oxide/axiom/Ffi.ax): `ffiHandleNew`, `ffiCellWord`, `ffiCellFree` | Destructors must match their pointers; cells must have the declared extent and remain live until foreign access ends; freeing must spend exactly the owned share |
| External implementations | [Ffi.ax](../pkg/axiom-oxide/axiom/Ffi.ax), [Sys/Platform.windows.ax](../stdlib/Sys/Platform.windows.ax), and linked archives | Symbol grounding and ABI checks cannot prove pointer validity, foreign destruction, aliasing or synchronisation. Review the external implementation and its ABI |
| Explicit user trust | A program's own `effect(unsafe)`, `extern` and `asm` declarations | Keep the same storage, layout, ownership and access obligations as the library; type, effect and restriction checks still apply |

The trusted set includes wrappers around unsafe operations, even when
a wrapper performs no primitive itself. `symbols` marks trusted
declarations `#unsafe=trusted`.
[`tests/agent/stdlib-effects.allow`](../tests/agent/stdlib-effects.allow)
records standard-library effect declarations. It is not a proof of
their bodies or an inventory of linked foreign machine code.

Contracts can express some preconditions and trap with status 80 when
they fail. A numeric range predicate cannot establish that an address
is mapped, live, correctly typed or exclusively writable.

Tested by `tests/stdlib/707-library-pre.ax` and
`tests/diagnostics/1041-trusted-call.ax`.

## Counterexamples to broader claims

| Broader claim | Existing counterexample or limit | What you may conclude |
|---|---|---|
| Every untagged call is memory-safe for every well-typed argument | `tests/diagnostics/1081-sys-buffer-calls.ax` accepts address-taking wrappers, including a `restrict(no-unsafe)` caller | The raw-address preconditions still need review; the fixture does not run invalid addresses |
| An effect restriction accounts for every cleanup effect | `tests/stdlib/712-drop-effects-at-creation.ax` accepts replacement that closes a file inside `no-io` | Drop effects are attributed at creation; an effect row does not establish absence of cleanup IO |
| Every reclaimed allocation has run its destructor | `MM-RGN-6` does not promise a destructor for every reclaimed object; `MM-EXEC-20` sweeps registered owners | Reclamation and external-resource cleanup require separate arguments |
| Every unreachable graph is reclaimed | `MM-LIFE-3` permits cycles | ARC provides no general leak-freedom guarantee |
| Every fault becomes a named trap | `MM-EXEC-9d` admits trusted raw-address calls | Named traps cover their checked conditions; trusted corruption and hardware faults remain outside that guarantee |
| A deadline proves bounded execution | [restricted-profile.md](restricted-profile.md) and `MM-PAR-17` state specific resource and task limits | State the covered entry, target and budget; whole-program timing remains unproved |

The linked fixtures establish particular behaviours, on the
configurations that run them. Their existence, a passing run or green
CI does not establish a soundness theorem, complete boundary coverage
or cross-platform equivalence. The
[assurance evidence](assurance.md#guarantees-and-evidence) states the
configuration limits; the [roadmap](roadmap.md) owns remaining work.
