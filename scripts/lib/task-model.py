"""The task pool of `stdlib/Task.ax` (MM-PAR-13), transcribed for
`scripts/lib/protocol-model.py`, which installs it (`install`).

The filename follows the script convention; importlib loads it by path.

WHAT IS TRANSCRIBED. The budgeted pool's parent loop, `taskLoop`, and every
step it takes on shared state or on a child: the token's cancel flag and event
counter, a slot's state word, the spawn, the look at a child
(`sysChildExited`), the kill, the join that reaps, the clock, and the
sleep on the event counter. And the child's half, `taskChild` and the
`taskAnswer` it runs on the task's own stack: its answer into its slot,
over the limit or not, and the bump that wakes the parent. The stack the
answer runs on is the process's own, so the switch to it is no step.
The parent's per-slot words (`st`) and its handles (`hs`) are its own, so
their accesses are plain steps inside the one before them. The scalar-word
pools, `taskMapWords` and `taskMapWordsChecked`, also transcribe their bounded
handle rings, submit-order joins, and the checked pool's refusal cleanup.

A TASK'S BODY is the program's `f`, which the model does not run: each
task is given a behaviour, fixed or chosen at its start - it
answers within the limit, answers over it, traps (exit 72), runs for ever
(`hang`), answers and then cannot exit (`stuck`), answers after a delay,
or exits without answering.

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

WHAT IT IS NOT. This proves properties of the model at its bounds (up to
five tasks and three outstanding children, a few units of time), not about
Task.ax: the bytes of an answer are one word, the sink and its region are a delivery
step. The budgeted pool's spawn refusal (which `taskLoop` turns into a
cancellation) and a parent killed from outside are outside it. Checked
word-pool scenarios include refused spawns (70 and 78), traps, and races
between child completion and refusal cleanup. The unchecked word pool's
raising recovery sweep and external-command internals remain runtime
obligations, exercised by check-task.sh. The clock is the model's.
"""

