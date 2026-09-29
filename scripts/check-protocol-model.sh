#!/usr/bin/env bash
# The channel, mutex and task-pool protocols: every interleaving in a
# model, and the deadlock and starvation limits on the machine (R-E1,
# R-C2, R-C2a; docs/memory-model.md MM-PAR-10 to MM-PAR-13).
#
# `stdlib/Chan.ax` and `stdlib/Sync.ax` build a channel and a mutex from
# the five atomics and a kernel wait on a word, and `stdlib/Task.ax` a
# pool of forked tasks with deadlines and cancellation. `check-chan.sh`,
# `check-task.sh` and `check-race.sh` run them under load and see the
# interleavings the hardware happened to make. This gate explores all of
# them at small bounds, in `scripts/lib/protocol-model.py` and the pool's
# `scripts/lib/task_model.py`, and then measures on the real binary what
# the load gates do not: deadlock and starvation, apart from races.
#
# FIVE SECTIONS.
#
#   1. The model. Every interleaving of two and three bindings running
#      the transcribed protocols, at the bounds the model's `scenarios`
#      states (capacities 1 and 2, one to four words, one- and two-slice
#      time budgets; more under --long), with spurious wakeups, timeouts,
#      kills and reaps as environment steps; and the task pool with two
#      and three tasks at widths 1 to 3, each task's body one of seven
#      behaviours, and a clock. Every scenario must be clean: mutual
#      exclusion, exactly-once FIFO delivery, close and end of stream,
#      the mutex's guard and poisoning, the channel's poisoning only by a
#      holder that died holding its lock, every task answering exactly
#      its own slot in submit order, at most `w` children and `w`
#      handles, nothing started after a cancellation, no sleep past a
#      running task's deadline or a cancellation's grace, every child
#      reaped when the pool returns, and no lost wakeup, deadlock or
#      livelock in the model's terms. Floors: the scenario count, the
#      states explored, a kernel wait reached in every scenario, and
#      every transcribed step executed but the three the model names as
#      unreachable. AN-10's scenario - a sender killed holding the
#      channel's lock - must be clean.
#   2. Planted defects. Each protocol mistake the design exists to
#      prevent - a waiter that parks after releasing the lock, a changer
#      that reads the waiter count before its change, a release or a
#      notify that wakes nobody, a lock taken by a plain load and store,
#      a waiter that sleeps without its mark, a guard compared with the
#      counter, a dead-holder test that does not re-read the word, a
#      mutex waiter that never asks `waitid` about its own child; the
#      channel's dead-holder test, its sliced lock wait, its look at the
#      waiter's own child and its poisoning compare-and-swap each taken
#      back; and the pool's deadline kill, its wake times, its grace
#      kill, its wait for an exit, its slot, its stop on cancellation,
#      its bounded handles and its reaping, each broken - must be found
#      as the kind of failure it is, with its schedule printed.
#   3. The transcription. Every operation the model cites must still be
#      in its function in stdlib/, in the model's order, and every
#      function that touches a channel or mutex word, or a task's
#      process, must be modelled or excused. Four mutated copies of the
#      library must each fail it.
#   4. Replay. An instrumented copy of Chan.ax records every operation
#      on a channel word in the order it happened;
#      tests/litmus/chan-trace.ax runs five forked bindings on it, and
#      the model must accept the record operation by operation, each
#      answer the model's. A planted change the program's own count
#      cannot see (a change counter that counts in twos), and a record
#      with one operation cut, must each be refused.
#   5. Liveness on the machine, tests/litmus/liveness.ax, both lowerings:
#      four bindings contending on one mutex for a long run, exact, with
#      the shares and the worst waits REPORTED (the mutex is not fair,
#      AN-17); a lock-order inversion between two mutexes and a pair of
#      channels each waiting on the other, where the timed calls must
#      all answer sysTimedOut within [T, T + 800 ms], the untimed ones
#      must be killed by a watchdog with no process left, and the same
#      programs in a safe order must finish. And the lost-wakeup
#      signature, counted: a copy of Sync.ax that counts every lock wait
#      the 100 ms slice ended, reported under contention, with a timed
#      inversion as the control that must count some.
#
# LIMITS. The model is a proof about the model, at its bounds: every
# access is one step in a sequentially consistent order, the kernel
# wait is futex's compare-and-sleep, and Linux's 32-bit compare, pid
# reuse, a zombie seen by any process but its parent, and anything
# larger than the bounds are outside it. The task pool's clock is the
# model's: it moves only while the pool waits and nothing else can
# step. Sections 3 and 4 tie it to the source and to one run of the
# channel; the mutex and the pool have no replay. Section 5 is the runs made, on
# this host: a zero is evidence, and the shares are a measurement, not a
# promise either way.
#
# Usage: check-protocol-model.sh [--long]
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

