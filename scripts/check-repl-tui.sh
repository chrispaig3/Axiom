#!/usr/bin/env bash
# The REPL's terminal interface, on a terminal.
#
# WHY THIS GATE EXISTS. `replInteractive` is true only when fd 0 AND
# fd 1 are terminals, and every gate in this repository runs its
# subject with both on a pipe. So the decoder, the editor, the redraw
# and the raw-mode bracket are, to the entire existing battery,
# unreachable code that is green because nothing runs it - the same
# hole `check-terminal-restore.sh` was written to close one layer
# further down, and for the same reason. This drives the REPL on a
# pseudo-terminal it allocates itself and asserts what lands on the
# screen.
#
# THE ONE CONSTRAINT THAT MAKES ANY OF THIS SAFE is not checked here.
# `check-repl-selfhost.sh` pins the PIPED surface byte for byte across
# 14 sessions and that is the contract; this gate is its inverse and
# the two are only meaningful together. Layer 1 below runs the same
# session BOTH ways and requires them to DIFFER, because "no escapes
# off a TTY" and "escapes on one" are each satisfied by a build in
# which the other side is dead code.
#
# ------------------------------------------------------------------
# SAFETY. IT NEVER TOUCHES THE CALLER'S TERMINAL.
#
#   1. Everything interactive runs against a pty from `pty.openpty()`.
#      The child's fd 0, 1 and 2 are the slave end; the invoking
#      shell's descriptors are never handed to anything that calls
#      `sysTermRaw`.
#   2. The driver restores the pty under `try/finally` on every exit
#      path, and this script arms a `trap` that puts the CALLER's
#      terminal back if it had one. That second trap defends against a
#      future edit to this file rather than against anything it does
#      today: a gate that reports a failure and leaves the developer
#      in raw mode has done more damage than the bug it found.
#   3. It never runs a bare `waitpid`. A REPL left in raw mode with
#      nothing to read blocks forever, and a gate that hangs where it
#      should fail is worse than no gate.
# ------------------------------------------------------------------
#
# WHEN IT CANNOT RUN, IT FAILS. It does not skip. `python3` is already
# a hard dependency of check-repl-selfhost.sh's own layer 4a and of
# twenty other gates, and a pty is available to any process that can
# open /dev/ptmx. "Cannot run here" is reported with the battery's
# words - `NOT RUN HERE (1), needs ...` - AND a non-zero exit, for the
# reason check-terminal-restore.sh spells out at length: a gate that
# returns 0 when it could not run reads as coverage.
#
# IT RUNS IN PARALLEL WITH EVERYTHING, INCLUDING THE OTHER REPL GATE,
# and that is a measurement rather than an assumption.
# check-repl-selfhost.sh's header carried a HAZARD saying otherwise -
# every REPL on the machine writing /tmp/axiom-repl-1 because
# `fmtIntStr` answers "1" above 3 - and this gate was written to obey
# it. The hazard had been fixed twice before it was read: repl.ax uses
# `decStr` for the pid and a private `<tmp>/axiom-repl-<pid>.d` at mode
# 0700. Probed 2026-08-31: six `axiom repl` processes at once answered
# 101, 202, 303, 404, 505 and 606, and left nothing in /tmp. Both
# headers now say so, and neither gate is in run-gates.sh's serial
# list.
#
# ABLATION DRILLS, run at introduction 2026-08-31 with their OBSERVED
# results, because a layer whose comment claims more than the layer
# checks is the defect this repository records most often.
#
#   A. `replInteractive` pinned to 0, so the interactive branch is
#      dead. 15 of 38 checks FAILED, and the first of them named the
#      cause: "pty: 0 ESC bytes. Either replInteractive answered false
#      on a real terminal, or the driver's child did not get the pty."
#      Layer 2 went red (Ctrl-C reached the kernel and killed the
#      child), layer 3 stalled at step 0 with no `result 13`, `9`, `3`,
#      `15` or `42`, and layer 4's Ctrl-D path never exited.
#
#      THIS DRILL FOUND A WEAK CHECK, which is what a drill is for.
#      Layer 1's "the two transcripts DIFFER" PASSED under it, because
#      a pty in cooked mode expands every LF into CR LF and the two
#      streams differ by carriage returns alone even when the editor
#      never ran. It now compares them CR-stripped, and fails.
#
#      It also found that the driver's single 180-second budget made a
#      wholly broken build take minutes to report. Each step now has
#      its own 25-second stall deadline.
#
#   B. The forced `\n\r` at `C % W == 0` deleted from
#      `ledRefreshFull`. EXACTLY 2 of 42 checks failed, both of them
#      the phantom column and nothing else:
#          FAIL [W=20, content exactly one row]    cursor 0,0 want 1,0
#          FAIL [W=20, content exactly three rows] cursor 2,0 want 3,0
#      The mid-row cases stayed green, the GRID stayed correct in both
#      failing cases - the text looked right and only the cursor was a
#      row high, which is exactly why this bug survives review - and
#      layers 1, 2, 3, 4 and 6 stayed green. So did
#      `scripts/check-repl-selfhost.sh`, run under the same ablation:
#      "14 sessions passed (10 byte, 4 shape), 8 cross-path cases, all
#      checks passed". That is the measured proof that layer 5 sees
#      something no other check in this repository can: the deferred
#      wrap is invisible to anything that does not model a terminal.
#
#   C. `ledLeft` made a no-op. 6 of 38 checks failed, ALL of them in
#      layer 3 - no `result 13` (the arrows did not move), and then no
#      `result 9`, `3`, `15` or `42` because Ctrl-A is built from
#      `ledLeft` and the line was never cleared. Layers 1, 2, 4, 5 and
#      6 stayed green.
#
# Usage:  scripts/check-repl-tui.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

