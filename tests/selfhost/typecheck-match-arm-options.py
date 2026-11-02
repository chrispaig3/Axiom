#!/usr/bin/env python3
"""Keep match-arm absence, joins, diagnostics and owning result slots typed."""
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
CASES = [
    '(:: choose (-> Int Int))\n(fn (choose n) (match n (0 2) (_ 3)))\n(:: main Int)\n(fn (main) (choose 1))\n',
    '(:: choose (-> Int Int))\n(fn (choose n) (match n (0 "zero") (_ { (let value 1) value })))\n(:: main Int)\n(fn (main) (choose 1))\n',
    '(:: main Int)\n(fn (main) { (match 0 (0 "zero") (_ 1)) 0 })\n',
    '(:: choose (-> Int ()))\n(fn (choose n) (match n (0 ()) (_ "zero")))\n(:: main Int)\n(fn (main) { (choose 1) 0 })\n',
    '(:: choose (-> Int Int))\n(fn (choose n) (match n (0 missing) (_ 1)))\n(:: main Int)\n(fn (main) (choose 1))\n',
    '(data Color (Red) (Blue))\n(:: choose (-> Color Int))\n(fn (choose c) (match c ((Missing) 1) ((Blue) 2)))\n(:: main Int)\n(fn (main) 0)\n',
]
BRIDGE = '''
(pub :: probeCaseChecker (-> Int TC))
(pub fn (probeCaseChecker mode) {
  (let source (probeCaseSource mode))
  (let tokens (lex source))
  (let parsed (parseModuleWith tokens (scanAxtags source)))
  (let units (vecPush vecNew
    (CUnit2 :file "match-arms.ax" :src source :name (Some "") :imports vecNew :library false)))
  (match parsed
    ((ParseFailed parseError1) { (let checker (tcNew vecNew vecNew units))
      (vecPush checker.out (parseErrDiag tokens (ParseFailed parseError1) source))
      checker })
    ((ParseSuccess parsedValue1 parsedPos1) { (let declarations parsedValue1)
      (for declaration in declarations (writeNodeWord declaration 5 1))
      (checkModuleTcTyped declarations declarations units) }))
})
(pub :: probeCaseText (-> Int String))
(pub fn (probeCaseText mode) {
  (let checker (probeCaseChecker mode))
  (renderDiagsUnits checker.out checker.units)
})
(pub :: probeCaseGood (-> Int Bool))
(pub fn (probeCaseGood mode) {
  (let checker (probeCaseChecker mode))
  (if (|| (== mode 0) (|| (== mode 2) (== mode 3)))
    (== (vecLen checker.out) 0)
    (if (!= (vecLen checker.out) 1) false
      (strEq (diagCode (vecGet checker.out 0))
        (if (== mode 1) "AX3004" (if (== mode 4) "AX3001" "AX3003")))))
})
'''
BRIDGE += '(:: probeCaseSource (-> Int String))\n(fn (probeCaseSource mode)\n'
for i, source in enumerate(CASES[:-1]):
    BRIDGE += f'  (if (== mode {i}) {json.dumps(source)}\n'
BRIDGE += json.dumps(CASES[-1]) + ')' * len(CASES) + '\n'


def change_function(source, name, before, after):
    begin = source.index('(pub fn (' + name + ' ')
    end = source.index('\n\n', begin)
    changed = replace_once(source[begin:end], before, after, name)
    return source[:begin] + changed + source[end:]


