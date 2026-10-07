#!/usr/bin/env bash
# A program that puts a terminal into raw mode puts it back exactly as
# it found it.
#
# `stdlib/IO.ax`'s `termRaw` and `termRestore` let a REPL read keys one
# at a time. A program that exits without restoring leaves the user a
# shell with no echo, no line editing and no ^C, and `stty sane` typed
# blind is the only way out. Every other gate but `check-repl-tui.sh`
# runs its program with stdin on a pipe, where `sysIsatty` is false and
# this path is skipped.
#
# A save, raw, restore, compare round trip passes when `termRaw` does
# nothing at all, because nothing changed the bytes. So the round trip
# is asserted together with its precondition: the state while raw must
# differ from the state saved. Check 2 below is that inequality, and a
# no-op `termRaw` must turn it red.
#
# Two independent witnesses:
#
#   * The Axiom probe reads the attributes itself, with its own
#     `ioctl`, and compares all `termiosBytes` bytes with `memCmp` (72
#     on Darwin, 36 on Linux, 44 on FreeBSD), so the assertion is
#     byte-exact. The state `termRaw` saves is sealed inside its
#     `TermState`, so the probe's reads are its own.
#   * The Python driver holds the pty's other end and asks the kernel,
#     through `termios.tcgetattr`, from outside the process. It uses
#     Python's own `termios.ISIG`, so a wrong `tiosIsig` in
#     `Sys/Platform.*.ax` is caught here rather than confirmed by itself.
#
# One witness catches a broken restore but not a broken constant: a
# probe that reads and writes through one wrong definition agrees with
# itself.
#
# ------------------------------------------------------------------
# Safety. This gate changes terminal state and must never change yours.
#
#   1. It works only on a pseudo-terminal it allocates (`pty.openpty`).
#      The probe's fd 0, 1 and 2 are the pty's slave end, dup2'd in the
#      forked child. The probe takes no fd argument that could point at
#      the invoking shell's terminal.
#   2. It needs no controlling terminal, so it runs on CI. `openpty`
#      opens `/dev/ptmx`; it does not ask for the job's terminal.
#   3. It restores on every exit path, including a failed assertion and
#      an interrupt. The driver restores the pty under `try/finally`,
#      and this script's `trap` restores the caller's terminal, if there
#      is one. That trap guards against a future edit to this file: a
#      gate that leaves the developer in raw mode does more damage than
#      the bug it finds.
# ------------------------------------------------------------------
#
# When it cannot run, it fails. It does not skip.
#
# It needs `python3` and a pty, which every Linux, macOS and FreeBSD
# runner provides, with or without a controlling terminal. If either is
# missing it prints `NOT RUN HERE (1), needs ...` and exits non-zero. A
# gate that exits 0 when it could not run is counted as a pass by
# `run-gates.sh` and by CI, so it reads as coverage nobody has. That is
# worse than no gate, which is at least visible. To exclude this gate
# somewhere, name it in `scripts/run-gates.sh`'s NOTRUN_RE, which is a
# reviewed edit. No environment variable turns it into a pass.

set -euo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

# Safety item 3 above: remember the caller's terminal, if there is one,
# and put it back however this script exits. Nothing below should change
# it; this catches a future edit that does, such as a probe run without
# the pty or a debugging `stty` left behind.
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
# The probe: one Axiom program, run twice with `keepSignals` as its only
# argument. It prints every fact as a KEY=VALUE line, so this script
# asserts on values rather than on prose.
#
# It works on fd 0, the pty slave in the driver's forked child, and
# takes no descriptor argument: a probe that could be pointed at the
# invoking shell's fd 0 eventually would be.
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
      buf      n      (+ i 1)      (concat acc (concat (if (< (memGetByte buf i) 16) "0" "") (fmtHex (memGetByte buf i))))
    )
  )
)

(:: kv (-> String String Int))

;@axiom:effect(io)
(fn (kv k v) { (println (concat k (concat "=" v))) 0 })

(:: kvInt (-> String Int Int))

;@axiom:effect(io)
(fn (kvInt k v) (kv k (fmtInt v)))

; The probe's own read of fd 0's attributes into `buf`: 0, or -errno.
; Independent of `IO`, whose saved state is sealed.
(:: getAttr (-> Int Int))

;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (getAttr buf) (__syscall3 sysIoctlNum 0 tcGetAttrReq buf))

(:: errInt (-> (Result Int Error) Int))

