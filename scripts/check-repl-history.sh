#!/usr/bin/env bash
# The REPL's history survives the process that wrote it, and two REPLs
# at once do not eat each other's.
#
# WHY THIS GATE EXISTS SEPARATELY FROM THE FIXTURE. `tests/selfhost/
# 975-repl-history.ax` already drives the codec, the ring, browsing and
# reverse search - thirty-eight assertions, no terminal, no filesystem.
# What it cannot do is tell a file that was WRITTEN from a ring that was
# merely never dropped: everything it asserts is true of a build with
# `sysAppendFile` deleted. That distinction needs two processes, and two
# processes need a script.
#
# WHY IT CAN FAIL, which is the property this repository asks of a gate
# before anything else. `self_host/replhist.ax` never asks whether a
# terminal is present; `histOpen` takes `interactive` as an ordinary
# Int. So this gate drives BOTH directions with ONE BINARY - the same
# `write` probe, run twice, differing only in the Int it passes - and
# asserts the file exists in one and does not exist in the other. A
# module that called isatty itself would leave only the "no file"
# direction reachable from a script, and "no file" is exactly what a
# module that writes nothing at all produces. That is the vacuous shape
# this repository refuses, and arm B is the assertion that closes it.
#
# THE COMPILER. This gate builds its probes with `$axiom` rather than
# with `gate_build_axc`, and the difference matters here in the other
# direction from usual: the SUBJECT is `self_host/replhist.ax`, a leaf
# module with no compiler in it, and every probe below is compiled from
# the working tree on every run - so an ablation of the module is
# visible whichever compiler reads it, which is what the four drills at
# the bottom of this header confirm by measurement. `check-net.sh` is
# the precedent for a gate that builds its probe with `$axiom`.
# `gate_init` prints which compiler it resolved, so the choice is never
# invisible.
#
# THE FORMAT IS RE-DERIVED IN PYTHON, below, and never by calling the
# module under test. A gate that decoded the file with `histDecode`
# would agree with any format the module happened to write, including
# one that lost a line break; the Python is the second opinion, and
# `tests/repl/history/basic.hist` - a checked-in golden written by hand
# from the format section of the module's header - is the third.
#
# ABLATION DRILLS, run at introduction on 2026-08-31 against a copy of
# the tree, each a single edit, with the exact failure recorded. A
# drill that does not turn this gate red is a gate defect.
#
#   1. Drop the TAB prefix in `histEncode`, so the file becomes one
#      record per PHYSICAL line - the naive format this one exists to
#      not be. 3 of 18 red:
#        FAIL A2: the file does not match tests/repl/history/basic.hist
#          (the diff shows the leading TABs gone from four lines)
#        FAIL A3+A4+A5: the independent decoder disagrees with the format
#            python decode found 11 entries, want 8
#        FAIL A6: read.ax answered 4 of 14 checks
#      - which is the brief's defect in its own words: eleven records
#      where eight entries were recorded. `tests/selfhost/
#      975-repl-history.ax` answers 31 of 38 against the same edit.
#   2. Make `histOpen` ignore its `interactive` argument. 3 of 18 red -
#      and note that arms A, C and D stay GREEN, which is the whole
#      reason arm B exists:
#        FAIL B2a: write answered 18 non-interactively, want 8
#        FAIL B2b: a history file exists after a non-interactive session
#        FAIL B3: the interactive flag did not decide whether a file appeared
#   3. Make `histKeepLast` keep the OLDEST `cap` entries instead of the
#      newest. The COUNT is still 1000, so only the by-value arm moves,
#      1 of 18 red:
#        FAIL C2: the compacted file is not what the cap promises
#            the newest entry (bulk 1399) is not in the compacted file
#            the oldest entry (bulk 0) is still in the compacted file
#   4. Replace `sysAppendFile` with `sysWriteFile` in `histRecord` -
#      the same bytes, without O_APPEND. 7 of 18 red, including:
#        FAIL D2: concurrent appends lost or corrupted entries
#            tag t1 wrote 200 entries, 0 survived   (t3: 1 survived)
#        FAIL C1: compaction did NOT run - 1400 entries did not cross histMaxBytes
#      Six processes and 1200 entries reduced to one line.
#   5. Make `histClose` compact from THIS SESSION'S RING instead of
#      from the file. Arms A, B, C and D2 all stay green - the file is
#      never rewritten in any of them - and only D3 moves, 1 of 18 red:
#        FAIL D3: a concurrent compaction corrupted or discarded history
#            332 entries survived six concurrent compactions; the floor is 995
#      (and, on another run, "tag c6 has no entries left at all"). This
#      is the drill that says why D3 is a separate arm from D2.
#
# TWO MORE CLAIMS THE COMPILER ITSELF GATES, on every build rather than
# in this script, probed the same way on 2026-08-31:
#   * removing `;@axiom:effect(io)` from `histRecord` draws
#     "error[AX3042]: `histRecord` performs IO and its declaration does
#     not say so";
#   * adding a `sysReadFile` inside `histEncode`, which claims
#     `restrict(no-io)`, draws "error[AX3049]: `histEncode` claims
#     `restrict(no-io)` and the body performs IO: histEncode ->
#     Sys$sysReadFile -> Sys$sysCloseFd -> __syscall1".
#   So the codec staying pure and the file layer saying what it does
#   are refusals, not comments.
#
# Usage:
#   scripts/check-repl-history.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

