#!/usr/bin/env bash
#
# Name resolution must scale. Three arms, all ratios, all timed on the
# compiler built from this tree:
#
#   1. Private against public. Two modules of one size, differing only
#      in whether the helper half is `pub`, must check in about the same
#      time: the private one under BOUND times the public one. A private
#      name goes through the visibility filter. With an index the two
#      are the same work; with a scan the private side degrades with size.
#   2. N against 2N. Doubling the declarations must cost under DBL_BOUND
#      times the time, on each side. Recording a declaration asks
#      `bares` whether the name is claimed. `bares` answers from an
#      index (`MangleIdx`, self_host/namespace.ax). A scan is quadratic.
#   3. One `let`'s bindings, N against 2N, under LET_BOUND (AN-54). See
#      that arm's section near the end.
#
# Arms 1 and 2 use generated modules of one shape: N private (or public)
# helpers and N public wrappers that each call one.
#
# The standard library is private by default, so every program that
# imports it takes the visibility path. A fast path guarded by a claim
# about the corpus ("nothing here is private") needs a gate that
# re-asks the claim, because the corpus changes. Correctness gates
# cannot see a regression here: a scan gives the right answers, slowly.
#
# Why ratios: a wall-clock bound on a shared runner is flaky, the same
# call `bench-datastructures.sh` and `bench-compile.sh` make. A ratio
# between two runs of one binary on one machine charges the machine to
# both sides, where it cancels.
#
# The bounds:
#   DBL_BOUND is 3.00. Indexed doubling ratios read 1.5 to 2.1, with a
#   2.81 outlier on the darwin-aarch64 runner. Un-indexed ones read 3.2
#   to 4.1. The bound sits in that gap; don't shave it to the current
#   reading, which is how a floor expires.
#   BOUND is 2.00. On the darwin-aarch64 runner arm 1 reads 0.96 to
#   1.26, and slow runs give high ratios. The defect reads about 80 at
#   2N=16000. So 2.00 stays green on a slow runner, sits forty times
#   below the defect, and still refuses any doubling of what a private
#   name costs.
#   Never raise a bound on an arm that nothing ablates: that is how a
#   check becomes one that cannot fail.
#
# Each arm carries its negative, which must fail on the ratio the arm
# asserts, not on the floor. Each ablates one cause in its own scratch
# copy of self_host/, since a compiler carrying two defects proves
# neither arm:
#   arm 1: `fnEntVisibleExact` (self_host/typecheck.ax) branches on
#          `memGetWord tc 20`. Forcing the zero branch makes every
#          lookup fall to `findFnEntVisibleExact`, a scan of every entry
#          filtered by `privBlocks`. The suffix index (`memGetWord tc
#          26`) is left alone: the exact pass dominates
#          `check self_host/main.ax`, so one seam is enough.
#   arm 2: `mangleIdxHas` put back to a scan of `bares`. This is arm 2's
#          cause, not arm 1's: arm 1 passes on that compiler.
#   arm 3: the per-call scan of the `let`'s binders put back.
#
# NEG_N is 4000. The scanning compiler is quadratic, so its doubling
# separation grows with size, while a run at 16000 costs seconds for the
# same verdict. At 2000 its small side sits at FLOOR on GitHub's x86_64
# runner, and the gate refuses its own negative. CI hardware runs the
# negatives too, so size them for the fastest runner.
#
# N is 8000 and may not go lower. Below FLOOR the two numbers divided
# are timer resolution. The indexed compiler reads about 0.12s at
# N=4000, near the floor and under it on a faster machine. A gate that
# fails on the floor when the code is right teaches people to lower it.
# Raise N, never the floor.
#
# `measure_pair` times every private rep, then every public rep.
# Interleaving them, as `web/bench/run-bench.sh` does, would cancel load
# better, but with each bound in a wide gap it buys nothing measurable.
#
# The subject is the compiler `gate_build_axc` builds from this tree,
# not `$axiom`, so an ablation of the working tree is visible.
#
# Every run must print `OK` and exit 0. A compiler that dies early is a
# very fast compiler and would pass any ratio.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

N="${N:-8000}"
BOUND="${BOUND:-2.00}"
DBL_BOUND="${DBL_BOUND:-3.00}"
REPS="${REPS:-3}"
NEG_N=4000
# Arm 1 is a same-size ratio, so its ablation runs at one size. 8000,
# not 16000: the un-indexed private side is quadratic, so 16000 costs
# four times as long for the same verdict. One rep, not REPS: a 40x
# separation needs no best-of.
NEG1_N=8000
FLOOR="0.10"

