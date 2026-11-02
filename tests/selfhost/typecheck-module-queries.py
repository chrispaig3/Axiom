#!/usr/bin/env python3
"""Check optional module indexes and Boolean import membership without changing diagnostics."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile


def check(compiler, root, work, baseline=None):
    snapshot = work / 'source'
    snapshot.mkdir()
    for name in ('core', 'stdlib'):
        shutil.copytree(root / name, snapshot / name)
    source = (snapshot / 'core/typecheck.ax').read_text()
    fixture = (root / 'tests/selfhost/typecheck-module-queries.axp').read_text()
    diagnostics = (root / 'tests/selfhost/typecheck-module-query-diagnostics.axp').read_text()
    expected = ''.join(f'{i} true\n' for i in range(1, 42))
    golden = json.loads((root / 'tests/selfhost/typecheck-module-query-diagnostics.golden.json').read_text())
    report = {
        'builder': str(compiler),
        'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'diagnostic_sha256': hashlib.sha256(golden.encode()).hexdigest(),
        'configurations': [], 'controls': [], 'refusals': [],
        'limits': ['Host O0/O2 tests cover module query representation, not memory-model qualification.',
                   'Default unit0 policy, packed module storage and held inference bodies are unchanged.'],
    }

    def modules(label, text):
        folder = work / (label + '-modules/core')
        folder.mkdir(parents=True)
        for path in (snapshot / 'core').iterdir():
            destination = folder / path.name
            if path.name == 'typecheck.ax':
                destination.write_text(text)
            else:
                destination.symlink_to(path, target_is_directory=path.is_dir())
        return dict(os.environ, AXIOM_PATH=str(folder), AXIOM_STDLIB=str(snapshot / 'stdlib'))

    def invoke(label, arguments, env, timeout=240):
        result = subprocess.run(arguments, env=env, capture_output=True, text=True, timeout=timeout)
        (work / (label + '.stdout')).write_text(result.stdout)
        (work / (label + '.stderr')).write_text(result.stderr)
        return result

    def native(label, level, text, program, expected_status=0):
        env = modules(label, text)
        path = work / (label + '.ax')
        path.write_text(program)
        binary = work / label
        built = invoke(label + '-build', [str(compiler), '--diagnostic-format=ai', 'build',
                       str(path), '--opt', str(level), '--alloc-poison', '-o', str(binary)], env)
        assert built.returncode == 0 and not built.stderr, (label, built.returncode, built.stderr)
        ran = invoke(label, [str(binary)], env, timeout=30)
        assert ran.returncode == expected_status and not ran.stderr, (label, ran.returncode, ran.stderr)
        return ran.stdout

    if baseline:
        old = baseline.read_text()
        assert native('baseline-diagnostics', 0, old, diagnostics) == golden, 'baseline bytes differ'
        report['baseline_source_sha256'] = hashlib.sha256(old.encode()).hexdigest()
    for level in (0, 2):
        assert native('positive-O' + str(level), level, source, fixture) == expected, level
        assert native('diagnostics-O' + str(level), level, source, diagnostics) == golden, level
        report['configurations'].append({'opt': level, 'allocation_poison': True, 'cases': 41,
                                         'diagnostic_cases': 7, 'diagnostic_bytes': len(golden.encode())})
        print(f'ok   Module queries: 41 cases and 7 exact diagnostic sources O{level}', flush=True)

    existing = (root / 'tests/selfhost/typecheck-module-options.ax').read_text()
    assert native('existing-consumer', 0, source, existing, expected_status=42) == ''
    report['existing_consumer_exit'] = 42
    controls = [
        ('lose-unit-zero', 'unitIndexForFrom', '(Some i)',
         '(if (== i 0) None (Some i))', {2, 5, 7}),
        ('invent-unit-zero', 'unitIndexForFrom', '    None', '    (Some 0)', {1, 4, 6, 9}),
        ('change-default-unit', 'unitIndexFor', '((None) 0)', '((None) 1)', {11}),
        ('lose-declared-name', 'declaredInModule', '        true', '        false',
         {16, 18, 24, 30, 31, 33, 37, 38, 40}),
        ('invent-declared-name', 'declaredInModule', '    false', '    true',
         {20, 22, 23, 26, 27, 35, 39, 40}),
        ('invent-exported-name', 'exportedFromModule', '    false', '    true',
         {19, 21, 28, 34, 36, 38, 40}),
        ('ignore-private-declaration', 'exportedFromModule', '(== (nodeVis d) 1)', 'true',
         {19, 36, 38, 40}),
    ]
    for label, function, before, after, failures in controls:
        start = source.index('(pub fn (' + function + ' ')
        end = source.index('\n\n', start)
        body = source[start:end]
        assert body.count(before) == 1, (label, 'mutation anchor changed')
        changed = source[:start] + body.replace(before, after) + source[end:]
        rows = native(label, 0, changed, fixture).splitlines()
        assert len(rows) == 41, (label, rows)
        observed = set()
        for i, row in enumerate(rows, 1):
            assert row in (f'{i} true', f'{i} false'), (label, row)
            if row.endswith(' false'):
                observed.add(i)
        assert observed == failures, (label, observed, failures)
        report['controls'].append({'name': label, 'failed_cases': sorted(observed)})
        print(f'ok   {label}: actual mutant fails {sorted(observed)}', flush=True)

    env = modules('refusals', source)
    for label, expression, code in [
        ('raw-index', '(unitIndexForFrom vecNew "Owner" 0)', 'AX3004'),
        ('missing-none', '(match (unitIndexForFrom vecNew "Owner" 0) ((Some index) index))', 'AX3005'),
        ('raw-declared', '(declaredInModule vecNew "Owner" "name" 0)', 'AX3004'),
        ('raw-exported', '(exportedFromModule vecNew "Owner" "name" 0)', 'AX3004'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import core)\n(import typecheck)\n(import Vec)\n(:: bad Int)\n(fn (bad) ' + expression + ')\n')
        result = invoke(label, [str(compiler), '--diagnostic-format=ai', 'check', str(path)], env)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and errors[0].startswith('E ' + code + ' '), (
            label, result.returncode, result.stderr)
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   {label}: {code}', flush=True)
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--baseline-source', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), root, args.work.resolve(), args.baseline_source)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-module-queries-') as directory:
            check(args.axiom.resolve(), root, Path(directory), args.baseline_source)


if __name__ == '__main__':
    main()
