#!/usr/bin/env bash
# Assert that a program which puts a terminal into raw mode puts it back
# EXACTLY as it found it.
#
# WHY THIS GATE EXISTS. `stdlib/Sys.ax` grew `sysTermSave`, `sysTermRaw`
# and `sysTermRestore` so that a REPL can read keys one at a time. The
# failure mode of that trio is not a wrong answer, it is a wrecked
# machine: a program that exits without restoring hands the user a shell
# with no echo, no line editing and no ^C, and the only recovery is
# `stty sane` typed blind into a terminal that is not showing what is
# typed. Nothing in this repository could see that happen. Every other
# gate runs with its stdin on a pipe, where `sysIsatty` is false and the
# whole path is skipped, so the raw-mode code was reachable by exactly
# nobody and green everywhere.
#
# THE CHECK THAT LOOKS RIGHT AND PROVES NOTHING, stated here because it
# is the one this gate is shaped to avoid. Save the attributes, enter
# raw mode, restore, read the attributes back, compare. That passes
# PERFECTLY when `sysTermRaw` does nothing at all - the bytes match
# because nothing ever changed them - so it is satisfied by the
# complete absence of the feature it is meant to defend. The round trip
# is therefore asserted TOGETHER with its own precondition: the state
# while raw must DIFFER from the state saved. Check 2 below is that
# inequality, and ablation B drives it.
#
# TWO WITNESSES, AND THEY ARE INDEPENDENT ON PURPOSE.
#
#   * The Axiom probe compares all `sysTermStateBytes` bytes with
#     `memCmp` - 72 of them on Darwin, 36 on Linux, 44 on FreeBSD - so
#     the assertion is byte-exact rather than "the flags look right".
#     It reads through the same library it is testing.
#   * The Python driver holds the pty's other end and asks the KERNEL,
#     through `termios.tcgetattr`, from outside the process. It uses
#     Python's own `termios.ISIG`, not the constant in
#     `Sys/Platform.*.ax`, so a wrong `tiosIsig` in the platform module
#     is caught here rather than confirmed by itself.
#
# A single witness would be enough to catch a broken restore and would
# NOT be enough to catch a broken constant, because a probe that reads
# and writes through one wrong definition agrees with itself.
#
# ------------------------------------------------------------------
# SAFETY. THIS GATE MANIPULATES TERMINAL STATE, AND IT MUST NEVER
# MANIPULATE YOURS.
#
#   1. It operates only on a PSEUDO-TERMINAL IT ALLOCATES ITSELF
#      (`pty.openpty`). The Axiom probe's fd 0, 1 and 2 are the slave
#      end of that pty, dup2'd over in the forked child. The invoking
#      shell's descriptors are never handed to anything that calls
#      `sysTermRaw`, and the probe takes no fd argument that could be
#      pointed at one.
#   2. It needs no controlling terminal, which is what lets it run on a
#      CI runner. `openpty` is an operation on `/dev/ptmx`, not a
#      request for the terminal the job was started from.
#   3. It restores on EVERY exit path, including a failed assertion and
#      an interrupt. The driver restores the pty under `try/finally`;
#      this script arms a `trap` that puts the CALLER's terminal back
#      the way it found it, if the caller had one at all. That second
#      trap defends against a future edit to this file rather than
#      against anything it does today - the point of the promise is
#      that it survives the next person, and a gate that reports a
#      failure and leaves the developer in raw mode has done more
#      damage than the bug it found.
# ------------------------------------------------------------------
#
# WHEN IT CANNOT RUN, IT FAILS. LOUDLY. It does not skip.
#
# This gate needs `python3` and a pty. `python3` is already a hard
# dependency of twenty other gates here, and a pty is available to any
# process that can open `/dev/ptmx` - which is every Linux, macOS and
# FreeBSD runner, with or without a controlling terminal. So "cannot
# run here" is a real and rare condition, and it is reported with the
# battery's own words - `NOT RUN HERE (1), needs ...` - AND a non-zero
# exit.
#
# THE EXIT CODE IS THE WHOLE POINT AND IT WAS A DELIBERATE CHOICE. A
# gate that returns 0 when it could not run reads as coverage: it is
# counted in `run-gates.sh`'s pass total and it is green on the CI leg,
# and the property nobody is checking is the one everybody believes is
# checked. That is strictly worse than having no gate, because no gate
# is at least visible. `scripts/run-gates.sh` has a mechanism for a
# gate that genuinely cannot run somewhere - `NOTRUN_RE`, which
# EXCLUDES it from the battery and prints why - and putting a gate
# there is a visible edit in a reviewed file. That is where the
# decision belongs. It is not a valve this script may pull on its own
# at runtime, and there is deliberately no environment variable that
# turns this gate into a pass.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