TASK = "Task.ax"
TASK_WORDS = "Internal/TaskWords.ax"
COMMAND = "Internal/Command.ax"
COMMAND_POOL = "Internal/CommandPool.ax"

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
        ("set", "s", "t % w", "(let s (% t w))"),
        ("set", "slot", "slab + %d * s" % SB, "(let slot (+ slab (* (% t w) slotBytes)))"),
        ("astore", "slot", "1", "(taskStoreAt slot 1)"),
        ("pstore", "slot + 1", "0", "(rawSetWord slot 1 0)"),
        ("pstore", "slot + 2", "0", "(rawSetWord slot 2 0)"),
        ("ghost", "tStart", ["t", "w"]),
        ("spawn", "h", "t", "t + 1", "(taskSpawn wrapper t mark)"),
        ("if", "t < w", "reuse", "(if (< t w)"),
        ("ghost", "tHandle", ["t", "w"]),
        ("pstore", "hs + t", "h", "(vecPush hs h)"),
        ("goto", "stamp"),
        ("L", "reuse"),
        ("ghost", "tHandle", ["s", "w"]),
        ("pstore", "hs + s", "h", "(vecSet hs s h)"),
        ("L", "stamp"),
        ("if", "D > 0", "nodl"),
        ("clock", "c", "sysTimeoutMicros"),
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
         "(let finished (|| (== status 0) (&& (== status 137) (>= why 2))))"),
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
        ("set", "slot", "slab + %d * s" % SB, "(let slot (+ slab (* s slotBytes)))"),
        ("pload", "status", "st + 3 * s + 1", "(let status (taskSt st s 1))"),
        ("pload", "why", "st + 3 * s + 2", "(let why (taskSt st s 2))"),
        ("call", None, "taskResultAt", ["slot", "status", "why", "t"], "(taskResultAt slot status why)"),
        ("ret", "0"),
    ])
    F("taskDeliverCancelled", ["t"], [], (TASK, "taskDeliverCancelled"), [
        ("ghost", "tDeliver", ["t", str(R_NOTSTARTED), "0", "0", "-1"]),
        ("ret", "0", '(mkError taskCancelledCode "task not started: the pool was cancelled")'),
    ])
    F("taskWakeBy", ["st", "head", "nxt", "w", "now", "canPoll", "cancelling", "graceEnd", "slab", "nap"],
      ["wake", "running", "answered", "t", "s", "k", "a", "d", "p"], (TASK, "taskWakeBy"), [
        ("set", "wake", "graceEnd if cancelling == 1 else -1", "(let mut wake\n      (if (== cancelling 1)"),
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
        ("pload", "d", "st + 3 * s", "(let d (taskSt st s 0))"),
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
        ("clock", "now", "sysTimeoutMicros"),
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
        ("call", None, "taskDeliver", ["st", "head % w", "slab", "head"], "(taskDeliverKept"),
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
    F("taskChild", ["tok", "slab", "w", "lim", "beh", "x", "idle", "arg"], ["slot", "p", "r"],
      (TASK, "taskChild"), [
        ("set", "slot", "slab + %d * (arg %% w)" % SB, "(let slot (+ slab (* (% arg w) slotBytes)))"),
        ("pid", "p"),
        ("pstore", "slot + 2", "p", "(rawSetWord slot 2 sysPid)"),
        ("call", "r", "taskAnswer", ["tok", "slot", "w", "lim", "beh", "x", "idle", "arg"],
         "(lambda (i) (taskAnswer f slot limit tok i))"),
        ("ret", "r"),
    ])
    # The task itself, on the stack `taskChild` mapped for it.
    F("taskAnswer", ["tok", "slot", "w", "lim", "beh", "x", "idle", "arg"], ["b", "c0", "c", "code", "len"],
      (TASK, "taskAnswer"), [
        ("choose", "b", "beh"),
        ("if", "b == %d" % SLOW, "work"),
        ("clock", "c0"),
        ("L", "nap"),
        ("clock", "c"),
        ("if", "c < c0 + x", "work"),
        ("sleepuntil", "code", "idle", "0", "c0 + x"),
        ("goto", "nap"),
        ("L", "work"),
        ("if", "b == %d" % TRAP, "runs", "(let r (f i))"),
        ("ghost", "tTrap", ["arg", "72"]),
        ("ret", "72"),
        ("L", "runs"),
        ("if", "b == %d" % QUIT, "stays"),
        ("ghost", "tTrap", ["arg", str(QUIT_MARK)]),
        ("ret", "0"),
        ("L", "stays"),
        ("if", "b == %d" % HANG, "answers"),
        ("block",),
        ("L", "answers"),
        ("set", "len", "lim + 1 if b == %d else lim" % BIG),
        ("pstore", "slot + 1", "len", "(rawSetWord slot 1 len)"),
        ("if", "len > lim", "fits", "(if (> len limit)"),
        ("astore", "slot", "3", "(taskStoreAt slot 3)"),
        ("ghost", "tAnswer", ["arg", "2"]),
        ("goto", "bump"),
        ("L", "fits"),
        ("pstore", "slot + 3", "arg", "(rawCopy (+ slot 32) (strData r) len)"),
        ("astore", "slot", "2", "(taskStoreAt slot 2)"),
        ("ghost", "tAnswer", ["arg", "1"]),
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

    # ---- the scalar-word pool -------------------------------------------------
    # Handles are the model's child pids. Each child's private answer page
    # is one word at `answers + i`; join returns its exit status separately.
    # The runtime transports the answer from that page when it reaps the
    # child. Keeping both witnesses lets the checks distinguish a result
    # from the next child, a trap, and a successful child killed too late.
    F("taskMapWords", ["n", "width", "hs", "answers"],
      ["w", "joined", "i", "h", "status", "ans"], (TASK_WORDS, "wordPoolMap"), [
        ("set", "w", "max(1, width)", "(if (< width 1)"),
        ("set", "joined", "0", "(let mut joined 0)"),
        ("set", "i", "0", "(for i in 0..n"),
        ("L", "fill"),
        ("if", "i < n", "drain"),
        ("L", "room"),
        ("if", "i - joined >= w", "start", "(while (>= (- i joined) w)"),
        ("pload", "h", "hs + joined % w"),
        ("join", "status", "h", "(__proc_join (vecGet hs (% joined w)))"),
        ("assert", "status == 0", "unchecked word scenarios supply successful workers"),
        ("pload", "ans", "answers + joined"),
        ("ghost", "wDeliver", ["joined", "h", "status", "ans"]),
        ("set", "joined", "joined + 1", "(set joined (+ joined 1))"),
        ("goto", "room"),
        ("L", "start"),
        ("ghost", "wStart", ["i", "w"]),
        ("spawn", "h", "i", "i + 1", "(__proc_spawn f i)"),
        ("if", "i < w", "reuse", "(if (< i w)"),
        ("ghost", "tHandle", ["i", "w"]),
        ("pstore", "hs + i", "h", "(vecPush hs h)"),
        ("goto", "advance"),
        ("L", "reuse"),
        ("ghost", "tHandle", ["i % w", "w"]),
        ("pstore", "hs + i % w", "h", "(vecSet hs (% i w) h)"),
        ("L", "advance"),
        ("set", "i", "i + 1"),
        ("goto", "fill"),
        ("L", "drain"),
        ("if", "joined < n", "done", "(while (< joined n)"),
        ("pload", "h", "hs + joined % w"),
        ("join", "status", "h", "(__proc_join (vecGet hs (% joined w)))"),
        ("assert", "status == 0", "unchecked word scenarios supply successful workers"),
        ("pload", "ans", "answers + joined"),
        ("ghost", "wDeliver", ["joined", "h", "status", "ans"]),
        ("set", "joined", "joined + 1", "(set joined (+ joined 1))"),
        ("goto", "drain"),
        ("L", "done"),
        ("ghost", "wDone", []),
        ("ret", "0", "out"),
    ])

    for name, message in (
        ("taskWordsJoinChecked", "parallel slot trapped"),
        ("taskWordsJoinKilled", "parallel slot killed: a later spawn was refused"),
    ):
        F(name, ["h"], ["st"], (TASK, name), [
            ("join", "st", "h", "(__proc_join_nr h cell)"),
            ("set", "st", "st", "(let st (rawGetWord cell 0))"),
            ("if", "st == 0", "failed", "(if (== st 0)"),
            ("ret", "0", "(Ok w)"),
            ("L", "failed"),
            ("ret", "st", '(Err (mkError st "%s"))' % message),
        ])

    F("taskWordsSpawn", ["i", "w", "refuseAt", "refuseCode"], ["h"], (TASK, "taskWordsSpawn"), [
        # The recovery extent converts a refused fork/handle allocation
        # into its status. Scenarios fix the refusal point and reason;
        # success remains the same visible spawn as the budgeted pool.
        ("if", "i == refuseAt", "start"),
        ("ghost", "wRefused", ["i", "refuseCode"]),
        ("ret", "refuseCode"),
        ("L", "start"),
        ("ghost", "wStart", ["i", "w"]),
        ("spawn", "h", "i", "i + 1", "(__proc_spawn f i)"),
        ("ret", "h"),
    ])
    F("taskWordsKill", ["h"], ["r"], (TASK, "taskWordsKill"), [
        ("kill9", "r", "h", "(sysKill (__spawn_pid h) 9)"),
        ("ret", "0"),
    ])
    F("taskMapWordsChecked", ["n", "width", "hs", "answers", "refuseAt", "refuseCode"],
      ["w", "joined", "nxt", "refused", "h", "hw", "status", "ans", "k"],
      (TASK, "taskMapWordsChecked"), [
        ("set", "w", "max(1, width)", "(if (< width 1)"),
        ("set", "joined", "0", "(let mut joined 0)"),
        ("set", "nxt", "0", "(let mut next 0)"),
        ("set", "refused", "0", "(let mut refused 0)"),
        ("L", "fill"),
        ("if", "nxt < n and refused == 0", "drain", "(while (&& (< next n) (== refused 0))"),
        ("L", "room"),
        ("if", "nxt - joined >= w", "start", "(while (>= (- next joined) w)"),
        ("pload", "h", "hs + joined % w"),
        ("call", "status", "taskWordsJoinChecked", ["h"],
         "(taskWordsJoinChecked (vecGet hs (% joined w)) cell)"),
        ("pload", "ans", "answers + joined"),
        ("ghost", "wDeliver", ["joined", "h", "status", "ans"]),
        ("set", "joined", "joined + 1", "(set joined (+ joined 1))"),
        ("goto", "room"),
        ("L", "start"),
        ("call", "hw", "taskWordsSpawn", ["nxt", "w", "refuseAt", "refuseCode"], "(taskWordsSpawn f next)"),
        ("if", "hw not in (70, 78)", "refuse", "(if (taskSpawned hw)"),
        ("set", "h", "hw", "(taskHandleOf hw)"),
        ("if", "nxt < w", "reuse", "(if (< next w)"),
        ("ghost", "tHandle", ["nxt", "w"]),
        ("pstore", "hs + nxt", "h", "(vecPush hs h)"),
        ("goto", "advance"),
        ("L", "reuse"),
        ("ghost", "tHandle", ["nxt % w", "w"]),
        ("pstore", "hs + nxt % w", "h", "(vecSet hs (% next w) h)"),
        ("L", "advance"),
        ("set", "nxt", "nxt + 1", "(set next (+ next 1))"),
        ("goto", "fill"),
        ("L", "refuse"),
        ("set", "refused", "hw", "(set refused hw)"),
        ("goto", "fill"),
        ("L", "drain"),
        ("if", "refused == 0", "kill", "(if (== refused 0)"),
        ("L", "normal"),
        ("if", "joined < n", "done", "(while (< joined n)"),
        ("pload", "h", "hs + joined % w"),
        ("call", "status", "taskWordsJoinChecked", ["h"],
         "(taskWordsJoinChecked (vecGet hs (% joined w)) cell)"),
        ("pload", "ans", "answers + joined"),
        ("ghost", "wDeliver", ["joined", "h", "status", "ans"]),
        ("set", "joined", "joined + 1", "(set joined (+ joined 1))"),
        ("goto", "normal"),
        ("L", "kill"),
        ("set", "k", "joined", "(for k in joined..next"),
        ("L", "killNext"),
        ("if", "k < nxt", "reap"),
        ("pload", "h", "hs + k % w"),
        ("call", None, "taskWordsKill", ["h"], "(taskWordsKill (vecGet hs (% k w)))"),
        ("set", "k", "k + 1"),
        ("goto", "killNext"),
        ("L", "reap"),
        ("if", "joined < nxt", "notStarted", "(while (< joined next)"),
        ("pload", "h", "hs + joined % w"),
        ("call", "status", "taskWordsJoinKilled", ["h"],
         "(taskWordsJoinKilled (vecGet hs (% joined w)) cell)"),
        ("pload", "ans", "answers + joined"),
        ("ghost", "wDeliver", ["joined", "h", "status", "ans"]),
        ("set", "joined", "joined + 1", "(set joined (+ joined 1))"),
        ("goto", "reap"),
        ("L", "notStarted"),
        ("set", "k", "nxt", "(for k in next..n"),
        ("L", "refusedNext"),
        ("if", "k < n", "done"),
        ("ghost", "wNotStarted", ["k", "refused"]),
        ("set", "k", "k + 1", '(Err (mkError refused "parallel slot not started: its spawn was refused"))'),
        ("goto", "refusedNext"),
        ("L", "done"),
        ("ghost", "wDone", []),
        ("ret", "0", "out"),
    ])
    F("taskWordChild", ["answers", "beh", "arg"], ["b", "work"], None, [
        ("choose", "b", "beh"),
        # One schedulable body step, represented by a private-page read.
        # Without it a body made entirely of local instructions would
        # finish during spawn normalisation, before a join could wait.
        ("uload", "work", "answers + arg"),
        ("if", "b == %d" % HANG, "work"),
        ("block",),
        ("L", "work"),
        ("if", "b == %d" % TRAP, "answer"),
        ("ghost", "tTrap", ["arg", "72"]),
        ("ret", "72"),
        ("L", "answer"),
        ("pstore", "answers + arg", "17 * arg + 5"),
        ("ghost", "tAnswer", ["arg", "1"]),
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

    def g_wStart(self, c, b, t, w):
        if c.ghost["wrefused"]:
            raise Violation("spawn refusal", "task %d started after a spawn was refused" % t)
        self.g_tStart(c, b, t, w)

    def g_wRefused(self, c, b, t, code):
        if c.ghost["wrefused"]:
            raise Violation("spawn refusal", "word task %d's spawn was retried after refusal" % t)
        if code not in (70, 78) or c.procs[self.sc.tasks[t]] != "-":
            raise Violation("spawn refusal", "task %d's refusal does not describe an unstarted child" % t)
        c.ghost["wrefused"] = code

    def g_wDeliver(self, c, b, t, h, status, ans):
        if t != c.ghost["deliv"]:
            raise Violation("one slot each", "word task %d was delivered out of submit order" % t)
        k = self.sc.tasks[t]
        if h != self.sc.pids[k]:
            raise Violation("one slot each", "word task %d was delivered from another task's handle" % t)
        if c.procs[k] != "X":
            raise Violation("nothing outlives", "word task %d was delivered before its child was reaped" % t)
        started, answered, trapped, killed = c.ghost["fate"][t]
        expected = c.mem[self.sc.exitword[k]]
        good = started and status == expected
        if status == 0:
            good = good and answered == 1 and ans == 17 * t + 5
        elif status == 137:
            good = good and killed and c.ghost["wrefused"]
        else:
            good = good and status == trapped
        if not good:
            raise Violation("one slot each", "word task %d's result (%d, %d) disagrees with its child"
                            % (t, status, ans))
        c.ghost["deliv"] += 1

    def g_wNotStarted(self, c, b, t, status):
        if t != c.ghost["deliv"] or status != c.ghost["wrefused"] or not status:
            raise Violation("spawn refusal", "word task %d has the wrong refusal result or position" % t)
        if c.procs[self.sc.tasks[t]] != "-" or c.ghost["fate"][t][0]:
            raise Violation("spawn refusal", "word task %d ran despite its not-started result" % t)
        c.ghost["deliv"] += 1

    def g_wDone(self, c, b):
        self.g_tPoolDone(c, b, c.ghost["deliv"])
        for t, k in enumerate(self.sc.tasks):
            if c.procs[k] not in ("X", "-"):
                raise Violation("nothing outlives", "the word pool returned with task %d unreaped" % t)

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
        if name.startswith(("g_t", "g_w")):
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
            g.update(cseen=0, deliv=0, wrefused=0, fate=tuple((0, 0, 0, 0) for _ in self.tasks))
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

    def word_pool(name, behaviours, width, checked=True, refuseAt=-1, refuseCode=78):
        n, w = len(behaviours), max(1, width)
        lay, mem = task_mem(n, min(n, w))
        answers = len(mem)
        mem.extend([0] * n)
        driver = "taskMapWordsChecked" if checked else "taskMapWords"
        args = (n, width, lay["hs"], answers)
        if checked:
            args += (refuseAt, refuseCode)
        bindings = [(driver, args)] + [
            ("taskWordChild", (answers, tuple(beh), -1)) for beh in behaviours]
        sc = Scenario("word pool: " + name, "task", mem, bindings, progress=("n", "t", "c"))
        sc.procs, sc.lay, sc.width, sc.ntasks = True, lay, w, n
        sc.tasks = list(range(1, n + 1))
        sc.parents = {k: 0 for k in sc.tasks}
        sc.exitword = {k: lay["exit"] + k - 1 for k in sc.tasks}
        sc.unspawned, sc.drains = frozenset(sc.tasks), False
        # Word pools have no deadlines or timed sleeps: the only wait is
        # a join, and a blocked worker can end only through refusal cleanup.
        return sc

    def word_scenarios(long=False):
        out = [
            word_pool("unchecked, 3 tasks reuse 2 handles", [(OK,)] * 3, 2, checked=False),
            word_pool("unchecked, negative width clamps to 1", [(OK,)] * 2, -2, checked=False),
            word_pool("unchecked, width exceeds input", [(OK,)] * 2, 5, checked=False),
            word_pool("checked, 3 tasks reuse 2 handles, answers or traps", [A2] * 3, 2),
            word_pool("checked, zero width clamps to 1", [A2] * 2, 0),
            word_pool("checked, width exceeds input", [A2] * 2, 5),
            word_pool("fork refused with two outstanding, answer/trap/kill races",
                      [(OK, TRAP, HANG)] * 4, 3, refuseAt=2),
            word_pool("page refused after ring reuse", [A2, A2, (OK,), (OK,)],
                      1, refuseAt=2, refuseCode=70),
            word_pool("fork refused after ring reuse, two outstanding",
                      [A2, A2, (OK, HANG), (OK, HANG), (OK,)], 3, refuseAt=4),
        ]
        if long:
            out.append(word_pool("checked, 4 tasks reuse 3 handles, answers or traps", [A2] * 4, 3))
        return out

    ns["EXTRA_SCENARIOS"].append(word_scenarios)

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
                                     "(let mut wake\n      (if (== cancelling 1)")], [("set", "wake", "-1")])

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
                                    "(let slot (+ slab (* (% arg w) slotBytes)))")],
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

    def d_word_unbounded(fns):
        replace(fns, "taskMapWords", [("if", "i - joined >= w", "start", "(while (>= (- i joined) w)")],
                [("goto", "start")])

    def d_word_slot_mixup(fns):
        replace(fns, "taskMapWordsChecked", [("pload", "h", "hs + joined % w")],
                [("pload", "h", "hs + (joined + 1) % w")], count=3)

    def d_word_refusal_no_kill(fns):
        replace(fns, "taskWordsKill", [("kill9", "r", "h", "(sysKill (__spawn_pid h) 9)")],
                [("set", "r", "0")])

    def d_word_refusal_no_join(fns):
        replace(fns, "taskWordsJoinKilled", [("join", "st", "h", "(__proc_join_nr h cell)")],
                [("set", "st", "137")])

    def d_word_drop_refusal_results(fns):
        replace(fns, "taskMapWordsChecked", [("if", "k < n", "done")], [("goto", "done")])

    def d_word_retry_refusal(fns):
        replace(fns, "taskMapWordsChecked", [
            ("if", "nxt < n and refused == 0", "drain", "(while (&& (< next n) (== refused 0))")],
            [("if", "nxt < n", "drain")])

    def word_pick(*names):
        return lambda: [s for s in word_scenarios() if any(n in s.name for n in names)]

    ns["DEFECTS"].extend([
        ("word pool spawned before joining", "the word ring admits a third child at width two",
         d_word_unbounded, "bounded", word_pick("unchecked, 3 tasks")),
        ("word pool joins its neighbour's slot", "the checked ring delivers the next handle's result",
         d_word_slot_mixup, "one slot each", word_pick("checked, 3 tasks")),
        ("word refusal leaves a running child", "spawn refusal omits SIGKILL before the non-raising joins",
         d_word_refusal_no_kill, "deadlock", word_pick("fork refused with two")),
        ("word refusal kills without reaping", "a killed word task is delivered without joining its handle",
         d_word_refusal_no_join, "nothing outlives", word_pick("fork refused with two")),
        ("word refusal drops unstarted results", "the refusal path omits the unstarted suffix",
         d_word_drop_refusal_results, "one slot each", word_pick("fork refused with two")),
        ("word pool retries a refused spawn", "submission continues after the first refused spawn",
         d_word_retry_refusal, "spawn refusal", word_pick("fork refused with two")),
    ])

    # ---- the transcription's tie to Task.ax ---------------------------------------------
    ns["UNREACHABLE"][("taskWakeBy", ("ret", "-1"))] = (
        "no task running: taskLoop asks only when nothing moved, and then one is, as every other case "
        "starts, joins or delivers something")
    ns["SOURCES"].extend([TASK, TASK_WORDS, COMMAND, COMMAND_POOL])
    ns["WRAPPERS"].extend([
        (TASK, "taskLoadAt", "(__atomic_load a)"),
        (TASK, "taskStoreAt", "(__atomic_store a v)"),
        (TASK, "taskAddAt", "(__atomic_add a v)"),
        (TASK, "taskHandlePid", "(__spawn_pid h)"),
        (TASK, "taskSpawn", "(lambda (x) (taskWordOf (__proc_spawn wrapper arg)))"),
        (TASK, "taskNapNext", "(if (> (* nap 2) taskPollNanos)\n    taskPollNanos\n    (* nap 2))"),
        (TASK, "taskPollPeriod", "(if (== answered 1)\n    nap\n    taskPollNanos)"),
        (TASK, "taskSleepFor", "(if (> wake now)"),
        (TASK, "taskMapRanges", "(taskMapWith"),
        (TASK, "taskMapRanges", "(+ 1 (/ (- count 1) size)) opts)"),
        (TASK, "taskMapWords", "(wordPoolMap f n width)"),
        (TASK, "taskArgvVector", "(commandArgvVector argv)"),
        (TASK, "taskRunCommand", "(commandRun argv)"),
        (TASK, "taskRunCommands", "(commandPoolRun cmds width)"),
        (COMMAND, "commandRun", "(sysRunPath (strDup (rawVecGetStr argv 0)) (commandArgvVector argv) sysEnvp)"),
        (COMMAND, "commandRunWord", "(match (commandRun argv)"),
        (COMMAND_POOL, "commandPoolRun", "(wordPoolMap (lambda (i) (commandRunWord (vecGet cmds i))) (vecLen cmds) width)"),
        (TASK, "taskMapCompute", "(taskMapDecodedWith (lambda (index) (taskComputeEncode (worker index))) taskComputeDecode count"),
    ])
    ns["NOT_MODELLED"][TASK] = {
        "taskOpts": "builds the options", "taskWithDeadline": "builds the options",
        "taskWithGrace": "builds the options", "taskWithFailFast": "builds the options",
        "taskWithToken": "builds the options",
        "taskWithKeep": "builds the options", "taskWithMemory": "builds the options",
        "taskWithStack": "builds the options", "taskStackDefault": "a constant",
        "taskOverBudgetCode": "a constant",
        "taskCapArena": "runs in the child before the task: caps its arena, which the model's tasks never fill",
        "taskOkBytes": "an answer's bytes against the keep budget: the model's pools have no keep budget",
        "taskDeliverKept": "the keep budget's gate around taskDeliver, which with no keep budget it calls at once: "
                           "the model's pools have none, so taskLoop's delivery is modelled as taskDeliver",
        "taskCancelledCode": "a constant", "taskTooLargeCode": "a constant",
        "taskPollNanos": "a constant: POLL in the model's units",
        "taskExitNapFirst": "a constant: NAP1 in the model's units",
        "taskNapNext": "the nap's doubling, capped at the poll period: the model's min(nap * 2, POLL); in WRAPPERS",
        "taskPollPeriod": "nap while a task has answered, else the poll period: in WRAPPERS",
        "taskLoadAt": "the atomic load, in WRAPPERS", "taskStoreAt": "the atomic store, in WRAPPERS",
        "taskAddAt": "the atomic add, in WRAPPERS",
        "taskHandlePid": "the pid a handle names: in the model a handle is its child's pid; in WRAPPERS",
        "taskSpawn": "the spawn inside its own recovery point, which the model's spawn is, "
                     "whichever cell holds the mark; in WRAPPERS",
        "taskSpawned": "whether the recovery point answered a handle: a word-pool scenario fixes any refusal",
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
        "taskMapRanges": "partitions indices into worker bodies, then delegates to taskMapWith; in WRAPPERS",
        "taskMapWords": "delegates to the unchanged transcribed Internal.TaskWords loop; in WRAPPERS",
        "taskArgvVector": "delegates to the shared argument-vector encoder; in WRAPPERS",
        "taskRunCommand": "delegates to the shared one-command launch; in WRAPPERS",
        "taskRunCommands": "delegates to the target-selected command entry; its POSIX route is in WRAPPERS",
        "taskMapCompute": "encodes numeric worker bodies and delegates to the budgeted pool; in WRAPPERS",
        "taskComputeEncode": "serialises the worker's scalar answer as eight bytes",
        "taskComputeDecode": "checks the answer length and decodes eight bytes in the parent",
    }
    ns["NOT_MODELLED"][TASK_WORDS] = {}
    ns["NOT_MODELLED"][COMMAND] = {
        "commandArgvVector": "constructs a null-terminated argument vector in the caller's arena",
        "commandRun": "the command body's Sys launch is outside this model; in WRAPPERS",
        "commandRunWord": "encodes the command body's Result as a scalar word; in WRAPPERS",
    }
    ns["NOT_MODELLED"][COMMAND_POOL] = {
        "commandPoolRun": "the POSIX entry delegates to the transcribed word pool; in WRAPPERS; "
                          "the Windows sibling's native lifecycle has separate runtime tests",
    }
    ns["PROCESS_OPS"][TASK] = r"__proc_\w+|__spawn_pid|sysKill\b|sysChildExited|sysTimeoutMicros"
    ns["PROCESS_OPS"][TASK_WORDS] = r"__proc_\w+"
