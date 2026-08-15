#!/usr/bin/env python3
"""Check a stdlib case's OUTPUT against its own SOURCE, not against a golden.

`check-stdlib-selfhost.sh` compares what a compiled case prints with the
checked-in `NAME.out`. That comparison is only as trustworthy as the
golden, and a golden can be re-blessed: run the wrong compiler, redirect
its output over `NAME.out`, and the gate goes green while the compiler is
still wrong. This script is the half a re-bless cannot satisfy, because
it never reads `NAME.out` at all - every claim it makes is derived from
`NAME.ax`, and rewriting a golden does not change the source.

Three independent classes of claim, all anchored in the fixture's bytes:

  ANNOTATION  The corpus documents itself. 23 of the 37 cases write the
              expected value beside the call that produces it -
              `(printlnInt (& 12 10))  ; 8`, `(printlnInt (vecCap v))
              ; 8, vecDefaultCap`, `(describe (CInt 7))  ; 7`, where the
              print is inside `describe`'s `match`. Those comments were
              written by hand, by someone who knew what the answer should
              be, and they are not machine-generated from anything. Any
              call on the line is enough - for a print spread over
              several lines the annotation sits beside the closing paren,
              as in 160-arena's `(usable fresh)))  ; 987654321` - and the
              prose filters are what keep a comment from becoming a
              claim, not the shape of the call. The trailing text is
              cut at the first `:` or `=` (both introduce prose), then at
              the first `,`, and what remains must be either a bare
              number - used verbatim, so `0.50` stays `0.50` and does not
              become `0.5` - or an integer arithmetic expression, which
              is evaluated. Anything else is prose and is not a claim:
              `; bits 62 and 63: negative, not overflow` yields nothing.

  MODEL       A second implementation, in Python, of the small part of
              `Str`/`Utf8` whose answer follows from the literal alone.
              `(printlnInt (strLen "héllo"))` must print 6 because the
              literal is six bytes; `(println (strConcat hello world))`
              must print `helloworld` because that is what those two
              literals concatenated are. It reaches six cases that carry
              no annotation at all - 010-hello, 020-fmt, 030-str,
              060-exit-code, 190-string-literals, 330-utf8 - taking the
              corpus from 20 covered files to 26. The model is
              deliberately partial: an
              expression it does not fully understand, or one whose
              indices leave the string, produces NO claim rather than a
              guess. Only `{ ... }` statement positions and `let` bodies
              are walked - never an `if` branch or a lambda, since a
              claim for a branch that is not taken would be a claim about
              nothing.

  HARNESS     A fixture that grades itself. `340-json` defines
              `(fn (eq name got want) (if (strEq got want) { (print
              "ok   ") (println name) 0 } { (print "FAIL ") ... }))` and
              calls it 54 times with the check's name as a literal, so
              the source names every line a passing run must print and
              names the prefix no line may ever start with. Nothing here
              knows what `jsonWrite` of the most negative Int is - the
              fixture decided that, and then published its verdict. This
              is the only class that reaches 340-json, which was 56
              golden lines and no claim, and it is what refuses a golden
              re-blessed from a build with a broken `\\uXXXX` decoder:
              such a golden contains `FAIL surrogate pair length got=6
              want=4`, and the source it came from forbids that line.

Claims are checked in source order as a SUBSEQUENCE of the observed
lines, not position by position: a case may print lines the model has no
opinion about, and an unannotated print between two annotated ones must
not shift everything after it. Being a subsequence is still strong - 446
values taking 169 distinct forms, in order - and a compiler that gets one
of them wrong drops out of the sequence and stays out. Measured: lowering
`>>` to `lshr` instead of `ashr` moves one value in 180-bitwise, and this
file refuses the corpus.

Where a line carries both an annotation and a modelled value the two are
cross-checked against each other before either becomes a claim; a
disagreement is a defect in this file or in the fixture, and is reported
rather than silently resolved.

EXIT STATUS is derived too, for the 34 of 37 cases whose source names
one: `(exit N)` on the unconditional path, or the integer literal `main`
ends on, since `main`'s result is the process's. That is checked against
`<out-dir>/NAME.exit` - the checked-in golden when these are the goldens,
what the program actually returned when they are not. Before this, no
`.exit` file in the corpus was pinned by anything but itself.

Usage:
  verify-stdlib-out.py [--label L] [--filter PREFIX] [--min-files N]
                       [--min-claims N] [--min-distinct N]
                       [--min-harness N] [--min-exits N] <src-dir> <out-dir>

`<out-dir>` holds the observed `NAME.out` and `NAME.exit` for each case
to check; cases with no file there are counted as unchecked and reported.
Passing the source directory as both arguments checks the checked-in
goldens themselves, which needs no compiler. `--filter` restricts the
corpus to one prefix AND turns "selected but not observed" from a note
into a failure: a filtered run that compiled nothing must not pass.
"""

