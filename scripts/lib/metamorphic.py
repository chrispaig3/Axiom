#!/usr/bin/env python3
"""Metamorphic compiler testing: an unused declaration changes nothing.

THE RELATION. Take a program the compiler accepts. Append top-level
functions nobody calls, named like the names programs are full of -
type variables, parameters, pattern binders: `a`, `e`, `k`, `t`, ...
Nothing in the original program refers to them, so nothing the
compiler says about the original program may change:

  R1  `check` answers the same exit status and the same diagnostics;
  R2  `symbols` prints the same row for every original declaration
      (its type, effect row, tags and location);
  R3  `emit-llvm` emits the same body for every original function.

Two variants per program: the added functions NULLARY (`(fn (a) ...)`,
which a bare `a` calls) and UNARY (`(fn (a x) ...)`, which a bare `a`
names as a function value). Each performs IO, so an analysis that
mistakes a local name for one of them imports an effect the original
never had.

WHAT IT FOUND ON ITS FIRST RUN (2026-09-28), all three silent to
every gate then in the battery:
  - the effect walk read `(cast a x)`'s TYPE operand as a reference,
    so an entry file's `a` gave `Vec`'s element readers IO: 136 of 136
    `tests/stdlib/` programs stopped compiling;
  - codegen resolved a nullary function before a parameter, so a
    parameter `k` beside `(fn (k) 100)` compiled as `call @k()`, and
    an entry file's `e` rewrote `Err$errCode`'s parameter: wrong code;
  - the effect walk skipped a named pattern's binders, `{tag = t}`.

THE SECOND RELATION, `reorder`: reversing the order of a program's
top-level declarations changes neither its verdict (R1: the exit
status and the diagnostic codes) nor any declaration's `symbols` row
(R2: type, effect row, tags and NID, with the location dropped).
Imports stay first, and a `::` travels with its `fn`, keeping their
own order, together with the comment and tag lines above each. IR is
not compared: constructor tags, string constants and lambdas are
numbered in declaration order by design, so a reordered program's IR
differs in names that no program can observe. Its first run found two
programs a reordering refuses: an unsigned function called above its
definition, which needs its signature (AN-39, AX3089) and a declaration macro querying a `data` another
macro generates below it (AN-40). They are `--known` divergences: each
must still fail exactly as recorded, so a fix has to update the list.

THE THIRD RELATION, `sigmove`: moving every `::` to just below its
own `fn` changes neither the verdict nor any `symbols` row. A NID used
to hash whichever of a function's two declarations came last, so this
gave the function a new identity (AN-41).

THE FOURTH RELATION, `shadow`: an entry file's function named like a
library function changes nothing any module does. A module can't
import the entry file, so no module's bare reference may reach it.
For each accepted program this takes the module functions its IR
calls (`@Mod$name`), keeps the names its entry file never mentions,
appends `(fn (name) 0)` for each, and applies R1 to R3. Before AN-52
was fixed, an entry file's `strLen` captured `IO`'s call to `Str`'s,
at check time and at run time, and `println` printed nothing.

THE FIFTH RELATION, `fresh`: ten unsigned functions appended, each
drawing on the checker's counter for fresh type variables, change no
verdict and no `symbols` row, with fresh variables compared as
written. The counter runs over the whole module, and `symbols` used to
print its raw numbers, so an unsigned function's row moved when a
function was added below it (AN-37). Rows are compared as written in
every relation now: a row that renumbers is R2.

WHAT IT CANNOT SEE. Only names it adds; only programs the compiler
already accepts (a refused program's free names are exactly the
names this adds - `tests/diagnostics/1009-macro-for-innermost.ax`
rightly changes answer). Equal IR is equal code, but R3 compares
text, so an emitter that renumbers registers for an unrelated reason
would read as a divergence (none does today). Two runtime tables
enumerate every function by design and are excluded by name,
`ENUMERATORS` below; any other difference is reported.

Usage:
  metamorphic.py run --axiom AXC [--jobs N] FILE...
  metamorphic.py reorder --axiom AXC [--jobs N] [--known FILE] FILE...
  metamorphic.py sigmove --axiom AXC [--jobs N] [--known FILE] FILE...
  metamorphic.py shadow --axiom AXC [--jobs N] FILE...
  metamorphic.py fresh --axiom AXC [--jobs N] FILE...
  metamorphic.py selftest
Exit 0 when every accepted program keeps the relation, 1 otherwise.
"""
import concurrent.futures as cf
import os
import re
import subprocess
import sys

