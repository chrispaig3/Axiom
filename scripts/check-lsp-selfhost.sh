#!/usr/bin/env bash
# The self-hosted language server, session by session, with no second
# compiler anywhere in the loop.
#
# WHAT THIS USED TO PIN. Half of this gate ran the Rust compiler. For
# every fixture it ran the Rust binary's `check --diagnostic-format ai`,
# parsed the AXDL line, converted stage0's 1-based CHARACTER column
# into the 0-based UTF-16 code unit LSP requires, and demanded the set of
# (severity, code, line, column) tuples the server published equal it.
# That was the half a `--bless` could not satisfy. The Rust compiler is
# being deleted, and a differential does not fail when its reference
# disappears - point `$axiom` at a self-hosted binary and every
# comparison becomes a compiler against itself: 7 fixtures swept, zero
# differences, exit 0, nothing tested. That is the failure mode this
# repository names most often, so the gate was rewritten rather than
# left to rot into agreement by mutual silence.
#
# WHAT IT PINS NOW. tests/lsp/drive.py runs one fixed session per
# fixture - lifecycle, didOpen, documentSymbol, an unsupported request,
# didClose, shutdown, exit - and checks the result against a checked-in
# golden AND against two hand-maintained manifests plus the fixture's
# own bytes. Only the first of those is re-blessable.
#
#   GOLDEN-ONLY, and therefore exactly as strong as whichever compiler
#   last blessed it: the framed byte stream - framing, field order,
#   JSON escaping, message sequence, the `initialize` capabilities, the
#   -32601 body - and the `help:` paragraph after a diagnostic
#   message's first line.
#
#   NOT RE-BLESSABLE, because there is no field in either manifest a
#   wrong answer could be written into and `--bless` rewrites *.golden
#   only:
#
#     * every diagnostic of every fixture, as a sorted LIST of (LSP
#       severity integer, code, line, UTF-16 start, UTF-16 end, first
#       line of the message). Positions are recomputed in Python from
#       the fixture's bytes - `len(line[:col].encode("utf-16-le")) // 2`
#       - a second implementation, in another language, of the exact
#       quantity stage0 used to supply. tests/lsp/expected-diagnostics.txt
#       names each diagnostic by severity, code, an ANCHOR STRING the
#       source contains, and the message line it must render; it carries
#       no line and no column at all. A list and not a set, so a
#       document with three diagnostics is three obligations.
#     * every symbol of every fixture: name, SymbolKind and
#       selectionRange, against tests/lsp/expected-outline.txt, which
#       is total - a fixture with no rows must publish an empty outline.
#     * two invariants on every symbol of every document including the
#       6001-symbol generated one, needing no manifest: selectionRange
#       contained in range, and the source sliced at selectionRange
#       spelling the symbol's own name.
#     * every non-empty diagnostic range must SPELL the name its own
#       message quotes in backticks, read back out of the source at
#       exactly those UTF-16 units - the shape of
#       tests/tools/verify-axsym.py.
#
# The one thing the deleted differential had that this does not is
# stage0's opinion about WHICH diagnostics a file deserves; the manifest
# carries that, and it was cross-checked against stage0 on 2026-08-08
# while both compilers still existed - 0 disagreements over all 7
# fixtures then present. That check is recorded in the manifest's
# header, because it cannot be repeated.
#
# NEGATIVE TESTS, re-run 2026-08-08 against this version of the gate.
# Six ablations. Each PATCHES self_host/lsp.ax in a scratch tree (never
# the real one), builds a server from it - six distinct binaries, sha256
# all different from the good one's 0cffc884 - RE-BLESSES every golden
# from that build so the golden half is green by construction, and then
# runs this whole script clean against the re-blessed tree. Every status
# below was captured with output redirected and `echo $?`, never through
# a pipe.
#
#   BYTE COLUMNS. `lspChar` returns `off - lineStartOf` instead of
#   walking UTF-16 code units. Caught before and still caught: 1 golden
#   rewritten, exit 1, 030-utf16-columns publishes 23 where the source
#   derives 20. That fixture's last line carries U+00E9 and U+1F600
#   inside a string literal before the anchor `zzz`, which therefore
#   sits at character 19, byte 23 and UTF-16 unit 20 - three different
#   numbers on purpose. drive.py refuses to run at all if no anchor in
#   the corpus has that property any more.
#
#   The next three all PASSED this gate as it stood on the morning of
#   2026-08-08 - "9 passed, 0 failed", exit 0, from a compiler that was
#   wrong about the language server's actual job. Each now fails:
#
#   SEVERITY 3. `lspSeverity` publishes Warning as LSP severity 3.
#   WAS exit 0, with the re-blessed golden reading `"severity":3` where
#   the checked-in one reads 2, because the driver projected everything
#   that was not 1 onto "W". NOW exit 1: 2 goldens rewritten, and both
#   070 and 080 report "published severities outside LSP Error(1) and
#   Warning(2): [('AX3010', 3)]".
#
#   OUTLINE DESTROYED. `lspSymKind` always answers 12 AND every symbol
#   `range` is `(lspRange src 0)`. WAS exit 0, with 060-outline.golden
#   re-blessed to call an enum a Function and to publish a
#   selectionRange NOT contained in its range - the invariant
#   self_host/lsp.ax's own comment claims it satisfies. NOW exit 1:
#   7 goldens rewritten, 8 failures, the first being "symbol 'Color':
#   selectionRange (0, 6)-(0, 11) is not contained in range
#   (0, 0)-(0, 0), which the protocol requires", and the large-document
#   case fails the same way on 6001 generated symbols.
#
#   ONLY THE FIRST DIAGNOSTIC, message text corrupted. The publish loop
#   becomes `(while (&& (< i 1) (< i (vecLen ds)))` and every message is
#   prefixed "WRONG-EXPLANATION ". WAS exit 0: every fixture had exactly
#   one expected diagnostic, so a set comparison could not see a dropped
#   one, and the backtick check reads only the FIRST quoted name out of
#   a message, so arbitrary prose around it was free. NOW exit 1:
#   5 goldens rewritten, 6 failures.
#
# The last two ablations exist because the two above each break two
# things at once, and a gate must be shown to catch each one ALONE -
# otherwise the weaker assertion is carried by the stronger:
#
#   KIND ONLY. `lspSymKind` answers 12 for everything; every range and
#   selectionRange is left exactly as it was, so both manifest-free
#   symbol invariants are satisfied. Exit 1, 1 golden rewritten, and
#   exactly one failure, from the hand-written file:
#     FAIL 060-outline: outline is not what expected-outline.txt and
#          the source say
#          server:  [('Color', 12, ...), ('P', 12, ...), ...]
#          derived: [('Color', 10, ...), ('P', 23, ...), ...]
#
#   DROP ONLY. The publish loop stops after one diagnostic; message
#   text untouched. Exit 1, 1 golden rewritten, and exactly one
#   failure, from comparing counted lists rather than sets:
#     FAIL 080-many-diagnostics: count: server published 1, manifest
#          demands 3
#
#   FILTERED RUN. `check-lsp-selfhost.sh 010` used to disable all three
#   anti-vacuousness floors - `if not filt:` - and exit 0 having swept
#   one fixture. Measured now: exit 1, with the floors scaled to the
#   selection rather than skipped (1 derived position, 1 name-at-range
#   check, 6002 symbol names, all equalities) and a PARTIAL line saying
#   the status is 1 by construction, because a one-fixture sweep must
#   not read as "the gate passed".
#
# THE MANIFESTS THEMSELVES are what those assertions rest on, so
# gutting one is refused before any server starts. Measured, each exit
# 1 with no fixture run: a diagnostic manifest where every fixture
# expects exactly one diagnostic ("comparing lists is the same as
# comparing sets"); one with no anchor whose UTF-16 column differs from
# both the byte and the character column ("no run could tell the three
# encodings apart"); an outline manifest naming fewer than three
# distinct SymbolKinds ("a server that answered 12 to everything would
# pass").
#
# RESTORED, this tree, same day: exit 0. 10 passed, 0 failed, 8
# fixtures + 2 generated; 7 positions derived from source, 7
# name-at-range checks, 6015 symbol names read back out of the source,
# discriminating on 030-utf16-columns:zzz.
#
#   AXIOM_BLESS=1 scripts/check-lsp-selfhost.sh          # all
#   AXIOM_BLESS=1 scripts/check-lsp-selfhost.sh 080      # one, exits 1
#
# Blessing does NOT skip the derived checks: a bless from a broken
# compiler prints its failures in the same run that wrote the goldens.

