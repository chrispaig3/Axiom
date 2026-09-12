#!/usr/bin/env bash
# S4 slice 1 (docs/memory-model-v2-design.md §4): inside a `(region r
# BODY)` a value the body itself constructed and drops needs no
# `axiom_release` - the reset reclaims it in one pointer move - and
# this is what holds that the elision fires, fires only there, and
# changes nothing but binary size.
#
# WHAT S4 IS, IN ONE SLICE. The design's whole claim is that a region
# reset returns in one pointer move what counting frees one object at
# a time (§1.1: deleting every release costs 2.4x peak RSS). This
# slice is the first traffic the discipline provably owns: a release
# whose operand IS the construction - a fully-applied data or struct
# construction, emitted right here, after the mark, at count 1 -
# dropped inside the region body. `isRegionCoveredCon`
# (self_host/codegen.ax) answers it; `releaseOwnedArgs` spends the
# answer while `argOwnedRelease` still says 1, so `mustTailOK` stays
# conservative and `check-tail-calls.sh` does not move.
#
# Five checks, each with the reason a lesser gate would be vacuous:
#
#   1. THE ANSWERS. `tests/stdlib/479-region-reclaim.ax` prints eight
#      terms under the compiler under test, byte-identical to its
#      `.out` - data and struct temporaries elided (terms 1-2), the
#      un-regioned, let-bound, lambda-bound and shadowed shapes kept
#      (terms 3-6), the waterline back (term 7), fifty thousand
#      regions summed (term 8). A gate that deleted releases too
#      eagerly fails here first, against a golden no re-bless of the
#      IR counts below can move.
#   2. THE COUNT, AS A DELTA. The fixture's IR under this compiler
#      against the same IR under a compiler built from a tree whose
#      predicate answers 0: six fewer `axiom_release` calls, and the
#      `diff` between the two IRs is those six lines and nothing
#      else. An absolute count would bless whatever the println
#      machinery contributes; a delta distinguishes the six this
#      slice owns from all of it. Six is terms 1, 2, three in term
#      7 and the loop in term 8 - counted by hand, asserted by
#      machine.
#   3. THE RSS, AS A RATIO. A loop of 300,000 regions, each building
#      and dropping a box, under both compilers: same stdout, same
#      exit, and this compiler's peak RSS within 1.5x of the
#      ablated one's. If an elided release had been load-bearing the
#      loop would leak ~5 MiB here and the ratio would say so; the
#      waterline term of check 1 already says it exactly, and this
#      says it dynamically. A ratio and not a bound, so a loaded
#      runner cannot fail it.
#   4. THE ABLATION IS WHAT MAKES 2 AND 3 MEAN ANYTHING. The tree is
#      copied, `isRegionCoveredCon` is made to answer 0 for every
#      operand - the rule still exists, still runs, and never fires -
#      and a compiler is built from it. Six releases come back and
#      only six: any other delta fails the gate, because an ablation
#      that moved anything else broke the program instead of
#      restoring the traffic. Cost: one extra compiler build, the
#      price `check-region-scope.sh` pays for the same reason.
#   5. THE ADJACENT HOLE, BEHAVING IDENTICALLY. A callee-mediated
#      store of a fresh construction into an outer cell from inside
#      a region is unchecked today (`rgnCheckAll` runs only under
#      `@r` signatures): it checks OK and reads back wrong, with
#      every gate green. That hole is NOT this slice - the reset
#      frees unconditionally, so eliding changes nothing there - and
#      this check pins that it changes nothing: the probe built by
#      this compiler and by the ablated one prints the same bytes
#      with the same exit. If both refuse to build (the day the
#      checker learns the shape) that is identical too, and passes.
#      Recorded in the design note's S4 subsection, not fixed here.
#
# What this gate does NOT cover, stated rather than left to be
# found: call results (freshness needs the MM-RGN-5 witness),
# `VAR` operands (def-tracking), field stores (paired retains), and
# `musttail` paths - each documented in the predicate's own comment
# with the reason. `emitLamDef`'s clearing of the depth is
# defense-in-depth under today's drain timing (lambdas always emit
# at depth 0 in the module loop); term 5 passes either way, and the
# comment says so.
#
# Usage:
#   scripts/check-region-reclaim.sh
#   AXIOM=path/to/compiler scripts/check-region-reclaim.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

gate_build_axc axc

fixture="$repo_root/tests/stdlib/479-region-reclaim.ax"
golden="$repo_root/tests/stdlib/479-region-reclaim.out"

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
echo "== 1. the eight terms answer under the compiler under test =="
# ---------------------------------------------------------------
if ! "$axc" build --input "$fixture" --output "$work/reclaim" >"$work/build.log" 2>&1; then
  bad "could not build the fixture"
  sed 's/^/     /' "$work/build.log" | head -20
