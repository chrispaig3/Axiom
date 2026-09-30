# The agent harness

How an agent reads, checks and rewrites Axiom programs, and what the
compiler guarantees while it does.

This page is a design. A claim about what exists today names the probe
or gate that pins it. A claim about what doesn't exist says so plainly,
and a sentence that mixes the two says which half is which. We keep them
apart because an agent-facing surface written against an imagined
compiler fails silently.

---

## 0. How to read this document

Sections 1 and 2 describe the compiler as it is. Section 3 onward is
proposal.

A proposal the repository already satisfies is marked **shipped** and
cites the gate that pins it. A proposal that needs a compiler change is
marked **owed** and names what blocks it. §5 orders the work by what
blocks what, not by date.

---

## 1. What is already there

Four agent-facing notations ship today, each pinned by a gate:

| Notation | What it carries | Pinned by |
|---|---|---|
| **AXDL** | one line per diagnostic, with machine-applicable fixes as byte-range substitutions | `scripts/check-diagnostics.sh` |
| **AXSYM** | one line per symbol: kind, name, span, type, NID, and every accepted AXTAG | `scripts/check-tools-selfhost.sh` |
| **NID** | `FNV-1a-64(kind ++ bareName)`, stable across reordering and reformatting | `scripts/check-tools-selfhost.sh` |
| **AXTAG** | `;@axiom:<key>(<value>)` above a declaration, validated where the compiler knows the key | `scripts/check-diagnostics.sh` |

Three facts about them shape most of this design.

**AXTAG already carries the `agent:*` namespace.** A declaration tagged
`;@axiom:agent:allowed(net,fs)` compiles today. The tag is recorded
against that declaration, and `axiom symbols --diagnostic-format=ai`
re-emits it as `#agent:allowed=net,fs`. The key namespace is open by
design, as [the reference](reference.md) says, and
`tests/diagnostics/346-axtag-key-typo.ax` already uses `agent:readonly`
and asserts it draws nothing.

AXSYM re-emits the tags of *imported* modules too, so one command gives
a whole-program tag stream. Nothing has to be added to the compiler for
an agent to write these tags. What's missing is the checking.

**AXDL already carries rewrites.** A machine-applicable fix travels with
its diagnostic as `?<loc>:"<msg>"~>"<replacement>"`. A tool applies it
as a byte-range substitution and never parses English. This is the
existing rewrite channel, and it is narrower than `safeRewrite`: the
compiler writes the fix, not the agent.

**One effect boundary already refuses to emit.** `(handle BODY (Pure) 0)`
over a body that performs `IO`, `Alloc` or `Mut` is `AX3011`: an error,
exit 1, and no binary written. It costs nothing at run time. With no
declared custom effect in the list, the handler expression is dead and
the form lowers to the body alone. This is the strongest primitive the
language offers the harness, and it is shipped.

---

## 2. What the compiler does not do

The proposal assumed otherwise.

**Effects are not in types.** `TAG_T_ARR` carries a parameter and a
result and no effect row. `axiom symbols` renders a function that
performs I/O as a plain `(Int -> Int)` and puts the inferred set beside
it as `#effects=IO`.

Effects are a side analysis keyed by function entry, not a typing
judgement, and nothing is checked at a call site. Any API whose
signatures carry effect constraints is proposing a new type system.

**There is no IR.** `self_host/codegen.ax` is an LLVM *text* emitter:
`(pub :: emitModule (-> Int String String))` takes declarations in and
gives assembly text out. `emitExpr` is `(-> Int Int Int)`, and an
expression's value is a `String` in `CG` field 2. Block state is
`curBlock`, one String, and `terminated`, one bit. There is no
intermediate representation, no block and no CFG, so `Agent.IR` as
proposed has nothing to refer to.

In practice the **AST is the IR**, annotated in place. The typechecker
fills each node's `ty` word, `resolveDecls` stamps its `module`, and
`expandProgram` and then `lowerConds` rewrite it.
What was missing was never a representation. It was that nothing
*published* one. §3.5 shows the graph the effect fixpoint already walks,
now printed instead of dropped.

**The AST is untyped.** A node is a flat 11-word record: tag, a, b, c,
span, vis, ty, axtags, module, fieldNames and defscope. Every word is an
`Int`, read by offset. `parser.ax` makes 355 `memGetWord` calls and
builds the record in two places, and across 22 compiler modules there is
exactly one real ADT. So `(vecLen (parseModule toks))` type-checks,
answers `OK` and segfaults: everything is `Int`, so the checker protects
nothing.

**A refuted AXTAG claim is an error.** A false `;@axiom:effect(pure)` on a body
that performs I/O is `AX3010`, an error, and no executable is written.

`tests/diagnostics/severity.policy` is a hand-maintained allowlist of
the codes permitted to render as warnings: `AX3037`, `AX3038`,
`AX3039`, `AX3043`, `AX3045`, `AX3046`, `AX3048`, `AX3051`, `AX3053`
and `AX3074`.

