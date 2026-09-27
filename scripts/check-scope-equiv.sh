#!/usr/bin/env bash
# THE SCOPE-EQUIVALENCE GATE (MAC-HYG-9 equivalence slice).
#
# The expander carries scope sets beside the rename table
# (`self_host/expand.ax`'s scope track, words 24-28), and under
# AXIOM_VERIFY_SCOPES=1 every variable reference the rename table hits
# is resolved both ways. A parting is AX3075. This gate runs the
# checkable corpus through verify mode and pins the theorem: both
# mechanisms agree on every reference, except the listed positive
# controls, which diverge by design (renaming answers the template
# binder where scope resolution would take the for-binding).
#
# The two legs are airtight together: the corpus leg passes by ABSENCE
# (no AX3075), which a silently-disabled verify would also produce -
# and the controls leg then fails for the same reason, because a
# control that does not diverge is a check that is not running.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()   { echo "ok   $*"; checks=$((checks + 1)); }
bad()  { echo "FAIL $*"; failed=$((failed + 1)); }

# Programs that diverge ON PURPOSE: renaming's ren-first precedence
# against scope resolution's innermost-wins. Each must emit AX3075
# under verify and check clean without it. One today; the list grows
# if the corpus ever grows a second shape (that day the corpus leg
# below goes red first, which is how the shape announces itself).
controls=(
  tests/selfhost/1003-macro-for-precedence.ax
)

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
echo "corpus: ${#corpus[@]} files, controls: ${#controls[@]}"

echo "== every corpus file resolves identically both ways =="
n_div=0
n_checked=0
for f in "${corpus[@]}"; do
  skip=0
  for c in "${controls[@]}"; do
    [[ "$f" == "$c" ]] && skip=1
  done
  (( skip )) && continue
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

echo "== the positive controls diverge, and only under verify =="
for c in "${controls[@]}"; do
  checks=$((checks + 1))
  if [[ ! -f "$c" ]]; then
    echo "FAIL scope-equiv: control $c is missing - retire it or restore it"
    failed=$((failed + 1))
    continue
  fi
  vout="$(AXIOM_VERIFY_SCOPES=1 "$axc" --diagnostic-format=ai check "$c" 2>&1)" || true
  nout="$("$axc" --diagnostic-format=ai check "$c" 2>&1)" || true
  if echo "$vout" | grep 'AX3075' >/dev/null; then
    if echo "$nout" | grep 'AX3075' >/dev/null; then
      echo "FAIL scope-equiv: control $c diverges WITHOUT verify - the track leaks into normal builds"
      failed=$((failed + 1))
    else
      echo "ok   control $c diverges under verify, clean without"
    fi
  else
    echo "FAIL scope-equiv: control $c does NOT diverge under verify - the check is not running"
    failed=$((failed + 1))
  fi
done

echo "check-scope-equiv: $checks checks, $failed failed"
exit $(( failed > 0 ))