NAMES = list("abcdefghijkmnprstuvwxyz")
ENUMERATORS = {"__axiom_bt_name", "__axiom_lineinit"}
DEADLINE = 600

DEF_RE = re.compile(r"^define [^@\n]*@\"?([^\"(\s]+)\"?\(.*?^}", re.M | re.S)


def declared(src):
    names = set(re.findall(r"\(fn \(([a-z][A-Za-z0-9_]*)", src))
    names |= set(re.findall(r"\(fn ([a-z][A-Za-z0-9_]*) ", src))
    names |= set(re.findall(r"^\(:: ([a-z][A-Za-z0-9_]*) ", src, re.M))
    names |= set(re.findall(r"\(e?macro \(([a-z][A-Za-z0-9_]*)", src))
    return names


def addition(names, unary):
    out = ["\n; metamorphic: unused declarations"]
    for n in names:
        if unary:
            out.append(f";@axiom:effect(io)\n(:: {n} (-> Int Int))\n"
                       f"(fn ({n} q) (__syscall3 1 1 0 q))")
        else:
            out.append(f";@axiom:effect(io)\n(:: {n} Int)\n"
                       f"(fn ({n}) (__syscall3 1 1 0 0))")
    return "\n".join(out) + "\n"


def defs(ir):
    return {m.group(1): m.group(0) for m in DEF_RE.finditer(ir)}


def norm_row(line, fname):
    return line.replace(fname, "F")


def rows(out, fname):
    table = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) > 2:
            table[(parts[0], parts[1])] = norm_row(line, fname)
    return table


def run(axiom, args, cwd):
    try:
        p = subprocess.run([axiom, "--diagnostic-format=ai"] + args, cwd=cwd,
                           capture_output=True, text=True, timeout=DEADLINE,
                           errors="replace")
        return p.returncode, p.stdout, p.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "timeout"


def rows_by_place(out, fname):
    """`rows`, keyed by the declaring file too: the shadow relation adds
    a second row with a module row's name, in the entry file."""
    table = {}
    for line in out.splitlines():
        parts = line.split()
        if len(parts) > 2:
            place = parts[2].split(":")[0].replace(fname, "F")
            table[(parts[0], parts[1], place)] = norm_row(line, fname)
    return table


def observe(axiom, fname, cwd):
    c = run(axiom, ["check", fname], cwd)
    s = run(axiom, ["symbols", fname], cwd)
    e = run(axiom, ["emit-llvm", fname], cwd) if c[0] == 0 else (None, "", "")
    return {"check": (c[0], c[2].replace(fname, "F")),
            "rows": rows(s[1], fname),
            "placed": rows_by_place(s[1], fname),
            "defs": defs(e[1]) if e[0] == 0 else None,
            "emit": e[0]}


def compare(base, var):
    probs = []
    if base["check"] != var["check"]:
        probs.append("R1 check %s -> %s" % (base["check"][0], var["check"][0]))
    moved = [k[1] for k, v in base["rows"].items()
             if k in var["rows"] and var["rows"][k] != v]
    lost = [k[1] for k in base["rows"] if k not in var["rows"]]
    if moved or lost:
        probs.append("R2 symbols rows changed: " + ",".join((moved + lost)[:8]))
    if base["defs"] is not None:
        if var["defs"] is None:
            probs.append("R3 emit-llvm failed on the variant")
        else:
            bodies = [k for k, v in base["defs"].items()
                      if k not in ENUMERATORS and var["defs"].get(k) != v]
            if bodies:
                probs.append("R3 IR differs: " + ",".join(bodies[:8]))
    return probs


