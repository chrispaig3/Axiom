#!/usr/bin/env python3
"""Probe typed interner/binder-summary ownership with actual emitted modules."""
import argparse
import json
import os
from pathlib import Path
import re
import runpy
import shlex
import subprocess
import sys
import tempfile

SUPPORT = runpy.run_path(str(Path(__file__).with_name('emitter-line-buffer.py')))
run_checked = SUPPORT['run_checked']
replace_once = SUPPORT['replace_once']
check_output = SUPPORT['check_output']

BRIDGES = r'''
; Private-copy-only typed field probes; the production sealed boundary stays closed.
(pub :: probeSummaryUnknown (-> BinderSummary Int))
(pub fn (probeSummaryUnknown summary) summary.unknown)
(pub :: probeSummaryBinders (-> BinderSummary InternState))
(pub fn (probeSummaryBinders summary) summary.binders)
(pub :: probeSummaryHeads (-> BinderSummary InternState))
(pub fn (probeSummaryHeads summary) summary.heads)
(pub :: probeSummaryAnswers (-> BinderSummary Ints))
(pub fn (probeSummaryAnswers summary) summary.answers)
(pub :: probeSlotSummaryRoundtrip (-> CG ASTNode Int Int))
(pub fn (probeSlotSummaryRoundtrip cg body cls)
  (if (== cls 2)
    {
      (let summary (binderSummary body))
      (+ (boundIn "x" summary) (headIsLocal cg "global" summary))
    }
    0))
(pub :: probeOwnershipFacts (-> CG ASTNode Int Int Int Int))
(pub fn (probeOwnershipFacts cg node tail cls kept)
  (slotOwnershipFacts cg node tail cls kept))
(pub :: probeAliasUnknown (-> CG Names ASTNode Bool))
(pub fn (probeAliasUnknown cg aliases body)
  (slotAliasUnknown cg aliases body))
(pub :: probePatternCollect (-> InternState ASTNode Int))
(pub fn (probePatternCollect state pat)
  (binderCollectPattern state pat))
(pub :: probePatternAgreement (-> ASTNode Bool))
(pub fn (probePatternAgreement pat)
  {
    (let state internNewTyped)
    (let unknown (binderCollectPattern state pat))
    (let old (patBindersCg pat vecNew))
    (if (== (as old Int) 0)
      (== unknown 1)
      {
        (let oldSet internNewTyped)
        (let mut same (== unknown 0))
        (for i in 0..(vecLen old)
          {
            (let name (vecGet old i))
            (internIntern oldSet name)
            (match (internFind state name)
              ((Some _) 0)
              ((None) (set same false)))
          })
        (&& same (== (internCount state) (internCount oldSet)))
      })
  })
'''


def function(ir, name):
    found = re.search(r'^define [^\n]*@' + re.escape(name) +
                      r'\([^\n]*\)[^\n]*\{\n(.*?)^\}', ir, re.M | re.S)
    if not found:
        raise RuntimeError(f'missing emitted function {name}')
    return found[1]


def call_result(body, callee, suffix=''):
    found = re.search(r'(%\S+) = (?:musttail )?call i64 @' + re.escape(callee) +
                      r'\(' + suffix, body)
    if not found:
        raise RuntimeError(f'missing call to {callee}')
    return found[1]


def cleanup(body, value):
    return body.count(f'call void @axiom_release(i64 {value})')


