#!/usr/bin/env bash
# Baselines for the parallel pool: what `parMapWords` and `parRunAll`
# cost on this machine BEFORE the per-slot accounting rework, so the
# rework has something to beat besides its own aspirations.
#
# Three workloads, each its own whole process printing a checksum -
# a program that prints anything else is not running this workload,
# and its timing means nothing beside these figures:
#
#   spawn   4000 trivial thunks at width 8 (fork/join round trips)
#   alloc   2000 thunks each summing a fresh 2000-word Vec (join
#           under allocation - the path per-slot accounting touches)
#   runall  800 true(1) at width 8, end to end through parRunAll
#
# METHODOLOGY, inherited from `bench-datastructures.sh` (and see
# `web/bench/README.md`): whole processes timed by hyperfine, best
# of REPS (the distribution is one-sided), process startup measured
# separately with a program that does nothing and subtracted. Work
# sizes are fixed in the programs, not argv - these are baselines,
# not a scaling study.
#
# COMPARING AGAINST THESE FIGURES has one rule: interleave. Time the
# old and new binaries round-robin, one repetition each in turn, and
# keep the minima - blocks compare two different load conditions,
# and a background anything landing on one block is a gap that was
# never there. `web/bench/run-bench.sh` shows the shape.
#
# BASELINES (best of 20, startup subtracted, --opt 2). Measured
# 2026-09-25 on Apple M1, 8 cores, trunk 139382b1:
#
#   spawn   0.2916s
#   alloc   0.1447s
#   runall  0.3922s
#
# Beat these with the per-slot rework, interleaved per the rule
# above, or explain in the commit why the accounting costs what it
# costs. A rework that cannot show its margin against this table
# has not finished.
#
# This is not a gate: it prints figures and exits 0 when every
# checksum answers. It has no verdict column because there is no
# criterion yet - the per-slot rework's margin is unknown until it
# is measured, and a threshold written before that is a wish.
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
      (for i 0 n
        (vecPush v i))
      (vecSum v)
    }))

(:: main Int)
;@axiom:effect(io)
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
(fn (main)
  (let ((cmds vecNew))
    {
      (for k 0 800
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

# The checksums. A program that prints anything else is not running
# the workload its timing would be filed under. (A case function, not
# an associative array: macOS ships bash 3.2, which has none.)
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
  # `--shell none`: hyperfine's own shell calibration is noisier than
  # the startup probe it would time (one pass read 46us for an
  # execve that costs 2ms). The commands here are bare paths, so no
  # shell feature is lost. This is a deliberate deviation from the
  # shared harness, for the reason hyperfine's own warning gives.
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
