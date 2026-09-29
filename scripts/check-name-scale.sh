#!/usr/bin/env bash
#
# A module's PRIVATE declarations must cost no more to resolve than its
# public ones, DOUBLING a module's declarations must not quadruple
# the time to resolve them, and doubling one `let`'s bindings must not
# multiply the time to emit them by 5.5 (arm 3, near the end).
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
# DBL_BOUND is 3.00: above the indexed side's 1.5-2.1 by a margin the
# 2026-09-09 darwin-aarch64 leg's 2.81x outlier still clears, below the
# un-indexed side's 3.2-4.1 at every N measured (3.25x/3.58x at
# 8000->16000, 3.35x minimum of the in-gate ablation at 4000->8000),
# and the enterprise plan's number moved with the measurement. It is
# not shaved to the current reading, which is how a floor expires.
#
# HISTORY, because a bound moved without one is a bound that cannot be
# trusted. 2.80 was above the indexed 1.6-1.9 by what was believed to
# be a margin no runner's noise reaches in a ratio of two best-of-three
# runs. On 2026-09-09 the darwin-aarch64 leg of the fix/trunk-ci PR
# read private 0.23s->0.66s (x2.81) public 0.32s->0.49s (x1.53) on a
# tree whose only delta from two green legs (x1.75/x1.57,
# x1.90/x2.06) was the seed-lineage comparison and the site count -
# neither of which the timed compiler reads. Same code, green twice,
# red once: the machine, not the tree. 3.00 keeps every ablated
# reading red with at least 0.25 to spare and clears the worst indexed
# reading by 0.19.
#
# BOUND for arm 1 WAS 1.20, and on 2026-09-04 it was measuring the
# runner rather than the property. Two darwin CI legs went red on it
# inside four hours - 1.26 both times - on a tree whose only change was
# website copy, and the same tree read 1.19 an hour later. The
# distribution says why: across ten runs the darwin-aarch64 leg reads
# 0.96 to 1.26, mean 1.120, sd 0.080, so mu+2sd is 1.280 and the
# ceiling was 1.20. The ratio also tracks the runner's ABSOLUTE speed
# (Pearson r = 0.883, slow runs give high ratios), which is the
# definition of measuring the machine. The two Linux legs read
# 1.01-1.04 and this development machine reads 1.02-1.11, so 1.20 was
# calibrated on hardware that is not the hardware it has to pass on.
#
# THE SIGNAL IS 80x, AND THE BOUND WAS SITTING IN THE NOISE. What this
# arm exists to catch is not a 26% drift. Measured 2026-09-04 on
# darwin-aarch64 with the ablation this script now carries - the
# visibility index forced off, `fnEntVisibleExact` answering from
# `findFnEntVisibleExact` - at 2N=16000:
#
#     indexed    private  0.356s   public 0.345s   ratio  1.03
#     ablated    private 30.859s   public 0.385s   ratio 80.16
#
# So BOUND is 2.00: eleven standard deviations above the darwin mean
# and 0.74 above the worst reading ever recorded there, which is what
# keeps it green on a slow runner; and forty times below the defect,
# which is what keeps it a gate. It still refuses any DOUBLING of what
# a private name costs, so the regression it was written for cannot
# creep past it - the old bound bought no sensitivity the new one
# lacks, it bought false reds.
#
# The bound was NOT raised until the arm had a negative. Raising a
# bound on an arm nothing ablates is how a check becomes one that
# cannot fail, and this arm had no ablation at all - see below.
#
# The reading the old header recorded (un-indexed private 1.26s public
# 0.60s ratio 2.10 at N=4000, from the day the arm was written) is kept
# because it explains the shape: the indexed ratio was BELOW one then,
# a private declaration taking one `mangleHasIn` scan where a public
# one took two. With that scan gone the two sides read within 5% of
# each other (1.04 at N=8000, 1.03 at N=16000). That 2.10 was measured
# against HEAD~ - a compiler predating both indexes - so it understates
# this arm's own defect by 38x, and it is not what the bound is set
# from.
#
# INTERLEAVING WAS CONSIDERED AND NOT DONE. `measure_pair` takes every
# private rep and then every public rep, so the header's argument that
# a ratio "charges the machine to both sides, where it cancels" holds
# only if both blocks see the same load - and `web/bench/run-bench.sh`
# interleaves for exactly that reason. With the bound in the gap
# instead of in the noise the correction buys nothing measurable: the
# worst interference ever observed moved the ratio by 0.14 and the
# bound now clears the worst reading by 0.74. It is left alone rather
# than changed alongside the bound, because two changes at once would
# leave neither one's effect readable.
#
# THE NEGATIVE IS IN THE SCRIPT, which is this repository's rule for a
# new test, and it ablates the CAUSE: a scratch copy of self_host/ has
# `mangleIdxHas` put back to the scan, the same parent builds a compiler
# from it, and the doubling arm must FAIL on that compiler - and fail on
# the RATIO, not on the floor, because an arm that fails for a reason
# other than the one it asserts has proved nothing.
#
# THERE ARE TWO NEGATIVES, AND FOR EIGHT DAYS THERE WAS ONE. The
# paragraph above is arm 2's. Arm 1 - the arm this gate is NAMED for,
# and the only one that has ever gone red - had none, and the gap was
# invisible because a script that carries an ablation reads as a script
# whose arms are ablated. `mangleIdxHas` is arm 2's cause, not arm 1's:
# measured on the ablated compiler this script already built, arm 1
# reads 0.70 and PASSES. So the one number arm 1 rested on was
# unverified by the gate's own rule, and the gate could not have failed
# on the defect it names.
#
# Arm 1's cause is the VISIBILITY index. `fnEntVisibleExact`
# (self_host/typecheck.ax) branches on `memGetWord tc 20`: zero means
# no index and the lookup falls to `findFnEntVisibleExact`, a scan of
# every entry filtered by `privBlocks`. Forcing that branch is the
# whole ablation - one function, no type changes, nothing else moved -
# and it is deliberately NOT the `mangleIdxHas` tree, because an
# ablation carrying two defects proves neither arm.
#
# The suffix index (`memGetWord tc 26`) is left alone by this ablation
# for the same reason. A sampling profile put `findFnEntVisibleExactFrom`
# at 54% of `check self_host/main.ax` on its own, so the exact pass is
# where the arm's subject lives and one seam is enough to prove it. It is taken at
# NEG_N=4000: the un-indexed compiler costs 3.3s a run at N=8000 and
# 11.8s at 16000, which would triple this gate to prove a shape a small
# size already shows - 3.41x (public) and 3.24x (private) at 2000, and
# the table above shows it at every size.
#
# NEG_N WAS 2000, AND THE FLOOR IS WHY IT IS NOT. `doubling_verdict`
# refuses to answer when either small-side time is under FLOOR, which
# is the same rule the live arm's N obeys, and the ablation's small
# side is the fastest number this gate takes: the ABLATED compiler,
# but at a quarter of the live arm's size. On the machine this was
# written on that is 0.47s, nowhere near the floor. On GitHub's x86_64
# runner, measured 2026-09-05, it is 0.10s - AT the floor - so the
# gate refused its own negative and the leg went red with the compiler
# entirely correct: the live arm passed in the same run at ratio 1.05,
# doubling 2.06x and 2.12x. The verdict it refused was right (3.18x
# private, 4.05x public, both over DBL_BOUND); what had stopped being
# a measurement was the pair underneath it. Same lesson as the live
# arm's, one arm over - raise the size, never the floor - and it is
# the third time this repository has learned that wiring a gate into
# CI is what first runs its negative probe on hardware the author
# never had. At NEG_N=4000 that runner's small side is 0.31s, three
# times the floor, and the ablated compiler being quadratic means the
# doubling separation grows with the size rather than shrinking. Run inside a pristine df60fdb tree,
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
BOUND="${BOUND:-2.00}"
DBL_BOUND="${DBL_BOUND:-3.00}"
REPS="${REPS:-3}"
NEG_N=4000
# Arm 1's ablation is measured at ONE size rather than a doubling - the
# arm is a same-size ratio - and at 8000 rather than 16000 because the
# un-indexed compiler is quadratic on the private side: 30.9s at 16000
# against 7.7s at 8000, for a verdict that does not change. One rep,
# not REPS: a 40x separation does not need a best-of.
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
#
# RE-ANCHORED AGAIN 2026-09-02, when `Vec` took an element type. The
# scan this puts back USED to be spelled `(mangleHasIn bares name 0)`,
# and `mangleHasIn` is still there and still the same seven lines - but
# its signature says `(Vec Int)` while `bares` is a `(Vec String)`, so
# that call is now `expected Vec Int, found Vec String` and the ablated
# compiler does not build. The scan is therefore restored VERBATIM
# under a fresh name carrying the type its own body already implies -
# it reads every element with `vecGetStr` - which is the shape
# `check-contracts.sh`'s `guard-restored` ablation uses too. Restoring
# it rather than casting at the call keeps this ablation about the SCAN
# and nothing else: `(cast (Vec Int) bares)` at an argument root is a
# memory-model change (`MM-VAL-22`) on top of the speed change this arm
# measures, and an ablation that moves two things at once proves
# neither. The restored scan is a precondition interface, because
# `vecGetStr` is one (R-B6): an untagged caller is AX3073, and a
# trusted one would leave `mangleIdxHas`'s own `effect(unsafe)` with
# nothing to support it (AX3010).
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
# Arm 1's negative: the visibility index forced off, in a SECOND
# scratch copy, must fail arm 1.
# --------------------------------------------------------------------
# A separate tree from the `mangleIdxHas` one on purpose. Arm 1 and
# arm 2 have different causes, and one compiler carrying both defects
# would let either arm's red stand in for the other's - which is the
# thing an ablation exists to rule out.
abl1="$work/tree1"
mkdir -p "$abl1"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl1/" || {
  echo "FAIL: could not copy the tree to ablate for arm 1" >&2; exit 1; }

