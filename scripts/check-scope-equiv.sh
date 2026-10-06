#!/usr/bin/env bash
# The scope-drift gate (the MAC-HYG-9 equivalence slice).
#
# The expander carries scope sets beside the rename table
# (`self_host/expand.ax`'s scope track, words 24-28). Under
# AXIOM_VERIFY_SCOPES=1 every variable reference the scope track hits
# is resolved both ways, and a parting is AX3075. This gate runs the
# checkable corpus in that mode and requires no AX3075.
#
# With innermost-wins (M3) the scope track resolves and the rename
# table only shadows it. Any AX3075 is drift: a push or truncation that
# reached one track and not the other, which is a compiler bug. The
# planned M4 step deletes the rename table, and this gate with it.
#
# The gate passes by absence, which a silently disabled verify mode
# would also produce, and drift has no positive control. Its value is
# the red it would go.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0
checks=0
ok()   { echo "ok   $*"; checks=$((checks + 1)); }
bad()  { echo "FAIL $*"; failed=$((failed + 1)); }

# The corpus: every standalone-checkable program. Exit statuses mean
# nothing here, since tests/diagnostics fails by design, so the only
# assertion is no AX3075. Helper modules under mods/ are left out, since
# they check as imports of their fixtures. `while read` stands in for
# `mapfile`, which the macOS runner's bash 3.2 lacks.
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
  # match exits early and SIGPIPEs the producer, flipping the branch.
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