import argparse
import os
import re
import sys

# ---------------------------------------------------------------
# lexing shared by all three classes
# ---------------------------------------------------------------

def mask_literals(line):
    """Blank out string and char literals so `;` inside one is not a comment.

    LENGTH-PRESERVING, one space per masked character: the caller slices
    the RAW line at an offset it found in the masked one. Collapsing a
    literal to a single space instead used to shift every offset after it
    - `(describe (CChar 'K'))  ; 75` handed back `; 75` as the comment
    text, which is not a number, so the claim was dropped. Two of the
    corpus's annotations were lost that way and a third could have been
    read as the wrong number.
    """
    out = []
    i, n = 0, len(line)
    while i < n:
        c = line[i]
        if c == '"':
            start = i
            i += 1
            while i < n:
                if line[i] == '\\':
                    i += 2
                    continue
                if line[i] == '"':
                    i += 1
                    break
                i += 1
            out.append(' ' * (min(i, n) - start))
            continue
        if c == "'":
            j = i + 1
            while j < n:
                if line[j] == '\\':
                    j += 2
                    continue
                if line[j] == "'":
                    j += 1
                    break
                j += 1
            if j <= n and j > i + 1:
                out.append(' ' * (j - i))
                i = j
                continue
        out.append(c)
        i += 1
    return ''.join(out)


ESCAPES = {'n': '\n', 't': '\t', 'r': '\r', '0': '\0', '\\': '\\', '"': '"', "'": "'"}


def unescape(raw):
    """Resolve a literal's escapes. Returns None on an escape we do not know,
    so an unmodelled spelling produces no claim instead of a wrong one."""
    out = []
    i, n = 0, len(raw)
    while i < n:
        c = raw[i]
        if c == '\\':
            if i + 1 >= n:
                return None
            e = raw[i + 1]
            if e not in ESCAPES:
                return None
            out.append(ESCAPES[e])
            i += 2
            continue
        out.append(c)
        i += 1
    return ''.join(out)


TOKEN = re.compile(r'''
      (?P<open>[(\[{])
    | (?P<close>[)\]}])
    | "(?P<str>(?:[^"\\]|\\.)*)"
    | '(?P<chr>(?:[^'\\]|\\.)*)'
    | (?P<atom>[^\s()\[\]{}";]+)
''', re.VERBOSE)


class Str:
    """A modelled string value: the BYTES a literal denotes."""
    __slots__ = ('b',)

    def __init__(self, b):
        self.b = b


def tokenize(src):
    toks = []
    line = 1
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == '\n':
            line += 1
            i += 1
            continue
        if c.isspace():
            i += 1
            continue
        if c == ';':
            while i < n and src[i] != '\n':
                i += 1
            continue
        m = TOKEN.match(src, i)
        if not m:
            i += 1
            continue
        if m.lastgroup is None:
            i = m.end()
            continue
        kind = [k for k in ('open', 'close', 'str', 'chr', 'atom') if m.group(k) is not None][0]
        toks.append((kind, m.group(kind), line))
        line += m.group(0).count('\n')
        i = m.end()
    return toks


def parse(toks):
    """S-expressions as nested lists. Each list carries its opening line in
    slot 0 of a parallel structure; we attach it as an attribute-free tuple
    ('form', line, [children]) to keep line numbers for the claims."""
    pos = 0

    def one():
        nonlocal pos
        kind, text, line = toks[pos]
        if kind == 'open':
            pos += 1
            kids = []
            while pos < len(toks) and toks[pos][0] != 'close':
                kids.append(one())
            if pos < len(toks):
                pos += 1
            return ('form', line, kids)
        if kind == 'close':
            pos += 1
            return ('atom', line, ')')
        pos += 1
        return (kind, line, text)

    forms = []
    while pos < len(toks):
        forms.append(one())
    return forms


# ---------------------------------------------------------------
# class 1: the corpus's own inline expectations
# ---------------------------------------------------------------

ANY_CALL = re.compile(r'\(\s*[A-Za-z_]')
BARE_NUMBER = re.compile(r'^-?[0-9]+(\.[0-9]+)?$')
INT_ARITH = re.compile(r'^-?[0-9]+(\s*[-+*]\s*[0-9]+)+$')


