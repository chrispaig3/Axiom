#!/usr/bin/env bash
# How peak memory grows with work, and with --gate, whether the explicit
# arena contract reclaims it.
#
# The probe is a 24x24 Game of Life: one board (about 10 KiB of Vec)
# live at a time, advanced by `(advance (step board) (- n 1))`. That is a
# tail call whose activation never returns, so a per-activation arena's
# watermark never rewinds. Under the bump allocator, peak RSS grows with
# the generation count while live data stays flat. Compiler passes,
# request handlers and macro expansions share this shape.
#
# The board holds a lone glider, so the printed population is 5 at every
# generation. It pins that every step really ran, and the optimiser
# can't fold it away without doing the work.
#
# Two variants run at every count:
#
#   unmanaged  The loop as anyone would write it. The tail call's
#              boundary releases each old board (MM-LIFE-2c event 4,
#              MM-LIFE-2m), so RSS stays flat with no arena at all.
#   managed    The same loop bracketed by the explicit arena primitives.
#              Mark once before the loop. Each iteration steps, copies
#              the new board up, resets to the mark, then copies it down
#              from the up-copy. The up-copy's bytes sit above the
#              restored pointer and survive, because reset moves the
#              pointer and scrubs nothing. The down-copy's allocation is
#              the only one in the window, and `vecWithCapacity` keeps
#              the copies exact, so it never reaches its source. RSS
#              stays flat. A board is a counted value, and a reset hands
#              back blocks without asking their counts, so nothing that
#              crosses the reset is held by a counted binding: the board
#              lives in a raw cell below the mark, and the up-copy as a
#              raw word, so no release touches reclaimed memory.
#
# The managed variant is the contract an automatic arena pass would have
# to infer.
#
# --gate checks the contract. Both populations must be exactly 5 at 2000
# generations, and managed peak RSS must stay under 4096 KiB, which
# leaves room for the allocator's 1 MiB chunks. An ablated variant
# (reset with no copy) must not exit cleanly printing 5, which shows the
# check can see the unsoundness the contract prevents.
#
# Either of two outcomes passes the negative: the probe dies at the read
# with no output, because `vecGet` traps out of range (`__indexTrap`,
# status 77), or it prints a wrong population. Only a clean exit
# printing 5 fails.
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

# `ru_maxrss` is bytes on Darwin and kilobytes elsewhere, FreeBSD
# included, though FreeBSD's `time` also takes `-l`. So the divisor is
# keyed on the kernel, not on which flag works. Fail rather than skip
# when neither works: a measurement that silently measures nothing hides
# a regression.
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

# emit_probe VARIANT N OUTFILE: one Life program with three versions of
# `advance`. unmanaged allocates forever; managed marks, copies up,
# resets and copies down; ablated resets with no copy, the unsound shape
# the gate's negative uses.
emit_probe() {
  local variant="$1" n="$2" out="$3"
  local advance
  case "$variant" in
    unmanaged) advance='(:: advance (-> (Vec Int) Int (Vec Int)))
(fn (advance b n)
  (if (== n 0) b (advance (step b) (- n 1))))' ;;
    managed) advance='(:: copyBoard (-> (Vec Int) (Vec Int)))
(fn (copyBoard src)
  (let ((dst (vecWithCapacity 576)) (mut i 0))
    {
      (while (< i 576)
        { (vecPush dst (vecGet src i)) (set i (+ i 1)) })
      dst
    }))

(:: advance (-> (Vec Int) Int (Vec Int)))
;@axiom:effect(unsafe)
(fn (advance b n)
  (let ((cell (memAlloc 8)) (m (__axiom_arena_mark)) (mut nn n))
    {
      (memSetWord cell 0 b)
      (while (> nn 0)
        (let ((up (cast Int (copyBoard (step (memGetWordVec cell 0))))))
          {
            (__axiom_arena_reset m)
            (memSetWord cell 0 (copyBoard (cast (Vec Int) up)))
            (set nn (- nn 1))
          }))
      (memGetWordVec cell 0)
    }))' ;;
    ablated) advance='(:: advance (-> (Vec Int) Int (Vec Int)))
;@axiom:effect(unsafe)
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
(import Mem)

(:: at (-> (Vec Int) Int Int Int))
(fn (at b x y)
  (vecGet b (+ (* (% (+ y 24) 24) 24) (% (+ x 24) 24))))

(:: neighbors (-> (Vec Int) Int Int Int))
(fn (neighbors b x y)
  (+ (+ (+ (at b (- x 1) (- y 1)) (at b x (- y 1)))
        (+ (at b (+ x 1) (- y 1)) (at b (- x 1) y)))
     (+ (+ (at b (+ x 1) y) (at b (- x 1) (+ y 1)))
        (+ (at b x (+ y 1)) (at b (+ x 1) (+ y 1))))))

(:: step (-> (Vec Int) (Vec Int)))
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

(:: population (-> (Vec Int) Int))
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

(:: seed (Vec Int))
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
  # The negative: reset with no copy is the unsoundness the contract
  # guards against, and the check must see it. Step's `vecPush`
  # reallocates over the reset region at once and corrupts the board.
  # If the ablated probe prints 5, the population check is blind and
  # the gate is vacuous.
  # Run it directly: `build_and_measure` treats a non-zero exit as a
  # failure, and here it means the ablation was caught. The probe is
  # about the answer, so RSS isn't measured.
  emit_probe ablated 80 "$work/life_ablated_80.ax"
  if ! "$axiom" build --input "$work/life_ablated_80.ax" \
       --output "$work/life_ablated_80" --opt 2 \
       >"$work/build_ablated_80.log" 2>&1; then
    echo "FAIL: the ablated probe did not build - the negative never ran"
    tail -5 "$work/build_ablated_80.log" >&2
    failed=1
  else
    ab_out="$("$work/life_ablated_80" 2>/dev/null)"; ab_rc=$?
    if [[ "$ab_rc" == 0 && "$ab_out" == 5 ]]; then
      echo "FAIL: the deliberately-unsound variant ran clean and printed 5 - the negative is blind"
      failed=1
    elif [[ "$ab_rc" != 0 ]]; then
      echo "negative: ablated variant is REFUSED at the read (exit $ab_rc), not carried into the answer"
    else
      echo "negative: ablated variant corrupts as expected (population ${ab_out:-<none>})"
    fi
  fi
  if [[ "$failed" == 0 ]]; then
    echo "check-memory-baseline: gate passed"
  else
    echo "check-memory-baseline: FAILED"
  fi
  exit "$failed"
fi

echo "(one board live at every count: ~10 KiB. The unmanaged column"
echo " is flat because each dead board is released at the tail call;"
echo " the managed variant is the explicit mark/copy/reset contract -"
echo " flat too, and the P2 slice-1 exit criterion made durable by"
echo " --gate.)"
