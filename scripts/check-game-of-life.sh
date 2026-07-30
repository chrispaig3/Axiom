#!/usr/bin/env bash
# Build and run the Game of Life demo, checking both cases against their
# golden output.
#
# This is a correctness gate, not a showcase. Life is Turing-complete, so
# the demo doubles as the largest pure-Axiom program in the tree, and it
# exercises the combination the unit tests cover only separately:
# polymorphic recursive `data` across two type levels
# (`List (List Cell)`), exhaustive `match` on every access, multi-module
# imports, and iteration expressed as recursion because the language has
# no loop.
#
# Both cases are checked at `-O0` and `--opt 2`. That is not redundant:
# `--opt 2` is what promotes self-recursion to a branch, so the two levels
# have genuinely different stack behaviour, and a bug that only appears
# when the optimiser runs (or only when it does not) is a bug this project
# has already shipped once - see `scripts/check-cross-targets.sh`.

set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "building the compiler first (no binary at $axiom)" >&2
  cargo build --release
fi

export AXIOM_STDLIB="$repo_root/stdlib"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

status=0

# case:expected-output
cases=(
  "main.ax:expected.out"
  "stress.ax:stress.expected.out"
)

for opt in 0 2; do
  for entry in "${cases[@]}"; do
    source_file="game_of_life/${entry%%:*}"
    expected="game_of_life/${entry##*:}"
    name="$(basename "$source_file" .ax)"
    bin="$work/$name.O$opt"

    if ! log="$("$axiom" build --input "$source_file" --output "$bin" \
      --opt "$opt" 2>&1)"; then
      echo "FAIL $name -O$opt (build)"
      echo "$log" | sed 's/^/    /'
      status=1
      continue
    fi

    if ! actual="$("$bin" 2>&1)"; then
      echo "FAIL $name -O$opt (run: exited nonzero)"
      echo "$actual" | sed 's/^/    /'
      status=1
      continue
    fi

    if [[ "$actual" != "$(cat "$expected")" ]]; then
      echo "FAIL $name -O$opt (stdout)"
      diff "$expected" <(printf '%s\n' "$actual") | sed 's/^/    /' || true
      status=1
      continue
    fi

    echo "ok   $name -O$opt"
  done
done

# The core must stay free of effects. `Life.ax` is where the language
# claim lives, and it is only a claim about pure computation if nothing in
# it touches the operating system. The compiler already knows the answer -
# effects are inferred transitively - so this asks it rather than trusting
# the file's structure.
if "$axiom" --diagnostic-format=ai symbols game_of_life/Life.ax \
  | grep -q 'effect=io'; then
  echo "FAIL Life.ax declares an io effect; the pure core must not perform I/O"
  status=1
else
  echo "ok   Life.ax is effect-free"
fi

exit "$status"
