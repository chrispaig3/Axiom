#!/usr/bin/env python3
"""Check typed constructor lookup, optional misses, spelling and pair eligibility."""
import argparse
import os
from pathlib import Path
import re
import runpy
import subprocess
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).with_name('emitter-line-buffer.py')))
run_checked = SUPPORT['run_checked']
replace_once = SUPPORT['replace_once']
check_output = SUPPORT['check_output']
emitted_function = SUPPORT['emitted_function']


def check(axiom, repo, work):
    source = repo / 'tests/selfhost/emitter-type-registry.axp'
    fixture = work / source.with_suffix('.ax').name
    fixture.write_bytes(source.read_bytes())
    expected = [f'{i} true' for i in range(1, 15)]
    original = (repo / 'core/codegen.ax').read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(repo / 'stdlib'))
    run_checked([str(axiom), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)],
                env=env, stdout=work / 'fmt.stdout', stderr=work / 'fmt.stderr')

    def build_run(label, level, source, negative=()):
        modules = work / f'{label}-modules/core'
        modules.mkdir(parents=True, exist_ok=True)
        for path in (repo / 'core').iterdir():
            destination = modules / path.name
            if path.name == 'codegen.ax':
                destination.write_text(source)
            elif not destination.exists():
                destination.symlink_to(path, target_is_directory=path.is_dir())
        local = dict(env, AXIOM_PATH=str(modules))
        binary = work / label
        run_checked([str(axiom), '--diagnostic-format=ai', 'build', str(fixture),
                     '--opt', str(level), '--alloc-poison', '--emit-llvm', '-o', str(binary)],
                    env=local, stdout=work / f'{label}.build.stdout', stderr=work / f'{label}.build.stderr')
        output = work / f'{label}.stdout'
        run_checked([str(binary)], env=local, stdout=output, stderr=work / f'{label}.stderr', timeout=30)
        failures = check_output(output, expected, required_failures=negative)
        if not negative:
            module = binary.with_suffix('.ll').read_text()
            body = emitted_function(module, 'codegen$addTypeNamed')
            stores = re.findall(r'@Vec\$vecPush\(i64 [^,]+, i64 [^,]+, i64 ([01])\)', body)
            if stores != ['1']:
                raise RuntimeError(f'type registry must own its TypeEntry payload: {stores}')
        return failures

    for level in (0, 2):
        build_run(f'positive-O{level}', level, original)
        print(f'ok   typed constructor registry: 14 cases at -O{level} with allocation poisoning', flush=True)
    for label, expression, message in [
        ('main-missing', '(emitMainResultTail newCG 0)', 'missing result constructor: Err$Ok'),
        ('pair-missing', '(emitPairBoxResult newCG nilNode "%tag" "%payload")',
         'missing pair constructor: Err$Ok'),
    ]:
        missing = work / f'{label}.ax'
        missing.write_text('(import codegen)\n(import core)\n(:: main Int)\n'
                           ';@axiom:effect(io)\n(fn (main) { ' + expression + ' 0 })\n')
        local = dict(env, AXIOM_PATH=str(repo / 'core'))
        binary = work / label
        run_checked([str(axiom), '--diagnostic-format=ai', 'build', str(missing),
                     '--opt', '0', '--alloc-poison', '-o', str(binary)],
                    env=local, stdout=work / f'{label}.build.stdout', stderr=work / f'{label}.build.stderr')
        result = subprocess.run([str(binary), '--diagnostic-format=ai'], env=local,
                                capture_output=True, text=True, timeout=30)
        if result.returncode != 3 or 'AX4002' not in result.stderr or message not in result.stderr:
            raise RuntimeError(f'{label}: absent required entry lost its error: {result}')
        print(f'ok   {label}: absent required constructor reports AX4002 and exits 3', flush=True)

    variants = [
        ('name-collision', replace_once(original,
                                       '(&& (== (eNameLen e) nLen) (strEq (eName e) name))',
                                       '(== (eNameLen e) nLen)', 'full spelling comparison'), (1, 3, 14)),
        ('pair-arity', replace_once(original, '(if (!= (eArity en) want)',
                                   '(if false', 'pair constructor arity'), (10, 11)),
    ]
    for label, source, negative in variants:
        failures = build_run(label, 0, source, negative)
        print(f'ok   negative probe {label}: cases {sorted(failures)} fail', flush=True)


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
        with tempfile.TemporaryDirectory(prefix='axiom-type-registry-') as directory:
            check(args.axiom.resolve(), repo, Path(directory))


if __name__ == '__main__':
    main()
