#!/usr/bin/env bash
# THE CONTAINER RECLAMATION GATE (docs/memory-model.md MM-LIFE-2h).
#
# Every other memory gate in this repository is reset-BASED: every arm
# of `measure-memory-baseline.sh` calls `__axiom_arena_mark` and
# `__axiom_arena_reset`, so all of them measure a program that hands
# whole regions back at once. This one measures the other half - a
# program that never resets anything, allocates containers in a loop,
# drops them, and must not grow. That is the shape of a server, an
# agent loop, and a compiler pass run twice, and until this gate
# existed nothing in the tree asserted it.
#
# WHAT IS MEASURED, AND WHY IT IS MAX RSS. The in-fixture technique the
# 35x-series ARC fixtures use - two probe allocations bracketing a loop,
# their address difference bounding the bump - does not survive a chunk
# crossing, and these loops cross many: bump addresses in different
# 1 MiB chunks are not comparable, and the difference comes back as a
# garbage number rather than a failure. There is no cumulative
# allocation counter in the runtime (`@__axiom_bump`, `_bump_end`,
# `_chunk`, `_free`, `_high`, `_slabs` - none is cumulative). Max RSS
# is the only observation that survives, and it is what a person
# watching the process would see anyway.
#
# THE ABLATED ARM IS MANDATORY, NOT DECORATIVE. A flat line also reads
# flat when the measurement is broken - when the probe was optimised
# away, when the loop count never reached the binary, when `time -l`
# answered for the wrong process. So each probe ships in two spellings
# that differ by ONE WORD, and the gate asserts that the two DISAGREE
# by more than 5x. If both go flat the gate goes red; if both grow the
# gate goes red. It can only pass if reclamation is happening AND the
# instrument can see it.
#
#   vec/mapped   `vecPush`    - the vector's first element is a
#                `String`, so it owns its elements and its data block
#                carries the ARRAY form. Nothing frees it by hand: it
#                dies at the end of its scope, and its death reaches
#                the elements.
#   vec/leaf     `vecPushStr` - the SAME program, but each string goes
#                in as a word the vector makes no claim on, so the
#                vector stays plain and its data block a leaf. The
#                scope end still reclaims the header and the buffer;
#                every element leaks. This is the ablation of the
#                array form itself.
#
#   big/mapped   the SAME pair at 16,384 elements instead of 32, which
#   big/leaf     is past the point where the array form used to stop
#                working. Its own section below says why it is not
#                simply a third `n` on the pair above.
#
#   chain/freed  an `Intern` and a `Map` of strings built and dropped
#                each iteration - five levels of map-walking, header
#                to `Vec` to data block to `Str` header to bytes. The
#                map dies at the end of its scope; the interner is an
#                `Int` handle and is freed by hand.
#   chain/held   the SAME program with the map kept alive by one extra
#                share and the interner's free removed.
#
# Usage:
#   scripts/check-container-reclaim.sh           # gate (the default)
#   scripts/check-container-reclaim.sh --report  # print the table too
#   AXIOM=path/to/compiler scripts/...           # any compiler

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

report=0
[[ "${1:-}" == "--report" ]] && report=1

# `measure-memory-baseline.sh`'s reader, and its rule: fail rather than
# skip when neither `time` answers. A measurement script that silently
# measures nothing is how the last RSS regression hid.
# (`max_rss_kb` itself is defined once, in scripts/lib/gate.sh.)

# emit_probe PROBE VARIANT N OUTFILE
#
# RESET-FREE BY CONSTRUCTION: neither spelling below mentions
# `__axiom_arena_mark` or `__axiom_arena_reset`, and `assert_reset_free`
# greps the generated file to make sure a later edit cannot quietly
# reintroduce one and turn this into another arena gate.
emit_probe() {
  local probe="$1" variant="$2" n="$3" out="$4"
  case "$probe" in
    vec|big)
      local push='vecPush' elems=32
      [[ "$variant" == leaf ]] && push='vecPushStr'
      [[ "$probe" == big ]] && elems=16384
      cat > "$out" <<AX
