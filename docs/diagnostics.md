# Axiom Diagnostics & Agent Notations

Axiom's compiler output is built around one goal: **tell an agent what it
needs to know to act, in as few tokens as possible.** A location without
an explanation forces every developer (human or AI agent) to re-derive
the reasoning the compiler already had; a signature the agent has to
re-parse out of pretty-printed prose is tokens spent re-deriving a fact
the compiler already computed exactly. This document describes two
members of the same notation family:

* **AXDL** (Axiom eXchange Diagnostic Line) - what went wrong, and where,
  and how to fix it. One line per diagnostic.
* **AXSYM** (Axiom eXchange Symbol Line) - what a file *successfully*
  declares, and what its type is. One line per symbol.

Both exist because an agent's two most common compiler-facing questions -
"why did this fail" and "what does this already provide" - deserve the
same design treatment: dense, greppable, colorless, one-line-per-fact,
with locations addressed identically across both notations. Neither
notation is a general "tag everything" scheme; each is scoped to exactly
one question so a consumer never has to guess which fields a given line
might contain.

All diagnostics flow through a single structured type,
`Diag` in [`self_host/diag.ax`](../self_host/diag.ax), built at every
stage that can refuse: the parser (which raises the lexer's errors too -
`lexErrDiag` reads the code off the offending byte), the macro expander,
the type checker, and the codegen and driver stages that lower and link.
That one representation is
rendered into whichever of the formats below you ask for with
`--diagnostic-format`; the renderers never see anything the compiler
didn't already know, so `human`, `ai`, and `json` output can never
disagree about *what* went wrong.

## Stable diagnostic codes

Every diagnostic (except a handful of catch-all fallbacks) carries a
stable code such as `AX3001`, in the same spirit as `rustc`'s `E0308`.
Codes are namespaced by compiler stage:

| Range | Stage |
|---|---|
| `AX1xxx` | Lexical analysis |
| `AX2xxx` | Parsing / syntax |
| `AX3xxx` | Semantic analysis / type checking |
| `AX4xxx` | IR lowering, codegen, and the native toolchain |
| `AX5xxx` | Module/import resolution |

Macro expansion runs as part of semantic analysis and its refusals live
in `AX3xxx`: `AX3018` arity, `AX3019` recursion limit, `AX3020`
duplicate parameter, `AX3021` an unsupported template form, `AX3022` a
`set` target that is not a name, `AX3024` the expansion-size limit,
`AX3027` a declaration-macro invocation the expander cannot resolve,
`AX3028` a `syntax/*` query with no answer, `AX3033` a rule that can
never match, `AX3034` an ellipsis used at the wrong depth, `AX3035` a
binder parameter given something that is not a variable. All eleven are
constructed in `self_host/expand.ax` (`AX3028` in
`self_host/typecheck.ax` as well). See
[macro-system.md](macro-system.md).

Module visibility lives there too: `AX3023` is a reference to a name
that exists, in a module that does not export it — the declaration is
not `pub`, or the `(import M (a b))` that brought the module in does
not list it. It is a *different* mistake from `AX3001`, which is a name
that is defined nowhere, and it did not exist before a module could
have a private declaration at all.

Two codes constrain a string the source hands straight to something
outside the compiler, and both are constructed in `self_host/parser.ax`
even though only one of them numbers as a syntax error.

`AX2006` refuses a module-path segment containing `/`. `(import M)`
names a module, and the resolver turns that name into a filename by
concatenating each search directory onto it in turn — so a segment that
is already a path re-anchors the concatenation and reads a file the
search directories never offered. Measured on 2026-08-23:
`(import /tmp/axtrav/secret)` compiled a file outside the project and
`axiom check` printed `OK`. `/` stays an ordinary identifier byte
everywhere else, because `syntax/format` and `syntax/join` are spelled
with one; only a module path is constrained, and only a module path
becomes a filename
(`tests/diagnostics/955-import-absolute-path.axbad`).

