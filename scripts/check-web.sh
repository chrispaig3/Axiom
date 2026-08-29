#!/usr/bin/env bash
# Assert that the templated server in examples/web answers every one of
# its pages byte for byte - the escaped `<script>` among them - holds
# its memory flat across ten thousand requests, refuses a path that
# climbs out of its static directory, and that this script could tell
# if any of that stopped being true.
#
# This is `check-net.sh` one layer up. That gate measures a server whose
# handler builds garbage on purpose; this one measures a server whose
# handler does the work a web server does - parse a request off a
# socket (`stdlib/Http.ax`), render a page through the macro-system DSL
# (`stdlib/Html.ax`), write it back - and asks the same question of it:
# is the request handler an arena scope (docs/memory-model.md
# MM-ALLOC-22), so that a stateless service runs on bounded memory? It
# is also the only thing that exercises examples/web at all, which is
# the rule ci.yml applies to examples/axdoc: an example CI runs is one
# that cannot rot.
#
# THE PAGES ARE COMPARED AS BYTES, HEADERS INCLUDED, against responses
# this script writes by hand - the second implementation CONTRIBUTING's
# gate rule asks for. The server emits no `Date` and no `Server`
# header, so the whole response is reproducible, and the static files
# are compared against the bytes on disk. The XSS case is a byte
# comparison too, not a substring: `/hello?name=<script>alert(1)</script>`
# must come back as exactly the page with `&lt;script&gt;` in the text
# node and in the attribute value. A PNG - a real one, written at run
# time, with NUL bytes in it (22, counted before it is served) - is
# planted and fetched, because `strCStr` stops at a NUL and a gate that
# only fetched text would never see a binary body truncated.
#
# EVERY ASSERTION HERE HAS ITS ABLATION, and they are the point:
#
#   - the byte comparison: one byte of the index page's expected bytes
#     is flipped in a copy and the comparison must go red, because a
#     comparison against a file nobody checks is a comparison against
#     itself;
#   - the escaping: the same binary is run with `AXIOM_WEB_NOESC=1`,
#     which routes the query parameter around the escaper, and that
#     arm MUST answer the raw `<script>` in both positions - or the
#     assertion above is being satisfied by a 404, an empty body, or a
#     server that never started;
#   - the traversal refusal: a file is planted OUTSIDE the static
#     directory, `/static/../../planted.txt` and its `%2e%2e` spelling
#     must answer 400, and a build of the same program against a copy
#     of the library with `httpPathSafe` replaced by `true` must SERVE
#     the planted file - a refusal test that never sees an acceptance
#     is testing nothing (`check-compat.sh`'s own lesson: "five probes
#     for refusing and none for accepting");
#   - the memory: the same binary is run with the arena flag OFF, and
#     that run must grow past 2x between the short and the long drive,
#     or the flat scoped column means the measurement reads nothing.
#
# MEASURED when this was written (2026-08-29, two workers, peak worker
# RSS, `GET /` - the 749-byte templated index page - per request, one
# connection per request):
#
#     scoped       200 requests          208 KiB
#     scoped    10,000 requests          576 KiB
#     unscoped     200 requests        1,536 KiB
#     unscoped  10,000 requests       61,216 KiB     <- 106x the scoped run
#
# The unscoped column is linear in total allocation: about 6.2 KiB of
# RSS a request, against the 8,608 bytes `stdlib/Http.ax`'s header
# measured the bump moving for a page request off the arena mark cell.
# The gap is the reader's 2 KiB buffer, which is allocated whole and
# written only as far as the 55-byte head reaches - RSS counts pages
# TOUCHED, and the bump counts bytes claimed. The scoped column grows
# the few dozen bytes a connection `check-net.sh` attributes to
# descriptor churn and the kernel's socket accounting, so as there the
# criterion is a RATIO between two runs of the same binary and not a
# ceiling. The floor is 20x: measured 106x, and the headroom is
# smaller than check-net's 50x-under-313x because a real page is ~6
# KiB of garbage where that gate's handler builds 16 KiB on purpose. A
# slower machine does not move an RSS ratio; a different kernel's
# per-process baseline does, which is what the headroom is for.
#
# WHY IT IS IN CI ALL THE SAME. Two servers and 20,400 real requests,
# each of which renders a page, is under a minute on a laptop and the
# criterion is a ratio, so a slow runner cannot fail it - the same
# case `ci.yml` makes for `check-net.sh`.
#
# WHY python3 AND NOT curl: python3 is already an asserted dependency
# of `check-net.sh` and `tests/lsp/drive.py`; curl is asserted by no
# gate in the tree. The driver is sequential on purpose, as there: a
# concurrent client would make the request count a function of how
# fast the machine is, and this gate asserts a memory ratio rather
# than a rate.
#
# WHAT THIS DOES NOT TEST: keep-alive. Every response carries
# `Connection: close` and the server closes, which is the stateless
# case MM-ALLOC-22 scopes its claim to; a per-connection loop needs
# `Rpc.rdReseat`'s move and `__axiom_arena_reset_keeping`, and its
# own arm here whose ablation must grow. `stdlib/Http.ax`'s header
# names that follow-up.