`AX3037`, `AX3038`, `AX3039` and `AX3051` are the half of the AXTAG
family that the compiler can't answer, and one split is the whole rule
for them. A claim the walk checked and refuted refuses the build. A
claim the walk wasn't in a position to check informs, and doesn't
refuse. `AX3051` is the unanswerable half of a
`restrict(...)` claim, and its answerable half is `AX3049`, an error.

`AX3048` is on the list for a different reason: it isn't about
something the compiler couldn't determine. A reference to a name marked
`;@axiom:deprecated` is fully determinate, because the name exists,
type-checks and works. It warns because the release that announces a
removal is the one release in which callers must still build. Making it
an error would make deprecation and removal the same event. See
`COMPAT-7` in [compatibility.md](compatibility.md).

`AX3053` is on the list because of a measurement. An operation the
program reaches with no handler is determinate at run time: the process
exits 71. The check that reports it reads `main`'s finished effect row,
and that approximation errs in both directions:

- A lambda's operations count where the lambda is *written*. A worker
  bound before the `handle` that covers its call is reported, although
  it runs (exit 20).
- The `let` of a `handle` form is an opaque local. A closure built
  inside a `handle` and called after it pops isn't reported, although
  it traps (exit 71).

As an error, `AX3053` would refuse the first program and accept the
second. That is §6's objection to a check that refuses correct
programs, landing on both sides of one rule. `;@axiom:unhandled(trap)`
on an `effect` declaration says the trap is intended. `stdlib/Test.ax`
carries it, because otherwise `axiom test`'s generated `main` would be
reported on every suite.

`AX3040` and `AX3010` are errors. The compiler tells a function that
never returns from one that fabricates a value, so `AX3040` can refuse.
The shapes the walk can't check go to `AX3037`, so `AX3010` fires only
on a claim the walk refuted.

**There is no strictness flag.** There's no `-Werror`, no `--deny` and
no `--agent-harness`. The driver's flag table is closed, and an unknown
flag exits 2.

---

## 3. The corrected architecture

### 3.1 `Agent.AST` — a typed façade, and why it is now safe

**owed.** The compiler's AST can't be handed out as it stands. The
harness owns a *façade*: nominal handle types over the flat node, with
accessors that are the only way to read a word.

```scheme fragment
(type NID  = Int)
(type Node = Int)

(pub struct Decl
  (nid  : NID)
  (node : Node)
  (name : String))

(pub :: astOfFile    (-> String Int))
(pub :: astDecls     (-> Int Int))
(pub :: declOfNid    (-> Int NID Int))
(pub :: nodeKind     (-> Node Int))
(pub :: nodeChildren (-> Node Int))
```

Note the shape: `(pub :: name Type)` and `(pub fn (name args) body)` are
two separate declarations. The proposal's `(pub fn f :: (-> A B))` is a
parse error, `AX2001`, at the `::`. There is also no `List`: `[T]` is
refused in type position (`AX2004`) and there is no list literal, so
every sequence is a `Vec` handle or an ADT you declare.

The façade is safe to write because a `type` alias now expands in
struct fields and in `data` constructor fields, as it does in
signatures. Before that, `(Decl 1 n s)` drew `AX3004` against its own
field, and the emitter leaked 80 bytes an iteration from the `String`
in the next field. `tests/stdlib/374-arc-alias-field.ax` measures both
spellings at 0.

Without aliases, every handle would be spelled `Int` and the checker
would protect nothing. Handle types are the point of the façade, so the
alias fix is a prerequisite.

**Hazard: the type namespace is flat, but not silent.** There is no
`Module::Type`, and a qualified spelling doesn't parse in type position.
Two `Agent.*` modules that both export a `Node` don't merge, though.
Each module's own code reaches its own declaration. A reference from a
module that owns neither is `AX3044`, naming both modules
(`scripts/check-type-namespace.sh`).

You still can't write the disambiguation at the reference. The escapes
are an import name list that leaves one of them out, or a unique name.
So the harness rule stands: give every exported type a name that is
unique across the whole namespace. Breaking it gives you a diagnostic,
not a wrong answer at exit 0.

### 3.2 `Agent.Tags` — read and validate

**mostly shipped.** Reading is `axiom symbols --diagnostic-format=ai`
piped through a parser. The AXSYM line already carries the NID, the
type, the inferred `#effects=` and every AXTAG, `agent:*` included.
Because AXSYM re-emits imports, one command gives a whole program's
tags.

**owed:** validation of the three new keys, and the schema. Adding a
checked key means an edit to the AXTAG value map and a new diagnostic
in the `AX30xx` band. Its long-form text must be in
`self_host/explain.ax` before it can ship, or `check-tools-selfhost.sh`
fails.

