#!/usr/bin/env bash
# S4 slice 4, scrutinee path (docs/memory-model-v2-design.md §4):
# inside a `(region r BODY)` a `match` whose scrutinee the witness
# proved fresh - a call result, or a join whose every arm is one -
# needs no merge-path `axiom_release` for the temporary it
# consumed, because the reset reclaims it in one pointer move - and
# this is what holds that the elision fires, fires only there, and
# changes nothing but binary size.
#
# WHAT SLICE 4 IS, IN ONE ARGUMENT. Slices 1 through 3 owned
# releases whose operand IS the value's birth: a construction
# answered syntactically, a call result read off the MM-RGN-5
# witness, a join whose every arm carries the stamp. A match
# scrutinee is a fourth position holding the same birth: the
# temporary the match consumes, released after the merge when
# `scrutineeReleasable` says no arm binder escapes through its body
# (binders are the block's fields - releasing first would hand an
# arm a dangling field). The stamp is the same one (a fresh call,
# or a fresh join - including a nested match, whose result register
# is a scratch-cell load); `releaseScrutinee` spends it exactly
# where MM-LIFE-2c used to emit unconditionally, under the same
# depth gate, while the pending vector still takes the share for
# the tail-jump path, which keeps its release. `argOwnedRelease`
# is not asked here - `scrutineeReleasable` already decided - so
# `mustTailOK` cannot drift, and the tail and non-tail emitters
# share the one spend: the rule is position-independent by
# construction. TC word 40 (`rgnStamping`) is what keeps a
# still-moving row from ever becoming a stamp.
#
# Five checks, each with the reason a lesser gate would be vacuous:
#
#   1. THE ANSWERS. `tests/stdlib/484-region-scrutinee.ax` prints
#      twelve terms under the compiler under test, byte-identical
#      to its `.out` - a call scrutinee elided (term 1), `if`,
#      `match` and `cond` scrutinees elided (terms 2-4), a reader
#      scrutinee kept (term 5), a borrowed binder elided (term 6),
#      an escaping binder with no release site at all (term 7), the
#      un-regioned, `let`-bound and construction shapes kept (terms
#      8-10), the waterline back (term 11), fifty thousand regions
#      summed (term 12). A gate that stamped too eagerly fails here
#      first, against a golden no re-bless of the IR counts below
#      can move.
#   2. THE COUNT, AS A DELTA. The fixture's IR under this compiler
#      against the same IR under a compiler built from a tree whose
#      scrutinee spend never fires: eight fewer `axiom_release`
#      calls, and the `diff` between the two IRs is those eight
#      lines and nothing else. An absolute count would bless
#      whatever the println machinery contributes; a delta
#      distinguishes the eight this path owns from all of it. Eight
#      is terms 1-4 and 6, two in term 11 and the loop in term 12 -
#      counted by hand, asserted by machine. Terms 5 and 8-10 keep
#      theirs: a reader, no region, a borrowed `let` binding with
#      no site either way, and a construction the witness never
#      stamps. Term 7 has no release site in either arm -
#      `scrutineeReleasable` says 0 where a binder escapes bare -
#      so it never enters this delta.
#   3. THE RSS, AS A RATIO. A loop of 300,000 regions, each
#      consuming a fresh join scrutinee and dropping it, under both
#      compilers: same stdout, same exit, and this compiler's peak
#      RSS within 1.5x of the ablated one's. If an elided release
#      had been load-bearing the loop would leak ~5 MiB here and the
#      ratio would say so; the waterline term of check 1 already
#      says it exactly, and this says it dynamically. A ratio and
#      not a bound, so a loaded runner cannot fail it.
#   4. THE ABLATION IS WHAT MAKES 2 AND 3 MEAN ANYTHING. The tree is
#      copied, the scrutinee spend is made to never fire - the rule
#      still exists, still runs beside `scrutineeReleasable`, and
#      answers nothing - and a compiler is built from it. Eight
#      releases come back and only eight: any other delta fails the
#      gate, because an ablation that moved anything else broke the
#      program instead of restoring the traffic. Cost: one extra
#      compiler build, the price the sibling gates pay for the same
#      reason.
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
# found: tail-loop parameter slots (released on the callee's return
# path against its entry retain - callee-shared code no call site
# may elide), field and `mut`-slot old values (their release drops
# a share of unknown provenance - load-bearing unless proven
# otherwise, which no walker here proves), and field reads anywhere
# (a field read is a borrow at every site - argument, binding,
# scrutinee and join arm all answer unowned for one - so no release
# site exists to spend on; measured, not assumed). Field stores are
# excluded finally, not deferred: their release balances a retain
# in the same step (`emitSetF`), so eliding one half would leak.
# `musttail` paths stay conservative by construction (the pending
# vector keeps its share).
#
# Usage:
#   scripts/check-region-scrutinee.sh
#   AXIOM=path/to/compiler scripts/check-region-scrutinee.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

