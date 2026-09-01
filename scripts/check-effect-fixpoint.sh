#!/usr/bin/env bash
# The effect fixpoint's worklist, and the shape it exists to survive.
#
# WHAT THIS IS ABOUT. `inferEffects` is a monotone fixpoint over the
# call graph, and until 2026-08-30 every round re-walked EVERY body.
# One round of two passes in opposite directions (2026-08-25) collapses
# a linear chain in either declaration order to a single round, which
# is why the two orders a human writes are both fast. What it does not
# collapse is an order that defeats both passes at once - `f2 f1 f4 f3
# f6 f5 ...`, a helper emitted beside each of its callers, which is
# what a GENERATOR produces. There each round advances the frontier by
# one pair and pays for a full walk to do it.
#
# Measured on this tree the day the worklist landed, one chain of N
# functions with the effect at the bottom, only the declaration order
# varying:
#
#   n      callers first   pairs swapped   pairs swapped
#                                          (with worklist)
#   1000       0.02 s          1.34 s          0.02 s
#   2000       0.03 s          3.88 s          0.03 s
#   4000       0.05 s         14.33 s          0.06 s
#   8000       0.09 s         56.05 s          0.10 s
#
# 560x at n=8000, and the pathological order now costs what the plain
# one does.
#
# WHAT IS ASSERTED, AND WHY IN THIS ORDER.
#
#   1. A RATIO, not a time. `swap / fwd <= 3` on one machine under
#      unknown load says the two orders cost the same; "swap under
#      0.2s" says the machine was idle. `check-type-namespace.sh`
#      learned this the hard way and its note is the reason this gate
#      is written as a comparison from its first line.
#
#   2. THE SAME ANSWER. `symbols --calls` over `self_host/main.ax`,
#      byte for byte, from the tree's compiler and from one with the
#      frontier ablated. The worklist may change what the fixpoint
#      COSTS and must not change what it ANSWERS, and a fixpoint is
#      exactly the kind of thing where a wrong frontier shows up as a
#      missing effect on one row out of 3,495 rather than as a crash.
#
#   3. THE NEGATIVE PROBE. The ablated compiler must read `swap / fwd
#      > 10`. Assertions 1 and 2 are both satisfied by a compiler that
#      never had a worklist - 2 trivially, and 1 on a fast enough
#      machine with a small enough N - so without this the gate would
#      be green on the code it exists to hold. `nextFrontier` is one
#      line and the ablation replaces its body with "every declaration
#      is dirty", which is precisely the behaviour the worklist
#      replaced.
#
# The chains are GENERATED here rather than checked in: they are 24,000
# lines at the size this needs, they carry no information a reader
# wants, and a generator is the only way the size can be raised when a
# machine gets fast enough for the ratio to stop discriminating.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# N is a compromise: big enough that the quadratic dominates process
# startup (at n=500 the unfixed compiler takes 0.55s, which is only 25x
# a `check` that does nothing), small enough that the ablated arm below
# does not take a minute. 2000 is 3.88s unfixed against 0.03s fixed.
N=2000

# f1 -> f2 -> ... -> fN, the effect at the bottom. Two files, the same
# call graph, different declaration order:
#
#   fwd    f1 f2 f3 f4 ...   callers first, one round
#   swap   f2 f1 f4 f3 ...   pairs swapped, N/2 rounds unfixed
gen_chain() {
  local order="$1" n="$2" out="$3"
  python3 - "$order" "$n" "$out" <<'PY'
import sys
order, n, out = sys.argv[1], int(sys.argv[2]), sys.argv[3]
d = []
for i in range(1, n + 1):
    body = '{ (println "end") x }' if i == n else f"(f{i+1} x)"
    d.append(f"(:: f{i} (-> Int Int))\n\n;@axiom:effect(io)\n(fn (f{i} x) {body})\n")
if order == "swap":
    seq = []
    for i in range(0, len(d), 2):
        seq += list(reversed(d[i:i + 2]))
else:
    seq = d
with open(out, "w") as fh:
    fh.write("(import IO)\n\n")
    fh.write("\n".join(seq))
    fh.write("\n(:: main Int)\n\n;@axiom:effect(io)\n(fn (main) (f1 1))\n")
PY
}

# Seconds, to two places, of one `check`. `python3` rather than `time`
# because the two `time` spellings disagree about their output format
# and this gate needs a number it can divide.
secs() {
  python3 - "$@" <<'PY'
import subprocess, sys, time
t = time.time()
subprocess.run(sys.argv[1:], capture_output=True)
print(f"{time.time() - t:.2f}")
PY
}

ratio() { python3 -c "import sys; a=float(sys.argv[1]); b=max(float(sys.argv[2]),0.01); print(f'{a/b:.1f}')" "$1" "$2"; }

