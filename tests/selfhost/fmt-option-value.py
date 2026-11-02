#!/usr/bin/env python3
"""Check formatter option absence, supplied empty values and CLI behavior."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).with_name('emitter-line-buffer.py')))
replace_once = SUPPORT['replace_once']
CLI = runpy.run_path(str(Path(__file__).with_name('cli-flag-parts-options.py')))
ADAPTER = '''
(pub :: probeFmtOptionValue (-> String Int (Option String)))
;@axiom:effect(io)
(pub fn (probeFmtOptionValue name from) (fmtOptionValue name from))
'''
QUERIES = [
    (['fmt'], 'None'),
    (['fmt', '--emit='], 'Some 0:'),
    (['fmt', '--emit', ''], 'Some 0:'),
    (['fmt', '--emit', 'stdout'], 'Some 6:stdout'),
    (['fmt', '--emit=files', '--emit=stdout'], 'Some 5:files'),
    (['fmt', '--', '--emit=stdout'], 'None'),
    (['fmt', '--input', '--emit=stdout'], 'None'),
    (['fmt', '--emit'], 'None'),
    (['fmt', '--emit=a=b'], 'Some 3:a=b'),
    (['fmt', '--check', '--emit=stdout'], 'Some 6:stdout'),
]


def check(compiler, root, work):
    source = (root/'core/fmtcli.ax').read_text()
    fixture = (root/'tests/selfhost/fmt-option-value.axp').read_text()
    behavior = (root/'tests/selfhost/cli-flag-parts-behavior.axp').read_text()
    golden = root/'tests/selfhost/cli-flag-parts-behavior.golden.json'
    wanted = json.loads(golden.read_text())
    report = {'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
              'configurations': [], 'controls': [], 'refusals': [],
              'limits': ['Host O0/O2 with allocation poisoning; not target-wide qualification.',
                         'The query adapter is appended only to a private test copy.',
                         'This probe covers its named query contract; general values and command indexes have separate fixtures.']}
    data = work/'inputs'; data.mkdir(exist_ok=True)

    def modules(label, text):
        folder = work/(label+'-modules/core'); folder.mkdir(parents=True, exist_ok=True)
        for path in (root/'core').iterdir():
            dest = folder/path.name
            if path.name == 'fmtcli.ax':
                dest.write_text(text+ADAPTER)
            elif not dest.exists():
                dest.symlink_to(path, target_is_directory=path.is_dir())
        return dict(os.environ, AXIOM_PATH=str(folder), AXIOM_STDLIB=str(root/'stdlib'))

    def run(label, command, env, require=None):
        result = subprocess.run(command, env=env, cwd=data, capture_output=True, timeout=240)
        (work/(label+'.stdout')).write_bytes(result.stdout)
        (work/(label+'.stderr')).write_bytes(result.stderr)
        if require is not None:
            assert result.returncode == require, (label, result.returncode, result.stderr[-6000:])
        return result

    def native(label, level, text, program):
        local = modules(label, text)
        path = work/(label+'.ax'); path.write_text(program)
        binary = work/label
        run(label+'-build', [str(compiler), '--diagnostic-format=ai', 'build', str(path), '--opt', str(level),
                            '--alloc-poison', '-o', str(binary)], local, 0)
        return binary, local

    def queries(label, binary, local):
        changed = []
        for i, (argv, expected) in enumerate(QUERIES):
            result = run(label+'-'+str(i), [str(binary), *argv], local, 0)
            assert not result.stderr, (label, i)
            if result.stdout.decode().splitlines() != [expected, 'None', 'None', 'balanced=true']:
                changed.append(i)
        return changed

    def outcomes(label, binary, local):
        results = []
        for i, args in enumerate(CLI['SCENARIOS']):
            for file in ('probe.ax', '-dash.ax'):
                (data/file).write_text('(:: main Int)\n(fn (main) 3)\n')
            actual = run(label+'-'+str(i), [str(binary), *args], local)
            results.append({'argv': args, 'status': actual.returncode, 'stdout': actual.stdout.decode(),
                            'stderr': actual.stderr.decode(),
                            'files': {file: (data/file).read_text() for file in ('probe.ax', '-dash.ax')}})
        return results

    for level in (0, 2):
        label = 'positive-O'+str(level)
        binary, local = native(label, level, source, fixture)
        assert not queries(label, binary, local), label
        binary, local = native('behavior-O'+str(level), level, source, behavior)
        assert outcomes('behavior-O'+str(level), binary, local) == wanted, ('CLI behavior changed', level)
        report['configurations'].append({'optimization': level, 'poison': True, 'query_scenarios': 10,
                                         'cli_scenarios': len(wanted)})
        print(f'ok   formatter lookup: 10 query/ownership and {len(wanted)} exact CLI scenarios O{level}', flush=True)
    start = source.index('(fn (fmtOptionValue ')
    end = source.index('(:: fmtPaths', start)
    body = source[start:end]
    for label, before, after, failures in [
        ('discard-empty', '((Some value) (Some value))',
         '((Some value) (if (== (strLen value) 0) None (Some value)))', {1}),
        ('ignore-separator', '(if (strEq arg "--")', '(if false', {5}),
        ('inspect-other-value', '(if (&& (== arity 1) (! (flagHasValuePart arg)))', '(if false', {6}),
        ('retain-inline-value', '((Some value) (Some value))',
         '((Some value) { (__retainref value) (Some value) })', {4, 8, 9}),
    ]:
        changed = source[:start]+replace_once(body, before, after, label)+source[end:]
        binary, local = native(label, 0, changed, fixture)
        failed = queries(label, binary, local)
        assert failures <= set(failed), (label, failed)
        report['controls'].append({'name': label, 'failed_query_scenarios': failed})
        print(f'ok   counterexample {label}: {failed}', flush=True)
    label = 'discard-stdout-mode'
    changed = replace_once(source,
        '(let emitStdout\n      (match emit\n        ((None) false)\n        ((Some value) (strEq value "stdout"))))',
        '(let emitStdout false)', label)
    binary, local = native(label, 0, changed, behavior)
    actual = outcomes(label, binary, local)
    different = [i for i, (got, expected) in enumerate(zip(actual, wanted)) if got != expected]
    assert {23, 24} <= set(different), different
    report['controls'].append({'name': label, 'changed_cli_scenarios': different})
    print(f'ok   counterexample {label}: CLI scenarios {different}', flush=True)
    local = modules('refusals', source)
    for label, declaration, code in [
        ('unchecked-option', '(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (strLen (probeFmtOptionValue "--emit" 1)))', 'AX3004'),
        ('nonexhaustive-option', '(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (match (probeFmtOptionValue "--emit" 1) ((Some text) (strLen text))))', 'AX3005'),
        ('raw-option', '(:: bad String) ;@axiom:effect(io)\n(fn (bad) (probeFmtOptionValue "--emit" 1))', 'AX3004'),
    ]:
        path = work/(label+'.ax'); path.write_text('(import fmtcli) (import Str)\n'+declaration+'\n')
        result = run(label, [str(compiler), '--diagnostic-format=ai', 'check', str(path)], local)
        errors = [line for line in result.stderr.decode().splitlines() if line.startswith('E ')]
        assert result.returncode != 0 and len(errors) == 1 and errors[0].startswith('E '+code+' '), (label, result)
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    report['behavior_sha256'] = hashlib.sha256(golden.read_bytes()).hexdigest()
    (work/'report.json').write_text(json.dumps(report, indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    work = args.work or Path(tempfile.mkdtemp(prefix='axiom-fmt-values-'))
    work.mkdir(parents=True, exist_ok=True)
    check(args.axiom.resolve(), root, work.resolve())


if __name__ == '__main__':
    main()
