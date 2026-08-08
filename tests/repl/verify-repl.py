#!/usr/bin/env python3
"""Re-derive the REPL transcripts from the session sources, in another language.

The goldens in this directory are what the compiler printed. That makes them
a record, not a check: regenerate them from a compiler that evaluates
`(+ 1 2)` as 4 and the byte-comparison in scripts/check-repl-selfhost.sh goes
green on `result 4`. Nothing in a golden knows what the answer should be.

This does. It reads the session file's own bytes, tokenizes and evaluates the
subset of Axiom the deterministic sessions use - Int/Bool/Char/String
literals, `+ - *`, the comparisons, `if`, `let`, `fn` and `::` declarations,
calls into them, and undefined-name detection - and predicts the whole
transcript byte for byte: the `OK: <name> defined` line a declaration prints,
the `type : T` and `result V` pair an expression prints, the
``Type error: undefined variable `x` `` line an unbound head prints, `:quit`
stopping without a farewell, and the blank line before `Goodbye!` at EOF.
Then it compares that prediction to the checked-in golden.

A second implementation is not proof of correctness - two implementations can
be wrong together - but it cannot be satisfied by re-blessing, which is the
specific hole a golden leaves. The arithmetic here is Python's.

TWO MODES, because one session is half chatter. Seven of the eight goldens are
pure evaluation and are matched BYTE FOR BYTE against the prediction. The
eighth, 050-commands, mixes evaluation with `:help`'s banner and the REPL's
own error wording - text this model must not transcribe, because transcribing
a compiler's chatter re-derives nothing. It used to be skipped by name, and
skipping it left the largest golden in the bank (858 B of 1708 B) with no
derived half at all: a `:reset` that announced a reset and kept the
declarations was re-blessed into a green gate.

So chatter is modelled as a WINDOW rather than as text. `predict` emits
derived lines and, for each command whose output has no semantics, a chatter
marker. `match_anchored` then requires, of the golden:

  * every derived line present, in order, and consecutive where the model
    says consecutive - including the ones that depend on session state, so
    `:reset` really must drop the definitions before `(f 1)` is an unbound
    name and `:type (+ 1 2)` really must answer Int;
  * each chatter window at least as many lines as the commands that fed it,
    so a command that prints nothing is not silently absorbed;
  * and NO line inside a window that this model accounts for elsewhere -
    a `result`, `type :`, `OK:`, `Type error:` or `Goodbye!` line inside the
    chatter is output the model did not predict, and is a failure rather
    than slack. That is what catches the laundered `:reset`: the golden's
    `type : Int` / `result 1` land inside the reset window.

Sessions using a command this model does not implement (`:load`, `:defs`,
`:llvm`, `:time`) are still SKIPPED BY NAME - and the floors below turn a
model that quietly went blind into a failure rather than a success.

Usage:  python3 tests/repl/verify-repl.py tests/repl
Exit:   0 if every modelled session matches and the floors hold.
"""

import sys
import os
import difflib

MIN_SESSIONS = 8      # every golden in the bank has a derived half
MIN_EXACT = 7         # ... and all but the command session are byte-exact
MIN_CLAIMS = 70       # predicted transcript lines, over all modelled sessions
MIN_ANCHORS = 5       # derived lines inside the anchored (chattering) ones
STEP_BUDGET = 200000  # eval steps per line; a runaway model must not hang

# Lines this model claims to produce itself. One of these inside a chatter
# window means the golden printed evaluation output where the model predicted
# none - the shape a re-blessed wrong compiler takes.
MODELLED_PREFIXES = ("result ", "type : ", "OK: ", "Type error: ")
MODELLED_EXACT = ("Goodbye!",)

# The commands repl.ax dispatches (replMain), by hand. The model needs the
# whole list to tell a command the REPL does not know (one line of chatter,
# predictable) from one this model has not implemented (skip the session).
COMMANDS = {":help", ":h", ":quit", ":q", ":exit", ":type", ":t", ":load",
            ":l", ":reset", ":r", ":defs", ":d", ":llvm", ":time"}