long=0
[[ "${1:-}" == --long ]] && long=1

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

model="$repo_root/scripts/lib/protocol-model.py"
if (( long )); then
  want_scenarios=109; want_states=6900000; budget=3600; trace_n=300; starve_ms=5000
else
  want_scenarios=86; want_states=1300000; budget=900; trace_n=50; starve_ms=1500
fi
# Every transcribed step the scenarios execute, and the operations the
# transcription check matches: what they are on the tree today.
want_reached=585
want_matched=311

# ---------------------------------------------------------------------
echo "== 1. the model: every interleaving of the real protocols =="
rc=0; gate_timeout "$budget" python3 "$model" run $( ((long)) && echo --long ) > "$work/run.txt" 2>&1 || rc=$?
scenarios=0
while IFS= read -r line; do
  name="$(sed -E 's/^clean (.*[^ ]) +states .*/\1/' <<< "$line")"
  states="$(sed -E 's/.* states +([0-9]+) .*/\1/' <<< "$line")"
  asleep="$(sed -E 's/.* asleep +([0-9]+)$/\1/' <<< "$line")"
  scenarios=$((scenarios + 1))
  if (( asleep > 0 )); then
    ok "$name: clean in $states states, a binding asleep in $asleep"
  else
    bad "$name: clean in $states states, and no binding ever slept - the kernel wait was never reached"
  fi
done < <(grep '^clean ' "$work/run.txt")
if grep -q '^FAIL ' "$work/run.txt"; then
  bad "the model found a failure in the real protocols:"
  sed -n '/^FAIL /,/^\(clean\|TOTAL\)/p' "$work/run.txt" | sed 's/^/    /'
fi
total="$(sed -nE 's/^TOTAL scenarios ([0-9]+) states ([0-9]+) .*/\2/p' "$work/run.txt")"
if [[ -z "$total" ]]; then
  bad "the model did not finish (exit $rc):"; tail -12 "$work/run.txt" | sed 's/^/    /'
else
  if (( scenarios >= want_scenarios )); then
    ok "$scenarios scenarios explored (floor $want_scenarios)"
  else
    bad "$scenarios scenarios explored, fewer than the floor of $want_scenarios"
  fi
  if (( total >= want_states )); then
    ok "$total states explored in all (floor $want_states)"
  else
    bad "$total states explored in all, fewer than the floor of $want_states"
  fi
fi
cov="$(grep '^COVERAGE ' "$work/run.txt")"
reached="$(sed -nE 's/.* reached ([0-9]+) .*/\1/p' <<< "$cov")"
gaps="$(sed -nE 's/.* gaps ([0-9]+)$/\1/p' <<< "$cov")"
grep -E '^(unreached|UNREACHED) ' "$work/run.txt" | sed 's/^/     /'
if [[ "$gaps" == 0 && -n "$reached" ]] && (( reached >= want_reached )); then
  ok "every transcribed step executed but the excused ones: ${cov#COVERAGE }"
else
  bad "coverage: '${cov:-none}' (want gaps 0 and at least $want_reached reached)"