# SAFETY NET (see the block above).
caller_tty_state=""
if [[ -t 0 ]]; then caller_tty_state="$(stty -g 2>/dev/null || true)"; fi
restore_caller_tty() {
  [[ -n "$caller_tty_state" ]] && stty "$caller_tty_state" 2>/dev/null || true
}
trap restore_caller_tty EXIT INT TERM

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

command -v python3 >/dev/null || {
  echo "NOT RUN HERE (1), needs python3 to allocate a pty: python3 is not on PATH"
  echo "     This gate does not skip. See the header."
  exit 1
}

drive="$repo_root/tests/repl/tui/drive.py"
screen="$repo_root/tests/repl/tui/screen.py"
for f in "$drive" "$screen"; do
  [[ -f "$f" ]] || { bad "missing $f"; echo "check-repl-tui: 1 of 1 checks FAILED"; exit 1; }
done

# The prompt's visible width, which the driver's readiness marker and
# every expected grid below depend on. Read from the SOURCE rather
# than written down twice, so a prompt that changes width fails here
# with its own message instead of as a mysterious timeout.
pcols="$(python3 - "$repo_root/self_host/repl.ax" <<'PYX'
import re, sys
src = open(sys.argv[1]).read()
m = re.search(r'\(pub fn \(replPromptMain\) \(paint \w+ "([^"]*)"\)\)', src)
print(len(m.group(1)) if m else -1)
PYX
)"
if [[ "$pcols" == 7 ]]; then
  ok "the prompt is $pcols visible columns, which is what the driver waits for and the screen model assumes"
else
  bad "replPromptMain is $pcols columns, not 7 - the driver's readiness marker and every expected grid below are wrong"
  echo "     Fix tests/repl/tui/drive.py's \`park\` and this script's specs together."
fi

# run_pty <rows> <cols> <script.json> <tag>
#   -> $work/<tag>.bin (transcript), $work/<tag>.err (PY_ findings)
run_pty() {
  local rows="$1" cols="$2" script="$3" tag="$4" rc=0
  (cd "$work" && HOME="$work" XDG_CONFIG_HOME="$work" \
     python3 "$drive" "$work/axc" "$rows" "$cols" "$script" \
       >"$work/$tag.bin" 2>"$work/$tag.err") || rc=$?
  if (( rc == 3 )); then
    echo "NOT RUN HERE (1), needs a pty this process may allocate:"
    echo "     python3's pty.openpty() failed - /dev/ptmx is unavailable here."
    echo "     This gate does not skip; to exclude it deliberately, name it in"
    echo "     scripts/run-gates.sh's NOTRUN_RE, which is a reviewed edit."
    exit 1
  fi
  return $rc
}

