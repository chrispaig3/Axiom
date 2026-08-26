#!/usr/bin/env python3
"""The public surface of the standard library, as a comparable stream.

WHY THIS EXISTS. `scripts/check-version.sh` proves the version number is
STATED in nineteen places. Nothing proved it was EARNED: every gate in
this repository stayed green while a public name changed type, widened
its effect row, or stopped existing. `CHANGELOG.md`'s 0.2.0
"Compatibility" section named the gap - "a deprecation policy and a
compatibility gate over the symbol stream are the next release's work".

WHY AXSYM IS THE RIGHT SUBSTRATE, measured rather than assumed:

  * the `@nid` is location-independent - the same hash comes back when
    the module is read from a different path;
  * the `@nid` is contract-independent - it did not move when a
    signature went from `(Int -> Int)` to `(Int -> (Int -> Int))`.

So the nid is IDENTITY and the type plus the effect row is the
CONTRACT, and a diff separates "this name is gone" from "this name
changed" without heuristics.

WHAT IS DELIBERATELY DROPPED. `#calls=` is the graph BEHIND the effect
row, not part of the promise - a function may reorganise its callees
freely. `file:line:col` is dropped because a contract does not move when
a declaration moves down its file, and because the path a row carries
comes from module resolution: it reads
`<prefix>/.axiom-bin/../stdlib/Err.ax` and so embeds the compiler's
install location (`docs/agent-harness.md` records this as the
portability hazard it is).

WHAT IS DELIBERATELY KEPT. `Sys/Platform.<target>.ax` folds to one
name. The three platform files declare the same names, and folding them
means the baseline is one file that all three CI legs must agree with -
a stronger claim than the per-name comparison `check-stdlib-api.sh`
already makes, and one that goes red on the leg that disagrees.
"""
import sys, re, os, subprocess

# The modules the surface covers. Named rather than globbed, for the
# reason `scripts/check-stdlib-api.sh` gives: `Sys/Platform` has one
# file per target declaring the same names, so a glob prints it three
# times and the choice of which to carry is a decision worth seeing.
MODULES = ("Agent/Tags Err Ffi Fmt IO Intern Job Json Map Mem Path Pre Rpc Show Str Sys "
           "Sys/Platform.darwin Test Utf8 Vec").split()

# Visibility is not in AXSYM - `symbols` has no `pub` field - so the
# public set is read from the source, with the rule
# `scripts/check-stdlib-api.sh` already uses for the generated
# reference. The two must agree about what "public" means.
PUB = re.compile(r'^\(pub (?::: |macro |data |struct |trait |type )\(?([A-Za-z0-9_!?*+/<>=-]+)')
EFFECT = re.compile(r'^\(effect ([A-Za-z0-9_]+)')
ROW = re.compile(r'^(\S+) (\S+) (\S+) "(.*?)"(.*)$')
CONTRACT_META = ("#effects=", "#ctors=", "#of=", "#effect-params=")

# A stream that stops producing reads as agreement, so it is floored.
# 407 rows on 2026-08-26; the floor is under it with room, and it is a
# floor rather than a count so adding a public name does not fail here.
ROW_FLOOR = 380


class Fatal(Exception):
    """The tree did not compile, or `symbols` answered nothing.

    Kept distinct from every comparison result on purpose. A negative
    probe that BREAKS THE BUILD otherwise satisfies a gate that only
    asks for a non-zero exit - which is how a check comes to pass for
    the wrong reason, the defect this repository produces most.
    """


def public_names(root):
    names = set()
    for m in MODULES:
        path = os.path.join(root, m + ".ax")
        if not os.path.exists(path):
            raise Fatal(f"module named in MODULES is not in the tree: {path}")
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                g = PUB.match(line) or EFFECT.match(line)
                if g:
                    names.add(g.group(1))
    return names


def normalise(text, root, names):
    root = os.path.realpath(root)
    rows = []
    for line in text.split("\n"):
        g = ROW.match(line)
        if not g:
            continue
        kind, name, loc, ty, rest = g.groups()
        if name not in names:
            continue
        if loc == "-":
            module = "-"                      # a compiler builtin has no file
        else:
            real = os.path.realpath(loc.split(":")[0])
            module = ("stdlib/" + os.path.relpath(real, root)
                      if real.startswith(root + os.sep) else real)
            module = re.sub(r'Sys/Platform\.[A-Za-z0-9_-]+\.ax$', 'Sys/Platform.ax', module)
        tokens = rest.split()
        nid = next((t for t in tokens if t.startswith("@")), "-")
        meta = sorted(t for t in tokens if t.startswith(CONTRACT_META))
        rows.append(f'{kind} {name} {module} {nid} "{ty}"' + "".join(" " + m for m in meta))
    return sorted(set(rows))


