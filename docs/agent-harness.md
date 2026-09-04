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
text out. `emitExpr` is `(-> Int Int Int)` and an expression's *value*
is a **String** in `CG` field 2; block state is `curBlock`, one String,
and `terminated`, one bit. There is no intermediate representation, no
block, no CFG. `Agent.IR` as proposed has no referent in this compiler.

The honest sharpening, since it decided what shipped instead: the
**AST is the IR**, annotated in place. The typechecker fills each node's
`ty` word, `resolveDecls` stamps its `module`, and `expandProgram` ->
`lowerImpls` -> `lowerConds` rewrite it in sequence. What was missing
was never a representation. It was that nothing *published* one - see
§3.5, where the graph the effect fixpoint already walks is now printed
rather than dropped.

**The AST is untyped.** A node is a flat 11-word record - tag, a, b, c,
span, vis, ty, axtags, module, fieldNames, defscope - every word an `Int`,
read by offset. `parser.ax` makes 355 `memGetWord` calls and constructs
the record twice. Across 22 compiler modules there is exactly one real
ADT. So `(vecLen (parseModule toks))` type-checks, answers `OK`, and
segfaults: everything is `Int`, so the checker protects nothing.

**A refuted AXTAG claim is an error.** A false `;@axiom:pure` on a body
that performs I/O *was* `AX3010`, exit 0, a 60 KB executable, and the
I/O happening at run time. Since 2026-08-25 it is an **error** and there
is no executable.

`tests/diagnostics/severity.policy` is a hand-maintained allowlist of
the codes permitted to render as warnings: `AX3037`, `AX3038`,
`AX3039`, `AX3048`, `AX3051` and `AX3053`.

`AX3037`, `AX3038`, `AX3039` and `AX3051` are the AXTAG family's
UNANSWERABLE half, and that split is the whole rule for them - a claim
the walk checked and refuted refuses the build; a claim it was not in a
position to check informs and does not. `AX3051` joined on 2026-08-29
with the `restrict(...)` tag: the answerable half of that claim is
`AX3049`, an error from its first day.

`AX3048` is on the list for a different reason, and it is the first
member that is not a statement about what the compiler could not
determine. A reference to a name marked `;@axiom:deprecated` is
perfectly determinate: the name exists, it type-checks, and it works.
It warns because the release that ANNOUNCES a removal is the one
release in which the callers must still build, and promoting it would
make deprecation and removal the same event - the distinction the
notice exists to draw. See `docs/compatibility.md` COMPAT-7.

`AX3053` is on it for a third reason, and it is the only member whose
warrant is a MEASUREMENT rather than an argument. An operation the
program reaches with no handler is perfectly determinate at run time -
the process exits 71 - and the check that names it reads `main`'s
finished effect row. What is not determinate is which side the
approximation falls on, and it falls on both: a lambda's operations
count where the lambda is WRITTEN, so a worker bound before the
`handle` that covers its call is reported although it runs (exit 20);
and the `let` of a `handle` form is an opaque local, so a closure built
inside a handle and called after it pops is not reported although it
traps (exit 71). An error would refuse the first and accept the second
- §6's objection to a check that refuses correct programs, arriving on
both sides of one rule at once. `;@axiom:unhandled(trap)` on an
`effect` declaration is the claim that the trap is the design, and
`stdlib/Test.ax` carries it because `axiom test`'s generated `main`
would otherwise be reported on every suite.

`AX3040` left the list the same day, when the compiler learned to tell a
function that never returns from one that fabricates a value; `AX3010`
left it once the shapes the walk could not check were routed to
`AX3037`, which is what removed the last thing excusing it. This
paragraph went on naming `AX3040` as a member for a day after it stopped
being one - which is why the list is compared against the file by
`scripts/check-doc-drift.sh` rather than restated here from memory. That
comparison is also what caught this paragraph.

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

