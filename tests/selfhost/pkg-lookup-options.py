#!/usr/bin/env python3
"""Check typed manifest/key lookups and the existing CLI defaults and refusals."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import tempfile

HERE = Path(__file__).parent
CLI = runpy.run_path(str(HERE / 'cli-index-options.py'))
VALUES = CLI['VALUES']
declaration = VALUES['declaration']
replace_once = CLI['replace_once']
NAMES = ('pkg.ax', 'driver.ax', 'main.ax', 'codegen.ax', 'doc.ax', 'fmtcli.ax')
MANIFESTS = {
    'none': None,
    'valid': 'name demo\nversion 0.1.0\nopt 2\nmain Main.ax\n',
    'broken': 'name demo\nversion 0.1.0\nopt 2\nmain Main.ax\n',
    'empty': '',
    'empty-values': 'name\nopt\nmain\n',
    'zero': 'name zero\nopt 0\nmain src/App.ax\n',
    'duplicates': 'name\nname first\nname second\nopt 0\nopt 3\n',
    'bad-opt': 'name okay\nopt /\n',
    'bad-name': 'name ../escape\n',
    'bad-key': 'nmae typo\n',
    'bad-depend': 'depend absent\n',
    'dependencies': 'depend one\ndepend\ndepend two\ncrate third\n',
    'read-failure': 'DIRECTORY',
}


def harness(sources):
    program = CLI['index_harness'](sources)
    fetch = declaration(sources['main.ax'], 'fetchCmd')
    # The real fetch query, validation and rejection paths are retained; only
    # successful network work is a marker, so the test has no spawn/block effect.
    for effect in ('spawn', 'block'):
        fetch = fetch.replace(';@axiom:effect(' + effect + ')\n', '')
    extra = '\n' + fetch + '''
(:: fetchUrls (-> String Names String Int Int))
;@axiom:effect(io)
(fn (fetchUrls text urls base from) { (println "fetch-ready") 0 })
'''
    at = program.index('(:: main Int)')
    program = program[:at] + extra + '\n' + program[at:]
    program = program.replace('(import IO (fileExists writeStr stderr stdout))',
                              '(import IO (fileExists readFile writeStr stderr stdout))', 1)
    return program.replace('      (_ 97))', '''      ("fetch" fetchCmd)
      ("verify" (pkgVerify ""))
      (_ 97))''')


def extra_cases():
    cases = []
    for kind in MANIFESTS:
        for mode in ('opt', 'buildout', 'manifest', 'verify', 'fetch'):
            cases.append({'mode': mode, 'argv': ['fetch' if mode == 'fetch' else 'build'], 'fixture': kind})
    for args in (['build', '--opt='], ['build', '--opt=3'], ['build', '--opt=0']):
        cases.append({'mode': 'opt', 'argv': args, 'fixture': 'zero'})
    cases.append({'mode': 'fetch', 'argv': ['fetch', 'extra'], 'fixture': 'valid'})
    return cases


def entry_disappears(compiler, root, work, sources, baseline=None):
    """Exercise the second lookup going missing after a manifest was found."""
    results = {}
    for version, edits in [('current', sources)] + ([('baseline', {name: (baseline / name).read_text() for name in NAMES})] if baseline else []):
        pkg = edits['pkg.ax']; fn = declaration(pkg, 'pkgEntryFile')
        nodes = VALUES['parse'](fn); body = nodes[-1]
        missing = 'None' if '(Option String)' in fn else '""'
        changed = fn[:body[0]] + '(pub fn (pkgEntryFile dir) { (let observed (pkgFindManifest dir)) ' + missing + ' })'
        edits = dict(edits, **{'pkg.ax': replace_once(pkg, fn, changed, 'vanished-entry')})
        label = 'vanished-entry-' + version
        folder = work / (label + '-modules'); folder.mkdir(exist_ok=True)
        for path in (root / 'core').iterdir():
            dest = folder / path.name
            if path.name in edits: dest.write_text(edits[path.name])
            elif not dest.exists(): dest.symlink_to(path, target_is_directory=path.is_dir())
        env = dict(os.environ, AXIOM_PATH=str(folder), AXIOM_STDLIB=str(root / 'stdlib'))
        path = work / (label + '.ax'); path.write_text(harness(edits)); binary = work / label
        got = subprocess.run([str(compiler), '--diagnostic-format=ai', 'build', str(path), '--opt', '0',
                              '--alloc-poison', '-o', str(binary)], env=env, capture_output=True, timeout=240)
        (work / (label + '-build.stdout')).write_bytes(got.stdout)
        (work / (label + '-build.stderr')).write_bytes(got.stderr)
        assert got.returncode == 0, (label, got.stderr)
        env['AXIOM_OPTION_PROBE'] = 'manifest'
        got = subprocess.run([str(binary), 'build'], env=env, cwd=work / 'inputs/valid', capture_output=True, timeout=30)
        (work / (label + '.stdout')).write_bytes(got.stdout)
        (work / (label + '.stderr')).write_bytes(got.stderr)
        results[version] = {'status': got.returncode, 'stdout': got.stdout.decode(), 'stderr': got.stderr.decode()}
    expected = {'status': 1, 'stdout': '', 'stderr': "error: the project manifest `./axiom.pkg` names no entry file that exists (want ``)\n       Set `main` to move it, or write `Main.ax` beside the manifest.\n"}
    assert all(result == expected for result in results.values()), results
    print('ok   manifest disappearance: exact missing-entry diagnostic', flush=True)
    return results


def check(compiler, root, work, baseline=None):
    sources = {name: (root / 'core' / name).read_text() for name in NAMES}
    fixture = (root / 'tests/selfhost/pkg-lookup-options.axp').read_text()
    report = {'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'source_sha256': {k: hashlib.sha256(v.encode()).hexdigest() for k, v in sources.items()},
              'configurations': [], 'controls': [], 'refusals': [],
              'limits': ['Host O0/O2 with allocation poisoning; not target-wide qualification.',
                         'Successful dispatch and fetch use markers; no native tools or network operations run.',
                         'sysEnv remains its public String ABI: missing and present-empty environment values are indistinguishable.',
                         'A found but unreadable manifest exits 3 with its path and errno.',
                         'Repeated filesystem lookups have pre-existing allocation-counter growth, measured separately from balanced pure Option lookups.',
                         'pkgOpt retains the existing prevalidated-byte interpretation; pkgVerify refuses invalid manifest levels.']}
    data = work / 'inputs'; data.mkdir(exist_ok=True)
    for kind, manifest in MANIFESTS.items():
        folder = data / kind; folder.mkdir(exist_ok=True)
        if manifest == 'DIRECTORY':
            (folder / 'axiom.pkg').mkdir(exist_ok=True)
        elif manifest is not None:
            (folder / 'axiom.pkg').write_text(manifest)
        if kind in ('valid', 'empty', 'empty-values', 'duplicates'):
            (folder / 'Main.ax').write_text('(:: main Int) (fn (main) 0)\n')
        if kind == 'zero':
            (folder / 'src').mkdir(exist_ok=True)
            (folder / 'src/App.ax').write_text('(:: main Int) (fn (main) 0)\n')
    deep = data / 'deep'; deep.mkdir(exist_ok=True); (deep / 'axiom.pkg').write_text('name deep\n')
    leaf = deep
    for _ in range(9):
        leaf = leaf / 'a'; leaf.mkdir(exist_ok=True)
    nested = data / 'nearest'; (nested / 'child').mkdir(parents=True, exist_ok=True)
    (nested / 'axiom.pkg').write_text('name parent\n')
    (nested / 'child/axiom.pkg').write_text('name child\n')

    def modules(label, edits):
        folder = work / (label + '-modules'); folder.mkdir(exist_ok=True)
        for path in (root / 'core').iterdir():
            dest = folder / path.name
            if path.name in edits:
                dest.write_text(edits[path.name])
            elif not dest.exists():
                dest.symlink_to(path, target_is_directory=path.is_dir())
        return dict(os.environ, AXIOM_PATH=str(folder), AXIOM_STDLIB=str(root / 'stdlib'))

    def run(label, command, local, cwd=None, require=None):
        got = subprocess.run(command, env=local, cwd=cwd or data, capture_output=True, timeout=240)
        (work / (label + '.stdout')).write_bytes(got.stdout)
        (work / (label + '.stderr')).write_bytes(got.stderr)
        if require is not None:
            assert got.returncode == require, (label, got.returncode, got.stderr[-6000:])
        return got

    def native(label, level, edits, program):
        local = modules(label, edits); path = work / (label + '.ax'); path.write_text(program)
        binary = work / label
        run(label + '-build', [str(compiler), '--diagnostic-format=ai', 'build', str(path),
                              '--opt', str(level), '--alloc-poison', '-o', str(binary)], local, require=0)
        return binary, local

    # Paths remain exactly what the bounded query returns, without normalising
    # away its depth or nearest-manifest decision.
    queries = [
        ('none', '', None, None, None, None, []),
        ('valid', '', './axiom.pkg', 'demo', 2, './Main.ax', []),
        ('empty', '', './axiom.pkg', None, None, './Main.ax', []),
        ('empty-values', '', './axiom.pkg', '', None, './Main.ax', []),
        ('zero', '', './axiom.pkg', 'zero', 0, './src/App.ax', []),
        ('duplicates', '', './axiom.pkg', 'first', 0, './Main.ax', []),
        ('bad-opt', '', './axiom.pkg', 'okay', -1, './Main.ax', []),
        ('read-failure', '', './axiom.pkg', None, None, './Main.ax', []),
        ('dependencies', '', './axiom.pkg', None, None, './Main.ax', ['./one/', './two/', './third/axiom/']),
        ('nearest/child', '', './axiom.pkg', 'child', None, './Main.ax', []),
    ]
    for depth in (8, 9):
        path = 'deep/' + 'a/' * depth
        manifest = path + '../' * depth + 'axiom.pkg' if depth == 8 else None
        entry = path + '../' * depth + 'Main.ax' if depth == 8 else None
        queries.append(('', path, manifest, 'deep' if depth == 8 else None, None, entry, []))
    baseline_retained = {}
    def query_cases(label, binary, local):
        failed = []
        string = lambda x: 'None' if x is None else f'Some {len(x)}:{x}'
        integer = lambda x: 'None' if x is None else f'Some {x}'
        for i, (cwd, path, manifest, name, opt, entry, dirs) in enumerate(queries):
            if cwd == 'read-failure':
                result = run(label + '-' + str(i), [str(binary), path], local, data / cwd, require=3)
                expected_prefix = ''.join(f'{n} true\n' for n in range(1, 17)).encode()
                expected_error = (
                    b'error: could not read manifest `./axiom.pkg`: errno 21\n'
                )
                if result.stdout != expected_prefix or result.stderr != expected_error:
                    failed.append(i)
                    (work / (label + '-' + str(i) + '.expected')).write_bytes(expected_prefix)
                continue
            result = run(label + '-' + str(i), [str(binary), path], local, data / cwd, require=0)
            expected = [f'{n} true' for n in range(1, 17)] + [string(manifest), string(name), integer(opt),
                        string(entry), f'dirs={len(dirs)}'] + ['dir=' + d for d in dirs]
            lines = result.stdout.decode().splitlines()
            measurements = [line for line in lines if line.startswith('filesystem-retained=')]
            assert len(measurements) == 1, (label, i, lines)
            retained = int(measurements[0].split('=')[1])
            report.setdefault('filesystem_retained_bytes', {}).setdefault(label, []).append(retained)
            growth = i in baseline_retained and retained > baseline_retained[i]
            lines.remove(measurements[0])
            if result.stderr or lines != expected or growth:
                failed.append(i)
                (work / (label + '-' + str(i) + '.expected')).write_text('\n'.join(expected) + '\n')
        return failed

    cases = VALUES['scenarios']() + CLI['extra_cases']() + extra_cases()
    original_count = len(VALUES['scenarios']()) + len(CLI['extra_cases']())
    def policies(label, binary, local):
        results = []
        for i, case in enumerate(cases):
            env = dict(local, AXIOM_OPTION_PROBE=case['mode'], XDG_CACHE_HOME='cache')
            got = run(label + '-' + str(i), [str(binary), *case['argv']], env, data / case['fixture'])
            results.append(dict(case, status=got.returncode, stdout=got.stdout.decode(), stderr=got.stderr.decode()))
        return results

    golden = root / 'tests/selfhost/pkg-lookup-options.golden.json'
    if baseline:
        old = {name: (baseline / name).read_text() for name in NAMES}
        binary, local = native('baseline', 0, old, harness(old)); got = policies('baseline', binary, local)
        assert got[:original_count] == json.loads((HERE / 'cli-index-options.golden.json').read_text())
        if golden.exists():
            assert json.loads(golden.read_text()) == got[original_count:]
        else:
            golden.write_text(json.dumps(got[original_count:], indent=2) + '\n')
        # The legacy filesystem reader already retains allocation-counter bytes.
        # Compare the same direct-call probe before/after without investigating
        # or changing the independent runtime/ownership boundary.
        balance = '''(import pkg) (import IO) (import Sys) (import Str)
(:: discard (-> String Int)) (fn (discard value) (strLen value))
(:: live Int) (fn (live) (- (__axiom_mem_stat 0) (__axiom_mem_stat 1)))
(:: main ())
;@axiom:effect(io)
(fn (main) { (let dir (sysArg 1)) (discard (pkgName dir)) (let before live)
  (for i in 0..12 (discard (pkgName dir)))
  (let after live) (let delta (- after before)) (println \"delta={delta}\") })
'''
        binary, local = native('baseline-filesystem', 0, old, balance)
        for i, (cwd, path, *_) in enumerate(queries):
            got = run('baseline-filesystem-' + str(i), [str(binary), path], local, data / cwd, require=0)
            assert not got.stderr
            baseline_retained[i] = int(got.stdout.decode().strip().split('=')[1])
        report['baseline_filesystem_retained_bytes'] = baseline_retained
        report['baseline_source_sha256'] = {k: hashlib.sha256(v.encode()).hexdigest() for k, v in old.items()}
    assert golden.exists(), 'record original policy behaviour first'
    wanted = json.loads((HERE / 'cli-index-options.golden.json').read_text()) + json.loads(golden.read_text())
    assert len(wanted) == len(cases)
    for level in (0, 2):
        label = 'query-O' + str(level); binary, local = native(label, level, sources, fixture)
        failed = query_cases(label, binary, local); assert not failed, (label, failed)
        label = 'policy-O' + str(level); program = harness(sources); binary, local = native(label, level, sources, program)
        got = policies(label, binary, local); different = [i for i, (a, b) in enumerate(zip(got, wanted)) if a != b]
        assert not different, (label, different)
        report['configurations'].append({'optimization': level, 'poison': True, 'query_scenarios': len(queries),
                                         'pure_and_ownership_outcomes_per_scenario': 16, 'policy_scenarios': len(cases),
                                         'harness_sha256': hashlib.sha256(program.encode()).hexdigest()})
        print(f'ok   package lookups: {len(queries)} query/ownership and {len(cases)} exact policies O{level}', flush=True)

    source = sources['pkg.ax']
    for label, name, before, after, required in [
        ('discard-empty', 'pkgLineValue', '(Some (pkgTrim (strSlice t (strLen k) (- (strLen t) (strLen k)))))',
         '{ (let text (pkgTrim (strSlice t (strLen k) (- (strLen t) (strLen k))))) (if (== (strLen text) 0) None (Some text)) }', {3}),
        ('last-value-wins', 'pkgValue', '(set found (Some value))', '(set found (Some value))', set()),
        ('discard-zero', 'pkgOpt', '(Some (- (strByte value 0) 48))',
         '(if (== (strByte value 0) 48) None (Some (- (strByte value 0) 48)))', {4, 5}),
        ('short-search', 'pkgFindManifestFrom', '(> depth 8)', '(> depth 7)', {10}),
        ('retain-value', 'pkgValue', '    found\n  })',
         '    (match found ((None) None) ((Some text) { (__retainref text) (Some text) }))\n  })', {0}),
    ]:
        fn = declaration(source, name)
        if label == 'last-value-wins':
            parse, walk, op, value = (VALUES[k] for k in ('parse', 'walk', 'op', 'value'))
            matches = [n for n in walk(parse(fn)[-1]) if op(n) == 'match' and n[2][1][3] == 'found']
            assert len(matches) == 1
            before, after = value(fn, matches[0]), 'true'; required = {5}
        changed = replace_once(source, fn, replace_once(fn, before, after, label), label)
        edits = dict(sources, **{'pkg.ax': changed}); binary, local = native(label, 0, edits, fixture)
        failed = query_cases(label, binary, local); assert required <= set(failed), (label, failed)
        report['controls'].append({'name': label, 'failed_queries': failed})
        print(f'ok   counterexample {label}: query cases {failed}', flush=True)
    label = 'wrong-opt-default'; driver = sources['driver.ax']; fn = declaration(driver, 'optLevelArg')
    changed = fn.replace('((None) 1)', '((None) 2)'); assert changed != fn
    edits = dict(sources, **{'driver.ax': replace_once(driver, fn, changed, label)})
    binary, local = native(label, 0, edits, harness(edits)); got = policies(label, binary, local)
    different = [i for i, (a, b) in enumerate(zip(got, wanted)) if a != b]
    assert different and all(cases[i]['mode'] == 'opt' for i in different), different
    report['controls'].append({'name': label, 'changed_policies': different})
    print(f'ok   counterexample {label}: policy cases {different}', flush=True)
    local = modules('refusals', sources)
    for label, statement, code in [
        ('unchecked-value', '(:: bad Int) (fn (bad) (strLen (pkgValue "name x" "name")))', 'AX3004'),
        ('unchecked-path', '(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (strLen (pkgFindManifest "")))', 'AX3004'),
        ('unchecked-opt', '(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (+ (pkgOpt "") 1))', 'AX3004'),
        ('nonexhaustive-line', '(:: bad String) (fn (bad) (match (pkgLineValue "" "name") ((Some s) s)))', 'AX3005'),
        ('nonexhaustive-entry', '(:: bad String) ;@axiom:effect(io)\n(fn (bad) (match (pkgEntryFile "") ((Some s) s)))', 'AX3005'),
    ]:
        path = work / (label + '.ax'); path.write_text('(import pkg) (import Str)\n' + statement + '\n')
        got = run(label, [str(compiler), '--diagnostic-format=ai', 'check', str(path)], local)
        errors = [line for line in got.stderr.decode().splitlines() if line.startswith('E ')]
        assert got.returncode != 0 and len(errors) == 1 and errors[0].startswith('E ' + code + ' '), (label, got.stderr)
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    report['vanished_entry'] = entry_disappears(compiler, root, work, sources, baseline)
    report['golden_sha256'] = hashlib.sha256(golden.read_bytes()).hexdigest()
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    p = argparse.ArgumentParser(); p.add_argument('--axiom', required=True, type=Path)
    p.add_argument('--work', type=Path); p.add_argument('--baseline-core', type=Path)
    args = p.parse_args(); root = Path(__file__).resolve().parents[2]
    work = args.work or Path(tempfile.mkdtemp(prefix='axiom-pkg-options-')); work.mkdir(parents=True, exist_ok=True)
    check(args.axiom.resolve(), root, work.resolve(), args.baseline_core)


if __name__ == '__main__':
    main()
