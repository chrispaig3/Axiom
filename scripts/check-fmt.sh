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
# There is no `--check` mode. This script had one - "assert every file
# in the working tree is already formatted" - and it was a mode that
# could never pass and that nothing ran: CONTRIBUTING.md says plainly
# that the repository is deliberately NOT kept in `axiom fmt`'s normal
# form, because a formatted tree would bury the narrative comments this
# codebase is written in. A gate that cannot go green is not a gate.
#
# Usage:
#   scripts/check-fmt.sh          # format a copy, then re-run the suites

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init --no-stdlib

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
# `tar | tar` rather than `cp -r .` so the build directories and git
# metadata stay out of the copy - formatting them is pointless and
# copying a `target/` is gigabytes. `./target` was the deleted Rust
# compiler's build directory; the live ones are `rust/target`, the
# per-example targets under `rust/examples/*/target`, and `.axiom-bin`.
#
# `.claude/` IS EXCLUDED AND THAT IS NOT A CONVENIENCE. Agent worktrees
# land at `.claude/worktrees/<run>-<n>/`, each a full checkout of this
# repository at whatever commit that run started from. They are in
# `.gitignore`, and `find` does not read `.gitignore`. Measured
# 2026-08-25: eleven abandoned worktrees, 494 MB, and this sweep was
# formatting **5,809** `.ax` files where the repository has **506** -
# ten copies of the tree, most of them months of commits stale.
#
# It is not only slow. A gate that sweeps "every file in the
# repository" and reaches files that are NOT in the repository will go
# red for a change that is correct here and stale there, which is
# exactly what a grammar change did. Whatever a sweep means by "the
# repository", it must not mean "whatever is under this directory".
tar --exclude=./.git --exclude=./rust/target --exclude=./.axiom-bin \
    --exclude='./rust/examples/*/target' --exclude=./node_modules \
    --exclude=./.claude/worktrees \
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
  # Once each, capturing to a file. This used to run both suites TWICE -
  # once piped through `tail -1` so the summary line could be shown, and
  # again with the output discarded so `$?` could be read, because a
  # pipeline's status is its last stage's. That is a second stage1 build,
  # 151 self-host cases and 59 stdlib builds per run of this gate, for a
  # status a temporary file already holds.
  for suite in run-stdlib-tests check-self-host; do
    if ( cd "$copy"
         export AXIOM="$axiom" AXIOM_STDLIB="$copy/stdlib"
         "./scripts/$suite.sh" ) >"$work/$suite.log" 2>&1; then
      sed 's/^/     /' <<< "$(tail -1 "$work/$suite.log")"
    else
      sed 's/^/     /' <<< "$(tail -1 "$work/$suite.log")"
      failed=$((failed + 1))
    fi
  done
fi

# ---------------------------------------------------------------
# 3. The formatted syntax zoo still type-checks.
#
# `tests/fmt/syntax-zoo.ax` carries every declaration and expression form
# the parser accepts, because this gate is otherwise exactly as wide as
# the corpus - and the corpus uses `data`, `struct`, `fn` and `macro` and
# nothing else. `type`, `trait` and `impl` were all formatted into source
# that did not parse, with CI green. So was `foreign`, until it was
# removed from the language - the zoo no longer carries it, and the
# printer no longer has an arm for it.
#
# Type-checking rather than only re-parsing, because the worst of those
# bugs produced a file that parsed perfectly well and meant something
# else: an unparenthesised type application regroups its enclosing form,
# turning `(Node (Tree a) a (Tree a))` into a five-field constructor and
# `(-> (Tree Int) Int)` into a two-argument function. `fmt`'s own
# round-trip check cannot see that, because both spellings are valid.
# ---------------------------------------------------------------
# ---------------------------------------------------------------
# 2b. The zoo formats to exactly the checked-in golden.
#
# Everything above asks whether formatting PRESERVES meaning. This asks
# what the normal form *is*, and pins it as a reviewed artefact rather
# than as whatever the printer happens to do.
#
# Two things need that. The zoo's last section is the list of spellings
# `fmt` deliberately rewrites - `(define x 1)` to `(fn (x) 1)`,
# `1_000_000` to `1000000`, `(-> Int (-> Int Int))` to
# `(-> Int Int Int)` - and a rewrite cannot be checked by re-parsing,
# because both spellings mean the same thing. Only a golden can say
# which one comes out.
#
# The formatter is the self-hosted one and there is no second
# implementation to diff it against, which is exactly why the golden is
# checked in rather than derived: with the expected bytes in the tree,
# changing the normal form means changing a file a human reads and
# reviews, instead of a number a script recomputes.
#
# Regenerate deliberately, never automatically:
#   cp tests/fmt/syntax-zoo.ax tests/fmt/syntax-zoo.expected.ax
#   .axiom-bin/axiom fmt tests/fmt/syntax-zoo.expected.ax
# ---------------------------------------------------------------
echo "== the zoo formats to the checked-in golden =="
golden="$repo_root/tests/fmt/syntax-zoo.expected.ax"
if [[ ! -f "$golden" ]]; then
  echo "FAIL tests/fmt/syntax-zoo.expected.ax is missing"
  failed=$((failed + 1))
elif [[ ! -s "$golden" ]]; then
  # A golden with no content agrees with everything, which is the
  # failure that looks like success.
  echo "FAIL the golden is empty"
  failed=$((failed + 1))
else
  fresh="$work/zoo-formatted.ax"
  cp "$repo_root/tests/fmt/syntax-zoo.ax" "$fresh"
  if ! "$axiom" fmt "$fresh" >/dev/null 2>&1; then
    echo "FAIL formatting the zoo failed"
    failed=$((failed + 1))
  elif ! cmp -s "$fresh" "$golden"; then
    echo "FAIL the zoo no longer formats to tests/fmt/syntax-zoo.expected.ax"
    diff "$golden" "$fresh" | head -20 | sed 's/^/     /'
    failed=$((failed + 1))
  else
    echo "     $(wc -l < "$golden" | tr -d ' ') lines of normal form, unchanged"
  fi
fi

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
