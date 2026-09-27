#!/usr/bin/env python3
"""Which gate scripts a GitHub workflow actually RUNS, read structurally.

Used by `scripts/check-ci-coverage.sh`. It answers one question per gate:
is there a step that invokes `scripts/check-<name>.sh` in a way whose
failure fails the workflow? A MENTION is not that. Until 2026-09-26 the
gate answered it by stripping comments and grepping the whole file, and
an audit turned the real `check-scope-equiv.sh` invocation into
`echo ./scripts/check-scope-equiv.sh` in a copy of `ci.yml`: the gate
still said every script was run. A step's `name:`, an `echo`, a step
behind `if: false`, a job nothing can start, `continue-on-error: true`
and a trailing `|| true` are all mentions of the same kind.

So the workflow is read as a structure - jobs, their steps, each step's
`run`, `if`, `continue-on-error` and `shell` - and a gate counts as run
only when ALL of these hold:

  - it is invoked in a step's own `run:` (an action's `with: run:` is
    that action's business and is not read);
  - the invocation is a whole command line of the deliberately narrow
    form `[VAR=value ...] ./scripts/check-<name>.sh [plain args]`, with
    no `|`, `;`, `&`, `&&` or `||` on it, and the line before it does
    not continue onto it with `\\`;
  - the `run` script it sits in is straight-line: no `if`/`for`/`while`/
    `case`/function syntax, no heredoc, no `set +e`, no `exit` - any of
    which can make a line unreachable or its status irrelevant;
  - the step's `shell` is the default or `bash`, both of which GitHub
    runs with `-e`, so a failing line fails the step;
  - neither the step nor its job is disabled by a condition that is
    literally false, and no job it `needs` is disabled either;
  - neither the step nor its job has a `continue-on-error` that is
    anything but literally false.

A condition that is not literally false (a platform, a schedule, a
changed-path output) is REPORTED alongside the invocation rather than
refused: the workflow is built out of those, and "runs on the nightly
only" is a decision the gate should show, not overrule.

Output, one tab-separated record per line:

  RUN     <gate> <job> <step> <condition or ->
  REFUSED <gate> <job> <step> <why the mention does not count>

This is a reader for the YAML GitHub workflows are written in -
block mappings, block sequences, `|`/`>` block scalars, plain, quoted
and flow (`[a, b]`) scalars, comments - and not a general YAML parser.
It fails loudly (exit 2) on a shape it cannot read rather than guess.
"""

import re
import sys


class Unreadable(Exception):
    pass


def indent_of(line):
    return len(line) - len(line.lstrip(" "))


def strip_comment(v):
    """A plain scalar's value without a trailing ` #...` comment."""
    out, q = [], None
    for i, c in enumerate(v):
        if q:
            if c == q:
                q = None
        elif c in "'\"" and (i == 0 or v[i - 1] in " [,:"):
            q = c
        elif c == "#" and (i == 0 or v[i - 1] in " \t"):
            break
        out.append(c)
    return "".join(out).rstrip()


def unquote(v):
    v = v.strip()
    if len(v) >= 2 and v[0] == v[-1] and v[0] in "'\"":
        return v[1:-1]
    return v


