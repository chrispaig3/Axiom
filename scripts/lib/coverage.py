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
object code at one `--opt`, over the inputs run; and, from the same
counters, DECISION (branch-outcome) coverage of the object code. Level 3
splits every critical edge before it instruments, so each successor of
a conditional `br` or a `switch` in the instrumented IR is a block with
a counter of its own: an outcome is hit when that counter is. It is not
MC/DC - conditions inside a decision are the source's, and nothing below
the front end keeps them - a block LLVM removed as dead is not counted
anywhere, and the blocks are those of the optimised IR, so coverage is of
the code that ships at that level, not of source lines.

    coverage.py merge  DIR ACC       OR every DIR/run.*.cnt into ACC, delete them
    coverage.py report DIR ACC BIN   print the report (and --json PATH)
    coverage.py decisions DIR ACC BIN COV.LL [--fn NAME]   decision coverage from the
                                     instrumented IR (--fn: one function's decisions)
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


def fn_starts(d, binary):
    """{function name: index of its first counter} - the pc table lists a
    function's blocks consecutively, entry first, in the order its
    counter array holds them."""
    import bisect
    pcs = load_pcs(d)
    syms = symbols(binary)
    addrs = [a for a, _ in syms]
    main_addr = next(a for a, n in syms if n == 'main')
    starts = {}
    for i, (delta, flags) in enumerate(pcs):
        k = bisect.bisect_right(addrs, main_addr + delta) - 1
        fn = syms[k][1] if k >= 0 else '?'
        if fn not in starts:
            starts[fn] = i
    return starts


GEN = re.compile(r'@__sancov_gen_(?:\.\d+)?(?:, i64 0, i64 (\d+))?\)?')


def ir_decisions(cov_ll):
    """[(function, block, [successor labels], {label: counter index})]
    for every conditional `br` and `switch` in the instrumented IR."""
    out = []
    fn = None
    label = None
    idx = {}
    pending = []
    for line in open(cov_ll):
        if line.startswith('define '):
            m = re.search(r'@("?)([^"(]+)\1\(', line)
            fn = m.group(2) if m else None
            label = 'entry0'
            idx = {}
            pending = []
            continue
        if fn is None:
            continue
        if line.startswith('}'):
            for blk, succ in pending:
                out.append((fn, blk, succ, idx))
            fn = None
            continue
        m = re.match(r'^([A-Za-z0-9_.$"-]+):', line)
        if m:
            label = m.group(1).strip('"')
            continue
        if '__sancov_gen_' in line and 'load i8' in line and label not in idx:
            g = GEN.search(line)
            idx[label] = int(g.group(1)) if g and g.group(1) else 0
            continue
        s = line.strip()
        if s.startswith('br i1 '):
            succ = re.findall(r'label %("?)([^",\s]+)\1', s)
            pending.append((label, [x[1] for x in succ]))
        elif s.startswith('switch '):
            succ = re.findall(r'label %("?)([^",\s\]]+)\1', s)
            seen = []
            for x in succ:
                if x[1] not in seen:
                    seen.append(x[1])
            pending.append((label, seen))
    return out


def decisions(d, acc_path, binary, cov_ll, only_fn=None):
    acc = open(acc_path, 'rb').read()
    starts = fn_starts(d, binary)
    total = hit = full = reached = measured = unmeasured = 0
    groups = {}
    for fn, blk, succ, idx in ir_decisions(cov_ll):
        if fn not in starts or any(x not in idx for x in succ) or blk not in idx:
            unmeasured += 1
            continue
        base = starts[fn]
        outs = [1 if acc[base + idx[x]] else 0 for x in succ]
        if only_fn is not None:
            if fn == only_fn:
                print('decision %s outcomes %s' % (blk, ' '.join(map(str, outs))))
            continue
        measured += 1
        total += len(outs)
        hit += sum(outs)
        full += 1 if all(outs) else 0
        reached += 1 if acc[base + idx[blk]] else 0
        g = groups.setdefault(group_of(fn), [0, 0])
        g[0] += len(outs)
        g[1] += sum(outs)
    if only_fn is not None:
        return None
    print('decisions: %d measured (%d unmeasurable), %d reached; outcomes %d of %d hit (%.1f%%); '
          '%d decisions with every outcome hit (%.1f%%)' % (
              measured, unmeasured, reached, hit, total, 100.0 * hit / max(total, 1),
              full, 100.0 * full / max(measured, 1)))
    for k in sorted(groups, key=lambda k: -groups[k][0])[:12]:
        t, h = groups[k]
        print('  %-20s outcomes %6d/%-6d %5.1f%%' % (k, h, t, 100.0 * h / max(t, 1)))
    return dict(measured=measured, unmeasured=unmeasured, reached=reached,
                outcomes=total, outcomes_hit=hit, full=full)


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
    elif cmd == 'decisions':
        fn = sys.argv[sys.argv.index('--fn') + 1] if '--fn' in sys.argv else None
        decisions(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5], fn)
    elif cmd == 'entered':
        print(entered(sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]))
    else:
        sys.stderr.write(__doc__)
        sys.exit(2)