; $n iterations, each building a $elems-element Vec of freshly duplicated
; Strings and dropping it. Variant: $variant (each pushed by $push).
(import IO)
(import Vec)
(import Str)

(:: build (-> Int Int))
(fn (build n)
  (let ((v vecNew) (mut i 0))
    {
      (while (< i n)
        {
          ($push v (strDup "hello world hello world"))
          (set i (+ i 1))
        })
      (vecLen v)
    }))

(:: loop (-> Int Int Int))
(fn (loop n acc)
  (if (== n 0) acc (loop (- n 1) (+ acc (build $elems)))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (loop $n 0))
    0
  })
AX
      ;;
    chain)
      # The ablation is one statement per container, and nothing
      # else. `mapHeld` takes a share nobody hands back, so the map
      # outlives its scope; `(+ 0 0)` replaces the interner's free.
      # Both spellings keep the same shape - a statement each, in the
      # same position - so the difference is reclamation and not the
      # optimiser seeing a smaller function.
      local keepMap='(mapLen m)' freeIt='(internFree it)'
      if [[ "$variant" == held ]]; then keepMap='(mapHeld m)'; freeIt='(+ 0 0)'; fi
      cat > "$out" <<AX
; $n iterations, each building a 32-entry Map of Strings and a
; 40-string Intern and dropping both. Variant: $variant.
(import IO)
(import Map)
(import Intern)
(import Str)
(import Fmt)

; One share of the map that nothing hands back.
(:: mapHeld (-> Map Int))
;@axiom:effect(unsafe)
(fn (mapHeld m)
  {
    (__retain (cast Int m))
    (mapLen m)
  })

(:: buildMap (-> Int Int))
(fn (buildMap n)
  (let ((m mapNew) (mut i 0))
    {
      (while (< i n)
        { (mapInsert m i (strDup "hello world hello world")) (set i (+ i 1)) })
      (let ((r (mapLen m))) { $keepMap r })
    }))

(:: buildIntern (-> Int Int))
(fn (buildIntern n)
  (let ((it internNew) (mut i 0))
    {
      (while (< i n)
        { (internIntern it (fmtInt i)) (set i (+ i 1)) })
      (let ((r (internCount it))) { $freeIt r })
    }))

(:: loop (-> Int Int Int))
(fn (loop n acc)
  (if (== n 0) acc (loop (- n 1) (+ acc (+ (buildMap 32) (buildIntern 40))))))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (loop $n 0))
    0
  })
AX
      ;;
  esac
}

failed=0

# The gate's own precondition. `check-memory-baseline.sh` owns the
# reset-based measurement; this one is worth nothing if it drifts into
# being a second copy of it.
assert_reset_free() {
  local f="$1"
  if grep -q '__axiom_arena_' "$f"; then
    echo "FAIL: $(basename "$f") names an arena primitive - this gate measures the reset-FREE path"
    failed=1
  fi
}

# build_and_measure PROBE VARIANT N -> sets $out (stdout) and $rss (KiB)
build_and_measure() {
  local probe="$1" variant="$2" n="$3"
  local src="$work/${probe}_${variant}_$n.ax" bin="$work/${probe}_${variant}_$n"
  emit_probe "$probe" "$variant" "$n" "$src"
  assert_reset_free "$src"
  if ! "$axc" build --input "$src" --output "$bin" --opt 2 \
       >"$work/build_${probe}_${variant}_$n.log" 2>&1; then
    echo "FAIL: $probe/$variant did not build at n=$n" >&2
    tail -5 "$work/build_${probe}_${variant}_$n.log" >&2
    return 1
  fi
  out="$("$bin")"
  rss="$(max_rss_kb "$bin")" || return 1
  # A measurement of zero is not a small number, it is a broken
  # instrument, and every assertion below divides by one of these.
  if [[ -z "$rss" || "$rss" -le 0 ]]; then
    echo "FAIL: $probe/$variant at n=$n measured no RSS at all ('$rss')"
    failed=1
    rss=1
  fi
}

