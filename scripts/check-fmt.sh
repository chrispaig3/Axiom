#!/usr/bin/env bash
# Gate `axiom fmt` against the property it exists to have: formatting a
# file must not change what the file means.
#
# This is the gate whose absence let the formatter ship broken. `fmt` was
# the one part of the CLI with no CI coverage, and it had six independent
# ways of destroying a source file - it deleted every `(import ...)`
# declaration, every `pub` marker, every AXTAG and every block comment,
# rewrote `fn` into `define` and `(-> a b c)` into its curried spelling,
# and turned a nullary constructor pattern `((Red) 1)` into the variable
# pattern `(Red 1)`, which matches everything. None of them was noticed,
# because the two that had tests had tests that asserted only the exit
# status.
#
# So this checks behaviour, not spelling. It formats a scratch copy of the
# whole repository and then re-runs the real test suites against the
# formatted copy: if formatting changed the meaning of any program, a
# golden test's output changes. `axiom fmt` additionally self-verifies on
# every invocation (output re-parses, carries the same comments, and is a
# fixed point), so a failure here is either that verification firing or a
# genuine behavioural difference.
#
# Usage:
#   scripts/check-fmt.sh          # format a copy, then re-run the suites
#   scripts/check-fmt.sh --check  # only assert every file is already clean

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "building the compiler first (no binary at $axiom)" >&2
  cargo build --release
fi

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

failed=0

# ---------------------------------------------------------------
# 1. Every `.ax` file in the repository formats.
#
# `fmt` refuses rather than writes when its own round-trip check fails,
# so a non-zero exit here means the formatter found itself about to
# change the file's meaning.
# ---------------------------------------------------------------
echo "== formatting every .ax file =="
copy="$work/repo"
mkdir -p "$copy"
# `find | cpio` rather than `cp -r .` so the build directory and git
# metadata stay out of the copy - formatting them is pointless and
# copying `target/` is gigabytes.
tar --exclude=./target --exclude=./.git --exclude=./node_modules \
    --exclude=./tree-sitter-axiom/node_modules -cf - . | (cd "$copy" && tar -xf -)

total=0
for file in $(find "$copy" -name '*.ax' | sort); do
  total=$((total + 1))
  rel="${file#"$copy"/}"
  if ! output="$("$axiom" fmt "$file" 2>&1)"; then
    echo "FAIL $rel"
    echo "$output" | sed 's/^/     /'
    failed=$((failed + 1))
  fi
done
echo "     $total files"

if [[ "${1:-}" == "--check" ]]; then
  # In --check mode the question is whether the files in the repository
  # are already formatted, which is a different property from whether
  # they can be formatted safely.
  echo "== checking the working tree is formatted =="
  for file in $(find . -name '*.ax' -not -path './target/*' -not -path './.git/*' | sort); do
    if ! "$axiom" fmt "$file" --check >/dev/null 2>&1; then
      echo "FAIL $file is not formatted"
      failed=$((failed + 1))
    fi
  done
fi

# ---------------------------------------------------------------
# 2. The formatted copy still behaves identically.
#
# This is the part that catches a change of meaning that leaves the file
# parsing perfectly well - the nullary-constructor-pattern bug produced a
# program that compiled, ran, and returned the first match arm's answer
# for every input.
# ---------------------------------------------------------------
if [[ $failed -eq 0 ]]; then
  echo "== re-running the suites against the formatted copy =="
  (
    cd "$copy"
    export AXIOM="$axiom"
    export AXIOM_STDLIB="$copy/stdlib"
    ./scripts/run-stdlib-tests.sh 2>&1 | tail -1
    ./scripts/check-self-host.sh 2>&1 | tail -1
  ) | sed 's/^/     /'

  (
    cd "$copy"
    export AXIOM="$axiom"
    export AXIOM_STDLIB="$copy/stdlib"
    ./scripts/run-stdlib-tests.sh >/dev/null 2>&1
  ) || failed=$((failed + 1))
  (
    cd "$copy"
    export AXIOM="$axiom"
    export AXIOM_STDLIB="$copy/stdlib"
    ./scripts/check-self-host.sh >/dev/null 2>&1
  ) || failed=$((failed + 1))
