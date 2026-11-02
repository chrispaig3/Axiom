#!/usr/bin/env python3
"""Check DupRef width guards, ordered owning fallback and stable diagnostics."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).with_name('emitter-line-buffer.py')))
run_checked = SUPPORT['run_checked']
replace_once = SUPPORT['replace_once']
check_output = SUPPORT['check_output']
GOLDENS = ['010-duplicate-fn', '020-duplicate-thrice', '050-duplicate-struct', '1255-duplicate-signature']
BRIDGE = '''
(pub :: probeDupNew (-> Int Int DupIdx))
(pub fn (probeDupNew hint capacity) (dupIdxNew hint capacity))
(pub :: probeDupCompact (-> DupIdx Bool))
(pub fn (probeDupCompact index) index.compact)
(pub :: probeDupNames (-> DupIdx Int))
(pub fn (probeDupNames index) (vecLen index.names))
(pub :: probeDupWide (-> DupIdx Int))
(pub fn (probeDupWide index) (vecLen index.wide))
(pub :: probeDupLimit (-> DupIdx Int))
(pub fn (probeDupLimit index) index.limit)
(pub :: probeDupBuckets (-> DupIdx Int))
(pub fn (probeDupBuckets index) (vecLen index.value))
(pub :: probeDupWideOwners (-> DupIdx Bool))
(pub fn (probeDupWideOwners index) (vecOwnsRefs index.wide))
(pub :: probeDupReturned (-> Bool DupIdx))
(pub fn (probeDupReturned packed) {
  (let name (strDup "survivor"))
  (let index (dupIdxNew 0 (if packed 1 0)))
  (dupIdxPut index name NS_VALUE 0)
  index
})
(pub :: probeDupFromDecls (-> Int DupIdx))
(pub fn (probeDupFromDecls capacity) {
  (let declarations (vecPush vecNew (nodeBuildDFn (strDup "from-source") vecNew (mkEInt 0) 0)))
  (let index (dupIdxNew (vecLen declarations) capacity))
  (for i in 0..(vecLen declarations) (dupIdxAddDecl index (vecGet declarations i) i))
  (vecClear declarations)
  index
})
(pub :: probeDupDiagnostic (-> Int Int String))
(pub fn (probeDupDiagnostic mode capacity) {
  (let source (probeDupSource mode))
  (let parsed (parseModuleWith (lex source) (scanAxtags source)))
  (match parsed
    ((ParseFailed parseError1) "parse failed")
    ((ParseSuccess parsedValue1 parsedPos1) { (let declarations parsedValue1)
      (let index (dupIdxNew (vecLen declarations) capacity))
      (for i in 0..(vecLen declarations) (dupIdxAddDecl index (vecGet declarations i) i))
      (let diagnostics (checkDuplicates index declarations vecNew 0))
      (let units (vecPush vecNew (CUnit2 :file (probeDupFile mode) :src source :name None :imports vecNew :library false)))
      (renderDiagsUnits diagnostics units) }))
})
(pub :: probeDupDiagnosticGood (-> Int Int Bool))
(pub fn (probeDupDiagnosticGood mode capacity)
  (strEq (probeDupDiagnostic mode capacity) (probeDupDiagnostic mode 4294967295)))
'''


def change_function(source, name, before, after):
    head = '(pub fn (' + name + ' ' if '(pub fn (' + name + ' ' in source else '(fn (' + name + ' '
    begin = source.index(head)
    end = source.index('\n\n', begin)
    return source[:begin] + replace_once(source[begin:end], before, after, name) + source[end:]


def check(compiler, root, work):
    original = (root / 'core/typecheck.ax').read_text()
    bridge = BRIDGE
    for name, values in [('probeDupSource', [(root / 'tests/diagnostics' / (name + '.ax')).read_text() for name in GOLDENS]),
                         ('probeDupFile', [name + '.ax' for name in GOLDENS])]:
        bridge += '(:: ' + name + ' (-> Int String))\n(fn (' + name + ' mode)\n'
        for index, value in enumerate(values[:-1]):
            bridge += f'  (if (== mode {index}) {json.dumps(value)}\n'
        bridge += json.dumps(values[-1]) + ')' * len(values) + '\n'
    fixture = work / 'dup-link-guard.ax'
    fixture.write_bytes((root / 'tests/selfhost/typecheck-dup-link-guard.axp').read_bytes())
    expected = [f'{i} true' for i in range(1, 49)]
    environment = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {'source_sha256': hashlib.sha256(original.encode()).hexdigest(), 'builder': str(compiler),
              'configurations': [], 'counterexamples': [], 'diagnostics': [], 'refusals': [],
              'invariants': [
                  {'invariant': 'Both packed widths are checked before the declaration cast and Link field store.',
                   'enforcement': 'Nonnegative index, clamped capacity, index <= limit and name count < limit guards; tests17-28 include real UInt32max/max+1 without large allocation.',
                   'counterexample': 'unchecked-declaration-index and unchecked-name-link'},
                  {'invariant': 'Overflow permanently selects a full-width owning fallback; packed rows precede every fallback row.',
                   'enforcement': 'DupWide fields, compact flag and packed-first/ordered-wide lookup; tests1-16,29-31,38-41,48.',
                   'counterexample': 'repacked-after-fallback and crossed-fallback-namespace'},
                  {'invariant': 'Both paths own their names and release them after the index dies; links survive vector growth.',
                   'enforcement': 'Owning names/DupWide vectors; dynamic String counts, returned owners, source-vector drop, growth and vecOwnsRefs cases32-38,45-47.',
                   'counterexample': 'unmapped-wide-name'},
                  {'invariant': 'Valid duplicate diagnostics retain first-witness order and exact source fields.',
                   'enforcement': 'Four existing AX3006 byte goldens under capacity0,2,UInt32max at O0/O2; cases42-44.',
                   'counterexample': 'crossed-fallback-namespace'},
              ],
              'known_limits': ['Host O0/O2 native checks with allocation poisoning; no Windows runtime or throughput improvement claim.',
                               'Tiny injected capacities exercise transition guards; real UInt32max declaration indices are scalar inputs, not four-billion-entry allocations.',
                               'The packed DupRef definition remains one UInt32 Link plus UInt32 index; owners remain full width.',
                               'Fallback intentionally scans in insertion order and may be slower for oversized inputs.',
                               'The guard does not redesign Link, Vec growth, lifetime algorithms or held M5 work; no global safety/completeness claim follows.']}
    run_checked([str(compiler), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)], env=environment,
                stdout=work / 'fmt.stdout', stderr=work / 'fmt.stderr')

    def modules(label, contents):
        directory = work / (label + '-modules/core')
        directory.mkdir(parents=True)
        for path in (root / 'core').iterdir():
            out = directory / path.name
            if path.name == 'typecheck.ax':
                out.write_text(contents + bridge)
            else:
                out.symlink_to(path, target_is_directory=path.is_dir())
        return dict(environment, AXIOM_PATH=str(directory))

    def build_run(label, contents, level, failures=()):
        local = modules(label, contents)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(fixture), '--opt', str(level), '--alloc-poison', '-o', str(binary)],
                    env=local, stdout=work / (label + '.build.stdout'), stderr=work / (label + '.build.stderr'), timeout=240)
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        observed = check_output(output, expected, required_failures=failures)
        print(f'ok   {label}: {sorted(observed)}', flush=True)
        return binary, local, observed

    for level in (0, 2):
        binary, local, _ = build_run('positive-O' + str(level), original, level)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True, 'cases': 48, 'status': 'passed'})
        for mode, name in enumerate(GOLDENS):
            wanted = (root / 'tests/diagnostics' / (name + '.axdl')).read_text()
            for capacity in (0, 2, 4294967295):
                result = subprocess.run([str(binary), str(mode), str(capacity)], env=local, capture_output=True, text=True, timeout=30)
                (work / f'{name}-cap{capacity}-O{level}.axdl').write_text(result.stdout)
                if result.returncode or result.stderr or result.stdout != wanted:
                    raise RuntimeError(('diagnostic changed', name, capacity, level, wanted, result))
                report['diagnostics'].append({'case': name, 'capacity': capacity, 'optimization': level, 'status': 'passed'})
        result = subprocess.run([str(binary), 'negative'], env=local, capture_output=True, text=True, timeout=30)
        if result.returncode != 77 or 'vector index out of range' not in result.stderr:
            raise RuntimeError(('negative index guard', result))
        report['refusals'].append({'name': 'negative-declaration-index', 'optimization': level, 'exit': 77, 'status': 'passed'})

    declaration = change_function(original, 'dupIdxPut', '(<= i idx.limit)', 'true')
    names = change_function(original, 'dupIdxPut', '(< (vecLen idx.names) idx.limit)', 'true')
    permanent = change_function(original, 'dupIdxPut', '(&& idx.compact ', '(&& true ')
    namespace = change_function(original, 'firstDefinerWide', '(== entry.ns ns)', 'true')
    owner = change_function(original, 'dupIdxPut', '(vecPush idx.wide (DupWide :name name :ns (dupTableNS ns) :idx i))',
                            '(let entry (DupWide :name name :ns (dupTableNS ns) :idx i))\n        (memMarkLeaf (as entry Int))\n        (vecPush idx.wide entry)')
    for label, source, failures in [('unchecked-declaration-index', declaration, (19, 21)),
                                     ('unchecked-name-link', names, (10, 15)),
                                     ('repacked-after-fallback', permanent, (27, 39)),
                                     ('crossed-fallback-namespace', namespace, (30,)),
                                     ('unmapped-wide-name', owner, (35,))]:
        _, _, observed = build_run(label, source, 0, failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(observed)})
    no_negative = change_function(original, 'dupIdxPut', '(if (< i 0)', '(if false')
    binary, local, _ = build_run('unchecked-negative-index', no_negative, 0)
    result = subprocess.run([str(binary), 'negative'], env=local, capture_output=True, text=True, timeout=30)
    if result.returncode != 0:
        raise RuntimeError(('negative guard ablation ineffective', result))
    report['counterexamples'].append({'name': 'unchecked-negative-index', 'observed_exit': 0, 'required_positive_exit': 77})
    for name, body, code in [
        ('raw-declaration-index', '(dupIdxPut (dupIdxBuild vecNew) "bad" NS_VALUE "wrong") 0', 'AX3004'),
        ('missing-first-definer-none', '(match (firstDefiner (dupIdxBuild vecNew) 1 NS_VALUE "missing") ((Some index) index))', 'AX3005'),
    ]:
        path = work / (name + '.ax')
        path.write_text('(import typecheck)\n(import Vec)\n(:: main Int)\n(fn (main) { ' + body + ' })\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)], env=local,
                                capture_output=True, text=True, timeout=60)
        (work / (name + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or f'E {code} ' not in errors[0]:
            raise RuntimeError((name, result))
        report['refusals'].append({'name': name, 'diagnostic': code, 'status': 'passed'})
    (work / 'dup-link-guard-report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), root, args.work.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-dup-link-guard-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
