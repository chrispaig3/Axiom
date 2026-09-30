#!/usr/bin/env bash
# The cryptography suite's gate: known answers, negative cases, and the
# proof that each of those tests can fail.
#
# WHAT IT RUNS. Every `tests/crypto/NNN-*.ax` is a program that reads
# vector files from the directory named by its first argument, checks
# every case, and prints one line per suite: `<suite> ok`, or a `FAIL`
# line per failing case and `<suite> FAILED`. Its stdout must equal the
# `.out` beside it. The per-suite case counts go to stderr and are
# printed here, so the log says how many cases each suite ran; a suite
# that ran none prints `FAILED`, never `ok` (tests/crypto/Kat.ax).
#
# THE ABLATION. A known-answer test that cannot fail is the defect this
# repository keeps finding (a sweep that reads no files, a check under
# a stray `set -e`). So every test is run a second time against a COPY
# of the vectors in which the last hex digit of the last field of every
# case line has been changed. A test that still prints only `ok` lines
# there is reported as vacuous and fails the gate. A test that reads
# no vector file at all - one that checks built-in cases - says so with
# a `.novectors` marker beside it and is exempt from this half.
#
# LEVELS. `CRYPTO_OPTS` lists the optimisation levels each test is
# built at, default "1" (the compiler's default). The scheduled run
# sets "0 1 3": the constant-time kernels and the arithmetic they rely
# on must give the same answers whatever the optimiser did.
#
# Usage:
#   scripts/check-crypto.sh            # every test
#   scripts/check-crypto.sh 100-sha2   # tests whose name starts with this
set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

filter="${1:-}"
opts="${CRYPTO_OPTS:-1}"
vectors="$repo_root/tests/crypto/vectors"
failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

# The corrupted copy the ablation half runs against.
spoiled="$work/spoiled-vectors"
mkdir -p "$spoiled"
for f in "$vectors"/*.txt; do
  [[ -e "$f" ]] || continue
  python3 - "$f" "$spoiled/$(basename "$f")" <<'PY'
import sys
src, dst = sys.argv[1], sys.argv[2]
out = []
for line in open(src, encoding="utf-8").read().split("\n"):
    if line and not line.startswith("#"):
        fields = line.split(" ")
        last = fields[-1]
        if last and last != "-":
            c = last[-1]
            flip = {"0": "1"}.get(c.lower(), "0")
            fields[-1] = last[:-1] + flip
        line = " ".join(fields)
    out.append(line)
open(dst, "w", encoding="utf-8").write("\n".join(out))
PY
done

shopt -s nullglob
tests=("$repo_root"/tests/crypto/[0-9]*.ax)
ran=0
for t in "${tests[@]}"; do
  name="$(basename "$t" .ax)"
  [[ -n "$filter" && "$name" != "$filter"* ]] && continue
  golden="${t%.ax}.out"
  if [[ ! -f "$golden" ]]; then
    bad "$name: no $name.out beside it"
    continue
  fi
  ran=$((ran + 1))
  for lvl in $opts; do
    bin="$work/$name.O$lvl"
    if ! (cd "$repo_root/tests/crypto" && "$axc" --diagnostic-format=ai build --input "$name.ax" --output "$bin" --opt "$lvl") >"$work/$name.build.log" 2>&1; then
      bad "$name --opt $lvl: does not build"
      sed 's/^/    /' "$work/$name.build.log" | head -20
      continue
    fi
    rc=0
    gate_timeout 900 "$bin" "$vectors" >"$work/$name.O$lvl.out" 2>"$work/$name.O$lvl.err" || rc=$?
    sed 's/^/    /' "$work/$name.O$lvl.err" | grep -E ': [0-9]+ passed, [0-9]+ failed$' || true
    if [[ $rc -eq 0 ]] && diff -u "$golden" "$work/$name.O$lvl.out" >"$work/$name.diff"; then
      ok "$name --opt $lvl"
    else
      bad "$name --opt $lvl: exit $rc"
      sed 's/^/    /' "$work/$name.diff" | head -40
      sed 's/^/    /' "$work/$name.O$lvl.err" | grep -v -E ': [0-9]+ passed, [0-9]+ failed$' | head -10 || true
    fi
  done
  # The ablation, at the first level only: it asks whether the test can
  # fail, which does not depend on the level.
  if [[ -f "${t%.ax}.novectors" ]]; then
    continue
  fi
  first="${opts%% *}"
  bin="$work/$name.O$first"
  [[ -x "$bin" ]] || continue
  rc=0
  gate_timeout 900 "$bin" "$spoiled" >"$work/$name.spoiled.out" 2>/dev/null || rc=$?
  if [[ $rc -ne 0 ]] && grep -q ' FAILED$' "$work/$name.spoiled.out"; then
    ok "$name fails on corrupted vectors ($(grep -c ' FAILED$' "$work/$name.spoiled.out") suite(s) caught it)"
  else
    bad "$name still passes with every expected value corrupted: it cannot fail"
  fi
done

if [[ $ran -eq 0 ]]; then
  bad "no test matched '${filter}'"
fi

echo
if [[ $failed -eq 0 ]]; then
  echo "check-crypto: all $checks checks passed"
else
  echo "check-crypto: $failed of $((checks + failed)) checks failed"
  exit 1
fi
