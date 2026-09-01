#!/usr/bin/env python3
"""Drive `axc repl` on a pseudo-terminal this process allocates itself.

WHY A DRIVER AND NOT A PIPE. `replInteractive` is true only when fd 0
and fd 1 are both terminals, so every line of the TUI is unreachable
from an ordinary shell redirect - which is precisely how the raw-mode
path in `stdlib/Sys.ax` managed to be green everywhere and reachable by
nobody until `check-terminal-restore.sh` was written. This is that
gate's driver aimed one layer up: at the decoder, the editor and the
redraw.

SAFETY. It operates ONLY on a pty from `pty.openpty()`. The child's fd
0, 1 and 2 are the slave end, dup2'd in the fork; the invoking shell's
descriptors are never handed to anything that calls `sysTermRaw`, and
this script takes no descriptor argument that could be pointed at one.
It restores the pty under `finally` on every exit path, including a
failed step and an interrupt.

PACING, AND WHY IT IS NOT A SLEEP. The REPL forks `llc` and `cc` to
evaluate, so "wait a bit" is a race whose loser is a flaky gate. Each
step therefore names what it is waiting FOR:

  ["send", "<python bytes literal>"]  write those bytes to the master
  ["prompt"]                         wait until NEW output has arrived and
                                     the transcript then ends with the
                                     editor's empty-prompt park - CR,
                                     then CSI <pcols> C - which is what
                                     the redraw emits and nothing else
                                     does. The "new output" half is not
                                     belt and braces: without it the step
                                     matches the park left by the
                                     PREVIOUS prompt and returns before
                                     the child has read a byte, so the
                                     next send lands during an evaluation
                                     and is flushed away when raw mode is
                                     re-entered. Found that way: `:quit`
                                     was echoed by the cooked-mode line
                                     discipline and then discarded, and
                                     the REPL sat waiting forever.
  ["quiet", ms]                      wait for ms of no output
  ["mark", "name"]                   record the transcript's length HERE,
                                     so a later check can replay only the
                                     prefix up to this moment - which is
                                     how the screen is inspected mid-line
                                     without the keys that end the
                                     session overwriting it first
  ["exit"]                           wait for the child to exit

TYPE-AHEAD IS DISCARDED ACROSS AN EVALUATION and that is not a bug in
this driver. `sysTermRestore` and `sysTermRaw` both use the FLUSHING
ioctl, so bytes still in the kernel's input queue when the REPL leaves
or re-enters raw mode are dropped - see term.ax's header. A driver that
fired its whole script at once would lose half of it, and would then
report the loss as a broken editor.

Output: the raw transcript on stdout, and KEY=VALUE findings on stderr,
so the gate asserts on values rather than on prose it greps.
"""
import os, pty, sys, select, time, termios, fcntl, struct, json

