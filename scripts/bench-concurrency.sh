#!/usr/bin/env bash
# What the concurrency primitives cost on this machine: spawn and join
# in both lowerings, a task's round trip and its answer's copy, the
# mutex with and without contention, a channel's throughput and its
# uncontended send and receive, and the spread of a task's latency.
# `docs/assurance/scorecard.md` quotes the figures.
#
#   scripts/bench-concurrency.sh            # REPS runs of each, best and median
#   REPS=9 OPT=2 scripts/bench-concurrency.sh
#
# THE PROGRAM IS tests/litmus/conc-bench.ax. Each mode times its own
# work with the clock `sysTimeoutMicros` reads, so process start-up and
# the build are outside every figure, and checks its own answer: a
# wrong answer prints WRONG, and this script stops rather than report a
# time for work that was not done.
#
# WHAT THE FIGURES ARE. The best of REPS runs is the cost without
# interference, and the median says how much interference there was.
# They are measurements on one machine at one moment, not bounds, and
# the latency percentiles in particular are the scheduler's as much as
# the runtime's. This is not a gate: it asserts nothing but that every
# answer was right, and exits 0 when it was.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
# The compiler `gate_init` resolved ($AXIOM, $AXIOM_AXC, or the installed
# one), as `bench-par.sh` uses it: a measurement builds no compiler of its
# own, and so is not one of the gates `check-gate-lib.sh` counts.
axc="$axiom"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

REPS="${REPS:-7}"
opt="${OPT:-2}"
prog="$repo_root/tests/litmus/conc-bench.ax"

for lowering in processes threads; do
  flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
  (cd "$repo_root" && "$axc" build ${flags[@]+"${flags[@]}"} --opt "$opt" --input "$prog" --output "$work/cb-$lowering") \
    > "$work/cb-$lowering.build" 2>&1 || { echo "error: conc-bench did not build ($lowering):"; sed 's/^/  /' "$work/cb-$lowering.build" | head -8; exit 1; }
done

# run <lowering> <mode args...>: REPS runs; prints "best median" of the
# microseconds field, or stops on a wrong answer.
run() {
  local lowering="$1"; shift
  local r out us=()
  for ((r = 0; r < REPS; r++)); do
    out="$(gate_timeout 300 "$work/cb-$lowering" "$@" 2>&1)" || { echo "error: conc-bench $* ($lowering) failed: $out" >&2; exit 1; }
    case "$out" in *WRONG*) echo "error: conc-bench $* ($lowering) answered wrong: $out" >&2; exit 1 ;; esac
    us+=("$(printf '%s\n' "$out" | awk '{print $NF}')")
  done
  printf '%s\n' "${us[@]}" | sort -n | awk '{a[NR]=$1} END {print a[1], a[int((NR+1)/2)]}'
}

per() {  # per <microseconds> <count> <unit scale> -> the cost of one, in the unit
  awk -v t="$1" -v n="$2" -v k="$3" 'BEGIN { printf "%.2f", t * k / n }'
}

echo "== concurrency costs: best and median of $REPS runs, --opt $opt, $(uname -sm) =="
echo

N_SPAWN=400
for lowering in processes threads; do
  read -r best med < <(run "$lowering" spawn "$N_SPAWN")
  echo "spawn+join, $lowering: $(per "$best" $((N_SPAWN * 2)) 1) us per binding (median $(per "$med" $((N_SPAWN * 2)) 1))"
done

N_TASKS=2000
for bytes in 64 4096 65536; do
  n=$N_TASKS; (( bytes == 65536 )) && n=400
  read -r best med < <(run processes tasks "$n" 8 "$bytes")
  mbps="$(awk -v t="$best" -v n="$n" -v b="$bytes" 'BEGIN { printf "%.1f", n * b / t }')"
  echo "task round trip, width 8, $bytes-byte answers: $(per "$best" "$n" 1) us per task (median $(per "$med" "$n" 1)); answers at $mbps MB/s"
done

N_MUTEX=200000
for lowering in processes threads; do
  read -r best med < <(run "$lowering" mutex "$N_MUTEX" 1)
  echo "mutex lock+unlock, uncontended, $lowering: $(per "$best" "$N_MUTEX" 1000) ns (median $(per "$med" "$N_MUTEX" 1000))"
  read -r best med < <(run "$lowering" mutex "$N_MUTEX" 4)
  echo "mutex lock+unlock, 4 bindings contending, $lowering: $(per "$best" $((N_MUTEX * 4)) 1000) ns per operation (median $(per "$med" $((N_MUTEX * 4)) 1000))"
done

N_CHAN=200000
for lowering in processes threads; do
  read -r best med < <(run "$lowering" chan "$N_CHAN")
  echo "channel, 1 sender to 1 receiver, capacity 64, $lowering: $(per "$best" "$N_CHAN" 1000) ns per word (median $(per "$med" "$N_CHAN" 1000))"
  read -r best med < <(run "$lowering" chan1 "$N_CHAN")
  echo "channel, uncontended send and receive, $lowering: $(per "$best" "$N_CHAN" 1000) ns per word (median $(per "$med" "$N_CHAN" 1000))"
done

out="$(gate_timeout 300 "$work/cb-processes" latency 500 2>&1)" || { echo "error: latency failed: $out" >&2; exit 1; }
echo "one-task pool round trip, 500 in a row: $(printf '%s' "$out" | sed 's/^latency 500 //') (microseconds)"
