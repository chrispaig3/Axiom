#!/usr/bin/env python3
"""Check optional trivia positions, match fix bytes and effective counterexamples."""
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
    fixture = (root / 'tests/selfhost/typecheck-trivia-options.axp').read_text()
    diagnostics = (root / 'tests/selfhost/typecheck-trivia-diagnostics.axp').read_text()
    expected = ''.join(f'{i} true\n' for i in range(1, 35))
    golden = json.loads((root / 'tests/selfhost/typecheck-trivia-diagnostics.golden.json').read_text())
    report = {
        'builder': str(compiler),
        'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'diagnostic_sha256': hashlib.sha256(golden.encode()).hexdigest(),
        'configurations': [], 'controls': [], 'refusals': [],
        'limits': ['Host O0/O2 tests cover source-position semantics, not memory-model qualification.',
                   'Span storage and ownership/lifetime inference are unchanged.'],
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

    def native(label, level, text, program):
        env = modules(label, text)
        path = work / (label + '.ax')
        path.write_text(program)
        binary = work / label
        built = invoke(label + '-build', [str(compiler), '--diagnostic-format=ai', 'build',
                       str(path), '--opt', str(level), '--alloc-poison', '-o', str(binary)], env)
        assert built.returncode == 0 and not built.stderr, (label, built.returncode, built.stderr)
        ran = invoke(label, [str(binary)], env, timeout=30)
        assert ran.returncode == 0 and not ran.stderr, (label, ran.returncode, ran.stderr)
        return ran.stdout

    if baseline:
        old = baseline.read_text()
        assert native('baseline-diagnostics', 0, old, diagnostics) == golden, 'baseline bytes differ'
        report['baseline_source_sha256'] = hashlib.sha256(old.encode()).hexdigest()
    for level in (0, 2):
        assert native('positive-O' + str(level), level, source, fixture) == expected, level
        assert native('diagnostics-O' + str(level), level, source, diagnostics) == golden, level
        report['configurations'].append({'opt': level, 'allocation_poison': True, 'cases': 34,
                                         'diagnostic_cases': 8, 'diagnostic_bytes': len(golden.encode())})
        print(f'ok   trivia positions: 34 cases and 8 exact match diagnostics O{level}', flush=True)

    controls = [
        ('lose-zero', 'skipTrivia', '(if (&& (>= k 0) (< k n))',
         '(if (&& (> k 0) (< k n))', {1, 2, 16, 17, 18, 19}),
        ('fabricate-absence', 'skipTrivia', '(Some k)\n        None)',
         '(Some k)\n        (Some 0))', {5, 6, 7, 8, 9, 10, 14, 15, 21}),
        ('accept-nonclosing-token', 'matchCloseAt', '(== (strByte src next) 41)',
         'true', {30, 31, 32}),
    ]
    for label, function, before, after, failures in controls:
        start = source.index('(pub fn (' + function + ' ')
        end = source.index('\n\n', start)
        body = source[start:end]
        assert body.count(before) == 1, (label, 'mutation anchor changed')
        changed = source[:start] + body.replace(before, after) + source[end:]
        rows = native(label, 0, changed, fixture).splitlines()
        assert len(rows) == 34, (label, rows)
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
        ('raw-offset', '(skipTrivia "x" 0)', 'AX3004'),
        ('missing-none', '(match (skipTrivia "x" 0) ((Some position) position))', 'AX3005'),
        ('binding-scope', '(if (let (Some position) (skipTrivia "" 0)) 0 position)', 'AX3001'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import typecheck)\n(:: bad Int)\n(fn (bad) ' + expression + ')\n')
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
        with tempfile.TemporaryDirectory(prefix='axiom-trivia-options-') as directory:
            check(args.axiom.resolve(), root, Path(directory), args.baseline_source)


if __name__ == '__main__':
    main()
