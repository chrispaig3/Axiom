#!/usr/bin/env bash
# The REPL's terminal interface, on a terminal.
#
# `replInteractive` is true only when fd 0 and fd 1 are both terminals,
# and every other gate runs its subject on pipes. So the decoder, the
# editor, the redraw and the raw-mode bracket run nowhere else. This
# gate drives the REPL on a pseudo-terminal it allocates and asserts
# what lands on the screen. `check-terminal-restore.sh` covers the same
# gap one layer down.
#
# `check-repl-selfhost.sh` pins the piped surface byte for byte. This
# gate is its inverse, and the two mean something only together. Layer 1
# runs one session both ways and requires the transcripts to differ:
# "no escapes off a TTY" and "escapes on one" are each satisfied by a
# build in which the other side is dead code.
#
# It never touches the caller's terminal:
#   1. Everything interactive runs against a pty from `pty.openpty()`.
#      The child's fd 0, 1 and 2 are the slave end, so the invoking
#      shell's descriptors never reach anything that calls `termRaw`.
#   2. The driver restores the pty under `try/finally` on every exit
#      path, and this script's `trap` restores the caller's terminal if
#      it had one. The trap guards against future edits: a gate that
#      leaves the developer in raw mode does more harm than the bug it
#      found.
#   3. It never runs a bare `waitpid`. A REPL in raw mode with nothing to
#      read blocks forever, and a gate that hangs instead of failing is
#      worse than none. Each driver step has a 25-second stall deadline.
#
# When it cannot run, it fails rather than skipping. `python3` is already
# a hard dependency of other gates, including check-repl-selfhost.sh, and
# any process that can open /dev/ptmx can get a pty. It reports
# `NOT RUN HERE (1), needs ...` and exits non-zero, because a gate that
# returns 0 when it could not run reads as coverage.
#
# It runs in parallel with everything, including check-repl-selfhost.sh.
# Each REPL works in its own `<tmp>/axiom-repl-<pid>.d` at mode 0700, so
# concurrent sessions share no files, and neither gate is in
# run-gates.sh's serial list.
#
# Ablation drills, and what each one shows:
#   A. `replInteractive` pinned to 0. Layer 1's ESC count names the
#      cause, layer 2's Ctrl-C kills the child, layer 3 stalls at step 0
#      and layer 4's Ctrl-D path never exits. Layer 1 compares the
#      transcripts with CRs stripped, because a cooked pty turns every LF
#      into CR LF, and the raw streams differ even with no editor.
#   B. The forced `\n\r` at `C % W == 0` removed from `ledRefreshFull`.
#      Only layer 5's two W=20 exact-row cases fail, on the cursor: the
#      text looks right and the cursor sits a row high. Every other layer
#      and `scripts/check-repl-selfhost.sh` stay green, so only layer 5
#      sees the deferred wrap.
#   C. `ledLeft` made a no-op. Only layer 3 fails: no `result 13`, then
#      no `result 9`, `3`, `15` or `42`, because Ctrl-A is built from
#      `ledLeft` and the line is never cleared.
#
# Usage:  scripts/check-repl-tui.sh

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