`AX3041` refuses an `extern` block's library name that is not one. That
string is the stem of `lib<name>.a`, so it is `[A-Za-z0-9._+-]` and may
not be empty, and it has two verbatim consumers: the driver passes it to
the linker as `-l<name>`, and the emitter writes it beside the block's
`declare` lines as `; axiom-extern-lib <name>`. An LLVM `;` comment ends
at the newline, so a name carrying one used to close that comment and
leave every following line as live module-level IR — measured on
2026-08-23, a global and a `define` with a body reached the executable
and `nm` listed both. The injection lands after the type checker, the
effect system and the freestanding gate, and the driver's grounding pass
reads `declare` lines only, so nothing downstream saw it
(`tests/diagnostics/945-extern-lib-newline.axbad`). It is numbered as a
semantic refusal rather than a syntactic one because the token is a
perfectly well-formed string literal; what is refused is what the string
means to the linker. The lexer is deliberately not the place for it: a
line break inside a string literal is an ordinary character by decision,
and that decision belongs to the language rather than to one consumer of
one string.

`AX3044` refuses a bare TYPE name that two or more imported modules
declare, where nothing module-less outranks them and the reference is
inside neither. It is `AX3014`'s type-namespace sibling and is a
separate code because the ESCAPE is different: `AX3014` tells the
reader to write `Mod::name`, and in type position that does not parse
at all (`parseTypeAtom` has no `::` arm), so answering `AX3014` there
would hand the reader a fix that fails to compile. What it says
instead is to narrow one of the imports with a name list, or to rename
one declaration. Until 2026-08-24 there was no diagnostic here of any
kind: a type name resolved to whichever declaration came first in the
merged list, which is import order, so a module's own bodies could be
compiled against another module's field offsets — at exit 0, with the
answer changing when an unrelated `(import ...)` line moved
(`scripts/check-type-namespace.sh`, `tests/selfhost/491`-`494`).

Codes are stable across wording changes, so you can grep for them in CI,
pattern-match on them in editor tooling, or look them up directly:

```bash
axiom explain AX3001        # full explanation of one code
axiom explain --list        # every known code
```

Each code also has a kebab-case **slug** (e.g. `undefined-variable`) that
is wording-independent and appears in both the human report's footer link
and every line of AI-notation output, so tooling can match on the slug
without depending on the numeric code at all.

## Cascade suppression

Previously, a single root-cause error (e.g. one undefined variable) could
produce a wall of unrelated downstream errors, because the type checker
kept assigning a fresh placeholder type after the failure and reused it
as if it were real. That placeholder would then fail *other* type checks,
producing 2-3 more "errors" that were really just echoes of the first one.

Axiom's type checker now propagates a `TypeId::TError` **poison** type
after reporting a failure, and every downstream check treats a poisoned
type as "already explained, don't check again" (`is_error()` guards at
every type-mismatch construction site in `self_host/typecheck.ax`). This is the actual,
exercised mechanism behind every cascade fix today.

The Rust compiler additionally carried a `group` key and an
`axiom_errors::dedup` pass that dropped every diagnostic after the first
in a group. It had no call sites - poisoning covered the one cascade
that exists - so it was a no-op for the whole life of that compiler, and
it was not carried across when the crate was deleted. If a cascade ever
turns up that poisoning and span guards cannot prevent, that is when to
build it; the lesson from the Rust version is to build it with a call
site rather than ahead of one.

The second suppression that IS exercised is spanlessness: a node with no
span suppresses its diagnostic rather than pointing it somewhere wrong.
There are ten `span == 0` guards in `self_host/typecheck.ax` and
they are the reason a diagnostic never lands on line 1 column 1 by
accident.

Concretely, this:

```lisp
(:: main Int)
(define main (+ (foo 1 2) 0))
```

reports exactly **one** diagnostic - `foo` is undefined. The poisoned
type flows into `+` and back out into `main`'s declared `Int`, and
neither comparison reports a second time.

## Human format (`--diagnostic-format=human`, default)

rustc-flavored reports: the offending line is quoted, the exact span is
underlined and labelled, and a code, a message, any notes and every help
are shown.

```
error[AX3001]: undefined variable `foo`
 --> main.ax:3:4
  |
3 |   (foo 1 2))
  |    ^^^ no binding named `foo` in scope
  |
  = help: variables must be defined (via `define`/`fn`, a `let` binding, or a lambda parameter) before they are used; check for typos
  = help: run `axiom explain AX3001` for a full explanation

compilation failed due to 1 previous error
```

