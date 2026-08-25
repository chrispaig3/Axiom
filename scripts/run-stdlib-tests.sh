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
#
# EXACT UP TO THE BACKTRACE, and no further. A trapping program now
# prints `axiom: backtrace (most recent call first)` and then one
# `  at <function>` line per stack frame. The frames are NOT comparable
# here: which of them survive depends on what the optimiser inlined,
# which depends on the LLVM version, and the three CI legs do not run
# the same one. Pinning them in a golden would be a fixture that fails
# on a runner upgrade while the compiler is correct.
#
# So the comparison stops AT the marker line, which the golden itself
# carries - `sed '/^axiom: backtrace/q'`. That keeps every byte the
# fixture was written to pin, and adds one: that a trace was emitted at
# all. The trace's CONTENTS are gated by `scripts/check-backtrace.sh`,
# which controls the optimisation level and the program shape and can
# therefore pin them exactly.
# This is the
# same set of cases the deleted Rust test suite ran as `stdlib_golden`
# covers; the script exists so that a contributor can run one case, see
# the actual diff, and keep the compiled binary around to poke at -
# none of which a unit-test harness makes easy.
#
# IT COMPILES WITH THE COMPILER THIS TREE BUILDS, and until 2026-08-24
# it did not: it took `$axiom`, which in CI is the one
# `bootstrap-from-seed.sh` builds from the COMMITTED SEED. That made it
# the only runner in the repository testing a compiler nobody ships,
# and it had a hard consequence rather than a philosophical one - a
# fixture exercising anything the seed does not know cannot compile
# here at all, whatever the compiler in the tree thinks. Three
# recovery-point cases arrived and this script reported
# `undefined variable __axiom_recover` against a tree where the
# feature works and `check-stdlib-selfhost.sh` runs the same goldens
# green.
#
# The alternative was to advance the seed, and `scripts/reseed.sh`
# states the rule that rules it out: the seed moves when it can no
# longer compile `self_host/`, "and it is the only routine reason to
# move it. Advancing it otherwise is optional and costs 8.4 MB of
# generated text in the diff". The seed compiles `self_host/` fine.
# What was wrong was this script's choice of compiler, and the shared
# artifact makes the right one free - `gate_build_axc` is the same one
# every other gate here uses, and in CI it is a cache hit.
#
# Usage:
#   scripts/run-stdlib-tests.sh            # every case
#   scripts/run-stdlib-tests.sh 030-str    # every case whose name starts with 030-str

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

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

  if ! build_log="$("$axc" build --input "$repo_root/$case_file" \
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
    sed '/^axiom: backtrace/q' "$case_dir/$name.stderr" > "$case_dir/$name.stderr.cmp"
    if [[ "$(cat "$case_dir/$name.stderr.cmp")" != "$(cat "$expected_err")" ]]; then
      echo "FAIL $name (stderr)"
      diff "$expected_err" "$case_dir/$name.stderr.cmp" | sed 's/^/    /' || true
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
