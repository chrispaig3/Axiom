#!/usr/bin/env bash
# The mutex, the timed waits and the structured task pool (R-C2;
# docs/memory-model.md MM-PAR-11, MM-PAR-12, MM-PAR-13).
#
# `stdlib/Sync.ax` is a futex-style mutex in a MAP_SHARED word,
# `sysWaitWordTimeout` (`stdlib/Sys.ax`) the timed wait under it and
# under `chanRecvTimeout`/`chanSendTimeout` (`stdlib/Chan.ax`), and
# `stdlib/Task.ax` a bounded pool of forked tasks answering typed
# results by serialization, with deadlines, cancellation and per-task
# failure. The fixtures `tests/stdlib/540`-`543` pin their answers;
# this gate puts them under load, against the clock, against ablated
# copies of the library, and checks the processes the pool leaves.
#
# TEN SECTIONS.
#
#   1. Mutual exclusion. tests/litmus/sync-load.ax: four bindings,
#      released together, add 1 to one PLAIN shared word N times each
#      under the mutex - exact in BOTH lowerings at --opt 0 and 2. Beside
#      each, the same run with no lock is REQUIRED to lose updates: a
#      control that cannot lose one means the count cannot see a race
#      on this host, and that is reported as a failure, not a pass.
#   2. The clock. Timed receive, send and lock (200 ms) must answer
#      `sysTimedOut` no sooner than asked and within a generous slack
#      (800 ms: this gate runs in the parallel pool, and the bound is on
#      lateness under load, not on the kernel); a receive and a lock
#      satisfied at ~100 ms of a 2 s wait must answer then, not at the
#      timeout. A holder SIGKILLed holding the
#      mutex must be found dead by the next lock call, and so must a
#      holder that exits holding it and is not yet reaped - a zombie,
#      which only its own process's `waitid` sees exit: the parent's
#      2 s timed lock must answer syncOwnerDead well before 2 s, in both
#      lowerings, and so must a sibling THREAD's under --threads, while a
#      sibling PROCESS, which cannot look, times out (the stated limit,
#      and the control that the look is what decides); every unlock the
#      caller did not earn must be refused - including a stale guard
#      presented in the window between a new holder's lock and its
#      guard's publication, which is built exactly rather than raced
#      for; and under load, a binding double-unlocking every time
#      beside two correct ones must be refused every time while no
#      earned unlock is.
#   3. Tasks. Results equal the sequential answer (300 tasks, width 8,
#      both lowerings, --opt 0 and 2); a grace of the largest `Int` is
#      for ever, not a wrapped negative; a task that answers and then
#      cannot exit (a thread its process joins for ever) is ended by
#      its deadline with its answer, rather than blocking the pool in
#      `wait4`; a trapping task answers its
#      status while its siblings complete, found by looking at the
#      child with no deadline to help; a task past its deadline answers
#      the timeout and its pid is GONE (the program asks `kill(pid, 0)`
#      before it exits, so a zombie would count as present, and this
#      gate asks again after); an oversized answer is refused and the
#      parent survives; a cancellation from another binding stops the
#      cooperative task, kills the stubborn one after the grace and
#      starts nothing more; `failFast` does the same after a trap.
#   4. No child outlives the call. A trap in the parent in the middle of
#      a pool (`taskFold`'s step divides by zero) must take the running
#      tasks with it - MM-PAR-7's sweep; both recorded pids must be gone.
#      And the CONTROL that shows `kill -0` can see a survivor: a parent
#      SIGKILLed from outside runs no sweep, and its tasks must still be
#      alive (the limit `stdlib/Task.ax` states), after which this gate
#      kills them itself. And under --threads a trap in a SIBLING
#      thread, which ends the process with its own registry swept,
#      must take the pool's task with it: the process-wide kill list's
#      job (MM-PAR-7). A thread started inside a forked child - a raw
#      fork's, a task's, a stuck task's - must run, in both lowerings
#      (`tests/litmus/thread-in-fork.ax`).
#   5. Retained memory. `taskFold` over 500 and 5,000 tasks of 4 KiB
#      answers: peak RSS may differ by at most 1 MiB. The control keeps
#      the same answers with `taskMap` and must grow by at least 8 MiB,
#      so a flat fold is a measurement and not a blind one.
#   6. Ablations, each on a COPY of the standard library, each required
#      to turn its check red: the lock (no compare-and-swap), the timed
#      wait (the kernel asked for a tenth of the time), the dead-holder
#      test, the deadline's kill, the borrowed handle layout (a pid that
#      is not the child's), the child look (never sees an exit),
#      the result slot (a task answers into its neighbour's), the byte
#      limit, the cancellation's kill, the mutex's look at its own
#      zombie child (never asked), the unlock's guard (compared
#      against the counter again, which accepts the stale guard in
#      the window), the microseconds conversion (rounding that wraps
#      a grace of the largest `Int`) and the exit wait (a task joined
#      on its answer alone, which blocks the pool on a task that
#      cannot exit).
#   7. The examples under examples/concurrency/ build and run, in both
#      lowerings, each checking its own answers and ending `ok`.
#   8. The runtime's half, ablated in the COMPILER: a copy of
#      `self_host/` with the abort's kill-list sweep deleted must leave
#      the sibling-trap task alive; and on Darwin a copy forking with
#      the raw system call again must crash a thread started inside a
#      forked child (`tests/litmus/thread-in-fork.ax`). Linux's raw
#      fork leaves the child's threads working, so there that drill
#      cannot go red and is reported as not applicable, not passed.
#   9. A spawn refused mid-pool (R-B2). tests/litmus/pool-refuse.ax
#      fills the runtime's handle table but for a few slots, so a pool's
#      third spawn is refused - the path a fork the kernel refuses takes
#      too - with two tasks running. `taskMap` must answer 78 in the
#      refused slot and cancel, `parMapWordsChecked` answer 78 there and
#      137 for the two it killed, and `parMapWords` raise 78 to the
#      recovery point. While the program still lives, every pid a task
#      printed must be gone, it must have no child at all, and every
#      handle slot must be back; eight refused `taskMap` rounds with a
#      128 MiB slab each must leave the address space where one left
#      it. The kernel refuses too: a fold's step lowers RLIMIT_NPROC so
#      the next fork fails, and `ulimit -u 1` refuses the first (both
#      skipped under root, which the limit does not bind). Three
#      ablations: the recovery point around a task's spawn (the rounds
#      keep their slabs again), the cancellation a refusal starts (the
#      pool never ends), and the checked pool's kill (its joins never
#      end).
#  10. Determinism (MM-PAR-14). tests/litmus/par-determinism.ax adds
#      2,000 Float terms whose sum rounds differently in any other
#      order, through `taskFold`, `taskMap`, `parMapWords` and
#      `parMapWordsChecked` at widths 1, 2, 3, 4 and 8, in both
#      lowerings, with tasks made to finish out of submit order: every
#      answer must be the sequential sum's bits, which a Python
#      recomputation in IEEE doubles must agree with. `parallel`
#      bindings (1 to 8) must answer the chunked association computed
#      in turn. Controls: the reverse-order, pairwise and chunked sums
#      must each differ from index order. Several failures: the
#      raising pool must raise the lowest failing index's status in
#      every run at every width, and the per-slot pools must answer
#      each failure in its slot. The emitted IR must carry no fast-math
#      mark, and after opt and llc -O3 no fused multiply-add or
#      vectorised sum, beside controls whose IR asks for each and must
#      show it. Two ablations: a pool delivering in completion order
#      must answer other bits, and a raising pool joining newest first
#      must raise another status. failFast's answers are reported,
#      because they are the clock's.
#
# WHAT THE NUMBERS ARE. Peak RSS (`max_rss_kb`), in KiB, of the whole
# program. Times are the programs' own `sysTimeoutMicros` readings -
# CLOCK_MONOTONIC on Linux, the realtime clock on Darwin (MM-PAR-12).
#
# LIMITS. A load that passed is evidence on the runs made, on this
# host; the lock, the protocol and the pool are not proved. FreeBSD
# spins instead of blocking and looks at a child through `wait6`, and
# neither is run here. The pids a check reads are reused by the kernel
# eventually; the checks run within seconds of recording them.
#
# Usage: check-task.sh
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

sync="$repo_root/tests/litmus/sync-load.ax"
task="$repo_root/tests/litmus/task-load.ax"

# build <out> <source> <flags...>: from the tree's stdlib.
build() {
  local out="$1" src="$2"; shift 2
  (cd "$repo_root" && "$axc" build "$@" --input "$src" --output "$out") > "$out.build" 2>&1
}

# field <text> <first word>: the rest of the first line starting with it.
field() {
  printf '%s\n' "$1" | awk -v k="$2" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }'
}

# gone <pid...>: 0 when every pid names no process (not even a zombie).
gone() {
  local p
  for p in "$@"; do
    kill -0 "$p" 2>/dev/null && return 1
  done
  return 0
}

