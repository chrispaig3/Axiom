#!/usr/bin/env python3
"""Check the complete test partition, aggregate verdict and cache namespaces."""
from pathlib import Path
import collections
import importlib.util
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('ci_step_reader', ROOT / 'scripts/lib/ci-steps.py')
reader = importlib.util.module_from_spec(spec)
spec.loader.exec_module(reader)


def validate(workflow, cache):
    errors = []
    def require(condition, message):
        if not condition:
            errors.append(message)
    try:
        document = reader.Reader(workflow).node(0)
        require(document['concurrency']['group'] == 'ci-sharded-v1-${{ github.ref }}',
                'the sharded layout must not wait behind the old serial queue')
        require(document['concurrency']['cancel-in-progress'] == 'false',
                'a newer push must not cancel a running battery')
        jobs = document['jobs']
        test = jobs['test']
        matrix = test['strategy']['matrix']
        require(matrix['shard'] == ['1', '2', '3', '4'], 'test matrix must contain each shard once')
        platforms = ['linux-aarch64', 'darwin-aarch64']
        require(matrix['name'] == platforms, 'both supported platforms must run every shard')
        require(matrix['include'] == [
            {'name': 'linux-aarch64', 'os': 'ubuntu-24.04-arm'},
            {'name': 'darwin-aarch64', 'os': 'macos-15'}],
            'the platform runners changed or an include row overrides a shard')
        require(not test.get('if') and test.get('continue-on-error', 'false') == 'false',
                'test jobs must run after grammar and preserve failures')
        require(test['strategy']['fail-fast'] == 'false', 'one shard failure must not cancel another')
        counts = collections.Counter()
        for step in test['steps']:
            command = step.get('run', '')
            if not command or 'scripts/build-shared-axc.sh' in command:
                continue
            guard = str(step.get('if', ''))
            matches = re.findall(r'matrix\.shard == ([1-4])(?=\s|\})', guard)
            require(len(matches) == 1, 'test step needs exactly one shard: ' + step.get('name', command))
            require('!cancelled()' in guard and "steps.compiler.outcome == 'success'" in guard,
                    'a test step lost its compiler/cancellation guard')
            require(step.get('continue-on-error', 'false') == 'false', 'a shard step masks failure')
            if matches:
                counts[matches[0]] += 1
        require(sum(counts.values()) >= 90 and all(counts[str(i)] >= 10 for i in range(1, 5)),
                'the partition lost a substantial part of the test battery')
        slots = [step.get('with', {}).get('namespace') for step in test['steps']
                 if step.get('uses') == './.github/actions/gate-cache']
        require(slots == ['-shard-${{ matrix.shard }}'] * 2,
                'restore and save must use the same shard namespace')
        aggregate = jobs['test-results']
        require(aggregate['name'] == 'Tests (${{ matrix.name }})', 'aggregate check names changed')
        require(set(aggregate['needs']) == {'grammar', 'test'}, 'aggregate must await the entire test matrix')
        require(aggregate['if'] == "${{ always() && needs.grammar.result == 'success' }}",
                'aggregate must evaluate failed shards after grammar succeeds')
        require(aggregate['strategy']['matrix']['name'] == platforms, 'aggregate lost a required check')
        steps = aggregate['steps']
        require(len(steps) == 1 and steps[0].get('run') == 'test "$SHARDS_RESULT" = success'
                and steps[0].get('env', {}).get('SHARDS_RESULT') == '${{ needs.test.result }}',
                'aggregate must reject failure, cancellation and skipped tests')
        require(aggregate.get('continue-on-error', 'false') == 'false'
                and steps[0].get('continue-on-error', 'false') == 'false', 'aggregate masks failure')
        action = reader.Reader(cache).node(0)
        require(action['inputs']['namespace'].get('default') == '', 'unsharded cache keys must stay unchanged')
        operations = [s for s in action['runs']['steps'] if s.get('uses', '').startswith('actions/cache/')]
        keys = [s['with']['key'] for s in operations]
        require(len(keys) == 2 and keys[0] == keys[1], 'cache restore/save identities differ')
        require(all('${{ runner.arch }}${{ inputs.namespace }}-' in key for key in keys),
                'cache identity must include the shard without changing unsharded keys')
        restore = operations[0]['with']['restore-keys']
        require('${{ inputs.namespace }}-' in restore
                and 'axiom-gates-v1-${{ github.job }}-${{ runner.os }}-${{ runner.arch }}-' in restore,
                'restore must prefer this shard and retain the old cache fallback')
    except (KeyError, TypeError, reader.Unreadable) as exc:
        errors.append('unreadable shard contract: ' + str(exc))
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
        ('the old serial queue', workflow.replace('ci-sharded-v1-${{ github.ref }}', 'ci-${{ github.ref }}', 1), cache),
        ('cancelling an active run', workflow.replace('cancel-in-progress: false', 'cancel-in-progress: true', 1), cache),
        ('a missing shard', workflow.replace('shard: [1, 2, 3, 4]', 'shard: [1, 2, 3, 3]', 1), cache),
        ('an unassigned gate', workflow.replace(' && matrix.shard == 1', '', 1), cache),
        ('an unreachable gate', workflow.replace('matrix.shard == 1', 'matrix.shard == 5', 1), cache),
        ('an early aggregate', workflow.replace('needs: [grammar, test]', 'needs: [grammar]', 1), cache),
        ('an aggregate hiding failure', workflow.replace('test "$SHARDS_RESULT" = success', 'true', 1), cache),
        ('colliding shard cache keys', workflow, cache.replace('${{ inputs.namespace }}', '')),
    ]
    for label, changed, changed_cache in mutations:
        if (changed, changed_cache) == (workflow, cache) or not validate(changed, changed_cache):
            print('FAIL control did not detect ' + label)
            return 1
    print('ok: complete platform/shard partition, aggregate verdict and cache namespaces; eight negative controls')
    return 0


if __name__ == '__main__':
    sys.exit(main())