# SAFETY NET 1 (see the block above): remember the caller's terminal, if
# the caller has one, and put it back however this script exits. Nothing
# below should ever change it. This exists so that a future edit which
# does - a probe run without the pty, a debugging `stty` left behind -
# cannot escape the file.
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
  echo "     This gate does not skip. See the header for why a green"
  echo "     'could not run' is worse than no gate at all."
  exit 1
}

# ------------------------------------------------------------------
# The probe. One Axiom program, run twice: `keepSignals` is its only
# argument, and every fact it learns is printed as a KEY=VALUE line so
# that this script asserts on values rather than on prose it greps.
#
# It works on fd 0, which in the child the driver forks is the pty
# slave. It takes no descriptor argument on purpose - a probe that
# could be pointed at fd 0 of the invoking shell is a probe that will
# one day be pointed there.
# ------------------------------------------------------------------
cat > "$work/probe.ax" <<'AX'
(import Sys)
(import IO)
(import Mem)
(import Fmt)
(import Str)
(import Err)

; `n` bytes at `buf` as lowercase hex, no separator - one field this
; script can compare with `=`.
(:: hexOf (-> Int Int Int String String))

(fn (hexOf buf n i acc)
  (if (>= i n)
    acc
    (hexOf
      buf      n      (+ i 1)      (strConcat acc (strConcat (if (< (memGetByte buf i) 16) "0" "") (fmtHex (memGetByte buf i))))
    )
  )
)

(:: kv (-> String String Int))

;@axiom:effect(io)
(fn (kv k v) { (println (strConcat k (strConcat "=" v))) 0 })

(:: kvInt (-> String Int Int))

;@axiom:effect(io)
(fn (kvInt k v) (kv k (fmtInt v)))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let (
    (keep (if (strEq (sysArg 1) "0") 0 1))
    (save (memAlloc sysTermStateBytes))
    (live (memAlloc sysTermStateBytes))
    (after (memAlloc sysTermStateBytes))
    (key (memAlloc 8))
    (ws (memAlloc sysTermSizeBytes))
  )
    {
      (kvInt "STATE_BYTES" sysTermStateBytes)
      (kvInt "KEEPSIGNALS" keep)
      (kvInt "ISATTY0" (if (sysIsatty 0) 1 0))
      ; SAVE. From here on `save` is never written to again, by anything.
      (kvInt "SAVE_RC" (sysTermSave 0 save))
      (kv "SAVED" (hexOf save sysTermStateBytes 0 ""))
      ; RAW. It re-reads the attributes into `save` itself and edits a
      ; private copy; `SAVED_AGAIN` must equal `SAVED` above.
      (kvInt "RAW_RC" (sysTermRaw 0 save keep))
      (kv "SAVED_AGAIN" (hexOf save sysTermStateBytes 0 ""))
      ; What the terminal IS, now, read back fresh.
      (kvInt "LIVE_RC" (sysTermSave 0 live))
      (kv "LIVE" (hexOf live sysTermStateBytes 0 ""))
      (kvInt "RAW_DIFFERS" (if (== (memCmp save live sysTermStateBytes) 0) 0 1))
      ; One keypress. With ICANON off this returns on the first byte,
      ; with no newline anywhere. The driver writes exactly one 'A'.
      ; `sysReadFd` answers `(Result Int Error)` since 2026-09-03
      ; (ERR-ADOPT-1); the probe reads the count out of the `Ok` and
      ; keeps the old `-errno` spelling for the driver's KEY_RC key.
      (kvInt "KEY_RC" (match (sysReadFd 0 key 1) ((Ok k) k) ((Err e) (- 0 (errCode e)))))
      (kvInt "KEY_BYTE" (memGetByte key 0))
      (kvInt "RESTORE_RC" (sysTermRestore 0 save))
      (kvInt "AFTER_RC" (sysTermSave 0 after))
      (kv "AFTER" (hexOf after sysTermStateBytes 0 ""))
      (kvInt "ROUND_TRIP_EXACT" (if (== (memCmp save after sysTermStateBytes) 0) 1 0))
      (kvInt "SIZE_RC" (sysTermSize 0 ws))
      (kvInt "ROWS" (sysTermRows ws))
      (kvInt "COLS" (sysTermCols ws))
      (println "PROBE_DONE=1")
      0
    }
  )
)
AX

