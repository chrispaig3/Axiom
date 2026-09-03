#!/usr/bin/env bash
# WHAT LLVM'S VECTORIZER DOES WITH AN AXIOM LOOP, COUNTED IN THE IR.
#
# Axiom emits LLVM IR and the driver hands it to `opt`, so "automatic
# SIMD" is a question about the SHAPE of the emitted loops: the loop
# and SLP vectorizers run inside `opt -O2` and `-O3` already, and what
# decides whether a loop becomes `<2 x i64>` arithmetic is whether the
# emitter gave them something they can prove things about. Measured
# 2026-09-03 with `opt --pass-remarks-output` over four fixtures, and
# recorded in docs/reference.md's Optimisation section:
#
#   a `for` over a `(Vec Int)` summing     VECTORIZED at --opt 2
#                                          (width 2, interleave 4; 3.1x)
#   a byte scan over a String              VECTORIZED (width 16; 1.9x)
#   an in-place map through `vecSet`       refused: the range check's
#                                          trap was an EXIT inside the
#                                          loop, and the ownership
#                                          branch keeps a call there
#   `web/bench/collatz.ax`'s `while`       refused, correctly: the trip
#                                          count is data-dependent
#
# `--opt 1`, the driver's default, runs NO vectorizer - LLVM enables
# both at speedup level 2 - so every number above is about `--opt 2`.
#
# THE ONE EMITTER CHANGE THIS GATE HOLDS is the trap runtime being
# `noreturn cold` (`trapFnAttrs`, self_host/codegen.ax). Before it,
# `Vec$vecGet` and every accessor like it was inlined everywhere and
# carried the trap's body - two syscalls and a `@__axiom_backtrace`
# call - into 1,518 hot functions of the compiler's own IR at --opt 2
# and 1,685 at --opt 1; after, 2, the definition and one call that
# `opt` keeps. The compiler binary is 6.9% smaller for it (2,153,352 ->
# 2,004,600 bytes, `__TEXT` 8.7% smaller), and three more of its loops
# vectorize (98 -> 101). A cold callee is one the inliner leaves as a
# call, and a noreturn callee is one whose call is followed by
# `unreachable` rather than an edge back into the loop.
#
# WHY COUNTS AND NOT TIMINGS. `bench-compile.sh` is explicit that a
# wall-clock bound on a shared runner is a flaky test. Whether a loop
# was vectorized is a property of the emitted module, exact, and it is
# the thing this is about; the speedups above are DECLARED, measured on
# an idle machine, and not asserted here.
#
# WHAT IT ASSERTS.
#
#   1. BEHAVIOUR IS FIXED. The reduction answers the same number at
#      --opt 0, 1 and 2, and the byte scan does too. A faster wrong
#      answer is not the goal, and it is first for that reason.
#
#   2. THE TWO LOOPS THAT VECTORIZE STILL DO, at the level the driver
#      uses for `--opt 2`: `opt` reports `Vectorized` for `sumVec` and
#      for `countA`, and their bodies carry `<N x i64>` and `<N x i8>`
#      operations. The width is not pinned: the baseline CPU of each
#      release target decides it (NEON and SSE2 are both 128 bits), and
#      a gate that pinned 2 would fail on a runner with wider vectors
#      while the compiler was correct.
#
#   3. A LOOP THAT MUST NOT VECTORIZE IS NOT. The Collatz `while` has a
#      data-dependent trip count, so `steps` has no `vector.body`. This
#      is what proves the reader can answer zero; without it, 2 could
#      be satisfied by a grep that matched everything.
#
#   4. THE TRAP STAYS OUT OF LINE. The emitted module defines the index
#      trap `noreturn cold`, and after `opt -O2` the in-place map's
#      body holds NO copy of the trap's message address and the module
#      still CALLS the trap. Then the ablation: `trapFnAttrs` blanked to
#      `#0` in a copy of the tree, the compiler rebuilt from it, and
#      the copies must come back into the same function. A count no
#      ablation can move is not evidence.
#
#   5. THE COMPILER'S OWN IR, as a census rather than a floor that
#      pretends to be exact: its trap copies at --opt 2 are at most 2,
#      and at least 50 of its loops vectorize (101 on 2026-09-03). The
#      numbers are printed so a reader can see them move.
#
# THE FIXTURES LIVE HERE, in heredocs, rather than under `tests/`,
# for the reason `check-unboxed-sums.sh` gives: every `.ax` added to a
# test directory moves population counts in gates that have nothing to
# say about vectorization.
#
# Usage:
#   scripts/check-simd.sh
#   AXIOM_AXC=path/to/stamped/axc scripts/check-simd.sh

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

