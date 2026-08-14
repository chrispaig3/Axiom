# The Axiom Macro System

The normative specification of compile-time syntactic abstraction in
Axiom: what a macro is, when it expands, what it may and may not see,
what hygiene guarantees, and what a conforming implementation owes the
tools that read macro-generated code.

This document is the specification. [macros.md](macros.md) is the
measured status of the current implementation and the order the rest is
planned in; [v1-roadmap.md §4.2](v1-roadmap.md) is the design sketch
this expands. Where they disagree with this document, this document is
wrong until it is fixed.

**One disagreement was live when this document landed, and it
arbitrated.** `README.md` marked Macros **Complete** and asserted
"pattern-substitution expansion before sema with hygiene (scope sets +
gensym) … expansion backtrace on diagnostics". `CONTRIBUTING.md` marked
the same feature **Partial** — "no repetition, no declaration-level
macros, no derive" — and [macros.md](macros.md) agreed with it. The
binary agreed with the second: there are no scope sets (`MAC-HYG-2` is
renaming), no patterns (`MAC-LANG-14`), and the backtrace field is
populated by nothing (`MAC-DIAG-4`). The README row was corrected to
**Partial** on 2026-08-14. What the episode proves is kept here:
`check-doc-drift.sh` could not arbitrate, because its status-row rule
only checks that a **Complete** row names an existing fixture, never
that the row's prose is true — a false claim passed CI for as long as
it existed, and would again.

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
share with `fn`/`define`, every trait method and every effect operation.
(Exactly three namespaces exist: value, type, and none. Data
constructors, type aliases, struct field names, a trait's own name and
`impl` occupy *no* namespace and collide with nothing.)

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
[v1-roadmap.md §4.2](v1-roadmap.md), made explicitly and restated here
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

**MAC-LANG-14 (P).** A macro **SHALL** be a sequence of rules, each a
pattern and a template, tried in order:

```scheme
; today's single-rule form, unchanged
(macro (when test body) (if test body 0))

; the multi-rule form: a bare name, then rules
(macro when
  ((when test body)      (if test body 0))
  ((when test body else) (if test body else)))
```

The two forms are distinguished by one token of lookahead — `(macro (`
introduces a head list, `(macro <name>` introduces a rule list — so no
existing program changes meaning. Each rule's pattern repeats the macro
name in head position, as `syntax-rules` does.

*Today (2026-08-14):* the **rule-list surface exists, with exactly one
rule, and it is the declaration-macro form** — `MAC-CAP-8` parses
`(macro name ((name p ...) decl ...))`, the pattern head must repeat
the macro's name (`AX2001` otherwise), and the parameters are still a
flat positional list of distinct identifiers. What this rule still
specifies beyond that: multiple rules tried in order, non-identifier
patterns (`MAC-LANG-15`), and ellipsis (`MAC-LANG-16`). A mismatched
invocation is an arity error, never a fall-through to another rule.

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

**MAC-LANG-15 (P).** A pattern **SHALL** be one of:

| Pattern | Matches |
|---|---|
| an identifier | any single form, binding it |
| `_` | any single form, binding nothing |
| a literal integer, float, char or string | itself |
| `(p1 ... pn)` | a form of exactly *n* elements, each matching |
| `(p ...)` | zero or more forms matching `p` (`MAC-LANG-16`) |
| a **literal identifier** declared in the macro's literal list | itself, by *binding*, not by spelling (`MAC-LANG-17`) |

**MAC-LANG-16 (P).** Ellipsis repetition `...` **SHALL** be available in
both patterns and templates, and a template **MUST** use a repeated
binding under an ellipsis of the same depth.

*Today:* `...` does not lex. `.` is `TK_DOT`, never an identifier
character, so `...` is three separate tokens and `(macro (m x ...) ...)`
is `AX2001 expected identifier, found ` `.` ``.

The cost is stated here rather than discovered later. **Four
implementations of the token set must move together** — not three:

| Implementation | Role |
|---|---|
| `self_host/lexer.ax` | the compiler |
| `self_host/format.ax` | the formatter, with its own `FT_*` kinds |
| `tree-sitter-axiom/grammar.js` + `src/scanner.c` | the editor grammar |
| `tests/fmt/verify-fmt.py` | the independent formatter verifier |

and the checked-in refusal golden
`tests/fmt/parity/060-splice-refused.axp` becomes an acceptance.

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

**MAC-LANG-18 (P).** Rules are tried in order; the first whose pattern
matches wins. If no rule matches, the diagnostic **MUST** name the macro
and list the shapes it accepts — the arity diagnostic `AX3018`
generalised. Today's `AX3018` becomes the one-rule case of it.

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
be expanded**, and every one is: `fn` bodies, `impl` method
expressions, and trait **default** bodies (`expandDecl`'s three arms).
Pinned by `tests/selfhost/367-macro-in-impl.ax` (93), whose impl method
and trait default each invoke a macro — the unfixed compiler exits 4.

Until 2026-08-14 the pass walked `fn` declarations only, and trait and
`impl` bodies lower into ordinary declarations *after* it
(`lowerImpls`), so a macro invoked in either was never expanded at all
— the exact failure `MAC-EXP-1` was supposed to have eliminated,
surviving in the one place the pass did not reach:

```scheme
(macro (dbl x) (+ x x))
(trait (Doubler a) where (dub :: (-> a Int)))
(impl (Doubler Int) where ((dub (lambda (x) (dbl x)))))
(fn (main) (dub 21))
```
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
  argument. [macros.md](macros.md)'s table says "at the surplus
  argument"; measured, `(fn (main) (one 5 6))` reports at columns 17–18,
  which is the `5` the macro expanded to. A conforming implementation
  **SHOULD** anchor it at the surplus argument, which is the token the
  author can delete.

Both behaviours replace silent miscompiles: under-application used to
leave the parameter's own name in the emitted IR (`add i64 40, %q`,
rejected by `opt` as an undefined value), and over-application used to
drop the surplus argument **without evaluating it**.

### 2.3 Termination

**MAC-EXP-9 (H).** Expansion **MUST** terminate, and three independent
budgets enforce it. Each replaces a hang or a crash, and each reports
once rather than at every node after the first refusal.

| Budget | Limit | Diagnostic | What it bounds |
|---|---|---|---|
| instantiation depth | 128 | `AX3019` `macro-recursion-limit` | a macro that rewrites to itself |
| output tree depth | 1024 | `AX3024` `macro-expansion-limit` | nesting the parser would have refused in source |
| output node count | 2,000,000 | `AX3024` `macro-expansion-limit` | fan-out, which no depth limit can see |

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

*v1 limit:* phase D expands **entry-file invocations only**. An
invocation inside an imported module is `AX3027` with the reason in
the note (`tests/diagnostics/515-decl-macro-in-module.ax`): generated
declarations in a module would need the module's mangling and
visibility applied after import resolution has already run. The
refusal is what keeps the limit loud until that is built.

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
a `~>` replacement — the general form of which is `MAC-TOOL-5`.

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

### 3.4 What hygiene does not yet cover

**MAC-HYG-8 (P; two of the four closed 2026-08-14).** These four holes
**SHALL** close, and the second and third have. Each is stated
with what happens today, because each is a place a reader could
reasonably believe the guarantee is total:

