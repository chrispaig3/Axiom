#!/usr/bin/env bash
# S4 slice 3, args path (docs/memory-model-v2-design.md §4): inside a
# `(region r BODY)` a join - an `if`, `cond` or `match` - whose every
# arm the witness proved fresh needs no `axiom_release` for the
# single value it answers - the reset reclaims whichever arm flowed
# in one pointer move - and this is what holds that the elision
# fires, fires only there, and changes nothing but binary size.
#
# WHAT SLICE 3 IS, IN ONE ARGUMENT. Slices 1 and 2 owned releases
# whose operand IS the value's birth: a construction answered
# syntactically where it is built, a call result read off the
# MM-RGN-5 witness on the callee. A join is neither - it answers
# whichever arm it took, so freshness needs per-arm reasoning: the
# region pass stamps the join itself (`nodeResWord` 2, post-fixpoint
# only, converged facts only, an upgrade 0 to 2) iff every arm value
# node already carries the stamp, a proven-fresh call result or such
# a join. Anything else for an arm - a reader, an unknown call, a
# construction (slice 1's syntactic domain, never stamped), a name -
# abstains, and so does the join; a missing `else` is not a stamped
# arm either. `releaseOwnedArgs` spends the stamp exactly where
# slices 1 and 2 spend theirs while `argOwnedRelease` still says 1,
# so `mustTailOK` stays conservative and `check-tail-calls.sh` does
# not move. TC word 40 (`rgnStamping`) is what keeps a still-moving
# row from ever becoming a stamp: the same `rgnPass` with report 0
# runs inside `rgnRounds` on every round, so the report value cannot
# distinguish them.
#
# Five checks, each with the reason a lesser gate would be vacuous:
#
#   1. THE ANSWERS. `tests/stdlib/482-region-phi-call.ax` prints
#      eleven terms under the compiler under test, byte-identical to
#      its `.out` - an `if` join elided (term 1), a reader arm kept
#      (term 2), a construction arm kept (term 3), the un-regioned
#      and closure-called shapes kept (terms 4 and 6), a `let`-bound
#      join elided by the scope-end walker in both arms here (term
#      5), a nested join elided (term 7), a `match` join elided
#      (term 8), a `cond` join elided (term 9), the waterline back
#      (term 10), fifty thousand regions summed (term 11). A gate
#      that stamped too eagerly fails here first, against a golden
#      no re-bless of the IR counts below can move.
#   2. THE COUNT, AS A DELTA. The fixture's IR under this compiler
#      against the same IR under a compiler built from a tree whose
#      ARGS-path join spend never fires: seven fewer `axiom_release`
#      calls, and the `diff` between the two IRs is those seven lines
#      and nothing else. An absolute count would bless whatever the
#      println machinery contributes; a delta distinguishes the seven
#      this path owns from all of it. Seven is terms 1, 7, 8 and 9,
#      two in term 10 and the loop in term 11 - counted by hand,
#      asserted by machine. Terms 2, 3, 4 and 6 keep theirs: a
#      reader arm, a construction arm, no region, and a closure-call
#      arm the walk cannot resolve. Term 5's `let`-bound join is the
#      SCOPE path's (`scripts/check-region-phi-let.sh`): elided in
#      both arms here, so it never enters this delta. No term hands
#      a bare call result directly to a call, so every stamped
#      argument here is a join and the shared spend's ablation below
#      restores exactly this walker's traffic.
#   3. THE RSS, AS A RATIO. A loop of 300,000 regions, each calling
#      home a join of two fresh calls and dropping it, under both
#      compilers: same stdout, same exit, and this compiler's peak
#      RSS within 1.5x of the ablated one's. If an elided release had
#      been load-bearing the loop would leak ~5 MiB here and the ratio
#      would say so; the waterline term of check 1 already says it
#      exactly, and this says it dynamically. A ratio and not a bound,
#      so a loaded runner cannot fail it.
#   4. THE ABLATION IS WHAT MAKES 2 AND 3 MEAN ANYTHING. The tree is
#      copied, the args path's own spend is made to never fire - the
#      rule still exists, still runs beside the construction test,
#      and answers nothing - and a compiler is built from it. Seven
#      releases come back and only seven: any other delta fails the
#      gate, because an ablation that moved anything else broke the
#      program instead of restoring the traffic. Cost: one extra
#      compiler build, the price the sibling gates pay for the same
#      reason.
#   5. THE ADJACENT HOLE, CLOSED AND PINNED. A callee-mediated
#      store of a fresh construction into an outer cell from inside
#      a region used to check OK and read back wrong with every gate
#      green (`rgnCheckAll` reported only under `@r` signatures).
#      S3's reporting walk now runs for region-form programs too -
#      with S2's refused store spans suppressing the same-store
#      double - and refuses the probe, which is what this check pins:
#      both compilers refuse identically. The elision cannot change
#      that outcome either way, since the reset frees unconditionally;
#      and if the hole ever reopened, identical answers under both
#      compilers would still pass. Recorded in the design note's S4
#      subsection, closed there too.
#
# What this gate does NOT cover, stated rather than left to be
# found: a fresh join bound by `let` and released at scope end
# rather than passed as an argument - `releaseOwnedArgs` never sees
# it, so this walker never spends on it. Term 5 pins one, elided in
# both arms here by the scope-end walker
# (`scripts/check-region-phi-let.sh`), which is why the ablation
# above restores exactly seven. `VAR` operands that are not `let`
# bindings are neither walker's. Loads resolved in slice 4
# (`scripts/check-region-scrutinee.sh`): the spendable ones were
# match scrutinee temporaries; tail-loop slots and `set` olds are
# paired, and field reads are borrows at every site with no release
# to spend on.
# Field stores are excluded finally, not deferred: their release
# balances a retain in the same step (`emitSetF`), so eliding one
# half would leak. `musttail` paths stay conservative by
# construction (`argOwnedRelease` untouched).
#
# Usage:
#   scripts/check-region-phi.sh
#   AXIOM=path/to/compiler scripts/check-region-phi.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

