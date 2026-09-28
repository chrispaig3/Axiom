# Diagnostic corpus

Each `NAME.ax` here is a program that should draw a diagnostic. A case
that must not parse at all is named `NAME.axbad`. Three goldens sit
beside each case:

| File | Surface | Checked by |
|---|---|---|
| `NAME.axdl` | AXDL, one line per diagnostic | `scripts/check-diagnostics.sh` |
| `NAME.human` | the rendered report, colour and all | `scripts/check-render-selfhost.sh` |
| `NAME.json` | JSON Lines, one object per diagnostic | same |

A golden records what the compiler printed when it was blessed, so
re-blessing can make any output match. Each check therefore also reads
a *different* artifact, one that re-blessing can't satisfy:

* `verify-axdl-spans.py` recomputes every span claim from the fixture's
  own bytes.
* `verify-json.py` rebuilds every JSON field from `NAME.axdl` and the
  fixture.
* The render check derives the exit status, the heading, the caret
  geometry and every quoted source row from `NAME.axdl` and the fixture.
  It also checks the escape stream against the palette the compiler
  declares.

<a id="the-layout-of-these-files-is-load-bearing"></a>
## Don't reformat the cases

Every golden contains `line:col`, so **reformatting a case invalidates
its golden**. `axiom fmt` inserts blank lines between declarations and
splits declarations that share a line, which moves every position in
the file. So these cases stay unformatted, like most of `self_host/`.
`scripts/check-fmt.sh` formats a copy of the tree and re-runs the
suites against it. It doesn't require the working tree to be formatted.

`070-nonascii-same-line.ax` is the sharpest instance. It is meant to
put two declarations on one line with an em dash between them, so the
second declaration's name sits after a multi-byte character on the same
line. Split that line and the case still passes while testing nothing.
The copy in the tree has its declarations on separate lines, so it
needs rejoining before it tests this.

<a id="why-a-non-ascii-case-exists-at-all"></a>
## Why a non-ASCII case exists

Diagnostic columns count characters, starting at 1. On a line with a
multi-byte character, a character count and a byte count disagree,
though line numbers still agree. The compiler's own sources are full of
em dashes, so an ASCII-only corpus would miss a lexer that counted
bytes. That is what `tests/diagnostics/070-nonascii-same-line.ax` is
for: with the second declaration's name after an em dash on the same
line, the right column is 22 and a byte count gives 24.

<a id="regenerating-a-golden"></a>
## Regenerate a golden

Regenerate a golden only when you mean to change the compiler's output.
A changed golden means a changed compiler, which is why the goldens are
checked in.

```bash
AXIOM_BLESS=1 scripts/check-diagnostics.sh          # every case
AXIOM_BLESS=1 scripts/check-diagnostics.sh 010      # one case
```

Then read the diff before you commit it.
