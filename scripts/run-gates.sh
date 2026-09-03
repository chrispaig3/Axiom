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
# THIS RUNS THE SAME GATES THE SAME WAY. It does not pass them flags
# or interpret their output beyond the exit status. A gate that fails
# here fails when run by hand.
#
# ONE GATE CANNOT BE RUN THAT WAY, and it is NAMED rather than skipped
# quietly. `check-windows-hello.sh` is two halves on two machines - it
# emits for windows-x86_64 on any host under `--emit DIR` and links and
# EXECUTES on a Windows runner under `--run DIR` - so a bare invocation
# is a usage error, not a result. Globbed in and run bare it failed in
# 0s on every local run, which made this battery permanently red and
# taught its reader to skim the FAILED list instead of reading it. That
# is the cost being paid here: a gate whose failure means nothing
# devalues the ones whose failure means something.
#
# So it is listed below, excluded from the run, and PRINTED as not run
# with the reason. Not run and silent would be the worse defect of the
# two - the whole point of naming it is that the reader can see the
# battery is not the whole story.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Gates a bare invocation cannot run at all, with the reason each is
# printed with. Excluded from the run and reported, never silent.
NOTRUN_RE='check-(windows-hello)\.sh$'
NOTRUN_WHY='needs --emit DIR on any host and --run DIR on a Windows runner; a bare run is a usage error, not a result'

# Gates whose result depends on having the machine to themselves.
# `check-compat` joined on 2026-09-01, and it is the first member added
# for a reason that is neither a clock nor a ratio. It shells out to
# `git diff --quiet` over a regenerated baseline and rebuilds its own
# probe compilers; under six-way parallelism it failed three times in
# one evening - "a public name leaves the API", "adding a public name
# was not reported ADDED" - and passed alone every time, three for
# three. A gate that fails for load is worse than a slow one: it
# teaches its reader to re-run rather than to read, which is the habit
# `run-gates.sh`'s own header exists to prevent.
#
# `check-net` joined on 2026-09-03, and it is the clearest case yet of
# the rule the header states two paragraphs up - the tell is the RATIO,
# not the clock. It serves 20,400 real HTTP requests over loopback and
# asserts that every byte sent comes back; under six-way parallelism it
# reported "varied-size run echoed 5983 of 10000" and failed. Run alone
# immediately afterwards, on the same tree and the same compiler, it
# passed. Nothing about the server is timing-dependent by design; what
# is load-dependent is a socket's buffers and the scheduler's
# willingness to drain them while fifteen compilers are running, and a
# short read is indistinguishable at the assertion from a server that
# lost data.
SERIAL_RE='check-(bootstrap|container-reclaim|recover|steady-state|memory-baseline|arena-reset-rate|name-scale|type-namespace|degenerate|stack-depth|concurrent-run|reproducible|ffi|seed-provenance|lsp-selfhost|compat|net)\.sh$'

# THE TWO REPL GATES ARE NOT HERE, and they were nearly added on
# 2026-08-31 on the strength of a comment. `check-repl-selfhost.sh`'s
# header said every REPL on the machine writes /tmp/axiom-repl-1
# because `fmtIntStr` answers "1" above 3, so two REPLs at once corrupt
# each other - and `check-repl-tui.sh` starts several. Both halves of
# that were fixed before it was written down as live: `repl.ax` uses
# `decStr` (distinctness, 2026-08-08) and a private
# `<tmp>/axiom-repl-<pid>.d` at mode 0700 created with an exclusive
# `sysMkdir` (predictability, 2026-08-23), and its own comment says so.
# MEASURED 2026-08-31 before removing the entry: six `axiom repl`
# processes run at once each answered their own expression correctly
# (101, 202, 303, 404, 505, 606) and left nothing in /tmp. Serialising
# on a stale comment costs the battery two of its slowest gates for
# nothing, which is why the measurement came first.

# A NOTE ON ONE GATE THAT IS DELIBERATELY *NOT* IN EITHER LIST ABOVE,
# because it looks like it should be in both. `check-terminal-restore.sh`
# drives a TERMINAL: it puts one into raw mode and asserts it comes back
# byte for byte. Neither the serial list nor the not-run list is right
# for it, and the reasons are worth stating where the lists are.
#
#   Not SERIAL. That list is for gates whose RESULT depends on having
#   the machine to themselves - they time something, or measure memory,
#   or drive cargo. This one measures nothing: every assertion is a byte
#   equality or an errno, and neither moves under load. The terminal it
#   drives is a pty it allocates for itself with `openpty`, so there is
#   no shared device to contend for and no other gate it can disturb.
#   The only load-sensitive thing in it is the driver's 30-second
#   deadline for a probe that finishes in milliseconds.
#
#   Not NOTRUN. It needs a pty, but it does NOT need a controlling
#   terminal - `openpty` is an operation on `/dev/ptmx`, which a CI step
#   with no tty has - so it runs here, in the Linux container, and on
#   every runner. It never touches fd 0/1/2 of whatever invoked it.
#
# If a future environment genuinely cannot give it a pty, the gate exits
# NON-ZERO saying so rather than passing quietly, and the deliberate fix
# is to name it in NOTRUN_RE above - a visible edit in a reviewed file,
# which is where that decision belongs.

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

par=(); ser=(); notrun=()
for g in "${all[@]}"; do
  if [[ "$g" =~ $NOTRUN_RE ]]; then notrun+=("$g")
  elif [[ "$g" =~ $SERIAL_RE ]]; then ser+=("$g")
  else par+=("$g"); fi
done

if [[ " $* " == *" --list "* ]]; then
  echo "parallel (${#par[@]}, $jobs at a time):"; printf '  %s\n' "${par[@]##*/}"
  echo "serial (${#ser[@]}), because they measure or drive cargo:"; printf '  %s\n' "${ser[@]##*/}"
  if (( ${#notrun[@]} )); then
    echo "not run here (${#notrun[@]}), $NOTRUN_WHY:"; printf '  %s\n' "${notrun[@]##*/}"
  fi
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
if (( ${#notrun[@]} )); then
  echo "NOT RUN HERE (${#notrun[@]}), $NOTRUN_WHY:"
  printf '  %s\n' "${notrun[@]##*/}"
  echo
fi
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
