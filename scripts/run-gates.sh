#!/usr/bin/env bash
# Run the whole gate battery, in parallel where that is sound.
#
#   scripts/run-gates.sh                          # everything
#   scripts/run-gates.sh --list                   # show the split and exit
#   scripts/run-gates.sh fmt lsp                  # only gates whose name contains these
#   scripts/run-gates.sh --profile fast           # the smoke set: seconds once the compiler is cached
#   scripts/run-gates.sh --profile expensive      # platform, bootstrap and measurement gates only
#   AXIOM_GATE_JOBS=4 scripts/run-gates.sh
#
# Profiles. `fast` is the edit-and-rerun set: gates that take 15 seconds
# or less and do not need the machine to themselves. CONTRIBUTING.md
# ("Which command runs what") has the timings. It leaves out the two
# corpora (`check-self-host`, `check-stdlib-selfhost`), the diagnostics
# goldens, the formatter, LSP and tools sweeps, and the reclamation
# gates, which cost one to five minutes each. `full`, the default, is
# every gate. `expensive` is the platform, bootstrap and measurement
# tail for scheduled runs and release checks.
#
# One shared compiler. A gate that tests the working tree builds the
# compiler from `self_host/` unless `AXIOM_AXC` names a binary whose
# `.stamp` matches `gate_source_stamp`; then `gate_build_axc` copies it.
# `scripts/build-shared-axc.sh` writes that pair, so this builds once
# and exports it. Each gate then only copies the compiler into its own
# `$work`, so parallel gates never write the same path. Without
# `AXIOM_AXC` they would race to build into the same cache.
#
# What stays serial (SERIAL_RE below): any gate whose verdict depends on
# how much wall time passes inside it. These run one at a time, after
# the parallel pool. Some read a clock
# (`check-bootstrap`, `check-container-reclaim`, `check-recover`,
# `check-steady-state`) or assert a memory figure. Some compare two
# timings as a ratio, which is just as load-sensitive:
# `check-type-namespace` asserts that naming the last type in a table
# costs the same as naming the first.
#
# `check-stack-bound` bisects `ulimit -s` and reads every non-zero exit
# as "out of stack". Stack depth is load-independent, but a failure from
# memory pressure would move the reported floor up.
#
# `check-repl-history` asserts a floor on a race. Its D3 arm forks six
# REPLs that append to one shared file and compact it. An append landing
# between the size re-check and the rename is lost, a documented
# one-syscall window, so it requires 995 of 1200. Scheduling delay under
# load widens that window.
#
# `check-ffi` and `check-bootstrap` also drive `cargo`, which builds in
# parallel itself. Nesting it inside this pool oversubscribes the
# machine.
#
# A gate runs here exactly as it runs by hand: no extra flags, and only
# its exit status is read.
#
# Not run (NOTRUN_RE below). `check-windows-hello.sh` has two halves on
# two machines: `--emit DIR` emits for both Windows targets on any host,
# and `--run DIR` links and executes on a Windows runner. A bare
# invocation is a usage error, so it is excluded and printed as not run,
# with the reason. A gate whose failure means nothing teaches readers to
# skim the FAILED list.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

# Gates a bare invocation cannot run, and the reason printed for them.
# They are reported as not run, never skipped silently.
NOTRUN_RE='check-(windows-hello)\.sh$'
NOTRUN_WHY='needs --emit DIR on any host and --run DIR on a Windows runner; a bare run is a usage error, not a result'

# Gates whose result depends on having the machine to themselves (the
# header gives the rule). A gate that fails under load is worse than a
# slow one: it teaches its reader to re-run instead of reading.
#
# `check-compat` runs `git diff --quiet` over a regenerated baseline and
# rebuilds its own probe compilers. Under parallel load it reports
# spurious API changes that do not reproduce alone.
#
# `check-net` serves thousands of HTTP requests over loopback and
# asserts every byte comes back. Under load the scheduler drains socket
# buffers slowly, and a short read looks the same as lost data.
#
# `check-race` runs `examples/concurrency/pipeline.ax` under
# ThreadSanitizer, which slows it several times over. The example's
# consumer stops after 2 s with no word and its sends wait at most 1 s,
# so under load it can fail with no race reported.
#
# `check-protocol-model` reads the clock: its timed locks and receives
# must answer within [T, T + 800 ms], and its starvation run measures
# waits. Its model also runs four worker processes of its own.
SERIAL_RE='check-(race|protocol-model|bootstrap|container-reclaim|reclaim-soak|recover|steady-state|memory-baseline|arena-reset-rate|name-scale|type-namespace|degenerate|stack-depth|stack-bound|concurrent-run|reproducible|ffi|seed-provenance|lsp-selfhost|compat|net|repl-history)\.sh$'

