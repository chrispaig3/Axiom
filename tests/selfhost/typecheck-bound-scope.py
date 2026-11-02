#!/usr/bin/env python3
"""Check typed body-scope aliases, optional misses, ownership and refusal."""
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


def check(axiom, repo, dependencies, work):
    source = repo / 'tests/selfhost/typecheck-bound-scope.axp'
    fixture = work / 'bound-scope.ax'
    fixture.write_bytes(source.read_bytes())
    expected = [f'{i} true' for i in range(1, 41)]
    original = (repo / 'core/typecheck.ax').read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(repo / 'stdlib'))
    version = subprocess.run([str(axiom), '--diagnostic-format=ai', 'version'],
                             env=env, capture_output=True, text=True, check=True).stdout.strip()
    report = {'source_sha256': hashlib.sha256(original.encode()).hexdigest(),
              'parser_sha256': hashlib.sha256((dependencies / 'parser.ax').read_bytes()).hexdigest(),
              'builder': str(axiom), 'builder_version': version,
              'configurations': [], 'counterexamples': [], 'refusals': [],
              'invariants': [
                  {'invariant': 'Body scopes and their vectors own concrete binding records and their children.',
                   'enforcement': 'BScope and Vec BEnt typed fields/constructors; cases 18,19.',
                   'counterexample': 'unmapped-binding-child'},
                  {'invariant': 'Innermost bindings shadow parameters, globals and earlier stored values.',
                   'enforcement': 'bsFindFrom reverse scan and Option BEnt; cases 1-16,24,27-30.',
                   'counterexample': 'outer-binding-first'},
                  {'invariant': 'Opaque, attributed, parameter and known-value meanings stay distinct.',
                   'enforcement': 'Exhaustive BindingSource matches and optional parameter lookup; cases 17,20-40.',
                   'counterexample': 'opaque-classification'},
              ],
              'known_limits': ['Host execution only; no Windows runtime evidence.',
                               'Known value and parameter indexes remain numeric payloads with existing bounds contracts.',
                               'Scope signatures explicitly distinguish None from present AST values.',
                               'TC and unrelated checker carrier migration has separate evidence.',
                               'Focused evidence does not establish global soundness, Rust parity or certification.']}
    run_checked([str(axiom), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)],
                env=env, stdout=work / 'fmt.stdout', stderr=work / 'fmt.stderr')

    def modules_for(label, content):
        modules = work / f'{label}-modules/core'
        modules.mkdir(parents=True, exist_ok=True)
        for path in dependencies.iterdir():
            destination = modules / path.name
            if path.name == 'typecheck.ax':
                destination.write_text(content)
            elif not destination.exists():
                destination.symlink_to(path, target_is_directory=path.is_dir())
        return modules

    def build_run(label, level, content, negative=()):
        local = dict(env, AXIOM_PATH=str(modules_for(label, content)))
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
                                         'cases': 40, 'status': 'passed'})
        print(f'ok   typed body scopes: 40 cases at -O{level} with allocation poisoning', flush=True)
    unmapped = replace_once(original, '    (vecPush names (BEnt :name name :source source))',
                            '    { (let entry (BEnt :name name :source source))\n'
                            '      (memMarkLeaf (as entry Int)) (vecPush names entry) }',
                            'binding child reference map')
    outer = replace_once(original,
                         '(bsFindFrom (bsNamesVec b) n (- (vecLen (bsNamesVec b)) 1))',
                         '(bsFindFrom (bsNamesVec b) n (if (== (vecLen (bsNamesVec b)) 0) -1 0))',
                         'innermost binding order')
    opaque = replace_once(original, '((BoundOpaque) true)', '((BoundOpaque) false)',
                          'opaque binding classification')
    for label, content, cases in [
        ('unmapped-binding-child', unmapped, (19,)),
        ('outer-binding-first', outer, (12, 29, 30)),
        ('opaque-classification', opaque, (12, 24)),
    ]:
        failures = build_run(label, 0, content, cases)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failures)})
        print(f'ok   counterexample {label}: cases {sorted(failures)} fail', flush=True)
    refusals = [
        ('erased-scope', '(bsFind 0 "missing")', 'AX3004', ('BScope', 'Int')),
        ('erased-alias', '(bsWith (bsNew vecNew vecNew vecNew None) "value" 0)',
         'AX3004', ('BindingSource', 'Int')),
        ('missing-alias-variants', '(match BoundOpaque ((BoundParam index) index))',
         'AX3005', ('BoundOpaque',)),
    ]
    local = dict(env, AXIOM_PATH=str(modules_for('refusal', original)))
    for label, expression, code, names in refusals:
        refused = work / f'{label}.ax'
        refused.write_text('(import core)\n(import typecheck)\n(import Vec)\n'
                           f'(:: main Int)\n(fn (main) {{ {expression} 0 }})\n')
        result = subprocess.run([str(axiom), '--diagnostic-format=ai', 'check', str(refused)],
                                env=local, capture_output=True, text=True)
        (work / f'{label}.stderr').write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or f'E {code} ' not in errors[0] or any(name not in errors[0] for name in names):
            raise RuntimeError(f'{label}: lost typed refusal: {result}')
        report['refusals'].append({'name': label, 'diagnostic': code, 'status': 'passed'})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'bound-scope-report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--module-root', type=Path, help='dependency tree for a local prerequisite snapshot')
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    dependencies = (args.module_root or repo / 'core').resolve()
    if args.work:
        work = args.work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), repo, dependencies, work)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-bound-scope-') as directory:
            check(args.axiom.resolve(), repo, dependencies, Path(directory))


if __name__ == '__main__':
    main()
