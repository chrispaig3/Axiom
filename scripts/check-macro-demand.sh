#!/usr/bin/env bash
# Generated-name demand: the measurement that re-opens MAC-TOOL-3.
#
# WHAT STANDS. `docs/macro-system.md` MAC-TOOL-3 (H, 2026-08-15): editor
# requests read the raw parse tree and expand nothing, because expansion
# is bounded but not free (MAC-EXP-10: 41.4 s on a fan-out probe) and an
# editor cannot wait. The visible consequence is that a name only the
# expansion knows - `tagColour` from `(deriveTag Colour)`, `w1` from a
# declaration macro - goes unanswered: definition and hover are null,
# references are empty, completion does not offer it.
#
# WHAT RE-OPENS IT. Roadmap item 08: measurement of how often generated
# names are wanted. Two numbers, both pinned here:
#
#   population  every `#generated=` AXSYM row over the corpus that can
#               carry one - 115 today, all in tests/selfhost's decl-macro
#               family plus one frontend case, none in stdlib or the
#               compiler itself. The surface that could want locating.
#   demand      requests in tests/lsp/drive.py targeting a generated
#               name - 3 today (definition and hover unanswered, and
#               references seeing exactly the use site, on the generated
#               `tagShape` call), each asserting the raw-tree shape
#               inline. The want, going unanswered.
#
# A pin, not a ceiling: if either number moves, this gate fails and the
# conversation is whether MAC-TOOL-3 still holds - a new decl-macro user
# in stdlib, or expansion starting to answer, is exactly the evidence
# the decision was waiting for. The threshold is therefore movement
# itself, reviewed in the diff rather than tuned in the gate.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0; passed=0
ok()   { echo "ok   $*"; passed=$((passed + 1)); }
fail() { echo "FAIL: $*"; failed=$((failed + 1)); }

WANT_POPULATION=115
WANT_DEMAND=3

echo "== population: every #generated= row over the corpus =="
swept=0
population=0
for src in tests/selfhost/*.ax tests/frontend/*.ax self_host/main.ax; do
  [[ -e "$src" ]] || continue
  swept=$((swept + 1))
  n="$("$axc" --diagnostic-format=ai symbols "$src" 2>/dev/null | grep -c '#generated=' || true)"
  population=$((population + n))
done
# The stdlib side: one probe importing every module, so the stream is
# the whole library's (the shape scripts/check-agent-policy.sh uses).
# A file-by-file sweep here would resolve each module standalone and
# miss what only the merged namespace shows.
: > "$work/modfiles"
for f in stdlib/*.ax stdlib/*/*.ax; do
  [[ -e "$f" ]] || continue
  rel="${f#stdlib/}"; dir="$(dirname "$rel")"
  base="$(basename "$rel" .ax)"; base="${base%%.*}"
  if [[ "$dir" == "." ]]; then
    printf '%s\n' "$base" >> "$work/modfiles"
  else
    printf '%s.%s\n' "${dir//\//.}" "$base" >> "$work/modfiles"
  fi
done
{
  while read -r m; do printf '(import %s)\n\n' "$m"; done < <(LC_ALL=C sort -u "$work/modfiles")
  printf '(:: main Int)\n\n(fn (main) 0)\n'
} > "$work/probe.ax"
swept=$((swept + 1))
n="$("$axc" --diagnostic-format=ai symbols "$work/probe.ax" 2>/dev/null | grep -c '#generated=' || true)"
population=$((population + n))

# A sweep that reads fewer files than it should reports the population
# it was looking for. 197 corpus files plus the stdlib probe today.
if (( swept < 150 )); then
  fail "swept $swept file(s), floor is 150 - the corpus shrank or a glob stopped matching"
else
  ok "swept $swept files (corpus plus the stdlib probe)"
fi
if (( population == WANT_POPULATION )); then
  ok "population is $population #generated= rows, as pinned"
else
  fail "population is $population #generated= rows, pinned $WANT_POPULATION - a decl-macro user arrived or left; revisit MAC-TOOL-3 in the diff"
fi

echo
echo "== demand: requests targeting a generated name =="
# The behaviour itself is pinned inline in drive.py (each asserts the
# raw-tree absence); what is pinned here is that the probes still
# exist. A demand probe deleted quietly is demand measured quietly.
demand="$(grep -c 'MAC-TOOL-3-demand' tests/lsp/drive.py || true)"
if (( demand == WANT_DEMAND )); then
  ok "demand is $demand generated-name requests in drive.py, as pinned"
else
  fail "demand is $demand generated-name request(s) in drive.py, pinned $WANT_DEMAND - a probe was added or removed; revisit MAC-TOOL-3 in the diff"
fi

echo
echo "== the pin refuses a doctored count =="
# A pin that accepts everything is the vacuous check this repository
# finds most often: the comparison below is the whole gate, so the
# probe exercises it directly.
if (( 116 == WANT_POPULATION )); then
  fail "probe: a population of 116 against a pin of $WANT_POPULATION was accepted - the comparison cannot fail"
else
  ok "probe: a population of 116 against a pin of $WANT_POPULATION is refused"
fi
if (( 4 == WANT_DEMAND )); then
  fail "probe: a demand of 4 against a pin of $WANT_DEMAND was accepted - the comparison cannot fail"
else
  ok "probe: a demand of 4 against a pin of $WANT_DEMAND is refused"
fi

echo
if (( failed > 0 )); then
  echo "check-macro-demand: $failed check(s) failed, $passed passed"
  exit 1
fi
echo "check-macro-demand: $passed checks - $population generated rows, $demand unanswered wants"
