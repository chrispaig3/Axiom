#!/usr/bin/env python3
"""Exercise prune interner, cursor and line ownership with emitted modules.

The source template becomes a private .ax input. Negative probes change only
the copied codegen module. The old loop is reconstructed from the current
per-line helper, so shallow CI checkouts need no historical source files.
Remaining raw CG storage is measured in like-for-like runs.
"""
import argparse
import hashlib
import json
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

BRIDGES = r'''
; Private-copy-only views; none transfer the CG's existing owner share.
(pub :: probeLines (-> CG Strings))
;@axiom:effect(unsafe)
(pub fn (probeLines cg) (memGetWordVec (as cg Int) 0))
(pub :: probeLineAt (-> Strings Int String))
(pub fn (probeLineAt lines index) (vecGet lines index))
(pub :: probeStringCount (-> String Int))
;@axiom:effect(unsafe)
(pub fn (probeStringCount value) (__load64 (as value Int) -2))
(pub :: probeLineHeaderCount (-> Strings Int Int))
;@axiom:effect(unsafe)
(pub fn (probeLineHeaderCount lines index)
  {
    (let data (__load64 (as lines Int) 2))
    (__load64 (__load64 data index) -2)
  })
'''


def function(ir, name):
    match = re.search(r'^define [^\n]*@' + re.escape(name) +
                      r'\([^\n]*\)[^\n]*\{\n(.*?)^\}', ir, re.M | re.S)
    if match is None:
        raise RuntimeError(f'missing actual emitted function {name}')
    return match.group(1)


def result(body, callee, arguments=''):
    match = re.search(r'(%\S+) = (?:musttail )?call i64 @' + re.escape(callee) +
                      r'\(' + arguments, body)
    if match is None:
        raise RuntimeError(f'missing call to {callee}')
    return match.group(1)


def check_owner_ir(path):
    ir = path.read_text()
    body = function(ir, 'codegen$pruneDeadDefs')
    owner = result(body, 'Intern$internNew')
    ctx = result(body, 'codegen$pruneCtxNew', 'i64 ' + re.escape(owner) + ',')
    release = f'call void @axiom_release(i64 {owner})'
    if body.count(release) != 1:
        raise RuntimeError('prune interner must have exactly one ordinary owner release')
    if f'call void @axiom_retain(i64 {owner})' in body:
        raise RuntimeError('prune must not retain an unmatched interner share')
    required = ('@codegen$pruneIndexDefs(', '@codegen$pruneWalk(',
                '@codegen$pruneRebuild(', '@codegen$cgReplaceLines(i64 %cg,',
                f'call void @axiom_release(i64 {ctx})')
    # The swap publishes the rebuilt buffer before it retires the
    # displaced one, so a survivor never outlives both.
    swap = function(ir, 'codegen$cgReplaceLines')
    check_typed_slot(swap, 0, '%lines')
    drop = body.index(release)
    for operation in required:
        if operation not in body or body.rindex(operation) >= drop:
            raise RuntimeError(f'prune owner retires before {operation}')
    uses = [line for line in body.splitlines()
            if re.search(re.escape(ctx) + r'(?![0-9])', line)]
    if any(body.index(line) > drop for line in uses):
        raise RuntimeError('prune context remains in use after the interner owner retires')
    context = function(ir, 'codegen$pruneCtxNew')
    if context.count('call void @axiom_retain(i64 %si)') != 1:
        raise RuntimeError('typed prune context must retain its interner field once')
    if 'store i64 983048,' not in context:
        raise RuntimeError('typed prune context must describe all four owned fields')
    return {'owner': owner, 'context': ctx, 'ordinary_final_releases': 1,
            'drop_after_index_walk_rebuild_publish_ctx': True,
            'typed_context_owned_fields': 4}


def check_cursor_ir(path):
    ir = path.read_text()
    outer = function(ir, 'codegen$pruneIndexDefs')
    line = result(outer, 'Vec$vecGet')
    if outer.count(f'call void @axiom_release(i64 {line})') != 1:
        raise RuntimeError('line getter must have one ordinary release per iteration')
    cursor = result(outer, 'axiom_alloc', r'i64 24\)')
    if outer.count(f'call void @axiom_release(i64 {cursor})') != 1:
        raise RuntimeError('scalar cursor must have one ordinary final release')
    call = outer.index('@codegen$pruneIndexLine(')
    if outer.index(f'call void @axiom_release(i64 {line})') < call:
        raise RuntimeError('line getter retires before its per-line borrow ends')
    if outer.index(f'call void @axiom_release(i64 {cursor})') < call:
        raise RuntimeError('cursor retires before its per-line uses end')
    if 'store i64 8, ptr ' not in outer or 'store i64 1, ptr ' not in outer:
        raise RuntimeError('cursor must start with empty reference map and count1')
    helper = function(ir, 'codegen$pruneIndexLine')
    if re.findall(r'^  ret .*', helper, re.M) != ['  ret i64 0']:
        raise RuntimeError('per-line helper must return literal unit')
    if re.search(r'@axiom_(?:retain|release)\(i64 %(?:line|cursor)\)', helper):
        raise RuntimeError('per-line helper must borrow its line and cursor')
    if helper.count('@Str$strSlice(') != 1 or '@Str$strDup(' in helper:
        raise RuntimeError('symbol slice must keep its original ownership and spelling')
    return {'line_release_count': 1, 'cursor_release_count': 1,
            'cursor_bytes': 24, 'cursor_reference_map': 0,
            'helper_unit_return': True, 'borrowed_helper_parameters': True}


