#!/usr/bin/env python3
"""Check actual line-table metadata ownership, contents and scope cleanup."""
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

BRIDGES = r'''
; These forwarding probes exist only in the test's copied codegen module.
(pub :: probeMetadataScope Int)
(pub fn (probeMetadataScope)
  {
    (let marks vecNew)
    (pushLineMark marks (strDup "first") (strDup "@one") "; @@line modA 0")
    (pushLineMark marks (strDup "other") (strDup "@two") "; @@line modB 2")
    (pushLineMark marks (strDup "last") (strDup "@three") "; @@line modA 3")
    (let mods (collectMods marks 0 vecNew))
    (let rows vecNew)
    (let files vecNew)
    (let functions vecNew)
    (let labels vecNew)
    (let ix (srcLineIndexTyped "α\nz\n"))
    (resolveModMarks marks 0 "modA" "α\nz\n" "source.ax" ix rows files functions labels)
    (+ (vecLen rows) (vecLen mods))
  })
(pub :: probeMetadataValues Strings)
(pub fn (probeMetadataValues)
  {
    (let marks vecNew)
    (pushLineMark marks "first" "@one" "; @@line modA 0")
    (pushLineMark marks "other" "@two" "; @@line modB 2")
    (pushLineMark marks "last" "@three" "; @@line modA 3")
    (let mods (collectMods marks 0 vecNew))
    (let rows vecNew)
    (let files vecNew)
    (let functions vecNew)
    (let labels vecNew)
    (let ix (srcLineIndexTyped "α\nz\n"))
    (resolveModMarks marks 0 "modA" "α\nz\n" "source.ax" ix rows files functions labels)
    (let result vecNew)
    (vecPush result (vecGet mods 0))
    (vecPush result (vecGet mods 1))
    (vecPush result (vecGet labels 0))
    (vecPush result (vecGet functions 0))
    (vecPush result (vecGet labels 1))
    (vecPush result (vecGet functions 1))
    (vecPush result (vecGet files 0))
    (vecPush result (vecGet rows 0))
    (vecPush result (vecGet rows 1))
    result
  })
(pub :: probeMetadataOwnsRows Bool)
(pub fn (probeMetadataOwnsRows)
  {
    (let marks vecNew)
    (pushLineMark marks "block" "@owner" "; @@line modA 0")
    (let rows vecNew)
    (let files vecNew)
    (let functions vecNew)
    (let labels vecNew)
    (let ix (srcLineIndexTyped "ok"))
    (resolveModMarks marks 0 "modA" "ok" "source.ax" ix rows files functions labels)
    (&& (vecOwnsRefs marks)
      (&& (vecOwnsRefs rows)
        (&& (vecOwnsRefs files) (&& (vecOwnsRefs functions) (vecOwnsRefs labels)))))
  })
'''


def function(ir, name):
    found = re.search(r'^define [^\n]*@' + re.escape(name) + r'\([^\n]*\)[^\n]*\{\n(.*?)^\}', ir, re.M | re.S)
    if not found:
        raise RuntimeError(f'missing actual emitted function {name}')
    return found[1]


def check_ir(path):
    ir = path.read_text()
    marker = function(ir, 'codegen$pushLineMark')
    if not re.search(r'@Vec\$vecPush\([^\n]+, i64 1\)', marker):
        raise RuntimeError('marker vector did not retain its typed record')
    resolve = function(ir, 'codegen$resolveModMarks')
    stores = re.findall(r'@Vec\$vecPush\([^\n]+, i64 (\d+)\)', resolve)
    if stores != ['1', '1', '1']:
        raise RuntimeError(f'line rows/function/label stores lost their counted witnesses: {stores}')
    row = re.search(r'(%\S+) = call i64 @codegen\$lineRowStr\(', resolve)
    if not row or f'call void @axiom_release(i64 {row[1]})' not in resolve:
        raise RuntimeError('fresh line row birth did not retire after counted storage')
    scope = function(ir, 'codegen$probeMetadataScope')
    marks = re.search(r'(%\S+) = call i64 @Vec\$vecNew\(', scope)
    if not marks or f'call void @axiom_release(i64 {marks[1]})' not in scope:
        raise RuntimeError('marker registry birth remains parked after metadata scope')
    factory = function(ir, 'diag$srcLineIndexTyped')
    for name in re.findall(r'(%\S+) = call i64 @Vec\$vecNew\(', factory):
        if f'call void @axiom_release(i64 {name})' not in factory:
            raise RuntimeError('typed index did not retire its transferred vector birth')


