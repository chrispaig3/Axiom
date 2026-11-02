#!/usr/bin/env python3
"""Check optional AXTAG delimiters, diagnostic bytes and effective counterexamples."""
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
    fixture = (root / 'tests/selfhost/typecheck-axtag-delimiters.axp').read_text()
    diagnostics = (root / 'tests/selfhost/typecheck-axtag-delimiter-diagnostics.axp').read_text()
    expected = ''.join(f'{i} true\n' for i in range(1, 54))
    golden = json.loads((root / 'tests/selfhost/typecheck-axtag-delimiter-diagnostics.golden.json').read_text())
    report = {
        'builder': str(compiler),
        'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'diagnostic_sha256': hashlib.sha256(golden.encode()).hexdigest(),
        'configurations': [], 'controls': [], 'refusals': [],
        'limits': ['Host O0/O2 tests cover delimiter-presence semantics, not memory-model qualification.',
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
        report['configurations'].append({'opt': level, 'allocation_poison': True, 'cases': 53,
                                         'diagnostic_cases': 14, 'diagnostic_bytes': len(golden.encode())})
        print(f'ok   AXTAG delimiters: 53 cases and 14 exact diagnostic sources O{level}', flush=True)

    existing = (root / 'tests/selfhost/checker-axtag-owners.axp').read_text()
    assert native('existing-consumer', 0, source, existing) == ''.join(f'{i} true\n' for i in range(1, 43))
    report['existing_consumer_cases'] = 42
    controls = [
        ('lose-zero', 'axtagListValue', '(< op 0)', '(<= op 0)', {1}),
        ('invent-missing-value', 'axtagListValue', '    ""))', '    "missing"))', {2, 4, 13, 20}),
        ('drop-bare-restriction', 'restrictCollect', '(strSlice content 0 opening)\n                  content)',
         '(strSlice content 0 opening)\n                  "")', {13}),
        ('drop-bare-ct', 'ctCollect', '(strSlice content 0 opening)\n                  content)',
         '(strSlice content 0 opening)\n                  "")', {20}),
        ('drop-bare-isr', 'tagsHaveIsrIn', '(strSlice content 0 opening)\n                content)',
         '(strSlice content 0 opening)\n                "")', {25, 30}),
        ('ignore-trailing-text', 'checkOneAxtag', '(let trail\n        (if (isSome op)', '(let trail\n        (if false', {35, 38}),
        ('lose-closing-zero', 'axtagCloseFrom', '(Some i)', '(if (== i 0) None (Some i))', {43, 46}),
        ('invent-closing-zero', 'axtagCloseFrom', '    None', '    (Some 0)', {33, 41, 42, 48, 49, 53}),
        ('lose-end-fallback', 'checkOneAxtag', '((None) (strLen content))', '((None) 0)', {33, 53}),
    ]
    for label, function, before, after, failures in controls:
        start = source.index('(pub fn (' + function + ' ')
        end = source.index('\n\n', start)
        body = source[start:end]
        assert body.count(before) == 1, (label, 'mutation anchor changed')
        changed = source[:start] + body.replace(before, after) + source[end:]
        rows = native(label, 0, changed, fixture).splitlines()
        assert len(rows) == 53, (label, rows)
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
        ('raw-delimiter', '(strLen (axtagListValue "key(value)" 3))', 'AX3004'),
        ('wrong-payload', '(strLen (axtagListValue "key(value)" (Some "3")))', 'AX3004'),
        ('missing-none', '(match (strFindByte "key" 40 0) ((Some opening) (strLen (axtagListValue "key" (Some opening)))))', 'AX3005'),
        ('raw-closing', '(axtagCloseAt "key(value)")', 'AX3004'),
        ('closing-missing-none', '(match (axtagCloseAt "key(value)") ((Some closing) closing))', 'AX3005'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import typecheck)\n(import Str)\n(import Vec)\n(:: bad Int)\n(fn (bad) ' + expression + ')\n')
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
        with tempfile.TemporaryDirectory(prefix='axiom-axtag-delimiters-') as directory:
            check(args.axiom.resolve(), root, Path(directory), args.baseline_source)


if __name__ == '__main__':
    main()