set -uo pipefail

source "$(dirname "${BASH_SOURCE[0]}")/lib/gate.sh"
gate_init
gate_build_axc axc

reqs_small="${AXIOM_WEB_SMALL:-200}"
reqs_large="${AXIOM_WEB_LARGE:-10000}"
workers=2

status=0

command -v python3 >/dev/null 2>&1 || {
  echo "FAIL: python3 is needed to drive the requests"; exit 1
}

# ---------------------------------------------------------------
# The server, and the site it serves. The static directory is a COPY
# under $work, because the traversal arm plants a file one level above
# it and the planted file must not be the repository's.
# ---------------------------------------------------------------
srv="$work/webserver"
"$axc" build --input examples/web/server.ax --output "$srv" >"$work/build.log" 2>&1 || {
  echo "FAIL: could not build examples/web/server.ax"
  sed 's/^/    /' "$work/build.log" | head -10
  exit 1
}

site="$work/site"
mkdir -p "$site"
cp -R examples/web/static "$site/static"
printf 'the planted file, one level above the static directory\n' > "$work/planted.txt"

# A real 1x1 PNG, written here rather than checked in: it holds NUL
# bytes (counted below, and there must be at least one), which is the
# property the binary arm needs and a text asset cannot supply.
python3 - "$site/static/dot.png" <<'PY'
import struct, zlib, sys
def chunk(t, d): return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0)) \
    + chunk(b"IDAT", zlib.compress(b"\x00\xff\x00\x00")) + chunk(b"IEND", b"")
open(sys.argv[1], "wb").write(png)
PY
png_nuls="$(python3 -c 'import sys; print(open(sys.argv[1],"rb").read().count(b"\x00"))' "$site/static/dot.png")"
if (( png_nuls < 1 )); then
  echo "FAIL: the planted PNG holds no NUL byte, so the binary arm would test nothing"; exit 1
fi

# The raw client: one request, the whole response as bytes on stdout.
# Raw rather than http.client so the HEAD is compared too.
cat > "$work/fetch.py" <<'PY'
import socket, sys
port, method, path = int(sys.argv[1]), sys.argv[2], sys.argv[3]
s = socket.create_connection(("127.0.0.1", port), timeout=10)
s.sendall(("%s %s HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept-Encoding: identity\r\n\r\n" % (method, path)).encode())
out = b""
while True:
    d = s.recv(65536)
    if not d:
        break
    out += d
s.close()
sys.stdout.buffer.write(out)
PY

