#!/usr/bin/env bash
# Assert that the call graph `symbols --calls` prints explains the
# effect rows printed beside it, and that asking for it changes nothing
# for anyone who did not.
#
# `inferEffects` (self_host/typecheck.ax) is a monotone fixpoint over the
# call graph. It resolves every reference site to a `FnEnt` and folds
# that entry's effect row into the caller's. `tcNoteCall` records each
# resolved edge and `#calls=` prints it, so a reader can see which call
# put an effect in a row.
#
# The gate asserts four properties:
#
#   Containment. For every declaration, every effect of every callee is
#   an effect of the caller, except `Unsafe` on a callee marked
#   `#unsafe=trusted`: its boundary ends that obligation (MM-EXEC-9d).
#   If this fails, `#calls=` and `#effects=` disagree, and an
#   `Agent.Policy` reading either learns something false.
#
#   Totality. Every row whose effect set was inferred carries at least
#   one edge accounting for it. The shapes that legitimately have none
#   are listed at the totality check. One is a row whose whole effect
#   set is `Mut`: a field `set` is the one effect-bearing form that is
#   not a call, so `(fn (f c x) { (set c.v x) 0 })` prints
#   `#effects=Mut` and no `#calls=`. Only the exact set `{Mut}` is
#   excused. `Alloc,Mut` with no edge is still an effect from nowhere.
#
#   Silence by default. Without `--calls`, no row carries the key.
#   `check-tools-selfhost.sh` compares `tests/tools/symbols-zoo.golden`
#   byte for byte, so an unasked key would churn that golden on every
#   stdlib edit. This follows `--builtins`: content selection on
#   `symbols`, not a build mode.
#
#   Grounding. Every inferred IO reaches a primitive through the graph.
#
# It runs with `--builtins` because an operator is a `FnEnt`, so `+` and
# `==` are real call edges. Without their rows, containment would skip
# hundreds of edges. `__alloc` matters most: it is a builtin, and it
# puts `Alloc` in the row beside it.
#
# Trait implementations do not resolve to a row. `walkCallHead` cannot
# pick an implementation without the dispatch argument's type, so it
# unions every implementation and records each as an edge. Those edges
# name `Trait#Type#method`, and `symbols` prints no row for a generated
# name (`smGenerated`, symbols.ax), so an impl method body has no AXSYM
# row. That gap is `symbols.ax`'s to close. The number of distinct such
# names is printed and capped, so the gap cannot grow unnoticed.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

stdlib_prefix="$repo_root/stdlib/"

# `--calls` is a flag, and the driver's flag table is closed: an unknown
# flag exits 2 before printing anything. Probe it first, so a compiler
# without the flag fails with a message instead of dying silently under
# `set -e` on the first `symbols` run.
printf '(:: main Int)\n\n(fn (main) 0)\n' > "$work/flagprobe.ax"
set +e
"$axc" symbols --calls --diagnostic-format=ai "$work/flagprobe.ax" >/dev/null 2>&1
flagrc=$?
set -e
if (( flagrc == 2 )); then
  echo "FAIL: the compiler under test rejects \`symbols --calls\` (exit 2, the"
  echo "      driver's closed flag table). That flag is the whole input to"
  echo "      this gate; a compiler built from before it landed cannot"
  echo "      satisfy anything below."
  exit 1
fi
if (( flagrc != 0 )); then
  echo "FAIL: \`symbols --calls\` exited $flagrc on a three-line program that"
  echo "      declares nothing but \`main\`. Something below would have"
  echo "      reported an empty stream as a passing library."
  exit 1
fi

# The probe imports every stdlib module, built as check-agent-policy
# builds it: the module list is derived from the tree, so a new module
# is covered at once. It lives in its own directory because module
# resolution searches the entry file's own directory first.
: > "$work/modules"
for f in stdlib/*.ax stdlib/*/*.ax; do
  [[ -e "$f" ]] || continue
  rel="${f#stdlib/}"; dir="$(dirname "$rel")"
  base="$(basename "$rel" .ax)"; base="${base%%.*}"
  if [[ "$dir" == "." ]]; then printf '%s\n' "$base" >> "$work/modules"
  else printf '%s.%s\n' "${dir//\//.}" "$base" >> "$work/modules"; fi
done
LC_ALL=C sort -u -o "$work/modules" "$work/modules"