1. **A macro defined in the entry file.** Entry-file declarations are
   left bare by import resolution — there is no `Mod$name` to resolve to
   — so a caller's local binding can still capture a template's free
   identifier. It is a loud failure rather than a wrong answer
   (`AX3004 expected function type, found Int`), but it is not a
   diagnostic about capture and it names neither the macro nor the
   binding that shadowed it.
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
   imported is still captured.** `MAC-HYG-7`'s rewrite tries exactly one
   spelling, `Mod$n` for the macro's *own* module. A template calling a
   function its module imported transitively finds no such declaration,
   stays bare, and is captured by the caller — the same
   one-macro-two-meanings failure `MAC-HYG-6` closed, in the case
   `MAC-HYG-6` does not reach. This hole was absent from
   [macros.md](macros.md) §3 until 2026-08-14 — the residue read as
   benign there; it is recorded now. Closing it means resolving a free
   identifier to its *true* defining module rather than to the macro's
   — and the measured blocker is that the merged declaration list has
   no import edges to resolve through: `resolveDeclsPhase` consumes
   each `(import ...)` during the merge and pushes nothing into the
   merged list, so which modules the macro's module imported is not
   recoverable after resolution. `MAC-LANG-12` closed without this (a
   qualified reference names its module in the source); this hole
   cannot.

**MAC-HYG-9 (P).** The mechanism **SHALL** become **scope sets**: an
identifier is a `(name, scopes)` pair rather than a bare name, every
expansion introduces a fresh scope, and resolution matches on both.

Renaming is a sound implementation of the *forward* direction and
nothing more. Scope sets are required by `MAC-LANG-17` (a literal
identifier must be comparable *as a binding*), by `MAC-HYG-8`'s first
hole (an entry-file macro has no mangled name to resolve to, but it does
have a definition scope), and by any nested-pattern macro where one
expansion's binder must be visible to another's template.

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

**MAC-CAP-4 (P).** With `MAC-LANG-14`–`MAC-LANG-18`, a macro **SHALL**
be able to dispatch on the *shape* of its arguments: arity, literal
heads, nesting, and repetition. This is what turns the current facility
from *substitution* into *pattern-based rewriting*, which is what
[v1-roadmap.md §4.2](v1-roadmap.md) means by tier 1.

### 4.3 Compile-time evaluation

**MAC-CAP-5 (R, with a replacement — v1 of the replacement landed
2026-08-14).** Compile-time evaluation of **user code** is refused
(`MAC-LANG-13`). What replaces it is a **closed, compiler-implemented
query vocabulary** evaluated by the expander over the declaration list
it already holds:

| Query | Status | Answers | Needed by |
|---|---|---|---|
| `(syntax/constructors T)` | **H** (v1: entry-file `T`, as a `syntax/for` sequence) | the constructor names of `data` type `T`, in declaration order | `derive` for any sum |
| `(syntax/arity C)` | P | the field count of constructor `C` | generated `match` arms |
| `(syntax/fields S)` | P | the field names of `struct` `S`, in declaration order | lenses, `Eq`, serializers |
| `(syntax/name x)` | P | the identifier `x` as a string literal | generated `Show` |
| `(syntax/join a b)` | **H** (declaration NAME position) | one identifier from two, the second's first letter upcased (`lens` + `Point` → `lensPoint`, `eq` + `Color` → `eqColor`) | naming generated declarations |
| `(syntax/defined n)` | P | whether `n` names a declaration | conditional derivation |
| `(syntax/same a b)` | P | whether `a` and `b` are the same **binding or declaration slot** — two answers naming field `f` of `S` compare equal, spelling alone never suffices; `MAC-LANG-17`'s binding comparison is the pattern-side instance | `deriveLenses`' diagonal (§10.3) |
| `(syntax/binders C p)` | P | `(syntax/arity C)` fresh identifiers derived from prefix `p` — the *same* sequence at every mention within one expansion, each a template binder that `MAC-HYG-2` renames | fieldful `derive` (§10.2) |
| `(syntax/for ((x xs) …) tpl)` | **H** (v1: one sequence, match-ARM position; the for-variable substitutes in constructor patterns, nested iterations compose) | `tpl` once per element, spliced in place; several sequences zip in lockstep and **MUST** have equal length — a mismatch is a diagnostic at the invocation | the iteration form |
| `(syntax/fold f z ((x xs) …) tpl)` | P | the right-fold `(f tpl₁ (f tpl₂ … z))` — `tpl` instantiated per element and nested under a two-argument head, since `&&` takes exactly two | chaining `&&` over field comparisons |

