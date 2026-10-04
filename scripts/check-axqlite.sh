#!/usr/bin/env bash
# AXQLite's gate: storage, recovery, concurrency and AXQL behaviour.
#
# WHAT IT RUNS. Every `tests/axqlite/NNN-*.ax` is built from inside
# `tests/axqlite`, so a harness module beside the tests is found, and
# run in an empty directory of its own, so the database files one test
# makes can never be seen by another. Its first argument is the path of
# `tests/axqlite`, where it reads any `.test` script or fixture it
# needs. Its stdout must equal the `.out` beside it, and its exit status
# the `.exit` beside it (0 when there is none).
#
# A test that runs longer than the limit fails rather than hanging the
# gate: a lock that is never released looks exactly like that.
#
# Usage:
#   scripts/check-axqlite.sh            # every test
#   scripts/check-axqlite.sh 2          # tests whose name starts with 2
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

prefix="${1:-}"
limit="${AXIOM_AXQLITE_LIMIT:-300}"
tests="$repo_root/tests/axqlite"
ran=0; passed=0; failed=0

run_case() {
  local name="$1" flag="$2" label="$3"
  ran=$((ran + 1))
  local dir="$work/$label"
  mkdir -p "$dir/run"
  if ! ( cd "$tests" && "$axiom" build $flag --input "$name.ax" --output "$dir/prog" ) >"$dir/build.log" 2>&1; then
    echo "FAIL $label: did not build"
    sed 's/^/    /' "$dir/build.log" | head -8
    failed=$((failed + 1))
    return
  fi
  want_exit=0
  [[ -f "$tests/$name.exit" ]] && want_exit="$(tr -d '[:space:]' < "$tests/$name.exit")"
  ( cd "$dir/run" && perl -e 'alarm shift; exec @ARGV' "$limit" "$dir/prog" "$tests" ) \
    >"$dir/out" 2>"$dir/err"
  rc=$?
  if [[ ! -f "$tests/$name.out" ]]; then
    echo "FAIL $label: no $name.out beside it"
    failed=$((failed + 1))
  elif ! cmp -s "$dir/out" "$tests/$name.out"; then
    echo "FAIL $label: stdout differs from $name.out"
    diff "$tests/$name.out" "$dir/out" | head -12 | sed 's/^/    /'
    sed 's/^/    stderr: /' "$dir/err" | head -4
    failed=$((failed + 1))
  elif [[ "$rc" != "$want_exit" ]]; then
    echo "FAIL $label: exit $rc, wanted $want_exit"
    sed 's/^/    stderr: /' "$dir/err" | head -4
    failed=$((failed + 1))
  else
    echo "ok   $label"
    passed=$((passed + 1))
  fi
}

for src in "$tests"/[0-9][0-9][0-9]-*.ax; do
  [[ -e "$src" ]] || continue
  name="$(basename "$src" .ax)"
  [[ -n "$prefix" && "$name" != "$prefix"* ]] && continue
  run_case "$name" "" "$name"
  # Explicit process isolation must also hold when thread lowering is enabled.
  if [[ -f "$tests/$name.threads" ]]; then
    run_case "$name" "--threads" "$name-threads"
  fi
done

# Calling the thunk in the parent removes the isolation guarantee. The
# same probe must then be refused by the region checker, before execution.
if [[ -z "$prefix" || 206-crash-isolation == "$prefix"* ]]; then
  control="$work/isolation-control"
  mkdir -p "$control"
  cp "$tests"/Store*.ax "$control/"
  cp "$repo_root/tests/axqlite/206-crash-isolation.ax" "$control/"
  sed 's/(__proc_join (__proc_spawn work 0))/(work 0)/' \
    "$repo_root/tests/axqlite/StoreCrash.ax" > "$control/StoreCrash.ax"
  ran=$((ran + 1))
  if "$axiom" --diagnostic-format=ai check "$control/206-crash-isolation.ax" >"$control/check.log" 2>&1; then
    echo "FAIL isolation-control: a parent-side callback passed the lifetime check"
    failed=$((failed + 1))
  elif rg -q '^E AX3060 ' "$control/check.log"; then
    echo "ok   isolation-control: removing the process boundary is AX3060"
    passed=$((passed + 1))
  else
    echo "FAIL isolation-control: refusal was not AX3060"
    head -8 "$control/check.log" | sed 's/^/    /'
    failed=$((failed + 1))
  fi
fi

# A run that found nothing to run is not a pass.
if (( ran == 0 )); then
  echo "FAIL: no test matched '${prefix}' in tests/axqlite"
  exit 1
fi

echo
if (( failed > 0 )); then
  echo "check-axqlite: $failed of $ran tests failed"
  exit 1
fi
echo "check-axqlite: all $ran tests passed"