def check_factory_ir(path):
    ir = path.read_text()
    words = function(ir, 'Internal.Intern$rawInternWordsNew')
    leaf = call_result(words, 'Internal.Raw$rawAlloc')
    if words.count(f'call void @axiom_retain(i64 {leaf})') != 1 or cleanup(words, leaf):
        raise RuntimeError('typed leaf must acquire exactly one ordinary result share')
    factory = function(ir, 'Internal.Intern$rawInternAllocTableTyped')
    header = call_result(factory, 'Internal.Raw$rawAllocMapped', r'i64 32, i64 5\)')
    strings = call_result(factory, 'Vec$vecWithCapacity')
    slots = call_result(factory, 'Internal.Intern$rawInternWordsNew')
    for index, value in ((0, strings), (2, slots)):
        if not re.search(r'@Internal\.Raw\$rawSetWord\(i64 ' + re.escape(header) +
                         ', i64 ' + str(index) + ', i64 ' + re.escape(value) +
                         r', i64 1\)', factory):
            raise RuntimeError(f'factory field{index} lacks its counted store')
        if cleanup(factory, value) != 1:
            raise RuntimeError(f'factory field{index} temporary was parked or over-released')
    if not re.search(r'@Internal\.Raw\$rawSetWord\(i64 ' + re.escape(header) +
                     r', i64 3, i64 ' + re.escape(header) + r', i64 0\)', factory):
        raise RuntimeError('factory self address must remain a scalar nonowning field')
    if factory.count(f'call void @axiom_retain(i64 {header})') != 1 or cleanup(factory, header):
        raise RuntimeError('typed factory must return exactly one acquired header share')
    legacy = function(ir, 'Internal.Intern$rawInternAllocTable')
    if legacy.count('@Internal.Intern$rawInternAllocTableTyped(') != 1 or '@axiom_retain(' in legacy or '@axiom_release(' in legacy:
        raise RuntimeError('legacy raw factory must transfer its one owned result unchanged')
    scalar = function(ir, 'Internal.Intern$rawInternWordOf')
    if not re.search(r'getelementptr i64, ptr %\S+, i64 3', scalar):
        raise RuntimeError('raw accessor must load the explicit self-address scalar')
    if any(op in scalar for op in ('@axiom_retain(', '@axiom_release(', '@axiom_alloc(')):
        raise RuntimeError('raw accessor changed ownership or allocated')
    births = 0
    for name in ('factoryChecks', 'stringOwnerChecks', 'typedRoundtrip'):
        body = function(ir, 'InternalProbeFixture$' + name)
        found = re.findall(r'(%\S+) = call i64 @Intern\$internNewTyped\(', body)
        if len(found) != 1 or cleanup(body, found[0]) != 1:
            raise RuntimeError(f'{name}: typed owner birth lacks exactly one ordinary release')
        births += len(found)
    alias = function(ir, 'InternalProbeFixture$ownedAlias')
    if alias.count('call void @axiom_retain(i64 %state)') != 1:
        raise RuntimeError('owned alias return must acquire exactly one result share')
    return {'typed_factory_children': 2, 'ordinary_fixture_birth_cleanups': births,
            'header_bytes': 32, 'header_map': 5, 'self_word': 3,
            'legacy_wrapper_extra_shares': 0}


def private_stdlib(directory, source_root, intern_source):
    directory.mkdir(parents=True, exist_ok=True)
    for item in (source_root / 'stdlib').iterdir():
        target = directory / item.name
        if item.name == 'Internal':
            target.mkdir(exist_ok=True)
            for helper in item.iterdir():
                destination = target / helper.name
                if helper.name == 'Intern.ax':
                    destination.write_text(intern_source)
                elif not destination.exists():
                    destination.symlink_to(helper, target_is_directory=helper.is_dir())
        elif not target.exists():
            target.symlink_to(item, target_is_directory=item.is_dir())
    return directory


def private_modules(directory, source_root, codegen_source):
    directory.mkdir(parents=True, exist_ok=True)
    for item in (source_root / 'core').iterdir():
        target = directory / item.name
        if item.name == 'codegen.ax':
            target.write_text(codegen_source + BRIDGES)
        elif not target.exists():
            target.symlink_to(item, target_is_directory=item.is_dir())
    return directory


