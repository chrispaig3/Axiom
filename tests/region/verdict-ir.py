#!/usr/bin/env python3
"""Compare S4 emissions while checking every normalised ownership dependency.

Run with --selftest for the focused positive and negative controls, or supply
ablated and enabled IR files. The gate reads the printed residual COUNT.
"""
import re, subprocess, sys
from collections import Counter
def literal_result_guards(lines):
    literals, guards = set(), set()
    for i, line in enumerate(lines):
        if line.startswith('define '):
            literals.clear()
        literal = re.match(r'\s*(%[.\w]+) = ptrtoint .*@strhdr_\d+\b', line)
        if literal:
            literals.add(literal.group(1))
        retain = re.fullmatch(r'\s*call void @axiom_retain\(i64 (%[.\w]+)\)\s*', line)
        if not retain or i == 0 or i + 1 == len(lines):
            continue
        call = re.fullmatch(r'\s*(%[.\w]+) = (?:tail )?call i64 @[^ (]+\((.*)\)\s*', lines[i - 1])
        release = re.fullmatch(r'\s*call void @axiom_release\(i64 (%[.\w]+)\)\s*', lines[i + 1])
        if (call and release and retain.group(1) == call.group(1)
                and release.group(1) in literals
                and re.search(r'\bi64 ' + re.escape(release.group(1)) + r'(?=[,)])', call.group(2) + ')')):
            guards.add(i)
    return guards

# A copied result needs this guard; unrelated retains must survive.
probe = ['define i64 @probe(i64 %heap) {',
         '  %lit = ptrtoint ptr @strhdr_1 to i64',
         '  %result = call i64 @forward(i64 %heap, i64 %lit)',
         '  call void @axiom_retain(i64 %result)',
         '  call void @axiom_release(i64 %lit)', '}']
assert literal_result_guards(probe) == {3}
for index, replacement in [(2, '  %result = call i64 @forward(i64 %heap)'),
                           (3, '  call void @axiom_retain(i64 %heap)'),
                           (4, '  call void @axiom_release(i64 %heap)'),
                           (4, '  ret i64 %result')]:
    mutant = probe.copy()
    mutant[index] = replacement
    assert not literal_result_guards(mutant), (index, replacement)

def call_key(function, callee, args):
    args = re.sub(r"%t\d+|%\.\w*\d+", "%RN", args)
    return function, callee, args

def tail_calls(lines):
    calls, function = Counter(), None
    for line in lines:
        start = re.match(r'define [^@]*@([^ (]+)', line)
        if start:
            function = start.group(1)
        call = re.fullmatch(r'\s*%[.\w]+ = musttail call i64 @([^ (]+)\((.*)\)\s*', line)
        if call:
            calls[call_key(function, *call.groups())] += 1
    return calls

def literal_merge_stores(lines, peer_tails):
    """Only a literal-release-induced call-to-tail flip's result stores.

    Require the peer's matching musttail call, a released literal
    argument, the exact three-instruction store of the call's result,
    and a slot loaded on the function's return dependency graph.
    """
    skip, function, start = set(), None, 0
    for end, line in enumerate(lines):
        head = re.match(r'define [^@]*@([^ (]+)', line)
        if head:
            function, start = head.group(1), end
        if line.strip() != '}' or function is None:
            continue
        body = lines[start:end + 1]
        defs, roots = {}, []
        for text in body:
            definition = re.match(r'\s*(%[.\w]+) = (.*)', text)
            if definition:
                defs[definition.group(1)] = definition.group(2)
            ret = re.fullmatch(r'\s*ret i64 (%[.\w]+)\s*', text)
            if ret:
                roots.append(ret.group(1))
        seen = set()
        while roots:
            value = roots.pop()
            if value not in seen:
                seen.add(value)
                roots.extend(re.findall(r'%[.\w]+', defs.get(value, '')))
        slots = {match.group(1) for value in seen
                 if (match := re.fullmatch(r'inttoptr i64 (%[.\w]+) to ptr', defs.get(value, '')))}
        literals = set()
        for i in range(start, end - 4):
            literal = re.match(r'\s*(%[.\w]+) = ptrtoint .*@strhdr_\d+\b', lines[i])
            if literal:
                literals.add(literal.group(1))
            call = re.fullmatch(r'\s*(%[.\w]+) = call i64 @([^ (]+)\((.*)\)\s*', lines[i])
            release = re.fullmatch(r'\s*call void @axiom_release\(i64 (%[.\w]+)\)\s*', lines[i + 1])
            base = re.fullmatch(r'\s*(%[.\w]+) = inttoptr i64 (%[.\w]+) to ptr\s*', lines[i + 2])
            field = re.fullmatch(r'\s*(%[.\w]+) = getelementptr i64, ptr (%[.\w]+), i64 0\s*', lines[i + 3])
            store = re.fullmatch(r'\s*store i64 (%[.\w]+), ptr (%[.\w]+)\s*', lines[i + 4])
            if not all((call, release, base, field, store)):
                continue
            key = call_key(function, call.group(2), call.group(3))
            if (peer_tails[key] and release.group(1) in literals
                    and re.search(r'\bi64 ' + re.escape(release.group(1)) + r'(?=[,)])', call.group(3) + ')')
                    and base.group(2) in slots and field.group(2) == base.group(1)
                    and store.groups() == (call.group(1), field.group(1))):
                skip.update(range(i + 2, i + 5))
                peer_tails[key] -= 1
        function = None
    return skip