gate_build_axc axc

failed=0
checks=0
ok()  { checks=$((checks + 1)); echo "ok   $*"; }
bad() { checks=$((checks + 1)); failed=$((failed + 1)); echo "FAIL $*"; }

command -v opt >/dev/null || { echo "FAIL: opt is not on PATH; this gate reads its remarks"; exit 1; }

SUM_GOLDEN=24999975000000
BYTES_GOLDEN=10485760
# The compiler's own IR: copies of the index trap left inlined at
# --opt 2 (2 = the definition and the one call `opt` keeps), and a
# floor on the loops the vectorizer accepts (101 on 2026-09-03).
SELF_COPIES_MAX=2
SELF_VECTORIZED_MIN=50

mkdir -p "$work/simd"

# The reduction: a `for` over a `(Vec Int)`, no store in the loop.
cat > "$work/simd/sum.ax" <<'EOF'
(import IO)

(import Vec)

(:: fill (-> Int (Vec Int)))

(fn (fill n)
  (let ((v vecNew))
    {
      (for i 0 n (vecPush v i))
      v
    }
  )
)

(:: sumVec (-> (Vec Int) Int))

(fn (sumVec xs)
  (let ((mut acc 0))
    {
      (for x xs (set acc (+ acc x)))
      acc
    }
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let ((v (fill 1000000)))
    (let ((mut total 0))
      {
        (for r 0 50 (set total (+ total (sumVec v))))
        (println total)
        0
      }
    )
  )
)
EOF

# The byte scan: "abcabcaa" doubled 17 times is 1,048,576 bytes with
# 524,288 of them `a`; twenty passes.
cat > "$work/simd/bytes.ax" <<'EOF'
(import IO)

(import Str)

(:: countA (-> String Int))

(fn (countA s)
  (let ((n (strLen s)))
    (let ((mut c 0))
      {
        (for i 0 n (if (== (strByte s i) 97) (set c (+ c 1)) 0))
        c
      }
    )
  )
)

(:: bigStr (-> Int String))

(fn (bigStr k)
  (let ((mut s "abcabcaa"))
    {
      (for i 0 k (set s (strConcat s s)))
      s
    }
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let ((s (bigStr 17)))
    (let ((mut total 0))
      {
        (for r 0 20 (set total (+ total (countA s))))
        (println total)
        0
      }
    )
  )
)
EOF

# The control: a data-dependent trip count. Nothing may vectorize it.
cat > "$work/simd/steps.ax" <<'EOF'
(import IO)

(:: steps (-> Int Int))

(fn (steps n0)
  (let ((mut n n0))
    (let ((mut c 0))
      {
        (while (> n 1)
          (set n (if (== (% n 2) 0) (/ n 2) (+ (* n 3) 1)))
          (set c (+ c 1)))
        c
      }
    )
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println (steps 27))
    0
  }
)
EOF

# The in-place map through the real accessors: every element read and
# written is bounds-checked, so this is where the trap's body used to
# be inlined into the loop.
cat > "$work/simd/bump.ax" <<'EOF'
(import IO)

(import Vec)

(:: fill (-> Int (Vec Int)))

(fn (fill n)
  (let ((v vecNew))
    {
      (for i 0 n (vecPush v i))
      v
    }
  )
)

(:: bump (-> (Vec Int) Int))

(fn (bump v)
  (let ((n (vecLen v)))
    {
      (for i 0 n (vecSet v i (+ (vecGet v i) 1)))
      0
    }
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let ((a (fill 1000)))
    {
      (bump a)
      (println (vecGet a 999))
      0
    }
  )
)
EOF

# One function's body out of a module, for a grep to read. The name is
# matched with `index`, not a regex: passed through `awk -v`, the `\(`
# that would anchor the parameter list loses its backslash and opens a
# group instead, the regex never matches, and every check over the
# body reads an EMPTY body. The first run of this gate did exactly
# that - two "no vector operation" failures on loops `opt` had just
# reported vectorized, and an ablation that could not put the trap
# back into a body it was not reading. The ablation is what said so.
fn_body() {  # <ll> <name>
  awk -v fn="$2" '/^define / && index($0, "@" fn "(") {p=1} p {print} p && /^}/ {exit}' "$1"
}