if (( N < 8000 )); then
  echo "FAIL: N=$N is under 8000. The indexed compiler checks N=4000 in" >&2
  echo "      about 0.12s, within timer resolution of the ${FLOOR}s floor on a" >&2
  echo "      fast runner, and a ratio of two such numbers asserts nothing." >&2
  echo "      Raise N rather than lowering the floor - see the header." >&2
  exit 1
fi

command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH" >&2; exit 1; }

ln -s "$repo_root/stdlib" "$work/stdlib"

# Two modules, same size, same call graph. In `Priv` the helper half is
# module-private and every public wrapper calls one; in `Publ` the same
# helpers are exported. The wrappers are identical in both.
gen() { # gen <file> <helper-vis> <count>
  local out="$1" vis="$2" n="$3" i
  : > "$out"
  for (( i = 0; i < n; i++ )); do
    printf '%s:: h%d (-> Int Int))\n%sfn (h%d n) (+ n %d))\n' "$vis" "$i" "$vis" "$i" "$i" >> "$out"
  done
  for (( i = 0; i < n; i++ )); do
    printf '(pub :: p%d (-> Int Int))\n(pub fn (p%d n) (h%d n))\n' "$i" "$i" "$i" >> "$out"
  done
}

# The pair at size <n>: Priv<n>.ax / Publ<n>.ax and the two entry files
# that import them. Generated once per size, whichever arm asks first.
mk_pair() { # mk_pair <n>
  local n="$1"
  [[ -f "$work/mpriv$n.ax" ]] && return 0
  gen "$work/Priv$n.ax" '(' "$n"
  gen "$work/Publ$n.ax" '(pub ' "$n"
  printf '(import Priv%s)\n(:: main Int)\n(fn (main) (p0 42))\n' "$n" > "$work/mpriv$n.ax"
  printf '(import Publ%s)\n(:: main Int)\n(fn (main) (p0 42))\n' "$n" > "$work/mpubl$n.ax"
}

# Best of REPS. Interference only ever makes a run slower, so the
# minimum is the closest estimate of the cost itself, as in
# `bench-datastructures.sh`.
best_of() { # best_of <compiler> <entry>
  local comp="$1" entry="$2" i best="" t out rc
  for (( i = 0; i < REPS; i++ )); do
    local s e
    s=$(python3 -c 'import time;print(time.monotonic())')
    out="$( cd "$work" && "$comp" check "$entry" 2>&1 )"; rc=$?
    e=$(python3 -c 'import time;print(time.monotonic())')
    if (( rc != 0 )); then
      echo "FAIL: \`check $entry\` exited $rc - this gate measured a failure, not a compile" >&2
      echo "$out" | tail -5 >&2
      exit 1
    fi
    if [[ "$out" != *OK* ]]; then
      echo "FAIL: \`check $entry\` exited 0 without printing OK, so it did no work" >&2
      exit 1
    fi
    t=$(python3 -c "print($e - $s)")
    if [[ -z "$best" ]] || (( $(python3 -c "print(1 if $t < $best else 0)") )); then best="$t"; fi
  done
  printf '%s' "$best"
}

# Time both sides at size <n> with <compiler>: sets TP (private) and
# TQ (public).
measure_pair() { # measure_pair <compiler> <n>
  local comp="$1" n="$2"
  mk_pair "$n"
  TP="$(best_of "$comp" "mpriv$n.ax")" || exit 1
  TQ="$(best_of "$comp" "mpubl$n.ax")" || exit 1
}

# The doubling verdict, shared by the live arm and the ablated one so
# the two cannot drift apart. Prints the line and returns 0 when both
# ratios are under DBL_BOUND, 1 when either is at or over it, and 2 when
# a small-side time is under FLOOR, which is no verdict at all.
doubling_verdict() { # doubling_verdict <label> <n> <tp1> <tq1> <tp2> <tq2>
  local label="$1" n="$2" tp1="$3" tq1="$4" tp2="$5" tq2="$6"
  local rp rq under over
  read -r rp rq under over <<<"$(python3 -c "
p1, q1, p2, q2 = $tp1, $tq1, $tp2, $tq2
rp, rq = p2 / p1, q2 / q1
print('%.2f' % rp, '%.2f' % rq,
      1 if (p1 < $FLOOR or q1 < $FLOOR) else 0,
      1 if (rp >= $DBL_BOUND or rq >= $DBL_BOUND) else 0)")"
  printf 'check-name-scale: %s N=%s->%s  private %.2fs->%.2fs (x%s)  public %.2fs->%.2fs (x%s)  (bound %s)\n' \
    "$label" "$n" "$(( 2 * n ))" "$tp1" "$tp2" "$rp" "$tq1" "$tq2" "$rq" "$DBL_BOUND"
  if (( under )); then return 2; fi
  if (( over )); then return 1; fi
  return 0
}

