#!/usr/bin/env python3
"""The second implementation behind `scripts/check-ddc.sh`: a direct
interpreter for a frozen subset of Axiom, written from the language
reference rather than from the compiler's sources.

WHY THIS EXISTS. Every gate in this tree runs a compiler descended
from the committed LLVM seed, so a defect in the seed is invisible to
all of them: each one asks the suspect to grade its own work. The
lineage gate (`check-seed-lineage.sh`) replays the seed back to a Rust
compiler no Axiom seed touched, but that anchor shares an author with
`self_host/` and covers the first seed, not the current tree. This
file is the deliberately simple checker the roadmap's item 01 calls
for: a different language (Python, standard library only), independent
logic (derived from `docs/reference.md`'s described behaviour, never
ported from `self_host/*.ax`), a subset (below), compiling the same
`sources (tests/ddc/*.ax)` to a comparable artefact (the program's
exit status). The gate requires the seed-descended binary and this
interpreter to agree with each other and with the `; expect N` the
fixture states.

THE SUBSET, frozen. Extending it is a design change, not a bug fix:
every form outside it is a loud error, never a guess.
  Top level: `(:: name Type)` signatures (read and ignored - the types
    are the compiler's business; agreement on VALUES is this file's),
    and `(fn (name params...) body)` with exactly one body expression.
    `import` and any other top-level form are refused.
  Expressions: integer literals, `true`/`false`, variables, `if`
    (the condition must be a Bool, as the language requires), `let`
    with sequential bindings, calls to defined functions (arity
    checked, no partial application), and the operators
    `+ - * / % == != < > <= >=`.
  NOT in the subset: strings, chars, floats, `&&`/`||`/`!` (their
    short-circuit behaviour is not pinned down here), brace blocks,
    `while`/`mut`/`set`, ADTs, structs, effects, macros, FFI.
  Integers are 64-bit two's-complement: every arithmetic result is
    masked to i64, `/` truncates toward zero and `%` takes the
    dividend's sign (the LLVM `sdiv`/`srem` semantics the backend
    emits). A fixture that overflows is still deterministic - both
    sides wrap identically - but the shipped fixtures stay small.
  Limits: recursion depth under 10,000 (CPython frames), `main` takes
    no arguments and answers an Int. Anything else exits 3 with the
    reason on stderr; a program's answer exits as its status code,
    truncated to a byte by the OS exactly as a compiled binary's is.

WHAT IT FOUND when it was written: nothing - and that is the point
being recorded. The eight fixtures agree on first contact; the value
of this file is not a discrepancy but the standing comparison, and
the gate's ablation (a flipped `icmp sgt` in emitted IR) proves the
comparison can fail.
"""

import sys

MASK = (1 << 64) - 1


def to_i64(n):
    n &= MASK
    return n - (1 << 64) if n >= (1 << 63) else n


def trunc_div(a, b):
    if b == 0:
        raise InterpError("division by zero is outside the DDC subset")
    q = abs(a) // abs(b)
    return to_i64(-q if (a < 0) != (b < 0) else q)


def trunc_rem(a, b):
    if b == 0:
        raise InterpError("remainder by zero is outside the DDC subset")
    return to_i64(a - trunc_div(a, b) * b)


class InterpError(Exception):
    pass


def tokenize(src):
    toks = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c == ";":
            while i < n and src[i] != "\n":
                i += 1
        elif c in " \t\r\n":
            i += 1
        elif c in "()":
            toks.append(c)
            i += 1
        elif c == '"':
            raise InterpError("string literals are outside the DDC subset")
        else:
            j = i
            while j < n and src[j] not in " \t\r\n();\"":
                j += 1
            toks.append(src[i:j])
            i = j
    return toks


def parse(toks):
    pos = [0]

    def expr():
        if pos[0] >= len(toks):
            raise InterpError("unexpected end of file")
        t = toks[pos[0]]
        pos[0] += 1
        if t == "(":
            xs = []
            while True:
                if pos[0] >= len(toks):
                    raise InterpError("unterminated form")
                if toks[pos[0]] == ")":
                    pos[0] += 1
                    return xs
                xs.append(expr())
        if t == ")":
            raise InterpError("stray close paren")
        return t

    forms = []
    while pos[0] < len(toks):
        forms.append(expr())
    return forms


def is_int(tok):
    return isinstance(tok, str) and tok.lstrip("-").isdigit() and tok not in ("-", "")


ARITH = {"+", "-", "*", "/", "%"}
CMP = {"==", "!=", "<", ">", "<=", ">="}


def apply_arith(head, a, b):
    # Dict dispatch: a missing operator is a KeyError, never a silent
    # fallthrough into another operator's answer.
    return {
        "+": lambda: to_i64(a + b),
        "-": lambda: to_i64(a - b),
        "*": lambda: to_i64(a * b),
        "/": lambda: trunc_div(a, b),
        "%": lambda: trunc_rem(a, b),
    }[head]()


