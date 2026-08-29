#!/usr/bin/env bash
#
# A TYPE NAME MEANS WHAT ITS OWN MODULE SAYS IT MEANS - and finding out
# which declaration that is must not cost a scan of the program.
#
# WHY THIS EXISTS. `mangleDecl` (self_host/namespace.ax) rewrites `fn`
# and `::` declarations to `Mod$name` on the way into the merged
# declaration list and rewrites nothing else, so `data`, `struct` and
# `type` names arrive spelled exactly as their module wrote them. The
# lookups that read them - `findStructFrom`, `findDataFrom`,
# `findCtorFrom`, `tcAliasFindFrom` - were linear scans that returned
# the FIRST match, and that list is ordered dependencies-first by
# import order. So:
#
#     TeamA.ax  (pub struct Config (port : Int) (retries : Int))
#     TeamB.ax  (pub struct Config (retries : Int) (port : Int))
#               (pub fn (bPort) (let ((c (Config 3 99))) c.port))
#     app.ax    (import TeamA) (import TeamB) (fn (main) (bPort))
#
#     axiom check app.ax   ->  OK, exit 0
#     axiom run   app.ax   ->  exit 3      TeamA's slot 0
#     imports swapped      ->  exit 99
#
# TeamB's own function, reading TeamB's own struct, was compiled
# against TeamA's field offsets - and the answer changed when an
# unrelated line moved. No diagnostic, at any level, from any pass.
# Three more classes fell out of the same root, all on programs that
# are individually valid: a `data` collision drew AX3005 inside the
# innocent module listing constructors its type does not have, an
# arity difference drew AX3008 there against a shape it never wrote,
# and a `type` alias collision drew AX3004s in both directions.
#
# WHAT IS ASSERTED HERE, in the order the sections run:
#
#   1  RESOLUTION.  The two-team probe answers 99 with the imports in
#      BOTH orders - order-independence is the property, and either
#      order alone is half a test (the B-first order answered 99
#      before the fix, by accident). Plus the control - TeamB alone,
#      no collision - so 99 is not arriving for some reason of its
#      own. Plus a MUTANT of TeamB whose `bPort` reads the other
#      field, which must NOT answer 99: that is what proves this
#      section reads a real exit status rather than passing on air.
#
#   2  REFUSAL.  A bare reference that two modules can both answer and
#      neither owns is AX3044, naming BOTH modules. Asserted for
#      `struct`, for `data` and for `type` alias, and each one paired
#      with its own control - the same program with one import
#      removed, which must check clean, so the diagnostic is charged
#      to the collision and not to the reference existing.
#
#   3  THE ESCAPE.  An import name list decides what a module exports
#      to this program, so `(import TeamA (aPort))` leaves TeamA's
#      `Config` invisible and the reference resolves. This is the fix
#      AX3044's help text tells the reader to make, and a help text
#      naming a fix nobody checked is how this repository's
#      diagnostics have been wrong before.
#
#   4  ONE FILE, TWO ALIASES.  `declNamespace` put TAG_D_ALIAS in
#      NS_NONE, so two `(type Amt = ...)` in one file were silent
#      while two `(struct Amt ...)` were AX3006. Same class, same
#      change.
#
#   5  SCALE.  Rules (a)-(d) cannot exit on the first match: deciding
#      that a name is unambiguous means looking at every declaration
#      of it. On the old linear list that turns an early-exit scan
#      into a full scan of the program's types AT EVERY TYPE
#      REFERENCE - which is why the semantics and the index had to
#      land in one change, and this section is what re-asks it. Two
#      byte-identical programs but for four digits: 8,000 struct
#      declarations and 48,000 type references, where one names the
#      FIRST declaration in the table and the other the LAST. A scan
#      pays one comparison against 8,000; a bucket keyed on the name
#      pays one entry either way.
#
# NEGATIVE PROBE, RUN. Sections 1-4 each carry an in-gate control, and
# section 1 carries a mutant, all described above - but no in-gate
# control can show this gate red against the compiler that had the
# defect, because that costs a second compiler build. So the ablation
# was performed by hand, once, on 2026-08-24: `self_host/typecheck.ax`
# and `self_host/explain.ax` reverted to the parent commit, the
# compiler that tree builds handed to `gate_build_axc` through
# `AXIOM_AXC`, this script run unchanged. It reported
#
#     11 of 18 check(s) failed        (exit 1)
#
# and the eleven were, verbatim, colour stripped:
#
#   FAIL TeamA imported first, TeamB's own Config: `run ab.ax` exited 3, want 99
#   FAIL both modules resolve their own (99 + 7): `run both.ax` exited 10, want 106
#   FAIL mutant: TeamB reading its other field is not 99: `run mut.ax` exited 99,
#        which this probe is built to make impossible
#   FAIL arity variant: NarrowB compiles against its own shape: `run run.ax` exited 1, want 99
#        error[AX3008]: struct `Config` expects 3 field(s), found 2
#         --> NarrowB.ax:7:27
#   FAIL arity variant: the entry file's bare Config: no-AX3044 missing:WideA
#   FAIL data: ShB's match is exhaustive over ITS Shade: `run run.ax` exited 1, want 22
#        error[AX3005]: non-exhaustive pattern match: missing Aa, Ab
#         --> ShB.ax:8:10
#   FAIL data: the entry file's bare Shade: no-AX3044 missing:ShA
#   FAIL alias: AlB's Amount is Int inside AlB: `run run.ax` exited 1, want 42
#        error[AX3004]: type mismatch: expected Float, found Int
#         --> AlB.ax:5:25
#   FAIL alias: the entry file's bare Amount: no-AX3044 missing:AlA
#   FAIL two `type Amt` in one file: `check two.ax` exited 0 - the reference was
#        resolved, not refused
#   FAIL scale: naming the LAST type in the table now costs 26.88x what naming the
#        first one costs
#     check-type-namespace: 8000 types, 48000 references  first 0.38s  last 10.08s
#       ratio 26.88 (bound 1.40)
#
# The three carets are worth reading twice: every one of them is
# anchored inside the module that wrote the code CORRECTLY, blaming it
# for a shape another module declared. The mutant line is the same
# defect wearing the gate's own clothes - `c.retries` inside TeamMut
# resolved to TeamA's `retries` and answered 99, which is why the
# mutant is a namespace probe and not merely a wiring check.
#
# On the compiler this tree builds, the same run: `all 18 checks
# passed`, and
#
#     check-type-namespace: 8000 types, 48000 references
#       first 0.44s  last 0.45s  ratio 1.01 (bound 1.40)
#
# The bound is 1.40 rather than something tighter because it is placed
# between two measurements and shaved to neither: 1.01 below it, 26.88
# above. See check-name-scale.sh's note on how a floor expires.
#
# WHAT THE INDEX COST, stated because the honest number is not zero.
# `first 0.38s -> 0.44s` is the linear scan's BEST case - a name that
# hit on comparison one - and the index is ~0.06s slower there,
# building 8,000 entries nothing looks at twice. `last 10.08s ->
# 0.45s` is its worst. On the compiler's own source, where the type
# table is 46 entries, `check self_host/main.ax` went 0.53s -> 0.48s.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

