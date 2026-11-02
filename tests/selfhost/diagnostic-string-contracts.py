#!/usr/bin/env python3
"""Check required diagnostic Strings and typed absence at their producers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).with_name('emitter-line-buffer.py')))
run_checked = SUPPORT['run_checked']
replace_once = SUPPORT['replace_once']
check_output = SUPPORT['check_output']


def check(compiler, root, work):
    source = {name: (root / 'core' / name).read_text()
              for name in ('core.ax', 'diag.ax', 'render.ax', 'typecheck.ax')}
    fixture = (root / 'tests/selfhost/diagnostic-string-contracts.axp').read_text()
    expected = [f'{i} true' for i in range(1, 22)]
    empty = work / 'empty.ax'; empty.write_text('')
    missing = work / 'missing.ax'
    assert not missing.exists(), 'missing-file probe must remain absent'
    report = {'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'source_sha256': {n: hashlib.sha256(s.encode()).hexdigest() for n, s in source.items()},
              'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
              'configurations': [], 'controls': [], 'refusals': [],
              'limits': ['Unsafe casts and packet decoding remain trusted boundaries.',
                         'Read-error empty-text fallbacks retain existing diagnostic policy.',
                         'Entry-source availability and full-report entry-unit contracts are separate.']}

    def modules(label, texts):
        folder = work / (label + '-modules/core'); folder.mkdir(parents=True, exist_ok=True)
        for path in (root / 'core').iterdir():
            dest = folder / path.name
            if path.name in texts:
                dest.write_text(texts[path.name])
            elif not dest.exists():
                dest.symlink_to(path, target_is_directory=path.is_dir())
        return dict(os.environ, AXIOM_PATH=str(folder), AXIOM_STDLIB=str(root / 'stdlib'))

    def native(label, level, texts):
        local = modules(label, texts)
        path = work / (label + '.ax'); path.write_text(fixture)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(path), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work/(label + '-build.stdout'), stderr=work/(label + '-build.stderr'), timeout=240)
        output = work / (label + '.stdout')
        run_checked([str(binary), str(empty), str(missing)], env=local, stdout=output,
                    stderr=work/(label + '.stderr'), timeout=30)
        return output

    for level in (0, 2):
        check_output(native('positive-O' + str(level), level, source), expected)
        report['configurations'].append({'optimization': level, 'poison': True, 'cases': 21})
        print(f'ok   diagnostic Strings: 21 outcomes O{level}', flush=True)
    for label, module, before, after, failures in [
        ('discard-source', 'core.ax', '(pub fn (unitSrc u)\n  u.src)', '(pub fn (unitSrc u)\n  "")', {21}),
        ('discard-clean-text', 'render.ax', '(if (== run 0)\n        s', '(if (== run 0)\n        ""', {4}),
        ('skip-control-escape', 'render.ax', '(|| (< b 32) (== b 127))', '(|| false (== b 127))', {5, 14}),
    ]:
        changed = dict(source)
        if module == 'render.ax':
            start = source[module].index('(pub fn (ctlEsc s)')
            end = source[module].index('; `ctlEsc` is applied', start)
            body = replace_once(source[module][start:end], before, after, label)
            changed[module] = source[module][:start] + body + source[module][end:]
        else:
            changed[module] = replace_once(source[module], before, after, label)
        failed = check_output(native(label, 0, changed), expected, required_failures=failures)
        report['controls'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: {sorted(failed)}', flush=True)
    local = modules('refusals', source)
    for label, body, code in [
        ('integer-text', '(:: bad String) (fn (bad) (ctlEsc 0))', 'AX3004'),
        ('optional-required-text', '(:: bad String) (fn (bad) (ctlEsc None))', 'AX3004'),
        ('optional-unit-source', '(:: bad CUnit2) (fn (bad) (CUnit2 :file "x" :src None :name None :imports vecNew :library false))', 'AX3004'),
        ('forged-source', '(:: bad SrcIx) (fn (bad) (srcLineIndex (as 0 String)))', 'AX3073'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import core) (import diag) (import render)\n' + body + '\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)], env=local,
                                capture_output=True, text=True, timeout=90)
        (work/(label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode != 0 and len(errors) == 1 and errors[0].startswith('E ' + code + ' '), (label, result)
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    work = args.work or Path(tempfile.mkdtemp(prefix='axiom-diagnostic-strings-'))
    work.mkdir(parents=True, exist_ok=True)
    check(args.axiom.resolve(), root, work)


if __name__ == '__main__':
    main()
