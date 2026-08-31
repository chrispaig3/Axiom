#!/usr/bin/env bash
# Assert that the call graph `symbols --calls` prints actually explains
# the effect rows printed beside it, and that asking for it changes
# nothing for anyone who did not.
#
# WHY THERE IS A GRAPH AT ALL. `inferEffects` (self_host/typecheck.ax)
# is a monotone fixpoint over the program's call graph: it walks every
# body, resolves every reference site to a `FnEnt`, and folds that
# entry's effect row into the caller's. It then dropped the edge. So
# AXSYM could say `#effects=IO` and could not say which call put the IO
# there - and `#effects-incomplete`, the sentinel for a call head the
# walk could not resolve, named the ROW rather than the call, which is
# the one thing a reader needs to fix it. `tcNoteCall` records the edge
# the walk had already resolved; `#calls=` prints it.
#
# This gate exists because a graph nobody checks is a comment. What it
# asserts is the property that makes the graph worth reading:
#
#   CONTAINMENT. For every declaration, every effect of every callee is
#   an effect of the caller. That is not a nice-to-have - it is the
#   statement that `#calls=` and `#effects=` are two views of one walk.
#   If it ever fails, one of them is lying and an `Agent.Policy` reading
#   either learns something false.
#
#   TOTALITY. Every row whose effect set was INFERRED carries at least
#   one edge accounting for it. A row with `#effects=IO` and no edge is
#   an effect from nowhere. Three shapes legitimately have none and all
#   are named below with the reason: an `extern`, whose row is
#   CONSTRUCTED by `tcAddExtern` rather than walked; a row with no
#   effects at all; and a row whose whole effect set is `Mut` - the
#   `set` of a struct field is the one effect-bearing FORM in the
#   language that is not a call, so a function that assigns a field and
#   calls nothing has `Mut` and no edge, by the walk's own definition.
#   Measured 2026-08-29 (`stdlib/Http.ax`'s `routeNotFound` was the
#   first such row in the library): `(fn (f c x) { (set c.v x) 0 })`
#   prints `#effects=Mut` and no `#calls=`; the same `set` on a `mut`
#   LOCAL prints no effect at all; and `__store64` prints `Mut` WITH a
#   `__store64` edge, because a builtin is a `FnEnt`. Only the field
#   form has no name to record, so only the exact set `{Mut}` is
#   excused - `Alloc,Mut` with no edge is still an effect from nowhere.
#
#   SILENCE BY DEFAULT. Without `--calls`, no row carries the key.
#   `tests/tools/symbols-zoo.golden` pins 147 rows byte for byte and
#   `check-tools-selfhost.sh` compares them, so a key that appeared
#   unasked would put an edge list in the diff of every future stdlib
#   edit. That is the churn `ac95e2b` was: a golden moving for a reason
#   unrelated to the change under review. `--builtins` is the precedent
#   this follows - content selection on `symbols`, not a build mode.
#
# WHY IT RUNS WITH `--builtins`. An operator is a `FnEnt` in this
# language, so `+` and `==` are real call edges and the graph prints
# them. Without `--builtins` they have no row, and CONTAINMENT would
# skip every edge naming one - 772 of them, measured, which is a check
# that silently ignores more than it reads. `__alloc` is the case that
# makes this load-bearing rather than tidy: it is a builtin AND it is
# what puts `Alloc` in the row beside it.
#
# THE ONE THING THAT LEGITIMATELY DOES NOT RESOLVE, and it is a finding
# rather than an exemption: a trait implementation. `walkCallHead`
# cannot select an implementation - that needs the dispatch argument's
# type, which the fixpoint does not have - so it unions EVERY
# implementation, and this gate records every one as an edge. Those
# edges name `Trait#Type#method`, and `symbols` prints no row for a
# generated name (`smGenerated`, symbols.ax). So the graph now NAMES the
# gap `check-agent-policy.sh` already documents in prose: "an impl
# METHOD BODY gets no AXSYM row at all ... that is a real gap in this
# gate's input and it is `symbols.ax`'s to close". It is still open; the
# difference is that it is now visible in the stream instead of only in
# a comment, and the count is asserted below so closing it is noticed.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

