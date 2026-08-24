# The Agent Harness

How an agent reads, checks and rewrites Axiom programs, and what the
compiler guarantees while it does.

This document is a **design**, not a record of shipped behaviour. Every
claim about what exists today carries the probe that established it;
every claim about what does not exist says so in those words. Where the
two are mixed the sentence says which half is which. That convention is
the whole value of the document: an agent-facing surface specified
against an imagined compiler is worse than none, because the failures it
produces are silent.

---

## 0. How to read this document

Sections 1 and 2 are measurement. Sections 3 onward are proposal.

A proposal that this repository already satisfies is marked **shipped**
and cites the gate that pins it. A proposal that needs a compiler change
is marked **owed** and names what blocks it. Nothing here is scheduled
by calendar week; the ordering in §5 is by what blocks what, which is
the only ordering this project has ever been able to hold to.

---

## 1. What is already there

Four agent-facing notations ship today and are gated:

| Notation | What it carries | Pinned by |
|---|---|---|
| **AXDL** | one line per diagnostic, with machine-applicable fixes as byte-range substitutions | `check-diagnostics.sh` |
| **AXSYM** | one line per symbol: kind, name, span, type, NID, and every accepted AXTAG | `check-tools-selfhost.sh` |
| **NID** | `FNV-1a-64(kind ++ bareName)`, stable across reordering and reformatting | `check-tools-selfhost.sh` |
| **AXTAG** | `;@axiom:<key>(<value>)` above a declaration, validated where the compiler knows the key | `check-diagnostics.sh` |

Three facts about them decide most of this design.

**AXTAG already carries the `agent:*` namespace.** A declaration tagged
`;@axiom:agent:allowed(net,fs)` compiles today, is recorded against that
declaration, and is re-emitted by `axiom symbols --diagnostic-format=ai`
as `#agent:allowed=net,fs`. The key namespace is open by decision -
`docs/reference.md` says so in those words - and `agent:readonly` is
already a fixture in `tests/diagnostics/346-axtag-key-typo.ax` asserting
it draws nothing. AXSYM re-emits the tags of *imported* modules too, so
one command yields a whole-program tag stream.

*Nothing has to be added to the compiler for an agent to write these
tags. What is missing is the checking.*

**AXDL already carries rewrites.** A machine-applicable fix travels with
its diagnostic as `?<loc>:"<msg>"~>"<replacement>"`, so a tool applies it
with a byte-range substitution and never parses English. This is the
existing rewrite channel, and it is narrower than `safeRewrite`: it is
compiler-authored, not agent-authored.

**One effect boundary already refuses to emit.** `(handle BODY (Pure) 0)`
over a body that performs `IO`, `Alloc` or `Mut` is `AX3011`, severity
error, exit 1, **no binary written**. It costs nothing at runtime: with
no declared custom effect in the list the handler expression is dead and
the form lowers to the body alone. This is the strongest primitive the
language has for the harness, and it is already shipped.

---

## 2. What the compiler does not do

Stated plainly, because the proposal assumed otherwise.

**Effects are not in types.** `TAG_T_ARR` carries a parameter and a
result and no effect row. `axiom symbols` renders an I/O-performing
function as a plain `(Int -> Int)` and puts the inferred set beside it as
`#effects=IO`. Effects are a side analysis keyed by function entry, not a
typing judgement, and nothing is checked at a call site. Any API whose
signatures carry effect constraints is proposing a new type system.

**No IR exists.** `self_host/codegen.ax` is an LLVM *text* emitter -
`(pub :: emitModule (-> Int String String))`, declarations in, assembly
text out. There is no intermediate representation, no block, no CFG.
`Agent.IR` as proposed has no referent in this compiler.

**The AST is untyped.** A node is a flat 11-word record - tag, a, b, c,
span, vis, ty, axtags, module, fieldNames, defscope - every word an `Int`,
read by offset. `parser.ax` makes 355 `memGetWord` calls and constructs
the record twice. Across 22 compiler modules there is exactly one real
ADT. So `(vecLen (parseModule toks))` type-checks, answers `OK`, and
segfaults: everything is `Int`, so the checker protects nothing.

