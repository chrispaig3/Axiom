#!/usr/bin/env python3
"""Hold optional REPL history paths, environment ownership and IO fallback."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def verify(compiler, root, work):
    module = root / 'core/replhist.ax'
    fixture = root / 'tests/tools/repl-history-path-options.axp'
    source = module.read_text()
    fixture_text = fixture.read_text()
    base_env = dict(os.environ, AXIOM_PATH=str(root / 'core'),
                    AXIOM_STDLIB=str(root / 'stdlib'))
    report = {'compiler_sha256': digest(compiler), 'source_sha256': digest(module),
              'fixture_sha256': digest(fixture), 'configurations': [],
              'controls': [], 'refusals': []}

    def build(label, text, level=0):
        path = work / (label + '.ax')
        path.write_text(text)
        executable = work / label
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'build',
                                 str(path), '--opt', str(level), '--alloc-poison',
                                 '-o', str(executable)], cwd=root, env=base_env,
                                capture_output=True, text=True, timeout=300)
        (work / (label + '.build.stderr')).write_text(result.stderr)
        assert result.returncode == 0, (label, result.stderr)
        return executable

    def cases(executable, label):
        failures = []
        observations = {}
        for name in ('noninteractive', 'off', 'absolute', 'xdg', 'home',
                     'missing', 'io-failure'):
            folder = work / ('cases-' + label) / name
            folder.mkdir(parents=True)
            xdg = folder / 'xdg'; xdg.mkdir()
            home = folder / 'home'; home.mkdir()
            blocked = folder / 'blocked'
            if name == 'io-failure':
                blocked.write_text('not a directory\n')
            interactive = '0' if name == 'noninteractive' else '1'
            configured = str(folder / 'absolute history')
            xdg_value = str(xdg)
            home_value = str(home)
            expected = None
            writable = False
            if name == 'off':
                configured = 'off'
            elif name == 'absolute':
                expected = Path(configured); writable = True
            elif name == 'xdg':
                configured = 'relative-history'
                expected = xdg / 'axiom' / 'repl-history'; writable = True
            elif name == 'home':
                configured = 'relative-history'
                xdg_value = 'relative-config'
                expected = home / '.config' / 'axiom' / 'repl-history'
                writable = True
            elif name == 'missing':
                configured = 'relative-history'
                xdg_value = 'relative-config'
                home_value = 'relative-home'
            elif name == 'io-failure':
                configured = str(blocked / 'axiom' / 'repl-history')
                expected = Path(configured)
            env = dict(base_env, HIST_INTERACTIVE=interactive,
                       AXIOM_REPL_HISTORY=configured, XDG_CONFIG_HOME=xdg_value,
                       HOME=home_value)
            result = subprocess.run([str(executable)], cwd=folder, env=env,
                                    capture_output=True, text=True, timeout=30)
            path_text = 'None' if expected is None else 'Some:' + str(expected)
            wanted = ('resolve ' + path_text + '\n' +
                      'session ' + path_text + '\n' +
                      'persist ' + ('0' if expected is None else '1') + '\n' +
                      'length 1\n')
            disk = expected.read_bytes() if expected and expected.is_file() else None
            no_unexpected_file = not any(path.is_file() for path in (
                folder / 'absolute history', xdg / 'axiom' / 'repl-history',
                home / '.config' / 'axiom' / 'repl-history'))
            good = (result.returncode == 0 and not result.stderr and
                    result.stdout == wanted and
                    ((disk == b'(+ 1 2)\n') if writable else disk is None) and
                    (expected is not None or no_unexpected_file))
            if not good:
                failures.append(name)
            observations[name] = {'passed': good, 'exit': result.returncode,
                                  'stdout': result.stdout, 'stderr': result.stderr,
                                  'disk': disk.decode(errors='replace') if disk else None}
        return failures, observations

    for level in (0, 2):
        label = 'paths-O' + str(level)
        binary = build(label, fixture_text, level)
        failures, outcomes = cases(binary, label)
        assert not failures, (label, failures, outcomes)
        report['configurations'].append({'optimization': level,
                                         'allocation_poisoning': True,
                                         'cases': outcomes})
        print(f'ok   history paths: seven scenarios O{level} poison', flush=True)

    selective_io = '(import IO (appendFile fileSize makeDir readFile renamePath writeFile))'
    assert source.count(selective_io) == 1
    parent_main = '''
(:: printParent (-> String ()))
;@axiom:effect(io)
(fn (printParent path)
  (match (histDirOf path)
    ((None) (println "None"))
    ((Some parent) (println (concat "Some:" parent)))))
(:: main ())
;@axiom:effect(io)
(fn (main)
  { (printParent "/") (printParent "/a") (printParent "/a/b") })
'''
    def parent_output(label, text):
        binary = build(label, text.replace(selective_io, '(import IO)') + parent_main)
        result = subprocess.run([str(binary)], cwd=work, env=base_env,
                                capture_output=True, text=True, timeout=30)
        assert result.returncode == 0 and not result.stderr, (label, result)
        return result.stdout

    expected_parents = 'None\nNone\nSome:/a\n'
    assert parent_output('parent-boundary', source) == expected_parents
    report['configurations'].append({'parent_boundary': expected_parents})
    print('ok   parent directories: root absent, nested present', flush=True)
    parent_guard = '(if (<= n 1)'
    assert source.count(parent_guard) == 1
    wrong_parents = parent_output('parent-guard-erased',
                                  source.replace(parent_guard, '(if (< n 0)'))
    assert wrong_parents != expected_parents, wrong_parents
    report['controls'].append({'name': 'parent-guard-erased',
                               'observed': wrong_parents})
    print('ok   control parent-guard-erased: root parent invented', flush=True)

    body = ''.join(line for line in fixture_text.splitlines(keepends=True)
                   if not line.startswith('(import '))

    def change(old, new, label):
        assert source.count(old) == 1, (label, source.count(old))
        changed = source.replace(old, new).replace(selective_io, '(import IO)')
        return changed + '\n' + body

    for label, before, after, required in (
            ('interactive-erased', '(if (== interactive 0)',
             '(if (== interactive 1)', 'noninteractive'),
            ('off-erased', '(if (strEq v "off")',
             '(if false', 'off'),
            ('persist-always-on', '(if (isSome h.path)',
             '(if true', 'noninteractive')):
        binary = build(label, change(before, after, label))
        failures, outcomes = cases(binary, label)
        assert required in failures, (label, required, failures, outcomes)
        report['controls'].append({'name': label, 'failed_cases': failures})
        print(f'ok   control {label}: {required} fails', flush=True)

    for label, declaration, code in (
            ('raw-session-path', '(:: bad (-> Hist String)) (fn (bad h) (histPath h))', 'AX3004'),
            ('raw-resolved-path', '(:: bad String)\n;@axiom:effect(io)\n(fn (bad) (histResolvePath 0))', 'AX3004'),
            ('missing-none', '(:: bad (-> Hist String)) (fn (bad h) (match (histPath h) ((Some p) p)))', 'AX3005'),
            ('missing-some', '(:: bad (-> Hist String)) (fn (bad h) (match (histPath h) ((None) "")))', 'AX3005'),
            ('old-raw-field', '(:: bad Hist) (fn (bad) (Hist :entries vecNew :path "" :cap 1 :pos 0 :draft ""))', 'AX3004')):
        path = work / (label + '.ax')
        path.write_text('(import replhist)\n' + declaration +
                        '\n(:: main Int) (fn (main) 0)\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check',
                                 str(path)], cwd=root, env=base_env,
                                capture_output=True, text=True, timeout=120)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode == 1 and len(errors) == 1 and f'E {code} ' in errors[0], (
            label, result.returncode, result.stderr)
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   refusal {label}: {code}', flush=True)

    assert digest(module) == report['source_sha256']
    assert digest(fixture) == report['fixture_sha256']
    assert digest(compiler) == report['compiler_sha256']
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        verify(args.axiom.resolve(), root, args.work.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-repl-path-') as folder:
            verify(args.axiom.resolve(), root, Path(folder))


if __name__ == '__main__':
    main()
