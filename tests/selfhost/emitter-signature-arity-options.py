#!/usr/bin/env python3
"""Check unknown/zero signature arities, typed queries and ownership."""
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
change_function = runpy.run_path(str(Path(__file__).with_name('emitter-type-metadata-options.py')))['change_function']
BRIDGE = '''
(pub :: probeGetArity (-> FSig (Option Int)))
(pub fn (probeGetArity entry) (fsigArity entry))
(pub :: probeSetArity (-> FSig (Option Int) FSig))
(pub fn (probeSetArity entry count) (fsigSetArity entry count))
(pub :: probeArityMatches (-> CG String Int Bool))
(pub fn (probeArityMatches cg name count) (fnArityMatches cg name count))
(pub :: probeIndexArities (-> CG CG))
(pub fn (probeIndexArities cg) (buildNameIndexes cg))
'''


def check(compiler, root, work):
    source = (root / 'core/codegen.ax').read_text()
    fixture = (root / 'tests/selfhost/emitter-signature-arity-options.axp').read_text()
    expected = [f'{i} true' for i in range(1, 48)]
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {
        'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'configurations': [], 'counterexamples': [], 'refusals': [],
        'invariants': [
            {'invariant': 'Unknown body arity is None, known nullary is Some 0; no absent count matches an application.',
             'enforcement': 'FSig.arity, typed getters/setter, scanners and fnArityMatches; cases 1-17,28-33,43-47.',
             'counterexamples': ['unknown-as-zero', 'missing-matches', 'discard-zero']},
            {'invariant': 'Unknown count preserves the unapplied signature and zero iterations; known counts peel the same arrows and preserve poison/wild/empty/missing children.',
             'enforcement': 'fnDeclaredResultTy, scalar known-count walker and refParamOwnerBits; cases 12-27.',
             'counterexamples': ['unknown-loses-signature', 'lost-known-count']},
            {'invariant': 'The optional numeric carrier is owned through setter replacement, lookup, retirement and return.',
             'enforcement': 'Typed FSig field and shared indexed entries; cases 29-42.',
             'counterexamples': ['duplicate-arity-share']},
        ],
        'known_limits': ['Host O0/O2 poisoned representation/query execution; no Windows runtime or call-emission claim.',
                         'DeclIndex scalar table, AST/span/packed storage, numeric masks/classes and other finite optional protocols remain separate.',
                         'None count preserves the previous unapplied-signature policy; it does not invent a valid parameter count.',
                         'No inference/escape/lifetime traversal/fixpoint/enforcement algorithm or held work is changed or validated.',
                         'The separately blocked evidence-stamp port and its pre-existing retained word-vector share are not included.',
                         'A previously reproduced nullary-closure call discrepancy remains an unresolved release issue under a separate hold; call-emission checks are excluded here.',
                         'This evidence does not establish global soundness or compiler-wide completion.'],
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
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True, 'cases': 47, 'status': 'passed'})
        print(f'ok   signature arity Options: 47 outcomes at O{level} poison', flush=True)
    zero = change_function(source, 'scanFloatSigs', ':arity None', ':arity (Some 0)')
    missing = change_function(source, 'fnArityMatches', '((None) false)', '((None) true)')
    discard = change_function(source, 'fsigArity', '  e.arity)',
                              '  (match e.arity ((None) None) ((Some count) (if (== count 0) None (Some count)))))')
    lost = change_function(source, 'fnDeclaredResultTyKnown', '(if (&& (> arity 0) (== (nodeTag ty) TAG_T_ARR))', '(if false')
    unknown = change_function(source, 'fnDeclaredResultTy', '(match signature\n        ((None) None)\n        ((Some ty) (Some ty)))', 'None')
    duplicate = change_function(source, 'fsigSetArity', '  {\n    (let s e)', '  {\n    (__retainref v)\n    (let s e)')
    for label, text, failures in [
        ('unknown-as-zero', zero, {28}),
        ('missing-matches', missing, {6, 7}),
        ('discard-zero', discard, {4, 8, 29, 33, 35, 40, 44, 47}),
        ('lost-known-count', lost, {17, 21, 22}),
        ('unknown-loses-signature', unknown, {15, 19, 23, 26}),
        ('duplicate-arity-share', duplicate, {34, 36, 37, 39, 41}),
    ]:
        failed = build_run(label, 0, text, failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: cases {sorted(failed)} fail', flush=True)
    local = modules('refusals', source)
    for label, declaration, code in [
        ('raw-arity-field', '(:: bad (-> FSig Int)) (fn (bad entry) entry.arity)', 'AX3004'),
        ('raw-arity-setter', '(:: bad (-> FSig FSig)) (fn (bad entry) (probeSetArity entry 0))', 'AX3004'),
        ('raw-arity-query', '(:: bad Int) (fn (bad) (fnArityCg newCG "missing"))', 'AX3004'),
        ('raw-result-count', '(:: bad (Option ASTNode)) (fn (bad) (fnDeclaredResultTy None 0))', 'AX3004'),
        ('missing-arity-none', '(:: bad (-> FSig Int)) (fn (bad entry) (match entry.arity ((Some count) count)))', 'AX3005'),
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

    (work / 'signature-arity-options-report.json').write_text(json.dumps(report, indent=2) + '\n')

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
        with tempfile.TemporaryDirectory(prefix='axiom-signature-arity-options-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
