#!/usr/bin/env python3
"""Check that every JSON golden says what the AXDL golden and the fixture say.

This is to `NAME.json` what verify-axdl-spans.py is to `NAME.axdl`: the
half a re-bless cannot satisfy. `AXIOM_BLESS=1` rewrites the JSON
goldens; it does not write `NAME.axdl`, and it cannot write the fixture,
which is the compiler's INPUT.

WHY THIS EXISTS AT ALL. The JSON renderer had no golden and no gate of
any kind - it was reachable with `--diagnostic-format=json`, documented
in docs/diagnostics.md, and checked by nothing. Its one recorded
divergence from stage0 (`"label"` hardcoded to `""`) was found by
reading it, which is not a method that scales.

WHAT IS DERIVED, per diagnostic:

  * one JSON object per AXDL line, in the same order. A renderer that
    dropped, merged or reordered a diagnostic in one format but not the
    other fails here even though each format's own golden is
    self-consistent.
  * `severity` from the sigil, `code`/`slug`/`message`/`file` from the
    AXDL's own fields.
  * `span.start` and `span.end` equal to the AXDL span, which is what
    stops the two formats drifting apart on a column. AXDL prints
    `L:C` for an empty span, `L:C-C2` within a line and `L:C-L2:C2`
    across lines; all three are expanded here to the same (line, col)
    pair the JSON carries.
  * `char_start`/`char_end` RECOMPUTED FROM THE FIXTURE as character
    offsets. This is the strongest leg: the renderer converts byte
    offsets to characters at print time, and a regression to bytes
    would leave every ASCII case passing and exactly the non-ASCII ones
    wrong - which is the same trap `060-nonascii-earlier-line` and
    `070-nonascii-same-line` were added to the AXDL corpus for.
  * `label` from the AXDL's `#` field, `related` from `^`, `notes` from
    `!`, `help` from `?`, `expansion` from `&`.

The comparison is on the whole decoded object, so a key the renderer
invented and a key it dropped are both failures; a derivation that
merely checked the keys it knew about would accept either.

`expansion` has no stage0 counterpart: stage0 carried an expansion
backtrace in its Diagnostic and in its AXDL grammar but never in its
JSON, because nothing ever populated it. The rest of the shape is
stage0's `json_line`, field for field.

Usage:  verify-json.py <diagnostics-dir> [<golden.axdl> ...]
        with no goldens named, every `*.axdl` in the directory is read.
Exit 0 if every field holds; 1 otherwise, listing the failures.
"""

import glob
import importlib.util
import json
import os
import sys

_HERE = os.path.dirname(os.path.abspath(__file__))


def _sibling(name, path):
    spec = importlib.util.spec_from_file_location(name, os.path.join(_HERE, path))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


# The AXDL grammar is defined once, next door. Importing it rather than
# restating it is what keeps the two verifiers from disagreeing about
# what an AXDL line is.
axdl = _sibling('axdl_spans', 'verify-axdl-spans.py')

# Floors, all under what the corpus produces today: 52 goldens, 86
# objects, 1784 fields. A verifier that reads nothing reports the same
# silence as one that verifies everything, and the failure mode this
# guards is a derivation that stops producing rather than one that
# produces a wrong answer.
MIN_GOLDENS = 45
MIN_OBJECTS = 75
MIN_FIELDS = 1600


def norm_span(l1, c1, l2, c2):
    """AXDL's three span spellings -> (startLine, startCol, endLine, endCol)."""
    l1, c1 = int(l1), int(c1)
    if c2 is None:                      # `L:C` - empty span
        return (l1, c1, l1, c1)
    if l2 is None:                      # `L:C-C2` - within one line
        return (l1, c1, l1, int(c2))
    return (l1, c1, int(l2), int(c2))   # `L:C-L2:C2`


def parse_full(line):
    """An AXDL line -> every field it carries, structurally."""
    m = axdl.HEAD.match(line)
    if not m:
        raise ValueError('not an AXDL line')
    sev, code, span_tok, slug = m.groups()
    sm = axdl.SPAN.match(span_tok)
    if sm:
        path, l1, c1, l2, c2 = sm.groups()
        span = norm_span(l1, c1, l2, c2)
    elif span_tok.endswith(':-'):       # stage0's spelling for "no span"
        path, span = span_tok[:-2], None
    else:
        raise ValueError('unparsable primary span %r' % span_tok)

    message, i = axdl.read_string(line, m.end())
    out = {'sev': sev, 'code': code, 'slug': slug, 'file': path,
           'span': span, 'message': message, 'label': None,
           'related': [], 'notes': [], 'helps': [], 'frames': []}

    while i < len(line):
        if line[i] == ' ':
            i += 1
            continue
        mark = line[i]
        i += 1
        if mark in '!&#':
            text, i = axdl.read_string(line, i)
            if mark == '!':
                out['notes'].append(text)
            elif mark == '&':
                out['frames'].append(text)
            else:
                out['label'] = text
            continue
        if mark not in '^?':
            raise ValueError('unexpected %r after the message' % line[i - 1:][:20])
        sp = None
        sec = axdl.SECONDARY.match(line, i)
        if sec:
            sp = norm_span(*sec.groups())
            i = sec.end()
        text, i = axdl.read_string(line, i)
        if mark == '^':
            out['related'].append((sp, text))
        else:
            fix = None
            if line[i:i + 2] == '~>':
                fix, i = axdl.read_string(line, i + 2)
            out['helps'].append((sp, text, fix))
    return out


