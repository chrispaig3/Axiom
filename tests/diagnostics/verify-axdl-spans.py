#!/usr/bin/env python3
"""Check that every span an AXDL golden claims is true of the fixture's bytes.

This is the half of `check-diagnostics.sh` that a re-bless cannot satisfy.

The gate used to assert `golden == stage0 == stage1`: three-way, so a
stage0 bug baked into stage1 showed up as a diff against a file in the
repository rather than as two compilers agreeing with each other. Delete
stage0 and one leg of that tripod is gone, and what is left - `golden ==
the only compiler` - is satisfied by regenerating the golden. A wrong
column, blessed, is green forever.

So the goldens are checked against something that is not a compiler at
all. An AXDL line is

    SEV CODE file:line:colStart-colEnd slug "message" ^L:C-C:"note" ?"help"

with two further text-only fields the grammar allows and this parser
reads without deriving a claim from - `#"label"` (the primary label) and
`!"note"` - and one that DOES carry a claim since 2026-08-14:
`&file:L:C-C:"name"`, an expansion-backtrace frame, whose span points at
the named macro's declaration in the named file (the bare `&"name"` form
still parses and claims nothing). Every one of
the *positions* above is a claim about a file this repository
also contains. `tests/diagnostics/010-duplicate-fn.ax` really does or
does not have a line 3 whose characters 6 through 9 spell `main`. That
is a fact about the fixture, so no amount of blessing can make a wrong
span satisfy it, and unlike a golden it does not churn: the position is
recomputed from the source on every run.

Four things are required of every claim:

  1. The file named resolves to a fixture in this directory - `NAME.ax`,
     `NAME.axbad`, or `mods/NAME.ax` (a diagnostic raised inside an
     imported module names that module's file, not the case's).
  2. The line exists.
  3. The columns lie inside that line: 1-based, end-EXCLUSIVE, so
     `colEnd` may be one past the last character and no further.
  4. Token boundaries. If the slice starts with an identifier character
     the character before it must not be one, and likewise at the end -
     a span may name a whole identifier or something that is not one,
     but never the tail of a longer name. This is what makes an
     off-by-one survivable only by being caught: shift every column by
     one and `main` becomes `ain)`, which still lies inside the line and
     still ends at a legal column, but now begins in the middle of
     `main`. Spans containing a backslash are exempt, and only those: an
     invalid escape sequence (AX1005) is a fragment of a string literal
     by construction, which is the whole reason it is being reported.

And one corroboration, counted rather than required per claim: where the
message names something in backticks and the source slice spells exactly
that, the span is *anchored* - the golden's own text and the fixture's
bytes independently agree on what is being pointed at. 322 of the
corpus's 418 claims are anchored today, and this sentence said 87 of 109
until 2026-08-16, which is the same staleness the floors below record.
The unanchored rest point at expressions rather than
names (`type mismatch: expected Bool, found Int` spans the offending
expression, which spells nothing in particular), so anchoring cannot be
demanded of every claim; a floor is demanded instead, because a
systematic column error collapses the count to near zero. Anchors are
compared against the PRIMARY message only, never the note or help text
attached to the span: `150-undefined-suggestion` spans `helpr` while its
help says `helper`, and accepting the help's spelling would let the span
point at the suggestion instead of the mistake.

COLUMNS ARE CHARACTERS, NOT BYTES. stage0's lexer tokenises a
`Vec<char>`; `060-nonascii-earlier-line` and `070-nonascii-same-line`
exist to pin that, the latter by putting an em-dash and two declarations
on one line so a byte count reads column 24 where the answer is 22.
Decoding UTF-8 here rather than indexing bytes is what makes those two
files pass - and a verifier that indexed bytes would report them as the
only failures in the corpus, which is worth knowing if this ever fires.

Usage:  verify-axdl-spans.py <diagnostics-dir> [<golden.axdl> ...]
        with no goldens named, every `*.axdl` in the directory is read.
Exit 0 if every claim holds; 1 otherwise, listing the failures.
"""

import glob
import os
import re
import sys