# Did `opt` report a vectorized loop in this function? Read from the
# YAML remarks rather than the IR, because the remark is LLVM's own
# statement and the IR grep below is the corroboration.
vectorized_in() {  # <yaml> <name> -> count
  awk -v fn="$2" '/^Name: *Vectorized/ {v=1; next} /^Function:/ { if (v && $2 == fn) n++; v=0 } END {print n+0}' "$1"
}

emit_and_opt() {  # <stem> -> $work/simd/<stem>.ll and <stem>.O2.ll, <stem>.yaml
  local stem="$1"
  "$axc" emit-llvm "$work/simd/$stem.ax" -o "$work/simd/$stem.ll" >"$work/simd/$stem.emit.log" 2>&1 || {
    echo "FAIL: could not emit $stem.ax"; sed 's/^/     /' "$work/simd/$stem.emit.log" | head -10; exit 1; }
  opt -O2 -S "$work/simd/$stem.ll" -o "$work/simd/$stem.O2.ll" \
      --pass-remarks-output="$work/simd/$stem.yaml" --pass-remarks-filter=loop-vectorize \
      >"$work/simd/$stem.opt.log" 2>&1 || {
    echo "FAIL: opt -O2 refused $stem.ll"; sed 's/^/     /' "$work/simd/$stem.opt.log" | head -10; exit 1; }
}

# ---------------------------------------------------------------
echo "== 1. behaviour is fixed across --opt 0, 1 and 2 =="
# ---------------------------------------------------------------
for stem in sum bytes; do
  want="$SUM_GOLDEN"; [[ "$stem" == bytes ]] && want="$BYTES_GOLDEN"
  for o in 0 1 2; do
    if ! "$axc" build --opt "$o" --input "$work/simd/$stem.ax" --output "$work/simd/$stem$o" \
         >"$work/simd/$stem.build$o.log" 2>&1; then
      bad "$stem did not build at --opt $o"
      sed 's/^/     /' "$work/simd/$stem.build$o.log" | head -10
      continue
    fi
    got="$("$work/simd/$stem$o" 2>/dev/null || true)"
    if [[ "$got" == "$want" ]]; then
      ok "$stem at --opt $o answers $want"
    else
      bad "$stem at --opt $o answered '$got', wanted $want"
    fi
  done
done

# ---------------------------------------------------------------
echo
echo "== 2. the reduction and the byte scan vectorize at --opt 2 =="
# ---------------------------------------------------------------
emit_and_opt sum
emit_and_opt bytes
n="$(vectorized_in "$work/simd/sum.yaml" sumVec)"
if (( n >= 1 )); then
  ok "opt reports a vectorized loop in sumVec"
else
  bad "opt reports no vectorized loop in sumVec"
  grep -A3 '^Name:' "$work/simd/sum.yaml" | grep -B1 -A2 'Function: *sumVec' | head -12 | sed 's/^/     /'
fi
if fn_body "$work/simd/sum.O2.ll" sumVec | grep -qE '<[0-9]+ x i64>'; then
  ok "sumVec's body carries <N x i64> operations"
else
  bad "sumVec's body has no <N x i64> operation"
fi
n="$(vectorized_in "$work/simd/bytes.yaml" countA)"
if (( n >= 1 )); then
  ok "opt reports a vectorized loop in countA"
else
  bad "opt reports no vectorized loop in countA"
fi
if fn_body "$work/simd/bytes.O2.ll" countA | grep -qE '<[0-9]+ x i8>'; then
  ok "countA's body carries <N x i8> operations"
else
  bad "countA's body has no <N x i8> operation"
fi

# ---------------------------------------------------------------
echo
echo "== 3. the data-dependent loop is refused =="
# ---------------------------------------------------------------
emit_and_opt steps
n="$(vectorized_in "$work/simd/steps.yaml" steps)"
if (( n == 0 )) && ! fn_body "$work/simd/steps.O2.ll" steps | grep -q 'vector.body'; then
  ok "steps has no vectorized loop and no vector.body - the reader can answer zero"
else
  bad "steps was reported vectorized ($n) or its body has a vector.body; a Collatz loop cannot be"
fi

# ---------------------------------------------------------------
echo
echo "== 4. the trap stays out of line =="
# ---------------------------------------------------------------
emit_and_opt bump
if grep -q '^define internal i64 @__axiom_index_out_of_range() noreturn cold #0 {' "$work/simd/bump.ll"; then
  ok "the emitted module defines the index trap noreturn cold"
else
  bad "the index trap is not defined noreturn cold in the emitted module"
  grep -n '@__axiom_index_out_of_range()' "$work/simd/bump.ll" | head -3 | sed 's/^/     /'
