# Macros

What Axiom's macro system does, what it does not do, and the
measurement behind each claim. This follows the convention of
[self-hosting.md](self-hosting.md) and [v1-roadmap.md](v1-roadmap.md):
every capability claim is stated with the observation that established
it, so a reader can re-run the probe rather than take the claim on
trust.

Status as of 2026-08-09: expansion is a pass of its own, hygienic in
the binder direction, and everything it generates is type-checked.
Declaration-level macros, repetition patterns and `derive` do not
exist. Section 5 is the list, and section 6 is why the order is what it
is.

---

## 1. The form

```scheme
(macro (name param...) template)
(pub macro (name param...) template)
```

The name lives *inside* the head parens, exactly as a function's does.
A macro is applied to exactly as many arguments as it declares
parameters; the invocation is replaced by the template with each
parameter reference replaced by that argument's syntax tree.

```scheme
(macro (when test body) (if test body 0))

(when (== n 40) 5)     ; becomes  (if (== n 40) 5 0)
```

There is no compile-time evaluation. The compiler executes no code from
a source file: expansion is a rewrite and nothing else. That is the
tier-1 decision recorded in [v1-roadmap.md §4.2](v1-roadmap.md), and it
is a property of the threat model, not an implementation convenience.

A macro's arguments are substituted as *syntax*, so an argument used
twice in a template is evaluated twice:

```scheme
(macro (twice x) (+ x x))
(twice (side 3))       ; calls `side` twice
```

## 2. Where expansion happens

Between import resolution and the type checker, in
`self_host/expand.ax`, over the merged declaration list.

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

### What hygiene does NOT cover

The **reverse direction** — a caller's binder capturing a *free*
identifier of the template — is not fixed. A template that refers to a
top-level `helper`, invoked inside a caller's `(let ((helper ...)) ...)`,
resolves to the caller's `helper`.

This is not an oversight to be patched in the expander. It needs
definition-site resolution, which needs macros to be module-qualified,
which they are not: a macro's name is a flat program-wide entry with no
module recorded, `Pre::when` is `AX3001`, and one macro genuinely means
two different things depending on the caller's module. Measured — a
module `MacLib` defining both `helper` and a macro `callHelper` that
uses it:

| Call site | Answer |
|---|---|
| entry file that defines its own `helper` | 6 — the entry's |
| a function inside `MacLib` | 105 — `MacLib`'s |

Same macro, two meanings, chosen by where it was called. That is
§6's first item and it is a resolution change, not an expander change.

## 4. Diagnostics

Five codes, all in the semantic range because expansion is
semantic-analysis-time work:

| Code | Slug | What it catches |
|---|---|---|
| `AX3018` | `macro-arity` | wrong number of arguments |
| `AX3019` | `macro-recursion-limit` | expansion did not terminate (limit 128) |
| `AX3020` | `macro-duplicate-parameter` | two parameters sharing a name |
| `AX3021` | `macro-template-unsupported` | a template form the expander cannot substitute into |
| `AX3022` | `macro-set-target` | a parameter used as a `set` target, given an expression |

`AX3018` and `AX3019` each replace a failure that was not a diagnostic
at all. Under-application left the parameter's own name in the
generated code (`add i64 40, %q`, rejected by `opt` as an undefined
value); over-application dropped the surplus argument **without
evaluating it**, so its side effects silently did not happen; and
`(macro (loopy x) (loopy x))` segfaulted the compiler with no output
and no diagnostic, in about 10 ms of CPU time.

`AX3021` **has no reachable producer today**, and that is on purpose.
Every form a template can contain has a case in `substTpl`, so nothing
reaches the default arm. It exists because the default arm used to
return the node *unchanged*, and that single decision was eight
separate silent miscompiles: `let mut`, `set`, `while`, field access,
field store, struct construction, `alloc` and `handle` each survived
into the generated code carrying the template's own identifiers. The
next form added to the language will reach `AX3021` and say so, in the
commit that adds it, instead of miscompiling quietly. It is recorded
here as unreachable so nobody mistakes its silence for coverage — the
same way [v1-roadmap.md](v1-roadmap.md) records the `&` backtrace field
as rendered-but-unpopulated.

