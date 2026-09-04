# The Axiom Macro System

The normative specification of compile-time syntactic abstraction in
Axiom: what a macro is, when it expands, what it may and may not see,
what hygiene guarantees, and what a conforming implementation owes the
tools that read macro-generated code.

This document is the specification, and since 2026-08-22 it is also the
only measured status of the implementation: every rule carries its own
marker and names the fixture that establishes it, so there is no second
document to drift against this one. the roadmap's §4.2
records the design decision this expands. Where anything else in the
repository disagrees with this document, this document is wrong until it
is fixed.

**A status table cannot arbitrate, and one episode proves it.**
`README.md` and `CONTRIBUTING.md` once described this feature
differently — **Complete** with "hygiene (scope sets + gensym) …
expansion backtrace on diagnostics" against **Partial** with "no
repetition, no declaration-level macros, no derive" — and the binary
agreed with the second. `check-doc-drift.sh` could not tell them apart,
because its status-row rule only checks that a **Complete** row names an
existing fixture, never that the row's prose is true; a false claim
passed CI for as long as it existed, and would again. That is why every
rule below names a probe instead of a status word.

Conventions — rule identifiers, RFC 2119 keywords, and the **H** / **P**
/ **R** status markers — are as defined in
[memory-model.md §0](memory-model.md). Briefly: **H** holds today and
names its probe, **P** is normative but unimplemented and says what
happens instead, **R** is refused by design.

---

## 1. The macro language

### 1.1 Declaration form

**MAC-LANG-1 (H).** A macro is declared at top level:

```scheme
(macro (name param...) template)
(pub macro (name param...) template)
```

The name lives *inside* the head parens, exactly as a function's does.
`template` is an **expression**, and a macro's parameters are a flat
positional list of distinct identifiers.

**MAC-LANG-2 (H).** Two parameters sharing a name is `AX3020`.

**MAC-LANG-3 (H).** A zero-parameter macro is invoked either bare or
parenthesized, and both spellings mean the same thing:

```scheme
(macro (five) 5)
(fn (main) (+ five (five)))     ; 10
```

**MAC-LANG-3a (H).** Macros are **order-independent**, like every other
top-level declaration: a macro may be invoked above the line that
declares it. Measured — `(fn (main) (dbl 21))` above
`(macro (dbl x) (+ x x))` answers 42. Expansion therefore has no
"defined before use" rule and **MUST NOT** acquire one; the table is
built from the whole merged declaration list before any body is walked.

**MAC-LANG-4 (H).** A macro's own template is **not** expanded where it
is written. It is expanded once per invocation, against that
invocation's arguments; expanding it in place would rewrite it against
no arguments at all.

**MAC-LANG-5 (H, 2026-08-14).** **A macro invocation in declaration
position expands** (`MAC-CAP-8` v1). A top-level form whose head is not
a declaration keyword parses as a declaration-macro invocation and
resolves against the same table, with the same visibility and the same
qualified-name split as expression invocations. A head that names no
visible rule-form macro — a typo'd keyword lands here too — is
`AX3027` with the head's name in the message, where it used to be a
bare `AX2003 "syntax error"` that also stopped the parse at the first
unknown head, hiding every later diagnostic in the file (measured:
`tests/diagnostics/500-unknown-decl-head.ax` reports both of its
typos; the pre-change compiler reported only the first).

The two template kinds are disjoint, both ways, and each mismatch is
`AX3027` at the invocation: an expression macro cannot stand in
declaration position, and a rule-form macro cannot stand in expression
position (`tests/diagnostics/505-decl-macro-positions.ax` pins all
three refusals).

An expression macro's template written as a declaration form —
`(macro (defTwo nm) (fn (nm) 2))` — still checks `OK` uninvoked
(`MAC-EXP-1a`), and still expands as an *expression* where invoked;
declaration generation is the rule form's alone (`MAC-CAP-8`).

### 1.2 The compile-time environment

**MAC-LANG-6 (H).** A macro's expansion has access to exactly three
things:

1. the syntax trees of its arguments;
2. the identifiers written in its own template;
3. the **merged declaration list** of the program, used for one purpose
   only — resolving a template's free identifiers at the macro's
   definition site (`MAC-HYG-6`).

It has no access to types, to inferred effects, to the values of
anything, or to the file system. A macro cannot ask what type an
argument has, because expansion runs before the checker (`MAC-EXP-1`).

**MAC-LANG-7 (H).** Item 3 is the only introspective capability that
exists today, and it is not exposed to the macro author: it is applied
by the expander, on the author's behalf, to make hygiene work.
`MAC-CAP-5` specifies exposing it.

### 1.3 Namespaces and visibility

**MAC-LANG-8 (H).** Macros occupy the **value namespace**, which they
share with `fn`/`define` and every effect operation.
(Exactly three namespaces exist: value, type, and none. `data`,
`struct` and — since 2026-08-24 — `type` occupy the TYPE namespace and
collide with each other; data constructors and struct field names
occupy *no* namespace and collide with nothing. A trait's own name and
`impl` were in that last group until 0.6.0 removed both words.)

A macro and a function of the same name in one file is `AX3006`, with
both spans real:

```
error[AX3006]: duplicate definition `thing`
1 | (macro (thing x) (+ x 1))
  |         ----- `thing` first defined here
3 | (fn (thing n) (* n 2))
  |      ^^^^^ `thing` redefined here
```

**MAC-LANG-9 (H).** A macro is private to its module unless written
`pub`, or named by an importing `(import M (name))` list. Reaching a
private one is `AX3023`:

```
E AX3023 private-name "`secret` is private to module `mods.Lib`"
```

**MAC-LANG-10 (H).** A `pub` macro whose template invokes a **private**
macro of its own module expands correctly from outside that module. The
expander tracks the *definition site* of the macro being instantiated,
and visibility is judged against it — the same rule `MAC-HYG-6` applies
to free identifiers. Measured: `(open 4)` from another file answers 5,
where `open`'s template calls its module's private `secret`.

**MAC-LANG-11 (H).** The macro table is built in declaration order and
searched **backward**, so a later definition of a name wins. Because
import resolution places an imported module's declarations *ahead* of
the importing file's, this is also what lets an entry file's macro
shadow an imported one. This ordering is a language rule, not an
implementation detail: changing it changes which macro a program means.

**MAC-LANG-12 (H).** A macro name is qualifiable as `Mod::name`, like
any other declaration: `(QualMac::qdbl 21)` expands, a zero-parameter
macro's bare-qualified spelling `QualMac::qfive` expands
(`MAC-LANG-3`, through the same split), and a qualified reference to a
**private** macro is `AX3023` naming the module, not a false `AX3001`.
Pinned by `tests/selfhost/368-macro-qualified.ax` (47; the unfixed
compiler refuses it with two `AX3001`s) and
`tests/diagnostics/485-qualified-private-macro.ax`.

The mechanism is a **split, not a mangle** — the reverse of what this
rule sketched while it was planned. `Mod::name` is not a distinct AST
node: the parser flattens it to `Mod$name`, the spelling import
resolution writes onto `fn`/`::` declarations. Macro declarations keep
their bare names, and the lookup splits the *reference* instead,
matching the bare part against the macro's name and the module part
against the module already stamped on its declaration — `declMatches`'
rule, the same one that fixed qualified constructors. Mangling the
declarations would have moved every bare-name behaviour this document
gates (`MAC-LANG-11`'s ordering, `MAC-LANG-8`'s collisions, five
hygiene fixtures); splitting the reference moved none of them, and the
checker's `isMacroName` applies the identical split so the two sides
keep agreeing.

Two residues, stated so nobody reads this as more than it is: two
imported modules defining the same macro name still resolve a **bare**
invocation last-wins with no `AX3014` — which `MAC-LANG-11` blesses as
a language rule, and qualification now disambiguates on demand — and
`Mod::name` in **type** position is still a parse error, which is a
type-grammar gap, not a macro one.

### 1.4 The no-evaluation invariant

**MAC-LANG-13 (R).** **The compiler MUST NOT execute code from a source
file during compilation.** Expansion is a rewrite and nothing else.

This is the tier decision of
the roadmap's §4.2, made explicitly and restated here
as a rule because everything else in this document is shaped by it:

- **Tier 1, pattern-based** — a macro is a set of pattern/template
  pairs; expansion is a rewrite. This is Axiom's design.
- **Tier 2, procedural** — a macro is an Axiom function from syntax to
  syntax, run at compile time. Strictly more expressive, and it requires
  the compiler to run arbitrary code from the file it is compiling.

Tier 2 **MUST NOT** be introduced as an implementation detail of tier 1.
It is a change to the compiler's threat model and needs a sandbox, a
resource policy, and an explicit decision — not a convenient evaluator
that appears because some macro wanted arithmetic.

The invariant is observable rather than merely asserted: the compiler
does not evaluate anything, including constant arithmetic in its own
output (`MM-EXEC-14`).

### 1.5 Pattern macros

**MAC-LANG-14 (H in part; rules 2026-08-15, patterns 2026-08-16).** A
macro **SHALL** be a sequence of rules, each a pattern and a template,
tried in order. **The rules belong to the RULE FORM**, which is the
decision the 2026-08-15 measurement below forced. They were selected
by ARITY for one day; since `MAC-LANG-15` they are selected by a
MATCH, and arity survives as a pre-filter — see the paragraph after
the example:

```scheme
; the head-list form: one template, one expression, unchanged
(macro (when test body) (if test body 0))

; the rule form: a bare name, then one or more rules, each a pattern
; and a DECLARATION template
(macro deriveTag
  ((deriveTag T)      (:: (syntax/join tag T) Int)
                      (fn ((syntax/join tag T)) 1))
  ((deriveTag T base) (:: (syntax/join tag T) Int)
                      (fn ((syntax/join tag T)) base)))
```

The two forms are distinguished by one token of lookahead — `(macro (`
introduces a head list, `(macro <name>` introduces a rule list — so no
existing program changes meaning, and one rule is the list of length
one. Each rule's pattern repeats the macro name in head position, as
`syntax-rules` does.

**Selection is a MATCH, not a count** (`MAC-LANG-15`, `MAC-LANG-18`):
the rules are tried in order and the first whose pattern matches wins,
where a pattern may be a binder, `_`, a literal or a parenthesised
shape. Arity survives as a pre-filter — a rule whose element count
differs cannot match — so
`tests/selfhost/390-multi-rule-macro.ax` (51), which selects across
three arities, is unchanged, and
`tests/selfhost/392-macro-patterns.ax` (127) is the same macro shape
selected by something other than counting.

Two refusals hang off this, and BOTH changed with the selector:

- an **unreachable rule**, refused at the macro's own line. The old
  test was "two rules of one arity", whose stated reason — arity
  chooses, so the second can never be reached — patterns falsify. It
  narrowed to irrefutability, and took its own code (`AX3033`); see
  `MAC-LANG-18` for both halves.
- an invocation matching **no rule**, `AX3018`, which named every
  arity the macro offers (`takes 1 or 3 arguments`) and now names
  every SHAPE. `tests/diagnostics/585-multi-rule-misuse.ax` pins both,
  and `600`/`605` pin them apart.

**What this rule still specifies and does not yet hold:** rules over
EXPRESSION templates, which is the question the measurement below
leaves open. The pattern language landed in part — see `MAC-LANG-15`
for which four of its six kinds, and which two are still blocked and
on what.

*Today (2026-08-16):* the **rule list takes one or more rules and it
is the declaration-macro form** — `MAC-CAP-8` parses
`(macro name ((name p ...) decl ...) ...)` and each pattern head must
repeat the macro's name. The parameters are no longer a flat list of
identifiers: each is a PATTERN (`MAC-LANG-15`), and selection is a
match in rule order (`MAC-LANG-18`). What this rule still specifies
beyond that: ellipsis (`MAC-LANG-16`) and literal identifiers
(`MAC-LANG-17`). A mismatched invocation is still a refusal and never
a fall-through past the last rule — with several rules, "mismatched"
means matching none of them.

*Two corrections, measured 2026-08-15 by running the example above
through the compiler rather than reading the parser.*

1. **The head-mismatch refusal is `AX2003`, not `AX2001`.**
   `parseDeclMacro` calls `pErr`, which carries no expectation, so it
   renders as a bare `syntax error` — the shape this repository
   replaced for declaration heads and has not yet replaced here.
2. **The multi-rule example in this section does not mean what it
   shows, and would not even if the rule loop existed.** As written it
   is `AX2003` at the second rule's `(` — there is no loop. Reduced to
   one rule it *parses*, and becomes a **declaration** macro whose
   template is one form headed by `if`; invoking it in expression
   position is then `AX3027`, "declaration macro `when` invoked in
   expression position". The rule-list form's template is
   declarations, and `(if test body 0)` in a template is read as a
   nested declaration-macro invocation of `if`.

   So multi-rule cannot simply be "add a loop": the rule form and the
   head-list form differ in what a template *is*, and this section's
   example silently assumed they do not. Deciding it by the template's
   head is not sound either — a declaration template's first form is
   legitimately a nested invocation (`372-decl-macro.ax`'s `defPair`
   generates two), so "not a declaration keyword" would misread it as
   an expression.

   **THE DECISION, made 2026-08-15: rules belong to the rule form, and
   the head-list form stays single-template.** The example above was
   rewritten to a declaration macro to match. A rule list over
   EXPRESSION templates would need the two forms to agree about what a
   template is, and nothing forces that question until patterns exist
   (`MAC-LANG-15`): an expression macro selected by arity alone buys
   little, since its one template already takes whatever arity it
   declares. The narrow half is what shipped, and the wide half is
   held open rather than guessed at.

**MAC-LANG-14a (P, prerequisite).** **Patterns are not a distinct
syntactic category today**, and a pattern-macro design must say what it
does about that. `(Cons h t)` in match position is an ordinary
`TAG_E_APP`, indistinguishable by tag from an application; only
`TAG_P_CON0` (a parenthesised nullary constructor) and `TAG_P_CONNAMED`
(a named-field pattern) are pattern-specific. Pattern-ness is
*positional*.

A conforming implementation **MUST** choose one, and this specification
chooses the second:

1. introduce a real pattern node category — which changes the tag
   numbering that `expand.ax`, `typecheck.ax` and `codegen.ax` all index
   by number, and those numbers are the AST's wire format between the
   parser and its readers (the retired `foreign` tag 29 is documented as
   never reusable for exactly this reason); or
2. keep pattern-ness positional and define a macro that expands *into*
   pattern position as expanding into an expression that the enclosing
   `match` then reads as a pattern.

Choice 2 costs nothing structurally and has one consequence that
**MUST** be stated: a macro cannot tell whether it was invoked in
pattern or expression position, so a macro usable in both **MUST**
expand to a form valid in both.

**MAC-LANG-15 (P; four of the six landed 2026-08-16).** A pattern
**SHALL** be one of:

| Pattern | Matches | |
|---|---|---|
| an identifier | any single form, binding it | **holds** |
| `_` | any single form, binding nothing | **holds** |
| a literal integer, float, char or string | itself | **holds** |
| `(p1 ... pn)` | a form of exactly *n* elements, each matching | **holds** |
| `(p ...)` | zero or more forms matching `p` (`MAC-LANG-16`) | `...` lexes since 2026-08-16; a repeat over a PATTERN rather than a bare NAME is still `AX3034` |
| a **literal identifier** declared in the macro's literal list | itself, by *binding*, not by spelling (`MAC-LANG-17`) | needs scope sets |

(The `...` in the fourth row is this document's metasyntax for "p₁
through pₙ" and not the ellipsis operator, which is why that row cites
no rule and the fifth does.)

**What the four buy, stated as a limit rather than a promise.** A
pattern's head is an ordinary binder, so a nested pattern
discriminates by the SHAPE of a form and never by its head's spelling:
`(m (h T))` matches `(m (anything X))`. Measured while building this —
the first draft of `tests/selfhost/392-macro-patterns.ax` wrote
`((defOp (unary T)) ...)` and `((defOp (binary T)) ...)` expecting two
rules, and both invocations took the first, answering 2 where the file
claimed 3. So the discriminating powers this landed are exactly two:
the shape of a nested form, and the value of a literal. Discriminating
by a head's spelling is `MAC-LANG-17`, and §10.4's `simplify` table —
whose rules are told apart by `+` and `*` in head position — needs it.

The representation discharges `MAC-LANG-14a`'s choice 2 literally: a
pattern is an ordinary expression node in a slot the parser knows is a
pattern, so no tag was added and none renumbered. A nested pattern is
`mkEApp`'s left spine, the same tree an application gets, which is
what makes a pattern and an argument comparable at all — both sides
come out of the same parser.

**Three consequences of that choice, which `MAC-LANG-14a` requires be
stated rather than discovered.** Each is the parser showing through,
and each was measured:

- `((f x) y)` is the same tree as `(f x y)`, because a spine does not
  record where its parentheses were. Symmetric, so two forms that
  spell alike still match; but two RULES whose patterns differ only
  that way are one pattern, and the second is dead without drawing
  `AX3033`.
- `(p)` is the bare binder `p`. A one-element form loses its
  parentheses on the argument side too, so this is symmetric and the
  irrefutability test is right to call such a rule irrefutable — but
  an author who wrote parentheses expecting a shape gets a rule that
  matches everything. `AX3033`'s help says so by name.
- **a parenthesised pattern never matches a KEYWORD-headed form.**
  Arguments are parsed by the ordinary expression parser, so
  `(if p q r)`, `(let ((p 1)) p)`, `(lambda (p) q)` and `(match …)`
  arrive under their own tags and not as spines; a shape pattern of
  the right element count refuses them, and the invocation falls
  through to a more general rule. A macro that must accept those
  shapes takes them under a plain binder.

A literal pattern compares VALUES, not spellings, in all four kinds:
`10` matches `1_0`, `1.0` matches `1.00`, and `"\t"` matches an
argument written as a real tab. The first two come free — the parser
decodes an int and a float on the way in — and the third does not: a
string node keeps its lexeme verbatim by a design the emitter relies
on, so the matcher decodes as it compares. Measured, after an earlier
revision compared string spellings and refused the tab.

A rule's parameters are its patterns' BINDERS, nested ones included,
and `AX3020` refuses a repeated one — `((m a (f a)) ...)` binds `a`
twice and `expParamIndex` is last-wins, so the first would be silently
discarded. `_` is exempt because it binds nothing.