fi
copies="$(fn_body "$work/simd/bump.O2.ll" bump | grep -c '@__axiom_index_msg to i64' || true)"
calls="$(grep -c 'call i64 @__axiom_index_out_of_range()' "$work/simd/bump.O2.ll" || true)"
if (( copies == 0 )); then
  ok "bump's body holds no inlined copy of the trap at --opt 2"
else
  bad "bump's body holds $copies inlined copies of the trap at --opt 2"
fi
if (( calls >= 1 )); then
  ok "the module still calls the trap ($calls call sites), so it was not deleted"
else
  bad "no call to the index trap survives in the module; the count above is vacuous"
fi

echo "-- ablation: trapFnAttrs blanked to #0 puts the copies back --"
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/" || {
  echo "FAIL: could not copy the tree to ablate" >&2; exit 1; }
python3 - "$abl/self_host/codegen.ax" <<'PY'
import sys
p = sys.argv[1]
s = open(p, encoding="utf-8").read()
old = '(pub fn (trapFnAttrs) "noreturn cold #0")'
new = '(pub fn (trapFnAttrs) "#0")'
if s.count(old) != 1:
    sys.exit("the ablation matched %d times, wanted 1" % s.count(old))
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
if [[ $? -ne 0 ]]; then
  bad "could not apply the ablation - trapFnAttrs has moved, and check 4 is asserting nothing"
elif ! AXIOM_STDLIB="$abl/stdlib" "$axc" build "$abl/self_host/main.ax" \
       -o "$work/axc-ablated" >"$work/ablated.build.log" 2>&1; then
  bad "the ablated compiler did not build"
  sed 's/^/     /' "$work/ablated.build.log" | head -20
elif ! "$work/axc-ablated" emit-llvm "$work/simd/bump.ax" -o "$work/simd/bump.abl.ll" \
       >"$work/simd/bump.abl.emit.log" 2>&1; then
  bad "the ablated compiler did not emit the fixture"
  sed 's/^/     /' "$work/simd/bump.abl.emit.log" | head -10
else
  opt -O2 -S "$work/simd/bump.abl.ll" -o "$work/simd/bump.abl.O2.ll" >/dev/null 2>&1 || true
  acopies="$(fn_body "$work/simd/bump.abl.O2.ll" bump | grep -c '@__axiom_index_msg to i64' || true)"
  if (( acopies >= 1 )); then
    ok "ablated: $acopies inlined copies of the trap in bump's body - the attributes are what keep it out"
  else
    bad "ablated: still no inlined copy in bump's body, so check 4 is not measuring the attributes"
  fi
fi

# ---------------------------------------------------------------
echo
echo "== 5. the compiler's own IR: a census, and two bounds =="
# ---------------------------------------------------------------
if ! "$axc" emit-llvm "$repo_root/self_host/main.ax" -o "$work/self.ll" >"$work/self.emit.log" 2>&1; then
  bad "could not emit self_host/main.ax"
  sed 's/^/     /' "$work/self.emit.log" | head -10
else
  opt -O2 -S "$work/self.ll" -o "$work/self.O2.ll" \
      --pass-remarks-output="$work/self.yaml" --pass-remarks-filter=loop-vectorize >/dev/null 2>&1 || true
  scopies="$(grep -c '@__axiom_index_msg to i64' "$work/self.O2.ll" || true)"
  svec="$(grep -c '^Name: *Vectorized' "$work/self.yaml" || true)"
  echo "     self_host/main.ax at --opt 2: $scopies trap copies, $svec vectorized loops ($(wc -l < "$work/self.ll" | tr -d ' ') lines emitted)"
  if (( scopies <= SELF_COPIES_MAX )); then
    ok "at most $SELF_COPIES_MAX inlined trap copies in the compiler's own IR"
  else
    bad "$scopies inlined trap copies in the compiler's own IR (bound $SELF_COPIES_MAX; it was 1,518 before the attributes)"
  fi
  if (( svec >= SELF_VECTORIZED_MIN )); then
    ok "at least $SELF_VECTORIZED_MIN of the compiler's loops vectorize"
  else
    bad "only $svec of the compiler's loops vectorize (floor $SELF_VECTORIZED_MIN, 101 on 2026-09-03)"
  fi
fi

echo
if (( failed == 0 )); then
  echo "check-simd: all $checks checks passed"
else
  echo "check-simd: $failed of $checks checks FAILED"
  exit 1
fi
