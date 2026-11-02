#!/usr/bin/env python3
"""Check optional flag facts, CLI validation bytes and formatter side effects."""
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

SCENARIOS = [
    ['build'], ['build', '--opt=0'], ['build', '--opt', '0'], ['check', '--alloc-poison', 'probe.ax'],
    ['check', '--unknown', 'probe.ax'], ['check', '--unknown=', 'probe.ax'],
    ['check', '--input'], ['build', '--opt'], ['build', '--opt='], ['build', '--opt', ''],
    ['build', '--opt=banana'], ['check', '--diagnostic-format='],
    ['check', '--diagnostic-format=ai', 'probe.ax'], ['check', '--diagnostic-format=wrong'],
    ['fmt', '--check=', 'probe.ax'], ['fmt', '--check=true', 'probe.ax'],
    ['--opt', '0', 'check', 'probe.ax'], ['check', '--input', '--help'],
    ['run', 'probe.ax', '--unknown'], ['run', '--', '--unknown'],
    ['check', '--', '--help'], ['fmt', 'probe.ax', '--help'], ['fmt'],
    ['fmt', '--emit=stdout', 'probe.ax'], ['fmt', '--emit', 'stdout', 'probe.ax'],
    ['fmt', '--emit=', 'probe.ax'], ['fmt', '--check', 'probe.ax'], ['fmt', '--diff', 'probe.ax'],
    ['fmt', '--emit=wrong', 'probe.ax'], ['fmt', '--input='], ['fmt', '--input', 'probe.ax'],
    ['fmt', '--input=probe.ax', '--check'], ['fmt', '--emit=std=out', 'probe.ax'],
    ['fmt', '--', '-dash.ax'], ['fmt', '--check', '--', '-dash.ax'],
]