# The negative half: the same calls against things that are NOT
# terminals. No pty, no driver - it runs with its stdin on a pipe,
# which is what every other gate in this repository gives a program.
cat > "$work/neg.ax" <<'AX'
(import Sys)
(import IO)
(import Mem)
(import Fmt)
(import Str)

(:: kvInt (-> String Int Int))

;@axiom:effect(io)
(fn (kvInt k v) { (println (strConcat k (strConcat "=" (fmtInt v)))) 0 })

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let ((buf (memAlloc sysTermStateBytes)))
    {
      (kvInt "PIPE_ISATTY" (if (sysIsatty 0) 1 0))
      (kvInt "PIPE_SAVE" (sysTermSave 0 buf))
      (kvInt "PIPE_RAW" (sysTermRaw 0 buf 1))
      (kvInt "PIPE_RESTORE" (sysTermRestore 0 buf))
      (kvInt "PIPE_SIZE" (sysTermSize 0 (memAlloc sysTermSizeBytes)))
      (kvInt "BADFD_ISATTY" (if (sysIsatty 999) 1 0))
      (kvInt "BADFD_SAVE" (sysTermSave 999 buf))
      (kvInt "BADFD_RAW" (sysTermRaw 999 buf 1))
      (println "NEG_DONE=1")
      0
    }
  )
)
AX

echo "== building the probes =="
"$axc" build "$work/probe.ax" -o "$work/probe" > "$work/build.log" 2>&1 \
  || { echo "FAIL: could not build the pty probe"; sed 's/^/     /' "$work/build.log" | head -20; exit 1; }
"$axc" build "$work/neg.ax" -o "$work/neg" >> "$work/build.log" 2>&1 \
  || { echo "FAIL: could not build the non-terminal probe"; sed 's/^/     /' "$work/build.log" | head -20; exit 1; }
ok "both probes built"

# ------------------------------------------------------------------
# The driver. Allocates the pty, forks the probe onto it, samples the
# kernel's own view of the terminal at three moments, and prints its
# findings as more KEY=VALUE lines - prefixed `PY_` so the two
# witnesses can never be confused for one another in the output.
#
# It sizes the pty with TIOCSWINSZ first, so that `sysTermSize` has a
# definite answer to find rather than a zero a pty may legitimately
# report.
# ------------------------------------------------------------------
cat > "$work/drive.py" <<'PY'
import os, pty, sys, termios, fcntl, struct, select, time

prog, keep = sys.argv[1], sys.argv[2]
ROWS, COLS = 42, 137

try:
    master, slave = pty.openpty()
except Exception as e:                                    # pragma: no cover
    print("PY_NO_PTY=%s" % type(e).__name__)
    sys.exit(3)

saved = termios.tcgetattr(slave)

def field(a, i):
    return a[i]

