#!/usr/bin/env python3
"""Exercise actual pending-register String ownership and compiler scope cleanup."""
import argparse
import os
from pathlib import Path
import re
import runpy
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).with_name('emitter-line-buffer.py')))
run_checked = SUPPORT['run_checked']
replace_once = SUPPORT['replace_once']
check_output = SUPPORT['check_output']
check_typed_slot = SUPPORT['check_typed_slot']
raw_setter = SUPPORT['raw_setter']

BRIDGES = r'''
; Private-copy-only forwarding probes; no production raw access is exported.
(pub :: probePending (-> CG Strings))
(pub fn (probePending cg) (cgPendingStrings cg))
(pub :: probePendingAt (-> CG Int String))
(pub fn (probePendingAt cg index) (vecGet (cgPendingStrings cg) index))
(pub :: probePendingPush (-> CG String Int))
(pub fn (probePendingPush cg value) (cgPendingPush cg value))
(pub :: probePendingTruncate (-> CG Int Int))
(pub fn (probePendingTruncate cg size) (cgPendingTruncate cg size))
(pub :: probePendingReset (-> CG CG))
(pub fn (probePendingReset cg) (cgPendingReset cg))
'''


def function(ir, name):
    found = re.search(r'^define [^\n]*@' + re.escape(name) + r'\([^\n]*\)[^\n]*\{\n(.*?)^\}', ir, re.M | re.S)
    if not found:
        raise RuntimeError(f'missing emitted function {name}')
    return found[1]


def check_ir(path):
    ir = path.read_text()
    push = function(ir, 'codegen$cgPendingPush')
    if not re.search(r'@Vec\$vecPush\([^\n]+, i64 1\)', push):
        raise RuntimeError('pending append did not retain its typed String')
    truncate = function(ir, 'codegen$cgPendingTruncate')
    pop = re.search(r'(%\S+) = call i64 @Vec\$vecPop\([^\n]+, i64 1\)', truncate)
    if not pop or f'call void @axiom_release(i64 {pop[1]})' not in truncate:
        raise RuntimeError('discarded pending pop did not retire its transferred String share')
    reset = function(ir, 'codegen$cgPendingReset')
    check_typed_slot(reset, 42)
    parked = []
    for name in ('emitLetAt', 'emitMatch', 'emitMatchTail'):
        body = function(ir, f'codegen${name}')
        birth = re.search(r'(%\S+) = call i64 @Str\$strDup\(', body)
        if not birth:
            raise RuntimeError(f'{name}: missing ordinary register String allocation')
        if f'call void @axiom_release(i64 {birth[1]})' not in body:
            parked.append(name)
        if '@codegen$cgPendingPush(' not in body or '@codegen$cgPendingTruncate(' not in body:
            raise RuntimeError(f'{name}: actual insertion/truncation path missing')
    # Other conservative callee aliases can still park these births. Report
    # that limit explicitly; never spend their ordinary shares in raw code.
    print('note existing emitter register births still parked: ' + ','.join(parked), flush=True)
    getter_calls = 0
    for match in re.finditer(r'^define [^\n]*@codegen\$[^\n]+\{\n(.*?)^\}', ir, re.M | re.S):
        body = match[1]
        for get in re.finditer(r'(%\S+) = call i64 @codegen\$cgPendingStrings\(', body):
            getter_calls += 1
            if f'call void @axiom_release(i64 {get[1]})' not in body:
                raise RuntimeError(f'pending getter {get[1]} lacks its ordinary release')
    # Ten production consumer calls and one retained test-only element view.
    # probePending forwards its owned result with a musttail call instead.
    if getter_calls != 11:
        raise RuntimeError(f'expected 11 owned pending getter calls in emitted helpers/consumers, got {getter_calls}')


def check(axiom, repo, work):
    source = repo / 'tests/selfhost/emitter-pending-strings.axp'
    fixture = work / source.with_suffix('.ax').name
    fixture.write_bytes(source.read_bytes())
    expected = source.with_suffix('.out').read_text().splitlines()
    if expected != [f'{i} true' for i in range(1, 46)]:
        raise RuntimeError('update the explicit 45-case assertion count')
    original = (repo / 'core/codegen.ax').read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(repo / 'stdlib'))

    run_checked([str(axiom), "--diagnostic-format=ai", "fmt", "--check", str(fixture)],
                env=env, stdout=work / "fixture.fmt.stdout", stderr=work / "fixture.fmt.stderr")

    def build_run(label, level, source, negative=()):
        modules = work / f'{label}-modules/core'
        modules.mkdir(parents=True, exist_ok=True)
        for path in (repo / 'core').iterdir():
            destination = modules / path.name
            if path.name == 'codegen.ax':
                destination.write_text(source + BRIDGES)
            elif not destination.exists():
                destination.symlink_to(path, target_is_directory=path.is_dir())
        local = dict(env, AXIOM_PATH=str(modules))
        binary = work / label
        run_checked([str(axiom), 'build', str(fixture), '--opt', str(level), '--alloc-poison',
                     '--emit-llvm', '--diagnostic-format=ai', '-o', str(binary)],
                    env=local, stdout=work / f'{label}.build.stdout', stderr=work / f'{label}.build.stderr')
        output = work / f'{label}.stdout'
        error = work / f'{label}.stderr'
        run_checked([str(binary)], env=local, stdout=output, stderr=error, timeout=30)
        failures = check_output(output, expected, required_failures=negative)
        growth = re.fullmatch(r'pending-soak-growth (-?\d+)\n', error.read_text())
        if growth is None:
            raise RuntimeError(f'{label}: missing ordinary pending String storage measurement')
        print(f'note {label}: ordinary pending String storage growth {growth[1]} bytes', flush=True)
        return failures, binary.with_suffix('.ll')

    for level in (0, 2):
        label = f'positive-O{level}'
        _, ir = build_run(label, level, original)
        if level == 0:
            check_ir(ir)
        print(f'ok   pending String ledger: 45 cases at -O{level} with allocation poisoning', flush=True)

    raw_truncate = replace_once(
        original,
        '    (let pending (cgPendingStrings cg))\n    (while (> (vecLen pending) size)\n      {\n        (let retired (vecPop pending))\n        0\n      })\n',
        '    (memSetWord (memGetWord (as cg Int) 42) 0 size)\n', 'raw length truncation')
    raw_schema = replace_once(
        raw_truncate, '(vecPush (cgPendingStrings cg) value)',
        '(vecPush (as (cgPendingStrings cg) Ints) (as value Int))', 'erased pending String store')
    raw_schema = replace_once(
        raw_schema, '(:: cgPendingPush (-> CG String Int))\n',
        '(:: cgPendingPush (-> CG String Int))\n;@axiom:effect(unsafe)\n',
        'private raw-schema boundary claim')
    reset = raw_setter(original, 'cgPendingReset', 'pendingOwned', 42, 'vecNew')
    for label, source, negative in [
        ('raw-schema', raw_schema, (2, 3, 8, 11, 22, 33)),
        ('raw-truncate', raw_truncate, (5, 8, 12, 14, 18, 23, 24, 33)),
        ('reset-leak', reset, (26, 28, 30)),
    ]:
        failures, _ = build_run(label, 0, source, negative)
        print(f'ok   negative probe {label}: cases {",".join(map(str, sorted(failures)))} fail', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    if args.work:
        work = args.work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), repo, work)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-pending-strings-') as directory:
            check(args.axiom.resolve(), repo, Path(directory))


if __name__ == '__main__':
    main()
