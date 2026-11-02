#!/usr/bin/env python3
"""Check optional lexer/parser scan results and their actual refusal consumers."""
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
EXPECTED = [f'{index} true' for index in range(1, 38)]


def check(compiler, root, work):
    sources = {name: (root / 'core' / f'{name}.ax').read_text() for name in ('lexer', 'parser')}
    fixture = (root / 'tests/selfhost/parser-scan-options.axp').read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    report = {'compiler': str(compiler), 'compiler_sha256': hashlib.sha256(compiler.read_bytes()).hexdigest(),
              'source_sha256': {name: hashlib.sha256(text.encode()).hexdigest() for name, text in sources.items()},
              'configurations': [], 'counterexamples': [], 'refusals': [],
              'invariants': ['Some zero is the first position; None never reaches indexing.',
                             'Invalid escape positions, two-byte error spans and first-error ordering remain exact.',
                             'Nesting at the limit is accepted by the guard; the first opener beyond it is refused before recursive parsing.',
                             'Stray closing delimiters cannot cancel later nesting; strings/comments are not delimiters.',
                             'Private external-name/field scans preserve their optional result without an extra wrapper allocation.'],
              'limits': ['Native host O0/O2 with allocation poisoning; this does not establish global memory soundness.',
                         'The invalid-escape helper allocates only its Some error position; its former no-alloc claim is removed truthfully.',
                         'No held M5 code or lifetime/escape/fixpoint algorithm is inspected or changed.']}

    def modules(label, changes):
        folder = work / (label + '-modules/core')
        folder.mkdir(parents=True)
        for path in (root / 'core').iterdir():
            if path.stem in changes:
                (folder / path.name).write_text(changes[path.stem])
            else:
                (folder / path.name).symlink_to(path, target_is_directory=path.is_dir())
        return dict(env, AXIOM_PATH=str(folder))

    def native(label, level, local, source, expected=None, failures=()):
        program, binary = work / (label + '.ax'), work / label
        program.write_text(source)
        run_checked([str(compiler), '--diagnostic-format=ai', 'build', str(program), '--opt', str(level),
                     '--alloc-poison', '-o', str(binary)], env=local,
                    stdout=work / (label + '.build.stdout'), stderr=work / (label + '.build.stderr'))
        output = work / (label + '.stdout')
        run_checked([str(binary)], env=local, stdout=output, stderr=work / (label + '.stderr'), timeout=30)
        if expected is not None:
            if output.read_text() != expected:
                raise AssertionError((label, 'diagnostic/editor output changed', output.read_text()))
            return output.read_bytes()
        return check_output(output, EXPECTED, required_failures=failures)

    local = modules('positive', sources)
    old_result = runpy.run_path(str(root / 'tests/selfhost/compiler-parse-result-owners.py'))['BASELINE']
    diagnostics = (root / 'tests/selfhost/compiler-parse-result-diagnostics.axp').read_text()
    for level in (0, 2):
        native(f'positive-O{level}', level, local, fixture)
        wire = native(f'diagnostics-O{level}', level, local, diagnostics, expected=old_result)
        report['configurations'].append({'optimization': level, 'allocation_poison': True, 'cases': 37,
                                         'diagnostic_bytes': len(wire), 'diagnostic_sha256': hashlib.sha256(wire).hexdigest()})
        print(f'ok   optional parser scans: 37 outcomes and exact {len(wire)} diagnostic/editor bytes O{level} poison', flush=True)

    def function_change(module, name, old, new):
        text = sources[module]
        starts = [text.find(prefix + name + ' ') for prefix in ('(fn (', '(pub fn (')]
        start = next(pos for pos in starts if pos >= 0)
        end = text.index('\n\n', start)
        body = text[start:end]
        return text[:start] + replace_once(body, old, new, name) + text[end:]

    controls = [
        ('invalid-escape-shifted', 'lexer', 'badEscapeIn', '(set found (Some i))', '(set found (Some (+ i 1)))', {29, 31, 33, 34}),
        ('at-limit-refused', 'parser', 'nestOverflowTok', '(if (> d limit)', '(if (>= d limit)', {15, 18, 22, 24}),
        ('missing-library-byte-lost', 'parser', 'externLibBadAtFrom', '(Some i)', 'None', {3, 4, 5, 6, 7}),
        ('field-zero-shifted', 'parser', 'namedFieldIndexFrom', '(Some i)', '(Some (+ i 1))', {9, 10}),
    ]
    for label, module, name, old, new, failures in controls:
        changed = function_change(module, name, old, new)
        failed = native(label, 0, modules(label, dict(sources, **{module: changed})), fixture, failures=failures)
        report['counterexamples'].append({'name': label, 'failed_cases': sorted(failed)})
        print(f'ok   counterexample {label}: cases {sorted(failed)} fail', flush=True)

    refusals = [
        ('raw-escape-position', '(:: bad Int) (fn (bad) (badEscapeIn "" 0 0))', 'AX3004'),
        ('raw-depth-position', '(:: bad Int) (fn (bad) (nestOverflowTok (lex "") 1))', 'AX3004'),
        ('missing-depth-none', '(:: bad Int) (fn (bad) (match (nestOverflowTok (lex "(") 0) ((Some n) n)))', 'AX3005'),
        ('missing-escape-some', '(:: bad Int) (fn (bad) (match (badEscapeIn "" 0 0) ((None) 0)))', 'AX3005'),
        ('present-index-no-alloc', '(:: bad (Option Int))\n;@axiom:restrict(no-alloc)\n(fn (bad) (badEscapeIn "" 0 0))', 'AX3049'),
    ]
    for label, declaration, code in refusals:
        program = work / (label + '.ax')
        program.write_text('(import core)\n(import lexer)\n(import parser)\n' + declaration + '\n(:: main Int) (fn (main) 0)\n')
        result = subprocess.run([str(compiler), '--diagnostic-format=ai', 'check', str(program)], env=local,
                                capture_output=True, text=True, timeout=60)
        errors = [line for line in result.stderr.splitlines() if line.startswith('E ')]
        if result.returncode != 1 or len(errors) != 1 or not errors[0].startswith('E ' + code + ' '):
            raise AssertionError((label, result.returncode, result.stdout, result.stderr))
        report['refusals'].append({'name': label, 'code': code})
        print(f'ok   refusal {label}: {code}', flush=True)
    (work / 'parser-scan-options-report.json').write_text(json.dumps(report, indent=2) + '\n')


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
        with tempfile.TemporaryDirectory(prefix='axiom-parser-scan-') as directory:
            check(args.axiom.resolve(), root, Path(directory))


if __name__ == '__main__':
    main()