# The two counts. 1,000 is the small end and 20,000 the large one, a
# 20x range - so an arm that is linear in the iteration count shows it
# unambiguously and an arm that is flat cannot fake it.
small=1000
large=20000

# macOS ships bash 3.2, which has no associative arrays, so the results
# live in ordinary variables named `V_<probe>_<variant>_<n>_<field>`.
# Every reader below goes through `getv`, which answers the empty
# string for a key that was never set - and every arithmetic use of one
# supplies its own default, because an arm that failed to build must
# make the gate red rather than make it divide by nothing.
setv() { eval "V_$1=\"\$2\""; }
getv() { eval "printf '%s' \"\${V_$1-}\""; }

for probe in vec chain; do
  if [[ "$probe" == vec ]]; then variants="mapped leaf"; else variants="freed held"; fi
  for variant in $variants; do
    for n in "$small" "$large"; do
      build_and_measure "$probe" "$variant" "$n" || { failed=1; continue; }
      setv "${probe}_${variant}_${n}_rss" "$rss"
      setv "${probe}_${variant}_${n}_out" "$out"
    done
  done
done

# THE BIG ARM, at ONE iteration count and outside the loop above, and
# both of those are deliberate.
#
# 16,384 elements is past the point where the array form used to stop
# working: the shape word's array LENGTH used to be read out of the
# allocator's word count in bits 1..14, which the allocator clamps to 0
# past 16,383 words, so a data block of 131,072 bytes announced itself
# as an array of zero handles and `vecFree` released none of its
# elements. Measured on the compiler at 50ae6a2 (2026-09-03), n=200:
# big/mapped and big/leaf were BOTH 335,344 KiB - identical to the
# kilobyte, which is what an ablation that stopped being an ablation
# looks like. The length now lives in bits 16..62.
#
# ONE COUNT, BECAUSE THIS ARM DOES NOT PLATEAU AND SHOULD NOT CLAIM TO.
# The 131,072-byte data block is itself past the 8,192-word (64 KiB)
# pool ceiling in the release path's `filev`, so it is never filed and
# never reused; only the ELEMENTS come back. big/mapped is therefore
# linear in the iteration count at about 130 KiB a turn - measured
# 9,520 / 16,048 / 29,088 / 55,120 KiB at n = 50 / 100 / 200 / 400 -
# and assertion 2's plateau test would go red on a correct compiler.
# Anyone reading this arm as "big reference vectors are now flat" will
# be wrong. What it asserts is the 10x separation from its ablation,
# which is the elements and nothing else.
bigN=100
for variant in mapped leaf; do
  build_and_measure big "$variant" "$bigN" || { failed=1; continue; }
  setv "big_${variant}_${bigN}_rss" "$rss"
  setv "big_${variant}_${bigN}_out" "$out"
done

rssof() {
  local v
  v="$(getv "$1_rss")"
  if [[ -z "$v" ]]; then echo 0; else echo "$v"; fi
}

if [[ "$report" == 1 ]]; then
  echo
  printf '%-18s %8s %8s  %s\n' "probe/variant" "n=$small" "n=$large" "growth"
  for k in vec_mapped vec_leaf chain_freed chain_held; do
    a="$(rssof "${k}_${small}")"; b="$(rssof "${k}_${large}")"
    printf '%-18s %8s %8s  %sx\n' "$k" "$a" "$b" "$(( a > 0 ? b / a : 0 ))"
  done
  echo
  printf '%-18s %8s\n' "probe/variant" "n=$bigN"
  for k in big_mapped big_leaf; do
    printf '%-18s %8s\n' "$k" "$(rssof "${k}_${bigN}")"
  done
  echo
fi

# ratio_at_least NAME NUM DEN K - assert NUM >= K * DEN, in integers.
ratio_at_least() {
  local name="$1" num="$2" den="$3" k="$4"
  if [[ "$den" -le 0 ]]; then
    echo "FAIL: $name has no denominator to divide by - that arm did not measure"
    failed=1
    return
  fi
  if [[ "$num" -lt $(( den * k )) ]]; then
    echo "FAIL: $name is ${num} against ${den}, under the ${k}x this gate exists to see"
    failed=1
  else
    echo "ok   $name: ${num} KiB against ${den} KiB, past ${k}x"
  fi
}