# The load driver. Sequential on purpose - see the header. Counts the
# responses whose status line is the one asked for.
cat > "$work/drive.py" <<'PY'
import socket, sys
port, n = int(sys.argv[1]), int(sys.argv[2])
req = b"GET / HTTP/1.1\r\nHost: 127.0.0.1\r\nAccept-Encoding: identity\r\n\r\n"
ok = 0
for i in range(n):
    try:
        s = socket.create_connection(("127.0.0.1", port), timeout=10)
        s.sendall(req)
        head = b""
        while b"\r\n" not in head:
            d = s.recv(65536)
            if not d:
                break
            head += d
        while True:
            d = s.recv(65536)
            if not d:
                break
        s.close()
        if head.startswith(b"HTTP/1.1 200 OK\r\n"):
            ok += 1
    except OSError:
        pass
print(ok)
PY

# start_server <port> <arena 0|1> <extra env...>  -> sets `pids`, `srv_pid`
#
# Waits for the `pids` line rather than sleeping a guess: a listener
# that could not be bound exits 2 before printing it.
start_server() {
  local port="$1" arena="$2" bin="${3:-$srv}"
  local out="$work/srv.$port.out"
  AXIOM_WEB_ROOT="$site" "$bin" "$port" "$workers" "$arena" >"$out" 2>&1 &
  srv_pid=$!
  local waited=0
  pids=""
  while [[ -z "$pids" && "$waited" -lt 100 ]]; do
    pids="$(sed -n 's/^pids //p' "$out" 2>/dev/null)"
    [[ -n "$pids" ]] && break
    sleep 0.1
    waited=$((waited + 1))
  done
  if [[ -z "$pids" ]]; then
    echo "FAIL: the server never announced its workers (port $port)" >&2
    sed 's/^/    /' "$out" >&2
    kill "$srv_pid" 2>/dev/null
    return 1
  fi
  return 0
}

stop_server() {
  local p
  for p in $pids; do kill -TERM "$p" 2>/dev/null; done
  wait "$srv_pid" 2>/dev/null
  pids=""
}

# Whatever happens, no worker outlives this script.
cleanup_servers() { [[ -n "${pids:-}" ]] && stop_server; rm -rf "$work"; }
trap cleanup_servers EXIT

# ---------------------------------------------------------------
# The expected bytes, written by hand. `frame` is the page frame
# examples/web/server.ax's `pageOf` macro renders, spelled out here so
# the two implementations are independent; `response` is the head
# `Http.httpRespond` writes, with the length counted from the body.
# ---------------------------------------------------------------
nav='<nav class="top"><a href="/">home</a><a href="/hello?name=world">hello</a><a href="/static/site.css">stylesheet</a></nav>'
frame() {
  local title="$1" inner="$2"
  printf '<!DOCTYPE html>\n<html lang="en"><head><meta charset="utf-8"><title>%s</title><link rel="stylesheet" href="/static/site.css"><script src="/static/app.js"></script></head><body>%s<div class="card"><h1>%s</h1>%s</div></body></html>' \
    "$title" "$nav" "$title" "$inner"
}

# response <status> <reason> <content-type> <body file>  -> stdout
response() {
  local status="$1" reason="$2" ctype="$3" body="$4"
  printf 'HTTP/1.1 %s %s\r\nContent-Type: %s\r\nContent-Length: %s\r\nConnection: close\r\n\r\n' \
    "$status" "$reason" "$ctype" "$(wc -c < "$body" | tr -d ' ')"
  cat "$body"
}

html='text/html; charset=utf-8'
plain='text/plain; charset=utf-8'
mkdir -p "$work/expect" "$work/got"

items='<p>Every item below came out of a Vec through `for`, escaped.</p><ul><li>a plain item</li><li>one with &lt;angle&gt; brackets</li><li>ampersands &amp; "quotes"</li></ul><form action="/hello" method="get"><label for="name">Your name</label><input id="name" name="name" type="text" placeholder="a &lt;name&gt;"><button type="submit">Say hello</button></form>'
frame 'Items &amp; &lt;things&gt;' "$items" > "$work/expect/index.body"
response 200 OK "$html" "$work/expect/index.body" > "$work/expect/index.http"

