#!/usr/bin/env python3
"""A row without `Alloc` names a definition without `axiom_alloc`.

    alloc-rows.py <symbols-ai-stream> <module.ll>

The effect row `axiom symbols` prints for a function is a CLAIM about
its body, and `restrict(no-alloc)` is checked against that claim. The
emitter is the other witness: a definition either contains a
`call i64 @axiom_alloc` or it does not. This holds every function
whose row lacks `Alloc` to a definition with no such call - over the
whole self-compile, so the checker's register-pair mirror
(`self_host/typecheck.ax`, `tcPairFnOK` and its neighbours) is held to
the emitter's predicate (`self_host/codegen.ax`, `pairFnOK`) on every
function the compiler compiles into itself, and not only on a
fixture.

WHICH DEFINITION. A function the emitter gives a `@F$pair` has its
body THERE; `@F` is then a wrapper that boxes, and the box it builds is
charged to the CALLER by the checker (`walkCallHead`'s pair clause),
which is why `@F`'s own `axiom_alloc` is not held against `F`'s row. A
function with no pair variant is its `@F`.

THE DIRECTION. Only "row says no Alloc, body allocates" fails. The
other disagreement - a row carrying `Alloc` for a body that emits
none - is an over-approximation, and the effect walk is allowed those
(`docs/memory-model.md` MM-EXEC-9a states the analysis is a lower
bound in the other direction, never this one).

A row the module does not define - a function nothing reached, a
primitive, an extern - is not a witness and is skipped; the count of
rows actually held is printed so a run that matched nothing cannot
read as a run that found nothing.

Exit 0 when every held row agrees, 1 with the offenders listed, 2 when
the inputs are unreadable or too few rows matched to mean anything.
"""
import re
import sys

ROW_FLOOR = 1000  # the self-compile matches ~3,400; a tenth of that is a broken input


def main(argv):
    if len(argv) != 3:
        sys.exit(__doc__)
    syms, ll = argv[1], argv[2]
    defs = {}
    cur = None
    with open(ll, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r"^define [^@]*@([A-Za-z0-9_$.]+)\(", line)
            if m:
                cur = m.group(1)
                defs[cur] = 0
                continue
            if cur is not None and "call i64 @axiom_alloc" in line:
                defs[cur] += 1
            if line.startswith("}"):
                cur = None
    rows = []
    with open(syms, encoding="utf-8") as fh:
        for line in fh:
            m = re.match(r'^F (\S+) (\S+) "(.*)" @(\S+)(.*)$', line.rstrip("\n"))
            if m:
                rows.append((m.group(1), m.group(2), m.group(5)))
    if not defs or not rows:
        print(f"FATAL: {len(defs)} definitions and {len(rows)} rows read")
        return 2

    def module_of(loc):
        p = loc.split(":")[0]
        p = re.sub(r"^.*?(stdlib|self_host)/", "", p)
        return p[:-3] if p.endswith(".ax") else p

    held = 0
    bad = []
    for name, loc, meta in rows:
        mod = module_of(loc)
        base = mod.split("/")[-1]
        d = None
        for cand in (mod.replace("/", ".") + "$" + name, base + "$" + name, name):
            if cand in defs:
                d = cand
                break
        if d is None:
            continue
        held += 1
        m = re.search(r"#effects=(\S+)", meta)
        effs = m.group(1).split(",") if m else []
        body = d + "$pair" if d + "$pair" in defs else d
        if "Alloc" not in effs and defs[body] > 0:
            bad.append((name, loc, body, defs[body]))
    if held < ROW_FLOOR:
        print(f"FATAL: only {held} rows matched a definition, floor is {ROW_FLOOR}")
        return 2
    print(f"held {held} rows to their definitions, {sum(1 for d in defs if d.endswith('$pair'))} of them pair variants")
    for name, loc, body, n in bad:
        print(f"  {name} ({loc}) has no Alloc in its row, and @{body} calls axiom_alloc {n} time(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
