#!/usr/bin/env python3
"""Confirmed erasures support unsafe claims, including in compiler/library files."""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def check(compiler, repo, work):
    library = work / 'stdlib'
    shutil.copytree(repo / 'stdlib', library)
    core = work / 'core'
    core.mkdir()
    env = dict(os.environ, AXIOM_STDLIB=str(library))
    cases = [
        ('Erasure', 'String', 'Int', '(as value Int)', []),
        ('Noop', 'Int', 'Int', 'value', ['AX3010']),
        ('Numeric', 'Int', 'Int', '(as value Int)', ['AX3010']),
        ('Identity', 'String', 'String', '(as value String)', ['AX3010']),
    ]
    for location in ('core', 'library'):
        for name, argument, answer, expression, expected in cases:
            public = 'pub ' if location == 'library' else ''
            source = (f'({public}:: probe (-> {argument} {answer}))\n'
                      ';@axiom:effect(unsafe)\n'
                      f'({public}fn (probe value) {expression})\n')
            if location == 'library':
                module = 'ErasureClaim' + name
                (library / (module + '.ax')).write_text(source)
                entry = work / (name + '.ax')
                entry.write_text(f'(import {module})\n(:: main Int)\n(fn (main) 0)\n')
            else:
                entry = core / (name + '.ax')
                entry.write_text(source + '(:: main Int)\n(fn (main) 0)\n')
            result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(entry)],
                                    env=env, capture_output=True, text=True)
            output = result.stdout + result.stderr
            codes = re.findall(r'^E (AX\d+)', output, re.M)
            if codes != expected or result.returncode != int(bool(expected)):
                raise AssertionError(f'{location}/{name}: expected {expected}, got exit '
                                     f'{result.returncode}\n{output}')
            print(f'ok {location}/{name}: {codes}', flush=True)

    fixture = repo / 'tests/diagnostics/1510-erasing-cast.ax'
    result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', fixture.name],
                            cwd=fixture.parent, env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, text=True)
    diagnostics = ''.join(line + '\n' for line in result.stdout.splitlines()
                          if line.startswith(('E ', 'W ', 'N ')))
    expected = fixture.with_suffix('.axdl').read_text()
    if result.returncode != 1 or diagnostics != expected:
        raise AssertionError('1510 diagnostics differ from its golden:\n' + result.stdout)
    print('ok 1510: exact diagnostic golden', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', required=True, type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix='axiom-erasure-claim-') as directory:
        check(args.axiom.resolve(), repo, Path(directory))


if __name__ == '__main__':
    main()