# ---------------------------------------------------------------------
echo "== 1. mutual exclusion: 4 bindings, one plain word =="
N=100000
for lowering in processes threads; do
  flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
  for lvl in 0 2; do
    bin="$work/sync-$lowering-O$lvl"
    if ! build "$bin" "$sync" ${flags[@]+"${flags[@]}"} --opt "$lvl"; then
      bad "$lowering -O$lvl: sync-load did not build"; sed 's/^/    /' "$bin.build" | head -8; continue
    fi
    rc=0; out="$(gate_timeout 120 "$bin" excl 1 "$N" 2>&1)" || rc=$?
    if [[ "$rc" == 0 && "$out" == "count $((4 * N)) ok" ]]; then
      ok "$lowering -O$lvl: $((4 * N)) locked increments, none lost"
    else
      bad "$lowering -O$lvl: locked run exit $rc, '$out'"
    fi
    # The control may take up to five runs, as check-atomics' controls
    # do: four bindings that never overlap lose nothing, and on
    # linux-aarch64 one run of the unlocked control lost no update at
    # -O2 under processes and at -O0 under threads (CI run 36584155583).
    lost=0; tries=0
    while (( lost == 0 && tries < 5 )); do
      tries=$((tries + 1))
      rc=0; out="$(gate_timeout 120 "$bin" excl 0 "$N" 2>&1)" || rc=$?
      if [[ "$rc" == 0 && "$out" =~ lost\ ([0-9]+)$ ]]; then
        lost="${BASH_REMATCH[1]}"
      fi
    done
    if (( lost > 0 )); then
      ok "$lowering -O$lvl: the unlocked control lost $lost of $((4 * N)) on run $tries - the count can see a race"
    else
      bad "$lowering -O$lvl: the unlocked control showed no lost update in $tries runs ('$out', exit $rc) - this host cannot show the race the locked run is held to"
    fi
  done
done

# ---------------------------------------------------------------------
echo "== 2. timed waits against the clock; a dead holder; misuse =="
T=200
SLACK=800
# within <what> <code> <us> <want code> <lo ms> <hi ms>
within() {
  local what="$1" line="$2" want="$3" lo="$4" hi="$5" code us
  code="${line%% *}"; us="${line##* }"
  if [[ "$code" == "$want" && "$us" =~ ^[0-9]+$ ]] && (( us >= lo * 1000 && us <= hi * 1000 )); then
    ok "$what: code $code after $((us / 1000)) ms (bounds $lo..$hi ms)"
  else
    bad "$what: '$line' - wanted code $want within $lo..$hi ms"
  fi
}
for lowering in processes threads; do
  bin="$work/sync-$lowering-O2"
  [[ -x "$bin" ]] || { bad "$lowering: no sync binary"; continue; }
  rc=0; out="$(gate_timeout 30 "$bin" timed "$T" 2>&1)" || rc=$?
  [[ "$rc" == 0 ]] || bad "$lowering: timed mode exit $rc: $out"
  within "$lowering recv-timeout" "$(field "$out" recv-timeout)" 1001 "$T" $((T + SLACK))
  within "$lowering send-timeout" "$(field "$out" send-timeout)" 1001 "$T" $((T + SLACK))
  within "$lowering lock-timeout" "$(field "$out" lock-timeout)" 1001 "$T" $((T + SLACK))
  within "$lowering lock-got (holder lets go at ~$((T / 2)) ms of a $((10 * T)) ms wait)" "$(field "$out" lock-got)" 0 $((T / 4)) $((10 * T - 500))
  within "$lowering recv-got (sent at ~$((T / 2)) ms of a $((10 * T)) ms wait)" "$(field "$out" recv-got)" 0 $((T / 4)) $((10 * T - 500))
  rc=0; out="$(gate_timeout 30 "$bin" dead 2>&1)" || rc=$?
  within "$lowering: lock while the holder lives" "$(field "$out" alive-timed)" 1001 250 $((250 + SLACK))
  within "$lowering: timed lock after the holder was killed" "$(field "$out" dead-timed)" 1004 0 1500
  within "$lowering: untimed lock after that" "$(field "$out" dead-untimed)" 1004 0 1500
  if [[ "$(field "$out" holder-status)" == 137 && "$(field "$out" poisoned)" == 1 ]]; then
    ok "$lowering: the holder died of SIGKILL (137) and the mutex reads poisoned"
  else
    bad "$lowering: dead mode exit $rc: $(printf '%s' "$out" | tr '\n' ';')"
  fi
  # A holder that exits holding the lock and is not reaped (AN-56).
  rc=0; out="$(gate_timeout 30 "$bin" zombie 2>&1)" || rc=$?
  if [[ "$lowering" == threads ]]; then
    within "$lowering: a sibling thread's timed lock, its process's zombie child holding" "$(field "$out" sibling-timed)" 1004 0 1500
  else
    within "$lowering: CONTROL - a sibling process's timed lock, a zombie it cannot look at holding" "$(field "$out" sibling-timed)" 1001 300 $((300 + SLACK))
  fi
  within "$lowering: the parent's 2 s timed lock, its own zombie child holding" "$(field "$out" zombie-timed)" 1004 0 1500
  within "$lowering: its untimed lock after that" "$(field "$out" zombie-untimed)" 1004 0 1500
  if [[ "$rc" == 0 && "$(field "$out" holder-status)" == 0 && "$(field "$out" poisoned)" == 1 ]]; then
    ok "$lowering: the zombie holder had exited 0 holding the lock, and the mutex reads poisoned"
  else
    bad "$lowering: zombie mode exit $rc: $(printf '%s' "$out" | tr '\n' ';')"
  fi
done
bin="$work/sync-processes-O2"
if [[ -x "$bin" ]]; then
  out="$(gate_timeout 30 "$bin" misuse 2>&1 | tr '\n' ' ')"
  if [[ "$out" == "free 1005 wrong-guard 1005 zero-guard 1005 right 0 twice 1005 "* ]]; then
    ok "every unearned unlock refused with syncNotHeld (free, wrong guard, zero guard, twice)"
  else
    bad "misuse: '$out'"
  fi
  # The stale guard in the one window a double unlock can land in: the
  # lock word taken by a new holder that has not yet published its
  # guard. Built exactly, so the check does not depend on a race.
  if [[ "$out" == *"stale-in-window 1005 still-held 1 " ]]; then
    ok "a stale guard presented between a new holder's lock and its guard is refused, and the lock stays held"
  else
    bad "stale guard in the window: '$out' - wanted 'stale-in-window 1005 still-held 1'"
  fi
fi
# The same under load: one binding double-unlocks every time while two
# lock normally. No stale unlock may be accepted, no earned one refused,
# and no increment lost. The window is a few instructions wide, so a
# broken guard shows here only now and then; the exact check above is
# the one that always does. This one holds the fix to not refusing a
# legitimate unlock under contention.
for lowering in processes threads; do
  bin="$work/sync-$lowering-O2"
  [[ -x "$bin" ]] || continue
  rc=0; out="$(gate_timeout 60 "$bin" stale 200000 2>&1)" || rc=$?
  if [[ "$rc" == 0 && "$out" == "stale-accepted 0 own-refused 0 count 600000 of 600000 ok" ]]; then
    ok "$lowering: 200,000 stale unlocks under contention all refused, 400,000 earned ones all accepted, 600,000 increments exact"
  else
    bad "$lowering: stale exit $rc, '$out'"
  fi
done

# ---------------------------------------------------------------------
echo "== 3. tasks: results, failures, deadlines, cancellation =="
for lowering in processes threads; do
  flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
  for lvl in 0 2; do
    bin="$work/task-$lowering-O$lvl"
    if ! build "$bin" "$task" ${flags[@]+"${flags[@]}"} --opt "$lvl"; then
      bad "$lowering -O$lvl: task-load did not build"; sed 's/^/    /' "$bin.build" | head -8; continue
    fi
    rc=0; out="$(gate_timeout 120 "$bin" results 300 8 2>&1)" || rc=$?
    if [[ "$rc" == 0 && "$out" == "equal 300" ]]; then
      ok "$lowering -O$lvl: 300 answers equal the sequential ones, in submit order"
    else
      bad "$lowering -O$lvl: results exit $rc, '$out'"
    fi
  done
done

