# The Axiom macro system

This is the specification for Axiom's macros: what a macro is, when it
expands, what it can see, what hygiene guarantees, and what tools can
rely on in the code a macro generates.

## In brief

A macro rewrites the program tree before type checking, so the code it
generates is checked like code you wrote. Axiom's macros are
pattern-based: a macro is a set of patterns and templates, and the
compiler never runs code from your file while compiling it.

This page gives the full contract, rule by rule. You need it if you
work on the expander, build tools that read macro-generated code, or
want to know exactly what a macro may do. To learn to write macros,
start with [Macros in the language reference](reference.md#macros).

## How to read this page

Every rule has a stable identifier, such as `MAC-LANG-3`. Compiler
messages and tests cite these identifiers, and they are never renamed.
Rules use the RFC 2119 keywords, such as **MUST**, **SHALL** and
**MAY**, and one of the status markers defined in
[memory-model.md §0](memory-model.md):

- **H** holds today, and the rule names the probe that shows it.
- **P** is normative but not yet implemented, and the rule says what
  happens instead.
- **R** is refused by design.

This page is also the status record for macros. Each rule names the
fixture that establishes it, instead of a status word. If anything else
in the repository disagrees with this page, treat this page as wrong
until it is fixed.

---

## 1. The macro language

### 1.1 Declaration form

**MAC-LANG-1 (H).** A macro is declared at top level:

```scheme
(macro (name param...) template)
(pub macro (name param...) template)
```

The name goes inside the head's parentheses, just as a function's
does. `template` is an expression, and the parameters are a flat
positional list of distinct identifiers. This is the head-list form.
§1.5 adds the rule forms.

**MAC-LANG-2 (H).** Two parameters with the same name are rejected with
`AX3020`.

**MAC-LANG-3 (H).** You can invoke a zero-parameter macro bare or in
parentheses, and both spellings mean the same thing:

```scheme
(macro (five) 5)
(fn (main) (+ five (five)))     ; 10
```

**MAC-LANG-3a (H).** Macros are order-independent, like every other
top-level declaration: you can invoke a macro above the line that
declares it. `(fn (main) (dbl 21))` placed above
`(macro (dbl x) (+ x x))` answers 42. Expansion has no "defined before
use" rule and **MUST NOT** gain one. The macro table is built from the
whole merged declaration list before any body is walked. A
`syntax/*` query naming a declaration another macro generates below
it waits for the round that generates it, and only a name no round
generates is `AX3028` (`tests/selfhost/1008-macro-query-order.ax`).

**MAC-LANG-4 (H).** A macro's own template is not expanded where it is
written. It is expanded once per invocation, against that invocation's
arguments. Expanding it in place would rewrite it against no arguments
at all.

**MAC-LANG-5 (H).** A macro invocation in declaration position expands
(`MAC-CAP-8` v1). A top-level form whose head isn't a declaration
keyword parses as a declaration-macro invocation. It resolves against
the same table as an expression invocation, with the same visibility
and the same qualified-name split.

If the head names no visible rule-form macro, as happens with a
mistyped keyword, the form is `AX3027`, and the message names the head.
Parsing carries on, so every unknown head in a file is reported:
`tests/diagnostics/500-unknown-decl-head.ax` reports both of its typos.

The two template kinds don't mix, in either direction, and each
mismatch is `AX3027` at the invocation. An expression macro can't stand
in declaration position, and a rule-form macro can't stand in
expression position. `tests/diagnostics/505-decl-macro-positions.ax`
pins both, along with a third refusal: a generated declaration whose
name was given an expression.

An expression macro whose template is written as a declaration, such as
`(macro (defTwo nm) (fn (nm) 2))`, still checks `OK` while nothing
invokes it (`MAC-EXP-1a`). Where it is invoked, it still expands as an
expression. Only the rule form generates declarations (`MAC-CAP-8`).

### 1.2 The compile-time environment

**MAC-LANG-6 (H).** A macro's expansion can see exactly three things:

1. the syntax trees of its arguments;
2. the identifiers written in its own template;
3. the program's merged declaration list, used for one purpose only:
   resolving a template's free identifiers at the macro's definition
   site (`MAC-HYG-6`).

It can't see types, inferred effects, the value of anything, or the
file system. A macro can't ask what type an argument has, because
expansion runs before the checker (`MAC-EXP-1`).

**MAC-LANG-7 (H).** Item 3 is the only introspection that exists today,
and the macro author can't reach it directly. The expander applies it
on the author's behalf to make hygiene work. `MAC-CAP-5` specifies
exposing it, through a closed vocabulary of queries the compiler
implements.

### 1.3 Namespaces and visibility

**MAC-LANG-8 (H).** Macros live in the value namespace, which they share
with `fn`/`define` and every effect operation.

Axiom has exactly three namespaces: value, type, and none. `data`,
`struct` and `type` occupy the type namespace and collide with each
other. Data constructors and struct field names occupy no namespace and
collide with nothing.

A macro and a function with the same name in one file is `AX3006`, and
both spans point at real source:

```text
error[AX3006]: duplicate definition `thing`
 --> thing.ax:3:6
  |
1 | (macro (thing x) (+ x 1))
  |         ----- `thing` first defined here
...
3 | (fn (thing n) (* n 2))
  |      ^^^^^ `thing` redefined here
```

**MAC-LANG-9 (H).** A macro is private to its module unless it is
written `pub`. When an `(import M (name))` carries a name list, the
macro must also appear in that list. Reaching a macro any other way is
`AX3023`:

```text
error[AX3023]: `privMac` is private to module `VisAll`
 --> 430-private-macro.ax:5:18
  |
5 |   (+ (pubMac 1) (privMac 2)))
  |                  ^^^^^^^ `privMac` is not exported by its module
```

Tested by `tests/diagnostics/430-private-macro.ax`.

**MAC-LANG-10 (H).** A `pub` macro whose template invokes a private
macro of its own module expands correctly from outside that module.
The expander tracks the definition site of the macro being
instantiated, and judges visibility against it. This is the same rule
`MAC-HYG-6` applies to free identifiers. For example, `(open 4)` from
another file answers 5, where `open`'s template calls its module's
private `secret`.

**MAC-LANG-11 (H).** The macro table is built in declaration order and
searched backward, so a later definition of a name wins. Import
resolution places an imported module's declarations ahead of the
importing file's, so this is also what lets an entry file's macro
shadow an imported one. The ordering is a language rule: changing it
changes which macro a program means.

**MAC-LANG-12 (H).** A macro name can be qualified as `Mod::name`, like
any other declaration:

- `(QualMac::qdbl 21)` expands.
- A zero-parameter macro's bare qualified spelling, `QualMac::qfive`,
  expands (`MAC-LANG-3`, through the same split).
- A qualified reference to a private macro is `AX3023` naming the
  module, not a false `AX3001`.

Pinned by `tests/selfhost/368-macro-qualified.ax` (47) and
`tests/diagnostics/485-qualified-private-macro.ax`.

The mechanism splits the reference instead of mangling the
declaration. `Mod::name` is not a distinct AST node: the parser
flattens it to `Mod$name`, the spelling import resolution writes onto
`fn`/`::` declarations. Macro declarations keep their bare names. The
lookup splits the reference, matching the bare part against the
macro's name and the module part against the module already stamped on
its declaration. This is `declMatches`' rule, the same one qualified
constructors use, and the checker's `isMacroName` applies the same
split so the two sides agree.

Mangling the declarations would have moved every bare-name behaviour
this page pins: `MAC-LANG-11`'s ordering, `MAC-LANG-8`'s collisions,
and five hygiene fixtures. Splitting the reference moves none of them.

Two things to know about qualified names:

- Two imported modules that define the same macro name still resolve a
  bare invocation last-wins, with no `AX3014`. `MAC-LANG-11` makes that
  a language rule, and qualifying the name picks one explicitly.
- In type position, the type grammar accepts the same `Mod::Name` and
  `Mod.Sub::Name` spellings that expressions do, answered by the same
  module-aware lookup (`parseTyQualChain`, with type compatibility
  decided by declaration rather than spelling). A bare type name that
  both modules define draws `AX3044`, which names the qualified
  spelling that settles it.

### 1.4 The no-evaluation invariant

**MAC-LANG-13 (R).** **The compiler MUST NOT execute code from a source
file during compilation.** Expansion is a rewrite and nothing else.

This rule records the choice between two tiers of macro system, and
everything else on this page follows from it:

- **Tier 1, pattern-based.** A macro is a set of pattern and template
  pairs, and expansion is a rewrite. This is Axiom's design.
- **Tier 2, procedural.** A macro is an Axiom function from syntax to
  syntax, run at compile time. It is strictly more expressive, and it
  requires the compiler to run arbitrary code from the file it is
  compiling.

Tier 2 **MUST NOT** be introduced as an implementation detail of
tier 1. It changes the compiler's threat model, so it needs a sandbox,
a resource policy and an explicit decision. A macro that wants
arithmetic is not a reason to add an evaluator.

You can observe the invariant: the compiler evaluates nothing, not even
constant arithmetic in its own output (`MM-EXEC-14`).

### 1.5 Pattern macros

**MAC-LANG-14 (H).** A macro **SHALL** be a sequence of rules, each a
pattern and a template, tried in order. Rules belong to the rule forms.
There are two, one per template kind, so no rule has to guess its kind
from its head:

```scheme
; The head-list form: one template, which is one expression.
(macro (when test body) (if test body 0))

; The declaration rule form: a bare name, then one or more rules.
; Each rule is a pattern and a template of declarations.
(macro deriveTag
  ((deriveTag T)      (:: (syntax/join tag T) Int)
                      (fn ((syntax/join tag T)) 1))
  ((deriveTag T base) (:: (syntax/join tag T) Int)
                      (fn ((syntax/join tag T)) base)))

; The expression rule form: the same shape, but each template is
; one expression.
(emacro total
  ((total x) x)
  ((total x rest ...) (+ x (total rest ...))))
```

One token of lookahead tells the forms apart: `(macro (` starts a head
list, and `(macro <name>` starts a rule list. `emacro` always takes a
rule list. No existing program changes meaning, and one rule is a rule
list of length one. Each rule's pattern repeats the macro's name in
head position, as Scheme's `syntax-rules` does.

Selection is a match, not a count (`MAC-LANG-15`, `MAC-LANG-18`). The
rules are tried in order, and the first whose pattern matches wins. A
pattern may be a binder, `_`, a literal or a parenthesised shape.
Arity still acts as a pre-filter, because a rule with a different
element count can't match. `tests/selfhost/390-multi-rule-macro.ax`
(51) selects across three arities, and
`tests/selfhost/392-macro-patterns.ax` (127) selects among rules of one
arity by shape.

Two refusals follow from this:

- A rule that can never be reached is refused at the macro's own line
  with `AX3033`. See `MAC-LANG-18`.
- An invocation that matches no rule is `AX3018`, and the message names
  every shape the macro accepts.

`tests/diagnostics/585-multi-rule-misuse.ax` pins both.
`tests/diagnostics/600-macro-rule-unreachable.ax` and
`tests/diagnostics/605-macro-no-rule-matches.ax` pin each on its own.

This rule holds in full. A rule list takes one or more rules, in either
of two forms:

- `(macro name ((name p ...) decl ...) ...)`, whose templates are
  declarations (`MAC-CAP-8`);
- `(emacro name ((name p ...) expr) ...)`, whose templates are one
  expression each.

Each pattern's head must repeat the macro's name. Each parameter is a
pattern (`MAC-LANG-15`), and selection is a match in rule order
(`MAC-LANG-18`). Ellipsis (`MAC-LANG-16`) and literal identifiers
(`MAC-LANG-17`) both hold. An invocation that matches no rule is
refused. It never falls through past the last rule.

A pattern whose head doesn't repeat the macro's name is `AX2003`, a
bare `syntax error`. `parseDeclMacro` reports it with `pErr`, which
carries no expectation. Unknown declaration heads have a better message
(`MAC-LANG-5`), and this refusal doesn't have one yet.

The two rule forms exist because a template's kind can't be read from
the template. In the declaration rule form, a template is
declarations. So in `(macro when ((when test body) (if test body 0)))`,
the template `(if test body 0)` is read as a nested declaration-macro
invocation of `if`. Invoking `when` in expression position is then
`AX3027`, "declaration macro `when` invoked in expression position".

Deciding the kind from the template's head isn't sound either. A
declaration template's first form can legitimately be a nested
invocation: `372-decl-macro.ax`'s `defPair` generates two. So the
head-list form stays single-template, `macro` rules generate
declarations, and `emacro` rules generate expressions. Multi-rule
expression macros earn their place because patterns, ellipsis and
literals give them something to select by. By arity alone they would
add little, since a single template already takes whatever arity it
declares. Tested by `tests/selfhost/403-expr-rule-macro.ax` (153).
`tests/diagnostics/612-emacro-misuse.ax` pins the two `emacro`
refusals: an `emacro` in declaration position, and an invocation that
matches no rule.

**MAC-LANG-14a (P, prerequisite).** Patterns are not a distinct
syntactic category today, and a pattern-macro design must say what it
does about that. `(Cons h t)` in match position is an ordinary
`TAG_E_APP`, and its tag can't tell it from an application. Only
`TAG_P_CON0` (a parenthesised nullary constructor) and `TAG_P_CONNAMED`
(a named-field pattern) are pattern-specific. Whether a form is a
pattern depends on its position.

A conforming implementation **MUST** choose one of these, and this
specification chooses the second:

1. Introduce a real category of pattern nodes. This changes the tag
   numbering that `expand.ax`, `typecheck.ax` and `codegen.ax` all
   index by number. Those numbers are the AST's wire format between the
   parser and its readers, which is why the retired `foreign` tag 29 is
   documented as never reusable.
2. Keep pattern-ness positional. A macro that expands into pattern
   position expands into an expression, which the enclosing `match`
   then reads as a pattern.

Choice 2 costs nothing structurally. It has one consequence that
**MUST** be stated: a macro can't tell whether it was invoked in
pattern or expression position, so a macro usable in both **MUST**
expand to a form that is valid in both.

**MAC-LANG-15 (H).** A pattern **SHALL** be one of:

| Pattern | Matches | Status |
|---|---|---|
| an identifier | any single form, binding it | Holds |
| `_` | any single form, binding nothing | Holds |
| a literal integer, float, char or string | itself | Holds |
| `(p1 ... pn)` | a form of exactly *n* elements, each matching | Holds |
| `(p ...)` | zero or more forms matching `p` (`MAC-LANG-16`) | Holds. A repeat over a nested pattern binds each binder in lockstep (`tests/selfhost/397-nested-repeat.ax`, 170) |
| a literal identifier declared in the macro's literal list | itself, compared by binding rather than spelling (`MAC-LANG-17`) | Holds, by canonical-spelling comparison. Scope sets are still provisional. `tests/selfhost/402-literal-dispatch.ax` (19), `tests/diagnostics/611-macro-literal.ax` |

In the fourth row, `...` is this page's shorthand for "p1 through pn",
not the ellipsis operator. That is why that row cites no rule and the
fifth does.

A pattern's head is an ordinary binder unless the rule list reserves it
as a literal. So an unreserved nested pattern tells forms apart by
their shape, never by the spelling of their head: `(m (h T))` matches
`(m (anything X))`. Rules written `((defOp (unary T)) ...)` and
`((defOp (binary T)) ...)` are the same pattern, and every invocation
takes the first. Patterns can tell rules apart in exactly three ways:

- the shape of a nested form;
- the value of a literal;
- a reserved head's binding (`MAC-LANG-17`). §10.4's `simplify` table
  needs this for its `+` and `*` heads, and
  `tests/selfhost/403-expr-rule-macro.ax` rewrites `(+ a 0)` to `a`.

The representation takes `MAC-LANG-14a`'s choice 2 literally. A pattern
is an ordinary expression node in a slot the parser knows is a pattern,
so no tag was added and none was renumbered. A nested pattern is
`mkEApp`'s left spine, the same tree an application gets. That is what
makes a pattern and an argument comparable at all: both come out of
the same parser.

`MAC-LANG-14a` requires the consequences of that choice to be stated.
There are three, and each is the parser showing through:

- `((f x) y)` is the same tree as `(f x y)`, because a spine doesn't
  record where its parentheses were. This is symmetric, so two forms
  spelled alike still match. But two rules whose patterns differ only
  this way are one pattern, and the second is dead without drawing
  `AX3033`.
- `(p)` is the bare binder `p`. A one-element form loses its
  parentheses on the argument side too, so this is symmetric, and the
  irrefutability test is right to call such a rule irrefutable. An
  author who wrote the parentheses expecting a shape gets a rule that
  matches everything, and `AX3033`'s help says so by name.
- A parenthesised pattern never matches a keyword-headed form.
  Arguments are parsed by the ordinary expression parser, so
  `(if p q r)`, `(let ((p 1)) p)`, `(lambda (p) q)` and `(match …)`
  arrive under their own tags, not as spines. A shape pattern of the
  right element count refuses them, and the invocation falls through to
  a more general rule. A macro that must accept those shapes takes them
  with a plain binder.

A literal pattern compares values, not spellings, in all four kinds.
`10` matches `1_0`, `1.0` matches `1.00`, and `"\t"` matches an
argument written as a real tab. The parser decodes integers and floats
on the way in. A string node keeps its lexeme verbatim, because the
emitter relies on that, so the matcher decodes strings as it compares.

A rule's parameters are its patterns' binders, nested ones included,
and `AX3020` rejects a repeated one. `((m a (f a)) ...)` binds `a`
twice, and `expParamIndex` is last-wins, so the first binding would be
silently discarded. `_` is exempt because it binds nothing.

**MAC-LANG-16 (H).** Ellipsis repetition `...` **SHALL** be available in
both patterns and templates, and a template **MUST** use a repeated
binding under an ellipsis of the same depth.

One element per rule may repeat. In `(m T v ...)`, `T` takes one
argument and `v` takes any number after it, including none. In the
template, `(f v ...)` splices them in where the pair stands. That is
the variadic macro `MAC-CAP-10.4` says the language lacks.
`tests/selfhost/393-macro-ellipsis.ax` (63) is one rule generating both
a two-field constructor call and a three-field one.

The repeating element can also be a nested pattern. `(m (f a) ...)`
matches every absorbed argument against `(f a)`, and binds each binder
to the sequence of what it bound, in order. An empty tail matches, with
empty sequences. `tests/selfhost/397-nested-repeat.ax` (170) is six
macros over this shape.

A template rebuilds a repeated form once per element, with each
sequence-bound name taking its element, in four positions:

| Template | Rebuilds | Tested by |
|---|---|---|
| `(f a) ...` | an application spine | `tests/selfhost/397-nested-repeat.ax` (170) |
| `arm ...` | one `match` arm per element | `tests/selfhost/398-arm-ctor-splice.ax` (155) |
| `C ...` | one data constructor per element | `tests/selfhost/398-arm-ctor-splice.ax` (155) |
| `decl ...` | one whole declaration per element | `tests/selfhost/399-decl-splice.ax` (45) |

Arm and constructor splices are what §10.5's machine macro needs for
its step function and its `data`, so that machine now expands.
`398-arm-ctor-splice.ax` ends with the Door machine, end to end.

In a spliced arm, a sequence-bound name in the pattern is a test, not a
binder: `(Off)` matches only `Off`. Substituting the element there
unconverted would bind, and so match everything. That is the silent
wildcard `expSubstPatForSpine`'s note records for the `syntax/for`
path. So the splice converts a sequence-bound bare name to the
nullary-constructor test before the single-arm path renames binders.

The same rule applies one level down, in constructor patterns. A fixed
nullary test rebuilds as itself, and a sequence-bound field of a named
pattern tests its element. This mirrors what the `syntax/for`
substitution does for its own iteration variables. A parameter that
stands in a field binder but was given something other than a name is
refused as `AX3035`.

A declaration splice goes through the ordinary single-declaration
path, so names, types and bodies substitute exactly as they do in a
written declaration. `399-decl-splice.ax` has three macros over it: a
`fn` and a `::` over parallel sequences, a `data` building two boxed
types, and a nested invocation rebuilt once per element. Among template
declarations, a bare `...` parses as the invocation `(...)` already
did, so no wire format changes. Outside a template it keeps its
ordinary meaning: `(...)` at top level is `AX3027`, and a bare `...`
there is `AX2001`.

These are still refused:

- a repeat beneath a repeat, which would bind sequences of sequences;
- a repeat inside a spliced declaration, arm body or spine, which would
  use one sequence at two depths and rebuild it n-squared times;
- a marker on its own, which follows nothing;
- a `...` standing where an arm stands in ordinary code, which is
  diagnosed where it stands rather than spliced.

The depth rule is `AX3034`, `macro-ellipsis`. Its refusals are split
by where the author can act
(`tests/diagnostics/610-macro-ellipsis-misuse.ax`):

- At the macro's line: two `...` in one rule, and a repeat beneath a
  repeat.
- At the invocation: a repeating name used without `...`, and `...`
  after something that doesn't repeat. Without this refusal, the first
  would surface as `AX3001 undefined variable`, blaming the name.
- At the invocation, inside a splice: a marker that follows nothing,
  and a repeat nested inside a spliced declaration, arm body or spine.
  The check walks the whole form, not one application level, so a
  nested marker never re-splices the whole sequence inside every
  element.

Selection composes with `MAC-LANG-18` by turning a repeating rule's
arity into a floor. A fixed rule and a repeating rule with the same
fixed count are both live. The fixed rule takes its own arity, and the
repeating rule takes everything above it. `AX3033` tells covering one
arity apart from covering a range.

A repeated name binds a sequence rather than a value, and
`MAC-LANG-15`'s representation can't carry one: a match flattens to a `Vec String` of names beside a `Vec node` of forms,
and `expParamIndex` then `vecGet` spends each name on exactly one node.
So a repeat has its own channel on the environment, modelled on the
for-binding stack that `syntax/for` uses (`expForLookup`).

`...` lexes as an ordinary identifier. Three dots are one token, and
there is no new token kind. `self_host/lexer.ax` meets byte 46 (`.`),
looks at the next two bytes, and emits `TK_IDENT` spanning all three
when they are dots too, or `TK_DOT` for a single one. A lone `.` is
untouched, so field access, module paths and `MAC-HYG-3`'s gensym
separator are untouched too. One dot still can't sit inside an
identifier.

Reading the ellipsis as an identifier is why only one implementation
had to change. Each was checked by running
`(macro m ((m T a ...) (:: (syntax/join z T) Int) …))` through it:

| Implementation | What it does with `...` |
|---|---|
| `self_host/lexer.ax` | Changed. It was the only one that refused it. |
| `self_host/format.ax` | Accepts it unchanged. The rule form's interior is copied verbatim, and the ellipsis survives a format byte for byte. |
| `tree-sitter-axiom/grammar.js` | Parsed it already, with no `ERROR` node, because its identifier rule admits `.`. It now has an `ellipsis` node, which marks the element before it as repeating. That is a fidelity change, not a fix. |
| `tests/fmt/verify-fmt.py` | Unaffected. It models no macros. |

`tests/fmt/parity/060-splice-refused.axp` is a different feature. It is
`` (macro (all es) `(+ ,@es)) ``, a quasiquote splice, and `...`
doesn't make it acceptable.

Two facts make the syntax more delicate than a token addition sounds:

- The three implementations already disagree. `format.ax` has
  `FT_BACKTICK` and `FT_COMMAAT` token kinds that the compiler's lexer
  doesn't, and treats `'`, `` ` ``, `,` and `,@` as prefixes attached
  to the following form. So `axiom fmt` accepts and rewrites source
  that `axiom check` refuses lexically. tree-sitter's identifier rule
  admits `.`, `?`, `~` and `@`, which `lexer.ax` doesn't.
- `.` already has three jobs: field access, the module-path separator,
  and the hygiene gensym separator, which `MAC-HYG-3` relies on being
  unspellable. Claiming `...` for repetition doesn't break that. Any
  design that makes `.` gluable would, and would need a different
  gensym separator. The only free bytes with no lexical meaning are
  `$`, `?`, `@`, `` ` `` and `~`.

**MAC-LANG-17 (H, subset).** A rule list **MAY** declare literal
identifiers, written `(macro name (literals lits...) rules...)`. A
literal matches only itself, and is compared by binding, not by
spelling:

```scheme
(emacro simp (literals + *)
  ((simp (+ a 0)) a)
  ((simp (* a 1)) a)
  ((simp other) other))
```

Here `(simp (+ x 0))` rewrites to `x`, and `(simp (- x 0))` falls
through to the last rule.

The comparison uses canonical spellings: the module's own declaration,
the single visible declarer, or the builtin. Spellings that nothing
binds agree by spelling. So a pattern `+` meaning the Prelude operator
doesn't match an invocation whose `+` the call site declared itself.
That shadow veto is what makes this a comparison of bindings rather
than spellings. A qualified `Pre::+` does match, although the spellings
differ.

This matters for a branching macro that dispatches on `else`: it must
see *the* `else` it means, not any identifier a caller happened to name
`else`. A literal binds nothing, never takes a parameter slot, and
makes its rule refutable. A declared literal that no pattern spells is
`AX3066` at the macro's own line. Tested by
`tests/selfhost/402-literal-dispatch.ax` (19) and
`tests/diagnostics/611-macro-literal.ax`.

Scope sets would add little on top of this. Renamed heads are spelled
`name.N` with an unspellable separator, so a renamed head never spells
a literal by accident. Constructor heads compare by spelling, because
call-head resolution covers `fn` declarations, which is the operator
namespace the dispatch needs. `MAC-HYG-9` stays provisional for the
representation change, and the dispatch doesn't wait on it.

**MAC-LANG-18 (H).** Rules are tried in order, and the first whose
pattern matches wins. If no rule matches, the diagnostic **MUST** name
the macro and list the shapes it accepts. This is the arity diagnostic
`AX3018`, generalised, and the single-rule arity message is its
one-rule case.

Both halves hold. `AX3018` reads:

```text
no rule of macro `defN` matches this invocation; it accepts (defN (a b)) or (defN T 7)
```

The shapes are the rules' patterns as the author spelled them. They are
joined from the tokens each pattern consumed, not printed back from the
tree: a float pattern holds its bits and a char its codepoint, so
printing either back would show a spelling nobody wrote.
`tests/diagnostics/605-macro-no-rule-matches.ax` pins it.

Ordering has one cost. A rule whose every element is a plain binder is
irrefutable: it matches every invocation of its arity, and starves any
later rule of that arity. That is decidable from the patterns alone,
and it is refused at the macro's own line as `AX3033`,
`macro-unreachable-rule`. Several rules of one arity are fine when
something else tells them apart: `392-macro-patterns.ax` has three told
apart by shape, and §10.4's `simplify` table has seven.

An unreachable rule has its own code because it is a different mistake
from a repeated parameter, which is `AX3020`,
`macro-duplicate-parameter`. `AX3033` is pinned by
`tests/diagnostics/600-macro-rule-unreachable.ax`, and by
`585-multi-rule-misuse.ax`, which checks that two all-binder rules of
one arity are still refused.

---

## 2. The expansion model

### 2.1 Position in the pipeline

**MAC-EXP-1 (H).** Expansion is a pass of its own
(`self_host/expand.ax`). It runs over the merged declaration list,
**after import resolution and before the type checker**.

This position is normative. The checker sees the expanded program, so
what a macro generates is checked exactly like code you wrote:

| A template that… | Result |
|---|---|
| calls an undefined name | `AX3001` at the invocation |
| under-applies a function | `AX3013` at the invocation |
| generates a non-exhaustive `match` | `AX3005`, the same code a hand-written `match` draws |
| uses `while`, `set` or a field access | compiles and answers correctly |

**MAC-EXP-1a (H).** A macro that is never invoked is never checked. Its
template isn't walked, so an undefined name, a type error or an
unsupported form inside it produces no diagnostic. A template only
becomes a program at an invocation. A conforming implementation
**MAY** check templates on their own. This specification doesn't
require it, because a template's meaning depends on its arguments, and
most useful templates don't type-check in isolation.

**MAC-EXP-1b (H).** If expansion reports any error, the compiler
renders those diagnostics and exits without running the checker. So
expansion refusals never appear alongside type errors, and their order
is stable: expansion diagnostics are merged ahead of the checker's.

**MAC-EXP-2 (H).** Everything a macro generates **MUST** be
type-checked exactly as hand-written code is, exhaustiveness included.
The checker has no exemption for generated code, and there **MUST NOT**
be one. The same `match` written by hand and by a macro draws the same
diagnostic, and that is the property a hygiene mechanism exists to
protect.

**MAC-EXP-3 (H).** A function body is expanded in place: the result is
written back into the declaration node, not rebuilt around it. Import
resolution returns a merged list that shares declaration nodes with the
entry list the checker also holds. Rebuilding would expand one view of
the program and leave the other unexpanded.

**MAC-EXP-3a (H).** Every body that can contain an expression **MUST**
be expanded, and every one is. Only `fn` has such a body today, and it
is `expandDecl`'s one arm. The rule names a class of mistake: lowering
a body into ordinary declarations after the expansion pass has run. A
macro invoked in such a body would never be expanded.

The checker wouldn't catch that, because of a residual path in
`checkApp`. For any application whose head names a visible macro, it
checks only the arguments and answers a silent wildcard. On the
driver's path, an unexpanded macro means expansion already refused, and
the process exits before checking (`MAC-EXP-1b`).

That `checkApp` arm exists for the language server, which keeps
checking a broken file. There, its silence stops a wrong `AX3001`
from landing on top of the expansion's own diagnostic. The same
silence would hide a body the pass doesn't walk, so a commit that adds
a new kind of body **MUST** add its arm to `expandDecl`.

### 2.2 The algorithm

**MAC-EXP-4 (H).** Expansion walks an expression structurally, carrying
a **bound-name set**: the names bound by every enclosing binder at that
point.

**MAC-EXP-5 (H).** A form is a macro invocation when the identifier at
the head of its application spine (a) is not in the bound set and
(b) names a visible macro. Condition (a) comes first, so a macro name
never outranks a binder:

```scheme
(import IO)

(macro (v) 9)

(:: f (-> Int Int))
(fn (f v)
  v)

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let (
    (a (f 1))
    (b (let ((v 2))
      v))
    (c v)
  )
    {
      (println "{a} {b} {c}")
      0
    }))