Two rows were RESPELLED on 2026-08-14, when implementation reached
them: this table wrote `syntax/defined?` and `syntax/same?`, and `?`
is deliberately not an identifier character in the lexer
(`lexer.ax`'s own comment reserves admitting it as a separate language
change), so the specified spellings could not lex. A spec whose
spelling the lexer refuses is wrong the moment someone types it; the
`?`-free names are the specification now.

The v1 rows are pinned by `tests/selfhost/374-derive-eq.ax` (101 —
§10.2's nullary `deriveEq`, the roadmap's acceptance criterion,
verbatim), `376-syntax-nested-for.ax` (7 — nested iteration over two
types), and `tests/frontend/070-derive-macro.ax` (42, through every
frontend consumer). A generated declaration whose name came from
`syntax/join` has **no source spelling**, so it records no span and
`axiom symbols` reports it positionless rather than claiming bytes
that spell something else.

`syntax/for` and `syntax/fold` are the only constructs that turn a
query's *sequence* answer into repeated output, and both are bounded by
the length of that sequence — which is a property of the program's
declarations, not of anything a macro computes. That is what keeps
`MAC-EXP-9`'s budgets a backstop rather than the primary termination
argument. (`syntax/for`'s one-sequence form `(syntax/for (x xs) tpl)`
is the common case and reads as before; the parenthesised-pairs form is
what the fieldful examples need.)

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

**MAC-CAP-7 (P).** "Type-level macro" in Axiom means **a macro that
generates type and instance declarations**, keyed on declared types via
`MAC-CAP-5`. It does **not** mean type-level computation, and cannot:
Axiom's type system has parametric polymorphism, aliases and traits, and
no type-level functions, no higher-kinded abstraction over them, and no
dependency of types on values. A macro cannot inspect an *inferred*
type at all, because expansion precedes inference (`MAC-EXP-1`).

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

- **Templates generate `fn` and `::` declarations, and further macro
  invocations** (resolved by the next fixpoint round). Any other
  declaration kind in a template — `data`, `struct`, `trait`, `impl`,
  `effect`, `import` — is `AX3021` **at the macro's own line**, before
  any invocation exists (`MAC-SAFE-4`'s loud-at-definition shape;
  `tests/diagnostics/510-decl-macro-template-kind.ax`).
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
- **Invocation is entry-file only** in v1; a module-side invocation is
  `AX3027` with the reason in the note (`MAC-EXP-16`'s limit,
  `tests/diagnostics/515-decl-macro-in-module.ax`).

Diagnostic: `AX3027` (`declaration-macro`) covers every way a
declaration-position invocation fails — see `axiom explain AX3027`.
What `derive` still needs from this rule is `data`/`struct` field
*inspection* (`MAC-CAP-5`/`MAC-CAP-6`), not more template kinds: a
`deriveEq` writes `fn` and `::` declarations only.

**MAC-CAP-9 (P).** `derive` **SHALL** be built on `MAC-CAP-8` and
`MAC-CAP-5`, not on a compiler-internal deriving mechanism.

*Today:* `deriving (Eq Show)` **parses and is discarded** — measured:
the clause's names never reach the AST, and a program carrying one
checks `OK`. That is the documented-but-inert shape this repository
keeps finding, and the next rule is the decision it demanded.

