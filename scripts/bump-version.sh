#!/usr/bin/env bash
# Move the version everywhere it is stated, in one command.
#
#   scripts/bump-version.sh 0.3.0
#
# WHAT THIS REPLACED. `VERSION` is the authority, and seventeen sites
# across four file formats restate it: the compiler's own banner, the
# REPL's, the language server's `serverInfo`, four keys in
# `rust/Cargo.toml`, two tree-sitter manifests, and the REPL banner as
# quoted in `README.md` (twice) and `docs/reference.md`. Every one of
# those was a hand edit. `check-version.sh` would catch a miss - it did,
# on this very release, with seventeen sites still reading 0.2.0 - but
# catching it is not the same as not doing it, and a gate that fires
# after the tag is cut has fired too late.
#
# IT DOES NOT OWN THE LIST. The sites, the readers and the writers live
# in `scripts/lib/version-sites.sh`, which `check-version.sh` sources
# too. A second copy here would be a list to keep in step with the
# first, and that failure is silent: the bump rewrites sixteen, the gate
# checks seventeen, and the one they disagree about is the one nobody
# edited.
#
# IT PROVES ITS OWN WORK. The last thing it does is run
# `check-version.sh`, and it exits non-zero if that fails. So the script
# cannot report success over a site its writer missed - the writer and
# the reader are a pair, and this is where the pair is tested. Nothing
# else here needs to be trusted.
#
# WHAT IT DELIBERATELY DOES NOT DO: it does not touch `CHANGELOG.md`,
# does not commit, and does not tag. A release note is prose somebody
# writes, and `docs/` records that a `v*` tag is what fires
# `release.yml` - so cutting one is a decision, not a side effect of
# renumbering.

set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."
source scripts/lib/version-sites.sh

new="${1:-}"
if [[ -z "$new" ]]; then
  echo "usage: $0 <major.minor.patch>" >&2
  echo "       current: $(tr -d '[:space:]' < VERSION)" >&2
  exit 2
fi
if [[ ! "$new" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "FAIL: '$new' is not MAJOR.MINOR.PATCH" >&2
  exit 2
fi

old="$(tr -d '[:space:]' < VERSION)"
if [[ "$old" == "$new" ]]; then
  echo "VERSION already reads $new; rewriting the sites anyway so a"
  echo "half-applied bump is repairable by running this again."
fi

echo "== $old -> $new =="
printf '%s\n' "$new" > VERSION
echo "ok   VERSION"

while IFS='|' read -r file expect reader writer; do
  [[ -z "$file" ]] && continue
  if [[ ! -f "$file" ]]; then
    echo "FAIL $file: named in version-sites.sh but not in the tree" >&2
    exit 1
  fi
  "$writer" "$file" "$new"
  # The reader is the gate's, so this count is the gate's question asked
  # early: a writer that rewrote the wrong shape shows up here rather
  # than three minutes later.
  n="$("$reader" < "$file" | grep -c . || true)"
  if (( n != expect )); then
    echo "FAIL $file: states $n version(s) after rewriting, expected $expect" >&2
    echo "     the writer and the reader in version-sites.sh disagree about this site" >&2
    exit 1
  fi
  echo "ok   $file ($n)"
done <<< "$VERSION_SITES"

# The compiler's banner is compiled from `self_host/main.ax`, so the
# built binary keeps saying the old number until it is rebuilt.
# `check-version.sh` checks the BINARY as well as the sources, which is
# why this is a step and not a footnote.
echo
echo "== rebuilding, because check-version reads the built compiler too =="
if ! scripts/bootstrap-from-seed.sh --install .axiom-bin >/dev/null 2>&1; then
  echo "FAIL: could not rebuild the compiler after the bump" >&2
  exit 1
fi
echo "ok   .axiom-bin/axiom rebuilt"

echo
echo "== proving it: scripts/check-version.sh =="
if ! scripts/check-version.sh; then
  echo >&2
  echo "FAIL: the bump did not satisfy check-version.sh" >&2
  exit 1
fi

echo
echo "bumped to $new. Still yours to do: the CHANGELOG section, the commit,"
echo "and the v$new tag that fires .github/workflows/release.yml."