**MAC-LANG-16 (H, v1 landed 2026-08-16).** Ellipsis repetition `...`
**SHALL** be available in both patterns and templates, and a template
**MUST** use a repeated binding under an ellipsis of the same depth.

**v1: one repeating element per rule, and it is a bare name.**
`(m T v ...)` takes one argument and then any number; `v` is bound to
all of them at once, and `(f v ...)` splices them where the pair
stands. That is the variadic macro `MAC-CAP-10.4` says the language
lacks, and `tests/selfhost/393-macro-ellipsis.ax` (63) is one rule
generating a two-field constructor call and a three-field one.

It is the first binding in this expander that is a SEQUENCE rather
than a value. `MAC-LANG-15`'s representation spends each name on
exactly one form — `expParamIndex` then `vecGet` — which is what that
rule said it could not carry; the repeat got a channel of its own on
the env, modelled on the `syntax/for` stack beside it.

The depth rule is `AX3034`, `macro-ellipsis`, in four shapes and split
by where the author can act
(`tests/diagnostics/610-macro-ellipsis-misuse.ax`). At the macro's
line: two `...` in one rule, and a repeat over a PATTERN rather than a
bare name. At the invocation: a repeating name used with no `...`
(which without this refusal died as `AX3001 undefined variable`,
blaming the name), and `...` after something that does not repeat.

Selection composes with `MAC-LANG-18` by turning a rule's arity into a
FLOOR. So a fixed rule and a repeating rule of the same fixed count
are both live — the fixed one takes its own arity, the repeat takes
everything above it — and `AX3033` had to learn the difference between
covering one arity and covering a range.

**What v1 does not do:** a repeat over a nested pattern, which binds
each of that pattern's binders to a sequence in lockstep. That is a
second feature and is refused rather than half-built.

**`...` lexes, and it lexes as an ORDINARY IDENTIFIER.** Three
dots are one token and there is no new token kind: `self_host/lexer.ax`
meets byte 46, looks at the next two, and emits `TK_IDENT` spanning
all three when they are dots too, falling back to `TK_DOT` for a
single one. A lone `.` is untouched, so field access, module paths and
`MAC-HYG-3`'s gensym separator are untouched with it — one dot still
cannot sit inside an identifier. Reading the ellipsis as an identifier
is what made the price below collapse from four implementations to
one.

**The cost this rule stated was wrong, and it was wrong in the
expensive direction.** Re-derived by probe on 2026-08-16, one
implementation at a time, on
`(macro m ((m T a ...) (:: (syntax/join z T) Int) …))`:

| Implementation | Stated | Measured |
|---|---|---|
| `self_host/lexer.ax` | must move | **must move** — the only one that refuses |
| `self_host/format.ax` | must move | **accepts it already**, unchanged: the rule form's interior is copied VERBATIM, and the ellipsis survived a format byte for byte |
| `tree-sitter-axiom/grammar.js` | must move | **parses it already**, no `ERROR` node — its identifier rule admits `.`, which this rule notes two paragraphs down without drawing the conclusion. It reads `...` as an `(identifier)` parameter, so it should still move to model an ellipsis *properly*; that is a fidelity change, not a blocker |
| `tests/fmt/verify-fmt.py` | must move | **models no macro at all** — the word does not appear in it |

