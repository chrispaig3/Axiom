#!/usr/bin/env python3
"""Check that formatting preserved what a program MEANS, not what it spells.

This is the half of `check-fmt-selfhost.sh` that a re-bless cannot
satisfy. The gate's goldens say what the normal form is; this says the
normal form still contains the program. It reads the ORIGINAL bytes and
the FORMATTED bytes of the same file and compares the three things the
printer has no licence to touch, using a scanner written here rather
than the compiler's - so a lexer bug cannot hide behind itself:

  comments        every `;` line and every `#| ... |#` block, body for
                  body. `fmt` shipped having deleted every block comment
                  and every AXTAG (`;@axiom:...`) in the tree, with CI
                  green, because the two tests it had asserted an exit
                  status. AXTAGs are comments, so they are covered here
                  by construction rather than by a special case.

  string literals compared DECODED, not raw: the printer legitimately
                  respells a literal newline inside a string as `\\n`
                  and drops a redundant `\\'`, and both spellings mean
                  the same string. Comparing raw bytes would report
                  those two files as destroyed; comparing decoded values
                  reports a changed string, which is what matters.
                  The seven escapes are stage0's set, `n t r \\ " ' 0`
                  (self_host/lexer.ax:isEscapeChar); an escape outside
                  it is left as written, which is also what the lexer
                  does before refusing the file.

  char literals   decoded the same way.

Not checked, because it is measurably NOT an invariant: the atom
sequence. `fmt` deliberately rewrites `define` to `fn`, `(-> a (-> b
c))` to `(-> a b c)`, `1_000_000` to `1000000`, `007` to `7`, `(- 5)` to
`-5`, `Q.Inner::label` to `Q::Inner::label`, `newtype` to `data`, `$` to
`!`, a bare `mut` effect to `Mut`, and drops `pub` from an import. Those
are the rewrites the goldens exist to pin, and an allowlist here would
be a second, weaker copy of them. Meaning-preservation at the atom level
is instead carried by the gate's rebuild: the formatted tree has to
compile into a compiler that reproduces the zoo golden.

Also checked, on the formatted bytes alone: delimiters balance, no tabs,
no CR, and the file ends in exactly one newline. Trailing spaces are NOT
checked - the printer emits them (`(else ` before a line break, 15 of
the 224 corpus files), the checked-in zoo golden contains them, and a
gate must assert what is true rather than what would be tidy.

Usage:  verify-fmt.py <pairs-file>
        each line: <original-path> <formatted-path>
Exit 0 if every pair preserved everything; 1 otherwise.
"""

import collections
import re
import sys

DELIMS = set('(){}[],')
OPENERS, CLOSERS = '([{', ')]}'
# stage0's seven, self_host/lexer.ax:isEscapeChar.
ESC = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"', "'": "'", '0': '\0'}
CHARLIT = re.compile(r"^'(\\.|[^\\'])'$", re.S)


def decode(body):
    out, i, n = [], 0, len(body)
    while i < n:
        if body[i] == '\\' and i + 1 < n:
            out.append(ESC.get(body[i + 1], '\\' + body[i + 1]))
            i += 2
        else:
            out.append(body[i])
            i += 1
    return ''.join(out)


def scan(text):
    """-> (comments, strings, chars, delims), each a list in source order.

    A hand-rolled scanner, not the compiler's: the point of this file is
    to be a second opinion. It knows only what it has to - that `;` runs
    to end of line, that `#| |#` nests, that a backslash inside a string
    escapes the next character (so `"\\""` is one literal), and that a
    character literal is a single character or one escape between single
    quotes. `'` is also legal INSIDE an identifier (`x'`), which is why
    the character-literal test is anchored at both ends of a whole atom
    rather than applied to a bare quote.
    """
    comments, strings, chars, delims = [], [], [], []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in ' \t\r\n':
            i += 1
        elif c == ';':
            j = text.find('\n', i)
            if j < 0:
                j = n
            comments.append(text[i + 1:j].rstrip())
            i = j
        elif text.startswith('#|', i):
            depth, j = 1, i + 2
            start = j
            while j < n and depth:
                if text.startswith('#|', j):
                    depth += 1
                    j += 2
                elif text.startswith('|#', j):
                    depth -= 1
                    j += 2
                else:
                    j += 1
            comments.append(text[start:max(start, j - 2)].strip())
            i = j
        elif c == '"':
            j = i + 1
            while j < n:
                if text[j] == '\\':
                    j += 2
                elif text[j] == '"':
                    j += 1
                    break
                else:
                    j += 1
            strings.append(decode(text[i + 1:max(i + 1, j - 1)]))
            i = j
        elif c in DELIMS:
            if c in OPENERS or c in CLOSERS:
                delims.append(c)
            i += 1
        else:
            j = i
            while j < n and text[j] not in ' \t\r\n";' and text[j] not in DELIMS:
                if text.startswith('#|', j):
                    break
                j += 1
            atom = text[i:j]
            if CHARLIT.match(atom):
                chars.append(decode(atom[1:-1]))
            i = j if j > i else i + 1
    return comments, strings, chars, delims


def load(path):
    with open(path, encoding='utf-8') as fh:
        return fh.read()


def shape_problems(text, delims):
    """Invariants of the OUTPUT alone, independent of the input."""
    problems = []
    depth = 0
    for d in delims:
        depth += 1 if d in OPENERS else -1
        if depth < 0:
            problems.append('a closing delimiter with nothing open')
            break
    if depth > 0:
        problems.append(f'{depth} delimiter(s) left open')
    if '\t' in text:
        problems.append('contains a tab')
    if '\r' in text:
        problems.append('contains a carriage return')
    if text and not text.endswith('\n'):
        problems.append('does not end in a newline')
    if text.endswith('\n\n'):
        problems.append('ends in a blank line')
    return problems


