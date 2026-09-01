#!/usr/bin/env bash
#
# A module's PRIVATE declarations must cost no more to resolve than its
# public ones, and DOUBLING a module's declarations must not quadruple
# the time to resolve them.
#
# WHY THIS EXISTS, and it is the whole story. `8942644` indexed
# `findFnEnt`, which had been three linear scans of a ~1,600-entry table
# per name reference: `check self_host/main.ax` 0.89s -> 0.17s. Its own
# note (the self-hosting record) recorded what was left linear on
# purpose - `findFnEntVisibleExact`/`Suffix`, "which only run when a
# program declares something private", and then the sentence this gate
# exists because of:
#
#     the count of those in this repository is zero
#
# It was zero for FOUR HOURS. `3b6d485`, the same afternoon, made the
# standard library private by default - 151 names, 288 declarations - so
# every program in the repository, and every program that imports it,
# started taking the un-indexed branch. The index was dead for eight
# days and the number that would have shown it was never taken, because
# 32.4 also decided - explicitly, with reasons - that this change would
# ship with no speed gate of its own. Every correctness gate stayed
# green throughout, as they should have: the answers were right, they
# were just arrived at by scanning.
#
# So the lesson is not "add a benchmark". It is that a fast path guarded
# by a claim about the CORPUS ("nothing here is private") needs a gate
# that re-asks the claim, because the corpus is what changes.
#
# WHAT IT ASSERTS. Two arms, both ratios, both taken on the compiler
# built from THIS tree, over generated modules of one shape: N private
# (or public) helpers and N public wrappers that each call one.
#
#   1. PRIVATE AGAINST PUBLIC. Two modules of identical size, differing
#      only in whether the helper half is `pub`, must check in about
#      the same time - the private one no more than BOUND times the
#      public one. Resolving a private name goes through the visibility
#      filter and a public one does not; if the filter is indexed the
#      two are the same work, and if it is a table scan the private
#      side degrades with the program.
#
#   2. N AGAINST 2N. The same two modules at twice the declaration
#      count must check in no more than DBL_BOUND times the time, on
#      each side. Recording a declaration asks `bares` whether the name
#      is claimed, once for a private one and twice for a public one,
#      and until 2026-08-29 `bares` answered by scanning itself
#      (`mangleHasIn`, self_host/namespace.ax) - quadratic in the
#      declaration count, and the compile-time ceiling the enterprise
#      plan named. It answers from an index now (`MangleIdx`, the note
#      above it says why the index is a separate structure and why it
#      cannot go stale), and this arm is what keeps it one.
#
# WHY RATIOS, rather than the obvious shape: NOT a wall-clock bound. A
# second on a shared runner is a flaky test - the same call
# `bench-datastructures.sh` and `bench-compile.sh` both make. A ratio
# between two runs of the same binary on the same machine charges the
# machine to both sides, where it cancels.
#
# WHY THERE WAS NO DOUBLING ARM BEFORE, because this header used to
# refuse one, with a measurement: per-doubling exponents on this corpus
# were ~4x on BOTH sides of the `findFnEnt` fix (indexed 3.7/3.9,
# un-indexed 4.2/4.7), because the `mangleHasIn` scan was 55.7% of a
# check at N=8000 and dominated whatever else was measured, so "a
# doubling gate would therefore have passed on the broken code". That
# was true, and it is why arm 1 was written as a ratio between two
# programs of the SAME size. The scan is gone, the exponent is
# arm 2's subject, and 55.7% understated it: at N=8000 the indexed
# compiler is fifteen times faster on the public module.
#
# MEASURED, 2026-08-29, best of three, each compiler built from its tree
# by the same parent (0.3.6 seed), darwin-aarch64:
#
#     un-indexed, df60fdb    N=2000   private 0.18s   public 0.24s
#                            N=4000   private 0.56s   public 0.83s   3.14x / 3.45x
#                            N=8000   private 2.12s   public 3.26s   3.78x / 3.93x
#                            N=16000  private 7.09s   public 11.76s  3.25x / 3.58x
#     indexed                N=2000   private 0.08s   public 0.08s
#                            N=4000   private 0.12s   public 0.12s   1.58x / 1.63x
#                            N=8000   private 0.23s   public 0.22s   1.83x / 1.76x
#                            N=16000  private 0.43s   public 0.42s   1.89x / 1.91x
#
# DBL_BOUND is 2.80: above the indexed side's 1.6-1.9 by a margin no
# runner's noise reaches in a ratio of two best-of-three runs, below
# the un-indexed side's 3.1-3.9 at every N measured, 16000 included,
# and the number the enterprise plan asked for. It is not shaved to the
# current reading, which is how a floor expires.
#
# BOUND for arm 1 is still 1.20. Its own negative, from the day it was
# written (built from HEAD~ and HEAD by the same parent, N=4000):
# un-indexed private 1.26s public 0.60s ratio 2.10 FAILS; indexed 0.37s
# against 0.60s ratio 0.62 passes. The indexed ratio was below one
# because a private declaration took one `mangleHasIn` scan and a
# public one two; with the scan gone the two sides read within 5% of
# each other (1.04 at N=8000, 1.03 at N=16000), so the bound now sits
# above the reading by a smaller margin than it did - which is why the
# arm is taken at 2N, the larger and steadier of the two sizes.
#
# THE NEGATIVE IS IN THE SCRIPT, which is this repository's rule for a
# new test, and it ablates the CAUSE: a scratch copy of self_host/ has
# `mangleIdxHas` put back to the scan, the same parent builds a compiler
# from it, and the doubling arm must FAIL on that compiler - and fail on
# the RATIO, not on the floor, because an arm that fails for a reason
# other than the one it asserts has proved nothing. It is taken at
# NEG_N=2000: the un-indexed compiler costs 3.3s a run at N=8000 and
# 11.8s at 16000, which would triple this gate to prove a shape that
# N=2000 already shows at 3.41x (public) and 3.24x (private) - and the
# table above shows at every size. Run inside a pristine df60fdb tree,
# this script's own doubling arm reads 3.25x / 3.58x at 8000->16000
# and exits 1, which is the pre-change failure a new gate owes.
#
# THE COMPILER MEASURED IS THE TREE'S. Until 2026-08-29 this gate timed
# `$axiom` - the builder, a seed-descended binary from `.axiom-bin/` or
# `$AXIOM` - and never built from self_host/ at all, so an ablation of
# namespace.ax in the working tree was invisible to it and every number
# it printed was about a binary nobody had just changed. It builds the
# subject with `gate_build_axc` now, like its thirty-seven siblings.
#
# WHY N IS 8000 AND MAY NOT GO LOWER. Below FLOOR the two numbers being
# divided are timer resolution and the ratio reports whatever it likes.
# The indexed compiler reads 0.12s at N=4000 - within 20% of the floor
# on this machine, under it on a faster one - and a gate that fails on
# the floor when the code is right teaches people to lower the floor.
# So N=8000 (0.22s, 2N 0.42s), and an N under 8000 is refused rather
# than measured. Raise N, never the floor.
#
# AND IT CHECKS THE WORK WAS DONE. Every run must print `OK` and exit 0.
# A compiler that dies early is a very fast compiler and would pass any
# ratio; this repository has been fooled by exactly that three times.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

