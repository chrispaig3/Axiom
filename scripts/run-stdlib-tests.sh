#!/usr/bin/env bash
# Compile, run, and check every standard-library golden case in
# tests/stdlib.
#
# Each case is `NAME.ax` with an expected stdout in `NAME.out`, an
# optional expected exit status in `NAME.exit` (default 0), and an
# optional expected STDERR in `NAME.err`. Stderr is discarded unless
# that third file exists, because almost every case writes none and a
# runner that compared it everywhere would turn a stray warning into
# fifty failures. Where the file IS present the comparison is exact -
# it exists for the cases whose whole subject is what they said on the
# way out, like a program that dies of an allocation it could not make.
# This is the
# same set of cases the deleted Rust test suite ran as `stdlib_golden`
# covers; the script exists so that a contributor can run one case, see
# the actual diff, and keep the compiled binary around to poke at -
# none of which a unit-test harness makes easy. It is now the only
# runner for them.
#
# Usage:
#   scripts/run-stdlib-tests.sh            # every case
#   scripts/run-stdlib-tests.sh 030-str    # every case whose name starts with 030-str

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

filter="${1:-}"

passed=0
failed=0

for case_file in tests/stdlib/*.ax; do
  name="$(basename "$case_file" .ax)"
  if [[ -n "$filter" && "$name" != "$filter"* ]]; then
    continue
  fi

  expected_out="tests/stdlib/$name.out"
  expected_exit=0
  if [[ -f "tests/stdlib/$name.exit" ]]; then
    expected_exit="$(tr -d '[:space:]' < "tests/stdlib/$name.exit")"
  fi

  # Each case gets its own directory: some of them create files, and a
  # leftover from a previous case would make a failure look like a pass.
  case_dir="$work/$name"
  mkdir -p "$case_dir"

  if ! build_log="$("$axiom" build --input "$repo_root/$case_file" \
      --output "$case_dir/$name" 2>&1)"; then
    echo "FAIL $name (build)"
    echo "$build_log" | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi

  expected_err="tests/stdlib/$name.err"

  set +e
  if [[ -f "$expected_err" ]]; then
    actual_out="$(cd "$case_dir" && "./$name" 2>"$case_dir/$name.stderr")"
  else
    actual_out="$(cd "$case_dir" && "./$name" 2>/dev/null)"
  fi
  actual_exit=$?
  set -e

  if [[ -f "$expected_err" ]]; then
    if [[ "$(cat "$case_dir/$name.stderr")" != "$(cat "$expected_err")" ]]; then
      echo "FAIL $name (stderr)"
      diff "$expected_err" "$case_dir/$name.stderr" | sed 's/^/    /' || true
      failed=$((failed + 1))
      continue
    fi
  fi

  if [[ "$actual_out" != "$(cat "$expected_out")" ]]; then
    echo "FAIL $name (stdout)"
    diff <(cat "$expected_out") <(printf '%s\n' "$actual_out") | sed 's/^/    /' || true
    failed=$((failed + 1))
    continue
  fi

  if [[ "$actual_exit" != "$expected_exit" ]]; then
    echo "FAIL $name (exit: expected $expected_exit, got $actual_exit)"
    failed=$((failed + 1))
    continue
  fi

  echo "ok   $name"
  passed=$((passed + 1))
done

echo
echo "$passed passed, $failed failed"
[[ "$failed" -eq 0 ]]
