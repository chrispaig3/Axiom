#!/usr/bin/env bash
# The bounded channel between `parallel` bindings (R-C2, MM-PAR-10).
#
# `stdlib/Chan.ax` is a ring of words in a MAP_SHARED mapping, guarded
# by a futex-style lock, with an event counter a waiter sleeps on in the
# kernel (`sysWaitWord`: Linux `futex`, Darwin `__ulock_wait`). The
# fixture `tests/stdlib/528-chan.ax` pins its answers one binding at a
# time and across forked processes; this gate puts it under load and
# checks the properties a fixture cannot.
#
# SIX SECTIONS.
#
#   1. Load. tests/litmus/chan-load.ax sends 1..3N from three producers
#      to three consumers, at capacities 1 and 64, in BOTH lowerings
#      (forked children by default, threads under --threads), at --opt 0
#      and 2. Each run must report the exact count, sum and sum of
#      squares - a lost word and a duplicate cancel in the count and
#      cannot cancel in both sums - within a timeout, so a deadlock is a
#      failure with a name rather than a hung job. The consumers' shares
#      are printed: that is the starvation measurement, reported, not
#      asserted, because the channel promises no fairness.
#   2. Blocking. `wait` mode: a binding blocked in `sysWaitWord` while
#      its sibling spins ~200 ms must make at most three wait calls - a
#      wait that returned at once would make thousands.
#   2b. A wake reaches a sleeper. `wake` mode: eleven rounds of a
#      receiver asleep on an empty channel and a sender that sends one
#      word 20 ms in; the median time from the send to the receive's
#      return must be under 20 ms, in both lowerings. Measured in
#      microseconds on H3. It is the baseline section 4's `notify`
#      ablation is judged against.
#   3. A receive nobody can satisfy blocks, and stays blocked: `stuck`
#      mode must still be running after 2 s, in both lowerings, and the
#      deadline must leave no process behind. That is the documented
#      behaviour (no timeout exists), measured separately from the races
#      in section 1, as deadlock and data race are different failures.
#   4. Ablations, each on a COPY of the standard library, each required
#      to go red:
#        lock   - `chanLock` and `chanUnlock` answer 0 without touching
#                 the lock word: producers overwrite each other's slots,
#                 and section 1's load goes red.
#        notify - `chanNotify` wakes a word nobody sleeps on, so a
#                 sleeping receiver sees a send only when its 100 ms
#                 slice ends (`chanSliceNanos`, AN-10's dead-holder
#                 look): section 2b's median must reach 40 ms. This is
#                 also the proof that a waiter really sleeps in the
#                 kernel: one that spun would see the word at once. It
#                 used to be judged by section 1's load hanging, which
#                 stopped being true when waits became slices. A lost
#                 wake is a stall, and on linux-x86_64 the load finished
#                 inside its 20 s, twice.
#   5. Retained memory. The --threads load at N and 10N: peak RSS must
#      not grow by more than 8 MiB while ten times the words go through.
#   6. A binding that dies holding the lock (AN-10), in both lowerings,
#      tests/litmus/chan-dead.ax. `exact`: a forked holder takes the
#      lock word as `chanLock` does and is SIGKILLed and reaped with a
#      binding asleep on the ring and one asleep on the lock; each must
#      answer None, poisoned, within a second, a timed receive beside
#      the LIVE holder must answer sysTimedOut no sooner than asked, and
#      every call on the poisoned channel must answer its stated status.
#      `parent`: the holder killed and not reaped, a zombie, whose
#      parent's untimed receive must still find it dead. `sweep`:
#      recovered traps, each sweeping a binding that hammers the channel,
#      wherever it is, until five have left the lock held; every round
#      must answer, and at least one must have left it held, or the
#      check saw nothing. Ablations on a
#      copy of the library - the dead-holder test that never finds one,
#      and the look at the waiter's own child removed - must each leave
#      the probe with no answer.
#
# LIMITS. Load that passed is evidence on the runs made, on this host;
# the lock and the protocol are not proved. FreeBSD spins instead of
# blocking (`waitWordKind` 0) and is not run here. The channel carries
# words only, and `chanSend` and `chanRecv` have no timeout - the
# obligations `stdlib/Chan.ax`'s header states.
#
# Usage: check-chan.sh
set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