**Hazard, narrowed 2026-08-24: the type namespace is flat but no longer
silent.** There is still no `Module::Type` — a qualified spelling does
not parse in type position — but two `Agent.*` modules that both export
a `Node` no longer merge. Each module's own code reaches its own
declaration, and a reference from anywhere that owns neither is
`AX3044` naming both modules (`scripts/check-type-namespace.sh`). What
is left of the hazard is that there is no way to *write* the
disambiguation at the reference: the escapes are an import name list
that leaves one of them behind, or a unique name. So the harness rule
stands — give every exported type a name unique across the whole
namespace — but breaking it is now a diagnostic rather than a wrong
answer at exit 0.

### 3.2 `Agent.Tags` — read and validate

**mostly shipped.** Reading is `axiom symbols --diagnostic-format=ai`
piped through a parser: the AXSYM line already carries the NID, the type,
the inferred `#effects=`, and every AXTAG including `agent:*`. A whole
program's tags come from one command because AXSYM re-emits imports.

**owed:** validation of the three new keys, and the schema. Adding a
checked key is an edit to the AXTAG value map and a new diagnostic in the
`AX30xx` band, with its long-form text in `self_host/explain.ax` before
it can ship - `check-tools-selfhost.sh` fails otherwise.

**Not a hazard, and this paragraph used to say it was.** It read:
"`effect(...)` values are lowercase-only. `;@axiom:effect(IO)` is
silently reinterpreted as a *custom* effect named `IO` and reported
'missing IO'." Measured 2026-08-30 — `;@axiom:effect(IO)` above a body
that prints checks **OK**, and `symbols` gives it `#effect=IO
#effects=IO`. Custom tag values match declarations **case-insensitively**
(`docs/reference.md`, Effects), so the value folds to the built-in and
there is no trap to case-fold around. The corrected fact is worth
keeping in its place: a tag's value is compared without regard to case,
which is why `effect(io)` and `effect(IO)` are one claim.

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

**CLOSED 2026-08-23 - and this section had it as the document's number
one.** `handle` was described here as *laundering* effects:
`(handle BODY (IO) 0)` subtracting `IO` from what the body contributes,
so a `;@axiom:pure` function wrapping its I/O in that one form built at
exit 0, reported `#pure` to `symbols`, and wrote to stdout at run time -
and an inner handle subtracting before an outer one measured defeated
the `(Pure)` boundary above.

`6dcc784` split the two questions one predicate had been answering.
`handle` NAMES a set and DISCHARGES a smaller one: for a built-in the
effect still reaches the caller, because `handleIsDynamic` installs
evidence only for a *declared* effect and the form otherwise lowers to
its body. Re-measured against the compiler in this tree, both shapes
this section built are refused:

```console
$ axiom check --input launder.ax        # the laundering `pure` claim
E AX3010 launder.ax:6:6-12 axtag-mismatch "AXTAG mismatch on `sneaky`:
    `pure` claim contradicted: body performs IO"
compilation failed due to 1 previous error          # exit 1

$ axiom check --input pureb.ax          # an inner handle under (Pure)
E AX3011 pureb.ax:5:31-38 effect-mismatch "effect mismatch: unhandled
    effect `IO`"
compilation failed due to 1 previous error          # exit 1
```

The inversion is complete. It is the **lying callee** that is refused
now, and its honest caller draws nothing at all - where this section's
own example had the diagnostic landing on `main`, for truthfully
declaring the I/O its callee had laundered away.

So the change this section called "the single most important compiler
change in this document" is made, and an `Agent.Policy` reading a build
that SUCCEEDED is reading a `#pure` the compiler stood behind. What is
still advisory is the smaller and differently-shaped set below.

One further hole bounds what `Agent.Safe` can promise, and the second
one this section carried is closed:

- A function value that goes through memory — a struct field or a
  `let`-bound local — escapes both the `;@axiom:pure` claim and the
  `(Pure)` boundary. `AX3037`/`AX3038` now report it, as warnings.