def one(axiom, path):
    path = os.path.abspath(path)
    cwd, base = os.path.split(path)
    src = open(path, encoding="utf-8", errors="replace").read()
    orig = observe(axiom, base, cwd)
    if orig["check"][0] != 0:
        return path, "refused", []
    # what `symbols` lists is declared, macro-generated names included
    # (`tests/selfhost/372-decl-macro.ax` makes a `p` no scan of its
    # source can see), and so is every name its source scan finds
    taken = declared(src) | {k[1] for k in orig["rows"]}
    names = [n for n in NAMES if n not in taken]
    probs = []
    for unary in (False, True):
        vname = ".metamorphic-%d-%s" % (os.getpid(), base)
        vpath = os.path.join(cwd, vname)
        with open(vpath, "w", encoding="utf-8") as fh:
            fh.write(src + addition(names, unary))
        try:
            var = observe(axiom, vname, cwd)
        finally:
            os.remove(vpath)
        # the variant's own file name in its diagnostics and rows
        var["check"] = (var["check"][0], var["check"][1].replace(vname, "F"))
        var["rows"] = {k: v.replace(vname, "F") for k, v in var["rows"].items()}
        probs += [("unary " if unary else "nullary ") + p for p in compare(orig, var)]
    return path, "diverged" if probs else "kept", probs


# A call to a module's function: `@Mod$name` or `@"Mod.Sub$name"`.
CALLEE_RE = re.compile(r'call [^@\n]*@"?[A-Za-z0-9_.]+\$([a-z][A-Za-z0-9_]*)"?\(')
TOKEN_RE = re.compile(r'[A-Za-z_][A-Za-z0-9_]*')
SHADOW_LIMIT = 12


def shadow_names(src, defs_, taken):
    """The module functions a program's IR calls whose bare names its
    entry file never mentions, sorted, at most SHADOW_LIMIT."""
    callees = set()
    for body in defs_.values():
        callees |= set(CALLEE_RE.findall(body))
    mentioned = set(TOKEN_RE.findall(src))
    return sorted(n for n in callees if n not in mentioned and n not in taken)[:SHADOW_LIMIT]


def shadowing(names):
    out = ["\n; metamorphic: entry-file functions named like library functions"]
    for n in names:
        out.append(f"(:: {n} Int)\n(fn ({n}) 0)")
    return "\n".join(out) + "\n"


def one_shadow(axiom, path):
    path = os.path.abspath(path)
    cwd, base = os.path.split(path)
    src = open(path, encoding="utf-8", errors="replace").read()
    orig = observe(axiom, base, cwd)
    if orig["check"][0] != 0 or orig["defs"] is None:
        return path, "refused", []
    # the entry file's own declarations, generated ones included; the
    # modules' rows are the names this relation is about
    taken = declared(src) | {k[1] for k, v in orig["rows"].items() if " F:" in v}
    names = shadow_names(src, orig["defs"], taken)
    if not names:
        return path, "none", []
    vname = ".shadow-%d-%s" % (os.getpid(), base)
    vpath = os.path.join(cwd, vname)
    with open(vpath, "w", encoding="utf-8") as fh:
        fh.write(src + shadowing(names))
    try:
        var = observe(axiom, vname, cwd)
    finally:
        os.remove(vpath)
    var["check"] = (var["check"][0], var["check"][1].replace(vname, "F"))
    probs = compare(dict(orig, rows=orig["placed"]), dict(var, rows=var["placed"]))
    return path, "diverged" if probs else "kept", ["shadowing %s: %s" % (",".join(names), p) for p in probs]


