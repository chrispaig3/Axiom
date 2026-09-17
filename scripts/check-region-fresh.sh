#!/usr/bin/env bash
# S4 slice 2, args path (docs/memory-model-v2-design.md §4): inside a
# `(region r BODY)` a call result the witness proved fresh needs no
# `axiom_release` - the reset reclaims it in one pointer move - and
# this is what holds that the elision fires, fires only there, and
# changes nothing but binary size.
#
# WHAT SLICE 2 IS, IN ONE ARGUMENT. Slice 1 owned releases whose
# operand IS the construction, answered syntactically where the value
# is built. A call result needs the MM-RGN-5 witness instead: the
# callee may alias an outer value, so freshness is read per callee
# off the region facts - result from CUR0, from no heap parameter (a
# scalar-typed parameter contributes no alias), from no call the walk
# could not resolve - never while facts are still moving and never
# when truncation made every row a lower bound. The checker stamps
# such a call `nodeResWord` 2 post-fixpoint (an upgrade 0 to 2; a word
# answer stays 1, and every old reader asks `== 1`); `releaseOwnedArgs`
# spends the stamp exactly where slice 1 spends its construction test
# while `argOwnedRelease` still says 1, so `mustTailOK` stays
# conservative and `check-tail-calls.sh` does not move. TC word 40
# (`rgnStamping`) is what keeps a still-moving row from ever becoming
# a stamp: the same `rgnPass` with report 0 runs inside `rgnRounds` on
# every round, so the report value cannot distinguish them.
#
# Five checks, each with the reason a lesser gate would be vacuous:
#
#   1. THE ANSWERS. `tests/stdlib/480-region-fresh-call.ax` prints
#      eight terms under the compiler under test, byte-identical to
#      its `.out` - a fresh call result elided (term 1), a reader's
#      result kept (term 2), the un-regioned, let-bound and
#      closure-called shapes kept (terms 3-5), a fresh result built
#      on both branch arms elided (term 6), the waterline back
#      (term 7), fifty thousand regions summed (term 8). A gate that
#      stamped too eagerly fails here first, against a golden no
#      re-bless of the IR counts below can move.
#   2. THE COUNT, AS A DELTA. The fixture's IR under this compiler
#      against the same IR under a compiler built from a tree whose
#      stamp never fires: six fewer `axiom_release` calls, and the
#      `diff` between the two IRs is those six lines and nothing
#      else. An absolute count would bless whatever the println
#      machinery contributes; a delta distinguishes the six this
#      slice owns from all of it. Six is terms 1, 6, three in term
#      7 and the loop in term 8 - counted by hand, asserted by
#      machine. Terms 2, 3, 4 and 5 keep theirs: a reader, no
#      region, a `VAR` at scope end (the next slice, not this one),
#      and a closure call the walk cannot resolve.
#   3. THE RSS, AS A RATIO. A loop of 300,000 regions, each calling
#      home a fresh box and dropping it, under both compilers: same
#      stdout, same exit, and this compiler's peak RSS within 1.5x of
#      the ablated one's. If an elided release had been load-bearing
#      the loop would leak ~5 MiB here and the ratio would say so;
#      the waterline term of check 1 already says it exactly, and
#      this says it dynamically. A ratio and not a bound, so a loaded
#      runner cannot fail it.
#   4. THE ABLATION IS WHAT MAKES 2 AND 3 MEAN ANYTHING. The tree is
#      copied, the witness stamp is made to never fire - the rule
#      still exists, still runs, and answers nothing - and a compiler
#      is built from it. Six releases come back and only six: any
#      other delta fails the gate, because an ablation that moved
#      anything else broke the program instead of restoring the
#      traffic. Cost: one extra compiler build, the price
#      `check-region-reclaim.sh` pays for the same reason.
#   5. THE ADJACENT HOLE, BEHAVING IDENTICALLY. A callee-mediated
#      store of a fresh construction into an outer cell from inside
#      a region is unchecked today (`rgnCheckAll` reports only under
#      `@r` signatures): it checks OK and reads back wrong, with
#      every gate green. That hole is NOT this slice - the reset
#      frees unconditionally, so the elision cannot change the
#      outcome - and this check pins that it does not. If both
#      compilers refuse to build (the day the checker learns the
#      shape) that refusal is itself identical, and passes.
#      Recorded in the design note's S4 subsection, not fixed here.
#
# What this gate does NOT cover, stated rather than left to be
# found: a fresh call result bound by `let` and released at scope end
# rather than passed as an argument - `releaseOwnedArgs` never sees
# it, so the stamp sits unused on it until the scope-end walker
# learns to read it. Term 4 pins one, kept. `VAR` operands and field
# stores are that walker's company, not this gate's; `musttail`
# paths stay conservative by construction (`argOwnedRelease`
# untouched).
#
# Usage:
#   scripts/check-region-fresh.sh
#   AXIOM=path/to/compiler scripts/check-region-fresh.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

gate_build_axc axc

fixture="$repo_root/tests/stdlib/480-region-fresh-call.ax"
golden="$repo_root/tests/stdlib/480-region-fresh-call.out"

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
if ! "$axc" build --input "$fixture" --output "$work/fresh" >"$work/build.log" 2>&1; then
  bad "could not build the fixture"
  sed 's/^/     /' "$work/build.log" | head -20
else
  "$work/fresh" >"$work/fresh.out" 2>&1
  rc=$?
  if (( rc != 0 )); then
    bad "the fixture exits $rc, wanted 0"
  elif ! cmp -s "$work/fresh.out" "$golden"; then
    bad "the fixture's stdout differs from $golden"
    diff "$golden" "$work/fresh.out" | head -10 | sed 's/^/     /'
  else
    ok "480-region-fresh-call: eight terms byte-identical to the golden, exit 0"
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

target="$abl/self_host/typecheck.ax"
if ! python3 - "$target" <<'PY'
import sys
p = sys.argv[1]
s = open(p).read()
# Anchored on the witness stamp's own call, and only it: the other
# `setNodeResWord` in this file stamps wordness during checking, and
# ablating that instead would break every closure application rather
# than restoring six releases. Replacing the stamp with 0 leaves the
# rule in place - the predicate still evaluates over converged facts
# on every post-fixpoint walk - and answering nothing.
old = "(setNodeResWord e 2)"
if s.count(old) != 1:
    sys.stderr.write("stamp not found verbatim (%d)\n" % s.count(old))
    sys.exit(1)
open(p, "w").write(s.replace(old, "0"))
PY
then
  bad "could not ablate the witness stamp"
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
      if "$work/axc-ablated" build --input "$fixture" --output "$work/fresh-abl" >>"$work/emit.log" 2>&1; then
        "$work/fresh-abl" >"$work/fresh-abl.out" 2>&1
        rc_abl=$?
        if (( rc_abl != 0 )); then
          bad "the ablated fixture exits $rc_abl, wanted 0"
        elif ! cmp -s "$work/fresh-abl.out" "$golden"; then
          bad "the ablated fixture's stdout differs - the ablation broke the program, not the traffic"
          diff "$golden" "$work/fresh-abl.out" | head -10 | sed 's/^/     /'
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

(:: mkBox (-> Int Box))

(fn (mkBox x) (MkBox x))

(:: useBox (-> Box Int Int))

(fn (useBox o d) (+ (match o ((MkBox x) x)) d))

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
            (region r (set acc (+ acc (useBox (mkBox i) 0))))
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
  echo "check-region-fresh: $failed check(s) failed, $checks passed"
  exit 1
fi
echo "check-region-fresh: $checks checks - fresh call results are reset-reclaimed as arguments, and only binary changed"