v() { sed -n "s/^$2=//p" "$1" | tail -1 | tr -d '\r'; }

# `mkscript` builds a driver script from a compact spec so that the
# byte literals are written once, in Python, and not escaped twice
# through JSON by hand.
mkscript() { python3 - "$1"; }

esc_count() { LC_ALL=C python3 -c "import sys;print(open(sys.argv[1],'rb').read().count(b'\x1b'))" "$1"; }
has()       { LC_ALL=C python3 -c "import sys;sys.exit(0 if sys.argv[2].encode() in open(sys.argv[1],'rb').read() else 1)" "$1" "$2"; }

# =================================================================
echo "== layer 1: the two surfaces, and both of them run =="
# =================================================================
printf '(+ 1 2)\n:quit\n' > "$work/s.txt"
(cd "$work" && HOME="$work" XDG_CONFIG_HOME="$work" \
   "$work/axc" repl --no-banner <"$work/s.txt" >"$work/pipe.bin" 2>"$work/pipe.err")
piperc=$?

mkscript "$work/l1.json" <<'PYX'
import json, sys
json.dump([["prompt"],
           ["send", "b'(+ 1 2)\\r'"], ["prompt"],
           ["send", "b':quit\\r'"], ["exit"]], open(sys.argv[1], "w"))
PYX
run_pty 24 80 "$work/l1.json" ptyrun
ptyrc=$?

if [[ "$piperc" == 0 && ! -s "$work/pipe.err" ]]; then
  ok "piped: exit 0, stderr empty"
else
  bad "piped: exit $piperc, stderr $(wc -c <"$work/pipe.err" | tr -d ' ')B"
fi

pipe_esc="$(esc_count "$work/pipe.bin")"
pty_esc="$(esc_count "$work/ptyrun.bin")"
if [[ "$pipe_esc" == 0 ]]; then
  ok "piped: 0 ESC bytes - the editor wrote nothing off a TTY"
else
  bad "piped: $pipe_esc ESC bytes reached a pipe. The interactive branch ran where it must not,"
  echo "     and check-repl-selfhost.sh's 10 byte goldens are about to disagree too."
fi
if (( pty_esc > 0 )); then
  ok "pty: $pty_esc ESC bytes - the editor really painted"
else
  bad "pty: 0 ESC bytes. Either replInteractive answered false on a real terminal, or the"
  echo "     driver's child did not get the pty. Every check below would pass vacuously."
fi
# CR-STRIPPED, and that is not a nicety. A pty in cooked mode expands
# every LF the REPL writes into CR LF, so the two transcripts differ by
# carriage returns alone even when the editor never ran - measured
# while ablating `replInteractive` to false, where this check passed
# and said the two branches both executed. Stripping CR removes the
# terminal's own contribution and leaves only the editor's.
LC_ALL=C tr -d '\r' < "$work/pipe.bin" > "$work/pipe.nocr"
LC_ALL=C tr -d '\r' < "$work/ptyrun.bin" > "$work/pty.nocr"
if ! cmp -s "$work/pipe.nocr" "$work/pty.nocr"; then
  ok "the two transcripts DIFFER by more than the terminal's own CRs - both branches execute"
else
  bad "with carriage returns removed the pty transcript EQUALS the piped one. The"
  echo "     interactive branch produced nothing of its own, so it is dead code and"
  echo "     'no escapes off a TTY' is satisfied by a REPL with no editor at all."
fi
if [[ "$(v "$work/ptyrun.err" PY_EXIT)" == 0 ]]; then
  ok "pty: :quit exited 0"
else
  bad "pty: exit $(v "$work/ptyrun.err" PY_EXIT) (killed=$(v "$work/ptyrun.err" PY_CHILD_KILLED))"
  sed 's/^/     /' "$work/ptyrun.err" | head -12
fi
if has "$work/ptyrun.bin" "result 3"; then
  ok "pty: the session evaluated - 'result 3'"