Tag values are compared without regard to case, as Effects in
[the reference](reference.md) says. So `effect(io)` and `effect(IO)`
are one claim: `;@axiom:effect(IO)` above a body that prints checks
**OK**, and `symbols` gives it `#effect=IO #effects=IO`.

### 3.3 `Agent.Safe` — built on `handle`, not on types

The proposal's premise fails, but its goal survives. Effects can't
appear in a signature, so `forbidEffects :: (-> NID (List Effect) Bool)`
has no type to be written in. The enforcement it wants exists one level
down, in a form that already refuses to emit:

```scheme fragment
(handle BODY (Pure) 0)
```

So `Agent.Safe` is a *macro* surface over `handle`, not a function
surface over types. `(safeRegion BODY)` expands to the form above. The
compiler refuses the build if `BODY` reaches `IO`, `Alloc` or `Mut`,
and the emitted code is `BODY` with nothing added.

**CLOSED: `handle` doesn't launder effects.** `handle` names a set and
discharges a smaller one. For a built-in effect, the effect still
reaches the caller, because `handleIsDynamic` installs evidence only
for a *declared* effect, and otherwise the form lowers to its body. A
`;@axiom:effect(pure)` function that wraps its I/O in `(handle BODY (IO) 0)` is
refused, and so is an inner handle under a `(Pure)` boundary:

```console
$ axiom check --diagnostic-format=ai --input launder.ax   # the laundering `effect(pure)` claim
E AX3010 launder.ax:6:6-12 axtag-mismatch "AXTAG mismatch on `sneaky`:
    `effect(pure)` claim contradicted: body performs IO" ?"an AXTAG is a CLAIM,
    and this is the compiler answering it: make the body match the tag,
    or correct the tag to what the body does. Deleting the tag also
    silences this, and an untagged function is never checked - but that
    WITHDRAWS the claim rather than answering it, and every reader that
    trusted the tag loses the guarantee. A claim the walk cannot check is
    AX3037 and stays a warning; this code fires only where the walk has
    an answer"
compilation failed due to 1 previous error          # exit 1

$ axiom check --diagnostic-format=ai --input pureb.ax     # an inner handle under (Pure)
E AX3011 pureb.ax:6:29-32 effect-mismatch "effect mismatch: unhandled
    effect `IO`"
compilation failed due to 1 previous error          # exit 1
```

It is the **lying callee** that is refused, and its truthful caller
draws nothing at all. So an `Agent.Policy` reading a build that
succeeded is reading a `#effect=pure` the compiler stands behind. What is still advisory is
the smaller set below.

Tested by `tests/diagnostics/348-handle-discharge.ax`.

One hole still bounds what `Agent.Safe` can promise, and a second is
closed:

- A function value that goes through memory, in a struct field or a
  `let`-bound local, escapes both the `;@axiom:effect(pure)` claim and the
  `(Pure)` boundary. `AX3037` and `AX3038` report it, as warnings.
- **CLOSED.** An effect operation reached with no handler anywhere
  still aborts the process with status 71, but it no longer compiles
  clean. `AX3053` reads `main`'s finished effect row. A `handle` is the only construct that
  discharges a custom effect, so an effect still in that row is one
  nothing handled. It is a **warning**, for the measured reason given
  in §2. `scripts/check-test-runner.sh` deletes
  `;@axiom:unhandled(trap)` from a shadow copy of `stdlib/Test.ax` and
  requires the warning, so that claim is checked rather than assumed.

### 3.4 `Agent.Policy` — a gate, not a build mode

**This is the largest structural correction.** The proposal makes
policy a compiler mode. The only boundary policy that works in this
repository is a *shell gate*: `check-ffi.sh` compares a binary's `nm`
symbols against a per-crate `axiom-allow.txt`, with a negative probe
proving the allowlist can go red.

`Agent.Policy` should be built the same way: a gate over the AXSYM
stream that compares each declaration's `#effects=` and `agent:*` tags
against a checked-in allowlist. There are three reasons, each measured:

1. Determinism is already unconditional. `check-reproducible.sh`
   asserts byte-identical output for every compile, because the
   bootstrap compares stage N against stage N+1, and that is
   meaningless if a stage can differ from itself. Making deterministic
   IR a property of a *mode* would imply ordinary builds may be
   nondeterministic, which this project has already refused.
2. The strictness the mode would turn on is per-diagnostic severity,
   and `tests/diagnostics/severity.policy` already governs that, in
   both directions.
3. A mode flag is a new axis on every gate. An allowlist is a file.

**shipped** for the standard library's effect rows: the gate, the
allowlist and its negative probes, as `scripts/check-agent-policy.sh`
against `tests/agent/stdlib-effects.allow`. It doesn't read `agent:*`
tags yet.

**Hazard:** AXSYM lines embed absolute paths, unlike `emit-llvm`
output, which is path-free. A policy artifact built from AXSYM isn't
portable between checkouts until that is normalised.

