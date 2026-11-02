#!/usr/bin/env python3
"""Check optional CG payload ownership, absence, precedence and lambda descriptors.

Evidence is bounded to the selected builder, host target, O0/O2 and allocation
poisoning. Each mapped invariant has a deliberate counterexample; the report
states remaining storage boundaries instead of claiming global soundness.
"""
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
(pub :: probeParams (-> CG Names CG))
(pub fn (probeParams cg params) (cgSetParams cg params))
(pub :: probeFlags (-> CG (Option Ints) CG))
(pub fn (probeFlags cg flags)
  (if (let (Some _) flags)
    (cgSetParamFlags cg flags)
    (cgClearParamFlags cg)))
(pub :: probeSelf (-> CG (Option String) CG))
(pub fn (probeSelf cg name) (cgSetTcoName cg name))
(pub :: probeSelfActive (-> CG Bool))
(pub fn (probeSelfActive cg) (cgInTailLoop cg))
(pub :: probeSelfRestore (-> CG String Bool))
(pub fn (probeSelfRestore cg expected)
  {
    (let saved (cgTcoName cg))
    (cgSetTcoName cg (None))
    (cgSetTcoName cg saved)
    (if (let (Some actual) (cgTcoName cg))
      (strEq actual expected)
      false)
  })
(pub :: probeModule (-> CG (Option String) CG))
(pub fn (probeModule cg name) (cgSetModule cg name))
'''


def check(axiom, repo, work):
    source = repo / 'tests/selfhost/emitter-context-options.axp'
    fixture = work / source.with_suffix('.ax').name
    fixture.write_bytes(source.read_bytes())
    expected = [f'{i} true' for i in range(1, 44)]
    original = (repo / 'core/codegen.ax').read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(repo / 'stdlib'))
    report = {'source_sha256': hashlib.sha256(original.encode()).hexdigest(),
              'builder': str(axiom), 'configurations': [], 'counterexamples': [], 'refusals': [],
              'invariants': [
                  {'invariant': 'Optional CG fields own replacement payloads and retire displaced payloads.',
                   'enforcement': 'Typed Option fields and field stores; cases 3,5,9,10,13,16,22,24,26,32,33.',
                   'counterexample': 'duplicate-parameter-share'},
                  {'invariant': 'Missing context values use explicit fallback and module precedence is preserved.',
                   'enforcement': 'Some/None branches in queries and mangling; cases 1,2,11,12,17-21,25,27-31,34,41-43 (Some empty versus None).',
                   'counterexample': 'lost-module-context'},
                  {'invariant': 'Lifted descriptors and their queue own typed child shares until retirement.',
                   'enforcement': 'LamDesc fields and Vec LamDesc; cases 35-40.',
                   'counterexample': 'unmapped-descriptor-children'},
              ],
              'known_limits': ['Host execution only; no Windows runtime evidence.',
                               'Numeric compatibility results and parser checked-stamp nil boundaries remain outside this context suite.',
                               'Focused tests do not establish global soundness, Rust parity or certification.']}
    run_checked([str(axiom), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)],
                env=env, stdout=work / 'fmt.stdout', stderr=work / 'fmt.stderr')

    def build_run(label, level, source, negative=()):
        modules = work / f'{label}-modules/core'
        modules.mkdir(parents=True, exist_ok=True)
        for path in (repo / 'core').iterdir():
            destination = modules / path.name
            if path.name == 'codegen.ax':
                destination.write_text(source + BRIDGES)
            elif not destination.exists():
                destination.symlink_to(path, target_is_directory=path.is_dir())
        local = dict(env, AXIOM_PATH=str(modules))
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
                                         'cases': 43, 'status': 'passed'})
        print(f'ok   context Options: 43 cases at -O{level} with allocation poisoning', flush=True)
    duplicate = replace_once(original, '(fn (cgSetParams cg params)\n  {\n',
                             '(fn (cgSetParams cg params)\n  {\n    (__retainref params)\n',
                             'duplicate parameter payload share')
    lost_module = replace_once(original, '(fn (cgModule cg)\n  cg.curModule)',
                               '(fn (cgModule cg)\n  (None))', 'module context query')
    start = original.index('(pub fn (mkLamDesc ')
    constructor = original.index('  (LamDesc\n', start)
    end = original.index('\n\n', constructor)
    body = original[constructor:end]
    unmapped = replace_once(original, body,
                            '  { (let desc ' + body.strip()[:-1] + ')\n'
                            '    (memMarkLeaf (as desc Int))\n    desc })',
                            'missing descriptor child reference map')
    for label, mutated, cases in [
        ('duplicate-parameter-share', duplicate, (3, 5, 9)),
        ('lost-module-context', lost_module, (29, 30)),
        ('unmapped-descriptor-children', unmapped, (36, 38, 40)),
    ]:
        failures = build_run(label, 0, mutated, cases)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failures)})
        print(f'ok   counterexample {label}: cases {sorted(failures)} fail', flush=True)
    local = dict(env, AXIOM_PATH=str(work / 'positive-O0-modules/core'))
    for label, body, code in [
        ('raw-module-owner', '(let cg newCG) (set cg.curModule "raw") 0', 'AX3004'),
        ('raw-lambda-row', '(let cg newCG) (vecPush cg.pendingLams 42) 0', 'AX3004'),
        ('raw-index-owner', '(let cg newCG) (set cg.bareIntern 0) 0', 'AX3004'),
        ('missing-module-none', '(match newCG.curModule ((Some name) 0))', 'AX3005'),
    ]:
        refused = work / (label + '.ax')
        refused.write_text('(import codegen)\n(import Vec)\n(:: main Int)\n(fn (main) { ' + body + ' })\n')
        result = subprocess.run([str(axiom), '--diagnostic-format=ai', 'check', str(refused)],
                                env=local, capture_output=True, text=True, timeout=60)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or f'E {code} ' not in errors[0]:
            raise RuntimeError((label, result))
        report['refusals'].append({'name': label, 'diagnostic': code, 'status': 'passed'})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'context-option-report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    if args.work:
        work = args.work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), repo, work)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-context-options-') as directory:
            check(args.axiom.resolve(), repo, Path(directory))


if __name__ == '__main__':
    main()
