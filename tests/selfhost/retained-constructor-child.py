#!/usr/bin/env python3
"""Keep counted constructor children while retiring their container owners."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def execute(arguments, environment, log, timeout=240):
    result = subprocess.run(arguments, env=environment, capture_output=True,
                            text=True, timeout=timeout)
    log.write_text(result.stdout + result.stderr)
    if result.returncode:
        raise RuntimeError(f'{arguments}: exit {result.returncode}: {log}')
    return result


def check(compiler, root, work):
    environment = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    fixture = work / 'retained-child.ax'
    fixture.write_bytes((root / 'tests/selfhost/retained-constructor-child.axp').read_bytes())
    expected = [f'{index} true' for index in range(1, 14)]
    execute([str(compiler), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)],
            environment, work / 'fmt.log')

    def build_run(builder, label, level):
        binary = work / label
        execute([str(builder), '--diagnostic-format=ai', 'build', str(fixture),
                 '--opt', str(level), '--alloc-poison', '--emit-llvm', '-o', str(binary)],
                environment, work / (label + '.build.log'))
        result = execute([str(binary)], environment, work / (label + '.run.log'), 30)
        lines = result.stdout.splitlines()
        if result.stderr or len(lines) != len(expected):
            raise RuntimeError(f'{label}: unexpected output {result}')
        failures = {index + 1 for index, line in enumerate(lines) if line != expected[index]}
        return failures

    for level in (0, 2):
        failures = build_run(compiler, f'positive-O{level}', level)
        if failures:
            raise RuntimeError(f'counted child ownership failures: {failures}')
        print(f'ok   counted children and raw owner words: 13 cases at O{level} with poisoning', flush=True)

    original = (root / 'core/codegen.ax').read_text()
    start = original.index('(pub fn (retainedFieldWordFlow ')
    finish = original.index('\n\n', start) + 2
    function = original[start:finish]
    report = []
    for label, body, required in [('old-owner-park', '(wordParts flow)', {2, 5, 7}),
                                   ('count-every-field', '(wordPart flow)', {11}),
                                   ('old-weak-park', None, {13})]:
        modules = work / (label + '-modules/core')
        modules.mkdir(parents=True)
        if body is None:
            begin = original.index('(pub fn (argumentWordFlow ')
            end = original.index('; The declared type node ', begin)
            changed = original[:begin] + '(pub fn (argumentWordFlow cg argument flow) (wordParts flow))\n\n' + original[end:]
        else:
            changed = original[:start] + '(pub fn (retainedFieldWordFlow retainCode flow)\n  ' + body + ')\n\n' + original[finish:]
        if label == 'count-every-field':
            begin = changed.index('(pub fn (ctorFieldParks ')
            end = changed.index('(pub :: mentionsArgs ', begin)
            changed = changed[:begin] + '(pub fn (ctorFieldParks cg entry e tn i) 0)\n\n' + changed[end:]
        for path in (root / 'core').iterdir():
            destination = modules / path.name
            if path.name == 'codegen.ax':
                destination.write_text(changed)
            else:
                destination.symlink_to(path, target_is_directory=path.is_dir())
        builder = work / (label + '-compiler')
        local = dict(environment, AXIOM_PATH=str(modules))
        execute([str(compiler), '--diagnostic-format=ai', 'build', str(modules / 'main.ax'),
                 '--opt', '0', '-o', str(builder)], local, work / (label + '.compiler.log'))
        failures = build_run(builder, label, 0)
        if not required <= failures:
            raise RuntimeError(f'{label}: counterexample lost {required}: {failures}')
        report.append({'mutation': label, 'failed_cases': sorted(failures)})
        print(f'ok   counterexample {label}: cases {sorted(failures)} fail', flush=True)
    (work / 'retained-child-report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), root, args.work.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-retained-child-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
