# Diagnostic parity corpus

Each `NAME.ax` is a program that should draw a diagnostic, and
`NAME.axdl` is the AXDL both compilers must produce for it, byte for
byte. `scripts/check-diagnostics.sh` asserts

    golden == stage0 == stage1

which is self-hosting phase 3's acceptance criterion (`docs/self-hosting.md`).

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