gate_build_axc axc

fixture="$repo_root/tests/stdlib/482-region-phi-call.ax"
golden="$repo_root/tests/stdlib/482-region-phi-call.out"

# `measure-memory-baseline.sh`'s reader, and its rule: fail rather
# than skip when neither `time` answers.
max_rss_kb() {
  local div=1
  [[ "$(uname -s)" == Darwin ]] && div=1024
  if /usr/bin/time -l true >/dev/null 2>&1; then
    /usr/bin/time -l "$@" 2>&1 >/dev/null \
      | awk -v div="$div" '/maximum resident set size/ {print int($1/div)}'
  elif /usr/bin/time -v true >/dev/null 2>&1; then
    /usr/bin/time -v "$@" 2>&1 >/dev/null \
      | awk -F: '/Maximum resident set size/ {print int($2)}'
  else
    echo "FAIL: no usable time(1) for RSS measurement" >&2
    return 1
  fi
}

releases_in() { # <ll> -> count of release call sites (not the define)
  grep -c 'call void @axiom_release' "$1"
}

# ---------------------------------------------------------------
echo "== 1. the eleven terms answer under the compiler under test =="
# ---------------------------------------------------------------
if ! "$axc" build --input "$fixture" --output "$work/phi" >"$work/build.log" 2>&1; then
  bad "could not build the fixture"
  sed 's/^/     /' "$work/build.log" | head -20
else
  "$work/phi" >"$work/phi.out" 2>&1
  rc=$?
  if (( rc != 0 )); then
    bad "the fixture exits $rc, wanted 0"
  elif ! cmp -s "$work/phi.out" "$golden"; then
    bad "the fixture's stdout differs from $golden"
    diff "$golden" "$work/phi.out" | head -10 | sed 's/^/     /'
  else
    ok "482-region-phi-call: eleven terms byte-identical to the golden, exit 0"
  fi
fi

# ---------------------------------------------------------------
echo
echo "== 2-4. seven releases gone, nothing else moved, ablation red =="
# ---------------------------------------------------------------
# Ablated on a COPY of the tree: `gate_source_stamp` hashes
# `self_host/`, so an ablation left behind would silently become the
# tree every later gate builds from.
abl="$work/tree"
mkdir -p "$abl"
cp -R "$repo_root/self_host" "$repo_root/stdlib" "$abl/" || {
  echo "FAIL: could not copy the tree to ablate" >&2; exit 1; }

target="$abl/self_host/codegen.ax"
if ! python3 - "$target" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
# Anchored on the args path's own spend, and only it: the scope-end
# path in `emitLetAt` reads `(nodeResWord valExpr)`, the chain
# walkers read `(nodeResWord snode)` for wordness, and ablating any
# of those instead would restore traffic this walker never owned -
# or break every closure application. Replacing the stamp read with
# a value no stamp takes leaves the rule in place - the construction
# test still evaluates beside it on every argument - and answering
# nothing. 2 is the only stamped value beside 0 and 1, so 3 fires
# nowhere.
old = "(== (nodeResWord a) 2)"
if s.count(old) != 1:
    sys.stderr.write("args-path spend not found verbatim (%d)\n" % s.count(old))
    sys.exit(1)
