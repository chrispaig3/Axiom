#!/usr/bin/env bash
# THE STEADY-STATE GATE (the readiness plan's P3, stated so it can be
# falsified: *a long-running job with no request boundary must reach a
# measured steady state*).
#
# WHAT THIS MEASURES THAT NOTHING ELSE DOES. Every other memory gate in
# this repository measures a program that hands whole regions back:
# `measure-memory-baseline.sh` and `check-net.sh` bracket their work in
# `__axiom_arena_mark`/`__axiom_arena_reset`, and even
# `check-container-reclaim.sh` - the reset-free one - builds a container,
# fills it, and FREES THE WHOLE THING each iteration. That is a request
# handler. This is the other workload, the one the batch-and-agent
# decision put on the critical path: a process that never resets, never
# frees the container, and holds a LIVE SET whose size is bounded while
# its contents turn over completely.
#
#   cache      a 256-entry window over 2,000,000 keys. Every iteration
#              inserts one and removes the one 256 back, so `mapLen` is
#              256 forever and every string in it is younger than 256
#              iterations. The eviction path - `mapRemove` handing back
#              the value's share - is the whole subject.
#   aggregate  64 fixed keys whose values are REPLACED every iteration.
#              `mapLen` is 64 forever and nothing is ever removed. The
#              overwrite path is the subject, and it is a different one:
#              `mapInsert` handing back the value it displaces.
#
# Neither shape appears in `check-container-reclaim.sh`, which frees
# containers whole and never removes or overwrites an element.
#
# THREE MAGNITUDES, NOT TWO, and that is the difference between "steady
# state" and "sublinear". A program that grows as log n passes any
# 1x-against-20x ratio test comfortably. It does not pass a PLATEAU
# test: the 100x arm has to land within a few hundred kilobytes of the
# 10x arm, which is a claim about the shape and not about the slope.
#
# EACH LIVE ARM HAS AN ABLATED TWIN THAT MUST GROW, because a flat line
# also reads flat when the measurement is broken - when the loop count
# never reached the binary, when `time -l` answered for the wrong
# process. The twins differ by ONE form each:
#
#   cache/hoarding    the `mapRemove` replaced by `(+ 0 0)`. Same
#                     statement position, same shape, no eviction.
#   aggregate/leaking `mapNew` instead of `mapNewRefVals`. One word,
#                     and the two arms print the SAME ANSWER - which is
#                     what says they did the same work and differ only
#                     in what they hand back.
#
# Usage:
#   scripts/check-steady-state.sh           # gate (the default)
#   scripts/check-steady-state.sh --report  # print the table too

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

failed=0

# emit_probe PROBE VARIANT N OUTFILE
emit_probe() {
  local probe="$1" variant="$2" n="$3" out="$4"
  case "$probe" in
    cache)
      local evict='(mapRemove m (- i windowSize))'
      [[ "$variant" == hoarding ]] && evict='(+ 0 0)'
      cat > "$out" <<AX
; A 256-entry window over $n keys. Variant: $variant.
(import IO)
(import Map)
(import Str)
(import Fmt)

(:: windowSize Int)
(fn (windowSize) 256)

(:: churn (-> Int Int Int Int))
(fn (churn m i n)
  (if (>= i n)
    (mapLen m)
    {
      (mapInsert m i (strDup (fmtInt i)))
      (if (>= i windowSize) $evict m)
      (churn m (+ i 1) n)
    }))

(:: main Int)
;@axiom:effect(io)
(fn (main) { (println (churn mapNewRefVals 0 $n)) 0 })
AX
      ;;
    aggregate)
      local ctor='mapNewRefVals'
      [[ "$variant" == leaking ]] && ctor='mapNew'
      cat > "$out" <<AX
; 64 fixed keys, values replaced $n times. Variant: $variant.
(import IO)
(import Map)
(import Str)
(import Fmt)

(:: keyCount Int)
(fn (keyCount) 64)

(:: churn (-> Int Int Int Int))
(fn (churn m i n)
  (if (>= i n)
    (mapLen m)
    {
      (mapInsert m (% i keyCount) (strDup (fmtInt i)))
      (churn m (+ i 1) n)
    }))

(:: main Int)
;@axiom:effect(io)
(fn (main) { (println (churn $ctor 0 $n)) 0 })
AX
      ;;
  esac
}

# The gate's own precondition. `check-memory-baseline.sh` owns the
# reset-based measurement; this one is worth nothing if it drifts into
# being a third copy of it.
assert_reset_free() {
  local f="$1"
  if grep -q '__axiom_arena_' "$f"; then
    echo "FAIL: $(basename "$f") names an arena primitive - this gate measures the reset-FREE path"
    failed=1
  fi
}

# macOS ships bash 3.2, which has no associative arrays.
# `check-container-reclaim.sh` works around it with exactly these two
# lines, and a second idiom for one problem would be worse than the
# duplication.
setv() { eval "V_$1=\"\$2\""; }
getv() { eval "printf '%s' \"\${V_$1-}\""; }