failed=0

# --------------------------------------------------------------------
# The live compiler, at N and 2N.
# --------------------------------------------------------------------
measure_pair "$axc" "$N";            tp1="$TP"; tq1="$TQ"
measure_pair "$axc" "$(( 2 * N ))";  tp2="$TP"; tq2="$TQ"

# Arm 1: private against public, at 2N.
read -r ratio under_floor <<<"$(python3 -c "
p, q = $tp2, $tq2
print('%.2f' % (p / q), 1 if (p < $FLOOR or q < $FLOOR) else 0)")"

printf 'check-name-scale: N=%s  private %.2fs  public %.2fs  ratio %s (bound %s)\n' \
  "$(( 2 * N ))" "$tp2" "$tq2" "$ratio" "$BOUND"

if (( under_floor )); then
  echo "FAIL: one of those is under ${FLOOR}s, so the ratio is between two" >&2
  echo "      timer-resolution numbers and asserts nothing. Re-run with a" >&2
  echo "      larger N=." >&2
  exit 1
fi

if (( $(python3 -c "print(1 if $ratio >= $BOUND else 0)") )); then
  echo "FAIL: resolving a module's PRIVATE names now costs ${ratio}x what its" >&2
  echo "      public ones cost. Some lookup on the visibility path has gone" >&2
  echo "      back to scanning the function table - see \`findFnEnt\` and the" >&2
  echo "      index sections in self_host/typecheck.ax, and the note at the" >&2
  echo "      top of this file for how that happened the first time." >&2
  failed=1
fi

# Arm 2: N against 2N, both sides.
doubling_verdict "indexed" "$N" "$tp1" "$tq1" "$tp2" "$tq2"
case $? in
  0) ;;
  1)
    echo "FAIL: doubling the module's declarations costs more than ${DBL_BOUND}x" >&2
    echo "      on at least one side. Recording a declaration has gone back to" >&2
    echo "      scanning \`bares\` - see \`MangleIdx\` and the writers below it in" >&2
    echo "      self_host/namespace.ax, and this file's header for what the" >&2
    echo "      scan cost before it was indexed." >&2
    failed=1 ;;
  2)
    echo "FAIL: a small-side time is under ${FLOOR}s, so the doubling ratio is" >&2
    echo "      between timer-resolution numbers and asserts nothing. Re-run" >&2
    echo "      with a larger N=." >&2
    exit 1 ;;
esac

# --------------------------------------------------------------------
# The negative: the scan put back, in a scratch copy, must fail arm 2.
# --------------------------------------------------------------------
# A copy, never the tree: a gate that edits the checkout and dies before
# restoring it leaves an ablation behind for every later gate to build.
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/" || {
  echo "FAIL: could not copy the tree to ablate" >&2; exit 1; }

# Anchored on the whole function: a `match` on `internFind` is a shape
# other indexes share, and a bare substitution would edit whichever
# matched first. A mismatch is a hard failure, not a skip, because an
# ablation that no longer applies leaves the red half proving nothing.
#
# The scan comes back as `mangleScanIn`, typed `(Vec String)` because
# it reads every element with `vecGetStr`. A scan under its own name
# keeps the ablation independent of `mangleHasIn`'s signature.
# `check-contracts.sh`'s `guard-restored` ablation uses the same shape.
# The restored scan is a precondition interface because `vecGetStr` is
# one (R-B6): an untagged caller is AX3073, and a trusted one would
# leave `mangleIdxHas`'s own `effect(unsafe)` with nothing to support
# it (AX3010).
if ! python3 - "$abl/self_host/namespace.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = """(pub fn (mangleIdxHas idx bares name)
  {
    (mangleIdxSync idx bares)
    (match (internFind (memGetWord idx 0) name)
      ((Some _) true)
      ((None) false))
  })"""
new = """(pub fn (mangleIdxHas idx bares name)
  {
    (mangleIdxSync idx bares)
    (mangleScanIn bares name 0)
  })