def annotation_claims(path):
    """(line, value) for every call whose trailing comment names its answer.

    The rule used to be `println*` on the same line, which threw away 13
    annotations the corpus had already written by hand: the value a case
    documents is not always beside a print. It is beside the CALL that
    produces the line - `(describe (CInt 7))  ; 7` in 250-field-kinds,
    where the print is inside `describe`'s `match` - and, for a print
    spread over several lines, beside the closing paren rather than the
    opening one: 160-arena's `(usable fresh)))  ; 987654321`. Any call on
    the line is enough; the prose filters below are what keep a comment
    from becoming a claim.
    """
    claims = []
    with open(path, encoding='utf-8') as fh:
        for lineno, raw in enumerate(fh.read().splitlines(), 1):
            masked = mask_literals(raw)
            cut = masked.find(';')
            if cut < 0:
                continue
            if not ANY_CALL.search(masked[:cut]):
                continue
            head = raw[cut + 1:]
            for sep in (':', '='):
                if sep in head:
                    head = head.split(sep, 1)[0]
            head = head.split(',', 1)[0].strip()
            if not head:
                continue
            if BARE_NUMBER.match(head):
                claims.append((lineno, head))
            elif INT_ARITH.match(head):
                # `; 8200 - 70 + 12345` is an answer shown as its working.
                claims.append((lineno, str(eval(head, {'__builtins__': {}}, {}))))
    return claims


# ---------------------------------------------------------------
# class 2: a Python model of the literal-only part of Str/Utf8
# ---------------------------------------------------------------

UNMODELLED = object()   # "this expression is not one we have an opinion about"


def wrap64(x):
    x &= (1 << 64) - 1
    return x - (1 << 64) if x >= (1 << 63) else x


def is_form(node, head=None):
    if node[0] != 'form' or not node[2]:
        return False
    if head is None:
        return True
    h = node[2][0]
    return h[0] == 'atom' and h[2] == head


def head_of(node):
    return node[2][0][2] if is_form(node) and node[2][0][0] == 'atom' else None


def ev(node, env):
    kind, _, val = node
    if kind == 'str':
        s = unescape(val)
        return UNMODELLED if s is None else Str(s.encode('utf-8'))
    if kind == 'atom':
        if re.match(r'^-?[0-9]+$', val):
            return int(val)
        if val == 'true':
            return True
        if val == 'false':
            return False
        return env.get(val, UNMODELLED)
    if kind != 'form':
        return UNMODELLED

    h = head_of(node)
    args = node[2][1:]

    def a(i):
        return ev(args[i], env) if i < len(args) else UNMODELLED

    # Arithmetic, so that an index written as `(- 0 1)` is still an index.
    # Wrapping at 64 bits, because `Int` is a signed 64-bit machine word
    # and `020-fmt` reaches `Int`'s minimum - which has no literal
    # spelling - by overflowing `(+ 9223372036854775807 1)` on purpose.
    if h in ('+', '-', '*') and len(args) == 2:
        x, y = a(0), a(1)
        if isinstance(x, int) and isinstance(y, int) and not isinstance(x, bool) and not isinstance(y, bool):
            return wrap64({'+': x + y, '-': x - y, '*': x * y}[h])
        return UNMODELLED

    if h == 'strFromLit' and len(args) == 1:
        # `(strFromLit (__addr "x"))` denotes the same bytes as `"x"`.
        inner = args[0]
        if is_form(inner, '__addr') and len(inner[2]) == 2:
            return ev(inner[2][1], env)
        return UNMODELLED

    if h == 'strConcat' and len(args) == 2:
        x, y = a(0), a(1)
        if isinstance(x, Str) and isinstance(y, Str):
            return Str(x.b + y.b)
        return UNMODELLED

    if h == 'strLen' and len(args) == 1:
        x = a(0)
        return len(x.b) if isinstance(x, Str) else UNMODELLED

    if h == 'utf8Len' and len(args) == 1:
        x = a(0)
        if isinstance(x, Str):
            try:
                return len(x.b.decode('utf-8'))
            except UnicodeDecodeError:
                return UNMODELLED
        return UNMODELLED

    if h == 'strByte' and len(args) == 2:
        x, i = a(0), a(1)
        # Out of range is a stdlib policy decision, not a fact about the
        # literal, so only an in-range index is claimed.
        if isinstance(x, Str) and isinstance(i, int) and not isinstance(i, bool) and 0 <= i < len(x.b):
            return x.b[i]
        return UNMODELLED

    if h == 'strSlice' and len(args) == 3:
        x, s, n = a(0), a(1), a(2)
        if isinstance(x, Str) and isinstance(s, int) and isinstance(n, int) \
                and not isinstance(s, bool) and not isinstance(n, bool) \
                and 0 <= s and 0 <= n and s + n <= len(x.b):
            return Str(x.b[s:s + n])
        return UNMODELLED

    if h == 'strIsEmpty' and len(args) == 1:
        x = a(0)
        return len(x.b) == 0 if isinstance(x, Str) else UNMODELLED

    if h == 'strEq' and len(args) == 2:
        x, y = a(0), a(1)
        if isinstance(x, Str) and isinstance(y, Str):
            return x.b == y.b
        return UNMODELLED

    if h == 'utf8FromChar' and len(args) == 1:
        x = a(0)
        if isinstance(x, int) and not isinstance(x, bool) and 0 <= x <= 0x10FFFF \
                and not (0xD800 <= x <= 0xDFFF):
            return Str(chr(x).encode('utf-8'))
        return UNMODELLED

    if h == 'utf8Width' and len(args) == 1:
        x = a(0)
        if isinstance(x, int) and not isinstance(x, bool) and 0 <= x <= 0x10FFFF \
                and not (0xD800 <= x <= 0xDFFF):
            return len(chr(x).encode('utf-8'))
        return UNMODELLED

    if h == 'cast' and len(args) == 2:
        # `(cast Int 'é')` is the code point, which is what Python's ord is.
        target = args[0]
        lit = args[1]
        if target[0] == 'atom' and target[2] == 'Int' and lit[0] == 'chr':
            s = unescape(lit[2])
            if s is not None and len(s) == 1:
                return ord(s)
        return UNMODELLED

    if h == 'if' and len(args) == 3:
        c = a(0)
        if isinstance(c, bool):
            return ev(args[1] if c else args[2], env)
        return UNMODELLED

    return UNMODELLED


