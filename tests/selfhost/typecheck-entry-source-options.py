#!/usr/bin/env python3
"""Check optional entry source, quick-fix fallback and exact diagnostic bytes."""
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
    source = (root / 'core/typecheck.ax').read_text()
    fixture = (root / 'tests/selfhost/typecheck-entry-source-options.axp').read_text()
    diagnostics = (root / 'tests/selfhost/typecheck-entry-source-diagnostics.axp').read_text()
    expected = [f'{i} true' for i in range(1, 25)]
    report = {'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
              'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
              'diagnostic_fixture_sha256': hashlib.sha256(diagnostics.encode()).hexdigest(),
              'configurations': [], 'controls': [], 'refusals': [],
              'limits': ['Host O0/O2 allocation poisoning; not target-wide qualification.',
                         'Inference, effect inference and lifetime algorithms are unchanged.',
                         'Full diagnostic reports still require their entry-unit contract.']}

    def modules(label, text):
        folder = work / (label + '-modules/core'); folder.mkdir(parents=True, exist_ok=True)
        for path in (root / 'core').iterdir():
            dest = folder / path.name
            if path.name == 'typecheck.ax':
                dest.write_text(text)
            elif not dest.exists():
                dest.symlink_to(path, target_is_directory=path.is_dir())
        return dict(os.environ, AXIOM_PATH=str(folder), AXIOM_STDLIB=str(root / 'stdlib'))

    def native(label, level, text, program):
        local = modules(label, text)
        path = work / (label + '.ax'); path.write_text(program)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(path), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work/(label + '-build.stdout'), stderr=work/(label + '-build.stderr'), timeout=240)
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work/(label + '.stderr'), timeout=30)
        assert not (work/(label + '.stderr')).read_bytes(), label
        return output

    golden = root / 'tests/selfhost/typecheck-entry-source-diagnostics.golden.json'
    if baseline:
        old = baseline.read_text()
        rendered = native('baseline-diagnostics', 0, old, diagnostics).read_bytes()
        if golden.exists():
            assert rendered == json.loads(golden.read_text()).encode(), 'baseline golden differs'
        else:
            golden.write_text(json.dumps(rendered.decode(), ensure_ascii=True) + '\n')
        report['baseline_source_sha256'] = hashlib.sha256(old.encode()).hexdigest()
    assert golden.exists(), 'original diagnostic bytes must be recorded first'
    expected_bytes = json.loads(golden.read_text()).encode()
    for level in (0, 2):
        check_output(native('positive-O' + str(level), level, source, fixture), expected)
        actual = native('diagnostics-O' + str(level), level, source, diagnostics).read_bytes()
        assert actual == expected_bytes, ('diagnostics differ', level)
        report['configurations'].append({'optimization': level, 'poison': True, 'cases': 24,
                                         'diagnostic_bytes': len(expected_bytes)})
        print(f'ok   entry source: 24 outcomes and {len(expected_bytes)} exact diagnostic bytes O{level}', flush=True)
    start = source.index('(pub fn (tcEntrySrc tc)')
    end = source.index('; The byte just past', start)
    body = source[start:end]
    for label, before, after, failures in [
        ('discard-present-source', '(Some (unitSrc (vecGet units 0)))', 'None', {2, 3, 7, 13, 17, 21}),
        ('allow-imported-edits', '(!= (tcCurUnit tc) 0)', 'false', {4, 5, 16, 20, 24}),
        ('discard-present-empty', '(Some (unitSrc (vecGet units 0)))',
         '(if (== (strLen (unitSrc (vecGet units 0))) 0) None (Some (unitSrc (vecGet units 0))))', {2}),
        ('fabricate-missing-source', '(if (== (vecLen units) 0)\n        None',
         '(if (== (vecLen units) 0)\n        (Some "")', {1, 12}),
        ('duplicate-source-share', '(Some (unitSrc (vecGet units 0)))',
         '{ (let text (unitSrc (vecGet units 0))) (__retainref text) (Some text) }', {9, 11}),
    ]:
        changed = source[:start] + replace_once(body, before, after, label) + source[end:]
        failed = check_output(native(label, 0, changed, fixture), expected, required_failures=failures)
        report['controls'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: {sorted(failed)}', flush=True)
    local = modules('refusals', source)
    for label, result_type, expression, code in [
        ('raw-source-result', 'String', '(tcEntrySrc tc)', 'AX3004'),
        ('unchecked-source', 'Int', '(strLen (tcEntrySrc tc))', 'AX3004'),
        ('missing-none', 'Int', '(match (tcEntrySrc tc) ((Some source) (strLen source)))', 'AX3005'),
        ('binding-outside-success', 'Int', '(if (let (Some source) (tcEntrySrc tc)) 0 (strLen source))', 'AX3001'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import typecheck) (import Str)\n(:: bad (-> TC ' + result_type + '))\n(fn (bad tc) ' + expression + ')\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)], env=local,
                                capture_output=True, text=True, timeout=90)
        (work/(label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode != 0 and len(errors) == 1 and errors[0].startswith('E ' + code + ' '), (label, result)
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    report['diagnostic_sha256'] = hashlib.sha256(expected_bytes).hexdigest()
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--baseline-source', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    work = args.work or Path(tempfile.mkdtemp(prefix='axiom-entry-source-'))
    work.mkdir(parents=True, exist_ok=True)
    check(args.axiom.resolve(), root, work, args.baseline_source)


if __name__ == '__main__':
    main()
