#!/usr/bin/env python3
"""Exercise gate reuse, invalidation and failure propagation on a real Git tree."""
import contextlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tempfile
import time

repo = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('ci_gate', repo / 'scripts/ci-gate.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)
context = {'compiler': 'test-toolchain-1'}
ci.tool_context = lambda: context
checks = 0


def expect(value, message):
    global checks
    checks += 1
    if not value:
        raise AssertionError(message)


saved_env = os.environ.copy()
try:
    with tempfile.TemporaryDirectory(prefix='axiom-ci-cache-') as scratch:
        root = Path(scratch)
        subprocess.run(['git', 'init', '-q', str(root)], check=True)
        for d in ('scripts/lib', 'core', 'stdlib', 'tests/selfhost', 'tests/stdlib'):
            (root / d).mkdir(parents=True)
        files = {'.gitignore': '.results/\ncount\nfailure\n', 'core/main.ax': 'compiler\n',
                 'scripts/lib/gate.sh': 'helper\n', 'stdlib/Pre.ax': 'stdlib\n',
                 '/'.join(('tests', 'selfhost', 'input.ax')): 'completion input\n',
                 '/'.join(('tests', 'stdlib', 'unrelated.ax')): 'unrelated fixture\n'}
        for p, body in files.items():
            (root / p).write_text(body)
        gate = root / 'scripts/check-self-host.sh'
        body = '#!/bin/sh\n: "${SELF_TEST:-0}"\nn=0\n[ ! -e count ] || n=$(cat count)\necho $((n+1)) > count\nrc=0\n[ ! -e failure ] || rc=$(cat failure)\nexit "$rc"\n'
        gate.write_text(body)
        gate.chmod(0o755)
        subprocess.run(['git', '-C', str(root), 'add', '.'], check=True)
        os.environ.update(AXIOM_CI_CACHE=str(root / '.results'), GITHUB_SHA='a' * 40,
                          GITHUB_RUN_ID='123')
        os.environ.pop('AXIOM_CI_FRESH', None)
        os.environ.pop('SELF_TEST', None)
        os.environ.pop('GITHUB_STEP_SUMMARY', None)

        def run(args=()):
            with contextlib.redirect_stdout(io.StringIO()):
                return ci.run(root, ['./scripts/check-self-host.sh', *args])

        def count():
            return int((root / 'count').read_text())

        def current_record(args=()):
            key = ci.fingerprint(root, gate.name, args, context)
            return root / '.results' / (key + '.json')

        expect(run() == 0 and count() == 1, 'a miss must execute')
        expect(run() == 0 and count() == 1, 'a matching pass must be reused')
        (root / 'docs').mkdir()
        (root / 'docs/reference.md').write_text('unrelated prose\n')
        (root / 'CHANGELOG.md').write_text('unrelated release note\n')
        (root / 'scripts/check-other.sh').write_text('#!/bin/sh\nexit 0\n')
        expect(run() == 0 and count() == 1, 'unrelated prose and gate scripts should preserve reuse')
        (root / '/'.join(('tests', 'stdlib', 'unrelated.ax'))).write_text('changed unrelated fixture\n')
        expect(run() == 0 and count() == 1, 'unrelated fixtures should preserve reuse')
        for p in ('/'.join(('tests', 'selfhost', 'input.ax')), 'core/main.ax', 'stdlib/Pre.ax', 'scripts/lib/gate.sh'):
            (root / p).write_text((root / p).read_text() + 'changed\n')
            before = count()
            expect(run() == 0 and count() == before + 1, f'{p} must invalidate a pass')
        expect(run(('different-argument',)) == 0 and count() == 6, 'arguments must invalidate')
        context['compiler'] = 'test-toolchain-2'
        expect(run() == 0 and count() == 7, 'toolchain changes must invalidate')
        before_mode = ci.fingerprint(root, gate.name, (), context)
        gate.chmod(0o644)
        expect(ci.fingerprint(root, gate.name, (), context) != before_mode, 'file modes must be inputs')
        gate.chmod(0o755)
        (root / 'tests/new-suite').mkdir()
        (root / '/'.join(('tests', 'new-suite', 'new.ax'))).write_text('new fixture directory\n')
        expect(run() == 0 and count() == 8, 'new test directories must invalidate conservatively')
        (root / '/'.join(('tests', 'selfhost', 'input.ax'))).unlink()
        expect(run() == 0 and count() == 9, 'deletions must invalidate')
        os.environ['AXIOM_CI_FRESH'] = '1'
        (root / 'failure').write_text('7')
        expect(run() == 7 and count() == 10, 'a fresh failing run must propagate its status')
        os.environ.pop('AXIOM_CI_FRESH')
        expect(run() == 7 and count() == 11, 'a failed fresh run must invalidate the earlier pass')
        expect(run() == 7 and count() == 12, 'failures must run again')
        (root / 'failure').write_text('0')
        expect(run() == 0 and count() == 13, 'a repaired gate must execute before reuse')
        record = current_record()
        record.write_text('{broken')
        expect(run() == 0 and count() == 14, 'corrupt records must run again')
        for stamp in (time.time() - ci.MAX_AGE - 1, time.time() + 60):
            proof = json.loads(record.read_text())
            proof['completed_at'] = stamp
            record.write_text(json.dumps(proof))
            before = count()
            expect(run() == 0 and count() == before + 1, 'expired/future records must run again')
        proof = json.loads(record.read_text())
        proof['key'] = 'wrong'
        record.write_text(json.dumps(proof))
        expect(run() == 0 and count() == 17, 'records must match their content key')
        base_proof = json.loads(record.read_text())
        for field, value in (('schema', 0), ('gate', 'check-other.sh'), ('sha', 'invalid'),
                             ('run_id', 'invalid'), ('result', 'failed')):
            wrong = dict(base_proof)
            wrong[field] = value
            record.write_text(json.dumps(wrong))
            expect(not ci.valid_record(record, record.stem, gate.name, time.time()),
                   f'invalid {field} must never represent a reusable pass')
        record.write_text(json.dumps(base_proof))
        action = (repo / '.github/actions/gate-cache/action.yml').read_text()
        expect("!cancelled() && inputs.mode == 'save'" in action and
               "github.event_name == 'push'" in action and
               "github.ref == 'refs/heads/stable' || github.ref == 'refs/heads/nightly'" in action and
               "github.event_name == 'pull_request'" in action and
               "head.repo.full_name == github.repository" in action,
               'failed jobs must save completed passes on branch pushes and same-repository pull requests')
        ci.ALWAYS_RUN.add(gate.name)
        expect(run() == 0 and run() == 0 and count() == 19, 'always-run audits must not reuse passes')
        ci.ALWAYS_RUN.remove(gate.name)
        os.environ.pop('AXIOM_CI_CACHE')
        expect(run() == 0 and run() == 0 and count() == 21, 'ordinary local runs must stay fresh')
        os.environ['AXIOM_CI_CACHE'] = str(root / '.results')
        os.environ['SELF_TEST'] = '1'
        before = count()
        expect(run() == 0 and count() == before + 1, 'gate-specific environment switches must invalidate')
        os.environ.pop('SELF_TEST')
        gate.write_text(body.replace('exit ', 'echo changed >> core/main.ax\nexit '))
        before = len(list((root / '.results').glob('*.json')))
        expect(run() == 0 and len(list((root / '.results').glob('*.json'))) == before,
               'a gate that mutates its inputs must not earn a success record')
        # Input selection: the rules CI uses to rerun only what changed.
        expect(not ci.uses_git(root, gate.name),
               'a gate that never invokes git must not be history-dependent')
        probe = root / 'scripts/check-probe.sh'
        probe.write_text('#!/bin/sh\ngit ls-files\n')
        expect(ci.uses_git(root, probe.name), 'a git enumeration is history-dependent')
        expect(len(ci.input_paths(root, probe.name)) == len(ci.tracked_paths(root)),
               'a git enumeration keeps the whole tree as input')
        probe.write_text('#!/bin/sh\ntar -cf - tests\n')
        expect(len(ci.input_paths(root, probe.name)) == len(ci.tracked_paths(root)),
               'sweeping the bare tests directory keeps the whole tree as input')
        probe.write_text('#!/bin/sh\ncat ' + '/'.join(('tests', 'selfhost', 'input.ax'))
                         + '\necho "so it tests nothing"\n')
        expect(ci.touches_gate(root, probe.name, {'/'.join(('tests', 'selfhost', 'gone.ax'))}),
               'a deleted fixture in a named root must still select its gate')
        expect(not ci.touches_gate(root, probe.name, {'/'.join(('tests', 'stdlib', 'unrelated.ax'))}),
               'an unrelated fixture root must not select the gate')
        expect(not ci.touches_gate(root, probe.name, {'docs/reference.md', 'README.md'}),
               'prose a gate never names must not select it')
        probe.unlink()
        # The coverage reader accepts only the exact audited wrapper form.
        spec = importlib.util.spec_from_file_location('ci_steps', repo / 'scripts/lib/ci-steps.py')
        reader = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(reader)
        expect(reader.read_steps('./scripts/ci-gate.py ./scripts/check-self-host.sh')[0] == [gate.name],
               'the coverage reader must recognise the wrapper')
        for text in ('echo ./scripts/ci-gate.py ./scripts/check-self-host.sh',
                     './scripts/ci-gate.py ./scripts/check-self-host.sh || true',
                     './scripts/ci-gate.py bash ./scripts/check-self-host.sh'):
            expect(not reader.read_steps(text)[0], 'a mention or status-masking wrapper is not coverage')
finally:
    os.environ.clear()
    os.environ.update(saved_env)
print(f'gate-cache: {checks} checks passed')