# Only the `println` family, never `print`: those emit no newline, so
# their argument is part of a line rather than a line, and
# `(print "checks ")` followed by `(println n)` is one output line whose
# text neither call names on its own.
#
# `printlnInt` was here until 2026-08-15 and no longer exists: `println`
# is a MACRO over the `Show` trait, so one name renders every type and
# an Int argument prints the integer that `printlnInt` used to print.
# The model follows by asking what `ev` answered rather than which
# function was called.
PRINT_STR = {'println', 'printlnLit'}


def defmt(text):
    """What a format-string LITERAL prints, or None when it interpolates.

    `println` parses a bare string literal at expansion time
    (macro-system.md MAC-CAP-10): `{{` and `}}` collapse to one brace,
    and anything else in braces is a HOLE whose value the model cannot
    see. A hole yields no claim rather than a guess, which is this
    model's standing rule.
    """
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c in '{}':
            if i + 1 < n and text[i + 1] == c:
                out.append(c)
                i += 2
                continue
            return None
        out.append(c)
        i += 1
    return ''.join(out)


def rendered(node, env):
    """The line a print statement must produce, or None."""
    h = head_of(node)
    args = node[2][1:]
    if h not in PRINT_STR or len(args) != 1:
        return None
    arg = args[0]
    if h == 'printlnLit':
        # `printlnLit` takes the ADDRESS of the bytes, and is a function
        # rather than a macro - no format string, nothing to collapse.
        if not is_form(arg, '__addr') or len(arg[2]) != 2:
            return None
        arg = arg[2][1]
    v = ev(arg, env)
    if isinstance(v, bool):
        return None          # Show's Bool instance, deliberately not modelled
    if isinstance(v, int):
        return str(v)
    if not isinstance(v, Str):
        return None
    try:
        text = v.b.decode('utf-8')
    except UnicodeDecodeError:
        return None
    if h == 'println' and arg[0] == 'str':
        # A BARE literal is the format string. Anything else - a
        # `strConcat`, a binding - reaches `println` as a value and is
        # printed byte for byte, braces included.
        text = defmt(text)
        if text is None:
            return None
    if '\n' in text:
        return None      # more than one output line; not modelled
    return text