# The two REPL gates (`check-repl-selfhost`, `check-repl-tui`) stay
# parallel. `repl.ax` gives each REPL a private
# `<tmp>/axiom-repl-<pid>.d`, mode 0700, created with an exclusive
# `makeDir`, so concurrent REPLs never share a file. Serialising them
# would cost the battery two of its slowest gates for nothing.

# `check-terminal-restore.sh` is in neither list. It puts a terminal
# into raw mode and asserts it comes back byte for byte. It is not
# serial: every assertion is a byte equality or an errno, and it drives
# a pty it allocates with `openpty`, so load cannot move its verdict.
# Its only timing is a 30-second deadline for a probe that takes
# milliseconds. It is not NOTRUN: `openpty` needs `/dev/ptmx`, not a
# controlling terminal, so it runs in CI steps with no tty. It never
# touches fd 0/1/2 of whatever invoked it.
#
# If an environment cannot give it a pty, the gate exits non-zero and
# says so. The fix is then to name it in NOTRUN_RE above, a reviewed
# edit.

jobs="${AXIOM_GATE_JOBS:-}"
if [[ -z "$jobs" ]]; then
  cores="$( (sysctl -n hw.ncpu 2>/dev/null || nproc 2>/dev/null || echo 4) )"
  jobs=$(( cores - 2 )); (( jobs < 2 )) && jobs=2; (( jobs > 12 )) && jobs=12
fi
[[ "$jobs" =~ ^[1-9][0-9]*$ ]] || { echo "FAIL: AXIOM_GATE_JOBS must be a positive integer" >&2; exit 2; }

profile=full
list=0
patterns=()
while (( $# )); do
  case "$1" in
    --list) list=1 ;;
    --profile)
      shift
      profile="${1:-}"
      [[ "$profile" == fast || "$profile" == full || "$profile" == expensive ]] || {
        echo "usage: $0 [--list] [--profile fast|full|expensive] [name ...]" >&2; exit 2;
      } ;;
    --*) echo "FAIL: unknown option $1" >&2; exit 2 ;;
    *) patterns+=("$1") ;;
  esac
  shift
