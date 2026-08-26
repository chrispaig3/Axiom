#!/usr/bin/env bash
# Run the whole gate battery, in parallel where that is sound.
#
#   scripts/run-gates.sh            # everything
#   scripts/run-gates.sh --list     # show the split and exit
#   scripts/run-gates.sh fmt lsp    # only gates whose name contains these
#   AXIOM_GATE_JOBS=4 scripts/run-gates.sh
#
# WHY IT IS FASTER, AND WHY THAT IS NOT A TRICK. Every gate that tests
# the working tree starts by building the compiler from `self_host/`,
# and `gate_build_axc` already knows how not to: point `AXIOM_AXC` at a
# binary whose `.stamp` matches `gate_source_stamp`, and the gate copies
# it instead of spending a build. `scripts/build-shared-axc.sh` writes
# exactly that pair. So this builds ONCE, exports it, and the gates that
# would each have rebuilt the same 60,881 lines stop doing so.
#
# That much was already available serially. What this adds is running
# them CONCURRENTLY, which is only safe because of the line above: with
# `AXIOM_AXC` set, a gate's use of the compiler is a `cp` into its own
# `$work`, so two gates never write the same path. Without it they would
# race to build into the same cache.
#
# WHAT STAYS SERIAL, AND WHY. Four gates read a clock
# (`check-bootstrap`, `check-container-reclaim`, `check-recover`,
# `check-steady-state`) and several more assert a ratio or a memory
# figure. A measurement taken while fifteen compilers share the machine
# is not the measurement the gate means to take - it would fail on a
# loaded laptop and pass on an idle one, which is the definition of a
# flaky gate and worse than a slow one. They run alone, after the rest.
#
# `check-ffi` and `check-bootstrap` also drive `cargo`, which is its own
# parallel build; nesting that inside this one oversubscribes the
# machine and slows BOTH.
#
# The list was WRONG ONCE and the way it was wrong is worth recording:
# `check-type-namespace` asserts that naming the last type in a table
# costs the same as naming the first, and it was left in the parallel
# set because it does not read a clock -- it compares two measurements
# to each other. Under load it reported 1.42x and failed; alone it
# passes. A gate that compares two timings is as load-sensitive as one
# that reads a clock, and the tell is the RATIO, not the clock.
#
# THIS RUNS THE SAME GATES THE SAME WAY. It does not pass them flags,
# skip any, or interpret their output beyond the exit status. A gate
# that fails here fails when run by hand.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Gates whose result depends on having the machine to themselves.
SERIAL_RE='check-(bootstrap|container-reclaim|recover|steady-state|memory-baseline|arena-reset-rate|name-scale|type-namespace|degenerate|stack-depth|concurrent-run|reproducible|ffi|seed-provenance|lsp-selfhost)\.sh$'

jobs="${AXIOM_GATE_JOBS:-}"
if [[ -z "$jobs" ]]; then
  cores="$( (sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4) )"
  jobs=$(( cores - 2 )); (( jobs < 2 )) && jobs=2; (( jobs > 12 )) && jobs=12
fi

all=(); for g in scripts/check-*.sh; do all+=("$g"); done
if (( $# )); then
  filtered=()
  for g in "${all[@]}"; do
    for pat in "$@"; do
      [[ "$pat" == --* ]] && continue
      [[ "$g" == *"$pat"* ]] && { filtered+=("$g"); break; }
    done
  done
  [[ " $* " == *" --list "* ]] || all=("${filtered[@]}")
fi

par=(); ser=()
for g in "${all[@]}"; do
  if [[ "$g" =~ $SERIAL_RE ]]; then ser+=("$g"); else par+=("$g"); fi
done

if [[ " $* " == *" --list "* ]]; then
  echo "parallel (${#par[@]}, $jobs at a time):"; printf '  %s\n' "${par[@]##*/}"
  echo "serial (${#ser[@]}), because they measure or drive cargo:"; printf '  %s\n' "${ser[@]##*/}"
  exit 0
fi

out="$(mktemp -d)"
trap 'rm -rf "$out"' EXIT
started=$SECONDS

# THE SHARED COMPILER. If this fails there is no point running anything:
# every gate would fall back to building its own, serially, and the
# battery would look mysteriously slow rather than broken.
echo "== building the compiler every gate will share =="
if ! ./scripts/build-shared-axc.sh "$out/axc" > "$out/build.log" 2>&1; then
  echo "FAIL: could not build the shared compiler; running gates would each rebuild it" >&2
  tail -20 "$out/build.log" >&2
  exit 1
fi
export AXIOM_AXC="$out/axc"
echo "   shared compiler ready ($(( SECONDS - started ))s)"

run_one() { # run_one <script>
  local g="$1" n; n="$(basename "$g")"
  local t0=$SECONDS
  if ./"$g" > "$out/$n.log" 2>&1; then
    printf '%s %s %s\n' PASS "$(( SECONDS - t0 ))" "$n" >> "$out/RESULTS"
  else
    printf '%s %s %s\n' FAIL "$(( SECONDS - t0 ))" "$n" >> "$out/RESULTS"
  fi
}

# `"${par[@]}"` on an EMPTY array is an unbound-variable error under
# `set -u` on bash 3.2, which the macOS runner ships - so a filter that
# selects only serial gates (`run-gates.sh seed-provenance`) died here
# after building the shared compiler. Guard the expansion, do not drop
# `set -u`.
if (( ${#par[@]} )); then
  echo "== ${#par[@]} gate(s), $jobs at a time =="
  for g in "${par[@]}"; do
    while (( $(jobs -rp | wc -l) >= jobs )); do wait -n 2>/dev/null || sleep 0.3; done
    run_one "$g" &
  done
  wait
fi

if (( ${#ser[@]} )); then
  echo "== ${#ser[@]} gate(s) alone, because they measure =="
  for g in "${ser[@]}"; do run_one "$g"; done
fi

elapsed=$(( SECONDS - started ))
# `grep -c` EXITS 1 when the count is zero, so `|| echo 0` appends a
# SECOND zero and the variable becomes "0\n0" - which `(( ))` then
# refuses with a syntax error, after the gates have already run. Count
# with awk, which exits 0 whatever it counted.
pass="$(awk '/^PASS/{n++} END{print n+0}' "$out/RESULTS" 2>/dev/null)"
fail="$(awk '/^FAIL/{n++} END{print n+0}' "$out/RESULTS" 2>/dev/null)"

echo
sort -k2 -rn "$out/RESULTS" | head -5 | while read -r st sec nm; do
  printf '   %4ss  %s\n' "$sec" "$nm"
done
echo "   (slowest five)"
echo
if (( fail )); then
  echo "FAILED:"
  grep '^FAIL' "$out/RESULTS" | while read -r st sec nm; do
    echo "  $nm (${sec}s)"
    sed 's/^/      /' "$out/$nm.log" | grep -E 'FAIL|error\[' | head -3
  done
  echo
  echo "run-gates: $pass passed, $fail FAILED in ${elapsed}s"
  exit 1
fi
echo "run-gates: all $pass gates passed in ${elapsed}s"
