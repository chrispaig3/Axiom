#!/usr/bin/env python3
"""Check compiler argument-register text ownership without target RC probes."""
import argparse
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile


def checked(command, env, stdout, stderr, timeout=180):
    with stdout.open('w') as output, stderr.open('w') as error:
        result = subprocess.run(command, env=env, stdout=output, stderr=error, timeout=timeout)
    if result.returncode:
        raise RuntimeError(f'command exited {result.returncode}: {command}\n{stderr.read_text()[-4000:]}')


def function(ir, name):
    match = re.search(r'^define [^\n]*@' + re.escape(name)
                      + r'\([^\n]*\)[^\n]*\{\n(.*?)^\}', ir, re.M | re.S)
    if not match:
        raise RuntimeError(f'missing emitted function {name}')
    return match.group(1)


def reference_aliases(body, initial):
    """Follow parameter copies through local slots, without interpreting uses."""
    values, slots = set(initial), set()
    while True:
        before = len(values) + len(slots)
        for value, slot in re.findall(r'store i64 (%[^, ]+), ptr (%[^, \n]+)', body):
            if value in values:
                slots.add(slot)
        for value, slot in re.findall(r'(%\S+) = load i64, ptr (%[^, \n]+)', body):
            if slot in slots:
                values.add(value)
        if len(values) + len(slots) == before:
            return values


def definition_span(source, name):
    start = source.index('(pub fn (' + name + ' ')
    i, depth = start, 0
    while i < len(source):
        if source.startswith('#|', i):
            end = source.find('|#', i + 2)
            if end < 0:
                raise RuntimeError('unterminated comment in source definition')
            i = end + 2
        elif source[i] == ';':
            end = source.find('\n', i)
            i = len(source) if end < 0 else end + 1
        elif source[i] == '"':
            i += 1
            while i < len(source) and source[i] != '"':
                i += 2 if source[i] == '\\' else 1
            i += 1
        else:
            if source[i] in '({[':
                depth += 1
            elif source[i] in ')}]':
                depth -= 1
                if depth == 0:
                    return start, i + 1
            i += 1
    raise RuntimeError('unterminated source definition')


def metadata_ir(path, counted):
    ir = path.read_text()
    producer = function(ir, 'codegen$emitArgsRegs')
    birth = re.search(r'(%\S+) = call i64 @Str\$strDup\(', producer)
    if not birth:
        raise RuntimeError('argument producer has no ordinary register-text birth')
    pushes = re.findall(r'@Vec\$vecPush\(i64 %regs, i64 ' + re.escape(birth[1])
                        + r', i64 ([01])\)', producer)
    if pushes != ['1' if counted else '0']:
        raise RuntimeError(f'argument ledger has unexpected element witness: {pushes}')
    release = f'call void @axiom_release(i64 {birth[1]})'
    if producer.count(release) != (1 if counted else 0):
        raise RuntimeError('ordinary register-text birth cleanup did not follow its counted storage')
    if not counted:
        return {'element_witness': 0, 'ordinary_birth_released': False}
    uses = [line.strip() for line in producer.splitlines()
            if re.search(re.escape(birth[1]) + r'(?![A-Za-z0-9_.])', line)]
    if uses[-1] != release:
        raise RuntimeError('ordinary register-text birth does not retire at its last use')
    for getter in re.findall(r'(%\S+) = call i64 @raw\$memGetWordStr\(', producer):
        if producer.count(f'call void @axiom_release(i64 {getter})') != 1:
            raise RuntimeError('argument producer leaves an owned String getter temporary alive')
    for name in ['releaseOwnedArgs', 'releaseBorrowedFrom']:
        body = function(ir, 'codegen$' + name)
        aliases = reference_aliases(body, ['%regs'])
        reads = [(value, witness) for value, vector, witness in re.findall(
            r'(%\S+) = call i64 @Vec\$vecGet\(i64 (%[^, ]+), i64 [^,]+, i64 ([01])\)', body)
                 if vector in aliases]
        if not reads or any(witness != '1' for _, witness in reads):
            raise RuntimeError(f'{name}: metadata ledger read lacks String evidence')
        for value, _ in reads:
            if body.count(f'call void @axiom_release(i64 {value})') != 1:
                raise RuntimeError(f'{name}: owned metadata read temporary does not retire')
    for name in ['emitPlainCall', 'emitPairFwd']:
        body = function(ir, 'codegen$' + name)
        ledgers = re.findall(r'@codegen\$emitArgsRegs\(i64 [^,]+, i64 [^,]+, i64 (%[^, ]+),', body)
        if len(ledgers) != 1 or body.count(f'call void @axiom_release(i64 {ledgers[0]})') != 1:
            raise RuntimeError(f'{name}: ordinary local argument ledger does not drop')
    return {'element_witness': 1, 'ordinary_birth_released': True,
            'getter_temporaries_retire': True, 'both_local_ledgers_drop': True}