# Safety net: restore the caller's terminal on exit (see the header).
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
# every expected grid below depend on. It is read from the source, so a
# prompt that changes width fails here with its own message rather than
# as a timeout.
pcols="$(python3 - "$repo_root/self_host/repl.ax" <<'PYX'
import re, sys
src = open(sys.argv[1]).read()
# The normal form puts the single body form on its own line, so
# the anchor must allow whitespace between the head and the body.
# An anchor that forbids the newline finds no match (-1) on a
# formatted tree.
m = re.search(r'\(pub fn \(replPromptMain\)\s+\(paint \w+ "([^"]*)"\)\)', src)
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
# Compare with CRs stripped. A pty in cooked mode expands every LF the
# REPL writes into CR LF, so the raw transcripts differ even when the
# editor never ran. Stripping CR leaves only the editor's contribution.
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
# `termRaw` is called with keepSignals 0, which clears ISIG. Byte 3
# is then an ordinary key the editor turns into a cancelled line, and
# the REPL survives to answer the next expression. Without raw mode the
# kernel turns byte 3 into SIGINT, the child dies, and there is no
# `result 3` and no clean exit.
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
# Each of these produces a value that only a working path can produce.
#   arrows:    (+ 111 2) with three Lefts and a Delete is 13, not 113
#   ctrl-a/k:  a killed line leaves nothing behind, so the answer is 9
#   utf-8:     one Backspace removes a character; removing one byte of
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
           # one Backspace over a 2-byte character removes the character
           ["send", "b'(+ 1 2)\\xc3\\xa9'"], ["quiet", 250],
           ["send", "b'\\x7f\\r'"], ["prompt"],
           # Alt-b twice lands before `12345`; Alt-d kills the whole word
           ["send", "b'(+ 12345 7)'"], ["quiet", 250],
           ["send", "b'\\x1bb'"], ["send", "b'\\x1bb'"], ["quiet", 250],
           ["send", "b'\\x1bd'"], ["quiet", 250],
           ["send", "b'8\\r'"], ["prompt"],
           # A lone ESC, left to time out. It must resolve to the
           # Escape key, which is unbound, and the `)` sent 300ms later
           # must be an ordinary character. A decoder that held the
           # prefix would read Alt-`)` and leave the form unbalanced,
           # so the REPL would show the continuation prompt instead.
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
# `check-terminal-restore.sh` proves the primitive. This proves the REPL
# uses it correctly, including that `:quit`'s `sysExitWith 0`, deep in
# the colon dispatch, runs in cooked mode and so cannot leak raw.
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
# The screen is modelled independently, twice over. tests/repl/tui/
# screen.py replays the editor's real bytes onto a grid with a
# terminal's deferred-wrap rule, and separately computes the grid the
# key script implies with plain string slicing. Neither side is a
# checked-in value, so there is nothing for AXIOM_BLESS to launder.
#
# Some cases land the content exactly on a row boundary: the phantom
# column, where a terminal holds the cursor at column W with the wrap
# pending. That is why ledRefreshFull emits a forced newline, which
# drill B removes.
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
# 7 + 13 = 20 = 1 x 20. The phantom column.
wrap_case 20 "abcdefghijklm"                             "W=20, content exactly one row"
# 7 + 53 = 60 = 3 x 20. The phantom column, three rows down.
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
# AX3049 at SEV_ERROR, so a `writeStr` added to any decoder or editor
# function fails the build. These greps catch what the compiler cannot:
# a function added without the claim, which is never asked.
tty_sites="$(LC_ALL=C grep -rl '(isTerminal ' "$repo_root"/self_host/*.ax | wc -l | tr -d ' ')"
tty_lines="$(LC_ALL=C grep -rh '(isTerminal ' "$repo_root"/self_host/*.ax | wc -l | tr -d ' ')"
if [[ "$tty_lines" == 1 && "$tty_sites" == 1 ]]; then
  ok "the tty predicate is written EXACTLY once across self_host/ (1 line, 1 file)"
else
  bad "isTerminal is called on $tty_lines line(s) in $tty_sites file(s), want exactly 1 and 1."
  echo "     A second test downstream is how the two surfaces start diverging in places"
  echo "     no gate looks. The one place is replInteractive."
  LC_ALL=C grep -rn '(isTerminal ' "$repo_root"/self_host/*.ax | sed 's/^/     /'
fi
for m in Keys Edit; do
  if LC_ALL=C grep -q '^(import Sys)' "$repo_root/stdlib/Tui/$m.ax"; then
    bad "stdlib/Tui/$m.ax imports Sys - it is supposed to be unable to touch a descriptor even by accident"
  else
    ok "stdlib/Tui/$m.ax does not import Sys"
  fi
done

# The TUI is standard library and must not import the compiler. It lives
# in stdlib/Tui so any Axiom program can use it, with the REPL as its
# first caller. One `(import lexer)` for a word rule would make it a
# compiler module again. The two rules it would borrow, the word boundary
# and the display width, are a caller-supplied `wordChars` and
# `tuiVisLen`. tests/selfhost/978-line-editor.ax sweeps both against the
# compiler's own rules, so they cannot drift apart.
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
# Every assertion in layer 5 compares two things this script computed,
# and a comparison that cannot fail would pass unnoticed. Flip one byte
# of a real transcript and require the model to reject it.
checks=$((checks + 1))
python3 - "$work/wrap37.bin" "$work/corrupt.bin" "$(v "$work/wrap37.err" PY_MARK_at)" <<'PYX'
import sys
d = bytearray(open(sys.argv[1], "rb").read())
# Flip a screen-content byte inside the replayed prefix. A byte past
# the mark is never compared. A byte inside an escape sequence tests the
# model, not the editor: flipping the `C` of a cursor-forward moves the
# cursor without touching the grid. Lowercase letters are content here;
# `m` is excluded because it is the SGR final the painted prompt ends with.
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