**The real output is coloured** - severity and carets in the severity's
colour, the gutter blue, the `= help:` marker green - and always is,
including when stderr is redirected. Shown plain here because a markdown
code fence is not a terminal. The palette is one table in
`self_host/style.ax`.

Notes on the layout, all of them things the renderer is checked on:

* **Columns count characters, not bytes**, so a caret under a line
  containing an em dash lands where the eye expects. Tabs expand to the
  next multiple of four, and the caret is placed in DISPLAY columns
  while the `-->` line keeps the character column AXDL reports - those
  are different numbers on a tab-indented line and both are right.
* **A line wider than 160 columns is quoted as a window**, 20 columns
  before the span, marked `...` on whichever side was elided.
* **Every help renders.** The header line number comes from the primary
  span, and a span past end of file is clamped so "unexpected end of
  file" shows the last real line instead of rendering blank.
* **A machine-applicable fix shows its replacement**, after `~>` - the
  same notation AXDL uses for the same fact.

## AI-optimized notation (`--diagnostic-format=ai`)

Axiom introduces **AXDL** (Axiom eXchange Diagnostic Line): one dense,
colorless, greppable line per diagnostic, designed to minimize the tokens
an LLM agent burns reading compiler output. The design rationale:

* **No re-rendered source.** An agent working on a file already has its
  contents in context; re-printing the offending line plus a box-drawn
  frame around it is pure token waste. AXDL gives you the exact
  `line:col` range and nothing else about the source text.
* **No ANSI color codes or Unicode box-drawing.** These are either
  stripped by the tokenizer inconsistently or cost extra tokens for zero
  semantic value to a model.
* **Exactly one line per diagnostic.** `grep -c '^E '` counts errors.
  `grep AX3001` or `grep undefined-variable` filters by kind. No
  multi-line state machine is needed to know where one diagnostic ends
  and the next begins.
* **Both the stable code and the wording-independent slug are present**,
  so matching works whether the tool knows Axiom's numeric codes or not.
* **Machine-applicable fixes are inline, not prose.** When a suggestion
  has a known replacement, it's encoded as `<loc>:"<msg>"~>"<replacement>"`
  so a tool (or an agent) can apply it with a plain byte-range
  substitution instead of parsing English.

### Grammar

```
<SEV> <CODE> <FILE>:<LOC> <SLUG> "<MESSAGE>" [#"<label>"]
     [^<LOC>:"<related>"]* [!"<note>"]* [?<field>]* [&"<frame>"]*
```

| Field | Meaning |
|---|---|
| `SEV` | `E` (error) or `W` (warning). See the note below on `N` and `H`. |
| `CODE` | Stable code, e.g. `AX3001` |
| `FILE:LOC` | `file:line:col` or `file:line:col-col` or `file:line:col-line:col` |
| `SLUG` | kebab-case, wording-independent diagnostic kind |
| `"MESSAGE"` | Quoted human message (still present - codes alone don't carry the specific name/type involved) |
| `#"label"` | The primary span's own label, the sentence the human renderer prints after the carets. Absent when it would only repeat the message. |
| `^LOC:"msg"` | A secondary/related span, e.g. the other side of a type mismatch |
| `!"note"` | An additional note: a fact about why the program is wrong, as against a help, which is an action that would make it right |
| `?"msg"` or `?LOC:"msg"~>"replacement"` | A help suggestion; the `~>` form is machine-applicable |
| `&"name"` or `&FILE:LOC:"name"` | One frame of the expansion backtrace, outermost first: the macro's name, and - in the located form - the span of its DECLARATION. Uniquely among the line's fields, that `FILE` is not the diagnostic's own: the span indexes the macro's file, which is why the file is spelled out where `^` and `?` leave it implied |

Every field marked `*` repeats. Fields appear in exactly the order
above, and a consumer that meets one it does not know should fail rather
than skip it - `tests/diagnostics/verify-axdl-spans.py` does, and that
is how the `!` field was found to be documented in three places and
implemented in none.

`N` and `H` are reserved as severities and are not emitted: every
diagnostic this compiler builds is an error or a warning, and a note or
a help is a FIELD of one rather than a diagnostic of its own.

`&` is macro expansion's field, and it had no producer until
2026-08-14. A diagnostic raised inside an expansion now carries one
frame per enclosing macro, outermost first, each naming the macro and
the span of its own declaration in its own file:
`tests/diagnostics/490-expansion-backtrace.ax` pins one frame and a
nested two, and `tests/diagnostics/595-macro-imported-ambiguous.ax`
pins an `AX3014` reported at an invocation that mentions neither the
name nor the modules, where the frame is the whole of what makes the
line actionable.

`tests/selfhost/645-axdl-repetition.ax` is still the case that pins the
GRAMMAR: it builds one diagnostic carrying two of every repeating
field and renders the whole line, which is how a combination no real
producer emits stays covered.

**Severity decides the exit status.** Only `E` fails a build: a run that
produces nothing but `W` still exits zero, and the summary
line counts errors alone, so one error alongside one warning is reported
as "1 previous error". Warnings are printed either way — on the failing
path they appear next to the errors, because not failing a build must
not mean not reporting. The split is derived from the rendered severity
rather than from a list of diagnostic kinds, so the letter a reader sees
and the behaviour they get cannot drift apart.

**Parsing note:** `"msg"` and `"replacement"` are always emitted using
Rust's `Debug`-style string escaping (embedded `"`, `\`, and newlines are
backslash-escaped), so a diagnostic is guaranteed to stay on exactly one
line and every quoted field has an unambiguous end. However, the message
or replacement text itself is *not* forbidden from containing the literal
two-character sequence `~>` (e.g. a diagnostic about arrow types). A
correct consumer must therefore parse each quoted field as a proper
escaped string (find the matching unescaped closing `"`) and only look for
the `~>` separator in the unquoted gap *between* the two quoted fields -
never do a naive whole-line `str.split("~>")`, which can misfire if `~>`
appears inside the message itself.

