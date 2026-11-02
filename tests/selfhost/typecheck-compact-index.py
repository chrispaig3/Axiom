#!/usr/bin/env python3
"""Check compact exact-name indexes, owning pools and measured layout savings."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).with_name('emitter-line-buffer.py')))
run_checked = SUPPORT['run_checked']
replace_once = SUPPORT['replace_once']
check_output = SUPPORT['check_output']
BRIDGE = '''
(pub :: probeIndexCompact (-> FnIndex Bool))
(pub fn (probeIndexCompact index) index.indexed)
(pub :: probeIndexEntries (-> FnIndex Int))
(pub fn (probeIndexEntries index) (vecLen index.entries))
(pub :: probeIndexNodes (-> FnIndex Int))
(pub fn (probeIndexNodes index) (vecLen index.nodes))
(pub :: probeIndexBuckets (-> FnIndex Int))
(pub fn (probeIndexBuckets index) (vecLen index.buckets))
(pub :: probeIndexScalarNodes (-> FnIndex Bool))
(pub fn (probeIndexScalarNodes index) (! (vecOwnsRefs index.nodes)))
(pub :: probeIndexScalarBuckets (-> FnIndex Bool))
(pub fn (probeIndexScalarBuckets index) (! (vecOwnsRefs index.buckets)))
(pub :: probeIndexPoolAddress (-> FnIndex Addr))
(pub fn (probeIndexPoolAddress index) (addrOf index.entries))
'''


def check(compiler, root, work):
    original = (root / 'core/typecheck.ax').read_text()
    environment = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    expected = [f'{index} true' for index in range(1, 43)]
    source = work / 'compact-index.ax'
    source.write_bytes((root / 'tests/selfhost/typecheck-compact-index.axp').read_bytes())
    capacity = work / 'capacity.ax'
    capacity.write_bytes((root / 'tests/selfhost/typecheck-compact-index-capacity.axp').read_bytes())
    memory = work / 'memory.ax'
    memory.write_bytes((root / 'tests/selfhost/typecheck-compact-index-memory.axp').read_bytes())
    version = subprocess.run([str(compiler), '--diagnostic-format=ai', 'version'],
                             env=environment, capture_output=True, text=True, check=True).stdout.strip()
    report = {'source_sha256': hashlib.sha256(original.encode()).hexdigest(),
              'builder': str(compiler), 'builder_version': version,
              'configurations': [], 'counterexamples': [], 'refusals': [], 'memory': [],
              'invariants': [
                  {'invariant': 'Exact lookup preserves first insertion order, qualification and visibility.',
                   'enforcement': 'Packed head/tail chains and existing predicates; cases 1-20,34-41.',
                   'counterexample': 'lost-chain-head'},
                  {'invariant': 'The index owns entries independently of their original vector.',
                   'enforcement': 'Sealed FnIndex entry pool; shared mutation14 and ownership29-33.',
                   'counterexample': 'unmapped-entry-pool'},
                  {'invariant': 'Append-only vector headers preserve Links through data-buffer growth.',
                   'enforcement': 'Typed Link API and sealed vector identity; cases 21-28.',
                   'counterexample': 'lost-chain-head'},
                  {'invariant': 'Chain nodes and bucket head/tail pairs are unallocated scalar words.',
                   'enforcement': 'Two UInt32 Link fields per word, sizeof8 and scalar-vector evidence4,10,11,28; fnIdxAdd IR has no record allocations.',
                   'counterexample': 'allocated-chain-nodes'},
                  {'invariant': 'Link capacity overflow preserves lookup by switching to the owning linear table.',
                   'enforcement': 'UInt32 guard, bounded oversized-hint fallback34-41, and injected UInt8 capacity12 cases.',
                   'counterexample': 'missing-capacity-guard traps80 before overflowing packed Link'},
              ],
              'known_limits': ['Host O0/O2 execution with allocation poisoning; no Windows runtime evidence.',
                               'The suffix index retains its original storage; its alias is renamed only.',
                               'Link itself does not carry vector identity; sealed index operations keep both owning vectors private and append-only.',
                               'Capacity tests inject UInt8/255 bounds, never allocate four billion entries.',
                               'Memory counters include allocator chunk overhead; process RSS varies by host and is recorded only where resource.getrusage is available.',
                               'No region traversal, lifetime enforcement or held M5 work is exercised.',
                               'These bounded tests do not establish global soundness, Rust parity or certification.']}
    for fixture in [source, capacity, memory]:
        run_checked([str(compiler), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)],
                    env=environment, stdout=work / (fixture.stem + '.fmt.stdout'), stderr=work / (fixture.stem + '.fmt.stderr'))

    def modules(label, contents):
        directory = work / (label + '-modules/core')
        directory.mkdir(parents=True)
        for path in (root / 'core').iterdir():
            destination = directory / path.name
            if path.name == 'typecheck.ax':
                destination.write_text(contents + BRIDGE)
            else:
                destination.symlink_to(path, target_is_directory=path.is_dir())
        return dict(environment, AXIOM_PATH=str(directory))

    def build(label, contents, level, fixture=source):
        local = modules(label, contents)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(fixture),
                     '--opt', str(level), '--alloc-poison', '--emit-llvm', '-o', str(binary)],
                    env=local, stdout=work / (label + '.build.stdout'), stderr=work / (label + '.build.stderr'))
        return binary, local

    def build_run(label, contents, level, failures=(), fixture=source, count=42):
        binary, local = build(label, contents, level, fixture)
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        wanted = expected if count == 42 else [f'{index} true' for index in range(1, count + 1)]
        observed = check_output(output, wanted, required_failures=failures)
        print('ok   ' + label + ': ' + str(sorted(observed)), flush=True)
        return observed, binary

    for level in (0, 2):
        _, binary = build_run('positive-O' + str(level), original, level)
        ir = Path(str(binary) + '.ll').read_text()
        start = ir.index('define i64 @typecheck$fnIdxAdd(')
        finish = ir.index('\n}', start)
        if '@axiom_alloc(' in ir[start:finish]:
            raise RuntimeError('fnIdxAdd allocates chain/bucket records instead of word values')
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True,
                                         'cases': 42, 'status': 'passed', 'record_allocations_in_fnIdxAdd': 0})
    head = replace_once(original, '(FnIndexBucket :head bucket.head :tail added)',
                        '(FnIndexBucket :head added :tail added)', 'chain head preserves earlier entries')
    allocated = replace_once(original, '(pub struct FnIndexNode word sealed',
                             '(pub struct FnIndexNode sealed', 'word node layout')
    pool = replace_once(original, '(fnIdxAdd index (vecGet fns i)))\n    index',
                        '(fnIdxAdd index (vecGet fns i)))\n    (memMarkLeaf (as index.entries Int))\n    index',
                        'owning entry pool reference map')
    for label, changed, cases in [('lost-chain-head', head, (5, 7, 13, 14, 22)),
                                  ('allocated-chain-nodes', allocated, (10, 28)),
                                  ('unmapped-entry-pool', pool, (30, 32))]:
        failures, _ = build_run(label, changed, 0, cases)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failures)})
    tiny = original.replace('(Link FnEnt UInt32)', '(Link FnEnt UInt8)').replace(
        '(Link FnIndexNode UInt32)', '(Link FnIndexNode UInt8)')
    tiny = replace_once(tiny, '(fn (fnIdxLinkLimit)\n  4294967295)', '(fn (fnIdxLinkLimit)\n  255)', 'test capacity')
    build_run('capacity-255', tiny, 0, fixture=capacity, count=12)
    guard = '(&& index.indexed (&& (< position fnIdxLinkLimit) (< (vecLen nodes) fnIdxLinkLimit)))'
    unsafe = replace_once(tiny, guard, 'index.indexed', 'capacity guard')
    binary, local = build('missing-capacity-guard', unsafe, 0, capacity)
    result = subprocess.run([str(binary)], env=local, capture_output=True, text=True)
    (work / 'missing-capacity-guard.stdout').write_text(result.stdout)
    (work / 'missing-capacity-guard.stderr').write_text(result.stderr)
    if result.returncode != 80 or 'axiom: link does not fit its field' not in result.stderr:
        raise RuntimeError(('missing-capacity-guard', result))
    report['counterexamples'].append({'name': 'missing-capacity-guard', 'status': 80})
    print('ok   missing-capacity-guard: traps80', flush=True)
    local = modules('refusals', original)
    for name, expression, code in [
        ('erased-index', '(fnIdxGet (:: vecNew (Vec FnEnt)) "missing")', 'AX3004'),
        ('wrong-link-pool', '(linkGet (:: vecNew (Vec FnEnt)) (:: linkNone (Link FnIndexNode UInt32)))', 'AX3004'),
        ('missing-lookup-none', '(match (fnIdxGet (fnIdxBuildSized vecNew 0) "missing") ((Some entry) 0))', 'AX3005'),
        ('sealed-node', '(FnIndexNode :entry (:: linkNone (Link FnEnt UInt32)) :next (:: linkNone (Link FnIndexNode UInt32)))', 'AX3085'),
    ]:
        refused = work / (name + '.ax')
        refused.write_text('(import core)\n(import parser)\n(import typecheck)\n(import Vec)\n(import Link)\n'
                           '(:: main Int)\n(fn (main) { ' + expression + ' 0 })\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(refused)],
                                env=local, capture_output=True, text=True)
        (work / (name + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or f'E {code} ' not in errors[0]:
            raise RuntimeError((name, result))
        report['refusals'].append({'name': name, 'diagnostic': code, 'status': 'passed'})
        print('ok   ' + name + ': ' + code, flush=True)
    binary, local = build('memory-comparison', original, 2, memory)
    # A fresh parent for each child prevents ru_maxrss retaining a previous maximum.
    probe = '''import json,subprocess,sys
r=subprocess.run(sys.argv[1:],capture_output=True,text=True)
try:
    import resource
    peak=resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
except ImportError:
    peak=None
print(json.dumps({"status":r.returncode,"stdout":r.stdout,"stderr":r.stderr,"peak_rss":peak}))
'''
    for size in ['small', 'large']:
        rows = {}
        for mode in ['legacy', 'compact']:
            result = subprocess.run([sys.executable, '-c', probe, str(binary), size, mode],
                                    env=local, capture_output=True, text=True, check=True)
            stats = json.loads(result.stdout)
            parts = stats['stdout'].split()
            if stats['status'] != 0 or stats['stderr'] or len(parts) != 5 or parts[-1] != 'true':
                raise RuntimeError((size, mode, stats))
            rows[mode] = {'count': int(parts[0]), 'held_delta': int(parts[1]),
                          'live_delta': int(parts[2]), 'mapped_delta': int(parts[3]),
                          'peak_rss_bytes': None if stats['peak_rss'] is None else stats['peak_rss'] * (1024 if sys.platform != 'darwin' else 1)}
        if rows['compact']['live_delta'] * 2 >= rows['legacy']['live_delta']:
            raise RuntimeError(('compact index failed live allocation budget', rows))
        report['memory'].append({'size': size, 'rows': rows})
        print('ok   memory ' + size + ': ' + json.dumps(rows), flush=True)
    (work / 'compact-index-report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if arguments.work:
        work = arguments.work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        check(arguments.axiom.resolve(), root, work)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-compact-index-') as directory:
            check(arguments.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