want_mixed='0 ok 0:0
1 ok 1:8
2 ok 2:18
3 err 72 task trapped
4 ok 4:44
5 err 1001 task past its deadline
6 err 1003 task answer over the byte limit
7 ok 7:98
survived'
want_slowtrap='0 ok 0:0
1 err 72 task trapped
2 ok 2:18
3 ok 3:30'
for lowering in processes threads; do
  bin="$work/task-$lowering-O2"
  [[ -x "$bin" ]] || { bad "$lowering: no task binary"; continue; }

  rc=0; out="$(gate_timeout 30 "$bin" mixed 2>/dev/null)" || rc=$?
  if [[ "$rc" == 0 && "$out" == "$want_mixed" ]]; then
    ok "$lowering: a trap (72), a deadline (1001) and an oversized answer (1003) each in its slot; siblings answered; the parent survived"
  else
    bad "$lowering: mixed exit $rc:"; printf '%s\n' "$out" | sed 's/^/    /'
  fi

  rc=0; out="$(gate_timeout 20 "$bin" slowtrap 2>/dev/null)" || rc=$?
  if [[ "$rc" == 0 && "$out" == "$want_slowtrap" ]]; then
    ok "$lowering: a task that traps with no deadline and is not the oldest is found by looking at the child"
  elif [[ "$rc" == 124 ]]; then
    bad "$lowering: slowtrap never answered - a death without an answer went unseen"
  else
    bad "$lowering: slowtrap exit $rc:"; printf '%s\n' "$out" | sed 's/^/    /'
  fi

  rc=0; out="$(gate_timeout 30 "$bin" deadline 2>/dev/null)" || rc=$?
  pids="$(field "$out" pids)"
  if [[ "$rc" == 0 && "$(field "$out" gone)" == 2 && "$(printf '%s\n' "$out" | grep -c 'err 1001 task past its deadline')" == 2 ]] && gone $pids; then
    ok "$lowering: two tasks past a 200 ms deadline answered 1001; both pids ($pids) gone before the pool returned and after"
  else
    bad "$lowering: deadline exit $rc: $(printf '%s' "$out" | tr '\n' ';')"
    kill -KILL $pids 2>/dev/null || true
  fi

  rc=0; out="$(gate_timeout 30 "$bin" cancel 2>/dev/null)" || rc=$?
  pids="$(field "$out" pids)"; ms="$(field "$out" ms)"
  if [[ "$rc" == 0 && "$(field "$out" 0)" == "ok stopped" && "$(field "$out" 1)" == "err 1002 task cancelled" \
        && "$(printf '%s\n' "$out" | grep -c 'err 1002 task not started')" == 6 && "$(field "$out" gone)" == 1 \
        && "$ms" =~ ^[0-9]+$ ]] && (( ms < 3000 )) && gone $pids; then
    ok "$lowering: cancelled from a sibling binding at 300 ms: the cooperative task stopped, the stubborn one was killed after the grace, six never started ($ms ms)"
  else
    bad "$lowering: cancel exit $rc: $(printf '%s' "$out" | tr '\n' ';')"
    kill -KILL $pids 2>/dev/null || true
  fi

  # A grace of the largest Int is "for ever", not a negative number: a
  # conversion to microseconds that wrapped killed the task at once.
  rc=0; out="$(gate_timeout 30 "$bin" grace 9223372036854775807 2>/dev/null)" || rc=$?
  if [[ "$rc" == 0 && "$out" == "0 ok finished" ]]; then
    ok "$lowering: a grace of the largest Int let the cancelled task finish"
  else
    bad "$lowering: grace max exit $rc, '$out' - wanted '0 ok finished'"
  fi

  # Written to a FILE: the stuck task's process outlives the answer
  # until its deadline, and a `$(...)` would wait on its pipe too.
  rc=0; gate_timeout 30 "$bin" stuck > "$work/stuck-$lowering.out" 2>/dev/null || rc=$?
  out="$(cat "$work/stuck-$lowering.out")"; ms="$(field "$out" ms)"
  if [[ "$rc" == 0 && "$(field "$out" 0)" == "ok answered" && "$ms" =~ ^[0-9]+$ ]] && (( ms < 3000 )); then
    ok "$lowering: a task that answered and could not exit was ended by its 300 ms deadline, answer kept ($ms ms)"
  else
    bad "$lowering: stuck exit $rc, '$(printf '%s' "$out" | tr '\n' ';')' - wanted '0 ok answered' well before 3 s"
  fi

  rc=0; out="$(gate_timeout 30 "$bin" failfast 2>/dev/null)" || rc=$?
  ms="$(field "$out" ms)"
  if [[ "$rc" == 0 && "$(field "$out" 1)" == "err 72 task trapped" && "$(printf '%s\n' "$out" | grep -c 'err 1002')" == 5 \
        && "$(field "$out" gone)" == 2 && "$ms" =~ ^[0-9]+$ ]] && (( ms < 3000 )); then
    ok "$lowering: fail-fast: one trap cancelled the pool, two stuck tasks killed, three never started ($ms ms)"
  else
    bad "$lowering: failfast exit $rc: $(printf '%s' "$out" | tr '\n' ';')"
  fi
done

# ---------------------------------------------------------------------
echo "== 4. no child outlives the call =="
for lowering in processes threads; do
  bin="$work/task-$lowering-O2"
  [[ -x "$bin" ]] || continue
  rc=0; out="$(gate_timeout 30 "$bin" parenttrap 2>/dev/null)" || rc=$?
  pids="$(field "$out" pids)"
  sleep 0.3
  if [[ "$rc" == 72 && -n "$pids" ]] && gone $pids; then
    ok "$lowering: the parent trapped (72) mid-pool and took both running tasks ($pids) with it"
  else
    bad "$lowering: parenttrap exit $rc, pids '$pids' - $(for p in $pids; do kill -0 "$p" 2>/dev/null && echo "$p alive"; done)"
    kill -KILL $pids 2>/dev/null || true
  fi
done
# The control: a parent SIGKILLed from outside runs no sweep.
bin="$work/task-processes-O2"
if [[ -x "$bin" ]]; then
  "$bin" orphan > "$work/orphan.out" 2>/dev/null &
  parent=$!
  for _ in $(seq 1 100); do
    grep -q '^pids' "$work/orphan.out" 2>/dev/null && break
    sleep 0.1
  done
  pids="$(field "$(cat "$work/orphan.out")" pids)"
  kill -KILL "$parent" 2>/dev/null; wait "$parent" 2>/dev/null
  sleep 0.3
  alive=0; for p in $pids; do kill -0 "$p" 2>/dev/null && alive=$((alive + 1)); done
  if [[ -n "$pids" && "$alive" == 2 ]]; then
    ok "control: a parent SIGKILLed from outside leaves its two tasks alive ($pids) - the check above can see a survivor"
  else
    bad "control: after SIGKILL of the parent, $alive of '$pids' alive - wanted both (the stated limit)"
  fi
  kill -KILL $pids 2>/dev/null || true
fi
# Under --threads the registry is per thread, so a trap in a SIBLING
# thread ends the process having swept only its own children. The
# process-wide kill list takes the pool's task down anyway.
# The output goes to a FILE, as `orphan`'s does: the task that outlives
# the program inherits its stdout, and a `$(...)` would wait for that
# pipe's end for as long as the task lives.
bin="$work/task-threads-O2"
if [[ -x "$bin" ]]; then
  rc=0; gate_timeout 30 "$bin" siblingtrap > "$work/sibling.out" 2>/dev/null || rc=$?
  out="$(cat "$work/sibling.out")"
  pids="$(field "$out" pids)"
  sleep 0.3
  alive=0; for p in $pids; do kill -0 "$p" 2>/dev/null && alive=$((alive + 1)); done
  if [[ "$rc" == 72 && -n "$pids" && "$alive" == 0 ]]; then
    ok "threads: a sibling thread's trap (72) took the pool's running task ($pids) with it - the kill list"
  else
    bad "threads: siblingtrap exit $rc, pids '$pids', $alive still alive - a trap in one thread left another thread's task running"
  fi
  kill -KILL $pids 2>/dev/null || true
fi
# A thread started inside a forked child: a raw fork's child, a task's
# body, and a task that answers and then cannot exit. On Darwin the first
# two died with SIGSEGV while the runtime forked with the raw system
# call; the third blocked the pool. Output to a FILE, as above.
tif="$repo_root/tests/litmus/thread-in-fork.ax"
want_tif='raw fork: 42
task: ran
stuck task: answered'
for lowering in processes threads; do
  flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
  bin="$work/tif-$lowering"
  if ! build "$bin" "$tif" ${flags[@]+"${flags[@]}"} --opt 2; then
    bad "$lowering: thread-in-fork did not build"; sed 's/^/    /' "$bin.build" | head -6; continue
  fi
  rc=0; gate_timeout 30 "$bin" > "$bin.out" 2>/dev/null || rc=$?
  if [[ "$rc" == 0 && "$(cat "$bin.out")" == "$want_tif" ]]; then
    ok "$lowering: a thread started inside a raw fork's child, a task's body and a stuck task, and each answered"
  else
    bad "$lowering: thread-in-fork exit $rc, '$(tr '\n' ';' < "$bin.out")'"
  fi
  pkill -KILL -f "$bin" 2>/dev/null || true
done