### 3.5 `Agent.IR` — still refused; the graph it was reaching for shipped

**The proposal stays refused.** `self_host/codegen.ax` is a one-pass,
syntax-directed text emitter. `emitExpr` is `(-> Int Int Int)`: node
and context in, the same context out. An expression's *value* is a
string in `CG` field 2, an LLVM register name like `"%.t7"`, with a
float bit beside it in field 14.

Block structure is two scalars. `curBlock` is one String, written in
exactly one place and read in five, all five filling a phi predecessor.
`terminated` is one bit. The file defines four structs and one
constructor, and that constructor holds AST pointers. There is no
instruction, no block, no CFG and no def-use edge as data anywhere in
it.

So there is nothing to snapshot. Building something to snapshot means
re-architecting the emitter, and the ARC evidence ordering, the TCO
rewrite and the arena discipline all ride on it *in emission order*.
That is not a harness feature.

AXSYM doesn't fill the gap on its own, because it stops at the
**declaration boundary**. On a 13-line, three-function program, AXSYM
gives three lines with kind, name, span, type, NID and effects, and
nothing about a body. `emit-llvm` gives 5,514 lines and 303 defines
with **zero** debug locations, so it is faithful and unmappable at
once. Without the call graph below, neither lets an agent ask what
`main` calls.

**What was missing was never an IR. It was the graph**, and the
compiler already computes it. `inferEffects` (`typecheck.ax`) is a
monotone fixpoint over the call graph. It walks every body, resolves
every reference site to a `FnEnt` and folds that entry's effect row
into the caller's. That is how `#effects=IO` reaches `main` through
`greet` from `writeStr`.

**shipped.** `tcNoteCall` records the edge the walk resolved, on a
`calls` word beside `effects` on the same `FnEnt`. `symbols --calls`
prints it as `#calls=`:

```console
F twice p.ax:3:5-10 "(Int -> Int)" @852e07f… #calls=*
F greet p.ax:6:5-10 "(String -> Int)" @194c3b2… #effects=IO #calls=IO$writeStr,Str$strEq
F main  p.ax:12:5-9 "Int" @6159d36… #effects=IO #calls=greet
```

`scripts/check-agent-calls.sh` gates four properties:

- **Containment.** No callee's effect escapes its caller's row, so
  `#calls=` and `#effects=` are two views of one walk (595 stdlib
  rows, 0 violations).
- **Totality.** Every *inferred* effect row carries an edge accounting
  for it. The only exemption is `stdlib/Ffi.ax`, whose rows are
  *constructed* by `tcAddExtern` rather than walked.
- **Grounding.** Every one of the 90 IO-performing library rows reaches
  a `__syscallN` or an `extern` transitively. A syscall is recorded as
  an edge for this reason: it short-circuits above `findFnEnt`, so
  without it the bottom of every IO chain would be an effect from
  nowhere.
- **Silence.** Without `--calls` the stream is byte-identical to
  before. `tests/tools/symbols-zoo.golden` pins 147 rows, and a key on
  every row would put an edge list in the diff of every future stdlib
  edit. `--builtins` is the precedent: content selection on `symbols`,
  not a build mode. `tests/tools/symbols-zoo-calls.golden` pins the
  edges. The two goldens are cross-checked by stripping the key from
  one and comparing bytes with the other.

The graph runs with `--builtins`. An operator is a `FnEnt` in this
language, so `+` and `==` are real edges. `__alloc` is a builtin *and*
is what puts `Alloc` in the row beside it, so a graph that dropped
builtins couldn't explain its own effect set.

**The graph states its own limit.** A call whose head is a *value*
rather than a name, such as dispatch through a capability record's
field, `((c.render) x)`, can't be resolved by this fixpoint. The walk
doesn't guess. It records no edge and marks the row
`#effects-incomplete`. For `(fn (useIt c x) ((c.render) x))` the row is
`F useIt … #effects-incomplete`, with no `#calls=` key at all. An AXTAG
or `handle` claim over such a body is `AX3037` or `AX3038` rather than
a refusal.

The policy *can* refuse an incomplete row. An unexempt
`#effects-incomplete` in stdlib fails `check-agent-policy.sh` outright.
The only exemptions are the four higher-order rows the gate names with
reasons: `vecSortBy`, `vecSiftDownBy`, `taskFoldOne` and `taskFold`. Its `partial.ax` probe plants one to prove the refusal fires. A
lower bound never passes as an upper one.

`trait` and `impl` are refused as `AX2004`, so no edge can name a
generated `Trait#Type#method` callee, which would have no AXSYM row.
Across every stdlib module, **zero** edges do.

There are two caveats, both measured:

- `#calls=` names the **resolved** entry, `Mod$name` where the checker
  mangled it, not the spelling at the reference site. So an edge says
  *which* `writeStr`, which the bare `F` rows can't. It is also the
  symbol codegen emits, so the two cross-check.