gate_build_axc axc

failed=0
checks=0

# `run` writes an executable beside the entry file, so every probe gets
# its own directory - and the module search path is the ENTRY FILE's
# directory, which is what makes two modules of the same name in two
# probes not see each other.
mk() { mkdir -p "$work/$1"; }

# ok_exit <dir> <entry> <want> <label>
ok_exit() {
  local d="$1" entry="$2" want="$3" label="$4" got
  checks=$((checks + 1))
  ( cd "$work/$d" && "$axc" run "$entry" ) >/dev/null 2>"$work/$d.err"
  got=$?
  if [[ "$got" != "$want" ]]; then
    echo "FAIL $label: \`run $entry\` exited $got, want $want"
    sed 's/^/     /' "$work/$d.err" | head -6
    failed=$((failed + 1))
  else
    echo "ok   $label (exit $got)"
  fi
}

# not_exit <dir> <entry> <notwant> <label>
not_exit() {
  local d="$1" entry="$2" notwant="$3" label="$4" got
  checks=$((checks + 1))
  ( cd "$work/$d" && "$axc" run "$entry" ) >/dev/null 2>&1
  got=$?
  if [[ "$got" == "$notwant" ]]; then
    echo "FAIL $label: \`run $entry\` exited $got, which this probe is built to make impossible"
    failed=$((failed + 1))
  else
    echo "ok   $label (exit $got, not $notwant)"
  fi
}