- **CLOSED 2026-08-30.** "An effect operation reached with no handler
  anywhere compiles clean and the process aborts at run time with status
  71 … there is no whole-program discharge check, so this remains a
  runtime failure." There is one now: `AX3053` reads `main`'s finished
  effect row, and a `handle` is the only construct that discharges a
  custom effect, so an effect still in that row is one nothing handled.
  It is a **warning**, not an error, and the reason is measured rather
  than cautious — on the two closure shapes the evidence is one-sided in
  both directions at once, so an error would refuse a program that runs
  (a lambda performing the operation, bound before the `handle` that
  covers its call: exit 20) and accept one that traps (a closure built
  inside the `handle` and called after it pops: exit 71). That is this
  document's own §6 objection landing on both sides of one rule.
  `tests/diagnostics/severity.policy` carries the measurement;
  `;@axiom:unhandled(trap)` on an `effect` declaration is how a program
  says the trap is the design, and `stdlib/Test.ax` uses it so that
  `axiom test`'s generated `main` stays silent
  (`scripts/check-test-runner.sh` deletes the tag from a shadow copy and
  requires the warning, so the claim is answered rather than assumed).

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

### 3.5 `Agent.IR` — still refused; the graph it was reaching for shipped

**The proposal stays refused, and the refusal was re-derived rather than
inherited.** `self_host/codegen.ax` is a one-pass syntax-directed text
emitter. `emitExpr` is `(-> Int Int Int)` — node and context in, the
same context out — and an expression's *value* is a **string** in `CG`
field 2, an LLVM register name like `"%.t7"`, with a float bit beside it
in field 14. Block structure is two scalars: `curBlock`, one String,
written in exactly one place and read in five, all five filling a phi
predecessor; and `terminated`, one bit. In 14,406 lines the file defines
four structs and one constructor, and that constructor holds AST
pointers. There is no instruction, no block, no CFG and no def-use edge
as data anywhere in it.

So there is nothing to snapshot, and building something to snapshot
means re-architecting the emitter — on which the ARC evidence ordering,
the TCO rewrite and the arena discipline all currently ride *in emission
order*. That is not a harness feature.

**But the refusal used to end one sentence too early.** It said AXSYM is
"the structural view" and left it there, and that is not true: AXSYM
stops at the **declaration boundary**. Measured on a 13-line,
three-function program — AXSYM gives three lines carrying kind, name,
span, type, NID and effects, and *nothing whatever about a body*;
`emit-llvm` gives 5,514 lines and 303 defines with **zero** debug
locations, so it is faithful and unmappable at once. Between them there
was nothing. An agent could not ask what `main` calls.

**What was missing was never an IR. It was the graph** — and the
compiler had already computed it. `inferEffects` (`typecheck.ax`) is a
monotone fixpoint over the call graph: it walks every body, resolves
every reference site to a `FnEnt`, folds that entry's effect row into
the caller's, and then dropped the edge it had just resolved. That is
how `#effects=IO` reaches `main` through `greet` from `writeStr` — and
why the row could not say so.

**shipped.** `tcNoteCall` records the edge the walk already resolved,
on a `calls` word beside `effects` on the same `FnEnt`; `symbols
--calls` prints it as `#calls=`:

```console
F twice p.ax:3:5-10 "(Int -> Int)" @852e07f… #calls=*
F greet p.ax:6:5-10 "(String -> Int)" @194c3b2… #effects=IO #calls=IO$writeStr,Str$strEq
F main  p.ax:12:5-9 "Int" @6159d36… #effects=IO #calls=greet
```

Four properties, each gated by `scripts/check-agent-calls.sh`:

- **containment** — no callee's effect escapes its caller's row, so
  `#calls=` and `#effects=` are two views of one walk (595 stdlib rows,
  0 violations);
- **totality** — every *inferred* effect row carries an edge accounting
  for it. The only exemption is `stdlib/Ffi.ax`, whose rows are
  **constructed** by `tcAddExtern` rather than walked;
- **grounding** — every one of the 90 IO-performing library rows reaches
  a `__syscallN` or an `extern` transitively. A syscall is recorded as
  an edge for exactly this reason: it short-circuits above `findFnEnt`,
  so without it the bottom of every IO chain was an effect from nowhere;
