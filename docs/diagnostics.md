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
`Diag` in [`self_host/diag.ax`](../self_host/diag.ax), produced
by the lexer, parser, and semantic analyzer. That one representation is
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
There are thirteen `span == 0` guards in `self_host/typecheck.ax` and
they are the reason a diagnostic never lands on line 1 column 1 by
accident.

Concretely, poisoning today makes this:

```lisp
(:: main Int)
(define main (foo 1 2) 0)
```

now reports exactly **one** diagnostic (`foo` is undefined), instead of
three.

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
| `&"frame"` | One frame of the expansion backtrace, outermost first |

Every field marked `*` repeats. Fields appear in exactly the order
above, and a consumer that meets one it does not know should fail rather
than skip it - `tests/diagnostics/verify-axdl-spans.py` does, and that
is how the `!` field was found to be documented in three places and
implemented in none.

`N` and `H` are reserved as severities and are not emitted: every
diagnostic this compiler builds is an error or a warning, and a note or
a help is a FIELD of one rather than a diagnostic of its own.

`&` has no producer yet. Macro expansion does not report through
diagnostics (docs/v1-roadmap.md records the backtrace as part of that
work), so the field is rendered only by
`tests/selfhost/645-axdl-repetition`, which builds one diagnostic
carrying two of every repeating field and pins the whole line.

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
E AX3001 main.ax:6:4-9 undefined-variable "undefined variable `helpr`" ?6:4-9:"a similarly named binding `helper` is in scope; did you mean this?"~>"helper"
```

Everything a human report would tell you is present - the exact span,
the kind of error, the message, and a machine-applicable fix - in a
single 190-byte line instead of a multi-line, ANSI-colored, box-drawn
report several times that size.

## JSON Lines (`--diagnostic-format=json`)

For tooling that would rather not parse either prose format, each
diagnostic is also available as one JSON object per line (not a JSON
array, so output can be streamed):

```json
{"severity":"error","code":"AX3001","slug":"undefined-variable","message":"undefined variable `helpr`","file":"main.ax","span":{"start":{"line":6,"col":4},"end":{"line":6,"col":9},"char_start":84,"char_end":89},"label":"no binding named `helpr` in scope","related":[],"notes":[],"help":["a similarly named binding `helper` is in scope; did you mean this?"]}
```

`char_start`/`char_end` are **character offsets**, not byte offsets:
Axiom's lexer tokenizes a `Vec<char>`, so every span everywhere in the
compiler (and therefore every renderer) is character-indexed end to end.
For source containing only ASCII text the two coincide; for source with
multi-byte UTF-8 characters, only the character offsets are meaningful -
do not use these fields as byte indices into the file.

## AXSYM: symbol/type notation (`axiom symbols`)

AXDL only fires when something is wrong. It has nothing to say about
Axiom's other constant agent-facing question: *"what does this file
already declare, and what type does it have?"* Answering that today
without tooling means an agent re-reads the whole file and re-derives
every signature by eye - exactly the "re-derive what the compiler
already knew" waste AXDL was built to avoid, just for the success case
instead of the failure case.

`axiom symbols <file>` runs the same lexer -> parser -> type-checker
pipeline as `check` (including resolving `(import ...)`s, see
`docs/diagnostics.md`'s multi-file notes below), then prints one fact per
top-level name the checker collected: every `define`/`fn`, every
`foreign` binding, every `data` type and its constructors, every
`struct` (with its exact field shapes and layout attributes),
every `type` alias, and every trait.

```bash
# AXSYM, one line per symbol - the only format, and the default
axiom symbols main.ax