# ---------------------------------------------------------------
# class 3: a fixture that grades itself
# ---------------------------------------------------------------
#
# `340-json` is not a transcript, it is a harness. It defines
#
#   (fn (eq name got want)
#     (if (strEq got want)
#         { (print "ok   ") (println name) 0 }
#         { (print "FAIL ") (print name) ... 1 }))
#
# and then calls it 54 times, each with the check's name as a string
# literal. Nothing in the Str/Utf8 model can say what `jsonWrite` of the
# most negative Int is - but the fixture already decided that, and it
# publishes the verdict: a check that passed prints `ok   ` followed by
# its own name, and a check that failed prints `FAIL ` followed by it.
# Both halves of that vocabulary are string literals in `NAME.ax`.
#
# So for a harness case the source names, in order, every line the run
# must produce, and names the prefix no line may ever start with. That
# is derived from the fixture's bytes and survives a re-bless: rewriting
# `NAME.out` from a compiler that breaks `\uXXXX` decoding puts `FAIL
# surrogate pair length got=6 want=4` into the golden, and the golden is
# then refused by the source it was generated from.
#
# Recognition is deliberately narrow. A checker is a two-branch `if`
# whose one branch prints a literal and then one of the function's own
# parameters, and whose other branch leads with a different literal and
# prints that same parameter. Anything else yields no checker and no
# claims - a silence the min-harness floor in main() turns into a
# failure.
#
# Since 2026-08-15 those pieces usually arrive as ONE call. `println` is
# a macro over a compile-time format string, so the harness above is now
#
#   (fn (eq name got want)
#     (if (strEq got want)
#         { (println "ok   {name}") 0 }
#         { (println "FAIL {name} got={got} want={want}") 1 }))
#
# which is the same vocabulary in a different arrangement: the literal
# runs and the holes of one format string are exactly the alternating
# literals and parameters the recogniser already wanted. `fmt_parts`
# splits them back apart, so `branch_prints` sees what it always saw and
# `checker_from` is unchanged.

SKIPPED_HEADS = ('if', 'lambda', 'match', 'when', 'while', 'handle')


class Checker:
    """A self-grading helper: `ok` ++ arg[idx] is the line a passing call
    prints, and no line may begin with `fail`."""
    __slots__ = ('ok', 'fail', 'idx')

    def __init__(self, ok, fail, idx):
        self.ok, self.fail, self.idx = ok, fail, idx


def fmt_parts(text):
    """A format string as alternating ('lit', run) and ('var', name), or
    None when the model should not have an opinion.

    A hole carrying a SPECIFIER answers None: `{n:>8}` does not print
    the parameter, it prints a padded rendering of it, and this class
    claims exact lines. Doubled braces are literal braces.
    """
    parts, run, i, n = [], [], 0, len(text)

    def flush():
        if run:
            parts.append(('lit', ''.join(run)))
            del run[:]

    while i < n:
        c = text[i]
        if c == '}':
            if i + 1 < n and text[i + 1] == '}':
                run.append('}')
                i += 2
                continue
            return None
        if c != '{':
            run.append(c)
            i += 1
            continue
        if i + 1 < n and text[i + 1] == '{':
            run.append('{')
            i += 2
            continue
        j = text.find('}', i + 1)
        if j < 0:
            return None
        name = text[i + 1:j]
        if not name or not re.match(r'^[A-Za-z_][A-Za-z0-9_\'-]*$', name):
            return None      # a specifier, or something not a bare name
        flush()
        parts.append(('var', name))
        i = j + 1
    flush()
    return parts


def branch_prints(node):
    """The leading run of print statements in a branch, as ('lit', text)
    for a literal and ('var', name) for a parameter. Stops at the first
    statement that is not a one-argument print."""
    stmts = node[2] if (node[0] == 'form' and node[2] and head_of(node) is None) else [node]
    out = []
    for s in stmts:
        if s[0] != 'form' or not s[2]:
            break
        h = head_of(s)
        args = s[2][1:]
        if h not in ('println', 'printLit', 'printlnLit') or len(args) != 1:
            break
        arg = args[0]
        if h in ('printLit', 'printlnLit'):
            if not is_form(arg, '__addr') or len(arg[2]) != 2:
                break
            arg = arg[2][1]
        if arg[0] == 'str':
            t = unescape(arg[2])
            if t is None:
                break
            if h == 'println':
                # A bare literal is a FORMAT string: its runs and holes
                # are the literals and parameters this recogniser wants.
                ps = fmt_parts(t)
                if ps is None:
                    break
                out.extend(ps)
            else:
                out.append(('lit', t))
        elif arg[0] == 'atom':
            out.append(('var', arg[2]))
        else:
            break
    return out