```

```text
1 2 9
```

Inside `f` and the inner `let`, `v` is a bound name. Only the free `v`
is the macro.

**MAC-EXP-6 (H).** Instantiating a macro takes three steps, in order:

1. Expand each argument that the macro will consume.
2. Substitute them into the template, renaming every binder the
   template introduces (`MAC-HYG-1`) and resolving every free
   identifier at the definition site (`MAC-HYG-6`).
3. Expand the result, so a template that invokes another macro expands
   too.

Steps 1 and 3 make expansion a fixpoint.

Step 1 is where expansion time and run time part company, and the
distinction **MUST** be kept:

- At expansion time, every argument the invocation supplies is
  expanded exactly once. That includes an argument the template never
  mentions, and a surplus argument beyond the macro's arity. So a macro
  invocation inside an unused argument is still expanded, and still
  counts against `MAC-EXP-9`'s budgets.
- At run time, an argument is evaluated once per occurrence of its
  parameter in the template: twice if it's mentioned twice
  (`MAC-EXP-7`), and not at all if the template drops it. That is the
  one position `MM-EXEC-4` lists where a macro argument goes
  unevaluated.

**MAC-EXP-7 (H).** An argument is substituted as syntax, so a template
that mentions a parameter twice evaluates that argument twice:

```scheme
(macro (twice x) (+ x x))
(twice (readLine))          ; reads twice
```

This follows from substitution and isn't a defect. `MAC-SAFE-1` says
what a macro author owes because of it.

**MAC-EXP-8 (H).** Arity is checked in one direction only:

- Too few arguments is `AX3018`.
- A longer spine isn't an error. Exactly *arity* arguments feed the
  macro, and the surplus is applied to whatever the macro produced.
  That is how a macro that expands to a function stays usable. When
  the application is wrong, it's an ordinary type error:
  `(macro (one x) x)` invoked as `(one 5 6)` is
  `AX3004 expected function type, found Int`, not `AX3018`.

The diagnostic anchors at the expansion, not at the surplus argument.
`(fn (main) (one 5 6))` reports at column 17, which is the `5` the
macro expanded to. A conforming implementation **SHOULD** anchor it at
the surplus argument, which is the token the author can delete. That
gap is `MAC-EXP-8`'s recorded defect.

No implementation meets that SHOULD yet. `spanOf` in
`self_host/typecheck.ax` gives an application its callee's span, so
giving the expander-built application the surplus argument's span
changes nothing by itself. Reading the stored span instead would move
every application's anchor: `((if c f g) x)` reports at `c` today.

The checker also can't tell a surplus application from any other after
expansion. The callee is arbitrary macro output, no span for the whole
invocation survives, and the expansion frame is joined by pointer
identity on the invocation span, which a surplus application doesn't
carry. Carrying that provenance would take a new node tag, a borrowed
word, or a side table passed through every expand and check step. That
is too much for an anchor.

The cheap alternative makes things worse. Anchoring wherever the stored
span differs from the callee's moves a parameter-headed application
such as `(app 5 6)` from its argument, which the author can fix, to the
invocation, which only names the macro. So the rendering stays held but
defective.

### 2.3 Termination

**MAC-EXP-9 (H).** Expansion **MUST** terminate, and five independent
budgets enforce it. Each reports once, not at every node after the
first refusal. In the phase column, E is expression expansion and D is
declaration expansion (`MAC-EXP-16`).

| Budget | Limit | Phase | Diagnostic | What it bounds |
|---|---|---|---|---|
| instantiation depth | 128 | E | `AX3019` `macro-recursion-limit` | a macro that rewrites to itself |
| output tree depth | 1024 | E | `AX3024` `macro-expansion-limit` | nesting the parser would have refused in source |
| output node count | 2,000,000 | E | `AX3024` `macro-expansion-limit` | fan-out, which no depth limit can see |
| declaration rounds | 128 | D | `AX3019` `macro-recursion-limit` | a declaration macro that regenerates its own invocation |
| generated declarations | 10,000 | D | `AX3024` `macro-expansion-limit` | a declaration template that fans out |

The phase column is why the last row exists. The phase E budgets are
counted inside `expandExpr`, and `expandProgram` runs phase D first, so
a template that generates declarations never reaches them. The round
budget bounds phase D's depth. The declaration budget bounds its width:
without it, a template that generates three invocations of itself per
round reaches gigabytes of memory within a second, and the operating
system kills the compiler with no diagnostic.

Tested by `tests/diagnostics/401-decl-macro-size-limit.ax` and
`tests/diagnostics/406-decl-macro-round-limit.ax`.

**MAC-EXP-10 (H).** The output depth and node budgets exist because the
parser's own limits measure the source, and expansion produces the
program. A template 500 deep invoked 120 times nests 620 deep in the
file and 60,000 deep in the tree. Without a budget, that tree depth
would overflow the stack in `check`, `run`, `symbols` and `axiom lsp`.

Fan-out is worse. `(macro (m x) (+ x x))` doubles per level, so a
140-byte file with 26 nested invocations expands to 2²⁶ nodes. Expanding
them all would take `check` tens of seconds and leave the language
server unresponsive. The node budget refuses the program instead:

```scheme refused
(macro (m x) (+ x x))
(fn (main) (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m 1)))))))))))))))))))))))))))
```

```text
$ axiom check fan.ax
error[AX3024]: macro expansion produced more than the limit of 2000000 forms
 --> fan.ax:2:85
  |
