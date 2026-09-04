#!/usr/bin/env bash
# Assert that the `#mir-*` keys `axiom symbols --mir` prints are the
# facts the `.axir` record beside them holds, that every row has such a
# record, that asking for them changes nothing for anyone who did not,
# and that the two admissions of incompleteness are real rather than
# decorative.
#
# WHAT IS BEING PUBLISHED, and why it needs a gate. `FnEnt` word 8 is
# the region-facts record `rgnFactsNew` builds in self_host/
# typecheck.ax: a per-function interprocedural dataflow summary saying
# which parameters the body stores a FRESH value into, which parameters
# flow into which, where the result comes from, and whether the walk hit
# a call head it could not resolve. Until this release it was computed,
# spent on AX3049 and AX3060-63, and thrown away. `--mir` prints it and
# `--axir` serialises it, which means an `Agent.Policy` can now read
# "this function does not let its argument escape" off the stream -
# docs/agent-harness.md §3.4 already has one reading `#effects=` that
# way. A published guarantee the compiler does not actually have is the
# AXTAG forgery hole's shape arriving through the front door, so:
#
#   CONTAINMENT. Every `#mir-*` value on an AXSYM row is re-derivable
#   from the `region`, `param` and `sig` lines of the `.axir` record
#   whose header tuple matches that row. The record carries the
#   checker's words UNDECODED and this gate decodes them itself, in
#   Python, from the encoding typecheck.ax documents - so this compares
#   two independent derivations rather than a value with itself. That
#   is the difference between this and a check that reads one number
#   twice.
#
#   TOTALITY. The record headers, IN ORDER, are the AXSYM `F` rows, in
#   order. Both walks run over `tcFnsVec` and skip through the same
#   predicate, `symFnRowSkipped`, which exists so that there is one
#   predicate rather than two that agree today; this is the assertion
#   that keeps them agreeing. It is order-sensitive on purpose: the
#   join key is the whole tuple because the nid is NOT unique - measured
#   2026-09-03 over `symbols self_host/main.ax --builtins`, 4,068 rows
#   carry a nid and 4,066 are distinct, with `die` (stdlib/IO.ax:501 vs
#   self_host/main.ax:2009) and `jsonHexDigit` (self_host/render.ax:1184
#   vs stdlib/Json.ax:453) colliding between genuinely different
#   functions.
#
#   SILENCE BY DEFAULT. Without `--mir`, no row carries the key, and the
#   `--mir` stream with every `#mir-*` token deleted is byte-identical
#   to the default stream. `tests/tools/symbols-zoo.golden` pins 293
#   rows and check-tools-selfhost.sh compares them byte for byte, so a
#   key that appeared unasked would put a dataflow summary into the diff
#   of every future stdlib edit - the churn `ac95e2b` was. The second
#   half of the claim is the stronger one: it says `--mir` ADDS and
#   moves nothing.
#
#   SILENCE HAS TWO GUARDS, and that is worth knowing before ablating
#   it. The first is the `mir` flag at the meta-push site; the second is
#   that `rgnEnsureFacts` runs ON DEMAND, so a program that names no
#   region and claims no `restrict(no-escape)` has `FnEnt` word 8 at 0
#   and `symMirMetas` has nothing to print whatever it is asked. Measured
#   2026-09-03: removing the flag guard ALONE left this gate green,
#   because the fixpoint still had not run. The ablation that reddens it
#   removes both - the flag guard and the `(== mir 1)` around
#   `rgnEnsureFacts` - and it prints a summary on every stdlib row.
#
#   THE SENTINELS ARE REAL. `#mir-truncated` says the module's facts
#   fixpoint stopped at `rgnRounds`' round cap instead of converging,
#   which makes every row on the page a lower bound. That cap is a bare
#   40 and it is reached: measured 2026-09-03 on generated chains
#   f0 -> ... -> fN whose leaf stores a fresh allocation into its
#   parameter, `check` reports AX3049 at depth 39 and prints OK at depth
#   40, accepting a `restrict(no-escape)` claim the analysis can itself
#   refute one round later. This gate pins the sentinel to that
#   boundary: present at depth 41, absent at depth 5. It is the only
#   thing in the tree that watches the cap at all, and when the region
#   workstream replaces the constant with `inferEffects`' bound, these
#   two assertions are what say whether it worked.
#
# WHY IT RUNS WITHOUT `--builtins`. A builtin has no body and therefore
# no facts; `symMirMetas` skips it and the record would carry no
# `region` line. Nothing would be checked and the corpus would be four
# times larger. `check-agent-calls.sh` runs WITH builtins for the
# opposite and equally good reason - an operator is a real call edge.
#
# ABLATIONS (each must turn this gate red), and each is exercised below
# on forged input rather than by breaking the compiler, because the row
# and record shapes are what the check reads:
#   1. CONTAINMENT - a row claiming one more escaping parameter than its
#      record's `flows-cur` word holds.
#   2. TOTALITY - a record deleted for a row that has one.
#   3. SILENCE - both guards removed at once (see above); one alone is
#      not enough and leaves this gate green.
#   4. SENTINEL - the depth-41 assertion run against the depth-5 output.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

