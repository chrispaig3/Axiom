#!/usr/bin/env python3
"""Check named Show outcomes, cache bookkeeping and exact refusal diagnostics."""
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
    fixture = (root / 'tests/selfhost/typecheck-show-outcomes.axp').read_text()
    diagnostics = (root / 'tests/tools/checker-renderer-diagnostics.axp').read_text()
    expected = ''.join(f'{i} true\n' for i in range(1, 77))
    golden = (root / 'tests/tools/checker-renderer-options.golden').read_text()
    report = {
        'builder': str(compiler),
        'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'diagnostic_sha256': hashlib.sha256(golden.encode()).hexdigest(),
        'configurations': [], 'controls': [], 'refusals': [],
        'limits': ['Host O0/O2 tests cover Show result and cache bookkeeping, not memory-model qualification.',
                   'Rendering generation, call emission and ownership/lifetime inference are unchanged.'],
    }

    def modules(label, text):
        folder = work / (label + '-modules/core')
        folder.mkdir(parents=True)
        for path in (snapshot / 'core').iterdir():
            destination = folder / path.name
            if path.name == 'typecheck.ax':
                # Test-only read access to the private cache; production visibility is unchanged.
                destination.write_text(text + '\n(pub :: showOutcomeTestCache (-> TC Nodes))\n'
                                       '(pub fn (showOutcomeTestCache tc) (tcFormatChecked tc))\n')
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
        report['configurations'].append({'opt': level, 'allocation_poison': True, 'cases': 76,
                                         'diagnostic_cases': 5, 'diagnostic_bytes': len(golden.encode())})
        print(f'ok   Show outcomes: 76 cases and 5 exact renderer diagnostics O{level}', flush=True)

    existing = (root / 'tests/tools/checker-renderer-options.axp').read_text()
    assert native('existing-consumer', 0, source, existing) == ''.join(f'{i} true\n' for i in range(1, 51))
    report['existing_consumer_cases'] = 50
    controls = [
        ('unsupported-as-refused', 'showResolve',
         '(showUnknownDiag tc arg ty)\n              ShowUnavailable)',
         '(showUnknownDiag tc arg ty)\n              ShowRefused)', {3}),
        ('poison-as-unavailable', 'showResolve',
         '        ShowRefused\n        ; A subtype',
         '        ShowUnavailable\n        ; A subtype', {4, 35}),
        ('failed-helper-as-rewritten', 'showRewriteTo',
         '    ShowRefused))', '    ShowRewritten))', {10}),
        ('splice-as-rewrite', 'showSplice', '    ShowSpliced', '    ShowRewritten', {14, 44}),
        ('cache-wrong-expression', 'showBuiltin',
         '((ShowRewritten) (showCheckRewritten tc e arg at))',
         '((ShowRewritten) (showCheckRewritten tc e e at))', {24, 26, 37}),
        ('lose-cache-pop', 'showCheckRewritten',
         '            (vecPop cache)\n            (vecPop cache)',
         '            (vecPop cache)', {23, 25, 27, 38, 43}),
        ('lose-reserved-head-guard', 'showCheckRewritten',
         '(if (if (== (nodeTag e) TAG_E_APP)', '(if (if false', {42}),
        ('drop-unavailable-diagnostic', 'showBuiltin',
         '(showNoRenderingDiag tc arg at)', '0', {32, 33}),
        ('claim-qualified-head', 'showIsHead', '(strEq hname "format#")',
         '(strEq (bareOf hname) "format#")', {48}),
        ('lose-seen-name', 'showSeenName', '      true', '      false', {54, 55, 58, 62}),
        ('invent-seen-name', 'showSeenName', '    false', '    true', {53, 56, 57, 59, 60, 61}),
        ('lose-constructor-fields', 'showCtorsHaveFields', '      true', '      false', {65, 66}),
        ('invent-constructor-fields', 'showCtorsHaveFields', '    false', '    true', {63, 64, 67, 68, 75}),
        ('omit-field-guard', 'showGuarded', '(if (! hasFields)', '(if true', {71, 72, 73}),
        ('invent-field-guard', 'showGuarded', '(if (! hasFields)', '(if false', {69, 70, 72, 74}),
    ]
    for label, function, before, after, failures in controls:
        start = source.index('(pub fn (' + function + ' ')
        end = source.index('\n\n', start)
        body = source[start:end]
        assert body.count(before) == 1, (label, 'mutation anchor changed')
        changed = source[:start] + body.replace(before, after) + source[end:]
        rows = native(label, 0, changed, fixture).splitlines()
        assert len(rows) == 76, (label, rows)
        observed = set()
        for i, row in enumerate(rows, 1):
            assert row in (f'{i} true', f'{i} false'), (label, row)
            if row.endswith(' false'):
                observed.add(i)
        assert observed == failures, (label, observed, failures)
        report['controls'].append({'name': label, 'failed_cases': sorted(observed)})
        print(f'ok   {label}: actual mutant fails {sorted(observed)}', flush=True)

    env = modules('refusals', source)
    for label, declaration, code in [
        ('raw-status', '(:: bad Int) (fn (bad) ShowRewritten)', 'AX3004'),
        ('raw-head-predicate', '(:: bad Int) (fn (bad) (showIsHead "format#"))', 'AX3004'),
        ('raw-seen-predicate', '(:: bad Int) (fn (bad) (showSeenName vecNew "x" 0))', 'AX3004'),
        ('raw-fields-predicate', '(:: bad Int) (fn (bad) (showCtorsHaveFields vecNew 0))', 'AX3004'),
        ('raw-has-fields', '(:: bad (-> TC ASTNode (Option ASTNode))) '
         '(fn (bad tc body) (showGuarded tc body 1 0))', 'AX3004'),
        ('missing-refusal', '(:: bad (-> ShowOutcome Int)) (fn (bad value) '
         '(match value ((ShowUnavailable) 1) ((ShowRewritten) 2) ((ShowSpliced) 3)))', 'AX3005'),
        ('raw-resolver', '(:: bad (-> TC ASTNode ASTNode ASTNode ASTNode Int)) '
         '(fn (bad tc expression head argument ty) (showResolve tc expression head argument ty))', 'AX3004'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import core)\n(import typecheck)\n(import Vec)\n' + declaration + '\n')
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
        with tempfile.TemporaryDirectory(prefix='axiom-show-outcomes-') as directory:
            check(args.axiom.resolve(), root, Path(directory), args.baseline_source)


if __name__ == '__main__':
    main()