def char_off(lines, line, col):
    """The character offset of 1-based (line, col), from the fixture's text.

    Every earlier line contributes its characters plus its newline. This
    is the same count `charsBetween src 0 off` makes over the bytes, and
    deliberately not the same number a byte offset would give.
    """
    if line - 1 > len(lines):
        raise ValueError('line %d past end of file' % line)
    return sum(len(l) + 1 for l in lines[:line - 1]) + (col - 1)


def span_obj(lines, sp):
    sl, sc, el, ec = sp
    return {'start': {'line': sl, 'col': sc},
            'end': {'line': el, 'col': ec},
            'char_start': char_off(lines, sl, sc),
            'char_end': char_off(lines, el, ec)}


def derive(f, lines):
    """The JSON object the renderer must have produced for this AXDL line."""
    want = {
        'severity': 'error' if f['sev'] == 'E' else 'warning',
        'code': f['code'],
        'slug': f['slug'],
        'message': f['message'],
        'file': f['file'],
        'related': [{'span': span_obj(lines, sp), 'label': text}
                    for sp, text in f['related']],
        'notes': list(f['notes']),
        'help': [text for _sp, text, _fix in f['helps']],
        'expansion': list(f['frames']),
    }
    # A spanless diagnostic carries neither key - the renderer emits the
    # pair or neither, and so does this.
    if f['span'] is not None:
        want['span'] = span_obj(lines, f['span'])
        want['label'] = f['label'] or ''
    return want


def count_fields(obj):
    n = 0
    if isinstance(obj, dict):
        for v in obj.values():
            n += 1 + count_fields(v)
    elif isinstance(obj, list):
        for v in obj:
            n += count_fields(v)
    return n


def main(argv):
    if not argv:
        print(__doc__.strip().splitlines()[-3], file=sys.stderr)
        return 2
    root = argv[0]
    goldens = argv[1:] or sorted(glob.glob(os.path.join(root, '*.axdl')))
    fixtures = axdl.Fixtures(root)

    failures = []
    read = 0
    objects = 0
    fields = 0

    for g in goldens:
        stem = os.path.basename(g)[:-len('.axdl')]
        jpath = os.path.join(root, stem + '.json')
        if not os.path.exists(jpath):
            failures.append('%s: no JSON golden at %s' % (stem, jpath))
            continue
        read += 1

        with open(g, encoding='utf-8') as fh:
            axdl_lines = [l for l in fh.read().split('\n')
                          if l[:2] in ('E ', 'W ', 'N ', 'H ')]
        with open(jpath, encoding='utf-8') as fh:
            raw = fh.read()
        if '\x1b' in raw:
            failures.append('%s: the JSON golden carries an ANSI escape' % stem)
        json_lines = [l for l in raw.split('\n') if l.strip()]

        if len(axdl_lines) != len(json_lines):
            failures.append('%s: %d AXDL line(s), %d JSON object(s)'
                            % (stem, len(axdl_lines), len(json_lines)))
            continue

        for k, (aline, jline) in enumerate(zip(axdl_lines, json_lines)):
            where = '%s line %d' % (stem, k + 1)
            try:
                got = json.loads(jline)
            except ValueError as e:
                failures.append('%s: not valid JSON (%s)' % (where, e))
                continue
            try:
                f = parse_full(aline)
            except ValueError as e:
                failures.append('%s: unreadable AXDL (%s)' % (where, e))
                continue
            lines = fixtures.lines(f['file'])
            if lines is None:
                failures.append('%s: AXDL names %s, not a fixture here'
                                % (where, f['file']))
                continue
            try:
                want = derive(f, lines)
            except ValueError as e:
                failures.append('%s: cannot derive (%s)' % (where, e))
                continue

            objects += 1
            fields += count_fields(want)
            if got != want:
                for key in sorted(set(got) | set(want)):
                    if got.get(key, '<missing>') != want.get(key, '<missing>'):
                        failures.append(
                            '%s: %r is %s, the AXDL and the fixture say %s'
                            % (where, key,
                               json.dumps(got.get(key, None)),
                               json.dumps(want.get(key, None))))

    for f in failures:
        print('FAIL ' + f, file=sys.stderr)

    bad = bool(failures)
    if read < MIN_GOLDENS:
        print('FAIL: read %d JSON golden(s); the floor is %d'
              % (read, MIN_GOLDENS), file=sys.stderr)
        bad = True
    if objects < MIN_OBJECTS:
        print('FAIL: checked %d JSON object(s); the floor is %d'
              % (objects, MIN_OBJECTS), file=sys.stderr)
        bad = True
    if fields < MIN_FIELDS:
        print('FAIL: checked %d field(s); the floor is %d - that derivation '
              'stopped producing, which is not the same as nothing being wrong'
              % (fields, MIN_FIELDS), file=sys.stderr)
        bad = True

    if not bad:
        print('%d JSON goldens, %d objects, %d fields derived from the AXDL '
              'goldens and the fixtures, 0 wrong' % (read, objects, fields))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