command -v python3 >/dev/null || { echo "FAIL: python3 is not on PATH"; exit 1; }

failed=0
checks=0
ok()  { echo "ok   $*"; checks=$((checks + 1)); }
bad() { echo "FAIL $*"; failed=$((failed + 1)); }

load="$repo_root/tests/litmus/chan-load.ax"
n=20000

# build <out> <flags...>: the load program, from the tree's stdlib.
build() {
  local out="$1"; shift
  (cd "$repo_root" && "$axc" build "$@" --input "$load" --output "$out") > "$out.build" 2>&1
}

# ---------------------------------------------------------------------
echo "== 1. load: 3 producers, 3 consumers, both lowerings =="
for lowering in processes threads; do
  flags=(); [[ "$lowering" == threads ]] && flags=(--threads)
  for lvl in 0 2; do
    bin="$work/load-$lowering-O$lvl"
    if ! build "$bin" ${flags[@]+"${flags[@]}"} --opt "$lvl"; then
      bad "$lowering -O$lvl: the load program did not build"; sed 's/^/    /' "$bin.build" | head -8; continue
    fi
    for cap in 1 64; do
      rc=0; out="$(gate_timeout 60 "$bin" stress "$cap" "$n" 2>&1)" || rc=$?
      if [[ "$rc" == 0 && "$out" == ok\ * ]]; then
        ok "$lowering -O$lvl cap $cap: $((3 * n)) words, every one received once (shares ${out#ok })"
      elif [[ "$rc" == 124 ]]; then
        bad "$lowering -O$lvl cap $cap: no answer in 60 s - a deadlock or a lost wake"
      else
        bad "$lowering -O$lvl cap $cap: exit $rc, '$out'"
      fi
    done
  done
done

# ---------------------------------------------------------------------
echo "== 2. a waiter blocks in the kernel =="
for lowering in processes threads; do
  bin="$work/load-$lowering-O2"
  [[ -x "$bin" ]] || { bad "$lowering: no binary for the wait probe"; continue; }
  rc=0; out="$(gate_timeout 30 "$bin" wait 2>&1)" || rc=$?
  calls="${out#wait calls }"
  if [[ "$rc" == 0 && "$calls" =~ ^[0-9]+$ ]] && (( calls >= 1 && calls <= 3 )); then
    ok "$lowering: blocked through ~200 ms in $calls wait call(s)"
  else
    bad "$lowering: '$out' (exit $rc) - a wait that returns at once spins"
  fi
done

# ---------------------------------------------------------------------
echo "== 2b. a send wakes a sleeping receiver =="
# wake_median <bin>: sets w_med and w_max (microseconds) from `wake`.
wake_median() {
  local rc=0 out
  w_med=""; w_max=""
  out="$(gate_timeout 30 "$1" wake 2>&1)" || rc=$?
  w_out="$out"
  [[ "$rc" == 0 ]] || return 1
  w_med="$(sed -nE 's/^wake median (-?[0-9]+) max (-?[0-9]+)$/\1/p' <<<"$out")"
  w_max="$(sed -nE 's/^wake median (-?[0-9]+) max (-?[0-9]+)$/\2/p' <<<"$out")"
  [[ "$w_med" =~ ^[0-9]+$ && "$w_max" =~ ^[0-9]+$ ]]
}
for lowering in processes threads; do
  bin="$work/load-$lowering-O2"
  [[ -x "$bin" ]] || { bad "$lowering: no binary for the wake probe"; continue; }
  if ! wake_median "$bin"; then
    bad "$lowering: the wake probe gave no reading: '$w_out'"
  elif (( w_med < 20000 )); then
    ok "$lowering: a send reaches a sleeping receiver in $w_med us at the median, $w_max us at worst, of 11"
  else
    bad "$lowering: a send reached a sleeping receiver in $w_med us at the median - a wake is being lost or delayed"
  fi