run_probe() {
  local probe="$1" variant="$2" n="$3"
  local key="${probe}_${variant}_${n}"
  local src="$work/$key.ax" bin="$work/$key"
  emit_probe "$probe" "$variant" "$n" "$src"
  assert_reset_free "$src"
  if ! "$axc" build --input "$src" --output "$bin" --opt 2 >"$work/$key.log" 2>&1; then
    echo "FAIL: $probe/$variant did not build at n=$n"
    tail -5 "$work/$key.log" | sed 's/^/    /'
    failed=1
    return 1
  fi
  local o rc
  o="$("$bin")"
  rc=$?
  if (( rc != 0 )); then
    echo "FAIL: $probe/$variant exited $rc at n=$n"
    failed=1
    return 1
  fi
  local r
  r="$(max_rss_kb "$bin")" || { failed=1; return 1; }
  # A measurement of zero is not a small number, it is a broken
  # instrument, and every assertion below reads one of these.
  if [[ -z "$r" || "$r" -le 0 ]]; then
    echo "FAIL: $probe/$variant at n=$n measured no RSS at all ('$r')"
    failed=1
    return 1
  fi
  setv "${key}_rss" "$r"
  setv "${key}_out" "$o"
}

small=20000
mid=200000
large=2000000

for probe in cache aggregate; do
  live=owning; [[ "$probe" == cache ]] && live=evicting
  for n in "$small" "$mid" "$large"; do
    run_probe "$probe" "$live" "$n"
  done
done
run_probe cache hoarding "$mid"
run_probe aggregate leaking "$mid"

rssof() {
  local v
  v="$(getv "$1_rss")"
  if [[ -z "$v" ]]; then echo 0; else echo "$v"; fi
}
outof() { getv "$1_out"; }

if (( report )); then
  printf '\n%-26s %8s %8s %8s\n' "probe/variant" "n=$small" "n=$mid" "n=$large"
  for k in cache_evicting aggregate_owning; do
    printf '%-26s %8s %8s %8s\n' "$k" "$(rssof "${k}_$small")" "$(rssof "${k}_$mid")" "$(rssof "${k}_$large")"
  done
  for k in cache_hoarding aggregate_leaking; do
    printf '%-26s %8s %8s %8s\n' "$k" "-" "$(rssof "${k}_$mid")" "-"
  done
  echo
fi

# ------------------------------------------------------------------
# 1. THE ANSWER, before any number about memory.
#
# A loop that stopped early, or a map that quietly lost its entries,
# would report a beautifully flat line. Each arm's printed value says
# the work happened AND says what its live set was: the cache holds
# exactly its window, the aggregate exactly its key count, and the
# hoarding twin holds every key it was ever given.
# ------------------------------------------------------------------
answer_is() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" != "$want" ]]; then
    echo "FAIL: $label answered '$got', not $want"
    failed=1
  else
    echo "ok   $label answers $want"
  fi
}
for n in "$small" "$mid" "$large"; do
  answer_is "cache/evicting at n=$n holds its window" "$(outof "cache_evicting_$n")" 256
  answer_is "aggregate/owning at n=$n holds its keys" "$(outof "aggregate_owning_$n")" 64
done
answer_is "cache/hoarding at n=$mid holds everything" "$(outof "cache_hoarding_$mid")" "$mid"
answer_is "aggregate/leaking at n=$mid does the same work" "$(outof "aggregate_leaking_$mid")" 64

# ------------------------------------------------------------------
# 2. THE PLATEAU. Ten times the work, then a hundred times, and the
#    last two land within `band` KiB of each other.
#
#    An absolute band and not a ratio: at these sizes the whole process
#    is a megabyte and change, so a 10% ratio is 140 KiB - inside the
#    allocator's own quantisation - while 256 KiB is a quarter of a
#    chunk and far below any real growth. Measured 2026-08-24 on
#    darwin-aarch64: cache 1392 / 1408 / 1408 KiB, aggregate 1328 /
#    1328 / 1344 KiB. The bands are 0 and 16.
# ------------------------------------------------------------------
band=256
for pair in "cache evicting" "aggregate owning"; do
  set -- $pair
  probe="$1" variant="$2"
  a="$(rssof "${probe}_${variant}_$mid")"
  b="$(rssof "${probe}_${variant}_$large")"
  d=$(( b > a ? b - a : a - b ))
  if (( d > band )); then
    echo "FAIL: $probe/$variant moved ${a} -> ${b} KiB over ten times the work - that is not a plateau"
    failed=1
  else
    echo "ok   $probe/$variant plateaus: ${a} KiB at n=$mid, ${b} KiB at n=$large (${d} KiB apart)"
  fi
done

