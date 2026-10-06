#!/usr/bin/env bash
#
# Measures how much stack the compiler needs to check the largest Axiom
# program in the tree, `self_host/main.ax`, by bisection.
#
# The frames-per-entry hazard: recursion that costs one stack frame per
# table entry or per source byte. It crashes with SIGSEGV inside whatever
# is being compiled, far from the walk that caused it. The self and mutual
# tail-call rewrites (`scripts/check-tail-calls.sh`) remove most of it,
# including a tail call in a `let` body. Three shapes still cost a frame
# per iteration: a combining step that runs after the call, a mutual call
# across arities, and a call handing over an owned temporary
# (docs/memory-model.md MM-EXEC-6c).
#
# This gate turns that whole class into one number that regresses
# visibly, for a handful of sub-second runs. It asserts:
#   * The minimum stack at which `check self_host/main.ax` succeeds is
#     under a ceiling. It is printed either way, so growth shows in the
#     log before it fails.
#   * At half that minimum the process dies by a signal, not just a
#     non-zero exit. A run that failed for an unrelated reason would
#     otherwise look like one that ran out of stack, and any number would
#     pass.
#   * The successful run prints `OK`. A compiler that exits 0 having done
#     nothing needs very little stack.
#
# The figure comes from exit statuses, not from a golden file, so there
# is nothing to re-bless.
#
# `;@axiom:restrict(no-recursion)` is the static half
# (docs/restricted-profile.md, scripts/check-restrictions.sh). A
# declaration under it reaches no cycle in the call graph, so
# `scripts/check-stack-bound.sh` can compute its stack need from frame
# sizes. The compiler recurses and claims no such restriction, so this
# gate measures it instead.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

# The ceiling is loose. It still catches a need that grows with program
# size, and leaves room for other platforms' frame layouts and other
# toolchains' spilling. A tight ceiling would fail on host differences.
ceiling_kib=1024
subject="self_host/main.ax"

# Measure a compiler built from the current sources. `$AXIOM` is only the
# builder, as in the other `*-selfhost` gates, so pointing it at an old
# binary does not change what is measured.
if ! gate_build_tree "$axiom" "$repo_root" "$AXIOM_STDLIB" "$work/stage1" \
       --opt 1 >"$work/build.log" 2>&1; then
  echo "FAIL: could not build a compiler from self_host/" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi
axiom="$work/stage1"

# One run at a given stack limit. Answers "ok", "signal", or "other:<rc>".
run_at() {
  local kib="$1" rc out
  out="$( (ulimit -s "$kib" 2>/dev/null || exit 200; "$axiom" check "$subject") 2>"$work/err" )"
  rc=$?
  if [[ "$rc" -eq 200 ]]; then echo "unsettable"; return; fi
  if [[ "$rc" -eq 0 ]]; then
    # Prove the work happened: a silent exit 0 needs no stack at all.
    if [[ "$out" == *OK* ]]; then echo "ok"; else echo "other:0-no-OK"; fi
    return
  fi
  if [[ "$rc" -ge 128 ]]; then echo "signal:$rc"; return; fi
  echo "other:$rc"
}

# Confirm the top of the range works before bisecting downward, so a
# broken compiler reports as broken rather than as needing lots of stack.
top=$((ceiling_kib * 4))
r="$(run_at "$top")"
if [[ "$r" == "unsettable" ]]; then
  echo 'SKIP: this shell cannot set ulimit -s (nothing to measure)'
  exit 0
fi
if [[ "$r" != "ok" ]]; then
  echo "FAIL: check $subject does not succeed even with ${top} KiB of stack: $r" >&2
  cat "$work/err" >&2
  exit 1
fi

# Bisect the smallest multiple of 8 KiB that still succeeds.
lo=8
hi=$top
while (( hi - lo > 8 )); do
  mid=$(( ((lo + hi) / 2 / 8) * 8 ))
  if [[ "$(run_at "$mid")" == "ok" ]]; then hi=$mid; else lo=$mid; fi
done
need=$hi

echo "check $subject needs ${need} KiB of stack (ceiling ${ceiling_kib} KiB)"

if (( need > ceiling_kib )); then
  echo "FAIL: that is over the ceiling. Something now recurses per program" >&2
  echo "      element - see the frames-per-entry note at the top of this file," >&2
  echo '      and prefer a while loop over a let-bound tail call.' >&2
  exit 1
fi

# The other half: at half the requirement it must die by a signal.
# Without this, the bisection above could report anything and still pass.
half=$(( need / 2 ))
(( half < 8 )) && half=8
r="$(run_at "$half")"
case "$r" in
  signal:*) echo "and dies by ${r#signal:} at ${half} KiB, as it must" ;;
  ok)
    echo "FAIL: it also succeeded at ${half} KiB, so the ${need} KiB figure is not" >&2
    echo "      a stack requirement and this gate measured nothing" >&2
    exit 1 ;;
  *)
    echo "FAIL: at ${half} KiB it answered '$r' rather than dying by a signal, so" >&2
    echo "      the failure above is not the stack running out" >&2
    exit 1 ;;
esac

echo "check-stack-depth: gate passed"