# SEV CODE path:line:col[-[line:]col] slug "message"
HEAD = re.compile(r'^([EWNH]) (AX\d{4}) (\S+) (\S+) ')
SPAN = re.compile(r'^(\S+):(\d+):(\d+)(?:-(?:(\d+):)?(\d+))?$')
# A secondary span on a `^note` or `?help`: same file, no path repeated.
SECONDARY = re.compile(r'(\d+):(\d+)(?:-(?:(\d+):)?(\d+))?:')
FRAME = re.compile(r'([^\s:"]+):(\d+):(\d+)(?:-(?:(\d+):)?(\d+))?:')
BACKTICKED = re.compile(r'`([^`]*)`')
# Per AX1001's own help text: letters, digits, `_`, and `'`.
IDENT_CH = re.compile(r"[^\W]|'", re.UNICODE)

ESCAPES = {'n': '\n', 't': '\t', 'r': '\r', '\\': '\\', '"': '"', "'": "'", '0': '\0'}

# Floors, all just under what the corpus produces: 126 goldens, 418
# claims, 322 anchored, 42 codes (re-derived 2026-08-16). A verifier
# that reads nothing reports the same silence as one that verifies
# everything, and the reason this gate needs floors at all is that its
# predecessor's sweep once read zero files and passed.
#
# THE MARGIN IS THE POINT, and it is what went wrong here. These were
# 54/108/86/24 against a corpus of 56/113/90/26 - a few per cent of
# headroom, which is what makes a floor detect a glob that stopped
# matching. The corpus then tripled and the floors did not move.
# Measured 2026-08-16 by running this verifier over a prefix of the
# goldens rather than all of them:
#
#   * on 100 of the 126 goldens, the old floors report NOTHING - all
#     four pass, and a fifth of the corpus has silently stopped being
#     checked. The new floors report four failures.
#   * on 63 - exactly half - the old floors catch it on ONE of the
#     four, the distinct-code count at 21 against 24. The three
#     COUNTING floors all pass: 63 against 54, 135 claims against 108,
#     102 anchored against 86. So the last floor still doing any work
#     was the one measuring variety, not volume, and it was doing it
#     by accident.
#
# A floor is a measurement with an expiry date, and a growing corpus is
# what expires it - so re-derive these whenever the printed counts have
# pulled ahead, and keep the margin small enough that losing a tenth of
# the corpus is a failure.
MIN_GOLDENS = 120
MIN_CLAIMS = 400
MIN_ANCHORED = 310
MIN_CODES = 40


def read_string(text, i):
    """Read a `"..."` starting at text[i]; return (value, index after it)."""
    if i >= len(text) or text[i] != '"':
        raise ValueError('expected a quoted string at column %d' % (i + 1))
    out = []
    i += 1
    while i < len(text):
        c = text[i]
        if c == '\\':
            if i + 1 >= len(text):
                raise ValueError('trailing backslash')
            # `\u{XX}`, Rust Debug's form for a control byte with no
            # two-character escape. AXDL gained these on 2026-08-16,
            # when `quoteBody` stopped passing such bytes through raw;
            # without this arm the fallback below dropped the backslash
            # and read `\u{1}` as the four characters `u{1}`, so the
            # message this verifier derived disagreed with the one the
            # JSON golden carried and 478-json-control-bytes could not
            # be pinned at all.
            if text[i + 1] == 'u' and i + 2 < len(text) and text[i + 2] == '{':
                close = text.find('}', i + 3)
                if close < 0:
                    raise ValueError('unterminated \\u{...} escape')
                digits = text[i + 3:close]
                if not digits or any(d not in '0123456789abcdefABCDEF'
                                     for d in digits):
                    raise ValueError('bad \\u{...} escape %r' % digits)
                out.append(chr(int(digits, 16)))
                i = close + 1
                continue
            out.append(ESCAPES.get(text[i + 1], text[i + 1]))
            i += 2
            continue
        if c == '"':
            return ''.join(out), i + 1
        out.append(c)
        i += 1
    raise ValueError('unterminated string')