else
  bad "pty: no 'result 3' in the transcript"
fi

# =================================================================
echo
echo "== layer 2: raw mode is really entered (Ctrl-C is a KEY, not a signal) =="
# =================================================================
# `sysTermRaw` is called with keepSignals 0, which clears ISIG. Byte 3
# is then an ordinary key the editor turns into a cancelled line, and
# the REPL survives to answer the next expression. If raw mode were
# NOT entered, the kernel turns byte 3 into SIGINT, the child dies,
# and there is no `result 3` and no clean exit.
mkscript "$work/l2.json" <<'PYX'
import json, sys
json.dump([["prompt"],
           ["send", "b'(+ 9999'"], ["quiet", 300],
           ["send", "b'\\x03'"], ["prompt"],
           ["send", "b'(+ 1 2)\\r'"], ["prompt"],
           ["send", "b':quit\\r'"], ["exit"]], open(sys.argv[1], "w"))
PYX
run_pty 24 80 "$work/l2.json" ctrlc
if [[ "$(v "$work/ctrlc.err" PY_EXIT)" == 0 ]] && has "$work/ctrlc.bin" "result 3"; then
  ok "Ctrl-C cancelled the line and the session survived to answer 'result 3'"
else
  bad "Ctrl-C killed the REPL, so ISIG was still set: raw mode was not entered."
  echo "     exit=$(v "$work/ctrlc.err" PY_EXIT) killed=$(v "$work/ctrlc.err" PY_CHILD_KILLED)"
fi
if has "$work/ctrlc.bin" '^C'; then
  ok "and it echoed ^C, so the abort was the editor's and not the kernel's"
else
  bad "no ^C echo - the abandoned line was not announced"
fi
if has "$work/ctrlc.bin" "9999"; then
  ok "the abandoned text had been drawn before Ctrl-C took it away"
else
  bad "the text typed before Ctrl-C never appeared on screen at all"
fi

# =================================================================
echo
echo "== layer 3: the decoder and the editor are live on a real terminal =="
# =================================================================
# Each of these produces a value that only a WORKING path can produce.
#   arrows:    (+ 111 2) with three Lefts and a Delete is 13, not 113
#   ctrl-a/k:  a killed line leaves nothing behind, so the answer is 9
#   utf-8:     one Backspace removes a CHARACTER; removing one BYTE of
#              `é` leaves a stray 0xC3 and the parse fails
#   alt-b:     a word motion lands before `111`, not inside it
mkscript "$work/l3.json" <<'PYX'
import json, sys
json.dump([["prompt"],
           # arrows and Backspace: (+ 111 2) -> (+ 11 2)
           ["send", "b'(+ 111 2)'"], ["quiet", 250],
           ["send", "b'\\x1b[D'"], ["send", "b'\\x1b[D'"], ["send", "b'\\x1b[D'"],
           ["quiet", 250],
           ["send", "b'\\x7f\\r'"], ["prompt"],
           # Ctrl-A then Ctrl-K: the half-typed line leaves nothing behind
           ["send", "b'(+ 12 3)'"], ["quiet", 250],
           ["send", "b'\\x01'"], ["send", "b'\\x0b'"], ["quiet", 250],
           ["send", "b'(+ 4 5)\\r'"], ["prompt"],
           # one Backspace over a 2-byte character removes the CHARACTER
           ["send", "b'(+ 1 2)\\xc3\\xa9'"], ["quiet", 250],
           ["send", "b'\\x7f\\r'"], ["prompt"],
           # Alt-b twice lands before `12345`; Alt-d kills the whole word
           ["send", "b'(+ 12345 7)'"], ["quiet", 250],
           ["send", "b'\\x1bb'"], ["send", "b'\\x1bb'"], ["quiet", 250],
           ["send", "b'\\x1bd'"], ["quiet", 250],
           ["send", "b'8\\r'"], ["prompt"],
           # A LONE ESC, sent on its own and left to time out. It must
           # resolve to the Escape key - unbound, so nothing happens -
           # and the `)` that follows 300ms later must be an ordinary
           # character. A decoder that held the prefix would read
           # Alt-`)`, insert nothing, and leave the form unbalanced;
           # the next ["prompt"] would then never arrive, because the
           # REPL would be showing the continuation prompt instead.
           ["send", "b'(+ 40 2'"], ["quiet", 250],
           ["send", "b'\\x1b'"], ["quiet", 300],
           ["send", "b')\\r'"], ["prompt"],
           ["send", "b':quit\\r'"], ["exit"]], open(sys.argv[1], "w"))