try:
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", ROWS, COLS, 0, 0))
    before = termios.tcgetattr(slave)

    pid = os.fork()
    if pid == 0:
        # The child's only descriptors are the pty's. Nothing it can do
        # reaches the terminal this gate was invoked from.
        os.dup2(slave, 0); os.dup2(slave, 1); os.dup2(slave, 2)
        os.close(master); os.close(slave)
        os.execv(prog, [prog, keep])

    out, during, sent = b"", None, False
    deadline = time.time() + 30
    while time.time() < deadline:
        r, _, _ = select.select([master], [], [], 0.25)
        if r:
            try:
                chunk = os.read(master, 65536)
            except OSError:
                break
            if not chunk:
                break
            out += chunk
        if not sent and b"RAW_DIFFERS=" in out:
            # The probe is now blocked in read(1). Ask the kernel what
            # the terminal actually is, from outside the process.
            during = termios.tcgetattr(slave)
            os.write(master, b"A")
            sent = True
        if b"PROBE_DONE=1" in out:
            break

    # Sample BEFORE reaping: the pty must not be torn down under us.
    after = termios.tcgetattr(slave)

    # REAP WITH A DEADLINE, NEVER A BARE waitpid. If raw mode did not
    # take, the probe is still in CANONICAL mode and is blocked in
    # read() waiting for a newline that the single 'A' above is not -
    # so a plain waitpid here hangs forever, and the gate that exists
    # to catch a broken sysTermRaw would hang instead of failing.
    # Found while ablating: it is exactly the ablation this file must
    # survive. Kill, then reap.
    status, waited = None, time.time() + 5
    while time.time() < waited:
        done, st = os.waitpid(pid, os.WNOHANG)
        if done == pid:
            status = st
            break
        time.sleep(0.05)
    if status is None:
        os.kill(pid, 9)
        _, status = os.waitpid(pid, 0)
        print("PY_PROBE_KILLED=1")
finally:
    # SAFETY: the pty is ours and is about to be closed, but restore it
    # anyway, so that no exit path from this driver is one that leaves a
    # terminal changed.
    try:
        termios.tcsetattr(slave, termios.TCSAFLUSH, saved)
    except Exception:
        pass
    try:
        os.close(master); os.close(slave)
    except Exception:
        pass

if during is None:
    print("PY_NEVER_RAW=1")
    sys.exit(4)

LFLAG = 3
print("PY_EXIT=%d" % (os.WEXITSTATUS(status) if os.WIFEXITED(status) else 128))
print("PY_ROUND_TRIP_EXACT=%d" % (1 if before == after else 0))
print("PY_RAW_DIFFERS=%d"      % (0 if before == during else 1))
print("PY_ISIG_BEFORE=%d" % (1 if field(before, LFLAG) & termios.ISIG else 0))
print("PY_ISIG_DURING=%d" % (1 if field(during, LFLAG) & termios.ISIG else 0))
print("PY_ISIG_AFTER=%d"  % (1 if field(after,  LFLAG) & termios.ISIG else 0))
print("PY_ECHO_DURING=%d"   % (1 if field(during, LFLAG) & termios.ECHO   else 0))
print("PY_ICANON_DURING=%d" % (1 if field(during, LFLAG) & termios.ICANON else 0))
print("PY_WANT_ROWS=%d" % ROWS)
print("PY_WANT_COLS=%d" % COLS)
if before != after:
    print("PY_DIFF=%s" % [(i, x, y) for i, (x, y) in enumerate(zip(before, after)) if x != y])
sys.stdout.write(out.decode("utf-8", "replace").replace("\r\n", "\n"))
PY

# `v <file> <KEY>` - the value of one KEY=VALUE line, or the empty
# string. Anchored, so `KEY` never matches `OTHER_KEY`.
v() { sed -n "s/^$2=//p" "$1" | tail -1 | tr -d '\r'; }

# The two errno values the negative paths must answer, taken from THIS
# host rather than written down. They agree on Darwin, Linux and
# FreeBSD today; reading them here means the gate does not depend on
# that continuing to be true.
e_notty="$(python3 -c 'import errno; print(errno.ENOTTY)')"
e_badf="$(python3 -c 'import errno; print(errno.EBADF)')"

