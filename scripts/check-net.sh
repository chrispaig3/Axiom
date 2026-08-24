#!/usr/bin/env bash
# Assert that a pre-forked Axiom server holds its memory flat across ten
# thousand connections - whether their sizes are uniform or vary by
# three orders of magnitude - and that this script could tell if it did
# not.
#
# This is the acceptance measurement for the socket work, and it is the
# first thing in this tree that tests the MEMORY PLAN rather than a
# syscall. The plan's premise for backend services is that a request
# handler is an arena scope: `__axiom_arena_mark` before the work,
# `__axiom_arena_reset` after it, and the watermark rewinds every
# connection - so a stateless service can run on bounded memory without
# waiting for reference counting to be finished. Nothing had tested that
# claim. This does.
#
# WHY IT IS NOT IN THE FAST BATTERY. It runs two servers, drives ten
# thousand real loopback connections through each, and reads RSS out of
# `ps`. That is a minute or so and a lot of file descriptors, which is
# the same reason `check-ffi.sh` stands outside the battery. `ci.yml` is
# the authority on what runs where.
#
# THE ABLATION IS THE POINT, and it is built in rather than bolted on.
# The server takes the arena as a FLAG, so this script runs the same
# binary twice: once with the handler scoped and once without. A gate
# that only ever saw flat memory could be flat because the measurement
# is broken - reading the wrong pid, sampling after the workers died,
# `ps` printing nothing. The unscoped run must GROW, and by a lot, or
# the flat one proves nothing. That is `check-memory-baseline.sh`'s
# managed/unmanaged/ablated shape applied to a server.
#
# MEASURED when this was written, two workers, peak worker RSS:
#
#     scoped     1,000 conns      192 KiB
#     scoped    10,000 conns      608 KiB
#     unscoped   1,000 conns   19,136 KiB
#     unscoped  10,000 conns  190,128 KiB     <- 313x the scoped run
#
# The unscoped column is linear in TOTAL ALLOCATION because the
# allocator is a bump allocator that never frees (MM-ALLOC-4a). The
# response is built by repeated `strConcat` on purpose - about 16 KiB of
# unreachable intermediates per connection - so there is something real
# to reclaim.
#
# THE CRITERION IS A RATIO, NOT A CEILING, AND THAT IS A MEASURED
# DECISION. The scoped column is not perfectly flat either: it grows
# about 48 bytes per connection. That looked like a leak until the
# control was run - the same server with the response loop set to ZERO
# iterations, so the handler allocates nothing at all:
#
#     0 concats, scoped     1,000 / 10,000 / 40,000  ->  160 / 576 / 1,968 KiB
#     0 concats, UNSCOPED   1,000 / 10,000 / 40,000  ->  128 / 544 / 1,936 KiB
#
# The two are the same, and the arena flag is irrelevant when there is
# nothing to reclaim. So that 48 bytes is per-connection process
# overhead - descriptor churn and the kernel's socket accounting - and
# not the Axiom heap, which IS flat. Both arms of the real measurement
# carry the same baseline, so comparing them to each other cancels it
# and comparing either to an absolute number does not. An earlier
# version of this gate asserted "within 2x of a small run" and failed on
# that baseline while the allocator was behaving perfectly.
#
# FRAGMENTATION IS TESTED TOO, AND IT DOES NOT RATCHET. `MM-ALLOC-4b`
# says free chunks are never split and never coalesced, and first fit
# runs over the whole mapping - so a workload whose request sizes VARY
# was expected to climb even with the arena, one un-reusable chunk at a
# time. The third measurement below is that workload: response sizes
# cycle from 8 to 488 concatenations, about 1 KiB to 3.8 MiB of
# intermediates per connection, which crosses the 1 MiB chunk boundary
# in both directions on every cycle.
#
# It plateaus. Measured 3,968 / 4,192 / 4,864 KiB at 1,000 / 5,000 /
# 20,000 connections - it starts at the peak working set of the LARGEST
# single connection, which is the honest cost of serving one, and then
# grows 47 bytes per connection after that, which is the same process
# baseline the control below establishes. So the arena reclaims across
# chunk boundaries, and worker recycling is not needed to bound this
# workload. That is a planned item retired by measurement rather than
# built.
#
# WHAT THIS STILL DOES NOT TEST: nothing here keeps per-connection
# state, so this is the STATELESS case the plan scoped to and not
# keep-alive, where the live set outlives the request and the arena
# boundary stops being free.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init