done

# ---------------------------------------------------------------------
echo "== 3. a receive nobody can satisfy stays blocked =="
# Both lowerings. Under processes the blocked receiver is a FORKED child,
# so this also holds `gate_timeout` to killing the whole process group:
# a timeout that killed only the parent left the child holding the
# output pipe, and section 1's "no answer in 60 s" could never fire for
# a cross-process deadlock (found by an independent review, fixed in
# scripts/lib/gate.sh). No process may outlive the deadline.
for lowering in processes threads; do
  bin="$work/load-$lowering-O2"
  [[ -x "$bin" ]] || { bad "$lowering: no binary for the stuck receive"; continue; }
  rc=0; out="$(gate_timeout 2 "$bin" stuck 2>&1)" || rc=$?
  sleep 1
  left="$(pgrep -f "$bin" || true)"
  if [[ "$rc" == 124 && -z "$left" ]]; then
    ok "$lowering: a receive nobody satisfies is still blocked at 2 s, and the deadline took every binding with it"
  elif [[ "$rc" != 124 ]]; then
    bad "$lowering: the stuck receive ended: exit $rc, '$out'"
  else
    bad "$lowering: timed out, but process(es) $left outlived the deadline"
    kill -KILL $left 2>/dev/null || true
  fi
done

# ---------------------------------------------------------------------
echo "== 4. ablations: each turns the load red =="
# ablate <kind>: a copy of the tree's stdlib with one rule removed, and
# the load built against it - `AXIOM_STDLIB` names the copy, because
# gate_init exported the tree's and the compiler reads that first (the
# IR comparison below is what caught it being ignored).
ablate() {
  local kind="$1" dir="$work/abl-$1"
  rm -rf "$dir"; mkdir -p "$dir"
  cp -R "$repo_root/stdlib" "$dir/stdlib"
  cp "$load" "$dir/chan-load.ax"
  python3 - "$dir/stdlib/Chan.ax" "$kind" <<'PY' || return 1
import sys
p, kind = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
cuts = {
  "lock": [
    # The unsafe claim goes with the compare-and-swap, the lock's one raw
    # operation, or the copy would not compile.
    (";@axiom:effect(unsafe)\n;@axiom:effect(block)\n(fn (chanLock ch me b timed)\n  (if (== (__atomic_cas ch 0 me) 0)", ";@axiom:effect(block)\n(fn (chanLock ch me b timed)\n  (if (== 0 0)"),
    ("(fn (chanUnlock ch me)\n  (if (== (__atomic_cas ch me 0) me)", "(fn (chanUnlock ch me)\n  (if (== me me)"),
  ],
  "notify": [
    # The wake goes to word 6, the closed flag, which nobody sleeps on;
    # the call stays, so the declaration's effects stay what it claims.
    ("    (sysWakeWord (+ ch 8))\n    0))", "    (sysWakeWord (+ ch 48))\n    0))"),
  ],
}[kind]
for old, new in cuts:
    if s.count(old) != 1:
        sys.exit("seam %r found %d times, wanted 1" % (old[:40], s.count(old)))
    s = s.replace(old, new)
open(p, "w", encoding="utf-8").write(s)
PY
  (cd "$dir" && AXIOM_STDLIB="$dir/stdlib" "$axc" build --threads --input chan-load.ax --output "$dir/load") > "$dir/build.log" 2>&1
}