2 | (fn (main) (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m (m 1)))))))))))))))))))))))))))
  |                                                                                     ^
  |
 --> fan.ax:1:9
  |
1 | (macro (m x) (+ x x))
  |         ^ in this expansion of `m`
  |
  = note: the parser's own nesting limit measures the SOURCE, and this limit measures what expansion produced from it
  = help: expansion is a rewrite, so the program the compiler sees is the expanded one; make the macro produce less, or write the repeated part as a function and let the macro expand to a call
  = help: run `axiom explain AX3024` for a full explanation

compilation failed due to 1 previous error
```

**MAC-EXP-11 (H).** An invocation of `(macro (loopy x) (loopy x))` is
`AX3019`: it stops at the instantiation-depth budget of 128.

**MAC-EXP-11a (H;).** The two output budgets share
`AX3024`, and the message tells them apart: *"nested deeper than the
limit of 1024 forms"* or *"produced more than the limit of 2000000
forms"*. Only nodes that expansion produced are counted. Inside an
instantiation (`expDepth` > 0), every node visited was produced by
expansion or reached through such a node, so both budgets apply there
and only there. The parser's own limits already bound source depth.
Counting source nodes would let a large macro-free file hit a budget
whose message blames macros that don't exist.

### 2.4 Determinism

**MAC-EXP-12 (H).** Expansion **MUST** be deterministic. The gensym
counter, which numbers the fresh names hygiene creates, is a per-run
monotonic integer. It is never an address or a hash of one, so emitted
IR stays byte-identical across runs (`scripts/check-reproducible.sh`).

**MAC-EXP-13 (H).** The expander's counter **MUST** be separate from
the type checker's. The checker names type variables `_tN`, those names
are printed inside `AX3004` messages, and the AXDL goldens pin them
byte for byte. Renaming a binder must not renumber a type variable.

### 2.5 Spans

**MAC-EXP-14 (H).** Every node a template produces carries the span of
the invocation, and every node that came from an argument keeps its own
span.

The reason applies to every node. A template node's own span indexes
the file the macro was *defined* in, and a `Diag` carries one unit. A
diagnostic anchored at a template node would point at a real line of
the wrong file. That reads as a correct diagnostic about unrelated
code, which is worse than pointing nowhere.

**MAC-EXP-14a (H;).** Every template literal is
rebuilt with the invocation's span (`expRebuildLit`). Integer, string,
float and char literals carry their value in word A and nothing else,
so the rebuild is exact. A diagnostic anchored at a literal indexes the
unit it is reported against, not the defining file's bytes.

The same question applies to the sub-nodes `MAC-EXP-14b` names, and
this specification answers it the same way: a node that reaches a
diagnostic **MUST** carry a span that indexes the unit the diagnostic
is reported against.

**MAC-EXP-14c (H, prerequisite).** `MAC-EXP-14` says "the span of the
invocation", and for some node kinds there is no such span. A span is
a two-word record of half-open byte offsets into one source text, with
no line, column or file identity. A node's span is an anchor token,
such as a head, a keyword or a binder name, and never the extent of the
form. And `if`, `{}` blocks, `match`, `while`, `handle` and match arms
carry no span at all. A variadic `if` is nested `if`s, so the same
holds for it.

So a macro invoked in one of those positions has nothing to inherit. A
rule phrased as "the expansion inherits the span of the form it
replaced" can't be implemented there. A conforming implementation
**MUST** give every node a span before `MAC-DIAG-4` can be honoured. It
**SHOULD** decide at the same time whether a span is an anchor or an
extent. An IDE feature such as "select this expansion" needs extents,
and that changes every construction site in the parser.

**MAC-EXP-14b (H).** Four positions inside otherwise-handled template
forms are not substituted. A macro parameter placed in one is used as a
literal name, not replaced by its argument:

| Form | Unsubstituted position |
|---|---|
| field access / field store | the field name |
| struct construction | the type name |
| `alloc` | the type operand |
| `handle` | the effect-name list |

Each position is a name, not an expression, so this is by design. It is
easy to miss, though, and more so for `alloc`, whose type operand is
never resolved either (`MM-VAL-21`). A conforming implementation
**SHOULD** diagnose a macro parameter in one of these positions instead
of passing its name through.

This implementation warns. A parameter in one of the four positions
draws `AX3074` (`macro-parameter-name-position`) at the invocation,
under the macro's expansion frame. It is a warning, not a refusal,
because refusing would break templates that mean the literal spelling.
A field name that an enclosing `syntax/for` binds is exempt, since the
iteration substitutes it.

Tested by `tests/diagnostics/1007-macro-param-name-position.ax`: five
warnings (field access and field store each draw one) over a program
that still checks clean, and nothing for a literal field or a
`syntax/for`-bound field.

**MAC-EXP-15 (H).** Because of `MAC-EXP-14`, a diagnostic from inside
an expansion anchors at the invocation, in the file being compiled. It
names the macro in an expansion frame (`MAC-DIAG-4`). Here is a library
whose macro calls a function that doesn't exist, saved as `MacLib.ax`:

```scheme
; A library macro whose template names a function that does not exist.
(pub macro (bad x) (noSuchFunction x))
```

And `probe.ax`, which invokes it:

```scheme fragment
(import MacLib)

(fn (main) (bad 1))
```

```text
$ axiom check probe.ax
error[AX3001]: undefined variable `noSuchFunction`
 --> probe.ax:3:13
  |
3 | (fn (main) (bad 1))
  |             ^^^ no binding named `noSuchFunction` in scope
  |
 --> MacLib.ax:2:13
  |
2 | (pub macro (bad x) (noSuchFunction x))
  |             ^^^ in this expansion of `bad`
  |
  = help: variables must be defined (via `define`/`fn`, a `let` binding, or a lambda parameter) before they are used; check for typos
  = help: run `axiom explain AX3001` for a full explanation

compilation failed due to 1 previous error
```

The error points at the line you wrote, and the frame tells you which
macro produced the code.

### 2.6 Phases

**MAC-EXP-16 (H).** With declaration macros
(`MAC-CAP-8`), expansion is a two-phase pass over the declaration list:

1. **Phase D** expands invocations in declaration position and appends
   their results to the declaration list. It repeats to a fixpoint
   under the budgets of `MAC-EXP-9`. A macro invoked in phase D **MAY**
   produce further declaration invocations: `defPair` in
   `tests/selfhost/372-decl-macro.ax` generates two. The round budget
   bounds the number of rounds, and a round that resolves nothing new
   ends the fixpoint.
2. **Phase E** expands invocations in expression position inside every
   declaration body.

Phase D completes before the declaration list is fixed, because name
resolution, `declNamespace` and the checker all read that list. A
generated function's body can invoke expression macros, and a later
declaration can call a generated function. Order doesn't matter, as
for everything else at top level (`MAC-LANG-3a`). Phase D runs after
import resolution, so an invocation can name an imported macro
qualified (`QualMac::qmk` in fixture 372), and a generated declaration
can refer to imported names.

Phase D also expands invocations inside imported modules. A
declaration generated in a module needs the module's mangling and
visibility, and import resolution has already run by then. So phase D
applies them itself, from records that import resolution builds as it
goes: the bare-to-`Mod$name` mapping, and a (module, import filter)
table. A generated declaration is therefore indistinguishable from a
written one on the module's side too. That is `MAC-EXP-17` extended by
one namespace.

Three rules decide what leaves the module. Each is the rule a
hand-written declaration already follows:

- The template's own `pub` decides whether the product is exported.
  It's the only signal available, since an invocation can't carry
  `pub`, and it's the right one: a library that derives says what it
  publishes, as it does for the functions it writes. The templates in
  `stdlib/Pre.ax` say `pub`. A module-local `derive` that omits it
  keeps its products to itself. The module's own calls to them still
  work, because privacy is about what leaves a module, not what the
  module may do.
- The import's name list applies to a generated name as it does to a
  written one. It can't be applied at the usual point, because the
  name doesn't exist yet when the module's declarations land. So import
  resolution records the filter against the module, and phase D asks
  for it. `(import M (a))` beside a generated `pub b` is `AX3023` on
  `b`.
- The query vocabulary answers from the invocation site. A module
  deriving over its own type asks about a name its neighbours can see,
  whatever an importer's name list says. Reading the rule as "visible
  from the entry file" would make a module's own `pub data` refuse
  inside the module that declared it, whenever an importer's name list
  left it out. That is the kind of coupling a module system exists to
  prevent.

Import resolution (in `codegen.ax`) and phase D (in `expand.ax`) share
one implementation of these rules, in `self_host/namespace.ax`. Because
`codegen.ax` imports `expand.ax`, the helpers can live in neither file,
and one copy keeps the two passes from drifting apart.

Not yet: a pipeline that re-expands an already-resolved program, such
as codegen's re-expansion or the REPL's type probe, carries no mangling
records. A module-side invocation that reaches one is `AX3027`, which
names that limit instead of generating a declaration nothing can name.

`tests/selfhost/388-module-side-decl-macro.ax` is the positive test. A
module spends the prelude's `deriveEq` and `deriveArity` on its own type
and calls a private product, and the entry file's own `eqSignal` sits
beside the module's mangled one. `tests/diagnostics/515-decl-macro-in-module.ax`
pins the visibility refusal.

**MAC-EXP-17 (H).** A declaration a macro generates is
indistinguishable, to every later pass, from one the author wrote. The
checker types it. The duplicate-definition check sees it, so a
fixed-name template invoked twice is `AX3006` on the second generated
declaration. Codegen emits it. A generated signature's per-arrow float
flags are recomputed from the substituted type, not copied from the
template's tokens: in `tests/selfhost/373-decl-macro-types.ax`,
`(defT idFloat Float)` is float-typed end to end.

---

## 3. Hygiene

Hygiene works in two directions. A binder that a template introduces
must not capture a name from the call site (§3.1, §3.2). A free
identifier in a template must mean what it meant where the macro was
written (§3.3). Both hold today. §3.4 records the four holes hygiene
had, all now closed, and `MAC-HYG-9` covers the planned move to scope
sets.

### 3.1 Binders a template introduces

**MAC-HYG-1 (H).** A binder introduced by a template **MUST NOT**
capture a name from the call site. That holds for a `let` binder and
for a `match` arm's pattern binder alike:

```scheme
(macro (addTo x) (let ((tmp 100)) (+ tmp x)))
(let ((tmp 1)) (addTo tmp))          ; 101

(macro (orElse o d) (match o ((Some v) d) ((None) d)))
(let ((v 42)) (orElse (Some 8) v))   ; 42
```

If the template's `tmp` and `v` captured the caller's, these would
answer 200 and 8.

**MAC-HYG-2 (H).** Hygiene works by renaming. At each expansion, every
binder the template introduces is renamed, and so is every reference to
it inside the template. That covers `let` and `let mut` binders,
`lambda` parameters and `match` arm pattern binders.

**MAC-HYG-3 (H).** The fresh name is `<name>.<counter>`, such as
`tmp.1`. This shape can't collide with anything, on either side:

- Source can't spell it. The lexer reads `.` as `TK_DOT`, never as part
  of an identifier, so `(let ((tmp.1 5)) tmp.1)` is `AX2001`.
- LLVM accepts it. `.` is legal in an unquoted LLVM identifier, so the
  renamed binder survives codegen's register naming with nothing to
  escape: `llc` accepts `%tmp.1`.

**MAC-HYG-3a (H;).** Because source can't spell a
renamed binder, a renamed binder is useless in a diagnostic. A
conforming implementation **MUST** render a renamed binder under its
original spelling in every diagnostic, and **MUST NOT** emit one inside
a `~>` replacement.

Here a typo inside a template draws a suggestion. It names `tmpvar`,
the spelling you wrote, and not the renamed `tmpvar.0`:

```scheme refused
(macro (m x) (let ((tmpvar x)) (+ tmpvarr 1)))    ; note the typo
(fn (main) (m 5))
```

Checked as `leak.ax` with `--diagnostic-format=ai`, the compiler
reports:

```text
E AX3001 leak.ax:2:13-14 undefined-variable "undefined variable `tmpvarr`" #"no binding named `tmpvarr` in scope" ?"a similarly named binding `tmpvar` is in scope; did you mean this?" &leak.ax:1:9-10:"m"
```

The suggestion carries no `~>` replacement either. A diagnostic with an
expansion frame drops its machine-applicable replacements
(`MAC-TOOL-5`, the general form of this rule). Its span is the
invocation's, so an applied edit would land in the wrong text, and an
edit writing `tmpvar.0` would write a token the lexer refuses
(`AX2001`).

`offerScope` strips a scope candidate at its first `.` and `#` before
offering it, so the distance, the stored best match and the suggestion
all use the original spelling. `emitAX3012`, `emitSetOnParam` and
`emitSetCaptured` render the same stripped spelling in the message, the
label, the helps and the replacement. In an expansion, `MAC-TOOL-5`
disarms that replacement; in hand-written code it stays.
`tests/diagnostics/654-macro-hygiene-suggestion.ax` pins the suggestion
(`tmpvar`, no `~>`), with a hand-written `count` control that keeps its
`~>"count"`. `tests/diagnostics/580-expansion-fix-suppressed.ax` shows
`tmp` where the renamed spelling would otherwise appear.

**MAC-HYG-4 (H).** The expander rebuilds nodes and never mutates them.
Returning a template's own node would make one node reachable from
every call site. That is safe only while nothing writes to a node, and
renaming writes.

### 3.2 Pattern position

**MAC-HYG-5 (H).** Three bare names in pattern position are not binders
and **MUST NOT** be renamed: `true`, `false` and `_`.

`true` and `false` in a pattern are literal tests. The emitter compares
the scrutinee against 1 and 0, and the checker binds nothing. Renaming
`true` to `true.1` would turn the test into a binder: the arm would
match everything, every later arm would be unreachable, and
`(isTrue false)` below would answer 1. The same `match` would then
answer differently when a macro wrote it, which is the silent wrong
answer hygiene exists to prevent.

```scheme
(macro (isTrue b) (match b ((true) 1) ((false) 0)))
(isTrue false)                          ; 0
(match false ((true) 1) ((false) 0))    ; 0, the same by hand
```

Nothing else is exempt. A bare constructor name in pattern position
*is* a binder in Axiom, which is why `(Nil)` needs its parentheses. So
renaming it is correct, and the existing hygiene cases depend on it.
The expander walks past a constructor spine's head rather than renaming
it. A named-field pattern's field names belong to the struct, so they
aren't binders either.

### 3.3 Free identifiers in a template

**MAC-HYG-6 (H).** A free identifier in a template means what it meant
where the macro was written. This is the reverse direction. Without it,
one macro means different things depending on where you call it. In
this table, the template calls `helper`: the macro's module defines one
that gives 50, and an entry file defines its own that gives 6.

| Call site | Without this rule | With it |
|---|---|---|
| an entry file that defines its own `helper` | 6, the entry's | 50, the macro module's |
| a function inside the macro's module | 50 | 50 |
| under a caller's `(let ((helper 0)) ...)` | `AX3004 expected function type, found Int` | 50: the local can't capture it |

The first row is silent. The captured name really is in scope at the
call site, so nothing reports it.

**MAC-HYG-7 (H).** The mechanism costs nothing outside the expander.
Import resolution already mangles an imported `fn` or `::`
declaration's name to `Mod$name`. So the name a free identifier should
resolve to already exists as a declaration name, and rewriting the
reference to it is enough.

