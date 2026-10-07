"""The task pool of `stdlib/Task.ax` (MM-PAR-13), transcribed for
`scripts/lib/protocol-model.py`, which installs it (`install`).

The filename follows the script convention; importlib loads it by path.

WHAT IS TRANSCRIBED. The pool's parent loop, `taskLoop`, and every step it
takes on shared state or on a child: the token's cancel flag and event
counter, a slot's state word, the spawn, the look at a child
(`sysChildExited`), the kill, the join that reaps, the clock, and the
sleep on the event counter. And the child's half, `taskChild`: its answer
into its slot, over the limit or not, and the bump that wakes the parent.
The parent's per-slot words (`st`) and its handles (`hs`) are its own, so
their accesses are plain steps inside the one before them.

A TASK'S BODY is the program's `f`, which the model does not run: each
task is given one of five behaviours, fixed or chosen at its start - it
answers within the limit, answers over it, traps (exit 72), runs for ever
(`hang`), or answers and then cannot exit (`stuck`).

TIME is a clock word, in units of the poll period's half (`POLL` is two
units, the first exit nap one). The pool's own steps take no time; the
clock moves only while the pool sleeps or waits in a join, one unit per
environment step, up to the scenario's horizon, and a sleep times out only
once the clock has reached the wake time the pool computed. Deadlines and
grace are small multiples of the unit. That is what lets the model check
the pool's timing: when the clock would move past a running task's
deadline, or past the end of a cancellation's grace with a task still
alive, while the pool sleeps, the pool computed its wake time wrong.

WHAT IS CHECKED, in every reachable state and at the end:
  one slot each      task t is delivered once, t-th, in submit order, and
                     its result is what happened to it: its own answer, the
                     over-limit refusal, its trap status, the deadline's kill,
                     the cancellation's kill, or never started because the
                     pool was cancelled first;
  bounded            at most `w` children exist at once, a handle is kept at
                     one of `w` places, and nothing starts once the pool has
                     seen a cancellation;
  on time            the pool never sleeps past a running task's deadline,
                     nor past the end of a cancellation's grace;
  nothing outlives   when the pool returns, every child it started has been
                     reaped;
  liveness           every binding can still finish (the model's LOST
                     WAKEUP, DEADLOCK and LIVELOCK), given the clock.

WHAT IT IS NOT. A proof about the model at its bounds (two and three tasks,
widths one to three, a few units of time), not about Task.ax: the bytes of
an answer are one word, the sink and the region around it are a delivery
step, a spawn that is refused (78, which `taskStart` answers and `taskLoop`
turns into a cancellation) and a parent killed from outside are outside it,
and the clock is the model's.
"""

TASK = "Task.ax"

# Behaviours of a task's body.
OK, BIG, TRAP, HANG, STUCK, SLOW, QUIT = 0, 1, 2, 3, 4, 5, 6
BEHAVIOUR = {OK: "answers", BIG: "answers over the limit", TRAP: "traps", HANG: "runs for ever",
             STUCK: "answers and cannot exit", SLOW: "answers after a while",
             QUIT: "exits 0 without answering (sysExitWith 0)"}
QUIT_MARK = 1000   # a fate's "trapped" for a task that exited 0 unanswered
# What a delivery says (taskResultAt's branches, and taskDeliverCancelled).
R_OK, R_BIG, R_NOANSWER, R_TIMEDOUT, R_CANCELLED, R_TRAP, R_NOTSTARTED = range(7)
R_NAME = ["its answer", "over the limit", "ended without an answer", "past its deadline", "cancelled",
          "trapped", "not started"]

SB = 4        # a slot's words: 0 state, 1 length, 2 the child's pid, 3 the answer
POLL = 2      # taskPollNanos, in the model's units
NAP1 = 1      # taskExitNapFirst
LIMIT = 1     # the byte limit: an answer is one unit, an over-limit one two


def task_mem(n, w):
    """Word layout: 0 the token's cancel flag and 1 its event counter, 2 the
    clock, then each task's exit status, the slab, and the parent's own
    per-slot words (`st`, three a slot) and handles (`hs`)."""
    lay = {"tok": 0, "clock": 2, "exit": 3, "slab": 3 + n}
    lay["st"] = lay["slab"] + SB * w
    lay["hs"] = lay["st"] + 3 * w
    lay["idle"] = lay["hs"] + w
    return lay, [0] * (lay["idle"] + 1)