for kind in lock notify; do
  if ! ablate "$kind"; then
    bad "$kind: the ablation did not apply or build"; sed 's/^/    /' "$work/abl-$kind/build.log" 2>/dev/null | head -6; continue
  fi
  # The copy must be what was compiled: its IR differs from the tree's.
  (cd "$work/abl-$kind" && AXIOM_STDLIB="$work/abl-$kind/stdlib" "$axc" emit-llvm chan-load.ax -o "$work/abl-$kind/load.ll") > /dev/null 2>&1
  (cd "$repo_root" && "$axc" emit-llvm "$load" -o "$work/tree-load.ll") > /dev/null 2>&1
  if cmp -s "$work/abl-$kind/load.ll" "$work/tree-load.ll"; then
    bad "$kind: the ablated build emitted the tree's IR - the copy was not what compiled"; continue
  fi
  if [[ "$kind" == notify ]]; then
    if ! wake_median "$work/abl-$kind/load"; then
      ok "$kind: red - the wake probe gave no answer: '${w_out:0:90}'"
    elif (( w_med >= 40000 )); then
      ok "$kind: red - a sleeping receiver saw the send $w_med us later at the median, the slice's end"
    else
      bad "$kind: the ablated channel still woke its receiver in $w_med us at the median - section 2b is blind to a lost wake"
    fi
    continue
  fi
  rc=0; out="$(gate_timeout 20 "$work/abl-$kind/load" stress 1 "$n" 2>&1)" || rc=$?
  if [[ "$rc" == 0 && "$out" == ok\ * ]]; then
    bad "$kind: the ablated channel still passed the load ('$out') - section 1 is blind to it"
  elif [[ "$rc" == 124 ]]; then
    ok "$kind: red - no answer in 20 s"
  else
    ok "$kind: red - exit $rc, '${out:0:90}'"
  fi
done

# ---------------------------------------------------------------------
echo "== 5. retained memory does not grow with the words sent =="
bin="$work/load-threads-O2"
if [[ -x "$bin" ]]; then
  small="$(max_rss_kb "$bin" stress 4 "$n")" || small=""
  large="$(max_rss_kb "$bin" stress 4 $((10 * n)))" || large=""
  if [[ "$small" =~ ^[0-9]+$ && "$large" =~ ^[0-9]+$ && "$small" -gt 0 ]]; then
    if (( large - small <= 8192 )); then
      ok "peak RSS ${small} KiB at $((3 * n)) words and ${large} KiB at $((30 * n))"
    else
      bad "peak RSS ${small} KiB at $((3 * n)) words but ${large} KiB at $((30 * n)) - something is retained per word"
    fi
  else
    bad "RSS unreadable ('$small', '$large')"
  fi
else
  bad "no threads binary for the RSS run"
fi

