#!/usr/bin/env python3
"""Check optional type witnesses and owned pending-evidence alternatives."""
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


def golden_helpers(root):
    """Run the checker and AXDL renderer directly, preserving real source spans."""
    cases = ['426-undefined-sig-type', '1103-removed-builtin-types',
             '1108-star-glued-type', '1420-generic-alias-arity', '1424-generic-alias-ambiguity']
    text = '''
(:: expectParsed (-> (PResult a) a))
(fn (expectParsed result)
  (match result
    ((ParseSuccess value position) value)
    ((ParseFailed error) __indexTrap)))

(:: probeParse (-> String Nodes))
(fn (probeParse text) (expectParsed (parseModuleWith (lex text) (scanAxtags text))))
(:: probeGoldenSingle (-> String String String))
(fn (probeGoldenSingle file text) {
  (let declarations (probeParse text))
  (for declaration in declarations (writeNodeWord declaration 5 1))
  (let units (vecPush vecNew (CUnit2 :file file :src text :name (Some "") :imports vecNew :library false)))
  (let checker (checkModuleTcTyped declarations declarations units))
  (renderDiagsUnits checker.out units)
})
(:: probeModule (-> Nodes String ()))
(fn (probeModule declarations name) (for declaration in declarations (writeNodeText declaration 8 name)))
'''
    ambiguity = (root / 'tests/diagnostics/1424-generic-alias-ambiguity.ax').read_text()
    module_a = (root / 'tests/diagnostics/mods/AliasAmbA.ax').read_text()
    module_b = (root / 'tests/diagnostics/mods/AliasAmbB.ax').read_text()
    quote = lambda value: json.dumps(value, ensure_ascii=False)
    text += f'''
(:: probeGoldenAmbiguous String)
(fn (probeGoldenAmbiguous) {{
  (let entrySource {quote(ambiguity)})
  (let sourceA {quote(module_a)})
  (let sourceB {quote(module_b)})
  (let entry (probeParse entrySource))
  (for declaration in entry (writeNodeWord declaration 5 1))
  (let a (probeParse sourceA))
  (let b (probeParse sourceB))
  (probeModule a "AliasAmbA")
  (probeModule b "AliasAmbB")
  (let all vecNew)
  (for d in a (vecPush all d))
  (for d in b (vecPush all d))
  (for d in entry (vecPush all d))
  (let units (vecPush vecNew (CUnit2 :file "1424-generic-alias-ambiguity.ax" :src entrySource :name (Some "") :imports (vecPush (vecPush vecNew (vecGet entry 0)) (vecGet entry 1)) :library false)))
  (vecPush units (CUnit2 :file "AliasAmbA.ax" :src sourceA :name (Some "AliasAmbA") :imports vecNew :library false))
  (vecPush units (CUnit2 :file "AliasAmbB.ax" :src sourceB :name (Some "AliasAmbB") :imports vecNew :library false))
  (let checker (checkModuleTcTyped entry all units))
  (renderDiagsUnits checker.out units)
}})
(:: probeGolden (-> String String))
(fn (probeGolden name)
'''
    for case in cases[:-1]:
        source = (root / 'tests/diagnostics' / (case + '.ax')).read_text()
        text += f'  (if (strEq name "{case}") (probeGoldenSingle "{case}.ax" {quote(source)})\n'
    text += '    probeGoldenAmbiguous' + ')' * len(cases) + '\n'
    return text, cases


