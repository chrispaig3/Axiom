#!/usr/bin/env python3
"""Check optional diagnostic labels and paired edits across all renderers.

The rendering golden was captured from unchanged 00d6c04b, before this port.
"""
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


def check(compiler, root, work, baseline=None):
    names = ('diag.ax', 'render.ax', 'lsp.ax')
    source = {name: (root / 'core' / name).read_text() for name in names}
    fixture = (root / 'tests/selfhost/diagnostic-option-fields.axp').read_text()
    rendering = (root / 'tests/selfhost/diagnostic-option-rendering.axp').read_text()
    expected = [f'{i} true' for i in range(1, 35)]
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'source_sha256': {n: hashlib.sha256(t.encode()).hexdigest() for n, t in source.items()},
              'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
              'configurations': [], 'controls': [], 'refusals': [],
              'limits': ['Host O0/O2 native allocation poisoning, not target-wide qualification.',
                         'Packed spans and unit indexes retain the existing numeric wire protocol.',
                         'No held lifetime analysis work is read, changed or validated.']}

    def modules(label, texts):
        folder = work / (label + '-modules/core')
        folder.mkdir(parents=True, exist_ok=True)
        for path in (root / 'core').iterdir():
            dest = folder / path.name
            if path.name in texts:
                dest.write_text(texts[path.name])
            elif not dest.exists():
                dest.symlink_to(path, target_is_directory=path.is_dir())
        return dict(env, AXIOM_PATH=str(folder))

    def native(label, level, texts, program):
        local = modules(label, texts)
        path = work / (label + '.ax')
        path.write_text(program)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(path), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '-build.stdout'), stderr=work / (label + '-build.stderr'), timeout=240)
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        return output

    golden = root / 'tests/selfhost/diagnostic-option-rendering.golden.json'
    if baseline:
        old = {name: (baseline / name).read_text() for name in names}
        output = native('baseline-rendering', 0, old, rendering)
        if golden.exists():
            assert output.read_bytes() == json.loads(golden.read_text()).encode(), 'baseline disagrees with recorded output'
        else:
            golden.write_text(json.dumps(output.read_text(), ensure_ascii=True) + '\n')
    assert golden.exists(), 'rendering baseline is required'
    expected_rendering = json.loads(golden.read_text()).encode()
    for level in (0, 2):
        check_output(native('positive-O' + str(level), level, source, fixture), expected)
        rendered = native('rendering-O' + str(level), level, source, rendering)
        assert rendered.read_bytes() == expected_rendering, ('rendering differs', level)
        report['configurations'].append({'optimization': level, 'poison': True, 'cases': 34, 'rendered_bytes': len(expected_rendering)})
        print(f'ok   diagnostic fields: 34 outcomes and {len(expected_rendering)} exact renderer bytes O{level}', flush=True)
    report['rendering_sha256'] = hashlib.sha256(expected_rendering).hexdigest()
    controls = [
        ('discard-present-empty-label', ':label label', ':label None', {2}),
        ('drop-empty-deletion', ':fix\n        (if (== fixSpan 0)',
         ':fix\n        (if (|| (== fixSpan 0) (== (strLen fixText) 0))', {15, 16, 19, 20, 32}),
        ('skip-fix-disarm', '(set h.fix None)', '0', {27, 28, 31}),
    ]
    for label, before, after, failures in controls:
        changed = dict(source)
        changed['diag.ax'] = replace_once(source['diag.ax'], before, after, label)
        if label == 'drop-empty-deletion':
            changed['diag.ax'] = replace_once(changed['diag.ax'],
                '(if (== span 0)\n    None\n    (Some (DFix',
                '(if (|| (== span 0) (== (strLen text) 0))\n    None\n    (Some (DFix',
                'drop constructor deletion')
        failed = check_output(native(label, 0, changed, fixture), expected, required_failures=failures)
        report['controls'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: {sorted(failed)}', flush=True)
    mutated_fixture = replace_once(fixture, '(fn (retireLabel text)\n  {',
                                   '(fn (retireLabel text)\n  { (__retainref text)', 'extra label share')
    failed = check_output(native('duplicate-label-share', 0, source, mutated_fixture), expected, required_failures={6})
    report['controls'].append({'name': 'duplicate-label-share', 'failed_cases': sorted(failed)})
    print(f'ok   counterexample duplicate-label-share: {sorted(failed)}', flush=True)
    local = modules('refusal', source)
    for label, body, code in [
        ('raw-label', '(:: bad (-> Diag Int)) (fn (bad d) d.label)', 'AX3004'),
        ('string-label', '(:: bad Diag) (fn (bad) (mkDiagBase 0 "AX3001" "probe" 0 "m" "label"))', 'AX3004'),
        ('raw-fix', '(:: bad DHelp) (fn (bad) (DHelp :msg "fix" :fix 0))', 'AX3004'),
        ('optional-replacement', '(:: bad (-> Diag Int String)) (fn (bad d i) (diagHelpFixText d i))', 'AX3004'),
        ('missing-label-case', '(:: bad (-> Diag String)) (fn (bad d) (match (diagLabel d) ((Some text) text)))', 'AX3005'),
        ('missing-fix-case', '(:: bad (-> Diag Int String)) (fn (bad d i) (match (diagHelpFix d i) ((Some fix) fix.text)))', 'AX3005'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import diag)\n' + body + '\n(:: main Int) (fn (main) 0)\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)], env=local,
                                capture_output=True, text=True, timeout=120)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and ('E ' + code + ' ') in errors[0], (label, result)
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--baseline-core', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), root, args.work.resolve(), args.baseline_core)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-diagnostic-options-') as directory:
            check(args.axiom.resolve(), root, Path(directory), args.baseline_core)


if __name__ == '__main__':
    main()
