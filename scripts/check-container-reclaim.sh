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
#   vec/mapped   `vecNewRef`  - the data block carries the ARRAY form,
#                so `vecFree` reaches the elements.
#   vec/leaf     `vecNew`     - the SAME program with a leaf data
#                block. `vecFree` still reclaims the header and the
#                buffer; every element leaks. This is the ablation of
#                the array form itself.
#
#   chain/freed  an `Intern` and a ref-valued `Map` built and freed
#                each iteration - five levels of map-walking, header
#                to `Vec` to data block to `Str` header to bytes.
#   chain/held   the SAME program with the two frees removed.
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
max_rss_kb() {
  if /usr/bin/time -l true >/dev/null 2>&1; then
    /usr/bin/time -l "$@" 2>&1 >/dev/null \
      | awk '/maximum resident set size/ {print int($1/1024)}'
  elif /usr/bin/time -v true >/dev/null 2>&1; then
    /usr/bin/time -v "$@" 2>&1 >/dev/null \
      | awk -F: '/Maximum resident set size/ {print int($2)}'
  else
    echo "FAIL: no usable time(1) for RSS measurement" >&2
    return 1
  fi
}

# emit_probe PROBE VARIANT N OUTFILE
#
# RESET-FREE BY CONSTRUCTION: neither spelling below mentions
# `__axiom_arena_mark` or `__axiom_arena_reset`, and `assert_reset_free`
# greps the generated file to make sure a later edit cannot quietly
# reintroduce one and turn this into another arena gate.
emit_probe() {
  local probe="$1" variant="$2" n="$3" out="$4"
  case "$probe" in
    vec)
      local ctor='vecNewRef'
      [[ "$variant" == leaf ]] && ctor='vecNew'
      cat > "$out" <<AX
; $n iterations, each building a 32-element Vec of freshly duplicated
; Strings and dropping it. Variant: $variant (constructor $ctor).
(import IO)
(import Vec)
(import Str)

(:: build (-> Int Int))
(fn (build n)
  (let ((v $ctor) (mut i 0))
    {
      (while (< i n)
        {
          (vecPush v (strDup "hello world hello world"))
          (set i (+ i 1))
        })
      (let ((r (vecLen v))) { (vecFree v) r })
    }))

(:: loop (-> Int Int Int))
(fn (loop n acc)
  (if (== n 0) acc (loop (- n 1) (+ acc (build 32)))))

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
      # The ablation is the two frees, and nothing else. `(+ 0 0)`
      # keeps both spellings the same shape - a statement each, in the
      # same position - so the difference is reclamation and not the
      # optimiser seeing a smaller function.
      local freeMap='(mapFree m)' freeIt='(internFree it)'
      if [[ "$variant" == held ]]; then freeMap='(+ 0 0)'; freeIt='(+ 0 0)'; fi
      cat > "$out" <<AX
; $n iterations, each building a 32-entry ref-valued Map and a
; 40-string Intern and dropping both. Variant: $variant.
(import IO)
(import Map)
(import Intern)
(import Str)
(import Fmt)

(:: buildMap (-> Int Int))
(fn (buildMap n)
  (let ((m mapNewRefVals) (mut i 0))
    {
      (while (< i n)
        { (mapInsert m i (strDup "hello world hello world")) (set i (+ i 1)) })
      (let ((r (mapLen m))) { $freeMap r })
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
#    ceiling" - a line that reads as evidence and was not. 512 KiB is
#    below the 1 MiB chunk the allocator maps before it hands out a
#    byte, so nothing that ran can be under it.
for k in vec_mapped chain_freed; do
  r="$(rssof "${k}_${large}")"
  if [[ "$r" -lt 512 ]]; then
    echo "FAIL: $k measured ${r} KiB at n=$large, under the 512 KiB floor - that is not a running program"
    failed=1
  elif [[ "$r" -gt 4096 ]]; then
    echo "FAIL: $k holds ${r} KiB at n=$large, past the 4096 KiB ceiling"
    failed=1
  else
    echo "ok   $k holds ${r} KiB at n=$large, inside 512..4096 KiB"
  fi
done

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
# FEATURE can go red, and both were made to, by hand, on 2026-08-24.
# Each ablation costs a compiler build, so they are recorded here
# rather than run, and these are the ACTUAL runs, unedited.
#
# (a) `local ctor='vecNewRef'` in `emit_probe` changed to `'vecNew'` -
#     the ablation of THE ARRAY FORM ALONE, which is the feature this
#     whole change adds. `vecFree` still runs and still reclaims the
#     header and the data block; only the elements are unreachable.
#
#       probe/variant        n=1000  n=20000  growth
#       vec_mapped             4336    61328  14x
#       vec_leaf               4320    61328  14x
#       chain_freed            1344     1344  1x
#       chain_held            10272   179824  17x
#
#       FAIL: vec/mapped grew from 4336 KiB to 61328 KiB over 20x the
#             iterations - it does not plateau
#       ok   vec/leaf grows with n: 61328 KiB against 4320 KiB, past 5x
#       FAIL: vec/leaf over vec/mapped at n=20000 is 61328 against
#             61328, under the 5x this gate exists to see
#       ...
#       FAIL: vec_mapped holds 61328 KiB at n=20000, past the 4096 KiB
#             ceiling
#       check-container-reclaim: FAILED          (exit status 1)
#
# (b) `(vecFree v)` in the vec probe replaced with `(+ 0 0)`, so
#     nothing is ever released at all:
#
#       vec_mapped             4656    67568  14x
#       vec_leaf               4656    67568  14x
#
#       FAIL: vec/mapped grew from 4656 KiB to 67568 KiB over 20x the
#             iterations - it does not plateau
#       FAIL: vec/leaf over vec/mapped at n=20000 is 67568 against
#             67568, under the 5x this gate exists to see
#       FAIL: vec_mapped holds 67568 KiB at n=20000, past the 4096 KiB
#             ceiling
#       check-container-reclaim: FAILED          (exit status 1)
#
# Three assertions fire on each, and the `chain` half stayed green
# through both - which is the other thing worth knowing, because it
# says the two probes are independent rather than one measurement
# printed twice.
#
# The unablated run, for the record:
#
#       vec_mapped             1344     1344  1x
#       vec_leaf               4320    61328  14x
#       chain_freed            1344     1344  1x
#       chain_held            10272   179824  17x
# ---------------------------------------------------------------

if [[ "$failed" == 0 ]]; then
  echo "check-container-reclaim: gate passed"
else
  echo "check-container-reclaim: FAILED"
fi
exit "$failed"
