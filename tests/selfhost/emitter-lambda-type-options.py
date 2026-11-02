#!/usr/bin/env python3
"""Check owning optional lambda arrows and unchanged lambda emission."""
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
(pub :: probeLambdaGet (-> CG (Option ASTNode)))
(pub fn (probeLambdaGet cg) (cgLambdaType cg))
(pub :: probeLambdaSet (-> CG (Option ASTNode) CG))
(pub fn (probeLambdaSet cg arrow) (cgSetLambdaType cg arrow))
(pub :: probeLambdaResult (-> (Option ASTNode) (Option ASTNode)))
(pub fn (probeLambdaResult arrow) (lambdaResultType arrow))
'''
CASES = [
    ('scalar', '(:: make (-> Int (-> Int Int)))\n(fn (make value) (lambda (n) (+ value n)))\n(:: main Int)\n(fn (main) ((make 40) 2))\n'),
    ('reference', '(:: make (-> Int (-> String String)))\n(fn (make ignored) (lambda (text) text))\n(:: main Int)\n(fn (main) { (let value "owned") (let answer ((make 0) value)) (if (== value answer) 42 0) })\n'),
    ('float', '(:: make (-> Int (-> Float Float)))\n(fn (make ignored) (lambda (value) value))\n(:: main Int)\n(fn (main) (if (== ((make 0) 3.5) 3.5) 42 0))\n'),
    ('generic', '(:: make (-> a (-> Int a)))\n(fn (make value) (lambda (ignored) value))\n(:: main Int)\n(fn (main) ((make 42) 0))\n'),
]


def check(compiler, root, work, baseline=None):
    source = (root / 'core/codegen.ax').read_text()
    fixture = (root / 'tests/selfhost/emitter-lambda-type-options.axp').read_text()
    expected = [f'{i} true' for i in range(1, 39)]
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {
        'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'configurations': [], 'counterexamples': [], 'refusals': [], 'same_ir': [],
        'invariants': [
            {'invariant': 'Missing checked arrows and results are None; present poison, wildcard and empty-name children remain present.',
             'enforcement': 'LamDesc.arrow, cgLambdaType, lambdaResultType and packed-read producer; cases 1-26,34-38.',
             'counterexamples': ['lost-lambda-context', 'missing-result-as-int', 'discard-poison-result', 'lost-checked-producer']},
            {'invariant': 'Descriptors and CG fields own their optional arrows until replacement, retirement or return.',
             'enforcement': 'Typed Option fields, direct field stores and returned Option; cases 27-36.',
             'counterexamples': ['duplicate-arrow-owners']},
            {'invariant': 'Missing result metadata keeps class1, and scalar/reference/float/generic lambda emission retains its previous behavior.',
             'enforcement': 'Exhaustive optional metadata queries and four emitted-program IR/native controls.',
             'counterexamples': ['missing-result-as-int']},
        ],
        'known_limits': ['Host O0/O2 poisoned execution and host LLVM/native controls; no Windows runtime claim.',
                         'Partial lambda descriptors may lack checked arrows and retain their conservative fallback; required pair-result refusal is covered by emitter-pair-state.py.',
                         'CG.curDeclNode and other finite optional protocols remain separate groups.',
                         'No inference/escape/lifetime algorithm or held work is read, changed or validated; no global soundness or completion claim.'],
    }

    def modules(label, text, bridge=True):
        path = work / (label + '-modules/core')
        path.mkdir(parents=True, exist_ok=True)
        (path / 'codegen.ax').write_text(text + (BRIDGE if bridge else ''))
        return dict(env, AXIOM_PATH=os.pathsep.join((str(path), str(root / 'core'))))

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
        return check_output(output, expected, required_failures=failures)

    for level in (0, 2):
        build_run('positive-O' + str(level), level, source)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True, 'cases': 38, 'status': 'passed'})
        print(f'ok   lambda arrow Options: 38 outcomes at O{level} poison', flush=True)
    lost = replace_once(source, '(fn (cgLambdaType cg)\n  cg.pairState.lambdaArrow)', '(fn (cgLambdaType cg)\n  None)', 'lambda metadata getter')
    missing = replace_once(source, '(fn (lambdaResultType signature)\n  (match signature\n    ((None) None)',
                           '(fn (lambdaResultType signature)\n  (match signature\n    ((None) (Some (mkTCon "Int" nodesNew)))', 'missing lambda result')
    poison = replace_once(source, '(if (nodeSame ty nilNode)\n    None\n    (Some ty))',
                          '(if (|| (nodeSame ty nilNode) (== (nodeTag ty) TAG_T_ERR)) None (Some ty))', 'poison preservation')
    owner = replace_once(source, '(pub fn (mkLamDesc lname lparams body capNames capFloats resultTy)\n  (LamDesc',
                         '(pub fn (mkLamDesc lname lparams body capNames capFloats resultTy)\n  { (__retainref resultTy) (LamDesc', 'descriptor ownership')
    owner = replace_once(owner, ':arrow resultTy))', ':arrow resultTy) })', 'descriptor control close')
    owner = replace_once(owner, '(fn (cgSetLambdaType cg ty)\n  {', '(fn (cgSetLambdaType cg ty)\n  {\n    (__retainref ty)', 'context ownership')
    producer = replace_once(source, '(cgTypeNodeOpt (nodeBinderTyChild node)))', 'None)', 'checked lambda producer')
    for label, text, failures in [
        ('lost-lambda-context', lost, {5, 6, 34}),
        ('missing-result-as-int', missing, {16, 21}),
        ('discard-poison-result', poison, {19}),
        ('duplicate-arrow-owners', owner, {28, 30, 33}),
        ('lost-checked-producer', producer, {38}),
    ]:
        failed = build_run(label, 0, text, failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: cases {sorted(failed)} fail', flush=True)
    local = modules('refusals', source)
    for label, declaration, code in [
        ('raw-arrow-field', '(:: bad (-> LamDesc ASTNode)) (fn (bad desc) desc.arrow)', 'AX3004'),
        ('raw-arrow-constructor', '(:: bad LamDesc) (fn (bad) (mkLamDesc "x" vecNew (mkEInt 0) vecNew vecNew nilNode))', 'AX3004'),
        ('raw-arrow-setter', '(:: bad CG) (fn (bad) (probeLambdaSet newCG nilNode))', 'AX3004'),
        ('raw-parameter-query', '(:: bad Int) (fn (bad) (lambdaParamIsFloat nilNode 0))', 'AX3004'),
        ('missing-arrow-none', '(:: bad (-> LamDesc ASTNode)) (fn (bad desc) (match desc.arrow ((Some ty) ty)))', 'AX3005'),
        ('missing-result-none', '(:: bad ASTNode) (fn (bad) (match (probeLambdaResult None) ((Some ty) ty)))', 'AX3005'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import codegen)\n(import parser)\n(import core)\n(import Vec)\n' + declaration + '\n(:: main Int) (fn (main) 0)\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)],
                                env=local, capture_output=True, text=True, timeout=180)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and f'E {code} ' in errors[0], (label, result)
        report['refusals'].append({'name': label, 'diagnostic': code})
        print(f'ok   refusal {label}: {code}', flush=True)

    # Ordinary source exercises the real checker -> emitter handoff, without
    # adapting any baseline optional metadata API.
    flow = (root / 'tests/selfhost/emitter-flow-environment.axp').read_text()
    helper = flow[flow.index('(:: emitSource '):flow.index('(:: checks ())')]
    branches = json.dumps(CASES[-1][1])
    for name, program in reversed(CASES[:-1]):
        branches = '(if (strEq name ' + json.dumps(name) + ') ' + json.dumps(program) + ' ' + branches + ')'
    loader = work / 'emit-lambdas.ax'
    loader.write_text('(import core)\n(import Host)\n(import lexer)\n(import parser)\n(import typecheck)\n(import codegen)\n(import checked)\n(import Str)\n(import Vec)\n(import IO)\n(import Sys)\n' + helper +
                      '\n(:: main Int)\n;@axiom:effect(io)\n(fn (main) { (let name (sysArg 1)) (writeStr stdout (emitSource ' + branches + ')) 0 })\n')
    texts = [('current-O0', source, 0), ('current-O2', source, 2)]
    if baseline:
        texts.insert(0, ('baseline-O0', baseline.read_text(), 0))
    ir = {}
    for label, text, level in texts:
        local = modules(label, text, bridge=False)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(loader), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '-build.stdout'), stderr=work / (label + '-build.stderr'), timeout=240)
        for name, _ in CASES:
            path = work / (label + '-' + name + '.ll')
            run_checked([str(binary), name], env=local, stdout=path, stderr=work / (label + '-' + name + '.stderr'), timeout=60)
            assert 'target triple' in path.read_text(), (label, name)
            ir[label, name] = path.read_bytes()
    reference = 'baseline-O0' if baseline else 'current-O0'
    for name, _ in CASES:
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
            report['same_ir'].append({'program': name, 'optimization': level, 'reference': reference,
                                      'sha256': hashlib.sha256(ir[label, name]).hexdigest(), 'native_exit': 42 if os.name != 'nt' else None})
        print(f'ok   unchanged {name} lambda IR; O0/O2 native exits42', flush=True)
    (work / 'lambda-type-options-report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--baseline-codegen', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), root, args.work.resolve(), args.baseline_codegen)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-lambda-types-') as directory:
            check(args.axiom.resolve(), root, Path(directory), args.baseline_codegen)


if __name__ == '__main__':
    main()