def parse(line):
    """An AXDL line -> (code, path, message, [(l1, c1, l2, c2, kind), ...]).

    Parsed structurally rather than scanned for span-shaped substrings,
    so that a `?3:4-5:` appearing INSIDE a message cannot be mistaken for
    a span, and so that a line this grammar does not describe is a
    failure instead of a silent skip.
    """
    m = HEAD.match(line)
    if not m:
        raise ValueError('not an AXDL line')
    _sev, code, span_tok, _slug = m.groups()
    sm = SPAN.match(span_tok)
    if not sm:
        raise ValueError('unparsable primary span %r' % span_tok)
    path, l1, c1, l2, c2 = sm.groups()
    spans = [(int(l1), int(c1), int(l2) if l2 else None,
              int(c2) if c2 else None, 'primary', None, None)]
    message, i = read_string(line, m.end())
    while i < len(line):
        if line[i] == ' ':
            i += 1
            continue
        mark = line[i]
        if mark not in '^?!#&':
            raise ValueError('unexpected %r after the message' % line[i:][:20])
        i += 1
        # `#"label"`, `!"note"` and `&"frame"` are text-only: the primary
        # label, an additional note, and one expansion-backtrace frame.
        # None of them carries a location, so none of them adds a span
        # claim - which is why MIN_CLAIMS and MIN_ANCHORED are unmoved by
        # a corpus that starts using them. They are read rather than
        # skipped because an unread field is a field whose quoting nobody
        # is checking, and `read_string` is what proves each one is a
        # properly escaped string that ends where it says it does.
        #
        # The label in particular must NOT join the anchor text: anchors
        # are compared against the primary message alone, for the reason
        # the docstring gives about `150-undefined-suggestion`, and a
        # label naming the same identifier as the span would turn the
        # corroboration into a tautology.
        if mark in '!#&':
            # A frame MAY carry its own location - `&file:L:C-C:"name"`
            # - and uniquely on the line, the file it names is NOT the
            # primary's: the span points at the macro's declaration in
            # the macro's own unit. That is a claim like any other and
            # is checked like one, against THAT file; the name doubles
            # as the anchor text, since the span is the name token.
            if mark == '&':
                fm = FRAME.match(line, i)
                if fm:
                    fpath, fl1, fc1, fl2, fc2 = fm.groups()
                    fname, i = read_string(line, fm.end())
                    spans.append((int(fl1), int(fc1),
                                  int(fl2) if fl2 else None,
                                  int(fc2) if fc2 else None,
                                  'frame', fpath, fname))
                    continue
            _text, i = read_string(line, i)
            continue
        sec = SECONDARY.match(line, i)
        if sec:
            sl1, sc1, sl2, sc2 = sec.groups()
            spans.append((int(sl1), int(sc1), int(sl2) if sl2 else None,
                          int(sc2) if sc2 else None,
                          'note' if mark == '^' else 'help', None, None))
            i = sec.end()
        _text, i = read_string(line, i)
        if line[i:i + 2] == '~>':          # a machine-applicable fix
            _fix, i = read_string(line, i + 2)
    return code, path, message, spans


def is_ident_ch(ch):
    return bool(ch) and (ch.isalnum() or ch == '_' or ch == "'")


class Fixtures(object):
    """`010-duplicate-fn.ax` -> the lines of whichever file really holds it."""

    def __init__(self, root):
        self.root = root
        self.cache = {}

    def lines(self, named):
        if named in self.cache:
            return self.cache[named]
        stem = named[:-3] if named.endswith('.ax') else named
        text = None
        for cand in (os.path.join(self.root, stem + '.ax'),
                     os.path.join(self.root, stem + '.axbad'),
                     os.path.join(self.root, 'mods', stem + '.ax')):
            if os.path.exists(cand):
                with open(cand, encoding='utf-8') as fh:
                    text = fh.read()
                break
        # split('\n'), not splitlines(): a file ending in a newline gains
        # a final empty line, and that is exactly where an EOF diagnostic
        # points. The `900-unexpected-eof` case has three lines of
        # source and AX2002 at 4:1. (Named without its extension on
        # purpose: on disk it is `.axbad`, and what the diagnostic says
        # is `.ax`, because the harness copies every case in as `.ax`.)
        self.cache[named] = None if text is None else text.split('\n')
        return self.cache[named]