(pub :: mangleScanIn (-> (Vec String) String Int Bool))
;@axiom:effect(unsafe)
;@axiom:precondition(every element of `bares` is a live `String`)
(pub fn (mangleScanIn bares bare i)
  (if (>= i (vecLen bares))
    false
    (if (strEq (vecGetStr bares i) bare)
      true
      (mangleScanIn bares bare (+ i 1)))))"""
n = s.count(old)
if n != 1:
    sys.exit("the mangleIdxHas ablation matched %d times, wanted 1" % n)
open(p, "w").write(s.replace(old, new))
PY
then
  echo "FAIL: could not ablate \`mangleIdxHas\` - its shape has moved, so the" >&2
  echo "      red half of this gate proves nothing. Re-anchor the ablation." >&2
  exit 1
fi

echo "-- rebuilding the compiler with the scan put back --"
if ! gate_build_tree "$axiom" "$abl" "$abl/stdlib" \
       "$work/axc-scan" >"$work/scan.build.log" 2>&1; then
  echo "FAIL: the ablated compiler did not build" >&2
  sed 's/^/    /' "$work/scan.build.log" | head -20 >&2
  exit 1
fi

measure_pair "$work/axc-scan" "$NEG_N";            np1="$TP"; nq1="$TQ"
measure_pair "$work/axc-scan" "$(( 2 * NEG_N ))";  np2="$TP"; nq2="$TQ"

doubling_verdict "ablated" "$NEG_N" "$np1" "$nq1" "$np2" "$nq2"
case $? in
  1) echo "check-name-scale: the ablated compiler fails the doubling arm, so the arm is load-bearing" ;;
  0)
    echo "FAIL: putting the scan back did NOT fail the doubling arm, so this" >&2
    echo "      gate cannot fail on the defect it exists for. Either the arm's" >&2
    echo "      subject stopped reaching \`mangleIdxHas\` or the bound has" >&2
    echo "      drifted above the scan's exponent." >&2
    failed=1 ;;
  2)
    echo "FAIL: the ablated compiler's small side is under ${FLOOR}s at" >&2
    echo "      NEG_N=$NEG_N, so its verdict is noise and the negative proves" >&2
    echo "      nothing. Raise NEG_N in this script." >&2
    failed=1 ;;
esac

# --------------------------------------------------------------------
# Arm 1's negative: the visibility index forced off, in a second
# scratch copy, must fail arm 1.
# --------------------------------------------------------------------
# A separate tree from arm 2's. The arms have different causes, and one
# compiler carrying both defects would let either arm's failure stand in
# for the other's.
abl1="$work/tree1"
mkdir -p "$abl1"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl1/" || {
  echo "FAIL: could not copy the tree to ablate for arm 1" >&2; exit 1; }

# Anchored on the whole function. `fnEntVisibleSuffix` reads slot 26
# with the same two-branch shape, so a substitution anchored on the `if`
# alone would edit whichever came first. The `effect(unsafe)` tag goes
# with the index read: the scan alone performs no unsafe operation, and
# a claim with nothing under it is AX3010 (R-B6).
if ! python3 - "$abl1/self_host/typecheck.ax" <<'PY_ABL'
import sys
p = sys.argv[1]
s = open(p).read()
old = ''';@axiom:effect(unsafe)
(pub fn (fnEntVisibleExact tc privs name curMod)
  (if (== (memGetWord tc 20) 0)
    (findFnEntVisibleExact privs (tcFnsVec tc) name curMod)
    (fnIdxGetVisible (memGetWordVec tc 20) privs name curMod)))'''
new = '''(pub fn (fnEntVisibleExact tc privs name curMod)
  (findFnEntVisibleExact privs (tcFnsVec tc) name curMod))'''
n = s.count(old)
if n != 1:
    sys.exit("the fnEntVisibleExact ablation matched %d times, wanted 1" % n)
open(p, "w").write(s.replace(old, new))
PY_ABL
then
  echo "FAIL: could not ablate \`fnEntVisibleExact\` - its shape has moved, so" >&2
  echo "      arm 1 has no negative and its bound rests on nothing." >&2
  echo "      Re-anchor the ablation." >&2
  exit 1
fi

echo "-- rebuilding the compiler with the visibility scan put back --"
if ! gate_build_tree "$axiom" "$abl1" "$abl1/stdlib" \
       "$work/axc-noidx" >"$work/noidx.build.log" 2>&1; then
  echo "FAIL: the arm-1 ablated compiler did not build" >&2
  sed 's/^/    /' "$work/noidx.build.log" | head -20 >&2
  exit 1
fi

# One rep, at one size. The separation is 40x, and a best-of-three would
# spend a minute of un-indexed private checks for no sharper verdict.
mk_pair "$NEG1_N"
saved_reps="$REPS"; REPS=1
measure_pair "$work/axc-noidx" "$NEG1_N"; ap="$TP"; aq="$TQ"
REPS="$saved_reps"

read -r aratio aunder <<<"$(python3 -c "
p, q = $ap, $aq
print('%.2f' % (p / q), 1 if (p < $FLOOR or q < $FLOOR) else 0)")"

printf 'check-name-scale: ablated N=%s  private %.2fs  public %.2fs  ratio %s (bound %s)\n' \
  "$NEG1_N" "$ap" "$aq" "$aratio" "$BOUND"

if (( aunder )); then
  echo "FAIL: the arm-1 ablated compiler's public side is under ${FLOOR}s at" >&2
  echo "      NEG1_N=$NEG1_N, so its ratio is against a timer-resolution" >&2
  echo "      number and the negative proves nothing. Raise NEG1_N." >&2
  failed=1
elif (( $(python3 -c "print(1 if $aratio >= $BOUND else 0)") )); then
  echo "check-name-scale: the ablated compiler fails arm 1, so the arm is load-bearing"
else
  echo "FAIL: forcing the visibility scan back did NOT fail arm 1 (ratio" >&2
  echo "      $aratio, bound $BOUND), so this arm cannot fail on the defect it" >&2
  echo "      exists for. Either the arm's subject stopped reaching" >&2
  echo "      \`fnEntVisibleExact\` or BOUND has drifted above the scan's cost." >&2
  failed=1
fi

# --------------------------------------------------------------------
# Arm 3: bindings in one `let`. Doubling them must not multiply the
# time to reach LLVM IR by LET_BOUND or more (AN-54).
# --------------------------------------------------------------------
# For each binding, the emitter decides whether it escapes by walking
# the rest of the `let`. Asking, per call, whether its head is a local
# by walking the whole root (`boundWithin`) and scanning the symbols
# (`lookupSym`) is cubic. Instead the walk reads a summary of the root's
# binders, built once per binding, and memoises each head's answer
# (`binderSummary`, `headIsLocal` in self_host/codegen.ax). What is left
# is quadratic: a doubling ratio tending to 4, where cubic tends to 8.
# Each binding makes two calls, `(Cell (strDup "none"))`, which doubles
# the cubic term and leaves the memoised walk as it is. From 500 to
# 1,000 bindings the live compiler reads about x3.4 and the ablated one
# about x7.1, so LET_BOUND sits between them.
LET_N="${LET_N:-500}"
LET_BOUND="${LET_BOUND:-5.50}"

gen_let() { # gen_let <file> <count>
  local out="$1" n="$2" i
  {
    printf '(import IO)\n(struct Cell\n  (name : String))\n\n(:: main Int)\n;@axiom:effect(io)\n(fn (main)\n  (let (\n'
    for (( i = 0; i < n; i++ )); do printf '    (c%d (Cell (strDup "none")))\n' "$i"; done
    printf '  )\n    {\n      (println c0.name)\n      0\n    }))\n'
  } > "$out"
}

emit_best() { # emit_best <compiler> <n> <reps>: the best emit-llvm time
  local comp="$1" n="$2" reps="$3" i best="" s e t
  [[ -f "$work/let$n.ax" ]] || gen_let "$work/let$n.ax" "$n"
  for (( i = 0; i < reps; i++ )); do
    s=$(python3 -c 'import time;print(time.monotonic())')
    if ! ( cd "$work" && "$comp" emit-llvm "let$n.ax" -o "let$n.ll" ) >"$work/let.log" 2>&1; then
      echo "FAIL: \`emit-llvm let$n.ax\` failed - this arm measured a failure" >&2
      tail -5 "$work/let.log" >&2
      exit 1
    fi
    e=$(python3 -c 'import time;print(time.monotonic())')
    t=$(python3 -c "print($e - $s)")
    if [[ -z "$best" ]] || (( $(python3 -c "print(1 if $t < $best else 0)") )); then best="$t"; fi
  done
  printf '%s' "$best"
}

let_verdict() { # let_verdict <label> <t1> <t2> <n>: 0 under, 1 over, 2 under the floor
  local r
  r="$(python3 -c "print('%.2f' % ($3 / $2))")"
  printf 'check-name-scale: %s let bindings N=%s->%s  %.2fs->%.2fs (x%s, bound %s)\n' \
    "$1" "$4" "$(( 2 * $4 ))" "$2" "$3" "$r" "$LET_BOUND"
  if (( $(python3 -c "print(1 if $2 < $FLOOR else 0)") )); then return 2; fi
  if (( $(python3 -c "print(1 if $r >= $LET_BOUND else 0)") )); then return 1; fi
  return 0
}

lt1="$(emit_best "$axc" "$LET_N" "$REPS")"
lt2="$(emit_best "$axc" "$(( 2 * LET_N ))" "$REPS")"
let_verdict "live" "$lt1" "$lt2" "$LET_N"
case $? in
  0) ;;
  1)
    echo "FAIL: doubling one \`let\`'s bindings costs ${LET_BOUND}x or more to emit." >&2
    echo "      The escape walk has gone back to a per-call scan - see" >&2
    echo "      \`binderSummary\` and \`headIsLocal\` in self_host/codegen.ax." >&2
    failed=1 ;;
  2)
    echo "FAIL: the small side is under ${FLOOR}s, so the ratio is noise." >&2
    echo "      Raise LET_N." >&2
    exit 1 ;;
esac

# The negative, in a third scratch copy: a scan of the `let`'s binders
# and of the symbols for every call. Removing only the memo does not
# fail, because the symbol scan it saves is cheap beside the walk. The
# binders' scan is what makes the per-call walk expensive.
abl3="$work/tree3"
mkdir -p "$abl3"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl3/" || {
  echo "FAIL: could not copy the tree to ablate for arm 3" >&2; exit 1; }
if ! python3 - "$abl3/self_host/codegen.ax" <<'PY_LET'
import sys
p = sys.argv[1]
s = open(p).read()
old = "              (if (== (headIsLocal cg n bound) 1)"
new = "              (if (|| (!= (lookupSym cg n) 0) (|| (>= (paramIndexOf cg n) 0) (== (boundInScan n bound) 1)))"
n = s.count(old)
if n != 1:
    sys.exit("the headIsLocal ablation matched %d times, wanted 1" % n)
s = s.replace(old, new)
anchor = "(pub :: boundIn (-> String Int Int))"
if s.count(anchor) != 1:
    sys.exit("the boundIn anchor matched %d times, wanted 1" % s.count(anchor))
scan = """(pub :: boundInScan (-> String Int Int))
;@axiom:effect(unsafe)
(pub fn (boundInScan name sum)
  (if (== (memGetWord sum 0) 1)
    1
    (let (
      (set (memGetWord sum 1))
      (mut i 0)
      (mut hit 0)
    )
      {
        (while (< i (internCount set))
          {
            (if (strEq (internLookup set i) name)
              (set hit 1)
              0)
            (set i (+ i 1))
          })
        hit
      })))