open(p, "w").write(s.replace(old, "(== (nodeResWord a) 3)"))
PY
then
  bad "could not ablate the args-path spend"
  echo "     nothing was ablated, so the red half of this gate proves nothing"
else
  echo "-- rebuilding the compiler from the ablated tree --"
  if AXIOM_STDLIB="$abl/stdlib" "$axiom" build "$abl/self_host/main.ax" \
       -o "$work/axc-ablated" >"$work/ablated.build.log" 2>&1; then
    "$axc" emit-llvm "$fixture" -o "$work/fix.ll" >"$work/emit.log" 2>&1 \
      || { bad "could not emit the fixture under test"; sed 's/^/     /' "$work/emit.log" | head -10; }
    "$work/axc-ablated" emit-llvm "$fixture" -o "$work/fix-abl.ll" >>"$work/emit.log" 2>&1 \
      || { bad "could not emit the fixture ablated"; sed 's/^/     /' "$work/emit.log" | head -10; }
    if [[ -f "$work/fix.ll" && -f "$work/fix-abl.ll" ]]; then
      n_new="$(releases_in "$work/fix.ll")"
      n_abl="$(releases_in "$work/fix-abl.ll")"
      if (( n_new == 0 )); then
        bad "no releases at all under test - an elision that fires everywhere proves nothing"
      elif (( n_abl - n_new != 7 )); then
        bad "release delta is $((n_abl - n_new)) ($n_abl ablated, $n_new under test), wanted exactly 7"
      else
        other="$(diff "$work/fix-abl.ll" "$work/fix.ll" | grep -E '^[<>]' | grep -vc 'axiom_release' || true)"
        if (( other != 0 )); then
          bad "the two IRs differ by $other non-release line(s) - the elision moved something else"
          diff "$work/fix-abl.ll" "$work/fix.ll" | grep -E '^[<>]' | grep -v 'axiom_release' | head -10 | sed 's/^/     /'
        else
          ok "seven releases gone ($n_abl -> $n_new), and the IR diff is those seven lines and nothing else"
        fi
      fi
      # The ablated binary answers identically: the traffic was never
      # load-bearing for correctness, only for binary size.
      if "$work/axc-ablated" build --input "$fixture" --output "$work/phi-abl" >>"$work/emit.log" 2>&1; then
        "$work/phi-abl" >"$work/phi-abl.out" 2>&1
        rc_abl=$?
        if (( rc_abl != 0 )); then
          bad "the ablated fixture exits $rc_abl, wanted 0"
        elif ! cmp -s "$work/phi-abl.out" "$golden"; then
          bad "the ablated fixture's stdout differs - the ablation broke the program, not the traffic"
          diff "$golden" "$work/phi-abl.out" | head -10 | sed 's/^/     /'
        else
          ok "ablated binary answers the same eleven terms - the seven calls were binary only"
        fi
      else
        bad "the ablated fixture did not build"
      fi
    fi
  else
    bad "the ablated compiler did not build"
    sed 's/^/     /' "$work/ablated.build.log" | head -20
  fi
fi

# ---------------------------------------------------------------
echo
echo "== 3. three hundred thousand regions hold their RSS =="
# ---------------------------------------------------------------
cat > "$work/loop.ax" <<'AX'
(import IO)

(data Box (MkBox Int))

(:: mkBox (-> Int Box))

(fn (mkBox x) (MkBox x))

(:: usePhi (-> Box Int Int))

(fn (usePhi o d) (+ (match o ((MkBox x) x)) d))