# ------------------------------------------------------------------
# run_pty <keepSignals> <label>
# ------------------------------------------------------------------
run_pty() {
  # Split across statements rather than one `local a=.. b=$a`: bash 3.2,
  # which the macOS runner ships, does not reliably see the first
  # assignment from the second on the same line, and `set -u` turns
  # that into "keep: unbound variable" at the first call.
  local keep="$1"
  local label="$2"
  local log="$work/pty-$keep.log"
  local rc=0
  python3 "$work/drive.py" "$work/probe" "$keep" > "$log" 2>&1 || rc=$?

  if (( rc == 3 )); then
    echo "NOT RUN HERE (1), needs a pty this process may allocate:"
    echo "     python3's pty.openpty() failed with $(v "$log" PY_NO_PTY) - /dev/ptmx"
    echo "     is unavailable in this environment. This gate does not skip;"
    echo "     see the header for why a green 'could not run' is worse than"
    echo "     no gate at all. To exclude it deliberately, name it in"
    echo "     scripts/run-gates.sh's NOTRUN_RE, which is a reviewed edit."
    exit 1
  fi
  if (( rc == 4 )); then
    bad "[$label] the probe never reached raw mode - the driver saw no RAW_DIFFERS line"
    sed 's/^/     /' "$log" | head -20
    return
  fi
  if (( rc != 0 )); then
    bad "[$label] the pty driver exited $rc"
    sed 's/^/     /' "$log" | head -25
    return
  fi

  local sb; sb="$(v "$log" STATE_BYTES)"

  # 0a. The probe ran on a terminal at all. Everything below is vacuous
  #     without this: on a pipe every call short-circuits and the round
  #     trip is exact because nothing ever happened. This is the ONE
  #     condition that makes the rest meaningless, so it is the one
  #     that returns early.
  if [[ "$(v "$log" ISATTY0)" == 1 ]]; then
    ok "[$label] the probe ran on a pty, and sysIsatty agrees ($sb-byte state)"
  else
    bad "[$label] the probe's fd 0 was not a terminal (ISATTY0=$(v "$log" ISATTY0)) - every check below would be vacuous"
    sed 's/^/     /' "$log" | head -25
    return
  fi

  # 0b. THE PROBE FINISHED. It is a separate question from 0a, and
  #     conflating the two made this gate misreport its own most
  #     important ablation: with `sysTermRaw` stubbed to a no-op the
  #     probe reached the pty perfectly well (ISATTY0=1) and then hung,
  #     because a terminal still in CANONICAL mode does not return from
  #     read() until it sees a newline, and the driver deliberately
  #     sends one byte that is not one. The old wording said "the probe
  #     did not run on a terminal" while printing the evidence that it
  #     had. Diagnose the hang as what it is, and carry on checking the
  #     lines the probe did manage to print - RAW_DIFFERS is one of
  #     them, and it is the finding that explains the hang.
  if [[ "$(v "$log" PROBE_DONE)" == 1 ]]; then
    ok "[$label] the probe ran to completion"
  else
    if [[ "$(v "$log" PY_PROBE_KILLED)" == 1 ]]; then
      bad "[$label] the probe HUNG and had to be killed - it never returned from read()."
      echo "       That is what a terminal still in canonical mode does: the driver"
      echo "       sends one byte and no newline, so a read() that is waiting for a"
      echo "       line never returns. Suspect sysTermRaw: RAW_DIFFERS=$(v "$log" RAW_DIFFERS)."
    else
      bad "[$label] the probe stopped early without finishing (no PROBE_DONE, and it was not killed)"
      sed 's/^/     /' "$log" | head -25
    fi
  fi

  # 1. THE ROUND TRIP IS BYTE-EXACT. Both witnesses.
  local saved after
  saved="$(v "$log" SAVED)"; after="$(v "$log" AFTER)"
  if [[ -n "$saved" && "$saved" == "$after" && "$(v "$log" ROUND_TRIP_EXACT)" == 1 ]]; then
    ok "[$label] round trip byte-exact: all $sb bytes identical (memCmp, and the hex agrees)"
  else
    bad "[$label] round trip is NOT byte-exact - sysTermRestore did not restore what was saved"
    echo "       saved: $saved"
    echo "       after: $after"
  fi
  if [[ "$(v "$log" PY_ROUND_TRIP_EXACT)" == 1 ]]; then
    ok "[$label] round trip byte-exact by the kernel's own account (tcgetattr, outside the process)"
  else
    bad "[$label] the kernel disagrees that the terminal was restored: $(v "$log" PY_DIFF)"
  fi

  # 2. RAW MODE ACTUALLY TOOK EFFECT. Without this, check 1 is passed
  #    by a sysTermRaw that does nothing whatsoever.
  if [[ "$(v "$log" RAW_DIFFERS)" == 1 ]]; then
    ok "[$label] raw mode changed the state (the saved bytes and the live bytes differ)"
  else
    bad "[$label] raw mode changed NOTHING - the round trip above is vacuous"
  fi
  if [[ "$(v "$log" PY_RAW_DIFFERS)" == 1 && "$(v "$log" PY_ECHO_DURING)" == 0 && "$(v "$log" PY_ICANON_DURING)" == 0 ]]; then
    ok "[$label] and the kernel agrees: ECHO and ICANON are both off while raw"
  else
    bad "[$label] the kernel says raw mode did not take: differs=$(v "$log" PY_RAW_DIFFERS) ECHO=$(v "$log" PY_ECHO_DURING) ICANON=$(v "$log" PY_ICANON_DURING)"
  fi

  # 3. The saved buffer is not the buffer that got edited.
  if [[ "$saved" == "$(v "$log" SAVED_AGAIN)" ]]; then
    ok "[$label] sysTermRaw left the caller's saved bytes untouched"
  else
    bad "[$label] sysTermRaw WROTE THROUGH the caller's saved buffer - the original is lost"
  fi

  # 4. ICANON off is observable, not just declared: one byte came back
  #    with no newline sent. An empty KEY_RC means the read never
  #    returned at all, which is the same finding said louder.
  if [[ "$(v "$log" KEY_RC)" == 1 && "$(v "$log" KEY_BYTE)" == 65 ]]; then
    ok "[$label] a single keypress returned from read() with no newline - ICANON is really off"
  elif [[ -z "$(v "$log" KEY_RC)" ]]; then
    bad "[$label] read() never returned from a single keypress - ICANON is still on"
  else
    bad "[$label] the one-byte read did not behave: rc=$(v "$log" KEY_RC) byte=$(v "$log" KEY_BYTE)"
  fi

  # 5. Every call reported success.
  local rcs_ok=1
  local k
  local got_rc
  for k in SAVE_RC RAW_RC LIVE_RC RESTORE_RC AFTER_RC SIZE_RC; do
    got_rc="$(v "$log" $k)"
    if [[ -z "$got_rc" ]]; then
      rcs_ok=0; bad "[$label] $k was never printed - the probe did not get that far"
    elif [[ "$got_rc" != 0 ]]; then
      rcs_ok=0; bad "[$label] $k = $got_rc, want 0"
    fi
  done
  (( rcs_ok )) && ok "[$label] every call answered 0 on a real terminal"

  # 6. The size is the size the driver set.
  if [[ "$(v "$log" ROWS)" == "$(v "$log" PY_WANT_ROWS)" && "$(v "$log" COLS)" == "$(v "$log" PY_WANT_COLS)" ]]; then
    ok "[$label] sysTermSize read back the $(v "$log" ROWS)x$(v "$log" COLS) the driver set"
  else
    bad "[$label] sysTermSize answered $(v "$log" ROWS)x$(v "$log" COLS), want $(v "$log" PY_WANT_ROWS)x$(v "$log" PY_WANT_COLS)"
  fi

  # 7. ISIG FOLLOWS THE CALLER'S ARGUMENT, both ways, judged by
  #    Python's own termios.ISIG rather than by the platform module
  #    under test.
  local want_isig="$keep"
  if [[ "$(v "$log" PY_ISIG_DURING)" == "$want_isig" ]]; then
    if [[ "$keep" == 1 ]]; then
      ok "[$label] keepSignals=1 left ISIG SET while raw - ^C still interrupts"
    else
      ok "[$label] keepSignals=0 CLEARED ISIG while raw - ^C arrives as a byte"
    fi
  else
    bad "[$label] ISIG while raw is $(v "$log" PY_ISIG_DURING), want $want_isig - the third argument is not being honoured"
  fi
  if [[ "$(v "$log" PY_ISIG_AFTER)" == "$(v "$log" PY_ISIG_BEFORE)" ]]; then
    ok "[$label] ISIG is back to its original value after the restore"
  else
    bad "[$label] ISIG was $(v "$log" PY_ISIG_BEFORE) before and is $(v "$log" PY_ISIG_AFTER) after"
  fi
}

