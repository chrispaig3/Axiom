#!/usr/bin/env bash
# MM-EXEC-6b, pinned defect: a `match` on a direct call loses tail
# position when the payload is a reference.
#
# This gate asserts a defect. `tests/tailpos/crash.ax` makes its
# recursive call in tail position, as the whole of its `Some` arm, and
# still overflows the stack. `codegen.ax` sends a match on a direct call
# to a pair-returning function through `emitMatch` instead of
# `emitMatchTail` when the payload is a reference, so no frame is reused.
#
# The fix belongs in `emitMatchTail`, the region MIR slice 2 rewrites,
# and two changes to one tail-position function invite a second defect,
# so the defect is pinned here instead. A fix turns section 2 red:
# delete this gate and record the fix in CHANGELOG.md.
#
# Two controls, each one change away from `crash.ax`, must pass:
#
#   boxed.ax    binds the scrutinee with `let` before the match
#   intpay.ax   uses an `Int` payload instead of a `String`
#
# Either change alone runs in constant stack, so the defect needs both a
# reference payload and a direct-call scrutinee. If a control fails,
# `crash.ax` no longer isolates MM-EXEC-6b.
#
# A default stack needs 2,000,000 iterations to crash. Under
# `ulimit -s 512`, as in `check-stack-depth.sh`, 20,000 is enough: the
# overflow comes between 5,000 and 10,000, and both controls still pass.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

gate_build_axc axc

# A shell that cannot lower its stack limit measures nothing, so skip
# and say so.
if ! ( ulimit -s 512 ) 2>/dev/null; then
  echo "SKIP: this shell cannot set ulimit -s (nothing to measure)"
  exit 0
fi

run_at_512() {
  local bin="$1" rc
  # When the child dies on a signal, the outer shell prints its own
  # "Segmentation fault" line. The crash is expected here, so silence the
  # shell's stderr as well as the child's.
  { ( ulimit -s 512; "$bin" >/dev/null 2>&1 ); } 2>/dev/null
  rc=$?
  echo "$rc"
}

echo "--- 1. the three programs compile ---"
for n in crash boxed intpay; do
  if "$axc" build --input "tests/tailpos/$n.ax" --output "$work/$n" > "$work/$n.build" 2>&1; then
    ok "$n.ax compiles"
  else
    bad "$n.ax does not compile"
    sed 's/^/     /' "$work/$n.build" | head -10
  fi
done

echo
echo "--- 2. the defect, and the two controls that localise it ---"
if [[ -x "$work/crash" ]]; then
  st="$(run_at_512 "$work/crash")"
  if [[ "$st" == 139 ]]; then
    ok "crash.ax still overflows at 20,000 under a 512 KiB stack (exit $st) - MM-EXEC-6b is unfixed"
  elif [[ "$st" == 0 ]]; then
    bad "crash.ax now EXITS 0. If MM-EXEC-6b has been fixed, delete this gate and say so in the changelog; if it has not, this fixture has stopped reproducing it"
  else
    bad "crash.ax exited $st, which is neither the overflow (139) nor success (0)"
  fi
fi
for n in boxed intpay; do
  [[ -x "$work/$n" ]] || continue
  st="$(run_at_512 "$work/$n")"
  if [[ "$st" == 0 ]]; then
    ok "$n.ax runs in constant stack (exit 0) - the control holds"
  else
    bad "$n.ax exited $st; a control that crashes means crash.ax is not evidence for MM-EXEC-6b"
  fi
done

echo
echo "--- 3. the controls answer, rather than merely exiting 0 ---"
# A program that printed nothing would also exit 0, so each control
# must print the iteration count it reached.
for n in boxed intpay; do
  [[ -x "$work/$n" ]] || continue
  out="$( ( ulimit -s 512; "$work/$n" ) 2>/dev/null )"
  if [[ "$out" == "20000" ]]; then
    ok "$n.ax reached 20000 iterations"
  else
    bad "$n.ax printed '$out', not 20000 - it exited 0 without doing the work"
  fi
done

echo
if (( failed > 0 )); then
  echo "check-tail-position: $failed of $checks checks failed"
  exit 1
fi
echo "check-tail-position: $checks checks - MM-EXEC-6b reproduces at 20,000"
echo "                     iterations under a 512 KiB stack, and both controls"
echo "                     pass there, so the defect is the intersection of a"
echo "                     reference payload and a direct-call scrutinee."