# ok_clean <dir> <entry> <label>
ok_clean() {
  local d="$1" entry="$2" label="$3" out rc
  checks=$((checks + 1))
  out="$( cd "$work/$d" && "$axc" check "$entry" 2>&1 )"; rc=$?
  if (( rc != 0 )); then
    echo "FAIL $label: \`check $entry\` exited $rc, want 0"
    printf '%s\n' "$out" | sed 's/^/     /' | head -6
    failed=$((failed + 1))
  else
    echo "ok   $label (check clean)"
  fi
}

# ok_diag <dir> <entry> <code> <label> <must-appear>...
#
# Refused, with that code, and every remaining argument present in the
# message. The module NAMES are passed in that way: "names both
# modules" is the assertion, and a check that only looked for the code
# would pass on a diagnostic that named neither, which is precisely
# what the old compiler emitted.
ok_diag() {
  local d="$1" entry="$2" code="$3" label="$4"; shift 4
  local out rc bad="" w
  checks=$((checks + 1))
  # Twice: once for the exit status, once for the text with the colour
  # escapes stripped. A pipeline's `$?` is the LAST stage's, so reading
  # the status off the `sed` would have made every one of these pass.
  ( cd "$work/$d" && "$axc" check "$entry" >/dev/null 2>&1 ); rc=$?
  out="$( cd "$work/$d" && "$axc" check "$entry" 2>&1 | sed 's/\x1b\[[0-9;]*m//g' )"
  if (( rc == 0 )); then
    echo "FAIL $label: \`check $entry\` exited 0 - the reference was resolved, not refused"
    failed=$((failed + 1))
    return
  fi
  [[ "$out" == *"$code"* ]] || bad="$bad no-$code"
  for w in "$@"; do
    [[ "$out" == *"$w"* ]] || bad="$bad missing:$w"
  done
  if [[ -n "$bad" ]]; then
    echo "FAIL $label:$bad"
    printf '%s\n' "$out" | sed 's/^/     /' | head -6
    failed=$((failed + 1))
  else
    echo "ok   $label ($code, names $*)"
  fi
}

# ---------------------------------------------------------------
# 1. resolution: the two-team probe, both orders, plus its controls
# ---------------------------------------------------------------
echo "== resolution: a module's own type name reaches its own declaration =="
mk two
cat > "$work/two/TeamA.ax" <<'EOF'
(pub struct Config
  (port : Int)
  (retries : Int))

(pub :: aPort Int)

(pub fn (aPort) (let ((c (Config 7 1))) c.port))
EOF
cat > "$work/two/TeamB.ax" <<'EOF'
(pub struct Config
  (retries : Int)
  (port : Int))

(pub :: bPort Int)

(pub fn (bPort) (let ((c (Config 3 99))) c.port))
EOF
# The mutant: TeamB's own code reading its OTHER field. The honest
# answer is 3, so a harness that is not really reading exit statuses -
# or a probe that answers 99 for a reason of its own - is caught here.
cat > "$work/two/TeamMut.ax" <<'EOF'
(pub struct Config
  (retries : Int)
  (port : Int))

