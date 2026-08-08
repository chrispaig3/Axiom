#!/usr/bin/env bash
# The P2 slice-1 exit criterion, enforced: the managed Life probe -
# the explicit mark/copy-up/reset/copy-down contract - holds RSS
# flat (under 4 MiB) across 2000 generations with population exactly
# 5, while the unmanaged twin of the same program demonstrates the
# linear growth the memory model exists to remove. The negative runs
# every time: a reset with NO copy must corrupt the board, or the
# population check is blind to the exact unsoundness the contract
# guards against. All logic lives in measure-memory-baseline.sh;
# this wrapper exists so the battery and CI invoke the measurement
# and the gate by different names for the same code.
exec "$(dirname "${BASH_SOURCE[0]}")/measure-memory-baseline.sh" --gate