def form_end(source, start):
    """End of one balanced source form, respecting strings and comments."""
    depth = 0
    quoted = escaped = comment = False
    for index in range(start, len(source)):
        char = source[index]
        if comment:
            if char == '\n':
                comment = False
            continue
        if quoted:
            if escaped:
                escaped = False
            elif char == '\\':
                escaped = True
            elif char == '"':
                quoted = False
            continue
        if char == ';':
            comment = True
        elif char == '"':
            quoted = True
        elif char == '(':
            depth += 1
        elif char == ')':
            depth -= 1
            if depth == 0:
                return index + 1
    raise RuntimeError('unbalanced source while reversing cursor extraction')


def restore_old_loop(source):
    """Inline the same per-line algorithm into its original three-local loop."""
    helper_start = source.index('(fn (pruneIndexLine ')
    helper = source[helper_start:form_end(source, helper_start)]
    prefix = helper.index('  {\n') + len('  {\n')
    suffix = helper.rindex('\n    ()\n  })')
    body = helper[prefix:suffix]
    for field, local in (('current', 'cur'), ('function', 'function'), ('depth', 'depth')):
        body = body.replace('cursor.' + field, local)
    body = '\n'.join('    ' + line for line in body.splitlines())
    outer_start = source.index('(pub fn (pruneIndexDefs ')
    outer_end = form_end(source, outer_start)
    declaration = '(pub :: pruneIndexDefs (-> Strings InternState Ints Ints Ints Ints Ints Int))'
    if source.count(declaration) != 1:
        raise RuntimeError('cursor ablation needs the unchanged public index signature')
    old = declaration + '''
;@axiom:effect(unsafe)
(pub fn (pruneIndexDefs lines si idToDef defStart defEnd live defOf)
  {
    (let mut i 0)
    (let mut cur (- 0 1))
    (let mut function 0)
    (let mut depth 0)
    (while (< i (vecLen lines))
      {
        (let line (vecGetStr lines i))
''' + body + '''
        (set i (+ i 1))
      })
    0
  })'''
    start = source.index('(struct PruneCursor sealed')
    return source[:start] + old + source[outer_end:]


def private_modules(directory, source_root, source):
    directory.mkdir(parents=True, exist_ok=True)
    for item in (source_root / 'core').iterdir():
        target = directory / item.name
        if item.name == 'codegen.ax':
            target.write_text(source + BRIDGES)
        elif not target.exists():
            target.symlink_to(item, target_is_directory=item.is_dir())
    return directory