- **silence** — without `--calls` the stream is byte-identical to
  before. `tests/tools/symbols-zoo.golden` pins 147 rows, and a key on
  every row would put an edge list in the diff of every future stdlib
  edit. `--builtins` is the precedent: content selection on `symbols`,
  not a build mode. `tests/tools/symbols-zoo-calls.golden` pins the
  edges themselves, and the two goldens are cross-checked by stripping
  the key from one and comparing bytes with the other.

**It runs with `--builtins`, and that is not tidiness.** An operator is
a `FnEnt` in this language, so `+` and `==` are real edges; and
`__alloc` is a builtin *and* is what puts `Alloc` in the row beside it,
so a graph that dropped builtins could not explain its own effect set.

**What the graph made visible, which is the point of having one.** A
call whose head is a VALUE rather than a name — dispatch through a
capability record's field, `((c.render) x)` — cannot be resolved by
this fixpoint, and the walk does not guess: it records no edge and
marks the row `#effects-incomplete`. Measured 2026-08-31 on
`(fn (useIt c x) ((c.render) x))` — `F useIt … #effects-incomplete`,
no `#calls=` key at all — and an AXTAG or `handle` claim over such a
body is `AX3037`/`AX3038` rather than a refusal. So the graph states
its own limit in the stream instead of reporting a set that looks
complete. Until 0.6.0 the unresolvable head was a trait-method call:
`walkCallHead` unioned *every* implementation, and those edges named
`Trait#Type#method`, for which `symbols` prints no row — the gap
`check-agent-policy.sh` still describes in prose ("an impl METHOD BODY
gets no AXSYM row at all …"). `trait` and `impl` are `AX2004` now, so
that gap and the four edges pointing at it went with them: measured
over every stdlib module, **zero** edges name a generated callee.

**Two caveats, both measured.**

`#calls=` names the **resolved** entry, `Mod$name` where the checker
mangled it, not the spelling at the reference site — so an edge says
*which* `writeStr`, which the bare `F` rows cannot. It is also the
symbol codegen emits, so the two cross-check.

A bare **reference** is an edge, not only a call. `(Box direct)` puts
`direct` in the row's `#calls=`, because the effect walk attributes a
reference exactly as it attributes a call, and a graph that disagreed
with the effect row about what counts would break containment by
construction.

**And the second thing the compiler had already computed: the
per-function dataflow summary.** `FnEnt` word 8 is the region-facts
record `rgnFactsNew` builds (`typecheck.ax`, stage S3): which parameters
a body stores a *freshly allocated* value into, which parameters flow
into which, where the result comes from, and whether the walk hit a call
head it could not resolve. It was computed, spent on `AX3049` and
`AX3060`–`AX3063`, and thrown away. `symbols --mir` prints it and
`symbols --axir` serialises it:

```console
F keep p.ax:3:5-9 "(Int -> (Int -> Int))" @ee8bd13… #effects=Alloc,Mut #mir-params=2 #mir-escapes=p #mir-result-from=v
F pass p.ax:12:5-9 "(Int -> (Int -> Int))" @c4b4251… #effects=Alloc,Mut #mir-params=2 #mir-escapes=p #mir-result-from=v
F fresh p.ax:16:5-10 "(Int -> Int)" @24c9891… #effects=Alloc #mir-params=1 #mir-result-fresh
```

`pass` calls `keep` and does nothing else, so the escape reaching its
row is the summary being interprocedural rather than local.

This is a *lower bound*, and it says so in the stream rather than in a
document. `#mir-incomplete` is the per-row admission — this body called
something the walk could not resolve — and `#mir-truncated` is the
whole-module one: the facts fixpoint stopped at `rgnRounds`' 40-round
cap instead of converging. That cap is reached, and until this release
it was silent: measured 2026-09-03 on a generated chain whose leaf
stores a fresh allocation into its parameter, `restrict(no-escape)` on
the head is refused at depth 39 and **accepted** at depth 40.
`scripts/check-mir-projection.sh` pins the sentinel to that boundary,
and `docs/mir-design.md` §4.1 is the record of it.

`--mir` is off by default for the same reason `--calls` is, and for a
second one: it *forces* a walk that otherwise never runs. Measured
2026-09-03, `axiom check self_host/main.ax` goes from 0.72s to 21.7s.
Silence therefore has two guards, the flag and the on-demand fixpoint,
and both must be removed before the gate's silence assertion fires.

The `.axir` file is the same facts as a record file rather than a line
format, with room for the arity, the parameter names, the raw region
words, and — since 2026-09-04 — the block and instruction lines of the
function as `self_host/mir.ax`'s `mLowerFn` lowered it, one `blk`, `op`
or `term` per block, instruction and terminator. A function outside that
lowering's subset carries no body rather than a partial one, so an agent
reading a record can tell "this function does *that*" from "nothing here
knows what this function does". It joins to AXSYM on the **whole `F`
header tuple**, not on the nid,
because the nid is not unique across modules — measured over
`self_host/main.ax --builtins`, 4,068 rows carry one and 4,066 are
distinct, with `die` and `jsonHexDigit` each colliding between two
genuinely different functions. `docs/mir-design.md` is the format's
design record.

**Still refused, separately:** emitted IR is not a function of (source,
target) alone. Module resolution searches the input file's own directory
ahead of `$AXIOM_STDLIB`, so a stray file beside the input changes the
output — silently, at exit 0. A reproducible harness must pin its module
path.

### 3.6 `Agent.Macro` — deferred, with the reason

**Deferred, not refused.** Expansion is deterministic per input and a
macro cannot perform effects at expansion time: a template calling
`readFile` emits the *call*, and the file's contents appear nowhere in
the output. That is the sandbox the proposal wanted, and it holds.

Two measured defects still block a *safe* expansion API, and neither is
small. A third, the one that was never a hygiene defect, is closed:

1. **Reverse hygiene has a live hole**, and the printing macros are no
   longer an instance of it. A template's free identifier can still be
   captured by an entry-file declaration of the same name, which is
   what a general expansion API would have to answer for. The format
   lowering was the worked example — it expanded to bare `show` and
   `strConcat` calls, and an entry file declaring either hijacked every
   hole in the file — and both halves closed:
   `expQualify`'s exactly-one-module rule takes `strConcat` to
   `Str$strConcat`, and 0.7.4 replaced the rendering head with the
   unwritable `format#`.
   `tests/selfhost/383-format-capture.ax` measures both, at exit 60,
   where 20 was the value that said the hijack won.
2. **Declaration-level generated names are unhygienic**, colliding with
   hand-written ones as `AX3006` at a positionless span.
3. ~~**A declaration-macro fan-out is unbounded.**~~ **Bounded,
   2026-08-23.** The two expression budgets are still reachable only
   from `expandExpr`, which phase D never enters, so the fix was a
   third budget on the axis phase D lacked: `expMaxDecls`, 10,000,
   counted at every generated declaration rather than at the product.
   A doubling template that used to be an operating-system kill at
   multi-gigabyte RSS with no diagnostic and no output now refuses as
   `AX3024` (`tests/diagnostics/401-decl-macro-size-limit.ax`, and §5's
   item 5). `axiom check` has the memory lever this said it lacked.

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

`Agent.IR` does not appear as proposed, and neither does
`--agent-harness`. What did land under that heading is a **printer, not
a stage**: `symbols --calls` emits the call graph `inferEffects` already
resolves and used to drop, gated by `scripts/check-agent-calls.sh`
(§3.5). It needed no IR, and it is the answer to the question the
proposal was actually asking - "what does this function reach?" - which
AXSYM could not answer at all, because it stops at the declaration
boundary.

What is left is (2)'s façade, (4), and (6). The effect rows those rest
on are honest now in a way they were not when this was written: the
laundering is closed, `Alloc` names the primitive that allocates rather
than a keyword that does not, and five of MM-EXEC-9a's seven
under-approximations are closed — a function that writes memory, reads
the command line or resets the arena is no longer inferred effect-free
(`docs/memory-model.md` MM-EXEC-9a). Measured 2026-08-31, a `pure` claim
over `(__store64 n 0 1)` is `AX3010 body performs Mut`, and over
`(__argc)` it is `AX3010 body performs IO`. The fifth closure was trait
dispatch, and the construct went in 0.6.0: dispatch through a capability
record's field is not a resolvable call, so it lands back on the first
of the two rows still open — a call the compiler cannot resolve, which
announces itself as `#effects-incomplete` rather than reporting a set
that looks complete. The second is a constructor's allocation, a
decision that table records rather than a gap.

---

## 6. What is refused, and why

- ~~**Promoting `AX3010` to an error.**~~ **DONE 2026-08-25.** The
  obvious next step after making the effect rows honest was to make a
  contradicted claim refuse the build, and this entry recorded it as
  wrong twice over — measured both times, and both now closed. The
  reasoning is kept in full below because it is what the promotion had
  to answer, and because each objection was a real defect rather than a
  reason to leave the claim unenforced.

  The code carries two shapes. "`effect(io)` claim unsupported: missing
  IO" is the one that looks undecidable and is not: it already consults
  `effPartial` and suppresses itself whenever the walk hit a lower bound
  or the function has effect-transparent parameters. The one that looks
  decidable is not: "`pure` claim contradicted: body performs IO" fires
  on a function that merely NAMES an effectful function without calling
  it — `(fn (handoff k) shout)` was reported as performing IO and
  carried `#effects=IO`. Promoting that shape refuses correct programs.

  **That half is closed as of 2026-08-25.** The cause is the
  reference-site rule unioning a referent's effects, which is EXACT for
  a nullary referent — this language invokes `vecNew`, `sysArgc` and
  `__argc` by writing their names, so naming one *is* calling it — and
  an over-approximation for one that takes arguments, where a bare name
  is a value.

  The over-approximation is **not** removed, because a second consumer
  needs it. Deleting it was tried first and measured:
  `tests/diagnostics/340-effect-op-value.ax` is
  `(handle (apply ask 1) (IO) ...)`, which reaches `Ask` only through
  the bare `ask`, and without the union its `AX3011` — a hard error for
  an inexhaustive `handle` list — became an `AX3038` warning. That is
  the wrong direction for a check whose whole job is refusing a list
  that does not name what the body can reach.

  So the same walk answers its two consumers differently. A
  contribution made by NAMING an arrow-typed function arrives as
  *possible* — each effect spelled `~b:IO` beside the definite `b:IO`,
  so the row says per effect what `?:incomplete` says per row in the
  other direction: `?:incomplete` says the row is a lower bound, a
  possible effect says the body may perform it. `AX3011` keeps the
  upper bound and is unchanged. The `contradicted` arm — the one that
  accuses an author of writing a false claim — accuses on definite
  effects only, and over a row holding nothing definite emits `AX3037`
  *cannot be checked* instead. `handoff` draws that; a function that
  really performs IO under a `pure` tag still draws `AX3010`. Measured
  across `stdlib/` and `self_host/` when the rule landed: **zero** of
  3,034 effect rows changed. (Until 2026-08-29 the possibility was one
  row-global marker, `?:byref`, and every reader of it excused the
  whole row — which is how an untagged function one hop above a
  `println` with a `{hole}` compiled clean; `reference.md`, "Definite
  and possible".)

  And the cost lands in exactly the wrong place. `symbols` folds every
  failure into exit 1 and prints no table, so making the claim an error
  deletes the AXSYM surface for the files that carry a wrong tag — eight
  files in this repository's own corpus, one of them 196 symbol lines —
  which is the moment an agent most needs to read what the body actually
  does. `check-tools-selfhost.sh` cannot see it, because its cross-check
  is the equivalence "symbols exits 0 iff check exits 0" and the change
  moves both sides at once.

  **The second reason closed the same day.** `symbols` emits its table
  alongside the diagnostics now rather than instead of them: a symbol
  table is a fact about the SOURCE, every language server answers
  `documentSymbol` for a file that does not compile, and `tc` is built
  before the branch that used to exit — the table was being thrown
  away, not spared. The exit status did not move, so this section's own
  equivalence (`symbols` exits 0 for exactly the files `check` does)
  and the `check-tools-selfhost.sh` sweep that asserts it are both
  untouched; what changed is stdout, which that sweep reads separately.
  Measured: a file with an undefined variable answered **0** symbol
  rows and answers **3**, at exit 1 either way, and a healthy file's
  output is byte-identical.

  **Neither objection survived, and the promotion shipped the same day.**
  `AX3010` is `SEV_ERROR`, it carries a help line naming the three ways
  out, and it left `severity.policy`.

  **What it cost, counted before it was made rather than after:** twelve
  files in the corpus, **all twelve fixtures that construct the
  diagnostic on purpose**, and **zero** in `self_host/` or `stdlib/` —
  the compiler self-compiles with the claim fatal, which is the same
  fact stated as a build. Three of the twelve had a subject that
  *depended* on the severity and were re-founded rather than re-blessed:
  `tests/lsp/070-warning-only.ax` and `080-many-diagnostics.ax` needed a
  warning to still exist in the LSP corpus, and
  `tests/diagnostics/370-mixed-warning-error.ax` needed one of each.
  All three now use `AX3039`, which is a warning **by decision** — the
  AXTAG key namespace is open — so the subject cannot be promoted out
  from under them a second time.

  **What it bought, and what it left:** it made a false tag fatal. It
  did not, by itself, make effects *checked* — a tag was opt-in, and an
  untagged function performing IO still drew nothing.

  **That second gap closed the same day, in `AX3042`.** `checkAxtags`
  opened with `(if (&& (== own 0) (== sig 0)) 0 ...)`, so a declaration
  that volunteered no tag was never asked what it performed; that one
  line WAS the opt-in. Silence is now the claim *"performs no IO"* and
  is checked like any other, so effects are enforced for every
  function. Only `IO` is **required** — measured 2026-08-30, 1,664 of
  the 2,095 effectful functions here perform exactly `Alloc,Mut`, so
  requiring a declaration on those distinguishes nothing from nothing,
  and both stay ambient. (This said "only `IO` is declarable", which is
  a different and false claim: `;@axiom:effect(mut)` over a body that
  writes a field checks **OK**, and over one that does not it is
  `AX3010`, an error. `Alloc`, `Mut` and every custom effect are
  declarable and checked; `IO` is the one whose absence is itself a
  claim.) §"Effect rows in signatures" below is therefore about
  putting effects in *types*, which is a different and still-open
  question from whether they are enforced.

  `AX3037`/`AX3038` stay warnings, and
  `tests/diagnostics/355-tag-over-approximated.ax` pins the boundary in
  a single fixture: the unverifiable claim renders `W AX3037` and the
  refuted one on the next declaration renders `E AX3010`.

  The gate keeps its job either way: `check-agent-policy.sh` is where a
  violated *policy* stops a build, which is §3.4's argument arriving a
  second time, and it is about the standard library declaring what it
  performs rather than about any one tag being true.

- **`--agent-harness` as a build mode.** Determinism is already
  unconditional; strictness already has an artifact; a mode is a new axis
  on every gate. §3.4.
- **`Agent.IR`** as a new lowering stage. No IR exists to snapshot, and
  the emitter's correctness rides on emission order. The graph it was
  reaching for shipped without one. §3.5.
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
| the call graph explains the effect rows it sits beside | **`scripts/check-agent-calls.sh`** — containment, totality, grounding, and silence, each with a negative probe |
| the edges themselves do not change unnoticed | **`tests/tools/symbols-zoo-calls.golden`**, cross-checked against the plain golden by stripping the key |
| a published dataflow summary is the record's own words | **`scripts/check-mir-projection.sh`** — containment against the raw region words, totality on the header tuple, silence by default, and the truncation sentinel held to the depth it reports |
| the record file survives its own reader, and that reader reads | **`scripts/check-mir-roundtrip.sh`** — round trip over the corpus, a non-normal file normalised to a fixed point, and a closed grammar with every malformed fixture refused |
