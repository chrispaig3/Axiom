#!/usr/bin/env bash
# Verify the tree-sitter grammar against the compiler, and the
# documentation's Axiom against itself.
#
# Three checks. The second is the one that matters most, and the third
# is here rather than in a gate of its own because it belongs to the
# same CI job: the cheap one that needs no compiler.
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
#   3. Every Axiom code block in `README.md`, `docs/reference.md` and
#      `CONTRIBUTING.md` balances its delimiters. Documented syntax is
#      the one corpus nothing else reads, and it drifts the same way the
#      grammar does - see the note on the check itself.
#
# A grammar that drifts from the compiler is worse than no grammar: it
# misleads an editor into highlighting invalid code as valid, and the author
# only finds out at compile time - which is exactly the feedback loop the
# grammar exists to shorten.
#
# `tree-sitter` is not vendored, and if it is absent this script FAILS.
# It used to skip, on the reasoning that a contributor working on the
# compiler has no reason to install a JavaScript toolchain - but a gate
# that exits 0 when its tool is missing is a gate that is off on every
# machine that has not run the npm install below, which is most of
# them. `AXIOM_TREE_SITTER_OPTIONAL=1` skips it on purpose.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root/tree-sitter-axiom"

echo "--- documented Axiom code blocks balance their delimiters ---"
# Placed before the CLI probe below, because it needs no CLI and no
# compiler: a machine that has neither should still get this one.
#
# `axiom check` cannot be the test here. Most documented blocks are
# fragments - a column of literals, a bare expression, a `{}` body - and
# a fragment is not a module, so `check` refuses 45 of the 107 that
# exist and is right to. Balance is the property fragments and modules
# share, and it is the property both defects this found had violated:
# README.md's multi-method `trait` and multi-method `impl` examples each
# carried one extra `)`. Both were the SECOND, longer example under
# their heading; the short one above each was correct, which is how they
# survived being read.
# A document outside a sweep's list is invisible to it, and this list
# used to be written out here, again in check-tools-selfhost.sh, and a
# third time inside check-doc-drift.sh's Python - three copies that had
# already diverged. It is `gate_prose_docs` in scripts/lib/gate.sh now,
# and every gate that sweeps prose reads the same set.
gate_prose_docs_abs
python3 "$repo_root/tests/docs/verify-doc-code.py" "${prose_docs[@]}"

# Prefer a project-local install, then anything on PATH.
if [[ -x "$repo_root/tree-sitter-axiom/node_modules/.bin/tree-sitter" ]]; then
  ts="$repo_root/tree-sitter-axiom/node_modules/.bin/tree-sitter"
elif command -v tree-sitter > /dev/null 2>&1; then
  ts="$(command -v tree-sitter)"
elif [[ "${AXIOM_TREE_SITTER_OPTIONAL:-0}" == 1 ]]; then
  echo "skip: tree-sitter CLI not found (AXIOM_TREE_SITTER_OPTIONAL=1)"
  exit 0
else
  # Failing rather than skipping, deliberately.
  #
  # This exited 0 when the CLI was missing, which is the state of any
  # machine that has not run the npm install below - so on a developer
  # machine the gate reported success without checking anything. It hid
  # two real breakages at once: the grammar rejected every `struct` with
  # fields (and so most of `self_host/`), and the highlight-query step
  # named a file that had been deleted. Both would have been caught the
  # day they landed.
  #
  # Set AXIOM_TREE_SITTER_OPTIONAL=1 to skip on purpose.
  echo "error: tree-sitter CLI not found; cannot verify the grammar" >&2
  echo "       install with: npm install --prefix tree-sitter-axiom tree-sitter-cli" >&2
  echo "       or set AXIOM_TREE_SITTER_OPTIONAL=1 to skip this gate" >&2
  exit 1
fi

echo "using $ts"

# THE GENERATED PARSER IS CHECKED IN, AND `generate` OVERWRITES IT.
#
# Until this block that overwrite was silent: the gate regenerated
# `src/parser.c` from `grammar.js`, tested the result, and reported
# success on a parser nobody had committed. A grammar edit landing
# without its regenerated parser passed here and shipped a `src/` that
# no longer corresponded to the `grammar.js` beside it - and `src/` is
# what every consumer of this grammar compiles, because the CLI is not
# a build dependency of the published package.
#
# It also carries the VERSION. `tree-sitter generate` writes
# `.major_version` / `.minor_version` / `.patch_version` into
# `parser.c` from `tree-sitter.json`'s `metadata.version`, which is one
# of the sites `scripts/check-version.sh` holds to `VERSION`. So this
# comparison is what connects that gated number to the generated file
# it ends up in; without it the release could bump `tree-sitter.json`
# and ship a `parser.c` still claiming the previous minor.
#
# The comparison is against a copy taken here rather than against
# `git diff`, deliberately: `git diff` would call an uncommitted -
# and correct - working tree a failure, which is exactly the state this
# gate runs in on a developer's machine and in a release commit.
pre_gen="$(mktemp -d)"
trap 'rm -rf "$pre_gen"' EXIT
cp -R src "$pre_gen/src"

"$ts" generate