def check_summary_ir(path):
    ir = path.read_text()
    factory = function(ir, 'codegen$binderSummary')
    children = re.findall(r'(%\S+) = call i64 @(?:Intern\$internNewTyped|Vec\$vecNew)\(', factory)
    if len(children) != 3:
        raise RuntimeError('summary factory must construct two interners and one answer vector')
    for child in children:
        if factory.count(f'call void @axiom_retain(i64 {child})') != 1 or cleanup(factory, child) != 1:
            raise RuntimeError('summary factory must transfer each typed child and release its temporary')
    if not re.search(r'store i64 917512, ptr ', factory):
        raise RuntimeError('summary reference map must own words1/2/3, keeping unknown scalar')
    births = {}
    for name, expected in (('argsMayAlias', 1), ('scrutineeReleasable', 1),
                           ('placeScrutHeld', 2), ('emitLetAt', 2),
                           ('letTransferClass', 1), ('letReleasable', 1),
                           ('slotOwnershipFacts', 1), ('slotAliasUnknown', 1),
                           ('tailScrutineeReleasable', 1)):
        body = function(ir, 'codegen$' + name)
        values = re.findall(r'(%\S+) = call i64 @codegen\$binderSummary\(', body)
        if len(values) != expected or any(cleanup(body, value) != 1 for value in values):
            raise RuntimeError(f'{name}: expected {expected} ordinary summary birth cleanups')
        births[name] = len(values)
    consumers = ('escapes escapesSeq escapesArms escapesViaBinders escapesAny mayAlias '
                 'mayAliasArgs callEscapesArg ctorWordFieldsMention wordArgAliases headIsLocal '
                 'boundIn slotStoreCounts slotOwns slotReleasesAtEnd slotScan slotHolds '
                 'slotMayAlias slotAliases slotAliasBinders namesMayAlias').split()
    loops = {}
    for name in consumers:
        body = function(ir, 'codegen$' + name)
        slots = re.findall(r'store i64 %(?:bound|sum), ptr (%\S+)', body)
        if not slots:
            if re.search(r'@axiom_(?:retain|release)\(i64 %(?:bound|sum)\)', body):
                raise RuntimeError(f'{name}: ordinary borrowed summary parameter changed ownership')
            continue
        if len(slots) != 1 or body.count('call void @axiom_retain(i64 %bound)') != 1:
            raise RuntimeError(f'{name}: missing single entry-owned loop summary share')
        slot = slots[0]
        stores = re.findall(r'store i64 (%\S+), ptr ' + re.escape(slot) + r'\b', body)
        loads = re.findall(r'(%\S+) = load i64, ptr ' + re.escape(slot) + r'\b', body)
        released = [value for value in loads if cleanup(body, value) == 1]
        if len(released) != 1:
            raise RuntimeError(f'{name}: loop summary lacks its single ordinary final cleanup')
        for value in stores[1:]:
            if value not in loads or body.count(f'call void @axiom_retain(i64 {value})') or cleanup(body, value):
                raise RuntimeError(f'{name}: loop replacement must preserve the same borrowed summary')
        loops[name] = {'entry': 1, 'replacement_stores': len(stores) - 1,
                       'ordinary_final_releases': len(released)}
    for name, base, slots in [('headIsLocal', 'bound', (2, 3)), ('boundIn', 'sum', (1,))]:
        body = function(ir, 'codegen$' + name)
        roots = re.findall(r'(%\S+) = inttoptr i64 %' + base + r' to ptr', body)
        for slot in slots:
            fields = []
            for root in roots:
                pointers = re.findall(r'(%\S+) = getelementptr i64, ptr ' + re.escape(root)
                                      + r', i64 ' + str(slot) + r'\n', body)
                for pointer in pointers:
                    fields.extend(re.findall(r'(%\S+) = load i64, ptr ' + re.escape(pointer)
                                             + r'\n', body))
            if len(fields) != 1:
                raise RuntimeError(f'{name}: expected one typed summary field{slot} read')
            value = fields[0]
            taken = body.count(f'call void @axiom_retain(i64 {value})')
            given = cleanup(body, value)
            if taken != given or taken > 1:
                raise RuntimeError(f'{name}: field{slot} takes {taken} shares and retires {given}')
    direct = function(ir, 'codegen$binderCollectArms')
    if '@codegen$patBindersCg(' in direct or '@codegen$binderCollectPattern(' not in direct:
        raise RuntimeError('summary arm walk must collect patterns without temporary Names vectors')
    facts = function(ir, 'codegen$slotOwnershipFacts')
    if not re.search(r'mul i64 2, ', facts) or not re.search(r'add i64 1, ', facts):
        raise RuntimeError('slot facts must encode ownership in bit0 and release-at-end in bit1')
    alias = function(ir, 'codegen$slotAliasUnknown')
    flag = call_result(alias, 'codegen$slotAliases')
    if not re.search(r'icmp eq i64 ' + re.escape(flag) + r', 1', alias):
        raise RuntimeError('alias helper must preserve the existing0/1 result as Bool')
    caller = function(ir, 'codegen$emitLetMAt')
    if '@codegen$binderSummary(' in caller or 'binderSummaryForSlot' in caller:
        raise RuntimeError('mutable slot emitter still owns an escaping summary carrier')
    if caller.count('@codegen$slotOwnershipFacts(') != 1 or caller.count('@codegen$slotAliasUnknown(') != 1:
        raise RuntimeError('mutable slot emitter must use both scoped scalar helpers')
    return {'factory_child_cleanups': len(children), 'production_births': births,
            'production_birth_cleanup_total': sum(births.values()),
            'typed_consumers': len(consumers), 'owned_tail_loop_slots': loops,
            'scoped_slot_helper_births': 2, 'escaping_slot_carriers': 0,
            'complete': True}


