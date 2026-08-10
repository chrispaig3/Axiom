#!/usr/bin/env python3
"""Every Axiom code block in the documentation balances its delimiters,
and every one that presents itself as a whole PROGRAM compiles.

WHY BALANCE FOR EVERY BLOCK. Most documented blocks are fragments - a
column of literals, a bare expression, a `{}` block - and a fragment is
not a module, so `axiom check` refuses 45 of the 107 that exist and is
right to. Balance is the property fragments and modules share, it is
the property both known defects violated, and it is checkable with no
compiler at all, which is what lets this run in CI's cheap grammar job.

WHY COMPILATION FOR SOME. Balance cannot see an example that parses and
means nothing, and three did: `(fn main ...)` with more than one body
expression is a syntax error, and `printf` is not a function in this
language. A block is compiled when it declares a `main` - which is a
block claiming to be a whole program - and a block opts out by tagging
its fence ```scheme fragment. Three do: the two halves of the
multi-file `Math.Ops` example, which needs a companion file, and the
AXTAG SYNTAX block, whose `(def legacyFn ...)` is deliberately not a
program.

It is opt-in on a compiler path, passed as `--compile <axiom>`, because
this file runs in the grammar job that deliberately has no compiler -
see the roadmap's "a cheap job that gates every other job".
`check-tools-selfhost.sh` passes one.

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
import subprocess
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
FMT = os.path.join(HERE, os.pardir, 'fmt', 'verify-fmt.py')

# A fenced block is Axiom if it says so. `text`, `console` and unmarked
# blocks are transcripts and are not read.
# The info string after the language is captured so a block can opt out
# of the compile check with ```scheme fragment. It is still balance-checked.
FENCE = re.compile(r'^```(scheme|axiom)([^\n]*)\n(.*?)^```', re.S | re.M)

# The floor. Docs shrink, and a regex that stopped matching would report
# the same silence as a clean sweep.
MIN_BLOCKS = 80
# Whole programs among them. 17 compile today; the floor is under that
# and far above what a broken `main` test would leave.
MIN_PROGRAMS = 12


def load_scanner():
    spec = importlib.util.spec_from_file_location('verify_fmt', FMT)
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def is_program(body):
    """A block claiming to be a whole program: it declares `main`."""
    return re.search(r'\(\s*(?:pub\s+)?(?:fn|define)\s+\(?\s*main\b', body) is not None


def compile_block(axiom, body, where, failures, work):
    path = os.path.join(work, 'block.ax')
    with open(path, 'w', encoding='utf-8') as fh:
        fh.write(body)
    r = subprocess.run([axiom, '--diagnostic-format=ai', 'check', path],
                       capture_output=True, text=True)
    if r.returncode != 0:
        first = (r.stdout + r.stderr).strip().split('\n')[0][:120]
        failures.append('%s: does not compile: %s' % (where, first))
        return 0
    return 1


def main(argv):
    axiom = None
    if len(argv) > 2 and argv[1] == '--compile':
        axiom = argv[2]
        argv = [argv[0]] + argv[3:]
    if len(argv) < 2:
        print('usage: verify-doc-code.py [--compile AXIOM] FILE...',
              file=sys.stderr)
        return 2
    vf = load_scanner()
    blocks = 0
    programs = 0
    work = tempfile.mkdtemp(prefix='axdoc')
    failures = []
    for path in argv[1:]:
        with open(path, encoding='utf-8') as fh:
            src = fh.read()
        for m in FENCE.finditer(src):
            body = m.group(3)
            line = src[:m.start()].count('\n') + 1
            blocks += 1
            info = (m.group(2) or '')
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
            elif (axiom is not None and 'fragment' not in info
                  and is_program(body)):
                programs += compile_block(axiom, body, where, failures, work)
    for f in failures:
        print('FAIL doc snippet %s' % f)
    if blocks < MIN_BLOCKS:
        print('FAIL: read %d Axiom code blocks; the floor is %d - the fence '
              'pattern has stopped matching' % (blocks, MIN_BLOCKS))
        return 1
    if failures:
        return 1
    if axiom is not None:
        if programs < MIN_PROGRAMS:
            print('FAIL: compiled %d documented programs; the floor is %d - '
                  'the `main` test has stopped matching, and a compile check '
                  'that compiles nothing passes every time'
                  % (programs, MIN_PROGRAMS), file=sys.stderr)
            return 1
        print('ok   %d documented Axiom code blocks balance their delimiters, '
              '%d of them whole programs that compile' % (blocks, programs))
        return 0
    print('ok   %d documented Axiom code blocks balance their delimiters'
          % blocks)
    return 0


if __name__ == '__main__':
    sys.exit(main(sys.argv))
