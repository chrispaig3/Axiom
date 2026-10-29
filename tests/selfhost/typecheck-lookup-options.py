#!/usr/bin/env python3
"""Check optional function/type-variable/import lookup and divergence ownership."""
import argparse
import os
from pathlib import Path
import subprocess
import tempfile


def execute(arguments, environment):
    return subprocess.run(arguments, env=environment, capture_output=True, text=True, timeout=180)


def check(compiler, root, work):
    original = (root / 'core/typecheck.ax').read_text()
    source = root / 'tests/selfhost/typecheck-lookup-options.axp'
    environment = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    expected = [f'{index} true' for index in range(1, 37)]

    def modules(label, contents):
        directory = work / (label + '-modules')
        directory.mkdir()
        for path in (root / 'core').iterdir():
            destination = directory / path.name
            if path.name == 'typecheck.ax':
                destination.write_text(contents)
            else:
                destination.symlink_to(path, target_is_directory=path.is_dir())
        return dict(environment, AXIOM_PATH=str(directory))

    def build_run(label, contents, level, failures):
        local = modules(label, contents)
        binary = work / label
        built = execute([str(compiler), '--diagnostic-format=ai', 'build', str(source),
                         '--opt', str(level), '--alloc-poison', '-o', str(binary)], local)
        assert built.returncode == 0, (label, built.stdout, built.stderr)
        result = execute([str(binary)], local)
        assert result.returncode == 0 and result.stderr == '', (label, result)
        lines = result.stdout.splitlines()
        assert len(lines) == len(expected), (label, lines)
        observed = {index + 1 for index, line in enumerate(lines) if line != expected[index]}
        assert observed == set(failures), (label, observed, failures, lines)
        print('ok   ' + label, flush=True)

    for level in (0, 2):
        build_run('positive-O' + str(level), original, level, ())
    start = original.index('(pub fn (findFnDecl ')
    end = original.index('(pub :: bareNameIs ', start)
    function = original[start:end]
    assert function.count('(set i n)') == 1
    changed = original[:start] + function.replace('(set i n)', '()') + original[end:]
    build_run('last-definition', changed, 0, (2, 4))
    start = original.index('(pub fn (divRound ')
    end = original.index('\n\n', start)
    function = original[start:end]
    assert function.count('(vecPush out name)') == 1
    changed = original[:start] + function.replace('(vecPush out name)', '()') + original[end:]
    build_run('lost-divergence-candidate', changed, 0, (25,))
    marker = '(if (nodeSame body nilNode)\n        None\n        (Some body))'
    assert original.count(marker) == 1
    build_run('missing-body-is-present', original.replace(marker, '(Some body)'), 0, (6,))
    local = modules('refusals', original)
    for name, expression, code in [
        ('unchecked-declaration', '(nodeTag (findFnDecl vecNew "missing"))', 'AX3004'),
        ('missing-none', '(match (firstResultOnly vecNew vecNew 0) ((Some name) (strLen name)))', 'AX3005'),
        ('erased-names', '(firstResultOnly (:: vecNew (Vec Int)) vecNew 0)', 'AX3004'),
    ]:
        refused = work / (name + '.ax')
        refused.write_text('(import core)\n(import parser)\n(import typecheck)\n(import Vec)\n(import Str)\n'
                           '(:: main Int)\n(fn (main) { ' + expression + ' 0 })\n')
        result = execute([str(compiler), '--diagnostic-format=ai', 'check', str(refused)], local)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and f'E {code} ' in errors[0], (name, result)
        print('ok   ' + name + ': ' + code, flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', required=True, type=Path)
    arguments = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    with tempfile.TemporaryDirectory(prefix='axiom-checker-lookups-') as directory:
        check(arguments.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