### Example

Source:

```lisp
(:: helper (-> Int Int))
(define (helper x) (+ x 1))

(:: main Int)
(define main
  (helpr 5))
```

AXDL output:

```
E AX3001 main.ax:6:4-9 undefined-variable "undefined variable `helpr`" #"no binding named `helpr` in scope" ?6:4-9:"a similarly named binding `helper` is in scope; did you mean this?"~>"helper"
```

Everything a human report would tell you is present - the exact span,
the kind of error, the primary label, the message and a
machine-applicable fix - in a single 193-byte line instead of a
multi-line, ANSI-coloured report several times that size.

## JSON Lines (`--diagnostic-format=json`)

For tooling that would rather not parse either prose format, each
diagnostic is also available as one JSON object per line (not a JSON
array, so output can be streamed):

```json
{"severity":"error","code":"AX3001","slug":"undefined-variable","message":"undefined variable `helpr`","file":"main.ax","span":{"start":{"line":6,"col":4},"end":{"line":6,"col":9},"char_start":84,"char_end":89},"label":"no binding named `helpr` in scope","related":[],"notes":[],"help":["a similarly named binding `helper` is in scope; did you mean this?"],"expansion":[]}
```

`expansion` is the array form of AXDL's `&` field, one object per
enclosing macro; it is empty for a diagnostic raised outside an
expansion.

`char_start`/`char_end` are **character offsets**, not byte offsets.
The compiler's own spans count bytes - the lexer walks the source a byte
at a time and a `Span` is a byte range - and this renderer converts them
(`charsBetween` in `self_host/render.ax`), so the two offset fields are
character-indexed whatever the representation behind them is. For source
containing only ASCII text the two coincide; for source with multi-byte
UTF-8 characters, only the character offsets are meaningful - do not use
these fields as byte indices into the file.

## AXSYM: symbol/type notation (`axiom symbols`)

AXDL only fires when something is wrong. It has nothing to say about
Axiom's other constant agent-facing question: *"what does this file
already declare, and what type does it have?"* Answering that today
without tooling means an agent re-reads the whole file and re-derives
every signature by eye - exactly the "re-derive what the compiler
already knew" waste AXDL was built to avoid, just for the success case
instead of the failure case.

`axiom symbols <file>` runs the same lexer -> parser -> type-checker
pipeline as `check` (including resolving `(import ...)`s, which is why
a symbol's `FILE` is the file that declared it - see the `FILE:LOC` row
below), then prints one fact per top-level name the checker collected:
every `define`/`fn`, every `data` type and its constructors, every
`struct` (with its exact field shapes), every `type` alias, and every
trait.

