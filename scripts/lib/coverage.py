#!/usr/bin/env python3
"""Merge and report object-code block coverage (`scripts/measure-coverage.sh`).

WHAT IS MEASURED. SanitizerCoverage (`opt -passes=sancov-module
-sanitizer-coverage-level=3 -sanitizer-coverage-inline-8bit-counters
-sanitizer-coverage-pc-table`) gives every basic block of the optimised
IR an 8-bit counter and a table entry holding the block's address and a
flag (1 = the function's entry block). `scripts/lib/axcov.c` moves the
counters onto a file per run, so a run that ends in a trap's raw exit
syscall is recorded like one that returns. This module ORs the runs of
ONE binary together and attributes each block to the function whose
symbol precedes its address.

WHAT IT IS, IN A STANDARD'S WORDS: block (statement-level) coverage of
object code at one `--opt`, over the inputs run. It is not decision
coverage and not MC/DC; a block LLVM removed as dead is not counted
anywhere; and the blocks are those of the optimised IR, so coverage is
of the code that ships at that level, not of source lines.

    coverage.py merge  DIR ACC       OR every DIR/run.*.cnt into ACC, delete them
    coverage.py report DIR ACC BIN   print the report (and --json PATH)
"""

import glob
import json
import os
import re
import subprocess
import sys


def load_pcs(d):
    rows = []
    for line in open(os.path.join(d, 'pcs')):
        a, b = line.split()
        rows.append((int(a), int(b)))
    return rows


def merge(d, acc_path):
    pcs = load_pcs(d)
    n = len(pcs)
    acc = bytearray(open(acc_path, 'rb').read()) if os.path.exists(acc_path) else bytearray(n)
    if len(acc) != n:
        raise SystemExit('coverage: %s holds %d counters, the pcs table %d' % (acc_path, len(acc), n))
    runs = 0
    for meta in sorted(glob.glob(os.path.join(d, 'run.*.meta'))):
        off, m = map(int, open(meta).read().split())
        if m != n:
            raise SystemExit('coverage: %s names %d counters, the pcs table %d - two binaries in one directory' % (meta, m, n))
        cnt = meta[:-5] + '.cnt'
        data = open(cnt, 'rb').read()[off:off + n]
        if len(data) != n:
            raise SystemExit('coverage: %s is short' % cnt)
        for i, x in enumerate(data):
            if x:
                acc[i] = 1
        os.unlink(meta)
        os.unlink(cnt)
        runs += 1
    # A counter file with no meta is a run that died before writing it.
    stray = glob.glob(os.path.join(d, 'run.*.cnt'))
    open(acc_path, 'wb').write(bytes(acc))
    return runs, len(stray)


def symbols(binary):
    """(address, name) of every text symbol, sorted; the leading
    underscore Mach-O adds is removed."""
    out = subprocess.run(['nm', '-n', binary], capture_output=True, text=True).stdout
    syms = []
    for line in out.splitlines():
        parts = line.split(None, 2)
        if len(parts) != 3 or parts[1] not in ('T', 't'):
            continue
        name = parts[2]
        if sys.platform == 'darwin' and name.startswith('_'):
            name = name[1:]
        syms.append((int(parts[0], 16), name))
    syms.sort()
    return syms


def group_of(name):
    if name.startswith('axiom_') or name.startswith('__axiom') or name in ('main', '_start'):
        return 'runtime'
    if '$' in name:
        return name.split('$', 1)[0]
    return '(root module)'


def report(d, acc_path, binary, json_path=None):
    pcs = load_pcs(d)
    acc = open(acc_path, 'rb').read()
    syms = symbols(binary)
    main_addr = next((a for a, n in syms if n == 'main'), None)
    if main_addr is None:
        raise SystemExit('coverage: no `main` symbol in %s' % binary)
    addrs = [a for a, _ in syms]
    import bisect
    per_fn = {}
    for i, (delta, flags) in enumerate(pcs):
        a = main_addr + delta
        k = bisect.bisect_right(addrs, a) - 1
        fn = syms[k][1] if k >= 0 else '?'
        e = per_fn.setdefault(fn, [0, 0, False, False])
        e[0] += 1
        e[1] += 1 if acc[i] else 0
        if flags & 1:
            e[2] = True
            e[3] = e[3] or bool(acc[i])
    groups = {}
    for fn, (blocks, hit, has_entry, entered) in per_fn.items():
        g = groups.setdefault(group_of(fn), [0, 0, 0, 0])
        g[0] += blocks
        g[1] += hit
        g[2] += 1
        g[3] += 1 if (entered or hit) else 0
    total = sum(g[0] for g in groups.values())
    hit = sum(g[1] for g in groups.values())
    nfn = sum(g[2] for g in groups.values())
    nent = sum(g[3] for g in groups.values())
    out = {'blocks': total, 'blocks_hit': hit, 'functions': nfn, 'functions_entered': nent,
           'groups': {k: dict(blocks=v[0], hit=v[1], functions=v[2], entered=v[3]) for k, v in groups.items()},
           'never_entered': sorted(fn for fn, e in per_fn.items() if e[1] == 0)}
    print('blocks: %d of %d hit (%.1f%%); functions: %d of %d entered (%.1f%%)' % (
        hit, total, 100.0 * hit / max(total, 1), nent, nfn, 100.0 * nent / max(nfn, 1)))
    for k in sorted(groups, key=lambda k: -groups[k][0]):
        b, h, f, e = groups[k]
        print('  %-20s blocks %6d/%-6d %5.1f%%   functions %4d/%-4d' % (k, h, b, 100.0 * h / max(b, 1), e, f))
    if json_path:
        json.dump(out, open(json_path, 'w'), indent=1, sort_keys=True)
    return out


def entered(d, acc_path, binary, fn):
    """1 if `fn`'s entry block was hit, 0 if not, -1 if the binary has
    no instrumented entry block attributed to `fn`."""
    import bisect
    pcs = load_pcs(d)
    acc = open(acc_path, 'rb').read()
    syms = symbols(binary)
    addrs = [a for a, _ in syms]
    main_addr = next(a for a, n in syms if n == 'main')
    for i, (delta, flags) in enumerate(pcs):
        if not flags & 1:
            continue
        k = bisect.bisect_right(addrs, main_addr + delta) - 1
        if k >= 0 and syms[k][1] == fn:
            return 1 if acc[i] else 0
    return -1


if __name__ == '__main__':
    cmd = sys.argv[1] if len(sys.argv) > 1 else ''
    if cmd == 'merge':
        runs, stray = merge(sys.argv[2], sys.argv[3])
        print('%d runs merged, %d unfinished' % (runs, stray))
    elif cmd == 'report':
        jp = sys.argv[sys.argv.index('--json') + 1] if '--json' in sys.argv else None
        report(sys.argv[2], sys.argv[3], sys.argv[4], jp)
    elif cmd == 'entered':
        print(entered(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]))
    else:
        sys.stderr.write(__doc__)
        sys.exit(2)
