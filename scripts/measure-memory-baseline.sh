#!/usr/bin/env bash
# The measurement that drives the memory-model schedule (§2.2 of
# the roadmap, restored) - and, once reclamation lands, the
# before/after evidence for it.
#
# The probe is a 24x24 Game of Life: one board (~10 KiB of Vec) live
# at any moment, advanced by the EXACT shape §4.1 names as the hard
# case - `(advance (step board) (- n 1))`, a tail call whose
# activation never returns, so a per-activation arena's watermark
# never rewinds. Under the current bump allocator, peak RSS is linear
# in GENERATIONS while live data stays flat: memory tracks total
# allocations, not reachable data. This is the shape of every
# compiler pass, request handler and macro expansion, which is why
# the memory model is the hinge of the roadmap rather than one item
# on a list.
#
# The historical numbers (measured before the game_of_life/ demo was
# removed in 720a0d5, at --opt 2): 10 generations = 5.2 MiB, 80 =
# 31.8 MiB, 2000 = 744 MiB. This script reproduces the methodology;
# the population line printed by the probe pins that the computation
# is real (a glider on a torus returns to its shape every 96 steps,
# so population is a function of N the optimiser cannot fold away
# without doing the work).
#
# TWO variants of the same program run at every count:
#
#   unmanaged - the loop as anyone would write it. Linear RSS,
#     ~16 KiB per generation, forever. The "before".
#   managed - the SAME loop bracketed by the explicit arena
#     primitives, in the shape the adversarial review of the
#     automatic-insertion plan proved sound and measured FLAT
#     (population 5, ~1.4 MiB RSS, 80 through 20,000 generations):
#     mark once before the loop; each iteration steps, copies the
#     new board UP, resets to the mark, copies DOWN from the
#     up-copy, whose bytes sit above the restored pointer and
#     survive because reset moves the pointer and scrubs nothing -
#     and the down-copy's own allocation is the only allocation in
#     the window. `vecWithCapacity` keeps the copies exact, so the
#     down-copy can never reach its source. The "after".
#
# The managed variant is the programmer-written contract that the
# §4.1 automation will eventually infer. Automation itself was
# re-scoped OUT of the first slice by adversarial review (three
# lenses, a judge, five probes): the copyable-set trigger is
# unsound because Int is the universal heap-handle type (String
# unifies with Int BY FIAT, typecheck.ax:180), reset strands
# chunks mapped after the mark (~320 KiB/iteration measured on a
# chunk-crossing loop), and a compiler-inserted copy was tried
# once before and removed for exactly the pointer-blindness reason
# (the ArenaCompact story, the self-hosting record). Those three are
# the automation slice's named prerequisites.
#
# --gate: enforce the managed numbers (this is the P2 slice-1 exit
# criterion made durable): both populations exactly 5 at 2000
# generations, managed max RSS under 4096 KiB (measured ~1.4 MiB;
# the ceiling leaves headroom for the allocator's 1 MiB chunk
# quantization), and the DELIBERATELY-UNSOUND variant (reset with
# no copy - the exact shape the review's p4 probe measured
# corrupting) must NOT print 5, proving the population check
# discriminates the unsoundness this contract exists to prevent.
#
# Usage:
#   scripts/measure-memory-baseline.sh              # 10 80 500 2000
#   scripts/measure-memory-baseline.sh 100 1000     # your counts
#   scripts/measure-memory-baseline.sh --gate       # pass/fail
#   AXIOM=path/to/stage2 scripts/...                # any compiler

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

gate=0
if [[ "${1:-}" == "--gate" ]]; then
  gate=1
  shift
fi