**Every AXTAG claim is a warning.** A false `;@axiom:pure` on a body that
performs I/O is `AX3010`, exit 0, a 60 KB executable, and the I/O happens
at run time. `tests/diagnostics/severity.policy` is a hand-maintained
allowlist of the only five codes permitted to render as warnings, and all
five - `AX3010`, `AX3037`, `AX3038`, `AX3039`, `AX3040` - are in this
family. The non-blocking-ness is a decision with a gate behind it, not an
oversight.

**There is no strictness flag.** No `-Werror`, no `--deny`, no
`--agent-harness`; the driver's flag table is closed and an unknown flag
exits 2.

---

## 3. The corrected architecture

### 3.1 `Agent.AST` — a typed façade, and why it is now safe

**owed.** The compiler's AST cannot be handed out as it stands. The
harness owns a *façade*: nominal handle types over the flat node, with
accessors that are the only way to read a word.

```scheme fragment
(type NID  = Int)
(type Node = Int)

(pub struct Decl
  (nid  : NID)
  (node : Node)
  (name : String))

(pub :: astOfFile   (-> String Int))
(pub :: astDecls    (-> Int Int))
(pub :: declOfNid   (-> Int NID Int))
(pub :: nodeKind    (-> Node Int))
(pub :: nodeChildren(-> Node Int))
```

Note the shape: `(pub :: name Type)` and `(pub fn (name args) body)` are
two separate declarations. The proposal's `(pub fn f :: (-> A B))` is a
parse error, `AX2001`, at the `::`. There is also no `List`: `[T]` exists
in type position and is uninhabited - there is no list literal - so every
sequence is a `Vec` handle or a user-declared ADT.

**This façade was unsafe to write until 2026-08-23.** A `type` alias in a
struct field stayed nominal, so `(Decl 1 n s)` drew `AX3004` against its
own field; and behind that, the emitter's `fldClass` could not classify
the alias, forced the block to a leaf, and dropped the reference map the
`String` in the *next* field needed - 80 bytes an iteration, leaking the
field that was spelled correctly. Aliases now expand in struct fields and
in `data` constructor fields as they already did in signatures.
`tests/stdlib/374-arc-alias-field.ax` measures both spellings at 0.

Without that fix the façade above had two bad options: spell every handle
`Int` and lose the checker, or spell them with aliases and leak. Handle
types are the whole point of the façade, so the fix is a prerequisite
rather than an improvement.

**Hazard, unfixed: the type namespace is flat.** There is no
`Module::Type`, so two `Agent.*` modules that both export a `Node` merge
silently. The harness must give every exported type a name unique across
the whole namespace.

### 3.2 `Agent.Tags` — read and validate

**mostly shipped.** Reading is `axiom symbols --diagnostic-format=ai`
piped through a parser: the AXSYM line already carries the NID, the type,
the inferred `#effects=`, and every AXTAG including `agent:*`. A whole
program's tags come from one command because AXSYM re-emits imports.

**owed:** validation of the three new keys, and the schema. Adding a
checked key is an edit to the AXTAG value map and a new diagnostic in the
`AX30xx` band, with its long-form text in `self_host/explain.ax` before
it can ship - `check-tools-selfhost.sh` fails otherwise.

**Hazard:** `effect(...)` values are lowercase-only. `;@axiom:effect(IO)`
is silently reinterpreted as a *custom* effect named `IO` and reported
"missing IO" - a message textually identical to the built-in failure.
An agent-authored tag is the likeliest place for this, so `agent:*` value
parsing must be case-folded at the point of entry, not left to the same
trap.

### 3.3 `Agent.Safe` — built on `handle`, not on types

