#!/usr/bin/env bash
# Checks that a pre-forked Axiom server holds its memory flat across ten
# thousand connections, whether their sizes are uniform or vary by three
# orders of magnitude, and that this script would see it if it did not.
#
# The memory plan treats a request handler as an arena scope:
# `__axiom_arena_mark` before the work and `__axiom_arena_reset` after
# it, so the watermark rewinds every connection. A stateless service then
# runs on bounded memory without reference counting. This gate tests
# that claim.
#
# It stays out of the fast battery, as `check-ffi.sh` does: two servers,
# ten thousand real loopback connections each and RSS read from `ps`
# take a minute or so and many file descriptors. `ci.yml` decides what
# runs where.
#
# The server takes the arena as a flag, so the same binary runs scoped
# and unscoped. A flat reading could come from a broken measurement (the
# wrong pid, workers already dead, `ps` printing nothing), so the
# unscoped run must grow, and by a lot. This is
# `check-memory-baseline.sh`'s managed/unmanaged/ablated shape applied to
# a server.
#
# Unscoped memory grows with total allocation. The handler builds its
# response the way repeated `concat` does, about 16 KiB per connection,
# but from raw `memAlloc` blocks. Counting never frees a raw block, so
# only a reset reclaims it. Strings would not do: counting reclaims
# `concat`'s intermediates by itself, and the unscoped arm would hold
# flat too.
#
# The criterion is a ratio of growth, not a ceiling. Anything a worker
# grows by per connection in both arms alike, such as the kernel's
# socket accounting, cancels in the ratio; a fixed ceiling would pin it.
# The handler refreshes one mark cell per worker. A fresh
# `__axiom_arena_mark` per connection leaves its 24-byte cell below the
# mark (MM-ALLOC-12), and that would show here as growth in both arms.
#
# Fragmentation is tested too. MM-ALLOC-4b never splits or coalesces
# free chunks, so varied request sizes could ratchet memory upward. The
# third measurement cycles responses from 8 to 488 steps (about 1 KiB
# to 3.8 MiB per connection), crossing the 1 MiB chunk boundary
# both ways on every cycle. It must plateau: it starts at the largest
# connection's working set and then grows only by the process overhead.
#
# ---------------------------------------------------------------------
# The two address arms at the end check a different claim: the socket
# layer reports who connected, over IPv4 and IPv6. They need a real
# second process on the other end; `tests/stdlib/317-peer-address.ax`
# covers the case where one process is both ends.
#
# The assertion is the address itself. A server that answered
# `127.0.0.1` to everything would pass a check that only looked for an
# address, so the driver binds a distinct source port per connection,
# derived from this script's pid. No fixed answer, reused previous peer
# or listener address can produce the expected lines.
#
# The IPv6 arm checks three things in one round trip: `afInet6` is this
# platform's number (or `socket` answers -47/-97 EAFNOSUPPORT), the
# address length comes from the family (`sockaddr_in6` is 28 bytes, or
# `bind` answers -22 EINVAL), and the address lands in the right sixteen
# bytes. The server exits 2 on a failed bind and never prints its `pids`
# line, so any of these shows up as a timeout on that line.
#
# Not covered: per-connection state (keep-alive, where the live set
# outlives the request), and addresses beyond loopback.

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

# The driver. It runs sequentially, because a concurrent client would
# make the connection count depend on machine speed, and this gate
# asserts a memory ratio, not a rate.
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
# connects, so the peer the server reports is a number this script
# already knows. It asserts three strings, not a rate.
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
# Runs one worker with the peer report on, drives `n` connections from
# `n` consecutive bound source ports, and leaves the server's output in
# `$work/peer.<port>.out`. Echoes "<echoed>".
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

# check_peers <port> <host> <bracketed host> <source base> <connections> <label>
#
# Compares the `peer` lines the server printed with the endpoints the
# driver connected from, and prints the difference when they differ.
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

# run_server <arena 0|1> <port> <connections> [<varied 0|1>]  ->  echoes "<echoed> <peakRssKiB>"
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

  # Peak across the pool, sampled while the workers are alive: after the
  # SIGTERM there is nothing to read.
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

# Scoped growth is reported, not asserted: pinning it would pin the
# kernel's socket accounting.
echo "     scoped growth ${a_small_rss} -> ${a_large_rss} KiB over $(( conns_large / conns_small ))x the connections"


# ---------------------------------------------------------------
# The ablation. A broken measurement also keeps a number small, so the
# same binary runs with the arena off. The watermark must then track
# total allocation; if this script cannot see that growth, the flat
# result above means nothing.
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

# The claim in one number. Both arms run the same binary on the same load
# and differ only in the arena scope. Each arm's growth (its large run
# minus its small run) drops the process overhead, so the ratio of the
# two growths is the allocator's behaviour.
#
# Dividing totals would not cancel the overhead. On FreeBSD the dynamic
# libc and rtld keep a scoped worker near 2 MiB resident, which drags a
# flat arena's ratio far down.
#
# The floor is 50x. A darwin-aarch64 run gives a ratio of a few hundred,
# so the floor survives a slower machine and still catches an arena that
# has stopped reclaiming.
unscoped_growth=$(( n_large_rss - n_small_rss ))
scoped_growth=$(( a_large_rss - a_small_rss ))
ratio=$(( unscoped_growth / (scoped_growth > 0 ? scoped_growth : 1) ))
# ---------------------------------------------------------------
# Fragmentation. Same binary, same arena, but the response size cycles
# across three orders of magnitude, so free chunks of many sizes are
# made and reused. MM-ALLOC-4b is why a ratchet is possible.
# ---------------------------------------------------------------
echo "== varying the request size must not ratchet the watermark =="
read -r v_small_ok v_small_rss < <(run_server 1 $((base_port + 4)) "$conns_small" 1) || status=1
read -r v_large_ok v_large_rss < <(run_server 1 $((base_port + 5)) "$conns_large" 1) || status=1

if [[ "${v_large_ok:-0}" != "$conns_large" ]]; then
  echo "FAIL: varied-size run echoed $v_large_ok of $conns_large"; status=1
fi
# The floor is the largest single connection's working set, which is
# real work, not growth. So the comparison is between two runs of the
# same shape at different lengths.
if (( v_large_rss > v_small_rss * 2 )); then
  echo "FAIL: with varying request sizes RSS went ${v_small_rss} -> ${v_large_rss} KiB."
  echo "     Free chunks are not being reused across sizes - MM-ALLOC-4b ratcheting."
  status=1
else
  echo "ok   varied sizes held within 2x (${v_small_rss} -> ${v_large_rss} KiB) over $(( conns_large / conns_small ))x the connections"
fi

# ---------------------------------------------------------------
# The peer address. The server asks `tcpPeerAddr` for each accepted
# stream and prints one `peer` line per connection.
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
# IPv6. One round trip that passes only if `afInet6` is this platform's
# number, the address length comes from the family, and `netAddr6`
# writes `::1` into the right sixteen bytes.
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
  echo "FAIL: scoped growth (${a_small_rss} -> ${a_large_rss} KiB) is only ${ratio}x below unscoped growth (${n_small_rss} -> ${n_large_rss} KiB)."
  echo "     The handler's garbage is outliving the connection - either the reset is"
  echo "     not rewinding, or something the handler allocates escaped the scope."
  status=1
else
  echo "ok   scoped grows ${ratio}x less than unscoped from $conns_small to $conns_large connections (scoped ${a_small_rss} -> ${a_large_rss} KiB, unscoped ${n_small_rss} -> ${n_large_rss} KiB)"
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
