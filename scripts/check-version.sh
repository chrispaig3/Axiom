#!/usr/bin/env bash
# Assert that every place this project states its own version says the
# same thing, and that it is the thing `VERSION` says.
#
# WHY THIS GATE EXISTS. The version is a bare literal in every file
# `scripts/lib/version-sites.sh` names, across five formats - Axiom
# sources, Cargo entries, tree-sitter manifests, checked-in LSP
# transcripts and prose documents - and nothing held them to a single
# source of truth. The totals are printed below rather than restated
# here: this header said eleven for as long as it existed, and the
# table it describes has not been eleven since.
#
# It is NOT true that nothing compared them before this file, and the
# first version of this header said so; `check-driver.sh` (`22f2c19`,
# the same day) already pinned `self_host/repl.ax`, `self_host/lsp.ax`,
# the first `rust/Cargo.toml` key and all eight `tests/lsp/*.golden`
# files to what the built BINARY prints, and CI runs it. Those stay
# where they are and are not duplicated here.
#
# What this adds is the part that check could not express: a source of
# truth OUTSIDE the compiler. `check-driver.sh` compares the literals to
# the binary, so a tree where every site says `9.9.9` in agreement is
# green there. `VERSION` is the number the release tag, the archive name
# and the install script all read, so it is the number the literals must
# match - and the three `[workspace.dependencies]` keys, the two
# tree-sitter manifests and the two prose banners are reached by nothing
# else at all.
#
# It matters more than a tidiness gate, and it stopped being a
# prediction on 2026-08-24: `v0.2.0` is cut, so these numbers have been
# read from outside this repository. (This paragraph argued from "there
# are ZERO git tags today" until 2026-08-25, which was true when it was
# written and is the kind of claim that expires without anything
# noticing.) A binary whose `--version` disagrees with the archive it
# shipped in is the kind of thing that is discovered by a user rather
# than by CI.
#
# THE OTHER HALF OF P6 IS NOW HELD, ELSEWHERE. This paragraph used to
# read "what this gate still does NOT hold is ... a shipped binary
# names its VERSION and not its COMMIT, so two builds of different
# trees at one version are indistinguishable to whoever has the
# binary." Since 2026-08-25 `axiom version` prints a BUILD ID beside
# the version - a hash of every `.ax` byte the compiler was built
# from, plus the commit when git can say one - and
# `scripts/check-build-id.sh` is the gate. The split of labour is
# exact and worth keeping straight: a version is a promise about an
# interface and every site that states one must agree, which is this
# file; a build id is a fact about bytes and only the binary can carry
# it, which is that one.
#
# `VERSION` at the repository root is the single source of truth, and
# it is a file rather than a constant in `self_host/` on purpose: the
# Cargo workspace and the tree-sitter manifests cannot import an Axiom
# module, so a shared Axiom constant would still leave eight of the
# eleven sites ungated. A file every format can read keeps ONE number
# authoritative for all of them. Single-sourcing the three Axiom sites
# behind one exported constant is still worth doing and does not
# replace this.
#
# THE SITES ARE NAMED WITH THEIR COUNTS, NOT DISCOVERED. A grep for the
# current version string would pass vacuously the moment a site stopped
# containing it, which is the exact drift this exists to catch - so each
# site is listed with the pattern that must yield the version AND with
# how many times it must yield it. A count rather than a floor, because
# a floor is how `rust/Cargo.toml` could shrink from four version keys
# to one and still pass: the survivor agrees with `VERSION`, and the
# three that stopped matching are invisible to a test that only asks
# whether the file said the number at all.

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

# The readers, the writers and the site list all live in one file, which
# `scripts/bump-version.sh` sources too. That is the point: the bump and
# the check cannot disagree about what the sites ARE, because there is
# only one list. See scripts/lib/version-sites.sh.
source "$(dirname "${BASH_SOURCE[0]}")/lib/version-sites.sh"

# <file> <expected-count> <extractor>. The extractor prints every
# version this file states, one per line.
#
# `README.md` and `docs/reference.md` are here because they quote the
# REPL banner, which contains the version, and both were bumped by
# hand. README states it TWICE since 2026-08-25: the REPL banner and
# the `axiom version` line in CLI Commands, which now shows the build
# id beside the version. The count is what catches a third appearing. The gate a reader would assume covers them does not:
# `check-repl-selfhost.sh` drives the REPL as `repl --no-banner`, so the
# two lines those documents pin are the two lines that gate never sees.
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
# The literal agreeing with `VERSION` is not the same claim as the
# BINARY agreeing with it - that is `22f2c19`'s lesson, where a version
# assertion passed on a compiler that could have printed anything.
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
# A gate that has never been observed red is not evidence. This mutates
# a copy of EVERY named file and requires its own extractor to read the
# mutation back - all four extractors and all eleven sites, where the
# first version of this probe ran one extractor over one file and left
# the other three unexercised.
#
# The count is asserted on the mutant too, so an extractor that
# half-matches - reading three of `rust/Cargo.toml`'s four keys, say -
# fails here rather than in six months.
probed=0
# The dots are escaped: an unescaped `0.2.0` is a regex matching
# `0X2Y0`, so the mutation would land in places the assertions never
# look and the probe would be measuring its own sloppiness.
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
# Newest-release-only, formalised as a per-minor window (item 02's
# bus-factor work): each minor line is supported until the next minor
# lands, one supported minor at a time, no LTS. `SECURITY.md` states
# it; this section holds it. The minor and the next minor are DERIVED
# from `VERSION` here, so a minor cut that leaves the old window behind
# fails - and moving the paragraph is deliberately a hand edit, not a
# `bump-version.sh` rewrite: re-affirming the policy is the point, and
# a script cannot do it. Patch bumps need no touch: the minor and the
# next do not move under them.
major="${want%%.*}"; minor_n="${want#*.}"; minor_n="${minor_n%%.*}"
minor="$major.$minor_n"; next="$major.$((10#$minor_n + 1)).0"
check_window() { # <file> -> 0 when its window paragraph holds
  local f="$1" para
  # Lines are joined before the search: the phrases are claims about
  # words, and a reflow must not read as a policy change (nor a policy
  # change hide as a reflow - the mutants below move words, not lines).
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
  # mutant, then probe. The guard is load-bearing, not hygiene: a
  # reflow of SECURITY.md can move the words a `-e` anchors on, and a
  # mutation that changes no byte is a probe that passes while proving
  # nothing - measured while writing this, on the wrapped "one
  # supported minor" sentence.
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
