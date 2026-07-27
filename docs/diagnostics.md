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
[`axiom_errors::Diagnostic`](../axiom-errors/src/diagnostic.rs), produced
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
every `TypeMismatch` call site in `axiom-sema`). This is the actual,
exercised mechanism behind every cascade fix today.

Separately, `Diagnostic` also supports tagging a diagnostic with a
`group` key via `.with_group(...)`, and [`axiom_errors::dedup`] drops
every diagnostic after the first one in a given group before anything is
rendered. This is generic plumbing for a *different* kind of cascade -
one where a truly separate `Diagnostic` was already constructed and needs
suppressing after the fact, rather than being prevented from firing in
the first place - and is not currently used by any lexer/parser/sema call
site (poisoning covers the one cascade case that exists today, so nothing
needs it yet). It's kept because a purely span/type-based guard isn't
always available (e.g. two diagnostics from unrelated compiler stages that
are nonetheless both consequences of the same root cause); reach for it
only when you have a concrete cascade that poisoning/guards can't prevent,
and give the group key enough specificity that it can't accidentally merge
two genuinely distinct errors (e.g. never group solely by diagnostic code -
two different undefined variables must not collapse into one report).

Concretely, poisoning today makes this:

```lisp
(:: main Int)
(fn main (foo 1 2) 0)
```

now reports exactly **one** diagnostic (`foo` is undefined), instead of
three.

## Human format (`--diagnostic-format=human`, default)

Rust-style reports: the offending line is quoted, the exact span is
underlined, and a code + slug + message + suggestion are shown. Example:

```
error: [AX3001] undefined variable `foo`
   ╭─[main.ax:3:4]
   │
 3 │   (foo 1 2)
   │    ─┬─
   │     ╰── no binding named `foo` in scope
   │
   │ Help: run `axiom explain AX3001` for a full explanation
───╯
```

Unlike the pre-1.0 renderer, the header line number is now computed from
the actual primary span (it used to be hardcoded to `1:1` no matter where
the error was), and every span is clamped into valid file bounds so
"unexpected end of file" errors still show the last real line instead of
rendering blank.

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
<SEV> <CODE> <FILE>:<LOC> <SLUG> "<MESSAGE>" [^<LOC>:"<related>"]* [!"<note>"]* [?<field>]*
```

| Field | Meaning |
|---|---|
| `SEV` | One of `E` (error), `W` (warning), `N` (note), `H` (help) |
| `CODE` | Stable code, e.g. `AX3001` |
| `FILE:LOC` | `file:line:col` or `file:line:col-col` or `file:line:col-line:col` |
| `SLUG` | kebab-case, wording-independent diagnostic kind |
| `"MESSAGE"` | Quoted human message (still present - codes alone don't carry the specific name/type involved) |
| `^LOC:"msg"` | A secondary/related span, e.g. the other side of a type mismatch |
| `!"note"` | An additional note |
| `?"msg"` or `?LOC:"msg"~>"replacement"` | A help suggestion; the `~>` form is machine-applicable |

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
(fn (helper x) (+ x 1))

(:: main Int)
(fn main
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
top-level name the checker collected: every `fn`, every
`foreign` binding, every multi-variant `struct` type and its
constructors (variants), every `struct`/`union` single-variant product
(with its exact field shapes and layout attributes), every `type` alias,
and every `class`. Like diagnostics, it honors
`--diagnostic-format`:

```bash
# Dense AXSYM notation, one line per symbol
./target/release/axiom --diagnostic-format=ai symbols main.ax

# JSON Lines, one object per symbol
./target/release/axiom --diagnostic-format=json symbols main.ax

# Aligned table for humans (the default)
./target/release/axiom symbols main.ax

