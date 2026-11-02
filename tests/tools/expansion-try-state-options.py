#!/usr/bin/env python3
"""Check optional Try-lowering state, cleanup and unchanged trees/diagnostics."""
import argparse
import hashlib
import json
import os
import re
from pathlib import Path
import runpy
import subprocess
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).resolve().parents[1] / 'selfhost/emitter-line-buffer.py'))
run_checked = SUPPORT['run_checked']
replace_once = SUPPORT['replace_once']
check_output = SUPPORT['check_output']
EXPECTED = [f'{i} true' for i in range(1, 39)]


def check(compiler, root, work):
    source = (root / 'core/expand.ax').read_text()
    fixture = (root / 'tests/tools/expansion-try-state-options.axp').read_text()
    lowering = (root / 'tests/tools/expansion-try-state-lowering.axp').read_text()
    golden = (root / 'tests/tools/expansion-try-state-lowering.golden').read_bytes()
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {
        'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'configurations': [], 'counterexamples': [], 'refusals': [],
        'invariants': [
            'QmSt.scrut owns None or a real AST; zero-tag ASTs stay present and malformed null operands stay absent.',
            'State replacement, self-assignment, clearing and retirement balance their child shares.',
            'First and nested Try extraction preserve the scrutinee identity, generated names and failure state.',
            'Lowered tree structure, evaluation order and diagnostics agree with the unchanged parent baseline.',
        ],
        'known_limits': [
            'Host O0/O2 with allocation poisoning is bounded evidence, not whole-compiler soundness.',
            'The original strict retirement assertion is retained as case 8; the typed scalar tag accessor resolves its raw-reader retention dependency.',
            'Raw AST payload readers and broader expansion-result retirement remain separate boundaries.',
            'No lifetime traversal, fixpoint, enforcement algorithm or held M5 work is inspected or changed.',
        ],
    }

    def modules(label, contents):
        folder = work / (label + '-modules') / 'core'
        folder.mkdir(parents=True)
        for path in (root / 'core').iterdir():
            dest = folder / path.name
            if path.name == 'expand.ax':
                dest.write_text(contents)
            else:
                dest.symlink_to(path, target_is_directory=path.is_dir())
        return dict(env, AXIOM_PATH=str(folder))

    def build_run(label, level, local, program=fixture, failures=(), expected=EXPECTED):
        path = work / (label + '.ax')
        path.write_text(program)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(path), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '.build.stdout'), stderr=work / (label + '.build.stderr'))
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        if expected is None:
            return output.read_bytes()
        return check_output(output, expected, required_failures=failures)

    local = modules('positive', source)
    for level in (0, 2):
        build_run(f'positive-O{level}', level, local)
        actual = build_run(f'lowering-O{level}', level, local, lowering, expected=None)
        if actual != golden:
            raise AssertionError(('lowering or diagnostic bytes changed', level, actual))
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True, 'cases': 38,
                                         'lowering_and_diagnostic_bytes': len(golden),
                                         'golden_sha256': hashlib.sha256(golden).hexdigest()})
        print(f'ok   optional Try state: 38 outcomes O{level} poison; exact {len(golden)} lowering/diagnostic bytes', flush=True)

    anchors = re.findall(r'\(if \(nodeSame scrutinee nilNode\)\s+None\s+\(Some scrutinee\)\)', source)
    if len(anchors) != 1:
        raise AssertionError('expected one scrutinee normalisation branch')
    present = anchors[0]
    discard = replace_once(source, present, 'None', 'discard present scrutinee')
    nil_present = replace_once(source, present, '(Some scrutinee)', 'accept missing operand')
    zero_absent = replace_once(source, present,
                                '(if (== (nodeTag scrutinee) 0) None (Some scrutinee))', 'erase valid zero tag')
    failed = replace_once(source, '(set st.failed true)', '(set st.failed false)', 'discard refusal state')
    extra_owner = replace_once(fixture, '(fn (retireState value)\n  {',
                                '(fn (retireState value)\n  {\n    (__retainref value)', 'extra scrutinee share')
    for label, contents, program, failures in [
        ('discard-present', discard, fixture, {10, 13, 15, 29, 31, 38}),
        ('missing-as-present', nil_present, fixture, {16, 30}),
        ('zero-tag-as-absent', zero_absent, fixture, {29}),
        ('discard-failure', failed, fixture, {35}),
        ('extra-scrutinee-share', source, extra_owner, {8}),
    ]:
        observed = build_run(label, 0, modules(label, contents), program, failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(observed)})
        print(f'ok   counterexample {label}: cases {sorted(observed)} fail', flush=True)

    for label, declaration, code in [
        ('raw-scrutinee', '(:: bad (-> QmSt ASTNode)) (fn (bad st) st.scrut)', 'AX3004'),
        ('missing-none', '(:: bad (-> QmSt Int)) (fn (bad st) (match st.scrut ((Some node) (nodeTag node))))', 'AX3005'),
        ('null-as-option', '(:: bad (-> QmSt ())) (fn (bad st) (set st.scrut nilNode))', 'AX3004'),
        ('word-as-child', '(:: bad (-> QmSt ())) (fn (bad st) (set st.scrut (Some 7)))', 'AX3004'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import core)\n(import parser)\n(import expand)\n' + declaration + '\n(:: main Int) (fn (main) 0)\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)],
                                env=local, capture_output=True, text=True, timeout=180)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or f'E {code} ' not in errors[0]:
            raise AssertionError((label, result))
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'try-state-options-report.json').write_text(json.dumps(report, indent=2) + '\n')


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
        with tempfile.TemporaryDirectory(prefix='axiom-try-state-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