The rewrite applies only when `Mod$name` really is a declaration. That
keeps it away from `+`, from constructors (which aren't mangled) and
from names the macro's module merely imported. Each of those finds
nothing, stays bare and resolves outward as usual. `MAC-HYG-8` item 4
adds a fallback for the imported case.

<a id="34-the-four-holes-hygiene-had-and-what-each-cost"></a>
### 3.4 Four holes, all closed

**MAC-HYG-8 (H; all four closed, the last two on).** These
four holes **SHALL** close, and all four have. Each item records the
failure the hole caused, because that failure is the argument for the
mechanism that closed it.

1. **A macro defined in the entry file.** Import resolution leaves
   entry-file declarations bare, so there is no `Mod$name` to resolve
   to. A caller's local binding could capture a template's free
   identifier, and the result was a silent wrong answer. An entry-file
   `(macro (useHelper v) (helper v))` invoked under
   `(let ((helper (lambda (y) 0))) …)` answered 0, where the macro's own
   `helper` answers 40, with no diagnostic.

   The fix needs one bit, not the scope sets `MAC-HYG-9` describes. A
   macro is a top-level declaration, so its template's free identifiers
   had no enclosing local scope where they were written: each one names
   something at the top level. `substTpl` stamps each free identifier
   with `setNodeDefScope` (node word 10). Both resolvers skip the local
   scope for a stamped reference: `checkVar` in the checker, and
   `emitVar` and `dispatchCall` in the emitter.

   Both resolvers must carry the bit. With only the checker taught, the
   program type-checks against the macro's `helper` while the emitter
   still calls the local. The head of a call never passes through
   `emitVar`, which is why `dispatchCall` needs the bit too.

   A template's own binders must not be stamped. A generated function's
   parameters reach the same code path. They aren't renamed, because a
   fresh function has nothing to be protected from, and stamping them
   makes `tests/selfhost/372-decl-macro.ax` fail with
   `AX3001 undefined variable x`. Instead, an environment scope of their
   own binds them while the body is substituted.

   Pinned by `tests/selfhost/394-macro-entry-capture.ax` (130).
   `AX3032`, the refusal that stood in before the fix, is retired
   because it would reject correct programs. It is out of the registry,
   so `axiom explain` no longer answers it. Its number is never reused,
   which is the rule for every code, retired or live.
2. **A qualified reference to a macro.** Closed: `MAC-LANG-12` holds,
   by splitting the reference rather than mangling the declarations.
3. **An imported macro outranking an entry-file function of the same
   name.** Closed. A bare invocation of a name that a bare `fn` or `::`
   declares resolves to the function, as `findFnEnt` does for entry-file
   names. The exception is a macro from the invocation site's own
   module. The macro stays reachable by qualification. Pinned by
   `tests/selfhost/369-macro-vs-function.ax` (15; a compiler without the
   fix answers 10).

   Without the fix, the failure was silent when the arities agreed: the
   macro's answer, 10, and no diagnostic. When they disagreed, the
   report was about the wrong thing: ``AX3018 macro `when` takes 2
   arguments, but was given 1``. Within one file, the collision is always
   caught (`MAC-LANG-8`).
4. **A free identifier naming something the macro's module merely
   imported.** Closed. `MAC-HYG-7`'s rewrite tries one spelling,
   `Mod$n` for the macro's own module. A template calling a function its
   module imported found no such declaration, stayed bare and could be
   captured by the caller. That is the same one-macro-two-meanings
   failure as `MAC-HYG-6`, in a case `MAC-HYG-6` doesn't reach.

   The fix needs no import edges. Import resolution consumes them:
   `resolveDeclsPhase` reads each `(import ...)` and pushes nothing into
   the merged list, so the macro module's imports can't be recovered
   afterwards. But every merged declaration records the module it came
   from (`nodeModule`), so the list itself says which module declares a
   name. When `Mod$n` isn't a declaration, `expQualify` falls back to
   the unique `pub` declaration whose bare name is `n`, and rewrites to
   that.

   Unique, or nothing. Two modules declaring the name is `AX3014`'s
   ambiguity, and the rewrite has no more right to choose between them
   than a bare reference does. So it leaves the name alone, and the
   invocation reports `AX3014` with the expansion frame naming the
   macro. Taking the unique match is sound because a template naming
   something its module couldn't see wouldn't have compiled where it
   was written. The rewrite chooses among modules the macro's module
   reached. It doesn't search the world.

   Pinned by `tests/selfhost/391-macro-imported-name.ax` (31), over the
   modules `LibImp`, `HelpImp`, `MidImp` and `DeepImp`. Two of its five
   bits are the hole: a local at the invocation, and the unshadowed
   two-meanings case. Three are controls. One control covers
   precedence: a name the macro's module both declares and imports
   resolves to its own, because the `Mod$n` spelling is tried before the
   search. The search reaches through two import edges, which shows it
   walks the merged list and not only direct imports. A compiler
   without the fix refuses the file with the retired `AX3032`. With
   that one term removed, it answers 13 rather than 31.

**MAC-HYG-9 (P).** The mechanism **SHALL** become scope sets. An
identifier becomes a `(name, scopes)` pair rather than a bare name,
every expansion introduces a fresh scope, and resolution matches on
both.

Renaming is a sound implementation of the forward direction and nothing
more. What still needs scope sets is `MAC-LANG-17`: a literal
identifier is compared by binding, and comparing bindings needs both
sides to carry theirs. Read this rule as scoped to that. Two other
cases turned out not to need them:

- `MAC-HYG-8`'s first hole, the entry-file macro, only needed one side
  to carry the fact that it had no local definition scope. One bit on
  the reference says so, with no change to what an identifier is (see
  `MAC-HYG-8` item 1).
- Nested-pattern macros, where one expansion's binder must be visible
  to another's template, work through textual substitution: the outer
  `substTpl` renames before the inner invocation expands.
  `tests/selfhost/1004-macro-nested-shadow.ax` (46) pins it.

`MAC-LANG-17` still makes that comparison by canonical spelling, with
the shadow veto, and will until a failing shape says otherwise. Scopes make the binding
available, not the comparison.

The migration **MUST** preserve every case gated today. A conforming
implementation that replaces renaming with scope sets **MUST** keep
`tests/selfhost/361-macro-hygiene.ax` (143), `362-macro-coverage.ax`
(57), `363-macro-shadowing.ax` (3), `364-macro-definition-site.ax`
(157) and `365-macro-pattern-literal.ax` (95) answering exactly those
values. It **MUST NOT** change the emitted IR's determinism
(`MAC-EXP-12`).

The migration happens inside the expander. Scopes become the decision
procedure inside substitution, and renamed spellings stay the output
encoding that everything downstream reads. After expansion, the checker
resolves by spelling on fully renamed output. That is sound exactly when
substitution gives each reference its correct binder's spelling, and
scope resolution decides that at substitution time. Nothing downstream
needs the pairs:

- the def-scope stamp (node word 10) stays the downstream encoding of
  "top level";
- the `.N` shape stays, because the checker strips it for display
  (`emitAX3012` and the others in `MAC-HYG-3a`);
- the `fresh` counter keeps numbering binder spellings in push order,
  so the output bytes don't move.

The migration has four steps:

- **M1, landed.** The expander carries a scope track beside the rename
  table `ren`: `(name, scopes)` records for every template binder and
  `syntax/for` binding (its state words 24 to 28). Under
  `AXIOM_VERIFY_SCOPES=1`, every reference the rename table hits is resolved both ways, and a
  parting is `AX3075`.
- **M2, landed.** Lookup sites resolve through scope records, taking
  the innermost visible binder, and answer the record's assigned
  spelling. Template binders still took precedence over `syntax/for`
  bindings at this step. Goldens stayed byte-identical, selfhost
  answers stayed identical and the bootstrap fixpoint held. `ren` is
  still written in lockstep, but no longer read for decisions.
- **M3, landed.** Precedence is innermost-wins. `syntax/for` bindings
  take part as ordinary inner binders, ordered against template binders
  by push order. The one corpus program where the two orders differed,
  a `syntax/for` binding inside a template `let` of the same spelling,
  is `tests/diagnostics/1009-macro-for-innermost.ax`. It draws two
  `AX3001`, because the field names `x` and `y` arrive where no
  variable is bound. `AX3075`'s precedence shape retired with the old
  order, and every other golden stayed byte-identical.
- **M4, planned.** Delete `ren`: its pushes, lookups, truncations and
  lockstep asserts. Spelling assignment stays on the `fresh` counter at
  the same push sites, so output bytes still don't move, and the test
  battery proves it. `AX3075`'s remaining shape, drift, retires with
  the second track, and its number is never reused. After M4, binders
  are `(name, scopes)` pairs from push to emission.

Until M4, `AXIOM_VERIFY_SCOPES=1` still checks the two tracks against
each other. Any `AX3075` now means drift: a push or truncation that
reached one track and not the other. That is a compiler bug, not a
program bug. `scripts/check-scope-equiv.sh` runs the checkable corpus
in this mode and pins the absence of `AX3075`.

**MAC-HYG-10 (H).** When a binder position holds a macro
parameter, the binder takes the argument's name and **MUST NOT** be
renamed. A binder the template itself introduces is renamed, as
`MAC-HYG-1` says. The two cases are opposite, and what tells them apart
is which side named the binding.

Renaming both would make every binding form impossible:

```scheme
(macro (bind! x e body) (let ((x e)) body))
(bind! v 41 (+ v 1))   ; 42
```

If `x` were renamed to `x.N`, the `let` would bind `x.N` while `body`,
which arrives through a different parameter, still reads `v`. The
result would be `` AX3001 undefined variable `v` ``.

A template that binds and reads through the same parameter hides the
problem. In `(macro (m x e) (let ((x e)) x))`, the rename table maps
both of the template's `x`s to the same fresh name. The answer comes out
right for the wrong reason, and the caller's chosen name appears nowhere
in the output. Only a macro that takes a separate body shows the
difference.

`substName` already follows this rule for `set` targets. A parameter in
a name position answers the argument's name, and an argument that isn't
a name is refused with `AX3035` (`macro-binder-target`). For example,
`(bind! (f 1) 41 7)` has nothing to bind. Without the refusal, it would
expand silently, binding a fresh name nobody could reference and
discarding the argument.

All three binder positions the expander owns follow the rule: `let`
and `let mut` binders, `lambda` parameters and match-arm pattern
binders (`expBinderParam` in `self_host/expand.ax`). Nothing goes onto
the rename stack for such a binder. A reference to the parameter
elsewhere in the template already substitutes to the same identifier
through the ordinary parameter path, so a rename entry would be a second
route to one answer.

The reverse direction is unaffected and belongs to `MAC-HYG-8`. A
template's free identifier that the caller's binder happens to shadow
still resolves at the definition site. So `(bind! helper 1 ...)`
doesn't steal the template's own `helper`.

`tests/diagnostics/590-macro-binder-target.ax` pins the refusal in both
positions. `tests/stdlib/371-err-module.ax` depends on the rule and
doesn't compile without it. This rule is what makes a propagation form
writable, and `ERR-SUGAR-2` in [error-model.md](error-model.md) is that
form.

**MAC-HYG-11 (H).** When a template's free identifier names
a function its module keeps private, the invocation is refused with
`AX3023`. The definition itself is accepted. `MAC-HYG-6` and
`MAC-HYG-7` resolve every helper a template names at the definition
site, and there the private name resolves fine, since it's the same
module. The expansion then carries that name into the caller's module,
where it doesn't exist. A free identifier's visibility is judged where
the macro is used. `MAC-LANG-10` is the mirror: a private *macro* is
refused at the definition site.

```scheme
;; PrivMac.ax
(pub macro (once x) (helper x))
(fn (helper x) (* x 2))
;; entry file
(import PrivMac)
(once 21)
; E AX3023 `PrivMac::helper` is private to module `PrivMac`
```

`tests/diagnostics/516-private-fn-capture.ax`, with
`tests/diagnostics/mods/PrivMac.ax`, pins the refusal at the
invocation, under the macro's frame.

---

## 4. Capabilities

### 4.1 What substitution already gives

**MAC-CAP-1 (H).** Every form a template can contain has a substitution
case: application, `if`, `match` and its arms, `let`, `let mut`, `set`,
`while`, field access, field store, struct construction, `lambda`,
block, `alloc`, `handle`, and every literal. A variadic `if`
substitutes as the nested `if`s it stands for. Lists and tuples need no
case of their own, because `[T]` and tuple types are type nodes: a
list-shaped value is a constructor application (`MM-VAL-13`).

**MAC-CAP-2 (H).** The default arm **MUST** refuse. A template form the
substituter doesn't know is `AX3021 macro-template-unsupported`. It is
never passed through unchanged.

Passing an unknown form through is a silent miscompile. The form
reaches the generated code still carrying the template's own
identifiers. The failure then surfaces as `AX4003`, a toolchain
failure, with no span into your source: the compiler blaming the
toolchain for its own bug.

`AX3021` has no reachable producer today. It exists so that the next
form added to the language becomes a diagnostic in the commit that adds
it, instead of a silent miscompile.

**MAC-CAP-3 (H).** When a macro parameter is the target of a `set` and
the argument is an expression rather than a name, the result is
`AX3022 macro-set-target`.

**MAC-CAP-3a (H;).** `AX3022` poisons its expansion.
The substituter reports the error and answers a null name. The caller
then emits a poison node (span 0, which suppresses cascades) instead of
putting the template's own identifier into the tree.

### 4.2 Pattern matching on syntax

**MAC-CAP-4 (H;).** With `MAC-LANG-14` to
`MAC-LANG-18`, a macro **SHALL** be able to dispatch on the shape of its
arguments: arity, literal heads, nesting and repetition. This is what
turns substitution into pattern-based rewriting. All of it holds:

- **Arity and nesting**: `MAC-LANG-15` and `MAC-LANG-18`. Dispatch on a
  literal argument's value holds too.
- **Repetition**: `MAC-LANG-16`, in all five of its parts: bare name (v1),
  nested (v2), arm and constructor (v3), declaration (v4) and
  constructor pattern (v5).
- **Literal heads**: `MAC-LANG-17`, which compares by canonical
  spelling with the shadow veto.

Scope sets (`MAC-HYG-9`) remain provisional as a change of
representation, and the dispatch doesn't wait on them.

### 4.3 Compile-time evaluation

**MAC-CAP-5 (R, with a replacement).** Compile-time evaluation of user
code is refused (`MAC-LANG-13`). In its place is a closed query
vocabulary that the compiler implements. The expander answers each
query from the declaration list it already holds:

| Query | Status | Answers | Needed by |
|---|---|---|---|
| `(syntax/constructors T)` | **H** | the constructor names of `data` type `T`, in declaration order, as a `syntax/for` sequence | `derive` for any sum |
| `(syntax/arity C)` | **H** | the field count of constructor `C`, as an integer literal | `deriveArity` in `stdlib/Pre.ax` |
| `(syntax/fields S)` | **H** | the field names of `struct` `S`, in declaration order, as a `syntax/for` sequence | lenses, `Eq`, serialisers |
| `(syntax/name x)` | **H** | the identifier `x`, as a string literal | `deriveShow` in `stdlib/Pre.ax` |
| `(syntax/join a b)` | **H** | one identifier made from two, with the second's first letter upper-cased | naming generated declarations, and calling them |
| `(syntax/defined n)` | **H** | whether `n` names a visible declaration | `showOr` in `stdlib/Pre.ax` |
| `(syntax/same a b)` | **H** | whether `a` and `b` are the same binding or declaration slot | `deriveLenses`' diagonal (§10.3) |
| `(syntax/binders C p)` | **H** | arity-of-`C` fresh identifiers derived from prefix `p` | fieldful `derive` (§10.2) |
| `(syntax/for ((x xs) …) tpl)` | **H** | `tpl` once per element, spliced in place | the iteration form |
| `(syntax/fold f z ((x xs) …) tpl)` | **H** | the right fold `(f tpl₁ (f tpl₂ … z))` | chaining `&&` over field comparisons |

The details, query by query:

- `syntax/constructors` and `syntax/fields` answer for any type that an
  entry-file reference could name. A private type refuses.
- `syntax/arity` reads the same declaration slot that `syntax/binders`
  counts, and refuses in the same two cases. A value's field count
  can't be recovered at run time, because a heap block records its tag
  and never its arity (`MM-VAL-6` in [memory-model.md](memory-model.md)).
- `syntax/name` is the only way a constructor's spelling reaches a
  running program, because a tag is an integer at run time.
- `syntax/join` works in three places: a declaration's name, a
  reference to what such a name declares, and another query's argument.
  As a reference, `((syntax/join show T) x)` calls `showColor`. As an
  argument, it lets `syntax/defined` ask about a name no source spells.
- `syntax/join` joins `lens` and `Point` into `lensPoint`, and `eq` and
  `Color` into `eqColor`. Either side may be a join of its own, so a
  name can have more than two parts:
  `(syntax/join (syntax/join get S) f)` is `getPointX`.
- `syntax/defined` is true when `n` names a `fn` or `::`, a `data` or
  `struct`, or a constructor. Those are exactly the names a generated
  body could refer to.
- An `if` whose condition is a `syntax/defined` or a `syntax/same` is
  decided at expansion time, and only the chosen branch is spliced.
  That folding is what makes `syntax/defined` useful. The losing branch
  names a declaration the program doesn't have, so a run-time `if`
  over both arms would be `AX3001` in every program that didn't derive.
  For `syntax/same`, it is what makes §10.3's expansion shapes literal.
- `syntax/same` needs both sides to be iteration variables over the
  same sequence. Over different sequences it refuses instead of
  answering false. Two answers that name field `f` of `S` compare
  equal, and matching spelling alone is never enough. `MAC-LANG-17`'s
  binding comparison is the same test on the pattern side.
- `syntax/binders` spells its identifiers `p#i`. The spelling is
  deterministic, so every mention within one expansion gets the same
  sequence, and `#` can't appear in a user identifier. Each identifier
  is a template binder that `MAC-HYG-2` renames. A mention in a pattern
  splices them as binders, and later mentions land on the same renamed
  binders through the rename table.
- `syntax/for` works in match-arm, template-declaration and
  call-argument positions. The for-variable substitutes in constructor
  patterns, field-name positions and name positions. Iterations nest,
  and a nested declaration iteration can name its products because
  `syntax/join` nests.
- `syntax/for` also has a parallel form, with several `(x xs)` pairs,
  in all three positions. The sequences zip in lockstep and **MUST**
  have equal length. A mismatch is `AX3028` at the `syntax/for` that
  wrote it, never a truncation to the shorter sequence.
- `syntax/fold` has the same single and parallel forms, and parallel
  sequences must have equal length: a mismatch is `AX3028`, never a
  truncation. It instantiates `tpl` per element and nests the results
  under a two-argument head, since `&&` takes exactly two. An empty
  fold answers `z`, so equality on a nullary constructor needs no
  special case.

No query name ends in `?`, because `?` isn't an identifier character.
Admitting it is reserved as a separate language change (see the comment
in `self_host/lexer.ax`). So the names are `syntax/defined` and
`syntax/same`, and `syntax/defined?` and `syntax/same?` don't lex.

Each of the three scalar queries, `syntax/name`, `syntax/arity` and
`syntax/defined`, comes with the library macro that needs it. That is
`MAC-CAP-6`'s closure rule applied literally: a query with no consumer
is one that nothing tests. `stdlib/Pre.ax` uses them in `deriveShow`,
`deriveArity` and `showOr`. Those macros also need a join to work as a
reference, so a macro can call what it names as well as name it.
`tests/selfhost/380-syntax-scalar-queries.ax` tests them, and
`tests/diagnostics/560-syntax-scalar-misuse.ax` pins the four
refusals.

`MAC-CAP-6` says a query with no answer is a diagnostic, never a
default value. `syntax/defined`'s `false` isn't a default. It is the
answer to a predicate, just as `syntax/same`'s `false` is. What refuses
is a malformed argument: a subject that is neither a bare identifier
nor a `(syntax/join a b)`.

The non-scalar rows are pinned by `tests/selfhost/374-derive-eq.ax`
(§10.2's nullary `deriveEq`, verbatim), `375-derive-lenses.ax` (§10.3,
verbatim), `376-syntax-nested-for.ax` (nested iteration over two
types) and `tests/frontend/070-derive-macro.ax` (through every frontend
consumer).

A declaration whose name came from `syntax/join` has no source
spelling. It records no span, so `axiom symbols` reports it without a
position instead of pointing at bytes that spell something else.

`syntax/for` is the rule form's binding syntax. It is unrelated to the
expression keyword `for`, which loops over values at run time, not
over declarations at expansion time.

`syntax/for` and `syntax/fold` are the only constructs that turn a
query's *sequence* answer into repeated output. Both are bounded by the
length of that sequence, which is a property of the program's
declarations, not of anything a macro computes. That is why
`MAC-EXP-9`'s budgets are a backstop and not the main termination
argument. The one-sequence form `(syntax/for (x xs) tpl)` is the common
case. The form with parenthesised pairs is what the fieldful examples
need.

Two forms generalise the rules above without adding a new mechanism:

- **Parallel `syntax/for`.** One normaliser handles the binding form
  for both `syntax/for` and `syntax/fold`. `(x xs)` is the application
  `APP(VAR x, xs)`, and `((x xs) (y ys))` is an application whose head
  is that application, so both arities share one grammar. The parser
  stores the whole binding form, and keeps the first binder in the
  node's name slot for diagnostics.

  The three splice sites push every parallel binding for an element
  together and pop them together, so a template sees the whole zipped
  tuple. The use it serves is what a zip is for: turning one
  enumeration into a parallel one. A hand-written version repeats the
  pairing, and repeated pairings drift apart
  (`tests/selfhost/386-syntax-parallel-for.ax`).
- **Nested `syntax/join`.** The marker string the parser writes into a
  declaration's name slot is prefix notation over a fixed arity, so it
  stays unambiguous when nested. The third part matters in practice.
  With only two parts, a lens set over two structs that share a field
  name generates `getX` twice, and the program is
  `AX3006 duplicate definition`
  (`tests/selfhost/387-syntax-nested-join.ax`).

**MAC-CAP-6 (H).** The vocabulary **MUST** be closed. Every entry
**MUST** be total, terminating, and a pure function of the declaration
list. Adding one is a language change, with a diagnostic, a gate and a
line in this table. A query with no answer is a diagnostic, never a
default value. That covers a `syntax/` head the vocabulary doesn't
implement, and `syntax/constructors` of a struct or of nothing.

One code enforces the closure for the whole family: `AX3028`
(`syntax-query`). It covers unknown heads, wrong positions, subjects
with nothing to answer, queries written outside a macro template, and
the reservation below. `axiom explain AX3028` is the catalogue.
Tested by `tests/diagnostics/520-syntax-query-misuse.ax` and
`525-syntax-reserved.axbad`.

The `syntax/` prefix is reserved in declaration names, and in the arm
and name positions the vocabulary owns. Without the reservation, the
near-miss `(fn (syntax/join a b) body)`, one paren short of a joined
name, would silently declare a function called `syntax/join` that takes
`a` and `b`.

This is the boundary the design turns on. Reading the declaration table
isn't evaluation: it terminates, it runs no user code, and its answers
are already in the compiler's hands. An expander that *ran* a user
function to compute a field list would bring in tier 2 through the back
door, which `MAC-LANG-13` forbids.

### 4.4 Type-level macros

**MAC-CAP-7 (H).** In Axiom, "type-level macro" means a macro that
generates type and instance declarations, keyed on declared types
through `MAC-CAP-5`. It doesn't mean type-level computation, and can't.
Axiom's type system has parametric polymorphism and aliases, but no
type-level functions, no higher-kinded abstraction over them, and no
dependency of types on values. A macro can't inspect an *inferred* type
at all, because expansion comes before inference (`MAC-EXP-1`).

The rule holds. `data` and `struct` are part of `MAC-CAP-8`'s template
surface, so every declaration kind this rule covers can be generated.
An instance is an ordinary value, so the `fn` that builds a capability
record is generated like any other function.
`tests/selfhost/381-macro-type-templates.ax` derives equality over a
type that a macro invented. What the rule denies matters more, and the
paragraphs below say what "type-level" does *not* give you.

The limit goes further than having no type-level functions. The type
grammar is purely structural: pointer, `linear`, keyword, type
variable, application, tuple, list and arrow. It has no const generics,
no type-level literals, no associated types, no constraints and no kind
system.

Higher-kinded types are absent for a syntactic reason worth knowing.
Type application needs an uppercase head, and a lowercase head in the
same position parses as a tuple. So `(f Int)` is the pair `(f, Int)`,
not `f` applied to `Int`.

Macros don't expand in type position either. A macro invocation in
type position is `AX3002`, not an expansion.

A conforming implementation **MUST NOT** get around this by running
expansion after the checker for some macros and before it for others.
That would make the pipeline position, and so whether generated code is
checked, depend on which macro was used.

### 4.5 Declaration macros and `derive`

**MAC-CAP-8 (H).** A macro can be invoked in declaration position,
producing one or more declarations, under the phase rules of
`MAC-EXP-16`. The declaration form is the rule form: one rule, whose
pattern head must repeat the macro's name. Everything after the pattern
is the template, and each form in it is one generated declaration:

```scheme
(pub macro deriveThing
  ((deriveThing T)                       ; pattern
   (:: ...)                              ; declaration 1
   (fn ...)))                            ; declaration 2
```

Tested by `tests/selfhost/372-decl-macro.ax` and
`tests/selfhost/373-decl-macro-types.ax`. The surface is:

- **Templates generate `fn`, `::`, `data`, `struct`, `type` and
  `effect` declarations, further macro invocations, and `syntax/for`
  iterations over them.** The next fixpoint round resolves the
  invocations. `data` and `struct` templates are what make `MAC-CAP-7`
  real (`tests/selfhost/381-macro-type-templates.ax`). In
  `tests/selfhost/389-type-effect-templates.ax`, a macro generates an
  alias and an effect declaration and names both from its arguments.

  An `import` template or a nested `macro` template is `AX3021` at the
  macro's own line, before any invocation exists. That is
  `MAC-SAFE-4`'s loud-at-definition shape. Both are refused by
  decision, not by schedule. An `import` inside a template would reopen
  module resolution, which has already run when phase D starts. A
  nested `macro` would add to the table that the same fixpoint is
  reading. Tested by `tests/diagnostics/510-decl-macro-template-kind.ax`
  and `565-macro-type-template-limits.axbad`.

  A `trait` or `impl` template never reaches `AX3021`. Neither word is
  part of Axiom any more, so the parser refuses either one with
  `AX2004`, one layer earlier.

  `type` and `effect` names go through `parseDeclName`, as the other
  type kinds' names do. A joined name is also writable in type
  position, because the signature beside a generated alias is the first
  thing that names it. There, `(syntax/join nm Handle)` parses as a
  joined name, not as the tuple a lowercase head would otherwise give.
  Read as a tuple, it would surface at a call site as well-typed
  nonsense, far from its cause.

  A constructor's name is a name position like any other, so
  `(syntax/join Off N)` names one, and two invocations of one macro
  generate two distinct types. A generated type can be queried in the
  same phase-D round that generated it. `(deriveEq Mode)` reads
  `syntax/constructors` off a `data` that `(defFlag Mode)` appended
  just before, because generated declarations join the merged list the
  queries read.
- **A parameter substitutes in name position, type position and
  expression position.**
  - A name position is a generated declaration's head, a `fn`'s
    parameter list, or a nested invocation's head. The argument there
    must be a bare identifier (`AX3027` otherwise), because a generated
    declaration's name has to be spellable.
  - A type position recomputes the signature's per-arrow float flags
    from the substituted type (`MAC-EXP-17`).
  - An expression position substitutes through the expression
    machinery, so hygiene, spans and the definition-site rule are
    `MAC-HYG-*`'s, unchanged.
- **Declaration macros share the expression macros' table, visibility
  and qualified-name split.** A `pub macro` in a module can be invoked
  as `Mod::name` from the entry file (fixture 372's `QualMac::qmk`). A
  private one can't. The fn-wins veto (`MAC-HYG-8` item 3) applies.
- **Arity is exact.** Declaration position has no "surplus applies to
  the result" rule, because the result is declarations, not a value. A
  count mismatch is the arity diagnostic, not a partial application.
- **Invocation works on both sides:** in the entry file, and in a
  module over its own declarations. The template's `pub` decides what
  leaves the module. The import's name list applies to a generated name
  as it does to a written one (`MAC-EXP-16`). Tested by
  `tests/selfhost/388-module-side-decl-macro.ax` and
  `tests/diagnostics/515-decl-macro-in-module.ax`.

`AX3027` (`declaration-macro`) covers every way a declaration-position
invocation fails. See `axiom explain AX3027`.

`derive` also needs to inspect `data` and `struct` fields, which
`MAC-CAP-5` and `MAC-CAP-6` provide. There is no `impl` template kind. A
derived comparison is a plain function, and it composes by being called
by name.

**MAC-CAP-9 (H).** `derive` is built on `MAC-CAP-8` and `MAC-CAP-5`,
not on a deriving mechanism inside the compiler. The worked `deriveEq`s
of §10.2 are ordinary macros in ordinary source.

You derive by explicit invocation. `derive` is a library of declaration
macros, such as `(deriveEq T)`, which you write where you want the
instance. A `deriving` clause is refused with `AX2004`, and the help
names the replacement.

We refused the clause instead of implementing it. A clause that parses
and derives nothing is the documented-but-inert failure class, and
refusal is the smallest true behaviour. Threading the clause's names
into the AST would touch the parser, the node layout, AXSYM and the
formatter, while explicit invocation needs only `MAC-CAP-8`.

The formatter refuses along with the parser: a `deriving` clause
poisons its output instead of being rewritten. A formatter that accepts
what `check` refuses is the `MAC-TOOL-6` defect class. Tested by
`tests/fmt/parity/070-deriving-refused.axp` and
`tests/diagnostics/545-deriving-refused.axbad`.

`stdlib/Pre.ax` provides `deriveEq`. You invoke it like any prelude
macro, over entry-file and imported types
(`tests/selfhost/379-derive-imported.ax`). No cross-module query is
needed, because the subject resolves through the invocation's
arguments.

A query answers for any type that an entry-file reference could name.
A private type refuses loudly at the invocation
(`tests/diagnostics/550-derive-private-type.ax`). That is the same
visibility rule the checker's own lookups apply. It is enforced in the
query, so the refusal is one diagnostic in the right place, not checker
errors scattered over generated code.

### 4.6 Format strings

A format string puts names from your code straight into the text, with
an optional specifier for width, alignment, zero padding, precision or
hex:

```scheme
(import IO)
;@axiom:effect(io)
(fn (main)
  (let ((name "parse") (ms 42) (x 3.14159) (n 255))
    { (println "ok {name} in {ms:>4}ms")
      (println "hex {n:x} {n:X}, pi {x:.2}, [{name:<8}] [{name:^9}] {ms:04}")
      (println "{{literal}}")
      0 }))
```

```text
ok parse in   42ms
hex ff FF, pi 3.14, [parse   ] [  parse  ] 0042
{literal}
```

**MAC-CAP-10 (H).** Two queries, `(syntax/format e)` and
`(syntax/formatln e)`, answer the expression that renders `e` as a
`String`. When `e` is a string literal, they parse it at expansion
time. They are the only queries that read a literal instead of the
declaration list, and they are all the compiler does for formatting.
The printing surface is these macros in `stdlib/`:

```scheme
; stdlib/IO.ax
(pub macro (println e)  (writeStr stdout (syntax/formatln e)))
(pub macro (eprintln e) (writeStr stderr (syntax/formatln e)))
; stdlib/Str.ax
(pub macro (format e)   (syntax/format e))
```

There is no newline-less `print`. C-descended libraries have one
because assembling a line was expensive, so you emitted the pieces.
Here the line is assembled at compile time, so
`(println "ok {name} in {ms:>4}ms")` is one call and one syscall. For
bytes with no newline and no rendering, use `writeStr`.

The formatting is a compiler primitive because tier 1 rewrites syntax
nodes. A format string arrives as one node, a `TAG_E_STR` whose payload
is an opaque lexeme, and no query can take a string apart. Adding one
would put a string-processing language inside the template language. So
the compiler splits the literal it already holds. This isn't tier 2
(§1.4): no user code runs, the input is a literal and not a program,
and the output is a tree the compiler builds, just as
`syntax/constructors` reads a `data` declaration.

**MAC-CAP-10.1: what the queries answer.** The answer depends on what
the argument is:

| Argument | Answer |
|---|---|
| a string literal | the concatenation of its literal runs, with one rendering call per hole |
| anything else | `(format# e)`: one call, dispatched on `e`'s static type. A program writes it as `(format e)` |

The second row is what lets `println` print any value, not just a
format string. `(println s)` on a `String` renders as itself, and
`(println n)` on an `Int` prints the integer. A value with no named
static type has no rendering to pick, and is `AX3025` (MAC-CAP-10.6).
Name its type with a `cast` or a signature.

`syntax/formatln` folds `\n` into the last literal run at expansion
time. So `(println "hi")` compiles to one static constant, `"hi\n"`,
and one call to `IO$writeStr`, with no allocation.

**MAC-CAP-10.2: the hole grammar.**

```text
hole   := '{' name [ ':' spec ] '}'
spec   := [align] ['0'] [width] ['.' precision] [type]
align  := '<' | '^' | '>'                       (default '>')
type   := 'x' | 'X'
`{{` and `}}` are a literal brace.
```

`name` uses the lexer's identifier charset, so any name the language
can spell can be interpolated, and the two can't drift apart.

A specifier isn't interpreted at run time. Each part selects a `Fmt`
function, once, during expansion:

| Written | Expands to |
|---|---|
| `{n}` | `(format n)` |
| `{n:x}` / `{n:X}` | `(fmtHex n)` / `(fmtHexUpper n)` |
| `{x:.2}` | `(fmtFloatPrec x 2)` |
| `{n:>8}`, `{n:8}` | `(fmtPadLeft (format n) 8)` |
| `{s:<12}` | `(fmtPadRight (format s) 12)` |
| `{s:^12}` | `(fmtPadCenter (format s) 12)` |
| `{n:04}` | `(fmtPadZerosLeft (format n) 4)` |
| `{x:>10.2}` | `(fmtPadLeft (fmtFloatPrec x 2) 10)` |

This is why there is one `println` and no print function per type. The
specifier and the argument's static type choose the rendering call.
`printInt` and `printlnInt` are gone: write `(println n)`.

**MAC-CAP-10.3: validation, and who owns which half.** Format
specifiers are validated at compile time, by two mechanisms. Neither is
a run-time check.

- The expander owns the string's shape. A malformed format string is
  `AX3031 malformed-format-string` at expansion time, with the caret
  inside the literal on the offending byte.
  `tests/diagnostics/570-format-refusals.ax` has one case per shape.
  Five are about holes: an unclosed hole, an unopened `}`, an empty
  `{}`, a hole that names nothing and an unterminated name. The rest
  are about specifiers: an unclosed one, an unknown type, a bare `.`,
  trailing bytes after one, a width above 1,000,000 and a precision
  above 1,000,000.
- The checker owns the value's type. A specifier chooses a function
  with a type, so a well-formed specifier on the wrong type is an
  ordinary `AX3004` at the invocation: `{s:.2}` on a `String` reaches
  `fmtFloatPrec`'s `Float` parameter. A hole naming an unbound name is
  `AX3001`. A hole whose type has no rendering, such as a type
  variable, a function value or a `Foreign`, is `AX3025`.

No specifier can be ignored at run time, because none of them survives
to run time.

**MAC-CAP-10.4: no argument list.** There is no positional `{}` and no
trailing argument list. A hole captures a name from the call's scope,
the same form Rust's 2021 edition settled on. A variadic macro
(`MAC-LANG-16`) is a rule with a repeating last element, not an
argument list on the format call. `{}` is refused by name as `AX3031`,
and its help points to the capture form.

**MAC-CAP-10.5 (H, CLOSED 0.7.4).** The names these queries generate
are `strConcat`, `fmtInt`, the `fmtPad*` family and the rendering call
for a hole. No template writes them, so they take `expQualify`'s
definition-site rule (`MAC-HYG-6`) explicitly, not through
substitution. An entry file that declares the same name can't capture
them. This program declares its own `show` and `strConcat`, and still
prints `n=42`:

```scheme
(import IO)
(:: show (-> a String))
(fn (show x) "HIJACKED")
(:: strConcat (-> String String String))
(fn (strConcat a b) "HIJACKED")
;@axiom:effect(io)
(fn (main) (let ((n 42)) { (println "n={n}") 0 }))
```

```text
n=42
```

Two mechanisms close the two ways in:

- **Helper names.** `expQualify`'s fourth rule (`MAC-HYG-8` hole 4)
  rewrites a free identifier to `Mod$name` when exactly one module in
  the merged declaration list declares it. The entry file's own
  declaration isn't a module's. `Str` is the only module declaring
  `strConcat`, so the lowering emits `Str$strConcat`.
- **The rendering call.** A hole's rendering call isn't a name at all.
  `expFmtShow` emits the head `format#`, and `#` isn't an identifier
  character (`AX1001`). The checker claims that head and rewrites it
  from the argument's static type. So `expQualify` isn't consulted,
  nothing can declare the spelling, and `(format x)` is the only way a
  program writes the lowering. `(show 1)` is an ordinary `AX3001`.

A capture like this would be silent. The program compiles, exits 0 and
prints the wrong text, which is why the fixtures run it.
Tested by `tests/selfhost/383-format-capture.ax` and
`tests/diagnostics/621-show-removed.ax`.

<!-- doc-gate:negative-exempt narrative: this says what the corpus DOES contain - two shapes with no named type - which the AX3025 fixtures witness directly. It is a positive population claim wearing a negative clause. -->
**MAC-CAP-10.6: the dispatch cliff.** A hole becomes a call, and the
argument's static type decides which rendering it reaches. Where there
is no named type, there is nothing to reach: a generic function's own
type variable, or a type that mentions one such as `(Box a)`. That hole
is `AX3025`, naming the situation. The fix is to name the type, with a
signature or a `cast`, as in `(println (cast Int x))`. An effect
operation's result is typed by its `handle` body, so
`(println (handle ..))` renders. Tested by
`tests/diagnostics/620-show-refusals.ax`.

Any rewrite that picks a callee from a type has to say what it emits
when the type isn't there. Two defects of that class were found here,
and both went away with `trait` and `impl` in 0.6.0:

1. **Dispatch emitted a call to a function that doesn't exist.** With
   no head name, `traitRewrite` answered 0 and left the head spelled
   `show`. The emitter wrote `call i64 @show`, and `opt` rejected the
   module with `AX4003` against `<toolchain>`, with no span into the
   source.
2. **Every diagnostic inside a dispatch argument was doubled.**
   Selecting an implementation checks that argument for its type, and
   the ordinary argument walk checked it again. Both reported, so
   `(sz nope)` gave two identical `AX3001`s.

---

## 5. Safety

**MAC-SAFE-1 (H, author obligation).** Arguments are substituted as
syntax (`MAC-EXP-7`), so a template that mentions a parameter more than
once duplicates its effects. A macro author who must not duplicate one
**MUST** bind it first:

```scheme
(macro (twiceSafe x) (let ((v x)) (+ v v)))    ; hygiene renames `v`
```

`MAC-HYG-1` makes this idiom safe: the binding can't capture anything
at the call site.

**MAC-SAFE-2 (H).** Expansion **MUST NOT** be able to produce a program
the checker would not have checked. It runs before the checker and
emits ordinary AST nodes, and no path from a template to the emitter
bypasses `checkModule`. `MAC-EXP-1` provides this property.

**MAC-SAFE-3 (H).** Expansion **MUST NOT** be able to forge a claim
about a program. Generated code contributes to effect inference exactly
as written code does: a template that reaches a syscall makes its
caller `#effects=IO`. `;@axiom:` metadata attaches to declarations,
which a template can't produce today (`MAC-LANG-5`). Under
`MAC-CAP-8`, a generated declaration's AXTAG claims **MUST** be
validated by `AX3010` like any other.

**MAC-SAFE-4 (H).** Expansion **MUST NOT** be able to hang or crash the
compiler. `MAC-EXP-9`'s five budgets bound it, and node handle 0 is
guarded everywhere the expander walks. `()` in a template is refused
at the macro's own line, before any invocation. It is one of the
positions of the empty form that `scripts/check-degenerate.sh` pins.

**MAC-SAFE-5 (R).** A macro **MUST NOT** be able to observe the
compilation environment: no file access, no environment variables, no
clock, no randomness and no network. This follows from `MAC-LANG-13`.
It is stated again because it makes an Axiom source tree auditable by
reading it, the same argument `scripts/check-reproducible.sh` makes
about the output.

---

## 6. Integration

**MAC-INT-1 (H).** **Modules.** A macro is a declaration. It is
imported, made visible by `pub`, selectable by an import's name list,
and private otherwise (`MAC-LANG-9`). Diamond imports merge it once, as
for any declaration.

**MAC-INT-2 (H).** **Generics.** A macro doesn't see types, so it
composes with polymorphism trivially and can't specialise on it. A
macro that generates a call to a polymorphic function generates an
ordinary call.

Two facts about what that call meets limit how much a generated call
can be checked:

- Generic instantiation uses uniform representation, not
  monomorphisation. Every value is one machine word, so a polymorphic
  function is emitted once and every call site calls the same symbol.
  A macro can never cause a code-size explosion by instantiation.
- There is no Hindley–Milner inference. An unsignatured function's
  parameters are all `Int`. A signature's type variable is rigid inside
  the body and becomes an unsolved placeholder at each reference, and
  placeholders are never solved. So a generated call that passes two
  mutually inconsistent arguments to a polymorphic function is
  accepted. `MAC-EXP-2` promises generated code is checked exactly as
  written code is. It doesn't promise the checker is strong.

**MAC-INT-3 (H).** **Effects.** Expansion is invisible to the effect
system. Inference runs on the expanded program (`MAC-EXP-1`), so a
macro's effects are its expansion's effects, attributed to the caller.
A macro **cannot** be effect-polymorphic in its own right, and doesn't
need to be.

**MAC-INT-3a (H).** A macro that drops an argument can invalidate an
AXTAG claim the author wrote. This looks like a compiler bug the first
time you see it. The claim is validated against the expanded program,
and the dropped argument isn't in it:

```scheme fragment
(macro (ignore x) 7)
;@axiom:effect(io)
(fn (main) (ignore (side 1)))     ; `side` performs IO, and is dropped
```
```text
E AX3010 axtag-mismatch "AXTAG mismatch on `main`: `effect(io)` claim unsupported: missing IO"
```

The diagnostic is correct, and it refuses the build. After expansion,
`main` performs no I/O, so the claim is false as written. The fix is to
drop the tag the macro made untrue. A conforming implementation
**MUST** keep validating claims against the expanded program.
Validating them against the source would let a macro's rewrite
silently falsify a claim in the other direction.

**MAC-INT-4 (H, its subject removed in 0.6.0).** **Interfaces.** An
interface is a capability record: a parameterised `struct` holding the
functions. The `struct` and `fn` template kinds generate one like any
other declaration. `trait` and `impl` were removed in 0.6.0 and are
`AX2004` now. A capability record is an ordinary value with an ordinary
module-qualified name, so two modules can't collide over one the way
two `impl`s of the same `(Trait, Type)` pair did.

There is no dictionary-passing, and generated code **MUST NOT** assume
there is. A function that needs an interface's members has to be
handed the record that holds them. Dispatch is `((c.eq) x y)`, an
application of a field.

**MAC-INT-5 (H).** **The formatter.** `axiom fmt` formats a macro
declaration and its template as source. It does **not** format
expansions, which don't exist in the file. A conforming formatter
**MUST NOT** rewrite a template in a way that changes what it expands
to. This is a real risk: the formatter re-implements the token set on
its own, and it has changed a literal's meaning before (`0.05` became
`0.5`).

**MAC-INT-6 (H).** **tree-sitter.** `tree-sitter-axiom/grammar.js` is
one of the four implementations of the surface syntax that
`MAC-LANG-16` lists. Any change under `MAC-LANG-14`–`MAC-LANG-16`
**MUST** land in the lexer, the formatter and the grammar together,
checked by `scripts/check-tree-sitter.sh` and `scripts/check-fmt.sh`.

---

## 7. Diagnostics

**MAC-DIAG-1 (H).** Macro diagnostics live in the semantic range,
because expansion happens at semantic-analysis time. These codes can
reach a macro author. `axiom explain --list` is the authority on the
set, and all but `AX3023` are constructed in `self_host/expand.ax`:

| Code | Slug | Fires when |
|---|---|---|
| `AX3018` | `macro-arity` | an invocation no rule accepts (`MAC-EXP-8`, `MAC-LANG-18`). For the head-list form this is still a count: too few arguments. A longer spine isn't an error in expression position, because the surplus is applied to whatever the macro produced. In declaration position the message names the shapes the rules accept ("no rule of macro `n` matches this invocation; it accepts …"), and an invocation whose count some rule declares still lands here if no rule's shape matches. The slug stays `macro-arity` because `MAC-LANG-18` names the generalisation |
| `AX3019` | `macro-recursion-limit` | instantiation depth exceeded 128 |
| `AX3020` | `macro-duplicate-parameter` | two parameters share a name |
| `AX3021` | `macro-template-unsupported` | a template form substitution can't handle. Its expression-template arm has no reachable producer, by design (`MAC-CAP-2`). Its reachable producer is a declaration template generating a kind outside the v1 surface, reported at the macro's own line |
| `AX3022` | `macro-set-target` | a parameter used as a `set` target is given an expression |
| `AX3023` | `private-name` | a macro its module doesn't export. This is the general visibility code, which reaches macros through `MAC-LANG-9` |
| `AX3024` | `macro-expansion-limit` | the output tree exceeded 1024 deep or 2,000,000 nodes. The parser's limits measure the source, and these measure what expansion produced from it |
| `AX3027` | `declaration-macro` | every way a declaration-position invocation fails: an unknown head (including a mistyped keyword), either template kind across the position boundary, a non-identifier argument in a name position, or a module-side invocation reaching a pipeline that carries no mangling records. `axiom explain AX3027` is the catalogue |
| `AX3028` | `syntax-query` | every `syntax/*` query with no answer (`MAC-CAP-5`, `MAC-CAP-6`): an unknown or wrong-position head (the vocabulary is closed), a subject with nothing to answer, a query written outside a macro template, or a declaration named into the reserved `syntax/` prefix. `axiom explain AX3028` is the catalogue |
| `AX3031` | `malformed-format-string` | the expander's half of `MAC-CAP-10.3`, with the caret inside the literal on the offending byte |
| `AX3033` | `macro-unreachable-rule` | a rule an earlier one starves. Rules are tried in order, and a rule whose every element is a plain binder matches everything of its arity, so nothing of that arity after it can run. Two rules of one arity are fine when their shapes differ: that is what patterns are for |
| `AX3034` | `macro-ellipsis` | an ellipsis at the wrong depth: a repeating name used without `...`, `...` after something that doesn't repeat, two `...` in one rule, or a repeat over a pattern instead of a bare name. The first two report at the invocation, the last two at the macro |
| `AX3035` | `macro-binder-target` | a parameter in binder position is given something that isn't a variable (`MAC-HYG-10`). It follows the same rule `AX3022` follows for `set` targets |

`AX3006` (duplicate definition) also reaches macros (`MAC-LANG-8`).

**MAC-DIAG-2 (H).** Every macro diagnostic **MUST** anchor at a span in
the file being compiled (`MAC-EXP-14`). It **MUST** name the macro in
its message, since it can't point at it.

**MAC-DIAG-3 (H).** A diagnostic **MUST** be reported once. The output
budgets set a "blown" flag, so the refusal is reported at the first
node and not at every node after it.

**MAC-DIAG-4 (H).** A diagnostic that arises inside an expansion
carries an expansion backtrace. It has one frame per enclosing
instantiation, outermost first. Each frame names the macro, with the
span of its declaration in its own unit. Each surface shows frames its
own way:

- AXDL renders each frame as `&FILE:LOC:"name"`, the one field on the
  line whose file isn't the diagnostic's own.
- The human renderer prints ``in this expansion of `name` (FILE:LOC)``
  as a note, or a location block (`MAC-DIAG-5`).
- JSON's `expansion` array holds `{"macro", "file", "line", "col"}`
  objects.
- The LSP appends the name.

`tests/diagnostics/490-expansion-backtrace.ax` pins it, with one frame
on a direct invocation and two on a nested one.
`tests/diagnostics/verify-axdl-spans.py` checks its frame spans against
the macro's file, as it checks every claim.

Frames join by span handle, not by node provenance. Every node a
template produces is rebuilt carrying the invocation's span, the same
record by reference (`MAC-EXP-14`). So the expander records one entry
per instantiation: the declaration module, the invocation span, the
macro, its span and its module. After the checker, a post-pass attaches
frames to any diagnostic whose primary span is a recorded handle.
Pointer equality can't collide across files, no node carries a
provenance word, and the parser is untouched.

A frame is `(name, span, unit)` (`DFrame`). A frame with no span
renders as the bare `&"name"` that the AXDL grammar in
[diagnostics.md](diagnostics.md) allows.

The invocation stays primary, as `MAC-DIAG-5` wants, because it is the
line the author can change. The REPL discards frames: its error line
joins bare messages, and the prompt is the invocation.

The expander's own refusals carry frames too. `AX3021`, `AX3027` and
`AX3028` are by construction from inside an expansion, and they go
through the same `expAttachFrames` as the checker's diagnostics.

That brings `MAC-DIAG-5`'s rule one level down. **A refusal about the
template's shape anchors at the macro. A refusal about the arguments'
values anchors at the invocation and carries the frame.** The author
edits a different line in each case. A binding form that isn't a
`(y ys)` pair is the macro's text however it is invoked. A skew is the
invocation's doing: the template pairs the sequences, and the arguments
decide their lengths. So `syntax/fold` and `syntax/for` both report a
skew at the invocation.

**MAC-DIAG-5 (H).** With `MAC-DIAG-4`, the rendered form **SHALL** be:

```text
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

The invocation stays primary, because it is the line the author can
change. The frames follow it outermost first, each opened in its own
file.

A frame whose unit the renderer can reach becomes a location block of
its own. It quotes the macro's declaration line and puts a caret under
its span, labelled ``in this expansion of `name` ``. A frame with no
span, or one whose unit is out of reach, still renders as the
`MAC-DIAG-4` note, because a location block needs a file to open. The
gutter is computed across the primary and every frame together, so one
report keeps one bar column however many files it spans. Tested by
`tests/diagnostics/490-expansion-backtrace.ax`, with one frame and a
nested two.

The machine surfaces are unchanged by this rendering: the AXDL `&`
field and the JSON `expansion` array are the same as under
`MAC-DIAG-4`. `scripts/check-render-selfhost.sh` derives each frame's
expected block from the AXDL, the same way it derives the primary's:
the header line, the quoted source line, a caret row as wide as the
span, and the frame's label. It reads the quoted line from the frame's
own fixture bytes.

---

## 8. Tooling

**MAC-TOOL-1 (H).** A macro declaration **MUST** carry a real span.
The language server's `documentSymbol` entry for a macro depends on it,
and so does the "first defined here" line of `AX3006`.

**MAC-TOOL-2 (H).** The language server **SHALL** treat a macro
invocation as a reference to its declaration. Go-to-definition jumps to
the `macro` form, hover shows the template, and `documentSymbol` lists
macros beside functions.

All three hold. The server advertises `definitionProvider`,
`hoverProvider` and `completionProvider`. On a macro name, definition
answers the declaration's own name range. On a name that isn't a
declaration, it answers `null`, the protocol's "nothing here".

Lookup covers every declaration kind `documentSymbol` lists: a macro, a
function, a `data`, a `struct`. It reads this document's declarations
first, and walks the import graph only when that misses. That matches
the language's scoping, where a module's own declaration shadows an
imported one. A definition request inside the file you are editing
costs one parse. Nothing expands, because the raw tree carries every
declaration either lookup needs, so `MAC-TOOL-3` holds. The server maps a module path back to a URI with `lspPathToUri`, the
inverse of `lspUriToPath`.

Hover uses the same order and the same set of names. It answers:

- the declaration in an `axiom` code fence, taken verbatim from its
  source. A `fn` is shown as its `(:: f T)` signature rather
  than its body;
- the module it comes from, when the name was imported;
- the comment paragraph written directly above the declaration (above
  the signature, for a `fn`).

The hover `range` is the word under the cursor, as the protocol asks,
not the declaration's span. For an imported name, the declaration is in
another file.

Completion also works under `MAC-TOOL-3` unchanged. It offers, in this
order:

1. the head keywords the parser dispatches on;
2. this document's declarations, and the constructors each `data`
   names;
3. every imported module's declarations, under their bare names.

A local name shadows an imported one, and both shadow a keyword, which
is the language's own rule. The server filters the list on the prefix
under the cursor and sends it with `isIncomplete: true`, so the client
asks again on the next keystroke. A document that doesn't parse still
completes keywords. That's the normal case, because a file can't parse
while you are halfway through writing a form.

**MAC-TOOL-3 (H).** A conforming language server **SHALL NOT** expand
macros to answer a request that doesn't need it. Expansion is bounded
but not free (`MAC-EXP-10` records 41.4 s on a fan-out probe), and an
editor can't wait.

These requests are sent per keystroke or per cursor move. They read the
raw parse tree and the document's bytes, and expand nothing:
`documentSymbol`, `definition`, `hover`, `completion`, `references`,
`documentHighlight`, `prepareRename`, `rename`, `signatureHelp`,
`inlayHint`, `foldingRange`, `selectionRange`, `documentLink`,
`workspace/symbol`, `formatting`, `typeDefinition` and `codeLens`.

Three requests run the pipeline, because the expansion is the answer:

- `didOpen` and `didChange` publish diagnostics, and a diagnostic
  about generated code needs the expansion.
- `codeAction` returns a quickfix, which is a checker diagnostic's own
  fix.
- `axiom/expandMacro` renders what a macro generated.

None of the three is sent per keystroke. A client asks for code actions
when the cursor rests, and for an expansion on demand. Each costs about
one `didOpen` of the same document.

Completion doesn't offer a name that only a macro generates:
`(deriveTag Colour)` doesn't put `tagColour` in the menu, because
nothing has expanded it. `tests/lsp/drive.py` asserts that absence.

Other requests can still find a generated name through a cache. At
`didOpen` and `didChange`, where the pipeline already runs for
diagnostics, the server expands each top-level invocation in isolation.
It stores the result by generated name, with the invocation head's span
and the rendered product. `definition`, `declaration`, `hover` and
`references` read that cache when the raw-tree lookup misses, and
expand nothing. The fast path still never expands: it remembers what
the last `didOpen` expanded.

`scripts/check-macro-demand.sh` pins the evidence behind this rule as
two numbers. The population is the count of `#generated=` AXSYM rows
over the corpus that can carry one: the declaration-macro family in
`tests/selfhost` and one frontend case, with none in the standard
library or the compiler. The demand is the count of requests in
`tests/lsp/drive.py` that target a generated name, each asserting the
cached shape inline. If either number moves, the gate fails, and the
question to settle in review is whether this rule still holds.

`axiom/expandMacro` needs to turn a tree back into source. The printer
is `lspRenderDecl`/`lspRenderExpr` in `self_host/lsp.ax`. It promises
that its output parses and means what the tree meant:

- The gate checks the first half by reopening the rendering as a
  document and requiring an outline of exactly the generated name.
- The second half was checked on a template that holds a mutable
  `let`, a block, `set`, `while`, `match`, a two-parameter lambda,
  struct construction, field access, an escaped string, a char, a
  float, a negative literal, and a generated `data`, `type` and
  `struct`. `check` on the rendering reported exactly the diagnostics
  it reported on the template.

The printer changes two spellings: a hygiene binder `x.3` is written
`x_3`, and `Mod$name` is written `Mod::name`.

A generated `struct` and its handwritten twin produce identical AXSYM
rows and identical code, down to each field's type. This is tested by
`tests/selfhost/396-macro-struct-field-types.ax`, and by the zoo's
`RecTwin`, whose row in `tests/tools/symbols-zoo.golden` carries
`Rec`'s own `#fields=`.

**MAC-TOOL-4 (H).** With `MAC-CAP-8`, `axiom symbols` **SHALL** list
generated declarations, attributed to the file that contains the
invocation. It **SHOULD** mark them as generated, so a reader can tell
why a name has no visible definition.

Both hold. A generated row carries `#generated=<macro>`, naming the
macro that produced it. Phase D builds the (name, macro) table, and
`expandProgram` returns it. A caller that doesn't need the table
discards it. A generated declaration whose name came from `syntax/join`
still reports no position, because the file never spells that name.
The `#generated=` field explains the dash.

**MAC-TOOL-5 (H).** **Lints run on the program the author wrote, not on
the program expansion produced.** A diagnostic whose span lies inside
an expansion, and whose fix would edit generated text, **MUST NOT** be
offered as machine-applicable: there is nothing at that location to
edit. A conforming implementation **MUST** suppress a
machine-applicable `~>` replacement whose span belongs to a generated
node. It **MUST NOT** emit a replacement string that contains a renamed
binder (`MAC-HYG-3a`).

The hazard is real, because tools apply the AXDL grammar's `~>` field
without asking. Without this rule, two diagnostics offered these fixes:

```text
E AX3012 ... "cannot assign to immutable binding `tmp.0`"
    ?4:13-17:"declare it mutable: `(mut tmp.0 ...)`"~>"mut tmp.0"
    &tool5.ax:1:9-13:"bump"
E AX3001 ... "undefined variable `helperr`"
    ?7:13-19:"a similarly named binding `helper` is in scope"~>"helper"
    &tool5b.ax:1:9-15:"callIt"
```

Both spans are the invocation's. That is right for the report
(`MAC-DIAG-5`) and wrong for the fix, because applying it pastes the
replacement over the macro call. The first fix also contains `tmp.0`, a
renamed binder no source can spell, which is the `MAC-HYG-3a` half of
this rule.

The implementation reuses the join that `MAC-DIAG-4` already computes.
A diagnostic that acquires an expansion frame is about generated text,
so `expAttachFrames` disarms its helps as it attaches the frame. The
help's text survives, and its span-and-replacement pair doesn't.
Diagnostics outside an expansion are unchanged. The fixture shows both
sides by carrying the same diagnostics twice, once from a macro and
once written by hand.

Tested by `tests/diagnostics/580-expansion-fix-suppressed.ax`.

**MAC-TOOL-6 (H, closed).** `axiom fmt` **MUST NOT** disagree with
`axiom check` about what lexes. The formatter's reader has token kinds
for the backtick and `,@` that the compiler's lexer lacks, and it reads
`'`, `` ` ``, `,` and `,@` as prefix markers on the following form.
Printing those markers would rewrite files that `check` refuses, so the
printer refuses them too. On `` (fn (main) `(+ 1 2)) ``:

```text
$ axiom --diagnostic-format=ai check bt.ax
E AX1001 bt.ax:1:12-13 unexpected-char "unexpected character ```" ...
$ axiom fmt bt.ax
bt.ax was not rewritten: formatter refusal
```

This matters to the macro system because `` ` `` and `,@` are the
obvious spellings for any future quotation form. Any change under
`MAC-LANG-16` **MUST** keep `fmt` and `check` in agreement on them.

The formatter refuses all four prefix markers in `fpExpr`'s
`FN_PREFIX` arm, through `fpBad`, the printer's existing refusal. It's
inlined in that arm, so no new top-level function moves the
effect-distribution pins. `tests/fmt/parity/230`, `231` and `232` pin
one refusal each, and `check` refuses all three. `060` pins the `,@`
refusal.

---

## 9. Rationale

### 9.1 Why a rewrite and not an evaluator

Every other decision in this document follows from `MAC-LANG-13`. A
procedural macro system is strictly more expressive, but it would cost
the property this project has always kept: compiling a file runs
nothing the file chose. A compiler that runs the code it compiles needs
a threat model, a sandbox and a resource policy. Axiom would be
designing all three just to derive an equality function.

### 9.2 Why patterns rather than more parameters

Axiom is an S-expression language, so the shape of a form *is* its
data. Matching on that shape is the natural tool. It covers the use
cases we care about without needing evaluation: deriving functions,
removing the boilerplate in the standard library, and generating the
repetitive parts of a self-hosted compiler.