**The proposal's premise fails and its goal survives.** Effects cannot
appear in a signature, so `forbidEffects :: (-> NID (List Effect) Bool)`
has no type to be written in. But the enforcement it wants exists one
level down, in a form that already refuses to emit:

```scheme fragment
(handle BODY (Pure) 0)
```

`Agent.Safe` is therefore a *macro* surface over `handle`, not a function
surface over types. `(safeRegion BODY)` expands to the form above; the
compiler refuses the build if `BODY` reaches `IO`, `Alloc` or `Mut`, and
the emitted code is `BODY` with nothing added.

**owed, and load-bearing: `handle` launders effects.**
`(handle BODY (IO) 0)` *subtracts* `IO` from what the body contributes -
`docs/reference.md` describes the subtraction as the built-in case's
intended meaning. So a `;@axiom:pure` function whose body wraps its I/O
in that one form builds at exit 0, is reported `#pure` by `symbols`, and
writes to stdout at run time. Because an inner handle subtracts before an
outer one measures, this also defeats the `(Pure)` boundary above.

The measured shape is worse than "no diagnostic". The build is not
silent - it warns, on the **wrong function**:

```console
W AX3010 launder.ax:7:6-10 axtag-mismatch "AXTAG mismatch on `main`:
    `effect(io)` claim unsupported: missing IO"
Build successful: ld
```

`sneaky` laundered the effect, so its honest caller no longer *appears*
to perform I/O, and `main` is warned for truthfully declaring that it
does. The lying callee passes clean and reports `#pure`. An
`Agent.Policy` reading this build learns the opposite of the truth about
both functions, which is the precise reason this item is first in §5
rather than filed with the other effect holes.

So the single most important compiler change in this document is not a
build mode. It is: **a handler that discharges a built-in effect without
handling it must not be silently accepted inside a region a policy is
reading.** Until that is closed, every `#pure` and every `#effects=` an
`Agent.Policy` consumes is advisory.

Two further holes bound what `Agent.Safe` can promise, both measured:

- A function value that goes through memory — a struct field or a
  `let`-bound local — escapes both the `;@axiom:pure` claim and the
  `(Pure)` boundary. `AX3037`/`AX3038` now report it, as warnings.
- An effect operation reached with no handler anywhere compiles clean and
  the process aborts at run time with status 71 and no message. There is
  no whole-program discharge check.

### 3.4 `Agent.Policy` — a gate, not a build mode

**This is the largest structural correction.** The proposal makes policy
a compiler mode. The only boundary policy that works in this repository
today is a *shell gate*: `check-ffi.sh` compares a binary's `nm` symbols
against a per-crate `axiom-allow.txt`, and carries a negative probe
proving the allowlist can go red.

`Agent.Policy` should be built the same way — a gate over the AXSYM
stream, comparing each declaration's `#effects=` and `agent:*` tags
against a checked-in allowlist — for three reasons, each measured:

1. Determinism is **already unconditional**. `check-reproducible.sh`
   asserts byte-identical output for every compile, because the bootstrap
   compares stage N against stage N+1 and that is meaningless if one
   stage can differ from itself. Making deterministic IR a property of a
   *mode* would imply ordinary builds may be nondeterministic, which this
   project has already refused.
2. The strictness the mode would turn on is per-diagnostic severity, and
   `tests/diagnostics/severity.policy` is already the artifact that
   governs it, in both directions.
3. A mode flag is a new axis on every gate. An allowlist is a file.

**owed:** the gate, the allowlist format, and its negative probe.

**Hazard:** AXSYM lines embed absolute paths, unlike `emit-llvm` output,
which is path-free. A policy artifact built from AXSYM is not portable
between checkouts until that is normalised.

### 3.5 `Agent.IR` — refused

There is no IR. What the proposal wants from it — a deterministic
artifact an analysis can be run against and compared across runs — is
already served by two things that exist:

- `emit-llvm` output, which is byte-deterministic for a fixed input,
  ordered by *source* position, free of paths, filenames and timestamps,
  and identical at every `--opt` level;
