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

for src in "$tests"/[0-9][0-9][0-9]-*.ax; do
  [[ -e "$src" ]] || continue
  name="$(basename "$src" .ax)"
  [[ -n "$prefix" && "$name" != "$prefix"* ]] && continue
  ran=$((ran + 1))
  dir="$work/$name"
  mkdir -p "$dir/run"
  if ! ( cd "$tests" && "$axiom" build --input "$name.ax" --output "$dir/prog" ) >"$dir/build.log" 2>&1; then
    echo "FAIL $name: did not build"
    sed 's/^/    /' "$dir/build.log" | head -8
    failed=$((failed + 1))
    continue
  fi
  want_exit=0
  [[ -f "$tests/$name.exit" ]] && want_exit="$(tr -d '[:space:]' < "$tests/$name.exit")"
  ( cd "$dir/run" && perl -e 'alarm shift; exec @ARGV' "$limit" "$dir/prog" "$tests" ) \
    >"$dir/out" 2>"$dir/err"
  rc=$?
  if [[ ! -f "$tests/$name.out" ]]; then
    echo "FAIL $name: no $name.out beside it"
    failed=$((failed + 1))
  elif ! cmp -s "$dir/out" "$tests/$name.out"; then
    echo "FAIL $name: stdout differs from $name.out"
    diff "$tests/$name.out" "$dir/out" | head -12 | sed 's/^/    /'
    sed 's/^/    stderr: /' "$dir/err" | head -4
    failed=$((failed + 1))
  elif [[ "$rc" != "$want_exit" ]]; then
    echo "FAIL $name: exit $rc, wanted $want_exit"
    sed 's/^/    stderr: /' "$dir/err" | head -4
    failed=$((failed + 1))
  else
    echo "ok   $name"
    passed=$((passed + 1))
  fi
done

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