N="${N:-8000}"
BOUND="${BOUND:-1.20}"
DBL_BOUND="${DBL_BOUND:-2.80}"
REPS="${REPS:-3}"
NEG_N=2000
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

# Best of REPS. The distribution is one-sided - interference only ever
# makes a run slower - so the minimum is the closest estimate of the
# cost itself, which is `bench-datastructures.sh`'s methodology.
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
# the two cannot drift apart. Prints the line; answers 0 when both
# ratios are under DBL_BOUND, 1 when either is at or over it, and 2
# when a small-side time is under FLOOR, which is not a verdict at all.
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
# A COPY, never the tree: a gate that edits the checkout and dies before
# restoring it leaves an ablation behind that every later gate builds
# from.
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/" || {
  echo "FAIL: could not copy the tree to ablate" >&2; exit 1; }

# Anchored on the whole function, not on the one line: a `match` on
# `internFind` is a shape other indexes share, and a bare substitution
# would edit whichever matched first. RE-ANCHORED when `internFind`
# became `(Option Int)` - the body this replaces is the port's, and an
# ablation that no longer matches makes the red half of this gate prove
# nothing, which is why the mismatch is a hard failure below rather
# than a skip.
if ! python3 - "$abl/self_host/namespace.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
old = """(pub fn (mangleIdxHas idx bares name)
  {
    (mangleIdxSync idx bares)
    (match (internFind (memGetWord idx 0) name)
      ((Some _) true)
      ((None) false)
    )
  }
)"""
new = """(pub fn (mangleIdxHas idx bares name)
  {
    (mangleIdxSync idx bares)
    (mangleHasIn bares name 0)
  }
)"""
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
if ! AXIOM_STDLIB="$abl/stdlib" "$axiom" build --input "$abl/self_host/main.ax" \
       --output "$work/axc-scan" >"$work/scan.build.log" 2>&1; then
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

if (( failed )); then
  exit 1
fi

echo "check-name-scale: gate passed"
