#!/usr/bin/env python3
"""Check optional region marks, binding indexes and resolved witnesses."""
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
CHECKED = runpy.run_path(str(Path(__file__).with_name('typecheck-checked-type-options.py')))
DIAGNOSTICS = CHECKED['DIAGNOSTICS']
BRIDGE = CHECKED['BRIDGE']
RECORDS = runpy.run_path(str(Path(__file__).with_name('typecheck-region-records.py')))


def change_function(original, name, old, new):
    begin = original.index('(pub fn (' + name + ' ')
    end = original.index('\n\n', begin)
    body = replace_once(original[begin:end], old, new, name)
    return original[:begin] + body + original[end:]


def check(compiler, root, work):
    original = (root / 'core/typecheck.ax').read_text()
    environment = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    fixture = work / 'region-index-options.ax'
    fixture.write_bytes((root / 'tests/selfhost/typecheck-region-index-options.axp').read_bytes())
    expected = [f'{i} true' for i in range(1, 43)]
    mark = change_function(original, 'rgInnerMark', '(Some entry.mark)',
                           '(if (== entry.mark 0) None (Some entry.mark))')
    shadow = change_function(original, 'rgnEnvFind',
                             '(rgnEnvFindFrom rc name (- (vecLen (rgnNames rc)) 1))',
                             '(rgnEnvFindFrom rc name (if (== (vecLen (rgnNames rc)) 0) -1 0))')
    root_zero = change_function(original, 'rgRootIdx',
                                '(scopeFindIdx (tcScopeVec tc) (nodeAName e))',
                                '(if (let (Some index) (scopeFindIdx (tcScopeVec tc) (nodeAName e)))'
                                ' (if (== index 0) None (Some index)) None)')
    unresolved = change_function(original, 'rgnResolvedCulprit',
                                 '(if (strEq (vecGet (rgnCulprits f) i) "<unresolved call>")\n'
                                 '            false\n            true)', 'true')
    variants = [('lost-zero-mark', mark, (3, 5)), ('oldest-binding', shadow, (18, 19, 20, 21, 25, 28, 29)),
                ('lost-zero-root', root_zero, (8, 9, 32)), ('unresolved-is-finding', unresolved, (35, 36))]
    report = {'source_sha256': hashlib.sha256(original.encode()).hexdigest(), 'builder': str(compiler),
              'configurations': [], 'counterexamples': [], 'refusals': [], 'diagnostics': [],
              'adapter_controls': [],
              'invariants': [
                  {'invariant': 'A missing mark or root is None; mark and root index zero remain present.',
                   'enforcement': 'Option Int signatures, explicit store fallback and cases1-12,32.',
                   'counterexample': 'lost-zero-mark and lost-zero-root'},
                  {'invariant': 'Binding search selects the most recent matching entry and preserves parameter shadowing.',
                   'enforcement': 'Reverse lookup and explicit local/global, scoped and store branches; cases13-31.',
                   'counterexample': 'oldest-binding'},
                  {'invariant': 'Only a resolved flow is a finding, with the first parameter witness retained.',
                   'enforcement': 'Option witness and explicit absence path in restrictNoEscape; cases33-42.',
                   'counterexample': 'unresolved-is-finding'},
                  {'invariant': 'Existing optional record ownership and ordinary region diagnostics remain intact.',
                   'enforcement': 'Original39-case record fixture including strict cache retirement32; byte-exact accepted/AX3059/AX3062 controls.',
                   'counterexample': 'Existing record fixture ownership ablations remain unchanged.'},
              ],
              'known_limits': ['Host O0/O2 execution with allocation poisoning; no Windows runtime claim.',
                               'Only lookup representations and their direct branches change; masks, traversal, fixpoint and lifetime algorithms stay numeric and unchanged.',
                               'Empty-name case exercises typed helper storage, not source identifier syntax.',
                               'Internal stack cursor rgInner remains numeric; parser arena nil and poison are separate contracts.',
                               'No held M5 contents are reviewed or validated; focused evidence does not establish global soundness or Rust parity.']}
    run_checked([str(compiler), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)], env=environment,
                stdout=work / 'fmt.stdout', stderr=work / 'fmt.stderr')

    def modules(label, contents, bridge=BRIDGE):
        directory = work / (label + '-modules/core')
        directory.mkdir(parents=True)
        for path in (root / 'core').iterdir():
            dest = directory / path.name
            if path.name == 'typecheck.ax':
                dest.write_text(contents + bridge)
            else:
                dest.symlink_to(path, target_is_directory=path.is_dir())
        return dict(environment, AXIOM_PATH=str(directory))

    def build_run(label, contents, level, failures=()):
        local = modules(label, contents)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(fixture),
                     '--opt', str(level), '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '.build.stdout'), stderr=work / (label + '.build.stderr'))
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        observed = check_output(output, expected, required_failures=failures)
        print('ok   ' + label + ': ' + str(sorted(observed)), flush=True)
        return observed, binary, local

    baselines = []
    for index, text in enumerate(DIAGNOSTICS):
        source = work / ('diagnostic-' + str(index) + '.ax')
        source.write_text(text)
        baseline = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(source)],
                                  env=environment, capture_output=True, text=True)
        if baseline.returncode != (0 if index == 0 else 1):
            raise RuntimeError(('diagnostic control status', index, baseline))
        lines = baseline.stderr.splitlines(keepends=True)
        diagnostics = [line for line in lines if line.startswith(('E ', 'W '))]
        other = [line.strip() for line in lines if line.strip() and not line.startswith(('E ', 'W '))]
        if other != ([] if index == 0 else ['compilation failed due to 1 previous error']):
            raise RuntimeError(('unexpected compiler output', index, other))
        wanted = ''.join(diagnostics).replace(str(source), 'checked-stamp.ax')
        if (index == 0 and wanted) or (index != 0 and len(wanted.splitlines()) != 1):
            raise RuntimeError(('diagnostic control shape', index, wanted))
        baselines.append(wanted)
    for level in (0, 2):
        _, binary, local = build_run('positive-O' + str(level), original, level)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True,
                                         'cases': 42, 'status': 'passed'})
        for index, wanted in enumerate(baselines):
            result = subprocess.run([str(binary), str(index)], env=local, capture_output=True, text=True)
            (work / (f'diagnostic-{index}-O{level}.axdl')).write_text(result.stdout)
            if result.returncode or result.stderr or result.stdout != wanted:
                raise RuntimeError(('diagnostic changed', index, wanted, result))
            report['diagnostics'].append({'case': index, 'optimization': level, 'status': 'passed'})
    for label, changed, cases in variants:
        failures, _, _ = build_run(label, changed, 0, cases)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failures)})

    local = modules('record-adapter', original, RECORDS['BRIDGE'])
    record_fixture = work / 'region-record-adapter.ax'
    record_fixture.write_bytes((root / 'tests/selfhost/typecheck-region-records.axp').read_bytes())
    binary = work / 'record-adapter'
    run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(record_fixture),
                 '--opt', '0', '--alloc-poison', '-o', str(binary)], env=local,
                stdout=work / 'record-adapter.build.stdout', stderr=work / 'record-adapter.build.stderr')
    output = work / 'record-adapter.stdout'
    run_checked([str(binary)], env=local, stdout=output, stderr=work / 'record-adapter.stderr', timeout=30)
    check_output(output, [f'{i} true' for i in range(1, 40)])
    report['adapter_controls'].append({'fixture': 'typecheck-region-records.axp', 'cases': 39,
                                       'optimization': 0, 'allocation_poisoning': True, 'status': 'passed'})
    print('ok   region record API adapter: 39 cases including strict retirement32', flush=True)

    local = modules('refusals', original)
    for name, expression, code in [
        ('unchecked-mark', '(+ 1 (rgInnerMark (tcNew vecNew vecNew vecNew)))', 'AX3004'),
        ('missing-index-none', '(match (rgnEnvFind context "first") ((Some i) i))', 'AX3005'),
        ('unchecked-culprit', '(+ 1 (rgnResolvedCulprit (rgnFactsNew 1) 0))', 'AX3004'),
    ]:
        refused = work / (name + '.ax')
        template = fixture.read_text()
        begin = template.index('(:: context ')
        end = template.index('(:: checks ', begin)
        refused.write_text('(import core)\n(import parser)\n(import typecheck)\n(import Vec)\n'
                           + template[begin:end] + '(:: main Int)\n(fn (main) { ' + expression + ' 0 })\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(refused)],
                                env=local, capture_output=True, text=True)
        (work / (name + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or f'E {code} ' not in errors[0]:
            raise RuntimeError((name, result))
        report['refusals'].append({'name': name, 'diagnostic': code, 'status': 'passed'})
        print('ok   ' + name + ': ' + code, flush=True)
    (work / 'region-index-option-report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), root, args.work.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-region-index-options-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
