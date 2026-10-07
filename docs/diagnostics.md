# Axiom diagnostics & agent notations

When something is wrong, Axiom tells you where, why, and often how to
fix it, with a stable code you can look up. This page covers the
diagnostic formats, the codes, and the one-line notations your tools
and agents can read.

## Read a diagnostic

Here's a program with a typo in it. Save it as `main.ax`:

```scheme refused
(:: helper (-> Int Int))
(fn (helper x) (+ x 1))

(:: main Int)
(fn (main)
  (helpr 5))
```

Then run `axiom check main.ax`:

```text
error[AX3001]: undefined variable `helpr`
 --> main.ax:6:4
  |
6 |   (helpr 5))
  |    ^^^^^ no binding named `helpr` in scope
  |
  = help: a similarly named binding `helper` is in scope; did you mean this? ~> helper
  = help: run `axiom explain AX3001` for a full explanation

compilation failed due to 1 previous error
```

You get the exact location, a fix, and a stable code you can look up
with `axiom explain`.

The same diagnostic comes in three formats. Choose one with
`--diagnostic-format`:

| Format | For |
|---|---|
| `human`, the default | you, in a terminal |
| `ai` | agents and scripts: one AXDL line per diagnostic |
| `json` | tools that want JSON Lines |

```bash
axiom --diagnostic-format=ai check main.ax
```

The three names are spelled exactly as in the table. Any other value
is refused like a bad flag, with exit status 2.

Every diagnostic is one `Diag` value, defined in
[`self_host/diag.ax`](../self_host/diag.ax). It's built by whichever
stage refuses the program: the parser, the macro expander, the type
checker, or the codegen and driver stages that lower and link. The
parser raises the lexer's errors too, with `lexErrDiag` reading the
code off the offending byte. Each format renders that one value and
knows nothing more, so `human`, `ai` and `json` never disagree about
what went wrong.

### Two notations for agents

Axiom's machine-facing output tells an agent what it needs to act, in
as few tokens as possible. A location without an explanation makes
every reader, human or agent, re-derive what the compiler already
knew. So does a signature buried in pretty-printed prose. Two
notations answer the two questions an agent asks a compiler most:

- **AXDL** (Axiom eXchange Diagnostic Line) answers "why did this
  fail?": what went wrong, where, and how to fix it. One line per
  diagnostic.