PYX
run_pty 24 80 "$work/l3.json" edit
if [[ "$(v "$work/edit.err" PY_STEPS_DONE)" == "$(v "$work/edit.err" PY_STEPS_TOTAL)" ]]; then
  ok "the driver completed all $(v "$work/edit.err" PY_STEPS_TOTAL) steps"
else
  bad "the driver stalled at step $(v "$work/edit.err" PY_STEPS_DONE) of $(v "$work/edit.err" PY_STEPS_TOTAL)"
  sed 's/^/     /' "$work/edit.err" | head -12
fi
probe_edit() {   # probe_edit <want-substring> <what it proves> <what it means if absent>
  if has "$work/edit.bin" "$1"; then
    ok "$2"
  else
    bad "$3 (no '$1' in the transcript)"
  fi
}
probe_edit "result 13"  "three CSI Lefts then Backspace turned (+ 111 2) into (+ 11 2)" \
                        "the arrow keys or Backspace did not edit"
probe_edit "result 9"   "Ctrl-A then Ctrl-K erased the half-typed line" \
                        "Ctrl-A or Ctrl-K did not work"
probe_edit "result 3"   "Backspace removed the whole 2-byte 'é', not one byte of it" \
                        "Backspace split a multi-byte character"
probe_edit "result 15"  "Alt-b moved by WORD, twice, and Alt-d killed the word it landed on" \
                        "the Alt- prefix, the word motion or the word kill is wrong"
probe_edit "result 42"  "a lone ESC timed out into the Escape key, and the next byte was an ordinary character" \
                        "a lone ESC was held as a sequence prefix and swallowed the key after it"
if has "$work/edit.bin" "result 113"; then
  bad "'result 113' is present: the three Lefts were ignored and the text was typed unedited"
else
  ok "'result 113' is absent, so the Lefts were not silently dropped"
fi
if has "$work/edit.bin" "Parse error" || has "$work/edit.bin" "Type error"; then
  bad "the session produced an error line - an escape sequence or a character byte reached the buffer"
  LC_ALL=C grep -a -m3 -E 'Parse error|Type error' "$work/edit.bin" | sed 's/^/     /'
else
  ok "no parse or type error anywhere: no escape sequence was typed into the line"
fi

# =================================================================
echo
echo "== layer 4: the terminal comes back, on both exit paths =="
# =================================================================
# `check-terminal-restore.sh` proves the primitive. This proves that
# THE REPL uses it correctly - including that `:quit`'s `sysExitWith
# 0`, which fires from deep inside the colon dispatch, lands in cooked
# mode and so cannot leak raw.
check_restored() {   # check_restored <tag> <label>
  local t="$1" l="$2"
  if [[ "$(v "$work/$t.err" PY_TERMIOS_EXACT)" == 1 ]]; then
    ok "[$l] the kernel's own attributes are byte-identical to what they were before"
  else
    bad "[$l] the terminal was NOT restored: echo=$(v "$work/$t.err" PY_ECHO_AFTER) icanon=$(v "$work/$t.err" PY_ICANON_AFTER) isig=$(v "$work/$t.err" PY_ISIG_AFTER)"
  fi
  if [[ "$(v "$work/$t.err" PY_ECHO_AFTER)" == 1 && "$(v "$work/$t.err" PY_ICANON_AFTER)" == 1 && "$(v "$work/$t.err" PY_ISIG_AFTER)" == 1 ]]; then
    ok "[$l] ECHO, ICANON and ISIG are all back on - a shell inherited from here is usable"
  else
    bad "[$l] the user would be left with a terminal that does not echo"
  fi
}
check_restored ptyrun ":quit"

