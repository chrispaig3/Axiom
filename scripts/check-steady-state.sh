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
#   batch      $n records, every seventh malformed, totalled under
#              `stdlib/Fallible.ax`'s skip handler - the plan's batch
#              workload ("record 4,000,001 is malformed, skip it"),
#              with NO container at all: the live set is an
#              accumulator and a handler, and every record must cost
#              nothing. `docs/error-model.md` ERR-REC-7 is the rule;
#              a two-argument operation or a message built per record
#              would each put bytes on every record (32 and 80,
#              measured in the module's header), and this is the arm
#              that would see them.
#
# Neither of the first two shapes appears in
# `check-container-reclaim.sh`, which frees containers whole and never
# removes or overwrites an element; the third has no container to
# free.
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
#   batch/keeping     `fallibleSkip` replaced by a handler that KEEPS a
#                     fresh String per malformed record and skips it
#                     all the same. One form, the same answer, and a
#                     live set that grows by one string in seven
#                     records - so this twin runs at 2,000,000 records
#                     to keep 285,714 strings, the count the other two
#                     keep at 200,000. Measured at 200,000 it held
#                     4,592 KiB against 1,376: real growth, 3.3x, and
#                     under the 5x bar that keeps noise out.
#
# AND THE EXAMPLE PROGRAM, `examples/batch-fallible/batch-fallible.ax`,
# built and run at 100,000 and at 1,000,000 records - the plan's own
# number - with its three printed answers checked against arithmetic
# and its peak RSS held to the same band and ceiling. That is what
# gates the example; nothing else compiles it.
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
    batch)
      # The ablation is the HANDLER and nothing else. Both spellings
      # declare `kept`; the live one never touches it, so the two
      # programs are the same shape and the same answer, and differ in
      # what one of them holds on to.
      local handler='fallibleSkip'
      [[ "$variant" == keeping ]] && handler='(lambda (m) { (vecPush kept (strDup "record malformed")) fallibleSkipped })'
      cat > "$out" <<AX
; $n records, every seventh malformed, totalled under a Fallible
; handler, with no arena reset anywhere. Variant: $variant.
(import IO)
(import Str)
(import Vec)
(import Fallible)

(:: parseRecord (-> Int Int))
(fn (parseRecord i)
  (if (== (% i 7) 0) (fallibleMalformed "record malformed") i))

(:: total (-> Int Int))
(fn (total n)
  (let ((mut i 1) (mut acc 0))
    {
      (while (<= i n)
        (let ((v (parseRecord i)))
          {
            (set acc (if (fallibleIsSkipped v) acc (+ acc v)))
            (set i (+ i 1))
          }))
      acc
    }))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  (let ((kept vecNewRef))
    { (println (cast Int (handle (total $n) (Fallible Alloc Mut) $handler))) 0 }))
AX
      ;;
  esac
}

# What the batch probe must print: the sum of 1..n with every multiple
# of seven left out. Arithmetic, not a golden, so a loop that stopped
# early or a handler that answered 0 instead of the sentinel is a
# different number.
batch_answer() {  # <n>
  local n="$1" m=$(( $1 / 7 ))
  echo $(( n * (n + 1) / 2 - 7 * (m * (m + 1) / 2) ))
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

live_of() {  # <probe> -> the live variant's name
  case "$1" in
    cache) echo evicting ;;
    aggregate) echo owning ;;
    batch) echo skipping ;;
  esac
}
dead_of() {  # <probe> -> the ablated twin's name
  case "$1" in
    cache) echo hoarding ;;
    aggregate) echo leaking ;;
    batch) echo keeping ;;
  esac
}
twin_n() {  # <probe> -> the magnitude its twin runs at
  case "$1" in
    batch) echo "$large" ;;
    *) echo "$mid" ;;
  esac
}

for probe in cache aggregate batch; do
  live="$(live_of "$probe")"
  for n in "$small" "$mid" "$large"; do
    run_probe "$probe" "$live" "$n"
  done
  run_probe "$probe" "$(dead_of "$probe")" "$(twin_n "$probe")"
done

rssof() {
  local v
  v="$(getv "$1_rss")"
  if [[ -z "$v" ]]; then echo 0; else echo "$v"; fi
}
outof() { getv "$1_out"; }

if (( report )); then
  printf '\n%-26s %8s %8s %8s\n' "probe/variant" "n=$small" "n=$mid" "n=$large"
  for k in cache_evicting aggregate_owning batch_skipping; do
    printf '%-26s %8s %8s %8s\n' "$k" "$(rssof "${k}_$small")" "$(rssof "${k}_$mid")" "$(rssof "${k}_$large")"
  done
  for k in cache_hoarding aggregate_leaking; do
    printf '%-26s %8s %8s %8s\n' "$k" "-" "$(rssof "${k}_$mid")" "-"
  done
  printf '%-26s %8s %8s %8s\n' batch_keeping "-" "-" "$(rssof "batch_keeping_$large")"
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
  answer_is "batch/skipping at n=$n skipped every seventh" "$(outof "batch_skipping_$n")" "$(batch_answer "$n")"
