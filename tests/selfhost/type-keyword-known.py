#!/usr/bin/env python3
"""Check exact builtin recognition without a nullable String result."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile


def check(compiler, root, work):
    # Controls must compile the same dependency snapshot as the positive run.
    snapshot = work / 'source'
    snapshot.mkdir()
    for directory in ('core', 'stdlib'):
        shutil.copytree(root / directory, snapshot / directory)
    fixture = work / 'probe.ax'
    fixture.write_bytes((root / 'tests/selfhost/type-keyword-known.axp').read_bytes())
    expected = (root / 'tests/selfhost/type-keyword-known.golden').read_text()
    assert expected.splitlines()[:38] == [f'{i} true' for i in range(1, 39)]
    parser_source = (snapshot / 'core/parser.ax').read_text()
    start = parser_source.index('(pub fn (typeKeywordKnown n)')
    end = parser_source.index('\n\n', start)
    body = parser_source[start:end]
    environment = dict(os.environ, AXIOM_PATH=str(snapshot / 'core'),
                       AXIOM_STDLIB=str(snapshot / 'stdlib'))
    report = {
        'builder': str(compiler),
        'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'sources': {name: hashlib.sha256((snapshot / 'core' / name).read_bytes()).hexdigest()
                    for name in ('parser.ax', 'typecheck.ax', 'lsp.ax')},
        'configurations': [], 'controls': [], 'refusals': [],
        'invariants': [
            'All 15 builtin spellings preserve value equality and dynamic input shares.',
            'Unsupported widths, case variants, containers and an empty name are not keywords.',
            'Parser grouping/application, checker queries and LSP builtin recognition agree.',
            'The predicate allocates no Option or String and performs no unsafe operation.',
            'Diagnostic and LSP bytes match the pre-migration source baseline.',
        ],
        'limits': [
            'Host O0/O2 allocation-poison tests do not establish global memory soundness.',
            'Linear remains the LSP-specific fallback already present before this change.',
            'The old integer-name path retained shares; the positive probe requires retirement.',
        ],
    }

    def invoke(label, arguments, env=environment, timeout=240):
        result = subprocess.run(arguments, env=env, capture_output=True, text=True,
                                timeout=timeout)
        (work / (label + '.stdout')).write_text(result.stdout)
        (work / (label + '.stderr')).write_text(result.stderr)
        return result

    def native(label, level, env, failures=None):
        binary = work / label
        built = invoke(label + '.build', [str(compiler), '--diagnostic-format=ai',
                       'build', str(fixture), '--opt', str(level), '--alloc-poison',
                       '-o', str(binary)], env)
        assert built.returncode == 0 and not built.stderr, (label, built.returncode, built.stderr)
        ran = invoke(label, [str(binary)], env, timeout=30)
        assert ran.returncode == 0 and not ran.stderr, (label, ran.returncode, ran.stderr)
        if failures is None:
            assert ran.stdout == expected, (label, ran.stdout)
        else:
            rows = ran.stdout.splitlines()[:38]
            assert len(rows) == 38
            observed = set()
            for index, row in enumerate(rows, 1):
                assert row in (f'{index} true', f'{index} false'), (label, row)
                if row.endswith(' false'):
                    observed.add(index)
            assert observed == failures, (label, observed, failures)
            report['controls'].append({'name': label, 'failed_cases': sorted(observed)})
        return ran.stdout

    for level in (0, 2):
        output = native('positive-O' + str(level), level, environment)
        report['configurations'].append({'opt': level, 'allocation_poison': True,
                                         'cases': 38, 'bytes': len(output.encode()),
                                         'sha256': hashlib.sha256(output.encode()).hexdigest()})
        print(f'ok   keyword predicate: 38 cases and exact diagnostic/LSP bytes O{level} poison', flush=True)

    def mutation(label, before, after, failures):
        assert body.count(before) == 1, (label, body.count(before))
        folder = work / (label + '-core/core')
        folder.mkdir(parents=True)
        for path in (snapshot / 'core').iterdir():
            if path.name == 'parser.ax':
                (folder / path.name).write_text(parser_source[:start] + body.replace(before, after)
                                               + parser_source[end:])
            else:
                (folder / path.name).symlink_to(path, target_is_directory=path.is_dir())
        native(label, 0, dict(environment, AXIOM_PATH=str(folder)), failures)
        print(f'ok   {label}: cases {sorted(failures)} fail', flush=True)

    mutation('lost-integer-keywords', '(> (integerTypeCode n) 0)', 'false', set(range(1, 9)) | {31})
    mutation('unknown-keywords-accepted', 'false)))))))))', 'true)))))))))',
             set(range(16, 31)) | {32, 33, 36, 38})

    for label, declaration in (
        ('predicate-used-as-string', '(:: bad Int) (fn (bad) (strLen (typeKeywordKnown "Int")))'),
        ('non-string-input', '(:: bad Bool) (fn (bad) (typeKeywordKnown 0))'),
    ):
        program = work / (label + '.ax')
        program.write_text('(import parser)\n(import Str)\n' + declaration
                           + '\n(:: main Int) (fn (main) 0)\n')
        result = invoke(label, [str(compiler), '--diagnostic-format=ai', 'check', str(program)])
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and errors[0].startswith('E AX3004 '), (
            label, result.returncode, result.stderr)
        report['refusals'].append({'name': label, 'code': 'AX3004'})
        print(f'ok   {label}: AX3004', flush=True)

    result = invoke('metadata', [str(compiler), '--diagnostic-format=ai', 'symbols', '--calls', str(fixture)])
    assert result.returncode == 0 and not result.stderr, result.stderr
    rows = [line for line in result.stdout.splitlines() if line.startswith('F typeKeywordKnown ')]
    assert len(rows) == 1 and '"(String -> Bool)"' in rows[0], rows
    assert '#restrict=no-io,no-alloc,no-foreign' in rows[0], rows
    assert not re.search(r'#effects(?:=|-incomplete)', rows[0]), rows
    assert '#effect=unsafe' not in rows[0], rows
    report['predicate_row'] = rows[0]
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('ok   typed Boolean predicate is pure and satisfies no-allocation restrictions', flush=True)


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
        with tempfile.TemporaryDirectory(prefix='axiom-type-keyword-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