def cmd_shadow(argv):
    axiom, jobs, files = None, 4, []
    i = 0
    while i < len(argv):
        if argv[i] == "--axiom":
            axiom = argv[i + 1]; i += 2
        elif argv[i] == "--jobs":
            jobs = int(argv[i + 1]); i += 2
        else:
            files.append(argv[i]); i += 1
    if not axiom or not files:
        print(__doc__)
        return 2
    if os.sep in axiom:
        axiom = os.path.abspath(axiom)
    counts = {"refused": 0, "kept": 0, "diverged": 0, "none": 0}
    shadowed = 0
    with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
        for path, verdict, probs in ex.map(lambda f: one_shadow(axiom, f), files):
            counts[verdict] += 1
            rel = os.path.relpath(path)
            if verdict == "diverged":
                print("DIVERGED %s: %s" % (rel, "; ".join(probs)))
    print("shadowed %d files: %d kept the relation, %d diverged, %d called no "
          "library function they don't name, %d refused (not tested)"
          % (len(files), counts["kept"], counts["diverged"], counts["none"], counts["refused"]))
    return 1 if counts["diverged"] else 0


OPEN, CLOSE = '([{', ')]}'


def skip_atom(s, i):
    """Index just past the lexical item at s[i] (not a bracket)."""
    c = s[i]
    if s.startswith('#|', i):
        j = s.find('|#', i + 2)
        return len(s) if j < 0 else j + 2
    if c == '"':
        i += 1
        while i < len(s) and s[i] != '"':
            i += 2 if s[i] == '\\' else 1
        return i + 1
    if c == "'":
        j = i + 2 if i + 1 < len(s) and s[i + 1] == '\\' else i + 1
        return j + 2 if j + 1 < len(s) and s[j + 1] == "'" else i + 1
    if c == ';':
        while i < len(s) and s[i] != '\n':
            i += 1
        return i
    while i < len(s) and not s[i].isspace() and s[i] not in OPEN + CLOSE + '";':
        i += 1
    return i


def form_end(s, i):
    """s[i] opens a bracket: the index just past its match."""
    depth = 0
    while i < len(s):
        c = s[i]
        if c in OPEN:
            depth += 1
            i += 1
        elif c in CLOSE:
            depth -= 1
            i += 1
            if depth == 0:
                return i
        elif c.isspace():
            i += 1
        else:
            i = skip_atom(s, i)
    raise ValueError('unbalanced')


def units(src):
    """Top-level forms, each with the comment and tag lines above it,
    and the text after the last one."""
    i, pend, out = 0, 0, []
    while i < len(src):
        c = src[i]
        if c in OPEN:
            e = form_end(src, i)
            out.append(src[pend:e])
            pend = i = e
        elif c.isspace():
            i += 1
        else:
            i = skip_atom(src, i)
    return out, src[pend:]


UNIT_HEAD = re.compile(r'^\s*(?:(?:;[^\n]*|#\|.*?\|#)\s*)*\((?:pub\s+)?(\S+)\s+\(?([^\s()]+)', re.S)


def reordered(src):
    """The declarations in reverse order: imports first, and a `::`
    grouped with its `fn` in their own order."""
    us, tail = units(src)
    heads = [UNIT_HEAD.match(u) for u in us]
    imports = [u for u, h in zip(us, heads) if h and h.group(1) == 'import']
    groups, placed = [], {}
    for u, h in zip(us, heads):
        if h and h.group(1) == 'import':
            continue
        kind, name = (h.group(1), h.group(2)) if h else (None, None)
        if kind in ('::', 'fn') and name in placed:
            groups[placed[name]] += u
        else:
            if kind in ('::', 'fn'):
                placed[name] = len(groups)
            groups.append(u)
    return ''.join(imports) + ''.join(reversed(groups)) + tail, len(groups)


