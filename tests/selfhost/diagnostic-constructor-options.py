#!/usr/bin/env python3
"""Check typed diagnostic construction, absence and payload retirement."""
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


def check(compiler, root, work):
    source = (root / 'core/diag.ax').read_text()
    fixture = (root / 'tests/selfhost/diagnostic-constructor-options.axp').read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    expected = [f'{i} true' for i in range(1, 32)]
    report = {'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'diag_sha256': hashlib.sha256(source.encode()).hexdigest(),
              'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
              'configurations': [], 'controls': [], 'refusals': [],
              'limits': ['Host native O0/O2 allocation poisoning; not target-wide qualification.',
                         'Packed spans and unit indexes retain the existing numeric wire protocol.',
                         'Diagnostic arguments only; no lifetime or region analysis algorithms change.']}

    def modules(label, text):
        folder = work / (label + '-modules/core')
        folder.mkdir(parents=True, exist_ok=True)
        for path in (root / 'core').iterdir():
            dest = folder / path.name
            if path.name == 'diag.ax':
                dest.write_text(text)
            elif not dest.exists():
                dest.symlink_to(path, target_is_directory=path.is_dir())
        return dict(env, AXIOM_PATH=str(folder))

    def native(label, level, text, program):
        local = modules(label, text)
        path = work / (label + '.ax')
        path.write_text(program)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(path), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '-build.stdout'), stderr=work / (label + '-build.stderr'), timeout=240)
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        return output

    for level in (0, 2):
        check_output(native('positive-O' + str(level), level, source, fixture), expected)
        report['configurations'].append({'optimization': level, 'poison': True, 'cases': 31})
        print(f'ok   diagnostic constructors: 31 outcomes O{level}', flush=True)
    controls = [
        ('drop-empty-help', '(diagAddHelp d text))\n    d\n  })\n\n;@axiom:restrict(no-io,no-foreign)\n(pub :: mkDiagFix',
         '(if (> (strLen text) 0) (diagAddHelp d text)))\n    d\n  })\n\n;@axiom:restrict(no-io,no-foreign)\n(pub :: mkDiagFix', {5}),
        ('drop-related', '(diagAddSecondaryIn d label.span label.msg label.unit)', '0', {8, 24}),
        ('admit-zero-related', '(if (== span 0)\n    None\n    (Some (DLabel',
         '(if false\n    None\n    (Some (DLabel', {7}),
        ('admit-zero-fix', '(if (== span 0)\n    None\n    (Some (DFix',
         '(if false\n    None\n    (Some (DFix', {12}),
    ]
    for label, before, after, failures in controls:
        changed = replace_once(source, before, after, label)
        failed = check_output(native(label, 0, changed, fixture), expected, required_failures=failures)
        report['controls'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: {sorted(failed)}', flush=True)
    changed = replace_once(fixture, '(fn (retireInputs related help replacement note)\n  {',
                           '(fn (retireInputs related help replacement note)\n  {\n    (__retainref replacement)', 'duplicate input share')
    failed = check_output(native('duplicate-input-share', 0, source, changed), expected, required_failures={28})
    report['controls'].append({'name': 'duplicate-input-share', 'failed_cases': sorted(failed)})
    print(f'ok   counterexample duplicate-input-share: {sorted(failed)}', flush=True)
    local = modules('refusals', source)
    for label, body, code in [
        ('raw-related', '(:: bad Diag) (fn (bad) (mkDiag 0 "AX3001" "probe" 0 "message" 0 None))', 'AX3004'),
        ('bare-related', '(:: bad Diag) (fn (bad) (mkDiag 0 "AX3001" "probe" 0 "message" (DLabel :span 0 :msg "m" :unit -1) None))', 'AX3004'),
        ('raw-help', '(:: bad Diag) (fn (bad) (mkDiag 0 "AX3001" "probe" 0 "message" None "help"))', 'AX3004'),
        ('raw-note', '(:: bad Diag) (fn (bad) (mkDiagNote 0 "AX3001" "probe" 0 "message" None None 0))', 'AX3004'),
        ('raw-fix', '(:: bad Diag) (fn (bad) (mkDiagFix 0 "AX3001" "probe" 0 "message" None "help" 0))', 'AX3004'),
        ('raw-replacement', '(:: bad (Option DFix)) (fn (bad) (diagFix 0 0))', 'AX3004'),
        ('missing-related-case', '(:: bad (-> Int String)) (fn (bad span) (match (diagRelated span "related") ((Some label) label.msg)))', 'AX3005'),
        ('missing-fix-case', '(:: bad (-> Int String)) (fn (bad span) (match (diagFix span "replace") ((Some fix) fix.text)))', 'AX3005'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import diag)\n' + body + '\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)], env=local,
                                text=True, capture_output=True, timeout=90)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode != 0 and len(errors) == 1 and errors[0].startswith('E ' + code + ' '), (label, result)
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    work = args.work or Path(tempfile.mkdtemp(prefix='axiom-diag-constructors-'))
    work.mkdir(parents=True, exist_ok=True)
    check(args.axiom.resolve(), root, work)


if __name__ == '__main__':
    main()