def maxdepth_of(text, delims):
    depth = maxdepth = 0
    for d in delims:
        if d in OPENERS:
            depth += 1
            maxdepth = max(maxdepth, depth)
        else:
            depth -= 1
    return maxdepth


def indent_problems(text, delims, orig):
    """The output must actually be INDENTED.

    Layout is the one thing about a formatter that has no independent
    truth: where a printer puts its spaces is defined by its goldens and
    nothing else. That makes layout exactly the part a re-bless owns,
    and an adversary proved it - one token in `foIndentStr`
    (`(strConcat s "  ")` -> `(strConcat s "")`) makes the printer emit
    every file flush left, and re-blessing the three goldens this gate
    reads turned it green: 224 of 224 mappings reproduced, zoo matched,
    37 parity cases matched, exit 0. Comments, strings and chars all
    survive flush-left untouched, so nothing else here saw it either.

    This does not model the layout, because modelling it would encode
    the printer's own rule and inherit its bugs. It asserts the much
    weaker thing a re-bless cannot supply: that a file with real nesting
    comes out with a real variety of indentation. Measured over
    `self_host/` and `stdlib/`, every file with structural depth >= 3
    and more than 20 code lines has at least SIX distinct indentation
    levels. Flush left has exactly one. The floor is three.

    Re-run against that same defective build with this check in place:
    13 of the 30 files swept fail, each naming its own numbers - e.g.
    `stdlib/Utf8.ax: formatted to 1 distinct indentation level(s) with
    nesting 16 deep over 191 code lines`. Exit 1, with every golden
    still blessed from the defective compiler.
    """
    depth = maxdepth = 0
    for d in delims:
        if d in OPENERS:
            depth += 1
            maxdepth = max(maxdepth, depth)
        else:
            depth -= 1
    leads = set()
    code_lines = 0
    for line in text.split('\n'):
        body = line.lstrip(' ')
        if body and not body.startswith(';'):
            leads.add(len(line) - len(body))
            code_lines += 1
    if maxdepth >= 3 and code_lines > 20 and len(leads) < 3:
        return [f'{orig}: formatted to {len(leads)} distinct indentation '
                f'level(s) with nesting {maxdepth} deep over {code_lines} '
                f'code lines - the printer is not indenting']
    return []


def compare(kind, before, after, orig, failures):
    a, b = collections.Counter(before), collections.Counter(after)
    if a == b:
        return len(before)
    lost = list((a - b).items())[:3]
    gained = list((b - a).items())[:3]
    failures.append(
        f'{orig}: formatting changed the {kind}: '
        f'lost {lost!r}, gained {gained!r}')
    return len(before)


def main(argv):
    if len(argv) != 1:
        print(__doc__.strip().splitlines()[-3], file=sys.stderr)
        return 1
    pairs = []
    for raw in open(argv[0], encoding='utf-8'):
        raw = raw.strip()
        if raw and not raw.startswith('#'):
            parts = raw.split()
            if len(parts) != 2:
                print(f'  malformed pair line: {raw[:80]}', file=sys.stderr)
                return 1
            pairs.append(tuple(parts))

    failures = []
    n_comments = n_strings = n_chars = n_indented = 0
    for orig, formatted in pairs:
        try:
            before, after = load(orig), load(formatted)
        except OSError as exc:
            failures.append(f'{orig}: cannot read the pair: {exc}')
            continue
        b_com, b_str, b_chr, _ = scan(before)
        a_com, a_str, a_chr, a_delims = scan(after)
        n_comments += compare('comments', b_com, a_com, orig, failures)
        n_strings += compare('string literals', b_str, a_str, orig, failures)
        n_chars += compare('character literals', b_chr, a_chr, orig, failures)
        for problem in shape_problems(after, a_delims):
            failures.append(f'{orig}: the formatted output {problem}')
        failures.extend(indent_problems(after, a_delims, orig))
        if maxdepth_of(after, a_delims) >= 3:
            n_indented += 1

    for f in failures[:20]:
        print('  ' + f, file=sys.stderr)
    if len(failures) > 20:
        print(f'  ... and {len(failures) - 20} more', file=sys.stderr)
    print(f'{len(pairs)} formatted files verified against their source: '
          f'{n_comments} comments, {n_strings} strings, {n_chars} char '
          f'literals preserved, {n_indented} indented, '
          f'{len(failures)} failure(s)')

    # Silence is the failure this file exists to avoid: verifying nothing
    # reads exactly like verifying everything. The corpus carries ~7,700
    # comments and ~1,300 string literals over ~240 pairs; the floors sit
    # well under that and above anything a broken sweep would produce.
    # A rule that never applies is a rule nobody is checking. The corpus
    # has ~200 files with nesting three deep or more; the floor is well
    # under that and far above what a truncated sweep would leave.
    if n_indented < 50:
        print(f'FAIL: only {n_indented} of {len(pairs)} formatted files were '
              f'nested deeply enough for the indentation rule to apply; the '
              f'floor is 50', file=sys.stderr)
        return 1
    if len(pairs) < 150:
        print(f'FAIL: only {len(pairs)} pairs given; the floor is 150 - '
              f'the sweep that produced them lost its corpus', file=sys.stderr)
        return 1
    if n_comments < 2000 or n_strings < 300:
        print(f'FAIL: only {n_comments} comments and {n_strings} strings '
              f'seen; the floors are 2000 and 300 - the scanner matched '
              f'nothing, which is not the same as nothing being wrong',
              file=sys.stderr)
        return 1
    return 1 if failures else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