- the AXSYM stream, which is the structural view.

Specifying a third would mean building an IR in order to snapshot it.

**Caveat, measured:** emitted IR is not a function of (source, target)
alone. Module resolution searches the input file's own directory ahead of
`$AXIOM_STDLIB`, so a stray file beside the input changes the output. A
reproducible harness must pin its module path.

### 3.6 `Agent.Macro` — deferred, with the reason

**Deferred, not refused.** Expansion is deterministic per input and a
macro cannot perform effects at expansion time: a template calling
`readFile` emits the *call*, and the file's contents appear nowhere in
the output. That is the sandbox the proposal wanted, and it holds.

Three measured defects block a *safe* expansion API, and none is small:

1. **Reverse hygiene has a live hole.** A template's free identifier
   naming a trait method is captured by an entry-file declaration. The
   stdlib's own `format` macro is subject to it, and
   `tests/selfhost/383-format-capture.ax` pins the broken behaviour.
2. **Declaration-level generated names are unhygienic**, colliding with
   hand-written ones as `AX3006` at a positionless span.
3. **A declaration-macro fan-out is unbounded.** The two output budgets
   are incremented only inside expression expansion; the declaration
   phase never touches them, so a doubling template is killed at
   multi-gigabyte RSS with no diagnostic and no output. For a harness
   compiling model-generated code this is the sharpest edge in the
   language: `axiom check` has no memory bound and no lever to give it
   one.

There is, however, a **closed compile-time reflection vocabulary** that
already exists — the `syntax/*` forms — letting a program interrogate the
declaration list at expansion time, with anything outside the vocabulary
refused as `AX3028`. That is a better foundation than a new API, and
§5 orders it accordingly.

---

## 4. Reaching the compiler at all

The proposal assumes an agent program can obtain an AST. It can, today,
and the route needs to be named because it is currently an accident.

**What works.** A program that does `(import parser)` with
`AXIOM_PATH=<repo>/self_host` lexes, calls `parseModule`, and walks real
declarations. Driving lexer + parser + codegen reproduces the compiler's
own LLVM IR byte for byte.

**Why it is an accident.** Import resolution searches five slots, and
`self_host/` is reachable only through a CWD-relative literal that
`self_host/codegen.ax` documents as deliberate legacy — *"They are
history, not the rule"* — kept so gate harnesses can bisect. Setting
`AXIOM_PATH` is the only supported route.

**Why it does not scale.** `import` is whole-program **source splicing**,
not linking. Hello-world emits 10 LLVM defines; a parser client emits
590; a full pipeline client emits 1,939 and a ~970 KB binary — about 56×.
Every harness recompiles the compiler into itself.

**The route the ABI should take instead.** `--emit-staticlib` already
produces a linkable archive exposing compiler internals as C symbols —
449 exported text symbols, including `parser$parseModule`. And the
detail that makes a *curated* ABI possible: **the entry file's own `pub`
functions become unmangled C symbols**. So the harness ABI is the
exported surface of one Axiom file, not a freeze of the compiler's 2,135
`pub` functions — of which only 2 in the whole of `self_host/` are
private, so there is no encapsulation boundary to inherit.

Selective import — `(import parser (TAG_D_FN nodeVis))` — is the
in-language access-control lever, and works today.

---

## 5. Ordering, by what blocks what

1. ~~**Close the `handle` laundering hole.**~~ **Done, 2026-08-23.**
   Everything `Agent.Safe` and `Agent.Policy` claim was advisory until
   this landed, which is why it went first and alone
   (`tests/diagnostics/348-handle-discharge.ax`).
2. **`Agent.AST` façade** — still owed. **`Agent.Tags` reader — done**,
   `stdlib/Agent/Tags.ax`, over the AXSYM stream rather than the
   compiler's internals (§4 gives the size argument).
