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
# fixture - lifecycle, didOpen, documentSymbol, hover, an unsupported
# request, didClose, shutdown, exit - and checks the result against a
# checked-in golden AND against two hand-maintained manifests plus the
# fixture's own bytes. Only the first of those is re-blessable.
#
# Beside the per-fixture sessions it drives three whole-document ones
# that are written INTO drive.py rather than read from `tests/lsp/`, so
# their positions cannot drift away from the text they describe: a
# generated 500-diagnostic document, an editing session that must not
# grow, and NAVIGATION - six `definition` requests and a `hover` over a
# document that imports a module written to a temp directory. The
# navigation block is the one whose answers are all DERIVED: every
# expected range is computed from the two documents' own bytes, so no
# re-bless of any golden can satisfy it.
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

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

filter="${1:-}"
bless="${AXIOM_BLESS:-0}"

# The server under test is built FROM SOURCE by `$axiom`, not `$axiom`
# itself: this gate exists to watch self_host/, and `$axiom` may be an
# older seed-descended binary that predates the change being tested.
gate_build_axc stage1

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

# ------------------------------------------------------------------
# The outline's COST, as a ratio rather than a stopwatch.
#
# Everything above pins what the server answers; nothing pinned what it
# spends. `lspPos` used to answer both halves of a position by scanning
# the document from byte 0 - `lineOf` counts newlines from 0 and
# `lspChar`'s `lineStartOf` rescans to find the line start - and
# `lspRange` calls it twice per symbol, so an outline cost four
# whole-document scans per symbol. Measured before the line index:
# `documentSymbol` on `self_host/typecheck.ax` took 0.166 s against
# 0.042 s for the entire `didOpen` that parses and checks the same file,
# and 2.22 s at 8,002 symbols against 0.20 s.
#
# The assertion is a RATIO of two measurements taken here, on the same
# machine, in the same run: the outline request must not cost more than
# the whole parse-and-check of the same document. `didOpen` does strictly
# more work, so a correct index makes this comfortable (measured ~0.02x)
# and the quadratic makes it impossible (measured ~11x). An absolute
# millisecond ceiling would be a machine-speed assertion wearing a
# performance costume.
#
# And it proves the work happened before it reports the number, because
# a server that answers no symbols is extremely fast: the outline must
# carry at least $sym_floor symbols or this section fails rather than
# passes.
# ------------------------------------------------------------------
sym_floor=2000
perf=$(SERVER="$work/stage1" SYM_FLOOR="$sym_floor" python3 - <<'PY'
import json, os, subprocess, sys, time
server=os.environ["SERVER"]; floor=int(os.environ["SYM_FLOOR"])
n=floor+50   # one TAG_D_FN symbol per function; the `::` lines are not symbols
text="".join(f"(:: f{i} (-> Int Int))\n(fn (f{i} x) (+ x {i}))\n" for i in range(n))
text+="(:: main Int)\n(fn (main) 0)\n"
uri="file:///tmp/axiom-lsp-perf/big.ax"
def frame(o):
    b=json.dumps(o).encode(); return b"Content-Length: "+str(len(b)).encode()+b"\r\n\r\n"+b
base=[frame({"jsonrpc":"2.0","id":1,"method":"initialize","params":{"processId":None,"rootUri":None,"capabilities":{}}}),
      frame({"jsonrpc":"2.0","method":"initialized","params":{}}),
      frame({"jsonrpc":"2.0","method":"textDocument/didOpen","params":{"textDocument":{"uri":uri,"languageId":"axiom","version":1,"text":text}}})]
tail=[frame({"jsonrpc":"2.0","id":9,"method":"shutdown","params":{}}),frame({"jsonrpc":"2.0","method":"exit","params":{}})]
ds=[frame({"jsonrpc":"2.0","id":2,"method":"textDocument/documentSymbol","params":{"textDocument":{"uri":uri}}})]
def best(msgs):
    b=None; out=None
    for _ in range(3):
        t0=time.time()
        p=subprocess.run([server,"lsp","--no-banner"],input=b"".join(msgs),capture_output=True,timeout=600)
        dt=time.time()-t0
        if p.returncode!=0:
            print(f"FAIL server exited {p.returncode}"); sys.exit(1)
        if b is None or dt<b: b=dt;
        out=p.stdout
    return b,out
t_open,_=best(base+tail)
t_all,out=best(base+ds+tail)
syms=out.count(b'"selectionRange"')
if syms < floor:
    print(f"FAIL the outline carried {syms} symbols, floor {floor} - a server that")
    print(f"     answers nothing is fast, so the ratio below would mean nothing")
    sys.exit(1)
cost=max(t_all-t_open, 0.0)
ratio=cost/t_open if t_open>0 else 0.0
print(f"outline {syms} symbols: didOpen {t_open:.3f}s, documentSymbol {cost:.3f}s, ratio {ratio:.2f}x")
if ratio > 2.0:
    print(f"FAIL documentSymbol cost {ratio:.2f}x the whole parse-and-check of the same")
    print( "     document, over a ceiling of 2.00x. The line index is what keeps this")
    print( "     under one - see lspLineIndex in self_host/lsp.ax.")
    sys.exit(1)
PY
)
perf_status=$?
echo "$perf"
if [[ "$perf_status" -ne 0 ]]; then
  status=1
fi

exit $status
