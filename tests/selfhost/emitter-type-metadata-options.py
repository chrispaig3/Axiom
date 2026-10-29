#!/usr/bin/env python3
"""Check optional emitter field metadata, ownership, witnesses and layout refusal."""
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
(pub :: probeCtorTypes (-> TypeEntry (Option Nodes)))
(pub fn (probeCtorTypes entry) (ctorFieldTypes entry))
(pub :: probeCtorWords (-> TypeEntry (Option Int)))
(pub fn (probeCtorWords entry) (ctorPayloadWords entry))
(pub :: probeRequireFields (-> TypeEntry Int))
;@axiom:effect(io)
(pub fn (probeRequireFields entry) (vecLen (requireStructFields entry)))
'''


def change_function(source, name, before, after):
    prefix = '(pub fn (' + name + ' ' if '(pub fn (' + name + ' ' in source else '(fn (' + name + ' '
    start = source.index(prefix)
    end = source.index('\n\n', start)
    return source[:start] + replace_once(source[start:end], before, after, name) + source[end:]


def check(compiler, root, work):
    source = (root / 'core/codegen.ax').read_text()
    fixture = (root / 'tests/selfhost/emitter-type-metadata-options.axp').read_text()
    expected = [f'{i} true' for i in range(1, 67)]
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {
        'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'configurations': [], 'counterexamples': [], 'refusals': [],
        'invariants': [
            {'invariant': 'Missing metadata, present-empty vectors and missing field types remain distinct typed states.',
             'enforcement': 'TypeEntry Option fields and Option queries; cases 1-14,30-43,51-55,63-66.',
             'counterexamples': ['discard-empty-names', 'discard-field-types', 'unnormalized-struct-fields']},
            {'invariant': 'Valid poison and wildcard nodes survive; scalar/reference and dynamic evidence decisions retain exact meanings.',
             'enforcement': 'fieldTypeNode, fieldRetainCode and ctorFieldParks; cases 15-29,48,49,56-59.',
             'counterexamples': ['discard-poison-type', 'lost-dynamic-witness']},
            {'invariant': 'Metadata owns vector and AST/String child shares, and remains shared through mutation and return.',
             'enforcement': 'Typed TypeEntry fields, getters and constructors; cases 44-47,50,60-62.',
             'counterexamples': ['duplicate-metadata-share']},
            {'invariant': 'Pure unavailable-layout queries return None; emission requires metadata and refuses absence with AX4002.',
             'enforcement': 'ctorPayloadWords/ctorShapeConst Options and require* emission helpers; cases 34-37,52-55 and native missing-layout modes.',
             'counterexamples': ['unchecked-required-layout']},
        ],
        'known_limits': ['Selected host native O0/O2 with allocation poisoning; no Windows runtime claim.',
                         'Parser packed constructor/type/name slots remain explicit storage boundaries; nil type payloads normalize only at that read.',
                         'Raw inert field-result nodes, FSig.sigTy and numeric arity/mask/index protocols remain separate inventory items.',
                         'Shape arithmetic, evidence masks and flow/ownership/lifetime algorithms retain their prior rules.',
                         'No held work is read, changed or validated; no global soundness, Rust parity or certification claim.'],
    }

    def build_run(label, level, text, failures=(), expected_fault=False):
        modules = work / (label + '-modules')
        modules.mkdir(exist_ok=True)
        (modules / 'codegen.ax').write_text(text + BRIDGE)
        local = dict(env, AXIOM_PATH=os.pathsep.join((str(modules), str(root / 'core'))))
        program = work / (label + '.ax')
        program.write_text(fixture)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(program), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '-build.stdout'), stderr=work / (label + '-build.stderr'), timeout=240)
        output = work / (label + '.stdout')
        if expected_fault:
            result = subprocess.run([str(binary)], env=local, capture_output=True, text=True, timeout=30)
            output.write_text(result.stdout)
            (work / (label + '.stderr')).write_text(result.stderr)
            # The deliberately restored null-vector reader faults only after
            # all preceding 64 outcomes pass. Do not accept arbitrary failures.
            assert result.returncode in {-11, 3221225477, -1073741819}, (label, result)
            assert result.stdout == "".join(line + "\n" for line in expected[:64]) and not result.stderr, (label, result)
            return {'native_exit': result.returncode, 'preceding_passed_cases': 64,
                    'unreached_cases': [65, 66]}, binary, local
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        observed = check_output(output, expected, required_failures=failures)
        return observed, binary, local

    def layout_outcomes(binary, local, label, expected_status=3):
        results = []
        for name, suffix, phrase in [('fields', [], 'struct entry has no field metadata: Case'),
                                     ('shape', ['shape'], 'constructor entry has no layout metadata: Case')]:
            result = subprocess.run([str(binary), '--diagnostic-format=ai', *suffix],
                                    env=local, capture_output=True, text=True, timeout=30)
            (work / (label + '-' + name + '.stdout')).write_text(result.stdout)
            (work / (label + '-' + name + '.stderr')).write_text(result.stderr)
            assert result.returncode == expected_status and not result.stdout, (label, name, result)
            if expected_status == 3:
                assert 'E AX4002 ' in result.stderr and phrase in result.stderr, (label, name, result)
            else:
                assert not result.stderr, (label, name, result)
            results.append(name)
        return results

    for level in (0, 2):
        _, binary, local = build_run('positive-O' + str(level), level, source)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True,
                                         'cases': 66, 'status': 'passed'})
        for name in layout_outcomes(binary, local, 'positive-O' + str(level)):
            report['refusals'].append({'name': 'missing-required-' + name, 'optimization': level,
                                        'diagnostic': 'AX4002', 'status': 3})
        print(f'ok   optional field metadata: 66 outcomes and two AX4002 refusals at O{level} poison', flush=True)
    empty = change_function(source, 'eFieldNamesVec', '  e.fieldNames',
                            '  (match e.fieldNames ((None) None) ((Some names) (if (== (vecLen names) 0) None (Some names))))')
    missing = change_function(source, 'fieldTypeNode', '(if (nodeSame ty nilNode)', '(if true')
    poison = change_function(source, 'fieldTypeNode', '(if (nodeSame ty nilNode)',
                             '(if (|| (nodeSame ty nilNode) (== (nodeTag ty) TAG_T_ERR))')
    witness = change_function(source, 'fieldRetainCode', '(if (>= wv 2)\n                          wv',
                              '(if (>= wv 2)\n                          1')
    owner = change_function(source, 'addTypeNamed', '(let nl (strLen name))',
                            '(let nl (strLen name))\n    (__retainref fieldNames)\n    (__retainref fieldTys)')
    normalizer = change_function(source, 'scanOne', '(let fields (nodeStructFields node))',
                                 '(let fields (nodeBChildren node))')
    for label, text, failures in [
        ('discard-empty-names', empty, {8}),
        ('discard-field-types', missing, {12, 15, 19, 20, 31, 48}),
        ('discard-poison-type', poison, {19, 48}),
        ('lost-dynamic-witness', witness, {23}),
        ('duplicate-metadata-share', owner, {44, 45}),
    ]:
        observed, _, _ = build_run(label, 0, text, failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(observed)})
        print(f'ok   counterexample {label}: cases {sorted(observed)} fail', flush=True)
    fault, _, _ = build_run('unnormalized-struct-fields', 0, normalizer, expected_fault=True)
    report['counterexamples'].append({'name': 'unnormalized-struct-fields', **fault})
    print(f"ok   counterexample unnormalized-struct-fields: native fault {fault['native_exit']} after preceding64 pass", flush=True)
    unchecked = source
    for name, message in [('requireStructFields', 'struct entry has no field metadata: '),
                          ('requireCtorWords', 'constructor entry has no layout metadata: '),
                          ('requireCtorShapeConst', 'constructor entry has no shape metadata: ')]:
        unchecked = change_function(unchecked, name,
                                    '(dieCodegenDiag ' + json.dumps(message) + ' (eName entry))',
                                    '(writeStr stderr "")')
    _, binary, local = build_run('unchecked-required-layout', 0, unchecked)
    layout_outcomes(binary, local, 'unchecked-required-layout', expected_status=0)
    report['counterexamples'].append({'name': 'unchecked-required-layout', 'invalid_layout_modes_accepted': ['fields', 'shape']})
    print('ok   counterexample unchecked-required-layout: both missing-layout modes lose AX4002', flush=True)
    local = dict(env, AXIOM_PATH=os.pathsep.join((str(work / 'positive-O0-modules'), str(root / 'core'))))
    for label, body, code in [
        ('raw-metadata-vector', '(:: bad (-> TypeEntry Nodes)) (fn (bad entry) (eStructFields entry))', 'AX3004'),
        ('raw-field-type', '(:: bad (-> TypeEntry ASTNode)) (fn (bad entry) (fieldTypeNode entry 0))', 'AX3004'),
        ('missing-field-none', '(:: bad (-> TypeEntry Int)) (fn (bad entry) (match (fieldTypeNode entry 0) ((Some ty) 0)))', 'AX3005'),
        ('missing-layout-none', '(:: bad (-> TypeEntry Int)) (fn (bad entry) (match (ctorShapeConst newCG entry) ((Some shape) shape)))', 'AX3005'),
    ]:
        program = work / (label + '.ax')
        program.write_text('(import codegen)\n(import parser)\n(import core)\n' + body + '\n(:: main Int)\n(fn (main) 0)\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(program)],
                                env=local, cwd=root, capture_output=True, text=True, timeout=180)
        (work / (label + '.stdout')).write_text(result.stdout)
        (work / (label + '.stderr')).write_text(result.stderr)
        assert result.returncode == 1 and code in result.stderr, (label, result.returncode, result.stderr)
        report['refusals'].append({'name': label, 'diagnostic': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'type-metadata-options-report.json').write_text(json.dumps(report, indent=2) + '\n')


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
        with tempfile.TemporaryDirectory(prefix='axiom-type-metadata-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