def check(compiler, root, work):
    source = (root / 'core/typecheck.ax').read_text()
    fixture = work / 'match-arm-options.ax'
    fixture.write_bytes((root / 'tests/selfhost/typecheck-match-arm-options.axp').read_bytes())
    environment = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    expected = [f'{i} true' for i in range(1, 58)]
    missing = replace_once(source, '(vecPush tys (:: None (Option ASTNode)))',
                           '(vecPush (as tys Ints) (as (:: None (Option ASTNode)) Int))', 'erased absent row')
    missing = replace_once(missing, '(pub fn (checkArms ',
                           ';@axiom:effect(unsafe)\n(pub fn (checkArms ', 'unsafe ablation boundary')
    unit = change_function(source, 'matchArmsUnit', '(tyIsUnit ty)\n      false)', '(tyIsUnit ty)\n      true)')
    mismatch = change_function(source, 'armJoin', '(== disc 0)', '(== disc 2)')
    ownership = change_function(source, 'armTypeOpt', '(Some ty)',
                               '{ (let row (Some ty)) (memMarkLeaf (as row Int)) row }')
    tail = change_function(source, 'armTailSpan', '(spanOf e)\n              sp)',
                           '(spanOf e)\n              (spanOf e))')
    variants = [('erased-absent-row', missing, (32, 56)), ('missing-is-unit', unit, (19,)),
                ('lost-mismatch', mismatch, (11, 51)), ('unmapped-present-row', ownership, (56,)),
                ('lost-tail-span', tail, (42, 43))]
    report = {'source_sha256': hashlib.sha256(source.encode()).hexdigest(), 'builder': str(compiler),
              'configurations': [], 'counterexamples': [], 'refusals': [], 'diagnostics': [],
              'invariants': [
                  {'invariant': 'Rejected arms are None; checked poison, wildcard and unit types remain Some.',
                   'enforcement': 'ArmTypes, armTypeOpt and explicit join/agreement/unit branches; cases1-21,31-39,49.',
                   'counterexample': 'missing-is-unit'},
                  {'invariant': 'The first concrete join witness and original last-arm result are preserved.',
                   'enforcement': 'Optional witnesses and ordered checkArms recursion; cases5-14,31-37.',
                   'counterexample': 'lost-mismatch'},
                  {'invariant': 'None-first and static values keep the vector owning, and present children retire on clear and death.',
                   'enforcement': 'Typed Option writes, vecOwnsRefs and child counts through growth/set/clear/death; cases17,22-30,32,56-57.',
                   'counterexample': 'erased-absent-row and unmapped-present-row'},
                  {'invariant': 'Diagnostic order, tail anchors, discarded results and recovery retain their prior meaning.',
                   'enforcement': 'Tail cases40-46, Result/recovery47-49 and byte-exact six source controls at O0/O2.',
                   'counterexample': 'lost-tail-span and lost-mismatch'},
              ],
              'known_limits': ['Host O0/O2 native execution with allocation poisoning; no Windows runtime claim.',
                               'None/static array-kind evidence relies on existing counted-type retain evidence; Vec policy is unchanged.',
                               'Parser nil handles are normalised at arm-result insertion and child-selection boundaries; Span0 remains the existing unavailable-source protocol.',
                               'The match still returns its prior last-arm type or fresh fallback; this does not redesign inference or exhaustiveness.',
                               'No held M5 work or lifetime/enforcement algorithm is read, changed or validated; no global soundness or Rust parity claim follows.']}
    run_checked([str(compiler), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)], env=environment,
                stdout=work / 'fmt.stdout', stderr=work / 'fmt.stderr')

    def modules(label, contents):
        directory = work / (label + '-modules/core')
        directory.mkdir(parents=True)
        for path in (root / 'core').iterdir():
            destination = directory / path.name
            if path.name == 'typecheck.ax':
                destination.write_text(contents + BRIDGE)
            else:
                destination.symlink_to(path, target_is_directory=path.is_dir())
        return dict(environment, AXIOM_PATH=str(directory))

    def build_run(label, contents, optimization, failures=()):
        local = modules(label, contents)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(fixture),
                     '--opt', str(optimization), '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '.build.stdout'), stderr=work / (label + '.build.stderr'), timeout=240)
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        observed = check_output(output, expected, required_failures=failures)
        print('ok   ' + label + ': ' + str(sorted(observed)), flush=True)
        return observed, binary, local

    baselines = []
    for index, text in enumerate(CASES):
        path = work / ('diagnostic-' + str(index) + '.ax')
        path.write_text(text)
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)],
                                env=environment, capture_output=True, text=True, timeout=60)
        expected_status = 1 if index in (1, 4, 5) else 0
        lines = result.stderr.splitlines(keepends=True)
        diagnostics = [line for line in lines if line.startswith(('E ', 'W '))]
        other = [line.strip() for line in lines if line.strip() and not line.startswith(('E ', 'W '))]
        if result.returncode != expected_status or other != ([] if not expected_status else ['compilation failed due to 1 previous error']):
            raise RuntimeError(('diagnostic baseline', index, result))
        if len(diagnostics) != expected_status:
            raise RuntimeError(('diagnostic shape', index, diagnostics))
        baselines.append(''.join(diagnostics).replace(str(path), 'match-arms.ax'))
    for level in (0, 2):
        _, binary, local = build_run('positive-O' + str(level), source, level)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True,
                                         'cases': 57, 'status': 'passed'})
        for index, wanted in enumerate(baselines):
            result = subprocess.run([str(binary), str(index)], env=local, capture_output=True, text=True, timeout=30)
            (work / (f'diagnostic-{index}-O{level}.axdl')).write_text(result.stdout)
            if result.returncode or result.stderr or result.stdout != wanted:
                raise RuntimeError(('diagnostic changed', index, wanted, result))
            report['diagnostics'].append({'case': index, 'optimization': level, 'status': 'passed'})
    for label, changed, cases in variants:
        observed, _, _ = build_run(label, changed, 0, cases)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(observed)})
    local = modules('refusals', source)
    for name, expression, code in [
        ('raw-join-witness', '(armJoin (tcNew vecNew vecNew vecNew) nilNode mkIntTy (mkEInt 0) 0)', 'AX3004'),
        ('raw-arm-vector', '(matchArmsUnit (vecPush vecNew mkIntTy) 0)', 'AX3004'),
        ('missing-join-none', '(match (armJoin (tcNew vecNew vecNew vecNew) None mkIntTy (mkEInt 0) 0) ((Some ty) (nodeTag ty)))', 'AX3005'),
    ]:
        path = work / (name + '.ax')
        path.write_text('(import core)\n(import parser)\n(import typecheck)\n(import Vec)\n(:: main Int)\n(fn (main) { '
                        + expression + ' 0 })\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)],
                                env=local, capture_output=True, text=True, timeout=60)
        (work / (name + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or f'E {code} ' not in errors[0]:
            raise RuntimeError((name, result))
        report['refusals'].append({'name': name, 'diagnostic': code, 'status': 'passed'})
        print('ok   ' + name + ': ' + code, flush=True)
    (work / 'match-arm-option-report.json').write_text(json.dumps(report, indent=2) + '\n')


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
        with tempfile.TemporaryDirectory(prefix='axiom-match-arm-options-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
