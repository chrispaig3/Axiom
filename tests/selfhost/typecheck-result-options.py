#!/usr/bin/env python3
"""Check explicit optional borrow, store-type and function-body lookup results."""
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
(pub :: probeRememberBorrow (-> TC String ASTNode Int))
(pub fn (probeRememberBorrow checker name body) {
  (let placeholders (tcParLends checker))
  (vecPush placeholders (mkEVar name))
  (vecPush placeholders body)
  0
})
'''


def check(compiler, root, work):
    original = (root / 'core/typecheck.ax').read_text()
    source = work / 'result-options.ax'
    source.write_bytes((root / 'tests/selfhost/typecheck-result-options.axp').read_bytes())
    environment = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    expected = [f'{index} true' for index in range(1, 39)]
    version = subprocess.run([str(compiler), '--diagnostic-format=ai', 'version'],
                             env=environment, capture_output=True, text=True, check=True).stdout.strip()
    report = {'source_sha256': hashlib.sha256(original.encode()).hexdigest(),
              'builder': str(compiler), 'builder_version': version,
              'configurations': [], 'counterexamples': [], 'refusals': [],
              'invariants': [
                  {'invariant': 'A missing borrow placeholder refuses lending; the most recent matching one wins.',
                   'enforcement': 'Option ASTNode with explicit None refusal, reverse pair scan; cases 1-10.',
                   'counterexample': 'oldest-borrow-placeholder'},
                  {'invariant': 'Unavailable operand types are absent while poison and inference AST values stay present.',
                   'enforcement': 'storeKnownTy boundary and Option store lookup; cases 11-25,35-38.',
                   'counterexample': 'lost-poison and present-nil-type'},
                  {'invariant': 'Declared function lookup keeps exact names and first-match order, with numeric diagnostic fallback.',
                   'enforcement': 'Option declaration result and explicit None branch; cases 26-34.',
                   'counterexample': 'last-function-declaration'},
              ],
              'known_limits': ['Host O0/O2 execution with allocation poisoning; no Windows runtime evidence.',
                               'Only the named lookup contracts and selected AX3071/AX3043/AX3001 controls are covered.',
                               'Region traversal, lifetime enforcement and the held M5 work are excluded.',
                               'No global soundness, Rust parity or certification claim follows from this fixture.']}
    run_checked([str(compiler), '--diagnostic-format=ai', 'fmt', '--check', str(source)],
                env=environment, stdout=work / 'fmt.stdout', stderr=work / 'fmt.stderr')

    def modules(label, contents):
        directory = work / (label + '-modules/core')
        directory.mkdir(parents=True)
        for path in (root / 'core').iterdir():
            destination = directory / path.name
            if path.name == 'typecheck.ax':
                destination.write_text(contents + BRIDGE)
            else:
                destination.symlink_to(path, target_is_directory=path.is_dir())
        return dict(environment, AXIOM_PATH=str(directory))

    def build_run(label, contents, level, failures=()):
        local = modules(label, contents)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(source),
                     '--opt', str(level), '--alloc-poison', '-o', str(binary)],
                    env=local, stdout=work / (label + '.build.stdout'), stderr=work / (label + '.build.stderr'))
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        observed = check_output(output, expected, required_failures=failures)
        print('ok   ' + label + ': ' + str(sorted(observed)), flush=True)
        return observed

    for level in (0, 2):
        build_run('positive-O' + str(level), original, level)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True,
                                         'cases': 38, 'status': 'passed'})
    oldest = replace_once(original, '(let mut i (- (vecLen v) 2))', '(let mut i (if (>= (vecLen v) 2) 0 (- 0 2)))', 'reverse borrow scan')
    marker = '(fn (storeKnownTy ty)\n  (if (nodeSame ty nilNode)\n    None\n    (Some ty)))'
    lost = replace_once(original, marker, '(fn (storeKnownTy ty)\n  (if (|| (nodeSame ty nilNode) (== (tyIsErr ty) 1))\n    None\n    (Some ty)))',
                        'store poison remains present')
    nil = replace_once(original, marker, '(fn (storeKnownTy ty) (Some ty))', 'nil type remains absent')
    begin = original.index('(pub fn (rgnDeclOfFrom ')
    end = original.index('; ---- one function ----', begin)
    function = original[begin:end]
    assert function.count('(Some d)') == 1
    last = original[:begin] + function.replace('(Some d)',
        '(if (let (Some later) (rgnDeclOfFrom decls name (+ i 1))) (Some later) (Some d))') + original[end:]
    for label, changed, cases in [('oldest-borrow-placeholder', oldest, (8,)),
                                  ('lost-poison', lost, (22,)),
                                  ('present-nil-type', nil, (24,)),
                                  ('last-function-declaration', last, (27,))]:
        failures = build_run(label, changed, 0, cases)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failures)})
    local = modules('refusals', original)
    for name, expression, code in [
        ('unchecked-borrow', '(nodeTag (capBorrowBlock (tcNew vecNew vecNew vecNew) "none"))', 'AX3004'),
        ('missing-type-none', '(match (storeOperandTy (tcNew vecNew vecNew vecNew) (mkEInt 1)) ((Some ty) (nodeTag ty)))', 'AX3005'),
        ('unchecked-declaration', '(nodeTag (rgnDeclOfFrom vecNew "none" 0))', 'AX3004'),
    ]:
        refused = work / (name + '.ax')
        refused.write_text('(import core)\n(import parser)\n(import typecheck)\n(import Vec)\n'
                           '(:: main Int)\n(fn (main) { ' + expression + ' 0 })\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(refused)],
                                env=local, capture_output=True, text=True)
        (work / (name + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or f'E {code} ' not in errors[0]:
            raise RuntimeError((name, result))
        report['refusals'].append({'name': name, 'diagnostic': code, 'status': 'passed'})
        print('ok   ' + name + ': ' + code, flush=True)
    (work / 'result-option-report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if arguments.work:
        work = arguments.work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        check(arguments.axiom.resolve(), root, work)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-checker-result-options-') as directory:
            check(arguments.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
