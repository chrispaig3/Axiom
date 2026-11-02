#!/usr/bin/env python3
"""Check ordinary region record ownership and an acyclic checker scratch cache."""
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
(pub :: probeScratch (-> TC (Option RgnScratch)))
(pub fn (probeScratch checker) (tcRegionScratch checker))
'''


def check(axiom, repo, dependencies, work):
    fixture = work / 'region-records.ax'
    fixture.write_bytes((repo / 'tests/selfhost/typecheck-region-records.axp').read_bytes())
    expected = [f'{i} true' for i in range(1, 40)]
    original = (repo / 'core/typecheck.ax').read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(repo / 'stdlib'))
    version = subprocess.run([str(axiom), '--diagnostic-format=ai', 'version'],
                             env=env, capture_output=True, text=True, check=True).stdout.strip()
    report = {'source_sha256': hashlib.sha256(original.encode()).hexdigest(),
              'parser_sha256': hashlib.sha256((dependencies / 'parser.ax').read_bytes()).hexdigest(),
              'builder': str(axiom), 'builder_version': version,
              'configurations': [], 'counterexamples': [], 'refusals': [],
              'invariants': [
                  {'invariant': 'Facts and stack records own their typed children and retire them.',
                   'enforcement': 'RgnFacts, Vec RgEnt and scoped popped entry; cases 1-17,18-25.',
                   'counterexample': 'unmapped-facts-children'},
                  {'invariant': 'Absent facts remain conservative and present facts retain their numeric answers.',
                   'enforcement': 'Option RgnFacts branches and typed scalar fields; cases 1-15.',
                   'counterexample': 'missing-facts-keep'},
                  {'invariant': 'TC caches scratch buffers with no active context or checker backedge.',
                   'enforcement': 'RgnScratch buffer-only record and fresh RgnCtx; cases 26-36.',
                   'counterexample': 'scratch-checker-backedge'},
                  {'invariant': 'Scratch children retire after the checker owner releases its cache.',
                   'enforcement': 'Typed RgnScratch child map; cases 31,32.',
                   'counterexample': 'unmapped-scratch-children and erased-bound-name'},
              ],
              'known_limits': ['Host execution only; no Windows runtime evidence.',
                               'Evidence concerns ordinary nightly record representations, not the held M5 work.',
                               'Traversal, fixpoint, lifetime enforcement, numeric masks and statuses are unchanged.',
                               'Ordinary diagnostic controls cover scalar acceptance and two AX3059 shapes only.',
                               'Focused evidence does not establish global soundness, Rust parity or certification.']}
    run_checked([str(axiom), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)],
                env=env, stdout=work / 'fmt.stdout', stderr=work / 'fmt.stderr')

    def modules_for(label, content):
        modules = work / f'{label}-modules/core'
        modules.mkdir(parents=True, exist_ok=True)
        for path in dependencies.iterdir():
            destination = modules / path.name
            if path.name == 'typecheck.ax':
                destination.write_text(content + BRIDGE)
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
                                         'cases': 39, 'status': 'passed'})
        print(f'ok   region records: 39 cases at -O{level} with allocation poisoning', flush=True)
    missing = replace_once(original, '(rgnAnyFlow (rgnFlowsFrom facts) 0))\n    1))',
                           '(rgnAnyFlow (rgnFlowsFrom facts) 0))\n    0))', 'missing facts conservative result')
    start = original.index('      (RgnFacts\n')
    end = original.index(':mayEnter 0)', start) + len(':mayEnter 0)')
    constructor = original[start:end]
    facts = replace_once(original, constructor,
                         '      { (let facts ' + constructor.strip() + ')\n'
                         '        (memMarkLeaf (as facts Int)) facts }', 'facts child reference map')
    cycle = replace_once(original, '(pub struct RgnScratch\n',
                         '(pub struct RgnScratch\n  (checker : TC)\n', 'scratch backedge field')
    cycle = replace_once(cycle, '        (RgnScratch\n',
                         '        (RgnScratch\n          :checker tc\n', 'scratch backedge owner')
    scratch = replace_once(original, '      (tcSetRegionScratch tc (Some fresh))',
                           '      (memMarkLeaf (as fresh Int))\n      (tcSetRegionScratch tc (Some fresh))',
                           'scratch child reference map')
    erased_name = replace_once(original, '(let names (rgnNames rc))\n    (vecPush names name)',
                               '(let names (rgnNames rc))\n    (vecPushStr names name)',
                               'typed scratch name ownership')
    for label, content, cases in [
        ('unmapped-facts-children', facts, (17,)),
        ('missing-facts-keep', missing, (2,)),
        ('scratch-checker-backedge', cycle, (27, 28, 32)),
        ('unmapped-scratch-children', scratch, (32,)),
        ('erased-bound-name', erased_name, (32,)),
    ]:
        failures = build_run(label, 0, content, cases)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failures)})
        print(f'ok   counterexample {label}: cases {sorted(failures)} fail', flush=True)
    local = dict(env, AXIOM_PATH=str(modules_for('refusal', original)))
    for label, expression, code, names in [
        ('erased-facts', '(rgnFlowsCUR 0)', 'AX3004', ('RgnFacts', 'Int')),
        ('erased-region-name', '(rgPush (tcNew vecNew vecNew vecNew) 0 0 0)', 'AX3004', ('String', 'Int')),
        ('missing-facts-case', '(match (fnEntRgn (entry "missing")) ((Some facts) (rgnNparams facts)))',
         'AX3005', ('None',)),
    ]:
        refused = work / f'{label}.ax'
        # Reuse only the independent entry constructor from the positive template.
        template = fixture.read_text()
        begin = template.index('(:: entry ')
        finish = template.index('(:: holdFactsName ', begin)
        refused.write_text('(import core)\n(import parser)\n(import typecheck)\n(import Vec)\n'
                           + template[begin:finish] + f'(:: main Int)\n(fn (main) {{ {expression} 0 }})\n')
        result = subprocess.run([str(axiom), '--diagnostic-format=ai', 'check', str(refused)],
                                env=local, capture_output=True, text=True)
        (work / f'{label}.stderr').write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or f'E {code} ' not in errors[0] or any(name not in errors[0] for name in names):
            raise RuntimeError(f'{label}: lost typed refusal: {result}')
        report['refusals'].append({'name': label, 'diagnostic': code, 'status': 'passed'})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'region-record-report.json').write_text(json.dumps(report, indent=2) + '\n')


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
        with tempfile.TemporaryDirectory(prefix='axiom-region-records-') as directory:
            check(args.axiom.resolve(), repo, dependencies, Path(directory))


if __name__ == '__main__':
    main()
