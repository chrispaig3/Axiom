#!/usr/bin/env python3
"""Focused Vec growth checks; use an already-built compiler, never install one.

AXIOM=/path/to/compiler python3 scripts/check-vec-growth.py --work /tmp/vec-qa
Add --baseline /path/to/baseline --bench for alternating process measurements.
The raw evidence, emitted IR and commands remain under --work.
"""
import argparse
import json
import os
from pathlib import Path
import platform
import re
import statistics
import subprocess
import sys
import tempfile
import time

ROOT = Path(__file__).resolve().parents[1]
RAW_HELPERS = """
; Raw observations are confined to this unsafe allocator probe.
(:: memGetWord (-> Int Int Int))
;@axiom:effect(unsafe)
(fn (memGetWord p i) (__load64 p i))
(:: memSetWord (-> Int Int Int Int))
;@axiom:effect(unsafe)
(fn (memSetWord p i v) { (__store64 p i v) v })
(:: memAlloc (-> Int Int))
;@axiom:effect(unsafe)
(fn (memAlloc n) (__alloc n))
"""
PROBE = """(import IO)
(import Mem)
(import Vec)
(:: fill (-> (Vec Int) Int Int))
(fn (fill v n) {
  (let mut i (vecLen v))
  (while (< i n) { (vecPush v i) (set i (+ i 1)) })
  (vecGet v (- n 1)) })
(:: main Int)
;@axiom:effect(io)
(fn (main) {
  (let v (vecWithCapacity 131072))
  (let alias v)
  (let before (memGetWord (as v Int) 2))
  (fill v 524289)
  (println (if (== before (memGetWord (as alias Int) 2)) 1 0))
  (println (& (memGetWord (as v Int) 2) 15))
  (println (memGetWord (memGetWord (as v Int) 2) (- (vecCap v) 1)))
  (fill v 4194305)
  (println (if (!= before (memGetWord (as alias Int) 2)) 1 0))
  (println (vecGet alias 4194304))
  0 })
"""
ACCOUNT = """(import IO)
(import Mem)
(:: main Int)
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main) {
  (let mark __axiom_arena_mark)
  (let held (__axiom_mem_stat 0))
  (let mapped (__axiom_mem_stat 2))
  (let p (memAlloc 1048576))
  (__retain p)
  (println (- (__axiom_mem_stat 0) held))
  (println (- (__axiom_mem_stat 2) mapped))
  (__release p)
  (println (- (__axiom_mem_stat 2) mapped))
  (for i in 0..20 { (memAlloc 2097152) (__axiom_arena_reset mark) })
  (println (- (__axiom_mem_stat 2) mapped))
  0 })
"""
BENCH = """(import IO)
(import Sys)
(import Vec)
(:: main Int)
;@axiom:effect(io)
(fn (main) {
  (let n (+ 16777215 sysArgc))
  (let v vecNew)
  (let mut i 0)
  (while (< i n) { (vecPush v i) (set i (+ i 1)) })
  (let mut sum 0)
  (set i 0)
  (while (< i n) { (set sum (+ sum (vecGet v i))) (set i (+ i 1)) })
  (println sum)
  0 })
"""
STARTUP = """(import IO)
(:: main Int)
;@axiom:effect(io)
(fn (main) { (println 0) 0 })
"""


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument('--axiom', default=os.environ.get('AXIOM'))
    ap.add_argument('--baseline')
    ap.add_argument('--work', type=Path)
    ap.add_argument('--bench', action='store_true')
    ap.add_argument('--bench-only', action='store_true')
    ap.add_argument('--cross', action='store_true')
    args = ap.parse_args()
    if not args.axiom:
        ap.error('--axiom or AXIOM must name an already-built compiler')
    work = args.work or Path(tempfile.mkdtemp(prefix='axiom-vec-growth-'))
    work.mkdir(parents=True, exist_ok=True)
    work = work.resolve()
    env = dict(os.environ, AXIOM_STDLIB=str(ROOT / 'stdlib'),
               AXIOM_PATH=str(ROOT / 'core'), AXIOM_CODEGEN_JOBS='1')
    commands = []
    results = {'host': platform.platform(), 'work': str(work), 'checks': []}

    def run(argv, *, timeout=120, expect=0):
        argv = list(map(str, argv))
        commands.append(argv)
        p = subprocess.run(argv, cwd=ROOT, env=env, capture_output=True,
                           text=True, timeout=timeout)
        if expect is not None and p.returncode != expect:
            raise AssertionError(f'{argv}: exit {p.returncode}\n{p.stdout}\n{p.stderr}')
        return p

    def check(label, actual, expected):
        if actual != expected:
            raise AssertionError(f'{label}: {actual!r}, expected {expected!r}')
        results['checks'].append(label)
        print('ok', label, flush=True)

    def build(compiler, src, name, opt=2, extra=()):
        out = work / name
        p = run([sys.executable, ROOT / 'scripts/lib/internal-probe.py', compiler,
                 '--diagnostic-format=ai', 'build', src, '--opt', opt,
                 '--emit-llvm', '-o', out, *extra])
        (work / (name + '.build.log')).write_text(p.stdout + p.stderr)
        return out

    def hand_build(ir, name):
        out = work / name
        run(['opt', '-O2', ir, '-S', '-o', str(out) + '.opt.ll'])
        run(['llc', '-filetype=obj', '-relocation-model=pic', str(out) + '.opt.ll',
             '-o', str(out) + '.o'])
        link = ['cc', str(out) + '.o', '-o', out]
        if platform.system() == 'Darwin':
            link += ['-e', '_main']
        run(link)
        return out

    def fixture(compiler, stem, opt, suffix):
        src = ROOT / 'tests/stdlib' / (stem + '.ax')
        out = build(compiler, src, f'{stem}.{suffix}.O{opt}', opt)
        result = run([out], expect=None)
        (work / (out.name + '.run.log')).write_text(
            f'exit={result.returncode}\n{result.stdout}{result.stderr}')
        expected_out = src.with_suffix('.out').read_text() if src.with_suffix('.out').exists() else ''
        expected_exit = int(src.with_suffix('.exit').read_text()) if src.with_suffix('.exit').exists() else 0
        check(out.name, (result.returncode, result.stdout), (expected_exit, expected_out))
        err = src.with_suffix('.err')
        if err.exists():
            check(out.name + ' trap message', result.stderr.startswith(err.read_text().strip()), True)

    try:
        if not args.bench_only:
            for opt in (0, 2):
                fixture(args.axiom, '1002-vec-in-place-growth', opt, 'candidate')
                if args.baseline:
                    fixture(args.baseline, '1002-vec-in-place-growth', opt, 'baseline')
            for stem in ('160-arena', '165-arena-keep', '166-arena-bad-mark',
                         '168-region', '402-recover-oom', '406-array-form-large-block',
                         '561-failed-operations', '562-vec-capacity-range',
                         '702-arena-mark-into', '777-vec-borrowed-element',
                         '778-vec-lent-argument', '801-reset-cleanup', '846-vec-pop-release',
                         '852-task-budgets', '952-task-ranges-lifecycle',
                         '968-vec-set-reclaim', '974-large-block-reuse', '975-large-block-keep'):
                fixture(args.axiom, stem, 2, 'candidate')

            probe = work / 'pointer.ax'
            probe.write_text(PROBE + RAW_HELPERS)
            binary = build(args.axiom, probe, 'pointer')
            check('in-place growth, alignment, zero tail, moving fallback and alias',
                  run([binary]).stdout, '1\n0\n0\n1\n4194304\n')
            irpath = binary.with_suffix('.ll')
            ir = irpath.read_text()
            # Every ablation must change exactly the intended instruction.
            edits = {
                'no-reservations': ('  %resok = and i1 %resmin, %resmax',
                                    '  %resok = and i1 %resmin, false'),
                'reservation-refused': ('  %rfail = or i1 %rfl, %rfn',
                                        '  %rfail = or i1 %rfl, true'),
            }
            for name, (before, after) in edits.items():
                check(name + ' mutation site', ir.count(before), 1)
                path = work / (name + '.ll')
                path.write_text(ir.replace(before, after))
                changed = hand_build(path, name)
                check(name + ' copies with unchanged elements', run([changed]).stdout,
                      '0\n0\n0\n1\n4194304\n')
            if args.baseline:
                base = build(args.baseline, probe, 'pointer-baseline')
                check('baseline moves and preserves elements', run([base]).stdout,
                      '0\n0\n0\n1\n4194304\n')

            accounting = work / 'accounting.ax'
            accounting.write_text(ACCOUNT + RAW_HELPERS)
            binary = build(args.axiom, accounting, 'accounting')
            check('reservations charge payload plus header and reset stays bounded',
                  run([binary]).stdout, '1048640\n1048640\n0\n0\n')

            semantic = work / '1002-vec-in-place-growth.candidate.O2.ll'
            text = semantic.read_text()
            match = re.search(r'define i64 @Vec\$vecReserveExactly\([^\n]+\n.*?^}', text, re.M | re.S)
            if not match:
                raise AssertionError('missing Vec reserve definition')
            body, sites = re.subn(r'(?m)^(  %[^ ]+) = call i64 @Internal.Raw\$rawMarkArray\([^\n]+',
                                  r'\1 = add i64 0, 0', match[0])
            check('array-length mutation site', sites, 1)
            ablated = work / 'array-length-ablated.ll'
            ablated.write_text(text[:match.start()] + body + text[match.end():])
            bad = run([hand_build(ablated, 'array-length-ablated')], expect=None)
            check('appended reference cleanup control fails', (bad.returncode, bad.stdout), (24, '24\n'))
            body, sites = re.subn(r'(?m)^(  %[^ ]+) = call i64 @Internal.Raw\$rawMarkLeaf\([^\n]+',
                                  r'\1 = add i64 0, 0', match[0])
            check('old array metadata mutation site', sites, 1)
            ablated = work / 'array-shape-ablated.ll'
            ablated.write_text(text[:match.start()] + body + text[match.end():])
            bad = run([hand_build(ablated, 'array-shape-ablated')], expect=None)
            check('non-power-of-two array length control fails',
                  (bad.returncode, bad.stdout), (8, '8\n'))

            text = semantic.read_text()
            before = '  %exactkeep = and i1 %exactpayload, %knew'
            check('older source keep mutation site', text.count(before), 1)
            ablated = work / 'older-source-ablated.ll'
            ablated.write_text(text.replace(before, '  %exactkeep = and i1 %exactpayload, true'))
            bad = run([hand_build(ablated, 'older-source-ablated')], expect=None)
            check('older source ownership keep control fails',
                  (bad.returncode, bad.stdout), (32, '32\n'))

            text = semantic.read_text()
            before = '  %src = call i64 @__axiom_reserved_snapshot(i64 %original, i64 %bytes, i64 %sourcefloor)'
            check('cleanup source snapshot mutation site', text.count(before), 1)
            ablated = work / 'cleanup-source-ablated.ll'
            ablated.write_text(text.replace(before, '  %src = add i64 %original, 0'))
            bad = run([hand_build(ablated, 'cleanup-source-ablated')], expect=None)
            check('resource cleanup source lifetime control fails', bad.returncode != 0, True)

            before = '  %cleanup = icmp sgt i64 %rseq, %floor'
            check('count-zero adoption cleanup mutation site', text.count(before), 1)
            ablated = work / 'adoption-source-ablated.ll'
            ablated.write_text(text.replace(before, '  %cleanup = icmp eq i64 %rseq, -1'))
            bad = run([hand_build(ablated, 'adoption-source-ablated')], expect=None)
            check('count-zero source adoption control fails', bad.returncode != 0, True)

            # Restore the withdrawn overflow defect. The existing failed-operation
            # fixture must distinguish the bad allocator without writing its payload.
            src = ROOT / 'tests/stdlib/561-failed-operations.ax'
            binary = build(args.axiom, src, 'overflow-control')
            ir = binary.with_suffix('.ll').read_text()
            before = '  %resmax = icmp ule i64 %sz0, 137438953472'
            check('overflow mutation site', ir.count(before), 1)
            bad_ir = work / 'overflow-ablated.ll'
            bad_ir.write_text(ir.replace(before, '  %resmax = icmp ule i64 %sz0, 4611686018427387904'))
            bad = run([hand_build(bad_ir, 'overflow-ablated')], expect=None)
            check('overflow control is rejected by the golden',
                  (bad.returncode, bad.stdout) != (0, src.with_suffix('.out').read_text()), True)

            # The shared creation counter cannot be driven to its end by
            # running. Patching its initializer is the boundary, as the
            # retain-overflow fixture patches a header.
            limit = '9223372036854775807'
            last = '9223372036854775806'

            def patch_counter(ir, symbol, value):
                needle = f'{symbol} = internal global i64 0'
                check(symbol + ' initializer', ir.count(needle), 1)
                return ir.replace(needle, f'{symbol} = internal global i64 {value}', 1)

            def patched(ir, name):
                path = work / (name + '.ll')
                path.write_text(ir)
                return hand_build(path, name)

            reserve_src = work / 'sequence-reserve.ax'
            reserve_src.write_text(r"""(import IO)
(import Mem)
(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (let mark0 __axiom_arena_mark)
    (println (memGetWord mark0 3))
    (let p (memAlloc 1048576))
    (println (memGetWord p -3))
    (let mark1 __axiom_arena_mark)
    (println (memGetWord mark1 3))
    (let q (memAlloc 1048576))
    (println (memGetWord q -3))
    0
  })
""" + RAW_HELPERS)
            reserve_bin = build(args.axiom, reserve_src, 'sequence-reserve')
            reserve_ir = reserve_bin.with_suffix('.ll').read_text()
            check('shared counter reserves below the limit', run([reserve_bin]).stdout,
                  '0\n-1\n1\n-1\n')
            check('last shared number still reserves once',
                  run([patched(patch_counter(reserve_ir, '@__axiom_res_seq', last),
                               'sequence-reserve-last')]).stdout,
                  last + '\n-1\n' + limit + '\n4100\n')
            check('shared limit uses the ordinary allocator twice',
                  run([patched(patch_counter(reserve_ir, '@__axiom_res_seq', limit),
                               'sequence-reserve-limit')]).stdout,
                  limit + '\n4100\n' + limit + '\n4100\n')
            reserve_off = reserve_ir.replace(
                '%rwrapped = icmp uge i64 %rseq, ' + limit,
                '%rwrapped = icmp eq i64 %rseq, -1', 1)
            check('reservation limit mutation site',
                  reserve_ir.count('%rwrapped = icmp uge i64 %rseq, ' + limit), 1)
            reserve_disabled = run([patched(
                patch_counter(reserve_off, '@__axiom_res_seq', limit),
                'sequence-reserve-off')])
            # The mark is read before the allocation, so line 0 is the limit
            # and line 1 is the class of that allocation.
            check('disabled reservation limit still reserves',
                  reserve_disabled.stdout.split('\n')[1], '-1')

            resource_src = work / 'sequence-resource.ax'
            resource_src.write_text(r"""(import IO)
(import Mem)
(:: note (-> Int Int))
(fn (note p)
  {
    (memSetWord p 0 1)
    0
  })
(:: main Int)
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (main)
  {
    (let flag (memAlloc 8))
    (let st
      (__axiom_recover __axiom_arena_mark
        (lambda (x)
          {
            (__resource_new note flag)
            0
          })))
    (println st)
    (println (memGetWord flag 0))
    (let p (memAlloc 1048576))
    (println (memGetWord p -3))
    (let mark __axiom_arena_mark)
    (println (memGetWord mark 3))
    0
  })
""" + RAW_HELPERS)
            resource_bin = build(args.axiom, resource_src, 'sequence-resource')
            resource_ir = resource_bin.with_suffix('.ll').read_text()
            refused = '70\n0\n4100\n' + limit + '\n'
            # Startup has not consumed a number, so the unpatched program
            # creates the owner and its discarded callback runs.
            check('resource creation below the limit runs its callback',
                  run([resource_bin]).stdout.split('\n')[1], '1')
            check('resource limit refuses before the callback',
                  run([patched(patch_counter(resource_ir, '@__axiom_res_seq', limit),
                               'sequence-resource-limit')]).stdout,
                  refused)
            resource_off = resource_ir.replace(
                '%sequencefull = icmp uge i64 %sequence, ' + limit,
                '%sequencefull = icmp eq i64 %sequence, -1', 1)
            check('resource limit mutation site',
                  resource_ir.count('%sequencefull = icmp uge i64 %sequence, ' + limit), 1)
            disabled = run([patched(patch_counter(resource_off, '@__axiom_res_seq', limit),
                                    'sequence-resource-off')])
            check('disabled resource limit acquires and wraps',
                  disabled.stdout, '0\n1\n4100\n-9223372036854775808\n')
            check('resource refusal differs from its disabled check',
                  refused != disabled.stdout, True)

            bare_src = work / 'sequence-bare.ax'
            bare_src.write_text(r"""(import Mem)
(:: main Int)
(fn (main)
  {
    (let before (memGetWord __axiom_arena_mark 3))
    (let p (memAlloc 1048576))
    (let cls (memGetWord p -3))
    (let after (memGetWord __axiom_arena_mark 3))
    (if (== cls -1)
      (if (== after (+ before 1))
        0
        4)
      (if (== after before)
        2
        5))
  })
""" + RAW_HELPERS)
            bare_bin = build(args.axiom, bare_src, 'sequence-bare')
            bare_ir = bare_bin.with_suffix('.ll').read_text()
            check('private reservation counter reserves', run([bare_bin]).returncode, 0)
            check('last private number reserves',
                  run([patched(patch_counter(bare_ir, '@__axiom_reserve_seq', last),
                               'sequence-bare-last')], expect=None).returncode, 0)
            check('private limit keeps the counter and uses ordinary allocation',
                  run([patched(patch_counter(bare_ir, '@__axiom_reserve_seq', limit),
                               'sequence-bare-limit')], expect=None).returncode, 2)
            bare_off = bare_ir.replace(
                '%rwrapped = icmp uge i64 %rseq, ' + limit,
                '%rwrapped = icmp eq i64 %rseq, -1', 1)
            check('private limit mutation site',
                  bare_ir.count('%rwrapped = icmp uge i64 %rseq, ' + limit), 1)
            check('disabled private limit reserves',
                  run([patched(patch_counter(bare_off, '@__axiom_reserve_seq', limit),
                               'sequence-bare-off')], expect=None).returncode, 0)

            if args.cross:
                for target in ('darwin-aarch64', 'darwin-x86_64', 'linux-aarch64',
                               'linux-x86_64', 'freebsd-aarch64', 'freebsd-x86_64',
                               'windows-aarch64', 'windows-x86_64', 'baremetal-aarch64'):
                    ll = work / (target + '.ll')
                    run([args.axiom, '--diagnostic-format=ai', 'emit-llvm', probe,
                         '--target', target, '-o', ll])
                    text = ll.read_text()
                    check(target + ' reservation eligibility',
                          '@__axiom_reserved = ' in text,
                          target.startswith(('darwin-', 'linux-', 'freebsd-')))
                    run(['opt', '-passes=verify', ll, '-disable-output'])
                    run(['llc', '-filetype=obj', ll, '-o', work / (target + '.o')])
                    check(target + ' IR verifies and assembles', True, True)
                for name, extra in (('ceiling', ['--heap-ceiling', '268435456']),
                                    ('cap', []), ('threads', ['--threads'])):
                    source = work / (name + '.ax')
                    text = PROBE
                    if name == 'cap':
                        text = text.replace('(let v (vecWithCapacity 131072))',
                                            '(__axiom_arena_cap 268435456)\n  (let v (vecWithCapacity 131072))')
                    if name == 'threads':
                        text = text.replace(';@axiom:effect(io)',
                                            ';@axiom:effect(io)\n;@axiom:effect(spawn)\n;@axiom:effect(block)')
                        text = text.replace('(let v (vecWithCapacity 131072))',
                                            '(__thread_join (__thread_spawn (lambda (x) 0) 0))\n  (let v (vecWithCapacity 131072))')
                    source.write_text(text + RAW_HELPERS)
                    out = build(args.axiom, source, name, extra=extra)
                    check(name + ' uses copying fallback', run([out]).stdout,
                          '0\n0\n0\n1\n4194304\n')
                    check(name + ' contains no reservation runtime',
                          '@__axiom_reserved = ' in out.with_suffix('.ll').read_text(), False)

        if args.bench:
            if not args.baseline:
                ap.error('--bench needs --baseline')
            src = work / 'bench.ax'
            src.write_text(BENCH)
            startup = work / 'startup.ax'
            startup.write_text(STARTUP)
            binaries = {}
            starts = {}
            samples = {'baseline': [], 'candidate': []}
            for label, compiler in [('baseline', args.baseline), ('candidate', args.axiom)]:
                binaries[label] = build(compiler, src, 'bench-' + label)
                starts[label] = build(compiler, startup, 'startup-' + label)
            for i in range(9):
                for label in (('baseline', 'candidate') if i % 2 == 0 else ('candidate', 'baseline')):
                    start = time.perf_counter()
                    check_run = run([starts[label]])
                    launch = time.perf_counter() - start
                    check('startup checksum ' + label + str(i), check_run.stdout, '0\n')
                    argv = [str(binaries[label])]
                    commands.append(argv)
                    start = time.perf_counter()
                    child = subprocess.Popen(argv, cwd=ROOT, env=env,
                                             stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                             text=True)
                    _, status, usage = os.wait4(child.pid, 0)
                    elapsed = time.perf_counter() - start
                    child.returncode = os.waitstatus_to_exitcode(status)
                    stdout, stderr = child.communicate()
                    check('benchmark exit ' + label + str(i), child.returncode, 0)
                    check('benchmark checksum ' + label + str(i), stdout, '140737479966720\n')
                    rss = usage.ru_maxrss * (1 if platform.system() == 'Darwin' else 1024)
                    samples[label].append({'wall_s': elapsed, 'launch_s': launch,
                                           'net_s': elapsed - launch, 'rss_bytes': rss,
                                           'stderr': stderr, 'user_s': usage.ru_utime,
                                               'system_s': usage.ru_stime})
            results['benchmark'] = {'samples': samples, 'medians': {
                label: {key: statistics.median(s[key] for s in rows)
                        for key in ('wall_s', 'launch_s', 'net_s', 'rss_bytes')}
                for label, rows in samples.items()}}
            print(json.dumps(results['benchmark']['medians'], indent=2), flush=True)
    finally:
        (work / 'commands.json').write_text(json.dumps(commands, indent=2) + '\n')
        (work / 'results.json').write_text(json.dumps(results, indent=2) + '\n')
    print(f'{len(results["checks"])} checks passed; evidence: {work}')


if __name__ == '__main__':
    main()