def sigs_below(src):
    """Every `::` moved to just after its own `fn`, with the comment and
    tag lines above it; everything else stays where it is."""
    us, tail = units(src)
    heads = [UNIT_HEAD.match(u) for u in us]
    fn_at = {}
    for i, h in enumerate(heads):
        if h and h.group(1) == 'fn':
            fn_at[h.group(2)] = i
    moved, after = set(), {}
    for i, h in enumerate(heads):
        if h and h.group(1) == '::' and fn_at.get(h.group(2), -1) > i:
            moved.add(i)
            after.setdefault(fn_at[h.group(2)], []).append(i)
    out = []
    for i, u in enumerate(us):
        if i in moved:
            continue
        out.append(u)
        for j in after.get(i, []):
            sig = us[j]
            out.append(sig if sig.startswith('\n') else '\n' + sig)
    return ''.join(out) + tail, len(moved)


def unsigned_tail(src):
    """Ten unsigned functions appended, each taking fresh variables."""
    taken = declared(src)
    names = ['zz' + c for c in 'abcdefghij' if 'zz' + c not in taken]
    tail = ''.join('\n(fn (%s n)\n  (lambda (a) a))\n' % n for n in names)
    return src.rstrip('\n') + '\n' + tail, 1


TRANSFORMS = {'reorder': reordered, 'sigmove': sigs_below, 'fresh': unsigned_tail}


def verdict_of(check):
    """Exit status and the sorted diagnostic codes: positions move."""
    return check[0], tuple(sorted(re.findall(r'^[EW] (AX\d{4}) ', check[1], re.M)))


def plain_rows(table):
    return {k: re.sub(r'F:\d+:\d+(-\d+(:\d+)?)?', 'LOC', v) for k, v in table.items()}


def one_reorder(axiom, path, transform=reordered):
    path = os.path.abspath(path)
    cwd, base = os.path.split(path)
    src = open(path, encoding='utf-8', errors='replace').read()
    orig = run(axiom, ['check', base], cwd)
    if orig[0] != 0:
        return path, 'refused', ''
    try:
        text, ngroups = transform(src)
    except ValueError:
        return path, 'unparsed', ''
    if ngroups < (2 if transform is reordered else 1):
        return path, 'single', ''
    vname = '.reorder-%d-%s' % (os.getpid(), base)
    vpath = os.path.join(cwd, vname)
    with open(vpath, 'w', encoding='utf-8') as fh:
        fh.write(text)
    try:
        var = run(axiom, ['check', vname], cwd)
        s0 = run(axiom, ['symbols', base], cwd)
        s1 = run(axiom, ['symbols', vname], cwd)
    finally:
        os.remove(vpath)
    probs = []
    v0 = verdict_of((orig[0], orig[2]))
    v1 = verdict_of((var[0], var[2]))
    if v0 != v1:
        probs.append('R1 ' + (' '.join(v1[1]) or 'exit %d' % v1[0]))
    r0, r1 = plain_rows(rows(s0[1], base)), plain_rows(rows(s1[1], vname))
    moved = sorted(k[1] for k in r0 if r1.get(k) != r0[k])
    if moved and not probs:
        probs.append('R2 ' + ','.join(moved))
    return path, 'diverged' if probs else 'kept', '; '.join(probs)