def internal_raw_effects(axiom, repo, source_root, work, env, current):
    # Independently recorded from the pre-migration API. CI checkouts may
    # contain one commit, so the reference must travel with the test.
    expected = json.loads((repo / 'tests/selfhost/emitter-binder-raw-api.json').read_text())
    public = set(expected)
    if len(public) != 9:
        raise RuntimeError('the legacy raw API reference must cover all nine functions')
    fixture = work / 'raw-api.ax'
    fixture.write_text('(import Intern)\n(:: main Int)\n(fn (main) 0)\n')
    stdlib = private_stdlib(work / 'raw-api-current-stdlib', source_root, current)
    local = dict(env, AXIOM_STDLIB=str(stdlib), AXIOM_STDLIB_PATH=str(stdlib))
    output = work / 'raw-api-current.axsym'
    run_checked([sys.executable, str(repo / 'scripts/lib/internal-probe.py'),
                 '--fixture', 'tests/selfhost/emitter-binder-summary.py', str(axiom),
                 '--diagnostic-format=ai', 'symbols', str(fixture)],
                env=local, stdout=output, stderr=work / 'raw-api-current.stderr')
    rows = {}
    for line in output.read_text().splitlines():
        if not line.startswith('F '):
            continue
        parts = shlex.split(line)
        if not parts[1].startswith('rawIntern') or '/Internal/Intern.ax:' not in parts[2]:
            continue
        parts[1] = 'intern' + parts[1][9:]
        if parts[1] not in public:
            continue
        if parts[1] in rows:
            raise RuntimeError('duplicate internal raw API row: ' + parts[1])
        rows[parts[1]] = {'type': parts[3],
                          'effects': [x for x in parts[4:]
                                      if x.startswith(('#effects=', '#unsafe='))]}
    if set(rows) != public:
        raise RuntimeError(f'incomplete internal raw API census {sorted(public-set(rows))}')
    deltas = {name: {'old': expected[name], 'current': rows[name]}
              for name in public
              if expected[name] != rows[name]}
    if deltas:
        raise RuntimeError('legacy internal raw API type/effect changed: ' + json.dumps(deltas, sort_keys=True))
    return {'unchanged_internal_raw_api': len(public), 'deltas': deltas}