stdlib_prefix="$repo_root/stdlib/"

# `--calls` is a flag, and the driver's flag table is CLOSED: an unknown
# flag exits 2 before printing anything. Without this the whole gate
# would die on its first `symbols` invocation under `set -e` and report
# nothing at all - which is exactly how it behaved when first run
# against a compiler built from before this feature. A gate whose
# failure mode is silence cannot be told from a gate that did not run.
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

# The probe imports every stdlib module, exactly as check-agent-policy
# builds it and for the same reason: the module list is derived from the
# tree, so a module is covered the day it lands. It lives in its own
# directory because module resolution searches the ENTRY FILE'S OWN
# directory first.
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
  grep '#calls=' "$work/plain" | sed 's/^/     /' | head -5
  exit 1
fi
echo "ok   the default stream is unchanged by this feature"

echo
echo "== containment: a callee's effects are its caller's effects =="
# `Trait#Type#method` edges have no row of their own - see the header.
# The COUNT is asserted, not just the shape, so that closing the
# symbols.ax gap shows up here as a failure to re-read rather than as
# silence.
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
    key = (mod, name)
    prev = rows.get(key)
    rows[key] = (effs | (prev[0] if prev else set()),
                 calls or (prev[1] if prev else []))

bare = {}
for (mod, name), v in rows.items():
    bare.setdefault(name, v)

def lookup(callee):
    if '$' in callee:
        mod, b = callee.rsplit('$', 1)
        return rows.get((mod.split('.')[-1], b)) or bare.get(b)
    return bare.get(callee)

violations, rowless = [], []
for (mod, name), (effs, calls) in rows.items():
    for callee in calls:
        target = lookup(callee)
        if target is None:
            rowless.append((mod, name, callee))
            continue
        missing = target[0] - effs
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