gate_build_axc axc

fixture="$repo_root/tests/stdlib/484-region-scrutinee.ax"
golden="$repo_root/tests/stdlib/484-region-scrutinee.out"

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
echo "== 1. the twelve terms answer under the compiler under test =="
# ---------------------------------------------------------------
if ! "$axc" build --input "$fixture" --output "$work/scrut" >"$work/build.log" 2>&1; then
  bad "could not build the fixture"
  sed 's/^/     /' "$work/build.log" | head -20
else
  "$work/scrut" >"$work/scrut.out" 2>&1
  rc=$?
  if (( rc != 0 )); then
    bad "the fixture exits $rc, wanted 0"
  elif ! cmp -s "$work/scrut.out" "$golden"; then
    bad "the fixture's stdout differs from $golden"
    diff "$golden" "$work/scrut.out" | head -10 | sed 's/^/     /'
  else
    ok "484-region-scrutinee: twelve terms byte-identical to the golden, exit 0"
  fi
fi

# ---------------------------------------------------------------
echo
echo "== 2-4. eight releases gone, nothing else moved, ablation red =="
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
# Anchored on the scrutinee spend, and only it: the args path reads
# `(nodeResWord a)`, the scope-end path reads `(nodeResWord
# valExpr)`, the chain walkers read `(nodeResWord snode)` for
# wordness, and ablating any of those instead would restore traffic
# this walker never owned - or break every closure application.
# Replacing the stamp read with a value no stamp takes leaves the
# rule in place - `scrutineeReleasable` still decides beside it on
# every match - and answering nothing. 2 is the only stamped value
# beside 0 and 1, so 3 fires nowhere.
old = "(== (nodeResWord scrutExpr) 2)"
if s.count(old) != 1:
    sys.stderr.write("scrutinee spend not found verbatim (%d)\n" % s.count(old))
    sys.exit(1)
open(p, "w").write(s.replace(old, "(== (nodeResWord scrutExpr) 3)"))
PY
then
  bad "could not ablate the scrutinee spend"
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
      elif (( n_abl - n_new != 8 )); then
        bad "release delta is $((n_abl - n_new)) ($n_abl ablated, $n_new under test), wanted exactly 8"
      else
        other="$(diff "$work/fix-abl.ll" "$work/fix.ll" | grep -E '^[<>]' | grep -vc 'axiom_release' || true)"
        if (( other != 0 )); then
          bad "the two IRs differ by $other non-release line(s) - the elision moved something else"
          diff "$work/fix-abl.ll" "$work/fix.ll" | grep -E '^[<>]' | grep -v 'axiom_release' | head -10 | sed 's/^/     /'
        else
          ok "eight releases gone ($n_abl -> $n_new), and the IR diff is those eight lines and nothing else"
        fi
      fi
      # The ablated binary answers identically: the traffic was never
      # load-bearing for correctness, only for binary size.
      if "$work/axc-ablated" build --input "$fixture" --output "$work/scrut-abl" >>"$work/emit.log" 2>&1; then
        "$work/scrut-abl" >"$work/scrut-abl.out" 2>&1
        rc_abl=$?
        if (( rc_abl != 0 )); then
          bad "the ablated fixture exits $rc_abl, wanted 0"
        elif ! cmp -s "$work/scrut-abl.out" "$golden"; then
          bad "the ablated fixture's stdout differs - the ablation broke the program, not the traffic"
          diff "$golden" "$work/scrut-abl.out" | head -10 | sed 's/^/     /'
        else
          ok "ablated binary answers the same twelve terms - the eight calls were binary only"
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

; The RSS loop is iterative, not recursive: a `region` around a
; self-call is not a tail position (MM-EXEC-6b's whole subject), so
; a recursive loop would die of stack, identically, under both
; compilers - measuring nothing. `while` trips no frames at all.
; Each iteration consumes a fresh join scrutinee: even iterations
; take the left arm, odd ones the right, so the sum pairs to one
; per two iterations.
(:: loop (-> Int Int))

(fn (loop n)
  (let ((mut i n))
    (let ((mut acc 0))
      {
        (while (> i 0)
          {
            (region r (set acc (+ acc (match (if (== (% i 2) 0) (mkBox i) (mkBox (- 0 i))) ((MkBox x) x)))))
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
  echo "check-region-scrutinee: $failed check(s) failed, $checks passed"
  exit 1
fi
echo "check-region-scrutinee: $checks checks - fresh scrutinee temporaries are reset-reclaimed, and only binary changed"