def surface(root, axiom, work):
    """The current public surface, as normalised rows."""
    entry = os.path.join(work, "surface-entry.ax")
    with open(entry, "w", encoding="utf-8") as fh:
        for m in MODULES:
            fh.write("(import %s)\n" % m.replace("/", ".").replace(".darwin", ""))
        fh.write("(fn (main) 0)\n")
    env = dict(os.environ, AXIOM_STDLIB=root)
    r = subprocess.run([axiom, "symbols", "--diagnostic-format=ai", entry],
                       capture_output=True, env=env, cwd=work)
    if r.returncode != 0:
        # `symbols` folds every failure into exit 1 and prints no table
        # (CHANGELOG.md, 0.3.0). An empty stream must never read as
        # "every symbol was removed".
        raise Fatal("symbols exited %d: %s"
                    % (r.returncode, r.stderr.decode("utf-8", "replace").strip()[:300]))
    rows = normalise(r.stdout.decode("utf-8", "replace"), root, public_names(root))
    if len(rows) < ROW_FLOOR:
        raise Fatal(f"the surface is {len(rows)} rows, floor is {ROW_FLOOR}")
    return rows


def identity(row):
    f = row.split()
    return (f[0], f[1])          # kind and name; builtins carry no nid


def contract(row):
    return row.split(" ", 4)[4]  # '"type"' and the contract metadata


def effects(text):
    m = re.search(r'#effects=(\S+)', text)
    return set(m.group(1).split(",")) if m else set()


BREAKING = ("REMOVED", "CHANGED", "WIDENED")


def compare(base, cur):
    b = {identity(r): r for r in base}
    c = {identity(r): r for r in cur}
    out = []
    for k in sorted(set(b) | set(c)):
        if k not in c:
            out.append(("REMOVED", k, contract(b[k]), ""))
        elif k not in b:
            out.append(("ADDED", k, "", contract(c[k])))
        elif contract(b[k]) != contract(c[k]):
            bt, ct = contract(b[k]), contract(c[k])
            be, ce = effects(bt), effects(ct)
            if ce > be:
                kind = "WIDENED"
            elif be > ce:
                kind = "NARROWED"
            else:
                kind = "CHANGED"
            out.append((kind, k, bt, ct))
    return out


def uncovered(root, axiom, work):
    """Public names the symbol stream does not carry.

    `symbols` has no arm for `TAG_D_MACRO` and none for `TAG_D_IMPL`,
    and its `TAG_D_EFFECT` arm registers the effect's OPERATIONS rather
    than the effect. So twelve macros - `println` and `format` among
    them - and one effect declaration are public API that no gate over
    this stream can see.

    That is a hole in the contract, and it is reported as a SET rather
    than a count: a fourteenth invisible name must go red, and the list
    shrinking to nothing is what closing the hole looks like.
    """
    rows = surface(root, axiom, work)
    seen = {r.split()[1] for r in rows}
    return sorted(public_names(root) - seen)


def main(argv):
    if len(argv) < 4:
        sys.exit("usage: verify-compat.py {generate|compare} <axiom> <work> [args]")
    # Resolved before anything chdirs. `surface` runs the compiler with
    # `cwd` set to the work directory, so a relative path handed in from
    # a gate would be resolved against the wrong root - and would fail
    # as a missing file rather than as a wrong answer, which is the
    # better of the two but still not this tool's job to explain.
    cmd = argv[1]
    axiom = os.path.abspath(argv[2])
    work = os.path.abspath(argv[3])
    argv = argv[:4] + [os.path.abspath(a) for a in argv[4:]]
    try:
        if cmd == "generate":
            for row in surface(argv[4], axiom, work):
                print(row)
            return 0
        if cmd == "uncovered":
            for name in uncovered(argv[4], axiom, work):
                print(name)
            return 0
        if cmd != "compare":
            sys.exit(f"unknown command {cmd!r}")
        with open(argv[4], encoding="utf-8") as fh:
            base = [l.rstrip("\n") for l in fh if l.strip()]
        if len(base) < ROW_FLOOR:
            raise Fatal(f"the baseline is {len(base)} rows, floor is {ROW_FLOOR}")
        cur = surface(argv[5], axiom, work)
    except Fatal as e:
        # Printed with this prefix and this exit status so the gate can
        # tell "the tree does not compile" from "the API changed". They
        # are different failures and only one of them is this gate's.
        print(f"FATAL: {e}")
        return 2
    diffs = compare(base, cur)
    breaking = 0
    for kind, (letter, name), was, now in diffs:
        print(f"  {kind} {letter} {name}")
        if was and now:
            print(f"      was: {was}")
            print(f"      now: {now}")
        if kind in BREAKING:
            breaking += 1
    print(f"{len(diffs)} difference(s), {breaking} breaking, over {len(cur)} public rows")
    return 1 if breaking else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