# ---------------------------------------------------------------------
echo "== 5. retained memory does not grow with the tasks run =="
bin="$work/task-processes-O2"
if [[ -x "$bin" ]]; then
  small="$(max_rss_kb "$bin" fold 500 8)" || small=""
  large="$(max_rss_kb "$bin" fold 5000 8)" || large=""
  ksmall="$(max_rss_kb "$bin" keep 500 8)" || ksmall=""
  klarge="$(max_rss_kb "$bin" keep 5000 8)" || klarge=""
  if [[ "$small" =~ ^[0-9]+$ && "$large" =~ ^[0-9]+$ && "$ksmall" =~ ^[0-9]+$ && "$klarge" =~ ^[0-9]+$ ]]; then
    if (( large - small <= 1024 )); then
      ok "taskFold: peak RSS ${small} KiB at 500 tasks and ${large} KiB at 5,000 (4 KiB answers)"
    else
      bad "taskFold: peak RSS ${small} KiB at 500 tasks but ${large} KiB at 5,000 - something is kept per task"
    fi
    if (( klarge - ksmall >= 8192 )); then
      ok "control: taskMap keeping the same answers grew from ${ksmall} to ${klarge} KiB - the measurement sees retention"
    else
      bad "control: taskMap keeping every answer grew only ${ksmall} -> ${klarge} KiB - the RSS reading is blind"
    fi
  else
    bad "RSS unreadable ('$small', '$large', '$ksmall', '$klarge')"
  fi
fi

# ---------------------------------------------------------------------
echo "== 6. ablations: each turns its check red =="
# ablate <kind> <program>: a copy of the stdlib with one rule removed and
# <program> built against it. `AXIOM_STDLIB` names the copy, and the IR
# must differ from the tree's, or the copy was not what compiled.
ablate() {
  local kind="$1" prog="$2" dir="$work/abl-$1"
  rm -rf "$dir"; mkdir -p "$dir"
  cp -R "$repo_root/stdlib" "$dir/stdlib"
  cp "$prog" "$dir/prog.ax"
  python3 - "$dir/stdlib" "$kind" <<'PY' || return 1
import sys, os
root, kind = sys.argv[1], sys.argv[2]
cuts = {
  "lock": [("Sync.ax",
    "    (if (== (syncLoad m 3) 1)\n      (Err (mkError syncOwnerDead \"mutexLock: the holder died holding it\"))\n      (let ((me syncMe))\n        (if (== (syncCas m 0 me) 0)",
    "    (if (== (syncLoad m 3) 1)\n      (Err (mkError syncOwnerDead \"mutexLock: the holder died holding it\"))\n      (let ((me syncMe))\n        (if (== 0 0)")],
  "timed": [("Sys.ax", "      (/ (+ nanos 999) 1000))))", "      (/ (+ nanos 999) 10000))))"),
            ("Sys.ax", "(memSetWord ts 0 (/ nanos 1000000000))", "(memSetWord ts 0 (/ (/ nanos 10) 1000000000))"),
            ("Sys.ax", "(memSetWord ts 1 (% nanos 1000000000))", "(memSetWord ts 1 (% (/ nanos 10) 1000000000))")],
  "holder": [("Sync.ax", "(if (== (errCode e) 3)", "(if (== (errCode e) 99999)")],
  # The mutex never asks `waitid` about its own child: a zombie holder
  # looks alive to its parent too (AN-56 as it was).
  "synclook": [("Sync.ax", "          (if (syncChildEnded owner)", "          (if false")],
  "kill": [("Task.ax", "(sysKill (taskHandlePid (vecGet hs s)) 9)", "(sysKill (taskHandlePid (vecGet hs s)) 0)")],
  # The pid `__spawn_pid` reads through the handle, moved past every
  # kernel's pid_max: the same miss as a wrong word of the page, with
  # nothing to hit. (Another word would be worse: an address whose low
  # 32 bits `kill` could read as 0 or negative, a process GROUP.)
  "layout": [("Task.ax", "(fn (taskHandlePid h)\n  (__spawn_pid h))", "(fn (taskHandlePid h)\n  (+ (__spawn_pid h) 1073741824))")],
  "look": [("Sys.ax", "(Ok (!= (& (memGetWord buf 0) 4294967295) 0))", "(Ok false)")],
  "slot": [("Task.ax", "(let ((slot (+ slab (* (% arg w) slotBytes))))", "(let ((slot (+ slab (* (% (+ arg 1) w) slotBytes))))")],
  "limit": [("Task.ax", "            (if (> len limit)", "            (if (> len (* limit 1000))")],
  "grace": [("Task.ax", "(if (&& (== cancelling 1) (>= now graceEnd))", "(if (&& (== cancelling 2) (>= now graceEnd))")],
  # The unlock compares the guard COUNTER again, as it first did.
  "guard": [("Sync.ax", "(if (|| (<= guard 0) (!= (syncCasAt m 1 guard 0) guard))", "(if (|| (<= guard 0) (|| (== (syncLoad m 0) 0) (!= (syncLoad m 2) guard)))")],
  # A task is joined on its answer alone, as it first was.
  "exitjoin": [("Task.ax", "        ((Ok b)\n          (if b\n            1\n            (if answered\n              2\n              0))", "        ((Ok b)\n          (if (|| b answered)\n            1\n            0)")],
  # A refused spawn traps past the pool again: no recovery point.
  "spawnrp": [("Task.ax", "  (region r\n    (__axiom_recover\n      __axiom_arena_mark\n      (lambda (x) (taskWordOf (__proc_spawn wrapper arg))))))", "  (taskWordOf (__proc_spawn wrapper arg)))")],
  # A refused spawn no longer cancels the pool.
  "refusecancel": [("Task.ax", "                  {\n                    (set cancelling 1)\n                    (set graceEnd (+ now graceUs))\n                  }\n                  0)", "                  0\n                  0)")],
  # The checked pool no longer kills its running slots on a refusal.
  "parkill": [("Par.ax", "(parKill (vecGet hs (% k w)))", "0")],
  # The microseconds conversion rounds without saturating.
  "micros": [("Task.ax", "    (if (> nanos 9223372036854774808)\n      9223372036854776\n      (/ (+ nanos 999) 1000))", "    (/ (+ nanos 999) 1000)")],
  # Section 10. The pool delivers each answer when it joins the task,
  # in the order it finds them ended, and not in submit order: the
  # completion-order fold MM-PAR-14 rules out.
  "completion": [("Task.ax", "                        {\n                          (set progress 1)\n                          (if (&& (== r 1) opts.failFast)", "                        {\n                          (taskDeliver sink scoped st s slab slotBytes)\n                          (set progress 1)\n                          (if (&& (== r 1) opts.failFast)"),
                 ("Task.ax", "                (taskDeliver\n                  sink\n                  scoped\n                  st\n                  (% head w)\n                  slab\n                  slotBytes)\n", "                0\n")],
  # Section 10. The raising pool's drain joins newest first.
  "drain": [("Par.ax", "      (while (< joined n)\n        {\n          (vecPush out (__proc_join (vecGet hs (% joined w))))", "      (while (< joined n)\n        {\n          (vecPush out (__proc_join (vecGet hs (% (- n (+ joined 1)) w))))")],
}[kind]
for f, old, new in cuts:
    p = os.path.join(root, f)
    s = open(p, encoding="utf-8").read()
    if s.count(old) != 1:
        sys.exit("seam %r in %s found %d times, wanted 1" % (old[:50], f, s.count(old)))
    s = s.replace(old, new)
    open(p, "w", encoding="utf-8").write(s)
PY
  (cd "$dir" && AXIOM_STDLIB="$dir/stdlib" "$axc" build --opt 2 --input prog.ax --output "$dir/prog") > "$dir/build.log" 2>&1 || return 1
  (cd "$dir" && AXIOM_STDLIB="$dir/stdlib" "$axc" emit-llvm prog.ax -o "$dir/prog.ll") > /dev/null 2>&1
  (cd "$repo_root" && "$axc" emit-llvm "$prog" -o "$dir/tree.ll") > /dev/null 2>&1
  if cmp -s "$dir/prog.ll" "$dir/tree.ll"; then
    echo "    the ablated build emitted the tree's IR" > "$dir/build.log"; return 1
  fi
}

# red <kind> <what the check wanted>: report an ablation's verdict. $rc
# and $out are the ablated run's; `$3` is 1 when the check passed.
red() {
  local kind="$1" passed="$2"
  if (( passed )); then
    bad "$kind: the ablated library still passed ('${out:0:100}', exit $rc) - the check is blind to it"
  elif [[ "$rc" == 124 ]]; then
    ok "$kind: red - no answer before the deadline"
  else
    ok "$kind: red - exit $rc, '$(printf '%s' "${out:0:100}" | tr '\n' ';')'"
  fi
}

run_ablation() {
  local kind="$1" prog="$2"; shift 2
  if ! ablate "$kind" "$prog"; then
    bad "$kind: the ablation did not apply or build"; sed 's/^/    /' "$work/abl-$kind/build.log" 2>/dev/null | head -6; return 1
  fi
  rc=0; out="$(gate_timeout "$@" 2>/dev/null)" || rc=$?
  return 0
}

if run_ablation lock "$sync" 60 "$work/abl-lock/prog" excl 1 "$N"; then
  red lock "$([[ "$rc" == 0 && "$out" == "count $((4 * N)) ok" ]] && echo 1 || echo 0)"