# ------------------------------------------------------------------
# 3. A FLOOR AND A CEILING, so that "flat" cannot mean "flat at zero"
#    or "flat at 300 MB". 4096 KiB is `check-container-reclaim.sh`'s
#    ceiling, and `check-memory-baseline.sh`'s, against the same
#    quantisation.
#    A FLOOR AS WELL, because a ceiling alone is happiest at zero. It is
#    64 KiB and not the 512 the first draft carried: 512 was a DARWIN
#    MEASUREMENT being used as a portable bound, and a Linux binary is
#    freestanding with no dyld and no libSystem behind it, so its
#    baseline is smaller by an amount nothing here has measured. What a
#    floor can honestly assert is that the instrument returned something
#    rather than nothing - which two stronger checks above already do
#    (a measurement of <= 0 is a hard fail, and the printed ANSWER says
#    the work happened). 64 KiB is below any process that mapped a
#    1 MiB arena and wrote a line to stdout, and far above the zero this
#    exists to refuse.
# ------------------------------------------------------------------
for pair in "cache evicting" "aggregate owning"; do
  set -- $pair
  r="$(rssof "${1}_${2}_$large")"
  if (( r < 64 )); then
    echo "FAIL: $1/$2 measured ${r} KiB at n=$large, under the 64 KiB floor - that is not a running program"
    failed=1
  elif (( r > 4096 )); then
    echo "FAIL: $1/$2 holds ${r} KiB at n=$large, past the 4096 KiB ceiling"
    failed=1
  else
    echo "ok   $1/$2 holds ${r} KiB at n=$large, inside 64..4096 KiB"
  fi
done

# ------------------------------------------------------------------
# 4. THE ABLATED TWINS, which must GROW. This is the half that makes
#    the three flat lines above evidence rather than a claim: the same
#    measurement, on a program one form different, reading a number
#    many times larger.
#
#    Measured 2026-08-24: cache/hoarding 34,368 KiB against 1,408
#    (24x), aggregate/leaking 16,976 KiB against 1,328 (12x). The bar
#    is 5x, far below both and far above any noise.
# ------------------------------------------------------------------
for pair in "cache evicting hoarding" "aggregate owning leaking"; do
  set -- $pair
  probe="$1" live="$2" dead="$3"
  l="$(rssof "${probe}_${live}_$mid")"
  d="$(rssof "${probe}_${dead}_$mid")"
  if (( l <= 0 )); then
    echo "FAIL: $probe/$live has no denominator at n=$mid - that arm did not measure"
    failed=1
  elif (( d < l * 5 )); then
    echo "FAIL: $probe/$dead peaked at ${d} KiB against $probe/$live's ${l} KiB:"
    echo "FAIL: the measurement cannot see the growth it is supposed to refuse"
    failed=1
  else
    echo "ok   $probe/$dead grows to ${d} KiB against $probe/$live's ${l} KiB (past 5x)"
  fi
done

# ------------------------------------------------------------------
# 5. THE NEGATIVE PROBE, measured rather than modelled.
#
# This gate went red on its first run, against the tree that had just
# turned `check-container-reclaim.sh` green - which is the whole reason
# it is a separate script and not a fifth arm of that one.
#
# `mapNeedsGrow` reads `used`, and `used` counts TOMBSTONES. Under the
# cache's insert-and-remove churn `used` therefore reached the load
# factor with a live set that had not moved, and `mapInsert` doubled
# the table for entries that did not exist. The window held 256 keys
# and the table climbed to roughly 524,288 slots:
#
#     cache/evicting  10,048 KiB      (bounded live set, unbounded table)
#     cache/evicting   1,392 KiB      after `mapRehashCap`
#
# A 7.2x reduction, and every OTHER gate in the tree was green across
# it - `check-container-reclaim.sh` included, because it frees its
# containers whole and never removes an entry from one.
#
# The two ablations that make it go red from here were both RUN, not
# modelled, on 2026-08-24:
#
#   `Mem.memMarkArray` made a no-op (`(| sw 32768)` -> `(| sw 0)`), so
#   no block ever carries the array form and neither map hands back
#   what it displaces:
#
#       cache_evicting       2928   17008   157616
#       aggregate_owning     2896   16976   157600
#       cache_hoarding          -   34352        -
#       aggregate_leaking       -   16960        -
#
#   Seven FAIL lines: both plateaus, both ceilings, both ratios. The
#   detail worth keeping is that aggregate/owning lands on 16,976 KiB
#   at n=200,000 - its own ablated twin's number to the kilobyte -
#   which is what "the live arm stopped being different from the dead
#   one" looks like in a measurement. Every ANSWER stayed correct
#   through all of it: 256, 64, 256, 64. This gate is about memory and
#   nothing else can see it.
#
#   `mapRehashCap` reverted to `(* (mapCap m) 2)`, i.e. the tombstone
#   ratchet put back:
#
#       cache_evicting       1904   10048    71088
#       aggregate_owning     1328    1328     1344
#
#   Four FAIL lines, all of them cache's - plateau, ceiling and ratio -
#   and aggregate green throughout, because the aggregate never removes
#   an entry and so never makes a tombstone. That is the discrimination
#   between the two probes rather than a hole in one, and it is why
#   there are two.
# ------------------------------------------------------------------
if (( failed )); then
  echo "check-steady-state: FAILED"
  exit 1
fi
echo "check-steady-state: gate passed"