conns_small="${AXIOM_NET_SMALL:-200}"
conns_large="${AXIOM_NET_LARGE:-10000}"
workers=4

status=0

command -v python3 >/dev/null 2>&1 || {
  echo "FAIL: python3 is needed to drive the connections"; exit 1
}

srv="$work/echo-server"
"$axiom" build --input tests/net/echo-server.ax --output "$srv" >"$work/build.log" 2>&1 || {
  echo "FAIL: could not build tests/net/echo-server.ax"
  sed 's/^/    /' "$work/build.log" | head -10
  exit 1
}

# The driver. Sequential on purpose: a concurrent client would make the
# connection count a function of how fast the machine is, and this gate
# asserts a memory ratio rather than a rate.
cat > "$work/drive.py" <<'PY'
import socket, sys
port, n = int(sys.argv[1]), int(sys.argv[2])
ok = 0
for i in range(n):
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=10)
        s.sendall(bytes([i % 251]))
        if s.recv(1) == bytes([i % 251]):
            ok += 1
        s.close()
    except OSError:
        pass
print(ok)
PY

# run <arena 0|1> <port> <connections>  ->  echoes "<echoed> <peakRssKiB>"
run_server() {
  local arena="$1" port="$2" n="$3" varied="${4:-0}"
  local out="$work/srv.$port.out"

  "$srv" "$port" "$workers" "$arena" "$varied" >"$out" 2>&1 &
  local srv_pid=$!

  # Wait for the pids line rather than sleeping a guess.
  local waited=0 pids=""
  while [[ -z "$pids" && "$waited" -lt 100 ]]; do
    pids="$(sed -n 's/^pids //p' "$out" 2>/dev/null)"
    [[ -n "$pids" ]] && break
    sleep 0.1
    waited=$((waited + 1))
  done
  if [[ -z "$pids" ]]; then
    echo "FAIL: the server never announced its workers (port $port)" >&2
    kill "$srv_pid" 2>/dev/null
    return 1
  fi

  local echoed
  echoed="$(python3 "$work/drive.py" "$port" "$n")"

  # Peak across the pool, sampled while the workers are still alive -
  # after the SIGTERM there is nothing to read.
  local peak=0 r
  for p in $pids; do
    r="$(ps -o rss= -p "$p" 2>/dev/null | tr -d ' ')"
    [[ -n "$r" ]] && (( r > peak )) && peak="$r"
  done

  for p in $pids; do kill -TERM "$p" 2>/dev/null; done
  wait "$srv_pid" 2>/dev/null

  if (( peak == 0 )); then
    echo "FAIL: could not read RSS for any worker (port $port)" >&2
    return 1
  fi
  echo "$echoed $peak"
}

base_port=$(( 21000 + ($$ % 3000) ))

echo "== the handler is an arena scope: memory holds across $conns_large connections =="
read -r a_small_ok a_small_rss < <(run_server 1 $((base_port + 0)) "$conns_small") || status=1
read -r a_large_ok a_large_rss < <(run_server 1 $((base_port + 1)) "$conns_large") || status=1

if [[ "${a_small_ok:-0}" != "$conns_small" ]]; then
  echo "FAIL: scoped run echoed $a_small_ok of $conns_small"; status=1
else
  echo "ok   $conns_small connections, all echoed, peak worker RSS ${a_small_rss} KiB"
fi
if [[ "${a_large_ok:-0}" != "$conns_large" ]]; then
  echo "FAIL: scoped run echoed $a_large_ok of $conns_large"; status=1
else
  echo "ok   $conns_large connections, all echoed, peak worker RSS ${a_large_rss} KiB"