; The RSS loop is iterative, not recursive: a `region` around a
; self-call is not a tail position (MM-EXEC-6b's whole subject), so
; a recursive loop would die of stack, identically, under both
; compilers - measuring nothing. `while` trips no frames at all.
; Each iteration calls home a join of two fresh calls: even
; iterations take the left arm, odd ones the right, so the sum
; pairs to one per two iterations.
(:: loop (-> Int Int))

(fn (loop n)
  (let ((mut i n))
    (let ((mut acc 0))
      {
        (while (> i 0)
          {
            (region r (set acc (+ acc (usePhi (if (== (% i 2) 0) (mkBox i) (mkBox (- 0 i))) 0))))
            (set i (- i 1))
          })
        acc
      }
    )
  )
)

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (println (loop 300000))
    0
  }
)
AX
if "$axc" build --input "$work/loop.ax" --output "$work/loop" >"$work/loop.build.log" 2>&1 \
   && [[ -f "$work/axc-ablated" ]] \
   && "$work/axc-ablated" build --input "$work/loop.ax" --output "$work/loop-abl" >>"$work/loop.build.log" 2>&1; then
  out_new="$("$work/loop" 2>&1)"; rc_new=$?
  out_abl="$("$work/loop-abl" 2>&1)"; rc_abl=$?
  if [[ "$out_new" != "$out_abl" || "$rc_new" != "$rc_abl" ]]; then
    bad "loop answers differ: test '$out_new'/$rc_new against ablated '$out_abl'/$rc_abl"
  elif [[ "$out_new" != "150000" ]]; then
    bad "loop answers $out_new, wanted 150000"
  else
    rss_new="$(max_rss_kb "$work/loop")" || rss_new=""
    rss_abl="$(max_rss_kb "$work/loop-abl")" || rss_abl=""
    if [[ -z "$rss_new" || -z "$rss_abl" ]]; then
      bad "could not measure peak RSS on this host"
    elif (( rss_abl == 0 )); then
      bad "ablated peak RSS reads 0 - the measurement is broken, not flat"
    else
      # Integer ratio x100: a load-bearing release dropped by mistake
      # leaks ~5 MiB over this loop (300000 × 16 B), which no noise
      # hides; identical traffic reads within it.
      ratio=$(( rss_new * 100 / rss_abl ))
      if (( ratio > 150 )); then
        bad "peak RSS ratio ${ratio}% (${rss_new} KiB against ${rss_abl} KiB) - the reset did not cover the elided traffic"
      else
        ok "loop answers 150000 both ways, peak RSS ${rss_new} KiB against ${rss_abl} KiB (${ratio}%)"
      fi
    fi
  fi
else
  bad "could not build the RSS loop under one or both compilers"
  sed 's/^/     /' "$work/loop.build.log" | head -10
fi

# ---------------------------------------------------------------
echo
echo "== 5. the adjacent hole, closed, refuses identically either way =="
# ---------------------------------------------------------------
# A callee-mediated store of a fresh construction into an outer cell
# from inside a region was the adjacent hole: unchecked, reading back
# wrong, every gate green. S3's reporting walk closes it - both
# compilers refuse the probe, which is what passes here. The elision
# cannot change the outcome either way, since the reset frees
# unconditionally; if the hole ever reopened, identical answers under
# both compilers would still pass.
cat > "$work/evil.ax" <<'AX'
(import IO)

(import Mem)

(data Box (MkBox Int))

(struct Cell (mut b : Box))

(:: evil (-> Cell Box Int))

(fn (evil c x) { (set c.b x) 0 })

(:: getInner (-> Box Int))

(fn (getInner o) (match o ((MkBox x) x)))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let ((c (Cell (MkBox 0))))
    {
      (region r
        {
          (evil c (MkBox 1))
          0
        })
      (let ((w (memAlloc 64)))
        {
          (memSet w 0 222)
          (println (getInner c.b))
          0
        })
      0
    }))
AX
built_new=0; built_abl=0
if "$axc" build --input "$work/evil.ax" --output "$work/evil" >"$work/evil.log" 2>&1; then built_new=1; fi
if [[ -f "$work/axc-ablated" ]] && "$work/axc-ablated" build --input "$work/evil.ax" --output "$work/evil-abl" >>"$work/evil.log" 2>&1; then built_abl=1; fi
if (( built_new != built_abl )); then
  bad "the probe builds under one compiler and not the other (test $built_new, ablated $built_abl)"
elif (( built_new == 0 )); then
  ok "both compilers refuse the probe identically - the checker learned the shape"
else
  out_new="$("$work/evil" 2>&1)"; rc_new=$?
  out_abl="$("$work/evil-abl" 2>&1)"; rc_abl=$?
  if [[ "$out_new" != "$out_abl" || "$rc_new" != "$rc_abl" ]]; then
    bad "the probe answers '$out_new'/$rc_new under test against '$out_abl'/$rc_abl ablated - the elision changed it"
  else
    ok "callee-mediated store reads back '$out_new'/$rc_new both ways - identical, and still wrong (see the design note)"
  fi
fi

echo
if (( failed > 0 )); then
  echo "check-region-phi: $failed check(s) failed, $checks passed"
  exit 1
fi
echo "check-region-phi: $checks checks - fresh joins are reset-reclaimed as arguments, and only binary changed"