xss='&lt;script&gt;alert(1)&lt;/script&gt;'
hello='<p>Hello, <strong>'"$xss"'</strong>!</p><form action="/hello" method="get"><input name="name" type="text" value="'"$xss"'"><button type="submit">Again</button></form>'
frame 'Hello' "$hello" > "$work/expect/hello.body"
response 200 OK "$html" "$work/expect/hello.body" > "$work/expect/hello.http"

frame 'Not found' '<p>Nothing lives at <code>/n&lt;pe</code>.</p>' > "$work/expect/nope.body"
response 404 'Not Found' "$html" "$work/expect/nope.body" > "$work/expect/nope.http"

response 200 OK 'text/css; charset=utf-8' "$site/static/site.css" > "$work/expect/css.http"
response 200 OK 'text/javascript; charset=utf-8' "$site/static/app.js" > "$work/expect/js.http"
response 200 OK 'image/png' "$site/static/dot.png" > "$work/expect/png.http"

printf '405 Method Not Allowed: no route for this method at this path\n' > "$work/expect/post.body"
response 405 'Method Not Allowed' "$plain" "$work/expect/post.body" > "$work/expect/post.http"

printf '400 Bad Request: unsafe path\n' > "$work/expect/unsafe.body"
response 400 'Bad Request' "$plain" "$work/expect/unsafe.body" > "$work/expect/unsafe.http"

response 200 OK "$plain" "$work/planted.txt" > "$work/expect/planted.http"

# expect_bytes <port> <name> <method> <path> <what>
expect_bytes() {
  local port="$1" name="$2" method="$3" path="$4" what="$5"
  python3 "$work/fetch.py" "$port" "$method" "$path" > "$work/got/$name.http" 2>"$work/got/$name.err"
  if cmp -s "$work/expect/$name.http" "$work/got/$name.http"; then
    echo "ok   $what: $(wc -c < "$work/got/$name.http" | tr -d ' ') bytes, head and body as written by hand"
    return 0
  fi
  echo "FAIL: $what - the bytes differ from the expected response"
  cmp "$work/expect/$name.http" "$work/got/$name.http" 2>&1 | sed 's/^/     /' | head -3
  diff <(tr '\r' '\n' < "$work/expect/$name.http") <(tr '\r' '\n' < "$work/got/$name.http") | sed 's/^/     /' | head -12
  return 1
}

base_port=$(( 40000 + ($$ % 3000) ))

echo "== every page and file, byte for byte =="
if start_server $((base_port + 0)) 1; then
  expect_bytes $((base_port + 0)) index GET / "the templated index" || status=1
  expect_bytes $((base_port + 0)) hello GET '/hello?name=%3Cscript%3Ealert(1)%3C/script%3E' "the query parameter escaped in text and attribute" || status=1
  expect_bytes $((base_port + 0)) nope GET '/n%3Cpe' "a rendered 404 with the path escaped" || status=1
  expect_bytes $((base_port + 0)) css GET /static/site.css "site.css from disk as text/css" || status=1
  expect_bytes $((base_port + 0)) js GET /static/app.js "app.js from disk as text/javascript" || status=1
  expect_bytes $((base_port + 0)) png GET /static/dot.png "a PNG with $png_nuls NUL bytes, written whole" || status=1
  expect_bytes $((base_port + 0)) post POST / "a POST to a GET route is 405" || status=1
  expect_bytes $((base_port + 0)) unsafe GET '/static/../../planted.txt' "the traversal is refused before the filesystem" || status=1
  expect_bytes $((base_port + 0)) unsafe GET '/static/%2e%2e/%2e%2e/planted.txt' "and its percent-encoded spelling too" || status=1
  stop_server
else
  status=1
fi

