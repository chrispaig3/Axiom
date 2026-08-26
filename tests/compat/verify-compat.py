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
# Everything AXSYM emits that a CALLER can depend on. Measured over the
# whole surface rather than guessed: the keys that appear are
# `#effects=`, `#effect=`, `#effects-overapprox`, `#effect-params=`,
# `#of=`, `#fields=`, `#effects-incomplete`, `#ctors=` and `#methods=`.
#
# `#fields=` and `#methods=` are here because leaving them out was a
# hole: a struct row without them is `"struct Error"` and nothing else,
# so reordering `Error`'s fields, changing one's type, or deleting a
# trait method all read as NO DIFFERENCE. Field ORDER is contract in
# this language - a `struct` is positional and `cast` reinterprets a
# block - which is the miscompile `AX3044` was built for, one module
# along.
#
# Three keys are deliberately out. `#effect=` is the author's AXTAG
# re-emitted, and since 0.3.0 `AX3010` refuses a claim the body does
# not perform - so it is a subset of `#effects=` and carrying it would
# report a tag added over an unchanged body as a breaking change.
# `#effects-overapprox` and `#effects-incomplete` are states of the
# ANALYSIS, not promises to a caller.
CONTRACT_META = ("#effects=", "#ctors=", "#of=", "#effect-params=",
                 "#fields=", "#methods=")

# Carried in the row so the baseline RECORDS it, and stripped by
# `contract()` so it is not compared.
#
# `;@axiom:deprecated(...)` is how a name is retired gracefully: it
# needs no compiler change - the AXTAG key namespace is open, unknown
# keys already parse, are recorded and are re-emitted on the AXSYM line
# as `#deprecated=`. What it gives this gate is the one thing a
# removal rule needs: evidence that the name was marked BEFORE the
# release that removes it, which is exactly what "the baseline carried
# it" means.
#
# It must not be contract. If it were, ADDING a deprecation notice
# would read as a signature change and be refused as breaking - which
# would make the graceful path the forbidden one.
ANNOTATION_META = ("#deprecated=",)

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
        # Metadata is split on the ` #` that starts each key, NOT on
        # whitespace: a value can contain spaces. `#methods=` carries a
        # method's TYPE, so `show:(a -> String)` tokenises into three
        # words and a whitespace split silently truncates it to
        # `#methods=show:(a` - which compares equal for every change
        # after the first token.
        nid = next((t for t in rest.split() if t.startswith("@")), "-")
        found = [m.strip() for m in re.findall(r'#[a-z-]+(?:=[^#]*)?', rest)]
        meta = sorted(m for m in found if m.startswith(CONTRACT_META))
        note = sorted(m for m in found if m.startswith(ANNOTATION_META))
        rows.append(f'{kind} {name} {module} {nid} "{ty}"'
                    + "".join(" " + m for m in meta)
                    + "".join(" " + m for m in note))
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
    """Everything a caller can depend on: the type and the contract
    metadata, with the annotations stripped."""
    tail = row.split(" ", 4)[4]
    for m in re.findall(r'\s#[a-z-]+(?:=\S*)?', tail):
        if m.strip().startswith(ANNOTATION_META):
            tail = tail.replace(m, "")
    return tail


def deprecated(row):
    return any(t.startswith(ANNOTATION_META) for t in row.split())


def effects(text):
    m = re.search(r'#effects=(\S+)', text)
    return set(m.group(1).split(",")) if m else set()


# `RETIRED` is deliberately absent: a name the previous release
# shipped marked `;@axiom:deprecated` was announced, and removing it is
# the notice being honoured rather than a surprise.
BREAKING = ("REMOVED", "CHANGED", "WIDENED")


def compare(base, cur):
    b = {identity(r): r for r in base}
    c = {identity(r): r for r in cur}
    out = []
    for k in sorted(set(b) | set(c)):
        if k not in c:
            # A name the BASELINE already marked deprecated shipped with
            # that notice in a previous release, which is the whole
            # point of the notice. Removing it is not a surprise, and it
            # needs no line in `compat/BREAKING`.
            kind = "RETIRED" if deprecated(b[k]) else "REMOVED"
            out.append((kind, k, contract(b[k]), ""))
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


# --- the sentinel census ------------------------------------------
#
# `docs/error-model.md` sizes the `Result` migration with a `grep`
# proxy over `errno|sentinel|\(- 0 1\)` and tells the reader to
# RECOMPUTE it rather than quote it. Recomputed 2026-08-26 it reads 89
# over 15 files, not the recorded 64 - and roughly sixty of those are
# COMMENT lines. `stdlib/IO.ax` has eleven matches and zero in code.
#
# So a per-file "no file may rise" rule over that proxy would gate
# PROSE, and the migration's own explanatory comments would break it on
# the first commit. R5's rule is to gate the direction before porting
# anything; a gate over the wrong metric is worse than no gate, because
# it reads as coverage.
#
# The unit here is a PUBLIC FUNCTION whose own doc-comment block states
# a sentinel contract - which is the thing the migration actually ports
# and the thing a caller actually depends on. Measured the same day:
# 40 overall, 31 across `IO.ax` and `Sys.ax`, which matches the
# document's own "32 sites" for that slice closely enough to believe
# both.
SENTINEL_PROSE = re.compile(
    r"-errno|answers 0, or|or `-1`|, or -1|negative errno|a negative/errno")


def sentinel_census(root):
    """{module: count of public functions with a sentinel contract}."""
    out = {}
    for m in MODULES:
        path = os.path.join(root, m + ".ax")
        lines = open(path, encoding="utf-8").read().split("\n")
        n = 0
        for i, line in enumerate(lines):
            if not line.startswith("(pub :: "):
                continue
            block, j = [], i - 1
            while j >= 0 and (lines[j].startswith(";") or not lines[j].strip()):
                if lines[j].startswith(";"):
                    block.append(lines[j])
                j -= 1
                if len(block) > 14:
                    break
            if SENTINEL_PROSE.search("\n".join(block)):
                n += 1
        if n:
            out["stdlib/" + m + ".ax"] = n
    return out


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
        if cmd == "sentinels":
            for mod, n in sorted(sentinel_census(argv[4]).items()):
                print(f"{mod} {n}")
            return 0
        if cmd == "modules":
            # Printed rather than duplicated in the gate: a second copy
            # of this list is a second thing to keep in step, and the
            # failure mode of that is silent.
            for m in MODULES:
                print("stdlib/" + m + ".ax")
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
