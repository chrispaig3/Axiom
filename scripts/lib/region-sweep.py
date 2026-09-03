#!/usr/bin/env python3
"""The two-region sweep of docs/memory-model-v2-design.md §5, probe 1,
as a program rather than a number somebody once took.

A function RELATES TWO REGIONS when a store inside it puts a value that
derives from one parameter into a place that derives from another:

    (fn (put v x) (vecPush v x))          v <- x       relates
    (fn (bump c) (set c.n (+ c.n 1)))     c <- Int     does not
    (fn (add t k) (mapInsert t k k))      t <- k       relates

MM-RGN-4 says the common case needs no annotation, and this is the
count of the uncommon case, over every `fn` in the tree. It is a
STRUCTURAL PROXY - it reads S-expressions, not types, so it counts a
store of an `Int` parameter (which has no region) exactly as it counts
a store of a `String` one. The hand audit of 2026-08-31 put the true
figure at 3.5-5.2% against the proxy's 5.98%; the proxy is what a gate
can hold, and the audit is why its floor is quoted as an upper bound.

Stores are recognised by head: the field write `(set p.f v)`, the raw
`(memSetWord p i v)` / `(__store64 p i v)`, and the container writers
`vecPush`, `vecPushStr`, `vecSet`, `mapInsert`, `mapInsertStr`. A
target DERIVES from a parameter when its root identifier is one; a
value derives from a parameter when any identifier inside it is one.
`let`-bound aliases are followed one level: `(let ((w p)) (vecPush w
x))` relates `p` and `x`.

Usage: region-sweep.py DIR... -> prints `fns=N relating=M pct=P`.
"""
import os, re, sys

STORE_HEADS = {"vecPush": (0, -1), "vecPushStr": (0, -1), "vecSet": (0, -1),
               "mapInsert": (0, -1), "mapInsertStr": (0, -1),
               "memSetWord": (0, -1), "__store64": (0, -1)}

TOKEN = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'|[()\[\]{}]|[^\s()\[\]{}"\']+')


def strip_comments(src):
    out = []
    for line in src.split("\n"):
        i = 0
        instr = False
        res = []
        while i < len(line):
            c = line[i]
            if instr:
                res.append(c)
                if c == "\\":
                    if i + 1 < len(line):
                        res.append(line[i + 1])
                    i += 2
                    continue
                if c == '"':
                    instr = False
            elif c == '"':
                instr = True
                res.append(c)
            elif c == ";":
                break
            else:
                res.append(c)
            i += 1
        out.append("".join(res))
    return "\n".join(out)


def parse(src):
    """A minimal S-expression reader: strings become atoms, braces and
    brackets read as lists like parens."""
    toks = TOKEN.findall(strip_comments(src))
    stack = [[]]
    for t in toks:
        if t in "([{":
            stack.append([])
        elif t in ")]}":
            if len(stack) == 1:
                continue
            l = stack.pop()
            stack[-1].append(l)
        else:
            stack[-1].append(t)
    while len(stack) > 1:
        l = stack.pop()
        stack[-1].append(l)
    return stack[0]


def idents(x, acc):
    if isinstance(x, list):
        for y in x:
            idents(y, acc)
    elif isinstance(x, str) and not x.startswith('"') and not x.startswith("'"):
        acc.add(x)
    return acc


def root_param(x, params, aliases):
    """The parameter a place-expression's root names, or None."""
    while isinstance(x, list) and x:
        x = x[0] if isinstance(x[0], list) else x[0]
        break
    if isinstance(x, str):
        base = x.split(".")[0]
        base = aliases.get(base, base)
        if base in params:
            return base
    return None


def relates(body, params):
    aliases = {}
    found = [False]

    def walk(x):
        if not isinstance(x, list) or not x:
            return
        h = x[0]
        if h == "let" and len(x) >= 2 and isinstance(x[1], list):
            for b in x[1]:
                if isinstance(b, list) and len(b) == 2 and isinstance(b[0], str) and isinstance(b[1], str):
                    base = b[1].split(".")[0]
                    if base in params:
                        aliases[b[0]] = base
                if isinstance(b, list) and len(b) == 3 and b[0] == "mut" and isinstance(b[2], str):
                    base = b[2].split(".")[0]
                    if base in params:
                        aliases[b[1]] = base
        if h == "set" and len(x) == 3 and isinstance(x[1], str) and "." in x[1]:
            tgt = aliases.get(x[1].split(".")[0], x[1].split(".")[0])
            if tgt in params:
                vals = {aliases.get(i, i) for i in idents(x[2], set())}
                if any(v in params and v != tgt for v in vals):
                    found[0] = True
        if isinstance(h, str) and h in STORE_HEADS and len(x) >= 3:
            tgt = root_param(x[1], params, aliases)
            if tgt is not None:
                vals = {aliases.get(i, i) for i in idents(x[-1], set())}
                if any(v in params and v != tgt for v in vals):
                    found[0] = True
        for y in x:
            walk(y)

    walk(body)
    return found[0]


def main(dirs):
    fns = 0
    rel = 0
    for d in dirs:
        for root, _, files in os.walk(d):
            if "node_modules" in root or "/target" in root:
                continue
            for f in files:
                if not f.endswith(".ax"):
                    continue
                try:
                    src = open(os.path.join(root, f), encoding="utf-8", errors="replace").read()
                except OSError:
                    continue
                for form in parse(src):
                    if not isinstance(form, list) or not form:
                        continue
                    if form[0] == "pub" and len(form) > 1:
                        form = form[1:]
                    if form[0] not in ("fn", "define") or len(form) < 3:
                        continue
                    head = form[1]
                    if not isinstance(head, list) or not head:
                        continue
                    params = set(p for p in head[1:] if isinstance(p, str))
                    fns += 1
                    if len(params) >= 2 and relates(form[2:], params):
                        rel += 1
    pct = (100.0 * rel / fns) if fns else 0.0
    print("fns=%d relating=%d pct=%.2f" % (fns, rel, pct))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:] or ["."]))