### 9.3 Why hygiene by renaming first, scope sets second

Renaming fully solves the direction that produces *wrong answers*. It
fit in one pass, with no change to either resolver. Scope sets change
what an identifier *is*, which reaches the parser and name resolution.
Shipping the cheap half first was right, but stopping there is not. So
`MAC-HYG-9` is normative, and it carries an equivalence obligation
rather than a licence to rewrite.

### 9.4 Why the default arm refuses

Eight silent miscompiles were one bug: a tag added to the parser and
not to the substituter. A default arm that returns the node unchanged
makes the ninth silent too. A default that refuses makes it loud, in
the commit that adds the tag. This is the most transferable rule in the
document: **a rewriter's unknown case is never a passthrough.**

### 9.5 Why the budgets are on the output

The parser's limits measure the source, and a macro's source is short
by nature. 154 bytes that produce 2²⁶ nodes aren't an attack. They are
six lines of plausible code.

---

## 10. Worked examples

### 10.1 What works today

`stdlib/Pre.ax` exports `when` and `unless`:

```scheme
; from stdlib/Pre.ax
(pub macro (when test body)   (if test body 0))
(pub macro (unless test body) (if test 0 body))
```

It also exports `range`, `deriveEq`, `deriveShow`, `deriveArity` and
`showOr`. Variadic branching needs no macro: `(if t1 b1 t2 b2 ... els)`
is the nested chain, built by the parser.