# A return slot and its peer tail call are both required; arbitrary
# field stores and unrelated call results stay in the comparison.
merge_probe = ['define i64 @probe(i64 %heap) {',
               '  %lit = ptrtoint ptr @strhdr_1 to i64',
               '  %result = call i64 @forward(i64 %heap, i64 %lit)',
               '  call void @axiom_release(i64 %lit)',
               '  %p = inttoptr i64 %slot to ptr',
               '  %q = getelementptr i64, ptr %p, i64 0',
               '  store i64 %result, ptr %q',
               '  %p2 = inttoptr i64 %slot to ptr',
               '  %q2 = getelementptr i64, ptr %p2, i64 0',
               '  %answer = load i64, ptr %q2', '  ret i64 %answer', '}']
peer = Counter({call_key('probe', 'forward', 'i64 %heap, i64 %lit'): 1})
assert literal_merge_stores(merge_probe, peer.copy()) == {4, 5, 6}
assert not literal_merge_stores(merge_probe, Counter())
for index, replacement in [(6, '  store i64 %heap, ptr %q'),
                           (5, '  %q = getelementptr i64, ptr %p, i64 1'),
                           (3, '  call void @axiom_release(i64 %heap)'),
                           (10, '  ret i64 %heap')]:
    mutant = merge_probe.copy()
    mutant[index] = replacement
    assert not literal_merge_stores(mutant, peer.copy()), (index, replacement)

def function_bodies(lines):
    bodies, name, start = {}, None, 0
    for end, line in enumerate(lines):
        head = re.match(r'define [^@]*@([^ (]+)', line)
        if head:
            name, start = head.group(1), end
        if line.strip() == '}' and name is not None:
            bodies[name] = (start, lines[start:end + 1])
            name = None
    return bodies


def literal_words(body):
    return {m.group(1): m.group(2) for line in body
            if (m := re.match(r'\s*(%[.\w]+) = ptrtoint .*(@strhdr_\d+)\b', line))}


def literal_call_key(function, callee, args, literals):
    args = re.sub(r'%[.\w]+', lambda m: literals.get(m.group(), m.group()), args)
    return call_key(function, callee, args)


def literal_call_sites(function, body):
    counts, sites, literals = Counter(), {}, literal_words(body)
    for i, line in enumerate(body):
        call = re.fullmatch(r'\s*(%[.\w]+) = (musttail )?call i64 @([^ (]+)\((.*)\)\s*', line)
        if call:
            key = literal_call_key(function, call.group(3), call.group(4), literals)
            sites[i] = (call.group(1), (key, counts[key]), bool(call.group(2)), call.group(4))
            counts[key] += 1
    return sites


def literal_call_flips(function, body, peer):
    """Pair calls by function, callee, literal arguments and occurrence."""
    tails = {key for i, (result, key, tail, _) in literal_call_sites(function, peer).items()
             if tail and i + 1 < len(peer) and peer[i + 1].strip() == 'ret i64 ' + result}
    literals, calls = literal_words(body), []
    for i, (result, key, tail, args) in literal_call_sites(function, body).items():
        if tail or key not in tails or i + 1 == len(body):
            continue
        release = re.fullmatch(r'\s*call void @axiom_release\(i64 (%[.\w]+)\)\s*', body[i + 1])
        if (release and release.group(1) in literals
                and re.search(r'\bi64 ' + re.escape(release.group(1)) + r'(?=[,)])', args + ')')):
            calls.append((i, result, key))
    return calls