- A bare **reference** is an edge, not only a call. `(Box direct)` puts
  `direct` in the row's `#calls=`. The effect walk attributes a
  reference exactly as it attributes a call, and a graph that disagreed
  with the effect row about what counts would break containment.

**The compiler also computes a per-function dataflow summary.**
`FnEnt` word 8 is the region-facts record `rgnFactsNew` builds
(`typecheck.ax`, stage S3). It records which parameters a body stores a
*freshly allocated* value into, which parameters flow into which, where
the result comes from, and whether the walk hit a call head it couldn't
resolve. The checker uses it for `AX3049` and `AX3060`–`AX3063`.
`symbols --mir` prints it and `symbols --axir` serialises it:

```console
F keep p.ax:3:5-9 "(Int -> (Int -> Int))" @ee8bd13… #effects=Alloc,Mut #mir-params=2 #mir-escapes=p #mir-result-from=v
F pass p.ax:12:5-9 "(Int -> (Int -> Int))" @c4b4251… #effects=Alloc,Mut #mir-params=2 #mir-escapes=p #mir-result-from=v
F fresh p.ax:16:5-10 "(Int -> Int)" @24c9891… #effects=Alloc #mir-params=1 #mir-result-fresh
```

`pass` calls `keep` and does nothing else, so the escape reaching its
row shows the summary is interprocedural, not local.

This is a *lower bound*, and the stream says so. `#mir-incomplete` is
the per-row admission: this body called something the walk couldn't
resolve. `#mir-truncated` is the whole-module one: the facts fixpoint
stopped at `rgnRounds`' round cap instead of converging. The cap is the
program's own size, so on a chain whose leaf stores a fresh allocation
into its parameter, `restrict(no-escape)` on the head is refused at
every depth. `scripts/check-mir-projection.sh` pins `#mir-truncated`'s
absence at depth 5 and at depth 60, with the escape on `f0`'s row, and
[mir-design.md](mir-design.md) §4.1 records it.

`--mir` is off by default for the same reason `--calls` is, and for a
second one: it *forces* a walk that otherwise never runs. With it,
`axiom check self_host/main.ax` goes from 0.72s to 21.7s. So silence
has two guards, the flag and the on-demand fixpoint, and both would have
to be removed before the gate's silence assertion fires.

The `.axir` file holds the same facts as a record file rather than a
line format. It has room for the arity, the parameter names, the raw
region words, and the block and instruction lines of the function as
`self_host/mir.ax`'s `mLowerFn` lowered it: one `blk`, `op` or `term`
per block, instruction and terminator. A function outside that
lowering's subset carries no body rather than a partial one. So an
agent reading a record can tell "this function does *that*" from
"nothing here knows what this function does".

An `.axir` record joins to AXSYM on the **whole `F` header tuple**, not
on the nid, because the nid isn't unique across modules. Over
`self_host/main.ax --builtins`, 4,068 rows carry one and 4,066 are
distinct: `die` and `jsonHexDigit` each collide between two different
functions. `docs/mir-design.md` is the format's design record.

**Still refused, separately:** emitted IR is not a function of (source,
target) alone. Module resolution searches the input file's own
directory ahead of `$AXIOM_STDLIB`, so a stray file beside the input
changes the output, silently, at exit 0. A reproducible harness must
pin its module path.

### 3.6 `Agent.Macro` — deferred, with the reason

**Deferred, not refused.** Expansion is deterministic per input, and a
macro can't perform effects at expansion time. A template calling
`readFile` emits the *call*, and the file's contents appear nowhere in
the output. That is the sandbox the proposal wanted, and it holds.

One measured defect still blocks a *safe* expansion API, and it isn't
small: item 2 below. Items 1 and 3 are closed, and they stay listed
because what they cost is the argument for the mechanisms that closed
them:

1. ~~**Reverse hygiene has a live hole.**~~ **Closed** (`MAC-HYG-8.1` in
   [macro-system.md](macro-system.md)). A template's free identifier
   could be captured by an entry-file declaration of the same name. A
   macro is a top-level declaration, so every free identifier in its
   template means something top level, and one bit on the reference
   says so. Both resolvers skip the local scope for a stamped
   reference.

   The format lowering was the worked example. It expanded to bare
   `show` and `strConcat` calls, and an entry file declaring either
   hijacked every hole in the file. Both halves are closed:
   `expQualify`'s exactly-one-module rule takes `strConcat` to
   `Str$strConcat`, and the rendering head is the unwritable `format#`.
   `tests/selfhost/383-format-capture.ax` measures both, at exit 60,
   where 20 would mean the hijack won.
   `tests/selfhost/394-macro-entry-capture.ax` (exit 130) measures the
   general case.
2. **Declaration-level generated names are unhygienic.** They collide
   with hand-written ones as `AX3006`, at a positionless span.
