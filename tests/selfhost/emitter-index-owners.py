#!/usr/bin/env python3
"""Check typed name-index ownership, absence, declaration order and precedence."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).with_name('emitter-line-buffer.py')))
run_checked = SUPPORT['run_checked']
replace_once = SUPPORT['replace_once']
check_output = SUPPORT['check_output']


def check(axiom, repo, work):
    template = (repo / 'tests/selfhost/emitter-index-owners.axp').read_text()
    expected = [f'{i} true' for i in range(1, 39)]
    original = (repo / 'core/codegen.ax').read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(repo / 'stdlib'))
    report = {'source_sha256': hashlib.sha256(original.encode()).hexdigest(),
              'builder': str(axiom), 'configurations': [], 'counterexamples': [],
              'invariants': [
                  {'invariant': 'Absent indexes explicitly fall back; an empty built index is present.',
                   'enforcement': 'Option owner branches; cases 1-10,17-19,30-34.',
                   'counterexample': 'missing-index-fallback'},
                  {'invariant': 'Declaration arity and mangling preserve first-writer and module precedence.',
                   'enforcement': 'DeclIndex tables and indexed lookup; cases 11-28.',
                   'counterexample': 'last-writer-arity'},
                  {'invariant': 'The typed aggregate retires all five child shares and replacement retires the old aggregate.',
                   'enforcement': 'DeclIndex fields and Option field stores; cases 29,35-38.',
                   'counterexample': 'unmapped-index-children'},
              ],
              'known_limits': ['Host execution only; no Windows runtime evidence.',
                               'Numeric arity compatibility results remain an explicit protocol outside this owner-carrier suite.',
                               'Focused evidence does not establish global soundness, Rust parity or certification.']}

    def build_run(label, level, module, fixture=template, negative=()):
        source = work / f'{label}.ax'
        source.write_text(fixture)
        run_checked([str(axiom), '--diagnostic-format=ai', 'fmt', '--check', str(source)],
                    env=env, stdout=work / f'{label}.fmt.stdout', stderr=work / f'{label}.fmt.stderr')
        modules = work / f'{label}-modules/core'
        modules.mkdir(parents=True, exist_ok=True)
        for path in (repo / 'core').iterdir():
            destination = modules / path.name
            if path.name == 'codegen.ax':
                destination.write_text(module)
            elif not destination.exists():
                destination.symlink_to(path, target_is_directory=path.is_dir())
        local = dict(env, AXIOM_PATH=str(modules))
        binary = work / label
        run_checked([str(axiom), '--diagnostic-format=ai', 'build', str(source),
                     '--opt', str(level), '--alloc-poison', '-o', str(binary)],
                    env=local, stdout=work / f'{label}.build.stdout', stderr=work / f'{label}.build.stderr')
        output = work / f'{label}.stdout'
        run_checked([str(binary)], env=local, stdout=output, stderr=work / f'{label}.stderr', timeout=30)
        return check_output(output, expected, required_failures=negative)

    for level in (0, 2):
        build_run(f'positive-O{level}', level, original)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True,
                                         'cases': 38, 'status': 'passed'})
        print(f'ok   index owners: 38 cases at -O{level} with allocation poisoning', flush=True)
    fallback = replace_once(original, '      (mangledFor cg name))\n    (mangledFor cg name)))',
                            '      name)\n    (mangledFor cg name)))', 'missing declaration-index fallback')
    last = replace_once(original, '(if (< (vecGet dar id) 0)', '(if true', 'first declaration arity')
    unmapped = replace_once(template, '    (set cg.bareFirst (Some index))\n',
                            '    (memMarkLeaf (as index Int))\n    (set cg.bareFirst (Some index))\n',
                            'aggregate reference map counterexample')
    # The fixture mutation is deliberately formatted before checking it.
    fixture = work / 'unmapped-format.ax'
    fixture.write_text(unmapped)
    run_checked([str(axiom), '--diagnostic-format=ai', 'fmt', str(fixture)],
                env=env, stdout=work / 'unmapped-format.stdout', stderr=work / 'unmapped-format.stderr')
    for label, source, fixture, cases in [
        ('missing-index-fallback', fallback, template, (30,)),
        ('last-writer-arity', last, template, (15, 16)),
        ('unmapped-index-children', original, fixture.read_text(), (36, 37, 38)),
    ]:
        failures = build_run(label, 0, source, fixture, cases)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failures)})
        print(f'ok   counterexample {label}: cases {sorted(failures)} fail', flush=True)
    (work / 'index-owner-report.json').write_text(json.dumps(report, indent=2) + '\n')


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
        with tempfile.TemporaryDirectory(prefix='axiom-index-owners-') as directory:
            check(args.axiom.resolve(), repo, Path(directory))


if __name__ == '__main__':
    main()