def literal_tail_dependents(lines, peer_lines):
    """Follow a proven tail flip through a collapsed phi or moved local cleanup."""
    skip, rewrite = set(), {}
    peers = function_bodies(peer_lines)

    def definitions(body):
        return {m.group(1): m.group(2) for line in body
                if (m := re.match(r'\s*(%[.\w]+) = (.*)', line))}

    def return_dependencies(body, defs):
        roots = [m.group(1) for line in body
                 if (m := re.fullmatch(r'\s*ret i64 (%[.\w]+)\s*', line))]
        seen = set()
        while roots:
            value = roots.pop()
            if value not in seen:
                seen.add(value)
                roots.extend(re.findall(r'%[.\w]+', defs.get(value, '')))
        return seen

    def return_slot(pointer, defs, returned):
        field = re.fullmatch(r'getelementptr i64, ptr (%[.\w]+), i64 0', defs.get(pointer, ''))
        base = field and re.fullmatch(r'inttoptr i64 (%[.\w]+) to ptr', defs.get(field.group(1), ''))
        slot = base and re.fullmatch(r'ptrtoint ptr (%[.\w]+) to i64', defs.get(base.group(1), ''))
        if slot and base.group(1) in returned and defs.get(slot.group(1)) == 'alloca i64':
            return slot.group(1)
        return None

    for function, (start, body) in function_bodies(lines).items():
        if function not in peers:
            continue
        peer = peers[function][1]
        defs, peer_defs = definitions(body), definitions(peer)
        returned, peer_returned = return_dependencies(body, defs), return_dependencies(peer, peer_defs)
        uses = Counter(re.findall(r'%[.\w]+', ''.join(body)))
        peer_uses = Counter(re.findall(r'%[.\w]+', ''.join(peer)))
        params = set(re.findall(r'\bi64 (%[.\w]+)', body[0]))
        labels, label = [], None
        for line in body:
            match = re.fullmatch(r'([.\w]+):\s*', line)
            if match:
                label = '%' + match.group(1)
            labels.append(label)

        # The released call's result joins one surviving parameter. Its peer
        # returns from that call, stores the parameter in the same return slot,
        # and therefore needs no phi. Change only that proven store operand.
        for call_i, result, _ in literal_call_flips(function, body, peer):
            branch = re.fullmatch(r'\s*br label (%[.\w]+)\s*', body[call_i + 2])
            if not branch:
                continue
            for i, line in enumerate(body[:-3]):
                phi = re.fullmatch(r'\s*(%[.\w]+) = phi i64 \[ (%[.\w]+), (%[.\w]+) \], \[ (%[.\w]+), (%[.\w]+) \]\s*', line)
                if not phi or labels[i] != branch.group(1):
                    continue
                incoming = [(phi.group(2), phi.group(3)), (phi.group(4), phi.group(5))]
                if (result, labels[call_i]) not in incoming:
                    continue
                survivors = [pair for pair in incoming if pair != (result, labels[call_i])]
                if len(survivors) != 1:
                    continue
                survivor, _ = survivors[0]
                store = re.fullmatch(r'\s*store i64 (%[.\w]+), ptr (%[.\w]+)\s*', body[i + 3])
                if not store or store.group(1) != phi.group(1) or uses[phi.group(1)] != 2 or survivor not in params:
                    continue
                slot = return_slot(store.group(2), defs, returned)
                peers_storing = [m for text in peer
                                 if (m := re.fullmatch(r'\s*store i64 (%[.\w]+), ptr (%[.\w]+)\s*', text))
                                 and m.group(1) == survivor
                                 and return_slot(m.group(2), peer_defs, peer_returned) == slot]
                if slot is not None and len(peers_storing) == 1:
                    rewrite[start + i + 3] = body[i + 3].replace('store i64 ' + phi.group(1) + ',',
                                                              'store i64 ' + survivor + ',')

        # A tail return cleans its local cell before the call. The peer cleans
        # that same cell at its ordinary return. The extra load feeds only the
        # removed release; no observed value or arbitrary load is normalised.
        flipped = {key for _, _, key in literal_call_flips(function, peer, body)}
        sites = literal_call_sites(function, body)
        for i in range(len(body) - 3):
            load = re.fullmatch(r'\s*(%[.\w]+) = load i64, ptr (%[.\w]+)\s*', body[i])
            call = re.fullmatch(r'\s*(%[.\w]+) = musttail call i64 @([^ (]+)\((.*)\)\s*', body[i + 2])
            if not load or not call or defs.get(load.group(2)) != 'alloca i64' or uses[load.group(1)] != 2:
                continue
            if (body[i + 1].strip() != 'call void @axiom_release(i64 ' + load.group(1) + ')'
                    or body[i + 3].strip() != 'ret i64 ' + call.group(1)
                    or sites[i + 2][1] not in flipped):
                continue
            for j in range(len(peer) - 2):
                other = re.fullmatch(r'\s*(%[.\w]+) = load i64, ptr (%[.\w]+)\s*', peer[j])
                if (other and other.group(2) == load.group(2) and peer_defs.get(other.group(2)) == 'alloca i64'
                        and peer_uses[other.group(1)] == 2
                        and peer[j + 1].strip() == 'call void @axiom_release(i64 ' + other.group(1) + ')'
                        and re.fullmatch(r'\s*ret i64 (%[.\w]+)\s*', peer[j + 2])):
                    skip.add(start + i)
    return skip, rewrite