fi
an10="$(sed -n 's/^AN10 //p' "$work/run.txt")"
an10_states="$(sed -nE 's/^AN-10 .*: ([0-9]+) states$/\1/p' "$work/run.txt")"
if [[ "$an10" == clean && -n "$an10_states" ]]; then
  ok "AN-10 closed: a sender killed anywhere, the lock held or not, and every timed receive still answers ($an10_states states)"
else
  bad "AN-10: the model should find the killed sender's scenario clean, and found '${an10:-nothing}':"
  sed -n '/^AN-10 /,/^AN10 /p' "$work/run.txt" | sed '1d;$d' | sed 's/^/  /'
fi

# ---------------------------------------------------------------------
echo "== 2. planted defects: each found, as what it is, with its schedule =="
rc=0; gate_timeout "$budget" python3 "$model" defects > "$work/defects.txt" 2>&1 || rc=$?
for name in "park after release" "notify reads the announcement before the change" \
            "chan release without a wake" "chan notify without a wake" "chan lock by load then store" \
            "chan dead-holder test removed" "chan lock wait without a slice" "chan child look removed" \
            "chan poison without its compare-and-swap" \
            "task deadline kill removed" "task wake ignores deadlines" "task grace kill removed" \
            "task joined on its answer alone" "task answers into its neighbour's slot" \
            "task started after the cancellation" "task handle pushed for every task" \
            "task killed and not joined" "task wake ignores the grace" \
            "mutex release without a wake" "mutex lock by load then store" "mutex waiter without its mark" \
            "mutex guard compared with the counter" "mutex dead-holder test without its re-read" \
            "mutex child look removed"; do
  line="$(grep -F "RED $name:" "$work/defects.txt" | head -1)"
  if [[ -n "$line" ]]; then
    ok "${line#RED }"
    awk -v head="RED $name:" 'index($0, head) == 1 {on = 1; next} /^(RED|FAIL|REPORT) / {on = 0} on' \
      "$work/defects.txt" | sed 's/^/  /'
  else
    bad "$name: not found - $(grep -F "$name:" "$work/defects.txt" | head -1)"
  fi
done
grep '^FAIL ' "$work/defects.txt" | while IFS= read -r line; do echo "     $line"; done
if grep -q '^FAIL ' "$work/defects.txt"; then
  bad "a planted defect was missed or found as the wrong kind (above)"
fi
grep '^REPORT ' "$work/defects.txt" | sed 's/^REPORT /     reported: /'

# ---------------------------------------------------------------------
echo "== 3. the transcription: what the model cites is still in stdlib/ =="
rc=0; python3 "$model" transcription "$repo_root/stdlib" > "$work/tx.txt" 2>&1 || rc=$?
grep -v '^SOURCE ' "$work/tx.txt"
summary="$(grep '^SOURCE ' "$work/tx.txt")"
matched="$(sed -nE 's/^SOURCE matched ([0-9]+) failures ([0-9]+)$/\1/p' <<< "$summary")"
if [[ "$rc" == 0 && "$summary" == *" failures 0" ]] && (( matched >= want_matched )); then
  ok "$matched cited operations found in their functions, in the model's order (floor $want_matched)"
else
  bad "the transcription: '${summary:-no answer}' (exit $rc)"