- **AXSYM** (Axiom eXchange Symbol Line) answers "what does this
  already provide?": what a file successfully declares, and its type.
  One line per symbol. It has
  [its own section](#axsym-symboltype-notation-axiom-symbols) below.

Both are dense, greppable and colourless, with one fact per line, and
both address locations the same way. Neither is a general "tag
everything" scheme. Each answers exactly one question, so you never
have to guess which fields a line might hold.

### Errors, warnings and the exit status

Only an error fails the build. A run that produces nothing but warnings
exits zero. Warnings are printed either way, and when the build fails
they appear next to the errors.

After a failed run, every format ends with one plain summary line,
such as `compilation failed due to 1 previous error`. It counts errors
alone, so one error beside one warning still reads "1 previous error".

The exit status follows the severity each diagnostic is rendered with,
not a list of diagnostic kinds. The severity you see and the behaviour
you get always agree.

## Read symbol tags

`Agent.Tags` parses AXSYM rows from `axiom symbols --calls`.
`axsymLine` returns `Option Sym`; `axsymParse` reads a stream. A symbol
records its kind, name, location, type, NID and metadata. The reader
accepts all eight declaration kinds and ignores diagnostic lines that
also begin with `E`. Imported declarations keep their declaring file.

Use `symEffects` for the compiler's derived row and `symTag` for an
author's AXTAG. `symHasTag` distinguishes an empty tag from an absent
one. Derived keys follow author tags, so they cannot be shadowed.
`symAgentTag` and `symHasAgentTag` read `agent:*` annotations; the
compiler records them, while a consuming tool chooses their policy.
Effects reached through stored values may escape a static call graph.

Tested by `tests/stdlib/380-agent-tags.ax`.

## Stable diagnostic codes

Every diagnostic, apart from a few catch-all fallbacks, carries a
stable code such as `AX3001`, much like `rustc`'s `E0308`. The first
digit names the compiler stage:

| Range | Stage |
|---|---|
| `AX1xxx` | Lexical analysis |
| `AX2xxx` | Parsing / syntax |
| `AX3xxx` | Semantic analysis / type checking |
| `AX4xxx` | IR lowering, codegen, and the native toolchain |
| `AX5xxx` | Module/import resolution |

A code stays the same when its wording changes, so you can grep for it
in CI, match on it in editor tooling, or look it up:

```bash
axiom explain AX3001        # full explanation of one code
axiom explain --list        # every known code
```

Each code also has a kebab-case slug, such as `undefined-variable`,
which doesn't depend on the wording either. It appears on every AXDL
line, as `slug` in JSON, and beside each code in
`axiom explain --list`. Your tools can match on the slug without
knowing the numbers at all.

### Macro expansion codes

Macro expansion runs as part of semantic analysis, so its refusals are
`AX3xxx` codes:

| Code | Slug | What it refuses |
|---|---|---|
| `AX3018` | `macro-arity` | an invocation no rule accepts (arity) |
| `AX3019` | `macro-recursion-limit` | an expansion that hits the recursion limit |
| `AX3020` | `macro-duplicate-parameter` | a duplicate parameter |
| `AX3021` | `macro-template-unsupported` | an unsupported template form |
| `AX3022` | `macro-set-target` | a `set` target that isn't a name |
| `AX3024` | `macro-expansion-limit` | an expansion past the size limit |
| `AX3027` | `declaration-macro` | a declaration-macro invocation the expander can't resolve |
| `AX3028` | `syntax-query` | a `syntax/*` query with no answer |
| `AX3033` | `macro-unreachable-rule` | a rule that can never match |
| `AX3034` | `macro-ellipsis` | an ellipsis used at the wrong depth |
| `AX3035` | `macro-binder-target` | a binder parameter given something that isn't a variable |
| `AX3066` | `macro-literal` | a literal a rule declares and never uses |

All twelve are raised in `self_host/expand.ax`, and `AX3028` in
`self_host/typecheck.ax` as well. See
[macro-system.md](macro-system.md) for the rules behind them.

### Names from other modules

`AX3023` (`private-name`) is a reference to a name that exists, in a
module that doesn't export it. Either the declaration isn't `pub`, or
the `(import M (a b))` that brought the module in doesn't list it.
That's a different mistake from `AX3001`, which is a name defined
nowhere. See [Modules and imports](reference.md#modules-and-imports).

`AX3044` (`ambiguous-type`) is the type-namespace sibling of `AX3014`
(`ambiguous-name`). It refuses a bare type name that two or more
imported modules declare, when neither the entry file nor a builtin
declares it and the reference is inside neither module. Nothing
decides which one you mean. Picking by import order would compile a
module against another module's field offsets, and the answer would
change when an unrelated import moved.

- In a type position, such as a signature or a field, qualify the name:
  `TeamA::Config`. The diagnostic's help names each qualified spelling.
- Where the program constructs the value, qualification isn't accepted
  yet: `(TeamA::Config 42 3)` draws `AX3044` too. Narrow one of the
  imports with a name list, such as `(import TeamA (fromA))`, or rename
  one of the declarations.

Tested by `scripts/check-type-namespace.sh` and `tests/selfhost/491`-`494`.

### Strings the compiler hands on

Two codes check a string that the source hands straight to something
outside the compiler. Both are raised in `self_host/parser.ax`, though
only `AX2006` is numbered as a syntax error.

`AX2006` (`module-path-segment`) refuses a module-path segment that
contains `/`. `(import M)` names a module, and the resolver turns that
name into a filename by joining each search directory onto it in turn.
A segment that is already a path re-anchors the join, and reads a file
the search directories never offered: `(import /etc/x)` would read
`/etc/x.ax`. Write the dotted name, such as `Sys.Platform`, instead.

`/` stays an ordinary identifier character everywhere else, because
`syntax/format` and `syntax/join` are spelled with one. Only a module
path becomes a filename, so only a module path is checked. Tested by
`tests/diagnostics/955-import-absolute-path.axbad`.

`AX3041` (`extern-library-name`) refuses an `extern` block's library
name that isn't one. The name is the stem of `lib<name>.a`, so it can't
be empty and may use only `[A-Za-z0-9._+-]`. It reaches two consumers
verbatim:

- the driver passes it to the linker as `-l<name>`;
- the emitter writes it beside the block's `declare` lines as
  `; axiom-extern-lib <name>`.

An LLVM `;` comment ends at the newline, so a newline in the name would
turn the rest of it into live module-level IR. That IR would arrive
after the type checker, the effect system and the freestanding check
had all run, and the driver's grounding pass reads only `declare`
lines, so nothing downstream would catch it. Tested by `tests/diagnostics/945-extern-lib-newline.axbad`.

`AX3041` is a semantic refusal rather than a syntax error because the
string literal itself is well formed. What's refused is what the
string means to the linker. The lexer leaves it alone because a line
break inside a string literal is valid Axiom.

## Cascade suppression

One mistake gives you one diagnostic. This program has a single
problem:

```scheme refused
(:: main Int)
(fn (main) (+ (foo 1 2) 0))
```

Checking it with `--diagnostic-format=ai` reports one diagnostic:

```text
E AX3001 main.ax:2:16-19 undefined-variable "undefined variable `foo`" #"no binding named `foo` in scope" ?"variables must be defined (via `define`/`fn`, a `let` binding, or a lambda parameter) before they are used; check for typos"
compilation failed due to 1 previous error
```

Two mechanisms keep the follow-on errors away.

The first is a poison type. After reporting a failure, the type
checker gives the failing expression the type `TAG_T_ERR`. Every later
check treats a poisoned type as already explained, and doesn't check it
again. `tyIsErr` guards every site in `self_host/typecheck.ax` that
builds a type mismatch, and `tyCompat` tests for poison before it tests
for type variables. Above, the poison flows into `+` and back out to
`main`'s declared `Int`, and neither comparison reports a second time.

The second is spanlessness. A node with no span suppresses its
diagnostic rather than pointing it somewhere wrong. The `(== span 0)`
guards in `self_host/typecheck.ax`, with `(!= span 0)` emission guards
and `spanOf` checks, are why a diagnostic never lands on line 1,
column 1 by accident.

There's no grouping or deduplication pass. The retired Rust compiler
had one, `axiom_errors::dedup`, but nothing ever called it, so it
wasn't carried over. If a cascade turns up that poisoning and span
guards can't prevent, build that pass then, with that cascade as its
first caller.

## Human format (`--diagnostic-format=human`, default)

The default report follows `rustc`'s layout. It quotes the offending
line, underlines and labels the exact span, and shows the code, the
message, any notes and every help. [Read a diagnostic](#read-a-diagnostic)
shows one.

The real report is coloured: the severity and carets in the severity's
colour, the gutter blue and the `= help:` marker green. It's coloured
even when stderr is redirected to a file or a pipe. This page shows it
plain. The palette is one table in `self_host/style.ax`.

The layout follows these rules:

- Columns count characters, not bytes, so a caret under a line with an
  em dash lands where you expect. Tabs expand to the next multiple of
  four. The caret is placed in display columns, while the `-->` line
  keeps the character column AXDL reports. On a tab-indented line those
  are different numbers, and both are right.
- A line wider than 160 columns is quoted as a window, starting 20
  columns before the span, with `...` on whichever side was cut.
- Every help renders. The header's line number comes from the primary
  span. A span past the end of the file is clamped, so "unexpected end
  of file" shows the last real line instead of a blank one.
- A machine-applicable fix shows its replacement after `~>`, the same
  notation AXDL uses. A replacement with a line break in it ends the
  help line at `~>` and continues on lines of its own. Each is indented
  to the help text's column and otherwise verbatim, so it reads as
  source with its own indentation. A break at the start or end of the
  replacement prints no blank line.

`tests/diagnostics/250-non-exhaustive-match.ax` leaves two constructors
out of a `match`. Its first diagnostic carries two fixes:

```text
error[AX3005]: non-exhaustive pattern match: missing Green, Blue
 --> tests/diagnostics/250-non-exhaustive-match.ax:8:10
  |
8 |   (match Red
  |          ^^^ this `match` does not cover: Green, Blue
  |
  = help: add the missing arms, each a `todo` until it is written ~>
              ((Green _) (todo "Green"))
              ((Blue) (todo "Blue"))
  = help: import `todo` from IO ~>
          (import IO (todo))
  = help: run `axiom explain AX3005` for a full explanation
```

On the AXDL line the same two replacements are escaped, because a
diagnostic there is one line:

```text
E AX3005 tests/diagnostics/250-non-exhaustive-match.ax:8:10-13 non-exhaustive-match "non-exhaustive pattern match: missing Green, Blue" #"this `match` does not cover: Green, Blue" ?9:14:"add the missing arms, each a `todo` until it is written"~>"\n    ((Green _) (todo \"Green\"))\n    ((Blue) (todo \"Blue\"))" ?1:1:"import `todo` from IO"~>"(import IO (todo))\n"
```

Tested by `scripts/check-render-selfhost.sh`.

<a id="ai-optimized-notation---diagnostic-formatai"></a>
## AXDL: one line per diagnostic (`--diagnostic-format=ai`)

`--diagnostic-format=ai` prints AXDL: one dense, colourless, greppable
line per diagnostic. It's built so an agent spends as few tokens as
possible reading compiler output.

- No re-rendered source. An agent working on a file already has it in
  context, so AXDL gives the exact `line:col` range and nothing else
  about the source text.
- No ANSI colour codes or Unicode box drawing. Tokenisers strip them
  inconsistently, or they cost tokens and tell a model nothing.
- Exactly one line per diagnostic. `grep -c '^E '` counts errors, and
  `grep AX3001` or `grep undefined-variable` filters by kind. You never
  need a state machine to find where one diagnostic ends and the next
  begins.
- Both the stable code and the slug, so matching works whether or not
  a tool knows Axiom's numeric codes.
- Fixes as data. A suggestion with a known replacement is encoded as
  `<loc>:"<msg>"~>"<replacement>"`, so a tool or an agent can apply it
  with a plain byte-range substitution instead of parsing English.
- Every fact the diagnostic carries, on the one line: the primary
  label, every related span, every note and every help. The one thing
  left out is the human report's `run axiom explain AX####` help. An
  agent that wants prose can run `axiom explain` itself.

### Example

The program from [Read a diagnostic](#read-a-diagnostic) gives this
line:

```text
E AX3001 main.ax:6:4-9 undefined-variable "undefined variable `helpr`" #"no binding named `helpr` in scope" ?6:4-9:"a similarly named binding `helper` is in scope; did you mean this?"~>"helper"
```

Everything the human report tells you is here: the exact span, the kind
of error, the primary label, the message and a machine-applicable fix.
It's a single 193-byte line, where the coloured human report is more
than twice that size. Only the `axiom explain` pointer is left out, so the
human report's two `help:` lines become one `?` field.

### Grammar

```
<SEV> <CODE> <FILE>:<LOC> <SLUG> "<MESSAGE>" [#"<label>"]
     [^<relfield>]* [!"<note>"]* [?<field>]* [&"<frame>"]*

<relfield> ::= <LOC>:"<related>"           in the diagnostic's own file
             | <FILE>:<LOC>:"<related>"    in another file
             | -:"<related>"               nowhere
```

| Field | Meaning |
|---|---|
| `SEV` | `E` (error) or `W` (warning). `N` and `H` are reserved; see below. |
| `CODE` | Stable code, e.g. `AX3001` |
| `FILE:LOC` | `file:line:col` or `file:line:col-col` or `file:line:col-line:col` |
| `SLUG` | kebab-case, wording-independent diagnostic kind |
| `"MESSAGE"` | Quoted human message. It's still needed, because a code alone doesn't carry the specific name or type involved. |
| `#"label"` | The primary span's own label: the sentence the human report prints after the carets. Absent when it would only repeat the message. |
| `^LOC:"msg"` | A secondary or related span, such as the other side of a type mismatch |
| `^FILE:LOC:"msg"` | The same, in a different file, spelled out for the same reason `&` spells out its file. `AX3049`'s call chain is the producer: in a typical `no-io` violation, four of the six hops are in `stdlib/`. |
| `^-:"msg"` | The same, with no location at all. `-` is how the primary `FILE:LOC` field already spells a spanless diagnostic. A call-chain hop that is a builtin or an `extern` item has no declaration to point at, and it still gets a field. |
| `!"note"` | An extra note: a fact about why the program is wrong. A help, by contrast, is an action that would make it right. |
| `?"msg"` or `?LOC:"msg"~>"replacement"` | A help suggestion. The `~>` form is machine-applicable. |
| `&"name"` or `&FILE:LOC:"name"` | One frame of the expansion backtrace, outermost first: the macro's name and, in the located form, the span of its declaration. That span indexes the macro's file, not the diagnostic's, so the located form always spells the file out, where `?` and `^LOC` leave it implied. |

Every field marked `*` repeats. Fields appear in exactly the order
above. If your consumer meets a field it doesn't know, it should fail
rather than skip it, as `tests/diagnostics/verify-axdl-spans.py` does.

`N` and `H` are reserved as severities and never emitted. Every
diagnostic the compiler builds is an error or a warning. A note or a
help is a field of one, not a diagnostic of its own.

Tested by `tests/selfhost/645-axdl-repetition.ax`, which builds one
diagnostic with two of every repeating field and renders the whole
line. That keeps combinations no real diagnostic produces covered.

### Parse a line safely

Every quoted field, `"msg"` and `"replacement"` included, uses Rust's
`Debug`-style string escaping:

- `"` and `\` are backslash-escaped;
- newline, tab and carriage return become `\n`, `\t` and `\r`;
- any other control byte, and DEL, becomes `\u{..}` in lowercase hex.

So a diagnostic always stays on one line, and every quoted field has an
unambiguous end.

The text inside a quoted field can still contain the two characters
`~>`, for example in a message about arrow types. Parse each quoted
field as an escaped string, up to its matching unescaped `"`. Look for
the `~>` separator only in the unquoted gap between two quoted fields.
Never split the whole line with `str.split("~>")`, which breaks when
`~>` appears inside a message.

### Macro expansion frames

A diagnostic raised inside a macro expansion carries one `&` frame per
enclosing macro, outermost first. Each frame names the macro and the
span of its own declaration, in its own file. Sometimes the frame is
all that makes a line actionable, such as an `AX3014` reported at an
invocation that mentions neither the name nor the modules.

Tested by `tests/diagnostics/490-expansion-backtrace.ax`, with one
frame and a nested two, and `tests/diagnostics/595-macro-imported-ambiguous.ax`.

### Call chains

`AX3049` (`restriction-violated`) reports a declaration that breaks its
own `restrict(...)` claim. It names the chain of calls from that
declaration to where the effect enters, or around the cycle. The
message spells the chain out, and the line gives each hop a `^` field
you can follow.

The first diagnostic for `tests/diagnostics/371-restrict-no-io.ax`
says the body performs IO through `parseConfig -> readSection ->
IO$writeStr -> Sys$sysWriteAllFd -> Sys$sysWriteAllFrom ->
Sys$sysWriteFd -> __syscall3`. Its related fields, shown here one per
line, are:

```text
^31:6-17:"readSection"
^stdlib/IO.ax:36:10-18:"IO$writeStr"
^stdlib/Sys.ax:152:10-23:"Sys$sysWriteAllFd"
^stdlib/Sys.ax:160:6-21:"Sys$sysWriteAllFrom"
^stdlib/Sys.ax:132:6-16:"Sys$sysWriteFd"
^-:"__syscall3"
```

The fields follow three rules:

- One `^` field per hop, after the first. The first hop is the
  declaration the diagnostic is reported at, so its span is already the
  primary `FILE:LOC`.
- A hop with no declaration still gets a field, `^-:"name"`. A builtin
  such as `__syscall3`, an `extern` item and an effect operation have no
  declaration node in any unit. Leaving them out would make the list
  look complete while being short.
- The label is the hop's resolved name. It's the same spelling
  `graphRender` puts in the message and `symbols --calls` puts in its
  rows. So a checker that knows neither the compiler nor the renderer
  can compare the chain with the fields hop by hop, and
  `tests/diagnostics/verify-axdl-spans.py` does.

The other formats show the same hops:

- The human snippet quotes one source file, so it can't draw a hop in
  another file. A line number from that file would put a caret under
  the wrong text. The hop renders as a note with its own file and
  position instead, `= note: IO$writeStr (stdlib/IO.ax:44:10-18)`. An
  expansion frame whose file can't be reached is shown the same way.
- A hop with no location renders as
  `= note: __syscall3 (no declaration to point at)`.
- In JSON, a related entry in another file gains a `"file"` beside its
  span. One with no location carries a `"label"` and no `"span"` key.
- The language server publishes neither kind. It holds one document
  and no unit table, so it drops a hop it can't place rather than aim
  it at the open file's URI.

## JSON Lines (`--diagnostic-format=json`)

If your tool would rather not parse either text format, ask for JSON
Lines: one JSON object per diagnostic, one per line. It isn't a JSON
array, so output can be streamed. The program from
[Read a diagnostic](#read-a-diagnostic) gives:

```json
{"severity":"error","code":"AX3001","slug":"undefined-variable","message":"undefined variable `helpr`","file":"main.ax","span":{"start":{"line":6,"col":4},"end":{"line":6,"col":9},"char_start":78,"char_end":83},"label":"no binding named `helpr` in scope","related":[],"notes":[],"help":["a similarly named binding `helper` is in scope; did you mean this?"],"fixes":[{"file":"main.ax","span":{"start":{"line":6,"col":4},"end":{"line":6,"col":9},"char_start":78,"char_end":83},"replacement":"helper"}],"expansion":[]}
```

- `expansion` is the array form of AXDL's `&` field, one object per
  enclosing macro. It's empty for a diagnostic raised outside an
  expansion.
- `span` appears only when the diagnostic has a location, and `label`
  only when it also has a label. You can tell "no label" from an empty
  one.
- `help` holds each help's text. When a help carries a replacement,
  `fixes` contains its `file`, `span` and `replacement`, in help order.
  The key is absent when there are no fixes. Empty replacements delete
  the span; an empty span inserts the replacement.
- After the last object, a failed run prints the plain summary line
  from [Errors, warnings and the exit status](#errors-warnings-and-the-exit-status).

`char_start` and `char_end` are character offsets, not byte offsets.
The compiler's own spans count bytes, because the lexer walks the
source a byte at a time. The JSON renderer converts them (`jsonSpan` in
`self_host/render.ax`), so the two fields count characters whatever the
representation behind them. For ASCII source, characters and bytes
agree. For source with multi-byte UTF-8 characters, don't use these
fields as byte indices into the file.

Tested by `scripts/check-render-selfhost.sh`.

## AXSYM: symbol/type notation (`axiom symbols`)

AXDL tells you what went wrong. AXSYM answers the other question you
and your agents ask all the time: what does this file already declare,
and what type does each name have? Without it, you re-read the file
and work out every signature by eye.

`axiom symbols <file>` runs the same lexer, parser and type checker as
`check`, including resolving `(import ...)`. It then prints one line
per top-level name the checker collected: every function (`fn` or
`define`), every `data` type and its constructors, every `struct` with
its field shapes, and every `type` alias.

```bash
# The aligned table, one line per symbol (the default)
axiom symbols main.ax

# AXSYM: the same facts, plus the nid and the metadata
axiom --diagnostic-format=ai symbols main.ax

# Also list the always-in-scope builtins, omitted by default:
# operators (+, ==, &&, ...) and primitives (__syscall0, __alloc, ...)
axiom symbols main.ax --builtins
```

The default is an aligned table: the kind spelled out, the name, the
type, and the location in brackets. A builtin shows `[builtin]` where
AXSYM writes `-`. The example below shows both renderings.

`--diagnostic-format=ai` gives you AXSYM: the same facts, plus the nid
(a stable ID for each declaration) and the metadata the table has no
column for. The table is built by re-reading the AXSYM text
(`symbolsHumanTable` in `self_host/symbols.ax`), so the two can't
disagree about what the symbols are.

`symbols --diagnostic-format=json` exits with status 2 and prints guidance
on stderr. Use `--diagnostic-format=ai` for AXSYM or `human` for the table.
The refusal also applies to `symbols --axir`.

### Grammar

```text
<KIND> <NAME> <FILE>:<LOC>|- "<TYPE>" [@<NID>] [#<key>=<value>]*
```

| Field | Meaning |
|---|---|
| `KIND` | One letter: `F` function, `D` data type, `C` constructor, `S` struct, `A` type alias, `E` effect declaration, `M` macro. `T` was a trait. Traits were removed in 0.6.0 and `trait` is now `AX2004`, so no row carries it |
| `NAME` | The declared name, exactly as written |
| `FILE:LOC` | The same `file:line:col[-col\|:line:col]` addressing as AXDL, from the same source map in [`self_host/diag.ax`](../self_host/diag.ax). With `(import ...)`, `FILE` is the file that declared the symbol, which may be an imported module rather than the entry file, just as AXDL attributes diagnostics across files |
| `-` | Replaces `FILE:LOC` for a name with no source span: the built-in operators (`+`, `==`, `&&`, ...), the primitives (`__syscall0`, `__alloc`, ...), an effect's operations, and the built-in types `Option` (with its two constructors) and `Vec`. The operators and primitives never change, so they appear only with `--builtins`. `Option` and `Vec` are always listed |
| `"TYPE"` | The type as the checker writes it, curried and quoted: `(-> Int Int Int)` in source is `"(Int -> (Int -> Int))"` here. A type can contain `->` and parentheses, so the quotes keep field boundaries clear, the same way AXDL quotes messages |
| `@NID` | The stable node ID (see [below](#stable-node-ids-and-source-embedded-tags)). Constructors and builtins have none |
| `#key=value` | Kind-specific metadata (see below). A key with no value, such as `#no_refactor`, is written alone |

The metadata keys:

| Key | Kinds | Meaning |
|---|---|---|
| `ctors` | `D` | Constructor names, comma-separated, e.g. `#ctors=Nothing,Just` |
| `of` | `C` | The data type the constructor belongs to, e.g. `#of=Maybe` |
| `fields` | `S` | Each field's name and type, `name:Type,name:Type,...`, e.g. `#fields=x:Int,y:Int` |
| `repr` | `S` | A word struct's representation: `#repr=word`, or `#repr=word,shared` when a concurrent binding may capture it ([memory-model.md](memory-model.md) `MM-VAL-10a`). `#repr=sealed,shared` on a heap struct a `parallel` form lends (`MM-PAR-16`). Absent on any other heap struct |
| `tyvars` | `A` | Type parameters, comma-separated, e.g. `#tyvars=a,b`. Absent when there are none |
| `effects` | `F` | The effect row the checker derived by walking the function's calls, sorted and comma-separated, e.g. `#effects=IO`. Absent when the function performs none. An `extern` item carries `#effects=IO` |
| `effect-params` | `F` | For an effect-polymorphic signature, the parameters the row varies in, by their declared names |
| `effects-incomplete` | `F` | The walk met a call it couldn't resolve: a struct field or opaque local holding a function, or a call that applies a callee's result. So `#effects=` is a lower bound. A row with nothing but this carries no `#effects=` |
| `effects-overapprox` | `F` | Some member of `#effects=` is only *possible*: it comes from naming an arrow-typed function without calling it, such as handing it back or storing it in a capability record. Always appears with `effects-possible` |
| `effects-possible` | `F` | Which members those are, sorted and comma-separated, e.g. `#effects-possible=IO` on `(fn (handoff k) shout)`. A member the body also performs definitely isn't listed. `#effects=` stays the union either way (see "definite" and "possible" in [Effects](reference.md#effects)) |
| `extern` | `F` | The row is an `extern` item - code outside the program, reached through the C ABI. Without it an extern row is a function with no calls and `#effects=IO`, which is also what a body writing one syscall looks like; `restrict(no-foreign)` and the restricted profile's RP-3 ([restricted-profile.md](restricted-profile.md)) are about exactly this difference |
| `unsafe` | `F` | The declaration's place in the unsafe boundary (`MM-EXEC-9d` in [memory-model.md](memory-model.md)): `trusted` for `;@axiom:effect(unsafe)`, whose callers inherit no `Unsafe`. `grep '#unsafe=trusted'` lists a program's trusted set |
| `erasures` | `F` | How many casts in the body turn a reference into a word: an operand that is a `String`, `Vec`, `Handle`, record, closure, tuple or signature type variable, cast to `Int`, `Foreign`, a number or an alias of one. Counted by the operand's type, so `(cast Int c)` of a `Char` isn't one. Absent when there are none. `scripts/check-cast-arg-root.sh` holds the compiler's total to a ratchet |
| `generated` | `F` | The declaration macro that wrote this declaration, for a name no line of the file spells |
| `calls` | `F` | Only with `--calls`. The call edges the effect walk resolved to derive this row's `#effects=`, sorted and comma-separated. Each names the resolved entry, `Mod$name` where the checker mangled it (the same symbol codegen emits), so an edge tells you which `writeStr`. A bare reference is an edge too, because the effect walk counts it just like a call. See [agent-harness.md](agent-harness.md) §3.5 |

AXTAG keys such as `#effect=io` and `#effect=pure` join these on `F`, `D`,
`S`, `A` and `E` rows (see [AXTAG](#source-embedded-tags-axtag)
below). On an `E` row, `#unhandled=trap` comes from
`;@axiom:unhandled(trap)`, which tells the compiler that reaching the
effect with no handler is intended, so it doesn't refuse it with
`AX3053`.
A policy check reading this output uses it to list the effects a
program allows to abort.

`KIND` letters don't overlap AXDL's severity letters (`E`, `W`, `N`,
`H`), with one exception: `E` is an error in AXDL and an effect
declaration here. If you mix the two outputs in one stream, the first
character alone can't tell you which produced a line.

Tested by `tests/tools/symbols-zoo.golden`.

### Example

Source:

```scheme
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

The default table:

```text
Fn       add                  (Int -> (Int -> Int))                    [main.ax:9:5-8]
Data     Option               data Option                              [builtin]
Ctor     Some                 (a -> Option a)                          [builtin]
Ctor     None                 Option a                                 [builtin]
Data     Vec                  data Vec                                 [builtin]
Data     Maybe                data Maybe                               [main.ax:1:7-12]
Ctor     Nothing              Maybe a                                  [main.ax:2:4-11]
Ctor     Just                 (a -> Maybe a)                           [main.ax:3:4-8]
Struct   Point                struct Point                             [main.ax:5:9-14]
```

The same file under `--diagnostic-format=ai`, with the nid and the
metadata:

```text
F add main.ax:9:5-8 "(Int -> (Int -> Int))" @27bcb2cac184465e
D Option - "data Option" #ctors=Some,None
C Some - "(a -> Option a)" #of=Option
C None - "Option a" #of=Option
D Vec - "data Vec"
D Maybe main.ax:1:7-12 "data Maybe" @247d1682b2330461 #ctors=Nothing,Just
C Nothing main.ax:2:4-11 "Maybe a" #of=Maybe
C Just main.ax:3:4-8 "(a -> Maybe a)" #of=Maybe
S Point main.ax:5:9-14 "struct Point" @aa47cd1e9254cc56 #fields=x:Int,y:Int
```

`Option`, its constructors and `Vec` appear either way. The operators
and primitives appear only with `--builtins`.

Say an agent is asked to add a function that formats a `Maybe Int`.
`grep '^D Maybe '` gives it the constructor names, `grep '#of=Maybe'`
each constructor's type, and `grep '^S Point '` the exact field shapes.
It never has to re-read the file to recover facts the type checker
already has.

## Stable node IDs and source-embedded tags

### Stable node IDs (NID)

Every named declaration gets a content-derived ID: a short hash of its
kind and name. A function's kind is its `fn`, wherever its `::` sits. It survives edits elsewhere in the file and
reformatting, which a `file:line:col` doesn't. AXSYM prints it as the
optional `@NID` field after the type.

### Source-embedded tags (AXTAG)

An AXTAG is a comment of the form `;@axiom:<key>(<value>)` directly
above a declaration. It records intent, which the compiler checks
where it can. The lexer keeps the tag, the parser attaches it to the
declaration, and `axiom symbols` prints each accepted tag as `#`
metadata on that declaration's line, such as `#effect=io` or `#effect=pure`.

Here the first declaration carries `;@axiom:effect(pure)`, the second is an
`extern` item, and the third is a data type:

```scheme
;@axiom:effect(pure)
(:: double (-> Int Int))
(fn (double x) (* x 2))

(extern "mymath"
  (addTwo :: (-> Int Int Int)))

(data Maybe (a)
  (Nothing)
  (Just a))
```

Their AXSYM lines, with the nid after the type and the metadata after
the nid (constructor and builtin rows left out):

```text
F double main.ax:2:5-11 "(Int -> Int)" @c74a58529d6a1016 #effect=pure
F addTwo main.ax:6:4-10 "(Int -> (Int -> Int))" @531b42e47de2ddf6 #effects=IO
D Maybe main.ax:8:7-12 "data Maybe" @247d1682b2330461 #ctors=Nothing,Just
```

An `extern` item is an `F` like any other function: it has a name, a
type and a span. The effects it carries are the ones a call to it
performs.

The type checker validates the tags it can:

- `effect(io)` is checked against what the body performs: a
  `__syscallN`, or a call to something that performs one.
- `pure` is checked against the absence of any effect.
- `restrict(...)` lists what a declaration doesn't do, comma-separated.
  The names are `no-io`, `no-alloc`, `no-unsafe`, `no-foreign`,
  `no-cast`, `no-cast:deep`, `no-recursion`, `no-wrap`, `no-trap`
  and `no-escape`. Each is checked against the effect row, the call
  graph or the region facts.

| Code | Severity | Raised for |
|---|---|---|
| `AX3010` (`axtag-mismatch`) | error | an `effect(...)` or `effect(pure)` claim the body contradicts |
| `AX3037` | warning | an `effect(...)` or `effect(pure)` claim the effect walk can't check: the body calls a value the compiler can't resolve, or may perform the effect only through a function it hands on or a field whose stored functions disagree |
| `AX3049` | error | a violated restriction. The message shows the path of resolved calls to where the effect enters, or the cycle |
| `AX3051` | warning | a restriction over a row the walk couldn't close |
| `AX3052` | error | a name in `restrict(...)` that isn't a restriction. The list is closed ([AXTAG metadata](reference.md#axtag-metadata)) |
| `AX3057` | error | with `strict`, a restriction the walk couldn't settle |

Because `AX3010` and `AX3049` are errors, a successful build means
every claim the compiler could check holds.

`strict` in a `restrict(...)` list, as in
`;@axiom:restrict(no-io, strict)`, is a modifier, not a restriction. It
turns an unsettled claim from `AX3051` into `AX3057`, which fails the
build. The default stays a warning because a body that calls through a
stored function is a correct program the walk can't follow. `strict`
says that, on this declaration, an unproven guarantee doesn't count.

Other tags, such as `no_refactor` and `owned(arena=frame)`, are kept
and printed but not validated yet.

Tested by `tests/diagnostics/330-axtag-mismatch.ax`.

### Region checks

A signature can name the region a reference lives in, such as
`(String @r)` (see [Region annotations](reference.md#region-annotations)).
After every body is typed, the escape rule checks those names:

- `AX3060`: a store whose place outlives the value.
- `AX3061`: a result that doesn't live in its declared region.
- `AX3062`: either of those with a closure as the value, reported
  against the capture.
- `AX3063`: a call whose arguments disagree on a region the callee
  names, or a signature whose result names a region no parameter
  supplies.

All four are errors. A program whose signatures name no region never
sees them, because the pass doesn't run.

Tested by `tests/diagnostics/645-region-escape-store.ax`.

## Adding a new diagnostic

1. Pick the next free number in the right range: `AX1xxx` lexical,
   `AX2xxx` parse, `AX3xxx` semantic (macro expansion included),
   `AX4xxx` IR lowering, codegen and the native toolchain, `AX5xxx`
   module resolution. Take a number above the reserved block, never
   inside it. [error-model.md](error-model.md) keeps a Proposed table
   of numbers not yet built, and `scripts/check-doc-drift.sh` fails if
   the compiler spends one of them.
2. Construct it at the site that detects the condition, with `mkDiag`,
   or `mkDiagFix` when the help is machine-applicable and should render
   as `?LOC:"msg"~>"replacement"`. That site is in
   `self_host/parser.ax` (which raises the lexer's errors too),
   `self_host/expand.ax`, `self_host/typecheck.ax`,
   `self_host/codegen.ax` or `self_host/driver.ax`. It takes a
   severity, the code, a kebab-case slug, a span, a message, a related
   span with its message, and a help. Pass `0` for a related span or a
   help you don't have.
3. Write its long-form text in `self_host/explain.ax`, so
   `axiom explain AX....` answers. `scripts/check-doc-drift.sh` fails a
   code that is constructed but has no entry, and the reverse.
   `scripts/check-diagnostic-coverage.sh` requires either a primary
   golden in `tests/diagnostics/` or a row in
   `tests/diagnostics/UNCOVERED`. `scripts/check-tools-selfhost.sh`
   also checks every code the corpus emits against `explain --list`.
4. If the new error can follow from another one, poison it: propagate
   the error type from the failing check instead of a fresh
   placeholder, and guard later comparisons. One mistake should draw
   one diagnostic, not a cascade.
5. Add a case to `tests/diagnostics/` with its `.axdl`, `.human` and
   `.json` goldens. Name the source `.axbad` if it must not parse,
   because the formatter and grammar checks sweep every `*.ax` and
   require it to parse. Bless it with
   `AXIOM_BLESS=1 scripts/check-diagnostics.sh NNN`. Then make sure the
   case isn't vacuous: it should fail against a compiler built from
   before your change.

## See also

- [agent-harness.md](agent-harness.md): how an agent reads, checks and
  rewrites Axiom programs with these notations.
- [error-model.md](error-model.md): how a program represents failure,
  and how the compiler reports it.
- [AXTAG metadata](reference.md#axtag-metadata) in the language
  reference: every tag key and what it claims.