for probe in vec chain; do
  if [[ "$probe" == vec ]]; then live=mapped; dead=leaf; else live=freed; dead=held; fi

  # 1. THE COMPUTATION IS THE SAME ONE. Both spellings must print the
  #    same answer at both counts, or the two arms are not comparable
  #    and the RSS difference is measuring two different programs.
  for n in "$small" "$large"; do
    lo="$(getv "${probe}_${live}_${n}_out")"
    do_="$(getv "${probe}_${dead}_${n}_out")"
    if [[ -z "$lo" || "$lo" != "$do_" ]]; then
      echo "FAIL: $probe printed '$lo' live and '$do_' ablated at n=$n - different programs"
      failed=1
    fi
  done

  # 2. THE REAL ARM PLATEAUS. Twenty times the work, and it may not
  #    take half again as much memory. This is the assertion that goes
  #    red if reclamation regresses.
  a="$(rssof "${probe}_${live}_${small}")"; b="$(rssof "${probe}_${live}_${large}")"
  if [[ "$a" -le 0 || $(( b * 2 )) -gt $(( a * 3 )) ]]; then
    echo "FAIL: $probe/$live grew from ${a} KiB to ${b} KiB over 20x the iterations - it does not plateau"
    failed=1
  else
    echo "ok   $probe/$live plateaus: ${a} KiB at $small, ${b} KiB at $large"
  fi

  # 3. THE ABLATED ARM GROWS PAST 5x, twice over: against its own
  #    small-n figure (the instrument can see growth at all) and
  #    against the real arm at the same count (the difference is
  #    reclamation, not noise). Either one alone is satisfiable by a
  #    broken measurement; both together are not.
  ratio_at_least "$probe/$dead grows with n" \
    "$(rssof "${probe}_${dead}_${large}")" "$(rssof "${probe}_${dead}_${small}")" 5
  ratio_at_least "$probe/$dead over $probe/$live at n=$large" \
    "$(rssof "${probe}_${dead}_${large}")" "$(rssof "${probe}_${live}_${large}")" 5
done

# 4. AN ABSOLUTE CEILING, so that "flat" cannot mean "flat at 300 MB".
#    The live set is a few kilobytes; the allocator's chunk is 1 MiB
#    and it maps two or three of them. 4096 KiB is
#    `check-memory-baseline.sh`'s ceiling, measured against the same
#    quantisation.
#    A FLOOR AS WELL AS A CEILING, because a ceiling alone is happiest
#    at zero: run against a compiler that could not build these
#    probes, every arm above went red and this one still printed
#    "ok   vec_mapped holds 0 KiB at n=20000, inside the 4096 KiB
#    ceiling" - a line that reads as evidence and was not.
#
#    64 KiB, and not the 512 the first draft carried, for the reason
#    `check-steady-state.sh` records at its own floor: 512 was a darwin
#    measurement standing in for a portable bound, and a Linux binary
#    is freestanding with no dyld behind it. What a floor can honestly
#    assert is that the instrument answered at all.
for k in vec_mapped chain_freed; do
  r="$(rssof "${k}_${large}")"
  if [[ "$r" -lt 64 ]]; then
    echo "FAIL: $k measured ${r} KiB at n=$large, under the 64 KiB floor - that is not a running program"
    failed=1
  elif [[ "$r" -gt 4096 ]]; then
    echo "FAIL: $k holds ${r} KiB at n=$large, past the 4096 KiB ceiling"
    failed=1
  else
    echo "ok   $k holds ${r} KiB at n=$large, inside 64..4096 KiB"
  fi
done