modcount=$(wc -l < "$work/modules" | tr -d ' ')
if (( modcount < 15 )); then
  echo "FAIL: derived only $modcount stdlib modules from the tree; there were 19 on 2026-08-24"
  echo "      (a derivation that finds nothing imports nothing and would pass every check below)"
  exit 1
fi

{
  while read -r m; do printf '(import %s)\n\n' "$m"; done < "$work/modules"
  printf '(:: main Int)\n\n(fn (main) 0)\n'
} > "$work/probe.ax"

( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" \
    "$axc" --diagnostic-format=ai symbols --calls --builtins probe.ax ) \
  > "$work/calls" 2> "$work/calls.err"

( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" \
    "$axc" --diagnostic-format=ai symbols probe.ax ) \
  > "$work/plain" 2> "$work/plain.err"

rows=$(grep -c '^F ' "$work/calls" || true)
edged=$(grep -c '#calls=' "$work/calls" || true)
if (( rows < 400 )); then
  echo "FAIL: the probe listed only $rows declarations; the floor is 400 (600 today)"
  echo "      (a probe that resolves nothing lists nothing and would pass every check below)"
  exit 1
fi
if (( edged < 300 )); then
  echo "FAIL: only $edged rows carry #calls=; the floor is 300 (413 today)"
  echo "      (a graph with no edges satisfies containment vacuously)"
  exit 1
fi
echo "ok   the probe imports $modcount stdlib modules: $rows rows, $edged carrying edges"

echo
echo "== silence: without --calls, nothing carries the key =="
if grep -q '#calls=' "$work/plain"; then
  echo "FAIL: \`symbols\` emitted #calls= without being asked, which puts an"
  echo "      edge list into tests/tools/symbols-zoo.golden and therefore into"
  echo "      the diff of every future stdlib edit:"
  { grep '#calls=' "$work/plain" || true; } | sed 's/^/     /' | head -5
  exit 1
fi
echo "ok   the default stream is unchanged by this feature"

echo
echo "== containment: a callee's effects are its caller's effects =="
# `Trait#Type#method` edges have no row of their own (see the header).
# Their distinct count is printed, and capped at 12, so the symbols.ax
# gap growing fails here and the gap closing reads as 0.
python3 - "$work/calls" <<'PY' > "$work/contain.out" || { cat "$work/contain.out"; exit 1; }
import re, sys
rows = {}
for line in open(sys.argv[1]):
    if not line.startswith('F '):
        continue
    parts = line.split(None, 3)
    name, span = parts[1], parts[2]
    m = re.search(r'#effects=([A-Za-z,]+)', line)
    effs = set(m.group(1).split(',')) if m else set()
    c = re.search(r'#calls=(\S+)', line)
    calls = c.group(1).split(',') if c else []
    if span == '-':
        mod = ''
    else:
        base = span.rsplit(':', 1)[0].rsplit(':', 1)[0].split('/')[-1]
        mod = (base[:-3] if base.endswith('.ax') else base).split('.')[0]
    trusted = '#unsafe=trusted' in line
    key = (mod, name)
    prev = rows.get(key)
    rows[key] = (effs | (prev[0] if prev else set()),
                 calls or (prev[1] if prev else []),
                 trusted or (prev[2] if prev else False))

bare = {}
for (mod, name), v in rows.items():
    bare.setdefault(name, v)

def lookup(callee):
    if '$' in callee:
        mod, b = callee.rsplit('$', 1)
        return rows.get((mod.split('.')[-1], b)) or bare.get(b)
    return bare.get(callee)

violations, rowless = [], []
for (mod, name), (effs, calls, _trusted) in rows.items():
    for callee in calls:
        target = lookup(callee)
        if target is None:
            rowless.append((mod, name, callee))
            continue
        missing = target[0] - effs
        if target[2]:
            missing.discard('Unsafe')
        if missing:
            violations.append((mod, name, callee, ','.join(sorted(missing))))

if violations:
    print("FAIL: these callees perform an effect their caller's row does not carry,")
    print("      so #calls= and #effects= disagree about the same walk:")
    for mod, name, callee, miss in violations[:20]:
        print(f"     {mod}.{name} -> {callee} performs {miss}")
    raise SystemExit(1)

generated = [r for r in rowless if '#' in r[2]]
other = [r for r in rowless if '#' not in r[2]]
if other:
    print("FAIL: these edges name a callee with no AXSYM row, and it is not a")
    print("      trait implementation - the graph names something that does not exist:")
    for mod, name, callee in other[:20]:
        print(f"     {mod}.{name} -> {callee}")
    raise SystemExit(1)

# The bound is on distinct callees, not edges. Each caller of a trait
# method adds one edge per implementation, so an edge bound would
# measure the library's size. The gap is `symbols.ax` emitting no row
# for an impl method body, and its size is the number of distinct names
# (such as `Show#Int#show`) the stream cannot explain. That moves only
# when an implementation is added or the gap closes. The edge count is
# printed but not asserted.
callees = sorted({r[2] for r in generated})
print(f"ok   {len(rows)} rows, every edge resolved, no effect escapes a caller except through a trusted unsafe boundary")
print(f"ok   {len(generated)} edges name a trait implementation, over "
      f"{len(callees)} distinct names, which have no row "
      f"(the open symbols.ax gap, named in this gate's header)")
if len(callees) > 12:
    print(f"FAIL: {len(callees)} distinct rowless trait-impl callees; there were 4 on")
    print( "      2026-08-25. That is not a failure of this change - it is the")
    print( "      symbols.ax gap growing. Re-read the header before raising this.")
    for c in callees[:20]:
        print(f"     {c}")
    raise SystemExit(1)
PY
cat "$work/contain.out"

echo
echo "== totality: an inferred effect has an edge that accounts for it =="
# Rows that legitimately have no edge. The last three are matched on
# the whole `#effects=` value, so a row that also carries another effect
# is still reported.
#
#   1. An `extern` row is constructed: `tcAddExtern` seeds `IO` rather
#      than inferring it. Anchored on the span field, so a meta value
#      spelling `Ffi.ax` cannot inherit the exemption.
#   2. `Mut` alone is the field-`set` form (see the header).
#   3. `Alloc` alone is a constructor application. A constructor adds
#      `Alloc` so that `restrict(no-alloc)` is sound, and
#      `(Error code message "")` puts `Alloc` in `mkError`'s row with no
#      call to point at.
#   4. A syscall number tagged `;@axiom:syscall(...)`, matched on the
#      `#syscall=` meta. `syscallTagEffects` seeds its row from the tag:
#      `sysWaitWordNum` is `Block`, `sysFork` `Spawn`, `sysRandomNum`
#      `Entropy`.
#
# `Alloc,IO` is still reported: a function that allocates and reaches a
# syscall has a call somewhere, and a missing edge there is a finding.
missing=$(awk -v p="$stdlib_prefix" '
  $1 == "F" && index($3, p) == 1 &&
  /#effects=/ && !/#calls=/ &&
  !/#effects=Mut( |$)/ &&
  !/#effects=Alloc( |$)/ &&
  !(/#syscall=/ && /#effects=(Block|Spawn|Entropy)( |$)/) &&
  index($3, p "Ffi.ax:") != 1 { print $2, $3 }' "$work/calls" | LC_ALL=C sort -u || true)
if [[ -n "$missing" ]]; then
  echo "FAIL: these rows carry an inferred effect and no edge explaining it:"
  echo "$missing" | sed 's/^/     /' | head -20
  echo '     either the walk attributed an effect it did not resolve a call'
  echo '     for, or a new construction site seeds an effect row the way'
  echo '     `tcAddExtern` does - in which case name it in this gate.'
  exit 1
fi
echo "ok   every inferred effect row carries an edge, extern, field-set, constructor and tagged-syscall rows excepted"

echo
echo "== negative probes: every assertion can go red =="

# Containment can see a caller whose row is narrower than its callee's.
# The check reads the row shape, so a forged row probes it without
# breaking the compiler.
cat > "$work/forged.axsym" <<'FORGED'
F alpha /x/stdlib/A.ax:1:1-2 "(Int -> Int)" @a #effects=IO
F beta /x/stdlib/A.ax:2:1-2 "(Int -> Int)" @b #calls=A$alpha
FORGED
if python3 - "$work/forged.axsym" <<'PY' >/dev/null 2>&1
import re, sys
rows = {}
for line in open(sys.argv[1]):
    if not line.startswith('F '): continue
    parts = line.split(None, 3); name, span = parts[1], parts[2]
    m = re.search(r'#effects=([A-Za-z,]+)', line)
    effs = set(m.group(1).split(',')) if m else set()
    c = re.search(r'#calls=(\S+)', line)
    calls = c.group(1).split(',') if c else []
    base = span.rsplit(':',1)[0].rsplit(':',1)[0].split('/')[-1]
    mod = (base[:-3] if base.endswith('.ax') else base).split('.')[0]
    rows[(mod, name)] = (effs, calls)
bare = {}
for (m_, n), v in rows.items(): bare.setdefault(n, v)
def lookup(c):
    if '$' in c:
        mod, b = c.rsplit('$',1); return rows.get((mod.split('.')[-1], b)) or bare.get(b)
    return bare.get(c)
for (mod, name), (effs, calls) in rows.items():
    for c in calls:
        t = lookup(c)
        if t and (t[0] - effs): raise SystemExit(1)
raise SystemExit(0)
PY
then
  echo "FAIL negative: a caller narrower than its callee passed containment"
  exit 1
fi
echo "ok   a caller whose row omits a callee's effect fails containment"

# Totality can see an effect with no edge, the Ffi exemption is
# anchored to the span, and the field-set exemption is exactly `{Mut}`:
# zeta is excused, and eta (`Mut` with `Alloc` and no edge) is not.
cat > "$work/tot.axsym" <<'TOT'
F gamma /x/stdlib/B.ax:1:1-2 "(Int -> Int)" @c #effects=IO
F delta /x/stdlib/Ffi.ax:1:1-2 "(Int -> Int)" @d #effects=IO
F epsilon /x/stdlib/C.ax:1:1-2 "(Int -> Int)" @e #effects=IO #calls=Ffi.ax
F zeta /x/stdlib/D.ax:1:1-2 "(Int -> Int)" @f #effects=Mut
F eta /x/stdlib/D.ax:2:1-2 "(Int -> Int)" @g #effects=Alloc,Mut
TOT
hits=$(awk -v p="/x/stdlib/" '
  $1 == "F" && index($3, p) == 1 && /#effects=/ && !/#calls=/ &&
  !/#effects=Mut( |$)/ &&
  index($3, p "Ffi.ax:") != 1 { print $2 }' "$work/tot.axsym" | tr '\n' ' ' || true)
if [[ "$hits" != "gamma eta " ]]; then
  echo "FAIL negative: the totality matcher reported '$hits', wanted exactly 'gamma eta '"
  echo "               (delta is the anchored Ffi exemption; epsilon has an edge"
  echo "                whose VALUE spells Ffi.ax and must not inherit it; zeta"
  echo "                is a field set, Mut alone; eta carries Alloc too)"
  exit 1
fi
echo "ok   totality sees an unexplained effect, the Ffi exemption is anchored, and only {Mut} is a field set"

# Silence can see the key arriving unasked.
printf 'F zeta /x/stdlib/D.ax:1:1-2 "Int" @f #effects=IO #calls=D$eta\n' > "$work/sil.axsym"
if ! grep -q '#calls=' "$work/sil.axsym"; then
  echo "FAIL negative: the silence matcher cannot see #calls= at all"
  exit 1
fi
echo "ok   the silence check can see the key it refuses"

echo
echo "== grounding: every inferred IO reaches a primitive through the graph =="
# Containment says no effect escapes upward. Grounding says every IO
# effect comes from a real origin below: a `__syscallN`, `stdlib/Ffi.ax`,
# or a primitive the compiler registers with `IO`.
#
# Those primitives include `__argc` and `__argv`, since reading the
# command line is input the process did not compute
# (`docs/memory-model.md` MM-EXEC-9a). They also include the spawn and
# join primitives: `@__axiom_par_spawn_proc` is `fork` and `wait4`
# through a syscall the emitter writes, which no walk over `#calls=`
# can reach.
#
# The walk is transitive because the library is several hops deep:
# `writeStr` -> `sysWriteAllFd` -> `sysWriteFd` -> ... -> `__syscall3`.
#
# The origin list is read from `self_host/typecheck.ax`, never copied:
# `regFnEff <name> <type> (builtinEff "IO")`, or `regFnEff2` for a
# primitive with a second effect (a spawn's `Spawn`, a join's `Block`).
# A floor under the count catches a grep that stops matching. The
# `|| true` keeps that floor reachable: under `set -e` and `pipefail`, a
# grep that matched nothing would kill the script with no message.
io_prims="$(grep -E 'regFnEff2? fns "' "$repo_root/self_host/typecheck.ax" \
  | grep 'builtinEff "IO"' \
  | sed -E 's/.*regFnEff2? fns "([^"]*)".*/\1/' | LC_ALL=C sort -u | tr '\n' ',' || true)"
n_io_prims="$(printf '%s' "$io_prims" | tr ',' '\n' | grep -c . || true)"
if [[ "$n_io_prims" -lt 4 ]]; then
  echo "FAIL: only $n_io_prims IO-registering primitive(s) found in self_host/typecheck.ax;"
  echo "      the floor is 4 (8 on 2026-09-03: __argc, __argv and the six spawn/join"
  echo "      primitives). The grep has stopped matching \`regFnEff\`, and a grounding"
  echo "      check with no origins grounds nothing."
  exit 1
fi
echo "     origins: __syscallN, stdlib/Ffi.ax, and $n_io_prims from regFnEff: ${io_prims%,}"
python3 - "$work/calls" "$stdlib_prefix" "$io_prims" <<'PYG' > "$work/ground.out" || { cat "$work/ground.out"; exit 1; }
import re, sys
axsym, prefix = sys.argv[1], sys.argv[2]
IO_PRIMS = {p for p in sys.argv[3].split(",") if p}
rows, spans = {}, {}
for line in open(axsym):
    if not line.startswith('F '):
        continue
    parts = line.split(None, 3)
    name, span = parts[1], parts[2]
    m = re.search(r'#effects=([A-Za-z,]+)', line)
    effs = set(m.group(1).split(',')) if m else set()
    c = re.search(r'#calls=(\S+)', line)
    calls = c.group(1).split(',') if c else []
    if span == '-':
        mod = ''
    else:
        base = span.rsplit(':', 1)[0].rsplit(':', 1)[0].split('/')[-1]
        mod = (base[:-3] if base.endswith('.ax') else base).split('.')[0]
    key = (mod, name)
    prev = rows.get(key)
    rows[key] = (effs | (prev[0] if prev else set()),
                 calls or (prev[1] if prev else []))
    spans.setdefault(key, span)

bare = {}
for k in rows:
    bare.setdefault(k[1], k)

def resolve(callee):
    if '$' in callee:
        mod, b = callee.rsplit('$', 1)
        k = (mod.split('.')[-1], b)
        return k if k in rows else bare.get(b)
    return bare.get(callee)

def grounded(key, seen):
    if key in seen:
        return False
    seen.add(key)
    for callee in rows[key][1]:
        if callee.startswith('__syscall') or callee in IO_PRIMS:
            return True
        nxt = resolve(callee)
        if nxt is None:
            continue
        if spans.get(nxt, '').startswith(prefix + 'Ffi.ax:'):
            return True
        if grounded(nxt, seen):
            return True
    return False

sys.setrecursionlimit(20000)
ungrounded = []
for key, (effs, calls) in rows.items():
    span = spans.get(key, '')
    if 'IO' not in effs or not span.startswith(prefix):
        continue
    if span.startswith(prefix + 'Ffi.ax:'):
        continue
    if not grounded(key, set()):
        ungrounded.append((key, span))

if ungrounded:
    print("FAIL: these rows carry IO but no path through #calls= reaches a")
    print("      `__syscallN`, an `extern`, or a primitive `regFnEff` gives")
    print("      `IO` (%s), so the" % ", ".join(sorted(IO_PRIMS)))
    print("      effect has no origin:")
    for (mod, name), span in ungrounded[:20]:
        print("     %s.%s  %s" % (mod, name, span))
    raise SystemExit(1)

n = sum(1 for k, v in rows.items()
        if 'IO' in v[0] and spans.get(k, '').startswith(prefix))
print("ok   all %d IO-performing library rows reach a syscall, an extern, "
      "or the argument vector" % n)
PYG
cat "$work/ground.out"

echo
echo "check-agent-calls: the graph explains the rows, every inferred effect"
echo "                   has an edge accounting for it, and asking for the"
echo "                   graph changes nothing for anyone who did not"