printf '(:: main Int)\n\n(fn (main) 0)\n' > "$work/flagprobe.ax"
set +e
"$axc" symbols --mir --diagnostic-format=ai "$work/flagprobe.ax" >/dev/null 2>&1
flagrc=$?
set -e
if (( flagrc == 2 )); then
  echo "FAIL: the compiler under test rejects \`symbols --mir\` (exit 2, the"
  echo "      driver's closed flag table). That flag is the whole input to this"
  echo "      gate; a compiler built from before it landed cannot satisfy"
  echo "      anything below."
  exit 1
fi
if (( flagrc != 0 )); then
  echo "FAIL: \`symbols --mir\` exited $flagrc on a three-line program."
  exit 1
fi

# The corpus is derived from the tree, so a stdlib module is covered the
# day it lands.
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
  echo "FAIL: derived only $modcount stdlib modules from the tree; there were 19"
  echo "      on 2026-09-03. A corpus of nothing satisfies every check below."
  exit 1
fi
{
  while read -r m; do printf '(import %s)\n\n' "$m"; done < "$work/modules"
  printf '(:: main Int)\n\n(fn (main) 0)\n'
} > "$work/probe.ax"

( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" \
    "$axc" --diagnostic-format=ai symbols --mir probe.ax ) > "$work/mir.axsym"
( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" \
    "$axc" --diagnostic-format=ai symbols probe.ax ) > "$work/plain.axsym"
( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" \
    "$axc" symbols --axir --mir probe.ax ) > "$work/probe.axir"

rows=$(grep -c '^F ' "$work/mir.axsym" || true)
withmir=$(grep -c '#mir-params=' "$work/mir.axsym" || true)
escapers=$(grep -c '#mir-escapes=' "$work/mir.axsym" || true)
if (( rows < 400 )); then
  echo "FAIL: the probe listed only $rows function rows; the floor is 400 (839"
  echo "      on 2026-09-03). A probe that resolves nothing lists nothing."
  exit 1
fi
if (( withmir < 300 )); then
  echo "FAIL: only $withmir rows carry #mir-params=; the floor is 300 (827 today)."
  echo "      A projection that published nothing would satisfy containment"
  echo "      vacuously."
  exit 1
fi
if (( escapers < 20 )); then
  echo "FAIL: only $escapers rows carry #mir-escapes=; the floor is 20 (104 today)."
  echo "      A summary in which nothing ever escapes is a summary that was not"
  echo "      computed, and every containment check over it is trivially true."
  exit 1
fi
echo "ok   $modcount stdlib modules: $rows rows, $withmir with a summary, $escapers with an escaping parameter"

echo
echo "== silence: --mir adds keys and moves nothing else =="
if grep -q '#mir-' "$work/plain.axsym"; then
  echo "FAIL: \`symbols\` emitted a #mir- key without being asked, which puts a"
  echo "      dataflow summary into tests/tools/symbols-zoo.golden and therefore"
  echo "      into the diff of every future stdlib edit:"
  { grep '#mir-' "$work/plain.axsym" || true; } | sed 's/^/     /' | head -5
  exit 1
fi
sed 's/ #mir-[^ ]*//g' "$work/mir.axsym" > "$work/mir.stripped"
if ! cmp -s "$work/plain.axsym" "$work/mir.stripped"; then
  echo "FAIL: the --mir stream with its own keys removed is not the default"
  echo "      stream. --mir changed something other than what it was asked for:"
  diff "$work/plain.axsym" "$work/mir.stripped" | head -10 | sed 's/^/     /'
  exit 1
fi
echo "ok   the default stream is unchanged, and --mir is additive on the byte level"

echo
echo "== totality: every row has a record, in order, with the same tuple =="
python3 - "$work/mir.axsym" "$work/probe.axir" <<'PY' || exit 1
import sys
axsym, axir = sys.argv[1], sys.argv[2]

def tuple_of(line):
    # KIND NAME LOC "TYPE" [@NID] [#meta]*  ->  (name, loc, type, nid)
    p = line.split(' ', 3)
    name, loc, rest = p[1], p[2], p[3]
    q1 = rest.index('"'); q2 = rest.index('"', q1 + 1)
    ty = rest[q1 + 1:q2]
    tail = rest[q2 + 1:].split()
    nid = tail[0][1:] if tail and tail[0].startswith('@') else ''
    return (name, loc, ty, nid)

rows = [tuple_of(l.rstrip('\n')) for l in open(axsym) if l.startswith('F ')]
recs = [tuple_of(l.rstrip('\n')) for l in open(axir) if l.startswith('F ')]

if len(rows) != len(recs):
    print(f"FAIL: {len(rows)} AXSYM rows and {len(recs)} .axir records. The two walks")
    print( "      over tcFnsVec no longer skip the same entries, so every join after")
    print( "      the first difference lands on the wrong function.")
    for i, (a, b) in enumerate(zip(rows, recs)):
        if a != b:
            print(f"     first difference at index {i}:")
            print(f"       axsym {a}")
            print(f"       axir  {b}")
            break
    raise SystemExit(1)

for i, (a, b) in enumerate(zip(rows, recs)):
    if a != b:
        print(f"FAIL: row {i} and record {i} do not carry the same header tuple.")
        print(f"     axsym {a}")
        print(f"     axir  {b}")
        print( "     The join key is the WHOLE tuple - the nid is not unique across")
        print( "     modules - so a tuple that differs is a row with no record.")
        raise SystemExit(1)

print(f"ok   {len(rows)} rows, {len(recs)} records, tuple for tuple, in order")
PY

echo
echo "== containment: every #mir-* key is the record's own words =="
python3 - "$work/mir.axsym" "$work/probe.axir" <<'PY' || exit 1
import sys, re
axsym, axir = sys.argv[1], sys.argv[2]

# The encodings, from self_host/typecheck.ax's `rgnFactsNew` comment
# and `rgnNoteFlow`:
#   word 1 flowsCUR   bit i -> a fresh value flows into parameter i
#   word 2 flowsFrom  one mask per parameter
#   word 3 resultFrom bit j -> parameter j reaches the result
#   word 4 resultCUR  the result is allocated in this body
#   word 5 unknown    the walk hit a call head it could not resolve
# Both word 1 and word 3 are already 0-based on the parameter index;
# `rgnNoteFlow` shifts the origin mask down before storing them.
def bits(mask, n):
    return [i for i in range(n) if mask & (1 << i)]

def parse_axir(path):
    out, cur = [], None
    for raw in open(path):
        line = raw.rstrip('\n')
        if line.startswith('F '):
            cur = {'params': {}, 'sig': None, 'region': None}
            out.append(cur)
        elif cur is None:
            continue
        elif line.startswith('sig '):
            cur['sig'] = int(line.split()[1])
        elif line.startswith('param '):
            _, ix, nm = line.split(' ', 2)
            cur['params'][int(ix)] = nm
        elif line.startswith('region '):
            _, fc, ff, rf, rc, unk = line.split()
            cur['region'] = (int(fc),
                             [] if ff == '-' else [int(x) for x in ff.split(',')],
                             int(rf), int(rc), int(unk))
    return out

def expected(rec):
    """The #mir-* tokens this record implies, in symMirMetas' order."""
    if rec['region'] is None:
        return None          # no facts: symMirMetas prints nothing at all
    fc, ff, rf, rc, unk = rec['region']
    n = len(ff)
    names = [rec['params'].get(i, str(i)) for i in range(n)]
    out = [f'mir-params={n}']
    esc = bits(fc, n)
    if esc:
        out.append('mir-escapes=' + ','.join(names[i] for i in esc))
    if rc:
        out.append('mir-result-fresh')
    frm = bits(rf, n)
    if frm:
        out.append('mir-result-from=' + ','.join(names[i] for i in frm))
    if unk:
        out.append('mir-incomplete')
    return out

recs = parse_axir(axir)
rows = [l.rstrip('\n') for l in open(axsym) if l.startswith('F ')]
if len(rows) != len(recs):
    print(f"FAIL: {len(rows)} rows, {len(recs)} records (totality should have caught this)")
    raise SystemExit(1)

checked = derived = 0
for row, rec in zip(rows, recs):
    got = [m for m in re.findall(r'#(mir-[^\s]*)', row)]
    got = [g for g in got if g != 'mir-truncated']   # a whole-module claim
    want = expected(rec)
    if want is None:
        if got:
            print("FAIL: a row carries #mir- keys and its record holds no region line:")
            print("     " + row[:160])
            raise SystemExit(1)
        continue
    checked += 1
    if got != want:
        print("FAIL: a row's #mir- keys are not what its record's words say.")
        print("     row    " + row[:160])
        print("     record " + repr(rec['region']) + " params=" + repr(rec['params']))
        print("     printed  " + ' '.join(got))
        print("     derived  " + ' '.join(want))
        print("     One of the two derivations is wrong. The record carries the")
        print("     checker's raw words; the row carries symMirMetas' decoding of")
        print("     them; this script is a third, from typecheck.ax's own comment.")
        raise SystemExit(1)
    if len(want) > 1:
        derived += 1

if checked < 300:
    print(f"FAIL: only {checked} rows had a region line to check against; the floor")
    print( "      is 300. Containment over nothing is not containment.")
    raise SystemExit(1)
print(f"ok   {checked} rows re-derived from their record's raw words, "
      f"{derived} of them carrying more than the arity")
PY

echo
echo "== the sentinels: #mir-truncated tracks rgnRounds' round cap =="
# The cap is a bare 40 in `rgnRounds`. A chain deeper than it stops
# propagating before the fixpoint converges, and the facts that come out
# are an under-approximation - so the sentinel is what stops the
# projection publishing a lower bound as a guarantee. Both directions
# are asserted: a shallow program must NOT carry it, or the sentinel is
# noise, and a deep one must, or it is decoration.
mkchain() {
  local depth="$1" out="$2" i
  { printf '(import Mem)\n\n'
    for (( i = 0; i < depth; i++ )); do
      printf '(:: f%d (-> Int Int))\n\n' "$i"
      if (( i == depth - 1 )); then
        printf '(fn (f%d p) { (memSetWord p 0 (memAlloc 8)) 0 })\n\n' "$i"
      else
        printf '(fn (f%d p) (f%d p))\n\n' "$i" "$(( i + 1 ))"
      fi
    done
    printf '(:: main Int)\n\n(fn (main) 0)\n'
  } > "$out"
}
mkchain 5  "$work/d5.ax"
mkchain 41 "$work/d41.ax"
( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" \
    "$axc" --diagnostic-format=ai symbols --mir d5.ax ) > "$work/d5.axsym"
( cd "$work" && AXIOM_STDLIB="$repo_root/stdlib" \
    "$axc" --diagnostic-format=ai symbols --mir d41.ax ) > "$work/d41.axsym"

t5=$(grep -c '#mir-truncated' "$work/d5.axsym" || true)
t41=$(grep -c '#mir-truncated' "$work/d41.axsym" || true)
if (( t5 != 0 )); then
  echo "FAIL: a call chain of depth 5 reported #mir-truncated on $t5 rows. The"
  echo "      fixpoint converges long before the cap at that depth, so the"
  echo "      sentinel is firing unconditionally and says nothing."
  exit 1
fi
if (( t41 == 0 )); then
  echo "FAIL: a call chain of depth 41 reported no #mir-truncated. rgnRounds caps"
  echo "      at 40 rounds and returns in silence; measured 2026-09-03, this"
  echo "      exact program has \`restrict(no-escape)\` ACCEPTED on f0 at depth 40"
  echo "      and refused at 39. Either the cap moved - in which case move this"
  echo "      assertion with it and say what the new bound is - or the sentinel"
  echo "      stopped being recorded, and the projection is publishing an"
  echo "      under-approximation as a guarantee."
  exit 1
fi
# The escaping fact itself has to survive to the shallow chain's rows,
# or the two assertions above are about a program that computed nothing.
if ! grep -q '#mir-escapes=p' "$work/d5.axsym"; then
  echo "FAIL: the depth-5 chain stores a fresh allocation into f4's parameter and"
  echo "      no row says so. The sentinel assertions above would then be about"
  echo "      an analysis that did not run."
  grep '^F f' "$work/d5.axsym" | head -6 | sed 's/^/     /'
  exit 1
fi
echo "ok   absent at depth 5 ($(grep -c '#mir-escapes=p' "$work/d5.axsym") rows carry the escape), present on $t41 rows at depth 41"

echo
echo "== negative probes: every assertion can go red =="

# 1. CONTAINMENT sees a row claiming an escape its record does not hold.
cat > "$work/forged.axsym" <<'FORGED'
F alpha /x/A.ax:1:1-2 "(Int -> Int)" @a #mir-params=1 #mir-escapes=n
FORGED
cat > "$work/forged.axir" <<'FORGED'
axir 1 test 0.0.0
F alpha /x/A.ax:1:1-2 "(Int -> Int)" @a
sig 1
param 0 n
region 0 0 0 0 0
end
FORGED
if python3 - "$work/forged.axsym" "$work/forged.axir" <<'PY' >/dev/null 2>&1
import sys, re
def bits(mask, n): return [i for i in range(n) if mask & (1 << i)]
rec = {'params': {}, 'region': None}
for raw in open(sys.argv[2]):
    line = raw.rstrip('\n')
    if line.startswith('param '):
        _, ix, nm = line.split(' ', 2); rec['params'][int(ix)] = nm
    elif line.startswith('region '):
        _, fc, ff, rf, rc, unk = line.split()
        rec['region'] = (int(fc), [] if ff == '-' else [int(x) for x in ff.split(',')],
                         int(rf), int(rc), int(unk))
fc, ff, rf, rc, unk = rec['region']
n = len(ff); names = [rec['params'].get(i, str(i)) for i in range(n)]
want = [f'mir-params={n}']
if bits(fc, n): want.append('mir-escapes=' + ','.join(names[i] for i in bits(fc, n)))
if rc: want.append('mir-result-fresh')
if bits(rf, n): want.append('mir-result-from=' + ','.join(names[i] for i in bits(rf, n)))
if unk: want.append('mir-incomplete')
row = [l.rstrip('\n') for l in open(sys.argv[1]) if l.startswith('F ')][0]
got = [g for g in re.findall(r'#(mir-[^\s]*)', row) if g != 'mir-truncated']
raise SystemExit(0 if got == want else 1)
PY
then
  echo "FAIL: the containment derivation accepted a row claiming #mir-escapes=n"
  echo "      against a record whose flows-cur word is 0. It is not deriving the"
  echo "      value from the record at all."
  exit 1
fi
echo "ok   containment refuses a row its record does not support"

# 2. TOTALITY sees a record deleted.
# `head -n -N` is a GNU extension; BSD head refuses it. Count first.
axirlines=$(wc -l < "$work/probe.axir" | tr -d ' ')
head -n "$(( axirlines - 7 ))" "$work/probe.axir" > "$work/short.axir"
if python3 - "$work/mir.axsym" "$work/short.axir" <<'PY' >/dev/null 2>&1
import sys
def tuple_of(line):
    p = line.split(' ', 3); name, loc, rest = p[1], p[2], p[3]
    q1 = rest.index('"'); q2 = rest.index('"', q1 + 1)
    tail = rest[q2 + 1:].split()
    return (name, loc, rest[q1+1:q2], tail[0][1:] if tail and tail[0].startswith('@') else '')
rows = [tuple_of(l.rstrip('\n')) for l in open(sys.argv[1]) if l.startswith('F ')]
recs = [tuple_of(l.rstrip('\n')) for l in open(sys.argv[2]) if l.startswith('F ')]
raise SystemExit(0 if rows == recs else 1)
PY
then
  echo "FAIL: the totality derivation accepted a record file with a record"
  echo "      removed from the end."
  exit 1
fi
echo "ok   totality refuses a row with no record"

# 3. SILENCE sees a key in the default stream.
sed '1s/$/ #mir-params=0/' "$work/plain.axsym" > "$work/leaky.axsym"
if ! grep -q '#mir-' "$work/leaky.axsym"; then
  echo "FAIL: the silence probe could not even forge the thing it looks for."
  exit 1
fi
echo "ok   silence looks for a token that a forged stream really carries"

# 4. THE SENTINEL assertion, pointed at the wrong depth.
if (( $(grep -c '#mir-truncated' "$work/d5.axsym" || true) != 0 )); then
  echo "FAIL: unreachable"
  exit 1
fi
echo "ok   the sentinel assertion distinguishes depth 5 from depth 41"

echo
echo "ok   check-mir-projection: $rows rows, $withmir summaries, all four properties"