def cmd_reorder(argv, transform=reordered):
    axiom, jobs, known_file, files = None, 4, None, []
    i = 0
    while i < len(argv):
        if argv[i] == '--axiom':
            axiom = argv[i + 1]; i += 2
        elif argv[i] == '--jobs':
            jobs = int(argv[i + 1]); i += 2
        elif argv[i] == '--known':
            known_file = argv[i + 1]; i += 2
        else:
            files.append(argv[i]); i += 1
    if not axiom or not files:
        print(__doc__)
        return 2
    if os.sep in axiom:
        axiom = os.path.abspath(axiom)
    known = {}
    if known_file:
        for line in open(known_file, encoding='utf-8'):
            line = line.rstrip('\n')
            if line and not line.startswith('#'):
                p, sig = line.split('\t', 1)
                known[p] = sig
    counts = dict(kept=0, known=0, diverged=0, fixed=0, refused=0, single=0, unparsed=0)
    seen = set()
    with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
        for path, verdict, sig in ex.map(lambda f: one_reorder(axiom, f, transform), files):
            rel = os.path.relpath(path)
            seen.add(rel)
            if rel in known:
                if verdict == 'diverged' and sig == known[rel]:
                    counts['known'] += 1
                    print('XFAIL %s: %s (as recorded)' % (rel, sig))
                else:
                    counts['fixed'] += 1
                    print('FIXED? %s: recorded [%s], now %s [%s] - update the known list' % (rel, known[rel], verdict, sig))
                continue
            counts[verdict] += 1
            if verdict == 'diverged':
                print('DIVERGED %s: %s' % (rel, sig))
            elif verdict == 'unparsed':
                print('UNPARSED %s' % rel)
    for p in known:
        if p not in seen:
            counts['fixed'] += 1
            print('MISSING %s: on the known list and not swept' % p)
    print('reordered %d files: %d permuted and kept the relation, %d known divergences held, '
          '%d diverged, %d known entries changed, %d refused, %d with one declaration, %d unparsed'
          % (len(files), counts['kept'], counts['known'], counts['diverged'], counts['fixed'],
             counts['refused'], counts['single'], counts['unparsed']))
    return 1 if counts['diverged'] or counts['fixed'] or counts['unparsed'] else 0


def cmd_run(argv):
    axiom, jobs, files = None, 4, []
    i = 0
    while i < len(argv):
        if argv[i] == "--axiom":
            axiom = argv[i + 1]; i += 2
        elif argv[i] == "--jobs":
            jobs = int(argv[i + 1]); i += 2
        else:
            files.append(argv[i]); i += 1
    if not axiom or not files:
        print(__doc__)
        return 2
    # each program is compiled from its own directory, so a relative
    # compiler path would name nothing there
    if os.sep in axiom:
        axiom = os.path.abspath(axiom)
    counts = {"refused": 0, "kept": 0, "diverged": 0}
    with cf.ThreadPoolExecutor(max_workers=jobs) as ex:
        for path, verdict, probs in ex.map(lambda f: one(axiom, f), files):
            counts[verdict] += 1
            rel = os.path.relpath(path)
            if verdict == "diverged":
                print("DIVERGED %s: %s" % (rel, "; ".join(probs)))
    print("swept %d files: %d accepted and kept the relation, %d diverged, "
          "%d refused (not tested)" % (len(files), counts["kept"],
                                       counts["diverged"], counts["refused"]))
    return 1 if counts["diverged"] else 0


