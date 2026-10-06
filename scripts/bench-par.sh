#!/usr/bin/env bash
# What the parallel pool's `parMapWords` and `parRunAll` cost on this
# machine, as a baseline for changes to the pool's accounting.
#
#   scripts/bench-par.sh                # best of 20 runs at --opt 2
#   REPS=9 OPT=0 scripts/bench-par.sh
#
# Three workloads, each a whole process that prints a checksum. A
# program that prints anything else isn't running the workload, and its
# timing means nothing:
#
#   spawn   4000 trivial thunks at width 8 (fork/join round trips)
#   alloc   2000 thunks each summing a fresh 2000-word Vec (join
#           under allocation)
#   runall  800 true(1) at width 8, end to end through parRunAll
#
# The method is `bench-datastructures.sh`'s (see `web/bench/README.md`).
# Hyperfine times whole processes, the figure is the best of REPS runs
# because noise only ever adds time, and the startup of a program that
# does nothing is subtracted. Work sizes are fixed in the programs. The
# scaling study across widths 1 to 8 is the second half of
# `scripts/bench-concurrency.sh`.
#
# To compare two builds, interleave: time the old and new binaries
# round-robin, one repetition each, and keep the minima. Separate blocks
# run under different load. `web/bench/run-bench.sh` shows the shape.
#
# This is not a gate. It prints figures, sets no threshold, and exits 0
# when every checksum answers.
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

REPS="${REPS:-20}"
opt="${OPT:-2}"

command -v "${HYPERFINE:-hyperfine}" > /dev/null || { echo "error: hyperfine not on PATH - timings are measured with it" >&2; exit 1; }

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
axiom="$AXIOM_AXC"

cat > "$work/b_empty.ax" <<'AX'
(:: main Int)
(fn (main)
  0)
AX

cat > "$work/b_spawn.ax" <<'AX'
(import IO)
(import Par)
(import Vec)

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  (let ((out (parMapWords (lambda (i) i) 4000 8)))
    (let ((s (vecSum out)))
      {
        (println "{s}")
        0
      })))
AX

cat > "$work/b_alloc.ax" <<'AX'
(import IO)
(import Par)
(import Vec)

(:: childSum (-> Int Int))
(fn (childSum n)
  (let ((v vecNew))
    {
      (for i in 0..n
        (vecPush v i))
      (vecSum v)
    }))

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  (let ((out (parMapWords (lambda (i) (childSum 2000)) 2000 8)))
    (let ((s (vecSum out)))
      {
        (println "{s}")
        0
      })))
AX

cat > "$work/b_runall.ax" <<'AX'
(import IO)
(import Par)
(import Str)
(import Vec)

(:: main Int)
;@axiom:effect(io)
;@axiom:effect(spawn)
;@axiom:effect(block)
(fn (main)
  (let ((cmds vecNew))
    {
      (for k in 0..800
        (let ((one vecNew))
          {
            (vecPushStr one "true")
            (vecPushVec cmds one)
          }))
      (let ((codes (parRunAll cmds 8)))
        (let ((n (vecLen codes)))
          (let ((s (vecSum codes)))
            {
              (println "{n} {s}")
              0
            })))
    }))
AX

echo "building..."
for b in empty spawn alloc runall; do
  "$axiom" build --opt "$opt" --input "$work/b_$b.ax" --output "$work/ax_$b" \
    >"$work/build.log" 2>&1 || {
    echo "error: could not build the $b benchmark" >&2
    tail -20 "$work/build.log" >&2; exit 1
  }
done

# The expected checksums. A case function stands in for an associative
# array, which macOS's bash 3.2 lacks.
expect_of() {
  case "$1" in
    spawn)  printf '7998000' ;;
    alloc)  printf '3998000000' ;;
    runall) printf '800 0' ;;
  esac
}
for b in spawn alloc runall; do
  got="$("$work/ax_$b")"
  want="$(expect_of "$b")"
  if [[ "$got" != "$want" ]]; then
    echo "error: $b printed '$got', expected '$want' - not the workload" >&2
    exit 1
  fi
done
echo "checksums answer."

time_best() {
  # `--shell none`, unlike the shared harness: hyperfine's shell
  # calibration is noisier than the startup probe it would correct.
  # The commands are bare paths, so no shell feature is lost.
  HF_BIN="${HYPERFINE:-hyperfine}" python3 - "$REPS" "$@" <<'PY'
import json, os, shlex, subprocess, sys, tempfile
reps = int(sys.argv[1])
cmd = shlex.join(sys.argv[2:])
with tempfile.NamedTemporaryFile(suffix=".json", delete=False) as f:
    path = f.name
subprocess.run([os.environ["HF_BIN"], "--warmup", "0", "--runs", str(reps),
                "--style", "none", "--shell", "none",
                "--export-json", path, cmd],
               stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, check=True)
print(f"{min(json.load(open(path))['results'][0]['times']):.6f}")
os.unlink(path)
PY
}

startup="$(time_best "$work/ax_empty")"

printf '\n%-9s %11s  %s\n' workload best-of-"$REPS" checksum
printf '%s\n' "----------------------------------------"
for b in spawn alloc runall; do
  raw="$(time_best "$work/ax_$b")"
  t="$(python3 -c "print(f'{max($raw - $startup, 1e-6):.4f}')")"
  printf '%-9s %10ss  %s\n' "$b" "$t" "$(expect_of "$b")"
done
printf '\nstartup %ss subtracted; axiom --opt %s, best of %s\n' "$startup" "$opt" "$REPS"
