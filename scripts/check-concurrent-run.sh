#!/usr/bin/env bash
# Two `axiom run`s in one directory do not corrupt each other.
#
# `axiom run` compiles to a scratch name and executes it. That name was
# the fixed literal `axiom_temp_output` in the WORKING DIRECTORY, and
# `buildToExecutable` derives `<name>.ll`, `<name>.o` and
# `<name>.opt.ll` from it - so two runs in one directory wrote over each
# other's intermediates and each unlinked the other's.
#
# The failure does not present as a collision. It presents as a
# miscompile, because what breaks is a later stage reading a file some
# other process already replaced or removed. Measured on six concurrent
# runs of six programs whose only difference is the integer they return,
# against a compiler built before the fix:
#
#   3:4  6:45  1:4  5:4  4:4  2:137
#
# One correct answer out of six. Four `exit 4` - `AX4003 opt failed`,
# blamed on the toolchain - and one `137`, a child killed by a signal.
# After the fix, the same six runs in the same directory:
#
#   1:41  2:42  3:43  4:44  5:45  6:46
#
# THE WORST OUTCOME IS NOT THE CRASH. Running this gate against a tree
# with the fix reverted fails 26 of 30, and the failures include:
#
#   FAIL round 4, program p4.ax: answered 46, want 44
#   FAIL round 4, program p5.ax: answered 46, want 45
#
# `axiom run p4.ax` answering 46 is p4 being handed p6's executable -
# one program printing another program's result, exit status 0, nothing
# on stderr. A crash is a bad outcome that announces itself; this one
# does not. It is why the assertion below is each run's OWN value rather
# than "no run failed".
#
# WHY NO GATE COULD SEE IT. Every other gate in this repository runs one
# compiler at a time, and the ones that run many run them in per-case
# scratch directories. Nothing had ever started two compilers in one
# directory, so the one piece of process-global state `axiom run` owns -
# a filename in the cwd - was never contended. It was found by running
# probe programs from the repository root while a gate battery was
# running there, and the wrong answers read as a real regression until
# the directory turned out to be what decided them.
#
# This is also the prerequisite for everything parallel: no job pool can
# be trusted while a filename is shared.
#
# The assertion is per-run and exact - each run must answer with ITS OWN
# number - and repeated over several rounds, because a race that passes
# once has proved nothing. `sysGetPid` is the discriminator, the same
# one `replEval` already uses (repl.ax) for the same reason.
#
# Requires: a compiler, and the native toolchain, since this gate is
# about what happens when several builds run at once.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

# Built from the tree, so an ablation of `self_host/` is visible here
# rather than hidden behind whatever binary `AXIOM` names.
gate_build_axc axc "$work/axiom"

WIDTH="${WIDTH:-6}"
ROUNDS="${ROUNDS:-5}"

# All of them in ONE directory. That is the whole point; per-case
# directories are what hid this.
d="$work/shared"; mkdir -p "$d"
i=1
while [[ $i -le $WIDTH ]]; do
  printf '(:: main Int)\n(fn (main) %d)\n' $((40 + i)) > "$d/p$i.ax"
  i=$((i + 1))
done

failed=0; runs=0
for round in $(seq 1 "$ROUNDS"); do
  rm -f "$d"/res_*
  i=1
  while [[ $i -le $WIDTH ]]; do
    ( cd "$d" && "$axc" run "p$i.ax" >/dev/null 2>&1; echo $? > "$d/res_$i" ) &
    i=$((i + 1))
  done
  wait

  i=1
  while [[ $i -le $WIDTH ]]; do
    runs=$((runs + 1))
    got="$(cat "$d/res_$i" 2>/dev/null || echo missing)"
    want=$((40 + i))
    if [[ "$got" != "$want" ]]; then
      # 128+n is a child killed by a signal, which is the worst of the
      # observed failures and must be named as such rather than counted.
      extra=""
      [[ "$got" =~ ^[0-9]+$ && "$got" -ge 128 ]] && extra=" (killed by signal $((got - 128)))"
      echo "FAIL round $round, program p$i.ax: answered $got, want $want$extra"
      failed=$((failed + 1))
    fi
    i=$((i + 1))
  done
done

echo "     $runs concurrent runs across $ROUNDS rounds at width $WIDTH"

# Floors. A race gate that stopped starting processes reports the same
# silence as one that passed.
if [[ $WIDTH -lt 4 ]]; then
  echo "FAIL: width is $WIDTH; the floor is 4 - fewer processes may not contend at all"
  failed=$((failed + 1))
fi
if [[ $runs -lt 20 ]]; then
  echo "FAIL: only $runs runs were made; the floor is 20. A race that passes once proves nothing"
  failed=$((failed + 1))
fi

echo
if [[ $failed -eq 0 ]]; then
  echo "PASS: $runs concurrent runs in one directory, every one answered its own value"
  exit 0
fi
echo "FAIL: $failed of $runs concurrent runs were wrong"
exit 1