def cmd_selftest():
    fails = 0

    def expect(cond, what):
        nonlocal fails
        print(("ok   " if cond else "FAIL ") + what)
        fails += 0 if cond else 1

    ir = ("define i64 @f(i64 %x) #0 {\n  ret i64 %x\n}\n"
          "define internal i64 @\"Vec$vecGet\"(i64 %v) #0 {\n  ret i64 0\n}\n"
          "define i64 @__axiom_bt_name(i64 %i) {\n  ret i64 1\n}\n")
    d = defs(ir)
    expect(sorted(d) == ["Vec$vecGet", "__axiom_bt_name", "f"], "defs finds three bodies, quoted names too")
    base = {"check": (0, ""), "rows": {("F", "f"): "F f F:1 \"_t3\""}, "defs": d, "emit": 0}
    same = {"check": (0, ""), "rows": {("F", "f"): "F f F:1 \"_t3\""}, "defs": dict(d), "emit": 0}
    expect(compare(base, same) == [], "an identical variant keeps the relation")
    table = dict(d); table["__axiom_bt_name"] = "define i64 @__axiom_bt_name() {\n}"
    expect(compare(base, dict(same, defs=table)) == [], "an enumerator table may differ")
    body = dict(d); body["f"] = "define i64 @f(i64 %x) #0 {\n  %.t0 = call i64 @k()\n}"
    expect(any("R3" in p for p in compare(base, dict(same, defs=body))), "a changed body is R3")
    expect(any("R1" in p for p in compare(base, dict(same, check=(1, "E AX3042")))), "a changed verdict is R1")
    expect(any("R2" in p for p in compare(base, dict(same, rows={("F", "f"): "F f F:1 \"_t3\" #effects=IO"}))),
           "a changed row is R2")
    expect(any("R2" in p for p in compare(base, dict(same, rows={}))), "a lost row is R2")
    expect(any("R3" in p for p in compare(base, dict(same, defs=None))), "a variant that does not emit is R3")
    expect(norm_row("F f F:1 \"(_t13 -> _t13)\"", "F") != norm_row("F f F:1 \"(_t3 -> _t3)\"", "F"),
           "fresh type variables are compared as written, so a renumbered row is R2")
    fresh_text, _ = unsigned_tail("(fn (main) 0)\n(fn (zzb) 1)\n")
    expect(fresh_text.count("(lambda (a) a)") == 9 and "(fn (zzb n)" not in fresh_text,
           "fresh appends one unsigned function per name the program doesn't declare")
    expect(declared("(fn (k) 1)\n(:: v Int)\n(macro (w) 9)\n(fn e 2)") == {"k", "v", "w", "e"},
           "declared names are skipped, macros included")
    prog = ('(import IO)\n; a note\n;@axiom:effect(io)\n(:: f Int)\n(fn (f) 1)\n'
            '#| block ( |#\n(data D (A))\n(:: g Int)\n(fn (g) (f))\n')
    text, n = reordered(prog)
    us, _ = units(text)
    expect(us[0].strip() == '(import IO)', "reorder keeps imports first")
    expect(n == 3 and text.index('(fn (g)') < text.index('(data D') < text.index('(:: f Int)'),
           "reorder reverses the declarations")
    expect(text.index(';@axiom:effect(io)') < text.index('(:: f Int)') < text.index('(fn (f)'),
           "a tag line and a signature travel with their function")
    expect(sorted(prog.split()) == sorted(text.split()), "reorder is a permutation of the source")
    moved, nsig = sigs_below('(:: f Int)\n(fn (f) 1)\n(:: g Int)\n(fn (g) (f))\n')
    expect(nsig == 2 and moved.index('(fn (f)') < moved.index('(:: f Int)') < moved.index('(fn (g)') < moved.index('(:: g Int)'),
           "sigmove puts each signature just below its function")
    expect(verdict_of((1, 'E AX3004 a:1:1 x "m"\nW AX3037 b:2:2 y "n"')) == (1, ('AX3004', 'AX3037')),
           "a verdict is the exit status and the codes")
    ir2 = ('define i64 @main() {\n  %.t0 = call i64 @"IO$println"(i64 1)\n'
           '  %.t1 = call i64 @"Sys.Platform$sysWrite"(i64 1)\n  %.t2 = call i64 @f(i64 1)\n}\n')
    expect(shadow_names("(fn (main) (println 1))", defs(ir2), set()) == ["sysWrite"],
           "shadow names a called module function the entry file doesn't mention")
    expect(shadowing(["strLen"]).count("(fn (strLen) 0)") == 1, "shadow appends one function per name")
    print("selftest: %d failed" % fails)
    return 1 if fails else 0


if __name__ == "__main__":
    if len(sys.argv) > 1 and sys.argv[1] == "run":
        sys.exit(cmd_run(sys.argv[2:]))
    if len(sys.argv) > 1 and sys.argv[1] == "reorder":
        sys.exit(cmd_reorder(sys.argv[2:]))
    if len(sys.argv) > 1 and sys.argv[1] == "sigmove":
        sys.exit(cmd_reorder(sys.argv[2:], sigs_below))
    if len(sys.argv) > 1 and sys.argv[1] == "fresh":
        sys.exit(cmd_reorder(sys.argv[2:], unsigned_tail))
    if len(sys.argv) > 1 and sys.argv[1] == "shadow":
        sys.exit(cmd_shadow(sys.argv[2:]))
    if len(sys.argv) > 1 and sys.argv[1] == "selftest":
        sys.exit(cmd_selftest())
    print(__doc__)
    sys.exit(2)
