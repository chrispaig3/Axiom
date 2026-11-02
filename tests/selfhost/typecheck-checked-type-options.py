#!/usr/bin/env python3
"""Keep optional checked-type lookups conservative at their direct consumers."""
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
DIAGNOSTICS = [
    '(:: main Int)\n(fn (main) { (region r (+ 1 2)) 0 })\n',
    '(struct Payload (name : String))\n(:: main Int)\n(fn (main) { (region r (Payload :name "inner")) 0 })\n',
    '(struct Payload (name : String))\n(struct Hook (mut f : (-> Int Int)))\n'
    '(:: initial (-> Int Int))\n(fn (initial n) n)\n'
    '(:: keepFn (-> Hook (-> Int Int) Int))\n(fn (keepFn h f) { (set h.f f) 0 })\n'
    '(:: main Int)\n(fn (main) { (let h (Hook :f initial)) '
    '(region r { (let s (Payload :name "inner")) '
    '(keepFn h (lambda (n) { s.name n })) 0 }) 0 })\n',
]
BRIDGE = '''
(:: expectParsed (-> (PResult a) a))
(fn (expectParsed result)
  (match result
    ((ParseSuccess value position) value)
    ((ParseFailed error) __indexTrap)))

(pub :: probeComputeCast (-> (Option ASTNode) Int))
(pub fn (probeComputeCast ty) {
  (let checker (tcNew vecNew vecNew vecNew))
  (let expression (mkEApp (mkEApp (mkEVar "cast") (mkEVar "Int")) (mkEInt 1)))
  (if (let (Some checked) ty) (setNodeBinderTyChild expression checked))
  (let walk (ComputeWalk :tc checker :site 0 :unit 0 :seen vecNew :failed 0))
  (computeWalkApp walk expression vecNew vecNew)
  walk.failed
})
(pub :: probeDiagnosticChecker (-> Int TC))
(pub fn (probeDiagnosticChecker mode) {
  (let text (probeDiagnosticSource mode))
  (let declarations (expectParsed (parseModuleWith (lex text) (scanAxtags text))))
  (for declaration in declarations (writeNodeWord declaration 5 1))
  (let units (vecPush vecNew (CUnit2 :file "checked-stamp.ax" :src text :name (Some "") :imports vecNew :library false)))
  (checkModuleTcTyped declarations declarations units)
})
(pub :: probeDiagnosticText (-> Int String))
(pub fn (probeDiagnosticText mode) {
  (let checker (probeDiagnosticChecker mode))
  (renderDiagsUnits checker.out checker.units)
})
(pub :: probeDiagnosticGood (-> Int Bool))
(pub fn (probeDiagnosticGood mode) {
  (let checker (probeDiagnosticChecker mode))
  (if (== mode 0)
    (== (vecLen checker.out) 0)
    (if (!= (vecLen checker.out) 1) false
      (strEq (diagCode (vecGet checker.out 0)) (if (== mode 1) "AX3059" "AX3062"))))
})
'''
BRIDGE += '(:: probeDiagnosticSource (-> Int String))\n(fn (probeDiagnosticSource mode)\n'
for i, text in enumerate(DIAGNOSTICS[:-1]):
    BRIDGE += f'  (if (== mode {i}) {json.dumps(text)}\n'
BRIDGE += json.dumps(DIAGNOSTICS[-1]) + ')))\n'


def change_function(original, name, old, new):
    begin = original.index('(pub fn (' + name + ' ')
    end = original.index('\n\n', begin)
    body = replace_once(original[begin:end], old, new, name + ' None path')
    return original[:begin] + body + original[end:]


