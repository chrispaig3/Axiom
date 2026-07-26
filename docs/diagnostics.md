# Axiom Diagnostics

Axiom's compiler diagnostics are built around one goal: **tell you why,
not just where.** A location without an explanation forces every
developer (human or AI agent) to re-derive the reasoning the compiler
already had. This document describes the diagnostic architecture, the
human-readable report format, and Axiom's AI-optimized notation ("AXDL").

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
(define main (foo 1 2) 0)
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