class Reader:
    def __init__(self, text):
        self.lines = text.split("\n")
        self.i = 0

    def skip(self):
        while self.i < len(self.lines):
            s = self.lines[self.i].strip()
            if s == "" or s.startswith("#"):
                self.i += 1
            else:
                return

    def eof(self):
        self.skip()
        return self.i >= len(self.lines)

    def node(self, ind):
        """The node whose first line is the next one, at indentation `ind`."""
        if self.eof():
            return None
        line = self.lines[self.i]
        if indent_of(line) < ind:
            return None
        ind = indent_of(line)
        s = line[ind:]
        if s == "-" or s.startswith("- "):
            return self.seq(ind)
        return self.mapping(ind)

    def seq(self, ind):
        items = []
        while not self.eof():
            line = self.lines[self.i]
            s = line[indent_of(line):]
            if indent_of(line) != ind or not (s == "-" or s.startswith("- ")):
                break
            rest = s[1:].lstrip(" ")
            if rest == "" or rest.startswith("#"):
                self.i += 1
                items.append(self.node(ind + 1))
                continue
            # The item's content starts on the dash's line: re-read that
            # line as if the dash were spaces, at the column it begins.
            col = ind + (len(s) - len(rest))
            self.lines[self.i] = " " * col + rest
            if re.match(r"""^(?:"[^"]*"|'[^']*'|[^\s#'"][^#]*?):(?:\s|$)""", rest):
                items.append(self.mapping(col))
            else:
                self.i += 1
                items.append(unquote(strip_comment(rest)))
        return items

    def mapping(self, ind):
        d = {}
        while not self.eof():
            line = self.lines[self.i]
            if indent_of(line) != ind:
                if indent_of(line) > ind:
                    raise Unreadable(f"line {self.i + 1}: unexpected indentation")
                break
            s = line[ind:]
            if s == "-" or s.startswith("- "):
                break
            m = re.match(r"""^("[^"]*"|'[^']*'|[^\s#'"][^:]*?):(?:\s+(.*))?$""", s)
            if not m:
                raise Unreadable(f"line {self.i + 1}: not a `key: value` line: {s!r}")
            key = unquote(m.group(1))
            raw = strip_comment(m.group(2) or "")
            self.i += 1
            if re.fullmatch(r"[|>][+-]?[0-9]?", raw):
                d[key] = self.block_scalar(ind, raw[0] == ">")
            elif raw == "":
                if self.eof():
                    d[key] = None
                    continue
                nxt = self.lines[self.i]
                ns = nxt[indent_of(nxt):]
                if indent_of(nxt) > ind or (
                    indent_of(nxt) == ind and (ns == "-" or ns.startswith("- "))
                ):
                    d[key] = self.node(indent_of(nxt))
                else:
                    d[key] = None
            else:
                d[key] = self.flow(raw, ind)
        return d

    def block_scalar(self, ind, folded):
        body = []
        while self.i < len(self.lines):
            line = self.lines[self.i]
            if line.strip() == "":
                body.append("")
                self.i += 1
                continue
            if indent_of(line) <= ind:
                break
            body.append(line)
            self.i += 1
        while body and body[-1] == "":
            body.pop()
        if not body:
            return ""
        col = min(indent_of(b) for b in body if b)
        body = [b[col:] for b in body]
        return " ".join(b.strip() for b in body if b) if folded else "\n".join(body)

    def flow(self, raw, ind):
        # A plain scalar may continue on more-indented lines.
        while self.i < len(self.lines):
            line = self.lines[self.i]
            if line.strip() == "" or indent_of(line) <= ind:
                break
            raw += " " + strip_comment(line.strip())
            self.i += 1
        if raw.startswith("[") and raw.endswith("]"):
            return [unquote(x) for x in raw[1:-1].split(",") if x.strip()]
        return unquote(raw)


def literally_false(v):
    if v is None:
        return False
    s = str(v).strip()
    m = re.fullmatch(r"\$\{\{\s*(.*?)\s*\}\}", s)
    if m:
        s = m.group(1)
    return s in ("false", "0", "''", '""', "")


def continues_on_error(v):
    """True unless the key is absent or literally false: an expression
    may evaluate true, and then a failure is hidden."""
    if v is None:
        return False
    return not literally_false(v)


GATE = re.compile(r"scripts/(check-[a-z0-9-]+\.sh)")
INVOCATION = re.compile(
    r"""^(?:[A-Za-z_][A-Za-z0-9_]*=(?:"[^"]*"|'[^']*'|[^\s"';&|<>()`]*)\s+)*"""
    r"""(?:bash\s+)?\.?/?scripts/(check-[a-z0-9-]+\.sh)(?:\s+[A-Za-z0-9_./=:+-]+)*\s*$"""
)
COMPOUND = re.compile(
    r"""^(?:if|then|else|elif|fi|for|while|until|do|done|case|esac|function|select)\b"""
    r"""|^[{}]\s*$|^[A-Za-z_][A-Za-z0-9_]*\s*\(\)|<<|^set\s+\+e\b|^set\s+-[a-zA-Z]*\+|^exit\b|^return\b"""
)