(fn (errInt r) (match r ((Ok n) n) ((Err e) (- 0 e.code))))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  (let (
    (keep (strEq (sysArg 1) "1"))
    (save (memAlloc termiosBytes))
    (live (memAlloc termiosBytes))
    (after (memAlloc termiosBytes))
    (key (readBufferNew 1))
  )
    {
      (kvInt "STATE_BYTES" termiosBytes)
      (kvInt "KEEPSIGNALS" (if keep 1 0))
      (kvInt "ISATTY0" (if (sysIsatty 0) 1 0))
      (kvInt "SAVE_RC" (getAttr save))
      (kv "SAVED" (hexOf save termiosBytes 0 ""))
      (match (termRaw 0 keep)
        ((Err e) (kvInt "RAW_RC" (- 0 e.code)))
        ((Ok st)
          {
            (kvInt "RAW_RC" 0)
            ; What the terminal IS, now, read back fresh.
            (kvInt "LIVE_RC" (getAttr live))
            (kv "LIVE" (hexOf live termiosBytes 0 ""))
            (kvInt "RAW_DIFFERS" (if (== (memCmp save live termiosBytes) 0) 0 1))
            ; One keypress. With ICANON off this returns on the first
            ; byte, with no newline anywhere. The driver writes exactly
            ; one 'A'.
            (kvInt "KEY_RC" (errInt (readBuffer 0 key 0 1)))
            (kvInt "KEY_BYTE" (readBufferByte key 0))
            (kvInt "RESTORE_RC" (errInt (termRestore st)))
            0
          }))
      (kvInt "AFTER_RC" (getAttr after))
      (kv "AFTER" (hexOf after termiosBytes 0 ""))
      (kvInt "ROUND_TRIP_EXACT" (if (== (memCmp save after termiosBytes) 0) 1 0))
      (match (termSize 0)
        ((Ok sz)
          {
            (kvInt "SIZE_RC" 0)
            (kvInt "ROWS" sz.rows)
            (kvInt "COLS" sz.cols)
          })
        ((Err e) (kvInt "SIZE_RC" (- 0 e.code))))
      (println "PROBE_DONE=1")
      0
    }
  )
)
AX

# The negative half: the same calls against things that are not
# terminals. It runs with stdin on a pipe, with no pty and no driver.
cat > "$work/neg.ax" <<'AX'
(import Sys)
(import IO)
(import Mem)
(import Fmt)
(import Str)
(import Err)

(:: kvInt (-> String Int Int))

;@axiom:effect(io)
(fn (kvInt k v) { (println (concat k (concat "=" (fmtInt v)))) 0 })

(:: code (-> (Result a Error) Int))

(fn (code r) (match r ((Ok _) 0) ((Err e) (- 0 e.code))))

(:: main Int)

;@axiom:effect(io)
(fn (main)
  {
    (kvInt "PIPE_ISATTY" (if (sysIsatty 0) 1 0))
    (kvInt "PIPE_SAVE" (code (termSave 0)))
    (kvInt "PIPE_RAW" (code (termRaw 0 true)))
    (kvInt "PIPE_SIZE" (code (termSize 0)))
    (kvInt "BADFD_ISATTY" (if (sysIsatty 999) 1 0))
    (kvInt "BADFD_SAVE" (code (termSave 999)))
    (kvInt "BADFD_RAW" (code (termRaw 999 true)))
    (println "NEG_DONE=1")
    0
  }
)
AX

echo "== building the probes =="
"$axc" build "$work/probe.ax" -o "$work/probe" > "$work/build.log" 2>&1 \
  || { echo "FAIL: could not build the pty probe"; sed 's/^/     /' "$work/build.log" | head -20; exit 1; }
"$axc" build "$work/neg.ax" -o "$work/neg" >> "$work/build.log" 2>&1 \
  || { echo "FAIL: could not build the non-terminal probe"; sed 's/^/     /' "$work/build.log" | head -20; exit 1; }
ok "both probes built"

# ------------------------------------------------------------------
# The driver allocates the pty, forks the probe onto it, samples the
# kernel's view of the terminal at three moments, and prints KEY=VALUE
# lines prefixed `PY_`, so the two witnesses never mix in the output.
#
# It sets the pty's size with TIOCSWINSZ first, so `termSize` has a
# definite answer rather than the zero a pty may report.
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
    # to catch a broken termRaw would hang instead of failing.
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

