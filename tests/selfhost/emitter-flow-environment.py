#!/usr/bin/env python3
"""Check owning flow environments, optional lookups, memo keys and unchanged IR."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import runpy
import subprocess
import sys
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).with_name('emitter-line-buffer.py')))
run_checked = SUPPORT['run_checked']
replace_once = SUPPORT['replace_once']
check_output = SUPPORT['check_output']
BRIDGE = '''
(pub :: probeMemoFlag (-> CG String ASTNode ASTNode Names FlowEnv (Option Int)))
(pub fn (probeMemoFlag cg name init body params env)
  (match (mutMemoFind cg.pairState.mutMemo name init body params env 0)
    ((Some entry) (Some entry.flag))
    ((None) None)))
(pub :: probeValueOwned (-> CG ASTNode FlowEnv Int))
(pub fn (probeValueOwned cg expression env) (valueOwnedRefIn cg expression env))
'''
CASES = [
    ('shadow', '(:: choose (-> Int Int))\n(fn (choose x) { (let y x) (let x 7) (+ x y) })\n(:: main Int)\n(fn (main) (choose 35))\n', 42),
    ('scalar-pattern', '(data Pair (CPair Int Int))\n(:: sum (-> Pair Int))\n(fn (sum p) (match p ((CPair a b) (+ a b))))\n(:: main Int)\n(fn (main) (sum (CPair 20 22)))\n', 42),
    ('reference-pattern', '(data Box (BoxValue String))\n(:: unbox (-> Box String))\n(fn (unbox b) (match b ((BoxValue text) text)))\n(:: main Int)\n(fn (main) 0)\n', 0),
    ('mutable-alias', '(:: keep (-> Int Int))\n(fn (keep x) { (let mut y x) (set y x) y })\n(:: main Int)\n(fn (main) (keep 42))\n', 42),
    ('captured-local', '(:: make (-> Int (-> Int Int)))\n(fn (make x) (lambda (n) x))\n(:: main Int)\n(fn (main) { (let f (make 42)) (f 0) })\n', 42),
    ('pattern-shadow', '(:: choose (-> Int Int))\n(fn (choose x) (match (Some x) ((Some x) x) ((None) 0)))\n(:: main Int)\n(fn (main) (choose 42))\n', 42),
]


def function_change(source, name, before, after):
    start = source.index('(pub fn (' + name + ' ')
    end = source.index('\n\n', start)
    return source[:start] + replace_once(source[start:end], before, after, name) + source[end:]


def check(compiler, root, work, baseline_path=None):
    source = (root / 'core/codegen.ax').read_text()
    template = (root / 'tests/selfhost/emitter-flow-environment.axp').read_text()
    fixture = work / 'flow-environment.ax'
    fixture.write_text(template)
    expected = [f'{i} true' for i in range(1, 63)]
    environment = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {'source_sha256': hashlib.sha256(source.encode()).hexdigest(), 'builder': str(compiler),
              'configurations': [], 'counterexamples': [], 'refusals': [], 'same_ir': [],
              'reference': {'kind': 'parent-codegen' if baseline_path else 'cross-optimization', 'path': str(baseline_path) if baseline_path else None},
              'invariants': [
                  {'invariant': 'Lookup distinguishes None from every stored Int, including zero and negative values; later bindings shadow earlier ones.',
                   'enforcement': 'FlowBinding/FlowEnv and Option lookup, rows1-18,44-52.',
                   'counterexample': 'first-binding-wins, missing-as-zero and lost-zero'},
                  {'invariant': 'Environment copies and snapshots own immutable rows and their names until the last owner retires.',
                   'enforcement': 'Typed vector writes/copies, pop/clear, counts19-28,40-42.',
                   'counterexample': 'unmapped-binding-children and skipped-memo-retirement'},
                  {'invariant': 'Memo keys preserve ordered name identity and flag values, independently of binding-record identity; the first matching entry wins.',
                   'enforcement': 'Typed snapshots and name-identity/flag comparison, cases29-43,57-58.',
                   'counterexample': 'byte-equal-memo-key'},
                  {'invariant': 'Flow masks, captures, scalar pattern fields and valid emitted programs retain their prior meaning.',
                   'enforcement': 'Existing operations44-62 and six byte-identical IR/native-exit comparisons, using a parent emitter when --baseline-codegen is supplied.',
                   'counterexample': 'lost-zero and first-binding-wins'},
              ],
              'known_limits': ['Host O0/O2 execution with allocation poisoning and host LLVM verification; emitted six-program native exits run on POSIX, Windows checks IR but skips this cc link path.',
                               'The flow/fixpoint/enforcement algorithms are unchanged; only environment representation and missing-result contracts change.',
                               'Snapshots share immutable bindings but keep original String-address identity in memo keys.',
                               'Production masks are nonnegative bounded bit sets; the optional lookup itself preserves arbitrary Int payloads without sentinel collision.',
                               'Other nullable TypeEntry/FSig/AST and numeric-index protocols remain outside this increment.',
                               'No held M5 contents or lifetime algorithm is read, changed or validated; no global soundness, Rust parity or certification claim follows.']}
    run_checked([str(compiler), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)], env=environment,
                stdout=work / 'fmt.stdout', stderr=work / 'fmt.stderr')

    def modules(label, contents, bridge=True):
        directory = work / (label + '-modules/core')
        directory.mkdir(parents=True)
        for path in (root / 'core').iterdir():
            out = directory / path.name
            if path.name == 'codegen.ax':
                out.write_text(contents + (BRIDGE if bridge else ''))
            else:
                out.symlink_to(path, target_is_directory=path.is_dir())
        return dict(environment, AXIOM_PATH=str(directory))

    def build_run(label, contents, level, failures=()):
        local = modules(label, contents)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(fixture), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '.build.stdout'), stderr=work / (label + '.build.stderr'), timeout=240)
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        observed = check_output(output, expected, required_failures=failures)
        print(f'ok   {label}: {sorted(observed)}', flush=True)
        return binary, local, observed

    positives = []
    for level in (0, 2):
        binary, local, _ = build_run('positive-O' + str(level), source, level)
        positives.append((level, binary, local))
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True, 'cases': 62, 'status': 'passed'})

    baseline = baseline_path.read_text() if baseline_path else source
    report['reference']['sha256'] = hashlib.sha256(baseline.encode()).hexdigest()
    driver = work / 'baseline-driver.ax'
    imports = template[:template.index('(:: say ')]
    emitter = template[template.index('(:: emitSource '):template.index('(:: checks ')]
    driver.write_text(imports + emitter + '''(:: main Int)
;@axiom:effect(io)
(fn (main) { (writeStr stdout (emitSource (unwrapOr (readFile (sysArg 1)) ""))) 0 })
''')
    if baseline_path:
        base_env = modules('baseline', baseline, False)
        base_binary = work / 'baseline'
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(driver), '--opt', '0', '--alloc-poison', '-o', str(base_binary)],
                    env=base_env, stdout=work / 'baseline.build.stdout', stderr=work / 'baseline.build.stderr', timeout=240)
    else:
        _, base_binary, base_env = positives[0]
    for name, program, status in CASES:
        path = work / (name + '.ax')
        path.write_text(program)
        before = subprocess.run([str(base_binary), str(path)], env=base_env, capture_output=True, text=True, timeout=60)
        if before.returncode or before.stderr or not before.stdout.startswith('target triple = '):
            raise RuntimeError(('baseline emission', name, before))
        for level, binary, local in positives:
            after = subprocess.run([str(binary), str(path)], env=local, capture_output=True, text=True, timeout=60)
            if after.returncode or after.stderr or after.stdout != before.stdout:
                raise RuntimeError(('IR changed', name, level, after.returncode, after.stderr))
            report['same_ir'].append({'case': name, 'optimization': level, 'sha256': hashlib.sha256(after.stdout.encode()).hexdigest(), 'status': 'passed', 'native_execution': sys.platform != 'win32'})
        ir = work / (name + '.ll')
        ir.write_text(before.stdout)
        run_checked(['opt', '-passes=verify', '-disable-output', str(ir)], env=environment,
                    stdout=work / (name + '.verify.stdout'), stderr=work / (name + '.verify.stderr'))
        if sys.platform != 'win32':
            obj = work / (name + '.o')
            native = work / (name + '.native')
            run_checked(['llc', '-filetype=obj', '-relocation-model=pic', str(ir), '-o', str(obj)], env=environment,
                        stdout=work / (name + '.llc.stdout'), stderr=work / (name + '.llc.stderr'))
            run_checked(['cc', str(obj), '-o', str(native)], env=environment,
                        stdout=work / (name + '.link.stdout'), stderr=work / (name + '.link.stderr'))
            result = subprocess.run([str(native)], env=environment, capture_output=True, text=True, timeout=30)
            if result.returncode != status or result.stdout or result.stderr:
                raise RuntimeError(('native result changed', name, status, result))
        detail = f'native exit{status}' if sys.platform != 'win32' else 'native link skipped on Windows'
        print(f'ok   unchanged IR: {name}; {detail}', flush=True)

    first = replace_once(source, '(envFlagFrom env name (- (vecLen env) 1))', '(if (== (vecLen env) 0) None (envFlagFrom env name 0))', 'innermost binding')
    missing = function_change(source, 'envFlagFrom', '    None\n', '    (Some 0)\n')
    zero = function_change(source, 'envFlagFrom', '(Some binding.flag)', '(if (== binding.flag 0) None (Some binding.flag))')
    owner = function_change(source, 'envWith', '(vecPush v (FlowBinding :name name :flag flag))',
                            '(let binding (FlowBinding :name name :flag flag))\n    (memMarkLeaf (as binding Int))\n    (vecPush v binding)')
    key = function_change(source, 'mutMemoEnvEq', '(addrEq (addrOf previous.name) (addrOf current.name))', '(strEq previous.name current.name)')
    retired = function_change(source, 'mutMemoOpen', '(vecClear (mutMemoEntries cg))', '(memSetWord (as (mutMemoEntries cg) Int) 0 0)')
    for label, changed, failures in [('first-binding-wins', first, (6, 12)), ('missing-as-zero', missing, (1, 8, 10)),
                                     ('lost-zero', zero, (2, 45)), ('unmapped-binding-children', owner, (23, 25, 27)),
                                     ('byte-equal-memo-key', key, (33,)), ('skipped-memo-retirement', retired, (42,))]:
        _, _, observed = build_run(label, changed, 0, failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(observed)})

    local = modules('refusals', source)
    for label, body, code in [
        ('raw-binding-row', '(envFlagOf (vecPush vecNew 42) "x") 0', 'AX3004'),
        ('raw-lookup-result', '(+ (envFlagOf vecNew "x") 1)', 'AX3004'),
        ('missing-lookup-none', '(match (envFlagOf vecNew "x") ((Some flag) flag))', 'AX3005'),
        ('missing-memo-none', '(let cg newCG) (let node (mkEInt 0)) (match (mutMemoFind cg.pairState.mutMemo "key" node node vecNew vecNew 0) ((Some row) 0))', 'AX3005'),
    ]:
        path = work / (label + '.ax')
        path.write_text('(import codegen)\n(import parser)\n(import Vec)\n(:: main Int)\n(fn (main) { ' + body + ' })\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(path)],
                                env=local, capture_output=True, text=True, timeout=60)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or f'E {code} ' not in errors[0]:
            raise RuntimeError((label, result))
        report['refusals'].append({'name': label, 'diagnostic': code, 'status': 'passed'})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'flow-environment-report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', required=True, type=Path)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--baseline-codegen', type=Path, help='optional prior codegen.ax for a historical byte comparison; otherwise compare O0/O2 output')
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), root, args.work.resolve(), args.baseline_codegen)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-flow-environment-') as directory:
            check(args.axiom.resolve(), root, Path(directory), args.baseline_codegen)


if __name__ == '__main__':
    main()
