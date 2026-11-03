#!/usr/bin/env python3
"""Check the planned battery's contract: one build per platform, a
generated shard matrix, change selection, and the aggregate verdicts.

The workflow this describes used to be a hand-written step list in
four shards; it is now generated. `scripts/ci-plan.py` assigns every
gate to a shard, the `scope` job plans the matrix for the change
set, `scripts/ci-run.py` executes a shard, and each gate reuses a
recorded pass through `scripts/ci-gate.py` when its inputs are
unchanged. This test holds that shape: the workflow must execute
the plan (not a second, hand-kept list), the plan must partition
the battery exactly, selection must run what a change can affect
and no more, and the checks branch protection reads must still be
green only when every shard passed.
"""
from pathlib import Path
import importlib.util
import sys

ROOT = Path(__file__).resolve().parents[2]


def _load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


reader = _load('ci_step_reader', ROOT / 'scripts/lib/ci-steps.py')
plan = _load('ci_plan_under_test', ROOT / 'scripts/ci-plan.py')

PLATFORMS = ['linux-aarch64', 'darwin-aarch64']


def _needs(job):
    needs = job.get('needs') or []
    return {needs} if isinstance(needs, str) else set(needs)


def _runs(job):
    return [s.get('run', '') for s in job.get('steps') or []
            if isinstance(s, dict) and isinstance(s.get('run'), str)]


def validate(workflow, cache):
    errors = []

    def require(condition, message):
        if not condition:
            errors.append(message)

    try:
        document = reader.Reader(workflow).node(0)
        require(document['concurrency']['group'] == 'ci-${{ github.ref }}',
                'one concurrency group per ref')
        cancel = str(document['concurrency']['cancel-in-progress'])
        require('refs/heads/stable' in cancel and '!=' in cancel,
                'superseded runs cancel except on stable, whose verdict a release may await')
        jobs = document['jobs']

        # scope plans the run: the matrix, and which dedicated jobs
        # the change reaches. Renames must name both paths, or the
        # old name's gates never hear about the deletion.
        scope = jobs['scope']
        require({'docs_only', 'battery', 'matrix', 'special'} <= set(scope['outputs']),
                'scope must publish docs_only, battery, matrix and special')
        scope_runs = '\n'.join(_runs(scope))
        require('scripts/ci-plan.py' in scope_runs and '--matrix' in scope_runs,
                'scope must generate the test matrix with ci-plan.py')
        require('previous_filename' in scope_runs,
                'the change set must name renamed-away paths as well as new ones')
        require('schedule' in scope_runs,
                'scheduled runs must plan the full battery without a change set')

        # The compiler is built once per platform and handed over.
        build = jobs['build']
        include = build['strategy']['matrix']['include']
        require([row['name'] for row in include] == PLATFORMS,
                'the build matrix must cover both supported platforms once')
        require(any(str(s.get('uses', '')).startswith('actions/upload-artifact@')
                    and 'axc-' in str(s.get('with', {}).get('name', ''))
                    for s in build['steps'] if isinstance(s, dict)),
                'the build job must hand the compilers to the shards as artifacts')

        # The battery job executes the generated plan, nothing else.
        test = jobs['test']
        require(_needs(test) == {'scope', 'build'},
                'test shards must wait for the plan and the built compilers')
        require('battery' in str(test.get('if', '')),
                'test shards run only when the plan selected battery gates')
        require(test['strategy']['fail-fast'] == 'false',
                'one shard failure must not cancel another')
        require(str(test['strategy']['matrix']) == '${{ fromJSON(needs.scope.outputs.matrix) }}',
                'the test matrix must be the generated plan, not a hand-kept list')
        test_runs = '\n'.join(_runs(test))
        require('scripts/ci-plan.py' in test_runs and 'scripts/ci-run.py' in test_runs,
                'each shard must regenerate its gate list and run it with ci-run.py')
        provision = [s for s in test['steps'] if isinstance(s, dict)
                     and s.get('uses') == './.github/actions/provision']
        require(provision and all(str(s.get('with', {}).get('bootstrap')) == 'false'
                                  for s in provision),
                'shards install LLVM only; the compilers arrive as artifacts')
        slots = [s.get('with', {}).get('namespace') for s in test['steps']
                 if isinstance(s, dict) and s.get('uses') == './.github/actions/gate-cache']
        require(len(slots) == 2 and slots[0] == slots[1] and 'matrix.shard' in str(slots[0]),
                'gate-cache restore and save must share one per-shard namespace')

        # Dedicated jobs follow the same selection as the battery.
        for job_id, gate in (('ffi', 'check-ffi.sh'),):
            job = jobs[job_id]
            require(_needs(job) == {'scope', 'grammar'} and gate in str(job.get('if', '')),
                    f'{job_id} must start only when the change meets {gate}')
        cross_if = str(jobs['cross'].get('if', ''))
        require('check-cross-targets.sh' in cross_if and 'check-windows-hello.sh' in cross_if,
                'cross must start only when the change meets one of its gates')

        # The per-platform aggregate branch protection reads.
        aggregate = jobs['test-results']
        require(aggregate['name'] == 'Tests (${{ matrix.name }})', 'aggregate check names changed')
        require(_needs(aggregate) == {'grammar', 'test'},
                'aggregate must await the entire test matrix')
        require(aggregate['if'] == "${{ always() && needs.grammar.result == 'success' }}",
                'aggregate must evaluate failed shards after grammar succeeds')
        require(aggregate['strategy']['matrix']['name'] == PLATFORMS,
                'aggregate lost a required check')
        steps = aggregate['steps']
        require(len(steps) == 1 and steps[0].get('run') == 'test "$SHARDS_RESULT" = success'
                and steps[0].get('env', {}).get('SHARDS_RESULT') == '${{ needs.test.result }}',
                'aggregate must reject failure, cancellation and skipped tests')

        # The one overall verdict.
        overall = jobs['ci']
        require({'scope', 'build', 'test', 'test-results'} <= _needs(overall),
                'the CI verdict must await the plan, the builds and every shard')
        require('always()' in str(overall.get('if', '')),
                'the CI verdict must render even when a needed job failed')

        # The cache contract behind reuse and re-runs.
        action = reader.Reader(cache).node(0)
        require(action['inputs']['namespace'].get('default') == '',
                'unsharded cache keys must stay unchanged')
        operations = [s for s in action['runs']['steps']
                      if str(s.get('uses', '')).startswith('actions/cache/')]
        keys = [s['with']['key'] for s in operations]
        require(len(keys) == 2 and keys[0] == keys[1], 'cache restore/save identities differ')
        require(all('${{ inputs.namespace }}' in key for key in keys),
                'cache identity must include the shard namespace')
        save_if = str(operations[1].get('if', '')) if len(operations) > 1 else ''
        require('refs/heads/nightly' in save_if and 'pull_request' in save_if,
                'completed passes must save on nightly pushes and same-repository pull requests, '
                'so a re-run only redoes what has not passed')
    except (KeyError, TypeError, reader.Unreadable) as exc:
        errors.append('unreadable CI contract: ' + str(exc))

    # The plan itself, whatever the workflow text says: a complete,
    # disjoint partition, and selection that follows gate inputs.
    try:
        shards = plan.plan()
        battery = plan.battery_gates()
        flat = [g for shard in shards for g in shard]
        require(len(shards) == plan.SHARDS and all(shards),
                'the plan must fill every shard')
        require(sorted(flat) == sorted(battery) and len(flat) == len(set(flat)),
                'the shards must partition the battery exactly once')
        require([p['name'] for p in plan.PLATFORMS] == PLATFORMS,
                'the planner platforms must be the supported targets')

        crypto = sorted((ROOT / 'tests/crypto').glob('*.ax'))
        require(bool(crypto), 'tests/crypto fixtures are missing')
        if crypto:
            rel = crypto[0].relative_to(ROOT).as_posix()
            selected = plan.select_gates(battery, {rel})
            require('check-crypto.sh' in selected and len(selected) < len(battery),
                    'a fixture change must select its gate and not the whole battery')
            deleted = plan.select_gates(battery, {'/'.join(('tests', 'crypto', '__deleted__.ax'))})
            require('check-crypto.sh' in deleted,
                    'a deleted fixture must still select its gate')
        require(plan.select_gates(battery, {'core/parser.ax'}) == battery,
                'a compiler change must select the whole battery')
        require('check-race.sh' not in plan.select_gates(battery, {'docs/reference.md'}),
                'a document change must not select gates that read no documents')
        require(plan.select_gates(battery, None) == battery,
                'an unenumerable change set must select the whole battery')
    except Exception as exc:  # the planner refusing to plan is a finding
        errors.append('unreadable plan: ' + str(exc))
    return errors


