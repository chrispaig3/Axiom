#!/usr/bin/env python3
"""Drive the self-hosted language server over a pipe, one session per
fixture, and check its output two ways.

WHY NOT A DIFFERENTIAL. Every other self-hosting gate compares stage1
against stage0 for the same surface. There is no stage0 `lsp`
subcommand: the language server is native to the self-hosted compiler,
so a two-sided diff has nothing on the other side, and "agreement by
mutual silence" is precisely the failure mode this project has recorded
about comparing against a not-yet-implemented side.

So the gate follows the human-renderer precedent instead, and checks
two independent things:

  1. GOLDEN. The full framed byte stream of the session, with the
     document's absolute URI normalised, must equal a checked-in
     golden. This pins the protocol exactly - framing, field order,
     JSON escaping, message sequence.

  2. STAGE0-DERIVED FACTS. For every fixture that parses, the set of
     (code, 0-based line) pairs the server publishes must equal the set
     stage0's own `check --diagnostic-format ai` reports for the same
     file. A golden alone could be blessed from a broken server; this
     half is derived from an artifact stage0 produces, so it cannot be
     satisfied by blessing.

     Fixtures that do NOT parse are exempt from the code comparison and
     assert only that both sides report a failure: stage1's parser
     carries no diagnostic payload yet (the parse-error port), so it
     answers a single AX2003 at the top of the file where stage0 names
     a specific AX2001/AX2002 and a position. Recording that as a known
     divergence is honest; asserting equality would be asserting a lie.

Usage: drive.py STAGE1 STAGE0 FIXTURE_DIR [--bless] [filter]
"""
import json
import os
import re
import subprocess
import sys

stage1, stage0, fixdir = sys.argv[1], sys.argv[2], sys.argv[3]
rest = sys.argv[4:]
bless = "--bless" in rest
filt = next((a for a in rest if not a.startswith("--")), "")

DOC_URI = "file:///DOC.ax"


def frame(obj):
    b = json.dumps(obj, separators=(",", ":")).encode("utf-8")
    return b"Content-Length: " + str(len(b)).encode() + b"\r\n\r\n" + b


def session(uri, text):
    """The fixed session every fixture runs. Deliberately exercises the
    lifecycle, both sync directions, an outline request and an
    unsupported request, so one golden pins the whole surface."""
    return b"".join(frame(m) for m in [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize",
         "params": {"processId": None, "rootUri": None, "capabilities": {}}},
        {"jsonrpc": "2.0", "method": "initialized", "params": {}},
        {"jsonrpc": "2.0", "method": "textDocument/didOpen",
         "params": {"textDocument": {"uri": uri, "languageId": "axiom",
                                     "version": 1, "text": text}}},
        {"jsonrpc": "2.0", "id": 2, "method": "textDocument/documentSymbol",
         "params": {"textDocument": {"uri": uri}}},
        {"jsonrpc": "2.0", "id": 3, "method": "textDocument/hover",
         "params": {"textDocument": {"uri": uri},
                    "position": {"line": 0, "character": 0}}},
        {"jsonrpc": "2.0", "method": "textDocument/didClose",
         "params": {"textDocument": {"uri": uri}}},
        {"jsonrpc": "2.0", "id": 4, "method": "shutdown", "params": None},
        {"jsonrpc": "2.0", "method": "exit", "params": None},
    ])


def canonicalise(out, real_uri):
    """Re-frame the byte stream with the document's absolute URI
    replaced by a fixed placeholder.

    The replacement MUST be followed by recomputing `Content-Length`.
    Substituting the URI in the raw stream leaves every header claiming
    the pre-substitution length, which produces a golden whose frames
    do not parse - and which still compares equal to another run made
    the same way, so the damage is invisible until the fixtures move to
    a path of a different length. The message bodies are otherwise
    passed through BYTE FOR BYTE, so this still pins the server's exact
    JSON: field order, escaping, spacing."""
    out_parts, i = [], 0
    while True:
        j = out.find(b"\r\n\r\n", i)
        if j < 0:
            break
        hdr = out[i:j].decode("utf-8", "replace")
        cl = [l for l in hdr.split("\r\n") if l.lower().startswith("content-length")]
        if not cl:
            break
        n = int(cl[0].split(":")[1])
        body = out[j + 4:j + 4 + n].replace(real_uri.encode(), DOC_URI.encode())
        out_parts.append(b"Content-Length: " + str(len(body)).encode()
                         + b"\r\n\r\n" + body)
        i = j + 4 + n
    return b"".join(out_parts), out[i:]


def unframe(out):
    msgs, i = [], 0
    while True:
        j = out.find(b"\r\n\r\n", i)
        if j < 0:
            break
        hdr = out[i:j].decode("utf-8", "replace")
        cl = [l for l in hdr.split("\r\n") if l.lower().startswith("content-length")]
        if not cl:
            break
        n = int(cl[0].split(":")[1])
        msgs.append(json.loads(out[j + 4:j + 4 + n]))
        i = j + 4 + n
    return msgs, out[i:]