# Anchored on the whole function. `fnEntVisibleExact` is one of two
# lookups with this exact two-branch shape - `fnEntVisibleSuffix` reads
# slot 26 the same way - so a substitution anchored on the `if` alone
# would edit whichever came first. The `effect(unsafe)` tag goes with
# the index read: the scan alone performs no unsafe operation, and a
# claim with nothing under it is AX3010 (R-B6).
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

# One rep, at one size. The separation is 40x; a best-of-three would
# spend a minute of un-indexed private checks to sharpen a number that
# does not need sharpening.
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
# Arm 3: bindings in ONE `let`. Doubling them must not multiply the
# time to reach LLVM IR by LET_BOUND or more (AN-54).
# --------------------------------------------------------------------
# The emitter decides, for each binding, whether it escapes, by walking
# the rest of the `let`, and asked every call it met whether the call's
# head was a local: a walk of the whole root (`boundWithin`) and a
# linear scan of the symbols (`lookupSym`), per call, per binding. That
# is cubic: `(cN (Cell "none"))` 1,000 times took 13.0 s and 2,000 took
# 109 s. The walk now reads a summary of the root's binders, built once
# per binding, and memoises each head's answer (`binderSummary`,
# `headIsLocal` in self_host/codegen.ax), which leaves the walk itself:
# quadratic, a doubling ratio tending to 4, where a cubic one tends to
# 8. Each binding here makes two calls, `(Cell (strDup "none"))`, which
# doubles the cubic term and leaves the memoised walk as it was: from
# 500 to 1,000 bindings the live compiler went 0.40 s to 1.35 s (x3.4)
# and the ablated one 1.80 s to 12.8 s (x7.1).
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

# The negative, in a third scratch copy: the defect put back as it was,
# a scan of the `let`'s binders and of the symbols for every call. The
# memo alone taken out is not enough to fail, because the symbol scan
# it saves is cheap beside the walk; the binders' scan is what the
# per-call walk of the whole `let` cost.
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