def check(compiler, root, work):
    original = (root / 'core/typecheck.ax').read_text()
    environment = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    fixture = work / 'checked-type-options.ax'
    fixture.write_bytes((root / 'tests/selfhost/typecheck-checked-type-options.axp').read_bytes())
    expected = [f'{i} true' for i in range(1, 36)]
    # Validate every source mutation before spending native compiler work.
    poison = replace_once(original, 'None\n            (Some ty))',
                          'None\n            (if (== (tyIsErr ty) 1) None (Some ty)))', 'poison remains present')
    nil = replace_once(original, '(if (nodeSame ty nilNode)\n            None\n            (Some ty))',
                       '(Some ty)', 'missing result remains absent')
    scalar = change_function(original, 'rgnSetField', '        false)', '        true)')
    handler = change_function(original, 'rgnHandlerValue', '    false)', '    true)')
    variants = [('lost-poison', poison, (5, 8, 21)), ('present-nil-result', nil, (10,)),
                ('missing-field-scalar', scalar, (24,)), ('missing-handler-poison', handler, (20,))]
    report = {'source_sha256': hashlib.sha256(original.encode()).hexdigest(), 'builder': str(compiler),
              'configurations': [], 'counterexamples': [], 'refusals': [], 'diagnostics': [],
              'invariants': [
                  {'invariant': 'Missing checked stamps and missing stamped result types are None, with poison and wildcard preserved.',
                   'enforcement': 'Option ASTNode lookup and identity checks1-11.',
                   'counterexample': 'lost-poison and present-nil-result'},
                  {'invariant': 'Unavailable scalar proofs keep parameter and field origins.',
                   'enforcement': 'Explicit None conservative branches, optional parameter signature, cases12-19,23-28.',
                   'counterexample': 'missing-field-scalar'},
                  {'invariant': 'Unavailable handler proofs remain conservative; existing poison suppresses cascades.',
                   'enforcement': 'Explicit optional checked-type tests, cases20-22.',
                   'counterexample': 'missing-handler-poison'},
                  {'invariant': 'Compute casts need a checked primitive type; ordinary accepted and refused diagnostics stay stable.',
                   'enforcement': 'Cases29-35 and byte comparisons with the invoking compiler on identical source.',
                   'counterexample': 'missing-field-scalar and missing-handler-poison'},
              ],
              'known_limits': ['Host O0/O2 execution with allocation poisoning; no Windows runtime claim.',
                               'Only checked-stamp lookup and direct consumer representation contracts are changed.',
                               'Existing ordinary AX3059/AX3062 samples are checked; no lifetime algorithm or held M5 work is reviewed.',
                               'AST storage remains at its existing parser boundary.',
                               'No global soundness, Rust parity or certification claim follows.']}
    run_checked([str(compiler), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)], env=environment,
                stdout=work / 'fmt.stdout', stderr=work / 'fmt.stderr')

    def modules(label, contents):
        directory = work / (label + '-modules/core')
        directory.mkdir(parents=True)
        for path in (root / 'core').iterdir():
            dest = directory / path.name
            if path.name == 'typecheck.ax':
                dest.write_text(contents + BRIDGE)
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
                                         'cases': 35, 'status': 'passed'})
        for index, wanted in enumerate(baselines):
            result = subprocess.run([str(binary), str(index)], env=local, capture_output=True, text=True)
            (work / (f'diagnostic-{index}-O{level}.axdl')).write_text(result.stdout)
            if result.returncode or result.stderr or result.stdout != wanted:
                raise RuntimeError(('diagnostic changed', index, wanted, result))
            report['diagnostics'].append({'case': index, 'optimization': level, 'status': 'passed'})
    for label, changed, cases in variants:
        failures, _, _ = build_run(label, changed, 0, cases)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failures)})
    local = modules('refusals', original)
    for name, expression, code in [
        ('unchecked-stamp', '(nodeTag (rgnCheckedTy (mkEInt 0)))', 'AX3004'),
        ('missing-stamp-none', '(match (rgnCheckedTy (mkEInt 0)) ((Some ty) (nodeTag ty)))', 'AX3005'),
        ('unchecked-parameter-signature', '(rgnBindTypedParams (context 0) vecNew 0 1 nilNode)', 'AX3004'),
    ]:
        refused = work / (name + '.ax')
        template = fixture.read_text()
        begin = template.index('(:: context ')
        end = template.index('(:: parameterOrigin ', begin)
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
    (work / 'checked-type-option-report.json').write_text(json.dumps(report, indent=2) + '\n')


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
        with tempfile.TemporaryDirectory(prefix='axiom-checked-type-options-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