"""
open(p, "w").write(s.replace(anchor, scan + anchor))
PY_LET
then
  echo "FAIL: could not ablate \`headIsLocal\` - its call or \`boundIn\` has moved, so arm 3" >&2
  echo "      has no negative. Re-anchor the ablation." >&2
  exit 1
fi
echo "-- rebuilding the compiler with the per-call scan put back --"
if ! gate_build_tree "$axiom" "$abl3" "$abl3/stdlib" \
       "$work/axc-letscan" >"$work/letscan.build.log" 2>&1; then
  echo "FAIL: the arm-3 ablated compiler did not build" >&2
  sed 's/^/    /' "$work/letscan.build.log" | head -20 >&2
  exit 1
fi
# Best of REPS on the small side, where interference would lower the
# ratio; one run on the large side, where it could only raise it.
at1="$(emit_best "$work/axc-letscan" "$LET_N" "$REPS")"
at2="$(emit_best "$work/axc-letscan" "$(( 2 * LET_N ))" 1)"
let_verdict "ablated" "$at1" "$at2" "$LET_N"
case $? in
  1) echo "check-name-scale: the ablated compiler fails arm 3, so the arm is load-bearing" ;;
  0)
    echo "FAIL: the per-call scan put back did NOT fail arm 3, so this arm cannot" >&2
    echo "      fail on the defect it exists for." >&2
    failed=1 ;;
  2)
    echo "FAIL: the arm-3 ablated compiler's small side is under ${FLOOR}s." >&2
    failed=1 ;;
esac

if (( failed )); then
  exit 1
fi

echo "check-name-scale: gate passed"