def main():
    workflow_path = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / '.github/workflows/ci.yml'
    workflow = workflow_path.read_text()
    cache = (ROOT / '.github/actions/gate-cache/action.yml').read_text()
    errors = validate(workflow, cache)
    if errors:
        print('\n'.join('FAIL ' + e for e in errors))
        return 1
    mutations = [
        ('a renamed concurrency group',
         workflow.replace('ci-${{ github.ref }}', 'ci-old-${{ github.ref }}', 1), cache),
        ('cancelling a stable run',
         workflow.replace("cancel-in-progress: ${{ github.ref != 'refs/heads/stable' }}",
                          'cancel-in-progress: true', 1), cache),
        ('a hand-kept test matrix',
         workflow.replace('fromJSON(needs.scope.outputs.matrix)', 'fromJSON({})', 1), cache),
        ('a shard that never runs its gates',
         workflow.replace('scripts/ci-run.py', 'scripts/no-run.py'), cache),
        ('renames losing their old path',
         workflow.replace('previous_filename', 'previous_name'), cache),
        ('shards re-bootstrapping the seed',
         workflow.replace("bootstrap: 'false'", "bootstrap: 'true'", 1), cache),
        ('the FFI job ignoring selection',
         workflow.replace("contains(needs.scope.outputs.special, 'check-ffi.sh')", 'true', 1), cache),
        ('an aggregate hiding failure',
         workflow.replace('test "$SHARDS_RESULT" = success', 'true', 1), cache),
        ('colliding shard cache keys',
         workflow, cache.replace('${{ inputs.namespace }}', '')),
    ]
    for label, changed, changed_cache in mutations:
        if (changed, changed_cache) == (workflow, cache) or not validate(changed, changed_cache):
            print('FAIL control did not detect ' + label)
            return 1
    print('ok: planned partition, built-once handoff, change selection, '
          'aggregate verdicts and cache contract; nine negative controls')
    return 0


if __name__ == '__main__':
    sys.exit(main())
