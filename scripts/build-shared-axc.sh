#!/usr/bin/env bash
# Build the compiler-under-test ONCE, and stamp it so the gates will
# trust it.
#
# Eighteen gates call `gate_build_axc`, and each one rebuilt the same
# 60,881 lines into a byte-identical artifact. Measured 2026-08-24:
# 13s per build on a quiet developer machine, and the repository's own
# note for `check-repl-selfhost.sh` records ~1m40s on the machine it
# was written on - rising to 3m05s "with other gates running", which is
# the regime CI is always in. So the saving is between about four
# minutes and half an hour PER MATRIX LEG, and it grows with
# contention rather than shrinking.
#
# This writes two files: the artifact, and `<artifact>.stamp` holding
# `gate_source_stamp` for the tree as it stands. `gate_build_axc` reuses
# the artifact only while those agree, so this script does not have to
# be re-run when the tree changes - a stale artifact is ignored rather
# than believed, and the gate that proves that is
# `scripts/check-gate-lib.sh`.
#
# Usage:  ./scripts/build-shared-axc.sh <output-path>
# Then:   AXIOM_AXC=<output-path> ./scripts/check-whatever.sh

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

out="${1:-}"
if [[ -z "$out" ]]; then
  echo "usage: $0 <output-path>" >&2
  exit 2
fi
mkdir -p "$(dirname "$out")"

echo "== building the shared compiler under test from self_host/ =="
if ! "$axiom" build --input self_host/main.ax --output "$out" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build the shared compiler from self_host/" >&2
  sed 's/^/    /' "$work/build.log" | head -20 >&2
  exit 1
fi

gate_source_stamp > "$out.stamp"

# A stamp that does not match the tree it was just taken from would
# make every gate quietly rebuild - correct, but silently paying the
# cost this script exists to remove. Better to say so here than to
# discover it as a CI time that never improved.
if [[ "$(cat "$out.stamp")" != "$(gate_source_stamp)" ]]; then
  echo "FAIL: the stamp does not match the tree it was taken from" >&2
  exit 1
fi

echo "ok   $out"
echo "ok   stamp $(cut -c1-16 "$out.stamp")… - gates will reuse this until a source file moves"