fi
# Each control mutates a copy of the library in a way that still
# compiles, and the check must fail naming the function.
python3 - "$repo_root/stdlib" "$work/tx" <<'PY' || bad "the transcription controls could not be made"
import os, shutil, sys
src, base = sys.argv[1], sys.argv[2]
cuts = {
  # chanSend and chanRecv park after releasing the lock.
  "park": ("Chan.ax", "                (let ((seen (chanPark ch)))\n                  {\n                    (chanUnlock ch me)\n                    (chanSleep ch seen)\n                  }))))))",
           "                {\n                  (chanUnlock ch me)\n                  (let ((seen (chanPark ch)))\n                    (chanSleep ch seen))\n                }))))", 2),
  # mutexUnlock's contended release wakes nobody.
  "wake": ("Sync.ax", "            (syncStore m 0 0)\n            (sysWakeWord m)\n            (Ok 0)", "            (syncStore m 0 0)\n            (Ok 0)", 1),
  # A task's deadline kill sends signal 0 (check-task.sh's kill ablation).
  "kill": ("Task.ax", "(sysKill (taskHandlePid (vecGet hs s)) 9)", "(sysKill (taskHandlePid (vecGet hs s)) 0)", 1),
  # A new function reads the lock word.
  "new": ("Chan.ax", "(pub :: chanCap (-> Chan Int))",
          "(pub :: chanPeekLock (-> Int Int))\n;@axiom:effect(unsafe)\n(pub fn (chanPeekLock ch)\n  (__atomic_load ch))\n\n(pub :: chanCap (-> Chan Int))", 1),
}
for kind, (f, old, new, count) in cuts.items():
    d = os.path.join(base, kind)
    shutil.rmtree(d, ignore_errors=True)
    shutil.copytree(src, d)
    p = os.path.join(d, f)
    s = open(p, encoding="utf-8").read()
    if s.count(old) != count:
        sys.exit("seam %s: found %d times, wanted %d" % (kind, s.count(old), count))
    open(p, "w", encoding="utf-8").write(s.replace(old, new))
PY
for pair in "park:chanSend" "wake:mutexUnlock" "kill:taskKillJoin" "new:chanPeekLock"; do
  kind="${pair%%:*}"; fn="${pair#*:}"
  [[ -d "$work/tx/$kind" ]] || continue
  rc=0; out="$(python3 "$model" transcription "$work/tx/$kind" --quiet 2>&1)" || rc=$?
  if [[ "$rc" != 0 ]] && grep -q "^FAIL .* $fn" <<< "$out"; then
    ok "control $kind: red - $(grep -m1 "^FAIL .* $fn" <<< "$out" | sed 's/^FAIL //')"
  else
    bad "control $kind: the transcription check passed a library whose $fn changed ('$(tail -1 <<< "$out")')"
  fi
done

# ---------------------------------------------------------------------
echo "== 4. replay: a recorded run of the channel, step by step through the model =="
trace_prog="$repo_root/tests/litmus/chan-trace.ax"
# traced <dir> [plant]: a traced copy of the library and the program built on it.
traced() {
  local dir="$1" plant="${2:-}"
  rm -rf "$dir"; mkdir -p "$dir"
  cp -R "$repo_root/stdlib" "$dir/stdlib"
  cp "$trace_prog" "$dir/chan-trace.ax"
  python3 "$model" instrument "$dir/stdlib" ${plant:+--plant "$plant"} > "$dir/instrument.txt" 2>&1 || return 1
  (cd "$dir" && AXIOM_STDLIB="$dir/stdlib" "$axc" build --opt 2 --input chan-trace.ax --output "$dir/trace") \
    > "$dir/build.log" 2>&1
}
# The program is also a plain load test against the tree's library.
if (cd "$repo_root" && "$axc" build --opt 2 --input "$trace_prog" --output "$work/trace-tree") > "$work/trace-tree.build" 2>&1; then
  rc=0; out="$(gate_timeout 60 "$work/trace-tree" 2 "$trace_n" 2>&1)" || rc=$?
  if [[ "$rc" == 0 && "$out" == "ok "* && "$out" != *trace* ]]; then
    ok "chan-trace on the tree's library: '$out', and no record"
  else
    bad "chan-trace on the tree's library: exit $rc, '${out:0:120}'"
  fi
else
  bad "chan-trace did not build:"; head -8 "$work/trace-tree.build" | sed 's/^/    /'