# BOTH SIDES WARM, and this is not a nicety. The first `check` of a run
# pays for the file cache and the dynamic loader, and on the first
# writing of this gate that landed on the FAST side: `fwd 0.33s, swap
# 0.03s, ratio 0.1x` - a pass, arrived at by mismeasuring the
# denominator by 10x. A ratio is only load-insensitive when both of its
# terms were taken under the same conditions, so each file is checked
# once and thrown away before it is timed.
warm() { "$1" check "$2" >/dev/null 2>&1 || true; }

gen_chain fwd  "$N" "$work/fwd.ax"
gen_chain swap "$N" "$work/swap.ax"
echo "== two declaration orders of one $N-function chain =="
echo "   $(wc -l <"$work/fwd.ax" | tr -d ' ') lines each"

# --------------------------------------------------------------------
echo
echo "== 1. the pathological order costs what the plain one does =="
# --------------------------------------------------------------------
warm "$axc" "$work/fwd.ax"
warm "$axc" "$work/swap.ax"
fwd_t="$(secs "$axc" check "$work/fwd.ax")"
swap_t="$(secs "$axc" check "$work/swap.ax")"
r="$(ratio "$swap_t" "$fwd_t")"
echo "   fwd ${fwd_t}s, swap ${swap_t}s, ratio ${r}x"
if python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) <= 3.0 else 1)" "$r"; then
  ok "swap/fwd is ${r}x, at or under the 3x ceiling"
else
  bad "swap/fwd is ${r}x, over the 3x ceiling - the worklist is not doing its work"
fi

# Both must actually have CHECKED. A compiler that refused both files
# would have a fine ratio and no meaning.
for f in fwd swap; do
  if ! "$axc" check "$work/$f.ax" >/dev/null 2>&1; then
    bad "$f.ax does not check - the timings above are of a failure"
  fi
done
ok "both orders check clean, so the times are of a completed inference"

# --------------------------------------------------------------------
echo
echo "== 2. and answers the same thing =="
# --------------------------------------------------------------------
# The frontier ablated to "everything is dirty", which is the behaviour
# the worklist replaced. Anchored on `nextFrontier`'s own body, so a
# rename upstream is a loud failure here rather than a silent no-op.
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/"
seam='(pub fn (nextFrontier next decls) next)'
n_seam="$(grep -c -F -x "$seam" "$abl/self_host/typecheck.ax" || true)"
if [[ "$n_seam" != 1 ]]; then
  bad "self_host/typecheck.ax holds $n_seam copies of the ablation seam; this gate expects exactly 1"
else
  python3 - "$abl/self_host/typecheck.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = "(pub fn (nextFrontier next decls) next)"
new = "(pub fn (nextFrontier next decls) (allIndexes (vecLen decls)))"
assert s.count(old) == 1
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  if ! (cd "$abl" && "$axiom" build --input self_host/main.ax --output "$work/axc-abl") \
       > "$work/abl.build.log" 2>&1; then
    bad "the ablated compiler would not build"
    sed 's/^/     /' "$work/abl.build.log" | head -10
  else
    "$axc"            --diagnostic-format=ai symbols --calls "$repo_root/self_host/main.ax" > "$work/sym.tree" 2>&1
    "$work/axc-abl"   --diagnostic-format=ai symbols --calls "$repo_root/self_host/main.ax" > "$work/sym.abl"  2>&1
    rows="$(wc -l <"$work/sym.tree" | tr -d ' ')"
    if [[ "$rows" -lt 3000 ]]; then
      bad "only $rows AXSYM rows for self_host/main.ax; the floor is 3000 (3495 today) - the comparison below would be of nothing"
    elif cmp -s "$work/sym.tree" "$work/sym.abl"; then
      ok "the worklist changes no row of $rows: --calls is byte-identical to the ablated compiler's"
    else
      bad "the worklist changed the answer, not only the cost"
      { diff "$work/sym.tree" "$work/sym.abl" || true; } | head -10 | sed 's/^/     /'
    fi

    # ----------------------------------------------------------------
    echo
    echo "== 3. and the ratio moves when the frontier is taken away =="
    # ----------------------------------------------------------------
    warm "$work/axc-abl" "$work/fwd.ax"
    afwd="$(secs "$work/axc-abl" check "$work/fwd.ax")"
    aswap="$(secs "$work/axc-abl" check "$work/swap.ax")"
    ar="$(ratio "$aswap" "$afwd")"
    echo "   ablated: fwd ${afwd}s, swap ${aswap}s, ratio ${ar}x"
    if python3 -c "import sys; sys.exit(0 if float(sys.argv[1]) > 10.0 else 1)" "$ar"; then
      ok "ablated swap/fwd is ${ar}x, over the 10x floor - assertion 1 is measuring the frontier"
    else
      bad "ablated swap/fwd is only ${ar}x: assertion 1 would pass without the worklist, so it tests nothing"
    fi
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-effect-fixpoint: $failed of $((checks + failed)) checks failed"
  exit 1
fi
echo "check-effect-fixpoint: $checks checks, the worklist held by a ratio and by the answer it must not change"