# Also list Axiom's dozen always-in-scope built-in operators (+, ==, &&, ...),
# which are omitted by default (see the `-`/builtins row below)
axiom symbols main.ax --builtins
```

**`symbols` emits AXSYM and nothing else.** The Rust implementation of
this compiler had three renderers for it - an aligned human table, which
was its default, one JSON object per line, and AXSYM - and the
self-hosted compiler that replaced it has only AXSYM, which is also its
default. That is deliberate: AXSYM is the notation this language is
designed around, the human table was a strict subset of it (dropping the
nid and the metadata), and nothing consumed the JSON. Asking for either
of the other two with `--diagnostic-format` prints a note saying so
rather than silently answering with something else; the flag still
selects the format of *diagnostics*, which is what it is named for.

### Grammar

```
<KIND> <NAME> <FILE>:<LOC>|- "<TYPE>" [#<key>=<value>]*
```

| Field | Meaning |
|---|---|
| `KIND` | One letter: `F` function, `X` foreign binding, `D` data type, `C` constructor, `S` struct, `A` type alias, `T` trait |
| `NAME` | The declared name, exactly as written |
| `FILE:LOC` | Same `file:line:col[-col\|:line:col]` addressing as AXDL, via the same source map in [`self_host/diag.ax`](../self_host/diag.ax) - for a program with `(import ...)`s, `FILE` is the *actual* file that declared this symbol (an imported module's own file), not always the entry file, exactly like AXDL's own multi-file attribution |
| `-` | In place of `FILE:LOC`, for names with no source span at all - in practice, only Axiom's dozen built-in operators (`+`, `==`, `&&`, ...), which `axiom symbols` omits entirely unless `--builtins` is passed (they never change, so printing them on every call is exactly the restating-what's-already-known token waste this notation exists to avoid) |
| `"TYPE"` | Axiom's own curried type syntax, quoted (it can itself contain `->`/parens, so quoting keeps the line's field boundaries unambiguous the same way AXDL quotes messages) |
| `#key=value` | Kind-specific metadata (see below) |

Metadata keys actually emitted today:

| Key | Kinds | Meaning |
|---|---|---|
| `ctors` | `D` | Comma-separated constructor names, e.g. `#ctors=Nothing,Just` |
| `of` | `C` | The constructor's owning data type, e.g. `#of=Maybe` |
| `fields` | `S` | `name:Type,name:Type,...` - the actual field shapes, not just a count, e.g. `#fields=x:Int,y:Int` |
| `packed` / `repr=C` / `align=N` | `S` | The struct's layout attribute, when it has a non-default one |
| `methods` | `T` | `name:Type,name:Type,...` for the trait's methods, same shape as `fields` |
| `symbol` | `X` | The real linked C symbol name from `(foreign name :: Type = "c_symbol")`, e.g. `#symbol=printf` - not always the same as `NAME` |
| `tyvars` | `A` | Comma-separated type parameters, e.g. `#tyvars=a,b`, omitted when there are none |

`KIND` letters are deliberately disjoint from the severity sigils `E`/`W`/`N`/`H`, so the first character of a line is never ambiguous about which notation (or which command) produced it even if AXDL and AXSYM output were ever concatenated into one stream.

### Example

Source:

```lisp
(foreign printf :: (-> String Int) = "printf")

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

AXSYM output (`--diagnostic-format=ai symbols`, builtins omitted by default):

```
X printf main.ax:1:10-16 "(String -> Int)" #symbol=printf
F add main.ax:11:5-8 "(Int -> (Int -> Int))"
D Maybe main.ax:3:7-12 "data Maybe" #ctors=Nothing,Just
C Nothing main.ax:4:4-11 "Maybe" #of=Maybe
C Just main.ax:5:4-8 "(a -> Maybe a)" #of=Maybe
S Point main.ax:7:9-14 "struct Point" #fields=x:Int,y:Int
```

An agent asked to "add a function that formats a `Maybe Int`" can now
`grep '^D Maybe'`/`grep '^C '` for the exact constructor set and
`grep '^X printf'` for the exact FFI signature, instead of paying to
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
   lexical, `AX2xxx` parse, `AX3xxx` semantic, `AX5xxx` module
   resolution.
2. Construct it with `mkDiag` - or `mkDiagFix` when the help is
   machine-applicable and should render as `?LOC:"msg"~>"replacement"` -
   at the site that detects the condition, in `self_host/lexer.ax`,
   `self_host/parser.ax`, or `self_host/typecheck.ax`. It takes a
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
  actual foreign calls in the body, and `pure` claims are checked against
  foreign calls. Mismatches emit a normal `AX3010` / `axtag-mismatch`
  warning so an agent can correct the annotation instead of silently
  trusting it. Other tags (`no_refactor`, `owned(arena=frame)`, etc.) are
  preserved and emitted but not yet validated.

Example AXSYM output with NID and AXTAG metadata:

```
F add main.ax:1:6-9 "(Int -> (Int -> Int))" @a1b2c3d4e5f6a1b2
X printf main.ax:1:10-16 "(String -> Int)" #symbol=printf @c3d4e5f6a1b2
D Maybe main.ax:3:7-12 "data Maybe" #ctors=Nothing,Just @e5f6a1b2c3d4
```