(pub :: mPort Int)

(pub fn (mPort) (let ((c (Config 3 99))) c.retries))
EOF
printf '(import TeamA)\n(import TeamB)\n(:: main Int)\n(fn (main) (bPort))\n'  > "$work/two/ab.ax"
printf '(import TeamB)\n(import TeamA)\n(:: main Int)\n(fn (main) (bPort))\n'  > "$work/two/ba.ax"
printf '(import TeamB)\n(:: main Int)\n(fn (main) (bPort))\n'                  > "$work/two/solo.ax"
printf '(import TeamA)\n(import TeamB)\n(:: main Int)\n(fn (main) (+ (bPort) (aPort)))\n' > "$work/two/both.ax"
printf '(import TeamA)\n(import TeamMut)\n(:: main Int)\n(fn (main) (mPort))\n' > "$work/two/mut.ax"

ok_exit  two ab.ax   99 "TeamA imported first, TeamB's own Config"
ok_exit  two ba.ax   99 "TeamB imported first  - the same answer"
ok_exit  two solo.ax 99 "control: TeamB alone, no collision"
ok_exit  two both.ax 106 "both modules resolve their own (99 + 7)"
not_exit two mut.ax  99 "mutant: TeamB reading its other field is not 99"

# ---------------------------------------------------------------
# 2. refusal: a reference neither module owns names both modules
# ---------------------------------------------------------------
echo "== refusal: an unresolvable bare type name is AX3044, naming both =="

# struct, with an ARITY difference between the two - the variant that
# used to refuse the innocent module against a shape it never wrote.
mk arity
cat > "$work/arity/WideA.ax" <<'EOF'
(pub struct Config
  (port : Int)
  (retries : Int)
  (spare : Int))
EOF
cat > "$work/arity/NarrowB.ax" <<'EOF'
(pub struct Config
  (retries : Int)
  (port : Int))

(pub :: bPort Int)

(pub fn (bPort) (let ((c (Config 3 99))) c.port))
EOF
printf '(import WideA)\n(import NarrowB)\n(:: main Int)\n(fn (main) (bPort))\n' > "$work/arity/run.ax"
printf '(import WideA)\n(import NarrowB)\n(:: pick (-> Config Int))\n(fn (pick c) c.port)\n(:: main Int)\n(fn (main) 0)\n' > "$work/arity/ref.ax"
printf '(import NarrowB)\n(:: pick (-> Config Int))\n(fn (pick c) c.port)\n(:: main Int)\n(fn (main) 0)\n' > "$work/arity/one.ax"

ok_exit  arity run.ax 99 "arity variant: NarrowB compiles against its own shape"
ok_diag  arity ref.ax AX3044 "arity variant: the entry file's bare Config" WideA NarrowB
ok_clean arity one.ax "control: one import, the same reference resolves"

# data
mk dat
cat > "$work/dat/ShA.ax" <<'EOF'
(pub data Shade
  (Aa)
  (Ab))
EOF
cat > "$work/dat/ShB.ax" <<'EOF'
(pub data Shade
  (Ba)
  (Bb))

(pub :: shb (-> Shade Int))

(pub fn (shb s)
  (match s
    ((Ba) 11)
    ((Bb) 22)))

(pub :: shbGo Int)

(pub fn (shbGo) (shb (Bb)))
EOF
printf '(import ShA)\n(import ShB)\n(:: main Int)\n(fn (main) (shbGo))\n' > "$work/dat/run.ax"
printf '(import ShA)\n(import ShB)\n(:: pick (-> Shade Int))\n(fn (pick s) 0)\n(:: main Int)\n(fn (main) 0)\n' > "$work/dat/ref.ax"
printf '(import ShB)\n(:: pick (-> Shade Int))\n(fn (pick s) 0)\n(:: main Int)\n(fn (main) 0)\n' > "$work/dat/one.ax"