LINE = "line"          # a transcript line this model derived
CHATTER = "chatter"    # one command's output, unpredictable, window-checked


class Unmodelled(Exception):
    """The session uses something this model does not implement."""


class Undefined(Exception):
    def __init__(self, name):
        super().__init__(name)
        self.name = name


class Val:
    __slots__ = ("kind", "v")

    def __init__(self, kind, v):
        self.kind = kind      # Int | Bool | Char | String
        self.v = v

    def type_name(self):
        return self.kind

    def render(self):
        # How the REPL prints a value: the wrapper program prints it and the
        # REPL trims whitespace off both ends of what the program wrote
        # (repl.ax replTrim). Bool is printed by the wrapper as a word.
        if self.kind == "Int":
            return str(self.v)
        if self.kind == "Bool":
            return "true" if self.v else "false"
        if self.kind == "Char":
            return self.v.strip()
        return self.v.strip()


# ---------------------------------------------------------------------
# Reader
# ---------------------------------------------------------------------

DECL_HEADS = {"fn", "define", "::", "pub", "data", "struct",
              "import", "macro", "foreign", "effect", "type", "trait"}


def tokenize(src):
    toks = []
    i, n = 0, len(src)
    while i < n:
        c = src[i]
        if c in " \t\r\n":
            i += 1
            continue
        if c == ";":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if c in "()":
            toks.append((c, None))
            i += 1
            continue
        if c == '"':
            j = i + 1
            buf = []
            while j < n and src[j] != '"':
                if src[j] == "\\":
                    if j + 1 >= n:
                        raise Unmodelled("string ends in a backslash")
                    e = src[j + 1]
                    buf.append({"n": "\n", "t": "\t", "\\": "\\",
                                '"': '"'}.get(e, None))
                    if buf[-1] is None:
                        raise Unmodelled("escape \\%s" % e)
                    j += 2
                    continue
                buf.append(src[j])
                j += 1
            if j >= n:
                raise Unmodelled("unterminated string literal")
            toks.append(("str", "".join(buf)))
            i = j + 1
            continue
        if c == "'":
            if i + 2 < n and src[i + 1] != "\\" and src[i + 2] == "'":
                toks.append(("char", src[i + 1]))
                i += 3
                continue
            if i + 3 < n and src[i + 1] == "\\" and src[i + 3] == "'":
                e = {"n": "\n", "t": "\t", "0": "\0", "\\": "\\",
                     "'": "'"}.get(src[i + 2])
                if e is None:
                    raise Unmodelled("char escape \\%s" % src[i + 2])
                toks.append(("char", e))
                i += 4
                continue
            raise Unmodelled("char literal at byte %d" % i)
        j = i
        while j < n and src[j] not in " \t\r\n()":
            j += 1
        word = src[i:j]
        if word.lstrip("-").isdigit() and word not in ("-",):
            toks.append(("int", int(word)))
        else:
            toks.append(("sym", word))
        i = j
    return toks


def read_form(toks, pos):
    if pos >= len(toks):
        raise Unmodelled("form ends early")
    kind, val = toks[pos]
    if kind == "(":
        items = []
        pos += 1
        while pos < len(toks) and toks[pos][0] != ")":
            item, pos = read_form(toks, pos)
            items.append(item)
        if pos >= len(toks):
            raise Unmodelled("unclosed form")
        return items, pos + 1
    if kind == ")":
        raise Unmodelled("stray close paren")
    return (kind, val), pos + 1


def read_line(line):
    toks = tokenize(line)
    if not toks:
        return None
    form, pos = read_form(toks, 0)
    if pos != len(toks):
        raise Unmodelled("more than one form on a line")
    return form


# ---------------------------------------------------------------------
# Evaluator
# ---------------------------------------------------------------------

def is_sym(node, name=None):
    return isinstance(node, tuple) and node[0] == "sym" and \
        (name is None or node[1] == name)


class Budget:
    def __init__(self):
        self.left = STEP_BUDGET

    def spend(self):
        self.left -= 1
        if self.left <= 0:
            raise Unmodelled("evaluation exceeded %d steps" % STEP_BUDGET)


