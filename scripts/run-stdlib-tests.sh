#!/usr/bin/env bash
# Compile, run, and check every standard-library golden case in
# tests/stdlib.
#
# Each case is `NAME.ax` with an expected stdout in `NAME.out` and an
# optional expected exit status in `NAME.exit` (default 0). This is the
# same set of cases `cargo test -p axiom-cli --test stdlib_golden`
# covers; the script exists so that a contributor can run one case, see
# the actual diff, and keep the compiled binary around to poke at -
# none of which `cargo test` makes easy.
#
# Usage:
#   scripts/run-stdlib-tests.sh            # every case
#   scripts/run-stdlib-tests.sh 030-str    # one case, by name prefix

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "building the compiler first (no binary at $axiom)" >&2
  cargo build --release
fi

export AXIOM_STDLIB="$repo_root/stdlib"

filter="${1:-}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

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

  set +e
  actual_out="$(cd "$case_dir" && "./$name" 2>/dev/null)"
  actual_exit=$?
  set -e

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
