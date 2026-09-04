#!/usr/bin/env bash
# MM-EXEC-6b, PINNED: a `match` on a direct call loses tail position
# when the payload is a reference.
#
# THIS GATE ASSERTS A DEFECT, which is unusual here and deliberate.
# `tests/tailpos/crash.ax` is written in tail position - the recursive
# call is the whole of its `Some` arm - and it overflows the stack
# anyway, because `codegen.ax` routes a match whose scrutinee is a
# direct call to a pair-returning function through `emitMatch` rather
# than `emitMatchTail` when the payload is a reference. So the frame is
# not reused and the stack grows once per iteration.
#
# WHY PIN IT RATHER THAN FIX IT. The fix is in `emitMatchTail`, which is
# the same region MIR slice 2 is rewriting, and two changes fighting
# over that function is how a subtle tail-position bug acquires a second
# one. This file converts "there is a reproducible segfault in the
# compiler" into "there is one, and here is exactly how much we know
# about it" - and it will go RED the day someone fixes it, which is the
# point: a defect's own demonstration is an assertion, the same rule
# `tests/docs/verify-doc-code.py`'s `refused` marker applies to a block
# a document quotes as broken.
#
# WHAT MAKES IT NOT A TEST THAT DEEP RECURSION OVERFLOWS. Two controls,
# each one change away from the crashing program and each required to
# PASS:
#
#   boxed.ax    the scrutinee `let`-bound before the match
#   intpay.ax   an `Int` payload instead of a `String`
#
# Either change alone makes the same program iterate in constant stack.
# So the defect is the INTERSECTION - a reference payload AND a
# direct-call scrutinee - and if a control ever fails, `crash.ax` has
# stopped being evidence for the thing it names.
#
# WHY IT IS FAST. On the default stack the crash needs 2,000,000
# iterations, which is why this was never gated. Under `ulimit -s 512`
# it fails at 20,000 and both controls still pass there - measured, and
# the threshold sits between 5,000 and 10,000. `check-stack-depth.sh`
# established the reduced-ulimit idiom in this battery.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

gate_build_axc axc

# A shell that cannot lower its own stack limit can measure nothing
# here. Say so rather than passing.
if ! ( ulimit -s 512 ) 2>/dev/null; then
  echo "SKIP: this shell cannot set ulimit -s (nothing to measure)"
  exit 0
fi

run_at_512() {
  local bin="$1" rc
  # The outer shell prints its own "Segmentation fault" line when the
  # child dies on a signal, and that line is noise here: the crash IS
  # the expected result. Redirect the SHELL's stderr, not the child's.
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
# A program that printed nothing would exit 0 too. Each control must
# report the iteration count it actually reached.
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