def ev(node, env, defs, budget):
    budget.spend()
    if isinstance(node, tuple):
        kind, val = node
        if kind == "int":
            return Val("Int", val)
        if kind == "str":
            return Val("String", val)
        if kind == "char":
            return Val("Char", val)
        if val == "true":
            return Val("Bool", True)
        if val == "false":
            return Val("Bool", False)
        if val in env:
            return env[val]
        raise Undefined(val)

    if not node:
        raise Unmodelled("empty form")
    head = node[0]
    if not is_sym(head):
        raise Unmodelled("computed head position")
    op = head[1]

    if op in ("+", "-", "*"):
        if len(node) != 3:
            raise Unmodelled("%s with %d arguments" % (op, len(node) - 1))
        a = ev(node[1], env, defs, budget)
        b = ev(node[2], env, defs, budget)
        if a.kind != "Int" or b.kind != "Int":
            raise Unmodelled("%s on %s/%s" % (op, a.kind, b.kind))
        return Val("Int", {"+": a.v + b.v, "-": a.v - b.v,
                           "*": a.v * b.v}[op])
    if op in ("==", "!=", "<", ">", "<=", ">="):
        if len(node) != 3:
            raise Unmodelled("%s with %d arguments" % (op, len(node) - 1))
        a = ev(node[1], env, defs, budget)
        b = ev(node[2], env, defs, budget)
        if a.kind != b.kind:
            raise Unmodelled("%s across %s and %s" % (op, a.kind, b.kind))
        if op in ("<", ">", "<=", ">=") and a.kind != "Int":
            raise Unmodelled("%s on %s" % (op, a.kind))
        r = {"==": a.v == b.v, "!=": a.v != b.v, "<": a.v < b.v,
             ">": a.v > b.v, "<=": a.v <= b.v, ">=": a.v >= b.v}[op]
        return Val("Bool", r)
    if op == "if":
        if len(node) != 4:
            raise Unmodelled("if with %d arguments" % (len(node) - 1))
        c = ev(node[1], env, defs, budget)
        if c.kind != "Bool":
            raise Unmodelled("if on %s" % c.kind)
        return ev(node[2] if c.v else node[3], env, defs, budget)
    if op == "let":
        if len(node) != 3 or not isinstance(node[1], list):
            raise Unmodelled("let shape")
        inner = dict(env)
        for b in node[1]:
            if not isinstance(b, list) or len(b) != 2 or not is_sym(b[0]):
                raise Unmodelled("let binding shape (mut?)")
            inner[b[0][1]] = ev(b[1], inner, defs, budget)
        return ev(node[2], inner, defs, budget)

    if op in env:
        raise Unmodelled("calling a local binding")
    if op not in defs:
        raise Undefined(op)
    params, body = defs[op]
    if len(params) != len(node) - 1:
        raise Unmodelled("arity mismatch calling %s" % op)
    args = [ev(a, env, defs, budget) for a in node[1:]]
    return ev(body, dict(zip(params, args)), defs, budget)


# ---------------------------------------------------------------------
# Transcript model
# ---------------------------------------------------------------------

def decl_head_word(line):
    """repl.ax declHeadWord: the word right after the opening paren."""
    i = 1
    n = len(line)
    while i < n and line[i] in " \t\r\n":
        i += 1
    start = i
    while i < n and line[i] not in " \t\r\n()":
        i += 1
    return line[start:i]