# 5. THE BIG ARM, past the count field's ceiling. Two assertions, and
#    each is red on the pre-fix compiler for its own reason.
#
#    (a) the same program. big/mapped and big/leaf must print the same
#        answer, or the RSS difference is two programs and not one
#        release path.
#    (b) the separation. Measured after the fix at n=100: big/mapped
#        16,032 KiB, big/leaf 168,416 KiB - 10.5x. Before it: 168,416
#        against 168,416, 1x.
#    (c) a ceiling on the live arm, derived rather than guessed. Each
#        iteration strands one 131,072-byte data block that `filev`
#        will not pool, so the floor this arm can reach is
#        $bigN x 128 KiB = 12,800 KiB and 16,032 is what it measures.
#        40,960 KiB is a little over 3x that headroom and a little over
#        4x below the 168,432 the unfixed compiler produces, so the
#        ceiling separates the two without pinning the measurement to
#        one machine's quantisation. There is no floor pair here
#        because (b)'s denominator already refuses to be zero.
lo="$(getv "big_mapped_${bigN}_out")"
do_="$(getv "big_leaf_${bigN}_out")"
if [[ -z "$lo" || "$lo" != "$do_" ]]; then
  echo "FAIL: big printed '$lo' live and '$do_' ablated at n=$bigN - different programs"
  failed=1
fi
ratio_at_least "big/leaf over big/mapped at n=$bigN" \
  "$(rssof "big_leaf_${bigN}")" "$(rssof "big_mapped_${bigN}")" 5
bigr="$(rssof "big_mapped_${bigN}")"
if [[ "$bigr" -gt 40960 ]]; then
  echo "FAIL: big/mapped holds ${bigr} KiB at n=$bigN, past the 40960 KiB ceiling - the elements are not coming back"
  failed=1
else
  echo "ok   big/mapped holds ${bigr} KiB at n=$bigN, inside the 40960 KiB ceiling"
fi

# ---------------------------------------------------------------
# THE NEGATIVE PROBE, run in full every time this gate runs.
#
# Assertions 2 and 3 are each other's negative: the SAME instrument
# reads one arm flat and the other linear in the same invocation, so
# there is no reading of "the measurement is broken" that leaves this
# gate green. That is what the ablated arm buys, and it is why it is
# built and run rather than described.
#
# The remaining question is whether the assertions that guard the
# FEATURE can go red, and each was made to, by hand. Each ablation
# costs a compiler build, so they are recorded here rather than run,
# and these are the actual runs.
#
# (a) THE ARRAY FORM ALONE: `Mem.memMarkArray` made a no-op (its 32768
#     and its count both 0), so no element buffer is ever walked. The
#     vectors and the table still die; only their elements leak.
#
#       probe/variant        n=1000  n=20000  growth
#       vec_mapped             4576    61600  13x
#       vec_leaf               4576    61584  13x
#       chain_freed            7744   124096  16x
#       chain_held            10528   180384  17x
#       big_mapped           168688
#       big_leaf             168688
#
#     Every arm that reclaims elements fails: the vec and big
#     plateaus, separations and ceilings, and the chain's, whose map
#     stops handing its strings back.
#
# (b) THE VECTOR'S DEATH: `Vec` put back on `scalarTyName`'s list in
#     codegen, so nothing releases a vector at the end of its scope:
#
#       vec_mapped             4912    67824  13x
#       vec_leaf               4896    67824  13x
#       chain_freed            1616     1600  0x
#       chain_held            10528   180368  17x
#       big_mapped           168688
#       big_leaf             168688
#
#     The vec and big assertions fire, and the chain half stays green:
#     a `Map` is a struct the compiler always counted, which says the
#     two probes are independent rather than one measurement printed
#     twice.
#
# The unablated run, for the record:
#
#       vec_mapped             1600     1600  1x
#       vec_leaf               4576    61600  13x
#       chain_freed            1616     1616  1x
#       chain_held            10528   180384  17x
#       big_mapped            16304
#       big_leaf             168704
# ---------------------------------------------------------------

if [[ "$failed" == 0 ]]; then
  echo "check-container-reclaim: gate passed"
else
  echo "check-container-reclaim: FAILED"
fi
exit "$failed"
