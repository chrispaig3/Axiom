#!/usr/bin/env bash
# The effect fixpoint's worklist, and the declaration order it exists
# to survive.
#
# `inferEffects` is a monotone fixpoint over the call graph. Each round
# makes two passes in opposite directions, so a linear chain in either
# declaration order settles in one round. An order that defeats both
# passes, `f2 f1 f4 f3 f6 f5 ...`, takes one round per pair. A generator
# that emits a helper beside each caller produces exactly that. The
# worklist re-walks only the frontier, so that order costs what the
# plain one does.
#
# Three assertions:
#
#   1. A ratio: `swap / fwd <= 3`. A ratio holds under unknown load; an
#      absolute time only shows the machine was idle.
#   2. The same answer. `symbols --calls` over `self_host/main.ax` must
#      match byte for byte between the tree's compiler and one with the
#      frontier ablated. A wrong frontier shows up as a missing effect
#      on one row, with no crash.
#   3. The negative probe. The ablated compiler must read `swap / fwd >
#      10`. A compiler with no worklist passes 2 trivially, and 1 on a
#      fast machine, so without this the gate would still pass with the
#      worklist removed. The ablation makes `nextFrontier` return every
#      declaration.
#
# The chains are generated here: they are large, carry nothing a reader
# wants, and N can rise if machines get fast enough for the ratio to stop
# discriminating.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# N is big enough that the quadratic dominates process startup, and
# small enough that the ablated arm below stays well under a minute.
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

# Seconds, to two places, of one `check`. Timed in python3 because the
# `time` keyword and `/usr/bin/time` print different formats.
secs() {
  python3 - "$@" <<'PY'
import subprocess, sys, time
t = time.time()
subprocess.run(sys.argv[1:], capture_output=True)
print(f"{time.time() - t:.2f}")
PY
}

ratio() { python3 -c "import sys; a=float(sys.argv[1]); b=max(float(sys.argv[2]),0.01); print(f'{a/b:.1f}')" "$1" "$2"; }

# Warm each file before timing it. The first `check` of a run pays for
# the file cache and the dynamic loader, which can skew one term of the
# ratio by 10x and turn a failure into a pass.
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

# Both files must check clean. A compiler that refused both would have
# a fine ratio and no meaning.
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
# Ablate the frontier to "everything is dirty". The seam is
# `nextFrontier`'s own body, so a rename fails here instead of
# silently ablating nothing.
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/"
# The formatter puts the body on its own line, so the seam is the whole
# two-line definition, counted exactly.
seam_old='(pub fn (nextFrontier next decls)
  next)'
seam_new='(pub fn (nextFrontier next decls)
  (allIndexes (vecLen decls)))'
n_seam="$(python3 -c 'import sys; print(open(sys.argv[1], encoding="utf-8").read().count(sys.argv[2]))' "$abl/self_host/typecheck.ax" "$seam_old" || true)"
if [[ "$n_seam" != 1 ]]; then
  bad "self_host/typecheck.ax holds $n_seam copies of the ablation seam; this gate expects exactly 1"
else
  python3 - "$abl/self_host/typecheck.ax" "$seam_old" "$seam_new" <<'PY'
import sys
p, old, new = sys.argv[1], sys.argv[2], sys.argv[3]
s = open(p, encoding="utf-8").read()
assert s.count(old) == 1
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  if ! gate_build_tree "$axiom" "$abl" "$AXIOM_STDLIB" "$work/axc-abl" \
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
