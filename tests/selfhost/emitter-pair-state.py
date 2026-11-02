#!/usr/bin/env python3
"""Check typed auxiliary state, scoped ledger retirement and optional facts."""
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
BRIDGES = '''
(pub :: probeLambdaType (-> CG (Option ASTNode) CG))
(pub fn (probeLambdaType cg ty) (cgSetLambdaType cg ty))
(pub :: probeFunctionTypes (-> CG FunctionTypes CG))
(pub fn (probeFunctionTypes cg types) (cgSetFunctionFloats cg (Some (functionFloatIndex types))))
(pub :: probeCheckedFlags (-> CG String (Option Ints)))
(pub fn (probeCheckedFlags cg name) (checkedFloatFlags cg name))
(pub :: probeTruncateSlots (-> CG Int Int))
(pub fn (probeTruncateSlots cg size) (truncatePendingSlots (pairOwningSlots cg) size))
(pub :: probePairResultType (-> CG (Option ASTNode)))
(pub fn (probePairResultType cg) (cgPairResultType cg))
(pub :: probePairMode (-> CG Int))
(pub fn (probePairMode cg) (cgPairMode cg))
'''


def check(axiom, repo, work, baseline=None):
    fixture = work / 'pair-state.ax'
    fixture.write_bytes((repo / 'tests/selfhost/emitter-pair-state.axp').read_bytes())
    expected = [f'{i} true' for i in range(1, 66)]
    original = (repo / 'core/codegen.ax').read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(repo / 'stdlib'))
    report = {'source_sha256': hashlib.sha256(original.encode()).hexdigest(),
              'builder': str(axiom), 'configurations': [], 'counterexamples': [],
              'invariants': [
                  {'invariant': 'Auxiliary state owns and retires its nested references.',
                   'enforcement': 'PairState/PendingSlot typed fields, typed vectors and field stores; cases 10-13,17,19,22,32-35,42-49.',
                   'counterexample': 'unmapped-state-children'},
                  {'invariant': 'Owning slot scope truncation retires each removed descriptor.',
                   'enforcement': 'truncatePendingSlots vecPop loop; cases 36-41.',
                   'counterexample': 'raw-slot-truncation'},
                  {'invariant': 'Optional facts handle absence and preserve typed lookup results.',
                   'enforcement': 'Some/None branches and pairRetTyOf; cases 1-9,14-16,18-31.',
                   'counterexample': 'lost-float-index'},
                  {'invariant': 'Pair result queries preserve None and present scalar/reference/poison metadata with owning returns.',
                   'enforcement': 'cgPairResultType returns Option ASTNode; emitPairRet explicitly handles absence; cases 52-65.',
                   'counterexample': 'lost-pair-result'},
              ],
              'known_limits': ['Host execution only; no Windows runtime evidence.',
                               'Numeric flags/counters and emitted LLVM words remain numeric intentionally.',
                               'AST nil is normalized at checked reader boundaries; this is not a general AST redesign.',
                               'Focused evidence does not establish global soundness, Rust parity or certification.']}
    run_checked([str(axiom), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)],
                env=env, stdout=work / 'fmt.stdout', stderr=work / 'fmt.stderr')

    def modules_for(label, source):
        modules = work / f'{label}-modules/core'
        modules.mkdir(parents=True, exist_ok=True)
        for path in (repo / 'core').iterdir():
            destination = modules / path.name
            if path.name == 'codegen.ax':
                destination.write_text(source + BRIDGES)
            elif not destination.exists():
                destination.symlink_to(path, target_is_directory=path.is_dir())
        return modules

    def build_run(label, level, source, negative=()):
        local = dict(env, AXIOM_PATH=str(modules_for(label, source)))
        binary = work / label
        run_checked([str(axiom), '--diagnostic-format=ai', 'build', str(fixture),
                     '--opt', str(level), '--alloc-poison', '-o', str(binary)],
                    env=local, stdout=work / f'{label}.build.stdout', stderr=work / f'{label}.build.stderr')
        output = work / f'{label}.stdout'
        run_checked([str(binary)], env=local, stdout=output, stderr=work / f'{label}.stderr', timeout=30)
        return check_output(output, expected, required_failures=negative)

    for level in (0, 2):
        build_run(f'positive-O{level}', level, original)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True,
                                         'cases': 65, 'status': 'passed'})
        print(f'ok   PairState: 65 cases at -O{level} with allocation poisoning', flush=True)
    unmapped = replace_once(original, '      (CG\n        :lines vecNew',
                            '      (memMarkLeaf (as ps Int))\n      (CG\n        :lines vecNew',
                            'state child reference map')
    truncate = replace_once(original,
                            '    (while (> (vecLen slots) size)\n      {\n        (let retired (vecPop slots))\n        0\n      })',
                            '    (memSetWord (as slots Int) 0 size)', 'typed slot scope retirement')
    lost = replace_once(original, '(fn (cgFunctionFloats cg)\n  cg.pairState.functionFloats)',
                        '(fn (cgFunctionFloats cg)\n  (None))', 'checked float index lookup')
    lost_pair = replace_once(original, '(fn (cgPairResultType cg)\n  cg.pairState.returnTy)',
                             '(fn (cgPairResultType cg)\n  None)', 'pair result lookup')
    for label, source, cases in [
        ('unmapped-state-children', unmapped, (11, 13, 33, 34, 35)),
        ('raw-slot-truncation', truncate, (38,)),
        ('lost-float-index', lost, (26,)),
        ('lost-pair-result', lost_pair, (53, 54, 55, 56, 57, 59, 62, 64)),
    ]:
        failures = build_run(label, 0, source, cases)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failures)})
        print(f'ok   counterexample {label}: cases {sorted(failures)} fail', flush=True)
    local = dict(env, AXIOM_PATH=str(modules_for('result-refusals', original)))
    for label, body, code in [
        ('raw-result-query', '(:: bad (-> CG ASTNode)) (fn (bad cg) (probePairResultType cg))', 'AX3004'),
        ('missing-result-none', '(:: bad (-> CG ASTNode)) (fn (bad cg) (match (probePairResultType cg) ((Some ty) ty)))', 'AX3005'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import codegen)\n(import core)\n' + body + '\n(:: main Int) (fn (main) 0)\n')
        result = subprocess.run([str(axiom), '--diagnostic-format=ai', 'check', str(path)], env=local, capture_output=True, text=True, timeout=180)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and ('E ' + code + ' ') in errors[0], (label, result)
        print('ok   refusal ' + label + ': ' + code, flush=True)
    report['result_query_refusals'] = ['AX3004', 'AX3005']
    source = work / 'missing-pair-result.ax'
    source.write_text('''(import codegen)
(import parser)
(:: main Int)
;@axiom:effect(io)
(fn (main) { (emitPairWrapper (mkDFnAt "missing" vecNew (mkEInt 0) 0) newCG) 0 })
''')
    local = dict(env, AXIOM_PATH=str(modules_for('missing-result', original)))
    binary = work / 'missing-pair-result'
    run_checked([str(axiom), '--diagnostic-format=ai', 'build', str(source), '--opt', '0',
                 '--alloc-poison', '-o', str(binary)], env=local,
                stdout=work / 'missing-result.build.stdout', stderr=work / 'missing-result.build.stderr')
    result = subprocess.run([str(binary)], env=local, capture_output=True, text=True, timeout=30)
    (work / 'missing-result.stderr').write_text(result.stderr)
    if result.returncode != 3 or 'AX4002' not in result.stderr or 'pair wrapper has no checked result type' not in result.stderr:
        raise RuntimeError(f'missing checked pair result lost its error: {result}')
    report['required_missing_result'] = {'diagnostic': 'AX4002', 'exit': 3, 'status': 'passed'}
    print('ok   missing required pair result: AX4002 and exit 3', flush=True)
    report['same_ir'] = check_emission(axiom, repo, work, original, baseline)
    (work / 'pair-state-report.json').write_text(json.dumps(report, indent=2) + '\n')


PAIR_PROGRAMS = [
    ('scalar-option', '(:: choose (-> Int (Option Int)))\n(fn (choose n) (if (== n 0) None (Some (+ n 1))))\n(:: main Int)\n(fn (main) (match (choose 41) ((None) 0) ((Some value) (match (choose 0) ((None) value) ((Some _) 0)))))\n'),
    ('reference-option', '(:: choose (-> String (Option String)))\n(fn (choose text) (if (== text "") None (Some text)))\n(:: main Int)\n(fn (main) { (let text "owned") (match (choose text) ((None) 0) ((Some value) (if (== value text) (match (choose "") ((None) 42) ((Some _) 0)) 0))) })\n'),
]


def check_emission(axiom, repo, work, original, baseline):
    env = dict(os.environ, AXIOM_STDLIB=str(repo / 'stdlib'))
    report = []

    def modules(label, text, bridge=False):
        directory = work / (label + '-emit-modules/core')
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'codegen.ax').write_text(text)
        return dict(env, AXIOM_PATH=os.pathsep.join((str(directory), str(repo / 'core'))))

    flow = (repo / 'tests/selfhost/emitter-flow-environment.axp').read_text()
    helper = flow[flow.index('(:: emitSource '):flow.index('(:: checks ())')]
    branches = json.dumps(PAIR_PROGRAMS[-1][1])
    for name, program in reversed(PAIR_PROGRAMS[:-1]):
        branches = '(if (strEq name ' + json.dumps(name) + ') ' + json.dumps(program) + ' ' + branches + ')'
    loader = work / 'emit-programs.ax'
    loader.write_text('(import core)\n(import Host)\n(import lexer)\n(import parser)\n(import typecheck)\n(import codegen)\n(import checked)\n(import Str)\n(import Vec)\n(import IO)\n(import Sys)\n' + helper +
                      '\n(:: main Int)\n;@axiom:effect(io)\n(fn (main) { (let name (sysArg 1)) (writeStr stdout (emitSource ' + branches + ')) 0 })\n')
    texts = [('current-O0', original, 0), ('current-O2', original, 2)]
    if baseline:
        texts.insert(0, ('baseline-O0', baseline.read_text(), 0))
    ir = {}
    for label, text, level in texts:
        local = modules(label, text, bridge=False)
        binary = work / label
        run_checked([str(axiom), '--diagnostic-format=ai', 'build', str(loader), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '-build.stdout'), stderr=work / (label + '-build.stderr'), timeout=240)
        for name, _ in PAIR_PROGRAMS:
            path = work / (label + '-' + name + '.ll')
            run_checked([str(binary), name], env=local, stdout=path, stderr=work / (label + '-' + name + '.stderr'), timeout=60)
            assert 'target triple' in path.read_text(), (label, name)
            ir[label, name] = path.read_bytes()
    reference = 'baseline-O0' if baseline else 'current-O0'
    for name, _ in PAIR_PROGRAMS:
        for level in (0, 2):
            label = 'current-O' + str(level)
            assert ir[label, name] == ir[reference, name], (label, name, 'emitted IR changed')
            path = work / (label + '-' + name + '.ll')
            optimized = path.with_suffix('.opt.ll')
            run_checked(['opt', '-S', '-passes=default<O' + str(level) + '>', str(path), '-o', str(optimized)],
                        env=env, stdout=work / (label + '-' + name + '-opt.stdout'), stderr=work / (label + '-' + name + '-opt.stderr'))
            if os.name != 'nt':
                obj = path.with_suffix('.o')
                run_checked(['llc', str(optimized), '-filetype=obj', '-relocation-model=pic', '-O' + str(level), '-o', str(obj)],
                            env=env, stdout=work / (label + '-' + name + '-llc.stdout'), stderr=work / (label + '-' + name + '-llc.stderr'))
                native = path.with_suffix('')
                run_checked(['cc', str(obj), '-o', str(native)], env=env,
                            stdout=work / (label + '-' + name + '-link.stdout'), stderr=work / (label + '-' + name + '-link.stderr'))
                result = subprocess.run([str(native)], capture_output=True, text=True, timeout=30)
                assert result.returncode == 42 and not result.stdout and not result.stderr, (label, name, result)
            report.append({'program': name, 'optimization': level, 'reference': reference,
                                      'sha256': hashlib.sha256(ir[label, name]).hexdigest(), 'native_exit': 42 if os.name != 'nt' else None})
        print(f'ok   unchanged {name} IR; O0/O2 native exits42', flush=True)
    return report


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--baseline-codegen', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    if args.work:
        work = args.work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), repo, work, args.baseline_codegen)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-pair-state-') as directory:
            check(args.axiom.resolve(), repo, Path(directory), args.baseline_codegen)


if __name__ == '__main__':
    main()
