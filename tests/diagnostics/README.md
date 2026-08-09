# Diagnostic corpus

Each `NAME.ax` (or `NAME.axbad`, for a case that deliberately does not
parse) is a program that should draw a diagnostic. Three goldens sit
beside it:

| File | Surface | Gate |
|---|---|---|
| `NAME.axdl` | AXDL, one line per diagnostic | `scripts/check-diagnostics.sh` |
| `NAME.human` | the rendered report, colour and all | `scripts/check-render-selfhost.sh` |
| `NAME.json` | JSON Lines, one object per diagnostic | same |

This asserted `golden == stage0 == stage1` until the Rust compiler was
deleted. A differential does not fail when its reference disappears -
point it at a self-hosted binary and every comparison becomes a compiler
against itself - so the third leg was replaced rather than repointed.
Each gate now has a half that reads a DIFFERENT artifact and that a
re-bless therefore cannot satisfy:

* `verify-axdl-spans.py` recomputes every span claim from the fixture's
  own bytes;
* `verify-json.py` reconstructs every JSON field from `NAME.axdl` and
  the fixture;
* the render gate derives the exit status, the heading, the caret
  geometry and every quoted source row from `NAME.axdl` and the fixture,
  and checks the escape stream against the palette the compiler
  declares.

## The layout of these files is load-bearing

Every golden contains `line:col`, so **reformatting a case invalidates
its golden**. `axiom fmt` inserts blank lines between declarations and
splits multiple declarations off a shared line, which moves every
position in the file. These cases are deliberately left unformatted —
the same state most of `self_host/` is in, and the reason
`scripts/check-fmt.sh --check` is not the mode CI runs.

`070-nonascii-same-line.ax` is the sharpest instance: it puts two
declarations on **one line** with an em-dash between them, precisely so
that the second declaration's name sits after a multi-byte character on
the same line. Split that line and the case still passes while testing
nothing.

## Why a non-ASCII case exists at all

stage0's lexer tokenizes a `Vec<char>`, so its spans are character
indices; stage1's lexer walks bytes. Line numbers agree either way, but
columns do not, and the compiler's own sources are full of em-dashes.
An ASCII-only corpus would have shipped that divergence silently and
detonated at phase 5, when stage1 checks its own source. Here stage0
says column 22 and a byte count says 24.

## Regenerating a golden

Deliberately, and never as a reflex — a changed golden is a changed
compiler, which is the whole point of checking them in:

    AXIOM_BLESS=1 scripts/check-diagnostics.sh          # every case
    AXIOM_BLESS=1 scripts/check-diagnostics.sh 010      # one case

Then read the diff before committing it.