# THE BOUND IS ON DISTINCT CALLEES, NOT ON EDGES, and that is a
# correction. It bounded `len(generated)` - the EDGE count - at 12,
# with 4 measured on 2026-08-24. But an edge is one caller naming one
# implementation, so the number scales with how many functions call a
# trait method: `stdlib/Test.ax` arrived on 2026-08-25 with six public
# assertions that each `println` a value, and 6 callers x 4 `Show`
# implementations took it from 4 to 28 without the gap moving at all.
# A ceiling that fires when somebody writes a function that prints is
# measuring the library's size.
#
# The gap is `symbols.ax` emitting no row for an impl method body, and
# its size is the number of DISTINCT names the graph can name and the
# stream cannot explain. That is 4 today - `Show#Int#show` and its
# three siblings - and it moves when a trait implementation is added
# or when the gap closes, which is what this is for. The edge count is
# still printed, because it is the thing a reader will see in the
# stream, and it is no longer asserted.
callees = sorted({r[2] for r in generated})
print(f"ok   {len(rows)} rows, every edge resolved, no callee effect escapes its caller")
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
# An `extern` item's row is CONSTRUCTED - `tcAddExtern` seeds `IO`
# rather than inferring it - so it has no edge and must not have one.
# Anchored on the SPAN field, not on the line, so a meta value spelling
# `Ffi.ax` cannot inherit the exemption. And a row whose effect set is
# exactly `Mut` is the field-`set` form's own row (the header says how
# that was measured); the match is on the whole value, so a row that
# also carries `IO` is still reported.
#
# AND A ROW WHOSE EFFECT SET IS EXACTLY `Alloc` IS THE CONSTRUCTOR
# APPLICATION'S OWN ROW, added 2026-08-31 for the same reason and in
# the same shape. `restrict(no-alloc)` was unsound until that day
# because a constructor contributed nothing to the effect walk; making
# it contribute means `(Error code message "")` now puts `Alloc` in
# `mkError`'s row with NO call to point at, exactly as `(set p.x 1)`
# puts `Mut` in one. Six stdlib rows arrived here that way, every one
# a body whose whole content is building a value.
#
# The match is on the whole value here too, so `Alloc,IO` is still
# reported: a function that allocates AND reaches a syscall has a call
# somewhere, and a missing edge there would be a real finding.
missing=$(awk -v p="$stdlib_prefix" '
  $1 == "F" && index($3, p) == 1 &&
  /#effects=/ && !/#calls=/ &&
  !/#effects=Mut( |$)/ &&
  !/#effects=Alloc( |$)/ &&
  index($3, p "Ffi.ax:") != 1 { print $2, $3 }' "$work/calls" | LC_ALL=C sort -u || true)
if [[ -n "$missing" ]]; then
  echo "FAIL: these rows carry an inferred effect and no edge explaining it:"
  echo "$missing" | sed 's/^/     /' | head -20
  echo '     either the walk attributed an effect it did not resolve a call'
  echo '     for, or a new construction site seeds an effect row the way'
  echo '     `tcAddExtern` does - in which case name it in this gate.'
  exit 1
fi
echo "ok   every inferred effect row carries an edge, extern rows and field-set rows excepted"

echo
echo "== negative probes: every assertion can go red =="

# CONTAINMENT can see a caller whose row is narrower than its callee's.
# Built by hand rather than by breaking the compiler: the row shape is
# what the check reads, so a forged row is the honest probe of it.
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

# TOTALITY can see an effect with no edge, the Ffi exemption is
# anchored to the span rather than to the line, and the field-set
# exemption is the exact set `{Mut}`: zeta is excused, eta - `Mut` with
# an `Alloc` beside it and no edge - is not.
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

# SILENCE can see the key arriving unasked.
printf 'F zeta /x/stdlib/D.ax:1:1-2 "Int" @f #effects=IO #calls=D$eta\n' > "$work/sil.axsym"
if ! grep -q '#calls=' "$work/sil.axsym"; then
  echo "FAIL negative: the silence matcher cannot see #calls= at all"
  exit 1
fi
echo "ok   the silence check can see the key it refuses"

echo
echo "== grounding: every inferred IO reaches a primitive through the graph =="
# The assertion the other three set up. Containment says no effect
# ESCAPES upward; this says every IO effect came from somewhere real
# going down.
#
# WHAT COUNTS AS "REAL" IS THE DEFINITION OF `IO`, AND THE DEFINITION
# MOVED. It was a `__syscallN` or an `extern`, and this walk said so.
# On 2026-08-25 `__argc`/`__argv` were registered with `IO` as well
# (`docs/memory-model.md` MM-EXEC-9a): reading the command line is
# reading input the process did not compute, which is what `IO` means
# even though no syscall happens. Nine `stdlib/Sys.ax` rows became
# IO-performing that day and every one of them failed here, correctly -
# the gate was holding the old definition, and a grounding check whose
# origin list is short reports honest effects as unexplained.
#
# So the list is four, not two, and it is the SAME list the compiler
# registers with `regFnEff` in `self_host/typecheck.ax`. When one
# grows, so does the other; there is no third place to look.
#
# It is a transitive walk, not a one-hop check, because the library is
# four and five hops deep: `writeStr` -> `sysWriteAllFd` -> `sysWriteFd`
# -> ... -> `__syscall3`. An earlier version of this probe asserted the
# one hop and failed on a correct tree, which is why it is spelled as
# reachability now.
python3 - "$work/calls" "$stdlib_prefix" <<'PYG' > "$work/ground.out" || { cat "$work/ground.out"; exit 1; }
import re, sys
axsym, prefix = sys.argv[1], sys.argv[2]
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
        if callee.startswith('__syscall') or callee in ('__argc', '__argv'):
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
    print("      `__syscallN`, an `extern`, `__argc` or `__argv`, so the")
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