Here is hygiene at work. The template binds its own `v`, and the caller
also has a `v`. Renaming keeps them apart, so the caller's `v` reaches
`test` and `acc` untouched:

```scheme
(macro (sumIf test x acc)
  (let ((v x))                       ; MAC-SAFE-1: evaluate x once
    (if test (+ acc v) acc)))

(:: main Int)
(fn (main)
  (let ((v 10))
    (sumIf (> v 5) 2 v)))            ; 10 + 2
```

```bash
axiom run sum.ax; echo $?
```

```text
12
```

### 10.2 Deriving structural equality

This example uses `MAC-CAP-5` and `MAC-CAP-8`, and it is the acceptance
criterion from the roadmap's §4.2. The nullary form below is tested
verbatim by `tests/selfhost/374-derive-eq.ax`: this section's macro,
data type and invocation, answering 101 from three `eqColor` probes.

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

It expands to exactly what you would write by hand:

```scheme
(:: eqColor (-> Color Color Bool))
(fn (eqColor a b)
  (match a
    ((Red)   (match b ((Red) true)   (_ false)))
    ((Green) (match b ((Green) true) (_ false)))
    ((Blue)  (match b ((Blue) true)  (_ false)))))
```

The example shows two properties:

- **The generated `match` is checked.** Add a fourth constructor to
  `Color` without regenerating, and you get `AX3005`, the same code the
  hand-written match draws (`MAC-EXP-2`). This already holds for
  expression macros.
- **No user code runs at compile time.** The expander answers
  `syntax/constructors` and `syntax/join` from the declaration list
  (`MAC-CAP-6`).

Constructors *with* fields use the same shape, one step up the
vocabulary. `syntax/binders` names a constructor's fields as fresh
pattern binders, and the parallel form of `syntax/fold` zips the two
sides:

```scheme
(pub macro deriveEqF
  ((deriveEqF T)
   (:: (syntax/join eq T) (-> T T Bool))
   (fn ((syntax/join eq T) a b)
     (match a
       (syntax/for (C (syntax/constructors T))
         ((C (syntax/binders C x))
          (match b
            ((C (syntax/binders C y))
             (syntax/fold && true
                          ((xi (syntax/binders C x))
                           (yi (syntax/binders C y)))
               (== xi yi)))
            (_ false))))))))
```

One template covers a sum whose constructors carry 1, 2 and 0 fields.
The nullary case falls out of the empty fold, which answers `true`.
`(== xi yi)` covers `Int` fields. Tested by
`tests/selfhost/377-derive-eq-fieldful.ax`, which answers 30.

The `impl`-generating form is gone, with traits, since 0.6.0. An
interface is now a capability record, an ordinary value a macro can
build with the same `syntax/for`, `syntax/binders` and `syntax/fold`.

A *polymorphic* field, such as `(Just a)`'s payload, is still an edge,
and it belongs to `MAC-INT-4`. It has no concrete type to select a
comparison on, and no dictionary exists to pass. So `deriveEq` over a parameterised type draws the same
refusal the hand-written comparison would. That is `MAC-EXP-2` at work:
generated code is checked exactly as written code, and it can't call
what the language can't dispatch.

### 10.3 Deriving lenses

This is the boilerplate case. `MM-MUT-2`'s aliasing hazard makes a
*functional* accessor worth generating. `tests/selfhost/375-derive-lenses.ax`
is this section's macro, struct and invocation verbatim, and it answers
34 from a `getX`/`withX`/`withY` round trip.

It uses four mechanisms beyond §10.2's set:

- declaration-position `syntax/for`, giving four declarations per
  field;
- argument-position `syntax/for`, where each element splices one
  argument into the `(Point ...)` rebuild;
- field-name substitution: `s.f`, with `f` iterating;
- `syntax/same`, deciding the diagonal at expansion time and splicing
  in the chosen branch.

So the "expands to" claim below is literal, not only behavioural:

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

`withX` expands to `(fn (withX s v) (Point v s.y))`, a **rebuild**.
That's what separates a lens from a field store: `(set p.x 1)` mutates
through every alias (`MM-MUT-2`), and `(withX p 1)` doesn't.

This example is why `syntax/same` has a row in `MAC-CAP-5`'s table. A
real macro needed it, which is what `MAC-CAP-6`'s closure rule asks
for: the entry is a language change, argued for here and recorded
there.

### 10.4 An algebraic optimiser as rewrite rules

Pattern macros turn a peephole optimiser into a table rather than a
visitor. Each rule is a pattern and a template, which is exactly what a
rewrite rule *is*:

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

Two rules make this work:

- `MAC-EXP-9`'s budgets make a recursive rewrite table safe to write.
  Without them, `(simplify e)` falling through to itself would hang the
  compiler.
- `MAC-LANG-18`'s ordering makes the last rule a default rather than an
  ambiguity.

Here is where the table stands. `MAC-LANG-18`'s ordering holds, and the
seven rules of arity one are accepted. Two of the three pieces it
needed are in place:

- The heads. `+` and `*` in `(+ e 0)` tell rule 1 from rule 3. A
  `(literals + *)` header reserves them, so dispatch is by binding,
  with the shadow veto (`MAC-LANG-17`).
  `tests/selfhost/403-expr-rule-macro.ax` rewrites both.
- `(f a ...)`, which is `MAC-LANG-16`'s ellipsis: v1, and v2 for the
  nested shape the last rule's right-hand side needs.

Not yet: `(- e e)`, a repeated binder. `MAC-LANG-15` refuses it with
`AX3020` rather than reading it as a same-form test. `expParamIndex` is
last-wins, so allowing it would silently bind the second occurrence.
There is also no structural form-equality to compare against, and
`syntax/same` isn't one.

