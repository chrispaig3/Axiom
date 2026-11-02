#!/usr/bin/env python3
"""Check owning declaration Options and packed evidence-owner identity."""
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
CASES = runpy.run_path(str(Path(__file__).with_name('emitter-lambda-type-options.py')))['CASES']
BRIDGE = '''
(pub :: probeDeclarationGet (-> CG (Option ASTNode)))
(pub fn (probeDeclarationGet cg) (cgCurDecl cg))
(pub :: probeDeclarationSet (-> CG (Option ASTNode) CG))
(pub fn (probeDeclarationSet cg declaration) (cgSetCurDecl cg declaration))
(pub :: probeDeclarationMatches (-> CG ASTNode Bool))
(pub fn (probeDeclarationMatches cg owner) (cgDeclarationMatches cg owner))
'''


def check(compiler, root, work, baseline=None):
    source = (root / 'core/codegen.ax').read_text()
    fixture = (root / 'tests/selfhost/emitter-declaration-options.axp').read_text()
    expected = [f'{i} true' for i in range(1, 53)]
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {
        'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'configurations': [], 'counterexamples': [], 'refusals': [], 'same_ir': [],
        'invariants': [
            {'invariant': 'An inactive declaration is None; present empty-name and poison nodes remain Some.',
             'enforcement': 'CG.curDeclNode, getter/setter and exhaustive query branches; cases 1-10,18-20,21-36.',
             'counterexamples': ['discard-declaration']},
            {'invariant': 'Packed evidence owner identity preserves absent/absent and rejects stale or different declarations.',
             'enforcement': 'cgDeclarationMatches and existing parser optional stamp boundary; cases 2-7,11-17,37-44.',
             'counterexamples': ['reject-absent-owner', 'accept-any-owner']},
            {'invariant': 'The context owns declaration metadata through replacement, clearing, return and save/restore.',
             'enforcement': 'Typed Option field stores and returned getter; cases 45-52.',
             'counterexamples': ['duplicate-declaration-share']},
            {'invariant': 'Missing-context defaults, Some 0 evidence bits and scalar/reference/Float/generic output are preserved.',
             'enforcement': 'Query cases 21-44 and actual source-to-emitter IR/native comparisons.',
             'counterexamples': ['discard-declaration', 'reject-absent-owner']},
        ],
        'known_limits': ['Host native O0/O2 allocation-poison configurations and host LLVM emission; no Windows runtime claim.',
                         'Packed evidence stamps still encode their absent owner as nilNode only at the parser storage boundary.',
                         'evStampOk result, numeric masks/class lattices and other finite optional query groups remain separate.',
                         'No inference/escape/lifetime traversal/fixpoint/enforcement algorithm or held work is changed or validated.',
                         'This bounded evidence does not establish global soundness or compiler-wide completion.'],
    }

    def modules(label, text, bridge=True):
        directory = work / (label + '-modules/core')
        directory.mkdir(parents=True, exist_ok=True)
        (directory / 'codegen.ax').write_text(text + (BRIDGE if bridge else ''))
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
        return check_output(output, expected, required_failures=failures)

    for level in (0, 2):
        build_run('positive-O' + str(level), level, source)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True, 'cases': 52, 'status': 'passed'})
        print(f'ok   declaration Options: 52 outcomes at O{level} poison', flush=True)
    lost = replace_once(source, '(fn (cgCurDecl cg)\n  {\n    (let c cg)\n    c.curDeclNode\n  })',
                        '(fn (cgCurDecl cg) None)', 'context getter')
    absent = replace_once(source, '((None) (nodeSame owner nilNode))', '((None) false)', 'absent packed owner')
    any_owner = replace_once(source, '(fn (cgDeclarationMatches cg owner)\n  (match (cgCurDecl cg)\n    ((None) (nodeSame owner nilNode))\n    ((Some declaration) (nodeSame owner declaration))))',
                             '(fn (cgDeclarationMatches cg owner) true)', 'packed owner identity')
    duplicate = replace_once(source, '(fn (cgSetCurDecl cg d)\n  {\n    (let c cg)',
                             '(fn (cgSetCurDecl cg d)\n  {\n    (__retainref d)\n    (let c cg)', 'context share')
    for label, text, failures in [
        ('discard-declaration', lost, {4, 5, 13, 27, 29, 31, 33, 34, 37, 42, 50, 51}),
        ('reject-absent-owner', absent, {2, 11, 20, 39, 40}),
        ('accept-any-owner', any_owner, {3, 6, 7, 12, 14, 15, 38, 41}),
        ('duplicate-declaration-share', duplicate, {46, 47, 48, 49}),
    ]:
        failed = build_run(label, 0, text, failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: cases {sorted(failed)} fail', flush=True)
    local = modules('refusals', source)
    for label, declaration, code in [
        ('raw-context-field', '(:: bad (-> CG ASTNode)) (fn (bad cg) cg.curDeclNode)', 'AX3004'),
        ('raw-context-setter', '(:: bad CG) (fn (bad) (probeDeclarationSet newCG nilNode))', 'AX3004'),
        ('optional-packed-owner', '(:: bad Bool) (fn (bad) (probeDeclarationMatches newCG None))', 'AX3004'),
        ('nested-optional-context', '(:: bad CG) (fn (bad) (probeDeclarationSet newCG (Some None)))', 'AX3004'),
        ('missing-context-none', '(:: bad (-> CG ASTNode)) (fn (bad cg) (match (probeDeclarationGet cg) ((Some declaration) declaration)))', 'AX3005'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import codegen)\n(import parser)\n(import core)\n' + declaration + '\n(:: main Int) (fn (main) 0)\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)],
                                env=local, capture_output=True, text=True, timeout=180)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and f'E {code} ' in errors[0], (label, result)
        report['refusals'].append({'name': label, 'diagnostic': code})
        print(f'ok   refusal {label}: {code}', flush=True)

    # Compile the actual checker/emitter handoff, without rewriting a baseline
    # metadata API. The input programs exercise real declaration save/restore.
    flow = (root / 'tests/selfhost/emitter-flow-environment.axp').read_text()
    helper = flow[flow.index('(:: emitSource '):flow.index('(:: checks ())')]
    branches = json.dumps(CASES[-1][1])
    for name, program in reversed(CASES[:-1]):
        branches = '(if (strEq name ' + json.dumps(name) + ') ' + json.dumps(program) + ' ' + branches + ')'
    loader = work / 'emit-programs.ax'
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
        print(f'ok   unchanged {name} IR; O0/O2 native exits42', flush=True)
    (work / 'declaration-options-report.json').write_text(json.dumps(report, indent=2) + '\n')


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
        with tempfile.TemporaryDirectory(prefix='axiom-declaration-options-') as directory:
            check(args.axiom.resolve(), root, Path(directory), args.baseline_codegen)


if __name__ == '__main__':
    main()