# ---------------------------------------------------------------------
echo "== 6. a binding that dies holding the lock (AN-10) =="
dead="$repo_root/tests/litmus/chan-dead.ax"
# The random sweep is required where it was measured to land (Darwin).
sweep_required=0; [[ "$(uname -s)" == Darwin ]] && sweep_required=1
# dead_build <dir> <lowering> [stdlib]: chan-dead.ax built into <dir>.
dead_build() {
  local dir="$1" lowering="$2" lib="${3:-$repo_root/stdlib}" f=()
  [[ "$lowering" == threads ]] && f=(--threads)
  mkdir -p "$dir"
  (cd "$repo_root" && AXIOM_STDLIB="$lib" "$axc" build ${f[@]+"${f[@]}"} --opt 2 --input "$dead" --output "$dir/dead-$lowering") \
    > "$dir/dead-$lowering.build" 2>&1
}
# line <text> <first word>: the rest of the first line starting with it.
line() { printf '%s\n' "$1" | awk -v k="$2" '$1 == k { $1 = ""; sub(/^ /, ""); print; exit }'; }
# soon <us>: answered within a second of the kill.
soon() { [[ "$1" =~ ^[0-9]+$ ]] && (( $1 <= 1000000 )); }
want_after='send 0
try-send 0
recv-none 1
try-recv-none 1
send-timed 1004
recv-timed 1004
close 0
closed 1
len 0
poisoned 1
free 1'
for lowering in processes threads; do
  if ! dead_build "$work/dead" "$lowering"; then
    bad "$lowering: chan-dead did not build"; head -8 "$work/dead/dead-$lowering.build" | sed 's/^/    /'; continue
  fi
  bin="$work/dead/dead-$lowering"
  # exact: a holder killed inside the lock, three bindings waiting on it.
  rc=0; out="$(gate_timeout 30 "$bin" exact 2>&1)" || rc=$?
  alive="$(line "$out" alive-timed)"; set -- $alive; acode="${1:-}"; aus="${2:-}"
  if [[ "$acode" == 1001 && "$aus" =~ ^[0-9]+$ ]] && (( aus >= 200000 && aus <= 1000000 )); then
    ok "$lowering: a timed receive while the holder lives answers sysTimedOut after $((aus / 1000)) ms of 200"
  else
    bad "$lowering: the timed receive beside a live holder answered '$alive' (exit $rc)"
  fi
  for who in ring-waiter lock-waiter; do
    got="$(line "$out" "$who")"; set -- $got
    if [[ "${1:-}" == none && "${2:-}" == poisoned && "${3:-}" == 1 ]] && soon "${4:-}"; then
      ok "$lowering: the $who asleep before the kill answered None, poisoned, $((${4} / 1000)) ms after it"
    else
      bad "$lowering: the $who answered '$got' (exit $rc) - wanted 'none poisoned 1' within a second of the kill"
    fi
  done
  dt="$(line "$out" dead-timed)"; set -- $dt
  if [[ "$rc" == 0 && "$(line "$out" holder-status)" == 137 && "${1:-}" == 1004 ]] && soon "${2:-}"; then
    ok "$lowering: the holder died of SIGKILL (137), and the killer's timed receive answered chanOwnerDead after $((${2} / 1000)) ms"
  else
    bad "$lowering: exact exit $rc: $(printf '%s' "$out" | tr '\n' ';')"
  fi
  after="$(printf '%s\n' "$out" | sed -n '/^send /,$p')"
  if [[ "$after" == "$want_after" ]]; then
    ok "$lowering: on the poisoned channel send and try-send answer False, the receives None, the timed forms 1004, close changes nothing, closed is True, len 0, and it frees"
  else
    bad "$lowering: the poisoned channel's answers: '$(tr '\n' ';' <<< "$after")'"
  fi
  # parent: the holder killed and not reaped, a zombie only its parent
  # can see through.
  rc=0; out="$(gate_timeout 30 "$bin" parent 2>&1)" || rc=$?
  got="$(line "$out" parent-untimed)"; set -- $got
  if [[ "$rc" == 0 && "${1:-}" == none && "${3:-}" == 1 ]] && soon "${4:-}"; then
    ok "$lowering: a zombie holder's parent: its untimed receive answered None, poisoned, $((${4} / 1000)) ms after the kill"
  else
    bad "$lowering: parent exit $rc, '$(tr '\n' ';' <<< "$out")'"
  fi
  # sweep: AN-10 as it happens, a recovered trap's sweep killing a
  # binding wherever it is in its calls on the channel.
  # The lock is held for nanoseconds of each call, so most rounds miss
  # it; the probe runs until five rounds left it held, or 2,000 rounds.
  rc=0; out="$(gate_timeout 120 "$bin" sweep 2000 2>&1)" || rc=$?
  set -- $(line "$out" sweep)
  if [[ "$rc" == 0 && "${1:-}" =~ ^[0-9]+$ && "${3:-}" =~ ^[0-9]+$ && "${5:-}" =~ ^[0-9]+$ && "${7:-}" == 0 && "${9:-}" =~ ^[0-9]+$ ]] \
      && (( ${3} >= 1 && ${3} + ${5} == ${1} && ${9} <= 1000 )); then
    ok "$lowering: $1 recovered traps swept a binding mid-channel: $3 left the lock held and were poisoned, $5 clean, every call answered within ${9} ms"
  elif [[ "$rc" == 0 && "${3:-}" == 0 && "${5:-}" == "${1:-x}" && "${7:-}" == 0 ]] && (( ! sweep_required )); then
    # Reported, not required, off Darwin: a sweep lands inside the lock
    # only by chance, and on linux-aarch64 under podman none of 2,000
    # did, where H3's `getpid` per call makes the window wide enough.
    # The `exact` mode above kills a holder inside the lock on every
    # host, and its ablation is the negative there.
    ok "$lowering: $1 recovered traps swept a binding mid-channel and every call answered; none landed inside the lock on this host (reported, not required: exact covers the dead holder)"
  elif [[ "$rc" == 0 && "${3:-}" == 0 ]]; then
    bad "$lowering: no sweep landed inside the lock, so the check saw nothing ('$out')"
  else
    bad "$lowering: sweep exit $rc, '$out' - a round did not answer"
  fi
