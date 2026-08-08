#!/usr/bin/env python3
"""Check that every AXSYM line's position claim is true of the source.

This is the half of `check-tools-selfhost.sh` that a re-bless cannot
satisfy, and it replaces a comparison against the Rust compiler with
something strictly stronger: agreeing with another implementation only
says the two agree, while this says the answer is *correct*.

An AXSYM line is

    KIND name file:line:colStart-colEnd "type" @nid

and the claim it makes is checkable against the file it names: at that
line, between those columns, the source must literally spell that name.
A symbol emitted at the wrong position fails here no matter how many
goldens are regenerated, and unlike a golden it does not churn when an
edit moves a span - the position is recomputed from the source every
run, so it is only ever wrong when it is wrong.

COLUMNS ARE CHARACTERS, NOT BYTES. `axiom-errors/src/source_map.rs`
says so at length, and stage1 reproduces it: the Rust lexer tokenises a
`Vec<char>`, so a file with a non-ASCII character before a declaration
reports a column that a byte count would miss. `tests/diagnostics/060`
and `070` exist because of that. Decoding here rather than indexing
bytes is what makes those two files pass.

Usage:  verify-axsym.py <axsym-file> [<axsym-file> ...]
        reads AXSYM lines, resolves paths relative to CWD.
Exit 0 if every claim holds; 1 otherwise, listing the failures.
"""

import re
import sys

# KIND name path:line:c1-c2 "type" @nid  - the type and nid are not
# checked here; the position is the falsifiable part.
LINE = re.compile(r'^([A-Z]+) (\S+) (.+?):(\d+):(\d+)-(\d+) ')

# Some symbols have no position and say so with a bare `-`: the builtin
# `Option` and its constructors, which no file declares, and the
# operations of an `(effect E ...)`, which carry their effect rather
# than a span. They are counted rather than skipped - an unexplained
# skip is how a sweep reads fewer lines than it should while still
# reporting the silence it was looking for.
POSITIONLESS = re.compile(r'^([A-Z]+) (\S+) - ')

_cache = {}


def source_lines(path):
    if path not in _cache:
        try:
            with open(path, encoding='utf-8') as fh:
                _cache[path] = fh.read().split('\n')
        except OSError:
            _cache[path] = None
    return _cache[path]


def main(argv):
    checked = 0
    positionless = 0
    failures = []
    unrecognised = []
    for arg in argv:
        with open(arg, encoding='utf-8') as fh:
            for raw in fh:
                text_line = raw.rstrip('\n')
                if not text_line.strip():
                    continue
                m = LINE.match(text_line)
                if not m:
                    if POSITIONLESS.match(text_line):
                        positionless += 1
                    else:
                        # Not a lax fallback: correct output has ZERO of
                        # these, measured over the whole corpus. The
                        # ablation drill produced 23, all one-character
                        # names - shifting the start column made the span
                        # zero-width, and `fmtSpan` prints that as
                        # `line:col` with no dash. A format that changes
                        # under a defect is a symptom of it.
                        unrecognised.append(
                            f'{arg}: unrecognised AXSYM line: {text_line[:90]}')
                    continue
                _kind, name, path, line_s, c1_s, c2_s = m.groups()
                line, c1, c2 = int(line_s), int(c1_s), int(c2_s)
                # Counted here, before anything can go wrong with it, so
                # that `checked` is the number of claims EXAMINED and
                # `failures` can never exceed it. Counting after the
                # range test instead reported "14100 verified, 14123
                # wrong" during the ablation drill - a pair of numbers
                # that cannot both be true and that took a second look
                # to explain.
                checked += 1
                lines = source_lines(path)
                if lines is None:
                    failures.append(f'{arg}: names a file that cannot be read: {path}')
                    continue
                if not (1 <= line <= len(lines)):
                    failures.append(
                        f'{path}:{line} - claimed for `{name}` but the file has '
                        f'{len(lines)} lines')
                    continue
                text = lines[line - 1]
                # 1-based, end-exclusive, in characters.
                got = text[c1 - 1:c2 - 1]
                if got != name:
                    failures.append(
                        f'{path}:{line}:{c1}-{c2} - AXSYM says `{name}`, '
                        f'the source says `{got}`')
    for f in (failures + unrecognised)[:20]:
        print('  ' + f, file=sys.stderr)
    extra = len(failures) + len(unrecognised) - 20
    if extra > 0:
        print(f'  ... and {extra} more', file=sys.stderr)
    # Three counts that add up, deliberately. An earlier version printed
    # "14100 verified, 14123 wrong" - two numbers that cannot both be
    # true - because unrecognised lines were folded into the failure
    # count without being counted as examined.
    print(f'{checked} AXSYM position claims checked, {len(failures)} wrong; '
          f'{positionless} positionless by design; '
          f'{len(unrecognised)} unrecognised')
    # Silence is the failure mode this file exists to avoid: verifying
    # nothing and reporting success reads exactly like verifying
    # everything. The floor is well under the 14,123 the corpus emits.
    if checked < 1000:
        print(f'FAIL: only {checked} claims checked; the floor is 1000 - '
              f'the input was empty or unparsed', file=sys.stderr)
        return 1
    return 1 if (failures or unrecognised) else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