And `tests/fmt/parity/060-splice-refused.axp` is not this feature: it
is `` (macro (all es) `(+ ,@es)) ``, a QUASIQUOTE splice, and nothing
about `...` turns it into an acceptance.

So the token half of this rule is one lexer plus a grammar-fidelity
follow-up, not a four-way lockstep. **The real cost is the other
half**, which this rule did not price: a binder under an ellipsis
binds a SEQUENCE, and `MAC-LANG-15`'s binding representation cannot
carry one — a match flattens to a `Vec String` of names beside a
`Vec node` of forms, and `expParamIndex` then `vecGet` spends each
name on exactly one node. Sequences need the for-binding stack
`syntax/for` already uses (`expForLookup`), which is where the seam
was deliberately left.

Two facts make this more delicate than a token addition sounds:

- **The three implementations already disagree.** `format.ax` has
  `FT_BACKTICK` and `FT_COMMAAT` kinds the compiler's lexer does not,
  and treats `'`, `` ` ``, `,` and `,@` as prefix tokens attaching to
  the following form — so `axiom fmt` accepts and **rewrites** source
  that `axiom check` refuses lexically. tree-sitter's identifier rule
  admits `.`, `?`, `~` and `@`, which `lexer.ax` does not.
- **`.` is carrying three jobs already**: field access, the module-path
  separator, and — critically — the hygiene gensym separator, which
  `MAC-HYG-3` relies on being *unspellable*. Claiming `...` for
  repetition does not by itself break that, but any design that makes
  `.` gluable does, and would need a different gensym separator chosen
  from the free bytes (`$ ? @ ` ` ` ~` are the only ones with no
  lexical meaning).

**MAC-LANG-17 (P).** A rule list **MAY** declare *literal identifiers*,
which match only themselves and are compared by **binding**, not by
spelling — the `else` in a `cond`-shaped macro must be *the* `else` the
macro means, not any identifier a caller happened to name `else`. This
is the pattern-side half of hygiene and it is why `MAC-HYG-9`'s scope
sets are a prerequisite: with renaming alone there is nothing to compare
a literal *against*.

**MAC-LANG-18 (H, 2026-08-16).** Rules are tried in order; the first
whose pattern matches wins. If no rule matches, the diagnostic **MUST**
name the macro and list the shapes it accepts — the arity diagnostic
`AX3018` generalised. Today's `AX3018` becomes the one-rule case of it.

Both halves hold. `AX3018` reads *no rule of macro `defN` matches this
invocation; it accepts `(defN (a b))` or `(defN T 7)`* — the rules'
patterns as the author spelled them, joined from the TOKENS each
consumed rather than printed back from the tree, because a float
pattern holds its bits and a char its codepoint and printing either
back would show a spelling nobody wrote.
`tests/diagnostics/605-macro-no-rule-matches.ax` pins it.

**What ordering costs, and the refusal that survived it.**
`MAC-LANG-14` shipped a refusal for two rules of one ARITY, on the
ground that arity was the selector and the second could never be
reached. Patterns falsify that: three rules of arity one told apart by
shape are what `392-macro-patterns.ax` is, and this document's own
`simplify` table is seven rules of arity one. The test narrowed to
what was always the real claim — a rule whose every element is a plain
binder is IRREFUTABLE, matches every invocation of its arity, and
starves anything of that arity after it. That is decidable from the
patterns alone and refuses exactly what the old test refused among
all-binder rules.

It also became its own code. `AX3020` was chosen because both
conditions could be said to say "this macro declares the same thing
twice"; a repeated PARAMETER and an unreachable RULE do not say that,
and a slug reading `macro-duplicate-parameter` on the second is a
machine-readable field that is simply wrong. It is **`AX3033`**,
`macro-unreachable-rule`, pinned by
`tests/diagnostics/600-macro-rule-unreachable.ax` and by
`585-multi-rule-misuse.ax`, which measures that the narrowing did not
lose the case it was narrowed from.

---

## 2. The expansion model

### 2.1 Position in the pipeline

**MAC-EXP-1 (H).** Expansion is a pass of its own
(`self_host/expand.ax`), running **after import resolution and before
the type checker**, over the merged declaration list.

This placement is normative, not incidental. Before it, expansion ran
inside `codegen.ax` at emit time, and every one of the following was
true and invisible:

| Program | Emit-time expander | Today |
|---|---|---|
| template calling an undefined name | `check` says `OK`, exit 0 | `AX3001` at the invocation |
| template under-applying a function | `check` says `OK`, exit 0 | `AX3013` at the invocation |
| macro generating a non-exhaustive `match` | compiles silently | `AX3005`, the same code the hand-written match draws |
| template using `while`, `set` or a field access | `check` OK, then `AX4003 opt failed` against `<toolchain>` | compiles; answers correctly |

**MAC-EXP-1a (H).** A macro that is **never invoked is never checked**.
Its template is not walked, so an undefined name, a type error or an
unsupported form inside it produces no diagnostic at all — the template
only becomes a program at an invocation. A conforming implementation
**MAY** check templates independently; this specification does not
require it, because a template's meaning depends on its arguments and
most useful templates do not type-check in isolation.

**MAC-EXP-1b (H).** If expansion emits any error, the compiler renders
those diagnostics and **exits without running the checker**. Expansion
refusals therefore never appear alongside type errors, and their order
is stable: expansion diagnostics are merged ahead of the checker's.

**MAC-EXP-2 (H).** Everything a macro generates **MUST** be type-checked
exactly as hand-written code is, including exhaustiveness. There is no
"generated code" exemption anywhere in the checker, and there **MUST
NOT** be one: the guarantee that the same `match` written by hand and by
a macro draws the same diagnostic is the property a hygiene mechanism
exists to protect.

**MAC-EXP-3 (H).** A function body is expanded **in place** — written
back into the declaration node rather than rebuilt around it — because
import resolution answers a merged list that *shares* declaration nodes
with the entry list the checker also holds. Rebuilding would expand one
view of the program and leave the other unexpanded.

**MAC-EXP-3a (H).** **Every body that can contain an expression MUST
be expanded**, and every one is. Until traits were removed in 0.6.0
there were three such bodies — `fn` bodies, `impl` method expressions,
and trait **default** bodies, `expandDecl`'s three arms — and the rule
existed because the last two lowered into ordinary declarations
*after* the expansion pass (`lowerImpls`), so a macro invoked in
either was never expanded at all: the exact failure `MAC-EXP-1` was
supposed to have eliminated, reached by a different road. That road is
closed with the construct, and `fn` is the only body left, but the
rule is stated rather than deleted because it is about a *class* of
mistake — lowering a body into declarations after the expander has
already run — and the next construct to lower late will meet it
again.

Until 2026-08-14 the pass walked `fn` declarations only, and trait and
`impl` bodies lower into ordinary declarations *after* it
(`lowerImpls`), so a macro invoked in either was never expanded at all
— the exact failure `MAC-EXP-1` was supposed to have eliminated,
surviving in the one place the pass did not reach:

```scheme refused
(macro (dbl x) (+ x x))
(trait (Doubler a) where (dub :: (-> a Int)))
(impl (Doubler Int) where ((dub (lambda (x) (dbl x)))))
(fn (main) (dub 21))
```

The fence says `refused` because that program cannot be written any
more: `trait` and `impl` were removed in 0.6.0 and draw `AX2004`. The
block is kept as written rather than translated, because what it
documents is a defect in *that* syntax and a translation would document
nothing — and `refused` makes the removal a checked claim instead of a
sentence, so this block goes red the day either word is accepted
again.
```
$ axiom check impl2.ax        # before the fix
OK
$ axiom run impl2.ax
opt: ...ll:247:18: error: use of undefined value '@dbl'
E AX4003 <toolchain>:- toolchain-failure "opt failed"
```

`check` and `build` disagreed, and the diagnostic blamed the toolchain
for the compiler's own bug with no span into the source. The fix
expands the two body classes *before* lowering — inside the same pass,
so no pass order moved in `main.ax`, `repl.ax` or `lsp.ax` — and each
expression expands under an empty bound set, since a lambda pushes its
own parameters.

What kept the miscompile silent through the checker was a **residual
macro-head path** in `checkApp`, answering a silent wildcard for any
spine whose head names a visible macro. That arm stays, deliberately,
with its stale "expansion lives in codegen" comment corrected: on the
driver's path an unexpanded macro means expansion already refused and
the process exits before checking (`MAC-EXP-1b`), so the arm exists
for the consumers that keep checking a broken file — the LSP — where
its silence stops a wrong `AX3001` landing on top of the expansion's
own diagnostic. A future body class the pass does not walk would be
hidden by the same silence, which is why this rule's first sentence is
normative rather than descriptive: the commit that adds a fourth body
class **MUST** add the fourth arm.

### 2.2 The algorithm

**MAC-EXP-4 (H).** Expansion of an expression proceeds structurally,
carrying a **bound-name set** — the names bound by every enclosing
binder at that point.

**MAC-EXP-5 (H).** A form is a macro invocation when its spine head is
an identifier that (a) is **not** in the bound set and (b) names a
visible macro. Condition (a) comes first, and is what stops a macro name
from outranking every binder in the program:

```scheme
(macro (v) 9)
(fn (f v) v)      (f 1)          ; 1
(let ((v 2)) v)                  ; 2
```

**MAC-EXP-6 (H).** Instantiating a macro is, in order:

1. **expand each argument** that the macro will consume;
2. **substitute** them into the template, renaming every binder the
   template introduces (`MAC-HYG-1`) and resolving every free identifier
   at the definition site (`MAC-HYG-6`);
3. **expand the result**, so a template that invokes another macro
   expands too.

Steps 1 and 3 make expansion a fixpoint.

Step 1 is where expansion-time and run-time part company, and the
distinction **MUST** be kept:

- **At expansion time**, every argument the invocation supplies is
  expanded exactly once — including one the template never mentions, and
  including a surplus argument beyond the macro's arity. So a macro
  invocation inside an unused argument is still expanded, and still
  subject to `MAC-EXP-9`'s budgets.
- **At run time**, an argument is evaluated once per occurrence of its
  parameter in the template: twice if mentioned twice (`MAC-EXP-7`),
  and **not at all** if the template drops it — the one position
  `MM-EXEC-4` lists where a macro argument goes unevaluated.

**MAC-EXP-7 (H).** An argument is substituted as **syntax**, so a
template that mentions a parameter twice evaluates that argument twice:

```scheme
(macro (twice x) (+ x x))
(twice (readLine))          ; reads twice
```

This is a property of substitution, not a defect, and `MAC-SAFE-1`
specifies what a macro author owes because of it.

**MAC-EXP-8 (H).** Arity is checked in one direction only:

- **too few** arguments is `AX3018`;
- **a longer spine is not an error.** Exactly *arity* arguments feed the
  macro and the surplus is **applied** to whatever the macro produced,
  which is how a macro expanding to a function stays usable. When that
  is wrong it is an ordinary type error: `(macro (one x) x)` invoked as
  `(one 5 6)` is `AX3004 expected function type, found Int`, not
  `AX3018`.

  The diagnostic anchors at the **expansion**, not at the surplus
  argument: measured, `(fn (main) (one 5 6))` reports at columns 17–18,
  which is the `5` the macro expanded to. A conforming implementation
  **SHOULD** anchor it at the surplus argument, which is the token the
  author can delete. That gap is `MAC-EXP-8`'s recorded defect.

Both behaviours replace silent miscompiles: under-application used to
leave the parameter's own name in the emitted IR (`add i64 40, %q`,
rejected by `opt` as an undefined value), and over-application used to
drop the surplus argument **without evaluating it**.

### 2.3 Termination

**MAC-EXP-9 (H).** Expansion **MUST** terminate, and five independent
budgets enforce it. Each replaces a hang or a crash, and each reports
once rather than at every node after the first refusal.

| Budget | Limit | Phase | Diagnostic | What it bounds |
|---|---|---|---|---|
| instantiation depth | 128 | E | `AX3019` `macro-recursion-limit` | a macro that rewrites to itself |
| output tree depth | 1024 | E | `AX3024` `macro-expansion-limit` | nesting the parser would have refused in source |
| output node count | 2,000,000 | E | `AX3024` `macro-expansion-limit` | fan-out, which no depth limit can see |
| declaration rounds | 128 | D | `AX3019` `macro-recursion-limit` | a declaration macro that regenerates its own invocation |
| generated declarations | 10,000 | D | `AX3024` `macro-expansion-limit` | a declaration template that fans out |

The **phase** column is the whole of why the last row exists. The first
three are counted inside `expandExpr`, and `expandProgram` runs phase D
first (`MAC-EXP-16`), so a template that generates declarations reaches
none of them: phase E never starts. The depth axis was covered there
anyway by the round budget, and it fires. The width axis was not, and
what was under it was not a slow compile — a template generating three
invocations of itself per round reached 3.4 GB in one second and was
killed by the operating system, with no diagnostic and no output
(`tests/diagnostics/401-decl-macro-size-limit.ax`, and
`406-decl-macro-round-limit.ax` for the round budget, which until then
was enforced by the compiler and pinned by nothing).

**MAC-EXP-10 (H).** The last two exist because **the parser's own limits
measure the source and expansion produces the program**. A template 500
deep invoked 120 times nests 620 in the file and 60,000 in the tree, and
it is the second number that overflows the stack — measured as a SIGSEGV
of `check`, `run`, `symbols` and `axiom lsp`. Fan-out is worse:
`(macro (m x) (+ x x))` doubles per level, so 26 nested invocations are
154 bytes of source and 2²⁶ nodes; `check` took 41.4 s and the language
server never answered.

Measured today, the same input is refused in 42 ms:

```
E AX3024 macro-expansion-limit "macro expansion produced more than the limit of 2000000 forms"
  !"the parser's own nesting limit measures the SOURCE, and this limit measures what expansion produced from it"
```

**MAC-EXP-11 (H).** `(macro (loopy x) (loopy x))` is `AX3019`. It used
to segfault the compiler in about 10 ms — no output, no diagnostic, and
not even slowly enough to interrupt.

**MAC-EXP-11a (H).** The two output budgets share `AX3024` and are
distinguished by message — *"nested deeper than the limit of 1024
forms"* against *"produced more than the limit of 2000000 forms"*. Both
counters increment for **every node the pass visits**, macro-generated
or not, so they apply to a macro-free program as well. The depth budget
is harmless there — the parser's identical limit catches deep source
first — but the node budget has no parser analogue and is reachable by a
large generated file containing no macros at all. A conforming
implementation **SHOULD** count only expansion-produced nodes, and
**MUST NOT** let the limit's message imply a macro is involved when none
is.

### 2.4 Determinism

**MAC-EXP-12 (H).** Expansion **MUST** be deterministic. The gensym
counter is a per-run monotonic integer — never an address, never a hash
of one — so emitted IR stays byte-identical across runs and
`scripts/check-reproducible.sh` keeps holding.

**MAC-EXP-13 (H).** The expander's counter **MUST** be distinct from the
type checker's. The checker's names type variables `_tN`, those names
are printed inside `AX3004` messages, and the AXDL goldens pin them byte
for byte: a renamed binder must not renumber a type variable.

### 2.5 Spans

**MAC-EXP-14 (H).** Every node a template produces carries the **span of
the invocation**, and every node that came from an argument keeps its
own span.

**MAC-EXP-14a (H, defective).** Four tags are exempt from `MAC-EXP-14`
because they are returned rather than rebuilt: integer, string, float
and char literals. A literal in a template therefore keeps the **defining
file's** byte offsets, which are then rendered against the *invoking*
file's line table — producing a span like `probe.ax:4:375-378` in a
50-byte file. This is the wrong-file anchoring `MAC-EXP-14` exists to
prevent, surviving in the one case where rebuilding looked unnecessary.
A conforming implementation **MUST** rebuild literals with the
invocation's span.

The same question applies to the sub-nodes `MAC-EXP-14b` names, and this
specification answers it the same way: a node that reaches a diagnostic
**MUST** carry a span that indexes the unit the diagnostic is reported
against.

**MAC-EXP-14c (H, prerequisite).** `MAC-EXP-14` says "the span of the
invocation", and for seven node kinds **there is no such span**. A span
is a two-word record of half-open byte offsets into one source text,
carrying no line, no column and no file identity; a node's span is an
**anchor token** — a head, a keyword, a binder name — never the extent
of the form; and `if`, `{}` blocks, `match`, `while`, `cond`, `handle`
and match arms carry **no span at all**.

So a macro invoked in one of those positions has nothing to inherit, and
any rule phrased as "the expansion inherits the span of the form it
replaced" is unimplementable there. A conforming implementation **MUST**
give every node a span before `MAC-DIAG-4` can be honoured, and
**SHOULD** decide at the same time whether a span is an anchor or an
extent — an IDE-facing "select this expansion" feature needs extents,
and that is a change to every construction site in the parser.

**MAC-EXP-14b (H).** Four positions inside otherwise-handled template
forms are **not substituted**, so a macro parameter placed in one is
used as a literal name rather than replaced by its argument:

| Form | Unsubstituted position |
|---|---|
| field access / field store | the field name |
| struct construction | the type name |
| `alloc` | the type operand |
| `handle` | the effect-name list |

This is deliberate — each position is a *name*, not an expression — but
it is silent, and in `alloc`'s case doubly so, because `alloc`'s type
operand is never resolved either (`MM-VAL-21`). A conforming
implementation **SHOULD** diagnose a macro parameter appearing in one of
these positions rather than pass its name through.

The rule is uniform and deliberate. A template node's own span indexes
the file the macro was *defined* in; a `Diag` carries one unit; so a
diagnostic anchored at a template node would point at a real line of the
**wrong file**, which reads as a correct diagnostic about unrelated code
and is worse than pointing nowhere.

**MAC-EXP-15 (H).** A diagnostic from inside an expansion therefore
anchors at the invocation, in the file being compiled — and names the
macro in an expansion frame (`MAC-DIAG-4`, since 2026-08-14):

```
error[AX3001]: undefined variable `noSuchFunction`
 --> probe.ax:3:13
  |
3 | (fn (main) (bad 1))
  |             ^^^ no binding named `noSuchFunction` in scope
  |
 = note: in this expansion of `bad` (MacLib.ax:2:13-16)
```

Until then the note line did not exist, and a reader saw an error about
a name that appears nowhere on the line pointed at.

### 2.6 Phases

**MAC-EXP-16 (H, v1 2026-08-14).** With declaration macros
(`MAC-CAP-8`), expansion is a two-phase pass over the declaration list:

1. **Phase D** — expand declaration-position invocations, appending
   their results to the declaration list, to a fixpoint under the
   budgets of `MAC-EXP-9`. A macro invoked in phase D **MAY** produce
   further declaration invocations
   (`tests/selfhost/372-decl-macro.ax`'s `defPair` generates two);
   the round count is bounded by the depth budget, and a round that
   resolves nothing new terminates the fixpoint.
2. **Phase E** — expand expression-position invocations inside every
   declaration body, exactly as before.

Phase D completes before the declaration list is fixed, because name
resolution, `declNamespace` and the checker all read that list — a
generated fn's body can invoke expression macros, and a later
declaration can call a generated function, order-independently like
everything else at top level (`MAC-LANG-3a`). Phase D runs after
import resolution, so an invocation can name an imported macro
qualified (`QualMac::qmk` in fixture 372) and a generated declaration
can refer to imported names.

*The v1 limit is lifted (2026-08-15).* Phase D expanded **entry-file
invocations only**, and an invocation inside an imported module was
`AX3027` with the reason in the note: generated declarations in a
module would need the module's mangling and visibility applied after
import resolution has already run. Phase D now applies them itself,
from the records that pass built — the bare-to-`Mod$name` mapping, and
a (module, import filter) table import resolution records as it goes.
A generated declaration is therefore indistinguishable from a written
one on the module's side too, which is `MAC-EXP-17` extended by one
namespace.

Three rules decide what leaves the module, and each is the rule a
hand-written declaration already followed:

- **The template's own `pub`** decides whether the product is
  exported. It is the only signal available — an invocation cannot
  carry `pub` — and it is the right one: a library that derives says
  what it publishes, exactly as it does for the functions it writes.
  `stdlib/Pre.ax`'s templates say `pub`; a module-local `derive` that
  omits it keeps its products to itself, and the module's own calls to
  them still work, because privacy is about what leaves a module and
  not about what the module may do.
- **The import's name list** applies to a generated name as it does to
  a written one. It cannot be applied where it is applied to
  everything else — the name does not exist yet when the module's
  declarations land — so import resolution records the filter against
  the module and phase D asks for it. `(import M (a))` beside a
  generated `pub b` is `AX3023` on `b`.
- **The query vocabulary answers from the invocation site.** A module
  deriving over its own type asks about a name its neighbours can see,
  whatever an importer's name list says. Reading the rule as
  "entry-file visible" made a module's own `pub data` refuse inside
  the module that declared it the moment an importer's name list did
  not mention it, which is the kind of coupling a module system exists
  to prevent.

The two passes share one implementation of those rules, in a module of
its own: `codegen.ax` imports `expand.ax`, so the mangling and filter
helpers could live in neither, and duplicating them is the failure
this repository keeps finding — two implementations of one rule that
drift. `self_host/namespace.ax` holds them, and the compiler's
own self-clean sweep is what forced the split: with the helpers left
in `codegen.ax`, `expand.ax` compiled as part of the whole program and
drew three `AX3001`s the moment anything checked it alone.

What still refuses: a pipeline that re-expands an already-resolved
program (codegen's re-expansion, the REPL's type probe) carries no
mangling records, and a module-side invocation reaching it is
`AX3027` naming that rather than generating a declaration nothing can
name. `tests/selfhost/388-module-side-decl-macro.ax` (239) is the
positive gate — the prelude's `deriveEq` and `deriveArity` spent by a
module on its own type, a private product the module calls, and an
entry-file `eqSignal` coexisting with the module's mangled one — and
`tests/diagnostics/515-decl-macro-in-module.ax` pins the visibility
refusal.

**MAC-EXP-17 (H, v1 2026-08-14).** A declaration a macro generates is
indistinguishable, to every later pass, from one the author wrote: the
checker types it, the duplicate-definition check sees it (a fixed-name
template invoked twice is `AX3006` on the second generated
declaration), codegen emits it, and a generated signature's per-arrow
float flags are **recomputed from the substituted type** rather than
copied from the template's tokens
(`tests/selfhost/373-decl-macro-types.ax`: `(defT idFloat Float)`
really is float-typed end to end — the type-alias slice's measured
defect class, not repeated here).

---

## 3. Hygiene

Hygiene has two directions, and Axiom's differ in status.

### 3.1 Binders a template introduces

**MAC-HYG-1 (H).** **A binder introduced by a template MUST NOT capture
a name from the call site.** Both places a template can introduce one
are covered:

```scheme
(macro (addTo x) (let ((tmp 100)) (+ tmp x)))
(let ((tmp 1)) (addTo tmp))          ; 101   (was 200)

(macro (orElse o d) (match o ((Some v) d) ((None) d)))
(let ((v 42)) (orElse (Some 8) v))   ; 42    (was 8)
```

**MAC-HYG-2 (H).** The mechanism is **renaming**. At each expansion
every binder the template introduces — `let`, `let mut`, `lambda`
parameters, `match` arm pattern binders — is renamed, and every
reference to it inside the template is renamed with it.

**MAC-HYG-3 (H).** The fresh name is `<name>.<counter>`, and the shape
makes collision **impossible rather than unlikely**, on both sides:

- `.` is `TK_DOT` to the lexer and never an identifier character, so no
  Axiom source can spell `tmp.1` as one identifier — measured:
  `(let ((tmp.1 5)) tmp.1)` is `AX2001`;
- `.` *is* legal in an unquoted LLVM identifier, so the renamed binder
  survives codegen's register naming with nothing to escape — measured:
  `llc` accepts `%tmp.1`.

**MAC-HYG-3a (H, defective).** The property that makes `MAC-HYG-3` sound
— that a renamed binder cannot be spelled in source — makes it unusable
in a diagnostic, and it reaches one anyway:

```scheme refused
(macro (m x) (let ((tmpvar x)) (+ tmpvarr 1)))    ; note the typo
(fn (main) (m 5))
```
```
E AX3001 leak.ax:2:13-14 undefined-variable "undefined variable `tmpvarr`"
  #"no binding named `tmpvarr` in scope"
  ?2:13-14:"a similarly named binding `tmpvar.0` is in scope; did you mean this?"~>"tmpvar.0"
```

The suggestion is **machine-applicable**: the `~>` field offers
`tmpvar.0` as a replacement, and a tool that applies it writes a token
the lexer refuses (`AX2001`). The span is the invocation's, so the edit
would also land in the wrong file's text.

A conforming implementation **MUST** render a renamed binder under its
original spelling in every diagnostic, and **MUST NOT** emit one inside
a `~>` replacement — the general form of which is `MAC-TOOL-5`, and
the `~>` half of it holds since 2026-08-15: a diagnostic carrying an
expansion frame loses its machine-applicable replacements. What
remains defective here is the *rendering* — the message still quotes
`tmpvar.0` rather than `tmpvar`.

**MAC-HYG-4 (H).** Nodes are **rebuilt**, never mutated. Returning a
template's own node would make one node reachable from every call site,
which is safe only as long as nothing writes to a node — and renaming
writes.

### 3.2 Pattern position

**MAC-HYG-5 (H).** Three bare names in pattern position are **not**
binders and **MUST NOT** be renamed: `true`, `false` and `_`.

`true` and `false` are literal *tests* — the emitter compares the
scrutinee against 1 and 0, and the checker binds nothing — so renaming
one to `true.1` turns the test into a binder, the arm matches
everything, and every later arm becomes unreachable:

```scheme
(macro (isTrue b) (match b ((true) 1) ((false) 0)))
(isTrue false)                          ; 0   (was 1)
(match false ((true) 1) ((false) 0))    ; 0   unchanged
```

The same `match`, written by hand and written by a macro, disagreeing —
a silent wrong answer, and precisely the failure hygiene exists to
prevent.

**Nothing else is exempt.** A bare constructor name in pattern position
*is* a binder in this language — which is why `(Nil)` needs its
parentheses — so renaming it is correct, and the existing hygiene cases
depend on it. A constructor spine's head is walked past rather than
renamed, and a named-field pattern's field names are the struct's, not
binders.

### 3.3 Free identifiers in a template

**MAC-HYG-6 (H).** **A free identifier in a template means what it meant
where the macro was written.** This is the reverse direction, and it
used to fail in a way that made one macro mean two things:

| Call site | Was | Is |
|---|---|---|
| an entry file that defines its own `helper` | 6 — the *entry's* | 50 — the macro module's |
| a function inside the macro's module | 50 | 50 — unchanged |
| under a caller's `(let ((helper 0)) ...)` | `AX3004 expected function type, found Int` | 50 — the local cannot capture it |

Same macro, same template, two answers, chosen by the caller's module —
and neither compiler diagnosed it, because both were resolving a name
that really was in scope.

**MAC-HYG-7 (H).** The mechanism costs nothing outside the expander.
Import resolution already mangles an imported `fn`/`::` declaration's
name to `Mod$name`, so the definition-site name a free identifier should
resolve to **already exists as a declaration name**; rewriting the
reference to it is enough. The rewrite is **conditional on `Mod$name`
really being a declaration**, which is what keeps it from touching a
reference to `+`, to a constructor (constructors are not mangled), or to
a name the macro's module merely imported — each finds nothing and stays
bare, resolving outward exactly as before.

### 3.4 The four holes hygiene had, and what each cost

**MAC-HYG-8 (H; all four closed, the last two on 2026-08-16).** These
four holes **SHALL** close, and all four have. Each is kept with what
it cost while it was open, because what a hole cost is the argument
for the mechanism that closed it:

1. **A macro defined in the entry file** — **closed 2026-08-16.**
   Entry-file declarations are left bare by import resolution — there
   is no `Mod$name` to resolve to — so a caller's local binding
   captured a template's free identifier, and **measured, that was a
   silent wrong answer**: an entry-file `(macro
   (useHelper v) (helper v))` invoked under `(let ((helper (lambda (y)
   0))) …)` answered **0** where the macro's own `helper` answers 40,
   at exit 0, with no diagnostic from any pass. From 2026-08-15 it
   refused (`AX3032`), which was loud but rejected a correct program.

   **It resolves now, and not by the mechanism this rule predicted.**
   `MAC-HYG-9` says the fix is scope sets, an identifier becoming a
   `(name, scopes)` pair — a change to what an identifier *is*. This
   case needs one bit of that and no representation change: a macro is
   a **top-level declaration**, so a template's free identifiers had
   no enclosing local scope where they were written, and every one of
   them means something top level. `substTpl` stamps each with
   `setNodeDefScope` (node word 10, appended) and both resolvers skip
   the local scope for a stamped reference — `checkVar`, and
   `emitVar` through `dispatchCall`.

   **Both, and that is the part worth recording.** With only the
   checker taught, the program type-checked against the macro's
   `helper` and the emitter still called the local: a checker typing
   one binding while the emitter reads another. The head of a call is
   the one reference that never passes through `emitVar`, which is why
   `dispatchCall` had to carry the bit too.

   A template's own binders must NOT be stamped, and the corpus said
   so: a generated function's PARAMETERS reach the same arm — they are
   not gensym-renamed, because a fresh function has nothing to be
   protected from — and stamping them made
   `tests/selfhost/372-decl-macro.ax` `AX3001 undefined variable x`.
   They are bound by an env scope of their own for the length of the
   body's substitution.

   Pinned by `tests/selfhost/394-macro-entry-capture.ax` (130), which
   is the old refusal fixture measuring the answer instead.
   **`AX3032` is retired**: it would now reject correct programs, so
   it is deleted rather than left unreachable, and it is out of the
   registry — `explain` no longer answers it. The number is never
   reused, which is the standing rule for a code whether retired or
   live.
2. **Qualified reference to a macro** — **closed**: `MAC-LANG-12`
   holds, by splitting the reference rather than mangling the
   declarations.
3. **An imported macro outranks an entry-file function of the same
   name** — **closed**: a bare invocation whose name a bare `fn`/`::`
   declares resolves to the function, mirroring `findFnEnt`'s
   entry-file resolution, unless the macro belongs to the invocation
   site's own module; the macro stays reachable by qualification.
   Pinned by `tests/selfhost/369-macro-vs-function.ax` (15; the
   unfixed compiler answers 10). The old behaviour was loud only when
   the arities disagreed — `AX3018 macro `when` takes 2 arguments, but
   was given 1`, a diagnostic about the wrong thing — and **silent**
   when they agreed, which is the measured 10: the macro's answer, no
   diagnostic from anything. Within one file the collision was always
   caught (`MAC-LANG-8`); now the import boundary resolves instead of
   ambushing.
4. **A free identifier naming something the macro's module merely
   imported** — **closed 2026-08-16.** `MAC-HYG-7`'s rewrite tries
   exactly one spelling, `Mod$n` for the macro's *own* module, so a
   template calling a function its module imported found no such
   declaration, stayed bare, and was captured by the caller — the same
   one-macro-two-meanings failure `MAC-HYG-6` closed, in the case
   `MAC-HYG-6` does not reach.

   **The blocker this rule recorded was wrong, and the correction is
   the whole of the fix.** It said closing the hole needs import
   *edges*, which the merge consumes — `resolveDeclsPhase` reads each
   `(import ...)` and pushes nothing into the merged list — and
   concluded that which modules the macro's module imported is not
   recoverable after resolution. That is true and it does not matter.
   Every merged declaration carries the module it came from
   (`nodeModule`), so *which module declares this name* is answerable
   from the list itself, without any edge. `expQualify` therefore
   falls back, when `Mod$n` is not a declaration, to the unique
   `pub` declaration whose bare name is `n`, and rewrites to that.

   **Unique, or nothing.** Two modules declaring the name is
   `AX3014`'s ambiguity by another name, and this rewrite has no more
   right to choose between them than a bare reference does — so it
   leaves the name alone, and the invocation reports `AX3014` carrying
   the expansion frame that names the macro. The soundness argument
   for taking the unique one is that a template naming something its
   module could not see would not have compiled where it was written;
   the rewrite is choosing among modules the macro's module reached,
   not searching the world.

   Pinned by `tests/selfhost/391-macro-imported-name.ax` (31) over the
   modules `LibImp`, `HelpImp`, `MidImp` and `DeepImp`. Two of its five
   bits are the hole (a local at the invocation, and the unshadowed
   two-meanings case) and three are controls, including the one that
   matters for precedence: a name the macro's module declares *and*
   imports resolves to its own, because the one spelling is still tried
   before the search. The search reaches two import edges, which is the
   evidence that what it walks is the merged list and not a
   direct-import list. The compiler before the commit refuses the file
   — with `AX3032`, the capture refusal that item 1 above records as
   retired the following day; with that one term removed so the
   refusal cannot mask the rest, it answers **13 against 31**.

**MAC-HYG-9 (P).** The mechanism **SHALL** become **scope sets**: an
identifier is a `(name, scopes)` pair rather than a bare name, every
expansion introduces a fresh scope, and resolution matches on both.

Renaming is a sound implementation of the *forward* direction and
nothing more. Scope sets are required by `MAC-LANG-17` (a literal
identifier must be comparable *as a binding*) and by any
nested-pattern macro where one expansion's binder must be visible to
another's template.

**`MAC-HYG-8`'s first hole was on that list and came off it on
2026-08-16**, which narrows what remains. The hole was stated as "an
entry-file macro has no mangled name to resolve to, but it does have a
definition scope", and the second clause turned out to be the whole
fix: a macro is a top-level declaration, so its template's free
identifiers have exactly ONE definition scope, the top level, and one
bit on the reference says so. No `(name, scopes)` pair and no change
to what an identifier is. See `MAC-HYG-8`.1.

**MAC-HYG-10 (H, 2026-08-16).** A binder position holding a macro
**PARAMETER** takes the **argument's** name and **MUST NOT** be
renamed. A binder the *template* introduces is renamed as `MAC-HYG-1`
says; these are opposite cases and the distinction is which side named
the binding.

Renaming both is what made **every binding form impossible**, and the
rule exists because that went unnoticed for as long as it did:

```scheme
(macro (bind! x e body) (let ((x e)) body))
(bind! v 41 (+ v 1))
; before: AX3001 undefined variable `v`
; after:  42
```

`x` was gensymed to `x.N` and `body` — arriving through a *different*
parameter — was spliced verbatim, so the expansion bound one name and
read another. The defect hid behind the case that happens to work:
when a template binds and reads through the **same** parameter,
`(macro (m x e) (let ((x e)) x))`, the rename table maps the template's
`x` to the gensym on both sides and the answer is right for the wrong
reason, with the caller's chosen name appearing nowhere in the output.
Only a macro taking a separate body could see it, and until this rule
none existed — `stdlib/Pre.ax`'s macros are all single-expression
templates.

The rule is `substName`'s, which has been right about `set` targets
since it was written: a parameter in a name position answers the
argument's name, and an argument that is not a name is refused. That
refusal is **`AX3035`** (`macro-binder-target`) — `(bind! (f 1) 41 7)`
has nothing to bind, and before the rule it *silently expanded*,
binding a gensym nobody could reference and discarding the argument.

All three binder positions the expander owns follow it: `let`/`let mut`
binders, `lambda` parameters, and match-arm pattern binders
(`expBinderParam`, `self_host/expand.ax`). Nothing is pushed onto the
rename stack for such a binder — a reference to the parameter elsewhere
in the template already substitutes to the same identifier through the
ordinary parameter path, so a rename entry would be a second route to
one answer.

The reverse half is unaffected and is `MAC-HYG-8`'s: a template's free
identifier that the caller's binder happens to shadow still resolves at
the definition site, so `(bind! helper 1 ...)` does not steal the
template's own `helper`.

`tests/diagnostics/590-macro-binder-target.ax` pins the refusal in both
positions; `tests/stdlib/371-err-module.ax` is the first program that
depends on the rule, and does not compile without it. This is what
made a propagation form writable, and `docs/error-model.md`
`ERR-SUGAR-2` is the form.

So this rule is now required by **one** thing — `MAC-LANG-17` — and a
conforming implementation should read it as scoped to that. A literal
identifier is compared by BINDING, and comparing bindings needs both
sides to carry theirs; the entry-file hole only needed one side to
carry that it had none.

**The migration MUST preserve every case gated today.** Concretely, a
conforming implementation replacing renaming with scope sets **MUST**
keep `tests/selfhost/361-macro-hygiene.ax` (143),
`362-macro-coverage.ax` (57), `363-macro-shadowing.ax` (3),
`364-macro-definition-site.ax` (157) and `365-macro-pattern-literal.ax`
(95) answering exactly those values, and **MUST NOT** change the emitted
IR's determinism (`MAC-EXP-12`).

---

## 4. Capabilities

### 4.1 What substitution already gives

**MAC-CAP-1 (H).** Every form a template can contain has a substitution
case: application, `if`, `cond`, `match` and its arms, `let`, `let mut`,
`set`, `while`, field access, field store, struct construction, lambda,
block, `alloc`, `handle`, and every literal. Lists and tuples need no
case, because `[T]` and tuple types are *type* nodes — a list-shaped
value is a constructor application (`MM-VAL-13`).

**MAC-CAP-2 (H).** **The default arm MUST refuse.** A template form the
substituter does not know is `AX3021 macro-template-unsupported`, never
passed through unchanged.

This rule is the whole lesson of the pass. The default arm used to
return the node *unchanged*, and that single decision was **eight
separate silent miscompiles**: `let mut`, `set`, `while`, field access,
field store, struct construction, `alloc` and `handle` each survived
into the generated code carrying the *template's* own identifiers, all
eight surfacing as `AX4003 opt failed` against `<toolchain>` — the
compiler blaming the toolchain for its own bug, with no span into the
source.

`AX3021` has **no reachable producer today**, and that is the point: it
exists so that the ninth form — the next one added to the language —
becomes a diagnostic in the commit that adds it, instead of a silent
miscompile.

**MAC-CAP-3 (H).** A macro parameter used as the target of a `set` is
`AX3022 macro-set-target` when the argument is an expression rather than
a name.

**MAC-CAP-3a (H).** `AX3022` **does not poison its expansion**: the
substituter reports it and then emits the *parameter's own name* into
the generated tree. Only the driver's error gate keeps that tree away
from codegen, so any consumer that renders diagnostics without exiting —
an incremental path, the language server — would emit a template
identifier into IR. A conforming implementation **MUST** replace the
node with a poison value, as every other refusal in the pass does.

### 4.2 Pattern matching on syntax

**MAC-CAP-4 (P; two of the four dispatch axes landed 2026-08-16).** With
`MAC-LANG-14`–`MAC-LANG-18`, a macro **SHALL** be able to dispatch on
the *shape* of its arguments: arity, literal heads, nesting, and
repetition. This is what turns the current facility from
*substitution* into *pattern-based rewriting*, which is what
the roadmap's §4.2 means by tier 1.

**Arity** and **nesting** hold (`MAC-LANG-15`, `MAC-LANG-18`), and so
does dispatch on a literal argument's VALUE, which this list did not
separate out. **Repetition** followed on 2026-08-16 (`MAC-LANG-16` v1). **Literal
heads** need `MAC-LANG-17`, which needs `MAC-HYG-9`'s scope sets — the
one axis of the four still blocked, and blocked on something named
rather than on effort.

### 4.3 Compile-time evaluation

**MAC-CAP-5 (R, with a replacement — v1 of the replacement landed
2026-08-14).** Compile-time evaluation of **user code** is refused
(`MAC-LANG-13`). What replaces it is a **closed, compiler-implemented
query vocabulary** evaluated by the expander over the declaration list
it already holds:

| Query | Status | Answers | Needed by |
|---|---|---|---|
| `(syntax/constructors T)` | **H** (any type an entry-file reference could name — a private one refuses; as a `syntax/for` sequence) | the constructor names of `data` type `T`, in declaration order | `derive` for any sum |
| `(syntax/arity C)` | **H** (2026-08-15; same declaration slot `syntax/binders` counts, same two refusals) | the field count of constructor `C`, as an integer literal | `stdlib/Pre.ax`'s `deriveArity` — a value's field count is not recoverable at run time, since a block records its tag and never its arity (`memory-model.md` MM-VAL-6) |
| `(syntax/fields S)` | **H** (any struct an entry-file reference could name — a private one refuses; as a `syntax/for` sequence) | the field names of `struct` `S`, in declaration order | lenses, `Eq`, serializers |
| `(syntax/name x)` | **H** (2026-08-15) | the identifier `x` as a string literal | `stdlib/Pre.ax`'s `deriveShow` — a constructor's SPELLING reaches a running program no other way, since a tag is an integer at run time |
| `(syntax/join a b)` | **H** (declaration NAME position; **since 2026-08-15** also as a REFERENCE to what such a name declares — `((syntax/join show T) x)` calls `showColor` — and as another query's argument, which is what lets `syntax/defined` ask about a name no source spells; **either side may be a join of its own since 2026-08-15**, so a name carries more than two parts) | one identifier from two, the second's first letter upcased (`lens` + `Point` → `lensPoint`, `eq` + `Color` → `eqColor`); nested, `(syntax/join (syntax/join get S) f)` is `getPointX` | naming generated declarations, and calling them |
| `(syntax/defined n)` | **H** (2026-08-15; an `if` whose condition is one is decided at expansion time and the CHOSEN BRANCH spliced, exactly as for `syntax/same`) | whether `n` names a visible declaration — a `fn`/`::`, a `data`/`struct`, or a constructor: exactly the names a generated body could refer to | `stdlib/Pre.ax`'s `showOr`. The folding is not a nicety here but the rule that makes the query useful: the losing branch names a declaration the program does not have, so a runtime `if` over both arms would be `AX3001` in every program that did not derive |
| `(syntax/same a b)` | **H** (both sides must be iteration variables over the SAME sequence; different sequences refuse rather than answer false) | whether `a` and `b` are the same **binding or declaration slot** — two answers naming field `f` of `S` compare equal, spelling alone never suffices; `MAC-LANG-17`'s binding comparison is the pattern-side instance. An `if` whose condition is a `syntax/same` is decided at expansion time and the CHOSEN BRANCH spliced, which is what makes §10.3's expansion shapes literal | `deriveLenses`' diagonal (§10.3) |
| `(syntax/binders C p)` | **H** (spelled `p#i` — deterministic, which is what "same sequence at every mention" requires, and `#` cannot lex in a user identifier; a pattern mention splices them as binders `MAC-HYG-2` renames, and later mentions land on the same renamed binders through the rename table) | arity-of-`C` fresh identifiers derived from prefix `p` — the *same* sequence at every mention within one expansion, each a template binder that `MAC-HYG-2` renames | fieldful `derive` (§10.2) |
| `(syntax/for ((x xs) …) tpl)` | **H** (match-ARM, template-DECLARATION and call-ARGUMENT positions; the for-variable substitutes in constructor patterns, field-name positions and name positions, and nested iterations compose. **The parallel form landed 2026-08-15** in all three positions, sharing one binding-form normaliser with `syntax/fold`; nested DECLARATION iteration can name its products since the same day, because `syntax/join` nests) | `tpl` once per element, spliced in place; several sequences zip in lockstep and **MUST** have equal length — a mismatch is `AX3028` at the `syntax/for` that wrote it, never a truncation to the shorter | the iteration form |
| `(syntax/fold f z ((x xs) …) tpl)` | **H** (single and parallel forms; parallel sequences must have equal length — a mismatch is `AX3028`, never a truncation; the empty fold answers `z`, which is how a nullary constructor's equality costs no special case) | the right-fold `(f tpl₁ (f tpl₂ … z))` — `tpl` instantiated per element and nested under a two-argument head, since `&&` takes exactly two | chaining `&&` over field comparisons |

Two rows were RESPELLED on 2026-08-14, when implementation reached
them: this table wrote `syntax/defined?` and `syntax/same?`, and `?`
is deliberately not an identifier character in the lexer
(`lexer.ax`'s own comment reserves admitting it as a separate language
change), so the specified spellings could not lex. A spec whose
spelling the lexer refuses is wrong the moment someone types it; the
`?`-free names are the specification now.

**The three SCALAR rows landed 2026-08-15, each with the library macro
that needs it** — which is `MAC-CAP-6`'s closure rule read literally,
since a vocabulary entry with no consumer is one nothing measures.
`stdlib/Pre.ax` grew `deriveShow` (`syntax/name`), `deriveArity`
(`syntax/arity`) and `showOr` (`syntax/defined`), and the composition
those three needed — a join standing as a reference, so a macro can
CALL what it names and not only name it — landed with them.
`tests/selfhost/380-syntax-scalar-queries.ax` (41) is the gate;
`tests/diagnostics/560-syntax-scalar-misuse.ax` pins the four
refusals.

One clarification the third row forces, and this specification states
it rather than leaving it to be inferred: `MAC-CAP-6` says a query
with no answer is a diagnostic and never a default value, and
`syntax/defined`'s `false` is **not** a default — it is the answer to
a predicate, the same way `syntax/same`'s `false` is. What refuses is
a malformed argument: a subject that is neither a bare identifier nor
a `(syntax/join a b)`.

The v1 rows are pinned by `tests/selfhost/374-derive-eq.ax` (101 —
§10.2's nullary `deriveEq`, the roadmap's acceptance criterion,
verbatim), `375-derive-lenses.ax` (34 — §10.3 verbatim, same day,
one commit later), `376-syntax-nested-for.ax` (7 — nested iteration
over two types), and `tests/frontend/070-derive-macro.ax` (42,
through every frontend consumer). A generated declaration whose name
came from `syntax/join` has **no source spelling**, so it records no
span and `axiom symbols` reports it positionless rather than claiming
bytes that spell something else.

`syntax/for` is the rule form's binding syntax and is unrelated to the
expression keyword `for` of 2026-09-03, which is a loop over values
at run time and not over declarations at expansion time. `syntax/for` and `syntax/fold` are the only constructs that turn a
query's *sequence* answer into repeated output, and both are bounded by
the length of that sequence — which is a property of the program's
declarations, not of anything a macro computes. That is what keeps
`MAC-EXP-9`'s budgets a backstop rather than the primary termination
argument. (`syntax/for`'s one-sequence form `(syntax/for (x xs) tpl)`
is the common case and reads as before; the parenthesised-pairs form is
what the fieldful examples need.)

**The two forms the previous revision of this section listed as
remaining both landed on 2026-08-15**, and each is the same shape as
the rule it generalises rather than a new mechanism:

- **Parallel `syntax/for`.** One normaliser now answers the binding
  form for `for` and `fold` alike — `(x xs)` is the application
  `APP(VAR x, xs)`, and `((x xs) (y ys))` is an application whose head
  is that application, so both arities are one grammar. The parser
  stores the whole binding form and keeps the first binder in the
  node's name slot for diagnostics; the three splice sites push every
  parallel binding for an element together and pop them together, so a
  template sees the whole zipped tuple. Its consumer is the shape a
  zip is *for*: converting one enumeration into a parallel one, where
  a hand-written version repeats the pairing and a repeated pairing
  drifts (`tests/selfhost/386-syntax-parallel-for.ax`, 63).
- **Nested `syntax/join`.** The marker string the parser writes into a
  declaration's name slot was already unambiguous for nesting — it is
  prefix notation over a fixed arity — and what limited a name to two
  parts was the READER, which split on the first space. What the third
  part buys is measured rather than asserted: with two parts, a lens
  set over two structs that share a field name generates `getX` twice
  and the program is `AX3006 duplicate definition`, so the derived
  accessor was unusable for the case a `derive` exists to serve
  (`tests/selfhost/387-syntax-nested-join.ax`, 47).

**MAC-CAP-6 (H, 2026-08-14).** The vocabulary **MUST** be closed. Every
entry **MUST** be total, terminating, and a pure function of the
declaration list; adding one is a language change with a diagnostic, a
gate and a line in this table. A query with no answer — a `syntax/`
head the vocabulary does not implement, `syntax/constructors` of a
struct or of nothing — is a diagnostic, never a default value.

The closure is enforced, with one code for the family: **`AX3028`**
(`syntax-query`), covering unknown heads, wrong positions, subjects
with nothing to answer, queries written outside a macro template, and
the reservation below (`tests/diagnostics/520-syntax-query-misuse.ax`,
`525-syntax-reserved.axbad`; `axiom explain AX3028` is the catalogue).
The `syntax/` prefix is **reserved in declaration names** — the
near-miss `(fn (syntax/join a b) body)`, one paren short of a joined
name, would otherwise silently declare a function called `syntax/join`
taking `a` and `b` — and in the arm and name positions the vocabulary
owns. Corpus population of `syntax/`-prefixed identifiers when the
reservation landed: zero, measured.

This is the boundary the design turns on. Reading the declaration table
is not evaluation: it terminates, it runs no user code, and its answers
are already in the compiler's hands. An expander that instead *ran* a
user function to compute a field list would be tier 2 arriving through
the back door, which `MAC-LANG-13` forbids.

### 4.4 Type-level macros

**MAC-CAP-7 (H, 2026-08-15).** "Type-level macro" in Axiom means **a macro that
generates type and instance declarations**, keyed on declared types via
`MAC-CAP-5`. It does **not** mean type-level computation, and cannot:
Axiom's type system has parametric polymorphism and aliases, and no
type-level functions, no higher-kinded abstraction over them, and no
dependency of types on values. A macro cannot inspect an *inferred*
type at all, because expansion precedes inference (`MAC-EXP-1`).

It **holds** since 2026-08-15, when `data` and `struct` joined
`MAC-CAP-8`'s template surface, which then also carried `impl`: the
declaration kinds this rule is about are all generable now — and since
0.6.0 an instance is an ordinary value, so the `fn` that builds a
capability record is generated by the kind that was there first. Also
`tests/selfhost/381-macro-type-templates.ax` derives equality over a
type a macro invented. What the rule denies is unchanged and is the
half worth reading — the sentences below are what "type-level" does
*not* buy here.

The measured position is stronger than "no type-level functions": the
type grammar is purely structural — pointer, `linear`, keyword, type
variable, application, tuple, list, arrow — with **no** const generics,
no type-level literals, no associated types, no constraints and no kind
system. Higher-kinded types are absent for a syntactic reason worth
knowing: type application requires an uppercase head, and a lowercase
head in the same position parses as a **tuple**, so `(f Int)` is the
pair `(f, Int)` rather than `f` applied to `Int`.

Macros are also expression-position only in the strict sense: a macro
invocation in **type** position is `AX3002`, not an expansion.

A conforming implementation **MUST NOT** paper over this by running
expansion after the checker for some macros and before it for others:
that would make the pipeline position — and therefore whether generated
code is checked — depend on which macro was used.

### 4.5 Declaration macros and `derive`

**MAC-CAP-8 (H, v1 2026-08-14).** A macro is invocable in declaration
position, producing one or more declarations, under the phase rules of
`MAC-EXP-16`. The declaration form is the **rule form** — one rule,
whose pattern head must repeat the macro's name — and **everything
after the pattern is the template**, each form in it one generated
declaration:

```scheme
(pub macro deriveThing
  ((deriveThing T)                       ; pattern
   (:: ...)                              ; declaration 1
   (fn ...)))                            ; declaration 2
```

The v1 surface, all of it measured
(`tests/selfhost/372-decl-macro.ax` = 144,
`tests/selfhost/373-decl-macro-types.ax` = 10):

- **Templates generate `fn`, `::`, `data`, `struct`, `type` and
  `effect` declarations, further macro invocations**
  (resolved by the next fixpoint round), **and `syntax/for`
  iterations over them** (`impl` joined the surface with the iteration
  form and left it with the construct in 0.6.0; `data` and `struct` on
  2026-08-15, which is what
  makes `MAC-CAP-7` real — `tests/selfhost/381-macro-type-templates.ax`,
  32; `type` and `effect` the same day —
  `tests/selfhost/389-type-effect-templates.ax`, 38). What still
  refuses is refused by DECISION rather than schedule: an `import`
  template would reopen resolution ordering, which has already run
  when phase D starts, and a nested `macro` template would add to the
  table the same fixpoint is reading. (`trait` and `impl` refuse one
  layer earlier — a template position does not parse either word at
  all.)

  The two late kinds each needed their name to go through
  `parseDeclName`, as the type kinds did, and one thing more that the
  earlier kinds never asked for: **a joined name has to be writable in
  TYPE position**, because the signature beside a generated alias is
  the first thing that wants to name it. It had no parse there — a
  type application needs an uppercase head, so `(syntax/join nm
  Handle)` fell into the tuple branch, and a generated signature took
  a three-tuple where its alias belonged. The failure surfaced at the
  CALL SITE as `expected Int, found (_a, {unknown}, {unknown})`,
  which is the shape of every defect this document keeps a list of:
  well-typed nonsense reported far from its cause. A constructor's
  name is a name position like any other, so `(syntax/join Off N)`
  names one, and two invocations of one macro therefore generate two
  distinct types. A generated type is queryable in the **same** phase-D
  round that generated it: `(deriveEq Mode)` reads
  `syntax/constructors` off a `data` that `(defFlag Mode)` appended
  moments earlier, because generated declarations join the merged
  list the queries read.

  The remaining kinds — an `import` template and a nested `macro` —
  are `AX3021` **at the macro's own line**, before any invocation
  exists (`MAC-SAFE-4`'s loud-at-definition shape;
  `tests/diagnostics/510-decl-macro-template-kind.ax`,
  `565-macro-type-template-limits.axbad`). `type` and `effect` joined
  the template surface on 2026-08-15 and do not refuse at all —
  `tests/selfhost/389-type-effect-templates.ax` (38) is where a macro
  generates an alias and an effect declaration and names both from its
  arguments. Both survivors are refusals
  by **decision** rather than by schedule, and this specification says
  so rather than leaving them on a list: an `import` inside a template
  would reopen module resolution, which has already run when phase D
  starts, and a nested `macro` would reopen the fixpoint that is
  expanding it. A `trait` or `impl` template does not even reach
  `AX3021`: since 0.6.0 the word is `AX2004` at the parser, measured
  2026-08-31 on a template holding each, which is a fact about a
  different layer.
- **A parameter substitutes in name position, type position and
  expression position.** A name position — a generated declaration's
  head, a fn's parameter list, a nested invocation's head — requires
  the argument to be a **bare identifier** (`AX3027` otherwise): a
  generated declaration's name has to be spellable. A type position
  recomputes the signature's per-arrow float flags from the
  substituted type (`MAC-EXP-17`). An expression position substitutes
  through the expression machinery, so hygiene, spans and the
  definition-site rule are `MAC-HYG-*`'s, unchanged.
- **Same table, same visibility, same qualified-name split** as
  expression macros: a `pub macro` in a module is invocable as
  `Mod::name` from the entry file (fixture 372's `QualMac::qmk`), a
  private one is not, and the fn-wins veto (`MAC-HYG-8` item 3)
  applies.
- **Arity is exact.** Declaration position has no "surplus applies to
  the result" story — the result is declarations, not a value — so a
  count mismatch is the arity diagnostic, not a partial application.
- **Invocation works on both sides** since 2026-08-15: the entry
  file's, and a module's own over its own declarations. What the
  template says `pub` about is what leaves the module, and the
  import's name list applies to a generated name as it does to a
  written one (`MAC-EXP-16`,
  `tests/selfhost/388-module-side-decl-macro.ax`,
  `tests/diagnostics/515-decl-macro-in-module.ax`).

Diagnostic: `AX3027` (`declaration-macro`) covers every way a
declaration-position invocation fails — see `axiom explain AX3027`.
What `derive` still needs from this rule is `data`/`struct` field
*inspection* (`MAC-CAP-5`/`MAC-CAP-6`), which now exists. The `impl`
template kind joined the surface the same day and left it with the
construct in 0.6.0; a derived comparison is a plain function now, and
composes by being called by name.

**MAC-CAP-9 (H, 2026-08-14).** `derive` is built on `MAC-CAP-8` and
`MAC-CAP-5`, not on a compiler-internal deriving mechanism — the
worked `deriveEq`s of §10.2 are ordinary macros in ordinary source.

**The spelling is settled and enforced: explicit invocation.**
`derive` is a library of declaration macros — `(deriveEq T)`, written
where the author wants the instance — and the `deriving` clause is
**refused** (`AX2004`, with the replacement named in the help) rather
than implemented. It had parsed and been silently discarded from the
day it was written: its names never reached the AST, no instance was
ever derived, and a program carrying one checked `OK` — the
documented-but-inert failure class, and refusal is the smallest true
behaviour. The costs decided it. Threading `deriving`'s names into the
AST touches the parser, the node layout, AXSYM and the formatter, while
the explicit call needs only `MAC-CAP-8`; and the clause's corpus
population was **one file pair** — `tests/fmt/syntax-zoo.ax` and its
expected output, written deliberately by someone reading the parser to
pin the formatter's spelling of a clause the compiler ignored. The
refusal flipped exactly that fixture and `reference.md`'s Deriving
example — the blast radius this paragraph counted before the
commit landed, and nothing else. The formatter refuses WITH the parser
(a `deriving` clause poisons the output rather than being rewritten),
because a formatter that accepts what `check` refuses is the
`MAC-TOOL-6` defect class; the refusal itself is pinned by
`tests/fmt/parity/070-deriving-refused.axp` and
`tests/diagnostics/545-deriving-refused.axbad`.

**The library SHIPS (2026-08-14, seventh commit): `stdlib/Pre.ax`
carries `deriveEq`**, invoked like any prelude macro over entry-file
AND imported types (`tests/selfhost/379-derive-imported.ax`, 30). An
earlier revision of this paragraph claimed a stdlib macro deriving
over an entry file's type needed cross-module queries — measured
false: the subject resolves through the invocation's arguments, and
the entry-file case always worked. What the seventh commit actually
lifted was the SUBJECT limit: a query now answers any type an
entry-file reference could name, with a private type refusing loudly
at the invocation (`tests/diagnostics/550-derive-private-type.ax`) —
the same visibility rule the checker's own lookups apply, enforced in
the query so the refusal is one diagnostic at the right place rather
than checker errors scattered over generated code.

### 4.6 Format strings

**MAC-CAP-10 (H, 2026-08-15).** Two queries — `(syntax/format e)` and
`(syntax/formatln e)` — answer the expression that renders `e` as a
`String`, parsing `e` at expansion time when it is a **string
literal**. They are the only members of the vocabulary that read a
literal rather than the declaration list, and the whole of the
compiler's involvement in formatting: the printing surface is five
macros in `stdlib/`, four lines each.

```scheme
; stdlib/IO.ax
(pub macro (println e)  (writeStr stdout (syntax/formatln e)))
(pub macro (eprintln e) (writeStr stderr (syntax/formatln e)))
; stdlib/Fmt.ax
(pub macro (format e)   (syntax/format e))
```

There is deliberately no newline-less `print`. A partial-line printer
exists in C-descended libraries because assembling a line was
expensive, so you emitted the pieces; here the line is assembled at
compile time and `(println "ok {name} in {ms:>4}ms")` is one call and
one syscall. `writeStr` remains for bytes with no newline and no
rendering. Removing it took `tests/stdlib/340-json.ax`'s self-grading
harness from six print statements per verdict to one, with
byte-identical output.

**Why this is a compiler primitive and not a macro.** Tier 1 rewrites
syntax *nodes*. A format string arrives as one node — a `TAG_E_STR`
whose payload is an opaque lexeme — and nothing in the vocabulary can
take a string apart. Adding a query that could would be a
string-processing language inside the template language. So the
decomposition happens in compiler code, over a literal the compiler
already holds. **This is not tier 2** and does not move the line
the roadmap's §4.2 draws: no user code runs, the
input is a literal rather than a program, and the output is a tree the
compiler builds — exactly as `syntax/constructors` reads a `data`
declaration.

**MAC-CAP-10.1 — what the queries answer.** Two shapes, decided by
what the argument *is*:

| argument | answer |
|---|---|
| a string literal | the concatenation of its literal runs with one rendering call per hole |
| anything else | `(format# e)` — one call, dispatched on `e`'s static type; `(format e)` is how a program writes it |

The second row is load-bearing rather than a convenience: it is why
`println` could *take the name* of the function it replaced. All 78
`(println expr)` that predate the macro still mean what they meant,
because the rendering of a `String` is the identity — the call is
elided outright.

That is not the same as "no call site changed", and an earlier
revision of this paragraph said so and was wrong. **Forty did**, all
of one shape: a value printed straight out of a polymorphic accessor
(`vecGet`, `mapGet`, `memGetWord`) or out of a `handle`, where there
is no named type to select an instance and the answer is `AX3025`
(MAC-CAP-10.6). Each took a `cast`, which is the same fact
`printlnInt` used to carry in its name.

`syntax/formatln` folds `\n` into the **last literal run**, at
expansion time. `(println "hi")` therefore emits one `write` of one
static constant — measured: `@str_9 = ... c"\68\69\0A\00"`, length 3,
one `call @IO$writeStr`, no allocation. The `println` *function* it
replaced did two writes.

**MAC-CAP-10.2 — the hole grammar.**

```
hole   := '{' name [ ':' spec ] '}'
spec   := [align] ['0'] [width] ['.' precision] [type]
align  := '<' | '^' | '>'                       (default '>')
type   := 'x' | 'X'
`{{` and `}}` are a literal brace.
```

`name` is an identifier in the **lexer's** charset, not a second one
invented for format strings, so any name the language can spell can be
interpolated and the two cannot drift.

**A specifier is not a mini-language interpreted at run time — there
is no run time here.** Each part selects a different `Fmt` *function*,
once, during expansion:

| written | expands to |
|---|---|
| `{n}` | `(format n)` |
| `{n:x}` / `{n:X}` | `(fmtHex n)` / `(fmtHexUpper n)` |
| `{x:.2}` | `(fmtFloatPrec x 2)` |
| `{n:>8}`, `{n:8}` | `(fmtPadLeft (format n) 8)` |
| `{s:<12}` | `(fmtPadRight (format s) 12)` |
| `{s:^12}` | `(fmtPadCenter (format s) 12)` |
| `{n:04}` | `(fmtPadZerosLeft (format n) 4)` |
| `{x:>10.2}` | `(fmtPadLeft (fmtFloatPrec x 2) 10)` |

**This is what replaces a print function per type.** `printInt`
existed because rendering an `Int` was a different *call* from
rendering a `String`; the call is now chosen by the specifier and the
argument's static type, so there is one `println` and the per-type
family is gone (`IO` exported `printInt`/`printlnInt` until
2026-08-15; 445 call sites moved to `println`).

**MAC-CAP-10.3 — validation, and who owns which half.** The claim
"format specifiers are validated at compile time" decomposes into two
mechanisms, and neither is a runtime check:

- The **expander** owns the string's shape. A malformed format string
  is `AX3031 malformed-format-string`, at expansion time, with the
  caret **inside the literal** on the offending byte. Eleven cases in
  one fixture (`tests/diagnostics/570-format-refusals.ax`), each a
  distinct shape: an unclosed hole, an unopened `}`, an empty `{}`, a
  hole that names nothing, an unterminated name, an unclosed
  specifier, an unknown specifier type, a bare `.`, trailing bytes
  after a specifier, and a width and a precision above 1,000,000.
- The **checker** owns the value's type. A specifier chooses a
  function with a type, so a well-formed specifier applied to the
  wrong type is an ordinary `AX3004` at the invocation — `{s:.2}` on a
  `String` reaches `fmtFloatPrec`'s `Float` parameter. A hole naming
  an unbound name is `AX3001`; one whose type has no rendering — a
  type variable, a function value, a `Foreign` — is `AX3025`.

No specifier can be "ignored at run time", because none of them
survives to run time.

**MAC-CAP-10.4 — no argument list, and why.** There is no positional
`{}` and no trailing argument list: a macro took a fixed number of
arguments (`MAC-LANG-2`) until `MAC-LANG-16` v1 landed on 2026-08-16,
and a variadic one is a rule with a repeating last element rather than
an argument list on the format call. Capture is the form the
language has, and it is the form Rust's own 2021 edition settled on;
`{}` is refused **by name** — naming the capture form in its help —
rather than left to fail as an empty identifier.

**MAC-CAP-10.5 (H, CLOSED 0.7.4).** The names these queries invent —
`strConcat`, `fmtInt`, the `fmtPad*` family, and the rendering call
for a hole — are not written in any template, so they take
`expQualify`'s definition-site rule (`MAC-HYG-6`) explicitly rather
than through substitution. For as long as any of them could stay
*bare*, an entry file declaring the same name captured it. That was
`MAC-HYG-8`'s residue, shared by the format lowering, and it is now
closed on both counts — by two different mechanisms, which is why the
history is kept.

**The capture was silent and answered wrongly**, and this paragraph
first said the opposite — "loud rather than silent, a type error at
the invocation carrying the expansion backtrace" — until it was run.
Two programs, both at exit 0:

```scheme
(import IO)
(:: show (-> a String))
(fn (show x) "HIJACKED")
;@axiom:effect(io)
(fn (main) (let ((n 42)) { (println "n={n}") 0 }))   ; printed n=HIJACKED
```

```scheme
(import IO)
(:: strConcat (-> String String String))
(fn (strConcat a b) "HIJACKED")
;@axiom:effect(io)
(fn (main) (let ((n 42)) { (println "n={n}") 0 }))   ; printed HIJACKED
```

A capture that happens to be *ill-typed* is loud — an entry-file
`(:: show (-> Int String))` fails, though it fails inside
`stdlib/IO.ax` with no backtrace, which is its own defect — and that
is the case the old claim generalised from. A well-typed capture was
not loud at all.

**What closed the second program.** `expQualify` grew a fourth rule
(`MAC-HYG-8` hole 4): a free identifier is rewritten to `Mod$name`
when exactly *one module* in the merged declaration list declares it,
and the entry file's own declaration is not a module's. `Str` is the
only module declaring `strConcat`, so the lowering emits
`Str$strConcat` and the hijack is not reached. Re-measured on the
0.7.3 binary, which predates the 0.7.4 work below: the second program
prints `n=42`, and `symbols --calls` on `main` reads
`#calls=IO$writeStr,Str$strConcat,Sys$stdout`. This paragraph went on
asserting the capture for as long as it took someone to re-run it,
which is the argument for the fixture rather than the paragraph.

**What closed the first program, in 0.7.4.** A hole's rendering call
is no longer a name at all. `expFmtShow` emits the head `format#`,
`#` is not an identifier character (`AX1001`), and the checker claims
that head and rewrites it from the argument's static type — so
`expQualify` is not consulted, nothing can declare the spelling, and
`(format x)` is the only way a program writes the lowering.
`tests/selfhost/383-format-capture.ax` measures both halves against a
file that still declares its own `show` and its own `strConcat`, and
`tests/diagnostics/621-show-removed.ax` pins that `(show 1)` is now an
ordinary `AX3001`.

<!-- doc-gate:negative-exempt narrative: this says what the corpus DOES contain - two shapes with no named type - which the AX3025 fixtures witness directly. It is a positive population claim wearing a negative clause. -->
**MAC-CAP-10.6 — the dispatch cliff, and the two compiler bugs it
exposed.** A hole becomes a *call*, and which instance it reaches is
decided from the argument's **static type**. Where there is no named
type there is no instance, and the corpus had two such shapes: a
polymorphic accessor's return (`vecGet : (-> Int Int a)`) and, until
2026-08-29, an effect operation's result - a `handle` answered the
checker's silent wildcard; it is typed by its body now, so `(println
(handle ..))` renders. The accessor is `AX3025` naming the situation;
the fix is to name the type (`(println (cast Int (vecGet v 0)))`),
which is exactly the information `printlnInt` used to carry.

Reaching that cliff found two defects that predated this work and were
latent only because nothing in the repository had called a trait method
on a failing or non-concrete expression. Both went with `trait` and
`impl` in 0.6.0, and they are recorded because the class outlives the
construct — a rewrite that picks a callee from a type has to answer for
what it emits when the type is not there:

1. **Dispatch emitted a call to a function that does not exist.** With
   no head name, `traitRewrite` answered 0 and left the head spelled
   `show`; the emitter wrote `call i64 @show` and `opt` rejected the
   module — `AX4003` against `<toolchain>`, no span into the source.
2. **Every diagnostic inside a dispatch argument was doubled.**
   Selecting an implementation means checking that argument for its
   type, and the ordinary argument walk checks it again; both
   reported. Reproduced with an entry-file trait, one impl, and no
   macros at all: `(sz nope)` answered two identical `AX3001`s.

---

## 5. Safety

**MAC-SAFE-1 (H, author obligation).** Because arguments are substituted
as syntax (`MAC-EXP-7`), a template that mentions a parameter more than
once **duplicates its effects**. A macro author who must not duplicate
one **MUST** bind it first:

```scheme
(macro (twiceSafe x) (let ((v x)) (+ v v)))    ; hygiene renames `v`
```

`MAC-HYG-1` is what makes this idiom safe to write: the binding cannot
capture anything at the call site.

**MAC-SAFE-2 (H).** Expansion **MUST NOT** be able to produce a program
the checker would not have checked. It runs before the checker, it emits
ordinary AST nodes, and there is no path from a template to the emitter
that bypasses `checkModule`. This is the property `MAC-EXP-1` buys and
the reason the pass was moved.

**MAC-SAFE-3 (H).** Expansion **MUST NOT** be able to forge a claim
about a program. Generated code contributes to effect inference exactly
as written code does — a template that reaches a syscall makes its
caller `#effects=IO` — and `;@axiom:` metadata attaches to declarations,
which a template cannot produce today (`MAC-LANG-5`). Under
`MAC-CAP-8`, a generated declaration's AXTAG claims **MUST** be
validated by `AX3010` like any other.

**MAC-SAFE-4 (H).** Expansion **MUST NOT** be able to hang or crash the
compiler: `MAC-EXP-9`'s five budgets, and node handle 0 guarded
everywhere the expander walks. This rule was FALSE as written between
phase D's arrival and 2026-08-23, and its own wording is why: it said
three budgets while the phase that runs first was covered by one of
them, so a fanning-out declaration template was killed by the operating
system at multi-gigabyte RSS — a crash of the compiler, by this rule's
own definition, with the rule claiming it could not happen. `()` in a template is refused at the
macro's own line, before any invocation — one of the twenty-three
positions of the empty form that `scripts/check-degenerate.sh` pins,
seven of which used to kill `check` rather than the emitter.

**MAC-SAFE-5 (R).** A macro **MUST NOT** be able to observe the
compilation environment: no file access, no environment variables, no
clock, no randomness, no network. This follows from `MAC-LANG-13` and is
restated because it is the property that makes an Axiom source tree
*auditable by reading it* — the same argument
`scripts/check-reproducible.sh` makes about the output.

---

## 6. Integration

**MAC-INT-1 (H).** **Modules.** A macro is a declaration: it is
imported, made visible by `pub`, selectable by an import's name list,
and private otherwise (`MAC-LANG-9`). Diamond imports merge it once, as
for any declaration.

**MAC-INT-2 (H).** **Generics.** A macro is oblivious to types, so it
composes with polymorphism trivially and cannot specialise on it. A
macro that generates a call to a polymorphic function generates an
ordinary call.

Two facts about what that call meets, because they bound how much a
generated call can be checked. Generic instantiation is **uniform
representation, not monomorphisation**: every value is one machine word,
so a polymorphic function is emitted once and every call site calls the
same symbol — a macro can never cause a code-size explosion by
instantiation. And there is **no Hindley–Milner inference**: an
unsignatured function's parameters are all `Int`, a signature's type
variable is rigid inside the body and becomes an unsolved placeholder at
each reference, and placeholders are never solved — so a generated call
passing two mutually inconsistent arguments to a polymorphic function is
**accepted**. `MAC-EXP-2` promises generated code is checked exactly as
written code is; it does not promise the checker is strong.

**MAC-INT-3 (H).** **Effects.** Expansion is invisible to the effect
system: inference runs on the expanded program (`MAC-EXP-1`), so a
macro's effects are its expansion's effects, attributed to the caller.
A macro **cannot** be effect-polymorphic in its own right, and does not
need to be.

**MAC-INT-3a (H).** One consequence is worth stating because it looks
like a compiler bug the first time it is seen: **a macro that drops an
argument can invalidate an AXTAG claim the author wrote.** The claim is
validated against the *expanded* program, and the dropped argument is
not in it:

```scheme fragment
(macro (ignore x) 7)
;@axiom:effect(io)
(fn (main) (ignore (side 1)))     ; `side` performs IO — and is dropped
```
```
E AX3010 axtag-mismatch "AXTAG mismatch on `main`: `effect(io)` claim unsupported: missing IO"
```

The diagnostic is **correct**, and since 2026-08-25 it refuses the
build: after expansion, `main` performs no I/O, so the claim is false as
written and the fix is to drop the tag the macro made untrue. (That is
why the block above is fenced `scheme fragment` — `tests/docs/verify-doc-code.py`
compiles every documented whole program, and this one is documented
precisely because it does not compile.)
This is the intended interaction, not a defect, and a conforming
implementation **MUST** keep validating claims against the expanded
program — validating them against the source would let a macro's
rewrite silently falsify a claim in the other direction.

**MAC-INT-4 (H, its subject removed in 0.6.0).** **Interfaces.**
Traits and `impl` *were* implemented: an `impl` lowered to an ordinary
declaration named `Trait#Type#method`, and a trait-method call was
statically rewritten to a direct call to that symbol, selected by the
concrete type of the first argument. They were *declarations*, so a
macro could generate them only under `MAC-CAP-8` — which is why
`MAC-CAP-8` was the highest-value planned rule in this document. Both
words are `AX2004` now, and an interface is a **capability record**: a
parameterised `struct` holding the functions, generated by the `struct`
and `fn` template kinds like any other declaration.

Two properties of that lowering bore on generated instances, and one of
them outlived it. Impl symbols carried **no module**, so two modules
implementing the same `(Trait, Type)` pair passed `check` and then
failed in `opt` as an LLVM redefinition — no coherence or overlap
check, and a `derive` invoked in two modules for one type hit exactly
that. A capability record is an ordinary value with an ordinary
module-qualified name, so that shape went with the construct.

What stands is the second, and it is now a rule about the record rather
than about a trait: **there is no dictionary-passing, and generated
code MUST NOT assume there is.** A function that needs an interface's
members has to be handed the record that holds them — dispatch is
`((c.eq) x y)`, an application of a field. Under traits the same rule
had a sharper edge: a function generic over a trait could not call the
trait's methods at all, and that program passed `check` and died in
`opt` with `use of undefined value`.

**MAC-INT-5 (H).** **The formatter.** `axiom fmt` formats a macro
declaration and its template as source; it does **not** format
expansions, which do not exist in the file. A conforming formatter
**MUST NOT** rewrite a template in a way that changes what it expands to
— which is not a hypothetical, since the formatter has independently
re-implemented the token set and has changed a literal's meaning before
(`0.05` became `0.5`).

**MAC-INT-6 (H).** **tree-sitter.** `tree-sitter-axiom/grammar.js` is
one of the four implementations of the surface syntax `MAC-LANG-16`
enumerates. Any change under
`MAC-LANG-14`–`MAC-LANG-16` **MUST** land in the lexer, the formatter
and the grammar together, gated by `scripts/check-tree-sitter.sh` and
`scripts/check-fmt.sh`. This document names the obligation because the
last three surface changes each found the three implementations
disagreeing.

---

## 7. Diagnostics

**MAC-DIAG-1 (H).** Macro diagnostics live in the semantic range,
because expansion is semantic-analysis-time work. Thirteen codes can
reach a macro author; `axiom explain --list` is the authority on the
set, and all but `AX3023` are constructed in `self_host/expand.ax`:

| Code | Slug | Fires when |
|---|---|---|
| `AX3018` | `macro-arity` | an invocation no rule accepts (`MAC-EXP-8`, `MAC-LANG-18`). For the head-list form that is still counting — too FEW arguments; a longer spine is not an error in expression position, since the surplus is applied to whatever the macro produced. In DECLARATION position the message names the SHAPES the rules accept — "no rule of macro `n` matches this invocation; it accepts …" — and an invocation whose count some rule declares still lands here if no rule's shape matches. The slug stayed `macro-arity` because `MAC-LANG-18` specifies the generalisation by name |
| `AX3019` | `macro-recursion-limit` | instantiation depth exceeded 128 |
| `AX3020` | `macro-duplicate-parameter` | two parameters share a name |
| `AX3021` | `macro-template-unsupported` | a template form substitution cannot handle. Its *expression*-template arm has no reachable producer, by design (`MAC-CAP-2`); its reachable producer is a declaration template generating a kind outside the v1 surface, at the macro's own line |
| `AX3022` | `macro-set-target` | a parameter used as a `set` target, given an expression |
| `AX3023` | `private-name` | a macro its module does not export — the general visibility code, reached by macros since `MAC-LANG-9` |
| `AX3024` | `macro-expansion-limit` | the output tree exceeded 1024 deep or 2,000,000 nodes. The parser's limits measure the source; these measure what expansion produced from it |
| `AX3027` | `declaration-macro` | every way a declaration-position invocation fails: unknown head (a typo'd keyword lands here, where it used to be a bare `AX2003` that stopped the parse), either template kind across the position boundary, a non-identifier argument in a name position, and a module-side invocation reaching a pipeline that carries no mangling records. `axiom explain AX3027` is the catalogue |
| `AX3028` | `syntax-query` | every `syntax/*` query with no answer (`MAC-CAP-5`/`MAC-CAP-6`): an unknown or wrong-position head (the vocabulary is CLOSED), a subject with nothing to answer, a query written outside a macro template, a declaration named into the reserved `syntax/` prefix. `axiom explain AX3028` is the catalogue |
| `AX3031` | `malformed-format-string` | the expander's half of `MAC-CAP-10.3`, with the caret inside the literal on the offending byte |
| `AX3033` | `macro-unreachable-rule` | a rule an earlier one starves: rules are tried in order, and a rule whose every element is a plain binder matches everything of its arity, so nothing of that arity after it can run. Two rules of one arity are fine when their shapes differ — that is what patterns are for |
| `AX3034` | `macro-ellipsis` | an ellipsis at the wrong depth: a repeating name used without `...`, `...` after something that does not repeat, two `...` in one rule, or a repeat over a pattern rather than a bare name. The first two report at the invocation, the last two at the macro |
| `AX3035` | `macro-binder-target` | a parameter in BINDER position given something that is not a variable (`MAC-HYG-10`); the same rule `AX3022` follows for `set` targets |

`AX3006` (duplicate definition) also reaches macros (`MAC-LANG-8`).

`AX3018` and `AX3019` each replace a failure that was not a diagnostic
at all. Under-application left the parameter's own name in the
generated code (`add i64 40, %q`, rejected by `opt` as an undefined
value); over-application dropped the surplus argument **without
evaluating it**, so its side effects silently did not happen; and
`(macro (loopy x) (loopy x))` segfaulted the compiler with no output
and no diagnostic, in about 10 ms of CPU time.

**MAC-DIAG-2 (H).** Every macro diagnostic **MUST** anchor at a span in
the file being compiled (`MAC-EXP-14`) and **MUST** name the macro in
its message, since it cannot point at it.

**MAC-DIAG-3 (H).** A diagnostic **MUST** be reported once. The output
budgets set a "blown" flag so that the refusal is reported at the first
node rather than at every node after it.

**MAC-DIAG-4 (H).** A diagnostic arising inside an expansion carries an
**expansion backtrace**: one frame per enclosing instantiation,
outermost first, each naming the macro with the span of its
**declaration** in its **own unit** — the two-source diagnostic the
one-unit `Diag` could not express while a frame was a bare string.
AXDL renders each as `&FILE:LOC:"name"`, the one field on the line
whose file is not the diagnostic's own; the human renderer prints
``in this expansion of `name` (FILE:LOC)`` as a note; JSON's
`expansion` array holds `{"macro", "file", "line", "col"}` objects; the
LSP appends the name. Pinned by
`tests/diagnostics/490-expansion-backtrace.ax` — one frame on a direct
invocation, two on a nested one — whose frame spans
`verify-axdl-spans.py` checks against the macro's file the way it
checks every claim, boundary rules and name anchoring included.

Two decisions made it small where this rule used to warn it was large:

- **Frames join by span handle, not by node provenance.** Every node a
  template produces is rebuilt carrying the invocation's span
  (`MAC-EXP-14`) — the same record *by reference* — so the expander
  records one `(declaration module, invocation span, macro, its span,
  its module)` entry per instantiation, and a post-pass after the
  checker attaches frames to any diagnostic whose primary span IS a
  recorded handle. Pointer equality cannot collide across files, no
  node grew a provenance word, and the parser is untouched.
- **The widening cost what it predicted and no goldens.** The frame
  element became `(name, span, unit)` (`DFrame`), the four renderers
  and the published grammar in [diagnostics.md](diagnostics.md) moved
  together, and `645-axdl-repetition`'s hand-built string survived
  byte-for-byte because a span-less frame still renders the bare
  `&"name"` the grammar always had — and nothing had ever populated
  the field, so no existing golden held one.

The invocation stays primary, exactly as `MAC-DIAG-5` wants: it is the
line the author can change. The REPL deliberately discards frames —
its error line joins bare messages, and the prompt *is* the invocation.

**The expander's own refusals carry frames too, since 2026-08-15.**
The join used to run over the CHECKER's diagnostics only, so `AX3021`,
`AX3027` and `AX3028` — the refusals that are, by construction, from
inside an expansion — gave a span and no macro name. They go through
the same `expAttachFrames` now, and nine `.axdl` goldens gained an `&`
field the day it landed, which is the whole visible cost.

Attaching them forced a rule this specification had left to accident,
and it is `MAC-DIAG-5`'s rule applied one level down. **A refusal
about the TEMPLATE's shape anchors at the macro; a refusal about the
ARGUMENTS' values anchors at the invocation and carries the frame.**
The author edits a different line in each case: a binding form that is
not a `(y ys)` pair is the macro's text however it is invoked, while a
SKEW is the invocation's doing — the template pairs the sequences and
the arguments decide their lengths. `syntax/fold` had always reported
its skew at the invocation and `syntax/for` at the form; that was a
coincidence of two authors, and now it is one rule with the same
answer on both sides.

**MAC-DIAG-5 (H, 2026-08-15).** With `MAC-DIAG-4`, the rendered form
**SHALL** be:

```
error[AX3005]: non-exhaustive match: `Blue` not covered
 --> app.ax:12:3
  |
12| (deriveEq Color)
  |  ^^^^^^^^^ in this expansion
  |
 --> stdlib/Derive.ax:8:14
  |
 8|   (match a ((Red) 1) ((Green) 2))
  |    ^^^^^ the match generated here
```

The invocation stays primary — it is the line the author can change —
and the frames follow it outermost first, each opened in its own file.

*Held since 2026-08-15* (`tests/diagnostics/490-expansion-backtrace`,
one frame and a nested two): a frame whose unit the renderer can reach
becomes a location block of its own, with the macro's declaration line
quoted and its span under a caret labelled ``in this expansion of
`name` ``. A frame with no span, or one whose unit is out of reach,
still renders as the note `MAC-DIAG-4` shipped — a location block
needs a file to open. The gutter is computed across the primary and
every frame together, so one report keeps one bar column however many
files it spans.

The machine surfaces did not move: the AXDL `&` field and the JSON
`expansion` array are byte-identical before and after, which is what
"renderer work alone" meant. `scripts/check-render-selfhost.sh`
derives the block from the AXDL the same way it derives the primary —
header line, quoted source line, caret row of the span's width and the
frame's label — reading the right-hand side out of the frame's own
fixture bytes.

---

## 8. Tooling

**MAC-TOOL-1 (H).** A macro declaration **MUST** carry a real span. It
did not until recently, which also left the language server's
`documentSymbol` arm for macros dead since it was written, and made
`AX3006`'s "first defined here" line point nowhere.

**MAC-TOOL-2 (H, 2026-08-15).** The language server **SHALL** treat a
macro invocation as a reference to its declaration: go-to-definition
jumps to the `macro` form, hover shows the template, and
`documentSymbol` lists macros beside functions. All three hold —
`definitionProvider`, `hoverProvider` and `completionProvider` are
advertised, a position on a macro name answers the declaration's own
name range, and hover answers the declaration verbatim from the
document's bytes in an `axiom` code fence. A position on a name that is not a macro answers
`null`, which is the protocol's "nothing here" and what every other
word in a file gets.

*That limit is closed, 2026-08-25.* This paragraph read: "the lookup
reads THIS document's declarations, so a macro imported from another
module answers null rather than jumping into that module's file.
Resolving it means walking the import graph for a navigation request,
which is the work `MAC-TOOL-3` exists to keep out of the fast path, and
it wants the module-URI mapping the server does not otherwise need."

Both halves were right about the cost and wrong about the conclusion.
The server does now resolve the import graph for a navigation request —
but only when the lookup in THIS document misses, which is the same
ordering the language's own scoping has (a module's own declaration
shadows an imported one), so a definition request inside the file being
edited still pays one parse. Nothing expands: the raw tree carries
every declaration either lookup needs, so `MAC-TOOL-3` holds unchanged.
The module-URI mapping is `lspPathToUri`, the inverse of the
`lspUriToPath` the server already had.

The same slice widened the lookup from macros to every declaration kind
`documentSymbol` lists — a function, a `data`, a `struct`. It had been
macros alone, so a call to a function three lines above answered null,
which an editor renders as "there is nothing here" rather than as "this
server does not do that". `documentSymbol` and `definition` answering
different sets of names is drift, and there is no reason for a name the
outline shows to be a name navigation cannot reach.

*And hover followed, 2026-08-26.* `hover` was still the macros-only
lookup this paragraph describes `definition` having been — the same
wrong answer, on the other request. It now takes `definition`'s
ordering and `definition`'s set: this document's declarations first,
then the merged list, over every kind the outline lists. What it
answers is the declaration in an `axiom` fence, the module below it
when the name was imported, and the COMMENT PARAGRAPH written above the
declaration, which is the half a signature cannot carry. A `fn` is
quoted as its `(:: f T)` signature rather than its body — a body is
arbitrarily long, and "where is this written" is the question
`definition` answers — and the paragraph is read from above the
signature, because that is where this language puts it. The published
`range` is the WORD under the cursor rather than the declaration's own
span, which is what the protocol asks for and which for an imported
name is not even in the same file.

`completionProvider` joined them in the same slice, under `MAC-TOOL-3`
unchanged. A completion offers, in this order, the head keywords the
parser dispatches on, this document's declarations and the
constructors a `data` names, and every imported module's declarations
under their bare names — a local name shadowing an imported one and
both shadowing a keyword, which is the language's own rule. The list is
filtered on the prefix under the cursor and sent with `isIncomplete:
true`, because a server that filters must be asked again on the next
keystroke; a document that does not parse still completes keywords,
which is not a degraded case but the normal one, since a file is
unparseable exactly while a form is half written.

**MAC-TOOL-3 (H, 2026-08-15).** A conforming language server **SHALL
NOT** expand macros to answer a request that does not need it.
Expansion is bounded but not free (`MAC-EXP-10` measured 41.4 s on a
fan-out probe), and the budgets exist precisely because an editor
cannot wait. Every request that is asked per keystroke or per cursor
move — `documentSymbol`, `definition`, `hover`, `completion`, and since
2026-08-28 `references`, `documentHighlight`, `prepareRename`,
`rename`, `signatureHelp`, `inlayHint`, `foldingRange`,
`selectionRange`, `documentLink`, `workspace/symbol`, `formatting`,
`typeDefinition` and `codeLens` — reads the RAW parse tree and the
document's bytes and expands nothing. Three things run the pipeline,
each because expansion IS the answer: `didOpen` and `didChange`, which
publish diagnostics, because a diagnostic about generated code is
exactly what expansion is for; `codeAction`, because a quickfix is a
checker diagnostic's own fix and the assist writes what the checker
inferred; and `axiom/expandMacro`, because rendering what a macro
generated is the question being asked. None of the three is sent per
keystroke — a client asks for code actions when the cursor rests and
for an expansion on demand — and each costs about one `didOpen` of the
same document, which the editor paid on the last keystroke anyway.
The visible consequence is that completion does not offer a name a
macro would generate: `(deriveTag Colour)` does not put `tagColour` in
the menu, because nothing has expanded it. `check-lsp-selfhost.sh`
asserts that absence rather than leaving it to be noticed.

*The expansion request needed a printer, 2026-08-28.* Nothing in the
compiler could turn a node back into source — `format.ax` prints from
its own token forms, `symbols` renders types alone — so
`axiom/expandMacro` carries the first `ASTNode`-to-source printer,
`lspRenderDecl`/`lspRenderExpr` in `self_host/lsp.ax`. Its promise is
that the output parses and means what the tree meant, and the gate
holds the first half by reopening the rendering as a document and
requiring an outline of exactly the generated name; the second was
measured on a template holding a mutable `let`, a block, `set`,
`while`, `match`, `cond`, a two-parameter lambda, struct construction,
field access, an escaped string, a char, a float, a negative literal
and a generated `data`, `type` and `struct` — `check` on the rendering
reported exactly the diagnostics it reported on the template. Two
things the printer says out loud: a hygiene binder `x.3` is written
`x_3`, and `Mod$name` as `Mod::name`. And one thing it found, an
expander defect rather than a printer choice, fixed the same day: a
generated `struct`'s fields carried no type in the expanded tree,
because `expBuildStructFieldsIn` substituted the parsed field's
float-flag word where the type sits. An `Int` field's 0 became an
untyped field — the wildcard the checker already saw, `{unknown}` in
`symbols` where the handwritten twin prints `Int`, `(name)` in the
rendering — and a bare `Float` field's 1 was dereferenced as a node,
so `check` died of SIGSEGV before saying anything. The builder now
substitutes the field's type node and recomputes the float flag from
what came out, as `expCtorFlags` does for a constructor, so a generated
struct and its handwritten twin produce identical AXSYM rows and
identical code. Pinned by
`tests/selfhost/396-macro-struct-field-types.ax` — exit 139 on the
unfixed compiler — and by the zoo's `RecTwin`, whose row in
`tests/tools/symbols-zoo.golden` carries `Rec`'s own `#fields=`.

**MAC-TOOL-4 (H, 2026-08-15).** With `MAC-CAP-8`, `axiom symbols`
**SHALL** list generated declarations, attributed to the file
containing the invocation, and **SHOULD** mark them as generated so a
reader can tell why a name has no visible definition. Both hold: a
generated row carries `#generated=<macro>`, naming the macro that
produced it, and phase D answers the (name, macro) table that says so
— `expandProgram` RETURNS it, rather than taking a tenth parameter,
and every caller that does not care discards it exactly as it
discarded the 0 that came back before. A generated declaration whose
name came from `syntax/join` still reports no position, because the
file spells no such name; `#generated=` is what now explains that
dash.

**MAC-TOOL-5 (H, 2026-08-15).** **Lints run on the program the author
wrote, not on the program expansion produced.** A diagnostic whose span
lies inside an expansion and whose fix would edit generated text
**MUST NOT** be offered as machine-applicable: there is nothing at that
location to edit. Concretely, a conforming implementation **MUST**
suppress a machine-applicable `~>` replacement whose span belongs to a
generated node, and **MUST NOT** emit a replacement string containing a
renamed binder (`MAC-HYG-3a`).

This is a rule about a hazard the language already has rather than a
future one: the AXDL grammar's `~>` field is consumed by tools that
apply it without asking. It was being violated, measured on two
diagnostics rather than argued:

```
E AX3012 ... "cannot assign to immutable binding `tmp.0`"
    ?4:13-17:"declare it mutable: `(mut tmp.0 ...)`"~>"mut tmp.0"
    &tool5.ax:1:9-13:"bump"
E AX3001 ... "undefined variable `helperr`"
    ?7:13-19:"a similarly named binding `helper` is in scope"~>"helper"
    &tool5b.ax:1:9-15:"callIt"
```

Both spans are the INVOCATION's — which is what `MAC-DIAG-5` wants for
the report and what makes the fix wrong, since applying it pastes the
replacement over the macro call. The first also carries `tmp.0`, a
renamed binder no source can spell, which is `MAC-HYG-3a`'s half of
this rule.

The implementation is the join `MAC-DIAG-4` already computes: a
diagnostic that acquired an expansion FRAME is a diagnostic about
generated text, so `expAttachFrames` disarms its helps as it attaches
them — the help's text survives, its span-and-replacement pair does
not. Nothing outside an expansion moves, which the fixture asserts by
carrying the same two diagnostics twice, once from a macro and once
written by hand (`tests/diagnostics/580-expansion-fix-suppressed.ax`).

**MAC-TOOL-6 (H, defective).** `axiom fmt` **MUST NOT** disagree with
`axiom check` about what lexes. It does today — the formatter carries
backtick and `,@` token kinds the compiler's lexer does not, and treats
`'`, `` ` ``, `,` and `,@` as prefix tokens attaching to the following
form. Measured on `(fn (main) `(+ 1 2))`:

```
$ axiom check bt.ax
E AX1001 bt.ax:1:12-13 unexpected-char "unexpected character ```"
$ axiom fmt bt.ax
OK: bt.ax formatted
```

`fmt` **rewrote** a file `check` refuses. This matters to the macro
system specifically because `` ` `` and `,@` are the obvious spellings
for any future quotation form, and the formatter has already claimed
them with semantics nobody specified. Any change under `MAC-LANG-16`
inherits the discrepancy and **MUST** resolve it rather than add to it.

---

## 9. Rationale

**Why a rewrite and not an evaluator.** Every other decision in this
document follows from `MAC-LANG-13`. A procedural macro system is
strictly more expressive and would cost this project the one property it
has consistently paid for: that compiling a file executes nothing the
file chose. A language whose compiler runs the code it is compiling has
a threat model, a sandbox and a resource policy to design — and Axiom
would be designing them in order to derive an `Eq` instance.

**Why patterns rather than more parameters.** Axiom is an S-expression
language, so the shape of a form *is* its data. Matching on it is the
natural facility, and it covers the stated use cases — deriving
instances, eliminating the boilerplate the standard library is full of,
generating the repetitive parts of a self-hosted compiler — without the
expressiveness that requires evaluation.

**Why hygiene by renaming first, scope sets second.** Renaming is a
complete solution to the direction that produces *wrong answers*, and it
was implementable in one pass with no change to either resolver. Scope
sets are a change to what an identifier *is*, reaching the parser and
name resolution. Shipping the cheap half first was right; stopping there
is not, which is why `MAC-HYG-9` is normative and carries an equivalence
obligation rather than a rewrite licence.

**Why the default arm refuses.** Eight silent miscompiles were one bug —
a tag added to the parser and not to the substituter — and a default
that returns the node unchanged makes the ninth silent too. A default
that refuses makes it loud, in the commit that adds the tag. This is the
most transferable rule in the document: **a rewriter's unknown case is
never a passthrough.**

**Why the budgets are on the output.** The parser's limits measure the
source, and a macro's source is short by construction. 154 bytes
producing 2²⁶ nodes is not an adversarial input; it is six lines of
plausible code.

---

## 10. Worked examples

### 10.1 What works today

```scheme
; stdlib/Pre.ax, in full — the whole of the current facility
(pub macro (when test body)   (if test body 0))
(pub macro (unless test body) (if test 0 body))
(pub macro (cond2 t1 b1 t2 b2 els)       (if t1 b1 (if t2 b2 els)))
(pub macro (cond3 t1 b1 t2 b2 t3 b3 els) (if t1 b1 (if t2 b2 (if t3 b3 els))))
```

A guarded accumulator, showing hygiene doing its job — the template's
`acc` cannot collide with the caller's:

```scheme
(macro (sumIf test x acc)
  (let ((v x))                       ; MAC-SAFE-1: evaluate x once
    (if test (+ acc v) acc)))
```

### 10.2 Deriving structural equality

Under `MAC-CAP-5` and `MAC-CAP-8`. This is the acceptance criterion
the roadmap's §4.2 states, written out — and since
2026-08-14 the nullary form below is **measured, verbatim**:
`tests/selfhost/374-derive-eq.ax` is this section's macro, data type
and invocation, and it answers 101 from three `eqColor` probes on the
first complete run of the query vocabulary. The fieldful form further
down is measured too, since later the same day:
`tests/selfhost/377-derive-eq-fieldful.ax` (30) — `syntax/binders` and
`syntax/fold` landed with the fixture that spends them.

```scheme
(pub macro deriveEq
  ((deriveEq T)
   (:: (syntax/join eq T) (-> T T Bool))
   (fn ((syntax/join eq T) a b)
     (match a
       (syntax/for (C (syntax/constructors T))
         ((C) (match b ((C) true) (_ false))))))))

(data Color () (Red) (Green) (Blue))
(deriveEq Color)          ; generates eqColor : Color -> Color -> Bool
```

expanding to exactly what an author would have written by hand:

```scheme
(:: eqColor (-> Color Color Bool))
(fn (eqColor a b)
  (match a
    ((Red)   (match b ((Red) true)   (_ false)))
    ((Green) (match b ((Green) true) (_ false)))
    ((Blue)  (match b ((Blue) true)  (_ false)))))
```

Two properties this example exists to demonstrate:

- **The generated `match` is checked.** Adding a fourth constructor to
  `Color` without regenerating draws `AX3005` — the same code the
  hand-written match draws (`MAC-EXP-2`). This half is *already* true
  today for expression macros.
- **No user code runs at compile time.** `syntax/constructors` and
  `syntax/join` are answered by the expander from the declaration list
  (`MAC-CAP-6`).

Constructors *with* fields are the same shape one vocabulary rung up —
**and that rung holds too (2026-08-14, third commit)**:
`syntax/binders` names a constructor's fields as fresh pattern binders,
the parallel form of `syntax/fold` zips the two sides, and
`tests/selfhost/377-derive-eq-fieldful.ax` (30) runs the free-function
form over a sum whose constructors carry 1, 2 and 0 fields — one
template, with the nullary case falling out of the empty fold
answering `true`. The field comparison there is written `(== xi yi)`,
which covers `Int` fields; the trait-dispatching `(eq xi yi)` of the
`impl` form below landed one commit later. (An earlier revision called the
fieldful case "the honest edge" because nothing could name the *i*-th
field of a bound pattern; `syntax/binders` is the table row that
closed it, argued for exactly as `MAC-CAP-6` requires.)

**The `impl`-generating form is gone (0.6.0)**: it was the fourth commit's worked example, and it composed — `(deriveEq Inner)` left `Eq#Inner#eq` behind and `(deriveEq Outer)`'s comparison of its `Inner`-typed field dispatched to it by the field's static type, at compile time. Traits went and took both the template and the dispatch it generated. What the expander is shown to do here — `syntax/for` over constructors, `syntax/binders` naming the *i*-th field, `syntax/fold` closing the conjunction — is unchanged and still pinned by the three fixtures above; only the declaration the template expands *into* was a trait instance, and a capability record is an ordinary value a macro can build the same way.

```scheme fragment
(pub macro deriveEq
  ((deriveEq T)
   (impl (Eq T) where
     ((eq (lambda (a b)
       (match a
         (syntax/for (C (syntax/constructors T))
           ((C (syntax/binders C x))
            (match b
              ((C (syntax/binders C y))
               (syntax/fold && true
                            ((xi (syntax/binders C x))
                             (yi (syntax/binders C y)))
                 (eq xi yi)))
              (_ false)))))))))))
```

The honest edge moves rather than disappears, and it is `MAC-INT-4`'s
rather than this section's: a **polymorphic** field — `(Just a)`'s
payload — has no concrete type for that dispatch to select on, and no
dictionary exists to pass. `deriveEq` over a parameterised type
therefore draws the same refusal the hand-written comparison would,
which is `MAC-EXP-2` doing its job: generated code is checked exactly
as written code, and it cannot call what the language cannot dispatch.

### 10.3 Deriving lenses

The boilerplate case, and the one where `MM-MUT-2`'s aliasing hazard
makes a *functional* accessor worth generating — **measured, verbatim,
2026-08-14**: `tests/selfhost/375-derive-lenses.ax` is this section's
macro, struct and invocation, and it answers 34 from a
getX/withX/withY round trip. Four mechanisms carry it beyond §10.2's
set: declaration-position `syntax/for` (four declarations per field),
argument-position `syntax/for` (each element splicing one argument
into the `(Point ...)` rebuild), field-name substitution (`s.f` with
`f` iterating), and `syntax/same` deciding the diagonal at expansion
time with the chosen branch spliced — so the "expands to" claim below
is literal, not merely behavioural:

```scheme
(pub macro deriveLenses
  ((deriveLenses S)
   (syntax/for (f (syntax/fields S))
     (:: (syntax/join get f) (-> S Int))
     (fn ((syntax/join get f) s) s.f)

     (:: (syntax/join with f) (-> S Int S))
     (fn ((syntax/join with f) s v)
       (S (syntax/for (g (syntax/fields S))
            (if (syntax/same f g) v s.g)))))))

(struct Point (x : Int) (y : Int))
(deriveLenses Point)
; getX  : Point -> Int         withX : Point -> Int -> Point
; getY  : Point -> Int         withY : Point -> Int -> Point
```

`withX` expands to `(fn (withX s v) (Point v s.y))` — a **rebuild**,
which is the difference between a lens and a field store: `(set p.x 1)`
mutates through every alias (`MM-MUT-2`), and `(withX p 1)` does not.
This example is also why `syntax/same` has a row in `MAC-CAP-5`'s
table: the entry earned its place the moment a real macro needed it,
which is what `MAC-CAP-6`'s closure rule is for — the entry is a
language change, argued for here and recorded there.


### 10.4 An algebraic optimiser as rewrite rules

Pattern macros make a peephole optimiser a table rather than a visitor —
each rule is a pattern and a template, which is exactly what a rewrite
rule *is*:

```scheme
(pub macro simplify
  ((simplify (+ e 0))     (simplify e))
  ((simplify (+ 0 e))     (simplify e))
  ((simplify (* e 1))     (simplify e))
  ((simplify (* e 0))     0)
  ((simplify (- e e))     0)              ; literal repetition: same form twice
  ((simplify (f a ...))   (f (simplify a) ...))
  ((simplify e)           e))

(simplify (+ (* n 1) 0))                  ; n
```

Two rules of this document are load-bearing here and worth naming:
`MAC-EXP-9`'s budgets are what make a recursive rewrite table safe to
write (`(simplify e)` falling through to itself would otherwise hang the
compiler), and `MAC-LANG-18`'s ordering is what makes the last rule a
default rather than an ambiguity.

**What this example still needs, itemised on 2026-08-16 rather than
left implied.** `MAC-LANG-18`'s ordering holds and the seven rules of
arity one are no longer refused — that refusal narrowed the same day,
and refusing this table six times over was the measurement that showed
it had to. Three things are still missing, and every one is a named
rule rather than an omission:

- the heads. `+` and `*` in `(+ e 0)` are what tell rule 1 from rule 3,
  and a pattern's head is an ordinary binder, so `(+ e 0)` as written
  matches `(* n 1)` too. Literal identifiers are `MAC-LANG-17` and
  they need `MAC-HYG-9`'s scope sets, exactly as `MAC-LANG-17` says.
- `(f a ...)`, which is `MAC-LANG-16`'s ellipsis.
- `(- e e)`, a repeated binder, which `MAC-LANG-15` refuses (`AX3020`)
  rather than reading as a same-form test: `expParamIndex` is
  last-wins, so permitting it would silently bind the second
  occurrence, and there is no structural form-equality to compare
  against — `syntax/same` is not one.

And the templates here are EXPRESSIONS, which the rule form does not
take (`MAC-LANG-14`'s decision of 2026-08-15). So this section is
still a sketch of where the rules point, and it now says which ones.

### 10.5 A small DSL

A state machine, where the value of a macro is that the *shape* is
checked by the compiler rather than by a runtime parser:

```scheme
(pub macro machine
  ((machine nm (state s (on ev next)) ...)
   (data (syntax/join nm State) () (s) ...)

   (:: (syntax/join nm Step)
       (-> (syntax/join nm State) Int (syntax/join nm State)))
   (fn ((syntax/join nm Step) st e)
     (match st
       ((s) (if (== e ev) (next) (s))) ...))))

(machine Door
  (state Closed (on 1 Open))
  (state Open   (on 0 Closed)))
```

Here the ellipsis is doing the work rather than a query: the pattern
`(state s (on ev next)) ...` binds three parallel sequences, and the
template uses each at the same depth — `MAC-LANG-16`'s rule. The
generated `match` is exhaustive over the generated `data` type by
construction, and if a transition names a state that has no `state`
clause, `AX3002` reports it at the `(machine Door ...)` line.

That last sentence is why `MAC-DIAG-4` is normative rather than a
nicety: without an expansion backtrace, the author of `(machine Door
...)` reads a diagnostic about a constructor they never wrote, in a
`match` they never wrote, at a line that contains neither.

### 10.6 A DSL that ships: `stdlib/Html.ax`

The HTML templating layer is the first DSL in the standard library
written in this macro system, and its module header is the proof of
which rule each part rests on. It is pinned by
`tests/stdlib/420-html-render.ax` (rendering, escaping in both
contexts, iteration, hygiene, a component, a whole document) and
`421-html-script.ax` (`</script>` neutralised at run time), each
compared against bytes written by hand. What it exercises, rule by
rule:

- **`MAC-EXP-7`** is the reason an element is a macro and not a
  function: `(div b { children })` must write `<div>` BEFORE its
  children run, and only substitution-as-syntax evaluates an argument
  where its parameter stands. Children are a `{ ... }` block, which
  `MAC-CAP-1` admits as a template form and the parser admits as an
  argument, so a fixed-arity macro takes any number of them.
- **`MAC-HYG-10`** is what MADE `(for it items body)` writable while
  the loop was this module's macro: `it` was a parameter in binder
  position and kept the caller's spelling, while the template's `i`
  and `n` were renamed (`MAC-HYG-3`). Since 2026-09-03 `for` is a
  language KEYWORD (`docs/reference.md`, "`for` — the counted loop
  and the container loop") and the module's two loop macros are
  deleted; the keyword needs neither rule, because its binders are
  `for$i`, `for$n` and `for$v`, and `$` is `AX1001` inside an
  identifier, so nothing a caller writes can collide with them. 420's
  hygiene check — a `for` surrounded by a caller's own `i` and `n` —
  still holds, and now holds for that reason. `MAC-HYG-10` itself is
  unchanged and `Err.ax`'s `try!` still depends on it.
- **`MAC-HYG-6`/`MAC-HYG-7`** resolve every helper a template names at
  the definition site, and the module keeps a rule because of it:
  every such helper is declared in `Html.ax` — and declared `pub`,
  which was measured rather than assumed. `MAC-LANG-10` judges a
  template's private *macro* at the definition site, but a private
  *function* named by a template is refused at the invocation with
  `AX3023` `private-name`; the visibility of a free identifier is
  judged where the macro is used. Not yet a numbered rule, recorded
  here so it is not rediscovered.
- **`MAC-SAFE-1`** is applied in `el`/`elA`: the builder and the tag
  are each mentioned twice, so both are bound first.
- **`MAC-LANG-13`** decides that escaping is a run-time function
  (`hEscText`, `hEscAttr`) and that `</` inside `script`/`style` is
  rewritten at run time rather than refused at `check`.
- The limits it works around, each named in the header: no variadic
  expression macro (`MAC-LANG-14`'s decision, so children are a
  block), no macro generating a macro (`MAC-CAP-8`'s `AX3021`, so the
  tag table is written out, two lines per tag), no `{}` (so `div` and
  `divA` are two macros), no `:class` (the lexer), no dispatch on a
  head's spelling (`MAC-LANG-17`, so one macro per attribute name plus
  `attr`), and `MAC-EXP-14a`'s literal spans, of which the ~70 string
  literals in its templates are the densest exposure in the tree.
- **One measured refusal worth knowing before naming a macro**: a bare
  identifier that names a macro is a zero-argument invocation
  (`MAC-LANG-3`), and the expander reads TYPE positions too — a macro
  named `a` made every `(-> Int a Int)` in `Vec.ax` report `AX3018
  macro a takes 2 arguments, but was given 0`. The anchor element is
  therefore `anchor`, and `a`, `b`, `e`, `f` are unusable as macro
  names while any signature in scope spells them as type variables.

---

## 11. Conformance summary

| Area | Holds today | Planned | Refused |
|---|---|---|---|
| Language | LANG-1…12, LANG-14 (multi-rule over the declaration form — selected by ARITY for one day, and by a pattern MATCH in rule order since 2026-08-16, with arity surviving inside the match as a pre-filter), LANG-15 (four of its six pattern kinds), LANG-16 (v1: one repeating bare NAME as a rule's last element), LANG-18 | LANG-14 (rules over expression templates), LANG-15's last two kinds — a repeat over a PATTERN (LANG-16's second half) and a literal identifier (LANG-17) | LANG-13 |
| Expansion | EXP-1…17 (module-side invocation landed 2026-08-15) | — | — |
| Hygiene | HYG-1…8 (HYG-8's four holes are all closed, the last two on 2026-08-16; HYG-3a held-but-defective) | HYG-9 | — |
| Capabilities | CAP-1…3, CAP-6, CAP-7, CAP-8 (`fn`/`::`/`data`/`struct`/`type`/`effect`/invocation/iteration templates — the kind list closed 2026-08-15, and `impl` left it with the construct in 0.6.0), CAP-9 (the deriving clause refuses), CAP-10 (format strings; 10.5's capture CLOSED in 0.7.4) | CAP-4 | CAP-5 (replacement landed, and the table is now COMPLETE: join — in name, reference and argument position, nested to any depth — constructors, fields, same, for including its parallel form, binders, fold, name, arity, defined, format, formatln) |
| Safety | SAFE-1…4 | — | SAFE-5 |
| Integration | INT-1…6 | — | — |
| Diagnostics | DIAG-1…5 (DIAG-5's second snippet landed 2026-08-15) | — | — |
| Tooling | TOOL-1…6 (TOOL-6 held-but-defective) | — | — |

Six rules in the Holds column are held-but-defective, each with the
defect stated inline where it is defined —
`MAC-EXP-8` (the over-application diagnostic anchors at the expansion,
not the surplus argument), `MAC-EXP-11a` (the node budget counts
unexpanded nodes and its message blames macros that may not exist),
`MAC-EXP-14a` (a template literal keeps the defining file's byte
offsets), `MAC-HYG-3a` (a renamed binder is still RENDERED under its
gensym spelling; the `~>` half of that defect closed with
`MAC-TOOL-5` on 2026-08-15), `MAC-CAP-3a` (`AX3022` reports and then
emits the bad node anyway), and
`MAC-TOOL-6` (`fmt` rewrites what `check` refuses to lex).
`MAC-CAP-10.5` was the seventh until 0.7.4, when the format
lowering's last capturable name stopped being a name. This is [memory-model.md §9.0](memory-model.md)'s
convention; the list, not any one entry, is the argument for gating.

### 11.1 What is gated

| Pinned by | Rules |
|---|---|
| `tests/selfhost/360-macro.ax` (45) | LANG-1, EXP-6 (nested invocation), EXP-7 (double evaluation) |
| `tests/selfhost/361-macro-hygiene.ax` (143) | HYG-1, HYG-2 |
| `tests/selfhost/362-macro-coverage.ax` (57) | CAP-1 |
| `tests/selfhost/368-macro-qualified.ax` (47) | LANG-12 — the unfixed compiler refuses with two `AX3001`s |
| `tests/selfhost/369-macro-vs-function.ax` (15) | HYG-8.3 — the unfixed compiler answers 10, silently |
| `tests/selfhost/372-decl-macro.ax` (144) | CAP-8, EXP-16 — two invocations of one macro, nested generation, qualified module invocation; the unfixed compiler exits 1 |
| `tests/selfhost/373-decl-macro-types.ax` (10) | EXP-17 — type-position substitution recomputes the float flags |
| `tests/diagnostics/500-unknown-decl-head.ax` | CAP-8's unknown-head `AX3027`, twice — the parse no longer stops at the first |
| `tests/diagnostics/505-decl-macro-positions.ax` | CAP-8's position rules: both template kinds refused across the boundary, and the bare-identifier name rule |
| `tests/diagnostics/510-decl-macro-template-kind.ax` | CAP-8's template-kind `AX3021`, at the macro's own line |
| `tests/selfhost/381-macro-type-templates.ax` (32) | CAP-7/CAP-8's `data` and `struct` templates — joined constructor names, two invocations giving two distinct types, and `deriveEq` querying a type generated in the same round |
| `tests/selfhost/389-type-effect-templates.ax` (38) | CAP-8's `type` and `effect` templates — a joined alias name written in TYPE position by the signature beside it, and an effect whose name, operation and arrow all come from the invocation |
| `tests/diagnostics/565-macro-type-template-limits.axbad` | what still refuses — an `import` template and a nested `macro` at the macro's line (the fixture's two `AX3021` subjects are `badMacro` and `badImport`), and the reserved `syntax/` prefix in a data name and a constructor name, both positions the parser could not even express before (`.axbad`: a joined name at top level is a shape the formatter must not learn, the same reason `525` carries the extension) |
| `tests/selfhost/388-module-side-decl-macro.ax` (239) | EXP-16's module-side invocation — the prelude's derive spent by a module on its own type, a private product the module calls, and an entry-file name coexisting with the module's mangled one; the unfixed compiler refuses at the module's line |
| `tests/diagnostics/515-decl-macro-in-module.ax` | EXP-16's visibility rule — a generated declaration from a non-`pub` template is `AX3023` outside its module, and the module's own call to it still works |
| `tests/selfhost/374-derive-eq.ax` (101) | CAP-5/CAP-6 — §10.2's nullary deriveEq verbatim, the roadmap's acceptance criterion; the unfixed compiler dies parsing the joined name |
| `tests/selfhost/376-syntax-nested-for.ax` (7) | CAP-5 — nested syntax/for over two types, inner splice under the live outer binding |
| `tests/selfhost/386-syntax-parallel-for.ax` (63) | CAP-5's parallel `syntax/for` — the zip in all three positions, one bit each, positional past the first element; the unfixed compiler does not parse the file |
| `tests/selfhost/390-multi-rule-macro.ax` (51) | LANG-14's arity selection across three rules, each a template in its own right |
| `tests/diagnostics/585-multi-rule-misuse.ax` | LANG-14's refusals — two rules of one arity at the macro's line, and an invocation matching none, which names every arity the macro offers |
| `tests/diagnostics/575-syntax-parallel-for-misuse.axbad` | the zip's refusals — a skewed pair in each of the three positions, and a parallel binding that is not a pair (`.axbad`: the last is an expression to the parser and a non-shape to the grammar) |
| `tests/selfhost/387-syntax-nested-join.ax` (47) | CAP-5's nested `syntax/join` — a lens set over two structs sharing a field name, three-deep nesting, and the `getX`-twice collision that made the two-part form unusable |
| `tests/frontend/070-derive-macro.ax` (42) | the derive shape through check, run, symbols, :load, LSP and fmt in one place |
| `tests/selfhost/375-derive-lenses.ax` (34) | CAP-5's lens set — §10.3 verbatim: declaration/argument-position for, fields, same's spliced diagonal, field-name substitution |
| `tests/diagnostics/530-syntax-same-keys.ax` | syntax/same's refusals — cross-sequence comparison names both sequences; an unbound side names itself |
| `tests/diagnostics/535-syntax-for-toplevel.axbad` | declaration-position for outside a template, refused and re-tagged inert (`.axbad`: the formatter rewrites the shape) |
| `tests/selfhost/377-derive-eq-fieldful.ax` (30) | CAP-5's fieldful rung — binders' deterministic `p#i` spelling through the renamer, fold's parallel zip, the empty fold as the nullary case |
| `tests/diagnostics/540-syntax-fold-misuse.ax` | fold/binders refusals — zip-length mismatch, unknown constructor, sequence in scalar position, fold arity |
| `tests/selfhost/379-derive-imported.ax` (30) | CAP-9's shipped library — stdlib/Pre.ax's deriveEq over an entry-file type and an imported one |
| `tests/diagnostics/550-derive-private-type.ax` | the query visibility rule — a private subject refuses at the invocation, one diagnostic in the right place |
| `tests/selfhost/380-syntax-scalar-queries.ax` (41) | CAP-5's scalar rows — `syntax/name`, `syntax/arity`, `syntax/defined`, and a join standing as a callable reference; `stdlib/Pre.ax`'s `deriveArity` and the fixture's own copies of `deriveShow`/`showOr` are the consumers (the prelude's two are deprecated since 0.3.8, because the builtin `show` renders a value in full where they answered the constructor's name) |
| `tests/diagnostics/560-syntax-scalar-misuse.ax` | the scalar rows' refusals — an arity of nothing (naming `syntax/arity`, not the counter it shares a slot with), a bare query head, a non-identifier argument, a one-part join |
| `tests/diagnostics/520-syntax-query-misuse.ax` | CAP-6's closure — unknown query, wrong-kind subject, missing subject, all AX3028 |
| `tests/selfhost/382-format-macros.ax` (255) | CAP-10's lowering — eight independent claims, one bit each, so a partial regression names itself in the exit status: interpolation, escaped braces, the three alignments, signed zero-padding, both hex cases, precision, conversion-inside-padding, and the degenerate literals |
| `tests/stdlib/365-format.ax` | CAP-10 end to end, against a golden stdout — what actually reaches the descriptor |
| `tests/diagnostics/570-format-refusals.ax` | CAP-10.3's expander half — all eleven `AX3031` cases, each caret inside the literal on the offending byte |
| `tests/diagnostics/525-syntax-reserved.axbad` | CAP-6's reservation — syntax/ spellings outside a template, including the one-paren-short near-miss (`.axbad`: the formatter must not learn these shapes) |
| `tests/diagnostics/485-qualified-private-macro.ax` | LANG-12's `AX3023` route for a qualified private macro |
| `tests/diagnostics/490-expansion-backtrace.ax` | DIAG-4 — one frame and a nested two, spans verified against the macro's own file |
| `tests/diagnostics/580-expansion-fix-suppressed.ax` | TOOL-5 — the same two diagnostics from a macro and by hand: the expansion pair keeps its help text and loses its `~>`, the hand-written pair keeps both |
| `tests/selfhost/363-macro-shadowing.ax` (3) | EXP-5 |
| `tests/selfhost/364-macro-definition-site.ax` (157) | HYG-6, HYG-7 |
| `tests/selfhost/365-macro-pattern-literal.ax` (95) | HYG-5 |
| `tests/diagnostics/990-macro-arity` | EXP-8 |
| `tests/diagnostics/991-macro-recursion` | EXP-11 |
| `tests/diagnostics/992-macro-duplicate-parameter` | LANG-2 |
| `tests/diagnostics/993-macro-shadows-function` | LANG-8, TOOL-1 |
| `tests/diagnostics/400-macro-size-limit` | EXP-9 (node budget) |
| `tests/diagnostics/405-macro-depth-limit` | EXP-9 (depth budget) |
| `tests/diagnostics/430-private-macro` | LANG-9 |
| `tests/selfhost/370-pre-import.ax` (42) | INT-1 — `stdlib/Pre.ax` erases entirely into rewrites |
| `tests/selfhost/MacScope.ax` | the cross-module helper HYG-6 needs |
| `tests/fmt/parity/060-splice-refused.axp` | the backtick refusal LANG-16 would flip |
| `scripts/check-degenerate.sh` | SAFE-4 (four empty-form macro cases) |
| `scripts/check-diagnostics.sh` | every `tests/diagnostics/` case above, byte for byte against its checked-in AXDL golden, plus a silence sweep whose floor over `tests/selfhost/` is 150 files |
| `scripts/check-tree-sitter.sh` | INT-6 — `grammar.js`'s `macro_declaration` must parse every `.ax` in the repository |
| `scripts/check-reproducible.sh` | EXP-12 |
| `tests/lsp/drive.py`'s macro-navigation case | TOOL-2 and TOOL-3 — definition lands on the macro's own name, hover quotes its declaration, a non-macro name answers null, and both are derived from the document's bytes rather than from a golden |

Reproduce the macro corpus and its refusals directly:

```bash
scripts/check-self-host.sh 36        # 360-369, the macro corpus
scripts/check-diagnostics.sh 99      # 990-993 among them, the refusals
```

**The ablation behind the "was" column of every table in this
document** is a compiler built from the commit before expansion moved
ahead of the checker. Each case answers the middle column when built
that way and the right column when built from trunk, which is what
makes the fixture a measurement rather than a regression guard:

| Case | want | before | after |
|---|---|---|---|
| `361-macro-hygiene` | 143 | 208 | 143 |
| `362-macro-coverage` | 57 | 4 (`AX4003`) | 57 |
| `363-macro-shadowing` | 3 | 18 | 3 |
| `364-macro-definition-site` | 157 | 1 (`AX3004`) | 157 |

and one refusal that used to be an acceptance:

| Case | before | after |
|---|---|---|
| `993-macro-shadows-function` | `OK`, exit 11 | `AX3006`, exit 1 |

Unpinned, and therefore documentation rather than specification:
`MAC-LANG-3`'s two spellings of a zero-parameter invocation,
`MAC-EXP-6`'s ordering (that an unused argument is not expanded),
`MAC-LANG-10`'s private-macro-from-a-public-template case,
`MAC-LANG-11`'s last-definition-wins rule, and `MAC-EXP-14`'s span
assignment. Each is measurable in a fixture of a few lines, and each is
a rule a future change could break silently.

**Every documented limitation now has a fixture.** The last one
without — an entry-file macro's free identifier being capturable
(`MAC-HYG-8`.1) — was measured on 2026-08-15, found to be a SILENT
wrong answer rather than the loud failure this section claimed, and
made a refusal (`AX3032`). It stopped being a limitation on
2026-08-16: the reference resolves at the macro's own scope now, the
refusal is retired with its code, and the fixture measures the answer
(`tests/selfhost/394-macro-entry-capture.ax`, 130).
(This list held four on 2026-08-13, plus one wrong-answer bug:
`MAC-LANG-12`'s `Pre::when`-is-`AX3001` and `MAC-HYG-8`.3's
imported-macro-outranks were fixed and pinned on 2026-08-14 by
`tests/selfhost/368-macro-qualified.ax` and
`369-macro-vs-function.ax`, and `MAC-LANG-5`'s
declaration-position-is-`AX2003` became `MAC-CAP-8` v1, pinned by
`372-decl-macro.ax`.)

### 11.2 Are the limits normative?

`AX3019` names 128, and `AX3024` names 1024 and 2,000,000 — all three in
**user-visible diagnostic text**, so changing one changes a checked-in
`.axdl` golden. This specification's position: the limits are
**implementation-defined**, and a conforming implementation **MAY**
choose others, but each diagnostic **MUST** state the limit it enforced.
That is what makes the number a fact about the run rather than a
constant a reader has to look up, and it is why the goldens pin the text
rather than the value alone.

### 11.3 What is left

Three things, and they are the same three `MAC-LANG-14`–`MAC-LANG-18`
and the Language row of the conformance table name:

1. **`MAC-LANG-17` — literal identifiers**, where a head's *spelling*
   discriminates rather than its shape. It needs `MAC-HYG-9`'s scope
   sets, because two identifiers spelled alike are the same pattern
   only if they mean the same binding, and it is why §10.4's
   `simplify` table does not run yet.
2. **`MAC-LANG-16`'s second half — a repeat over a nested pattern**,
   binding each of that pattern's binders to a sequence in lockstep.
   Refused rather than half-built (§1.5).
3. **`MAC-LANG-14` over EXPRESSION templates.** Rules belong to the
   rule form today, because the two forms differ in what a template
   IS; extending them to the head-list form is a separate decision,
   not a port.

Everything else this list once scheduled has landed, and two of its
price estimates are worth keeping because they were measured and
wrong in the expensive direction — both are recorded where the feature
is specified rather than here. The imported-name capture was priced
against import edges the merged declaration list does not carry, and
needed only each declaration's own module (§3.4). The ellipsis was
priced at four implementations of the token set, and cost one, because
`...` lexes as an ordinary identifier (§1.5's table).