else
  "$work/reclaim" >"$work/reclaim.out" 2>&1
  rc=$?
  if (( rc != 0 )); then
    bad "the fixture exits $rc, wanted 0"
  elif ! cmp -s "$work/reclaim.out" "$golden"; then
    bad "the fixture's stdout differs from $golden"
    diff "$golden" "$work/reclaim.out" | head -10 | sed 's/^/     /'
  else
    ok "479-region-reclaim: eight terms byte-identical to the golden, exit 0"
  fi
fi

# ---------------------------------------------------------------
echo
echo "== 2-4. six releases gone, nothing else moved, ablation red =="
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
# Anchored on the predicate's own head, and only the first guard
# read after it, so a later use of `pairSlot` elsewhere in the
# growing file is not silently ablated instead of - or as well as -
# this one. `(== 0 0)` is always true, so the rule still exists,
# still runs, and never fires.
head = "(pub fn (isRegionCoveredCon cg e)"
if s.count(head) != 1:
    sys.stderr.write("predicate head not found verbatim\n")
    sys.exit(1)
i = s.index(head)
j = s.index("(pairSlot cg 9)", i)
s = s[:j] + "0" + s[j + len("(pairSlot cg 9)"):]
open(p, "w").write(s)
PY
then
  bad "could not ablate the predicate's depth guard"
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
      elif (( n_abl - n_new != 6 )); then
        bad "release delta is $((n_abl - n_new)) ($n_abl ablated, $n_new under test), wanted exactly 6"
      else
        other="$(diff "$work/fix-abl.ll" "$work/fix.ll" | grep -E '^[<>]' | grep -vc 'axiom_release' || true)"
        if (( other != 0 )); then
          bad "the two IRs differ by $other non-release line(s) - the elision moved something else"
          diff "$work/fix-abl.ll" "$work/fix.ll" | grep -E '^[<>]' | grep -v 'axiom_release' | head -10 | sed 's/^/     /'
        else
          ok "six releases gone ($n_abl -> $n_new), and the IR diff is those six lines and nothing else"
        fi
      fi
      # The ablated binary answers identically: the traffic was never
      # load-bearing for correctness, only for binary size.
      if "$work/axc-ablated" build --input "$fixture" --output "$work/reclaim-abl" >>"$work/emit.log" 2>&1; then
        "$work/reclaim-abl" >"$work/reclaim-abl.out" 2>&1
        rc_abl=$?
        if (( rc_abl != 0 )); then
          bad "the ablated fixture exits $rc_abl, wanted 0"
        elif ! cmp -s "$work/reclaim-abl.out" "$golden"; then
          bad "the ablated fixture's stdout differs - the ablation broke the program, not the traffic"
          diff "$golden" "$work/reclaim-abl.out" | head -10 | sed 's/^/     /'
        else
          ok "ablated binary answers the same eight terms - the six calls were binary only"
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

(:: useBox (-> Box Int Int))

(fn (useBox o d) (+ (match o ((MkBox x) x)) d))

(:: spin (-> Int Int Int))

(fn (spin i acc)
  (if (<= i 0)
    acc
    (spin (- i 1) (+ acc (useBox (MkBox i) 0))))
)

; The RSS loop is iterative, not recursive: a `region` around a
; self-call is not a tail position (MM-EXEC-6b's whole subject), so
; a recursive loop would die of stack, identically, under both
; compilers - measuring nothing. `while` trips no frames at all.
(:: loop (-> Int Int))

(fn (loop n)
  (let ((mut i n))
    (let ((mut acc 0))
      {
        (while (> i 0)
          {
            (region r (set acc (+ acc (useBox (MkBox i) 0))))
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
  elif [[ "$out_new" != "45000150000" ]]; then
    bad "loop answers $out_new, wanted 45000150000"
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
        ok "loop answers 45000150000 both ways, peak RSS ${rss_new} KiB against ${rss_abl} KiB (${ratio}%)"
      fi
    fi
  fi
else
  bad "could not build the RSS loop under one or both compilers"
  sed 's/^/     /' "$work/loop.build.log" | head -10
fi

# ---------------------------------------------------------------
echo
echo "== 5. the adjacent hole behaves identically either way =="
# ---------------------------------------------------------------
# A callee-mediated store of a fresh construction into an outer cell
# from inside a region is unchecked today and reads back wrong. NOT
# this slice: the reset frees unconditionally, so the elision cannot
# change the outcome - and this pins that it does not. If both
# compilers refuse to build (the day the checker learns the shape)
# that refusal is itself identical, and passes.
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
  echo "check-region-reclaim: $failed check(s) failed, $checks passed"
  exit 1
fi
echo "check-region-reclaim: $checks checks - in-region constructions are reset-reclaimed, and only binary changed"