fi

# Growth across the scoped runs is reported rather than asserted: it is
# the process baseline measured above, not the heap, and pinning it here
# would pin the kernel's socket accounting.
echo "     scoped growth ${a_small_rss} -> ${a_large_rss} KiB over $(( conns_large / conns_small ))x the connections"


# ---------------------------------------------------------------
# The ablation. Everything above asserts a NUMBER STAYING SMALL, and a
# broken measurement produces that too. So the same binary is run with
# the arena off, where the bump allocator's watermark must track total
# allocation - and if it does not, this script cannot see growth and its
# green above means nothing.
# ---------------------------------------------------------------
echo "== ablation: with the handler unscoped, the same measurement must see growth =="
read -r n_small_ok n_small_rss < <(run_server 0 $((base_port + 2)) "$conns_small") || status=1
read -r n_large_ok n_large_rss < <(run_server 0 $((base_port + 3)) "$conns_large") || status=1

echo "     unscoped: $conns_small -> ${n_small_rss} KiB, $conns_large -> ${n_large_rss} KiB"
if (( n_large_rss <= n_small_rss * 2 )); then
  echo "FAIL negative probe: unscoped memory did NOT grow past 2x, so this gate cannot"
  echo "     distinguish a working arena from a measurement that reads nothing"
  status=1
else
  echo "ok   negative probe: unscoped RSS grew $(( n_large_rss / (n_small_rss > 0 ? n_small_rss : 1) ))x, so the flat result above is a real one"
fi

# THE CLAIM, IN ONE LINE. Both arms ran the same binary against the same
# load and differ only in whether the handler was an arena scope, so the
# ratio between them is the allocator's behaviour with the process
# baseline cancelled out. Measured at 313x; the floor is 50x, which is
# far enough below to survive a slower machine and far enough above to
# catch an arena that stopped reclaiming.
ratio=$(( n_large_rss / (a_large_rss > 0 ? a_large_rss : 1) ))
# ---------------------------------------------------------------
# Fragmentation. Same binary, same arena, but the response size cycles
# across three orders of magnitude, so free chunks of many sizes are
# produced and reused. `MM-ALLOC-4b` is the reason to expect a ratchet.
# ---------------------------------------------------------------
echo "== varying the request size must not ratchet the watermark =="
read -r v_small_ok v_small_rss < <(run_server 1 $((base_port + 4)) "$conns_small" 1) || status=1
read -r v_large_ok v_large_rss < <(run_server 1 $((base_port + 5)) "$conns_large" 1) || status=1

if [[ "${v_large_ok:-0}" != "$conns_large" ]]; then
  echo "FAIL: varied-size run echoed $v_large_ok of $conns_large"; status=1
fi
# The floor is the largest single connection's working set, which is
# real work and not growth, so the comparison is between two runs of the
# SAME shape at different lengths.
if (( v_large_rss > v_small_rss * 2 )); then
  echo "FAIL: with varying request sizes RSS went ${v_small_rss} -> ${v_large_rss} KiB."
  echo "     Free chunks are not being reused across sizes - MM-ALLOC-4b ratcheting."
  status=1
else
  echo "ok   varied sizes held within 2x (${v_small_rss} -> ${v_large_rss} KiB) over $(( conns_large / conns_small ))x the connections"
fi

if (( ratio < 50 )); then
  echo "FAIL: scoped (${a_large_rss} KiB) is only ${ratio}x below unscoped (${n_large_rss} KiB)."
  echo "     The handler's garbage is outliving the connection - either the reset is"
  echo "     not rewinding, or something the handler allocates escaped the scope."
  status=1
else
  echo "ok   scoped uses ${ratio}x less than unscoped at $conns_large connections"
fi

if (( status == 0 )); then
  echo
  echo "check-net: a pre-forked server holds its memory flat across"
  echo "           $conns_large connections when the handler is an arena scope,"
  echo "           holds it when the request sizes vary by three orders of"
  echo "           magnitude, and this measurement can see it when it does not"
fi
exit "$status"