def check(axiom, repo, source_root, work):
    template = repo / 'tests/selfhost/emitter-prune-owner.axp'
    expected = template.with_suffix('.out').read_text().splitlines()
    if expected != [f'{i} true' for i in range(1, 35)]:
        raise RuntimeError('update the explicit 34-case verdict inventory')
    fixture = work / 'fixture.ax'
    fixture.write_text(template.read_text())
    source = (source_root / 'core/codegen.ax').read_text()
    report = {'builder': str(axiom), 'source_root': str(source_root),
              'builder_sha256': hashlib.sha256(axiom.read_bytes()).hexdigest(),
              'source_sha256': hashlib.sha256(source.encode()).hexdigest(),
              'positive': [], 'negative': []}
    env = dict(os.environ)
    env['PATH'] = '/opt/homebrew/opt/llvm/bin:' + env.get('PATH', '')
    env['AXIOM_STDLIB'] = str(source_root / 'stdlib')
    env['AXIOM_STDLIB_PATH'] = str(source_root / 'stdlib')
    run_checked([str(axiom), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)],
                env=env, stdout=work / 'format.stdout', stderr=work / 'format.stderr')
    semantic_reference = []

    def build_run(label, level, emitter, negative=None):
        modules = private_modules(work / (label + '-modules/core'), source_root, emitter)
        local = dict(env, AXIOM_PATH=str(modules))
        binary = work / label
        run_checked([str(axiom), '--diagnostic-format=ai', 'build', str(fixture),
                     '--opt', str(level), '--alloc-poison', '--emit-llvm', '-o', str(binary)],
                    env=local, stdout=work / (label + '.build.stdout'),
                    stderr=work / (label + '.build.stderr'))
        output = work / (label + '.stdout')
        error = work / (label + '.stderr')
        run_checked([str(binary)], env=local, stdout=output, stderr=error, timeout=60)
        failures = check_output(output, expected,
                                 required_failures=range(29, 35) if negative == 'old-loop' else ())
        if negative == 'old-loop' and failures != set(range(29, 35)):
            raise RuntimeError(f'{label}: reversing the loop changed more than the header-count verdicts')
        text = error.read_text()
        growth = re.search(r'^prune-soak-growth (-?\d+) (-?\d+)\n', text, re.M)
        if growth is None:
            raise RuntimeError(f'{label}: missing exact retained-heap measurements')
        semantics = text[:growth.start()] + text[growth.end():]
        if not semantic_reference:
            semantic_reference.append(semantics)
            (work / 'semantic-state.txt').write_text(semantics)
        elif semantic_reference[0] != semantics:
            raise RuntimeError(f'{label}: index tables, spellings, live state or rebuilt bytes changed')
        row = {'label': label, 'cases': len(expected),
               'failed_cases': sorted(failures), 'semantic_bytes_identical': True,
               'index_scope_retained_bytes': int(growth[1]),
               'whole_pruner_retained_bytes': int(growth[2])}
        try:
            row['owner_ir'] = check_owner_ir(binary.with_suffix('.ll'))
        except RuntimeError as problem:
            if negative != 'held-owner':
                raise
            row['owner_ir_expected_failure'] = str(problem)
        else:
            if negative == 'held-owner':
                raise RuntimeError(f'{label}: retaining an unmatched owner unexpectedly passed owner proof')
        try:
            row['cursor_ir'] = check_cursor_ir(binary.with_suffix('.ll'))
        except RuntimeError as problem:
            if negative != 'old-loop':
                raise
            row['cursor_ir_expected_failure'] = str(problem)
        else:
            if negative == 'old-loop':
                raise RuntimeError(f'{label}: restoring the old loop unexpectedly passed cursor proof')
        static_output = work / (label + '.static.stdout')
        static_error = work / (label + '.static.stderr')
        run_checked([str(binary), '--emit-staticlib'], env=local,
                    stdout=static_output, stderr=static_error, timeout=30)
        check_output(static_output, [f'{i} true' for i in range(1, 4)])
        if static_error.read_text():
            raise RuntimeError(f'{label}: unexpected static-library-path stderr')
        row['static_library_cases'] = 3
        return row

    for level in (0, 2):
        row = build_run(f'positive-O{level}', level, source)
        report['positive'].append(row)
        print(f'ok   prune owner: 34 semantic + 3 static-library cases at O{level}; '
              f'index retention {row["index_scope_retained_bytes"]}, '
              f'whole-pruner retention {row["whole_pruner_retained_bytes"]}', flush=True)
    raw = replace_once(source,
                       '(let si internNew)',
                       '(let si internNew)\n      (__retain (as si Int))', 'retain an unmatched prune interner share')
    raw = replace_once(raw, '(pub fn (pruneDeadDefs cg)',
                       ';@axiom:effect(unsafe)\n(pub fn (pruneDeadDefs cg)',
                       'declare the test-only unmatched retain')
    for level in (0, 2):
        row = build_run(f'held-owner-O{level}', level, raw, negative='held-owner')
        positive = report['positive'][level // 2]['whole_pruner_retained_bytes']
        row['extra_retained_bytes_vs_candidate'] = row['whole_pruner_retained_bytes'] - positive
        if row['extra_retained_bytes_vs_candidate'] <= 0:
            raise RuntimeError(f'held-owner-O{level}: held interner did not increase retained heap')
        report['negative'].append(row)
        print(f'ok   held-owner ablation at O{level}: owner proof fails and retains '
              f'{row["extra_retained_bytes_vs_candidate"]} additional bytes', flush=True)
    old_loop = restore_old_loop(source)
    for level in (0, 2):
        row = build_run(f'old-loop-O{level}', level, old_loop, negative='old-loop')
        report['negative'].append(row)
        print(f'ok   old-loop ablation at O{level}: header cases 29-34 and cursor proof fail; '
              'all indexed state and rebuilt bytes agree', flush=True)
    report['semantic_state_sha256'] = hashlib.sha256(semantic_reference[0].encode()).hexdigest()
    (work / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--source-root', type=Path, required=True)
    parser.add_argument('--work', type=Path)
    args = parser.parse_args()
    repo = Path(__file__).resolve().parents[2]
    if args.work:
        work = args.work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), repo, args.source_root.resolve(), work)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-prune-owner-') as path:
            check(args.axiom.resolve(), repo, args.source_root.resolve(), Path(path))


if __name__ == '__main__':
    main()
