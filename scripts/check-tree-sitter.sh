#!/usr/bin/env bash
# Verify the tree-sitter grammar against the compiler.
#
# Two checks, and the second is the one that matters:
#
#   1. `tree-sitter test` runs the hand-written corpus in
#      `tree-sitter-axiom/test/corpus/`, which pins the *shape* of the tree
#      for each construct. A grammar change that still parses everything but
#      reorganises the tree breaks queries silently, and this catches it.
#
#   2. Every `.ax` file in the repository is parsed with the grammar and
#      must produce no ERROR node. This is the check that keeps the grammar
#      honest, because the corpus is written by whoever changed the grammar
#      and the standard library is not. When the language grows a form, the
#      stdlib and the demos get it first, and this fails until the grammar
#      catches up.
#
# A grammar that drifts from the compiler is worse than no grammar: it
# misleads an editor into highlighting invalid code as valid, and the author
# only finds out at compile time - which is exactly the feedback loop the
# grammar exists to shorten.
#
# `tree-sitter` is not vendored. If it is absent this script says so and
# skips, rather than failing, because a contributor working on the compiler
# has no reason to install a JavaScript toolchain.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/tree-sitter-axiom"

# Prefer a project-local install, then anything on PATH.
if [[ -x "$repo_root/tree-sitter-axiom/node_modules/.bin/tree-sitter" ]]; then
  ts="$repo_root/tree-sitter-axiom/node_modules/.bin/tree-sitter"
elif command -v tree-sitter > /dev/null 2>&1; then
  ts="$(command -v tree-sitter)"
else
  echo "skip: tree-sitter CLI not found"
  echo "      install with: npm install --prefix tree-sitter-axiom tree-sitter-cli"
  exit 0
fi

echo "using $ts"
"$ts" generate
"$ts" build

echo
echo "--- corpus tests (tree shape) ---"
"$ts" test

echo
echo "--- every .ax file in the repository parses without error ---"
# Paths are made relative to the grammar directory because the CLI resolves
# a file's language from the grammar directory it is run in.
# Built with a read loop rather than `mapfile`, which is bash 4 and absent
# from the bash 3.2 that ships with macOS - where half this project's
# development happens.
sources=()
while IFS= read -r path; do
  sources+=("$path")
done < <(
  cd "$repo_root" && find . -name '*.ax' -not -path './target/*' \
    | sed 's|^\./|../|' | sort
)

if [[ "${#sources[@]}" -eq 0 ]]; then
  echo "error: no .ax files found; the check would pass vacuously" >&2
  exit 1
fi

# `parse --quiet --stat` prints one line per failure and a summary. Its exit
# status is nonzero when any parse produced an ERROR node, which is the
# condition this gate is about.
if ! "$ts" parse --quiet --stat "${sources[@]}"; then
  echo
  echo "the grammar does not accept every .ax file in the repository" >&2
  exit 1
fi

echo
echo "--- highlight queries compile ---"
# A query with a nonexistent node name fails at load time. Running it over
# one real file is enough to prove it loads against the current node types.
"$ts" query queries/highlights.scm ../game_of_life/Life.ax > /dev/null
echo "ok   queries/highlights.scm"
