#!/usr/bin/env python3
"""Exercise owning signature registries, optional lookups and indexed aliases."""
import argparse
import os
from pathlib import Path
import re
import runpy
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).with_name('emitter-line-buffer.py')))
run_checked = SUPPORT['run_checked']
replace_once = SUPPORT['replace_once']
check_output = SUPPORT['check_output']
emitted_function = SUPPORT['emitted_function']

BRIDGE = r'''
(pub :: probeInstallSignatures (-> CG (Vec FSig) Bool CG))
(pub fn (probeInstallSignatures cg signatures indexed)
  {
    (cgSetFloatSigs cg signatures)
    (if indexed
      (buildNameIndexes cg))
    cg
  })
'''


def check(axiom, repo, work):
    source = repo / 'tests/selfhost/emitter-signature-options.axp'
    fixture = work / source.with_suffix('.ax').name
    fixture.write_bytes(source.read_bytes())
    expected = [f'{i} true' for i in range(1, 19)]
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
                     '--opt', str(level), '--alloc-poison', '--emit-llvm', '-o', str(binary)],
                    env=local, stdout=work / f'{label}.build.stdout', stderr=work / f'{label}.build.stderr')
        output = work / f'{label}.stdout'
        run_checked([str(binary)], env=local, stdout=output, stderr=work / f'{label}.stderr', timeout=30)
        failures = check_output(output, expected, required_failures=negative)
        if not negative:
            module = binary.with_suffix('.ll').read_text()
            for name in ['scanFloatSigs', 'scanExternSigs']:
                body = emitted_function(module, 'codegen$' + name)
                stores = re.findall(r'@Vec\$vecPush\(i64 [^,]+, i64 [^,]+, i64 ([01])\)', body)
                if stores != ['1']:
                    raise RuntimeError(f'{name}: registry must own its FSig payload: {stores}')
        return failures

    for level in (0, 2):
        build_run(f'positive-O{level}', level, original)
        print(f'ok   signature Options: 18 cases at -O{level} with allocation poisoning', flush=True)
    variants = [
        ('spelling', replace_once(original,
                                  '(&& (== (fsigNameLen e) nl) (strEq (fsigName e) name))',
                                  '(== (fsigNameLen e) nl)', 'signature full spelling'), (1, 3, 7)),
        ('indexed-id', replace_once(original, '(Some (vecGet (cgSigById cg) id))',
                                    '(Some (vecGet (cgSigById cg) 0))', 'signature index value'), (9, 11)),
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
        with tempfile.TemporaryDirectory(prefix='axiom-signature-options-') as directory:
            check(args.axiom.resolve(), repo, Path(directory))


if __name__ == '__main__':
    main()