echo "== on a pty, keeping signals (keepSignals=1) =="
run_pty 1 "keep"
echo
echo "== on a pty, full raw (keepSignals=0) =="
run_pty 0 "raw"

# ------------------------------------------------------------------
# The negative half: things that are not terminals must answer errors,
# not silence and not a fabricated success.
# ------------------------------------------------------------------
echo
echo "== not a terminal: a pipe, and a descriptor that is not open =="
: | "$work/neg" > "$work/neg.log" 2>&1 || {
  bad "the non-terminal probe exited non-zero"; sed 's/^/     /' "$work/neg.log" | head -20; }

if [[ "$(v "$work/neg.log" NEG_DONE)" == 1 ]]; then
  for pair in "PIPE_ISATTY 0" "BADFD_ISATTY 0"; do
    set -- $pair
    got="$(v "$work/neg.log" "$1")"
    if [[ "$got" == "$2" ]]; then ok "$1 = $2"; else bad "$1 = $got, want $2"; fi
  done
  for k in PIPE_SAVE PIPE_RAW PIPE_RESTORE PIPE_SIZE; do
    got="$(v "$work/neg.log" $k)"
    if [[ "$got" == "-$e_notty" ]]; then
      ok "$k answers -$e_notty (ENOTTY on this host), not a fabricated success"
    else
      bad "$k = $got, want -$e_notty (ENOTTY)"
    fi
  done
  for k in BADFD_SAVE BADFD_RAW; do
    got="$(v "$work/neg.log" $k)"
    if [[ "$got" == "-$e_badf" ]]; then
      ok "$k answers -$e_badf (EBADF on this host)"
    else
      bad "$k = $got, want -$e_badf (EBADF)"
    fi
  done