if diff -r -q "$pre_gen/src" src >/dev/null 2>&1; then
  echo "ok   the checked-in src/ is what generate produces from grammar.js"
else
  echo "FAIL: regenerating changed the checked-in parser." >&2
  echo "      grammar.js and src/ have diverged - run" >&2
  echo "        (cd tree-sitter-axiom && ./node_modules/.bin/tree-sitter generate)" >&2
  echo "      and commit src/ alongside the grammar change." >&2
  diff -r -q "$pre_gen/src" src >&2 || true
  exit 1
fi

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
# THE TRACKED SET, NOT THE DIRECTORY. This was `find . -name '*.ax'`
# with two `-not -path` exclusions, and every exclusion it needed was a
# symptom of the same defect: `find` answers "what is under this
# directory", which is not what "every .ax file in the repository"
# means. The exclusions were `./target/*`, a build directory, and
# `./.claude/*` - agent worktrees, each a full stale checkout,
# gitignored and so invisible to `.gitignore` but not to `find`.
# Measured 2026-08-25: 5,809 files swept against 506 in the tree, and a
# correct grammar change went red against a months-old copy of the
# corpus.
#
# The index needs neither exclusion - both are ignored, so neither is in
# it - and it fixes a second, nastier symptom this gate shares with
# check-doc-drift.sh's .ax census: this gate also runs in
# run-gates.sh's parallel phase, and a stray or vanishing .ax here is
# not a wrong count but a PARSE FAILURE or a missing-file error, blamed
# on the grammar.
#
# A version-control query that will not answer is fatal rather than a
# fallback to `find`, for the reason scripts/lib/ax-census.py gives at
# length: a silent fallback restores the race in the configuration
# nobody tests. The floor below is what catches an empty or garbled
# answer.
#
# THE COMMENT LIVES OUT HERE AND NOT INSIDE THE `< <( ... )`, and that
# is not style. An apostrophe in a comment inside a process
# substitution makes bash 3.2 give up with
# "bad substitution: no closing `)' in <(" - measured 2026-09-03, and
# the gate then printed its own source as the file list, swept nothing,
# skipped its remaining three sections and STILL EXITED 0. `bash -n`
# does not see it, because it is an expansion failure and not a syntax
# error. Nothing but running the gate finds that, which is why the
# floor below now asks for a number rather than for non-emptiness.
#
# Paths are made relative to the grammar directory because the CLI
# resolves a file's language from the grammar directory it is run in.
# Built with a read loop rather than `mapfile`, which is bash 4 and
# absent from the bash 3.2 that ships with macOS - where half this
# project's development happens.
sources=()
while IFS= read -r path; do
  sources+=("$path")
done < <(cd "$repo_root" && git ls-files -- '*.ax' | sed 's|^|../|' | sort)

# A FLOOR, not a non-emptiness test. `-eq 0` was the guard here, and it
# is satisfied by garbage: when the substitution above broke, `sources`
# held 30 lines of this script's own comment and the guard was happy.
# The tree has 613 `.ax` files today; 400 is a floor that a real
# deletion campaign would have to cross deliberately and that no
# malfunction of the enumeration can drift under.
if [[ "${#sources[@]}" -lt 400 ]]; then
  echo "error: the .ax sweep found only ${#sources[@]} file(s); the floor is 400." >&2
  echo "       Either the enumeration broke or the tree did - the check would" >&2
  echo "       otherwise pass over almost nothing." >&2
  printf '       first: %s\n' "${sources[0]:-<none>}" >&2
  exit 1
fi

if ! "$ts" parse --quiet --stat "${sources[@]}"; then
  echo
  echo "the grammar does not accept every .ax file in the repository" >&2
  exit 1
fi

echo
echo "--- highlight queries compile ---"
# A query with a nonexistent node name fails at load time, so running it
# proves it still loads against the current node types.
#
# Run over the whole corpus rather than one named file. The previous
# version named `../game_of_life/Life.ax`, which was deleted with the rest
# of that sample; the step had been failing on a missing file ever since,
# and nothing noticed because this script exits 0 when the CLI is absent -
# which it is on any machine that has not run the npm install above.
"$ts" query queries/highlights.scm "${sources[@]}" > /dev/null
echo "ok   queries/highlights.scm over ${#sources[@]} files"

# The rainbow query names every bracket-opening rule as a scope, and a
# rule renamed in grammar.js is a query that no longer compiles - which
# the editor reports as no rainbow colours and nothing else. So it is
# loaded against the same files, and it must MATCH: a query that
# compiles and captures no bracket on a corpus of 500 files is a query
# whose token list has drifted from the grammar's spelling.
"$ts" query queries/rainbows.scm "${sources[@]}" > "$pre_gen/rainbows.out"
rainbow_brackets=$(grep -c 'rainbow.bracket' "$pre_gen/rainbows.out" || true)
if [[ "$rainbow_brackets" -lt 1000 ]]; then
  echo "FAIL: queries/rainbows.scm captured $rainbow_brackets brackets over ${#sources[@]} files;" >&2
  echo "      a corpus this size has tens of thousands, so the query has stopped matching" >&2
  exit 1
fi
echo "ok   queries/rainbows.scm over ${#sources[@]} files, $rainbow_brackets brackets captured"