done
# Gates that answer in seconds on a warm cache. The corpora and the
# diagnostics goldens are `full`-tier by cost (see Profiles above), and
# a gate that grows slower belongs there too. `check-gate-lib.sh`
# requires every name here to be a script that exists.
FAST_RE='check-(type-pinning|gate-lib|ci-coverage|vec-field-shape|cast-arg-root|tail-position|agent-policy|agent-calls|c-abi|nostd-subset|platform-constants|seed-supply-chain|terminal-restore|version|windows-entry|diverging-tyvar|mir-projection|frontend-parity|trap-statuses|backtrace|test-runner|packages|doc-drift|diagnostic-coverage|examples|repl-highlight|tail-calls|install|release-targets)\.sh$'
EXPENSIVE_RE='check-(bootstrap|seed-lineage|seed-provenance|ddc|cross-targets|embedded|windows-hello|reproducible|memory-baseline|arena-reset-rate|container-reclaim|reclaim-soak|steady-state|recover|name-scale|type-namespace|degenerate|stack-bound|stack-depth)\.sh$'
all=(); omitted=()
for g in scripts/check-*.sh; do
  if [[ "$profile" == fast && ! "$g" =~ $FAST_RE ]] ||
     [[ "$profile" == expensive && ! "$g" =~ $EXPENSIVE_RE ]]; then
    omitted+=("$g"); continue
  fi
  if (( ${#patterns[@]} )); then
    matched=0
    for pat in "${patterns[@]}"; do [[ "$g" == *"$pat"* ]] && matched=1; done
    (( matched )) || { omitted+=("$g"); continue; }
  fi
  all+=("$g")
done
(( ${#all[@]} )) || { echo "FAIL: no gates match the requested selection" >&2; exit 2; }

par=(); ser=(); notrun=()
for g in "${all[@]}"; do
  if [[ "$g" =~ $NOTRUN_RE ]]; then notrun+=("$g")
  elif [[ "$g" =~ $SERIAL_RE ]]; then ser+=("$g")
  else par+=("$g"); fi
done

# Start the parallel pool longest first, ordered by each gate's duration
# in the most recent run that recorded it (a longest-processing-time
# schedule). Otherwise the slowest gates can start last and run on with
# most slots idle. A gate with no history sorts first, as the likeliest
# new long pole. This changes only when a gate starts; the serial list
# keeps its written order.
report_root="${AXIOM_GATE_REPORT_DIR:-$PWD/.axiom-shared/runs}"
gate_history() {  # "<script basename> <seconds>", newest run first, one per gate
  local f
  ls -t "$report_root"/run.*/RESULTS 2>/dev/null | while IFS= read -r f; do
    awk '{ print $3, $2 }' "$f"
  done | awk '!seen[$1]++'
}
if (( ${#par[@]} > 1 )); then
  ordered="$(
    { gate_history | sed 's/^/H /'; printf 'G %s\n' "${par[@]}"; } |
      awk '$1 == "H" { d[$2] = $3; next }
           { n = $2; sub(/.*\//, "", n); print ((n in d) ? d[n] : 999999), $2 }' |
      sort -k1,1nr -k2,2 | cut -d' ' -f2-
  )"
  par=()
  while IFS= read -r g; do [[ -n "$g" ]] && par+=("$g"); done <<< "$ordered"
fi

if (( list )); then
  echo "profile: $profile"
  echo "parallel (${#par[@]}, $jobs at a time):"; (( ${#par[@]} )) && printf '  %s\n' "${par[@]##*/}"
  echo "serial (${#ser[@]}), because they measure or drive cargo:"; (( ${#ser[@]} )) && printf '  %s\n' "${ser[@]##*/}"
  if (( ${#notrun[@]} )); then
    echo "not run here (${#notrun[@]}), $NOTRUN_WHY:"; printf '  %s\n' "${notrun[@]##*/}"
  fi
  echo "not selected: ${#omitted[@]} (use --profile full without filters for the complete local battery)"
  exit 0
fi

source scripts/lib/gate.sh
repo_root="$PWD"
# What every gate's `gate_init` exports, so the stamp computed here is
# the stamp each gate will compute (`gate_config_stamp` records it).
export AXIOM_STDLIB="$repo_root/stdlib"
mkdir -p "$report_root" || exit 1
# Keep the twenty newest earlier runs. Each holds a compiler snapshot
# and every gate's log: evidence for that run, and history for the
# schedule above.
ls -dt "$report_root"/run.* 2>/dev/null | tail -n +21 | while IFS= read -r old; do
  rm -rf "$old"
done
# Keep the eighty most recently used ablated-tree compilers
# (`gate_build_tree`), about two full batteries' worth. Prune them here,
# before any gate starts, never from inside a gate.
tree_cache="${AXIOM_GATE_CACHE:-$repo_root/.axiom-shared/cache}"
if [[ "$tree_cache" != off && -d "$tree_cache" ]]; then
  ls -t "$tree_cache"/tree-* 2>/dev/null | grep -v '\.sha$' | tail -n +81 |
    while IFS= read -r old; do rm -f "$old" "$old.sha"; done
fi
out="$(mktemp -d "$report_root/run.XXXXXX")" || exit 1
: > "$out/RESULTS"
for g in "${all[@]}"; do printf '%s\n' "$g"; done > "$out/SELECTED"
if (( ${#omitted[@]} )); then printf '%s\n' "${omitted[@]}" > "$out/NOT-SELECTED"; fi
if (( ${#notrun[@]} )); then printf '%s\n' "${notrun[@]}" > "$out/NOT-RUN"; fi
echo "gate logs and accounting: $out"
started=$SECONDS
expected=$(( ${#par[@]} + ${#ser[@]} ))
if (( expected == 0 )); then
  echo "NOT RUN: $NOTRUN_WHY" >&2
  exit 2
fi

# Reuse the existing stamped compiler across invocations. Each run gets
# a private snapshot; changing or publishing a shared artifact cannot
# replace an executable underneath gates already running.
cache="${AXIOM_AXC:-$repo_root/.axiom-shared/axc}"
axiom="${AXIOM:-$cache}"
valid=0
if [[ -x "$cache" && -f "$cache.stamp" ]]; then
  [[ "$(cat "$cache.stamp")" == "$(gate_source_stamp)" ]] && valid=1
fi
if (( valid )); then
  echo "== reusing the verified shared compiler =="
else
  echo "== building the compiler every gate will share =="
  if ! ./scripts/build-shared-axc.sh "$cache" > "$out/build.log" 2>&1; then
    echo "FAIL: could not build the shared compiler; see $out/build.log" >&2
    tail -20 "$out/build.log" >&2
    exit 1
  fi
fi
cp "$cache" "$out/axc" && cp "$cache.stamp" "$out/axc.stamp" || exit 1
axiom="$out/axc"
if [[ "$(cat "$out/axc.stamp")" != "$(gate_source_stamp)" ]]; then
  echo "FAIL: shared compiler changed during snapshot, or its inputs changed; retry" >&2
  exit 1
fi
export AXIOM_AXC="$out/axc"
# Gates use the same compiler identity as the published stamp. AXIOM
# selected the builder above; it must not make every consumer miss.
export AXIOM="$AXIOM_AXC"
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

# `"${par[@]}"` on an empty array is an unbound-variable error under
# `set -u` in bash 3.2, which the macOS runner ships. A filter that
# selects only serial gates (`run-gates.sh seed-provenance`) hits it.
# Guard the expansion and keep `set -u`.
if (( ${#par[@]} )); then
  echo "== ${#par[@]} gate(s), $jobs at a time =="
  for g in "${par[@]}"; do
    while (( $(jobs -rp | wc -l) >= jobs )); do wait -n 2>/dev/null || sleep 0.1; done
    run_one "$g" &
  done
  wait
fi

if (( ${#ser[@]} )); then
  echo "== ${#ser[@]} gate(s) alone, because they measure =="
  for g in "${ser[@]}"; do run_one "$g"; done
fi

elapsed=$(( SECONDS - started ))
completed="$(wc -l < "$out/RESULTS" | tr -d ' ')"
if (( completed != expected )); then
  echo "FAIL: expected $expected gate results, received $completed; see $out" >&2
  exit 1
fi
# Collect skipped sections. A gate's exit status says whether what it
# checked held, not whether it checked everything. Gates print a line
# starting `SKIP` (or `skip`) for a section the host cannot exercise:
# no `git`, no `ulimit -s`, an `llc` without `--stack-usage-file`, a
# REPL case the model does not cover. Printing them with the verdict
# keeps "passed" from reading as "passed in full".
: > "$out/SKIPS"
for g in ${par[@]+"${par[@]}"} ${ser[@]+"${ser[@]}"}; do
  [[ -n "$g" ]] || continue
  n="$(basename "$g")"
  grep -E '^[[:space:]]*(note[[:space:]]+)?(SKIP|skip)([:[:space:]]|$)' "$out/$n.log" 2>/dev/null |
    sed "s|^[[:space:]]*|$n: |" >> "$out/SKIPS"
done
skipped="$(wc -l < "$out/SKIPS" | tr -d ' ')"
printf 'profile=%s\nselected=%s\nexecuted=%s\nnot_selected=%s\nnot_run=%s\nskipped_sections=%s\nelapsed_seconds=%s\n' \
  "$profile" "${#all[@]}" "$completed" "${#omitted[@]}" "${#notrun[@]}" "$skipped" "$elapsed" > "$out/SUMMARY"
echo "not selected: ${#omitted[@]}; not run here: ${#notrun[@]}; logs: $out"
# Count with awk, not `grep -c`: `grep -c` exits 1 on a zero count, so
# `|| echo 0` would give "0\n0", which `(( ))` rejects after the gates
# have run.
pass="$(awk '/^PASS/{n++} END{print n+0}' "$out/RESULTS" 2>/dev/null)"
fail="$(awk '/^FAIL/{n++} END{print n+0}' "$out/RESULTS" 2>/dev/null)"

echo
if (( ${#notrun[@]} )); then
  echo "NOT RUN HERE (${#notrun[@]}), $NOTRUN_WHY:"
  printf '  %s\n' "${notrun[@]##*/}"
  echo
fi
if (( skipped )); then
  echo "SECTIONS NOT EXERCISED ON THIS HOST ($skipped), from the gates' own SKIP lines:"
  sed 's/^/  /' "$out/SKIPS" | head -20
  (( skipped > 20 )) && echo "  ... and $((skipped - 20)) more in $out/SKIPS"
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
echo "run-gates: all $pass gates passed in ${elapsed}s$( (( skipped )) && echo ", $skipped section(s) skipped on this host" )"
