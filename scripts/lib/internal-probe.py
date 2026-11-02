#!/usr/bin/env python3
"""Compile listed raw-storage fixtures inside an isolated copy of the library.

All other compiler invocations pass through unchanged. Copies made by ablation
runners qualify only when their complete bytes match a listed fixture. An
explicit --fixture names a listed template for gate-owned instrumentation.
"""
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

ROOT = Path(__file__).resolve().parents[2]
MANIFEST = ROOT / 'tests/internal-probes.txt'


def main():
    arguments = sys.argv[1:]
    explicit = None
    if arguments[:1] == ['--fixture']:
        explicit = (ROOT / arguments[1]).resolve()
        arguments = arguments[2:]
    compiler, *arguments = arguments
    fixtures = [ROOT / line for line in MANIFEST.read_text().splitlines()
                if line and not line.startswith('#')]
    if explicit is not None and explicit not in fixtures:
        raise ValueError(f'unlisted probe template: {explicit}')
    sources = [(i, Path(arg).resolve()) for i, arg in enumerate(arguments)
               if arg.endswith('.ax') and Path(arg).is_file()]
    selected = None
    for index, source in sources:
        if explicit is not None or source in fixtures or any(source.read_bytes() == fixture.read_bytes()
                                     for fixture in fixtures if fixture.suffix == ".ax"):
            selected = index, source
            break
    if selected is None and explicit is not None:
        raise ValueError('instrumented probe has no source argument')
    if selected is None:
        return subprocess.call([compiler, *arguments])
    index, source = selected
    original = source.read_text()
    # A fixture remains ordinary source on disk. Only this private library copy
    # receives imports of the production implementations it probes.
    transformed, signatures = re.subn(r'\((?:pub )?:: main\b', '(pub :: internalProbeMain', original)
    transformed, bodies = re.subn(r'\((?:pub )?fn \(main\b', '(pub fn (internalProbeMain', transformed)
    if bodies != 1 or signatures > 1:
        raise ValueError(f'unsupported probe entry point: {source}')
    entry_tags = re.search(r'((?:;[^\n]*\n)*)\((?:pub )?fn \(main\b', original).group(1)
    # The outer shim only calls a trusted library function; unsafe operations
    # and their claim stay on the original fixture body.
    entry_tags = entry_tags.replace(';@axiom:effect(unsafe)\n', '')
    with tempfile.TemporaryDirectory(prefix='axiom-internal-probe-') as temporary:
        work = Path(temporary)
        library = work / 'stdlib'
        shutil.copytree(Path(os.environ.get('AXIOM_STDLIB', ROOT / 'stdlib')).resolve(), library)
        (library / 'InternalProbeFixture.ax').write_text(
            '(import Internal.Wait)\n(import Internal.Mapping)\n(import Internal.Platform)\n(import Internal.ProcessRaw)\n(import Internal.CryptoBytes)\n(import Internal.CryptoCt)\n(import Internal.Intern)\n' + transformed)
        entry = work / 'probe.ax'
        entry.write_text('(import InternalProbeFixture)\n' + entry_tags +
                         '(fn (main) internalProbeMain)\n')
        env = dict(os.environ, AXIOM_STDLIB=str(library))
        # Fixture-local helpers stay resolvable when its entry moves into the library.
        env['AXIOM_PATH'] = str(source.parent) + (os.pathsep + env['AXIOM_PATH'] if env.get('AXIOM_PATH') else '')
        arguments[index] = str(entry)
        return subprocess.call([compiler, *arguments], env=env)


if __name__ == '__main__':
    sys.exit(main())