def checker_from(params, good, bad):
    """A Checker if `good`/`bad` are the two branches of a checker, else None."""
    if len(good) != 2 or good[0][0] != 'lit' or good[1][0] != 'var':
        return None
    ok, name = good[0][1], good[1][1]
    if not ok or name not in params:
        return None
    if not bad or bad[0][0] != 'lit':
        return None
    fail = bad[0][1]
    if not fail or fail == ok or ('var', name) not in bad:
        return None
    return Checker(ok, fail, params.index(name))


def fn_parts(form):
    """(name, params, body) for a `(fn (name p...) body)`, else None."""
    if not is_form(form):
        return None
    kids = form[2]
    # `(pub fn (main) ...)` is one flat form; drop the visibility atom.
    if kids and kids[0][0] == 'atom' and kids[0][2] == 'pub':
        kids = kids[1:]
    if not kids or kids[0][0] != 'atom' or kids[0][2] != 'fn' or len(kids) < 3:
        return None
    sig = kids[1]
    if not is_form(sig) or sig[2][0][0] != 'atom':
        return None
    return (sig[2][0][2], [p[2] for p in sig[2][1:] if p[0] == 'atom'], kids[2:])


def harness_checkers(forms):
    """name -> Checker for every self-grading helper the source defines."""
    out = {}
    for f in forms:
        parts = fn_parts(f)
        if parts is None:
            continue
        fname, params, body = parts
        if len(body) != 1 or not is_form(body[0], 'if') or len(body[0][2]) != 4:
            continue
        left, right = body[0][2][2], body[0][2][3]
        for good, bad in ((branch_prints(left), branch_prints(right)),
                          (branch_prints(right), branch_prints(left))):
            c = checker_from(params, good, bad)
            if c is not None:
                out[fname] = c
                break
    return out


def checker_calls(node, checkers, found):
    """Every call to a checker under an unconditional statement, in source
    order, with the line it must print. Conditional forms are not entered,
    for the same reason `walk_statements` does not enter them."""
    if node[0] != 'form' or not node[2]:
        return
    h = head_of(node)
    if h in SKIPPED_HEADS:
        return
    c = checkers.get(h)
    if c is not None:
        args = node[2][1:]
        if c.idx < len(args) and args[c.idx][0] == 'str':
            s = unescape(args[c.idx][2])
            if s is not None and '\n' not in s:
                found.append((node[1], c.ok + s))
    for kid in node[2]:
        checker_calls(kid, checkers, found)


def walk_statements(node, env, claims, checkers):
    """Only unconditional statement positions: a block's statements and a
    `let` body. Never an `if` arm, a lambda or a `when`, because a claim
    about a branch that is not taken is a claim about nothing."""
    if node[0] != 'form' or not node[2]:
        return
    h = head_of(node)

    if h == 'let' and len(node[2]) >= 3:
        env = dict(env)
        binds = node[2][1]
        if binds[0] == 'form':
            for b in binds[2]:
                if b[0] == 'form' and len(b[2]) == 2 and b[2][0][0] == 'atom':
                    v = ev(b[2][1], env)
                    if v is not UNMODELLED:
                        env[b[2][0][2]] = v
        for stmt in node[2][2:]:
            walk_statements(stmt, env, claims, checkers)
        return

    if h is None:
        # A `{ ... }` block parses as a form with no leading atom head.
        for stmt in node[2]:
            walk_statements(stmt, env, claims, checkers)
        return

    if checkers:
        found = []
        checker_calls(node, checkers, found)
        if found:
            for lineno, text in found:
                claims.append((lineno, 'harness', text))
            return

    line = rendered(node, env)
    if line is not None:
        claims.append((node[1], 'model', line))


def model_claims(forms, checkers):
    claims = []
    for f in forms:
        parts = fn_parts(f)
        if parts is None or parts[0] != 'main':
            continue
        for stmt in parts[2]:
            walk_statements(stmt, {}, claims, checkers)
    return claims


# ---------------------------------------------------------------
# the status the source names
# ---------------------------------------------------------------
#
# A `.exit` file is a golden like any other, and every one of them was
# re-blessable: nothing here used to open one. Two spellings are read out
# of `NAME.ax` instead. `(exit N)` in an unconditional statement position
# ends the program with N and makes everything after it unreachable;
# otherwise, if the last thing `main` evaluates on that same path is an
# integer literal, that literal IS the status, because `main`'s result is
# the process's. A path that ends in anything else - a call, a variable,
# a trap - yields no claim rather than a guess.

