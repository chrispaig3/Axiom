#!/usr/bin/env bash
# Two `axiom run`s in one directory do not corrupt each other.
#
# `axiom run` compiles to a scratch name and executes it, and
# `buildToExecutable` derives `<name>.ll`, `<name>.o` and `<name>.opt.ll`
# from that name. Two runs sharing a name overwrite and unlink each
# other's intermediates.
#
# A collision rarely looks like one. It shows up as `AX4003 opt failed`,
# as a child killed by a signal, or worst, as `axiom run p4.ax` exiting
# 0 with p6's answer because it was handed p6's executable. So each run
# must answer its own value; a pass/fail count would miss that case.
#
# Other gates run one compiler at a time or give each case its own
# scratch directory, so only this gate contends the working directory.
# Any parallel job pool relies on what it checks.
#
# The compiler keeps the names apart with `sysGetPid`, as `replEval`
# in repl.ax does. The runs repeat over several rounds, because a race
# that passes once proves nothing.
#
# Requires a compiler and the native toolchain.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

# Built from the tree, so a change to `self_host/` shows here, whatever
# binary `AXIOM` names.
gate_build_axc axc "$work/axiom"

WIDTH="${WIDTH:-6}"
ROUNDS="${ROUNDS:-5}"

# Every run shares one directory, so the scratch names contend.
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
      # 128+n is a child killed by a signal; name the signal.
      extra=""
      [[ "$got" =~ ^[0-9]+$ && "$got" -ge 128 ]] && extra=" (killed by signal $((got - 128)))"
      echo "FAIL round $round, program p$i.ax: answered $got, want $want$extra"
      failed=$((failed + 1))
    fi
    i=$((i + 1))
  done
done

echo "     $runs concurrent runs across $ROUNDS rounds at width $WIDTH"

# Floors: a gate that stopped starting processes would otherwise pass.
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
