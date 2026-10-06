#!/usr/bin/env bash
# Checks that every place the project states its version agrees with
# `VERSION` at the repository root.
#
# The version is a bare literal in every file
# `scripts/lib/version-sites.sh` names: Axiom sources, Cargo entries,
# tree-sitter manifests, checked-in LSP transcripts and prose documents.
# The totals are printed below.
#
# `check-driver.sh` pins some of these literals to what the built binary
# prints, which passes when every site agrees on the wrong number.
# `VERSION` is what the release tag, the archive name and the install
# script read, so every literal must match it. Some sites, such as the
# `[workspace.dependencies]` keys, the tree-sitter manifests and the
# prose banners, have no other gate. Without this, a binary whose
# `--version` disagrees with its archive reaches users unnoticed.
#
# A version is a promise about an interface, and every site that states
# one must agree: that is this gate. A build id is a fact about bytes
# that only the binary carries: `scripts/check-build-id.sh` holds it.
#
# `VERSION` is a file because the Cargo workspace and the tree-sitter
# manifests can't import an Axiom module. One exported constant for the
# Axiom sites would still help, alongside this.
#
# Each site is named with the pattern that must yield the version and the
# exact number of times it must yield it. A grep for the current version
# would pass the moment a site stopped containing it. A floor would let
# `rust/Cargo.toml` shrink from four version keys to one and still pass,
# because the survivor agrees and the three lost keys are invisible.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init --no-stdlib

failed=0