# A literal-tail flip removes one phi input but leaves its return-slot store.
join_old = '''define i64 @join(i64 %value, i64 %heap) {
  %slot = alloca i64
  %word = ptrtoint ptr %slot to i64
  br i1 true, label %take, label %keep
take:
  %lit = ptrtoint ptr @strhdr_1 to i64
  %answer = call i64 @forward(i64 %heap, i64 %lit)
  call void @axiom_release(i64 %lit)
  br label %join
keep:
  call void @axiom_retain(i64 %value)
  br label %join
join:
  %joined = phi i64 [ %answer, %take ], [ %value, %keep ]
  %p = inttoptr i64 %word to ptr
  %q = getelementptr i64, ptr %p, i64 0
  store i64 %joined, ptr %q
  %p2 = inttoptr i64 %word to ptr
  %q2 = getelementptr i64, ptr %p2, i64 0
  %result = load i64, ptr %q2
  ret i64 %result
}
'''.splitlines(keepends=True)
join_new = ''.join(join_old).replace(
    '  %answer = call i64 @forward(i64 %heap, i64 %lit)\n  call void @axiom_release(i64 %lit)\n  br label %join\n',
    '  %answer = musttail call i64 @forward(i64 %heap, i64 %lit)\n  ret i64 %answer\n').replace(
    '  %joined = phi i64 [ %answer, %take ], [ %value, %keep ]\n', '').replace(
    'store i64 %joined,', 'store i64 %value,').splitlines(keepends=True)
store_index = join_old.index('  store i64 %joined, ptr %q\n')
assert literal_tail_dependents(join_old, join_new) == (set(), {store_index: '  store i64 %value, ptr %q\n'})


def changed(lines, old, new):
    text = ''.join(lines)
    assert text.count(old) == 1, old
    return text.replace(old, new).splitlines(keepends=True)


for side, old, new in [
    (0, 'axiom_release(i64 %lit)', 'axiom_release(i64 %heap)'),
    (1, 'musttail call', 'call'),
    (1, 'ret i64 %answer', 'ret i64 %heap'),
    (0, '[ %answer, %take ]', '[ %heap, %take ]'),
    (0, 'store i64 %joined,', 'store i64 %heap,'),
    (1, 'store i64 %value,', 'store i64 %heap,'),
    (0, '%q = getelementptr i64, ptr %p, i64 0', '%q = getelementptr i64, ptr %p, i64 1'),
    (1, '%q = getelementptr i64, ptr %p, i64 0', '%q = getelementptr i64, ptr %p, i64 1'),
    (0, 'ret i64 %result', 'ret i64 %heap'),
    (0, '  ret i64 %result', '  call void @axiom_retain(i64 %joined)\n  ret i64 %result'),
    (1, '@join(', '@other('),
    (1, '@strhdr_1', '@strhdr_2'),
]:
    pair = [join_old, join_new]
    pair[side] = changed(pair[side], old, new)
    assert literal_tail_dependents(*pair) == (set(), {}), (side, old, new)