ok_exit  dat run.ax 22 "data: ShB's match is exhaustive over ITS Shade"
ok_diag  dat ref.ax AX3044 "data: the entry file's bare Shade" ShA ShB
ok_clean dat one.ax "control: one import, the same reference resolves"

# type alias
mk al
cat > "$work/al/AlA.ax" <<'EOF'
(pub type Amount = Float)

(pub :: aOne Amount)

(pub fn (aOne) 1.5)
EOF
cat > "$work/al/AlB.ax" <<'EOF'
(pub type Amount = Int)

(pub :: bTwice (-> Amount Amount))

(pub fn (bTwice n) (* n 2))

(pub :: bGo Int)

(pub fn (bGo) (bTwice 21))
EOF
printf '(import AlA)\n(import AlB)\n(:: main Int)\n(fn (main) (bGo))\n' > "$work/al/run.ax"
printf '(import AlA)\n(import AlB)\n(:: pick (-> Amount Int))\n(fn (pick a) 0)\n(:: main Int)\n(fn (main) 0)\n' > "$work/al/ref.ax"
printf '(import AlB)\n(:: pick (-> Amount Int))\n(fn (pick a) 0)\n(:: main Int)\n(fn (main) 0)\n' > "$work/al/one.ax"

ok_exit  al run.ax 42 "alias: AlB's Amount is Int inside AlB"
ok_diag  al ref.ax AX3044 "alias: the entry file's bare Amount" AlA AlB
ok_clean al one.ax "control: one import, the same reference resolves"

# ---------------------------------------------------------------
# 3. the escape AX3044's help text names
# ---------------------------------------------------------------
echo "== the escape: a narrowed import leaves the other declaration behind =="
mk esc
cp "$work/two/TeamA.ax" "$work/two/TeamB.ax" "$work/esc/"
printf '(import TeamA (aPort))\n(import TeamB)\n(:: pick (-> Config Int))\n(fn (pick c) c.port)\n(:: main Int)\n(fn (main) (pick (Config 3 99)))\n' > "$work/esc/narrow.ax"
ok_exit esc narrow.ax 99 "\`(import TeamA (aPort))\` resolves the reference to TeamB"

# ---------------------------------------------------------------
# 4. two aliases in one file
# ---------------------------------------------------------------
echo "== one file, two \`type\` declarations of one name =="
mk dup
printf '(type Amt = Int)\n(type Amt = Float)\n(:: main Int)\n(fn (main) 0)\n' > "$work/dup/two.ax"
printf '(type Amt = Int)\n(:: main Int)\n(fn (main) 0)\n' > "$work/dup/one.ax"
ok_diag  dup two.ax AX3006 "two \`type Amt\` in one file" "Amt"
ok_clean dup one.ax "control: one \`type Amt\` is not a duplicate"

# ---------------------------------------------------------------
# 5. scale: the lookup must not grow with the type table
# ---------------------------------------------------------------
echo "== scale: a type reference costs the same in a table twice the size =="
N="${N:-4000}"
K="${K:-6000}"
W="${W:-8}"
BOUND="${BOUND:-1.40}"
REPS="${REPS:-3}"
# Below this the two numbers being divided are timer resolution and
# the ratio reports whatever it likes. Raise N or K, never this.
FLOOR="0.10"

