#!/usr/bin/env python3
"""An executable model of the channel, mutex and task-pool protocols, explored exhaustively.

`stdlib/Chan.ax` (MM-PAR-10) and `stdlib/Sync.ax` (MM-PAR-11, MM-PAR-12)
build a bounded channel and a mutex out of the five atomics and a kernel
wait on a word. Their headers state the protocols in prose: the lock
word that names its holder, which both share, and its dead-holder test
and poisoning; the channel's change counter and the waiter announcement
in word 2; the mutex's guard. `stdlib/Task.ax` (MM-PAR-13) runs a pool of
forked tasks on a token and a slab; its transcription is in
`task-model.py`, which this file installs. The load gates
(`scripts/check-chan.sh`, `scripts/check-task.sh`,
`scripts/check-race.sh`) run them and see the interleavings the hardware
happened to make. This file is the other half: the same steps,
transcribed, and every interleaving of two and three bindings at small
bounds.

HOW THE PROTOCOLS ARE WRITTEN DOWN. Each function the protocols run is a
short program in a tiny instruction set (`FUNCTIONS` below), written in
the order of its source text, and every step that touches a shared word
cites the exact spelling it transcribes: `('acas', 'r', 'ch', '0', 'me',
'(__atomic_cas ch 0 me)')` is `chanLock`'s first compare-and-swap. The
`transcription` command reads the real files and requires every cited
spelling to occur in its function, in the model's order, and every
function in the two modules to be either modelled or listed in
`NOT_MODELLED` with its reason.

WHAT A STEP IS. One access to a shared word: an atomic load, store, add
or compare-and-swap, the plain entry load of `sysWaitWordTimeout`, a
kernel wait, a wake, or a `kill(pid, 0)`. Everything a binding does
between two such accesses (arithmetic, branches, calls, and the plain
`chanGet`/`chanPut` accesses of words only the lock holder touches) runs
inside the step before it. That merge is sound only while the lock
excludes, so mutual exclusion is checked in every state, and a planted
lock that does not exclude is found as exactly that. A binding a wake
resumes runs its local steps at once, for the same reason. Bindings that
run the same driver with the same arguments and pid are interchangeable,
so each state is stored once, with them sorted. And a frame's dead locals
- written before they are next read - are zeroed as a state is stored
(`liveness`), so two states that differ only in one are one state.

THE KERNEL WAIT is Linux's `futex` and Darwin's `__ulock_wait`: one step
compares the word with the expected value and either returns (the word
differs) or puts the binding to sleep. A sleeping binding is released by
a wake on that word, and by nothing else in the protocol's own steps. Two
more ways out are ENVIRONMENT transitions, explored in every state but
never counted as progress: a spurious wakeup, and the timeout of a timed
wait. A kill and the parent's reap of a killed or finished process are
environment transitions too, in the scenarios that model a dying binding;
a binding whose parent is another binding is reaped by nobody, and only
that parent's `waitid` look sees it exit. The task pool adds a clock that
moves while the pool waits and nothing else can step, and a sleep that
only the clock ends (`task-model.py`).

WHAT IS CHECKED, in every reachable state:
  mutual exclusion   at most one binding holds a lock;
  exactly once       a word is received only as the oldest word accepted
                     and not yet received, so none is lost, duplicated or
                     reordered - one total order over all senders;
  FIFO per sender    each sender's words are accepted in the order sent;
  close              no send is accepted once the channel is closed, and
                     a send that answered False or timed out never
                     appears; a receive answers the end of the stream only
                     when the ring is empty and closed, and a timed-out
                     receive only when it was empty and open;
  the lock word      a stale guard is refused, only the holder releases,
                     a mutex or channel is poisoned only when its word names
                     a holder that died holding it, a poisoned one is never
                     taken, and a call answers "poisoned" only when it is;
  the task pool      what `task-model.py` states: every task answers its own
                     slot once, the pool stays within its width, sleeps past
                     no deadline or grace, and reaps every child.
And, over the whole graph, liveness in the model's terms: from every
reachable state, every binding can still finish using protocol steps
alone (plus timeouts and reaps where a scenario says the protocol relies
on them). A state from which that is impossible is reported as a LOST
WAKEUP when some sleeping binding's condition already holds (the lock is
free, the ring has a word or room, the channel is closed), as a DEADLOCK
when none does, and as a LIVELOCK when steps remain but none leads out.
`run` also reports which transcribed steps no scenario executed: every
one but those `UNREACHABLE` names is a gap in the scenarios.

WHAT IT IS NOT. A proof about the model, at its bounds, not about the
implementation: two bindings with one to four words each and three
bindings with one and two (six and three under --long, and four
bindings), capacities 1 and 2, one and two slices of time; two and three
tasks at widths 1 to 3. The link between the two is the `transcription`
check (the cited operations are still there, in this order) and
`replay`, which drives the model with the operation sequence an
instrumented build recorded and requires every recorded answer to be the
model's. Replay covers the channel's untimed calls under the process
lowering, where a pid names each binding; the mutex, the timed forms and
the pool have none. Outside the model: the memory model (every access is
a step in one sequentially consistent order, which MM-PAR-9 promises for
the atomics and the lock gives the plain words; the lowering is
`scripts/check-atomics.sh`'s subject); Linux's 32-bit futex compare
(MM-PAR-10's caveat); FreeBSD's spin; the clock beyond "a slice ends or
it does not", except the pool's; pid reuse, and a zombie holder seen by
any process but its parent (the stated limits of MM-PAR-10 and
MM-PAR-11); the handle's lifetime and a forged guard; and every scenario
larger than the bounds.

Usage:
  protocol-model.py run [--long]           explore every scenario; exit 1 on any finding or gap
  protocol-model.py defects                explore each planted defect; exit 1 unless each is found
  protocol-model.py transcription [DIR]    check the transcription against the stdlib in DIR
  protocol-model.py instrument DIR [--plant NAME]
                                           rewrite DIR/Chan.ax (a copy) to record its operations
  protocol-model.py replay TRACE           replay what tests/litmus/chan-trace.ax recorded
  protocol-model.py show SCENARIO          explore the scenarios whose names contain SCENARIO
"""

import array
import collections
import os
import re
import sys

# ---------------------------------------------------------------------
# The instruction set.
#
#   ('L', label)                         a label
#   ('set', var, expr)                   a local
#   ('if', cond, else_label)             then-branch follows; else jumps
#   ('goto', label)
#   ('call', dst|None, callee, [args])   a call; dst gets the answer
#   ('ret', expr)
#   ('aload', dst, addr)                 seq_cst atomic load
#   ('astore', addr, val)                seq_cst atomic store
#   ('aadd', dst|None, addr, delta)      seq_cst fetch-and-add: the old word
#   ('acas', dst|None, addr, old, new)   seq_cst compare-and-swap: the word found
#   ('uload', dst, addr)                 a plain load of a word others write
#   ('pload', dst, addr)                 a plain load of a lock-protected word
#   ('pstore', addr, val)                a plain store to a lock-protected word
#   ('wait', dst|None, addr, exp, timed) the kernel's compare-and-sleep: 2 when
#                                        the word differs, 0 woken, 1 timed out
#   ('wake', addr)                       wake every binding asleep on addr
#   ('pid', dst)                         this binding's pid
#   ('kill0', dst, pid)                  kill(pid, 0): 0 alive, 3 ESRCH
#   ('look', dst, pid)                   waitid WNOWAIT: 1 when pid is the looker's own
#                                        child and has exited unreaped, else 0 (-1
#                                        where the scenario has no look)
#   ('clock', dst)                       the clock `sysTimeoutMicros` reads
#   ('spawn', dst, arg, child)           start binding `child` with `arg`; dst its pid
#   ('join', dst, pid)                   wait for the child to exit, reap it; dst its status
#   ('kill9', dst, pid)                  SIGKILL: an alive child exits 137; 3 when reaped
#   ('sleepuntil', dst, addr, exp, at)   the kernel's wait, timed out only once the
#                                        clock reaches `at`
#   ('block',)                           wait for ever: only a kill ends it
#   ('choose', dst, choices)             a nondeterministic local choice
#   ('ghost', hook, [args])              bookkeeping the checks read
#   ('assert', cond, message)
#
# Any instruction but 'L', 'ghost' and 'assert' may end with the source
# spelling it transcribes. Addresses are word indices; the spelling is the
# source's byte address.
# ---------------------------------------------------------------------

CHAN = "Chan.ax"
SYNC = "Sync.ax"
SYS = "Sys.ax"
# The files the transcription is checked against. `task-model.py` adds
# Task.ax, with the process operations its functions must hold.
SOURCES = [CHAN, SYNC, SYS]
PROCESS_OPS = {}
# Functions answering more scenarios, each taking `long`.
EXTRA_SCENARIOS = []

VISIBLE = frozenset(("aload", "astore", "aadd", "acas", "uload", "wait", "wake", "kill0", "look",
                     "clock", "spawn", "join", "kill9", "sleepuntil", "block"))
ARITY = {  # operands before the optional spelling
    "set": 2, "if": 2, "goto": 1, "call": 3, "ret": 1, "aload": 2, "astore": 2,
    "aadd": 3, "acas": 4, "uload": 2, "pload": 2, "pstore": 2, "wait": 4, "wake": 1,
    "pid": 1, "kill0": 2, "look": 2, "choose": 2, "ghost": 2, "assert": 2,
    "clock": 1, "spawn": 3, "join": 2, "kill9": 2, "sleepuntil": 4, "block": 0,
}

# name -> (params, locals, (file, source function) or None, body)
FUNCTIONS = {}


def F(name, params, locs, src, body):
    FUNCTIONS[name] = (tuple(params), tuple(locs), src, tuple(body))


# Return codes the drivers read.
NONE = -1          # chanRecv's None
TIMED_OUT = -3     # a timed channel call's sysTimedOut
RECV_POISONED = -4  # chanRecvTimeout's syncOwnerDead
SENT, CLOSED, SEND_TIMED_OUT, POISONED = 1, 2, 3, 4
POISON = 3         # chanPoisonMark: the lock word of a poisoned channel
LOCK_TIMED_OUT, OWNER_DEAD = -1, -2
UNLOCK_OK, NOT_HELD = 0, 1005

# ---- Sys.ax: the kernel's word wait ------------------------------------

F("sysWakeWord", ["addr"], [], (SYS, "sysWakeWord"), [
    ("wake", "addr", "(sysWakeWordRaw addr)"),
    ("ret", "0"),
])
F("sysWaitWordTimeout", ["addr", "expected", "nanos"], ["cur", "code"], (SYS, "sysWaitWordTimeout"), [
    ("uload", "cur", "addr", "(memGetWord addr 0)"),
    ("if", "cur != expected", "same"),
    ("ret", "2"),
    ("L", "same"),
    ("if", "nanos <= 0", "sleep", "(<= nanos 0)"),
    ("ret", "1"),
    ("L", "sleep"),
    ("wait", "code", "addr", "expected", True, "(sysWaitWordTimed addr expected nanos)"),
    ("ret", "code"),
])

# ---- Chan.ax -------------------------------------------------------------
# Words: 0 the lock (0, the holder's pid * 4 plus 1 when someone waits,
# or POISON once a holder died holding it), 1 change counter, 2 waiters,
# 3 head, 4 tail, 5 capacity, 6 closed, 7 mapping length, 8.. the ring.
# The channel is at word 0. A timed call's scratch block is a word of its
# own past the ring (`b`), private to the binding, so its accesses are
# the plain `pload`/`pstore` that run inside the step before them.

F("chanMe", [], ["p"], (CHAN, "chanMe"), [
    ("pid", "p", "sysPid"),
    ("ret", "p * 4"),
])
F("chanLock", ["ch", "me", "b", "timed"], ["r", "g"], (CHAN, "chanLock"), [
    ("acas", "r", "ch", "0", "me", "(__atomic_cas ch 0 me)"),
    ("if", "r == 0", "slow"),
    ("ghost", "acquire", []),
    ("ret", "0"),
    ("L", "slow"),
    ("call", "g", "chanAcquire", ["ch", "me", "b", "timed"], "(chanAcquire ch me b timed)"),
    ("ret", "g"),
])
F("chanAcquire", ["ch", "me", "b", "timed"], ["v", "r", "left", "w", "slice", "code", "d", "dead"],
  (CHAN, "chanAcquire"), [
    ("L", "top"),
    ("aload", "v", "ch", "(__atomic_load ch)"),
    ("if", "v == 0", "held"),
    ("acas", "r", "ch", "0", "me + 1", "(__atomic_cas ch 0 (+ me 1))"),
    ("if", "r == 0", "top"),
    ("ghost", "acquire", []),
    ("ret", "0"),
    ("L", "held"),
    ("if", "v == %d" % POISON, "live", "(== v chanPoisonMark)"),
    ("ret", "2"),
    ("L", "live"),
    ("if", "timed == 1", "anytime"),
    ("pload", "left", "b", "(chanOutOfTime b timed)"),
    ("if", "left <= 0", "anytime"),
    ("ghost", "lockTimedOut", []),
    ("ret", "1"),
    ("L", "anytime"),
    ("call", "w", "chanMarkWaiting", ["ch", "v"], "(chanMarkWaiting ch v)"),
    ("if", "w == 0", "marked"),
    ("goto", "top"),
    ("L", "marked"),
    ("set", "slice", "min(left, 1) if timed == 1 else 1", "(chanLockSlice b timed)"),
    ("call", "code", "sysWaitWordTimeout", ["ch", "w", "slice"], "(sysWaitWordTimeout ch w slice)"),
    ("if", "timed == 1", "charged"),
    ("choose", "d", "(0, slice)", "(chanTimeSpent b code slice)"),
    ("pstore", "b", "left - (slice if code == 1 else d)"),
    ("L", "charged"),
    ("if", "code == 1", "top"),
    ("call", "dead", "chanHolderDead", ["w", "me"], "(chanHolderDead w me)"),
    ("if", "dead == 1", "top"),
    ("call", None, "chanPoison", ["ch", "w"], "(chanPoison ch w)"),
    ("goto", "top"),
])
F("chanMarkWaiting", ["ch", "v"], ["r"], (CHAN, "chanMarkWaiting"), [
    ("if", "v % 2 == 1", "mark", "(== (% v 2) 1)"),
    ("ret", "v"),
    ("L", "mark"),
    ("acas", "r", "ch", "v", "v + 1", "(__atomic_cas ch v (+ v 1))"),
    ("if", "r == v", "moved"),
    ("ret", "v + 1"),
    ("L", "moved"),
    ("ret", "0"),
])
F("chanHolderDead", ["w", "me"], ["owner", "k", "e"], (CHAN, "chanHolderDead"), [
    ("set", "owner", "w // 4", "(/ w 4)"),
    ("if", "owner == 0 or owner * 4 == me", "look"),
    ("ret", "0"),
    ("L", "look"),
    ("kill0", "k", "owner", "(sysKill owner 0)"),
    ("if", "k == 0", "gone"),
    ("call", "e", "chanChildEnded", ["owner"], "(chanChildEnded owner)"),
    ("ret", "e"),
    ("L", "gone"),
    ("ret", "1 if k == 3 else 0", "(== (errCode e) 3)"),
])
F("chanChildEnded", ["pid"], ["x"], (CHAN, "chanChildEnded"), [
    ("look", "x", "pid", "(sysChildExited pid buf)"),
    ("ret", "x"),
])
F("chanPoison", ["ch", "w"], ["r"], (CHAN, "chanPoison"), [
    ("acas", "r", "ch", "w", str(POISON), "(__atomic_cas ch w chanPoisonMark)"),
    ("if", "r == w", "lost"),
    ("ghost", "chanPoison", ["w"]),
    ("aadd", None, "ch + 1", "1", "(__atomic_add (+ ch 8) 1)"),
    ("call", None, "sysWakeWord", ["ch"], "(sysWakeWord ch)"),
    ("call", None, "sysWakeWord", ["ch + 1"], "(sysWakeWord (+ ch 8))"),
    ("L", "lost"),
    ("ret", "0"),
])
F("chanIsPoisoned", ["ch"], ["v"], (CHAN, "chanIsPoisoned"), [
    ("aload", "v", "ch", "(__atomic_load ch)"),
    ("ret", "1 if v == %d else 0" % POISON),
])
F("chanUnlock", ["ch", "me"], ["r"], (CHAN, "chanUnlock"), [
    ("acas", "r", "ch", "me", "0", "(__atomic_cas ch me 0)"),
    ("if", "r == me", "contended"),
    ("ghost", "release", []),
    ("ret", "0"),
    ("L", "contended"),
    ("astore", "ch", "0", "(__atomic_store ch 0)"),
    ("ghost", "release", []),
    ("call", None, "sysWakeWord", ["ch"], "(sysWakeWord ch)"),
    ("ret", "0"),
])
F("chanPark", ["ch"], ["seen"], (CHAN, "chanPark"), [
    ("aadd", None, "ch + 2", "1", "(__atomic_add (+ ch 16) 1)"),
    ("aload", "seen", "ch + 1", "(__atomic_load (+ ch 8))"),
    ("ret", "seen"),
])
F("chanSleep", ["ch", "seen"], ["code"], (CHAN, "chanSleep"), [
    ("call", "code", "sysWaitWordTimeout", ["ch + 1", "seen", "1"], "(sysWaitWordTimeout (+ ch 8) seen chanSliceNanos)"),
    ("aadd", None, "ch + 2", "-1", "(__atomic_add (+ ch 16) (- 0 1))"),
    ("ret", "0"),
])
F("chanSleepFor", ["ch", "seen", "nanos"], ["code"], (CHAN, "chanSleepFor"), [
    ("call", "code", "sysWaitWordTimeout", ["ch + 1", "seen", "nanos"], "(sysWaitWordTimeout (+ ch 8) seen nanos)"),
    ("aadd", None, "ch + 2", "-1", "(__atomic_add (+ ch 16) (- 0 1))"),
    ("ret", "code"),
])
F("chanBump", ["ch"], [], (CHAN, "chanBump"), [
    ("aadd", None, "ch + 1", "1", "(__atomic_add (+ ch 8) 1)"),
    ("ret", "0"),
])
F("chanNotify", ["ch"], ["w"], (CHAN, "chanNotify"), [
    ("aload", "w", "ch + 2", "(__atomic_load (+ ch 16))"),
    ("if", "w > 0", "none"),
    ("call", None, "sysWakeWord", ["ch + 1"], "(sysWakeWord (+ ch 8))"),
    ("L", "none"),
    ("ret", "0"),
])