**The spelling is settled: explicit invocation.** `derive` is a library
of declaration macros — `(deriveEq T)`, written where the author wants
the instance — and the `deriving` clause **SHALL** be **refused** rather
than implemented: a clause that parses and is discarded is the
documented-but-inert failure class, and refusal is the smallest true
behaviour. The costs decided it. Threading `deriving`'s names into the
AST touches the parser, the node layout, AXSYM and the formatter, while
the explicit call needs only `MAC-CAP-8`; and the clause's corpus
population is **one file pair** — `tests/fmt/syntax-zoo.ax` and its
expected output, written deliberately by someone reading the parser to
pin the formatter's spelling of a clause the compiler ignores. The
refusal flips that fixture (and `reference.md`'s Deriving Traits
example), and those flips are the change's whole migration cost —
counted here so the commit that implements the refusal knows its blast
radius before it lands.

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
compiler: `MAC-EXP-9`'s three budgets, and node handle 0 guarded
everywhere the expander walks. `()` in a template is refused at the
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

```scheme
(macro (ignore x) 7)
;@axiom:effect(io)
(fn (main) (ignore (side 1)))     ; `side` performs IO — and is dropped
```
```
W AX3010 axtag-mismatch "AXTAG mismatch on `main`: `effect(io)` claim unsupported: missing IO"
```

The warning is **correct**: after expansion, `main` performs no I/O.
This is the intended interaction, not a defect, and a conforming
implementation **MUST** keep validating claims against the expanded
program — validating them against the source would let a macro's
rewrite silently falsify a claim in the other direction.

**MAC-INT-4 (P).** **Traits.** Traits and `impl` are implemented: an
`impl` lowers to an ordinary declaration named `Trait#Type#method`, and
a trait-method call is statically rewritten to a direct call to that
symbol, selected by the concrete type of the first argument. They are
*declarations*, so a macro can generate them only under `MAC-CAP-8` —
which is the mechanism `derive` needs and the reason `MAC-CAP-8` is the
highest-value planned rule in this document.

Two properties of that lowering bear on generated instances, and a
`derive` design **MUST** account for both. Impl symbols carry **no
module**, so two modules implementing the same `(Trait, Type)` pair pass
`check` and then fail in `opt` as an LLVM redefinition — there is no
coherence or overlap check, and a `derive` invoked in two modules for
one type would hit exactly this. And a function generic over a trait
cannot call the trait's methods: that program passes `check` and dies in
`opt` with `use of undefined value`, so generated code **MUST NOT**
assume dictionary-passing exists.

**MAC-INT-5 (H).** **The formatter.** `axiom fmt` formats a macro
declaration and its template as source; it does **not** format
expansions, which do not exist in the file. A conforming formatter
**MUST NOT** rewrite a template in a way that changes what it expands to
— which is not a hypothetical, since the formatter has independently
re-implemented the token set and has changed a literal's meaning before
(`0.05` became `0.5`).

**MAC-INT-6 (P).** **tree-sitter.** `tree-sitter-axiom/grammar.js` is
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
because expansion is semantic-analysis-time work. Seven codes exist
(macros.md listed five until 2026-08-14; it lists all seven now):

| Code | Slug | Fires when |
|---|---|---|
| `AX3018` | `macro-arity` | too few arguments (`MAC-EXP-8`) |
| `AX3019` | `macro-recursion-limit` | instantiation depth exceeded 128 |
| `AX3020` | `macro-duplicate-parameter` | two parameters share a name |
| `AX3021` | `macro-template-unsupported` | a template form substitution cannot handle — no reachable producer, by design (`MAC-CAP-2`) |
| `AX3022` | `macro-set-target` | a parameter used as a `set` target, given an expression |
| `AX3023` | `private-name` | a macro its module does not export — the general visibility code, reached by macros since `MAC-LANG-9` |
| `AX3024` | `macro-expansion-limit` | the output tree exceeded 1024 deep or 2,000,000 nodes |

`AX3006` (duplicate definition) also reaches macros (`MAC-LANG-8`).

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

**MAC-DIAG-5 (P; the location renders, the second snippet does not
yet).** With `MAC-DIAG-4`, the rendered form **SHALL** be:

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

The invocation stays primary — it is the line the author can change.

*Today:* the human renderer prints the frame as a note —
``= note: in this expansion of `deriveEq` (stdlib/Derive.ax:8:14)`` —
which names the macro and its declaration but does not open the second
file for a snippet. The data the snippet needs is on the frame since
`MAC-DIAG-4` closed; what remains is renderer work alone.

