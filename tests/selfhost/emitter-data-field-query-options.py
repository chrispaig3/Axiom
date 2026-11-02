#!/usr/bin/env python3
"""Check optional data-field descriptors, indices and missing-field refusal."""
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
check_output = SUPPORT['check_output']
change_function = runpy.run_path(str(Path(__file__).with_name('emitter-type-metadata-options.py')))['change_function']
BRIDGE = '''
(pub :: probeDataFieldOf (-> TypeEntry String (Option ASTNode)))
(pub fn (probeDataFieldOf entry name) (dataFieldOfEntry entry name))
(pub :: probeResolveDataField (-> (Vec TypeEntry) ASTNode (Option ASTNode)))
(pub fn (probeResolveDataField types node) (resolveDataField types node))
'''
MISSING_FIELD_DIAGNOSTIC = (
    'E AX4002 <codegen>:- codegen-failure "unknown struct field: missing" '
    '?"this is a compiler bug: the check that should have refused this program did not run"\n'
)


def check(compiler, root, work):
    source = (root / 'core/codegen.ax').read_text()
    fixture = (root / 'tests/selfhost/emitter-data-field-query-options.axp').read_text()
    expected = [f'{i} true' for i in range(1, 35)]
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {
        'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'configurations': [], 'counterexamples': [], 'refusals': [],
        'invariants': [
            {'invariant': 'Missing fields and exhausted searches return None; index zero and empty names remain present.',
             'enforcement': 'Typed dataFieldIndexIn and descriptor results; cases 1-14,30,33.',
             'counterexamples': ['discard-zero', 'missing-as-zero']},
            {'invariant': 'Registry order, start position, constructor identity and the existing Float fallback are preserved.',
             'enforcement': 'findDataFieldFrom, resolveDataField and dataFieldOfEntry; cases 12-34.',
             'counterexamples': ['skip-first-entry', 'ignore-constructor-stamp', 'discard-float-flag']},
            {'invariant': 'A missing descriptor retains the existing emission diagnostic and negative cursors retain the index trap.',
             'enforcement': 'emitField None branch and unchanged Vec bounds check; native modes at O0/O2.',
             'counterexamples': ['unchecked-missing-field']},
        ],
        'known_limits': [
            'Bounded host O0/O2 poisoned data-query execution; no Windows runtime or global soundness claim.',
            'The descriptor payload remains the existing inert AST storage record; packed checker stamps remain a parser boundary.',
            'Struct descriptor APIs and their argument-protection/inference consumers remain unchanged and outside this slice.',
            'No indirect-call corruption reproduction, inference algorithm, ARC algorithm or held work is exercised.',
        ],
    }

    def modules(label, text):
        directory = work / (label + '-modules/core')
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'codegen.ax').write_text(text + BRIDGE)
        return dict(env, AXIOM_PATH=os.pathsep.join((str(directory), str(root / 'core'))))

    def build_run(label, level, text, failures=()):
        local = modules(label, text)
        path = work / (label + '.ax')
        path.write_text(fixture)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(path), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '-build.stdout'), stderr=work / (label + '-build.stderr'), timeout=240)
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        failed = check_output(output, expected, required_failures=failures)
        return failed, binary, local

    def missing_field(binary, local, label, status=3):
        result = subprocess.run([str(binary), '--diagnostic-format=ai', 'missing'],
                                env=local, capture_output=True, text=True, timeout=30)
        (work / (label + '-missing.stdout')).write_text(result.stdout)
        (work / (label + '-missing.stderr')).write_text(result.stderr)
        assert result.returncode == status and not result.stdout, (label, result)
        if status == 3:
            assert result.stderr == MISSING_FIELD_DIAGNOSTIC, (label, result)
        else:
            assert not result.stderr, (label, result)
        return result.stderr

    for level in (0, 2):
        label = 'positive-O' + str(level)
        _, binary, local = build_run(label, level, source)
        diagnostic = missing_field(binary, local, label)
        negative = subprocess.run([str(binary), 'negative-index'], env=local, capture_output=True, text=True, timeout=30)
        (work / (label + '-negative.stdout')).write_text(negative.stdout)
        (work / (label + '-negative.stderr')).write_text(negative.stderr)
        assert negative.returncode == 77 and not negative.stdout, (label, negative)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True, 'cases': 34, 'status': 'passed'})
        report['refusals'].extend([
            {'name': 'missing-emission-field', 'optimization': level, 'diagnostic': 'AX4002', 'status': 3,
             'stderr': diagnostic},
            {'name': 'negative-search-cursor', 'optimization': level, 'status': 77},
        ])
        print(f'ok   data-field Options: 34 outcomes, AX4002 and index trap at O{level} poison', flush=True)

    zero = change_function(source, 'dataFieldIndexIn', '(Some i)', '(if (== i 0) None (Some i))')
    missing = change_function(source, 'dataFieldIndexIn', '\n    None\n', '\n    (Some 0)\n')
    first = change_function(source, 'findDataField', '(findDataFieldFrom types fname 0)', '(findDataFieldFrom types fname 1)')
    stamp = change_function(source, 'resolveDataField', '(if (== (nodeBinderTy node) 0)', '(if true')
    floating = change_function(source, 'dataFieldOfEntry', '(vecGet (eFieldFlagsVec entry) i)', '0')
    for label, text, failures in [
        ('discard-zero', zero, {2, 12}),
        ('missing-as-zero', missing, {1, 5, 6, 7, 10, 11}),
        ('skip-first-entry', first, {17, 24, 25}),
        ('ignore-constructor-stamp', stamp, {26, 27, 28, 29}),
        ('discard-float-flag', floating, {12}),
    ]:
        failed, _, _ = build_run(label, 0, text, failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: cases {sorted(failed)} fail', flush=True)
    unchecked = change_function(source, 'emitField', '(cgFail cg "unknown struct field: " (nodeBName node))', 'cgB')
    _, binary, local = build_run('unchecked-missing-field', 0, unchecked)
    missing_field(binary, local, 'unchecked-missing-field', status=0)
    report['counterexamples'].append({'name': 'unchecked-missing-field', 'missing_field_accepted': True})
    print('ok   counterexample unchecked-missing-field: missing descriptor loses AX4002', flush=True)

    local = modules('refusals', source)
    for label, declaration, code in [
        ('raw-data-index', '(:: bad Int) (fn (bad) (dataFieldIndexIn vecNew "field" 0))', 'AX3004'),
        ('raw-data-descriptor', '(:: bad ASTNode) (fn (bad) (findDataField vecNew "field"))', 'AX3004'),
        ('raw-entry-descriptor', '(:: bad (-> TypeEntry ASTNode)) (fn (bad entry) (probeDataFieldOf entry "field"))', 'AX3004'),
        ('missing-data-none', '(:: bad Int) (fn (bad) (match (findDataField vecNew "field") ((Some field) (nodeA field))))', 'AX3005'),
        ('missing-index-none', '(:: bad Int) (fn (bad) (match (dataFieldIndexIn vecNew "field" 0) ((Some index) index)))', 'AX3005'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import codegen)\n(import parser)\n(import core)\n' + declaration + '\n(:: main Int) (fn (main) 0)\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)],
                                env=local, capture_output=True, text=True, timeout=180)
        (work / (label + '.stdout')).write_text(result.stdout)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and f'E {code} ' in errors[0], (label, result)
        report['refusals'].append({'name': label, 'diagnostic': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'data-field-query-options-report.json').write_text(json.dumps(report, indent=2) + '\n')


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
        with tempfile.TemporaryDirectory(prefix='axiom-data-field-query-options-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
