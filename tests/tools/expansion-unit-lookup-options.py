#!/usr/bin/env python3
"""Pin present and missing expansion units before a diagnostic needs an index."""

import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def replace_once(source, old, new, label):
    count = source.count(old)
    if count != 1:
        raise AssertionError((label, count))
    return source.replace(old, new, 1)


def run(command, environment, root, timeout=240):
    result = subprocess.run(command, cwd=root, env=environment,
                            capture_output=True, text=True, timeout=timeout)
    return result


def check(compiler, root, work):
    fixture = root / 'tests/tools/expansion-unit-lookup-options.axp'
    source_path = root / 'core/expand.ax'
    source = source_path.read_text()
    source_hash = hashlib.sha256(source.encode()).hexdigest()
    builder_hash = hashlib.sha256(compiler.read_bytes()).hexdigest()
    expected = ''.join(f'{index} true\n' for index in range(1, 17))
    environment = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'),
                       AXIOM_PATH=str(root / 'core'))
    report = {'source_sha256': source_hash, 'builder_sha256': builder_hash,
              'positive': [], 'effective_controls': [], 'refusals': []}

    def modules(label, expansion):
        folder = work / (label + '-modules')
        folder.mkdir()
        for path in (root / 'core').iterdir():
            destination = folder / path.name
            if path.name == 'expand.ax':
                destination.write_text(expansion)
            else:
                destination.symlink_to(path, target_is_directory=path.is_dir())
        return dict(environment, AXIOM_PATH=str(folder))

    def build_run(label, level, local):
        executable = work / label
        built = run([str(compiler), '--diagnostic-format=ai', 'build',
                     str(fixture), '--opt', str(level), '--alloc-poison',
                     '-o', str(executable)], local, root)
        if built.returncode != 0:
            raise AssertionError((label, 'build', built.stdout, built.stderr))
        observed = run([str(executable)], local, root, timeout=30)
        (work / (label + '.stdout')).write_text(observed.stdout)
        (work / (label + '.stderr')).write_text(observed.stderr)
        return observed

    for level in (0, 2):
        result = build_run('positive-O' + str(level), level, environment)
        assert result.returncode == 0 and result.stdout == expected and not result.stderr, (
            level, result.returncode, result.stdout, result.stderr)
        report['positive'].append({'opt': level, 'cases': 16, 'allocation_poisoning': True})
        print(f'ok   unit lookup: 16 cases O{level} poison', flush=True)

    controls = [
        ('missing-forged',
         replace_once(source,
                      '(pub fn (expUnitOfModFrom units m i)\n  (if (>= i (vecLen units))\n    None',
                      '(pub fn (expUnitOfModFrom units m i)\n  (if (>= i (vecLen units))\n    (Some 0)',
                      'missing-forged'), '1 false'),
        ('missing-file-fallback',
         replace_once(source,
                      '(pub fn (expAsmFileFor units module)\n  (match (expUnitOfMod units module)\n    ((None) "")',
                      '(pub fn (expAsmFileFor units module)\n  (match (expUnitOfMod units module)\n    ((None) (unitFile (vecGet units 0)))',
                      'missing-file-fallback'), '10 false'),
        ('missing-diag-fallback',
         replace_once(source,
                      '(pub fn (expUnitForDiag units m)\n  (match (expUnitOfMod units m)\n    ((None) 0)',
                      '(pub fn (expUnitForDiag units m)\n  (match (expUnitOfMod units m)\n    ((None) 1)',
                      'missing-diag-fallback'), '11 false'),
    ]
    for name, changed, required in controls:
        result = build_run(name, 0, modules(name, changed))
        assert required in result.stdout.splitlines(), (name, result.returncode, result.stdout, result.stderr)
        report['effective_controls'].append({'name': name, 'required_output': required})
        print(f'ok   {name}: effective counterexample', flush=True)

    refusals = [
        ('raw-unit-index', '(+ 1 (expUnitOfMod (:: vecNew Units) None))', 'AX3004'),
        ('missing-none', '(match (expUnitOfMod (:: vecNew Units) None) ((Some u) u))', 'AX3005'),
        ('missing-some', '(match (expUnitOfMod (:: vecNew Units) None) ((None) 0))', 'AX3005'),
    ]
    for name, expression, code in refusals:
        probe = work / (name + '.ax')
        probe.write_text('(import core)\n(import expand)\n(import Vec)\n'
                         '(:: main Int)\n(fn (main) ' + expression + ')\n')
        result = run([str(compiler), '--diagnostic-format=ai', 'check', str(probe)],
                     environment, root, timeout=60)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and f'E {code} ' in errors[0], (
            name, result.returncode, result.stderr)
        report['refusals'].append({'name': name, 'code': code})
        print(f'ok   {name}: {code}', flush=True)

    assert hashlib.sha256(source_path.read_bytes()).hexdigest() == source_hash
    assert hashlib.sha256(compiler.read_bytes()).hexdigest() == builder_hash
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), root, args.work.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-exp-unit-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
