#!/usr/bin/env python3
"""User source paths cannot grant the library's erasure exemption."""
import argparse
from collections import Counter
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

UNTAGGED = '''(pub :: eraseWord (-> String Int))
(pub fn (eraseWord value) (as value Int))
'''
TAGGED = UNTAGGED.replace('(pub fn', ';@axiom:effect(unsafe)\n(pub fn')
ENTRY = '''(:: main Int)
(fn (main) 0)
'''
LIBRARY_CLIENT = '''(import ErasurePathProbe)
(:: main Int)
(fn (main) { (eraseWord "live owner") 0 })
'''


def check(compiler, root, work):
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    env.pop('AXIOM_STDLIB_PATH', None)
    fixture = (root / 'tests/diagnostics/1510-erasing-cast.ax').read_bytes()
    baseline = None
    checked = 0

    def run(source, local, expected):
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(source)],
                                env=local, capture_output=True, text=True, timeout=120)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        codes = Counter(line.split()[1] for line in errors)
        if result.returncode != (1 if expected else 0) or codes != Counter(expected):
            raise AssertionError((str(source), result.returncode, codes, expected,
                                  result.stdout, result.stderr))
        return [line.replace(str(source), '<source>') for line in errors]

    # The module carries the same untagged body as the refused user input.
    # Only the loader's genuine library classification grants this exemption.
    library = work / 'private-library'
    shutil.copytree(root / 'stdlib', library)
    (library / 'ErasurePathProbe.ax').write_text(UNTAGGED)
    library_env = dict(env, AXIOM_STDLIB=str(library))
    for relative in ('ordinary', 'core', 'nested/core', 'core/nested', 'stdlib'):
        directory = work / relative
        directory.mkdir(parents=True)
        source = directory / 'fixture.ax'
        source.write_bytes(fixture)
        errors = run(source, env, {'AX3073': 8, 'AX3049': 2, 'AX3010': 1})
        if baseline is None:
            baseline = errors
        elif errors != baseline:
            raise AssertionError(('directory changed diagnostics', relative, baseline, errors))
        checked += 1
        source.write_text(UNTAGGED + ENTRY)
        run(source, env, {'AX3073': 1})
        checked += 1
        source.write_text(TAGGED + ENTRY)
        run(source, env, {})
        checked += 1
        source.write_text(LIBRARY_CLIENT)
        run(source, library_env, {})
        checked += 1
        print(f'ok   {relative}: identical 1510 refusals, untagged refusal, tagged and library controls', flush=True)
    print(f'ok   erasure path boundary: {checked} checks across five directory layouts', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--source-root', type=Path)
    args = parser.parse_args()
    root = (args.source_root or Path(__file__).resolve().parents[2]).resolve()
    with tempfile.TemporaryDirectory(prefix='axiom-erasure-path-') as directory:
        check(args.axiom.resolve(), root, Path(directory).resolve())


if __name__ == '__main__':
    main()