class Interp:
    def __init__(self, forms):
        self.fns = {}
        for f in forms:
            if not isinstance(f, list) or not f:
                raise InterpError("top-level form must be a list, got %r" % (f,))
            head = f[0]
            if head == "::":
                continue
            if head == "fn":
                if len(f) != 3:
                    raise InterpError("fn takes a binder and one body, got %r" % (f,))
                bind, body = f[1], f[2]
                if not isinstance(bind, list) or not bind:
                    raise InterpError("bad fn binder %r" % (bind,))
                name, params = bind[0], bind[1:]
                if name in self.fns:
                    raise InterpError("duplicate definition %r" % name)
                for p in params:
                    if not isinstance(p, str):
                        raise InterpError("bad parameter %r" % (p,))
                self.fns[name] = (params, body)
                continue
            raise InterpError("outside the DDC subset: %r" % (head,))
        if "main" not in self.fns:
            raise InterpError("no main function")

    def run(self):
        params, body = self.fns["main"]
        if params:
            raise InterpError("main takes no arguments in the DDC subset")
        sys.setrecursionlimit(10000)
        v = self.eval(body, {})
        if not isinstance(v, int) or isinstance(v, bool):
            raise InterpError("main must answer an Int, got %r" % (v,))
        return v

    def eval(self, e, env):
        if isinstance(e, str):
            if is_int(e):
                return to_i64(int(e))
            if e == "true":
                return True
            if e == "false":
                return False
            if e in env:
                return env[e]
            raise InterpError("undefined variable %r" % e)
        if not isinstance(e, list) or not e:
            raise InterpError("bad expression %r" % (e,))
        head = e[0]
        if head == "if":
            if len(e) != 4:
                raise InterpError("if takes three parts, got %r" % (e,))
            c = self.eval(e[1], env)
            if not isinstance(c, bool):
                raise InterpError("if consumes a Bool, got %r" % (c,))
            return self.eval(e[2] if c else e[3], env)
        if head == "let":
            if len(e) != 3 or not isinstance(e[1], list):
                raise InterpError("bad let %r" % (e,))
            env = dict(env)
            for b in e[1]:
                if not isinstance(b, list) or len(b) != 2 or not isinstance(b[0], str):
                    raise InterpError("bad let binding %r" % (b,))
                env[b[0]] = self.eval(b[1], env)
            return self.eval(e[2], env)
        if isinstance(head, str) and head in ARITH:
            if len(e) != 3:
                raise InterpError("operator %r takes two operands" % head)
            a, b = self.eval(e[1], env), self.eval(e[2], env)
            if not self.is_int(a) or not self.is_int(b):
                raise InterpError("operator %r needs Ints" % head)
            try:
                return apply_arith(head, a, b)
            except KeyError:
                raise InterpError("operator %r is outside the DDC subset" % head)
        if isinstance(head, str) and head in CMP:
            if len(e) != 3:
                raise InterpError("comparison %r takes two operands" % head)
            a, b = self.eval(e[1], env), self.eval(e[2], env)
            if head in ("==", "!="):
                if type(a) is not type(b) and not (self.is_int(a) and self.is_int(b)):
                    raise InterpError("comparison %r needs same types" % head)
                r = a == b
                return r if head == "==" else not r
            if not self.is_int(a) or not self.is_int(b):
                raise InterpError("comparison %r needs Ints" % head)
            try:
                return {"<": a < b, ">": a > b, "<=": a <= b, ">=": a >= b}[head]
            except KeyError:
                raise InterpError("comparison %r is outside the DDC subset" % head)
        if isinstance(head, str) and head in self.fns:
            params, body = self.fns[head]
            if len(e) - 1 != len(params):
                raise InterpError(
                    "partial application is not supported: %r takes %d, got %d"
                    % (head, len(params), len(e) - 1)
                )
            vals = [self.eval(a, env) for a in e[1:]]
            return self.eval(body, dict(zip(params, vals)))
        raise InterpError("outside the DDC subset: %r" % (head,))

    @staticmethod
    def is_int(v):
        return isinstance(v, int) and not isinstance(v, bool)


def main(path):
    try:
        with open(path, encoding="utf-8") as f:
            src = f.read()
        sys.exit(Interp(parse(tokenize(src))).run())
    except InterpError as ex:
        print("ddc-interp: %s: %s" % (path, ex), file=sys.stderr)
        sys.exit(3)
    except RecursionError:
        print("ddc-interp: %s: recursion past the subset limit" % path, file=sys.stderr)
        sys.exit(3)


if __name__ == "__main__":
    if len(sys.argv) != 2:
        print("usage: ddc-interp.py FILE.ax", file=sys.stderr)
        sys.exit(2)
    main(sys.argv[1])
