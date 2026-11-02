#!/usr/bin/env python3
"""Check typed effect registry retention, optional misses and lookup precedence."""
import argparse
import os
from pathlib import Path
import runpy
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).with_name('emitter-line-buffer.py')))
run_checked = SUPPORT['run_checked']
replace_once = SUPPORT['replace_once']
check_output = SUPPORT['check_output']

BRIDGE = r'''
(pub :: probeEffectModule (-> CG String CG))
(pub fn (probeEffectModule cg name)
  (cgSetModule cg (Some name)))
'''


def check(axiom, repo, work):
    source = repo / 'tests/selfhost/emitter-effect-registry.axp'
    fixture = work / source.with_suffix('.ax').name
    fixture.write_bytes(source.read_bytes())
    expected = [f'{i} true' for i in range(1, 16)]
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
                destination.write_text(source + BRIDGE)
            elif not destination.exists():
                destination.symlink_to(path, target_is_directory=path.is_dir())
        local = dict(env, AXIOM_PATH=str(modules))
        binary = work / label
        run_checked([str(axiom), '--diagnostic-format=ai', 'build', str(fixture),
                     '--opt', str(level), '--alloc-poison', '-o', str(binary)],
                    env=local, stdout=work / f'{label}.build.stdout', stderr=work / f'{label}.build.stderr')
        output = work / f'{label}.stdout'
        run_checked([str(binary)], env=local, stdout=output, stderr=work / f'{label}.stderr', timeout=30)
        return check_output(output, expected, required_failures=negative)

    for level in (0, 2):
        build_run(f'positive-O{level}', level, original)
        print(f'ok   typed effect registry: 15 cases at -O{level} with allocation poisoning', flush=True)
    variants = [
        ('entry-priority', replace_once(original, '(lookupEffIn tbl name 1 0)',
                                       '(lookupEffIn tbl name 0 0)', 'entry precedence'), (2, 11, 14)),
        ('module-priority', replace_once(original, '(Some local)\n    (lookupEff tbl name)',
                                        '(lookupEff tbl name)\n    (lookupEff tbl name)', 'module precedence'), (12,)),
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
        with tempfile.TemporaryDirectory(prefix='axiom-effect-registry-') as directory:
            check(args.axiom.resolve(), repo, Path(directory))


if __name__ == '__main__':
    main()
