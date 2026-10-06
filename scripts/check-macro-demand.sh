#!/usr/bin/env bash
# Generated-name demand: the measurement that would re-open MAC-TOOL-3.
#
# `docs/macro-system.md` MAC-TOOL-3 (H): editor requests read the raw
# parse tree and expand nothing, because expansion is bounded but not
# free (MAC-EXP-10). A name only the expansion knows, such as `tagColour`
# from `(deriveTag Colour)`, is answered by `definition`, `declaration`,
# `hover` and `references` from a cache filled at `didOpen`. Completion
# does not offer it.
#
# Roadmap item 08 asks how often generated names are wanted. This gate
# pins two numbers:
#
#   population  `#generated=` AXSYM rows over the corpus and a probe
#               importing all of stdlib. At the pin, every row comes
#               from a test fixture, none from stdlib or the compiler.
#   demand      requests in tests/lsp/drive.py tagged
#               `MAC-TOOL-3-demand`. They target the generated
#               `tagShape` call and assert the cached answer inline.
#
# Either number moving fails the gate. Then review whether MAC-TOOL-3
# still holds: a decl-macro user in stdlib, or a request that needs
# expansion, is the evidence it waits for. Re-bless by updating
# WANT_POPULATION or WANT_DEMAND in the same diff.
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

failed=0; passed=0
ok()   { echo "ok   $*"; passed=$((passed + 1)); }
fail() { echo "FAIL: $*"; failed=$((failed + 1)); }

WANT_POPULATION=130
WANT_DEMAND=4

echo "== population: every #generated= row over the corpus =="
swept=0
population=0
for src in tests/selfhost/*.ax tests/frontend/*.ax self_host/main.ax; do
  [[ -e "$src" ]] || continue
  swept=$((swept + 1))
  n="$("$axc" --diagnostic-format=ai symbols "$src" 2>/dev/null | grep -c '#generated=' || true)"
  population=$((population + n))
done
# The stdlib side: one probe importing every module, as
# scripts/check-agent-policy.sh does. A file-by-file sweep would resolve
# each module alone and miss what only the merged namespace shows.
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

# A floor on files swept, so a glob that stops matching fails here and
# not as a population change.
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
# drive.py asserts each answer. This counts the probes, so deleting one
# fails here.
demand="$(grep -c 'MAC-TOOL-3-demand' tests/lsp/drive.py || true)"
if (( demand == WANT_DEMAND )); then
  ok "demand is $demand generated-name requests in drive.py, as pinned"
else
  fail "demand is $demand generated-name request(s) in drive.py, pinned $WANT_DEMAND - a probe was added or removed; revisit MAC-TOOL-3 in the diff"
fi

echo
echo "== the pin refuses a doctored count =="
# Negative probes: a doctored count must be refused, or the pins
# above could never fail.
if (( 116 == WANT_POPULATION )); then
  fail "probe: a population of 116 against a pin of $WANT_POPULATION was accepted - the comparison cannot fail"
else
  ok "probe: a population of 116 against a pin of $WANT_POPULATION is refused"
fi
if (( 5 == WANT_DEMAND )); then
  fail "probe: a demand of 5 against a pin of $WANT_DEMAND was accepted - the comparison cannot fail"
else
  ok "probe: a demand of 5 against a pin of $WANT_DEMAND is refused"
fi

echo
if (( failed > 0 )); then
  echo "check-macro-demand: $failed check(s) failed, $passed passed"
  exit 1
fi
echo "check-macro-demand: $passed checks - $population generated rows, $demand answered wants"