set -uo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

axiom="${AXIOM:-$repo_root/.axiom-bin/axiom}"
if [[ ! -x "$axiom" ]]; then
  echo "no compiler at $axiom - building one from the committed seed" >&2
  "$repo_root/scripts/bootstrap-from-seed.sh" --install "$repo_root/.axiom-bin" >&2 \
    || { echo "FAIL: could not bootstrap a compiler" >&2; exit 1; }
fi

export AXIOM_STDLIB="$repo_root/stdlib"

filter="${1:-}"
bless="${AXIOM_BLESS:-0}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

# The server under test is built FROM SOURCE by `$axiom`, not `$axiom`
# itself: this gate exists to watch self_host/, and `$axiom` may be an
# older seed-descended binary that predates the change being tested.
if ! "$axiom" build --input self_host/main.ax --output "$work/stage1" >"$work/build.log" 2>&1; then
  echo "FAIL: could not build the language server under test" >&2
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
floor=8
if [[ "$fixtures" -lt "$floor" ]]; then
  echo "FAIL: only $fixtures LSP fixtures found, expected at least $floor" >&2
  echo "      (a gate that reads fewer files than it should reports success it has not earned)" >&2
  exit 1
fi

# The two manifests are the half no re-bless can satisfy. If either is
# missing the gate is only a golden comparison, which is worth saying
# out loud rather than discovering later from a green run.
manifest="tests/lsp/expected-diagnostics.txt"
outline="tests/lsp/expected-outline.txt"
for f in "$manifest" "$outline"; do
  if [[ ! -s "$f" ]]; then
    echo "FAIL: $f is missing or empty - without it this gate is a golden" >&2
    echo "      comparison and nothing else, and a bless would satisfy all of it" >&2
    exit 1
  fi
done
rows=$(grep -cE '^[^#[:space:]]' "$manifest")
if [[ "$rows" -lt 6 ]]; then
  echo "FAIL: $manifest has $rows rows, expected at least 6" >&2
  exit 1
fi
orows=$(grep -cE '^[^#[:space:]]' "$outline")
if [[ "$orows" -lt 10 ]]; then
  echo "FAIL: $outline has $orows rows, expected at least 10" >&2
  exit 1
fi

args=("$work/stage1" "$repo_root/tests/lsp")
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

echo "swept $fixtures fixtures (floor $floor), $rows manifest rows, $orows outline rows"
exit $status
