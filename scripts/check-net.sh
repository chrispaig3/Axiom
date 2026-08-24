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
# ---------------------------------------------------------------------
# THE ADDRESS ARMS, WHICH MEASURE NOTHING. Everything above is one
# claim about memory. The two arms at the bottom are a different
# claim - that the socket layer can say WHO connected, and can do it
# over both address families - and they are here rather than in
# `tests/stdlib/` because they need a real second process on the other
# end of the connection. `tests/stdlib/317-peer-address.ax` is the same
# property with one process being both ends; this is the one where the
# client is not us.
#
# THE ASSERTION IS THE ADDRESS, NOT THAT A CALL RETURNED. That
# distinction is this script's own, one layer up: the memory arms
# compare two runs to each other rather than to a constant, because a
# constant can be met by a measurement that reads nothing. An address
# arm has the same hole - a server that answered `127.0.0.1` to
# everything would pass any check that only looked at the address - so
# the driver BINDS ITS SOURCE PORT, to a number derived from this
# script's pid at run time, and a different one per connection. The
# expected lines are therefore three distinct endpoints that no fixed
# answer, no reuse of the previous peer, and no report of the
# LISTENER's own address can produce.
#
# THE IPv6 ARM PROVES THREE THINGS AT ONCE and cannot separate them,
# which is the point of running it as one round trip: `afInet6` has to
# be this platform's number or `socket` answers -47/-97 EAFNOSUPPORT;
# the length has to come off the family or `bind` answers -22 EINVAL,
# because `sockaddr_in6` is 28 bytes and the literal 16 that used to be
# there is refused; and the address has to be built into the right
# sixteen bytes or the connection goes somewhere else. The server exits
# 2 on a failed bind and never prints its `pids` line, so any of the
# three shows up as this arm timing out on that line rather than as a
# wrong address.
#
# WHAT THIS STILL DOES NOT TEST: nothing here keeps per-connection
# state, so this is the STATELESS case the plan scoped to and not
# keep-alive, where the live set outlives the request and the arena
# boundary stops being free. And both address arms are LOOPBACK: they
# establish that the peer the kernel reports is the peer that
# connected, not that a globally routed address survives anything.

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

# The address driver. Every connection binds its source port before it
# connects, which is what makes the peer the server reports a number
# this script already knows - see the header. Sequential and tiny: this
# arm asserts three strings, not a rate.
cat > "$work/drive-addr.py" <<'PY'
import socket, sys
port, host, src, n = int(sys.argv[1]), sys.argv[2], int(sys.argv[3]), int(sys.argv[4])
fam = socket.AF_INET6 if ":" in host else socket.AF_INET
ok = 0
for i in range(n):
    try:
        s = socket.socket(fam, socket.SOCK_STREAM)
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind((host, src + i))
        s.settimeout(10)
        s.connect((host, port))
        s.sendall(bytes([i % 251]))
        if s.recv(1) == bytes([i % 251]):
            ok += 1
        s.close()
    except OSError as e:
        print("client:", e, file=sys.stderr)
print(ok)
PY

# run_peer_server <port> <host> <v6 0|1> <source base> <connections>
#
# Runs ONE worker with the peer report on, drives `n` connections from
# `n` consecutive bound source ports, and leaves the server's own
# output in `$work/peer.<port>.out`. Echoes "<echoed>".
run_peer_server() {
  local port="$1" host="$2" v6="$3" src="$4" n="$5"
  local out="$work/peer.$port.out"

  AXIOM_NET_PEER=1 AXIOM_NET_LISTEN6="$v6" \
    "$srv" "$port" 1 1 0 >"$out" 2>&1 &
  local srv_pid=$!

  local waited=0 pids=""
  while [[ -z "$pids" && "$waited" -lt 100 ]]; do
    pids="$(sed -n 's/^pids //p' "$out" 2>/dev/null)"
    [[ -n "$pids" ]] && break
    sleep 0.1
    waited=$((waited + 1))
  done
  if [[ -z "$pids" ]]; then
    # A listener that could not be created or could not be bound exits
    # before this line, so this is where a wrong `afInet6` or a wrong
    # address length surfaces.
    echo "FAIL: the server never announced its worker on $host port $port" >&2
    sed 's/^/    /' "$out" >&2
    kill "$srv_pid" 2>/dev/null
    return 1
  fi

  local echoed
  echoed="$(python3 "$work/drive-addr.py" "$port" "$host" "$src" "$n")"

  for p in $pids; do kill -TERM "$p" 2>/dev/null; done
  wait "$srv_pid" 2>/dev/null
  echo "$echoed"
}

# check_peers <port> <host> <bracketed host> <source base> <connections>
#
# Compares the `peer` lines the server printed against the endpoints the
# driver actually connected from, and prints the difference when they
# are not the same.
check_peers() {
  local port="$1" host="$2" shown="$3" src="$4" n="$5" what="$6"
  local out="$work/peer.$port.out" i expected actual

  expected=""
  for ((i = 0; i < n; i++)); do
    expected+="peer $shown:$((src + i))"$'\n'
  done
  actual="$(grep '^peer ' "$out" || true)"

  if [[ "$actual" != "${expected%$'\n'}" ]]; then
    echo "FAIL: $what - the addresses reported are not the ones that connected"
    diff <(printf '%s' "$expected") <(printf '%s\n' "$actual") | sed 's/^/    /' || true
    return 1
  fi
  echo "ok   $what: $n connections, each reported as the endpoint it came from"
  echo "     $(printf '%s' "$expected" | tr '\n' ' ')"
  return 0
}

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

# ---------------------------------------------------------------
# The peer address. `netAccept` passed NULL for `accept`'s two
# out-parameters and the peer was gone by the time it returned;
# `netAcceptFrom` takes a buffer instead. Nothing in this script could
# tell the difference before - `grep -c peer` over it answered 0.
# ---------------------------------------------------------------
echo "== the server reports the address each connection came from =="
addr_src=$(( 25000 + ($$ % 3000) ))
peer_conns=3

peer_ok="$(run_peer_server $((base_port + 6)) 127.0.0.1 0 "$addr_src" "$peer_conns")" || status=1
if [[ "${peer_ok:-0}" != "$peer_conns" ]]; then
  echo "FAIL: the v4 peer arm echoed ${peer_ok:-0} of $peer_conns"; status=1
fi
check_peers $((base_port + 6)) 127.0.0.1 127.0.0.1 "$addr_src" "$peer_conns" \
  "IPv4" || status=1

# ---------------------------------------------------------------
# IPv6. One round trip that cannot pass unless `afInet6` is this
# platform's number, the address length came off the family rather than
# the literal 16, and `netAddr6` wrote `::1` into the right sixteen
# bytes.
# ---------------------------------------------------------------
echo "== a v6 listener on ::1 round-trips and reports v6 peers =="
v6_src=$(( addr_src + 100 ))

v6_ok="$(run_peer_server $((base_port + 7)) ::1 1 "$v6_src" "$peer_conns")" || status=1
if [[ "${v6_ok:-0}" != "$peer_conns" ]]; then
  echo "FAIL: the v6 arm echoed ${v6_ok:-0} of $peer_conns"; status=1
fi
check_peers $((base_port + 7)) ::1 '[::1]' "$v6_src" "$peer_conns" \
  "IPv6" || status=1

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
  echo "           magnitude, and this measurement can see it when it does not;"
  echo "           and it can name the peer of every connection it served,"
  echo "           over IPv4 and over IPv6, on this platform's own afInet6"
fi
exit "$status"
