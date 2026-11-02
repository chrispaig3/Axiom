#!/usr/bin/env python3
"""Check optional alloca insertion positions and their owned marker carrier."""
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
(pub :: probeMark (-> CG (Option Int)))
(pub fn (probeMark cg) (cgAllocaMark cg))
(pub :: probeSetMark (-> CG (Option Int) CG))
(pub fn (probeSetMark cg marker) (cgSetAllocaMark cg marker))
'''


def check(compiler, root, work):
    source = (root / 'core/codegen.ax').read_text()
    fixture = (root / 'tests/selfhost/emitter-alloca-marker-options.axp').read_text()
    expected = [f'{i} true' for i in range(1, 28)]
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {
        'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'configurations': [], 'counterexamples': [], 'refusals': [],
        'invariants': [
            {'invariant': 'None emits directly; Some 0 and later positions collect and replace the designated placeholder.',
             'enforcement': 'CG.allocaMark, openAllocaMark and the three output guards; cases 1-19.',
             'counterexamples': ['discard-first-position', 'force-direct-output', 'skip-placeholder-write']},
            {'invariant': 'Closing clears the marker and queue, opening resets the queue and nested saved markers remain owned.',
             'enforcement': 'Typed setter/getter and explicit close Some/None paths; cases 11-17,25-27.',
             'counterexamples': ['leave-marker-active', 'keep-old-queue']},
            {'invariant': 'The optional numeric marker owns exactly one stored share and retires replaced or dropped shares.',
             'enforcement': 'Mapped Option field, setter slot43 IR and cases 20-24.',
             'counterexamples': ['duplicate-marker-share']},
        ],
        'known_limits': [
            'Host O0/O2 poisoned marker and string-buffer execution only; no Windows or global soundness claim.',
            'Allocation strings and registry/reserve decisions are unchanged; no region/lifetime traversal or enforcement is tested.',
            'Function/call emission APIs, indirect-call protection, inference and evidence-stamp code remain unchanged.',
            'Other declaration-table and result-class sentinel protocols remain separate blocked inventory items.',
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
                     '--alloc-poison', '--emit-llvm', '-o', str(binary)], env=local,
                    stdout=work / (label + '-build.stdout'), stderr=work / (label + '-build.stderr'), timeout=240)
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        failed = check_output(output, expected, required_failures=failures)
        return failed, binary

    for level in (0, 2):
        _, binary = build_run('positive-O' + str(level), level, source)
        module = Path(str(binary) + '.ll').read_text()
        setter = SUPPORT['emitted_function'](module, 'codegen$cgSetAllocaMark')
        SUPPORT['check_typed_slot'](setter, 43, '%mark')
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True,
                                         'cases': 27, 'setter_IR_slot43_balanced': True, 'status': 'passed'})
        print(f'ok   alloca marker Options: 27 outcomes and slot43 owner store at O{level} poison', flush=True)

    first = change_function(source, 'cgAllocaMark', '    c.allocaMark',
                            '    (match c.allocaMark ((None) None) ((Some mark) (if (== mark 0) None (Some mark))))')
    active = change_function(source, 'closeAllocaMark', '(cgSetAllocaMark cg None)', 'cg')
    queue = change_function(source, 'openAllocaMark', '(cgSetHoisted cgM vecNew)', 'cgM')
    patch = change_function(source, 'closeAllocaMark', '(vecSet (cgLines cg) mark (joinAllocas hoisted))', '(cgLines cg)')
    direct = source
    for name in ('emitAlloca', 'emitRecoverCell', 'emitRegionCell'):
        direct = change_function(direct, name, '(if (isNone (cgAllocaMark cg))', '(if true')
    duplicate = change_function(source, 'cgSetAllocaMark', '    (let c cg)',
                                '    (__retainref mark)\n    (let c cg)')
    for label, text, failures in [
        ('discard-first-position', first, {6, 8, 10, 25}),
        ('leave-marker-active', active, {11, 16, 27}),
        ('keep-old-queue', queue, {17}),
        ('skip-placeholder-write', patch, {10, 15, 26}),
        ('force-direct-output', direct, {8, 9, 10}),
        ('duplicate-marker-share', duplicate, {20, 22, 23, 24}),
    ]:
        failed, _ = build_run(label, 0, text, failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: cases {sorted(failed)} fail', flush=True)

    local = modules('refusals', source)
    for label, declaration, code in [
        ('raw-marker-field', '(:: bad (-> CG Int)) (fn (bad cg) cg.allocaMark)', 'AX3004'),
        ('raw-marker-getter', '(:: bad (-> CG Int)) (fn (bad cg) (probeMark cg))', 'AX3004'),
        ('raw-marker-setter', '(:: bad (-> CG CG)) (fn (bad cg) (probeSetMark cg 0))', 'AX3004'),
        ('wrong-marker-payload', '(:: bad (-> CG CG)) (fn (bad cg) (probeSetMark cg (Some "position")))', 'AX3004'),
        ('missing-marker-none', '(:: bad (-> CG Int)) (fn (bad cg) (match (probeMark cg) ((Some mark) mark)))', 'AX3005'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import codegen)\n(import core)\n' + declaration + '\n(:: main Int) (fn (main) 0)\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)],
                                env=local, capture_output=True, text=True, timeout=180)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and f'E {code} ' in errors[0], (label, result)
        report['refusals'].append({'name': label, 'diagnostic': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'alloca-marker-options-report.json').write_text(json.dumps(report, indent=2) + '\n')


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
        with tempfile.TemporaryDirectory(prefix='axiom-alloca-marker-options-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
