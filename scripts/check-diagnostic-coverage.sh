#!/usr/bin/env bash
# THE DIAGNOSTIC-COVERAGE GATE (QA P1 §5 F1).
#
# `scripts/check-doc-drift.sh` holds constructed == listed (81/81) and
# `tests/diagnostics/verify-axdl-spans.py` holds a MIN_CODES floor, but
# neither asks per-code reachability: a diagnostic that constructs and
# never fires - a dead check, a wrong call site - stays green in both.
# This gate closes that hole the way `compat/UNCOVERED` closed the
# symbol-stream one: as a SET, not a count.
#
#   constructed (81, from self_host/*.ax outside explain.ax)
#     == primary .axdl codes + tests/diagnostics/UNCOVERED
#
# A new diagnostic code without a primary golden fails here until it
# gains a fixture or an UNCOVERED line with a reason. Closing a hole is
# UNCOVERED losing a line and tests/diagnostics/ gaining a fixture.
# Measured 2026-09-19: 81 constructed, 71 primary, 10 uncovered.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init --no-stdlib

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

constructed="$(sed 's/;.*$//' self_host/*.ax | grep -ohE '"AX[0-9]{4}"' | tr -d '"' | sort -u)"
primary="$(grep -hoE '^[EWNH] AX[0-9]{4}' tests/diagnostics/*.axdl | grep -oE 'AX[0-9]{4}' | sort -u)"
uncovered="$(grep -oE '^AX[0-9]{4}$' tests/diagnostics/UNCOVERED | sort -u)"

n_constructed="$(echo "$constructed" | wc -l | tr -d ' ')"
n_primary="$(echo "$primary" | wc -l | tr -d ' ')"
n_uncovered="$(echo "$uncovered" | wc -l | tr -d ' ')"

echo "constructed $n_constructed, primary $n_primary, uncovered $n_uncovered"

# Every constructed code is either primary or uncovered.
missing="$(comm -23 <(echo "$constructed") <(printf '%s\n%s' "$primary" "$uncovered" | sort -u))"
if [ -z "$missing" ]; then
  ok "every constructed code has a primary golden or an UNCOVERED line"
else
  bad "constructed but neither primary nor uncovered: $(echo "$missing" | tr '\n' ' ')"
fi

# Every UNCOVERED line is still constructed (no phantoms) and still
# uncovered (a fixture that landed must retire its line).
phantom="$(comm -23 <(echo "$uncovered") <(echo "$constructed"))"
if [ -z "$phantom" ]; then
  ok "every UNCOVERED line names a constructed code"
else
  bad "UNCOVERED names no-longer-constructed codes: $(echo "$phantom" | tr '\n' ' ')"
fi
retired="$(comm -12 <(echo "$uncovered") <(echo "$primary"))"
if [ -z "$retired" ]; then
  ok "no UNCOVERED code has gained a primary golden (nothing to retire)"
else
  bad "UNCOVERED codes with a primary golden - retire the line: $(echo "$retired" | tr '\n' ' ')"
fi

echo
if [ "$failed" -gt 0 ]; then
  echo "check-diagnostic-coverage: $failed of $checks checks failed"
  exit 1
fi
echo "check-diagnostic-coverage: $checks checks - $n_constructed constructed == $n_primary primary + $n_uncovered uncovered"
