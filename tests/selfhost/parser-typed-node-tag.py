#!/usr/bin/env python3
"""Check typed scalar tag reads, packed-layout compatibility and owner retirement."""
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
EXPECTED = [f'{i} true' for i in range(1, 35)]


def check(compiler, root, work):
    sources = {name: (root / 'core' / f'{name}.ax').read_text() for name in ('core', 'parser')}
    fixture = (root / 'tests/selfhost/parser-typed-node-tag.axp').read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {
        'builder': str(compiler), 'builder_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
        'source_sha256': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in sources.items()},
        'fixture_sha256': hashlib.sha256(fixture.encode()).hexdigest(),
        'configurations': [], 'counterexamples': [], 'refusals': [],
        'invariants': [
            'Both the public core accessor and parser wrapper map a nil AST handle to scalar zero without a field load.',
            'The tag is the declared Int field at packed slot zero, including zero, negative and maximum signed Int values.',
            'Reading the scalar tag through owned Options and records does not leave an extra AST share after their retirement.',
            'Other packed fields, annotation packet bytes and the child reference map keep their existing representation.',
        ],
        'known_limits': [
            'Host O0/O2 native execution with allocation poisoning is bounded evidence, not global memory soundness.',
            'The AST payload slots and other raw readers remain separate migration boundaries.',
            'No ownership inference, lifetime traversal, fixpoint or enforcement algorithm is inspected or changed.',
            'No held M5 contents are read or validated.',
        ],
    }

    def modules(label, changes):
        folder = work / (label + '-modules/core')
        folder.mkdir(parents=True)
        for path in (root / 'core').iterdir():
            output = folder / path.name
            if path.stem in changes:
                output.write_text(changes[path.stem])
            else:
                output.symlink_to(path, target_is_directory=path.is_dir())
        return dict(env, AXIOM_PATH=str(folder))

    def build_run(label, level, local, source=fixture, failures=()):
        program = work / (label + '.ax')
        program.write_text(source)
        binary = work / label
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(program), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '.build.stdout'), stderr=work / (label + '.build.stderr'))
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        return check_output(output, EXPECTED, required_failures=failures)

    local = modules('positive', sources)
    packet_source = root / 'tests/tools/axtag-carrier-packets.axp'
    golden = (root / 'tests/tools/axtag-carrier-packets.golden').read_bytes()
    for level in (0, 2):
        build_run(f'positive-O{level}', level, local)
        report['configurations'].append({'optimization': level, 'allocation_poisoning': True, 'cases': 34})
        print(f'ok   typed AST tag: 34 cases O{level} poison', flush=True)
        binary = work / f'packets-O{level}'
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(packet_source), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / f'packets-O{level}.build.stdout', stderr=work / f'packets-O{level}.build.stderr')
        result = subprocess.run([str(binary)], env=local, capture_output=True, timeout=30)
        if result.returncode or result.stderr or result.stdout != golden:
            raise AssertionError(('annotation wire bytes changed', level, result))
        report['configurations'][-1]['wire_bytes'] = sum(len(line) // 2 for line in golden.splitlines())
        print(f'ok   existing annotation packets O{level}: exact 1456 bytes', flush=True)

    raw_reader = replace_once(sources['parser'],
                              '(pub fn (nodeTag n)\n  (if (nodeSame n nilNode)\n    0\n    (astNodeTag n)))',
                              '(pub fn (nodeTag n)\n  (nodeWord n 0))', 'raw tag reader')
    wrong_slot = replace_once(sources['core'], '    node.tag))', '    node.a))', 'wrong scalar slot')
    wrong_nil = replace_once(sources['core'], '(if (addrEq (addrOf node) (addrOf 0))\n    0\n    node.tag)',
                             '(if (addrEq (addrOf node) (addrOf 0))\n    1\n    node.tag)', 'public nil guard result')
    lost_owner = replace_once(fixture, '(let box (Box :value (Some value)))',
                              '(let box (Box :value (Some value)))\n    (memMarkLeaf (as box Int))',
                              'boxed option child map')
    for label, changes, program, failures in [
        ('raw-word-reader', {'parser': raw_reader}, fixture, {10, 12, 16, 20, 32}),
        ('wrong-tag-slot', {'core': wrong_slot}, fixture, {6, 7, 25, 26, 27, 28}),
        ('public-nil-changed', {'core': wrong_nil}, fixture, {2}),
        ('lost-box-child-map', {}, lost_owner, {10, 16, 32}),
    ]:
        failed = build_run(label, 0, modules(label, {**sources, **changes}), program, failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: cases {sorted(failed)} fail', flush=True)

    for label, source, code in [
        ('integer-as-ast', '(astNodeTag 0)', 'AX3004'),
        ('string-as-ast', '(nodeTag "node")', 'AX3004'),
        ('missing-optional-branch', '(match (Some (mkEInt 1)) ((Some child) (nodeTag child)))', 'AX3005'),
    ]:
        program = work / (label + '.ax')
        program.write_text('(import core)\n(import parser)\n(:: main Int)\n(fn (main) ' + source + ')\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(program)],
                                env=local, capture_output=True, text=True, timeout=180)
        (work / (label + '.stderr')).write_text(result.stderr)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or f'E {code} ' not in errors[0]:
            raise AssertionError((label, result))
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'typed-node-tag-report.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    root = Path(__file__).resolve().parents[2]
    if args.work:
        args.work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), root, args.work.resolve())
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-typed-node-tag-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