# The two programs are BYTE-IDENTICAL apart from four digits: 2N struct
# declarations with zero-padded, equal-length names, then K signature
# and definition pairs each naming one of those types W times. `a`
# names the FIRST declaration in the table and `b` names the LAST, so
# a forward scan pays one comparison in `a` and 2N in `b`, while a
# bucket keyed on the name pays one entry in both. Same declaration
# count, same line count, same byte count, same reference count - the
# ratio is the scan and nothing else.
#
# No imports, deliberately: `mangleDecl` runs only over IMPORTED
# declarations, and when this gate was written it was quadratic in
# their count (the note in check-name-scale.sh about a per-doubling
# exponent that swamped the thing being measured; that scan was
# indexed on 2026-08-29 and the same gate now holds the exponent
# down). A confound charged to both sides is still a confound when it
# is that large; here there is none to charge.
python3 - "$work" "$N" "$K" "$W" <<'PY'
import sys
work, n, k, w = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), int(sys.argv[4])
total = 2 * n
width = len(str(total - 1))
def gen(path, ref):
    out = ["(struct S%0*d (a : Int) (b : Int))" % (width, i) for i in range(total)]
    arrow = " ".join([ref] * w)
    params = " ".join("p%d" % j for j in range(w))
    for i in range(k):
        out.append("(:: g%d (-> %s Int))" % (i, arrow))
        out.append("(fn (g%d %s) 1)" % (i, params))
    out.append("(:: main Int)")
    out.append("(fn (main) 0)")
    open(path, "w").write("\n".join(out) + "\n")
gen("%s/scale_a.ax" % work, "S%0*d" % (width, 0))
gen("%s/scale_b.ax" % work, "S%0*d" % (width, total - 1))
PY

best_of() { # best_of <entry>
  local entry="$1" i best="" t out rc s e
  for (( i = 0; i < REPS; i++ )); do
    s=$(python3 -c 'import time;print(time.monotonic())')
    out="$( cd "$work" && "$axc" check "$entry" 2>&1 )"; rc=$?
    e=$(python3 -c 'import time;print(time.monotonic())')
    # A compiler that dies early is a very fast compiler and would pass
    # any ratio; this repository has been fooled by exactly that.
    if (( rc != 0 )); then
      echo "FAIL scale: \`check $entry\` exited $rc - this measured a failure, not a compile" >&2
      printf '%s\n' "$out" | tail -5 >&2
      return 1
    fi
    if [[ "$out" != *OK* ]]; then
      echo "FAIL scale: \`check $entry\` exited 0 without printing OK, so it did no work" >&2
      return 1
    fi
    t=$(python3 -c "print($e - $s)")
    if [[ -z "$best" ]] || (( $(python3 -c "print(1 if $t < $best else 0)") )); then best="$t"; fi
  done
  printf '%s' "$best"
}

checks=$((checks + 1))
ta="$(best_of scale_a.ax)"; rca=$?
tb="$(best_of scale_b.ax)"; rcb=$?
if (( rca != 0 || rcb != 0 )); then
  failed=$((failed + 1))
else
  read -r ratio under_floor <<<"$(python3 -c "
a, b = $ta, $tb
print('%.2f' % (b / a), 1 if (a < $FLOOR or b < $FLOOR) else 0)")"
  printf 'check-type-namespace: %s types, %s references  first %.2fs  last %.2fs  ratio %s (bound %s)\n' \
    "$(( N * 2 ))" "$(( K * W ))" "$ta" "$tb" "$ratio" "$BOUND"
  if (( under_floor )); then
    echo "FAIL scale: one of those is under ${FLOOR}s, so the ratio is between two"
    echo "     timer-resolution numbers and asserts nothing. Re-run with a larger K=."
    failed=$((failed + 1))
  elif (( $(python3 -c "print(1 if $ratio >= $BOUND else 0)") )); then
    echo "FAIL scale: naming the LAST type in the table now costs ${ratio}x what"
    echo "     naming the first one costs, so some type lookup has gone back to"
    echo "     scanning. See the type namespace section in self_host/typecheck.ax:"
    echo "     module-aware resolution CANNOT exit on the first match, so without"
    echo "     the index it is a full scan of the program's types per reference."
    failed=$((failed + 1))
  else
    echo "ok   the type table doubled and the reference did not get slower"
  fi
fi

# ---------------------------------------------------------------
echo
if (( failed )); then
  echo "check-type-namespace: $failed of $checks check(s) failed"
  exit 1
fi
echo "check-type-namespace: all $checks checks passed"