# The comparator's own ablation: one byte of the expected index page
# flipped in a copy must be noticed, or every `ok` above is a
# comparison against nothing.
python3 - "$work/expect/index.http" "$work/expect/index-flipped.http" <<'PY'
import sys
b = bytearray(open(sys.argv[1], "rb").read())
i = b.index(b"<h1>") + 4
b[i] ^= 0x20
open(sys.argv[2], "wb").write(bytes(b))
PY
if cmp -s "$work/expect/index-flipped.http" "$work/got/index.http"; then
  echo "FAIL negative probe: an expected page with one byte flipped still compared equal"
  status=1
else
  echo "ok   negative probe: one flipped byte in the expected index page is a mismatch"
fi

# ---------------------------------------------------------------
# The XSS ablation. The same binary with the escaper bypassed for the
# query parameter must answer the raw bytes in BOTH positions.
# ---------------------------------------------------------------
echo "== ablation: with the escaper bypassed the raw <script> must come back =="
if AXIOM_WEB_NOESC=1 start_server $((base_port + 1)) 1; then
  python3 "$work/fetch.py" $((base_port + 1)) GET '/hello?name=%3Cscript%3Ealert(1)%3C/script%3E' > "$work/got/noesc.http"
  raw_text='<strong><script>alert(1)</script></strong>'
  raw_attr='value="<script>alert(1)</script>"'
  if grep -qF "$raw_text" "$work/got/noesc.http" && grep -qF "$raw_attr" "$work/got/noesc.http"; then
    echo "ok   negative probe: unescaped, the page carries <script> in the text node and the attribute"
  else
    echo "FAIL negative probe: the AXIOM_WEB_NOESC arm did not answer the raw <script>, so the"
    echo "     escaped comparison above cannot tell an escaper from a page that never rendered"
    status=1
  fi
  if grep -qF "$raw_text" "$work/got/hello.http"; then
    echo "FAIL: the escaped arm's page carries a raw <script> too"; status=1
  fi
  stop_server
else
  status=1
fi

# ---------------------------------------------------------------
# The traversal ablation. A build against a copy of the library whose
# `httpPathSafe` answers `true` must SERVE the planted file.
# ---------------------------------------------------------------
echo "== ablation: with the path check compiled out the planted file is served =="
cp -R "$repo_root/stdlib" "$work/stdlib-open"
sed 's/(if (httpPathSafe req.path)/(if true/' "$work/stdlib-open/Http.ax" > "$work/stdlib-open/Http.ax.new"
if cmp -s "$work/stdlib-open/Http.ax" "$work/stdlib-open/Http.ax.new"; then
  echo "FAIL: the ablation's edit matched nothing in stdlib/Http.ax, so the open build is the real one"
  status=1
else
  mv "$work/stdlib-open/Http.ax.new" "$work/stdlib-open/Http.ax"
  if AXIOM_STDLIB="$work/stdlib-open" "$axc" build --input examples/web/server.ax --output "$work/webserver-open" >"$work/build-open.log" 2>&1; then
    if start_server $((base_port + 2)) 1 "$work/webserver-open"; then
      python3 "$work/fetch.py" $((base_port + 2)) GET '/static/../../planted.txt' > "$work/got/planted.http"
      if cmp -s "$work/expect/planted.http" "$work/got/planted.http"; then
        echo "ok   negative probe: the open build serves ../../planted.txt, so the refusal above is the check and not a 404"
      else
        echo "FAIL negative probe: the build with httpPathSafe removed did not serve the planted file"
        diff <(tr '\r' '\n' < "$work/expect/planted.http") <(tr '\r' '\n' < "$work/got/planted.http") | sed 's/^/     /' | head -8
        status=1
      fi
      stop_server
    else
      status=1
    fi
  else
    echo "FAIL: could not build the ablated server"
    sed 's/^/    /' "$work/build-open.log" | head -10
    status=1
  fi
fi

