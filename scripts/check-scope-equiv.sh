#!/usr/bin/env bash
# THE SCOPE-DRIFT GATE (MAC-HYG-9 equivalence slice, redefined at M3).
#
# The expander carries scope sets beside the rename table
# (`self_host/expand.ax`'s scope track, words 24-28), and under
# AXIOM_VERIFY_SCOPES=1 every variable reference the scope track hits
# is resolved both ways. A parting is AX3075. Before M3 this gate
# pinned an AGREEMENT - both mechanisms resolving every reference
# alike, with the one designed precedence control diverging - and the
# corpus leg's green was M3's safety proof: no shipped program relied
# on ren-first, so the flip to innermost-wins could move nothing but
# the control. Afterwards there is no agreement left to assert -
# one mechanism resolves, the other only shadows it - so the gate is
# redefined rather than left asserting a tautology: it runs the
# checkable corpus through verify mode and pins the absence of drift.
# Any AX3075 now is the drift shape, a missed push or truncation
# pairing between the two tracks, which is a compiler bug; M4 retires
# even that with the second track.
#
# The airtightness argument retired with the controls. The corpus leg
# passes by ABSENCE (no AX3075), which a silently-disabled verify
# would also produce - and no positive control can exist for a
# diagnostic whose only remaining shape is a compiler bug. M4 deletes
# this leg with the track it watches rather than letting a dead check
# report green; until then the leg's value is the red it would go,
# not the green it reports.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()   { echo "ok   $*"; checks=$((checks + 1)); }
bad()  { echo "FAIL $*"; failed=$((failed + 1)); }

# The corpus: every standalone-checkable program. Exit statuses are
# meaningless here - tests/diagnostics fails BY DESIGN - so the only
# assertion is the absence of AX3075. Helper modules under mods/ are
# not entries (they check as imports of their fixtures).
# A `while read` rather than `mapfile`: the macOS runner's bash is
# 3.2, which has neither `mapfile` nor `readarray`.
corpus=()
while IFS= read -r line; do
  corpus+=("$line")
done < <(find tests/selfhost tests/stdlib tests/diagnostics stdlib self_host \
  -name '*.ax' -not -path '*/mods/*' 2>/dev/null | sort)
echo "corpus: ${#corpus[@]} files"

echo "== every corpus file resolves identically both ways =="
n_div=0
n_checked=0
for f in "${corpus[@]}"; do
  n_checked=$((n_checked + 1))
  out="$(AXIOM_VERIFY_SCOPES=1 "$axc" --diagnostic-format=ai check "$f" 2>&1)" || true
  # `grep ... >/dev/null`, never `grep -q`: under `pipefail` a `-q`
  # match exits early and SIGPIPEs the producer, flipping the branch
  # (measured 2026-08-25; `check-gate-lib.sh` carries the scar).
  if echo "$out" | grep 'AX3075' >/dev/null; then
    n_div=$((n_div + 1))
    echo "FAIL scope-equiv: $f diverges:"
    echo "$out" | grep 'AX3075' | head -3 | sed 's/^/     /'
    failed=$((failed + 1))
  fi
done
(( n_div == 0 )) && ok "$n_checked corpus files, zero AX3075"

echo "check-scope-equiv: $checks checks, $failed failed"
exit $(( failed > 0 ))