def predict(session):
    """Answer the transcript the REPL must print for this session's bytes.

    A list of (LINE, text) - derived - and (CHATTER, why) - one command's
    unpredictable output, checked as a window instead of as text.
    """
    out = []
    defs = {}
    for raw in session.split("\n"):
        line = raw.strip()
        if line == "" or line.startswith(";"):
            continue
        if line.startswith(":"):
            word = line.split()[0]
            rest = line[len(word):].strip()
            if word in (":quit", ":q", ":exit"):
                return out            # no farewell on an explicit quit
            if word in (":help", ":h"):
                out.append((CHATTER, "the :help banner"))
                continue
            if word in (":reset", ":r"):
                # The claim is not the announcement, which is chatter. The
                # claim is that everything declared so far is GONE, and the
                # lines predicted after this one say so.
                defs = {}
                out.append((CHATTER, "the :reset announcement"))
                continue
            if word in (":type", ":t"):
                if not rest:
                    out.append((CHATTER, "the :type usage error"))
                    continue
                form = read_line(rest)
                try:
                    v = ev(form, {}, defs, Budget())
                except Undefined:
                    # What the type checker prints for an unbound name under
                    # :type is not modelled here; refuse rather than guess.
                    raise Unmodelled(":type of an unbound name")
                # repl.ax replCmdType: the argument as typed, ` : `, the type.
                out.append((LINE, "%s : %s" % (rest, v.type_name())))
                continue
            if word in COMMANDS:
                raise Unmodelled("command %s" % word)
            out.append((CHATTER, "the unknown-command error for %s" % word))
            continue

        if len(line) >= 2 and line[0] == "(" and \
                decl_head_word(line) in DECL_HEADS:
            form = read_line(line)
            if not isinstance(form, list) or len(form) < 2:
                raise Unmodelled("declaration shape")
            head = form[0][1] if is_sym(form[0]) else None
            if head == "fn":
                sig = form[1]
                if not isinstance(sig, list) or not sig or not is_sym(sig[0]):
                    raise Unmodelled("fn signature shape")
                name = sig[0][1]
                params = []
                for p in sig[1:]:
                    if not is_sym(p):
                        raise Unmodelled("pattern parameter")
                    params.append(p[1])
                if len(form) != 3:
                    raise Unmodelled("fn with %d body forms" % (len(form) - 2))
                defs[name] = (params, form[2])
                out.append((LINE, "OK: %s defined" % name))
            elif head == "::":
                if not is_sym(form[1]):
                    raise Unmodelled(":: shape")
                out.append((LINE, "OK: %s defined" % form[1][1]))
            elif head in ("data", "struct"):
                if not isinstance(form[1], list) or not is_sym(form[1][0]):
                    raise Unmodelled("%s shape" % head)
                out.append((LINE, "OK: data %s defined" % form[1][0][1]))
            else:
                raise Unmodelled("declaration head `%s`" % head)
            continue

        form = read_line(line)
        try:
            v = ev(form, {}, defs, Budget())
        except Undefined as u:
            out.append((LINE, "Type error: undefined variable `%s`" % u.name))
            continue
        out.append((LINE, "type : %s" % v.type_name()))
        out.append((LINE, "result %s" % v.render()))

    out.append((LINE, ""))            # the blank line before the farewell
    out.append((LINE, "Goodbye!"))
    return out


# ---------------------------------------------------------------------
# Matching: byte-exact when nothing is chatter, anchored when something is
# ---------------------------------------------------------------------

def blocks_of(items):
    """Group the prediction into (chatter commands before, run of lines)."""
    blocks = []
    pending = 0
    run = []
    for kind, text in items:
        if kind == CHATTER:
            if run:
                blocks.append((pending, run))
                pending = 0
                run = []
            pending += 1
        else:
            run.append(text)
    blocks.append((pending, run))
    return blocks


def window_problems(window, ncmds, why):
    """What a stretch of unpredicted golden lines is not allowed to be."""
    ps = []
    if len(window) < ncmds:
        ps.append("%d command(s) printed %d line(s) of output (%s)"
                  % (ncmds, len(window), why))
    for l in window:
        if l.startswith(MODELLED_PREFIXES) or l in MODELLED_EXACT:
            ps.append("unpredicted output inside %s: %r - the model accounts "
                      "for lines of this shape and did not predict this one"
                      % (why, l))
    return ps


def find_run(g, start, run):
    """First index >= start where `run` matches consecutively, or None."""
    for i in range(start, len(g) - len(run) + 1):
        if g[i:i + len(run)] == run:
            return i
    return None