fi
if run_ablation timed "$sync" 30 "$work/abl-timed/prog" timed "$T"; then
  line="$(field "$out" recv-timeout)"; us="${line##* }"
  red timed "$([[ "$us" =~ ^[0-9]+$ ]] && (( us >= T * 1000 )) && echo 1 || echo 0)"
fi
if run_ablation holder "$sync" 30 "$work/abl-holder/prog" dead; then
  red holder "$([[ "$(field "$out" dead-timed)" == 1004\ * ]] && echo 1 || echo 0)"
fi
if run_ablation synclook "$sync" 10 "$work/abl-synclook/prog" zombie; then
  red synclook "$([[ "$(field "$out" zombie-timed)" == 1004\ * ]] && echo 1 || echo 0)"
  pkill -KILL -f "$work/abl-synclook/prog" 2>/dev/null || true
fi
if run_ablation kill "$task" 20 "$work/abl-kill/prog" deadline; then
  red kill "$([[ "$rc" == 0 && "$(field "$out" gone)" == 2 ]] && echo 1 || echo 0)"
  pkill -KILL -f "$work/abl-kill/prog" 2>/dev/null || true
fi
if run_ablation layout "$task" 20 "$work/abl-layout/prog" deadline; then
  red layout "$([[ "$rc" == 0 && "$(field "$out" gone)" == 2 ]] && echo 1 || echo 0)"
  pkill -KILL -f "$work/abl-layout/prog" 2>/dev/null || true
fi
if run_ablation look "$task" 10 "$work/abl-look/prog" slowtrap; then
  red look "$([[ "$rc" == 0 && "$out" == "$want_slowtrap" ]] && echo 1 || echo 0)"
  pkill -KILL -f "$work/abl-look/prog" 2>/dev/null || true
fi
if run_ablation slot "$task" 60 "$work/abl-slot/prog" results 300 8; then
  red slot "$([[ "$rc" == 0 && "$out" == "equal 300" ]] && echo 1 || echo 0)"
fi
if run_ablation limit "$task" 30 "$work/abl-limit/prog" mixed; then
  red limit "$([[ "$rc" == 0 && "$out" == "$want_mixed" ]] && echo 1 || echo 0)"
fi
if run_ablation grace "$task" 10 "$work/abl-grace/prog" cancel; then
  red grace "$([[ "$rc" == 0 && "$(field "$out" gone)" == 1 ]] && echo 1 || echo 0)"
  pkill -KILL -f "$work/abl-grace/prog" 2>/dev/null || true
fi
if run_ablation guard "$sync" 30 "$work/abl-guard/prog" misuse; then
  out="$(printf '%s' "$out" | tr '\n' ' ')"
  red guard "$([[ "$rc" == 0 && "$out" == *"stale-in-window 1005 still-held 1 " ]] && echo 1 || echo 0)"
fi
if run_ablation micros "$task" 30 "$work/abl-micros/prog" grace 9223372036854775807; then
  red micros "$([[ "$rc" == 0 && "$out" == "0 ok finished" ]] && echo 1 || echo 0)"
fi
# The stuck task's run goes to a file, as in section 3, and whatever
# the ablated pool left behind is killed after it.
if ablate exitjoin "$task"; then
  rc=0; gate_timeout 10 "$work/abl-exitjoin/prog" stuck > "$work/abl-exitjoin/out" 2>/dev/null || rc=$?
  out="$(cat "$work/abl-exitjoin/out")"
  red exitjoin "$([[ "$rc" == 0 && "$(field "$out" 0)" == "ok answered" ]] && echo 1 || echo 0)"
  pkill -KILL -f "$work/abl-exitjoin/prog" 2>/dev/null || true
else
  bad "exitjoin: the ablation did not apply or build"; sed 's/^/    /' "$work/abl-exitjoin/build.log" 2>/dev/null | head -6
fi

# ---------------------------------------------------------------------
echo "== 7. the examples run and check themselves =="
for ex in pipeline typed-tasks cancel; do
  src="$repo_root/examples/concurrency/$ex.ax"
  for lowering in processes threads; do
    flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
    bin="$work/ex-$ex-$lowering"
    if ! build "$bin" "$src" ${flags[@]+"${flags[@]}"}; then
      bad "examples/concurrency/$ex.ax ($lowering) did not build"; sed 's/^/    /' "$bin.build" | head -8; continue
    fi
    rc=0; out="$(gate_timeout 60 "$bin" 2>/dev/null)" || rc=$?
    if [[ "$rc" == 0 && "$(printf '%s\n' "$out" | tail -1)" == ok ]]; then
      ok "examples/concurrency/$ex.ax ($lowering): $(printf '%s\n' "$out" | tail -2 | head -1)"
    else
      bad "examples/concurrency/$ex.ax ($lowering): exit $rc"; printf '%s\n' "$out" | tail -6 | sed 's/^/    /'
    fi
  done
done

# ---------------------------------------------------------------------
echo "== 8. the runtime's half, ablated in the compiler =="
# ablate_cc <tag> <python old> <python new>: a compiler built from a copy
# of self_host/ with one exact string replaced - aborting when the
# string is not there, so a drill that silently did not apply cannot
# pass as one that could not fail.
ablate_cc() {
  local tag="$1" old="$2" new="$3" dir="$work/cc-$1"
  rm -rf "$dir"; mkdir -p "$dir"
  cp -R "$repo_root/self_host" "$dir/self_host"
  python3 - "$dir/self_host/codegen.ax" "$old" "$new" <<'PY' || return 1
import sys
p, old, new = sys.argv[1], sys.argv[2].encode().decode("unicode_escape"), sys.argv[3].encode().decode("unicode_escape")
s = open(p, encoding="utf-8").read()
if s.count(old) != 1:
    sys.exit("seam %r found %d times" % (old[:60], s.count(old)))
open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
  gate_build_tree "$axc" "$dir" "$repo_root/stdlib" "$dir/axc" > "$dir/build.log" 2>&1
}
if ablate_cc gkill '          (emitLine cg "  call void @__axiom_par_gkill()")' '          0'; then
  (cd "$repo_root" && "$work/cc-gkill/axc" build --threads --opt 2 --input "$task" --output "$work/cc-gkill/prog") > "$work/cc-gkill/prog.build" 2>&1
  rc=0; gate_timeout 30 "$work/cc-gkill/prog" siblingtrap > "$work/cc-gkill/out" 2>/dev/null || rc=$?
  pids="$(field "$(cat "$work/cc-gkill/out")" pids)"
  sleep 0.3
  alive=0; for p in $pids; do kill -0 "$p" 2>/dev/null && alive=$((alive + 1)); done
  if [[ "$rc" == 72 && -n "$pids" && "$alive" == 1 ]]; then
    ok "gkill: red - with the abort's kill-list sweep deleted, the sibling trap left the task alive ($pids)"
  else
    bad "gkill: the ablated compiler's run exit $rc, pids '$pids', $alive alive - the check cannot see a surviving task"
  fi
  kill -KILL $pids 2>/dev/null || true
else
  bad "gkill: the compiler ablation did not apply or build"; tail -4 "$work/cc-gkill/build.log" 2>/dev/null | sed 's/^/    /'
fi
case "$(uname -s)" in
  Darwin)
    fx="$repo_root/tests/litmus/thread-in-fork.ax"
    if ablate_cc libcfork ';@axiom:effect(unsafe)\n(pub fn (parLibcFork cg)\n  (if (cgThreads cg)\n    (let ((t (memGetWord cg 26)))\n      (if (|| (== t 0) (== t 1))\n        1\n        0))\n    0))' '(pub fn (parLibcFork cg)\n  (if (cgThreads cg)\n    0\n    0))'; then
      (cd "$repo_root" && "$work/cc-libcfork/axc" build --input "$fx" --output "$work/cc-libcfork/prog") > "$work/cc-libcfork/prog.build" 2>&1
      rc=0; gate_timeout 30 "$work/cc-libcfork/prog" > "$work/cc-libcfork/out" 2>/dev/null || rc=$?
      if [[ "$rc" != 0 ]] && ! grep -q '^raw fork: 42$' "$work/cc-libcfork/out"; then
        ok "libcfork: red - forking with the raw system call again, a thread inside the child died (exit $rc)"
      else
        bad "libcfork: the raw-fork compiler's fixture exit $rc, '$(tr '\n' ';' < "$work/cc-libcfork/out")' - the fixture cannot see the crash"
      fi
      pkill -KILL -f "$work/cc-libcfork/prog" 2>/dev/null || true
    else
      bad "libcfork: the compiler ablation did not apply or build"; tail -4 "$work/cc-libcfork/build.log" 2>/dev/null | sed 's/^/    /'
    fi
    ;;
  *)
    echo "n/a  libcfork: a raw fork leaves a thread working in the child on $(uname -s), so this drill cannot go red here (not counted)"
    ;;
esac

