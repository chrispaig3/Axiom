#!/usr/bin/env python3
"""Check counted source indexes and missing cross-unit render context."""
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
    source = {n: (root / 'core' / n).read_text() for n in ('diag.ax', 'render.ax')}
    fixture = (root / 'tests/selfhost/diagnostic-source-index.axp').read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    expected = [f'{i} true' for i in range(1, 45)]
    report = {'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'source_sha256': {n: hashlib.sha256(s.encode()).hexdigest() for n, s in source.items()},
              'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
              'configurations': [], 'controls': [], 'refusals': [],
              'limits': ['Host native O0/O2 allocation poisoning, not target-wide qualification.',
                         'Primary reporting still requires an entry unit; sourceIndexAt is the optional lookup.',
                         'Numeric span ABI and remaining nullable source String guards are outside this change.']}

    def modules(label, texts):
        folder = work / (label + '-modules/core')
        folder.mkdir(parents=True, exist_ok=True)
        for path in (root / 'core').iterdir():
            dest = folder / path.name
            if path.name in texts:
                dest.write_text(texts[path.name])
            elif not dest.exists():
                dest.symlink_to(path, target_is_directory=path.is_dir())
        return dict(env, AXIOM_PATH=str(folder))

    def native(label, level, texts, program):
        local = modules(label, texts)
        path = work / (label + '.ax')
        path.write_text(program)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(path), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '-build.stdout'), stderr=work / (label + '-build.stderr'), timeout=240)
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        return output

    for level in (0, 2):
        label = 'positive-O' + str(level)
        check_output(native(label, level, source, fixture), expected)
        growth = (work / (label + '.stderr')).read_text()
        assert growth == 'index-growth 0\n', growth
        report['configurations'].append({'optimization': level, 'poison': True, 'cases': 44,
                                         'twenty_iterations_live_growth_bytes': 0})
        print(f'ok   source index: 44 cases O{level}; twenty two-unit tables leave 0 live bytes', flush=True)
    for label, before, after, required in [
        ('wrong-start-vector', '(pub fn (srcIxStartsVec ix)\n  ix.starts)',
         '(pub fn (srcIxStartsVec ix)\n  ix.chars)', {2, 8}),
        ('drop-present-index', '(Some (vecGet ixs unit))', 'None', {15, 21}),
        ('raw-index-storage', '(vecPush out (srcLineIndex (unitSrc (vecGet units i))))',
         '(vecPush (as out Ints) (as (srcLineIndex (unitSrc (vecGet units i))) Int))', {36}),
    ]:
        changed = dict(source)
        changed['diag.ax'] = replace_once(source['diag.ax'], before, after, label)
        if label == 'raw-index-storage':
            changed['diag.ax'] = replace_once(changed['diag.ax'], '(pub fn (unitIndexes units)',
                ';@axiom:effect(unsafe)\n(pub fn (unitIndexes units)', 'raw storage claim')
        failures = check_output(native(label, 0, changed, fixture), expected, required_failures=required)
        report['controls'].append({'name': label, 'failed_cases': sorted(failures)})
        print(f'ok   counterexample {label}: {sorted(failures)}', flush=True)
    prelude = '''(import core) (import diag) (import render) (import Vec) (import IO)
(:: main ())
;@axiom:effect(io)
(fn (main) {
 (let units (:: vecNew Units))
 (vecPush units (CUnit2 :file "entry" :src "x" :name None :imports vecNew :library false))
 (vecPush units (CUnit2 :file "other" :src "x" :name None :imports vecNew :library false))
 (let indexes (:: vecNew SourceIndexes)) (vecPush indexes (srcLineIndex "x"))
 (let d (mkDiagBase 0 "AX3001" "probe" 0 "m" None))
 (diagAddSecondaryIn d (mkSpan 0 1) "secondary" 1)
 (diagAddTrace d "frame" (mkSpan 0 1) UNIT)
 (let good CHECK) (println "1 {good}") })
'''
    for label, module, before, after, unit, expression in [
        ('short-secondary-index', 'diag.ax', '(>= (diagSecUnit d i) (vecLen ixs))', 'false', '1',
         '(== (diagSecCross d 0 units indexes) 0)'),
        ('short-frame-index', 'render.ax', '(pub fn (traceResolvable d i units ixs)', None, '1',
         '(== (traceResolvable d 0 units indexes) 0)'),
        ('negative-frame-unit', 'render.ax', '(pub fn (traceResolvable d i units ixs)', None, '-1',
         '(== (traceResolvable d 0 units indexes) 0)'),
    ]:
        changed = dict(source)
        if after is not None:
            changed[module] = replace_once(source[module], before, after, label)
        else:
            text = source[module]
            start = text.index(before)
            end = text.index('(pub :: traceRows ', start)
            body = text[start:end]
            old = '(>= fu (vecLen ixs))' if label == 'short-frame-index' else '(< fu 0)'
            body = replace_once(body, old, 'false', label)
            changed[module] = text[:start] + body + text[end:]
        program = prelude.replace('UNIT', unit).replace('CHECK', expression)
        check_output(native(label + '-baseline', 0, source, program), ['1 true'])
        failures = check_output(native(label, 0, changed, program), ['1 true'], required_failures={1})
        report['controls'].append({'name': label, 'failed_cases': sorted(failures)})
        print(f'ok   counterexample {label}: {sorted(failures)}', flush=True)
    local = modules('refusals', source)
    for label, body, code in [
        ('erased-index', '(:: bad (-> Int Int)) (fn (bad ix) (lineOfIx ix 0))', 'AX3004'),
        ('erased-index-table', '(:: bad (-> Units Ints)) (fn (bad units) (unitIndexes units))', 'AX3004'),
        ('wrong-vector-elements', '(:: bad (-> SrcIx Strings)) (fn (bad ix) (srcIxStartsVec ix))', 'AX3004'),
        ('missing-index-case', '(:: bad (-> SourceIndexes Int SrcIx)) (fn (bad indexes unit) (match (sourceIndexAt indexes unit) ((Some index) index)))', 'AX3005'),
    ]:
        path = work / (label + '.ax'); path.write_text('(import core) (import diag)\n' + body + '\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)], env=local,
                                capture_output=True, text=True, timeout=90)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        assert result.returncode != 0 and len(errors) == 1 and errors[0].startswith('E ' + code + ' '), (label, result)
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    path = work / 'empty-primary.ax'
    path.write_text('(import diag) (import Vec)\n(:: main ())\n(fn (main) { (let index (indexForUnit vecNew 0)) () })\n')
    binary = work / 'empty-primary'
    run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(path), '--alloc-poison', '-o', str(binary)],
                env=local, stdout=work/'empty-primary-build.stdout', stderr=work/'empty-primary-build.stderr')
    result = subprocess.run([str(binary)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 80 and 'precondition failed' in result.stderr, result
    report['empty_primary_contract'] = {'exit': result.returncode}
    (work / 'report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    work = args.work or Path(tempfile.mkdtemp(prefix='axiom-source-index-'))
    work.mkdir(parents=True, exist_ok=True)
    check(args.axiom.resolve(), root, work)


if __name__ == '__main__':
    main()
