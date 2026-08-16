# Macros

**This document is the measured status of the implementation.** The
normative specification — what a conforming implementation must do,
including the parts not built yet — is
[macro-system.md](macro-system.md), and the memory model it sits on is
[memory-model.md](memory-model.md).

What Axiom's macro system does, what it does not do, and the
measurement behind each claim. This follows the convention of
[self-hosting.md](self-hosting.md) and [v1-roadmap.md](v1-roadmap.md):
every capability claim is stated with the observation that established
it, so a reader can re-run the probe rather than take the claim on
trust.

Status as of 2026-08-14: expansion is a pass of its own, hygienic in
the binder direction and — for a module-defined macro — at the
definition site, and everything it generates is type-checked —
including an `impl` method's body and a trait default's, which until
the same day were never expanded at all: `check` passed and the build
died in `opt` blaming the toolchain
([macro-system.md](macro-system.md) `MAC-EXP-3a`, pinned by
`tests/selfhost/367-macro-in-impl.ax`, 93 where the unfixed compiler
exits 4). Declaration macros, the syntax/* query vocabulary, and
`derive` — shipped in `stdlib/Pre.ax`, with the spec's worked
examples running verbatim as fixtures 374-379 — all landed on
2026-08-14, across seven commits. Multi-rule patterns and repetition
do not exist. Section 5 is the list, and section 6 is why the order
is what it is.

---

## 1. The form

There are two, and their templates are disjoint kinds:

```scheme
; expression macro: the template is ONE EXPRESSION
(macro (name param...) template)
(pub macro (name param...) template)

; declaration macro (rule form): everything after the pattern is the
; template, each form one generated DECLARATION (2026-08-14)
(macro name
  ((name param...)
   (:: ...)
   (fn ...)))
```

The expression form's name lives *inside* the head parens, exactly as
a function's does; the rule form's pattern must repeat the macro's
name in head position. A macro is applied to exactly as many arguments
as it declares parameters; the invocation is replaced by the template
with each parameter reference replaced by that argument's syntax tree.
An expression macro expands in expression position only, a declaration
macro in declaration position only; either crossing is `AX3027`
(`tests/diagnostics/505-decl-macro-positions.ax`). A declaration
template may generate `fn`, `::`, `data`, `struct` and `impl`
declarations, further macro invocations, and `syntax/for` iterations
over them — any other declaration kind is `AX3021` at the macro's own
line — a
name-position argument must be a bare identifier, and a macro is
invocable from the entry file and from a module alike — a module's own
invocation puts its products in that module's namespace, with the
template's `pub` deciding what leaves it (2026-08-15)
([macro-system.md](macro-system.md) `MAC-CAP-8` for the limits).
Measured: `tests/selfhost/372-decl-macro.ax` (144) and
`373-decl-macro-types.ax` (10, type-position substitution with the
float flags recomputed).

```scheme
(macro (when test body) (if test body 0))

(when (== n 40) 5)     ; becomes  (if (== n 40) 5 0)
```

There is no compile-time evaluation. The compiler executes no code from
a source file: expansion is a rewrite and nothing else. That is the
tier-1 decision, normative as [macro-system.md](macro-system.md)
`MAC-LANG-13` (first recorded in [v1-roadmap.md §4.2](v1-roadmap.md)), and it
is a property of the threat model, not an implementation convenience.

A macro's arguments are substituted as *syntax*, so an argument used
twice in a template is evaluated twice:

```scheme
(macro (twice x) (+ x x))
(twice (side 3))       ; calls `side` twice
```

## 2. Where expansion happens

Between import resolution and the type checker, in
`self_host/expand.ax`, over the merged declaration list — in two
phases since 2026-08-14: phase D expands declaration-position
invocations to a fixpoint first, so the declarations they generate are
in the list before any body is walked (a generated fn's body can
invoke expression macros, and a later declaration can call a generated
function, order-independently); phase E then expands
expression-position invocations inside every declaration body.

This is load-bearing and it is a change. Expansion used to run inside
`codegen.ax` at emit time, which meant the checker never saw an
expansion. Measured on the compiler before the move:

| Program | Was | Is |
|---|---|---|
| a template calling an undefined name | `check` says `OK`, exit 0 | `AX3001`, anchored at the invocation |
| a template under-applying a function | `check` says `OK`, exit 0 | `AX3013`, anchored at the invocation |
| a macro generating a non-exhaustive `match` | compiles silently | `AX3005`, the same diagnostic the hand-written match draws |
| a macro constructing a struct, then a field read | `AX3004: expected Int, found I64` blaming the user's own line | compiles; answers correctly |

The third row is roadmap criterion 1's "exhaustiveness still checked on
the generated `match`" and it is now met. The identical non-exhaustive
match written by hand and written by a macro now draw the same code.

`check` and `build` also agree now, which they did not: a template
using `while`, `set` or a field access passed `check` and then died in
`opt` as `AX4003 opt failed` against `<toolchain>` — the compiler
blaming the toolchain for its own bug, with no span into the source.

## 3. Hygiene

**A binder introduced by a template cannot capture a name from the call
site.** Both places a template can introduce one are covered:

```scheme
(macro (addTo x) (let ((tmp 100)) (+ tmp x)))
(let ((tmp 1)) (addTo tmp))          ; 101   (was 200)

(macro (orElse o d) (match o ((Some v) d) ((None) d)))
(let ((v 42)) (orElse (Some 8) v))   ; 42    (was 8)
```

The mechanism is renaming, not scope sets. At each expansion every
binder the template introduces — `let`, `let mut`, `lambda` parameters,
`match` arm pattern binders — is renamed to `<name>.<counter>`, and
references to it inside the template are renamed with it.

The name shape is chosen so the collision is impossible rather than
unlikely, and it holds on both sides:

- `.` is `TK_DOT` to the lexer, never an identifier character, so
  **no Axiom source can spell `tmp.1` as one identifier** — measured:
  `(let ((tmp.1 5)) tmp.1)` is `AX2001`.
- `.` *is* legal in an unquoted LLVM identifier, so the renamed binder
  survives codegen's register naming with nothing to escape —
  measured: `llc` accepts `%tmp.1`.

The counter is a per-run monotonic integer, not a hash of an address,
so the emitted IR is byte-identical across runs and
`scripts/check-reproducible.sh` keeps holding. It is deliberately *not*
the checker's `tcCounter`: that one names type variables `_tN`, those
names are printed inside `AX3004` messages, and the AXDL goldens pin
them byte for byte.

**A macro name no longer outranks every binder in the program.**
Expansion used to consult the macro table before the symbol table, so a
macro named `v` rewrote every occurrence of the identifier `v`
anywhere:

```scheme
(macro (v) 9)
(fn (f v) v)      (f 1)          ; 1   (was 9)
(let ((v 2)) v)                  ; 2   (was 9)
```

**A free identifier in a template means what it meant where the macro
was written.** This is the reverse direction of hygiene, and it used to
fail in a way that made one macro mean two things. A module `MacScope`
defining both `helper` and a macro `callHelper` whose template calls
it:

| Call site | Was | Is |
|---|---|---|
| an entry file that defines its own `helper` | 6 — the *entry's* | 50 — `MacScope`'s |
| a function inside `MacScope` | 50 — `MacScope`'s | 50 — unchanged |
| under a caller's `(let ((helper 0)) ...)` | `AX3004 expected function type, found Int` | 50 — the local cannot capture it |

Same macro, same template, two answers, chosen by the caller's module —
and neither compiler diagnosed it, because both were resolving a name
that really was in scope. Gated by
`tests/selfhost/364-macro-definition-site.ax` (157; the unfixed
compiler exits 1).

The mechanism costs nothing outside the expander. `resolveImports` runs
before this pass and already mangles an imported `fn`/`::` declaration's
name to `Mod$name`, so the definition-site name a template's free
identifier should resolve to **already exists as a declaration name**.
Rewriting the reference to it is enough: `findFnEnt` looks names up in a
table keyed by exactly those, and `mangledFor` passes an
already-mangled name through unchanged. Neither resolver learns
anything about macros. The rewrite is conditional on `Mod$name` really
being a declaration, which is what keeps it from touching a reference
to `+` or to a constructor (constructors are not mangled) — each finds
nothing and stays bare, resolving outward exactly as before. A name the
macro's own module merely **imported** also finds nothing and stays
bare, and that one is not benign: it is the fourth hole below.

**Three bare names in pattern position are not binders**, and the
renamer treated them as if they were. `true` and `false` are literal
*tests* — `emitPattern` compares the scrutinee against 1 and 0 for them
and `checkPatternTyped` binds nothing — so renaming one to `true.1`
turned the test into a binder, the arm matched everything, and every
later arm became unreachable:

```scheme
(macro (isTrue b) (match b ((true) 1) ((false) 0)))
(isTrue false)                          ; 0   (was 1)
(match false ((true) 1) ((false) 0))    ; 0   unchanged
```

The same `match`, written by hand and written by a macro, disagreeing —
which is the one thing a hygiene mechanism exists to prevent, and a
silent wrong answer rather than a diagnostic. `_` is excluded with them
because the checker special-cases it too. Nothing else is: a bare
constructor name in pattern position IS a binder in this language, which
is why `(Nil)` needs its parentheses, so renaming it is correct and is
what the existing hygiene cases depend on. Pinned by
`tests/selfhost/365-macro-pattern-literal.ax` (95; the unfixed compiler
answers 97), which also carries `_`, an integer literal, a nullary
constructor and a constructor spine whose binder must still be renamed.

### What hygiene still does NOT cover

**A macro defined in the entry file.** Entry-file declarations are left
bare by `resolveImports` — there is no `Mod$name` to resolve to — so a
caller's local binding of the same name can still capture a template's
free identifier. It is a loud failure rather than a wrong answer
(`AX3004 expected function type, found Int` on the probe above), but it
is not a diagnostic about capture and it names neither the macro nor
the binding that shadowed it.

~~**Qualified reference to a macro.**~~ **Closed, 2026-08-14.**
`(QualMac::qdbl 21)` expands, a zero-parameter macro's bare-qualified
spelling expands, and a qualified private macro is `AX3023` naming its
module. The mechanism is a split of the reference — bare part against
the macro's name, module part against its declaration's module — not a
mangle of the declarations, which is what keeps every bare-name
behaviour in this file byte-stable. `tests/selfhost/368-macro-qualified.ax`
(47; the unfixed compiler refuses with two `AX3001`s) and
`tests/diagnostics/485-qualified-private-macro.ax` pin it. Two imported
modules defining the same macro name still resolve a BARE invocation
last-wins — the documented ordering rule — and qualification now
disambiguates on demand.

~~**An imported macro still outranks an entry-file function of the
same name.**~~ **Closed, 2026-08-14.** A bare invocation whose name a
bare `fn`/`::` declares resolves to the function — mirroring
`findFnEnt`'s entry-file resolution — unless the macro belongs to the
invocation site's own module; the macro stays reachable by
qualification. `tests/selfhost/369-macro-vs-function.ax` (15) pins it,
and its ablation is the reason the hole mattered more than its
paragraph here admitted: with the arities AGREEING the old behaviour
was not the loud-but-wrong `AX3018` this section described — it was
the macro's answer, 10 against the function's 15, silently. Within ONE
file the collision was always caught (see below); the import boundary
now resolves instead of ambushing.

**A name the macro's module merely imported is still capturable.** The
definition-site rewrite tries exactly one spelling, `Mod$name` for the
macro's *own* module. A template calling a function its module imported
finds no such declaration, stays bare, and resolves at the call site —
the same one-macro-two-meanings failure the definition-site fix closed,
in the case it does not reach
([macro-system.md](macro-system.md) `MAC-HYG-8`.4; absent from this
list until 2026-08-14, when the spec called out that this section read
the residue as benign). Closing it means resolving a free identifier to
its *true* defining module, which is the same lookup module-qualified
macro names need.

### Macros occupy the value namespace

A macro and a function cannot share a name in the same file. Expansion
consults the macro table before anything else, so the function would
simply be unreachable — and before macros joined `declNamespace`'s
value namespace, this was silent: the file below checked `OK` and
answered 11 where the function says 20.

```scheme
(macro (thing x) (+ x 1))
(:: thing (-> Int Int))
(fn (thing n) (* n 2))
```

```
error[AX3006]: duplicate definition `thing`
1 | (macro (thing x) (+ x 1))
  |         ----- `thing` first defined here
3 | (fn (thing n) (* n 2))
  |      ^^^^^ `thing` redefined here
```

That the macro's span is real — and so the "first defined here" line
points anywhere at all — is the other half of a fix in the same slice:
`parseMacroDecl` stamped no span on a macro node, which also left
`lsp.ax`'s `documentSymbol` arm for macros dead since it was written.
Pinned by `tests/diagnostics/993-macro-shadows-function`.

## 4. Diagnostics

Nine codes, all in the semantic range because expansion is
semantic-analysis-time work:

| Code | Slug | What it catches |
|---|---|---|
| `AX3018` | `macro-arity` | too FEW arguments. A longer spine is not an error in expression position: the surplus is applied to whatever the macro produced, which is how a macro expanding to a function stays usable. Measured: `(macro (one x) x)` invoked as `(one 5 6)` is `AX3004 expected function type, found Int` at the surplus argument, not `AX3018`. In DECLARATION position arity is exact — the result is declarations, not a value |
| `AX3019` | `macro-recursion-limit` | expansion did not terminate (limit 128) |
| `AX3020` | `macro-duplicate-parameter` | two parameters sharing a name |
| `AX3021` | `macro-template-unsupported` | a template form the expander cannot substitute into — including a declaration template generating a kind outside the v1 surface, at the macro's own line |
| `AX3022` | `macro-set-target` | a parameter used as a `set` target, given an expression |
| `AX3023` | `private-name` | reaching a macro its module does not export — the general visibility code, shared by macros since they joined the value namespace |
| `AX3024` | `macro-expansion-limit` | the expansion's OUTPUT exceeded a budget: nested deeper than 1024 forms, or more than 2,000,000 forms produced. The parser's limits measure the source; these measure what expansion produced from it |
| `AX3027` | `declaration-macro` | every way a declaration-position invocation fails: unknown head (a typo'd keyword lands here, where it used to be a bare `AX2003` that stopped the parse), an expression macro in declaration position or a declaration macro in expression position, a non-identifier argument in a name position, and a module-side invocation reaching a pipeline that carries no mangling records. `axiom explain AX3027` is the catalogue |
| `AX3032` | `macro-capture` | an entry-file macro's own free identifier is shadowed at the invocation (MAC-HYG-8.1). Refused rather than captured: before it, the program quietly computed with the local binding - 0 where the macro's own `helper` answers 40, at exit 0 |
| `AX3028` | `syntax-query` | every `syntax/*` query with no answer (MAC-CAP-5/6): an unknown or wrong-position head (the vocabulary is CLOSED), a subject with nothing to answer (constructors of a struct, of nothing, of an imported type), a query written outside a macro template, a declaration named into the reserved `syntax/` prefix. `axiom explain AX3028` is the catalogue |

`AX3006` (duplicate definition) also reaches macros now — see
"Macros occupy the value namespace" above.

`AX3018` and `AX3019` each replace a failure that was not a diagnostic
at all. Under-application left the parameter's own name in the
generated code (`add i64 40, %q`, rejected by `opt` as an undefined
value); over-application dropped the surplus argument **without
evaluating it**, so its side effects silently did not happen - it is now
applied rather than dropped, which is a rewrite the reader can follow
and a type error when it is wrong; and
`(macro (loopy x) (loopy x))` segfaulted the compiler with no output
and no diagnostic, in about 10 ms of CPU time.

`AX3021`'s *expression-template* default arm **has no reachable
producer today**, and that is on purpose. Every form an expression
template can contain has a case in `substTpl`, so nothing reaches the
default arm. It exists because that arm used to return the node
*unchanged*, and that single decision was eight separate silent
miscompiles: `let mut`, `set`, `while`, field access, field store,
struct construction, `alloc` and `handle` each survived into the
generated code carrying the template's own identifiers. The promise
recorded here — "the next form added to the language will reach
`AX3021` and say so, in the commit that adds it" — was kept on
2026-08-14: declaration templates are the next form, and the kinds
outside their v1 surface reach `AX3021` at the macro's own line
(`tests/diagnostics/510-decl-macro-template-kind.ax`), the code's
first reachable producer.

### What a diagnostic inside an expansion looks like

It anchors at the **invocation**, in the file being compiled, and — 
since 2026-08-14 — carries one **expansion frame** per enclosing
instantiation, naming the macro with the span of its declaration in its
own file:

```
error[AX3001]: undefined variable `noSuchFunction`
 --> probe.ax:3:13
  |
3 | (fn (main) (bad 1))
  |             ^^^ no binding named `noSuchFunction` in scope
  |
 = note: in this expansion of `bad` (MacLib.ax:2:13-16)
```

AXDL renders the frame as `&MacLib.ax:2:13-16:"bad"` — the one field
on the line whose file is not the diagnostic's own — JSON as a
`{"macro","file","line","col"}` object in `expansion`, and the LSP
appends the name. A nested invocation carries two frames, outermost
first. `tests/diagnostics/490-expansion-backtrace.ax` pins all of it,
and `verify-axdl-spans.py` checks the frame's span against the macro's
file exactly as it checks every other claim.

The mechanism dodged the data-model rewrite this section used to
predict. A `Diag` still carries one *primary* unit; the frame element
widened to `(name, span, unit)`; and no node grew provenance — every
node a template produces already carries the invocation's span *by
reference*, so the expander records one table entry per instantiation
and a post-pass attaches frames to any checker diagnostic whose
primary span is a recorded handle. What has NOT landed is
[macro-system.md](macro-system.md) `MAC-DIAG-5`'s second snippet: the
human renderer names the declaration's location but does not yet open
the second file to caret it.

### One crash this did not fix — since fixed, 2026-08-09

`(macro (m x) ())` segfaulted the compiler at emission, and so did
`(fn (main) ())` with no macro anywhere: the parser answered node handle
**0** for the empty form and `emitExpr` dereferenced it. The expander
already guarded handle 0 everywhere it walks, so it was not a *second*
road to the crash, but the road itself was in the parser and was out of
that slice's scope. Measured then, with and without a macro: exit 139,
no output, no diagnostic.

It is now `AX2001` — `()` in expression position is a refusal, the same
one `[]` and `(set)` already gave — along with twenty-two other
positions of the same two characters, seven of which killed `check`
rather than the emitter. A template is an expression, so
`(macro (m x) ())` is refused at the macro's own line before any
invocation is expanded. See
[self-hosting.md §13](self-hosting.md#13-the-empty-form-a-node-the-parser-said-it-built-and-never-made);
the bank that pins it is `scripts/check-degenerate.sh`, and
`empty-in-macro-tpl` and `empty-macro-arg` are two of its cases.

## 5. What does not exist

- **Declaration macros beyond the v1 surface.** The v1 form exists
  (§1, 2026-08-14): rule-form macros generating `fn`/`::`
  declarations and further invocations. Module-side invocation joined
  it on 2026-08-15 - a module derives over its own types, the
  template's `pub` deciding what leaves it. What does not exist:
  `trait` templates (`AX2003` - a template position does not parse the
  form at all), and `import`/nested-`macro` templates, which are
  `AX3021` at the macro's line and refusals by decision. `impl`
  templates joined in the fourth commit of 2026-08-14, `data` and
  `struct` on 2026-08-15, `type` and `effect` the same day.
- **`derive` as a stdlib library.** The mechanism is DONE for sums
  AND for struct lenses: declaration macros plus the query vocabulary
  (2026-08-14, two commits) run macro-system.md §10.2's nullary
  `deriveEq` verbatim (`tests/selfhost/374-derive-eq.ax`, 101) and
  §10.3's `deriveLenses` verbatim (`375-derive-lenses.ax`, 34 —
  declaration/argument-position `syntax/for`, `syntax/fields`,
  `syntax/same`'s expansion-time diagonal, field-name substitution).
  `syntax/binders` and `syntax/fold` landed the same day (third
  commit): the fieldful free-function `deriveEq` runs over a
  mixed-arity sum from one template
  (`tests/selfhost/377-derive-eq-fieldful.ax`, 30 — the nullary case
  falls out of the empty fold). The `impl`-generating form landed in
  the fourth commit: derived instances COMPOSE — `(deriveEq Inner)`
  then `(deriveEq Outer)` dispatches the inner field's comparison to
  the first instance by its static type
  (`tests/selfhost/378-derive-eq-impl.ax`, 30). Two gaps this list
  carried are closed: a `deriveEq` shipped in `stdlib/Pre.ax` (needs
  module-side types — LIFTED in the seventh commit: `stdlib/Pre.ax`
  ships `deriveEq`, and it derives over imported types too,
  `tests/selfhost/379-derive-imported.ax`), and nested `syntax/join`
  (2026-08-15: either side of a join may be a join, so nested
  declaration iteration names its products — a lens set over two
  structs sharing a field name generated `getX` twice and was
  `AX3006`, `tests/selfhost/387-syntax-nested-join.ax`, 47). The
  parallel `syntax/for` landed beside it, zipping several sequences
  in each of the three iteration positions
  (`tests/selfhost/386-syntax-parallel-for.ax`, 63).
  The `deriving` clause is REFUSED as of the fifth commit (`AX2004`
  naming the replacement; the formatter poisons rather than rewrites
  — the two grammars refuse together, MAC-CAP-9).
- **Patterns.** The rule-list *surface* exists with exactly one rule
  (the declaration form). No multiple rules, no literal atoms, no
  nested patterns, no alternatives; an expression macro is still one
  positional parameter list. "Pattern-based" in the roadmap's tier-1
  sense is not implemented; this is substitution.
- **Repetition.** No `...`; `.` cannot lex as part of a token, so this
  needs a lexer change that ripples to `tree-sitter-axiom/grammar.js`
  and `format.ax`, both of which re-implement the token set. This is
  also why the printing macros interpolate by CAPTURE (`{name}`) and
  have no positional `{}` or argument list: a macro takes a fixed
  number of arguments, and a variadic `println` is repetition's first
  real customer. See [macro-system.md](macro-system.md) MAC-CAP-10.4.

(Module-qualified macros stood in this list until 2026-08-14 — §3
records the close. Declaration-level macros as a whole stood here
until the same date. Format strings stood here until 2026-08-15:
`(syntax/format e)` and `(syntax/formatln e)` parse a string literal
at expansion time, and `println`/`print`/`eprintln`/`eprint`/`format`
are ordinary macros over them — MAC-CAP-10, and the reason `IO` no
longer exports a print function per type.)

## 6. The order the rest should land in

1. ~~**Module qualification for macros**~~ — **done**, in three
   instalments: a template's free identifiers resolve at the
   definition site and macros occupy the value namespace, so a
   same-file collision is `AX3006` (§3); and since 2026-08-14,
   `Pre::when`-style qualified invocation works (private ones are
   `AX3023`), and an entry-file function outranks an imported macro
   of the same name. What remains under this heading: an entry-file
   macro's free identifiers are still capturable, and a name the
   macro's module merely imported still is too (§3's two open holes).
2. ~~**`Diag` frames carrying a span and a unit**~~ — **done,
   2026-08-14** (criterion 3): a diagnostic inside an expansion now
   names each enclosing macro with its declaration's span in its own
   file, in all four renderings —
   `tests/diagnostics/490-expansion-backtrace.ax` pins one frame and a
   nested two. It touched exactly what this item predicted:
   `diag.ax`'s word 10, the four renderers, the published grammar,
   `645-axdl-repetition`'s hand-built string (which survived
   byte-for-byte — the bare `&"name"` form still renders) and
   `verify-axdl-spans.py`, which now checks a frame's span against the
   MACRO's file.
3. ~~**Declaration-level macros**~~ — **v1 done, 2026-08-14**
   (criterion 1's prerequisite). It touched exactly the three surfaces
   this item predicted: the parser (an unknown top-level head now
   parses as an invocation, `TAG_D_MACROCALL`, instead of dying as
   `AX2003`; the rule form parses its template with the real
   declaration parsers), the pipeline (phase D expands
   declaration-position invocations to a fixpoint before the
   declaration list is fixed, then phase E walks bodies as before),
   and `format.ax` (invocation heads print as expressions; a rule
   form's interior prints verbatim from source, because `fpExpr`
   would rewrite `fn` to `lambda` inside it). Invocable from the
   entry file and from a module alike since 2026-08-15; `AX3027`
   covers every refusal, `axiom explain AX3027` the catalogue.
4. ~~**`derive`**~~ — **done as a mechanism, 2026-08-14** (criterion
   1): explicit declaration macros, with the spec's `deriveEq`s
   running verbatim (fixtures 374/377/378, the impl form's instances
   composing) and the `deriving` clause REFUSED the same day - the
   blast radius macro-system.md counted (one zoo file pair,
   reference.md's example) and nothing else. What remains is the
   *stdlib shipping* of the library — which landed the same day:
   `stdlib/Pre.ax` carries `deriveEq`, fixture 379 uses it over an
   entry-file type and an imported one, and a private subject
   refuses (fixture 550).
5. **Repetition patterns** — the boilerplate case. Needs the lexer,
   `format.ax` and the tree-sitter grammar to move together, and flips
   a checked-in refusal golden (`tests/fmt/parity/060-splice-refused`)
   to an acceptance.

## 7. Reproducing everything above

```bash
scripts/check-self-host.sh 36        # 360-365, the macro corpus
scripts/check-diagnostics.sh 99      # 990-993, the refusals
```

The ablation that gives the "was" column of every table here is a
compiler built from the commit before the expander moved:

| Case | want | before | after |
|---|---|---|---|
| `361-macro-hygiene` | 143 | 208 | 143 |
| `362-macro-coverage` | 57 | 4 (`AX4003`) | 57 |
| `363-macro-shadowing` | 3 | 18 | 3 |
| `364-macro-definition-site` | 157 | 1 (`AX3004`) | 157 |

and one refusal that used to be an acceptance:

| Case | Before | After |
|---|---|---|
| `993-macro-shadows-function` | `OK`, exit 11 | `AX3006`, exit 1 |