### What a diagnostic inside an expansion looks like

It anchors at the **invocation**, in the file being compiled:

```
error[AX3001]: undefined variable `noSuchFunction`
 --> probe.ax:3:13
  |
3 | (fn (main) (bad 1))
  |             ^^^ no binding named `noSuchFunction` in scope
```

The span is real and it is in the right file. It does not yet name the
macro, which is the second half of roadmap criterion 3, and a reader
sees an error about a name that does not appear on that line.

The reason it is not simply added is a data-model limit, not missing
wiring. A `Diag` carries **one** unit, and the realistic case is a
stdlib macro invoked from a user file — two different source texts on
one diagnostic. Anchoring at the macro's own span instead would point
at a real line of the *wrong* file, which reads as a correct diagnostic
about unrelated code and is worse than pointing nowhere. `Diag`'s
`trace` field exists and all four renderers consume it, but its element
type is `Vec of Str`: a frame can hold pre-rendered English, not a
span. Criterion 3 needs the element widened to carry `(name, span,
unit)` and the AXDL `&"frame"` grammar to gain a location.

### One crash this did not fix, recorded so it is not mistaken for a macro bug

`(macro (m x) ())` still segfaults the compiler at emission — and so
does `(fn (main) ())` with no macro anywhere. The parser answers node
handle **0** for the empty form and `emitExpr` dereferences it. The
expander guards handle 0 everywhere it walks, so it is no longer a
*second* road to the crash, but the road itself is in the parser and
codegen and is out of this scope. Measured on both compilers, with and
without a macro: exit 139, no output, no diagnostic.

## 5. What does not exist

- **Declaration-level macros.** A template is an expression. A macro in
  declaration position is `AX2003`. `derive` needs this.
- **`derive`.** `deriving (Eq Show)` parses and is discarded; the
  clause's names never reach the AST.
- **Patterns.** One parameter list per macro, positional, no literal
  atoms, no nested patterns, no alternatives. "Pattern-based" in the
  roadmap's tier-1 sense is not implemented; this is substitution.
- **Repetition.** No `...`; `.` cannot lex as part of a token, so this
  needs a lexer change that ripples to `tree-sitter-axiom/grammar.js`
  and `format.ax`, both of which re-implement the token set.
- **Module-qualified macros.** See §3.

## 6. The order the rest should land in

1. **Module qualification for macros** — the resolution change §3
   describes. It is the prerequisite for the reverse half of hygiene
   *and* it fixes a live wrong-answer bug, so it is first on both
   counts.
2. **`Diag` frames carrying a span and a unit** — criterion 3. Touches
   `diag.ax`'s word 10, all four renderers, the published AXDL grammar,
   `tests/selfhost/645-axdl-repetition.ax`'s hand-built expected string
   and `verify-axdl-spans.py`.
3. **Declaration-level macros** — criterion 1's prerequisite. Parser
   surface (a template in declaration position), pipeline surface
   (expansion must run before the declaration list is fixed), and
   `format.ax`, which refuses every declaration head in expression
   position and whose refusals are whole-file.
4. **`derive`** — criterion 1. The spelling is an unmade decision:
   threading `deriving`'s names into the AST touches the parser, the
   node layout, AXSYM and the formatter; an explicit `(derive-eq T)`
   macro call needs only (3). Choosing the first pulls in the second.
5. **Repetition patterns** — the boilerplate case. Needs the lexer,
   `format.ax` and the tree-sitter grammar to move together, and flips
   a checked-in refusal golden (`tests/fmt/parity/060-splice-refused`)
   to an acceptance.

## 7. Reproducing everything above

```bash
scripts/check-self-host.sh 36        # 360-363, the macro corpus
scripts/check-diagnostics.sh 99      # 990-992, the refusals
```

The ablation that gives the "was" column of every table here is a
compiler built from the commit before the expander moved:

| Case | want | before | after |
|---|---|---|---|
| `361-macro-hygiene` | 143 | 208 | 143 |
| `362-macro-coverage` | 57 | 4 (`AX4003`) | 57 |
| `363-macro-shadowing` | 3 | 18 | 3 |
