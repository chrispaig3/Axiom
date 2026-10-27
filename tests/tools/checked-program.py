#!/usr/bin/env python3
"""Exercise the final-check handoff through the CLI's production path."""
import argparse
from pathlib import Path
import os
import shutil
import re
import subprocess
import tempfile


def handoff_lifetime(compiler, root, env, work):
    """Observe snapshot retirement through the real sealed handoff API."""
    source = (root / 'core/checked.ax').read_text()
    getter = '''
(pub :: checkedSnapshotCount (-> CheckedProgram Int))
(pub fn (checkedSnapshotCount program) (vecLen program.syntax))
'''
    expected = ''.join(f'{i} true\n' for i in range(1, 12))

    def probe(name, checked, level):
        directory = work / name
        directory.mkdir(exist_ok=True)
        (directory / 'checked.ax').write_text(checked + getter)
        environment = dict(env, AXIOM_PATH=os.pathsep.join(
            (str(directory), str(root / 'core'), str(root / 'tests/selfhost'))))
        output = directory / ('lifetime-O' + level)
        built = subprocess.run(
            [compiler, '--diagnostic-format=ai', 'build',
             str(root / 'tests/tools/checked-handoff-lifetime.ax'),
             '--opt', level, '--alloc-poison', '-o', str(output)],
            cwd=work, env=environment, capture_output=True, text=True, timeout=180)
        (directory / ('build-O' + level + '.log')).write_text(built.stdout + built.stderr)
        assert built.returncode == 0, (name, level, built.stderr)
        result = subprocess.run([str(output)], cwd=work, capture_output=True,
                                text=True, timeout=30)
        (directory / ('run-O' + level + '.out')).write_text(result.stdout)
        (directory / ('run-O' + level + '.err')).write_text(result.stderr)
        assert result.returncode == 0, (name, level, result.returncode, result.stderr)
        return result.stdout

    for level in ('0', '2'):
        actual = probe('positive', source, level)
        assert actual == expected, (level, 'handoff lifetime', actual)
    seam = '    (vecClear program.syntax)\n'
    assert source.count(seam) == 1, 'snapshot retirement seam changed'
    actual = probe('no-clear-control', source.replace(seam, ''), '0')
    failed = [line for line in actual.splitlines() if line.endswith(' false')]
    assert failed == ['4 false'], ('snapshot retirement ablation', actual)
    print('ok   checked handoff lifetime: 11 cases at O0/O2, no-clear ablation rejected')


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument('compiler')
    args.add_argument('--lifetime-only', action='store_true')
    args.add_argument('--work', type=Path, help='retain focused lifetime probe artifacts here')
    options = args.parse_args()
    compiler = str(Path(options.compiler).resolve())
    root = Path(__file__).resolve().parents[2]
    env = dict(os.environ, AXIOM_STDLIB=str(root / 'stdlib'))
    if options.lifetime_only:
        if options.work is not None:
            work = options.work.resolve()
            work.mkdir(parents=True, exist_ok=True)
            handoff_lifetime(compiler, root, env, work)
        else:
            with tempfile.TemporaryDirectory(prefix='axiom-checked-lifetime-') as temporary:
                handoff_lifetime(compiler, root, env, Path(temporary))
        return
    cases = {
        'parse': ('(:: main Int) (fn (main)', 'AX2001'),
        'binding': ('(:: main Int) (fn (main) missing)', 'AX3001'),
        'type': ('(:: main Int) (fn (main) true)', 'AX3004'),
        'effect': (
            '(import IO) (:: main ()) ;@axiom:effect(pure)\n'
            '(fn (main) (println "unsafe purity claim"))', 'AX3010'),
        'region': (
            '(import Str) (:: escaped (-> Int String)) '
            '(fn (escaped x) (region r (strAlloc x))) '
            '(:: main Int) (fn (main) 0)', 'AX3059'),
    }
    checks = 0
    with tempfile.TemporaryDirectory(prefix='axiom-checked-') as work:
        work = Path(work)
        handoff_lifetime(compiler, root, env, work)
        for name, (source, code) in cases.items():
            path = work / (name + '.ax')
            path.write_text(source)
            for command in ('emit-llvm', 'build'):
                output = work / (name + '-' + command)
                sentinel = b'previous output must survive a refused check\n'
                output.write_bytes(sentinel)
                run = subprocess.run(
                    [compiler, '--diagnostic-format=ai', command, str(path),
                     '-o', str(output)], cwd=work, env=env,
                    capture_output=True, text=True, timeout=60)
                assert run.returncode == 1, (name, command, run.returncode, run.stderr)
                assert 'E ' + code + ' ' in run.stderr, (name, command, run.stderr)
                assert output.read_bytes() == sentinel, (name, command, 'output replaced')
                assert 'target triple' not in run.stdout, (name, command, 'IR escaped')
                checks += 1

        (work / 'Support.ax').write_text(
            '(pub :: identity (-> a a)) (pub fn (identity x) x)\n')
        valid = work / 'valid.ax'
        valid.write_text(
            '(import Support) (import Vec) (import Str)\n'
            '(:: main Int)\n;@axiom:restrict(no-unsafe)\n'
            '(fn (main) { (let values (vecPush vecNew "typed")) '
            '(let nested (vecPush vecNew values)) '
            '(if (strEq (vecGet (vecGet nested 0) 0) "typed") '
            '(identity 42) 1) })\n')
        executable = work / 'valid'
        built = subprocess.run(
            [compiler, '--diagnostic-format=ai', 'build', str(valid),
             '-o', str(executable)], cwd=work, env=env,
            capture_output=True, text=True, timeout=60)
        assert built.returncode == 0, built.stderr
        result = subprocess.run([str(executable)], cwd=work, timeout=10)
        assert result.returncode == 42, result.returncode
        checks += 1

        # The standalone host generator edits the checked tree. The final
        # handoff follows the second check, including nominal accessors.
        archive = work / 'nominal.a'
        binding = work / 'nominal.rs'
        source = work / 'nominal-generated.ax'

        def host(input_path):
            return subprocess.run(
                ['cargo', 'run', '--quiet', '--manifest-path',
                 str(root / 'pkg/axiom-oxide/Cargo.toml'), '-p', 'axiom-oxide', '--',
                 'host', '--input', str(input_path), '--rust', str(binding),
                 '--archive', str(archive), '--keep-source', str(source),
                 '--axiom', compiler], cwd=work,
                env=dict(env, AXIOM_PATH=str(root / 'tests/ffi/host')),
                capture_output=True, text=True, timeout=180)

        built = host(root / 'tests/ffi/host/nominal.ax')
        assert built.returncode == 0, built.stderr
        assert archive.read_bytes().startswith(b'!<arch>\n'), 'missing native archive'
        assert 'make_thing' in binding.read_text(), 'missing generated binding'
        checks += 1

        archive_before, binding_before = archive.read_bytes(), binding.read_bytes()
        refused = host(root / 'tests/ffi/host/mangle-collision.ax')
        assert refused.returncode == 1, refused.stderr
        assert 'generated accessor names collide for `Box_Int`' in refused.stderr, refused.stderr
        assert archive.read_bytes() == archive_before, 'refused archive replaced output'
        assert binding.read_bytes() == binding_before, 'refused binding replaced output'
        checks += 1

        # Compiler clients may retain the mutable merged declaration vector.
        # Edits must invalidate its handoff, while an unchanged list and a
        # freshly checked edit remain usable. These exercise the real API.
        probe_env = dict(env, AXIOM_PATH=str(root / 'core'))

        def build_probe(name, output, environment):
            result = subprocess.run(
                [compiler, '--diagnostic-format=ai', 'build',
                 str(root / 'tests/selfhost' / name), '-o', str(output)],
                cwd=work, env=environment, capture_output=True, text=True, timeout=300)
            assert result.returncode == 0, result.stderr

        for name, status in (('1033-checked-declarations.ax', 42),
                             ('1034-checked-declarations-stale.ax', 80),
                             ('1035-checked-nested.ax', 42),
                             ('1036-checked-nested-stale.ax', 80)):
            executable = work / name.removesuffix('.ax')
            build_probe(name, executable, probe_env)
            result = subprocess.run([str(executable)], cwd=work,
                                    capture_output=True, timeout=30)
            assert result.returncode == status, (name, result.returncode, result.stderr)
            checks += 1

        # Remove only the membership precondition, preserving the private
        # snapshot. The same stale probe must then reach emission and exit 0,
        # proving that its status-80 assertion depends on this enforcement.
        control = work / 'control'
        control.mkdir()
        source = (root / 'core/checked.ax').read_text()
        seam = ';@axiom:pre((checkedDeclarationsUnchanged program))\n'
        assert source.count(seam) == 1, 'missing declaration-list enforcement seam'
        (control / 'checked.ax').write_text(source.replace(seam, ''))
        control_env = dict(env, AXIOM_PATH=os.pathsep.join((str(control), str(root / 'core'))))
        executable = work / 'unchecked-control'
        build_probe('1034-checked-declarations-stale.ax', executable, control_env)
        result = subprocess.run([str(executable)], cwd=work,
                                capture_output=True, timeout=30)
        assert result.returncode == 0, (result.returncode, result.stderr)
        checks += 1

        # Inferred return types must reach numeric lowering. A Float call
        # has the same word representation as Int, so successful assembly
        # alone does not detect integer arithmetic on its bit pattern.
        numeric = root / 'tests/selfhost/1044-checked-function-types.ax'
        for level in ('0', '2'):
            executable = work / ('checked-numeric-' + level)
            built = subprocess.run(
                [compiler, '--diagnostic-format=ai', 'build', str(numeric),
                 '--opt', level, '-o', str(executable)], cwd=work,
                env=probe_env, capture_output=True, text=True, timeout=180)
            assert built.returncode == 0, built.stderr
            result = subprocess.run([str(executable)], cwd=work,
                                    capture_output=True, timeout=30)
            assert result.returncode == 42, (level, result.returncode, result.stderr)
            checks += 1

        # Withhold only the checked function-type handoff. The accepted
        # source still builds, but computes the wrong answer, exit 1.
        # This leaves ownership and effect inference in both stages intact.
        seam = '(checkedFunctionTypes program.functions)'
        assert source.count(seam) == 1, 'missing checked function-type handoff seam'
        numeric_control = work / 'numeric-control-source'
        shutil.copytree(root / 'core', numeric_control)
        (numeric_control / 'checked.ax').write_text(source.replace(seam, 'vecNew'))
        control_compiler = work / 'numeric-control-compiler'
        built = subprocess.run(
            [compiler, '--diagnostic-format=ai', 'build', str(numeric_control / 'main.ax'),
             '-o', str(control_compiler)], cwd=work, env=env,
            capture_output=True, text=True, timeout=600)
        assert built.returncode == 0, built.stderr
        executable = work / 'numeric-control'
        # Use the original silent miscompilation as the control. The wider
        # positive fixture also mixes applications and nullary references;
        # their mismatched flags can instead trigger the AX4002 guard.
        control_input = work / 'numeric-control.ax'
        control_input.write_text(
            '(fn (value) 2.5)\n'
            '(fn (fraction n) (/ (as n Float) 2.0))\n'
            '(:: main Int)\n'
            '(fn (main) (if (&& (== (as (+ value value) Int) 5) '
            '(== (as (+ (fraction 5) (fraction 5)) Int) 5)) 42 1))\n')
        accepted = subprocess.run(
            [str(control_compiler), '--diagnostic-format=ai', 'check', str(control_input)],
            cwd=work, env=env, capture_output=True, text=True, timeout=60)
        assert accepted.returncode == 0, accepted.stderr
        built = subprocess.run(
            [str(control_compiler), '--diagnostic-format=ai', 'build', str(control_input),
             '-o', str(executable)], cwd=work, env=probe_env,
            capture_output=True, text=True, timeout=60)
        assert built.returncode == 0, built.stderr
        result = subprocess.run([str(executable)], cwd=work,
                                capture_output=True, timeout=30)
        assert result.returncode == 1, (result.returncode, result.stderr)
        checks += 1

        # Independently remove only nested-syntax enforcement. The stale
        # nested edit must then emit, while declaration-list enforcement
        # stays present. This catches a missing or ineffective guard.
        nested_seam = ';@axiom:pre((checkedSyntaxUnchanged program))\n'
        assert source.count(nested_seam) == 1, 'missing nested-syntax enforcement seam'
        (control / 'checked.ax').write_text(source.replace(nested_seam, ''))
        executable = work / 'unchecked-nested-control'
        build_probe('1036-checked-nested-stale.ax', executable, control_env)
        result = subprocess.run([str(executable)], cwd=work,
                                capture_output=True, timeout=30)
        assert result.returncode == 0, (result.returncode, result.stderr)
        checks += 1

        # Every current AST tag has an explicit traversal decision. A new
        # tag must update the checked handoff's schema rather than silently
        # inheriting the leaf fallback.
        parser = (root / 'core/parser.ax').read_text()
        tags = {int(value) for value in re.findall(
            r'\(pub fn \(TAG_\w+\)\s+(\d+)\)', parser)}
        shape = source.split('(fn (checkedSyntaxShape tag)', 1)[1].split(
            '; Hash buckets', 1)[0]
        covered = {int(value) for value in re.findall(r'\((\d+) "[wnNS]+"\)', shape)}
        assert tags == covered, ('unchecked AST schema tags', tags - covered, covered - tags)
        checks += 1

        # The emitter has one way in. `emitResolvedMode` is called from
        # `checked.ax` and nowhere else, and the entries that once went
        # around the final check - `emitModule`, `emitResolved` - are
        # gone. A new caller must take the sealed value, so it cannot
        # emit what the check refused.
        callers = {}
        for source in sorted((root / 'core').glob('*.ax')):
            for lineno, line in enumerate(source.read_text().split('\n'), 1):
                code = line.split(';', 1)[0]
                if '(emitResolvedMode ' in code:
                    callers.setdefault(source.name, []).append(lineno)
                for retired in ('(emitModule ', '(emitResolved ', 'emitModule (', 'emitResolved ('):
                    assert retired not in code, (source.name, lineno, retired)
        assert set(callers) == {'checked.ax', 'codegen.ax'}, callers
        assert len(callers['checked.ax']) == 1, callers
        # codegen's own occurrence is the declaration, not a call site
        definition = (root / 'core' / 'codegen.ax').read_text()
        assert definition.count('(pub fn (emitResolvedMode ') == 1
        assert callers['codegen.ax'] == [
            lineno for lineno, line in enumerate(definition.split('\n'), 1)
            if '(pub fn (emitResolvedMode ' in line
        ], callers
        checks += 1
    print(f'ok   checked compilation: {checks} refusal/output-preservation and native checks, and one way into the emitter')


if __name__ == '__main__':
    main()
