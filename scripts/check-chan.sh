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
# FIVE SECTIONS.
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
#   3. A receive nobody can satisfy blocks, and stays blocked: `stuck`
#      mode must still be running after 2 s, in both lowerings, and the
#      deadline must leave no process behind. That is the documented
#      behaviour (no timeout exists), measured separately from the races
#      in section 1, as deadlock and data race are different failures.
#   4. Ablations, each on a COPY of the standard library, each required
#      to turn section 1's load red:
#        lock   - `chanLock` and `chanUnlock` answer 0 without touching
#                 the lock word: producers overwrite each other's slots.
#        notify - `chanNotify` wakes a word nobody sleeps on, so a waiter
#                 on the counter sleeps forever
#                 so the load hangs. This one is also the proof that a
#                 waiter really sleeps in the kernel: one that spun would
#                 re-check the ring and never need the wake.
#   5. Retained memory. The --threads load at N and 10N: peak RSS must
#      not grow by more than 8 MiB while ten times the words go through.
#
# LIMITS. Load that passed is evidence on the runs made, on this host;
# the lock and the protocol are not proved. FreeBSD spins instead of
# blocking (`waitWordKind` 0) and is not run here. The channel carries
# words only, has no timeout, and its handle is an `Int` - the
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
    (";@axiom:effect(unsafe)\n(fn (chanLock ch)\n  (if (== (__atomic_cas ch 0 1) 0)", "(fn (chanLock ch)\n  (if (== 0 0)"),
    ("(fn (chanUnlock ch)\n  (if (== (__atomic_add ch (- 0 1)) 1)", "(fn (chanUnlock ch)\n  (if (== 1 1)"),
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

echo
if (( failed > 0 )); then
  echo "check-chan: $failed failed, $checks passed"
  exit 1
fi
echo "check-chan: $checks checks - every word sent was received exactly once, in both"
echo "            lowerings, a waiter sleeps in the kernel, and both ablations turn it red"