[[ -f VERSION ]] || { echo "FAIL: VERSION is missing at the repository root"; exit 1; }
want="$(tr -d '[:space:]' < VERSION)"
if [[ ! "$want" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "FAIL: VERSION reads '$want', which is not MAJOR.MINOR.PATCH"
  exit 1
fi
echo "== VERSION says $want =="

# The readers, the writers and the site list live in
# scripts/lib/version-sites.sh, which `scripts/bump-version.sh` sources
# too, so the bump and the check share one list.
source "$(dirname "${BASH_SOURCE[0]}")/lib/version-sites.sh"

# <file> <expected-count> <extractor>. The extractor prints every
# version this file states, one per line.
#
# The `ax_version` sites quote the REPL or `axiom version` banner, and
# the count catches a new copy. `check-repl-selfhost.sh` drives the
# REPL as `repl --no-banner`, so it never sees these lines.
SITES="$VERSION_SITES"

extract() { "$2" < "$1" || true; }

count_of() { printf '%s' "$1" | grep -c . || true; }

check_site() {
  local file="$1" expect="$2" fn="$3"
  if [[ ! -f "$file" ]]; then
    echo "FAIL $file: named here but not in the tree"
    failed=$((failed + 1)); return
  fi
  local got n bad=0 v
  got="$(extract "$file" "$fn")"
  n="$(count_of "$got")"
  if (( n != expect )); then
    echo "FAIL $file: states $n version(s), expected $expect."
    if (( n == 0 )); then
      echo "     The pattern found nothing, which is drift rather than agreement."
    else
      echo "     A site stopped matching, or a new one appeared. Recount and update"
      echo "     the expected count here in the same commit that moved it."
    fi
    failed=$((failed + 1)); return
  fi
  while IFS= read -r v; do
    [[ -z "$v" ]] && continue
    [[ "$v" == "$want" ]] || { echo "FAIL $file: says '$v', VERSION says '$want'"; bad=1; }
  done <<< "$got"
  if (( bad )); then failed=$((failed + 1)); else echo "ok   $file ($n)"; fi
}

total=0
while IFS='|' read -r file expect fn _writer; do
  [[ -z "$file" ]] && continue
  check_site "$file" "$expect" "$fn"
  total=$((total + expect))
done <<< "$SITES"
echo "     $total sites over $(printf '%s' "$SITES" | grep -c .) files"

echo
echo "== the built compiler reports it too =="
# The literals agreeing with `VERSION` is a separate claim from the
# binary agreeing with it.
gate_build_axc axc
got="$("$axc" version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1 || true)"
if [[ "$got" != "$want" ]]; then
  echo "FAIL: the built compiler prints '$got', VERSION says '$want'"
  failed=$((failed + 1))
else
  echo "ok   \`axiom version\` prints $got"
fi

echo
echo "== negative probe: every extractor sees a disagreement =="
# Mutate a copy of every named file and require its extractor to read
# the mutation back, so every extractor and site is seen to go red. The
# count is checked on the mutant too, so an extractor that reads three of
# `rust/Cargo.toml`'s four keys fails here.
probed=0
# Escape the dots: an unescaped `0.2.0` is a regex matching `0X2Y0`, so
# the mutation could land where the assertions never look.
want_re="$(printf '%s' "$want" | sed 's/\./\\./g')"
while IFS='|' read -r file expect fn _writer; do
  [[ -z "$file" ]] && continue
  mutant="$work/mutant-$(echo "$file" | tr '/.' '__')"
  sed -e "s/$want_re/9.9.9/g" "$file" > "$mutant"
  got="$(extract "$mutant" "$fn")"
  n="$(count_of "$got")"
  saw_only_999=1
  while IFS= read -r v; do
    [[ -z "$v" ]] && continue
    [[ "$v" == "9.9.9" ]] || saw_only_999=0
  done <<< "$got"
  if (( n == expect )) && (( saw_only_999 )); then
    echo "ok   $file: $n mutated literal(s) read back as 9.9.9"
    probed=$((probed + 1))
  else
    echo "FAIL negative $file: read $n value(s) from the mutant, expected $expect"
    echo "                    all reading 9.9.9 - so the assertion above is matching"
    echo "                    something other than what it claims to."
    failed=$((failed + 1))
  fi
done <<< "$SITES"
echo "     $probed extractor/site pairs observed red"

echo
echo "== the support window names this minor and the next =="
# `SECURITY.md` states the support window: each minor line is supported
# until the next minor lands, one at a time, with no LTS. The minor and
# the next are derived from `VERSION`, so cutting a minor without moving
# the window fails. `bump-version.sh` leaves the paragraph alone: moving
# it is a hand edit that re-affirms the policy. Patch bumps don't move it.
major="${want%%.*}"; minor_n="${want#*.}"; minor_n="${minor_n%%.*}"
minor="$major.$minor_n"; next="$major.$((10#$minor_n + 1)).0"
check_window() { # <file> -> 0 when its window paragraph holds
  local f="$1" para
  # Lines are joined before the search, so a reflow doesn't read as a
  # policy change. The mutants below move words, not lines.
  para="$(sed -n '/^Support window:/,/^$/p' "$f" | tr '\n' ' ')"
  [[ -n "$para" ]] || return 1
  grep -qF "the $minor line" <<<"$para" || return 1
  grep -qF "until $next" <<<"$para" || return 1
  grep -qF "one supported minor at a time" <<<"$para" || return 1
  return 0
}
if check_window SECURITY.md; then
  echo "ok   SECURITY.md windows the $minor line until $next, newest-only"
else
  echo "FAIL SECURITY.md's support window does not name the $minor line until $next"
  failed=$((failed + 1))
fi
# One mutant per arm, plus the paragraph deleted entirely: each must go
# red, or the arm above is a check that cannot fail.
win_probed=0
win_probe() { # <label> <mutant>
  if check_window "$2"; then
    echo "FAIL negative window $1: the mutant was accepted"
    failed=$((failed + 1))
  else
    echo "ok   window $1 refused"
    win_probed=$((win_probed + 1))
  fi
}
win_mutant() { # <label> <out> <sed-expr>...: mutate, refuse an unchanged
  # mutant, then probe. A reflow of SECURITY.md can move the words an
  # `-e` anchors on, and a mutation that changes no byte proves nothing.
  local label="$1" out="$2"; shift 2
  sed "$@" SECURITY.md > "$out"
  if cmp -s "$out" SECURITY.md; then
    echo "FAIL negative window $label: the mutation changed no byte - re-anchor it"
    failed=$((failed + 1)); return
  fi
  win_probe "$label" "$out"
}
win_mutant "a window naming another minor" "$work/win-minor.ax" -e "s/the $minor line/the 9.9 line/"
win_mutant "a window ending at another release" "$work/win-next.ax" -e "s/until $next/until 9.9.0/"
win_mutant "a window promising several minors" "$work/win-single.ax" -e "s/There is one$/There are several/" -e "s/supported minor at a time/supported minors at once/"
sed -e '/^Support window:/,/^$/d' SECURITY.md > "$work/win-gone.ax"
if cmp -s "$work/win-gone.ax" SECURITY.md; then
  echo "FAIL negative window a policy with no window at all: the deletion removed nothing"
  failed=$((failed + 1))
else
  win_probe "a policy with no window at all" "$work/win-gone.ax"
fi
echo "     $win_probed window mutants observed red"

echo
if (( failed > 0 )); then
  echo "check-version: $failed site(s) disagree with VERSION"
  exit 1
fi
echo "check-version: every site states $want, and the built compiler prints it"