# ---------------------------------------------------------------------
echo "== 9. a spawn refused mid-pool: children killed and reaped, mappings back =="
# tests/litmus/pool-refuse.ax fills the runtime's handle table but for
# K slots, so the pool's Kth spawn is refused - the path a fork the
# kernel refuses takes too - while earlier tasks run for a minute. The
# program prints `ready PID` and waits; while it lives, every pid its
# tasks printed must be gone (a child it had not reaped would still
# answer `kill -0`), and it must have no child left at all (`pgrep -P`).
# Its handle slots must all come back, and its address space must not
# grow with the rounds: each round's slab is 4 x 32 MiB, so a pool that
# kept its mappings grows by 128 MiB a round.
refuse="$repo_root/tests/litmus/pool-refuse.ax"
# live <out> <cmd...>: run it in the background; at `ready`, record its
# VSZ (KiB) in $live_vsz, how many printed pids still answer in
# $live_alive, its children in $live_kids; then wait for it, in $live_rc.
live() {
  local out="$1" bg pid p i; shift
  "$@" > "$out" 2> "$out.err" &
  bg=$!
  for i in $(seq 1 600); do
    grep -q '^ready ' "$out" 2>/dev/null && break
    kill -0 "$bg" 2>/dev/null || break
    sleep 0.05
  done
  pid="$(sed -n 's/^ready //p' "$out")"
  live_vsz=""; live_alive=0; live_kids=""; live_pids=""
  if [[ -n "$pid" ]]; then
    live_vsz="$(ps -o vsz= -p "$pid" | tr -d ' ')"
    live_kids="$(pgrep -P "$pid" | tr '\n' ' ')"
  fi
  for p in $(sed -n 's/^pid //p' "$out"); do
    live_pids="$live_pids $p"
    kill -0 "$p" 2>/dev/null && live_alive=$((live_alive + 1))
  done
  live_rc=0
  ( sleep 60; kill -KILL "$bg" 2>/dev/null ) &
  local dog=$!
  wait "$bg" || live_rc=$?
  kill "$dog" 2>/dev/null; wait "$dog" 2>/dev/null
  for p in $live_pids; do kill -KILL "$p" 2>/dev/null; done
  return 0
}
# answers <out>: the answer lines and round lines, one per line.
answers() { grep -v '^pid \|^ready ' "$1"; }
want_task='0 err 1002 task cancelled
1 err 1002 task cancelled
2 err 78 task not started: its spawn was refused
3 err 1002 task not started: the pool was cancelled'
want_checked='0 err 137 parallel slot killed: a later spawn was refused
1 err 137 parallel slot killed: a later spawn was refused
2 err 78 parallel slot not started: its spawn was refused
3 err 78 parallel slot not started: its spawn was refused'
MIB32=33554432
for lowering in processes threads; do
  flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
  bin="$work/refuse-$lowering"
  if ! build "$bin" "$refuse" ${flags[@]+"${flags[@]}"} --opt 2; then
    bad "$lowering: pool-refuse did not build"; sed 's/^/    /' "$bin.build" | head -8; continue
  fi
  # One round and eight: the answers, the pids, the handles, the VSZ.
  live "$work/refuse-$lowering-1.out" "$bin" task 3 4 4 1 "$MIB32" 1
  v1="$live_vsz"; out="$(answers "$work/refuse-$lowering-1.out")"
  n1="$(wc -w <<< "$live_pids" | tr -d ' ')"
  if [[ "$live_rc" == 0 && "$out" == "$want_task"$'\n'"round 0 status 1004 free 3" && "$n1" == 2 && "$live_alive" == 0 && -z "$live_kids" ]]; then
    ok "$lowering taskMap: the third spawn refused; it answered 78, the two running tasks ($live_pids ) were killed and reaped before the pool returned, the fourth never started, and all 3 handle slots came back"
  else
    bad "$lowering taskMap refusal: exit $live_rc, pids [$live_pids ] $live_alive alive, children [$live_kids], '$(tr '\n' ';' <<< "$out")'"
  fi
  live "$work/refuse-$lowering-8.out" "$bin" task 3 4 4 8 "$MIB32" 1
  v8="$live_vsz"; out="$(answers "$work/refuse-$lowering-8.out")"
  rounds_ok="$(grep -c '^round [0-7] status 1004 free 3$' <<< "$out")"
  if [[ "$live_rc" == 0 && "$rounds_ok" == 8 && "$v1" =~ ^[0-9]+$ && "$v8" =~ ^[0-9]+$ ]] && (( v8 - v1 < 65536 )); then
    ok "$lowering taskMap: eight refused rounds, every handle back each time; VSZ ${v1} KiB after one round and ${v8} after eight - no slab or token page kept"
  else
    bad "$lowering taskMap: eight rounds: exit $live_rc, $rounds_ok of 8 rounds whole, VSZ ${v1:-?} -> ${v8:-?} KiB (a kept 128 MiB slab a round shows as 917,504 KiB)"
  fi
  # The checked pool: the refused slot and the ones after answer 78, the
  # running ones are killed and joined in order.
  live "$work/refuse-$lowering-c.out" "$bin" checked 2 4 4 1
  out="$(answers "$work/refuse-$lowering-c.out")"
  if [[ "$live_rc" == 0 && "$out" == "$want_checked"$'\n'"round 0 status 1004 free 2" && "$live_alive" == 0 && -z "$live_kids" ]]; then
    ok "$lowering parMapWordsChecked: the third spawn refused; two running slots killed and joined (137), two never started (78), both handles back"
  else
    bad "$lowering parMapWordsChecked refusal: exit $live_rc, pids [$live_pids ] $live_alive alive, children [$live_kids], '$(tr '\n' ';' <<< "$out")'"
  fi
  # The raising pool: the refusal raises 78 to the caller's recovery
  # point, and the runtime's sweep is its cleanup.
  live "$work/refuse-$lowering-r.out" "$bin" raising 2 4 4 1
  out="$(answers "$work/refuse-$lowering-r.out")"
  if [[ "$live_rc" == 0 && "$out" == "round 0 status 78 free 2" && "$live_alive" == 0 && -z "$live_kids" ]]; then
    ok "$lowering parMapWords: the refusal raised 78 to the recovery point, the sweep killed and reaped its children, both handles back"
  else
    bad "$lowering parMapWords refusal: exit $live_rc, pids [$live_pids ] $live_alive alive, children [$live_kids], '$(tr '\n' ';' <<< "$out")'"
  fi
done
# The KERNEL refusing: the fold's first step lowers RLIMIT_NPROC to 1,
# so the next fork answers EAGAIN, and `ulimit -u 1` refuses the first.
# Root is exempt from the limit, so under root this says so and counts
# nothing, as check-parallel.sh §12d does.
case "$(uname -s)-$(uname -m)" in
  Darwin-*) lim=(33554626 33554627 7) ;;
  Linux-x86_64) lim=(97 160 6) ;;
  Linux-aarch64) lim=(163 164 6) ;;
  *) lim=() ;;
esac
bin="$work/refuse-processes"
if [[ "$(id -u)" == 0 ]]; then
  echo "SKIP 9 kernel: running as root, which RLIMIT_NPROC does not bind - nothing was refused, and this is not a pass"