---

## 8. Tooling

**MAC-TOOL-1 (H).** A macro declaration **MUST** carry a real span. It
did not until recently, which also left the language server's
`documentSymbol` arm for macros dead since it was written, and made
`AX3006`'s "first defined here" line point nowhere.

**MAC-TOOL-2 (P).** The language server **SHALL** treat a macro
invocation as a reference to its declaration: go-to-definition jumps to
the `macro` form, hover shows the template, and `documentSymbol` lists
macros beside functions.

**MAC-TOOL-3 (P).** A conforming language server **SHALL NOT** expand
macros to answer a request that does not need it. Expansion is bounded
but not free (`MAC-EXP-10` measured 41.4 s on a fan-out probe), and the
budgets exist precisely because an editor cannot wait.

**MAC-TOOL-4 (P).** With `MAC-CAP-8`, `axiom symbols` **SHALL** list
generated declarations, attributed to the file containing the
invocation, and **SHOULD** mark them as generated so a reader can tell
why a name has no visible definition.

**MAC-TOOL-5 (P).** **Lints run on the program the author wrote, not on
the program expansion produced.** A diagnostic whose span lies inside an
expansion and whose fix would edit generated text **MUST NOT** be
offered as machine-applicable: there is nothing at that location to
edit. Concretely, a conforming implementation **MUST** suppress a
machine-applicable `~>` replacement whose span belongs to a generated
node, and **MUST NOT** emit a replacement string containing a renamed
binder (`MAC-HYG-3a`).

This is a rule about a hazard the language already has rather than a
future one: the AXDL grammar's `~>` field is consumed by tools that
apply it without asking.

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
[v1-roadmap.md §4.2](v1-roadmap.md) states, written out — and since
2026-08-14 the nullary form below is **measured, verbatim**:
`tests/selfhost/374-derive-eq.ax` is this section's macro, data type
and invocation, and it answers 101 from three `eqColor` probes on the
first complete run of the query vocabulary. The fieldful form further
down still waits on `syntax/binders` and `syntax/fold`.

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

Constructors *with* fields are the same shape one vocabulary rung up:
`syntax/binders` names a constructor's fields as fresh pattern binders,
the parallel forms of `syntax/for`/`syntax/fold` zip the two sides, and
the field comparison is written `(eq xi yi)` — dispatching through the
trait lowering `MAC-INT-4` describes, selected by the field's concrete
type per constructor. (An earlier revision called the fieldful case
"the honest edge" because nothing could name the *i*-th field of a
bound pattern; `syntax/binders` is the table row that closed it, argued
for exactly as `MAC-CAP-6` requires.)

The fieldful form generates an **`impl`**, not the free function the
nullary sketch above generates — and the difference is load-bearing,
not stylistic. Its own field comparisons dispatch through `Eq`, so a
derived type's instance must *be* an `Eq` instance for a containing
type's derive to find: `(deriveEq Point)` then `(deriveEq Shape)` works
precisely because the first left an `Eq#Point#eq` behind for the
second's `(eq xi yi)` to resolve to. An `impl` is a declaration, which
is exactly what `MAC-CAP-8` produces:

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
makes a *functional* accessor worth generating:

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

---

## 11. Conformance summary