# Also list Axiom's dozen always-in-scope built-in operators (+, ==, &&, ...),
# which are omitted by default (see the `-`/builtins row below)
./target/release/axiom --diagnostic-format=ai symbols main.ax --builtins
```

### Grammar

```
<KIND> <NAME> <FILE>:<LOC>|- "<TYPE>" [#<key>=<value>]*
```

| Field | Meaning |
|---|---|
| `KIND` | One letter: `F` function, `X` foreign binding, `D` ADT type, `C` constructor, `S` struct, `U` union, `A` type alias, `T` trait, `E` effect, `I` impl |
| `NAME` | The declared name, exactly as written |
| `FILE:LOC` | Same `file:line:col[-col\|:line:col]` addressing as AXDL, via the same [`SourceMap`](../axiom-errors/src/source_map.rs) - for a program with `(import ...)`s, `FILE` is the *actual* file that declared this symbol (an imported module's own file), not always the entry file, exactly like AXDL's own multi-file attribution |
| `-` | In place of `FILE:LOC`, for names with no source span at all - in practice, only Axiom's dozen built-in operators (`+`, `==`, `&&`, ...), which `axiom symbols` omits entirely unless `--builtins` is passed (they never change, so printing them on every call is exactly the restating-what's-already-known token waste this notation exists to avoid) |
| `"TYPE"` | Axiom's own curried type syntax, quoted (it can itself contain `->`/parens, so quoting keeps the line's field boundaries unambiguous the same way AXDL quotes messages) |
| `#key=value` | Kind-specific metadata (see below) |

Metadata keys actually emitted today:

| Key | Kinds | Meaning |
|---|---|---|
| `ctors` | `D` | Comma-separated constructor names, e.g. `#ctors=None,Some` |
| `of` | `C` | The constructor's owning struct type (ADT), e.g. `#of=Color` |
| `fields` | `S`, `U` | `name:Type,name:Type,...` - the actual field shapes, not just a count, e.g. `#fields=x:Int,y:Int` |
| `packed` / `repr=C` / `align=N` | `S` | The struct's layout attribute, when it has a non-default one |
| `methods` | `T`, `I` | `name:Type,name:Type,...` for the class's methods (as class/trait) or impl's trait's methods, same shape as `fields` |
| `symbol` | `X` | The real linked C symbol name from `(foreign name :: Type = "c_symbol")`, e.g. `#symbol=printf` - not always the same as `NAME` |
| `tyvars` | `A`, `D`, `S`, `U`, `T` | Comma-separated type parameters, e.g. `#tyvars=a,b`, omitted when there are none |

`KIND` letters are deliberately disjoint from [`Severity::sigil`](../axiom-errors/src/severity.rs)'s `E`/`W`/`N`/`H`, so the first character of a line is never ambiguous about which notation (or which command) produced it even if AXDL and AXSYM output were ever concatenated into one stream.

### Example

Source:

```lisp
(foreign printf :: (-> String Int) = "printf")

(struct Tree (Leaf) (Node Int (Tree Int) (Tree Int)))

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
F add main.ax:14:5-8 "(Int -> (Int -> Int))"
D Tree main.ax:3:7-11 "struct Tree" #ctors=Leaf,Node
C Leaf main.ax:4:4-8 "Tree" #of=Tree
C Node main.ax:5:4-8 "Int Tree Tree" #of=Tree
S Point main.ax:8:9-14 "struct Point" #fields=x:Int,y:Int
```

An agent asked to inspect `Tree` declarations can now
`grep '^D Tree'`/`grep '^C '` for the exact constructor set and
`grep '^X printf'` for the exact FFI signature, instead of paying to
re-read and re-parse the whole file just to recover facts the type
checker already has in hand.

### Why this found a real parser bug

Building AXSYM immediately exposed that `(struct Tree (Leaf) (Node Int (Tree Int) (Tree Int)))` - the README's own example - was parsing `(a)` as a *third,
spurious nullary constructor named `a`* instead of a type-parameter list,
because `parse_tyvars` only recognized bare, unparenthesized type
variables. Without this fix, recursive types like `Tree` could silently
parse with an extra bogus constructor. See `axiom-parser/src/lib.rs`'s
`parse_tyvars`/`looks_like_tyvar_list` for the fix.

## Adding a new diagnostic

1. Add a `CodeInfo` entry to the `registry!` macro invocation in
   `axiom-errors/src/code.rs` with the next free number in the
   appropriate `AX{1,2,3,4}xxx` range, a kebab-case slug, a one-line
   title, and a full explanation paragraph.
2. Add or extend an error variant in the owning crate (`axiom-lexer`,
   `axiom-parser`, or `axiom-sema`) and implement/extend `to_diagnostic()`
   to build a `Diagnostic` using the new code, a primary span, and a
   helpful suggestion.
3. If the new error can be a downstream consequence of another error in
   `axiom-sema`, prefer the poisoning pattern: return/propagate
   `TypeId::TError` from the failing check instead of a fresh placeholder,
   and guard every later comparison with `.is_error()` so a poisoned value
   never triggers a second, redundant diagnostic (see `EApp`/`EIf`/`ECond`
   in `axiom-sema/src/lib.rs` for the pattern). Only reach for
   `.with_group(...)` + `dedup()` when poisoning genuinely can't apply
   (e.g. the cascade spans multiple compiler stages), and pick a group key
   specific enough that it can never merge two unrelated errors.

## Stable node IDs and source-embedded tags

Both NID and AXTAG are now implemented.

* **NID (stable node ID).** Every named declaration gets a content-derived
   ID - a short hash of the declaration kind, name, and structural
   content (type parameters, field types, signatures). This makes NIDs
   sensitive to interface changes (renaming a field, changing a type
   parameter, etc.) while remaining stable across formatting-only edits
   (whitespace, comment changes, reordering of independent fields).
   AXSYM lines emit an optional `@NID` field after the type. This is
   *not* "line numbers with extra steps" - the whole point is a
   coordinate that is stable exactly when `file:line:col` is not.

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
  trusting it. Other tags (`no_refactor`, `owned(region=N)`, etc.) are
  preserved and emitted but not yet validated.

Example AXSYM output with NID and AXTAG metadata:

```
F add main.ax:1:6-9 "(Int -> (Int -> Int))" @a1b2c3d4e5f6a1b2
X printf main.ax:1:10-16 "(String -> Int)" #symbol=printf @c3d4e5f6a1b2
D Tree main.ax:3:7-11 "struct Tree" #ctors=Leaf,Node @e5f6a1b2c3d4
```