def check(axiom, repo, source_root, work, controls_only=False):
    source = repo / 'tests/selfhost/emitter-line-metadata.axp'
    fixture = work / source.with_suffix('.ax').name
    fixture.write_bytes(source.read_bytes())
    expected = source.with_suffix('.out').read_text().splitlines()
    if expected != [f'{i} true' for i in range(1, 31)]:
        raise RuntimeError('update the explicit 30-case assertion count')
    original = (source_root / 'core/codegen.ax').read_text()
    env = dict(os.environ, AXIOM_STDLIB=str(source_root / 'stdlib'))

    run_checked([str(axiom), "--diagnostic-format=ai", "fmt", "--check", str(fixture)],
                env=env, stdout=work / "fixture.fmt.stdout", stderr=work / "fixture.fmt.stderr")

    def build_run(label, level, source, negative=()):
        modules = work / f'{label}-modules/core'
        modules.mkdir(parents=True, exist_ok=True)
        for path in (source_root / 'core').iterdir():
            destination = modules / path.name
            if path.name == 'codegen.ax':
                destination.write_text(source + BRIDGES)
            elif not destination.exists():
                destination.symlink_to(path, target_is_directory=path.is_dir())
        local = dict(env, AXIOM_PATH=str(modules))
        binary = work / label
        run_checked([str(axiom), 'build', str(fixture), '--opt', str(level), '--alloc-poison',
                     '--emit-llvm', '--diagnostic-format=ai', '-o', str(binary)],
                    env=local, stdout=work/f'{label}.build.stdout', stderr=work/f'{label}.build.stderr')
        output, error = work/f'{label}.stdout', work/f'{label}.stderr'
        run_checked([str(binary)], env=local, stdout=output, stderr=error, timeout=30)
        failed = check_output(output, expected, required_failures=negative)
        growth = re.fullmatch(r'metadata-growth (-?\d+) index-growth (-?\d+)\n', error.read_text())
        if not growth:
            raise RuntimeError(f'{label}: missing scoped allocation measurements')
        print(f'note {label}: metadata/index growth {growth[1]}/{growth[2]} bytes', flush=True)
        return failed, binary.with_suffix('.ll')

    for level in (() if controls_only else (0, 2)):
        label = f'positive-O{level}'
        _, ir = build_run(label, level, original)
        if level == 0:
            check_ir(ir)
        print(f'ok   line metadata: 30 cases at -O{level} with allocation poisoning', flush=True)

    erased = replace_once(original,
        '(vecPush rows (lineRowStr fi path (lineOfIx ix off) (colOfIx text ix off)))',
        '(vecPush (as rows Ints) (as (lineRowStr fi path (lineOfIx ix off) (colOfIx text ix off)) Int))',
        'line row storage erasure')
    # The private control really forges a vector view, so its declaration
    # must admit that operation before runtime assertions can measure it.
    erased = replace_once(erased,
        '(pub fn (resolveModMarks marks i modname text path ix rows files addrFns addrLbls)\n',
        ';@axiom:effect(unsafe)\n(pub fn (resolveModMarks marks i modname text path ix rows files addrFns addrLbls)\n',
        'private erased-storage unsafe declaration')
    failed, _ = build_run('raw-row-storage', 0, erased, (24, 25))
    print(f'ok   negative probe raw-row-storage: cases {",".join(map(str, sorted(failed)))} fail', flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--source-root', type=Path)
    parser.add_argument('--work', type=Path)
    parser.add_argument('--controls-only', action='store_true', help='resume just the deliberate negative control')
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    source_root = (args.source_root or repo).resolve()
    if args.work:
        work = args.work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), repo, source_root, work, args.controls_only)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-line-metadata-') as directory:
            check(args.axiom.resolve(), repo, source_root, Path(directory), args.controls_only)


if __name__ == '__main__':
    main()