F("chanSend", ["ch", "v"], ["me", "g", "head", "tail", "cap", "closed", "seen"], (CHAN, "chanSend"), [
    ("call", "me", "chanMe", [], "chanMe"),
    ("L", "top"),
    ("call", "g", "chanLock", ["ch", "me", "0", "0"], "(chanLock ch me 0 0)"),
    ("if", "g != 0", "locked"),
    ("ghost", "sawPoison", []),
    ("ret", str(POISONED)),
    ("L", "locked"),
    ("pload", "head", "ch + 3", "(chanGet ch 3)"),
    ("pload", "tail", "ch + 4", "(chanGet ch 4)"),
    ("pload", "cap", "ch + 5", "(chanGet ch 5)"),
    ("pload", "closed", "ch + 6", "(chanGet ch 6)"),
    ("if", "closed == 1", "open"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("ret", str(CLOSED)),
    ("L", "open"),
    ("if", "tail - head < cap", "full", "(< (- tail head) cap)"),
    ("pstore", "ch + 8 + tail % cap", "v", "(chanPut ch (+ 8 (% tail cap)) v)"),
    ("pstore", "ch + 4", "tail + 1", "(chanPut ch 4 (+ tail 1))"),
    ("ghost", "accept", ["v"]),
    ("call", None, "chanBump", ["ch"], "(chanBump ch)"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("call", None, "chanNotify", ["ch"], "(chanNotify ch)"),
    ("ret", str(SENT)),
    ("L", "full"),
    ("call", "seen", "chanPark", ["ch"], "(chanPark ch)"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("call", None, "chanSleep", ["ch", "seen"], "(chanSleep ch seen)"),
    ("goto", "top"),
])
F("chanRecv", ["ch"], ["me", "g", "head", "tail", "cap", "got", "closed", "seen"], (CHAN, "chanRecv"), [
    ("call", "me", "chanMe", [], "chanMe"),
    ("L", "top"),
    ("call", "g", "chanLock", ["ch", "me", "0", "0"], "(chanLock ch me 0 0)"),
    ("if", "g != 0", "locked"),
    ("ghost", "sawPoison", []),
    ("ret", str(NONE)),
    ("L", "locked"),
    ("pload", "head", "ch + 3", "(chanGet ch 3)"),
    ("pload", "tail", "ch + 4", "(chanGet ch 4)"),
    ("pload", "cap", "ch + 5", "(chanGet ch 5)"),
    ("if", "head < tail", "empty", "(< head tail)"),
    ("pload", "got", "ch + 8 + head % cap", "(chanGet ch (+ 8 (% head cap)))"),
    ("pstore", "ch + 3", "head + 1", "(chanPut ch 3 (+ head 1))"),
    ("ghost", "take", ["got"]),
    ("call", None, "chanBump", ["ch"], "(chanBump ch)"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("call", None, "chanNotify", ["ch"], "(chanNotify ch)"),
    ("ret", "got"),
    ("L", "empty"),
    ("pload", "closed", "ch + 6", "(chanGet ch 6)"),
    ("if", "closed == 1", "open"),
    ("ghost", "eos", []),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("ret", str(NONE)),
    ("L", "open"),
    ("call", "seen", "chanPark", ["ch"], "(chanPark ch)"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("call", None, "chanSleep", ["ch", "seen"], "(chanSleep ch seen)"),
    ("goto", "top"),
])

# The timed forms: `b` is the word that stands for the scratch block's
# time left, in slices. A wait the kernel timed out costs the whole
# slice; any other costs the clock's step, clamped to [0, slice]
# (`chanTimeSpent`, `chanStep`), which the model chooses as 0 or the
# whole slice.
F("chanSendTimeout", ["ch", "v", "nanos", "b"],
  ["me", "g", "left", "head", "tail", "cap", "closed", "seen", "slice", "code", "d"], (CHAN, "chanSendTimeout"), [
    ("call", "me", "chanMe", [], "chanMe"),
    ("pstore", "b", "nanos", "(chanScratch nanos)"),
    ("L", "top"),
    ("call", "g", "chanLock", ["ch", "me", "b", "1"], "(chanLock ch me b 1)"),
    ("if", "g == 1", "intime"),
    ("ret", str(SEND_TIMED_OUT)),
    ("L", "intime"),
    ("if", "g == 2", "locked"),
    ("ghost", "sawPoison", []),
    ("ret", str(POISONED)),
    ("L", "locked"),
    ("pload", "head", "ch + 3", "(chanGet ch 3)"),
    ("pload", "tail", "ch + 4", "(chanGet ch 4)"),
    ("pload", "cap", "ch + 5", "(chanGet ch 5)"),
    ("pload", "closed", "ch + 6", "(chanGet ch 6)"),
    ("if", "closed == 1", "open"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("ret", str(CLOSED)),
    ("L", "open"),
    ("if", "tail - head < cap", "full", "(< (- tail head) cap)"),
    ("pstore", "ch + 8 + tail % cap", "v", "(chanPut ch (+ 8 (% tail cap)) v)"),
    ("pstore", "ch + 4", "tail + 1", "(chanPut ch 4 (+ tail 1))"),
    ("ghost", "accept", ["v"]),
    ("call", None, "chanBump", ["ch"], "(chanBump ch)"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("call", None, "chanNotify", ["ch"], "(chanNotify ch)"),
    ("ret", str(SENT)),
    ("L", "full"),
    ("pload", "left", "b", "(<= (chanTimeLeft b) 0)"),
    ("if", "left <= 0", "wait"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("ret", str(SEND_TIMED_OUT)),
    ("L", "wait"),
    ("call", "seen", "chanPark", ["ch"], "(chanPark ch)"),
    ("set", "slice", "min(left, 1)", "(chanSlice b)"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("call", "code", "chanSleepFor", ["ch", "seen", "slice"], "(chanTimeSpent b (chanSleepFor ch seen slice) slice)"),
    ("choose", "d", "(0, slice)"),
    ("pstore", "b", "left - (slice if code == 1 else d)"),
    ("goto", "top"),
])
F("chanRecvTimeout", ["ch", "nanos", "b"],
  ["me", "g", "left", "head", "tail", "cap", "got", "closed", "seen", "slice", "code", "d"], (CHAN, "chanRecvTimeout"), [
    ("call", "me", "chanMe", [], "chanMe"),
    ("pstore", "b", "nanos", "(chanScratch nanos)"),
    ("L", "top"),
    ("call", "g", "chanLock", ["ch", "me", "b", "1"], "(chanLock ch me b 1)"),
    ("if", "g == 1", "intime"),
    ("ret", str(TIMED_OUT)),
    ("L", "intime"),
    ("if", "g == 2", "locked"),
    ("ghost", "sawPoison", []),
    ("ret", str(RECV_POISONED)),
    ("L", "locked"),
    ("pload", "head", "ch + 3", "(chanGet ch 3)"),
    ("pload", "tail", "ch + 4", "(chanGet ch 4)"),
    ("pload", "cap", "ch + 5", "(chanGet ch 5)"),
    ("if", "head < tail", "empty", "(< head tail)"),
    ("pload", "got", "ch + 8 + head % cap", "(chanGet ch (+ 8 (% head cap)))"),
    ("pstore", "ch + 3", "head + 1", "(chanPut ch 3 (+ head 1))"),
    ("ghost", "take", ["got"]),
    ("call", None, "chanBump", ["ch"], "(chanBump ch)"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("call", None, "chanNotify", ["ch"], "(chanNotify ch)"),
    ("ret", "got"),
    ("L", "empty"),
    ("pload", "closed", "ch + 6", "(chanGet ch 6)"),
    ("if", "closed == 1", "open"),
    ("ghost", "eos", []),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("ret", str(NONE)),
    ("L", "open"),
    ("pload", "left", "b", "(<= (chanTimeLeft b) 0)"),
    ("if", "left <= 0", "wait"),
    ("ghost", "recvTimedOut", []),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("ret", str(TIMED_OUT)),
    ("L", "wait"),
    ("call", "seen", "chanPark", ["ch"], "(chanPark ch)"),
    ("set", "slice", "min(left, 1)", "(chanSlice b)"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("call", "code", "chanSleepFor", ["ch", "seen", "slice"], "(chanTimeSpent b (chanSleepFor ch seen slice) slice)"),
    ("choose", "d", "(0, slice)"),
    ("pstore", "b", "left - (slice if code == 1 else d)"),
    ("goto", "top"),
])
F("chanTrySend", ["ch", "v"], ["me", "g", "head", "tail", "cap", "closed"], (CHAN, "chanTrySend"), [
    ("call", "me", "chanMe", [], "chanMe"),
    ("call", "g", "chanLock", ["ch", "me", "0", "0"], "(chanLock ch me 0 0)"),
    ("if", "g != 0", "locked"),
    ("ghost", "sawPoison", []),
    ("ret", "0"),
    ("L", "locked"),
    ("pload", "head", "ch + 3", "(chanGet ch 3)"),
    ("pload", "tail", "ch + 4", "(chanGet ch 4)"),
    ("pload", "cap", "ch + 5", "(chanGet ch 5)"),
    ("pload", "closed", "ch + 6", "(chanGet ch 6)"),
    ("if", "closed == 1", "open"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("ret", "0"),
    ("L", "open"),
    ("if", "tail - head < cap", "full", "(< (- tail head) cap)"),
    ("pstore", "ch + 8 + tail % cap", "v", "(chanPut ch (+ 8 (% tail cap)) v)"),
    ("pstore", "ch + 4", "tail + 1", "(chanPut ch 4 (+ tail 1))"),
    ("ghost", "accept", ["v"]),
    ("call", None, "chanBump", ["ch"], "(chanBump ch)"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("call", None, "chanNotify", ["ch"], "(chanNotify ch)"),
    ("ret", "1"),
    ("L", "full"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("ret", "0"),
])
F("chanTryRecv", ["ch"], ["me", "g", "head", "tail", "cap", "got"], (CHAN, "chanTryRecv"), [
    ("call", "me", "chanMe", [], "chanMe"),
    ("call", "g", "chanLock", ["ch", "me", "0", "0"], "(chanLock ch me 0 0)"),
    ("if", "g != 0", "locked"),
    ("ghost", "sawPoison", []),
    ("ret", str(NONE)),
    ("L", "locked"),
    ("pload", "head", "ch + 3", "(chanGet ch 3)"),
    ("pload", "tail", "ch + 4", "(chanGet ch 4)"),
    ("pload", "cap", "ch + 5", "(chanGet ch 5)"),
    ("if", "head < tail", "empty", "(< head tail)"),
    ("pload", "got", "ch + 8 + head % cap", "(chanGet ch (+ 8 (% head cap)))"),
    ("pstore", "ch + 3", "head + 1", "(chanPut ch 3 (+ head 1))"),
    ("ghost", "take", ["got"]),
    ("call", None, "chanBump", ["ch"], "(chanBump ch)"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("call", None, "chanNotify", ["ch"], "(chanNotify ch)"),
    ("ret", "got"),
    ("L", "empty"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("ret", str(NONE)),
])
F("chanClose", ["ch"], ["me", "g"], (CHAN, "chanClose"), [
    ("call", "me", "chanMe", [], "chanMe"),
    ("call", "g", "chanLock", ["ch", "me", "0", "0"], "(chanLock ch me 0 0)"),
    ("if", "g != 0", "locked"),
    ("ghost", "sawPoison", []),
    ("ret", "0"),
    ("L", "locked"),
    ("pstore", "ch + 6", "1", "(chanPut ch 6 1)"),
    ("ghost", "close", []),
    ("call", None, "chanBump", ["ch"], "(chanBump ch)"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("call", None, "chanNotify", ["ch"], "(chanNotify ch)"),
    ("ret", "0"),
])
F("chanClosed", ["ch"], ["me", "g", "c"], (CHAN, "chanClosed"), [
    ("call", "me", "chanMe", [], "chanMe"),
    ("call", "g", "chanLock", ["ch", "me", "0", "0"], "(chanLock ch me 0 0)"),
    ("if", "g != 0", "locked"),
    ("ghost", "sawPoison", []),
    ("ret", "1"),
    ("L", "locked"),
    ("pload", "c", "ch + 6", "(chanGet ch 6)"),
    ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)"),
    ("ret", "1 if c == 1 else 0"),
])
F("chanPoisoned", ["ch"], ["p"], (CHAN, "chanPoisoned"), [
    ("call", "p", "chanIsPoisoned", ["ch"], "(chanIsPoisoned (chanAt c))"),
    ("ret", "p"),
])

# ---- Sync.ax ---------------------------------------------------------------
# Words: 0 the lock (0, or the holder's pid * 4, plus 1 when someone
# waits), 1 the holder's guard, 2 the guard counter, 3 poisoned, 4 the
# mapping length. The mutex is at word 0. `syncLoad`, `syncStore`,
# `syncCas` and `syncCasAt` are the atomics on word i (`WRAPPERS` below).

F("syncMe", [], ["p"], (SYNC, "syncMe"), [
    ("pid", "p", "sysPid"),
    ("ret", "p * 4"),
])
F("syncNextGuard", ["m"], ["old"], (SYNC, "syncNextGuard"), [
    ("aadd", "old", "m + 2", "1", "(__atomic_add (+ m 16) 1)"),
    ("ret", "old + 1"),
])
F("syncTake", ["m"], ["g"], (SYNC, "syncTake"), [
    ("call", "g", "syncNextGuard", ["m"], "(syncNextGuard m)"),
    ("astore", "m + 1", "g", "(syncStore m 1 g)"),
    ("ret", "g"),
])
F("syncHolderDead", ["m", "v", "me"], ["owner", "k", "w", "e"], (SYNC, "syncHolderDead"), [
    ("set", "owner", "v // 4", "(/ v 4)"),
    ("if", "owner == 0 or owner * 4 == me", "look"),
    ("ret", "0"),
    ("L", "look"),
    ("kill0", "k", "owner", "(sysKill owner 0)"),
    ("if", "k == 0", "gone"),
    ("call", "e", "syncChildEnded", ["owner"], "(syncChildEnded owner)"),
    ("if", "e == 1", "alive"),
    ("aload", "w", "m", "(syncLoad m 0)"),
    ("ret", "1 if w // 4 == owner else 0"),
    ("L", "alive"),
    ("ret", "0"),
    ("L", "gone"),
    ("if", "k == 3", "other", "(== (errCode e) 3)"),
    ("aload", "w", "m", "(syncLoad m 0)"),
    ("ret", "1 if w // 4 == owner else 0"),
    ("L", "other"),
    ("ret", "0"),
])
F("syncChildEnded", ["pid"], ["x"], (SYNC, "syncChildEnded"), [
    ("look", "x", "pid", "(sysChildExited pid buf)"),
    ("ret", "x"),
])
F("syncPoison", ["m"], [], (SYNC, "syncPoison"), [
    ("astore", "m + 3", "1", "(syncStore m 3 1)"),
    ("ghost", "poison", []),
    ("call", None, "sysWakeWord", ["m"], "(sysWakeWord m)"),
    ("ret", "0"),
])
F("syncMarkWaiting", ["m", "v"], ["r"], (SYNC, "syncMarkWaiting"), [
    ("if", "v % 2 == 1", "mark", "(== (% v 2) 1)"),
    ("ret", "v"),
    ("L", "mark"),
    ("acas", "r", "m", "v", "v + 1", "(syncCas m v (+ v 1))"),
    ("if", "r == v", "moved"),
    ("ret", "v + 1"),
    ("L", "moved"),
    ("ret", "0"),
])
# `b` is the scratch block's time left, in slices; `timed` is 1 for
# mutexLockTimeout. A slice is `syncProbeNanos`, one unit here.
F("syncAcquire", ["m", "left", "timed"], ["me", "p", "v", "r", "g", "w", "slice", "code", "d", "dead"],
  (SYNC, "syncAcquire"), [
    ("call", "me", "syncMe", [], "syncMe"),
    ("L", "top"),
    ("aload", "p", "m + 3", "(syncLoad m 3)"),
    ("if", "p == 1", "live"),
    ("ret", str(OWNER_DEAD)),
    ("L", "live"),
    ("aload", "v", "m", "(syncLoad m 0)"),
    ("if", "v == 0", "held"),
    ("acas", "r", "m", "0", "me + 1", "(syncCas m 0 (+ me 1))"),
    ("if", "r == 0", "top"),
    ("ghost", "acquire", []),
    ("call", "g", "syncTake", ["m"], "(syncTake m)"),
    ("ret", "g"),
    ("L", "held"),
    ("if", "timed == 1 and left <= 0", "time", "(syncOutOfTime b timed)"),
    ("ret", str(LOCK_TIMED_OUT)),
    ("L", "time"),
    ("call", "w", "syncMarkWaiting", ["m", "v"], "(syncMarkWaiting m v)"),
    ("if", "w == 0", "marked"),
    ("goto", "top"),
    ("L", "marked"),
    ("set", "slice", "min(left, 1) if timed == 1 else 1", "(syncSlice b timed)"),
    ("call", "code", "sysWaitWordTimeout", ["m", "w", "slice"], "(sysWaitWordTimeout m w slice)"),
    ("if", "timed == 1", "untimed"),
    ("choose", "d", "(0, slice)", "(syncTimeSpent b code slice)"),
    ("set", "left", "left - (slice if code == 1 else d)"),
    ("L", "untimed"),
    ("if", "code == 1", "top"),
    ("call", "dead", "syncHolderDead", ["m", "w", "me"], "(syncHolderDead m w me)"),
    ("if", "dead == 1", "top"),
    ("call", None, "syncPoison", ["m"], "(syncPoison m)"),
    ("ret", str(OWNER_DEAD)),
])
F("mutexLock", ["m"], ["p", "me", "r", "g"], (SYNC, "mutexLock"), [
    ("aload", "p", "m + 3", "(syncLoad m 3)"),
    ("if", "p == 1", "live"),
    ("ret", str(OWNER_DEAD)),
    ("L", "live"),
    ("call", "me", "syncMe", [], "syncMe"),
    ("acas", "r", "m", "0", "me", "(syncCas m 0 me)"),
    ("if", "r == 0", "slow"),
    ("ghost", "acquire", []),
    ("call", "g", "syncTake", ["m"], "(syncTake m)"),
    ("ret", "g"),
    ("L", "slow"),
    ("call", "g", "syncAcquire", ["m", "0", "0"], "(syncAcquire m 0 0)"),
    ("if", "g > 0", "dead"),
    ("ret", "g"),
    ("L", "dead"),
    ("ret", str(OWNER_DEAD)),
])
F("mutexTryLock", ["m"], ["p", "me", "r", "g"], (SYNC, "mutexTryLock"), [
    ("aload", "p", "m + 3", "(syncLoad m 3)"),
    ("if", "p == 1", "live"),
    ("ret", "0"),
    ("L", "live"),
    ("call", "me", "syncMe", [], "syncMe"),
    ("acas", "r", "m", "0", "me", "(syncCas m 0 me)"),
    ("if", "r == 0", "held"),
    ("ghost", "acquire", []),
    ("call", "g", "syncTake", ["m"], "(syncTake m)"),
    ("ret", "g"),
    ("L", "held"),
    ("ret", "0"),
])
F("mutexLockTimeout", ["m", "nanos"], ["p", "me", "r", "g"], (SYNC, "mutexLockTimeout"), [
    ("aload", "p", "m + 3", "(syncLoad m 3)"),
    ("if", "p == 1", "live"),
    ("ret", str(OWNER_DEAD)),
    ("L", "live"),
    ("call", "me", "syncMe", [], "syncMe"),
    ("acas", "r", "m", "0", "me", "(syncCas m 0 me)"),
    ("if", "r == 0", "slow"),
    ("ghost", "acquire", []),
    ("call", "g", "syncTake", ["m"], "(syncTake m)"),
    ("ret", "g"),
    ("L", "slow"),
    ("call", "g", "syncAcquire", ["m", "nanos", "1"], "(syncAcquire m b 1)"),
    ("ret", "g"),
])
F("mutexUnlock", ["m", "guard"], ["r", "v", "r2"], (SYNC, "mutexUnlock"), [
    ("if", "guard <= 0", "claim", "(<= guard 0)"),
    ("ret", str(NOT_HELD)),
    ("L", "claim"),
    ("acas", "r", "m + 1", "guard", "0", "(syncCasAt m 1 guard 0)"),
    ("if", "r != guard", "claimed"),
    ("ret", str(NOT_HELD)),
    ("L", "claimed"),
    ("aload", "v", "m", "(syncLoad m 0)"),
    ("if", "v % 2 == 0", "waiters", "(== (% v 2) 0)"),
    ("acas", "r2", "m", "v", "0", "(syncCas m v 0)"),
    ("if", "r2 == v", "waiters"),
    ("ghost", "release", []),
    ("ret", str(UNLOCK_OK)),
    ("L", "waiters"),
    ("astore", "m", "0", "(syncStore m 0 0)"),
    ("ghost", "release", []),
    ("call", None, "sysWakeWord", ["m"], "(sysWakeWord m)"),
    ("ret", str(UNLOCK_OK)),
])

# The one-line wrappers each module reads its words through: the model
# takes `(syncLoad m i)` to be an atomic load of word i, and so on, and
# `source` checks that each wrapper still says so.
WRAPPERS = [
    (CHAN, "chanGet", "(__load64 ch i)"),
    (CHAN, "chanPut", "(__store64 ch i v)"),
    (CHAN, "chanStep", "(if (== code 1)\n    slice"),
    (CHAN, "chanSlice", "(if (< (chanTimeLeft b) chanSliceNanos)"),
    (CHAN, "chanLockSlice", "(if (== timed 1)\n    (chanSlice b)\n    chanSliceNanos)"),
    (CHAN, "chanOutOfTime", "(if (== timed 1)\n    (<= (chanTimeLeft b) 0)\n    false)"),
    (CHAN, "chanMe", "(* sysPid 4)"),
    (CHAN, "chanPoisonMark", "(fn (chanPoisonMark)\n  %d)" % POISON),
    (SYNC, "syncLoad", "(__atomic_load (+ m (* 8 i)))"),
    (SYNC, "syncStore", "(__atomic_store (+ m (* 8 i)) v)"),
    (SYNC, "syncCas", "(__atomic_cas m old new)"),
    (SYNC, "syncCasAt", "(__atomic_cas (+ m (* 8 i)) old new)"),
    (SYNC, "syncMe", "(* sysPid 4)"),
    (SYNC, "syncOutOfTime", "(<= (syncTimeLeft b) 0)"),
    (SYNC, "syncSlice", "(if (< (syncTimeLeft b) syncProbeNanos)"),
    (SYNC, "syncStep", "(if (== code 1)\n    slice"),
    (SYS, "sysWakeWordRaw", "2147483647"),
    (SYS, "sysWaitWordTimeout", "(sysWaitWordTimed addr expected nanos)"),
]

# Transcribed steps no scenario reaches, and why. The coverage report
# names every other unreached step as a gap in the scenarios.
UNREACHABLE = {
    ("sysWaitWordTimeout", ("ret", "1")):
        "a non-positive wait: every caller asks for a slice of at least one",
    ("syncHolderDead", ("ret", "0"), 3):
        "kill(pid, 0) answering an error other than ESRCH, which the model's kill never does",
}

# Every other function in the two modules, and why the model leaves it out.
NOT_MODELLED = {
    CHAN: {
        "chanScratch": "the timed forms' private time left: the binding's own word `b` in the model",
        "chanBlock": "a scratch block with a share taken; touches no channel word",
        "chanBlockDone": "returns a scratch block; touches no channel word",
        "chanTimeLeft": "reads the private time left",
        "chanTimeSpent": "charges a wait to the private time left: the model's `choose`",
        "chanSlice": "min(time left, one slice): the model's `min(left, 1)`; checked in WRAPPERS",
        "chanLockSlice": "the lock wait's slice, timed or not, checked in WRAPPERS",
        "chanOutOfTime": "time left <= 0 for a timed lock, checked in WRAPPERS",
        "chanSliceNanos": "a constant, the slice",
        "chanPoisonMark": "a constant, the poisoned lock word, checked in WRAPPERS",
        "chanYes": "reads a look's answer: `Ok True` is 1, anything else 0, the model's look",
        "chanStep": "the charge rule, checked in WRAPPERS",
        "chanGet": "the plain load of a lock-protected word, checked in WRAPPERS",
        "chanPut": "the plain store to a lock-protected word, checked in WRAPPERS",
        "chanNew": "runs before any binding can reach the channel",
        "chanLen": "a lock, two reads and an unlock: chanClosed's shape, which is modelled",
        "chanCap": "reads the capacity, written once by chanNew, with no lock",
        "chanFree": "runs after the parallel form, when no binding can reach the channel",
        "chanKind": "a constant, the handle table's kind for a channel",
        "chanAt": "the handle table's lookup of a live channel's ring; touches no channel word",
        "chanName": "names a fresh ring in the handle table, inside chanNew",
        "chanNamed": "chanNew's handle step, before any binding can reach the channel",
        "chanRetire": "retires the handle inside chanFree, after the parallel form",
    },
    SYNC: {
        "syncOwnerDead": "a constant", "syncNotHeld": "a constant", "syncProbeNanos": "a constant, the slice",
        "syncLoad": "the atomic load of word i, checked in WRAPPERS",
        "syncStore": "the atomic store to word i, checked in WRAPPERS",
        "syncCas": "the compare-and-swap of word 0, checked in WRAPPERS",
        "syncCasAt": "the compare-and-swap of word i, checked in WRAPPERS",
        "syncScratch": "the timed lock's private time left, the model's `left`",
        "syncScratchDone": "returns the scratch block", "syncTimeLeft": "reads the private time left",
        "syncBlock": "a scratch block with a share taken; touches no mutex word",
        "syncYes": "reads a look's answer: `Ok True` is 1, anything else 0, the model's look",
        "syncTimeSpent": "charges a wait: the model's `choose`", "syncStep": "the charge rule, checked in WRAPPERS",
        "syncOutOfTime": "time left <= 0 for a timed wait, checked in WRAPPERS",
        "syncSlice": "min(time left, the slice), checked in WRAPPERS",
        "mutexNew": "runs before any binding can reach the mutex",
        "mutexOwnerDead": "one load of the poisoned word",
        "mutexFree": "runs after the parallel form",
        "syncKind": "a constant, the handle table's kind for a mutex",
        "syncAt": "the handle table's lookup of a live mutex's page; touches no mutex word",
        "syncName": "names a fresh page in the handle table, inside mutexNew",
        "syncNamed": "mutexNew's handle step, before any binding can reach the mutex",
        "syncRetire": "retires the handle inside mutexFree, after the parallel form",
    },
}

# ---------------------------------------------------------------------
# Compilation: labels to indices, expressions to closures over the
# frame's locals (a tuple in declaration order: parameters, then locals).
# ---------------------------------------------------------------------


class Violation(Exception):
    def __init__(self, kind, msg):
        Exception.__init__(self, msg)
        self.kind = kind
        self.msg = msg


class Code:
    __slots__ = ("name", "params", "vars", "src", "ins", "raw", "nlocs", "keep_top", "keep_call")

    def __init__(self, name, params, locs, src, body):
        self.name, self.params, self.src = name, params, src
        self.vars = params + locs
        self.nlocs = len(locs)
        labels, raw = {}, []
        for t in body:
            if t[0] == "L":
                if t[1] in labels:
                    raise ValueError("%s: label %s twice" % (name, t[1]))
                labels[t[1]] = len(raw)
            else:
                raw.append(t)
        self.raw = raw
        self.ins = [self._compile(t, labels) for t in raw]

    def _expr(self, e):
        return eval("lambda %s: (%s)" % (", ".join(self.vars), e), {"min": min})

    def _var(self, v):
        if v is None:
            return None
        if v not in self.vars:
            raise ValueError("%s: no local %s" % (self.name, v))
        return self.vars.index(v)

    def _compile(self, t, labels):
        op = t[0]
        n = ARITY[op]
        a = t[1:1 + n]
        sp = t[1 + n] if len(t) > 1 + n else None
        E, V = self._expr, self._var

        def lab(x):
            if x not in labels:
                raise ValueError("%s: no label %s" % (self.name, x))
            return labels[x]
        if op == "set":
            return (op, V(a[0]), E(a[1]), sp)
        if op == "if":
            return (op, E(a[0]), lab(a[1]), sp)
        if op == "goto":
            return (op, lab(a[0]), sp)
        if op == "call":
            return (op, V(a[0]), a[1], [E(x) for x in a[2]], sp)
        if op == "ret":
            return (op, E(a[0]), sp)
        if op in ("aload", "uload", "pload"):
            return (op, V(a[0]), E(a[1]), sp)
        if op in ("astore", "pstore"):
            return (op, E(a[0]), E(a[1]), sp)
        if op == "aadd":
            return (op, V(a[0]), E(a[1]), E(a[2]), sp)
        if op == "acas":
            return (op, V(a[0]), E(a[1]), E(a[2]), E(a[3]), sp)
        if op == "wait":
            return (op, V(a[0]), E(a[1]), E(a[2]), a[3], sp)
        if op == "wake":
            return (op, E(a[0]), sp)
        if op == "pid":
            return (op, V(a[0]), sp)
        if op in ("kill0", "look", "join", "kill9"):
            return (op, V(a[0]), E(a[1]), sp)
        if op == "clock":
            return (op, V(a[0]), sp)
        if op == "spawn":
            return (op, V(a[0]), E(a[1]), E(a[2]), sp)
        if op == "sleepuntil":
            return (op, V(a[0]), E(a[1]), E(a[2]), E(a[3]), sp)
        if op == "block":
            return (op, sp)
        if op == "choose":
            return (op, V(a[0]), E(a[1]), sp)
        if op == "ghost":
            return (op, a[0], [E(x) for x in a[1]], None)
        if op == "assert":
            return (op, E(a[0]), a[1], None)
        raise ValueError(op)


def compile_all(fns):
    codes = {name: Code(name, *spec) for name, spec in fns.items()}
    for c in codes.values():
        for ins in c.ins:
            if ins[0] == "call" and ins[2] not in codes:
                raise ValueError("%s calls %s, which is not modelled" % (c.name, ins[2]))
        liveness(c)
    return codes


IDENT = re.compile(r"[A-Za-z_][A-Za-z0-9_]*")


def liveness(code):
    """Which locals each frame still needs. A frame stopped at pc keeps the
    locals live into pc; a caller's frame, stopped at its call, keeps those
    live after the call but the one the call's answer overwrites. The rest
    are dead - written before they are next read - so `freeze` zeroes them,
    and two states that differ only in a dead local are one state."""
    names = set(code.vars)
    n = len(code.raw)

    def uses_of(exprs):
        u = set()
        for e in exprs:
            if isinstance(e, str):
                u |= set(IDENT.findall(e)) & names
        return u
    uses, defs, succ = [], [], []
    for pc, t in enumerate(code.raw):
        op = t[0]
        a = t[1:1 + ARITY[op]]
        dst = None
        if op == "set":
            dst, ex = a[0], [a[1]]
        elif op == "call":
            dst, ex = a[0], list(a[2])
        elif op in ("aload", "uload", "pload", "kill0", "look", "choose", "join", "kill9"):
            dst, ex = a[0], [a[1]]
        elif op == "spawn":
            dst, ex = a[0], [a[1], a[2]]
        elif op == "sleepuntil":
            dst, ex = a[0], [a[1], a[2], a[3]]
        elif op == "clock":
            dst, ex = a[0], []
        elif op == "block":
            ex = []
        elif op in ("aadd", "acas", "wait"):
            dst, ex = a[0], list(a[1:4]) if op != "wait" else [a[1], a[2]]
        elif op == "pid":
            dst, ex = a[0], []
        elif op == "ghost":
            ex = list(a[1])
        elif op == "goto":
            ex = []
        else:
            ex = list(a)
        uses.append(uses_of(ex))
        defs.append({dst} if dst else set())
        ins = code.ins[pc]
        if op == "if":
            succ.append({pc + 1, ins[2]})
        elif op == "goto":
            succ.append({ins[1]})
        elif op == "ret":
            succ.append(set())
        else:
            succ.append({pc + 1})
    live_in = [set() for _ in range(n)]
    live_out = [set() for _ in range(n)]
    changed = True
    while changed:
        changed = False
        for pc in range(n - 1, -1, -1):
            out = set()
            for q in succ[pc]:
                if q < n:
                    out |= live_in[q]
            inn = uses[pc] | (out - defs[pc])
            if out != live_out[pc] or inn != live_in[pc]:
                live_out[pc], live_in[pc] = out, inn
                changed = True
    code.keep_top = [tuple(i for i, v in enumerate(code.vars) if v in live_in[pc]) for pc in range(n)]
    code.keep_call = [tuple(i for i, v in enumerate(code.vars) if v in live_out[pc] - defs[pc]) for pc in range(n)]


# ---------------------------------------------------------------------
# Scenarios: the programs the bindings run, what the words start as, and
# the checks.
# ---------------------------------------------------------------------

# Channel drivers. Sender `s` sends s*1000+1, s*1000+2, ... (as
# tests/litmus/chan-trace.ax does, so a recorded run replays).
F("sender", ["ch", "s", "n", "closes"], ["k", "r"], None, [
    ("set", "k", "1"),
    ("L", "loop"),
    ("if", "k <= n", "end"),
    ("call", "r", "chanSend", ["ch", "s * 1000 + k"]),
    ("ghost", "answered", ["s * 1000 + k", "1 if r == %d else 0" % SENT]),
    ("set", "k", "k + 1"),
    ("goto", "loop"),
    ("L", "end"),
    ("if", "closes == 1", "done"),
    ("call", None, "chanClose", ["ch"]),
    ("L", "done"),
    ("ret", "0"),
])
F("receiver", ["ch"], ["r"], None, [
    ("L", "loop"),
    ("call", "r", "chanRecv", ["ch"]),
    ("if", "r == %d" % NONE, "loop"),
    ("ret", "0"),
])
# `b` is the binding's private word for a timed call's time left.
F("timedSender", ["ch", "s", "n", "t", "b"], ["k", "r"], None, [
    ("set", "k", "1"),
    ("L", "loop"),
    ("if", "k <= n", "end"),
    ("call", "r", "chanSendTimeout", ["ch", "s * 1000 + k", "t", "b"]),
    ("ghost", "answered", ["s * 1000 + k", "1 if r == %d else 0" % SENT]),
    ("set", "k", "k + 1"),
    ("goto", "loop"),
    ("L", "end"),
    ("call", None, "chanClose", ["ch"]),
    ("ret", "0"),
])
F("timedReceiver", ["ch", "t", "b"], ["r"], None, [
    ("L", "loop"),
    ("call", "r", "chanRecvTimeout", ["ch", "t", "b"]),
    ("if", "r == %d or r == %d" % (NONE, RECV_POISONED), "loop"),
    ("ret", "0"),
])
# Takes one word, closes the channel, then drains it: a send after that
# is refused, in whichever form it was made.
F("closingReceiver", ["ch"], ["r"], None, [
    ("call", "r", "chanRecv", ["ch"]),
    ("call", None, "chanClose", ["ch"]),
    ("L", "loop"),
    ("call", "r", "chanRecv", ["ch"]),
    ("if", "r == %d" % NONE, "loop"),
    ("ret", "0"),
])
# Gives up at its first answer that is not a word: the AN-10 scenario's
# receiver.
F("timedReceiverOnce", ["ch", "t", "b"], ["r"], None, [
    ("L", "loop"),
    ("call", "r", "chanRecvTimeout", ["ch", "t", "b"]),
    ("if", "r > 0", "stop"),
    ("goto", "loop"),
    ("L", "stop"),
    ("ret", "0"),
])
F("trySender", ["ch", "s", "n"], ["k", "r"], None, [
    ("set", "k", "1"),
    ("L", "loop"),
    ("if", "k <= n", "end"),
    ("call", "r", "chanTrySend", ["ch", "s * 1000 + k"]),
    ("ghost", "answered", ["s * 1000 + k", "r"]),
    ("set", "k", "k + 1"),
    ("goto", "loop"),
    ("L", "end"),
    ("call", None, "chanClose", ["ch"]),
    ("ret", "0"),
])
# Polls: closed is read before the empty try, so an empty try after a
# close has seen everything the channel will ever hold.
F("tryReceiver", ["ch"], ["c", "r"], None, [
    ("L", "loop"),
    ("call", "c", "chanClosed", ["ch"]),
    ("call", "r", "chanTryRecv", ["ch"]),
    ("if", "r == %d" % NONE, "loop"),
    ("if", "c == 1", "loop"),
    ("ghost", "drained", []),
    ("ret", "0"),
])

# Receives to the end of the stream, then asks why it ended: a poisoned
# channel must say so, and a closed one must not.
F("watchingReceiver", ["ch"], ["r", "p"], None, [
    ("L", "loop"),
    ("call", "r", "chanRecv", ["ch"]),
    ("if", "r == %d" % NONE, "loop"),
    ("call", "p", "chanPoisoned", ["ch"]),
    ("ghost", "poisonedIs", ["p"]),
    ("ret", "0"),
])
# Closes the channel and nothing else.
F("closer", ["ch"], [], None, [
    ("call", None, "chanClose", ["ch"]),
    ("ret", "0"),
])

# Mutex drivers.
F("locker", ["m", "n"], ["k", "g", "r"], None, [
    ("set", "k", "0"),
    ("L", "loop"),
    ("if", "k < n", "end"),
    ("call", "g", "mutexLock", ["m"]),
    ("if", "g > 0", "dead"),
    ("call", "r", "mutexUnlock", ["m", "g"]),
    ("assert", "r == %d" % UNLOCK_OK, "the holder's own unlock was refused"),
    ("set", "k", "k + 1"),
    ("goto", "loop"),
    ("L", "dead"),
    ("ghost", "ownerDead", []),
    ("L", "end"),
    ("ret", "0"),
])
# Unlocks twice: the second guard is stale and must be refused.
F("staleLocker", ["m", "n"], ["k", "g", "r"], None, [
    ("call", "r", "mutexUnlock", ["m", "0"]),
    ("ghost", "staleAnswer", ["r"]),
    ("set", "k", "0"),
    ("L", "loop"),
    ("if", "k < n", "end"),
    ("call", "g", "mutexLock", ["m"]),
    ("assert", "g > 0", "mutexLock failed"),
    ("call", "r", "mutexUnlock", ["m", "g"]),
    ("assert", "r == %d" % UNLOCK_OK, "the holder's own unlock was refused"),
    ("call", "r", "mutexUnlock", ["m", "g"]),
    ("ghost", "staleAnswer", ["r"]),
    ("set", "k", "k + 1"),
    ("goto", "loop"),
    ("L", "end"),
    ("ret", "0"),
])
F("timedLocker", ["m", "t"], ["g", "r"], None, [
    ("call", "g", "mutexLockTimeout", ["m", "t"]),
    ("if", "g > 0", "failed"),
    ("call", "r", "mutexUnlock", ["m", "g"]),
    ("assert", "r == %d" % UNLOCK_OK, "the holder's own unlock was refused"),
    ("ret", "0"),
    ("L", "failed"),
    ("ghost", "lockFailed", ["g"]),
    ("ret", "0"),
])
# Locks (and unlocks) once, then tries: after a poisoning the try must
# answer None.
F("lockThenTry", ["m"], ["g", "r"], None, [
    ("call", "g", "mutexLock", ["m"]),
    ("if", "g > 0", "dead"),
    ("call", "r", "mutexUnlock", ["m", "g"]),
    ("assert", "r == %d" % UNLOCK_OK, "the holder's own unlock was refused"),
    ("goto", "try"),
    ("L", "dead"),
    ("ghost", "ownerDead", []),
    ("L", "try"),
    ("call", "g", "mutexTryLock", ["m"]),
    ("if", "g > 0", "none"),
    ("call", "r", "mutexUnlock", ["m", "g"]),
    ("assert", "r == %d" % UNLOCK_OK, "the holder's own unlock was refused"),
    ("ret", "0"),
    ("L", "none"),
    ("ret", "0"),
])
F("tryLocker", ["m"], ["g", "r"], None, [
    ("call", "g", "mutexTryLock", ["m"]),
    ("if", "g > 0", "none"),
    ("call", "r", "mutexUnlock", ["m", "g"]),
    ("assert", "r == %d" % UNLOCK_OK, "the holder's own unlock was refused"),
    ("L", "none"),
    ("ret", "0"),
])


class Scenario:
    """Bindings (driver, args), the initial words, and which environment
    transitions exist and which count as progress."""

    def __init__(self, name, kind, mem, bindings, progress=("n",), pids=None,
                 killable=(), what="", drains=True, parents=None):
        self.name, self.kind, self.mem0, self.bindings = name, kind, tuple(mem), bindings
        self.progress = frozenset(progress)
        self.pids = pids or [b + 1 for b in range(len(bindings))]
        self.killable = frozenset(killable)
        self.procs = bool(killable)
        # Binding -> the binding whose child it is. Only its parent can
        # look at it with `waitid`, and only its parent reaps it, which
        # the model's parent never does; every other binding is the
        # environment's child, reaped by a reap transition.
        self.parents = dict(parents or {})
        # The task pool's: whether `sysChildExited` exists, the clock's
        # word and its horizon, each child's exit-status word, and the
        # bindings that start unspawned (`N`).
        self.lookable = True
        self.clock = None
        self.horizon = 0
        self.exitword = {}
        self.unspawned = frozenset()
        self.what = what
        self.drains = drains

    # The ghost: a dict frozen into a tuple of (key, value) pairs.
    def ghost0(self):
        g = {"hold": frozenset(), "dead": 0}
        if self.kind == "chan":
            g.update(acc=(), log=(), ref=frozenset(), eos=0)
        return g


def chan_mem(cap):
    """The channel's words, and past the ring one private word per binding
    for a timed call's time left (`scratch(cap, k)` names binding k's)."""
    return [0, 0, 0, 0, 0, cap, 0, 8 * (cap + 8)] + [0] * cap + [0] * 3


def scratch(cap, k):
    return 8 + cap + k


def sync_mem():
    return [0, 0, 0, 0, 4096]


def scenarios(long=False):
    """The bounds. Two bindings: capacities 1 and 2, one to four words
    (six under --long). Three bindings: one and two words each (three
    under --long). Timed forms: one and two slices. Four bindings under
    --long."""
    out = []
    S = Scenario
    two = (1, 2, 3, 4, 5, 6) if long else (1, 2, 3, 4)
    three = (1, 2, 3) if long else (1, 2)
    for cap in (1, 2):
        for n in two:
            out.append(S("chan cap %d: 1 sender x%d, 1 receiver" % (cap, n), "chan", chan_mem(cap),
                         [("sender", (0, 1, n, 1)), ("receiver", (0,))]))
        for n in three:
            out.append(S("chan cap %d: 2 senders x%d, one closes, 1 receiver" % (cap, n), "chan", chan_mem(cap),
                         [("sender", (0, 1, n, 1)), ("sender", (0, 2, n, 0)), ("receiver", (0,))]))
            # One word never fills a ring of two, so cap 2 starts at two.
            if cap == 1 or n > 1:
                out.append(S("chan cap %d: 1 sender x%d, 2 receivers" % (cap, n), "chan", chan_mem(cap),
                             [("sender", (0, 1, n, 1)), ("receiver", (0,)), ("receiver", (0,))]))
    if long:
        for cap in (1, 2):
            out.append(S("chan cap %d: 2 senders x1, one closes, 2 receivers" % cap, "chan", chan_mem(cap),
                         [("sender", (0, 1, 1, 1)), ("sender", (0, 2, 1, 0)), ("receiver", (0,)), ("receiver", (0,))]))
    # The timed forms. Their time runs out only by timeouts, so a timeout
    # counts as progress here.
    for t in (1, 2):
        for n in two:
            out.append(S("chan cap 1: timed sender x%d, timed receiver, %d slice(s)" % (n, t), "chan", chan_mem(1),
                         [("timedSender", (0, 1, n, t, scratch(1, 0))), ("timedReceiver", (0, t, scratch(1, 1)))],
                         progress=("n", "t")))
    out.append(S("chan cap 1: timed sender x1, a timed and an untimed receiver, 1 slice", "chan", chan_mem(1),
                 [("timedSender", (0, 1, 1, 1, scratch(1, 0))), ("timedReceiver", (0, 1, scratch(1, 1))),
                  ("receiver", (0,))],
                 progress=("n", "t")))
    out.append(S("chan cap 1: timed sender x2 with no time, 1 receiver", "chan", chan_mem(1),
                 [("timedSender", (0, 1, 2, 0, scratch(1, 0))), ("receiver", (0,))]))
    # The non-blocking forms, and chanClosed.
    for n in two:
        out.append(S("chan cap 1: try-sender x%d, polling receiver" % n, "chan", chan_mem(1),
                     [("trySender", (0, 1, n)), ("tryReceiver", (0,))]))
    # Sends a close refuses, in each form: the receiver closes after one word.
    out.append(S("chan cap 1: sender x3, a receiver that closes", "chan", chan_mem(1),
                 [("sender", (0, 1, 3, 1)), ("closingReceiver", (0,))]))
    out.append(S("chan cap 1: timed sender x3, a receiver that closes, 1 slice", "chan", chan_mem(1),
                 [("timedSender", (0, 1, 3, 1, scratch(1, 0))), ("closingReceiver", (0,))], progress=("n", "t")))
    out.append(S("chan cap 1: try-sender x3, a receiver that closes", "chan", chan_mem(1),
                 [("trySender", (0, 1, 3)), ("closingReceiver", (0,))]))
    # Under --threads every binding's mark is the one pid: a waiter must
    # never take a sibling thread for a dead holder.
    for n in ((1, 2, 3) if long else (1, 2)):
        out.append(S("chan threads cap 1: 1 sender x%d, 2 receivers" % n, "chan", chan_mem(1),
                     [("sender", (0, 1, n, 1)), ("receiver", (0,)), ("receiver", (0,))], pids=[1, 1, 1]))
    out.append(S("chan threads cap 1: 1 sender x2, 1 receiver", "chan", chan_mem(1),
                 [("sender", (0, 1, 2, 1)), ("receiver", (0,))], pids=[1, 1]))
    # A forked binding killed anywhere, the channel's lock held or not
    # (AN-10). Every live binding must still finish. A waiter finds the
    # holder dead when a slice times out after its parent has reaped it,
    # or at once when the waiter is that parent, so timeouts and reaps
    # count as progress. A closer keeps the stream finite when the sender
    # dies before it sends.
    out.extend(chan_kill_scenarios())
    # The mutex. Forked bindings each have a pid; threads share one.
    for lowering, same in (("processes", False), ("threads", True)):
        def pids(k):
            return [1] * k if same else None
        for nb, k in ((2, 1), (2, 2), (2, 3), (3, 1), (3, 2)) + (((3, 3), (4, 1)) if long else ()):
            out.append(S("mutex %s: %d bindings x%d" % (lowering, nb, k), "sync", sync_mem(),
                         [("locker", (0, k))] * nb, pids=pids(nb)))
        out.append(S("mutex %s: stale unlock beside a locker" % lowering, "sync", sync_mem(),
                     [("staleLocker", (0, 1)), ("locker", (0, 2))], pids=pids(2)))
        out.append(S("mutex %s: stale unlock beside 2 lockers" % lowering, "sync", sync_mem(),
                     [("staleLocker", (0, 1)), ("locker", (0, 1)), ("locker", (0, 1))], pids=pids(3)))
        for t in (1, 2):
            out.append(S("mutex %s: timed lock, %d slice(s), beside a locker" % (lowering, t), "sync", sync_mem(),
                         [("timedLocker", (0, t)), ("locker", (0, 1))], pids=pids(2), progress=("n", "t")))
        out.append(S("mutex %s: try-lock beside a locker" % lowering, "sync", sync_mem(),
                     [("tryLocker", (0,)), ("locker", (0, 1))], pids=pids(2)))
    # A forked holder killed anywhere. The waiters find it dead when a
    # slice times out after the parent has reaped it, so timeouts and
    # reaps count as progress here.
    out.append(S("mutex processes: a killable holder, 1 waiter", "sync", sync_mem(),
                 [("locker", (0, 1)), ("locker", (0, 1))], killable=(0,), progress=("n", "t", "r")))
    out.append(S("mutex processes: a killable holder, a lock then a try", "sync", sync_mem(),
                 [("locker", (0, 1)), ("lockThenTry", (0,))], killable=(0,), progress=("n", "t", "r")))
    out.append(S("mutex processes: a killable holder, a waiter and a timed waiter", "sync", sync_mem(),
                 [("locker", (0, 1)), ("locker", (0, 1)), ("timedLocker", (0, 1))], killable=(0,),
                 progress=("n", "t", "r")))
    # The holder is the waiter's own child, which only that waiter could
    # reap and never does: a zombie `kill(pid, 0)` answers for, which only
    # the waiter's `waitid` look sees exit (AN-56).
    out.extend(mutex_parent_scenarios())
    for more in EXTRA_SCENARIOS:
        out.extend(more(long))
    return out


def mutex_parent_scenarios():
    S = Scenario
    kp = ("n", "t", "r")
    return [
        S("mutex processes: a killable holder whose parent waits", "sync", sync_mem(),
          [("locker", (0, 1)), ("locker", (0, 1))], killable=(0,), parents={0: 1}, progress=kp),
        S("mutex processes: a killable holder whose parent makes a timed lock", "sync", sync_mem(),
          [("locker", (0, 1)), ("timedLocker", (0, 2))], killable=(0,), parents={0: 1}, progress=kp),
    ]


def chan_kill_scenarios():
    S = Scenario
    kp = ("n", "t", "r")
    return [
        # AN-10 itself: the timed receive gives up at its first answer that
        # is not a word, which must come, poisoned or timed out.
        an10_scenario(),
        S("chan cap 1: a killable sender, a receiver and a closer", "chan", chan_mem(1),
          [("sender", (0, 1, 1, 0)), ("watchingReceiver", (0,)), ("closer", (0,))], killable=(0,),
          progress=kp, drains=False),
        S("chan cap 1: a killable receiver, a receiver, a sender x2", "chan", chan_mem(1),
          [("receiver", (0,)), ("watchingReceiver", (0,)), ("sender", (0, 1, 2, 1))], killable=(0,),
          progress=kp, drains=False),
        S("chan cap 1: a killable sender whose parent receives, and a closer", "chan", chan_mem(1),
          [("sender", (0, 1, 1, 0)), ("watchingReceiver", (0,)), ("closer", (0,))], killable=(0,),
          parents={0: 1}, progress=kp, drains=False),
        # Every other call's poisoned answer: a timed send, the two tries
        # and chanClosed, each meeting a dead receiver's or sender's lock.
        S("chan cap 1: a killable receiver, a timed sender x2, 1 slice", "chan", chan_mem(1),
          [("receiver", (0,)), ("timedSender", (0, 1, 2, 1, scratch(1, 1)))], killable=(0,),
          progress=kp, drains=False),
        S("chan cap 1: a killable sender, a polling receiver and a closer", "chan", chan_mem(1),
          [("sender", (0, 1, 1, 0)), ("tryReceiver", (0,)), ("closer", (0,))], killable=(0,),
          progress=kp, drains=False),
        S("chan cap 1: a killable receiver, a try-sender x2, a receiver", "chan", chan_mem(1),
          [("receiver", (0,)), ("trySender", (0, 1, 2)), ("watchingReceiver", (0,))], killable=(0,),
          progress=kp, drains=False),
        # The receive gives up at its first answer that is not a word, as
        # AN-10's does: nobody else would close the channel.
        S("chan cap 1: a killable timed sender x2, a timed receiver, 1 slice", "chan", chan_mem(1),
          [("timedSender", (0, 1, 2, 1, scratch(1, 0))), ("timedReceiverOnce", (0, 1, scratch(1, 1)))],
          killable=(0,), progress=kp, drains=False),
    ]


# AN-10: a sender killed holding the channel's lock, beside a timed
# receive that gives up at its first answer that is not a word. The lock
# word names its holder, so a waiter can find that holder dead: the
# scenario must be clean, and the planted regressions below must find it
# stuck.
def an10_scenario():
    return Scenario("chan cap 1: a killable sender, a timed receiver (AN-10)", "chan", chan_mem(1),
                    [("sender", (0, 1, 1, 1)), ("timedReceiverOnce", (0, 1, scratch(1, 1)))], killable=(0,),
                    progress=("n", "t", "r"), drains=False)


# ---------------------------------------------------------------------
# The machine.
# ---------------------------------------------------------------------

class Ctx:
    """One transition's working copy of a state."""
    __slots__ = ("mem", "bs", "procs", "ghost", "work", "desc", "woken")

    def copy(self):
        c = Ctx()
        c.woken = list(self.woken)
        c.mem = list(self.mem)
        c.bs = list(self.bs)
        c.procs = list(self.procs)
        c.ghost = dict(self.ghost)
        c.work = {b: [w[0], [[f[0], f[1], list(f[2])] for f in w[1]], w[2]] for b, w in self.work.items()}
        c.desc = None if self.desc is None else list(self.desc)
        return c

    def thaw(self, b):
        w = self.work.get(b)
        if w is None:
            st, frames, sleep = self.bs[b]
            w = [st, [[f, pc, list(L)] for f, pc, L in frames], sleep]
            self.work[b] = w
        return w


class Model:
    def __init__(self, sc, codes):
        self.sc, self.codes = sc, codes
        self.n = len(sc.bindings)
        self.gkeys = sorted(sc.ghost0().keys())
        self.hold_ix = self.gkeys.index("hold")
        self.pool = {}
        self.reached = set()
        # Bindings that run the same driver with the same arguments, the
        # same pid and the same exposure to kills are interchangeable: a
        # state and the same state with two of them swapped have the same
        # futures. Each state is stored once, with each group sorted.
        groups = collections.defaultdict(list)
        for b, (fn, args) in enumerate(sc.bindings):
            groups[(fn, args, sc.pids[b], b in sc.killable)].append(b)
        self.groups = [g for g in groups.values() if len(g) > 1]

    def canon(self, s):
        if not self.groups:
            return s
        bs, procs = s[1], s[2]
        perm = list(range(self.n))
        moved = False
        for g in self.groups:
            order = sorted(g, key=lambda i: (bs[i], procs[i] if procs else 0))
            for dst, src in zip(g, order):
                perm[dst] = src
                if dst != src:
                    moved = True
        if not moved:
            return s
        inv = [0] * self.n
        for dst, src in enumerate(perm):
            inv[src] = dst
        ghost = list(s[3])
        ghost[self.hold_ix] = frozenset(inv[x] for x in ghost[self.hold_ix])
        return (s[0], tuple(bs[perm[i]] for i in range(self.n)),
                tuple(procs[perm[i]] for i in range(self.n)) if procs else procs, tuple(ghost))

    # ---- states -----------------------------------------------------------
    def freeze(self, c):
        """The context as a state. Most states share most of their parts
        with others, so each part is interned: one object per distinct
        binding state, memory and ghost, however many states hold it."""
        pool = self.pool
        bs = c.bs
        codes = self.codes
        for b, w in c.work.items():
            frames = w[1]
            top = len(frames) - 1
            fs = []
            for k, (f, pc, L) in enumerate(frames):
                code = codes[f]
                keep = code.keep_top[pc] if k == top else code.keep_call[pc]
                z = [0] * len(L)
                for i in keep:
                    z[i] = L[i]
                fs.append((f, pc, tuple(z)))
            t = (w[0], tuple(fs), w[2])
            bs[b] = pool.setdefault(t, t)
        m = tuple(c.mem)
        g = tuple(c.ghost[k] for k in self.gkeys)
        return (pool.setdefault(m, m), tuple(bs), tuple(c.procs), pool.setdefault(g, g))

    def ctx(self, s, describe=False):
        c = Ctx()
        c.mem = list(s[0])
        c.bs = list(s[1])
        c.procs = list(s[2])
        c.ghost = dict(zip(self.gkeys, s[3]))
        c.work = {}
        c.desc = [] if describe else None
        c.woken = []
        return c

    def initial(self):
        sc = self.sc
        c = Ctx()
        c.mem = list(sc.mem0)
        c.bs = []
        for fn, args in sc.bindings:
            code = self.codes[fn]
            c.bs.append(("R", ((fn, 0, tuple(args) + (0,) * code.nlocs),), None))
        c.procs = ["A"] * self.n if sc.procs else []
        for b in sc.unspawned:
            c.bs[b] = ("N",) + c.bs[b][1:]
            c.procs[b] = "-"
        c.ghost = sc.ghost0()
        c.work = {}
        c.desc = None
        c.woken = []
        outs = [c]
        for b in range(self.n):
            if b in sc.unspawned:
                continue
            nxt = []
            for cc in outs:
                nxt.extend(self.run(cc, b, False))
            outs = nxt
        if len(outs) != 1:
            raise ValueError("the initial state branched")
        return self.freeze(outs[0])

    # ---- running one binding ------------------------------------------------
    def run(self, ctx, b, allow, stops=VISIBLE):
        """Run binding b forward: local instructions, the plain accesses to
        lock-protected words, and at most one visible step when `allow`.
        Answers every context it can end in (a `choose` branches). Replay
        passes `stops` with the plain accesses in it, to take them one at
        a time."""
        out = []
        stack = [(ctx, allow)]
        codes = self.codes
        reached = self.reached.add
        while stack:
            c, allow = stack.pop()
            w = c.thaw(b)
            frames = w[1]
            while True:
                if not frames:
                    w[0] = "D"
                    if c.procs:
                        c.procs[b] = "Z"
                    out.append(c)
                    break
                fr = frames[-1]
                code = codes[fr[0]]
                ins = code.ins[fr[1]]
                op = ins[0]
                L = fr[2]
                reached((fr[0], fr[1]))
                if op in stops:
                    if not allow:
                        out.append(c)
                        break
                    allow = False
                if op == "set":
                    L[ins[1]] = ins[2](*L)
                    fr[1] += 1
                elif op == "if":
                    fr[1] = fr[1] + 1 if ins[1](*L) else ins[2]
                elif op == "goto":
                    fr[1] = ins[1]
                elif op == "call":
                    callee = codes[ins[2]]
                    args = tuple(f(*L) for f in ins[3])
                    frames.append([ins[2], 0, list(args) + [0] * callee.nlocs])
                    if c.desc is not None:
                        c.desc.append(("call", b, code, ins, args))
                elif op == "ret":
                    val = ins[1](*L)
                    frames.pop()
                    if not frames and b in self.sc.exitword:
                        c.mem[self.sc.exitword[b]] = val
                    if frames:
                        caller = frames[-1]
                        cins = codes[caller[0]].ins[caller[1]]
                        if cins[1] is not None:
                            caller[2][cins[1]] = val
                        caller[1] += 1
                elif op in ("aload", "uload", "pload"):
                    a = ins[2](*L)
                    L[ins[1]] = c.mem[a]
                    fr[1] += 1
                    self._say(c, b, code, ins, a, c.mem[a])
                elif op in ("astore", "pstore"):
                    a = ins[1](*L)
                    v = ins[2](*L)
                    c.mem[a] = v
                    fr[1] += 1
                    self._say(c, b, code, ins, a, v)
                elif op == "aadd":
                    a = ins[2](*L)
                    old = c.mem[a]
                    c.mem[a] = old + ins[3](*L)
                    if ins[1] is not None:
                        L[ins[1]] = old
                    fr[1] += 1
                    self._say(c, b, code, ins, a, old)
                elif op == "acas":
                    a = ins[2](*L)
                    found = c.mem[a]
                    if found == ins[3](*L):
                        c.mem[a] = ins[4](*L)
                    if ins[1] is not None:
                        L[ins[1]] = found
                    fr[1] += 1
                    self._say(c, b, code, ins, a, found)
                elif op == "wait":
                    a = ins[2](*L)
                    e = ins[3](*L)
                    if c.mem[a] != e:
                        if ins[1] is not None:
                            L[ins[1]] = 2
                        fr[1] += 1
                        self._say(c, b, code, ins, a, "the word differs: returns")
                    else:
                        w[0] = "S"
                        w[2] = a
                        self._say(c, b, code, ins, a, "sleeps (word %d holds %d)" % (a, e))
                        out.append(c)
                        break
                elif op == "wake":
                    a = ins[1](*L)
                    woke = []
                    for o in range(self.n):
                        if o == b:
                            continue
                        st = c.work[o][0] if o in c.work else c.bs[o][0]
                        sl = c.work[o][2] if o in c.work else c.bs[o][2]
                        if st == "S" and sl == a:
                            self._resume(c, o, 0)
                            c.woken.append(o)
                            woke.append(o)
                    fr[1] += 1
                    self._say(c, b, code, ins, a,
                              "wakes " + (", ".join("B%d" % (o + 1) for o in woke) if woke else "nobody"))
                elif op == "pid":
                    L[ins[1]] = self.sc.pids[b]
                    fr[1] += 1
                elif op == "kill0":
                    pid = ins[2](*L)
                    t = self.sc.pids.index(pid) if pid in self.sc.pids else None
                    gone = t is not None and c.procs and c.procs[t] == "X"
                    L[ins[1]] = 3 if gone else 0
                    fr[1] += 1
                    self._say(c, b, code, ins, pid, "ESRCH" if gone else "alive")
                elif op == "look":
                    pid = ins[2](*L)
                    t = self.sc.pids.index(pid) if pid in self.sc.pids else None
                    ended = (t is not None and c.procs and c.procs[t] == "Z"
                             and self.sc.parents.get(t) == b)
                    L[ins[1]] = (1 if ended else 0) if self.sc.lookable else -1
                    fr[1] += 1
                    self._say(c, b, code, ins, pid, ("its child has exited" if ended else "not an exited child of it")
                              if self.sc.lookable else "no look exists: Err")
                elif op == "clock":
                    L[ins[1]] = c.mem[self.sc.clock]
                    fr[1] += 1
                    self._say(c, b, code, ins, self.sc.clock, "reads %d" % c.mem[self.sc.clock])
                elif op == "spawn":
                    arg = ins[2](*L)
                    k = ins[3](*L)
                    if c.procs[k] != "-":
                        raise Violation("spawn", "B%d spawned B%d twice" % (b + 1, k + 1))
                    wk = c.thaw(k)
                    kf = wk[1][0]
                    kf[2][codes[kf[0]].vars.index("arg")] = arg
                    wk[0] = "R"
                    c.procs[k] = "A"
                    c.woken.append(k)
                    L[ins[1]] = self.sc.pids[k]
                    fr[1] += 1
                    self._say(c, b, code, ins, arg, "starts B%d" % (k + 1))
                elif op == "join":
                    pid = ins[2](*L)
                    k = self.sc.pids.index(pid)
                    if c.procs[k] == "X":
                        raise Violation("joined twice", "B%d joined B%d, which was already reaped" % (b + 1, k + 1))
                    if c.procs[k] == "Z":
                        c.procs[k] = "X"
                        L[ins[1]] = c.mem[self.sc.exitword[k]]
                        fr[1] += 1
                        self._say(c, b, code, ins, pid, "reaps B%d: status %d" % (k + 1, L[ins[1]]))
                    else:
                        w[0] = "S"
                        w[2] = -100 - k
                        self._say(c, b, code, ins, pid, "waits for B%d to exit" % (k + 1))
                        out.append(c)
                        break
                elif op == "kill9":
                    pid = ins[2](*L)
                    k = self.sc.pids.index(pid)
                    if c.procs[k] == "A":
                        wk = c.thaw(k)
                        wk[0], wk[1], wk[2] = "K", [], None
                        c.procs[k] = "Z"
                        c.mem[self.sc.exitword[k]] = 137
                        self.g_tKilled(c, b, k)
                        L[ins[1]] = 0
                        said = "B%d dies (137)" % (k + 1)
                    else:
                        L[ins[1]] = 3 if c.procs[k] == "X" else 0
                        said = "B%d has already exited" % (k + 1)
                    fr[1] += 1
                    self._say(c, b, code, ins, pid, said)
                elif op == "sleepuntil":
                    a = ins[2](*L)
                    e = ins[3](*L)
                    if c.mem[a] != e:
                        L[ins[1]] = 2
                        fr[1] += 1
                        self._say(c, b, code, ins, a, "the word differs: returns")
                    else:
                        w[0] = "S"
                        w[2] = a
                        self._say(c, b, code, ins, a, "sleeps until the clock reads %d (word %d holds %d)"
                                  % (ins[4](*L), a, e))
                        out.append(c)
                        break
                elif op == "block":
                    w[0] = "S"
                    w[2] = -1
                    self._say(c, b, code, ins, -1, "blocks for ever")
                    out.append(c)
                    break
                elif op == "choose":
                    alts = ins[2](*L)
                    fr[1] += 1
                    for alt in alts[1:]:
                        c2 = c.copy()
                        c2.work[b][1][-1][2][ins[1]] = alt
                        stack.append((c2, allow))
                    L[ins[1]] = alts[0]
                elif op == "ghost":
                    getattr(self, "g_" + ins[1])(c, b, *[f(*L) for f in ins[2]])
                    fr[1] += 1
                elif op == "assert":
                    if not ins[1](*L):
                        raise Violation("assertion", "B%d: %s" % (b + 1, ins[2]))
                    fr[1] += 1
                else:
                    raise ValueError(op)
        return out

    def settle(self, ctxs):
        """Run every binding a transition resumed up to its next step on a
        shared word: what it does in between no other binding can see."""
        out = []
        work = list(ctxs)
        while work:
            c = work.pop()
            if not c.woken:
                out.append(c)
                continue
            o = c.woken.pop()
            work.extend(self.run(c, o, False))
        return out

    def _say(self, c, b, code, ins, a, result):
        if c.desc is not None:
            c.desc.append(("op", b, code, ins, a, result))

    def _resume(self, c, o, answer):
        w = c.thaw(o)
        w[0] = "R"
        w[2] = None
        fr = w[1][-1]
        ins = self.codes[fr[0]].ins[fr[1]]
        if ins[1] is not None:
            fr[2][ins[1]] = answer
        fr[1] += 1

    # ---- the ghost hooks: the checks ---------------------------------------
    def g_acquire(self, c, b):
        h = c.ghost["hold"]
        if h:
            raise Violation("mutual exclusion", "B%d took the lock while B%d holds it" % (b + 1, min(h) + 1))
        c.ghost["hold"] = frozenset((b,))
        if self.sc.kind == "sync" and c.mem[3] == 1:
            raise Violation("poisoned", "B%d took a poisoned mutex" % (b + 1))

    def g_release(self, c, b):
        h = c.ghost["hold"]
        if b not in h:
            raise Violation("unearned unlock", "B%d released a lock %s" % (
                b + 1, "B%d holds" % (min(h) + 1) if h else "nobody holds"))
        c.ghost["hold"] = h - {b}

    def g_accept(self, c, b, v):
        if c.mem[6] == 1:
            raise Violation("send after close", "B%d's word %d went into a closed channel" % (b + 1, v))
        acc = c.ghost["acc"]
        mine = [x for x in acc if x // 1000 == v // 1000]
        if mine and mine[-1] > v:
            raise Violation("FIFO per sender", "word %d accepted after %d" % (v, mine[-1]))
        c.ghost["acc"] = acc + (v,)

    def g_take(self, c, b, v):
        acc, log = c.ghost["acc"], c.ghost["log"]
        want = acc[len(log)] if len(log) < len(acc) else None
        if v != want:
            raise Violation("exactly once", "B%d received %d, but the oldest word not yet received is %s" % (
                b + 1, v, want if want is not None else "none"))
        c.ghost["log"] = log + (v,)

    def g_answered(self, c, b, v, sent):
        acc = c.ghost["acc"]
        if sent and v not in acc:
            raise Violation("exactly once", "B%d's send of %d answered True and the word is not in the ring" % (b + 1, v))
        if not sent:
            if v in acc:
                raise Violation("exactly once", "B%d's send of %d was refused but the word went in" % (b + 1, v))
            c.ghost["ref"] = c.ghost["ref"] | {v}

    def g_close(self, c, b):
        pass

    def g_eos(self, c, b):
        m = c.mem
        if m[3] != m[4] or m[6] != 1:
            raise Violation("end of stream", "B%d answered the end of the stream with head %d, tail %d, closed %d"
                            % (b + 1, m[3], m[4], m[6]))
        if len(c.ghost["log"]) != len(c.ghost["acc"]):
            raise Violation("end of stream", "B%d answered the end of the stream with words unreceived" % (b + 1))
        c.ghost["eos"] = c.ghost["eos"] + 1

    def g_drained(self, c, b):
        if c.mem[0] == POISON:
            return
        if len(c.ghost["log"]) != len(c.ghost["acc"]) or c.mem[6] != 1:
            raise Violation("end of stream", "B%d stopped polling with words unreceived" % (b + 1))
        c.ghost["eos"] = c.ghost["eos"] + 1

    def g_recvTimedOut(self, c, b):
        m = c.mem
        if m[3] != m[4] or m[6] != 0:
            raise Violation("timed out", "B%d's receive timed out with head %d, tail %d, closed %d"
                            % (b + 1, m[3], m[4], m[6]))

    def g_poison(self, c, b):
        named = c.mem[0] // 4
        t = self.sc.pids.index(named) if named in self.sc.pids else None
        if t is None or not c.procs or c.procs[t] == "A":
            raise Violation("false poisoning", "B%d poisoned the mutex while word 0 names %s" % (
                b + 1, "pid %d, which is alive" % named if t is not None else "no holder"))

    def g_ownerDead(self, c, b):
        if not c.ghost["dead"]:
            raise Violation("false poisoning", "B%d was told the holder died, and no holder died holding it" % (b + 1))

    def g_chanPoison(self, c, b, w):
        """A channel is poisoned only from the mark of a holder that died
        holding its lock."""
        named = w // 4
        t = self.sc.pids.index(named) if named in self.sc.pids else None
        if t is None or not c.procs or c.procs[t] == "A" or t not in c.ghost["hold"]:
            raise Violation("false poisoning", "B%d poisoned the channel from mark %d, and %s" % (
                b + 1, w, "no binding died holding its lock" if t is None or t not in c.ghost["hold"]
                else "B%d is alive" % (t + 1)))

    def g_sawPoison(self, c, b):
        if c.mem[0] != POISON:
            raise Violation("false poisoning", "B%d answered as poisoned, and the lock word is %d" % (b + 1, c.mem[0]))

    def g_poisonedIs(self, c, b, p):
        if p != (1 if c.mem[0] == POISON else 0):
            raise Violation("false poisoning", "B%d's chanPoisoned answered %d with the lock word %d" % (b + 1, p, c.mem[0]))
        if not p and c.mem[6] != 1:
            raise Violation("end of stream", "B%d's stream ended, and the channel is neither closed nor poisoned" % (b + 1))

    def g_lockTimedOut(self, c, b):
        if b in c.ghost["hold"]:
            raise Violation("timed out", "B%d's timed lock ran out while it holds the lock" % (b + 1))

    def g_lockFailed(self, c, b, g):
        if b in c.ghost["hold"]:
            raise Violation("timed out", "B%d's timed lock failed while it holds the lock" % (b + 1))
        if g == OWNER_DEAD and not c.ghost["dead"]:
            raise Violation("false poisoning", "B%d was told the holder died, and none did" % (b + 1))

    def g_staleAnswer(self, c, b, r):
        if r != NOT_HELD:
            raise Violation("unearned unlock", "B%d's stale unlock answered %d, not syncNotHeld" % (b + 1, r))

    # ---- transitions ------------------------------------------------------------
    def successors(self, s, describe=False):
        """Every transition out of `s`: (class, binding, state or
        Violation, description). Class 'n' is a protocol step, 's' a
        spurious wakeup, 't' a timeout, 'k' a kill and 'r' a reap."""
        out = []
        sc = self.sc
        bs = s[1]
        for b in range(self.n):
            st = bs[b][0]
            if st == "R":
                c = self.ctx(s, describe)
                try:
                    for cc in self.settle(self.run(c, b, True)):
                        out.append(("n", b, self.freeze(cc), cc.desc))
                except Violation as v:
                    out.append(("n", b, v, c.desc))
            elif st == "S" and self.codes[bs[b][1][-1][0]].ins[bs[b][1][-1][1]][0] in ("sleepuntil", "join", "block"):
                out.extend(self.task_successors(s, b, describe))
            elif st == "S":
                fr = bs[b][1][-1]
                timed = self.codes[fr[0]].ins[fr[1]][4]
                for cls, answer in (("s", 0), ("t", 1)) if timed else (("s", 0),):
                    c = self.ctx(s, describe)
                    self._resume(c, b, answer)
                    c.woken.append(b)
                    if describe:
                        c.desc.append(("env", b, "spurious wakeup" if cls == "s" else "the slice times out"))
                    try:
                        for cc in self.settle([c]):
                            out.append((cls, b, self.freeze(cc), cc.desc))
                    except Violation as v:
                        out.append((cls, b, v, c.desc))
            if sc.procs:
                pr = s[2][b]
                if b in sc.killable and pr == "A" and st in ("R", "S"):
                    c = self.ctx(s, describe)
                    w = c.thaw(b)
                    w[0], w[1], w[2] = "K", [], None
                    c.procs[b] = "Z"
                    if b in c.ghost["hold"]:
                        c.ghost["dead"] = 1
                    if describe:
                        c.desc.append(("env", b, "is killed (SIGKILL)" + (" holding the lock" if b in c.ghost["hold"] else "")))
                    out.append(("k", b, self.freeze(c), c.desc))
                if pr == "Z" and b not in sc.parents:
                    c = self.ctx(s, describe)
                    c.procs[b] = "X"
                    if describe:
                        c.desc.append(("env", b, "is reaped by its parent"))
                    out.append(("r", b, self.freeze(c), c.desc))
        if sc.clock is not None:
            out.extend(self.tick(s, describe))
        return out

    # The task pool's environment: a sleep that the clock ends, a join
    # that a child's exit ends, and the clock itself.
    def task_successors(self, s, b, describe):
        out = []
        fr = s[1][b][1][-1]
        ins = self.codes[fr[0]].ins[fr[1]]
        op = ins[0]
        if op == "sleepuntil":
            at = ins[4](*fr[2])
            moves = [("s", 0, "spurious wakeup")]
            if s[0][self.sc.clock] >= at:
                moves.append(("t", 1, "the clock reaches %d: the wait times out" % at))
            for cls, answer, what in moves:
                c = self.ctx(s, describe)
                self._resume(c, b, answer)
                c.woken.append(b)
                if describe:
                    c.desc.append(("env", b, what))
                try:
                    for cc in self.settle([c]):
                        out.append((cls, b, self.freeze(cc), cc.desc))
                except Violation as v:
                    out.append((cls, b, v, c.desc))
        elif op == "join":
            k = self.sc.pids.index(ins[2](*fr[2]))
            if s[2][k] == "Z":
                c = self.ctx(s, describe)
                c.procs[k] = "X"
                self._resume(c, b, c.mem[self.sc.exitword[k]])
                c.woken.append(b)
                if describe:
                    c.desc.append(("env", b, "B%d has exited: the join reaps it, status %d"
                                   % (k + 1, c.mem[self.sc.exitword[k]])))
                try:
                    for cc in self.settle([c]):
                        out.append(("n", b, self.freeze(cc), cc.desc))
                except Violation as v:
                    out.append(("n", b, v, c.desc))
        return out

    def tick(self, s, describe):
        """One unit of time, while the pool sleeps or waits in a join and no
        other binding can step, up to the scenario's horizon."""
        sc = self.sc
        now = s[0][sc.clock]
        st, frames, _ = s[1][0]
        if now >= sc.horizon or st != "S":
            return []
        # Maximal progress: a step no binding waits on takes no time, so
        # the clock moves only once every other binding is asleep, blocked,
        # finished or not started.
        if any(bb[0] == "R" for bb in s[1][1:]):
            return []
        fr = frames[-1]
        ins = self.codes[fr[0]].ins[fr[1]]
        if ins[0] == "sleepuntil":
            if now >= ins[4](*fr[2]):
                return []
        elif ins[0] != "join":
            return []
        c = self.ctx(s, describe)
        if describe:
            c.desc.append(("env", 0, "the clock moves to %d" % (now + 1)))
        try:
            if ins[0] == "sleepuntil":
                self.g_tAsleepAt(c, now, frames)
            c.mem[sc.clock] = now + 1
            return [("c", 0, self.freeze(c), c.desc)]
        except Violation as v:
            return [("c", 0, v, c.desc)]

    def terminal(self, s):
        return all(b[0] in ("D", "K", "N") for b in s[1])

    def final_check(self, s):
        g = dict(zip(self.gkeys, s[3]))
        if self.sc.kind == "chan" and self.sc.drains:
            if set(g["log"]) != set(g["acc"]):
                return Violation("exactly once", "every binding finished with words %s accepted and %s received"
                                 % (list(g["acc"]), list(g["log"])))
        if g["hold"] and not g.get("dead"):
            return Violation("mutual exclusion", "every binding finished and B%d still holds the lock" % (min(g["hold"]) + 1))
        return None

    # ---- describing a state -------------------------------------------------------
    def where(self, s, b):
        st, frames, sleep = s[1][b]
        names = " > ".join(f for f, _, _ in frames)
        if st == "D":
            return "finished"
        if st == "K":
            return "killed"
        if st == "N":
            return "not started"
        if st == "S":
            fr = frames[-1]
            code = self.codes[fr[0]]
            ins = code.ins[fr[1]]
            if ins[0] == "join":
                return "waiting in %s to reap pid %d" % (names, ins[2](*fr[2]))
            if ins[0] == "block":
                return "blocked for ever in %s" % names
            if ins[0] == "sleepuntil":
                return "asleep in %s, on word %d expecting %d (it holds %d), until the clock reads %d (it reads %d)" % (
                    names, sleep, ins[3](*fr[2]), s[0][sleep], ins[4](*fr[2]), s[0][self.sc.clock])
            e = ins[3](*fr[2])
            return "asleep in %s, on word %d expecting %d (it holds %d)" % (names, sleep, e, s[0][sleep])
        return "runnable in " + names

    def condition(self, s, b):
        """Whether the thing sleeping binding b waits for is already there."""
        frames = s[1][b][1]
        names = [f for f, _, _ in frames]
        m = s[0]
        if self.sc.kind == "sync":
            return m[0] == 0 or m[3] == 1, "the lock word is 0 or the mutex is poisoned"
        if "chanLock" in names:
            return m[0] in (0, POISON), "the lock word is 0 or poisoned"
        if any(n in names for n in ("chanSend", "chanSendTimeout")):
            return (m[4] - m[3] < m[5]) or m[6] == 1 or m[0] == POISON, "the ring has room, or it is closed or poisoned"
        return (m[3] < m[4]) or m[6] == 1 or m[0] == POISON, "the ring has a word, or it is closed or poisoned"


def fmt_desc(model, desc):
    """A transition's description as lines."""
    lines = []
    for d in desc or ():
        if d[0] == "env":
            lines.append("B%d %s" % (d[1] + 1, d[2]))
        elif d[0] == "op":
            _, b, code, ins, a, result = d
            sp = ins[-1]
            if sp is None:
                sp = "(%s word %s)" % (ins[0], a)
            where = "%s %s" % (code.src[0], code.src[1]) if code.src else code.name
            if ins[0] in ("pload", "pstore"):
                lines.append("B%d   %s: %s -> %s" % (b + 1, where, sp.replace("\n", " "), result))
            else:
                lines.append("B%d %s: %s -> %s" % (b + 1, where, sp.replace("\n", " "), result))
    return lines


# ---------------------------------------------------------------------
# The explorer.
# ---------------------------------------------------------------------

class Finding:
    def __init__(self, kind, msg, path, detail=()):
        self.kind, self.msg, self.path, self.detail = kind, msg, path, detail


class Result:
    def __init__(self, sc):
        self.sc = sc
        self.states = 0
        self.transitions = 0
        self.terminal = 0
        self.depth = 0
        self.finding = None
        self.sleeping = 0
        self.reached = set()


def explore(model, limit=5_000_000):
    sc = model.sc
    res = Result(sc)
    canon = model.canon
    init = canon(model.initial())
    ids = {init: 0}
    states = [init]
    parent = array.array("q", [-1])
    depth = array.array("l", [0])
    esrc = array.array("q")   # progress edges: esrc[k] -> edst[k]
    edst = array.array("q")
    terminals = []
    q = collections.deque([0])
    prog = sc.progress
    stuck = []
    while q:
        i = q.popleft()
        s = states[i]
        succ = model.successors(s)
        res.transitions += len(succ)
        if any(b[0] == "S" for b in s[1]):
            res.sleeping += 1
        if model.terminal(s):
            terminals.append(i)
            v = model.final_check(s)
            if v is not None:
                res.finding = Finding(v.kind, v.msg, path_to(model, states, parent, i))
                break
        has_progress = False
        for cls, b, t, _ in succ:
            if isinstance(t, Violation):
                path, raw = path_to(model, states, parent, i, want_raw=True)
                res.finding = Finding(t.kind, t.msg, path + [failing_step(model, raw, b, t)])
                break
            t = canon(t)
            j = ids.get(t)
            if j is None:
                j = len(states)
                ids[t] = j
                states.append(t)
                parent.append(i)
                depth.append(depth[i] + 1)
                if len(states) > limit:
                    res.finding = Finding("too large", "more than %d states: these bounds are more than the "
                                          "explorer holds, so the scenario was not explored" % limit, [])
                    break
                q.append(j)
            if cls in prog:
                has_progress = True
                esrc.append(i)
                edst.append(j)
        if res.finding:
            break
        if not has_progress and not model.terminal(s):
            stuck.append(i)
    res.states = len(states)
    res.depth = max(depth)
    res.terminal = len(terminals)
    res.reached = set(model.reached)
    if res.finding:
        return res
    # Liveness: which states can still reach an end, by progress steps.
    # The edges are turned round into a table of predecessors first.
    n = len(states)
    start = array.array("q", [0]) * (n + 1)
    for j in edst:
        start[j + 1] += 1
    for j in range(n):
        start[j + 1] += start[j]
    fill = array.array("q", start[:n])
    pred = array.array("q", [0]) * len(edst)
    for k in range(len(edst)):
        j = edst[k]
        pred[fill[j]] = esrc[k]
        fill[j] += 1
    del fill, esrc, edst
    can = bytearray(n)
    work = list(terminals)
    for t in terminals:
        can[t] = 1
    while work:
        j = work.pop()
        for k in range(start[j], start[j + 1]):
            p = pred[k]
            if not can[p]:
                can[p] = 1
                work.append(p)
    bad = next((i for i in range(len(states)) if not can[i]), None)
    if bad is not None:
        # The shallowest stuck state, if there is one; else the shallowest trap.
        stuck_bad = [i for i in stuck if not can[i]]
        i = min(stuck_bad) if stuck_bad else bad
        path, s = path_to(model, states, parent, i, want_raw=True)
        detail = []
        lost = []
        for b in range(model.n):
            detail.append("B%d %s" % (b + 1, model.where(s, b)))
            if s[1][b][0] == "S":
                holds, what = model.condition(s, b)
                detail[-1] += "; %s: %s" % (what, "yes" if holds else "no")
                if holds:
                    lost.append(b)
        if stuck_bad:
            env = sorted({c for c, _, _, _ in model.successors(s)} - prog)
            tail = " (only %s remain)" % ", ".join({"s": "spurious wakeups", "t": "timeouts", "k": "kills",
                                                     "r": "reaps"}[c] for c in env) if env else ""
            if lost:
                kind = "lost wakeup"
                msg = "%s sleep%s though %s, and no binding can take a step%s" % (
                    ", ".join("B%d" % (b + 1) for b in lost), "s" if len(lost) == 1 else "",
                    model.condition(s, lost[0])[1], tail)
            else:
                kind = "deadlock"
                msg = "every live binding is blocked and none can take a step%s" % tail
        else:
            kind = "livelock"
            msg = "steps remain, and none of them leads to every binding finishing"
        res.finding = Finding(kind, msg, path, detail)
    return res


def path_to(model, states, parent, i, want_raw=False):
    """The steps from the initial state to state i. States are stored with
    interchangeable bindings sorted, so the walk follows the raw states and
    the bindings keep their numbers from the first step to the last."""
    chain = []
    while i > 0:
        chain.append(i)
        i = parent[i]
    chain.reverse()
    steps = []
    prev = model.initial()
    for j in chain:
        t = states[j]
        for cls, b, u, desc in model.successors(prev, describe=True):
            if not isinstance(u, Violation) and model.canon(u) == t:
                steps.append(fmt_desc(model, desc))
                prev = u
                break
        else:
            steps.append(["(a step the explorer could not describe)"])
            break
    return (steps, prev) if want_raw else steps


def failing_step(model, s, b, v):
    for cls, bb, u, desc in model.successors(s, describe=True):
        if bb == b and isinstance(u, Violation):
            return fmt_desc(model, desc) + ["!! " + v.msg]
    return ["!! " + v.msg]


def print_finding(res, out=sys.stdout):
    f = res.finding
    out.write("  %s: %s\n" % (f.kind, f.msg))
    out.write("  schedule (%d steps):\n" % len(f.path))
    for k, step in enumerate(f.path, 1):
        for n, line in enumerate(step):
            out.write("   %3s %s\n" % ("%d." % k if n == 0 else "", line))
    for line in f.detail:
        out.write("   state: %s\n" % line)


# ---------------------------------------------------------------------
# Planted defects: each is a change to the transcription, the kind of
# finding it must produce, and the scenarios it is explored on.
# ---------------------------------------------------------------------

def replace(fns, name, old, new, count=1):
    params, locs, src, body = fns[name]
    body = list(body)
    hits = [i for i in range(len(body) - len(old) + 1) if tuple(body[i:i + len(old)]) == tuple(old)]
    if len(hits) != count:
        raise SystemExit("defect seam in %s matched %d time(s), wanted %d: %r" % (name, len(hits), count, old[0]))
    for i in reversed(hits):
        body[i:i + len(old)] = new
    fns[name] = (params, locs, src, tuple(body))


def add_locals(fns, name, extra):
    params, locs, src, body = fns[name]
    fns[name] = (params, locs + tuple(extra), src, body)


PARK = ("call", "seen", "chanPark", ["ch"], "(chanPark ch)")
UNLOCK = ("call", None, "chanUnlock", ["ch", "me"], "(chanUnlock ch me)")
SLICE = ("set", "slice", "min(left, 1)", "(chanSlice b)")
NOTIFY = ("call", None, "chanNotify", ["ch"], "(chanNotify ch)")
LOCK = ("call", "g", "chanLock", ["ch", "me", "0", "0"], "(chanLock ch me 0 0)")
TLOCK = ("call", "g", "chanLock", ["ch", "me", "b", "1"], "(chanLock ch me b 1)")


def d_park_after_release(fns):
    for f in ("chanSend", "chanRecv"):
        replace(fns, f, [PARK, UNLOCK], [UNLOCK, PARK])
    for f in ("chanSendTimeout", "chanRecvTimeout"):
        replace(fns, f, [PARK, SLICE, UNLOCK], [SLICE, UNLOCK, PARK])


def d_announce_after_release(fns):
    F("chanParkRead", ["ch"], ["seen"], None, [("aload", "seen", "ch + 1"), ("ret", "seen")])
    F("chanParkAnnounce", ["ch"], [], None, [("aadd", None, "ch + 2", "1"), ("ret", "0")])
    fns["chanParkRead"] = FUNCTIONS.pop("chanParkRead")
    fns["chanParkAnnounce"] = FUNCTIONS.pop("chanParkAnnounce")
    read = ("call", "seen", "chanParkRead", ["ch"])
    ann = ("call", None, "chanParkAnnounce", ["ch"])
    for f in ("chanSend", "chanRecv"):
        replace(fns, f, [PARK, UNLOCK], [read, UNLOCK, ann])
    for f in ("chanSendTimeout", "chanRecvTimeout"):
        replace(fns, f, [PARK, SLICE, UNLOCK], [read, SLICE, UNLOCK, ann])


def d_notify_before_change(fns):
    F("chanPeek", ["ch"], ["w"], None, [("aload", "w", "ch + 2"), ("ret", "w")])
    F("chanNotifyIf", ["ch", "w"], [], None, [
        ("if", "w > 0", "none"), ("call", None, "sysWakeWord", ["ch + 1"]), ("L", "none"), ("ret", "0")])
    fns["chanPeek"] = FUNCTIONS.pop("chanPeek")
    fns["chanNotifyIf"] = FUNCTIONS.pop("chanNotifyIf")
    for f in ("chanSend", "chanRecv", "chanSendTimeout", "chanRecvTimeout", "chanClose", "chanTrySend", "chanTryRecv"):
        add_locals(fns, f, ["early"])
        lock = TLOCK if f.endswith("Timeout") else LOCK
        n_lock = sum(1 for t in fns[f][3] if t == lock)
        replace(fns, f, [lock], [("call", "early", "chanPeek", ["ch"]), lock], count=n_lock)
        replace(fns, f, [NOTIFY], [("call", None, "chanNotifyIf", ["ch", "early"])])


def d_unlock_no_wake(fns):
    replace(fns, "chanUnlock", [("call", None, "sysWakeWord", ["ch"], "(sysWakeWord ch)")], [])


def d_notify_no_wake(fns):
    replace(fns, "chanNotify", [("call", None, "sysWakeWord", ["ch + 1"], "(sysWakeWord (+ ch 8))")], [])


def d_plain_lock(fns):
    replace(fns, "chanLock", [("acas", "r", "ch", "0", "me", "(__atomic_cas ch 0 me)"), ("if", "r == 0", "slow")],
            [("uload", "r", "ch"), ("if", "r == 0", "slow"), ("astore", "ch", "me")])


# AN-10's regressions: each removes one part of the dead-holder handling,
# and the dead-holder scenarios must find the channel stuck.
def d_chan_no_dead_test(fns):
    replace(fns, "chanHolderDead", [("set", "owner", "w // 4", "(/ w 4)")], [("ret", "0")])


def d_chan_lock_unsliced(fns):
    # The lock wait of the three-state lock: the kernel's wait with no
    # slice, which nothing but a wake ends.
    F("sysWaitWordForever", ["addr", "expected", "nanos"], ["code"], None, [
        ("wait", "code", "addr", "expected", False), ("ret", "code")])
    fns["sysWaitWordForever"] = FUNCTIONS.pop("sysWaitWordForever")
    replace(fns, "chanAcquire",
            [("call", "code", "sysWaitWordTimeout", ["ch", "w", "slice"], "(sysWaitWordTimeout ch w slice)")],
            [("call", "code", "sysWaitWordForever", ["ch", "w", "slice"])])


def d_chan_no_child_look(fns):
    replace(fns, "chanChildEnded", [("look", "x", "pid", "(sysChildExited pid buf)")], [("set", "x", "0")])


def d_chan_poison_by_store(fns):
    replace(fns, "chanPoison",
            [("acas", "r", "ch", "w", str(POISON), "(__atomic_cas ch w chanPoisonMark)"), ("if", "r == w", "lost")],
            [("astore", "ch", str(POISON))])


def d_mutex_unlock_no_wake(fns):
    replace(fns, "mutexUnlock", [("call", None, "sysWakeWord", ["m"], "(sysWakeWord m)")], [])


def d_mutex_plain_lock(fns):
    replace(fns, "mutexLock", [("acas", "r", "m", "0", "me", "(syncCas m 0 me)"), ("if", "r == 0", "slow")],
            [("uload", "r", "m"), ("if", "r == 0", "slow"), ("astore", "m", "me")])


def d_mutex_guard_counter(fns):
    add_locals(fns, "mutexUnlock", ["l", "cnt"])
    replace(fns, "mutexUnlock",
            [("acas", "r", "m + 1", "guard", "0", "(syncCasAt m 1 guard 0)"), ("if", "r != guard", "claimed")],
            [("aload", "l", "m"), ("aload", "cnt", "m + 2"), ("if", "l == 0 or cnt != guard", "claimed")])


def d_mutex_no_reread(fns):
    replace(fns, "syncHolderDead", [("aload", "w", "m", "(syncLoad m 0)"), ("ret", "1 if w // 4 == owner else 0")],
            [("ret", "1")], count=2)


def d_mutex_no_child_look(fns):
    replace(fns, "syncChildEnded", [("look", "x", "pid", "(sysChildExited pid buf)")], [("set", "x", "0")])


def d_mutex_no_mark(fns):
    replace(fns, "syncAcquire", [("call", "w", "syncMarkWaiting", ["m", "v"], "(syncMarkWaiting m v)")],
            [("set", "w", "v")])


def chan_defect_scenarios():
    return [
        Scenario("chan cap 1: 1 sender x2, 1 receiver", "chan", chan_mem(1),
                 [("sender", (0, 1, 2, 1)), ("receiver", (0,))]),
        Scenario("chan cap 1: 1 sender x1, 2 receivers", "chan", chan_mem(1),
                 [("sender", (0, 1, 1, 1)), ("receiver", (0,)), ("receiver", (0,))]),
    ]


def sync_defect_scenarios():
    return [
        Scenario("mutex processes: 2 bindings x2", "sync", sync_mem(), [("locker", (0, 2))] * 2),
        Scenario("mutex threads: 3 bindings x1", "sync", sync_mem(), [("locker", (0, 1))] * 3, pids=[1, 1, 1]),
    ]


DEFECTS = [
    # name, what it plants, mutation, expected kind (None: expected clean), scenarios
    ("park after release",
     "the waiter parks (announces itself AND reads the counter) after releasing the lock",
     d_park_after_release, "lost wakeup", chan_defect_scenarios),
    ("announce after release",
     "only the announcement moves after the release; the counter is still read under the lock",
     d_announce_after_release, None, chan_defect_scenarios),
    ("notify reads the announcement before the change",
     "a changer reads word 2 before it takes the lock, and wakes only if that early read saw a waiter",
     d_notify_before_change, "lost wakeup", chan_defect_scenarios),
    ("chan release without a wake",
     "chanUnlock's contended release stores 0 and wakes nobody",
     d_unlock_no_wake, "lost wakeup", chan_defect_scenarios),
    ("chan notify without a wake",
     "chanNotify sees a waiter and wakes nobody (check-chan.sh's notify ablation)",
     d_notify_no_wake, "lost wakeup", chan_defect_scenarios),
    ("chan lock by load then store",
     "chanLock's acquire is a plain load of 0 then a store of 1",
     d_plain_lock, "mutual exclusion", chan_defect_scenarios),
    ("chan dead-holder test removed",
     "a lock waiter whose slice runs out never finds the holder dead (AN-10's regression)",
     d_chan_no_dead_test, "livelock",
     lambda: [s for s in chan_kill_scenarios() if "a receiver and a closer" in s.name]),
    ("chan lock wait without a slice",
     "the lock wait is the kernel's wait with no slice, as the three-state lock's was (AN-10 as it was found)",
     d_chan_lock_unsliced, "deadlock", lambda: [an10_scenario()]),
    ("chan child look removed",
     "a waiter never asks waitid about its own child, so a zombie holder looks alive to its parent too",
     d_chan_no_child_look, "livelock",
     lambda: [s for s in chan_kill_scenarios() if "whose parent" in s.name]),
    ("chan poison without its compare-and-swap",
     "the poison mark is stored, not swapped in from the dead holder's mark, so a stale look poisons a live channel",
     d_chan_poison_by_store, "false poisoning",
     lambda: [s for s in chan_kill_scenarios() if "a receiver and a closer" in s.name]),
    ("mutex release without a wake",
     "mutexUnlock's contended release stores 0 and wakes nobody",
     d_mutex_unlock_no_wake, "lost wakeup", sync_defect_scenarios),
    ("mutex lock by load then store",
     "mutexLock's acquire is a plain load of 0 then a store of the mark",
     d_mutex_plain_lock, "mutual exclusion", sync_defect_scenarios),
    ("mutex waiter without its mark",
     "a waiter sleeps on the lock word without setting bit 0",
     d_mutex_no_mark, "lost wakeup", sync_defect_scenarios),
    ("mutex guard compared with the counter",
     "mutexUnlock accepts a guard equal to the counter while the word is held (check-task.sh's guard ablation)",
     d_mutex_guard_counter, "unearned unlock",
     lambda: [Scenario("mutex threads: stale unlock beside a locker", "sync", sync_mem(),
                       [("staleLocker", (0, 1)), ("locker", (0, 1))], pids=[1, 1])]),
    ("mutex dead-holder test without its re-read",
     "a waiter poisons once kill(pid, 0) says ESRCH, without checking word 0 still names that pid",
     d_mutex_no_reread, "false poisoning",
     lambda: [Scenario("mutex processes: a killable holder, 1 waiter", "sync", sync_mem(),
                       [("locker", (0, 1)), ("locker", (0, 1))], killable=(0,), progress=("n", "t", "r"))]),
    ("mutex child look removed",
     "a waiter never asks waitid about its own child, so a zombie holder looks alive to its parent too (AN-56)",
     d_mutex_no_child_look, "livelock",
     lambda: [s for s in mutex_parent_scenarios() if "parent waits" in s.name]),
]


# ---------------------------------------------------------------------
# The transcription check.
# ---------------------------------------------------------------------

def source_functions(text):
    """name -> (first line, body text) for every `(fn (name ...` form."""
    out = {}
    starts = [(m.start(), m.group(1)) for m in re.finditer(r"^\((?:pub )?fn \(([A-Za-z0-9_]+)[ )]", text, re.M)]
    tops = [m.start() for m in re.finditer(r"^\(", text, re.M)] + [len(text)]
    for pos, name in starts:
        end = next(t for t in tops if t > pos)
        out[name] = (text.count("\n", 0, pos) + 1, text[pos:end])
    return out


def check_source(stdlib, verbose=True):
    texts = {}
    for f in SOURCES:
        p = os.path.join(stdlib, f)
        texts[f] = open(p, encoding="utf-8").read()
    fns = {f: source_functions(t) for f, t in texts.items()}
    failures, matched = [], 0
    # Each transcribed function: its cited spellings in order.
    for name, (params, locs, src, body) in FUNCTIONS.items():
        if src is None:
            continue
        f, sname = src
        if sname not in fns[f]:
            failures.append("%s %s: the model transcribes it, and the source has no such function" % (f, sname))
            continue
        line0, text = fns[f][sname]
        pos = 0
        for t in body:
            if t[0] in ("L", "ghost", "assert"):
                continue
            n = ARITY[t[0]]
            if len(t) <= 1 + n or t[1 + n] is None:
                continue
            sp = t[1 + n]
            k = text.find(sp, pos)
            if k < 0:
                where = "anywhere in it" if text.find(sp) < 0 else "after the step before it"
                failures.append("%s %s: `%s` (%s) is not %s" % (f, sname, sp.replace("\n", " "), t[0], where))
                continue
            line = line0 + text.count("\n", 0, k)
            if verbose:
                print("     %s:%d %s: %s `%s`" % (f, line, sname, t[0], sp.replace("\n", " ")))
            matched += 1
            pos = k + len(sp)
    for f, sname, sp in WRAPPERS:
        if sname not in fns[f]:
            failures.append("%s %s: a wrapper the model relies on is gone" % (f, sname))
            continue
        line0, text = fns[f][sname]
        k = text.find(sp)
        if k < 0:
            failures.append("%s %s: no longer contains `%s`" % (f, sname, sp.replace("\n", " ")))
            continue
        if verbose:
            print("     %s:%d %s: wrapper `%s`" % (f, line0 + text.count("\n", 0, k), sname, sp.replace("\n", " ")))
        matched += 1
    # Coverage: every function in the modules is modelled or excused.
    modules = [f for f in SOURCES if f != SYS]
    modelled = {src for (_, _, src, _) in FUNCTIONS.values() if src and src[0] in modules}
    for f in modules:
        for sname in fns[f]:
            if (f, sname) not in modelled and sname not in NOT_MODELLED[f]:
                failures.append("%s %s: neither modelled nor listed in NOT_MODELLED" % (f, sname))
        for sname in NOT_MODELLED[f]:
            if sname not in fns[f]:
                failures.append("%s %s: listed in NOT_MODELLED and gone from the source" % (f, sname))
        # Every atomic, wait and wake, and in Task.ax every process
        # operation, sits in a function the model transcribes or a wrapper
        # it checks. Comments are blanked first.
        code_only = re.sub(r";[^\n]*", lambda m: " " * len(m.group(0)), texts[f])
        ops = r"__atomic_\w+|sysWaitWord\w*|sysWakeWord\w*" + ("|" + PROCESS_OPS[f] if f in PROCESS_OPS else "")
        for m in re.finditer(ops, code_only):
            line = texts[f].count("\n", 0, m.start()) + 1
            owner = None
            for sname, (l0, text) in fns[f].items():
                if l0 <= line < l0 + text.count("\n") + 1:
                    owner = sname
            if owner is None:
                continue  # a comment outside any function
            if (f, owner) not in modelled and owner not in {w[1] for w in WRAPPERS if w[0] == f}:
                failures.append("%s:%d %s: `%s` is in a function the model does not transcribe"
                                % (f, line, owner, m.group(0)))
    return matched, failures


# ---------------------------------------------------------------------
# Replay: drive the model with the operations an instrumented build
# recorded, one at a time, and require every recorded operand and
# answer to be the model's.
# ---------------------------------------------------------------------
# `instrument DIR` rewrites DIR/Chan.ax (a copy of the standard library)
# so that every operation on a channel word (each atomic, each plain
# chanGet/chanPut, each wait and each wake) is made under a trace lock
# and recorded: `<pid> <op> <word> <a> <b> <answer>`, op 1 load, 2
# store, 3 add, 4 cas, 5 get, 6 put, 7 a wait begins (a expected,
# answer the word's value then), 8 that wait returned (answer its code),
# 9 wake. The lock is held across each operation, so the record's order
# is the order the operations happened in. A wait is
# `sysWaitWordTimeout`, whose own entry load is in Sys.ax and not
# recorded: the replay takes the recorded return code as the wait's
# answer. `chanFree` prints the record, with a `trace <cap> <count>
# <max>` line first. A program replayed here uses the untimed calls.

TRACE_OP = {1: "aload", 2: "astore", 3: "aadd", 4: "acas", 5: "pload", 6: "pstore", 7: "wait", 9: "wake"}
TRACE_NAME = {1: "load", 2: "store", 3: "add", 4: "cas", 5: "get", 6: "put", 7: "wait", 8: "woke", 9: "wake"}

# (the spelling in Chan.ax, what replaces it, how many times it occurs)
INSTRUMENT_SEAMS = [
    ("(import Err)\n", "(import Err)\n(import IO)\n(import Str)\n(import Fmt)\n", 1),
    ("(__atomic_load ", "(trLoad ", 4),
    ("(__atomic_cas ", "(trCas ", 5),
    ("(__atomic_add ", "(trAdd ", 5),
    ("(__atomic_store ", "(trStore ", 1),
    ("(sysWaitWordTimeout ", "(trWaitFor ", 3),
    ("(sysWakeWord ", "(trWake ", 4),
    ("(__load64 ch i)", "(trGet ch i)", 1),
    ("(__store64 ch i v)", "(trPut ch i v)", 1),
    ("(> cap 1048576)", "(> cap 504)", 1),
    ("(let ((len (* 8 (+ cap 8))))", "(let ((len (+ 4096 (* 8 (+ 3 (* 6 trMax))))))", 1),
    ("(chanPut ch 7 len)\n", "(chanPut ch 7 len)\n            (trStart ch)\n", 1),
    ("(sysUnmapShared ch (chanGet ch 7))", "(trFree ch)", 1),
]

TRACE_AX = r'''
; ---- the trace: scripts/check-protocol-model.sh's instrumented copy ----
; Each helper takes a raw address and is trusted: a helper whose body
; performs the primitive says `effect(unsafe)`, and `instrument` drops
; the claim of a function the replaced primitive alone supported.
; Every operation on a channel word, recorded in the order it happened:
; a trace lock is held across each. The record lives one page past the
; channel's words (so a traced channel holds at most 504): word 0 the
; trace lock, 1 recording on, 2 the count, then six words an operation.
(:: trMax Int)
(fn (trMax)
  60000)

(:: trArea (-> Int Int))
(fn (trArea addr)
  (+ (* (/ addr 4096) 4096) 4096))

(:: trEnter (-> Int Int))
;@axiom:effect(unsafe)
(fn (trEnter t)
  {
    (while (!= (__atomic_cas t 0 1) 0)
      0)
    0
  })

(:: trLeave (-> Int Int))
;@axiom:effect(unsafe)
(fn (trLeave t)
  (__atomic_store t 0))

(:: trNote (-> Int Int Int Int Int Int))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (trNote addr op a b r)
  (let ((t (trArea addr)))
    (if (== (__load64 t 1) 1)
      (let ((k (__load64 t 2)))
        {
          (if (< k trMax)
            (let ((e (+ t (* 8 (+ 3 (* 6 k))))))
              {
                (__store64 e 0 sysPid)
                (__store64 e 1 op)
                (__store64 e 2 (/ (- addr (- t 4096)) 8))
                (__store64 e 3 a)
                (__store64 e 4 b)
                (__store64 e 5 r)
                0
              })
            0)
          (__store64 t 2 (+ k 1))
          0
        })
      0)))

(:: trLoad (-> Int Int))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (trLoad a)
  (let ((t (trArea a)))
    {
      (trEnter t)
      (let ((r (__atomic_load a)))
        {
          (trNote a 1 0 0 r)
          (trLeave t)
          r
        })
    }))

(:: trStore (-> Int Int Int))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (trStore a v)
  (let ((t (trArea a)))
    {
      (trEnter t)
      (__atomic_store a v)
      (trNote a 2 v 0 0)
      (trLeave t)
      0
    }))

(:: trAdd (-> Int Int Int))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (trAdd a d)
  (let ((t (trArea a)))
    {
      (trEnter t)
      (let ((r (__atomic_add a d)))
        {
          (trNote a 3 d 0 r)
          (trLeave t)
          r
        })
    }))

(:: trCas (-> Int Int Int Int))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (trCas a old new)
  (let ((t (trArea a)))
    {
      (trEnter t)
      (let ((r (__atomic_cas a old new)))
        {
          (trNote a 4 old new r)
          (trLeave t)
          r
        })
    }))

(:: trGet (-> Int Int Int))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (trGet ch i)
  (let ((t (trArea ch)))
    {
      (trEnter t)
      (let ((r (__load64 ch i)))
        {
          (trNote (+ ch (* 8 i)) 5 0 0 r)
          (trLeave t)
          r
        })
    }))

(:: trPut (-> Int Int Int Int))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (trPut ch i v)
  (let ((t (trArea ch)))
    {
      (trEnter t)
      (__store64 ch i v)
      (trNote (+ ch (* 8 i)) 6 v 0 0)
      (trLeave t)
      0
    }))

(:: trWaitFor (-> Int Int Int Int))
;@axiom:effect(io)
;@axiom:effect(unsafe)
;@axiom:effect(block)
(fn (trWaitFor addr expected nanos)
  (let ((t (trArea addr)))
    {
      (trEnter t)
      (trNote addr 7 expected 0 (__atomic_load addr))
      (trLeave t)
      (let ((code (sysWaitWordTimeout addr expected nanos)))
        {
          (trEnter t)
          (trNote addr 8 expected 0 code)
          (trLeave t)
          code
        })
    }))

(:: trWake (-> Int Int))
;@axiom:effect(io)
(fn (trWake addr)
  (let ((t (trArea addr)))
    {
      (trEnter t)
      (trNote addr 9 0 0 0)
      (sysWakeWord addr)
      (trLeave t)
      0
    }))

(:: trStart (-> Int Int))
;@axiom:effect(unsafe)
(fn (trStart ch)
  {
    (__store64 (trArea ch) 1 1)
    0
  })

(:: trFree (-> Int (Result Int Error)))
;@axiom:effect(io)
;@axiom:effect(unsafe)
(fn (trFree ch)
  (let (
    (t (trArea ch))
    (n (__load64 (trArea ch) 2))
    (cap (__load64 ch 5))
    (mx trMax)
    (mut k 0)
  )
    {
      (__store64 t 1 0)
      (println "trace {cap} {n} {mx}")
      (while (&& (< k n) (< k mx))
        (let ((e (+ t (* 8 (+ 3 (* 6 k))))))
          (let (
            (p (__load64 e 0))
            (o (__load64 e 1))
            (w (__load64 e 2))
            (x (__load64 e 3))
            (y (__load64 e 4))
            (r (__load64 e 5))
          )
            {
              (println "{p} {o} {w} {x} {y} {r}")
              (set k (+ k 1))
            })))
      (sysUnmapShared ch (__load64 ch 7))
    }))
'''

# Changes the gate plants in the copy before tracing it, each of which the
# replay must refuse.
PLANTS = {
    # A change counter that counts in twos: a run that still works.
    "bump-by-two": [("(fn (chanBump ch)\n  (__atomic_add (+ ch 8) 1))",
                     "(fn (chanBump ch)\n  (__atomic_add (+ ch 8) 2))", 1)],
}

TRACED = ("trLoad", "trStore", "trAdd", "trCas", "trGet", "trPut", "trWaitFor", "trWake", "trStart", "trFree")


def instrument(stdlib_dir, extra=()):
    """Rewrite stdlib_dir/Chan.ax in place as the traced copy. `extra` is
    more (old, new, count) seams, applied first: the gate's controls."""
    p = os.path.join(stdlib_dir, CHAN)
    s = open(p, encoding="utf-8").read()
    report = []
    for old, new, count in list(extra) + INSTRUMENT_SEAMS:
        n = s.count(old)
        if n != count:
            raise SystemExit("instrument: `%s` occurs %d time(s) in %s, wanted %d"
                             % (old.strip()[:50], n, p, count))
        s = s.replace(old, new)
        report.append("%s x%d" % (old.strip(), n))
    # Every function that now reaches the trace performs IO, and says so.
    fns = source_functions(s)
    code = {name: re.sub(r";[^\n]*", "", text) for name, (_, text) in fns.items()}
    io = set()
    changed = True
    while changed:
        changed = False
        for name, text in code.items():
            if name in io:
                continue
            if any(re.search(r"\(%s[\s)]" % re.escape(t), text) for t in TRACED + tuple(io)):
                io.add(name)
                changed = True
    for name in sorted(io):
        m = re.search(r"^((?:;@axiom:[^\n]*\n)*)(\((?:pub )?fn \(%s[ )])" % re.escape(name), s, re.M)
        if m and ";@axiom:effect(io)" not in m.group(1):
            s = s[:m.start(2)] + ";@axiom:effect(io)\n" + s[m.start(2):]
    # A function whose only unsafe operations were the primitives the
    # seams replaced now calls trusted trace helpers instead, so its
    # `effect(unsafe)` claim would be unsupported (AX3010): drop it.
    for name, text in sorted(code.items()):
        if re.search(r"\((?:__|cast )", text):
            continue
        m = re.search(r"^((?:;@axiom:[^\n]*\n)*)(\((?:pub )?fn \(%s[ )])" % re.escape(name), s, re.M)
        if m and ";@axiom:effect(unsafe)\n" in m.group(1):
            tags = m.group(1).replace(";@axiom:effect(unsafe)\n", "", 1)
            s = s[:m.start(1)] + tags + s[m.end(1):]
    s += TRACE_AX
    open(p, "w", encoding="utf-8").write(s)
    return report, sorted(io)


def parse_trace(path):
    header, events = None, []
    for line in open(path, encoding="utf-8"):
        parts = line.split()
        if len(parts) == 4 and parts[0] == "trace":
            header = tuple(int(x) for x in parts[1:])
        elif header and len(parts) == 6 and all(re.fullmatch(r"-?\d+", x) for x in parts):
            events.append(tuple(int(x) for x in parts))
    return header, events


REPLAY_STOPS = VISIBLE | {"pload", "pstore"}


def replay_to_stop(model, c, b, op):
    """Run binding b to its next recorded step. A look at a holder (after
    a lock wait's slice ran out) is not recorded, and in a run where no
    binding dies it answers alive, which the model's kill and look do
    when no binding has died; it is taken here. A recorded wait begins
    (op 7) where the model's `sysWaitWordTimeout` makes its entry load,
    which Sys.ax does unrecorded: the load is taken as finding the word
    unchanged, and the recorded return code says what the wait found."""
    while True:
        outs = model.run(c, b, False, stops=REPLAY_STOPS)
        if len(outs) != 1:
            raise ValueError("the model branched")
        c = outs[0]
        w = c.thaw(b)
        if not w[1]:
            return c
        fr = w[1][-1]
        ins = model.codes[fr[0]].ins[fr[1]]
        if ins[0] in ("kill0", "look"):
            c = model.run(c, b, True, stops=REPLAY_STOPS)[0]
            continue
        if ins[0] == "uload" and fr[0] == "sysWaitWordTimeout" and op == 7:
            code = model.codes[fr[0]]
            fr[2][ins[1]] = fr[2][code.vars.index("expected")]
            fr[1] += 1
            continue
        return c


def replay(path, verbose=False):
    header, events = parse_trace(path)
    if header is None:
        return 0, ["the trace has no `trace` line: the program was not built against the traced copy"], {}
    cap, count, most = header
    if count != len(events):
        return len(events), ["the trace says %d operations and holds %d%s" % (
            count, len(events), " (it overflowed its %d)" % most if count > most else "")], {}
    # Who is who: a binding that put words in the ring is sender word//1000;
    # one that put 1 in word 6 closes; every other binding receives.
    pids = []
    for ev in events:
        if ev[0] not in pids:
            pids.append(ev[0])
    bindings, roles = [], []
    for p in pids:
        puts = [ev for ev in events if ev[0] == p and ev[1] == 6]
        ring = [ev for ev in puts if ev[2] >= 8]
        if ring:
            senders = {ev[3] // 1000 for ev in ring}
            if len(senders) != 1:
                return len(events), ["pid %d put words of senders %s in the ring" % (p, sorted(senders))], {}
            s = senders.pop()
            closes = 1 if any(ev[2] == 6 for ev in puts) else 0
            bindings.append(("sender", (0, s, len(ring), closes)))
            roles.append("sender %d x%d" % (s, len(ring)))
        elif any(ev[2] == 6 and ev[3] == 1 for ev in puts):
            bindings.append(("closer", (0,)))
            roles.append("closer")
        else:
            bindings.append(("receiver", (0,)))
            roles.append("receiver")
    # Each binding is its recorded pid, which is its mark in the lock word.
    sc = Scenario("replay", "chan", chan_mem(cap), bindings, pids=list(pids))
    model = Model(sc, compile_all(FUNCTIONS))
    c = model.ctx(model.initial())
    stats = collections.Counter()
    pending = {}   # binding -> [word, expected, justified]
    failures = []

    def fail(k, msg):
        failures.append("operation %d (%s): %s" % (k + 1, " ".join(str(x) for x in events[k]), msg))

    for k, ev in enumerate(events):
        pid, op, word, a, bb, r = ev
        b = pids.index(pid)
        stats[TRACE_NAME.get(op, "?")] += 1
        if op == 8:
            if b not in pending:
                fail(k, "B%d's wait returned, and it was not waiting" % (b + 1))
                break
            w_word, w_exp, justified = pending.pop(b)
            # A timeout is the environment's, and always a legal return.
            if not justified and r != 1:
                stats["unexplained wait returns"] += 1
            model._resume(c, b, r)
            continue
        if b in pending:
            fail(k, "B%d acted while the trace has it waiting" % (b + 1))
            break
        try:
            c = replay_to_stop(model, c, b, op)
        except Violation as v:
            fail(k, "%s: %s" % (v.kind, v.msg))
            break
        except ValueError as e:
            fail(k, str(e))
            break
        w = c.thaw(b)
        if not w[1]:
            fail(k, "B%d (%s) has finished in the model" % (b + 1, roles[b]))
            break
        fr = w[1][-1]
        code = model.codes[fr[0]]
        ins = code.ins[fr[1]]
        L = fr[2]
        mop = ins[0]
        where = "%s %s" % (code.src[0], code.src[1]) if code.src else code.name
        if TRACE_OP.get(op) != mop:
            fail(k, "B%d (%s) did %s; the model's next step is %s in %s (`%s`)"
                 % (b + 1, roles[b], TRACE_NAME.get(op, op), mop, where, ins[-1]))
            break
        # The operands, as the model computes them.
        if mop in ("aload", "pload", "aadd", "acas", "wait"):
            addr = ins[2](*L)
        else:
            addr = ins[1](*L)
        want = {"aload": (), "pload": (), "astore": (ins[2](*L),) if mop == "astore" else (),
                "pstore": (ins[2](*L),) if mop == "pstore" else (),
                "aadd": (ins[3](*L),) if mop == "aadd" else (),
                "acas": (ins[3](*L), ins[4](*L)) if mop == "acas" else (),
                "wait": (ins[3](*L),) if mop == "wait" else (), "wake": ()}[mop]
        got = (a, bb)[:len(want)]
        if addr != word or tuple(want) != tuple(got):
            fail(k, "B%d (%s) did %s on word %d with %s; the model's %s (`%s`) is on word %d with %s"
                 % (b + 1, roles[b], TRACE_NAME[op], word, list(got), where, ins[-1], addr, list(want)))
            break
        if mop == "wait":
            if c.mem[word] != r:
                fail(k, "word %d held %d at B%d's wait, and %d in the model" % (word, r, b + 1, c.mem[word]))
                break
            pending[b] = [word, a, c.mem[word] != a]
            continue
        before = c.mem[addr]
        if mop in ("aload", "pload", "aadd", "acas") and r != before:
            fail(k, "B%d's %s of word %d answered %d; the model's answers %d"
                 % (b + 1, TRACE_NAME[op], word, r, before))
            break
        try:
            outs = model.run(c, b, True, stops=REPLAY_STOPS)
        except Violation as v:
            fail(k, "%s: %s" % (v.kind, v.msg))
            break
        c = outs[0]
        if mop == "wake":
            for o, pw in pending.items():
                if pw[0] == word:
                    pw[2] = True
        elif c.mem[addr] != before:
            for o, pw in pending.items():
                if pw[0] == addr:
                    pw[2] = True
    if not failures:
        # Every binding ends with its own local steps.
        for b in range(len(pids)):
            c = replay_to_stop(model, c, b, 0)
            w = c.thaw(b)
            if w[1]:
                fr = w[1][-1]
                failures.append("the trace ends and B%d (%s) still has `%s` to do in %s"
                                % (b + 1, roles[b], model.codes[fr[0]].ins[fr[1]][-1], fr[0]))
        if not failures:
            v = model.final_check(model.freeze(c))
            if v is not None:
                failures.append("%s: %s" % (v.kind, v.msg))
    stats["bindings"] = len(pids)
    stats["roles"] = ", ".join(roles)
    return len(events), failures, stats


# ---------------------------------------------------------------------
# The task pool (stdlib/Task.ax), in a module of its own.
# ---------------------------------------------------------------------

def _install_task_model():
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "task_model", os.path.join(os.path.dirname(os.path.abspath(__file__)), "task-model.py"))
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    mod.install(globals())


_install_task_model()


# ---------------------------------------------------------------------
# The command line.
# ---------------------------------------------------------------------

def _explore_one(args):
    """One scenario, in a worker. Anything it raises comes back as a
    finding: a worker that dies leaves `Pool.map` waiting for ever."""
    k, long = args
    sc = scenarios(long)[k]
    try:
        res = explore(Model(sc, compile_all(FUNCTIONS)), limit=8_000_000 if long else 5_000_000)
    except BaseException as e:
        import traceback
        return (sc.name, 0, 0, 0, 0, "error", traceback.format_exc(), 0, set())
    buf = []
    if res.finding:
        import io
        out = io.StringIO()
        print_finding(res, out)
        buf.append(out.getvalue())
    return (sc.name, res.states, res.transitions, res.depth, res.terminal,
            res.finding.kind if res.finding else None, "".join(buf), res.sleeping, res.reached)


def workers():
    try:
        n = int(os.environ.get("PROTOCOL_MODEL_JOBS", "0"))
    except ValueError:
        n = 0
    return n if n > 0 else max(1, min(4, os.cpu_count() or 1))


def run_all(long):
    jobs = [(k, long) for k in range(len(scenarios(long)))]
    n = workers()
    if n > 1:
        import multiprocessing
        with multiprocessing.get_context("fork").Pool(n) as pool:
            results = pool.map(_explore_one, jobs, chunksize=1)
    else:
        results = [_explore_one(j) for j in jobs]
    total_states = total_trans = 0
    bad = 0
    reached = set()
    for name, states, trans, depth, ends, kind, text, sleeping, got in results:
        total_states += states
        total_trans += trans
        reached |= got
        if kind:
            bad += 1
            print("FAIL %s: %s after %d states" % (name, kind, states))
            sys.stdout.write(text)
        else:
            print("clean %-66s states %8d  transitions %9d  depth %3d  asleep %7d"
                  % (name, states, trans, depth, sleeping))
    print("TOTAL scenarios %d states %d transitions %d" % (len(results), total_states, total_trans))
    # Coverage: every transcribed instruction some scenario executed.
    codes = compile_all(FUNCTIONS)
    every = [(name, pc) for name, c in codes.items() if c.src for pc in range(len(c.ins))]
    missed = [x for x in every if x not in reached]
    excused = 0
    for name, pc in missed:
        raw = codes[name].raw[pc]
        # The k-th occurrence of this instruction in its function, from 1.
        k = sum(1 for q in range(pc + 1) if codes[name].raw[q] == raw)
        key = tuple(tuple(x) if isinstance(x, list) else x for x in raw)
        why = UNREACHABLE.get((name, key)) if k == 1 else None
        why = why or UNREACHABLE.get((name, key, k))
        text = " ".join(str(a) for a in raw[:3])
        if why:
            excused += 1
            print("unreached %s #%d %s - %s" % (name, pc, text, why))
        else:
            print("UNREACHED %s #%d %s - no scenario reaches it" % (name, pc, text))
    print("COVERAGE transcribed instructions %d reached %d excused %d gaps %d"
          % (len(every), len(every) - len(missed), excused, len(missed) - excused))
    return bad + (len(missed) - excused)


def run_an10():
    codes = compile_all(FUNCTIONS)
    res = explore(Model(an10_scenario(), codes))
    print("AN-10 %s: %d states" % (an10_scenario().name, res.states))
    if res.finding:
        print_finding(res)
        return res.finding.kind
    return None


def run_defects(long, only=None):
    bad = 0
    for name, what, mutate, want, make in DEFECTS:
        if only and name != only:
            continue
        fns = dict(FUNCTIONS)
        mutate(fns)
        codes = compile_all(fns)
        found = None
        states = 0
        for sc in make():
            res = explore(Model(sc, codes))
            states += res.states
            if res.finding:
                found = (sc, res)
                break
        if want is None:
            if found:
                print("REPORT %s: expected clean and found %s" % (name, found[1].finding.kind))
                print_finding(found[1])
            else:
                print("REPORT %s: clean in %d states - %s" % (name, states, what))
            continue
        if not found:
            bad += 1
            print("FAIL %s: nothing found in %d states - the model cannot see %s" % (name, states, what))
            continue
        sc, res = found
        kind = res.finding.kind
        verdict = "RED" if kind == want else "FAIL"
        if kind != want:
            bad += 1
        print("%s %s: %s on '%s' after %d states (wanted %s) - %s"
              % (verdict, name, kind, sc.name, res.states, want, what))
        print_finding(res)
    return bad


def main(argv):
    if len(argv) < 2:
        print(__doc__)
        return 2
    cmd = argv[1]
    long = "--long" in argv
    if cmd == "run":
        bad = run_all(long)
        kind = run_an10()
        print("AN10 %s" % (kind or "clean"))
        return 1 if bad else 0
    if cmd == "defects":
        only = None
        if "--only" in argv:
            only = argv[argv.index("--only") + 1]
        return 1 if run_defects(long, only) else 0
    if cmd == "transcription":
        stdlib = argv[2] if len(argv) > 2 and not argv[2].startswith("-") else os.path.join(
            os.path.dirname(os.path.abspath(__file__)), "..", "..", "stdlib")
        matched, failures = check_source(stdlib, verbose="--quiet" not in argv)
        for f in failures:
            print("FAIL " + f)
        print("SOURCE matched %d failures %d" % (matched, len(failures)))
        return 1 if failures else 0
    if cmd == "replay":
        n, failures, stats = replay(argv[2], verbose="--verbose" in argv)
        for f in failures:
            print("FAIL " + f)
        if stats:
            print("REPLAY bindings %s: %s" % (stats.pop("bindings"), stats.pop("roles")))
            print("REPLAY operations " + ", ".join("%s %d" % kv for kv in sorted(stats.items())))
        print("REPLAY events %d failures %d" % (n, len(failures)))
        return 1 if failures or n == 0 else 0
    if cmd == "instrument":
        extra = PLANTS[argv[argv.index("--plant") + 1]] if "--plant" in argv else ()
        report, io = instrument(argv[2], extra)
        print("INSTRUMENTED " + "; ".join(report))
        print("INSTRUMENTED effect(io) added where the trace is reached: " + ", ".join(io))
        return 0
    if cmd == "show":
        codes = compile_all(FUNCTIONS)
        for sc in scenarios(long) + [an10_scenario()]:
            if argv[2] in sc.name:
                res = explore(Model(sc, codes))
                print("%s: %d states, %d transitions" % (sc.name, res.states, res.transitions))
                if res.finding:
                    print_finding(res)
        return 0
    print(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
