#!/usr/bin/env python3
"""Check the expander's counted interner owner without changing lookup semantics."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('compiler', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    compiler = str(args.compiler.resolve())
    fixture = (root / 'tests/tools/expansion-interner-owner.axp').read_text()
    env = dict(os.environ, AXIOM_PATH=str(root / 'core'), AXIOM_STDLIB=str(root / 'stdlib'))
    expected = ''.join(f'{i} true\n' for i in range(1, 15))
    report = {'cases': 14, 'configurations': [], 'controls': [], 'refusals': [],
              'limits': 'Counted interner only; raw Intern APIs borrow the held owner. QmSt and pre-existing AST reader retention remain separate. No lifetime algorithms or held M5 work.'}
    with tempfile.TemporaryDirectory(prefix='axiom-expansion-interner-owner-') as directory:
        work = Path(directory)

        def native(label, text, level, failed=None):
            source = work / (label + '.ax')
            source.write_text(text)
            out = work / label
            built = subprocess.run([compiler, '--diagnostic-format=ai', 'build', str(source),
                                    '--opt', str(level), '--alloc-poison', '-o', str(out)],
                                   env=env, capture_output=True, text=True, timeout=240)
            assert built.returncode == 0, (label, built.stdout, built.stderr)
            ran = subprocess.run([str(out)], capture_output=True, text=True, timeout=30)
            assert ran.returncode == 0 and not ran.stderr, (label, ran)
            if failed is None:
                assert ran.stdout == expected, (label, ran.stdout)
            else:
                lines = ran.stdout.splitlines()
                assert len(lines) == 14 and lines[failed-1] == f'{failed} false', (label, ran.stdout)
                assert all(line in (f'{i} true', f'{i} false') for i, line in enumerate(lines, 1))
            print('ok   ' + label, flush=True)

        for level in (0, 2):
            native('positive-O' + str(level), fixture, level)
            report['configurations'].append({'optimization': level, 'poison': True, 'outcomes': 14})
        assert fixture.count(':structNames owner') == 1
        native('copied-owner', fixture.replace(':structNames owner', ':structNames internNewTyped'), 0, 2)
        report['controls'].append({'mutation': 'copied-owner', 'fails': 2})
        needle = '(fn (environment diagnostics units declarations owner)\n  (MEnv'
        assert fixture.count(needle) == 1
        changed = fixture.replace(needle, '(fn (environment diagnostics units declarations owner)\n  { (let held (MEnv')
        # The leaf mark closes the whole `MEnv` literal. The last field
        # is the anchor: an earlier field leaves the new fields outside
        # the `let`, so the mutant no longer builds.
        needle = ':optNames vecNew))'
        assert changed.count(needle) == 1
        changed = changed.replace(needle, ':optNames vecNew))\n    (memMarkLeaf (as held Int)) held })')
        native('lost-owner-map', changed, 0, 1)
        report['controls'].append({'mutation': 'lost-owner-map', 'fails': 1})
        for label, declaration in [
                ('erased-field', '(:: bad (-> MEnv Int)) (fn (bad env) env.structNames)'),
                ('unborrowed-raw-api', '(:: bad (-> MEnv Int)) (fn (bad env) (internCap env.structNames))')]:
            source = work / (label + '.ax')
            source.write_text('(import expand)\n(import Intern)\n' + declaration + '\n(:: main Int) (fn (main) 0)\n')
            checked = subprocess.run([compiler, '--diagnostic-format=ai', 'check', str(source)],
                                     env=env, capture_output=True, text=True, timeout=60)
            errors = [line for line in checked.stderr.splitlines() if line.startswith('E ')]
            assert checked.returncode == 1 and len(errors) == 1 and 'E AX3004 ' in errors[0], (label, checked)
            report['refusals'].append({'case': label, 'code': 'AX3004'})
            print('ok   ' + label + ': AX3004', flush=True)
        (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
        print('ok   expander interner owner: 14 cases O0/O2 poison, two effective controls, two refusals', flush=True)


if __name__ == '__main__':
    main()