fi
if traced "$work/traced"; then
  sed 's/^/     /' "$work/traced/instrument.txt"
  for cap in 1 2; do
    rec="$work/traced/record-$cap.txt"
    rc=0; gate_timeout 120 "$work/traced/trace" "$cap" "$trace_n" > "$rec" 2>&1 || rc=$?
    if [[ "$rc" != 0 ]] || ! grep -q '^ok ' "$rec"; then
      bad "cap $cap: the traced run failed: exit $rc, '$(head -1 "$rec")'"; continue
    fi
    rc=0; out="$(python3 "$model" replay "$rec" 2>&1)" || rc=$?
    events="$(sed -nE 's/^REPLAY events ([0-9]+) failures 0$/\1/p' <<< "$out")"
    waits="$(sed -nE 's/.*wait ([0-9]+).*/\1/p' <<< "$(grep '^REPLAY operations' <<< "$out")")"
    grep '^REPLAY \(bindings\|operations\)' <<< "$out" | sed 's/^/     /'
    if [[ "$rc" == 0 && -n "$events" && -n "$waits" ]] && (( events >= 20 * trace_n && waits > 0 )); then
      ok "cap $cap: $events recorded operations replayed, each the model's step with the model's answer, $waits of them kernel waits"
    else
      bad "cap $cap: the replay refused the record or it was too small (floor $((20 * trace_n)) operations, a wait):"
      sed 's/^/    /' <<< "$out" | head -8
    fi
  done
  # A record with one operation cut out must be refused.
  rec="$work/traced/record-1.txt"
  if [[ -f "$rec" ]]; then
    awk '/^trace /{split($0, f, " "); print "trace " f[2] " " f[3] - 1 " " f[4]; seen = 1; next}
         seen && NF == 6 && ++k == 50 {next} {print}' "$rec" > "$work/traced/cut.txt"
    rc=0; out="$(python3 "$model" replay "$work/traced/cut.txt" 2>&1)" || rc=$?
    if [[ "$rc" != 0 ]] && grep -q '^FAIL ' <<< "$out"; then
      ok "control cut: red - $(grep -m1 '^FAIL ' <<< "$out" | sed 's/^FAIL //' | cut -c1-150)"
    else
      bad "control cut: a record missing its 50th operation still replayed"
    fi
  fi
else
  bad "the traced copy did not build:"; tail -8 "$work/traced/build.log" "$work/traced/instrument.txt" 2>/dev/null | sed 's/^/    /'
fi
# A library whose change counter counts in twos passes the program's own
# check, and the replay must refuse it.
if traced "$work/plant" bump-by-two; then
  rec="$work/plant/record.txt"
  rc=0; gate_timeout 120 "$work/plant/trace" 1 "$trace_n" > "$rec" 2>&1 || rc=$?
  own="$(grep -m1 '^\(ok\|bad\) ' "$rec")"
  rc=0; out="$(python3 "$model" replay "$rec" 2>&1)" || rc=$?
  if [[ "$rc" != 0 ]] && grep -q '^trace ' "$rec" && grep -q '^FAIL .*chanBump' <<< "$out"; then
    ok "control bump-by-two: the program said '$own'; the replay is red - $(grep -m1 '^FAIL ' <<< "$out" | sed 's/^FAIL //' | cut -c1-150)"
  else
    bad "control bump-by-two: the replay did not refuse the changed counter at chanBump: '$(grep -m1 '^FAIL\|^REPLAY events' <<< "$out")'"
  fi
else
  bad "the planted traced copy did not build"; tail -8 "$work/plant/build.log" 2>/dev/null | sed 's/^/    /'
fi