| Area | Holds today | Planned | Refused |
|---|---|---|---|
| Language | LANG-1…12, LANG-14 (one rule — the declaration form) | LANG-14 (multi-rule), LANG-15…18 | LANG-13 |
| Expansion | EXP-1…15, EXP-16/17 (v1 — entry-file invocation, `fn`/`::`/invocation templates) | EXP-16 (module-side invocation) | — |
| Hygiene | HYG-1…7 | HYG-8, HYG-9 | — |
| Capabilities | CAP-1…3, CAP-6, CAP-8 (v1) | CAP-4, 7, 9 | CAP-5 (replacement's v1 landed: join, constructors, for) |
| Safety | SAFE-1…4 | — | SAFE-5 |
| Integration | INT-1…3, INT-5 | INT-4, INT-6 | — |
| Diagnostics | DIAG-1…4 | DIAG-5 | — |
| Tooling | TOOL-1, TOOL-6 | TOOL-2…5 | — |

Six rules in the Holds column are held-but-defective, each with the
defect stated inline where it is defined —
`MAC-EXP-8` (the over-application diagnostic anchors at the expansion,
not the surplus argument), `MAC-EXP-11a` (the node budget counts
unexpanded nodes and its message blames macros that may not exist),
`MAC-EXP-14a` (a template literal keeps the defining file's byte
offsets), `MAC-HYG-3a` (a renamed binder reaches a machine-applicable
fix as an unspellable token), `MAC-CAP-3a` (`AX3022` reports and then
emits the bad node anyway), and `MAC-TOOL-6` (`fmt` rewrites what
`check` refuses to lex). This is [memory-model.md §9.0](memory-model.md)'s
convention; the list, not any one entry, is the argument for gating.

### 11.1 What is gated

| Pinned by | Rules |
|---|---|
| `tests/selfhost/360-macro.ax` (45) | LANG-1, EXP-6 (nested invocation), EXP-7 (double evaluation) |
| `tests/selfhost/361-macro-hygiene.ax` (143) | HYG-1, HYG-2 |
| `tests/selfhost/362-macro-coverage.ax` (57) | CAP-1 |
| `tests/selfhost/367-macro-in-impl.ax` (93) | EXP-3a — the unfixed compiler exits 4 |
| `tests/selfhost/368-macro-qualified.ax` (47) | LANG-12 — the unfixed compiler refuses with two `AX3001`s |
| `tests/selfhost/369-macro-vs-function.ax` (15) | HYG-8.3 — the unfixed compiler answers 10, silently |
| `tests/selfhost/372-decl-macro.ax` (144) | CAP-8, EXP-16 — two invocations of one macro, nested generation, qualified module invocation; the unfixed compiler exits 1 |
| `tests/selfhost/373-decl-macro-types.ax` (10) | EXP-17 — type-position substitution recomputes the float flags |
| `tests/diagnostics/500-unknown-decl-head.ax` | CAP-8's unknown-head `AX3027`, twice — the parse no longer stops at the first |
| `tests/diagnostics/505-decl-macro-positions.ax` | CAP-8's position rules: both template kinds refused across the boundary, and the bare-identifier name rule |
| `tests/diagnostics/510-decl-macro-template-kind.ax` | CAP-8's template-kind `AX3021`, at the macro's own line |
| `tests/diagnostics/515-decl-macro-in-module.ax` | EXP-16's v1 limit — module-side invocation refused, at the module's own line |
| `tests/selfhost/374-derive-eq.ax` (101) | CAP-5/CAP-6 — §10.2's nullary deriveEq verbatim, the roadmap's acceptance criterion; the unfixed compiler dies parsing the joined name |
| `tests/selfhost/376-syntax-nested-for.ax` (7) | CAP-5 — nested syntax/for over two types, inner splice under the live outer binding |
| `tests/frontend/070-derive-macro.ax` (42) | the derive shape through check, run, symbols, :load, LSP and fmt in one place |
| `tests/diagnostics/520-syntax-query-misuse.ax` | CAP-6's closure — unknown query, wrong-kind subject, missing subject, all AX3028 |
| `tests/diagnostics/525-syntax-reserved.axbad` | CAP-6's reservation — syntax/ spellings outside a template, including the one-paren-short near-miss (`.axbad`: the formatter must not learn these shapes) |
| `tests/diagnostics/485-qualified-private-macro.ax` | LANG-12's `AX3023` route for a qualified private macro |
| `tests/diagnostics/490-expansion-backtrace.ax` | DIAG-4 — one frame and a nested two, spans verified against the macro's own file |
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
| `scripts/check-diagnostics.sh` | the seven macro AXDL goldens above, byte for byte, plus a silence sweep with a floor of 80 files over `tests/selfhost/` |
| `scripts/check-tree-sitter.sh` | INT-6 — `grammar.js`'s `macro_declaration` must parse every `.ax` in the repository |
| `scripts/check-reproducible.sh` | EXP-12 |

Unpinned, and therefore documentation rather than specification:
`MAC-LANG-3`'s two spellings of a zero-parameter invocation,
`MAC-EXP-6`'s ordering (that an unused argument is not expanded),
`MAC-LANG-10`'s private-macro-from-a-public-template case,
`MAC-LANG-11`'s last-definition-wins rule, and `MAC-EXP-14`'s span
assignment. Each is measurable in a fixture of a few lines, and each is
a rule a future change could break silently.

**One documented limitation has no fixture**, and it reproduces
exactly as documented — which is precisely the state in which a "fix"
can silently change behaviour with every gate still green: an
entry-file macro's free identifier is capturable (`MAC-HYG-8`.1).
(This list held four on 2026-08-13, plus one wrong-answer bug:
`MAC-LANG-12`'s `Pre::when`-is-`AX3001` and `MAC-HYG-8`.3's
imported-macro-outranks were fixed and pinned on 2026-08-14 by
`tests/selfhost/368-macro-qualified.ax` and
`369-macro-vs-function.ax`, `MAC-EXP-3a`'s `impl`-body miscompile by
`367-macro-in-impl.ax`, and `MAC-LANG-5`'s
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

### 11.3 The order the rest should land in

1. ~~**`MAC-LANG-12` + `MAC-HYG-8`**~~ — **landed 2026-08-14**, by
   splitting the reference instead of mangling the declarations:
   qualification works (hole 2), an entry-file function outranks an
   imported macro (hole 3), and a qualified private macro is `AX3023`.
   What remains under this heading: the entry-file capture (hole 1,
   which needs `MAC-HYG-9`'s scope sets) and the imported-name capture
   (hole 4, which needs import edges the merged declaration list does
   not carry).
2. ~~**`MAC-DIAG-4`**~~ — **landed 2026-08-14**, before the items that
   make diagnostics inside expansions more common, as this list
   ordered. The frame element is `(name, span, unit)`, the join is by
   invocation-span handle, and `MAC-DIAG-5`'s second snippet is what
   remains of the rendering.
3. ~~**`MAC-CAP-8`**~~ — **v1 landed 2026-08-14**, with `MAC-EXP-16`'s
   phase split: rule-form declaration macros generating `fn`/`::`
   declarations and further invocations, invoked from the entry file,
   parameters substituting in name, type and expression positions.
   What remains under this heading: module-side invocation
   (`MAC-EXP-16`'s stated limit) and the other template kinds
   (`AX3021` today, at the macro's line). The prerequisite for
   everything in §10.2–§10.5 now exists.
4. ~~**`MAC-CAP-5`/`MAC-CAP-6`**~~ — **v1 landed 2026-08-14**: the
   closed vocabulary exists and refuses (`AX3028`), and its three
   landed entries — `syntax/join` in name position,
   `syntax/constructors` as a sequence, `syntax/for` in arm position
   — are exactly the set §10.2's nullary `deriveEq` needs, which now
   runs verbatim (fixture 374, the roadmap's acceptance criterion).
   What remains under this heading: `syntax/fields`, `syntax/same`
   and declaration-position `syntax/for` (§10.3's lens set), then
   `syntax/binders`/`syntax/fold` (the fieldful rung), each landing
   as an H row in `MAC-CAP-5`'s table with its own fixture.
5. **`MAC-LANG-14`–`MAC-LANG-18`** — rules, patterns and ellipsis. The
   largest surface change, touching three implementations of the token
   set, and the one that should land last because the others do not
   depend on it.