done
answer_is "cache/hoarding at n=$mid holds everything" "$(outof "cache_hoarding_$mid")" "$mid"
answer_is "aggregate/leaking at n=$mid does the same work" "$(outof "aggregate_leaking_$mid")" 64
answer_is "batch/keeping at n=$large does the same work" "$(outof "batch_keeping_$large")" "$(batch_answer "$large")"

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
for pair in "cache evicting" "aggregate owning" "batch skipping"; do
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
for pair in "cache evicting" "aggregate owning" "batch skipping"; do
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
for pair in "cache evicting hoarding" "aggregate owning leaking" "batch skipping keeping"; do
  set -- $pair
  probe="$1" live="$2" dead="$3"
  tn="$(twin_n "$probe")"
  l="$(rssof "${probe}_${live}_$tn")"
  d="$(rssof "${probe}_${dead}_$tn")"
  if (( l <= 0 )); then
    echo "FAIL: $probe/$live has no denominator at n=$tn - that arm did not measure"
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
# ------------------------------------------------------------------
# 6. THE EXAMPLE PROGRAM, at the plan's own number.
#
# `examples/batch-fallible/batch-fallible.ax` is the batch probe as a
# program a reader would write: N records read as TEXT, every k-th
# saying `n/a` where a number belongs, the parser performing
# `fallibleMalformed` on the bad byte, and the loop totalling under
# the skip handler with a tally and then under `(fallibleDefault 1)`.
# It allocates a String per record and drops it, which the probe above
# does not, so its flat line is a second claim and not a repeat.
#
# Three answers, by arithmetic: with m = N / k, the skip total is
# N(N+1)/2 - k*m(m+1)/2, the default total is that plus m, and the
# tally is m. Then the plateau, between 100,000 and 1,000,000 records,
# against the same band the probes use.
#
# Measured 2026-08-29 on darwin-aarch64: 1,376 KiB at both sizes, 0 KiB
# apart.
# ------------------------------------------------------------------
example="$repo_root/examples/batch-fallible/batch-fallible.ax"
ex_bin="$work/batch-fallible"
ex_small=100000
ex_large=1000000
if [[ ! -f "$example" ]]; then
  echo "FAIL: $example is missing - the batch example has nothing to gate"
  failed=1
else
  assert_reset_free "$example"
  if ! "$axc" build --input "$example" --output "$ex_bin" --opt 2 >"$work/batch-fallible.log" 2>&1; then
    echo "FAIL: examples/batch-fallible did not build"
    tail -5 "$work/batch-fallible.log" | sed 's/^/    /'
    failed=1
  else
    for n in "$ex_small" "$ex_large"; do
      m=$(( n / 7 ))
      skip=$(( n * (n + 1) / 2 - 7 * (m * (m + 1) / 2) ))
      want="$(printf 'skip total %s\ndefault total %s\nmalformed %s' "$skip" $(( skip + m )) "$m")"
      got="$("$ex_bin" "$n" 7)"
      rc=$?
      if (( rc != 0 )); then
        echo "FAIL: examples/batch-fallible exited $rc at N=$n"
        failed=1
        continue
      fi
      answer_is "examples/batch-fallible at N=$n, k=7" "$got" "$want"
      r="$(max_rss_kb "$ex_bin" "$n" 7)" || { failed=1; continue; }
      if [[ -z "$r" || "$r" -le 0 ]]; then
        echo "FAIL: examples/batch-fallible at N=$n measured no RSS at all ('$r')"
        failed=1
        continue
      fi
      setv "example_$n" "$r"
    done
    a="$(getv "example_$ex_small")"; b="$(getv "example_$ex_large")"
    if [[ -z "$a" || -z "$b" ]]; then
      echo "FAIL: examples/batch-fallible did not measure at both sizes"
      failed=1
    else
      d=$(( b > a ? b - a : a - b ))
      if (( d > band )); then
        echo "FAIL: examples/batch-fallible moved ${a} -> ${b} KiB over ten times the records - that is not a plateau"
        failed=1
      else
        echo "ok   examples/batch-fallible plateaus: ${a} KiB at N=$ex_small, ${b} KiB at N=$ex_large (${d} KiB apart)"
      fi
      if (( b < 64 )); then
        echo "FAIL: examples/batch-fallible measured ${b} KiB at N=$ex_large, under the 64 KiB floor - that is not a running program"
        failed=1
      elif (( b > 4096 )); then
        echo "FAIL: examples/batch-fallible holds ${b} KiB at N=$ex_large, past the 4096 KiB ceiling"
        failed=1
      else
        echo "ok   examples/batch-fallible holds ${b} KiB at N=$ex_large, inside 64..4096 KiB"
      fi
    fi
  fi
fi

if (( failed )); then
  echo "check-steady-state: FAILED"
  exit 1
fi
echo "check-steady-state: gate passed"