def main():
    if len(sys.argv) < 5:
        sys.stderr.write("usage: drive.py <prog> <rows> <cols> <script.json>\n")
        return 2
    prog, rows, cols, script_path = sys.argv[1], int(sys.argv[2]), int(sys.argv[3]), sys.argv[4]
    steps = json.load(open(script_path))
    stdlib = os.environ.get("AXIOM_STDLIB", "")

    try:
        master, slave = pty.openpty()
    except Exception as e:
        print("PY_NO_PTY=%s" % type(e).__name__, file=sys.stderr)
        return 3

    saved = termios.tcgetattr(slave)
    try:
        fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", rows, cols, 0, 0))
        before = termios.tcgetattr(slave)

        pid = os.fork()
        if pid == 0:
            # NO setsid()/TIOCSCTTY. Making the child the session
            # leader of this pty means the kernel REVOKES the terminal
            # when it exits, and `tcgetattr` on the slave afterwards
            # answers ENOTTY - so the one question this driver most
            # needs to ask after the REPL is gone, "was the terminal
            # put back", becomes unaskable. Measured on this host
            # 2026-08-31: with setsid the post-exit sample raised
            # `termios.error (25, Inappropriate ioctl for device)`.
            # `sysIsatty` and every ioctl in stdlib/Sys.ax are
            # attribute queries on the descriptor and need no
            # controlling terminal, and ISIG is off in raw mode, so
            # nothing here wants a job-control session.
            os.dup2(slave, 0); os.dup2(slave, 1); os.dup2(slave, 2)
            os.close(master); os.close(slave)
            if stdlib:
                os.environ["AXIOM_STDLIB"] = stdlib
            os.execv(prog, [prog, "repl", "--no-banner"])

        # The editor parks the cursor on an empty line with CR then
        # `ESC [ <pcols> C`. Seven is `visLen` of the painted prompt;
        # the gate asserts that number separately, so a prompt that
        # changed width fails there and not here as a timeout.
        park = b"\r\x1b[7C"

        out = bytearray()
        marks = []
        exited = None
        step = 0
        mark_len = -1
        last_len = 0
        last_change = time.time()
        # Two budgets, because one is not enough. The overall deadline
        # bounds a healthy run (a few seconds; the REPL forks llc and
        # cc per expression). The PER-STEP stall is what stops a
        # BROKEN run from burning the whole budget on one wait:
        # measured while ablating `replInteractive` to false, where
        # every ["prompt"] step waited the full deadline and the gate
        # took minutes to report a failure it knew about in seconds.
        deadline = time.time() + 100
        step_deadline = time.time() + 25

        def pump(timeout):
            nonlocal out, exited
            r, _, _ = select.select([master], [], [], timeout)
            if r:
                try:
                    c = os.read(master, 65536)
                except OSError:
                    return False
                if not c:
                    return False
                out += c
            return True

        stalled = None
        while step < len(steps) and time.time() < deadline:
            if time.time() > step_deadline:
                stalled = step
                break
            s = steps[step]
            prev_step = step
            kind = s[0]
            if kind == "send":
                os.write(master, eval(s[1], {"__builtins__": {}}))
                step += 1
                last_change = time.time()
                last_len = len(out)
                mark_len = len(out)
            elif kind == "prompt":
                if len(out) > mark_len and bytes(out).endswith(park):
                    step += 1
                    mark_len = len(out)
                else:
                    if not pump(0.1):
                        print("PY_EOF_WAITING_PROMPT=1", file=sys.stderr)
                        break
            elif kind == "quiet":
                pump(0.05)
                if len(out) != last_len:
                    last_len = len(out); last_change = time.time()
                elif (time.time() - last_change) * 1000.0 >= s[1]:
                    step += 1
            elif kind == "mark":
                marks.append((s[1], len(out)))
                step += 1
            elif kind == "exit":
                d, st = os.waitpid(pid, os.WNOHANG)
                if d == pid:
                    exited = st
                    step += 1
                else:
                    pump(0.1)
            else:
                print("PY_BAD_STEP=%s" % kind, file=sys.stderr)
                return 2
            if step != prev_step:
                step_deadline = time.time() + 25

        # Drain whatever is still in flight before sampling.
        for _ in range(6):
            if not pump(0.1):
                break

        # Sampled AFTER the child is gone and BEFORE the pty is
        # closed, which is the only moment at which "the REPL left the
        # terminal as it found it" is a question about a finished
        # process rather than a running one.
        after = None

        if exited is None:
            waited = time.time() + 8
            while time.time() < waited:
                d, st = os.waitpid(pid, os.WNOHANG)
                if d == pid:
                    exited = st
                    break
                time.sleep(0.05)
        if exited is None:
            # Never a bare waitpid. A REPL left in raw mode with nothing
            # to read blocks forever, and a gate that hangs where it
            # should fail is worse than no gate.
            os.kill(pid, 9)
            _, exited = os.waitpid(pid, 0)
            print("PY_CHILD_KILLED=1", file=sys.stderr)
        try:
            after = termios.tcgetattr(slave)
        except Exception as e:
            print("PY_NO_SAMPLE=%s" % e, file=sys.stderr)
    finally:
        try:
            termios.tcsetattr(slave, termios.TCSAFLUSH, saved)
        except Exception:
            pass
        try:
            os.close(master); os.close(slave)
        except Exception:
            pass

    LFLAG = 3
    if after is None:
        print("PY_SAMPLE_FAILED=1", file=sys.stderr)
        after = [0, 0, 0, 0]
        before = [1, 1, 1, 1]
    if stalled is not None:
        print("PY_STALLED_AT=%d" % stalled, file=sys.stderr)
        print("PY_STALLED_ON=%s" % steps[stalled][0], file=sys.stderr)
    print("PY_STEPS_DONE=%d" % step, file=sys.stderr)
    print("PY_STEPS_TOTAL=%d" % len(steps), file=sys.stderr)
    print("PY_EXIT=%d" % (os.WEXITSTATUS(exited) if os.WIFEXITED(exited) else 128), file=sys.stderr)
    print("PY_ECHO_AFTER=%d"   % (1 if after[LFLAG] & termios.ECHO   else 0), file=sys.stderr)
    print("PY_ICANON_AFTER=%d" % (1 if after[LFLAG] & termios.ICANON else 0), file=sys.stderr)
    print("PY_ISIG_AFTER=%d"   % (1 if after[LFLAG] & termios.ISIG   else 0), file=sys.stderr)
    print("PY_TERMIOS_EXACT=%d" % (1 if before == after else 0), file=sys.stderr)
    for name, off in marks:
        print("PY_MARK_%s=%d" % (name, off), file=sys.stderr)
    print("PY_ESC_COUNT=%d" % bytes(out).count(b"\x1b"), file=sys.stderr)
    print("PY_BYTES=%d" % len(out), file=sys.stderr)
    sys.stdout.buffer.write(bytes(out))
    return 0

if __name__ == "__main__":
    sys.exit(main())