elif [[ ${#lim[@]} == 0 ]]; then
  echo "SKIP 9 kernel: no setrlimit numbers for $(uname -s)-$(uname -m) here"
elif [[ -x "$bin" ]]; then
  live "$work/refuse-kernel.out" "$bin" kernel "${lim[@]}" 1
  out="$(answers "$work/refuse-kernel.out")"
  want='0 ok first
limit lowered 0
1 err 1002 task cancelled
2 err 78 task not started: its spawn was refused
3 err 1002 task not started: the pool was cancelled
round 0 status 1004 free 0'
  if [[ "$live_rc" == 0 && "$out" == "$want" && -n "$live_pids" && "$live_alive" == 0 && -z "$live_kids" ]]; then
    ok "kernel: with RLIMIT_NPROC lowered mid-pool the kernel refused the third fork; it answered 78, the running task ($live_pids ) was killed and reaped, the fourth never started"
  else
    bad "kernel refusal mid-pool: exit $live_rc, pids [$live_pids ] $live_alive alive, children [$live_kids], '$(tr '\n' ';' <<< "$out")'"
  fi
  for mode in task checked; do
    args=(task -1 4 4 1 "$MIB32" 0); [[ "$mode" == checked ]] && args=(checked -1 4 4 0)
    rc=0; out="$(bash -c 'ulimit -u 1 && exec "$@"' _ "$bin" "${args[@]}" 2>/dev/null)" || rc=$?
    first="$(grep '^0 ' <<< "$out")"
    if [[ "$rc" == 0 && "$first" == "0 err 78 "* && "$(grep -c ' err ' <<< "$out")" == 4 ]] && grep -q '^round 0 status 1004 ' <<< "$out"; then
      ok "kernel $mode: under ulimit -u 1 the first fork was refused, and all four slots answered an error ($first)"
    else
      bad "kernel $mode under ulimit -u 1: exit $rc, '$(tr '\n' ';' <<< "$out")'"
    fi
  done
fi
# Ablations, each on a copy of the library (`ablate`, section 6). The
# recovery point around a task's spawn taken out: the refusal traps past
# the pool again, the recovery point answers 78, a handle slot and a
# slab stay behind every round.
if ablate spawnrp "$refuse"; then
  live "$work/abl-spawnrp/r1.out" "$work/abl-spawnrp/prog" task 3 4 4 1 "$MIB32" 1; a1="$live_vsz"
  live "$work/abl-spawnrp/r8.out" "$work/abl-spawnrp/prog" task 3 4 4 8 "$MIB32" 1; a8="$live_vsz"
  out="$(answers "$work/abl-spawnrp/r8.out")"
  whole="$(grep -c '^round [0-7] status 1004 free 3$' <<< "$out")"
  if [[ "$whole" == 8 ]]; then
    bad "spawnrp: without the recovery point the rounds still came back whole - the check cannot see the refusal escape"
  elif [[ "$a1" =~ ^[0-9]+$ && "$a8" =~ ^[0-9]+$ ]] && (( a8 - a1 >= 524288 )); then
    ok "spawnrp: red - the refusal trapped past the pool ('$(grep -m1 '^round' <<< "$out")'), and eight rounds kept $(( (a8 - a1) / 1024 )) MiB more than one"
  else
    bad "spawnrp: the rounds broke ('$(grep -m1 '^round' <<< "$out")') but the address space did not grow (${a1:-?} -> ${a8:-?} KiB) - the VSZ reading cannot see a kept slab"
  fi
else
  bad "spawnrp: the ablation did not apply or build"; sed 's/^/    /' "$work/abl-spawnrp/build.log" 2>/dev/null | head -6
fi
# The cancellation a refusal starts taken out: the pool starts what it
# can and then waits for tasks that run for a minute.
if run_ablation refusecancel "$refuse" 10 "$work/abl-refusecancel/prog" task 3 4 4 1 "$MIB32" 0; then
  red refusecancel "$([[ "$rc" == 0 && "$(answers <(printf '%s\n' "$out"))" == "$want_task"$'\n'"round 0 status 1004 free 3" ]] && echo 1 || echo 0)"
  pkill -KILL -f "$work/abl-refusecancel/prog" 2>/dev/null || true
fi
# The checked pool's kill taken out: its joins wait for the running slots.
if run_ablation parkill "$refuse" 10 "$work/abl-parkill/prog" checked 2 4 4 0; then
  red parkill "$([[ "$rc" == 0 && "$(answers <(printf '%s\n' "$out"))" == "$want_checked"$'\n'"round 0 status 1004 free 2" ]] && echo 1 || echo 0)"
  pkill -KILL -f "$work/abl-parkill/prog" 2>/dev/null || true
fi

# ---------------------------------------------------------------------
echo "== 10. determinism: ordered answers, float reductions, the first failure (MM-PAR-14) =="
# tests/litmus/par-determinism.ax adds 2,000 Float terms whose sum
# rounds differently in any other order. Each task sleeps up to 7 x J
# microseconds first, so at widths above 1 the tasks finish out of
# submit order; the ordered answers must not notice, and the
# completion-order ablation below must.
det="$repo_root/tests/litmus/par-determinism.ax"
DN=2000
DJ=100
DD=100000
for lowering in processes threads; do
  flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
  build "$work/det-$lowering" "$det" ${flags[@]+"${flags[@]}"} --opt 2 \
    || { bad "$lowering: par-determinism did not build"; sed 's/^/    /' "$work/det-$lowering.build" | head -8; }
done
build "$work/det-O0" "$det" --opt 0 || bad "par-determinism did not build at --opt 0"
seqline=""
[[ -x "$work/det-processes" ]] && seqline="$(gate_timeout 60 "$work/det-processes" seq "$DN" 2>/dev/null)"
read -r _ dseq _ drev _ dtree <<< "$seqline"
# A second implementation of the terms and the sums, in Python's IEEE
# doubles: the bits are IEEE 754's answer, not only this compiler's.
pyref="$(python3 - "$DN" "$DD" <<'PY'
import struct, sys
M = (1 << 64) - 1
def s64(x):
    x &= M
    return x - (1 << 64) if x >> 63 else x
def sar(x, k):
    return s64(x) >> k
def mix(i):
    z = s64(i * 7046029254386353131 + 1442695040888963407)
    a = s64((z ^ sar(z, 30)) * 5573014789349097917)
    b = s64((a ^ sar(a, 27)) * 1181783497276652981)
    return s64(b ^ sar(b, 31))
def pow2(e):
    x = 1.0
    for _ in range(abs(e)):
        x *= 2.0 if e > 0 else 0.5
    return x
def term(i):
    h = mix(i)
    mag = (1.0 + (float(h & 1048575) / 1048576.0 + 1.0 / float(i + 3))) * pow2((sar(h, 20) & 63) - 31)
    return (0.0 - mag) if (sar(h, 40) & 1) == 1 else mag
def bits(x):
    return struct.unpack('<q', struct.pack('<d', x))[0]
n = int(sys.argv[1])
def chunked(parts):
    acc = 0.0
    for k in range(parts):
        part = 0.0
        for i in range(n * k // parts, n * (k + 1) // parts):
            part = part + term(i)
        acc = acc + part
    return acc
acc = 0.0
for i in range(n - 1, -1, -1):
    acc = acc + term(i)
dot = 0.0
for i in range(int(sys.argv[2])):
    dot = float(i) * 1.0000001 + dot
print(bits(chunked(1)), bits(acc), *[bits(chunked(k)) for k in (2, 3, 4, 8)], bits(dot))
PY
)"
read -r pseq prev pc2 pc3 pc4 pc8 pdot <<< "$pyref"
if [[ -n "$dseq" && "$dseq" == "$pseq" && "$drev" == "$prev" ]]; then
  ok "the index-order sum of $DN terms is $dseq and the reverse-order sum $drev, as Python's IEEE doubles compute them"
else
  bad "sequential sums: the program says '$seqline', Python says index $pseq reverse $prev"
fi
if [[ -n "$dseq" && "$drev" != "$dseq" && "$dtree" != "$dseq" ]]; then
  ok "control: the reverse-order ($drev) and pairwise ($dtree) sums differ from index order - the data can see an order"
else
  bad "control: '$seqline' - the reverse or pairwise sum equals the index-order one, so no check below could see a reordering"
fi
# A multiply feeding an add, 100,000 times: the shape contraction would
# fuse and reassociation would split, which the controls below allow.
dots="$( [[ -x "$work/det-processes" ]] && gate_timeout 60 "$work/det-processes" dot "$DD" 2>/dev/null) / $( [[ -x "$work/det-O0" ]] && gate_timeout 60 "$work/det-O0" dot "$DD" 2>/dev/null)"
if [[ -n "$pdot" && "$dots" == "dot $pdot / dot $pdot" ]]; then
  ok "the sum of i x 1.0000001 over $DD terms is $pdot at --opt 0 and --opt 2, as Python computes it: one rounding per operation, in order"
else
  bad "the multiply-add sum answered '$dots', Python says $pdot"
fi
if [[ -x "$work/det-O0" && -n "$dseq" ]]; then
  got="$(gate_timeout 60 "$work/det-O0" seq "$DN" 2>/dev/null) / $(gate_timeout 120 "$work/det-O0" fold "$DN" 3 "$DJ" 2>/dev/null)"
  if [[ "$got" == "$seqline / fold $dseq" ]]; then
    ok "--opt 0 answers the same bits as --opt 2, sequentially and through taskFold at width 3"
  else
    bad "--opt 0 answered '$got', --opt 2 '$seqline'"
  fi
fi
# Every ordered answer, at every width, in both lowerings.
for lowering in processes threads; do
  bin="$work/det-$lowering"
  [[ -x "$bin" && -n "$dseq" ]] || continue
  for mode in fold map words checked; do
    wrong=""
    for w in 1 2 3 4 8; do
      j="$DJ"; (( w == 1 )) && j=0
      rc=0; out="$(gate_timeout 120 "$bin" "$mode" "$DN" "$w" "$j" 2>/dev/null)" || rc=$?
      [[ "$rc" == 0 && "$out" == "$mode $dseq" ]] || wrong="$wrong w$w:'$out'($rc)"
    done
    if [[ -z "$wrong" ]]; then
      ok "$lowering $mode: $DN answers added in submit order are the sequential sum's bits at widths 1, 2, 3, 4 and 8"
    else
      bad "$lowering $mode: not the sequential sum $dseq at$wrong"
    fi
  done
done
# `parallel` bindings: the same association as the sequential chunked
# sum, and a different one from index order when there are two or more.
for lowering in processes threads; do
  bin="$work/det-$lowering"
  [[ -x "$bin" ]] || continue
  wrong="" same=""
  for k in 1 2 3 4 8; do
    b="$(gate_timeout 60 "$bin" bind "$k" "$DN" 2>/dev/null)"
    c="$(gate_timeout 60 "$bin" chunked "$k" "$DN" 2>/dev/null)"
    want="$pseq"
    case "$k" in 2) want="$pc2" ;; 3) want="$pc3" ;; 4) want="$pc4" ;; 8) want="$pc8" ;; esac
    [[ "$b" == "bind $want" && "$c" == "chunked $want" ]] || wrong="$wrong K$k:'$b','$c' want $want"
    (( k > 1 )) && [[ "$want" == "$pseq" ]] && same="$same $k"
  done
  if [[ -z "$wrong" ]]; then
    ok "$lowering: 1, 2, 3, 4 and 8 bindings each answer the bits of the same chunked association computed in turn (and in Python)"
  else
    bad "$lowering bindings:$wrong"
  fi