def unconditional_tail(stmts):
    """('exit', n) for the first unconditional `(exit n)`, else the last
    statement node on the unconditional path, else None."""
    last = None
    for s in stmts:
        if is_form(s, 'exit') and len(s[2]) == 2 and s[2][1][0] == 'atom' \
                and re.match(r'^[0-9]+$', s[2][1][2]):
            return ('exit', int(s[2][1][2]))
        h = head_of(s) if s[0] == 'form' else None
        if s[0] == 'form' and s[2] and (h is None or (h == 'let' and len(s[2]) >= 3)):
            inner = unconditional_tail(s[2] if h is None else s[2][2:])
            if isinstance(inner, tuple) and inner and inner[0] == 'exit':
                return inner
            last = inner if inner is not None else last
            continue
        last = s
    return last


def exit_claim(forms):
    """The exit status `NAME.ax` names for itself, or None."""
    for f in forms:
        parts = fn_parts(f)
        if parts is None or parts[0] != 'main':
            continue
        tail = unconditional_tail(parts[2])
        if isinstance(tail, tuple) and tail and tail[0] == 'exit':
            return tail[1]
        if tail is not None and tail[0] == 'atom' and re.match(r'^[0-9]+$', tail[2]):
            n = int(tail[2])
            if 0 <= n <= 255:
                return n
        return None
    return None


# ---------------------------------------------------------------
# checking
# ---------------------------------------------------------------

class Source:
    """Everything `NAME.ax` says about its own run."""
    __slots__ = ('claims', 'conflicts', 'checkers', 'exit')

    def __init__(self, claims, conflicts, checkers, exit_):
        self.claims, self.conflicts, self.checkers, self.exit = \
            claims, conflicts, checkers, exit_