def check(compiler, root, work, baseline=None):
    sources = {name: (root/'core'/name).read_text() for name in ('driver.ax', 'fmtcli.ax')}
    fixture = (root/'tests/selfhost/cli-flag-parts-options.axp').read_text()
    behavior = (root/'tests/selfhost/cli-flag-parts-behavior.axp').read_text()
    expected = [f'{i} true' for i in range(1, 21)]
    report = {'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'source_sha256': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in sources.items()},
              'configurations': [], 'controls': [], 'refusals': [],
              'limits': ['Host O0/O2 with allocation poisoning; not target-wide qualification.',
                         'The behavior harness calls the real validator and formatter, not compiler code generation.',
                         'This probe covers its named query contract; general values and command indexes have separate fixtures.']}
    data = work/'inputs'; data.mkdir(exist_ok=True)

    def modules(label, edits):
        folder = work/(label+'-modules/core'); folder.mkdir(parents=True, exist_ok=True)
        for path in (root/'core').iterdir():
            dest = folder/path.name
            if path.name in edits:
                dest.write_text(edits[path.name])
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

    def native(label, level, edits, program):
        local = modules(label, edits)
        path = work/(label+'.ax'); path.write_text(program)
        binary = work/label
        run(label+'-build', [str(compiler), '--diagnostic-format=ai', 'build', str(path), '--opt', str(level),
                            '--alloc-poison', '-o', str(binary)], local, 0)
        return binary, local

    def outcomes(label, binary, local):
        results = []
        for i, args in enumerate(SCENARIOS):
            for file in ('probe.ax', '-dash.ax'):
                (data/file).write_text('(:: main Int)\n(fn (main) 3)\n')
            actual = run(label+'-'+str(i), [str(binary), *args], local)
            results.append({'argv': args, 'status': actual.returncode, 'stdout': actual.stdout.decode(),
                            'stderr': actual.stderr.decode(),
                            'files': {file: (data/file).read_text() for file in ('probe.ax', '-dash.ax')}})
        return results

    golden = root/'tests/selfhost/cli-flag-parts-behavior.golden.json'
    if baseline:
        old = {name: (baseline/name).read_text() for name in sources}
        binary, local = native('baseline', 0, old, behavior)
        result = outcomes('baseline', binary, local)
        if golden.exists():
            assert json.loads(golden.read_text()) == result, 'baseline behavior differs'
        else:
            golden.write_text(json.dumps(result, ensure_ascii=True, indent=2)+'\n')
        report['baseline_source_sha256'] = {name: hashlib.sha256(text.encode()).hexdigest() for name,text in old.items()}
    assert golden.exists(), 'record original CLI output first'
    wanted = json.loads(golden.read_text())
    for level in (0, 2):
        label='positive-O'+str(level)
        binary, local = native(label, level, sources, fixture)
        actual=run(label, [str(binary)], local, 0); assert not actual.stderr
        check_output(work/(label+'.stdout'), expected)
        binary, local = native('behavior-O'+str(level), level, sources, behavior)
        assert outcomes('behavior-O'+str(level), binary, local) == wanted, ('CLI behavior changed', level)
        report['configurations'].append({'optimization': level, 'poison': True, 'cases': 20,
                                         'cli_scenarios': len(SCENARIOS)})
        print(f'ok   CLI flag parts: 20 outcomes and {len(SCENARIOS)} exact behavior scenarios O{level}', flush=True)
    driver=sources['driver.ax']
    for label, before, after, failures in [
        ('discard-zero-arity', '(Some 0)', 'None', {1, 6}),
        ('unknown-is-boolean', '      None)))', '      (Some 0))))', {3, 4, 5}),
        ('discard-empty-inline', '(Some (strSlice a (+ e 1) (- (strLen a) (+ e 1))))',
         '(if (== (+ e 1) (strLen a)) None (Some (strSlice a (+ e 1) (- (strLen a) (+ e 1)))))', {9, 13}),
        ('fabricate-inline', '    None))\n\n; Is this argument', '    (Some "")))\n\n; Is this argument', {8, 20}),
        ('retain-inline-input', '(Some (strSlice a (+ e 1) (- (strLen a) (+ e 1))))',
         '{ (__retainref a) (Some (strSlice a (+ e 1) (- (strLen a) (+ e 1)))) }', {18}),
    ]:
        name = 'flagArity' if label in ('discard-zero-arity', 'unknown-is-boolean') else 'flagValuePart'
        start = driver.index('(pub fn (' + name + ' ')
        end = driver.index('\n\n', start)
        body = driver[start:end]
        if label == 'fabricate-inline':
            before, after = '    None))', '    (Some "")))'
        changed = driver[:start] + replace_once(body, before, after, label) + driver[end:]
        edits=dict(sources, **{'driver.ax':changed})
        binary,local=native(label,0,edits,fixture)
        actual=run(label,[str(binary)],local,0); assert not actual.stderr
        failed=check_output(work/(label+'.stdout'),expected,required_failures=failures)
        report['controls'].append({'name':label,'failed_cases':sorted(failed)})
        # Unit controls establish the changed fact; validator/formatter outputs are
        # independently compared against the original implementation above.
        print(f'ok   counterexample {label}: {sorted(failed)}',flush=True)
    label = 'accept-value-for-boolean'
    start = driver.index('(pub fn (checkArgsFrom ')
    end = driver.index('; The values that have exactly', start)
    changed = driver[:start] + replace_once(driver[start:end], '(if (== arity 0)', '(if false', label) + driver[end:]
    binary, local = native(label, 0, dict(sources, **{'driver.ax': changed}), behavior)
    actual = outcomes(label, binary, local)
    different = [i for i, (got, expected_case) in enumerate(zip(actual, wanted)) if got != expected_case]
    assert {14, 15} <= set(different), different
    report['controls'].append({'name': label, 'changed_cli_scenarios': different})
    print(f'ok   counterexample {label}: CLI scenarios {different}', flush=True)
    local=modules('refusals',sources)
    for label,declaration,code in [
        ('unchecked-arity','(:: bad Int) (fn (bad) (+ (flagArity "--check") 1))','AX3004'),
        ('unchecked-inline','(:: bad Int) (fn (bad) (strLen (flagValuePart "--input=")))','AX3004'),
        ('nonexhaustive-arity','(:: bad Int) (fn (bad) (match (flagArity "--check") ((Some n) n)))','AX3005'),
        ('nonexhaustive-inline','(:: bad Int) (fn (bad) (match (flagValuePart "--input=") ((Some text) (strLen text))))','AX3005'),
        ('binding-outside-success','(:: bad Int) (fn (bad) (if (let (Some text) (flagValuePart "x")) 0 (strLen text)))','AX3001'),
    ]:
        path=work/(label+'.ax');path.write_text('(import driver) (import Str)\n'+declaration+'\n')
        result=run(label,[str(compiler),'--diagnostic-format=ai','check',str(path)],local)
        errors=[line for line in result.stderr.decode().splitlines() if line.startswith('E ')]
        assert result.returncode!=0 and len(errors)==1 and errors[0].startswith('E '+code+' '),(label,result)
        report['refusals'].append({'name':label,'code':code})
        print(f'ok   refusal {label}: {code}',flush=True)
    report['behavior_sha256']=hashlib.sha256(golden.read_bytes()).hexdigest()
    (work/'report.json').write_text(json.dumps(report,indent=2)+'\n')


def main():
    parser=argparse.ArgumentParser()
    parser.add_argument('--axiom',required=True,type=Path)
    parser.add_argument('--work',type=Path)
    parser.add_argument('--baseline-core',type=Path)
    args=parser.parse_args()
    root=Path(__file__).resolve().parents[2]
    work=args.work or Path(tempfile.mkdtemp(prefix='axiom-cli-flag-parts-'))
    work.mkdir(parents=True,exist_ok=True)
    check(args.axiom.resolve(),root,work.resolve(),args.baseline_core)


if __name__=='__main__':
    main()