failed=0
checks=0

ok()   { checks=$((checks + 1)); echo "ok   $*"; }
bad()  { checks=$((checks + 1)); failed=$((failed + 1)); echo "FAIL $*"; }

# The compiler resolves `(import replhist)` against `self_host/`
# relative to its working directory, so both trees have to be reachable
# from where the probes are built. Without them the import fails loudly
# (AX5001), which is the good case; with a STALE copy it would not.
ln -s "$repo_root/stdlib"    "$work/stdlib"
ln -s "$repo_root/self_host" "$work/self_host"

echo "== building the probes from the working tree =="
for probe in write read bulk concurrent; do
  cp "$repo_root/tests/repl/history/$probe.ax" "$work/$probe.ax"
  if ! (cd "$work" && "$axiom" build "$probe.ax" -o "p-$probe") \
        >"$work/build-$probe.log" 2>&1; then
    bad "could not build tests/repl/history/$probe.ax"
    sed -n '1,20p' "$work/build-$probe.log"
    echo "$failed failure(s) in $checks checks"
    exit 1
  fi
done
ok "four probes built"

# The Python decoder: the file format read back by something that is
# not the module under test. Kept to the format's own rules and nothing
# else - first line verbatim, a leading TAB continues the entry with
# exactly one TAB removed, a blank line closes it.
decoder="$work/decode.py"
cat > "$decoder" <<'PY'
import sys
def decode(text):
    out, cur, have = [], None, False
    for line in text.split("\n")[:-1] if text.endswith("\n") else text.split("\n"):
        if line == "":
            if have: out.append(cur)
            cur, have = None, False
        elif line[0] == "\t":
            body = line[1:]
            if have: cur = cur + "\n" + body
            else:    cur, have = body, True
        else:
            if have: out.append(cur)
            cur, have = line, True
    if have: out.append(cur)
    return out
PY

# ---------------------------------------------------------------
# A. THE ROUND TRIP, ACROSS TWO PROCESSES.
#
# `write` records ten entries (two of which must be refused), closes,
# and exits `10*persist + entries`. The file is then compared with a
# hand-written golden, decoded independently in Python, and finally
# read back by a SECOND process that must find every entry.
# ---------------------------------------------------------------
echo "== A: an entry recorded by one process is there for the next =="
a="$work/A"; mkdir -p "$a"
hist="$a/hist"
status=0
(cd "$a" && HOME="$a" XDG_CONFIG_HOME="$a" AXIOM_REPL_HISTORY="$hist" \
   HIST_INTERACTIVE=1 "$work/p-write") || status=$?
if [[ "$status" == 18 ]]; then
  ok "A1: write persisted and kept 8 of 10 records (exit 18)"
else
  bad "A1: write answered $status, want 18 (10*persist + entries)"
fi

if [[ ! -f "$hist" ]]; then
  bad "A2: no history file at $hist"
elif diff -u "$repo_root/tests/repl/history/basic.hist" "$hist" >"$work/A.diff" 2>&1; then
  ok "A2: the file is byte-identical to tests/repl/history/basic.hist"
else
  bad "A2: the file does not match tests/repl/history/basic.hist"
  sed -n '1,30p' "$work/A.diff"
fi

if python3 - "$decoder" "$hist" <<'PY'
import sys
exec(open(sys.argv[1]).read())
entries = decode(open(sys.argv[2], encoding="utf-8").read())
want = ["(+ 1 2)",
        "(fn (f x)\n  (if (> x 0)\n    1 0))",
        "(* 3 4)",
        "(tabbed)\n\t(inner)",
        "(+ 1 2)",
        "(let ((a 1))\n  a)",
        ":type foo",
        "(- 9 5)"]
if len(entries) != len(want):
    print(f"    python decode found {len(entries)} entries, want {len(want)}")
    sys.exit(1)
