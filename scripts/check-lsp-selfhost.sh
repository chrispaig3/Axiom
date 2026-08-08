#!/usr/bin/env bash
# The self-hosted language server, session by session.
#
# `axiom lsp` is the first tool surface that is NOT a port of a stage0
# tool: the Rust compiler has no `lsp` subcommand, so there is nothing
# to run a two-sided differential against. That makes this gate the
# native-surface shape the human renderer established, and it checks
# two independent things per fixture:
#
#   1. The framed byte stream of a fixed session - lifecycle, didOpen,
#      documentSymbol, an unsupported request, didClose, shutdown,
#      exit - must equal a checked-in golden, with the document's
#      absolute URI normalised out.
#
#   2. The diagnostics it publishes must agree with what stage0's own
#      `check --diagnostic-format ai` reports for the same file: same
#      severity, same code, same line, and the same column AFTER
#      converting stage0's 1-based character column into the 0-based
#      UTF-16 code unit LSP asks for. That conversion is derived from
#      stage0's artifact plus the fixture's own bytes, so it cannot be
#      satisfied by re-blessing - which matters, because the drill
#      below proved a version of this gate that compared only lines
#      passed 7/7 with the UTF-16 conversion removed entirely.
#
# Fixtures that do not PARSE are exempt from the code comparison and
# assert only that both sides refuse: stage1's parser carries no
# diagnostic payload yet, so it answers one AX2003 at the top of the
# file where stage0 names a specific code and position. That is a
# recorded divergence (the parse-error port), not an agreement.
#
# NEGATIVE TEST, run and recorded 2026-08-08: replacing `lspChar`'s
# UTF-16 walk with a byte count, then RE-BLESSING every golden from
# that ablated build, still fails `030-utf16-columns` (server 23,
# stage0-derived 20) and exits 1.
#
#   AXIOM_BLESS=1 scripts/check-lsp-selfhost.sh          # all
#   AXIOM_BLESS=1 scripts/check-lsp-selfhost.sh 030      # one

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

# The server under test is the SELF-HOSTED compiler, built here rather
# than assumed: this gate exists to watch stage1, and a stale binary
# would report yesterday's answer.
if ! "$axiom" build --input self_host/main.ax --output "$work/stage1" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build stage1" >&2
  tail -20 "$work/build.log" >&2
  exit 1
fi

# `.axbad` is the deliberately-unparseable fixture; it is not `.ax`
# because check-fmt.sh and check-tree-sitter.sh sweep every `*.ax` file
# in the repository and require all of them to parse.
fixtures=$(find tests/lsp \( -name '*.ax' -o -name '*.axbad' \) | wc -l | tr -d ' ')
# A sweep that quietly shrinks is the failure mode this floor exists
# for: a glob that stops matching removes fixtures while the gate goes
# on reporting the silence it was looking for.
floor=7
if [[ "$fixtures" -lt "$floor" ]]; then
  echo "FAIL: only $fixtures LSP fixtures found, expected at least $floor" >&2
  echo "      (a gate that reads fewer files than it should reports success it has not earned)" >&2
  exit 1
fi

args=("$work/stage1" "$axiom" "$repo_root/tests/lsp")
if [[ "$bless" == "1" ]]; then
  args+=("--bless")
fi
if [[ -n "$filter" ]]; then
  args+=("$filter")
fi

# Run it directly, not through a pipe: `... | tail` reports TAIL's exit
# status, which has made a failing gate in this repository read as
# green more than once.
python3 tests/lsp/drive.py "${args[@]}"
status=$?

echo "swept $fixtures fixtures (floor $floor)"
exit $status