# ---------------------------------------------------------------------
echo "== 5. liveness on the machine: starvation and deadlock, apart from races =="
live="$repo_root/tests/litmus/liveness.ax"
# within <us> <T ms>: a timed call's answer time is in [T, T + 800] ms.
within() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 >= $2 * 1000 && $1 <= ($2 + 800) * 1000 )); }
for lowering in processes threads; do
  flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
  bin="$work/live-$lowering"
  if ! (cd "$repo_root" && "$axc" build ${flags[@]+"${flags[@]}"} --opt 2 --input "$live" --output "$bin") > "$bin.build" 2>&1; then
    bad "$lowering: liveness.ax did not build:"; head -8 "$bin.build" | sed 's/^/    /'; continue
  fi
  # Starvation: exact, and the distribution reported.
  rc=0; out="$(gate_timeout $((starve_ms / 1000 + 60)) "$bin" starve "$starve_ms" 2>&1)" || rc=$?
  if [[ "$rc" == 0 && "$(grep '^count ' <<< "$out")" == *" ok" ]]; then
    shares="$(grep '^binding ' <<< "$out" | awk '{print $4}' | sort -n | tr '\n' ' ')"
    worst="$(grep '^binding ' <<< "$out" | awk '{print $6}' | sort -n | tr '\n' ' ')"
    lo="${shares%% *}"; hi="$(awk '{print $NF}' <<< "$shares")"
    ok "$lowering starve ${starve_ms} ms: $(grep '^count ' <<< "$out" | sed 's/ ok$//') exact; acquisitions $shares(max/min $(awk -v a="$hi" -v b="$lo" 'BEGIN { if (b > 0) printf "%.2f", a / b; else print "inf" }')); worst waits ${worst}us"
    grep '^binding ' <<< "$out" | sed 's/^/     /'
  else
    bad "$lowering starve: exit $rc, '$(tail -1 <<< "$out")'"
  fi
  for what in inversion pair; do
    # Timed: both sides answer sysTimedOut within the bound.
    rc=0; out="$(gate_timeout 30 "$bin" "$what" timed 200 2>&1)" || rc=$?
    s1="$(grep '^side 1 [0-9-]* [0-9]*$' <<< "$out")"; s2="$(grep '^side 2 [0-9-]* [0-9]*$' <<< "$out")"
    set -- $s1; c1="${3:-}"; u1="${4:-}"
    set -- $s2; c2="${3:-}"; u2="${4:-}"
    if [[ "$rc" == 0 && "$c1" == 1001 && "$c2" == 1001 ]] && within "$u1" 200 && within "$u2" 200; then
      ok "$lowering $what timed 200 ms: both sides answer sysTimedOut, at ${u1} and ${u2} us"
    else
      bad "$lowering $what timed: exit $rc, '$(tr '\n' ';' <<< "$out")'"
    fi
    # Untimed: the documented deadlock; the watchdog must fire.
    rc=0; out="$(gate_timeout 2 "$bin" "$what" untimed 2>&1)" || rc=$?
    sleep 1
    left="$(pgrep -f "$bin" || true)"
    word=holds; [[ "$what" == pair ]] && word=waits
    if [[ "$rc" == 124 && -z "$left" ]] && grep -q "^side 1 $word$" <<< "$out" && grep -q "^side 2 $word$" <<< "$out"; then
      ok "$lowering $what untimed: both sides blocked on each other, the watchdog fired at 2 s and left no process"
    elif [[ "$rc" != 124 ]]; then
      bad "$lowering $what untimed: the deadlock ended by itself: exit $rc, '$(tr '\n' ';' <<< "$out")'"
    else
      bad "$lowering $what untimed: '$(tr '\n' ';' <<< "$out")', left '$left'"
      [[ -n "$left" ]] && kill -KILL $left 2>/dev/null
    fi
    # The control: the same program in an order that cannot deadlock.
    rc=0; out="$(gate_timeout 20 "$bin" "$what" ordered 2>&1)" || rc=$?
    if [[ "$rc" == 0 && "$(tail -1 <<< "$out")" == done ]]; then
      ok "$lowering $what ordered: the same program in a safe order finishes, so the watchdog above saw the deadlock"
    else
      bad "$lowering $what ordered: exit $rc, '$(tr '\n' ';' <<< "$out")'"
    fi
  done
done

# The lost-wakeup signature, counted. A lock wait the 100 ms slice ends
# with no wake is what a lost wake looks like to Sync.ax, which is built
# to survive one; a copy counts them, with how many found the lock free.
dir="$work/slices"
rm -rf "$dir"; mkdir -p "$dir"; cp -R "$repo_root/stdlib" "$dir/stdlib"; cp "$live" "$dir/liveness.ax"
if python3 - "$dir" <<'PY'
import os, sys
d = sys.argv[1]
def cut(path, old, new):
    s = open(path, encoding="utf-8").read()
    if s.count(old) != 1:
        sys.exit("seam in %s found %d times" % (path, s.count(old)))
    open(path, "w", encoding="utf-8").write(s.replace(old, new))
