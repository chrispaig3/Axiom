#!/usr/bin/env python3
"""Keep reverse-history matches and exhaustion distinct from entry zero."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(compiler, root, work):
    module = root / 'core/replhist.ax'
    source = module.read_text()
    fixture = root / 'tests/tools/repl-history-search-options.axp'
    terminal = root / 'tests/tools/repl-history-search-terminal.axp'
    extra = fixture.read_text()
    for line in ('(import IO)', '(import Fmt)', '(import Sys)'):
        extra = extra.replace(line, '')
    environment = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'), AXIOM_PATH=str(root / 'core'))
    expected = ''.join(f'{i} true\n' for i in range(1, 25))
    report = {'compiler': str(compiler), 'compiler_sha256': digest(compiler),
              'source_sha256': digest(module), 'repl_sha256': digest(root / 'core/repl.ax'),
              'fixture_sha256': digest(fixture), 'terminal_sha256': digest(terminal),
              'configurations': [], 'controls': [], 'refusals': [], 'terminals': [], 'regressions': [],
              'invariants': ['None is no match/exhaustion; Some zero is the oldest entry.',
                             'Some negative input is exhausted; oversize input clamps to the newest entry.',
                             'History order, case, multiline bytes, real empty entries and borrowing stay unchanged.',
                             'An unsuccessful Ctrl-R leaves the editor text unchanged; an oldest match exhausts the cursor.',
                             'EOF, Ctrl-C and a submitted empty line remain distinct.'],
              'remaining': ['Completion selection/detail queries, Ctrl-C event carrier'],
              'limits': ['Host O0/O2 allocation-poison probes; CI runs full target and REPL suites.',
                         'Borrow counts do not establish global destructor completeness.',
                         'No REPL evaluation/process-call or ownership/inference algorithm changes.']}

    def build(label, text, level=0, env=None):
        path = work / (label + '.ax'); path.write_text(text)
        executable = work / label
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'build', str(path),
                                 '--opt', str(level), '--alloc-poison', '-o', str(executable)],
                                cwd=root, env=env or environment, capture_output=True, text=True, timeout=300)
        (work / (label + '.build.stdout')).write_text(result.stdout)
        (work / (label + '.build.stderr')).write_text(result.stderr)
        assert result.returncode == 0, (label, result)
        return executable

    def execute(executable, expected_output=None, expected_status=0, env=None, data=None, args=()):
        result = subprocess.run([str(executable), *args], env=env or environment,
                                input=data, capture_output=True, timeout=30)
        assert result.returncode == expected_status and not result.stderr, result
        if expected_output is not None:
            assert result.stdout == expected_output, (executable, result.stdout, expected_output)
        return result

    for level in (0, 2):
        executable = build('queries-O' + str(level), '(import IO)\n' + source + '\n' + extra, level)
        execute(executable, expected.encode())
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True, 'outcomes': 24})
        print(f'ok   history query: 24 outcomes O{level}', flush=True)

    def alter(name, old, new):
        definition = re.search(r'\((?:pub )?fn \(' + re.escape(name) + r'\s', source)
        assert definition, name
        start = definition.start()
        following = re.search(r'^\((?:pub )?:: ', source[start:], re.M)
        end = start + following.start() if following else len(source)
        body = source[start:end]
        assert body.count(old) == 1, (name, old, body.count(old))
        return source[:start] + body.replace(old, new) + source[end:]

    controls = [
        ('invent-empty-top', alter('histSearchTop', '\n      None', '\n      (Some 0)'), {1}),
        ('discard-zero-match', alter('histFindBack', '(set found (Some i))',
                                     '(set found (if (== i 0) None (Some i)))'), {6, 13, 16}),
        ('invent-exhausted-match', alter('histFindBack', '((None) None)', '((None) (Some 0))'), {8, 15}),
        ('replace-match-index', alter('histFindBack', '(set found (Some i))', '(set found (Some 0))'),
         {4, 5, 10, 11, 18, 20, 24}),
        ('retain-search-history', alter('histFindBack', '(let n (histLen h))',
                                       '(__retainref h)\n        (let n (histLen h))'), {22}),
    ]
    for label, changed, failures in controls:
        executable = build(label, '(import IO)\n' + changed + '\n' + extra)
        result = execute(executable)
        failed = {int(line.split()[0]) for line in result.stdout.decode().splitlines() if line.endswith(' false')}
        assert failed == failures, (label, failed, failures, result.stdout)
        report['controls'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   control {label}: {sorted(failed)}', flush=True)

    invalid = [
        ('top-word', '(:: bad (-> Hist Int)) (fn (bad h) (histSearchTop h))', 'AX3004'),
        ('search-word', '(:: bad (-> Hist Int)) (fn (bad h) (histFindBack h "" None))', 'AX3004'),
        ('sentinel-cursor', '(:: bad (-> Hist (Option Int))) (fn (bad h) (histFindBack h "" (- 0 1)))', 'AX3004'),
        ('unchecked-match', '(:: bad (-> Hist Int)) (fn (bad h) (match (histSearchTop h) ((Some i) i)))', 'AX3005'),
        ('string-cursor', '(:: bad (-> Hist (Option Int))) (fn (bad h) (histFindBack h "" (Some "")))', 'AX3004'),
    ]
    for label, declaration, code in invalid:
        path = work / (label + '.ax')
        path.write_text(source + '\n' + declaration + '\n(:: main Int) (fn (main) 0)\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)],
                                cwd=root, env=environment, capture_output=True, text=True, timeout=120)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and f'E {code} ' in errors[0], (label, result)
        report['refusals'].append({'name': label, 'code': code})

    # The same actual key loop receives ordinary stdin bytes; this calls no
    # raw-mode bracket and changes no terminal belonging to the caller.
    sessions = [
        ('repeat-past-zero', b'hit\x12\x12\x12\r', (), b'hit old'),
        ('newest', b'hit\x12\r', (), b'hit new'),
        ('missing-preserves-buffer', b'missing\x12\r', (), b'missing'),
        ('case-sensitive', b'HIT\x12\r', (), b'HIT'),
        ('empty-ring', b'\x12\r', ('empty',), b''),
        ('empty-submission', b'\r', (), b''),
        ('empty-needle-to-oldest', b'\x12\x12\x12\x12\r', (), b'hit old'),
        ('ctrl-c', b'\x03', (), b'\x03'),
        ('ctrl-d', b'\x04', (), None),
        ('eof', b'', (), None),
    ]
    for level in (0, 2):
        executable = build('terminal-O' + str(level), terminal.read_text(), level)
        for name, data, args, answer in sessions:
            result = execute(executable, data=data, args=args)
            marker = b'\nRESULT None\n' if answer is None else b'\nRESULT Some:' + answer + b'\n'
            assert result.stdout.endswith(marker), (name, level, result.stdout, marker)
            (work / (name + '-O' + str(level) + '.stdout')).write_bytes(result.stdout)
            report['terminals'].append({'name': name, 'optimization': level,
                                        'answer': None if answer is None else answer.decode(),
                                        'bytes': len(result.stdout), 'sha256': hashlib.sha256(result.stdout).hexdigest()})
        print(f'ok   actual Ctrl-R/input loop: {len(sessions)} sessions O{level}', flush=True)

    executable = build('existing-history', (root / 'tests/selfhost/979-repl-history.ax').read_text())
    execute(executable, b'', 38)
    report['regressions'].append({'fixture': 'tests/selfhost/979-repl-history.ax', 'status': 38})
    executable = build('existing-read', (root / 'tests/repl/history/read.ax').read_text())
    history = work / 'existing.hist'
    history.write_bytes((root / 'tests/repl/history/basic.hist').read_bytes())
    isolated = dict(environment, HOME=str(work), XDG_CONFIG_HOME=str(work), AXIOM_REPL_HISTORY=str(history))
    execute(executable, b'', 14, isolated)
    report['regressions'].append({'fixture': 'tests/repl/history/read.ax', 'status': 14,
                                  'history_sha256': digest(history)})
    (work / 'repl-history-search-options-report.json').write_text(json.dumps(report, indent=2) + '\n')
    print('ok   5 effective controls; 5 refusals; existing 38/14 history outcomes', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True); parser.add_argument('--work', type=Path)
    args = parser.parse_args(); root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True); run(args.axiom.resolve(), root, args.work.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-repl-search-') as directory:
            run(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