done
if [[ -n "$pc2" && -z "$same" ]]; then
  ok "control: every chunked association of 2, 3, 4 and 8 parts differs from index order ($pc2, $pc3, $pc4, $pc8 against $pseq) - a different association is a different answer"
else
  bad "control: a chunked sum over parts [$same ] equals the index-order sum, so the bindings check cannot tell associations apart"
fi
# Several failures: the raising pool raises the lowest index's, every
# run and every width; the per-slot pools answer each in its slot.
want_fail='10 err 77
12 err 72
14 err 82
ok 37'
for lowering in processes threads; do
  bin="$work/det-$lowering"
  [[ -x "$bin" ]] || continue
  got=""
  for w in 1 2 3 4 8; do
    for _ in 1 2 3; do
      rc=0; gate_timeout 60 "$bin" fail-words 40 "$w" > /dev/null 2>&1 || rc=$?
      got="$got $rc"
    done
  done
  if [[ "$(printf '%s\n' $got | LC_ALL=C sort -u | tr -d '\n')" == 77 ]]; then
    ok "$lowering parMapWords: tasks 10 (77, last), 12 (72) and 14 (82) fail; the pool raised 77, the lowest index's, in all 15 runs at widths 1 to 8"
  else
    bad "$lowering parMapWords: exit statuses [${got# }], wanted 77 every time"
  fi
  for mode in fail-checked fail-tasks; do
    wrong=""
    for w in 1 3 8; do
      for _ in 1 2; do
        out="$(gate_timeout 60 "$bin" "$mode" 40 "$w" 2>/dev/null)"
        [[ "$out" == "$want_fail" ]] || wrong="$wrong w$w:'$(tr '\n' ';' <<< "$out")'"
      done
    done
    if [[ -z "$wrong" ]]; then
      ok "$lowering $mode: each of the three failures in its own slot with its own status, the 37 others their terms, in all 6 runs"
    else
      bad "$lowering $mode:$wrong"
    fi
  done
done
# failFast is the clock's: reported, not asserted.
bin="$work/det-processes"
if [[ -x "$bin" ]]; then
  : > "$work/ff.all"
  for _ in 1 2 3 4 5 6 7 8; do
    gate_timeout 60 "$bin" fail-fast 40 8 2>/dev/null | tr '\n' ';' >> "$work/ff.all"; echo >> "$work/ff.all"
  done
  echo "info fail-fast: 8 runs gave $(LC_ALL=C sort -u "$work/ff.all" | wc -l | tr -d ' ') distinct answers - which slots a cancellation reaches is the clock's (MM-PAR-14, not checked)"
fi
# The floating-point half: what the emitter writes, what opt keeps and
# what llc makes of it. A contracted multiply-add or a reassociated sum
# is a different answer, and none may appear unless the IR asks.
ird="$work/det-ir"; mkdir -p "$ird"
case "$(uname -m)" in
  arm64|aarch64) fused='fmadd|fmsub|fnmadd|fnmsub|fmla|fmls'; vsum='faddp|fadd[[:space:]]+v[0-9]+\.2d|fadd\.2d'; mattr="" ;;
  *) fused='vfmadd|vfmsub|vfnmadd|vfnmsub'; vsum='addpd|haddpd'; mattr="-mattr=+fma" ;;
esac
if (cd "$repo_root" && "$axc" emit-llvm "$det" -o "$ird/det.ll") > /dev/null 2>&1; then
  nflag="$(grep -cE '= f(add|sub|mul|div|rem|neg) (fast|reassoc|contract|nnan|ninf|nsz|arcp|afn)|llvm\.fmuladd|llvm\.fma\.|-fp-math"="true"' "$ird/det.ll")"
  nfadd="$(grep -cE '= f(add|mul|div) double' "$ird/det.ll")"
  if [[ "$nflag" == 0 ]] && (( nfadd >= 10 )); then
    ok "the emitted IR has $nfadd float adds, multiplies and divides and not one fast-math flag, fmuladd or fp-math attribute"
  else
    bad "the emitted IR: $nflag fast-math marks over $nfadd float operations"
  fi
  held=1
  for lvl in 1 2 3; do
    opt -O"$lvl" "$ird/det.ll" -S -o "$ird/det.O$lvl.ll" 2>/dev/null || { held=0; bad "opt -O$lvl refused the IR"; continue; }
    n="$(grep -cE '= f(add|sub|mul|div|rem|neg)( [a-z]+)* (fast|reassoc|contract|arcp|afn)|llvm\.fmuladd|llvm\.fma\.' "$ird/det.O$lvl.ll")"
    [[ "$n" == 0 ]] || { held=0; bad "opt -O$lvl wrote $n reassociating or contracting marks"; }
  done
  llc -O3 $mattr "$ird/det.O3.ll" -o "$ird/det.s" 2>/dev/null || held=0
  nf="$(grep -cE "$fused" "$ird/det.s")"; nv="$(grep -cE "$vsum" "$ird/det.s")"
  if (( held )) && [[ "$nf" == 0 && "$nv" == 0 ]]; then
    ok "opt -O1 to -O3 added no reassociating or contracting mark (nnan, ninf and nsz may be inferred where proved), and llc -O3 fused no multiply-add and vectorised no sum"
  else
    bad "after opt and llc -O3: $nf fused multiply-adds, $nv vector or pairwise adds"
  fi
  # Controls: the same IR asking for contraction, then reassociation,
  # must show each in the machine code, or the counts above are blind.
  for mark in contract reassoc; do
    sed -E "s/= (fadd|fmul) double/= \1 $mark double/" "$ird/det.ll" > "$ird/det.$mark.ll"
    opt -O3 "$ird/det.$mark.ll" -S -o "$ird/det.$mark.O3.ll" 2>/dev/null \
      && llc -O3 $mattr "$ird/det.$mark.O3.ll" -o "$ird/det.$mark.s" 2>/dev/null
    pat="$fused"; [[ "$mark" == reassoc ]] && pat="$vsum"
    n="$(grep -cE "$pat" "$ird/det.$mark.s" 2>/dev/null || true)"
    if [[ "$n" =~ ^[0-9]+$ ]] && (( n > 0 )); then
      ok "control: the IR marked '$mark' shows $n $([[ "$mark" == contract ]] && echo fused multiply-adds || echo vector or pairwise adds) - the count above can see it"
    else
      bad "control: the IR marked '$mark' shows none (${n:-?}) - the machine-code check is blind to it"
    fi
  done
else
  bad "par-determinism would not emit IR"
fi
# Ablations. A pool that delivers in completion order must answer a
# different sum at some width above 1 (rounds repeat, since a width
# whose tasks happened to finish in order shows nothing).
if ablate completion "$det"; then
  seen=""
  for round in 1 2 3; do
    for w in 2 3 4 8; do
      out="$(gate_timeout 120 "$work/abl-completion/prog" fold "$DN" "$w" "$DJ" 2>/dev/null)"
      [[ -n "$out" && "$out" != "fold $dseq" ]] && seen="$seen w$w:${out#fold }"
    done
    [[ -n "$seen" ]] && break
  done
  if [[ -n "$seen" ]]; then
    ok "completion: red - delivered in completion order, taskFold answered other bits ($seen) against $dseq"
  else
    bad "completion: three rounds of a completion-order fold all answered $dseq - the check cannot see a reordering"
  fi
  pkill -KILL -f "$work/abl-completion/prog" 2>/dev/null || true
else
  bad "completion: the ablation did not apply or build"; sed 's/^/    /' "$work/abl-completion/build.log" 2>/dev/null | head -6
fi
if ablate drain "$det"; then
  rc=0; gate_timeout 60 "$work/abl-drain/prog" fail-words 16 8 > /dev/null 2>&1 || rc=$?
  if [[ "$rc" != 77 ]]; then
    ok "drain: red - joined newest first, the raising pool raised $rc, not the lowest index's 77"
  else
    bad "drain: the reversed drain still raised 77 - the check cannot see the join order"
  fi
else
  bad "drain: the ablation did not apply or build"; sed 's/^/    /' "$work/abl-drain/build.log" 2>/dev/null | head -6
fi

echo
if (( failed > 0 )); then
  echo "check-task: $failed failed, $checks passed"
  exit 1
fi
echo "check-task: $checks checks - the mutex excludes in both lowerings, timed waits"
echo "            keep time, every task failure is a value in its slot, no child"
echo "            outlives the pool, memory is flat, ordered answers and float"
echo "            reductions are the sequential bits, and every ablation turns it red"