def check(axiom, repo, source_root, work):
    template = repo / 'tests/selfhost/emitter-binder-summary.axp'
    fixture = work / template.with_suffix('.ax').name
    fixture.write_bytes(template.read_bytes())
    expected = template.with_suffix('.out').read_text().splitlines()
    if expected != [f'{i} true' for i in range(1, 105)]:
        raise RuntimeError('update the explicit 104-case assertion count')
    current = (source_root / 'stdlib/Internal/Intern.ax').read_text()
    codegen = (source_root / 'core/codegen.ax').read_text()
    env = dict(os.environ, AXIOM_PATH=str(source_root / 'core'))
    env['PATH'] = '/opt/homebrew/opt/llvm/bin:' + env.get('PATH', '')
    report = {'source_root': str(source_root), 'builder': str(axiom), 'positive': [], 'negative': []}
    run_checked([str(axiom), '--diagnostic-format=ai', 'fmt', '--check', str(fixture)],
                env=env, stdout=work / 'fixture.fmt.stdout', stderr=work / 'fixture.fmt.stderr')

    def build_run(label, level, source, emitter=codegen, negative=()):
        stdlib = private_stdlib(work / (label + '-stdlib'), source_root, source)
        modules = private_modules(work / (label + '-modules/core'), source_root, emitter)
        local = dict(env, AXIOM_PATH=str(modules), AXIOM_STDLIB=str(stdlib), AXIOM_STDLIB_PATH=str(stdlib))
        binary = work / label
        run_checked([sys.executable, str(repo / 'scripts/lib/internal-probe.py'),
                     '--fixture', 'tests/selfhost/emitter-binder-summary.py', str(axiom),
                     '--diagnostic-format=ai', 'build', str(fixture),
                     '--opt', str(level), '--alloc-poison', '--emit-llvm', '-o', str(binary)],
                    env=local, stdout=work / (label + '.build.stdout'),
                    stderr=work / (label + '.build.stderr'))
        output = work / (label + '.stdout')
        error = work / (label + '.stderr')
        run_checked([str(binary)], env=local, stdout=output, stderr=error, timeout=30)
        failures = check_output(output, expected, required_failures=negative)
        growth = re.fullmatch(r'factory-soak-growth (-?\d+) (-?\d+)\n'
                              r'summary-soak-growth (-?\d+) (-?\d+) (-?\d+)\n'
                              r'slot-summary-soak-growth (-?\d+) (-?\d+) (-?\d+)\n', error.read_text())
        if growth is None:
            raise RuntimeError(f'{label}: missing exact factory/summary storage measurements')
        row = {'label': label, 'failed_cases': sorted(failures),
               'soak_growth': dict(zip(('typed_factory', 'legacy_factory', 'direct_summary',
                                       'nested_summary', 'unknown_summary', 'slot_summary',
                                       'optional_summary', 'no_optional_summary'),
                                      map(int, growth.groups())))}
        if not negative:
            row['factory_ir'] = check_factory_ir(binary.with_suffix('.ll'))
            row['summary_ir'] = check_summary_ir(binary.with_suffix('.ll'))
        return row

    for level in (0, 2):
        row = build_run(f'positive-O{level}', level, current)
        report['positive'].append(row)
        print(f'ok   typed interner and binder summary: 104 cases at -O{level} with allocation poisoning; all 8 soaks0', flush=True)
    no_map = replace_once(current, '(let it (rawAllocMapped 32 5))',
                          '(let it (rawAllocMapped 32 0))', 'missing owning-child map')
    duplicate_owner = replace_once(current, '      (rawSetWord it 3 it)\n      (as it InternalInternState)',
                                   '      (rawSetWord it 3 it)\n      (__retain it)\n      (as it InternalInternState)',
                                   'duplicate initial header share')
    wrong_cap = replace_once(current, '      (rawSetWord it 1 cap)\n',
                             '      (rawSetWord it 1 (/ cap 2))\n',
                             'wrong capacity metadata with unchanged allocated storage')
    for label, source, failures in (
            ('missing-owner-map', no_map, (4, 29, 33, 36, 38, 39)),
            ('duplicate-owner-share', duplicate_owner, (1, 28, 33, 38, 39)),
            ('wrong-capacity', wrong_cap, (2, 28))):
        row = build_run(label, 0, source, negative=failures)
        report['negative'].append(row)
        print('ok   negative probe ' + label + ': cases ' + ','.join(map(str, row['failed_cases'])) + ' fail', flush=True)
    wrong_memo = replace_once(codegen, '(vecPush answers a)', '(vecPush answers 0)',
                              'incorrect cached local-head answer')
    wrong_pattern = replace_once(codegen, '              (binderCollectPatternHead set (nodeAChild pat)))',
                                 '              (binderCollectPattern set (nodeAChild pat)))',
                                 'incorrectly intern constructor head')
    no_pattern = replace_once(codegen, '(let unknown (binderCollectPattern set (nodeAChild arm)))',
                              '(let unknown 0)', 'omit match arm pattern binders')
    raw_birth = replace_once(codegen, '(let set internNewTyped)',
                              '(let set (as (as internNewTyped Int) InternState))',
                              'erase a fresh interner birth before restoring the typed child')
    raw_birth = replace_once(raw_birth, '(pub fn (binderSummary e)',
                              ';@axiom:effect(unsafe)\n(pub fn (binderSummary e)',
                              'declare the test-only negative forgery boundary')
    for label, source, failures in (
            ('wrong-memo', wrong_memo, (49,)),
            ('constructor-head-is-binder', wrong_pattern, (78, 79, 80, 89)),
            ('omitted-arm-binders', no_pattern, (42,)),
            ('erased-summary-child-birth', raw_birth, (44, 58, 60, 62, 68, 70))):
        row = build_run(label, 0, current, source, failures)
        report['negative'].append(row)
        print('ok   negative probe ' + label + ': cases ' + ','.join(map(str, row['failed_cases'])) + ' fail', flush=True)
    report['internal_raw_api'] = internal_raw_effects(axiom, repo, source_root, work, env, current)
    (work / 'summary.json').write_text(json.dumps(report, indent=2) + '\n')
    print('ok   legacy internal raw API types/effects unchanged', flush=True)


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
        with tempfile.TemporaryDirectory(prefix='axiom-binder-summary-') as directory:
            check(args.axiom.resolve(), repo, args.source_root.resolve(), Path(directory))


if __name__ == '__main__':
    main()