# `v <file> <KEY>`: the value of one KEY=VALUE line, or the empty
# string. Anchored, so `KEY` never matches `OTHER_KEY`.
v() { sed -n "s/^$2=//p" "$1" | tail -1 | tr -d '\r'; }

# The errno values the negative paths must answer, read from this host
# so the gate does not depend on them matching across platforms.
e_notty="$(python3 -c 'import errno; print(errno.ENOTTY)')"
e_badf="$(python3 -c 'import errno; print(errno.EBADF)')"

# ------------------------------------------------------------------
# run_pty <keepSignals> <label>
# ------------------------------------------------------------------
run_pty() {
  # One `local` per variable: bash 3.2, which macOS ships, does not
  # reliably see an earlier assignment on the same `local` line, and
  # `set -u` turns that into an unbound-variable error.
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

  # 0a. The probe ran on a terminal. Without that every check below is
  #     vacuous: on a pipe each call short-circuits and the round trip
  #     is exact because nothing happened. It is the only numbered check
  #     that returns early.
  if [[ "$(v "$log" ISATTY0)" == 1 ]]; then
    ok "[$label] the probe ran on a pty, and sysIsatty agrees ($sb-byte state)"
  else
    bad "[$label] the probe's fd 0 was not a terminal (ISATTY0=$(v "$log" ISATTY0)) - every check below would be vacuous"
    sed 's/^/     /' "$log" | head -25
    return
  fi

  # 0b. The probe finished. This is separate from 0a: with `termRaw`
  #     a no-op, the probe runs on the pty (ISATTY0=1) and then hangs.
  #     A terminal still in canonical mode does not return from read()
  #     until it sees a newline, and the driver sends one byte that is
  #     not one. Report the hang as a hang and keep checking what the
  #     probe did print: RAW_DIFFERS is the line that explains it.
  if [[ "$(v "$log" PROBE_DONE)" == 1 ]]; then
    ok "[$label] the probe ran to completion"
  else
    if [[ "$(v "$log" PY_PROBE_KILLED)" == 1 ]]; then
      bad "[$label] the probe HUNG and had to be killed - it never returned from read()."
      echo "       That is what a terminal still in canonical mode does: the driver"
      echo "       sends one byte and no newline, so a read() that is waiting for a"
      echo "       line never returns. Suspect termRaw: RAW_DIFFERS=$(v "$log" RAW_DIFFERS)."
    else
      bad "[$label] the probe stopped early without finishing (no PROBE_DONE, and it was not killed)"
      sed 's/^/     /' "$log" | head -25
    fi
  fi

  # 1. The round trip is byte-exact, by both witnesses.
  local saved after
  saved="$(v "$log" SAVED)"; after="$(v "$log" AFTER)"
  if [[ -n "$saved" && "$saved" == "$after" && "$(v "$log" ROUND_TRIP_EXACT)" == 1 ]]; then
    ok "[$label] round trip byte-exact: all $sb bytes identical (memCmp, and the hex agrees)"
  else
    bad "[$label] round trip is NOT byte-exact - termRestore did not restore what was saved"
    echo "       saved: $saved"
    echo "       after: $after"
  fi
  if [[ "$(v "$log" PY_ROUND_TRIP_EXACT)" == 1 ]]; then
    ok "[$label] round trip byte-exact by the kernel's own account (tcgetattr, outside the process)"
  else
    bad "[$label] the kernel disagrees that the terminal was restored: $(v "$log" PY_DIFF)"
  fi

  # 2. Raw mode took effect. Without this, a termRaw that does
  #    nothing passes check 1.
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

  # 4. ICANON is really off: one byte came back with no newline sent.
  #    An empty KEY_RC means the read never returned.
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
    ok "[$label] termSize read back the $(v "$log" ROWS)x$(v "$log" COLS) the driver set"
  else
    bad "[$label] termSize answered $(v "$log" ROWS)x$(v "$log" COLS), want $(v "$log" PY_WANT_ROWS)x$(v "$log" PY_WANT_COLS)"
  fi

  # 7. ISIG follows the caller's argument, both ways, judged by
  #    Python's termios.ISIG rather than the platform module under test.
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
# The negative half: things that are not terminals must answer the
# matching errno, never a fabricated success.
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
  for k in PIPE_SAVE PIPE_RAW PIPE_SIZE; do
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
# A negative probe on the gate itself. Every comparison above is an
# equality between two strings pulled from a log, and a comparison that
# cannot fail checks nothing. So flip one bit of the captured SAVED
# state and require the comparison to tell them apart.
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