def claims_for(src_path):
    forms = parse(tokenize(open(src_path, encoding='utf-8').read()))
    checkers = harness_checkers(forms)
    ann = annotation_claims(src_path)
    walked = model_claims(forms, checkers)

    by_line = {}
    conflicts = []
    ordered = []
    for line, v in ann:
        by_line[line] = ('annotation', v)
    # Several checker calls can share a line, so claims carry the order
    # they were extracted in and are sorted by (line, order); one line's
    # annotation still precedes anything the walk found on that line.
    for seq, (line, kind, v) in enumerate(walked, 1):
        if kind == 'harness':
            ordered.append((line, seq, kind, v))
            continue
        if line in by_line:
            if by_line[line][1] != v:
                conflicts.append((line, by_line[line][1], v))
            continue
        by_line[line] = ('model', v)
    for line, (kind, v) in by_line.items():
        ordered.append((line, 0, kind, v))
    ordered.sort(key=lambda t: (t[0], t[1]))
    return Source([(ln, k, v) for ln, _, k, v in ordered], conflicts,
                  checkers, exit_claim(forms))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument('src_dir')
    ap.add_argument('out_dir')
    ap.add_argument('--label', default='')
    ap.add_argument('--min-files', type=int, default=27)
    ap.add_argument('--min-claims', type=int, default=420)
    ap.add_argument('--min-distinct', type=int, default=150)
    ap.add_argument('--min-harness', type=int, default=50,
                    help='self-graded check lines the corpus must still claim')
    ap.add_argument('--min-exits', type=int, default=30,
                    help='cases whose exit status must still be derivable')
    ap.add_argument('--filter', default='',
                    help='check only cases whose name starts with this; a case '
                         'selected but not observed is then a failure, not a note')
    ap.add_argument('--quiet', action='store_true')
    args = ap.parse_args()

    sources = sorted(f for f in os.listdir(args.src_dir) if f.endswith('.ax'))
    if args.filter:
        sources = [f for f in sources if f[:-3].startswith(args.filter)]
    if not sources:
        print('FAIL: no .ax sources in %s%s'
              % (args.src_dir, (' matching %r' % args.filter) if args.filter else ''))
        return 1

    failures = 0
    checked_files = 0
    files_with_claims = 0
    total_claims = 0
    harness_claims = 0
    exits_checked = 0
    unchecked = []
    distinct = set()

    for fn in sources:
        name = fn[:-3]
        src_path = os.path.join(args.src_dir, fn)
        out_path = os.path.join(args.out_dir, name + '.out')
        src = claims_for(src_path)
        claims, conflicts = src.claims, src.conflicts

        for line, av, mv in conflicts:
            print('FAIL %s:%d: the source annotation says %r but the model computes %r'
                  % (fn, line, av, mv))
            failures += 1

        if not os.path.exists(out_path):
            unchecked.append(name)
            continue
        checked_files += 1

        # The status the source names, against the status recorded beside
        # the output - the checked-in `NAME.exit` when these are the
        # goldens, what the program actually returned when they are not.
        if src.exit is not None:
            exit_path = os.path.join(args.out_dir, name + '.exit')
            recorded = 0
            if os.path.exists(exit_path):
                text = open(exit_path, encoding='utf-8').read().strip()
                recorded = int(text) if re.match(r'^[0-9]+$', text) else -1
            if recorded != src.exit:
                print('FAIL %s: %s names exit status %d, but %s says %s'
                      % (name, fn, src.exit, exit_path if os.path.exists(exit_path)
                         else '(no %s.exit, so 0)' % name, recorded))
                failures += 1
            else:
                exits_checked += 1

        observed = open(out_path, encoding='utf-8', errors='replace').read().splitlines()

        # A harness case publishes its own verdict, and no re-bless can
        # make that verdict read `ok`: the FAIL prefix is a literal in the
        # source, put there by the fixture's own failure path.
        for cname, c in sorted(src.checkers.items()):
            bad = [ln for ln in observed if ln.startswith(c.fail)]
            if bad:
                print('FAIL %s: %s grades itself, and %d line(s) of %s begin with %r: %s'
                      % (name, fn, len(bad), out_path, c.fail, bad[0]))
                failures += 1
                break

        if not claims:
            continue
        files_with_claims += 1

        i = 0
        for line, kind, want in claims:
            start = i
            while i < len(observed) and observed[i] != want:
                i += 1
            if i >= len(observed):
                print('FAIL %s: %s at %s:%d claims %r, and no such line remains in %s'
                      % (name, kind, fn, line, want, out_path))
                if start < len(observed):
                    print('     unmatched output from that point: %s'
                          % ' | '.join(observed[start:start + 4]))
                failures += 1
                break
            i += 1
        else:
            total_claims += len(claims)
            harness_claims += sum(1 for _, k, _ in claims if k == 'harness')
            distinct.update(w for _, _, w in claims)
            if not args.quiet:
                print('ok   %-28s %3d source-derived values, in order' % (name, len(claims)))

    label = (args.label + ': ') if args.label else ''

    # Anti-vacuousness. A verifier that stops extracting claims reports the
    # same silence as one that checks everything and finds nothing wrong.
    if files_with_claims < args.min_files:
        print('FAIL %sonly %d files yielded a claim; the floor is %d - the extractor '
              'or the corpus moved' % (label, files_with_claims, args.min_files))
        failures += 1
    if total_claims < args.min_claims:
        print('FAIL %sonly %d claims checked; the floor is %d'
              % (label, total_claims, args.min_claims))
        failures += 1
    if len(distinct) < args.min_distinct:
        print('FAIL %sthe claims take only %d distinct values; the floor is %d - a set of '
              'all-alike values cannot distinguish anything'
              % (label, len(distinct), args.min_distinct))
        failures += 1
    if harness_claims < args.min_harness:
        print('FAIL %sonly %d self-graded check lines claimed; the floor is %d - the '
              'harness shape stopped being recognised' % (label, harness_claims, args.min_harness))
        failures += 1
    if exits_checked < args.min_exits:
        print('FAIL %sonly %d exit statuses were derived from a source; the floor is %d'
              % (label, exits_checked, args.min_exits))
        failures += 1
    if unchecked:
        # Without a filter this is the corpus's own report that a case did
        # not run. WITH one, the caller asked for those cases by name, and
        # a case that was asked for and produced nothing is the vacuous
        # pass this file exists to refuse.
        if args.filter:
            print('FAIL %s%d selected case(s) produced no output at all: %s'
                  % (label, len(unchecked), ' '.join(unchecked)))
            failures += 1
        else:
            print('note %s%d case(s) had no observed output and were not checked: %s'
                  % (label, len(unchecked), ' '.join(unchecked)))
    if checked_files < 1:
        print('FAIL %sno case had any observed output; nothing was checked' % label)
        failures += 1

    print('%s%d claims over %d files (%d distinct values, %d self-graded, %d exit '
          'statuses), %d file(s) with observed output'
          % (label, total_claims, files_with_claims, len(distinct), harness_claims,
             exits_checked, checked_files))
    if failures:
        print('%s%d check(s) failed' % (label, failures))
        return 1
    return 0


if __name__ == '__main__':
    sys.exit(main())