else
  bad "the non-terminal probe did not finish"; sed 's/^/     /' "$work/neg.log" | head -20
fi

# ------------------------------------------------------------------
# NEGATIVE PROBE ON THE GATE ITSELF. Every comparison above is an
# equality between two strings this script pulled out of a log, and a
# comparison that cannot fail is not a comparison - which is this
# repository's most common defect. So corrupt one byte of a captured
# `AFTER` and require the byte-exact check to reject it.
# ------------------------------------------------------------------
echo
echo "== negative probe: the byte-exact comparison can actually fail =="
checks=$((checks + 1))
real_saved="$(v "$work/pty-1.log" SAVED)"
corrupt="$(python3 - "$real_saved" <<'PYX'
import sys
s = sys.argv[1]
# Flip the low bit of the very first byte. One byte, one bit: if the
# comparison is real, this is enough.
b = int(s[0:2], 16) ^ 1
sys.stdout.write("%02x%s" % (b, s[2:]))
PYX
)"
if [[ -n "$real_saved" && "$real_saved" != "$corrupt" && ${#real_saved} -eq ${#corrupt} ]]; then
  ok "a one-bit change to the saved state is not equal to it (the check has teeth)"
else
  bad "the corruption probe produced nothing distinguishable - the byte comparison proves nothing"
fi

echo
if (( failed )); then
  echo "check-terminal-restore: $failed of $checks checks FAILED"
  exit 1
fi
echo "check-terminal-restore: $checks checks - a terminal put into raw mode comes"
echo "                        back byte-for-byte, raw mode demonstrably took"
echo "                        effect first, ISIG follows the caller's argument,"
echo "                        and a non-terminal answers an error"
