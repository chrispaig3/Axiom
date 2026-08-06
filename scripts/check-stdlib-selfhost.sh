#!/usr/bin/env bash
# Run the standard-library test corpus through BOTH compilers and
# compare what the programs actually do: exit status and stdout.
#
# This gate exists because nothing else ran `tests/stdlib/` through
# stage1. `check-self-host.sh` runs `tests/selfhost/` end to end;
# `run-stdlib-tests.sh` runs `tests/stdlib/` through *stage0* only;
# and `check-diagnostics.sh` does compile `tests/stdlib/` with stage1
# but only reads its diagnostics, and explicitly exempts a non-zero
# exit there. So a stage1 miscompile of a stdlib test was invisible to
# every gate in the repository, and five of them were: two programs
# whose output was wrong, one whose IR `llc` rejected, and two more
# found only by running this comparison for the first time.
#
# The comparison is against stage0's answer rather than a checked-in
# expected value on purpose: stage0 is the trusted implementation, and
# `run-stdlib-tests.sh` already pins stage0's own answers, so
# "stage1 agrees with stage0" plus "stage0 is pinned" is the same
# three-way property `check-diagnostics.sh` gets from its goldens.
#
# Usage:
#   scripts/check-stdlib-selfhost.sh          # every case
#   scripts/check-stdlib-selfhost.sh 080      # one case, by name prefix

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
[[ -x "$axiom" ]] || cargo build --release

export AXIOM_STDLIB="$repo_root/stdlib"
filter="${1:-}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

ln -s "$repo_root/stdlib" "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"
ln -s "$repo_root/tests" "$work/tests"

if ! "$axiom" build --input self_host/main.ax --output "$work/stage1" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build stage1" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi

# Programs stage1's PARSER does not accept. These are language surface
# stage1 has not implemented, not miscompiles, and each is recorded in
# docs/self-hosting.md. Listed by name so that a file leaving the list
# is a deliberate edit.
UNPARSED="150-qualified-modules 210-struct-variants 300-effect-handlers 310-effect-unhandled 320-effect-gc-roots"

# Programs stage1 compiles and gets WRONG. Every entry is a real bug
# with a diagnosis; the list is here so the gate can be green while
# they are open, and so that a fix cannot land unnoticed - a name on
# this list that starts agreeing FAILS the gate and must be removed.
#
#   120-pattern-representation  output differs
#   140-function-values         prints closure addresses where stage0
#                               prints values: over-application is
#                               flattened into one direct call
#   160-arena                   arena mark/reset lower correctly now,
#                               but `b - a` comes out a full 1 MiB
#                               chunk instead of 64 - the emitted bump
#                               allocator, not the arena primitives
#   270-nullary-unboxed         `store i64 %x` with %x undefined: a
#                               pattern binder is never bound
#   280-function-application    prints 0 where stage0 prints values: a
#                               non-name application head lowers to the
#                               constant 0
KNOWN_WRONG="120-pattern-representation 140-function-values 160-arena 270-nullary-unboxed 280-function-application"

in_list() { case " $2 " in *" $1 "*) return 0;; *) return 1;; esac; }

passed=0; failed=0; skipped=0; xfail=0
for case_file in tests/stdlib/*.ax; do
  name="$(basename "$case_file" .ax)"
  [[ -n "$filter" && "$name" != "$filter"* ]] && continue

  if in_list "$name" "$UNPARSED"; then
    echo "skip $name (stage1 does not parse it)"
    skipped=$((skipped + 1))
    continue
  fi

  if ! "$axiom" build --input "$case_file" --output "$work/p0" >/dev/null 2>&1; then
    echo "FAIL $name (stage0 could not build it)"
    failed=$((failed + 1))
    continue
  fi
  (cd "$work" && ./p0 >o0.txt 2>&1); e0=$?

  agree=0
  cp "$case_file" "$work/in.ax"
  if (cd "$work" && ./stage1 in.ax >s1.ll 2>/dev/null) \
     && llc -filetype=obj "$work/s1.ll" -o "$work/s1.o" 2>/dev/null \
     && cc "$work/s1.o" -o "$work/p1" -e _main 2>/dev/null; then
    (cd "$work" && ./p1 >o1.txt 2>&1); e1=$?
    if [[ "$e0" == "$e1" ]] && cmp -s "$work/o0.txt" "$work/o1.txt"; then
      agree=1
    fi
  fi

  if in_list "$name" "$KNOWN_WRONG"; then
    if [[ "$agree" == 1 ]]; then
      # A known-wrong case that now agrees is good news the list has
      # to be told about, or the list rots into a lie.
      echo "FAIL $name (listed as known-wrong but now AGREES - remove it from KNOWN_WRONG)"
      failed=$((failed + 1))
    else
      echo "xfail $name (known stage1 bug)"
      xfail=$((xfail + 1))
    fi
    continue
  fi

  if [[ "$agree" == 1 ]]; then
    echo "ok   $name"
    passed=$((passed + 1))
  else
    echo "FAIL $name (stage1 disagrees with stage0)"
    diff "$work/o0.txt" "$work/o1.txt" 2>/dev/null | head -6 | sed 's/^/    /'
    failed=$((failed + 1))
  fi
done

echo
echo "$passed agree, $xfail known-wrong, $skipped unparsed, $failed failed"
[[ "$failed" -eq 0 ]]
