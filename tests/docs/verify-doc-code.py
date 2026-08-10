#!/usr/bin/env python3
"""Every Axiom code block in the documentation balances its delimiters.

WHY THIS AND NOT "the snippets compile". Most documented blocks are
fragments - a column of literals, a bare expression, a `{}` block - and
a fragment is not a module, so `axiom check` refuses 45 of the 107 that
exist and is right to. Balance is the property fragments and modules
share, it is the property both known defects violated, and it is
checkable with no compiler at all, which is what lets this run in CI's
cheap grammar job.

WHAT IT FOUND when it was written: `README.md`'s multi-method `trait`
and multi-method `impl` examples each carried one extra `)`. Both are
the second, longer example under their heading - the short one above
each was correct - which is how they survived being read.

The scanner is `tests/fmt/verify-fmt.py`'s, loaded rather than copied:
it already knows that `;` runs to end of line, that `#| |#` nests, that
a backslash escapes inside a string, and that `'` is legal inside an
identifier. A second copy of those rules would be a second thing to get
wrong.

Usage: verify-doc-code.py FILE...
"""

import importlib.util
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FMT = os.path.join(HERE, os.pardir, 'fmt', 'verify-fmt.py')

# A fenced block is Axiom if it says so. `text`, `console` and unmarked
# blocks are transcripts and are not read.
FENCE = re.compile(r'^```(scheme|axiom)[ \t]*\n(.*?)^```', re.S | re.M)

# The floor. Docs shrink, and a regex that stopped matching would report
# the same silence as a clean sweep.
MIN_BLOCKS = 80


def load_scanner():
    spec = importlib.util.spec_from_file_location('verify_fmt', FMT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def main(argv):
    if len(argv) < 2:
        print('usage: verify-doc-code.py FILE...', file=sys.stderr)
        return 2
    vf = load_scanner()
    blocks = 0
    failures = []
    for path in argv[1:]:
        with open(path, encoding='utf-8') as fh:
            src = fh.read()
        for m in FENCE.finditer(src):
            body = m.group(2)
            line = src[:m.start()].count('\n') + 1
            blocks += 1
            _, _, _, delims, _ = vf.scan(body)
            depth = 0
            under = False
            for d in delims:
                depth += 1 if d in vf.OPENERS else -1
                if depth < 0:
                    under = True
                    break
            where = '%s:%d' % (os.path.basename(path), line)
            if under:
                failures.append('%s: a closing delimiter with nothing open'
                                % where)
            elif depth > 0:
                failures.append('%s: %d delimiter(s) left open' % (where, depth))
            elif depth < 0:
                failures.append('%s: %d unmatched closing delimiter(s)'
                                % (where, -depth))
    for f in failures:
        print('FAIL doc snippet %s' % f)
    if blocks < MIN_BLOCKS:
        print('FAIL: read %d Axiom code blocks; the floor is %d - the fence '
              'pattern has stopped matching' % (blocks, MIN_BLOCKS))
        return 1
    if failures:
        return 1
    print('ok   %d documented Axiom code blocks balance their delimiters'
          % blocks)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