```bash
# The aligned table, one line per symbol - the default
axiom symbols main.ax

# AXSYM: the same facts, plus the nid and the metadata
axiom --diagnostic-format=ai symbols main.ax

# Also list the always-in-scope builtins - 18 operators (+, ==, &&, ...)
# and 26 primitives (__syscall0, __alloc, ...) - omitted by default
axiom symbols main.ax --builtins
```

**Two renderings of one set of facts.** The default is an aligned
table: the kind spelled out, the name, the type, and the location in
brackets, with `[builtin]` where AXSYM writes `-`.

```
Fn       add                  (Int -> (Int -> Int))                    [main.ax:9:5-8]
Data     Maybe                data Maybe                               [main.ax:1:7-12]
```

`--diagnostic-format=ai` gives AXSYM, the notation this language is
designed around: the same facts plus the nid and the metadata the table
has no column for. The table is derived by re-reading the AXSYM text
(`symbolsHumanTable` in `self_host/symbols.ax`) rather than by a second
walk over the collected facts, so the two cannot disagree about what the
symbols are. `json` has no symbol renderer of its own: asking for it
prints a note saying so and answers in AXSYM rather than silently
answering with something else, since the flag selects the format of
*diagnostics*, which is what it is named for.

### Grammar

```
<KIND> <NAME> <FILE>:<LOC>|- "<TYPE>" [@<NID>] [#<key>=<value>]*
```

