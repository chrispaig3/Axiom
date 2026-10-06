#!/usr/bin/env bash
# Move the version everywhere it is stated, in one command.
#
#   scripts/bump-version.sh 0.3.0
#
# `VERSION` is the authority. Every site in `scripts/lib/version-sites.sh`
# restates it: the compiler and language-server sources, the Cargo and
# npm manifests and lockfiles, the LSP transcripts, the website data,
# `SECURITY.md`, and the banners quoted in `README.md`, `docs/status.md`
# and `docs/reference.md`.
#
# The sites, with each one's reader and writer, live only in
# `version-sites.sh`, which `check-version.sh` also sources. A second
# list here could drift from the gate's without anyone noticing.
#
# The script ends by running `check-version.sh` and exits non-zero if it
# fails, so it can't report success over a site its writer missed.
#
# It doesn't edit `CHANGELOG.md`, commit or tag. A release note is prose
# someone writes, and a `v*` tag fires `release.yml`, so cutting one is
# a decision of its own.

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
  # The reader is the gate's, so a writer that rewrote the wrong shape
  # fails here, before the slower full check.
  n="$("$reader" < "$file" | grep -c . || true)"
  if (( n != expect )); then
    echo "FAIL $file: states $n version(s) after rewriting, expected $expect" >&2
    echo "     the writer and the reader in version-sites.sh disagree about this site" >&2
    exit 1
  fi
  echo "ok   $file ($n)"
done <<< "$VERSION_SITES"

# The compiler's banner is compiled in, so the built binary states the
# old number until it is rebuilt, and `check-version.sh` reads the
# binary as well as the sources.
echo
echo "== rebuilding, because check-version reads the built compiler too =="
if ! scripts/bootstrap-from-seed.sh --install .axiom-bin >/dev/null 2>&1; then
  echo "FAIL: could not rebuild the compiler after the bump" >&2
  exit 1
fi
echo "ok   .axiom-bin/axiom rebuilt"

# `tree-sitter-axiom/src/parser.c` is generated from `tree-sitter.json`,
# a version site, and compiles the version into the language's metadata.
# Rewriting the JSON alone leaves the parser stating the old number, and
# `check-tree-sitter.sh` then fails with "regenerating changed the
# checked-in parser", which looks like a grammar change.
# `check-version.sh` can't catch it, because the parser is a site's
# output rather than a site.
#
# Regenerating needs the tree-sitter CLI, a dev dependency that may be
# missing. Without it the script fails rather than warns, so it never
# reports success over a tree it has left broken.
echo
echo "== regenerating the tree-sitter parser, which states the version too =="
ts_cli="tree-sitter-axiom/node_modules/.bin/tree-sitter"
if [[ ! -x "$ts_cli" ]]; then
  echo "FAIL: no tree-sitter CLI at $ts_cli" >&2
  echo "     tree-sitter-axiom/src/parser.c is GENERATED from tree-sitter.json," >&2
  echo "     which this script just rewrote, so the checked-in parser now states" >&2
  echo "     the old version and check-tree-sitter.sh will fail on it." >&2
  echo "     Install the dev dependencies (cd tree-sitter-axiom && npm install)" >&2
  echo "     and re-run, or regenerate by hand before committing." >&2
  exit 1
fi
if ! ( cd tree-sitter-axiom && ./node_modules/.bin/tree-sitter generate ) >/dev/null 2>&1; then
  echo "FAIL: tree-sitter generate failed" >&2
  exit 1
fi
echo "ok   tree-sitter-axiom/src/ regenerated"

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