def shell_lines(run):
    """The run script's command lines, comments dropped, each with the
    previous line's trailing backslash recorded."""
    out, cont = [], False
    for raw in run.split("\n"):
        s = raw.strip()
        if s == "" or s.startswith("#"):
            continue
        s = strip_comment(s)
        out.append((s, cont))
        cont = s.endswith("\\")
    return out


def read_steps(run):
    """(invoked gates, [(gate, why) mentions that do not count])."""
    lines = shell_lines(run)
    mentioned = [(g, s) for s, _ in lines for g in GATE.findall(s)]
    if not mentioned:
        return [], []
    blocker = next((s for s, _ in lines if COMPOUND.search(s)), None)
    ran, refused = [], []
    for s, continued in lines:
        for g in GATE.findall(s):
            m = INVOCATION.match(s)
            if blocker is not None:
                refused.append((g, f"the step's script is not straight-line (`{blocker}`)"))
            elif continued:
                refused.append((g, "the line before continues onto it with `\\`"))
            elif not m or m.group(1) != g:
                refused.append((g, f"`{s}` is a mention, not an invocation"))
            else:
                ran.append(g)
    return ran, refused


def main(path):
    doc = Reader(open(path, encoding="utf-8").read()).node(0)
    if not isinstance(doc, dict) or not isinstance(doc.get("jobs"), dict):
        raise Unreadable("no `jobs:` mapping at the top level")
    jobs = doc["jobs"]

    disabled = {}

    def job_disabled(jid, seen=()):
        if jid in disabled:
            return disabled[jid]
        job = jobs.get(jid)
        if not isinstance(job, dict) or jid in seen:
            return True
        needs = job.get("needs") or []
        if isinstance(needs, str):
            needs = [needs]
        d = literally_false(job.get("if")) if "if" in job else False
        d = d or any(job_disabled(n, seen + (jid,)) for n in needs)
        disabled[jid] = d
        return d

    for jid, job in jobs.items():
        if not isinstance(job, dict):
            continue
        steps = job.get("steps") or []
        for k, step in enumerate(steps):
            if not isinstance(step, dict) or not isinstance(step.get("run"), str):
                continue
            label = str(step.get("name") or step.get("id") or f"step {k + 1}")
            label = label.replace("\t", " ")
            ran, refused = read_steps(step["run"])
            why = None
            if job_disabled(jid):
                why = "its job can never start (a literally false `if`, or a `needs` that cannot)"
            elif "if" in step and literally_false(step.get("if")):
                why = "the step's `if` is literally false"
            elif continues_on_error(job.get("continue-on-error")):
                why = "its job has `continue-on-error`, so a failure is hidden"
            elif continues_on_error(step.get("continue-on-error")):
                why = "the step has `continue-on-error`, so a failure is hidden"
            elif step.get("shell") not in (None, "bash"):
                why = f"the step's shell is `{step.get('shell')}`, not bash with -e"
            conds = [str(c) for c in (job.get("if"), step.get("if")) if c is not None]
            cond = " && ".join(" ".join(c.split()) for c in conds) or "-"
            for g in ran:
                if why:
                    print(f"REFUSED\t{g}\t{jid}\t{label}\t{why}")
                else:
                    print(f"RUN\t{g}\t{jid}\t{label}\t{cond}")
            for g, w in refused:
                print(f"REFUSED\t{g}\t{jid}\t{label}\t{w}")


if __name__ == "__main__":
    try:
        main(sys.argv[1])
    except Unreadable as e:
        print(f"ci-steps.py: cannot read {sys.argv[1]}: {e}", file=sys.stderr)
        sys.exit(2)