3. ~~**A declaration-macro fan-out is unbounded.**~~ **Bounded.** The
   two expression budgets are reachable only from `expandExpr`, which
   phase D never enters. So the fix is a third budget on the axis
   phase D lacked: `expMaxDecls`, 10,000, counted at every generated
   declaration rather than at the product. A doubling template refuses
   as `AX3024` instead of being killed by the operating system at
   multi-gigabyte RSS with no diagnostic
   (`tests/diagnostics/401-decl-macro-size-limit.ax`, and §5's item 5).
   `axiom check` now has a memory lever.

There is also a **closed compile-time reflection vocabulary**: the
`syntax/*` forms. They let a program interrogate the declaration list at
expansion time, and anything outside the vocabulary is refused as
`AX3028`. That is a better foundation than a new API, and §5 orders it
accordingly.

---

## 4. Reaching the compiler at all

The proposal assumes an agent program can get an AST. It can today, but
the route works by accident, so it is worth naming.

A program that does `(import parser)` with
`AXIOM_PATH=<repo>/self_host` set lexes, calls `parseModule` and walks
real declarations. Driving the lexer, parser and codegen together
reproduces the compiler's own LLVM IR byte for byte.

It works by accident because import resolution searches five slots, and
`self_host/` is reachable only through a literal path relative to the
working directory. `self_host/codegen.ax` documents that literal as
legacy, kept so gate harnesses can bisect: *"They are history, not the
rule."* Setting `AXIOM_PATH` is the only supported route.

It doesn't scale, because `import` splices source into one whole
program instead of linking. Hello-world emits 10 LLVM defines, and a
parser client emits 590. A full pipeline client emits 1,939 and builds a
binary of about 970 KB, roughly 56 times the size of hello-world's.
Every harness recompiles the compiler into itself.

The ABI should take a different route. `--emit-staticlib` already
produces a linkable archive that exposes compiler internals as C
symbols: 449 exported text symbols, including `parser$parseModule`. The
entry file's own `pub` functions become unmangled C symbols, and that is
what makes a curated ABI possible.

So the harness ABI is the exported surface of one Axiom file. It
doesn't freeze the compiler's 2,135 `pub` functions. Those offer no
encapsulation boundary to inherit anyway, because only 2 functions in
all of `self_host/` are private.

Selective import, such as `(import parser (TAG_D_FN nodeVis))`, is the
access control the language offers, and it works today.

---

## 5. Ordering, by what blocks what

1. ~~**Close the `handle` laundering hole.**~~ **Shipped**
   (`tests/diagnostics/348-handle-discharge.ax`). It went first and
   alone, because without it everything `Agent.Safe` and `Agent.Policy`
   claim is advisory.
2. **`Agent.AST` façade:** **owed**. **`Agent.Tags` reader:**
   **shipped**, as `stdlib/Agent/Tags.ax`. It reads the AXSYM stream
   rather than the compiler's internals, and §4 gives the size argument.
3. ~~**`Agent.Policy` gate, allowlist and negative probe.**~~
   **Shipped**: `scripts/check-agent-policy.sh` against
   `tests/agent/stdlib-effects.allow`. On its first run it found two
   standard-library functions that performed I/O without claiming it.
4. **Promote the `agent:*` checks:** **owed**. That means new
   diagnostics in the `AX30xx` band, `explain` entries, and a
   `severity.policy` decision made on its merits rather than inherited.
   Read §6's `AX3010` entry before starting. The neighbouring promotion
   turned out to be wrong twice over, for reasons that apply here too.
5. ~~**Bound declaration-macro expansion.**~~ **Shipped**
   (`tests/diagnostics/401-decl-macro-size-limit.ax`). This is the size
   limit phase D never had. Any harness that compiles code it did not
   write needed it first.
6. **`Agent.Macro`**, over `syntax/*`, after item 5: **owed**. Item 5
   unblocked it. It still waits on the one hygiene defect §3.6 leaves
   open: item 2 there, declaration-level generated names.

`Agent.IR` does not appear as proposed, and neither does
`--agent-harness`. What landed under that heading is a printer rather
than a stage. `symbols --calls` emits the call graph that `inferEffects`
already resolves, gated by `scripts/check-agent-calls.sh` (§3.5). It
needed no IR. It answers the question the proposal was really asking,
"what does this function reach?", which AXSYM could not answer, because
it stops at the declaration boundary.

What is left is item 2's façade, item 4 and item 6. The effect rows
they rest on can now be trusted:

- the laundering hole is closed;
- `Alloc` names the primitive that allocates, rather than a keyword that
  does not;
- five of MM-EXEC-9a's seven under-approximations are closed, so a
  function that writes memory, reads the command line or resets the
  arena is not inferred effect-free (MM-EXEC-9a in
  [`memory-model.md`](memory-model.md)).

An `effect(pure)` claim over `(__store64 n 0 1)` draws `AX3010` with "body
performs Mut, Unsafe", and over `(__argc)` it draws `AX3010` with "body
performs IO".

The fifth closure was trait dispatch, and that construct was removed in
0.6.0. Dispatch through a capability record's field is not a resolvable
call, so it falls under the first of the two rows still open: a call the
compiler cannot resolve. That row announces itself as
`#effects-incomplete` instead of reporting a set that looks complete.
The second open row is a constructor's allocation, which that table
records as a decision rather than a gap.

---

## 6. What is refused, and why

- ~~**Promoting `AX3010` to an error.**~~ **Shipped.** Once the effect
  rows could be trusted, the obvious next step was to make a contradicted
  claim refuse the build. This entry first recorded that step as wrong
  for two reasons. Each was a real defect, and both are now fixed. The
  reasoning stays because the promotion had to answer it.

  The first reason was false accusations. The code has two shapes.
  "`effect(io)` claim unsupported: missing IO" looks undecidable but is
  not. It already consults `effPartial`, and stays silent whenever the
  walk hit a lower bound or the function has effect-transparent
  parameters. "`effect(pure)` claim contradicted: body performs IO" looks
  decidable but was not. It fired on a function that only names an
  effectful function without calling it: `(fn (handoff k) shout)` was
  reported as performing IO and carried `#effects=IO`. Promoting that
  shape would have refused correct programs.

  The cause is the reference-site rule, which unions a referent's
  effects into the row. That is exact for a nullary referent. Axiom
  invokes `vecNew`, `sysArgc` and `__argc` by writing their names, so
  naming one *is* calling it. For a referent that takes arguments, a
  bare name is a value, and the union over-approximates.

  The over-approximation stays, because a second consumer needs it.
  Removing it was tried first. `tests/diagnostics/340-effect-op-value.ax`
  is `(handle (apply ask 1) (IO) ...)`, which reaches `Ask` only through
  the bare `ask`. Without the union, its `AX3011` became an `AX3038`
  warning. `AX3011` is a hard error for an inexhaustive `handle` list,
  and its job is to refuse a list that doesn't name what the body can
  reach, so that was the wrong direction.

  So the same walk answers its two consumers differently. An effect
  contributed by naming an arrow-typed function arrives as *possible*,
  spelled `~b:IO` beside the definite `b:IO`. A possible effect says the
  body may perform it. `?:incomplete` works per row and in the other
  direction: it says the row is a lower bound.

  - `AX3011` keeps the upper bound and is unchanged.
  - The `contradicted` arm, which accuses an author of a false claim,
    accuses on definite effects only. Over a row with nothing definite
    it emits `AX3037` *cannot be checked* instead.

  `handoff` draws `AX3037`, and a function that really performs IO under
  an `effect(pure)` tag still draws `AX3010`. Across `stdlib/` and `self_host/`,
  zero of 3,034 effect rows changed when the rule landed.

  Possibility is marked per effect because a single row-wide marker,
  `?:byref`, let every reader excuse the whole row: an untagged function
  one hop above a `println` with a `{hole}` compiled clean. See
  "definite" and "possible" under [Effects](reference.md#effects).

  The second reason was where the cost would land. `symbols` folded
  every failure into exit 1 and printed no table. Making the claim an
  error would have deleted the AXSYM surface for every file with a wrong
  tag, just when an agent most needs to read what the body does. In
  this repository's corpus that was eight files, one of them 196 symbol
  lines. `check-tools-selfhost.sh` couldn't catch it: its cross-check is
  "`symbols` exits 0 if and only if `check` exits 0", and the change
  moves both sides at once.

  That is fixed too. `symbols` prints its table alongside the
  diagnostics rather than instead of them. A symbol table is a fact
  about the source, and every language server answers `documentSymbol`
  for a file that doesn't compile. `tc` was already built before the
  branch that exited, so the table was being thrown away for nothing.

  The exit status is unchanged, so the equivalence above and the sweep
  that asserts it are untouched. Only stdout changed, and the sweep
  reads that separately. A file with an undefined variable went from 0
  symbol rows to 3, exiting 1 both times, and a healthy file's output
  stayed byte-identical.

  With both reasons answered, the promotion shipped. `AX3010` is
  `SEV_ERROR`, carries a help line naming the three ways out, and is no
  longer in `severity.policy`.

  The cost was counted before the change: twelve files in the corpus,
  and none in `self_host/` or `stdlib/`. All twelve are fixtures written
  to construct the diagnostic, and the compiler self-compiles with the
  claim fatal. Three of the twelve depended on the severity itself, so
  they were given a new subject rather than re-blessed:

  - `tests/lsp/070-warning-only.ax` and `tests/lsp/080-many-diagnostics.ax`
    needed a warning to exist in the LSP corpus;
  - `tests/diagnostics/370-mixed-warning-error.ax` needed one warning
    and one error.

  All three now use `AX3039`, which is a warning by decision because
  the AXTAG key namespace is open. Their subject can't be promoted out
  from under them again.

  The promotion made a false tag fatal. On its own it did not make
  effects *checked*: a tag was opt-in, and an untagged function
  performing IO drew nothing.

  `AX3042` closed that gap. `checkAxtags` opened with
  `(if (&& (== own 0) (== sig 0)) 0 ...)`, so a declaration with no tag
  was never asked what it performed. That one line was the opt-in. Now
  silence is the claim *"performs no IO"* and *"touches no raw memory"*,
  checked like any other, so effects are enforced for every function.

  `IO` is the one effect required transitively: every function up the
  call chain must answer for it. `Alloc` and `Mut` stay ambient. Of the
  591 effectful standard-library functions, 380 perform `Mut`, so
  requiring a declaration on those would distinguish nothing
  (`scripts/check-effect-distribution.sh` pins the distribution).
  `Unsafe` is required too, but lexically (`AX3073`): only the
  declaration that performs an unsafe operation must declare it, and a
  trusted encapsulation ends the obligation for its callers.

  Every effect is declarable and checked, not only `IO`.
  `;@axiom:effect(mut)` over a body that writes a field checks OK, and
  over one that doesn't it is `AX3010`, an error. `Alloc`, `Mut` and
  every custom effect work the same way. What sets `IO` apart is that it
  is required transitively.

  So "Effect rows in signatures" below is about putting effects in
  *types*. That is still open, and separate from whether effects are
  enforced.

  `AX3037` and `AX3038` stay warnings.
  `tests/diagnostics/355-tag-over-approximated.ax` pins the boundary in
  one fixture: the unverifiable claim renders `W AX3037`, and the
  refuted one on the next declaration renders `E AX3010`.

  The gate keeps its job either way. `check-agent-policy.sh` is where a
  violated *policy* stops a build, which is §3.4's argument again. It
  checks that the standard library declares what it performs, not that
  any one tag is true.

- **`--agent-harness` as a build mode.** Determinism is already
  unconditional, and strictness already has an artifact. A mode would
  add a new axis to every gate. §3.4.
- **`Agent.IR` as a new lowering stage.** There is no IR to snapshot,
  and the emitter's correctness depends on emission order. The graph it
  was reaching for shipped without one. §3.5.
- **Runtime telemetry.** `check-freestanding.sh` checks at two levels
  that generated code contains no libc call and that the linked
  executable imports no libc symbol. Telemetry from emitted code would
  fail that gate and the FFI allowlist. The harness may measure at
  *build* time, in a gate, where the rest of the project's measurement
  already lives.
- **Effect rows in signatures.** That is a new type system, not a
  harness.
- **Adoption and satisfaction targets.** This repository has one author
  and is four weeks old. A metric no one can compute should not gate a
  design.

---

## 7. Gates this design owes

A claim without a gate is a comment, so each claim here names its gate.

| Claim | Gate |
|---|---|
| a laundered effect cannot pass a policy region | held: `tests/diagnostics/348-handle-discharge.ax` refuses both shapes and pins §3.3's console session, with assertions 3–4 of `scripts/check-agent-policy.sh` beside `tests/diagnostics/severity.policy` |
| the AST façade hands out no unmapped block | blocked: the façade itself is owed (§5, item 2), so there are no façade records to extend the probe to yet |
| `agent:*` tags survive `fmt`, AXSYM and import | held: `tests/tools/TagLib.ax` and `TagLibImport.ax` in the survival section of `scripts/check-tools-selfhost.sh`. `fmt` is byte-identical, three keys are re-emitted, import is attributed to the defining file, and each key answers to its own comment |
| the policy allowlist can go red | held: the negative probes in `scripts/check-agent-policy.sh` ("every assertion can go red", modelled on `check-ffi.sh`) |
| declaration-macro expansion is bounded | held: `tests/diagnostics/401-decl-macro-size-limit.ax` and `402-decl-macro-width-counted-early.axbad` draw `AX3024`, and `406-decl-macro-round-limit.ax` draws `AX3019` |
| the call graph explains the effect rows it sits beside | held: `scripts/check-agent-calls.sh` checks containment, totality, grounding and silence, each with a negative probe |
| the edges themselves do not change unnoticed | held: `tests/tools/symbols-zoo-calls.golden`, cross-checked against the plain golden by stripping the key |
| a published dataflow summary is the record's own words | held: `scripts/check-mir-projection.sh` checks containment against the raw region words, totality on the header tuple, and silence by default, and holds the truncation sentinel to the depth it reports |
| the record file survives its own reader, and that reader reads | held: `scripts/check-mir-roundtrip.sh` round-trips the corpus, normalises a non-normal file to a fixed point, and refuses every malformed fixture against a closed grammar |