# A release-only local load moves before a tail call. The ordinary return
# must clean the same local cell, and the loaded value may have no other use.
cleanup_old = '''define i64 @cleanup(i64 %heap) {
  %cell = alloca i64
  %lit = ptrtoint ptr @strhdr_1 to i64
  %answer = call i64 @forward(i64 %heap, i64 %lit)
  call void @axiom_release(i64 %lit)
  %done = load i64, ptr %cell
  call void @axiom_release(i64 %done)
  ret i64 %answer
}
'''.splitlines(keepends=True)
cleanup_new = '''define i64 @cleanup(i64 %heap) {
  %cell = alloca i64
  %lit = ptrtoint ptr @strhdr_1 to i64
  %early = load i64, ptr %cell
  call void @axiom_release(i64 %early)
  %answer = musttail call i64 @forward(i64 %heap, i64 %lit)
  ret i64 %answer
}
'''.splitlines(keepends=True)
load_index = cleanup_new.index('  %early = load i64, ptr %cell\n')
assert literal_tail_dependents(cleanup_new, cleanup_old) == ({load_index}, {})
for side, old, new in [
    (0, 'axiom_release(i64 %early)', 'axiom_release(i64 %heap)'),
    (0, 'ret i64 %answer', 'ret i64 %early'),
    (0, 'ptr %cell\n  call', 'ptr %heap\n  call'),
    (0, '@forward(', '@other('),
    (0, '@strhdr_1', '@strhdr_2'),
    (1, '  call void @axiom_release(i64 %lit)\n', ''),
    (1, '  call void @axiom_release(i64 %done)\n', ''),
    (1, 'ret i64 %answer', 'ret i64 %done'),
    (1, 'ptr %cell\n  call', 'ptr %heap\n  call'),
]:
    pair = [cleanup_new, cleanup_old]
    pair[side] = changed(pair[side], old, new)
    assert literal_tail_dependents(*pair) == (set(), {}), (side, old, new)

unrelated = changed(cleanup_new, '  %early = load', '  %other = load i64, ptr %cell\n  %early = load')
assert literal_tail_dependents(unrelated, cleanup_old) == ({load_index + 1}, {})
# Repeated calls to the same callee and literal are paired by occurrence;
# the earlier ordinary call does not hide the later tail flip.
repeated = '  %earlier = call i64 @forward(i64 %heap, i64 %lit)\n  call void @axiom_release(i64 %lit)\n'
old_twice = changed(cleanup_old, '  %answer = call', repeated + '  %answer = call')
new_twice = changed(cleanup_new, '  %early = load', repeated + '  %early = load')
assert literal_tail_dependents(new_twice, old_twice) == ({load_index + 2}, {})
assert literal_tail_dependents(new_twice, cleanup_old) == (set(), {})


def norm(p, peer):
    out = []
    lines = open(p, encoding="utf-8", errors="replace").readlines()
    dependent_loads, rewrites = literal_tail_dependents(lines, peer)
    guards = literal_result_guards(lines) | literal_merge_stores(lines, tail_calls(peer)) | dependent_loads
    for i, L in enumerate(lines):
        if i in guards or "call void @axiom_release" in L:
            continue
        L = rewrites.get(i, L)
        L = re.sub(r"%t\d+", "%tN", L)
        L = re.sub(r"%\.\w*\d+", "%RN", L)
        L = re.sub(r"\.L+\d+", ".LN", L)
        out.append(L)
    return out
if sys.argv[1:] == ['--selftest']:
    print('ok   S4 IR comparison: literal-call, phi-store and cleanup-load controls')
    sys.exit(0)
if len(sys.argv) != 3:
    sys.exit('usage: verdict-ir.py --selftest | ABLATED.ll ENABLED.ll')

a, b = norm(sys.argv[1], open(sys.argv[2]).readlines()), norm(sys.argv[2], open(sys.argv[1]).readlines())
import tempfile, os
fa = tempfile.NamedTemporaryFile("w", delete=False); fa.write("".join(a)); fa.close()
fb = tempfile.NamedTemporaryFile("w", delete=False); fb.write("".join(b)); fb.close()
r = subprocess.run(["diff", fa.name, fb.name], capture_output=True, text=True)
os.unlink(fa.name); os.unlink(fb.name)
less, more = Counter(), Counter()
for L in r.stdout.split("\n"):
    if L.startswith("< "):
        less[L[2:]] += 1
    elif L.startswith("> "):
        more[L[2:]] += 1
resid = list((less - more).elements()) + list((more - less).elements())
voc = re.compile(r"musttail|br label|ret i64|@@line|^\.LN:|phi i64| = call i64 @|@__axiom_(line|filen)|icmp uge i64 %li,")
bad = [L for L in resid if not voc.search(L)]
for L in bad[:10]:
    print("RESID: " + L)
print("COUNT: %d" % len(bad))
