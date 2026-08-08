#!/usr/bin/env bash
# The measurement that drives the memory-model schedule (§2.2 of
# docs/v1-roadmap.md, restored) - and, once reclamation lands, the
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
# Not a gate ON PURPOSE, yet: there is no number to enforce until
# copy-at-boundary lands. When it does, the P2 exit criterion is this
# table's last row turning constant, and THEN a gate pins it.
#
# Usage:
#   scripts/measure-memory-baseline.sh              # 10 80 500 2000
#   scripts/measure-memory-baseline.sh 100 1000     # your counts
#   AXIOM=path/to/stage2 scripts/...                # any compiler

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "building the compiler first (no binary at $axiom)" >&2
  cargo build --release
fi

export AXIOM_STDLIB="$repo_root/stdlib"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

counts=("$@")
if [[ ${#counts[@]} -eq 0 ]]; then
  counts=(10 80 500 2000)
fi

# Darwin's `time -l` reports bytes; GNU's `time -v` reports kilobytes.
# Fail rather than skip when neither answers: a measurement script
# that silently measures nothing is how the last RSS regression hid.
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

echo "generations  population  max_rss_kib  kib_per_generation"
for n in "${counts[@]}"; do
  cat > "$work/life_$n.ax" <<AX
; 24x24 toroidal Game of Life, one board live, advanced $n times by
; the tail-call shape docs/v1-roadmap.md §4.1 names as the hard case.
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

; A fresh board from the old one - the allocation §4.1's tail call
; never reclaims.
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

(:: advance (-> Int Int Int))
(fn (advance b n)
  (if (== n 0) b (advance (step b) (- n 1))))

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
      ; a lone glider: on an empty torus it travels forever and its
      ; population is EXACTLY 5 at every generation - so the printed
      ; population pins that all N steps really computed Life, at
      ; every N, with one constant. (The first seed here had a
      ; blinker in the glider's path; they annihilated by generation
      ; 80 and a dead board pins nothing.)
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
    (printlnInt (population (advance seed $n)))
    0
  })
AX
  if ! "$axiom" build --input "$work/life_$n.ax" --output "$work/life_$n" --opt 2 \
       >"$work/build_$n.log" 2>&1; then
    echo "FAIL: probe did not build at n=$n" >&2
    tail -5 "$work/build_$n.log" >&2
    exit 1
  fi
  pop="$("$work/life_$n")"
  rss="$(max_rss_kb "$work/life_$n")" || exit 1
  echo "$n  $pop  $rss  $(( n > 0 ? rss / n : 0 ))"
done

echo
echo "(one board live at every count: ~10 KiB. RSS linear in the first"
echo " column is the allocator never reclaiming; the §4.1 copy-at-"
echo " boundary work exits when the last column goes to ~0.)"