The templates here are *expressions*, which the rule form accepts as
`emacro` (`MAC-LANG-14`'s wide half). The table above spells `macro`.
Written as `emacro` with a `(literals + *)` header, five of its seven
rules run today, and `(- e e)` is the one that still refuses.

### 10.5 A small DSL

A state machine. The macro's value is that the compiler checks the
*shape*, rather than a runtime parser:

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

Here the ellipsis does the work, not a query. The pattern
`(state s (on ev next)) ...` binds three parallel sequences, and the
template uses each at the same depth, following `MAC-LANG-16`. The
generated `match` is exhaustive over the generated `data` type by
construction. If a transition names a state with no `state` clause,
`AX3002` reports it at the `(machine Door ...)` line. The machine
expands end to end, using arm and constructor splices. Tested by
`tests/selfhost/398-arm-ctor-splice.ax`.

That `AX3002` report is why `MAC-DIAG-4` is normative. Without an
expansion backtrace, the author of `(machine Door ...)` would read a
diagnostic about a constructor they never wrote, in a `match` they
never wrote, at a line that contains neither.

<a id="106-a-dsl-that-shipped-and-what-it-established-stdlibhtmlax"></a>
### 10.6 What `stdlib/Html.ax` established

The HTML templating layer was the first DSL in the standard library
written in this macro system, with about a hundred element and
attribute macros. It has since been removed, along with its one
program, `examples/web/server.ax`. What it established about this
document's rules still holds:

- **`MAC-EXP-7`** was why an element was a macro and not a function.
  `(div b { children })` had to write `<div>` *before* its children
  ran, and only substitution as syntax evaluates an argument where its
  parameter stands. Children were a `{ ... }` block, which `MAC-CAP-1`
  admits as a template form and the parser admits as an argument. So a
  fixed-arity macro could take any number of them.
- **`MAC-HYG-10`** made `(for it items body)` writable as a macro: `it`
  was a parameter in binder position and kept the caller's spelling,
  while the template's `i` and `n` were renamed (`MAC-HYG-3`). `for` is
  now a language keyword ([for loops](reference.md#for-loops)), whose
  binders are `for$i`, `for$n` and `for$v`. `$` inside an identifier is
  `AX1001`, so nothing a caller writes can collide with them. Term 6 of
  `tests/stdlib/466-for-loop.ax` is the hygiene check. `MAC-HYG-10` is
  unchanged, and `Err.ax`'s `try!` still depends on it.
- **`MAC-HYG-6`/`MAC-HYG-7`** resolve every helper a template names at
  the definition site. The module kept every such helper in `Html.ax`,
  and declared it `pub`. `MAC-LANG-10` judges a template's private
  *macro* at the definition site, but the visibility of a free
  identifier is judged where the macro is used. A private *function* named by a template is refused at the
  invocation with `AX3023` `private-name`. That rule is `MAC-HYG-11`.
  No library template exercises it now, so
  `tests/diagnostics/516-private-fn-capture.ax` keeps it pinned.
- **`MAC-SAFE-1`** was applied in `el`/`elA`: the builder and the tag
  each appeared twice in the template, so both were bound first.
- **`MAC-LANG-13`** decided that escaping was a run-time function
  (`hEscText`, `hEscAttr`), and that `</` inside `script`/`style` was
  rewritten at run time rather than refused at `check`.
- The module worked around the system's limits at the time:
  - No variadic expression macro (`MAC-LANG-14`), so children were a
    block. `emacro` now fills that gap.
  - No macro generating a macro (`MAC-CAP-8`'s `AX3021`), so the tag
    table was written out, two lines per tag.
  - No `{}`, so `div` and `divA` were two macros.
  - No `:class`, a lexer limit.
  - No dispatch on a head's spelling (`MAC-LANG-17`), so each attribute
    name got its own macro, plus `attr`. Canonical-spelling dispatch
    now exists.
  - `MAC-EXP-14a`'s literal spans, now fixed. Its many string literals
    were the densest exposure to them in the tree.

One refusal is worth knowing before you name a macro. A bare identifier
that names a macro is a zero-argument invocation (`MAC-LANG-3`), and the
expander reads type positions too. A macro named `a` made the type
variable `a` in `Vec.ax`'s signatures report `AX3018`: "macro `a` takes
2 arguments, but was given 0". That's why the anchor element was called
`anchor`. Don't use `a`, `b`, `e` or `f` as a macro name while any
signature in scope spells them as type variables.

---

## 11. Conformance summary

| Area | Holds today | Planned | Refused |
|---|---|---|---|
| Language | LANG-1…12, LANG-14 (several rules over both forms, declarations through `macro` and expressions through `emacro`, selected by a pattern match in rule order, with arity kept inside the match as a pre-filter), LANG-15 (all six pattern kinds), LANG-16 (v1–v5: bare-name, nested-pattern, arm/ctor, declaration and ctor-pattern splices), LANG-17 (literal identifiers, canonical-spelling comparison), LANG-18 | — | LANG-13 |
| Expansion | EXP-1…17, including module-side invocation | — | — |
| Hygiene | HYG-1…8 (all four of HYG-8's holes are closed, and so is HYG-3a), HYG-11 | HYG-9 | — |
| Capabilities | CAP-1…4, CAP-6, CAP-7, CAP-8 (`fn`/`::`/`data`/`struct`/`type`/`effect`/invocation/iteration templates; the kind list is closed, and `impl` left it when the construct was removed in 0.6.0), CAP-9 (the deriving clause is refused), CAP-10 (format strings; 10.5's capture is closed as of 0.7.4) | — | CAP-5 (its replacement has landed, and the query table is complete: join in name, reference and argument position, nested to any depth; constructors; fields; same; for, including its parallel form; binders; fold; name; arity; defined; format; formatln) |
| Safety | SAFE-1…4 | — | SAFE-5 |
| Integration | INT-1…6 | — | — |
| Diagnostics | DIAG-1…5 | — | — |
| Tooling | TOOL-1…6 | — | — |

One rule in the Holds column is held-but-defective: it holds, and its
defect is stated where the rule is defined. It is `MAC-EXP-8`: the
over-application diagnostic anchors at the expansion instead of at the
surplus argument. Listing such rules follows
[memory-model.md §9.0](memory-model.md)'s convention. The list as a
whole, not any one entry, is the case for gating.

The earlier entries on this list are fixed: `MAC-HYG-3a`,
`MAC-TOOL-6`, `MAC-EXP-11a`, `MAC-EXP-14a`, `MAC-CAP-3a` and
`MAC-CAP-10.5`. Each rule's definition says what changed.

### 11.1 What is gated

A number in brackets after a fixture is the answer it expects, from its
`; expect` line. "Without the fix" describes the compiler from before
the rule landed.

| Pinned by | Rules |
|---|---|
| `tests/selfhost/360-macro.ax` (45) | LANG-1, EXP-6 (nested invocation), EXP-7 (double evaluation) |
| `tests/selfhost/361-macro-hygiene.ax` (143) | HYG-1, HYG-2 |
| `tests/selfhost/362-macro-coverage.ax` (57) | CAP-1 |
| `tests/selfhost/368-macro-qualified.ax` (47) | LANG-12. Without the fix, the compiler refuses with two `AX3001`s. |
| `tests/selfhost/369-macro-vs-function.ax` (15) | HYG-8.3. Without the fix, the compiler silently answers 10. |
| `tests/selfhost/372-decl-macro.ax` (144) | CAP-8, EXP-16: two invocations of one macro, nested generation, and a qualified module invocation. Without the fix, the compiler exits 1. |
| `tests/selfhost/373-decl-macro-types.ax` (10) | EXP-17: substitution in type position recomputes the float flags |
| `tests/diagnostics/500-unknown-decl-head.ax` | CAP-8's unknown-head `AX3027`, twice, because the parse no longer stops at the first |
| `tests/diagnostics/505-decl-macro-positions.ax` | CAP-8's position rules: both template kinds refused across the boundary, and the bare-identifier name rule |
| `tests/diagnostics/510-decl-macro-template-kind.ax` | CAP-8's template-kind `AX3021`, at the macro's own line |
| `tests/selfhost/381-macro-type-templates.ax` (32) | CAP-7 and CAP-8's `data` and `struct` templates: joined constructor names, two invocations giving two distinct types, and `deriveEq` querying a type generated in the same round |
| `tests/selfhost/389-type-effect-templates.ax` (38) | CAP-8's `type` and `effect` templates: a joined alias name written in type position by the signature beside it, and an effect whose name, operation and arrow all come from the invocation |
| `tests/diagnostics/565-macro-type-template-limits.axbad` | What is still refused: an `import` template and a nested `macro`, at the macro's line (the two `AX3021` subjects are `badImport` and `badMacro`), and the reserved `syntax/` prefix in a data name and a constructor name. It is `.axbad` because the formatter must not learn a joined name at top level, the same reason `525` carries the extension. |
| `tests/selfhost/388-module-side-decl-macro.ax` (239) | EXP-16's module-side invocation: a module spends the prelude's derive on its own type, calls a private product, and an entry-file name coexists with the module's mangled one. Without the fix, the compiler refuses at the module's line. |
| `tests/diagnostics/515-decl-macro-in-module.ax` | EXP-16's visibility rule: a declaration generated from a non-`pub` template is `AX3023` outside its module, and the module's own call to it still works |
| `tests/selfhost/374-derive-eq.ax` (101) | CAP-5 and CAP-6: §10.2's nullary `deriveEq` verbatim, the roadmap's acceptance criterion. Without the fix, the compiler dies parsing the joined name. |
| `tests/selfhost/376-syntax-nested-for.ax` (7) | CAP-5: a nested `syntax/for` over two types, with the inner splice under the live outer binding |
| `tests/selfhost/386-syntax-parallel-for.ax` (63) | CAP-5's parallel `syntax/for`: the zip in all three positions, one bit each, positional past the first element. Without the fix, the compiler can't parse the file. |
| `tests/selfhost/390-multi-rule-macro.ax` (51) | LANG-14's arity selection across three rules, each a template in its own right |
| `tests/selfhost/392-macro-patterns.ax` (127) | LANG-15 and LANG-18: shape and literal-value dispatch in rule order. Without the fix, the compiler refuses the file at the first pattern's paren. |
| `tests/selfhost/393-macro-ellipsis.ax` (63) | LANG-16 v1: one repeating bare name, spliced into a constructor call |
| `tests/selfhost/397-nested-repeat.ax` (170) | LANG-16 v2: a repeat over a nested pattern, with six macros over matching and spine splices |
| `tests/selfhost/398-arm-ctor-splice.ax` (155) | LANG-16 v3 and v5: `arm ...` and `C ...` splices, including fixed-test and named field-test ctor patterns in spliced arms |
| `tests/selfhost/399-decl-splice.ax` (45) | LANG-16 v4: `decl ...` over parallel sequences, a `data` splice and a nested-invocation splice |
| `tests/selfhost/402-literal-dispatch.ax` (19) | LANG-17: `(literals ...)` head-spelling dispatch with the shadow veto, over `LitLib.ax` |
| `tests/selfhost/403-expr-rule-macro.ax` (153) | LANG-14's wide half: `emacro` rules over expression templates, with ellipsis and hygiene |
| `tests/diagnostics/600-macro-rule-unreachable.ax` | LANG-18's `AX3033`: an irrefutable rule starving a later one of its arity |
| `tests/diagnostics/605-macro-no-rule-matches.ax` | LANG-18's `AX3018`: every shape the macro accepts, joined from the tokens |
| `tests/diagnostics/610-macro-ellipsis-misuse.ax` | LANG-16's `AX3034`: all four depth refusals, plus the arm and spine interior rows |
| `tests/diagnostics/611-macro-literal.ax` | LANG-17's `AX3066`: a declared literal that no pattern spells |
| `tests/diagnostics/612-emacro-misuse.ax` | The refusals of LANG-14's wide half: `emacro` in declaration position (`AX3027`) and no rule matching (`AX3018`) |
| `tests/diagnostics/585-multi-rule-misuse.ax` | LANG-14's refusals: two rules of one arity, at the macro's line, and an invocation matching none, which names every arity the macro offers |
| `tests/diagnostics/575-syntax-parallel-for-misuse.axbad` | The zip's refusals: a skewed pair in each of the three positions, and a parallel binding that is not a pair. It is `.axbad` because the last is an expression to the parser and a non-shape to the grammar. |
| `tests/selfhost/387-syntax-nested-join.ax` (47) | CAP-5's nested `syntax/join`: a lens set over two structs sharing a field name, three-deep nesting, and the `getX`-twice collision that made the two-part form unusable |
| `tests/frontend/070-derive-macro.ax` (42) | The derive shape through `check`, `run`, `symbols`, `:load`, LSP and `fmt` in one place |
| `tests/selfhost/375-derive-lenses.ax` (34) | CAP-5's lens set, §10.3 verbatim: declaration- and argument-position `for`, `fields`, `same`'s spliced diagonal, and field-name substitution |
| `tests/diagnostics/530-syntax-same-keys.ax` | `syntax/same`'s refusals: a cross-sequence comparison names both sequences, and an unbound side names itself |
| `tests/diagnostics/535-syntax-for-toplevel.axbad` | Declaration-position `for` outside a template, refused and re-tagged inert. It is `.axbad` because the formatter rewrites the shape. |
| `tests/selfhost/377-derive-eq-fieldful.ax` (30) | CAP-5's fieldful rung: `binders`' deterministic `p#i` spelling through the renamer, `fold`'s parallel zip, and the empty fold as the nullary case |
| `tests/diagnostics/540-syntax-fold-misuse.ax` | The `fold` and `binders` refusals: zip-length mismatch, unknown constructor, a sequence in scalar position, and `fold`'s arity |
| `tests/selfhost/379-derive-imported.ax` (30) | CAP-9's shipped library: `stdlib/Pre.ax`'s `deriveEq` over an entry-file type and an imported one |
| `tests/diagnostics/550-derive-private-type.ax` | The query visibility rule: a private subject is refused at the invocation, with one diagnostic in the right place |
| `tests/selfhost/380-syntax-scalar-queries.ax` (41) | CAP-5's scalar rows: `syntax/name`, `syntax/arity`, `syntax/defined`, and a join standing as a callable reference. The consumers are `stdlib/Pre.ax`'s `deriveArity` and the fixture's own copies of `deriveShow` and `showOr`. The prelude's two are deprecated since 0.3.8, because the builtin `show` renders the whole value and they give only the constructor's name. |
| `tests/diagnostics/560-syntax-scalar-misuse.ax` | The scalar rows' refusals: an arity of nothing (naming `syntax/arity`, not the counter it shares a slot with), a bare query head, a non-identifier argument, and a one-part join |
| `tests/diagnostics/520-syntax-query-misuse.ax` | CAP-6's closure: an unknown query, a wrong-kind subject and a missing subject, all `AX3028` |
| `tests/selfhost/382-format-macros.ax` (255) | CAP-10's lowering: eight independent claims, one bit each, so a partial regression names itself in the exit status. They are interpolation, escaped braces, the three alignments, signed zero-padding, both hex cases, precision, conversion inside padding, and the degenerate literals. |
| `tests/stdlib/365-format.ax` | CAP-10 end to end, against a golden stdout: what actually reaches the descriptor |
| `tests/diagnostics/570-format-refusals.ax` | CAP-10.3's expander half: all eleven `AX3031` cases, each caret inside the literal on the offending byte |
| `tests/diagnostics/525-syntax-reserved.axbad` | CAP-6's reservation: `syntax/` spellings outside a template, including the near-miss one paren short. It is `.axbad` because the formatter must not learn these shapes. |
| `tests/diagnostics/485-qualified-private-macro.ax` | LANG-12's `AX3023` route for a qualified private macro |
| `tests/diagnostics/490-expansion-backtrace.ax` | DIAG-4: one frame and a nested two, with spans checked against the macro's own file |
| `tests/diagnostics/580-expansion-fix-suppressed.ax` | TOOL-5: the same two diagnostics from a macro and by hand. The expansion pair keeps its help text and loses its `~>`, and the hand-written pair keeps both. The expansion `AX3012` pair renders `tmp` (HYG-3a), not `tmp.1`/`tmp.0`. |
| `tests/diagnostics/654-macro-hygiene-suggestion.ax` | HYG-3a: a typo beside a renamed binder suggests the original spelling (`tmpvar`, no `~>`), and the hand-written control keeps its `~>"count"` |
| `tests/selfhost/363-macro-shadowing.ax` (3) | EXP-5 |
| `tests/selfhost/364-macro-definition-site.ax` (157) | HYG-6, HYG-7 |
| `tests/selfhost/365-macro-pattern-literal.ax` (95) | HYG-5 |
| `tests/diagnostics/990-macro-arity.ax` | EXP-8 |
| `tests/diagnostics/991-macro-recursion.ax` | EXP-11 |
| `tests/diagnostics/992-macro-duplicate-parameter.ax` | LANG-2 |
| `tests/diagnostics/993-macro-shadows-function.ax` | LANG-8, TOOL-1 |
| `tests/diagnostics/400-macro-size-limit.ax` | EXP-9 (node budget) |
| `tests/diagnostics/405-macro-depth-limit.ax` | EXP-9 (depth budget) |
| `tests/diagnostics/430-private-macro.ax` | LANG-9 |
| `tests/selfhost/370-pre-import.ax` (42) | INT-1: `stdlib/Pre.ax` erases entirely into rewrites |
| `tests/selfhost/MacScope.ax` | The cross-module helper that HYG-6 needs |
| `tests/fmt/parity/060-splice-refused.axp` | The backtick refusal that LANG-16 would flip |
| `tests/fmt/parity/230-backtick-refused.axp`, `231-comma-refused.axp`, `232-quote-refused.axp` | TOOL-6: one refusal per prefix marker, with `check` refusing all three too |
| `scripts/check-degenerate.sh` | SAFE-4 (four empty-form macro cases) |
| `scripts/check-diagnostics.sh` | Every `tests/diagnostics/` case above, byte for byte against its checked-in AXDL golden, plus a silence sweep whose floor over `tests/selfhost/` is 150 files |
| `scripts/check-tree-sitter.sh` | INT-6: `grammar.js`'s `macro_declaration` must parse every `.ax` in the repository |
| `scripts/check-reproducible.sh` | EXP-12 |
| `tests/lsp/drive.py`'s macro-navigation case | TOOL-2 and TOOL-3: definition lands on the macro's own name, hover quotes its declaration, and a non-macro name answers null. Both are derived from the document's bytes, not from a golden. |

To reproduce the macro corpus and its refusals:

```bash
scripts/check-self-host.sh 36        # 360-369, the macro corpus
scripts/check-diagnostics.sh 99      # 990-993 among them, the refusals
```

The "before" column below comes from an ablation: a compiler built from
the commit before expansion moved ahead of the checker. Built that way,
each case gives the "before" answer. Built from trunk, it gives the
"after" answer. That difference is what makes each fixture a
measurement rather than a regression guard.

| Case | want | before | after |
|---|---|---|---|
| `361-macro-hygiene` | 143 | 208 | 143 |
| `362-macro-coverage` | 57 | 4 (`AX4003`) | 57 |
| `363-macro-shadowing` | 3 | 18 | 3 |
| `364-macro-definition-site` | 157 | 1 (`AX3004`) | 157 |

One case turns an acceptance into a refusal:

| Case | before | after |
|---|---|---|
| `993-macro-shadows-function` | `OK`, exit 11 | `AX3006`, exit 1 |

These rules are unpinned, so they are documentation rather than
specification:

- `MAC-LANG-3`'s two spellings of a zero-parameter invocation;
- `MAC-EXP-6`'s ordering, that an unused argument is not expanded;
- `MAC-LANG-10`'s case of a private macro used from a public template;
- `MAC-LANG-11`'s last-definition-wins rule;
- `MAC-EXP-14`'s span assignment.

Each could be measured by a fixture of a few lines, and a future change
could break any of them silently.

Every documented limitation has a fixture. The last to get one was an
entry-file macro's free identifier being capturable (`MAC-HYG-8`.1),
and it is no longer a limitation. The reference now resolves at the
macro's own scope, and `tests/selfhost/394-macro-entry-capture.ax`
(130) measures the answer. Its old refusal code, `AX3032`, is retired.
`368-macro-qualified.ax` pins `MAC-LANG-12`'s qualified invocation,
`369-macro-vs-function.ax` pins `MAC-HYG-8`.3's macro-versus-function
resolution, and `372-decl-macro.ax` pins `MAC-LANG-5`'s declaration
position, which is `MAC-CAP-8` v1.

### 11.2 Are the limits normative?

`AX3019` names 128, and `AX3024` names 1024 and 2,000,000. All three
appear in the diagnostic text the user sees, so changing one changes a
checked-in `.axdl` golden.

The limits are **implementation-defined**. A conforming implementation
**MAY** choose others, but each diagnostic **MUST** state the limit it
enforced. That makes the number a fact about the run, not a constant
the reader has to look up. It is also why the goldens pin the text
rather than the value alone.

### 11.3 What is left

The Language row of the conformance table holds in full.
`MAC-LANG-17`, `MAC-LANG-16`'s nested half and `MAC-LANG-14` over
expression templates have all landed. What remains is narrower:

1. `MAC-HYG-9`, scope sets. Dispatch holds without them, through
   canonical-spelling comparison with the shadow veto. What they would
   add is narrow and stated in `MAC-LANG-17`: renamed heads that can
   never be spelled by accident, and constructor heads compared by
   spelling. The representation change stays provisional.
2. A repeated binder read as a same-form test, such as `(- e e)` in
   §10.4's `simplify` table. `MAC-LANG-15` refuses it as last-wins
   (`AX3020`). The table's templates are also expressions, which the
   rule form does not take. `emacro` takes one expression per rule, and
   the table needs rewriting as well as dispatch.
3. The one held-but-defective render in §11, `MAC-EXP-8`'s anchor,
   plus `MAC-EXP-14c`'s spanless nodes, which no invocation-span rule
   can reach.

Two features cost less than first estimated, and each is recorded where
it is specified. Imported-name capture needed only each declaration's
own module, not import edges that the merged declaration list doesn't
carry (§3.4). The ellipsis needed one implementation of the token set,
not four, because `...` lexes as an ordinary identifier (§1.5's table).