counts=("$@")
if [[ ${#counts[@]} -eq 0 ]]; then
  if [[ "$gate" == 1 ]]; then counts=(2000); else counts=(10 80 500 2000); fi
fi

# Darwin's `time -l` reports bytes; GNU's `time -v` reports kilobytes,
# and so does FreeBSD's `time -l`: `ru_maxrss` is the kernel's unit,
# bytes on Darwin alone, so the divisor is keyed on the kernel rather
# than on which flag answered. Fail rather than skip when neither
# answers: a measurement script that silently measures nothing is how
# the last RSS regression hid.
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

# emit_probe VARIANT N OUTFILE - one Life program, three spellings of
# `advance`: unmanaged (allocate forever), managed (the sound
# explicit mark/copy-up/reset/copy-down), ablated (reset with NO
# copy - the measured-unsound shape the gate's negative rests on).
emit_probe() {
  local variant="$1" n="$2" out="$3"
  local advance
  case "$variant" in
    unmanaged) advance='(:: advance (-> Int Int Int))
(fn (advance b n)
  (if (== n 0) b (advance (step b) (- n 1))))' ;;
    managed) advance='(:: copyBoard (-> Int Int))
(fn (copyBoard src)
  (let ((dst (vecWithCapacity 576)) (mut i 0))
    {
      (while (< i 576)
        { (vecPush dst (vecGet src i)) (set i (+ i 1)) })
      dst
    }))

(:: advance (-> Int Int Int))
(fn (advance b n)
  (let ((m (__axiom_arena_mark)) (mut bb b) (mut nn n))
    {
      (while (> nn 0)
        (let ((b2 (step bb)))
          (let ((up (copyBoard b2)))
            {
              (__axiom_arena_reset m)
              (set bb (copyBoard up))
              (set nn (- nn 1))
            })))
      bb
    }))' ;;
    ablated) advance='(:: advance (-> Int Int Int))
(fn (advance b n)
  (let ((m (__axiom_arena_mark)) (mut bb b) (mut nn n))
    {
      (while (> nn 0)
        {
          (set bb (step bb))
          (__axiom_arena_reset m)
          (set nn (- nn 1))
        })
      bb
    }))' ;;
  esac
  cat > "$out" <<AX
; 24x24 toroidal Game of Life, one board live, advanced $n times.
; Variant: $variant.
(import IO)
(import Vec)

(:: at (-> Int Int Int Int))
(fn (at b x y)
  (vecGet b (+ (* (% (+ y 24) 24) 24) (% (+ x 24) 24))))

(:: neighbors (-> Int Int Int Int))
(fn (neighbors b x y)
  (+ (+ (+ (at b (- x 1) (- y 1)) (at b x (- y 1)))
        (+ (at b (+ x 1) (- y 1)) (at b (- x 1) y)))
     (+ (+ (at b (+ x 1) y) (at b (- x 1) (+ y 1)))
        (+ (at b x (+ y 1)) (at b (+ x 1) (+ y 1))))))

(:: step (-> Int Int))
(fn (step b)
  (let ((nb vecNew) (mut i 0))
    {
      (while (< i 576)
        (let ((x (% i 24)) (y (/ i 24)))
          (let ((n (neighbors b x y)))
            {
              (vecPush nb
                (if (== n 3)
                    1
                    (if (&& (== n 2) (== (vecGet b i) 1)) 1 0)))
              (set i (+ i 1))
            })))
      nb
    }))

$advance

(:: population (-> Int Int))
(fn (population b)
  (let ((mut i 0) (mut p 0))
    {
      (while (< i 576)
        {
          (set p (+ p (vecGet b i)))
          (set i (+ i 1))
        })
      p
    }))

(:: seed Int)
(fn (seed)
  (let ((b vecNew) (mut i 0))
    {
      (while (< i 576) { (vecPush b 0) (set i (+ i 1)) })
      ; a lone glider: population is EXACTLY 5 at every generation,
      ; so the printed population pins that all N steps computed
      ; Life. (A blinker in the glider's path annihilated by
      ; generation 80 once; a dead board pins nothing.)
      (vecSet b (+ (* 1 24) 2) 1)
      (vecSet b (+ (* 2 24) 3) 1)
      (vecSet b (+ (* 3 24) 1) 1)
      (vecSet b (+ (* 3 24) 2) 1)
      (vecSet b (+ (* 3 24) 3) 1)
      b
    }))

(:: main Int)
;@axiom:effect(io)
(fn (main)
  {
    (println (population (advance seed $n)))
    0
  })
AX
}

build_and_measure() {
  local variant="$1" n="$2"
  emit_probe "$variant" "$n" "$work/life_${variant}_$n.ax"
  if ! "$axiom" build --input "$work/life_${variant}_$n.ax" \
       --output "$work/life_${variant}_$n" --opt 2 \
       >"$work/build_${variant}_$n.log" 2>&1; then
    echo "FAIL: $variant probe did not build at n=$n" >&2
    tail -5 "$work/build_${variant}_$n.log" >&2
    return 1
  fi
  pop="$("$work/life_${variant}_$n")"
  rss="$(max_rss_kb "$work/life_${variant}_$n")" || return 1
}

failed=0
for variant in unmanaged managed; do
  echo "== $variant =="
  echo "generations  population  max_rss_kib  kib_per_generation"
  for n in "${counts[@]}"; do
    build_and_measure "$variant" "$n" || { failed=1; continue; }
    echo "$n  $pop  $rss  $(( n > 0 ? rss / n : 0 ))"
    if [[ "$gate" == 1 ]]; then
      if [[ "$pop" != 5 ]]; then
        echo "FAIL: $variant population is $pop, not 5 - the computation is wrong"
        failed=1
      fi
      if [[ "$variant" == managed && "$rss" -gt 4096 ]]; then
        echo "FAIL: managed RSS ${rss} KiB exceeds the 4096 KiB ceiling - reclamation is not happening"
        failed=1
      fi
    fi
  done
  echo
done

if [[ "$gate" == 1 ]]; then
  # The negative: reset with NO copy is the exact unsoundness the
  # explicit contract guards against, and it must be VISIBLE - the
  # adversarial review measured this shape corrupting the board
  # (population 0) because step's vecPush immediately reallocates
  # over the reset region. If the ablated probe prints 5, the
  # population check cannot see the corruption class and the gate
  # is vacuous.
  build_and_measure ablated 80 || failed=1
  if [[ "$pop" == 5 ]]; then
    echo "FAIL: the deliberately-unsound variant printed 5 - the negative is blind"
    failed=1
  else
    echo "negative: ablated variant corrupts as expected (population $pop)"
  fi
  if [[ "$failed" == 0 ]]; then
    echo "check-memory-baseline: gate passed"
  else
    echo "check-memory-baseline: FAILED"
  fi
  exit "$failed"
fi

echo "(one board live at every count: ~10 KiB. The unmanaged column"
echo " growing linearly is the allocator never reclaiming; the managed"
echo " variant is the explicit mark/copy/reset contract §4.1's"
echo " automation will eventually infer - flat, and the P2 slice-1"
echo " exit criterion made durable by --gate.)"
