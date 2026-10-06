#!/usr/bin/env bash
#
# A type name means what its own module says it means, and finding that
# declaration does not cost a scan of the program.
#
# `mangleDecl` (self_host/namespace.ax) renames `fn` and `::`
# declarations to `Mod$name` and nothing else, so `data`, `struct` and
# `type` names reach the merged declaration list as their module wrote
# them. A lookup that took the first match by name would depend on
# import order:
#
#     TeamA.ax  (pub struct Config (port : Int) (retries : Int))
#     TeamB.ax  (pub struct Config (retries : Int) (port : Int))
#               (pub fn (bPort) (let ((c (Config 3 99))) c.port))
#     app.ax    (import TeamA) (import TeamB) (fn (main) (bPort))
#
# The right answer is 99. A first-match lookup compiles TeamB's own
# function against TeamA's field offsets and answers 3, with no
# diagnostic. The same root turns a `data` collision into AX3005, an
# arity difference into AX3008 and an alias collision into AX3004, each
# blamed on the module that wrote its code correctly.
#
# What each section asserts:
#
#   1  Resolution. The two-team probe answers 99 with the imports in
#      both orders. Either order alone is half a test: a first-match
#      lookup also answers 99 when TeamB comes first. A control (TeamB
#      alone) shows 99 needs no collision, and a mutant of TeamB that
#      reads its other field must not answer 99, which proves the
#      section reads a real exit status.
#
#   2  Refusal. A bare reference that two modules can both answer and
#      neither owns is AX3044, naming both modules. Asserted for
#      `struct`, `data` and `type`, each with a control that drops one
#      import and must check clean, so the diagnostic is charged to the
#      collision.
#
#   3  The escapes. An import name list decides what a module exports
#      to this program, so `(import TeamA (aPort))` hides TeamA's
#      `Config` and the reference resolves. Qualification (`TeamC::Cfg`)
#      is the other. AX3044's help text names both, so both run here.
#
#   4  One file, two aliases. Two `(type Amt = ...)` in one file are
#      AX3006, as two `(struct Amt ...)` are.
#
#   5  Scale. Module-aware resolution cannot stop at the first match:
#      deciding that a name is unambiguous means seeing every
#      declaration of it. Without an index that is a scan of the whole
#      type table at every type reference. Two programs differ only in
#      the type their references name: the first of 2N declarations,
#      or the last. A scan pays 2N times as much for the last; a bucket
#      keyed on the name pays the same for both.
#
# The in-gate controls cannot show this gate red against a compiler
# with the defect, because that needs a second compiler build. To run
# that ablation by hand, revert the module-aware type lookup in
# `self_host/typecheck.ax` and `self_host/explain.ax` in a copy of the
# tree and run this script from that copy. `gate_build_axc` builds the
# copy's compiler (a shared `AXIOM_AXC` is skipped, as its stamp no
# longer matches), and sections 1, 2, 4 and 5 should fail.
#
# The scale bound is 1.40. An indexed lookup measures close to 1, and a
# linear scan more than ten times that. See check-name-scale.sh's note
# on how a floor expires.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

gate_build_axc axc

failed=0
checks=0

# `run` writes an executable beside the entry file, and modules are
# found in the entry file's directory. One directory per probe keeps
# same-named modules in different probes apart.
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
# message. The module names are passed that way because "names both
# modules" is the assertion; a check for the code alone would pass a
# diagnostic that named neither.
ok_diag() {
  local d="$1" entry="$2" code="$3" label="$4"; shift 4
  local out rc bad="" w
  checks=$((checks + 1))
  # Twice: once for the exit status, once for the text with the colour
  # escapes stripped. A pipeline's `$?` is the last stage's, so reading
  # the status off the `sed` would pass every case.
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
# The mutant: TeamB's own code reading its other field. The right answer
# is 3, so a harness that ignores exit statuses, or a probe that answers
# 99 for some reason of its own, is caught here.
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

# struct, with an arity difference between the two: a first-match lookup
# refuses NarrowB as AX3008 against WideA's shape.
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

# The other escape the help text names: `Mod::Name` in type position
# picks one declaration out of the collision. The field read shows
# which: `port` is first in TeamC and second in TeamD, so the wrong
# module answers 99.
mk qual
cat > "$work/qual/TeamC.ax" <<'EOF'
(pub struct Cfg
  (port : Int)
  (tag : Int))

(pub :: mkC (-> Int Int Cfg))

(pub fn (mkC a b) (Cfg a b))
EOF
cat > "$work/qual/TeamD.ax" <<'EOF'
(pub struct Cfg
  (tag : Int)
  (port : Int))

(pub :: mkD (-> Int Int Cfg))

(pub fn (mkD a b) (Cfg a b))
EOF
printf '(import TeamC)\n(import TeamD)\n(:: pick (-> TeamC::Cfg Int))\n(fn (pick c) c.port)\n(:: main Int)\n(fn (main) (pick (TeamC::mkC 3 99)))\n' > "$work/qual/qual.ax"
ok_exit qual qual.ax 3 "\`TeamC::Cfg\` resolves the reference to TeamC"

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
# The defaults keep each check a few times above FLOOR on a fast runner.
# Smaller programs finish under it, and a ratio of two timer-resolution
# numbers means nothing.
N="${N:-8000}"
K="${K:-24000}"
W="${W:-8}"
BOUND="${BOUND:-1.40}"
REPS="${REPS:-3}"
# Below this the two numbers being divided are timer resolution and
# the ratio reports whatever it likes. Raise N or K, never this.
FLOOR="0.10"

# The two programs are byte-identical apart from the type name every
# reference uses: 2N struct declarations with zero-padded, equal-length
# names, then K signature and definition pairs each naming one of those
# types W times. `a` names the first declaration in the table and `b`
# the last, so a forward scan pays one comparison in `a` and 2N in `b`,
# while a bucket keyed on the name pays one entry in both. Every other
# count is equal, so the ratio measures the scan and nothing else.
#
# No imports: `mangleDecl` runs only over imported declarations, so
# leaving them out keeps its cost out of the ratio. A large cost on both
# sides still pulls the ratio towards 1 and would hide a scan.
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
    # A compiler that dies early is fast and would pass any ratio, so a
    # failed or silent check fails the gate.
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