def match_anchored(items, golden):
    """Derived lines in order and consecutive; chatter only where licensed."""
    g = golden.split("\n")
    if g and g[-1] == "":
        g.pop()                       # every golden ends in a newline
    why = [t for k, t in items if k == CHATTER]
    problems = []
    gi = 0
    wi = 0
    for ncmds, run in blocks_of(items):
        label = "; ".join(why[wi:wi + ncmds]) if ncmds else ""
        wi += ncmds
        if ncmds == 0:
            if g[gi:gi + len(run)] != run:
                problems.append("the golden does not continue %r at line %d"
                                % (run[0] if run else "", gi + 1))
                return problems
            gi += len(run)
            continue
        if not run:               # trailing chatter: the rest is its window
            problems += window_problems(g[gi:], ncmds, label)
            gi = len(g)
            continue
        at = find_run(g, gi, run)
        if at is None:
            problems += window_problems(g[gi:], ncmds, label)
            problems.append("derived line(s) %r never appear after %s"
                            % (run[0], label))
            return problems
        problems += window_problems(g[gi:at], ncmds, label)
        gi = at + len(run)
    if gi != len(g):
        problems.append("%d golden line(s) after the transcript ends: %r"
                        % (len(g) - gi, g[gi:gi + 3]))
    return problems


# ---------------------------------------------------------------------
# Driver
# ---------------------------------------------------------------------

def main(argv):
    d = argv[1] if len(argv) > 1 else "tests/repl"
    names = sorted(f[:-4] for f in os.listdir(d) if f.endswith(".txt"))
    if not names:
        print("FAIL: no sessions in %s" % d)
        return 1

    modelled = 0
    exact = 0
    claims = 0
    anchors = 0
    bad = 0
    for name in names:
        golden_path = os.path.join(d, name + ".golden")
        if not os.path.exists(golden_path):
            continue                  # marker-gated session, nothing to model
        with open(os.path.join(d, name + ".txt")) as fh:
            session = fh.read()
        with open(golden_path) as fh:
            golden = fh.read()
        try:
            items = predict(session)
        except Unmodelled as why:
            print("skip %-20s not modelled: %s" % (name, why))
            continue
        derived = [t for k, t in items if k == LINE]
        windows = sum(1 for k, _ in items if k == CHATTER)
        modelled += 1
        claims += len(derived)

        if not windows:
            exact += 1
            expect = "".join(l + "\n" for l in derived)
            if expect != golden:
                bad += 1
                print("FAIL %-20s the golden is not what the session "
                      "evaluates to" % name)
                for dl in list(difflib.unified_diff(
                        expect.splitlines(True), golden.splitlines(True),
                        fromfile="derived", tofile=golden_path))[:14]:
                    sys.stdout.write("     " + dl)
            else:
                print("ok   %-20s %2d transcript lines re-derived" %
                      (name, len(derived)))
            continue

        anchors += len(derived)
        problems = match_anchored(items, golden)
        if problems:
            bad += 1
            print("FAIL %-20s the golden is not what the session evaluates "
                  "to, around %d window(s) of command chatter" % (name, windows))
            for p in problems[:8]:
                print("     " + p)
        else:
            print("anch %-20s %2d derived line(s) pinned across %d chatter "
                  "window(s)" % (name, len(derived), windows))

    if modelled < MIN_SESSIONS:
        print("FAIL: modelled %d sessions; the floor is %d - the model went "
              "blind or the bank shrank" % (modelled, MIN_SESSIONS))
        bad += 1
    if exact < MIN_EXACT:
        print("FAIL: only %d sessions matched byte for byte; the floor is %d "
              "- chatter windows are the weaker check and must stay the "
              "exception" % (exact, MIN_EXACT))
        bad += 1
    if claims < MIN_CLAIMS:
        print("FAIL: %d transcript lines re-derived; the floor is %d"
              % (claims, MIN_CLAIMS))
        bad += 1
    if anchors < MIN_ANCHORS:
        print("FAIL: %d derived line(s) inside the chattering sessions; the "
              "floor is %d - the command surface lost its derived half"
              % (anchors, MIN_ANCHORS))
        bad += 1

    print("verify-repl: %d sessions (%d byte-exact), %d lines re-derived "
          "(%d anchored), %d mismatched"
          % (modelled, exact, claims, anchors, bad))
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