mkscript "$work/l4.json" <<'PYX'
import json, sys
json.dump([["prompt"], ["send", "b'\\x04'"], ["exit"]], open(sys.argv[1], "w"))
PYX
run_pty 24 80 "$work/l4.json" ctrld
check_restored ctrld "Ctrl-D"
if [[ "$(v "$work/ctrld.err" PY_EXIT)" == 0 ]] && has "$work/ctrld.bin" "Goodbye!"; then
  ok "[Ctrl-D] on an empty buffer ended the session through replMain's own farewell path"
else
  bad "[Ctrl-D] did not end the session cleanly: exit=$(v "$work/ctrld.err" PY_EXIT)"
fi

# =================================================================
echo
echo "== layer 5: the redraw is correct where the line WRAPS =="
# =================================================================
# The screen is modelled INDEPENDENTLY, twice over: tests/repl/tui/
# screen.py replays the editor's real bytes onto a grid with a
# terminal's deferred-wrap rule, and separately COMPUTES the grid the
# key script implies with plain string slicing. Neither side is a
# checked-in value, so there is nothing an AXIOM_BLESS could launder.
#
# The widths and lengths are chosen so that one case lands the content
# EXACTLY on a row boundary - the phantom column, where a terminal
# holds the cursor at column W with the wrap pending. That case is the
# reason ledRefreshFull emits a forced newline, and drill B above is
# it being removed.
wrap_case() {   # wrap_case <cols> <text> <label>
  local cols="$1" text="$2" label="$3"
  python3 - "$work/w.json" "$text" <<'PYX' > /dev/null
import json, sys
json.dump([["prompt"],
           ["send", "b'%s'" % sys.argv[2]], ["quiet", 400], ["mark", "at"],
           ["send", "b'\\x01'"], ["send", "b'\\x0b'"], ["quiet", 300],
           ["send", "b'\\x04'"], ["exit"]], open(sys.argv[1], "w"))
PYX
  run_pty 24 "$cols" "$work/w.json" "wrap$cols"
  local off; off="$(v "$work/wrap$cols.err" PY_MARK_at)"
  if [[ -z "$off" ]]; then
    bad "[$label] the driver never reached the measurement point"
    sed 's/^/     /' "$work/wrap$cols.err" | head -10
    return
  fi
  python3 -c "
import json,sys
json.dump({'rows':24,'cols':int(sys.argv[2]),'prompt':'axiom> ','typed':sys.argv[3]}, open(sys.argv[1],'w'))
" "$work/spec.json" "$cols" "$text"
  python3 "$screen" "$work/spec.json" "$work/wrap$cols.bin" "$off" > "$work/screen$cols.log" 2>&1
  local cur grid unk
  cur="$(v "$work/screen$cols.log" MODEL_CURSOR_OK)"
  grid="$(v "$work/screen$cols.log" MODEL_GRID_OK)"
  unk="$(v "$work/screen$cols.log" MODEL_UNKNOWN)"
  if [[ "$unk" == 0 ]]; then
    ok "[$label] every byte the editor emitted is in the modelled vocabulary"
  else
    bad "[$label] the editor emitted $unk sequence(s) the model does not know: $(v "$work/screen$cols.log" MODEL_UNKNOWN_WHAT)"
  fi
  if [[ "$grid" == 1 ]]; then
    ok "[$label] the wrapped text on screen is what the key script implies"
  else
    bad "[$label] the screen does not hold the expected text"
    sed -n 's/^ROW/     ROW/p' "$work/screen$cols.log" | head -8
  fi
  if [[ "$cur" == 1 ]]; then
    ok "[$label] and the cursor is at $(v "$work/screen$cols.log" WANT_CURSOR)"
  else
    bad "[$label] the cursor is at $(v "$work/screen$cols.log" MODEL_CURSOR), want $(v "$work/screen$cols.log" WANT_CURSOR)"
    echo "     A row too high here is the deferred wrap: the content ends exactly on a"
    echo "     row boundary and the forced newline in ledRefreshFull is missing or wrong."
  fi
}
# 7 + 13 = 20 = 1 x 20. THE PHANTOM COLUMN.
wrap_case 20 "abcdefghijklm"                             "W=20, content exactly one row"
# 7 + 53 = 60 = 3 x 20. THE PHANTOM COLUMN, three rows down.
wrap_case 20 "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0" "W=20, content exactly three rows"
# 7 + 46 = 53, which is 2 rows and 13 columns: an ordinary mid-row cursor.
wrap_case 20 "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRST" "W=20, mid-row"
# An odd width nothing else in this file uses, so no arithmetic here
# can be accidentally right only for 20.
wrap_case 37 "abcdefghijklmnopqrstuvwxyzABCDEFGHIJ"      "W=37, mid-row"
wrap_case 37 "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefg" "W=37, content exactly two rows"

