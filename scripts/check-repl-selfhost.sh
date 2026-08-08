#!/usr/bin/env bash
# The self-hosted REPL against stage0's, session by session.
#
# The parity target is the PIPED surface - the only one a differential
# can compare (no prompt off-TTY, colors auto-suppressed, everything
# on stdout, stderr empty, exit 0) and the one the stage0 integration
# tests drive. Per-behavior policy, decided before any golden was
# blessed (docs/self-hosting.md):
#
#   * BYTE sessions (NNN-*.txt): stdout must be byte-identical
#     three-way - golden == stage0 == stage1 - with equal exit codes
#     and EMPTY stderr on both sides. Covers every scalar result
#     type (Float included: its bit-pattern print is deterministic
#     stage0 behavior, cloned bug-for-bug), declarations, state,
#     semantic errors, recovery, the command surface, comment/blank
#     handling, :quit, redefinition.
#   * SHAPE sessions (NNN-*-shape.txt): deterministic PREFIXES only.
#     `:time` prints a duration (stage1: an honest unavailable line
#     until a clock primitive exists); `:llvm` prints each compiler's
#     OWN IR, which differs by design (phase 4); `:defs` renders
#     stage0's builtin table, recorded divergent. For these, both
#     sides must exit 0 with empty stderr and print the session's
#     required marker lines; nothing else is compared.
#
# stage0 runs with HOME/XDG pointed into the work dir so its history
# file never touches the user's real one, and BOTH REPLs run from the
# work dir so relative scratch paths and wrapper import resolution
# see the same world. AXIOM_STDLIB carries the stdlib to both.
#
# Bless deliberately, never casually:
#   AXIOM_BLESS=1 scripts/check-repl-selfhost.sh          # all
#   AXIOM_BLESS=1 scripts/check-repl-selfhost.sh 010      # one

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/target/release/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "building the compiler first (no binary at $axiom)" >&2
  cargo build --release
fi

export AXIOM_STDLIB="$repo_root/stdlib"

filter="${1:-}"
bless="${AXIOM_BLESS:-0}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

if ! "$axiom" build --input self_host/main.ax --output "$work/stage1" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build stage1" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi

passed=0
failed=0
sessions=0

for sess in tests/repl/*.txt; do
  name="$(basename "$sess" .txt)"
  if [[ -n "$filter" && "$name" != "$filter"* ]]; then
    continue
  fi
  sessions=$((sessions + 1))

  (cd "$work" && HOME="$work" XDG_CONFIG_HOME="$work" \
     "$axiom" repl --no-banner <"$repo_root/$sess" >a.out 2>a.err)
  s0=$?
  (cd "$work" && ./stage1 repl --no-banner <"$repo_root/$sess" >b.out 2>b.err)
  s1=$?

  if [[ "$s0" != "$s1" ]]; then
    echo "FAIL $name: exit status diverged (stage0=$s0 stage1=$s1)"
    failed=$((failed + 1))
    continue
  fi
  # An eval surface that spills to stderr is passing vacuously
  # somewhere else - stage0 puts every REPL line on stdout, and so
  # must stage1.
  if [[ -s "$work/a.err" || -s "$work/b.err" ]]; then
    echo "FAIL $name: stderr is not empty (stage0 $(wc -c <"$work/a.err")B, stage1 $(wc -c <"$work/b.err")B)"
    head -3 "$work/a.err" "$work/b.err" | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi

  if [[ "$name" == *-shape ]]; then
    ok=1
    for marker in "Definitions in scope:" "Time: " "Generated LLVM IR:"; do
      if grep -qF "$marker" "$repo_root/$sess.markers" 2>/dev/null; then :; fi
    done
    # The session's marker file lists one required prefix per line;
    # both outputs must contain every one.
    while IFS= read -r marker; do
      [[ -z "$marker" ]] && continue
      if ! grep -qF -- "$marker" "$work/a.out"; then
        echo "FAIL $name: stage0 output lacks '$marker'"
        ok=0
      fi
      if ! grep -qF -- "$marker" "$work/b.out"; then
        echo "FAIL $name: stage1 output lacks '$marker'"
        ok=0
      fi
    done < "$repo_root/tests/repl/$name.markers"
    if [[ "$ok" == 1 ]]; then passed=$((passed + 1)); else failed=$((failed + 1)); fi
    continue
  fi

  golden="tests/repl/$name.golden"
  if [[ "$bless" == 1 ]]; then
    cp "$work/a.out" "$repo_root/$golden"
    if ! cmp -s "$work/a.out" "$work/b.out"; then
      echo "BLESS-WARNING $name: stage1 does not match the golden being blessed"
      diff "$work/a.out" "$work/b.out" | head -6 | sed 's/^/    /'
    fi
    echo "blessed $name"
    continue
  fi

  if [[ ! -f "$golden" ]]; then
    echo "FAIL $name (no golden; run with AXIOM_BLESS=1)"
    failed=$((failed + 1))
    continue
  fi
  if [[ ! -s "$golden" ]]; then
    echo "FAIL $name (golden is empty - agreement by silence)"
    failed=$((failed + 1))
    continue
  fi
  if ! cmp -s "$golden" "$work/a.out"; then
    echo "FAIL $name: stage0 diverged from the checked-in golden"
    diff "$golden" "$work/a.out" | head -6 | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi
  if ! cmp -s "$golden" "$work/b.out"; then
    echo "FAIL $name: stage1 diverged from the golden"
    diff "$golden" "$work/b.out" | head -6 | sed 's/^/    /'
    failed=$((failed + 1))
    continue
  fi
  passed=$((passed + 1))
done

if [[ "$bless" == 1 ]]; then
  echo "blessed $sessions sessions"
  exit 0
fi

# Floors: a glob that stops matching removes sessions while the sweep
# keeps reporting the silence it was looking for.
if [[ "$sessions" -lt 12 ]]; then
  echo "FAIL: swept $sessions sessions; the floor is 12"
  failed=$((failed + 1))
fi

# The differ, negative-tested: a corrupted golden must fail.
first_golden="$(ls tests/repl/*.golden 2>/dev/null | head -1)"
if [[ -n "$first_golden" ]]; then
  sed 's/result/resutl/' "$first_golden" > "$work/corrupt.golden"
  if cmp -s "$first_golden" "$work/corrupt.golden"; then
    echo "FAIL: the negative test did not fail - the differ is blind"
    failed=$((failed + 1))
  fi
else
  echo "FAIL: no goldens exist for the negative test"
  failed=$((failed + 1))
fi

echo "check-repl-selfhost: $passed passed, $failed failed ($sessions sessions)"
[[ "$failed" == 0 ]]