def check(compiler, root, work):
    original = (root / 'core/typecheck.ax').read_text()
    environment = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    source = work / 'evidence-options.ax'
    fixture = (root / 'tests/selfhost/typecheck-evidence-options.axp').read_text()
    helpers, goldens = golden_helpers(root)
    fixture = replace_once(fixture, '(import IO)', '(import IO)\n(import Sys)', 'diagnostic modes')
    fixture = replace_once(fixture, '    (typeSearchChecks)\n    (evidenceChecks)\n    0',
        '    (if (> sysArgc 1) { (writeStr stdout (probeGolden (sysArg 1))) 0 }\n'
        '      { (typeSearchChecks) (evidenceChecks) 0 })', 'diagnostic entry point')
    source.write_text(fixture + helpers)
    run_checked([str(compiler), '--diagnostic-format=ai', 'fmt', str(source)], env=environment,
                stdout=work / 'fmt.stdout', stderr=work / 'fmt.stderr')
    expected = [f'{index} true' for index in range(1, 43)]
    report = {'source_sha256': hashlib.sha256(original.encode()).hexdigest(),
              'builder': str(compiler), 'configurations': [], 'counterexamples': [],
              'refusals': [], 'goldens': [],
              'invariants': [
                  {'invariant': 'Type-name searches distinguish None from Some empty and keep the first witness.',
                   'enforcement': 'Option String and ordered head/argument/arrow/tuple/pointer walks; cases1-26.',
                   'counterexample': 'lost-empty-name and last-arrow-witness'},
                  {'invariant': 'Pending evidence owns only the live AST variant and its enclosing signature context.',
                   'enforcement': 'EvWitness sum and exhaustive replay; cases27-39.',
                   'counterexample': 'lost-pending-context and omitted-stamp-replay'},
                  {'invariant': 'Pending records retain and retire their owned signature-name snapshot.',
                   'enforcement': 'Typed EvPend vector and typed Names field; cases40-42.',
                   'counterexample': 'unmapped-pending-records'},
                  {'invariant': 'Unknown and ambiguous type diagnostics retain their spelling, ordering and poison fallback.',
                   'enforcement': 'Byte comparisons against five existing AXDL goldens.',
                   'counterexample': 'last-arrow-witness'},
              ],
              'known_limits': ['O0/O2 host execution with allocation poisoning; no Windows runtime claim.',
                               'An empty type name is tested through the public typed AST helper, not as valid source syntax.',
                               'AST nodes remain owned by the existing parser arena; this test does not redesign their lifetime.',
                               'Region traversal, lifetime enforcement and held M5 work are excluded.',
                               'This bounded evidence does not establish global soundness, Rust parity or certification.']}

    def modules(label, contents):
        directory = work / (label + '-modules/core')
        directory.mkdir(parents=True)
        for path in (root / 'core').iterdir():
            destination = directory / path.name
            if path.name == 'typecheck.ax':
                destination.write_text(contents)
            else:
                destination.symlink_to(path, target_is_directory=path.is_dir())
        return dict(environment, AXIOM_PATH=str(directory))

    def build_run(label, contents, level, failures=()):
        local = modules(label, contents)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(source),
                     '--opt', str(level), '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '.build.stdout'), stderr=work / (label + '.build.stderr'))
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        observed = check_output(output, expected, required_failures=failures)
        print('ok   ' + label + ': ' + str(sorted(observed)), flush=True)
        return observed, binary, local

    for level in (0, 2):
        _, binary, local = build_run('positive-O' + str(level), original, level)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True,
                                         'cases': 42, 'status': 'passed'})
        state = work / ('private-state-O' + str(level))
        run_checked([str(compiler), '--diagnostic-format=ai', 'build',
                     str(root / 'tests/selfhost/typecheck-private-state.ax'),
                     '--opt', str(level), '--alloc-poison', '-o', str(state)], env=local,
                    stdout=work / (state.name + '.build.stdout'), stderr=work / (state.name + '.build.stderr'))
        state_result = subprocess.run([str(state)], env=local, capture_output=True, text=True)
        if state_result.returncode != 42 or state_result.stdout or state_result.stderr:
            raise RuntimeError(('private state adapter', state_result))
        report['configurations'][-1]['private_state_exit'] = 42
        for case in goldens:
            output = work / (case + f'.O{level}.axdl')
            run_checked([str(binary), case], env=local, stdout=output,
                        stderr=work / (case + f'.O{level}.stderr'), timeout=30)
            wanted = (root / 'tests/diagnostics' / (case + '.axdl')).read_bytes()
            if output.read_bytes() != wanted:
                raise RuntimeError(('golden changed', case, output))
            report['goldens'].append({'name': case, 'optimization': level, 'status': 'passed'})
            print('ok   AXDL ' + case + ' O' + str(level), flush=True)
    empty = replace_once(original, '(Some (nodeAName t))\n        (tyUnknownConVec',
                         '(if (strEq (nodeAName t) "") None (Some (nodeAName t)))\n        (tyUnknownConVec', 'empty remains present')
    last = original
    for name in ['tyUnknownCon', 'tyAmbigCon']:
        last = replace_once(last, '(Some name)\n            (' + name + ' tc (nodeBChild t))',
                             '(' + name + ' tc (nodeBChild t))\n            (' + name + ' tc (nodeBChild t))', 'first arrow witness')
    context = original.replace('(EvStampWitness st pt at (tcCurSigVars tc))', '(EvStampWitness st pt at vecNew)').replace('(EvApplicationWitness node at (tcCurSigVars tc))', '(EvApplicationWitness node at vecNew)')
    if context == original:
        raise RuntimeError('pending context mutation anchor missing')
    leaf = replace_once(original, '(vecPush (evPendingOf tc) (EvApplicationWitness node at (tcCurSigVars tc)))',
                        '{ (let pending (EvApplicationWitness node at (tcCurSigVars tc))) '
                        '(memMarkLeaf (as pending Int)) (vecPush (evPendingOf tc) pending) }', 'pending context reference map')
    stamp = replace_once(original, '(evWalk tc st pt at 0 1)',
                         '0', 'stamp variant replay')
    for label, changed, cases in [('lost-empty-name', empty, (4,)),
                                  ('last-arrow-witness', last, (7, 20)),
                                  ('lost-pending-context', context, (30, 40)),
                                  ('unmapped-pending-records', leaf, (41,)),
                                  ('omitted-stamp-replay', stamp, (34,))]:
        failures, _, _ = build_run(label, changed, 0, cases)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failures)})
    for name, expression, code, extra in [
        ('unchecked-type-name', '(strLen (tyUnknownCon (tcNew vecNew vecNew vecNew) mkIntTy))', 'AX3004', ''),
        ('missing-name-none', '(match (tyAmbigCon (tcNew vecNew vecNew vecNew) mkIntTy) ((Some name) (strLen name)))', 'AX3005', ''),
        ('erased-pending-stamp', '(evNotePending (tcNew vecNew vecNew vecNew) 0 nilNode mkIntTy)', 'AX3004', ''),
        ('missing-pending-variant', '0', 'AX3005', '\n(:: incompletePending (-> EvWitness Int))\n(fn (incompletePending witness) (match witness ((EvStampWitness _ _ _ _) 0)))\n'),
    ]:
        local = modules(name, original + extra)
        refused = work / (name + '.ax')
        refused.write_text('(import core)\n(import parser)\n(import typecheck)\n(import Vec)\n(import Str)\n'
                           '(:: main Int)\n(fn (main) { ' + expression + ' 0 })\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(refused)],
                                env=local, capture_output=True, text=True)
        (work / (name + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or f'E {code} ' not in errors[0]:
            raise RuntimeError((name, result))
        report['refusals'].append({'name': name, 'diagnostic': code, 'status': 'passed'})
        print('ok   ' + name + ': ' + code, flush=True)
    (work / 'evidence-option-report.json').write_text(json.dumps(report, indent=2) + '\n')


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
        with tempfile.TemporaryDirectory(prefix='axiom-evidence-options-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
