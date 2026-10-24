#!/usr/bin/env python3
"""Check optional documentation facts, empty paths and exact renderer output."""
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
check_output = SUPPORT['check_output']


def check(compiler, root, work, baseline=None):
    source = (root / 'core/doc.ax').read_text()
    fixture = (root / 'tests/selfhost/doc-lookup-options.axp').read_text()
    rendering = (root / 'tests/selfhost/doc-lookup-render.axp').read_text()
    expected = [f'{i} true' for i in range(1, 28)]
    report = {'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
              'configurations': [], 'controls': [], 'refusals': [],
              'limits': ['Host O0/O2 allocation poisoning; not target-wide qualification.',
                         'Read failures retain the existing empty-source fallback.',
                         'pathOfCommand and command-line flag/environment sentinels remain separate APIs.']}
    data = work / 'inputs'; data.mkdir(exist_ok=True)
    (data/'docs').mkdir(exist_ok=True)
    (data/'library').mkdir(exist_ok=True)
    (data/'empty-library').mkdir(exist_ok=True)
    # doc-drift: synthetic-doc-links-begin
    # These links address the temporary fixture tree, including an absent page.
    readme = Path('README.md')
    start = Path('docs') / readme
    absent = Path('missing.md')
    parent = Path('..') / readme
    (data/readme).write_text(f'# About\n\n[Start]({start.as_posix()}) and [absent]({absent.as_posix()}#part).\n')
    (data/start).write_text(f'# Start\n\n[About]({parent.as_posix()}#part).\n')
    (data/'Fixture.ax').write_text(f''';;! A tiny module with [About]({readme.as_posix()}).
;; A documented value.
(pub :: value Int)
(pub fn (value) 1)
(pub macro (twice x) x)
(pub data Choice (One) (Two))
(pub struct Record (x : Int))
(pub type Alias Int)
(effect Ask (ask :: (-> Int Int)))
(:: private Int)
(fn (private) 2)
''')
    # doc-drift: synthetic-doc-links-end
    (data/'library/Tiny.ax').write_text(';; A value.\n(pub :: tiny Int)\n(pub fn (tiny) 1)\n')
    (data/'Broken.ax').write_text('(pub :: broken (-> Int\n')

    def modules(label, text):
        folder = work / (label + '-modules'); folder.mkdir(exist_ok=True)
        for path in (root / 'core').iterdir():
            dest = folder / path.name
            if path.name == 'doc.ax':
                dest.write_text(text)
            elif not dest.exists():
                dest.symlink_to(path, target_is_directory=path.is_dir())
        return dict(os.environ, AXIOM_PATH=str(folder), AXIOM_STDLIB=str(root / 'stdlib'))

    def run(label, command, env, expected_code=0):
        result = subprocess.run(command, env=env, cwd=data, capture_output=True, timeout=240)
        (work/(label + '.stdout')).write_bytes(result.stdout)
        (work/(label + '.stderr')).write_bytes(result.stderr)
        assert result.returncode == expected_code, (label, result.returncode, result.stderr[-6000:])
        return result

    def native(label, level, text, program):
        local = modules(label, text)
        path = work / (label + '.ax'); path.write_text(program)
        binary = work / label
        run(label+'-build', [str(compiler), '--diagnostic-format=ai', 'build', str(path),
                            '--opt', str(level), '--alloc-poison', '-o', str(binary)], local)
        return binary, local

    def options(label, binary, local, root_path, library, failures=()):
        env = dict(local, AXIOM_DOC=root_path, AXIOM_STDLIB=library)
        wanted_root = 'ABSENT' if root_path == 'missing-root' else root_path.rstrip('/')+'/'
        wanted_lib = 'ABSENT' if library == 'missing-library' else library.rstrip('/')+'/'
        result = run(label, [str(binary), wanted_root, wanted_lib], env)
        assert not result.stderr, label
        return check_output(work/(label+'.stdout'), expected, required_failures=failures)

    def fallback_options(label, binary, local, depth, failures=()):
        folder = data / 'tool-bin'
        if depth == 2:
            folder = folder / 'deep'
        folder.mkdir(parents=True, exist_ok=True)
        (data/'stdlib').mkdir(exist_ok=True)
        executable = folder / label
        if not executable.exists():
            executable.symlink_to(binary)
        selected = str(folder) + '/' + '../' * depth
        result = run(label, [str(executable), selected, selected+'stdlib/'],
                     dict(local, AXIOM_DOC='', AXIOM_STDLIB=''))
        assert not result.stderr, label
        return check_output(work/(label+'.stdout'), expected, required_failures=failures)

    def snapshot(label, binary, local):
        out = work / (label + '-html'); out.mkdir(exist_ok=True)
        result = run(label, [str(binary), str(out)+'/'], local)
        return {'stdout': result.stdout.decode(), 'stderr': result.stderr.decode(),
                'files': {str(path.relative_to(out)): path.read_text()
                          for path in sorted(out.rglob('*.html'))}}

    def cli(label, binary, local, missing_root=False, missing_lib=False):
        out = work / (label + '-html')
        env = dict(local, AXIOM_DOC='missing-root' if missing_root else '.',
                   AXIOM_STDLIB='missing-library' if missing_lib else 'library')
        result = run(label, [str(binary), 'doc', '--out', str(out), '--no-open'], env,
                     expected_code=1 if missing_root else 0)
        # The CLI reports its selected output path; preserve all remaining bytes.
        stdout = result.stdout.decode().replace(str(out), '<OUTPUT>')
        return {'stdout': stdout, 'stderr': result.stderr.decode(),
                'files': {str(path.relative_to(out)): path.read_text().replace(str(data), '<INPUT>')
                          for path in sorted(out.rglob('*')) if path.is_file()}}

    def renders(label, binary, local):
        return {'snapshot': snapshot(label+'-snapshot', binary, local),
                'cli': cli(label+'-cli', binary, local),
                'missing_root': cli(label+'-root', binary, local, missing_root=True),
                'missing_library': cli(label+'-library', binary, local, missing_lib=True)}

    golden = root / 'tests/selfhost/doc-lookup-render.golden.json'
    if baseline:
        old = baseline.read_text()
        binary, local = native('baseline-render', 0, old, rendering)
        original = renders('baseline', binary, local)
        if golden.exists():
            assert original == json.loads(golden.read_text()), 'baseline golden differs'
        else:
            golden.write_text(json.dumps(original, ensure_ascii=True, indent=2)+'\n')
        report['baseline_source_sha256'] = hashlib.sha256(old.encode()).hexdigest()
    assert golden.exists(), 'record original renderer output first'
    expected_render = json.loads(golden.read_text())
    for level in (0, 2):
        label = 'positive-O'+str(level)
        binary, local = native(label, level, source, fixture)
        options(label+'-present', binary, local, '.', 'library')
        options(label+'-absent', binary, local, 'missing-root', 'missing-library')
        options(label+'-empty-library', binary, local, '.', 'empty-library')
        fallback_options(label+'-fallback-first', binary, local, 1)
        fallback_options(label+'-fallback-second', binary, local, 2)
        report['configurations'].append({'optimization': level, 'poison': True, 'cases': 27,
                                         'path_scenarios': 5})
        binary, local = native('render-O'+str(level), level, source, rendering)
        rendered = renders('render-O'+str(level), binary, local)
        assert rendered == expected_render, ('rendered bytes differ', level)
        print(f'ok   doc lookups: 27 outcomes, five path scenarios and exact rendering O{level}', flush=True)
    for label, before, after, failures in [
        ('discard-index-zero', '(set at (Some i))', '(if (> i 0) (set at (Some i)))', {1, 5, 6, 19, 22}),
        ('expose-private-declarations', '(if (!= (nodeVis d) 1)', '(if false', {13}),
        ('discard-unmarked-effect', '(Some "effect")', 'None', {12}),
        ('discard-valid-root', '(Some (pathWithSlash env))', 'None', {25, 27}),
        ('discard-valid-library', '(set found (Some (vecGetStr dirs i)))', '(set found None)', {26}),
        ('retain-index-input', '(let n (vecLen v))', '(let n { (__retainref v) (vecLen v) })', {23}),
    ]:
        changed = replace_once(source, before, after, label)
        binary, local = native(label, 0, changed, fixture)
        failed = options(label, binary, local, '.', 'library', failures)
        report['controls'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: {sorted(failed)}', flush=True)
    label = 'discard-discovered-root'
    changed = replace_once(source, '(set found (Some (vecGet cands i)))', '(set found None)', label)
    binary, local = native(label, 0, changed, fixture)
    failed = fallback_options(label, binary, local, 2, {25, 27})
    report['controls'].append({'name': label, 'failed_cases': sorted(failed)})
    print(f'ok   counterexample {label}: {sorted(failed)}', flush=True)
    local = modules('refusals', source)
    for label, declaration, code in [
        ('unchecked-index', '(:: bad (-> Strings Int)) (fn (bad values) (+ 1 (docIndexOf values "")))', 'AX3004'),
        ('unchecked-kind', '(:: bad (-> ASTNode Int)) (fn (bad node) (strLen (docDeclKind node)))', 'AX3004'),
        ('nonexhaustive-index', '(:: bad (-> Strings Int)) (fn (bad values) (match (docIndexOf values "") ((Some n) n)))', 'AX3005'),
        ('nonexhaustive-root', '(:: bad Int) ;@axiom:effect(io)\n(fn (bad) (match docFindRoot ((Some path) (strLen path))))', 'AX3005'),
        ('raw-library-result', '(:: bad String) ;@axiom:effect(io)\n(fn (bad) docStdlibDir)', 'AX3004'),
    ]:
        path = work/(label+'.ax')
        path.write_text('(import core) (import parser) (import doc) (import Str)\n'+declaration+'\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)], env=local,
                                capture_output=True, text=True, timeout=90)
        (work/(label+'.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode != 0 and len(errors) == 1 and errors[0].startswith('E '+code+' '), (label, result)
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    report['render_golden_sha256'] = hashlib.sha256(golden.read_bytes()).hexdigest()
    report['render_bytes'] = sum(len(x.encode()) for item in expected_render.values()
                                 for x in [item['stdout'], item['stderr'], *item['files'].values()])
    (work/'report.json').write_text(json.dumps(report, indent=2)+'\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--baseline-source', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    work = args.work or Path(tempfile.mkdtemp(prefix='axiom-doc-lookups-'))
    work.mkdir(parents=True, exist_ok=True)
    check(args.axiom.resolve(), root, work.resolve(), args.baseline_source)


if __name__ == '__main__':
    main()