def install(ns):
    F = ns["F"]
    Scenario = ns["Scenario"]
    Model = ns["Model"]
    Violation = ns["Violation"]

    # ---- the parent's half ------------------------------------------------
    F("taskEvent", ["tok"], ["e"], (TASK, "taskEvent"), [
        ("aload", "e", "tok + 1", "(taskLoadAt (+ tok 8))"),
        ("ret", "e"),
    ])
    F("taskCancelledAt", ["tok"], ["c"], (TASK, "taskCancelledAt"), [
        ("aload", "c", "tok", "(taskLoadAt tok)"),
        ("ret", "1 if c == 1 else 0"),
    ])
    F("taskCancelAt", ["tok"], [], (TASK, "taskCancelAt"), [
        ("astore", "tok", "1", "(taskStoreAt tok 1)"),
        ("call", None, "taskBump", ["tok"], "(taskBump tok)"),
        ("ret", "0"),
    ])
    F("taskCancel", ["tok"], [], (TASK, "taskCancel"), [
        ("call", None, "taskCancelAt", ["tok"], "(taskCancelAt (taskTokenAt t))"),
        ("ret", "0"),
    ])
    F("taskBump", ["tok"], [], (TASK, "taskBump"), [
        ("aadd", None, "tok + 1", "1", "(taskAddAt (+ tok 8) 1)"),
        ("call", None, "sysWakeWord", ["tok + 1"], "(sysWakeWord (+ tok 8))"),
        ("ret", "0"),
    ])
    F("taskStart", ["st", "hs", "t", "w", "slab", "D"], ["s", "slot", "h", "c"], (TASK, "taskStart"), [
        ("set", "s", "t % w", "(s (% t w))"),
        ("set", "slot", "slab + %d * s" % SB, "(slot (+ slab (* (% t w) slotBytes)))"),
        ("astore", "slot", "1", "(taskStoreAt slot 1)"),
        ("pstore", "slot + 1", "0", "(memSetWord slot 1 0)"),
        ("pstore", "slot + 2", "0", "(memSetWord slot 2 0)"),
        ("ghost", "tStart", ["t", "w"]),
        ("spawn", "h", "t * w + s", "t + 1", "(taskSpawn wrapper (+ (* t w) s))"),
        ("if", "t < w", "reuse", "(if (< t w)"),
        ("ghost", "tHandle", ["t", "w"]),
        ("pstore", "hs + t", "h", "(vecPush hs h)"),
        ("goto", "stamp"),
        ("L", "reuse"),
        ("ghost", "tHandle", ["s", "w"]),
        ("pstore", "hs + s", "h", "(vecSet hs s h)"),
        ("L", "stamp"),
        ("if", "D > 0", "nodl"),
        ("clock", "c", "(sysTimeoutMicros clk)"),
        ("pstore", "st + 3 * s", "c + D"),
        ("goto", "rest"),
        ("L", "nodl"),
        ("pstore", "st + 3 * s", "0"),
        ("L", "rest"),
        ("pstore", "st + 3 * s + 1", "0", "(taskSetSt st s 1 0)"),
        ("pstore", "st + 3 * s + 2", "0", "(taskSetSt st s 2 0)"),
        ("ret", "0"),
    ])
    F("taskEnded", ["hs", "s", "slab", "canPoll"], ["st8", "answered", "h", "x"], (TASK, "taskEnded"), [
        ("aload", "st8", "slab + %d * s" % SB, "(taskLoadAt (+ slab (* s slotBytes)))"),
        ("set", "answered", "1 if st8 >= 2 else 0"),
        ("if", "canPoll == 1", "nolook", "(if (== canPoll 1)"),
        ("pload", "h", "hs + s"),
        ("look", "x", "h", "(sysChildExited (taskHandlePid (vecGet hs s)) pbuf)"),
        ("if", "x >= 0", "failed"),
        ("ret", "1 if x == 1 else (2 if answered == 1 else 0)"),
        ("L", "failed"),
        ("ret", "1 if answered == 1 else -1"),
        ("L", "nolook"),
        ("ret", "1 if answered == 1 else 0"),
    ])
    F("taskJoin", ["st", "hs", "s", "slab", "why"], ["h", "status", "state"], (TASK, "taskJoin"), [
        ("pload", "h", "hs + s"),
        ("join", "status", "h", "(__proc_join_nr (vecGet hs s) cell)"),
        ("aload", "state", "slab + %d * s" % SB, "(taskLoadAt (+ slab (* s slotBytes)))"),
        ("pstore", "st + 3 * s + 1", "status", "(taskSetSt st s 1 status)"),
        ("pstore", "st + 3 * s + 2", "why", "(taskSetSt st s 2 why)"),
        ("if", "why == 3", "counts", "(if (== why 3)"),
        ("ret", "0"),
        ("L", "counts"),
        ("ret", "0 if state == 2 and (status == 0 or (status == 137 and why >= 2)) else 1",
         "(if (&& (== state 2) (|| (== status 0) (&& (== status 137) (>= why 2))))"),
    ])
    F("taskKillJoin", ["st", "hs", "s", "slab", "why"], ["h", "k", "r"], (TASK, "taskKillJoin"), [
        ("pload", "h", "hs + s"),
        ("kill9", "k", "h", "(sysKill (taskHandlePid (vecGet hs s)) 9)"),
        ("call", "r", "taskJoin", ["st", "hs", "s", "slab", "why"], "(taskJoin"),
        ("ret", "r"),
    ])
    F("taskCheck", ["st", "hs", "s", "now", "cancelling", "graceEnd", "canPoll", "slab"], ["ended", "r", "d"],
      (TASK, "taskCheck"), [
        ("call", "ended", "taskEnded", ["hs", "s", "slab", "canPoll"], "(taskEnded"),
        ("if", "ended == 1", "late", "(if (== ended 1)"),
        ("call", "r", "taskJoin", ["st", "hs", "s", "slab", "1"], "(taskJoin"),
        ("ret", "r"),
        ("L", "late"),
        ("pload", "d", "st + 3 * s"),
        ("if", "d > 0 and now >= d", "grace", "(>= now (taskSt st s 0))"),
        ("call", "r", "taskKillJoin", ["st", "hs", "s", "slab", "2"], "(taskKillJoin"),
        ("ret", "r"),
        ("L", "grace"),
        ("if", "cancelling == 1 and now >= graceEnd", "none", "(>= now graceEnd)"),
        ("call", "r", "taskKillJoin", ["st", "hs", "s", "slab", "3"], "(taskKillJoin"),
        ("ret", "r"),
        ("L", "none"),
        ("ret", "-2 if ended == -1 else -1", "(if (== ended (- 0 1))"),
    ])
    F("taskResultAt", ["slot", "status", "why", "t"], ["state", "fin", "ans"], (TASK, "taskResultAt"), [
        ("aload", "state", "slot", "(taskLoadAt slot)"),
        ("set", "fin", "1 if status == 0 or (status == 137 and why >= 2) else 0",
         "(finished (|| (== status 0) (&& (== status 137) (>= why 2))))"),
        ("if", "fin == 1 and state == 2", "big", "(if (&& finished (== state 2))"),
        ("pload", "ans", "slot + 3", "(taskCopyOut slot)"),
        ("ghost", "tDeliver", ["t", str(R_OK), "status", "why", "ans"]),
        ("ret", "0"),
        ("L", "big"),
        ("if", "fin == 1 and state == 3", "noanswer", "(if (&& finished (== state 3))"),
        ("ghost", "tDeliver", ["t", str(R_BIG), "status", "why", "-1"]),
        ("ret", "0"),
        ("L", "noanswer"),
        ("if", "status == 0", "deadline", "(if (== status 0)"),
        ("ghost", "tDeliver", ["t", str(R_NOANSWER), "status", "why", "-1"]),
        ("ret", "0"),
        ("L", "deadline"),
        ("if", "status == 137 and why == 2", "cancel", "(if (&& (== status 137) (== why 2))"),
        ("ghost", "tDeliver", ["t", str(R_TIMEDOUT), "status", "why", "-1"]),
        ("ret", "0"),
        ("L", "cancel"),
        ("if", "status == 137 and why == 3", "trap", "(if (&& (== status 137) (== why 3))"),
        ("ghost", "tDeliver", ["t", str(R_CANCELLED), "status", "why", "-1"]),
        ("ret", "0"),
        ("L", "trap"),
        ("ghost", "tDeliver", ["t", str(R_TRAP), "status", "why", "-1"]),
        ("ret", "0"),
    ])
    # `t`, the task's index, exists only in the model. The sink takes the
    # answers in submit order and needs none; the check uses it.
    F("taskDeliver", ["st", "s", "slab", "t"], ["slot", "status", "why"], (TASK, "taskDeliver"), [
        ("set", "slot", "slab + %d * s" % SB, "(slot (+ slab (* s slotBytes)))"),
        ("pload", "status", "st + 3 * s + 1", "(status (taskSt st s 1))"),
        ("pload", "why", "st + 3 * s + 2", "(why (taskSt st s 2))"),
        ("call", None, "taskResultAt", ["slot", "status", "why", "t"], "(taskResultAt slot status why)"),
        ("ret", "0"),
    ])
    F("taskDeliverCancelled", ["t"], [], (TASK, "taskDeliverCancelled"), [
        ("ghost", "tDeliver", ["t", str(R_NOTSTARTED), "0", "0", "-1"]),
        ("ret", "0", '(mkError taskCancelledCode "task not started: the pool was cancelled")'),
    ])
    F("taskWakeBy", ["st", "head", "nxt", "w", "now", "canPoll", "cancelling", "graceEnd", "slab", "nap"],
      ["wake", "running", "answered", "t", "s", "k", "a", "d", "p"], (TASK, "taskWakeBy"), [
        ("set", "wake", "graceEnd if cancelling == 1 else -1", "(mut wake (if (== cancelling 1)"),
        ("set", "running", "0"),
        ("set", "answered", "0"),
        ("set", "t", "head", "(for t in head..next"),
        ("L", "loop"),
        ("if", "t < nxt", "end"),
        ("set", "s", "t % w"),
        ("pload", "k", "st + 3 * s + 2", "(if (== (taskSt st s 2) 0)"),
        ("if", "k == 0", "next"),
        ("set", "running", "1"),
        ("aload", "a", "slab + %d * s" % SB, "(>= (taskLoadAt (+ slab (* s slotBytes))) 2)"),
        ("if", "a >= 2", "deadline"),
        ("set", "answered", "1"),
        ("L", "deadline"),
        ("pload", "d", "st + 3 * s", "(let ((d (taskSt st s 0)))"),
        ("if", "d > 0 and (wake < 0 or d < wake)", "next", "(if (&& (> d 0) (|| (< wake 0) (< d wake)))"),
        ("set", "wake", "d"),
        ("L", "next"),
        ("set", "t", "t + 1"),
        ("goto", "loop"),
        ("L", "end"),
        ("if", "running == 0", "some", "(if (== running 0)"),
        ("ret", "-1"),
        ("L", "some"),
        ("if", "canPoll == 1", "nopoll", "(if (== canPoll 1)"),
        ("set", "p", "now + (nap if answered == 1 else %d)" % POLL, "(taskPollPeriod answered nap)"),
        ("ret", "p if (wake < 0 or p < wake) else wake", "(if (|| (< wake 0) (< p wake))"),
        ("L", "nopoll"),
        ("ret", "wake"),
    ])
    # The pool. `n` tasks at width `w` (already clamped to 1..n), a deadline
    # of `D` units (0 none), a grace of `G`, fail-fast `ff`; `tok`, `slab`,
    # `st` and `hs` are where their words are.
    F("taskLoop", ["n", "w", "D", "G", "ff", "tok", "slab", "st", "hs"],
      ["nxt", "head", "cancelling", "graceEnd", "canPoll", "progress", "nap", "seen", "now", "t", "s", "r", "c",
       "k", "wake", "code"], (TASK, "taskLoop"), [
        ("set", "canPoll", "1"),
        ("set", "nap", str(NAP1)),
        ("L", "top"),
        ("if", "head < n", "done"),
        ("call", "seen", "taskEvent", ["tok"], "(taskEvent tok)"),
        ("clock", "now", "(sysTimeoutMicros clk)"),
        ("set", "progress", "0"),
        ("if", "cancelling == 0", "start"),
        ("call", "c", "taskCancelledAt", ["tok"], "(taskCancelledAt tok)"),
        ("if", "c == 1", "start"),
        ("set", "cancelling", "1"),
        ("set", "graceEnd", "now + G", "(set graceEnd (+ now graceUs))"),
        ("ghost", "tCancelSeen", []),
        ("set", "progress", "1"),
        ("L", "start"),
        ("if", "cancelling == 0 and nxt < n and nxt - head < w", "checks", "(< (- next head) w)"),
        ("call", None, "taskStart", ["st", "hs", "nxt", "w", "slab", "D"], "(taskStart"),
        ("set", "nxt", "nxt + 1"),
        ("set", "progress", "1"),
        ("goto", "start"),
        ("L", "checks"),
        ("set", "t", "head"),
        ("L", "check"),
        ("if", "t < nxt", "delivers"),
        ("set", "s", "t % w"),
        ("pload", "k", "st + 3 * s + 2"),
        ("if", "k == 0", "nextcheck"),
        ("call", "r", "taskCheck", ["st", "hs", "s", "now", "cancelling", "graceEnd", "canPoll", "slab"],
         "(taskCheck"),
        ("if", "r == -2", "counted"),
        ("set", "canPoll", "0", "(set canPoll 0)"),
        ("goto", "nextcheck"),
        ("L", "counted"),
        ("if", "r >= 0", "nextcheck"),
        ("set", "progress", "1"),
        ("if", "r == 1 and ff == 1", "nextcheck"),
        ("call", None, "taskCancelAt", ["tok"], "(taskCancelAt tok)"),
        ("L", "nextcheck"),
        ("set", "t", "t + 1"),
        ("goto", "check"),
        ("L", "delivers"),
        ("if", "head < nxt", "cancels"),
        ("pload", "k", "st + 3 * (head % w) + 2"),
        ("if", "k != 0", "cancels"),
        ("call", None, "taskDeliver", ["st", "head % w", "slab", "head"], "(taskDeliver"),
        ("set", "head", "head + 1"),
        ("set", "progress", "1"),
        ("goto", "delivers"),
        ("L", "cancels"),
        ("if", "cancelling == 1 and head == nxt and nxt < n", "idle"),
        ("call", None, "taskDeliverCancelled", ["head"], "(taskDeliverCancelled sink scoped)"),
        ("set", "nxt", "nxt + 1"),
        ("set", "head", "head + 1"),
        ("set", "progress", "1"),
        ("goto", "cancels"),
        ("L", "idle"),
        ("if", "progress == 0", "busy"),
        ("call", "wake", "taskWakeBy", ["st", "head", "nxt", "w", "now", "canPoll", "cancelling", "graceEnd",
                                        "slab", "nap"], "(taskWakeBy"),
        ("set", "nap", "min(nap * 2, %d)" % POLL, "(taskNapNext nap)"),
        ("if", "wake >= 0", "nowake"),
        ("call", "code", "taskSleepUntil", ["tok + 1", "seen", "wake if wake > now else now"],
         "(sysWaitWordTimeout (+ tok 8) seen (taskSleepFor now wake))"),
        ("goto", "top"),
        ("L", "nowake"),
        ("if", "head < nxt", "top"),
        ("pload", "k", "st + 3 * (head % w) + 2"),
        ("if", "k == 0", "top"),
        ("call", "r", "taskJoin", ["st", "hs", "head % w", "slab", "1"], "(taskJoin"),
        ("if", "r == 1 and ff == 1", "top"),
        ("call", None, "taskCancelAt", ["tok"], "(taskCancelAt tok)"),
        ("goto", "top"),
        ("L", "busy"),
        ("set", "nap", str(NAP1), "(set nap taskExitNapFirst)"),
        ("goto", "top"),
        ("L", "done"),
        ("ret", "head"),
    ])
    # The kernel's wait on the event counter, timed out by the clock:
    # `sysWaitWordTimeout`'s entry load and its wait, with the time the pool
    # asked for as an absolute reading of the model's clock.
    F("taskSleepUntil", ["addr", "expected", "at"], ["cur", "code"], None, [
        ("uload", "cur", "addr"),
        ("if", "cur != expected", "sleep"),
        ("ret", "2"),
        ("L", "sleep"),
        ("sleepuntil", "code", "addr", "expected", "at"),
        ("ret", "code"),
    ])

    # ---- the child's half ---------------------------------------------------
    # `beh` is the tuple of behaviours the task's `f` may have.
    # A `slow` body takes `x` units of the clock, sleeping on `idle`, a
    # word nobody writes, before it answers.
    F("taskChild", ["tok", "slab", "w", "lim", "beh", "x", "idle", "arg"], ["slot", "p", "b", "c0", "c", "code", "len"],
      (TASK, "taskChild"), [
        ("set", "slot", "slab + %d * (arg %% w)" % SB, "(let ((slot (+ slab (* (% arg w) slotBytes))))"),
        ("pid", "p"),
        ("pstore", "slot + 2", "p", "(memSetWord slot 2 sysPid)"),
        ("choose", "b", "beh"),
        ("if", "b == %d" % SLOW, "work"),
        ("clock", "c0"),
        ("L", "nap"),
        ("clock", "c"),
        ("if", "c < c0 + x", "work"),
        ("sleepuntil", "code", "idle", "0", "c0 + x"),
        ("goto", "nap"),
        ("L", "work"),
        ("if", "b == %d" % TRAP, "runs", "(let ((r (f (/ arg w))))"),
        ("ghost", "tTrap", ["arg // w", "72"]),
        ("ret", "72"),
        ("L", "runs"),
        ("if", "b == %d" % QUIT, "stays"),
        ("ghost", "tTrap", ["arg // w", str(QUIT_MARK)]),
        ("ret", "0"),
        ("L", "stays"),
        ("if", "b == %d" % HANG, "answers"),
        ("block",),
        ("L", "answers"),
        ("set", "len", "lim + 1 if b == %d else lim" % BIG),
        ("pstore", "slot + 1", "len", "(memSetWord slot 1 len)"),
        ("if", "len > lim", "fits", "(if (> len limit)"),
        ("astore", "slot", "3", "(taskStoreAt slot 3)"),
        ("ghost", "tAnswer", ["arg // w", "2"]),
        ("goto", "bump"),
        ("L", "fits"),
        ("pstore", "slot + 3", "arg // w", "(memCopy (+ slot 32) (strData r) len)"),
        ("astore", "slot", "2", "(taskStoreAt slot 2)"),
        ("ghost", "tAnswer", ["arg // w", "1"]),
        ("L", "bump"),
        ("call", None, "taskBump", ["tok"], "(taskBump tok)"),
        ("if", "b == %d" % STUCK, "exit"),
        ("block",),
        ("L", "exit"),
        ("ret", "0"),
    ])

    # ---- drivers --------------------------------------------------------------
    F("taskPool", ["n", "w", "D", "G", "ff", "tok", "slab", "st", "hs"], ["r"], None, [
        ("call", "r", "taskLoop", ["n", "w", "D", "G", "ff", "tok", "slab", "st", "hs"]),
        ("ghost", "tPoolDone", ["r"]),
        ("ret", "0"),
    ])
    F("taskCanceller", ["tok"], [], None, [
        ("call", None, "taskCancel", ["tok"]),
        ("ret", "0"),
    ])

    # ---- the checks -------------------------------------------------------------
    def fate(c, t):
        return list(c.ghost["fate"][t])

    def set_fate(c, t, f):
        fs = list(c.ghost["fate"])
        fs[t] = tuple(f)
        c.ghost["fate"] = tuple(fs)

    def g_tStart(self, c, b, t, w):
        if c.ghost["cseen"]:
            raise Violation("cancellation", "B%d started task %d after it saw the cancellation" % (b + 1, t))
        live = sum(1 for k in self.sc.tasks if c.procs[k] in ("A", "Z"))
        if live >= w:
            raise Violation("bounded", "B%d started task %d with %d children unreaped, at width %d" % (b + 1, t, live, w))
        f = fate(c, t)
        f[0] = 1
        set_fate(c, t, f)

    def g_tHandle(self, c, b, i, w):
        if not 0 <= i < w:
            raise Violation("bounded", "B%d kept a handle at place %d of %d" % (b + 1, i, w))

    def g_tCancelSeen(self, c, b):
        if c.mem[self.sc.lay["tok"]] != 1:
            raise Violation("cancellation", "B%d saw a cancellation the token does not hold" % (b + 1))
        c.ghost["cseen"] = 1

    def g_tAnswer(self, c, b, t, kind):
        f = fate(c, t)
        f[1] = kind
        set_fate(c, t, f)

    def g_tTrap(self, c, b, t, how):
        f = fate(c, t)
        f[2] = how
        set_fate(c, t, f)

    def g_tKilled(self, c, b, k):
        t = self.sc.tasks.index(k)
        f = fate(c, t)
        f[3] = 1
        set_fate(c, t, f)

    def g_tDeliver(self, c, b, t, kind, status, why, ans):
        started, answered, trapped, killed = c.ghost["fate"][t]
        d = c.ghost["deliv"]
        if t != d:
            raise Violation("one slot each", "task %d was delivered %s" % (
                t, "again" if t < d else "before task %d" % d))
        ok = {
            R_OK: answered == 1 and ans == t,
            R_BIG: answered == 2,
            R_NOANSWER: trapped == QUIT_MARK and not answered and status == 0,
            R_TIMEDOUT: killed and not answered and why == 2 and status == 137,
            R_CANCELLED: killed and not answered and why == 3 and status == 137 and c.ghost["cseen"],
            R_TRAP: trapped not in (0, QUIT_MARK) and status == trapped and not answered,
            R_NOTSTARTED: not started and c.ghost["cseen"],
        }[kind]
        if not ok:
            raise Violation("one slot each", "task %d was delivered as %s%s, and it %s" % (
                t, R_NAME[kind], " (the answer of task %d)" % ans if kind == R_OK else "",
                "; ".join(x for x in (
                    "was never started" if not started else "",
                    "answered" if answered == 1 else ("answered over the limit" if answered == 2 else ""),
                    "trapped" if trapped not in (0, QUIT_MARK) else "",
                    "exited 0 unanswered" if trapped == QUIT_MARK else "", "was killed" if killed else "",
                    "was cancelled" if c.ghost["cseen"] else "") if x) or "did nothing"))
        c.ghost["deliv"] = d + 1

    def g_tPoolDone(self, c, b, r):
        if r != self.sc.ntasks:
            raise Violation("one slot each", "the pool answered %d deliveries of %d" % (r, self.sc.ntasks))

    def g_tAsleepAt(self, c, now, frames):
        """The clock is about to move past `now` while the pool sleeps."""
        lay, w = self.sc.lay, self.sc.width
        loop = next((L for f, pc, L in frames if f == "taskLoop"), None)
        code = self.codes["taskLoop"]
        cancelling = loop[code.vars.index("cancelling")] if loop else 0
        grace_end = loop[code.vars.index("graceEnd")] if loop else 0
        for t, k in enumerate(self.sc.tasks):
            if c.procs[k] != "A":
                continue
            s = t % w
            d = c.mem[lay["st"] + 3 * s]
            if d > 0 and now >= d:
                raise Violation("on time", "the pool sleeps on at %d past task %d's deadline %d, and it runs" % (now, t, d))
            if cancelling == 1 and now >= grace_end:
                raise Violation("on time", "the pool sleeps on at %d past the cancellation's grace (%d), and task %d runs"
                                % (now, grace_end, t))

    for name, fn in list(locals().items()):
        if name.startswith("g_t"):
            setattr(Model, name, fn)

    base_final = Model.final_check
    base_condition = Model.condition

    def final_check(self, s):
        if self.sc.kind != "task":
            return base_final(self, s)
        g = dict(zip(self.gkeys, s[3]))
        if g["deliv"] != self.sc.ntasks:
            return Violation("one slot each", "the pool ended with %d of %d tasks delivered" % (g["deliv"], self.sc.ntasks))
        for t, k in enumerate(self.sc.tasks):
            if s[2][k] not in ("X", "-"):
                return Violation("nothing outlives", "the pool returned and task %d's process is %s"
                                 % (t, "alive" if s[2][k] == "A" else "unreaped"))
        return None

    def condition(self, s, b):
        if self.sc.kind != "task":
            return base_condition(self, s, b)
        fr = s[1][b][1][-1]
        ins = self.codes[fr[0]].ins[fr[1]]
        if ins[0] == "sleepuntil":
            return s[0][ins[2](*fr[2])] != ins[3](*fr[2]), "the event counter has moved"
        if ins[0] == "join":
            return s[2][self.sc.pids.index(ins[2](*fr[2]))] == "Z", "the child it joins has exited"
        return False, "nothing ends a task that blocks but a kill"

    Model.final_check = final_check
    Model.condition = condition

    base_ghost0 = Scenario.ghost0

    def ghost0(self):
        g = base_ghost0(self)
        if self.kind == "task":
            g.update(cseen=0, deliv=0, fate=tuple((0, 0, 0, 0) for _ in self.tasks))
        return g

    Scenario.ghost0 = ghost0

    # ---- scenarios ------------------------------------------------------------------
    def pool(name, behaviours, w, D=0, G=2, ff=0, cancel=False, lookable=True, x=2, horizon=None):
        n = len(behaviours)
        lay, mem = task_mem(n, w)
        bindings = [("taskPool", (n, w, D, G, ff, lay["tok"], lay["slab"], lay["st"], lay["hs"]))]
        for t, beh in enumerate(behaviours):
            bindings.append(("taskChild", (lay["tok"], lay["slab"], w, LIMIT, tuple(beh), x, lay["idle"], -1)))
        if cancel:
            bindings.append(("taskCanceller", (lay["tok"],)))
        sc = Scenario("task pool: " + name, "task", mem, bindings, progress=("n", "t", "c"))
        sc.procs = True
        sc.lay = lay
        sc.width = w
        sc.ntasks = n
        sc.tasks = list(range(1, n + 1))
        sc.parents = {k: 0 for k in sc.tasks}
        sc.exitword = {k: lay["exit"] + k - 1 for k in sc.tasks}
        sc.unspawned = frozenset(sc.tasks)
        sc.clock = lay["clock"]
        sc.lookable = lookable
        sc.drains = False
        # Enough time for every task to run to its deadline, one batch of
        # width after another, with the grace and a poll period to spare.
        sc.horizon = horizon or (-(-n // w)) * (max(D, x) + POLL + 1) + G + 2 * POLL + 2
        return sc

    A3 = (OK, BIG, TRAP)
    A4 = (OK, BIG, TRAP, QUIT)
    A2 = (OK, TRAP)

    def task_scenarios(long=False):
        out = [
            pool("2 tasks at width 1, each answers, answers too much or traps", [A3, A3], 1),
            pool("2 tasks at width 2, each answers, answers too much, traps or exits unanswered", [A4, A4], 2),
            pool("3 tasks at width 2, each answers or traps", [A2, A2, A2], 2),
            pool("a task past its deadline, then one that answers, width 1", [(HANG,), (OK,)], 1, D=3),
            pool("a task past its deadline, alone", [(HANG,)], 1, D=3),
            pool("2 tasks at width 2 with a deadline, each answers, runs for ever or cannot exit",
                 [(OK, HANG, STUCK), (OK, HANG, STUCK)], 2, D=3),
            # A body that takes exactly its deadline: the answer and the kill race.
            pool("a slow task against its deadline, then one that answers, width 1", [(SLOW,), (OK,)], 1, D=3, x=3),
            pool("2 tasks at width 2 with a deadline, each slow or cannot exit", [(SLOW, STUCK), (SLOW, OK)], 2,
                 D=3, x=3),
            pool("cancelled from a sibling while a slow task works, 2 tasks at width 1", [(SLOW,), (OK,)], 1,
                 G=1, x=3, cancel=True),
            pool("cancelled from a sibling, 3 tasks at width 1, the first runs for ever", [(HANG,), (OK,), (OK,)], 1,
                 G=2, cancel=True),
            pool("cancelled from a sibling, 2 tasks at width 2, one cannot exit and one answers",
                 [(STUCK,), (OK, TRAP)], 2, D=4, G=1, cancel=True),
            pool("fail-fast, 3 tasks at width 2: a trap beside one that runs for ever", [(TRAP,), (HANG,), (OK,)], 2,
                 G=2, ff=1),
            pool("fail-fast, 3 tasks at width 1: an answer, then a trap, then one never started",
                 [(OK,), (TRAP, OK), (OK,)], 1, ff=1),
            pool("no look at a child, 2 tasks at width 1, each answers or traps", [A2, A2], 1, lookable=False),
            pool("no look at a child, a task past its deadline beside one that traps, width 2", [(HANG,), (TRAP,)], 2,
                 D=3, lookable=False),
            # With no look and no deadline, only the join on the oldest task
            # finds the trap, and fail-fast cancels from there.
            pool("no look at a child, fail-fast, a trap beside one that runs for ever, width 2",
                 [(TRAP,), (HANG,), (OK,)], 2, G=2, ff=1, lookable=False),
        ]
        out += [
            pool("3 tasks at width 2, each answers, answers too much or traps", [A3, A3, A3], 2),
            pool("3 tasks at width 3, each answers or traps", [A2, A2, A2], 3),
        ]
        if long:
            out += [
                pool("3 tasks at width 2 with a deadline, each answers, runs for ever or cannot exit",
                     [(OK, HANG, STUCK)] * 3, 2, D=3),
                pool("cancelled from a sibling, 3 tasks at width 2, each answers, runs for ever or cannot exit",
                     [(OK, HANG, STUCK)] * 3, 2, D=5, G=2, cancel=True),
            ]
        return out

    ns["EXTRA_SCENARIOS"].append(task_scenarios)

    # ---- planted defects ----------------------------------------------------------------
    replace = ns["replace"]

    def d_no_deadline_kill(fns):
        # check-task.sh's `kill` ablation: the deadline's SIGKILL is a
        # signal 0, so the task runs on.
        replace(fns, "taskKillJoin", [("kill9", "k", "h", "(sysKill (taskHandlePid (vecGet hs s)) 9)")],
                [("set", "k", "0")])

    def d_wake_ignores_deadline(fns):
        replace(fns, "taskWakeBy", [("set", "wake", "d")], [])

    def d_wake_ignores_grace(fns):
        replace(fns, "taskWakeBy", [("set", "wake", "graceEnd if cancelling == 1 else -1",
                                     "(mut wake (if (== cancelling 1)")], [("set", "wake", "-1")])

    def d_no_grace_kill(fns):
        # check-task.sh's `grace` ablation.
        replace(fns, "taskCheck", [("if", "cancelling == 1 and now >= graceEnd", "none", "(>= now graceEnd)")],
                [("if", "cancelling == 2 and now >= graceEnd", "none")])

    def d_join_on_answer(fns):
        # check-task.sh's `exitjoin` ablation: an answer is taken for an exit.
        replace(fns, "taskEnded", [("ret", "1 if x == 1 else (2 if answered == 1 else 0)")],
                [("ret", "1 if x == 1 or answered == 1 else 0")])

    def d_slot_mixup(fns):
        # check-task.sh's `slot` ablation: a task answers into its neighbour's slot.
        replace(fns, "taskChild", [("set", "slot", "slab + %d * (arg %% w)" % SB,
                                    "(let ((slot (+ slab (* (% arg w) slotBytes))))")],
                [("set", "slot", "slab + %d * ((arg + 1) %% w)" % SB)])

    def d_start_after_cancel(fns):
        replace(fns, "taskLoop", [("if", "cancelling == 0 and nxt < n and nxt - head < w", "checks",
                                   "(< (- next head) w)")],
                [("if", "nxt < n and nxt - head < w", "checks")])

    def d_push_every_handle(fns):
        replace(fns, "taskStart", [("if", "t < w", "reuse", "(if (< t w)")], [])

    def d_kill_without_join(fns):
        replace(fns, "taskKillJoin", [("call", "r", "taskJoin", ["st", "hs", "s", "slab", "why"], "(taskJoin")],
                [("pstore", "st + 3 * s + 1", "137"), ("pstore", "st + 3 * s + 2", "why"), ("set", "r", "0")])

    def pick(*names):
        def make():
            return [s for s in task_scenarios() if any(n in s.name for n in names)]
        return make

    ns["DEFECTS"].extend([
        ("task deadline kill removed",
         "the kill at a task's deadline sends signal 0, so the task runs on (check-task.sh's kill ablation)",
         d_no_deadline_kill, "deadlock", pick("a task past its deadline, then")),
        ("task wake ignores deadlines",
         "the pool's wake time leaves out the running tasks' deadlines, so it sleeps a poll period past one",
         d_wake_ignores_deadline, "on time", pick("a task past its deadline, then")),
        ("task grace kill removed",
         "a cancellation's grace never runs out (check-task.sh's grace ablation)",
         d_no_grace_kill, "livelock", pick("the first runs for ever")),
        ("task joined on its answer alone",
         "a task that answered is joined before it exits (check-task.sh's exitjoin ablation)",
         d_join_on_answer, "deadlock", pick("runs for ever or cannot exit")),
        ("task answers into its neighbour's slot",
         "a task's answer goes to the next slot (check-task.sh's slot ablation)",
         d_slot_mixup, "one slot each", pick("2 tasks at width 2, each answers, answers too much")),
        ("task started after the cancellation",
         "the start loop no longer stops once the pool has seen its token set",
         d_start_after_cancel, "cancellation", pick("3 tasks at width 1, the first runs for ever")),
        ("task handle pushed for every task",
         "every task's handle is pushed, so the handles grow with n, not w",
         d_push_every_handle, "bounded", pick("3 tasks at width 2, each answers or traps")),
        ("task killed and not joined",
         "a task killed at its deadline is recorded as ended and never reaped",
         d_kill_without_join, "nothing outlives", pick("a task past its deadline, alone")),
        ("task wake ignores the grace",
         "the pool's wake time leaves out the end of a cancellation's grace, so it sleeps a poll period past it",
         d_wake_ignores_grace, "on time", pick("while a slow task works")),
    ])

    # ---- the transcription's tie to Task.ax ---------------------------------------------
    ns["UNREACHABLE"][("taskWakeBy", ("ret", "-1"))] = (
        "no task running: taskLoop asks only when nothing moved, and then one is, as every other case "
        "starts, joins or delivers something")
    ns["SOURCES"].append(TASK)
    ns["WRAPPERS"].extend([
        (TASK, "taskLoadAt", "(__atomic_load a)"),
        (TASK, "taskStoreAt", "(__atomic_store a v)"),
        (TASK, "taskAddAt", "(__atomic_add a v)"),
        (TASK, "taskHandlePid", "(__spawn_pid h)"),
        (TASK, "taskSpawn", "(__proc_spawn wrapper arg)"),
        (TASK, "taskNapNext", "(if (> (* nap 2) taskPollNanos)\n    taskPollNanos\n    (* nap 2))"),
        (TASK, "taskPollPeriod", "(if (== answered 1)\n    nap\n    taskPollNanos)"),
        (TASK, "taskSleepFor", "(if (> wake now)"),
    ])
    ns["NOT_MODELLED"][TASK] = {
        "taskOpts": "builds the options", "taskWithDeadline": "builds the options",
        "taskWithGrace": "builds the options", "taskWithFailFast": "builds the options",
        "taskWithToken": "builds the options",
        "taskCancelledCode": "a constant", "taskTooLargeCode": "a constant",
        "taskPollNanos": "a constant: POLL in the model's units",
        "taskExitNapFirst": "a constant: NAP1 in the model's units",
        "taskNapNext": "the nap's doubling, capped at the poll period: the model's min(nap * 2, POLL); in WRAPPERS",
        "taskPollPeriod": "nap while a task has answered, else the poll period: in WRAPPERS",
        "taskLoadAt": "the atomic load, in WRAPPERS", "taskStoreAt": "the atomic store, in WRAPPERS",
        "taskAddAt": "the atomic add, in WRAPPERS",
        "taskHandlePid": "the pid a handle names: in the model a handle is its child's pid; in WRAPPERS",
        "taskSpawn": "the spawn inside its own recovery point, which the model's spawn is; in WRAPPERS",
        "taskSpawned": "whether taskSpawn answered a handle: the model's spawns are never refused",
        "taskWordOf": "a handle as the word a recovery point answers: in the model a handle is a pid",
        "taskHandleOf": "that word back as a handle: in the model a handle is a pid",
        "taskScratch": "a scratch block of the parent's own", "taskScratchDone": "returns a scratch block",
        "taskTokenAt": "the token's page, read from its owner",
        "taskTokenNew": "maps a token before any pool uses it", "taskTokenOwned": "taskTokenNew's owner step",
        "taskTokenDrop": "unmaps a token when its last owner in an address space lets go",
        "taskCancelled": "a cooperative task's poll of the token: the model's tasks do not poll",
        "taskSt": "a read of the parent's own per-slot words: the model's plain load",
        "taskSetSt": "a write of the parent's own per-slot words: the model's plain store",
        "taskCopyOut": "copies an answer after its join: the model's load of the answer word",
        "taskSleepFor": "wake - now, at least a microsecond: the model's absolute wake time; in WRAPPERS",
        "taskMicros": "the options in microseconds: the model's units are its own",
        "taskAllFailed": "no pool at all: every task answers the setup error",
        "taskWithSlab": "maps the slab around the pool", "taskRun": "maps and unmaps around the pool",
        "taskTokenFor": "the caller's token or a fresh one", 
        "taskWidth": "clamps the width to 1..n: the model's scenarios pass it clamped",
        "taskMap": "an entry: a sink that keeps every answer", "taskMapWith": "an entry, with every option",
        "taskMapDecoded": "an entry: taskMap's sink, decoding each answer in the parent",
        "taskMapDecodedWith": "an entry, with every option, decoding each answer in the parent",
        "taskDecodeResult": "the decoding sink's step on the delivered answer: a failure passes through",
        "taskFold": "an entry: a sink that folds the answers inside a region",
        "taskFoldOne": "the fold's sink: one step on the delivered answer",
    }
    ns["PROCESS_OPS"][TASK] = r"__proc_\w+|__spawn_pid|sysKill\b|sysChildExited|sysTimeoutMicros"