def main(argv):
    if not argv:
        print(__doc__.strip().splitlines()[-3], file=sys.stderr)
        return 2
    root = argv[0]
    goldens = argv[1:] or sorted(glob.glob(os.path.join(root, '*.axdl')))
    fixtures = Fixtures(root)

    failures = []
    claims = 0
    anchored = 0
    boundary_checked = 0
    codes = set()
    read = 0
    lines_seen = 0

    for golden in goldens:
        read += 1
        with open(golden, encoding='utf-8') as fh:
            for lineno, raw in enumerate(fh, 1):
                text = raw.rstrip('\n')
                if not text.strip():
                    continue
                lines_seen += 1
                try:
                    code, path, message, spans = parse(text)
                except ValueError as exc:
                    failures.append('%s:%d: %s: %s' % (golden, lineno, exc, text[:70]))
                    continue
                codes.add(code)
                src = fixtures.lines(path)
                if src is None:
                    failures.append(
                        '%s:%d: names `%s`, which is no fixture in %s'
                        % (golden, lineno, path, root))
                    continue
                names = BACKTICKED.findall(message)
                for (l1, c1, l2, c2, kind, fpath, fname) in spans:
                    claims += 1
                    if fpath is not None:
                        csrc = fixtures.lines(fpath)
                        if csrc is None:
                            failures.append(
                                '%s:%d: frame names `%s`, which is no fixture in %s'
                                % (golden, lineno, fpath, root))
                            continue
                        cpath, src_here = fpath, csrc
                    else:
                        cpath, src_here = path, src
                    where = '%s:%d:%d' % (cpath, l1, c1)
                    if not 1 <= l1 <= len(src_here):
                        failures.append(
                            '%s - %s span claims line %d, the file has %d lines'
                            % (where, kind, l1, len(src_here)))
                        continue
                    line = src_here[l1 - 1]
                    if l2 is not None:
                        # A span across lines (AX1002's unterminated
                        # string is the only one today): both ends must
                        # exist and be in order. There is no slice to
                        # compare, so it stops here.
                        if not 1 <= l2 <= len(src_here) or l2 < l1:
                            failures.append(
                                '%s-%d:%d - %s span ends on a line that does not '
                                'follow it (%d lines in the file)'
                                % (where, l2, c2, kind, len(src_here)))
                        elif c1 < 1 or c1 > len(line) + 1 or c2 < 1 or c2 > len(src_here[l2 - 1]) + 1:
                            failures.append(
                                '%s-%d:%d - %s span starts or ends outside its line'
                                % (where, l2, c2, kind))
                        continue
                    end = c1 if c2 is None else c2
                    if c1 < 1 or end < c1 or end > len(line) + 1:
                        failures.append(
                            '%s-%d - %s span outside a line of %d characters: %r'
                            % (where, end, kind, len(line), line))
                        continue
                    if c2 is None:
                        # A point, not a range: AX2002/AX2001 at end of
                        # file. Bounds are all there is to check.
                        continue
                    slice_ = line[c1 - 1:c2 - 1]
                    if slice_ == fname if fname is not None else slice_ in names:
                        anchored += 1
                    if slice_ and '\\' not in slice_:
                        boundary_checked += 1
                        why = None
                        if slice_ != slice_.strip():
                            why = 'begins or ends on whitespace'
                        elif is_ident_ch(slice_[0]) and c1 >= 2 and is_ident_ch(line[c1 - 2]):
                            why = 'begins in the middle of an identifier'
                        elif is_ident_ch(slice_[-1]) and c2 - 1 < len(line) \
                                and is_ident_ch(line[c2 - 1]):
                            why = 'ends in the middle of an identifier'
                        if why:
                            failures.append(
                                '%s-%d - %s span %s: it covers %r in %r'
                                % (where, c2, kind, why, slice_, line))

    for f in failures[:25]:
        print('  ' + f, file=sys.stderr)
    if len(failures) > 25:
        print('  ... and %d more' % (len(failures) - 25), file=sys.stderr)

    print('%d goldens, %d AXDL lines, %d span claims checked against the fixtures '
          '(%d anchored to a name in the message, %d boundary-checked, %d codes), '
          '%d wrong'
          % (read, lines_seen, claims, anchored, boundary_checked, len(codes),
             len(failures)))

    bad = len(failures) > 0
    if read < MIN_GOLDENS:
        print('FAIL: read %d goldens; the floor is %d - the corpus moved or the '
              'glob broke' % (read, MIN_GOLDENS), file=sys.stderr)
        bad = True
    if claims < MIN_CLAIMS:
        print('FAIL: only %d span claims checked; the floor is %d - the goldens '
              'were empty or unparsed' % (claims, MIN_CLAIMS), file=sys.stderr)
        bad = True
    if anchored < MIN_ANCHORED:
        print('FAIL: only %d of %d claims are anchored to the name their message '
              'quotes; the floor is %d. Every span still lands inside a line, so '
              'this is what a systematic column error looks like'
              % (anchored, claims, MIN_ANCHORED), file=sys.stderr)
        bad = True
    if len(codes) < MIN_CODES:
        print('FAIL: the goldens carry only %d distinct diagnostic codes; the '
              'floor is %d - a corpus that says one thing proves one thing'
              % (len(codes), MIN_CODES), file=sys.stderr)
        bad = True
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