def utf16_units(line_text, nchars):
    """UTF-16 code units occupied by the first `nchars` CHARACTERS of a
    line. This is the conversion the gate exists to check: stage0
    reports 1-based CHARACTER columns (its lexer walks a Vec<char>),
    LSP wants 0-based UTF-16 code units, and the two differ exactly
    where a character sits outside the BMP and needs a surrogate pair.
    Deriving the expected column here - from stage0's own column plus
    the fixture's bytes - is what stops the golden half of this gate
    from being self-satisfying."""
    return sum(2 if ord(c) > 0xFFFF else 1 for c in line_text[:nchars])


def stage0_diags(path):
    """(code, 0-based line) pairs stage0 reports, and whether it parsed.

    AXDL is `<SEV>[ CODE] file:line:col ...`; the renderer's own grammar
    is documented in self_host/diag.ax. Only ERROR lines are compared -
    the server publishes warnings too, but stage0's exit status treats
    them differently and the set comparison below is about errors."""
    p = subprocess.run([stage0, "check", "--diagnostic-format", "ai", path],
                       capture_output=True)
    srclines = open(path, encoding="utf-8").read().split("\n")
    pairs, parsed = set(), True
    for line in p.stderr.decode("utf-8", "replace").splitlines():
        # `<SEV> <CODE> <file>:<loc>` where loc is `line:col...` for a
        # positioned diagnostic and a bare `-` for a spanless one.
        # AX5001 is the spanless case, and the server reports it at the
        # top of the file, so `-` maps to line 0.
        m = re.match(r"^([EW])\s+(AX\d+)\s+\S*?:(\d+):(\d+)", line)
        ms = re.match(r"^([EW])\s+(AX\d+)\s+\S*?:-\s", line)
        if m:
            code, sev = m.group(2), m.group(1)
            ln = int(m.group(3)) - 1
            col = utf16_units(srclines[ln] if ln < len(srclines) else "",
                              int(m.group(4)) - 1)
        elif ms:
            code, sev, ln, col = ms.group(2), ms.group(1), 0, 0
        else:
            continue
        if code.startswith("AX1") or code.startswith("AX2"):
            parsed = False
        pairs.add((sev, code, ln, col))
    # A parse failure can also present as a bare `parse failed`-shaped
    # line with no AXDL at all; treat any non-zero exit with no AXDL
    # error lines as unparsed rather than as "clean".
    if p.returncode != 0 and not pairs:
        parsed = False
    return pairs, parsed, p.returncode


# `.axbad` is a fixture that deliberately does NOT parse. It cannot be
# called `.ax`: check-fmt.sh and check-tree-sitter.sh both sweep every
# `*.ax` file in the repository and require all of them to parse, and
# they are right to - a file that the grammar cannot read is not Axiom
# source. Every other deliberately-broken fixture in tests/ is broken
# SEMANTICALLY and parses fine, so this is the first of its kind.
fixtures = sorted(f for f in os.listdir(fixdir)
                  if f.endswith(".ax") or f.endswith(".axbad"))
if filt:
    fixtures = [f for f in fixtures if filt in f]

passed = failed = 0
for fx in fixtures:
    path = os.path.join(fixdir, fx)
    text = open(path, encoding="utf-8").read()
    name = fx[:-6] if fx.endswith(".axbad") else fx[:-3]
    golden_path = os.path.join(fixdir, name + ".golden")

    # The server resolves imports relative to the document's own
    # directory, so the URI must be the fixture's real path; it is
    # normalised out of the golden afterwards.
    real_uri = "file://" + os.path.abspath(path)
    p = subprocess.run([stage1, "lsp"], input=session(real_uri, text),
                       capture_output=True, cwd=fixdir)

    if p.returncode != 0:
        print(f"FAIL {name}: server exited {p.returncode}")
        print("     stderr:", p.stderr.decode()[:300])
        failed += 1
        continue
    if p.stderr:
        print(f"FAIL {name}: stderr not empty: {p.stderr[:200]!r}")
        failed += 1
        continue

    msgs, tail = unframe(p.stdout)
    if tail:
        print(f"FAIL {name}: {len(tail)} unframed trailing bytes on stdout")
        failed += 1
        continue

    normalised, _ = canonicalise(p.stdout, real_uri)

    if bless:
        open(golden_path, "wb").write(normalised)
        print(f"blessed {name}")
        passed += 1
        continue

    if not os.path.exists(golden_path):
        print(f"FAIL {name}: no golden at {golden_path}")
        failed += 1
        continue

    want = open(golden_path, "rb").read()
    if normalised != want:
        print(f"FAIL {name}: framed output differs from golden")
        gm, _ = unframe(want)
        for a, b in zip(msgs, gm):
            if a != b:
                print("     got: ", json.dumps(a, ensure_ascii=False)[:200])
                print("     want:", json.dumps(b, ensure_ascii=False)[:200])
                break
        if len(msgs) != len(gm):
            print(f"     message count: got {len(msgs)}, want {len(gm)}")
        failed += 1
        continue

    # --- the half a bless cannot satisfy -------------------------------
    pubs = [m for m in msgs if m.get("method") == "textDocument/publishDiagnostics"]
    if not pubs:
        print(f"FAIL {name}: server published no diagnostics notification at all")
        failed += 1
        continue
    # Warnings are compared as well as errors: a fixture whose only
    # output is a warning would otherwise assert nothing at all, which
    # is how a gate ends up passing with the feature removed.
    got = {("E" if d.get("severity") == 1 else "W",
            d["code"],
            d["range"]["start"]["line"],
            d["range"]["start"]["character"])
           for d in pubs[0]["params"]["diagnostics"]}

    want_pairs, parsed, rc0 = stage0_diags(path)

    if not parsed:
        # Known divergence, recorded above: both sides must merely agree
        # that the file is bad.
        if not got:
            print(f"FAIL {name}: stage0 rejects this file and the server reported nothing")
            failed += 1
            continue
        print(f"ok   {name} (unparseable; both sides report, codes not compared)")
        passed += 1
        continue

    if got != want_pairs:
        print(f"FAIL {name}: diagnostics disagree with stage0")
        print(f"     server: {sorted(got)}")
        print(f"     stage0: {sorted(want_pairs)}")
        failed += 1
        continue

    ne = len([g for g in got if g[0] == "E"])
    nw = len(got) - ne
    print(f"ok   {name} ({ne} error(s), {nw} warning(s), agrees with stage0)")
    passed += 1

