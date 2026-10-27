#!/usr/bin/env python3
"""Check typed String-vector queries and their positional/evidence consumers."""
import argparse
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile


def check(compiler, root, work, modules):
    source = {name: (root / 'core' / (name + '.ax')).read_text()
              for name in ('core', 'symbols', 'codegen', 'typecheck', 'expand')}
    for name, text in source.items():
        assert (modules / (name + '.ax')).read_text() == text, (name, 'stale dependency source')
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'), AXIOM_PATH=str(modules))
    expected = ''.join(f'{index} true\n' for index in range(1, 54))
    report = {'builder': compiler, 'builder_sha256': hashlib.sha256(Path(compiler).read_bytes()).hexdigest(),
              'sources': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in source.items()},
              'lsp_sha256': hashlib.sha256((modules / 'lsp.ax').read_bytes()).hexdigest(),
              'configurations': [], 'controls': [], 'refusals': [],
              'limits': ['Focused host O0/O2 native runs with allocation poisoning; GitHub owns full target/suite validation.',
                         'Membership stays allocation-free; successful optional index queries construct Some and report allocation truthfully.',
                         'Evidence bit indexes keep None separate from bit0; existing numeric evidence/retain-class lattice encodings remain values.',
                         'Dynamic name shares are tested while their AST owner stays live, avoiding a claim about the separate raw AST allocation/retirement boundary.',
                         'fieldRetainCode -1 is an existing no-retain class, and evWalkVar negative words are evidence-lattice states; neither forwards an absent index.',
                         'No lifetime/region algorithms or held M5 work are inspected or changed; no global memory/completion claim.']}

    def invoke(arguments, label, local=env, timeout=240):
        ran = subprocess.run(arguments, cwd=root, env=local, capture_output=True, text=True, timeout=timeout)
        (work / (label + '.out')).write_text(ran.stdout)
        (work / (label + '.err')).write_text(ran.stderr)
        return ran

    def build(label, level, local=env):
        binary = work / label
        ran = invoke([compiler, '--diagnostic-format=ai', 'build',
                      str(root / 'tests/tools/string-vector-option-queries.axp'),
                      '--opt', level, '--alloc-poison', '-o', str(binary)], label + '-build', local)
        assert ran.returncode == 0, (label, ran.stdout, ran.stderr)
        return binary

    for opt in ('0', '2'):
        binary = build('queries-O' + opt, opt)
        ran = invoke([str(binary)], binary.name + '-run', timeout=60)
        assert ran.returncode == 0 and not ran.stderr and ran.stdout == expected, (opt, ran.returncode, ran.stdout, ran.stderr)
        report['configurations'].append({'opt': opt, 'allocation_poisoning': True, 'outcomes': 53, 'status': 'passed'})
        print(f'ok   typed String-vector queries: 53 index/membership/join/evidence/rename/field/owner outcomes O{opt} poison', flush=True)

    first = '(set found (Some index))'
    last = '((Some previous) ())'
    member = '(for name in xs\n      (if (strEq name n)\n        (set found 1)))'
    comma = '(strBuilderPush s ",")'
    missing = '(expNamedBad env (nodeSpan callee) (concat "missing struct field `" (concat name "`")))'
    for module, seam in (('core', first), ('core', last), ('core', member), ('symbols', comma), ('expand', missing)):
        assert source[module].count(seam) == 1, (module, 'enforcement seam changed', seam)
    controls = {
        'discard-index-zero': ('core', source['core'].replace(first, '(if (!= index 0) ' + first + ')'), {2, 6, 7, 29, 32}),
        'select-last-duplicate': ('core', source['core'].replace(last, '((Some previous) (if (strEq name n) ' + first + '))'), {7, 8}),
        'discard-first-membership': ('core', source['core'].replace(member,
            '(for (name index) in xs (if (&& (> index 0) (strEq name n)) (set found 1)))'), {11, 13}),
        'discard-join-separator': ('symbols', source['symbols'].replace(comma, '()'), {16, 17, 18, 21}),
        'discard-missing-field-diagnostic': ('expand', source['expand'].replace(missing, '(mkEInt 0)'), {44, 45}),
        'extra-collector-child-share': ('codegen', source['codegen'].replace(
            '              (vecPush acc (nodeAName t))\n              0',
            '              (__retainref (nodeAName t))\n              (vecPush acc (nodeAName t))\n              0'), {50, 51, 52, 53}),
    }
    assert source['codegen'].count('              (vecPush acc (nodeAName t))\n              0') == 1
    for name, (module, text, required) in controls.items():
        altered = work / (name + '-modules'); altered.mkdir(exist_ok=True)
        (altered / (module + '.ax')).write_text(text)
        local = dict(env, AXIOM_PATH=os.pathsep.join((str(altered), str(modules))))
        binary = build(name, '0', local)
        ran = invoke([str(binary)], name + '-run', local, 60)
        assert ran.returncode == 0 and not ran.stderr, (name, ran.returncode, ran.stderr)
        failed = {int(line.split()[0]) for line in ran.stdout.splitlines() if line.endswith(' false')}
        assert required <= failed, (name, failed, required)
        report['controls'].append({'name': name, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {name}: cases {sorted(failed)} fail', flush=True)

    invalid = {
        'erased-membership-elements': ('(:: bad (-> Ints Int)) (fn (bad values) (strVecHas values "a"))', 'AX3004'),
        'erased-index-result': ('(:: bad (-> Names Int)) (fn (bad values) (strVecIdx values "a"))', 'AX3004'),
        'missing-index-none': ('(:: bad (-> Names Int)) (fn (bad values) (match (strVecIdx values "a") ((Some index) index)))', 'AX3005'),
        'erased-join-elements': ('(:: bad (-> Ints String)) (fn (bad values) (saJoinComma values))', 'AX3004'),
        'erased-variable-collector': ('(:: bad (-> ASTNode Ints Int)) (fn (bad ty values) (cgSigVarsInto ty values))', 'AX3004'),
        'erased-evidence-bit': ('(:: bad (-> CG Int)) (fn (bad cg) (curSigVarBit cg "a"))', 'AX3004'),
        'missing-evidence-none': ('(:: bad (-> CG Int)) (fn (bad cg) (match (curParamEvBit cg 0) ((Some bit) bit)))', 'AX3005'),
        'false-index-no-alloc': ('(:: bad (-> Names (Option Int)))\n;@axiom:restrict(no-alloc)\n(fn (bad values) (strVecIdx values "a"))', 'AX3049'),
    }
    for name, (declaration, code) in invalid.items():
        path = work / (name + '.ax')
        path.write_text('(import core) (import parser) (import codegen) (import symbols)\n' + declaration + '\n(:: main Int) (fn (main) 0)\n')
        ran = invoke([compiler, '--diagnostic-format=ai', 'check', str(path)], name)
        errors = [line for line in ran.stderr.splitlines() if line.startswith('E ')]
        assert ran.returncode == 1 and len(errors) == 1 and f'E {code} ' in errors[0], (name, ran.stdout, ran.stderr)
        report['refusals'].append({'name': name, 'code': code})
        print(f'ok   refusal {name}: {code}', flush=True)
    (work / 'string-vector-report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('compiler'); parser.add_argument('--work', type=Path)
    parser.add_argument('--dependency-core', type=Path)
    args = parser.parse_args(); root = Path(__file__).resolve().parents[2]
    compiler = str(Path(args.compiler).resolve()); modules = (args.dependency_core or root / 'core').resolve()
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True); check(compiler, root, args.work.resolve(), modules)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-string-vectors-') as directory:
            check(compiler, root, Path(directory), modules)


if __name__ == '__main__':
    main()
