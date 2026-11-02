#!/usr/bin/env python3
"""Check optional signature types, conservative queries and owned metadata."""
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
(pub :: probeSignatureParam (-> (Option ASTNode) Int (Option ASTNode)))
(pub fn (probeSignatureParam ty i) (signatureParamTy ty i))
(pub :: probeSignatureContext (-> CG ASTNode CG))
(pub fn (probeSignatureContext cg decl) (cgSetCurDecl cg (Some decl)))
(pub :: probeRequireSignature (-> FSig ASTNode))
;@axiom:effect(io)
(pub fn (probeRequireSignature entry) (requireSignatureResult entry))
'''


def check(compiler, root, work):
    source = (root / 'core/codegen.ax').read_text()
    fixture = (root / 'tests/selfhost/emitter-signature-types.axp').read_text()
    expected = [f'{i} true' for i in range(1, 65)]
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {
        'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'configurations': [], 'counterexamples': [], 'refusals': [],
        'invariants': [
            {'invariant': 'Missing signature/type slots are None; present poison, wildcard and empty-name nodes remain present.',
             'enforcement': 'FSig.sigTy, typed parameter/result queries and scanFloatSigs packed-read normalizer; cases 1-30.',
             'counterexamples': ['discard-signature', 'discard-poison']},
            {'invariant': 'Parameter, return, pair and partial declaration queries preserve their conservative classifications and first-match precedence.',
             'enforcement': 'Explicit Some/None consumers, declaration/extern producers and ordered registry; cases 6-24,31-52,59-64.',
             'counterexamples': ['missing-parameter-as-int', 'ignore-result-arity']},
            {'invariant': 'Signature metadata owns its optional AST through construction, retirement and return.',
             'enforcement': 'Typed FSig owning field and getter; cases 53-58.',
             'counterexamples': ['duplicate-signature-share']},
            {'invariant': 'Emission requires an available pair result type and refuses absence with AX4002.',
             'enforcement': 'requireSignatureResult at emitPlainCall, explicit emitMatch missing-type branch and native refusal mode.',
             'counterexamples': ['unchecked-required-signature']},
        ],
        'known_limits': ['Host native O0/O2 allocation-poison configurations; no Windows execution claim.',
                         'Partial declarations are direct scanner clients, not an interactive editor session.',
                         'Parser packed AST slots, numeric masks/arity counts and fldClass numeric lattice remain storage/analysis boundaries.',
                         'CG.curDeclNode, LamDesc.arrow and remaining optional query groups are separate tasks.',
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
                    stdout=work / (label + '-build.stdout'), stderr=work / (label + '-build.stderr'), timeout=240)
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        failed = check_output(output, expected, required_failures=failures)
        return failed, binary, local

    def required_result(binary, local, label, status=3):
        result = subprocess.run([str(binary), '--diagnostic-format=ai'], env=local,
                                capture_output=True, text=True, timeout=30)
        (work / (label + '-required.stdout')).write_text(result.stdout)
        (work / (label + '-required.stderr')).write_text(result.stderr)
        assert result.returncode == status and not result.stdout, (label, result)
        if status == 3:
            assert 'E AX4002 ' in result.stderr and 'pair function has no result type: unavailable' in result.stderr, (label, result)
        else:
            assert not result.stderr, (label, result)

    for level in (0, 2):
        _, binary, local = build_run('positive-O' + str(level), level, source)
        required_result(binary, local, 'positive-O' + str(level))
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True, 'cases': 64, 'status': 'passed'})
        report['refusals'].append({'name': 'required-signature', 'optimization': level, 'diagnostic': 'AX4002', 'status': 3})
        print(f'ok   optional signature types: 64 outcomes and AX4002 at O{level} poison', flush=True)

    discard = replace_once(source, '(fn (fsigTy e)\n  e.sigTy)', '(fn (fsigTy e)\n  (if (strEq (fsigName e) "typed") None e.sigTy))', 'discard signature')
    poison = replace_once(source, '(if (nodeSame ty nilNode)\n    None\n    (Some ty))',
                          '(if (|| (nodeSame ty nilNode) (== (nodeTag ty) TAG_T_ERR)) None (Some ty))', 'discard poison')
    parameter = replace_once(source, '((None) None)\n    ((Some ty) (arrowParamTy ty i))',
                             '((None) (Some (mkTCon "Int" nodesNew)))\n    ((Some ty) (arrowParamTy ty i))', 'missing parameter')
    arity = replace_once(source, '(if (&& (> arity 0) (== (nodeTag ty) TAG_T_ARR))', '(if false', 'result arity')
    for label, text, failures in [
        ('discard-signature', discard, {43, 44, 45, 46, 47, 51}),
        ('discard-poison', poison, {27}),
        ('missing-parameter-as-int', parameter, {6, 33, 35}),
        ('ignore-result-arity', arity, {14, 15, 16}),
    ]:
        failed, _, _ = build_run(label, 0, text, failures=failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: cases {sorted(failed)} fail', flush=True)
    owner = replace_once(fixture, '(fn (retireSignature ty)\n  {',
                         '(fn (retireSignature ty)\n  {\n    (__retainref ty)', 'signature child share')
    failed, _, _ = build_run('duplicate-signature-share', 0, source, program=owner, failures={54})
    report['counterexamples'].append({'name': 'duplicate-signature-share', 'failed_cases': sorted(failed)})
    print(f'ok   counterexample duplicate-signature-share: cases {sorted(failed)} fail', flush=True)
    unchecked = replace_once(source, '(dieCodegenDiag "pair function has no result type: " (fsigName signature))',
                             '(writeStr stderr "")', 'required signature guard')
    _, binary, local = build_run('unchecked-required-signature', 0, unchecked)
    required_result(binary, local, 'unchecked-required-signature', 0)
    report['counterexamples'].append({'name': 'unchecked-required-signature', 'missing_metadata_accepted': True})
    print('ok   counterexample unchecked-required-signature: missing metadata accepted', flush=True)

    local = dict(env, AXIOM_PATH=os.pathsep.join((str(work / 'positive-O0-modules/core'), str(root / 'core'))))
    for label, declaration, code in [
        ('raw-signature-type', '(:: bad (-> FSig ASTNode)) (fn (bad entry) entry.sigTy)', 'AX3004'),
        ('raw-result-type', '(:: bad ASTNode) (fn (bad) (fnDeclaredResultTy None (Some 1)))', 'AX3004'),
        ('raw-parameter-input', '(:: bad Int) (fn (bad) (tyvarSlotsFrom newCG nilNode 1 0))', 'AX3004'),
        ('missing-signature-none', '(:: bad (-> FSig ASTNode)) (fn (bad entry) (match entry.sigTy ((Some ty) ty)))', 'AX3005'),
        ('missing-result-none', '(:: bad ASTNode) (fn (bad) (match (arrowResultTy None) ((Some ty) ty)))', 'AX3005'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import codegen)\n(import parser)\n(import core)\n' + declaration + '\n(:: main Int)\n(fn (main) 0)\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)],
                                env=local, capture_output=True, text=True, timeout=180)
        (work / (label + '.stdout')).write_text(result.stdout)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and f'E {code} ' in errors[0], (label, result)
        report['refusals'].append({'name': label, 'diagnostic': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'signature-types-report.json').write_text(json.dumps(report, indent=2) + '\n')


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
        with tempfile.TemporaryDirectory(prefix='axiom-signature-types-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