# ---------------------------------------------------------------
# Memory, check-net.sh's shape: two lengths per arm, peak worker RSS
# sampled while the workers are alive, the unscoped arm as the probe.
# ---------------------------------------------------------------
# run_load <arena 0|1> <port> <requests>  -> echoes "<answered> <peakRssKiB>"
run_load() {
  local arena="$1" port="$2" n="$3"
  start_server "$port" "$arena" || return 1
  local answered
  answered="$(python3 "$work/drive.py" "$port" "$n")"
  local peak=0 r p
  for p in $pids; do
    r="$(ps -o rss= -p "$p" 2>/dev/null | tr -d ' ')"
    [[ -n "$r" ]] && (( r > peak )) && peak="$r"
  done
  stop_server
  if (( peak == 0 )); then
    echo "FAIL: could not read RSS for any worker (port $port)" >&2
    return 1
  fi
  echo "$answered $peak"
}

echo "== the request handler is an arena scope: memory holds across $reqs_large page requests =="
read -r a_small_ok a_small_rss < <(run_load 1 $((base_port + 3)) "$reqs_small") || status=1
read -r a_large_ok a_large_rss < <(run_load 1 $((base_port + 4)) "$reqs_large") || status=1

if [[ "${a_small_ok:-0}" != "$reqs_small" ]]; then
  echo "FAIL: scoped run answered $a_small_ok of $reqs_small with 200"; status=1
else
  echo "ok   $reqs_small requests, all answered 200, peak worker RSS ${a_small_rss} KiB"
fi
if [[ "${a_large_ok:-0}" != "$reqs_large" ]]; then
  echo "FAIL: scoped run answered $a_large_ok of $reqs_large with 200"; status=1
else
  echo "ok   $reqs_large requests, all answered 200, peak worker RSS ${a_large_rss} KiB"
fi
echo "     scoped growth ${a_small_rss:-0} -> ${a_large_rss:-0} KiB over $(( reqs_large / reqs_small ))x the requests"

echo "== ablation: with the handler unscoped, the same measurement must see growth =="
read -r n_small_ok n_small_rss < <(run_load 0 $((base_port + 5)) "$reqs_small") || status=1
read -r n_large_ok n_large_rss < <(run_load 0 $((base_port + 6)) "$reqs_large") || status=1

echo "     unscoped: $reqs_small -> ${n_small_rss:-0} KiB, $reqs_large -> ${n_large_rss:-0} KiB"
if (( ${n_large_rss:-0} <= ${n_small_rss:-0} * 2 )); then
  echo "FAIL negative probe: unscoped memory did NOT grow past 2x, so this gate cannot"
  echo "     distinguish a working arena from a measurement that reads nothing"
  status=1
else
  echo "ok   negative probe: unscoped RSS grew $(( n_large_rss / (n_small_rss > 0 ? n_small_rss : 1) ))x, so the flat result above is a real one"
fi

# THE CLAIM. Same binary, same load, one flag apart; the ratio is the
# allocator's behaviour with the process baseline cancelled. Measured
# at 106x, floor 20x - the header says why the headroom is what it is.
ratio=$(( ${n_large_rss:-0} / (${a_large_rss:-0} > 0 ? a_large_rss : 1) ))
if (( ratio < 20 )); then
  echo "FAIL: scoped (${a_large_rss:-0} KiB) is only ${ratio}x below unscoped (${n_large_rss:-0} KiB)."
  echo "     A request's garbage is outliving the connection - either the reset is"
  echo "     not rewinding, or something the handler allocates escaped the scope."
  status=1
else
  echo "ok   scoped uses ${ratio}x less than unscoped at $reqs_large page requests"
fi

if (( status == 0 )); then
  echo
  echo "check-web: a server written on Html and Http answers its templated"
  echo "           pages and its files byte for byte, escapes what the peer"
  echo "           sent in text and in attributes, refuses a path that climbs"
  echo "           out of its static directory, holds its memory flat across"
  echo "           $reqs_large page requests with the handler an arena scope, and"
  echo "           every one of those claims has an ablation that goes red"
fi
exit "$status"