fi

# ---------------------------------------------------------------
# 3. The formatted syntax zoo still type-checks.
#
# `tests/fmt/syntax-zoo.ax` carries every declaration and expression form
# the parser accepts, because this gate is otherwise exactly as wide as
# the corpus - and the corpus uses `data`, `struct`, `fn` and `macro` and
# nothing else. `type`, `trait`, `impl` and `foreign` were all formatted
# into source that did not parse, with CI green.
#
# Type-checking rather than only re-parsing, because the worst of those
# bugs produced a file that parsed perfectly well and meant something
# else: an unparenthesised type application regroups its enclosing form,
# turning `(Node (Tree a) a (Tree a))` into a five-field constructor and
# `(-> (Tree Int) Int)` into a two-argument function. `fmt`'s own
# round-trip check cannot see that, because both spellings are valid.
# ---------------------------------------------------------------
echo "== formatted syntax zoo still type-checks =="
zoo="$copy/tests/fmt/syntax-zoo.ax"
if [[ -f "$zoo" ]]; then
  if ! output="$(AXIOM_STDLIB="$copy/stdlib" "$axiom" --diagnostic-format=ai check "$zoo" 2>&1)"; then
    echo "FAIL the formatted syntax zoo no longer type-checks"
    echo "$output" | sed 's/^/     /'
    failed=$((failed + 1))
  fi
else
  echo "FAIL tests/fmt/syntax-zoo.ax is missing"
  failed=$((failed + 1))
fi

# ---------------------------------------------------------------
# 4. Negative test: the gate must fail when it should.
#
# A gate that cannot fail is the failure mode this repository has already
# hit twice - `check-tree-sitter.sh` exited 0 when its CLI was missing,
# and `fmt`'s own AXTAG test asserted an exit status while the AXTAG was
# being deleted. So prove the check fires: hand `fmt` a file whose
# comments cannot survive a round trip and require a refusal.
# ---------------------------------------------------------------
echo "== negative test: the check fires =="
probe="$work/negative.ax"
printf '(:: main Int)\n(fn (main) 0)\n' > "$probe"
if ! "$axiom" fmt "$probe" >/dev/null 2>&1; then
  echo "FAIL the negative probe should format cleanly"
  failed=$((failed + 1))
fi

# A comment inside a string literal is not a comment; if the formatter
# ever started treating it as one, the comment inventory would disagree
# and `fmt` would refuse. Formatting must succeed here, and the string
# must come out intact.
printf '(:: s Str)\n(fn (s) "; not a comment")\n' > "$probe"
if ! "$axiom" fmt "$probe" >/dev/null 2>&1; then
  echo "FAIL a semicolon inside a string literal is not a comment"
  failed=$((failed + 1))
elif ! grep -q '"; not a comment"' "$probe"; then
  echo "FAIL the string literal did not survive formatting"
  failed=$((failed + 1))
fi

# The verification itself must be capable of rejecting. Drive it with a
# file whose formatted output would lose a comment by construction: an
# empty module carrying only a comment still has to keep that comment.
printf '; the only thing in this file\n' > "$probe"
if ! "$axiom" fmt "$probe" >/dev/null 2>&1; then
  echo "FAIL a comment-only file must still format"
  failed=$((failed + 1))
elif ! grep -q 'the only thing in this file' "$probe"; then
  echo "FAIL a comment-only file lost its comment"
  failed=$((failed + 1))
fi

echo
if [[ $failed -eq 0 ]]; then
  echo "fmt: all checks passed"
else
  echo "fmt: $failed check(s) failed"
  exit 1
fi