for i, (g, w) in enumerate(zip(entries, want)):
    if g != w:
        print(f"    entry {i} came back as {g!r}, want {w!r}")
        sys.exit(1)
sys.exit(0)
PY
then ok "A3+A4+A5: an independent decoder recovers all 8 entries, the 3 multi-line ones included"
else bad "A3+A4+A5: the independent decoder disagrees with the format"
fi

status=0
(cd "$a" && HOME="$a" XDG_CONFIG_HOME="$a" AXIOM_REPL_HISTORY="$hist" \
   "$work/p-read") || status=$?
if [[ "$status" == 14 ]]; then
  ok "A6: a fresh process passed all 14 checks against the file"
else
  bad "A6: read.ax answered $status of 14 checks"
fi

# ---------------------------------------------------------------
# B. THE OFF DIRECTIONS - both of them, with the same binary.
#
# B1 is `AXIOM_REPL_HISTORY=off`. B2 is the one that matters: the
# environment is IDENTICAL to arm A's and only `interactive` changes,
# so "no file" cannot be explained by "nothing was configured".
# ---------------------------------------------------------------
echo "== B: history that is off writes nothing, and it is off for a reason =="
b="$work/B"; mkdir -p "$b"
status=0
(cd "$b" && HOME="$b" XDG_CONFIG_HOME="$b" AXIOM_REPL_HISTORY=off \
   HIST_INTERACTIVE=1 "$work/p-write") || status=$?
if [[ "$status" == 8 ]]; then
  ok "B1: AXIOM_REPL_HISTORY=off gives a ring and no persistence (exit 8)"
else
  bad "B1: write answered $status with history off, want 8"
fi

b2="$work/B2"; mkdir -p "$b2"
status=0
(cd "$b2" && HOME="$b2" XDG_CONFIG_HOME="$b2" AXIOM_REPL_HISTORY="$b2/hist" \
   HIST_INTERACTIVE=0 "$work/p-write") || status=$?
if [[ "$status" == 8 ]]; then
  ok "B2a: a non-interactive session persists nothing (exit 8)"
else
  bad "B2a: write answered $status non-interactively, want 8"
fi
found="$(find "$b" "$b2" -type f 2>/dev/null | wc -l | tr -d ' ')"
if [[ "$found" == 0 ]]; then
  ok "B2b: no file was created by either off-direction session"
else
  bad "B2b: a history file exists after a non-interactive session"
  find "$b" "$b2" -type f 2>/dev/null | sed 's/^/    /'
fi

# The pairing. Arm A wrote a file into the same shape of directory with
# the same variables set; the ONLY difference was the Int. Stated
# separately so that a build in which nothing ever writes fails here
# with a message about the pairing rather than passing B and A both.
if [[ -f "$hist" && "$found" == 0 ]]; then
  ok "B3: the same binary wrote a file with interactive=1 and none with 0"
else
  bad "B3: the interactive flag did not decide whether a file appeared"
fi

# ---------------------------------------------------------------
# C. THE CAP AND COMPACTION, BY VALUE.
#
# A count alone cannot tell a trim that kept the newest 1000 from one
# that kept the oldest 1000, so this asks which entries are there.
# ---------------------------------------------------------------
echo "== C: the file is compacted to the cap, keeping the newest =="
c="$work/C"; mkdir -p "$c"
chist="$c/hist"
status=0
(cd "$c" && HOME="$c" XDG_CONFIG_HOME="$c" AXIOM_REPL_HISTORY="$chist" \
   HIST_INTERACTIVE=1 HIST_BULK=1400 "$work/p-bulk") || status=$?
case "$status" in
  42) ok "C1: 1400 entries crossed the threshold, compaction ran, the ring is at its cap" ;;
  43) bad "C1: compaction ran but the ring is not at histMaxEntries" ;;
  44) bad "C1: compaction did NOT run - 1400 entries did not cross histMaxBytes" ;;
  *)  bad "C1: bulk.ax answered $status" ;;
esac

if python3 - "$decoder" "$chist" <<'PY'
import os, sys
exec(open(sys.argv[1]).read())
path = sys.argv[2]
entries = decode(open(path, encoding="utf-8").read())
bad = 0
if len(entries) != 1000:
    print(f"    the compacted file holds {len(entries)} entries, want 1000"); bad += 1
newest = [e for e in entries if e.startswith("(bulk 1399 ")]
oldest = [e for e in entries if e.startswith("(bulk 0 ")]
if not newest:
    print("    the newest entry (bulk 1399) is not in the compacted file"); bad += 1
