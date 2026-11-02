#!/usr/bin/env python3
"""Check owning optional float-flag metadata and checked-fact precedence."""
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
BRIDGE = '''
(pub :: probeSignatureFlags (-> CG String (Option Ints)))
(pub fn (probeSignatureFlags cg name) (functionFlags cg name))
(pub :: probeSignatureChecked (-> CG FunctionTypes CG))
(pub fn (probeSignatureChecked cg types) (cgSetFunctionFloats cg (Some (functionFloatIndex types))))
'''


def check(compiler, root, work):
    source = (root / 'core/codegen.ax').read_text()
    fixture = (root / 'tests/selfhost/emitter-signature-flags.axp').read_text()
    expected = [f'{i} true' for i in range(1, 25)]
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {
        'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'configurations': [], 'counterexamples': [], 'refusals': [],
        'invariants': [
            {'invariant': 'Unknown extern flags and known empty flags are distinct typed states.',
             'enforcement': 'FSig.flags Option Ints; scanFloatSigs Some and scanExternSigs None; cases 1-8,12-20,23,24.',
             'counterexamples': ['discard-present-flags', 'extern-as-known-empty']},
            {'invariant': 'Checked float metadata wins over written/extern fallback in the existing order.',
             'enforcement': 'functionFlags checkedFloatFlags-first branch; cases 19-23.',
             'counterexamples': ['discard-checked-precedence']},
            {'invariant': 'A signature owns its optional flags until retirement, and a returned Option owns its vector.',
             'enforcement': 'Typed owning FSig.flags field and getter; cases 9-11.',
             'counterexamples': ['duplicate-flags-share']},
        ],
        'known_limits': ['Selected host native O0/O2 with allocation poisoning; no Windows execution claim.',
                         'FSig.sigTy parser-nil, numeric masks/arity, TypeEntry metadata and other raw boundaries remain separate tasks.',
                         'No held work or lifetime traversal/fixpoint/enforcement algorithms are read, changed or validated.',
                         'Focused evidence does not establish global soundness, Rust parity or certification.'],
    }

    def build_run(label, level, text, program=fixture, failures=()):
        modules = work / (label + '-modules/core')
        modules.mkdir(parents=True, exist_ok=True)
        (modules / 'codegen.ax').write_text(text + BRIDGE)
        local = dict(env, AXIOM_PATH=os.pathsep.join((str(modules), str(root / 'core'))))
        path = work / (label + '.ax')
        path.write_text(program)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(path), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '-build.stdout'), stderr=work / (label + '-build.stderr'))
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        return check_output(output, expected, required_failures=failures)

    for level in (0, 2):
        build_run('positive-O' + str(level), level, source)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True,
                                         'cases': 24, 'status': 'passed'})
        print(f'ok   optional signature flags: 24 outcomes at O{level} poison', flush=True)
    discarded = replace_once(source, '(fn (fsigFlags e)\n  e.flags)',
                              '(fn (fsigFlags e)\n  None)', 'flags presence control')
    known_extern = replace_once(source, ':flags None', ':flags (Some vecNew)', 'extern unknown control')
    precedence = replace_once(source, '(if (let (Some flags) (checkedFloatFlags cg name))',
                               '(if (let (Some flags) (None))', 'checked precedence control')
    for label, text, failures in [
        ('discard-present-flags', discarded, {4, 6, 8}),
        ('extern-as-known-empty', known_extern, {17, 19}),
        ('discard-checked-precedence', precedence, {21, 22}),
    ]:
        failed = build_run(label, 0, text, failures=failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: cases {sorted(failed)} fail', flush=True)
    changed_fixture = replace_once(fixture, '(fn (retireFlags flags)\n  {',
                                   '(fn (retireFlags flags)\n  {\n    (__retainref flags)', 'flags share control')
    failed = build_run('duplicate-flags-share', 0, source, changed_fixture, {10})
    report['counterexamples'].append({'name': 'duplicate-flags-share', 'failed_cases': sorted(failed)})
    print(f'ok   counterexample duplicate-flags-share: cases {sorted(failed)} fail', flush=True)
    local = dict(env, AXIOM_PATH=os.pathsep.join((str(work / 'positive-O0-modules/core'), str(root / 'core'))))
    for label, body, code in [
        ('raw-flags-vector', '(:: bad (-> FSig Ints)) (fn (bad entry) entry.flags)', 'AX3004'),
        ('raw-flags-field', '(:: bad (-> FSig Int)) (fn (bad entry) (vecLen entry.flags))', 'AX3004'),
        ('missing-flags-none', '(:: bad (-> FSig Int)) (fn (bad entry) (match entry.flags ((Some flags) (vecLen flags))))', 'AX3005'),
    ]:
        program = work / (label + '.ax')
        program.write_text('(import codegen)\n(import core)\n(import Vec)\n' + body + '\n(:: main Int)\n(fn (main) 0)\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(program)],
                                cwd=root, env=local, capture_output=True, text=True, timeout=180)
        (work / (label + '.stdout')).write_text(result.stdout)
        (work / (label + '.stderr')).write_text(result.stderr)
        assert result.returncode == 1 and code in result.stderr, (label, result.returncode, result.stderr)
        report['refusals'].append({'name': label, 'diagnostic': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'signature-flags-report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), root, args.work.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-signature-flags-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