# =================================================================
echo
echo "== layer 6: structural, and mostly free from the compiler =="
# =================================================================
# `restrict` is transitive and typecheck.ax answers a violation with
# AX3049 at SEV_ERROR, so a `sysWriteFd` added to any decoder or
# editor function fails the BUILD and the whole battery goes red - not
# one script. These greps catch the direction the compiler cannot: a
# function added WITHOUT the claim, which is never asked.
tty_sites="$(LC_ALL=C grep -rl 'sysIsatty' "$repo_root"/self_host/*.ax | wc -l | tr -d ' ')"
tty_lines="$(LC_ALL=C grep -rh 'sysIsatty' "$repo_root"/self_host/*.ax | wc -l | tr -d ' ')"
if [[ "$tty_lines" == 1 && "$tty_sites" == 1 ]]; then
  ok "the tty predicate is written EXACTLY once across self_host/ (1 line, 1 file)"
else
  bad "sysIsatty appears on $tty_lines line(s) in $tty_sites file(s), want exactly 1 and 1."
  echo "     A second test downstream is how the two surfaces start diverging in places"
  echo "     no gate looks. The one place is replInteractive."
  LC_ALL=C grep -rn 'sysIsatty' "$repo_root"/self_host/*.ax | sed 's/^/     /'
fi
for m in Keys Edit; do
  if LC_ALL=C grep -q '^(import Sys)' "$repo_root/stdlib/Tui/$m.ax"; then
    bad "stdlib/Tui/$m.ax imports Sys - it is supposed to be unable to touch a descriptor even by accident"
  else
    ok "stdlib/Tui/$m.ax does not import Sys"
  fi
done

# THE TUI IS STANDARD LIBRARY, AND MUST NOT REACH BACK INTO THE
# COMPILER. That is the whole reason it lives in stdlib/Tui rather than
# self_host: a library any Axiom program can use, with the REPL as its
# first caller rather than its owner. One `(import lexer)` for a word
# rule, or one `(import diag)` for a decimal formatter, and it is a
# compiler module again wearing a different path. The two rules it
# WOULD have borrowed - the word boundary and the display width - are a
# caller-supplied `wordChars` and `tuiVisLen`, and
# tests/selfhost/978-line-editor.ax sweeps both against the compiler's
# own statements so that independence does not become drift.
compiler_mods="core|Host|lexer|parser|diag|render|typecheck|expand|codegen|driver|style|repl|symbols|namespace|explain|format|lsp|pkg|build|rustbind|main"
tui_leaks="$(LC_ALL=C grep -rhE "^\(import ($compiler_mods)\)" "$repo_root"/stdlib/Tui/*.ax | wc -l | tr -d ' ')"
tui_files="$(ls "$repo_root"/stdlib/Tui/*.ax | wc -l | tr -d ' ')"
if [[ "$tui_leaks" == 0 && "$tui_files" == 3 ]]; then
  ok "all $tui_files stdlib/Tui modules import compiler modules 0 times - the library is standalone"
else
  bad "stdlib/Tui reaches into the compiler ($tui_leaks import(s) across $tui_files file(s), want 0 across 3)"
  LC_ALL=C grep -rnE "^\(import ($compiler_mods)\)" "$repo_root"/stdlib/Tui/*.ax | sed 's/^/     /'
fi

# And the inverse: the REPL uses the library rather than a private copy.
tui_imports="$(LC_ALL=C grep -cE '^\(import Tui\.(Keys|Edit|Term)\)' "$repo_root/self_host/repl.ax" | tr -d ' ')"
if [[ "$tui_imports" == 3 ]]; then
  ok "self_host/repl.ax imports all 3 Tui modules - one implementation, not two"
else
  bad "self_host/repl.ax imports $tui_imports of the 3 Tui modules"
fi
python3 - "$repo_root" <<'PYX' > "$work/restrict.log" 2>&1
import sys, os
root = sys.argv[1]
# floors, so a shrunken file cannot pass by having nothing to check
FLOOR = {"Keys.ax": 30, "Edit.ax": 45}
bad = 0
for name, floor in FLOOR.items():
    L = open(os.path.join(root, "stdlib", "Tui", name)).read().split("\n")
    pub = [i for i, l in enumerate(L) if l.startswith("(pub :: ")]
    tagged = [i for i in pub if i > 0 and L[i - 1].startswith(";@axiom:restrict(no-io")]
    print("FILE=%s PUB=%d TAGGED=%d FLOOR=%d" % (name, len(pub), len(tagged), floor))
    for i in pub:
        if i not in tagged:
            print("UNTAGGED=%s:%d:%s" % (name, i + 1, L[i]))
            bad += 1
    if len(tagged) < floor:
        print("BELOW_FLOOR=%s" % name)
        bad += 1
sys.exit(1 if bad else 0)
PYX
if [[ $? == 0 ]]; then
  ok "every public declaration in Tui/Keys.ax and Tui/Edit.ax claims restrict(no-io...): $(sed -n 's/^FILE=//p' "$work/restrict.log" | tr '\n' ' ')"
else
  bad "a public declaration in the pure modules carries no restrict claim, so the compiler never asks it"
  sed 's/^/     /' "$work/restrict.log" | head -12
fi

# =================================================================
echo
echo "== negative probe: the screen comparison can actually fail =="
# =================================================================
# Every assertion in layer 5 is an equality between two things this
# script computed, and a comparison that cannot fail is not a
# comparison. Flip one byte of a real transcript and require the model
# to reject it.
checks=$((checks + 1))
python3 - "$work/wrap37.bin" "$work/corrupt.bin" "$(v "$work/wrap37.err" PY_MARK_at)" <<'PYX'
import sys
d = bytearray(open(sys.argv[1], "rb").read())
# Inside the REPLAYED prefix, and a byte that is definitely SCREEN
# CONTENT. Corrupting past the mark would leave the compared bytes
# untouched, and corrupting a byte inside an escape sequence would
# test the model rather than the editor - the first attempt flipped
# the `C` of a cursor-forward and moved the cursor without touching
# the grid, so the probe reported that the grid comparison had no
# teeth when what it had actually corrupted was a motion. Lowercase
# letters are content here; `m` is excluded because it is the SGR
# final the painted prompt ends with.
for i in range(int(sys.argv[3]) - 1, -1, -1):
    if 0x61 <= d[i] <= 0x7A and d[i] != 0x6D:
        d[i] = d[i] ^ 1
        break
open(sys.argv[2], "wb").write(bytes(d))
PYX
python3 -c "
import json,sys
json.dump({'rows':24,'cols':37,'prompt':'axiom> ','typed':'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789abcdefg'}, open(sys.argv[1],'w'))
" "$work/spec.json"
python3 "$screen" "$work/spec.json" "$work/corrupt.bin" "$(v "$work/wrap37.err" PY_MARK_at)" > "$work/neg.log" 2>&1
if [[ "$(v "$work/neg.log" MODEL_GRID_OK)" == 0 ]]; then
  ok "a one-bit change to one character on screen is rejected (the comparison has teeth)"
else
  bad "the model accepted a corrupted transcript - layer 5 proves nothing"
fi

echo
if (( failed )); then
  echo "check-repl-tui: $failed of $checks checks FAILED"
  exit 1
fi
echo "check-repl-tui: $checks checks - the REPL on a real pty decodes arrows, control"
echo "                keys, Alt- prefixes and multi-byte characters; Ctrl-C is a key"
echo "                and not a signal; the terminal comes back byte-exact on both"
echo "                exit paths; and the wrapped screen matches an independent model"
echo "                at the deferred-wrap boundary and away from it"