if oldest:
    print("    the oldest entry (bulk 0) is still in the compacted file"); bad += 1
size = os.path.getsize(path)
if size >= 262144:
    print(f"    the compacted file is {size} bytes, not under histMaxBytes"); bad += 1
sys.exit(1 if bad else 0)
PY
then ok "C2: 1000 entries, the newest kept, the oldest dropped, under histMaxBytes"
else bad "C2: the compacted file is not what the cap promises"
fi

# ---------------------------------------------------------------
# D. TWO REPLS AT ONCE.
#
# Six processes, 200 uniquely-tagged entries each, one file, no
# compaction (1200 short entries stay well under histMaxBytes). The
# assertion is PER PROCESS - each tag's own 200 entries - because
# check-concurrent-run.sh's header records what an aggregate count
# hides: one process reporting another's work, exit 0, empty stderr.
# ---------------------------------------------------------------
echo "== D: six sessions appending to one file lose nothing =="
d="$work/D"; mkdir -p "$d"
dhist="$d/hist"
for i in 1 2 3 4 5 6; do
  ( cd "$d" && HOME="$d" XDG_CONFIG_HOME="$d" AXIOM_REPL_HISTORY="$dhist" \
      HIST_INTERACTIVE=1 HIST_TAG="t$i" "$work/p-concurrent" >/dev/null 2>&1
    echo $? > "$d/rc$i" ) &
done
wait
rcbad=0
for i in 1 2 3 4 5 6; do
  rc="$(cat "$d/rc$i" 2>/dev/null || echo missing)"
  [[ "$rc" == 42 ]] || { echo "    process t$i exited $rc, want 42"; rcbad=1; }
done
if [[ "$rcbad" == 0 ]]; then ok "D1: all six sessions persisted"
else bad "D1: a session did not persist"; fi

if python3 - "$decoder" "$dhist" <<'PY'
import sys
exec(open(sys.argv[1]).read())
entries = decode(open(sys.argv[2], encoding="utf-8").read())
want = {f"(entry t{p} {i})" for p in range(1, 7) for i in range(200)}
seen = {}
for e in entries:
    seen[e] = seen.get(e, 0) + 1
bad = 0
# Per process, its OWN 200 - not "1200 in total", which one process
# writing twice would also satisfy.
for p in range(1, 7):
    mine = [f"(entry t{p} {i})" for i in range(200)]
    have = sum(1 for m in mine if m in seen)
    if have != 200:
        print(f"    tag t{p} wrote 200 entries, {have} survived"); bad += 1
garbled = [e for e in entries if e not in want]
if garbled:
    print(f"    {len(garbled)} decoded entries were written by nobody, e.g. {garbled[0]!r}")
    bad += 1
dupes = [e for e, n in seen.items() if n > 1]
if dupes:
    print(f"    {len(dupes)} entries appear more than once, e.g. {dupes[0]!r}")
    bad += 1
sys.exit(1 if bad else 0)
PY
then ok "D2: all 1200 entries present, none garbled, none duplicated"
else bad "D2: concurrent appends lost or corrupted entries"
fi

# D3: THE SAME SIX, BUT LARGE ENOUGH THAT EVERY ONE OF THEM COMPACTS.
# 1200 entries of ~260 bytes is ~310 KB, over `histMaxBytes`, so every
# process rewrites the file at close instead of only appending to it.
# This is the riskiest path in the module and the one the brief asks
# about, so it is measured rather than argued.
#
# WHAT IS ASSERTED, AND WHY IT IS NOT "EVERY ENTRY SURVIVES". Compaction
# carries a documented one-syscall window - an append landing between
# the size re-check and the rename is lost - so "all 1200" is not a
# property this design HAS, and a gate asserting it would be a gate that
# flakes. What IS guaranteed is that nothing is invented, nothing is
# doubled, and no session's history is wholesale replaced by another's:
# compaction rebuilds from the FILE, so a rewrite by c1 carries c2..c6
# forward. The floor is 995 because the cap alone accounts for the drop
# from 1200 to 1000, and anything below that is not the window - it is
# a session's work being thrown away, which is the failure that must
# not be silent.
echo "== D3: ... and again, large enough that all six compact =="
d3="$work/D3"; mkdir -p "$d3"
d3hist="$d3/hist"
for i in 1 2 3 4 5 6; do
  ( cd "$d3" && HOME="$d3" XDG_CONFIG_HOME="$d3" AXIOM_REPL_HISTORY="$d3hist" \
      HIST_INTERACTIVE=1 HIST_PAD=1 HIST_TAG="c$i" "$work/p-concurrent" >/dev/null 2>&1
    echo $? > "$d3/rc$i" ) &