3. ~~**`Agent.Policy` gate + allowlist + negative probe.**~~ **Done**,
   `scripts/check-agent-policy.sh` against
   `tests/agent/stdlib-effects.allow`. It found two standard-library
   functions performing I/O without claiming it on its first run.
4. **Promote the `agent:*` checks.** New diagnostics in the `AX30xx`
   band, `explain` entries, and a `severity.policy` decision made
   deliberately rather than inherited. Read §6's `AX3010` entry before
   starting: the neighbouring promotion turned out to be wrong twice
   over, and for reasons that apply here too.
5. ~~**Bound declaration-macro expansion.**~~ **Done** — the size axis
   phase D never had (`tests/diagnostics/401-decl-macro-size-limit.ax`).
   It was the prerequisite for any harness that compiles code it did not
   write.
6. **`Agent.Macro`**, over `syntax/*`, after 5 — now unblocked, and
   still gated on the three hygiene defects §3.6 lists.

`Agent.IR` does not appear. Neither does `--agent-harness`.

What is left is (2)'s façade, (4), and (6). The effect rows those rest
on are honest now in a way they were not when this was written: the
laundering is closed, and `Alloc` names the primitive that allocates
rather than a keyword that does not (`docs/memory-model.md` MM-EXEC-9a,
whose table lost that row on 2026-08-23).

---

## 6. What is refused, and why

- **Promoting `AX3010` to an error.** The obvious next step after making
  the effect rows honest is to make a contradicted claim refuse the
  build, and it is wrong twice over — measured both times.

  The code carries two shapes. "`effect(io)` claim unsupported: missing
  IO" is the one that looks undecidable and is not: it already consults
  `effPartial` and suppresses itself whenever the walk hit a lower bound
  or the function has effect-transparent parameters. The one that looks
  decidable is not: "`pure` claim contradicted: body performs IO" fires
  on a function that merely NAMES an effectful function without calling
  it — `(fn (handoff k) shout)` is reported as performing IO and carries
  `#effects=IO`. Promoting that shape refuses correct programs.

  And the cost lands in exactly the wrong place. `symbols` folds every
  failure into exit 1 and prints no table, so making the claim an error
  deletes the AXSYM surface for the files that carry a wrong tag — eight
  files in this repository's own corpus, one of them 196 symbol lines —
  which is the moment an agent most needs to read what the body actually
  does. `check-tools-selfhost.sh` cannot see it, because its cross-check
  is the equivalence "symbols exits 0 iff check exits 0" and the change
  moves both sides at once.

  So the severity stays, and the gate does the refusing:
  `check-agent-policy.sh` is where a violated policy stops a build,
  which is §3.4's argument arriving a second time.

- **`--agent-harness` as a build mode.** Determinism is already
  unconditional; strictness already has an artifact; a mode is a new axis
  on every gate. §3.4.
- **`Agent.IR`.** No IR exists to snapshot. §3.5.
- **Runtime telemetry.** `check-freestanding.sh` asserts at two levels
  that generated code contains no libc call and the linked executable
  imports no libc symbol. Telemetry out of emitted code fails that gate
  and the FFI allowlist. The harness may measure at *build* time, in a
  gate, where the rest of this project's measurement already lives.
- **Effect rows in signatures.** A new type system, not a harness.
- **Adoption and satisfaction targets.** This repository is one author
  and four weeks old; a metric no one can compute should not gate a
  design.

---

## 7. Gates this design owes

Following the convention that a claim without a gate is a comment:

| Claim | Gate |
|---|---|
| a laundered effect cannot pass a policy region | new negative probe beside `tests/diagnostics/severity.policy` |
| the AST façade hands out no unmapped block | extend `tests/stdlib/374-arc-alias-field.ax`'s shape to every façade record |
| `agent:*` tags survive `fmt`, AXSYM and import | fixture in `tests/tools/`, since `fmt --check` already refuses a non-canonical payload |
| the policy allowlist can go red | negative probe, on `check-ffi.sh`'s model |
| declaration-macro expansion is bounded | fixture that today is SIGKILLed |