sync = os.path.join(d, "stdlib", "Sync.ax")
cut(sync, "                      (let ((code (sysWaitWordTimeout m w slice)))\n                        {",
    "                      (let ((code (sysWaitWordTimeout m w slice)))\n                        {\n"
    "                          (if (== code 1)\n                            {\n"
    "                              (__atomic_add (+ m 40) 1)\n"
    "                              (if (== (__atomic_load m) 0)\n                                (__atomic_add (+ m 48) 1)\n                                0)\n"
    "                            }\n                            0)")
# A mutex is a sealed handle, so the program reads the two counters
# through a reader the copy exports rather than from the page itself.
with open(sync, "a", encoding="utf-8") as f:
    f.write("\n(pub :: syncSliceCount (-> Mutex Int Int))\n;@axiom:effect(unsafe)\n"
            "(pub fn (syncSliceCount mx i)\n  (memGetWord (syncAt mx) i))\n")
prog = os.path.join(d, "liveness.ax")
# Printed before `(shares res)`, which stays the run's answer.
cut(prog, "            (shares res)\n",
    "            (let (\n              (n (syncSliceCount m 5))\n              (f (syncSliceCount m 6))\n            )\n"
    "              (println \"slice-timeouts {n} lock-free {f}\"))\n            (shares res)\n")
cut(prog, "                (println \"done\")\n                0\n              }\n            )\n            ((Err e) 3))",
    "                (println \"done\")\n                (let (\n                  (n (+ (syncSliceCount a 5) (syncSliceCount b 5)))\n                )\n"
    "                  (println \"slice-timeouts {n}\"))\n                0\n              }\n            )\n            ((Err e) 3))")
PY
then
  for lowering in processes threads; do
    flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
    if ! (cd "$dir" && AXIOM_STDLIB="$dir/stdlib" "$axc" build ${flags[@]+"${flags[@]}"} --opt 2 --input liveness.ax --output "$dir/live-$lowering") > "$dir/build-$lowering.log" 2>&1; then
      bad "$lowering: the counting copy did not build"; head -6 "$dir/build-$lowering.log" | sed 's/^/    /'; continue
    fi
    rc=0; out="$(gate_timeout 30 "$dir/live-$lowering" inversion timed 350 2>&1)" || rc=$?
    n="$(sed -nE 's/^slice-timeouts ([0-9]+)$/\1/p' <<< "$out")"
    if [[ "$rc" == 0 && -n "$n" ]] && (( n >= 6 )); then
      ok "$lowering: CONTROL - a 350 ms timed inversion counts $n slice timeouts, so the count can see one"
    else
      bad "$lowering: the slice counter saw '${n:-nothing}' in a 350 ms inversion (exit $rc) - it cannot see a timeout"
      continue
    fi
    rc=0; out="$(gate_timeout $((starve_ms / 1000 + 60)) "$dir/live-$lowering" starve "$starve_ms" 2>&1)" || rc=$?
    line="$(grep '^slice-timeouts ' <<< "$out")"
    if [[ "$rc" == 0 && -n "$line" ]]; then
      echo "     $lowering starve ${starve_ms} ms: $(grep '^count ' <<< "$out" | sed 's/ ok$//'); $line (reported)"
    else
      bad "$lowering: the counting starve run failed: exit $rc"
    fi
  done
else
  bad "the slice-counting copies could not be made"
fi

echo
if (( failed > 0 )); then
  echo "check-protocol-model: $failed failed, $checks passed"
  exit 1
fi
echo "check-protocol-model: $checks checks - the model finds no failure in the transcribed"
echo "                      channel, mutex and task pool and finds every planted one; the"
echo "                      transcription and a recorded run agree with it; timed calls end"
echo "                      deadlocks and untimed ones stay deadlocked"