def raw_metadata(source):
    """Revert only the six metadata sites, leaving target decisions unchanged."""
    edits = [
        ('(pub :: emitArgsRegs (-> Nodes CG Strings Int String Int CG))',
         '(pub :: emitArgsRegs (-> Nodes CG Ints Int String Int CG))'),
        ('(vecPush regs reg)', '(vecPush regs (as reg Int))'),
        ('(pub :: releaseOwnedArgs (-> CG String Nodes Strings Int CG))',
         '(pub :: releaseOwnedArgs (-> CG String Nodes Ints Int CG))'),
        ('(pub :: releaseBorrowedFrom (-> CG String Nodes Strings Int CG))',
         '(pub :: releaseBorrowedFrom (-> CG String Nodes Ints Int CG))'),
    ]
    for before, after in edits:
        if source.count(before) != 1:
            raise RuntimeError('metadata ablation source anchor changed')
        source = source.replace(before, after, 1)
    # The reverted sites erase a reference, and a compiler-directory
    # declaration must say so (AX3073) even in a private ablation.
    for name in ['emitArgsRegs', 'releaseOwnedArgs', 'releaseBorrowedFrom']:
        anchor = f'(pub fn ({name} '
        if source.count(anchor) != 1:
            raise RuntimeError('metadata ablation function anchor changed')
        source = source.replace(anchor, ';@axiom:effect(unsafe)\n' + anchor, 1)
    # Change only the ledger read in each consumer, preserving every
    # surrounding byte, including target release-decision expressions.
    before = '(vecGet regs i)'
    after = '(as (vecGet regs i) String)'
    for name in ['releaseOwnedArgs', 'releaseBorrowedFrom']:
        start, end = definition_span(source, name)
        body = source[start:end]
        if body.count(before) != 1:
            raise RuntimeError('expected one metadata ledger read per consumer')
        changed = body.replace(before, after, 1)
        if changed.replace(after, before, 1) != body:
            raise RuntimeError('metadata ablation changed a surrounding decision')
        source = source[:start] + changed + source[end:]
        signature = f'(pub :: {name} (-> CG String Nodes Ints Int CG))\n'
        if source.count(signature) != 1:
            raise RuntimeError('raw metadata boundary declaration changed')
        source = source.replace(signature, signature + ';@axiom:effect(unsafe)\n', 1)
    return source


def check(axiom, repo, work, positive_only):
    source = (repo / 'core/codegen.ax').read_text()
    original_fixture = (Path(__file__).with_suffix('.ax')).read_text()
    expected = Path(__file__).with_suffix('.out').read_text().splitlines()
    if expected != [f'{i} true' for i in range(1, 21)]:
        raise RuntimeError('update the explicit 20-case assertion count')
    env = dict(os.environ, AXIOM_STDLIB=str(repo / 'stdlib'))

    def build(label, level, codegen, fixture):
        modules = work / (label + '-modules/core')
        modules.mkdir(parents=True, exist_ok=True)
        for path in (repo / 'core').iterdir():
            destination = modules / path.name
            if path.name == 'codegen.ax':
                destination.write_text(codegen)
            elif not destination.exists():
                destination.symlink_to(path, target_is_directory=path.is_dir())
        local = dict(env, AXIOM_PATH=str(modules))
        input_ = work / (label + '.ax')
        input_.write_text(fixture)
        binary = work / label
        checked([str(axiom), '--diagnostic-format=ai', 'fmt', '--check',
                 str(Path(__file__).with_suffix('.ax'))], local,
                work / (label + '.fmt.stdout'), work / (label + '.fmt.stderr'))
        checked([str(axiom), '--diagnostic-format=ai', 'build', str(input_),
                 '--opt', str(level), '--alloc-poison', '--emit-llvm', '-o', str(binary)],
                local, work / (label + '.build.stdout'), work / (label + '.build.stderr'))
        return binary, local

    reports = []
    for level in [0, 2]:
        label = f'positive-O{level}'
        binary, local = build(label, level, source, original_fixture)
        checked([str(binary)], local, work / (label + '.stdout'), work / (label + '.stderr'), timeout=30)
        if (work / (label + '.stdout')).read_text().splitlines() != expected:
            raise RuntimeError(f'{label}: argument metadata ownership cases differ')
        if (work / (label + '.stderr')).read_text() != 'argument-register-soak-growth 0\n':
            raise RuntimeError(f'{label}: ordinary metadata storage has nonzero live growth')
        if level == 0:
            reports.append(metadata_ir(Path(str(binary) + '.ll'), True))
        print(f'ok   argument register metadata: 20 cases, zero live growth at -O{level}', flush=True)
    if not positive_only:
        old_fixture = original_fixture.replace('(type RegisterTexts (Vec String))',
                                               '(type RegisterTexts (Vec Int))', 1)
        old_fixture = old_fixture.replace('(fn (registerAt values index)\n  (vecGet values index))',
                                         '(fn (registerAt values index)\n  (as (vecGet values index) String))', 1)
        old_fixture = old_fixture.replace('(:: registerAt (-> RegisterTexts Int String))\n',
                                         '(:: registerAt (-> RegisterTexts Int String))\n;@axiom:effect(unsafe)\n', 1)
        binary, _ = build('raw-metadata', 0, raw_metadata(source), old_fixture)
        reports.append(metadata_ir(Path(str(binary) + '.ll'), False))
        print('ok   raw metadata ablation: witness 0 and missing ordinary birth cleanup; not executed', flush=True)
    (work / 'argument-register-report.json').write_text(json.dumps(reports, indent=2) + '\n')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--axiom', type=Path, required=True)
    parser.add_argument('--repo', type=Path, required=True,
                        help='approved isolated source tree; no compiler is rebuilt')
    parser.add_argument('--work', type=Path)
    parser.add_argument('--positive-only', action='store_true')
    args = parser.parse_args()
    if args.work:
        work = args.work.resolve()
        work.mkdir(parents=True, exist_ok=True)
        check(args.axiom.resolve(), args.repo.resolve(), work, args.positive_only)
    else:
        with tempfile.TemporaryDirectory(prefix='axiom-argument-registers-') as directory:
            check(args.axiom.resolve(), args.repo.resolve(), Path(directory), args.positive_only)


if __name__ == '__main__':
    main()