# ---------------------------------------------------------------------
# A document larger than the reader's buffer, sent as the SECOND
# message.
#
# This is a regression, not a feature test. `Rpc.ax` shipped for one
# commit holding ABSOLUTE buffer offsets across a fill that may
# compact, so any message which did not fit in the free space was
# mis-sliced - and the symptom was a message silently DROPPED, read by
# the server as the client hanging up. Every fixture above is a few
# hundred bytes, so none of them could see it; `self_host/codegen.ax`
# is about 150 KB, so an editor opening the compiler's own source
# would have.
#
# It has to be the second message, because compaction only shifts when
# `consumed` is non-zero. And a request is sent AFTER it, because the
# failure to catch is losing stream sync, not mangling one body.
N = 6000
big_lines = []
for i in range(N):
    big_lines.append(f"(:: f{i} Int)")
    big_lines.append(f"(fn (f{i}) 0)")
big_lines.append("(:: main Int)")
big_lines.append("(fn (main) nosuchname)")
BIG = "\n".join(big_lines) + "\n"
BIG_ERR_LINE = 2 * N + 1
big_uri = "file://" + os.path.join(os.path.abspath(fixdir), "big-generated.ax")

big_session = b"".join(frame(m) for m in [
    {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {}},
    {"jsonrpc": "2.0", "method": "textDocument/didOpen",
     "params": {"textDocument": {"uri": big_uri, "languageId": "axiom",
                                 "version": 1, "text": BIG}}},
    {"jsonrpc": "2.0", "id": 2, "method": "textDocument/documentSymbol",
     "params": {"textDocument": {"uri": big_uri}}},
    {"jsonrpc": "2.0", "id": 3, "method": "shutdown", "params": None},
    {"jsonrpc": "2.0", "method": "exit", "params": None},
])

bp = subprocess.run([stage1, "lsp"], input=big_session, capture_output=True,
                    cwd=fixdir)
bmsgs, btail = unframe(bp.stdout)
bpubs = [m for m in bmsgs if m.get("method") == "textDocument/publishDiagnostics"]
bresp = {m["id"]: m for m in bmsgs if "id" in m}
why = None
if bp.returncode != 0:
    why = f"server exited {bp.returncode}"
elif bp.stderr:
    why = f"stderr not empty: {bp.stderr[:120]!r}"
elif btail:
    why = f"{len(btail)} unframed trailing bytes"
elif len(bpubs) != 1:
    why = f"expected 1 publishDiagnostics, got {len(bpubs)}"
elif [(d["code"], d["range"]["start"]["line"])
      for d in bpubs[0]["params"]["diagnostics"]] != [("AX3001", BIG_ERR_LINE)]:
    why = ("body did not arrive intact: "
           f"{[(d['code'], d['range']['start']['line']) for d in bpubs[0]['params']['diagnostics']]}"
           f" (want [('AX3001', {BIG_ERR_LINE})])")
elif 2 not in bresp or not isinstance(bresp[2].get("result"), list):
    why = "stream lost sync: the request after the large document was not answered"
elif len(bresp[2]["result"]) != N + 1:
    why = f"outline over the large document has {len(bresp[2]['result'])} symbols, want {N + 1}"

if why:
    print(f"FAIL large-document ({len(BIG):,} bytes): {why}")
    failed += 1
else:
    print(f"ok   large-document ({len(BIG):,} bytes, "
          f"{N + 1} symbols, error found on line {BIG_ERR_LINE})")
    passed += 1

print(f"\nlsp: {passed} passed, {failed} failed, "
      f"{len(fixtures)} fixtures + 1 generated")
sys.exit(1 if failed else 0)
