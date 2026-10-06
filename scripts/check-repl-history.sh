#!/usr/bin/env bash
# Check that the REPL's history survives the process that wrote it, and
# that two REPLs at once do not lose each other's entries.
#
# `tests/selfhost/979-repl-history.ax` covers the codec, ring, browsing
# and reverse search without a filesystem, and passes even with
# `sysAppendFile` deleted. Telling a written file from a live ring needs
# two processes.
#
# `histOpen` (self_host/replhist.ax) takes `interactive` as an Int and
# never checks for a terminal itself. A module that called isatty would
# show a script only the "no file" direction, which a module that writes
# nothing also produces. So one `write` binary, run with each value, must
# create the file once and not the other time, and arm B holds that.
#
# The probes are built with `$axiom`, not `gate_build_axc`: the subject
# is a leaf module with no compiler in it, compiled from the working
# tree into every probe, so any compiler sees an edit to it.
# `check-net.sh` does the same.
#
# The format is decoded independently in Python, never with
# `histDecode`, which would agree with any format the module wrote.
# `tests/repl/history/basic.hist`, written by hand from the module's
# format notes, is a third opinion.
#
# Ablation drills. Each single edit below, made to a copy of the tree,
# must turn this gate red. A drill that does not is a gate defect.
#
#   1. Drop the TAB prefix in `histEncode`, so each physical line is a
#      record. A2, A3+A4+A5 and A6 fail: eleven records where eight
#      entries were written.
#   2. Make `histOpen` ignore `interactive`. B2a, B2b and B3 fail, while
#      arms A, C and D stay green, which is why arm B exists.
#   3. Make `histKeepLast` keep the oldest `cap` entries. The count is
#      still 1000, so only C2, which checks entries by value, fails.
#   4. Use `sysWriteFile` instead of `sysAppendFile` in `histRecord`:
#      the same bytes without O_APPEND. Several arms fail, among them D2
#      with entries lost and C1.
#   5. Make `histClose` compact from the session's ring instead of from
#      the file. Only D3 fails, which is why D3 is separate from D2.
#
# The compiler enforces two more claims on every build:
#   * removing `;@axiom:effect(io)` from `histRecord` draws AX3042;
#   * adding a `sysReadFile` inside `histEncode`, which claims
#     `restrict(no-io)`, draws AX3049.
# So the codec stays pure and the file layer declares its IO.
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

export AXIOM_PATH="$repo_root/self_host${AXIOM_PATH:+:$AXIOM_PATH}"

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

# The Python decoder reads the format by its own rules and nothing else:
# the first line verbatim, a leading TAB continues the entry with exactly
# one TAB removed, and a blank line closes it.
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
# A. The round trip, across two processes.
#
# `write` records ten entries, two of which must be refused, closes, and
# exits `10*persist + entries`. The file is compared with a hand-written
# golden, decoded independently in Python, and read back by a second
# process that must find every entry.
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
# B. History that is off, both ways, with the same binary.
#
# B1 sets `AXIOM_REPL_HISTORY=off`. B2 matters more: the environment is
# identical to arm A's and only `interactive` changes, so "no file"
# cannot be explained by "nothing was configured".
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
# the same variables set, and only the Int differed. It is checked
# separately so a build that never writes fails with a message about the
# pairing.
if [[ -f "$hist" && "$found" == 0 ]]; then
  ok "B3: the same binary wrote a file with interactive=1 and none with 0"
else
  bad "B3: the interactive flag did not decide whether a file appeared"
fi

# ---------------------------------------------------------------
# C. The cap and compaction, by value.
#
# A count alone cannot tell a trim that kept the newest 1000 from one
# that kept the oldest 1000, so this checks which entries are there.
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
# D. Two REPLs at once.
#
# Six processes append 200 uniquely tagged entries each to one file.
# 1200 short entries stay well under histMaxBytes, so nothing compacts.
# The check is per process, each tag's own 200, because an aggregate
# count hides one process reporting another's work (see
# check-concurrent-run.sh).
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

# D3: the same six, with entries large enough that every process
# compacts. 1200 entries of about 260 bytes exceed `histMaxBytes`, so
# each process rewrites the file at close instead of only appending.
# This is the module's riskiest path.
#
# Not every entry survives. Compaction has a documented one-syscall
# window: an append landing between the size re-check and the rename is
# lost, so requiring all 1200 would flake. What is guaranteed is that
# nothing is invented, nothing is doubled, and no session's history is
# replaced by another's, because compaction rebuilds from the file. The
# cap accounts for the drop to 1000, and the floor of 995 allows for the
# window. Anything lower means a session's work was thrown away.
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
# E. Two spellings that are bugs, checked in one named file so a rename
# shows up as a missing match.
# ---------------------------------------------------------------
echo "== E: the two spellings that are bugs are not in the module =="
mod="$repo_root/self_host/replhist.ax"

# Search code, not comments. `sed 's/;.*$//'` strips them the way
# check-doc-drift.sh reads construction sites in `self_host/*.ax`. The
# module's header names both hazards, and a search that read comments
# would refuse the file for documenting them. Line numbers survive,
# because `sed` deletes the tail of a line and never the line.
code="$work/replhist.code"
sed 's/;.*$//' "$mod" > "$code"

# `sysEnv`'s answer shares the environment block and is not
# NUL-terminated, so passing it to a syscall as a path reads on into the
# next environment string.
if grep -nE '\((strData|strCStr) \(sysEnv' "$code" >/dev/null; then
  bad "E1: replhist.ax hands a raw sysEnv slice to a syscall"
  grep -nE '\((strData|strCStr) \(sysEnv' "$code" | sed 's/^/    /'
else
  ok "E1: no un-copied sysEnv value reaches a syscall"
fi

# `driver$fmtIntStr` renders 0, 1, 2 and 3 and answers "1" for anything
# else. Used for a pid, it gives every REPL on a machine the same
# scratch name.
if grep -n 'fmtIntStr' "$code" >/dev/null; then
  bad "E2: replhist.ax uses fmtIntStr, which renders only 0..3"
else
  ok "E2: fmtIntStr is not used"
fi
if grep -n 'fmtInt sysGetPid' "$code" >/dev/null; then
  ok "E3: the compaction temp name carries a fmtInt-rendered pid"
else
  bad "E3: the compaction temp name no longer carries a fmtInt pid"
fi

# Prove the searches can fire. A pattern that must match nothing would
# also match nothing after a typo, so each runs against a planted line
# it must find.
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