done
# Ablations on a copy of the library, built in both lowerings: each must
# leave the probe with no answer.
ablate_dead() {
  local kind="$1" dir="$work/dead-$1"
  rm -rf "$dir"; mkdir -p "$dir"
  cp -R "$repo_root/stdlib" "$dir/stdlib"
  python3 - "$dir/stdlib/Chan.ax" "$kind" <<'PY' || return 1
import sys
p, kind = sys.argv[1], sys.argv[2]
s = open(p, encoding="utf-8").read()
# Both cuts take out `chanChildEnded`, the look's one blocking call, so
# the block claim goes with it or the copy would not compile.
unblock = (";@axiom:effect(block)\n(fn (chanHolderDead w me)", "(fn (chanHolderDead w me)")
cuts = {
  # The dead-holder test never finds one: kill's ESRCH and the look ignored.
  "holder": [("        ((Ok r) (chanChildEnded owner))\n        ((Err e) (== (errCode e) 3))))))",
              "        ((Ok r) false)\n        ((Err e) false)))))"), unblock],
  # Only the look at the waiter's own child goes: a zombie looks alive.
  "look": [("        ((Ok r) (chanChildEnded owner))", "        ((Ok r) false)"), unblock],
}[kind]
for old, new in cuts:
    if s.count(old) != 1:
        sys.exit("seam %r found %d times, wanted 1" % (old[:40], s.count(old)))
    s = s.replace(old, new)
open(p, "w", encoding="utf-8").write(s)
PY
  dead_build "$dir" processes "$dir/stdlib" && dead_build "$dir" threads "$dir/stdlib"
}
for pair in holder:exact holder:sweep look:parent; do
  kind="${pair%%:*}"; mode="${pair#*:}"
  if [[ "$mode" == sweep ]] && (( ! sweep_required )); then
    echo "     $pair: not run - the sweep is reported, not required, on this host; holder:exact is the negative"
    continue
  fi
  if [[ ! -x "$work/dead-$kind/dead-threads" ]] && ! ablate_dead "$kind"; then
    bad "$kind: the ablation did not apply or build"; tail -4 "$work/dead-$kind"/*.build 2>/dev/null | sed 's/^/    /'; continue
  fi
  for lowering in processes threads; do
    args=("$mode"); limit=5
    [[ "$mode" == sweep ]] && { args=(sweep 2000); limit=30; }
    rc=0; out="$(gate_timeout "$limit" "$work/dead-$kind/dead-$lowering" "${args[@]}" 2>&1)" || rc=$?
    sleep 0.3; pkill -KILL -f "$work/dead-$kind/dead-$lowering" 2>/dev/null || true
    if [[ "$rc" == 124 ]]; then
      ok "$kind $mode ($lowering): red - no answer in $limit s, the channel stuck as AN-10 left it"
    else
      bad "$kind $mode ($lowering): the ablated channel still answered (exit $rc, '$(tr '\n' ';' <<< "$out" | cut -c1-120)')"
    fi
  done
done

echo
if (( failed > 0 )); then
  echo "check-chan: $failed failed, $checks passed"
  exit 1
fi
echo "check-chan: $checks checks - every word sent was received exactly once, in both"
echo "            lowerings, a waiter sleeps in the kernel, a holder that dies poisons the"
echo "            channel rather than hanging it, and every ablation turns it red"