| Field | Meaning |
|---|---|
| `KIND` | One letter: `F` function, `D` data type, `C` constructor, `S` struct, `A` type alias, `T` trait, `E` effect declaration, `M` macro |
| `NAME` | The declared name, exactly as written |
| `FILE:LOC` | Same `file:line:col[-col\|:line:col]` addressing as AXDL, via the same source map in [`self_host/diag.ax`](../self_host/diag.ax) - for a program with `(import ...)`s, `FILE` is the *actual* file that declared this symbol (an imported module's own file), not always the entry file, exactly like AXDL's own multi-file attribution |
| `-` | In place of `FILE:LOC`, for a name with no source span at all: the 18 built-in operators (`+`, `==`, `&&`, ...) and the 26 primitives (`__syscall0`, `__alloc`, ...), which `axiom symbols` omits unless `--builtins` is passed (they never change, so printing them on every call is exactly the restating-what's-already-known token waste this notation exists to avoid), and the built-in `Option` type with its two constructors, which is always listed because a file's own code names it |
| `"TYPE"` | Axiom's own curried type syntax, quoted (it can itself contain `->`/parens, so quoting keeps the line's field boundaries unambiguous the same way AXDL quotes messages) |
| `#key=value` | Kind-specific metadata (see below) |

Metadata keys actually emitted today:

| Key | Kinds | Meaning |
|---|---|---|
| `ctors` | `D` | Comma-separated constructor names, e.g. `#ctors=Nothing,Just` |
| `of` | `C` | The constructor's owning data type, e.g. `#of=Maybe` |
| `fields` | `S` | `name:Type,name:Type,...` - the actual field shapes, not just a count, e.g. `#fields=x:Int,y:Int` |
| `methods` | `T` | `name:Type,name:Type,...` for the trait's methods, same shape as `fields` |
| `tyvars` | `A` | Comma-separated type parameters, e.g. `#tyvars=a,b`, omitted when there are none |
| `effects` | `F` | The effect row the checker derived, sorted and comma-separated, e.g. `#effects=IO`; absent when the function performs none. An `extern` item carries `#effects=IO` |
| `effect-params` | `F` | For an effect-polymorphic signature, the parameters the row varies in, by their declared names |
| `effects-incomplete` | `F` | The walk met a call it could not resolve - a struct field or an opaque local holding a function, or a call applying a callee's result - so `#effects=` is a LOWER bound. A row with nothing but this carries no `#effects=` at all |
| `effects-overapprox` | `F` | Some member of `#effects=` is only POSSIBLE: contributed by naming an arrow-typed function without calling it, or by a trait method with more than one implementation. Always beside `effects-possible` |
| `effects-possible` | `F` | Which members those are, sorted and comma-separated, e.g. `#effects-possible=IO` on `(fn (handoff k) shout)`. A member the body also performs definitely is not listed; `#effects=` stays the union either way (see [reference.md](reference.md), "Definite and possible") |
| `generated` | `F` | The declaration macro that wrote this declaration, for a name no line of the file spells |
| `calls` | `F` | **Only with `--calls`.** The call edges the effect walk resolved to derive the `#effects=` row beside it, sorted and comma-separated. Names the *resolved* entry - `Mod$name` where the checker mangled it, which is also the symbol codegen emits - so an edge says which `writeStr`. A bare reference is an edge too, because the effect walk attributes one exactly as it attributes a call. Absent by default: it would otherwise land on every row of every golden. See [agent-harness.md](agent-harness.md) §3.5 |

AXTAG keys (`#effect=io`, `#pure`, ...) join these on `F`, `D`, `S`,
`A` and `T` - and, since 2026-08-30, on `E`: an `effect` declaration's
tags were parsed, attached and rendered by nobody until
`;@axiom:unhandled(trap)` became a claim the compiler acts on, so
`#unhandled=trap` on the `E` row is how a policy gate reading this
stream lists the effects a program allows to abort. See the AXTAG
section below.

`KIND` letters are deliberately disjoint from the severity sigils `E`/`W`/`N`/`H`, so the first character of a line is never ambiguous about which notation (or which command) produced it even if AXDL and AXSYM output were ever concatenated into one stream.

### Example

Source:

```lisp
(data Maybe (a)
  (Nothing)
  (Just a))

(struct Point
  (x : Int)
  (y : Int))

(:: add (-> Int Int Int))
(fn (add x y)
  (+ x y))
```

Default output, the aligned table:

```
Fn       add                  (Int -> (Int -> Int))                    [main.ax:9:5-8]
Data     Option               data Option                              [builtin]
Ctor     Some                 (a -> Option a)                          [builtin]
Ctor     None                 Option a                                 [builtin]
Data     Maybe                data Maybe                               [main.ax:1:7-12]
Ctor     Nothing              Maybe a                                  [main.ax:2:4-11]
Ctor     Just                 (a -> Maybe a)                           [main.ax:3:4-8]
Struct   Point                struct Point                             [main.ax:5:9-14]
```

The same file under `--diagnostic-format=ai`, where the nid and the
metadata the table has no column for come with it:

```
F add main.ax:9:5-8 "(Int -> (Int -> Int))" @27bcb2cac184465e
D Option - "data Option" #ctors=Some,None
C Some - "(a -> Option a)" #of=Option
C None - "Option a" #of=Option
D Maybe main.ax:1:7-12 "data Maybe" @247d1682b2330461 #ctors=Nothing,Just
C Nothing main.ax:2:4-11 "Maybe a" #of=Maybe
C Just main.ax:3:4-8 "(a -> Maybe a)" #of=Maybe
S Point main.ax:5:9-14 "struct Point" @aa47cd1e9254cc56 #fields=x:Int,y:Int
```

The built-in `Option` and its constructors are listed either way; the
operators and the primitives are not, unless `--builtins` is passed.

An agent asked to "add a function that formats a `Maybe Int`" can now
`grep '^D Maybe'`/`grep '^C '` for the exact constructor set and
`grep '^S Point'` for its exact field shapes, instead of paying to
re-read and re-parse the whole file just to recover facts the type
checker already has in hand.

### Why this found a real parser bug

Building AXSYM immediately exposed that `(data Maybe (a) (Nothing) (Just
a))` - the README's own example - was parsing `(a)` as a *third,
spurious nullary constructor named `a`* instead of a type-parameter list,
because `parse_tyvars` only recognized bare, unparenthesized type
variables. Every parenthesized-tyvar example in the README (which is all
of them) was affected, and `(type StringList () = [String])` failed to
parse at all. This is exactly the payoff a dense, greppable success-path
notation is supposed to deliver: the moment "what does this file
actually declare" became one `grep`-able line per symbol instead of
prose an agent (or a human) has to re-derive by eye, a real correctness
bug that pretty-printed output had been silently absorbing became
obvious immediately. See `self_host/parser.ax`'s type-variable parsing and
`looks_like_tyvar_list` for the fix.

## Adding a new diagnostic

1. Pick the next free number in the appropriate range: `AX1xxx`
   lexical, `AX2xxx` parse, `AX3xxx` semantic (macro expansion
   included), `AX4xxx` IR lowering, codegen and the native toolchain,
   `AX5xxx` module resolution.
2. Construct it with `mkDiag` - or `mkDiagFix` when the help is
   machine-applicable and should render as `?LOC:"msg"~>"replacement"` -
   at the site that detects the condition. That site is one of
   `self_host/parser.ax` (which raises the lexer's errors too),
   `self_host/expand.ax`, `self_host/typecheck.ax`,
   `self_host/codegen.ax` or `self_host/driver.ax`. It takes a
   severity, the code, a kebab-case slug, a span, a message and a help.
3. Write its long-form text into `self_host/explain.ax`, so
   `axiom explain AX....` answers. This is enforced:
   `scripts/check-tools-selfhost.sh` cross-checks every code the
   diagnostics corpus emits against `explain --list`, so a new
   diagnostic cannot ship undocumented.
4. If the new error can be a downstream consequence of another, prefer
   poisoning: propagate the error type from the failing check rather
   than a fresh placeholder, and guard later comparisons, so one mistake
   draws one diagnostic rather than a cascade.
5. Add a case to `tests/diagnostics/` with its `.axdl` and `.human`
   goldens - `.axbad` if it deliberately does not parse, because the
   formatter and grammar gates sweep every `*.ax` and require it to
   parse. Bless with `AXIOM_BLESS=1 scripts/check-diagnostics.sh NNN`,
   then prove the case is not vacuous by checking it FAILS against a
   compiler built from before the change.

## Stable node IDs and source-embedded tags

Both NID and AXTAG are now implemented.

* **NID (stable node ID).** Every named declaration gets a content-derived
  ID - a short hash of `(kind, name)` - that survives edits elsewhere in
  the file and small reformatting, unlike a character offset. AXSYM lines
  emit an optional `@NID` field after the type. This is *not* "line numbers
  with extra steps" - the whole point is a coordinate that is stable exactly
  when `file:line:col` is not.

* **AXTAG (source-embedded agent metadata).** A reserved comment form -
  `;@axiom:<key>(<value>)` immediately above a declaration - for
  agent-authored, compiler-checked intent. The lexer preserves AXTAG tokens
  as trivia attached to the following declaration, the parser attaches them
  to the AST, and `axiom symbols` surfaces accepted tags as `#`-metadata
  on the corresponding AXSYM line (e.g. `#effect=io`, `#pure`).

  Sema validates what it can: `effect(io)` claims are checked against
  what the body actually performs - a `__syscallN`, or a call to
  something that performs one - and `pure` claims are checked against
  the absence of any effect. A mismatch the checker can decide emits `AX3010` /
  `axtag-mismatch`, an **error** since 2026-08-25, so a build that
  succeeded is one whose claims the compiler stood behind rather than
  one an agent must re-read the warnings of. A claim it is not in a
  position to check is `AX3037`, which remains a warning. A
  `restrict(no-io | no-alloc | no-foreign | no-cast | no-cast:deep |
  no-recursion)` claim is checked against the same effect row and the
  call graph: a violation is `AX3049`, an error, whose message renders
  the path of resolved calls to where the effect enters, or the cycle; a claim over a row the walk could not close is
  `AX3051`, a warning; a name that is not a restriction is `AX3052`,
  an error, because that list is closed
  ([reference.md](reference.md), AXTAG Keys). Other tags
  (`no_refactor`, `owned(arena=frame)`, etc.) are preserved and
  emitted but not yet validated.

AXSYM output for a file whose first declaration carries `;@axiom:pure`,
whose second is an `extern` item and whose third is a data type - the
nid after the type, the metadata after the nid:

```
F double main.ax:2:5-11 "(Int -> Int)" @c74a58529d6a1016 #pure
F addTwo main.ax:6:4-10 "(Int -> (Int -> Int))" @531b42e47de2ddf6 #effects=IO
D Maybe main.ax:8:7-12 "data Maybe" @247d1682b2330461 #ctors=Nothing,Just
```

An `extern` item is an `F` like any other function - it has a name, a
type and a span - and the effects it is credited with are the ones a
call to it performs.