done
wait
if python3 - "$decoder" "$d3hist" <<'PYD3'
import sys
exec(open(sys.argv[1]).read())
entries = decode(open(sys.argv[2], encoding="utf-8").read())
want = {f"(entry c{p} {i}" for p in range(1, 7) for i in range(200)}
def head(e):
    # `(entry c3 17 000...)` -> `(entry c3 17`, the provenance prefix
    return " ".join(e.split(" ")[:3])
seen = {}
for e in entries:
    seen[head(e)] = seen.get(head(e), 0) + 1
bad = 0
garbled = [h for h in seen if h not in want]
if garbled:
    print(f"    {len(garbled)} decoded entries were written by nobody, e.g. {garbled[0]!r}")
    bad += 1
dupes = [h for h, n in seen.items() if n > 1]
if dupes:
    print(f"    {len(dupes)} entries appear more than once, e.g. {dupes[0]!r}")
    bad += 1
if len(entries) < 995:
    print(f"    {len(entries)} entries survived six concurrent compactions; the floor is 995")
    bad += 1
# Every process must still be represented. A rewrite that replaced the
# file with one session's own ring would leave exactly one tag standing,
# and that is the failure this arm exists for.
for p in range(1, 7):
    mine = sum(1 for h in seen if h.startswith(f"(entry c{p} "))
    if mine == 0:
        print(f"    tag c{p} has no entries left at all")
        bad += 1
sys.exit(1 if bad else 0)
PYD3
then ok "D3: six concurrent compactions - nothing invented, nothing doubled, every session still present"
else bad "D3: a concurrent compaction corrupted or discarded history"
fi

# ---------------------------------------------------------------
# E. THE STATIC FLOOR - two spellings that are bugs rather than style,
# anchored at one named file so a rename shows up as a missing match.
# ---------------------------------------------------------------
echo "== E: the two spellings that are bugs are not in the module =="
mod="$repo_root/self_host/replhist.ax"

# CODE, NOT PROSE. `sed 's/;.*$//'` first, the same way
# check-doc-drift.sh reads construction sites out of `self_host/*.ax`:
# this module's header EXPLAINS both hazards below by name, and a sweep
# that read the comments would refuse the file for documenting the bug
# it does not have. Measured on this gate's first run - both refusals
# fired, on their own explanations. Line numbers survive the strip
# because `sed` deletes the tail of a line and never the line.
code="$work/replhist.code"
sed 's/;.*$//' "$mod" > "$code"

# `sysEnv`'s answer SHARES the environment block and is not
# NUL-terminated (Sys.ax:912-915), so handing it to a syscall as a path
# reads on into the next environment string.
if grep -nE '\((strData|strCStr) \(sysEnv' "$code" >/dev/null; then
  bad "E1: replhist.ax hands a raw sysEnv slice to a syscall"
  grep -nE '\((strData|strCStr) \(sysEnv' "$code" | sed 's/^/    /'
else
  ok "E1: no un-copied sysEnv value reaches a syscall"
fi

# `driver$fmtIntStr` renders 0, 1, 2, 3 and answers "1" for everything
# else; using it for a pid is what made every REPL on one machine write
# to one scratch name (repl.ax:752-766).
if grep -n 'fmtIntStr' "$code" >/dev/null; then
  bad "E2: replhist.ax uses fmtIntStr, which renders only 0..3"
else
  ok "E2: fmtIntStr is not used"
fi
if grep -n 'decStr sysGetPid' "$code" >/dev/null; then
  ok "E3: the compaction temp name carries a decStr-rendered pid"
else
  bad "E3: the compaction temp name no longer carries a decStr pid"
fi

# THE GREPS ARE PROVEN ABLE TO FIRE. Two patterns that must match
# nothing are two patterns a typo would also make match nothing, and a
# check that cannot fail is the defect this repository names most
# often. So each is run against a planted line that it must find.
planted="$work/planted.ax"
printf '%s\n' '(fn (x) (sysOpenPath (strCStr (sysEnv "HOME")) 0))' \
              '(fn (y) (fmtIntStr 7))' > "$planted"
sed -i.bak 's/;.*$//' "$planted"
if grep -qE '\((strData|strCStr) \(sysEnv' "$planted" && grep -q 'fmtIntStr' "$planted"; then
  ok "E4: both refusals match a planted example, so they can fail"
else
  bad "E4: a refusal pattern does not match its own planted example"
fi

echo
if (( failed )); then
  echo "$failed failure(s) in $checks checks"
  exit 1
fi
echo "all $checks checks passed"
